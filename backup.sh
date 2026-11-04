#!/usr/bin/env bash
#
# backup.sh - Back up the WSL filesystem to the master and slave backup drives.
#
# Counterpart of win_scripts/Backup.ps1, which backs up the Windows files.
#
# Layout on each backup drive (same as Backup.ps1):
#   X:\<hostname>\<TARGET_FOLDER>\<user>\           mirror, original paths (home\user1\..., var\www\...)
#   X:\<hostname>\<TARGET_FOLDER>\<user>.history\   old versions of changed/deleted files
#
# Usage: ./backup.sh --help

# Exit on error (-e), on unset variables (-u) and on errors inside pipes (pipefail).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.7.5"

#===============================================================
# OUTPUT HELPERS
#===============================================================

# "source" runs another file in THIS shell, so its variables and functions
# become available here (like dot-sourcing ". file.ps1" in PowerShell).
# shellcheck source=library/colors.sh
source "$SCRIPT_DIR/library/colors.sh"
# shellcheck source=library/function/main_header.sh
source "$SCRIPT_DIR/library/function/main_header.sh"
# shellcheck source=library/function/section_header.sh
source "$SCRIPT_DIR/library/function/section_header.sh"

info(){ printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
error() { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die() {
    error "ERROR: $*"
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- options for Backup.ps1]

Options:
  -c, --config FILE   Config file (default: config/backup.conf next to this script)
  -n, --dry-run       Show what would happen, change nothing
      --skip-history  Do not keep old versions of changed/deleted files
      --with-windows  Run the Windows backup (Backup.ps1) afterwards
  -h, --help          Show this help

Everything after "--" is passed to Backup.ps1, e.g.:
  $(basename "$0") --with-windows -- -SkipHistory
EOF
}

#===============================================================
# PARAMS
#===============================================================

CONFIG_FILE=""
DRY_RUN=false
SKIP_HISTORY=false
WITH_WINDOWS=false
WINDOWS_ARGS=()

while (($# > 0)); do
    case "$1" in
    -c | --config)
        [[ $# -ge 2 ]] || die "$1 needs a file argument"
        CONFIG_FILE="$2"
        shift
        ;;
    -n | --dry-run) DRY_RUN=true ;;
    --skip-history) SKIP_HISTORY=true ;;
    --with-windows) WITH_WINDOWS=true ;;
    -h | --help)
        usage
        exit 0
        ;;
    --)
        # "--" means: the rest is not for me. Keep it for Backup.ps1.
        shift
        WINDOWS_ARGS=("$@")
        break
        ;;
    *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
done

if ((${#WINDOWS_ARGS[@]} > 0)) && ! $WITH_WINDOWS; then
    die "Options after -- are for Backup.ps1 and need --with-windows"
fi

# Backup.ps1 has no dry-run mode: the Windows part would silently run for real.
if $DRY_RUN && $WITH_WINDOWS; then
    die "--dry-run cannot be combined with --with-windows"
fi

#===============================================================
# MAIN HEADER
#===============================================================

main_header "Backup Script (WSL)" "Version $VERSION"

#===============================================================
# CHECKS
#===============================================================

# The WSL kernel has "microsoft" in its version string.
grep -qi microsoft /proc/version 2>/dev/null || die "This script only runs in WSL"

# Running as root would make $USER "root" and change the target folder.
[[ $EUID -ne 0 ]] || die "Please run as your normal user"

for tool in rsync powershell.exe pwsh.exe wsl.exe wslpath; do
    command -v "$tool" >/dev/null || die "Required tool not found: $tool"
done

#===============================================================
# CONFIG
#===============================================================

CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config/backup.conf}"
[[ -f "$CONFIG_FILE" ]] || die "Config file not found at: $CONFIG_FILE (copy config/backup.sample.conf)"
CONFIG_FILE="$(realpath "$CONFIG_FILE")"

# Defaults - the config file overrides them.
MASTER_LETTER="" MASTER_LABEL="" MASTER_BITLOCKER=false MASTER_ENVVAR=""
SLAVE_LETTER="" SLAVE_LABEL="" SLAVE_BITLOCKER=false SLAVE_ENVVAR=""
TARGET_FOLDER=""
HISTORY_KEEP=30
WIN_UNLOCK_SCRIPT=""
WIN_BACKUP_SCRIPT=""
SOURCES=()
EXCLUDES=()

info "Using config file $CONFIG_FILE"

# "source" runs the config file as bash code in this shell, so its variables
# become ours. Only ever source files you trust!
# shellcheck source=config/backup.sample.conf
source "$CONFIG_FILE"

[[ -n "$TARGET_FOLDER" ]] || die "TARGET_FOLDER is not set in the config"
((${#SOURCES[@]} > 0)) || die "SOURCES is empty in the config"

for src in "${SOURCES[@]}"; do
    [[ -e "$src" ]] || die "Source not found: $src"
done

# Mirror options (fixed, like the robocopy /MIR options in Backup.ps1):
# -r recursive, -l keep symlinks, -t keep timestamps, --delete = mirror.
# Not "-a": that also copies owner/group/permissions, which NTFS cannot store.
RSYNC_OPTS=(-rlt --delete)

EXCLUDE_ARGS=()
for pattern in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=("--exclude=$pattern")
done

$DRY_RUN && warn "Dry run: nothing will be changed"

#===============================================================
# HELPERS
#===============================================================

FAILED=false

# Read a per-drive config value, e.g. cfg MASTER LABEL -> $MASTER_LABEL
# ${!name} is "indirect expansion": the value of the variable whose name is in $name.
cfg() {
    local name="${1}_${2}"
    printf '%s' "${!name-}"
}

# Run a command as root without a sudo password: wsl.exe (a Windows program)
# starts the command in our own distro as root. Windows allows this for the
# Windows user who owns the distro.
as_root() {
    wsl.exe -d "$WSL_DISTRO_NAME" -u root -- "$@"
}

# Run powershell.exe; Windows output has CRLF line endings, so strip the \r.
win_ps() {
    powershell.exe -NoProfile -NonInteractive -Command "$1" 2>/dev/null | tr -d '\r'
}

# Prints "FILESYSTEM|LABEL" of a Windows drive, e.g. "NTFS|DrWork".
# A locked BitLocker drive shows as "Unknown|". Missing drive: empty output.
win_volume_info() {
    win_ps "\$v = Get-Volume -DriveLetter $1 -ErrorAction SilentlyContinue; if (\$v) { \"\$(\$v.FileSystemType)|\$(\$v.FileSystemLabel)\" }"
}

# Run rsync; exit code 24 ("some source files vanished") is only a warning.
run_rsync() {
    local -a extra=()
    $DRY_RUN && extra+=(--dry-run)
    local rc=0
    rsync "${extra[@]}" "$@" || rc=$?
    case $rc in
    0) ;;
    24) warn "Some source files vanished during transfer (rsync code 24)" ;;
    *)
        error "rsync failed with exit code $rc"
        FAILED=true
        return "$rc"
        ;;
    esac
}

#===============================================================
# DRIVES
#===============================================================

declare -A DRIVE_MOUNT=() # role -> mount point, filled by prepare_drive

# Let Windows unlock a BitLocker drive with Enable-BitlockerDrive.ps1.
# It elevates itself (UAC prompt) and reads the password from its own .env,
# so no password is ever stored in WSL.
win_unlock_bitlocker() {
    local role="$1" letter="$2" envvar="$3"

    # "Master" / "Slave": for the messages and the PS script's
    # -MasterDriveLetter / -SlaveDriveLetter parameters.
    # ${role,,} = "master", ${x^} = first letter uppercase -> "Master"
    local prefix="${role,,}"
    prefix="${prefix^}"

    [[ -n "$WIN_UNLOCK_SCRIPT" ]] ||
        { warn "$prefix drive '$letter' cannot be unlocked, WIN_UNLOCK_SCRIPT is not set"; return 1; }
    [[ -f "$WIN_UNLOCK_SCRIPT" ]] ||
        { warn "$prefix drive '$letter' cannot be unlocked, unlock script '$WIN_UNLOCK_SCRIPT' not found"; return 1; }

    # wslpath converts paths: /mnt/c/foo -> C:\foo (-w) and back (-u).
    local script_win
    script_win="$(wslpath -w "$WIN_UNLOCK_SCRIPT")"

    info "${C_YELLOW}Drive $letter: is locked. Unlocking via Windows (confirm the UAC prompt) ...${C_RESET}"
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$script_win" \
        "-${prefix}DriveLetter" "$letter" "-${prefix}DriveEnvvar" "$envvar" ||
        { warn "$prefix drive '$letter' could not be unlocked"; return 1; }
}

# Check, unlock and mount one Windows drive. Sets DRIVE_MOUNT[$role] on success.
prepare_drive() {
    local role="$1"
    local label letter bitlocker envvar role_name="${role,,}" # MASTER -> master
    letter="$(cfg "$role" LETTER)"
    letter="${letter^^}" # uppercase
    label="$(cfg "$role" LABEL)"
    bitlocker="$(cfg "$role" BITLOCKER)"
    envvar="$(cfg "$role" ENVVAR)"

    [[ -n "$label" && -n "$letter" ]] || return 1
    [[ "$letter" =~ ^[A-Z]$ ]] || { warn "${role_name^} drive letter '$letter' is invalid"; return 1; }

    local volume fstype actual_label
    volume="$(win_volume_info "$letter")"
    [[ -n "$volume" ]] || { warn "${role_name^} drive '$letter' not found"; return 1; }
    IFS='|' read -r fstype actual_label <<<"$volume"

    # Label doesn't match and drive is BitLocker -> probably locked: unlock and look again.
    if [[ "$actual_label" != "$label" && "$bitlocker" == "true" ]]; then
        win_unlock_bitlocker "$role" "$letter" "$envvar" || return 1
        volume="$(win_volume_info "$letter")"
        IFS='|' read -r fstype actual_label <<<"$volume"
    fi

    if [[ "$actual_label" != "$label" ]]; then
        warn "${role_name^} drive '$letter' has label '$actual_label' ($fstype), expected '$label'"
        return 1
    fi

    # Windows drives appear in WSL through "drvfs". WSL mounts them only at
    # startup, so a drive that was locked or plugged in later must be mounted.
    local mnt="/mnt/${letter,,}"

    # A stale mount (made while the drive was locked) can't be read: remount.
    if mountpoint -q "$mnt" && ! ls "$mnt" >/dev/null 2>&1; then
        as_root umount "$mnt" || true
    fi

    if ! mountpoint -q "$mnt"; then
        info "Mounting $letter: on $mnt ..."
        as_root mkdir -p "$mnt"
        as_root mount -t drvfs "$letter:" "$mnt" -o "uid=$(id -u),gid=$(id -g)" ||
            { warn "${role_name^} drive '$letter' could not be mounted"; return 1; }
    fi

    DRIVE_MOUNT[$role]="$mnt"
}

# Drive overview like in Backup.ps1: one line per drive, "Master"/"Slave"
# for the drives that were selected.
show_drives() {
    local letter label selected role role_letter

    printf '%-7s%-12s%s\n' "Letter" "Label" "Selected"
    printf '%-7s%-12s%s\n' "______" "___________" "________"

    # Same filter as Get-BackupVolumes in win_scripts: NTFS/FAT32, fixed or
    # removable, with a drive letter. One line per drive: "D|DrWork"
    # "< <(...)" feeds the output of a command into the while loop.
    while IFS='|' read -r letter label; do
        selected=""
        for role in MASTER SLAVE; do
            role_letter="$(cfg "$role" LETTER)"
            if [[ "${letter^^}" == "${role_letter^^}" && -n "${DRIVE_MOUNT[$role]-}" ]]; then
                selected="${role,,}"
                selected="${selected^}" # "Master" / "Slave"
            fi
        done
        printf '%-7s%-12s%s%s%s\n' "$letter" "$label" "$C_GREEN" "$selected" "$C_RESET"
    done < <(win_ps "Get-Volume | Where-Object { \$_.FileSystemType -in @('NTFS','FAT32') -and \$_.DriveType -in @('Fixed','Removable') -and \$_.DriveLetter } | ForEach-Object { \"\$(\$_.DriveLetter)|\$(\$_.FileSystemLabel)\" }")

    echo
}

INPUT_TIMEOUT=10

# Like Wait-ForInput in win_scripts: wait INPUT_TIMEOUT seconds for input, then
# continue with an empty answer. Once a key is pressed, the timeout stops.
# Usage: wait_for_input VARIABLE_NAME
wait_for_input() {
    # "local -n" makes "result" a reference (nameref) to the caller's variable:
    # assigning to result assigns to that variable.
    local -n result="$1"
    local rest=""
    result=""

    printf '(Timeout in %sSec) ' "$INPUT_TIMEOUT"

    # Read only the first key with a timeout (-n 1). Enter alone = empty answer.
    if read -r -t "$INPUT_TIMEOUT" -n 1 result; then
        # A key was pressed: read the rest of the line without time limit.
        if [[ -n "$result" ]]; then
            read -r rest || true
            result+="$rest"
        fi
    else
        echo
        warn "No input received within $INPUT_TIMEOUT seconds, proceeding..."
        result=""
    fi
}

# Fallback when the configured drive is not found: ask for a drive letter.
ask_for_drive() {
    local role="$1" label answer
    label="$(cfg "$role" LABEL)"
    [[ -n "$label" ]] || return 1

    printf 'Enter %s%s%s drive letter: ' "$C_YELLOW" "${role,,}" "$C_RESET"
    wait_for_input answer
    [[ -n "$answer" ]] || return 1

    # printf -v assigns to a variable whose NAME is dynamic: MASTER_LETTER=...
    printf -v "${role}_LETTER" '%s' "$answer"
    prepare_drive "$role"
}

#===============================================================
# UNLOCK / MOUNT DRIVES
#===============================================================

section_header "Drives"

for role in MASTER SLAVE; do
    prepare_drive "$role" || true
done

show_drives

for role in MASTER SLAVE; do
    [[ -n "${DRIVE_MOUNT[$role]-}" ]] || ask_for_drive "$role" || true
done

#===============================================================
# SET TARGETS
#===============================================================

TARGETS=()

for role in MASTER SLAVE; do
    if [[ -n "${DRIVE_MOUNT[$role]-}" ]]; then
        # Same layout as Backup.ps1: <drive>/<computer>/<target folder>/<user>
        target="${DRIVE_MOUNT[$role]}/$(hostname)/$TARGET_FOLDER/$USER"
        role_name="${role,,}" # MASTER -> master, then ${role_name^} -> Master
        info "${role_name^} is $target/"
        TARGETS+=("$target")
    else
        info "${C_YELLOW}No valid ${role,,} drive given, or drive is locked${C_RESET}"
    fi
done

echo
((${#TARGETS[@]} > 0)) || exit 1

#===============================================================
# BACKUP PER TARGET
#===============================================================

STAMP="$(date +%Y-%m-%d_%H_%M_%S)"

for target in "${TARGETS[@]}"; do

    history_root="$target.history"
    section_header "Backup" "$target/"

    $DRY_RUN || mkdir -p "$target"

    # --backup     before a file is overwritten or deleted, move its old version ...
    # --backup-dir ... to this folder (created only if something changed)
    history_args=()
    $SKIP_HISTORY || history_args=(--backup --backup-dir="$history_root/$STAMP")

    # --relative   keep the full source path below the target (/var/www -> <target>/var/www)
    # --info=name1 lists only what rsync changes. tee also writes that list to
    # a temp file: empty = nothing changed. "> >(tee ...)" keeps run_rsync in
    # this shell, so its FAILED=true is not lost.
    rsync_log="$(mktemp)"
    run_rsync "${RSYNC_OPTS[@]}" --relative --info=name1 "${history_args[@]}" \
        "${EXCLUDE_ARGS[@]}" "${SOURCES[@]}" "$target/" > >(tee "$rsync_log") || true
    wait $! # let tee finish writing

    [[ -s "$rsync_log" ]] || info "No changed files found for backup"
    rm -f -- "$rsync_log"

    if $SKIP_HISTORY; then
        warn "History: skipped (--skip-history)"
        continue # next target - no history to report or clean up
    fi

    # Report the history like Backup.ps1: one line per file, then the count.
    # rsync saves the old versions during the mirror, so this section comes
    # after the backup. The folder only exists if an old version was saved.
    if ! $DRY_RUN; then
        section_header "History" "$history_root/$STAMP/"

        count=0
        if [[ -d "$history_root/$STAMP" ]]; then
            while IFS= read -r -d '' file; do
                info "History: $file"
                count=$((count + 1))
            done < <(find "$history_root/$STAMP" -type f -printf '%P\0' | sort -z)
        fi

        info "Moved $count file(s) to history"
    fi

    # Keep the newest $HISTORY_KEEP history folders. The names are timestamps,
    # so sorting by name = sorting by date.
    if [[ -d "$history_root" ]]; then
        mapfile -t old_folders < <(
            find "$history_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
                sort -r | tail -n +$((HISTORY_KEEP + 1))
        )

        for folder in "${old_folders[@]}"; do
            if $DRY_RUN; then
                info "Would delete history: $history_root/$folder"
            else
                rm -rf -- "${history_root:?}/$folder"
                info "Deleted history: $history_root/$folder"
            fi
        done
    fi
done

#===============================================================
# WINDOWS BACKUP
#===============================================================

if $WITH_WINDOWS; then

    [[ -f "$WIN_BACKUP_SCRIPT" ]] || die "Backup.ps1 not found: $WIN_BACKUP_SCRIPT"

    # "${WINDOWS_ARGS[@]}" = everything after "--", passed on unchanged.
    rc=0
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$WIN_BACKUP_SCRIPT")" \
        "${WINDOWS_ARGS[@]}" || rc=$?

    if ((rc != 0)); then
        error "Windows backup failed with exit code $rc"
        FAILED=true
    fi
fi

#===============================================================
# DONE
#===============================================================

if $FAILED; then
    echo
    error "Backup finished with errors"
    exit 1
fi
