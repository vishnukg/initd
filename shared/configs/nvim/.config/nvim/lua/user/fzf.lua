require("fzf-lua").setup({
	buffers = {
		fzf_opts = {
			["--header-lines"] = false,
		},
	},
	keymap = {
		fzf = {
			["ctrl-n"] = "down",
			["ctrl-p"] = "up",
		},
	},
	winopts = {
		preview = {
			scrollbar = false,
		},
	},
})
