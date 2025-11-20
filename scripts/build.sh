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

    if [[ ! -d "$dist_dir" ]]; then
        log_warn "Distribution directory not found: $dist_dir"
        log_warn "Build output may be in a different location"
        return 0
    fi

    mkdir -p "$OUTPUT_DIR"

    log_info "Copying build output to: $OUTPUT_DIR"

    local img_count=$(find "${dist_dir}" -maxdepth 1 -name "*.img" 2>/dev/null | wc -l)
    if [[ $img_count -eq 0 ]]; then
        log_warn "No .img files found in $dist_dir"
        return 0
    fi

    cp -v "${dist_dir}"/*.img "$OUTPUT_DIR/"
    log_info "Copied $img_count image file(s)"

    log_info ""
    log_info "Output files:"
    ls -lh "$OUTPUT_DIR"/*.img
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
