#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"
source "$ROOT_DIR/lib/ui.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"
KERNELSU_REPO="${KERNELSU_REPO:-https://github.com/rifsxd/KernelSU-Next}"
KERNELSU_BRANCH="${KERNELSU_BRANCH:-next}"
KSU_VERSION="${KSU_VERSION:-12882}"
KSU_VERSION_TAG="${KSU_VERSION_TAG:-v1.1.1}"
AUTO_EXPUNGE="${AUTO_EXPUNGE:-0}"
ENABLE_WILD="${ENABLE_WILD:-false}"
ENABLE_SULTAN="${ENABLE_SULTAN:-false}"
WILDKERNELS_REPO="https://raw.githubusercontent.com/WildKernels/kernel_patches/main"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure kernel with KernelSU-Next and hotspot bypass support

REQUIRED OPTIONS (or set via environment variables):
  -d, --device CODENAME     Device codename (e.g., tegu, tokay, caiman)

OPTIONAL OPTIONS:
  --ksu-repo URL            KernelSU repository URL
  --ksu-branch BRANCH       KernelSU branch (default: next)
  --ksu-version VERSION     KernelSU version number (default: 12882)
  --ksu-version-tag TAG     KernelSU version tag (default: v1.1.1)
  -e, --expunge             Auto-expunge Bazel cache
  -h, --help                Show this help message

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage ;;
            -d|--device) DEVICE_CODENAME="$2"; shift 2 ;;
            --ksu-repo) KERNELSU_REPO="$2"; shift 2 ;;
            --ksu-branch) KERNELSU_BRANCH="$2"; shift 2 ;;
            --ksu-version) KSU_VERSION="$2"; shift 2 ;;
            --ksu-version-tag) KSU_VERSION_TAG="$2"; shift 2 ;;
            -e|--expunge) AUTO_EXPUNGE=1; shift ;;
            *) ui_error "Unknown option: $1"; show_usage ;;
        esac
    done
}

validate_configure_config() {
    if [[ -z "$DEVICE_CODENAME" ]]; then
        ui_error "Device codename required (-d)"
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
            printf "\r\033[K  ${COLOR_GREEN}✓${COLOR_RESET} %-30s ${COLOR_GRAY}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
        added)
            printf "\r\033[K  ${COLOR_GREEN}+${COLOR_RESET} %-30s ${COLOR_CYAN}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
        fixed)
            printf "\r\033[K  ${COLOR_YELLOW}~${COLOR_RESET} %-30s ${COLOR_CYAN}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
        skip)
            printf "\r\033[K  ${COLOR_GRAY}○${COLOR_RESET} %-30s ${COLOR_GRAY}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
        error)
            printf "\r\033[K  ${COLOR_RED}✗${COLOR_RESET} %-30s ${COLOR_RED}%s${COLOR_RESET}\n" "$name" "$detail"
            ;;
    esac
}

clone_kernelsu() {
    local ksu_dir="${KERNEL_DIR}/aosp/drivers/kernelsu"

    show_status checking "Clone KernelSU-Next"

    if [[ -d "$ksu_dir" ]]; then
        show_status skip "Clone KernelSU-Next" "already exists"
        return 0
    fi

    if git clone "$KERNELSU_REPO" "$ksu_dir" --branch "$KERNELSU_BRANCH" --depth=1 &>/dev/null; then
        show_status ok "Clone KernelSU-Next" "$KERNELSU_BRANCH"
    else
        show_status error "Clone KernelSU-Next" "failed"
        exit 1
    fi
}

apply_bazel_version_fix() {
    local makefile="${KERNEL_DIR}/aosp/drivers/kernelsu/kernel/Makefile"

    show_status checking "Apply version fix"

    if [[ ! -f "$makefile" ]]; then
        show_status error "Apply version fix" "Makefile not found"
        exit 1
    fi

    if grep -q "^ccflags-y += -DKSU_VERSION=${KSU_VERSION}$" "$makefile" 2>/dev/null; then
        show_status skip "Apply version fix" "already applied"
        return 0
    fi

    cp "$makefile" "${makefile}.bak"
    local temp_file=$(mktemp)
    echo "ccflags-y += -DKSU_VERSION=${KSU_VERSION}" > "$temp_file"
    echo "ccflags-y += -DKSU_VERSION_TAG='\"${KSU_VERSION_TAG}\"'" >> "$temp_file"
    echo "" >> "$temp_file"
    cat "$makefile" >> "$temp_file"
    mv "$temp_file" "$makefile"

    # Disable conflicting lines
    sed -i 's/^ccflags-y += -DKSU_VERSION_TAG=.*\$(KSU_VERSION_TAG).*$/#DISABLED &/' "$makefile"
    sed -i 's/^ccflags-y += -DKSU_VERSION_TAG=.*v0\.0\.0.*$/#DISABLED &/' "$makefile"
    sed -i 's/^ccflags-y += -DKSU_VERSION=.*\$(KSU_VERSION)$/#DISABLED &/' "$makefile"
    sed -i '4,$s/^ccflags-y += -DKSU_VERSION=[0-9]*$/#DISABLED &/' "$makefile"

    sed -i '/^obj-\$(CONFIG_KSU) += kernelsu.o$/,/^# \.git is a text file while/ {
        /^obj-\$(CONFIG_KSU) += kernelsu.o$/!{
            /^# \.git is a text file while/!{
                /^$/!s/^/#DISABLED /
            }
        }
    }' "$makefile"

    sed -i '/^# \.git is a text file while/,/^ifeq (\$(shell grep -q.*current_sid/ {
        /^# \.git is a text file while/!{
            /^ifeq (\$(shell grep -q.*current_sid/!{
                /^$/!s/^/#DISABLED /
            }
        }
    }' "$makefile"

    show_status ok "Apply version fix" "v${KSU_VERSION}"
}

integrate_into_build() {
    local drivers_makefile="${KERNEL_DIR}/aosp/drivers/Makefile"
    local drivers_kconfig="${KERNEL_DIR}/aosp/drivers/Kconfig"
    local makefile_done=false
    local kconfig_done=false

    show_status checking "Integrate into build"

    if grep -q "kernelsu" "$drivers_makefile" 2>/dev/null; then
        makefile_done=true
    else
        echo 'obj-$(CONFIG_KSU) += kernelsu/kernel/' >> "$drivers_makefile"
    fi

    if grep -q "kernelsu" "$drivers_kconfig" 2>/dev/null; then
        kconfig_done=true
    else
        sed -i '/^endmenu$/i source "drivers/kernelsu/kernel/Kconfig"' "$drivers_kconfig"
    fi

    if [[ "$makefile_done" == true && "$kconfig_done" == true ]]; then
        show_status skip "Integrate into build" "already done"
    else
        show_status ok "Integrate into build" "Makefile + Kconfig"
    fi
}

apply_config() {
    local defconfig="$1"
    local config_name="$2"
    local desired_value="$3"

    show_status checking "$config_name"

    if grep -q "^${config_name}=${desired_value}$" "$defconfig" 2>/dev/null; then
        show_status ok "$config_name" "=${desired_value}"
        return 0
    fi

    if grep -q "^${config_name}=" "$defconfig" 2>/dev/null; then
        local current=$(grep "^${config_name}=" "$defconfig" | cut -d'=' -f2)
        sed -i "s/^${config_name}=.*$/${config_name}=${desired_value}/" "$defconfig"
        show_status fixed "$config_name" "${current} → ${desired_value}"
        return 0
    fi

    echo "${config_name}=${desired_value}" >> "$defconfig"
    show_status added "$config_name" "=${desired_value}"
    return 0
}

apply_defconfig_changes() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"

    if [[ ! -f "$defconfig_path" ]]; then
        ui_error "Defconfig not found: $defconfig_path"
        exit 1
    fi

    echo ""
    echo "${COLOR_BOLD}Device Config${COLOR_RESET} ${COLOR_GRAY}($DEVICE_CODENAME)${COLOR_RESET}"

    # Add marker if not present
    local marker="# === Hotspot Bypass Additions ==="
    if ! grep -q "^${marker}$" "$defconfig_path"; then
        echo "" >> "$defconfig_path"
        echo "$marker" >> "$defconfig_path"
    fi

    apply_config "$defconfig_path" "CONFIG_OVERLAY_FS" "y"
    apply_config "$defconfig_path" "CONFIG_KPROBES" "y"
    apply_config "$defconfig_path" "CONFIG_HAVE_KPROBES" "y"
    apply_config "$defconfig_path" "CONFIG_KPROBE_EVENTS" "y"
    apply_config "$defconfig_path" "CONFIG_KSU" "y"
    apply_config "$defconfig_path" "CONFIG_NETFILTER_XT_TARGET_HL" "y"
    apply_config "$defconfig_path" "CONFIG_NETFILTER_ADVANCED" "y"
}

apply_gki_defconfig_changes() {
    local gki_defconfig="${KERNEL_DIR}/aosp/arch/arm64/configs/gki_defconfig"

    echo ""
    echo "${COLOR_BOLD}GKI Config${COLOR_RESET}"

    if [[ ! -f "$gki_defconfig" ]]; then
        show_status skip "CONFIG_NETFILTER_XT_TARGET_HL" "GKI defconfig not found"
        return 0
    fi

    show_status checking "CONFIG_NETFILTER_XT_TARGET_HL"

    if grep -q "^CONFIG_NETFILTER_XT_TARGET_HL=y$" "$gki_defconfig" 2>/dev/null; then
        show_status ok "CONFIG_NETFILTER_XT_TARGET_HL" "=y"
        return 0
    fi

    if grep -q "CONFIG_NETFILTER_XT_TARGET_DSCP=y" "$gki_defconfig"; then
        sed -i '/^CONFIG_NETFILTER_XT_TARGET_DSCP=y$/a CONFIG_NETFILTER_XT_TARGET_HL=y' "$gki_defconfig"
        show_status added "CONFIG_NETFILTER_XT_TARGET_HL" "=y (after DSCP)"
    else
        echo "CONFIG_NETFILTER_XT_TARGET_HL=y" >> "$gki_defconfig"
        show_status added "CONFIG_NETFILTER_XT_TARGET_HL" "=y (appended)"
    fi
}

verify_configs() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"
    local required=(
        "CONFIG_OVERLAY_FS=y"
        "CONFIG_KPROBES=y"
        "CONFIG_HAVE_KPROBES=y"
        "CONFIG_KPROBE_EVENTS=y"
        "CONFIG_KSU=y"
        "CONFIG_NETFILTER_XT_TARGET_HL=y"
    )
    local missing=()

    echo ""
    echo "${COLOR_BOLD}Verification${COLOR_RESET}"

    for config in "${required[@]}"; do
        local name="${config%=*}"
        show_status checking "$name"

        if grep -q "^${config}$" "$defconfig_path" 2>/dev/null; then
            show_status ok "$name" "verified"
        else
            show_status error "$name" "missing"
            missing+=("$config")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        ui_error "Verification failed: ${missing[*]}"
        return 1
    fi
}

download_patch() {
    local url="$1"
    local dest="$2"
    local name="$3"

    show_status checking "Download $name"

    if [[ -f "$dest" ]]; then
        show_status skip "Download $name" "already exists"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    if curl -sL "$url" -o "$dest" 2>/dev/null; then
        show_status ok "Download $name" "downloaded"
        return 0
    else
        show_status error "Download $name" "failed"
        return 1
    fi
}

apply_patch_file() {
    local patch_file="$1"
    local patch_name="$2"
    local target_dir="${3:-${KERNEL_DIR}/aosp}"

    show_status checking "Apply $patch_name"

    if [[ ! -f "$patch_file" ]]; then
        show_status skip "Apply $patch_name" "patch not found"
        return 0
    fi

    cd "$target_dir"
    if git apply --check "$patch_file" &>/dev/null; then
        if git apply "$patch_file" &>/dev/null; then
            show_status ok "Apply $patch_name" "applied"
            return 0
        else
            show_status skip "Apply $patch_name" "apply failed"
            return 0
        fi
    else
        # Check if already applied by checking reverse
        if git apply --check -R "$patch_file" &>/dev/null; then
            show_status skip "Apply $patch_name" "already applied"
            return 0
        else
            # Try with 3-way merge for better conflict handling
            if git apply --3way "$patch_file" &>/dev/null; then
                show_status ok "Apply $patch_name" "applied (3way)"
                return 0
            else
                show_status skip "Apply $patch_name" "skipped (conflicts)"
                return 0
            fi
        fi
    fi
}

download_wild_patches() {
    local patches_dir="${ROOT_DIR}/patches/wild"

    echo ""
    echo "${COLOR_BOLD}Download Wild Patches${COLOR_RESET}"

    # Hooks
    download_patch "${WILDKERNELS_REPO}/wild/hooks/ksu_hooks.patch" \
        "${patches_dir}/hooks/ksu_hooks.patch" "wild/hooks/ksu_hooks"
    download_patch "${WILDKERNELS_REPO}/wild/hooks/syscall_hooks.patch" \
        "${patches_dir}/hooks/syscall_hooks.patch" "wild/hooks/syscall_hooks"
    download_patch "${WILDKERNELS_REPO}/wild/hooks/scope_min_manual_hooks_v1.4.patch" \
        "${patches_dir}/hooks/scope_min_manual_hooks.patch" "wild/hooks/scope_min_manual"

    # Bypass patches
    download_patch "${WILDKERNELS_REPO}/wild/bypass_patches/abi_bypass_gki.patch" \
        "${patches_dir}/bypass/abi_bypass_gki.patch" "wild/bypass/abi_bypass_gki"
}

download_sultan_patches() {
    local patches_dir="${ROOT_DIR}/patches/sultan"

    echo ""
    echo "${COLOR_BOLD}Download Sultan Patches${COLOR_RESET}"

    download_patch "${WILDKERNELS_REPO}/sultan/ksu_hooks.patch" \
        "${patches_dir}/ksu_hooks.patch" "sultan/ksu_hooks"
    download_patch "${WILDKERNELS_REPO}/sultan/syscall_hooks.patch" \
        "${patches_dir}/syscall_hooks.patch" "sultan/syscall_hooks"
    download_patch "${WILDKERNELS_REPO}/sultan/sys.c_fix.patch" \
        "${patches_dir}/sys.c_fix.patch" "sultan/sys.c_fix"
}

apply_wild_patches() {
    local patches_dir="${ROOT_DIR}/patches/wild"

    echo ""
    echo "${COLOR_BOLD}Apply Wild Patches${COLOR_RESET}"
    echo "  ${COLOR_GRAY}Note: Hook patches skipped for KernelSU-Next (uses kprobes)${COLOR_RESET}"

    # Skip hook patches - they're for manual hook KSU, not KernelSU-Next which uses kprobes
    # The hooks and syscall_hooks patches are interdependent and incompatible with kprobe-based KSU

    # Apply bypass patches only
    [[ -f "${patches_dir}/bypass/abi_bypass_gki.patch" ]] && \
        apply_patch_file "${patches_dir}/bypass/abi_bypass_gki.patch" "wild/abi_bypass_gki"
}

apply_sultan_patches() {
    local patches_dir="${ROOT_DIR}/patches/sultan"

    echo ""
    echo "${COLOR_BOLD}Apply Sultan Patches${COLOR_RESET}"
    echo "  ${COLOR_GRAY}Note: Hook patches skipped for KernelSU-Next (uses kprobes)${COLOR_RESET}"

    # Skip hook patches - they're for manual hook KSU, not KernelSU-Next which uses kprobes
    # Only sys.c_fix may be applicable
    [[ -f "${patches_dir}/sys.c_fix.patch" ]] && \
        apply_patch_file "${patches_dir}/sys.c_fix.patch" "sultan/sys.c_fix"
}

invalidate_cache() {
    echo ""
    echo "${COLOR_BOLD}Build Cache${COLOR_RESET}"

    show_status checking "Invalidate cache"

    local makefile="${KERNEL_DIR}/aosp/Makefile"
    if [[ -f "$makefile" ]]; then
        touch "$makefile"
        show_status ok "Invalidate cache" "touched Makefile"
    else
        show_status skip "Invalidate cache" "Makefile not found"
    fi

    if [[ "$AUTO_EXPUNGE" == "1" ]]; then
        show_status checking "Expunge Bazel cache"
        if cd "$KERNEL_DIR" && tools/bazel clean --expunge &>/dev/null; then
            show_status ok "Expunge Bazel cache" "cleared"
        else
            show_status error "Expunge Bazel cache" "failed"
        fi
    fi
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${COLOR_GREEN}✓${COLOR_RESET} Configuration complete"
    # Only show "Next" hint when running standalone
    if [[ "${PHB_WORKFLOW:-}" != "true" ]]; then
        echo ""
        echo "  Next: ${COLOR_CYAN}phb build -d $DEVICE_CODENAME${COLOR_RESET}"
    fi
}

run_configure() {
    ui_header "Configure Kernel"
    echo "  Device: ${COLOR_CYAN}$DEVICE_CODENAME${COLOR_RESET}"
    echo "  KernelSU: ${COLOR_GRAY}${KSU_VERSION} (${KSU_VERSION_TAG})${COLOR_RESET}"

    if [[ ! -d "${KERNEL_DIR}/aosp" ]]; then
        echo ""
        ui_error "Kernel source not found: $KERNEL_DIR"
        ui_info "Run setup first: ${COLOR_CYAN}phb setup -d $DEVICE_CODENAME -b <branch>${COLOR_RESET}"
        exit 1
    fi

    echo ""
    echo "${COLOR_BOLD}KernelSU Integration${COLOR_RESET}"
    clone_kernelsu
    apply_bazel_version_fix
    integrate_into_build

    apply_defconfig_changes
    apply_gki_defconfig_changes

    # WildKernels patches
    if [[ "$ENABLE_WILD" == "true" ]]; then
        download_wild_patches
        apply_wild_patches
    fi

    if [[ "$ENABLE_SULTAN" == "true" ]]; then
        download_sultan_patches
        apply_sultan_patches
    fi

    verify_configs
    invalidate_cache
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_configure_config
    set_derived_vars
    run_configure
fi
