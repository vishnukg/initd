# Fish shell primer

Fish is the default shell for this repo. It is fast, has autosuggestions and
syntax highlighting built in, and requires almost no configuration to feel good.

## Key differences from zsh/bash

Fish is not POSIX-compatible. Shell scripts with a `#!/bin/bash` shebang still
run fine — the incompatibility only matters when writing fish config or sourcing
bash scripts directly into fish.

| Concept | bash/zsh | fish |
|---|---|---|
| Set variable | `export FOO=bar` | `set -gx FOO bar` |
| Condition | `if [ -f file ]` | `if test -f file` |
| Check command exists | `command -v foo` | `command -q foo` |
| String interpolation | `"hello $name"` | `"hello $name"` (same) |
| Source a file | `source file` | `source file` |
| Capture output | `$(cmd)` | `$(cmd)` or `(cmd)` |
| Function | `foo() { ... }` | `function foo; ...; end` |
| Pipe to eval | `eval "$(cmd)"` | `cmd \| source` |

## Variables

```fish
set name "value"           # local (current function only)
set -g name "value"        # global (current session, gone when fish exits)
set -gx name "value"       # global + exported to child processes
set -U name "value"        # universal (persists across all sessions forever)
```

### Global vs universal — when each makes sense

**Global (`-g`)** variables exist for the current fish session only and are
exported to all child processes. `config.fish` runs on every fish startup, so
anything set with `-g` there is always available to child processes like Neovim.
This is the right choice for PATH entries — simple, direct, no hidden state.

```fish
set -gx PATH /opt/homebrew/bin $PATH   # equivalent to bash's: export PATH=...
```

**Universal (`-U`)** variables are stored permanently in `fish_variables` and
survive across sessions without `config.fish` needing to run. Useful for
preferences you want to set once (e.g. `set -U fish_greeting ""`), but
unnecessary for PATH — since `config.fish` always runs at session start anyway.

## Homebrew + Neovim subprocess PATH (Apple Silicon)

On macOS Apple Silicon, there's a long-standing interaction between fish, the
system `path_helper`, and Homebrew that bites Neovim plugins (specifically
`none-ls` / `null-ls`) when they spawn subprocesses for tools like `yamllint`
and `golangci-lint`.

**Why it happens:**

1. macOS ships a tool called `path_helper` that reads `/etc/paths` and rebuilds
   `PATH` at shell startup. On Apple Silicon, `/etc/paths` only contains
   `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin` — **not** `/opt/homebrew/bin`.
2. Fish invokes `path_helper` on startup, which can strip or reorder
   `/opt/homebrew/bin` even after `fish_add_path` has put it in.
3. Neovim launches, inherits the truncated `PATH`. When `null_ls.setup()` runs
   `vim.fn.executable("yamllint")`, the binary is not found.

**Why zsh doesn't have this problem:**

zsh on macOS sources `/etc/zprofile` exactly once at **login** — `path_helper`
runs there, then `~/.zprofile` (or the user's profile config) appends Homebrew
after it. Because login shells only run once per session, that order sticks for
every child process. Fish doesn't have an equivalent login-only hook; it runs
its full config on every invocation, and `path_helper` can be re-evaluated.

**Workaround:**

Rather than modify system files (`/etc/paths.d/homebrew`), the fix is applied at
the Neovim layer in `nvim/.config/nvim/lua/user/lsp/null-ls.lua` — it prepends
`/opt/homebrew/bin` to `vim.env.PATH` immediately before `null_ls.setup()` runs.
See the Neovim docs (`docs/nvim.md`) for the full explanation.

The "proper" fix would be:

```bash
echo "/opt/homebrew/bin" | sudo tee /etc/paths.d/homebrew
```

But that requires `sudo` and modifies a system file, which Homebrew itself
deliberately avoids. The Neovim-level workaround is narrower and reversible.

## Abbreviations vs aliases

Fish has both. Prefer `abbr` for commands you type interactively — they expand
in the command line so you always see the full command before it runs.

```fish
abbr -a gst 'git status'   # expands when you press space or enter
alias vi nvim               # substitutes silently, like a regular alias
```

## Functions

Functions live in `~/.config/fish/functions/<name>.fish` and are autoloaded on
first call — no need to source them.

```fish
# ~/.config/fish/functions/mkcd.fish
function mkcd
    mkdir -p $argv && cd $argv
end
```

## Plugins (fisher)

Plugins are managed with [fisher](https://github.com/jorgebucaran/fisher).
Installed plugins are tracked in `fish_plugins` which is committed to this repo,
so `fisher update` on a new machine restores everything.

```fish
fisher install owner/repo   # install
fisher update               # sync all plugins from fish_plugins
fisher remove owner/repo    # uninstall
```

Current plugin: `patrickf1/fzf.fish`.

## Useful built-in shortcuts

| Key | Action |
|---|---|
| `→` (right arrow) | Accept the grey autosuggestion |
| `Alt+.` | Insert last argument from previous command |
| `Alt+↑` | Search history for commands starting with current input |
| `Ctrl+R` | Fuzzy history search (via fzf.fish) |
| `Ctrl+Alt+F` | Fuzzy file/directory search (via fzf.fish) |
| `Ctrl+Alt+L` | Fuzzy git log search (via fzf.fish) |
| `Ctrl+Alt+S` | Fuzzy git status search (via fzf.fish) |
| `Esc` | Switch to normal (vi) mode |
| `Ctrl+A` / `Ctrl+E` | Beginning / end of line (restored in insert mode) |

## Config layout

```
fish/.config/fish/
  config.fish          # main config — runs for every fish invocation (see below)
  fish_plugins         # fisher plugin list — committed to git
  fish_variables       # universal variables — NOT committed (machine-local state)
  conf.d/              # auto-sourced snippets (load order: alphabetical)
    00-initd-env.fish  # early env vars that must exist before vendor snippets
  functions/           # autoloaded functions
  themes/              # .theme files (if any custom themes are added)
```

### Why `00-initd-env.fish` exists

Fish loads files from `conf.d/` before it loads `config.fish`. Homebrew packages
can also install their own fish snippets in vendor `conf.d/` directories.

The mise Homebrew formula installs a vendor snippet that runs the full
`mise activate fish` hook unless `MISE_FISH_AUTO_ACTIVATE` is disabled first.
This repo uses mise shims instead, so full shell activation is unnecessary
startup work. `00-initd-env.fish` exists only to set that variable early enough:

```fish
set -gx MISE_FISH_AUTO_ACTIVATE 0
```

The name starts with `00-` so it is easy to spot as an early startup file.

## Interactive vs non-interactive

`config.fish` runs for **every** fish invocation — not just terminal sessions. That
includes scripts (`fish myscript.fish`), inline commands (`fish -c "..."`), and
subshells spawned by editors or tools. Fish calls these **non-interactive** contexts.

Config split in `config.fish`:

```
┌─ always runs ───────────────────────────────────────────┐
│  Homebrew PATH + env vars   (scripts need these)        │
│  fish_add_path              (PATH additions, idempotent) │
│  mise shims                 (tool versions for scripts)  │
└─────────────────────────────────────────────────────────┘
  if not status is-interactive; exit; end
┌─ interactive only ──────────────────────────────────────┐
│  Theme, vi mode, key bindings                           │
│  Aliases and abbreviations                              │
│  zoxide, starship                                       │
└─────────────────────────────────────────────────────────┘
```

Without this guard, every `fish -c "git status"` from Neovim would wastefully
load all 37 git abbreviations, run `starship init`, `zoxide init`, and set vi key
bindings — none of which have any effect outside a terminal.

The same rule applies to `conf.d/` files that define interactive-only behaviour.
`conf.d/fzf.fish` already does this with its own guard at the top.

## Startup speed choices

The config keeps startup fast by avoiding setup commands during shell startup:

- mise uses `~/.local/share/mise/shims` on `PATH` instead of `mise activate`.
- `starship` and `zoxide` are loaded from their mise install directories when
  available, so fish does not need to resolve them through shims first.
- Nord colors are set directly with `fish_color_*` variables instead of running
  `fish_config theme choose nord` on every shell start.
- `fish_greeting` is a normal global variable, not a universal variable written
  back to `fish_variables`.
- Fisher plugins are kept minimal. Fish already has history autosuggestions
  built in, so only `fzf.fish` is installed.

## Machine-local config

For settings that should only exist on one machine (work credentials, private
env vars, machine-specific aliases), create:

```
~/.config/fish/local.fish
```

This file is gitignored and sourced by `config.fish` at startup if it exists. Example work machine setup:

```fish
# ~/.config/fish/local.fish  (not in git)
set -gx GOPRIVATE "github.com/mycompany/*"
set -gx WORK_API_KEY "..."
abbr -a deploy './scripts/deploy.sh staging'
```

Create it on any machine that needs it, leave it absent everywhere else.
