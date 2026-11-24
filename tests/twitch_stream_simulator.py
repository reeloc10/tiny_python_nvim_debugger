# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 reeloc10

import time
import sys

def stream_telemetry_loop():
    print("\033[32m[twitch_debugger] Initializing stream telemetry monitor...\033[0m")
    time.sleep(0.5)

    mock_events = [
        ("INFO", "Connected to local Unix domain socket /dev/shm/debugger.sock"),
        ("CHAT", "user 'stream_watcher42': Loving the Neovim setup!"),
        ("METRIC", "CPU Core 0: 42°C | Frame Rate: 30.0 FPS (OBS target)"),
        ("CHAT", "user 'vim_enthusiast': Is that tab completion ?"),
        ("METRIC", "Memory RSS: 14.2 MB | Active Scratch Buffers: 1"),
    ]

    for level, msg in mock_events:
        color = "\033[36m" if level == "CHAT" else ("\033[33m" if level == "METRIC" else "\033[34m")
        sys.stdout.write(f"{color}[{level}]\033[0m {msg}\n")
        sys.stdout.flush()
        time.sleep(0.8)

    print("\033[32m[twitch_debugger] Telemetry cycle complete. Ready for live debugging.\033[0m")

if __name__ == "__main__":
    stream_telemetry_loop()
