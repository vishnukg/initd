local lualine = require("lualine")

-- Matches tmux tab colors:
--   active tab:   bg=#4ec994  fg=#141414
--   inactive tab: bg=#24283b  fg=#7aa2f7
local tmux_theme = {
	normal = {
		a = { bg = "#4ec994", fg = "#141414", gui = "bold" },
		b = { bg = "#24283b", fg = "#7aa2f7" },
		c = { bg = "#24283b", fg = "#7aa2f7" },
	},
	insert  = { a = { bg = "#e0af68", fg = "#141414", gui = "bold" } },
	visual  = { a = { bg = "#f7768e", fg = "#141414", gui = "bold" } },
	replace = { a = { bg = "#e46876", fg = "#141414", gui = "bold" } },
	command = { a = { bg = "#4ec994", fg = "#141414", gui = "bold" } },
	inactive = {
		a = { bg = "#24283b", fg = "#7aa2f7" },
		b = { bg = "#24283b", fg = "#7aa2f7" },
		c = { bg = "#24283b", fg = "#727169" },
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
		lualine_c = { { "filename", path = 1, symbols = { modified = "[+]", readonly = "", unnamed = "[No Name]", newfile = "[New]" }, color = { fg = "#7aa2f7" }, symbols_color = { modified = { fg = "#4ec994", gui = "bold" } } } },
		lualine_x = { "encoding", "fileformat", "filetype" },
		lualine_y = { "progress" },
		lualine_z = { "location" },
	},
	inactive_sections = {
		lualine_c = { "filename" },
		lualine_x = { "location" },
	},
})
