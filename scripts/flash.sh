#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"

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

EXAMPLES:
  $0 -d tegu
  $0 -d tegu -o /path/to/images
  export DEVICE_CODENAME=tegu
  $0

ENVIRONMENT VARIABLES:
  DEVICE_CODENAME, OUTPUT_DIR

PREREQUISITES:
  - Device must be in fastboot mode (adb reboot bootloader)
  - Required images in output directory:
    * boot.img
    * dtbo.img
    * vendor_kernel_boot.img
    * vendor_dlkm.img
    * system_dlkm.img

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage ;;
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; echo ""; show_usage ;;
        esac
    done
}

validate_flash_config() {
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
}

check_images() {
    local required_images=("boot.img" "dtbo.img" "vendor_kernel_boot.img" "vendor_dlkm.img" "system_dlkm.img")
    local missing=()
    for img in "${required_images[@]}"; do
        [[ ! -f "$OUTPUT_DIR/$img" ]] && missing+=("$img")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error_and_exit "Missing images: ${missing[*]} - run build first"
    fi
    log_success "All required images found"
}

get_current_slot() {
    local slot=$(fastboot getvar current-slot 2>&1 | grep "current-slot:" | awk '{print $2}' | tr -d '\r')
    if [[ -z "$slot" ]]; then
        log_warn "Could not detect current slot, defaulting to 'a'"
        slot="a"
    fi
    echo "$slot"
}

flash_bootloader_images() {
    local slot=$(get_current_slot)
    log_info "Current active slot: $slot"
    log_info "Flashing bootloader images to slot $slot..."
    cd "$OUTPUT_DIR"
    fastboot flash boot_${slot} boot.img
    fastboot flash dtbo_${slot} dtbo.img
    fastboot flash vendor_kernel_boot_${slot} vendor_kernel_boot.img
    log_info "Bootloader images flashed successfully"
}

flash_fastbootd_images() {
    local slot=$(get_current_slot)
    log_info "Rebooting to fastbootd for dynamic partitions..."
    fastboot reboot fastboot
    log_info "Waiting for device to enter fastbootd..."
    sleep 5
    if ! wait_for_fastboot_device 30; then
        log_error "Device did not enter fastbootd mode"
        log_error "Please manually reboot to fastbootd and run:"
        log_error "  cd $OUTPUT_DIR"
        log_error "  fastboot flash vendor_dlkm_${slot} vendor_dlkm.img"
        log_error "  fastboot flash system_dlkm_${slot} system_dlkm.img"
        exit 1
    fi
    log_info "Flashing dynamic partition images to slot $slot..."
    cd "$OUTPUT_DIR"
    fastboot flash vendor_dlkm_${slot} vendor_dlkm.img
    fastboot flash system_dlkm_${slot} system_dlkm.img
    log_info "Dynamic partition images flashed successfully"
}

reboot_device() {
    log_info "Rebooting device..."
    fastboot reboot
    log_info "Device is rebooting"
}

run_flash() {
    log_section "Flash Kernel"
    check_images
    check_fastboot_device
    flash_bootloader_images
    flash_fastbootd_images
    reboot_device
    log_success "Flash complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_flash_config
    set_derived_vars
    run_flash
fi
