# Intel Arc (DG2) — Full Recipe

> ✅ **Status**: Production (promoted 2026-05-15 — ≥2-week uptime threshold confirmed). Initial config verified 2026-04-20 on ASRock Intel Arc A310 Low Profile 4GB, Proxmox VE 9.1 kernel 6.17.x, Windows 11 Pro 25H2, Intel Graphics Driver 32.0.101.8629.

## TL;DR

Intel Arc DG2 (Alchemist: A310/A380/A580/A750/A770) passthrough to Windows **requires hiding the hypervisor bit** — `kvm=off` alone is not enough. The driver checks CPUID leaf `0x1` ECX bit 31 independently of the KVM vendor-string; without `-hypervisor`, WDDM interface negotiation fails with `E_NOINTERFACE` and Device Manager shows Code 43.

## Tested Matrix

| Host | Guest | Driver | Result |
|------|-------|--------|--------|
| Proxmox VE 9.1, kernel 6.17.13-2-pve | Windows 11 Pro 25H2 Build 26200 | Intel 32.0.101.8629 WHQL | ✅ Status OK, DX12 Ultimate, Vulkan 1.4.340 |

## Failure Modes This Recipe Prevents

| Symptom | Event | Root Cause |
|---------|-------|------------|
| Code 43 in Device Manager | DxgKrnl-Admin Event 549: `E_NOINTERFACE` | Driver sees Hypervisor-Running bit → requests WDDM interface DxgKrnl doesn't expose |
| Code 43 after partial fix | DxgKrnl-Admin Event 549: `STATUS_UNSUCCESSFUL` | KVM signature hidden but hypervisor bit still visible, or Hyper-V enlightenments missing |
| Device ends up as "Microsoft Basic Display Adapter" | Driver install succeeded but Windows didn't bind | Wrong INF installed — `iigd_dch.inf` is for iGPUs (Meteor Lake / Arrow Lake); DG2 needs `iigd_dch_d.inf` (`_d` = discrete) |
| Intel Graphics Installer exit code 7 "Install inhibited" | — | Installer refuses to run on a device currently showing Code 43 (catch-22; fix Code 43 first, then install) |

## Host Prep (Layer 1-3)

Standard [HOST_SETUP.md](../HOST_SETUP.md) applies. Arc-specific detail:

- The A310 presents **two functions**: GPU at `XX:00.0` and HDMI Audio at `XX:00.1` (same bus). Some boards route the audio to a separate BDF (e.g. `YY:00.0`). Check with `lspci -nn | grep -i "8086:4f"`.
- Both the GPU and its audio companion must be bound to vfio-pci:

```
# /etc/modprobe.d/vfio.conf
options vfio-pci ids=8086:56a6,8086:4f92
softdep i915 pre: vfio-pci
```

Vendor:device IDs for the A310 family:
- `8086:56a6` — Arc A310 GPU
- `8086:4f92` — DG2 Audio Controller (A310/A380 class)

Other DG2 cards (A580/A750/A770) have different GPU IDs (`56a0`, `56a1`, `5690`, `5691`, `5692`, `5693`) but the same audio controller family. Check your card with `lspci -nn`.

## VM Config

Standard [VM_CONFIG.md](../VM_CONFIG.md) settings apply. Arc-specific:
- `vga: none` (use RDP for remote access, physical monitor for direct)
- `balloon: 0`
- Two `hostpciN` entries: GPU at `0000:XX:00,pcie=1` and DG2 Audio at `0000:YY:00,pcie=1`

See [examples/intel-arc-a310/vm-config.example.conf](../../examples/intel-arc-a310/vm-config.example.conf) for a full `qm config` output.

## Code-43-Fix

### Symptom

Device Manager shows "Intel(R) Arc(TM) A310 Graphics" with warning triangle. Properties → General: `This device cannot start. (Code 43) CM_PROB_FAILED_POST_START`.

Event Viewer → `Applications and Services Logs → Microsoft → Windows → DxgKrnl → Admin` shows Event 549 (observed ID — Microsoft does not publish an official DxgKrnl event-ID reference, but the ID is consistent across all reported cases):

> Adapter start failed for VendorId (0x8086) DeviceId (0x56A6), status: **{Operation Failed} The requested operation was unsuccessful.**

Or:

> Adapter start failed, status: **The requested interface is not supported.**

### Root Cause

The Intel Arc Windows driver performs WDDM interface negotiation with `DxgKrnl` during `DdiStartDevice`. When CPUID reports a hypervisor is present, the driver falls into a code path that requests interface versions DxgKrnl doesn't expose under QEMU/KVM virtualization. This is **not** an active "no VMs allowed" check like older NVIDIA Consumer drivers — it's an architectural assumption that doesn't hold under virtualization.

### Fix

Add QEMU CPU args that hide KVM **and** the hypervisor bit:

```bash
qm set <vmid> --args '-cpu host,kvm=off,hv_vendor_id=GenuineIntel,-hypervisor,+kvm_pv_unhalt,+invtsc,hv_relaxed,hv_spinlocks=0x1fff'
```

Or use the generator:

```bash
qm set <vmid> --args "$(./scripts/generate-vm-args.sh --vendor intel-arc)"
```

### Flag Rationale

| Flag | Purpose | Necessary? |
|------|---------|-----------|
| `kvm=off` | Hide KVM signature in CPUID leaf `0x40000000` | **Required** |
| `-hypervisor` | Clear Hypervisor-Running bit in CPUID leaf `0x1` ECX bit 31 | **Required — this is the key** |
| `hv_vendor_id=GenuineIntel` | Spoof Hyper-V vendor string to look like bare-metal Intel | **Required** |
| `hv_relaxed,hv_spinlocks=0x1fff` | Hyper-V enlightenments the driver expects for timer coordination | Recommended (not isolated-tested as mandatory) |
| `+kvm_pv_unhalt,+invtsc` | Paravirt features for scheduling performance | Optional |

### Failure Evolution (for diagnosing partial fixes)

| Step | Args | DxgKrnl Event 549 |
|------|------|-------------------|
| 1. Baseline | `-cpu host` | `E_NOINTERFACE` — "The requested interface is not supported" |
| 2. Add KVM-hiding | `… ,kvm=off,hv_vendor_id=GenuineIntel,+kvm_pv_unhalt,+invtsc` | `STATUS_UNSUCCESSFUL` — error changed, driver progresses further |
| 3. Add hypervisor-bit hide | `… ,-hypervisor,hv_relaxed,hv_spinlocks=0x1fff` | **No error — Status OK, Code 0** |

Step 1 → 2 change in error message (from `E_NOINTERFACE` to `STATUS_UNSUCCESSFUL`) is your signal that `kvm=off` took effect but more is needed. Step 2 → 3 is where the device finally initializes.

### Why `kvm=off` Alone Doesn't Work

CPUID mechanics the Intel driver queries:

| CPUID | Field | Without Hiding | With `kvm=off` Only | With `kvm=off` + `-hypervisor` |
|-------|-------|----------------|---------------------|--------------------------------|
| `0x1` ECX Bit 31 | Hypervisor-Running flag | 1 (VM detected) | **1 (VM still detected!)** | 0 (looks like bare-metal) |
| `0x40000000` EAX | Hypervisor max leaf | `0x40000001` | 0 | 0 |
| `0x40000000` EBX/ECX/EDX | Vendor string | `KVMKVMKVM\0` | 0 | 0 |

The driver consults leaf `0x1` **independently** of leaf `0x40000000`. Hiding only the vendor string (what `kvm=off` does) leaves bit 31 set, and that's enough for the driver to know it's virtualized and pick the broken code path.

## Guest Driver Install

Intel ships the DG2 driver as a combined installer at <https://www.intel.com/content/www/us/en/download/785597/intel-arc-graphics-windows.html>. Tested version: **32.0.101.8629** WHQL (April 2026).

### Happy Path

1. Start VM with KVM-hiding args already applied (see Code-43-Fix)
2. Download `gfx_win_XX.X.XXX.XXXX_101_XXXX.exe`
3. Run — accept license, default options
4. Reboot when prompted
5. Device Manager → Intel(R) Arc(TM) A310 Graphics, Status OK, Code 0

### Fallback: Installer Exits 7 "Install inhibited"

If you somehow started the VM **without** the KVM-hiding args (e.g. first-try), the device shows Code 43. The Intel installer then refuses to run ("Install inhibited — this hardware is not supported"). Catch-22: you can't install the driver to fix the device, and you can't fix the device without the driver.

**Workaround** — apply args first, then if the installer still refuses, extract manually:

```powershell
# Install 7-Zip
iwr https://www.7-zip.org/a/7z2501-x64.exe -OutFile C:\7z.exe
Start-Process C:\7z.exe -ArgumentList '/S' -Wait

# Extract the Intel installer
& 'C:\Program Files\7-Zip\7z.exe' x C:\Users\<user>\Downloads\gfx_win_*.exe -oC:\gfx_extract

# Install the DG2-specific INF directly (not via installer)
pnputil /add-driver C:\gfx_extract\Graphics\iigd_dch_d.inf /install
```

### INF Gotcha: `iigd_dch_d.inf` vs `iigd_dch.inf`

The Intel driver package ships **two** INF files:

| INF | Target | Contains DEV_56A6? |
|-----|--------|-------------------|
| `iigd_dch.inf` | iGPU (Meteor Lake, Arrow Lake, Lunar Lake) | ❌ No |
| `iigd_dch_d.inf` | Discrete (DG2 Alchemist / Arc) — `_d` suffix = discrete | ✅ Yes |

If you install `iigd_dch.inf` by accident (alphabetical first in the folder), Windows doesn't find DEV_56A6 in the hardware-ID list and falls back to **Microsoft Basic Display Adapter**. Symptom: GPU is visible but stuck at 1024×768, no hardware acceleration.

**Fix**: uninstall the wrong INF, install `iigd_dch_d.inf`:

```powershell
# Identify which OEM file contains the wrong INF
pnputil /enum-drivers | Select-String -Pattern "iigd_dch" -Context 2,2

# Delete it (replace oemXX with the actual number)
pnputil /delete-driver oemXX.inf /uninstall /force

# Install the correct one
pnputil /add-driver C:\gfx_extract\Graphics\iigd_dch_d.inf /install

# Trigger re-enumeration
pnputil /scan-devices
```

#### Secondary Fallback: `/add-driver` ran but binding didn't happen

On a few Arc setups during the 2026-04-20 validation session, `pnputil
/add-driver … /install` **copied the INF into the Driver Store** without
actually binding it to the device — the GPU remained on Microsoft Basic
Display Adapter afterwards. In that case, force the binding via the
device's hardware ID:

```powershell
# Force pnputil to bind the INF to a specific hardware ID
# (Arc A310 = VEN_8086&DEV_56A6; check your card's ID with `pnputil /enum-devices /class Display`)
pnputil /update-driver 'PCI\VEN_8086&DEV_56A6' `
  "C:\gfx_extract\Graphics\iigd_dch_d.inf" /install

# Re-enumerate and verify
pnputil /scan-devices
Get-PnpDevice -Class Display | Select FriendlyName, Status, InstanceId
```

`/update-driver` (unlike `/add-driver`) takes a hardware-ID filter and forces
rebinding of any device matching it, even if the Driver Store already knows
the INF. This is the scripted equivalent of Device-Manager → Update Driver →
Browse → Pick from list.

### Vulkan ICD Registration (pnputil Gotcha)

If you installed the driver via `pnputil` (not the Intel installer), the Vulkan ICD is **not** registered in the Windows registry. `vulkan-1.dll` loads, can't find a driver, and applications fall back to software rendering or fail with `VK_ERROR_INCOMPATIBLE_DRIVER`.

The Intel full installer normally handles this; `pnputil` doesn't.

**Manual registration**:

```powershell
$driverDir = Get-ChildItem C:\Windows\System32\DriverStore\FileRepository\iigd_dch_d.inf_amd64_* -Directory | Select-Object -First 1
$icdPath = Join-Path $driverDir.FullName 'igvk64.json'

New-Item -Path 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers' -Name $icdPath -Value 0 -PropertyType DWord -Force

# Verify
& (Join-Path $driverDir.FullName 'vulkaninfo-64.exe') --summary
# Expected: "deviceName = Intel(R) Arc(TM) A310 Graphics", Vulkan 1.4.x
```

## Optional: Reset-Method Hookscript

If VM stop/start cycles produce noisy `Inappropriate ioctl for device` errors in `dmesg`, install the reset-method hookscript:

```bash
sudo ./scripts/install-reset-hook.sh <vmid> 03:00.0
```

The script installs one reset-method hook per invocation. If both the GPU
(`03:00.0`) and the DG2 Audio (`04:00.0`) trigger the `Inappropriate ioctl`
warning, run the installer twice (once per BDF).

Cosmetic — doesn't affect functionality, just cleans up journalctl.

## Capability Verification

After driver install, run the capability probe from the host side:

```bash
./scripts/capability-probe.sh <vmid>
# Or directly inside the VM:
powershell.exe -File scripts/capability-probe.ps1
```

Expected output (Arc A310 sanity check):

| Metric | Expected |
|--------|----------|
| Status | OK |
| ConfigManagerErrorCode | 0 |
| DriverVersion | 32.0.101.8629 or newer |
| Feature Level | 12_2 (DirectX 12 Ultimate) |
| DDI Version | 12 |
| Driver Model | WDDM 3.2 |
| Dedicated Memory (from dxdiag) | 4002 MB |
| Vulkan API | 1.4.x |

> **`AdapterRAM` via WMI is a 32-bit field** — tools report ~2 GB (`2147479552` = signed int32 ceiling, what `Get-CimInstance Win32_VideoController` returns here) or up to ~4 GB (unsigned uint32), depending on how they interpret the value. Either way, **it is not the real VRAM size** for any GPU with more than 2 GB. Canonical replacement: call DXGI directly (`IDXGIAdapter1::GetDesc1 → DedicatedVideoMemory` — see `scripts/capability-probe.ps1` section 3a for a PowerShell P/Invoke implementation). As a fallback without P/Invoke: `dxdiag /t file.txt` → "Dedicated Memory:" line.

## Known Limitations

| Feature | Status | Why |
|---------|--------|-----|
| Hardware Accelerated GPU Scheduling (HAGS) | Off (Block List: `DISABLE_HWSCH`) | Intel blocks HAGS in paravirt environments — minimal performance impact |
| Intel Graphics Command Center | Not installed by pnputil path | MSIX app must be installed separately via MS Store if wanted |
| Miracast | Not supported in VM | No display transport path |

## What's NOT the Fix (Don't Waste Time On These)

Things I tried that turned out to be irrelevant to Code 43:

| Attempted | Result |
|-----------|--------|
| VBIOS `romfile=` | Not needed — card subsystem initializes itself |
| `x-vga=1` | Irrelevant for dGPU (only matters for iGPU-primary scenarios) |
| BAR2 Resize 256 MB ↔ 4 GB | ReBAR tuning — doesn't touch driver init |
| Reset-Method Hookscript | Cosmetic, not a fix for Code 43 |
| Old driver deep-clean (DDU, pnputil purge) | Was already clean; no interference |
| `iigd_dch.inf` vs `iigd_dch_d.inf` | Separate issue (MBDA fallback), not Code 43 |

All of these are either necessary for other reasons or totally orthogonal. The actual fix is the three CPUID flags: `kvm=off`, `-hypervisor`, `hv_vendor_id=GenuineIntel`.
