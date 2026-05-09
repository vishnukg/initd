local M = {}

require("toggleterm").setup({
	size = 20,
	open_mapping = [[<c-\>]],
	hide_numbers = true,
	shade_filetypes = {},
	shade_terminals = true,
	shading_factor = 2,
	start_in_insert = true,
	insert_mappings = true,
	persist_size = true,
	direction = "float",
	close_on_exit = true,
	shell = vim.o.shell,
	float_opts = {
		border = "curved",
		winblend = 0,
		highlights = {
			border = "Normal",
			background = "Normal",
		},
	},
})

-- Keymaps for navigating out of a terminal buffer (back to normal windows)
local function set_terminal_keymaps()
	local opts = { noremap = true, buffer = 0 }
	vim.keymap.set("t", "<esc>",  [[<C-\><C-n>]],        opts)
	vim.keymap.set("t", "jk",     [[<C-\><C-n>]],        opts)
	vim.keymap.set("t", "<C-h>",  [[<C-\><C-n><C-W>h]],  opts)
	vim.keymap.set("t", "<C-j>",  [[<C-\><C-n><C-W>j]],  opts)
	vim.keymap.set("t", "<C-k>",  [[<C-\><C-n><C-W>k]],  opts)
	vim.keymap.set("t", "<C-l>",  [[<C-\><C-n><C-W>l]],  opts)
end

vim.api.nvim_create_autocmd("TermOpen", {
	group = vim.api.nvim_create_augroup("TerminalKeymaps", { clear = true }),
	pattern = "term://*",
	callback = set_terminal_keymaps,
})

-- Lazygit terminal — lazily initialised on first toggle
local lazygit_term

function M.toggle_lazygit()
	if not lazygit_term then
		lazygit_term = require("toggleterm.terminal").Terminal:new({
			cmd = "lazygit",
			hidden = true,
		})
	end
	lazygit_term:toggle()
end

return M
