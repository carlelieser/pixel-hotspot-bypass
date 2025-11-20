#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

init_directories
load_env

print_divider "Pixel Kernel Build - Complete Workflow"
log_info ""
log_info "Device: $DEVICE_CODENAME"
log_info ""
log_info "This script will run the complete build process:"
log_info "  1. Setup kernel source"
log_info "  2. Configure kernel (includes KernelSU integration)"
log_info "  3. Build kernel"
log_info "  4. Flash to device (optional)"
log_info ""

if ! ask_confirmation "Continue with complete build?"; then
    log_info "Aborted by user"
    exit 0
fi

run_step() {
    local step_num="$1"
    local step_name="$2"
    local script="$3"

    print_divider "Step $step_num: $step_name"
    log_info ""

    if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
        log_error "Script not found: ${script}"
        exit 1
    fi

    "${SCRIPT_DIR}/${script}"

    log_info ""
    log_success "Step $step_num complete: $step_name"
    log_info ""
}

main() {
    run_step "1" "Setup Kernel Source" "setup.sh"
    run_step "2" "Configure Kernel" "configure.sh"
    run_step "3" "Build Kernel" "build.sh"

    print_divider "Build Process Complete!"
    log_info ""
    log_success "Kernel built successfully for $DEVICE_CODENAME"
    log_info ""
    log_info "Output directory: ${ROOT_DIR}/out/${DEVICE_CODENAME}"
    log_info ""

    echo ""
    if ask_confirmation "Flash kernel to device now?" "N"; then
        run_step "4" "Flash Kernel" "flash.sh"

        print_divider "All Done!"
        log_info ""
        log_success "Kernel flashed successfully!"
        log_info "Your device is rebooting with KernelSU-Next and hotspot bypass"
    else
        log_info "To flash later, run: ./scripts/flash.sh"
    fi
}

main "$@"
