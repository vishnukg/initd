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
        ├── treesitter.lua    # Syntax parser config + installed parsers
        ├── nvimtree.lua      # File explorer
        ├── lualine.lua       # Status line
        ├── fzf.lua           # fzf-lua setup
        ├── gitsigns.lua      # Git decorations
        ├── fidget.lua        # LSP progress notifications
        ├── toggleterm.lua    # Integrated terminal
        ├── autopairs.lua     # Automatic bracket/quote pairs
        ├── neotest.lua       # Test runner adapters
        └── lsp/
            ├── init.lua      # Wires up handlers, null-ls, servers
            ├── servers.lua   # vim.lsp.config + vim.lsp.enable for each server
            ├── handlers.lua  # on_attach, keymaps, diagnostics, inlay hints
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

### 2. Install system dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| [Neovim](https://neovim.io/) v0.11+ | The editor | `brew install neovim` |
| [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter) v0.26.1+ | Compiles syntax parsers | `brew install tree-sitter` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | fzf-lua live grep | `brew install ripgrep` |
| [fd](https://github.com/sharkdp/fd) | Fast file search for fzf-lua | `brew install fd` |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy finding | `brew install fzf` |
| C compiler (gcc/clang) | Builds Treesitter parsers | Xcode CLT on macOS |
| [FiraCode Nerd Font](https://www.nerdfonts.com/) | Icons & special characters | Installed by `initd` |

> `initd` installs these dependencies via Homebrew and links this config into place.

> **Linux only:** install `xclip` for clipboard support.

### 3. Launch Neovim

```bash
nvim
```

On first launch, [lazy.nvim](https://github.com/folke/lazy.nvim) automatically:
- Installs all plugins
- Treesitter downloads and compiles all language parsers

LSP servers, formatters, and linters are **not** installed by Neovim — `initd` bootstrap installs them via `mise` (see [Tool installation (mise)](#tool-installation-mise) below).

Wait for everything to finish, then restart Neovim. Run `:checkhealth` to verify.

### 4. Language-specific external setup

A small number of languages need extra setup beyond what mise + Homebrew install — see the [Language Support](#language-support) table for details.

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
│ Text objects  │ │ Hover docs   │ │  CLI tools)      │
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
- Text objects (select a function, a block, etc.)

Treesitter parsers are compiled native libraries. The `tree-sitter-cli` binary is required to build them. Parsers are auto-installed on first launch from `lua/user/treesitter.lua`.

> ⚠️ Treesitter gives you *highlighting* — it does **not** know about types, errors, or completions. That's LSP's job.

---

### Tool installation (mise)

LSP servers, formatters, and linters are **not** managed by Neovim. They are installed by [mise](https://mise.jdx.dev/) via `~/.config/initd/shared/configs/mise/.config/mise/config.toml`. mise puts shims in `~/.local/share/mise/shims` on `PATH` ahead of Homebrew, so Neovim's `vim.fn.executable()` checks find everything.

```
mise tool sources (one committed file, every machine identical):

~/.config/initd/shared/configs/mise/.config/mise/config.toml
  ├── runtimes                 ← go, node, python, dotnet, terraform
  ├── LSP servers              ← lua_ls, gopls, pyright, ruff, ts_ls, taplo, …
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

vim.lsp.buf.format()
      │
      └──► none-ls client            → runs the right CLI tool:
                │
                ├── Lua     → stylua
                ├── Go      → goimports
                ├── JS/TS   → prettier
                ├── C#      → csharpier
                └── YAML    → yamlfmt
```

> **Why not just use the LSP formatter directly?** Some LSP servers (like `ts_ls` and `lua_ls`) have built-in formatters that don't match your preferred style tool. None-ls lets you override them with the exact tool you want. For those servers, the built-in formatter is explicitly disabled in this config.

> **Python is the exception.** Python lint + format + import-sorting all come from ruff's own LSP server, not none-ls. Format-on-save is registered centrally in `lsp/handlers.lua` (the `LspAttach` autocmd) and routed per-filetype: ruff formats python, none-ls formats everything else. ruff's hover is suppressed so pyright provides it, and pyright's "organize imports" is disabled so ruff owns it.

---

### Completion

`nvim-cmp` is the completion engine. It aggregates suggestions from multiple sources and displays them in a unified popup.

```
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
| **Go** | gopls | goimports | golangci_lint | neotest-golang |
| **TypeScript / JavaScript** | ts_ls | prettierd | eslint_d¹ | neotest-jest / neotest-vitest² |
| **JSON** | jsonls | prettierd | — | — |
| **HTML** | html + emmet_ls | prettierd | — | — |
| **CSS / SCSS** | — | prettierd | stylelint | — |
| **YAML** | yamlls | yamlfmt | yamllint | — |
| **Bash** | bashls | — | — | — |
| **TOML** | taplo | — | — | — |
| **Terraform / HCL** | terraformls | terraform_fmt | terraformls | — |
| **C#** | csharp_ls | csharpier | — | neotest-vstest |
| **Dockerfile** | dockerls | — | hadolint | — |

> ¹ ESLint diagnostics only activate when `.eslintrc` or `eslint.config.js` is present in the project.
> ² Jest adapter activates with `jest.config.*`; Vitest adapter activates with `vitest.config.*` or `vite.config.*`.
> ³ Runs the project's own `pytest` (venv / mise / system python), not a mise-managed tool — make sure `pytest` is installed in the project environment.

---

#### ⚪ Treesitter-only — highlighting only, no LSP/formatting

These languages have syntax highlighting via Treesitter but no LSP server or formatter configured:

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
| Dockerfile | ✓ | dockerls provides LSP; hadolint provides linting |
| Protocol Buffers | ✓ | — |
| SQL | ✓ | Highlighting only — no LSP configured |
| Regex | ✓ | Embedded in other languages |

---

## Key Commands

| Command | Description |
|---------|-------------|
| `:Lazy` | Open plugin manager — update/install plugins |
| `:TSUpdate` | Update Treesitter parsers managed by nvim-treesitter |
| `:LspInfo` | Show LSP clients attached to the current buffer |
| `:NullLsInfo` | Show none-ls sources active in the current buffer |
| `:Neotest summary` | Open test suite explorer |
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

### LSP (active when an LSP is attached)

| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gri` | Go to implementation |
| `grr` | Find references |
| `K` | Hover documentation |
| `<leader>fm` | Format buffer |
| `grn` | Rename symbol |
| `gra` | Code actions |
| `gl` | Open diagnostics float |
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

---

## Adding a New Language

Adding a language is now a two-place change: the tool binary goes into `mise/.config/mise/config.toml`, and Neovim is told to consume it.

1. **Tool binary (mise)** — add the LSP server or lint/format CLI to `mise/.config/mise/config.toml`. Tools live in mise's core registry where possible (`gopls`, `pyright`, `stylua`, …) and otherwise use a backend prefix:

   | Backend | Use for | Example |
   |---------|---------|---------|
   | (none)  | Core registry (Go, Rust, prebuilt binaries) | `"gopls" = "latest"` |
   | `npm:`  | Node-based tools                            | `"npm:bash-language-server" = "latest"` |
   | `pipx:` | Python tools (pipx installed via Homebrew)  | `"pipx:yamllint" = "latest"` |
   | `go:`   | Tools built from a Go module path           | `"go:github.com/mgechev/revive" = "latest"` |
   | `dotnet:` | .NET global tools                          | `"dotnet:csharpier" = "latest"` |

   Run `mise install` after editing.

2. **LSP server (Neovim)** — add the server name to `lsp_servers` in `lua/user/lsp/servers.lua`. Find the correct name in the [nvim-lspconfig server list](https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md). Add a settings file at `lua/user/lsp/settings/<server_name>.lua` if needed.

3. **Formatter / Linter (Neovim)** — add the corresponding none-ls source in `lua/user/lsp/null-ls.lua`. (There is no separate Neovim-side install list anymore — mise is the single source of truth for the binary.)

4. **Treesitter** — no committed parser list is required. `lua/user/treesitter.lua` auto-installs a parser the first time a supported filetype is opened.

5. **External tools** — if the language requires pip packages or system tools that genuinely cannot be installed by mise, document it in the [External Setup](#-requires-external-setup) section above.
