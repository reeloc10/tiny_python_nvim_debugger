-- git_status.lua

local M = {}

vim.api.nvim_set_hl(0, 'GitBranchClean', { fg = '#98c379', bg = '#282c34', bold = true })
vim.api.nvim_set_hl(0, 'GitBranchModified', { fg = '#e5c07b', bg = '#282c34', bold = true })
vim.api.nvim_set_hl(0, 'GitHash', { fg = '#abb2bf', bg = '#282c34' })

local function update_statusline()
  local branch_h = io.popen("git branch --show-current 2>/dev/null")
  if not branch_h then return end
  local branch = branch_h:read("*a"):gsub("%s+", "")
  branch_h:close()

  local git_component = ""

  if branch ~= "" then
    local hash_h = io.popen("git rev-parse --short HEAD 2>/dev/null")
    local hash = hash_h and hash_h:read("*a"):gsub("%s+", "") or ""
    if hash_h then hash_h:close() end

    local status_h = io.popen("git status --porcelain 2>/dev/null")
    local is_dirty = false
    if status_h then
      local status_output = status_h:read("*a")
      if status_output and status_output ~= "" then
        is_dirty = true
      end
      status_h:close()
    end

    local branch_hl = is_dirty and 'GitBranchModified' or 'GitBranchClean'
    local suffix = is_dirty and '*' or '·'

    git_component = string.format(
      "%%#%s#[%s%s]%%#GitHash#[%s]%%#StatusLine#",
      branch_hl,
      branch,
      suffix,
      hash
    )
  end

  -- %m is included here after the git component
  vim.opt.statusline = "%f %r " .. git_component .. " %m %= %l,%c%V %P"
end

local grp = vim.api.nvim_create_augroup('CustomGitStatusline', { clear = true })
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'FocusGained' }, {
  group = grp,
  pattern = '*',
  callback = update_statusline,
})

update_statusline()

return M
