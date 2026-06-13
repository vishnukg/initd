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
		event = "BufReadPre",
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
		event = "BufReadPre",
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
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-neotest/nvim-nio",
			"nvim-treesitter/nvim-treesitter",
			"nvim-neotest/neotest-jest",
			"marilari88/neotest-vitest",
			"fredrikaverpil/neotest-golang",
			"nsidorenco/neotest-vstest",
		},
		config = function() require("user.neotest") end,
		ft = { "go", "javascript", "typescript", "typescriptreact", "javascriptreact", "cs" },
	},

	-- ── AI / Copilot ──────────────────────────────────────────────────────────
	-- vim.g.copilot_filetypes is set in bootstrap.lua (must be before this loads).
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		dependencies = {
			{ "github/copilot.vim" },
			{ "nvim-lua/plenary.nvim", branch = "master" },
		},
		build = "make tiktoken",
		opts = {},
		cmd = "CopilotChat",
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

	-- Test coverage overlay (gcv = load & show, then <leader>cvs for summary)
	-- Workflow: run tests with neotest → gcv to overlay coverage gutters
	{
		"andythigpen/nvim-coverage",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			require("coverage").setup({
				commands = true,
				auto_reload = true,
				highlights = {
					covered   = { bg = "#004400" },
					uncovered = { bg = "#440000" },
				},
				signs = {
					covered   = { hl = "CoverageCovered",   text = "▎" },
					uncovered = { hl = "CoverageUncovered", text = "▎" },
				},
				lang = {
					-- go test -coverprofile=coverage.out ./...
					go         = { coverage_file = "coverage.out" },
					-- npm run test:coverage (vitest/jest with lcov reporter)
					typescript = { coverage_file = "coverage/lcov.info" },
					javascript = { coverage_file = "coverage/lcov.info" },
					-- coverage run -m pytest && coverage json
					python     = { coverage_file = ".coverage" },
					-- dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=lcov
					cs         = { coverage_file = "TestResults/lcov.info" },
				},
			})
		end,
		ft = { "go", "javascript", "typescript", "python", "cs" },
	},

	-- Go: struct tags, if-err, impl — NOT an LSP tool, no interference with gopls.
	-- Run :GoInstallDeps once after install.
	{
		"olexsmir/gopher.nvim",
		ft = "go",
		config = function(_, opts)
			require("gopher").setup(opts)
			-- Auto-install binaries on first Go file open (only if missing)
			if vim.fn.executable("gomodifytags") == 0 then
				vim.api.nvim_create_autocmd("FileType", {
					pattern = "go",
					once = true,
					callback = function() pcall(vim.cmd, "GoInstallDeps") end,
				})
			end
		end,
		opts = {
			commands = { gotests = "gotests" },
			gotag = {
				transform   = "camelcase",
				default_tag = "json",
				option      = nil, -- omitempty should be added per field, not by default
			},
		},
	},

	-- .NET
	{
		"GustavEikaas/easy-dotnet.nvim",
		dependencies = { "nvim-lua/plenary.nvim", "ibhagwan/fzf-lua" },
		cmd = "Dotnet",
		event = {
			"BufReadPost *.csproj",  "BufReadPost *.fsproj",  "BufReadPost *.vbproj",
			"BufReadPost *.sln",     "BufReadPost *.slnx",
			"BufNewFile *.csproj",   "BufNewFile *.fsproj",   "BufNewFile *.vbproj",
			"BufNewFile *.sln",      "BufNewFile *.slnx",
		},
		config = function()
			require("easy-dotnet").setup({
				picker = "fzf",
				-- Roslyn LSP disabled: csharp_ls handles all features consistently
				-- with the rest of the LSP stack (gopls, pyright, etc).
				lsp = { enabled = false },
			})
		end,
		ft = { "cs", "fs", "vb" },
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
