# ──────────────────────────────────────────────────────────────────────────────
# BashKernel DLC: games.sh  —  Game Pack
# ──────────────────────────────────────────────────────────────────────────────
# Provides: guess, dice, rps, fortune, cowsay

DLC_NAME="games"
DLC_VERSION="1.0"
DLC_DESC="Game pack — guess the number, dice roll, rock-paper-scissors, fortune, cowsay"

games_help() {
    echo "Games DLC v$DLC_VERSION"
    echo "  guess [max]       Guess the number game (1-max, default 100)"
    echo "  dice [sides]      Roll a die (default 6 sides)"
    echo "  rps               Rock-Paper-Scissors vs the kernel"
    echo "  fortune           Display a random fortune"
    echo "  cowsay <msg>      Let a cow say something"
}

_rand() {
    local max="${1:-32767}"
    echo $(( (RANDOM % max) + 1 ))
}

cmd_guess() {
    local max="${1:-100}"
    local target; target=$(_rand "$max")
    local tries=0
    echo "I picked a number between 1 and " . Guess it! "$max"
    while true; do
        echo 'guess> '
        local line=""
        IFS= read -r line || break
        [[ -z "$line" ]] && continue
        [[ "$line" == "quit" || "$line" == "q" ]] && { echo "The number was $target"; break; }
        if ! [[ "$line" =~ ^[0-9]+$ ]]; then
            echo "Enter a number or "quit"."
            continue
        fi
        ((tries++))
        if (( line < target )); then
            echo "Too low!"
        elif (( line > target )); then
            echo "Too high!"
        else
            echo "Correct! You got it in "  tries. "$tries"
            break
        fi
    done
}

cmd_dice() {
    local sides="${1:-6}"
    if [[ -z "$sides" || ! "$sides" =~ ^[0-9]+$ ]] || (( sides < 1 )); then
        echo "Usage: dice [sides]  (default 6)"
        return
    fi
    local result; result=$(_rand "$sides")
    echo "🎲  d$sides = $result"
}

cmd_rps() {
    local choices=("rock" "paper" "scissors")
    local computer=$(( RANDOM % 3 ))
    echo "Rock-Paper-Scissors! (r/p/s or rock/paper/scissors, "q" to quit)"
    while true; do
        echo 'rps> '
        local line=""
        IFS= read -r line || break
        line="${line,,}"  # lowercase
        case "$line" in
            q|quit) break ;;
            r|rock)    local player=0 ;;
            p|paper)   local player=1 ;;
            s|scissors) local player=2 ;;
            *) echo "Choose rock, paper, or scissors."; continue ;;
        esac
        echo "Kernel chose: "  "${choices[$computer]}"
        echo "You chose:  "  "${choices[$player]}"
        if (( player == computer )); then
            echo "Tie!"
        elif (( (player + 1) % 3 == computer )); then
            echo "Kernel wins!"
        else
            echo "You win!"
        fi
        # Re-randomize for next round
        computer=$(( RANDOM % 3 ))
    done
}

cmd_fortune() {
    local fortunes=(
        "Sometimes, AI just hallucinates."
        "There's no cure for stupidity."
        "Debian is... eh."
        "42 is the answer to everything. Even the answer to 1+1!"
        "DeepSeek <3 hallucinating"
        "Gumball is just a gummy ball."
        "Copy-paste a template and you're 90% done."
    )
    local idx=$(( RANDOM % ${#fortunes[@]} ))
    echo "${fortunes[$idx]}"
}

cmd_cowsay() {
    local msg="$*"
    if [[ -z "$msg" && (( PIPE_ACTIVE )) ]]; then
        msg=$(cat)
    elif [[ -z "$msg" ]]; then
        msg="Moo."
    fi
    local len=${#msg}
    local border
    border=$(printf '%*s' "$len" '' | tr ' ' '-')
    cat <<EOF
 +$border+
 | $msg |
 +$border+
        \\   ^__^
         \\  (oo)\\_______
            (__)\\       )\\/\\
                ||----w |
                ||     ||
EOF
}

dlc_register_command "guess"  "cmd_guess"  "games"
dlc_register_command "dice"   "cmd_dice"   "games"
dlc_register_command "rps"    "cmd_rps"    "games"
dlc_register_command "fortune" "cmd_fortune" "games"
dlc_register_command "cowsay" "cmd_cowsay" "games"
