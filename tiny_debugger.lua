-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

local MAX_BREAKPOINTS = 5

local client = nil
local exec_ns_id = vim.api.nvim_create_namespace("tiny_debugger_exec")
local bp_ns_id = vim.api.nvim_create_namespace("tiny_debugger_bp")
local read_buffer = ""
local write_queue = {}
local is_connecting = false
local breakpoints = {}
local verbose_mode = false

local function get_socket_path()
  return string.format("/dev/shm/tiny_debugger_%d.sock", vim.fn.getpid())
end

local function echo_cmd(msg, hl)
  vim.api.nvim_echo({ { msg, hl or "Normal" } }, false, {})
end

local function normalize_path(path)
  local resolved = vim.loop.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
  return vim.fs.normalize(resolved)
end

-- Get the absolute directory where tiny_debugger.lua physically lives
local function get_script_dir()
  local str = debug.getinfo(1, "S").source:sub(2)
  return normalize_path(vim.fn.fnamemodify(str, ":h"))
end

local function refresh_bp_signs(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cur_file = normalize_path(vim.api.nvim_buf_get_name(bufnr))
  vim.api.nvim_buf_clear_namespace(bufnr, bp_ns_id, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, bp in ipairs(breakpoints) do
    if normalize_path(bp.file) == cur_file and bp.line >= 1 and bp.line <= line_count then
      vim.api.nvim_buf_set_extmark(bufnr, bp_ns_id, bp.line - 1, 0, {
        sign_text = "●",
        sign_hl_group = "DiagnosticError",
        priority = 150, -- Higher than git signs (50) so breakpoints render on top
      })
    end
  end
end

local function ensure_connected(callback)
  if client ~= nil then
    local ok, closing = pcall(function() return client:is_closing() end)
    if ok and not closing then
      callback()
      return
    else
      client = nil
    end
  end

  if is_connecting then
    table.insert(write_queue, callback)
    return
  end

  is_connecting = true
  read_buffer = ""

  client = vim.loop.new_pipe(false)
  client:connect(get_socket_path(), function(err)
    is_connecting = false
    if err then
      write_queue = {}
      if client and not client:is_closing() then
        client:close()
      end
      client = nil
      vim.schedule(function()
        echo_cmd(
          string.format("[Debugger] Socket not ready — start target script first, nvim pid = %d",
          vim.fn.getpid()), "WarningMsg")
      end)
      return
    end

    client:read_start(function(read_err, chunk)
      assert(not read_err, read_err)
      if chunk then
        read_buffer = read_buffer .. chunk
        for line in read_buffer:gmatch("(.-)\n") do
          if line ~= "" then
            local ok, data = pcall(vim.json.decode, line)
            if ok then
              if data.event == "stopped" then
                vim.schedule(function()
                  local target_file = normalize_path(data.file)
                  local current_file = normalize_path(vim.api.nvim_buf_get_name(0))

                  if current_file ~= target_file then
                    vim.cmd("keepalt edit " .. vim.fn.fnameescape(target_file))
                  end

                  local line_count = vim.api.nvim_buf_line_count(0)
                  local safe_line = math.max(1, math.min(data.line, line_count))

                  vim.api.nvim_win_set_cursor(0, { safe_line, 0 })

                  for _, bp in ipairs(breakpoints) do
                    if normalize_path(bp.file) == target_file and bp.line == data.line then
                      bp.hits = (bp.hits or 0) + 1
                    end
                  end

                  local bufnr = vim.api.nvim_get_current_buf()
                  refresh_bp_signs(bufnr)
                  vim.api.nvim_buf_clear_namespace(bufnr, exec_ns_id, 0, -1)
                  vim.api.nvim_buf_set_extmark(bufnr, exec_ns_id, safe_line - 1, 0, {
                    line_hl_group = "Visual",
                  })

                  echo_cmd(string.format("[Debugger] Paused at line %d (Hit count: %d)", data.line, data.hits or 1), "MoreMsg")
                end)
              elseif data.event == "fatal_error" then
                vim.schedule(function()
                  local bufnr = vim.api.nvim_get_current_buf()
                  vim.api.nvim_buf_clear_namespace(bufnr, exec_ns_id, 0, -1)

                  vim.api.nvim_echo({
                    { "[Debugger Fatal Error] Script Location Mismatch Detected!\n", "ErrorMsg" },
                    { data.message, "WarningMsg" }
                  }, true, {})
                end)
                if client and not client:is_closing() then
                  client:close()
                end
                client = nil
              elseif data.event == "warning" then
                vim.schedule(function()
                  echo_cmd("[Debugger Warning]: " .. data.message, "WarningMsg")
                end)
              elseif data.event == "trace" then
                vim.schedule(function()
                  if verbose_mode then
                    echo_cmd(string.format("[Trace] %s:%d", vim.fn.fnamemodify(data.file, ":t"), data.line), "Comment")
                  end
                end)
              elseif data.event == "eval_result" then
                vim.schedule(function()
                  print(string.format("[Eval] %s = %s", data.expr, data.result))
                end)
              elseif data.event == "stack_result" then
                vim.schedule(function()
                  local lines = { "Call Stack (Top to Bottom):" }
                  for i, f in ipairs(data.stack) do
                    table.insert(lines, string.format("  [%d] %s() at %s:%d", i - 1, f.name, vim.fn.fnamemodify(f.file, ":t"), f.line))
                  end
                  print(table.concat(lines, "\n"))
                end)
              end
            end
          end
        end
        read_buffer = read_buffer:match("[^\n]*$") or ""
      else
        vim.schedule(function()
          local bufnr = vim.api.nvim_get_current_buf()
          vim.api.nvim_buf_clear_namespace(bufnr, exec_ns_id, 0, -1)
          echo_cmd("[Debugger] Program execution finished.", "Comment")
        end)
        if client and not client:is_closing() then
          client:close()
        end
        client = nil
      end
    end)

    vim.schedule(function()
      callback()
      for _, cb in ipairs(write_queue) do
        cb()
      end
      write_queue = {}
    end)
  end)
end

local function send_payload(payload_table)
  payload_table.nvim_script_dir = get_script_dir()
  local payload_str = vim.json.encode(payload_table)

  ensure_connected(function()
    if client and not client:is_closing() then
      client:write(payload_str .. "\n", function(err)
        if err then
          vim.schedule(function()
            echo_cmd("[Debugger] Write error: " .. tostring(err), "ErrorMsg")
          end)
          if client and not client:is_closing() then
            client:close()
          end
          client = nil
        end
      end)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(args)
      refresh_bp_signs(args.buf)
    end,
  })

  -- --- Action Handler Functions ---

  local function toggle_breakpoint()
    local file = normalize_path(vim.api.nvim_buf_get_name(0))
    local line = vim.api.nvim_win_get_cursor(0)[1]

    local found = false
    for i, bp in ipairs(breakpoints) do
      if normalize_path(bp.file) == file and bp.line == line then
        table.remove(breakpoints, i)
        found = true
        echo_cmd(string.format(":mb -> Breakpoint removed: %s:%d", vim.fn.fnamemodify(file, ":t"), line))
        break
      end
    end

    if not found then
      if #breakpoints >= MAX_BREAKPOINTS then
        echo_cmd(string.format(":mb -> Maximum %d breakpoints allowed.", MAX_BREAKPOINTS), "WarningMsg")
        return
      end
      table.insert(breakpoints, { file = file, line = line, hits = 0 })
      echo_cmd(string.format(":mb -> Breakpoint %d/%d set for %s:%d", #breakpoints, MAX_BREAKPOINTS, vim.fn.fnamemodify(file, ":t"), line), "MoreMsg")
    end

    refresh_bp_signs(0)
  end

  local function list_breakpoints()
    if #breakpoints == 0 then
      echo_cmd(":ml -> No breakpoints set.")
      return
    end
    local lines = { string.format("Current Breakpoints (%d/%d):", #breakpoints, MAX_BREAKPOINTS) }
    for i, bp in ipairs(breakpoints) do
      local hit_str = (bp.hits and bp.hits > 0) and string.format(" [Hit: %d times]", bp.hits) or " [Unreached]"
      table.insert(lines, string.format("  [%d] %s:%d%s", i, vim.fn.fnamemodify(bp.file, ":t"), bp.line, hit_str))
    end
    print(table.concat(lines, "\n"))
  end

  local function reset_breakpoints()
    breakpoints = {}
    refresh_bp_signs(0)
    local is_active = false
    if client ~= nil then
      local ok, closing = pcall(function() return client:is_closing() end)
      if ok and not closing then
        is_active = true
      end
    end

    if is_active then
      send_payload({ command = "reset_breakpoints", breakpoints = {} })
      echo_cmd(":mr -> All breakpoints reset (local and remote).")
    else
      echo_cmd(":mr -> All breakpoints reset locally.")
    end
  end

  local function quit_session()
    local is_active = false
    if client ~= nil then
      local ok, closing = pcall(function() return client:is_closing() end)
      if ok and not closing then
        is_active = true
      end
    end

    if not is_active then
      echo_cmd(":mq -> No active debug session found.")
      return
    end

    local choice = vim.fn.confirm("Terminate active debug session?", "&Yes\n&No", 2)
    if choice == 1 then
      send_payload({ command = "quit" })
      if client and not client:is_closing() then
        client:close()
      end
      client = nil
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_clear_namespace(bufnr, exec_ns_id, 0, -1)
      echo_cmd(":mq -> Debugger session terminated.")
    else
      echo_cmd(":mq -> Termination cancelled.")
    end
  end

  local function continue_execution()
    send_payload({
      command = "continue",
      breakpoints = breakpoints,
      verbose = verbose_mode,
    })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, exec_ns_id, 0, -1)
    echo_cmd(string.format(":mc -> Running (%d breakpoint(s)) [Verbose: %s]...", #breakpoints, tostring(verbose_mode)), "MoreMsg")
  end

  local function next_line()
    send_payload({ command = "next", verbose = verbose_mode })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, exec_ns_id, 0, -1)
    echo_cmd(":mn -> Next line")
  end

  local function step_into()
    send_payload({ command = "step", verbose = verbose_mode })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, exec_ns_id, 0, -1)
    echo_cmd(":mS -> Step into")
  end

  local function fetch_stack()
    send_payload({ command = "stack" })
    echo_cmd(":ms -> Fetching call stack...")
  end

  local function eval_cword()
    local cword = vim.fn.expand("<cword>")
    if cword == "" then
      echo_cmd(":mv -> No variable under cursor.", "WarningMsg")
      return
    end
    send_payload({ command = "eval:" .. cword })
    echo_cmd(":mv -> Evaluating variable: " .. cword)
  end

  local function eval_interactive()
    vim.ui.input({ prompt = "Evaluate Python expression: " }, function(input)
      if input and input ~= "" then
        send_payload({ command = "eval:" .. input })
        echo_cmd(":mi -> Evaluating: " .. input)
      end
    end)
  end

  local function toggle_verbose()
    verbose_mode = not verbose_mode
    echo_cmd(string.format(":mV -> Verbose tracing %s", verbose_mode and "ENABLED" or "DISABLED"), verbose_mode and "MoreMsg" or "Comment")
  end

  -- --- Register Uppercase User Commands ---

  vim.api.nvim_create_user_command("TinyBreakpoint", toggle_breakpoint, {})
  vim.api.nvim_create_user_command("TinyListBreakpoints", list_breakpoints, {})
  vim.api.nvim_create_user_command("TinyResetBreakpoints", reset_breakpoints, {})
  vim.api.nvim_create_user_command("TinyQuit", quit_session, {})
  vim.api.nvim_create_user_command("TinyContinue", continue_execution, {})
  vim.api.nvim_create_user_command("TinyNext", next_line, {})
  vim.api.nvim_create_user_command("TinyStep", step_into, {})
  vim.api.nvim_create_user_command("TinyStack", fetch_stack, {})
  vim.api.nvim_create_user_command("TinyEvalCword", eval_cword, {})
  vim.api.nvim_create_user_command("TinyEvalInput", eval_interactive, {})
  vim.api.nvim_create_user_command("TinyVerbose", toggle_verbose, {})

  -- --- Register Keymaps ---

  vim.keymap.set("n", "<leader>mb", toggle_breakpoint, { desc = "Debugger Toggle Breakpoint" })
  vim.keymap.set("n", "<leader>ml", list_breakpoints, { desc = "Debugger List Breakpoints" })
  vim.keymap.set("n", "<leader>mr", reset_breakpoints, { desc = "Debugger Reset Breakpoints" })
  vim.keymap.set("n", "<leader>mq", quit_session, { desc = "Debugger Quit Session" })
  vim.keymap.set("n", "<leader>mc", continue_execution, { desc = "Debugger Continue" })
  vim.keymap.set("n", "<leader>mn", next_line, { desc = "Debugger Next Line" })
  vim.keymap.set("n", "<leader>mS", step_into, { desc = "Debugger Step Into" })
  vim.keymap.set("n", "<leader>ms", fetch_stack, { desc = "Debugger Fetch Stack" })
  vim.keymap.set("n", "<leader>mv", eval_cword, { desc = "Debugger Eval Cword" })
  vim.keymap.set("n", "<leader>mi", eval_interactive, { desc = "Debugger Interactive Eval" })
  vim.keymap.set("n", "<leader>mV", toggle_verbose, { desc = "Debugger Toggle Verbose Mode" })
end

return M
