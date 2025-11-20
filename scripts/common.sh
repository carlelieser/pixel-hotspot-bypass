#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${BLUE}[✓]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
}

get_root_dir() {
    local script_dir="$1"
    echo "$(dirname "$script_dir")"
}

init_directories() {
    SCRIPT_DIR="$(get_script_dir)"
    ROOT_DIR="$(get_root_dir "$SCRIPT_DIR")"
}

load_env() {
    local env_file="${1:-${ROOT_DIR}/.env}"

    if [[ ! -f "$env_file" ]]; then
        log_error "Configuration file not found: $env_file"
        log_error "Please copy .env.sample to .env and configure it"
        exit 1
    fi

    log_info "Loading configuration from $(basename "$env_file")"
    set -a
    source "$env_file"
    set +a
}

validate_env_vars() {
    local required_vars=("$@")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required variables in .env: ${missing_vars[*]}"
        exit 1
    fi
}

validate_enum_var() {
    local var_name="$1"
    local var_value="$2"
    local error_msg="$3"
    shift 3
    local allowed_values=("$@")

    # Create pipe-separated regex from array for validation
    local regex_pattern=$(IFS="|"; echo "${allowed_values[*]}")

    if [[ ! "$var_value" =~ ^($regex_pattern)$ ]]; then
        log_error "Invalid $var_name value: '$var_value' $error_msg"
        exit 1
    fi
}

get_kernel_dir() {
    echo "${ROOT_DIR}/kernel-${DEVICE_CODENAME}"
}

check_kernel_dir() {
    local kernel_dir="$(get_kernel_dir)"
    local error_msg="${1:-Run setup.sh first}"

    if [[ ! -d "$kernel_dir" ]]; then
        log_error "Kernel directory not found: $kernel_dir"
        log_error "$error_msg"
        exit 1
    fi

    echo "$kernel_dir"
}

check_kernelsu_integrated() {
    local kernel_dir="$(check_kernel_dir)"
    local error_msg="${1:-Run kernelsu.sh first}"

    if [[ ! -d "${kernel_dir}/aosp/drivers/kernelsu" ]]; then
        log_error "KernelSU not found in kernel source"
        log_error "$error_msg"
        exit 1
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
        log_error "Please install them and try again"
        exit 1
    fi
}

check_adb_device() {
    if ! adb devices | grep -q "device$"; then
        log_error "No device connected via ADB"
        log_error "Connect your device and enable USB debugging"
        exit 1
    fi
}

check_fastboot_device() {
    if ! command -v fastboot >/dev/null 2>&1; then
        log_error "fastboot not found. Please install Android SDK Platform Tools"
        exit 1
    fi

    if ! fastboot devices | grep -q .; then
        log_error "No device found in fastboot mode"
        log_error "Please boot your device to bootloader mode:"
        log_error "  adb reboot bootloader"
        exit 1
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
