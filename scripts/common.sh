#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_error_and_exit() { log_error "$1"; exit "${2:-1}"; }
log_success() { echo -e "${BLUE}[✓]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

validate_required_vars() {
    local missing=()
    [[ -z "$DEVICE_CODENAME" ]] && missing+=("DEVICE_CODENAME")
    [[ -z "$MANIFEST_BRANCH" ]] && missing+=("MANIFEST_BRANCH")
    if [[ ${#missing[@]} -gt 0 ]]; then
        if [[ "$INTERACTIVE" == true ]]; then
            return 0
        fi
        log_error "Missing required configuration: ${missing[*]}"
        log_error ""
        log_error "Either:"
        log_error "  1. Use --interactive flag for guided setup"
        log_error "  2. Set environment variables: ${missing[*]}"
        log_error "  3. Pass via command-line flags (see --help)"
        exit 1
    fi
}

set_derived_vars() {
    [[ -z "$BAZEL_CONFIG" ]] && BAZEL_CONFIG="$DEVICE_CODENAME"
    [[ -z "$BUILD_TARGET" ]] && BUILD_TARGET="${SOC}_${DEVICE_CODENAME}_dist"
    DEVICE="$DEVICE_CODENAME"
    KERNEL_DIR="${ROOT_DIR}/kernel-${DEVICE}"
    OUTPUT_DIR="${ROOT_DIR}/out/${DEVICE_CODENAME}"
    DEFCONFIG_PATH="private/devices/google/${DEVICE_CODENAME}/${DEVICE_CODENAME}_defconfig"
}

get_kernel_dir() {
    echo "${ROOT_DIR}/kernel-${DEVICE_CODENAME}"
}

check_kernel_dir() {
    local kernel_dir="$(get_kernel_dir)"
    local error_msg="${1:-Run setup first}"
    if [[ ! -d "$kernel_dir" ]]; then
        log_error "Kernel directory not found: $kernel_dir"
        log_error_and_exit "$error_msg"
    fi
    echo "$kernel_dir"
}

check_kernelsu_integrated() {
    local kernel_dir="$(check_kernel_dir)"
    local error_msg="${1:-Run configuration first}"
    if [[ ! -d "${kernel_dir}/aosp/drivers/kernelsu" ]]; then
        log_error "KernelSU not found in kernel source"
        log_error_and_exit "$error_msg"
    fi
}

check_commands() {
    local required_commands=("$@")
    local missing=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error_and_exit "Please install them and try again"
    fi
}

check_fastboot_device() {
    if ! command -v fastboot >/dev/null 2>&1; then
        log_error_and_exit "fastboot not found. Please install Android SDK Platform Tools"
    fi
    if ! fastboot devices | grep -q .; then
        log_error "No device found in fastboot mode"
        log_error "Please boot your device to bootloader mode:"
        log_error_and_exit "  adb reboot bootloader"
    fi
}

print_divider() {
    local message="${1:-}"
    echo ""
    echo "============================================"
    if [[ -n "$message" ]]; then
        echo "$message"
        echo "============================================"
    fi
}

ask_confirmation() {
    local prompt="$1"
    local default="${2:-N}"
    local yn_prompt="[y/N]"
    if [[ "$default" =~ ^[Yy]$ ]]; then
        yn_prompt="[Y/n]"
    fi
    read -p "$prompt $yn_prompt " -n 1 -r
    echo
    if [[ -z "$REPLY" ]]; then
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
    [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
}

check_adb_device() {
    if ! command -v adb >/dev/null 2>&1; then
        log_error_and_exit "adb not found. Please install Android SDK Platform Tools"
    fi
    if ! adb devices | grep -q "device$"; then
        log_error "No device connected via ADB"
        log_error_and_exit "Connect your device and enable USB debugging"
    fi
}

get_device_property() {
    local property="$1"
    adb shell getprop "$property" 2>/dev/null | tr -d '\r'
}

get_kernel_version() {
    adb shell uname -r 2>/dev/null | tr -d '\r'
}

parse_kernel_major_minor() {
    local kernel_version="$1"
    echo "$kernel_version" | grep -oE '^[0-9]+\.[0-9]+'
}

get_android_manifest_version() {
    local android_version="$1"
    if [[ "$android_version" =~ ^([0-9]+) ]]; then
        echo "android${BASH_REMATCH[1]}"
    else
        echo "unknown"
    fi
}

detect_build_suffix() {
    local build_fingerprint="$1"
    if echo "$build_fingerprint" | grep -qi "beta\|preview\|dp"; then
        echo "-beta"
    else
        echo ""
    fi
}

build_recommended_branch() {
    local device="$1"
    local kernel_ver="$2"
    local android_ver="$3"
    local suffix="$4"
    echo "android-gs-${device}-${kernel_ver}-${android_ver}${suffix}"
}

require_file() {
    local file="$1"
    local error_msg="${2:-File not found: $file}"
    if [[ ! -f "$file" ]]; then
        log_error_and_exit "$error_msg"
    fi
}

optional_file_check() {
    local file="$1"
    local warn_msg="${2:-File not found, skipping: $file}"
    if [[ ! -f "$file" ]]; then
        log_warn "$warn_msg"
        return 1
    fi
    return 0
}

check_pattern_exists() {
    local pattern="$1"
    local file="$2"
    local success_msg="${3:-Pattern already exists}"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        log_info "$success_msg"
        return 0
    fi
    return 1
}

confirm_and_remove_directory() {
    local dir="$1"
    local item_name="${2:-Directory}"
    local action="${3:-re-create}"
    if [[ -d "$dir" ]]; then
        log_warn "$item_name already exists: $dir"
        if ask_confirmation "Remove and $action?"; then
            rm -rf "$dir"
            return 0
        else
            log_info "Skipping..."
            return 1
        fi
    fi
    return 0
}

disable_makefile_line() {
    local makefile="$1"
    local pattern="$2"
    sed -i "s/^${pattern}$/#DISABLED &/" "$makefile"
}

copy_image_if_exists() {
    local source="$1"
    local dest="$2"
    local counter_var="$3"
    if [[ -f "$source" ]]; then
        cp -v "$source" "$dest/"
        if [[ -n "$counter_var" ]]; then
            eval "$counter_var=\$(( \$$counter_var + 1 ))"
        fi
        return 0
    fi
    return 1
}

wait_for_fastboot_device() {
    local max_wait="${1:-30}"
    local waited=0
    while ! fastboot devices | grep -q . && [[ $waited -lt $max_wait ]]; do
        sleep 1
        waited=$((waited + 1))
    done
    [[ $waited -lt $max_wait ]]
}

