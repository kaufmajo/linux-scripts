# Linux scripts

Bash helpers for the WSL (Debian) setup, development, and backup.

Counterpart of the PowerShell [win-scripts](https://github.com/kaufmajo/win-scripts)
repository: some scripts here call Windows scripts from there.

## Scripts

| Script | Purpose |
| --- | --- |
| [backup.sh](#backupsh) | Back up the WSL filesystem to the BitLocker backup drives. |
| [start-terminal.sh](#start-terminalsh) | Start `Start-Terminal.ps1` from WSL. |
| [sc_install_packages.sh](#sc_install_packagessh) | Install the base apt packages. |
| [sc_install_neovim.sh](#sc_install_neovimsh) | Install the latest Neovim AppImage to `/opt/nvim`. |
| [sc_install_composer.sh](#sc_install_composersh) | Install Composer (PHP) with checksum verification. |
| [sc_install_dotfiles.sh](#sc_install_dotfilessh) | Link the Neovim config from `~/dotfiles`. |
| [sc_setup_ssh_access.sh](#sc_setup_ssh_accesssh) | Copy the SSH public key to the configured hosts. |
| [sc_start_development.sh](#sc_start_developmentsh) | (Re)start Apache and MariaDB. |

## backup.sh

Mirrors the WSL filesystem to the master and slave backup drives with `rsync`.
Files on the Windows side are backed up by `Backup.ps1` (win_scripts); start it
afterwards with `--with-windows`. The other way round, `Backup.ps1 -WithLinux`
starts this script afterwards.

Layout on each backup drive (`TARGET_FOLDER` is `wsl-debian` in the default config):

```text
X:\<hostname>\<TARGET_FOLDER>\<user>\           mirror, original paths (home\user1\..., var\www\...)
X:\<hostname>\<TARGET_FOLDER>\<user>.history\   history: old versions of changed and deleted files
```

**Setup:** copy [config/backup.sample.conf](config/backup.sample.conf) to
`config/backup.conf` and adjust it. `backup.conf` is not tracked by git.

**Run:**

```bash
./backup.sh
```

**Show what would happen, change nothing:**

```bash
./backup.sh --dry-run
```

**Run the Windows backup afterwards, passing options to Backup.ps1:**

```bash
./backup.sh --with-windows -- -SkipHistory
```

| Option | Effect |
| --- | --- |
| `-c, --config FILE` | Use another config file. |
| `-n, --dry-run` | Show what would happen, change nothing. |
| `--skip-history` | Do not keep old versions of changed and deleted files. |
| `--with-windows` | Run `Backup.ps1` afterwards. Options after `--` are passed to it. |
| `-h, --help` | Show the help. |

**How it works:**

1. For each drive, Windows is asked for its label (`powershell.exe`, no
   administrator rights needed). A locked BitLocker drive is unlocked with
   `Enable-BitlockerDrive.ps1` from win_scripts (UAC prompt); the password is
   read there, never stored in WSL.
2. The drive is mounted at `/mnt/<letter>` (drvfs) with `wsl.exe -u root`, so
   no sudo password is needed.
3. If a configured drive is not found, the script asks for its drive letter and
   continues without it after 10 seconds without input.
4. `rsync --relative --delete` mirrors every path in `SOURCES`; `--backup-dir`
   moves the old version of each overwritten or deleted file to a dated
   history folder first. The newest `HISTORY_KEEP` history folders are kept.

**Before running:**

- Runs in WSL only, as your normal user (not as root).
- Mirroring deletes files on the drive that no longer exist in the source;
  their old versions are kept in the history.
- `EXCLUDES` should list what can be downloaded again (tool caches,
  `node_modules`, `vendor`). Paths removed from `SOURCES` or newly excluded stay
  on the drive until you delete them there.
- NTFS cannot store Linux owners and permissions: a restore from the drive loses
  them (e.g. executable flags, `www-data` ownership).
- `--dry-run` cannot be combined with `--with-windows`, because `Backup.ps1`
  has no dry-run mode.

## start-terminal.sh

Finds `Start-Terminal.ps1` (next to this script, in the win_scripts repository,
or at `$START_TERMINAL_PS1`) and runs it with `pwsh.exe` or `powershell.exe`.
All arguments are passed on.

```bash
./start-terminal.sh
```

## sc_install_packages.sh

Installs the base packages with apt (`man-db`, `grep`, `rsync`, `wget`, `curl`,
`fuse`, `build-essential`, `python3`, `python3-pip`, `python3-venv`), skipping
packages that are already installed. Needs root.

```bash
sudo ./sc_install_packages.sh
```

## sc_install_neovim.sh

Downloads the latest Neovim AppImage and moves it to `/opt/nvim/nvim`. Add
`/opt/nvim` to `PATH` to use `nvim` globally. Uses sudo for the move.

## sc_install_composer.sh

Installs Composer into the current directory (`composer.phar`), following the
official instructions, and aborts if the installer checksum does not match.
Needs PHP.

## sc_install_dotfiles.sh

Replaces `~/.config/nvim` with a symbolic link to `~/dotfiles/nvim`. An existing
`~/.config/nvim` folder is deleted.

## sc_setup_ssh_access.sh

Asks for each configured host whether to install your public key
(`~/.ssh/id_ed25519.pub`) there with `ssh-copy-id`. The host list is defined at
the top of the script. Create a key first with `ssh-keygen -t ed25519`.

## sc_start_development.sh

Starts Apache, or restarts it if it is already running. Does the same for
MariaDB if it is installed. Needs root.

```bash
sudo ./sc_start_development.sh
```
