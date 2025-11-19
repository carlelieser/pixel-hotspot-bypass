# Flashing Instructions

Complete guide for flashing the custom kernel to your Pixel device.

## Prerequisites

### Required Tools

- **Android SDK Platform Tools** (fastboot)
  - Download: https://developer.android.com/studio/releases/platform-tools
  - Or install via package manager:
    ```bash
    # macOS
    brew install android-platform-tools

    # Ubuntu/Debian
    sudo apt install android-tools-adb android-tools-fastboot
    ```

### Device Preparation

1. **Unlock Bootloader** (if not already done)
   ```bash
   # Enable OEM unlocking in Developer Options first
   adb reboot bootloader
   fastboot flashing unlock
   ```
   **Warning**: This will factory reset your device!

2. **Enable USB Debugging**
   - Settings > About Phone > Tap Build Number 7 times
   - Settings > Developer Options > USB Debugging

## Understanding Partition Types

Modern Pixel devices use **dynamic partitions**. This means some partitions must be flashed in **fastbootd** (userspace fastboot) mode, not regular bootloader mode.

### Bootloader Mode Partitions
These can be flashed with standard `fastboot`:
- `boot`
- `dtbo`

### Fastbootd Mode Partitions
These require `fastboot reboot fastboot` first:
- `vendor_kernel_boot`
- `vendor_dlkm`
- `system_dlkm`

## Flashing Steps

### Quick Reference

```bash
cd out/tegu  # or your output directory

# Connect device and reboot to bootloader
adb reboot bootloader

# Flash bootloader-mode partitions
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img

# Reboot to fastbootd
fastboot reboot fastboot

# Flash dynamic partitions
fastboot flash vendor_kernel_boot vendor_kernel_boot.img
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot flash system_dlkm system_dlkm.img

# Reboot device
fastboot reboot
```

### Detailed Steps

#### 1. Connect Device

```bash
# Verify device is connected
adb devices

# Should show your device
```

#### 2. Enter Bootloader Mode

```bash
adb reboot bootloader

# Or use hardware buttons:
# Power off device, then hold Power + Volume Down
```

Wait for bootloader screen to appear.

#### 3. Flash Boot Partitions

```bash
# Navigate to output directory
cd out/tegu

# Flash boot image (kernel + ramdisk)
fastboot flash boot boot.img

# Flash device tree blob overlay
fastboot flash dtbo dtbo.img
```

Expected output:
```
Sending 'boot' (XXXX KB)                           OKAY [  X.XXXs]
Writing 'boot'                                     OKAY [  X.XXXs]
Finished. Total time: X.XXXs
```

#### 4. Reboot to Fastbootd

```bash
fastboot reboot fastboot
```

The screen will change to show "fastbootd" mode. This is userspace fastboot running in Android recovery.

#### 5. Flash Dynamic Partitions

```bash
# Vendor kernel boot
fastboot flash vendor_kernel_boot vendor_kernel_boot.img

# Vendor kernel modules
fastboot flash vendor_dlkm vendor_dlkm.img

# System kernel modules
fastboot flash system_dlkm system_dlkm.img
```

#### 6. Reboot Device

```bash
fastboot reboot
```

Device will boot with the new kernel.

## Verification

### Check Kernel Version

After booting, verify the kernel:

```bash
adb shell uname -a
```

Should show your custom kernel version.

### Check KernelSU

```bash
adb shell dmesg | grep -i kernelsu
```

Should show KernelSU initialization messages with version 12882.

### Install KernelSU Manager

1. Download KernelSU-Next Manager APK from:
   https://github.com/rifsxd/KernelSU-Next/releases

2. Install:
   ```bash
   adb install KernelSU-Next-Manager-*.apk
   ```

3. Open the app and verify it shows "Working" status.

### Check TTL/HL Support

```bash
# Check if xt_HL module is loaded
adb shell lsmod | grep xt_HL

# Check available iptables targets
adb shell iptables -j HL --help
adb shell ip6tables -j HL --help
```

## Installing Hotspot Bypass Module

After KernelSU is working:

1. Open KernelSU Manager
2. Go to Modules
3. Install the unlimited-hotspot module
4. Reboot device

The module will automatically set up iptables rules to modify TTL/HL values.

## Troubleshooting Flashing Issues

### "FAILED (remote: not allowed)"

**Cause**: Bootloader is locked.

**Solution**: Unlock bootloader first:
```bash
fastboot flashing unlock
```

### "FAILED (remote: Device not found)"

**Cause**: Device not connected or not in correct mode.

**Solution**:
- Check USB cable and port
- Verify device is in bootloader/fastbootd mode
- Try different USB port

### Fastbootd Mode Not Working

**Cause**: Device doesn't enter fastbootd properly.

**Solution**:
- Ensure you have recent platform-tools (30.0.0+)
- Try: `fastboot reboot fastboot` from bootloader mode
- Or boot to recovery, then select "Enter fastboot"

### Device Stuck in Bootloop

**Cause**: Kernel issue or partition mismatch.

**Solution**:
1. Boot to bootloader (hold Power + Volume Down)
2. Flash factory boot image:
   ```bash
   fastboot flash boot /path/to/factory/boot.img
   ```
3. Or factory reset from bootloader

### "Cannot flash dynamic partition"

**Cause**: Trying to flash dynamic partition in bootloader mode.

**Solution**: Use fastbootd mode:
```bash
fastboot reboot fastboot
fastboot flash vendor_dlkm vendor_dlkm.img
```

## Reverting to Stock Kernel

To revert to stock kernel:

1. Download factory image for your device:
   https://developers.google.com/android/images

2. Extract and flash relevant images:
   ```bash
   fastboot flash boot boot.img
   fastboot flash dtbo dtbo.img
   fastboot reboot fastboot
   fastboot flash vendor_kernel_boot vendor_kernel_boot.img
   fastboot flash vendor_dlkm vendor_dlkm.img
   fastboot flash system_dlkm system_dlkm.img
   fastboot reboot
   ```

Or use the full factory image flash script.

## OTA Updates

**Important**: Installing OTA updates will overwrite your custom kernel.

Options:
1. Skip OTA updates
2. Rebuild and reflash after each update
3. Use tools like OTA Survival to preserve modifications

## Safety Notes

- Always keep a backup of your data before flashing
- Keep factory images available for recovery
- Don't flash images built for different devices
- Test each build before daily driving
