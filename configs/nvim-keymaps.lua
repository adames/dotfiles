-- after/plugin slot for cross-cutting custom keymaps.
-- Leader is also set in init.lua (must be before plugins load); this is a no-op safety net.
vim.g.mapleader      = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

-- <leader>b* — buffer ops. Symmetric with the window/space layer:
--   Caps + hjkl moves between OS windows; <leader>b* moves between nvim buffers.
map("n", "<leader>bn", "<cmd>bnext<cr>",   { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })
map("n", "<leader>bo", function()
  -- Close every buffer except the current one. `%bd | e# | bd#` is the
  -- idiomatic dance: wipe all, re-edit alt buffer, kill the leftover [No Name].
  vim.cmd("%bdelete | edit # | bdelete #")
end, { desc = "Close others" })
