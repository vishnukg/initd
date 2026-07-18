return {
	settings = {
		-- ruff owns import sorting; stop pyright offering a competing
		-- "organize imports" code action.
		pyright = {
			disableOrganizeImports = true,
		},
		python = {
			analysis = {
				typeCheckingMode = "basic",
				autoSearchPaths = true,
				useLibraryCodeForTypes = true,
				-- Analyse open files eagerly; avoids indexing every Python file in
				-- large monorepos while preserving editor diagnostics.
				diagnosticMode = "openFilesOnly",
				-- ruff owns linting (Pyflakes-class checks); silence pyright's
				-- overlapping rules so each issue is reported once. pyright still
				-- does everything ruff can't — type errors.
				diagnosticSeverityOverrides = {
					reportUndefinedVariable = "none", -- ruff F821
					reportUnusedImport = "none",      -- ruff F401
					reportUnusedVariable = "none",    -- ruff F841
					reportUnusedExpression = "none",  -- ruff B018 / pyflakes
				},
				inlayHints = {
					variableTypes = true,
					functionReturnTypes = true,
					callArgumentNames = true,
					pytestParameters = true,
				},
			},
		},
	},
}
