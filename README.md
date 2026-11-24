# Tiny debugger & pylsp/ruff Integration

A minimal dependency, ~475-line Python and Neovim debugger using RAM-backed Unix domain sockets (`/dev/shm`) and `sys.settrace`—bypassing the DAP ecosystem—paired with a minimal `pylsp` and `ruff` LSP/linting setup (`pylsp_config.lua`).

## Preferred Documentation & Feedback Channel
Live demos, Q&A, and feedback: [twitch.tv/reeloc10](https://www.twitch.tv/reeloc10)

## Environment & Dependencies
Tested on Fedora 45 using system RPM packages from the official repositories:
* `python3-lsp-server-1.14.0-1.fc45.noarch`
* `ruff-0.17.4-1.fc45.x86_64`

## Testing
Run in two separate terminals (in any order):

```bash
nvim -u <cloned folder>/init.lua target.py
```

```bash
python3 <cloned folder>/tiny_debugger.py <nvim pid> target.py
```

## Keybindings & Commands

Default `<leader>` key is `Space`. Every shortcut maps directly to its corresponding Neovim Ex command.

### Debugger
| Action | Leader Shortcut | Ex Command |
| :--- | :--- | :--- |
| **Toggle breakpoint** *(max 5)* | `<leader>mb` | `:TinyBreakpoint` |
| **Continue / Start execution** | `<leader>mc` | `:TinyContinue` |
| **Step over** | `<leader>mn` | `:TinyNext` |
| **Step into** | `<leader>mS` | `:TinyStep` |
| **Inspect call stack** | `<leader>ms` | `:TinyStack` |
| **Inspect variable** | `<leader>mv` | `:TinyEvalCword` |
| **Evaluate expression** | `<leader>mi` | `:TinyEvalInput` |
| **List breakpoints** | `<leader>ml` | `:TinyListBreakpoints` |
| **Reset breakpoints** | `<leader>mr` | `:TinyResetBreakpoints` |
| **Terminate session** | `<leader>mq` | `:TinyQuit` |
| **Toggle Verbose Mode** | `<leader>mV` | `:TinyVerbose` |

### Git Integration
| Action | Ex Command |
| :--- | :--- |
| **Toggle GitSigns** | `:GitSignsToggle` |
| **View Git Diff** | `:GitSignsDiff` |
| **Inspect Git Hunk** | `:GitSignsInspect` |

### LSP & Diagnostic Keybindings & Commands
| Action | Leader Shortcut / Motion | Ex Command |
| :--- | :--- | :--- |
| **Go to definition** | `gd` (normal) | — |
| **Manual LSP completion trigger** | `<C-Space>` (insert) | — |
| **Automatic completion (as-you-type & member trigger)** | `.` / typing (insert) | — |
| **Interactive parameter completion & stubs** | `<C-j>` (insert) | — |
| **Show function documentation** | `K` (normal) | — |
| **Show function signature** | `<C-h>` / `<M-s>` (insert) | — |
| **Previous diagnostic** | `[d` | `:ReelocLspPrevDiagnostic` |
| **Next diagnostic** | `]d` | `:ReelocLspNextDiagnostic` |
| **Show / focus line diagnostics** *(passive hover opens non-focusable float after 300ms; invoking jumps into float)* | `<leader>e` (normal) | `:ReelocLspDiagnosticFloat` |
| **Workspace diagnostics to quickfix** | `<leader>qw` | `:ReelocLspWorkspaceDiagnostics` |
| **Symbol references to quickfix** | `gr` | — |
| **LSP Code Action** | `<leader>ca` | `:ReelocLspCodeAction` |
| **Ruff auto-fix & format** | `<leader>f` | `:ReelocLspRuffFix` |
| **Check attached LSP clients** | — | `:ReelocLspStatus` |

### Autopairing
Automatically closes matching brackets and quotes (`()`, `[]`, `{}`, `""`, `''`) in insert mode using native keymaps without external plugins.

| Action | Trigger | Behavior |
| :--- | :--- | :--- |
| **Auto-close pair** | `(`, `[`, `{`, `"`, `'` (insert) | Inserts matching closing character and centers cursor (skips quotes after word characters like `don't`) |
| **Step over closing delimiter** | `)`, `]`, `}`, `"`, `'` (insert) | Moves cursor past existing closing character instead of duplicating it |
| **Delete empty pair** | `<BS>` (insert) | Deletes both opening and closing characters when cursor is inside an empty pair |

### Terminal Split & Navigation
| Action | Leader Shortcut / Motion | Ex Command |
| :--- | :--- | :--- |
| **Open bottom terminal split** | `<leader>ft` | — |
| **Print AST node info** | `<leader>ni` | — |
| **Inspect live AST tree** | `<leader>nt` | `:InspectTree` |
| **Select inner function / class** | `vif` / `vic` | — |
| **Select around function / class** | `vaf` / `vac` | — |
| **Next / Previous function** | `]f` / `[f` | — |
| **Next / Previous class** | `]c` / `[c` | — |

### Fast Grep & Fuzzy File Search (`fastgrep.lua`)
Native workspace search powered by `ripgrep` (`rg`) and Neovim's built-in quickfix and fuzzy `:find` menu—requiring zero third-party fuzzy-finder plugins.

| Action | Leader Shortcut / Motion | Ex Command |
| :--- | :--- | :--- |
| **Search workspace text (ripgrep)** | `<leader>fg` (normal) | `:ReelocFastGrep [pattern]` |
| **Search word under cursor** | `<leader>fw` (normal) | `:ReelocFastGrepWord` |
| **Next / previous quickfix match** | `]q` / `[q` (normal) | `:cnext` / `:cprev` |
| **Fuzzy file finder** | — | `:find <partial><Tab>` |

### Useful Ad-Hoc Diagnostic & Shell Commands
Quick reference snippets for running tests, switching shells, and inspecting mappings on the fly.

| Task | Command |
| :--- | :--- |
| **Open file in horizontal split** | `:split \| find filename.py` |
| **Open file in vertical split** | `:vsplit \| find filename.py` |
| **Switch active shell to Bash** | `:lua vim.o.shell = '/bin/bash'` |
| **Switch active shell to Zsh** | `:lua vim.o.shell = '/bin/zsh'` |
| **Open terminal running Bash** | `:split \| terminal bash` |
| **Open terminal running Zsh** | `:split \| terminal zsh` |
| **Inspect mapping origin and scope** | `:verbose nmap <Space>e` |
| **View plugin, LSP, and deprecation logs** | `:messages` |

## License
Licensed under the [Apache License, Version 2.0](LICENSE).
