# Tasks & Goals

## Current Status

**Rebuilding kernel with clean Bazel cache** - Build in progress (~427/474 actions)

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
- [ ] Build #7 - Rebuild with clean cache (in progress)
- [ ] Verify KernelSU config (CONFIG_KSU=y)
- [ ] Verify TTL config (CONFIG_NETFILTER_XT_TARGET_HL=y)
- [x] Update apply-defconfig.sh to prevent caching issues

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
| #7 | android16 | KernelSU + TTL (clean rebuild) | **IN PROGRESS** |

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

### 3. Correct Flash Sequence
1. Boot to bootloader: `adb reboot bootloader`
2. Flash boot partitions: `fastboot flash boot boot.img && fastboot flash dtbo dtbo.img`
3. Flash vendor_kernel_boot: `fastboot flash vendor_kernel_boot vendor_kernel_boot.img`
4. Reboot to fastbootd: `fastboot reboot fastboot`
5. Flash dynamic partitions: `fastboot flash vendor_dlkm vendor_dlkm.img && fastboot flash system_dlkm system_dlkm.img`
6. Reboot: `fastboot reboot`

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

### Short-term
- Get kernel to boot successfully on Pixel 9a
- Verify KernelSU-Next functionality
- Verify TTL/HL bypass works

### Long-term
- Stable kernel with all features working
- Document the working configuration
- Create AnyKernel3 package for easier flashing

## Flash Commands

```bash
# Prerequisites (one-time)
adb reboot bootloader
fastboot oem disable-verification

# Flash kernel
cd out/tegu-full-source
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot reboot fastboot

# In fastbootd mode
fastboot flash vendor_kernel_boot vendor_kernel_boot.img
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot flash system_dlkm system_dlkm.img
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
- Flash partitions: boot, dtbo, vendor_kernel_boot, vendor_dlkm, system_dlkm

## Testing Checklist

- [ ] Device boots to Android
- [ ] `adb shell dmesg | grep -i ksu` shows KernelSU loaded
- [ ] `adb shell zcat /proc/config.gz | grep KSU` shows CONFIG_KSU=y
- [ ] KernelSU Manager detects module version >= 12797
- [ ] TTL modification works via iptables

## Next Steps if Build #5b Fails

1. Try AnyKernel3 packaging approach
2. Compare our boot.img with stock using `unpackbootimg`
3. Check kernel config differences with stock
4. Consider using etnperlong's android_kernel_google_tegu source

