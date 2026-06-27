-- ruff language server: python linting + formatting + import sorting.
-- Type-checking stays with pyright (see settings/pyright.lua). ruff defers
-- hover to pyright via hover_disabled in lsp/handlers.lua, and pyright defers
-- import organizing to ruff via disableOrganizeImports.
--
-- Defaults respect any pyproject.toml / ruff.toml / .ruff.toml in the project
-- root. Add overrides under init_options.settings when there is no project file
-- (e.g. lineLength, lint = { select = { ... } }, format = { ... }).
return {
	init_options = {
		settings = {},
	},
}
