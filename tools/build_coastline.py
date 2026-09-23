#!/usr/bin/env python3
"""把 Natural Earth 1:10m 陆地裁成东亚海域海图用的岸线。

数据源（公有领域）：
  https://www.naturalearthdata.com/
  geojson 镜像：
  https://github.com/martynafford/natural-earth-geojson

依赖：pip install pyclipper shapely

用法：
  python3 tools/build_coastline.py /path/to/ne_10m_land.geojson

写出：
  data/coastline.json   墨卡托海图用的陆地环
  data/sealanes.json    大圆会穿陆的港对，绕岸航线（只用于画线）

里程仍按 Voyage.distance_li 的大圆，本脚本不改经济数据。
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import pyclipper

ROOT = Path(__file__).resolve().parents[1]
OUT_COAST = ROOT / "data" / "coastline.json"
OUT_LANES = ROOT / "data" / "sealanes.json"
PORTS_PATH = ROOT / "data" / "ports.json"

# 比任何章节视窗都宽一圈，视窗贴边时仍能看到完整岸线，裁切边不会进画面。
LON0, LAT0, LON1, LAT1 = 103.0, 1.0, 143.0, 49.0
# 约 0.9 km。福建沿海的海湾还在，文件控制在可绘制的体量。
SIMPLIFY_DEG = 0.008
# 小于约 8 km² 的礁石丢掉。澎湖主岛约 60 km²，留得住。
MIN_AREA_DEG2 = 0.0007
ROUND = 3

# 航线采样：两端各留一截，港池落在陆上不算穿陆。
SAMPLE_N = 48
END_SKIP = 0.10
# 短途陆路（兴化—海口）不绕海。
MIN_DETOUR_KM = 180.0
A_STAR_PAD = 2.4
A_STAR_STEP = 0.18
# 绕岛（九州）可以比大圆长一截，仍然必须画在海上。再长就是寻路失败。
MAX_DETOUR_RATIO = 2.15


def dist_point_seg(p, a, b) -> float:
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    denom = dx * dx + dy * dy
    if denom == 0.0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / denom))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def douglas_peucker(pts: list, eps: float) -> list:
    if len(pts) <= 2:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        dmax = 0.0
        idx = -1
        a, b = pts[i], pts[j]
        for k in range(i + 1, j):
            d = dist_point_seg(pts[k], a, b)
            if d > dmax:
                dmax = d
                idx = k
        if idx >= 0 and dmax > eps:
            keep[idx] = True
            stack.append((i, idx))
            stack.append((idx, j))
    return [p for p, k in zip(pts, keep) if k]


def ring_bbox(ring):
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return (min(xs), min(ys), max(xs), max(ys))


def ring_area(ring) -> float:
    a = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        a += x1 * y2 - x2 * y1
    return abs(a) * 0.5


def dedup(pts, tol=1e-6):
    if not pts:
        return []
    out = [pts[0]]
    for p in pts[1:]:
        if abs(p[0] - out[-1][0]) > tol or abs(p[1] - out[-1][1]) > tol:
            out.append(p)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) < tol and abs(out[0][1] - out[-1][1]) < tol:
        out.pop()
    return out


def overlaps_bbox(b) -> bool:
    return not (b[2] < LON0 or b[0] > LON1 or b[3] < LAT0 or b[1] > LAT1)


def fully_inside(b) -> bool:
    return b[0] >= LON0 and b[2] <= LON1 and b[1] >= LAT0 and b[3] <= LAT1


# pyclipper 用整数。1e5 → 约 1 米，够把裁切边收成简单多边形。
CLIP_SCALE = 100000


def _clip_parts(ring) -> list:
    """与海图数据框求交。Sutherland–Hodgman 把凹岸切成自交多边形，Godot 填不出来。"""
    subj = [(int(round(p[0] * CLIP_SCALE)), int(round(p[1] * CLIP_SCALE))) for p in ring]
    clip = [
        (int(LON0 * CLIP_SCALE), int(LAT0 * CLIP_SCALE)),
        (int(LON1 * CLIP_SCALE), int(LAT0 * CLIP_SCALE)),
        (int(LON1 * CLIP_SCALE), int(LAT1 * CLIP_SCALE)),
        (int(LON0 * CLIP_SCALE), int(LAT1 * CLIP_SCALE)),
    ]
    pc = pyclipper.Pyclipper()
    try:
        pc.AddPath(subj, pyclipper.PT_SUBJECT, True)
        pc.AddPath(clip, pyclipper.PT_CLIP, True)
        solution = pc.Execute(
            pyclipper.CT_INTERSECTION, pyclipper.PFT_EVENODD, pyclipper.PFT_EVENODD
        )
    except pyclipper.ClipperException:
        return []
    parts = []
    for path in solution:
        path = pyclipper.CleanPolygon(path, 2.0)
        if len(path) >= 3:
            parts.append([(p[0] / CLIP_SCALE, p[1] / CLIP_SCALE) for p in path])
    return parts


def _simplify_part(clipped) -> list | None:
    clipped = dedup(clipped)
    if len(clipped) < 3:
        return None
    simplified = douglas_peucker(clipped + [clipped[0]], SIMPLIFY_DEG)
    simplified = dedup(simplified)
    if len(simplified) < 3 or ring_area(simplified) < MIN_AREA_DEG2:
        return None
    return [[round(p[0], ROUND), round(p[1], ROUND)] for p in simplified]


def process_ring(ring) -> list:
    if len(ring) < 4:
        return []
    if ring[0] == ring[-1]:
        ring = ring[:-1]
    b = ring_bbox(ring)
    if not overlaps_bbox(b):
        return []
    parts = [ring] if fully_inside(b) else _clip_parts(ring)
    out = []
    for part in parts:
        simplified = _simplify_part(part)
        if simplified:
            out.append(simplified)
    return out


def iter_polygons(feature):
    geom = feature["geometry"]
    if geom["type"] == "Polygon":
        yield geom["coordinates"]
    elif geom["type"] == "MultiPolygon":
        yield from geom["coordinates"]


def _make_valid_rings(rings: list) -> list:
    """Douglas–Peucker 会在雷州半岛这类窄颈处把岸线拧成自交，Godot 填不出色。"""
    from shapely.geometry import GeometryCollection, MultiPolygon, Polygon
    from shapely.validation import make_valid

    def explode(geom):
        if geom.is_empty:
            return []
        if isinstance(geom, Polygon):
            return [geom]
        if isinstance(geom, MultiPolygon):
            return list(geom.geoms)
        if isinstance(geom, GeometryCollection):
            out = []
            for g in geom.geoms:
                out.extend(explode(g))
            return out
        return []

    fixed = []
    for ring in rings:
        poly = Polygon(ring)
        if not poly.is_valid:
            poly = make_valid(poly)
        for g in explode(poly):
            if g.area < MIN_AREA_DEG2:
                continue
            coords = list(g.exterior.coords)
            if len(coords) >= 2 and coords[0] == coords[-1]:
                coords = coords[:-1]
            deduped = []
            for p in coords:
                if not deduped or abs(p[0] - deduped[-1][0]) > 1e-9 or abs(p[1] - deduped[-1][1]) > 1e-9:
                    deduped.append([round(p[0], ROUND), round(p[1], ROUND)])
            if len(deduped) >= 3:
                fixed.append(deduped)
    return fixed


def build_land(geojson_path: Path) -> dict:
    data = json.loads(geojson_path.read_text())
    land = []
    holes = []
    raw_pts = 0
    for feat in data["features"]:
        for poly in iter_polygons(feat):
            if not poly:
                continue
            raw_pts += len(poly[0])
            land.extend(process_ring(poly[0]))
            for hole in poly[1:]:
                raw_pts += len(hole)
                holes.extend(process_ring(hole))
    land = _make_valid_rings(land)
    land.sort(key=lambda r: -ring_area(r))
    out_pts = sum(len(r) for r in land) + sum(len(r) for r in holes)
    return {
        "meta": {
            "source": "Natural Earth 1:10m land (public domain, naturalearthdata.com)",
            "crs": "EPSG:4326",
            "bbox": [LON0, LAT0, LON1, LAT1],
            "simplify_deg": SIMPLIFY_DEG,
            "rings": len(land),
            "holes": len(holes),
            "points": out_pts,
            "note": "坐标 [经度, 纬度]。海图用墨卡托绘制。裁切框大于游戏视窗，直边不会进入画面。",
        },
        "land": land,
        "holes": holes,
    }


def point_in_ring(lon, lat, ring) -> bool:
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > lat) != (yj > lat):
            xint = (xj - xi) * (lat - yi) / (yj - yi) + xi
            if lon < xint:
                inside = not inside
        j = i
    return inside


def make_land_index(rings):
    boxes = [ring_bbox(r) for r in rings]
    return boxes


def on_land(lon, lat, rings, boxes) -> bool:
    for ring, b in zip(rings, boxes):
        if lon < b[0] or lon > b[2] or lat < b[1] or lat > b[3]:
            continue
        if point_in_ring(lon, lat, ring):
            return True
    return False


def haversine_km(lon1, lat1, lon2, lat2) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = p2 - p1
    dl = math.radians(lon2 - lon1)
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def segment_hits_land(a, b, rings, boxes) -> bool:
    """a/b = (lon, lat)。两端港池附近的陆地忽略。"""
    hits = 0
    checked = 0
    for i in range(1, SAMPLE_N):
        t = i / SAMPLE_N
        if t < END_SKIP or t > 1.0 - END_SKIP:
            continue
        lon = a[0] + (b[0] - a[0]) * t
        lat = a[1] + (b[1] - a[1]) * t
        checked += 1
        if on_land(lon, lat, rings, boxes):
            hits += 1
    # 擦到岸边一两个采样点不算穿岛
    return hits >= 2 and hits / max(1, checked) >= 0.06


def cell_has_sea(lon, lat, rings, boxes, step, sea_mask=None) -> bool:
    """格心或邻近有海水即可走。河口和窄海峡不会被整格涂成陆地。"""
    if sea_mask is not None:
        return sea_mask_at(sea_mask, lon, lat)
    for dx in (0.0, 0.34, -0.34):
        for dy in (0.0, 0.34, -0.34):
            if not on_land(lon + dx * step, lat + dy * step, rings, boxes):
                return True
    return False


def build_sea_mask(rings, boxes, step):
    """整张图的海水掩膜，寻路时不再逐格做点在多边形内判断。"""
    lon0 = LON0 - 1.0
    lon1 = LON1 + 1.0
    lat0 = LAT0 - 1.0
    lat1 = LAT1 + 1.0
    mask = set()
    y = lat0
    while y <= lat1:
        x = lon0
        while x <= lon1:
            sea = False
            for dx in (0.0, 0.34, -0.34):
                for dy in (0.0, 0.34, -0.34):
                    if not on_land(x + dx * step, y + dy * step, rings, boxes):
                        sea = True
                        break
                if sea:
                    break
            if sea:
                mask.add((round(x / step), round(y / step)))
            x += step
        y += step
    return {"step": step, "cells": mask}


def sea_mask_at(mask, lon, lat) -> bool:
    step = mask["step"]
    return (round(lon / step), round(lat / step)) in mask["cells"]


def nearest_sea(lon, lat, rings, boxes, step, sea_mask=None):
    if cell_has_sea(lon, lat, rings, boxes, step, sea_mask):
        return (lon, lat)
    # 螺旋搜索最近海水
    for rad in [step * k for k in range(1, 18)]:
        n = max(8, int(2 * math.pi * rad / step))
        best = None
        best_d = 1e18
        for i in range(n):
            ang = 2 * math.pi * i / n
            x = lon + rad * math.cos(ang)
            y = lat + rad * math.sin(ang)
            if on_land(x, y, rings, boxes):
                continue
            d = haversine_km(lon, lat, x, y)
            if d < best_d:
                best_d = d
                best = (x, y)
        if best:
            return best
    return None


def astar(start, goal, rings, boxes, sea_mask=None):
    lon0 = min(start[0], goal[0]) - A_STAR_PAD
    lon1 = max(start[0], goal[0]) + A_STAR_PAD
    lat0 = min(start[1], goal[1]) - A_STAR_PAD
    lat1 = max(start[1], goal[1]) + A_STAR_PAD
    step = A_STAR_STEP

    def key(p):
        return (round(p[0] / step), round(p[1] / step))

    def center(k):
        return (k[0] * step, k[1] * step)

    s_sea = nearest_sea(*start, rings, boxes, step, sea_mask)
    g_sea = nearest_sea(*goal, rings, boxes, step, sea_mask)
    if not s_sea or not g_sea:
        return None
    start_k = key(s_sea)
    goal_k = key(g_sea)
    if start_k == goal_k:
        return [start, goal]

    import heapq

    open_h = []
    heapq.heappush(open_h, (0.0, start_k))
    came = {}
    gscore = {start_k: 0.0}
    closed = set()
    neigh = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    found = False
    expansions = 0
    while open_h and expansions < 60000:
        _, cur = heapq.heappop(open_h)
        if cur in closed:
            continue
        closed.add(cur)
        expansions += 1
        if cur == goal_k:
            found = True
            break
        cx, cy = center(cur)
        for dx, dy in neigh:
            nk = (cur[0] + dx, cur[1] + dy)
            if nk in closed:
                continue
            nx, ny = center(nk)
            if nx < lon0 or nx > lon1 or ny < lat0 or ny > lat1:
                continue
            if not cell_has_sea(nx, ny, rings, boxes, step, sea_mask):
                continue
            step_cost = haversine_km(cx, cy, nx, ny)
            ng = gscore[cur] + step_cost
            if ng < gscore.get(nk, 1e18):
                came[nk] = cur
                gscore[nk] = ng
                h = haversine_km(nx, ny, *center(goal_k))
                heapq.heappush(open_h, (ng + h, nk))
    if not found:
        return None
    path = []
    cur = goal_k
    while cur != start_k:
        path.append(center(cur))
        cur = came[cur]
    path.append(center(start_k))
    path.reverse()
    # 简化后去掉与港口重合的两端
    path = douglas_peucker(path, 0.12)
    mid = []
    for p in path[1:-1]:
        mid.append([round(p[0], ROUND), round(p[1], ROUND)])
    return mid


def build_lanes(coast: dict) -> dict:
    ports = json.loads(PORTS_PATH.read_text())["ports"]
    rings = coast["land"]
    boxes = make_land_index(rings)
    print("rasterizing sea mask...")
    sea_mask = build_sea_mask(rings, boxes, A_STAR_STEP)
    print(f"sea cells={len(sea_mask['cells'])}")
    lanes = {}
    reports = []
    ids = [p["id"] for p in ports]
    by_id = {p["id"]: p for p in ports}
    for i, a_id in enumerate(ids):
        for b_id in ids[i + 1 :]:
            a = by_id[a_id]
            b = by_id[b_id]
            pa = (a["lon"], a["lat"])
            pb = (b["lon"], b["lat"])
            km = haversine_km(*pa, *pb)
            if km < MIN_DETOUR_KM:
                continue
            if not segment_hits_land(pa, pb, rings, boxes):
                continue
            mid = astar(pa, pb, rings, boxes, sea_mask)
            if not mid:
                reports.append((a_id, b_id, km, "no-path"))
                continue
            # 绕路长度
            seq = [pa] + [(p[0], p[1]) for p in mid] + [pb]
            sea_km = sum(haversine_km(*seq[k], *seq[k + 1]) for k in range(len(seq) - 1))
            ratio = sea_km / km if km else 99
            if ratio > MAX_DETOUR_RATIO:
                reports.append((a_id, b_id, km, f"too-long x{ratio:.2f}"))
                continue
            key = "|".join(sorted([a_id, b_id]))
            # 折线方向固定为 key 的左港 → 右港，画的时候按起迄决定要不要反过来。
            if a_id > b_id:
                mid = list(reversed(mid))
            lanes[key] = mid
            reports.append((a_id, b_id, km, f"lane {len(mid)} pts x{ratio:.2f}"))
    return {
        "meta": {
            "note": "大圆航线中段穿陆时，海图改画这条绕岸折线。港口里程仍用大圆，不改经济。短途陆路（兴化往海口）不绕。",
            "pairs": len(lanes),
        },
        "lanes": lanes,
        "_reports": reports,
    }


def main():
    if len(sys.argv) != 2:
        print("usage: python3 tools/build_coastline.py ne_10m_land.geojson", file=sys.stderr)
        sys.exit(2)
    src = Path(sys.argv[1])
    coast = build_land(src)
    OUT_COAST.write_text(json.dumps(coast, ensure_ascii=False, separators=(",", ":")))
    print(
        f"coast rings={coast['meta']['rings']} holes={coast['meta']['holes']} "
        f"pts={coast['meta']['points']} bytes={OUT_COAST.stat().st_size}"
    )
    lanes = build_lanes(coast)
    reports = lanes.pop("_reports")
    OUT_LANES.write_text(json.dumps(lanes, ensure_ascii=False, separators=(",", ":")))
    print(f"lanes={lanes['meta']['pairs']} bytes={OUT_LANES.stat().st_size}")
    for row in reports:
        print(" ", row)


if __name__ == "__main__":
    main()
