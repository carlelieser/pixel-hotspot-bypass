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
        selected+=("true")
    done
    local current=0
    local key
    if [[ "$UI_INTERACTIVE_MODE" == "true" ]]; then
        tput rc >/dev/tty 2>/dev/null || true
        tput ed >/dev/tty 2>/dev/null || true
    else
        tput sc >/dev/tty 2>/dev/null || true
    fi
    tput civis >/dev/tty 2>/dev/null || true
    while true; do
        tput rc >/dev/tty 2>/dev/null || true
        tput ed >/dev/tty 2>/dev/null || true
        echo "${COLOR_BOLD}${COLOR_MAGENTA}$title${COLOR_RESET}" >/dev/tty
        echo "" >/dev/tty
        for ((i=0; i<${#items[@]}; i++)); do
            local checkbox="☐"
            local color=""
            if [[ "${selected[$i]}" == "true" ]]; then
                checkbox="☑"
                color="${COLOR_GREEN}"
            fi
            if [[ $i -eq $current ]]; then
                echo "${COLOR_CYAN}▸${COLOR_RESET} ${color}${checkbox} ${items[$i]}${COLOR_RESET}" >/dev/tty
            else
                echo "  ${color}${checkbox} ${items[$i]}${COLOR_RESET}" >/dev/tty
            fi
        done
        echo "" >/dev/tty
        echo "${COLOR_GRAY}↑/↓: Navigate  Space: Toggle  Enter: Confirm${COLOR_RESET}" >/dev/tty
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
    tput cnorm >/dev/tty 2>/dev/null || true
    tput rc >/dev/tty 2>/dev/null || true
    tput ed >/dev/tty 2>/dev/null || true
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
    if [[ "$UI_INTERACTIVE_MODE" == "true" ]]; then
        tput rc >/dev/tty 2>/dev/null || true
        tput ed >/dev/tty 2>/dev/null || true
    else
        tput sc >/dev/tty 2>/dev/null || true
    fi
    tput civis >/dev/tty 2>/dev/null || true
    while true; do
        tput rc >/dev/tty 2>/dev/null || true
        tput ed >/dev/tty 2>/dev/null || true
        echo "${COLOR_BOLD}${COLOR_MAGENTA}$title${COLOR_RESET}" >/dev/tty
        echo "" >/dev/tty
        for ((i=0; i<${#items[@]}; i++)); do
            if [[ $i -eq $current ]]; then
                echo "${COLOR_CYAN}▸${COLOR_RESET} ${COLOR_GREEN}○${COLOR_RESET} ${items[$i]}" >/dev/tty
            else
                echo "  ○ ${items[$i]}" >/dev/tty
            fi
        done
        echo "" >/dev/tty
        echo "${COLOR_GRAY}↑/↓: Navigate  Enter: Select${COLOR_RESET}" >/dev/tty
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
    tput cnorm >/dev/tty 2>/dev/null || true
    tput rc >/dev/tty 2>/dev/null || true
    tput ed >/dev/tty 2>/dev/null || true
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

trap 'ui_spinner_stop; tput cnorm 2>/dev/null || true' EXIT INT TERM
