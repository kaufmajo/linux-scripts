#!/usr/bin/env bash
set -euo pipefail

#----------------------------------------------------------
# Check if the script is running in WSL
if [ -z "${WSL_DISTRO_NAME:-}" ] && [ -z "${WSLENV:-}" ]; then
    echo "Error: This script must be run from WSL." >&2
    exit 1
fi

#----------------------------------------------------------
# Determine the path to Start-Terminal.ps1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS1_FILE="${START_TERMINAL_PS1:-$SCRIPT_DIR/Start-Terminal.ps1}"

if [ ! -f "$PS1_FILE" ]; then
    WIN_USERPROFILE="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')"
    if [ -n "$WIN_USERPROFILE" ]; then
        PS1_FILE="$(wslpath "$WIN_USERPROFILE")/Joachim/Devpool/Scripts/Start-Terminal.ps1"
    fi
fi

#----------------------------------------------------------
# Check if the Start-Terminal.ps1 file exists
if [ ! -f "$PS1_FILE" ]; then
    echo "Error: Start-Terminal.ps1 not found." >&2
    echo "Set START_TERMINAL_PS1 to its WSL path, e.g.:" >&2
    echo "  export START_TERMINAL_PS1=/mnt/c/Users/you/.../Start-Terminal.ps1" >&2
    exit 1
fi

#----------------------------------------------------------
# Convert the WSL path to a Windows path
WIN_PATH="$(wslpath -w "$PS1_FILE")"

# Check if PowerShell is available
if command -v pwsh.exe &>/dev/null; then
    PWSH=pwsh.exe
elif command -v powershell.exe &>/dev/null; then
    PWSH=powershell.exe
else
    echo "Error: PowerShell (pwsh.exe or powershell.exe) not found in PATH." >&2
    exit 1
fi

#----------------------------------------------------------
# Execute the PowerShell script with the provided arguments
exec "$PWSH" -NoLogo -File "$WIN_PATH" "$@"
