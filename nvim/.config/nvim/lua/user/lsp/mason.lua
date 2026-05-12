-- =========================
-- Linting/Formatting Tools (Mason-managed)
-- =========================
--
-- The following tools are intentionally NOT in this list — they are managed by
-- Homebrew (see platforms/darwin/Brewfile) instead. The reasons:
--   • black, pylint, yamllint, yamlfmt — Mason installs these via pip and wraps
--     them in a venv. None-ls spawns subprocesses via the system PATH where the
--     wrapper is absent, causing "not executable" errors.
--   • golangci-lint — Mason has known v1/v2 flag-name compatibility issues.
--   • goimports — installed via the Go toolchain (go install).
--   • terraform_fmt — bundled with the terraform binary.
local lint_and_format = {
	-- Linters
	"revive",
	"stylelint",
	"eslint_d",
	-- Formatters
	"csharpier",
	"prettierd",
	"stylua",
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
-- Mason-null-ls Setup
-- =========================
require("mason-null-ls").setup({
	ensure_installed = lint_and_format,
	automatic_installation = false,
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
	local opts = { capabilities = handlers.capabilities }

	-- Merge server-specific settings if available
	local ok, server_opts = pcall(require, "user.lsp.settings." .. server)
	if ok then
		opts = vim.tbl_deep_extend("force", opts, server_opts)
	end

	vim.lsp.config(server, opts)
	vim.lsp.enable(server)
end
