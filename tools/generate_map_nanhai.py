#!/usr/bin/env python3
"""Generate strategic map aligned to ports.json map_pos coordinates."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "map_nanhai.png"
PORTS = ROOT / "data" / "ports.json"
SIZE = (640, 480)
INSET = 28


def uv_px(u: float, v: float) -> tuple[int, int]:
    w = SIZE[0] - INSET * 2
    h = SIZE[1] - INSET * 2
    return (INSET + int(u * w), INSET + int(v * h))


def uv_poly(draw: ImageDraw.ImageDraw, points: list[tuple[float, float]], fill: tuple[int, int, int]) -> None:
    draw.polygon([uv_px(u, v) for u, v in points], fill=fill, outline=(0x5a, 0x45, 0x2e))


def main() -> None:
    ports = json.loads(PORTS.read_text(encoding="utf-8"))["ports"]
    img = Image.new("RGB", SIZE, (0x2e, 0x5f, 0x7a))
    draw = ImageDraw.Draw(img)

    # Water gradient
    for y in range(SIZE[1]):
        t = y / max(SIZE[1] - 1, 1)
        draw.line(
            [(0, y), (SIZE[0], y)],
            fill=(int(0x2a + 8 * t), int(0x58 + 12 * t), int(0x72 + 10 * t)),
        )

    land = (0xcc, 0xb4, 0x7c)
    land_hi = (0xd8, 0xc4, 0x90)
    land_lo = (0xa4, 0x8c, 0x5c)

    # Southeast Asia + Indochina (west)
    uv_poly(
        draw,
        [(0.05, 0.48), (0.22, 0.46), (0.30, 0.56), (0.26, 0.72), (0.14, 0.82), (0.04, 0.76), (0.02, 0.58)],
        land_lo,
    )
    uv_poly(draw, [(0.10, 0.72), (0.22, 0.70), (0.24, 0.80), (0.12, 0.86)], land_lo)

    # Lingnan / Fujian / Zhejiang coast (center-right arc)
    uv_poly(
        draw,
        [
            (0.48, 0.18),
            (0.58, 0.20),
            (0.66, 0.28),
            (0.70, 0.36),
            (0.68, 0.44),
            (0.62, 0.48),
            (0.54, 0.50),
            (0.46, 0.48),
            (0.40, 0.54),
            (0.34, 0.56),
            (0.32, 0.48),
            (0.36, 0.36),
            (0.42, 0.24),
        ],
        land,
    )

    # Jiangnan bump
    uv_poly(draw, [(0.66, 0.18), (0.76, 0.20), (0.78, 0.28), (0.72, 0.32), (0.66, 0.30)], land_hi)

    # Hainan
    uv_poly(draw, [(0.38, 0.54), (0.42, 0.53), (0.44, 0.58), (0.40, 0.60), (0.36, 0.57)], land_lo)

    # Taiwan
    uv_poly(draw, [(0.74, 0.34), (0.78, 0.33), (0.80, 0.38), (0.78, 0.42), (0.74, 0.41), (0.72, 0.37)], land_hi)

    # Ryukyu chain
    uv_poly(draw, [(0.82, 0.36), (0.86, 0.38), (0.88, 0.42), (0.86, 0.44), (0.82, 0.42)], land_lo)

    # Korea
    uv_poly(draw, [(0.80, 0.12), (0.84, 0.13), (0.86, 0.22), (0.84, 0.28), (0.80, 0.26), (0.78, 0.18)], land_lo)

    # Japan
    uv_poly(
        draw,
        [(0.88, 0.16), (0.96, 0.18), (0.98, 0.30), (0.96, 0.40), (0.90, 0.42), (0.86, 0.34), (0.86, 0.22)],
        land,
    )

    # Frame
    draw.rectangle([(10, 10), (SIZE[0] - 11, SIZE[1] - 11)], outline=(0x8a, 0x68, 0x28), width=3)
    draw.rectangle([(16, 16), (SIZE[0] - 17, SIZE[1] - 17)], outline=(0x5a, 0x42, 0x18), width=1)
    draw.rectangle([(20, 20), (168, 50)], fill=(0x24, 0x18, 0x0c), outline=(0x8a, 0x68, 0x28))
    draw.text((32, 28), "東南海圖", fill=(0xec, 0xdc, 0xa8))

    # Port anchors (debug / layout guide — subtle)
    for port in ports:
        mp = port.get("map_pos")
        if not mp:
            continue
        px, py = uv_px(mp["u"], mp["v"])
        status = port.get("status", "")
        r = 3 if status == "main" else 2
        color = (0x4a, 0x9a, 0x5a) if status == "main" else (0x6a, 0x8a, 0x5a)
        draw.ellipse([(px - r, py - r), (px + r, py + r)], fill=color, outline=(0x2a, 0x3a, 0x20))

    img.save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()