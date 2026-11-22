-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

function M.setup()
  -- 1. Configure diagnostic display (virtual text and line signs)
  vim.diagnostic.config({
    virtual_text = { prefix = '■' },
    signs = true,
    underline = true,
    update_in_insert = false,
  })

  -- 2. Attach pylsp and ruff natively to Python buffers
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'python',
    callback = function()
      local root = vim.uv.cwd()

      vim.lsp.start({
        name = 'pylsp',
        cmd = { 'pylsp' },
        root_dir = root,
      })

      vim.lsp.start({
        name = 'ruff',
        cmd = { 'ruff', 'server' },
        root_dir = root,
      })
    end,
  })

  -- 3. Diagnostic navigation and inspection keymaps, Autocorrection keymaps
  local lsp_actions = {
    {
      mode = 'n',
      lhs = '[d',
      rhs = function() vim.diagnostic.goto_prev() end,
      desc = 'Previous diagnostic',
      cmd = 'ReelocLspPrevDiagnostic',
    },
    {
      mode = 'n',
      lhs = ']d',
      rhs = function() vim.diagnostic.goto_next() end,
      desc = 'Next diagnostic',
      cmd = 'ReelocLspNextDiagnostic',
    },
    {
      mode = 'n',
      lhs = '<leader>e',
      rhs = function() vim.diagnostic.open_float() end,
      desc = 'Show diagnostic error float',
      cmd = 'ReelocLspDiagnosticFloat',
    },
    {
      mode = 'n',
      lhs = '<leader>ca',
      rhs = function() vim.lsp.buf.code_action() end,
      desc = 'LSP Code Action',
      cmd = 'ReelocLspCodeAction',
    },
    {
      mode = 'n',
      lhs = '<leader>f',
      rhs = function()
        vim.lsp.buf.code_action({
          context = { only = { 'source.fixAll.ruff' } },
          apply = true,
        })
        vim.lsp.buf.format({ async = false })
      end,
      desc = 'Ruff auto-fix and format',
      cmd = 'ReelocLspRuffFix',
    },
    {
      -- Ex-command only (no leader keybinding)
      rhs = function()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then
          print('No active LSP clients attached to current buffer.')
          return
        end
        for _, client in ipairs(clients) do
          print(string.format('LSP Client: %s (ID: %d)', client.name, client.id))
        end
      end,
      desc = 'Show active LSP clients on current buffer',
      cmd = 'ReelocLspStatus',
    },
  }

  -- Register keymaps conditionally and Ex commands for all entries with a cmd
  for _, action in ipairs(lsp_actions) do
    if action.lhs and action.mode then
      vim.keymap.set(action.mode, action.lhs, action.rhs, { desc = action.desc })
    end

    if action.cmd then
      vim.api.nvim_create_user_command(action.cmd, action.rhs, { desc = action.desc })
    end
  end

end

return M
