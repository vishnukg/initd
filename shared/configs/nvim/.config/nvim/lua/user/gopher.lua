-- Go: struct tags, if-err, impl — not an LSP tool, so it does not overlap gopls.
-- Helper binaries come from mise (see mise/config.toml), not :GoInstallDeps.
require("gopher").setup({
	commands = { gotests = "gotests" },
	gotag = {
		transform   = "camelcase",
		default_tag = "json",
		option      = nil, -- omitempty should be added per field, not by default
	},
})
