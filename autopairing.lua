-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

local pairs_map = {
  ['('] = ')',
  ['['] = ']',
  ['{'] = '}',
  ['"'] = '"',
  ["'"] = "'",
}

function M.setup()
  for open, close in pairs(pairs_map) do
    -- Auto-close pair or step over closing quote
    vim.keymap.set('i', open, function()
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2]
      local next_char = line:sub(col + 1, col + 1)

      if open == close and next_char == close then
        return '<Right>'
      end

      -- Avoid auto-pairing quotes immediately after an alphanumeric character (e.g., contractions like don't)
      if open == close then
        local prev_char = col > 0 and line:sub(col, col) or ''
        if prev_char:match('[%w_]') then
          return open
        end
      end

      return open .. close .. '<Left>'
    end, { expr = true, noremap = true, desc = 'Auto-pair ' .. open .. close })

    -- Step over closing bracket/brace instead of duplicating it
    if open ~= close then
      vim.keymap.set('i', close, function()
        local line = vim.api.nvim_get_current_line()
        local col = vim.api.nvim_win_get_cursor(0)[2]
        if line:sub(col + 1, col + 1) == close then
          return '<Right>'
        end
        return close
      end, { expr = true, noremap = true, desc = 'Step over ' .. close })
    end
  end

  -- Delete both characters when pressing Backspace inside an empty pair
  vim.keymap.set('i', '<BS>', function()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local prev_char = col > 0 and line:sub(col, col) or ''
    local next_char = line:sub(col + 1, col + 1)
    if pairs_map[prev_char] == next_char then
      return '<Right><BS><BS>'
    end
    return '<BS>'
  end, { expr = true, noremap = true, desc = 'Delete empty auto-pair' })
end

return M
