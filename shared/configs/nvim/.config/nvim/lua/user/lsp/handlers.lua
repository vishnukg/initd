local M = {}

-- cmp-nvim-lsp is a dependency of nvim-lspconfig so it's always loaded first.
M.capabilities = require("cmp_nvim_lsp").default_capabilities()

-- Servers where none-ls handles formatting — disable the native LSP formatter
-- so we don't get two competing format-on-save triggers.
local formatting_disabled = { tsgo = true, lua_ls = true, gopls = true }

-- Per-filetype preferred formatter, keyed by LSP client name. Filetypes not
-- listed here fall back to null-ls, which owns formatting for everything else.
-- (Python is formatted by ruff's own LSP, not null-ls.)
local preferred_formatter = { python = "ruff" }

-- Servers whose hover we suppress so another client provides it instead.
-- ruff defers hover to pyright (which has richer type info).
local hover_disabled = { ruff = true }

local fmt_augroup = vim.api.nvim_create_augroup("LspFormatting", { clear = true })

-- Build a vim.lsp.buf.format filter that keeps only the right formatter client
-- for the given buffer's filetype.
local function format_filter(bufnr)
	local preferred = preferred_formatter[vim.bo[bufnr].filetype]
	return function(client)
		return client.name == (preferred or "null-ls")
	end
end

-- Keymaps applied to every buffer where an LSP client attaches.
-- 0.12 built-in defaults (no explicit mapping needed):
--   K        → hover documentation
--   gra      → code actions
--   grn      → rename symbol
--   grr      → show references
--   gri      → go to implementation
--   grt      → go to type definition
--   grl      → run codelens
--   gO       → list document symbols
--   <C-S>    → signature help (insert + select mode)
local function lsp_keymaps(bufnr)
	local opts = { noremap = true, silent = true, buffer = bufnr }
	vim.keymap.set("n", "gd",  vim.lsp.buf.definition,    vim.tbl_extend("force", opts, { desc = "LSP: go to definition" }))
	vim.keymap.set("n", "gD",  vim.lsp.buf.declaration,   vim.tbl_extend("force", opts, { desc = "LSP: go to declaration" }))
	vim.keymap.set("n", "grl", vim.lsp.codelens.run,      vim.tbl_extend("force", opts, { desc = "LSP: run codelens" }))
	vim.keymap.set("n", "gl",  vim.diagnostic.open_float, vim.tbl_extend("force", opts, { desc = "LSP: open diagnostic float" }))
	vim.keymap.set("n", "gch", vim.lsp.buf.incoming_calls,vim.tbl_extend("force", opts, { desc = "LSP: incoming calls" }))
	vim.keymap.set("n", "gth", function() vim.lsp.buf.typehierarchy("supertypes") end,
		vim.tbl_extend("force", opts, { desc = "LSP: type supertypes" }))
	vim.keymap.set("n", "gtH", function() vim.lsp.buf.typehierarchy("subtypes") end,
		vim.tbl_extend("force", opts, { desc = "LSP: type subtypes" }))
	vim.keymap.set("n", "<leader>fm", function() vim.lsp.buf.format({ async = true }) end,
		vim.tbl_extend("force", opts, { desc = "LSP: format buffer" }))
	vim.keymap.set("n", "<leader>li", "<cmd>LspInfo<CR>",  vim.tbl_extend("force", opts, { desc = "LSP: info" }))
	vim.keymap.set("n", "<leader>lj", function() vim.diagnostic.jump({ count =  1, float = true }) end,
		vim.tbl_extend("force", opts, { desc = "LSP: next diagnostic" }))
	vim.keymap.set("n", "<leader>lk", function() vim.diagnostic.jump({ count = -1, float = true }) end,
		vim.tbl_extend("force", opts, { desc = "LSP: prev diagnostic" }))
	vim.keymap.set("n", "<leader>ls", vim.lsp.buf.signature_help,
		vim.tbl_extend("force", opts, { desc = "LSP: signature help" }))
	vim.keymap.set("n", "<leader>lq", vim.diagnostic.setloclist,
		vim.tbl_extend("force", opts, { desc = "LSP: send diagnostics to loclist" }))
end

M.setup = function()
	-- Enable codelens globally. The capability check automatically gates it per
	-- client, so no per-buffer guard is needed.
	vim.lsp.codelens.enable(true)

	vim.diagnostic.config({
		virtual_text = true,
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "",
				[vim.diagnostic.severity.WARN]  = "",
				[vim.diagnostic.severity.HINT]  = "",
				[vim.diagnostic.severity.INFO]  = "",
			},
		},
		update_in_insert = false,
		underline = true,
		severity_sort = true,
		float = {
			focusable = true,
			style = "minimal",
			source = true,
			header = "",
			prefix = "",
		},
	})

	-- nvim 0.12 pattern: use LspAttach autocmd instead of per-server on_attach.
	-- Fires once per (client, buffer) pair whenever an LSP client attaches.
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client then return end
			local bufnr = args.buf

			-- Disable native formatter so none-ls/null-ls takes over exclusively
			if formatting_disabled[client.name] then
				client.server_capabilities.documentFormattingProvider = false
			end

			-- Suppress hover where another client owns it (ruff → pyright).
			if hover_disabled[client.name] then
				client.server_capabilities.hoverProvider = false
			end

			-- Format-on-save. Registered once per buffer (idempotent: cleared
			-- first). The filter routes each filetype to its preferred formatter
			-- (ruff for python, null-ls otherwise).
			if client:supports_method("textDocument/formatting") then
				vim.api.nvim_clear_autocmds({ group = fmt_augroup, buffer = bufnr })
				vim.api.nvim_create_autocmd("BufWritePre", {
					group = fmt_augroup,
					buffer = bufnr,
					callback = function()
						vim.lsp.buf.format({ async = false, filter = format_filter(bufnr) })
					end,
				})
			end

			-- Inlay hints (skip csharp_ls: tends to be too noisy)
			if client.server_capabilities.inlayHintProvider and client.name ~= "csharp_ls" then
				vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
			end

			lsp_keymaps(bufnr)
		end,
	})
end

return M
