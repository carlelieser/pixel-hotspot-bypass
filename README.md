# Pixel Kernel Hotspot Bypass

Custom Android kernel for Google Pixel devices with TTL/HL modification and KernelSU-Next support to bypass carrier hotspot restrictions.

## Features

- **TTL/HL Modification**: `CONFIG_NETFILTER_XT_TARGET_HL=y` enabled for iptables TTL/hop-limit mangling
- **KernelSU-Next**: Root access via [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) (v1.1.1 / version 12882)
- **Hotspot Bypass**: Works with [unlimited-hotspot](https://github.com/AdisonCavani/unlimited-hotspot) module

## Supported Devices

| Device | Codename | SoC | Kernel | Status |
|--------|----------|-----|--------|--------|
| Pixel 9a | tegu | Tensor G4 (zumapro) | 6.1.99 | Tested |
| Pixel 9 | tokay | Tensor G4 (zumapro) | 6.1.99 | Untested |
| Pixel 9 Pro | caiman | Tensor G4 (zumapro) | 6.1.99 | Untested |
| Pixel 9 Pro XL | komodo | Tensor G4 (zumapro) | 6.1.99 | Untested |
| Pixel 9 Pro Fold | comet | Tensor G4 (zumapro) | 6.1.99 | Untested |

## Quick Start

### Prerequisites

- Linux build machine (x86_64) with 16GB+ RAM
- ~100GB free disk space
- `repo`, `git`, `python3`, `bazel` installed
- Android SDK Platform Tools (fastboot)
- Unlocked bootloader on target device

**Note**: Ensure `repo` is in your PATH:
```bash
export PATH="$HOME/bin:$PATH"
```

### Build

```bash
# Clone this repository
git clone https://github.com/carlelieser/pixel-kernel-hotspot-bypass.git
cd pixel-kernel-hotspot-bypass

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
# Quick flash (device connected via USB)
cd out/dist

# Bootloader mode
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img

# Reboot to fastbootd for dynamic partitions
fastboot reboot fastboot

# Flash dynamic partitions
fastboot flash vendor_kernel_boot vendor_kernel_boot.img
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot flash system_dlkm system_dlkm.img

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

## Directory Structure

```
pixel-kernel-hotspot-bypass/
├── README.md
├── docs/
│   ├── BUILD.md
│   ├── FLASH.md
│   └── TROUBLESHOOTING.md
├── scripts/
│   ├── setup-kernel.sh
│   ├── integrate-kernelsu.sh
│   ├── apply-defconfig.sh
│   └── build-kernel.sh
├── patches/
│   └── kernelsu-version-fix.patch
├── devices/
│   └── tegu/
│       └── device.sh
└── releases/
```

## Credits

- [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) - Root solution
- [unlimited-hotspot](https://github.com/AdisonCavani/unlimited-hotspot) - KernelSU module for iptables rules
- Google Android Kernel Team - Base kernel source

## Disclaimer

This project is for educational and personal use only. Bypassing carrier restrictions may violate your terms of service. Use at your own risk.

## License

Scripts and documentation in this repository are MIT licensed. Kernel source and KernelSU-Next have their own licenses.
