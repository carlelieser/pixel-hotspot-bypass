#!/usr/bin/env bash

PHB_COMMANDS=(
    "detect:Auto-detect connected Pixel device"
    "setup:Download and setup kernel source"
    "configure:Apply patches to kernel (KernelSU, TTL/HL bypass, etc.)"
    "build:Compile kernel"
    "flash:Flash kernel to device"
    "run:Execute full workflow (setup → configure → build → flash)"
    "completion:Generate shell completion script"
)

PHB_GLOBAL_FLAGS=(
    "-h|--help:Show help message"
    "-v|--verbose:Enable verbose output"
    "-d|--device:Device codename (tegu, tokay, caiman)"
)

PHB_SETUP_FLAGS=(
    "-d|--device:Device codename"
    "-b|--branch:Manifest branch"
    "--skip-sync:Skip repo sync"
    "-h|--help:Show help"
)

PHB_CONFIGURE_FLAGS=(
    "-d|--device:Device codename"
    "--patches:Comma-separated patches (kernelsu,ttl-bypass)"
    "-h|--help:Show help"
)

PHB_BUILD_FLAGS=(
    "-d|--device:Device codename"
    "--lto:LTO mode (none, thin, full)"
    "--clean:Clean build"
    "--auto-expunge:Auto expunge if build fails"
    "-h|--help:Show help"
)

PHB_FLASH_FLAGS=(
    "-d|--device:Device codename"
    "-o|--output-dir:Output directory with images"
    "-h|--help:Show help"
)

PHB_RUN_FLAGS=(
    "-d|--device:Device codename"
    "-b|--branch:Manifest branch"
    "--lto:LTO mode (none, thin, full)"
    "--clean:Clean build"
    "--interactive:Interactive mode with checklists"
    "--skip-setup:Skip setup step"
    "--skip-configure:Skip configure step"
    "--skip-build:Skip build step"
    "--skip-flash:Skip flash step"
    "-h|--help:Show help"
)

PHB_DEVICES=(
    "tegu"
    "tokay"
    "caiman"
)

PHB_LTO_MODES=(
    "none"
    "thin"
    "full"
)

generate_bash_completion() {
    cat <<'EOF'
_phb_completion() {
    local cur prev words cword
    _init_completion || return
    local commands="detect setup configure build flash run completion"
    local global_flags="-h --help -v --verbose -d --device"
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return
    fi
    local command="${words[1]}"
    case "$command" in
        detect)
            COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            ;;
        setup)
            if [[ "$prev" == "-d" || "$prev" == "--device" ]]; then
                COMPREPLY=($(compgen -W "tegu tokay caiman" -- "$cur"))
            elif [[ "$prev" == "-b" || "$prev" == "--branch" ]]; then
                COMPREPLY=()
            else
                COMPREPLY=($(compgen -W "-d --device -b --branch --skip-sync -h --help" -- "$cur"))
            fi
            ;;
        configure)
            if [[ "$prev" == "-d" || "$prev" == "--device" ]]; then
                COMPREPLY=($(compgen -W "tegu tokay caiman" -- "$cur"))
            elif [[ "$prev" == "--patches" ]]; then
                COMPREPLY=($(compgen -W "kernelsu ttl-bypass kernelsu,ttl-bypass" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "-d --device --patches -h --help" -- "$cur"))
            fi
            ;;
        build)
            if [[ "$prev" == "-d" || "$prev" == "--device" ]]; then
                COMPREPLY=($(compgen -W "tegu tokay caiman" -- "$cur"))
            elif [[ "$prev" == "--lto" ]]; then
                COMPREPLY=($(compgen -W "none thin full" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "-d --device --lto --clean --auto-expunge -h --help" -- "$cur"))
            fi
            ;;
        flash)
            if [[ "$prev" == "-d" || "$prev" == "--device" ]]; then
                COMPREPLY=($(compgen -W "tegu tokay caiman" -- "$cur"))
            elif [[ "$prev" == "-o" || "$prev" == "--output-dir" ]]; then
                COMPREPLY=($(compgen -d -- "$cur"))
            else
                COMPREPLY=($(compgen -W "-d --device -o --output-dir -h --help" -- "$cur"))
            fi
            ;;
        run)
            if [[ "$prev" == "-d" || "$prev" == "--device" ]]; then
                COMPREPLY=($(compgen -W "tegu tokay caiman" -- "$cur"))
            elif [[ "$prev" == "-b" || "$prev" == "--branch" ]]; then
                COMPREPLY=()
            elif [[ "$prev" == "--lto" ]]; then
                COMPREPLY=($(compgen -W "none thin full" -- "$cur"))
            else
                local run_flags="-d --device -b --branch --lto --clean --interactive"
                run_flags="$run_flags --skip-setup --skip-configure --skip-build --skip-flash -h --help"
                COMPREPLY=($(compgen -W "$run_flags" -- "$cur"))
            fi
            ;;
        completion)
            COMPREPLY=($(compgen -W "bash zsh" -- "$cur"))
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}
complete -F _phb_completion phb phb.sh
EOF
}

generate_zsh_completion() {
    cat <<'EOF'
#compdef phb phb.sh
_phb() {
    local curcontext="$curcontext" state line
    typeset -A opt_args
    local -a commands
    commands=(
        'detect:Auto-detect connected Pixel device'
        'setup:Download and setup kernel source'
        'configure:Apply patches to kernel (KernelSU, TTL/HL bypass, etc.)'
        'build:Compile kernel'
        'flash:Flash kernel to device'
        'run:Execute full workflow (setup → configure → build → flash)'
        'completion:Generate shell completion script'
    )
    _arguments -C \
        '1: :->command' \
        '*:: :->args'
    case $state in
        command)
            _describe 'command' commands
            ;;
        args)
            case $words[1] in
                detect)
                    _arguments \
                        '(-h --help)'{-h,--help}'[Show help message]'
                    ;;
                setup)
                    _arguments \
                        '(-d --device)'{-d,--device}'[Device codename]:device:(tegu tokay caiman)' \
                        '(-b --branch)'{-b,--branch}'[Manifest branch]:branch:' \
                        '--skip-sync[Skip repo sync]' \
                        '(-h --help)'{-h,--help}'[Show help message]'
                    ;;
                configure)
                    _arguments \
                        '(-d --device)'{-d,--device}'[Device codename]:device:(tegu tokay caiman)' \
                        '--patches[Patches to apply]:patches:(kernelsu ttl-bypass kernelsu,ttl-bypass)' \
                        '(-h --help)'{-h,--help}'[Show help message]'
                    ;;
                build)
                    _arguments \
                        '(-d --device)'{-d,--device}'[Device codename]:device:(tegu tokay caiman)' \
                        '--lto[LTO mode]:lto:(none thin full)' \
                        '--clean[Clean build]' \
                        '--auto-expunge[Auto expunge if build fails]' \
                        '(-h --help)'{-h,--help}'[Show help message]'
                    ;;
                flash)
                    _arguments \
                        '(-d --device)'{-d,--device}'[Device codename]:device:(tegu tokay caiman)' \
                        '(-o --output-dir)'{-o,--output-dir}'[Output directory]:directory:_directories' \
                        '(-h --help)'{-h,--help}'[Show help message]'
                    ;;
                run)
                    _arguments \
                        '(-d --device)'{-d,--device}'[Device codename]:device:(tegu tokay caiman)' \
                        '(-b --branch)'{-b,--branch}'[Manifest branch]:branch:' \
                        '--lto[LTO mode]:lto:(none thin full)' \
                        '--clean[Clean build]' \
                        '--interactive[Interactive mode with checklists]' \
                        '--skip-setup[Skip setup step]' \
                        '--skip-configure[Skip configure step]' \
                        '--skip-build[Skip build step]' \
                        '--skip-flash[Skip flash step]' \
                        '(-h --help)'{-h,--help}'[Show help message]'
                    ;;
                completion)
                    _arguments \
                        '1:shell:(bash zsh)'
                    ;;
            esac
            ;;
    esac
}
_phb "$@"
EOF
}

generate_completion() {
    local shell="$1"
    case "$shell" in
        bash) generate_bash_completion ;;
        zsh) generate_zsh_completion ;;
        *) echo "Error: Unknown shell '$shell'. Use 'bash' or 'zsh'." >&2; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_completion "$@"
fi
