local null_ls = require("null-ls")
local h = require("null-ls.helpers")

local formatting = null_ls.builtins.formatting
local diagnostics = null_ls.builtins.diagnostics
local golangci_config_files = {
	".golangci.yml",
	".golangci.yaml",
	".golangci.toml",
	".golangci.json",
}

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

-- Format-on-save is registered centrally in lsp/handlers.lua (LspAttach), which
-- selects one available formatter — preferring null-ls here and ruff for Python.
-- null-ls only needs to register its sources.
null_ls.setup({
	debug = false,
	sources = {
		formatting.prettierd.with({
			disabled_filetypes = { "yaml" },
			condition = function(utils)
				return utils.root_has_file({
					".prettierrc",
					".prettierrc.js",
					".prettierrc.cjs",
					".prettierrc.mjs",
					".prettierrc.json",
					".prettierrc.json5",
					".prettierrc.yaml",
					".prettierrc.yml",
					".prettierrc.toml",
					"prettier.config.js",
					"prettier.config.cjs",
					"prettier.config.mjs",
					"prettier.config.ts",
				})
			end,
		}),
		formatting.stylua,
		formatting.goimports,
		formatting.terraform_fmt,
		formatting.csharpier,
		taplo,
		formatting.yamlfmt,
		-- golangci-lint is intentionally project-scoped and runs on save. gopls
		-- remains the fast baseline when a repository has no lint policy.
		diagnostics.golangci_lint.with({
			runtime_condition = function(params)
				-- Evaluate per buffer rather than once at plugin startup, so opening
				-- projects with different policies in one Neovim session is safe.
				return vim.fs.root(params.bufname, golangci_config_files) ~= nil
			end,
		}),
		diagnostics.yamllint,
		diagnostics.hadolint,
		diagnostics.stylelint.with({
			condition = function(utils)
				return utils.root_has_file({
					".stylelintrc",
					".stylelintrc.json",
					".stylelintrc.yaml",
					".stylelintrc.yml",
					".stylelintrc.js",
					".stylelintrc.cjs",
					"stylelint.config.js",
					"stylelint.config.cjs",
					"stylelint.config.mjs",
					"stylelint.config.ts",
				})
			end,
		}),
		require("none-ls.diagnostics.eslint_d").with({
			condition = function(utils)
				return utils.root_has_file({
					".eslintrc",
					".eslintrc.js",
					".eslintrc.cjs",
					".eslintrc.json",
					".eslintrc.yaml",
					".eslintrc.yml",
					"eslint.config.js",
					"eslint.config.mjs",
					"eslint.config.cjs",
					"eslint.config.ts",
				})
			end,
		}),
	},
})
