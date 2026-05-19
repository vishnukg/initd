require("fzf-lua").setup({
	buffers = {
		fzf_opts = {
			["--header-lines"] = false,
		},
	},
	keymap = {
		fzf = {
			["ctrl-d"] = "half-page-down",
			["ctrl-n"] = "down",
			["ctrl-p"] = "up",
			["ctrl-u"] = "half-page-up",
		},
	},
	winopts = {
		preview = {
			scrollbar = false,
		},
	},
})
