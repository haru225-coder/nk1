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
  data/sealanes.json    大圆会穿陆的港对，改走海上折线

Voyage.distance_li 按这条折线计里程（没有折线的港对仍用大圆）。
只重算航线、不重写岸线：python3 tools/build_coastline.py --lanes-only
"""
from __future__ import annotations

import bisect
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
# 约 9 km。格心必须落在海上，河口里的死水不算航道。
A_STAR_STEP = 0.08
# 贴岸的格子更贵，开阔水优先；窄海峡两边都贴岸，相对代价一样，仍走得过。
OFFSHORE_MULT = 1.8
# 广州在珠江里，这版岸线要走出约 38 km 才接到外海。
# 港池这一段允许贴陆，再远的采样落在陆上就算切陆。
DEEP_LAND_KM = 36.0
CHORD_SAMPLE_KM = 4.0
CHORD_STEP = 0.02
MAX_EXPANSIONS = 200000
# 博多到鹿儿岛要绕过九州南端，海路大约是大圆的 2.2 倍。再长就是寻路失败。
MAX_DETOUR_RATIO = 2.60


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


class LandGrid:
    """扫描线栅格，规则与 point_in_ring 的偶奇判断一致。"""

    def __init__(self, step, lon0, lat0, lon1, lat1):
        self.step = step
        self.kx0 = math.floor(lon0 / step)
        self.ky0 = math.floor(lat0 / step)
        self.kx1 = math.ceil(lon1 / step)
        self.ky1 = math.ceil(lat1 / step)
        self.w = self.kx1 - self.kx0 + 1
        self.h = self.ky1 - self.ky0 + 1
        self.grid = bytearray(self.w * self.h)

    def mark(self, kx, ky) -> None:
        if self.kx0 <= kx <= self.kx1 and self.ky0 <= ky <= self.ky1:
            self.grid[(ky - self.ky0) * self.w + (kx - self.kx0)] = 1

    def land_key(self, kx, ky) -> bool:
        if kx < self.kx0 or kx > self.kx1 or ky < self.ky0 or ky > self.ky1:
            return True
        return self.grid[(ky - self.ky0) * self.w + (kx - self.kx0)] == 1

    def on_land_pt(self, lon, lat) -> bool:
        return self.land_key(int(round(lon / self.step)), int(round(lat / self.step)))


def rasterize_land(rings, boxes, step, lon0, lat0, lon1, lat1) -> LandGrid:
    grid = LandGrid(step, lon0, lat0, lon1, lat1)
    for ring, b in zip(rings, boxes):
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        n = len(ring)
        ky_a = max(grid.ky0, math.floor(b[1] / step) - 1)
        ky_b = min(grid.ky1, math.ceil(b[3] / step) + 1)
        kx_a = max(grid.kx0, math.floor(b[0] / step) - 1)
        kx_b = min(grid.kx1, math.ceil(b[2] / step) + 1)
        for ky in range(ky_a, ky_b + 1):
            lat = ky * step
            crossings = []
            j = n - 1
            for i in range(n):
                yi, yj = ys[i], ys[j]
                if (yi > lat) != (yj > lat):
                    crossings.append((xs[j] - xs[i]) * (lat - yi) / (yj - yi) + xs[i])
                j = i
            if not crossings:
                continue
            crossings.sort()
            # 与 point_in_ring 一致：lon < xint 才算穿过。交点成对时，
            # 落在 [c[2k], c[2k+1]) 里的格心是陆地。奇数个交点退回逐格判断。
            if len(crossings) % 2 == 0:
                for k in range(0, len(crossings), 2):
                    left, right = crossings[k], crossings[k + 1]
                    if right <= left:
                        continue
                    kx_l = max(kx_a, math.ceil(left / step - 1e-9))
                    kx_r = min(kx_b, math.floor((right - 1e-9) / step))
                    for kx in range(kx_l, kx_r + 1):
                        grid.mark(kx, ky)
            else:
                for kx in range(kx_a, kx_b + 1):
                    lon = kx * step
                    n_right = len(crossings) - bisect.bisect_right(crossings, lon)
                    if n_right & 1:
                        grid.mark(kx, ky)
    return grid


def flood_ocean(grid: LandGrid):
    """从东海一点漫出整片外海。内河和潟湖不跟外海相连，船不从那里出发。"""
    from collections import deque

    start = nearest_sea_key(125.0, 30.0, grid)
    if start is None or grid.land_key(*start):
        return set()
    seen = {start}
    q = deque([start])
    neigh = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    while q:
        cur = q.popleft()
        for dx, dy in neigh:
            nk = (cur[0] + dx, cur[1] + dy)
            if nk in seen or grid.land_key(*nk):
                continue
            if dx and dy and (
                grid.land_key(cur[0] + dx, cur[1]) or grid.land_key(cur[0], cur[1] + dy)
            ):
                continue
            seen.add(nk)
            q.append(nk)
    return seen


def nearest_ocean_key(lon, lat, grid: LandGrid, ocean: set):
    step = grid.step
    k0 = (int(round(lon / step)), int(round(lat / step)))
    if k0 in ocean:
        return k0
    for rad in range(1, 80):
        best = None
        best_d = 1e18
        for dx in range(-rad, rad + 1):
            for dy in range(-rad, rad + 1):
                if max(abs(dx), abs(dy)) != rad:
                    continue
                nk = (k0[0] + dx, k0[1] + dy)
                if nk not in ocean:
                    continue
                cx, cy = nk[0] * step, nk[1] * step
                d = (cx - lon) ** 2 + (cy - lat) ** 2
                if d < best_d:
                    best_d = d
                    best = nk
        if best is not None:
            return best
    return None


def nearest_sea_key(lon, lat, grid: LandGrid):
    step = grid.step
    k0 = (int(round(lon / step)), int(round(lat / step)))
    if not grid.land_key(*k0):
        return k0
    for rad in range(1, 28):
        best = None
        best_d = 1e18
        for dx in range(-rad, rad + 1):
            for dy in range(-rad, rad + 1):
                if max(abs(dx), abs(dy)) != rad:
                    continue
                nk = (k0[0] + dx, k0[1] + dy)
                if grid.land_key(*nk):
                    continue
                cx, cy = nk[0] * step, nk[1] * step
                d = (cx - lon) ** 2 + (cy - lat) ** 2
                if d < best_d:
                    best_d = d
                    best = nk
        if best is not None:
            return best
    return None


def chord_hits_deep_land(a, b, port_a, port_b, grid: LandGrid) -> bool:
    km = haversine_km(a[0], a[1], b[0], b[1])
    if km < 1.0:
        return False
    n = max(1, int(km / CHORD_SAMPLE_KM))
    for i in range(1, n):
        t = i / n
        lon = a[0] + (b[0] - a[0]) * t
        lat = a[1] + (b[1] - a[1]) * t
        if not grid.on_land_pt(lon, lat):
            continue
        if (
            haversine_km(lon, lat, port_a[0], port_a[1]) > DEEP_LAND_KM
            and haversine_km(lon, lat, port_b[0], port_b[1]) > DEEP_LAND_KM
        ):
            return True
    return False


def exact_safe_waypoints(raw, port_a, port_b, fine: LandGrid, rings, boxes):
    """折线顶点都在外海格子上。弦若被精确点-in-多边形判定为切陆，就拆回寻路点。"""

    def ok(i, j) -> bool:
        if chord_hits_deep_land(raw[i], raw[j], port_a, port_b, fine):
            return False
        return deep_land_hits([raw[i], raw[j]], port_a, port_b, rings, boxes) == 0

    def rec(i, j):
        if j <= i + 1:
            return []
        if ok(i, j):
            return []
        k = (i + j) // 2
        return rec(i, k) + [raw[k]] + rec(k, j)

    if len(raw) <= 1:
        return list(raw)
    return [raw[0]] + rec(0, len(raw) - 1) + [raw[-1]]


def nudge_off_land(a, b, port_a, port_b, grid: LandGrid):
    """弦仍切陆时，往两侧外海插一个点。"""
    dx, dy = b[0] - a[0], b[1] - a[1]
    norm = math.hypot(dx, dy) or 1.0
    px, py = -dy / norm, dx / norm
    for dist in (0.08, 0.16, 0.28, 0.45, 0.7, 1.05):
        for sign in (1.0, -1.0):
            mx = (a[0] + b[0]) * 0.5 + sign * px * dist
            my = (a[1] + b[1]) * 0.5 + sign * py * dist
            mid = (mx, my)
            if grid.on_land_pt(mx, my):
                continue
            if chord_hits_deep_land(a, mid, port_a, port_b, grid):
                continue
            if chord_hits_deep_land(mid, b, port_a, port_b, grid):
                continue
            return mid
    return None


def repair_track(points, port_a, port_b, grid: LandGrid):
    guard = 0
    while guard < 6:
        guard += 1
        changed = False
        new = [points[0]]
        for i in range(len(points) - 1):
            b = points[i + 1]
            a = new[-1]
            if not chord_hits_deep_land(a, b, port_a, port_b, grid):
                new.append(b)
                continue
            mid = nudge_off_land(a, b, port_a, port_b, grid)
            if mid is None:
                new.append(b)
            else:
                new.append(mid)
                new.append(b)
                changed = True
        points = new
        if not changed:
            break
    return points


def astar(start, goal, grid: LandGrid, ocean: set):
    step = grid.step
    lon0 = min(start[0], goal[0]) - A_STAR_PAD
    lon1 = max(start[0], goal[0]) + A_STAR_PAD
    lat0 = min(start[1], goal[1]) - A_STAR_PAD
    lat1 = max(start[1], goal[1]) + A_STAR_PAD
    kx0, kx1 = math.floor(lon0 / step), math.ceil(lon1 / step)
    ky0, ky1 = math.floor(lat0 / step), math.ceil(lat1 / step)

    def center(k):
        return (k[0] * step, k[1] * step)

    start_k = nearest_ocean_key(start[0], start[1], grid, ocean)
    goal_k = nearest_ocean_key(goal[0], goal[1], grid, ocean)
    if start_k is None or goal_k is None:
        return None
    if start_k == goal_k:
        return [center(start_k)]

    import heapq

    open_h = []
    heapq.heappush(open_h, (0.0, start_k))
    came = {}
    gscore = {start_k: 0.0}
    closed = set()
    neigh = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    found = False
    expansions = 0
    while open_h and expansions < MAX_EXPANSIONS:
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
            if nk[0] < kx0 or nk[0] > kx1 or nk[1] < ky0 or nk[1] > ky1:
                continue
            if nk not in ocean:
                continue
            # 斜向不允许擦陆地的角，否则两格海水之间的弦会切进岬角。
            if dx != 0 and dy != 0:
                if (cur[0] + dx, cur[1]) not in ocean or (cur[0], cur[1] + dy) not in ocean:
                    continue
            step_cost = haversine_km(cx, cy, *center(nk))
            if (
                (cur[0] + 1, cur[1]) not in ocean
                or (cur[0] - 1, cur[1]) not in ocean
                or (cur[0], cur[1] + 1) not in ocean
                or (cur[0], cur[1] - 1) not in ocean
            ):
                step_cost *= OFFSHORE_MULT
            ng = gscore[cur] + step_cost
            if ng < gscore.get(nk, 1e18):
                came[nk] = cur
                gscore[nk] = ng
                h = haversine_km(*center(nk), *center(goal_k))
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
    return path


def _round_pt(p):
    return [round(p[0], ROUND), round(p[1], ROUND)]


def deep_land_hits(seq, port_a, port_b, rings, boxes) -> int:
    """精确点在多边形内。离两端都超过 DEEP_LAND_KM 仍在陆上的采样点。"""
    hits = 0
    for i in range(len(seq) - 1):
        a, b = seq[i], seq[i + 1]
        km = haversine_km(a[0], a[1], b[0], b[1])
        n = max(1, int(km / CHORD_SAMPLE_KM))
        for s in range(1, n):
            t = s / n
            lon = a[0] + (b[0] - a[0]) * t
            lat = a[1] + (b[1] - a[1]) * t
            if not on_land(lon, lat, rings, boxes):
                continue
            if (
                haversine_km(lon, lat, port_a[0], port_a[1]) > DEEP_LAND_KM
                and haversine_km(lon, lat, port_b[0], port_b[1]) > DEEP_LAND_KM
            ):
                hits += 1
    return hits


def build_lanes(coast: dict) -> dict:
    sys.setrecursionlimit(10000)
    ports = json.loads(PORTS_PATH.read_text())["ports"]
    rings = coast["land"]
    boxes = make_land_index(rings)
    print("rasterizing land grids...")
    coarse = rasterize_land(rings, boxes, A_STAR_STEP, LON0 - 1.0, LAT0 - 1.0, LON1 + 1.0, LAT1 + 1.0)
    fine = rasterize_land(rings, boxes, CHORD_STEP, LON0 - 1.0, LAT0 - 1.0, LON1 + 1.0, LAT1 + 1.0)
    land_n = sum(coarse.grid)
    ocean = flood_ocean(coarse)
    print(f"coarse land cells={land_n} ocean={len(ocean)} step={A_STAR_STEP}")
    probes = [
        ("台湾", 121.0, 23.7, True),
        ("海南", 109.7, 19.2, True),
        ("九州", 131.0, 32.5, True),
        ("济州", 126.5, 33.4, True),
        ("澎湖", 119.58, 23.57, True),
        ("台湾以东", 123.2, 25.0, False),
        ("东海", 125.0, 30.0, False),
        ("南海", 114.0, 18.0, False),
    ]
    for name, lon, lat, want in probes:
        got = fine.on_land_pt(lon, lat)
        exact = on_land(lon, lat, rings, boxes)
        if got != want or exact != want:
            print(f"land grid mismatch {name}: fine={got} exact={exact} want={want}", file=sys.stderr)
            sys.exit(1)
    lanes = {}
    reports = []
    ids = [p["id"] for p in ports]
    by_id = {p["id"]: p for p in ports}
    for i, a_id in enumerate(ids):
        for b_id in ids[i + 1 :]:
            lo, hi = (a_id, b_id) if a_id < b_id else (b_id, a_id)
            a = by_id[lo]
            b = by_id[hi]
            pa = (a["lon"], a["lat"])
            pb = (b["lon"], b["lat"])
            km = haversine_km(pa[0], pa[1], pb[0], pb[1])
            if km < MIN_DETOUR_KM:
                continue
            if not segment_hits_land(pa, pb, rings, boxes):
                continue
            raw = astar(pa, pb, coarse, ocean)
            if not raw:
                reports.append((lo, hi, km, "no-path"))
                continue
            sea_pts = exact_safe_waypoints(raw, pa, pb, fine, rings, boxes)
            seq = [pa] + sea_pts + [pb]
            seq = repair_track(seq, pa, pb, fine)

            def pack(points):
                out = []
                for p in points:
                    rnd = _round_pt(p)
                    if out and out[-1] == rnd:
                        continue
                    out.append(rnd)
                return out

            # 港口坐标另算，折线只留海上转折。贴港 1.5 km 内的点去掉；
            # 去掉之后若弦又切进深陆，就把贴港的入海点留回来。
            waypoints = pack(seq[1:-1])
            trimmed = [
                p for p in waypoints
                if haversine_km(p[0], p[1], pa[0], pa[1]) >= 1.5
                and haversine_km(p[0], p[1], pb[0], pb[1]) >= 1.5
            ]
            full = [pa] + [(p[0], p[1]) for p in trimmed] + [pb]
            hits = deep_land_hits(full, pa, pb, rings, boxes)
            if hits:
                waypoints = pack(seq[1:-1])
                full = [pa] + [(p[0], p[1]) for p in waypoints] + [pb]
                hits = deep_land_hits(full, pa, pb, rings, boxes)
            else:
                waypoints = trimmed
            sea_km = sum(haversine_km(full[k][0], full[k][1], full[k + 1][0], full[k + 1][1]) for k in range(len(full) - 1))
            ratio = sea_km / km if km else 99
            if hits:
                reports.append((lo, hi, km, f"deep-land {hits} x{ratio:.2f}"))
                continue
            if ratio > MAX_DETOUR_RATIO:
                reports.append((lo, hi, km, f"too-long x{ratio:.2f}"))
                continue
            key = f"{lo}|{hi}"
            lanes[key] = waypoints
            reports.append((lo, hi, km, f"lane {len(waypoints)} pts x{ratio:.2f}"))
    return {
        "meta": {
            "note": "大圆中段穿陆的港对改走这条海上折线。航行里程与逐段风向按折线计算。短途陆路（兴化往海口）不绕。",
            "pairs": len(lanes),
            "deep_land_km": DEEP_LAND_KM,
        },
        "lanes": lanes,
        "_reports": reports,
    }


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    lanes_only = "--lanes-only" in sys.argv[1:]
    if lanes_only:
        if not OUT_COAST.exists():
            print("missing coastline.json", file=sys.stderr)
            sys.exit(2)
        coast = json.loads(OUT_COAST.read_text())
        print(f"reuse coast rings={coast['meta']['rings']} pts={coast['meta']['points']}")
    else:
        if len(args) != 1:
            print(
                "usage: python3 tools/build_coastline.py ne_10m_land.geojson\n"
                "       python3 tools/build_coastline.py --lanes-only",
                file=sys.stderr,
            )
            sys.exit(2)
        coast = build_land(Path(args[0]))
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
    missing = [k for k in ("hakata|kagoshima", "guangzhou|quanzhou") if k not in lanes["lanes"]]
    if missing:
        print("missing required lanes:", missing, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
