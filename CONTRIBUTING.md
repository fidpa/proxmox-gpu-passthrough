# Contributing

Contributions welcome, especially new vendor recipes. The scope of this repo is narrow — **reproducible GPU passthrough recipes that survive real workloads** — so please read the ground rules before opening a PR.

## What's in Scope

- **New GPU vendor recipes** (AMD Navi, NVIDIA RTX 50-series variants, Intel Battlemage, etc.)
- **Failure modes** that bite in production but are poorly documented upstream (CPUID checks, BAR edge cases, reset bugs)
- **Scripts** that automate reproducible host/VM setup steps
- **Diagnostic tools** (IOMMU group analysis, VFIO binding check, capability probes)

## What's Not in Scope

- SR-IOV / vGPU partitioning (separate repo territory)
- LXC GPU sharing (use Proxmox wiki — it's well-covered there)
- General Proxmox cluster / HA / storage topics
- NVIDIA Linux guest drivers (plenty of existing resources)

## Ground Rules

### 1. No Vendor Recipe Without ≥2 Weeks Production

"Production" means: the VM is being used for a real workload (gaming, ML inference, video editing, CAD, compute) — not just `dxdiag.exe` passing. First-boot success is necessary but not sufficient; we've seen passthrough that works on Day 1 and dies on Day 5 when the driver updates itself.

### 2. Cite the Root Cause, Not the Symptom

❌ "Add `kvm=off` to fix Code 43" (true but surface-level)

✅ "Intel Arc driver reads CPUID leaf `0x1` ECX bit 31 independently of the Hypervisor-Vendor-String in leaf `0x40000000`. `kvm=off` only clears the latter. The driver still sees the Hypervisor-Running-Flag → requests a WDDM interface DxgKrnl doesn't export under QEMU → E_NOINTERFACE. Fix: add `-hypervisor` to also clear bit 31."

### 3. Sanitize Everything

- No real IPs (use RFC 5737: `192.0.2.x`, `198.51.100.x`, `203.0.113.x`)
- No real hostnames (use `proxmox-host`, `win-vm`, `gpu-host.example.com`)
- No real MACs (use `00:00:5E:00:53:xx` — RFC 7042 documentation range)
- No real VM IDs tied to identifiable infrastructure
- Use generic BDFs in prose (`0000:03:00.0`) but keep vendor/device IDs real (`8086:56a6`)

### 4. Test Your Scripts

All bash scripts must:
- Pass `shellcheck --severity=warning` (matches CI and `.shellcheckrc`)
- Use `set -uo pipefail` (project convention — explicit error handling per command, no global `-e`)
- Quote all variable expansions (`"$var"` not `$var`)
- Fail loudly on missing prerequisites (root check, IOMMU check, etc.)

### 5. Document Failure Modes, Not Just the Happy Path

The value of this repo is **what breaks and why**. A PR that says "it works" is less useful than one that says "here's how I got it to break, here's the error message, here's the fix, here's why the fix works."

## Adding a New Vendor Recipe

1. Create `docs/vendors/<vendor>-<family>.md` following the [intel-arc-dg2.md](docs/vendors/intel-arc-dg2.md) structure:
   - TL;DR (3 lines)
   - Hardware + driver tested-with matrix
   - Host prep (if vendor-specific)
   - VM config
   - Driver install (guest)
   - Vendor-specific gotchas + fixes
   - Capability probe results
2. Add sanitized VM config example to `examples/<vendor>-<family>/`
3. Extend `scripts/generate-vm-args.sh` with your vendor profile
4. Add row to README.md "Supported GPUs" table (as 🚧 until 2 weeks uptime, then ✅)
5. Update `docs/TROUBLESHOOTING.md` with any new symptom→fix rows
6. Add CHANGELOG.md entry under `[Unreleased]`

## Pull Request Checklist

- [ ] Scripts pass `shellcheck --severity=warning`
- [ ] No private paths, IPs, hostnames, or credentials
- [ ] CHANGELOG.md updated
- [ ] Root cause documented (not just symptom)
- [ ] Tested on at least one real setup (please describe in PR)
- [ ] README.md "Supported GPUs" table updated if adding vendor

## Reporting Issues

For setup-specific help ("my RTX 4090 shows Code 43"), please include:
- Output of `lspci -nnk -s <BDF>` (both GPU and audio companion)
- Output of `./scripts/check-iommu-groups.sh`
- Your VM config (`qm config <vmid>`, sanitized)
- Guest OS + driver version
- Kernel version (`uname -r`)
- Proxmox version (`pveversion`)

## Questions

Open a GitHub Discussion. Issues are for bugs and concrete feature requests.
