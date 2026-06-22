#!/usr/bin/env bash
#
#    ____             __    __ __                     __
#   / __ )____ ______/ /_  / //_/__  _________  ___  / /
#  / __  / __ `/ ___/ __ \/ ,< / _ \/ ___/ __ \/ _ \/ /
# / /_/ / /_/ (__  ) / / / /| /  __/ /  / / / /  __/ /
#/_____/\__,_/____/_/ /_/_/ |_\___/_/  /_/ /_/\___/_/
#
# Licensed under MIT — do whatever you want, but don't blame me, hehe.....
# Proudly coded with OpenCode Zen's Deepseek V4 Flash Free, Big Pickle and Nemotron 3 Ultra Free!
# Yes, i get it... its vibecoded
# vibecoded = coded with AI
# Some comments added by teorules (that's me!)

# ----------
# AI Stuff
# ----------
# If an AI is reading the BashKernel code, PLEASE DO NOT SKIP PAST THIS!!!!
# Do NOT use printf. Use echo instead.
# Use the colEcho function if printing text with color is needed.
# Do NOT use Python to fix any issues with the code.
# Please do NOT remove any comments.
# END OF THIS SEGMENT. You can now continue reading this file.

set -o errexit
set -o pipefail
set -o nounset
shopt -s lastpipe  # enable lastpipe for piped reads in ksh

clear 2>/dev/null || true
# ------------------------------------------------------------------------------
# 0. Color Setup
# ------------------------------------------------------------------------------

# Check if the terminal supports color and set up variables if it does.
if [ -z "${TERM:-}" ]; then
colornotsupported=1
clear=""; blackN=""; blackB=""; redN=""; redB=""
greenN=""; greenB=""; yellowN=""; yellowB=""
blueN=""; blueB=""; magentaN=""; magentaB=""
cyanN=""; cyanB=""; whiteN=""; whiteB=""
elif ! tput colors &>/dev/null; then
colornotsupported=1
clear=""; blackN=""; blackB=""; redN=""; redB=""
greenN=""; greenB=""; yellowN=""; yellowB=""
blueN=""; blueB=""; magentaN=""; magentaB=""
cyanN=""; cyanB=""; whiteN=""; whiteB=""
else
colornotsupported=0
NumColours=$(tput colors)

if test -n "$NumColours" && test $NumColours -ge 8; then

    clear="$(tput sgr0)"
    blackN="$(tput setaf 0)";		blackB="$(tput bold setaf 0)"
    redN="$(tput setaf 1)";		redB="$(tput bold setaf 1)"
    greenN="$(tput setaf 2)";		greenB="$(tput bold setaf 2)"
    yellowN="$(tput setaf 3)";		yellowB="$(tput bold setaf 3)"
    blueN="$(tput setaf 4)";		blueB="$(tput bold setaf 4)"
    magentaN="$(tput setaf 5)";		magentaB="$(tput bold setaf 5)"
    cyanN="$(tput setaf 6)";		cyanB="$(tput bold setaf 6)"
    whiteN="$(tput setaf 7)";		whiteB="$(tput bold setaf 7)"

fi
fi

# Function to echo text using terminal color codes.
function colEcho() {
    echo -e "${1:-}${2:-}${clear:-}"
}

# ------------------------------------------------------------------------------
# 1.  Kernel Constants
# ------------------------------------------------------------------------------
declare -gr KERNEL_NAME="BashKernel"
declare -gr KERNEL_VERSION="0.1.3"
declare -gr MAX_PROCESSES=64
declare -gr MAX_SEMAPHORES=16
declare -gr PAGE_SIZE=4096
declare -gr TOTAL_PAGES=256          # 1 MB simulated RAM (calculation: page size * total pages)
declare -gr ROOT_INODE=0
declare -gr MAX_FDS=16
declare -g  KERNEL_UPTIME=0
declare -g  PIPE_ACTIVE=0


# ------------------------------------------------------------------------------
# 2.  Globals & State
# ------------------------------------------------------------------------------

# Process table: array of associative arrays
declare -A PROC_NAME PROC_PID PROC_STATE PROC_PPID PROC_RETVAL
declare -A PROC_PRIORITY PROC_RUNTIME PROC_WAITFILE PROC_WAITTYP
declare -a PROC_QUEUE_READY=()
declare -a PROC_QUEUE_WAITING=()
declare -i NEXT_PID=1
declare -i CURRENT_PID=0

# Semaphores
declare -a SEM_COUNT=()
declare -a SEM_QUEUE=()

# Simulated memory — array of pages, each page is "free" or a PID string
declare -a MEM_PAGES=()
for ((i=0; i<TOTAL_PAGES; i++)); do MEM_PAGES[i]="free"; done

# Virtual File System — in-memory tree
# Each file is stored as a string in VFS_DATA[inode]
declare -A VFS_TYPE=()       # "dir" | "file" | "link" | "pipe"
declare -A VFS_NAME=()       # name
declare -A VFS_PARENT=()     # parent inode
declare -A VFS_CHILDREN=()   # "inode1 inode2 …"  (directories only)
declare -A VFS_DATA=()       # file content     (files only)
declare -A VFS_LINK=()       # target inode     (symlinks only)
declare -A VFS_SIZE=()       # size in bytes
declare -A VFS_MODE=()       # "rwx" string
declare -i NEXT_INODE=1

# Persistent VFS root on the real filesystem
declare -gr VFS_ROOT="$HOME/.bashkernel/fs"
declare -A VFS_REALPATH=()   # inode -> real filesystem path
declare -A VFS_NOPERSIST=()  # inode -> 1 (virtual, don't sync to disk)

# File descriptors per process — we store one global table indexed by
# "PID:FD" because bash can't nest associative arrays easily.
declare -A FD_TABLE=()        # "PID:FD" -> "inode"
declare -A FD_POS=()          # "PID:FD" -> byte-offset

# ------------------------------------------------------------------------------
# 3.  Utility Functions
# ------------------------------------------------------------------------------

_kpanic() {
    local msg="$*"
    colEcho $blueB ":("
    echo
    colEcho $blueB "Your kernel ran into a problem and needs to exit."
    echo
    colEcho $blueB "Error code: $msg"
    exit 1
}

_log() {
    local level="$1"; shift
    echo "[$level] $*" >&2
}

_log_info()  { _log "i"  "$*"; }
_log_warn()  { _log "!"  "$*"; }
_log_error() { _log "X" "$*"; }
_log_success() { _log "√" "$*"; }

# ------------------------------------------------------------------------------
# 5.  Virtual File System
# ------------------------------------------------------------------------------

# Virtual mounts that live in memory only (no disk persistence)
_VFS_IS_VIRTUAL() {
    local p="$1"
    case "$p" in
        /dev/*|/dev|/proc/*|/proc|/sys/*|/sys|/tmp/*|/tmp) return 0 ;;
        *) return 1 ;;
    esac
}

_VFS_REALPATH() {
    local path="$1"
    # Strip trailing slash
    path="${path%/}"
    [[ -z "$path" ]] && path="/"
    echo "${VFS_ROOT}${path}"
}

vfs_init() {
    VFS_TYPE[$ROOT_INODE]="dir"
    VFS_NAME[$ROOT_INODE]="/"
    VFS_PARENT[$ROOT_INODE]="$ROOT_INODE"
    VFS_CHILDREN[$ROOT_INODE]=""
    VFS_MODE[$ROOT_INODE]="rwx"
    VFS_SIZE[$ROOT_INODE]=0
    VFS_REALPATH[$ROOT_INODE]="$VFS_ROOT"
    NEXT_INODE=1

    mkdir -p "$VFS_ROOT"

    local fresh_boot=0
    # Check if we have a persisted filesystem (root has children on disk)
    local existing_dirs
    existing_dirs=$(find "$VFS_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    local existing_files
    existing_files=$(find "$VFS_ROOT" -mindepth 1 -type f 2>/dev/null | wc -l)

    if (( existing_dirs > 0 || existing_files > 0 )); then
        _log_info "Loading persistent filesystem from $VFS_ROOT"
        _vfs_load_from_disk
        fresh_boot=0
    else
        _log_info "Creating fresh filesystem"
        fresh_boot=1
    fi

    # Always create virtual directories (not persisted)
    if [[ "$fresh_boot" == 1 ]] || ! _vfs_lookup "/dev" >/dev/null 2>&1; then
        vfs_mkdir "/dev"
        vfs_create "/dev/null"  && VFS_SIZE[$VFS_LAST_INODE]=0
        vfs_create "/dev/zero"  && VFS_SIZE[$VFS_LAST_INODE]=0
        vfs_create "/dev/random" && VFS_SIZE[$VFS_LAST_INODE]=0
    fi
    if [[ "$fresh_boot" == 1 ]] || ! _vfs_lookup "/proc" >/dev/null 2>&1; then
        vfs_mkdir "/proc"
    fi
    if [[ "$fresh_boot" == 1 ]] || ! _vfs_lookup "/tmp" >/dev/null 2>&1; then
        vfs_mkdir "/tmp"
    fi
    if [[ "$fresh_boot" == 1 ]] || ! _vfs_lookup "/sys" >/dev/null 2>&1; then
        vfs_mkdir "/sys"
        vfs_create "/sys/version"  && vfs_write "$VFS_LAST_INODE" "$KERNEL_VERSION"
        vfs_create "/sys/hostname" && vfs_write "$VFS_LAST_INODE" "bashbook"
        vfs_create "/sys/uptime"   && vfs_write "$VFS_LAST_INODE" "0"
    fi
    if [[ "$fresh_boot" == 1 ]] || ! _vfs_lookup "/home" >/dev/null 2>&1; then
        vfs_mkdir "/home"
    fi

}

_vfs_build_path() {
    local inode="$1"
    local parts=()
    while (( inode != ROOT_INODE )); do
        parts=("${VFS_NAME[$inode]}" "${parts[@]}")
        inode="${VFS_PARENT[$inode]}"
    done
    local path="/"
    local p
    for p in "${parts[@]}"; do path+="$p/"; done
    path="${path%/}"
    [[ -z "$path" ]] && path="/"
    echo "$path"
}

_vfs_load_from_disk() {
    # Walk the real filesystem tree and rebuild in-memory VFS
    # We temporarily suppress persistence to avoid double-writes
    local VFS_LOADING=1

    # Use find to discover all files and directories
    local item
    while IFS= read -r -d '' item; do
        local rel="${item#$VFS_ROOT}"
        [[ -z "$rel" ]] && rel="/"
        local typ
        if [[ -d "$item" ]]; then
            # Check if already exists in VFS
            if _vfs_lookup "$rel" >/dev/null 2>&1; then continue; fi
            vfs_mkdir "$rel"
            local inode; inode=$(_vfs_lookup "$rel")
            VFS_REALPATH[$inode]="$item"
        fi
    done < <(find "$VFS_ROOT" -mindepth 1 -type d -print0 2>/dev/null)

    while IFS= read -r -d '' item; do
        local rel="${item#$VFS_ROOT}"
        [[ -z "$rel" ]] && continue
        if [[ -f "$item" ]]; then
            if _vfs_lookup "$rel" >/dev/null 2>&1; then continue; fi
            vfs_create "$rel"
            local inode; inode=$(_vfs_lookup "$rel")
            VFS_REALPATH[$inode]="$item"
            local content
            content=$(cat "$item" 2>/dev/null) || content=""
            VFS_DATA[$inode]="$content"
            VFS_SIZE[$inode]=${#content}
        fi
    done < <(find "$VFS_ROOT" -mindepth 1 -type f -print0 2>/dev/null)

    # Load metadata
    # Find the highest allocated inode and set NEXT_INODE past it
    local max_inode=0
    local inode
    for inode in "${!VFS_TYPE[@]}"; do
        (( inode > max_inode )) && max_inode=$inode
    done
    NEXT_INODE=$((max_inode + 1))

    unset VFS_LOADING
}

_vfs_lookup() {
    local path="$1"
    local follow="${2:-1}"  # follow symlinks by default

    # Normalise: collapse //, trailing /
    [[ "$path" != /* ]] && _kpanic "ABSOLUTE_PATH_REQUIRED" # "absolute path required, got '$path'"
    local normalized=""
    local segment=""
    local i
    for ((i=0; i<${#path}; i++)); do
        local c="${path:$i:1}"
        if [[ "$c" == "/" ]]; then
            if [[ -z "$segment" ]]; then continue; fi
            normalized+="/$segment"
            segment=""
        else
            segment+="$c"
        fi
    done
    [[ -n "$segment" ]] && normalized+="/$segment"
    [[ -z "$normalized" ]] && normalized="/"

    IFS='/' read -ra parts <<< "$normalized"
    local inode="$ROOT_INODE"
    for part in "${parts[@]}"; do
        [[ -z "$part" ]] && continue
        local found=-1
        local child=""
        for child in ${VFS_CHILDREN[$inode]}; do
            if [[ "${VFS_NAME[$child]}" == "$part" ]]; then
                found=$child
                break
            fi
        done
        if [[ $found -eq -1 ]]; then
            echo ""; return 1
        fi
        inode=$found
        # Follow symlinks if requested
        if [[ "${VFS_TYPE[$inode]}" == "link" ]] && (( follow )); then
            inode=${VFS_LINK[$inode]}
        fi
    done
    echo "$inode"
    return 0
}

_vfs_dirname() {
    local p="$1"
    if [[ "$p" == "/" ]]; then echo "/"; return; fi
    local stripped="${p%/}"
    local dir="${stripped%/*}"
    [[ "$dir" == "$stripped" ]] && dir="/"
    [[ -z "$dir" ]] && dir="/"
    echo "$dir"
}

_vfs_basename() {
    local p="$1"
    local stripped="${p%/}"
    echo "${stripped##*/}"
}

vfs_mkdir() {
    local path="$1"
    local parent_path; parent_path=$(_vfs_dirname "$path")
    local name; name=$(_vfs_basename "$path")
    local parent_inode
    parent_inode=$(_vfs_lookup "$parent_path") || {
        _log_error "mkdir: parent '$parent_path' not found"
        return 1
    }
    local inode=$NEXT_INODE
    ((NEXT_INODE++))
    VFS_TYPE[$inode]="dir"
    VFS_NAME[$inode]="$name"
    VFS_PARENT[$inode]="$parent_inode"
    VFS_CHILDREN[$inode]=""
    VFS_MODE[$inode]="rwx"
    VFS_SIZE[$inode]=0
    VFS_CHILDREN[$parent_inode]+=" $inode"
    VFS_REALPATH[$inode]=$(_VFS_REALPATH "$path")

    if _VFS_IS_VIRTUAL "$path"; then
        VFS_NOPERSIST[$inode]=1
    fi

    # Persist to real filesystem (skip virtual mounts and during loading)
    if [[ -z "${VFS_LOADING:-}" ]] && ! _VFS_IS_VIRTUAL "$path"; then
        mkdir -p "$VFS_ROOT${path}"
    fi
}

vfs_create() {
    local path="$1"
    local mode="${2:-rw-}"
    local parent_path; parent_path=$(_vfs_dirname "$path")
    local name; name=$(_vfs_basename "$path")
    local parent_inode
    parent_inode=$(_vfs_lookup "$parent_path") || {
        _log_error "create: parent '$parent_path' not found"
        return 1
    }
    local inode=$NEXT_INODE
    ((NEXT_INODE++))
    VFS_TYPE[$inode]="file"
    VFS_NAME[$inode]="$name"
    VFS_PARENT[$inode]="$parent_inode"
    VFS_DATA[$inode]=""
    VFS_MODE[$inode]="$mode"
    VFS_SIZE[$inode]=0
    VFS_CHILDREN[$parent_inode]+=" $inode"
    VFS_REALPATH[$inode]=$(_VFS_REALPATH "$path")
    VFS_LAST_INODE=$inode

    if _VFS_IS_VIRTUAL "$path"; then
        VFS_NOPERSIST[$inode]=1
    fi

    # Persist to real filesystem
    if [[ -z "${VFS_LOADING:-}" ]] && ! _VFS_IS_VIRTUAL "$path"; then
        local real="$VFS_ROOT${path}"
        mkdir -p "$(dirname "$real")"
        touch "$real" 2>/dev/null || true
    fi
}

vfs_write() {
    local inode="$1"
    local data="$2"
    VFS_DATA[$inode]="$data"
    VFS_SIZE[$inode]=${#data}

    # Persist to real filesystem
    if [[ -z "${VFS_LOADING:-}" ]] && [[ -z "${VFS_NOPERSIST[$inode]:-}" ]]; then
        local real="${VFS_REALPATH[$inode]:-}"
        if [[ -n "$real" ]]; then
            mkdir -p "$(dirname "$real")"
            echo "$data" > "$real" 2>/dev/null || true
        fi
    fi
}

vfs_read() {
    local inode="$1"
    echo "${VFS_DATA[$inode]}"
}

vfs_delete() {
    local path="$1"
    local parent_path; parent_path=$(_vfs_dirname "$path")
    local name; name=$(_vfs_basename "$path")
    local parent_inode
    parent_inode=$(_vfs_lookup "$parent_path") || return 1
    local target
    target=$(_vfs_lookup "$path") || return 1
    local no_persist="${VFS_NOPERSIST[$target]:-0}"

    # Remove from parent's children list
    local new_children=""
    local child
    for child in ${VFS_CHILDREN[$parent_inode]}; do
        [[ "$child" != "$target" ]] && new_children+=" $child"
    done
    VFS_CHILDREN[$parent_inode]="$new_children"

    # If directory, recursively delete children
    if [[ "${VFS_TYPE[$target]}" == "dir" ]]; then
        for child in ${VFS_CHILDREN[$target]}; do
            vfs_delete_by_inode "$child"
        done
    fi

    # Delete from real filesystem
    if [[ -z "${VFS_LOADING:-}" ]] && (( ! no_persist )); then
        local real="${VFS_REALPATH[$target]:-}"
        if [[ -n "$real" && -e "$real" ]]; then
            if [[ "${VFS_TYPE[$target]}" == "dir" ]]; then
                rm -rf "$real" 2>/dev/null || true
            else
                rm -f "$real" 2>/dev/null || true
            fi
        fi
    fi

    unset VFS_TYPE[$target] VFS_NAME[$target] VFS_PARENT[$target]
    unset VFS_CHILDREN[$target] VFS_DATA[$target] VFS_LINK[$target]
    unset VFS_SIZE[$target] VFS_MODE[$target]
    unset VFS_REALPATH[$target] VFS_NOPERSIST[$target]
}

vfs_delete_by_inode() {
    local target="$1"
    local no_persist="${VFS_NOPERSIST[$target]:-0}"

    if [[ -z "${VFS_LOADING:-}" ]] && (( ! no_persist )); then
        local real="${VFS_REALPATH[$target]:-}"
        if [[ -n "$real" && -e "$real" ]]; then
            if [[ "${VFS_TYPE[$target]}" == "dir" ]]; then
                rm -rf "$real" 2>/dev/null || true
            else
                rm -f "$real" 2>/dev/null || true
            fi
        fi
    fi

    unset VFS_TYPE[$target] VFS_NAME[$target] VFS_PARENT[$target]
    unset VFS_CHILDREN[$target] VFS_DATA[$target] VFS_LINK[$target]
    unset VFS_SIZE[$target] VFS_MODE[$target]
    unset VFS_REALPATH[$target] VFS_NOPERSIST[$target]
}

vfs_list() {
    local path="$1"
    local inode
    inode=$(_vfs_lookup "$path") || {
        _log_error "ls: '$path' not found"
        return
    }
    if [[ "${VFS_TYPE[$inode]}" != "dir" ]]; then
        echo "${VFS_NAME[$inode]}"
        return
    fi
    local child
    for child in ${VFS_CHILDREN[$inode]}; do
        local typ="${VFS_TYPE[$child]}"
        local name="${VFS_NAME[$child]}"
        local size="${VFS_SIZE[$child]}"
        local mode="${VFS_MODE[$child]}"
        case "$typ" in
            dir)  echo "d${mode} - ${name}" ;;
            file) echo "- ${mode} ${size} ${name}" ;;
            link) echo "l${mode} - ${name} -> ${VFS_NAME[${VFS_LINK[$child]}]}" ;;
            pipe) echo "p${mode} - ${name}" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5.  Process Manager
# ------------------------------------------------------------------------------

proc_init() {
    # Create the idle process (PID 0)
    PROC_PID[0]=0
    PROC_NAME[0]="idle"
    PROC_STATE[0]="idle"
    PROC_PPID[0]=0
    PROC_RETVAL[0]=""
    PROC_PRIORITY[0]=0
    PROC_RUNTIME[0]=0
    PROC_WAITFILE[0]=""
    PROC_WAITTYP[0]=""

    # Create init process (PID 1)
    proc_create "init" 0
    PROC_STATE[1]="ready"
    PROC_QUEUE_READY+=(1)
}

proc_create() {
    local name="$1"
    local ppid="$2"
    local pid=$NEXT_PID
    NEXT_PID=$((NEXT_PID+1))
    PROC_PID[$pid]=$pid
    PROC_NAME[$pid]="$name"
    PROC_STATE[$pid]="ready"
    PROC_PPID[$pid]=$ppid
    PROC_RETVAL[$pid]=""
    PROC_PRIORITY[$pid]=1
    PROC_RUNTIME[$pid]=0
    PROC_WAITFILE[$pid]=""
    PROC_WAITTYP[$pid]=""
    echo "$pid"
}

proc_schedule() {
    # Simple round-robin: move current to end, pick next
    if (( ${#PROC_QUEUE_READY[@]} == 0 )); then
        CURRENT_PID=0
        return
    fi

    # If current process is still ready, rotate it
    local state="${PROC_STATE[$CURRENT_PID]}"
    if [[ "$state" == "ready" ]]; then
        # dequeue and re-enqueue current
        local newq=()
        local seen=0
        local p
        for p in "${PROC_QUEUE_READY[@]}"; do
            if [[ "$p" == "$CURRENT_PID" && $seen -eq 0 ]]; then
                seen=1; continue
            fi
            newq+=("$p")
        done
        newq+=("$CURRENT_PID")
        PROC_QUEUE_READY=("${newq[@]}")
    fi

    # Pick first ready process
    if (( ${#PROC_QUEUE_READY[@]} > 0 )); then
        CURRENT_PID="${PROC_QUEUE_READY[0]}"
        PROC_QUEUE_READY=("${PROC_QUEUE_READY[@]:1}")
    else
        CURRENT_PID=0
    fi
}

proc_exit() {
    local pid="$1"
    local retval="${2:-0}"
    PROC_RETVAL[$pid]="$retval"
    PROC_STATE[$pid]="zombie"

    # Remove from ready queue if present
    local newq=()
    local p
    for p in "${PROC_QUEUE_READY[@]}"; do
        [[ "$p" != "$pid" ]] && newq+=("$p")
    done
    PROC_QUEUE_READY=("${newq[@]}")

    # Wake up parent if waiting
    local ppid="${PROC_PPID[$pid]}"
    if [[ "${PROC_WAITTYP[$ppid]}" == "pid:$pid" ]]; then
        PROC_STATE[$ppid]="ready"
        PROC_QUEUE_READY+=("$ppid")
        PROC_WAITTYP[$ppid]=""
    fi
}

proc_wait() {
    local pid="$1"
    local child="$2"
    local target="${child:-.}"
    if [[ "$target" == "." ]]; then
        # Wait for any child
        PROC_WAITTYP[$pid]="any"
    else
        PROC_WAITTYP[$pid]="pid:$target"
    fi
    PROC_STATE[$pid]="waiting"
}

proc_kill() {
    local pid="$1"
    local sig="${2:-TERM}"
    local state="${PROC_STATE[$pid]}"
    case "$state" in
        idle|zombie)
            _log_warn "kill: cannot kill process $pid (state=$state)"
            return 1
            ;;
        ready)
            proc_exit "$pid" 9
            ;;
        waiting)
            proc_exit "$pid" 9
            ;;
        running)
            proc_exit "$pid" 9
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 6.  Memory Manager (Simulated Paging)
# ------------------------------------------------------------------------------

mem_init() {
    for ((i=0; i<TOTAL_PAGES; i++)); do
        MEM_PAGES[i]="free"
    done
}

mem_alloc() {
    local pid="$1"
    local count="${2:-1}"
    local allocated=()
    local i
    for ((i=0; i<TOTAL_PAGES && ${#allocated[@]} < count; i++)); do
        if [[ "${MEM_PAGES[$i]}" == "free" ]]; then
            MEM_PAGES[i]="$pid"
            allocated+=("$i")
        fi
    done
    if (( ${#allocated[@]} < count )); then
        # Rollback
        local page
        for page in "${allocated[@]}"; do
            MEM_PAGES[page]="free"
        done
        _log_error "out of memory (requested $count pages, got ${#allocated[@]})"
        return 1
    fi
    echo "${allocated[*]}"
}

mem_free() {
    local pid="$1"
    local i
    for ((i=0; i<TOTAL_PAGES; i++)); do
        if [[ "${MEM_PAGES[$i]}" == "$pid" ]]; then
            MEM_PAGES[i]="free"
        fi
    done
}

mem_status() {
    local free=0 used=0
    local page
    for page in "${MEM_PAGES[@]}"; do
        if [[ "$page" == "free" ]]; then
            free=$((free+1))
        else
            used=$((used+1))
        fi
    done
    echo "Memory: $free/$TOTAL_PAGES pages free ($(( used * 100 / TOTAL_PAGES ))% used)"
}

# ------------------------------------------------------------------------------
# 7.  Semaphores
# ------------------------------------------------------------------------------

sem_init() {
    local id="$1"
    local count="${2:-1}"
    SEM_COUNT[$id]=$count
    SEM_QUEUE[$id]=""
}

sem_wait() {
    local id="$1"
    local pid="$2"
    if (( SEM_COUNT[$id] > 0 )); then
        SEM_COUNT[$id]=$((SEM_COUNT[$id]-1))
    else
        SEM_QUEUE[$id]+=" $pid"
        PROC_STATE[$pid]="waiting"
    fi
}

sem_signal() {
    local id="$1"
    SEM_COUNT[$id]=$((SEM_COUNT[$id]+1))
    # Wake up first waiter
    local queue="${SEM_QUEUE[$id]}"
    if [[ -n "$queue" ]]; then
        local first="${queue%% *}"
        local rest="${queue#* }"
        SEM_QUEUE[$id]="$rest"
        PROC_STATE[$first]="ready"
        PROC_QUEUE_READY+=("$first")
    fi
}

# ------------------------------------------------------------------------------
# 8.  System Calls
# ------------------------------------------------------------------------------

sys_open() {
    local pid="$1"
    local path="$2"
    local fd="$3"
    local inode
    inode=$(_vfs_lookup "$path") || {
        vfs_create "$path" || return 1
        inode=$VFS_LAST_INODE
    }
    FD_TABLE["$pid:$fd"]="$inode"
    FD_POS["$pid:$fd"]=0
}

sys_read() {
    local pid="$1"
    local fd="$2"
    local inode="${FD_TABLE[$pid:$fd]}"
    [[ -z "$inode" ]] && return 1
    vfs_read "$inode"
}

sys_write() {
    local pid="$1"
    local fd="$2"
    local data="$3"
    local inode="${FD_TABLE[$pid:$fd]}"
    [[ -z "$inode" ]] && return 1
    vfs_write "$inode" "$data"
}

sys_close() {
    local pid="$1"
    local fd="$2"
    unset FD_TABLE["$pid:$fd"]
    unset FD_POS["$pid:$fd"]
}

sys_fork() {
    local ppid="$1"
    local child_pid
    child_pid=$(proc_create "child_of_${PROC_NAME[$ppid]}" "$ppid")
    echo "$child_pid"
}

sys_exec() {
    local pid="$1"
    local name="${2:-}"
    [[ -n "$name" ]] && PROC_NAME[$pid]="$name"
}

sys_ps() {
    echo "PID    NAME       STATE    PPID   PRI    RUNTIME"
    local pid
    for pid in "${!PROC_PID[@]}"; do
        echo "${PROC_PID[$pid]}  ${PROC_NAME[$pid]}  ${PROC_STATE[$pid]}  ${PROC_PPID[$pid]}  ${PROC_PRIORITY[$pid]}  ${PROC_RUNTIME[$pid]}"
    done
}

# ------------------------------------------------------------------------------
# 9.  DLC Manager — Loadable Extension Packages
# ------------------------------------------------------------------------------

declare -a DLC_AVAILABLE=()
declare -a DLC_LOADED=()
declare -A DLC_VERS=()
declare -A DLC_DESC=()
declare -A DLC_COMMANDS=()
declare -A DLC_COMMAND_SRC=()   # "command" -> "dlc_name"
declare -gr DLC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dlc"

dlc_scan() {
    DLC_AVAILABLE=()
    local f
    for f in "$DLC_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local name; name=$(basename "$f" .sh)
        DLC_AVAILABLE+=("$name")
    done
}

dlc_info() {
    local name="$1"
    echo "DLC: $name"
    if [[ " ${DLC_LOADED[*]} " == *" $name "* ]]; then
        echo "  Status:  loaded"
    else
        echo "  Status:  available"
    fi
    echo "  Version: ${DLC_VERS[$name]:-?}"
    echo "  Description: ${DLC_DESC[$name]:-(none)}"
}

dlc_help() {
    local name="$1"
    if [[ -z "$name" ]]; then
        _log_error "dlc help: usage: dlc help <name>"
        return 1
    fi
    local func="${name}_help"
    if declare -f "$func" >/dev/null; then
        "$func"
    else
        _log_error "dlc '$name' has no help function"
    fi
}

dlc_load() {
    local name="$1"
    [[ -z "$name" ]] && { _log_error "dlc: usage: dlc load <name>"; return 1; }

    # Load all available DLCs
    if [[ "$name" == "all" ]]; then
        dlc_scan
        if (( ${#DLC_AVAILABLE[@]} == 0 )); then
            _log_warn "dlc: no packages found to load"
            return 0
        fi
        local loaded=0 skipped=0
        local d
        for d in "${DLC_AVAILABLE[@]}"; do
            if [[ " ${DLC_LOADED[*]} " == *" $d "* ]]; then
                skipped=$((skipped+1))
                continue
            fi
            if dlc_load_one "$d"; then
                loaded=$((loaded+1))
            fi
        done
        _log_info "dlc: loaded $loaded package(s), $skipped already loaded"
        return 0
    fi

    dlc_load_one "$name"
}

dlc_load_one() {
    local name="$1"
    if [[ " ${DLC_LOADED[*]} " == *" $name "* ]]; then
        _log_warn "dlc '$name' is already loaded"
        return 0
    fi
    local path="$DLC_DIR/$name.sh"
    if [[ ! -f "$path" ]]; then
        _log_error "dlc: '$name' not found in $DLC_DIR"
        return 1
    fi
    # Source the DLC — it should register itself
    source "$path"
    # DLC should have set DLC_NAME, DLC_VERSION, DLC_DESC
    # and called dlc_register_commands with its prefix
    if [[ -z "${DLC_NAME:-}" ]]; then
        _log_warn "dlc: '$name' did not set DLC_NAME — using filename"
        DLC_NAME="$name"
    fi
    DLC_VERS[$name]="${DLC_VERSION:-1.0}"
    DLC_DESC[$name]="${DLC_DESC:-}"
    DLC_LOADED+=("$name")
    _log_info "dlc '$name' v${DLC_VERS[$name]} loaded"
}

dlc_unload() {
    local name="$1"
    [[ -z "$name" ]] && { _log_error "dlc: usage: dlc unload <name>"; return 1; }

    # Unload all loaded DLCs
    if [[ "$name" == "all" ]]; then
        if (( ${#DLC_LOADED[@]} == 0 )); then
            _log_warn "dlc: no packages loaded"
            return 0
        fi
        local unloaded=0
        local d
        # Iterate backwards to avoid index shift issues
        local idx
        for (( idx=${#DLC_LOADED[@]}-1; idx>=0; idx-- )); do
            if dlc_unload_one "${DLC_LOADED[$idx]}"; then
                unloaded=$((unloaded+1))
            fi
        done
        _log_info "dlc: unloaded $unloaded package(s)"
        return 0
    fi

    dlc_unload_one "$name"
}

dlc_unload_one() {
    local name="$1"
    # Remove all commands registered by this DLC
    local cmd
    for cmd in "${!DLC_COMMAND_SRC[@]}"; do
        if [[ "${DLC_COMMAND_SRC[$cmd]}" == "$name" ]]; then
            unset DLC_COMMANDS[$cmd]
            unset DLC_COMMAND_SRC[$cmd]
        fi
    done
    # Remove from loaded list
    local newlist=()
    local d
    for d in "${DLC_LOADED[@]}"; do
        [[ "$d" != "$name" ]] && newlist+=("$d")
    done
    DLC_LOADED=("${newlist[@]}")
    unset DLC_VERS[$name]
    unset DLC_DESC[$name]
    _log_info "dlc '$name' unloaded"
}

dlc_list() {
    local opt="$1"
    if [[ "$opt" == "--long" || "$opt" == "-l" ]]; then
        echo "NAME             VERSION   STATUS     DESCRIPTION"
        local d
        for d in "${DLC_AVAILABLE[@]}"; do
            local status
            if [[ " ${DLC_LOADED[*]} " == *" $d "* ]]; then
                status="loaded"
            else
                status="available"
            fi
            echo "$d  ${DLC_VERS[$d]:-?}  $status  ${DLC_DESC[$d]:-}"
        done
    else
        echo 'Available DLCs:'
        if [[ " ${DLC_AVAILABLE[*]} " == "  " ]]; then echo " (none found in $DLC_DIR)"; fi
        echo ""
        local d
        for d in "${DLC_AVAILABLE[@]}"; do
            local mark=" "
            [[ " ${DLC_LOADED[*]} " == *" $d "* ]] && mark="*"
            echo "  ${mark}${d}"
        done
        [[ ${#DLC_AVAILABLE[@]} -gt 0 ]] && echo "  (* = loaded)"
    fi
}

dlc_register_command() {
    local cmd="$1"
    local handler="$2"
    local dlc_name="$3"
    DLC_COMMANDS[$cmd]="$handler"
    DLC_COMMAND_SRC[$cmd]="$dlc_name"
}

dlc_dispatch() {
    local cmd="$1"
    shift
    local handler="${DLC_COMMANDS[$cmd]:-}"
    if [[ -n "$handler" ]]; then
        "$handler" "$@"
        return $?
    fi
    return 1
}

# ------------------------------------------------------------------------------
# 10. Built-in Commands (the "init" process shell)
# ------------------------------------------------------------------------------

cmd_help() {
    cat <<'EOF'
BashKernel v0.1 — Built-in Commands
-------------------------------------
  help        Show this help
  ps          List processes
  mem         Show memory status
  ls [path]   List directory contents
  cat [file]  Show file contents (reads pipe if no file given)
  grep <pat>  Filter piped input by pattern
  echo >file <text>  Write text to file
  mkdir <dir> Create directory
  rm <path>   Remove file or directory
  touch <file> Create empty file
  uptime      Show kernel uptime
  uname       Print kernel name
  fork        Fork a child process
  exec <name> Rename current process
  kill <pid>  Kill a process
  wait <pid>  Wait for a child
  panic       Trigger kernel panic
  reboot      Reboot the kernel
  dmesg       Show kernel logs
  free        Show info about free/memory
  df          Show filesystem info
  clear       Clear the screen
  dlc <sub>   Manage DLC packages (list/load/unload/info/scan)
  exit        Exit the kernel shell
  ---
  Pipes are supported:  ls / | grep dev  |  cat
EOF
}

cmd_uname() { echo "${KERNEL_NAME} ${KERNEL_VERSION}"; }

cmd_uptime() { echo "up $KERNEL_UPTIME seconds"; }

cmd_free() {
    mem_status
    local total=$((TOTAL_PAGES * PAGE_SIZE))
    local used=0
    local page
    for page in "${MEM_PAGES[@]}"; do
        [[ "$page" != "free" ]] && used=$((used+1))
    done
    local free=$((TOTAL_PAGES - used))
    echo "  total     used      free"
    echo "  Mem:      ${total}      $((used*PAGE_SIZE))      $((free*PAGE_SIZE))"
}

cmd_df() {
    local used_pages=$(( TOTAL_PAGES - $(echo "${MEM_PAGES[@]}" | grep -c '^free$') ))
    local free_pages=$(( $(echo "${MEM_PAGES[@]}" | grep -c '^free$') ))
    echo "Filesystem           1K-blocks       Used      Avail Mount"
    echo "VFS_ROOT             $((TOTAL_PAGES*4))          $(( used_pages * 4 ))        $(( free_pages * 4 )) (bashfs)"
}

cmd_dmesg() { :; }  # logs go to stderr already

cmd_grep() {
    local pattern="$1"
    if [[ -z "$pattern" ]]; then
        _log_error "grep: usage: <command> | grep <pattern>"
        return
    fi
    if (( ! PIPE_ACTIVE )); then
        _log_error "grep: no piped input"
        return
    fi
    while IFS= read -r line; do
        if [[ "$line" == *"$pattern"* ]]; then
            echo "$line"
        fi
    done
}

cmd_cat() {
    local path="$1"
    if [[ -z "$path" ]]; then
        if (( PIPE_ACTIVE )); then
            cat
            return
        fi
        _log_error "cat: no file specified"
        return
    fi
    local inode
    inode=$(_vfs_lookup "$path") || {
        _log_error "cat: $path: not found"
        return
    }
    if [[ "${VFS_TYPE[$inode]}" != "file" ]]; then
        _log_error "cat: $path: is a ${VFS_TYPE[$inode]}"
        return
    fi
    echo "${VFS_DATA[$inode]:-}"
}

cmd_echo_write() {
    local path="$1"; shift
    local data="$*"
    local inode
    inode=$(_vfs_lookup "$path") || {
        vfs_create "$path" || return
        inode=$VFS_LAST_INODE
    }
    vfs_write "$inode" "$data"
}

cmd_touch() {
    local path="$1"
    local inode
    inode=$(_vfs_lookup "$path") || {
        vfs_create "$path"
    }
}

cmd_panic() { _kpanic "MANUALLY_TRIGGERED"; }

cmd_reboot() {
    _log_info "REBOOT: shutting down all processes..."
    local pid
    for pid in "${!PROC_PID[@]}"; do
        [[ "$pid" -gt 1 ]] && proc_exit "$pid" 0
    done
    _log_info "REBOOT: restarting init..."
    PROC_STATE[1]="ready"
    PROC_QUEUE_READY=(1)
    CURRENT_PID=1
}

# ------------------------------------------------------------------------------
# 11. Kernel Shell (REPL)
# ------------------------------------------------------------------------------

ksh_prompt() {
    echo -ne "\033[1;32m${KERNEL_NAME}\033[0m:\033[1;34m~\033[0m$ "
}

ksh_execute_pipe() {
    local line="$1"
    local stages=()
    IFS='|' read -ra stages <<< "$line"
    local prev_output=""
    local i
    for ((i=0; i<${#stages[@]}; i++)); do
        local cmd_text="${stages[$i]}"
        cmd_text="${cmd_text## }"
        cmd_text="${cmd_text%% }"
        [[ -z "$cmd_text" ]] && continue
        if (( i < ${#stages[@]} - 1 )); then
            prev_output=$(ksh_execute "$cmd_text" 2>/dev/null) || true
        else
            if [[ -n "$prev_output" ]]; then
                PIPE_ACTIVE=1
                echo "$prev_output" | ksh_execute "$cmd_text"
                PIPE_ACTIVE=0
            else
                ksh_execute "$cmd_text"
            fi
        fi
    done
}

ksh_execute() {
    local line="$1"
    [[ -z "$line" || "$line" == \#* ]] && return

    # Handle pipes
    if [[ "$line" == *\|* ]]; then
        ksh_execute_pipe "$line"
        return $?
    fi

    # Parse command and arguments using arrays
    local -a args=()
    IFS=$' \t' read -ra args <<< "$line"
    local cmd="${args[0]:-}"
    [[ -z "$cmd" ]] && return

    case "$cmd" in
        help)     cmd_help ;;
        ps)       sys_ps ;;
        mem|memory) cmd_free ;;
        free)     cmd_free ;;
        df)       cmd_df ;;
        ls)       vfs_list "${args[1]:-/}" ;;
        cat)      cmd_cat "${args[1]:-}" ;;
        grep)     cmd_grep "${args[1]:-}" ;;
        echo)
            if [[ "${#args[@]}" -ge 3 && "${args[1]}" == ">" ]]; then
                local path="${args[2]}"
                local data="${args[*]:3}"
                cmd_echo_write "$path" "$data"
            else
                echo "${args[*]:1}"
            fi
            ;;
        mkdir)    vfs_mkdir "${args[1]:-}" ;;
        rm)       vfs_delete "${args[1]:-}" ;;
        touch)    cmd_touch "${args[1]:-}" ;;
        uptime)   cmd_uptime ;;
        uname)    cmd_uname ;;
        fork)
            local child
            child=$(sys_fork "$CURRENT_PID")
            _log_info "forked child PID $child"
            ;;
        exec)
            sys_exec "$CURRENT_PID" "${args[1]:-}"
            ;;
        kill)
            local target="${args[1]:-}"
            [[ -n "$target" ]] && proc_kill "$target" || _log_error "kill: usage: kill <pid>"
            ;;
        wait)
            proc_wait "$CURRENT_PID" "${args[1]:-}"
            # Block until we're ready again
            while [[ "${PROC_STATE[$CURRENT_PID]}" == "waiting" ]]; do
                ksh_tick
            done
            ;;
        dmesg)    cmd_dmesg ;;
        panic)    cmd_panic ;;
        reboot)   cmd_reboot ;;
        clear)    clear ;;
        dlc)
            local sub="${args[1]:-}"
            case "$sub" in
                list|ls)  dlc_list "${args[2]:-}" ;;
                load)     dlc_load "${args[2]:-}" ;;
                unload)   dlc_unload "${args[2]:-}" ;;
                info)     dlc_info "${args[2]:-}" ;;
                help)     dlc_help "${args[2]:-}" ;;
                scan)     dlc_scan ;;
                *)        echo "Usage: dlc <list|load|unload|info|help|scan> [name]"
                          echo '  "dlc load all"  loads every available DLC'
                          echo '  "dlc unload all" unloads every loaded DLC' ;;
            esac
            ;;
        exit)     return 1 ;;
        *)
            # Try DLC command dispatch before giving up
            dlc_dispatch "$cmd" "${args[@]:1}" && return 0
            _log_error "unknown command: $cmd (try 'help')"
            ;;
    esac
    return 0
}

# ------------------------------------------------------------------------------
# 12. Kernel Tick / Scheduler
# ------------------------------------------------------------------------------

ksh_tick() {
    # Advance time
    KERNEL_UPTIME=$((KERNEL_UPTIME+1))

    # Run current process for one quantum
    local pid="$CURRENT_PID"
    if (( pid > 0 )); then
        PROC_RUNTIME[$pid]=$((PROC_RUNTIME[$pid]+1))
    fi

    # Check waiting processes: wake up if condition met
    local new_waiting=()
    local p
    for p in "${PROC_QUEUE_WAITING[@]}"; do
        local wtype="${PROC_WAITTYP[$p]}"
        local wake=0
        if [[ "$wtype" == "any" ]]; then
            # Check if any child has exited
            local child
            for child in "${!PROC_PID[@]}"; do
                if [[ "${PROC_PPID[$child]}" == "$p" && "${PROC_STATE[$child]}" == "zombie" ]]; then
                    wake=1
                    break
                fi
            done
        elif [[ "$wtype" == pid:* ]]; then
            local target="${wtype#pid:}"
            if [[ "${PROC_STATE[$target]}" == "zombie" ]]; then
                wake=1
            fi
        fi
        if (( wake )); then
            PROC_STATE[$p]="ready"
            PROC_QUEUE_READY+=("$p")
            PROC_WAITTYP[$p]=""
        else
            new_waiting+=("$p")
        fi
    done
    PROC_QUEUE_WAITING=("${new_waiting[@]}")
}

# ------------------------------------------------------------------------------
# 13. Boot Sequence
# ------------------------------------------------------------------------------

boot_sequence() {
    colEcho $greenB "BashKernel $KERNEL_VERSION"
    colEcho $greenB "A Vibecoded Tiny OS Kernel Written in Bash"

    _log_info "Booting ${KERNEL_NAME} v${KERNEL_VERSION}..."

    if [ "$colornotsupported" = 1 ]; then
    _log_error "Color is not supported in your terminal!"
    fi
    unset colornotsupported
    # Stage 1: Memory initialization
    _log_info "Initializing memory manager... ${TOTAL_PAGES} pages, ${PAGE_SIZE} bytes/page"
    mem_init
    sleep 0.1

    # Stage 2: Virtual file system
    _log_info "Mounting virtual file system (bashfs)..."
    vfs_init
    sleep 0.1

    # Stage 3: Semaphores
    _log_info "Initializing IPC primitives..."
    sem_init 0 1    # console lock
    sem_init 1 5    # pool of resources
    sleep 0.1

    # Stage 4: Process table
    _log_info "Starting process manager..."
    proc_init
    sleep 0.1

    # Stage 5: Scan for DLCs
    _log_info "Scanning for DLC packages..."
    dlc_scan
    local dlc_count=${#DLC_AVAILABLE[@]}
    if (( dlc_count > 0 )); then
        _log_info "Found $dlc_count DLC package(s): ${DLC_AVAILABLE[*]}"
        _log_info "Loading all DLCs, please be patient!"
        dlc_load all
        _log_success "Successfully loaded all DLCs."

    else
        _log_info "No DLC packages found (looked in $DLC_DIR)"
    fi
    sleep 0.1

    _log_success "Boot complete. Starting init (PID 1)..."
    echo ""
}

# ------------------------------------------------------------------------------
# 14. Main Loop
# ------------------------------------------------------------------------------

main() {
    boot_sequence

    CURRENT_PID=1
    PROC_STATE[1]="running"

    while true; do
        # Tick the kernel
        ksh_tick

        # Check if init is still alive
        if [[ "${PROC_STATE[1]}" == "zombie" ]]; then
            _log_error "init has apparently killed itself - goodbye!"
            break
        fi

        # If init is ready, schedule it
        if [[ "${PROC_STATE[1]}" == "ready" || "${PROC_STATE[1]}" == "running" ]]; then
            CURRENT_PID=1
            PROC_STATE[1]="running"

            # Show prompt and read a command
            ksh_prompt
            local line=""
            if ! IFS= read -r line; then
                echo
                break
            fi

            # Execute the command (shell stops if exit returns 1)
            ksh_execute "$line" && continue

            # exit command
            _log_info "init: exiting..."
            echo "["$KERNEL_NAME"] Goodbye."
            proc_exit 1 0
            break
        fi

        # Fallback scheduler tick
        proc_schedule
    done
}

# ------------------------------------------------------------------------------
# 15. Entry Point
# ------------------------------------------------------------------------------

main "$@"
