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

-- @cs blocks are plain keybinding docs now (the rune/cheatsheet HUD that
-- scraped them retired with AeroSpace). Keep each section next to the
-- bindings it documents.

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
-- @cs sub leader = space · pyright (py) · tsc --lsp (js/ts)
-- @cs idea Leader is your nvim command palette. LSP for code, fzf for everything else.
-- @cs row gd   gr           :: go to definition / references
-- @cs row K                 :: hover docs
-- @cs row ⟨leader⟩ rn       :: rename symbol
-- @cs row ⟨leader⟩ =        :: format buffer  (whatever the server offers)
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

-- Clipboard. Yanking has to reach the system clipboard on every machine
-- this config lands on, and each has a different answer.
--
-- WSL: the Linux clipboard isn't Windows', so route through the Windows
-- binaries that WSL exposes on PATH for free — clip.exe to copy,
-- powershell Get-Clipboard to paste. Deliberately not win32yank, which is
-- faster but means downloading a .exe and keeping it current; these two
-- ship with Windows. The \r strip matters: Get-Clipboard returns CRLF,
-- and without it every pasted line ends in a stray ^M.
--
-- Everything else (macOS, a Linux server over SSH): OSC 52, the escape
-- sequence that hands the clipboard to whichever terminal is drawing the
-- session. That's what makes a yank inside tmux on a remote box land in
-- the local clipboard — Ghostty and Windows Terminal both support it.
if vim.fn.has("wsl") == 1 then
  vim.g.clipboard = {
    name = "wsl-interop",
    copy = { ["+"] = "clip.exe", ["*"] = "clip.exe" },
    paste = {
      ["+"] = 'powershell.exe -NoLogo -NoProfile -Command [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
      ["*"] = 'powershell.exe -NoLogo -NoProfile -Command [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
    },
    cache_enabled = 0,
  }
elseif vim.env.SSH_CONNECTION and vim.env.SSH_CONNECTION ~= "" then
  vim.g.clipboard = "osc52"
end

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
        -- javascript: the typescript parser doesn't cover plain .js.
        -- lua/markdown: this repo's own two languages (nvim config, docs).
        "python", "typescript", "javascript", "tsx", "bash", "json", "yaml",
        "lua", "markdown",
      })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "*",
        callback = function() pcall(vim.treesitter.start) end,
      })
    end,
  },

  -- LSP via system-installed servers (brew) — no mason. Each server is
  -- gated on its binary, so a machine missing one degrades to plain
  -- editing instead of erroring on every buffer.
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

      -- JS/TS — the personal-project half of the stack. Treesitter has
      -- parsed typescript/tsx all along; until now there was no server
      -- behind gd/gr/K in a .ts buffer.
      --
      -- Spelled out by hand rather than via lspconfig's `ts_ls`: that one
      -- runs typescript-language-server, which wraps the tsserver.js that
      -- TypeScript 7 stopped shipping. `tsc --lsp` is TS 7's own Go-native
      -- server — one brew formula, no node_modules required, so a loose
      -- .ts file in /tmp gets diagnostics like anything else.
      if vim.fn.executable("tsc") == 1 then
        vim.lsp.config("tsgo", {
          cmd = { "tsc", "--lsp", "--stdio" },
          filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
          root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
        })
        vim.lsp.enable("tsgo")
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
