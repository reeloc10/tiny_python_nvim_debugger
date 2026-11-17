-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 reeloc10

-- Set your global leader key first
vim.g.mapleader = " "
vim.o.timeoutlen = 2000

-- Load modular configurations
require("pylsp_config").setup()
require("tiny_debugger").setup()
