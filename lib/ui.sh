#!/usr/bin/env bash

if [[ -t 1 ]] && command -v tput &>/dev/null; then
    COLOR_RESET=$(tput sgr0)
    COLOR_BOLD=$(tput bold)
    COLOR_RED=$(tput setaf 1)
    COLOR_GREEN=$(tput setaf 2)
    COLOR_YELLOW=$(tput setaf 3)
    COLOR_BLUE=$(tput setaf 4)
    COLOR_MAGENTA=$(tput setaf 5)
    COLOR_CYAN=$(tput setaf 6)
    COLOR_GRAY=$(tput setaf 8)
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_GRAY=""
fi

ui_success() { echo "${COLOR_GREEN}✓${COLOR_RESET} $*"; }
ui_error() { echo "${COLOR_RED}✗${COLOR_RESET} $*" >&2; }
ui_warning() { echo "${COLOR_YELLOW}⚠${COLOR_RESET} $*"; }
ui_info() { echo "${COLOR_BLUE}ℹ${COLOR_RESET} $*"; }
ui_step() { echo "${COLOR_CYAN}▸${COLOR_RESET} $*"; }
ui_header() { echo ""; echo "${COLOR_BOLD}${COLOR_MAGENTA}$*${COLOR_RESET}"; echo ""; }
ui_dim() { echo "${COLOR_GRAY}$*${COLOR_RESET}"; }

SPINNER_PID=""
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

ui_spinner_start() {
    local message="$1"
    tput civis 2>/dev/null || true
    {
        local i=0
        while true; do
            printf "\r${COLOR_BLUE}${SPINNER_FRAMES[$i]}${COLOR_RESET} %s" "$message"
            i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.1
        done
    } &
    SPINNER_PID=$!
}

ui_spinner_stop() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    printf "\r\033[K"
    tput cnorm 2>/dev/null || true
    if [[ -n "$1" ]]; then
        ui_success "$1"
    fi
}

ui_with_spinner() {
    local message="$1"
    shift
    ui_spinner_start "$message"
    local output
    local exit_code=0
    output=$("$@" 2>&1) || exit_code=$?
    ui_spinner_stop
    if [[ $exit_code -eq 0 ]]; then
        ui_success "$message"
    else
        ui_error "$message"
        echo "$output" >&2
    fi
    return $exit_code
}

# Only initialize if not already set (prevents reset when sourced multiple times)
UI_STEP_CURRENT="${UI_STEP_CURRENT:-0}"
UI_STEP_TOTAL="${UI_STEP_TOTAL:-0}"
UI_STEP_START_TIME="${UI_STEP_START_TIME:-0}"

ui_steps_init() {
    UI_STEP_TOTAL=$1
    UI_STEP_CURRENT=0
}

ui_step_start() {
    UI_STEP_CURRENT=$((UI_STEP_CURRENT + 1))
    UI_STEP_START_TIME=$(date +%s)
    local step_name="$1"
    echo ""
    echo "${COLOR_BOLD}[$UI_STEP_CURRENT/$UI_STEP_TOTAL]${COLOR_RESET} ${COLOR_CYAN}$step_name${COLOR_RESET}"
}

ui_step_complete() {
    local step_name="$1"
    local duration_override="$2"
    local duration
    if [[ -n "$duration_override" ]]; then
        duration="$duration_override"
    else
        local end_time=$(date +%s)
        duration=$((end_time - UI_STEP_START_TIME))
    fi
    ui_success "$step_name complete ${COLOR_GRAY}(${duration}s)${COLOR_RESET}"
}

ui_table() {
    local -a headers=()
    local -a rows=()
    local current_row=()
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            if [[ ${#headers[@]} -eq 0 ]]; then
                headers=("${current_row[@]}")
            else
                rows+=("${current_row[*]}")
            fi
            current_row=()
        else
            current_row+=("$1")
        fi
        shift
    done
    if [[ ${#current_row[@]} -gt 0 ]]; then
        rows+=("${current_row[*]}")
    fi
    local num_cols=${#headers[@]}
    local -a col_widths=()
    for ((i=0; i<num_cols; i++)); do
        local max_width=${#headers[$i]}
        for row in "${rows[@]}"; do
            IFS=' ' read -ra cols <<< "$row"
            local cell_width=${#cols[$i]}
            if [[ $cell_width -gt $max_width ]]; then
                max_width=$cell_width
            fi
        done
        col_widths+=($max_width)
    done
    local total_width=0
    for width in "${col_widths[@]}"; do
        total_width=$((total_width + width + 3))
    done
    total_width=$((total_width + 1))
    echo "┌$(printf '─%.0s' $(seq 1 $((total_width - 2))))┐"
    printf "│"
    for ((i=0; i<num_cols; i++)); do
        printf " ${COLOR_BOLD}%-${col_widths[$i]}s${COLOR_RESET} │" "${headers[$i]}"
    done
    echo ""
    echo "├$(printf '─%.0s' $(seq 1 $((total_width - 2))))┤"
    for row in "${rows[@]}"; do
        IFS=' ' read -ra cols <<< "$row"
        printf "│"
        for ((i=0; i<num_cols; i++)); do
            printf " %-${col_widths[$i]}s │" "${cols[$i]:-}"
        done
        echo ""
    done
    echo "└$(printf '─%.0s' $(seq 1 $((total_width - 2))))┘"
}

ui_table_kv() {
    local -a rows=()
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        shift 2 || break
        rows+=("$key|$value")
    done
    local max_key_width=0
    for row in "${rows[@]}"; do
        local key="${row%%|*}"
        if [[ ${#key} -gt $max_key_width ]]; then
            max_key_width=${#key}
        fi
    done
    local total_width=$((max_key_width + 40))
    echo "┌$(printf '─%.0s' $(seq 1 $((total_width - 2))))┐"
    for row in "${rows[@]}"; do
        local key="${row%%|*}"
        local value="${row#*|}"
        printf "│ ${COLOR_BOLD}%-${max_key_width}s${COLOR_RESET} │ %-$((total_width - max_key_width - 7))s │\n" "$key" "$value"
    done
    echo "└$(printf '─%.0s' $(seq 1 $((total_width - 2))))┘"
}

ui_checklist() {
    local title="$1"
    shift
    local -a items=("$@")
    local -a selected=()
    for item in "${items[@]}"; do
        selected+=("false")
    done
    local current=0
    local key

    # Enter alternate screen buffer, hide cursor
    printf '\033[?1049h\033[?25l\033[H' >/dev/tty

    while true; do
        # Move to top-left and clear screen
        printf '\033[H\033[J' >/dev/tty

        printf '%s\n\n' "${COLOR_BOLD}${COLOR_MAGENTA}$title${COLOR_RESET}" >/dev/tty
        for ((i=0; i<${#items[@]}; i++)); do
            local checkbox="☐"
            local color=""
            if [[ "${selected[$i]}" == "true" ]]; then
                checkbox="☑"
                color="${COLOR_GREEN}"
            fi
            if [[ $i -eq $current ]]; then
                printf '%s\n' "${COLOR_CYAN}▸${COLOR_RESET} ${color}${checkbox} ${items[$i]}${COLOR_RESET}" >/dev/tty
            else
                printf '%s\n' "  ${color}${checkbox} ${items[$i]}${COLOR_RESET}" >/dev/tty
            fi
        done
        printf '\n%s\n' "${COLOR_GRAY}↑/↓: Navigate  Space: Toggle  Enter: Confirm${COLOR_RESET}" >/dev/tty

        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\x1b')
                IFS= read -rsn2 -t 0.1 key </dev/tty
                case "$key" in
                    '[A') ((current--)); if [[ $current -lt 0 ]]; then current=$((${#items[@]} - 1)); fi ;;
                    '[B') ((current++)); if [[ $current -ge ${#items[@]} ]]; then current=0; fi ;;
                esac
                ;;
            ' ')
                if [[ "${selected[$current]}" == "true" ]]; then
                    selected[$current]="false"
                else
                    selected[$current]="true"
                fi
                ;;
            '') break ;;
        esac
    done

    # Exit alternate screen buffer, show cursor
    printf '\033[?25h\033[?1049l' >/dev/tty

    local result=()
    for ((i=0; i<${#items[@]}; i++)); do
        if [[ "${selected[$i]}" == "true" ]]; then
            result+=("${items[$i]}")
        fi
    done
    echo "${result[*]}"
}

ui_select() {
    local title="$1"
    shift
    local -a items=("$@")
    local current=0
    local key

    # Enter alternate screen buffer, hide cursor
    printf '\033[?1049h\033[?25l\033[H' >/dev/tty

    while true; do
        # Move to top-left and clear screen
        printf '\033[H\033[J' >/dev/tty

        printf '%s\n\n' "${COLOR_BOLD}${COLOR_MAGENTA}$title${COLOR_RESET}" >/dev/tty
        for ((i=0; i<${#items[@]}; i++)); do
            if [[ $i -eq $current ]]; then
                printf '%s\n' "${COLOR_CYAN}▸${COLOR_RESET} ${COLOR_GREEN}●${COLOR_RESET} ${items[$i]}" >/dev/tty
            else
                printf '%s\n' "  ○ ${items[$i]}" >/dev/tty
            fi
        done
        printf '\n%s\n' "${COLOR_GRAY}↑/↓: Navigate  Enter: Select${COLOR_RESET}" >/dev/tty

        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\x1b')
                IFS= read -rsn2 -t 0.1 key </dev/tty
                case "$key" in
                    '[A') ((current--)); if [[ $current -lt 0 ]]; then current=$((${#items[@]} - 1)); fi ;;
                    '[B') ((current++)); if [[ $current -ge ${#items[@]} ]]; then current=0; fi ;;
                esac
                ;;
            '') break ;;
        esac
    done

    # Exit alternate screen buffer, show cursor
    printf '\033[?25h\033[?1049l' >/dev/tty

    echo "${items[$current]}"
}

UI_INTERACTIVE_MODE=false

ui_interactive_start() {
    UI_INTERACTIVE_MODE=true
    tput sc 2>/dev/null || true
}

ui_interactive_end() {
    UI_INTERACTIVE_MODE=false
}

ui_box() {
    local title="$1"
    shift
    local -a lines=("$@")
    local max_width=${#title}
    for line in "${lines[@]}"; do
        if [[ ${#line} -gt $max_width ]]; then
            max_width=${#line}
        fi
    done
    max_width=$((max_width + 4))
    echo "╭─ ${COLOR_BOLD}$title${COLOR_RESET} $(printf '─%.0s' $(seq 1 $((max_width - ${#title} - 4))))╮"
    for line in "${lines[@]}"; do
        printf "│ %-$((max_width - 2))s │\n" "$line"
    done
    echo "╰$(printf '─%.0s' $(seq 1 $((max_width))))╯"
}

# Checklist with conflict detection for patches
# Usage: ui_checklist_with_conflicts "title" target_dir
# Args passed via global arrays: UI_CWC_ITEMS, UI_CWC_TYPES, UI_CWC_PATCH_FILES, UI_CWC_KPROBES_ENABLED
ui_checklist_with_conflicts() {
    local title="$1"
    local target_dir="$2"

    # Arrays passed via globals (bash limitation for array passing)
    local -a items=("${UI_CWC_ITEMS[@]}")
    local -a types=("${UI_CWC_TYPES[@]}")
    local -a patch_files=("${UI_CWC_PATCH_FILES[@]}")
    local kprobes_enabled="${UI_CWC_KPROBES_ENABLED:-false}"

    local -a selected=()
    local -a disabled=()
    local -a conflict_reason=()

    # Helper: check if patch requires manual hooks (incompatible with kprobes)
    _patch_requires_manual_hooks() {
        local patch_file="$1"
        grep -qE '(CONFIG_KSU_KPROBES_HOOK.*n|!defined.*CONFIG_KSU.*KPROBES|ksu_handle_|ksu_.*_hook)' "$patch_file" 2>/dev/null
    }

    # Initialize state for each item
    for ((i=0; i<${#items[@]}; i++)); do
        selected+=("false")
        # Check if patch requires manual hooks and kprobes is enabled
        if [[ "$kprobes_enabled" == "true" && -n "${patch_files[$i]}" ]]; then
            if _patch_requires_manual_hooks "${patch_files[$i]}"; then
                disabled+=("true")
                conflict_reason+=("requires manual hooks (kprobes enabled)")
            else
                disabled+=("false")
                conflict_reason+=("")
            fi
        else
            disabled+=("false")
            conflict_reason+=("")
        fi
    done

    local current=0
    local key
    local num_lines=0  # Track lines printed for cursor movement

    # Helper: check if patch j conflicts with any selected patch
    _check_conflicts_for_item() {
        local idx="$1"

        # Only patches can have conflicts
        [[ "${types[$idx]}" != "patch" ]] && return 1
        [[ -z "${patch_files[$idx]}" ]] && return 1

        local patch_file="${patch_files[$idx]}"
        local files_j=$(grep -E "^(\+\+\+|---) " "$patch_file" 2>/dev/null | \
            sed -E 's#^(\+\+\+|---) (\.?/|[ab]/)?##' | sed 's/\t.*//' | sort -u)

        for ((k=0; k<${#items[@]}; k++)); do
            [[ $k -eq $idx ]] && continue
            [[ "${selected[$k]}" != "true" ]] && continue
            [[ "${types[$k]}" != "patch" ]] && continue
            [[ -z "${patch_files[$k]}" ]] && continue

            local patch_k="${patch_files[$k]}"
            local files_k=$(grep -E "^(\+\+\+|---) " "$patch_k" 2>/dev/null | \
                sed -E 's#^(\+\+\+|---) (\.?/|[ab]/)?##' | sed 's/\t.*//' | sort -u)

            # Check for common files
            local common=$(comm -12 <(echo "$files_j") <(echo "$files_k") 2>/dev/null)
            if [[ -n "$common" ]]; then
                echo "${items[$k]}"
                return 0
            fi
        done
        return 1
    }

    # Helper: recalculate all conflicts
    _recalculate_conflicts() {
        for ((i=0; i<${#items[@]}; i++)); do
            # Skip if already disabled due to kprobes incompatibility
            if [[ "$kprobes_enabled" == "true" && -n "${patch_files[$i]}" ]]; then
                if _patch_requires_manual_hooks "${patch_files[$i]}"; then
                    disabled[$i]="true"
                    conflict_reason[$i]="requires manual hooks (kprobes enabled)"
                    continue
                fi
            fi

            if [[ "${selected[$i]}" == "true" ]]; then
                disabled[$i]="false"
                conflict_reason[$i]=""
                continue
            fi

            local conflicting_with
            conflicting_with=$(_check_conflicts_for_item "$i")
            if [[ $? -eq 0 && -n "$conflicting_with" ]]; then
                disabled[$i]="true"
                conflict_reason[$i]="conflicts with $conflicting_with"
            else
                disabled[$i]="false"
                conflict_reason[$i]=""
            fi
        done
    }

    # Enter alternate screen buffer, hide cursor
    printf '\033[?1049h\033[?25l\033[H' >/dev/tty

    while true; do
        # Move to top-left and clear screen
        printf '\033[H\033[J' >/dev/tty

        printf '%s\n\n' "${COLOR_BOLD}${COLOR_MAGENTA}$title${COLOR_RESET}" >/dev/tty

        for ((i=0; i<${#items[@]}; i++)); do
            local checkbox="☐"
            local color=""
            local suffix=""

            if [[ "${disabled[$i]}" == "true" ]]; then
                checkbox="☒"
                color="${COLOR_GRAY}"
                suffix=" (${conflict_reason[$i]})"
            elif [[ "${selected[$i]}" == "true" ]]; then
                checkbox="☑"
                color="${COLOR_GREEN}"
            fi

            if [[ $i -eq $current ]]; then
                printf '%s\n' "${COLOR_CYAN}▸${COLOR_RESET} ${color}${checkbox} ${items[$i]}${suffix}${COLOR_RESET}" >/dev/tty
            else
                printf '%s\n' "  ${color}${checkbox} ${items[$i]}${suffix}${COLOR_RESET}" >/dev/tty
            fi
        done

        printf '\n%s\n' "${COLOR_GRAY}↑/↓: Navigate  Space: Toggle  Enter: Confirm${COLOR_RESET}" >/dev/tty

        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\x1b')
                IFS= read -rsn2 -t 0.1 key </dev/tty
                case "$key" in
                    '[A') ((current--)); if [[ $current -lt 0 ]]; then current=$((${#items[@]} - 1)); fi ;;
                    '[B') ((current++)); if [[ $current -ge ${#items[@]} ]]; then current=0; fi ;;
                esac
                ;;
            ' ')
                # Only toggle if not disabled
                if [[ "${disabled[$current]}" != "true" ]]; then
                    if [[ "${selected[$current]}" == "true" ]]; then
                        selected[$current]="false"
                    else
                        selected[$current]="true"
                    fi
                    # Recalculate conflicts after toggle
                    _recalculate_conflicts
                fi
                ;;
            '') break ;;
        esac
    done

    # Exit alternate screen buffer, show cursor
    printf '\033[?25h\033[?1049l' >/dev/tty

    local result=()
    for ((i=0; i<${#items[@]}; i++)); do
        if [[ "${selected[$i]}" == "true" ]]; then
            result+=("${items[$i]}")
        fi
    done
    echo "${result[*]}"
}

trap 'ui_spinner_stop; tput cnorm 2>/dev/null || true' EXIT INT TERM
