# Pixel Hotspot Bypass

A collection of scripts for building a customized kernel for Google Pixel devices with [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) integration and [TTL/HL](https://en.wikipedia.org/wiki/Time_to_live) hotspot bypass support.

## Overview

Automated build system for Google Pixel kernels with KernelSU-Next root management and TTL/HL modifications for hotspot bypass. Combine with the [unlimited-hotspot module](https://github.com/felikcat/unlimited-hotspot) to bypass carrier restrictions.

**Supported Devices:** Pixel 9 series (Tensor G4)

## Compatibility

**Platform:** Linux or macOS (Windows requires WSL2)
**Storage:** 100GB+ free disk space
**Memory:** 16GB+ RAM recommended

## Environment Setup

<details>
<summary><b>Install Dependencies</b></summary>

**On Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install git-core gnupg flex bison build-essential zip curl \
  zlib1g-dev libc6-dev-i386 libncurses5 x11proto-core-dev libx11-dev \
  lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig
```

**On macOS:**
```bash
brew install git gnupg coreutils
```
</details>

<details>
<summary><b>Install Platform Tools</b></summary>

Download and install [Android Platform Tools](https://developer.android.com/tools/releases/platform-tools) for ADB/Fastboot:

```bash
# Extract and add to PATH
unzip platform-tools-*.zip
export PATH=$PATH:$PWD/platform-tools
```
</details>

<details>
<summary><b>Install repo Tool</b></summary>

```bash
mkdir -p ~/.bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod a+x ~/.bin/repo
export PATH=$PATH:~/.bin
```
</details>

<details>
<summary><b>Prepare Device</b></summary>

1. [Enable Developer Options](https://developer.android.com/studio/debug/dev-options#enable) (tap Build Number 7 times)
2. [Enable USB Debugging](https://developer.android.com/studio/debug/dev-options#debugging) in Developer Options
3. Unlock bootloader (warning: wipes device)
   ```bash
   adb reboot bootloader
   fastboot flashing unlock
   ```
</details>

## Quick Start

### 1. Setup

```bash
git clone https://github.com/yourusername/pixel-hotspot-bypass.git
cd pixel-hotspot-bypass
cp .env.sample .env
```

### 2. Configuration

Edit `.env` with your device details. Use the detection script if unsure:

```bash
./tools/detect-device-info.sh
```

Minimum required settings:
```bash
DEVICE_CODENAME=tegu
MANIFEST_BRANCH=android-gs-tegu-6.1-android16
```

### 3. Build

Run the complete build pipeline:

```bash
./scripts/start.sh
```

This will:
1. Download kernel source (~10-15 minutes)
2. Configure kernel (includes KernelSU integration and defconfig changes) (~3 minutes)
3. Build kernel (~30-60 minutes)
4. Optionally flash to device

### 4. Flash

If not flashed during build:

```bash
./scripts/flash.sh
```

Device must be in bootloader mode with USB debugging enabled.

## Configuration

See [.env.sample](.env.sample) for complete configuration documentation.

## Post-Installation

After flashing the kernel:

1. Install [KernelSU Manager](https://github.com/rifsxd/KernelSU-Next/releases)
2. Install [unlimited-hotspot module](https://github.com/felikcat/unlimited-hotspot) via KernelSU Manager
3. Reboot device
4. Verify hotspot functionality

## Resources

**Documentation:**
- [Google Kernel Build Guide](https://source.android.com/docs/setup/build/building-kernels)
- [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next)
- [Pixel Factory Images](https://developers.google.com/android/images)

**Tools:**
- [Android Platform Tools (ADB/Fastboot)](https://developer.android.com/tools/releases/platform-tools)
- [unlimited-hotspot module](https://github.com/felikcat/unlimited-hotspot)

**Community:**
- [XDA Developers - Pixel 9 Series](https://xdaforums.com/c/google-pixel-9-series.13305/)
- [r/GooglePixel](https://reddit.com/r/GooglePixel)

## License

Build scripts provided as-is under MIT license. Kernel source is GPL v2. No warranty provided.

## Acknowledgments

- Google for open-source Pixel kernels
- rifsxd for KernelSU-Next
- felikcat for unlimited-hotspot module
- XDA community for documentation and support

---

**Note:** This project is for educational and research purposes. Modifying carrier restrictions may violate service agreements. Use at your own discretion.
