-- TypeScript 7's built-in LSP (the native Go rewrite — no more tsserver).
-- lspconfig's old "tsgo" server expected a `tsgo` binary from
-- @typescript/native-preview, but that package is phased out and the server
-- itself is deprecated as of nvim-lspconfig (removal planned for 3.0.0) in
-- favor of this "tsc" server — typescript@7 ships the same binary as `tsc`,
-- which enters LSP mode with --lsp. Use the mise-provided `tsc` executable
-- from PATH so the same config works across macOS/Linux and custom mise
-- data dirs, rather than lspconfig's own default cmd (which also checks
-- node_modules/.bin first).
local inlay_hints = {
	parameterNames = {
		enabled = "literals",
		suppressWhenArgumentMatchesName = true,
	},
	parameterTypes = { enabled = true },
	variableTypes = { enabled = false },
	propertyDeclarationTypes = { enabled = true },
	functionLikeReturnTypes = { enabled = false },
	enumMemberValues = { enabled = false },
}

local code_lens = {
	referencesCodeLens = {
		enabled = true,
		showOnAllFunctions = true,
	},
	implementationsCodeLens = {
		enabled = true,
	},
}

return {
	cmd = {
		"tsc",
		"--lsp",
		"--stdio",
	},
	settings = {
		typescript = vim.tbl_extend("force", { inlayHints = inlay_hints }, code_lens),
		javascript = vim.tbl_extend("force", { inlayHints = inlay_hints }, code_lens),
	},
}
