# initd

`initd` bootstraps a fresh development machine from one repo and one shell script.

It owns both:

- **machine setup**: Homebrew, apps, runtimes, macOS defaults
- **user config**: Neovim, Kitty, Fish, tmux, Git, and other dotfiles via managed symlinks

The repo is intentionally macOS-focused today so the bootstrap path stays easy to follow.

## Layout

```text
initd/
├── brewinstall               # Add formulae/casks to the curated Brewfile and install them
├── Brewfile                  # Homebrew packages, apps, and fonts
├── bootstrap.sh              # macOS bootstrap
├── docs/                     # Maintenance notes and reference guides
├── fish/                     # Source linked to ~/.config/fish
├── git/                      # Git profiles -> ~/.gitconfig (local.gitconfig is gitignored)
├── kitty/                    # Source linked to ~/.config/kitty
├── mise/                     # Source linked to ~/.config/mise
├── nvim/                     # Source linked to ~/.config/nvim
├── tmux/                     # Source linked to ~/.config/tmux
├── scripts/                  # Shared helper scripts
│   ├── brewinstall.sh
│   ├── cleanup.sh
│   ├── fs.sh
│   ├── git-profile.sh
│   ├── link.sh
│   ├── logging.sh
│   ├── macos.sh
│   ├── managed-configs.sh
│   ├── test-install-behavior.sh
│   └── update.sh
```

## How it is set up

- **managed packages** (`fish/`, `git/`, `kitty/`, `mise/`, `nvim/`, `tmux/`): the source of truth for files that end up in `$HOME`
- **`Brewfile` and `bootstrap.sh`**: macOS package and machine setup
- **`scripts/`**: helper scripts for links, cleanup, Git profiles, and macOS defaults

### Maintenance map

| To change | Edit |
|---|---|
| Bootstrap order or machine setup | `bootstrap.sh` |
| Homebrew packages, apps, or fonts | `Brewfile` or `./brewinstall <package>` |
| macOS defaults | `scripts/macos.sh` |
| Managed dotfile paths | `scripts/managed-configs.sh`, then `scripts/test-install-behavior.sh` |
| Link, backup, or cleanup safety | `scripts/link.sh`, `scripts/cleanup.sh`, and `scripts/fs.sh` |
| Git profile switching | `scripts/git-profile.sh` |
| Package and runtime upgrades | `scripts/update.sh` |

### Managed config mapping

`initd` is the source of truth. Runtime config paths in `$HOME` are symlinks back into this repo:

| Runtime path | Source in `initd` | Managed by |
|---|---|---|
| `~/.gitconfig` | `git/profiles/personal.gitconfig` or `git/profiles/work.gitconfig` | `scripts/link.sh` and `scripts/git-profile.sh` |
| `~/.config/fish` | `fish/.config/fish` | `scripts/link.sh` |
| `~/.config/kitty` | `kitty/.config/kitty` | `scripts/link.sh` |
| `~/.config/mise` | `mise/.config/mise` | `scripts/link.sh` |
| `~/.config/nvim` | `nvim/.config/nvim` | `scripts/link.sh` |
| `~/.config/tmux` | `tmux/.config/tmux` | `scripts/link.sh` |

That means you edit files **inside `initd`**, not the live paths in `$HOME`.

## How managed links work

`bootstrap.sh` eventually runs `scripts/link.sh`, which creates explicit symlinks from runtime paths in `$HOME` back to this repo. Git is linked directly to the active full profile file because `~/.gitconfig` is a single home-level compatibility file while profiles live under `initd/git/profiles`.

The resulting live symlinks are:

- `~/.config/fish` -> `~/.config/initd/fish/.config/fish`
- `~/.config/kitty` -> `~/.config/initd/kitty/.config/kitty`
- `~/.config/mise` -> `~/.config/initd/mise/.config/mise`
- `~/.config/nvim` -> `~/.config/initd/nvim/.config/nvim`
- `~/.config/tmux` -> `~/.config/initd/tmux/.config/tmux`
- `~/.gitconfig` -> `~/.config/initd/git/profiles/personal.gitconfig` or `~/.config/initd/git/profiles/work.gitconfig`

Rerunning bootstrap is safe: existing managed links are left in place, unmanaged files are backed up before initd takes ownership, and the link step exits if any managed link is missing or points to the wrong source.

## Existing config backups

On an existing machine, bootstrap makes `initd` the default setup without deleting your old unmanaged configs.

If a managed runtime path already exists and is not an `initd` symlink, `scripts/link.sh` moves it to:

```text
~/.config/initd-backups/<timestamp>/<original-path>
```

Examples:

| Existing unmanaged path | Backup path |
|---|---|
| `~/.gitconfig` | `~/.config/initd-backups/<timestamp>/.gitconfig` |
| `~/.config/fish` | `~/.config/initd-backups/<timestamp>/.config/fish` |
| `~/.config/kitty` | `~/.config/initd-backups/<timestamp>/.config/kitty` |
| `~/.config/mise` | `~/.config/initd-backups/<timestamp>/.config/mise` |
| `~/.config/nvim` | `~/.config/initd-backups/<timestamp>/.config/nvim` |
| `~/.config/tmux` | `~/.config/initd-backups/<timestamp>/.config/tmux` |

The backup directory is outside the repo, so it is not linked and does not become config source.

## Git profiles

Each Git profile is a complete Git config. The files intentionally duplicate shared settings so switching profiles is just changing the `~/.gitconfig` symlink:

```bash
~/.config/initd/git/profiles/personal.gitconfig
~/.config/initd/git/profiles/work.gitconfig
```

### Email

Email is **not stored in the committed profile files** — it lives in `git/local.gitconfig`, which is gitignored and never pushed. Each machine has its own copy with the appropriate email.

Bootstrap prompts for machine type and email on first run:

```
:: Machine type [personal/work] (default: personal): work
:: Git email for this machine: you@example.com
```

If `local.gitconfig` already has an email (e.g. re-running bootstrap), the prompt is skipped.

To change the email later, delete the local file and re-run the profile switcher:

```bash
rm ~/.config/initd/git/local.gitconfig
~/.config/initd/scripts/git-profile.sh work
```

### Switching profiles

```bash
~/.config/initd/scripts/git-profile.sh personal
~/.config/initd/scripts/git-profile.sh work
```

The profile switcher symlinks `~/.gitconfig` to the chosen profile and prompts for email if `local.gitconfig` is missing.

## Fish shell

Fish is the default shell. Bootstrap installs it via Homebrew, registers it in `/etc/shells`, sets it as the login shell via `dscl`, and syncs plugins with [Fisher](https://github.com/jorgebucaran/fisher).

The managed config:

```text
~/.config/fish  ->  ~/.config/initd/fish/.config/fish
```

Plugins are declared in `fish/.config/fish/fish_plugins` and installed by bootstrap:

- [`patrickf1/fzf.fish`](https://github.com/patrickf1/fzf.fish) — fzf key bindings (`Ctrl+R` history, `Ctrl+Alt+F` files, `Ctrl+Alt+L` git log)

The managed `config.fish`:

1. Loads Homebrew shell environment for Apple Silicon
2. Adds mise shims to `PATH` and disables Homebrew's automatic mise fish hook
3. Sets the Nord color theme directly, without running `fish_config` at startup
4. Enables vi key bindings (with `Ctrl+A`/`Ctrl+E` restored in insert mode)
5. Defines `vi`/`vim` aliases to `nvim` and a full set of git abbreviations
6. Initializes `zoxide` and `starship` when those commands are available

To add or update plugins, edit `fish_plugins` and run `fisher update` inside fish, then commit the updated plugin files.

### Machine-local fish overrides

`config.fish` sources `~/.config/fish/local.fish` at startup if the file exists. Use it for machine-specific env vars that should not be committed — same pattern as `git/local.gitconfig`. The path is gitignored.

Create it on each machine as needed:

```fish
# ~/.config/fish/local.fish  (not committed)
set -gx MY_SECRET value
```

GitHub authentication for mise and fisher is handled via `gh auth login` — no token needs to be stored here. mise is configured to call `gh auth token` directly, and bootstrap passes the same token to fisher scoped to that subprocess only.

See [`docs/fish.md`](docs/fish.md) for a fish/bash/zsh syntax reference.

## tmux

tmux config is managed by `initd`:

```text
~/.config/tmux  ->  ~/.config/initd/tmux/.config/tmux
```

Key bindings in the managed `tmux.conf`:

| Key | Action |
|---|---|
| `Ctrl+Space` | Prefix (replaces default `Ctrl+B`) |
| `prefix n` | New window (in current path) |
| `prefix Tab` / `prefix BTab` | Next / previous window |
| `prefix s` | Horizontal split (in current path) |
| `prefix v` | Vertical split (in current path) |
| `Alt+h/j/k/l` | Move between panes (no prefix needed) |

Windows and panes start at index 1 and renumber automatically when closed.

## Current macOS setup

The macOS flow installs:

- system utilities via Homebrew: `git`, `fish`, `tmux`, `tig`, `gnu-sed`, `gnupg`, `neovim`, and build deps (`autoconf`, `gmp`, `libyaml`, `openssl@3`, `readline`, `ruby-build`)
- runtimes + dev tools via mise: `go`, `node`, `python`, `ruby`, `dotnet`, `terraform`, `gh`, `git-delta`, `ripgrep`, `fd`, `fzf`, `lazygit`, `glow`, `starship`, `zoxide`, `tree-sitter`, `openfga`, and all LSP servers, linters, and formatters
- apps: `BetterDisplay`, `Claude Code`, `Copilot CLI`, `Docker Desktop`, `Ghostty`, `iTerm2`, `Kitty`, and `Visual Studio Code`
- fonts: `FiraCode Nerd Font`, `Hack Nerd Font`, `JetBrains Mono Nerd Font`, `Meslo LG Nerd Font`, and `Victor Mono Nerd Font`
- managed configs into runtime paths such as `~/.config/nvim`, `~/.config/fish`, `~/.config/kitty`, and `~/.gitconfig`

See `Brewfile` for the Homebrew package list and `mise/.config/mise/config.toml` for all mise-managed tool versions.

## Usage

```bash
git clone <repo-url> ~/.config/initd
bash ~/.config/initd/bootstrap.sh
```

On a fresh machine, `bootstrap.sh` installs Homebrew packages, sets fish as the default shell, syncs fisher plugins, links configs into place, trusts the managed mise config, installs runtimes and LSP tooling via mise, and at the end prompts for machine type and Git email:

```
:: Machine type [personal/work] (default: personal): work
:: Git email for this machine: you@example.com
```

If Xcode Command Line Tools are missing, macOS will prompt for installation first. Re-run `bash ~/.config/initd/bootstrap.sh` after that finishes.

If you are new to maintaining these scripts, see [`docs/bash-primer.md`](docs/bash-primer.md) for a repo-specific Bash reference, [`docs/fish.md`](docs/fish.md) for fish shell syntax, and [`docs/git-branching-conflicts.md`](docs/git-branching-conflicts.md) for Git branching, git-delta, and conflict resolution basics.

To safely check install, migration, and cleanup behavior without touching your real home directory:

```bash
~/.config/initd/scripts/test-install-behavior.sh
```

## Existing machine migration

If you already have files at managed config paths such as `~/.config/fish`, `~/.config/nvim`, `~/.config/kitty`, or `~/.gitconfig`, bootstrap moves unmanaged files into `~/.config/initd-backups/<timestamp>/` and makes `initd` the default setup.

```bash
bash ~/.config/initd/bootstrap.sh
```

### Docker Desktop

Bootstrap handles Docker Desktop in all situations:

| Situation | What happens |
|---|---|
| Not installed | `brew bundle` installs it normally |
| Installed via Homebrew | `brew bundle` sees it is already there and skips it |
| Installed manually (no Homebrew receipt) | Stripped from the install list before `brew bundle` runs to avoid a conflict error |
| Receipt exists but app was deleted | Detected after `brew bundle` and force-reinstalled with `brew reinstall` |

## Updating configs later

Edit the source files in this repo, not the live symlinked paths.

Examples:

- Fish config: `~/.config/initd/fish/.config/fish`
- Neovim config: `~/.config/initd/nvim/.config/nvim`
- tmux config: `~/.config/initd/tmux/.config/tmux`
- Kitty config: `~/.config/initd/kitty/.config/kitty`
- Git profiles: `~/.config/initd/git/profiles`
- Runtime versions: `~/.config/initd/mise/.config/mise/config.toml`

After editing, re-apply links with either:

```bash
~/.config/initd/scripts/link.sh
```

or the full bootstrap:

```bash
bash ~/.config/initd/bootstrap.sh
```

## Cleanup

To remove initd-managed symlinks from a machine without deleting any source files in this repo:

```bash
~/.config/initd/scripts/cleanup.sh --dry-run
~/.config/initd/scripts/cleanup.sh
```

Cleanup only removes known symlinks that point back into `~/.config/initd`. Non-symlink files and unrelated symlinks are left in place.

For Neovim plugin changes, update the files under `nvim/.config/nvim`, then open Neovim and run `:Lazy sync`. See [`docs/nvim.md`](docs/nvim.md) for details on the plugin setup.

For runtime version changes, edit `~/.config/initd/mise/.config/mise/config.toml`. Because `~/.config/mise` is a symlink to that directory, changes are live immediately. Re-run `bash ~/.config/initd/bootstrap.sh` when you want bootstrap to refresh installed runtimes on the machine.

## Updating installed tools

Bootstrap does not run a full Homebrew upgrade. To intentionally update installed tools, run:

```bash
~/.config/initd/scripts/update.sh
```

This runs `brew update`, `brew upgrade`, `brew cleanup`, and `mise upgrade --yes`.

## Updating the curated Brewfile

`Brewfile` is intended to stay curated. Installing a package with `brew install` or `brew install --cask` does **not** update it automatically.

When you decide a package should be part of bootstrap:

1. Add it with `./brewinstall <package>`, `./brewinstall --cask <package>`, or `./brewinstall --formula <package>`.
2. Re-run `bash ~/.config/initd/bootstrap.sh` to confirm the curated list still applies cleanly.

`brewinstall` detects whether a package is a formula or cask when possible, updates `Brewfile`, and applies it locally with `brew bundle`.

If you want Homebrew to dump your machine's current state as a starting point, you can use:

```bash
brew bundle dump --force --file ~/.config/initd/Brewfile
```

Review the result carefully before committing it. `brew bundle dump` exports everything installed on the current machine, which can add packages you do not want in the shared bootstrap.
