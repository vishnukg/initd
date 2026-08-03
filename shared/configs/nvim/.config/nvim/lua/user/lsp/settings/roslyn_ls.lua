-- nvim-lspconfig defaults both scopes to "fullSolution", which keeps Roslyn
-- analyzing every project in the background; "openFiles" keeps large work
-- solutions cheap. Diagnostics for files you haven't opened won't appear.
return {
	settings = {
		["csharp|background_analysis"] = {
			dotnet_analyzer_diagnostics_scope = "openFiles",
			dotnet_compiler_diagnostics_scope = "openFiles",
		},
	},
}
