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
├── mise.toml                 # Runtime versions symlinked to ~/.config/mise/config.toml
├── git/                      # Stow package -> ~/.gitconfig
├── kitty/                    # Stow package -> ~/.config/kitty
├── nvim/                     # Stow package -> ~/.config/nvim
├── scripts/                  # Shared helper scripts
│   └── stow.sh
├── platforms/
│   └── darwin/
│       ├── Brewfile
│       ├── bootstrap.sh
│       └── macos.sh
```

## How it is set up

- **stow packages** (`git/`, `kitty/`, `nvim/`): the source of truth for files that end up in `$HOME`
- **`platforms/<os>/`**: package managers, OS defaults, and platform-specific setup
- **`mise.toml`**: shared language runtimes across platforms, symlinked to `~/.config/mise/config.toml`
- **`scripts/`**: shared helper scripts used by all platforms

### Stow package mapping

Each top-level package mirrors the final runtime location:

| Package in `initd` | Ends up at runtime |
|---|---|
| `git/.gitconfig` | `~/.gitconfig` |
| `git/.config/git/profiles/...` | `~/.config/git/profiles/...` |
| `kitty/.config/kitty/...` | `~/.config/kitty/...` |
| `nvim/.config/nvim/...` | `~/.config/nvim/...` |

That means you edit the files **inside `initd`**, and `stow` links them into the correct places in your home directory.

## How stow works

`bootstrap.sh` eventually runs `scripts/stow.sh`, which does:

```bash
stow --restow --dir ~/.config/initd --target "$HOME" git kitty nvim
```

`stow` creates symlinks from your home directory back into this repo. For example:

- `~/.config/nvim` -> `~/.config/initd/nvim/.config/nvim`
- `~/.config/kitty` -> `~/.config/initd/kitty/.config/kitty`
- `~/.gitconfig` -> `~/.config/initd/git/.gitconfig`

Because `--restow` is used, rerunning bootstrap is safe: existing managed links are refreshed in place.

## Git profiles

Git name is managed in `git/.gitconfig`, and the active email is selected via:

```bash
~/.config/git/profile.gitconfig
```

Bootstrap sets the default profile to **personal** on first run:

- personal -> `vishnukg@gmail.com`
- work -> `v.ganesan@xero.com`

To switch later:

```bash
~/.config/initd/scripts/git-profile.sh personal
~/.config/initd/scripts/git-profile.sh work
```

## Current macOS setup

The macOS flow installs:

- CLI tools and terminal utilities such as `git`, `gh`, `git-delta`, `ripgrep`, `fd`, `fzf`, `tmux`, `tig`, `zoxide`, and `stow`
- editor tooling: `neovim`, `tree-sitter`, `tree-sitter-cli`
- runtimes manager: `mise`
- runtimes via mise: `dotnet`, `go`, `node`, `python`, `ruby`, `terraform`
- apps: `BetterDisplay`, `Copilot CLI`, `Docker Desktop`, `Ghostty`, `iTerm2`, `Kitty`, and `Visual Studio Code`
- fonts including `FiraCode Nerd Font`, `Hack Nerd Font`, `JetBrains Mono Nerd Font`, `Meslo LG Nerd Font`, and `Victor Mono Nerd Font`
- managed configs into runtime paths such as `~/.config/nvim`, `~/.config/kitty`, and `~/.gitconfig`

See `platforms/darwin/Brewfile` for the authoritative package list.

## Usage

```bash
git clone <repo-url> ~/.config/initd
bash ~/.config/initd/bootstrap.sh
```

On a fresh machine, `bootstrap.sh` installs Homebrew packages, symlinks `~/.config/mise/config.toml` to this repo's `mise.toml`, installs runtimes from the repo root, and stows configs into place.

If Xcode Command Line Tools are missing, macOS will prompt for installation first. Re-run `bash ~/.config/initd/bootstrap.sh` after that finishes.

## Existing machine migration

If you already have files at `~/.config/nvim`, `~/.config/kitty`, or `~/.gitconfig`, `stow` will refuse to overwrite them.

```bash
bash ~/.config/initd/bootstrap.sh
```

If stow reports conflicts, move or delete the existing files first, then run bootstrap again.

If `/Applications/Docker.app` already exists but is not managed by Homebrew, bootstrap skips the `docker` cask instead of failing. A fresh machine still installs Docker normally.

## Updating configs later

Edit the source files in this repo, not the live symlinked paths.

Examples:

- Neovim config: `~/.config/initd/nvim/.config/nvim`
- Kitty config: `~/.config/initd/kitty/.config/kitty`
- Git config: `~/.config/initd/git/.gitconfig`
- Git profiles: `~/.config/initd/git/.config/git/profiles`
- Runtime versions: `~/.config/initd/mise.toml`

After editing, re-apply links with either:

```bash
~/.config/initd/scripts/stow.sh
```

or the full bootstrap:

```bash
bash ~/.config/initd/bootstrap.sh
```

For Neovim plugin changes, update the files under `nvim/.config/nvim`, then open Neovim and run your normal plugin workflow such as `:Lazy sync`.

For runtime version changes, edit `~/.config/initd/mise.toml`. Because `~/.config/mise/config.toml` is a symlink to that file, `mise up --bump` inside `~/.config/initd` updates the live global config too. Re-run `bash ~/.config/initd/bootstrap.sh` when you want bootstrap to refresh installed runtimes on the machine.

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
