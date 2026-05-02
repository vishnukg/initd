# initd

`initd` bootstraps a fresh development machine from one repo and one shell script.

The repo is structured for **multi-platform support later**, while only **macOS** is implemented today.

## Layout

```text
initd/
├── bootstrap.sh              # OS dispatcher
├── mise.toml                 # Cross-platform runtime installs
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

## What lives where

- **stow packages** (`git/`, `kitty/`, `nvim/`): the source of truth for files that end up in `$HOME`
- **`platforms/<os>/`**: package managers, OS defaults, and platform-specific setup
- **`mise.toml`**: shared language runtimes across platforms
- **`scripts/`**: shared helper scripts used by all platforms

## Current macOS setup

The macOS flow installs:

- CLI tools: `git`, `git-delta`, `ripgrep`, `fd`, `fzf`
- config manager: `stow`
- editor tooling: `neovim`, `tree-sitter`, `tree-sitter-cli`
- runtimes manager: `mise`
- apps: `kitty`, `docker`
- font: `FiraCode Nerd Font`
- runtimes via mise: `node`, `python`, `ruby`, `go`, `terraform`
- managed configs into runtime paths such as `~/.config/nvim`, `~/.config/kitty`, and `~/.gitconfig`

## Usage

```bash
git clone <repo-url> ~/.config/initd
bash ~/.config/initd/bootstrap.sh
```

On a fresh machine, `bootstrap.sh` installs Homebrew packages, trusts `mise.toml`, installs runtimes, and stows configs into place.

If Xcode Command Line Tools are missing, macOS will prompt for installation first. Re-run `bash ~/.config/initd/bootstrap.sh` after that finishes.

## Existing machine migration

If you already have files at `~/.config/nvim`, `~/.config/kitty`, or `~/.gitconfig`, `stow` will refuse to overwrite them.

```bash
bash ~/.config/initd/bootstrap.sh
```

If stow reports conflicts, move or delete the existing files first, then run bootstrap again.

If `/Applications/Docker.app` already exists but is not managed by Homebrew, bootstrap skips the `docker` cask instead of failing. A fresh machine still installs Docker normally.
