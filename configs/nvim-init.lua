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

-- Leader must be set before lazy loads plugins
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Options
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

-- Plugins
require("lazy").setup({

  -- Colorscheme
  {
    "catppuccin/nvim",
    name     = "catppuccin",
    priority = 1000,
    config   = function()
      vim.cmd.colorscheme("catppuccin-mocha")
    end,
  },

  -- Treesitter (rewritten API; lazy = false required)
  -- Bundled in Neovim 0.12: lua, markdown, c, vim, vimdoc
  -- Installed by this plugin: python, typescript, tsx, bash, json, yaml
  {
    "nvim-treesitter/nvim-treesitter",
    lazy  = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup()

      -- Install missing parsers (async; no-op if already installed)
      require("nvim-treesitter").install({
        "python", "typescript", "tsx", "bash", "json", "yaml",
      })

      -- Enable highlighting for all filetypes that have a parser
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "*",
        callback = function()
          pcall(vim.treesitter.start)
        end,
      })
    end,
  },

  -- LSP: mason installs servers, mason-lspconfig auto-enables them,
  -- nvim-lspconfig provides default server configs for vim.lsp to use.
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      { "williamboman/mason.nvim",           opts = {} },
      {
        "williamboman/mason-lspconfig.nvim",
        opts = {
          ensure_installed = { "pyright", "ruff", "ts_ls" },
        },
      },
      -- DAP / formatters / linters that aren't LSPs still come from Mason
      {
        "WhoIsSethDaniel/mason-tool-installer.nvim",
        opts = {
          ensure_installed = { "debugpy" },
        },
      },
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- Apply capabilities to all servers before they start
      vim.lsp.config("*", {
        capabilities = require("cmp_nvim_lsp").default_capabilities(),
      })

      -- Set keymaps whenever any LSP attaches
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
        callback = function(ev)
          local map = function(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = ev.buf, desc = desc })
          end
          map("gd",         vim.lsp.buf.definition,   "Go to definition")
          map("gr",         vim.lsp.buf.references,   "References")
          map("K",          vim.lsp.buf.hover,         "Hover docs")
          map("<leader>ca", vim.lsp.buf.code_action,   "Code action")
          map("<leader>rn", vim.lsp.buf.rename,        "Rename symbol")
          map("<leader>=",  function() vim.lsp.buf.format({ async = false }) end, "Format buffer")
        end,
      })

      -- Format Python on save with Ruff (pyright doesn't format)
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.py",
        callback = function()
          vim.lsp.buf.format({
            filter = function(client) return client.name == "ruff" end,
            timeout_ms = 1000,
          })
        end,
      })
    end,
  },

  -- Completion
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"]     = cmp.mapping.abort(),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
        }),
      })
    end,
  },

  -- Fuzzy finder
  {
    "ibhagwan/fzf-lua",
    config = function()
      require("fzf-lua").setup({})
      local map = vim.keymap.set
      map("n", "<leader>ff", "<cmd>FzfLua files<cr>",     { desc = "Find files" })
      map("n", "<leader>fg", "<cmd>FzfLua live_grep<cr>", { desc = "Live grep" })
      map("n", "<leader>fb", "<cmd>FzfLua buffers<cr>",   { desc = "Find buffers" })
    end,
  },

  -- Git gutter
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup()
    end,
  },

  -- which-key: pops up keymap menu after <leader> — accelerates muscle memory
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 300,
      spec = {
        { "<leader>f", group = "find" },
        { "<leader>l", group = "lsp"  },  -- reserved for future
        { "<leader>d", group = "debug" },
        { "<leader>t", group = "test" },
        { "<leader>g", group = "git"  },  -- reserved for future
        { "<leader>c", group = "code" },
      },
    },
  },

  -- Python debugging: nvim-dap UI + dap-python (uses debugpy from mason)
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "mfussenegger/nvim-dap-python",
    },
    config = function()
      local dap   = require("dap")
      local dapui = require("dapui")
      dapui.setup()

      -- debugpy is installed by mason-tool-installer above; dap-python finds
      -- it via mason's path. Falls back to system python3 if not present.
      local mason_python = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
      require("dap-python").setup(vim.fn.executable(mason_python) == 1 and mason_python or "python3")

      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"]     = function() dapui.close() end

      local map = vim.keymap.set
      map("n", "<leader>db", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
      map("n", "<leader>dc", dap.continue,           { desc = "Continue" })
      map("n", "<leader>do", dap.step_over,          { desc = "Step over" })
      map("n", "<leader>di", dap.step_into,          { desc = "Step into" })
      map("n", "<leader>du", dap.step_out,           { desc = "Step out" })
      map("n", "<leader>dr", dap.repl.open,          { desc = "REPL" })
      map("n", "<leader>dx", dap.terminate,          { desc = "Terminate" })
      map("n", "<leader>dU", dapui.toggle,           { desc = "Toggle UI" })
    end,
  },

  -- Test runner: neotest + neotest-python (uses pytest, integrates with dap)
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
          require("neotest-python")({
            dap     = { justMyCode = false },
            runner  = "pytest",
          }),
        },
      })
      local map = vim.keymap.set
      map("n", "<leader>tn", function() neotest.run.run() end,                     { desc = "Test nearest" })
      map("n", "<leader>tf", function() neotest.run.run(vim.fn.expand("%")) end,    { desc = "Test file" })
      map("n", "<leader>tl", function() neotest.run.run_last() end,                 { desc = "Test last" })
      map("n", "<leader>ts", function() neotest.summary.toggle() end,               { desc = "Test summary" })
      map("n", "<leader>to", function() neotest.output.open({ enter = true }) end,  { desc = "Test output" })
      map("n", "<leader>td", function() neotest.run.run({ strategy = "dap" }) end,  { desc = "Test debug" })
    end,
  },
})
