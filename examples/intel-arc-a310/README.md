# Example: Intel Arc A310 Passthrough

Sanitized Proxmox VM configuration for an Intel Arc A310 (DG2) passed through to Windows 11 — including the `args:` line that defeats the driver's CPUID check (Error 43).

> **Status**: 🚧 In validation — initial config verified 2026-04-20; promotes to ✅ on 2026-05-04 when the ≥2-week uptime threshold ([CONTRIBUTING.md § 1](../../CONTRIBUTING.md)) is met.

## What's in here

- `vm-config.example.conf` — sanitized Proxmox VM config (`/etc/pve/qemu-server/<vmid>.conf` equivalent). Shows the *complete* file, not just the passthrough lines, so you can see how the `args:` interacts with `machine:`, `cpu:`, `balloon:`, `vga:`, `hostpci0:` etc.

## How to adapt

1. Copy the file to `/etc/pve/qemu-server/<your-vmid>.conf` (after stopping the VM).
2. Replace `0000:03:00.0` with **your** GPU's BDF (find via `lspci -nn | grep -i VGA`).
3. Adjust `memory:`, `cores:`, and disk lines to your host.
4. Generate EFI/TPM state disks if you don't already have them:
   ```
   qm set <vmid> --efidisk0 local-lvm:0,pre-enrolled-keys=1,efitype=4m
   qm set <vmid> --tpmstate0 local-lvm:0,version=v2.0
   ```
5. Start the VM. Install Windows, then install the Intel Arc driver (`iigd_dch_d.inf`, NOT `iigd_dch.inf` — see [vendors/intel-arc-dg2.md § INF Gotcha](../../docs/vendors/intel-arc-dg2.md#inf-gotcha-iigd_dch_dinf-vs-iigd_dchinf)).

## Validation

Run [scripts/capability-probe.ps1](../../scripts/capability-probe.ps1) inside the guest after driver install. Expected output:
- `PnP Status: OK` for the Intel Arc adapter
- `Feature Levels: 12_2`
- `Dedicated Memory: 4002 MB` (for 4 GB A310)
- Vulkan: ICD present, at least one device listed

If Vulkan ICD is empty, register it manually — see [vendors/intel-arc-dg2.md § Vulkan ICD Registration](../../docs/vendors/intel-arc-dg2.md#vulkan-icd-registration-pnputil-gotcha).

## What this example does NOT include

- `hookscript:` line (A310 has a working FLR reset; no hookscript needed)
- `romfile=` (not needed on Arc A310, sometimes needed for older NVIDIA)
- `x-vga=1` (A310 works better as secondary/non-x-vga)

If you need any of those for your specific hardware, see the main [VM_CONFIG.md](../../docs/VM_CONFIG.md).

## See Also

- [../../docs/vendors/intel-arc-dg2.md](../../docs/vendors/intel-arc-dg2.md) — Full Arc A310 recipe (Code-43-Fix, INF gotcha, Vulkan ICD)
- [../../docs/VM_CONFIG.md](../../docs/VM_CONFIG.md) — VM-side options (machine type, OVMF, hookscripts)
- [../../docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md) — Symptom-driven matrix for all vendors
- [../nvidia-rtx-2000-ada/](../nvidia-rtx-2000-ada/) · [../nvidia-rtx-pro-4500-blackwell/](../nvidia-rtx-pro-4500-blackwell/) — Planned sibling recipes (NVIDIA Pro: Ada + Blackwell, ML-inference workload)
- [../nvidia-consumer-blackwell/](../nvidia-consumer-blackwell/) — Backlog stub for NVIDIA-GeForce-specific quirks (Consumer-tier passthrough is already demonstrated by *this* Arc A310 recipe)
