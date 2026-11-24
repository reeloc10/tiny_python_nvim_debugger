# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 reeloc10

import os
import sys  # Ruff will flag this as unused (F401)

def compute_telemetry_rate(base_hz: int) -> float:
    multiplier = 1.5
    # Pylsp / Ruff will catch 'undefined_variable' immediately
    return base_hz * multiplier * undefined_variable 

if __name__ == "__main__":
    rate = compute_telemetry_rate(60)
    print(f"Active rate: {rate}")
