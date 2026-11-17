-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local client = nil
local ns_id = vim.api.nvim_create_namespace("tiny_debugger")
local read_buffer = ""

local function ensure_connected(callback)
  if client and not client:is_closing() then
    callback()
    return
  end

  read_buffer = ""
  client = vim.loop.new_tcp()
  client:connect("127.0.0.1", 56789, function(err)
    if err then
      print("Debugger connection failed: " .. err)
      client = nil
      return
    end
    print("Connected to Python tracer socket.")

    -- Line-buffered reader to prevent JSON decode crashes on stream chunks
    client:read_start(function(read_err, chunk)
      assert(not read_err, read_err)
      if chunk then
        read_buffer = read_buffer .. chunk
        for line in read_buffer:gmatch("(.-)\n") do
          if line ~= "" then
            local ok, data = pcall(vim.json.decode, line)
            if ok and data.event == "stopped" then
              vim.schedule(function()
                local target_file = vim.fs.normalize(data.file)
                local current_file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))

                if current_file ~= target_file then
                  vim.cmd("keepalt edit " .. vim.fn.fnameescape(data.file))
                end

                vim.api.nvim_win_set_cursor(0, {data.line, 0})

                local bufnr = vim.api.nvim_get_current_buf()
                vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
                vim.api.nvim_buf_set_extmark(bufnr, ns_id, data.line - 1, 0, {
                  line_hl_group = "Visual",
                })
                print("Paused at line " .. data.line)
              end)
            end
          end
        end
        read_buffer = read_buffer:match("[^\n]*$") or ""
      else
        if client and not client:is_closing() then
          client:close()
        end
        client = nil
      end
    end)

    callback()
  end)
end

local function send_payload(payload_str)
  ensure_connected(function()
    if client and not client:is_closing() then
      client:write(payload_str .. "\n", function(err)
        if err then
          print("Write error: " .. tostring(err))
        end
      end)
    end
  end)
end

-- Force explicit keys instead of <leader> to test
vim.keymap.set("n", "mb", function()
  local file = vim.api.nvim_buf_get_name(0)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local payload = vim.json.encode({ file = file, line = line })
  send_payload(payload)
  print(string.format("Breakpoint sent for %s:%d", vim.fn.fnamemodify(file, ":t"), line))
end, { desc = "Debugger Set Breakpoint" })

vim.keymap.set("n", "mc", function()
  send_payload("continue")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  print("Resumed execution")
end, { desc = "Debugger Continue" })

vim.keymap.set("n", "mn", function()
  send_payload("next")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  print("Stepped to next line")
end, { desc = "Debugger Next" })
