-- LSP servers — binaries are provided by mise (see mise/config.toml).
-- nvim just enables them; install/upgrade is `mise install` / `mise upgrade`.
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
	"dockerls",
	"ruby_lsp",
}

local handlers = require("user.lsp.handlers")

for _, server in ipairs(lsp_servers) do
	local opts = { capabilities = handlers.capabilities }

	local ok, server_opts = pcall(require, "user.lsp.settings." .. server)
	if ok then
		opts = vim.tbl_deep_extend("force", opts, server_opts)
	end

	vim.lsp.config(server, opts)
	vim.lsp.enable(server)
end
