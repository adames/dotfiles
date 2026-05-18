-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Leader before plugins load
vim.g.mapleader      = " "
vim.g.maplocalleader = " "

-- Annotations below (@cs ...) are parsed by cheatsheet-gen.py into HUD cards.

-- @cs section Vim · Motion
-- @cs family vim
-- @cs sub neovim · cursor & jumps
-- @cs idea Every motion is a noun. Pair it with a verb (c · d · y) to describe an edit.
-- @cs custom keyboard
-- @cs row 0  ^  $          :: line: start / first nonblank / end
-- @cs row gg  G            :: file: top / bottom
-- @cs row {  }             :: paragraph: back / forward
-- @cs row f / F  ·  t / T  :: find / till char in line  ·  uppercase = backwards
-- @cs row %                :: matching ( [ {
-- @cs row /pat   n / N     :: search forward · next / prev match
-- @cs row *  #             :: search word under cursor: fwd / back
-- @cs row ctrl-o  ctrl-i   :: jumplist: back / forward
-- @cs row m⟨a-z⟩  '⟨a-z⟩   :: set mark / jump to mark line
-- @cs end

-- @cs section Vim · Edit
-- @cs family vim
-- @cs sub neovim · change & yank
-- @cs idea Verb + motion = composable change. The . key replays your last verb on the next thing.
-- @cs row i  a   I  A       :: insert: before / after / line-start / line-end
-- @cs row o  O               :: open line: below / above
-- @cs row cc  dd  yy         :: change / delete / yank whole line
-- @cs row ci⟨x⟩  ca⟨x⟩       :: change inside / around  (" ' ( [ { t p)
-- @cs row p  P               :: paste: after / before
-- @cs row u   ctrl-r         :: undo / redo
-- @cs row .                  :: repeat last change
-- @cs row ctrl-a  ctrl-x     :: increment / decrement number
-- @cs row q⟨x⟩ … q     @⟨x⟩  :: record macro to x / replay x
-- @cs row :%s/foo/bar/g      :: replace all in buffer  (add c for confirm)
-- @cs end

local opt = vim.opt
opt.number         = true
opt.relativenumber = true
opt.expandtab      = true
opt.tabstop        = 2
opt.shiftwidth     = 2
opt.smartindent    = true
opt.ignorecase     = true
opt.smartcase      = true
opt.swapfile       = false
opt.undofile       = true
opt.undodir        = vim.fn.stdpath("data") .. "/undo"
opt.termguicolors  = true
opt.signcolumn     = "yes"
opt.updatetime     = 250
opt.splitbelow     = true
opt.splitright     = true
vim.fn.mkdir(vim.fn.stdpath("data") .. "/undo", "p")

require("lazy").setup({

  {
    "catppuccin/nvim", name = "catppuccin", priority = 1000,
    config = function() vim.cmd.colorscheme("catppuccin-mocha") end,
  },

  -- Icons for fzf-lua and oil.nvim. Mocks nvim-web-devicons so plugins
  -- that look for it by name still resolve.
  {
    "echasnovski/mini.icons",
    lazy = false,
    config = function()
      require("mini.icons").setup()
      MiniIcons.mock_nvim_web_devicons()
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false, build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup()
      require("nvim-treesitter").install({
        "python", "typescript", "tsx", "bash", "json", "yaml",
      })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "*",
        callback = function() pcall(vim.treesitter.start) end,
      })
    end,
  },

  -- Simple LSP using system-installed pyright and ruff (brew)
  -- No mason auto-install complexity - just works if tools are in PATH
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")
      
      -- Enable LSP keymaps when attached
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
        callback = function(ev)
          local map = function(k, fn, d) vim.keymap.set("n", k, fn, { buffer = ev.buf, desc = d }) end
          map("gd", vim.lsp.buf.definition, "Go to definition")
          map("gr", vim.lsp.buf.references, "Find references")
          map("K",  vim.lsp.buf.hover,       "Hover documentation")
          map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
          map("<leader>=", vim.lsp.buf.format, "Format buffer")
        end,
      })
      
      -- Pyright for Python type checking
      if vim.fn.executable("pyright-langserver") == 1 then
        lspconfig.pyright.setup({})
      end
      
      -- Ruff for Python linting/formatting
      if vim.fn.executable("ruff-lsp") == 1 then
        lspconfig.ruff_lsp.setup({})
      end
      
      -- Bash
      if vim.fn.executable("bash-language-server") == 1 then
        lspconfig.bashls.setup({})
      end
    end,
  },

  {
    "ibhagwan/fzf-lua",
    config = function()
      require("fzf-lua").setup({})
      local map = vim.keymap.set
      map("n", "<leader>ff", "<cmd>FzfLua files<cr>",     { desc = "Files" })
      map("n", "<leader>fg", "<cmd>FzfLua live_grep<cr>", { desc = "Live grep" })
      map("n", "<leader>fb", "<cmd>FzfLua buffers<cr>",   { desc = "Buffers" })
      map("n", "<leader>gs", "<cmd>FzfLua git_status<cr>", { desc = "Git status" })
    end,
  },

  -- Simple marks for file navigation (replaces harpoon)
  -- Use m{a-z} to set mark, '{a-z} to jump to mark
  -- Much simpler, no plugin needed

  -- File explorer as a buffer. `-` opens the parent dir; edit names like text.
  {
    "stevearc/oil.nvim",
    config = function()
      require("oil").setup({
        view_options = { show_hidden = true },
        skip_confirm_for_simple_edits = true,
      })
      vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "Open parent dir" })
    end,
  },

  -- Terminal-based debugging and testing (simpler for learning)
  -- Debug: use `python -m pdb script.py` or add `breakpoint()` in code
  -- Tests: use `pytest -xvs test_file.py` in a tmux pane
  -- No heavy DAP/neotest dependencies to manage
}, {
  rocks = { enabled = false },
})
