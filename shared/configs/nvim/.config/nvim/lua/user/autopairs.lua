local npairs = require("nvim-autopairs")

npairs.setup({
	check_ts = true,
	ts_config = {
		lua = { "string", "source" },
		javascript = { "string", "template_string" },
		java = false,
	},
	disable_filetype = { "fzf", "grug-far" },
	fast_wrap = {
		map = "<M-e>",
		chars = { "{", "[", "(", '"', "'" },
		pattern = string.gsub([[ [%'%"%)%>%]%)%}%,] ]], "%s+", ""),
		offset = 0, -- Offset from pattern match
		end_key = "$",
		keys = "qwertyuiopzxcvbnmasdfghjkl",
		check_comma = true,
		highlight = "PmenuSel",
		highlight_grey = "LineNr",
	},
})

-- Wire autopairs into cmp's confirm event so the closing pair is inserted.
-- Guard with pcall: both plugins share the same InsertEnter trigger so load
-- order isn't guaranteed; if nvim-cmp loads after autopairs the hook is a no-op
-- (confirmed completions just won't auto-close, a minor degradation at worst).
local cmp_ok, cmp = pcall(require, "cmp")
if cmp_ok then
	local ap_ok, cmp_autopairs = pcall(require, "nvim-autopairs.completion.cmp")
	if ap_ok then
		cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done({ map_char = { tex = "" } }))
	end
end
