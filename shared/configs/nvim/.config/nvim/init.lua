-- Native Lua module bytecode cache (Neovim 0.9+). Must run before any other
-- require() so module loads hit the on-disk bytecode cache instead of re-parsing
-- source. lazy.nvim already caches plugin modules, so the median win is small —
-- the real benefit is faster loads of our own user.* modules and a tighter,
-- more consistent startup tail (worst-case cold start drops noticeably).
vim.loader.enable()

require "bootstrap"
require "user"

