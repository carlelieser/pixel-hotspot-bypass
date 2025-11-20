# Troubleshooting Guide

Common issues and solutions for the pixel-kernel-hotspot-bypass project.

## Build Issues

### KSU_VERSION / KERNEL_SU_VERSION undefined

**Error**:
```
error: expected expression
    u32 version = KERNEL_SU_VERSION;
```

**Cause**: Bazel sandbox doesn't include .git directory, so KernelSU's git-based version detection fails.

**Solution**: The `integrate-kernelsu.sh` script handles this automatically. If integrating manually, add at the **beginning** of `drivers/kernelsu/kernel/Makefile`:

```makefile
ccflags-y += -DKSU_VERSION=12882
ccflags-y += -DKSU_VERSION_TAG=\"v1.1.1\"
```

### Macro Redefinition Error

**Error**:
```
error: 'KSU_VERSION' macro redefined [-Werror,-Wmacro-redefined]
```

**Cause**: After adding hardcoded version, the original version detection code still runs and tries to define the same macros.

**Solution**: Comment out these lines in `drivers/kernelsu/kernel/Makefile`:
- Line ~24: `ccflags-y += -DKSU_VERSION_TAG=\"$(KSU_VERSION_TAG)\"`
- Line ~27: `ccflags-y += -DKSU_VERSION_TAG=\"v0.0.0\"`
- Line ~37: `ccflags-y += -DKSU_VERSION=$(KSU_VERSION)`
- Line ~40: `ccflags-y += -DKSU_VERSION=12882`

Use sed:
```bash
sed -i 's/^ccflags-y += -DKSU_VERSION/#DISABLED &/' Makefile
```

### Version Tag String Error

**Error**:
```
error: use of undeclared identifier 'v1'
    .version_tag = v1.1.1,
```

**Cause**: Version tag interpreted as C identifier instead of string literal.

**Solution**: Use escaped quotes in Makefile:
```makefile
# Wrong
ccflags-y += -DKSU_VERSION_TAG="v1.1.1"

# Correct
ccflags-y += -DKSU_VERSION_TAG=\"v1.1.1\"
```

### CONFIG_NETFILTER_XT_TARGET_HL Not Enabled

**Symptom**: TTL/HL iptables rules don't work after build.

**Cause**: Config not in correct defconfig or missing dependencies.

**Solution**:
1. Add to device defconfig (e.g., `tegu_defconfig`):
   ```
   CONFIG_NETFILTER_ADVANCED=y
   CONFIG_NETFILTER_XT_TARGET_HL=y
   ```

2. Verify in final config:
   ```bash
   grep TARGET_HL out/.config
   ```

3. Ensure `CONFIG_NETFILTER_ADVANCED=y` is also set (it's a dependency).

### savedefconfig Validation Error

**Error**:
```
ERROR: savedefconfig does not match aosp/arch/arm64/configs/gki_defconfig
```

**Cause**: Adding `CONFIG_KSU=y` to gki_defconfig when KernelSU's Kconfig already has `default y`, causing savedefconfig to remove it as redundant.

**Solution**: Don't add CONFIG_KSU to gki_defconfig - only add it to device defconfig. The `apply-defconfig.sh` script handles this correctly. If manually editing:
```bash
# Device defconfig (tegu_defconfig) - ADD this:
CONFIG_KSU=y

# GKI defconfig (gki_defconfig) - DON'T add CONFIG_KSU, only add:
CONFIG_NETFILTER_XT_TARGET_HL=y
```

### Bazel Cache Issues

**Symptom**: Changes not taking effect, old errors persist.

**Solution**: Clean Bazel cache:
```bash
cd kernel-tegu
tools/bazel clean
# or for full clean:
tools/bazel clean --expunge
rm -rf out bazel-*
```

### Out of Memory During Build

**Symptom**: Build process killed, OOM errors.

**Solutions**:
1. Use `LTO=none` to reduce memory usage:
   ```bash
   LTO=none ./scripts/build-kernel.sh tegu
   ```

2. Add swap space:
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. Close other applications

4. Build on machine with more RAM

## Flashing Issues

### "FAILED (remote: not allowed)"

**Cause**: Bootloader is locked.

**Solution**:
```bash
# Enable OEM unlocking in Developer Options first
adb reboot bootloader
fastboot flashing unlock
```

### Dynamic Partition Flash Failure

**Error**:
```
FAILED (remote: Cannot flash dynamic partition...)
```

**Cause**: Trying to flash dynamic partition (vendor_dlkm, etc.) in bootloader mode.

**Solution**: Use fastbootd:
```bash
fastboot reboot fastboot
fastboot flash vendor_dlkm vendor_dlkm.img
```

### Device Not Found

**Symptom**: `fastboot devices` shows nothing.

**Solutions**:
1. Check USB cable and port
2. Install proper USB drivers (Windows)
3. Add udev rules (Linux):
   ```bash
   echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666"' | sudo tee /etc/udev/rules.d/51-android.rules
   sudo udevadm control --reload-rules
   ```

## Runtime Issues

### KernelSU Manager Shows "Not Installed"

**Possible causes**:
1. KernelSU not compiled into kernel
2. Version too old for Manager app
3. Wrong kernel flashed

**Solutions**:
1. Check dmesg:
   ```bash
   adb shell dmesg | grep -i ksu
   ```

2. Verify CONFIG_KSU=y in your build:
   ```bash
   grep KSU= out/.config
   ```

3. Ensure version ≥ 12797:
   ```bash
   adb shell dmesg | grep "KernelSU version"
   ```

### KernelSU Version Too Low

**Error**: Manager app reports version needs to be 12797+.

**Cause**: Old KernelSU-Next source or version not properly set.

**Solution**:
1. Update to latest KernelSU-Next
2. Set version 12882 in Makefile
3. Clean build and reflash

### TTL/HL iptables Rules Fail

**Error**:
```
iptables: No chain/target/match by that name.
```

**Cause**: xt_HL module not loaded or not compiled.

**Solutions**:
1. Check if module exists:
   ```bash
   adb shell find /vendor -name "*xt_HL*"
   ```

2. Try loading module:
   ```bash
   adb shell insmod /path/to/xt_HL.ko
   ```

3. Verify CONFIG_NETFILTER_XT_TARGET_HL=y in build

### Hotspot Not Bypassing Detection

**Symptom**: Carrier still detects tethering.

**Possible causes**:
1. iptables rules not applied
2. Wrong interface name
3. Additional carrier detection methods

**Solutions**:
1. Verify rules are active:
   ```bash
   adb shell iptables -t mangle -L POSTROUTING -v
   ```

2. Check interface:
   ```bash
   adb shell ip link show
   ```
   (Usually wlan0, wlan1, or similar)

3. Check unlimited-hotspot module logs:
   ```bash
   adb shell dmesg | grep hotspot
   ```

### Device Bootloop

**Symptom**: Device continuously reboots.

**Most Common Cause**: Missing `vendor_kernel_boot.img` flash! Pixel 9a requires ALL THREE boot images (boot, dtbo, vendor_kernel_boot) to be flashed from bootloader mode.

**Solutions**:
1. Boot to bootloader (hold Power + Volume Down during boot)

2. Flash vendor_kernel_boot.img if you skipped it:
   ```bash
   cd kernel-tegu
   fastboot flash vendor_kernel_boot bazel-bin/private/devices/google/tegu/kernel_images_boot_images/vendor_kernel_boot.img
   fastboot reboot
   ```

3. If still looping, flash stock boot image:
   ```bash
   fastboot flash boot /path/to/stock/boot.img
   ```

4. If still looping, try factory reset from bootloader or flash full factory image

**Remember**: The correct flash sequence is:
```bash
# In bootloader mode
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash vendor_kernel_boot vendor_kernel_boot.img  # ← Don't forget this!
fastboot reboot fastboot

# In fastbootd mode
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot flash system_dlkm system_dlkm.img
```

### WiFi/Cellular Issues After Flash

**Symptom**: No WiFi or cellular connectivity.

**Possible cause**: vendor_dlkm mismatch.

**Solution**:
1. Ensure vendor_dlkm matches your Android version
2. Try flashing stock vendor_dlkm from factory image
3. Full factory reset may be needed

## Version Compatibility

### KernelSU-Next Manager Compatibility

| Manager Version | Minimum KSU Version |
|-----------------|---------------------|
| 0.7.x           | 12000               |
| 0.8.x           | 12500               |
| 1.0.x           | 12797               |

If Manager reports incompatibility, update KernelSU-Next version in build.

### Android Version

Ensure your kernel source matches your device's Android version:
- Check factory image version
- Use correct manifest branch (e.g., `android-gs-tegu-6.1-android14`)

## Getting More Help

### Collect Debug Info

```bash
# Kernel version and build info
adb shell uname -a
adb shell cat /proc/version

# KernelSU status
adb shell dmesg | grep -i ksu > ksu_dmesg.txt

# Kernel config
adb shell zcat /proc/config.gz | grep -E "KSU|NETFILTER" > kernel_config.txt

# Boot log
adb shell dmesg > full_dmesg.txt
```

### Useful Commands

```bash
# Check kernel modules
adb shell lsmod

# Check SELinux status
adb shell getenforce

# Monitor kernel messages
adb shell dmesg -w

# Check iptables
adb shell iptables -L -v -n

# Check network interfaces
adb shell ip addr
```

### Common Log Locations

- Kernel messages: `adb shell dmesg`
- Boot log: `adb logcat -b all`
- KernelSU logs: `adb shell dmesg | grep ksu`
