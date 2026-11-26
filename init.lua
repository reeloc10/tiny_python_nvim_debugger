-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- Ensure Lua can find modules relative to this init.lua location on first run
local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = repo_root .. "/?.lua;" .. package.path

-- Load common first to establish paths
local common = require("common")

-- Set global leader key first
vim.g.mapleader = " "
vim.o.timeoutlen = 2000

-- Visuals & Stream Readability (Zero impact on buffer line numbers)
vim.opt.number = true
-- vim.opt.relativenumber = true
vim.opt.cursorline = true
-- safety margin above and below your cursor when scrolling up or down
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"

-- Python Indentation (PEP 8)
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Search & Splits
-- makes search patterns (/ or ?) case-insensitive
-- vim.opt.ignorecase = true
-- Overrides ignorecase if your search query contains an uppercase letter.
-- vim.opt.smartcase = true
-- :vsplit open on the right side of current window
vim.opt.splitright = true
-- :split open below current window rather than above it
vim.opt.splitbelow = true

-- Disable legacy remote plugin providers
vim.g.loaded_python3_provider = 0
-- vim.g.loaded_node_provider = 0
-- vim.g.loaded_perl_provider = 0
-- vim.g.loaded_ruby_provider = 0

-- Visual whitespace & tab warnings
vim.opt.list = true
vim.opt.listchars = {
  tab = '→ ',   -- Visual symbol for literal tabs
  trail = '·',  -- Visual symbol for trailing spaces at end of lines
  nbsp = '␣',   -- Non-breaking spaces
}

-- Give literal tabs a distinct high-visibility highlight (e.g., Red)
vim.api.nvim_set_hl(0, 'Whitespace', { fg = '#ff5555', ctermfg = 'Red' })

-- Remember and restore last cursor position on file open
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    -- Skip special buffer types (e.g., terminal, quickfix, nofile)
    if vim.bo.buftype ~= "" then return end

    -- Skip specific filetypes if needed (e.g., git commits want a fresh start)
    if vim.bo.filetype == "gitcommit" then return end

    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Bottom horizontal terminal split (<leader>ft)
vim.keymap.set('n', '<leader>ft', function()
  vim.cmd('botright 12split | term')
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.opt_local.signcolumn = 'no'
  vim.opt_local.list = false
  vim.cmd('startinsert')
end, { desc = 'Open bottom horizontal terminal split' })

-- Ensure Python indentation uses standard rules, disables C-style tracking,
-- and clears the expression-based indent script that causes runaway indentation.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function(args)
    vim.bo.shiftwidth = 4
    vim.bo.tabstop = 4
    vim.bo.expandtab = true
    vim.bo.cindent = false
    -- Enable smartindent to handle block nesting after colons (:)
    -- while keeping indentexpr disabled to prevent runaway continuation bugs.
    vim.bo.smartindent = true
    vim.bo.autoindent = true
    vim.bo[args.buf].indentexpr = ""
  end,
})

-- Note: Registering multiple FileType autocmds across different modules
-- is completely fine in Neovim. It runs them sequentially and helps
-- maintain strict separation of concerns.

-- Configure netrw behavior for a clean sidebar experience
vim.g.netrw_banner = 0       -- Hide banner text at the top
vim.g.netrw_liststyle = 3    -- Tree view
vim.g.netrw_browse_split = 4 -- Open files in previous window (the main editing split)
vim.g.netrw_altwin = 1       -- Allow toggling back and forth cleanly
vim.g.netrw_winsize = 25     -- Width percentage (25%)

-- 1. Toggle from Neovim's working directory (pwd)
vim.api.nvim_create_user_command('ExplorerToggle', function()
  vim.cmd('Lexplore')
end, { desc = 'Toggle file explorer sidebar from CWD' })

-- 2. Toggle anchored to the active buffer's directory
vim.api.nvim_create_user_command('ExplorerToggleBuffer', function()
  vim.cmd('Lexplore ' .. vim.fn.fnameescape(vim.fn.expand('%:p:h')))
end, { desc = 'Toggle file explorer sidebar anchored to current buffer directory' })

-- Load modular configurations
require("treesitter").setup({ config_dir = config_dir })

local capabilities = vim.lsp.protocol.make_client_capabilities()
-- Tell the server we support snippets in completion items
capabilities.textDocument.completion.completionItem.snippetSupport = true

-- Pass this into your pylsp setup:
require("pylsp_config").setup({
  capabilities = capabilities,
})

require("autopairing").setup()
require("git_plugin").setup({ enabled = false }) -- starts disabled

require('git_status')
require('git_blame').setup()

-- --- Your existing configuration ---
-- (Ensure any existing statusline config is overwritten)
-- Use a single assignment instead of concatenation

require("tiny_debugger").setup()
require('fastgrep').setup()
require('markdown').setup({ auto_enable = false })
require('lua_dev').setup()

-- Quick diagnostic float with feedback if line is clean (<leader>d)
vim.keymap.set('n', '<leader>d', function()
  local win = vim.diagnostic.open_float()
  if not win then
    print("No diagnostics on current line")
  end
end, { desc = 'Show line diagnostics' })

-- Populate location list with all buffer diagnostics (<leader>q)
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'List all buffer diagnostics' })
