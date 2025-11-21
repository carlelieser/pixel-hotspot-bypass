#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/lib/ui.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-}"
MANIFEST_URL="${MANIFEST_URL:-https://android.googlesource.com/kernel/manifest}"
KERNELSU_REPO="${KERNELSU_REPO:-https://github.com/rifsxd/KernelSU-Next}"
KERNELSU_BRANCH="${KERNELSU_BRANCH:-next}"
KSU_VERSION="${KSU_VERSION:-12882}"
KSU_VERSION_TAG="${KSU_VERSION_TAG:-v1.1.1}"
SOC="${SOC:-zumapro}"
BAZEL_CONFIG="${BAZEL_CONFIG:-}"
BUILD_TARGET="${BUILD_TARGET:-}"
LTO="${LTO:-none}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"
AUTO_EXPUNGE="${AUTO_EXPUNGE:-0}"

SKIP_SETUP=false
SKIP_CONFIGURE=false
SKIP_BUILD=false
SKIP_FLASH=false
AUTO_FLASH=false
INTERACTIVE=false

ONLY_SETUP=false
ONLY_CONFIGURE=false
ONLY_BUILD=false
ONLY_FLASH=false

ENABLE_KERNELSU=true
ENABLE_TTL_BYPASS=true

CONFIG_FILE="$ROOT_DIR/.phb.conf"

show_main_help() {
    cat << EOF
${COLOR_BOLD}Pixel Hotspot Bypass (phb)${COLOR_RESET} - Kernel build tool with KernelSU + TTL/HL bypass

${COLOR_BOLD}USAGE:${COLOR_RESET}
  phb <command> [options]
  phb [legacy-flags]           (backward compatible)

${COLOR_BOLD}COMMANDS:${COLOR_RESET}
  ${COLOR_CYAN}deps${COLOR_RESET}                Check and install dependencies
  ${COLOR_CYAN}detect${COLOR_RESET}              Auto-detect connected device and show config
  ${COLOR_CYAN}setup${COLOR_RESET}               Download and setup kernel source
  ${COLOR_CYAN}configure${COLOR_RESET}           Apply selected patches to kernel
  ${COLOR_CYAN}build${COLOR_RESET}               Compile kernel
  ${COLOR_CYAN}flash${COLOR_RESET}               Flash kernel to device
  ${COLOR_CYAN}run${COLOR_RESET}                 Execute full workflow (setup → configure → build → flash)
  ${COLOR_CYAN}completion${COLOR_RESET}          Generate shell completion script (bash|zsh)

${COLOR_BOLD}GLOBAL OPTIONS:${COLOR_RESET}
  -h, --help          Show this help message
  -v, --verbose       Enable verbose output
  -d, --device NAME   Device codename (tegu, tokay, caiman)

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  ${COLOR_GRAY}# Modern subcommand interface${COLOR_RESET}
  phb detect                           # Auto-detect device
  phb run -d tegu                      # Full workflow with auto-detect branch
  phb run -d tegu -b android-gs-...    # Full workflow with specific branch
  phb build --clean --lto thin         # Clean build with thin LTO
  phb flash                            # Flash previously built kernel

  ${COLOR_GRAY}# Legacy flag interface (backward compatible)${COLOR_RESET}
  phb -d tegu -b android-gs-tegu-6.1-android16
  phb --device tegu --build-only --clean

${COLOR_BOLD}CONFIGURATION:${COLOR_RESET}
  First run uses interactive checklists to configure device and patches.
  Configuration is saved to .phb.conf for seamless subsequent runs.

${COLOR_BOLD}MORE HELP:${COLOR_RESET}
  phb <command> --help     Show help for specific command

EOF
}

show_setup_help() {
    cat << EOF
${COLOR_BOLD}phb setup${COLOR_RESET} - Download and setup kernel source

${COLOR_BOLD}USAGE:${COLOR_RESET}
  phb setup [options]

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
  -d, --device NAME      Device codename (required)
  -b, --branch NAME      Manifest branch (required)
  -u, --manifest-url URL Manifest URL (default: AOSP kernel manifest)
  --skip-sync            Skip repo sync (use existing source)
  -h, --help             Show this help

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  phb setup -d tegu -b android-gs-tegu-6.1-android16
  phb setup -d tegu -b android-gs-tegu-6.1-android16 --skip-sync

EOF
}

show_configure_help() {
    cat << EOF
${COLOR_BOLD}phb configure${COLOR_RESET} - Apply selected patches to kernel

${COLOR_BOLD}USAGE:${COLOR_RESET}
  phb configure [options]

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
  -d, --device NAME      Device codename (required)
  --patches LIST         Comma-separated patches (kernelsu,ttl-bypass)
  --interactive          Interactive patch selection
  -h, --help             Show this help

${COLOR_BOLD}AVAILABLE PATCHES:${COLOR_RESET}
  ${COLOR_GREEN}kernelsu${COLOR_RESET}     - KernelSU-Next root solution
  ${COLOR_GREEN}ttl-bypass${COLOR_RESET}   - TTL/HL hotspot bypass modifications

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  phb configure -d tegu                              # Interactive selection
  phb configure -d tegu --patches kernelsu,ttl-bypass
  phb configure -d tegu --patches kernelsu           # KernelSU only

EOF
}

show_build_help() {
    cat << EOF
${COLOR_BOLD}phb build${COLOR_RESET} - Compile kernel

${COLOR_BOLD}USAGE:${COLOR_RESET}
  phb build [options]

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
  -d, --device NAME      Device codename (required)
  --lto MODE             LTO mode: none, thin, full (default: none)
  --clean                Clean build (remove previous artifacts)
  --auto-expunge         Auto-expunge Bazel cache on failures
  -h, --help             Show this help

${COLOR_BOLD}LTO MODES:${COLOR_RESET}
  ${COLOR_GREEN}none${COLOR_RESET}   - Fastest build, larger binary (recommended)
  ${COLOR_GREEN}thin${COLOR_RESET}   - Balanced optimization
  ${COLOR_GREEN}full${COLOR_RESET}   - Slowest build, smallest binary

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  phb build -d tegu
  phb build -d tegu --clean --lto thin
  phb build -d tegu --auto-expunge

EOF
}

show_flash_help() {
    cat << EOF
${COLOR_BOLD}phb flash${COLOR_RESET} - Flash kernel to device

${COLOR_BOLD}USAGE:${COLOR_RESET}
  phb flash [options]

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
  -d, --device NAME      Device codename (required)
  -o, --output-dir PATH  Custom output directory (default: out/<device>)
  -h, --help             Show this help

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  phb flash -d tegu
  phb flash -d tegu -o /path/to/images

EOF
}

show_deps_help() {
    cat << EOF
${COLOR_BOLD}phb deps${COLOR_RESET} - Check and install dependencies

${COLOR_BOLD}USAGE:${COLOR_RESET}
  phb deps [options]

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
  -i, --install      Install missing dependencies (requires sudo)
  -n, --dry-run      Show what would be installed without installing
  -h, --help         Show this help

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  phb deps                # Check dependencies only
  phb deps --install      # Check and install missing dependencies
  phb deps --dry-run      # Show what would be installed

EOF
}

show_run_help() {
    cat << EOF
${COLOR_BOLD}phb run${COLOR_RESET} - Execute full kernel build workflow

${COLOR_BOLD}USAGE:${COLOR_RESET}
  phb run [options]

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
  -d, --device NAME      Device codename
  -b, --branch NAME      Manifest branch
  --lto MODE             LTO mode: none, thin, full
  --clean                Clean build
  --interactive          Interactive mode with checklists
  --skip-setup           Skip setup step
  --skip-configure       Skip configure step
  --skip-build           Skip build step
  --skip-flash           Skip flash step
  -f, --flash            Auto-flash after build (no prompt)
  -h, --help             Show this help

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
  phb run --interactive              # Full interactive setup
  phb run -d tegu                    # Auto-detect branch, use saved config
  phb run -d tegu -b android-gs-...  # Full workflow with specific branch
  phb run --skip-setup --skip-configure  # Quick rebuild
  phb run -d tegu --clean --flash    # Clean build + auto-flash

EOF
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
DEVICE_CODENAME="$DEVICE_CODENAME"
MANIFEST_BRANCH="$MANIFEST_BRANCH"
MANIFEST_URL="$MANIFEST_URL"
LTO="$LTO"
CLEAN_BUILD="$CLEAN_BUILD"
AUTO_EXPUNGE="$AUTO_EXPUNGE"
ENABLE_KERNELSU="$ENABLE_KERNELSU"
ENABLE_TTL_BYPASS="$ENABLE_TTL_BYPASS"
SOC="$SOC"
EOF
    ui_dim "Configuration saved to .phb.conf"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

cmd_deps() {
    for arg in "$@"; do
        case "$arg" in
            -h|--help) show_deps_help; exit 0 ;;
        esac
    done
    "$SCRIPT_DIR/scripts/install-dependencies.sh" "$@"
}

cmd_detect() {
    ui_header "Device Detection"
    if ! command -v adb &>/dev/null; then
        ui_error "ADB not found in PATH"
        exit 1
    fi
    if ! adb devices | grep -q "device$"; then
        ui_error "No device connected via ADB"
        ui_info "Connect your device and enable USB debugging"
        exit 1
    fi
    local device_codename=$(get_device_property "ro.product.device")
    local device_model=$(get_device_property "ro.product.model")
    local android_version=$(get_device_property "ro.build.version.release")
    local kernel_version=$(get_kernel_version)
    local build_fingerprint=$(get_device_property "ro.build.fingerprint")
    local kernel_major_minor=$(parse_kernel_major_minor "$kernel_version")
    local android_manifest=$(get_android_manifest_version "$android_version")
    local suggested_suffix=$(detect_build_suffix "$build_fingerprint")
    local recommended_branch=$(build_recommended_branch "$device_codename" "$kernel_major_minor" "$android_manifest" "$suggested_suffix")
    echo ""
    ui_table_kv \
        "Device" "$device_codename ($device_model)" \
        "Android" "$android_version" \
        "Kernel" "$kernel_version" \
        "Branch" "$recommended_branch"
    echo ""
    ui_success "Recommended configuration:"
    echo ""
    echo "  ${COLOR_CYAN}phb run -d $device_codename -b $recommended_branch${COLOR_RESET}"
    echo ""
}

interactive_device_selection() {
    local auto_detected=""
    if command -v adb &>/dev/null && adb devices 2>/dev/null | grep -q "device$"; then
        auto_detected=$(get_device_property "ro.product.device" 2>/dev/null || echo "")
    fi
    local selection
    if [[ -n "$auto_detected" ]]; then
        selection=$(ui_select "Select Device" \
            "Auto-detect ($auto_detected)" \
            "tegu (Pixel 9a)" \
            "tokay (Pixel 9)" \
            "caiman (Pixel 9 Pro)" \
            "komodo (Pixel 9 Pro XL)" \
            "comet (Pixel 9 Pro Fold)")
        if [[ "$selection" == "Auto-detect"* ]]; then
            DEVICE_CODENAME="$auto_detected"
        else
            DEVICE_CODENAME=$(echo "$selection" | awk '{print $1}')
        fi
    else
        selection=$(ui_select "Select Device" \
            "tegu (Pixel 9a)" \
            "tokay (Pixel 9)" \
            "caiman (Pixel 9 Pro)" \
            "komodo (Pixel 9 Pro XL)" \
            "comet (Pixel 9 Pro Fold)")
        DEVICE_CODENAME=$(echo "$selection" | awk '{print $1}')
    fi

    local device_family=$(get_device_family "$DEVICE_CODENAME")
    local recommended_branch=""

    if [[ -n "$auto_detected" && "$auto_detected" == "$DEVICE_CODENAME" ]]; then
        local android_version=$(get_device_property "ro.build.version.release")
        local kernel_version=$(get_kernel_version)
        local build_fingerprint=$(get_device_property "ro.build.fingerprint")
        local kernel_major_minor=$(parse_kernel_major_minor "$kernel_version")
        local android_manifest=$(get_android_manifest_version "$android_version")
        local suggested_suffix=$(detect_build_suffix "$build_fingerprint")
        recommended_branch=$(build_recommended_branch "$device_family" "$kernel_major_minor" "$android_manifest" "$suggested_suffix")
    fi

    echo ""
    ui_spinner_start "Fetching available branches for $device_family..."
    local branches_raw
    branches_raw=$(fetch_device_branches "$device_family" "$MANIFEST_URL")
    ui_spinner_stop

    if [[ -z "$branches_raw" ]]; then
        ui_warning "Could not fetch branches. Enter manually:"
        read -p "> " MANIFEST_BRANCH </dev/tty
        return
    fi

    local -a branches=()
    while IFS= read -r branch; do
        [[ -n "$branch" ]] && branches+=("$branch")
    done <<< "$branches_raw"

    if [[ ${#branches[@]} -eq 0 ]]; then
        ui_warning "No branches found for $device_family. Enter manually:"
        read -p "> " MANIFEST_BRANCH </dev/tty
        return
    fi

    if [[ -n "$recommended_branch" ]]; then
        local -a sorted_branches=()
        for b in "${branches[@]}"; do
            if [[ "$b" == "$recommended_branch" ]]; then
                sorted_branches=("$b (recommended)" "${sorted_branches[@]}")
            else
                sorted_branches+=("$b")
            fi
        done
        branches=("${sorted_branches[@]}")
    fi

    local branch_selection
    branch_selection=$(ui_select "Select Branch" "${branches[@]}")
    MANIFEST_BRANCH="${branch_selection% (recommended)}"
    ui_success "Selected branch: $MANIFEST_BRANCH"
}

interactive_patch_selection() {
    local selected=$(ui_checklist "Select Patches" \
        "KernelSU-Next (Root solution)" \
        "TTL/HL Bypass (Hotspot tethering)")
    ENABLE_KERNELSU=false
    ENABLE_TTL_BYPASS=false
    if echo "$selected" | grep -q "KernelSU"; then
        ENABLE_KERNELSU=true
    fi
    if echo "$selected" | grep -q "TTL/HL"; then
        ENABLE_TTL_BYPASS=true
    fi
}

interactive_build_options() {
    local lto_selection=$(ui_select "LTO Mode" \
        "none (Fast build, recommended)" \
        "thin (Balanced)" \
        "full (Slow, optimized)")
    LTO=$(echo "$lto_selection" | awk '{print $1}')
    local clean_selection=$(ui_select "Build Type" \
        "Incremental (faster)" \
        "Clean (from scratch)")
    if [[ "$clean_selection" == "Clean"* ]]; then
        CLEAN_BUILD=1
    else
        CLEAN_BUILD=0
    fi
}

run_interactive_setup() {
    ui_header "Interactive Setup"
    ui_interactive_start
    interactive_device_selection
    interactive_patch_selection
    interactive_build_options
    ui_interactive_end
    ui_header "Configuration Summary"
    echo ""
    ui_table_kv \
        "Device" "$DEVICE_CODENAME" \
        "Branch" "$MANIFEST_BRANCH" \
        "KernelSU" "$([ "$ENABLE_KERNELSU" = true ] && echo "Enabled" || echo "Disabled")" \
        "TTL/HL Bypass" "$([ "$ENABLE_TTL_BYPASS" = true ] && echo "Enabled" || echo "Disabled")" \
        "LTO" "$LTO" \
        "Build Type" "$([ "$CLEAN_BUILD" = "1" ] && echo "Clean" || echo "Incremental")"
    echo ""
    save_config
}

cmd_setup() {
    local device="$DEVICE_CODENAME"
    local branch="$MANIFEST_BRANCH"
    local skip_sync=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--device) device="$2"; shift 2 ;;
            -b|--branch) branch="$2"; shift 2 ;;
            -u|--manifest-url) MANIFEST_URL="$2"; shift 2 ;;
            --skip-sync) skip_sync=true; shift ;;
            -h|--help) show_setup_help; exit 0 ;;
            *) ui_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    [[ -z "$device" ]] && ui_error "Device codename required (-d)" && exit 1
    [[ -z "$branch" ]] && ui_error "Manifest branch required (-b)" && exit 1
    DEVICE_CODENAME="$device"
    MANIFEST_BRANCH="$branch"
    export DEVICE_CODENAME MANIFEST_BRANCH MANIFEST_URL
    export KERNEL_DIR OUTPUT_DIR DEFCONFIG_PATH ROOT_DIR
    source "$SCRIPT_DIR/scripts/setup.sh"
    run_setup
}

cmd_configure() {
    local device="$DEVICE_CODENAME"
    local patches=""
    local interactive_patches=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--device) device="$2"; shift 2 ;;
            --patches) patches="$2"; shift 2 ;;
            --interactive) interactive_patches=true; shift ;;
            -h|--help) show_configure_help; exit 0 ;;
            *) ui_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    [[ -z "$device" ]] && ui_error "Device codename required (-d)" && exit 1
    DEVICE_CODENAME="$device"
    if [[ "$interactive_patches" == true || -z "$patches" ]]; then
        interactive_patch_selection
    else
        ENABLE_KERNELSU=false
        ENABLE_TTL_BYPASS=false
        IFS=',' read -ra PATCH_ARRAY <<< "$patches"
        for patch in "${PATCH_ARRAY[@]}"; do
            case "$patch" in
                kernelsu) ENABLE_KERNELSU=true ;;
                ttl-bypass) ENABLE_TTL_BYPASS=true ;;
                *) ui_warning "Unknown patch: $patch" ;;
            esac
        done
    fi
    export DEVICE_CODENAME KERNELSU_REPO KERNELSU_BRANCH KSU_VERSION KSU_VERSION_TAG
    export ENABLE_KERNELSU ENABLE_TTL_BYPASS
    set_derived_vars
    source "$SCRIPT_DIR/scripts/configure.sh"
    run_configure
}

cmd_build() {
    local device="$DEVICE_CODENAME"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--device) device="$2"; shift 2 ;;
            --lto) LTO="$2"; shift 2 ;;
            --clean) CLEAN_BUILD=1; shift ;;
            --auto-expunge) AUTO_EXPUNGE=1; shift ;;
            -h|--help) show_build_help; exit 0 ;;
            *) ui_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    [[ -z "$device" ]] && ui_error "Device codename required (-d)" && exit 1
    [[ ! "$LTO" =~ ^(none|thin|full)$ ]] && ui_error "Invalid LTO: $LTO (none/thin/full)" && exit 1
    DEVICE_CODENAME="$device"
    export DEVICE_CODENAME LTO CLEAN_BUILD AUTO_EXPUNGE
    export SOC BAZEL_CONFIG BUILD_TARGET
    set_derived_vars
    source "$SCRIPT_DIR/scripts/build.sh"
    run_build
    echo ""
    ui_success "Kernel built successfully!"
    ui_info "Output directory: $OUTPUT_DIR"
}

cmd_flash() {
    local device="$DEVICE_CODENAME"
    local output_dir=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--device) device="$2"; shift 2 ;;
            -o|--output-dir) output_dir="$2"; shift 2 ;;
            -h|--help) show_flash_help; exit 0 ;;
            *) ui_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    [[ -z "$device" ]] && ui_error "Device codename required (-d)" && exit 1
    DEVICE_CODENAME="$device"
    [[ -n "$output_dir" ]] && OUTPUT_DIR="$output_dir"
    export DEVICE_CODENAME OUTPUT_DIR
    set_derived_vars
    source "$SCRIPT_DIR/scripts/flash.sh"
    run_flash
    echo ""
    ui_success "Kernel flashed successfully!"
}

cmd_run() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            -b|--branch) MANIFEST_BRANCH="$2"; shift 2 ;;
            -u|--manifest-url) MANIFEST_URL="$2"; shift 2 ;;
            -l|--lto) LTO="$2"; shift 2 ;;
            -c|--clean) CLEAN_BUILD=1; shift ;;
            -e|--expunge) AUTO_EXPUNGE=1; shift ;;
            -f|--flash) AUTO_FLASH=true; shift ;;
            -i|--interactive) INTERACTIVE=true; shift ;;
            --skip-setup) SKIP_SETUP=true; shift ;;
            --skip-configure) SKIP_CONFIGURE=true; shift ;;
            --skip-build) SKIP_BUILD=true; shift ;;
            --skip-flash) SKIP_FLASH=true; shift ;;
            -h|--help) show_run_help; exit 0 ;;
            *) ui_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    if [[ "$INTERACTIVE" == true ]]; then
        run_interactive_setup
    elif [[ -z "$DEVICE_CODENAME" || -z "$MANIFEST_BRANCH" ]]; then
        if load_config; then
            ui_success "Using saved configuration"
            echo ""
            ui_table_kv \
                "Device" "$DEVICE_CODENAME" \
                "Branch" "$MANIFEST_BRANCH"
            echo ""
        else
            ui_error "No saved configuration found. Run with --interactive or provide -d and -b flags"
            exit 1
        fi
    fi
    [[ -z "$DEVICE_CODENAME" ]] && ui_error "Device codename required" && exit 1
    [[ -z "$MANIFEST_BRANCH" ]] && ui_error "Manifest branch required" && exit 1
    [[ ! "$LTO" =~ ^(none|thin|full)$ ]] && ui_error "Invalid LTO: $LTO" && exit 1
    export DEVICE_CODENAME MANIFEST_BRANCH MANIFEST_URL KERNELSU_REPO KERNELSU_BRANCH \
           KSU_VERSION KSU_VERSION_TAG SOC BAZEL_CONFIG BUILD_TARGET LTO CLEAN_BUILD \
           AUTO_EXPUNGE ENABLE_KERNELSU ENABLE_TTL_BYPASS
    set_derived_vars
    export KERNEL_DIR OUTPUT_DIR DEFCONFIG_PATH ROOT_DIR
    ui_steps_init 4
    if [[ "$SKIP_SETUP" != true ]]; then
        ui_step_start "Setup"
        source "$SCRIPT_DIR/scripts/setup.sh"
        run_setup
        ui_step_complete "Setup"
    else
        ui_dim "[1/4] Setup - Skipped"
    fi
    if [[ "$SKIP_CONFIGURE" != true ]]; then
        ui_step_start "Configure"
        source "$SCRIPT_DIR/scripts/configure.sh"
        run_configure
        ui_step_complete "Configure"
    else
        ui_dim "[2/4] Configure - Skipped"
    fi
    if [[ "$SKIP_BUILD" != true ]]; then
        ui_step_start "Build"
        source "$SCRIPT_DIR/scripts/build.sh"
        run_build
        ui_step_complete "Build"
    else
        ui_dim "[3/4] Build - Skipped"
    fi
    if [[ "$SKIP_FLASH" != true ]]; then
        local should_flash=false
        if [[ "$AUTO_FLASH" == true ]]; then
            should_flash=true
        else
            echo ""
            if ask_confirmation "Flash kernel to device now?" "N"; then
                should_flash=true
            fi
        fi
        if [[ "$should_flash" == true ]]; then
            ui_step_start "Flash"
            source "$SCRIPT_DIR/scripts/flash.sh"
            run_flash
            ui_step_complete "Flash"
            echo ""
            ui_success "All done! Kernel flashed successfully"
        else
            ui_dim "[4/4] Flash - Skipped (user choice)"
            echo ""
            ui_info "Build complete! Flash manually when ready"
        fi
    else
        ui_dim "[4/4] Flash - Skipped"
    fi
    save_config
}

cmd_completion() {
    local shell="${1:-}"
    if [[ -z "$shell" ]]; then
        ui_error "Specify shell: bash or zsh"
        echo ""
        echo "Usage: phb completion bash > /etc/bash_completion.d/phb"
        echo "       phb completion zsh > ~/.zsh/completions/_phb"
        exit 1
    fi
    source "$SCRIPT_DIR/lib/completions.sh"
    generate_completion "$shell"
}

handle_legacy_flags() {
    local has_only_flag=false
    for arg in "$@"; do
        case "$arg" in
            --setup-only|--configure-only|--build-only|--flash-only)
                has_only_flag=true
                break
                ;;
        esac
    done
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_main_help; exit 0 ;;
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            -b|--branch) MANIFEST_BRANCH="$2"; shift 2 ;;
            -u|--manifest-url) MANIFEST_URL="$2"; shift 2 ;;
            -l|--lto) LTO="$2"; shift 2 ;;
            -c|--clean) CLEAN_BUILD=1; shift ;;
            -e|--expunge) AUTO_EXPUNGE=1; shift ;;
            -f|--flash) AUTO_FLASH=true; shift ;;
            -i|--interactive) INTERACTIVE=true; shift ;;
            --detect) cmd_detect; exit 0 ;;
            --skip-setup) SKIP_SETUP=true; shift ;;
            --skip-configure) SKIP_CONFIGURE=true; shift ;;
            --skip-build) SKIP_BUILD=true; shift ;;
            --skip-flash) SKIP_FLASH=true; shift ;;
            --setup-only) ONLY_SETUP=true; shift ;;
            --configure-only) ONLY_CONFIGURE=true; shift ;;
            --build-only) ONLY_BUILD=true; shift ;;
            --flash-only) ONLY_FLASH=true; shift ;;
            --ksu-repo) KERNELSU_REPO="$2"; shift 2 ;;
            --ksu-branch) KERNELSU_BRANCH="$2"; shift 2 ;;
            --ksu-version) KSU_VERSION="$2"; shift 2 ;;
            --ksu-version-tag) KSU_VERSION_TAG="$2"; shift 2 ;;
            --soc) SOC="$2"; shift 2 ;;
            --bazel-config) BAZEL_CONFIG="$2"; shift 2 ;;
            --build-target) BUILD_TARGET="$2"; shift 2 ;;
            *) ui_error "Unknown option: $1"; show_main_help; exit 1 ;;
        esac
    done
    if [[ "$has_only_flag" == true ]]; then
        SKIP_SETUP=true
        SKIP_CONFIGURE=true
        SKIP_BUILD=true
        SKIP_FLASH=true
        [[ "$ONLY_SETUP" == true ]] && SKIP_SETUP=false
        [[ "$ONLY_CONFIGURE" == true ]] && SKIP_CONFIGURE=false
        [[ "$ONLY_BUILD" == true ]] && SKIP_BUILD=false
        [[ "$ONLY_FLASH" == true ]] && SKIP_FLASH=false && AUTO_FLASH=true
    fi
    cmd_run
}

main() {
    if [[ $# -eq 0 ]]; then
        show_main_help
        exit 0
    fi
    local command="$1"
    case "$command" in
        deps|detect|setup|configure|build|flash|run|completion)
            shift
            "cmd_$command" "$@"
            ;;
        -*|--*)
            handle_legacy_flags "$@"
            ;;
        help)
            show_main_help
            exit 0
            ;;
        *)
            ui_error "Unknown command: $command"
            echo ""
            show_main_help
            exit 1
            ;;
    esac
}

main "$@"
