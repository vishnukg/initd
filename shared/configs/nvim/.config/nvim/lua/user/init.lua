-- Ordinary config, loaded by init.lua AFTER lua/bootstrap.lua.
-- Boundary: bootstrap.lua owns anything that must exist before plugins load
-- (vim.g.* provider/leader/netrw globals); everything else starts here.
-- Order matters: options/keymaps first so plugin specs (which reference
-- <leader> keys) and config= callbacks see the finished editor state.
require("user.options")
require("user.keymaps")
require("user.plugins") -- lazy.nvim setup; each plugin's config= callback fires at the right time
