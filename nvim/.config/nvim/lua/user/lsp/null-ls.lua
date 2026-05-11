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
		formatting.prettierd.with({ disabled_filetypes = { "yaml" } }),
		formatting.black.with({ extra_args = { "--fast" } }),
		formatting.stylua,
		-- goimports is installed via Go toolchain (go install golang.org/x/tools/cmd/goimports@latest), not Mason.
		formatting.goimports,
		-- terraform_fmt is bundled with the terraform binary (Homebrew: brew install terraform), not Mason.
		formatting.terraform_fmt,
		formatting.csharpier,
		-- yamlfmt is installed via Homebrew (brew install yamlfmt), not Mason.
		formatting.yamlfmt,
		-- golangci_lint is installed via Homebrew (brew install golangci-lint), not Mason.
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
