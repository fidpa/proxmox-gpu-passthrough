# AMD (Polaris / Navi / RDNA)

> 📋 **Status**: Backlog. Depends on access to test hardware.

## The AMD Reset Bug

AMD GPUs historically suffer from the **Reset Bug**: after a VM that owns the GPU shuts down, the GPU is left in a state that the PCIe bus can't recover from. First VM boot works; the second boot (or any VM restart) fails until the host itself is rebooted.

This has been the single biggest obstacle to AMD passthrough for years. Polaris (RX 4xx/5xx) and early Navi (RX 5000) are the worst affected; RDNA 2/3 (RX 6000/7000) improved but not fully fixed.

## Anticipated Recipe

```
Pattern C: Reset Bug (Layer 3)
Layer 3 fix: vendor-reset kernel module (third-party)
   https://github.com/gnif/vendor-reset
   Provides working reset sequences per AMD generation
Layer 4: Usually minimal — AMD driver is paravirt-tolerant
Layer 5: Standard AMD driver install
```

## Why This Is Backlog, Not Planned

No personal AMD passthrough hardware available for validation. Recipe would be a literature review — reading `vendor-reset` docs + reddit + VFIO forum threads — which doesn't meet this repo's "production-validated ≥2 weeks" bar.

## If You Have AMD Passthrough Running

A community-contributed recipe would be welcome. Required inputs:
- AMD GPU family + specific model + vendor:device ID
- Working host config (IOMMU groups, VFIO binding)
- Whether `vendor-reset` was needed and for which reset quirk
- 2+ weeks uptime with actual workload
- PR against this doc (stub → full recipe)

See [CONTRIBUTING.md](../../CONTRIBUTING.md).

## References

- `vendor-reset` kernel module: <https://github.com/gnif/vendor-reset>
  - ⚠️ Last tagged release `v0.1.0` was in January 2021. Known compatibility issues
    starting at kernel 5.15 (see GitHub issue #46). Before depending on it for
    production, verify it builds and loads on your current kernel, and check
    open issues for your GPU family.
- Level1Techs AMD Reset Bug threads (search "AMD reset bug Navi")
- Proxmox Forum AMD passthrough category
