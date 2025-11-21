#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"
SOC="${SOC:-zumapro}"
BAZEL_CONFIG="${BAZEL_CONFIG:-}"
BUILD_TARGET="${BUILD_TARGET:-}"
LTO="${LTO:-none}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build kernel for Pixel devices

REQUIRED OPTIONS (or set via environment variables):
  -d, --device CODENAME     Device codename (e.g., tegu, tokay, caiman)

OPTIONAL OPTIONS:
  --soc SOC                 SoC type (default: zumapro)
  --bazel-config CONFIG     Bazel config (default: same as device)
  --build-target TARGET     Build target (default: {soc}_{device}_dist)
  -l, --lto MODE            LTO mode: none, thin, full (default: none)
  -c, --clean               Clean build (default: incremental)
  -h, --help                Show this help message

EXAMPLES:
  $0 -d tegu
  $0 -d tegu --clean --lto thin
  $0 -d tegu --build-target zumapro_tegu_dist
  export DEVICE_CODENAME=tegu
  export LTO=thin
  $0

ENVIRONMENT VARIABLES:
  DEVICE_CODENAME, SOC, BAZEL_CONFIG, BUILD_TARGET, LTO, CLEAN_BUILD

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage ;;
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            --soc) SOC="$2"; shift 2 ;;
            --bazel-config) BAZEL_CONFIG="$2"; shift 2 ;;
            --build-target) BUILD_TARGET="$2"; shift 2 ;;
            -l|--lto) LTO="$2"; shift 2 ;;
            -c|--clean) CLEAN_BUILD=1; shift ;;
            *) log_error "Unknown option: $1"; echo ""; show_usage ;;
        esac
    done
}

validate_build_config() {
    local missing=()
    [[ -z "$DEVICE_CODENAME" ]] && missing+=("DEVICE_CODENAME")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required configuration: ${missing[*]}"
        log_error ""
        log_error "Either:"
        log_error "  1. Pass via command-line flags (see --help)"
        log_error "  2. Set environment variables: ${missing[*]}"
        exit 1
    fi
    [[ ! "$LTO" =~ ^(none|thin|full)$ ]] && log_error_and_exit "Invalid LTO value: '$LTO' (must be: none, thin, or full)"
    [[ ! "$CLEAN_BUILD" =~ ^(0|1)$ ]] && log_error_and_exit "Invalid CLEAN_BUILD value: '$CLEAN_BUILD' (must be: 0 or 1)"
}

build_check_prerequisites() {
    check_kernelsu_integrated
    local defconfig="${KERNEL_DIR}/private/devices/google/${DEVICE_CODENAME}/${DEVICE_CODENAME}_defconfig"
    if [[ ! -f "$defconfig" ]]; then
        log_error_and_exit "Defconfig not found: $defconfig"
    fi
    if ! grep -q "CONFIG_KSU=y" "$defconfig" 2>/dev/null; then
        log_error_and_exit "CONFIG_KSU not found - run configure first"
    fi
    if ! grep -q "CONFIG_NETFILTER_XT_TARGET_HL=y" "$defconfig" 2>/dev/null; then
        log_warn "CONFIG_NETFILTER_XT_TARGET_HL missing - hotspot bypass may not work"
    fi
}

clean_build() {
    if [[ "$CLEAN_BUILD" == "1" ]]; then
        log_info "Cleaning build artifacts..."
        cd "$KERNEL_DIR" && rm -rf out bazel-* && tools/bazel clean 2>/dev/null || true
        log_success "Clean complete"
    fi
}

run_build_process() {
    cd "$KERNEL_DIR"
    log_info "Building: ${BUILD_TARGET} (LTO=${LTO})"
    tools/bazel --bazelrc="private/devices/google/${DEVICE_CODENAME}/device.bazelrc" \
        build \
        --lto="${LTO}" \
        --config="${BAZEL_CONFIG}" \
        --config=use_source_tree_aosp \
        "//private/devices/google/${DEVICE_CODENAME}:${BUILD_TARGET}"
    log_success "Build completed"
}

copy_output() {
    local dist_dir="${KERNEL_DIR}/out/${DEVICE_CODENAME}/dist"
    local bazel_bin="${KERNEL_DIR}/bazel-bin/private/devices/google/${DEVICE_CODENAME}"
    if [[ -d "$dist_dir" ]] && [[ -n "$(find "${dist_dir}" -maxdepth 1 -name "*.img" 2>/dev/null)" ]]; then
        mkdir -p "$OUTPUT_DIR"
        cp -v "${dist_dir}"/*.img "$OUTPUT_DIR/"
        log_success "Output copied from dist directory"
        ls -lh "$OUTPUT_DIR"/*.img
        return 0
    fi
    if [[ -d "$bazel_bin" ]]; then
        mkdir -p "$OUTPUT_DIR"
        local images_found=0
        for img_type in kernel_images_dtbo/dtbo.img kernel_images_boot_images/vendor_kernel_boot.img \
                        kernel_images_vendor_dlkm_image/vendor_dlkm.img kernel_images_system_dlkm_image/system_dlkm.img; do
            local img_path="${bazel_bin}/${img_type}"
            [[ -f "$img_path" ]] && cp -v "$img_path" "$OUTPUT_DIR/" && ((images_found++))
        done
        local gki_boot="${KERNEL_DIR}/bazel-bin/aosp/kernel_aarch64_gki_artifacts/boot.img"
        [[ -f "$gki_boot" ]] && cp -v "$gki_boot" "$OUTPUT_DIR/" && ((images_found++))
        if [[ $images_found -gt 0 ]]; then
            log_success "Copied $images_found image(s) from Bazel output"
            ls -lh "$OUTPUT_DIR"/*.img
            return 0
        fi
    fi
    log_error "Could not find kernel images in any expected location"
    log_error "Checked: $dist_dir and $bazel_bin"
    return 1
}

run_build() {
    log_section "Build Kernel ($DEVICE_CODENAME)"
    build_check_prerequisites
    clean_build
    run_build_process
    copy_output
    log_success "Build complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_build_config
    set_derived_vars
    run_build
fi
