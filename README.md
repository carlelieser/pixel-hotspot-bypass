# Pixel Hotspot Bypass

Build custom Pixel kernel with KernelSU-Next and TTL/HL hotspot bypass support for Pixel 9 series devices.

## Quick Start

### Interactive Mode

```bash
./phb.sh run --interactive
```

This will guide you through:
1. Device selection (with auto-detection if connected)
2. Patch selection (KernelSU, TTL/HL bypass)
3. Build options (LTO mode, clean build)
4. Full workflow execution

## Usage

```bash
# Detect connected device
phb.sh detect

# Full workflow
phb.sh run -d tegu -b android-gs-tegu-6.1-android16

# Individual steps
phb.sh setup -d tegu -b android-gs-tegu-6.1-android16
phb.sh configure -d tegu --patches kernelsu,ttl-hl
phb.sh build -d tegu --clean --lto thin
phb.sh flash -d tegu

# Quick rebuild (skip setup/configure)
phb.sh run --skip-setup --skip-configure

# Help
phb.sh --help
phb.sh build --help
```

```bash
# Full workflow
./phb.sh -d tegu -b android-gs-tegu-6.1-android16

# Individual steps
./phb.sh -d tegu -b android-gs-tegu-6.1-android16 --build-only
./phb.sh -d tegu -b android-gs-tegu-6.1-android16 --flash-only

# With options
./phb.sh -d tegu -b android-gs-tegu-6.1-android16 --clean --flash
```

## Commands

- `detect` - Auto-detect connected device and show recommended config
- `setup` - Download and setup kernel source
- `configure` - Apply selected patches (KernelSU, TTL/HL bypass, etc.)
- `build` - Compile kernel
- `flash` - Flash kernel to device
- `post-install` - Install KSU manager APK and unlimited-hotspot module
- `run` - Execute full workflow (setup → configure → build → flash)

## Available Patches

- **kernelsu** - KernelSU-Next root solution
- **ttl-hl** - TTL/HL hotspot bypass modifications

Future: SUSFS support (coming soon)

## Configuration

First run with `--interactive` creates `.phb.conf` with your settings.
Subsequent runs automatically use saved configuration:

```bash
# First run - interactive setup
./phb.sh run --interactive

# Subsequent runs - uses saved config
./phb.sh run
```

## Build Process

1. **Setup** - Sync AOSP kernel source tree using repo tool
2. **Configure** - Apply selected patches (KernelSU, TTL/HL bypass)
3. **Build** - Compile kernel and generate boot images
4. **Flash** - Install boot images via fastboot
5. **Post-Install** - Install KSU manager and modules (optional)

## Post-Install

After flashing the kernel, install the KernelSU manager and modules:

```bash
# Install KernelSU-Next manager and unlimited-hotspot module
./phb.sh post-install

# Use original KernelSU manager instead
./phb.sh post-install --manager ksu

# Only install the unlimited-hotspot module
./phb.sh post-install --skip-manager
```

The post-install command will:
1. Download and install the KSU/KSUNext manager APK
2. Download the [unlimited-hotspot](https://github.com/felikcat/unlimited-hotspot) module
3. Push the module to your device's Download folder

After running, open the KSU manager app and install the module from `/sdcard/Download/`.

## Supported Devices

- **tegu** - Pixel 9a
- **tokay** - Pixel 9
- **caiman** - Pixel 9 Pro
- **komodo** - Pixel 9 Pro XL
- **comet** - Pixel 9 Pro Fold

## Examples

```bash
# Interactive first-time setup
./phb.sh run --interactive

# Auto-detect and build
./phb.sh detect
./phb.sh run -d tegu -b android-gs-tegu-6.1-android16

# Clean build with thin LTO
./phb.sh build -d tegu --clean --lto thin

# Build with only KernelSU (no TTL bypass)
./phb.sh configure -d tegu --patches kernelsu
./phb.sh build -d tegu

# Quick rebuild after code changes
./phb.sh run --skip-setup --skip-configure

# After flashing, install KSU manager and unlimited-hotspot module
./phb.sh post-install
```

