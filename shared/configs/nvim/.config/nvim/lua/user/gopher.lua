-- Go: struct tags, if-err, impl — NOT an LSP tool, no interference with gopls.
-- Run :GoInstallDeps once after install.
require("gopher").setup({
	commands = { gotests = "gotests" },
	gotag = {
		transform   = "camelcase",
		default_tag = "json",
		option      = nil, -- omitempty should be added per field, not by default
	},
})

-- Auto-install binaries on first Go file open (only if missing)
if vim.fn.executable("gomodifytags") == 0 then
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "go",
		once = true,
		callback = function() pcall(vim.cmd, "GoInstallDeps") end,
	})
end
