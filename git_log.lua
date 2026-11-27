-- git_log.lua
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- 2-window commit history diff browser with expandable bottom commit log.

local M = {}

-- Default configuration options
M.config = {
  history_command = "GitHistory",
  max_commits = 50,
}

local common = require("common")

function M.setup(opts)
  -- Merge user configuration overrides with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local toggle_browser, get_session = common.create_diff_browser_session({
    filetype = "git-history",
    init = function(ctx)
      -- Fetch commit history for this specific file (full hash + subject)
      local res = vim.system({
        "git", "log", "--format=%H %s", "-n", tostring(M.config.max_commits), "--", ctx.relpath
      }, { text = true }):wait()

      if res.code ~= 0 or not res.stdout or res.stdout == "" then
        vim.notify("No commit history found for file", vim.log.levels.WARN)
        ctx.close()
        return
      end

      local commits = {}
      for line in res.stdout:gmatch("[^\r\n]+") do
        local hash, subject = line:match("^(%S+)%s+(.*)$")
        if hash then
          table.insert(commits, {
            hash = hash,
            subject = subject,
            body = nil,
            expanded = false,
          })
        end
      end

      -- Map 1-based buffer line numbers to entries in `commits`
      local line_to_commit_idx = {}

      -- Render commit headers and any expanded commit message bodies
      local function render_log()
        line_to_commit_idx = {}
        local buf_lines = {}
        for idx, commit in ipairs(commits) do
          local prefix = commit.expanded and "[-] " or "[+] "
          table.insert(buf_lines, prefix .. commit.hash:sub(1, 7) .. " " .. commit.subject)
          line_to_commit_idx[#buf_lines] = idx

          if commit.expanded and commit.body then
            for _, body_line in ipairs(commit.body) do
              table.insert(buf_lines, "    " .. body_line)
              line_to_commit_idx[#buf_lines] = idx
            end
          end
        end

        vim.bo[ctx.log_buf].modifiable = true
        vim.api.nvim_buf_set_lines(ctx.log_buf, 0, -1, false, buf_lines)
        vim.bo[ctx.log_buf].modifiable = false
      end

      render_log()

      -- Function triggered on <CR> to load parent vs selected commit diff into upper 2 windows
      local function inspect_selected_commit()
        if not vim.api.nvim_win_is_valid(ctx.log_win) then
          print("[GitHistory-Debug] log_win is invalid!")
          return
        end

        -- Force focus back to log window before reading cursor
        vim.api.nvim_set_current_win(ctx.log_win)

        local cursor = vim.api.nvim_win_get_cursor(ctx.log_win)
        local commit_idx = line_to_commit_idx[cursor[1]]
        if not commit_idx then return end

        local commit = commits[commit_idx]
        local commit_hash = commit.hash

        print(string.format("[GitHistory-Debug] Inspecting commit: %s", commit_hash))

        -- Fetch file content at parent commit and selected commit
        local parent_res = vim.system({ "git", "show", commit_hash .. "^:" .. ctx.relpath }, { text = true }):wait()
        local target_res = vim.system({ "git", "show", commit_hash .. ":" .. ctx.relpath }, { text = true }):wait()

        -- Fallback if parent^ doesn't exist (initial commit)
        local parent_content = (parent_res.code == 0 and parent_res.stdout) or ""
        local target_content = (target_res.code == 0 and target_res.stdout) or ""

        ctx.set_session_diff(
          parent_content,
          target_content,
          string.format("GitHistory://%s^/%s", commit_hash, ctx.relpath),
          string.format("GitHistory://%s/%s", commit_hash, ctx.relpath)
        )

        print(string.format("[GitHistory] Comparing %s^ vs %s for %s", commit_hash:sub(1, 7), commit_hash:sub(1, 7), ctx.relpath))
      end

      -- Function triggered on <Tab> to expand or collapse full commit message body inline
      local function toggle_commit_expansion()
        if not vim.api.nvim_win_is_valid(ctx.log_win) then
          print("[GitHistory-Debug] log_win is invalid!")
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(ctx.log_win)
        local commit_idx = line_to_commit_idx[cursor[1]]
        if not commit_idx then return end

        local commit = commits[commit_idx]
        print(string.format("[GitHistory-Debug] Toggling expansion for commit: %s (currently expanded: %s)", commit.hash:sub(1, 7), tostring(commit.expanded)))

        if not commit.expanded then
          if not commit.body then
            local body_res = vim.system({ "git", "show", "-s", "--format=%B", commit.hash }, { text = true }):wait()
            if body_res.code == 0 and body_res.stdout then
              local clean_body = body_res.stdout:gsub("%s+$", "")
              commit.body = vim.split(clean_body, "\n", { plain = true })
            else
              commit.body = { "(no commit message body)" }
            end
          end
          commit.expanded = true
        else
          commit.expanded = false
        end

        render_log()
        vim.api.nvim_win_set_cursor(ctx.log_win, { math.min(cursor[1], vim.api.nvim_buf_line_count(ctx.log_buf)), 0 })
      end

      -- Keymaps in log window
      vim.keymap.set("n", "<CR>", inspect_selected_commit, { buffer = ctx.log_buf, silent = true, desc = "Inspect commit diff" })
      vim.keymap.set("n", "<Tab>", toggle_commit_expansion, { buffer = ctx.log_buf, silent = true, desc = "Toggle commit body" })
      vim.keymap.set("n", "q", function()
        ctx.close()
        print("[GitHistory] Closed history browser")
      end, { buffer = ctx.log_buf, silent = true, desc = "Close history window" })
    end,
    on_close = function()
      print("[GitHistory] Closed history browser")
    end,
  })

  -- Expose user command for CLI / keymap usage
  vim.api.nvim_create_user_command(M.config.history_command, toggle_browser, {
    desc = "Open interactive 2-window commit history browser",
  })

  -- Keybinding to toggle history browser
  vim.keymap.set("n", "<leader>gh", ":" .. M.config.history_command .. "<CR>", { silent = true, desc = "Open Git commit history" })
end

return M
