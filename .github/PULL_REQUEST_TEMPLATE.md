## Summary

<!-- One sentence: what does this PR do? -->

## Type of Change

- [ ] Bug fix (script/doc correction)
- [ ] New vendor recipe (requires ≥2 weeks production uptime — see CONTRIBUTING.md)
- [ ] New script / diagnostic tool
- [ ] Documentation improvement
- [ ] CI / tooling

## Testing

<!-- Describe the setup this was tested on. For vendor recipes, state workload + uptime. -->

- **Host**: Proxmox VE x.x, Kernel 6.xx.x
- **Guest**: Windows / Linux version + driver
- **GPU**: vendor/model + vendor:device ID
- **Workload**: (gaming, ML inference, CAD, idle-only, ...)
- **Uptime**: (days running without passthrough failure)

## Checklist

- [ ] Scripts pass `shellcheck --severity=warning`
- [ ] No private paths, IPs, hostnames, MACs, or credentials
- [ ] CHANGELOG.md updated under `[Unreleased]`
- [ ] Root cause documented (not just symptom), if bugfix
- [ ] README "Supported GPUs" table updated, if vendor recipe
- [ ] Linked any related issues: `Closes #xxx`

## Root Cause (for bugfixes)

<!-- Don't just say what you changed. Explain WHY the original code was wrong at the CPUID/IOMMU/WDDM/PCI-layer. -->

## Breaking Changes

<!-- Does this change script arguments, config format, or behavior in a way that existing users need to know about? -->
