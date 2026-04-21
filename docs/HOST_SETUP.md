# Host Setup — Proxmox VE IOMMU + VFIO

One-time preparation of the Proxmox host. After completing these steps, the GPU is ready to be assigned to any VM via `hostpci0`. Actual per-VM configuration is in [VM_CONFIG.md](VM_CONFIG.md).

## Prerequisites

- Proxmox VE 8.x or 9.x installed
- BIOS/UEFI settings verified:
  - IOMMU: **Enabled** (Intel VT-d / AMD-Vi)
  - Above 4G Decoding: **Enabled**
  - Resizable BAR: **Enabled** (recommended for GPUs with ≥4 GB VRAM)
  - CSM / Legacy Boot: **Disabled** (UEFI-only)

## Step 1 — Enable IOMMU in the Kernel

**Recommended path** — the helper auto-detects CPU vendor (Intel/AMD) and bootloader (GRUB vs. `proxmox-boot-tool` on systemd-boot, which is the default on modern Proxmox 9.x UEFI installs):

```bash
sudo ./scripts/enable-iommu.sh --apply
sudo reboot
```

Default is dry-run; `--apply` writes the cmdline and refreshes the bootloader. Re-running is idempotent — already-present flags are detected.

**Manual fallback** — if you prefer to edit by hand, edit `/etc/default/grub`:

```bash
# Intel
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"

# AMD
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
```

`iommu=pt` (passthrough mode) is the default on modern kernels but explicit is better than implicit.

Apply:

```bash
update-grub
# Proxmox also triggers proxmox-boot-tool refresh automatically
reboot
```

On systemd-boot setups the equivalent is editing `/etc/kernel/cmdline` and running `proxmox-boot-tool refresh`.

Verify after reboot:

```bash
dmesg | grep -i "IOMMU enabled"
# Expected:
#   DMAR: IOMMU enabled                 (Intel)
#   AMD-Vi: AMD IOMMUv2 loaded          (AMD)
```

## Step 2 — Configure VFIO Module Loading

Create `/etc/modules-load.d/vfio.conf`:

```
vfio
vfio_iommu_type1
vfio_pci
```

This ensures the VFIO modules load at boot (before any driver that might claim the GPU).

## Step 3 — Claim the GPU for VFIO

Create `/etc/modprobe.d/vfio.conf` with the vendor:device IDs of your GPU and its companion devices:

```
# Replace with your own IDs from `lspci -nn`
options vfio-pci ids=8086:56a6,8086:4f92

# Prevent the host driver from claiming the GPU before VFIO
softdep i915 pre: vfio-pci        # Intel
softdep nouveau pre: vfio-pci     # NVIDIA (if nouveau is loaded)
softdep amdgpu pre: vfio-pci      # AMD
```

> **Alternative**: Blacklist the host driver entirely (`blacklist i915`). Only do this if you have no other use for the host driver — e.g. if the passthrough GPU is the only Intel GPU and you don't need iGPU for the Proxmox host console. Most users prefer `softdep`, which leaves the driver available but yielded to VFIO.

## Step 4 — Regenerate initramfs

```bash
update-initramfs -u -k all
reboot
```

## Step 5 — Verify VFIO Binding

After reboot:

```bash
# Should show "Kernel driver in use: vfio-pci"
lspci -nnk -s <BDF>

# Example:
lspci -nnk -s 03:00
# 03:00.0 VGA compatible controller [0300]: Intel Corporation DG2 [Arc A310] [8086:56a6]
#     Subsystem: ...
#     Kernel driver in use: vfio-pci
#     Kernel modules: i915
```

Alternatively, use the helper:

```bash
./scripts/check-vfio-binding.sh 03:00.0
```

## Step 6 — Check IOMMU Groups

```bash
./scripts/check-iommu-groups.sh
```

**What to look for**:
- GPU (`03:00.0`) should be in its own group or only grouped with its own companions (audio, USB-C controller)
- Companions (`03:00.1`, `04:00.0`) must **all** go to VFIO — if one of them is stuck on host driver, passthrough fails with `-22` EINVAL

**If group contains unrelated devices** (USB controller, NIC, SATA):
1. First check: is your GPU in a PCIe slot routed through the CPU or the chipset? CPU-routed slots usually have cleaner groups.
2. If still problematic, `pcie_acs_override=downstream,multifunction` can split groups — but **this breaks isolation**. Document it in your own infrastructure and only use it for homelab / lab scenarios, never in multi-tenant production.

## Step 7 — (Optional) Install Reset-Method Hookscript

Some GPUs fail the default Proxmox reset sequence with `Inappropriate ioctl for device`. Harmless but noisy. If you see it:

```bash
sudo ./scripts/install-reset-hook.sh <vmid> <BDF> [RESET_METHOD]
# Example — GPU only:
sudo ./scripts/install-reset-hook.sh 102 03:00.0
# RESET_METHOD defaults to "bus"; override with flr, pm, device_specific
# if your device reports a different working method in reset_method sysfs.
```

> The script handles **one device per invocation** by design (Unix "do one
> thing well"). If your passthrough pulls a companion (GPU + audio on
> separate BDFs), the Proxmox reset path typically only complains about the
> GPU — start with that one. If the companion also logs reset warnings,
> run `install-reset-hook.sh` again for it; both hook entries coexist.

This installs a hookscript at `/var/lib/vz/snippets/` that writes the chosen reset method into `/sys/bus/pci/devices/<BDF>/reset_method` before VM start, so Proxmox skips the problematic ioctl.

## Step 8 — Proceed to VM Configuration

Host is now ready. See [VM_CONFIG.md](VM_CONFIG.md) for per-VM setup, or jump directly to the vendor-specific recipe:
- [vendors/intel-arc-dg2.md](vendors/intel-arc-dg2.md) ✅ (also serves as the Consumer-tier reference)
- [vendors/nvidia-professional.md](vendors/nvidia-professional.md) 🚧 (RTX 2000 Ada + RTX PRO 4500 Blackwell)
- [vendors/amd.md](vendors/amd.md) 📋 (backlog)
- [vendors/nvidia-consumer.md](vendors/nvidia-consumer.md) 📋 (contributor stub — Consumer-tier already covered by Intel Arc above)

## Common Host-Setup Failures

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `dmesg` shows no IOMMU messages | IOMMU disabled in BIOS | Enable VT-d / AMD-Vi in firmware |
| `lspci -nnk` shows GPU on `i915` / `nouveau` / `amdgpu` after reboot | `softdep` ordering lost or initramfs not regenerated | `update-initramfs -u -k all` + reboot |
| VM start: `Could not assign device ... -22` (EINVAL) | IOMMU group has device still on host driver | `lspci -nnk` all devices in group, bind all to vfio-pci |
| VM start: `vfio-pci: not enough MMIO resources` | Above 4G decoding disabled | Enable in BIOS |
| Host freezes when VM starts | Companion device in group was load-bearing (NIC, SATA) | Different PCIe slot, or ACS override with caveats |
