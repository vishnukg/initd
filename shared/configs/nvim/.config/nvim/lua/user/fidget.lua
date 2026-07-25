require("fidget").setup({
	notification = {
		override_vim_notify = true, -- Route vim.notify to Fidget
		window = {
			winblend = 0, -- Transparency (0 = opaque, 100 = transparent)
			border = "none", -- No border
			max_width = 60, -- Wider for better readability
			max_height = 12,
			x_padding = 2, -- More padding for cleaner look
			y_padding = 1,
			avoid = { "NvimTree" },
		},
		view = {
			stack_upwards = false, -- Display from top to bottom
			icon_separator = "  ", -- Extra space for breathing room
			group_separator = "───", -- Subtle separator between groups
			group_separator_hl = "Comment",
		},
	},
	progress = {
		ignore = { "null-ls" }, -- null-ls fires per buffer; suppress its spinner
		display = {
			render_limit = 16,
			done_ttl = 2, -- How long to show completed messages
			done_icon = "✓", -- Clean checkmark for completion
			done_style = "DiagnosticOk", -- Green success color
			progress_ttl = 10,
			progress_icon = { pattern = "moon", period = 1 }, -- Moon phases animation
			progress_style = "WarningMsg", -- Yellow/orange for in-progress
			group_style = "Title", -- Bold server names
			icon_style = "Question", -- Distinct icon color
			priority = 30,
			skip_history = true, -- Don't clutter notification history
			format_message = function(msg)
				return msg.message or ""
			end,
			format_annote = function(msg)
				return msg.title or ""
			end,
			format_group_name = function(group)
				return "  " .. tostring(group) .. " " -- Icon prefix for server names
			end,
		},
		lsp = {
			progress_ringbuf_size = 0, -- Disable if too noisy
		},
	},
})

-- Neovim reports missing paths from an LSP watch registration as an INFO
-- notification (for example, gopls may register a non-existent vendor/
-- directory in a multi-module workspace). The watch is skipped and LSP
-- features remain functional, so keep this implementation detail out of the
-- notification UI without hiding other notifications.
local fidget_notify = vim.notify
vim.notify = function(msg, level, opts)
	if msg == "watch.watch: ENOENT: no such file or directory" then
		return
	end
	return fidget_notify(msg, level, opts)
end
