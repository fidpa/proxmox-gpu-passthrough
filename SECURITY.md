# Security Policy

## Scope

This project provides host/VM configuration for PCIe GPU passthrough. It does **not** handle user credentials, network exposure, or secrets management — but it does modify kernel boot parameters, VFIO module bindings, and QEMU launch args.

## Reporting a Vulnerability

If you find a security issue that affects users of this project — e.g. a script that escalates privileges unexpectedly, a suggested config that weakens host isolation, or a hookscript path that allows injection — please **do not** open a public issue.

Instead:
1. Email the maintainer (check `git log` for contact) with subject `[SECURITY] proxmox-gpu-passthrough: <short description>`
2. Include a minimal reproducer and the impact you believe it has
3. Allow up to 30 days for a fix before public disclosure

## Out of Scope

- General Proxmox VE vulnerabilities (report to Proxmox Server Solutions)
- Kernel / VFIO driver bugs (report upstream to kernel.org)
- Vendor GPU driver bugs (report to Intel/NVIDIA/AMD)
- Configuration choices that the user explicitly enables (e.g. disabling IOMMU for debugging)

## Hardening Recommendations for Users

- **Keep your host kernel current** — VFIO and IOMMU fixes land regularly
- **Don't disable IOMMU as a workaround** — it exposes other VMs to DMA attacks from the GPU VM
- **Audit IOMMU groups** — if your passthrough pulls companion devices (USB controllers, NICs), those VMs get them too
- **Use `pcie_acs_override` sparingly** — it breaks the isolation guarantees that IOMMU groups provide
