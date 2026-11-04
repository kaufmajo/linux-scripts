# shellcheck shell=bash  # sourced, not run: tells shellcheck the shell (no shebang needed)
# colors.sh - ANSI color variables for the script output.
#
# Load with: source "$SCRIPT_DIR/library/colors.sh"
#
# Only uses colors when writing to a terminal (not when piped into a log file).
# The bright variants (9x) match PowerShell's Red, Green, ... (ConsoleColor 9-15);
# 90 = DarkGray. The normal variants (3x) would be PowerShell's DarkRed, DarkGreen, ...

# shellcheck disable=SC2034  # the variables are used by the scripts that load this file
if [[ -t 1 ]]; then
    C_RED=$'\e[91m' C_GREEN=$'\e[92m' C_YELLOW=$'\e[93m' C_BLUE=$'\e[94m'
    C_MAGENTA=$'\e[95m' C_CYAN=$'\e[96m' C_GRAY=$'\e[90m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_GRAY='' C_BOLD='' C_RESET=''
fi
