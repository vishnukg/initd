local nvim_tree = require("nvim-tree")

local function on_attach(bufnr)
	local api = require("nvim-tree.api")
	local function opts(desc)
		return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
	end

	api.config.mappings.default_on_attach(bufnr)

	vim.keymap.set("n", "u", api.tree.change_root_to_parent, opts("Up"))
end

nvim_tree.setup({
	on_attach = on_attach,
	disable_netrw = true,
	hijack_netrw = true,
	hijack_cursor = false,
	sync_root_with_cwd = true,
	view = {
		width = 30,
		adaptive_size = true,
		side = "left",
	},
	update_focused_file = {
		enable = true,
		update_cwd = false,
		ignore_list = {},
	},
	git = {
		enable = true,
		ignore = false,
		timeout = 500,
	},
	renderer = {
		root_folder_label = ":t",
		icons = {
			glyphs = {
				default = "",
				symlink = "",
				folder = {
					arrow_open = "",
					arrow_closed = "",
					default = "",
					open = "",
					empty = "",
					empty_open = "",
					symlink = "",
					symlink_open = "",
				},
				git = {
					unstaged = "",
					staged = "S",
					unmerged = "",
					renamed = "➜",
					untracked = "U",
					deleted = "",
					ignored = "*",
				},
			},
		},
	},
	filters = {
		dotfiles = false,
	},
	actions = {
		open_file = {
			quit_on_open = true,
			window_picker = {
				enable = false,
			},
		},
	},
})

-- Autoclose nvim_tree native option
-- https://github.com/nvim-tree/nvim-tree.lua/wiki/Auto-Close#naive-solution

local nvimtree_augroup = vim.api.nvim_create_augroup("NvimTreeAutoClose", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
	group = nvimtree_augroup,
	nested = true,
	callback = function()
		if #vim.api.nvim_list_wins() == 1 and require("nvim-tree.api").tree.is_tree_buf() then
			local listed = vim.tbl_filter(function(b)
				return vim.bo[b].buflisted and vim.api.nvim_buf_is_valid(b)
			end, vim.api.nvim_list_bufs())
			if #listed > 0 then
				vim.schedule(function()
					vim.api.nvim_command("vsplit | buffer " .. listed[1])
				end)
			else
				vim.schedule(function()
					vim.cmd("quit")
				end)
			end
		end
	end,
})

