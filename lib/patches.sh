#!/bin/bash
# Patch discovery and conflict detection for PHB
# No metadata files - conflicts detected by analyzing patch contents

PATCHES_DIR="${ROOT_DIR:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/patches"

# Discover all .patch files recursively
discover_patches() {
    find "$PATCHES_DIR" -name "*.patch" -type f 2>/dev/null | sort
}

# Get list of files modified by a patch
get_patch_files() {
    local patch_file="$1"
    # Handle various patch formats: "--- a/file", "--- ./file", "--- file"
    grep -E "^(\+\+\+|---) " "$patch_file" 2>/dev/null | \
        sed -E 's#^(\+\+\+|---) (\.?/|[ab]/)?##' | \
        sed 's/\t.*//' | \
        sort -u
}

# Get short name for display (relative to patches dir)
get_patch_name() {
    local patch_file="$1"
    echo "${patch_file#$PATCHES_DIR/}"
}

# Check if two patches conflict by checking if they can both apply
# Returns 0 if no conflict, 1 if conflict
check_patch_conflict() {
    local patch1="$1"
    local patch2="$2"
    local target_dir="$3"

    # Get files each patch modifies
    local files1=$(get_patch_files "$patch1")
    local files2=$(get_patch_files "$patch2")

    # Find common files
    local common=$(comm -12 <(echo "$files1") <(echo "$files2"))

    # If no common files, no conflict possible
    [[ -z "$common" ]] && return 0

    # Common files exist - try dry-run apply
    cd "$target_dir" || return 1

    # Try applying first patch
    if ! git apply --check "$patch1" &>/dev/null; then
        return 1  # First patch can't apply
    fi

    # Apply first, check second
    git apply "$patch1" &>/dev/null
    local can_apply_second=$?
    if [[ $can_apply_second -eq 0 ]]; then
        can_apply_second=$(git apply --check "$patch2" &>/dev/null; echo $?)
    fi

    # Revert first patch
    git apply -R "$patch1" &>/dev/null

    [[ $can_apply_second -eq 0 ]] && return 0 || return 1
}

# Validate a selection of patches for conflicts
# Args: target_dir patch1 [patch2 ...]
# Returns 0 if valid, 1 if conflicts found
# Outputs conflict info to stderr
validate_patch_selection() {
    local target_dir="$1"
    shift
    local patches=("$@")
    local has_conflict=0

    # Check each pair
    for ((i=0; i<${#patches[@]}; i++)); do
        for ((j=i+1; j<${#patches[@]}; j++)); do
            local p1="${patches[$i]}"
            local p2="${patches[$j]}"

            # Get common files
            local files1=$(get_patch_files "$p1")
            local files2=$(get_patch_files "$p2")
            local common=$(comm -12 <(echo "$files1") <(echo "$files2"))

            if [[ -n "$common" ]]; then
                # They touch same files - check if actually conflicts
                if ! check_patch_conflict "$p1" "$p2" "$target_dir"; then
                    echo "CONFLICT: $(get_patch_name "$p1") <-> $(get_patch_name "$p2")" >&2
                    echo "  Both modify: $common" >&2
                    has_conflict=1
                fi
            fi
        done
    done

    return $has_conflict
}

# Check if a single patch can apply cleanly
# Returns 0 if can apply, 1 if not
can_apply_patch() {
    local patch_file="$1"
    local target_dir="$2"

    cd "$target_dir" || return 1

    # Check if already applied (reverse applies cleanly)
    if git apply --check -R "$patch_file" &>/dev/null; then
        echo "already_applied"
        return 0
    fi

    # Check if can apply forward
    if git apply --check "$patch_file" &>/dev/null; then
        echo "can_apply"
        return 0
    fi

    echo "conflicts"
    return 1
}

# Apply a patch with status reporting
# Returns: 0=applied, 1=failed, 2=already applied, 3=skipped (conflicts)
apply_patch() {
    local patch_file="$1"
    local target_dir="$2"
    local patch_name=$(get_patch_name "$patch_file")

    cd "$target_dir" || return 1

    local status=$(can_apply_patch "$patch_file" "$target_dir")

    case "$status" in
        already_applied)
            return 2
            ;;
        can_apply)
            if git apply "$patch_file" &>/dev/null; then
                return 0
            else
                return 1
            fi
            ;;
        conflicts)
            # Try 3-way merge as fallback
            if git apply --3way "$patch_file" &>/dev/null; then
                return 0
            fi
            return 3
            ;;
    esac

    return 1
}

# Apply multiple patches in order, stopping on first fatal error
# Args: target_dir patch1 [patch2 ...]
apply_patches() {
    local target_dir="$1"
    shift
    local patches=("$@")
    local results=()

    for patch in "${patches[@]}"; do
        local name=$(get_patch_name "$patch")
        apply_patch "$patch" "$target_dir"
        local ret=$?

        case $ret in
            0) results+=("$name:applied") ;;
            1) results+=("$name:failed"); return 1 ;;
            2) results+=("$name:skipped (already applied)") ;;
            3) results+=("$name:skipped (conflicts)") ;;
        esac
    done

    # Output results
    for r in "${results[@]}"; do
        echo "$r"
    done

    return 0
}

# Detect which config changes a patch requires by scanning for CONFIG_ references
detect_required_configs() {
    local patch_file="$1"
    grep -ohE 'CONFIG_[A-Z0-9_]+' "$patch_file" 2>/dev/null | sort -u
}

# Check if patch disables kprobes (requires manual hooks)
patch_requires_manual_hooks() {
    local patch_file="$1"
    # Look for patterns that indicate manual hooks
    grep -qE '(CONFIG_KSU_KPROBES_HOOK.*n|!defined.*CONFIG_KSU.*KPROBES|ksu_handle_|ksu_.*_hook)' "$patch_file" 2>/dev/null
}
