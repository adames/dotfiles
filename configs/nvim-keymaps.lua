-- Loaded automatically from ~/.config/nvim/after/plugin/keymaps.lua
-- after lazy.nvim plugins load and after <leader> is set in init.lua.

local map = vim.keymap.set

-- Window navigation
map("n", "<Leader>h", "<C-w>h", { desc = "Window left"  })
map("n", "<Leader>j", "<C-w>j", { desc = "Window down"  })
map("n", "<Leader>k", "<C-w>k", { desc = "Window up"    })
map("n", "<Leader>l", "<C-w>l", { desc = "Window right" })

-- File explorer (netrw fallback; Telescope/oil etc. can override)
map("n", "<Leader>e", "<cmd>Explore<CR>", { desc = "File explorer" })

-- Git: prefer fugitive's :Git when available, else gitsigns status,
-- else fall back to a shell prompt.
map("n", "<Leader>g", function()
  if vim.fn.exists(":Git") == 2 then
    vim.cmd("Git")
  elseif pcall(require, "gitsigns") then
    vim.cmd("Gitsigns toggle_signs")
  else
    vim.cmd("!git status")
  end
end, { desc = "Git status" })

-- Run tests: prefer vim-test's :TestNearest if installed, else neotest.
map("n", "<Leader>t", function()
  if vim.fn.exists(":TestNearest") == 2 then
    vim.cmd("TestNearest")
  elseif pcall(require, "neotest") then
    require("neotest").run.run()
  else
    vim.notify("No test runner installed (vim-test or neotest)", vim.log.levels.WARN)
  end
end, { desc = "Run nearest test" })
