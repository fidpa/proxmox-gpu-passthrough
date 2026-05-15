# Example: NVIDIA RTX PRO 4500 Blackwell Passthrough

Placeholder slot for the NVIDIA RTX PRO 4500 Blackwell (Professional / Workstation, Blackwell silicon, 32 GB GDDR7 ECC) passthrough recipe — will land here once the card has run an ML-inference workload for ≥2 weeks.

> **Status**: 🚧 **In validation** — hardware installed 2026-05-15, passthrough active, ≥2-week production uptime accumulating under real ML-inference (Ollama VLM, qwen3-vl:8b-instruct-q8_0).
> Promotes to ✅ once the ≥2-week threshold ([CONTRIBUTING.md § 1](../../CONTRIBUTING.md#1-no-vendor-recipe-without-2-weeks-production)) is met.

## Why Still a Placeholder

This repo's rule is **no vendor recipe without ≥2 weeks of production validation on real hardware** (see [CONTRIBUTING.md](../../CONTRIBUTING.md)). The first session (2026-05-15) confirmed the passthrough works and the config shape below is correct. The full recipe lands here once ≥2 weeks of ML-inference workload have elapsed.

## ⚠️ Blackwell Critical: Open Kernel Modules Required

**The most important Blackwell-specific finding before anything else:**

Blackwell GPUs (GB2xx/GB3xx — including the RTX PRO 4500 GB203GL) **do not work with the proprietary NVIDIA kernel modules**. If you install the standard closed-source driver package (`nvidia-driver-XXX-server` on Ubuntu, or any non-open variant), you will see:

```
NVRM: The NVIDIA GPU 0000:02:00.0 (PCI ID: 10de:2c31)
NVRM: installed in this system requires use of the NVIDIA open kernel modules.
NVRM: GPU 0000:02:00.0: RmInitAdapter failed! (0x22:0x56:1017)
NVRM: GPU 0000:02:00.0: rm_init_adapter failed, device minor number 0
```

`nvidia-smi` will report `No devices found` even though the kernel module is loaded. The fix:

```bash
# Ubuntu 24.04 — install the open kernel module variant
sudo apt install nvidia-driver-595-server-open
# (replaces nvidia-driver-595-server; DKMS builds the open module automatically)

# Unload old closed modules, load new open ones (or just reboot the VM)
sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia
sudo modprobe nvidia
```

This requirement applies to **all** Blackwell GPUs in Linux guests, not just Pro cards. The open kernel modules (`nvidia-open`) have been mandatory for Ada Lovelace and newer since NVIDIA deprecated proprietary modules for those architectures.

See also: [TROUBLESHOOTING.md § nvidia-smi reports "No devices found"](../../docs/TROUBLESHOOTING.md#nvidia-smi-reports-no-devices-found-linux-guest-blackwell--ada).

## Confirmed Config Shape

Validated on Proxmox VE 9.1.1 / kernel 6.17.2-1-pve, AMD Ryzen 9 9900X host, Ubuntu 24.04 guest (kernel 6.8.0-111-generic):

```
args: (none -- Pro cards do NOT need kvm=off / -hypervisor)
machine: q35
bios: ovmf
cpu: host
balloon: 32768
vga: none
hostpci1: 0000:01:00,pcie=1
```

Notes on the config:
- **`hostpci1` not `hostpci0`**: In this setup `hostpci0` was already in use (NVMe passthrough). The index is arbitrary — use whatever slot is free.
- **No function suffix**: `0000:01:00` (without `.0`) attaches all functions — GPU (`01:00.0`, `10de:2c31`) + audio companion (`01:00.1`, `10de:22e9`) — in a single line.
- **No `x-vga`**: Card is used headless for ML inference. `x-vga=0` is implicit (and default) when `vga: none` is set.
- **`cpu: host`**: mandatory for CUDA workloads.
- **No extra `-cpu` flags**: Pro cards expect to see KVM. Do not apply Consumer Code-43 workarounds.

Guest-side driver: `nvidia-driver-595-server-open`, nvidia-container-toolkit 1.19.0, CUDA 13.2.

## Confirmed Hardware IDs

| Function | PCI ID | Description |
|----------|--------|-------------|
| GPU | `10de:2c31` | GB203GL — RTX PRO 4500 Blackwell |
| Audio | `10de:22e9` | NVIDIA Blackwell HD Audio companion |

IOMMU group (AMD Ryzen 9 9900X / Granite Ridge platform): **clean isolated group**, GPU + audio companion only. No other devices share the group.

## vfio.conf

```
# /etc/modprobe.d/vfio.conf
options vfio-pci ids=10de:2c31,10de:22e9
softdep snd_hda_intel pre: vfio-pci
softdep nouveau pre: vfio-pci
```

**Audio companion note**: the audio companion (`10de:22e9`) had `snd_hda_intel` bound on first boot. The `softdep snd_hda_intel pre: vfio-pci` line prevents this on subsequent boots. For a live bind without reboot:

```bash
echo 0000:01:00.1 > /sys/bus/pci/drivers/snd_hda_intel/unbind
# If the GPU IDs aren't yet known to the running vfio-pci module:
echo "10de 2c31" > /sys/bus/pci/drivers/vfio-pci/new_id
echo "10de 22e9" > /sys/bus/pci/drivers/vfio-pci/new_id
# Verify
for dev in 0000:01:00.0 0000:01:00.1; do
  echo "$dev → $(basename $(readlink /sys/bus/pci/devices/$dev/driver))"
done
```

Note: `echo <BDF> > /sys/bus/pci/drivers/vfio-pci/bind` fails with "No such device" if the device ID was not known to the running module instance (the IDs in `/etc/modprobe.d/vfio.conf` are only parsed at module load time). Use `new_id` for the live case.

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
