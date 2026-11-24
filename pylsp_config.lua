-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

local M = {}

function M.setup()
  -- 1. Configure diagnostic display (virtual text and line signs)
  vim.diagnostic.config({
    virtual_text = { prefix = '■' },
    signs = true,
    underline = true,
    update_in_insert = false,
  })

  -- 2. Configure native completion menu behavior with floating docstring popup
  vim.opt.completeopt = { 'menu', 'menuone', 'noinsert', 'noselect', 'popup' }

  -- 3. Super-Tab: Accept completion item OR jump to next parameter snippet tabstop
  vim.keymap.set({ 'i', 's' }, '<Tab>', function()
    if vim.fn.pumvisible() == 1 then
      -- If no item is selected yet (because of noselect), select first and confirm
      local info = vim.fn.complete_info({ 'selected' })
      if info.selected == -1 then
        return '<C-n><C-y>'
      end
      return '<C-y>'
    elseif vim.snippet.active({ direction = 1 }) then
      return '<Cmd>lua vim.snippet.jump(1)<CR>'
    else
      return '<Tab>'
    end
  end, { expr = true, desc = 'Accept completion or jump snippet forward' })

  vim.keymap.set({ 'i', 's' }, '<S-Tab>', function()
    if vim.fn.pumvisible() == 1 then
      return '<C-p>'
    elseif vim.snippet.active({ direction = -1 }) then
      return '<Cmd>lua vim.snippet.jump(-1)<CR>'
    else
      return '<S-Tab>'
    end
  end, { expr = true, desc = 'Previous completion or jump snippet backward' })

  -- 4. Enable native LSP completion & doc bindings when a server attaches
  vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client then return end

      local opts = { buffer = args.buf }

      -- Enable native LSP completion (triggerCharacters + as-you-type identifier letters)
      if client:supports_method('textDocument/completion') then
        vim.lsp.completion.enable(true, client.id, args.buf, {
          autotrigger = true,
        })

        local comp_group = vim.api.nvim_create_augroup('ReelocLspAutoComplete', { clear = false })
        vim.api.nvim_clear_autocmds({ group = comp_group, buffer = args.buf })
        vim.api.nvim_create_autocmd('InsertCharPre', {
          group = comp_group,
          buffer = args.buf,
          callback = function()
            if vim.fn.pumvisible() == 0 and vim.v.char:match('[%w_]') then
              vim.schedule(function()
                if vim.fn.mode() == 'i' and vim.fn.pumvisible() == 0 then
                  vim.lsp.completion.get()
                end
              end)
            end
          end,
        })
      end

      -- Trigger completion manually with Ctrl-Space
      vim.keymap.set('i', '<C-Space>', function()
        vim.lsp.completion.get()
      end, vim.tbl_extend('force', opts, { desc = 'Trigger LSP completion' }))

      -- Show function internal docs (hover)
      vim.keymap.set('n', 'K', vim.lsp.buf.hover,
        vim.tbl_extend('force', opts, { desc = 'Show function documentation' }))

      -- Buffer-local LSP keymaps and hover settings
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition,
        vim.tbl_extend('force', opts, { desc = 'Go to definition' }))
      vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float,
        vim.tbl_extend('force', opts, { desc = 'Show line diagnostics' }))

      -- Trigger CursorHold after 300ms (default is 4000ms)
      vim.o.updatetime = 300

      -- Automatically show diagnostics in a floating window on hover for this buffer
      local diag_group = vim.api.nvim_create_augroup("LspDiagnosticsHover", { clear = false })
      vim.api.nvim_clear_autocmds({ group = diag_group, buffer = opts.buffer })
      vim.api.nvim_create_autocmd("CursorHold", {
        group = diag_group,
        buffer = opts.buffer,
        callback = function()
          vim.diagnostic.open_float(nil, { focusable = false })
        end,
      })

      -- Show parameter signature while inside parentheses
      vim.keymap.set('i', '<C-h>', vim.lsp.buf.signature_help,
        vim.tbl_extend('force', opts, { desc = 'Show function signature' }))
      vim.keymap.set('i', '<M-s>', vim.lsp.buf.signature_help,
        vim.tbl_extend('force', opts, { desc = 'Show function signature' }))

      -- Cross-file symbol references mapping (quickfix navigation)
      vim.keymap.set('n', 'gr', function()
        vim.lsp.buf.references(nil, {
          on_list = function(options)
            vim.fn.setqflist({}, ' ', options)
            vim.cmd('copen')
          end,
        })
      end, vim.tbl_extend('force', opts, { desc = 'List symbol references in quickfix' }))
    end,
  })

  -- vim.lsp.set_log_level("debug")
  -- log file: ~/.local/state/nvim/lsp.log
  -- 5. Attach pylsp and ruff natively to Python buffers
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'python',
    callback = function()
      local root = vim.uv.cwd()

      -- Explicitly enable snippetSupport so pylsp honors include_params = true
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities.textDocument.completion.completionItem.snippetSupport = true

      vim.lsp.start({
        name = 'pylsp',
        cmd = { 'pylsp' },
        root_dir = root,
        capabilities = capabilities,
        settings = {
          pylsp = {
            plugins = {
              jedi_completion = {
                enabled = true,
                include_params = true,
              },
            },
          },
        },
      })

      vim.lsp.start({
        name = 'ruff',
        cmd = { 'ruff', 'server' },
        root_dir = root,
      })
    end,
  })

  -- 6. Diagnostic navigation and inspection keymaps, Autocorrection keymaps
  local lsp_actions = {
    {
      mode = 'n',
      lhs = '[d',
      rhs = function() vim.diagnostic.goto_prev() end,
      desc = 'Previous diagnostic',
      cmd = 'ReelocLspPrevDiagnostic',
    },
    {
      mode = 'n',
      lhs = ']d',
      rhs = function() vim.diagnostic.goto_next() end,
      desc = 'Next diagnostic',
      cmd = 'ReelocLspNextDiagnostic',
    },
    {
      -- Buffer-local <leader>e is mapped in LspAttach; keep Ex command available
      rhs = function() vim.diagnostic.open_float() end,
      desc = 'Show diagnostic error float',
      cmd = 'ReelocLspDiagnosticFloat',
    },
    {
      mode = 'n',
      lhs = '<leader>qw',
      rhs = function()
        vim.diagnostic.setqflist({ open = true })
      end,
      desc = 'Populate quickfix with workspace diagnostics',
      cmd = 'ReelocLspWorkspaceDiagnostics',
    },
    {
      mode = 'n',
      lhs = '<leader>ca',
      rhs = function() vim.lsp.buf.code_action() end,
      desc = 'LSP Code Action',
      cmd = 'ReelocLspCodeAction',
    },
    {
      mode = 'n',
      lhs = '<leader>f',
      rhs = function()
        vim.lsp.buf.code_action({
          context = { only = { 'source.fixAll.ruff' } },
          apply = true,
        })
        vim.lsp.buf.format({ async = false })
      end,
      desc = 'Ruff auto-fix and format',
      cmd = 'ReelocLspRuffFix',
    },
    {
      -- Ex-command only (no leader keybinding)
      rhs = function()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then
          print('No active LSP clients attached to current buffer.')
          return
        end
        for _, client in ipairs(clients) do
          print(string.format('LSP Client: %s (ID: %d)', client.name, client.id))
        end
      end,
      desc = 'Show active LSP clients on current buffer',
      cmd = 'ReelocLspStatus',
    },
  }

  -- Register keymaps conditionally and Ex commands for all entries with a cmd
  for _, action in ipairs(lsp_actions) do
    if action.lhs and action.mode then
      vim.keymap.set(action.mode, action.lhs, action.rhs, { desc = action.desc })
    end

    if action.cmd then
      vim.api.nvim_create_user_command(action.cmd, action.rhs, { desc = action.desc })
    end
  end
end

return M
