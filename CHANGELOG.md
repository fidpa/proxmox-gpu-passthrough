# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_No released changes yet — see README.md § Roadmap for upcoming vendor recipes._

### Planned for v0.2.0
- Extend `collect-diagnostics.sh` sanitizer to mask IPv4/IPv6, hardware/BIOS UUIDs, and usernames in paths — once enough real-world diag bundles surface the common patterns.

## [0.1.0-dev] — 2026-04-20

Initial scaffolding. Not yet released.

### Added
- Repository structure (scripts, docs, examples, CI)
- Intel Arc A310 (DG2) recipe — full Code-43 fix with CPUID mechanics
  - QEMU args: `kvm=off`, `-hypervisor`, `hv_vendor_id=GenuineIntel`, `hv_relaxed`, `hv_spinlocks=0x1fff`
  - Failure-mode documentation: `E_NOINTERFACE` → `STATUS_UNSUCCESSFUL` → OK evolution
  - INF gotcha: `iigd_dch_d.inf` (DG2-discrete) vs `iigd_dch.inf` (iGPU) distinction
  - Vulkan ICD manual registration (pnputil skips it)
- Host setup scripts (IOMMU enable, VFIO bind, binding verify)
- Vendor-aware CPU args generator
- Reset-method hookscript template
- Capability probe (PowerShell, post-install Windows verification)
- Troubleshooting matrix (symptom → vendor → root cause → fix)
- CI: shellcheck + bash syntax validation
