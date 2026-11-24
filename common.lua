-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

-- Single source of truth for the repository root
M.cloned_folder = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

function M.get_repo_rel_path(filepath)
  if not filepath or filepath == "" then return nil end
  local res = vim.system({ "git", "ls-files", "--full-name", "--", filepath }, { text = true }):wait()
  if res.code ~= 0 then return nil end
  local path = vim.trim(res.stdout or "")
  return path ~= "" and path or nil
end

return M
