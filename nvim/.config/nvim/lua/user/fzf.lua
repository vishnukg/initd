local status_ok, fzf = pcall(require, "fzf-lua")
if not status_ok then
	return
end

fzf.setup({
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
