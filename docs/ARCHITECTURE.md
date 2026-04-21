# Architecture — Why GPU Passthrough Breaks

This document explains the failure surfaces you hit when passing a PCIe GPU through to a VM. Each layer has its own set of gotchas. The vendor-specific recipes in [vendors/](vendors/) reference these as "Layer N" failures.

## The Five Layers

```
┌─────────────────────────────────────────────────────────┐
│ Layer 5 — Guest Driver                                  │
│          CPUID checks, WDDM interface negotiation,      │
│          vendor anti-VM checks, driver-side reset logic │
├─────────────────────────────────────────────────────────┤
│ Layer 4 — QEMU / KVM                                    │
│          -cpu flags, hv_* enlightenments, ACPI tables,  │
│          ROM injection, hidden-KVM spoofing             │
├─────────────────────────────────────────────────────────┤
│ Layer 3 — VFIO                                          │
│          PCI binding, BAR mapping, config-space emul,   │
│          interrupt remapping, reset_method              │
├─────────────────────────────────────────────────────────┤
│ Layer 2 — IOMMU Groups                                  │
│          Isolation boundaries, ACS support,             │
│          companion-device co-assignment                 │
├─────────────────────────────────────────────────────────┤
│ Layer 1 — Firmware / Hardware                           │
│          IOMMU enable, Above-4G decoding, ReBAR,        │
│          PCIe slot routing, CSM vs UEFI                 │
└─────────────────────────────────────────────────────────┘
```

Most online guides cover Layers 1-3 reasonably well. The interesting failures live in Layers 4 and 5 — which is where this repo focuses.

## Layer 1 — Firmware / Hardware

**Required BIOS/UEFI settings**:
- IOMMU: `Enabled` (Intel VT-d / AMD-Vi)
- Above 4G Decoding: `Enabled` (allows BAR mapping > 4 GB)
- Resizable BAR: `Enabled` (modern GPUs need full VRAM exposure)
- CSM: `Disabled` (UEFI-only)

**Failure signature**: `dmesg | grep -i iommu` shows "IOMMU disabled" or nothing at all.

## Layer 2 — IOMMU Groups

An IOMMU group is the smallest unit that can be passed through atomically. If your GPU shares a group with a USB controller, an SSD, or another GPU, **all of them** go to the VM together.

**Failure signatures**:
- `Could not assign device 0000:03:00.0, error -22` (EINVAL)
- VM boot, then host freezes (companion device was load-bearing for host)
- VM boots but NIC disappears from host

**Tools**:
- `./scripts/check-iommu-groups.sh` — list all groups + contents
- `pcie_acs_override=downstream,multifunction` kernel param — **use with caution**, breaks isolation

## Layer 3 — VFIO

VFIO is the kernel subsystem that unbinds a device from its host driver and makes it available to QEMU. Key knobs:

- `/etc/modprobe.d/vfio.conf` → `options vfio-pci ids=8086:56a6,8086:4f92`
- `softdep <vendor-driver> pre: vfio-pci` → ensures VFIO wins the binding race at boot
- `/sys/bus/pci/devices/<BDF>/reset_method` → controls how the device is reset before/after VM lifecycle

**Failure signatures**:
- `vfio-pci: not enough MMIO resources for MSI-X` — BAR ran out, check Above-4G
- `error: Inappropriate ioctl for device` on reset — driver doesn't support FLR/PM reset, use hookscript to force `/sys/.../reset_method`
- Host driver (`i915`, `nouveau`, `amdgpu`) stuck on GPU at boot — softdep ordering wrong

## Layer 4 — QEMU / KVM

QEMU launches the VM with a specific CPU model and a set of CPU flags. The guest driver reads these via CPUID and adjusts behavior. Two flag categories:

### Hypervisor-Hiding Flags

| Flag | What it hides |
|------|---------------|
| `kvm=off` | KVM signature (`KVMKVMKVM\0`) in CPUID leaf `0x40000000` |
| `-hypervisor` | Hypervisor-Running bit 31 in CPUID leaf `0x1` ECX |
| `hv_vendor_id=GenuineIntel` | Hyper-V vendor string → spoofed to look like bare-metal Intel |

Critically, **`kvm=off` alone is not sufficient**. The Hypervisor-Running bit in leaf `0x1` is a separate indicator; drivers that check both leaves independently (Intel Arc does) still detect virtualization even with `kvm=off`.

### Hyper-V Enlightenments

| Flag | Purpose |
|------|---------|
| `hv_relaxed` | Relaxed timing for Hyper-V paravirt clocks |
| `hv_spinlocks=0x1fff` | Tell guest to use Hyper-V spinlock enlightenment after 8191 spins |
| `hv_time` | Paravirt time source |
| `hv_synic` | Synthetic interrupt controller |

Ironically, some GPU drivers expect the **Hyper-V** enlightenments even when we're hiding KVM — because Windows itself uses them for scheduling, and if they're missing the driver gets stuck waiting for timer interrupts that arrive with wrong semantics.

**Failure signatures** (all in Event Viewer → DxgKrnl-Admin → Event 549):
- `E_NOINTERFACE` / "Schnittstelle wird nicht unterstützt" → Layer 4/5 boundary, usually hypervisor-bit visible
- `STATUS_UNSUCCESSFUL` → driver got further but still unhappy — missing enlightenment
- Timeout errors → reset_method issue (Layer 3)

## Layer 5 — Guest Driver

Where the vendor-specific drama lives. Three common patterns:

### Pattern A: Active Anti-VM Check (historical NVIDIA Consumer, pre-driver-465.89)

Driver explicitly checks for virtualization and refuses to initialize. Fixed by NVIDIA in **driver 465.89 (April 2021)** when GeForce GPU Passthrough (beta) officially landed. Some very old OEM driver bundles may still ship pre-465 drivers.

**Fix**: Hide the hypervisor (Layer 4 `kvm=off` + `-hypervisor`).

### Pattern B: WDDM Interface Mismatch (Intel Arc DG2)

Driver assumes it's on bare-metal and requests WDDM interface versions DxgKrnl doesn't expose under QEMU. Not a "block", but a fatal assumption.

**Fix**: Hide the hypervisor so the driver takes the bare-metal code path.

### Pattern C: Reset Bug (AMD Polaris/Navi)

Driver reset sequence leaves the GPU in an unreachable state between VM reboots. First VM boot works; subsequent starts fail until host reboot.

**Fix**: `vendor-reset` kernel module, or explicit reset sequence in hookscript.

### Pattern D: Paravirt-Assumption (NVIDIA Workstation)

Professional cards (RTX A/Pro/Ada) often *don't need* hypervisor-hiding at all — they work under KVM because they're marketed for virtualization. Overdoing the flags can actually cause issues (e.g. NVIDIA vGPU expects to see the hypervisor).

**Fix**: Start with minimal flags, add only what's needed.

## Reading the Vendor Recipes

Each vendor recipe in [vendors/](vendors/) specifies:
- Which **Layer 4 flags** are needed (often most of the complexity)
- Which **Layer 3 quirks** apply (reset_method, companion devices)
- Which **Layer 5 patterns** the driver exhibits (A/B/C/D above)
- Post-install verification via capability probe

Use the [TROUBLESHOOTING.md](TROUBLESHOOTING.md) matrix as the entry point when something breaks — it maps symptoms back to layers.

## Is Full Passthrough Even the Right Choice?

Full PCI(e)-passthrough is one of several ways to expose GPU capability to a VM. It's the right tool when a VM needs **exclusive**, **native-performance** access to a specific physical card — gaming, CAD, ML training, Windows-specific apps that demand real drivers. It's the wrong tool when you want to **share** a GPU across VMs, or when paravirt 2D/3D is sufficient.

Before committing to the full-passthrough path, consider the alternatives:

| Approach | When it fits | Not covered here because |
|----------|--------------|--------------------------|
| **VirtIO-GPU** (paravirt, QEMU-native) | 2D desktop acceleration, basic 3D via Virgil3D, multiple guests sharing transparently; no hypervisor hiding needed | Different failure modes — generic virt stack, not this repo's focus |
| **VirGL-GPU** (Linux guests only) | Multiple Linux VMs sharing host OpenGL rendering | Guest-OS-limited (Windows has no VirGL path) |
| **SR-IOV / vGPU / GVT-g / MxGPU** (mediated devices) | Splitting one enterprise GPU into multiple VFs, each assigned to a different VM | Scope is "full passthrough recipes"; see [Proxmox Wiki § Mediated Devices](https://pve.proxmox.com/wiki/MediatedDevices_(vGPU)) |
| **LXC container GPU** | AI inference / compute workloads that don't need a full guest OS (no Windows drivers, no desktop) | Different mechanism entirely (bind-mount `/dev/dri`, `/dev/nvidia*` etc.); see [Proxmox Wiki § LXC + GPU](https://pve.proxmox.com/wiki/PCI_Passthrough) |
| **Full PCI(e) passthrough** (this repo) | Gaming, CAD, Windows driver quirks, exclusive GPU access, ML-training VMs | — |

Rule of thumb: if you're **not** hitting driver-side anti-VM checks (Code 43), WDDM interface mismatches, or reset bugs, you probably don't need this repo — VirtIO-GPU or a mediated device is lighter-weight. If you **are** hitting those, welcome in.

Proxmox official reference: [pve.proxmox.com/wiki/PCI_Passthrough](https://pve.proxmox.com/wiki/PCI_Passthrough).
