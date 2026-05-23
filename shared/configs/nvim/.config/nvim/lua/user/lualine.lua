local lualine = require("lualine")

-- Matches tmux tab colors:
--   active tab:   bg=#111116  fg=#4ec994
--   inactive tab: bg=#111116  fg=#9aa5ce
local tmux_theme = {
	normal = {
		a = { bg = "#111116", fg = "#89b4fa", gui = "bold" },
		b = { bg = "#111116", fg = "#9aa5ce" },
		c = { bg = "#111116", fg = "#9aa5ce" },
	},
	insert  = { a = { bg = "#111116", fg = "#9ece6a", gui = "bold" } },
	visual  = { a = { bg = "#111116", fg = "#bb9af7", gui = "bold" } },
	replace = { a = { bg = "#111116", fg = "#f7768e", gui = "bold" } },
	command = { a = { bg = "#111116", fg = "#e0af68", gui = "bold" } },
	inactive = {
		a = { bg = "#111116", fg = "#9aa5ce" },
		b = { bg = "#111116", fg = "#9aa5ce" },
		c = { bg = "#111116", fg = "#727169" },
	},
}

lualine.setup({
	options = {
		icons_enabled = true,
		theme = tmux_theme,
		component_separators = { left = "", right = "" },
		section_separators   = { left = "", right = "" },
		globalstatus = true,
		refresh = { statusline = 250, tabline = 250 },
	},
	sections = {
		lualine_a = { "mode" },
		lualine_b = { "branch", "diff", "diagnostics" },
		lualine_c = { { "filename", path = 1, symbols = { modified = "[+]", readonly = "", unnamed = "[No Name]", newfile = "[New]" }, color = { fg = "#9aa5ce" }, symbols_color = { modified = { fg = "#4ec994", gui = "bold" } } } },
		lualine_x = { "encoding", "fileformat", "filetype" },
		lualine_y = { "progress" },
		lualine_z = { "location" },
	},
	inactive_sections = {
		lualine_c = { "filename" },
		lualine_x = { "location" },
	},
})
