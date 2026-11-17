# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 reeloc10

def compute_telemetry_rate(base_hz: int) -> float:
    multiplier = 1.5
    undefined_variable = 1
    # Pylsp / Ruff will catch 'undefined_variable' immediately
    return base_hz * multiplier * undefined_variable 

if __name__ == "__main__":
    rate = compute_telemetry_rate(60)
    print(f"Active rate: {rate}")
