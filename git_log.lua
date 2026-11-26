-- git_log.lua
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- 2-window commit history diff browser with bottom commit log.

local M = {}

-- Default configuration options
M.config = {
  history_command = "GitHistory",
  max_commits = 50,
}

local common = require("common")

-- Track active history session state globally
local active_session = nil

function M.setup(opts)
  -- Merge user configuration overrides with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Helper function to safely tear down diff windows and restore original file into the bottom window
  local function close_history()
    if not active_session then return end
    print("[GitHistory-Debug] closing history session START")
    pcall(vim.cmd, "diffoff!")

    print(string.format("[GitHistory-Debug] orig_win: %s (valid: %s)", tostring(active_session.orig_win), tostring(active_session.orig_win and vim.api.nvim_win_is_valid(active_session.orig_win))))
    print(string.format("[GitHistory-Debug] log_win: %s (valid: %s)", tostring(active_session.log_win), tostring(active_session.log_win and vim.api.nvim_win_is_valid(active_session.log_win))))
    print(string.format("[GitHistory-Debug] left_win: %s (valid: %s)", tostring(active_session.left_win), tostring(active_session.left_win and vim.api.nvim_win_is_valid(active_session.left_win))))
    print(string.format("[GitHistory-Debug] right_win: %s (valid: %s)", tostring(active_session.right_win), tostring(active_session.right_win and vim.api.nvim_win_is_valid(active_session.right_win))))

    -- 1. Close upper diff windows first (safe since log_win is still open)
    if active_session.right_win and vim.api.nvim_win_is_valid(active_session.right_win) then
      print("[GitHistory-Debug] Closing right_win")
      vim.api.nvim_win_close(active_session.right_win, true)
    end
    if active_session.left_win and vim.api.nvim_win_is_valid(active_session.left_win) then
      print("[GitHistory-Debug] Closing left_win")
      vim.api.nvim_win_close(active_session.left_win, true)
    end

    -- 2. Instead of closing log_win (which causes E444), reuse it and restore orig_bufnr!
    if active_session.log_win and vim.api.nvim_win_is_valid(active_session.log_win) then
      print("[GitHistory-Debug] Reusing log_win to restore orig_bufnr")
      vim.api.nvim_set_current_win(active_session.log_win)
      if active_session.orig_bufnr and vim.api.nvim_buf_is_valid(active_session.orig_bufnr) then
        vim.api.nvim_win_set_buf(active_session.log_win, active_session.orig_bufnr)
      end
    elseif active_session.orig_win and vim.api.nvim_win_is_valid(active_session.orig_win) then
      vim.api.nvim_set_current_win(active_session.orig_win)
    end

    active_session = nil
    print("[GitHistory-Debug] closing history session END")
  end

  -- Main function to open or toggle the interactive commit history inspector
  local function open_history_inspector()
    -- Toggle off if already active
    if active_session then
      close_history()
      print("[GitHistory] Closed history browser")
      return
    end

    local orig_bufnr = vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(orig_bufnr)
    if file == "" then
      vim.notify("Buffer has no file on disk", vim.log.levels.WARN)
      return
    end

    -- Extract repo-relative path for git execution
    local relpath = common.get_repo_rel_path(file)
    if not relpath then
      vim.notify("File is not tracked in git repository", vim.log.levels.WARN)
      return
    end

    -- Fetch commit history for this specific file
    local res = vim.system({
      "git", "log", "--oneline", "-n", tostring(M.config.max_commits), "--", relpath
    }, { text = true }):wait()

    if res.code ~= 0 or not res.stdout or res.stdout == "" then
      vim.notify("No commit history found for file", vim.log.levels.WARN)
      return
    end

    local lines = {}
    for line in res.stdout:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end

    -- Remember original window reference
    local orig_win = vim.api.nvim_get_current_win()
    print("[GitHistory-Debug] Stored orig_win: " .. tostring(orig_win))

    -- 1. Open bottom horizontal split for log selection
    vim.cmd("botright 10split")
    local log_win = vim.api.nvim_get_current_win()
    local log_buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(log_win, log_buf)
    vim.bo[log_buf].buftype = "nofile"
    vim.bo[log_buf].bufhidden = "wipe"
    vim.bo[log_buf].swapfile = false
    vim.bo[log_buf].filetype = "git-history"
    vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, lines)
    vim.bo[log_buf].modifiable = false

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

    -- Function triggered on <CR> to load parent vs selected commit diff into upper 2 windows
    local function inspect_selected_commit()
      if not vim.api.nvim_win_is_valid(log_win) then
        print("[GitHistory-Debug] log_win is invalid!")
        return
      end

      -- Force focus back to log window before reading cursor
      vim.api.nvim_set_current_win(log_win)

      local cursor = vim.api.nvim_win_get_cursor(log_win)
      local line = vim.api.nvim_buf_get_lines(log_buf, cursor[1] - 1, cursor[1], false)[1]
      if not line then return end

      local commit_hash = line:match("^(%S+)")
      if not commit_hash then return end

      print(string.format("[GitHistory-Debug] Inspecting commit: %s", commit_hash))

      -- Fetch file content at parent commit and selected commit
      local parent_res = vim.system({ "git", "show", commit_hash .. "^:" .. relpath }, { text = true }):wait()
      local target_res = vim.system({ "git", "show", commit_hash .. ":" .. relpath }, { text = true }):wait()

      -- Fallback if parent^ doesn't exist (initial commit)
      local parent_content = (parent_res.code == 0 and parent_res.stdout) or ""
      local target_content = (target_res.code == 0 and target_res.stdout) or ""

      local l_lines = vim.split(parent_content, "\n", { plain = true })
      if #l_lines > 0 and l_lines[#l_lines] == "" then table.remove(l_lines) end

      local r_lines = vim.split(target_content, "\n", { plain = true })
      if #r_lines > 0 and r_lines[#r_lines] == "" then table.remove(r_lines) end

      -- If diff windows already exist and are valid, reuse them in place to prevent layout collapse!
      if active_session.left_win and vim.api.nvim_win_is_valid(active_session.left_win) and
         active_session.right_win and vim.api.nvim_win_is_valid(active_session.right_win) and
         active_session.left_buf and vim.api.nvim_buf_is_valid(active_session.left_buf) and
         active_session.right_buf and vim.api.nvim_buf_is_valid(active_session.right_buf) then

        print("[GitHistory-Debug] Reusing existing diff windows in-place")
        
        -- Update left buffer content
        vim.bo[active_session.left_buf].modifiable = true
        vim.api.nvim_buf_set_lines(active_session.left_buf, 0, -1, false, l_lines)
        pcall(vim.api.nvim_buf_set_name, active_session.left_buf, string.format("GitHistory://%s^/%s", commit_hash, relpath))
        vim.bo[active_session.left_buf].readonly = true
        vim.bo[active_session.left_buf].modifiable = false

        -- Update right buffer content
        vim.bo[active_session.right_buf].modifiable = true
        vim.api.nvim_buf_set_lines(active_session.right_buf, 0, -1, false, r_lines)
        pcall(vim.api.nvim_buf_set_name, active_session.right_buf, string.format("GitHistory://%s/%s", commit_hash, relpath))
        vim.bo[active_session.right_buf].readonly = true
        vim.bo[active_session.right_buf].modifiable = false

        -- Ensure diff mode is active on both
        vim.api.nvim_set_current_win(active_session.left_win)
        vim.cmd("diffthis")
        vim.api.nvim_set_current_win(active_session.right_win)
        vim.cmd("diffthis")

        -- Return focus to log window
        vim.api.nvim_set_current_win(log_win)
        print(string.format("[GitHistory] Comparing %s^ vs %s for %s", commit_hash, commit_hash, relpath))
        return
      end

      -- First time opening diff panes: split from log window up
      vim.api.nvim_set_current_win(log_win)
      vim.cmd("wincmd k")

      -- Create fresh scratch buffers for left and right diffs
      local left_buf_name = string.format("GitHistory://%s^/%s", commit_hash, relpath)
      local right_buf_name = string.format("GitHistory://%s/%s", commit_hash, relpath)

      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) then
          local name = vim.api.nvim_buf_get_name(b)
          if name == left_buf_name or name == right_buf_name then
            vim.api.nvim_buf_delete(b, { force = true })
          end
        end
      end

      -- Populate left buffer (parent revision)
      local left_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(left_buf, left_buf_name)
      vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, l_lines)
      vim.bo[left_buf].readonly = true
      vim.bo[left_buf].modifiable = false
      vim.bo[left_buf].buftype = "nofile"

      -- Populate right buffer (selected revision)
      local right_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(right_buf, right_buf_name)
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

      -- Return focus to the log window so user can keep browsing with j/k and <CR>
      if vim.api.nvim_win_is_valid(log_win) then
        vim.api.nvim_set_current_win(log_win)
      end

      print(string.format("[GitHistory] Comparing %s^ vs %s for %s", commit_hash, commit_hash, relpath))
    end

    -- Keymaps in log window
    vim.keymap.set("n", "<CR>", inspect_selected_commit, { buffer = log_buf, silent = true, desc = "Inspect commit diff" })
    vim.keymap.set("n", "q", function()
      close_history()
      print("[GitHistory] Closed history browser")
    end, { buffer = log_buf, silent = true, desc = "Close history window" })
  end

  -- Expose user command for CLI / keymap usage
  vim.api.nvim_create_user_command(M.config.history_command, open_history_inspector, {
    desc = "Open interactive 2-window commit history browser",
  })

  -- Keybinding to toggle history browser
  vim.keymap.set("n", "<leader>gh", ":" .. M.config.history_command .. "<CR>", { silent = true, desc = "Open Git commit history" })
end

return M
