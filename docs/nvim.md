# Neovim Config Reference

A reference for reading and editing this config. Covers Vim fundamentals, Lua, and the patterns used throughout.

---

## Table of Contents

1. [Vim fundamentals](#vim-fundamentals)
   - [Modes](#modes)
   - [Buffers, windows, and tabs](#buffers-windows-and-tabs)
   - [The command line (ex commands)](#the-command-line-ex-commands)
   - [Motions and operators](#motions-and-operators)
   - [Marks](#marks)
   - [Registers](#registers)
   - [The leader key](#the-leader-key)
   - [Options system](#options-system)
2. [Lua primer](#lua-primer)
   - [Variables](#variables)
   - [Tables](#tables)
   - [Functions](#functions)
   - [Control flow](#control-flow)
   - [String operations](#string-operations)
   - [Multiple return values](#multiple-return-values)
   - [pcall — error handling](#pcall--error-handling)
   - [Modules](#modules)
3. [Neovim Lua API](#neovim-lua-api)
   - [vim.opt — setting options](#vimopt--setting-options)
   - [vim.g / vim.b / vim.w / vim.o](#vimg--vimb--vimw--vimo)
   - [vim.keymap.set](#vimkeymapset)
   - [Autocmds and augroups](#autocmds-and-augroups)
   - [User commands](#user-commands)
   - [vim.notify and vim.schedule](#vimnotify-and-vimschedule)
   - [vim.tbl_extend](#vimtbl_extend)
4. [How this config is structured](#how-this-config-is-structured)
5. [Key patterns](#key-patterns)
   - [Plugin config callback (lazy.nvim)](#plugin-config-callback-lazynvim)
   - [LspAttach autocmd](#lspattach-autocmd)
   - [vim.lsp.config + vim.lsp.enable](#vimlspconfig--vimlspenable)
   - [Format on save](#format-on-save-one-selected-client)
   - [How LSP loads when you open a file](#how-lsp-loads-when-you-open-a-file)
   - [How treesitter loads when you open a file](#how-treesitter-loads-when-you-open-a-file)
   - [Auto-reload when an external process edits a file](#auto-reload-when-an-external-process-edits-a-file)

---

## Vim fundamentals

### Modes

Vim is modal — the same keys do different things depending on which mode you're in.

| Mode | How to enter | What it's for |
|------|-------------|---------------|
| **Normal** | `<Esc>` from any mode | Navigation, operators, commands. The default/resting mode. |
| **Insert** | `i` (before cursor), `a` (after), `o` (new line below), `O` (new line above) | Typing text. |
| **Visual** | `v` (char), `V` (line), `<C-v>` (block) | Selecting text to operate on. |
| **Visual Block** | `<C-v>` | Column editing — insert on multiple lines at once. |
| **Command** | `:` | Ex commands (`:w`, `:q`, `:s///`, `:lua`, etc.). |
| **Terminal** | `:terminal` then `i` | Running a shell inside Neovim. |
| **Select** | `<C-g>` in visual | Like visual but typed text replaces selection (rarely used manually). |
| **Operator-pending** | After an operator (`d`, `c`, `y`) | Waiting for a motion to complete the operation. |

`<Esc>` always returns to Normal. In terminal mode, `<C-\><C-n>` exits to Normal.

### Buffers, windows, and tabs

These three concepts are often confused:

**Buffer** — an in-memory copy of a file (or an unnamed scratch space). Closing a window does not delete the buffer.
```
:ls          -- list all open buffers
:b <name>    -- switch to buffer by name/number
:bd          -- delete (close) current buffer
:bn / :bp    -- next / previous buffer
```

**Window** — a viewport onto a buffer. Multiple windows can show the same buffer simultaneously.
```
:split  / <C-w>s   -- horizontal split
:vsplit / <C-w>v   -- vertical split
<C-w>w             -- cycle through windows
<C-w>h/j/k/l       -- move to window left/down/up/right
<C-w>q             -- close current window
<C-w>=             -- equalize window sizes
```

**Tab** — a named collection of windows (not like browser tabs; each tab is a full window layout).
```
:tabnew        -- open a new tab
:tabnext / gt  -- next tab
:tabprev / gT  -- previous tab
:tabclose      -- close current tab
```

In practice: open many buffers, use a few windows per tab, rarely use multiple tabs.

### The command line (ex commands)

Press `:` to open the command line. These are "ex commands" (from the old `ex` editor).

```
:w              -- write (save) current file
:q              -- quit (fails if unsaved changes)
:wq / :x        -- write and quit
:q!             -- quit without saving
:e filename     -- open a file
:r filename     -- read file into buffer at cursor
:!cmd           -- run shell command
:lua print(1+1) -- execute Lua
:%s/old/new/g   -- substitute across whole file
:10,20s/old/new -- substitute on lines 10–20
```

### Motions and operators

Operators act on a region defined by a motion (or text object).

**Common operators:**
```
d   -- delete (cut)
c   -- change (delete + enter insert mode)
y   -- yank (copy)
>   -- indent right
<   -- indent left
=   -- auto-indent
```

**Common motions:**
```
h j k l      -- left / down / up / right
w / b        -- next / previous word start
e            -- end of word
0 / ^        -- start of line (with/without whitespace)
$            -- end of line
gg / G       -- first / last line of file
{ / }        -- previous / next blank-line-separated paragraph
%            -- jump to matching bracket
f<char>      -- find char forward on line (F = backward)
t<char>      -- till char (one before it)
```

**Text objects** (used after an operator):
```
iw / aw   -- inner word / a word (with surrounding space)
i" / a"   -- inside quotes / quotes + quotes
i( / a(   -- inside parens / parens + parens
ip / ap   -- inner paragraph / paragraph
it / at   -- inner tag / tag (HTML/XML)
```

Example: `ci"` = change inside quotes, `da(` = delete a set of parens and everything inside.

**Counts** multiply a motion or operator: `3w` = 3 words forward, `d2j` = delete 2 lines down.

### Marks

Marks remember positions you can jump back to.

```
ma       -- set mark 'a' at cursor (lowercase = buffer-local)
'a       -- jump to line of mark 'a'
`a       -- jump to exact position of mark 'a'
mA       -- set mark 'A' (uppercase = global, persists across files)
:marks   -- list all marks
```

Special marks set automatically:
```
''  / ``   -- position before last jump
'.  / `.   -- position of last change
'^  / `^   -- position of last insert
```

### Registers

Registers are named clipboards. There are many; these are the important ones:

| Register | What it holds |
|----------|--------------|
| `"` (unnamed) | Last deleted/yanked text — what `p` pastes |
| `0` | Last yanked text (not affected by delete) |
| `a`–`z` | Named registers — set with `"ay`, paste with `"ap` |
| `+` | System clipboard |
| `*` | Primary selection (X11) / system clipboard (macOS) |
| `_` | Black hole — send here to delete without affecting unnamed register |
| `%` | Current filename |
| `:` | Last ex command |
| `/` | Last search pattern |

```
"ayy   -- yank line into register a
"ap    -- paste from register a
"+p    -- paste from system clipboard
"_dd   -- delete line without affecting unnamed register
:reg   -- show all registers
```

This config sets `clipboard = "unnamedplus"` so `p` and `y` use the system clipboard directly.

### The leader key

`<leader>` is a prefix key with no built-in meaning — it's your namespace for custom shortcuts.

```lua
vim.g.mapleader = "\\"   -- set in bootstrap.lua before any plugin loads
```

So `<leader>ff` means: press backslash, then `f`, then `f` (`\ff`). The leader keeps custom multi-key shortcuts in one predictable namespace.

### Options system

Vim/Neovim has hundreds of options. They exist at different scopes:

| Scope | Lua API | Example |
|-------|---------|---------|
| Global | `vim.o` or `vim.opt` | `vim.o.wrap = false` |
| Buffer-local | `vim.bo` or `vim.opt_local` | `vim.bo.shiftwidth = 2` |
| Window-local | `vim.wo` or `vim.opt_local` | `vim.wo.number = true` |
| Scoped window (0.12+) | `vim.wo[0][0]` | Window 0, buffer 0 — sets buffer-local window opt |

`vim.opt` is the recommended general-purpose setter: it handles list-options (`:append`, `:remove`, `:prepend`) correctly and merges buffer/window scoping automatically.

```lua
vim.opt.number = true         -- same as :set number
vim.opt.tabstop = 4           -- same as :set tabstop=4
vim.opt.shortmess:append("c") -- same as :set shortmess+=c
vim.opt.formatoptions:remove({ "c", "r", "o" })
```

Use `:help 'optionname'` (with single quotes) to read the docs for any option.

---

## Lua primer

### Variables

```lua
local x = 42           -- local to current scope (always use local)
x = 42                 -- global — avoid; pollutes the global namespace

local s = "hello"
local t = true
local n = nil          -- nil means unset / nothing
```

### Tables

Tables are Lua's only data structure — they serve as arrays, dicts, objects, and namespaces.

```lua
-- Array-style (1-indexed, not 0)
local fruits = { "apple", "banana", "cherry" }
print(fruits[1])        -- "apple"

-- Dict-style
local opts = { noremap = true, silent = true }
print(opts.noremap)     -- true
print(opts["noremap"])  -- same thing

-- Mixed / nested
local config = {
    lsp = {
        servers = { "gopls", "tsc" },
    },
}
print(config.lsp.servers[1])  -- "gopls"

-- Append to an array table
local t = { 1, 2 }
table.insert(t, 3)     -- { 1, 2, 3 }
table.remove(t, 1)     -- removes index 1 → { 2, 3 }
#t                     -- length: 2
```

### Functions

```lua
-- Named function
local function greet(name)
    return "Hello, " .. name
end

-- Anonymous function (common in keymaps/callbacks)
local fn = function(x) return x * 2 end

-- Functions are first-class values — pass them around
vim.keymap.set("n", "<leader>x", function() print("hi") end)

-- Calling with a single table or string: parens are optional
require("lazy")          -- same as require("lazy")
```

### Control flow

```lua
if x > 0 then
    -- ...
elseif x == 0 then
    -- ...
else
    -- ...
end

-- Numeric for (1 to 5 inclusive)
for i = 1, 5 do print(i) end

-- Generic for: all key-value pairs (unordered)
for key, value in pairs({ a = 1, b = 2 }) do
    print(key, value)
end

-- ipairs: array portion in order (stops at first nil gap)
for i, v in ipairs({ "x", "y", "z" }) do
    print(i, v)
end

-- while loop
while condition do ... end

-- repeat ... until (executes at least once)
repeat ... until condition
```

### String operations

```lua
local a = "hello" .. " " .. "world"  -- concatenation: "hello world"
local n = #a                          -- length: 11
a:upper()                             -- "HELLO WORLD"
a:sub(1, 5)                           -- "hello" (1-indexed, inclusive)
a:match("(%a+)")                      -- first word: "hello"
a:find("world")                       -- returns start, end positions
string.format("count: %d", 42)        -- "count: 42"
```

### Multiple return values

```lua
local function minmax(t)
    return math.min(table.unpack(t)), math.max(table.unpack(t))
end
local lo, hi = minmax({ 3, 1, 4, 1, 5 })
-- lo = 1, hi = 5
```

### pcall — error handling

```lua
local ok, result = pcall(require, "some-plugin")
if not ok then
    -- plugin not installed or failed to load; result is the error message
    return
end
-- result is the module
```

`pcall` catches any error from the function call and returns `false, err` instead of crashing. In this config, `pcall` guards are mostly removed from plugin config files because those files are only called from lazy.nvim's `config =` callback — at that point the plugin is guaranteed loaded.

### Modules

```lua
-- my_module.lua
local M = {}

function M.greet(name)
    return "hi " .. name
end

return M

-- elsewhere:
local mod = require("my_module")
mod.greet("world")
```

`require` caches results — calling it twice returns the same table without re-running the file. The `lua/` directory in `runtimepath` is the search root: `require("user.lsp.handlers")` loads `lua/user/lsp/handlers.lua`.

---

## Neovim Lua API

### vim.opt — setting options

```lua
vim.opt.number = true              -- :set number
vim.opt.tabstop = 4                -- :set tabstop=4
vim.opt.clipboard = "unnamedplus"  -- :set clipboard=unnamedplus
vim.opt.shortmess:append("c")      -- :set shortmess+=c  (append to list-option)
vim.opt.whichwrap:remove("b")      -- :set whichwrap-=b
vim.opt.formatoptions:prepend("j") -- :set formatoptions^=j
```

### vim.g / vim.b / vim.w / vim.o

```lua
vim.g.mapleader = "\\"     -- global Neovim variable (g:mapleader in Vimscript)
vim.b.my_flag = true       -- buffer-local variable (b:my_flag)
vim.w.fold_level = 3       -- window-local variable (w:fold_level)
vim.o.wrap = false         -- raw global option (no list-option handling)
vim.bo.shiftwidth = 2      -- buffer-local option for current buffer
vim.wo.number = true       -- window-local option for current window
vim.wo[0][0].foldexpr = "…" -- buffer-local window option (nvim 0.12)
```

### vim.keymap.set

```lua
vim.keymap.set(mode, lhs, rhs, opts)
```

- **mode**: `"n"` normal, `"i"` insert, `"v"` visual+select, `"x"` visual only, `"t"` terminal, `"o"` operator-pending, `""` all modes
- **lhs**: key combination, e.g. `"<leader>ff"`, `"<C-h>"`, `"<S-Tab>"`
- **rhs**: string command (`:FzfLua files<CR>`) or Lua function
- **opts**: `{ noremap, silent, desc, buffer, expr, nowait, … }`

```lua
-- Lua callback; require() also triggers lazy.nvim's module loader
vim.keymap.set("n", "<leader>ff", function()
    require("fzf-lua").files()
end, { noremap = true, silent = true, desc = "FZF: find files" })

-- Lua function
vim.keymap.set("n", "<leader>gt", function()
    require("user.toggleterm").toggle_lazygit()
end, { desc = "Toggle lazygit" })

-- Buffer-local (only active in one buffer)
vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr, desc = "Go to definition" })
```

Always add `desc = "…"` — it shows up in mapping inspection and any UI that consumes Neovim's keymap descriptions.

### Autocmds and augroups

**Autocmds** run Lua (or Vimscript) automatically when an event fires.

```lua
vim.api.nvim_create_autocmd(event, opts)
```

Common events:

| Event | Fires when |
|-------|-----------|
| `BufReadPre` | Before reading a file into a buffer — fires on every `:e file` or buffer open, before content is loaded |
| `BufNewFile` | When opening a path that doesn't exist yet (companion to `BufReadPre`) |
| `BufWritePre` | Before a buffer is written to disk |
| `BufWritePost` | After a buffer is written |
| `BufEnter` | Entering a buffer |
| `FileType` | After filetype detection sets `&filetype` |
| `LspAttach` | An LSP client attaches to a buffer |
| `InsertEnter` | Entering insert mode |
| `VimEnter` | After Neovim finishes startup |
| `FocusGained` | Neovim window regains focus |
| `CursorHold` | Cursor hasn't moved for `updatetime` ms |

```lua
vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.go",          -- glob filter (omit or use "*" for all files)
    callback = function(args)
        -- args.buf    = buffer number
        -- args.match  = the matched pattern (filename or filetype)
        -- args.data   = event-specific data (e.g. client_id for LspAttach)
        vim.lsp.buf.format({ bufnr = args.buf })
    end,
})
```

**Augroups** (autocmd groups) bundle related autocmds so they can be cleared together. Without `clear = true`, re-sourcing the config file would duplicate the autocmd on every reload.

```lua
local group = vim.api.nvim_create_augroup("MyGroup", { clear = true })
-- clear = true: remove all autocmds in this group before re-registering

vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "lua",
    callback = function()
        vim.bo.shiftwidth = 2
    end,
})
```

**Rule**: every persistent autocmd in this config belongs to an augroup with `clear = true`. This is what makes the config safe to `:source` multiple times.

To list all autocmds: `:autocmd`
To delete an augroup and all its autocmds: `vim.api.nvim_del_augroup_by_name("MyGroup")`

### User commands

```lua
vim.api.nvim_create_user_command("Hello", function(opts)
    print("Hello " .. opts.args)
end, {
    nargs = "?",          -- 0 or 1 arg
    complete = "file",    -- tab-completion source
    desc = "Say hello",
})
-- Usage: :Hello world
```

### vim.notify and vim.schedule

```lua
vim.notify("something happened", vim.log.levels.WARN)
-- Levels: DEBUG, INFO, WARN, ERROR

-- vim.schedule defers to the next event loop tick — required when calling
-- Neovim APIs from inside async callbacks or fast-event handlers
vim.schedule(function()
    vim.notify("async result ready")
end)
```

### vim.tbl_extend

```lua
-- Shallow merge (last table wins on conflict)
local merged = vim.tbl_extend("force", { a = 1 }, { a = 2, b = 3 })
-- { a = 2, b = 3 }

-- Deep merge (recurses into nested tables)
local deep = vim.tbl_deep_extend("force", { lsp = { a = 1 } }, { lsp = { b = 2 } })
-- { lsp = { a = 1, b = 2 } }

-- Common use: add desc to a shared opts table
local opts = { noremap = true, silent = true, buffer = bufnr }
vim.keymap.set("n", "gd", vim.lsp.buf.definition,
    vim.tbl_extend("force", opts, { desc = "Go to definition" }))
```

---

## How this config is structured

```
nvim/.config/nvim/
├── init.lua                ← entry point: loads bootstrap then user/
└── lua/
    ├── bootstrap.lua       ← vim.g.* globals set BEFORE any plugin loads
    │                         (leader key, provider disables)
    └── user/
        ├── init.lua        ← loads options, keymaps, then plugins (lazy.nvim)
        ├── options.lua     ← vim.opt.* settings and persistent autocmds
        ├── keymaps.lua     ← all global keymaps
        ├── plugins.lua     ← lazy.nvim plugin spec; each plugin has config= callback
        ├── colorscheme.lua ← vscode.nvim setup + highlight overrides
        ├── lsp/
        │   ├── init.lua    ← requires handlers, null-ls, servers (in this order)
        │   ├── handlers.lua← capabilities, diagnostic config, LspAttach autocmd
        │   ├── servers.lua ← vim.lsp.config + vim.lsp.enable for each server
        │   ├── null-ls.lua ← none-ls formatters and linters
        │   └── settings/   ← per-server settings returned as tables
        ├── cmp.lua         ← nvim-cmp completion setup
        ├── treesitter.lua  ← treesitter setup + auto-install + FileType attach
        ├── nvimtree.lua    ← file explorer
        ├── lualine.lua     ← status line
        ├── gitsigns.lua    ← git gutter signs
        ├── toggleterm.lua  ← floating terminal + lazygit
        ├── fzf.lua         ← fuzzy finder
        ├── fidget.lua      ← LSP progress notifications
        ├── neotest.lua     ← test runner adapters
        ├── coverage.lua    ← test coverage overlays
        ├── gopher.lua      ← Go struct/code-generation helpers
        └── autopairs.lua   ← auto-close brackets/quotes
```

**Startup sequence:**

1. `init.lua` → `bootstrap.lua` (sets `mapleader`, disables providers)
2. `user/init.lua` → `options.lua`, `keymaps.lua`
3. `user/plugins.lua` → lazy.nvim initialises, installs missing plugins, and loads startup plugins (colorscheme and Treesitter)
4. Treesitter registers its `FileType` autocmd during startup; other plugins load from their `event`, `cmd`, `keys`, or module trigger
5. When a file is opened: the LSP group loads on `BufReadPre` → `FileType` attaches Treesitter → clients attach asynchronously → `LspAttach` registers keymaps, hints, and format-on-save

---

## Key patterns

### Plugin config callback (lazy.nvim)

```lua
{
    "author/plugin.nvim",
    event = "InsertEnter",   -- lazy-load trigger; plugin loads on this event
    config = function()
        require("user.plugin-config")  -- runs AFTER the plugin is loaded
    end,
}
```

Common lazy-load triggers:

| Field | Meaning |
|-------|---------|
| `event = "InsertEnter"` | Load when entering insert mode (common for completion) |
| `event = "VeryLazy"` | Load after UI, ~100ms after startup |
| `event = { "BufReadPre", "BufNewFile" }` | Load before reading any file — used by the LSP stack |
| `ft = "go"` | Load only for Go files |
| `cmd = "NvimTreeToggle"` | Load when this command is first run |
| `lazy = false` | Load immediately at startup — required by the current nvim-treesitter main branch |
| `priority = 1000` | Load before other startup plugins (use for colorschemes) |

**Why `config =` matters**: Before this was in place, `require("user.X")` calls in `user/init.lua` ran at startup — before plugins had loaded. The `pcall(require, …)` guard silently returned nil and the plugin was **never configured**. All plugin-specific config now lives in `config =` callbacks where the plugin is guaranteed to exist.

### LspAttach autocmd

```lua
vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client then return end
        local bufnr = args.buf

        -- register buffer-local keymaps
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr })

        -- enable inlay hints for this buffer
        if client.server_capabilities.inlayHintProvider then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
    end,
})
```

This is the **nvim 0.12 pattern**. It replaces the old `on_attach = function(client, bufnr)` per-server callback. One autocmd handles all clients uniformly — no need to pass `on_attach` to every `lspconfig.X.setup()` call.

**Order matters**: register `LspAttach` before calling `vim.lsp.enable()`. Otherwise the first attach event fires before the autocmd exists and those buffers get no keymaps.

### vim.lsp.config + vim.lsp.enable

```lua
-- Configure a server (decoupled from activation)
vim.lsp.config("gopls", {
    capabilities = caps,
    settings = {
        gopls = { analyses = { unusedparams = true } },
    },
})

-- Activate it (starts the server when a matching file is opened)
vim.lsp.enable("gopls")
```

This is the built-in LSP configuration API used by this Neovim 0.12+ config. It replaces `require("lspconfig").gopls.setup({ … })`: configuration is declared once, while `vim.lsp.enable` starts the matching server when a relevant file is opened.

### Format on save (one selected client)

```lua
-- handlers.lua chooses exactly one client for the current buffer:
--   1. filetype override (ruff for Python)
--   2. an available none-ls formatter
--   3. a native LSP formatter
local client = format_client(bufnr)
if client then
    vim.lsp.buf.format({ bufnr = bufnr, async = false, id = client.id })
end
```

The `BufWritePre` autocmd is registered centrally from `LspAttach` and cleared before re-registering, so a buffer gets one save hook even when several clients attach. Selection is recalculated on every save. None-ls sources can be conditional: Prettierd, ESLint, and Stylelint activate only when their corresponding project config exists; a native formatter remains available as fallback.

Current ownership is deliberate: Ruff formats and lints Python while ty provides types and completion; goimports formats Go while gopls provides the always-on staticcheck baseline, with golangci-lint added on save only for repositories containing a `.golangci.{yml,yaml,toml,json}` policy; project-local Prettier wins for supported web files, with native LSP formatting used when available otherwise.

### How LSP loads when you open a file

The entire LSP stack (nvim-lspconfig + none-ls) is set to `event = { "BufReadPre", "BufNewFile" }`. Here's what happens the moment you open e.g. a Go file:

1. **`BufReadPre` fires** — lazy.nvim sees the event and loads the LSP plugin group.
2. **`config =` callbacks run** — `servers.lua` is called, which runs `vim.lsp.config(server, opts)` and `vim.lsp.enable(server)` for every server in its list (including `gopls`).
3. **Server starts asynchronously** — `vim.lsp.enable` launches the server binary (resolved from `PATH` via the mise shim dir) in the background. Neovim is never blocked; you can type immediately.
4. **`LspAttach` fires** (once the server is ready) — `handlers.lua`'s autocmd registers buffer-local keymaps and enables inlay hints for that buffer.
5. **none-ls attaches where sources apply** — the central `LspAttach` handler keeps one `BufWritePre` autocmd and the formatter selector prefers an available none-ls source.

Any perceived delay after opening a file comes primarily from the language server starting and indexing the project. The LSP plugin group loads on `BufReadPre`, while heavy test and coverage adapters stay unloaded until their mappings or commands are used.

### How treesitter loads when you open a file

The current nvim-treesitter main branch does not support lazy-loading, so its plugin spec uses `lazy = false`. It starts with Neovim and registers the attach autocmd before any initial filetype event can be missed.

1. **Startup config runs** — `treesitter.setup()` sets the install directory, ensures injection parsers, and registers a `FileType` autocmd.
2. **`FileType` fires** after detection — the autocmd resolves the parser language and calls `try_attach(buf, language)`.
3. Two cases from there:
   - **Parser already on runtimepath** (including one bundled with Neovim): `vim.treesitter.start()` enables highlighting, folding, and supported indentation.
   - **Parser missing but available in the registry**: Treesitter installs it asynchronously and attaches if the originating buffer still exists.

Folding switches temporarily to manual mode during insert mode to avoid per-keystroke fold recomputation, then returns to Treesitter expression folds on `InsertLeave`.

### Auto-reload when an external process edits a file

When an external tool (Claude, Copilot, a code generator) edits a file that's already open in Neovim, Neovim doesn't know the file changed — it keeps showing the stale in-memory buffer. This setup makes Neovim reload silently and automatically.

**Three pieces work together:**

**1. `autoread = true` (options.lua)**

Tells Neovim: if a buffer has no unsaved changes and the file on disk has changed, reload it automatically instead of asking. Without this, `:checktime` would prompt you to confirm every reload. With it, the reload is silent.

**2. `updatetime = 300` (options.lua)**

Controls how long Neovim waits with the cursor idle before firing `CursorHold`. Lower = more responsive reloads when you're not typing. 300ms is a good balance — fast enough to feel instant, not so low that it causes LSP diagnostic churn (diagnostics are also debounced by `updatetime`).

**3. The `AutoReload` autocmd (options.lua)**

```lua
vim.api.nvim_create_autocmd({
    "FocusGained", "BufEnter", "CursorHold", "TermClose", "TermLeave",
}, {
    group = vim.api.nvim_create_augroup("AutoReload", { clear = true }),
    pattern = "*",
    callback = function()
        if vim.fn.mode() ~= "c" then
            vim.cmd("checktime")
        end
    end,
})
```

`:checktime` is what actually asks Neovim to re-read the file from disk and trigger `autoread`. Without an autocmd calling `checktime`, Neovim would only check when you switch focus or run it manually.

Why each event:

| Event | When it fires | Why it's here |
|-------|--------------|---------------|
| `FocusGained` | Neovim window regains OS focus | Instant reload the moment you switch from the Claude pane back to Vim |
| `BufEnter` | Entering a buffer (e.g. switching with `:b`) | Catches changes when you cycle between open buffers |
| `CursorHold` | Cursor idle for `updatetime` ms in normal mode | Polls while you're watching; no keypress needed |
| `TermClose` / `TermLeave` | Leaving a Neovim terminal or its process exits | Picks up edits made from toggleterm or another terminal command |

The `mode() ~= "c"` guard skips `checktime` while you're typing a `:` command — calling it mid-command could interrupt the command line.

**Why `FocusGained` requires a tmux setting**

Inside tmux, terminal applications don't receive focus events by default — tmux intercepts them. `set -g focus-events on` (already in `tmux.conf`) tells tmux to forward focus in/out escape sequences (`\033[I` / `\033[O`) to the active pane. Without it, switching from the Claude pane to the Vim pane never fires `FocusGained` and the most responsive trigger is lost.

**Why not `vim.uv.new_fs_event()`?**

Neovim also exposes libuv's OS-level file watcher (`vim.uv.new_fs_event()`), which is truly event-driven — it reacts the instant the OS signals a file change, with no polling interval. But it requires managing the watcher lifecycle (stop on `BufDelete`, handle errors, restart if the file is replaced rather than mutated). The API also already changed once: it was `vim.loop` before Neovim 0.10 renamed it to `vim.uv`. For a personal dotfile, the maintenance cost isn't worth it. The `CursorHold` approach with 300ms `updatetime` is imperceptibly fast and has been stable across Vim and Neovim for over a decade.
