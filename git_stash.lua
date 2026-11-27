-- git_stash.lua
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- 3-window interactive git stash list & diff browser.

local M = {}

M.config = {
  stash_command = "GitStashBrowser",
}

local common = require("common")

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local toggle_browser = common.create_diff_browser_session({
    filetype = "git-stash",
    init = function(ctx)
      -- Fetch stash entries list (%gd = reflog selector stash@{N}, %s = subject/message)
      local res = vim.system({
        "git", "stash", "list", "--format=%gd %s"
      }, { text = true }):wait()

      if res.code ~= 0 or not res.stdout then
        vim.notify("No stashes found in repository", vim.log.levels.WARN)
        ctx.close()
        return
      end

      local stashes = {}
      for line in res.stdout:gmatch("[^\r\n]+") do
        local stash_ref, message = line:match("^(stash@%{%d+%})%s+(.*)$")
        if stash_ref then
          table.insert(stashes, {
            ref = stash_ref,
            message = message,
          })
        end
      end

      local line_to_stash_idx = {}

      local function render_stash_list()
        line_to_stash_idx = {}
        local buf_lines = {}
        for idx, stash in ipairs(stashes) do
          table.insert(buf_lines, string.format("%s: %s", stash.ref, stash.message))
          line_to_stash_idx[#buf_lines] = idx
        end

        vim.bo[ctx.log_buf].modifiable = true
        vim.api.nvim_buf_set_lines(ctx.log_buf, 0, -1, false, buf_lines)
        vim.bo[ctx.log_buf].modifiable = false
      end

      render_stash_list()

      -- Helper to reload original file buffer from disk
      local function reload_buffer()
        if vim.api.nvim_buf_is_valid(ctx.orig_bufnr) then
          vim.api.nvim_buf_call(ctx.orig_bufnr, function()
            vim.cmd("e!")
          end)
        end
      end

      -- Helper to refresh stash list from git
      local function refresh_stash_list()
        local list_res = vim.system({ "git", "stash", "list", "--format=%gd %s" }, { text = true }):wait()
        if list_res.code == 0 and list_res.stdout then
          stashes = {}
          for line in list_res.stdout:gmatch("[^\r\n]+") do
            local stash_ref, message = line:match("^(stash@%{%d+%})%s+(.*)$")
            if stash_ref then
              table.insert(stashes, { ref = stash_ref, message = message })
            end
          end
          render_stash_list()
        else
          stashes = {}
          render_stash_list()
        end
      end

      -- Dismiss upper vimdiff panes and restore original file buffer above the stash list without breaking session handles
      local function close_diff_preview()
        local session = ctx.get_session()
        if not session then return end

        pcall(vim.cmd, "diffoff!")

        -- Close right diff window if valid
        if session.right_win and vim.api.nvim_win_is_valid(session.right_win) then
          vim.api.nvim_win_close(session.right_win, true)
        end
        session.right_win = nil
        session.right_buf = nil

        -- Restore original buffer into left window instead of destroying session.left_win
        if session.left_win and vim.api.nvim_win_is_valid(session.left_win) then
          if vim.api.nvim_buf_is_valid(ctx.orig_bufnr) then
            vim.api.nvim_win_set_buf(session.left_win, ctx.orig_bufnr)
          end
        end

        if vim.api.nvim_win_is_valid(ctx.log_win) then
          vim.api.nvim_set_current_win(ctx.log_win)
        end
        vim.notify("Diff preview closed", vim.log.levels.INFO)
      end

      -- Function triggered on <CR> to inspect stashed file diff in the upper vimdiff windows
      local function inspect_selected_stash()
        if not vim.api.nvim_win_is_valid(ctx.log_win) then return end

        vim.api.nvim_set_current_win(ctx.log_win)
        local cursor = vim.api.nvim_win_get_cursor(ctx.log_win)
        local stash_idx = line_to_stash_idx[cursor[1]]
        if not stash_idx then return end

        local stash = stashes[stash_idx]

        -- A stash commit has multiple parents:
        -- stash@{N}^1 is HEAD commit when stashed
        -- stash@{N} is the stashed commit
        local parent_res = vim.system({ "git", "show", stash.ref .. "^1:" .. ctx.relpath }, { text = true }):wait()
        local target_res = vim.system({ "git", "show", stash.ref .. ":" .. ctx.relpath }, { text = true }):wait()

        local parent_content = (parent_res.code == 0 and parent_res.stdout) or "(file not in stash parent state)"
        local target_content = (target_res.code == 0 and target_res.stdout) or "(file not present in stash)"

        ctx.set_session_diff(
          parent_content,
          target_content,
          string.format("GitStash://%s^1/%s", stash.ref, ctx.relpath),
          string.format("GitStash://%s/%s", stash.ref, ctx.relpath)
        )
      end

      -- Action helpers
      local function apply_stash()
        local cursor = vim.api.nvim_win_get_cursor(ctx.log_win)
        local stash_idx = line_to_stash_idx[cursor[1]]
        if not stash_idx then return end
        local stash = stashes[stash_idx]

        local res = vim.system({ "git", "stash", "apply", stash.ref }, { text = true }):wait()
        if res.code == 0 then
          reload_buffer()
          vim.notify("Applied " .. stash.ref, vim.log.levels.INFO)
        else
          vim.notify("Failed to apply stash: " .. (res.stderr or ""), vim.log.levels.ERROR)
        end
      end

      local function pop_stash()
        local cursor = vim.api.nvim_win_get_cursor(ctx.log_win)
        local stash_idx = line_to_stash_idx[cursor[1]]
        if not stash_idx then return end
        local stash = stashes[stash_idx]

        local confirm = vim.fn.confirm("Pop " .. stash.ref .. " (" .. stash.message .. ")?", "&Yes\n&No", 2)
        if confirm ~= 1 then return end

        local res = vim.system({ "git", "stash", "pop", stash.ref }, { text = true }):wait()
        if res.code == 0 then
          reload_buffer()
          vim.notify("Popped " .. stash.ref, vim.log.levels.INFO)
          refresh_stash_list()
        else
          vim.notify("Failed to pop stash: " .. (res.stderr or ""), vim.log.levels.ERROR)
        end
      end

      local function drop_stash()
        local cursor = vim.api.nvim_win_get_cursor(ctx.log_win)
        local stash_idx = line_to_stash_idx[cursor[1]]
        if not stash_idx then return end
        local stash = stashes[stash_idx]

        local confirm = vim.fn.confirm("Permanently drop " .. stash.ref .. " (" .. stash.message .. ")?", "&Yes\n&No", 2)
        if confirm ~= 1 then return end

        local res = vim.system({ "git", "stash", "drop", stash.ref }, { text = true }):wait()
        if res.code == 0 then
          vim.notify("Dropped " .. stash.ref, vim.log.levels.INFO)
          refresh_stash_list()
        else
          vim.notify("Failed to drop stash: " .. (res.stderr or ""), vim.log.levels.ERROR)
        end
      end

      -- Store current changes into a new stash with user-editable message, reload buffer to HEAD, and refresh list
      local function store_stash()
        -- Warn if original file buffer has unsaved changes on disk
        if vim.api.nvim_buf_is_valid(ctx.orig_bufnr) and vim.bo[ctx.orig_bufnr].modified then
          local confirm = vim.fn.confirm("Buffer has unsaved changes on disk. Stash anyway?", "&Yes\n&No", 2)
          if confirm ~= 1 then return end
        end

        local default_msg = string.format("WIP on %s via GitStashBrowser", ctx.relpath)
        local stash_msg = vim.fn.input("Stash message: ", default_msg)
        if stash_msg == "" then
          vim.notify("Stash aborted", vim.log.levels.INFO)
          return
        end

        local res = vim.system({ "git", "stash", "push", "-m", stash_msg, "--", ctx.relpath }, { text = true }):wait()
        if res.code ~= 0 then
          vim.notify("Failed to stash changes: " .. (res.stderr or ""), vim.log.levels.ERROR)
          return
        end

        reload_buffer()
        vim.notify("Stashed changes and restored HEAD for " .. ctx.relpath, vim.log.levels.INFO)
        refresh_stash_list()
      end

      -- Keymaps in log window
      vim.keymap.set("n", "<CR>", inspect_selected_stash, { buffer = ctx.log_buf, silent = true, desc = "Inspect stash diff" })
      vim.keymap.set("n", "<Esc>", close_diff_preview, { buffer = ctx.log_buf, silent = true, desc = "Close diff preview panes" })
      vim.keymap.set("n", "a", apply_stash, { buffer = ctx.log_buf, silent = true, desc = "Apply stash" })
      vim.keymap.set("n", "p", pop_stash, { buffer = ctx.log_buf, silent = true, desc = "Pop stash" })
      vim.keymap.set("n", "d", drop_stash, { buffer = ctx.log_buf, silent = true, desc = "Drop stash" })
      vim.keymap.set("n", "s", store_stash, { buffer = ctx.log_buf, silent = true, desc = "Store (stash) current changes & reset to HEAD" })
      vim.keymap.set("n", "q", function()
        ctx.close()
        vim.notify("Git stash browser closed", vim.log.levels.INFO)
      end, { buffer = ctx.log_buf, silent = true, desc = "Close stash window" })
    end,
  })

  vim.api.nvim_create_user_command(M.config.stash_command, toggle_browser, {
    desc = "Open interactive 3-window git stash browser",
  })

  vim.keymap.set("n", "<leader>gS", ":" .. M.config.stash_command .. "<CR>", { silent = true, desc = "Open Git stash browser" })
end

return M
