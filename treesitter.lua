-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

-- Constant for the system-wide Tree-sitter Python parser shared library
local SYSTEM_PYTHON_PARSER = "/usr/lib64/libtree-sitter-python.so"

local function find_enclosing_node(target_type)
  local node = vim.treesitter.get_node()

  if not node then
    print("[DEBUG] get_node returned nil, cursor:", vim.inspect(vim.api.nvim_win_get_cursor(0)))
  end

  while node do
    if node:type() == target_type then
      return node
    end
    node = node:parent()
  end
  return nil
end

local function select_node_range(node, inner)
  local target = node
  if inner then
    -- In tree-sitter-python, the indented body of function_definition / class_definition is a `block` child
    local body = node:field("body")[1]
    if body then
      target = body
    end
  end

  local start_row, start_col, end_row, end_col = target:range()
  -- Exit visual mode first if already active
  if vim.fn.mode():match("[vV\22]") then
    vim.cmd("normal! \27")
  end

  vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
  vim.cmd("normal! v")
  -- end_col from tree-sitter is exclusive; step back 1 char when end_col > 0
  local adj_col = end_col > 0 and (end_col - 1) or 0
  vim.api.nvim_win_set_cursor(0, { end_row + 1, adj_col })
end

local function jump_to_sibling_def(target_type, forward)
  local cur_row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local parser = vim.treesitter.get_parser(0)
  if not parser then return end

  local tree = parser:parse()[1]
  if not tree then return end

  local root = tree:root()
  local matches = {}

  local function collect(n)
    if n:type() == target_type then
      table.insert(matches, n)
    end
    for child in n:iter_children() do
      if child:named() then
        collect(child)
      end
    end
  end
  collect(root)

  if forward then
    for _, n in ipairs(matches) do
      local r = n:range()
      if r > cur_row then
        vim.api.nvim_win_set_cursor(0, { r + 1, 0 })
        return
      end
    end
  else
    for i = #matches, 1, -1 do
      local r = matches[i]:range()
      if r < cur_row then
        vim.api.nvim_win_set_cursor(0, { r + 1, 0 })
        return
      end
    end
  end
  print("No " .. (forward and "next " or "previous ") .. target_type)
end

function M.setup(opts)
  opts = opts or {}
  local config_dir = opts.config_dir or vim.fn.stdpath("config")

  -- Ensure Neovim picks up system tree-sitter queries from Fedora RPM path and repo lib64
  vim.opt.runtimepath:append("/usr/share/tree-sitter")
  vim.opt.runtimepath:append(config_dir .. "/lib64")

  -- Register the Python parser using the system-wide path constant
  local success, err = pcall(vim.treesitter.language.add, "python", { path = SYSTEM_PYTHON_PARSER })
  if not success then
    vim.notify("Failed to load system Python parser from " .. SYSTEM_PYTHON_PARSER .. ": " .. tostring(err), vim.log.levels.WARN)
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "python" },
    callback = function()
      local ok = pcall(vim.treesitter.start)
      if not ok then
        vim.cmd("packadd nvim-treesitter")
      end
    end,
  })

  -- 1. Print current Tree-sitter AST node under cursor (<leader>ni)
  vim.keymap.set("n", "<leader>ni", function()
    local node = vim.treesitter.get_node()
    if not node then
      print("No tree-sitter node found")
      return
    end
    if not node:named() then
      node = node:parent() or node
    end
    print(string.format("AST Node: [%s] -> text: %q", node:type(), vim.treesitter.get_node_text(node, 0)))
  end, { desc = "Print current Tree-sitter node info" })

  -- 2. Open Neovim built-in live AST tree viewer (<leader>nt)
  vim.keymap.set("n", "<leader>nt", "<cmd>InspectTree<cr>", { desc = "Inspect Tree-sitter AST" })

  -- 3. Text objects (enables cif, dif, yif, vif, caf, daf, cic, dic, vac, etc.)
  local textobjects = {
    { keys = "if", type = "function_definition", inner = true,  desc = "Inner function body" },
    { keys = "af", type = "function_definition", inner = false, desc = "Around function definition" },
    { keys = "ic", type = "class_definition",    inner = true,  desc = "Inner class body" },
    { keys = "ac", type = "class_definition",    inner = false, desc = "Around class definition" },
  }

  for _, obj in ipairs(textobjects) do
    vim.keymap.set({ "x", "o" }, obj.keys, function()
      local node = find_enclosing_node(obj.type)
      if node then
        select_node_range(node, obj.inner)
      else
        print("No enclosing " .. obj.type .. " found")
      end
    end, { desc = obj.desc })
  end

  -- 4. Structural navigation between functions and classes
  vim.keymap.set("n", "]f", function() jump_to_sibling_def("function_definition", true) end, { desc = "Next function" })
  vim.keymap.set("n", "[f", function() jump_to_sibling_def("function_definition", false) end, { desc = "Previous function" })
  vim.keymap.set("n", "]c", function() jump_to_sibling_def("class_definition", true) end, { desc = "Next class" })
  vim.keymap.set("n", "[c", function() jump_to_sibling_def("class_definition", false) end, { desc = "Previous class" })
end

return M
