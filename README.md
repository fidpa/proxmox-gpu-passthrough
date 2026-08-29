# Proxmox GPU Passthrough

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Status](https://img.shields.io/badge/status-wip-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Proxmox%20VE%209.x-orange?logo=proxmox)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnu-bash)
![GPUs](https://img.shields.io/badge/GPUs-Intel%20Arc%20%7C%20NVIDIA-blueviolet)

PCIe passthrough recipes for Proxmox VE, focused on the failure modes the official
wiki does not cover: CPUID-level driver anti-VM checks, IOMMU group isolation,
vendor-specific init quirks, and BAR/ReBAR edge cases.

Most guides stop at "add `hostpci0` and reboot". What comes after that is where the
day goes: Error 43 on Intel Arc and on NVIDIA Consumer before driver 465.89, the AMD
Reset Bug, `iigd_dch_d.inf` against `iigd_dch.inf`, Windows falling back to the
Microsoft Basic Display Adapter, silent BAR resize failures.

Each of those sits at a different layer, CPUID or WDDM or PCIe config space, and the
fix for one does nothing for the next. This repo writes down the fixes that worked on
real hardware and ships scripts for the reproducible steps.

## Supported GPUs

| GPU | Vendor | Status | Proven On |
|-----|--------|--------|-----------|
| **Intel Arc A310 (DG2)** | Intel | ✅ Production | Proxmox VE 9.1, kernel 6.17.x, Windows 11 Pro 25H2. Promoted 2026-05-15. |
| **NVIDIA RTX 2000 Ada** | NVIDIA Professional (Ada) | ✅ Production | Proxmox VE 9.1.1, kernel 6.17.2-1-pve, Ubuntu 24.04 guest. In production since 2026-05-11 (PaddleOCR GPU inference), promoted 2026-08-09. |
| **NVIDIA RTX PRO 4500 Blackwell (32 GB)** | NVIDIA Professional (Blackwell) | ✅ Production | Proxmox VE 9.1.1, kernel 6.17.2-1-pve, Ubuntu 24.04 guest. In production since 2026-05-15 (Ollama VLM inference), promoted 2026-08-09. |
| **AMD (Polaris/Navi)** | AMD | 📋 Backlog (Reset Bug research) | Not tested. |

> **How an entry becomes "Production"**: it ran >=2 weeks in a real workload, not just
> through `dxdiag`. "In validation" means a working first-boot config that has not
> cleared the two-week threshold yet. Nothing promotes before it does, my own cards
> included.

> **NVIDIA Consumer (GeForce RTX 40 / 50-series)** is deliberately absent. Consumer-tier
> passthrough is already represented by the Intel Arc A310, on which the harder failure
> modes (Code 43, CPUID hiding, INF gotcha) actually occur. The reasoning and what a
> submission would need are in [docs/vendors/nvidia-consumer.md](docs/vendors/nvidia-consumer.md).

## Open Findings and Backlog

- **RTX PRO 4500 Blackwell**: the WPR2 reset bug stays open. A host reboot is required
  after the VM stops; `vendor-reset` support for Blackwell is unconfirmed. ReBAR across
  the full 32 GB BAR and PCIe 5.0 link training under load are not verified.
- **RTX 2000 Ada**: the flag set is confirmed minimal (no hypervisor hiding). ECC status
  and CUDA/NVENC numbers are measured but unpublished, which blocks nothing.
- **AMD (Polaris / Navi / RDNA)**: waiting on test hardware and on `vendor-reset`
  building against current kernels.

## Scripts

Usage lines are the ones in each script's header; `--help` prints the same.

| Script | Usage | What it does |
|--------|-------|--------------|
| `enable-iommu.sh` | `sudo ./enable-iommu.sh [--apply]` | Detects CPU vendor and whether the host boots via GRUB or `proxmox-boot-tool`, then appends `intel_iommu=on iommu=pt` or `amd_iommu=on iommu=pt` and refreshes the bootloader. Dry-run without `--apply` (exit code 2). |
| `check-iommu-groups.sh` | `./check-iommu-groups.sh [GROUP_NUMBER]` | Lists every IOMMU group with its member BDFs, the driver each one is bound to, and the `lspci -nn` description. No argument lists all groups. |
| `bind-vfio.sh` | `sudo ./bind-vfio.sh <BDF>` | Unbinds one device from its host driver and rebinds it to `vfio-pci` at runtime, no reboot. One BDF per call. For permanent binding the script header gives the `/etc/modprobe.d/vfio.conf` stanza instead. |
| `check-vfio-binding.sh` | `./check-vfio-binding.sh <BDF>` | Pre-flight check that `i915` / `nouveau` / `amdgpu` do not hold the device. Exit 0 bound to `vfio-pci`, 1 bound elsewhere, 2 not found. |
| `generate-vm-args.sh` | `./generate-vm-args.sh --vendor <intel-arc\|nvidia-consumer\|nvidia-pro\|amd> [--as-config-line]` | Prints the `-cpu` line for one vendor profile. `--list` shows all profiles, `--explain <VENDOR>` explains every flag. Profiles that need no args print nothing to stdout and their rationale to stderr, so `qm set --args "$(...)"` sets an empty args line. |
| `install-reset-hook.sh` | `sudo ./install-reset-hook.sh <vmid> <BDF> [RESET_METHOD]` | Copies `hookscripts/reset-method.sh` to `/var/lib/vz/snippets/`, patches BDF and method into the copy, and attaches it with `qm set --hookscript`. |
| `hookscripts/reset-method.sh` | attached via `qm set <vmid> --hookscript` | At `pre-start`, writes a reset token (`flr`, `bus`, `pm`, `device_specific`; default `bus`) into `/sys/bus/pci/devices/<BDF>/reset_method`, for GPUs whose default reset sequence fails with `Inappropriate ioctl for device`. Other lifecycle phases pass through. |
| `capability-probe.ps1` | `powershell -ExecutionPolicy Bypass -File capability-probe.ps1` | Runs in the Windows guest. Reports DirectX feature level, Vulkan ICD registration and device presence, OpenGL, DXVA2/NVENC/QSV video profiles, and VRAM. VRAM comes from `DXGI_ADAPTER_DESC1.DedicatedVideoMemory` via P/Invoke, with `dxdiag` as fallback; WMI `AdapterRAM` is a 32-bit field and is reported only for reference. |
| `capability-probe.sh` | `./capability-probe.sh <vmid>` | Dispatches the PowerShell probe into a running Windows VM from the host and captures its output. Needs an active `qemu-guest-agent`; without one, copy the `.ps1` into the VM by hand. |
| `collect-diagnostics.sh` | `sudo ./collect-diagnostics.sh <vmid> [-o <outfile>]` | Bundles kernel cmdline, filtered dmesg, IOMMU layout, `vfio-pci` state, `qm config`/`qm status`, and `lspci -vv` into a tarball. It masks hostnames and part of each MAC address; it does **not** mask serial numbers, UUIDs, or paths, so review the bundle before sharing it. |

## Quick Start

```bash
# 1. Host preparation (one-time, requires reboot).
#    Default is dry-run; --apply writes the kernel cmdline + refreshes the bootloader.
sudo ./scripts/enable-iommu.sh --apply

# 2. Identify your GPU and its IOMMU group
./scripts/check-iommu-groups.sh
# Example output:
#   IOMMU Group 16:
#     0000:03:00.0  [driver: i915]  VGA compatible controller [0300]: Intel Corporation DG2 [Arc A310] [8086:56a6]
#
#   IOMMU Group 17:
#     0000:04:00.0  [driver: snd_hda_intel]  Audio device [0403]: Intel Corporation DG2 Audio [8086:4f92]

# 3. Bind GPU + companion to vfio-pci (one BDF per call)
sudo ./scripts/bind-vfio.sh 03:00.0
sudo ./scripts/bind-vfio.sh 04:00.0
# Verify each (should show "vfio-pci")
./scripts/check-vfio-binding.sh 03:00.0
./scripts/check-vfio-binding.sh 04:00.0

# 4. Generate vendor-specific QEMU args
./scripts/generate-vm-args.sh --vendor intel-arc
# -cpu host,kvm=off,hv_vendor_id=GenuineIntel,-hypervisor,+kvm_pv_unhalt,+invtsc,hv_relaxed,hv_spinlocks=0x1fff

# 5. Apply to VM. qm set is atomic, auditable in `qm config`, and works on a running VM
qm set 102 --hostpci0 '0000:03:00,pcie=1' \
           --hostpci1 '0000:04:00,pcie=1' \
           --vga none --balloon 0 \
           --args "$(./scripts/generate-vm-args.sh --vendor intel-arc)"

# 6. Start VM, install driver, then verify
qm start 102
# Inside Windows: PowerShell as Admin
powershell.exe -File capability-probe.ps1
```

> **Single host vs. cluster**: the Quick Start uses physical BDFs (`0000:03:00`). That
> holds on a standalone host and breaks in a cluster, where the same card sits at a
> different BDF on each node. For clusters with HA or migration use Resource Mappings
> (Proxmox VE 8+), see [docs/RESOURCE_MAPPINGS.md](docs/RESOURCE_MAPPINGS.md).

## Documentation

| Doc | Scope |
|-----|-------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Why passthrough fails: CPUID, IOMMU, BAR, Reset Bug overview |
| [docs/HOST_SETUP.md](docs/HOST_SETUP.md) | One-time Proxmox host preparation (IOMMU, VFIO, module blacklists) |
| [docs/VM_CONFIG.md](docs/VM_CONFIG.md) | `q35`, OVMF, `balloon: 0`, `vga: none`, `cpu: host`, hookscripts |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptom-driven matrix: Code 43, MBDA fallback, WPR2 reset (Blackwell), open-module requirement (Ada/Blackwell) |
| [docs/RESOURCE_MAPPINGS.md](docs/RESOURCE_MAPPINGS.md) | Cluster-aware passthrough via logical mapping names (Proxmox VE 8+); required for HA with passthrough |
| [docs/vendors/intel-arc-dg2.md](docs/vendors/intel-arc-dg2.md) | ✅ Intel Arc A310 full recipe (Code-43 fix, INF gotcha), production |
| [docs/vendors/nvidia-professional.md](docs/vendors/nvidia-professional.md) | ✅ RTX 2000 Ada + RTX PRO 4500 Blackwell, production. Two Pro cards in one VM, dual-GPU confirmed; open-module requirement, WPR2 reset bug |
| [docs/vendors/amd.md](docs/vendors/amd.md) | 📋 Reset Bug and the `vendor-reset` kernel module, backlog |
| [docs/vendors/nvidia-consumer.md](docs/vendors/nvidia-consumer.md) | 📋 Landing page for a contributed GeForce recipe, backlog |

Working VM configs per card live under [examples/](examples/): the Intel Arc A310 one
ships a complete [`vm-config.example.conf`](examples/intel-arc-a310/vm-config.example.conf).

## The Things Most Guides Miss

For **Intel Arc**: `kvm=off` alone is not enough. The Windows driver checks CPUID leaf
`0x1` ECX bit 31, the Hypervisor-Running flag, independently of the KVM signature in
leaf `0x40000000`. Passing the WDDM interface negotiation takes **both** `kvm=off` and
`-hypervisor`. The full CPUID mechanics are in
[docs/vendors/intel-arc-dg2.md § Code-43-Fix](docs/vendors/intel-arc-dg2.md#code-43-fix);
`./scripts/generate-vm-args.sh --explain intel-arc` prints the same reasoning per flag.

For **NVIDIA Blackwell / Ada Lovelace**: `nvidia-driver-XXX-server`, the standard
package, fails with `RmInitAdapter (0x22:0x56:1017)`. These architectures need the open
kernel module variant, `nvidia-driver-XXX-server-open`. What makes this expensive is the
symptom: `nvidia-smi` reports "No devices found" even with the module loaded, which looks
exactly like a VFIO binding problem and sends you down the wrong debug path. See
[docs/TROUBLESHOOTING.md § nvidia-smi Reports "No devices found"](docs/TROUBLESHOOTING.md#nvidia-smi-reports-no-devices-found-linux-guest--blackwell--ada).

For **NVIDIA Blackwell specifically**: the GPU does not survive a VM stop/start cycle
without a full host reboot, because PCIe FLR does not reset the GSP firmware's WPR2
state. This hits on the second VM boot, not the first, which makes first-boot success a
false signal. See
[docs/TROUBLESHOOTING.md § WPR2 Reset Bug](docs/TROUBLESHOOTING.md#nvidia-blackwell-gpu-failed-to-initialize-on-second-vm-start-wpr2-reset-bug).

## Prerequisites

- Proxmox VE 8.x or 9.x (tested on 9.1 with kernel 6.17.x)
- CPU with IOMMU support (Intel VT-d / AMD-Vi)
- BIOS: IOMMU enabled, "Above 4G Decoding" enabled, Resizable BAR enabled (recommended)
- Bash 4.0+ on the host for the scripts
- Guest: Windows 10/11 or any modern Linux. The examples lean Windows because that is
  where the driver quirks bite hardest.

## Contributing

New vendor recipes welcome. The one prerequisite: a reproducible setup that has been
running >=2 weeks, not a successful first boot. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Provenance

What is battle-tested here and what is codified are two different things:

- **The Intel Arc recipe text**
  ([docs/vendors/intel-arc-dg2.md](docs/vendors/intel-arc-dg2.md)) is the direct output
  of the validation session: symptoms, fix sequence, DxgKrnl event IDs, dead ends
  included. First-hand observations, not a literature review.
- **The Bash scripts in `scripts/`** codify standard VFIO and Proxmox-documentation
  patterns. They were **not** extracted from that session. The initial binding on the
  real host was done with one-liners
  (`echo "0000:03:00.0" > /sys/bus/pci/drivers/vfio-pci/bind` and friends); the scripts
  exist to make that flow repeatable on other setups.
- **`scripts/capability-probe.ps1`** is a clean-room re-composition of three forensic
  PowerShell scripts from the 2026-04-20 validation session (`probe.ps1`, `verify.ps1`,
  `dxgi_vram.ps1`). Those do not ship with the repo; the relevant logic was extracted
  and generalized.

So the recipe is battle-tested and the wrapper scripts are standards-based. Both
together are what makes the repo useful; neither one is the other.

## See Also

- [ubuntu-server-security](https://github.com/fidpa/ubuntu-server-security), Ubuntu hardening (14 components, CIS Benchmark)
- [step-ca-internal-pki](https://github.com/fidpa/step-ca-internal-pki), internal PKI for homelab services
- [bash-production-toolkit](https://github.com/fidpa/bash-production-toolkit), production-ready Bash libraries used across fidpa repos

## License

MIT, see [LICENSE](LICENSE).

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))

Running a Windows 11 VM with a passed-through Intel Arc A310 on Proxmox 9.1 cost me a
full day of debugging despite dozens of guides online, every one of which stopped short
of the CPUID and WDDM-interface corner cases that actually trip the driver. Once the
recipe worked I extracted the reproducible parts, scripts, config skeletons, symptom
matrix, so the next person, future me included, does not lose the same day to Error 43.
