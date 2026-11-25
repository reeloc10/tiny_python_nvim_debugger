-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

function M.setup()
  local ns = vim.api.nvim_create_namespace('reeloc_lua_syntax')

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'InsertLeave' }, {
    pattern = '*.lua',
    callback = function(args)
      local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
      local bufname = vim.api.nvim_buf_get_name(args.buf)

      -- Compile buffer text in memory via embedded LuaJIT (never executes it)
      local chunk, err = loadstring(table.concat(lines, '\n'), '@' .. bufname)
      if chunk then
        vim.diagnostic.reset(ns, args.buf)
        return
      end

      -- LuaJIT formats syntax errors as "<chunkname>:<line>: <message>"
      local lnum, msg = err:match(':(%d+):%s*(.+)')
      vim.diagnostic.set(ns, args.buf, {
        {
          lnum = (tonumber(lnum) or 1) - 1, -- vim.diagnostic uses 0-indexed lines
          col = 0,
          severity = vim.diagnostic.severity.ERROR,
          source = 'luajit',
          message = msg or err,
        },
      })
    end,
  })
end

return M
