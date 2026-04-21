#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# VFIO Runtime Rebinder
#
# Purpose: Unbind a PCI device from its host driver and rebind to vfio-pci
#          at runtime. Useful for first-time setup or after a module reload.
# Usage:   sudo ./bind-vfio.sh <BDF>
#          e.g. sudo ./bind-vfio.sh 0000:03:00.0
#
# Why not just "reboot and load vfio-pci first"?
#   That approach (vfio-pci softdep in /etc/modprobe.d/) is the PERMANENT
#   solution and IS recommended for production. This script is for:
#     - Testing the binding before committing to /etc/modprobe.d/
#     - Recovering from a stale binding
#     - Passing a device to vfio-pci without a reboot
#
# For permanent binding, add to /etc/modprobe.d/vfio.conf:
#   options vfio-pci ids=VENDOR:DEVICE[,VENDOR:DEVICE...]
#   softdep i915 pre: vfio-pci          # (Intel)
#   softdep nvidia pre: vfio-pci        # (NVIDIA)
#   softdep amdgpu pre: vfio-pci        # (AMD)
# and run:  update-initramfs -u
#
# Exit codes:
#   0 - Device successfully bound to vfio-pci
#   1 - Error (device not found, bind failed, etc.)

set -uo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <BDF>  (e.g. 0000:03:00.0)" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (writes to /sys/bus/pci/drivers/*/unbind)" >&2
    exit 1
fi

bdf="$1"
# Normalize domain prefix
if [[ ! "$bdf" =~ ^[0-9a-fA-F]{4}: ]]; then
    bdf="0000:$bdf"
fi

dev_path="/sys/bus/pci/devices/$bdf"
if [[ ! -d "$dev_path" ]]; then
    echo "ERROR: device $bdf not found" >&2
    exit 1
fi

# Read vendor:device IDs
if [[ ! -r "$dev_path/vendor" ]] || [[ ! -r "$dev_path/device" ]]; then
    echo "ERROR: cannot read vendor/device ID for $bdf" >&2
    exit 1
fi
vendor="$(sed 's/^0x//' < "$dev_path/vendor")"
device="$(sed 's/^0x//' < "$dev_path/device")"
echo "Device: $bdf  (${vendor}:${device})"
lspci -nns "$bdf" 2>/dev/null

# Ensure vfio-pci is loaded
if ! lsmod | grep -q "^vfio_pci"; then
    echo "Loading vfio-pci module..."
    modprobe vfio-pci || { echo "ERROR: modprobe vfio-pci failed" >&2; exit 1; }
fi

# Unbind from current driver if any
if [[ -L "$dev_path/driver" ]]; then
    current_driver="$(basename "$(readlink -f "$dev_path/driver")")"
    if [[ "$current_driver" == "vfio-pci" ]]; then
        echo "Already bound to vfio-pci. Nothing to do."
        exit 0
    fi
    echo "Unbinding from driver '$current_driver'..."
    echo "$bdf" > "$dev_path/driver/unbind" || {
        echo "ERROR: unbind failed. Device may be in use (e.g. framebuffer console)." >&2
        echo "Hint: blacklist the host driver and reboot, or use softdep vfio-pci." >&2
        exit 1
    }
fi

# Register this device ID with vfio-pci
echo "Registering ${vendor}:${device} with vfio-pci..."
echo "$vendor $device" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || {
    # new_id fails with EEXIST if ID already registered — that's fine
    true
}

# Bind
echo "Binding $bdf to vfio-pci..."
echo "$bdf" > /sys/bus/pci/drivers/vfio-pci/bind || {
    echo "ERROR: bind failed" >&2
    exit 1
}

# Verify
if [[ -L "$dev_path/driver" ]] && [[ "$(basename "$(readlink -f "$dev_path/driver")")" == "vfio-pci" ]]; then
    echo "Success: $bdf now bound to vfio-pci"
    exit 0
fi

echo "ERROR: bind appeared to succeed but verification failed" >&2
exit 1
