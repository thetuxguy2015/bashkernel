# ──────────────────────────────────────────────────────────────────────────────
# BashKernel DLC: extra.sh  —  Extra Utilities
# ──────────────────────────────────────────────────────────────────────────────
# Provides: clock, cal, date, whoami, hostname, tee, yes, factor, primes

DLC_NAME="extra"
DLC_VERSION="1.0"
DLC_DESC="Extra utilities — clock, calendar, date, identity, tee, yes, factor"

extra_help() {
    echo "Extra DLC v$DLC_VERSION"
    echo "  clock [12|24]     Live clock display (12h or 24h mode)"
    echo "  cal [year]        Display a calendar"
    echo "  date              Show current date and time"
    echo "  whoami            Show current user (kernel context)"
    echo "  hostname          Show system hostname"
    echo "  tee <file>        Copy stdin to file (one line)"
    echo "  yes [text]        Repeatedly print text"
    echo "  factor <num>      Factorize a number"
    echo "  primes [limit]    Show primes up to limit (default 100)"
    echo "  beep              Terminal bell"
    echo "  banner <text>     Display large banner text"
}

cmd_clock() {
    local mode="${1:-24}"
    echo "Clock (Ctrl+C to stop)"
    while true; do
        local now; now=$(date +"$([[ "$mode" == "12" ]] && echo '%I:%M:%S %p' || echo '%H:%M:%S')" 2>/dev/null)
        local today; today=$(date '+%Y-%m-%d %A')
        echo -e "\r\033[1;33m$today  |  $now\033[0m"
        sleep 1
    done
    echo ""
}

cmd_cal() {
    local year="${1:-}"
    if [[ -z "$year" ]]; then
        year=$(date '+%Y')
    fi
    if ! [[ "$year" =~ ^[0-9]+$ ]] || (( year < 1 || year > 9999 )); then
        echo "Usage: cal [year]  (1-9999)"
        return
    fi
    cal "$year" 2>/dev/null || {
        # Fallback: use ncal or just show the year
        echo "Calendar for $year"
        local m
        for ((m=1; m<=12; m++)); do
            echo ""
            date -d "$year-$m-01" "+%B %Y" 2>/dev/null || echo "Month $m $year"
        done
    }
}

cmd_date() {
    date 2>/dev/null || echo "BashKernel epoch: $KERNEL_UPTIME"
}

cmd_whoami() {
    echo 'root'
}

cmd_hostname() {
    local inode; inode=$(_vfs_lookup "/sys/hostname" 2>/dev/null) || {
        echo "bashbook"
        return
    }
    echo "${VFS_DATA[$inode]}"
}

cmd_tee() {
    local path="${1:-}"
    [[ -z "$path" ]] && { echo "Usage: tee <file>"; return 1; }
    if ! _vfs_lookup "$path" >/dev/null 2>&1; then
        vfs_create "$path" || return 1
    fi
    local inode; inode=$(_vfs_lookup "$path")
    local line=""
    echo "Enter text (empty line to finish):"
    while true; do
        IFS= read -r line || break
        [[ -z "$line" ]] && break
        echo "$line"
        local current="${VFS_DATA[$inode]:-}"
        vfs_write "$inode" "$current$line"$''
    done
}

cmd_yes() {
    local text="${*:-y}"
    # Print 10 times to avoid infinite loop
    local i
    for ((i=0; i<10; i++)); do
        echo "$text"
    done
}

cmd_factor() {
    local num="${1:-}"
    [[ -z "$num" ]] && { echo "Usage: factor <number>"; return; }
    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 2 )); then
        echo "Enter a positive integer >= 2."
        return
    fi
    echo "" : "$num"
    local n=$num
    local d=2
    while (( d * d <= n )); do
        while (( n % d == 0 )); do
            echo " "  "$d"
            n=$((n / d))
        done
        (( d == 2 )) && d=3 || d=$((d + 2))
    done
    (( n > 1 )) && echo " "  "$n"
    echo ""
}

cmd_primes() {
    local limit="${1:-100}"
    if ! [[ "$limit" =~ ^[0-9]+$ ]] || (( limit < 2 )); then
        echo "Usage: primes [limit]  (default 100)"
        return
    fi
    # Sieve of Eratosthenes
    local -a sieve=()
    local i
    for ((i=0; i<=limit; i++)); do sieve[i]=1; done
    sieve[0]=0; sieve[1]=0
    for ((i=2; i*i<=limit; i++)); do
        if (( sieve[i] )); then
            local j
            for ((j=i*i; j<=limit; j+=i)); do
                sieve[j]=0
            done
        fi
    done
    local count=0
    for ((i=2; i<=limit; i++)); do
        if (( sieve[i] )); then
            echo ""   "$i"
            ((count++))
        fi
    done
    echo "($count primes up to $limit)"
}

cmd_beep() {
    echo '\a'
}

cmd_banner() {
    local text="${*:-BashKernel}"
    # Simple figlet-like banner using ASCII art
    local line
    while IFS= read -r line; do
        echo "$line"
    done < <(echo "$text" | figlet 2>/dev/null || echo "$text" | banner 2>/dev/null || {
        echo "╔══════════════════════════════════╗"
        echo "║  $text  ║"
        echo "╚══════════════════════════════════╝"
    })
}

dlc_register_command "clock"   "cmd_clock"   "extra"
dlc_register_command "cal"     "cmd_cal"     "extra"
dlc_register_command "date"    "cmd_date"    "extra"
dlc_register_command "whoami"  "cmd_whoami"  "extra"
dlc_register_command "hostname" "cmd_hostname" "extra"
dlc_register_command "tee"     "cmd_tee"     "extra"
dlc_register_command "yes"     "cmd_yes"     "extra"
dlc_register_command "factor"  "cmd_factor"  "extra"
dlc_register_command "primes"  "cmd_primes"  "extra"
dlc_register_command "beep"    "cmd_beep"    "extra"
dlc_register_command "banner"  "cmd_banner"  "extra"
