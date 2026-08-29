-- Resolve the interpreter pyright analyses against. pyright does NOT discover
-- `.venv/` on its own: with no pythonPath it falls back to the first `python3`
-- on PATH (here, mise's), so in a uv/venv project every third-party import
-- resolves to nothing — `reportMissingImports` on the import line and no
-- completion for anything the package exports.
--
-- The project's own venv wins over $VIRTUAL_ENV so that editing project A from
-- a shell with project B activated still analyses against A.
local function interpreter(root)
	if root then
		for _, dir in ipairs({ ".venv", "venv" }) do
			local py = root .. "/" .. dir .. "/bin/python"
			if vim.uv.fs_stat(py) then
				return py
			end
		end
	end

	local active = vim.env.VIRTUAL_ENV
	if active and active ~= "" and vim.uv.fs_stat(active .. "/bin/python") then
		return active .. "/bin/python"
	end

	return nil
end

return {
	before_init = function(_, config)
		local py = interpreter(config.root_dir)
		if not py then
			return
		end

		-- Mutate in place. vim.lsp.Client aliases config.settings at creation
		-- (`settings = config.settings or {}`) and before_init runs afterwards,
		-- so *reassigning* config.settings here would leave client.settings —
		-- the table that answers pyright's workspace/configuration requests —
		-- pointing at the original.
		config.settings.python = vim.tbl_deep_extend("force", config.settings.python or {}, {
			pythonPath = py,
		})
	end,

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
