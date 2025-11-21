#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"
source "$ROOT_DIR/lib/ui.sh"

# KSU Manager URLs
KSUNEXT_MANAGER_URL="https://github.com/rifsxd/KernelSU-Next/releases/latest/download/KernelSU-Next_manager.apk"
KSU_MANAGER_URL="https://github.com/tiann/KernelSU/releases/latest/download/KernelSU_manager.apk"

# Unlimited hotspot module
UNLIMITED_HOTSPOT_URL="https://github.com/felikcat/unlimited-hotspot/releases/latest/download/unlimited-hotspot.zip"
UNLIMITED_HOTSPOT_FALLBACK_URL="https://github.com/felikcat/unlimited-hotspot/releases/download/v9/unlimited-hotspot-v9.zip"

DOWNLOAD_DIR="${ROOT_DIR}/downloads"
SKIP_MANAGER=false
SKIP_MODULE=false
MANAGER_TYPE="ksunext"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install KSU/KSUNext manager and unlimited-hotspot module

OPTIONS:
  --manager TYPE       Manager type: ksunext (default), ksu
  --skip-manager       Skip manager APK installation
  --skip-module        Skip unlimited-hotspot module installation
  -h, --help           Show this help message

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage ;;
            --manager) MANAGER_TYPE="$2"; shift 2 ;;
            --skip-manager) SKIP_MANAGER=true; shift ;;
            --skip-module) SKIP_MODULE=true; shift ;;
            *) ui_error "Unknown option: $1"; show_usage ;;
        esac
    done
}

check_prerequisites() {
    echo ""
    echo "${COLOR_BOLD}Prerequisites${COLOR_RESET}"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking ADB..."
    if ! command -v adb &>/dev/null; then
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} ADB not found\n"
        ui_error "Install Android SDK Platform Tools"
        exit 1
    fi
    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} ADB found\n"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking device connection..."
    if ! adb devices | grep -q "device$"; then
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} No device connected\n"
        ui_info "Connect your device via USB with debugging enabled"
        exit 1
    fi
    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Device connected\n"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking curl..."
    if ! command -v curl &>/dev/null; then
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} curl not found\n"
        ui_error "Install curl to download files"
        exit 1
    fi
    printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} curl found\n"

    mkdir -p "$DOWNLOAD_DIR"
}

download_file() {
    local url="$1"
    local output="$2"
    local fallback_url="${3:-}"

    if curl -fsSL --connect-timeout 10 -o "$output" "$url" 2>/dev/null; then
        return 0
    elif [[ -n "$fallback_url" ]]; then
        if curl -fsSL --connect-timeout 10 -o "$output" "$fallback_url" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

install_manager() {
    echo ""
    echo "${COLOR_BOLD}KernelSU Manager${COLOR_RESET}"

    local manager_url
    local manager_name
    local apk_file

    case "$MANAGER_TYPE" in
        ksunext|ksu-next)
            manager_url="$KSUNEXT_MANAGER_URL"
            manager_name="KernelSU-Next"
            apk_file="$DOWNLOAD_DIR/KernelSU-Next_manager.apk"
            ;;
        ksu)
            manager_url="$KSU_MANAGER_URL"
            manager_name="KernelSU"
            apk_file="$DOWNLOAD_DIR/KernelSU_manager.apk"
            ;;
        *)
            ui_error "Unknown manager type: $MANAGER_TYPE (use: ksunext, ksu)"
            exit 1
            ;;
    esac

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Downloading %s manager..." "$manager_name"
    if download_file "$manager_url" "$apk_file"; then
        local size=$(du -h "$apk_file" 2>/dev/null | cut -f1)
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Downloaded %s manager ${COLOR_GRAY}(%s)${COLOR_RESET}\n" "$manager_name" "$size"
    else
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} Failed to download %s manager\n" "$manager_name"
        ui_info "Download manually: $manager_url"
        return 1
    fi

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Installing %s manager..." "$manager_name"
    if adb install -r "$apk_file" &>/dev/null; then
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Installed %s manager\n" "$manager_name"
    else
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} Failed to install %s manager\n" "$manager_name"
        ui_info "Install manually: adb install $apk_file"
        return 1
    fi
}

install_module() {
    echo ""
    echo "${COLOR_BOLD}Unlimited Hotspot Module${COLOR_RESET}"

    local module_file="$DOWNLOAD_DIR/unlimited-hotspot.zip"
    local device_path="/data/local/tmp/unlimited-hotspot.zip"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Downloading unlimited-hotspot module..."
    if download_file "$UNLIMITED_HOTSPOT_URL" "$module_file" "$UNLIMITED_HOTSPOT_FALLBACK_URL"; then
        local size=$(du -h "$module_file" 2>/dev/null | cut -f1)
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Downloaded unlimited-hotspot ${COLOR_GRAY}(%s)${COLOR_RESET}\n" "$size"
    else
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} Failed to download module\n"
        ui_info "Download manually: https://github.com/felikcat/unlimited-hotspot/releases"
        return 1
    fi

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Pushing module to device..."
    if adb push "$module_file" "$device_path" &>/dev/null; then
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Module pushed to device\n"
    else
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} Failed to push module\n"
        return 1
    fi

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking for ksud..."
    if adb shell "su -c 'which ksud'" &>/dev/null; then
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} ksud found\n"

        printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Installing module via ksud..."
        local install_output
        install_output=$(adb shell "su -c 'ksud module install $device_path'" 2>&1)
        if [[ $? -eq 0 ]] && ! echo "$install_output" | grep -qi "error\|failed"; then
            printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Module installed successfully\n"
            adb shell "rm -f $device_path" &>/dev/null
            echo ""
            ui_info "Reboot device to activate the module"
            return 0
        else
            printf "\r\033[K  ${COLOR_YELLOW}⚠${COLOR_RESET} ksud install failed, trying alternative method\n"
        fi
    else
        printf "\r\033[K  ${COLOR_YELLOW}⚠${COLOR_RESET} ksud not found, trying alternative method\n"
    fi

    # Fallback: extract module directly to modules directory
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Installing module directly..."
    local module_id="unlimited_hotspot"
    local modules_dir="/data/adb/modules"

    # Create modules directory and extract
    local extract_cmd="su -c 'mkdir -p $modules_dir/$module_id && unzip -o $device_path -d $modules_dir/$module_id && chmod -R 755 $modules_dir/$module_id'"
    if adb shell "$extract_cmd" &>/dev/null; then
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} Module installed to $modules_dir/$module_id\n"
        adb shell "rm -f $device_path" &>/dev/null
        echo ""
        ui_info "Reboot device to activate the module"
        return 0
    else
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} Direct installation failed\n"
        # Copy to Download as last resort
        adb shell "cp $device_path /sdcard/Download/unlimited-hotspot.zip" &>/dev/null
        adb shell "rm -f $device_path" &>/dev/null
        echo ""
        ui_info "Module copied to /sdcard/Download/"
        echo "  Install manually via KernelSU manager"
        return 1
    fi
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${COLOR_GREEN}✓${COLOR_RESET} Post-install complete!"
    echo ""
    echo "  Next steps:"
    echo "  1. Reboot device to activate module"
    echo "  2. Open KernelSU manager to verify"
}

run_post_install() {
    ui_header "Post-Install"

    check_prerequisites

    if [[ "$SKIP_MANAGER" != true ]]; then
        install_manager || true
    else
        ui_dim "Skipping manager installation"
    fi

    if [[ "$SKIP_MODULE" != true ]]; then
        install_module || true
    else
        ui_dim "Skipping module installation"
    fi

    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    run_post_install
fi
