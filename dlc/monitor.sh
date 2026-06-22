# ──────────────────────────────────────────────────────────────────────────────
# BashKernel DLC: monitor.sh  —  System Monitor
# ──────────────────────────────────────────────────────────────────────────────
# Provides: top, mon, procs

DLC_NAME="monitor"
DLC_VERSION="1.0"
DLC_DESC="System monitor — live process viewer, resource usage"

monitor_help() {
    echo "Monitor DLC v$DLC_VERSION"
    echo "  top [n]    Show live process list (refresh n times, default infinite)"
    echo "  mon        Show one-shot system summary"
    echo "  procs      List processes with resource details"
}

_mon_header() {
    echo '\033[1;36m'
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                      BashKernel Monitor                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo '\033[0m'
}

_mon_mem_bar() {
    local used="$1"
    local total="$2"
    local width="${3:-20}"
    local pct=0
    (( total > 0 )) && pct=$(( used * 100 / total ))
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    echo '\033[1;31m'
    echo '%*s' "$filled" '' | tr ' ' '|'
    echo '\033[0m\033[1;30m'
    echo '%*s' "$empty" '' | tr ' ' '|'
    echo "\033[0m " %% "$pct"
}

cmd_top() {
    local max_refresh="${1:--1}"  # -1 = infinite
    local refresh=0
    while true; do
        (( max_refresh >= 0 && refresh >= max_refresh )) && break
        ((refresh++))
        echo '\033[2J\033[H'
        _mon_header
        echo "Kernel uptime: " s "$KERNEL_UPTIME"
        echo "Processes: "  total "${#PROC_PID[@]}"
        # Memory
        local used=0
        local p
        for p in "${MEM_PAGES[@]}"; do
            [[ "$p" != "free" ]] && ((used++))
        done
        echo "Memory: $used/$TOTAL_PAGES pages used  "
        _mon_mem_bar "$used" "$TOTAL_PAGES" 25
        echo ""
        # Process table
        echo "PID    NAME         STATE      CPU"
        for pid in "${!PROC_PID[@]}"; do
            local name="${PROC_NAME[$pid]:-?}"
            local state="${PROC_STATE[$pid]:-?}"
            local runtime="${PROC_RUNTIME[$pid]:-0}"
            echo "$pid    $name         $state      $((runtime > 0 ? runtime : 0))"
        done
        sleep 1
    done
}

cmd_mon() {
    _mon_header

    # Uptime
    echo "Uptime:"  seconds "$KERNEL_UPTIME"

    # Processes
    local running=0 waiting=0 zombie=0 idle=0 ready=0
    local pid
    for pid in "${!PROC_PID[@]}"; do
        case "${PROC_STATE[$pid]}" in
            running) ((running++)) ;;
            waiting) ((waiting++)) ;;
            zombie)  ((zombie++)) ;;
            idle)    ((idle++)) ;;
            ready)   ((ready++)) ;;
        esac
    done
    echo "Procs:   ${#PROC_PID[@]} total  [running: $running  ready: $ready  waiting: $waiting  zombie: $zombie  idle: $idle]"
        "${#PROC_PID[@]}" "$running" "$ready" "$waiting" "$zombie" "$idle"

    # Memory
    local used=0 mem_free=0
    local p
    for p in "${MEM_PAGES[@]}"; do
        [[ "$p" != "free" ]] && ((used++)) || ((mem_free++))
    done
    local total_pages=$((used + mem_free))
    echo "Memory:  $used/$total_pages pages used ($(( total_pages > 0 ? used * 100 / total_pages : 0 ))%%)   Free: $mem_free pages"
        "$used" "$total_pages" $(( total_pages > 0 ? used * 100 / total_pages : 0 )) "$mem_free"
    echo '         '
    _mon_mem_bar "$used" "$total_pages" 30

    # VFS
    local files=0 dirs=0 links=0
    for pid in "${!VFS_TYPE[@]}"; do
        case "${VFS_TYPE[$pid]}" in
            file) ((files++)) ;;
            dir)  ((dirs++)) ;;
            link) ((links++)) ;;
        esac
    done
    echo "VFS:     ${#VFS_TYPE[@]} inodes  [dirs: $dirs  files: $files  links: $links]"

    # Loaded DLCs
    echo 'DLCs:   '
    if (( ${#DLC_LOADED[@]} == 0 )); then
        echo "(none loaded)"
    else
        echo "${DLC_LOADED[*]}"
    fi
}

cmd_procs() {
    echo "PID    NAME              STATE     PPID   PRI    RUNTIME"
    local pid
    for pid in "${!PROC_PID[@]}"; do
        local ppid="${PROC_PPID[$pid]:-0}"
        local pri="${PROC_PRIORITY[$pid]:-0}"
        echo "$pid    ${PROC_NAME[$pid]:-?}         ${PROC_STATE[$pid]:-?}     $ppid   $pri    ${PROC_RUNTIME[$pid]:-0}" \
        # Show allocated memory for this process
        local mem_count=0
        local i
        for ((i=0; i<TOTAL_PAGES; i++)); do
            [[ "${MEM_PAGES[$i]}" == "$pid" ]] && ((mem_count++))
        done
        if (( mem_count > 0 )); then
            echo "      └─ mem: $mem_count pages ($((mem_count * PAGE_SIZE / 1024)) KB)"
        fi
    done
}

dlc_register_command "top"   "cmd_top"   "monitor"
dlc_register_command "mon"   "cmd_mon"   "monitor"
dlc_register_command "procs" "cmd_procs" "monitor"
