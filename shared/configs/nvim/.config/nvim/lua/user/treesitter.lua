-- Configure nvim-treesitter (main branch rewrite, Neovim 0.12+)
local treesitter = require("nvim-treesitter")
local available_parsers = treesitter.get_available()

treesitter.setup({
	install_dir = vim.fn.stdpath("data") .. "/site",
})

-- Injection parsers have no filetype of their own so the FileType autocmd below
-- will never trigger for them — pre-install so they are ready from the first startup.
treesitter.install({ "markdown_inline", "luadoc", "jsdoc", "regex" })

-- Filetypes where treesitter indentation is known to be broken
-- (cs: treesitter indentexpr breaks C# indentation)
local indent_disabled = { yaml = true, html = true, cs = true }

---Attach treesitter features (highlighting, folding, indentation) to a buffer.
---If the parser .so is missing (stale queries), force-reinstall once.
---@param buf integer
---@param language string
---@param retried boolean?
local function try_attach(buf, language, retried)
	-- Parser installation is asynchronous; the originating buffer may have
	-- disappeared before its callback runs.
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end

	if not vim.treesitter.language.add(language) then
		-- Prefer any parser already on runtimepath (including Neovim's bundled
		-- parsers). Only download when language.add confirms none is available.
		if not retried and vim.tbl_contains(available_parsers, language) then
			treesitter.install(language, { force = true }):await(function()
				try_attach(buf, language, true)
			end)
		end
		return
	end

	vim.treesitter.start(buf, language)

	-- Apply to the windows actually showing this buffer — after an async parser
	-- install the current window may no longer be the one that triggered attach.
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.wo[win][0].foldexpr   = "v:lua.vim.treesitter.foldexpr()"
		vim.wo[win][0].foldmethod = "expr"
		vim.wo[win][0].foldlevel  = 99
	end

	if not indent_disabled[vim.bo[buf].filetype] then
		vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("TreesitterAttach", { clear = true }),
	callback = function(args)
		local buf, filetype = args.buf, args.match

		local language = vim.treesitter.language.get_lang(filetype)
		if not language then return end

		try_attach(buf, language)
	end,
})
