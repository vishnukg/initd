# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the behavior test suite (safe — uses temporary home directories, never touches real $HOME)
scripts/test-install-behavior.sh

# Syntax-check all scripts
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

# Add a Homebrew package to the curated Brewfile and install it locally
./brewinstall <package>           # auto-detects formula vs cask
./brewinstall --cask <package>
./brewinstall --formula <package>

# Re-apply managed symlinks only (no Homebrew or mise)
scripts/link.sh

# Switch the active Git profile
scripts/git-profile.sh personal
scripts/git-profile.sh work

# Preview what cleanup would remove, then remove it
scripts/cleanup.sh --dry-run
scripts/cleanup.sh

# Full bootstrap from scratch
bash bootstrap.sh
```

## Architecture

### Execution flow

```
bootstrap.sh                    ← OS dispatcher; reads uname -s
  └─ platforms/darwin/bootstrap.sh
       ├─ ensure_xcode_clt
       ├─ ensure_homebrew
       ├─ brew bundle           ← installs all Homebrew packages/casks
       ├─ scripts/link.sh       ← installs managed symlinks
       ├─ ensure_fish           ← registers shell, installs fisher, syncs plugins
       ├─ mise trust + install  ← installs all runtimes and LSP tooling
       ├─ platforms/darwin/macos.sh
       └─ setup_git_profile     ← prompts once, skipped if already configured
```

### Script sourcing chain

Scripts source each other in a fixed order. Do not break it:

```
logging.sh          ← must be first; defines log_*, require_command, INITD_* color vars
  └─ fs.sh          ← filesystem helpers; requires logging.sh to already be sourced
       └─ paths.sh  ← MANAGED_LINKS list and git-profile helpers; requires fs.sh
```

`ROOT_DIR` must be set before sourcing `paths.sh` because `MANAGED_LINKS` embeds absolute paths.

### MANAGED_LINKS — the ownership list

`scripts/paths.sh` is the single source of truth for which runtime paths initd owns:

```bash
MANAGED_LINKS=(
  "${HOME}/.config/fish:${ROOT_DIR}/fish/.config/fish"
  ...
)
```

Format: `runtime path in $HOME : source path in repo`. Scripts split entries with `path="${link%%:*}"` / `src="${link#*:}"`.

`~/.gitconfig` is deliberately **not** in `MANAGED_LINKS` — it is handled separately in `link.sh` and `cleanup.sh` because it can point to any file under `git/profiles/`.

**Adding a new managed config:** add one entry to `MANAGED_LINKS` in `scripts/paths.sh` and add a corresponding assertion to `scripts/test-install-behavior.sh`.

### Machine-local secrets

Two files are gitignored and never committed:

| File | Purpose |
|---|---|
| `git/local.gitconfig` | Git email for this machine |
| `fish/.config/fish/local.fish` | Machine-specific env vars and overrides |

Both follow the same pattern: sourced/included at startup if present, silently skipped if absent.

### Dotfile layout convention

Each managed package lives in a subdirectory that mirrors `$HOME`:

```
fish/.config/fish/    →  symlinked as ~/.config/fish
kitty/.config/kitty/  →  symlinked as ~/.config/kitty
```

This means the relative path inside the package directory matches where the file lives in the real filesystem. Edit files inside this repo, not through the live symlinks.

### Backup safety

`backup_path` in `scripts/fs.sh` moves any pre-existing unmanaged file to `${BACKUP_ROOT}/.config/<original-path>` before taking ownership. `BACKUP_ROOT` is exported by `platforms/darwin/bootstrap.sh` so that re-running `scripts/link.sh` from bootstrap uses the same timestamped folder for the whole run.

### Reference docs

- `docs/bash-primer.md` — repo-specific Bash patterns, design rules, testing strategy
- `docs/fish.md` — fish/bash/zsh syntax comparison
- `docs/nvim.md` — Neovim plugin setup and Lazy.nvim usage
- `docs/mise.md` — mise tool management
