-- git_blame.lua
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

M.config = {
  enabled = true,
}

local HOVER_TIMEOUT = 3000 -- milliseconds
local ns_id = vim.api.nvim_create_namespace('reeloc_git_blame')
local timer = nil

local function clear_blame(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end
end

local function format_timestamp(epoch_str)
  local epoch = tonumber(epoch_str)
  if not epoch then return '' end
  return os.date('%Y-%m-%d %H:%M', epoch)
end

local function fetch_and_show_blame(bufnr)
  if not M.config.enabled then return end
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == '' or vim.bo[bufnr].buftype ~= '' then return end

  -- Ensure we are still in the same buffer and window
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= bufnr then return end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]

  -- Grab the live, unsaved buffer lines in memory
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')

  vim.system({
    'git',
    'blame',
    '-L',
    string.format('%d,%d', lnum, lnum),
    '--porcelain',
    '--contents',
    '-',
    '--',
    file,
  }, { text = true, stdin = content }, function(proc)
    if proc.code ~= 0 or not proc.stdout then return end

    local output = proc.stdout
    local commit_hash = output:match('^([0-9a-f]+)%s+')
    local author = output:match('\nauthor%s+(.-)\n')
    local author_time = output:match('\nauthor%-time%s+(%d+)\n')
    local summary = output:match('\nsummary%s+(.-)\n')

    if not commit_hash then return end

    local is_uncommitted = commit_hash:match('^0+$') ~= nil
    local short_hash = is_uncommitted and '0000000' or commit_hash:sub(1, 7)
    local date_str = format_timestamp(author_time)

    if is_uncommitted then
      local blame_text = '  [Uncommitted Working Changes]'
      vim.schedule(function()
        if not M.config.enabled then return end
        if vim.api.nvim_get_current_buf() ~= bufnr then return end
        if vim.api.nvim_win_get_cursor(0)[1] ~= lnum then return end
        clear_blame(bufnr)
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, lnum - 1, 0, {
          virt_text = { { blame_text, 'Comment' } },
          virt_text_pos = 'eol',
        })
      end)
      return
    end

    vim.system({ 'git', 'branch', '-r', '--contains', commit_hash }, { text = true }, function(push_proc)
      local is_pushed = (push_proc.code == 0 and push_proc.stdout and vim.trim(push_proc.stdout) ~= '')
      local push_status = is_pushed and 'Pushed' or 'Local'

      local blame_text = string.format('  %s [%s | %s] (%s: %s)',
        short_hash, date_str, push_status, author or 'Unknown', summary or '')

      vim.schedule(function()
        if not M.config.enabled then return end
        if vim.api.nvim_get_current_buf() ~= bufnr then return end
        local current_lnum = vim.api.nvim_win_get_cursor(0)[1]
        if current_lnum ~= lnum then return end

        clear_blame(bufnr)
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, lnum - 1, 0, {
          virt_text = { { blame_text, 'Comment' } },
          virt_text_pos = 'eol',
        })
      end)
    end)
  end)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})

  local grp = vim.api.nvim_create_augroup('ReelocGitBlameHover', { clear = true })

  -- Reset timer and clear virtual text whenever cursor moves or buffer changes
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufLeave', 'InsertEnter' }, {
    group = grp,
    pattern = '*',
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      clear_blame(bufnr)

      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
    end,
  })

  -- Start a 5-second idle timer when cursor stops moving
  vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
    group = grp,
    pattern = '*',
    callback = function()
      if not M.config.enabled then return end
      local bufnr = vim.api.nvim_get_current_buf()
      if timer then
        timer:stop()
        timer:close()
      end

      timer = vim.uv.new_timer()
      timer:start(HOVER_TIMEOUT, 0, vim.schedule_wrap(function()
        fetch_and_show_blame(bufnr)
      end))
    end,
  })

  -- Toggle command for git blame annotation hover
  vim.api.nvim_create_user_command('GitSignAnnotateToggle', function()
    M.config.enabled = not M.config.enabled
    print('Git Sign Annotate enabled: ' .. tostring(M.config.enabled))
    if not M.config.enabled then
      local bufnr = vim.api.nvim_get_current_buf()
      clear_blame(bufnr)
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
    end
  end, { desc = 'Toggle inline git blame hover annotations' })

  vim.api.nvim_create_user_command('GitBlameLine', function()
    fetch_and_show_blame(vim.api.nvim_get_current_buf())
  end, { desc = 'Show git blame info for current line' })

  vim.keymap.set('n', '<leader>gb', ':GitBlameLine<CR>', { silent = true, desc = 'Git blame current line' })
end

return M
