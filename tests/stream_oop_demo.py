# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 reeloc10

from enum import Enum, auto
from dataclasses import dataclass
from collections.abc import Callable
import time
import sys

class LogLevel(Enum):
    INFO = auto()
    METRIC = auto()
    DEBUG = auto()

@dataclass
class TelemetryPacket:
    source: str
    metric_type: str
    value: float
    unit: str

class StreamComponent:
    """Base class demonstrating inheritance and encapsulation."""
    def __init__(self, name: str) -> None:
        self.name = name
        self._active = True

    def emit(self, level: LogLevel, message: str) -> None:
        if not self._active:
            return
        prefix = f"\033[35m[{self.name}]\033[0m \033[36m[{level.name}]\033[0m"
        sys.stdout.write(f"{prefix} {message}\n")
        sys.stdout.flush()

class TelemetryEngine(StreamComponent):
    """Derived telemetry processor utilizing functional lambdas and higher-order filtering."""
    def __init__(self) -> None:
        super().__init__("TelemetryEngine")
        self._packets: list[TelemetryPacket] = []

    def ingest(self, packet: TelemetryPacket) -> None:
        self._packets.append(packet)
        self.emit(LogLevel.METRIC, f"Recorded {packet.metric_type} = {packet.value}{packet.unit} from {packet.source}")

    def filter_high_temps(self, threshold: float) -> list[TelemetryPacket]:
        # Functional lambda filtering for high-value metrics
        is_hot: Callable[[TelemetryPacket], bool] = lambda p: p.metric_type == "Temp" and p.value > threshold
        return list(filter(is_hot, self._packets))

def main() -> None:
    engine = TelemetryEngine()
    engine.emit(LogLevel.INFO, "Initializing OOP & Functional Python stream pipeline...")
    time.sleep(0.4)

    # Simulate incoming telemetry structs
    packets = [
        TelemetryPacket("GPU-0", "Temp", 42.5, "°C"),
        TelemetryPacket("CPU-0", "Temp", 68.2, "°C"),
        TelemetryPacket("RAM-0", "Usage", 34.0, "%")
    ]

    for pkt in packets:
        engine.ingest(pkt)
        time.sleep(0.5)

    hot_items = engine.filter_high_temps(50.0)
    engine.emit(LogLevel.DEBUG, f"Filtered {len(hot_items)} high-temperature alerts using lambda predicate.")
    engine.emit(LogLevel.INFO, "Stream demo payload ready.")

if __name__ == "__main__":
    main()
