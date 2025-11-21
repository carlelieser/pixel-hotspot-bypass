#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/lib/common.sh"
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

validate_post_install_config() {
    case "$MANAGER_TYPE" in
        ksunext|ksu-next|ksu) ;;
        *)
            ui_error "Invalid manager type: $MANAGER_TYPE (use: ksunext, ksu)"
            exit 1
            ;;
    esac
}

# Status output helper for consistent formatting
show_status() {
    local status="$1"
    local name="$2"
    local detail="$3"

    case "$status" in
        checking)
            printf "  ${COLOR_BLUE}⠋${COLOR_RESET} %s..." "$name"
            ;;
        ok)
            printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} %-25s ${COLOR_GRAY}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
        warn)
            printf "\r\033[K  ${COLOR_YELLOW}⚠${COLOR_RESET} %-25s ${COLOR_YELLOW}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
        skip)
            printf "\r\033[K  ${COLOR_GRAY}○${COLOR_RESET} %-25s ${COLOR_GRAY}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
        error)
            printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} %-25s ${COLOR_RED}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
    esac
}

check_prerequisites() {
    echo ""
    echo "${COLOR_BOLD}Prerequisites${COLOR_RESET}"

    local tools=("adb" "curl")
    local all_ok=true

    for tool in "${tools[@]}"; do
        show_status checking "$tool"

        if command -v "$tool" &>/dev/null; then
            local path=$(command -v "$tool")
            show_status ok "$tool" "$path"
        else
            show_status error "$tool" "not found"
            all_ok=false
        fi
    done

    if [[ "$all_ok" == false ]]; then
        echo ""
        ui_error "Missing prerequisites"
        exit 1
    fi

    # Check device connection
    show_status checking "Device connection"
    if adb devices | grep -q "device$"; then
        local device_model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        show_status ok "Device connection" "$device_model"
    else
        show_status error "Device connection" "no device"
        ui_info "Connect device via USB with debugging enabled"
        exit 1
    fi

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
    esac

    show_status checking "Download $manager_name"
    if download_file "$manager_url" "$apk_file"; then
        local size=$(du -h "$apk_file" 2>/dev/null | cut -f1)
        show_status ok "Download $manager_name" "$size"
    else
        show_status error "Download $manager_name" "failed"
        ui_info "Download manually: $manager_url"
        return 1
    fi

    show_status checking "Install APK"
    if adb install -r "$apk_file" &>/dev/null; then
        show_status ok "Install APK" "$manager_name"
    else
        show_status error "Install APK" "failed"
        ui_info "Install manually: adb install $apk_file"
        return 1
    fi
}

install_module() {
    echo ""
    echo "${COLOR_BOLD}Unlimited Hotspot Module${COLOR_RESET}"

    local module_file="$DOWNLOAD_DIR/unlimited-hotspot.zip"
    local device_path="/data/local/tmp/unlimited-hotspot.zip"

    show_status checking "Download module"
    if download_file "$UNLIMITED_HOTSPOT_URL" "$module_file" "$UNLIMITED_HOTSPOT_FALLBACK_URL"; then
        local size=$(du -h "$module_file" 2>/dev/null | cut -f1)
        show_status ok "Download module" "$size"
    else
        show_status error "Download module" "failed"
        ui_info "Download: https://github.com/felikcat/unlimited-hotspot/releases"
        return 1
    fi

    show_status checking "Push to device"
    if adb push "$module_file" "$device_path" &>/dev/null; then
        show_status ok "Push to device" "/data/local/tmp/"
    else
        show_status error "Push to device" "failed"
        return 1
    fi

    # Try ksud first
    show_status checking "ksud"
    if adb shell "su -c 'which ksud'" &>/dev/null; then
        show_status ok "ksud" "found"

        show_status checking "Install via ksud"
        local install_output
        install_output=$(adb shell "su -c 'ksud module install $device_path'" 2>&1)
        if [[ $? -eq 0 ]] && ! echo "$install_output" | grep -qi "error\|failed"; then
            show_status ok "Install via ksud" "success"
            adb shell "rm -f $device_path" &>/dev/null
            return 0
        else
            show_status warn "Install via ksud" "failed, trying fallback"
        fi
    else
        show_status warn "ksud" "not found, trying fallback"
    fi

    # Fallback: extract directly to modules directory
    show_status checking "Direct install"
    local module_id="unlimited_hotspot"
    local modules_dir="/data/adb/modules"
    local extract_cmd="su -c 'mkdir -p $modules_dir/$module_id && unzip -o $device_path -d $modules_dir/$module_id && chmod -R 755 $modules_dir/$module_id'"

    if adb shell "$extract_cmd" &>/dev/null; then
        show_status ok "Direct install" "$modules_dir/$module_id"
        adb shell "rm -f $device_path" &>/dev/null
        return 0
    else
        show_status error "Direct install" "failed"
        # Copy to Download as last resort
        adb shell "cp $device_path /sdcard/Download/unlimited-hotspot.zip" &>/dev/null
        adb shell "rm -f $device_path" &>/dev/null
        ui_info "Module copied to /sdcard/Download/"
        echo "  Install manually via KernelSU manager"
        return 1
    fi
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${COLOR_GREEN}✓${COLOR_RESET} Post-install complete"
    echo ""
    echo "  Reboot device to activate module"

    if [[ "${PHB_WORKFLOW:-}" != "true" ]]; then
        echo ""
        echo "  Verify: ${COLOR_CYAN}Open KernelSU manager app${COLOR_RESET}"
    fi
}

run_post_install() {
    ui_header "Post-Install"
    echo "  Manager: ${COLOR_CYAN}$MANAGER_TYPE${COLOR_RESET}"

    check_prerequisites

    if [[ "$SKIP_MANAGER" != true ]]; then
        install_manager || true
    else
        echo ""
        ui_dim "  Skipping manager installation"
    fi

    if [[ "$SKIP_MODULE" != true ]]; then
        install_module || true
    else
        echo ""
        ui_dim "  Skipping module installation"
    fi

    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_post_install_config
    run_post_install
fi
