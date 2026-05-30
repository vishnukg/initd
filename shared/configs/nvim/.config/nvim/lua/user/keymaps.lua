-- All keymaps live here. LSP-specific keymaps are in lua/user/lsp/handlers.lua
-- (they need the buffer number from LspAttach and are registered per-buffer).

local map = vim.keymap.set
local o = { noremap = true, silent = true }
local function d(desc) return vim.tbl_extend("force", o, { desc = desc }) end

-- ── Escape shortcuts ──────────────────────────────────────────────────────────
map("i", "jk", "<ESC>", d("Exit insert mode"))
map("i", "kj", "<ESC>", d("Exit insert mode"))

-- ── Save ──────────────────────────────────────────────────────────────────────
map("",  "<leader><leader>", ":wa<cr>",  d("Save all buffers"))
map("n", "ZZ", "<cmd>xa<CR>", d("Write all and quit"))
map("n", "ZQ", "<cmd>qa!<CR>", d("Quit all without saving"))

-- ── Search ────────────────────────────────────────────────────────────────────
map("n", "<C-l>", ":noh<cr><C-l>", d("Clear search highlight"))

-- ── Disable macros (q) ────────────────────────────────────────────────────────
map("n", "q", "<Nop>", o)

-- ── Arrow key training wheels ─────────────────────────────────────────────────
map("n", "<Left>",  ':echoe "Use h"<cr>', o)
map("n", "<Right>", ':echoe "Use l"<cr>', o)
map("n", "<Up>",    ':echoe "Use k"<cr>', o)
map("n", "<Down>",  ':echoe "Use j"<cr>', o)

-- ── Window resize ─────────────────────────────────────────────────────────────
map("n", "<A-Up>",    ":resize +2<CR>",          d("Resize: taller"))
map("n", "<A-Down>",  ":resize -2<CR>",          d("Resize: shorter"))
map("n", "<A-Left>",  ":vertical resize -2<CR>", d("Resize: narrower"))
map("n", "<A-Right>", ":vertical resize +2<CR>", d("Resize: wider"))
map("n", "<C-w><lt>", ":vertical resize -2<CR>", d("Resize: narrower"))
map("n", "<C-w>>",    ":vertical resize +2<CR>", d("Resize: wider"))

-- ── Buffer navigation ─────────────────────────────────────────────────────────
map("n", "<S-l>", ":bnext<CR>",     d("Next buffer"))
map("n", "<S-h>", ":bprevious<CR>", d("Prev buffer"))

-- ── Visual mode ───────────────────────────────────────────────────────────────
map("v", "<",     "<gv",       d("Indent left (stay in visual)"))
map("v", ">",     ">gv",       d("Indent right (stay in visual)"))
map("v", "<A-j>", ":m .+1<CR>==", d("Move line down"))
map("v", "<A-k>", ":m .-2<CR>==", d("Move line up"))
map("v", "p",     '"_dP',      d("Paste without yanking replaced text"))

-- ── FzfLua ────────────────────────────────────────────────────────────────────
map("n", "<leader>ff", ":FzfLua files<CR>",      d("FZF: find files"))
map("n", "<leader>fg", ":FzfLua live_grep<CR>",  d("FZF: live grep"))
map("n", "<leader>fb", ":FzfLua buffers<CR>",    d("FZF: buffers"))

-- ── File tree ─────────────────────────────────────────────────────────────────
map("n", "<C-g>", ":NvimTreeToggle<cr>", d("Toggle file tree"))

-- ── Search and replace (grug-far) ────────────────────────────────────────────
map("n", "<leader>sp", function() require("grug-far").open() end,                              d("Search & replace"))
map("n", "<leader>sw", function() require("grug-far").open({ prefills = { search = vim.fn.expand("<cword>") } }) end, d("Search & replace word"))

-- ── Diff ──────────────────────────────────────────────────────────────────────
map("n", "<leader>df", ":windo diffthis<CR>", d("Diff split buffers"))

-- ── Neotest ───────────────────────────────────────────────────────────────────
local function neotest() return require("neotest") end
map("n", "<leader>tr", function() neotest().run.run() end,                    d("Test: run nearest"))
map("n", "<leader>tf", function() neotest().run.run(vim.fn.expand("%")) end,  d("Test: run file"))
map("n", "<leader>ts", function() neotest().summary.toggle() end,             d("Test: toggle summary"))
map("n", "<leader>to", function() neotest().output.open({ enter = true }) end,d("Test: show output"))

-- ── Copilot Chat ──────────────────────────────────────────────────────────────
map("n", "<leader>co",  "<cmd>Copilot toggle<CR>",     d("Copilot: toggle"))
map("n", "<leader>cp",  "<cmd>CopilotChat<CR>",        d("Copilot Chat: open"))
map("n", "<leader>cpe", "<cmd>CopilotChatExplain<CR>", d("Copilot Chat: explain"))
map("n", "<leader>cpt", "<cmd>CopilotChatTests<CR>",   d("Copilot Chat: write tests"))
map("n", "<leader>cpr", "<cmd>CopilotChatReset<CR>",   d("Copilot Chat: reset"))

-- ── Trouble ───────────────────────────────────────────────────────────────────
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>",             d("Trouble: workspace diagnostics"))
map("n", "<leader>xd", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>",d("Trouble: buffer diagnostics"))

-- ── Tabs ──────────────────────────────────────────────────────────────────────
map("n", "<leader>nt", "<cmd>tabnew<CR>", d("New tab"))

-- ── Markdown ──────────────────────────────────────────────────────────────────
map("n", "<leader>vm", "<cmd>RenderMarkdown toggle<CR>", d("Toggle markdown rendering"))

-- ── Coverage ──────────────────────────────────────────────────────────────────
map("n", "gcv",         "<cmd>Coverage<CR>",        d("Coverage: load & show"))
map("n", "<leader>cvs", "<cmd>CoverageSummary<CR>", d("Coverage: summary"))
map("n", "<leader>hcv", "<cmd>CoverageHide<CR>",    d("Coverage: hide"))
map("n", "<leader>ccv", "<cmd>CoverageClear<CR>",   d("Coverage: clear"))

-- ── Go (gopher.nvim) ──────────────────────────────────────────────────────────
-- Add struct tags
map("n", "<leader>gaj", "<cmd>GoTagAdd json<CR>", d("Go: add json tag"))
map("n", "<leader>gay", "<cmd>GoTagAdd yaml<CR>", d("Go: add yaml tag"))
map("n", "<leader>gax", "<cmd>GoTagAdd xml<CR>",  d("Go: add xml tag"))
map("n", "<leader>gae", "<cmd>GoTagAdd env<CR>",  d("Go: add env tag"))
map("n", "<leader>gad", "<cmd>GoTagAdd db<CR>",   d("Go: add db tag"))
-- Remove struct tags
map("n", "<leader>grj", "<cmd>GoTagRm json<CR>",  d("Go: remove json tag"))
map("n", "<leader>gry", "<cmd>GoTagRm yaml<CR>",  d("Go: remove yaml tag"))
map("n", "<leader>grx", "<cmd>GoTagRm xml<CR>",   d("Go: remove xml tag"))
map("n", "<leader>gre", "<cmd>GoTagRm env<CR>",   d("Go: remove env tag"))
map("n", "<leader>grd", "<cmd>GoTagRm db<CR>",    d("Go: remove db tag"))
-- Code generation
map("n", "<leader>gie", "<cmd>GoIfErr<CR>",  d("Go: add if-err block"))
map("n", "<leader>gim", "<cmd>GoImpl<CR>",   d("Go: implement interface"))

-- ── Folding ───────────────────────────────────────────────────────────────────
map("n", "<leader>ft",  "za", d("Fold: toggle at cursor"))
map("n", "<leader>fC",  "zc", d("Fold: close at cursor"))
map("n", "<leader>foc", "zo", d("Fold: open at cursor"))
map("n", "<leader>fO",  "zR", d("Fold: open all"))
map("n", "<leader>fc",  "zM", d("Fold: close all"))
map("n", "<leader>fT",  "zA", d("Fold: toggle recursively at cursor"))
