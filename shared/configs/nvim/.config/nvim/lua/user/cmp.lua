local cmp     = require("cmp")
local luasnip = require("luasnip")

require("luasnip.loaders.from_vscode").lazy_load()
require("luasnip.loaders.from_vscode").lazy_load({ paths = { vim.fn.stdpath("config") .. "/snippets" } })

local kind_icons = {
	Text = "󰊄", Method = "", Function = "󰡱", Constructor = "",
	Field = "", Variable = "", Class = "", Interface = "",
	Module = "", Property = "", Unit = "", Value = "",
	Enum = "", Keyword = "", Snippet = "", Color = "",
	File = "", Reference = "", Folder = "", EnumMember = "",
	Constant = "", Struct = "", Event = "", Operator = "",
	TypeParameter = "",
}

local ELLIPSIS_CHAR  = "…"
local MAX_LABEL_WIDTH = 15
local MIN_LABEL_WIDTH = 15

cmp.setup({
	performance = {
		debounce = 60,
		throttle = 30,
		fetching_timeout = 200,
	},
	snippet = {
		expand = function(args)
			luasnip.lsp_expand(args.body)
		end,
	},
	mapping = {
		["<C-p>"]     = cmp.mapping.select_prev_item(),
		["<C-n>"]     = cmp.mapping.select_next_item(),
		["<C-b>"]     = cmp.mapping.scroll_docs(-4),
		["<C-f>"]     = cmp.mapping.scroll_docs(4),
		["<C-Space>"] = cmp.mapping.complete(),
		["<C-y>"]     = cmp.config.disable,
		["<C-e>"]     = cmp.mapping({ i = cmp.mapping.abort(), c = cmp.mapping.close() }),
		["<CR>"]      = cmp.mapping.confirm({ select = true, behavior = cmp.ConfirmBehavior.Replace }),
		["<Tab>"] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_next_item()
			elseif luasnip.expandable() then
				luasnip.expand()
			elseif luasnip.expand_or_jumpable() then
				luasnip.expand_or_jump()
			else
				fallback()
			end
		end, { "i", "s" }),
		["<S-Tab>"] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_prev_item()
			elseif luasnip.jumpable(-1) then
				luasnip.jump(-1)
			else
				fallback()
			end
		end, { "i", "s" }),
	},
	formatting = {
		fields = { "abbr", "kind", "menu" },
		format = function(entry, vim_item)
			local label = vim_item.abbr
			local truncated = vim.fn.strcharpart(label, 0, MAX_LABEL_WIDTH)
			if truncated ~= label then
				vim_item.abbr = truncated .. ELLIPSIS_CHAR
			elseif string.len(label) < MIN_LABEL_WIDTH then
				vim_item.abbr = label .. string.rep(" ", MIN_LABEL_WIDTH - string.len(label))
			end
			vim_item.kind = string.format("%s %s", kind_icons[vim_item.kind], vim_item.kind)
			vim_item.menu = ({
				nvim_lsp = "[LSP]",
				nvim_lua = "[NVIM_LUA]",
				luasnip  = "[Snippet]",
				buffer   = "[Buffer]",
				path     = "[Path]",
			})[entry.source.name]
			return vim_item
		end,
	},
	sources = {
		{ name = "nvim_lsp" },
		{ name = "nvim_lua" },
		{ name = "luasnip" },
		{ name = "buffer" },
		{ name = "path" },
	},
	window = {
		documentation = {
			border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
		},
	},
	experimental = {
		ghost_text = false,
	},
})

-- nvim-autopairs is an explicit cmp dependency, so this hook cannot be lost to
-- an InsertEnter load-order race.
cmp.event:on(
	"confirm_done",
	require("nvim-autopairs.completion.cmp").on_confirm_done({ map_char = { tex = "" } })
)
