# NVIDIA Professional (RTX A / RTX Ada / RTX PRO Blackwell / Quadro)

> 🚧 **Status**: Planned. Target hardware: **two Pro cards in one workstation** —
> **RTX 2000 Ada Generation (16 GB GDDR6 ECC)** as the Ada-generation reference,
> and **RTX PRO 4500 Blackwell (32 GB GDDR7)** as the Blackwell-generation reference.
> Both targeted at ML-inference workload. Recipes promote from 🚧 to ✅ once each
> card has cleared ≥2 weeks of production uptime per [CONTRIBUTING.md § 1](../../CONTRIBUTING.md#1-no-vendor-recipe-without-2-weeks-production).

## Why Professional Cards Are Different

NVIDIA RTX Professional cards (formerly Quadro) are **explicitly marketed for virtualization**. Unlike Consumer GeForce cards, they have never had a Code-43-block, and they support features Consumer cards can't:

- **vGPU (SR-IOV-based GPU partitioning)** via NVIDIA vGPU software — split one physical GPU across multiple VMs (where the SKU is licensed for it)
- **Proper ECC memory** on most Ada-/Blackwell-Pro cards (RTX 2000 Ada: GDDR6 ECC; RTX PRO 4500 Blackwell: GDDR7 ECC)
- **Long-term driver support** via the NVIDIA RTX Enterprise driver branch (separate from Consumer Game Ready / Studio)
- **GRID / CUDA compute in VMs** as a first-class use case
- **NVENC / NVDEC** without the Consumer per-process session cap

For plain **PCIe passthrough** (not vGPU), the Pro cards are actually easier than Consumer ones because the driver fully expects virtualization. Most problems disappear.

## Anticipated Recipe (Both Cards)

```
Pattern D: Paravirt-tolerant (Layer 5)
Layer 4: Minimal — no kvm=off, no -hypervisor, no hv_* enlightenments usually
Layer 3: Standard VFIO binding
Layer 2: Usually clean IOMMU group (Pro cards often get their own PCIe slot)
Layer 1: Standard — IOMMU, Above-4G, ReBAR

Driver branch: NVIDIA RTX Enterprise (NOT GeForce Game Ready / Studio).
Driver install: Search Product Series "RTX / Quadro" → choose Pro card → RTX Enterprise package.
```

## Why Overdoing It Can Break

Pro card passthrough often works with a **vanilla** QEMU config. Applying the Consumer Code-43 workaround flags (`kvm=off`, `-hypervisor`) on a Pro card can sometimes cause issues:

- **vGPU detection**: NVIDIA vGPU enterprise stack **needs** to see the hypervisor (KVM signature) to enter virtualization mode. Hiding KVM disables vGPU features.
- **Performance counters**: Some NVIDIA profiling tools check for hypervisor presence to know whether to use paravirt counters.

**Rule of thumb**: Start with no `-cpu` tuning beyond `-cpu host`. Add flags only if a specific failure mode occurs.

## Differences vs. Intel Arc and NVIDIA Consumer

| Aspect | Intel Arc | NVIDIA Consumer | **NVIDIA Pro** |
|--------|-----------|-----------------|----------------|
| Code 43 fix? | Yes (mandatory) | No (since 2021) | **Never needed** |
| CPUID hiding? | Yes | No | **Counterproductive** |
| Driver branch | Single Consumer | Game Ready / Studio | **Pro / RTX Enterprise** |
| vGPU capable? | No (DG2 Alchemist) | No | **Most Ada / Blackwell Pro cards: yes (license-gated)** |
| ECC VRAM? | No | No | **Most Ada / Blackwell Pro cards: yes** |
| NVENC session limit? | N/A | Yes (Consumer cap) | **No cap** |

## RTX 2000 Ada — Hardware Notes (Ada-Generation Pro)

- **Vendor:Device ID**: `10de:???` — to be confirmed from actual card
- **Architecture**: Ada Lovelace (AD107)
- **TDP**: 70 W — low-profile, single-slot, no external power connector
- **VRAM**: 16 GB GDDR6 with ECC
- **PCIe**: 4.0 x8 (physical x16 slot)
- **Expected workload**: ML inference (smaller models, fp16 / int8 inference, classical CV)
- **Why included**: Reference point for the Ada Pro lineage; low TDP makes it the "always-on" card alongside the Blackwell PRO 4500.

## RTX PRO 4500 Blackwell — Hardware Notes (Blackwell-Generation Pro)

- **Vendor:Device ID**: `10de:???` — to be confirmed from actual card
- **Architecture**: Blackwell (workstation silicon, not the Consumer GB20x line)
- **VRAM**: 32 GB GDDR7 with ECC
- **PCIe**: 5.0 x16
- **Expected workload**: ML inference (larger models — 32 GB headroom for 13B–34B-class quantized LLMs, larger transformer batches, multi-modal pipelines)
- **Why included**: Modern Blackwell silicon means it shares failure modes with **Consumer Blackwell cards** (ReBAR negotiation on 32 GB BAR, PCIe 5.0 link training) — but on the **Pro driver branch**, which avoids Code-43 flag-set entirely. Useful contrast for readers who otherwise have to triangulate between Consumer-Blackwell guides and Ada-Pro guides.

### Anticipated Quirks (Blackwell-Specific)

- **ReBAR on full 32 GB** — mainboard BIOS must map the full 32 GB BAR through the PCIe hierarchy; small-memory-map BIOSes silently fall back to 256 MB BAR with a massive perf hit. Verify with `lspci -vv -s <BDF>` showing the full BAR size, not the truncated fallback.
- **PCIe 5.0 link training** — host slot must negotiate full PCIe 5.0 x16; under heavy thermal load some host/board combos drop to PCIe 4.0 / 3.0. Check with `lspci -vv` `LnkSta:` line during workload.
- **GDDR7 ECC reporting** — `nvidia-smi -q -d ECC` should show ECC supported and active; default for Pro cards is usually enabled.

## Anticipated Test Plan (per card)

1. Install card in the workstation (both Pro cards live in the same chassis, separate IOMMU groups)
2. Host prep per [HOST_SETUP.md](../HOST_SETUP.md) — no Pro-specific deviations expected
3. VM config per [VM_CONFIG.md](../VM_CONFIG.md) — minimal args, no hypervisor hiding
4. Install NVIDIA RTX Enterprise driver in Linux/Windows guest (depending on inference stack)
5. Run capability probe — check CUDA compute, ECC status, full-BAR (Blackwell), full PCIe link width
6. Run 2-week ML-inference workload (real model serving, not synthetic benchmark)
7. Document any surprises — especially Blackwell-vs-Ada differences
8. Update this doc from stub → full recipe per card; flip README table rows from 🚧 to ✅

## Two-Card-One-Host Considerations

Running both Pro cards in the same workstation has its own gotchas:
- **IOMMU group placement** — verify each card lands in its own group (or a clean group with only its own audio companion). If they share a group, both must go to the same VM or both to vfio-pci.
- **Slot routing** — prefer CPU-routed PCIe slots over chipset-routed for both cards; chipset slots usually share groups.
- **TDP budget** — combined ~70 W (Ada) + ~200 W (Blackwell PRO 4500, full TDP) = ~270 W from PCIe + power connectors. PSU and cooling sized accordingly.
- **Thermal coupling** — two-slot cards stacked in adjacent slots run hotter; verify single-slot RTX 2000 Ada's airflow isn't choked by the PRO 4500 Blackwell next to it.

## Contributing

If you're running an NVIDIA Pro card in passthrough production (RTX A2000 / A4000 / A5000 / RTX 4000 Ada / 5000 Ada / 6000 Ada / RTX PRO Blackwell variants), please share your sanitized config. Professional-card recipes are underrepresented in the open source GPU-passthrough ecosystem — most guides focus on Consumer cards because that's what homelabbers have.
