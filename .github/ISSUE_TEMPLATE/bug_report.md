---
name: Bug Report
about: Report a failure in a script, doc, or recipe in this repo
labels: bug
---

## Summary

<!-- One sentence: what broke? -->

## Affected Component

- [ ] Script: `scripts/...`
- [ ] Hookscript: `hookscripts/...`
- [ ] Documentation: `docs/...`
- [ ] Vendor recipe: `docs/vendors/...`
- [ ] CI / Build

## Environment

- **Proxmox VE**: (e.g. 9.1)
- **Kernel**: `uname -r`
- **CPU**: (e.g. Intel i5-14400 / AMD Ryzen 9 7900)
- **GPU (passthrough target)**: vendor/model + vendor:device ID from `lspci -nn`
- **Guest OS**: (Windows 11 25H2 / Ubuntu 24.04 / ...)
- **Guest Driver Version**:

## Reproducer

```
# Exact commands you ran
```

## Expected

<!-- What should have happened? -->

## Actual

<!-- What happened? Include relevant log/error output. -->

## IOMMU & VFIO State

<details>
<summary>Output of <code>./scripts/check-iommu-groups.sh</code></summary>

```
PASTE OUTPUT HERE
```

</details>

<details>
<summary>Output of <code>lspci -nnk -s &lt;BDF&gt;</code> for GPU and companion</summary>

```
PASTE OUTPUT HERE
```

</details>

## VM Config (sanitized)

<details>
<summary>Output of <code>qm config &lt;vmid&gt;</code></summary>

```
PASTE OUTPUT HERE (redact IPs, MACs, hostnames)
```

</details>

## Additional Context

<!-- Screenshots, Event Viewer screenshots, dmesg snippets, anything else relevant -->
