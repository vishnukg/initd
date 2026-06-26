-- Formatting + diagnostics are owned by null-ls (standardrb), consistent with the
-- rest of the stack (black/prettier/etc). Disable ruby-lsp's own formatter/linter
-- so diagnostics aren't duplicated; ruby-lsp still handles hover/completion/nav.
return {
	init_options = {
		formatter = "none",
		linters = {},
	},
}
