-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}
local ns_id = vim.api.nvim_create_namespace("reeloc_markdown")

-- System-wide path constant for the Tree-sitter markdown parser shared object
local SYSTEM_MARKDOWN_PARSER = "/usr/lib64/nvim/parser/markdown.so"

local function load_treesitter_parser()
  local success, err = pcall(vim.treesitter.language.add, "markdown", { path = SYSTEM_MARKDOWN_PARSER })
  if not success then
    vim.notify("ReelocMarkdown: Tree-sitter parser not found at " .. SYSTEM_MARKDOWN_PARSER .. ". Using standard buffer overlay.", vim.log.levels.DEBUG)
  end
end

-- Helper to split a markdown table row by '|'
local function split_row(line)
  local cells = {}
  local inner = line:gsub("^%s*|%s*", ""):gsub("%s*|%s*$", "")
  for cell in (inner .. "|"):gmatch("(.-)%s*|%s*") do
    table.insert(cells, vim.trim(cell))
  end
  return cells
end

-- Swap markdown checkboxes to unicode glyphs correctly
local function swap_glyphs(text)
  local res = text:gsub("%[%s%]", "☐")
  res = res:gsub("%[[xX]%]", "☑")
  return res
end

local function enable(bufnr)
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = "nc"

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- First pass: Pre-process cells with glyph swaps, then calculate exact max column widths
  local col_widths = {}
  local table_rows = {}

  for idx, line in ipairs(lines) do
    if line:match("^%s*|.*|%s*$") then
      local cells = split_row(line)
      local is_separator = true
      for _, cell in ipairs(cells) do
        if not cell:match("^:?[-:]+$") then
          is_separator = false
          break
        end
      end

      -- Apply glyph swaps to cells before computing layout widths
      local swapped_cells = {}
      for _, cell in ipairs(cells) do
        table.insert(swapped_cells, swap_glyphs(cell))
      end

      table_rows[idx] = { cells = swapped_cells, is_separator = is_separator }

      if not is_separator then
        for i, cell in ipairs(swapped_cells) do
          col_widths[i] = math.max(col_widths[i] or 0, vim.fn.strdisplaywidth(cell))
        end
      end
    end
  end

  -- Second pass: Render clean headers, standalone checkboxes, and fully aligned tables
  for idx, line in ipairs(lines) do
    -- 1. Format headings: Dynamically calculate prefix length (# + spaces) and pad precisely
    local hashes, heading_text = line:match("^(#+)%s+(.*)$")
    if hashes and heading_text then
      local prefix_len = #hashes + 1 -- hashes plus the separating space
      local padding_len = prefix_len - (#line - (#heading_text + prefix_len))
      -- Ensure exact line-length matching by appending the required padding spaces
      local padded_title = heading_text .. string.rep(" ", math.max(0, #hashes + 1))

      vim.api.nvim_buf_set_extmark(bufnr, ns_id, idx - 1, 0, {
        end_col = #line,
        virt_text = { { padded_title, "Title" } },
        virt_text_pos = "overlay",
        hl_mode = "replace",
        priority = 200,
      })
    end

    -- 2. Overlay standalone or list checkboxes outside of tables
    if not table_rows[idx] then
      for col, match in line:gmatch("()(%[%s%])") do
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, idx - 1, col - 1, {
          end_col = col + #match,
          virt_text = { { "☐", "Conceal" } },
          virt_text_pos = "overlay",
        })
      end
      for col, match in line:gmatch("()(%[[xX]%])") do
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, idx - 1, col - 1, {
          end_col = col + #match,
          virt_text = { { "☑", "Conceal" } },
          virt_text_pos = "overlay",
        })
      end
    end

    -- 3. Render synchronized constant-width table formatting using pre-swapped widths
    if table_rows[idx] then
      local row = table_rows[idx]
      if row.is_separator then
        local sep_cells = {}
        for i, _ in ipairs(row.cells) do
          local target_w = col_widths[i] or 3
          local hyphens = string.rep("-", math.max(target_w, 3))
          table.insert(sep_cells, " " .. hyphens .. " ")
        end
        local formatted_sep = "│" .. table.concat(sep_cells, "│") .. "│"
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, idx - 1, 0, {
          end_col = #line,
          virt_text = { { formatted_sep, "Comment" } },
          virt_text_pos = "overlay",
          hl_mode = "replace",
        })
      else
        local formatted_cells = {}
        for i, cell in ipairs(row.cells) do
          local width = vim.fn.strdisplaywidth(cell)
          local target_width = col_widths[i] or width
          local padding = string.rep(" ", target_width - width)
          table.insert(formatted_cells, " " .. cell .. padding .. " ")
        end
        local formatted_line = "│" .. table.concat(formatted_cells, "│") .. "│"
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, idx - 1, 0, {
          end_col = #line,
          virt_text = { { formatted_line, "Normal" } },
          virt_text_pos = "overlay",
          hl_mode = "replace",
        })
      end
    end
  end

  vim.b[bufnr].reeloc_md_enabled = true
end

local function disable(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  vim.wo.conceallevel = 0
  vim.b[bufnr].reeloc_md_enabled = false
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "markdown" then
    vim.notify("ReelocMarkdown: Not a markdown buffer", vim.log.levels.WARN)
    return
  end

  if vim.b[bufnr].reeloc_md_enabled then
    disable(bufnr)
    vim.notify("ReelocMarkdown: Off", vim.log.levels.INFO)
  else
    enable(bufnr)
    vim.notify("ReelocMarkdown: On", vim.log.levels.INFO)
  end
end

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", { auto_enable = false }, opts or {})

  load_treesitter_parser()

  vim.api.nvim_create_user_command("ReelocMarkdown", function()
    M.toggle()
  end, { desc = "Toggle clean markdown headers, checkboxes, and table formatting" })

  if opts.auto_enable then
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("ReelocMarkdown", { clear = true }),
      pattern = "markdown",
      callback = function(args)
        if not vim.b[args.buf].reeloc_md_enabled then
          enable(args.buf)
        end
      end,
    })
  end
end

return M
