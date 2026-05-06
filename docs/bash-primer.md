# Bash primer for initd

This repo intentionally uses Bash because setup is mostly command orchestration:
Homebrew, Git, mise, macOS defaults, symlinks, temporary files, and `$HOME`
paths. Keeping this in Bash means a fresh machine does not need Node, Go, or a
build step before bootstrap can run.

The goal is not "clever Bash". The goal is readable, defensive scripts that a
developer can follow like a checklist.

## Current script map

| File | Purpose |
|---|---|
| `bootstrap.sh` | Detect the operating system and hand off to the platform bootstrap. |
| `platforms/darwin/bootstrap.sh` | macOS setup checklist: Xcode CLT, Homebrew, Brewfile, Oh My Zsh, links, mise, macOS defaults, verification. |
| `scripts/link.sh` | Install managed config symlinks into `$HOME`, back up unmanaged files, and migrate known old initd layouts. |
| `scripts/cleanup.sh` | Remove only symlinks that are known to be owned by initd. |
| `scripts/git-profile.sh` | Switch `~/.gitconfig` between the curated Git profiles. |
| `scripts/brewinstall.sh` | Add a formula or cask to the curated Brewfile and apply it locally. |
| `scripts/fs.sh` | Shared filesystem safety helpers. |
| `scripts/paths.sh` | Shared list of paths initd owns or knows how to migrate. |
| `scripts/logging.sh` | Shared log formatting helpers. |
| `scripts/test-install-behavior.sh` | Behavior tests that run against temporary home directories. |

## How to read a script

Start at `main`, usually near the bottom. The larger scripts are written so
`main` reads like a plain-English checklist.

For example, `scripts/link.sh` is structured like this:

```bash
main() {
  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Target home directory: ${HOME}"
  log "Preparing legacy paths and existing config directories..."
  remove_old_initd_layout
  ensure_git_profile_link

  log "Linking managed config paths..."
  install_managed_links

  verify_all_links
}
```

If you only want to understand what the script does, read `main` first. Then
open the helper function whose name matches the step you care about.

## Design rules used here

1. **Keep policy data in one place.** `scripts/paths.sh` says which runtime paths
   initd owns and which legacy paths it can migrate.
2. **Keep filesystem mechanics in one place.** `scripts/fs.sh` owns helpers like
   `path_exists`, `symlink_points_to`, `backup_path`, and
   `verify_symlink_target`.
3. **Prefer readable helper names.** Names like
   `remove_old_initd_layout` and `install_managed_links` explain intent without
   requiring the reader to understand every Bash condition.
4. **Do not delete user files.** Existing unmanaged files are moved to
   `~/.config/initd-backups/<timestamp>/` before initd takes ownership.
5. **Only remove links initd owns.** Cleanup checks where each symlink points
   before removing it.
6. **Test with temporary homes.** The behavior tests exercise install, backup,
   cleanup, directory folding, Git profile switching, and legacy migration
   without touching your real `$HOME`.

## Important data lists

`scripts/paths.sh` contains the main ownership rules:

```bash
MANAGED_LINKS=(
  "${HOME}/.config/kitty:${ROOT_DIR}/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/nvim/.config/nvim"
  "${HOME}/.zshrc:${ROOT_DIR}/zsh/.zshrc"
  "${HOME}/.zprofile:${ROOT_DIR}/zsh/.zprofile"
)
```

Each item is `runtime path:repo source`. Scripts split those pairs like this:

```bash
path="${link%%:*}"
source="${link#*:}"
```

`LEGACY_LINKS` is similar, but it lists known old initd symlinks that are safe
to remove during migration or cleanup.

## Why links are direct

`scripts/link.sh` creates direct symlinks such as:

```text
~/.config/nvim -> ~/.config/initd/nvim/.config/nvim
~/.zshrc       -> ~/.config/initd/zsh/.zshrc
```

Direct links are easier to understand than a generic dotfile package manager for
this repo because the managed paths are small, explicit, and tested.

## Backups and safety

If initd finds a real file or unrelated symlink where it needs to install a
managed link, it backs that path up first:

```bash
backup_path "${path}"
```

`backup_path` preserves the home-relative path under one timestamped backup root.
For example:

```text
~/.zshrc -> ~/.config/initd-backups/<timestamp>/.zshrc
```

This is why scripts must set `BACKUP_ROOT` before calling `backup_path`.

## Bash syntax used most often

### Script header

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Option | Meaning |
|---|---|
| `-e` | Stop when a command fails. |
| `-u` | Fail when reading an unset variable. |
| `pipefail` | Fail a pipeline if any command in it fails. |

### Root directory

Most scripts compute the repo root from their own path:

```bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

This lets scripts work no matter which directory the user runs them from.

### Quoting

Always quote variables unless you intentionally want word splitting:

```bash
ln -s "${source}" "${path}"
```

### Path checks

Use helpers when possible:

```bash
if path_exists "${path}"; then
  backup_path "${path}"
fi

if symlink_points_to "${path}" "${expected}"; then
  rm "${path}"
fi
```

The helpers hide the `[[ -e ... || -L ... ]]` and symlink-resolution details.

### Loops over managed links

```bash
for link in "${MANAGED_LINKS[@]}"; do
  install_managed_link "${link%%:*}" "${link#*:}"
done
```

This is why adding a new managed config usually means adding one line to
`MANAGED_LINKS`, then updating tests/docs.

### Argument parsing

Small scripts parse arguments with `case`:

```bash
while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      return
      ;;
    *)
      log_error "Unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
  shift
done
```

## Logging

Use the shared logging helpers instead of raw `echo`:

```bash
log "Linking managed config paths..."
log_success "Managed symlinks verified."
log_warn "Backing up unmanaged ${path} -> ${backup}"
log_error "Managed path points to the wrong target: ${path}"
```

They keep output consistent and make it clear what is happening.

## Testing strategy

### Existing behavior tests

Run:

```bash
scripts/test-install-behavior.sh
```

This is the most important test. It creates temporary `$HOME` directories and
checks user-visible behavior:

- clean link install
- backup of unmanaged configs
- Git profile switching
- cleanup removes only initd-owned symlinks
- old file-level links fold into direct directory links
- legacy layouts migrate during normal link setup

These are closer to integration tests than tiny unit tests, but they are the
right default for setup scripts because the risky behavior is filesystem state.

### Can we write unit tests for Bash?

Yes, but use them selectively.

Good candidates for Bash unit tests:

- pure helper behavior in `scripts/fs.sh`
- path list parsing from `scripts/paths.sh`
- small functions that return success/failure without modifying real files

Poor candidates:

- full bootstrap flows
- Homebrew or mise orchestration
- functions that intentionally move or remove files

If we add unit tests later, the simplest dependency-free approach is another
Bash test script that sources helper files and uses `mktemp -d`:

```bash
ROOT_DIR="$(pwd)"
HOME="$(mktemp -d)"
source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"

ln -s "target" "${HOME}/link"
symlink_points_to "${HOME}/link" "${HOME}/target"
```

For now, avoid adding a test framework unless the helper logic grows. The current
behavior test gives better safety for the setup flows we care about.

## Validation commands

Run syntax checks after editing scripts:

```bash
bash -n bootstrap.sh platforms/darwin/bootstrap.sh platforms/darwin/macos.sh scripts/link.sh scripts/cleanup.sh scripts/git-profile.sh scripts/logging.sh scripts/fs.sh scripts/paths.sh scripts/test-install-behavior.sh
```

Check whitespace issues:

```bash
git diff --check
```

Run behavior tests:

```bash
scripts/test-install-behavior.sh
```

## How to safely change these scripts

1. Update the data list first if ownership changes.
2. Keep `main` readable as a checklist.
3. Put repeated filesystem logic in `scripts/fs.sh`.
4. Put repeated path/profile knowledge in `scripts/paths.sh`.
5. Prefer a clear helper over a clever one-liner.
6. Add or update a temporary-`HOME` behavior test for any filesystem change.
7. Do not touch `nvim/` unless the task explicitly asks for Neovim changes.

When Bash feels confusing, rename the function or extract a helper before
rewriting the setup in another language. For this repo, clear Bash is still the
lowest-dependency option.
