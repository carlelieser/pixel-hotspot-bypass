#!/bin/bash
# apply-defconfig.sh - Apply defconfig modifications for hotspot bypass
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default values
DEVICE="${1:-tegu}"

# Load device configuration
DEVICE_CONFIG="${ROOT_DIR}/devices/${DEVICE}/device.sh"
if [[ ! -f "$DEVICE_CONFIG" ]]; then
    log_error "Device configuration not found: $DEVICE_CONFIG"
    exit 1
fi

source "$DEVICE_CONFIG"

KERNEL_DIR="${ROOT_DIR}/kernel-${DEVICE}"

log_info "Applying defconfig modifications for device: $DEVICE"

# Find and modify defconfig
apply_defconfig_changes() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"

    if [[ ! -f "$defconfig_path" ]]; then
        log_error "Defconfig not found: $defconfig_path"
        exit 1
    fi

    log_info "Modifying defconfig: $defconfig_path"

    # Create backup
    cp "$defconfig_path" "${defconfig_path}.bak"

    # Config options to add
    local configs=(
        "# KernelSU-Next support"
        "CONFIG_KSU=y"
        ""
        "# Netfilter TTL/HL modification support (for hotspot bypass)"
        "CONFIG_NETFILTER_XT_TARGET_HL=y"
        ""
        "# Required netfilter dependencies"
        "CONFIG_NETFILTER_ADVANCED=y"
    )

    # Check which configs already exist
    local to_add=()
    for config in "${configs[@]}"; do
        # Skip comments and empty lines for checking
        if [[ "$config" =~ ^# ]] || [[ -z "$config" ]]; then
            to_add+=("$config")
            continue
        fi

        local config_name="${config%%=*}"
        if grep -q "^${config_name}=" "$defconfig_path" 2>/dev/null; then
            log_warn "Config already exists: $config_name"
        else
            to_add+=("$config")
        fi
    done

    # Append new configs
    echo "" >> "$defconfig_path"
    echo "# === Hotspot Bypass Additions ===" >> "$defconfig_path"
    for config in "${to_add[@]}"; do
        echo "$config" >> "$defconfig_path"
    done

    log_info "Defconfig modifications applied"
}

# Also modify GKI defconfig if needed
apply_gki_defconfig_changes() {
    local gki_defconfig="${KERNEL_DIR}/aosp/arch/arm64/configs/gki_defconfig"

    if [[ ! -f "$gki_defconfig" ]]; then
        log_warn "GKI defconfig not found, skipping: $gki_defconfig"
        return 0
    fi

    # Create backup
    cp "$gki_defconfig" "${gki_defconfig}.bak"

    local modified=0

    # Note: CONFIG_KSU is NOT added to gki_defconfig because KernelSU's Kconfig
    # has "default y", which means it's enabled automatically. Adding it here
    # causes savedefconfig validation to fail since it would be removed by savedefconfig.

    # Add TTL config
    if grep -q "^CONFIG_NETFILTER_XT_TARGET_HL=y" "$gki_defconfig"; then
        log_info "TTL config already in GKI defconfig"
    else
        log_info "Adding TTL config to GKI defconfig..."
        # Insert after CONFIG_NETFILTER_XT_TARGET_DSCP=y to maintain alphabetical order
        if grep -q "CONFIG_NETFILTER_XT_TARGET_DSCP=y" "$gki_defconfig"; then
            sed -i '/^CONFIG_NETFILTER_XT_TARGET_DSCP=y$/a CONFIG_NETFILTER_XT_TARGET_HL=y' "$gki_defconfig"
        else
            log_warn "CONFIG_NETFILTER_XT_TARGET_DSCP not found, appending CONFIG_NETFILTER_XT_TARGET_HL at end"
            echo "CONFIG_NETFILTER_XT_TARGET_HL=y" >> "$gki_defconfig"
        fi
        modified=1
    fi

    if [[ $modified -eq 1 ]]; then
        log_info "GKI defconfig modifications applied"
    else
        log_info "GKI defconfig already up to date"
    fi
}

# Verify configurations
verify_configs() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"

    log_info "Verifying configurations..."

    local required_configs=(
        "CONFIG_KSU"
        "CONFIG_NETFILTER_XT_TARGET_HL"
    )

    local missing=()
    for config in "${required_configs[@]}"; do
        if ! grep -q "^${config}=y" "$defconfig_path"; then
            missing+=("$config")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing configs in defconfig: ${missing[*]}"
        return 1
    fi

    log_info "All required configs present"
}

# Invalidate Bazel cache to ensure config changes are compiled
invalidate_bazel_cache() {
    log_info "Invalidating Bazel cache to ensure config changes are compiled..."

    # Touch a tracked source file to invalidate the kernel build cache
    # Bazel doesn't track defconfig changes, so we need to force a rebuild
    local makefile="${KERNEL_DIR}/aosp/Makefile"
    if [[ -f "$makefile" ]]; then
        touch "$makefile"
        log_info "Touched $makefile to invalidate kernel cache"
    fi

    # Also recommend full clean for guaranteed rebuild
    log_warn "IMPORTANT: For guaranteed rebuild, run:"
    log_warn "  cd ${KERNEL_DIR} && tools/bazel clean --expunge"
}

# Main
main() {
    if [[ ! -d "$KERNEL_DIR" ]]; then
        log_error "Kernel directory not found: $KERNEL_DIR"
        log_error "Run setup-kernel.sh first"
        exit 1
    fi

    apply_defconfig_changes
    apply_gki_defconfig_changes
    verify_configs
    invalidate_bazel_cache

    log_info ""
    log_info "Defconfig modifications complete!"
    log_info ""
    log_info "Applied configurations:"
    log_info "  - CONFIG_KSU=y (KernelSU-Next)"
    log_info "  - CONFIG_NETFILTER_XT_TARGET_HL=y (TTL/HL modification)"
    log_info "  - CONFIG_NETFILTER_ADVANCED=y (Required dependency)"
    log_info ""
    log_info "Next step: Run build-kernel.sh $DEVICE"
}

main "$@"
