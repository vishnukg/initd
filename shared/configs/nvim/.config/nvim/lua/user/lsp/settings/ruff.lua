-- ruff language server: python linting + formatting + import sorting.
-- Type-checking stays with pyright (see settings/pyright.lua). ruff defers
-- hover to pyright via hover_disabled in lsp/handlers.lua, and pyright defers
-- import organizing to ruff via disableOrganizeImports.
--
-- settings must encode as a JSON object: an empty Lua table {} becomes a JSON
-- array [], which ruff rejects ("invalid client settings"). vim.empty_dict()
-- forces {}.

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
		if has_ruff_config(config.root_dir) then
			return
		end

		-- init_options is sent as-is in the initialize request, so this reassign
		-- is safe (unlike settings — see the note in settings/pyright.lua).
		params.initializationOptions = {
			settings = { lint = { extendSelect = default_rules } },
		}
	end,

	-- Fallback for a project that does carry its own ruff config: hand the
	-- server an empty object and let it resolve the files itself.
	init_options = {
		settings = vim.empty_dict(),
	},
}
