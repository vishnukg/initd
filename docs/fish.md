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

### Global vs universal — why it matters for PATH

This is the most important distinction to get right, especially for PATH entries.

**Global (`-g`)** variables exist only for the current fish session. Every time fish
starts, `config.fish` runs and sets them again from scratch. They are exported to
child processes of that session (like Neovim), so they appear to work — until they
don't. If fish is launched in a way that skips or partially runs `config.fish`, the
variable is simply absent for any child processes spawned in that session.

**Universal (`-U`)** variables are stored permanently in `~/.config/fish/fish_variables`
and are available immediately when any fish session starts, before `config.fish` even
runs. They are reliably exported to all child processes.

For PATH entries like `/opt/homebrew/bin`, global scope caused an intermittent bug:
tools like `yamllint` were visible to fish but not always to Neovim's subprocesses
(null-ls, LSP servers), depending on how the session was started. Switching to
universal scope fixed it permanently.

`fish_add_path -U` is the right choice for any path that should always be available.
It is idempotent — running it multiple times will not add duplicates.

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

Current plugins: `patrickf1/fzf.fish`, `meaningful-ooo/sponge`.

## Useful built-in shortcuts

| Key | Action |
|---|---|
| `→` (right arrow) | Accept the grey autosuggestion |
| `Alt+.` | Insert last argument from previous command |
| `Alt+↑` | Search history for commands starting with current input |
| `Ctrl+R` | Fuzzy history search (via fzf.fish) |
| `Ctrl+T` | Fuzzy file search (via fzf.fish) |
| `Alt+C` | Fuzzy directory jump (via fzf.fish) |
| `Esc` | Switch to normal (vi) mode |
| `Ctrl+A` / `Ctrl+E` | Beginning / end of line (restored in insert mode) |

## Config layout

```
fish/.config/fish/
  config.fish          # main config — runs for every fish invocation (see below)
  fish_plugins         # fisher plugin list — committed to git
  fish_variables       # universal variables — NOT committed (machine-local state)
  conf.d/              # auto-sourced snippets (load order: alphabetical)
  functions/           # autoloaded functions
  themes/              # .theme files (if any custom themes are added)
```

## Interactive vs non-interactive

`config.fish` runs for **every** fish invocation — not just terminal sessions. That
includes scripts (`fish myscript.fish`), inline commands (`fish -c "..."`), and
subshells spawned by editors or tools. Fish calls these **non-interactive** contexts.

Config split in `config.fish`:

```
┌─ always runs ───────────────────────────────────────────┐
│  Homebrew PATH + env vars   (scripts need these)        │
│  fish_add_path              (PATH additions, idempotent) │
│  mise activate              (tool versions for scripts)  │
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

## Machine-local config

For settings that should only exist on one machine (work credentials, private
env vars, machine-specific aliases), create:

```
~/.config/fish/conf.d/local.fish
```

This file is listed in `.gitignore` so it is never committed. Fish sources
everything in `conf.d/` automatically, so no changes to `config.fish` are
needed. Example work machine setup:

```fish
# ~/.config/fish/conf.d/local.fish  (not in git)
set -gx GOPRIVATE "github.com/mycompany/*"
set -gx WORK_API_KEY "..."
abbr -a deploy './scripts/deploy.sh staging'
```

Create it on any machine that needs it, leave it absent everywhere else.
