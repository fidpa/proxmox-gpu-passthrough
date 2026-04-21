#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# IOMMU Group Inspector
#
# Purpose: List all IOMMU groups and their PCI device members
# Usage:   ./check-iommu-groups.sh [GROUP_NUMBER]
#          (no arg = list all groups; arg = show one group in detail)
#
# Why this matters for passthrough:
#   VFIO assigns PCI devices to VMs at the IOMMU-group granularity. If a GPU
#   shares an IOMMU group with, say, a USB controller, passing through the GPU
#   also pulls the USB controller out of the host — or the passthrough fails
#   with "Could not assign device ..., error -22" because a group member is
#   still bound to a host driver.
#
# Clean passthrough requires: every device in the target group is either
#   (a) also bound to vfio-pci, or
#   (b) a PCI bridge (which doesn't need binding).
#
# Exit codes:
#   0 - Groups listed successfully
#   1 - IOMMU not enabled or no groups found

set -uo pipefail

readonly IOMMU_ROOT="/sys/kernel/iommu_groups"

if [[ ! -d "$IOMMU_ROOT" ]]; then
    echo "ERROR: $IOMMU_ROOT not found — IOMMU is not enabled." >&2
    echo "Hint: run ./scripts/enable-iommu.sh and reboot." >&2
    exit 1
fi

shopt -s nullglob
_iommu_groups=( "$IOMMU_ROOT"/*/ )
shopt -u nullglob
if [[ ${#_iommu_groups[@]} -eq 0 ]]; then
    echo "ERROR: $IOMMU_ROOT is empty — IOMMU likely not active in kernel cmdline." >&2
    exit 1
fi

print_group() {
    local group_num="$1"
    local group_dir="$IOMMU_ROOT/$group_num/devices"
    [[ -d "$group_dir" ]] || return 1

    echo "IOMMU Group $group_num:"
    for dev_path in "$group_dir"/*; do
        local bdf
        bdf="$(basename "$dev_path")"
        local info
        info="$(lspci -nns "$bdf" 2>/dev/null | sed 's/^[^ ]* //')"
        local driver="(unbound)"
        if [[ -L "$dev_path/driver" ]]; then
            driver="$(basename "$(readlink -f "$dev_path/driver")")"
        fi
        printf "  %s  [driver: %s]  %s\n" "$bdf" "$driver" "$info"
    done
    echo ""
}

if [[ $# -eq 1 ]]; then
    print_group "$1" || { echo "Group $1 not found." >&2; exit 1; }
    exit 0
fi

# List all, sorted numerically. IOMMU group dir names are numeric by kernel convention.
mapfile -t groups < <(printf '%s\n' "${_iommu_groups[@]}" | xargs -n1 basename | sort -n)
for g in "${groups[@]}"; do
    print_group "$g"
done
