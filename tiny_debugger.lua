-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

local MAX_BREAKPOINTS = 5

local client = nil
local ns_id = vim.api.nvim_create_namespace("tiny_debugger")
local read_buffer = ""
local write_queue = {}
local is_connecting = false
local breakpoints = {}

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
  client:connect("/dev/shm/tiny_debugger.sock", function(err)
    is_connecting = false
    if err then
      write_queue = {}
      if client and not client:is_closing() then
        client:close()
      end
      client = nil
      print("Please run target on a different command prompt")
      return
    end
    print("Connected to RAM socket in /dev/shm.")

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
                  local target_file = vim.fs.normalize(vim.fn.fnamemodify(data.file, ":p"))
                  local current_file = vim.fs.normalize(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p"))

                  if current_file ~= target_file then
                    vim.cmd("keepalt edit " .. vim.fn.fnameescape(target_file))
                  end

                  local line_count = vim.api.nvim_buf_line_count(0)
                  local safe_line = math.max(1, math.min(data.line, line_count))

                  vim.api.nvim_win_set_cursor(0, {safe_line, 0})

                  for _, bp in ipairs(breakpoints) do
                    local bp_path = vim.fs.normalize(vim.fn.fnamemodify(bp.file, ":p"))
                    if bp_path == target_file and bp.line == data.line then
                      bp.hits = (bp.hits or 0) + 1
                    end
                  end

                  local bufnr = vim.api.nvim_get_current_buf()
                  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
                  vim.api.nvim_buf_set_extmark(bufnr, ns_id, safe_line - 1, 0, {
                    line_hl_group = "Visual",
                  })

                  print(string.format("Paused at line %d (Hit count: %d)", data.line, data.hits or 1))
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
          print("Program execution finished.")
        end)
        if client and not client:is_closing() then
          client:close()
        end
        client = nil
      end
    end)

    callback()
    for _, cb in ipairs(write_queue) do
      cb()
    end
    write_queue = {}
  end)
end

local function send_payload(payload_str)
  ensure_connected(function()
    if client and not client:is_closing() then
      client:write(payload_str .. "\n", function(err)
        if err then
          print("Write error: " .. tostring(err))
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
  vim.keymap.set("n", "<leader>mb", function()
    local file = vim.api.nvim_buf_get_name(0)
    local line = vim.api.nvim_win_get_cursor(0)[1]

    local found = false
    for i, bp in ipairs(breakpoints) do
      if bp.file == file and bp.line == line then
        table.remove(breakpoints, i)
        found = true
        print(string.format("Breakpoint removed: %s:%d", vim.fn.fnamemodify(file, ":t"), line))
        break
      end
    end

    if not found then
      if #breakpoints >= MAX_BREAKPOINTS then
        print(string.format("Maximum %d breakpoints allowed.", MAX_BREAKPOINTS))
        return
      end
      table.insert(breakpoints, { file = file, line = line, hits = 0 })
      print(string.format("Breakpoint %d/%d set for %s:%d", #breakpoints, MAX_BREAKPOINTS, vim.fn.fnamemodify(file, ":t"), line))
    end
  end, { desc = "Debugger Toggle Breakpoint" })

  vim.keymap.set("n", "<leader>ml", function()
    if #breakpoints == 0 then
      print("No breakpoints set.")
      return
    end
    local lines = { string.format("Current Breakpoints (%d/%d):", #breakpoints, MAX_BREAKPOINTS) }
    for i, bp in ipairs(breakpoints) do
      local hit_str = (bp.hits and bp.hits > 0) and string.format(" [Hit: %d times]", bp.hits) or " [Unreached]"
      table.insert(lines, string.format("  [%d] %s:%d%s", i, vim.fn.fnamemodify(bp.file, ":t"), bp.line, hit_str))
    end
    print(table.concat(lines, "\n"))
  end, { desc = "Debugger List Breakpoints" })

  vim.keymap.set("n", "<leader>mr", function()
    breakpoints = {}
    local is_active = false
    if client ~= nil then
      local ok, closing = pcall(function() return client:is_closing() end)
      if ok and not closing then
        is_active = true
      end
    end

    if is_active then
      send_payload(vim.json.encode({ command = "reset_breakpoints", breakpoints = {} }))
      print("All breakpoints reset (local and remote).")
    else
      print("All breakpoints reset locally.")
    end
  end, { desc = "Debugger Reset Breakpoints" })

  vim.keymap.set("n", "<leader>mq", function()
    local choice = vim.fn.confirm("Terminate active debug session?", "&Yes\n&No", 2)
    if choice == 1 then
      send_payload(vim.json.encode({ command = "quit" }))
      if client and not client:is_closing() then
        client:close()
      end
      client = nil
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      print("Debugger session terminated.")
    else
      print("Termination cancelled.")
    end
  end, { desc = "Debugger Terminate Run" })

  vim.keymap.set("n", "<leader>mc", function()
    local payload = vim.json.encode({
      command = "continue",
      breakpoints = breakpoints
    })
    send_payload(payload)
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    print("Running execution...")
  end, { desc = "Debugger Continue / Start" })

  vim.keymap.set("n", "<leader>mn", function()
    send_payload("next")
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    print("Stepped to next line")
  end, { desc = "Debugger Next" })

  vim.keymap.set("n", "<leader>mS", function()
    send_payload("step")
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    print("Stepped into function")
  end, { desc = "Debugger Step Into" })

  vim.keymap.set("n", "<leader>ms", function()
    send_payload("stack")
    print("Fetching call stack...")
  end, { desc = "Debugger Stack Trace" })

  vim.keymap.set("n", "<leader>mv", function()
    local cword = vim.fn.expand("<cword>")
    if cword == "" then
      print("No variable under cursor.")
      return
    end
    send_payload("eval:" .. cword)
    print("Evaluating variable: " .. cword)
  end, { desc = "Debugger Inspect Variable" })

  vim.keymap.set("n", "<leader>mi", function()
    vim.ui.input({ prompt = "Evaluate Python expression: " }, function(input)
      if input and input ~= "" then
        send_payload("eval:" .. input)
        print("Evaluating: " .. input)
      end
    end)
  end, { desc = "Debugger Interactive Eval" })
end

return M
