-- LSP servers — binaries are provided by mise (see mise/config.toml).
-- nvim just enables them; install/upgrade is `mise install` / `mise upgrade`.
local lsp_servers = {
	"lua_ls",
	"html",
	"tsc",
	"pyright",
	"ruff",
	"bashls",
	"jsonls",
	"gopls",
	"yamlls",
	"emmet_ls",
	"taplo",
	"terraformls",
	"roslyn_ls",
	"dockerls",
}

local handlers = require("user.lsp.handlers")

for _, server in ipairs(lsp_servers) do
	local opts = { capabilities = handlers.capabilities }

	local ok, server_opts = pcall(require, "user.lsp.settings." .. server)
	if ok then
		opts = vim.tbl_deep_extend("force", opts, server_opts)
	elseif not tostring(server_opts):find("not found", 1, true) then
		-- Settings module exists but failed to load (syntax error etc.) —
		-- surface it instead of silently starting the server with defaults.
		error(server_opts)
	end

	vim.lsp.config(server, opts)
	vim.lsp.enable(server)
end
