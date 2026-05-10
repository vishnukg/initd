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
set name "value"           # local
set -g name "value"        # global (current session)
set -gx name "value"       # global + exported to child processes
set -U name "value"        # universal (persists across all sessions)
```

`fish_add_path` is a shorthand for adding to `PATH` as a universal variable — it
is idempotent (will not add duplicates).

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
  config.fish          # main config — runs for every interactive shell
  fish_plugins         # fisher plugin list — committed to git
  conf.d/              # auto-sourced snippets (load order: alphabetical)
  functions/           # autoloaded functions
  themes/              # .theme files (if any custom themes are added)
```

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
