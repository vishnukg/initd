# Bash primer for initd

This repo uses Bash because setup is mostly command orchestration: Homebrew,
Git, mise, and macOS defaults. Keeping the entry points in Bash
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
| `linux/setup.sh` | Linux system tweaks (fonts, GTK theme, session-script links, Firefox profile glue). |
| `shared/lib/link.sh` | Obtain Node through mise and launch `link.mjs`. Takes a platform argument. |
| `shared/lib/cleanup.mjs` | Remove only the symlinks that initd created. Takes platform arg. |
| `shared/lib/git-profile.mjs` | Set the Git identity: personal uses the default email; work writes an override to `local.gitconfig`. |
| `macos/brewinstall` | JavaScript entry point: add a formula or cask to the curated Brewfile and apply it locally; requires Node. |
| `shared/lib/fs.mjs` | JavaScript filesystem helpers shared by installation, cleanup, and Linux config setup. |
| `shared/managed-links.sh` | Cross-platform `MANAGED_LINKS` array. |
| `<platform>/managed-links.sh` | Appends platform-specific entries to `MANAGED_LINKS`. |
| `macos/defaults.sh` | Apply macOS system defaults (key repeat, hushlogin). |
| `macos/update.sh` / `linux/update.sh` | Upgrade Homebrew/dnf packages and mise-managed tools; Linux also self-updates mise. |
| `shared/lib/logging.sh` | Colored log helpers: `log`, `log_info`, `log_success`, `log_warn`, `log_error`. |
| `tests/install.test.mjs` | Behavior tests for installation, backups, cleanup, and the bootstrap launcher. |

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
2. **Keep filesystem mechanics in one place.** `shared/lib/fs.mjs` owns
   `pathStat`, `pointsTo`, `backupPath`, `installLink`, and `removeLink`.
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
  "${HOME}/.gitconfig:${ROOT_DIR}/shared/configs/git/gitconfig"
  "${HOME}/.colima/_templates/default.yaml:${ROOT_DIR}/shared/configs/colima/.colima/_templates/default.yaml"
  "${HOME}/.config/fish:${ROOT_DIR}/shared/configs/fish/.config/fish"
  "${HOME}/.config/ghostty:${ROOT_DIR}/shared/configs/ghostty/.config/ghostty"
  "${HOME}/.config/kitty:${ROOT_DIR}/shared/configs/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/shared/configs/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/shared/configs/nvim/.config/nvim"
  "${HOME}/.config/starship.toml:${ROOT_DIR}/shared/configs/starship/.config/starship.toml"
  "${HOME}/.config/tmux:${ROOT_DIR}/shared/configs/tmux/.config/tmux"
  "${HOME}/.local/share/wallpapers:${ROOT_DIR}/shared/wallpaper"
)
```

`linux/managed-links.sh` appends OS-only entries to the same array (Hyprland,
Quickshell, rofi, dunst, fontconfig, GTK, and session services).
`macos/managed-links.sh` is currently empty — every macOS dotfile lives in
`shared/configs/`.

Each entry is `home path:repo path`. `shared/lib/managed-links.mjs` evaluates
the manifests with Bash and reads NUL-separated entries. The JavaScript
installer consumes objects with `home` and `source` fields, preserving spaces
and newlines in paths.

**Adding a new managed config:** add one line to the appropriate `MANAGED_LINKS`
(`shared/managed-links.sh` for cross-platform, `<platform>/managed-links.sh` for
OS-only) and re-run `node --test tests/install.test.mjs`.

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

### Filesystem work

Bash still uses `[[ -f path ]]` and `[[ -d path ]]` for simple checks.
Installation and backup operations live in `shared/lib/fs.mjs`; its
`pathStat` handles broken symlinks and propagates filesystem errors.
`installLink` backs up unmanaged paths, and `removeLink` verifies ownership
before deleting. See [JavaScript in initd](javascript.md) for those helpers.

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
[[ -d "${font_dir}" ]] && log "Font directory exists"
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

```js
backupPath(file, { home, backupRoot });
```

`backupPath` in `shared/lib/fs.mjs` keeps the home-relative path under one shared `BACKUP_ROOT` so
all backups from a single bootstrap run are grouped in one folder. For example:

```text
~/.config/fish  ->  ~/.config/initd-backups/20260509120000/.config/fish
```

Callers pass `backupRoot` explicitly; the platform bootstrap exports
`BACKUP_ROOT` to group its helpers' backups. Paths outside HOME use an
`external/` subtree, keeping every backup beneath the chosen backup root.

## Testing strategy

### Behavior tests

```bash
node --test tests/install.test.mjs
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
for file in bootstrap.sh \
  shared/lib/logging.sh shared/lib/fonts.sh \
  shared/lib/link.sh \
  shared/managed-links.sh \
  macos/bootstrap.sh macos/defaults.sh macos/update.sh macos/managed-links.sh \
  linux/bootstrap.sh linux/setup.sh linux/update.sh linux/managed-links.sh \
  linux/scripts/*.sh; do
  bash -n "$file" || exit
done
```

Run `bash -n` separately for each file: additional arguments to a single call
are script arguments, so Bash only checks the first file. Check the JavaScript
helpers with `node --check`, including the extensionless `macos/brewinstall`.

## How to safely change these scripts

1. **To add a new managed config:** add one line to the appropriate
   `MANAGED_LINKS` (`shared/managed-links.sh` for cross-platform,
   `<platform>/managed-links.sh` for OS-only) and re-run `node --test tests/install.test.mjs`.
2. **To add a new Homebrew package:** run `macos/brewinstall <package>`. It
   updates `macos/Brewfile` and installs it locally.
3. **To add a new dnf package:** append it to `linux/packages.txt`, then re-run
   `linux/bootstrap.sh`.
4. **Keep `main` readable as a checklist.** Put filesystem logic in
   `shared/lib/fs.mjs` and path knowledge in the `managed-links.sh` files.
5. **Don't branch on OS inside `shared/`.** If shared code would need to, push
   the branch into the platform bootstrap script instead.
6. **Run the behavior tests** after any filesystem-related change.
7. **Do not touch `shared/configs/nvim/`** unless the task explicitly asks for
   Neovim changes.
