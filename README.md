# initd

`initd` bootstraps a fresh development machine from one repo and one shell script.

It owns both:

- **machine setup**: Homebrew, apps, runtimes, macOS defaults
- **user config**: Neovim, Kitty, Git, and other dotfiles via managed symlinks

The repo is structured for **multi-platform support later**, while only **macOS** is implemented today.

## Layout

```text
initd/
├── brewinstall               # Add formulae/casks to the curated Brewfile and install them
├── bootstrap.sh              # OS dispatcher
├── docs/                     # Maintenance notes and Bash reference
├── git/                      # Git profiles -> ~/.gitconfig
├── kitty/                    # Source linked to ~/.config/kitty
├── mise/                     # Source linked to ~/.config/mise
├── nvim/                     # Source linked to ~/.config/nvim
├── zsh/                      # Source linked to ~/.zshrc and ~/.zprofile
├── scripts/                  # Shared helper scripts
│   ├── brewinstall.sh
│   ├── cleanup.sh
│   ├── fs.sh
│   ├── git-profile.sh
│   ├── link.sh
│   ├── logging.sh
│   ├── paths.sh
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
|---|---|---|
| `~/.gitconfig` | `git/profiles/personal.gitconfig` or `git/profiles/work.gitconfig` | `scripts/link.sh` and `scripts/git-profile.sh` |
| `~/.config/kitty` | `kitty/.config/kitty` | `scripts/link.sh` |
| `~/.config/mise` | `mise/.config/mise` | `scripts/link.sh` |
| `~/.config/nvim` | `nvim/.config/nvim` | `scripts/link.sh` |
| `~/.zshrc` | `zsh/.zshrc` | `scripts/link.sh` |
| `~/.zprofile` | `zsh/.zprofile` | `scripts/link.sh` |

That means you edit files **inside `initd`**, not the live paths in `$HOME`.

## How managed links work

`bootstrap.sh` eventually runs `scripts/link.sh`, which creates explicit symlinks from runtime paths in `$HOME` back to this repo. Git is linked directly to the active full profile file because `~/.gitconfig` is a single home-level compatibility file while profiles live under `initd/git/profiles`.

The resulting live symlinks are:

- `~/.config/nvim` -> `~/.config/initd/nvim/.config/nvim`
- `~/.config/kitty` -> `~/.config/initd/kitty/.config/kitty`
- `~/.config/mise` -> `~/.config/initd/mise/.config/mise`
- `~/.gitconfig` -> `~/.config/initd/git/profiles/personal.gitconfig` or `~/.config/initd/git/profiles/work.gitconfig`
- `~/.zshrc` -> `~/.config/initd/zsh/.zshrc`
- `~/.zprofile` -> `~/.config/initd/zsh/.zprofile`

For package roots such as `~/.config/kitty`, `~/.config/mise`, and `~/.config/nvim`, `scripts/link.sh` prefers direct directory symlinks. If an existing directory already contains only symlinks back into the matching `initd` package, the script folds it into one direct symlink.

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
| `~/.config/kitty` | `~/.config/initd-backups/<timestamp>/.config/kitty` |
| `~/.config/mise` | `~/.config/initd-backups/<timestamp>/.config/mise` |
| `~/.config/nvim` | `~/.config/initd-backups/<timestamp>/.config/nvim` |
| `~/.zshrc` | `~/.config/initd-backups/<timestamp>/.zshrc` |
| `~/.zprofile` | `~/.config/initd-backups/<timestamp>/.zprofile` |
| `~/.oh-my-zsh` | `~/.config/initd-backups/<timestamp>/.oh-my-zsh` |

The backup directory is outside the repo, so it is not linked and does not become config source.

## Git profiles

Each Git profile is a complete Git config. The files intentionally duplicate shared settings so switching profiles is just changing the `~/.gitconfig` symlink:

```bash
~/.config/initd/git/profiles/personal.gitconfig
~/.config/initd/git/profiles/work.gitconfig
```

Bootstrap sets the default profile to **personal** on first run:

- personal -> `vishnukg@gmail.com`
- work -> `v.ganesan@xero.com`

To switch later:

```bash
~/.config/initd/scripts/git-profile.sh personal
~/.config/initd/scripts/git-profile.sh work
```

The profile switcher updates `~/.gitconfig` directly. No common include file or `~/.config/git` runtime directory is needed.

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

- CLI tools and terminal utilities such as `git`, `gh`, `git-delta`, `ripgrep`, `fd`, `fzf`, `tmux`, `tig`, and `zoxide`
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

If Xcode Command Line Tools are missing, macOS will prompt for installation first. Re-run `bash ~/.config/initd/bootstrap.sh` after that finishes.

If you are new to maintaining these scripts, see [`docs/bash-primer.md`](docs/bash-primer.md) for a repo-specific Bash reference and [`docs/git-branching-conflicts.md`](docs/git-branching-conflicts.md) for Git branching, git-delta, and conflict resolution basics.

To safely check install, migration, and cleanup behavior without touching your real home directory:

```bash
~/.config/initd/scripts/test-install-behavior.sh
```

## Existing machine migration

If you already have files at managed config paths such as `~/.config/nvim`, `~/.config/kitty`, `~/.gitconfig`, `~/.zshrc`, `~/.zprofile`, or `~/.oh-my-zsh`, bootstrap moves unmanaged files into `~/.config/initd-backups/<timestamp>/`, refreshes clean Oh My Zsh checkouts, and makes `initd` the default setup.

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

- Neovim config: `~/.config/initd/nvim/.config/nvim`
- Kitty config: `~/.config/initd/kitty/.config/kitty`
- Git profiles: `~/.config/initd/git/profiles`
- Runtime versions: `~/.config/initd/mise/.config/mise/config.toml`
- Zsh startup: `~/.config/initd/zsh`

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

For Neovim plugin changes, update the files under `nvim/.config/nvim`, then open Neovim and run your normal plugin workflow such as `:Lazy sync`.

For runtime version changes, edit `~/.config/initd/mise/.config/mise/config.toml`. Because `~/.config/mise` is a symlink to that directory, changes are live immediately. Re-run `bash ~/.config/initd/bootstrap.sh` when you want bootstrap to refresh installed runtimes on the machine.

## Updating the curated Brewfile

`platforms/darwin/Brewfile` is intended to stay curated. Installing a package with `brew install` or `brew install --cask` does **not** update it automatically.

When you decide a package should be part of bootstrap:

1. Add it with `./brewinstall <package>`, `./brewinstall --cask <package>`, or `./brewinstall --formula <package>`.
2. Re-run `bash ~/.config/initd/bootstrap.sh` to confirm the curated list still applies cleanly.

`brewinstall` detects whether a package is a formula or cask when possible, updates `platforms/darwin/Brewfile`, and applies the Brewfile locally with `brew bundle`.

If you want Homebrew to dump your machine's current state as a starting point, you can use:

```bash
brew bundle dump --force --file ~/.config/initd/platforms/darwin/Brewfile
```

Review the result carefully before committing it. `brew bundle dump` exports everything installed on the current machine, which can add packages you do not want in the shared bootstrap.
