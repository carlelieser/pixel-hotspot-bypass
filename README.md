# Pixel Kernel Hotspot Bypass

Custom Android kernel for Google Pixel devices with TTL/HL modification and KernelSU-Next support to bypass carrier hotspot restrictions.

## Features

- **TTL/HL Modification**: `CONFIG_NETFILTER_XT_TARGET_HL=y` enabled for iptables TTL/hop-limit mangling
- **KernelSU-Next**: Root access via [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) (version 10209+)
- **Hotspot Bypass**: Works with [unlimited-hotspot](https://github.com/AdisonCavani/unlimited-hotspot) module

## Supported Devices

| Device | Codename | SoC | Kernel | Status |
|--------|----------|-----|--------|--------|
| Pixel 9a | tegu | Tensor G4 (zumapro) | 6.1.124 | Tested |
| Pixel 9 | tokay | Tensor G4 (zumapro) | 6.1.124 | Untested |
| Pixel 9 Pro | caiman | Tensor G4 (zumapro) | 6.1.124 | Untested |
| Pixel 9 Pro XL | komodo | Tensor G4 (zumapro) | 6.1.124 | Untested |
| Pixel 9 Pro Fold | comet | Tensor G4 (zumapro) | 6.1.124 | Untested |

## Quick Start

### Prerequisites

- Linux build machine (x86_64) with 16GB+ RAM
- ~15-20GB free disk space (~11GB kernel source + ~2-4GB build artifacts)
- `repo`, `git`, `python3`, `bazel` installed
- Android SDK Platform Tools (fastboot)
- Unlocked bootloader on target device

**Note**: Ensure `repo` is in your PATH:
```bash
export PATH="$HOME/bin:$PATH"
```

### Configuration

Before building, configure the project for your device:

```bash
# Copy the sample environment file
cp .env.sample .env

# IMPORTANT: Detect your device's correct kernel branch
# (requires device connected via ADB)
./scripts/detect-device-info.sh

# The script will tell you the correct MANIFEST_BRANCH to use
# Edit .env and update MANIFEST_BRANCH if needed
```

**Why this matters**: The kernel branch must match your device's Android version. Building the wrong version can cause boot failures.

See [Configuration Options](#configuration-options) below for all available settings.

### Build

```bash
# Clone this repository
git clone https://github.com/carlelieser/pixel-kernel-hotspot-bypass.git
cd pixel-kernel-hotspot-bypass

# Configure for your device (see above)
cp .env.sample .env
# Edit .env with correct MANIFEST_BRANCH

# Set up kernel source (downloads ~50GB)
./scripts/setup-kernel.sh tegu

# Integrate KernelSU-Next
./scripts/integrate-kernelsu.sh

# Apply defconfig modifications
./scripts/apply-defconfig.sh tegu

# Build kernel
./scripts/build-kernel.sh tegu
```

### Flash

See [docs/FLASH.md](docs/FLASH.md) for detailed instructions.

```bash
# Quick flash (device connected via USB, from kernel-tegu directory)
cd kernel-tegu

# Bootloader mode - flash boot images
fastboot flash boot bazel-bin/aosp/kernel_aarch64_gki_artifacts/boot.img
fastboot flash dtbo bazel-bin/private/devices/google/tegu/kernel_images_dtbo/dtbo.img
fastboot flash vendor_kernel_boot bazel-bin/private/devices/google/tegu/kernel_images_boot_images/vendor_kernel_boot.img

# Reboot to fastbootd for dynamic partitions
fastboot reboot fastboot

# Flash dynamic partitions
fastboot flash vendor_dlkm bazel-bin/private/devices/google/tegu/kernel_images_vendor_dlkm_image/vendor_dlkm.img
fastboot flash system_dlkm bazel-bin/private/devices/google/tegu/kernel_images_system_dlkm_image/system_dlkm.img

# Reboot
fastboot reboot
```

## How It Works

### Hotspot Bypass

Carriers detect tethering by inspecting the TTL (Time To Live) field in IP packets. When a device is tethered, the TTL is decremented, revealing the traffic as tethered.

This kernel enables the `xt_HL` netfilter target, allowing iptables rules to modify the TTL/HL values:

```bash
# Example iptables rules (applied via KernelSU module)
iptables -t mangle -A POSTROUTING -o wlan+ -j TTL --ttl-set 64
ip6tables -t mangle -A POSTROUTING -o wlan+ -j HL --hl-set 64
```

### KernelSU-Next

KernelSU-Next provides root access without modifying the system partition. It integrates directly into the kernel and is managed via the KernelSU Manager app.

**Important**: KernelSU-Next version 12797+ is required for the latest Manager app.

## Documentation

- [BUILD.md](docs/BUILD.md) - Detailed build instructions
- [FLASH.md](docs/FLASH.md) - Flashing instructions
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and solutions

## Configuration Options

All build settings can be customized via the `.env` file. Copy `.env.sample` to `.env` and modify as needed.

### Essential Settings

| Variable | Description | Example |
|----------|-------------|---------|
| `DEVICE_CODENAME` | Device codename | `tegu` (Pixel 9a) |
| `MANIFEST_BRANCH` | Kernel source branch - **must match your Android version** | `android-gs-tegu-6.1-android16` |

### KernelSU Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `KSU_VERSION` | KernelSU version number | `12882` |
| `KSU_VERSION_TAG` | KernelSU version tag | `v1.1.1` |
| `KERNELSU_REPO` | KernelSU repository URL | `https://github.com/rifsxd/KernelSU-Next` |
| `KERNELSU_BRANCH` | KernelSU branch | `next` |

### Build Settings

| Variable | Description | Options | Default |
|----------|-------------|---------|---------|
| `LTO` | Link-time optimization | `none`, `thin`, `full` | `none` |
| `CLEAN_BUILD` | Clean before building | `0` (incremental), `1` (clean) | `0` |
| `AUTO_EXPUNGE` | Auto-clean Bazel cache after config changes | `0` (manual), `1` (automatic) | `0` |

### Finding Your Correct Branch

**Method 1: Automatic Detection (Recommended)**
```bash
# Connect your device via ADB
./scripts/detect-device-info.sh
```

**Method 2: Manual Check**
```bash
adb shell getprop ro.build.version.release  # Android version (15, 16, etc.)
adb shell uname -r                           # Kernel version (6.1.x)
```

Then construct the branch: `android-gs-{device}-{kernel_ver}-android{android_ver}`

**Examples**:
- Pixel 9a on Android 15: `android-gs-tegu-6.1-android15-d4`
- Pixel 9a on Android 16: `android-gs-tegu-6.1-android16`
- Pixel 9a on Android 16 Beta: `android-gs-tegu-6.1-android16-beta`

## Directory Structure

```
pixel-kernel-hotspot-bypass/
├── README.md
├── .env.sample              # Configuration template
├── docs/
│   ├── BUILD.md
│   ├── FLASH.md
│   └── TROUBLESHOOTING.md
├── scripts/
│   ├── detect-device-info.sh
│   ├── setup-kernel.sh
│   ├── integrate-kernelsu.sh
│   ├── apply-defconfig.sh
│   └── build-kernel.sh
├── patches/
│   └── kernelsu-version-fix.patch
└── devices/
    └── tegu/
        └── device.sh
```

## Credits

- [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) - Root solution
- [unlimited-hotspot](https://github.com/AdisonCavani/unlimited-hotspot) - KernelSU module for iptables rules
- Google Android Kernel Team - Base kernel source

## Disclaimer

This project is for educational and personal use only. Bypassing carrier restrictions may violate your terms of service. Use at your own risk.

## License

Scripts and documentation in this repository are MIT licensed. Kernel source and KernelSU-Next have their own licenses.
