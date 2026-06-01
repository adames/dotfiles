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

-- Annotations below are scraped by lib/cheatsheet-gen.py into the
-- HUD's neovim lens. Keep each section next to the bindings it
-- documents. sigil's committed cheatsheet.json wins on conflicts;
-- annotations here surface content for ids sigil doesn't already track.

-- @cs section Neovim · Files & Buffers
-- @cs id neovim-files-buffers
-- @cs family nvim
-- @cs sub fzf-lua · oil · :b* · native marks
-- @cs idea oil explores; ⟨leader⟩tv sends to a tmux pane right; tmux hjkl jumps between them. fzf for broad hops; marks for pins.
-- @cs row -                  :: open parent dir  (oil — edit names like text)
-- @cs row ⟨leader⟩ tv        :: open file in new tmux pane right  (oil: cursor entry; else: current file)
-- @cs row ⟨leader⟩ ff        :: fzf files
-- @cs row ⟨leader⟩ fb        :: fzf buffers
-- @cs row ⟨leader⟩ bn / bp   :: buffer: next / prev
-- @cs row ⟨leader⟩ bd        :: buffer: delete current
-- @cs row ⟨leader⟩ bo        :: buffer: close others
-- @cs row m⟨a-z⟩  '⟨a-z⟩     :: set mark / jump to mark line  (native, replaces harpoon)
-- @cs end

-- @cs section Neovim · LSP & Search
-- @cs id neovim-lsp-search
-- @cs family nvim
-- @cs sub leader = space · pyright + ruff for *.py
-- @cs idea Leader is your nvim command palette. LSP for code, fzf for everything else.
-- @cs row gd   gr           :: go to definition / references
-- @cs row K                 :: hover docs
-- @cs row ⟨leader⟩ rn       :: rename symbol
-- @cs row ⟨leader⟩ =        :: format buffer  (auto-runs ruff on :w for *.py)
-- @cs row ⟨leader⟩ fg       :: fzf live grep
-- @cs row ⟨leader⟩ gs       :: fzf git status
-- @cs row ctrl-w  v / s     :: split right / below
-- @cs row ctrl-w  h j k l   :: navigate splits
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
        vim.lsp.config("pyright", {})
        vim.lsp.enable("pyright")
      end

      -- Ruff for Python linting/formatting
      if vim.fn.executable("ruff") == 1 then
        vim.lsp.config("ruff", {})
        vim.lsp.enable("ruff")
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

  {
    "kawre/leetcode.nvim",
    build = ":TSUpdate html",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "MunifTanjim/nui.nvim",
      "ibhagwan/fzf-lua",
      "echasnovski/mini.icons",
      "nvim-lua/plenary.nvim",
    },
    opts = {
      lang = "python3",
    },
  },
}, {
  rocks = { enabled = false },
})
