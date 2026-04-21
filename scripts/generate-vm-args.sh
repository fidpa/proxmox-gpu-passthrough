#!/bin/bash
# Copyright (c) 2026 fidpa
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/proxmox-gpu-passthrough

# QEMU args Generator for GPU Passthrough
#
# Purpose: Print the QEMU -cpu args for a given GPU vendor profile, ready to
#          feed directly into Proxmox's `qm set --args`. Each profile encodes
#          the minimum set of CPU and hypervisor flags that vendor's driver
#          needs to accept virtualization.
#
# Usage:
#   ./generate-vm-args.sh --vendor <intel-arc|nvidia-consumer|nvidia-pro|amd>
#   ./generate-vm-args.sh --vendor intel-arc                    # raw args (default)
#   ./generate-vm-args.sh --vendor intel-arc --as-config-line   # with `args: ` prefix
#   ./generate-vm-args.sh --list                                # Show all profiles
#   ./generate-vm-args.sh --explain intel-arc                   # Show WHY each flag is there
#
# Output modes:
#   Default (raw)      → "-cpu host,kvm=off,…"     suitable for `qm set --args "$(…)"`
#   --as-config-line   → "args: -cpu host,…"       suitable for /etc/pve/qemu-server/<vmid>.conf
#
# Why raw is the default:
#   `qm set <vmid> --args "$(./generate-vm-args.sh --vendor intel-arc)"` is the
#   idiomatic Proxmox flow (atomic, hot-applicable to running VMs, auditable in
#   `qm config`). Prepending `args: ` there would produce a literal `args: args: …`
#   in the config — a silent bug. The config-file paste path is secondary, and
#   Proxmox warns against editing running VMs' conf files directly.
#
# Vendors with no args needed (nvidia-consumer on driver ≥ 465.89, nvidia-pro,
# amd) print NOTHING to stdout — intentional, so
#   qm set <vmid> --args "$(./generate-vm-args.sh --vendor amd)"
# sets an empty args line (= correct). Rationale goes to stderr.
#
# Why vendor profiles:
#   A "one size fits all" args line is actively harmful:
#     - NVIDIA Pro cards need vGPU enlightenments visible (do NOT hide KVM)
#     - Intel Arc DG2 needs BOTH kvm=off AND -hypervisor (Code 43 fix)
#     - NVIDIA Consumer driver ≥ 465.89 (April 2021) needs nothing special
#     - AMD is paravirt-tolerant; only the Reset Bug matters
#   Applying the wrong flags = unnecessary limits or broken features.
#
# Exit codes:
#   0 - Profile printed (stdout may be empty if vendor needs no custom args)
#   1 - Unknown vendor / bad args
#   2 - Profile is a placeholder (vendor not yet validated — see docs/vendors/)

set -uo pipefail

readonly VALID_VENDORS=("intel-arc" "nvidia-consumer" "nvidia-pro" "amd")

usage() {
    cat <<'EOF'
Usage:
  generate-vm-args.sh --vendor <VENDOR> [--as-config-line]
  generate-vm-args.sh --list
  generate-vm-args.sh --explain <VENDOR>

Vendors:
  intel-arc         Intel Arc DG2 (A310/A380/A750/A770)
  nvidia-consumer   NVIDIA GeForce (driver >= 465.89, April 2021+)
  nvidia-pro        NVIDIA RTX / Quadro / Tesla
  amd               AMD Radeon (Polaris/Navi/RDNA)

Flags:
  --as-config-line  Prepend `args: ` (for pasting into /etc/pve/qemu-server/<vmid>.conf).
                    Default: raw args only, for `qm set --args "$(…)"`.

Vendors without custom args (nvidia-consumer on modern driver, nvidia-pro, amd)
print nothing to stdout — rationale goes to stderr.
EOF
}

# Profiles emit RAW QEMU args (no `args: ` prefix). The prefix is added at
# output time when --as-config-line is given. No args → empty stdout, reason
# on stderr.

profile_intel_arc() {
    # Intel Arc DG2 Code 43 fix (flags match production-validated config):
    #   kvm=off              → hides KVM vendor-string in CPUID leaf 0x40000000
    #   -hypervisor          → clears CPUID leaf 0x1 ECX bit 31 (Intel driver checks this independently!)
    #   hv_vendor_id         → gives Hyper-V enlightenments a plausible vendor ID
    #   +kvm_pv_unhalt       → paravirt spinlock scheduling (performance)
    #   +invtsc              → invariant TSC exposed to guest (stable timing)
    #   hv_relaxed           → relax hypervisor timer checks
    #   hv_spinlocks=0x1fff  → avoid WDDM interface mismatch (DxgKrnl Event 549 STATUS_UNSUCCESSFUL)
    echo '-cpu host,kvm=off,hv_vendor_id=GenuineIntel,-hypervisor,+kvm_pv_unhalt,+invtsc,hv_relaxed,hv_spinlocks=0x1fff'
}

profile_nvidia_consumer() {
    # NVIDIA Consumer (GeForce) since driver 465.89 (April 2021):
    # No Code 43 workaround needed. Vanilla `cpu: host` in the VM config is
    # sufficient — no custom args line. Print empty stdout + explanation to
    # stderr so `qm set --args "$(…)"` sets an empty (= correct) args line.
    {
        echo "NVIDIA Consumer (driver >= 465.89, April 2021):"
        echo "  No custom args needed — set 'cpu: host' in the VM config."
        echo "  For pre-465.89 drivers only, the legacy workaround is:"
        echo "    -cpu host,kvm=off,hv_vendor_id=GenuineIntel"
        echo "  Prefer upgrading the driver."
    } >&2
}

profile_nvidia_pro() {
    # NVIDIA Pro / RTX Enterprise / Quadro: cards are designed for
    # virtualization. Hiding the hypervisor would disable vGPU features and
    # performance counters. Emit nothing to stdout.
    {
        echo "NVIDIA Pro (RTX / Quadro / Tesla):"
        echo "  No custom args — these cards expect to see KVM."
        echo "  Set 'cpu: host' in the VM config; do NOT add kvm=off / -hypervisor."
    } >&2
}

profile_amd() {
    # AMD is paravirt-tolerant — no Code-43-style lockout. The real issue is
    # the Reset Bug, fixed at the host layer (vendor-reset kernel module).
    {
        echo "AMD Radeon (Polaris/Navi/RDNA):"
        echo "  No custom args — drivers accept virtualization."
        echo "  The common issue is the Reset Bug — fix at host layer:"
        echo "    https://github.com/gnif/vendor-reset"
        echo "  NOTE: vendor-reset v0.1.0 (Jan 2021); verify build/load on your kernel."
    } >&2
}

explain() {
    local vendor="$1"
    case "$vendor" in
        intel-arc)
            cat <<'EOF'
INTEL ARC DG2 — Flag Explanation

  -cpu host                       Expose full host CPU model (standard for any passthrough).
  kvm=off                         Hide "KVMKVMKVM\0\0\0" vendor string in CPUID leaf 0x40000000.
                                  → Driver sees no KVM signature.
  -hypervisor                     Clear CPUID leaf 0x1 ECX bit 31 (Hypervisor-Running flag).
                                  → CRITICAL: Intel Arc driver checks this bit independently
                                    of the KVM vendor-string. Without this flag, the driver
                                    knows it is running under a hypervisor and refuses to
                                    initialize (Code 43).
  hv_vendor_id=GenuineIntel       Give Hyper-V enlightenments a non-Microsoft vendor ID so
                                  the Intel driver does not treat Hyper-V mode as foreign.
  hv_relaxed                      Relax Hyper-V timer strictness. Helps WDDM timing.
  hv_spinlocks=0x1fff             Enable Hyper-V spinlock enlightenment (required for the
                                  WDDM interface to return correctly — fixes DxgKrnl
                                  Event 549 "STATUS_UNSUCCESSFUL").

Why "kvm=off" ALONE is not enough:
  kvm=off hides the KVM vendor-string, but leaf 0x1 ECX bit 31 stays set.
  The Intel Arc driver cross-checks bit 31 → "hypervisor still visible" → Code 43.
  You need BOTH kvm=off AND -hypervisor.
EOF
            ;;
        nvidia-consumer)
            cat <<'EOF'
NVIDIA CONSUMER (GeForce) — Flag Explanation

  Since driver 465.89 (April 2021), NVIDIA officially supports Consumer cards
  in VMs via the "GeForce GPU Passthrough for Windows VM (Beta)" release.
  The historical Code-43 block is gone. Do NOT apply `kvm=off` or
  `-hypervisor` on a recent driver:
    - It does not help (driver no longer checks).
    - It can confuse other tools (nvidia-smi virtualization detection).

  For driver < 465.89 (not recommended), the old workaround still works:
    args: -cpu host,kvm=off,hv_vendor_id=GenuineIntel

  Upgrade the driver instead of applying workarounds.
  See: https://nvidia.custhelp.com/app/answers/detail/a_id/5173/
EOF
            ;;
        nvidia-pro)
            cat <<'EOF'
NVIDIA PRO (RTX / Quadro / Tesla) — Flag Explanation

  Pro cards are explicitly marketed for virtualization. They EXPECT to see the
  hypervisor. Applying `kvm=off` / `-hypervisor` is actively counterproductive:

  - vGPU stack needs KVM signature to enter virtualization mode.
  - Performance counters check hypervisor presence to select paravirt counters.
  - NVIDIA enterprise driver emits "unexpected CPU state" warnings when the
    hypervisor is hidden.

  Use a clean `cpu: host` in the VM config and nothing else. Only add specific
  flags if a concrete failure mode demands them.
EOF
            ;;
        amd)
            cat <<'EOF'
AMD (Radeon Polaris / Navi / RDNA) — Flag Explanation

  AMD GPU drivers are paravirt-tolerant. They do not check CPUID for hypervisor
  presence the way Intel Arc does, and they do not have a Code-43 block the way
  old NVIDIA Consumer drivers did.

  The single biggest AMD passthrough issue is the RESET BUG: after a VM that
  owns the GPU shuts down, the GPU is left in an unrecoverable state. The second
  VM start then fails until the host itself reboots.

  Fix is at the HOST layer, not in `args:`:
    https://github.com/gnif/vendor-reset

  NOTE: vendor-reset's last release (v0.1.0) was January 2021 and known issues
  exist starting at kernel 5.15 — verify build/load on your kernel first.

  Install vendor-reset, blacklist amdgpu for the passthrough device, and use
  standard VFIO binding. No QEMU CPU-hiding flags needed.
EOF
            ;;
        *)
            echo "Unknown vendor: $vendor" >&2
            echo "Valid: ${VALID_VENDORS[*]}" >&2
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

vendor=""
as_config_line=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            echo "Available profiles:"
            for v in "${VALID_VENDORS[@]}"; do
                echo "  - $v"
            done
            exit 0
            ;;
        --explain)
            [[ $# -ge 2 ]] || { usage; exit 1; }
            explain "$2"
            exit $?
            ;;
        --vendor)
            [[ $# -ge 2 ]] || { usage; exit 1; }
            vendor="$2"
            shift 2
            continue
            ;;
        --as-config-line)
            as_config_line=1
            shift
            continue
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$vendor" ]]; then
    usage
    exit 1
fi

case "$vendor" in
    intel-arc)        raw_args="$(profile_intel_arc)" ;;
    nvidia-consumer)  raw_args="$(profile_nvidia_consumer)" ;;
    nvidia-pro)       raw_args="$(profile_nvidia_pro)" ;;
    amd)              raw_args="$(profile_amd)" ;;
    *)
        echo "Unknown vendor: $vendor" >&2
        echo "Valid: ${VALID_VENDORS[*]}" >&2
        exit 1
        ;;
esac

# Emit output. Empty raw_args → empty stdout (profile sent rationale to stderr).
if [[ -n "$raw_args" ]]; then
    if (( as_config_line )); then
        echo "args: $raw_args"
    else
        echo "$raw_args"
    fi
fi
