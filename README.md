# initd

`initd` bootstraps a fresh development machine from one repo and one shell script. It supports both **macOS** and **Fedora Workstation** Linux from the same codebase.

It owns both:

- **machine setup**: Homebrew (mac) / dnf (linux), apps, runtimes, OS defaults, Hyprland desktop
- **user config**: Neovim, Ghostty, Fish, tmux, Git, Hyprland/Quickshell/rofi/dunst, and other dotfiles via managed symlinks

## Layout

Three top-level buckets. The platform directories are decoupled — `rm -rf macos/` or `rm -rf linux/` and the other platform keeps working.

```text
initd/
├── bootstrap.sh                 # dispatcher: detects uname -s and execs the platform bootstrap
├── shared/                      # cross-platform
│   ├── lib/                     # logging, fs, link, cleanup, git-profile
│   ├── managed-links.sh         # MANAGED_LINKS for shared configs + git helpers
│   ├── configs/                 # fish, git, ghostty, mise, nvim, starship, tmux
│   └── test.sh                  # behavior tests (auto-detects host OS)
├── macos/                       # self-contained macOS bootstrap
│   ├── bootstrap.sh
│   ├── Brewfile
│   ├── brewinstall / brewinstall.sh
│   ├── defaults.sh              # macOS defaults write …
│   ├── managed-links.sh
│   └── update.sh
└── linux/                       # self-contained Linux bootstrap
    ├── bootstrap.sh              # targets Fedora Workstation 44+ (dnf5)
    ├── packages.txt             # dnf package list (some via COPR — see below)
    ├── setup.sh                 # fonts/theme/Firefox profile glue
    ├── managed-links.sh
    ├── update.sh
    ├── scripts/                 # session scripts invoked by hyprland.lua/Quickshell
    └── configs/                 # hypr, quickshell, rofi, dunst, gtk-3.0, firefox
```

## Usage

```bash
git clone <repo-url> ~/.config/initd
bash ~/.config/initd/bootstrap.sh
```

The dispatcher runs `macos/bootstrap.sh` on Darwin and `linux/bootstrap.sh` on Linux. Both:

- install required packages (Homebrew or dnf, enabling COPRs on Linux where Fedora's own repos don't carry a package)
- install mise and gh (dnf repo on Linux, brew on macOS)
- link managed configs into `$HOME`, backing up unmanaged files to `~/.config/initd-backups/<timestamp>/`
- set fish as the login shell (`dscl` on macOS, `chsh` on Linux), then sync fisher plugins
- run `mise install` for shared runtimes and LSP tooling
- prompt for `personal`/`work` Git identity on first run (work stores a separate email in `local.gitconfig`)

Re-running is safe and idempotent.

## Common tasks

| Action | Command |
|---|---|
| Full bootstrap | `bash bootstrap.sh` |
| Re-apply links only | `shared/lib/link.sh <macos\|linux>` |
| Set Git identity | `shared/lib/git-profile.sh personal` / `work` |
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
| `~/.config/mise` | `shared/configs/mise/.config/mise` |
| `~/.config/nvim` | `shared/configs/nvim/.config/nvim` |
| `~/.config/starship.toml` | `shared/configs/starship/.config/starship.toml` |
| `~/.config/tmux` | `shared/configs/tmux/.config/tmux` |
| `~/.gitconfig` | `shared/configs/git/gitconfig` (work email override via `local.gitconfig`) |

### Linux-only

| Runtime path | Source |
|---|---|
| `~/.config/hypr` | `linux/configs/hypr` |
| `~/.config/hyprmoncfg` | `linux/configs/hyprmoncfg` |
| `~/.config/quickshell` | `linux/configs/quickshell` |
| `~/.config/rofi` | `linux/configs/rofi` |
| `~/.config/dunst` | `linux/configs/dunst` |
| `~/.config/fontconfig` | `linux/configs/fontconfig` |
| `~/.config/gtk-3.0` | `linux/configs/gtk-3.0` |
| `~/.config/pipewire` | `linux/configs/pipewire` |
| `~/.config/systemd/user/initd-hyprland-session.service` | `linux/configs/systemd/user/initd-hyprland-session.service` |
| `~/.gtkrc-2.0`, `~/.icons/default/index.theme`, Firefox profile glue | linked individually by `linux/setup.sh` (paths are dynamic or outside `~/.config/`) |

## Machine-local secrets

Two gitignored files — sourced/included if present, silently skipped if absent.

| File | Purpose |
|---|---|
| `shared/configs/git/local.gitconfig` | Work (or other) Git email override — absent on personal machines |
| `shared/configs/fish/.config/fish/local.fish` | Machine-specific env vars and overrides |

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

Docker comes via Colima (no Docker Desktop): the `colima`, `docker`, `docker-compose`, and `docker-credential-helper` formulas in the Brewfile, a managed VM template at `shared/configs/colima/`, and an `ensure_docker_config` bootstrap step that points `docker login` at the macOS Keychain and wires the brew-installed compose plugin into the docker CLI. See `docs/colima.md`.

## Linux — dnf specifics

`linux/packages.txt` is one package per line, comments allowed. Add to it and re-run `linux/bootstrap.sh`. The packages list intentionally tracks the brew formulas where equivalents exist (`fish`, `tmux`, `tig`, `git`, `gnupg2`, `neovim`) plus Fedora `-devel` build deps for mise-managed Python/Node. Fedora's own repos don't carry the Hyprland ecosystem, `hyprmoncfg`, or `ghostty` — `install_packages()` enables the `sdegler/hyprland`, `paolino/hyprmoncfg`, and `scottames/ghostty` COPRs first. Docker Engine is installed separately from Docker's official dnf repository, together with Buildx and the Compose v2 plugin; bootstrap adds the login user to the privileged `docker` group, so log out and back in once after its first installation. gh CLI and 1Password also come from their own official dnf repos.

`linux/setup.sh` handles things that don't fit the symlink flow:
- system fixes requiring sudo (`video` group membership for backlight keys)
- GTK theme + font/cursor gsettings (Fedora has no `fonts-ubuntu` or DMZ-cursor package, so this uses `Adwaita Sans` and the `Adwaita` cursor theme instead)
- session scripts symlinked to absolute `~/.config/` paths that hyprland.lua/Quickshell invoke directly
- the `hyprmoncfgd` user service for automatic monitor profile switching
- special-case paths outside `~/.config/`: `~/.gtkrc-2.0`, `~/.icons/default/`, Firefox profile files (profile path is dynamic; Firefox itself is unmanaged by bootstrap.sh — install it however you like, this glue configures whatever it finds)

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
- `docs/git-branching-conflicts.md` — Git branching and conflict resolution
- `docs/tmux-nvim.md` — tmux and Neovim workspace concepts
- `docs/tmux-sessions.md` — tmux session/window/pane workflow and keybindings
