-- TypeScript 7's built-in LSP (the native Go rewrite — no more tsserver).
-- lspconfig's "tsc" server picks the binary itself: a project-local
-- node_modules/.bin/tsc if it is 7.0+ (supports --lsp), else the mise-provided
-- `tsc` on PATH, so no cmd override is needed here. Only settings differ.
-- Keep literal argument labels; inferred types add too much inline clutter.
local inlay_hints = {
	parameterNames = {
		enabled = "literals",
		suppressWhenArgumentMatchesName = true,
	},
	parameterTypes = { enabled = false },
	variableTypes = { enabled = false },
	propertyDeclarationTypes = { enabled = false },
	functionLikeReturnTypes = { enabled = false },
	enumMemberValues = { enabled = true },
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
	settings = {
		typescript = vim.tbl_extend("force", { inlayHints = inlay_hints }, code_lens),
		javascript = vim.tbl_extend("force", { inlayHints = inlay_hints }, code_lens),
	},
}
