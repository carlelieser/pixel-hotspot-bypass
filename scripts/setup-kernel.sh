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

# Default values
DEVICE="${1:-tegu}"
KERNEL_DIR="${ROOT_DIR}/kernel-${DEVICE}"

# Load device configuration
DEVICE_CONFIG="${ROOT_DIR}/devices/${DEVICE}/device.sh"
if [[ ! -f "$DEVICE_CONFIG" ]]; then
    log_error "Device configuration not found: $DEVICE_CONFIG"
    log_error "Supported devices: tegu"
    exit 1
fi

source "$DEVICE_CONFIG"

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
LTO="${LTO:-none}"
tools/bazel run \
    --config=stamp \
    --config=DEVICE_CONFIG \
    --config=no_download_gki \
    //private/devices/google/DEVICE_CODENAME:DEVICE_BUILD_TARGET

echo "Build complete! Output in out/dist/"
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
