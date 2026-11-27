# Tiny Debugger, Source Control & LSP Integration

A minimal dependency, ~5,000-line modular Neovim setup combining a custom Python debugger using RAM-backed Unix domain sockets (`/dev/shm`) and `sys.settrace`, a streamlined `pylsp` and `ruff` linting configuration, embedded source control tools (`git_plugin.lua`, `git_log.lua`, `git_blame.lua`, `git_stash.lua`), high-performance grep searching (`fastgrep.lua`), and syntax parsing via Tree-sitter.

## Preferred Documentation & Feedback Channel
Live demos, Q&A, and feedback: [twitch.tv/reeloc10](https://www.twitch.tv/reeloc10)

## Environment & Dependencies
Tested on Fedora 45 using system RPM packages from the official repositories:
- `python3-lsp-server-1.14.0-1.fc45.noarch`
- `ruff-0.17.4-1.fc45.x86_64`

### Optional Dependencies
Suggested though not mandatory; some functionality or terminal enhancements may be omitted if missing:
- `ripgrep-15.2.0-1.fc45.x86_64`
- `libtree-sitter-python-0.25.0-4.fc45.x86_64`
- `libtree-sitter-python-devel-0.25.0-4.fc45.x86_64`
- `zsh-5.9.2-3.fc45.x86_64` *(optional: shell environment)*
- `zsh-autosuggestions-0.7.1-5.fc45.noarch` *(optional)*
- `zsh-syntax-highlighting-0.8.0-8.fc45.noarch` *(optional)*

## Core Modules & Architecture
- **Debugger (`tiny_debugger.lua` / `.py`):** RAM-socket tracing bypassing DAP.
- **Source Control (`git_plugin.lua`, `git_log.lua`, `git_blame.lua`, `git_stash.lua`):** Native Git integration, blame, commit history inspector, and interactive 3-window stash browser.
- **Search (`fastgrep.lua`):** Fast Ripgrep-backed text navigation.
- **Syntax (`treesitter.lua`):** Native incremental parsing.
- **LSP & Linting (`pylsp_config.lua`):** Python analysis and formatting.

## Testing

### Development

```bash
nvim -u <cloned folder>/init.lua filename.py
```
### Debugger
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
| **Launch target & debug** | *N/A* | `:TinyLaunch [args]` |
| **Continue / Start execution** | `<leader>mc` | `:TinyContinue` |
| **Step over** | `<leader>mn` | `:TinyNext` |
| **Step into** | `<leader>mS` | `:TinyStep` |
| **Inspect call stack** | `<leader>ms` | `:TinyStack` |
| **Toggle variables sidebar** | `<leader>mu` | `:TinyVariables` |
| **Inspect variable** | `<leader>mv` | `:TinyEvalCword` |
| **Evaluate expression** | `<leader>mi` | `:TinyEvalInput` |
| **List breakpoints** | `<leader>ml` | `:TinyListBreakpoints` |
| **Reset breakpoints** | `<leader>mr` | `:TinyResetBreakpoints` |
| **Terminate session** | `<leader>mq` | `:TinyQuit` |
| **Toggle Verbose Mode** | `<leader>mV` | `:TinyVerbose` |

### Git Integration & 3-Window Browsers
| Action | Leader Shortcut | Ex Command | Description |
| :--- | :--- | :--- | :--- |
| **Toggle GitSigns** | — | `:GitSignsToggle` | Toggle git hunk change signs in signcolumn |
| **View Git Diff** | — | `:GitSignsDiff` | View current unstaged diff |
| **Inspect Git Hunk** | — | `:GitSignsInspect` | Inspect hunk under cursor |
| **Revert File to HEAD** | — | `:GitResetFile` | Revert working file to HEAD |
| **Commit with Verbose Diff** | — | `:GitCommitVerbose` | Commit changes with split diff preview |
| **Pull Diff from Other Split** | — | `:diffget` | Pull hunk changes from adjacent diff split |
| **Push Diff to Other Split** | — | `:diffput` | Push hunk changes to adjacent diff split |
| **Toggle Git Blame Virtual Text** | `<leader>ga` | `:GitBlameToggle` | Toggle inline git blame annotations |
| **Git Blame Current Line** | `<leader>gb` | `:GitBlameLine` | Show blame details for current line in float |
| **Toggle Git Blame Split** | `<leader>gB` | `:GitBlameSplit` | Toggle left-split full-file blame sidebar |
| **Open Commit History Browser** | — | `:GitHistory` | Open interactive 3-window commit history inspector |
| **Open Interactive Stash Browser**| `<leader>gS` | `:GitStashBrowser` | Open interactive 3-window git stash browser |

#### Commit History Browser Keybindings (`git_log.lua`)
When `:GitHistory` is open on a file:
* **`<CR>`:** Inspect commit diff (parent vs selected revision) in upper side-by-side vimdiff panes.
* **`<Tab>`:** Expand/collapse full multi-line commit message body inline.
* **`q`:** Close history browser session and restore original window layout.

#### Git Stash Browser Keybindings (`git_stash.lua`)
When `:GitStashBrowser` is open on a file:
* **`<CR>`:** Inspect stashed diff (parent vs stashed state) in upper side-by-side vimdiff panes.
* **`<Esc>`:** Dismiss upper diff preview panes and restore the working file buffer above the stash list.
* **`a`:** Apply selected stash and reload buffer from disk (`e!`).
* **`p`:** Pop selected stash (applies, drops from reflog, reloads buffer, and refreshes list).
* **`d`:** Permanently drop selected stash with confirmation prompt.
* **`s`:** Store current file changes into a new stash with a user-editable message prompt and reset working copy to HEAD.
* **`q`:** Close stash browser session and restore original window layout.

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
| **Toggle file explorer (working directory)** | `:ExplorerToggle` |
| **Toggle file explorer (active buffer directory)** | `:ExplorerToggleBuffer` |
| **Switch active shell to Bash** | `:lua vim.o.shell = '/bin/bash'` |
| **Switch active shell to Zsh** | `:lua vim.o.shell = '/bin/zsh'` |
| **Open terminal running Bash** | `:split \| terminal bash` |
| **Open terminal running Zsh** | `:split \| terminal zsh` |
| **Inspect mapping origin and scope** | `:verbose nmap <Space>e` |
| **View plugin, LSP, and deprecation logs** | `:messages` |
| **List active and hidden buffers (and terminal jobs)** | `:buffers` |
| **Switch between open buffers** | `:buffer <number>` (or `:bnext` / `:bprevious`) |

### Built-in File Explorer (`netrw`)
Minimal dependency file browsing and management using Neovim's native `netrw` explorer.

| Task | Command |
| :--- | :--- |
| **Open file explorer in current window** | `:Explore` |
| **Open file explorer in vertical split** | `:Vexplore` |
| **Open file explorer in horizontal split** | `:Sexplore` |
| **Navigate up one directory (or open explorer)** | `-` |
| **Create a new file / directory** | `%` / `d` |
| **Rename / delete entry under cursor** | `R` / `D` |
| **Cycle view styles (thin, long, wide, tree)** | `i` |
| **Cycle sort order (name, time, size, ext)** | `s` |
| **Toggle hidden dotfiles / top help banner** | `gh` / `I` |

## License
Licensed under the [Apache License, Version 2.0](LICENSE).
