-- after/plugin slot for cross-cutting custom keymaps.
-- Leader is also set in init.lua (must be before plugins load); this is a no-op safety net.
vim.g.mapleader      = " "
vim.g.maplocalleader = " "

-- @cs section Neovim · Files & Buffers
-- @cs family nvim
-- @cs sub harpoon · oil · :b*
-- @cs idea Harpoon pins four files; oil edits the filesystem as text; buffers are everything else.
-- @cs row -                :: open parent dir (oil — edit names like text)
-- @cs row ⟨leader⟩ ha      :: harpoon: add file
-- @cs row ⟨leader⟩ hh      :: harpoon: toggle quick menu
-- @cs row ⟨leader⟩ 1…4     :: harpoon: jump to pinned slot N
-- @cs row ⟨leader⟩ bn  bp  :: buffer: next / prev
-- @cs row ⟨leader⟩ bd      :: buffer: delete current
-- @cs row ⟨leader⟩ bo      :: buffer: close others
-- @cs end

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
