-- Cross-cutting keymaps. Leader repeated here as a safety net (must be set before plugins in init.lua).
vim.g.mapleader      = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

map("n", "<leader>bn", "<cmd>bnext<cr>",   { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })
map("n", "<leader>bo", function()
  -- Close every buffer except the current one. `%bd | e# | bd#` is the
  -- idiomatic dance: wipe all, re-edit alt buffer, kill the leftover
  -- [No Name] — but %bdelete throws E89 on any modified buffer, and `e#`
  -- errors if there's no alternate file (single-buffer session). Guard both.
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].modified then
      vim.notify("Buffer has unsaved changes, not closed: " .. vim.api.nvim_buf_get_name(buf),
        vim.log.levels.WARN)
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted and not vim.bo[buf].modified then
      pcall(vim.api.nvim_buf_delete, buf, {})
    end
  end
end, { desc = "Close others" })

-- Open the file under cursor (oil) or current buffer in a new tmux pane to the right.
-- Workflow: oil explorer left, file opens right, tmux hjkl to navigate between them.
map("n", "<leader>tv", function()
  local path
  local ok, oil = pcall(require, "oil")
  if ok and vim.bo.filetype == "oil" then
    local entry = oil.get_cursor_entry()
    local dir   = oil.get_current_dir()
    if entry and dir then path = dir .. entry.name end
  end
  path = path or vim.fn.expand("%:p")
  if path ~= "" then
    vim.fn.system({"tmux", "split-window", "-h", "nvim " .. vim.fn.shellescape(path)})
  end
end, { desc = "Open in tmux pane right" })
