-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

-- Look up a short :help snippet for a symbol (cached for fast completion)
local doc_cache = {}
local function get_help_snippet(sym)
  if doc_cache[sym] ~= nil then
    return doc_cache[sym] or nil
  end

  local leaf = sym:match('([^%.]+)$') or sym
  local candidates = { sym, sym .. '()', leaf, leaf .. '()', "'" .. leaf .. "'" }
  local tag_loc

  for _, name in ipairs(candidates) do
    local tags = vim.fn.taglist('^' .. vim.fn.escape(name, '\\.*$^~[]') .. '$')
    if #tags > 0 and tags[1].filename then
      tag_loc = tags[1]
      break
    end
  end

  if not tag_loc then
    doc_cache[sym] = false
    return nil
  end

  local lines = vim.fn.readfile(tag_loc.filename)
  local target_idx = 1
  local pattern = tag_loc.cmd:gsub('^/', ''):gsub('/$', '')
  for i, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      target_idx = i
      break
    end
  end

  local doc = {}
  for i = target_idx, math.min(#lines, target_idx + 25) do
    if i > target_idx and (lines[i]:match('^=+$') or lines[i]:match('^%-+$')) then
      break
    end
    table.insert(doc, lines[i])
  end

  local text = table.concat(doc, '\n')
  doc_cache[sym] = text
  return text
end

-- Resolve a dotted path like "vim.api.nvim_buf" against the live runtime
local function resolve_table(prefix)
  local parts = vim.split(prefix, '.', { plain = true })
  local curr = _G
  for i = 1, #parts - 1 do
    if type(curr) ~= 'table' then
      return nil, ''
    end
    curr = curr[parts[i]]
  end
  if type(curr) ~= 'table' then
    return nil, ''
  end
  return curr, parts[#parts] or ''
end

-- Built-in omnifunc for Lua (<C-x><C-o>) with live :help preview info
function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local start = col
    while start > 0 and line:sub(start, start):match('[%w_%.]') do
      start = start - 1
    end
    return start
  end

  local tbl, partial = resolve_table(base)
  if not tbl then
    return {}
  end

  local prefix = base:sub(1, #base - #partial)
  local matches = {}

  if tbl == vim.opt or tbl == vim.opt_local or tbl == vim.opt_global or tbl == vim.bo or tbl == vim.wo then
    for name, info in pairs(vim.api.nvim_get_all_options_info()) do
      local valid_scope = (tbl ~= vim.bo or info.scope == 'buf')
        and (tbl ~= vim.wo or info.scope == 'win')
      if valid_scope and vim.startswith(name, partial) then
        local full = prefix .. name
        table.insert(matches, {
          word = full,
          abbr = name,
          kind = 'v',
          menu = '[' .. info.type .. ']',
          info = get_help_snippet(full),
        })
      end
    end
  else
    for k, v in pairs(tbl) do
      if type(k) == 'string' and vim.startswith(k, partial) then
        local full = prefix .. k
        table.insert(matches, {
          word = full,
          abbr = k,
          kind = type(v) == 'function' and 'f' or (type(v) == 'table' and 'm' or 'v'),
          menu = '[' .. type(v) .. ']',
          info = get_help_snippet(full),
        })
      end
    end
  end

  table.sort(matches, function(a, b)
    return a.abbr < b.abbr
  end)
  return matches
end

-- Extract full dotted identifier under cursor
local function symbol_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local left = line:sub(1, col):match('[%w_%.]+$') or ''
  local right = line:sub(col + 1):match('^[%w_%.]+') or ''
  return left .. right
end

-- Show floating :help window on K
local function show_help_float(sym)
  local text = get_help_snippet(sym)
  if not text then
    vim.notify('No :help tag found for ' .. sym, vim.log.levels.INFO)
    return
  end

  vim.lsp.util.open_floating_preview(vim.split(text, '\n', { plain = true }), 'help', {
    border = 'rounded',
    focus_id = 'reeloc_lua_help',
  })
end

function M.setup()
  local ns = vim.api.nvim_create_namespace('reeloc_lua_syntax')

  -- Ensure help tag index exists for vim.fn.taglist()
  vim.opt.tags:append(vim.env.VIMRUNTIME .. '/doc/tags')

  -- 1. Live syntax diagnostics via embedded LuaJIT
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'InsertLeave' }, {
    pattern = '*.lua',
    callback = function(args)
      local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
      local bufname = vim.api.nvim_buf_get_name(args.buf)
      local chunk, err = loadstring(table.concat(lines, '\n'), '@' .. bufname)
      if chunk then
        vim.diagnostic.reset(ns, args.buf)
        return
      end

      local lnum, msg = err:match(':(%d+):%s*(.+)')
      vim.diagnostic.set(ns, args.buf, {
        {
          lnum = (tonumber(lnum) or 1) - 1,
          col = 0,
          severity = vim.diagnostic.severity.ERROR,
          source = 'luajit',
          message = msg or err,
        },
      })
    end,
  })

  -- 2. Buffer-local auto-completion with live doc popup & floating K help
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'lua',
    callback = function(args)
      vim.bo[args.buf].omnifunc = "v:lua.require'lua_dev'.omnifunc"
      vim.bo[args.buf].completeopt = 'menu,menuone,noselect,popup'

      -- Trigger completion popup automatically while typing (after '.' or >= 2 chars)
      vim.api.nvim_create_autocmd('TextChangedI', {
        buffer = args.buf,
        callback = function()
          if vim.fn.pumvisible() == 1 then
            return
          end
          local col = vim.api.nvim_win_get_cursor(0)[2]
          local before = vim.api.nvim_get_current_line():sub(1, col)
          if before:match('[%w_]+%.[%w_]*$') or before:match('[%w_][%w_]+$') then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-x><C-o>', true, false, true), 'n', false)
          end
        end,
      })

      -- Use <Tab> / <S-Tab> to cycle the popup menu when open
      vim.keymap.set('i', '<Tab>', function()
        return vim.fn.pumvisible() == 1 and '<C-n>' or '<Tab>'
      end, { buffer = args.buf, expr = true })

      vim.keymap.set('i', '<S-Tab>', function()
        return vim.fn.pumvisible() == 1 and '<C-p>' or '<S-Tab>'
      end, { buffer = args.buf, expr = true })

      -- Floating window help on K (press K a second time to jump into the float)
      vim.keymap.set('n', 'K', function()
        local sym = symbol_under_cursor()
        if sym ~= '' then
          show_help_float(sym)
        end
      end, { buffer = args.buf, desc = 'Show floating Neovim/Lua :help for symbol' })
    end,
  })
end

return M
