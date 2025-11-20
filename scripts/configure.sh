#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

init_directories
load_env
validate_env_vars "DEVICE_CODENAME" "KERNELSU_REPO" "KERNELSU_BRANCH" "KSU_VERSION" "KSU_VERSION_TAG" "AUTO_EXPUNGE"
validate_enum_var "AUTO_EXPUNGE" "$AUTO_EXPUNGE" "(must be: 0 or 1)" "0" "1"

KERNEL_DIR="$(check_kernel_dir)"
DEFCONFIG_PATH="private/devices/google/${DEVICE_CODENAME}/${DEVICE_CODENAME}_defconfig"
MARKER_COMMENT="# === Hotspot Bypass Additions ==="

if [[ ! -d "${KERNEL_DIR}/aosp" ]]; then
    log_error "Invalid kernel directory: $KERNEL_DIR (aosp directory not found)"
    exit 1
fi

log_info "Using kernel directory: $KERNEL_DIR"
log_info "Device: $DEVICE_CODENAME"

# ============================================================================
# KernelSU Integration
# ============================================================================

clone_kernelsu() {
    local ksu_dir="${KERNEL_DIR}/aosp/drivers/kernelsu"

    if [[ -d "$ksu_dir" ]]; then
        log_warn "KernelSU directory already exists: $ksu_dir"
        if ask_confirmation "Remove and re-clone?"; then
            log_info "Removing existing KernelSU directory..."
            rm -rf "$ksu_dir"
        else
            log_info "Skipping KernelSU clone"
            return 0
        fi
    fi

    log_info "Cloning KernelSU-Next from $KERNELSU_REPO (branch: $KERNELSU_BRANCH)..."
    git clone "$KERNELSU_REPO" "$ksu_dir" --branch "$KERNELSU_BRANCH" --depth=1

    log_success "KernelSU-Next cloned successfully"
}

# Bazel's sandbox excludes .git directories, breaking git-based version detection
apply_bazel_version_fix() {
    local makefile="${KERNEL_DIR}/aosp/drivers/kernelsu/kernel/Makefile"

    if [[ ! -f "$makefile" ]]; then
        log_error "KernelSU Makefile not found: $makefile"
        exit 1
    fi

    log_info "Applying Bazel sandbox version fix..."

    if grep -q "^ccflags-y += -DKSU_VERSION=${KSU_VERSION}$" "$makefile"; then
        log_info "Version fix already applied"
        return 0
    fi

    cp "$makefile" "${makefile}.bak"

    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
# Version hardcoded for Bazel sandbox compatibility
# Bazel's sandbox doesn't include .git, breaking git-based version detection
ccflags-y += -DKSU_VERSION=${KSU_VERSION}
ccflags-y += -DKSU_VERSION_TAG="${KSU_VERSION_TAG}"

EOF
    cat "$makefile" >> "$temp_file"
    mv "$temp_file" "$makefile"

    sed -i 's/^ccflags-y += -DKSU_VERSION_TAG=.*\$(KSU_VERSION_TAG).*$/#DISABLED &/' "$makefile"
    sed -i 's/^ccflags-y += -DKSU_VERSION_TAG=.*v0\.0\.0.*$/#DISABLED &/' "$makefile"
    sed -i 's/^ccflags-y += -DKSU_VERSION=.*\$(KSU_VERSION)$/#DISABLED &/' "$makefile"
    sed -i '4,$s/^ccflags-y += -DKSU_VERSION=[0-9]*$/#DISABLED &/' "$makefile"

    log_success "Version fix applied successfully"
}

integrate_into_build() {
    local drivers_makefile="${KERNEL_DIR}/aosp/drivers/Makefile"
    local drivers_kconfig="${KERNEL_DIR}/aosp/drivers/Kconfig"

    log_info "Integrating KernelSU into kernel build system..."

    if grep -q "kernelsu" "$drivers_makefile" 2>/dev/null; then
        log_info "Already in drivers/Makefile"
    else
        log_info "Adding to drivers/Makefile..."
        echo 'obj-$(CONFIG_KSU) += kernelsu/kernel/' >> "$drivers_makefile"
    fi

    if grep -q "kernelsu" "$drivers_kconfig" 2>/dev/null; then
        log_info "Already in drivers/Kconfig"
    else
        log_info "Adding to drivers/Kconfig..."
        sed -i '/^endmenu$/i source "drivers/kernelsu/kernel/Kconfig"' "$drivers_kconfig"
    fi

    log_success "Build system integration complete"
}

integrate_kernelsu() {
    print_divider "KernelSU-Next Integration"
    log_info ""
    log_info "Version: ${KSU_VERSION} (${KSU_VERSION_TAG})"
    log_info ""

    clone_kernelsu
    apply_bazel_version_fix
    integrate_into_build

    log_info ""
    log_success "KernelSU-Next integration complete"
    log_info ""
}

# ============================================================================
# Defconfig Configuration
# ============================================================================

# Returns: 0=correct, 1=fixed, 2=needs to be added
apply_or_fix_config() {
    local defconfig="$1"
    local config_name="$2"
    local desired_value="$3"
    local desired_line="${config_name}=${desired_value}"

    if grep -q "^${desired_line}$" "$defconfig" 2>/dev/null; then
        log_success "$config_name already correct"
        return 0
    fi

    if grep -q "^${config_name}=" "$defconfig" 2>/dev/null; then
        local current_value=$(grep "^${config_name}=" "$defconfig" | cut -d'=' -f2)
        log_info "Fixing $config_name (was =${current_value}, setting to =${desired_value})"
        sed -i "s/^${config_name}=.*$/${desired_line}/" "$defconfig"
        return 1
    fi

    return 2
}

apply_defconfig_changes() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"

    if [[ ! -f "$defconfig_path" ]]; then
        log_error "Defconfig not found: $defconfig_path"
        exit 1
    fi

    log_info "Checking device defconfig: $defconfig_path"

    local already_applied=false
    if grep -q "^${MARKER_COMMENT}$" "$defconfig_path"; then
        already_applied=true
        log_info "Marker found - verifying existing configs..."
    fi

    declare -A configs=(
        ["CONFIG_KSU"]="y"
        ["CONFIG_NETFILTER_XT_TARGET_HL"]="y"
        ["CONFIG_NETFILTER_ADVANCED"]="y"
    )

    local modified=false
    local to_add=()

    for config_name in "${!configs[@]}"; do
        apply_or_fix_config "$defconfig_path" "$config_name" "${configs[$config_name]}"
        local result=$?

        if [[ $result -eq 1 ]]; then
            modified=true
        elif [[ $result -eq 2 ]]; then
            to_add+=("$config_name")
            modified=true
        fi
    done

    if [[ ${#to_add[@]} -gt 0 ]]; then
        if [[ "$already_applied" == false ]]; then
            echo "" >> "$defconfig_path"
            echo "$MARKER_COMMENT" >> "$defconfig_path"
        fi

        echo "" >> "$defconfig_path"
        echo "# KernelSU-Next support" >> "$defconfig_path"
        if [[ " ${to_add[@]} " =~ " CONFIG_KSU " ]]; then
            echo "CONFIG_KSU=y" >> "$defconfig_path"
            log_info "Added CONFIG_KSU=y"
        fi

        echo "" >> "$defconfig_path"
        echo "# Netfilter TTL/HL modification support (for hotspot bypass)" >> "$defconfig_path"
        if [[ " ${to_add[@]} " =~ " CONFIG_NETFILTER_XT_TARGET_HL " ]]; then
            echo "CONFIG_NETFILTER_XT_TARGET_HL=y" >> "$defconfig_path"
            log_info "Added CONFIG_NETFILTER_XT_TARGET_HL=y"
        fi

        echo "" >> "$defconfig_path"
        echo "# Required netfilter dependencies" >> "$defconfig_path"
        if [[ " ${to_add[@]} " =~ " CONFIG_NETFILTER_ADVANCED " ]]; then
            echo "CONFIG_NETFILTER_ADVANCED=y" >> "$defconfig_path"
            log_info "Added CONFIG_NETFILTER_ADVANCED=y"
        fi
    fi

    if [[ "$modified" == true ]]; then
        log_success "Device defconfig updated"
    else
        log_success "Device defconfig already up to date"
    fi
}

apply_gki_defconfig_changes() {
    local gki_defconfig="${KERNEL_DIR}/aosp/arch/arm64/configs/gki_defconfig"

    if [[ ! -f "$gki_defconfig" ]]; then
        log_warn "GKI defconfig not found, skipping: $gki_defconfig"
        return 0
    fi

    log_info "Checking GKI defconfig: $gki_defconfig"

    # CONFIG_KSU not added to gki_defconfig: KernelSU has "default y" in Kconfig,
    # so savedefconfig removes explicit entries, causing validation to fail
    apply_or_fix_config "$gki_defconfig" "CONFIG_NETFILTER_XT_TARGET_HL" "y"
    local result=$?

    if [[ $result -eq 2 ]]; then
        log_info "Adding CONFIG_NETFILTER_XT_TARGET_HL to GKI defconfig..."

        # Maintain alphabetical order by inserting after DSCP if it exists
        if grep -q "CONFIG_NETFILTER_XT_TARGET_DSCP=y" "$gki_defconfig"; then
            sed -i '/^CONFIG_NETFILTER_XT_TARGET_DSCP=y$/a CONFIG_NETFILTER_XT_TARGET_HL=y' "$gki_defconfig"
            log_info "Inserted after CONFIG_NETFILTER_XT_TARGET_DSCP (alphabetical order)"
        else
            echo "CONFIG_NETFILTER_XT_TARGET_HL=y" >> "$gki_defconfig"
            log_warn "CONFIG_NETFILTER_XT_TARGET_DSCP not found, appended to end"
        fi
        log_success "GKI defconfig updated"
    elif [[ $result -eq 1 ]]; then
        log_success "GKI defconfig updated"
    else
        log_success "GKI defconfig already up to date"
    fi
}

verify_configs() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"

    log_info "Verifying configurations..."

    local required_configs=(
        "CONFIG_KSU=y"
        "CONFIG_NETFILTER_XT_TARGET_HL=y"
    )

    local missing=()
    for config in "${required_configs[@]}"; do
        if ! grep -q "^${config}$" "$defconfig_path"; then
            missing+=("$config")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Verification failed! Missing configs: ${missing[*]}"
        return 1
    fi

    log_success "All required configs verified"
}

invalidate_bazel_cache() {
    log_info "Invalidating Bazel cache..."

    # Bazel doesn't track defconfig changes, so touch Makefile to force rebuild
    local makefile="${KERNEL_DIR}/aosp/Makefile"
    if [[ ! -f "$makefile" ]]; then
        log_warn "Makefile not found: $makefile"
        log_warn "Bazel cache invalidation may not work properly"
    else
        touch "$makefile"
        log_info "Touched $makefile to invalidate kernel cache"
    fi

    if [[ "$AUTO_EXPUNGE" == "1" ]]; then
        log_info "Running bazel clean --expunge (AUTO_EXPUNGE=1)..."
        cd "$KERNEL_DIR"
        tools/bazel clean --expunge
        log_success "Bazel cache fully cleared"
    else
        log_warn "For guaranteed rebuild with config changes:"
        log_warn "  1. Set AUTO_EXPUNGE=1 in .env, or"
        log_warn "  2. Manually run: cd ${KERNEL_DIR} && tools/bazel clean --expunge"
    fi
}

configure_kernel() {
    print_divider "Kernel Configuration"
    log_info ""

    apply_defconfig_changes
    apply_gki_defconfig_changes
    verify_configs
    invalidate_bazel_cache

    log_info ""
    log_success "Kernel configuration complete"
    log_info ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    integrate_kernelsu
    configure_kernel

    print_divider "Configuration Complete!"
    log_info ""
    log_info "KernelSU-Next: ${KSU_VERSION} (${KSU_VERSION_TAG})"
    log_info ""
    log_info "Applied configurations:"
    log_info "  - CONFIG_KSU=y (KernelSU-Next)"
    log_info "  - CONFIG_NETFILTER_XT_TARGET_HL=y (TTL/HL modification)"
    log_info "  - CONFIG_NETFILTER_ADVANCED=y (Required dependency)"
}

main "$@"
