-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- Ensure local repo modules load cleanly when launched via `nvim -u init.lua`
local config_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = config_dir .. "/?.lua;" .. package.path

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

-- Load modular configurations
require("pylsp_config").setup()
require("git_plugin").setup({ enabled = false }) -- starts disabled
require("tiny_debugger").setup()
