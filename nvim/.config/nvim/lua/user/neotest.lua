local function find_config(path, configs)
	local dir = vim.fn.fnamemodify(path, ":h")
	for _, config in ipairs(configs) do
		local found = vim.fn.findfile(config, dir .. ";")
		if found ~= "" then
			return vim.fn.fnamemodify(found, ":p")
		end
	end
end

local function filter_dir(name)
	return not (name == "node_modules" or name == "dist")
end

require("neotest").setup({
	adapters = {
		require("neotest-golang")({}),
		require("neotest-vstest")({}),
		require("neotest-minitest")({}),
		require("neotest-vitest")({
			filter_dir = filter_dir,
			vitestConfigFile = function(path)
				return find_config(path, {
					"vitest.config.ts", "vitest.config.js",
					"vitest.config.mts", "vitest.config.mjs",
					"vitest.config.cts", "vitest.config.cjs",
					"vite.config.ts",   "vite.config.js",
					"vite.config.mts",  "vite.config.mjs",
					"vite.config.cts",  "vite.config.cjs",
				})
			end,
		}),
		require("neotest-jest")({
			jestCommand = "npm test --",
			env = { CI = true },
			filter_dir = filter_dir,
			jestConfigFile = function(path)
				return find_config(path, {
					"jest.config.ts",  "jest.config.js",
					"jest.config.mjs", "jest.config.cjs",
					"jest.config.json",
				})
			end,
		}),
	},
})
