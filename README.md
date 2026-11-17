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

## Keybindings
Default `<leader>` key is `Space`:

* `<leader>mb` — Toggle breakpoint (max 5)
* `<leader>mc` — Continue / Start execution
* `<leader>mn` — Step over
* `<leader>mS` — Step into
* `<leader>ms` — Inspect call stack
* `<leader>mv` / `<leader>mi` — Inspect variable / Evaluate expression
* `<leader>ml` / `<leader>mr` — List / Reset breakpoints
* `<leader>mq` — Terminate session
* `<leader>mV` — Debugger Toggle Verbose Mode

## License
Licensed under the [Apache License, Version 2.0](LICENSE).
