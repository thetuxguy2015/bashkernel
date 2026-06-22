# ──────────────────────────────────────────────────────────────────────────────
# BashKernel DLC: template.sh  —  Template
# ──────────────────────────────────────────────────────────────────────────────
# Provides: template

DLC_NAME="template"
DLC_VERSION="1.0"
DLC_DESC="A template for making DLCs."

temp_help() {
    echo "Template DLC v$DLC_VERSION"
    echo "  template   Shows a message."
}

cmd_temp() {
    echo "This is a template for making DLCs."
}

dlc_register_command "template"   "cmd_temp"   "template"
