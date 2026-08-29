# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Extend the `collect-diagnostics.sh` sanitizer to mask IPv4/IPv6 addresses, hardware and BIOS UUIDs, and usernames in paths, once enough real-world diagnostic bundles surface the common patterns.
- Publish the outstanding NVIDIA Pro measurements: ECC status (`nvidia-smi -q -d ECC`), CUDA and NVENC benchmarks for both cards, and, Blackwell-specific, full 32 GB BAR exposure and PCIe 5.0 link width under sustained load.
- A `vendor-reset` installation guide for the Blackwell WPR2 reset bug, once Blackwell support in `gnif/vendor-reset` is confirmed.

## [1.3.1] - 2026-08-30: The README describes what the scripts actually do

A pass over `README.md` against the code it describes, prompted by the same question
the 1.3.0 changelog pass asked: does every sentence still hold. Three did not. The
hookscript was described as clearing `reset_method` when it writes a token into it, the
capability probe was credited to `dxdiag` for a number it reads through DXGI, and the
`check-iommu-groups.sh` sample output in the Quick Start had a format the script does
not produce. Three of the nine scripts had no mention in the README at all. No code,
script, or documentation file outside `README.md` changed.

### Changed
- **The README no longer describes the reset hookscript as clearing `reset_method`.** `hookscripts/reset-method.sh` writes a token into `/sys/bus/pci/devices/<BDF>/reset_method` (`flr`, `bus`, `pm` or `device_specific`, default `bus`); it never clears the file. The old wording sent readers looking for a behaviour the script does not have.
- **The capability probe's VRAM source is named correctly.** `capability-probe.ps1` reads `DXGI_ADAPTER_DESC1.DedicatedVideoMemory` by P/Invoke and falls back to `dxdiag`; the README credited `dxdiag` for the number. The WMI note now says what is actually wrong with `AdapterRAM` (a 32-bit field) instead of quoting a 2 GB cap.
- **The two sample outputs in the Quick Start are the outputs the scripts produce.** `check-iommu-groups.sh` prints `IOMMU Group <n>:` with one indented line per device carrying BDF, bound driver and `lspci -nn` text; the README showed a shorter invented format. `generate-vm-args.sh --vendor intel-arc` now appears with its full flag list instead of a trailing ellipsis.
- **A `Scripts` section documents all nine scripts and the hookscript with their usage lines.** `capability-probe.sh`, `collect-diagnostics.sh` and `install-reset-hook.sh` shipped undocumented in the README. The section replaces the former `Features` list, whose six bullets described four of the scripts under invented product names. The `collect-diagnostics.sh` row states what the sanitizer leaves untouched.
- **The `Roadmap` section is now `Open Findings and Backlog` and no longer repeats the GPU table.** Promotion dates and production workloads stand once, in `Supported GPUs`; what remains open (Blackwell WPR2, ReBAR and PCIe 5.0 verification, AMD hardware) stands once, below it.
- **Em dashes, arrows and the `>=` sign are gone from the README**, as they went from this changelog in 1.3.0. The status emoji stay, since the vendor docs and examples use them as the same table markers.
- **Prose reworked away from template shapes.** The `**The Problem**:` and `**Why I Built This**:` labels are gone, the five-claim opening paragraph is split, and the `Provenance` section no longer opens by announcing its own honesty. The scope rule for the GPU table is stated as a rule rather than as a discipline claim.
- **The README links `examples/` and `docs/vendors/nvidia-consumer.md` from the documentation table.** Both existed in the repository without a path from the front page.

## [1.3.0] - 2026-08-27: Release notes match the tags they are published under

Editorial pass over all five published sections, checked against the tags each one
describes and corrected where the repository contradicted the text. No code, script, or documentation
file outside this changelog changed, with one exception noted below: `release.yml` now
derives the release title from the section heading, so the titles on GitHub stay in step
with this file instead of repeating the version number.

Every measured value, file path, function name, PCI ID, and date in the older sections is
unchanged except where an entry below says otherwise.

### Changed
- **Release titles on GitHub now carry a headline instead of repeating the version number.** Each section heading in this file ends with `: <headline>`, and `.github/workflows/release.yml` reads it into the `name:` field of `softprops/action-gh-release`. Without it the action falls back to the tag name, which the release list already shows next to the title. The five published releases were retitled from this file.
- **The changelog is plain ASCII.** Em dashes, arrows, ellipses, the `>=` sign, and the status emoji were replaced by the words or ordinary punctuation they stood for. An em dash carried at least four different jobs in these sections (colon, parenthesis, causal clause, aside), and the reader had to guess which one applied at each occurrence.
- **Entries open with what changed for the operator, not with the file that changed.** In the sections for 1.1.0 through 1.2.2, three of twenty-two entries had a bold lead line, and all three led with a filename. Scanning the bold lines now gives the substance of a release. The feature list in 1.0.0 keeps its shape, since an initial release has no prior state to state an effect against.
- **Each release section opens with the incident that prompted it.** What went wrong, on which hardware, and with which symptom now stands ahead of the list of edits, which is the part someone needs when they read the section months later.
- **The changelog-extraction step in `release.yml` anchors on the start of the line.** It matched `## [` followed by a substring search for the version, which also hits a heading that merely mentions another version in its headline, and would then serve that section under the wrong tag. It now compares the literal prefix `## [VERSION]` at column 1, strips the leading blank line so the published body matches this file byte for byte, and fails the run when the section is empty.

### Fixed
- **The 1.2.2 section credited a repair to a link that was never broken.** It reported three broken heading anchors into `docs/TROUBLESHOOTING.md`. In the `v1.2.1` tree only two such links existed, in `docs/vendors/nvidia-professional.md` and `examples/nvidia-rtx-pro-4500-blackwell/README.md`. The link in `examples/nvidia-rtx-2000-ada/README.md` was added by that same release and carried the correct double hyphen from the start. The entry now names two.
- **The 1.2.2 section put two different dates under one span.** Both target promotion dates were described as eleven weeks in the past. Measured against the release date of 2026-08-09, 2026-05-25 is 76 days and 2026-05-29 is 72 days. The entry now names the dates without the span.
- **The 1.0.0 feature list omitted a shipped script.** `scripts/capability-probe.sh`, the host-side launcher that dispatches the PowerShell probe into a running Windows VM, is in the `v1.0.0` tree but appeared in no entry. It is now listed alongside `capability-probe.ps1`.

## [1.2.2] - 2026-08-09: Both NVIDIA Pro cards reach production

Both NVIDIA Pro cards had cleared the two-week production threshold months earlier, the
RTX 2000 Ada on 2026-05-25 and the RTX PRO 4500 Blackwell on 2026-05-29, but the
documentation still described them as in validation and the README roadmap still named
those two dates as targets. This release promotes both cards and repairs four
documentation defects that surfaced while the status was traced from the README table
through to the per-card example.

### Changed
- **Both NVIDIA Pro cards are documented as production-ready.** `README.md`, `docs/vendors/nvidia-professional.md`, `examples/nvidia-rtx-2000-ada/README.md` and `examples/nvidia-rtx-pro-4500-blackwell/README.md` now show Production, promoted 2026-08-09. The RTX 2000 Ada has carried a PaddleOCR GPU-inference workload since 2026-05-11, clearing the two-week threshold on 2026-05-25; the RTX PRO 4500 Blackwell has carried an Ollama VLM workload since 2026-05-15, clearing it on 2026-05-29. Status is set in five places per card: the GPU table, the roadmap, the documentation table, the vendor doc, and the example README.
- **The roadmap no longer promises promotion dates that have passed.** `README.md` carried 2026-05-25 and 2026-05-29 as targets while the entries still read "full recipe after threshold". Both are replaced by the actual production-since dates and the items that remain open.
- **The NVIDIA Pro vendor doc states what Production covers here and what it does not.** `docs/vendors/nvidia-professional.md` names the covered ground (passthrough recipe, PCI IDs, IOMMU placement, `vfio.conf`, mandatory open kernel modules, dual-GPU operation) and the excluded ground (the unpublished measurements, and the WPR2 reset bug as a known unfixed defect). "Anticipated Test Plan" is replaced by a validation path in which step 5, the capability probe, is the one item still open.
- **The two NVIDIA Pro examples are recipes, not placeholders.** `examples/nvidia-rtx-2000-ada/README.md` and `examples/nvidia-rtx-pro-4500-blackwell/README.md` no longer say "will land here once...". Each separates *Confirmed in production* from *Open verification items*. The Blackwell example gained a "Known Open Defect" section for the WPR2 reset bug so the promotion does not bury it. The Ada example gained the open-kernel-module caveat, which applies to Ada Lovelace on the `595` driver branch and not to Blackwell alone.

### Fixed
- **The Intel Arc A310 example told readers the card was still in validation** with a promotion date of 2026-05-04, while `README.md` and `docs/vendors/intel-arc-dg2.md` had shown Production since v1.2.1. `examples/intel-arc-a310/README.md` was the fifth status location and was missed in that release, the same class of omission that 1.2.0 already recorded for the RTX PRO 4500. It now shows Production, promoted 2026-05-15.
- **Two links into the troubleshooting section led nowhere.** The target heading in `docs/TROUBLESHOOTING.md` contains an em dash, which GitHub's slug algorithm collapses into a **double** hyphen (`...linux-guest--blackwell--ada`). The links in `docs/vendors/nvidia-professional.md` and `examples/nvidia-rtx-pro-4500-blackwell/README.md` carried a single one; the one in `README.md` was correct. The `markdown-links` CI job does not validate URL fragments, so CI stayed green over both.
- **The Ada example no longer describes the dual-GPU setup as future work.** It read "will share a host with the RTX PRO 4500 Blackwell once that card is installed". The card was installed 2026-05-15, and simultaneous dual-GPU operation was documented in 1.2.0.
- **The host setup guide no longer marks the NVIDIA Pro vendor doc as unfinished.** The vendor-doc list in `docs/HOST_SETUP.md` still flagged `nvidia-professional.md` as in validation.

## [1.2.1] - 2026-07-26: Intel Arc A310 reaches production

The Intel Arc A310 had met the two-week uptime threshold on 2026-05-15, and both NVIDIA Pro
cards had been in real workloads since May, but the README still listed the Arc card as in
validation and both NVIDIA entries as merely planned. This release brings the status
tables in line with what the hardware had been doing.

### Changed
- **The Intel Arc A310 is documented as production-ready.** Promoted from in validation to Production as of 2026-05-15, when the two-week uptime threshold was confirmed. Status is set in `README.md`, `docs/vendors/intel-arc-dg2.md`, and the documentation table.
- **The roadmap names the workloads the NVIDIA Pro cards actually run.** Both entries in `README.md` move from planned to in validation, with the workloads (PaddleOCR GPU inference on the RTX 2000 Ada, Ollama VLM inference on the RTX PRO 4500 Blackwell), the open items (WPR2 reset, ReBAR on the full 32 GB BAR, PCIe 5.0 link training), and target promotion dates.
- **The documentation table shows which vendor docs can be relied on.** In `README.md`, `nvidia-professional` moves from planned to in validation with dual-GPU confirmed, `intel-arc-dg2` to production, and the TROUBLESHOOTING scope line gains the WPR2 reset bug and the open-module requirement.
- **The README section on overlooked details covers three findings, not one.** "The One Thing Most Guides Miss" becomes "The Things Most Guides Miss" and gains the NVIDIA Blackwell and Ada open-module finding and the WPR2 reset bug alongside the existing Intel Arc entry.

## [1.2.0] - 2026-05-15: A second Pro card in the same VM, and the Blackwell reset bug named

With both Pro cards installed in one workstation on 2026-05-15, two findings came out of
running them side by side. A Blackwell GPU that has been passed through once fails to
initialize on the next VM start, because the GSP firmware keeps its WPR2 region across a
PCIe function-level reset. And the RTX 2000 Ada turned out to need the open kernel
modules as well, which until then had been documented as a Blackwell requirement.

### Added
- **A Blackwell GPU that fails to initialize on the second VM start now has a documented cause and workaround.** `docs/TROUBLESHOOTING.md` gains "NVIDIA Blackwell: GPU Failed to Initialize on Second VM Start (WPR2 Reset Bug)" with the root cause (GSP firmware WPR2 persists through PCIe FLR), a comparison table against the AMD reset bug, the short-term fix (host reboot), and a pointer to `vendor-reset` as the long-term fix.
- **Two Pro GPUs can serve separate Docker containers in the same Linux VM.** `docs/vendors/nvidia-professional.md` gains "Confirmed: Dual GPU to Same Linux VM - Docker Container Isolation", covering per-container GPU assignment via `NVIDIA_VISIBLE_DEVICES`, the passthrough order (`hostpci1` maps to GPU 0), the verification commands, and a WPR2 cross-reference. Confirmed 2026-05-15 with the RTX PRO 4500 and the RTX 2000 Ada in simultaneous production operation.

### Changed
- **The RTX 2000 Ada needs the open kernel modules too, not Blackwell alone.** In `docs/vendors/nvidia-professional.md` the driver is corrected to `nvidia-driver-595-server-open`; Ada Lovelace on this driver branch carries the same requirement, which earlier text implied was Blackwell-specific. The entry also gains the dual-GPU confirmation and the gotcha that `qm set` and `vfio.conf` are independent of each other.
- **The README GPU table shows the RTX PRO 4500 Blackwell as in validation** with its hardware details, corrected from planned. The promotion happened in 1.1.0, but the table was not updated with it.

## [1.1.0] - 2026-05-15: Both NVIDIA Pro cards need the open kernel modules

First hardware sessions with both NVIDIA Pro cards, the RTX 2000 Ada on 2026-05-11 and the
RTX PRO 4500 Blackwell on 2026-05-15. On Blackwell the closed-source driver loaded, the
GPU appeared in `lspci`, and `nvidia-smi` still answered `No devices found`; `dmesg`
showed `RmInitAdapter failed! (0x22:0x56:1017)`. The open kernel modules fixed it. Both
cards are promoted to in validation, with their PCI IDs confirmed from hardware.

### Added
- **`nvidia-smi` reporting "No devices found" in a Linux guest now has a documented fix.** `docs/TROUBLESHOOTING.md` gains a section for the case where the NVIDIA kernel module is loaded and `lspci` shows the GPU: the closed-source kernel modules do not support Blackwell or Ada Lovelace, and the fix is the `-server-open` or `-open` driver variant. The section names the affected architectures and the live VFIO bind technique via `new_id`, for when the device IDs are unknown to the already-loaded module instance.

### Changed
- **The RTX 2000 Ada recipe carries hardware-confirmed IDs and a named driver branch.** Status moves from planned to in validation after the first hardware session on 2026-05-11, in `docs/vendors/nvidia-professional.md`, `examples/nvidia-rtx-2000-ada/README.md` and `README.md`. Confirmed vendor:device IDs are `10de:28b0` for the GPU and `10de:22be` for the audio companion, CUDA compute capability 8.9, driver branch `nvidia-driver-595-server`. One Ubuntu 24.04 gotcha is documented: the standard apt repositories do not contain `nvidia-container-toolkit`, so NVIDIA's own repository (`nvidia.github.io/libnvidia-container`) is required; the Ubuntu package appears to install but places no binaries.
- **The RTX PRO 4500 Blackwell recipe names the driver that works and the one that does not.** Status moves from planned to in validation after the first hardware session on 2026-05-15, in `examples/nvidia-rtx-pro-4500-blackwell/README.md` and `docs/vendors/nvidia-professional.md`. Confirmed vendor:device IDs are `10de:2c31` for the GPU and `10de:22e9` for the audio companion, in a clean IOMMU group on AMD Raphael/Granite Ridge isolated to the GPU and its audio companion. The config shape is validated on a Proxmox VE 9.1.1 host with kernel 6.17.2-1-pve and an Ubuntu 24.04 guest on kernel 6.8.0-111-generic. Open kernel modules are mandatory: `nvidia-driver-595-server` fails with `RmInitAdapter (0x22:0x56:1017)`, and `nvidia-driver-595-server-open` is the fix. The audio companion had `snd_hda_intel` bound on first boot, which `softdep snd_hda_intel pre: vfio-pci` in `modprobe.d` prevents from recurring.

## [1.0.0] - 2026-04-21: Intel Arc A310 passthrough with the full Code-43 fix

Initial public release. The Intel Arc A310 recipe is the one complete vendor path at this
point; the NVIDIA Pro and AMD entries are stubs with no hardware behind them yet.

### Added
- Repository structure (scripts, docs, examples, CI)
- **Intel Arc A310 (DG2) recipe** with the full Code-43 fix and its CPUID mechanics (in validation, promotes to production on 2026-05-04)
  - QEMU args: `kvm=off`, `-hypervisor`, `hv_vendor_id=GenuineIntel`, `hv_relaxed`, `hv_spinlocks=0x1fff`
  - Failure-mode documentation: the `E_NOINTERFACE` to `STATUS_UNSUCCESSFUL` to OK progression
  - INF gotcha: `iigd_dch_d.inf` (DG2-discrete) against `iigd_dch.inf` (iGPU)
  - Vulkan ICD manual registration, which pnputil skips
- **Host setup scripts**: `enable-iommu.sh` (auto-detects GRUB against proxmox-boot-tool), `bind-vfio.sh`, `check-vfio-binding.sh`, `check-iommu-groups.sh`
- **Vendor-aware CPU-args generator** (`generate-vm-args.sh`), dual-mode (raw args for `qm set --args`, or `--as-config-line` for a config-file paste), with an `--explain` mode for pedagogy and profiles for intel-arc, nvidia-consumer, nvidia-pro, and amd
- **Reset-method hookscript** template (`hookscripts/reset-method.sh`) and its installer (`install-reset-hook.sh`)
- **Windows guest capability probe** (`capability-probe.ps1`) with DXGI-based VRAM detection (which avoids the 32-bit WMI cap), a Vulkan ICD registry check, DirectX feature levels, and NVENC/QSV/AMF detection, plus the host-side launcher (`capability-probe.sh`) that dispatches it into a running VM
- **Diagnostic bundler** (`collect-diagnostics.sh`) with an auto-sanitization disclaimer
- **Vendor stubs** for NVIDIA Pro (RTX 2000 Ada and RTX PRO 4500 Blackwell, planned), NVIDIA Consumer (backlog, since the Intel Arc A310 recipe already covers the Consumer tier), and AMD (backlog)
- **Cluster support**: `RESOURCE_MAPPINGS.md` for Proxmox VE 8+ HA and migration scenarios
- **Troubleshooting matrix** from symptom to vendor to root cause to fix
- **CI**: shellcheck (severity=warning), bash-syntax, and markdown-link-check via GitHub Actions
- **Release automation** via the `release.yml` workflow, which extracts the changelog section on tag push
