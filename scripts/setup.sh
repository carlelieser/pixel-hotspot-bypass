#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"
source "$ROOT_DIR/lib/ui.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-}"
MANIFEST_URL="${MANIFEST_URL:-https://android.googlesource.com/kernel/manifest}"
SOC="${SOC:-zumapro}"
BAZEL_CONFIG="${BAZEL_CONFIG:-}"
BUILD_TARGET="${BUILD_TARGET:-}"
LTO="${LTO:-none}"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup kernel source for Pixel devices

REQUIRED OPTIONS (or set via environment variables):
  -d, --device CODENAME     Device codename (e.g., tegu, tokay, caiman)
  -b, --branch BRANCH       Manifest branch (e.g., android-gs-tegu-6.1-android16)

OPTIONAL OPTIONS:
  -u, --manifest-url URL    Manifest URL (default: AOSP kernel manifest)
  --soc SOC                 SoC type (default: zumapro)
  --lto MODE                LTO mode: none, thin, full (default: none)
  -h, --help                Show this help message

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage ;;
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            -b|--branch) MANIFEST_BRANCH="$2"; shift 2 ;;
            -u|--manifest-url) MANIFEST_URL="$2"; shift 2 ;;
            --soc) SOC="$2"; shift 2 ;;
            --bazel-config) BAZEL_CONFIG="$2"; shift 2 ;;
            --build-target) BUILD_TARGET="$2"; shift 2 ;;
            --lto) LTO="$2"; shift 2 ;;
            *) ui_error "Unknown option: $1"; show_usage ;;
        esac
    done
}

validate_setup_config() {
    local missing=()
    [[ -z "$DEVICE_CODENAME" ]] && missing+=("device (-d)")
    [[ -z "$MANIFEST_BRANCH" ]] && missing+=("branch (-b)")

    if [[ ${#missing[@]} -gt 0 ]]; then
        ui_error "Missing required options: ${missing[*]}"
        exit 1
    fi
}

# Real-time status helper
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

    local tools=("repo" "git" "python3")
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
        ui_info "Run: ${COLOR_CYAN}phb deps --install${COLOR_RESET}"
        exit 1
    fi
}

setup_kernel_source() {
    echo ""
    echo "${COLOR_BOLD}Kernel Source${COLOR_RESET}"

    # Check if directory exists
    if [[ -d "$KERNEL_DIR" ]]; then
        show_status skip "Directory exists" "$KERNEL_DIR"
        echo ""

        if ! ask_confirmation "  Remove and re-download?" "N"; then
            ui_info "Using existing source"
            return 0
        fi

        show_status checking "Remove existing"
        rm -rf "$KERNEL_DIR"
        show_status ok "Remove existing" "done"
    fi

    # Create directory
    show_status checking "Create directory"
    mkdir -p "$KERNEL_DIR"
    show_status ok "Create directory" "$KERNEL_DIR"

    cd "$KERNEL_DIR"

    # Repo init with spinner
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Initializing repo..."
    tput civis 2>/dev/null || true

    local init_log=$(mktemp)
    local init_pid
    repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --depth=1 &>"$init_log" &
    init_pid=$!

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 $init_pid 2>/dev/null; do
        printf "\r  ${COLOR_BLUE}${frames[$i]}${COLOR_RESET} Initializing repo..."
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done

    wait $init_pid
    local init_status=$?
    tput cnorm 2>/dev/null || true

    if [[ $init_status -eq 0 ]]; then
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} %-25s ${COLOR_GRAY}%s${COLOR_RESET}\n" "Initialize repo" "$MANIFEST_BRANCH"
    else
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} %-25s ${COLOR_RED}failed${COLOR_RESET}\n" "Initialize repo"
        cat "$init_log" >&2
        rm -f "$init_log"
        exit 1
    fi
    rm -f "$init_log"

    # Repo sync with progress
    local num_jobs=$(nproc)
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Syncing source (this takes a while)..."

    local sync_log=$(mktemp)
    local sync_pid
    repo sync -c -j"$num_jobs" --no-tags --no-clone-bundle --fail-fast &>"$sync_log" &
    sync_pid=$!

    local start_time=$(date +%s)
    i=0
    while kill -0 $sync_pid 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start_time ))
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))

        # Try to get current project from log
        local current_project=$(tail -1 "$sync_log" 2>/dev/null | grep -oE 'Fetching: [0-9]+%' | tail -1 || echo "")

        if [[ -n "$current_project" ]]; then
            printf "\r  ${COLOR_BLUE}${frames[$i]}${COLOR_RESET} Syncing source... ${COLOR_CYAN}%s${COLOR_RESET} ${COLOR_GRAY}(%dm %02ds)${COLOR_RESET}  " "$current_project" "$mins" "$secs"
        else
            printf "\r  ${COLOR_BLUE}${frames[$i]}${COLOR_RESET} Syncing source... ${COLOR_GRAY}(%dm %02ds)${COLOR_RESET}  " "$mins" "$secs"
        fi

        i=$(( (i + 1) % 10 ))
        sleep 0.2
    done

    wait $sync_pid
    local sync_status=$?

    local total_time=$(( $(date +%s) - start_time ))
    local total_mins=$((total_time / 60))
    local total_secs=$((total_time % 60))

    if [[ $sync_status -eq 0 ]]; then
        printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} %-25s ${COLOR_GRAY}%dm %02ds${COLOR_RESET}\n" "Sync source" "$total_mins" "$total_secs"
    else
        printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} %-25s ${COLOR_RED}failed${COLOR_RESET}\n" "Sync source"
        echo ""
        echo "${COLOR_RED}Last 20 lines of sync log:${COLOR_RESET}"
        tail -20 "$sync_log" >&2
        rm -f "$sync_log"
        exit 1
    fi
    rm -f "$sync_log"
}

patch_kleaf() {
    echo ""
    echo "${COLOR_BOLD}Patches${COLOR_RESET}"

    local filegroup_bzl="${KERNEL_DIR}/build/kernel/kleaf/impl/kernel_filegroup.bzl"

    show_status checking "Kleaf build system"

    if [[ ! -f "$filegroup_bzl" ]]; then
        show_status skip "Kleaf build system" "not found"
        return 0
    fi

    if grep -q "strip_modules = False" "$filegroup_bzl" 2>/dev/null; then
        show_status skip "Kleaf build system" "already patched"
        return 0
    fi

    # Apply patches
    sed -i 's/collect_unstripped_modules = ctx.attr.collect_unstripped_modules,$/collect_unstripped_modules = ctx.attr.collect_unstripped_modules,\n        strip_modules = False,/' "$filegroup_bzl"

    if ! grep -q "config_env_and_outputs_info = ext_mod_env_and_outputs_info" "$filegroup_bzl"; then
        sed -i 's/modules_install_env_and_outputs_info = ext_mod_env_and_outputs_info,$/modules_install_env_and_outputs_info = ext_mod_env_and_outputs_info,\n        config_env_and_outputs_info = ext_mod_env_and_outputs_info,/' "$filegroup_bzl"
    fi

    if ! grep -q "module_kconfig = depset()" "$filegroup_bzl"; then
        sed -i 's/module_scripts = module_srcs.module_scripts,$/module_scripts = module_srcs.module_scripts,\n        module_kconfig = depset(),/' "$filegroup_bzl"
    fi

    show_status ok "Kleaf build system" "patched"
}

create_build_script() {
    local build_script="${KERNEL_DIR}/build_${DEVICE_CODENAME}.sh"

    show_status checking "Build script"

    cat > "$build_script" << EOF
#!/bin/bash
set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

LTO="\${LTO:-${LTO}}"
BAZEL_CONFIG="\${BAZEL_CONFIG:-${BAZEL_CONFIG}}"
BUILD_TARGET="\${BUILD_TARGET:-${BUILD_TARGET}}"

tools/bazel --bazelrc="private/devices/google/${DEVICE_CODENAME}/device.bazelrc" \\
    build \\
    --lto="\$LTO" \\
    --config="\$BAZEL_CONFIG" \\
    --config=use_source_tree_aosp \\
    "//private/devices/google/${DEVICE_CODENAME}:\$BUILD_TARGET"

echo "Build complete! Output in bazel-bin/"
EOF

    chmod +x "$build_script"
    show_status ok "Build script" "build_${DEVICE_CODENAME}.sh"
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${COLOR_GREEN}✓${COLOR_RESET} Setup complete"
    echo ""
    echo "  Source: ${COLOR_GRAY}$KERNEL_DIR${COLOR_RESET}"
    echo ""
    echo "  Next: ${COLOR_CYAN}phb configure -d $DEVICE_CODENAME${COLOR_RESET}"
}

run_setup() {
    ui_header "Setup Kernel Source"
    echo "  Device: ${COLOR_CYAN}$DEVICE_CODENAME${COLOR_RESET}"
    echo "  Branch: ${COLOR_GRAY}$MANIFEST_BRANCH${COLOR_RESET}"

    check_prerequisites
    setup_kernel_source
    patch_kleaf
    create_build_script
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_setup_config
    set_derived_vars
    run_setup
fi
