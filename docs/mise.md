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
  function __initd_mise_activate --on-event fish_preexec
      functions -e __initd_mise_activate
      __source_cached_init mise activate
  end
  ```

  That registers a prompt hook which prepends the *real* tool `bin/`
  directories to PATH, ahead of the shims. Interactive launches therefore
  exec the actual binary directly.

  It is deferred to the first command on purpose. Activation's initial
  `mise hook-env` costs ~23 ms — more than a new tab's entire ~16 ms shell
  startup — and buys nothing until a command runs, since the shims already
  resolve every tool for the prompt itself. `fish_preexec` fires before the
  first typed command executes, so that command and every prompt after it see
  the activated environment; only the empty first prompt is drawn without it.
  Interactive shell startup measures ~16 ms (non-interactive ~6 ms).

  It also sets `mise_fish_mode disable_arrow` before sourcing. mise's script
  otherwise installs a PWD hook that re-evaluates the toolset on every `cd`
  and then again at the next prompt; the prompt hook alone suffices, since
  fish_prompt handlers run before the prompt is drawn. cd + prompt is ~30 ms
  on 54 tools, ~23 ms of it the `hook-env` run: mise does a full
  re-evaluation on every directory change (it schedules its enter/leave hooks
  there), so `hook_env.cache_ttl` and `hook_env.chpwd_only` cannot skip it —
  both measure the same ~23 ms. A prompt in the same directory takes the
  early-exit path at ~7 ms.

Fish also sets `MISE_FISH_AUTO_ACTIVATE=0` in
`~/.config/fish/conf.d/00-initd-env.fish`. mise's Homebrew formula ships a
vendor conf.d hook that would run `mise activate fish | source` (uncached) on
every shell; disabling it keeps the cached call in `config.fish` as the single
activation path on both macOS and Linux.

`config.fish` deliberately does **not** put any `~/.local/share/mise/installs/…`
directory on PATH itself. It used to add starship's and zoxide's so the prompt
would skip the shim, but mise's `hook-env` treats install dirs it finds in the
inherited PATH as already covered: it leaves them out of the tool list it
prepends and moves them to the very end of PATH, behind the shims. The result
was the opposite of the intent — in every activated shell `zoxide` resolved to
the shim, so its PWD hook cost ~26 ms per `cd` instead of ~2.5 ms (measured
2026-09-04). Left to mise, both dirs land at the front of PATH on activation.
starship never needed the entry: its cached init embeds the absolute binary
path, so the prompt does not consult PATH at all.

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
- **Per prompt:** one `mise hook-env` call — ~7 ms when the directory and
  config files are unchanged (early exit), ~23 ms after a `cd`. This replaces
  the ~25ms previously paid on *every tool launch*.
- **Non-interactive contexts** are unchanged: shims stay on PATH as the
  fallback and keep working everywhere.

## Configuration

`mise/.config/mise/config.toml` is divided into three sections:

| Section | What it contains |
|---|---|
| `[settings]` | Global mise settings, including the eight-hour minimum release age |
| `[tools]` runtimes | `node`, `python`, `go`, `dotnet`, `terraform` — language runtimes with pinned versions |
| `[tools]` LSPs + CLI tools | Everything nvim's LSP config and none-ls (null-ls API) expect to find on PATH |

Claude Code is installed as `claude-code` from the mise registry
(`aqua:anthropics/claude-code`), which downloads the platform-native binary
directly. Don't switch it to `npm:@anthropic-ai/claude-code`: that package
ships a stub and relies on an npm postinstall script (which mise doesn't run)
to swap in the native binary, leaving a broken `claude` after every upgrade.

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

If the tool also needs to be available to nvim, the shim makes the binary
discoverable. Register an LSP in `lua/user/lsp/servers.lua`, or add its
formatter/linter source in `lua/user/lsp/null-ls.lua`, before Neovim will use it.
