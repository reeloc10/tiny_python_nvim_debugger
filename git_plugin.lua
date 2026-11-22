-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- Native 2-column git sign indicator and inline word-level diff tracking using Neovim API.
-- Implemented with clean, compact glyph extmarks for maximum compatibility and zero gutter jitter.

local M = {}

-- Default configuration options (starts enabled by default)
M.config = {
  enabled = true,
  diff_command = "GitSignsDiff",
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local ns_col1 = vim.api.nvim_create_namespace("native_git_signs_col1")
  local ns_col2 = vim.api.nvim_create_namespace("native_git_signs_col2")
  local debug_log_path = string.format("/dev/shm/git_plugin_debug_%d.log", vim.fn.getpid())

  -- Track active vimdiff split state
  local diff_win = nil
  local diff_buf = nil

  local function log_debug(fmt, ...)
    local f = io.open(debug_log_path, "w")
    if f then
      f:write(string.format("[%s] " .. fmt .. "\n", os.date("%H:%M:%S"), ...))
      f:close()
    end
  end

  local function log_append(fmt, ...)
    local f = io.open(debug_log_path, "a")
    if f then
      f:write(string.format("[%s] " .. fmt .. "\n", os.date("%H:%M:%S"), ...))
      f:close()
    end
  end

  local function fatal_error_exit(err_msg, target_bufnr)
    M.config.enabled = false
    log_append("%s", err_msg)
    vim.schedule(function()
      vim.fn.confirm("GitSigns Error:\n" .. err_msg, "&OK")
      local b = target_bufnr or vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_clear_namespace(b, ns_col1, 0, -1)
        vim.api.nvim_buf_clear_namespace(b, ns_col2, 0, -1)
      end
    end)
  end

  vim.api.nvim_set_hl(0, "GitSignsAdd",          { fg = "#2ecc71", default = true })
  vim.api.nvim_set_hl(0, "GitSignsDelete",       { fg = "#e74c3c", default = true })
  vim.api.nvim_set_hl(0, "GitSignsChange",       { fg = "#f1c40f", default = true })
  vim.api.nvim_set_hl(0, "GitSignsWordAdd",      { fg = "#2ecc71", underline = true, default = true })
  vim.api.nvim_set_hl(0, "GitSignsWordChange",   { fg = "#f1c40f", underline = true, default = true })

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

  local function update_git_signs()
    if not M.config.enabled then return end

    local bufnr = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local file = vim.api.nvim_buf_get_name(bufnr)

    -- Skip sign updates on our in-memory GitDiffHEAD scratch buffer
    if type(file) == "string" and file:match("GitDiffHEAD://") then return end

    if type(file) ~= "string" or file == "" then
      fatal_error_exit("Bad filename — Disabling plugin.", bufnr)
      return
    end

    local ok, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
    if not ok or type(buftype) ~= "string" or buftype ~= "" then
      fatal_error_exit("Invalid buffer type (" .. tostring(buftype) .. ") — Disabling plugin.", bufnr)
      return
    end

    vim.opt_local.signcolumn = "yes:2"
    vim.api.nvim_buf_clear_namespace(bufnr, ns_col1, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_col2, 0, -1)

    -- Let Git handle path resolution natively using ./ relative specifier
    local filename = vim.fn.fnamemodify(file, ":t")
    if filename == "" then
      fatal_error_exit("Empty filename resolved — Disabling plugin.", bufnr)
      return
    end

    local cmd_args = { "git", "show", "HEAD:./" .. filename, "--" }
    log_debug("Executing direct system call (argv array, no shell): %s", table.concat(cmd_args, " "))

    vim.system(cmd_args, { text = true }, function(show_obj)
      if type(show_obj) ~= "table" or show_obj.code ~= 0 then
        local raw_err = (show_obj and show_obj.stderr or ""):gsub("%s+$", "")
        local code_str = tostring(show_obj and show_obj.code or -1)
        local err_msg = string.format("Git command failed (code %s): %s — Disabling plugin.", code_str, raw_err)
        fatal_error_exit(err_msg, bufnr)
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

        local diff_str = vim.diff(old_text, new_text, { result_type = "unified" })
        if not diff_str or type(diff_str) ~= "string" then return end

        log_append("================ NEW DIFF EVALUATION for %s ================", filename)
        log_append("RAW DIFF OUTPUT:\n%s", diff_str)

        local current_old_line = 0
        local current_new_line = 0
        local current_hunk_new_start = 1
        local all_deletes = {}
        local all_adds = {}

        for line in diff_str:gmatch("[^\r\n]+") do
          if line:match("^@@") then
            local o_start, n_start = line:match("^@@ %-(%d+),?%d* %+(%d+)")
            if o_start and n_start then
              current_old_line = tonumber(o_start)
              current_new_line = tonumber(n_start)
              current_hunk_new_start = tonumber(n_start)
            end
          elseif line:sub(1, 1) == " " then
            current_old_line = current_old_line + 1
            current_new_line = current_new_line + 1
          elseif line:sub(1, 1) == "-" then
            table.insert(all_deletes, {
              text = line:sub(2),
              old_lnum = current_old_line,
              hunk_new_start = current_hunk_new_start
            })
            current_old_line = current_old_line + 1
          elseif line:sub(1, 1) == "+" then
            table.insert(all_adds, { lnum = current_new_line - 1, text = line:sub(2) })
            current_new_line = current_new_line + 1
          end
        end

        log_append("Collected global deletes: %d, adds: %d", #all_deletes, #all_adds)

        local function get_shared_count(s1, s2)
          local w1 = get_words(s1)
          local w2 = get_words(s2)
          local set = {}
          for _, w in ipairs(w1) do set[w.text] = true end
          local count = 0
          for _, w in ipairs(w2) do
            if set[w.text] then count = count + 1 end
          end
          return count
        end

        local consumed_deletes = {}
        local line_signs = {}

        for _, add_item in ipairs(all_adds) do
          local target_line = add_item.lnum
          if target_line >= 0 and target_line < line_count then
            local line_lines = vim.api.nvim_buf_get_lines(bufnr, target_line, target_line + 1, false)
            local line_text = line_lines[1] or ""
            local line_len = #line_text

            local best_del_idx = nil
            local max_score = -9999

            for d_idx, del_item in ipairs(all_deletes) do
              local overlap = get_shared_count(add_item.text, del_item.text)
              local line_distance = math.abs((target_line + 1) - del_item.old_lnum)

              local score = (overlap * 20) - line_distance
              if overlap > 0 and score > max_score then
                max_score = score
                best_del_idx = d_idx
              end
            end

            local best_del = best_del_idx and all_deletes[best_del_idx] or nil
            if not line_signs[target_line] then
              line_signs[target_line] = { col1 = "", col2 = "" }
            end
            local s = line_signs[target_line]

            if best_del and get_shared_count(add_item.text, best_del.text) >= 2 then
              consumed_deletes[best_del_idx] = true
              s.col1 = "~"
              log_append("Independent match: ADD line %d matched with DEL old_lnum=%d (~)", target_line + 1, best_del.old_lnum)

              local old_words = get_words(best_del.text)
              local new_words = get_words(add_item.text)

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
            else
              s.col1 = "+"
            end
          end
        end

        local unconsumed_groups = {}
        for d_idx, del_item in ipairs(all_deletes) do
          if not consumed_deletes[d_idx] then
            -- Anchor unconsumed deletes just before the hunk (0-indexed) to prevent column collision
            local target_line = del_item.hunk_new_start - 2
            target_line = math.min(line_count - 1, math.max(0, target_line))

            unconsumed_groups[target_line] = (unconsumed_groups[target_line] or 0) + 1
            log_append("Unconsumed DEL at old_lnum=%d anchored to target_line=%d", del_item.old_lnum, target_line + 1)
          end
        end

        for target_line, count in pairs(unconsumed_groups) do
          if not line_signs[target_line] then
            line_signs[target_line] = { col1 = "", col2 = "" }
          end
          local s = line_signs[target_line]
          local existing = (s.col2 ~= "" and tonumber(s.col2)) or 0
          local new_cnt = existing + count
          s.col2 = new_cnt > 9 and "9" or tostring(new_cnt)
        end

        log_append("FINAL LINE SIGNS MAPPING:")
        for lnum, s in pairs(line_signs) do
          log_append("  line %d (1-idx: %d): col1='%s', col2='%s'", lnum, lnum + 1, s.col1, s.col2)
        end

        -- Render clean compact signs without forced padding overhead
        log_append("--- EXTMARK RENDERING INSPECTION ---")
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
              log_append("  [Col1 Sign] line=%d (1-idx: %d) text='%s'", lnum, lnum + 1, s.col1)
            end

            if s.col2 ~= "" then
              vim.api.nvim_buf_set_extmark(bufnr, ns_col2, lnum, 0, {
                sign_text = s.col2,
                sign_hl_group = "GitSignsDelete",
                priority = 50,
              })
              log_append("  [Col2 Sign] line=%d (1-idx: %d) text='%s'", lnum, lnum + 1, s.col2)
            end
          end
        end

        -- Inspect final active extmarks across all namespaces
        local all_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })
        log_append("Total buffer extmarks active: %d", #all_extmarks)
        for _, em in ipairs(all_extmarks) do
          local id, row, col, details = em[1], em[2], em[3], em[4]
          if details.sign_text then
            log_append("  [Active Extmark] ns=%d line=%d (1-idx: %d) text='%s' priority=%d",
              details.ns_id, row, row + 1, details.sign_text, details.priority or 0)
          end
        end
      end)
    end)
  end

  -- User command to toggle plugin on/off
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
      end
    end
  end, {})

  -- User command to toggle read-only in-memory vimdiff split view against HEAD
  vim.api.nvim_create_user_command(M.config.diff_command, function()
    -- If diff window is already open and valid, tear it down
    if diff_win and vim.api.nvim_win_is_valid(diff_win) then
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

    local bufnr = vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(bufnr)
    if type(file) ~= "string" or file == "" then
      print("[tiny_debugger] Error: Active buffer has no valid filename.")
      return
    end

    local filename = vim.fn.fnamemodify(file, ":t")
    local cmd_output = vim.system({ "git", "show", "HEAD:./" .. filename }, { text = true }):wait()
    if cmd_output.code ~= 0 then
      local err_str = "[tiny_debugger] Failed to fetch HEAD revision for vimdiff: " .. (cmd_output.stderr or "")
      print(err_str)
      log_append("%s", err_str)
      return
    end

    -- Clean up any leftover scratch buffer with the same name before creating a fresh one
    local target_buf_name = "GitDiffHEAD://" .. filename
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("GitDiffHEAD://") then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end

    -- Create an anonymous memory buffer (no disk I/O, purely in-memory scratch buffer)
    diff_buf = vim.api.nvim_create_buf(false, true)
    if not diff_buf or not vim.api.nvim_buf_is_valid(diff_buf) then
      print("[tiny_debugger] Failed to create in-memory buffer.")
      return
    end

    -- Set buffer name for clarity in statusline
    vim.api.nvim_buf_set_name(diff_buf, target_buf_name)

    -- Populate memory buffer lines from git show output
    local lines = vim.split(cmd_output.stdout or "", "\n", { plain = true })
    if #lines > 0 and lines[#lines] == "" then
      table.remove(lines)
    end
    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, lines)

    -- Enforce strict read-only restrictions on the base buffer
    vim.bo[diff_buf].readonly = true
    vim.bo[diff_buf].modifiable = false
    vim.bo[diff_buf].buftype = "nofile"
    vim.bo[diff_buf].swapfile = false

    -- Open the in-memory buffer in a vertical split on the left
    vim.cmd("vsplit")
    diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(diff_win, diff_buf)

    -- Enable diff mode on the base memory buffer
    vim.cmd("diffthis")

    -- Move back to original buffer, enable diff mode, and sync folding/scroll
    vim.cmd("wincmd p")
    vim.cmd("diffthis")

    print("[tiny_debugger] Switched to vimdiff view (In-Memory HEAD base)")
    log_append("Switched to vimdiff view (In-Memory HEAD base)")
  end, {})

  -- User command to manually force a debug inspection trace dump (:GitSignsInspect)
  vim.api.nvim_create_user_command("GitSignsInspect", function()
    update_git_signs()
    print("GitSigns inspect log written to " .. debug_log_path)
  end, {})

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
    callback = update_git_signs,
  })
end

return M
