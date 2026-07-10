-- TypeScript 7's built-in LSP (the native Go rewrite — no more tsserver).
-- lspconfig's tsgo config expects a `tsgo` binary from @typescript/native-preview,
-- but that package is phased out: typescript@7 ships the same binary as `tsc`,
-- which enters LSP mode with --lsp. Point at the mise install directly (mise
-- installs npm packages in isolated directories, so PATH resolution via
-- node_modules doesn't apply).
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
		vim.fn.expand("~/.local/share/mise/installs/npm-typescript/latest/bin/tsc"),
		"--lsp",
		"--stdio",
	},
	settings = {
		typescript = vim.tbl_extend("force", { inlayHints = inlay_hints }, code_lens),
		javascript = vim.tbl_extend("force", { inlayHints = inlay_hints }, code_lens),
	},
}
