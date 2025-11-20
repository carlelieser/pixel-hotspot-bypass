#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

init_directories

load_env
validate_env_vars "DEVICE_CODENAME" "BAZEL_CONFIG" "BUILD_TARGET" "LTO" "CLEAN_BUILD"
validate_enum_var "LTO" "$LTO" "(must be: none, thin, or full)" "none" "thin" "full"
validate_enum_var "CLEAN_BUILD" "$CLEAN_BUILD" "(must be: 0 or 1)" "0" "1"

KERNEL_DIR="$(check_kernel_dir)"
OUTPUT_DIR="${ROOT_DIR}/out/${DEVICE_CODENAME}"

log_info "Building kernel for device: $DEVICE_CODENAME"
log_info "Kernel directory: $KERNEL_DIR"

check_prerequisites() {
    check_kernelsu_integrated

    local defconfig="${KERNEL_DIR}/private/devices/google/${DEVICE_CODENAME}/${DEVICE_CODENAME}_defconfig"
    if [[ ! -f "$defconfig" ]]; then
        log_error "Defconfig not found: $defconfig"
        exit 1
    fi

    if ! grep -q "CONFIG_KSU=y" "$defconfig" 2>/dev/null; then
        log_error "CONFIG_KSU not found in defconfig"
        log_error "Run configure.sh first"
        exit 1
    fi

    if ! grep -q "CONFIG_NETFILTER_XT_TARGET_HL=y" "$defconfig" 2>/dev/null; then
        log_warn "CONFIG_NETFILTER_XT_TARGET_HL not found in defconfig"
        log_warn "Hotspot bypass may not work without this config"
    fi

    log_info "All prerequisites satisfied"
}

clean_build() {
    if [[ "$CLEAN_BUILD" == "1" ]]; then
        log_info "Cleaning build artifacts..."
        cd "$KERNEL_DIR"
        rm -rf out bazel-*
        tools/bazel clean 2>/dev/null || true
        log_info "Clean complete"
    fi
}

run_build() {
    cd "$KERNEL_DIR"

    log_info "Starting kernel build..."
    log_info "Build target: //private/devices/google/${DEVICE_CODENAME}:${BUILD_TARGET}"
    log_info "Bazel config: ${BAZEL_CONFIG}"
    log_info "LTO mode: ${LTO}"

    # use_source_tree_aosp builds GKI from source instead of downloading prebuilt
    tools/bazel --bazelrc="private/devices/google/${DEVICE_CODENAME}/device.bazelrc" \
        build \
        --lto="${LTO}" \
        --config="${BAZEL_CONFIG}" \
        --config=use_source_tree_aosp \
        "//private/devices/google/${DEVICE_CODENAME}:${BUILD_TARGET}"

    log_info "Build completed successfully!"
}

copy_output() {
    local dist_dir="${KERNEL_DIR}/out/${DEVICE_CODENAME}/dist"
    local bazel_bin="${KERNEL_DIR}/bazel-bin/private/devices/google/${DEVICE_CODENAME}"

    # Try dist directory first (standard location)
    if [[ -d "$dist_dir" ]] && [[ -n "$(find "${dist_dir}" -maxdepth 1 -name "*.img" 2>/dev/null)" ]]; then
        log_info "Found images in dist directory"
        mkdir -p "$OUTPUT_DIR"
        cp -v "${dist_dir}"/*.img "$OUTPUT_DIR/"
        log_info ""
        log_info "Output files:"
        ls -lh "$OUTPUT_DIR"/*.img
        return 0
    fi

    # Fallback: Copy from Bazel output directory
    if [[ -d "$bazel_bin" ]]; then
        log_info "Dist directory not found, copying from Bazel output..."
        mkdir -p "$OUTPUT_DIR"

        # Find and copy each required image
        local images_found=0
        for img_type in kernel_images_dtbo/dtbo.img kernel_images_boot_images/vendor_kernel_boot.img \
                        kernel_images_vendor_dlkm_image/vendor_dlkm.img kernel_images_system_dlkm_image/system_dlkm.img; do
            local img_path="${bazel_bin}/${img_type}"
            if [[ -f "$img_path" ]]; then
                local img_name=$(basename "$img_path")
                cp -v "$img_path" "$OUTPUT_DIR/"
                ((images_found++))
            fi
        done

        # Copy GKI boot image
        local gki_boot="${KERNEL_DIR}/bazel-bin/aosp/kernel_aarch64_gki_artifacts/boot.img"
        if [[ -f "$gki_boot" ]]; then
            cp -v "$gki_boot" "$OUTPUT_DIR/"
            ((images_found++))
        fi

        if [[ $images_found -gt 0 ]]; then
            log_info ""
            log_info "Copied $images_found image file(s)"
            log_info "Output files:"
            ls -lh "$OUTPUT_DIR"/*.img
            return 0
        fi
    fi

    log_error "Could not find kernel images in any expected location"
    log_error "Checked: $dist_dir and $bazel_bin"
    return 1
}

main() {
    check_prerequisites
    clean_build
    run_build
    copy_output

    print_divider "Build complete!"
    log_info ""
    log_info "Output directory: $OUTPUT_DIR"
}

main "$@"
