-- tiny_debugger_ui.lua
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

local locals_win = nil
local locals_buf = nil
local globals_win = nil
local globals_buf = nil

local active_expanded_paths = nil
local current_data = { locals = {}, globals = {} }

function M.is_open()
  return locals_win and vim.api.nvim_win_is_valid(locals_win) and
         globals_win and vim.api.nvim_win_is_valid(globals_win)
end

function M.close()
  if locals_win and vim.api.nvim_win_is_valid(locals_win) then
    vim.api.nvim_win_close(locals_win, true)
  end
  if globals_win and vim.api.nvim_win_is_valid(globals_win) then
    vim.api.nvim_win_close(globals_win, true)
  end
  locals_win, locals_buf, globals_win, globals_buf = nil, nil, nil, nil
end

local function build_tree_lines(data_table, prefix, indent, lines_out, path_map, depth, total_nodes)
  if type(data_table) ~= "table" then return end

  depth = depth or 0
  total_nodes = total_nodes or { count = 0 }
  if depth > 10 or total_nodes.count > 500 then
    table.insert(lines_out, string.rep("  ", indent) .. "... (limit reached)")
    return
  end

  for k, v in pairs(data_table) do
    total_nodes.count = total_nodes.count + 1
    if total_nodes.count > 500 then break end

    local path = prefix .. "." .. tostring(k)
    local is_table = (type(v) == "table")
    local spacing = string.rep("  ", indent)

    if is_table then
      local is_expanded = active_expanded_paths and active_expanded_paths[path] == true
      local icon = is_expanded and "▾ " or "▸ "
      local line_str = string.format("%s%s%s: { ... }", spacing, icon, tostring(k))

      table.insert(lines_out, line_str)
      path_map[#lines_out] = { path = path, table = v }

      if is_expanded then
        build_tree_lines(v, path, indent + 1, lines_out, path_map, depth + 1, total_nodes)
      end
    else
      local val_str = tostring(v):gsub("\n", " ")
      local line_str = string.format("%s  %s = %s", spacing, tostring(k), val_str)

      table.insert(lines_out, line_str)
      path_map[#lines_out] = { path = path, table = nil }
    end
  end
end

function M.update(data, expanded_ref)
  if data then current_data = data end
  if expanded_ref then active_expanded_paths = expanded_ref end
  if not M.is_open() then return end

  -- Locals Buffer
  local local_lines = {}
  local local_path_map = {}
  if current_data.locals then
    build_tree_lines(current_data.locals, "locals", 0, local_lines, local_path_map)
  else
    table.insert(local_lines, "  (none)")
  end

  vim.bo[locals_buf].modifiable = true
  vim.api.nvim_buf_set_lines(locals_buf, 0, -1, false, local_lines)
  vim.bo[locals_buf].modifiable = false
  vim.b[locals_buf].path_map = local_path_map

  -- Globals Buffer
  local global_lines = {}
  local global_path_map = {}
  if current_data.globals then
    build_tree_lines(current_data.globals, "globals", 0, global_lines, global_path_map)
  else
    table.insert(global_lines, "  (none)")
  end

  vim.bo[globals_buf].modifiable = true
  vim.api.nvim_buf_set_lines(globals_buf, 0, -1, false, global_lines)
  vim.bo[globals_buf].modifiable = false
  vim.b[globals_buf].path_map = global_path_map
end

local function setup_buffer_keymaps(buf)
  vim.keymap.set("n", "<CR>", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local pmap = vim.b[bufnr].path_map

    if pmap and pmap[row] and pmap[row].table and active_expanded_paths then
      local path = pmap[row].path
      active_expanded_paths[path] = not active_expanded_paths[path]
      M.update(current_data, active_expanded_paths) -- <--- Pass active_expanded_paths here!
    end
  end, { buffer = buf, silent = true })
end

function M.toggle(expanded_ref)
  if expanded_ref then active_expanded_paths = expanded_ref end

  if M.is_open() then
    M.close()
    print("[Debugger UI] Variable sidebar closed.")
  else
    -- Remember current window to return focus later
    local orig_win = vim.api.nvim_get_current_win()

    -- 1. Create left vertical split for Locals (width 35)
    vim.cmd("topleft 35vsplit")
    locals_buf = vim.api.nvim_create_buf(false, true)
    locals_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(locals_win, locals_buf)

    vim.bo[locals_buf].buftype = "nofile"
    vim.bo[locals_buf].swapfile = false
    vim.bo[locals_buf].modifiable = false
    vim.wo[locals_win].winbar = " Locals (<CR> toggle) "
    setup_buffer_keymaps(locals_buf)

    -- 2. Split horizontally *inside* the locals window for Globals (lower half)
    vim.api.nvim_set_current_win(locals_win)
    vim.cmd("belowright split")
    globals_buf = vim.api.nvim_create_buf(false, true)
    globals_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(globals_win, globals_buf)

    vim.bo[globals_buf].buftype = "nofile"
    vim.bo[globals_buf].swapfile = false
    vim.bo[globals_buf].modifiable = false
    vim.wo[globals_win].winbar = " Globals (<CR> toggle) "
    setup_buffer_keymaps(globals_buf)

    -- Restore focus back to original code window
    if vim.api.nvim_win_is_valid(orig_win) then
      vim.api.nvim_set_current_win(orig_win)
    else
      vim.cmd("wincmd p")
    end

    M.update(current_data, active_expanded_paths)
    print("[Debugger UI] Variable sidebar opened.")
  end
end

return M
