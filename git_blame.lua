-- git_blame.lua
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

M.config = {
  enabled = true,
  split_width = 36,
}

local HOVER_TIMEOUT = 3000 -- milliseconds
local SPLIT_REFRESH_DEBOUNCE = 250 -- milliseconds
local ns_id = vim.api.nvim_create_namespace('reeloc_git_blame')
local timer = nil

-- Track active blame split state per source buffer:
-- [src_buf] = { src_win, blame_win, blame_buf, augroup, debounce_timer }
local active_splits = {}

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

local function format_short_date(epoch_str)
  local epoch = tonumber(epoch_str)
  if not epoch then return '          ' end
  return os.date('%Y-%m-%d', epoch)
end

local function get_buffer_stdin(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')
  if vim.bo[bufnr].eol then
    content = content .. '\n'
  end
  return content, #lines
end

local function parse_line_porcelain(stdout, expected_lines)
  local result = {}
  local hash, author, author_time

  for _, line in ipairs(vim.split(stdout, '\n', { plain = true })) do
    local h = line:match('^([0-9a-f]+)%s+%d+%s+%d+')
    if h then
      hash = h
      author = nil
      author_time = nil
    elseif hash then
      local a = line:match('^author%s+(.+)$')
      if a then author = a end

      local t = line:match('^author%-time%s+(%d+)$')
      if t then author_time = t end

      if line:sub(1, 1) == '\t' then
        if hash:match('^0+$') then
          table.insert(result, string.format('0000000 %-10s Uncommitted', ''))
        else
          local short_hash = hash:sub(1, 7)
          local date_str = format_short_date(author_time)
          local author_str = (author or 'Unknown'):sub(1, 16)
          table.insert(result, string.format('%s %s %-16s', short_hash, date_str, author_str))
        end
        hash = nil
      end
    end
  end

  -- Guarantee exact 1:1 line count parity with the source buffer
  while #result < expected_lines do
    table.insert(result, string.format('0000000 %-10s Uncommitted', ''))
  end
  while #result > expected_lines do
    table.remove(result)
  end

  return result
end

local function close_blame_split(src_buf)
  local state = active_splits[src_buf]
  if not state then return end
  active_splits[src_buf] = nil

  if state.debounce_timer then
    state.debounce_timer:stop()
    state.debounce_timer:close()
  end

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end

  if state.src_win and vim.api.nvim_win_is_valid(state.src_win) then
    vim.wo[state.src_win].scrollbind = false
    vim.wo[state.src_win].cursorbind = false
  end

  if state.blame_win and vim.api.nvim_win_is_valid(state.blame_win) then
    vim.api.nvim_win_close(state.blame_win, true)
  end

  if state.blame_buf and vim.api.nvim_buf_is_valid(state.blame_buf) then
    vim.api.nvim_buf_delete(state.blame_buf, { force = true })
  end
end

local function update_blame_split_buffer(src_buf)
  local state = active_splits[src_buf]
  if not state then return end
  if not vim.api.nvim_buf_is_valid(src_buf) then
    close_blame_split(src_buf)
    return
  end

  local file = vim.api.nvim_buf_get_name(src_buf)
  if file == '' then return end

  local content, line_count = get_buffer_stdin(src_buf)
  local cwd = vim.fs.dirname(file)

  vim.system({
    'git',
    'blame',
    '--line-porcelain',
    '--contents',
    '-',
    '--',
    file,
  }, { text = true, stdin = content, cwd = cwd }, function(proc)
    if proc.code ~= 0 or not proc.stdout then return end

    local blame_lines = parse_line_porcelain(proc.stdout, line_count)

    vim.schedule(function()
      local current_state = active_splits[src_buf]
      if not current_state then return end
      if not vim.api.nvim_buf_is_valid(current_state.blame_buf) or not vim.api.nvim_win_is_valid(current_state.blame_win) then
        close_blame_split(src_buf)
        return
      end

      vim.bo[current_state.blame_buf].modifiable = true
      vim.api.nvim_buf_set_lines(current_state.blame_buf, 0, -1, false, blame_lines)
      vim.bo[current_state.blame_buf].modifiable = false

      if vim.api.nvim_win_is_valid(current_state.src_win) then
        local view = vim.api.nvim_win_call(current_state.src_win, vim.fn.winsaveview)
        vim.api.nvim_win_call(current_state.blame_win, function()
          vim.fn.winrestview({ topline = view.topline, lnum = view.lnum, col = 0 })
        end)
        vim.cmd('syncbind')
      end
    end)
  end)
end

function M.toggle_blame_split()
  local src_buf = vim.api.nvim_get_current_buf()
  local src_win = vim.api.nvim_get_current_win()

  if active_splits[src_buf] then
    close_blame_split(src_buf)
    return
  end

  local file = vim.api.nvim_buf_get_name(src_buf)
  if file == '' or vim.bo[src_buf].buftype ~= '' then return end

  local content, line_count = get_buffer_stdin(src_buf)
  local cwd = vim.fs.dirname(file)

  vim.system({
    'git',
    'blame',
    '--line-porcelain',
    '--contents',
    '-',
    '--',
    file,
  }, { text = true, stdin = content, cwd = cwd }, function(proc)
    if proc.code ~= 0 or not proc.stdout then
      vim.schedule(function()
        vim.notify('Git blame failed: ' .. (proc.stderr or 'not in a git repo'), vim.log.levels.WARN)
      end)
      return
    end

    local blame_lines = parse_line_porcelain(proc.stdout, line_count)

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(src_buf) or not vim.api.nvim_win_is_valid(src_win) then
        return
      end
      if active_splits[src_buf] then return end

      local view = vim.api.nvim_win_call(src_win, vim.fn.winsaveview)

      local blame_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[blame_buf].buftype = 'nofile'
      vim.bo[blame_buf].bufhidden = 'wipe'
      vim.bo[blame_buf].swapfile = false
      vim.bo[blame_buf].filetype = 'reeloc-gitblame'
      vim.api.nvim_buf_set_lines(blame_buf, 0, -1, false, blame_lines)
      vim.bo[blame_buf].modifiable = false

      vim.api.nvim_set_current_win(src_win)
      vim.cmd('topleft ' .. M.config.split_width .. 'vsplit')
      local blame_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(blame_win, blame_buf)

      -- Match source window scroll and cursor position before binding
      vim.api.nvim_win_call(blame_win, function()
        vim.fn.winrestview({ topline = view.topline, lnum = view.lnum, col = 0 })
      end)

      local win_opts = {
        number = false,
        relativenumber = false,
        signcolumn = 'no',
        foldcolumn = '0',
        wrap = false,
        list = false,
        winfixwidth = true,
        scrollbind = true,
        cursorbind = true,
      }
      for k, v in pairs(win_opts) do
        vim.wo[blame_win][k] = v
      end

      vim.wo[src_win].scrollbind = true
      vim.wo[src_win].cursorbind = true
      vim.cmd('syncbind')

      local split_grp = vim.api.nvim_create_augroup('ReelocGitBlameSplit_' .. src_buf, { clear = true })
      local debounce_timer = vim.uv.new_timer()

      active_splits[src_buf] = {
        src_win = src_win,
        blame_win = blame_win,
        blame_buf = blame_buf,
        augroup = split_grp,
        debounce_timer = debounce_timer,
      }

      -- Refresh blame split live as unsaved buffer changes or saves
      vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
        group = split_grp,
        buffer = src_buf,
        callback = function()
          local st = active_splits[src_buf]
          if not st or not st.debounce_timer then return end
          st.debounce_timer:stop()
          st.debounce_timer:start(SPLIT_REFRESH_DEBOUNCE, 0, vim.schedule_wrap(function()
            update_blame_split_buffer(src_buf)
          end))
        end,
      })

      vim.keymap.set('n', 'q', function()
        close_blame_split(src_buf)
      end, { buffer = blame_buf, silent = true, desc = 'Close git blame split' })

      vim.api.nvim_create_autocmd({ 'BufWipeout', 'WinClosed' }, {
        group = split_grp,
        buffer = blame_buf,
        once = true,
        callback = function()
          close_blame_split(src_buf)
        end,
      })

      vim.api.nvim_set_current_win(src_win)
    end)
  end)
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
  local content = get_buffer_stdin(bufnr)
  local cwd = vim.fs.dirname(file)

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
  }, { text = true, stdin = content, cwd = cwd }, function(proc)
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

    vim.system({ 'git', 'branch', '-r', '--contains', commit_hash }, { text = true, cwd = cwd }, function(push_proc)
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

  vim.api.nvim_create_user_command('GitBlameSplit', function()
    M.toggle_blame_split()
  end, { desc = 'Toggle left-split full-file git blame sidebar' })

  vim.keymap.set('n', '<leader>gb', ':GitBlameLine<CR>', { silent = true, desc = 'Git blame current line' })
  vim.keymap.set('n', '<leader>gB', ':GitBlameSplit<CR>', { silent = true, desc = 'Toggle git blame split' })
end

return M
