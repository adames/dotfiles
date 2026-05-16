-- Cross-cutting keymaps. Leader repeated here as a safety net (must be set before plugins in init.lua).
vim.g.mapleader      = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

map("n", "<leader>bn", "<cmd>bnext<cr>",   { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })
map("n", "<leader>bo", function()
  -- Close every buffer except the current one. `%bd | e# | bd#` is the
  -- idiomatic dance: wipe all, re-edit alt buffer, kill the leftover [No Name].
  vim.cmd("%bdelete | edit # | bdelete #")
end, { desc = "Close others" })
