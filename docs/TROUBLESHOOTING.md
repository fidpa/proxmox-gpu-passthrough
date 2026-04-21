# Troubleshooting Matrix

Symptom-driven entry point. Find your symptom, jump to the fix.

## Code 43 (Device Manager — Windows Guest)

| Vendor | Root Cause | Fix |
|--------|-----------|-----|
| Intel Arc (DG2) | Driver reads CPUID Hypervisor-Running bit (leaf `0x1` ECX bit 31) + Hyper-V Vendor-String | Add `kvm=off,-hypervisor,hv_vendor_id=GenuineIntel` to QEMU args — see [intel-arc-dg2.md § Code-43-Fix](vendors/intel-arc-dg2.md#code-43-fix) |
| NVIDIA Consumer (driver ≥ 465.89, April 2021+) | **Should not happen** | Check driver version — older driver needs `kvm=off`; new driver supports passthrough natively |
| NVIDIA Consumer (driver < 465.89) | Active anti-VM check | Upgrade driver; interim fix `-cpu host,kvm=off,hv_vendor_id=GenuineIntel` |
| NVIDIA Pro / Ada | Shouldn't happen | Verify you're using NVIDIA Pro/RTX Enterprise driver, not mistakenly Consumer Game Ready |
| AMD | Rarely Code 43 specifically; more likely reset-failure | See "Host hangs on second VM start" below |

## DxgKrnl-Admin Event 549 (Windows)

> Event ID 549 is an observed value in Microsoft-Windows-DxgKrnl/Admin.
> Microsoft does not publish an official event-ID reference for this channel,
> but the ID has been consistent across all reported Arc-DG2 Code-43 cases.

| Message | Root Cause | Fix |
|---------|-----------|-----|
| `E_NOINTERFACE` / "Schnittstelle nicht unterstützt" | Hypervisor visible to driver, WDDM interface mismatch | Add `-hypervisor` to QEMU args (not just `kvm=off`) |
| `STATUS_UNSUCCESSFUL` / "Vorgang fehlgeschlagen" | KVM hidden but Hyper-V enlightenments missing | Add `hv_relaxed,hv_spinlocks=0x1fff` |
| `STATUS_TIMEOUT` | PCI reset failed, device didn't respond | Install reset-method hookscript |

## Device Shows as "Microsoft Basic Display Adapter"

| Vendor | Likely Cause | Fix |
|--------|-------------|-----|
| Intel Arc | Wrong INF installed (`iigd_dch.inf` for iGPU instead of `iigd_dch_d.inf` for discrete) | `pnputil /delete-driver oemXX.inf /uninstall /force` + reinstall `iigd_dch_d.inf` — see [intel-arc-dg2.md § INF Gotcha](vendors/intel-arc-dg2.md#inf-gotcha-iigd_dch_dinf-vs-iigd_dchinf) |
| Any | Driver install failed silently | Check `pnputil /enum-drivers`, re-run installer with logging |
| Any | Device has Code 43 — Windows falls back to basic driver | Fix Code 43 first (see above) |

## VM Won't Start — Proxmox Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Could not assign device 0000:XX:00.X, error -22` | IOMMU group contains device still bound to host driver | `./scripts/check-iommu-groups.sh` — bind all group members to vfio-pci |
| `vfio-pci: not enough MMIO resources for MSI-X` | Above 4G Decoding disabled in BIOS | Enable in firmware, reboot |
| `error writing '1' to /sys/.../reset: Inappropriate ioctl for device` | GPU doesn't support Proxmox's default reset method | Install reset-method hookscript — see [HOST_SETUP.md § Step 7](HOST_SETUP.md#step-7--optional-install-reset-method-hookscript) |
| `failed to initialize device in group N` | Companion device (audio, USB-C controller) not bound to vfio-pci | Add all companion vendor:device IDs to `/etc/modprobe.d/vfio.conf` |

## Host Hangs on Second VM Start

Typically **AMD Reset Bug**. The GPU was left in an unreclaimable state after the first VM shutdown.

| GPU Family | Fix |
|------------|-----|
| AMD Polaris (RX 4xx/5xx) | Install [vendor-reset](https://github.com/gnif/vendor-reset) kernel module |
| AMD Navi (RX 5xxx) | Install `vendor-reset` (Navi-specific reset sequence) |
| AMD RDNA 2+ (RX 6xxx/7xxx) | Usually better behaved, but `vendor-reset` still recommended |
| Intel / NVIDIA | Not a Reset Bug — check dmesg for specific error |

## Wrong VRAM Reported

| Tool | Reports | Reality |
|------|---------|---------|
| WMI `Win32_VideoController.AdapterRAM` | 32-bit field; tools show ~2 GB (signed int32, e.g. `2147479552`) or ~4 GB (unsigned uint32) depending on interpretation | 32-bit WMI field limit — **not real VRAM** for any card >2 GB |
| Device Manager → Properties → Adapter | Varies | Driver-reported, usually correct |
| DXGI `IDXGIAdapter1::GetDesc1 → DedicatedVideoMemory` (P/Invoke) | Actual value as `SIZE_T` (64-bit on x64) | **Authoritative** — no field-width caps, no external-tool dependency (see `scripts/capability-probe.ps1` section 3a) |
| `dxdiag /t file.txt` → `Dedicated Memory:` | Actual value | Authoritative fallback when P/Invoke isn't an option |
| NVIDIA `nvidia-smi` (in VM) | Actual value | Authoritative for NVIDIA |

Prefer DXGI (or vendor tool); `dxdiag` is the fallback; `Win32_VideoController.AdapterRAM` is never reliable for cards >2 GB.

## Vulkan Applications Can't Find GPU

| Vendor | Symptom | Fix |
|--------|---------|-----|
| Intel Arc (pnputil-installed) | `VK_ERROR_INCOMPATIBLE_DRIVER`, `vulkaninfo` says "Devices: 0" | Manually register ICD — see [intel-arc-dg2.md § Vulkan ICD Registration](vendors/intel-arc-dg2.md#vulkan-icd-registration-pnputil-gotcha) |
| NVIDIA | `vulkan-1.dll` not found | Driver didn't install System32 Vulkan loader — reinstall NVIDIA driver |
| Any | ICD registered but Vulkan apps still fail | Check `HKLM\SOFTWARE\Khronos\Vulkan\Drivers` has entry pointing to existing JSON |

## Resolution Stuck at 1024×768 or 800×600

Almost always "GPU shows as Microsoft Basic Display Adapter" (see above). Fix the driver binding; real resolution follows.

## Guest Performance Much Lower Than Bare-Metal

| Cause | Diagnostic | Fix |
|-------|-----------|-----|
| ReBAR not exposed | `dxdiag` shows VRAM < 4 GB on a 4+ GB card | Enable Resizable BAR in host BIOS; verify with `lspci -vv -s <BDF>` showing full BAR size |
| CPU not `host` model | `qm config <vmid>` shows different `--cpu` | `qm set <vmid> --cpu host` |
| Ballooning active | `qm config <vmid>` shows `balloon: <non-zero>` | `qm set <vmid> --balloon 0` |
| IO Thread disabled on storage | slow disk IO while GPU idle | `qm set <vmid> --scsi0 ...,iothread=1` |
| Memory fragmentation (huge pages) | Inconsistent performance | Enable `hugepages` via Proxmox config or kernel boot |

## GPU Fans Spin Full Speed

Fan controller usually lives on the GPU itself and is driven by the guest driver. On first boot with no driver loaded, fans may default to 100%. Should normalize once driver loads.

If fans stay full after driver loads:
- **NVIDIA**: driver fan curve might not apply; check GPU-Z / nvidia-smi for temperature
- **Intel Arc**: known issue on some boards with BIOS-side fan control conflicting with driver; usually resolves after one VM reboot
- **AMD**: check for `vendor-reset` leaving GPU in weird state

## Still Stuck?

1. Run `./scripts/collect-diagnostics.sh <vmid>` — bundles IOMMU groups, VFIO state, VM config, dmesg
2. Open an issue with the bundle attached (sanitize IPs/hostnames first)
3. Check [Proxmox Forum PCI Passthrough category](https://forum.proxmox.com/forums/pci-passthrough.117/) — lots of historical threads
4. For AMD: [Level1Techs Forum VFIO category](https://forum.level1techs.com/c/software/linux/vfio-passthrough)
