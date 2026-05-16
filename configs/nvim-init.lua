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

-- @cs annotations: parsed by cheatsheet-gen.py into HUD cards.

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

  -- mason installs LSP servers; mason-tool-installer handles non-LSP tools (debugpy).
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      { "williamboman/mason.nvim",          opts = {} },
      { "williamboman/mason-lspconfig.nvim", opts = { ensure_installed = { "pyright", "ruff", "ts_ls" } } },
      { "WhoIsSethDaniel/mason-tool-installer.nvim", opts = { ensure_installed = { "debugpy" } } },
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      vim.lsp.config("*", { capabilities = require("cmp_nvim_lsp").default_capabilities() })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
        callback = function(ev)
          local map = function(k, fn, d) vim.keymap.set("n", k, fn, { buffer = ev.buf, desc = d }) end
          map("gd",         vim.lsp.buf.definition,  "Definition")
          map("gr",         vim.lsp.buf.references,  "References")
          map("K",          vim.lsp.buf.hover,        "Hover")
          map("<leader>ca", vim.lsp.buf.code_action,  "Code action")
          map("<leader>rn", vim.lsp.buf.rename,       "Rename")
          map("<leader>=",  function() vim.lsp.buf.format({ async = false }) end, "Format")
        end,
      })

      -- Ruff handles Python format-on-save (pyright doesn't format).
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.py",
        callback = function()
          vim.lsp.buf.format({
            filter = function(c) return c.name == "ruff" end,
            timeout_ms = 1000,
          })
        end,
      })
    end,
  },

  {
    "hrsh7th/nvim-cmp",
    dependencies = { "hrsh7th/cmp-nvim-lsp", "L3MON4D3/LuaSnip", "saadparwaiz1/cmp_luasnip" },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")
      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"]     = cmp.mapping.abort(),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fallback() end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fallback() end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({ { name = "nvim_lsp" }, { name = "luasnip" } }),
      })
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
    end,
  },

  {
    "lewis6991/gitsigns.nvim",
    config = function()
      local gs = require("gitsigns")
      gs.setup({
        on_attach = function(bufnr)
          local map = function(k, fn, d) vim.keymap.set("n", k, fn, { buffer = bufnr, desc = d }) end
          map("]c", function()
            if vim.wo.diff then vim.cmd("normal! ]c") else gs.nav_hunk("next") end
          end, "Next hunk")
          map("[c", function()
            if vim.wo.diff then vim.cmd("normal! [c") else gs.nav_hunk("prev") end
          end, "Prev hunk")
          map("<leader>gh", gs.stage_hunk,                                "Stage hunk")
          map("<leader>gp", gs.preview_hunk,                              "Preview hunk")
          map("<leader>gr", gs.reset_hunk,                                "Reset hunk")
          map("<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")
          map("<leader>gd", gs.diffthis,                                  "Diff this")
        end,
      })
      -- Repo-level status panel (uses fzf-lua already loaded).
      vim.keymap.set("n", "<leader>gs", "<cmd>FzfLua git_status<cr>", { desc = "Git status" })
    end,
  },

  -- Pinned-file jumps. <leader>ha add · <leader>hh menu · <leader>1..4 jump.
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local harpoon = require("harpoon")
      harpoon:setup()
      local map = vim.keymap.set
      map("n", "<leader>ha", function() harpoon:list():add() end,                                     { desc = "Add file" })
      map("n", "<leader>hh", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end,             { desc = "Menu" })
      map("n", "<leader>1",  function() harpoon:list():select(1) end,                                  { desc = "Harpoon 1" })
      map("n", "<leader>2",  function() harpoon:list():select(2) end,                                  { desc = "Harpoon 2" })
      map("n", "<leader>3",  function() harpoon:list():select(3) end,                                  { desc = "Harpoon 3" })
      map("n", "<leader>4",  function() harpoon:list():select(4) end,                                  { desc = "Harpoon 4" })
    end,
  },

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

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay  = 300,
      spec   = {
        { "<leader>f", group = "find"    },
        { "<leader>l", group = "lsp"     },
        { "<leader>d", group = "debug"   },
        { "<leader>t", group = "test"    },
        { "<leader>g", group = "git"     },
        { "<leader>c", group = "code"    },
        { "<leader>b", group = "buffer"  },
        { "<leader>h", group = "harpoon" },
      },
    },
  },

  -- Python debugger. debugpy installed via mason-tool-installer above.
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "mfussenegger/nvim-dap-python",
    },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()

      local mason_py = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
      require("dap-python").setup(vim.fn.executable(mason_py) == 1 and mason_py or "python3")

      dap.listeners.after.event_initialized["dapui"] = function() dapui.open()  end
      dap.listeners.before.event_terminated["dapui"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui"]     = function() dapui.close() end

      local map = vim.keymap.set
      map("n", "<leader>db", dap.toggle_breakpoint, { desc = "Breakpoint" })
      map("n", "<leader>dc", dap.continue,           { desc = "Continue"  })
      map("n", "<leader>do", dap.step_over,          { desc = "Step over" })
      map("n", "<leader>di", dap.step_into,          { desc = "Step into" })
      map("n", "<leader>du", dap.step_out,           { desc = "Step out"  })
      map("n", "<leader>dr", dap.repl.open,          { desc = "REPL"      })
      map("n", "<leader>dx", dap.terminate,          { desc = "Terminate" })
      map("n", "<leader>dU", dapui.toggle,           { desc = "Toggle UI" })
    end,
  },

  -- Test runner over pytest, with DAP integration for <leader>td.
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-neotest/nvim-nio",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-python",
    },
    config = function()
      local neotest = require("neotest")
      neotest.setup({
        adapters = {
          require("neotest-python")({ dap = { justMyCode = false }, runner = "pytest" }),
        },
      })
      local map = vim.keymap.set
      map("n", "<leader>tn", function() neotest.run.run() end,                     { desc = "Nearest"  })
      map("n", "<leader>tf", function() neotest.run.run(vim.fn.expand("%")) end,    { desc = "File"     })
      map("n", "<leader>tl", function() neotest.run.run_last() end,                 { desc = "Last"     })
      map("n", "<leader>ts", function() neotest.summary.toggle() end,               { desc = "Summary"  })
      map("n", "<leader>to", function() neotest.output.open({ enter = true }) end,  { desc = "Output"   })
      map("n", "<leader>td", function() neotest.run.run({ strategy = "dap" }) end,  { desc = "Debug"    })
    end,
  },
})
