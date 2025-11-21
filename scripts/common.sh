#!/bin/bash
# Common utilities for PHB scripts
# UI functions are in lib/ui.sh - source that for colored output

# Legacy color definitions (for backwards compatibility)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Legacy logging (delegates to ui.sh if available)
log_info() {
    if type ui_info &>/dev/null; then
        ui_info "$1"
    else
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_warn() {
    if type ui_warning &>/dev/null; then
        ui_warning "$1"
    else
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

log_error() {
    if type ui_error &>/dev/null; then
        ui_error "$1"
    else
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

log_error_and_exit() {
    log_error "$1"
    exit "${2:-1}"
}

log_success() {
    if type ui_success &>/dev/null; then
        ui_success "$1"
    else
        echo -e "${BLUE}[✓]${NC} $1"
    fi
}

log_section() {
    if type ui_header &>/dev/null; then
        ui_header "$1"
    else
        echo -e "\n${BLUE}=== $1 ===${NC}"
    fi
}

# Configuration validation
validate_required_vars() {
    local missing=()
    [[ -z "$DEVICE_CODENAME" ]] && missing+=("DEVICE_CODENAME")
    [[ -z "$MANIFEST_BRANCH" ]] && missing+=("MANIFEST_BRANCH")
    if [[ ${#missing[@]} -gt 0 ]]; then
        if [[ "$INTERACTIVE" == true ]]; then
            return 0
        fi
        log_error "Missing required configuration: ${missing[*]}"
        exit 1
    fi
}

# Derived variable setup
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

# Command availability check
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

# Device interaction
check_fastboot_device() {
    if ! command -v fastboot >/dev/null 2>&1; then
        log_error_and_exit "fastboot not found. Please install Android SDK Platform Tools"
    fi
    if ! fastboot devices | grep -q .; then
        log_error "No device found in fastboot mode"
        log_error_and_exit "Please boot your device to bootloader: adb reboot bootloader"
    fi
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

# File operations
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

# Interactive prompts
ask_confirmation() {
    local prompt="$1"
    local default="${2:-N}"
    local yn_prompt="[y/N]"
    if [[ "$default" =~ ^[Yy]$ ]]; then
        yn_prompt="[Y/n]"
    fi
    read -p "$prompt $yn_prompt " -n 1 -r </dev/tty
    echo
    if [[ -z "$REPLY" ]]; then
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
    [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
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

# Fastboot helpers
wait_for_fastboot_device() {
    local max_wait="${1:-30}"
    local waited=0
    while ! fastboot devices | grep -q . && [[ $waited -lt $max_wait ]]; do
        sleep 1
        waited=$((waited + 1))
    done
    [[ $waited -lt $max_wait ]]
}

# Branch discovery
fetch_device_branches() {
    local device="$1"
    local manifest_url="${2:-https://android.googlesource.com/kernel/manifest}"
    local refs_url="${manifest_url}/+refs/heads?format=TEXT"

    curl -sL "$refs_url" 2>/dev/null | \
        grep -oE "android-gs-${device}-[^ ]+" | \
        sort -Vr | \
        head -20
}

get_device_family() {
    local codename="$1"
    case "$codename" in
        tegu) echo "tegu" ;;
        tokay|caiman|komodo) echo "caimito" ;;
        comet) echo "comet" ;;
        husky|shiba) echo "shusky" ;;
        akita) echo "akita" ;;
        felix) echo "felix" ;;
        lynx) echo "lynx" ;;
        tangorpro) echo "tangorpro" ;;
        cheetah|panther) echo "pantah" ;;
        bluejay) echo "bluejay" ;;
        oriole|raven) echo "raviole" ;;
        *) echo "$codename" ;;
    esac
}

# Legacy helpers (kept for compatibility)
print_divider() {
    local message="${1:-}"
    echo ""
    echo "============================================"
    if [[ -n "$message" ]]; then
        echo "$message"
        echo "============================================"
    fi
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
