# Bash primer for initd

This repo uses Bash because setup is mostly command orchestration: Homebrew,
Git, mise, macOS defaults, symlinks, and `$HOME` paths. Keeping it in Bash
means a fresh machine does not need Node, Go, or a build step before bootstrap
can run.

The goal is not "clever Bash". The goal is readable, defensive scripts that a
developer can follow like a checklist.

## Script map

| File | Purpose |
|---|---|
| `bootstrap.sh` | Dispatcher: detects `uname -s` and execs the platform bootstrap. |
| `macos/bootstrap.sh` | macOS setup: Xcode CLT → Homebrew → Brewfile → links → fish → mise → macOS defaults. |
| `linux/bootstrap.sh` | Linux setup: dnf packages (+ COPRs) → gh/1Password/Docker/mise → links → linux/setup.sh → fish → mise → git profile. |
| `linux/setup.sh` | Linux system tweaks (fonts, swappiness, GTK theme, session-script links, Firefox profile glue). |
| `shared/lib/link.sh` | Install managed config symlinks into `$HOME`, back up unmanaged files. Takes platform arg. |
| `shared/lib/cleanup.sh` | Remove only the symlinks that initd created. Takes platform arg. |
| `shared/lib/git-profile.sh` | Set the Git identity: personal uses the default email; work writes an override to `local.gitconfig`. |
| `macos/brewinstall.sh` | Add a formula or cask to the curated Brewfile and apply it locally. |
| `shared/lib/fs.sh` | Shared filesystem helpers: `path_exists`, `symlink_points_to`, `verify_symlink_target`, `backup_path`. |
| `shared/managed-links.sh` | Cross-platform `MANAGED_LINKS` array. Sources `fs.sh`. |
| `<platform>/managed-links.sh` | Appends platform-specific entries to `MANAGED_LINKS`. |
| `macos/defaults.sh` | Apply macOS system defaults (key repeat, hushlogin). |
| `macos/update.sh` / `linux/update.sh` | Upgrade Homebrew/dnf packages and mise-managed tools; Linux also self-updates mise. |
| `shared/lib/logging.sh` | Colored log helpers: `log`, `log_info`, `log_success`, `log_warn`, `log_error`. |
| `shared/test.sh` | Behavior tests that run against temporary home directories. |

## How to read a script

Start at `main`, which is always at the bottom. The larger scripts are written
so `main` reads like a plain-English checklist. For example,
`macos/bootstrap.sh`:

```bash
main() {
  ensure_xcode_clt
  ensure_homebrew

  # install packages...
  brew bundle --file "${work_brewfile}"

  "${SHARED_DIR}/lib/link.sh" macos

  ensure_fish

  mise install --yes

  "${MACOS_DIR}/defaults.sh"
}
```

If you only want to understand what the script does, read `main` first. Then
open the helper function whose name matches the step you care about.

## Design rules used here

1. **Keep policy data in one place per scope.** `shared/managed-links.sh` defines
   the cross-platform `MANAGED_LINKS`; each `<platform>/managed-links.sh` appends
   its OS-only entries to the same array.
2. **Keep filesystem mechanics in one place.** `shared/lib/fs.sh` owns helpers
   like `path_exists`, `symlink_points_to`, `backup_path`, and
   `verify_symlink_target`.
3. **Do not delete user files.** Existing unmanaged files are moved to
   `~/.config/initd-backups/<timestamp>/` before initd takes ownership.
4. **Only remove links initd owns.** Cleanup checks where each symlink points
   before removing it.
5. **Test with temporary homes.** The behavior tests exercise install, backup,
   cleanup, and Git profile switching without touching your real `$HOME`.

## The MANAGED_LINKS list

`shared/managed-links.sh` defines the cross-platform ownership list:

```bash
MANAGED_LINKS=(
  "${HOME}/.config/fish:${ROOT_DIR}/shared/configs/fish/.config/fish"
  "${HOME}/.config/ghostty:${ROOT_DIR}/shared/configs/ghostty/.config/ghostty"
  "${HOME}/.config/mise:${ROOT_DIR}/shared/configs/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/shared/configs/nvim/.config/nvim"
  "${HOME}/.config/starship.toml:${ROOT_DIR}/shared/configs/starship/.config/starship.toml"
  "${HOME}/.config/tmux:${ROOT_DIR}/shared/configs/tmux/.config/tmux"
)
```

`linux/managed-links.sh` appends OS-only entries to the same array (i3, polybar,
rofi, dunst, picom, xsettingsd, gtk-3.0). `macos/managed-links.sh` is currently
empty — every macOS dotfile lives in `shared/configs/`.

Each entry is `home path:repo path`. Scripts split
the pair like this:

```bash
home_path="${managed_link%%:*}"  # everything before the first colon
repo_path="${managed_link#*:}"   # everything after the first colon
```

**Adding a new managed config:** add one line to the appropriate `MANAGED_LINKS`
(`shared/managed-links.sh` for cross-platform, `<platform>/managed-links.sh` for
OS-only) and re-run `shared/test.sh`.

## Bash syntax used most often

### Script header

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Option | Meaning |
|---|---|
| `-e` | Exit immediately if any command fails. |
| `-u` | Treat unset variables as an error. |
| `pipefail` | A pipeline fails if any command in it fails (not just the last one). |

### Finding the repo root

Most scripts compute the repo root from their own path so they work no matter
which directory you run them from:

```bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

`${BASH_SOURCE[0]}` is the path to the current script file. `dirname` gives its
folder. `cd …/.. && pwd` walks up one level and resolves the absolute path.

### Quoting variables

Always wrap variables in double quotes to prevent word-splitting on spaces:

```bash
ln -s "${source}" "${path}"   # correct
ln -s $source $path           # breaks if path contains spaces
```

### Checking whether a path exists

`path_exists` from `shared/lib/fs.sh` handles regular files, directories, and
broken symlinks:

```bash
if path_exists "${path}"; then
  backup_path "${path}"
fi
```

Using `-e` alone would miss broken symlinks (a symlink whose target has been
deleted), so `path_exists` checks both `-e` and `-L`.

### Checking where a symlink points

`symlink_points_to` and `verify_symlink_target` from `shared/lib/fs.sh`:

```bash
# Returns true/false — use in if-conditions
if symlink_points_to "${path}" "${expected}"; then ...

# Exits 1 with an error message if wrong — use as a hard assertion
verify_symlink_target "${path}" "${expected}"
```

Under the hood, both call `readlink` to get the symlink's target and compare it
as a plain string. This works because all initd symlinks are created with
absolute paths.

### Loops over managed links

```bash
for managed_link in "${MANAGED_LINKS[@]}"; do
  home_path="${managed_link%%:*}"
  repo_path="${managed_link#*:}"
  install_managed_link "${home_path}" "${repo_path}"
done
```

`${array[@]}` expands every element. `%%:*` strips everything from the first
colon to the end; `#*:` strips everything up to and including the first colon.

### Argument parsing

Scripts parse their arguments with a `while` loop and `case`:

```bash
while (($#)); do      # while there are arguments left
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; return ;;
    *) log_error "Unknown argument: $1"; exit 1 ;;
  esac
  shift               # drop $1, move remaining args left
done
```

### Traps for cleanup

`trap` runs a command when the script exits, even on error. Used to clean up
temp files:

```bash
work_brewfile="$(mktemp)"
trap 'rm -f "${work_brewfile}"' EXIT
```

### Short-circuit operators

`&&` and `||` are used for one-line conditionals:

```bash
path_exists "${GITCONFIG}" && backup_path "${GITCONFIG}"   # backup only if it exists
command -v brew >/dev/null || { log_error "brew not found"; exit 1; }
```

## Logging

Use the shared helpers instead of raw `echo`:

```bash
log "Linking managed config paths..."        # blue ==>  — general progress
log_info "Dry run mode enabled."             # cyan ::   — extra detail
log_success "Managed symlinks verified."     # green OK  — step complete
log_warn "Backing up ${path} -> ${backup}"  # yellow !! — to stderr, non-fatal
log_error "brew not found."                 # red ERR   — to stderr, fatal
```

`log_warn` and `log_error` write to stderr so they appear even when stdout is
redirected.

## Backups and safety

If initd finds a real file or unrelated symlink where it needs to install a
managed link, it moves it to a timestamped backup directory first:

```bash
backup_path "${path}"
```

`backup_path` keeps the home-relative path under one shared `BACKUP_ROOT` so
all backups from a single bootstrap run are grouped in one folder. For example:

```text
~/.config/fish  ->  ~/.config/initd-backups/20260509120000/.config/fish
```

This is why `BACKUP_ROOT` must be set before calling `backup_path`.

## Testing strategy

### Behavior tests

```bash
shared/test.sh
```

This is the most important test. It creates temporary `$HOME` directories and
checks the four core behaviors:

1. **Clean install** — all managed paths are symlinked on a fresh home
2. **Backup of unmanaged configs** — existing user files are moved to the backup dir
3. **Git identity** — the personal path reports the baked-in default email; a work override goes into `local.gitconfig` without touching the linked base config
4. **Cleanup** — only initd-owned symlinks are removed; unrelated symlinks and real files are left alone

These behave like integration tests, which is the right choice for setup scripts
because the risky thing is filesystem state, not individual functions.

### Syntax check

After editing a script, verify there are no syntax errors:

```bash
bash -n bootstrap.sh \
  shared/lib/logging.sh shared/lib/fs.sh \
  shared/lib/link.sh shared/lib/cleanup.sh shared/lib/git-profile.sh \
  shared/managed-links.sh shared/test.sh \
  macos/bootstrap.sh macos/defaults.sh macos/brewinstall.sh macos/update.sh macos/managed-links.sh \
  linux/bootstrap.sh linux/setup.sh linux/update.sh linux/managed-links.sh
```

## How to safely change these scripts

1. **To add a new managed config:** add one line to the appropriate
   `MANAGED_LINKS` (`shared/managed-links.sh` for cross-platform,
   `<platform>/managed-links.sh` for OS-only) and re-run `shared/test.sh`.
2. **To add a new Homebrew package:** run `macos/brewinstall <package>`. It
   updates `macos/Brewfile` and installs it locally.
3. **To add a new dnf package:** append it to `linux/packages.txt`, then re-run
   `linux/bootstrap.sh`.
4. **Keep `main` readable as a checklist.** Put filesystem logic in
   `shared/lib/fs.sh` and path knowledge in the `managed-links.sh` files.
5. **Don't branch on OS inside `shared/`.** If shared code would need to, push
   the branch into the platform bootstrap script instead.
6. **Run the behavior tests** after any filesystem-related change.
7. **Do not touch `shared/configs/nvim/`** unless the task explicitly asks for
   Neovim changes.
