# Neovim Config

A personal Neovim configuration built on [lazy.nvim](https://github.com/folke/lazy.nvim), providing a full IDE-like experience with LSP, intelligent formatting, linting, testing, and AI assistance.

---

## Table of Contents

- [Config Structure](#config-structure)
- [Fresh Install](#fresh-install)
- [How Everything Works Together](#how-everything-works-together)
  - [Treesitter](#treesitter--syntax-highlighting)
  - [Tool installation (mise)](#tool-installation-mise)
  - [LSP](#lsp--language-intelligence)
  - [None-ls](#none-ls--formatting--linting)
  - [Completion](#completion)
- [Language Support](#language-support)
- [Key Commands](#key-commands)
- [Keymaps](#keymaps)
- [Adding a New Language](#adding-a-new-language)

---

## Config Structure

```
~/.config/nvim/
├── init.lua                  # Entry point — loads bootstrap then user config
└── lua/
    ├── bootstrap.lua         # Pre-plugin globals (leader keys, providers, netrw)
    │                         # ⚠️  Must load before lazy.nvim initialises
    └── user/
        ├── init.lua          # Loads all modules in order
        ├── options.lua       # Neovim options (tabstop, scrolloff, etc.)
        ├── keymaps.lua       # Global keymaps
        ├── plugins.lua       # lazy.nvim plugin specs
        ├── colorscheme.lua   # Theme setup
        ├── cmp.lua           # Completion (nvim-cmp + LuaSnip)
        ├── treesitter.lua    # Syntax parser setup, auto-install, attach/folds
        ├── nvimtree.lua      # File explorer
        ├── lualine.lua       # Status line
        ├── fzf.lua           # fzf-lua setup
        ├── gitsigns.lua      # Git decorations
        ├── fidget.lua        # LSP progress notifications
        ├── toggleterm.lua    # Integrated terminal
        ├── autopairs.lua     # Automatic bracket/quote pairs
        ├── neotest.lua       # Test runner adapters
        ├── coverage.lua      # Coverage overlays
        ├── gopher.lua        # Go struct/code-generation helpers
        └── lsp/
            ├── init.lua      # Wires up handlers, null-ls, servers
            ├── servers.lua   # vim.lsp.config + vim.lsp.enable for each server
            ├── handlers.lua  # LspAttach, formatter selection, diagnostics/keymaps
            ├── null-ls.lua   # none-ls sources (formatters & linters)
            └── settings/     # Per-server config overrides
                ├── lua_ls.lua
                ├── terraformls.lua
                └── ...
```

**Load order in `init.lua`:**
```
require "bootstrap"   -- 1. globals that must exist before any plugin loads
require "user"        -- 2. lazy.nvim + all plugins + LSP + keymaps
```

---

## Fresh Install

### 1. Bootstrap `initd`

```bash
bash ~/.config/initd/bootstrap.sh
```

This Neovim config is managed by the `initd` repo and linked into `~/.config/nvim`.

### 2. Provisioned dependencies

| Tool | Purpose | Provisioned by |
|------|---------|----------------|
| [Neovim](https://neovim.io/) v0.12+ | The editor | `mise/config.toml` |
| [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter) v0.26.1+ | Compiles syntax parsers | `mise/config.toml` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | fzf-lua live grep | `mise/config.toml` |
| [fd](https://github.com/sharkdp/fd) | Fast file search for fzf-lua | `mise/config.toml` |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy finding | `mise/config.toml` |
| C compiler (gcc/clang) | Builds Treesitter parsers | Platform bootstrap / Xcode CLT |
| [Nerd Font](https://www.nerdfonts.com/) | Icons & special characters | Platform bootstrap |

> `initd` provisions these dependencies through mise and the platform bootstrap, then links this config into place.

> **Linux:** `linux/bootstrap.sh` installs `wl-clipboard` (`wl-copy` / `wl-paste`) for clipboard support.

> **macOS:** Neovim automatically uses the system `pbcopy` / `pbpaste` provider; no additional clipboard package is required.

The shared terminal stack is intentionally portable: macOS bootstrap installs Ghostty, Fish, tmux, mise, and the Xcode command-line compiler; Ghostty reads the same XDG config on macOS and treats Option as terminal Alt; mise uses the same `~/.local/share/mise` data/shim layout on both supported platforms.

### 3. Launch Neovim

```bash
nvim
```

On first launch, [lazy.nvim](https://github.com/folke/lazy.nvim) installs all plugins. After that, Treesitter downloads and compiles missing parsers as their filetypes are first opened.

LSP servers, formatters, and linters are **not** installed by Neovim — `initd` bootstrap installs them via `mise` (see [Tool installation (mise)](#tool-installation-mise) below).

Wait for everything to finish, then restart Neovim. Run `:checkhealth` to verify.

### 4. Language-specific external setup

A small number of languages need project-specific setup beyond the bootstrap — see the [Language Support](#language-support) table for details.

---

## How Everything Works Together

Four separate systems collaborate to give you IDE features. Each one has a distinct job:

```
┌──────────────────────────────────────────────────────────────────────┐
│                        init.lua                                      │
│  require "bootstrap"  →  providers, leader keys, netrw (pre-plugin) │
│  require "user"       →  everything below                            │
└───────┬───────────────┬──────────────────┬───────────────────────────┘
        │               │                  │
        ▼               ▼                  ▼
┌───────────────┐ ┌──────────────┐ ┌──────────────────┐
│  Treesitter   │ │     LSP      │ │     None-ls      │
│               │ │              │ │                  │
│ Syntax        │ │ Diagnostics  │ │ Formatting       │
│ highlighting  │ │ Completions  │ │ Extra linting    │
│ Code folding  │ │ Go-to-def    │ │ (runs external   │
│ Indentation   │ │ Rename       │ │                  │
└───────────────┘ └──────┬───────┘ └────────┬─────────┘
                         │                  │
                         └────────┬─────────┘
                                  ▼
                       ┌────────────────────┐
                       │       mise         │
                       │                    │
                       │ Installs LSP       │
                       │ servers + lint /   │
                       │ format binaries    │
                       │ outside Neovim     │
                       └────────────────────┘
```

---

### Treesitter — Syntax Highlighting

Treesitter **parses your code into a syntax tree**. This is fundamentally different from the old regex-based highlighting — it actually understands the structure of your code.

**What it powers:**
- Accurate, context-aware syntax highlighting
- Smart code folding
- Indentation (for most languages)

Treesitter parsers are compiled native libraries. The `tree-sitter-cli` binary is required to build them. A parser is auto-installed the first time its supported filetype is opened; bundled Neovim parsers are reused directly.

The current nvim-treesitter main branch is loaded eagerly (`lazy = false`), as required by the plugin. Test runners, coverage, and Go helpers remain command/module-loaded and do not add work when an ordinary code file opens.

> ⚠️ Treesitter gives you *highlighting* — it does **not** know about types, errors, or completions. That's LSP's job.

---

### Tool installation (mise)

LSP servers, formatters, and linters are **not** managed by Neovim. They are installed by [mise](https://mise.jdx.dev/) via `~/.config/initd/shared/configs/mise/.config/mise/config.toml`. mise puts shims in `~/.local/share/mise/shims` on `PATH` ahead of Homebrew, so Neovim's `vim.fn.executable()` checks find everything.

```
mise tool sources (one committed file, every machine identical):

~/.config/initd/shared/configs/mise/.config/mise/config.toml
  ├── runtimes                 ← go, node, python, dotnet, terraform
  ├── LSP servers              ← lua_ls, gopls, pyright, ruff, tsgo, taplo, …
  └── linters / formatters     ← stylua, ruff, golangci-lint, prettierd, …
```

**Why mise instead of [mason.nvim](https://github.com/williamboman/mason.nvim):**
- One file describes every tool version and is committed to git, so two machines stay identical.
- `mise upgrade` (everything) or `mise upgrade gopls` (one tool) — no Mason UI to click through.
- mise's `pipx:`, `npm:`, `go:`, `gem:`, `dotnet:` backends share the runtime mise already manages, instead of Mason's isolated venv/sandbox per tool — that sandboxing was the source of several long-standing bugs (pip-wrapped venvs not on PATH, golangci-lint v1/v2 flag mismatches).

---

### LSP — Language Intelligence

The Language Server Protocol (LSP) is a standard that allows editors to talk to language-specific servers for deep code intelligence.

```
┌─────────────────────────────────────────────────────────────────┐
│                         Neovim                                  │
│                                                                 │
│  ┌─────────────┐    ┌──────────────────┐                       │
│  │  vim.lsp    │◄──►│  nvim-lspconfig  │                       │
│  │             │    │                  │                       │
│  │ Built-in    │    │ Knows HOW to     │                       │
│  │ LSP client  │    │ start each       │                       │
│  │ (the engine)│    │ server           │                       │
│  └─────────────┘    └──────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
        ▲                       │
        │ JSON-RPC              │ executes server binary by name
        ▼                       ▼
┌───────────────┐    ┌────────────────────────────────────────┐
│ Language      │    │ mise shims on PATH                     │
│ Server        │◄───│ (~/.local/share/mise/shims/gopls, …)   │
│ (e.g. gopls)  │    │                                        │
└───────────────┘    └────────────────────────────────────────┘
```

**The two LSP components and their roles:**

| Component | Role |
|-----------|------|
| `vim.lsp` | Built-in Neovim LSP engine — speaks the protocol |
| `nvim-lspconfig` | Knows the startup command & options for each server |

`lua/user/lsp/servers.lua` iterates the server list, applies any per-server overrides from `lua/user/lsp/settings/<server>.lua`, and calls `vim.lsp.config` + `vim.lsp.enable`. Server binaries are resolved from `PATH`, which the fish config populates with the mise shim directory via `fish_add_path` (no `mise activate` — it is explicitly disabled).

**What LSP provides:** completions, diagnostics, go-to-definition, hover docs, find references, rename, code actions, inlay hints.

---

### None-ls — Formatting & Linting

None-ls (a maintained fork of null-ls) **pretends to be an LSP server** so that standalone CLI tools (prettier, stylua, csharpier, etc.) can plug into Neovim's LSP formatting pipeline without needing a real language server.

```
On BufWritePre (save):

vim.lsp.buf.format({ id = selected_client })
      │
      └──► formatter selector
                │
                ├── Python override       → ruff
                ├── available none-ls     → stylua, goimports, prettierd, …
                └── native LSP fallback   → tsgo, jsonls, lua_ls, gopls, …
```

Exactly one client formats each save. A matching none-ls source is preferred, while native LSP formatting remains available as a fallback. For example, `prettierd` is used only when the project has a Prettier config; otherwise `tsgo`, `jsonls`, or `html` can format instead of silently doing nothing.

> **Python is the exception.** Python lint + format + import-sorting all come from ruff's own LSP server, not none-ls. Ruff's hover is suppressed so pyright provides it, and pyright's "organize imports" is disabled so ruff owns it.

---

### Completion

`nvim-cmp` is the completion engine. It aggregates suggestions from multiple sources and displays them in a unified popup.

```

`nvim-autopairs` is an explicit cmp dependency. Its `confirm_done` hook is registered from `cmp.lua`, so accepting a completion and inserting its closing pair does not depend on `InsertEnter` plugin load order.
nvim-cmp sources (in priority order):
  1. LSP         ← type/function/variable suggestions from language server
  2. LuaSnip     ← code snippet expansions
  3. Buffer      ← words from open buffers
  4. Path        ← filesystem paths
```

---

## Language Support

### What the columns mean

| Column | Description |
|--------|-------------|
| **LSP** | Language server providing completions, go-to-def, hover, diagnostics |
| **Formatter** | Tool that auto-formats on save |
| **Linter** | Tool that provides additional diagnostic warnings |
| **Test Runner** | Neotest adapter for running tests inside Neovim |
| **External Setup** | Anything you must install or configure beyond `bootstrap.sh` |

All listed LSPs, formatters, and linters are installed by `mise install` during bootstrap (see `mise/.config/mise/config.toml`).

---

### Languages

#### 🟢 Works out of the box after `bootstrap.sh`

| Language | LSP | Formatter | Linter | Test Runner |
|----------|-----|-----------|--------|-------------|
| **Lua** | lua_ls | stylua | — | — |
| **Python** | pyright + ruff | ruff | ruff | neotest-python (pytest)³ |
| **Go** | gopls | goimports | gopls staticcheck + golangci-lint⁵ | neotest-golang |
| **TypeScript / JavaScript** | tsgo (TS7 built-in LSP) | prettierd⁴ or tsgo fallback | eslint_d¹ | neotest-jest / neotest-vitest² |
| **JSON** | jsonls | prettierd⁴ or jsonls fallback | — | — |
| **HTML** | html + emmet_ls | prettierd⁴ or html fallback | — | — |
| **CSS / SCSS** | emmet_ls | prettierd⁴ | stylelint¹ | — |
| **YAML** | yamlls | yamlfmt | yamllint | — |
| **Bash** | bashls | — | — | — |
| **TOML** | taplo | taplo | — | — |
| **Terraform / HCL** | terraformls | terraform_fmt | terraformls | — |
| **C#** | roslyn_ls | csharpier | — | neotest-vstest |
| **Dockerfile** | dockerls | — | hadolint | — |

> ¹ ESLint and Stylelint diagnostics activate only when a corresponding project config exists.
> ² Jest adapter activates with `jest.config.*`; Vitest adapter activates with `vitest.config.*` or `vite.config.*`.
> ³ Runs the project's own `pytest` (venv / mise / system python), not a mise-managed tool — make sure `pytest` is installed in the project environment.
> ⁴ Prettierd activates only when a Prettier project config exists. Where the attached LSP supports formatting, it is used as the fallback.
> ⁵ Golangci-lint runs on save only when `.golangci.yml`, `.golangci.yaml`, `.golangci.toml`, or `.golangci.json` exists in the project; gopls remains the always-on baseline.

---

#### ⚪ Treesitter-only — highlighting only, no LSP/formatting

There is no fixed parser allow-list: any language in nvim-treesitter's parser registry is installed on first use. Examples that currently have highlighting but no configured LSP or formatter are:

| Language | Highlights | Notes |
|----------|-----------|-------|
| Rust | ✓ | Add `rust_analyzer` to `mise/.config/mise/config.toml` + `lsp_servers` to enable LSP |
| GraphQL | ✓ | — |
| C | ✓ | Add `clangd` to `mise/.config/mise/config.toml` + `lsp_servers` to enable LSP |
| XML | ✓ | — |
| Helm | ✓ | — |
| Make | ✓ | — |
| HTTP | ✓ | — |
| Git files | ✓ | gitcommit, gitconfig, gitignore, gitrebase |
| Diff | ✓ | — |
| Protocol Buffers | ✓ | — |
| SQL | ✓ | Highlighting only — no LSP configured |
| Regex | ✓ | Embedded in other languages |

---

## Key Commands

| Command | Description |
|---------|-------------|
| `:Lazy` | Open plugin manager — update/install plugins |
| `:TSUpdate` | Update Treesitter parsers managed by nvim-treesitter |
| `:checkhealth vim.lsp` | Show LSP configuration and attached-client health |
| `:NullLsInfo` | Show none-ls sources active in the current buffer (after the LSP group loads) |
| `:checkhealth` | Diagnose configuration issues |

LSP servers, formatters, and linters are installed/updated outside Neovim:

| Shell command | Description |
|---------------|-------------|
| `mise install` | Install everything listed in `mise/.config/mise/config.toml` (idempotent) |
| `mise upgrade` | Upgrade every tool to the latest version compatible with its pin |
| `mise upgrade <tool>` | Upgrade a single tool, e.g. `mise upgrade gopls` |
| `mise ls` | List installed tools and their resolved versions |

---

## Keymaps

`<leader>` is the backslash key (`\`). For example, `<leader>ff` is `\ff`.

### LSP (active when an LSP is attached)

| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gri` | Go to implementation |
| `grt` | Go to type definition |
| `grr` | Find references |
| `grl` | Run code lens |
| `gO` | List document symbols |
| `K` | Hover documentation |
| `<leader>fm` | Format buffer |
| `grn` | Rename symbol |
| `gra` | Code actions |
| `gl` | Open diagnostics float |
| `gch` | Show incoming calls |
| `gth` / `gtH` | Show type supertypes / subtypes |
| `<leader>li` | Open LSP health information |
| `<leader>lj` | Next diagnostic |
| `<leader>lk` | Previous diagnostic |
| `<leader>ls` | Signature help |
| `<leader>lq` | Send diagnostics to location list |

### Navigation

| Key | Action |
|-----|--------|
| `<C-g>` | Toggle file tree |
| `<leader>ff` | Find files (fzf-lua) |
| `<leader>fg` | Live grep (fzf-lua) |
| `<leader>fb` | Browse open buffers (fzf-lua) |
| `<S-h>` / `<S-l>` | Previous / next buffer |
| `<A-Arrow>` | Resize the current window |
| `<leader>sp` | Search and replace with grug-far |
| `<leader>sw` | Search and replace the word under the cursor |

### Git

| Key | Action |
|-----|--------|
| `:Git` / `:G` | Open Fugitive (git status) |

### Testing

| Key | Action |
|-----|--------|
| `<leader>tr` | Run nearest test |
| `<leader>tf` | Run all tests in file |
| `<leader>ts` | Toggle test summary |
| `<leader>to` | Open test output |

Neotest and all adapters load only when one of these mappings is first used.

### Terminal

| Key | Action |
|-----|--------|
| `<C-\>` | Toggle the floating terminal |
| `<leader>tv` / `<leader>th` | Toggle a vertical / horizontal terminal |
| `<leader>gt` | Toggle lazygit |
| `<Esc>` or `jk` | Leave terminal-input mode |

### Coverage and Go helpers

| Key | Action |
|-----|--------|
| `gcv` | Load and display coverage |
| `<leader>cvs` / `<leader>hcv` / `<leader>ccv` | Summarize / hide / clear coverage |
| `<leader>ga{j,y,x,e,d}` | Add JSON/YAML/XML/env/db Go struct tags |
| `<leader>gr{j,y,x,e,d}` | Remove those Go struct tags |
| `<leader>gie` / `<leader>gim` | Add an if-error block / implement an interface |

Coverage and Gopher are command-loaded on first use. Gopher's helper binaries are installed by lazy.nvim's plugin build step, not while opening a Go file.

---

## Adding a New Language

Adding a language usually touches two layers: install the tool in `mise/.config/mise/config.toml`, then register the corresponding LSP, formatter, or linter in Neovim.

1. **Tool binary (mise)** — add the LSP server or lint/format CLI to `mise/.config/mise/config.toml`. Tools live in mise's core registry where possible (`gopls`, `pyright`, `stylua`, …) and otherwise use a backend prefix:

   | Backend | Use for | Example |
   |---------|---------|---------|
   | (none)  | Core registry (Go, Rust, prebuilt binaries) | `"gopls" = "latest"` |
   | `npm:`  | Node-based tools                            | `"npm:bash-language-server" = "latest"` |
   | `pipx:` | Python CLIs (executed with uvx in this config) | `"pipx:yamllint" = "latest"` |
   | `go:`   | Tools built from a Go module path           | `"go:github.com/mgechev/revive" = "latest"` |
   | `dotnet:` | .NET global tools                          | `"dotnet:csharpier" = "latest"` |

   Run `mise install` after editing.

2. **LSP server (Neovim)** — add the server name to `lsp_servers` in `lua/user/lsp/servers.lua`. Find the correct name in the [nvim-lspconfig server list](https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md). Add a settings file at `lua/user/lsp/settings/<server_name>.lua` if needed.

3. **Formatter / Linter (Neovim)** — add the corresponding none-ls source in `lua/user/lsp/null-ls.lua`. (There is no separate Neovim-side install list anymore — mise is the single source of truth for the binary.)

4. **Treesitter** — no committed parser list is required. `lua/user/treesitter.lua` auto-installs a parser the first time a supported filetype is opened.

5. **External tools** — if the language requires anything that genuinely cannot be installed by mise, document it in the Language Support table or its notes.
