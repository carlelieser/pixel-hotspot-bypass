#!/bin/bash
# detect-device-info.sh - Detect device info and recommend correct kernel branch
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Check if device is connected
if ! adb devices | grep -q "device$"; then
    log_error "No device connected via ADB"
    log_info "Connect your device and enable USB debugging"
    exit 1
fi

log_section "Device Information"

# Get device codename
DEVICE_CODENAME=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
log_info "Device codename: $DEVICE_CODENAME"

# Get device model
DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
log_info "Device model: $DEVICE_MODEL"

# Get Android version
ANDROID_VERSION=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
log_info "Android version: $ANDROID_VERSION"

# Get kernel version
KERNEL_VERSION=$(adb shell uname -r 2>/dev/null | tr -d '\r')
log_info "Kernel version: $KERNEL_VERSION"

# Get build fingerprint
BUILD_FINGERPRINT=$(adb shell getprop ro.build.fingerprint 2>/dev/null | tr -d '\r')
log_info "Build fingerprint: $BUILD_FINGERPRINT"

log_section "Recommended Kernel Branch"

# Extract kernel major.minor version (e.g., 6.1 from 6.1.99-android14-...)
KERNEL_MAJOR_MINOR=$(echo "$KERNEL_VERSION" | grep -oE '^[0-9]+\.[0-9]+')

# Determine Android manifest version
# Android 15 -> android15, Android 16 -> android16, etc.
if [[ "$ANDROID_VERSION" =~ ^([0-9]+) ]]; then
    ANDROID_MANIFEST="android${BASH_REMATCH[1]}"
else
    log_warn "Could not parse Android version: $ANDROID_VERSION"
    ANDROID_MANIFEST="unknown"
fi

# Check if it's a beta/preview build
if echo "$BUILD_FINGERPRINT" | grep -qi "beta\|preview\|dp"; then
    log_warn "This appears to be a beta/preview build"
    SUGGESTED_SUFFIX="-beta"
else
    SUGGESTED_SUFFIX=""
fi

# Construct recommended branch
RECOMMENDED_BRANCH="android-gs-${DEVICE_CODENAME}-${KERNEL_MAJOR_MINOR}-${ANDROID_MANIFEST}${SUGGESTED_SUFFIX}"

log_info "Recommended branch: ${GREEN}$RECOMMENDED_BRANCH${NC}"

log_section "Verification"

# Check if branch exists
log_info "Checking if branch exists on Google's servers..."
if curl -s "https://android.googlesource.com/kernel/manifest/+refs/heads/$RECOMMENDED_BRANCH" | grep -q "$RECOMMENDED_BRANCH"; then
    log_info "${GREEN}✓${NC} Branch exists!"
else
    log_warn "Branch not found. Checking for alternatives..."

    # Try without suffix
    ALT_BRANCH="android-gs-${DEVICE_CODENAME}-${KERNEL_MAJOR_MINOR}-${ANDROID_MANIFEST}"
    if curl -s "https://android.googlesource.com/kernel/manifest/+refs/heads/$ALT_BRANCH" | grep -q "$ALT_BRANCH"; then
        log_info "${GREEN}✓${NC} Alternative found: $ALT_BRANCH"
        RECOMMENDED_BRANCH="$ALT_BRANCH"
    else
        log_error "Could not find matching branch"
        log_info "Available branches for $DEVICE_CODENAME:"
        curl -s "https://android.googlesource.com/kernel/manifest/+refs" | grep -o "android-gs-${DEVICE_CODENAME}-[^<]*" | sort -u
    fi
fi

log_section "Next Steps"

log_info "Update your device configuration:"
log_info "  File: devices/${DEVICE_CODENAME}/device.sh"
log_info "  Set: MANIFEST_BRANCH=\"$RECOMMENDED_BRANCH\""
echo ""
log_info "Then run the setup script:"
log_info "  ./scripts/setup-kernel.sh $DEVICE_CODENAME"
