#!/bin/bash
# build-kernel.sh - Build the kernel with all modifications
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default values
DEVICE="${1:-tegu}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"

# Load device configuration
DEVICE_CONFIG="${ROOT_DIR}/devices/${DEVICE}/device.sh"
if [[ ! -f "$DEVICE_CONFIG" ]]; then
    log_error "Device configuration not found: $DEVICE_CONFIG"
    exit 1
fi

source "$DEVICE_CONFIG"

KERNEL_DIR="${ROOT_DIR}/kernel-${DEVICE}"
OUTPUT_DIR="${ROOT_DIR}/out/${DEVICE}"

log_info "Building kernel for device: $DEVICE"
log_info "Kernel directory: $KERNEL_DIR"

# Check prerequisites
check_prerequisites() {
    if [[ ! -d "$KERNEL_DIR" ]]; then
        log_error "Kernel directory not found: $KERNEL_DIR"
        log_error "Run setup-kernel.sh first"
        exit 1
    fi

    if [[ ! -d "${KERNEL_DIR}/aosp/drivers/kernelsu" ]]; then
        log_error "KernelSU not found in kernel source"
        log_error "Run integrate-kernelsu.sh first"
        exit 1
    fi
}

# Clean build artifacts if requested
clean_build() {
    if [[ "$CLEAN_BUILD" == "1" ]]; then
        log_info "Cleaning build artifacts..."
        cd "$KERNEL_DIR"
        rm -rf out bazel-*
        tools/bazel clean 2>/dev/null || true
        log_info "Clean complete"
    fi
}

# Run the build
run_build() {
    cd "$KERNEL_DIR"

    log_info "Starting kernel build..."
    log_info "Build target: //private/devices/google/${DEVICE}:${BUILD_TARGET}"
    log_info "Bazel config: ${BAZEL_CONFIG}"

    # Set LTO mode (none for faster builds)
    local lto_mode="${LTO:-none}"
    log_info "LTO mode: $lto_mode"

    # Run Bazel build
    # use_source_tree_aosp builds GKI from source instead of downloading prebuilt
    tools/bazel --bazelrc="private/devices/google/${DEVICE}/device.bazelrc" \
        build \
        --lto="$lto_mode" \
        --config="${BAZEL_CONFIG}" \
        --config=use_source_tree_aosp \
        "//private/devices/google/${DEVICE}:${BUILD_TARGET}"

    log_info "Build completed successfully!"
}

# Copy output files
copy_output() {
    local dist_dir="${KERNEL_DIR}/out/${DEVICE}/dist"

    if [[ ! -d "$dist_dir" ]]; then
        log_warn "Distribution directory not found: $dist_dir"
        log_warn "Build output may be in a different location"
        return 0
    fi

    mkdir -p "$OUTPUT_DIR"

    log_info "Copying build output to: $OUTPUT_DIR"

    # Copy all images
    cp -v "${dist_dir}"/*.img "$OUTPUT_DIR/" 2>/dev/null || true

    # List output files
    log_info "Output files:"
    ls -lh "$OUTPUT_DIR"/*.img 2>/dev/null || log_warn "No .img files found"
}

# Print flash instructions
print_flash_instructions() {
    log_info ""
    log_info "============================================"
    log_info "Build complete!"
    log_info "============================================"
    log_info ""
    log_info "Output directory: $OUTPUT_DIR"
    log_info ""
    log_info "To flash the kernel:"
    log_info ""
    log_info "  cd $OUTPUT_DIR"
    log_info ""
    log_info "  # Boot to bootloader"
    log_info "  adb reboot bootloader"
    log_info ""
    log_info "  # Flash boot images"
    log_info "  fastboot flash boot boot.img"
    log_info "  fastboot flash dtbo dtbo.img"
    log_info ""
    log_info "  # Reboot to fastbootd for dynamic partitions"
    log_info "  fastboot reboot fastboot"
    log_info ""
    log_info "  # Flash dynamic partitions"
    log_info "  fastboot flash vendor_kernel_boot vendor_kernel_boot.img"
    log_info "  fastboot flash vendor_dlkm vendor_dlkm.img"
    log_info "  fastboot flash system_dlkm system_dlkm.img"
    log_info ""
    log_info "  # Reboot device"
    log_info "  fastboot reboot"
    log_info ""
    log_info "See docs/FLASH.md for detailed instructions"
}

# Main
main() {
    check_prerequisites
    clean_build
    run_build
    copy_output
    print_flash_instructions
}

main "$@"
