# shellcheck shell=bash  # sourced, not run: tells shellcheck the shell (no shebang needed)
# main_header.sh - main_header TITLE SUBTITLE
#
# Load with: source "$SCRIPT_DIR/library/function/main_header.sh"
#
# One line: bold cyan title, gray subtitle.
#   Backup Script (WSL)  Version 1.0
#
# Uses the colors from library/colors.sh if loaded, otherwise prints plain text.
# ${C_BOLD-} = value of C_BOLD, or empty if it is not set (avoids an error with "set -u").
main_header() {
    printf '\n%s%s%s  %s%s%s\n' "${C_BOLD-}${C_CYAN-}" "$1" "${C_RESET-}" "${C_GRAY-}" "$2" "${C_RESET-}"
}
