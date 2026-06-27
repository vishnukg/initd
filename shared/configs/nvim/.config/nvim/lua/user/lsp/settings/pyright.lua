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
				diagnosticMode = "workspace",
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
