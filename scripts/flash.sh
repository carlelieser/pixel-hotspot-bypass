#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

init_directories
load_env

OUTPUT_DIR="${ROOT_DIR}/out/${DEVICE_CODENAME}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
    log_error "Output directory not found: $OUTPUT_DIR"
    log_error "Run build.sh first"
    exit 1
fi

REQUIRED_IMAGES=(
    "boot.img"
    "dtbo.img"
    "vendor_kernel_boot.img"
    "vendor_dlkm.img"
    "system_dlkm.img"
)

check_images() {
    log_info "Checking for kernel images in: $OUTPUT_DIR"

    local missing=()
    for img in "${REQUIRED_IMAGES[@]}"; do
        if [[ ! -f "$OUTPUT_DIR/$img" ]]; then
            missing+=("$img")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required image files: ${missing[*]}"
        log_error "Run build.sh first"
        exit 1
    fi

    log_info "All required images found"
}

check_device() {
    check_fastboot_device
    log_info "Device detected in fastboot mode"
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

    log_info "Bootloader images flashed successfully"
}

flash_fastbootd_images() {
    local slot=$(get_current_slot)

    log_info "Rebooting to fastbootd for dynamic partitions..."
    fastboot reboot fastboot

    log_info "Waiting for device to enter fastbootd..."
    sleep 5

    # Poll for device availability with timeout to handle slow fastbootd transitions
    local max_wait=30
    local waited=0
    while ! fastboot devices | grep -q . && [[ $waited -lt $max_wait ]]; do
        sleep 1
        waited=$((waited + 1))
    done

    if [[ $waited -ge $max_wait ]]; then
        log_error "Device did not enter fastbootd mode"
        log_error "Please manually reboot to fastbootd and run:"
        log_error "  cd $OUTPUT_DIR"
        log_error "  fastboot flash vendor_kernel_boot_${slot} vendor_kernel_boot.img"
        log_error "  fastboot flash vendor_dlkm_${slot} vendor_dlkm.img"
        log_error "  fastboot flash system_dlkm_${slot} system_dlkm.img"
        exit 1
    fi

    log_info "Flashing dynamic partition images to slot $slot..."
    cd "$OUTPUT_DIR"

    fastboot flash vendor_kernel_boot_${slot} vendor_kernel_boot.img
    fastboot flash vendor_dlkm_${slot} vendor_dlkm.img
    fastboot flash system_dlkm_${slot} system_dlkm.img

    log_info "Dynamic partition images flashed successfully"
}

reboot_device() {
    log_info "Rebooting device..."
    fastboot reboot
    log_info "Device is rebooting"
}

print_manual_instructions() {
    print_divider "Manual Flash Instructions"
    log_info ""
    log_warn "IMPORTANT: Detect and flash to your current active slot!"
    log_info ""
    log_info "If you prefer to flash manually:"
    log_info ""
    log_info "  cd $OUTPUT_DIR"
    log_info ""
    log_info "  adb reboot bootloader"
    log_info ""
    log_info "  # Detect current slot"
    log_info "  SLOT=\$(fastboot getvar current-slot 2>&1 | grep 'current-slot:' | awk '{print \$2}')"
    log_info "  echo \"Flashing to slot: \$SLOT\""
    log_info ""
    log_info "  # Flash bootloader images"
    log_info "  fastboot flash boot_\${SLOT} boot.img"
    log_info "  fastboot flash dtbo_\${SLOT} dtbo.img"
    log_info ""
    log_info "  # Reboot to fastbootd"
    log_info "  fastboot reboot fastboot"
    log_info ""
    log_info "  # Flash dynamic partitions"
    log_info "  fastboot flash vendor_kernel_boot_\${SLOT} vendor_kernel_boot.img"
    log_info "  fastboot flash vendor_dlkm_\${SLOT} vendor_dlkm.img"
    log_info "  fastboot flash system_dlkm_\${SLOT} system_dlkm.img"
    log_info ""
    log_info "  fastboot reboot"
    log_info ""
}

main() {
    print_divider "Kernel Flash Tool"
    log_info ""
    log_info "Device: $DEVICE_CODENAME"
    log_info "Output: $OUTPUT_DIR"
    log_info ""

    check_images

    echo ""
    if ! ask_confirmation "Flash kernel automatically?" "Y"; then
        print_manual_instructions
        exit 0
    fi

    check_device
    flash_bootloader_images
    flash_fastbootd_images
    reboot_device

    print_divider "Flash complete!"
    log_info ""
    log_info "Your device is rebooting with the new kernel"
}

main "$@"
