#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$(dirname "$SCRIPT_DIR")/lib/ui.sh"

REPO_BIN_DIR="$HOME/.bin"
INSTALL_MISSING=false
DRY_RUN=false

declare -a RESULTS=()
declare -a MISSING_COMMANDS=()
declare -a MISSING_PACKAGES=()

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Check and install dependencies for Pixel Hotspot Bypass kernel build

OPTIONS:
  -i, --install     Install missing dependencies (requires sudo)
  -n, --dry-run     Show what would be installed without installing
  -h, --help        Show this help message

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--install) INSTALL_MISSING=true; shift ;;
            -n|--dry-run) DRY_RUN=true; shift ;;
            -h|--help) show_usage ;;
            *) shift ;;
        esac
    done
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_ID_LIKE="$ID_LIKE"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_ID="macos"
        OS_ID_LIKE=""
    else
        OS_ID="unknown"
        OS_ID_LIKE=""
    fi
}

is_debian_based() { [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID_LIKE" =~ debian ]]; }
is_fedora_based() { [[ "$OS_ID" == "fedora" || "$OS_ID_LIKE" =~ fedora ]]; }
is_arch_based() { [[ "$OS_ID" == "arch" || "$OS_ID_LIKE" =~ arch ]]; }
is_macos() { [[ "$OS_ID" == "macos" ]]; }

check_command() { command -v "$1" &>/dev/null; }

# Check a dependency with real-time spinner feedback
check_dep() {
    local name="$1"
    local cmd="$2"
    local package="$3"
    local version_check="$4"

    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking %s..." "$name"

    local status="ok"
    local detail=""

    if check_command "$cmd"; then
        local path=$(command -v "$cmd")
        detail="$path"

        # Version validation if specified
        if [[ -n "$version_check" ]]; then
            local version_result
            version_result=$(eval "$version_check" 2>/dev/null) || version_result=""
            if [[ -n "$version_result" ]]; then
                detail="v$version_result"
            fi
        fi
    else
        status="missing"
        MISSING_COMMANDS+=("$cmd")
        [[ -n "$package" ]] && MISSING_PACKAGES+=("$package")
    fi

    # Clear line and show result
    printf "\r\033[K"
    if [[ "$status" == "ok" ]]; then
        printf "  ${COLOR_GREEN}✓${COLOR_RESET} %-20s ${COLOR_GRAY}%s${COLOR_RESET}\n" "$name" "$detail"
        RESULTS+=("ok:$name")
    else
        printf "  ${COLOR_RED}✗${COLOR_RESET} %-20s ${COLOR_YELLOW}not found${COLOR_RESET}\n" "$name"
        RESULTS+=("missing:$name")
    fi
}

check_python() {
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking Python 3..."

    if check_command python3; then
        local version=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)

        printf "\r\033[K"
        if [[ "$major" -ge 3 && "$minor" -ge 6 ]]; then
            printf "  ${COLOR_GREEN}✓${COLOR_RESET} %-20s ${COLOR_GRAY}v%s${COLOR_RESET}\n" "Python 3" "$version"
            RESULTS+=("ok:Python 3")
        else
            printf "  ${COLOR_RED}✗${COLOR_RESET} %-20s ${COLOR_YELLOW}v%s (need 3.6+)${COLOR_RESET}\n" "Python 3" "$version"
            RESULTS+=("missing:Python 3")
            MISSING_COMMANDS+=("python3")
            MISSING_PACKAGES+=("python3")
        fi
    else
        printf "\r\033[K"
        printf "  ${COLOR_RED}✗${COLOR_RESET} %-20s ${COLOR_YELLOW}not found${COLOR_RESET}\n" "Python 3"
        RESULTS+=("missing:Python 3")
        MISSING_COMMANDS+=("python3")
        MISSING_PACKAGES+=("python3")
    fi
}

check_java() {
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking Java..."

    if check_command java; then
        local version=$(java -version 2>&1 | head -1 | grep -oE '"[0-9]+' | tr -d '"' | head -1)

        printf "\r\033[K"
        if [[ "$version" -ge 11 ]]; then
            printf "  ${COLOR_GREEN}✓${COLOR_RESET} %-20s ${COLOR_GRAY}v%s${COLOR_RESET}\n" "Java (JDK)" "$version"
            RESULTS+=("ok:Java")
        else
            printf "  ${COLOR_RED}✗${COLOR_RESET} %-20s ${COLOR_YELLOW}v%s (need 11+)${COLOR_RESET}\n" "Java (JDK)" "$version"
            RESULTS+=("missing:Java")
            MISSING_COMMANDS+=("java")
            add_java_package
        fi
    else
        printf "\r\033[K"
        printf "  ${COLOR_RED}✗${COLOR_RESET} %-20s ${COLOR_YELLOW}not found${COLOR_RESET}\n" "Java (JDK)"
        RESULTS+=("missing:Java")
        MISSING_COMMANDS+=("java")
        add_java_package
    fi
}

add_java_package() {
    if is_debian_based; then
        MISSING_PACKAGES+=("openjdk-17-jdk")
    elif is_fedora_based; then
        MISSING_PACKAGES+=("java-17-openjdk-devel")
    elif is_arch_based; then
        MISSING_PACKAGES+=("jdk17-openjdk")
    elif is_macos; then
        MISSING_PACKAGES+=("openjdk@17")
    fi
}

check_repo() {
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking repo tool..."

    local found=false
    local detail=""

    if check_command repo; then
        found=true
        detail=$(command -v repo)
    elif [[ -x "$REPO_BIN_DIR/repo" ]]; then
        found=true
        detail="$REPO_BIN_DIR/repo (add to PATH)"
    fi

    printf "\r\033[K"
    if [[ "$found" == true ]]; then
        printf "  ${COLOR_GREEN}✓${COLOR_RESET} %-20s ${COLOR_GRAY}%s${COLOR_RESET}\n" "repo" "$detail"
        RESULTS+=("ok:repo")
    else
        printf "  ${COLOR_RED}✗${COLOR_RESET} %-20s ${COLOR_YELLOW}not found${COLOR_RESET}\n" "repo"
        RESULTS+=("missing:repo")
        MISSING_COMMANDS+=("repo")
    fi
}

check_android_tools() {
    for tool in adb fastboot; do
        printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Checking %s..." "$tool"

        if check_command "$tool"; then
            local path=$(command -v "$tool")
            printf "\r\033[K"
            printf "  ${COLOR_GREEN}✓${COLOR_RESET} %-20s ${COLOR_GRAY}%s${COLOR_RESET}\n" "$tool" "$path"
            RESULTS+=("ok:$tool")
        else
            printf "\r\033[K"
            printf "  ${COLOR_RED}✗${COLOR_RESET} %-20s ${COLOR_YELLOW}not found${COLOR_RESET}\n" "$tool"
            RESULTS+=("missing:$tool")
            MISSING_COMMANDS+=("$tool")
        fi
    done

    # Add package if either missing
    if [[ " ${MISSING_COMMANDS[*]} " =~ " adb " || " ${MISSING_COMMANDS[*]} " =~ " fastboot " ]]; then
        if is_debian_based; then
            MISSING_PACKAGES+=("android-sdk-platform-tools")
        elif is_arch_based; then
            MISSING_PACKAGES+=("android-tools")
        elif is_macos; then
            MISSING_PACKAGES+=("android-platform-tools")
        fi
    fi
}

run_checks() {
    echo ""
    echo "${COLOR_BOLD}Core Tools${COLOR_RESET}"
    check_dep "git" "git" "git"
    check_dep "curl" "curl" "curl"
    check_dep "wget" "wget" "wget"

    echo ""
    echo "${COLOR_BOLD}Build Tools${COLOR_RESET}"
    check_dep "make" "make" "make"
    check_dep "gcc" "gcc" "gcc"
    check_dep "g++" "g++" "g++"
    check_dep "bc" "bc" "bc"
    check_dep "bison" "bison" "bison"
    check_dep "flex" "flex" "flex"

    echo ""
    echo "${COLOR_BOLD}Runtime${COLOR_RESET}"
    check_python
    check_java
    check_repo

    echo ""
    echo "${COLOR_BOLD}Android Tools${COLOR_RESET}"
    check_android_tools
}

get_install_command() {
    local packages=""

    if is_debian_based; then
        packages="git curl wget python3 build-essential bc bison flex libssl-dev libelf-dev openjdk-17-jdk"
        [[ " ${MISSING_PACKAGES[*]} " =~ "android-sdk-platform-tools" ]] && packages="$packages android-sdk-platform-tools"
        echo "sudo apt update && sudo apt install -y $packages"
    elif is_fedora_based; then
        packages="git curl wget python3 make gcc gcc-c++ bc bison flex openssl-devel elfutils-libelf-devel java-17-openjdk-devel"
        echo "sudo dnf install -y $packages"
    elif is_arch_based; then
        packages="git curl wget python base-devel bc bison flex openssl libelf jdk17-openjdk android-tools"
        echo "sudo pacman -S --needed $packages"
    elif is_macos; then
        packages="git curl wget python@3 coreutils bc bison flex openssl openjdk@17 android-platform-tools"
        echo "brew install $packages"
    fi
}

install_repo_tool() {
    echo ""
    printf "  ${COLOR_BLUE}⠋${COLOR_RESET} Installing repo tool..."

    if [[ "$DRY_RUN" == true ]]; then
        printf "\r\033[K"
        printf "  ${COLOR_CYAN}○${COLOR_RESET} Would install repo to %s\n" "$REPO_BIN_DIR/repo"
        return 0
    fi

    mkdir -p "$REPO_BIN_DIR"
    if curl -sL https://storage.googleapis.com/git-repo-downloads/repo > "$REPO_BIN_DIR/repo"; then
        chmod a+x "$REPO_BIN_DIR/repo"
        printf "\r\033[K"
        printf "  ${COLOR_GREEN}✓${COLOR_RESET} repo installed to %s\n" "$REPO_BIN_DIR/repo"

        if [[ ":$PATH:" != *":$REPO_BIN_DIR:"* ]]; then
            echo ""
            ui_warning "Add to your shell profile: export PATH=\"\$HOME/.bin:\$PATH\""
        fi
    else
        printf "\r\033[K"
        printf "  ${COLOR_RED}✗${COLOR_RESET} Failed to install repo\n"
        return 1
    fi
}

install_packages() {
    local cmd=$(get_install_command)

    if [[ -z "$cmd" ]]; then
        ui_error "Unsupported OS: $OS_ID"
        return 1
    fi

    echo ""
    echo "${COLOR_BOLD}Installing Packages${COLOR_RESET}"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo "  ${COLOR_CYAN}○${COLOR_RESET} Would run: $cmd"
        return 0
    fi

    echo "  ${COLOR_GRAY}$ $cmd${COLOR_RESET}"
    echo ""
    eval "$cmd"
}

print_summary() {
    local ok_count=0
    local missing_count=0

    for result in "${RESULTS[@]}"; do
        if [[ "$result" == ok:* ]]; then
            ((ok_count++))
        else
            ((missing_count++))
        fi
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $missing_count -eq 0 ]]; then
        echo "${COLOR_GREEN}✓${COLOR_RESET} All $ok_count dependencies installed"
        return 0
    fi

    echo "${COLOR_YELLOW}⚠${COLOR_RESET} $ok_count installed, $missing_count missing"
    echo ""
    echo "Missing: ${COLOR_RED}${MISSING_COMMANDS[*]}${COLOR_RESET}"

    if [[ "$INSTALL_MISSING" != true && "$DRY_RUN" != true ]]; then
        echo ""
        echo "Run ${COLOR_CYAN}phb deps --install${COLOR_RESET} to install missing dependencies"

        local cmd=$(get_install_command)
        if [[ -n "$cmd" ]]; then
            echo ""
            echo "Or manually:"
            echo "  ${COLOR_GRAY}$cmd${COLOR_RESET}"
        fi

        if [[ " ${MISSING_COMMANDS[*]} " =~ " repo " ]]; then
            echo ""
            echo "Install repo:"
            echo "  ${COLOR_GRAY}mkdir -p ~/.bin${COLOR_RESET}"
            echo "  ${COLOR_GRAY}curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo${COLOR_RESET}"
            echo "  ${COLOR_GRAY}chmod a+x ~/.bin/repo${COLOR_RESET}"
            echo "  ${COLOR_GRAY}export PATH=\"\$HOME/.bin:\$PATH\"${COLOR_RESET}"
        fi
    fi

    return 1
}

main() {
    parse_arguments "$@"
    detect_os

    ui_header "Dependency Check"
    echo "  OS: ${COLOR_CYAN}$OS_ID${COLOR_RESET}"

    run_checks

    local needs_install=false
    [[ ${#MISSING_COMMANDS[@]} -gt 0 ]] && needs_install=true

    if [[ "$needs_install" == true && ("$INSTALL_MISSING" == true || "$DRY_RUN" == true) ]]; then
        install_packages

        if [[ " ${MISSING_COMMANDS[*]} " =~ " repo " ]]; then
            install_repo_tool
        fi
    fi

    print_summary
}

main "$@"
