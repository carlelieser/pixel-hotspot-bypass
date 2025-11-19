# Device configuration for Pixel 9a (tegu)
# Source this file to get device-specific build variables

# Device information
DEVICE_NAME="Pixel 9a"
DEVICE_CODENAME="tegu"
SOC="zumapro"
SOC_NAME="Tensor G4"

# Kernel version
KERNEL_VERSION="6.1.99"
ANDROID_VERSION="android14-11"

# Manifest for repo init
MANIFEST_URL="https://android.googlesource.com/kernel/manifest"
MANIFEST_BRANCH="android-gs-tegu-6.1-android14"

# Build configuration
BAZEL_CONFIG="tegu"
BUILD_TARGET="zumapro_tegu_dist"

# Defconfig path (relative to kernel root)
DEFCONFIG_PATH="private/devices/google/tegu/tegu_defconfig"

# GKI defconfig (for additional modifications)
GKI_DEFCONFIG_PATH="aosp/arch/arm64/configs/gki_defconfig"

# Output images to flash
OUTPUT_IMAGES=(
    "boot.img"
    "dtbo.img"
    "vendor_kernel_boot.img"
    "vendor_dlkm.img"
    "system_dlkm.img"
)

# Partitions that need fastbootd (dynamic partitions)
FASTBOOTD_PARTITIONS=(
    "vendor_kernel_boot"
    "vendor_dlkm"
    "system_dlkm"
)

# Partitions that can be flashed in bootloader mode
BOOTLOADER_PARTITIONS=(
    "boot"
    "dtbo"
)
