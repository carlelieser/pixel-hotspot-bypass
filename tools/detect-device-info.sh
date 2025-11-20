#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/common.sh"

check_adb_device

log_section "Device Information"

DEVICE_CODENAME=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
log_info "Device codename: $DEVICE_CODENAME"

DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
log_info "Device model: $DEVICE_MODEL"

ANDROID_VERSION=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
log_info "Android version: $ANDROID_VERSION"

KERNEL_VERSION=$(adb shell uname -r 2>/dev/null | tr -d '\r')
log_info "Kernel version: $KERNEL_VERSION"

BUILD_FINGERPRINT=$(adb shell getprop ro.build.fingerprint 2>/dev/null | tr -d '\r')
log_info "Build fingerprint: $BUILD_FINGERPRINT"

log_section "Recommended Kernel Branch"

# Extract major.minor version (e.g., 6.1 from 6.1.99-android14-...)
KERNEL_MAJOR_MINOR=$(echo "$KERNEL_VERSION" | grep -oE '^[0-9]+\.[0-9]+')

# Normalize Android version to manifest format (e.g., 15 -> android15)
if [[ "$ANDROID_VERSION" =~ ^([0-9]+) ]]; then
    ANDROID_MANIFEST="android${BASH_REMATCH[1]}"
else
    log_warn "Could not parse Android version: $ANDROID_VERSION"
    ANDROID_MANIFEST="unknown"
fi

# Flag beta/preview builds - manifest branch naming may differ
if echo "$BUILD_FINGERPRINT" | grep -qi "beta\|preview\|dp"; then
    log_warn "This appears to be a beta/preview build"
    SUGGESTED_SUFFIX="-beta"
else
    SUGGESTED_SUFFIX=""
fi

RECOMMENDED_BRANCH="android-gs-${DEVICE_CODENAME}-${KERNEL_MAJOR_MINOR}-${ANDROID_MANIFEST}${SUGGESTED_SUFFIX}"

log_info "Recommended branch: ${GREEN}$RECOMMENDED_BRANCH${NC}"

log_section "Verification"

if curl -s "https://android.googlesource.com/kernel/manifest/+refs/heads/$RECOMMENDED_BRANCH" | grep -q "$RECOMMENDED_BRANCH"; then
    log_info "${GREEN}✓${NC} Branch exists!"
else
    log_warn "Branch not found. Checking for alternatives..."

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

log_info "Update your .env configuration:"
log_info "  File: .env"
log_info "  Set: MANIFEST_BRANCH=\"$RECOMMENDED_BRANCH\""
echo ""
log_info "Then run the setup script:"
log_info "  ./scripts/setup.sh"
