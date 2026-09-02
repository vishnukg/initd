local options = {
	backup = false,
	clipboard = "unnamedplus",
	cmdheight = 1,
	completeopt = { "menuone", "noselect" },
	conceallevel = 0,
	fileencoding = "utf-8",
	hlsearch = true,
	ignorecase = true,
	mouse = "a",
	pumheight = 10,
	showmode = false,
	smartcase = true,
	smartindent = true,
	splitbelow = true,
	splitright = true,
	swapfile = false,
	termguicolors = true,
	timeoutlen = 500,
	undofile = true,
	updatetime = 300,
	writebackup = false,
	expandtab = true,
	shiftwidth = 4,
	tabstop = 4,
	cursorline = true,
	number = true,
	relativenumber = true,
	numberwidth = 4,
	signcolumn = "yes",
	wrap = false,
	scrolloff = 8,
	sidescrolloff = 8,
	guifont = "monospace:h17",
	guicursor = "",
	autoread = true,
}
vim.opt.shortmess:append("c")

-- Neovim has no built-in detection for .bru; without this syntax/bru.vim never loads.
vim.filetype.add({ extension = { bru = "bru" } })

-- Auto-reload buffers when files change on disk (e.g. changed by Claude/Copilot)
-- TermClose/TermLeave catch changes made from a terminal inside nvim (toggleterm)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermClose", "TermLeave" }, {
	group = vim.api.nvim_create_augroup("AutoReload", { clear = true }),
	pattern = "*",
	callback = function()
		if vim.fn.mode() ~= "c" then
			vim.cmd("checktime")
		end
	end,
})

for k, v in pairs(options) do
	vim.opt[k] = v
end

vim.opt.whichwrap:append("<,>,[,],h,l")
vim.opt.foldenable = false
vim.opt.foldlevel = 99
vim.opt.iskeyword:append("-")
vim.opt.formatoptions:remove({ "c", "r", "o" })
vim.opt.fillchars:append({ eob = " " })
vim.o.winborder = "rounded"

-- Insert mode: use absolute line numbers and no cursorline to reduce redraws
local insert_mode_group = vim.api.nvim_create_augroup("InsertMode", { clear = true })
vim.api.nvim_create_autocmd("InsertEnter", {
	group = insert_mode_group,
	callback = function()
		vim.opt_local.relativenumber = false
		vim.opt_local.cursorline = false
	end,
})
vim.api.nvim_create_autocmd("InsertLeave", {
	group = insert_mode_group,
	callback = function()
		vim.opt_local.relativenumber = true
		vim.opt_local.cursorline = true
	end,
})
