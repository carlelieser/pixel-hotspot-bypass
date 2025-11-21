# Pixel Hotspot Bypass

Build custom Pixel kernel with KernelSU-Next and TTL/HL patch support for Pixel 9 series devices.

## Quick Start

```bash
./phb.sh run --interactive
```

This will guide you through device selection, patch selection, and build options.

## Usage

```bash
./phb.sh detect                    # → Device: tegu (Pixel 9a), Branch: android-gs-tegu-6.1-android16
./phb.sh run -d tegu -b android-gs-tegu-6.1-android16

./phb.sh setup -d tegu -b android-gs-tegu-6.1-android16
./phb.sh configure -d tegu --patches kernelsu,ttl-hl
./phb.sh build -d tegu
./phb.sh flash -d tegu
./phb.sh post-install

./phb.sh run --skip-setup --skip-configure   # rebuild only, keeps existing source/patches
./phb.sh build --help
```

## Commands

| Command | Description |
|---------|-------------|
| `detect` | Auto-detect connected device and show recommended branch |
| `setup` | Download kernel source (~15GB, takes 10-30min) |
| `configure` | Apply KernelSU and TTL/HL patches to kernel source |
| `build` | Compile kernel (~10-45min depending on LTO mode) |
| `flash` | Flash boot images via fastboot |
| `post-install` | Install KSU manager APK and unlimited-hotspot module |
| `run` | Execute full workflow (setup → configure → build → flash) |

## Build Options

```bash
./phb.sh build -d tegu --lto none    # fastest build (~10min), larger kernel
./phb.sh build -d tegu --lto thin    # balanced (~25min), moderate optimization
./phb.sh build -d tegu --lto full    # slowest (~45min), smallest kernel

./phb.sh build -d tegu --clean       # remove cached build artifacts first
```

## Patches

| Patch | Description |
|-------|-------------|
| `kernelsu` | KernelSU-Next root solution |
| `ttl-hl` | TTL/HL kernel modifications |

```bash
./phb.sh configure -d tegu --patches kernelsu,ttl-hl   # both patches (default)
./phb.sh configure -d tegu --patches kernelsu          # root only, no TTL/HL
```

## Post-Install

After flashing, install the KernelSU manager app and hotspot module:

```bash
./phb.sh post-install                  # KSU-Next manager + unlimited-hotspot module
./phb.sh post-install --manager ksu    # use original KernelSU manager instead
./phb.sh post-install --skip-manager   # module only (if manager already installed)
```

The module is installed via `ksud` or extracted to `/data/adb/modules/`. Reboot to activate.

## Supported Devices

| Codename | Device |
|----------|--------|
| `tegu` | Pixel 9a |
| `tokay` | Pixel 9 |
| `caiman` | Pixel 9 Pro |
| `komodo` | Pixel 9 Pro XL |
| `comet` | Pixel 9 Pro Fold |

## Configuration

Settings are saved to `.phb.conf` after first run:

```bash
./phb.sh run --interactive   # creates .phb.conf
./phb.sh run                 # uses saved config
```
