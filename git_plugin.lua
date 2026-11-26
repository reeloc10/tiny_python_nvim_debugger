-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- Native 2-column git sign indicator, inline word-level diff tracking,
-- hunk navigation ([c / ]c), and in-memory read-only vimdiff vertical split toggle.

local M = {}

-- Default configuration options (starts enabled by default)
M.config = {
  enabled = true,
  diff_command = "GitSignsDiff",
  base_ref = "HEAD",
}

local common = require("common")
-- Then use common.get_repo_rel_path(filepath) and common.cloned_folder

function M.setup(opts)
  -- Merge user configuration overrides with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local ns_col1 = vim.api.nvim_create_namespace("native_git_signs_col1")
  local ns_col2 = vim.api.nvim_create_namespace("native_git_signs_col2")
  local debug_log_path = string.format("/dev/shm/git_plugin_debug_%d.log", vim.fn.getpid())

  -- Cache detected hunk target lines per buffer for ]c / [c navigation
  -- [bufnr] = { line_num1, line_num2, ... } sorted ascending
  local hunk_cache = {}

  local diff_win = nil
  local diff_buf = nil

  -- Overwrite debug log file with fresh session trace
  local function log_debug(fmt, ...)
    local f = io.open(debug_log_path, "w")
    if f then
      f:write(string.format("[%s] " .. fmt .. "\n", os.date("%H:%M:%S"), ...))
      f:close()
    end
  end

  -- Append debug traces to log file for review
  local function log_append(fmt, ...)
    local f = io.open(debug_log_path, "a")
    if f then
      f:write(string.format("[%s] " .. fmt .. "\n", os.date("%H:%M:%S"), ...))
      f:close()
    end
  end

  -- Helper to check if a file exists in git HEAD
  local function is_tracked_in_head(filepath)
    local relpath = common.get_repo_rel_path(filepath)
    if not relpath then return false end
    local res = vim.system({ "git", "cat-file", "-e", "HEAD:" .. relpath }, { text = true }):wait()
    return res.code == 0
  end

  -- Helper to fetch recent git commits with hash and subject descriptions from HEAD
  local function fetch_git_commits(limit)
    limit = limit or 30
    local res = vim.system({
      "git", "log", "--format=%h %s", "-n", tostring(limit)
    }, { text = true }):wait()

    local items = {}
    if res.code == 0 and res.stdout then
      for line in res.stdout:gmatch("[^\r\n]+") do
        table.insert(items, line)
      end
    end
    return items
  end

  -- Disable plugin safely and notify user on unrecoverable environment errors
  local function fatal_error_exit(err_msg, target_bufnr)
    M.config.enabled = false
    log_append("%s", err_msg)
    vim.schedule(function()
      vim.fn.confirm("GitSigns Error:\n" .. err_msg, "&OK")
      local b = target_bufnr or vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_clear_namespace(b, ns_col1, 0, -1)
        vim.api.nvim_buf_clear_namespace(b, ns_col2, 0, -1)
        hunk_cache[b] = nil
      end
    end)
  end

  -- Set up highlight groups for native gutter signs and inline word diffs
  vim.api.nvim_set_hl(0, "GitSignsAdd",          { fg = "#2ecc71", default = true })
  vim.api.nvim_set_hl(0, "GitSignsDelete",       { fg = "#e74c3c", default = true })
  vim.api.nvim_set_hl(0, "GitSignsChange",       { fg = "#f1c40f", default = true })
  vim.api.nvim_set_hl(0, "GitSignsWordAdd",      { fg = "#2ecc71", underline = true, default = true })
  vim.api.nvim_set_hl(0, "GitSignsWordChange",   { fg = "#f1c40f", underline = true, default = true })

  -- Helper to split a string into distinct whitespace-separated words with column positions
  local function get_words(str)
    local words = {}
    for start_pos, word in str:gmatch("()(%S+)") do
      local pos = tonumber(start_pos)
      if pos and type(word) == "string" then
        table.insert(words, {
          text = word,
          start = pos - 1,
          finish = pos - 1 + #word
        })
      end
    end
    return words
  end

  -- Main function to evaluate git status and render gutter signs + cache hunks
  local function update_git_signs()
    if not M.config.enabled then return end

    local bufnr = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local file = vim.api.nvim_buf_get_name(bufnr)

    -- Skip sign updates on our in-memory GitDiffRef scratch buffer
    if type(file) == "string" and file:match("GitDiffRef://") then return end

    if type(file) ~= "string" or file == "" then
      return
    end

    local ok, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
    if not ok or type(buftype) ~= "string" or buftype ~= "" then
      return
    end

    -- Force signcolumn to 2 columns to prevent layout jitter
    vim.opt_local.signcolumn = "yes:2"
    vim.api.nvim_buf_clear_namespace(bufnr, ns_col1, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_col2, 0, -1)
    hunk_cache[bufnr] = nil

    -- Extract repo-relative path for git execution
    local relpath = common.get_repo_rel_path(file)
    -- Untracked or not in repo yet; skip signs cleanly without fatal exit
    if not relpath then return end

    -- Execute git show to fetch HEAD revision content asynchronously
    local cmd_args = { "git", "show", "HEAD:" .. relpath, "--" }
    log_append("Executing direct system call (argv array, no shell): %s", table.concat(cmd_args, " "))

    vim.system(cmd_args, { text = true }, function(show_obj)
      if type(show_obj) ~= "table" or show_obj.code ~= 0 then
        -- Skip sign updates if file does not exist in HEAD yet (new untracked files)
        return
      end

      vim.schedule(function()
        if not M.config.enabled then return end
        if not vim.api.nvim_buf_is_valid(bufnr) then return end

        vim.api.nvim_buf_clear_namespace(bufnr, ns_col1, 0, -1)
        vim.api.nvim_buf_clear_namespace(bufnr, ns_col2, 0, -1)

        local old_text = show_obj.stdout
        local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local line_count = #current_lines
        if line_count == 0 then return end

        local new_text = table.concat(current_lines, "\n") .. "\n"
        if type(old_text) ~= "string" or type(new_text) ~= "string" then return end

        -- Fetch precise hunk indices using Neovim's native histogram diff engine
        local hunks = vim.diff(old_text, new_text, {
          result_type = "indices",
          algorithm = "histogram",
        })

        if not hunks then return end

        log_append("================ NEW INDICES EVALUATION for %s ================", relpath)
        log_append("Total hunks detected: %d", #hunks)

        local old_lines = vim.split(old_text, "\n", { plain = true })
        if #old_lines > 0 and old_lines[#old_lines] == "" then
          table.remove(old_lines)
        end

        local line_signs = {}
        local detected_hunks = {}

        -- Iterate through exact hunk indices provided by the C backend
        for _, hunk in ipairs(hunks) do
          local start_a, count_a, start_b, count_b = hunk[1], hunk[2], hunk[3], hunk[4]
          log_append("Hunk: start_a=%d, count_a=%d, start_b=%d, count_b=%d", start_a, count_a, start_b, count_b)

          -- Push only the starting line of each hunk for whole-hunk navigation
          local hunk_line = math.max(1, start_b)
          if hunk_line <= line_count then
            table.insert(detected_hunks, hunk_line)
          end

          if count_a == 0 and count_b > 0 then
            -- Pure Addition
            for i = 0, count_b - 1 do
              local target_line = (start_b - 1) + i
              if target_line >= 0 and target_line < line_count then
                line_signs[target_line] = { col1 = "+", col2 = "" }
              end
            end
          elseif count_a > 0 and count_b == 0 then
            -- Pure Deletion
            local target_line = math.min(line_count - 1, math.max(0, start_b - 1))
            if not line_signs[target_line] then
              line_signs[target_line] = { col1 = "", col2 = "" }
            end
            local existing = (line_signs[target_line].col2 ~= "" and tonumber(line_signs[target_line].col2)) or 0
            local new_cnt = existing + count_a
            line_signs[target_line].col2 = new_cnt > 9 and "9" or tostring(new_cnt)
          else
            -- Modification Hunk: Mark replacement lines as changed (~)
            for i = 0, count_b - 1 do
              local target_line = (start_b - 1) + i
              if target_line >= 0 and target_line < line_count then
                line_signs[target_line] = { col1 = "~", col2 = "" }

                -- Inline word-level diff tracking against corresponding old line if available
                local old_line_idx = start_a + math.min(i, count_a - 1)
                local old_line_text = old_lines[old_line_idx] or ""
                local line_lines = vim.api.nvim_buf_get_lines(bufnr, target_line, target_line + 1, false)
                local line_text = line_lines[1] or ""
                local line_len = #line_text

                local old_words = get_words(old_line_text)
                local new_words = get_words(line_text)

                for _, nword in ipairs(new_words) do
                  local found = false
                  for _, oword in ipairs(old_words) do
                    if nword.text == oword.text then
                      found = true
                      break
                    end
                  end
                  if not found and nword.start < line_len then
                    local safe_end = math.min(nword.finish, line_len)
                    vim.api.nvim_buf_set_extmark(bufnr, ns_col1, target_line, nword.start, {
                      end_col = safe_end,
                      hl_group = "GitSignsWordChange",
                      priority = 50,
                    })
                  end
                end
              end
            end

            -- Handle excess deleted lines if replacement reduced total line count
            if count_a > count_b then
              local excess_del = count_a - count_b
              local target_line = math.min(line_count - 1, math.max(0, (start_b - 1) + count_b - 1))
              if not line_signs[target_line] then
                line_signs[target_line] = { col1 = "~", col2 = "" }
              end
              local existing = (line_signs[target_line].col2 ~= "" and tonumber(line_signs[target_line].col2)) or 0
              local new_cnt = existing + excess_del
              line_signs[target_line].col2 = new_cnt > 9 and "9" or tostring(new_cnt)
            end
          end
        end

        -- Deduplicate and sort hunk line numbers ascending
        table.sort(detected_hunks)
        local unique_hunks = {}
        local last_l = nil
        for _, l in ipairs(detected_hunks) do
          if l ~= last_l then
            table.insert(unique_hunks, l)
            last_l = l
          end
        end
        hunk_cache[bufnr] = unique_hunks

        -- Render gutter signs into respective namespaces without gutter jitter
        for lnum = 0, line_count - 1 do
          local s = line_signs[lnum]
          if s then
            if s.col1 ~= "" then
              local hl1 = (s.col1 == "~") and "GitSignsChange" or "GitSignsAdd"
              vim.api.nvim_buf_set_extmark(bufnr, ns_col1, lnum, 0, {
                sign_text = s.col1,
                sign_hl_group = hl1,
                priority = 50,
              })
            end

            if s.col2 ~= "" then
              vim.api.nvim_buf_set_extmark(bufnr, ns_col2, lnum, 0, {
                sign_text = s.col2,
                sign_hl_group = "GitSignsDelete",
                priority = 50,
              })
            end
          end
        end
      end)
    end)
  end

  -- Hunk navigation helper: jump to next/previous hunk with wrap-around
  local function navigate_hunk(direction)
    local bufnr = vim.api.nvim_get_current_buf()
    local hunks = hunk_cache[bufnr]
    if not hunks or #hunks == 0 then
      print("[GitSigns] No changes/hunks in buffer.")
      return
    end

    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local target_line = nil

    if direction == "next" then
      for _, lnum in ipairs(hunks) do
        if lnum > current_line then
          target_line = lnum
          break
        end
      end
      -- Wrap around to first hunk
      if not target_line then
        target_line = hunks[1]
      end
    else
      for i = #hunks, 1, -1 do
        local lnum = hunks[i]
        if lnum < current_line then
          target_line = lnum
          break
        end
      end
      -- Wrap around to last hunk
      if not target_line then
        target_line = hunks[#hunks]
      end
    end

    if target_line then
      vim.api.nvim_win_set_cursor(0, { target_line, 0 })
      vim.cmd("normal! zz")
      -- Find index for status message
      local idx = 1
      for i, l in ipairs(hunks) do
        if l == target_line then idx = i break end
      end
      print(string.format("[Hunk %d/%d] Line %d", idx, #hunks, target_line))
    end
  end

  vim.api.nvim_create_user_command("GitSignsToggle", function()
    M.config.enabled = not M.config.enabled
    print("Native Git Signs enabled: " .. tostring(M.config.enabled))
    if M.config.enabled then
      update_git_signs()
    else
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns_col1, 0, -1)
        vim.api.nvim_buf_clear_namespace(bufnr, ns_col2, 0, -1)
        hunk_cache[bufnr] = nil
      end
    end
  end, {})

  -- Hunk keymaps ([c and ]c)
  vim.keymap.set("n", "]c", function() navigate_hunk("next") end, { silent = true, desc = "Next git hunk" })
  vim.keymap.set("n", "[c", function() navigate_hunk("previous") end, { silent = true, desc = "Previous git hunk" })

  -- Core inner function to handle vertical split vimdiff view with explicit target ref and force state
  local function diff_command_inner(target_ref, force_state)
    target_ref = (target_ref and target_ref ~= "") and target_ref or M.config.base_ref

    -- If diff window is already open and valid
    if diff_win and vim.api.nvim_win_is_valid(diff_win) then
      if force_state == true then
        return
      end
      if force_state == false or (force_state == nil and target_ref == M.config.base_ref) then
        vim.cmd("diffoff!")
        vim.api.nvim_win_close(diff_win, true)
        if diff_buf and vim.api.nvim_buf_is_valid(diff_buf) then
          vim.api.nvim_buf_delete(diff_buf, { force = true })
        end
        diff_win = nil
        diff_buf = nil
        print("[tiny_debugger] Closed vimdiff split view")
        log_append("Closed vimdiff split view")
        return
      end
      -- Close old diff window before opening a different ref
      vim.cmd("diffoff!")
      vim.api.nvim_win_close(diff_win, true)
      if diff_buf and vim.api.nvim_buf_is_valid(diff_buf) then
        vim.api.nvim_buf_delete(diff_buf, { force = true })
      end
      diff_win = nil
      diff_buf = nil
    elseif force_state == false then
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(bufnr)
    if type(file) ~= "string" or file == "" then
      print("[tiny_debugger] Error: Active buffer has no valid filename.")
      return
    end

    local relpath = common.get_repo_rel_path(file)
    if not relpath then
      print("[tiny_debugger] Error: File is not tracked in git repository.")
      return
    end

    local cmd_output = vim.system({ "git", "show", target_ref .. ":" .. relpath }, { text = true }):wait()
    if cmd_output.code ~= 0 then
      local err_str = string.format("[tiny_debugger] Failed to fetch %s revision for vimdiff: %s", target_ref, (cmd_output.stderr or ""))
      print(err_str)
      log_append("%s", err_str)
      return
    end

    -- Clean up any leftover scratch buffer with the same name before creating a fresh one
    local target_buf_name = string.format("GitDiffRef://%s/%s", target_ref, relpath)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("GitDiffRef://") then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end

    -- Create an anonymous memory buffer (no disk I/O, purely in-memory scratch buffer)
    diff_buf = vim.api.nvim_create_buf(false, true)
    if not diff_buf or not vim.api.nvim_buf_is_valid(diff_buf) then
      print("[tiny_debugger] Failed to create in-memory buffer.")
      return
    end

    -- Set unique buffer name for statusline identification
    vim.api.nvim_buf_set_name(diff_buf, target_buf_name)

    -- Populate memory buffer lines from git show output
    local lines = vim.split(cmd_output.stdout or "", "\n", { plain = true })
    if #lines > 0 and lines[#lines] == "" then
      table.remove(lines)
    end
    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, lines)

    -- Enforce strict read-only restrictions on the base scratch buffer
    vim.bo[diff_buf].readonly = true
    vim.bo[diff_buf].modifiable = false
    vim.bo[diff_buf].buftype = "nofile"
    vim.bo[diff_buf].swapfile = false

    -- Open the in-memory buffer in a vertical split on the left
    vim.cmd("vsplit")
    diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(diff_win, diff_buf)
    -- Enable native diff mode on the base memory buffer
    vim.cmd("diffthis")

    -- Move back to original buffer, enable diff mode, and sync folding/scroll
    vim.cmd("wincmd p")
    vim.cmd("diffthis")

    print(string.format("[tiny_debugger] Switched to vimdiff view (Base: %s)", target_ref))
    log_append("Switched to vimdiff view (Base: %s)", target_ref)
  end

  -- Expose inner function on module table for programmatic calls
  M.diff = diff_command_inner

  -- Interactive picker using vim.ui.select to choose a base commit hash/ref with descriptions
  local function select_base_and_diff()
    local items = fetch_git_commits(30)
    if #items == 0 then
      print("[tiny_debugger] No git commits found.")
      return
    end

    vim.ui.select(items, {
      prompt = "Select Base Commit for Diff:",
      format_item = function(item)
        return item
      end,
    }, function(choice)
      if not choice then return end
      local hash = choice:match("^(%S+)")
      if hash then
        print(string.format("[tiny_debugger] Selected base hash: %s", hash))
        diff_command_inner(hash, true)
      end
    end)
  end

  -- Expose select helper on module table
  M.select_diff = select_base_and_diff

  -- User command wrapper for CLI / keymap usage with completion including abbreviations
  vim.api.nvim_create_user_command(M.config.diff_command, function(opts)
    local args = {}
    if opts.args and opts.args ~= "" then
      for word in opts.args:gmatch("%S+") do
        table.insert(args, word)
      end
    end

    local target_ref = args[1]
    local force_state = nil
    if args[2] == "true" then
      force_state = true
    elseif args[2] == "false" then
      force_state = false
    elseif args[1] == "true" then
      target_ref = nil
      force_state = true
    elseif args[1] == "false" then
      target_ref = nil
      force_state = false
    end

    diff_command_inner(target_ref, force_state)
  end, {
    nargs = "*",
    complete = function(lead)
      local candidates = fetch_git_commits(30)
      local matches = {}
      for _, c in ipairs(candidates) do
        if c:find(lead, 1, true) == 1 then
          table.insert(matches, c)
        end
      end
      return matches
    end
  })

  -- User command to manually force a debug inspection trace dump (:GitSignsInspect)
  vim.api.nvim_create_user_command("GitSignsInspect", function()
    update_git_signs()
    print("GitSigns inspect log written to " .. debug_log_path)
  end, {})

  -- Automatic event triggers to refresh signs on buffer events, text changes, and saves
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained", "TextChanged", "TextChangedI" }, {
    callback = update_git_signs,
  })

  -- Command :GitResetFile to revert current file to HEAD with safety prompt
  vim.api.nvim_create_user_command('GitResetFile', function()
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return end

    -- Print a clean red warning message in the command area using ErrorMsg highlight
    vim.api.nvim_echo({
      { "Revert file to HEAD and reload? [y/N] (Default: Keep changes): ", "ErrorMsg" }
    }, false, {})

    -- Get user input
    local ok, input = pcall(vim.fn.input, "")
    if not ok or input:lower() ~= "y" and input:lower() ~= "yes" then
      print("\nReset cancelled. Keeping changes.")
      return
    end

    -- Revert file on disk to HEAD, then force-reload buffer
    local relpath = common.get_repo_rel_path(filepath) or filepath
    vim.fn.system({ "git", "checkout", "HEAD", "--", relpath })
    vim.cmd("edit!")
    print("\nReverted to HEAD and reloaded.")
  end, {})

  -- Command :GitCommitVerbose with safe tracking check and split commit view
  vim.api.nvim_create_user_command('GitCommitVerbose', function()
    local orig_bufnr = vim.api.nvim_get_current_buf()

    -- Check for unsaved modifications
    if vim.bo[orig_bufnr].modified then
      vim.notify("Buffer has unsaved changes. Save file before committing.", vim.log.levels.WARN)
      return
    end

    local file = vim.api.nvim_buf_get_name(orig_bufnr)
    if file == "" then
      vim.notify("Buffer has no file on disk", vim.log.levels.WARN)
      return
    end

    -- 1. Stage the current file safely using repo-relative path
    local relpath = common.get_repo_rel_path(file) or file
    vim.fn.system({ "git", "add", "--", relpath })
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({ { "Failed to stage file with git add.", "ErrorMsg" } }, false, {})
      return
    end

    -- 2. Ensure GitSignsDiff is forced ON in vertical split if tracked in HEAD; otherwise notify
    if is_tracked_in_head(file) then
      diff_command_inner(nil, true)
    else
      print("New untracked file staged for commit.")
    end

    -- 3. Open terminal split below for git commit -v
    vim.cmd('botright 15split | terminal git commit -v')
    vim.cmd('startinsert')
  end, {})

end

return M
