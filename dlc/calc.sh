# ──────────────────────────────────────────────────────────────────────────────
# BashKernel DLC: calc.sh  —  Calculator & Expression Evaluator
# ──────────────────────────────────────────────────────────────────────────────
# Provides: calc, hex, dec, math

DLC_NAME="calc"
DLC_VERSION="1.0"
DLC_DESC="Calculator — evaluate expressions, hex/dec conversion, math ops"

calc_help() {
    echo "Calculator DLC v$DLC_VERSION"
    echo "  calc <expr>     Evaluate integer arithmetic expression"
    echo "  hex <num>       Convert decimal to hexadecimal"
    echo "  dec <hex>       Convert hexadecimal to decimal"
    echo "  math            Interactive calculator prompt"
    echo "Examples:"
    echo "  calc 2 + 2"
    echo "  calc (5 + 3) * 2 / 4"
    echo "  hex 255"
    echo "  dec ff"
}

cmd_calc() {
    local expr="$*"
    if [[ -z "$expr" ]]; then
        echo "Usage: calc <expression>"
        return
    fi
    # Use bash arithmetic for integer evaluation
    local result
    result=$((expr)) 2>/dev/null || {
        _log_error "calc: invalid expression"
        return 1
    }
    echo "$expr = $result"
}

cmd_hex() {
    local num="${1:-}"
    [[ -z "$num" ]] && { echo "Usage: hex <number>"; return; }
    echo "decimal $num = hex $(printf "%x" "$num" 2>/dev/null || echo ?)"
}

cmd_dec() {
    local hex="${1:-}"
    [[ -z "$hex" ]] && { echo "Usage: dec <hex>"; return; }
    # Normalize: strip 0x prefix if present
    hex="${hex#0x}"
    hex="${hex#0X}"
    if [[ ! "$hex" =~ ^[0-9a-fA-F]+$ ]]; then
        _log_error "dec: invalid hex number"
        return 1
    fi
    local result=$((16#$hex))
    echo "hex $hex = decimal $result"
}

cmd_math() {
    echo 'Interactive Calculator (enter "q" to quit)'
    echo 'Supports integer ops: + - * / % ( )'
    while true; do
        echo 'math> '
        local line=""
        IFS= read -r line || break
        [[ -z "$line" || "$line" == "q" || "$line" == "quit" ]] && break
        local result
        result=$((line)) 2>/dev/null || {
            echo "Error: invalid expression"
            continue
        }
        echo "= $result"
    done
}

dlc_register_command "calc" "cmd_calc" "calc"
dlc_register_command "hex"  "cmd_hex"  "calc"
dlc_register_command "dec"  "cmd_dec"  "calc"
dlc_register_command "math" "cmd_math" "calc"
