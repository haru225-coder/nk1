#!/usr/bin/env python3
"""Generate strategic map assets from ports.json (single source of truth)."""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PORTS = ROOT / "data" / "ports.json"
OUT = ROOT / "assets" / "map_nanhai.png"
OUT_MASK = ROOT / "assets" / "map_nanhai_sea_mask.png"
OUT_DEBUG = ROOT / "assets" / "map_nanhai_debug.png"
OUT_ROUTES = ROOT / "assets" / "map_nanhai_routes.png"
BASE_WIDTH = 4096
INSET = 48

LAND = (0xCC, 0xB4, 0x7C)
LAND_HI = (0xD8, 0xC4, 0x90)
LAND_LO = (0xA4, 0x8C, 0x5C)
LAND_OUTLINE = (0x5A, 0x45, 0x2E)
SEA_DEEP = (0x2E, 0x5F, 0x7A)
ROUTE_RGBA = (0xC4, 0xA8, 0x5C, 140)

# (uv polygon, fill) — shared by RGB map and sea mask.
LAND_POLYGONS: list[tuple[list[tuple[float, float]], tuple[int, int, int]]] = [
    (
        [(0.05, 0.48), (0.22, 0.46), (0.30, 0.56), (0.26, 0.72), (0.14, 0.82), (0.04, 0.76), (0.02, 0.58)],
        LAND_LO,
    ),
    ([(0.10, 0.72), (0.22, 0.70), (0.24, 0.80), (0.12, 0.86)], LAND_LO),
    (
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
        LAND,
    ),
    ([(0.66, 0.18), (0.76, 0.20), (0.78, 0.28), (0.72, 0.32), (0.66, 0.30)], LAND_HI),
    ([(0.38, 0.54), (0.42, 0.53), (0.44, 0.58), (0.40, 0.60), (0.36, 0.57)], LAND_LO),
    ([(0.74, 0.34), (0.78, 0.33), (0.80, 0.38), (0.78, 0.42), (0.74, 0.41), (0.72, 0.37)], LAND_HI),
    ([(0.82, 0.36), (0.86, 0.38), (0.88, 0.42), (0.86, 0.44), (0.82, 0.42)], LAND_LO),
    ([(0.80, 0.12), (0.84, 0.13), (0.86, 0.22), (0.84, 0.28), (0.80, 0.26), (0.78, 0.18)], LAND_LO),
    (
        [(0.88, 0.16), (0.96, 0.18), (0.98, 0.30), (0.96, 0.40), (0.90, 0.42), (0.86, 0.34), (0.86, 0.22)],
        LAND,
    ),
]


def load_data() -> tuple[dict, list[dict], tuple[int, int]]:
    data = json.loads(PORTS.read_text(encoding="utf-8"))
    wb = data["meta"]["map_layout"]["world_bounds"]
    world_w = wb["x_max"] - wb["x_min"]
    world_h = wb["y_max"] - wb["y_min"]
    size = (BASE_WIDTH, round(BASE_WIDTH * world_h / world_w))
    return data["meta"]["map_layout"], data["ports"], size


def uv_px(u: float, v: float, size: tuple[int, int]) -> tuple[int, int]:
    w = size[0] - INSET * 2
    h = size[1] - INSET * 2
    return (INSET + int(u * w), INSET + int(v * h))


def uv_poly(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    fill: tuple[int, int, int],
    size: tuple[int, int],
    *,
    outline: tuple[int, int, int] | None = LAND_OUTLINE,
    width: int = 2,
) -> None:
    px_pts = [uv_px(u, v, size) for u, v in points]
    draw.polygon(px_pts, fill=fill, outline=outline, width=width)


def draw_sea_gradient(size: tuple[int, int]) -> Image.Image:
    img = Image.new("RGB", size, SEA_DEEP)
    draw = ImageDraw.Draw(img)
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        draw.line(
            [(0, y), (size[0], y)],
            fill=(int(0x2A + 10 * t), int(0x58 + 14 * t), int(0x72 + 12 * t)),
        )
    return img


def draw_base_map(size: tuple[int, int]) -> Image.Image:
    img = draw_sea_gradient(size)
    draw = ImageDraw.Draw(img)
    for poly, fill in LAND_POLYGONS:
        uv_poly(draw, poly, fill, size)

    frame_w = max(4, size[0] // 340)
    inner_w = max(2, frame_w - 1)
    draw.rectangle([(12, 12), (size[0] - 13, size[1] - 13)], outline=(0x8A, 0x68, 0x28), width=frame_w)
    draw.rectangle([(20, 20), (size[0] - 21, size[1] - 21)], outline=(0x5A, 0x42, 0x18), width=inner_w)
    title_w = min(280, size[0] // 14)
    draw.rectangle([(24, 24), (24 + title_w, 72)], fill=(0x24, 0x18, 0x0C), outline=(0x8A, 0x68, 0x28))
    draw.text((40, 38), "東南海圖", fill=(0xEC, 0xDC, 0xA8))
    return img


def draw_sea_mask(size: tuple[int, int]) -> Image.Image:
    # White = sea (shader visible), black = land.
    mask = Image.new("L", size, 255)
    draw = ImageDraw.Draw(mask)
    for poly, _fill in LAND_POLYGONS:
        draw.polygon([uv_px(u, v, size) for u, v in poly], fill=0)
    return mask


def route_key(a: str, b: str) -> tuple[str, str]:
    return (a, b) if a < b else (b, a)


def draw_dashed_line(
    draw: ImageDraw.ImageDraw,
    p0: tuple[int, int],
    p1: tuple[int, int],
    color: tuple[int, int, int, int],
    *,
    dash: int = 18,
    gap: int = 12,
    width: int = 3,
) -> None:
    x0, y0 = p0
    x1, y1 = p1
    length = math.hypot(x1 - x0, y1 - y0)
    if length < 1:
        return
    dx = (x1 - x0) / length
    dy = (y1 - y0) / length
    pos = 0.0
    drawing = True
    while pos < length:
        seg = dash if drawing else gap
        seg = min(seg, length - pos)
        sx = x0 + dx * pos
        sy = y0 + dy * pos
        ex = x0 + dx * (pos + seg)
        ey = y0 + dy * (pos + seg)
        if drawing:
            draw.line([(sx, sy), (ex, ey)], fill=color, width=width)
        pos += seg
        drawing = not drawing


def draw_routes(img: Image.Image, ports: list[dict], size: tuple[int, int]) -> Image.Image:
    out = img.convert("RGBA")
    draw = ImageDraw.Draw(out)
    by_id = {p["id"]: p for p in ports}
    drawn: set[tuple[str, str]] = set()
    for port in ports:
        from_id = port.get("id", "")
        mp = port.get("map_pos")
        if not mp or from_id == "":
            continue
        p0 = uv_px(float(mp["u"]), float(mp["v"]), size)
        for conn_id in port.get("connections", []):
            key = route_key(from_id, conn_id)
            if key in drawn:
                continue
            other = by_id.get(conn_id)
            if other is None:
                continue
            omp = other.get("map_pos")
            if not omp:
                continue
            drawn.add(key)
            p1 = uv_px(float(omp["u"]), float(omp["v"]), size)
            draw_dashed_line(draw, p0, p1, ROUTE_RGBA, dash=22, gap=14, width=4)
    return out


def draw_port_markers(img: Image.Image, ports: list[dict], size: tuple[int, int], *, debug: bool) -> Image.Image:
    out = img.copy()
    draw = ImageDraw.Draw(out)
    for port in ports:
        mp = port.get("map_pos")
        if not mp:
            continue
        px, py = uv_px(float(mp["u"]), float(mp["v"]), size)
        status = port.get("status", "")
        if debug:
            r = 8 if status == "main" else 6
            color = (0x2A, 0xFF, 0x4A) if status == "main" else (0x6A, 0xFF, 0x8A)
            draw.ellipse([(px - r, py - r), (px + r, py + r)], fill=color, outline=(0x10, 0x30, 0x10), width=2)
            label = port.get("name", port.get("id", ""))
            tw = len(label) * 14 + 8
            draw.rectangle([(px + 10, py - 14), (px + 10 + tw, py + 6)], fill=(0x10, 0x10, 0x08))
            draw.text((px + 14, py - 12), label, fill=(0xFF, 0xF0, 0xC0))
        else:
            r = 4 if status == "main" else 3
            color = (0x4A, 0x9A, 0x5A) if status == "main" else (0x6A, 0x8A, 0x5A)
            draw.ellipse([(px - r, py - r), (px + r, py + r)], fill=color, outline=(0x2A, 0x3A, 0x20))
    return out


def main() -> None:
    _layout, ports, size = load_data()
    base = draw_base_map(size)
    mask = draw_sea_mask(size)
    routes = draw_routes(base, ports, size)
    debug = draw_port_markers(routes.convert("RGB"), ports, size, debug=True)

    base.save(OUT, optimize=True)
    mask.save(OUT_MASK, optimize=True)
    routes.save(OUT_ROUTES, optimize=True)
    debug.save(OUT_DEBUG, optimize=True)

    aspect = size[0] / size[1]
    print(f"wrote {OUT} ({size[0]}x{size[1]}, aspect={aspect:.4f})")
    print(f"wrote {OUT_MASK}")
    print(f"wrote {OUT_ROUTES}")
    print(f"wrote {OUT_DEBUG}")
    print(f"ports with routes: {len(ports)}")


if __name__ == "__main__":
    main()