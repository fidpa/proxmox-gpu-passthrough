# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Extend `collect-diagnostics.sh` sanitizer to mask IPv4/IPv6, hardware/BIOS UUIDs, and usernames in paths — once enough real-world diag bundles surface the common patterns.
- NVIDIA RTX 2000 Ada + RTX PRO 4500 Blackwell recipes (two Pro cards, same workstation, ML-inference workload — promote to ✅ after each clears its own ≥2-week threshold).
- `vendor-reset` installation guide for Blackwell WPR2 reset bug — once Blackwell support in `gnif/vendor-reset` is confirmed.

### Changed
- Intel Arc A310: promoted from 🚧 In validation → ✅ Production (2026-05-15 — ≥2-week uptime confirmed). Status updated in `README.md`, `docs/vendors/intel-arc-dg2.md`, and documentation table.

## [1.2.0] — 2026-05-15

### Added
- `docs/TROUBLESHOOTING.md`: new section "NVIDIA Blackwell: GPU Failed to Initialize on Second VM Start (WPR2 Reset Bug)" — root cause (GSP firmware WPR2 persists through PCIe FLR), contrast with AMD Reset Bug (comparison table), short-term fix (host reboot), long-term fix pointer (`vendor-reset`).
- `docs/vendors/nvidia-professional.md`: new subsection "Confirmed: Dual GPU to Same Linux VM — Docker Container Isolation" — documents `NVIDIA_VISIBLE_DEVICES` per-container GPU assignment, passthrough order (`hostpci1` → GPU 0), verification commands, WPR2 cross-reference. Confirmed 2026-05-15 with RTX PRO 4500 + RTX 2000 Ada in simultaneous production operation.

### Changed
- `docs/vendors/nvidia-professional.md`, RTX 2000 Ada: driver corrected to `nvidia-driver-595-server-open` (open kernel modules required for Ada Lovelace on this driver branch — same requirement as Blackwell, not only Blackwell as previously implied); added dual-GPU-confirmed note; added `qm set` / `vfio.conf` independence gotcha.
- `README.md`: RTX PRO 4500 Blackwell status corrected from `🚧 Planned` to `🚧 In validation` with hardware details — this promotion was done in v1.1.0 but the README table was not updated.

## [1.1.0] — 2026-05-15

### Added
- `docs/TROUBLESHOOTING.md`: new section "nvidia-smi Reports 'No devices found'
  (Linux Guest — Blackwell / Ada)" — root cause (closed-source kernel modules do not
  support Blackwell/Ada Lovelace), fix (`nvidia-driver-<VERSION>-server-open` or
  `-open` variant), affected architectures, and live VFIO bind technique via
  `new_id` (when device IDs are unknown to the already-loaded module instance).

### Changed
- RTX 2000 Ada (`docs/vendors/nvidia-professional.md`, `examples/nvidia-rtx-2000-ada/README.md`,
  `README.md`): status Planned → In validation (first hardware session 2026-05-11).
  Confirmed vendor:device IDs (`10de:28b0` GPU, `10de:22be` audio companion),
  CUDA compute 8.9, driver branch `nvidia-driver-595-server`. Documented Ubuntu 24.04
  gotcha: `nvidia-container-toolkit` is absent from standard apt repos — NVIDIA's own
  apt repository (`nvidia.github.io/libnvidia-container`) is required.
- RTX PRO 4500 Blackwell (`examples/nvidia-rtx-pro-4500-blackwell/README.md`,
  `docs/vendors/nvidia-professional.md`): status Planned → In validation (first hardware
  session 2026-05-15). Confirmed vendor:device IDs (`10de:2c31` GPU, `10de:22e9` audio
  companion), clean IOMMU group (AMD Raphael/Granite Ridge, group isolated to GPU +
  audio companion only), config shape validated on Proxmox VE 9.1.1 / kernel
  6.17.2-1-pve host, Ubuntu 24.04 guest (kernel 6.8.0-111-generic). Critical
  Blackwell finding: open kernel modules mandatory — `nvidia-driver-595-server`
  (closed) fails with `RmInitAdapter (0x22:0x56:1017)`; fix is
  `nvidia-driver-595-server-open`. Audio companion had `snd_hda_intel` bound on
  first boot; `softdep snd_hda_intel pre: vfio-pci` in `modprobe.d` prevents
  recurrence.

## [1.0.0] — 2026-04-21

Initial public release.

### Added
- Repository structure (scripts, docs, examples, CI)
- **Intel Arc A310 (DG2) recipe** — full Code-43 fix with CPUID mechanics (🚧 in validation, promotes to ✅ on 2026-05-04)
  - QEMU args: `kvm=off`, `-hypervisor`, `hv_vendor_id=GenuineIntel`, `hv_relaxed`, `hv_spinlocks=0x1fff`
  - Failure-mode documentation: `E_NOINTERFACE` → `STATUS_UNSUCCESSFUL` → OK evolution
  - INF gotcha: `iigd_dch_d.inf` (DG2-discrete) vs `iigd_dch.inf` (iGPU) distinction
  - Vulkan ICD manual registration (pnputil skips it)
- **Host setup scripts** — `enable-iommu.sh` (auto-detects GRUB vs. proxmox-boot-tool), `bind-vfio.sh`, `check-vfio-binding.sh`, `check-iommu-groups.sh`
- **Vendor-aware CPU-args generator** (`generate-vm-args.sh`) — dual-mode (raw args for `qm set --args`, or `--as-config-line` for config-file paste); `--explain` mode for pedagogy; profiles for intel-arc, nvidia-consumer, nvidia-pro, amd
- **Reset-method hookscript** template (`hookscripts/reset-method.sh`) + installer (`install-reset-hook.sh`)
- **Windows guest capability probe** (`capability-probe.ps1`) — DXGI-based VRAM detection (avoids the 32-bit WMI cap), Vulkan ICD registry check, DirectX feature levels, NVENC/QSV/AMF detection
- **Diagnostic bundler** (`collect-diagnostics.sh`) with auto-sanitization disclaimer
- **Vendor stubs** for NVIDIA Pro (RTX 2000 Ada + RTX PRO 4500 Blackwell, planned), NVIDIA Consumer (backlog — Intel Arc A310 already covers Consumer-tier), AMD (backlog)
- **Cluster support** — `RESOURCE_MAPPINGS.md` for Proxmox VE 8+ HA / migration scenarios
- **Troubleshooting matrix** (symptom → vendor → root cause → fix)
- **CI** — shellcheck (severity=warning) + bash-syntax + markdown-link-check via GitHub Actions
- **Release automation** via `release.yml` workflow (extracts CHANGELOG section on tag push)
