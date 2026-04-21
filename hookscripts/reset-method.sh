#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# Proxmox VM Hookscript: PCI Reset Method Override
#
# Purpose: Force Proxmox to use a specific PCI reset method when a GPU's
#          default reset path is broken.
#
# Installation:
#   1. Copy this file to /var/lib/vz/snippets/reset-method.sh
#      (use scripts/install-reset-hook.sh for the guided flow)
#   2. chmod +x /var/lib/vz/snippets/reset-method.sh
#   3. qm set <vmid> --hookscript local:snippets/reset-method.sh
#
# How it works:
#   Proxmox calls hookscripts at lifecycle events: pre-start, post-start,
#   pre-stop, post-stop. At `pre-start`, we write a reset_method token into
#   /sys/bus/pci/devices/<BDF>/reset_method BEFORE the VM binds the device.
#
# Supported reset tokens (defined in kernel source drivers/pci/pci.c,
# array `pci_reset_fn_methods[]`; exposed via sysfs since Linux 5.17):
#   flr             - Function-Level Reset (preferred when the device supports it)
#   bus             - Bus reset (whole PCIe bus; can affect neighbors)
#   pm              - PCI Power Management reset (D3->D0)
#   device_specific - Vendor-specific quirk in the kernel
# Alternative: write an empty string to `reset_method` to DISABLE reset entirely
# (the kernel ABI supports this; useful for devices where every reset method hangs).
#
# Configure which BDF/method to force via environment (set at top of file or
# via /etc/default/):
#     BDF="0000:03:00.0"
#     RESET_METHOD="bus"
#
# Why this exists:
#   Some GPUs (older NVIDIA, certain AMD Polaris/Navi) report the default
#   reset method as working but actually hang the bus on reset. Forcing an
#   alternative method is the quickest fix short of installing the
#   `vendor-reset` kernel module. For AMD Reset Bug, prefer vendor-reset
#   (see docs/vendors/amd.md) over this script.
#
# Exit codes:
#   0 - Success (or non-pre-start phase, pass-through)
#   1 - Failed to write reset_method (check BDF, check kernel support)

set -uo pipefail

# -------- Configuration -------------------------------------------------------
# Override via: qm set <vmid> --hookscript local:snippets/reset-method.sh
# Edit these to match your passthrough device:
readonly BDF="${BDF:-0000:03:00.0}"
readonly RESET_METHOD="${RESET_METHOD:-bus}"
# ------------------------------------------------------------------------------

# Hookscript args from Proxmox: $1 = vmid, $2 = phase
vmid="${1:-}"
phase="${2:-}"

# Only act in pre-start; silently pass through other phases
if [[ "$phase" != "pre-start" ]]; then
    exit 0
fi

target="/sys/bus/pci/devices/$BDF/reset_method"
if [[ ! -w "$target" ]]; then
    echo "reset-method hook [VM $vmid]: $target not writable (device missing or reset_method unsupported)" >&2
    exit 1
fi

current="$(cat "$target" 2>/dev/null || echo "?")"
echo "reset-method hook [VM $vmid]: $BDF reset_method was '$current', setting to '$RESET_METHOD'"

if ! echo "$RESET_METHOD" > "$target"; then
    echo "reset-method hook [VM $vmid]: write to $target failed" >&2
    exit 1
fi

new="$(cat "$target" 2>/dev/null)"
echo "reset-method hook [VM $vmid]: reset_method now '$new'"
exit 0
