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

  -- 3. Diagnostic navigation and inspection keymaps
  vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Previous diagnostic' })
  vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
  vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic error float' })

  -- 4. Autocorrection keymaps
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'LSP Code Action' })

  vim.keymap.set('n', '<leader>f', function()
    vim.lsp.buf.code_action({
      context = { only = { 'source.fixAll.ruff' } },
      apply = true,
    })
    vim.lsp.buf.format({ async = false })
  end, { desc = 'Ruff auto-fix and format' })
end

return M
