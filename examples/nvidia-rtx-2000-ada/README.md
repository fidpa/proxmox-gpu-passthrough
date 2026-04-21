# Example: NVIDIA RTX 2000 Ada Passthrough

Placeholder slot for the NVIDIA RTX 2000 Ada (Professional / Workstation, Ada-Generation, 16 GB GDDR6 ECC) passthrough recipe — will land here once the card has run an ML-inference workload for ≥2 weeks.

> **Status**: 🚧 **Planned** — target hardware on the procurement path. Will share a workstation with the [RTX PRO 4500 Blackwell](../nvidia-rtx-pro-4500-blackwell/) (two Pro cards, one host, ML-inference workload).

## Why Placeholder

This repo's rule is **no vendor recipe without ≥2 weeks of production validation on real hardware** (see [CONTRIBUTING.md](../../CONTRIBUTING.md)). The RTX 2000 Ada will be installed in a workstation alongside the RTX PRO 4500 Blackwell (32 GB GDDR7) and used for ML inference. Once the card has ≥2 weeks of uptime under real workload, the recipe lands here.

## Anticipated Config Shape

```
args: (none expected -- Pro cards do NOT need kvm=off / -hypervisor)
machine: pc-q35-9.2
bios: ovmf
cpu: host
balloon: 0
vga: none
hostpci0: 0000:<BDF>,pcie=1,x-vga=0
```

Key difference vs the Intel Arc example: **no `-hypervisor` flag**. NVIDIA Pro drivers expect to see KVM. Hiding the hypervisor would disable vGPU features and confuse the enterprise driver.

## What will be validated

1. Clean driver install (NVIDIA RTX Enterprise branch, not Game Ready)
2. ECC memory status (`nvidia-smi -q -d ECC`)
3. CUDA compute (`nvcc` sample: deviceQuery, bandwidthTest)
4. NVENC session capability (no Consumer session limit on Pro cards)
5. 2-week workload: real ML-inference task (smaller models, fp16 / int8 inference, classical CV — the 16 GB headroom is for model + activations + KV cache; larger models go to the PRO 4500 Blackwell sibling card)

## Tracking

- Open issue with label `vendor:nvidia-pro` when Code 43 / init issues encountered
- Stub doc: [../../docs/vendors/nvidia-professional.md](../../docs/vendors/nvidia-professional.md)

## See Also

- [../intel-arc-a310/](../intel-arc-a310/) — Validated Intel Arc example (contrast: hypervisor-hiding required; also serves as Consumer-tier reference)
- [../nvidia-rtx-pro-4500-blackwell/](../nvidia-rtx-pro-4500-blackwell/) — Sibling Pro card in the same workstation (Blackwell-generation, 32 GB)
- [../nvidia-consumer-blackwell/](../nvidia-consumer-blackwell/) — Backlog stub for NVIDIA-GeForce-specific quirks (not in main table)
- [../../docs/vendors/nvidia-professional.md](../../docs/vendors/nvidia-professional.md) — Stub doc covering both Pro cards
- [../../CONTRIBUTING.md](../../CONTRIBUTING.md) — ≥2-week-uptime rule for promotion from Planned → Production

---

*Contributors: if you run RTX A2000 / A4000 / A5000 / RTX 4000 Ada / 5000 Ada / 6000 Ada in Proxmox passthrough and want to submit a recipe before this one is ready, see [CONTRIBUTING.md](../../CONTRIBUTING.md). Professional-card recipes are underrepresented in open-source GPU-passthrough docs.*
