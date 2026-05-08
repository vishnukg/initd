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
| `bootstrap.sh` | Detect the operating system and hand off to the platform bootstrap. |
| `platforms/darwin/bootstrap.sh` | macOS setup: Xcode CLT → Homebrew → Brewfile → Oh My Zsh → links → mise → macOS defaults. |
| `scripts/link.sh` | Install managed config symlinks into `$HOME`, back up unmanaged files, and fold old file-level links into direct directory links. |
| `scripts/cleanup.sh` | Remove only the symlinks that initd created. |
| `scripts/git-profile.sh` | Switch `~/.gitconfig` between the curated Git profiles. |
| `scripts/brewinstall.sh` | Add a formula or cask to the curated Brewfile and apply it locally. |
| `scripts/fs.sh` | Shared filesystem helpers: `path_exists`, `symlink_points_to`, `verify_symlink_target`, `backup_path`. |
| `scripts/paths.sh` | The list of paths initd owns and the git-profile helpers. Sources `fs.sh`. |
| `scripts/logging.sh` | Colored log helpers: `log`, `log_info`, `log_success`, `log_warn`, `log_error`. |
| `scripts/test-install-behavior.sh` | Behavior tests that run against temporary home directories. |

## How to read a script

Start at `main`, which is always at the bottom. The larger scripts are written
so `main` reads like a plain-English checklist. For example,
`platforms/darwin/bootstrap.sh`:

```bash
main() {
  ensure_xcode_clt
  ensure_homebrew

  # install packages...
  brew bundle --file "${work_brewfile}"

  ensure_oh_my_zsh

  "${ROOT_DIR}/scripts/link.sh"

  mise install --yes

  "${ROOT_DIR}/platforms/darwin/macos.sh"
}
```

If you only want to understand what the script does, read `main` first. Then
open the helper function whose name matches the step you care about.

## Design rules used here

1. **Keep policy data in one place.** `scripts/paths.sh` defines which runtime
   paths initd owns via `MANAGED_LINKS`.
2. **Keep filesystem mechanics in one place.** `scripts/fs.sh` owns helpers
   like `path_exists`, `symlink_points_to`, `backup_path`, and
   `verify_symlink_target`.
3. **Do not delete user files.** Existing unmanaged files are moved to
   `~/.config/initd-backups/<timestamp>/` before initd takes ownership.
4. **Only remove links initd owns.** Cleanup checks where each symlink points
   before removing it.
5. **Test with temporary homes.** The behavior tests exercise install, backup,
   cleanup, directory folding, and Git profile switching without touching your
   real `$HOME`.

## The MANAGED_LINKS list

`scripts/paths.sh` contains the ownership list:

```bash
MANAGED_LINKS=(
  "${HOME}/.config/kitty:${ROOT_DIR}/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/nvim/.config/nvim"
  "${HOME}/.zshrc:${ROOT_DIR}/zsh/.zshrc"
  "${HOME}/.zprofile:${ROOT_DIR}/zsh/.zprofile"
)
```

Each entry is `runtime path in $HOME : source path in this repo`. Scripts split
the pair like this:

```bash
path="${link%%:*}"    # everything before the first colon
source="${link#*:}"   # everything after the first colon
```

**Adding a new managed config** means adding one line to `MANAGED_LINKS` and
adding the corresponding assertion to `test-install-behavior.sh`.

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

`path_exists` from `scripts/fs.sh` handles regular files, directories, and
broken symlinks:

```bash
if path_exists "${path}"; then
  backup_path "${path}"
fi
```

Using `-e` alone would miss broken symlinks (a symlink whose target has been
deleted), so `path_exists` checks both `-e` and `-L`.

### Checking where a symlink points

`symlink_points_to` and `verify_symlink_target` from `scripts/fs.sh`:

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
for link in "${MANAGED_LINKS[@]}"; do
  install_managed_link "${link%%:*}" "${link#*:}"
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
~/.zshrc  ->  ~/.config/initd-backups/20260509120000/.zshrc
```

This is why `BACKUP_ROOT` must be set before calling `backup_path`.

## Testing strategy

### Behavior tests

```bash
scripts/test-install-behavior.sh
```

This is the most important test. It creates temporary `$HOME` directories and
checks the five core behaviors:

1. **Clean install** — all managed paths are symlinked on a fresh home
2. **Backup of unmanaged configs** — existing user files are moved to the backup dir
3. **Git profile switching** — the profile switcher updates `~/.gitconfig` correctly and re-running link.sh does not reset a manually chosen profile
4. **Cleanup** — only initd-owned symlinks are removed; unrelated symlinks and real files are left alone
5. **Directory folding** — an old layout of many file-level symlinks is collapsed into one direct directory symlink

These behave like integration tests, which is the right choice for setup scripts
because the risky thing is filesystem state, not individual functions.

### Syntax check

After editing a script, verify there are no syntax errors:

```bash
bash -n bootstrap.sh \
  platforms/darwin/bootstrap.sh \
  platforms/darwin/macos.sh \
  scripts/link.sh \
  scripts/cleanup.sh \
  scripts/git-profile.sh \
  scripts/logging.sh \
  scripts/fs.sh \
  scripts/paths.sh \
  scripts/test-install-behavior.sh
```

## How to safely change these scripts

1. **To add a new managed config:** add one line to `MANAGED_LINKS` in
   `scripts/paths.sh` and add a corresponding assertion to
   `test-install-behavior.sh`.
2. **To add a new Homebrew package:** run `./brewinstall <package>` from the
   repo root. It updates the Brewfile and installs it locally.
3. **Keep `main` readable as a checklist.** Put filesystem logic in
   `scripts/fs.sh` and path/profile knowledge in `scripts/paths.sh`.
4. **Run the behavior tests** after any filesystem-related change.
5. **Do not touch `nvim/`** unless the task explicitly asks for Neovim changes.
