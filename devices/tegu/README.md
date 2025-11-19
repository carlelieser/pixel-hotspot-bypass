# Pixel 9a (tegu)

## Device Specifications

| Property | Value |
|----------|-------|
| Device Name | Google Pixel 9a |
| Codename | tegu |
| SoC | Google Tensor G4 (zumapro) |
| Kernel Version | 6.1.99 |
| Android Version | Android 14 (API 34) |

## Build Configuration

- **Manifest Branch**: `android-gs-tegu-6.1-android14`
- **Bazel Config**: `tegu`
- **Build Target**: `zumapro_tegu_dist`

## Notes

### Tested Configuration

This device has been tested with:
- KernelSU-Next v1.1.1 (version 12882)
- CONFIG_NETFILTER_XT_TARGET_HL=y
- unlimited-hotspot KernelSU module

### Flashing

The Pixel 9a uses dynamic partitions, so you need to use fastbootd for some partitions:

**Bootloader mode** (standard fastboot):
- boot.img
- dtbo.img

**Fastbootd mode** (userspace fastboot):
- vendor_kernel_boot.img
- vendor_dlkm.img
- system_dlkm.img

See [../../docs/FLASH.md](../../docs/FLASH.md) for detailed instructions.

## Related Devices

Other Pixel 9 series devices that may work with similar configuration:

| Device | Codename | Notes |
|--------|----------|-------|
| Pixel 9 | tokay | Untested |
| Pixel 9 Pro | caiman | Untested |
| Pixel 9 Pro XL | komodo | Untested |
| Pixel 9 Pro Fold | comet | Untested |

These devices share the same Tensor G4 SoC and may only need different defconfig paths.
