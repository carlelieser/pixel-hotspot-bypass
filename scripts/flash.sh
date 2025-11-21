#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"
source "$ROOT_DIR/lib/ui.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"
CURRENT_SLOT=""

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Flash kernel images to Pixel device

REQUIRED OPTIONS (or set via environment variables):
  -d, --device CODENAME     Device codename (e.g., tegu, tokay, caiman)

OPTIONAL OPTIONS:
  -o, --output-dir DIR      Output directory containing kernel images
                            (default: ../out/{device})
  -h, --help                Show this help message

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage ;;
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
            *) ui_error "Unknown option: $1"; show_usage ;;
        esac
    done
}

validate_flash_config() {
    if [[ -z "$DEVICE_CODENAME" ]]; then
        ui_error "Device codename required (-d)"
        exit 1
    fi
}

# Progress bar helper
progress_bar() {
    local current=$1
    local total=$2
    local width=20
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "${COLOR_GREEN}"
    printf '█%.0s' $(seq 1 $filled 2>/dev/null) || true
    printf "${COLOR_GRAY}"
    printf '░%.0s' $(seq 1 $empty 2>/dev/null) || true
    printf "${COLOR_RESET}"
}

# Flash a single partition with progress
flash_partition() {
    local partition="$1"
    local image="$2"
    local current="$3"
    local total="$4"

    printf "\r\033[K  [$(progress_bar $current $total)] %d/%d ${COLOR_CYAN}%s${COLOR_RESET}..." "$current" "$total" "$partition"

    if fastboot flash "${partition}_${CURRENT_SLOT}" "$image" &>/dev/null; then
        printf "\r\033[K  [$(progress_bar $current $total)] %d/%d ${COLOR_GREEN}✓${COLOR_RESET} %s\n" "$current" "$total" "$partition"
        return 0
    else
        printf "\r\033[K  [$(progress_bar $current $total)] %d/%d ${COLOR_RED}✗${COLOR_RESET} %s ${COLOR_RED}failed${COLOR_RESET}\n" "$current" "$total" "$partition"
        return 1
    fi
}

check_images() {
    local required_images=("boot.img" "dtbo.img" "vendor_kernel_boot.img" "vendor_dlkm.img" "system_dlkm.img")
    local found=0
    local missing=()

    echo ""
    echo "${COLOR_BOLD}Images${COLOR_RESET}"

    for img in "${required_images[@]}"; do
        printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking %s..." "$img"

        if [[ -f "$OUTPUT_DIR/$img" ]]; then
            local size=$(du -h "$OUTPUT_DIR/$img" 2>/dev/null | cut -f1)
            printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} %-25s ${COLOR_GRAY}%s${COLOR_RESET}\n" "$img" "$size"
            ((found++))
        else
            printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} %-25s ${COLOR_YELLOW}not found${COLOR_RESET}\n" "$img"
            missing+=("$img")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        ui_error "Missing images - run build first"
        exit 1
    fi
}

check_device() {
    echo ""
    echo "${COLOR_BOLD}Device${COLOR_RESET}"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking fastboot..."

    if ! command -v fastboot &>/dev/null; then
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} fastboot not found\n"
        ui_error "Install Android SDK Platform Tools"
        exit 1
    fi
    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} fastboot found\n"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking device..."

    if ! fastboot devices | grep -q .; then
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} No device in fastboot mode\n"
        echo ""
        ui_info "Boot to fastboot: ${COLOR_CYAN}adb reboot bootloader${COLOR_RESET}"
        exit 1
    fi
    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Device connected\n"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Getting slot..."

    CURRENT_SLOT=$(fastboot getvar current-slot 2>&1 | grep "current-slot:" | awk '{print $2}' | tr -d '\r')
    if [[ -z "$CURRENT_SLOT" ]]; then
        CURRENT_SLOT="a"
        printf "\r\033[K  ${COLOR_YELLOW}⚠${COLOR_RESET} Slot unknown, using ${COLOR_CYAN}%s${COLOR_RESET}\n" "$CURRENT_SLOT"
    else
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Active slot: ${COLOR_CYAN}%s${COLOR_RESET}\n" "$CURRENT_SLOT"
    fi
}

flash_bootloader() {
    echo ""
    echo "${COLOR_BOLD}Flashing Bootloader Partitions${COLOR_RESET}"

    cd "$OUTPUT_DIR"

    flash_partition "boot" "boot.img" 1 5
    flash_partition "dtbo" "dtbo.img" 2 5
    flash_partition "vendor_kernel_boot" "vendor_kernel_boot.img" 3 5
}

flash_dynamic() {
    echo ""
    echo "${COLOR_BOLD}Flashing Dynamic Partitions${COLOR_RESET}"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Rebooting to fastbootd..."
    fastboot reboot fastboot &>/dev/null
    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Rebooting to fastbootd\n"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Waiting for fastbootd..."

    local waited=0
    local max_wait=30
    while ! fastboot devices 2>/dev/null | grep -q . && [[ $waited -lt $max_wait ]]; do
        sleep 1
        ((waited++))
        # Animate spinner
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        printf "\r  ${COLOR_BLUE}${frames[$((waited % 10))]}${COLOR_RESET} Waiting for fastbootd... ${COLOR_GRAY}%ds${COLOR_RESET}" "$waited"
    done

    if [[ $waited -ge $max_wait ]]; then
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} Timeout waiting for fastbootd\n"
        echo ""
        ui_error "Manually flash remaining partitions:"
        echo "  ${COLOR_GRAY}fastboot flash vendor_dlkm_${CURRENT_SLOT} vendor_dlkm.img${COLOR_RESET}"
        echo "  ${COLOR_GRAY}fastboot flash system_dlkm_${CURRENT_SLOT} system_dlkm.img${COLOR_RESET}"
        exit 1
    fi

    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Device in fastbootd ${COLOR_GRAY}(%ds)${COLOR_RESET}\n" "$waited"

    cd "$OUTPUT_DIR"

    flash_partition "vendor_dlkm" "vendor_dlkm.img" 4 5
    flash_partition "system_dlkm" "system_dlkm.img" 5 5
}

reboot_device() {
    echo ""
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Rebooting device..."
    fastboot reboot &>/dev/null
    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Device rebooting\n"
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${COLOR_GREEN}✓${COLOR_RESET} Flash complete! Device is rebooting."
    echo ""
    echo "  After boot, verify with:"
    echo "  ${COLOR_GRAY}adb shell uname -r${COLOR_RESET}"
}

run_flash() {
    ui_header "Flash Kernel"
    echo "  Device: ${COLOR_CYAN}$DEVICE_CODENAME${COLOR_RESET}"
    echo "  Output: ${COLOR_GRAY}$OUTPUT_DIR${COLOR_RESET}"

    check_images
    check_device
    flash_bootloader
    flash_dynamic
    reboot_device
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_flash_config
    set_derived_vars
    run_flash
fi
