# NVIDIA Consumer (GeForce RTX 40-series Ada / 50-series Blackwell)

> 📋 **Status**: Backlog — not in the main README "Supported GPUs" table. Stub kept for contributors. Consumer-tier passthrough is already represented in this repo by the **[Intel Arc A310 recipe](intel-arc-dg2.md)**.

## Why This Slot Is Backlog and Not in the Main Table

Two reasons:

1. **Consumer-tier is already covered by Intel Arc A310.** The A310 recipe demonstrates the *harder* Consumer-tier failure modes — Code-43 with active CPUID checks, INF-file confusion, manual Vulkan ICD registration, WDDM interface negotiation — on a Consumer-class card. A second "easier" Consumer recipe (NVIDIA dropped Code-43 in driver 465.89, April 2021) would not add educational value to the main table.

2. **No planned hardware on the author's side.** The author's planned GPU acquisitions are two **Pro-line** cards (RTX 2000 Ada + RTX PRO 4500 Blackwell — see [nvidia-professional.md](nvidia-professional.md)). A copy-paste NVIDIA-Consumer recipe without real ≥2-week production validation would violate this repo's own ground rule ([CONTRIBUTING.md § 1](../../CONTRIBUTING.md#1-no-vendor-recipe-without-2-weeks-production)).

This stub stays in the repo as a deep-link landing page for contributors who actually run RTX 40 / 50-series in passthrough production and want to submit a recipe specifically about NVIDIA-GeForce-driver quirks (Game Ready vs. Studio branch, NVENC session cap, GeForce-specific ReBAR drama on RTX 5090) — things the Arc A310 doesn't exhibit.

## What a Consumer-Recipe Submission Should Cover

Modern NVIDIA Consumer cards (RTX 20-series Turing and newer — including RTX 40-series Ada and RTX 50-series Blackwell) are officially supported for virtualization since driver 465.89 (April 2021), when NVIDIA dropped the infamous Code-43 anti-VM check with the *"GeForce GPU Passthrough for Windows Virtual Machine (Beta)"* release. In theory, a recent driver on a recent card with a vanilla Proxmox config should "just work".

In practice, the interesting failures moved elsewhere — and a useful PR documents those:

- **ReBAR negotiation** on cards with large BARs (16+ GB VRAM) — BAR size must be exposed correctly through the PCIe hierarchy or the driver falls back to small-BAR mode with massive perf hit.
- **PCIe 5.0 link training** failures under heavy load (some boards/BIOS combinations drop to PCIe 4.0 / 3.0).
- **NVENC / NVDEC** session limits — NVIDIA limits Consumer cards to N concurrent sessions; patches exist (`nvidia-patch`) but are out of scope for this repo.
- **Power management** — RTX 40 / 50-series have aggressive P-state transitions that can confuse the host PCIe subsystem during VM stop/start.
- **Audio companion** — always on the same BDF function `.1` for Consumer cards; pass both functions.
- **Driver branch choice** — Game Ready vs. Studio. Document why your workload led to one or the other.

## Anticipated Recipe Shape (Pre-Submission Sketch)

```
Pattern D: Paravirt-tolerant driver (no Layer-4 hiding usually needed)
Layer 4: minimal flags — usually just -cpu host plus standard q35/OVMF
Layer 5: verify driver ≥ 465.89, check NVENC/NVDEC availability
Known quirks:
  - RTX 5090 32 GB + 4K BAR: boot-time BAR allocation on small-memory-map BIOS
  - Audio controller on .1 function — always pass both
  - Consumer NVLink: N/A on RTX 40 / 50 (removed)
```

## Differences vs. Intel Arc Recipe

| Aspect | Intel Arc DG2 | NVIDIA Consumer Ada / Blackwell |
|--------|---------------|----------------------------------|
| Code 43 fix needed? | Yes (CPUID hiding) | No (since driver 465.89, April 2021) |
| INF-file confusion? | Yes (`iigd_dch_d.inf` vs `iigd_dch.inf`) | No (single `nvlddmkm.inf`) |
| Vulkan ICD auto-register? | No (via pnputil) | Yes (NVIDIA installer handles it) |
| Audio companion? | Yes (often on separate BDF) | Yes (same BDF, function `.1`) |
| VBIOS romfile needed? | No | Usually no, sometimes for older boards |

## Differences vs. NVIDIA Pro Recipe

The most useful contribution would explicitly contrast the Consumer-Ada / Consumer-Blackwell setup with the [nvidia-professional.md](nvidia-professional.md) recipe — same silicon family in the case of Blackwell, but different driver branch and very different feature set (no ECC, NVENC session cap, Game Ready vs. RTX Enterprise).

## How to Submit a Recipe

1. Run RTX 40 / 50-series in production passthrough for ≥2 weeks with a real workload (not just `dxdiag` passing).
2. Sanitize your config per [CONTRIBUTING.md § 3](../../CONTRIBUTING.md#3-sanitize-everything).
3. Open a PR adding:
   - `examples/nvidia-rtx-<model>/` with vm-config.example.conf + README following the Intel Arc example structure
   - Updates to this doc (replace the "Anticipated Recipe Shape" stub with the actual recipe)
   - A row in the README "Supported GPUs" table flipping from 📋 backlog to 🚧 in validation (and ✅ once your own ≥2 weeks are documented)
4. Document failure modes, not just the happy path — see [CONTRIBUTING.md § 5](../../CONTRIBUTING.md).

## References

- NVIDIA GeForce GPU Passthrough for Windows VM (Beta): <https://nvidia.custhelp.com/app/answers/detail/a_id/5173/> — Driver R465 (April 2021) introduced official support
- Proxmox Forum PCI Passthrough category: <https://forum.proxmox.com/forums/pci-passthrough.117/>
- Level1Techs VFIO category (lots of Consumer-card threads): <https://forum.level1techs.com/c/software/linux/vfio-passthrough>
