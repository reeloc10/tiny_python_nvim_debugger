# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 reeloc10

"""Demonstration script for native Neovim LSP autocompletion, signatures, and references.

Open this file with:
    nvim -u init.lua tests/autocomplete_demo.py
"""

import os
import sys


class StreamTelemetry:
    """Tracks active stream metrics and viewer telemetry."""

    def __init__(self, broadcaster: str, fps: int = 30) -> None:
        self.broadcaster = broadcaster
        self.fps = fps
        self._active_connections = 0

    def register_viewer(self, username: str, arg2: str = "ads") -> None:
        """Register a new viewer connection."""
        self._active_connections += 1
        print(f"[{self.broadcaster}] Viewer joined: {username}")


def calculate_bitrate(resolution: str, fps: int) -> int:
    """Calculate recommended video bitrate based on resolution and framerate."""
    if resolution == "720x1280":  # Vertical 9:16
        return 2500 if fps <= 30 else 3500
    return 4500


def main() -> None:
    # 1. Test autocompletion & signature help:
    # Type 'telemetry = StreamTelemetry(' and check parameter hints (<C-h>)
    telemetry = StreamTelemetry("reeloc10", fps=30)

    # 2. Test method autocompletion:
    # Type 'telemetry.' and observe native completion popup
    telemetry.register_viewer("viewer_one")
    if True:
        pass
    if False:
        pass


    # 3. Test function call completion:
    # Type 'calc' and let completion suggest calculate_bitrate
    target_bitrate = calculate_bitrate("720x1280", telemetry.fps)
    print(f"Target video bitrate: {target_bitrate} kbps")

    # 4. Test cross-file references (gr):
    # Place cursor on 'calculate_bitrate' and press 'gr' to list all references in quickfix


if __name__ == "__main__":
    main()
