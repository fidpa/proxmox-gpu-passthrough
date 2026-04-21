#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# Capability-Probe Launcher (runs PowerShell probe in Windows guest)
#
# Purpose: From the Proxmox host, dispatch the PowerShell capability probe
#          into a running Windows VM and capture its output.
# Usage:   ./capability-probe.sh <vmid>
#
# Requires:
#   - VM is running with the qemu-guest-agent installed and active
#   - capability-probe.ps1 reachable under hookscripts or via clipboard copy
#
# This is a convenience wrapper. If qemu-guest-agent is not set up, just copy
# the .ps1 file into the VM manually and run it there.
#
# Exit codes:
#   0 - Probe output captured
#   1 - Error (VM not running, guest-agent missing, exec failed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIR
readonly PROBE_PS1="$SCRIPT_DIR/capability-probe.ps1"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <vmid>" >&2
    exit 1
fi

vmid="$1"
if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
    echo "ERROR: vmid must be numeric: $vmid" >&2
    exit 1
fi

if ! command -v qm >/dev/null 2>&1; then
    echo "ERROR: 'qm' not found -- must run on Proxmox host." >&2
    exit 1
fi

if ! qm status "$vmid" 2>/dev/null | grep -q 'status: running'; then
    echo "ERROR: VM $vmid is not running." >&2
    exit 1
fi

if [[ ! -r "$PROBE_PS1" ]]; then
    echo "ERROR: probe script not found: $PROBE_PS1" >&2
    exit 1
fi

# Send the .ps1 via guest-file-write, then execute via guest-exec.
echo "Copying capability-probe.ps1 into VM $vmid..."
remote_path='C:\Windows\Temp\capability-probe.ps1'

# guest-file-write expects base64 content
content_b64="$(base64 -w0 "$PROBE_PS1")"
if ! qm guest cmd "$vmid" file-open -path "$remote_path" -mode "w+" >/tmp/qm-fd-$$ 2>&1; then
    cat /tmp/qm-fd-$$ >&2
    rm -f /tmp/qm-fd-$$
    echo "ERROR: qemu-guest-agent not responding (install qemu-ga in the VM?)" >&2
    exit 1
fi
# Parsing file-open output is awkward; fall back to qm guest exec + PowerShell from-file read
rm -f /tmp/qm-fd-$$

# Simpler approach: execute PowerShell inline with the script content
echo "Executing probe via qm guest exec..."
# PowerShell reading stdin is fiddly through qm; use a temp file on the guest
# by embedding the probe as a base64 blob.
tmp_runner="$(mktemp)"
trap 'rm -f "$tmp_runner"' EXIT

cat > "$tmp_runner" <<EOF
\$b64 = "$content_b64"
\$bytes = [System.Convert]::FromBase64String(\$b64)
\$out = "C:\\Windows\\Temp\\capability-probe.ps1"
[System.IO.File]::WriteAllBytes(\$out, \$bytes)
powershell.exe -ExecutionPolicy Bypass -File \$out
EOF

# Execute the runner line-by-line (qm guest exec takes the full command)
# We use the runner file because multi-line PowerShell via qm guest exec quoting is brittle.
# First: write runner into the guest
runner_b64="$(base64 -w0 "$tmp_runner")"
boot_cmd="powershell -NoProfile -Command \"\$b='$runner_b64'; [System.IO.File]::WriteAllBytes('C:\\Windows\\Temp\\probe-runner.ps1',[System.Convert]::FromBase64String(\$b))\""

qm guest exec "$vmid" -- cmd.exe /c "$boot_cmd" >/dev/null || {
    echo "ERROR: failed to upload runner via qm guest exec." >&2
    exit 1
}

# Now run it
echo "Running probe (this may take 10-30 seconds)..."
qm guest exec "$vmid" -- powershell.exe -ExecutionPolicy Bypass -File 'C:\Windows\Temp\probe-runner.ps1'
