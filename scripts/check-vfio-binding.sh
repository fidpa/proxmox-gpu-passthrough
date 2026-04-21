#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# VFIO Binding Verifier
#
# Purpose: Check whether a given PCI device (by BDF) is bound to vfio-pci
# Usage:   ./check-vfio-binding.sh <BDF>
#          e.g. ./check-vfio-binding.sh 0000:03:00.0
#          (or just 03:00.0 — leading domain is inferred)
#
# Why this matters:
#   VFIO passthrough requires the device to be bound to `vfio-pci`, not to
#   the host driver (i915, nvidia, amdgpu, etc.). If the host driver claims
#   the device first at boot, the VM start fails with "Could not assign
#   device ..., error -22". This script is a quick pre-flight check.
#
# Exit codes:
#   0 - Device bound to vfio-pci (ready for passthrough)
#   1 - Device bound to a different driver
#   2 - Device not found

set -uo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <BDF>  (e.g. 0000:03:00.0)" >&2
    exit 2
fi

bdf="$1"
# Normalize: accept "03:00.0" as well as "0000:03:00.0"
if [[ ! "$bdf" =~ ^[0-9a-fA-F]{4}: ]]; then
    bdf="0000:$bdf"
fi

dev_path="/sys/bus/pci/devices/$bdf"
if [[ ! -d "$dev_path" ]]; then
    echo "ERROR: device $bdf not found in /sys/bus/pci/devices/" >&2
    exit 2
fi

info="$(lspci -nns "$bdf" 2>/dev/null)"
echo "Device: $info"

if [[ -L "$dev_path/driver" ]]; then
    driver="$(basename "$(readlink -f "$dev_path/driver")")"
    echo "Driver: $driver"
    if [[ "$driver" == "vfio-pci" ]]; then
        echo "Status: OK — bound to vfio-pci"
        exit 0
    else
        echo "Status: NOT READY — bound to '$driver', expected 'vfio-pci'"
        echo "Hint: run ./scripts/bind-vfio.sh $bdf to rebind."
        exit 1
    fi
else
    echo "Driver: (unbound)"
    echo "Status: NOT READY — device has no driver"
    exit 1
fi
