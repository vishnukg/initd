-- ruff language server: python linting + formatting + import sorting.
-- Type-checking is ty's, and ruff defers hover to it via hover_disabled in
-- lsp/handlers.lua. ty needs no counterpart settings file: it discovers the
-- project's .venv and pyproject.toml itself, and advertises only a `quickfix`
-- code action, so there is no competing "organize imports" to switch off.
--
-- settings must encode as a JSON object: an empty Lua table {} becomes a JSON
-- array [], which ruff rejects ("invalid client settings"). vim.empty_dict()
-- forces {}.

-- Checks ty also reports, so ruff stands down and each issue is raised once.
-- The delegation runs this way round because ty cannot be configured from the
-- editor at all — its rules live only in ty.toml / [tool.ty.rules], and
-- settings sent over LSP are ignored — whereas ruff's are set right here.
--   F821 undefined name  → ty `unresolved-reference` (error)
--   F841 unused variable → ty's unused hint
-- F401 deliberately stays with ruff: ty does not flag unused imports at all.
local ty_owned = { "F821", "F841" }

-- ruff's own default select is only E4/E7/E9/F — correctness, nothing else. A
-- mutable default argument (`def f(tags=[])`), a redundant `if` that could be a
-- ternary, or `typing.List` on 3.9+ all pass silently. These add the checks
-- worth having with no project config to state otherwise.
local default_rules = {
	"B",   -- flake8-bugbear: mutable defaults, loop-variable capture, bare except
	"SIM", -- flake8-simplify
	"UP",  -- pyupgrade: modernise for the project's requires-python
}

-- True when the project states its own ruff policy. Same rule as the
-- golangci-lint source in lsp/null-ls.lua: a repo that has declared a lint
-- policy owns it, and nvim must not quietly widen it.
local function has_ruff_config(root)
	if not root then
		return false
	end

	for _, name in ipairs({ "ruff.toml", ".ruff.toml" }) do
		if vim.uv.fs_stat(root .. "/" .. name) then
			return true
		end
	end

	local pyproject = root .. "/pyproject.toml"
	if not vim.uv.fs_stat(pyproject) then
		return false
	end

	-- pcall because io.lines throws on an unreadable file, and a throw in
	-- before_init takes the whole client down with it. An unreadable
	-- pyproject.toml reads as "no policy declared" — the same answer as no file.
	local ok, declared = pcall(function()
		-- Matches [tool.ruff] and every subtable ([tool.ruff.lint], .format, …).
		for line in io.lines(pyproject) do
			if line:match("^%s*%[tool%.ruff[%.%]]") then
				return true
			end
		end
		return false
	end)

	return ok and declared
end

return {
	before_init = function(params, config)
		-- Deduplicating against ty is an editor-integration concern, not a lint
		-- policy, so it applies even to a project that states its own rules.
		local lint = { ignore = ty_owned }

		-- Widening the rule set is a policy call, so it defers to the project.
		if not has_ruff_config(config.root_dir) then
			lint.extendSelect = default_rules
		end

		-- init_options is sent as-is in the initialize request, so this reassign
		-- is safe (client.settings aliasing only affects `settings`).
		params.initializationOptions = { settings = { lint = lint } }
	end,

	-- Only reached if before_init is somehow skipped; ruff rejects a bare {}.
	init_options = {
		settings = vim.empty_dict(),
	},
}
