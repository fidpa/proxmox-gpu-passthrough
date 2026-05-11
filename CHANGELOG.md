# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- RTX 2000 Ada (`docs/vendors/nvidia-professional.md`, `examples/nvidia-rtx-2000-ada/README.md`,
  `README.md`): status Planned → In validation (first hardware session 2026-05-11).
  Confirmed vendor:device IDs (`10de:28b0` GPU, `10de:22be` audio companion),
  CUDA compute 8.9, driver branch `nvidia-driver-595-server`. Documented Ubuntu 24.04
  gotcha: `nvidia-container-toolkit` is absent from standard apt repos — NVIDIA's own
  apt repository (`nvidia.github.io/libnvidia-container`) is required.

### Planned
- Extend `collect-diagnostics.sh` sanitizer to mask IPv4/IPv6, hardware/BIOS UUIDs, and usernames in paths — once enough real-world diag bundles surface the common patterns.
- Promote Intel Arc A310 recipe from 🚧 to ✅ once the ≥2-week production-uptime threshold is confirmed met.
- NVIDIA RTX 2000 Ada + RTX PRO 4500 Blackwell recipes (two Pro cards, same workstation, ML-inference workload — promote to ✅ after each clears its own ≥2-week threshold).

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
