#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# Reset Hookscript Installer
#
# Purpose: Copy hookscripts/reset-method.sh to /var/lib/vz/snippets/ and
#          attach it to a VM via `qm set`.
# Usage:   sudo ./install-reset-hook.sh <vmid> <BDF> [RESET_METHOD]
#          e.g. sudo ./install-reset-hook.sh 102 0000:03:00.0 bus
#
# This script:
#   1. Copies hookscripts/reset-method.sh to /var/lib/vz/snippets/
#   2. Patches the target BDF and RESET_METHOD into the copy
#   3. Makes it executable
#   4. Attaches it to the VM with `qm set <vmid> --hookscript ...`
#
# Exit codes:
#   0 - Hookscript installed and attached
#   1 - Error (missing args, not root, qm failure, etc.)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIR
readonly SOURCE_HOOK="$SCRIPT_DIR/../hookscripts/reset-method.sh"
readonly SNIPPETS_DIR="/var/lib/vz/snippets"
readonly VALID_METHODS=("flr" "bus" "pm" "device_specific")

usage() {
    cat <<'EOF'
Usage:
  install-reset-hook.sh <vmid> <BDF> [RESET_METHOD]

Arguments:
  vmid          Proxmox VM ID, e.g. 102
  BDF           PCI device, e.g. 0000:03:00.0
  RESET_METHOD  Optional; one of: flr, bus, pm, device_specific (default: bus)

Example:
  sudo ./install-reset-hook.sh 102 0000:03:00.0 bus
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (writes to $SNIPPETS_DIR and calls qm set)" >&2
    exit 1
fi

vmid="$1"
bdf="$2"
reset_method="${3:-bus}"

# Validate vmid
if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
    echo "ERROR: vmid must be numeric: $vmid" >&2
    exit 1
fi

# Normalize BDF
if [[ ! "$bdf" =~ ^[0-9a-fA-F]{4}: ]]; then
    bdf="0000:$bdf"
fi
if [[ ! "$bdf" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9]$ ]]; then
    echo "ERROR: bad BDF format: $bdf (expected 0000:03:00.0)" >&2
    exit 1
fi

# Validate reset_method
valid=0
for m in "${VALID_METHODS[@]}"; do
    [[ "$m" == "$reset_method" ]] && valid=1
done
if (( !valid )); then
    echo "ERROR: unknown reset_method '$reset_method'. Valid: ${VALID_METHODS[*]}" >&2
    exit 1
fi

# Check source hookscript exists
if [[ ! -f "$SOURCE_HOOK" ]]; then
    echo "ERROR: source hookscript not found: $SOURCE_HOOK" >&2
    exit 1
fi

# Check snippets dir exists (Proxmox standard path)
if [[ ! -d "$SNIPPETS_DIR" ]]; then
    echo "ERROR: $SNIPPETS_DIR not found. Is this a Proxmox host?" >&2
    exit 1
fi

# Check `qm` exists
if ! command -v qm >/dev/null 2>&1; then
    echo "ERROR: 'qm' not in PATH. Is this a Proxmox host?" >&2
    exit 1
fi

# Check VM config exists
if ! qm config "$vmid" >/dev/null 2>&1; then
    echo "ERROR: VM $vmid not found (qm config failed)" >&2
    exit 1
fi

dest="$SNIPPETS_DIR/reset-method.sh"
echo "Installing hookscript:"
echo "  Source : $SOURCE_HOOK"
echo "  Dest   : $dest"
echo "  VM     : $vmid"
echo "  BDF    : $bdf"
echo "  Method : $reset_method"

# Copy + patch config lines
# Replace the BDF=... and RESET_METHOD=... defaults
sed -e "s|^readonly BDF=\".*\"$|readonly BDF=\"\${BDF:-$bdf}\"|" \
    -e "s|^readonly RESET_METHOD=\".*\"$|readonly RESET_METHOD=\"\${RESET_METHOD:-$reset_method}\"|" \
    "$SOURCE_HOOK" > "$dest"

chmod +x "$dest"
echo "Hookscript installed at $dest"

# Attach to VM
echo "Attaching to VM $vmid..."
qm set "$vmid" --hookscript "local:snippets/reset-method.sh"
echo ""
echo "Done. Verify with:"
echo "  qm config $vmid | grep hookscript"
echo ""
echo "To uninstall:"
echo "  qm set $vmid --delete hookscript"
echo "  rm $dest"
