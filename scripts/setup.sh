#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-}"
MANIFEST_URL="${MANIFEST_URL:-https://android.googlesource.com/kernel/manifest}"
SOC="${SOC:-zumapro}"
BAZEL_CONFIG="${BAZEL_CONFIG:-}"
BUILD_TARGET="${BUILD_TARGET:-}"
LTO="${LTO:-none}"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup kernel source for Pixel devices

REQUIRED OPTIONS (or set via environment variables):
  -d, --device CODENAME     Device codename (e.g., tegu, tokay, caiman)
  -b, --branch BRANCH       Manifest branch (e.g., android-gs-tegu-6.1-android16)

OPTIONAL OPTIONS:
  -u, --manifest-url URL    Manifest URL (default: https://android.googlesource.com/kernel/manifest)
  --soc SOC                 SoC type (default: zumapro)
  --bazel-config CONFIG     Bazel config (default: same as device)
  --build-target TARGET     Build target (default: {soc}_{device}_dist)
  --lto MODE                LTO mode: none, thin, full (default: none)
  -h, --help                Show this help message

EXAMPLES:
  $0 -d tegu -b android-gs-tegu-6.1-android16
  $0 -d tegu -b android-gs-tegu-6.1-android16 -u https://custom.url/manifest
  export DEVICE_CODENAME=tegu
  export MANIFEST_BRANCH=android-gs-tegu-6.1-android16
  $0

ENVIRONMENT VARIABLES:
  DEVICE_CODENAME, MANIFEST_BRANCH, MANIFEST_URL, SOC, BAZEL_CONFIG,
  BUILD_TARGET, LTO

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage ;;
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            -b|--branch) MANIFEST_BRANCH="$2"; shift 2 ;;
            -u|--manifest-url) MANIFEST_URL="$2"; shift 2 ;;
            --soc) SOC="$2"; shift 2 ;;
            --bazel-config) BAZEL_CONFIG="$2"; shift 2 ;;
            --build-target) BUILD_TARGET="$2"; shift 2 ;;
            --lto) LTO="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; echo ""; show_usage ;;
        esac
    done
}

validate_setup_config() {
    local missing=()
    [[ -z "$DEVICE_CODENAME" ]] && missing+=("DEVICE_CODENAME")
    [[ -z "$MANIFEST_BRANCH" ]] && missing+=("MANIFEST_BRANCH")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required configuration: ${missing[*]}"
        log_error ""
        log_error "Either:"
        log_error "  1. Pass via command-line flags (see --help)"
        log_error "  2. Set environment variables: ${missing[*]}"
        exit 1
    fi
}

setup_check_prerequisites() {
    check_commands repo git python3
    log_success "Prerequisites satisfied"
}

setup_kernel_source() {
    if ! confirm_and_remove_directory "$KERNEL_DIR" "Kernel directory" "re-download"; then
        return 0
    fi
    mkdir -p "$KERNEL_DIR" && cd "$KERNEL_DIR"
    log_info "Initializing repo: $MANIFEST_BRANCH"
    repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --depth=1
    log_info "Syncing kernel source (this may take a while)..."
    repo sync -c -j$(nproc) --no-tags --no-clone-bundle --fail-fast
    log_success "Kernel source synced"
}

patch_kleaf() {
    local filegroup_bzl="${KERNEL_DIR}/build/kernel/kleaf/impl/kernel_filegroup.bzl"
    if ! optional_file_check "$filegroup_bzl" "kernel_filegroup.bzl not found, skipping"; then
        return 0
    fi
    if check_pattern_exists "strip_modules = False" "$filegroup_bzl" "Kleaf already patched"; then
        return 0
    fi
    log_info "Patching Kleaf build system..."
    sed -i 's/collect_unstripped_modules = ctx.attr.collect_unstripped_modules,$/collect_unstripped_modules = ctx.attr.collect_unstripped_modules,\n        strip_modules = False,/' "$filegroup_bzl"
    if ! grep -q "config_env_and_outputs_info = ext_mod_env_and_outputs_info" "$filegroup_bzl"; then
        sed -i 's/modules_install_env_and_outputs_info = ext_mod_env_and_outputs_info,$/modules_install_env_and_outputs_info = ext_mod_env_and_outputs_info,\n        config_env_and_outputs_info = ext_mod_env_and_outputs_info,/' "$filegroup_bzl"
    fi
    if ! grep -q "module_kconfig = depset()" "$filegroup_bzl"; then
        sed -i 's/module_scripts = module_srcs.module_scripts,$/module_scripts = module_srcs.module_scripts,\n        module_kconfig = depset(),/' "$filegroup_bzl"
    fi
    log_success "Kleaf patched"
}

create_build_script() {
    local build_script="${KERNEL_DIR}/build_${DEVICE_CODENAME}.sh"
    cat > "$build_script" << EOF
#!/bin/bash
set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

LTO="\${LTO:-${LTO}}"
BAZEL_CONFIG="\${BAZEL_CONFIG:-${BAZEL_CONFIG}}"
BUILD_TARGET="\${BUILD_TARGET:-${BUILD_TARGET}}"

tools/bazel --bazelrc="private/devices/google/${DEVICE_CODENAME}/device.bazelrc" \\
    build \\
    --lto="\$LTO" \\
    --config="\$BAZEL_CONFIG" \\
    --config=use_source_tree_aosp \\
    "//private/devices/google/${DEVICE_CODENAME}:\$BUILD_TARGET"

echo "Build complete! Output in bazel-bin/"
EOF
    chmod +x "$build_script"
    log_success "Build script created: build_${DEVICE_CODENAME}.sh"
}

run_setup() {
    log_section "Setup Kernel Source"
    setup_check_prerequisites
    setup_kernel_source
    patch_kleaf
    create_build_script
    log_success "Setup complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_setup_config
    set_derived_vars
    run_setup
fi
