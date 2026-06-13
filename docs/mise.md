# Mise primer

Mise (pronounced "meez") is a polyglot runtime and tool version manager. It
replaces `nvm`, `rbenv`, `pyenv`, `tfenv`, and similar single-language tools
with one binary that handles all of them. It also manages CLI tools and LSP
servers — anything that needs a pinned version.

This repo's tool inventory lives in `shared/configs/mise/.config/mise/config.toml`, symlinked
to `~/.config/mise/config.toml` by `shared/lib/link.sh`.

## How mise manages versions

Mise stores each tool version in its own directory under
`~/.local/share/mise/installs/<tool>/<version>/`. Multiple versions can be
installed simultaneously; mise decides which one to activate based on the
nearest `mise.toml` / `.tool-versions` file, falling back to the global config.

```
~/.local/share/mise/installs/
  node/
    24.15.0/bin/node
  python/
    3.14.5/bin/python3
  go/
    1.26.3/bin/go
```

## Shims vs activate

There are two ways mise can intercept a command like `node`:

**`mise activate`** — hooks into the shell's `cd` and prompt cycle to prepend
the right version's `bin/` directory onto `$PATH` dynamically. Fast for
interactive use but requires mise to run code on every directory change. Because
it manipulates `$PATH` at runtime, tools launched outside the shell (editors,
daemons, GUI apps) may start with a stale or partial PATH if they don't go
through the shell's eval hook.

**Shims** — mise creates thin wrapper scripts in a single fixed directory
(`~/.local/share/mise/shims/`). Every managed tool gets one:

```
~/.local/share/mise/shims/
  node      ← thin wrapper
  python3   ← thin wrapper
  go        ← thin wrapper
  gopls     ← thin wrapper
  stylua    ← thin wrapper
  ...
```

When you run `node`, the shim runs first. It asks mise which version is active
for the current directory, then exec's the real binary from
`~/.local/share/mise/installs/node/<version>/bin/node`. The lookup adds a few
milliseconds but the shim directory never changes, so any process that has it
on `$PATH` — the shell, nvim, CI, a launchd daemon — always gets the right
version without needing mise to be "activated" at all.

This repo uses **both**, each where it is strongest:

- **Shims are the baseline.** `~/.config/fish/config.fish` adds the shim
  directory at shell startup, for every shell:

  ```fish
  fish_add_path ~/.local/share/mise/shims
  ```

  Anything that inherits PATH without going through an interactive prompt —
  scripts, nvim's `vim.fn.executable()` lookups for LSPs/formatters, CI,
  launchd — resolves tools through shims and always gets the right version.

- **Interactive shells additionally run `mise activate`.** The interactive
  section of `config.fish` sources it through the same `__source_cached_init`
  caching used for zoxide and starship:

  ```fish
  __source_cached_init mise activate
  ```

  That registers a prompt hook which prepends the *real* tool `bin/`
  directories to PATH, ahead of the shims. Interactive launches therefore
  exec the actual binary directly.

Fish also sets `MISE_FISH_AUTO_ACTIVATE=0` in
`~/.config/fish/conf.d/00-initd-env.fish`. mise's Homebrew formula ships a
vendor conf.d hook that would run `mise activate fish | source` (uncached) on
every shell; disabling it keeps the cached call in `config.fish` as the single
activation path on both macOS and Linux.

For startup speed, `config.fish` also adds the direct install directories for a
couple of prompt-time tools when they exist (these run during shell init,
before the first prompt hook has fired):

```fish
if test -d ~/.local/share/mise/installs/starship/latest
    fish_add_path ~/.local/share/mise/installs/starship/latest
end
if test -d ~/.local/share/mise/installs/zoxide/latest
    fish_add_path ~/.local/share/mise/installs/zoxide/latest
end
```

## Why the hybrid

Shims alone have two interactive costs. Every launch pays the lookup: the shim
*is* the `mise` binary, which resolves the version and then `exec`s the real
tool — ~25ms added to every `nvim`, `rg`, `node`. And because the foreground
process is briefly named `mise`, tmux's `#{pane_current_command}` samples that
name and shows `mise` in the tab until the next redraw trigger.

Activate alone breaks non-interactive contexts: PATH is injected by a prompt
hook, so editors, daemons, and scripts that never render a prompt would start
with no mise tools at all.

The hybrid costs and gains:

- **Per interactive shell startup:** sourcing the cached activation script
  (~1ms). The script itself is regenerated only when the mise binary's mtime
  changes (i.e. after an upgrade) — same invalidation as zoxide/starship.
- **Per prompt:** one `mise hook-env` call (~20ms), which short-circuits
  unless a mise config file changed. This replaces the ~25ms previously paid
  on *every tool launch*.
- **Non-interactive contexts** are unchanged: shims stay on PATH as the
  fallback and keep working everywhere.

## Configuration

`mise/.config/mise/config.toml` is divided into three sections:

| Section | What it contains |
|---|---|
| `[settings]` | Global mise settings (e.g. `experimental = true` for the `dotnet:` backend) |
| `[tools]` runtimes | `node`, `python`, `go`, `dotnet`, `terraform` — language runtimes with pinned versions |
| `[tools]` LSPs + CLI tools | Everything nvim's LSP config and null-ls expect to find on PATH |

Version strings follow mise's resolution rules:

| Value | Meaning |
|---|---|
| `"latest"` | Track the latest stable release; mise updates on `mise upgrade` |
| `"lts"` | Latest LTS release (node only) |
| `"3.14"` | Latest patch in the 3.14.x series |
| `"1.22.22"` | Exact pin, never moves |

## Common commands

```sh
mise ls                  # list all installed tools and their active version
mise ls --missing        # list tools in config that are not yet installed
mise install             # install everything in config.toml
mise install node        # install just node
mise upgrade             # upgrade all "latest" tools to their current latest
mise upgrade node        # upgrade just node
mise which node          # print the real binary path behind the shim
mise exec -- node -e ""  # run a command in the mise environment explicitly
```

## Adding a new tool

Add a line to `[tools]` in `mise/.config/mise/config.toml` and run
`mise install`. The shim is created automatically. No PATH changes needed.

```toml
[tools]
"npm:ts-node" = "latest"
```

If the tool also needs to be available to nvim (formatter, linter, LSP server),
that's all you need — nvim already has the shim directory on its PATH.
