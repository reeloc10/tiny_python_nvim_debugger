-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

-- Single source of truth for the repository root
M.cloned_folder = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

function M.get_repo_rel_path(filepath)
  if not filepath or filepath == "" then return nil end
  local res = vim.system({ "git", "ls-files", "--full-name", "--", filepath }, { text = true }):wait()
  if res.code ~= 0 then return nil end
  local path = vim.trim(res.stdout or "")
  return path ~= "" and path or nil
end

-- Reusable 3-window diff browser engine session manager
function M.create_diff_browser_session(opts)
  local active_session = nil

  -- Helper function to safely tear down diff windows and restore original file into the bottom window
  local function close_session()
    if not active_session then return end
    print("[GitBrowser-Debug] closing session START")
    pcall(vim.cmd, "diffoff!")

    print(string.format("[GitBrowser-Debug] orig_win: %s (valid: %s)", tostring(active_session.orig_win), tostring(active_session.orig_win and vim.api.nvim_win_is_valid(active_session.orig_win))))
    print(string.format("[GitBrowser-Debug] log_win: %s (valid: %s)", tostring(active_session.log_win), tostring(active_session.log_win and vim.api.nvim_win_is_valid(active_session.log_win))))
    print(string.format("[GitBrowser-Debug] left_win: %s (valid: %s)", tostring(active_session.left_win), tostring(active_session.left_win and vim.api.nvim_win_is_valid(active_session.left_win))))
    print(string.format("[GitBrowser-Debug] right_win: %s (valid: %s)", tostring(active_session.right_win), tostring(active_session.right_win and vim.api.nvim_win_is_valid(active_session.right_win))))

    -- 1. Close upper diff windows first (safe since log_win is still open)
    if active_session.right_win and vim.api.nvim_win_is_valid(active_session.right_win) then
      print("[GitBrowser-Debug] Closing right_win")
      vim.api.nvim_win_close(active_session.right_win, true)
    end
    if active_session.left_win and vim.api.nvim_win_is_valid(active_session.left_win) then
      print("[GitBrowser-Debug] Closing left_win")
      vim.api.nvim_win_close(active_session.left_win, true)
    end

    -- 2. Instead of closing log_win (which causes E444), reuse it and restore orig_bufnr!
    if active_session.log_win and vim.api.nvim_win_is_valid(active_session.log_win) then
      print("[GitBrowser-Debug] Reusing log_win to restore orig_bufnr")
      vim.api.nvim_set_current_win(active_session.log_win)
      if active_session.orig_bufnr and vim.api.nvim_buf_is_valid(active_session.orig_bufnr) then
        vim.api.nvim_win_set_buf(active_session.log_win, active_session.orig_bufnr)
      end
    elseif active_session.orig_win and vim.api.nvim_win_is_valid(active_session.orig_win) then
      vim.api.nvim_set_current_win(active_session.orig_win)
    end

    active_session = nil
    print("[GitBrowser-Debug] closing session END")
  end

  local function toggle_browser()
    -- Toggle off if already active
    if active_session then
      close_session()
      if opts.on_close then opts.on_close() end
      return
    end

    local orig_bufnr = vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(orig_bufnr)
    if file == "" then
      vim.notify("Buffer has no file on disk", vim.log.levels.WARN)
      return
    end

    -- Extract repo-relative path for git execution
    local relpath = M.get_repo_rel_path(file)
    if not relpath then
      vim.notify("File is not tracked in git repository", vim.log.levels.WARN)
      return
    end

    -- Remember original window reference
    local orig_win = vim.api.nvim_get_current_win()
    print("[GitBrowser-Debug] Stored orig_win: " .. tostring(orig_win))

    -- 1. Open bottom horizontal split for log selection
    vim.cmd("botright 10split")
    local log_win = vim.api.nvim_get_current_win()
    local log_buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(log_win, log_buf)
    vim.bo[log_buf].buftype = "nofile"
    vim.bo[log_buf].bufhidden = "wipe"
    vim.bo[log_buf].swapfile = false
    vim.bo[log_buf].filetype = opts.filetype or "git-history"

    -- Initialize active session state
    active_session = {
      log_win = log_win,
      orig_win = orig_win,
      orig_bufnr = orig_bufnr,
      left_win = nil,
      right_win = nil,
      left_buf = nil,
      right_buf = nil,
    }

    -- Allow the module to populate buffer lines, keymaps, and callbacks
    if opts.init then
      opts.init({
        log_win = log_win,
        log_buf = log_buf,
        orig_bufnr = orig_bufnr,
        relpath = relpath,
        file = file,
        get_session = function() return active_session end,
        set_session_diff = function(left_content, right_content, left_name, right_name)
          M.update_diff_panes(active_session, log_win, left_content, right_content, left_name, right_name)
        end,
        close = close_session,
      })
    end
  end

  return toggle_browser, function() return active_session end
end

-- Helper to populate or reuse upper left/right vimdiff panes
function M.update_diff_panes(active_session, log_win, left_content, right_content, left_name, right_name)
  local l_lines = vim.split(left_content, "\n", { plain = true })
  if #l_lines > 0 and l_lines[#l_lines] == "" then table.remove(l_lines) end

  local r_lines = vim.split(right_content, "\n", { plain = true })
  if #r_lines > 0 and r_lines[#r_lines] == "" then table.remove(r_lines) end

  -- If diff windows already exist and are valid, reuse them in place to prevent layout collapse!
  if active_session.left_win and vim.api.nvim_win_is_valid(active_session.left_win) and
     active_session.right_win and vim.api.nvim_win_is_valid(active_session.right_win) and
     active_session.left_buf and vim.api.nvim_buf_is_valid(active_session.left_buf) and
     active_session.right_buf and vim.api.nvim_buf_is_valid(active_session.right_buf) then

    print("[GitBrowser-Debug] Reusing existing diff windows in-place")

    -- Update left buffer content
    vim.bo[active_session.left_buf].modifiable = true
    vim.api.nvim_buf_set_lines(active_session.left_buf, 0, -1, false, l_lines)
    pcall(vim.api.nvim_buf_set_name, active_session.left_buf, left_name)
    vim.bo[active_session.left_buf].readonly = true
    vim.bo[active_session.left_buf].modifiable = false

    -- Update right buffer content
    vim.bo[active_session.right_buf].modifiable = true
    vim.api.nvim_buf_set_lines(active_session.right_buf, 0, -1, false, r_lines)
    pcall(vim.api.nvim_buf_set_name, active_session.right_buf, right_name)
    vim.bo[active_session.right_buf].readonly = true
    vim.bo[active_session.right_buf].modifiable = false

    -- Ensure diff mode is active on both
    vim.api.nvim_set_current_win(active_session.left_win)
    vim.cmd("diffthis")
    vim.api.nvim_set_current_win(active_session.right_win)
    vim.cmd("diffthis")

    -- Return focus to log window
    vim.api.nvim_set_current_win(log_win)
    return
  end

  -- First time opening diff panes: split from log window up
  vim.api.nvim_set_current_win(log_win)
  vim.cmd("wincmd k")

  -- Create fresh scratch buffers for left and right diffs
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name == left_name or name == right_name then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end
  end

  -- Populate left buffer
  local left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(left_buf, left_name)
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, l_lines)
  vim.bo[left_buf].readonly = true
  vim.bo[left_buf].modifiable = false
  vim.bo[left_buf].buftype = "nofile"

  -- Populate right buffer
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(right_buf, right_name)
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, r_lines)
  vim.bo[right_buf].readonly = true
  vim.bo[right_buf].modifiable = false
  vim.bo[right_buf].buftype = "nofile"

  -- Open side-by-side diff panes above the bottom log window
  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right_buf)
  vim.cmd("diffthis")

  vim.cmd("wincmd h")
  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left_buf)
  vim.cmd("diffthis")

  -- Store active window references for cleanup
  active_session.left_win = left_win
  active_session.right_win = right_win
  active_session.left_buf = left_buf
  active_session.right_buf = right_buf

  -- Return focus to the log window
  if vim.api.nvim_win_is_valid(log_win) then
    vim.api.nvim_set_current_win(log_win)
  end
end

return M
