# Example: NVIDIA Consumer (RTX 40-series Ada / 50-series Blackwell) Passthrough

Backlog stub for the NVIDIA Consumer-Ada / Consumer-Blackwell passthrough recipe — Code-43 is dead since driver 465.89 (April 2021), but ReBAR, PCIe 5.0 link training, and aggressive P-states bring their own drama.

> **Status**: 📋 **Backlog — not in the main README "Supported GPUs" table.**
> Consumer-tier passthrough is already represented in this repo by the
> [Intel Arc A310 example](../intel-arc-a310/) (which demonstrates the harder
> Consumer-tier failure modes: Code-43, CPUID hiding, INF gotcha).
> This stub is kept as a deep-link landing page for contributors who want to
> submit a NVIDIA-GeForce-specific recipe under the standard ≥2-week-uptime rule.

## Why Backlog and Not in the Main Table

Two reasons:

1. **Consumer-tier is already covered by the Intel Arc A310 example.** The A310 demonstrates the harder Consumer-tier story (Code-43 with active CPUID checks, INF-file confusion, manual Vulkan ICD registration). A second easier Consumer recipe (Code-43 dropped in NVIDIA driver 465.89, April 2021) would not add educational value to the main navigation.

2. **No planned hardware on the author's side.** The author's planned NVIDIA cards are **Pro-line** (RTX 2000 Ada + RTX PRO 4500 Blackwell — see [../nvidia-rtx-2000-ada/](../nvidia-rtx-2000-ada/) and [../nvidia-rtx-pro-4500-blackwell/](../nvidia-rtx-pro-4500-blackwell/)). Adding a copy-paste Consumer-NVIDIA recipe without real ≥2-week production validation would violate this repo's own ground rule (see [CONTRIBUTING.md § 1](../../CONTRIBUTING.md#1-no-vendor-recipe-without-2-weeks-production)).

## Anticipated Config Shape

```
args: (none expected -- modern NVIDIA Consumer driver >= 465.89 needs no Code-43 workaround)
machine: pc-q35-9.2
bios: ovmf
cpu: host
balloon: 0
vga: none
hostpci0: 0000:<BDF>,pcie=1,x-vga=0
hostpci1: 0000:<BDF.1>,pcie=1  # Audio controller on .1 function
```

## The Interesting Failure Modes (not Code 43)

NVIDIA dropped the Code-43 VM-detection in driver 465.89 (April 2021) with the *"GeForce GPU Passthrough for Windows VM (Beta)"* release. On modern Consumer Ada / Blackwell cards the remaining issues are different:

- **Large-BAR (ReBAR) negotiation** — RTX 5090 32 GB has a 32 GB BAR. Some mainboard BIOSes fail to map the full BAR through the PCIe hierarchy; driver falls back to small-BAR mode (massive perf hit).
- **PCIe 5.0 link training** — some host/board combos drop to PCIe 4.0 / 3.0 under heavy load.
- **NVENC / NVDEC session limits** — Consumer cards have a session cap; `nvidia-patch` removes it but that's out of scope for this repo.
- **Power management** — aggressive P-state transitions on RTX 40 / 50-series can confuse the host PCIe subsystem during VM stop/start.

## What a Submission Should Validate

1. Clean driver install (NVIDIA Game Ready or Studio branch — document why)
2. ReBAR status (`dxdiag` "Dedicated Memory" shows full 12 / 16 / 24 / 32 GB)
3. NVENC / NVDEC active session count
4. DirectX 12 Ultimate feature level 12_2
5. ≥2-week real workload (gaming, ML, video editing — not synthetic)

## How to Submit

See [CONTRIBUTING.md](../../CONTRIBUTING.md). The most useful PR explicitly contrasts your Consumer-card setup with the Pro-card recipe in [../../docs/vendors/nvidia-professional.md](../../docs/vendors/nvidia-professional.md) — same Blackwell silicon family in some cases, but very different driver branch and feature set.

## Tracking

- Open issue with label `vendor:nvidia-consumer`
- Stub doc: [../../docs/vendors/nvidia-consumer.md](../../docs/vendors/nvidia-consumer.md)

## See Also

- [../intel-arc-a310/](../intel-arc-a310/) — Validated Intel Arc example (contrast: CPUID-check workaround required)
- [../nvidia-rtx-2000-ada/](../nvidia-rtx-2000-ada/) — Pro Ada placeholder (planned hardware)
- [../nvidia-rtx-pro-4500-blackwell/](../nvidia-rtx-pro-4500-blackwell/) — Pro Blackwell placeholder (planned hardware) — same silicon family, different driver branch
- [../../docs/vendors/nvidia-consumer.md](../../docs/vendors/nvidia-consumer.md) — Stub doc for Consumer-driver specifics
- [../../CONTRIBUTING.md](../../CONTRIBUTING.md) — ≥2-week-uptime rule for promotion from Backlog → In validation → Production

---

*Contributors: if you already run an RTX 40-series or 50-series Consumer card in Proxmox passthrough for ≥2 weeks and can sanitize your config, please open a PR — see [CONTRIBUTING.md](../../CONTRIBUTING.md).*
