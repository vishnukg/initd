local null_ls = require("null-ls")
local h = require("null-ls.helpers")

local formatting = null_ls.builtins.formatting
local diagnostics = null_ls.builtins.diagnostics

local taplo = h.make_builtin({
	name = "taplo",
	meta = { url = "https://taplo.tamasfe.dev/", description = "TOML formatter" },
	method = require("null-ls.methods").internal.FORMATTING,
	filetypes = { "toml" },
	generator_opts = {
		command = "taplo",
		args = { "fmt", "--option", "align_entries=true", "--option", "align_comments=true", "-" },
		to_stdin = true,
	},
	factory = h.formatter_factory,
})

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
		formatting.goimports,
		formatting.terraform_fmt,
		formatting.csharpier,
		taplo,
		formatting.yamlfmt,
		diagnostics.golangci_lint,
		diagnostics.yamllint,
		diagnostics.hadolint,
		require("none-ls.diagnostics.eslint").with({
			dynamic_command = require("null-ls.helpers.command_resolver").from_node_modules,
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
