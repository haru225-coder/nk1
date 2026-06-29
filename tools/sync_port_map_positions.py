#!/usr/bin/env python3
"""Sync ports.json position from map_pos using meta.map_layout.world_bounds."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PORTS = ROOT / "data" / "ports.json"

# Refined geographic pins (u=west→east, v=north→south)
MAP_POS: dict[str, tuple[float, float]] = {
    "mingzhou": (0.72, 0.26),
    "ganpu": (0.70, 0.28),
    "wenzhou": (0.74, 0.30),
    "xinghua": (0.68, 0.34),
    "quanzhou": (0.66, 0.38),
    "zhangzhou": (0.64, 0.42),
    "penghu": (0.74, 0.38),
    "keelung": (0.78, 0.35),
    "ryukyu": (0.84, 0.40),
    "guangzhou": (0.54, 0.46),
    "tunmen": (0.52, 0.48),
    "jiaozhi": (0.34, 0.52),
    "champa": (0.28, 0.58),
    "xuwen": (0.36, 0.54),
    "qiongzhou": (0.40, 0.56),
    "bugan": (0.18, 0.54),
    "longyamen": (0.12, 0.68),
    "sanfoqi": (0.10, 0.74),
    "yeshou": (0.08, 0.80),
    "hakata": (0.92, 0.30),
    "kagoshima": (0.90, 0.36),
    "tsushima": (0.88, 0.22),
    "jeju": (0.84, 0.20),
    "byland": (0.82, 0.16),
}


def uv_to_world(u: float, v: float, wb: dict) -> dict[str, int]:
    x_min, x_max = wb["x_min"], wb["x_max"]
    y_min, y_max = wb["y_min"], wb["y_max"]
    return {
        "x": int(x_min + u * (x_max - x_min)),
        "y": int(y_min + v * (y_max - y_min)),
    }


def main() -> None:
    data = json.loads(PORTS.read_text(encoding="utf-8"))
    wb = data["meta"]["map_layout"]["world_bounds"]
    for port in data["ports"]:
        pid = port["id"]
        if pid not in MAP_POS:
            continue
        u, v = MAP_POS[pid]
        port["map_pos"] = {"u": round(u, 3), "v": round(v, 3)}
        port["position"] = uv_to_world(u, v, wb)
    PORTS.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"synced {len(MAP_POS)} ports")


if __name__ == "__main__":
    main()