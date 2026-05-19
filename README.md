# initd

`initd` bootstraps a fresh development machine from one repo and one shell script. It supports both **macOS** and **Debian-based Linux** (Ubuntu, Linux Mint) from the same codebase.

It owns both:

- **machine setup**: Homebrew (mac) / apt (linux), apps, runtimes, OS defaults, i3 desktop
- **user config**: Neovim, Ghostty, Kitty, Fish, tmux, Git, i3/polybar/rofi/dunst, and other dotfiles via managed symlinks

## Layout

Three top-level buckets. The platform directories are decoupled — `rm -rf macos/` or `rm -rf linux/` and the other platform keeps working.

```text
initd/
├── bootstrap.sh                 # dispatcher: detects uname -s and execs the platform bootstrap
├── shared/                      # cross-platform
│   ├── lib/                     # logging, fs, link, cleanup, git-profile
│   ├── managed-links.sh         # MANAGED_LINKS for shared configs + git helpers
│   ├── configs/                 # fish, git, ghostty, kitty, mise, nvim, tmux
│   └── test.sh                  # behavior tests (auto-detects host OS)
├── macos/                       # self-contained macOS bootstrap
│   ├── bootstrap.sh
│   ├── Brewfile
│   ├── brewinstall / brewinstall.sh
│   ├── defaults.sh              # macOS defaults write …
│   ├── managed-links.sh
│   └── update.sh
└── linux/                       # self-contained Linux bootstrap
    ├── bootstrap.sh
    ├── packages.txt             # apt package list
    ├── setup.sh                 # xorg/wifi/picom hook/fonts/polybar patch/firefox/Xresources
    ├── managed-links.sh
    ├── update.sh
    ├── scripts/                 # systemd-sleep hooks
    └── configs/                 # i3, polybar, rofi, dunst, picom, gtk-3.0, xsettingsd, firefox
```

## Usage

```bash
git clone <repo-url> ~/.config/initd
bash ~/.config/initd/bootstrap.sh
```

The dispatcher runs `macos/bootstrap.sh` on Darwin and `linux/bootstrap.sh` on Linux. Both:

- install required packages (Homebrew or apt)
- install mise and gh (apt repo on Linux, brew on macOS)
- link managed configs into `$HOME`, backing up unmanaged files to `~/.config/initd-backups/<timestamp>/`
- set fish as the login shell (`dscl` on macOS, `chsh` on Linux), then sync fisher plugins
- run `mise install` for shared runtimes and LSP tooling
- prompt for `personal`/`work` Git profile and email on first run

Re-running is safe and idempotent.

## Common tasks

| Action | Command |
|---|---|
| Full bootstrap | `bash bootstrap.sh` |
| Re-apply links only | `shared/lib/link.sh <macos\|linux>` |
| Switch Git profile | `shared/lib/git-profile.sh personal` / `work` |
| Remove managed symlinks | `shared/lib/cleanup.sh <macos\|linux> --dry-run` |
| Add a brew formula/cask | `macos/brewinstall <name>` |
| Update tools | `macos/update.sh` or `linux/update.sh` |
| Run behavior tests | `shared/test.sh` |

## Managed config mapping

Runtime paths in `$HOME` are symlinks back into this repo. Editing happens **inside `initd`**, not at the live paths.

### Cross-platform (both OSes)

| Runtime path | Source |
|---|---|
| `~/.config/fish` | `shared/configs/fish/.config/fish` |
| `~/.config/ghostty` | `shared/configs/ghostty/.config/ghostty` |
| `~/.config/kitty` | `shared/configs/kitty/.config/kitty` |
| `~/.config/mise` | `shared/configs/mise/.config/mise` |
| `~/.config/nvim` | `shared/configs/nvim/.config/nvim` |
| `~/.config/tmux` | `shared/configs/tmux/.config/tmux` |
| `~/.gitconfig` | `shared/configs/git/profiles/{personal,work}.gitconfig` |

### Linux-only

| Runtime path | Source |
|---|---|
| `~/.config/i3` | `linux/configs/i3` |
| `~/.config/polybar` | `linux/configs/polybar` |
| `~/.config/rofi` | `linux/configs/rofi` |
| `~/.config/dunst` | `linux/configs/dunst` |
| `~/.config/picom` | `linux/configs/picom` |
| `~/.config/xsettingsd` | `linux/configs/xsettingsd` |
| `~/.config/gtk-3.0` | `linux/configs/gtk-3.0` |
| `~/.Xresources`, `~/.gtkrc-2.0`, `~/.icons/default/index.theme`, Firefox profile glue | linked individually by `linux/setup.sh` (paths are dynamic or outside `~/.config/`) |

## Machine-local secrets

Two gitignored files — sourced/included if present, silently skipped if absent.

| File | Purpose |
|---|---|
| `shared/configs/git/local.gitconfig` | Git email for this machine |
| `shared/configs/fish/.config/fish/local.fish` | Machine-specific env vars and overrides |

## Migrating an existing machine from the old flat layout

If a Mac already had `initd` bootstrapped before the three-bucket restructure
(where everything lived at the repo root in `fish/`, `git/`, `nvim/`, etc.),
run the one-shot migrator once after `git pull`. It moves the gitignored
machine-local files (`git/local.gitconfig`, `fish` local files, fisher
plugins, fish variables) into their new `shared/configs/...` locations and
clears empty old directories. Tracked files follow the rename automatically;
this only handles what `git pull` can't.

```bash
cd ~/.config/initd
git pull
shared/lib/migrate-from-flat-layout.sh
bash bootstrap.sh
```

The migrator is idempotent — safe to re-run, does nothing on a clean tree.

## Backups

If a managed runtime path already exists and isn't an initd symlink, it is moved to:

```
~/.config/initd-backups/<timestamp>/<original-path>
```

before initd takes ownership. Nothing is deleted.

## Line endings

`.gitattributes` enforces LF for `*.sh`, `*.fish`, `*.conf`, `*.ini`, etc. so commits from any host (including Windows) land as LF — the only line-ending bash and `/etc/`-style configs accept on macOS/Linux.

## macOS — Homebrew specifics

`macos/brewinstall <name>` detects whether the package is a formula or cask, appends it to `macos/Brewfile`, and runs `brew bundle`. `brew bundle dump --force --file macos/Brewfile` exports the current machine's state if you want a starting point — review carefully before committing.

`macos/bootstrap.sh` handles Docker Desktop quirks: skips the cask if `/Applications/Docker.app` already exists outside Homebrew, and force-reinstalls if the cask receipt exists but the app was deleted.

## Linux — apt specifics

`linux/packages.txt` is one package per line, comments allowed. Add to it and re-run `linux/bootstrap.sh`. The packages list intentionally tracks the brew formulas where equivalents exist (`fish`, `tmux`, `tig`, `git`, `gnupg`, `neovim`, `kitty`) plus Debian build deps for mise-managed Ruby/Python/Node.

`linux/setup.sh` handles four classes of thing that don't fit the symlink flow:
- system fixes requiring sudo (xorg TearFree, Intel BE200 WiFi d3cold udev rule, NetworkManager power save, swappiness, Chrome apt arch pin, power-profiles-daemon)
- systemd-sleep hooks (`picom-resume.sh`, `wifi-reconnect.sh`) copied into `/etc/systemd/system-sleep/`
- hardware-specific patching of `polybar/config.ini` (interface/battery/backlight names sed'd in based on `ip link`, `/sys/class/power_supply/`, `/sys/class/backlight/`)
- special-case paths outside `~/.config/`: `~/.Xresources`, `~/.gtkrc-2.0`, `~/.icons/default/`, Firefox profile files (profile path is dynamic)

## Adding a managed config

1. Cross-platform: drop the source under `shared/configs/<name>/`, add an entry to `MANAGED_LINKS` in `shared/managed-links.sh`.
2. macOS-only: drop under `macos/configs/<name>/`, append to `MANAGED_LINKS` in `macos/managed-links.sh`.
3. Linux-only: drop under `linux/configs/<name>/`, append in `linux/managed-links.sh`.

Then re-run `shared/test.sh`.

## Reference docs

- `docs/bash-primer.md` — repo-specific Bash patterns
- `docs/fish.md` — fish/bash/zsh syntax comparison
- `docs/nvim.md` — Neovim setup with Lazy.nvim
- `docs/mise.md` — mise tool management
