# Pixel Hotspot Bypass

Helper script to build and flash custom kernels for your Pixel 9 series device. By default, PHB will build a KernelSUNext-integrated kernel with TTL/HL modules enabled. This, combined with the [unlimited hotspot module](https://github.com/felikcat/unlimited-hotspot) allows us to effectively bypass hotspot restrictions on our Pixels!

## 🚀 Quick Start

```bash
./phb.sh run --interactive
```

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

## ⚙️ Build Options

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

```bash
./phb.sh post-install                  # KSU-Next manager + unlimited-hotspot module
./phb.sh post-install --manager ksu    # use original KernelSU manager instead
./phb.sh post-install --skip-manager   # module only (if manager already installed)
```

## Configuration

```bash
./phb.sh run --interactive   # creates .phb.conf
./phb.sh run                 # uses saved config
```

## 📚 Resources

- [Building Android Kernels](https://source.android.com/docs/setup/build/building-kernels) — Google's official guide
- [KernelSU](https://github.com/tiann/KernelSU) — Original KernelSU project
- [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) — KernelSU fork used by PHB
- [unlimited-hotspot](https://github.com/felikcat/unlimited-hotspot) — Hotspot bypass module
