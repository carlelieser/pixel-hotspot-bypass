---\nHistorical build log from initial development.\nDocuments 9 build attempts and lessons learned.\n---\n\n# Tasks & Goals

## Current Status

**Build #9 END-TO-END TEST SUCCESSFUL** - Complete workflow verified from scratch!
- Flashed stock firmware (BP3A.251105.015)
- Followed README instructions step-by-step
- Built kernel with KernelSU-Next v10209 and TTL/HL support
- All features verified working

## Current Tasks

- [x] Test Build #1 - Android 15 + KernelSU - **BOOTLOOP**
- [x] Test Build #2 - Android 15 Stock - **BOOTLOOP**
- [x] Investigate root cause - Found wrong manifest
- [x] Test Build #3 - Android 16 + KernelSU - **BOOTLOOP**
- [x] Test Build #4 - Android 16 Stock - **BOOTLOOP**
- [x] Test Build #5 - Android 16 + BUILD_AOSP_KERNEL=1 - **BOOTLOOP**
- [x] Research latest build guides - Found missing prerequisite!
- [x] Disable verification (`fastboot oem disable-verification`)
- [x] Test Build #5 with verification disabled - **BOOTED**
- [x] Add KernelSU and TTL modifications
- [x] Test Build #6 with KernelSU + TTL - **BOOTED but configs not compiled**
- [x] Clean Bazel cache (`tools/bazel clean --expunge`)
- [x] Build #7 - Rebuild with clean cache - **COMPLETED**
- [x] Verify KernelSU config (CONFIG_KSU=y) - **VERIFIED in build config**
- [x] Verify TTL config (CONFIG_NETFILTER_XT_TARGET_HL=y) - **VERIFIED in build config**
- [x] Update apply-defconfig.sh to prevent caching issues
- [x] Fix build scripts for Android 16 compatibility
- [x] Flash Build #7 and test on device - **BOOTED but GKI not customized**
- [x] Build #8 - Build kernel from source (not downloaded GKI) - **SUCCESS**
- [x] Flash Build #8 and verify KernelSU works - **VERIFIED**
- [x] Flash stock firmware BP3A.251105.015 for clean test
- [x] Build #9 - Follow README from scratch (fresh kernel source) - **SUCCESS**
- [x] Flash Build #9 with correct sequence (boot + vendor_kernel_boot + dtbo + dlkm partitions) - **BOOTED**
- [x] Verify all features: KernelSU root, TTL/HL modification - **ALL WORKING**

## Critical Discovery

**MISSING PREREQUISITE**: `fastboot oem disable-verification`

All previous builds bootlooped because Android Verified Boot (AVB) was rejecting the custom kernel. This must be run before flashing any custom kernel.

## Build Summary

| Build | Manifest | Modifications | Result |
|-------|----------|---------------|--------|
| #1 | android15-d4 | KernelSU + TTL | Bootloop |
| #2 | android15-d4 | None (stock) | Bootloop |
| #3 | android16 | KernelSU + TTL | Bootloop |
| #4 | android16 | None (stock) | Bootloop |
| #5 | android16 | BUILD_AOSP_KERNEL=1 | Bootloop (no verification disable) |
| #5b | android16 | BUILD_AOSP_KERNEL=1 + disable-verification | **BOOTED** |
| #6 | android16 | KernelSU + TTL (cached build) | Booted but configs not compiled |
| #7 | android16 | KernelSU + TTL (clean rebuild) | Booted but GKI not customized |
| #8 | android16 | KernelSU + TTL (GKI from source) | **SUCCESS** - KernelSU v10206 |
| #9 | android16 | KernelSU + TTL (fresh build from README) | **SUCCESS** - KernelSU v10209 + TTL/HL verified |

## Root Cause Analysis

### Issue 1: Wrong Manifest (Fixed)
- Device firmware: `bp3a.251105.015` (Android 16)
- Initially used: `android-gs-tegu-6.1-android15-d4`
- Corrected to: `android-gs-tegu-6.1-android16`

### Issue 2: Verification Not Disabled (Fixed)
- Official docs require: `fastboot oem disable-verification`
- This was not done for builds #1-5
- Now disabled for build #5b test

### Issue 3: Bazel Caching (Fixed)
- Bazel doesn't track defconfig changes as build inputs
- Build #6 used cached kernel from Build #5b (only 92 actions vs 462)
- Fix: Run `tools/bazel clean --expunge` after config changes
- Script fix: apply-defconfig.sh now touches aosp/Makefile to invalidate cache

### Issue 4: Kleaf Build System Bug (Fixed)
- `kernel_filegroup.bzl` missing fields in `KernelBuildExtModuleInfo`
- Causes error: `'KernelBuildExtModuleInfo' value has no field or method 'strip_modules'`
- Fix: Patch `kernel_filegroup.bzl` to add `strip_modules`, `config_env_and_outputs_info`, `module_kconfig`
- Script fix: setup-kernel.sh now patches Kleaf automatically

### Issue 5: GKI Downloaded Instead of Built (Fixed)
- Bazel downloads prebuilt GKI kernel instead of building from source
- Build #7 configs only apply to device modules, not kernel itself
- Device running: `6.1.124-android14-11-g8d713f9e8e7b-ab13202960` (Mar 2025 GKI)
- CONFIG_KSU and CONFIG_NETFILTER_XT_TARGET_HL not in running kernel
- **Fix**: Use `--config=use_source_tree_aosp` to build GKI from source
- Build #8 successfully compiled KernelSU-Next v10206 into kernel

### Issue 6: vendor_kernel_boot.img Missing from Flash Sequence (Fixed)
- **Critical**: Pixel 9a DOES have a vendor_kernel_boot partition (contrary to initial assumption)
- Build produces: `bazel-bin/private/devices/google/tegu/kernel_images_boot_images/vendor_kernel_boot.img` (8.4MB)
- First Build #9 flash attempt bootlooped because vendor_kernel_boot.img was NOT flashed
- **Fix**: Must flash vendor_kernel_boot.img from bootloader BEFORE rebooting to fastbootd
- Correct bootloader flash sequence: boot.img, dtbo.img, vendor_kernel_boot.img
- Then reboot to fastbootd and flash: vendor_dlkm.img, system_dlkm.img

### Issue 7: Dist vs GKI Artifacts boot.img (Fixed)
- `out/tegu/dist/boot.img` (51MB) - Uses downloaded/cached GKI
- `bazel-bin/aosp/kernel_aarch64_gki_artifacts/boot.img` (64MB) - Custom-built GKI with KernelSU
- **Must flash the GKI artifacts boot.img**, not the dist boot.img
- This is a Bazel build system quirk where dist uses `common/boot.img` which differs from the GKI artifacts

### Image Size Differences
Our builds produce smaller images than stock firmware:
- boot.img: 51MB (stock: 67MB)
- vendor_kernel_boot.img: 8.3MB (stock: 67MB)

This may be normal for custom builds without OTA padding/metadata.

## Lessons Learned

### 1. Match Manifest to Device Firmware
- Check device build number: `adb shell getprop ro.build.id`
- Build number prefix indicates Android version (e.g., `bp3a` = Android 16)
- Use matching manifest branch (e.g., `android-gs-tegu-6.1-android16`)

### 2. Always Disable Verification First
```bash
adb reboot bootloader
fastboot oem disable-verification
```
This is a ONE-TIME prerequisite before any custom kernel flashing.

### 3. Correct Flash Sequence (Pixel 9a)
1. Boot to bootloader: `adb reboot bootloader`
2. Flash boot partitions: `fastboot flash boot boot.img && fastboot flash dtbo dtbo.img && fastboot flash vendor_kernel_boot vendor_kernel_boot.img`
3. Reboot to fastbootd: `fastboot reboot fastboot`
4. Flash dynamic partitions: `fastboot flash vendor_dlkm vendor_dlkm.img && fastboot flash system_dlkm system_dlkm.img`
5. Reboot: `fastboot reboot`

**CRITICAL**: vendor_kernel_boot.img MUST be flashed in step 2, otherwise device will bootloop!

### 4. Bazel Caching with Defconfig Changes
- Bazel does NOT automatically detect defconfig changes
- After modifying defconfig, either:
  - Run `tools/bazel clean --expunge` (guaranteed rebuild)
  - Or touch `aosp/Makefile` (lighter invalidation)
- The apply-defconfig.sh script now handles this automatically

### 5. Build Verification
- Full kernel build should have ~462 actions
- If you see only ~92 actions, cache was used
- Check kernel build date: `adb shell dmesg | grep "Linux version"`
- Verify configs: `adb shell zcat /proc/config.gz | grep CONFIG_NAME`

### 6. Android 16 Build Notes
- `--config=no_download_gki` doesn't exist in Android 16
- Use `--lto=none` for faster builds
- Build target: `//private/devices/google/tegu:zumapro_tegu_dist`

## Completed

- [x] Initial project setup
- [x] KernelSU-Next integration scripts
- [x] TTL/HL support patches
- [x] Build scripts configuration
- [x] Device config updated to Android 16 manifest
- [x] Build script fixed for Android 16 (removed no_download_gki)

## Goals

### Short-term (COMPLETED ✓)
- [x] Get kernel to boot successfully on Pixel 9a
- [x] Verify KernelSU-Next functionality
- [x] Verify TTL/HL bypass works
- [x] End-to-end test following README from scratch

### Long-term
- [x] Stable kernel with all features working
- [x] Document the working configuration
- [ ] Create AnyKernel3 package for easier flashing

## Flash Commands

```bash
# Prerequisites (one-time)
adb reboot bootloader
fastboot oem disable-verification

# Flash kernel (from kernel-tegu directory)
cd kernel-tegu

# IMPORTANT: Use GKI artifacts boot.img (64MB), NOT out/tegu/dist/boot.img (51MB)
# CRITICAL: Must flash vendor_kernel_boot.img in bootloader mode!
fastboot flash boot bazel-bin/aosp/kernel_aarch64_gki_artifacts/boot.img
fastboot flash dtbo bazel-bin/private/devices/google/tegu/kernel_images_dtbo/dtbo.img
fastboot flash vendor_kernel_boot bazel-bin/private/devices/google/tegu/kernel_images_boot_images/vendor_kernel_boot.img
fastboot reboot fastboot

# In fastbootd mode
fastboot flash vendor_dlkm bazel-bin/private/devices/google/tegu/kernel_images_vendor_dlkm_image/vendor_dlkm.img
fastboot flash system_dlkm bazel-bin/private/devices/google/tegu/kernel_images_system_dlkm_image/system_dlkm.img
fastboot reboot
```

## Research Notes

### Working Pixel 9a Kernels (XDA)
- **Optimistic Kernel** - Uses AnyKernel3 packaging
- **blu_spark** - Supports Pixel 6/7/8/9 series

### Key Differences from Our Approach
1. XDA kernels use AnyKernel3 zip format
2. Flashed via Kernel Flasher app, not fastboot
3. Based on `android_kernel_google_tegu` GitHub repo

### Official Google Requirements
- Manifest: `android-gs-tegu-6.1-android16`
- Must disable verification before flashing
- Flash partitions: boot, dtbo, vendor_dlkm, system_dlkm (no vendor_kernel_boot on Pixel 9a)

## Testing Checklist

- [x] Device boots to Android
- [x] `adb shell zcat /proc/config.gz | grep KSU` shows CONFIG_KSU=y
- [x] `adb shell zcat /proc/config.gz | grep NETFILTER_XT_TARGET_HL` shows CONFIG_NETFILTER_XT_TARGET_HL=y
- [x] KernelSU Manager detects module and root works (`su -c 'id'` returns uid=0)
- [x] TTL modification works via iptables (`iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65`)
- [x] HL modification works via ip6tables (`ip6tables -t mangle -A POSTROUTING -j HL --hl-set 65`)

**Build #9 Verified (End-to-End Test)**:
- Kernel version: `6.1.124-android14-11-maybe-dirty`
- KernelSU-Next version: v10209 (from clean build)
- Root access: uid=0(root) ✓
- TTL modification: `iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65` ✓
- HL modification: `ip6tables -t mangle -A POSTROUTING -j HL --hl-set 65` ✓

## Hotspot Bypass Commands

For persistent hotspot bypass, use a KernelSU module or boot script:
```bash
# Set TTL/HL to 65 to bypass carrier hotspot detection
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65
ip6tables -t mangle -A POSTROUTING -j HL --hl-set 65
```

## Next Steps if Build #5b Fails

1. Try AnyKernel3 packaging approach
2. Compare our boot.img with stock using `unpackbootimg`
3. Check kernel config differences with stock
4. Consider using etnperlong's android_kernel_google_tegu source
