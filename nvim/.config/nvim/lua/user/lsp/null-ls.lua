-- null_ls.setup() checks vim.fn.executable() for each source. On macOS,
-- /opt/homebrew/bin is not always in vim.env.PATH at this point even when
-- fish has it set correctly — something in the lazy.nvim load sequence resets
-- it. Prepending here, immediately before setup runs, is the reliable fix.
if vim.fn.has("mac") == 1 then
	vim.env.PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:" .. vim.env.PATH
end

local null_ls = require("null-ls")

local formatting = null_ls.builtins.formatting
local diagnostics = null_ls.builtins.diagnostics

-- LspFormatting
local augroup = vim.api.nvim_create_augroup("LspFormatting", { clear = true })

local function lsp_format_on_save(client, bufnr)
	if client:supports_method("textDocument/formatting") then
		vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = augroup,
			buffer = bufnr,
			callback = function()
				vim.lsp.buf.format({ async = false, filter = function(c) return c.name == "null-ls" end })
			end,
		})
	end
end

null_ls.setup({
	debug = false,
	sources = {
		-- See user/lsp/mason.lua for which tools are managed by Mason vs Homebrew.
		formatting.prettierd.with({ disabled_filetypes = { "yaml" } }),
		formatting.black.with({ extra_args = { "--fast" } }),
		formatting.stylua,
		formatting.goimports,
		formatting.terraform_fmt,
		formatting.csharpier,
		formatting.yamlfmt,
		diagnostics.golangci_lint,
		diagnostics.yamllint,
		diagnostics.hadolint,
		require("none-ls.diagnostics.eslint").with({
			condition = function(utils)
				return utils.root_has_file({
					".eslintrc",
					".eslintrc.js",
					".eslintrc.json",
					".eslintrc.yaml",
					".eslintrc.yml",
					"eslint.config.js",
					"eslint.config.mjs",
				})
			end,
		}),
	},
	on_attach = lsp_format_on_save,
})
