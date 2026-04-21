# Example: NVIDIA RTX PRO 4500 Blackwell Passthrough

Placeholder slot for the NVIDIA RTX PRO 4500 Blackwell (Professional / Workstation, Blackwell silicon, 32 GB GDDR7 ECC) passthrough recipe — will land here once the card has run an ML-inference workload for ≥2 weeks.

> **Status**: 🚧 **Planned** — target hardware on the procurement path.
> Promotes to ✅ once the ≥2-week uptime threshold ([CONTRIBUTING.md § 1](../../CONTRIBUTING.md#1-no-vendor-recipe-without-2-weeks-production)) is met under real ML-inference load.

## Why Placeholder

This repo's rule is **no vendor recipe without ≥2 weeks of production validation on real hardware**. The RTX PRO 4500 Blackwell will be installed in a workstation alongside an RTX 2000 Ada (see [../nvidia-rtx-2000-ada/](../nvidia-rtx-2000-ada/)) and used for ML inference. Once the card has ≥2 weeks of uptime under real workload, the recipe lands here.

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

Same shape as the RTX 2000 Ada example — both are NVIDIA Pro cards on the RTX Enterprise driver branch, both use the `nvidia-pro` profile from `scripts/generate-vm-args.sh` (which emits no custom args).

## Why This Card Is Interesting (Beyond "It's a Pro Card")

The PRO 4500 Blackwell sits at an unusual intersection:

- **Architecturally Pro** → `nvidia-pro` profile applies. No `kvm=off`, no `-hypervisor`. The driver expects KVM visible.
- **Silicon-wise Blackwell** → it inherits Consumer-Blackwell-class issues that the Ada-Pro RTX 2000 doesn't have. Specifically:
  - **ReBAR negotiation on a full 32 GB BAR** — mainboard BIOS must map the entire 32 GB BAR through the PCIe hierarchy. Small-memory-map BIOSes silently fall back to a 256 MB BAR with a brutal perf hit. Verify with `lspci -vv -s <BDF>` — the BAR line should show full 32 GB, not the truncated fallback.
  - **PCIe 5.0 link training** — host slot must negotiate full PCIe 5.0 x16 and stay there under load. Some host/board combos drop to PCIe 4.0 / 3.0 thermally. Check `lspci -vv` `LnkSta:` during sustained inference.
  - **GDDR7 ECC** — `nvidia-smi -q -d ECC` should show ECC supported and on (Pro default).

This makes it a **useful contrast** to both the Ada-Pro RTX 2000 (same driver branch, different silicon-era quirks) and the Consumer-Blackwell stub (same silicon, different driver branch).

## What will be validated

1. Clean driver install (NVIDIA RTX Enterprise branch — Linux for inference workload, or Windows for guest-side tooling)
2. Full BAR exposed (`lspci -vv` shows 32 GB BAR, not truncated fallback)
3. PCIe 5.0 x16 link width sustained under load (`lspci -vv` `LnkSta:`)
4. ECC memory active (`nvidia-smi -q -d ECC`)
5. CUDA compute (`nvcc` sample: deviceQuery, bandwidthTest)
6. NVENC session capability (no Consumer per-process session cap on Pro cards)
7. ≥2-week ML-inference workload — actual model serving (e.g. 13B–34B-class quantized LLM, larger transformer batches, multi-modal inference)

## Two-Card-One-Host Considerations

This card shares a workstation with the RTX 2000 Ada. See [../../docs/vendors/nvidia-professional.md § Two-Card-One-Host Considerations](../../docs/vendors/nvidia-professional.md#two-card-one-host-considerations) for IOMMU group placement, slot routing, TDP budget, and thermal coupling notes.

## Tracking

- Open issue with label `vendor:nvidia-pro-blackwell` when init / ReBAR / link-training issues encountered
- Stub doc: [../../docs/vendors/nvidia-professional.md](../../docs/vendors/nvidia-professional.md)

## See Also

- [../intel-arc-a310/](../intel-arc-a310/) — Validated Intel Arc example (contrast: hypervisor-hiding required)
- [../nvidia-rtx-2000-ada/](../nvidia-rtx-2000-ada/) — Sibling Ada-Pro placeholder (same Pro driver branch, older silicon)
- [../nvidia-consumer-blackwell/](../nvidia-consumer-blackwell/) — Consumer-Blackwell stub (same silicon family, different driver branch)
- [../../docs/vendors/nvidia-professional.md](../../docs/vendors/nvidia-professional.md) — Stub doc for both Pro cards
- [../../CONTRIBUTING.md](../../CONTRIBUTING.md) — ≥2-week-uptime rule for promotion from Planned → Production

---

*Contributors: if you run any RTX PRO Blackwell variant (PRO 4000 / 4500 / 5000 / 6000 Blackwell) in Proxmox passthrough and want to submit a recipe before this one is ready, see [CONTRIBUTING.md](../../CONTRIBUTING.md). Pro-Blackwell recipes are completely absent from open-source GPU-passthrough docs at this point.*
