-- ~/.config/nvim/after/plugin/keymaps.lua
-- Minimal: Space as leader only.  Everything else is stock Neovim.
-- Add plugin-specific mappings here once you install plugins.
--
-- Space as leader is the overwhelming community default (LazyVim, Kickstart,
-- NvChad, AstroNvim all set it).  Defaults to backslash, which is awkward.
-- Note: if you later add a plugin manager, also set this at the top of
-- init.lua *before* plugins load so they see the right leader during setup.

vim.g.mapleader      = " "
vim.g.maplocalleader = " "
