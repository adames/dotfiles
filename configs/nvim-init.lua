-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
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

-- Annotations below are scraped by rune (configs/workspace/rune.toml) into the
-- HUD's neovim lens. Keep each section next to the bindings it documents.
-- These @cs blocks are the sole source for the vim/neovim lenses — rune
-- builds the HUD from annotations only (no committed cheatsheet.json merge).

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

-- Vim motion/edit reference. Not bindings — plain vim literacy, kept here
-- because the cheatsheet HUD's vim lens is annotation-driven and needs a home.
-- @cs section Vim · Motion
-- @cs id vim-motion
-- @cs family vim
-- @cs sub neovim · cursor & jumps
-- @cs idea Every motion is a noun. Pair it with a verb (c · d · y) to describe an edit.
-- @cs row 0  ^  $              :: line: start / first nonblank / end
-- @cs row gg  G                :: file: top / bottom
-- @cs row {  }                 :: paragraph: back / forward
-- @cs row f / F  ·  t / T      :: find / till char in line  ·  uppercase = backwards
-- @cs row %                    :: matching ( [ {
-- @cs row /pat → n / N         :: search forward · next / prev match
-- @cs row *  #                 :: search word under cursor: fwd / back
-- @cs row ctrl + o / ctrl + i  :: jumplist: back / forward
-- @cs row m⟨a-z⟩  '⟨a-z⟩       :: set mark / jump to mark line
-- @cs end

-- @cs section Vim · Edit
-- @cs id vim-edit
-- @cs family vim
-- @cs sub neovim · change & yank
-- @cs idea Verb + motion = composable change. The . key replays your last verb on the next thing.
-- @cs row i  a   I  A          :: insert: before / after / line-start / line-end
-- @cs row o  O                 :: open line: below / above
-- @cs row cc  dd  yy           :: change / delete / yank whole line
-- @cs row ci⟨x⟩  ca⟨x⟩         :: change inside / around  (" ' ( [ { t p)
-- @cs row p  P                 :: paste: after / before
-- @cs row u / ctrl + r         :: undo / redo
-- @cs row .                    :: repeat last change
-- @cs row ctrl + a / ctrl + x  :: increment / decrement number
-- @cs row q⟨x⟩ … q → @⟨x⟩      :: record macro to x / replay x
-- @cs row :%s/foo/bar/g        :: replace all in buffer  (add c for confirm)
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

  -- LSP via system-installed pyright + ruff (brew) — no mason.
  {
    "neovim/nvim-lspconfig",
    config = function()
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

      if vim.fn.executable("pyright-langserver") == 1 then
        vim.lsp.config("pyright", {})
        vim.lsp.enable("pyright")
      end

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

  -- File nav uses native marks (m{a-z} / '{a-z}) — no harpoon plugin.

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

  -- No DAP/neotest: debug with breakpoint()/pdb, test with pytest in a tmux pane.
}, {
  rocks = { enabled = false },
})
