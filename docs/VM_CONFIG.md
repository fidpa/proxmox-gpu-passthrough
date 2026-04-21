# VM Configuration

Per-VM settings for GPU passthrough. Vendor-specific quirks live in [vendors/](vendors/); this doc covers what's common across all vendors.

## Machine Model: q35

```bash
qm set <vmid> --machine q35 --bios ovmf
```

- **`q35`**: Required. `pc-i440fx` predates PCIe properly. Device gets assigned to a PCI bus instead of PCIe → missing features (ASPM, proper BAR mapping).
- **`ovmf`**: UEFI firmware. Required for modern GPUs; CSM/SeaBIOS doesn't expose the full VBIOS capability set.

## EFI Storage + TPM (for Windows guests)

```bash
qm set <vmid> --efidisk0 local-zfs:0,efitype=4m,pre-enrolled-keys=1,ms-cert=2023k
qm set <vmid> --tpmstate0 local-zfs:0,version=v2.0
```

`pre-enrolled-keys=1` is for fresh Windows installs (enrolls Microsoft's Secure Boot keys). For P2V imports of an existing Windows disk, use `pre-enrolled-keys=0` (the disk already has its own keys).

## Memory: Ballooning Off

```bash
qm set <vmid> --memory 24576 --balloon 0
```

**`balloon: 0` is mandatory with passthrough.** The balloon driver pages memory in/out as guest usage shifts — but the passed-through GPU has direct DMA access to guest memory via IOMMU. If balloon moves a page the GPU has DMA-mapped, you get silent memory corruption or VM crashes.

## Display: None

```bash
qm set <vmid> --vga none
```

- `vga: none` disables the emulated VGA adapter. The passed-through GPU is the only display.
- Side effect: Proxmox noVNC web console no longer works for this VM. Access via:
  - Physical monitor connected to the GPU's output
  - SPICE (see below)
  - RDP (Windows) / SSH (Linux) — most common

**Alternative — keep a small emulated display alongside**:
```bash
qm set <vmid> --vga virtio --hostpci0 0000:03:00,pcie=1
```
This gives you noVNC for emergency access but adds complexity (Windows sees two GPUs). Simpler to go `vga: none` and rely on RDP.

## CPU: Host Pass-Through

```bash
qm set <vmid> --cpu host --cores 8
```

`cpu: host` exposes all host CPU features to the guest. Required for modern instruction sets (AVX2, AVX-512) that drivers and workloads increasingly rely on.

## PCIe Assignment

```bash
qm set <vmid> --hostpci0 '0000:03:00,pcie=1'
qm set <vmid> --hostpci1 '0000:04:00,pcie=1'  # GPU audio companion, if present
```

Key switches:
- **`pcie=1`**: Attach as PCIe device, not PCI. Critical for q35.
- **`0000:03:00`** (no function suffix): Attaches all functions of the device. Equivalent to `0000:03:00.0` + `0000:03:00.1` + ... Use when the device has an audio companion at `.1`. If the audio companion is on a separate BDF (like Intel Arc: GPU at `03:00.0`, audio at `04:00.0`), use two `hostpciN` entries.
- **`x-vga=1`**: Set for the **primary** display-only GPU. Only needed when there's no emulated display and Windows must treat this as the primary. Not needed in most modern setups — omit unless you know you need it.
- **`romfile=`**: Explicit VBIOS file. Only needed if the card's onboard VBIOS can't be read by QEMU. Most modern GPUs don't need this.

## CPU Args (Vendor-Specific)

This is where the vendor-specific magic lives. Use the generator:

```bash
./scripts/generate-vm-args.sh --vendor intel-arc
./scripts/generate-vm-args.sh --vendor nvidia-consumer
./scripts/generate-vm-args.sh --vendor nvidia-pro
./scripts/generate-vm-args.sh --vendor amd
```

Default output is **raw** args (no `args: ` prefix), suitable for `qm set --args`:
```bash
qm set <vmid> --args "$(./scripts/generate-vm-args.sh --vendor intel-arc)"
```

Vendors that don't need custom args (`nvidia-consumer` on driver ≥ 465.89,
`nvidia-pro`, `amd`) print nothing to stdout — the `qm set --args ""` then
correctly applies no extra args. Rationale is emitted on stderr.

If you'd rather paste the result into the config file, use `--as-config-line`:
```bash
./scripts/generate-vm-args.sh --vendor intel-arc --as-config-line
# → "args: -cpu host,…"
```

See [vendors/](vendors/) for the rationale behind each vendor's flag set.

## Autostart / Startup Order

```bash
# Start on host boot, after any VM this GPU VM depends on
qm set <vmid> --onboot 1 --startup order=10,up=30
```

For a desktop VM you only fire up manually, leave `onboot: 0`.

## Complete Example

Intel Arc A310 passthrough on Proxmox VE 9.1. Replace `<vmid>` with your VM ID.

```bash
qm set <vmid> \
  --machine q35 \
  --bios ovmf \
  --efidisk0 local-zfs:0,efitype=4m,pre-enrolled-keys=1,ms-cert=2023k \
  --cpu host --cores 8 \
  --memory 24576 --balloon 0 \
  --scsi0 local-zfs:300,discard=on,iothread=1 \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr1 \
  --vga none \
  --hostpci0 '0000:03:00,pcie=1' \
  --hostpci1 '0000:04:00,pcie=1' \
  --agent enabled=1

# Vendor-specific args (Intel Arc — see vendors/intel-arc-dg2.md)
qm set <vmid> --args "$(./scripts/generate-vm-args.sh --vendor intel-arc)"

# Optional: reset-method hookscript (one device per invocation)
sudo ./scripts/install-reset-hook.sh <vmid> 03:00.0
```

## Sanity Check Before First Boot

```bash
qm config <vmid>
```

Checklist:
- [ ] `machine: q35`
- [ ] `bios: ovmf`
- [ ] `cpu: host`
- [ ] `balloon: 0`
- [ ] `vga: none` (or `virtio` with `x-vga=1` on hostpci)
- [ ] `hostpci0:` present with `pcie=1`
- [ ] `hostpci1:` for audio companion (if applicable)
- [ ] `args:` contains vendor-specific CPU flags (if vendor needs them)

Then:
```bash
qm start <vmid>
```

Next: guest driver install, per [vendors/](vendors/) recipe.
