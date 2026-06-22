# ──────────────────────────────────────────────────────────────────────────────
# BashKernel DLC: editor.sh  —  Mini Text Editor
# ──────────────────────────────────────────────────────────────────────────────
# Provides: edit, ed, write
# A simple line-oriented text editor for in-memory files.

DLC_NAME="editor"
DLC_VERSION="1.0"
DLC_DESC="Mini text editor — create and modify VFS files"

editor_help() {
    echo "Editor DLC v$DLC_VERSION"
    echo "  edit <file>     Open file in line editor"
    echo "  ed <file>       Same as edit (shorter)"
    echo "  write <file>    Write lines to file (one per line, EOF to finish)"
    echo "Editor commands (inside edit):"
    echo "  p               Print all lines"
    echo "  n               Print line numbers"
    echo "  l <num>         Print line <num>"
    echo "  i <num> <text>  Insert text before line <num>"
    echo "  a <num> <text>  Append text after line <num>"
    echo "  d <num>         Delete line <num>"
    echo "  w               Save changes"
    echo "  q               Quit (without saving unless w used)"
    echo "  h               Show this help"
}

cmd_edit() {
    local path="${1:-}"
    [[ -z "$path" ]] && { echo "Usage: edit <file>"; return 1; }
    if ! _vfs_lookup "$path" >/dev/null 2>&1; then
        vfs_create "$path" || return 1
    fi
    local inode; inode=$(_vfs_lookup "$path")
    # Read existing content into lines array
    local -a lines=()
    local content="${VFS_DATA[$inode]:-}"
    if [[ -n "$content" ]]; then
        IFS=$'' read -ra lines <<< "$content"
    fi
    local modified=0

    echo "Editing: $path  (${#lines[@]} lines)"
    echo "Type "h" for help, "q" to quit."
    while true; do
        echo "ed:" >  "${#lines[@]}"
        local input=""
        IFS= read -r input || break
        [[ -z "$input" ]] && continue
        local cmd="${input%% *}"
        local rest="${input#* }"
        [[ "$rest" == "$input" ]] && rest=""

        case "$cmd" in
            p|print)
                if (( ${#lines[@]} == 0 )); then
                    echo "(empty)"
                else
                    local i
                    for ((i=0; i<${#lines[@]}; i++)); do
                        echo "${lines[$i]}"
                    done
                fi
                ;;
            n|numbers)
                local i
                for ((i=0; i<${#lines[@]}; i++)); do
                    echo "$((i+1)): ${lines[$i]}"
                done
                ;;
            l|line)
                local num="${rest:-}"
                if [[ -z "$num" ]]; then
                    echo "Usage: l <line-number>"
                elif (( num < 1 || num > ${#lines[@]} )); then
                    echo "Line $num out of range (1-${#lines[@]})"
                else
                    echo "$num: ${lines[$((num-1))]}"
                fi
                ;;
            i|insert)
                local num="${rest%% *}"
                local text="${rest#* }"
                [[ "$text" == "$rest" ]] && text=""
                if [[ -z "$num" ]]; then
                    echo "Usage: i <line-number> <text>"
                elif (( num < 1 || num > ${#lines[@]} + 1 )); then
                    echo "Line $num out of range (1-$(( ${#lines[@]} + 1 )))"
                else
                    lines=("${lines[@]:0:$((num-1))}" "$text" "${lines[@]:$((num-1))}")
                    modified=1
                fi
                ;;
            a|append)
                local num="${rest%% *}"
                local text="${rest#* }"
                [[ "$text" == "$rest" ]] && text=""
                if [[ -z "$num" ]]; then
                    echo "Usage: a <line-number> <text>"
                elif (( num < 0 || num > ${#lines[@]} )); then
                    echo "Line $num out of range (0-${#lines[@]})"
                else
                    lines=("${lines[@]:0:$num}" "$text" "${lines[@]:$num}")
                    modified=1
                fi
                ;;
            d|delete)
                local num="${rest:-}"
                if [[ -z "$num" ]]; then
                    echo "Usage: d <line-number>"
                elif (( num < 1 || num > ${#lines[@]} )); then
                    echo "Line $num out of range (1-${#lines[@]})"
                else
                    lines=("${lines[@]:0:$((num-1))}" "${lines[@]:$num}")
                    modified=1
                fi
                ;;
            w|write|save)
                local new_content=""
                local i
                for ((i=0; i<${#lines[@]}; i++)); do
                    new_content+="${lines[$i]}"$''
                done
                vfs_write "$inode" "$new_content"
                modified=0
                echo "Saved (${#lines[@]} lines)"
                ;;
            q|quit)
                if (( modified )); then
                    echo "Unsaved changes! Use "w" to save or "q" again to force quit."
                    modified=0  # toggle: next q will quit
                    continue
                fi
                echo "Exiting editor."
                break
                ;;
            h|help)
                editor_help
                ;;
            *)
                echo "Unknown editor command: $cmd (type h for help)"
                ;;
        esac
    done
}

cmd_write() {
    local path="${1:-}"
    [[ -z "$path" ]] && { echo "Usage: write <file>"; return 1; }
    if ! _vfs_lookup "$path" >/dev/null 2>&1; then
        vfs_create "$path" || return 1
    fi
    local inode; inode=$(_vfs_lookup "$path")
    local content=""
    echo "Enter lines (empty line to finish):"
    while true; do
        local line=""
        IFS= read -r line || break
        [[ -z "$line" ]] && break
        content+="$line"$''
    done
    vfs_write "$inode" "$content"
    echo "Wrote ${#content} bytes to $path"
}

dlc_register_command "edit" "cmd_edit" "editor"
dlc_register_command "ed"   "cmd_edit" "editor"
dlc_register_command "write" "cmd_write" "editor"
