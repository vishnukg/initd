-- Bootstrap lazy.nvim if not already installed
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	local result = vim.fn.system({
		"git", "clone", "--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", lazypath,
	})
	if vim.v.shell_error ~= 0 then
		error("Failed to install lazy.nvim:\n" .. result)
	end
end
vim.opt.rtp:prepend(lazypath)

return require("lazy").setup({

	-- ── Colorscheme ───────────────────────────────────────────────────────────
	{
		"Mofiqul/vscode.nvim",
		lazy = false,
		priority = 1000, -- load before everything else so colors are set first
		config = function() require("user.colorscheme") end,
	},

	-- ── UI Enhancements ───────────────────────────────────────────────────────
	{
		"nvim-tree/nvim-tree.lua",
		version = "*",
		cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeOpen" },
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function() require("user.nvimtree") end,
	},
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		event = "UIEnter",
		config = function() require("user.lualine") end,
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		opts = { indent = { char = "╎" } },
		event = { "BufReadPre", "BufNewFile" },
	},

	-- ── Fuzzy Finder ──────────────────────────────────────────────────────────
	{
		"ibhagwan/fzf-lua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		cmd = "FzfLua",
		config = function() require("user.fzf") end,
	},

	-- ── Treesitter ────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		-- The main-branch rewrite does not support lazy-loading. Loading it at
		-- startup also guarantees the FileType attach autocmd is always present.
		lazy = false,
		cmd = { "TSUpdate", "TSInstall", "TSUninstall", "TSModuleInfo" },
		build = ":TSUpdate",
		config = function()
			require("user.treesitter")
		end,
	},

	-- ── Autopairs ─────────────────────────────────────────────────────────────
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		config = function() require("user.autopairs") end,
	},

	-- ── Terminal ──────────────────────────────────────────────────────────────
	{
		"akinsho/toggleterm.nvim",
		keys = {
			{ "<leader>tv", desc = "Toggle vertical terminal" },
			{ "<leader>th", desc = "Toggle horizontal terminal" },
			{ "<leader>gt", desc = "Toggle lazygit" },
		},
		config = function() require("user.toggleterm") end,
	},

	-- ── Git ───────────────────────────────────────────────────────────────────
	{ "tpope/vim-fugitive", cmd = { "Git", "G" } },
	{
		"lewis6991/gitsigns.nvim",
		event = "BufReadPre",
		config = function() require("user.gitsigns") end,
	},

	-- ── Search and Replace ────────────────────────────────────────────────────
	{
		"MagicDuck/grug-far.nvim",
		event = "VeryLazy",
		config = function() require("grug-far").setup({}) end,
	},

	-- ── Completion ────────────────────────────────────────────────────────────
	-- All cmp sources are listed here as dependencies so lazy.nvim loads them
	-- in the right order. Previously some were also listed as top-level entries
	-- (with lazy=true) which caused duplicate specs — removed.
	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter",
		dependencies = {
			-- Loaded before cmp so confirm_done integration is deterministic.
			"windwp/nvim-autopairs",
			-- Snippet engine (must load before cmp_luasnip)
			{
				"L3MON4D3/LuaSnip",
				dependencies = { "rafamadriz/friendly-snippets" },
			},
			"saadparwaiz1/cmp_luasnip",
			-- Sources
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-nvim-lua",
		},
		config = function() require("user.cmp") end,
	},

	-- ── LSP ecosystem ─────────────────────────────────────────────────────────
	-- LSP servers + lint/format tools are managed by mise (mise/config.toml).
	-- nvim-lspconfig just enables them.
	-- cmp-nvim-lsp is listed here so capabilities are ready before server
	-- configs run (it would otherwise only load on InsertEnter via nvim-cmp).
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			{ "nvimtools/none-ls.nvim", dependencies = "nvimtools/none-ls-extras.nvim" },
			"hrsh7th/cmp-nvim-lsp",
			-- LSP progress UI
			{
				"j-hui/fidget.nvim",
				config = function() require("user.fidget") end,
			},
		},
		config = function() require("user.lsp") end,
	},

	-- ── Testing ───────────────────────────────────────────────────────────────
	{
		"nvim-neotest/neotest",
		-- Global keymaps require("neotest") on first use, which lazy.nvim uses
		-- as the load trigger. Avoid loading every test adapter on each code file.
		lazy = true,
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-neotest/nvim-nio",
			"nvim-treesitter/nvim-treesitter",
			"nvim-neotest/neotest-jest",
			"marilari88/neotest-vitest",
			"fredrikaverpil/neotest-golang",
			"nsidorenco/neotest-vstest",
			"nvim-neotest/neotest-python",
		},
		config = function() require("user.neotest") end,
	},

	-- ── Markdown ──────────────────────────────────────────────────────────────
	{
		"MeanderingProgrammer/render-markdown.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
		ft = { "markdown" },
		opts = { enabled = true },
	},

	-- ── Language-specific ─────────────────────────────────────────────────────
	-- OpenFGA authorization models
	{
		"hedengran/fga.nvim",
		ft = { "fga" },
		opts = { install_treesitter_grammar = true },
	},

	-- Test coverage overlay
	{
		"andythigpen/nvim-coverage",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function() require("user.coverage") end,
		cmd = {
			"Coverage", "CoverageLoad", "CoverageLoadLcov", "CoverageShow",
			"CoverageHide", "CoverageToggle", "CoverageClear", "CoverageSummary",
		},
	},

	-- Go: struct tags, if-err, impl
	{
		"olexsmir/gopher.nvim",
		cmd = {
			"GopherLog", "GoIfErr", "GoCmt", "GoImpl", "GoInstallDeps",
			"GoInstallDepsSync", "GoTagAdd", "GoTagRm", "GoTagClear",
			"GoJson", "GoTestAdd", "GoTestsAll", "GoTestsExp", "GoMod",
			"GoGet", "GoWork", "GoGenerate",
		},
		build = ":GoInstallDepsSync",
		config = function() require("user.gopher") end,
	},

	-- Surround — manipulate surrounding characters (ys, cs, ds)
	{
		"kylechui/nvim-surround",
		version = "*",
		event = "VeryLazy",
		config = function() require("nvim-surround").setup({}) end,
	},

	-- Diagnostics list
	{
		"folke/trouble.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		cmd = "Trouble",
		opts = {},
	},
}, {
	performance = {
		rtp = {
			disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
		},
	},
	-- No plugin in this config requires luarocks (lazy's healthcheck confirms
	-- "no plugins require luarocks"). Disabling it stops lazy from trying to
	-- bootstrap a hererocks/luarocks toolchain — which otherwise shows up as a
	-- spurious ERROR in :checkhealth lazy.
	rocks = { enabled = false },
})
