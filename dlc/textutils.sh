# ──────────────────────────────────────────────────────────────────────────────
# BashKernel DLC: textutils.sh  —  Text Processing Utilities
# ──────────────────────────────────────────────────────────────────────────────
# Provides: head, tail, wc, sort, uniq

DLC_NAME="textutils"
DLC_VERSION="1.0"
DLC_DESC="Text processing — head, tail, wc, sort, uniq"

textutils_help() {
    echo "Textutils DLC v$DLC_VERSION"
    echo "  head [n] [file]    Show first n lines (default 10)"
    echo "  tail [n] [file]    Show last n lines (default 10)"
    echo "  wc [file]          Count lines, words, chars"
    echo "  sort [file]        Sort lines alphabetically"
    echo "  uniq [file]        Remove adjacent duplicate lines"
    echo "  All commands read from a file or from a pipe."
}

_read_lines() {
    local path="$1"
    local -n out="$2"
    local cname="${3:-${cmd:-}}"
    if [[ -n "$path" ]]; then
        local inode
        inode=$(_vfs_lookup "$path" 2>/dev/null) || {
            _log_error "$cname: $path: not found"
            return 1
        }
        if [[ "${VFS_TYPE[$inode]}" != "file" ]]; then
            _log_error "$cname: $path: not a file"
            return 1
        fi
        IFS=$'\n' read -rd '' -a out <<< "${VFS_DATA[$inode]:-}" || true
    elif (( PIPE_ACTIVE )); then
        local line
        while IFS= read -r line; do
            out+=("$line")
        done
    else
        _log_error "$cname: missing file or pipe input"
        return 1
    fi
}

cmd_head() {
    local num="${1:-10}"
    local path=""
    if [[ "$num" =~ ^[0-9]+$ ]]; then
        path="${2:-}"
    else
        path="$num"
        num=10
    fi
    local -a lines=()
    _read_lines "$path" lines "head" || return
    local i
    for ((i=0; i<num && i<${#lines[@]}; i++)); do
        echo "${lines[$i]}"
    done
}

cmd_tail() {
    local num="${1:-10}"
    local path=""
    if [[ "$num" =~ ^[0-9]+$ ]]; then
        path="${2:-}"
    else
        path="$num"
        num=10
    fi
    local -a lines=()
    _read_lines "$path" lines "tail" || return
    local start=$(( ${#lines[@]} - num ))
    (( start < 0 )) && start=0
    local i
    for ((i=start; i<${#lines[@]}; i++)); do
        echo "${lines[$i]}"
    done
}

cmd_wc() {
    local path="${1:-}"
    local -a lines=()
    _read_lines "$path" lines "wc" || return
    local line_count=${#lines[@]}
    local word_count=0 char_count=0
    local line
    for line in "${lines[@]}"; do
        local words=()
        IFS=$' \t' read -ra words <<< "$line"
        word_count=$((word_count + ${#words[@]}))
        char_count=$((char_count + ${#line} + 1))
    done
    echo "  $line_count   $word_count  $char_count"
}

cmd_sort() {
    local path="${1:-}"
    local -a lines=()
    _read_lines "$path" lines "sort" || return
    local i j
    for ((i=0; i<${#lines[@]}; i++)); do
        for ((j=i+1; j<${#lines[@]}; j++)); do
            if [[ "${lines[$j]}" < "${lines[$i]}" ]]; then
                local tmp="${lines[$i]}"
                lines[$i]="${lines[$j]}"
                lines[$j]="$tmp"
            fi
        done
    done
    local line
    for line in "${lines[@]}"; do
        echo "$line"
    done
}

cmd_uniq() {
    local path="${1:-}"
    local -a lines=()
    _read_lines "$path" lines "uniq" || return
    local prev=""
    local line
    for line in "${lines[@]}"; do
        [[ "$line" == "$prev" ]] && continue
        echo "$line"
        prev="$line"
    done
}

dlc_register_command "head" "cmd_head" "textutils"
dlc_register_command "tail" "cmd_tail" "textutils"
dlc_register_command "wc"   "cmd_wc"   "textutils"
dlc_register_command "sort" "cmd_sort" "textutils"
dlc_register_command "uniq" "cmd_uniq" "textutils"
