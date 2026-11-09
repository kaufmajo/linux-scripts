# shellcheck shell=bash  # sourced, not run: tells shellcheck the shell (no shebang needed)
# section_header.sh - section_header TITLE [DETAIL]
#
# Load with: source "$SCRIPT_DIR/library/function/section_header.sh"
#
# Blue marker and bold title (like Homebrew), optional gray detail (e.g. a
# path) on the next line, then an empty line:
#   ==> Backup
#   /mnt/d/host/wsl-debian/user1/
#
# Uses the colors from library/colors.sh if loaded, otherwise prints plain text.
# ${C_BLUE-} = value of C_BLUE, or empty if it is not set (avoids an error with "set -u").
section_header() {
    local title="$1" detail="${2:-}"
    printf '\n%s==>%s %s%s%s\n' "${C_BLUE-}" "${C_RESET-}" "${C_BOLD-}" "$title" "${C_RESET-}"
    [[ -z "$detail" ]] || printf '%s%s%s\n' "${C_GRAY-}" "$detail" "${C_RESET-}"
    printf '\n'
}
