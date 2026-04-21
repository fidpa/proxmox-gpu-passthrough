#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# Diagnostic Bundler for GPU Passthrough Issues
#
# Purpose: Collect everything a reviewer needs to debug a passthrough issue
#          into a single tarball. Auto-sanitizes IPs/hostnames where possible,
#          but you MUST review output before sharing.
# Usage:   sudo ./collect-diagnostics.sh <vmid> [-o <outfile>]
#          Default outfile: gpu-passthrough-diag-<vmid>-<timestamp>.tar.gz
#
# What gets collected:
#   - kernel cmdline, dmesg (filtered to VFIO/IOMMU/PCI)
#   - IOMMU group layout
#   - vfio-pci state, module config
#   - qm config <vmid>, qm status <vmid>
#   - lspci -vv for the passthrough device(s)
#   - proxmox version, kernel version
#
# Sanitization:
#   - Hostnames replaced with [HOSTNAME]
#   - MAC addresses partially masked
#   - NOT sanitized: serial numbers, UUIDs, file paths (review manually!)
#
# Exit codes:
#   0 - Bundle created
#   1 - Error (not root, VM missing, tar failure)

set -uo pipefail

OUTFILE=""
VMID=""

usage() {
    cat <<'EOF'
Usage: collect-diagnostics.sh <vmid> [-o <outfile>]

Example:
  sudo ./collect-diagnostics.sh 102
  sudo ./collect-diagnostics.sh 102 -o /tmp/mydiag.tar.gz
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            [[ $# -ge 2 ]] || { usage; exit 1; }
            OUTFILE="$2"
            shift 2
            ;;
        -h|--help)
            usage; exit 0
            ;;
        *)
            if [[ -z "$VMID" ]]; then
                VMID="$1"
                shift
            else
                echo "ERROR: unexpected arg: $1" >&2
                usage; exit 1
            fi
            ;;
    esac
done

if [[ -z "$VMID" ]]; then
    usage
    exit 1
fi

if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: vmid must be numeric: $VMID" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (reads /sys, /proc, /etc/pve)" >&2
    exit 1
fi

ts="$(date +%Y%m%d-%H%M%S)"
OUTFILE="${OUTFILE:-gpu-passthrough-diag-${VMID}-${ts}.tar.gz}"

workdir="$(mktemp -d -t gpu-diag-XXXXXX)"
trap 'rm -rf "$workdir"' EXIT

bundle="$workdir/bundle"
mkdir -p "$bundle"

sanitize() {
    # sanitize: replace hostname, mask MAC addresses
    local host
    host="$(hostname -s 2>/dev/null || echo localhost)"
    sed -e "s/\\b$host\\b/[HOSTNAME]/g" \
        -e 's/\([0-9a-fA-F]\{2\}:\)\{2\}[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}/XX:XX:XX:XX:XX:XX/g'
}

# ---- Host info --------------------------------------------------------------
{
    echo "=== System ==="
    uname -a
    echo ""
    echo "=== Proxmox Version ==="
    pveversion -v 2>/dev/null || echo "(pveversion not available)"
    echo ""
    echo "=== CPU ==="
    grep -m1 "model name" /proc/cpuinfo
    grep -m1 "vendor_id"  /proc/cpuinfo
    echo ""
    echo "=== Kernel Cmdline ==="
    cat /proc/cmdline
    echo ""
    echo "=== BIOS/Firmware ==="
    dmidecode -s bios-vendor 2>/dev/null || echo "(dmidecode not available)"
    dmidecode -s bios-version 2>/dev/null || true
} | sanitize > "$bundle/system.txt"

# ---- dmesg (filtered) -------------------------------------------------------
dmesg 2>/dev/null | grep -i -E "(iommu|dmar|vfio|pcieport|PCI\b)" | tail -500 | sanitize > "$bundle/dmesg-filtered.txt" || true

# ---- IOMMU groups -----------------------------------------------------------
{
    echo "=== IOMMU Groups ==="
    shopt -s nullglob
    iommu_group_dirs=( /sys/kernel/iommu_groups/*/ )
    shopt -u nullglob
    # Extract basenames and sort numerically
    for g in $(printf '%s\n' "${iommu_group_dirs[@]}" | xargs -n1 basename | sort -n); do
        echo ""
        echo "IOMMU Group $g:"
        for d in /sys/kernel/iommu_groups/"$g"/devices/*; do
            bdf="$(basename "$d")"
            info="$(lspci -nns "$bdf" 2>/dev/null)"
            drv="(unbound)"
            [[ -L "$d/driver" ]] && drv="$(basename "$(readlink -f "$d/driver")")"
            echo "  $info [driver=$drv]"
        done
    done
} > "$bundle/iommu-groups.txt"

# ---- vfio-pci state ---------------------------------------------------------
{
    echo "=== vfio-pci module ==="
    lsmod | grep -E "^vfio" || echo "(vfio modules not loaded)"
    echo ""
    echo "=== /etc/modprobe.d/vfio* ==="
    cat /etc/modprobe.d/vfio*.conf 2>/dev/null || echo "(no vfio conf found)"
    echo ""
    echo "=== /etc/modules / /etc/modules-load.d/ ==="
    cat /etc/modules 2>/dev/null
    for f in /etc/modules-load.d/*.conf; do
        [[ -f "$f" ]] && { echo "-- $f --"; cat "$f"; }
    done
    echo ""
    echo "=== vfio-pci bound devices ==="
    if [[ -d /sys/bus/pci/drivers/vfio-pci ]]; then
        for d in /sys/bus/pci/drivers/vfio-pci/0000:*; do
            [[ -L "$d" ]] || continue
            bdf="$(basename "$d")"
            lspci -nns "$bdf"
        done
    else
        echo "(vfio-pci driver not present)"
    fi
} > "$bundle/vfio.txt"

# ---- VM config --------------------------------------------------------------
{
    echo "=== qm config $VMID ==="
    qm config "$VMID" 2>&1 || echo "(qm config failed -- VM $VMID missing?)"
    echo ""
    echo "=== qm status $VMID ==="
    qm status "$VMID" 2>&1 || true
    echo ""
    echo "=== machine/QEMU version ==="
    qm config "$VMID" 2>/dev/null | grep -E "^(machine|bios|cpu|args):" || true
} | sanitize > "$bundle/vm-config.txt"

# ---- lspci -vv for all passthrough candidates ------------------------------
{
    echo "=== lspci -vv for devices mentioned in VM config ==="
    bdf_list="$(qm config "$VMID" 2>/dev/null | grep -oE "hostpci[0-9]+: [^,]+" | sed 's/hostpci[0-9]*: //' | sort -u)"
    if [[ -n "$bdf_list" ]]; then
        for bdf in $bdf_list; do
            # Normalize BDF
            [[ "$bdf" =~ ^[0-9a-fA-F]{4}: ]] || bdf="0000:$bdf"
            echo ""
            echo "-- $bdf --"
            lspci -vv -s "$bdf" 2>&1 || true
        done
    else
        echo "(no hostpci entries in VM config)"
    fi
} > "$bundle/lspci-passthrough.txt"

# ---- bundle metadata --------------------------------------------------------
{
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "VMID     : $VMID"
    echo "Tool     : proxmox-gpu-passthrough collect-diagnostics.sh"
    echo ""
    echo "Files:"
    find "$bundle" -maxdepth 1 -type f | sort | while read -r f; do
        echo "  $(basename "$f")  ($(wc -l < "$f") lines)"
    done
} > "$bundle/README.txt"

# ---- tarball ----------------------------------------------------------------
tar -czf "$OUTFILE" -C "$workdir" bundle || {
    echo "ERROR: tar failed" >&2
    exit 1
}

echo ""
echo "Bundle created: $OUTFILE"
echo "Size: $(du -h "$OUTFILE" | cut -f1)"
echo ""
echo "================================================================"
echo "  !!!  REVIEW BEFORE SHARING  !!!"
echo "================================================================"
echo "  Auto-sanitizer only masks: short hostname + MAC addresses."
echo "  It does NOT currently mask:"
echo "    - Private/public IPv4 and IPv6 addresses"
echo "    - Motherboard / disk SERIAL NUMBERS (lspci -vv, dmidecode)"
echo "    - Hardware / BIOS UUIDs"
echo "    - Usernames in file paths (/home/<user>/, /root/)"
echo "    - Full hostnames (only short form is masked)"
echo ""
echo "  Extract and review before uploading or posting anywhere:"
echo "    tar -tzf $OUTFILE              # list contents"
echo "    tar -xzf $OUTFILE -C /tmp/diag # extract, then grep carefully"
echo "================================================================"
