#!/bin/bash
# integrate-kernelsu.sh - Integrate KernelSU-Next into kernel source
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

# Configuration
KERNELSU_REPO="https://github.com/rifsxd/KernelSU-Next"
KERNELSU_BRANCH="next"
KSU_VERSION="12882"
KSU_VERSION_TAG="v1.1.1"

# Find kernel directory
find_kernel_dir() {
    if [[ -n "$1" && -d "$1" ]]; then
        KERNEL_DIR="$1"
    elif [[ -d "${ROOT_DIR}/kernel-tegu" ]]; then
        KERNEL_DIR="${ROOT_DIR}/kernel-tegu"
    else
        log_error "Kernel directory not found. Please specify path or run setup-kernel.sh first."
        exit 1
    fi

    # Verify it's a valid kernel source
    if [[ ! -d "${KERNEL_DIR}/aosp" ]]; then
        log_error "Invalid kernel directory: $KERNEL_DIR (aosp directory not found)"
        exit 1
    fi

    log_info "Using kernel directory: $KERNEL_DIR"
}

# Clone KernelSU-Next
clone_kernelsu() {
    local ksu_dir="${KERNEL_DIR}/aosp/drivers/kernelsu"

    if [[ -d "$ksu_dir" ]]; then
        log_warn "KernelSU directory already exists"
        read -p "Remove and re-clone? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$ksu_dir"
        else
            log_info "Skipping KernelSU clone"
            return 0
        fi
    fi

    log_info "Cloning KernelSU-Next..."
    git clone "$KERNELSU_REPO" "$ksu_dir" --branch "$KERNELSU_BRANCH"

    # Verify version
    cd "$ksu_dir"
    local commit_count=$(git rev-list --count HEAD)
    local calculated_version=$((10000 + commit_count + 200))
    log_info "KernelSU-Next commit count: $commit_count"
    log_info "Calculated version: $calculated_version"

    # Keep the original repo structure - kernel source is in kernel/ subdirectory
    # This matches how the working build was configured
    log_info "KernelSU-Next cloned successfully (keeping kernel/ subdirectory structure)"
}

# Apply version fix for Bazel sandbox
apply_version_fix() {
    local ksu_dir="${KERNEL_DIR}/aosp/drivers/kernelsu"
    local makefile="${ksu_dir}/kernel/Makefile"

    if [[ ! -f "$makefile" ]]; then
        log_error "KernelSU Makefile not found: $makefile"
        exit 1
    fi

    log_info "Applying version fix for Bazel sandbox..."

    # Bazel sandbox doesn't include .git, so version detection fails
    # We need to hardcode the version at the top of the Makefile

    # Create backup
    cp "$makefile" "${makefile}.bak"

    # Add hardcoded version at the beginning
    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
ccflags-y += -DKSU_VERSION=${KSU_VERSION}
ccflags-y += -DKSU_VERSION_TAG=\"${KSU_VERSION_TAG}\"

EOF
    cat "$makefile" >> "$temp_file"
    mv "$temp_file" "$makefile"

    # Comment out the duplicate version definitions to prevent redefinition errors
    sed -i 's/^ccflags-y += -DKSU_VERSION_TAG=.*$(KSU_VERSION_TAG).*$/#DISABLED &/' "$makefile"
    sed -i 's/^ccflags-y += -DKSU_VERSION_TAG=.*v0\.0\.0.*$/#DISABLED &/' "$makefile"
    sed -i 's/^ccflags-y += -DKSU_VERSION=.*$(KSU_VERSION)$/#DISABLED &/' "$makefile"

    # Also disable any later hardcoded version (in case of duplicate)
    # Skip the first two lines we just added
    sed -i '3,$s/^ccflags-y += -DKSU_VERSION=[0-9]*$/#DISABLED &/' "$makefile"

    log_info "Version fix applied (hardcoded: ${KSU_VERSION}, tag: ${KSU_VERSION_TAG})"
}

# Integrate KernelSU into kernel build
integrate_into_kernel() {
    local drivers_makefile="${KERNEL_DIR}/aosp/drivers/Makefile"
    local drivers_kconfig="${KERNEL_DIR}/aosp/drivers/Kconfig"

    # Check if already integrated
    if grep -q "kernelsu" "$drivers_makefile" 2>/dev/null; then
        log_info "KernelSU already integrated in drivers/Makefile"
    else
        log_info "Adding KernelSU to drivers/Makefile..."
        echo 'obj-$(CONFIG_KSU) += kernelsu/kernel/' >> "$drivers_makefile"
    fi

    if grep -q "kernelsu" "$drivers_kconfig" 2>/dev/null; then
        log_info "KernelSU already integrated in drivers/Kconfig"
    else
        log_info "Adding KernelSU to drivers/Kconfig..."
        # Add before the last endmenu
        sed -i '/^endmenu$/i source "drivers/kernelsu/kernel/Kconfig"' "$drivers_kconfig"
    fi

    log_info "KernelSU integration complete"
}

# Main
main() {
    find_kernel_dir "$1"
    clone_kernelsu
    apply_version_fix
    integrate_into_kernel

    log_info ""
    log_info "KernelSU-Next integration complete!"
    log_info "Version: ${KSU_VERSION} (${KSU_VERSION_TAG})"
    log_info ""
    log_info "Next step: Run apply-defconfig.sh to enable KernelSU in config"
}

main "$@"
