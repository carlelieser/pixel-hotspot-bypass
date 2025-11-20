# Build Instructions

Complete guide for building the kernel with hotspot bypass modifications.

## Prerequisites

### Hardware Requirements

- x86_64 Linux machine (or VM)
- 16GB+ RAM (32GB recommended)
- ~15-20GB free disk space (~11GB kernel source + ~2-4GB build artifacts)
- Fast internet connection (for downloading kernel source)

### Software Requirements

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y git python3 python3-pip curl wget bc bison flex \
    libssl-dev libelf-dev libncurses-dev make gcc

# Install repo tool
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

# Add to ~/.bashrc for persistence
echo 'export PATH=~/bin:$PATH' >> ~/.bashrc
```

### Build Machine Setup

For best results, use a native Linux machine. If using a VM:
- Enable nested virtualization if possible
- Allocate at least 8 CPU cores
- Use SSD storage

**Note**: Building on macOS (even with Docker) is not recommended due to case-sensitivity issues and performance.

## Build Steps

### 1. Clone This Repository

```bash
git clone https://github.com/carlelieser/pixel-kernel-hotspot-bypass.git
cd pixel-kernel-hotspot-bypass
```

### 2. Set Up Kernel Source

This downloads ~50GB of kernel source code.

```bash
./scripts/setup-kernel.sh tegu
```

This will:
- Initialize repo with the correct manifest
- Sync all kernel source repositories
- Create a build script in the kernel directory

### 3. Integrate KernelSU-Next

```bash
./scripts/integrate-kernelsu.sh
```

This will:
- Clone KernelSU-Next repository
- Apply version fix for Bazel sandbox
- Integrate into kernel drivers

### 4. Apply Defconfig Modifications

```bash
./scripts/apply-defconfig.sh tegu
```

This will:
- Add CONFIG_KSU=y
- Add CONFIG_NETFILTER_XT_TARGET_HL=y
- Add CONFIG_NETFILTER_ADVANCED=y

### 5. Build the Kernel

```bash
./scripts/build-kernel.sh tegu
```

Build time: 30-60 minutes depending on hardware.

The output will be in `kernel-tegu/bazel-bin/` with images in specific subdirectories:
- `bazel-bin/aosp/kernel_aarch64_gki_artifacts/boot.img`
- `bazel-bin/private/devices/google/tegu/kernel_images_boot_images/vendor_kernel_boot.img`
- `bazel-bin/private/devices/google/tegu/kernel_images_dtbo/dtbo.img`
- `bazel-bin/private/devices/google/tegu/kernel_images_vendor_dlkm_image/vendor_dlkm.img`
- `bazel-bin/private/devices/google/tegu/kernel_images_system_dlkm_image/system_dlkm.img`

## Build Options

### LTO Mode

By default, LTO (Link Time Optimization) is disabled for faster builds:

```bash
LTO=none ./scripts/build-kernel.sh tegu
```

For optimized production builds:

```bash
LTO=thin ./scripts/build-kernel.sh tegu
```

### Clean Build

To start fresh:

```bash
CLEAN_BUILD=1 ./scripts/build-kernel.sh tegu
```

Or manually:

```bash
cd kernel-tegu
rm -rf out bazel-*
tools/bazel clean
```

## Troubleshooting Build Issues

### KSU_VERSION undefined

**Error**: `error: expected expression u32 version = KERNEL_SU_VERSION;`

**Cause**: Bazel sandbox doesn't include .git directory, so git-based version detection fails.

**Solution**: The `integrate-kernelsu.sh` script applies this fix automatically. If you're integrating manually, add these lines at the **beginning** of `drivers/kernelsu/kernel/Makefile`:

```makefile
ccflags-y += -DKSU_VERSION=12882
ccflags-y += -DKSU_VERSION_TAG=\"v1.1.1\"
```

And comment out the duplicate definitions later in the file.

### Macro Redefinition Error

**Error**: `'KSU_VERSION' macro redefined [-Werror,-Wmacro-redefined]`

**Cause**: Multiple definitions of KSU_VERSION in Makefile.

**Solution**: Comment out lines with `#DISABLED`:
- Line 24: `ccflags-y += -DKSU_VERSION_TAG=\"$(KSU_VERSION_TAG)\"`
- Line 27: `ccflags-y += -DKSU_VERSION_TAG=\"v0.0.0\"`
- Line 37: `ccflags-y += -DKSU_VERSION=$(KSU_VERSION)`
- Line 40: `ccflags-y += -DKSU_VERSION=12882`

### Version Tag String Error

**Error**: `error: use of undeclared identifier 'v1'`

**Cause**: Version tag not properly escaped as C string.

**Solution**: Use escaped quotes: `\"v1.1.1\"` not `"v1.1.1"`

### Out of Memory

**Error**: Build process killed or OOM errors.

**Solution**:
- Close other applications
- Add swap space
- Use `LTO=none` to reduce memory usage
- Build on a machine with more RAM

### Repo Sync Failures

**Error**: Various git/repo sync errors.

**Solution**:
```bash
cd kernel-tegu
repo sync -c -j4 --no-tags --no-clone-bundle --fail-fast
```

Reduce `-j` value if you have bandwidth issues.

## Verifying the Build

After building, verify the output:

```bash
cd kernel-tegu
ls -lh bazel-bin/aosp/kernel_aarch64_gki_artifacts/boot.img
ls -lh bazel-bin/private/devices/google/tegu/kernel_images_boot_images/vendor_kernel_boot.img
ls -lh bazel-bin/private/devices/google/tegu/kernel_images_dtbo/dtbo.img
ls -lh bazel-bin/private/devices/google/tegu/kernel_images_vendor_dlkm_image/vendor_dlkm.img
ls -lh bazel-bin/private/devices/google/tegu/kernel_images_system_dlkm_image/system_dlkm.img
```

Expected files with approximate sizes:
- boot.img (~64MB - GKI kernel with KernelSU)
- vendor_kernel_boot.img (~8.4MB)
- dtbo.img (~1.5MB)
- vendor_dlkm.img (~45MB)
- system_dlkm.img (~12MB)

## Next Steps

See [FLASH.md](FLASH.md) for flashing instructions.
