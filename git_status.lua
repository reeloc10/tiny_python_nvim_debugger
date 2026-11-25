-- git_status.lua

local M = {}

-- 1. Highlight groups for Git and statusline elements
vim.api.nvim_set_hl(0, 'GitBranchClean', { fg = '#98c379', bg = '#282c34', bold = true })
vim.api.nvim_set_hl(0, 'GitBranchModified', { fg = '#e5c07b', bg = '#282c34', bold = true })
vim.api.nvim_set_hl(0, 'GitHash', { fg = '#abb2bf', bg = '#282c34' })
vim.api.nvim_set_hl(0, 'StatusMode', { fg = '#61afef', bg = '#282c34', bold = true })

vim.opt.showmode = false

-- 2. Mode translation table for clean display
local function get_current_mode()
  local modes = {
    ['n']      = 'NORMAL',
    ['no']     = 'PENDING',
    ['v']      = 'VISUAL',
    ['V']      = 'V-LINE',
    ['\x16']   = 'V-BLOCK', -- Ctrl-v
    ['s']      = 'SELECT',
    ['S']      = 'S-LINE',
    ['\x13']   = 'S-BLOCK',
    ['i']      = 'INSERT',
    ['ic']     = 'INSERT',
    ['R']      = 'REPLACE',
    ['Rv']     = 'V-REPLACE',
    ['c']      = 'COMMAND',
    ['cv']     = 'VIM EX',
    ['ce']     = 'EX',
    ['r']      = 'PROMPT',
    ['rm']     = 'MORE',
    ['r?']     = 'CONFIRM',
    ['!']      = 'SHELL',
    ['t']      = 'TERMINAL',
  }
  local current_mode = vim.api.nvim_get_mode().mode
  return modes[current_mode] or 'UNKNOWN'
end

-- State storage and throttle tracking
local git_component = ""
local last_check = 0

local function refresh_git_status()
  local now = vim.uv.now()
  if now - last_check < 500 then return end -- throttle updates to 500ms
  last_check = now

  -- Run asynchronous non-blocking git commands
  vim.system({ 'git', 'branch', '--show-current' }, { text = true }, function(branch_proc)
    if branch_proc.code ~= 0 then return end
    local branch = (branch_proc.stdout or ''):gsub('%s+', '')

    if branch == '' then
      git_component = ''
      vim.schedule(function() vim.cmd.redrawstatus() end)
      return
    end

    vim.system({ 'git', 'rev-parse', '--short', 'HEAD' }, { text = true }, function(hash_proc)
      local hash = hash_proc.code == 0 and (hash_proc.stdout or ''):gsub('%s+', '') or ''

      vim.system({ 'git', 'status', '--porcelain' }, { text = true }, function(status_proc)
        local is_dirty = status_proc.code == 0 and (status_proc.stdout or '') ~= ''

        local branch_hl = is_dirty and 'GitBranchModified' or 'GitBranchClean'
        local suffix = is_dirty and '*' or '·'

        git_component = string.format(
          "%%#%s#[%s%s]%%#GitHash#[%s]%%#StatusLine#",
          branch_hl,
          branch,
          suffix,
          hash
        )

        -- Safely update statusline string on the main thread
        vim.schedule(function()
          local mode_str = "%#StatusMode# " .. get_current_mode() .. " %#StatusLine#"
          vim.opt.statusline = mode_str .. " %f %r " .. git_component .. " %m %= %l,%c%V %P"
        end)
      end)
    end)
  end)
end

-- 3. Autocommands for updating statusline on events and mode changes
local grp = vim.api.nvim_create_augroup('CustomGitStatusline', { clear = true })
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'FocusGained', 'ModeChanged' }, {
  group = grp,
  pattern = '*',
  callback = refresh_git_status,
})

-- Initial trigger
refresh_git_status()

return M
