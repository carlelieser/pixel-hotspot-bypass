#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/common.sh"

DEVICE_CODENAME="${DEVICE_CODENAME:-}"
KERNELSU_REPO="${KERNELSU_REPO:-https://github.com/rifsxd/KernelSU-Next}"
KERNELSU_BRANCH="${KERNELSU_BRANCH:-next}"
KSU_VERSION="${KSU_VERSION:-12882}"
KSU_VERSION_TAG="${KSU_VERSION_TAG:-v1.1.1}"
AUTO_EXPUNGE="${AUTO_EXPUNGE:-0}"

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure kernel with KernelSU-Next and hotspot bypass support

REQUIRED OPTIONS (or set via environment variables):
  -d, --device CODENAME     Device codename (e.g., tegu, tokay, caiman)

OPTIONAL OPTIONS:
  --ksu-repo URL            KernelSU repository URL (default: https://github.com/rifsxd/KernelSU-Next)
  --ksu-branch BRANCH       KernelSU branch (default: next)
  --ksu-version VERSION     KernelSU version number (default: 12882)
  --ksu-version-tag TAG     KernelSU version tag (default: v1.1.1)
  -e, --expunge             Auto-expunge Bazel cache on config changes (default: 0)
  -h, --help                Show this help message

EXAMPLES:
  $0 -d tegu
  $0 -d tegu --ksu-version 12900 --ksu-version-tag v1.2.0
  $0 -d tegu --expunge
  export DEVICE_CODENAME=tegu
  export KSU_VERSION=12900
  $0

ENVIRONMENT VARIABLES:
  DEVICE_CODENAME, KERNELSU_REPO, KERNELSU_BRANCH, KSU_VERSION,
  KSU_VERSION_TAG, AUTO_EXPUNGE

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
            *) log_error "Unknown option: $1"; echo ""; show_usage ;;
        esac
    done
}

validate_configure_config() {
    local missing=()
    [[ -z "$DEVICE_CODENAME" ]] && missing+=("DEVICE_CODENAME")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required configuration: ${missing[*]}"
        log_error ""
        log_error "Either:"
        log_error "  1. Pass via command-line flags (see --help)"
        log_error "  2. Set environment variables: ${missing[*]}"
        exit 1
    fi
    [[ ! "$AUTO_EXPUNGE" =~ ^(0|1)$ ]] && log_error_and_exit "Invalid AUTO_EXPUNGE value: '$AUTO_EXPUNGE' (must be: 0 or 1)"
}

clone_kernelsu() {
    local ksu_dir="${KERNEL_DIR}/aosp/drivers/kernelsu"
    if ! confirm_and_remove_directory "$ksu_dir" "KernelSU directory" "re-clone"; then
        return 0
    fi
    log_info "Cloning KernelSU-Next: $KERNELSU_BRANCH"
    git clone "$KERNELSU_REPO" "$ksu_dir" --branch "$KERNELSU_BRANCH" --depth=1
    log_success "KernelSU-Next cloned"
}

apply_bazel_version_fix() {
    local makefile="${KERNEL_DIR}/aosp/drivers/kernelsu/kernel/Makefile"
    require_file "$makefile" "KernelSU Makefile not found: $makefile"
    if check_pattern_exists "^ccflags-y += -DKSU_VERSION=${KSU_VERSION}$" "$makefile" "Version fix already applied"; then
        return 0
    fi
    log_info "Applying Bazel version fix..."
    cp "$makefile" "${makefile}.bak"
    local temp_file=$(mktemp)
    echo "ccflags-y += -DKSU_VERSION=${KSU_VERSION}" > "$temp_file"
    echo "ccflags-y += -DKSU_VERSION_TAG='\"${KSU_VERSION_TAG}\"'" >> "$temp_file"
    echo "" >> "$temp_file"
    cat "$makefile" >> "$temp_file"
    mv "$temp_file" "$makefile"
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
    log_success "Version fix applied successfully"
}

integrate_into_build() {
    local drivers_makefile="${KERNEL_DIR}/aosp/drivers/Makefile"
    local drivers_kconfig="${KERNEL_DIR}/aosp/drivers/Kconfig"
    if ! grep -q "kernelsu" "$drivers_makefile" 2>/dev/null; then
        log_info "Integrating into drivers/Makefile..."
        echo 'obj-$(CONFIG_KSU) += kernelsu/kernel/' >> "$drivers_makefile"
    fi
    if ! grep -q "kernelsu" "$drivers_kconfig" 2>/dev/null; then
        log_info "Integrating into drivers/Kconfig..."
        sed -i '/^endmenu$/i source "drivers/kernelsu/kernel/Kconfig"' "$drivers_kconfig"
    fi
    log_success "Build system integration complete"
}

integrate_kernelsu() {
    print_divider "KernelSU-Next Integration (Version: ${KSU_VERSION} ${KSU_VERSION_TAG})"
    clone_kernelsu
    apply_bazel_version_fix
    integrate_into_build
    log_success "KernelSU-Next integration complete"
}

apply_or_fix_config() {
    local defconfig="$1"
    local config_name="$2"
    local desired_value="$3"
    local desired_line="${config_name}=${desired_value}"
    if grep -q "^${desired_line}$" "$defconfig" 2>/dev/null; then
        log_success "$config_name already correct"
        return 0
    fi
    if grep -q "^${config_name}=" "$defconfig" 2>/dev/null; then
        local current_value=$(grep "^${config_name}=" "$defconfig" | cut -d'=' -f2)
        log_info "Fixing $config_name (was =${current_value}, setting to =${desired_value})"
        sed -i "s/^${config_name}=.*$/${desired_line}/" "$defconfig"
        return 1
    fi
    return 2
}

apply_defconfig_changes() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"
    local marker_comment="# === Hotspot Bypass Additions ==="
    if [[ ! -f "$defconfig_path" ]]; then
        log_error_and_exit "Defconfig not found: $defconfig_path"
    fi
    local already_applied=false
    if grep -q "^${marker_comment}$" "$defconfig_path"; then
        already_applied=true
    fi
    declare -A configs=(
        ["CONFIG_OVERLAY_FS"]="y"
        ["CONFIG_KPROBES"]="y"
        ["CONFIG_HAVE_KPROBES"]="y"
        ["CONFIG_KPROBE_EVENTS"]="y"
        ["CONFIG_KSU"]="y"
        ["CONFIG_NETFILTER_XT_TARGET_HL"]="y"
        ["CONFIG_NETFILTER_ADVANCED"]="y"
    )
    local modified=false
    local to_add=()
    for config_name in "${!configs[@]}"; do
        result=0
        apply_or_fix_config "$defconfig_path" "$config_name" "${configs[$config_name]}" || result=$?
        if [[ $result -eq 1 ]]; then
            modified=true
        elif [[ $result -eq 2 ]]; then
            to_add+=("$config_name")
            modified=true
        fi
    done
    if [[ ${#to_add[@]} -gt 0 ]]; then
        if [[ "$already_applied" == false ]]; then
            echo "" >> "$defconfig_path"
            echo "$marker_comment" >> "$defconfig_path"
        fi
        echo "" >> "$defconfig_path"
        for dep_config in "CONFIG_OVERLAY_FS" "CONFIG_KPROBES" "CONFIG_HAVE_KPROBES" "CONFIG_KPROBE_EVENTS"; do
            if [[ " ${to_add[@]} " =~ " ${dep_config} " ]]; then
                echo "${dep_config}=y" >> "$defconfig_path"
                log_info "Added ${dep_config}=y"
            fi
        done
        echo "" >> "$defconfig_path"
        if [[ " ${to_add[@]} " =~ " CONFIG_KSU " ]]; then
            echo "CONFIG_KSU=y" >> "$defconfig_path"
            log_info "Added CONFIG_KSU=y"
        fi
        echo "" >> "$defconfig_path"
        if [[ " ${to_add[@]} " =~ " CONFIG_NETFILTER_XT_TARGET_HL " ]]; then
            echo "CONFIG_NETFILTER_XT_TARGET_HL=y" >> "$defconfig_path"
            log_info "Added CONFIG_NETFILTER_XT_TARGET_HL=y"
        fi
        echo "" >> "$defconfig_path"
        if [[ " ${to_add[@]} " =~ " CONFIG_NETFILTER_ADVANCED " ]]; then
            echo "CONFIG_NETFILTER_ADVANCED=y" >> "$defconfig_path"
            log_info "Added CONFIG_NETFILTER_ADVANCED=y"
        fi
    fi
    if [[ "$modified" == true ]]; then
        log_success "Device defconfig updated"
    else
        log_success "Device defconfig already up to date"
    fi
}

apply_gki_defconfig_changes() {
    local gki_defconfig="${KERNEL_DIR}/aosp/arch/arm64/configs/gki_defconfig"
    if [[ ! -f "$gki_defconfig" ]]; then
        log_warn "GKI defconfig not found, skipping"
        return 0
    fi
    result=0
    apply_or_fix_config "$gki_defconfig" "CONFIG_NETFILTER_XT_TARGET_HL" "y" || result=$?
    if [[ $result -eq 2 ]]; then
        log_info "Adding CONFIG_NETFILTER_XT_TARGET_HL to GKI defconfig..."
        if grep -q "CONFIG_NETFILTER_XT_TARGET_DSCP=y" "$gki_defconfig"; then
            sed -i '/^CONFIG_NETFILTER_XT_TARGET_DSCP=y$/a CONFIG_NETFILTER_XT_TARGET_HL=y' "$gki_defconfig"
            log_info "Inserted after CONFIG_NETFILTER_XT_TARGET_DSCP (alphabetical order)"
        else
            echo "CONFIG_NETFILTER_XT_TARGET_HL=y" >> "$gki_defconfig"
            log_warn "CONFIG_NETFILTER_XT_TARGET_DSCP not found, appended to end"
        fi
        log_success "GKI defconfig updated"
    elif [[ $result -eq 1 ]]; then
        log_success "GKI defconfig updated"
    else
        log_success "GKI defconfig already up to date"
    fi
}

verify_configs() {
    local defconfig_path="${KERNEL_DIR}/${DEFCONFIG_PATH}"
    local required_configs=(
        "CONFIG_OVERLAY_FS=y" "CONFIG_KPROBES=y" "CONFIG_HAVE_KPROBES=y"
        "CONFIG_KPROBE_EVENTS=y" "CONFIG_KSU=y" "CONFIG_NETFILTER_XT_TARGET_HL=y"
    )
    local missing=()
    for config in "${required_configs[@]}"; do
        if ! grep -q "^${config}$" "$defconfig_path"; then
            missing+=("$config")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Verification failed! Missing: ${missing[*]}"
        return 1
    fi
    log_success "Configuration verified"
}

invalidate_bazel_cache() {
    local makefile="${KERNEL_DIR}/aosp/Makefile"
    if [[ -f "$makefile" ]]; then
        touch "$makefile"
    else
        log_warn "Makefile not found, cache invalidation may not work"
    fi
    if [[ "$AUTO_EXPUNGE" == "1" ]]; then
        log_info "Expunging Bazel cache..."
        cd "$KERNEL_DIR" && tools/bazel clean --expunge
        log_success "Bazel cache cleared"
    else
        log_warn "Tip: Use AUTO_EXPUNGE=1 for guaranteed clean rebuild"
    fi
}

run_configure() {
    log_section "Configure Kernel"
    if [[ ! -d "${KERNEL_DIR}/aosp" ]]; then
        log_error_and_exit "Invalid kernel directory: $KERNEL_DIR (aosp directory not found)"
    fi
    integrate_kernelsu
    apply_defconfig_changes
    apply_gki_defconfig_changes
    verify_configs
    invalidate_bazel_cache
    log_success "Configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_configure_config
    set_derived_vars
    run_configure
fi
