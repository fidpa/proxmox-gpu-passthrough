# NVIDIA Professional (RTX A / RTX Ada / RTX PRO Blackwell / Quadro)

> 🚧 **Status**: In validation. Target hardware: **two Pro cards in one workstation** —
> **RTX 2000 Ada Generation (16 GB GDDR6 ECC)** as the Ada-generation reference (installed 2026-05-11),
> and **RTX PRO 4500 Blackwell (32 GB GDDR7)** as the Blackwell-generation reference (installed + passthrough active 2026-05-15).
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

- **Vendor:Device ID**: GPU `10de:28b0`, Audio companion `10de:22be` (AD107 High Definition Audio Controller) — confirmed from hardware 2026-05-11
- **Architecture**: Ada Lovelace (AD107), CUDA compute capability 8.9
- **TDP**: 70 W — low-profile, single-slot, no external power connector
- **VRAM**: 16 GB GDDR6 with ECC
- **PCIe**: 4.0 x8 (physical x16 slot)
- **Expected workload**: ML inference (smaller models, fp16 / int8 inference, classical CV)
- **Why included**: Reference point for the Ada Pro lineage; low TDP makes it the "always-on" card alongside the Blackwell PRO 4500.
- **Observed (2026-05-11)**: GPU was `(unbound)` on the Proxmox host out of the box — `nouveau` and `nvidiafb` listed as available modules but did not claim the device. The `softdep nouveau pre: vfio-pci` in `modprobe.d` is still recommended for robustness. Audio companion `02:00.1` had `snd_hda_intel` and required explicit unbind before VFIO could claim it.
- **Driver confirmed**: `nvidia-driver-595-server-open` (Ubuntu 24.04 guest, kernel 6.8.0-111-generic) — CUDA 13.2, `nvidia-smi` working inside Docker container via nvidia-container-toolkit 1.19.0. Note: open kernel modules are required for Ada Lovelace on this driver branch (same requirement as Blackwell, see below).
- **Container toolkit note**: Ubuntu 24.04 standard apt repos do **not** contain `nvidia-container-toolkit`. Must use NVIDIA's own apt repository (`nvidia.github.io/libnvidia-container`); the Ubuntu package appears to install but places no binaries.
- **Dual-GPU operation confirmed (2026-05-15)**: Both RTX 2000 Ada and RTX PRO 4500 passed through to the same VM simultaneously (separate `hostpci` slots). GPU assignment to Docker containers via `NVIDIA_VISIBLE_DEVICES` — see [Two-Card-One-Host](#two-card-one-host-considerations) below.
- **qm set must be run separately from vfio.conf**: Adding device IDs to `/etc/modprobe.d/vfio.conf` and rebooting binds the GPUs to vfio-pci on the host. But the VM doesn't see them until `qm set <vmid> -hostpciN <BDF>` is also run. These are two independent steps — a common source of confusion where host binding looks correct but VM config is missing the `hostpciN:` line.

## RTX PRO 4500 Blackwell — Hardware Notes (Blackwell-Generation Pro)

- **Vendor:Device ID**: GPU `10de:2c31`, Audio companion `10de:22e9` — confirmed from hardware 2026-05-15
- **Architecture**: Blackwell (GB203GL — workstation silicon)
- **VRAM**: 32 GB GDDR7 with ECC
- **PCIe**: 5.0 x16
- **TDP**: 200 W (requires external power connector — shipped with 600 W-rated 16-pin 12VHPWR/12V-2x6 cable)
- **Active workload**: ML inference (Ollama VLM — qwen3-vl:8b-instruct-q8_0 + qwen3-vl:32b-instruct-q4_K_M pre-loaded)
- **Why included**: Modern Blackwell silicon means it shares failure modes with **Consumer Blackwell cards** (ReBAR negotiation on 32 GB BAR, PCIe 5.0 link training) — but on the **Pro driver branch**, which avoids Code-43 flag-set entirely. Useful contrast for readers who otherwise have to triangulate between Consumer-Blackwell guides and Ada-Pro guides.
- **Observed (2026-05-15)**: GPU was unbound on host out of the box (no NVIDIA driver on Proxmox host). Audio companion `01:00.1` had `snd_hda_intel` — required explicit unbind before VFIO could claim it. IOMMU group 14 on AMD Raphael/Granite Ridge: clean, GPU + audio companion only.
- **Driver confirmed**: `nvidia-driver-595-server-open` (Ubuntu 24.04 guest, kernel 6.8.0-111-generic) — CUDA 13.2, `nvidia-smi` working inside Docker container via nvidia-container-toolkit 1.19.0. **Critical: closed-source driver (`nvidia-driver-595-server`) fails with `RmInitAdapter (0x22:0x56:1017)` — see below.**

### ⚠️ Blackwell Critical: Open Kernel Modules Required

Blackwell GPUs **do not work** with the proprietary NVIDIA kernel modules. The closed-source `nvidia.ko` fails to initialize Blackwell hardware:

```
NVRM: The NVIDIA GPU 0000:02:00.0 (PCI ID: 10de:2c31)
NVRM: installed in this system requires use of the NVIDIA open kernel modules.
NVRM: GPU 0000:02:00.0: RmInitAdapter failed! (0x22:0x56:1017)
```

`nvidia-smi` reports `No devices found` even with the module loaded. Fix: install `nvidia-driver-XXX-server-open` (or `nvidia-driver-XXX-open` for non-server builds). See [TROUBLESHOOTING.md § nvidia-smi reports "No devices found"](../TROUBLESHOOTING.md#nvidia-smi-reports-no-devices-found-linux-guest-blackwell--ada).

### Confirmed Quirks (Blackwell-Specific — still accumulating)

- **Open kernel modules mandatory** — confirmed critical, see above.
- **ReBAR on full 32 GB** — not yet verified; mainboard BIOS must map the full 32 GB BAR through the PCIe hierarchy; small-memory-map BIOSes silently fall back to 256 MB BAR with a massive perf hit. Verify with `lspci -vv -s <BDF>` showing the full BAR size, not the truncated fallback.
- **PCIe 5.0 link training** — not yet verified under sustained load; host slot must negotiate full PCIe 5.0 x16; under heavy thermal load some host/board combos drop to PCIe 4.0 / 3.0. Check with `lspci -vv` `LnkSta:` during workload.
- **GDDR7 ECC reporting** — not yet verified; `nvidia-smi -q -d ECC` should show ECC supported and active; default for Pro cards is usually enabled.

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

### Confirmed: Dual GPU to Same Linux VM — Docker Container Isolation

Tested configuration (2026-05-15): RTX PRO 4500 as `hostpci1` (GPU 0 in guest) + RTX 2000 Ada as `hostpci2` (GPU 1 in guest), both passed through to the same Ubuntu 24.04 VM. Both GPUs fully operational simultaneously.

**Container-level isolation via `NVIDIA_VISIBLE_DEVICES`**:

```yaml
# docker-compose.override.yml (pScan-specific, not committed to main repo)
services:
  ollama:          # Large VLM — needs high VRAM
    runtime: nvidia
    environment:
      NVIDIA_VISIBLE_DEVICES: "0"   # GPU 0 = RTX PRO 4500 Blackwell (32 GB)

  paddleocr:       # OCR inference — smaller footprint
    runtime: nvidia
    environment:
      NVIDIA_VISIBLE_DEVICES: "1"   # GPU 1 = RTX 2000 Ada (16 GB)
```

The guest sees GPUs in passthrough order (`hostpci1` → GPU 0, `hostpci2` → GPU 1). Each container sees only its assigned GPU; `nvidia-smi` inside the container shows one device. Cross-container GPU access is not possible without explicit `NVIDIA_VISIBLE_DEVICES: all`.

**Verification**:
```bash
# From host: confirm both GPUs have VRAM in use
nvidia-smi --query-gpu=index,name,memory.used --format=csv,noheader
# Expected:
# 0, NVIDIA RTX PRO 4500 Blackwell, NNNN MiB   ← Ollama loaded model
# 1, NVIDIA RTX 2000 Ada Generation, NNNN MiB  ← OCR models loaded
```

**WPR2 note**: The Blackwell WPR2 reset bug (see [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#nvidia-blackwell-gpu-failed-to-initialize-on-second-vm-start-wpr2-reset-bug)) applies to the RTX PRO 4500 in this setup. RTX 2000 Ada (Ada Lovelace) has not triggered the same issue — Ada appears more tolerant of PCIe FLR across VM restarts, though vendor-reset is still recommended as a precaution.

## Contributing

If you're running an NVIDIA Pro card in passthrough production (RTX A2000 / A4000 / A5000 / RTX 4000 Ada / 5000 Ada / 6000 Ada / RTX PRO Blackwell variants), please share your sanitized config. Professional-card recipes are underrepresented in the open source GPU-passthrough ecosystem — most guides focus on Consumer cards because that's what homelabbers have.
