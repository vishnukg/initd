# Mise primer

Mise (pronounced "meez") is a polyglot runtime and tool version manager. It
replaces `nvm`, `rbenv`, `pyenv`, `tfenv`, and similar single-language tools
with one binary that handles all of them. It also manages CLI tools and LSP
servers — anything that needs a pinned version.

This repo's tool inventory lives in `mise/.config/mise/config.toml`, symlinked
to `~/.config/mise/config.toml` by `scripts/link.sh`.

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

This repo uses shims. `~/.config/fish/config.fish` adds the shim directory at
shell startup:

```fish
fish_add_path ~/.local/share/mise/shims
```

Fish also sets `MISE_FISH_AUTO_ACTIVATE=0` in
`~/.config/fish/conf.d/00-initd-env.fish`. That disables the automatic
Homebrew-installed mise fish hook before vendor snippets run. No
`mise activate`, no `eval`, no prompt hooks.

For startup speed, `config.fish` also adds the direct install directories for a
couple of prompt-time tools when they exist:

```fish
if test -d ~/.local/share/mise/installs/starship/latest
    fish_add_path ~/.local/share/mise/installs/starship/latest
end
if test -d ~/.local/share/mise/installs/zoxide/latest
    fish_add_path ~/.local/share/mise/installs/zoxide/latest
end
```

That keeps normal mise-managed tools on shims, while avoiding an extra shim
lookup for commands that run every time an interactive shell starts.

## Why shims work better for this setup

- **Editors and tools inherit PATH correctly.** Nvim launched from fish sees
  `~/.local/share/mise/shims` because it was baked into PATH at fish startup,
  not injected dynamically. LSP servers and formatters resolved by nvim's
  `vim.fn.executable()` just work.
- **No shell startup overhead.** `mise activate` re-evaluates on every prompt
  draw. Shims move the version lookup to the moment you actually run the tool.
- **Simpler shell behavior.** A fixed PATH plus one early opt-out variable is
  easier to reason about than `mise activate fish | source` plus hook functions.

## Configuration

`mise/.config/mise/config.toml` is divided into three sections:

| Section | What it contains |
|---|---|
| `[settings]` | Global mise settings (e.g. `experimental = true` for the `dotnet:` backend) |
| `[tools]` runtimes | `node`, `python`, `ruby`, `go`, `dotnet`, `terraform` — language runtimes with pinned versions |
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
