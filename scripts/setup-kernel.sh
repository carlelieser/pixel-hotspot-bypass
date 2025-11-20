#!/bin/bash
# setup-kernel.sh - Clone and set up Pixel kernel source
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment variables from .env if it exists
ENV_MANIFEST_BRANCH=""
ENV_MANIFEST_URL=""
if [[ -f "${ROOT_DIR}/.env" ]]; then
    log_info "Loading configuration from .env"
    set -a  # automatically export all variables
    source "${ROOT_DIR}/.env"
    set +a
    # Save .env values to override device.sh defaults
    ENV_MANIFEST_BRANCH="$MANIFEST_BRANCH"
    ENV_MANIFEST_URL="$MANIFEST_URL"
fi

# Default values (can be overridden by .env or command line)
DEVICE="${1:-${DEVICE_CODENAME:-tegu}}"
KERNEL_DIR="${ROOT_DIR}/kernel-${DEVICE}"

# Load device configuration (provides defaults)
DEVICE_CONFIG="${ROOT_DIR}/devices/${DEVICE}/device.sh"
if [[ ! -f "$DEVICE_CONFIG" ]]; then
    log_error "Device configuration not found: $DEVICE_CONFIG"
    log_error "Supported devices: tegu"
    exit 1
fi

source "$DEVICE_CONFIG"

# Override device config values with .env values if they were set
if [[ -n "$ENV_MANIFEST_BRANCH" ]]; then
    MANIFEST_BRANCH="$ENV_MANIFEST_BRANCH"
    log_info "Using MANIFEST_BRANCH from .env"
fi
if [[ -n "$ENV_MANIFEST_URL" ]]; then
    MANIFEST_URL="$ENV_MANIFEST_URL"
fi

log_info "Setting up kernel for device: $DEVICE"
log_info "Kernel directory: $KERNEL_DIR"
log_info "Manifest branch: $MANIFEST_BRANCH"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    command -v repo >/dev/null 2>&1 || missing+=("repo")
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Please install them and try again."
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

# Initialize repo and sync
setup_kernel_source() {
    if [[ -d "$KERNEL_DIR" ]]; then
        log_warn "Kernel directory already exists: $KERNEL_DIR"
        read -p "Remove and re-download? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$KERNEL_DIR"
        else
            log_info "Skipping kernel source setup"
            return 0
        fi
    fi

    mkdir -p "$KERNEL_DIR"
    cd "$KERNEL_DIR"

    log_info "Initializing repo with manifest: $MANIFEST_URL"
    repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --depth=1

    log_info "Syncing kernel source (this may take a while)..."
    repo sync -c -j$(nproc) --no-tags --no-clone-bundle --fail-fast

    log_info "Kernel source setup complete"
}

# Patch Kleaf build system for compatibility
patch_kleaf() {
    log_info "Patching Kleaf build system..."

    local filegroup_bzl="${KERNEL_DIR}/build/kernel/kleaf/impl/kernel_filegroup.bzl"

    if [[ ! -f "$filegroup_bzl" ]]; then
        log_warn "kernel_filegroup.bzl not found, skipping Kleaf patch"
        return 0
    fi

    # Check if already patched
    if grep -q "strip_modules = False" "$filegroup_bzl"; then
        log_info "Kleaf already patched"
        return 0
    fi

    # Add missing fields to KernelBuildExtModuleInfo in kernel_filegroup.bzl
    # This fixes compatibility issues with the build system
    sed -i 's/collect_unstripped_modules = ctx.attr.collect_unstripped_modules,$/collect_unstripped_modules = ctx.attr.collect_unstripped_modules,\n        strip_modules = False,/' "$filegroup_bzl"

    # Also add config_env_and_outputs_info and module_kconfig if missing
    if ! grep -q "config_env_and_outputs_info = ext_mod_env_and_outputs_info" "$filegroup_bzl"; then
        sed -i 's/modules_install_env_and_outputs_info = ext_mod_env_and_outputs_info,$/modules_install_env_and_outputs_info = ext_mod_env_and_outputs_info,\n        config_env_and_outputs_info = ext_mod_env_and_outputs_info,/' "$filegroup_bzl"
    fi

    if ! grep -q "module_kconfig = depset()" "$filegroup_bzl"; then
        sed -i 's/module_scripts = module_srcs.module_scripts,$/module_scripts = module_srcs.module_scripts,\n        module_kconfig = depset(),/' "$filegroup_bzl"
    fi

    log_info "Kleaf patched successfully"
}

# Create build script
create_build_script() {
    local build_script="${KERNEL_DIR}/build_${DEVICE}.sh"

    log_info "Creating build script: $build_script"

    cat > "$build_script" << 'EOF'
#!/bin/bash
# Auto-generated build script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build with Bazel
# use_source_tree_aosp builds GKI from source instead of downloading prebuilt
LTO="${LTO:-none}"
tools/bazel --bazelrc="private/devices/google/DEVICE_CODENAME/device.bazelrc" \
    build \
    --lto="$LTO" \
    --config=DEVICE_CONFIG \
    --config=use_source_tree_aosp \
    //private/devices/google/DEVICE_CODENAME:DEVICE_BUILD_TARGET

echo "Build complete! Output in out/DEVICE_CODENAME/dist/"
EOF

    # Replace placeholders
    sed -i "s/DEVICE_CONFIG/${BAZEL_CONFIG}/g" "$build_script"
    sed -i "s/DEVICE_CODENAME/${DEVICE}/g" "$build_script"
    sed -i "s/DEVICE_BUILD_TARGET/${BUILD_TARGET}/g" "$build_script"

    chmod +x "$build_script"
    log_info "Build script created"
}

# Main
main() {
    check_prerequisites
    setup_kernel_source
    patch_kleaf
    create_build_script

    log_info "Setup complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. cd $KERNEL_DIR"
    log_info "  2. ../scripts/integrate-kernelsu.sh"
    log_info "  3. ../scripts/apply-defconfig.sh $DEVICE"
    log_info "  4. ../scripts/build-kernel.sh $DEVICE"
}

main "$@"
