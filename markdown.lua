-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}
local ns_id = vim.api.nvim_create_namespace("reeloc_markdown")

-- System-wide path constant for the Tree-sitter markdown parser shared object
local SYSTEM_MARKDOWN_PARSER = "/usr/lib64/nvim/parser/markdown.so"

-- Optional: Try loading system tree-sitter markdown parser gracefully
local function load_treesitter_parser()
  local success, err = pcall(vim.treesitter.language.add, "markdown", { path = SYSTEM_MARKDOWN_PARSER })
  if not success then
    -- Fails gracefully if libtree-sitter-markdown is not present, keeping plugin dependency-free
    vim.notify("ReelocMarkdown: Tree-sitter parser not found at " .. SYSTEM_MARKDOWN_PARSER .. ". Using standard buffer overlay.", vim.log.levels.DEBUG)
  end
end

local function enable(bufnr)
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = "nc"

  -- Clear any existing extmarks/matches
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for idx, line in ipairs(lines) do
    -- Overlay checkboxes using extmarks to completely bypass regex double-conceal bugs
    for col in line:gmatch("()%[%s%]") do
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, idx - 1, col - 1, {
        end_col = col + 2,
        virt_text = { { "☐", "Conceal" } },
        virt_text_pos = "overlay",
      })
    end
    for col in line:gmatch("()%[[xX]%]") do
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, idx - 1, col - 1, {
        end_col = col + 2,
        virt_text = { { "☑", "Conceal" } },
        virt_text_pos = "overlay",
      })
    end
  end

  -- Conceal table pipes into clean vertical borders
  vim.b[bufnr].reeloc_md_matches = {
    vim.fn.matchadd("Conceal", [=[|]=], 10, -1, { conceal = "│" }),
  }
  vim.b[bufnr].reeloc_md_enabled = true
end

local function disable(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  local matches = vim.b[bufnr].reeloc_md_matches or {}
  for _, id in ipairs(matches) do
    pcall(vim.fn.matchdelete, id)
  end
  vim.b[bufnr].reeloc_md_matches = {}
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

  -- Attempt loading tree-sitter parser on setup using the constant path
  load_treesitter_parser()

  vim.api.nvim_create_user_command("ReelocMarkdown", function()
    M.toggle()
  end, { desc = "Toggle clean markdown checkbox and table conceal" })

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
