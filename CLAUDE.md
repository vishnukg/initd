# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the behavior test suite (auto-detects host OS; uses temporary home directories)
shared/test.sh

# Syntax-check every script
bash -n bootstrap.sh \
  shared/lib/logging.sh shared/lib/fs.sh \
  shared/lib/link.sh shared/lib/cleanup.sh shared/lib/git-profile.sh \
  shared/managed-links.sh shared/test.sh \
  macos/bootstrap.sh macos/defaults.sh macos/brewinstall.sh macos/update.sh macos/managed-links.sh \
  linux/bootstrap.sh linux/setup.sh linux/update.sh linux/managed-links.sh

# Full bootstrap (dispatches by uname)
bash bootstrap.sh

# Re-apply managed symlinks only
shared/lib/link.sh macos    # or: linux

# Switch the active Git profile
shared/lib/git-profile.sh personal
shared/lib/git-profile.sh work

# Preview / run cleanup
shared/lib/cleanup.sh <platform> --dry-run
shared/lib/cleanup.sh <platform>

# macOS — add a Homebrew package to the curated Brewfile and install it locally
macos/brewinstall <package>           # auto-detects formula vs cask
macos/brewinstall --cask <package>
macos/brewinstall --formula <package>

# Update tools (per platform)
macos/update.sh
linux/update.sh
```

## Architecture

Three top-level buckets, intentionally decoupled. The contract: `shared/` must not branch on OS; if it would need to, push that branch into the platform script.

```
initd/
├── bootstrap.sh              # ~20-line dispatcher: uname -s → macos|linux
├── shared/                   # cross-platform — sourced by both bootstraps
│   ├── lib/                  # logging.sh, fs.sh, link.sh, cleanup.sh, git-profile.sh
│   ├── managed-links.sh      # MANAGED_LINKS for shared configs + git helpers
│   ├── configs/              # fish, git, ghostty, kitty, mise, nvim, tmux
│   └── test.sh
├── macos/                    # self-contained — `rm -rf macos/` and Linux still works
│   ├── bootstrap.sh
│   ├── Brewfile
│   ├── brewinstall, brewinstall.sh
│   ├── defaults.sh           # macOS defaults write …
│   ├── managed-links.sh      # appends macOS-only links to MANAGED_LINKS
│   └── update.sh
└── linux/                    # self-contained — `rm -rf linux/` and macOS still works
    ├── bootstrap.sh
    ├── packages.txt          # apt package list (one per line)
    ├── setup.sh              # system fixes (xorg, wifi, picom hook, fonts, polybar patch)
    ├── managed-links.sh      # appends i3/polybar/rofi/dunst/picom links
    ├── update.sh
    ├── scripts/              # sleep/resume hooks copied into /etc/systemd/system-sleep/
    └── configs/              # i3, polybar, rofi, dunst, picom, gtk, xsettingsd, firefox, …
```

### Execution flow

```
bootstrap.sh
  └─ exec macos/bootstrap.sh                  # if uname=Darwin
  └─ exec linux/bootstrap.sh                  # if uname=Linux

macos/bootstrap.sh
  ├─ ensure_xcode_clt
  ├─ ensure_homebrew
  ├─ brew bundle --file macos/Brewfile
  ├─ shared/lib/link.sh macos                 # symlinks
  ├─ ensure_gh_auth, ensure_fish (dscl)
  ├─ mise install
  ├─ macos/defaults.sh
  └─ setup_git_profile (uses shared/lib/git-profile.sh)

linux/bootstrap.sh
  ├─ ensure_debian
  ├─ install apt packages from linux/packages.txt
  ├─ ensure_gh (official apt repo), ensure_mise (curl mise.run)
  ├─ shared/lib/link.sh linux                 # symlinks
  ├─ linux/setup.sh                           # xorg/wifi/picom hook/fonts/polybar patch
  ├─ ensure_gh_auth, ensure_fish (chsh)
  ├─ mise install
  └─ setup_git_profile
```

### Script sourcing chain

```
shared/lib/logging.sh           ← must be first; defines log_*, require_command, INITD_* color vars
shared/lib/fs.sh                ← filesystem helpers; requires logging.sh first
shared/managed-links.sh         ← MANAGED_LINKS (shared) + GIT_PROFILES_DIR + git-profile helpers; requires ROOT_DIR
<platform>/managed-links.sh     ← appends to MANAGED_LINKS; requires ROOT_DIR + initial MANAGED_LINKS
```

`ROOT_DIR` must be exported before sourcing `shared/managed-links.sh` because the array embeds absolute paths.

### MANAGED_LINKS — the ownership list

The single array `MANAGED_LINKS` is built in two steps:

1. `shared/managed-links.sh` defines the cross-platform entries (fish, ghostty, kitty, mise, nvim, tmux).
2. `<platform>/managed-links.sh` appends OS-only entries (currently nothing on macOS; i3/polybar/rofi/dunst/picom/xsettingsd/gtk-3.0 on Linux).

Entry format: `"home path:repo path"`. Scripts split with `home_path="${entry%%:*}"` / `repo_path="${entry#*:}"`.

`~/.gitconfig` is deliberately **not** in `MANAGED_LINKS` — it is handled separately in `link.sh` and `cleanup.sh` because the target file under `shared/configs/git/profiles/` varies by profile.

**Adding a managed config:**
- Cross-platform: add to `MANAGED_LINKS` in `shared/managed-links.sh` and place the source under `shared/configs/<name>/`.
- Platform-only: append to `MANAGED_LINKS` in `<platform>/managed-links.sh` and place the source under `<platform>/configs/<name>/`.

Then add a corresponding assertion in `shared/test.sh` (or rely on the generic `get_managed_links` loop, which iterates over whatever the host platform produces).

### Machine-local secrets

Two files are gitignored and never committed:

| File | Purpose |
|---|---|
| `shared/configs/git/local.gitconfig` | Git email for this machine |
| `shared/configs/fish/.config/fish/local.fish` | Machine-specific env vars and overrides |

Both follow the same pattern: sourced/included at startup if present, silently skipped if absent.

### Dotfile layout convention

Each managed package lives in a subdirectory that mirrors `$HOME`:

```
shared/configs/fish/.config/fish/    →  symlinked as ~/.config/fish
shared/configs/kitty/.config/kitty/  →  symlinked as ~/.config/kitty
linux/configs/i3/                    →  symlinked as ~/.config/i3
linux/configs/polybar/               →  symlinked as ~/.config/polybar
```

For shared/ the path inside the package mirrors `$HOME` exactly. For linux/ the configs live directly under `linux/configs/<name>/` (no `.config` prefix) because the source path is already namespaced by platform.

Edit files inside this repo, not through the live symlinks.

### Backup safety

`backup_path` in `shared/lib/fs.sh` moves any pre-existing unmanaged file to `${BACKUP_ROOT}/<relative-path>` before taking ownership. `BACKUP_ROOT` is exported by each platform's `bootstrap.sh` so re-applying links uses the same timestamped folder for the whole run.

### Line endings

`.gitattributes` enforces `eol=lf` for `*.sh`, `*.fish`, `*.conf`, `*.ini`, and other text files so commits from any host (including Windows) land as LF — the only line-ending bash and `/etc/`-style configs can parse on macOS or Linux.

### Linux-specific quirks

`linux/setup.sh` handles four classes of things that don't fit the standard symlink flow:

- **System fixes** that need sudo: xorg TearFree, Intel BE200 WiFi d3cold udev rule, NetworkManager power save, swappiness, Chrome apt arch pin, power-profiles-daemon enable.
- **Sleep/resume hooks** copied into `/etc/systemd/system-sleep/` from `linux/scripts/` (`picom-resume.sh`, `wifi-reconnect.sh`).
- **Hardware-specific config patching**: `polybar/config.ini` gets the live `interface`, `battery`, and `card` names sed'd in based on `ip link`, `/sys/class/power_supply/`, and `/sys/class/backlight/`. This mutates the source file under `linux/configs/polybar/` — symlinks pick it up immediately.
- **Special-case paths**: `~/.Xresources`, `~/.gtkrc-2.0`, `~/.icons/default/index.theme`, and Firefox profile files (dynamic profile path) live outside `~/.config/` and are linked individually rather than via `MANAGED_LINKS`.

### Reference docs

- `docs/bash-primer.md` — repo-specific Bash patterns
- `docs/fish.md` — fish/bash/zsh syntax comparison
- `docs/nvim.md` — Neovim plugin setup and Lazy.nvim usage
- `docs/mise.md` — mise tool management
