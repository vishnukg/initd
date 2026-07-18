-- Register LspAttach autocmd BEFORE enabling any servers so no attach event
-- fires before our keymaps, inlay hints, and formatter selection are wired up.
require("user.lsp.handlers").setup()
require("user.lsp.null-ls")
require("user.lsp.servers")
