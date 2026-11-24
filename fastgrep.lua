-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

function M.setup()
  -- 1. Configure native ripgrep integration for :grep / :lgrep
  if vim.fn.executable('rg') == 1 then
    vim.opt.grepprg = 'rg --vimgrep --smart-case'
    vim.opt.grepformat = '%f:%l:%c:%m'
  end

  -- 2. Configure native fuzzy file matching for :find
  vim.opt.path:append('**')
  vim.opt.wildoptions = 'pum,fuzzy'
  vim.opt.wildignore:append({ '*/.git/*', '*/__pycache__/*', '*.pyc' })

  -- Helper to execute grep silently and open quickfix
  local function run_grep(query)
    if not query or query == '' then
      return
    end
    vim.cmd('silent grep! ' .. vim.fn.fnameescape(query))
    vim.cmd('copen')
  end

  -- 3. Fast grep keybindings and Ex commands
  local grep_actions = {
    {
      mode = 'n',
      lhs = '<leader>fg',
      rhs = function(opts)
        local query = (opts and opts.args ~= '') and opts.args or vim.fn.input('rg > ')
        run_grep(query)
      end,
      desc = 'Search workspace text with ripgrep into quickfix',
      cmd = 'ReelocFastGrep',
      nargs = '?',
    },
    {
      mode = 'n',
      lhs = '<leader>fw',
      rhs = function()
        local word = vim.fn.expand('<cword>')
        if word ~= '' then
          run_grep(word)
        end
      end,
      desc = 'Grep word under cursor into quickfix',
      cmd = 'ReelocFastGrepWord',
      nargs = 0,
    },
  }

  for _, action in ipairs(grep_actions) do
    if action.lhs and action.mode then
      vim.keymap.set(action.mode, action.lhs, function()
        action.rhs()
      end, { desc = action.desc })
    end

    if action.cmd then
      vim.api.nvim_create_user_command(action.cmd, action.rhs, {
        desc = action.desc,
        nargs = action.nargs,
      })
    end
  end
end

return M
