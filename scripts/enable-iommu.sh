#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# IOMMU Enablement Helper
#
# Purpose: Add IOMMU kernel cmdline flags so VFIO can isolate PCI devices.
# Usage:   sudo ./enable-iommu.sh [--apply]
#          (dry-run by default; --apply writes config and refreshes bootloader)
#
# What this does:
#   Proxmox VE uses either GRUB (legacy BIOS) or systemd-boot (UEFI) as
#   managed by `proxmox-boot-tool`. This script detects which is active,
#   appends the correct IOMMU flags to the kernel cmdline, and refreshes
#   the bootloader. A reboot is required afterwards.
#
# Flags applied:
#   Intel CPU: intel_iommu=on iommu=pt
#   AMD CPU:   amd_iommu=on iommu=pt
#
#   `iommu=pt` = passthrough mode for host devices (better host performance;
#   devices handed to a VM still get isolated normally).
#
# Exit codes:
#   0 - Config updated (or already correct); reboot required
#   1 - Error (unsupported bootloader, missing permissions, etc.)
#   2 - Dry-run only (no changes made)

set -uo pipefail

readonly APPLY_FLAG="${1:-}"
DRY_RUN=1
[[ "$APPLY_FLAG" == "--apply" ]] && DRY_RUN=0

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (IOMMU changes touch /etc/kernel/cmdline or /etc/default/grub)" >&2
    exit 1
fi

# Detect CPU vendor
cpu_vendor=""
if grep -q "GenuineIntel" /proc/cpuinfo; then
    cpu_vendor="intel"
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    cpu_vendor="amd"
else
    echo "ERROR: unsupported CPU vendor (not Intel/AMD)" >&2
    exit 1
fi

echo "CPU vendor: $cpu_vendor"

iommu_flags=""
case "$cpu_vendor" in
    intel) iommu_flags="intel_iommu=on iommu=pt" ;;
    amd)   iommu_flags="amd_iommu=on iommu=pt"   ;;
esac

# Detect bootloader managed by proxmox-boot-tool
# /etc/kernel/cmdline exists on systemd-boot / proxmox-boot-tool systems
# /etc/default/grub on classic GRUB
bootloader=""
if [[ -f /etc/kernel/cmdline ]] && command -v proxmox-boot-tool >/dev/null 2>&1; then
    bootloader="proxmox-boot-tool"
elif [[ -f /etc/default/grub ]]; then
    bootloader="grub"
else
    echo "ERROR: could not detect bootloader (neither /etc/kernel/cmdline nor /etc/default/grub found)" >&2
    exit 1
fi

echo "Bootloader: $bootloader"

case "$bootloader" in
    proxmox-boot-tool)
        current="$(cat /etc/kernel/cmdline)"
        echo "Current cmdline: $current"
        missing=()
        for flag in $iommu_flags; do
            grep -qw -- "$flag" <<< "$current" || missing+=("$flag")
        done
        if [[ ${#missing[@]} -eq 0 ]]; then
            echo "IOMMU flags already present. No changes needed."
            exit 0
        fi
        echo "Missing flags: ${missing[*]}"
        if (( DRY_RUN )); then
            echo "Dry run — would append: ${missing[*]}"
            echo "Re-run with --apply to write and refresh."
            exit 2
        fi
        new_cmdline="$current ${missing[*]}"
        echo "$new_cmdline" > /etc/kernel/cmdline
        proxmox-boot-tool refresh
        ;;

    grub)
        grub_file="/etc/default/grub"
        current_line="$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file" || true)"
        echo "Current: $current_line"
        missing=()
        for flag in $iommu_flags; do
            grep -qw -- "$flag" <<< "$current_line" || missing+=("$flag")
        done
        if [[ ${#missing[@]} -eq 0 ]]; then
            echo "IOMMU flags already present. No changes needed."
            exit 0
        fi
        echo "Missing flags: ${missing[*]}"
        if (( DRY_RUN )); then
            echo "Dry run — would append to GRUB_CMDLINE_LINUX_DEFAULT: ${missing[*]}"
            echo "Re-run with --apply to write and update-grub."
            exit 2
        fi
        # Append flags inside the quoted value
        sed -i.bak -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)(\".*)|\1 ${missing[*]}\2|" "$grub_file"
        update-grub
        ;;
esac

echo ""
echo "IOMMU flags applied. REBOOT REQUIRED before passthrough will work."
echo "After reboot, verify with:"
echo "  dmesg | grep -i -e DMAR -e IOMMU"
echo "  ./scripts/check-iommu-groups.sh"
