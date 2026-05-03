# initd

`initd` bootstraps a fresh development machine from one repo and one shell script.

It owns both:

- **machine setup**: Homebrew, apps, runtimes, macOS defaults
- **user config**: Neovim, Kitty, Git, and other dotfiles via GNU Stow

The repo is structured for **multi-platform support later**, while only **macOS** is implemented today.

## Layout

```text
initd/
├── bootstrap.sh              # OS dispatcher
├── docs/                     # Maintenance notes and Bash reference
├── git/                      # Source of truth -> ~/.gitconfig
├── kitty/                    # Stow package -> ~/.config/kitty
├── mise/                     # Stow package -> ~/.config/mise
├── nvim/                     # Stow package -> ~/.config/nvim
├── zsh/                      # Stow package -> ~/.zshrc and ~/.zprofile
├── scripts/                  # Shared helper scripts
│   ├── cleanup.sh
│   ├── fs.sh
│   ├── git-profile.sh
│   ├── logging.sh
│   ├── stow.sh
│   └── test-install-behavior.sh
├── platforms/
│   └── darwin/
│       ├── Brewfile
│       ├── bootstrap.sh
│       └── macos.sh
```

## How it is set up

- **managed packages** (`git/`, `kitty/`, `mise/`, `nvim/`, `zsh/`): the source of truth for files that end up in `$HOME`
- **`platforms/<os>/`**: package managers, OS defaults, and platform-specific setup
- **`scripts/`**: shared helper scripts used by all platforms

### Managed config mapping

`initd` is the source of truth. Runtime config paths in `$HOME` are symlinks back into this repo:

| Runtime path | Source in `initd` | Managed by |
|---|---|
| `~/.gitconfig` | `git/.gitconfig` | `scripts/stow.sh` |
| `~/.config/kitty` | `kitty/.config/kitty` | GNU Stow via `scripts/stow.sh` |
| `~/.config/mise` | `mise/.config/mise` | GNU Stow via `scripts/stow.sh` |
| `~/.config/nvim` | `nvim/.config/nvim` | GNU Stow via `scripts/stow.sh` |
| `~/.zshrc` | `zsh/.zshrc` | GNU Stow via `scripts/stow.sh` |
| `~/.zprofile` | `zsh/.zprofile` | GNU Stow via `scripts/stow.sh` |

That means you edit files **inside `initd`**, not the live paths in `$HOME`.

## How stow works

`bootstrap.sh` eventually runs `scripts/stow.sh`, which stows:

```bash
stow --restow --dir ~/.config/initd --target "$HOME" kitty mise nvim zsh
```

Git is handled separately because `~/.gitconfig` is a single home-level compatibility file while the rest of the Git source lives under `initd/git`:

- `~/.gitconfig` is linked directly to `~/.config/initd/git/.gitconfig`

The resulting live symlinks are:

- `~/.config/nvim` -> `~/.config/initd/nvim/.config/nvim`
- `~/.config/kitty` -> `~/.config/initd/kitty/.config/kitty`
- `~/.config/mise` -> `~/.config/initd/mise/.config/mise`
- `~/.gitconfig` -> `~/.config/initd/git/.gitconfig`
- `~/.zshrc` -> `~/.config/initd/zsh/.zshrc`
- `~/.zprofile` -> `~/.config/initd/zsh/.zprofile`

For package roots such as `~/.config/kitty`, `~/.config/mise`, and `~/.config/nvim`, `scripts/stow.sh` prefers direct directory symlinks. If an existing directory already contains only symlinks back into the matching `initd` package, the script folds it into one direct symlink.

Because `--restow` is used, rerunning bootstrap is safe: existing managed links are refreshed in place. The stow step also does a follow-up verification pass and fails if any managed links are still missing.

## Existing config backups

On an existing machine, bootstrap makes `initd` the default setup without deleting your old unmanaged configs.

If a managed runtime path already exists and is not an `initd` symlink, `scripts/stow.sh` moves it to:

```text
~/.config/initd-backups/<timestamp>/<original-path>
```

Examples:

| Existing unmanaged path | Backup path |
|---|---|
| `~/.gitconfig` | `~/.config/initd-backups/<timestamp>/.gitconfig` |
| `~/.config/kitty` | `~/.config/initd-backups/<timestamp>/.config/kitty` |
| `~/.config/mise` | `~/.config/initd-backups/<timestamp>/.config/mise` |
| `~/.config/nvim` | `~/.config/initd-backups/<timestamp>/.config/nvim` |
| `~/.zshrc` | `~/.config/initd-backups/<timestamp>/.zshrc` |
| `~/.zprofile` | `~/.config/initd-backups/<timestamp>/.zprofile` |
| `~/.oh-my-zsh` | `~/.config/initd-backups/<timestamp>/.oh-my-zsh` |
| legacy `~/.config/git` | `~/.config/initd-backups/<timestamp>/.config/git` |
| legacy `~/.config/zsh` | `~/.config/initd-backups/<timestamp>/.config/zsh` |

The backup directory is outside the repo, so it is not stowed and does not become config source.

## Git profiles

Git name is managed in `git/.gitconfig`, and the active email is selected by the repo-local symlink:

```bash
~/.config/initd/git/profile.gitconfig
```

`git/.gitconfig` includes that file directly:

```ini
[include]
	path = ~/.config/initd/git/profile.gitconfig
```

Bootstrap sets the default profile to **personal** on first run:

- personal -> `vishnukg@gmail.com`
- work -> `v.ganesan@xero.com`

To switch later:

```bash
~/.config/initd/scripts/git-profile.sh personal
~/.config/initd/scripts/git-profile.sh work
```

The profile switcher updates `git/profile.gitconfig` inside the repo. No `~/.config/git` runtime directory is needed.

## Zsh and Oh My Zsh

Zsh startup files are managed by `initd`:

```text
~/.zshrc     -> ~/.config/initd/zsh/.zshrc
~/.zprofile  -> ~/.config/initd/zsh/.zprofile
```

Bootstrap installs Oh My Zsh into:

```text
~/.oh-my-zsh
```

If `~/.oh-my-zsh` already exists as a clean Oh My Zsh checkout, bootstrap fetches and fast-forwards it. If it is missing, is not an Oh My Zsh checkout, has unmanaged changes, or cannot be fast-forwarded, bootstrap backs it up to `~/.config/initd-backups/<timestamp>/.oh-my-zsh` before cloning a fresh copy.

The managed `.zshrc`:

1. Loads Homebrew shell environment when available
2. Sets `ZSH="${HOME}/.oh-my-zsh"`
3. Sources `oh-my-zsh.sh`
4. Enables the `git` Oh My Zsh plugin
5. Initializes `zoxide`, `mise`, and `starship` when those commands are installed

## Current macOS setup

The macOS flow installs:

- CLI tools and terminal utilities such as `git`, `gh`, `git-delta`, `ripgrep`, `fd`, `fzf`, `tmux`, `tig`, `zoxide`, and `stow`
- editor tooling: `neovim`, `tree-sitter`, `tree-sitter-cli`
- runtimes manager: `mise`
- runtimes via mise: `dotnet`, `go`, `node`, `python`, `ruby`, `terraform`
- shell framework: Oh My Zsh installed into `~/.oh-my-zsh`
- apps: `BetterDisplay`, `Copilot CLI`, `Docker Desktop`, `Ghostty`, `iTerm2`, `Kitty`, and `Visual Studio Code`
- fonts including `FiraCode Nerd Font`, `Hack Nerd Font`, `JetBrains Mono Nerd Font`, `Meslo LG Nerd Font`, and `Victor Mono Nerd Font`
- managed configs into runtime paths such as `~/.config/nvim`, `~/.config/kitty`, and `~/.gitconfig`

See `platforms/darwin/Brewfile` for the authoritative package list.

## Usage

```bash
git clone <repo-url> ~/.config/initd
bash ~/.config/initd/bootstrap.sh
```

On a fresh machine, `bootstrap.sh` installs Homebrew packages, installs Oh My Zsh, links configs into place, trusts the managed mise config, and installs runtimes from the repo root.

Bootstrap verifies that all managed runtime config paths are symlinks into `~/.config/initd`.

If Xcode Command Line Tools are missing, macOS will prompt for installation first. Re-run `bash ~/.config/initd/bootstrap.sh` after that finishes.

If you are new to maintaining these scripts, see [`docs/bash-primer.md`](docs/bash-primer.md) for a repo-specific Bash reference.

To safely check install, migration, and cleanup behavior without touching your real home directory:

```bash
~/.config/initd/scripts/test-install-behavior.sh
```

## Existing machine migration

If you already have files at managed config paths such as `~/.config/nvim`, `~/.config/kitty`, `~/.gitconfig`, `~/.zshrc`, `~/.zprofile`, or `~/.oh-my-zsh`, bootstrap moves unmanaged files into `~/.config/initd-backups/<timestamp>/`, refreshes clean Oh My Zsh checkouts, and makes `initd` the default setup.

```bash
bash ~/.config/initd/bootstrap.sh
```

A rerun only reports success after stow verifies there is no remaining link work to do.

If `/Applications/Docker.app` already exists but is not managed by Homebrew, bootstrap skips the `docker-desktop` cask instead of failing. A fresh machine still installs Docker Desktop normally, and bootstrap verifies Docker Desktop is present after `brew bundle`.

## Updating configs later

Edit the source files in this repo, not the live symlinked paths.

Examples:

- Neovim config: `~/.config/initd/nvim/.config/nvim`
- Kitty config: `~/.config/initd/kitty/.config/kitty`
- Git config: `~/.config/initd/git/.gitconfig`
- Git profiles: `~/.config/initd/git/profiles`
- Runtime versions: `~/.config/initd/mise/.config/mise/config.toml`
- Zsh startup: `~/.config/initd/zsh`

After editing, re-apply links with either:

```bash
~/.config/initd/scripts/stow.sh
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

To remove only legacy symlinks from older `initd` layouts without touching current managed symlinks:

```bash
~/.config/initd/scripts/cleanup.sh --legacy-only
```

Legacy-only cleanup is useful after migrating from older layouts that used `~/.config/git`, `~/.config/zsh`, or `zsh-home/.zshrc`.

For Neovim plugin changes, update the files under `nvim/.config/nvim`, then open Neovim and run your normal plugin workflow such as `:Lazy sync`.

For runtime version changes, edit `~/.config/initd/mise/.config/mise/config.toml`. Because `~/.config/mise` is a symlink to that directory, changes are live immediately. Re-run `bash ~/.config/initd/bootstrap.sh` when you want bootstrap to refresh installed runtimes on the machine.

## Updating the curated Brewfile

`platforms/darwin/Brewfile` is intended to stay curated. Installing a package with `brew install` or `brew install --cask` does **not** update it automatically.

When you decide a package should be part of bootstrap:

1. Add or remove the relevant `brew` or `cask` entry in `platforms/darwin/Brewfile`.
2. Re-run `bash ~/.config/initd/bootstrap.sh` to confirm the curated list still applies cleanly.

If you want Homebrew to dump your machine's current state as a starting point, you can use:

```bash
brew bundle dump --force --file ~/.config/initd/platforms/darwin/Brewfile
```

Review the result carefully before committing it. `brew bundle dump` exports everything installed on the current machine, which can add packages you do not want in the shared bootstrap.
