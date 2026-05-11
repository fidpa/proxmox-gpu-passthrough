# Proxmox GPU Passthrough

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Status](https://img.shields.io/badge/status-wip-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Proxmox%20VE%209.x-orange?logo=proxmox)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnu-bash)
![GPUs](https://img.shields.io/badge/GPUs-Intel%20Arc%20%7C%20NVIDIA-blueviolet)

Battle-tested PCIe passthrough recipes for Proxmox VE — with focus on **the failure modes the official wiki doesn't cover**: CPUID-level driver anti-VM checks, IOMMU group isolation, vendor-specific init quirks, and BAR/ReBAR edge cases.

**The Problem**: Most GPU passthrough guides stop at "add `hostpci0` and reboot". In practice you hit Error 43 (Intel Arc, NVIDIA Consumer pre-465.89), the AMD Reset Bug, `iigd_dch_d.inf` vs `iigd_dch.inf` confusion, Windows falling back to Microsoft Basic Display Adapter, and silent BAR resize failures. Each has a different root cause at the CPUID / WDDM / PCIe-config-space layer. This repo documents the fixes that actually work, with scripts that automate the reproducible steps.

## Supported GPUs

| GPU | Vendor | Status | Proven On |
|-----|--------|--------|-----------|
| **Intel Arc A310 (DG2)** | Intel | 🚧 In validation (promotes to ✅ on 2026-05-04) | Proxmox VE 9.1, kernel 6.17.x, Windows 11 Pro 25H2 — initial config verified 2026-04-20 |
| **NVIDIA RTX 2000 Ada** | NVIDIA Professional (Ada) | 🚧 In validation | Proxmox VE 9.1.1, kernel 6.17.2-1-pve, Ubuntu 24.04 guest — initial config verified 2026-05-11 |
| **NVIDIA RTX PRO 4500 Blackwell (32 GB)** | NVIDIA Professional (Blackwell) | 🚧 Planned | — |
| **AMD (Polaris/Navi)** | AMD | 📋 Backlog (Reset Bug Research) | — |

> **NVIDIA Consumer (GeForce RTX 40 / 50-series)** intentionally not in the planned set. Consumer-tier passthrough is already represented by the **Intel Arc A310** entry above — it shows the harder failure modes (Code-43, CPUID hiding, INF gotcha) on a Consumer-class card. A separate NVIDIA-Consumer recipe is welcome from contributors with real ≥2-week production passthrough on Ada / Blackwell GeForce hardware — see [docs/vendors/nvidia-consumer.md](docs/vendors/nvidia-consumer.md).

> **Scope discipline**: Every "Production" entry in this table has been running for ≥2 weeks in a real workload (not just `dxdiag`). "In validation" entries have a working first-boot config but haven't cleared the two-week threshold yet. Entries promote to ✅ **only** after that threshold — including my own.

## Roadmap

- **NVIDIA RTX 2000 Ada (Professional, Ada-Generation)** — full recipe once the card runs ML-inference workload ≥2 weeks. Anticipated flag-set: minimal (no hypervisor-hiding — Pro cards expect KVM visible). Ada-generation reference point for the Pro lineage.
- **NVIDIA RTX PRO 4500 Blackwell (Professional, Blackwell-Generation, 32 GB GDDR7)** — second Pro card, planned for the same workstation alongside the RTX 2000 Ada. Recipe focus: ReBAR negotiation on a full 32 GB BAR, PCIe 5.0 link training, ECC + NVENC behaviour on the RTX Enterprise driver branch. Same `nvidia-pro` profile as RTX 2000 Ada (no hypervisor-hiding) but Blackwell silicon brings Consumer-Blackwell-style PCIe quirks.
- **AMD (Polaris / Navi / RDNA)** — backlog; contingent on test hardware access and on `vendor-reset` kernel module compatibility with current kernels.

## Features

- **Vendor-Aware CPU-Args Generator** — produces correct `-cpu` line for Intel Arc (hypervisor-hiding), NVIDIA Consumer (Code-43-bypass), NVIDIA Pro (no hiding needed), AMD
- **IOMMU Group Analyzer** — shows groupings, flags ACS-split candidates, identifies companion devices (audio, USB-C controller on Arc, NVLink on NVIDIA)
- **VFIO Binding Verifier** — confirms `i915` / `nouveau` / `amdgpu` are **not** bound to the passthrough device before VM start
- **Reset-Method Hookscript** — clears `/sys/bus/pci/devices/<BDF>/reset_method` for GPUs where Proxmox's default reset sequence fails (`Inappropriate ioctl for device`)
- **Capability Probe (Post-Install)** — Windows PowerShell script that verifies DirectX Feature Level, Vulkan API, Video en/decode, VRAM via `dxdiag` (not WMI — WMI caps at 2 GB)
- **Troubleshooting Matrix** — symptom → vendor → root cause → fix (CPUID / PCIe / WDDM / driver-specific)

## Quick Start

```bash
# 1. Host preparation (one-time, requires reboot).
#    Default is dry-run; --apply writes the kernel cmdline + refreshes the bootloader.
sudo ./scripts/enable-iommu.sh --apply

# 2. Identify your GPU and its IOMMU group
./scripts/check-iommu-groups.sh
# Example output:
#   Group 16: 03:00.0 Intel Corporation DG2 [Arc A310] [8086:56a6]
#   Group 17: 04:00.0 Intel Corporation DG2 Audio [8086:4f92]

# 3. Bind GPU + companion to vfio-pci (one BDF per call — do one thing well)
sudo ./scripts/bind-vfio.sh 03:00.0
sudo ./scripts/bind-vfio.sh 04:00.0
# Verify each (should show "vfio-pci")
./scripts/check-vfio-binding.sh 03:00.0
./scripts/check-vfio-binding.sh 04:00.0

# 4. Generate vendor-specific QEMU args
./scripts/generate-vm-args.sh --vendor intel-arc
# Outputs (raw): -cpu host,kvm=off,hv_vendor_id=GenuineIntel,-hypervisor,...

# 5. Apply to VM (idiomatic Proxmox flow: atomic, auditable, hot-applicable)
qm set 102 --hostpci0 '0000:03:00,pcie=1' \
           --hostpci1 '0000:04:00,pcie=1' \
           --vga none --balloon 0 \
           --args "$(./scripts/generate-vm-args.sh --vendor intel-arc)"

# 6. Start VM, install driver, then verify
qm start 102
# Inside Windows: PowerShell as Admin
powershell.exe -File capability-probe.ps1
```

> **Single host vs. cluster**: The Quick Start above uses physical BDFs (`0000:03:00`). That's fine on a standalone Proxmox host, but breaks in a cluster where the same card has a different BDF on each node. For clusters with HA or migration, use **Resource Mappings** (Proxmox VE 8+) — see [docs/RESOURCE_MAPPINGS.md](docs/RESOURCE_MAPPINGS.md).

## Documentation

| Doc | Scope |
|-----|-------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Why passthrough fails — CPUID, IOMMU, BAR, Reset-Bug overview |
| [docs/HOST_SETUP.md](docs/HOST_SETUP.md) | One-time Proxmox host preparation (IOMMU, VFIO, module blacklists) |
| [docs/VM_CONFIG.md](docs/VM_CONFIG.md) | `q35`, OVMF, `balloon: 0`, `vga: none`, `cpu: host`, hookscripts |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptom-driven matrix — Code 43, MBDA fallback, reset failures |
| [docs/RESOURCE_MAPPINGS.md](docs/RESOURCE_MAPPINGS.md) | Cluster-aware passthrough via logical mapping names (Proxmox VE 8+); required for HA with passthrough |
| [docs/vendors/intel-arc-dg2.md](docs/vendors/intel-arc-dg2.md) | 🚧 Intel Arc A310 full recipe (Code-43-fix, INF gotcha) — in 2-week validation |
| [docs/vendors/nvidia-professional.md](docs/vendors/nvidia-professional.md) | 🚧 RTX 2000 Ada + RTX PRO 4500 Blackwell — planned (two Pro cards, same workstation) |
| [docs/vendors/amd.md](docs/vendors/amd.md) | 📋 Reset Bug + `vendor-reset` kernel module — backlog |

> The Consumer-tier perspective is covered by the **Intel Arc A310** entry. A NVIDIA-GeForce-specific stub for contributors lives at [docs/vendors/nvidia-consumer.md](docs/vendors/nvidia-consumer.md).

## The One Thing Most Guides Miss

For **Intel Arc**: `kvm=off` alone is not enough. The Windows driver checks CPUID leaf `0x1` ECX bit 31 (Hypervisor-Running flag) independently of the KVM signature in leaf `0x40000000`. You need **both** `kvm=off` **and** `-hypervisor` to pass the WDDM interface negotiation. See [docs/vendors/intel-arc-dg2.md § Code-43-Fix](docs/vendors/intel-arc-dg2.md#code-43-fix) for the full CPUID mechanics.

## Prerequisites

- Proxmox VE 8.x or 9.x (tested: 9.1 with kernel 6.17.x)
- CPU with IOMMU support (Intel VT-d / AMD-Vi)
- BIOS: IOMMU enabled, "Above 4G Decoding" enabled, Resizable BAR enabled (recommended)
- Guest: Windows 10/11, Linux (any modern distro). Examples are Windows-heavy because that's where the driver quirks bite hardest.

## Contributing

New vendor recipes welcome. Prerequisite: reproducible setup running ≥2 weeks (not just first-boot). See [CONTRIBUTING.md](CONTRIBUTING.md).

## Provenance

Honesty about what's battle-tested and what's codified:

- **Bash scripts in `scripts/`** codify standard VFIO + Proxmox-documentation patterns. They are **not** extracted from the ad-hoc production session that validated the Intel Arc recipe. On the actual host the initial binding was done with one-liners (`echo "0000:03:00.0" > /sys/bus/pci/drivers/vfio-pci/bind` etc.); the scripts exist to make that flow reproducible across setups.
- **`scripts/capability-probe.ps1`** is a clean-room re-composition of three forensic PowerShell scripts used during the 2026-04-20 validation session (`probe.ps1`, `verify.ps1`, `dxgi_vram.ps1`). Those forensic scripts don't ship with the repo; the relevant logic was extracted and generalized.
- **The Intel Arc recipe text** ([docs/vendors/intel-arc-dg2.md](docs/vendors/intel-arc-dg2.md)) — symptoms, fix sequence, DxgKrnl event IDs, dead-end attempts — is the direct output of that session. First-hand observations, not a literature review.

In short: the **recipe is battle-tested**, the **wrapper scripts are standards-based**. Both together are what makes this repo useful; neither is the other.

## See Also

- [ubuntu-server-security](https://github.com/fidpa/ubuntu-server-security) — Ubuntu hardening (14 components, CIS Benchmark)
- [step-ca-internal-pki](https://github.com/fidpa/step-ca-internal-pki) — Internal PKI for homelab services
- [bash-production-toolkit](https://github.com/fidpa/bash-production-toolkit) — Production-ready Bash libraries used across fidpa repos

## License

MIT — see [LICENSE](LICENSE).

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))

**Why I Built This**: Running a Windows 11 VM with a passed-through Intel Arc A310 on Proxmox 9.1 took a full day of debugging despite dozens of guides online — every single one stopped short of the CPUID / WDDM-interface corner cases that actually trip the driver. Once the recipe worked I extracted the reproducible parts (scripts, config skeletons, symptom matrix) so the next person (including future me) doesn't lose the day to Error 43 again.
