#!/usr/bin/env python3
"""Generate East Asia strategic map assets from real coastline polygons.

Outputs map_east_asia.png + sea_mask + debug + routes into assets/.
Coastline polygons use real lat/lon, projected to the UV frame defined in
ports.json meta.map_layout.world_bounds (u=(lon-92)/42, v=(42-lat)/52).
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PORTS = ROOT / "data" / "ports.json"
OUT = ROOT / "assets" / "map_east_asia.png"
OUT_MASK = ROOT / "assets" / "map_east_asia_sea_mask.png"
OUT_DEBUG = ROOT / "assets" / "map_east_asia_debug.png"
OUT_ROUTES = ROOT / "assets" / "map_east_asia_routes.png"
BASE_WIDTH = 8192
INSET = 48

LAND = (0xCC, 0xB4, 0x7C)
LAND_HI = (0xD8, 0xC4, 0x90)
LAND_LO = (0xA4, 0x8C, 0x5C)
LAND_OUTLINE = (0x5A, 0x45, 0x2E)
SEA_DEEP = (0x2E, 0x5F, 0x7A)
ROUTE_RGBA = (0xC4, 0xA8, 0x5C, 140)
RIVER_RGBA = (0x6A, 0x96, 0xC4, 160)

LON_MIN, LON_MAX = 92.0, 134.0
LAT_MIN, LAT_MAX = -10.0, 42.0


def project(lat: float, lon: float) -> tuple[float, float]:
    return (lon - LON_MIN) / (LON_MAX - LON_MIN), (LAT_MAX - lat) / (LAT_MAX - LAT_MIN)


# (latlon polygon, fill) — real coastlines, clockwise winding.
LAND_POLYGONS: list[tuple[list[tuple[float, float]], tuple[int, int, int]]] = [
    # 亚洲大陆：中国东岸+中南半岛+马来半岛+缅甸，北/西边图外闭合（朝鲜段拆出单独画避免自交）
    ([
        (43, 130), (40.5, 124), (40, 121.5), (38, 121), (37.5, 122.5), (36, 120),
        (35, 119), (32.5, 121.5), (31.2, 121.8), (30, 121.5), (28.7, 121.5),
        (27.8, 120.7), (26.5, 119.8), (25.4, 119), (24.9, 118.6), (24, 117.5),
        (23, 116.5), (22.5, 113.8), (21.8, 112.5), (21, 110.5), (20.3, 110.5),
        (20.5, 107), (20.9, 106.5), (19, 106), (18, 105.8), (16.5, 107.5),
        (15.9, 108.3), (13.5, 109.3), (12.5, 109.5), (11, 107.5), (10.5, 107),
        (10.5, 104), (11, 103), (13.5, 100.5), (11, 99.5), (9.5, 99), (8, 98.5),
        (5, 100.5), (2.5, 102), (1.3, 104), (2.5, 101.5), (4, 100.5), (7, 98.5),
        (9.5, 98), (12, 97.5), (13, 97.8), (16, 95), (18, 94.5), (20, 93.5),
        (22, 91), (43, 91), (43, 130),
    ], LAND),
    # 朝鲜半岛（单独，确保平壤落陆）
    ([
        (43, 129), (40, 129), (38, 128.5), (36.5, 129), (35.5, 129.5), (35.2, 128.8),
        (35.8, 126.5), (36.5, 126), (37.5, 126), (38.5, 125.3), (39, 125), (39.5, 125.8),
        (40, 125.5), (40.5, 124), (43, 124), (43, 129),
    ], LAND),
    # 九州+本州西
    ([
        (33.8, 130), (33.5, 130.4), (32.5, 130.5), (31.5, 130.6), (31, 130.8), (31.5, 131),
        (32, 131.8), (33, 132), (33.8, 131.5), (34, 131), (34.5, 131.5), (35, 132), (35.5, 132.5),
        (34.5, 131), (34, 130.5), (33.8, 130),
    ], LAND),
    # 四国
    ([(33.5, 133), (34, 134), (33.5, 134.5), (33, 133.5), (33.5, 133)], LAND_LO),
    # 对马岛
    ([(34.5, 129.1), (34.5, 129.5), (34.1, 129.5), (34.1, 129.1), (34.5, 129.1)], LAND_HI),
    # 济州岛
    ([(33.7, 126.3), (33.7, 126.8), (33.2, 126.8), (33.2, 126.3), (33.7, 126.3)], LAND_LO),
    # 琉球散列小岛
    ([(26.8, 128), (26.3, 128.1), (25.8, 127.7), (26.2, 127.5), (26.8, 128)], LAND_LO),
    ([(28.2, 129.3), (27.8, 129.4), (27.6, 129.1), (28, 128.9), (28.2, 129.3)], LAND_LO),
    ([(24.6, 123.5), (24.2, 123.6), (24, 123.2), (24.4, 123.1), (24.6, 123.5)], LAND_LO),
    # 台湾
    ([
        (25.3, 121.7), (25, 121.5), (24, 121), (23, 120.5), (22.5, 120.3),
        (23, 121), (24, 121.5), (25.2, 122), (25.3, 121.7),
    ], LAND),
    # 澎湖
    ([(23.7, 119.35), (23.7, 119.85), (23.45, 119.85), (23.45, 119.35), (23.7, 119.35)], LAND_LO),
    # 海南
    ([(20.2, 110.5), (19.5, 109), (18.2, 109.2), (18.5, 111), (19.8, 111), (20.2, 110.5)], LAND_LO),
    # 苏门答腊（东南缘东延确保巨港落陆）
    ([
        (5.5, 95), (4, 96.5), (2, 98), (0, 99), (-1, 101), (-2, 103), (-2.8, 104.5),
        (-3.5, 105.5), (-5.5, 106), (-6, 105), (-5, 103), (-3, 101.5), (0, 99.5), (3, 97.5), (5.5, 95),
    ], LAND),
    # 爪哇
    ([
        (-6.5, 105), (-7, 108), (-7.5, 110.4), (-7.8, 112), (-8, 114), (-8.5, 114),
        (-8, 111), (-7.5, 110), (-7, 108), (-6.5, 105),
    ], LAND_LO),
    # 婆罗洲
    ([
        (7.3, 117), (6, 117.5), (4, 118), (1, 118), (-2, 117), (-4, 116),
        (-3, 112), (-1, 110), (2, 109), (4, 109.5), (6, 110.5), (7.3, 117),
    ], LAND),
    # 菲律宾吕宋
    ([
        (18.5, 121), (16.5, 122), (14.5, 122), (13.5, 121.5), (13.8, 120.5),
        (15, 120), (16.5, 119.5), (18.3, 120.3), (18.5, 121),
    ], LAND_LO),
    # 菲律宾民都洛（加宽确保麻逸落陆）
    ([(13.5, 119.8), (13.5, 121), (11.5, 121.2), (10.8, 120.3), (12, 119.3), (13.5, 119.8)], LAND_LO),
    # 菲律宾棉兰老
    ([(9.5, 126), (8, 126), (6.5, 125.5), (7, 124), (8.5, 123.5), (9.5, 125), (9.5, 126)], LAND_LO),
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
        px = [uv_px(*project(lat, lon), size) for lat, lon in poly]
        draw.polygon(px, fill=fill, outline=LAND_OUTLINE, width=2)

    frame_w = max(4, size[0] // 340)
    inner_w = max(2, frame_w - 1)
    draw.rectangle([(12, 12), (size[0] - 13, size[1] - 13)], outline=(0x8A, 0x68, 0x28), width=frame_w)
    draw.rectangle([(20, 20), (size[0] - 21, size[1] - 21)], outline=(0x5A, 0x42, 0x18), width=inner_w)
    title_w = min(280, size[0] // 14)
    draw.rectangle([(24, 24), (24 + title_w, 72)], fill=(0x24, 0x18, 0x0C), outline=(0x8A, 0x68, 0x28))
    draw.text((40, 38), "東南亞海圖", fill=(0xEC, 0xDC, 0xA8))
    return img


def draw_sea_mask(size: tuple[int, int]) -> Image.Image:
    mask = Image.new("L", size, 255)  # 白=海
    draw = ImageDraw.Draw(mask)
    for poly, _fill in LAND_POLYGONS:
        px = [uv_px(*project(lat, lon), size) for lat, lon in poly]
        draw.polygon(px, fill=0)  # 黑=陆
    return mask


def route_key(a: str, b: str) -> tuple[str, str]:
    return (a, b) if a < b else (b, a)


def river_route_keys(ports: list[dict]) -> set[tuple[str, str]]:
    keys: set[tuple[str, str]] = set()
    for port in ports:
        from_id = str(port.get("id", ""))
        if not from_id:
            continue
        for route in port.get("river_routes", []):
            if not isinstance(route, dict):
                continue
            to_id = str(route.get("to", ""))
            if to_id:
                keys.add(route_key(from_id, to_id))
    return keys


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
        if drawing:
            draw.line(
                [(x0 + dx * pos, y0 + dy * pos), (x0 + dx * (pos + seg), y0 + dy * (pos + seg))],
                fill=color, width=width,
            )
        pos += seg
        drawing = not drawing


def draw_routes(img: Image.Image, ports: list[dict], size: tuple[int, int]) -> Image.Image:
    out = img.convert("RGBA")
    draw = ImageDraw.Draw(out)
    by_id = {p["id"]: p for p in ports}
    drawn: set[tuple[str, str]] = set()
    river_keys = river_route_keys(ports)
    for port in ports:
        from_id = port.get("id", "")
        mp = port.get("map_pos")
        if not mp or from_id == "":
            continue
        p0 = uv_px(float(mp["u"]), float(mp["v"]), size)
        for conn_id in port.get("connections", []):
            conn_str = str(conn_id)
            key = route_key(from_id, conn_str)
            if key in river_keys:
                continue
            if key in drawn:
                continue
            other = by_id.get(conn_str)
            if other is None or not other.get("map_pos"):
                continue
            drawn.add(key)
            p1 = uv_px(float(other["map_pos"]["u"]), float(other["map_pos"]["v"]), size)
            draw_dashed_line(draw, p0, p1, ROUTE_RGBA, dash=22, gap=14, width=4)
        for r in port.get("river_routes", []):
            if not isinstance(r, dict):
                continue
            to_id = str(r.get("to", ""))
            other = by_id.get(to_id)
            if other is None or not other.get("map_pos"):
                continue
            key = route_key(from_id, to_id)
            if key in drawn:
                continue
            drawn.add(key)
            p_end = uv_px(float(other["map_pos"]["u"]), float(other["map_pos"]["v"]), size)
            prev = p0
            for wp in r.get("waypoints", []):
                wpt = uv_px(float(wp["u"]), float(wp["v"]), size)
                draw_dashed_line(draw, prev, wpt, RIVER_RGBA, dash=16, gap=10, width=3)
                prev = wpt
            draw_dashed_line(draw, prev, p_end, RIVER_RGBA, dash=16, gap=10, width=3)
    return out


def draw_port_markers(img: Image.Image, ports: list[dict], size: tuple[int, int]) -> Image.Image:
    out = img.copy()
    draw = ImageDraw.Draw(out)
    for port in ports:
        mp = port.get("map_pos")
        if not mp:
            continue
        px, py = uv_px(float(mp["u"]), float(mp["v"]), size)
        status = port.get("status", "")
        r = 8 if status == "main" else 6
        color = (0x2A, 0xFF, 0x4A) if status == "main" else (0x6A, 0xFF, 0x8A)
        draw.ellipse([(px - r, py - r), (px + r, py + r)], fill=color, outline=(0x10, 0x30, 0x10), width=2)
        label = port.get("name", port.get("id", ""))
        tw = len(label) * 14 + 8
        draw.rectangle([(px + 10, py - 14), (px + 10 + tw, py + 6)], fill=(0x10, 0x10, 0x08))
        draw.text((px + 14, py - 12), label, fill=(0xFF, 0xF0, 0xC0))
    return out


def main() -> None:
    _layout, ports, size = load_data()
    base = draw_base_map(size)
    mask = draw_sea_mask(size)
    routes = draw_routes(base, ports, size)
    debug = draw_port_markers(routes.convert("RGB"), ports, size)

    base.save(OUT, optimize=True)
    mask.save(OUT_MASK, optimize=True)
    routes.save(OUT_ROUTES, optimize=True)
    debug.save(OUT_DEBUG, optimize=True)

    aspect = size[0] / size[1]
    print(f"wrote {OUT.name} {size[0]}x{size[1]} aspect={aspect:.4f}")
    print(f"wrote {OUT_MASK.name} {OUT_ROUTES.name} {OUT_DEBUG.name}")
    print(f"ports: {len(ports)}  land polys: {len(LAND_POLYGONS)}")


if __name__ == "__main__":
    main()
