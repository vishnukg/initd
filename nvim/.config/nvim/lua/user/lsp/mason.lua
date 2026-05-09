-- =========================
-- Linting/Formatting Tools
-- =========================
local lint_and_format = {
	-- Linters
	"pylint",
	"revive",
	"stylelint",
	"yamllint",
	"eslint_d",
	-- Formatters
	"black",
	"csharpier",
	"prettierd",
	"stylua",
	"yamlfmt",
	"hadolint",
}

-- =========================
-- LSP Servers
-- =========================
local lsp_servers = {
	"lua_ls",
	"html",
	"ts_ls",
	"pyright",
	"bashls",
	"jsonls",
	"gopls",
	"yamlls",
	"emmet_ls",
	"taplo",
	"terraformls",
	"csharp_ls",
	"postgres_lsp",
	"ruby_lsp",
	"dockerls",
}

-- =========================
-- Mason Setup
-- =========================
require("mason").setup({
	ui = {
		border = "none",
		icons = {
			package_installed = "✓",
			package_pending = "⏳",
			package_uninstalled = "✗",
		},
	},
	log_level = vim.log.levels.INFO,
	max_concurrent_installers = 4,
})

-- =========================
-- Mason-null-ls Setup
-- =========================
require("mason-null-ls").setup({
	ensure_installed = lint_and_format,
	automatic_installation = true,
})

-- =========================
-- Mason-lspconfig Setup
-- =========================
require("mason-lspconfig").setup({
	ensure_installed = lsp_servers,
	automatic_installation = true,
	automatic_enable = false,
})

-- =========================
-- LSP Servers Setup
-- =========================
-- on_attach is intentionally omitted here — the LspAttach autocmd in
-- handlers.lua handles keymaps, inlay hints, and formatting-disable logic
-- for all clients. capabilities are still set per-server.
local handlers = require("user.lsp.handlers")

for _, server in ipairs(lsp_servers) do
	server = vim.split(server, "@")[1]

	local opts = { capabilities = handlers.capabilities }

	-- Merge server-specific settings if available
	local ok, server_opts = pcall(require, "user.lsp.settings." .. server)
	if ok then
		opts = vim.tbl_deep_extend("force", opts, server_opts)
	end

	vim.lsp.config(server, opts)
	vim.lsp.enable(server)
end
