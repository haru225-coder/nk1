#!/usr/bin/env python3
"""核对 data/coastline.json：环闭合、陆地还在该在的位置、港口贴着海岸。

取景常数从 scripts/SeaChart.gd 读，避免和绘制各写一套。
同时把第一章和全图取景画成 PNG，方便肉眼看海岸。
"""
import heapq
import json
import math
import re
import sys
from pathlib import Path

import mapbox_earcut
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
GD = ROOT / "scripts" / "SeaChart.gd"
COAST = ROOT / "data" / "coastline.json"
PORTS = ROOT / "data" / "ports.json"
OUT_DIR = Path("/tmp/coastline-preview")

# 城可以在岸上，不能落到腹地；屿可以略偏外海，不能漂到大洋中间。
MAX_INLAND_KM = 180.0
MAX_OFFSHORE_KM = 45.0

problems = []


def fail(msg: str) -> None:
    problems.append(msg)
    print(f"  ✗ {msg}")


def ok(msg: str) -> None:
    print(f"  ✓ {msg}")


def gdscript_numbers() -> dict:
    text = GD.read_text(encoding="utf-8")
    found = {}
    for name in (
        "CHART_LAT_MIN", "CHART_LAT_MAX", "CHART_LON_MIN", "CHART_LON_MAX",
        "CHART_MIN_SPAN", "CHART_FRAME_FILL",
    ):
        m = re.search(rf"const {name} := ([0-9.]+)", text)
        if not m:
            fail(f"SeaChart.gd 缺少 const {name}")
            continue
        found[name] = float(m.group(1))
    return found


def expand_axis(lo, hi, bound_lo, bound_hi, min_span, fill):
    mid = (lo + hi) * 0.5
    half = max(min_span, hi - lo) * 0.5 / fill
    lo, hi = mid - half, mid + half
    if hi - lo > bound_hi - bound_lo:
        return bound_lo, bound_hi
    if lo < bound_lo:
        shift = bound_lo - lo
        lo += shift
        hi += shift
    if hi > bound_hi:
        shift = hi - bound_hi
        lo -= shift
        hi -= shift
    return max(lo, bound_lo), min(hi, bound_hi)


def frame_for(ports, const):
    lats = [float(p["lat"]) for p in ports]
    lons = [float(p["lon"]) for p in ports]
    lat0, lat1 = expand_axis(
        min(lats), max(lats), const["CHART_LAT_MIN"], const["CHART_LAT_MAX"],
        const["CHART_MIN_SPAN"], const["CHART_FRAME_FILL"])
    lon0, lon1 = expand_axis(
        min(lons), max(lons), const["CHART_LON_MIN"], const["CHART_LON_MAX"],
        const["CHART_MIN_SPAN"], const["CHART_FRAME_FILL"])
    return lat0, lat1, lon0, lon1


def km(lon1, lat1, lon2, lat2) -> float:
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) * 0.5))
    y = math.radians(lat2 - lat1)
    return 6371.0 * math.hypot(x, y)


def explode(geom):
    if geom.is_empty:
        return
    if geom.geom_type == "Polygon":
        yield geom
    elif geom.geom_type in ("MultiPolygon", "GeometryCollection"):
        for g in geom.geoms:
            yield from explode(g)


def earcut_ok(poly: Polygon) -> bool:
    ring = list(poly.exterior.coords)
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return poly.area < 1e-8
    verts = np.asarray(ring, dtype=np.float64)
    counts = np.asarray([len(ring)], dtype=np.uint32)
    idx = mapbox_earcut.triangulate_float64(verts, counts)
    return len(idx) >= 3 and len(idx) % 3 == 0


def out_code(lon, lat, lon0, lat0, lon1, lat1) -> int:
    code = 0
    if lon < lon0:
        code |= 1
    elif lon > lon1:
        code |= 2
    if lat < lat0:
        code |= 4
    elif lat > lat1:
        code |= 8
    return code


def clip_segment(a, b, lon0, lat0, lon1, lat1):
    x0, y0 = a
    x1, y1 = b
    c0 = out_code(x0, y0, lon0, lat0, lon1, lat1)
    c1 = out_code(x1, y1, lon0, lat0, lon1, lat1)
    for _ in range(12):
        if c0 == 0 and c1 == 0:
            return (x0, y0), (x1, y1)
        if c0 & c1:
            return None
        outside = c0 or c1
        dx, dy = x1 - x0, y1 - y0
        if outside & 8 and dy != 0.0:
            x = x0 + dx * (lat1 - y0) / dy
            y = lat1
        elif outside & 4 and dy != 0.0:
            x = x0 + dx * (lat0 - y0) / dy
            y = lat0
        elif outside & 2 and dx != 0.0:
            y = y0 + dy * (lon1 - x0) / dx
            x = lon1
        elif dx != 0.0:
            y = y0 + dy * (lon0 - x0) / dx
            x = lon0
        else:
            return None
        if outside == c0:
            x0, y0 = x, y
            c0 = out_code(x0, y0, lon0, lat0, lon1, lat1)
        else:
            x1, y1 = x, y
            c1 = out_code(x1, y1, lon0, lat0, lon1, lat1)
    return None


def _coast_runs(poly, proj, lon0, lat0, lon1, lat1):
    ring = list(poly.exterior.coords)
    runs = []
    run = []
    n = len(ring) - 1 if ring[0] == ring[-1] else len(ring)
    for i in range(n):
        clipped = clip_segment(ring[i], ring[(i + 1) % n], lon0, lat0, lon1, lat1)
        if clipped is None:
            if len(run) >= 2:
                runs.append(run)
            run = []
            continue
        p0 = proj(clipped[0][1], clipped[0][0])
        p1 = proj(clipped[1][1], clipped[1][0])
        if not run or math.hypot(run[-1][0] - p0[0], run[-1][1] - p0[1]) > 0.75:
            if len(run) >= 2:
                runs.append(run)
            run = [p0]
        run.append(p1)
    if len(run) >= 2:
        runs.append(run)
    return runs


# 航线与港名的数字从 SeaChart.gd 读，避免和游戏各写一套。
_RINGS = []
_BOXES = []
_BINS = []


def lane_numbers() -> dict:
    text = GD.read_text(encoding="utf-8")
    found = {}
    for name in (
        "LANE_CELL", "LANE_INSET", "LANE_HARBOR", "LANE_SAMPLE", "LANE_DEDUP",
        "LANE_SHORE_PENALTY", "LABEL_CLUSTER_PX",
    ):
        m = re.search(rf"const {name} := ([0-9.]+)", text)
        if not m:
            fail(f"SeaChart.gd 缺少 const {name}")
            continue
        found[name] = float(m.group(1))
    return found


def load_land_index(lands) -> None:
    global _RINGS, _BOXES, _BINS
    _RINGS, _BOXES, _BINS = [], [], []
    for land in lands:
        ring = land.get("ring", [])
        if len(ring) >= 2 and ring[0] == ring[-1]:
            ring = ring[:-1]
        if len(ring) < 3:
            continue
        _RINGS.append(ring)
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        _BOXES.append((min(xs), min(ys), max(xs), max(ys)))
        edge_bins = {}
        n = len(ring)
        for i in range(n):
            y0 = ring[i][1]
            y1 = ring[(i + 1) % n][1]
            lo = int(math.floor(min(y0, y1))) - 6
            hi = int(math.floor(max(y0, y1))) - 6
            for b in range(lo, hi + 1):
                edge_bins.setdefault(b, []).append(i)
        _BINS.append(edge_bins)


def on_land(lon, lat) -> bool:
    for ring, (x0, y0, x1, y1), edge_bins in zip(_RINGS, _BOXES, _BINS):
        if lon < x0 or lon > x1 or lat < y0 or lat > y1:
            continue
        edges = edge_bins.get(int(math.floor(lat)) - 6)
        if not edges:
            continue
        inside = False
        n = len(ring)
        for i in edges:
            j = (i + 1) % n
            yi = ring[i][1]
            yj = ring[j][1]
            if (yi > lat) != (yj > lat):
                xi = ring[i][0]
                xj = ring[j][0]
                if lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                    inside = not inside
        if inside:
            return True
    return False


class LaneGrid:
    def __init__(self, frame, numbers):
        self.frame = frame
        self.n = numbers
        self.cache = {}

    def inside(self, lon, lat) -> bool:
        lat0, lat1, lon0, lon1 = self.frame
        pad = self.n["LANE_INSET"]
        return lon0 + pad <= lon <= lon1 - pad and lat0 + pad <= lat <= lat1 - pad

    def blocked(self, ix, iy) -> bool:
        key = (ix, iy)
        hit = self.cache.get(key)
        if hit is not None:
            return hit
        cell = self.n["LANE_CELL"]
        lon = (ix + 0.5) * cell
        lat = (iy + 0.5) * cell
        bad = (not self.inside(lon, lat)) or on_land(lon, lat)
        self.cache[key] = bad
        return bad


def _nearest_water(grid, lon, lat, toward):
    cell = grid.n["LANE_CELL"]
    ix = int(math.floor(lon / cell))
    iy = int(math.floor(lat / cell))
    if not grid.blocked(ix, iy):
        return ix, iy
    best = None
    best_score = 1e9
    vx = toward[0] - lon
    vy = toward[1] - lat
    vl = math.hypot(vx, vy) or 1.0
    for rad in range(1, 14):
        found = False
        for dy in range(-rad, rad + 1):
            for dx in range(-rad, rad + 1):
                if max(abs(dx), abs(dy)) != rad:
                    continue
                cx, cy = ix + dx, iy + dy
                if grid.blocked(cx, cy):
                    continue
                found = True
                clon = (cx + 0.5) * cell
                clat = (cy + 0.5) * cell
                align = ((clon - lon) * vx + (clat - lat) * vy) / vl
                score = math.hypot(clon - lon, clat - lat) - align * 0.35
                if score < best_score:
                    best_score = score
                    best = (cx, cy)
        if found and best is not None and rad >= 2:
            break
    return best


def _astar(grid, start, goal):
    if start is None or goal is None:
        return None
    if start == goal:
        return [start]
    sx, sy = start
    gx, gy = goal

    def heuristic(ix, iy):
        return math.hypot(ix - gx, iy - gy)

    openq = [(heuristic(sx, sy), 0.0, sx, sy)]
    came = {}
    cost = {start: 0.0}
    seen = 0
    penalty = grid.n["LANE_SHORE_PENALTY"]
    while openq:
        _, g, x, y = heapq.heappop(openq)
        if (x, y) == goal:
            path = [(x, y)]
            while (x, y) in came:
                x, y = came[(x, y)]
                path.append((x, y))
            path.reverse()
            return path
        if g > cost.get((x, y), 1e18) + 1e-9:
            continue
        seen += 1
        if seen > 20000:
            return None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nx, ny = x + dx, y + dy
                if grid.blocked(nx, ny):
                    continue
                if dx != 0 and dy != 0 and (grid.blocked(x + dx, y) or grid.blocked(x, y + dy)):
                    continue
                step = math.hypot(dx, dy)
                for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if grid.blocked(nx + ox, ny + oy):
                        step += penalty
                        break
                ng = g + step
                if ng < cost.get((nx, ny), 1e18):
                    cost[(nx, ny)] = ng
                    came[(nx, ny)] = (x, y)
                    heapq.heappush(openq, (ng + heuristic(nx, ny), ng, nx, ny))
    return None


def _line_clear(a, b, ends, harbor, sample) -> bool:
    dist = math.hypot(b[0] - a[0], b[1] - a[1])
    steps = max(1, int(math.ceil(dist / sample)))
    for i in range(steps + 1):
        t = i / steps
        lon = a[0] + (b[0] - a[0]) * t
        lat = a[1] + (b[1] - a[1]) * t
        if any(math.hypot(lon - e[0], lat - e[1]) < harbor for e in ends):
            continue
        if on_land(lon, lat):
            return False
    return True


def _shortcut(pts, ends, harbor, sample):
    if len(pts) <= 2:
        return pts
    out = [pts[0]]
    i = 0
    while i < len(pts) - 1:
        j = len(pts) - 1
        while j > i + 1 and not _line_clear(pts[i], pts[j], ends, harbor, sample):
            j -= 1
        out.append(pts[j])
        i = j
    return out


def sea_lane(grid, a, b):
    """(lon, lat) 到 (lon, lat)。航程仍按直线，这里只给海图一条不穿陆地的画法。"""
    harbor = grid.n["LANE_HARBOR"]
    cell = grid.n["LANE_CELL"]
    dedup = grid.n["LANE_DEDUP"]
    sample = grid.n["LANE_SAMPLE"]
    straight = [a, b]
    if _line_clear(a, b, [a, b], harbor, sample):
        return straight
    start = _nearest_water(grid, a[0], a[1], b)
    goal = _nearest_water(grid, b[0], b[1], a)
    path = _astar(grid, start, goal)
    if not path:
        return straight
    pts = [((ix + 0.5) * cell, (iy + 0.5) * cell) for ix, iy in path]
    pts = _shortcut(pts, [a, b], harbor, sample)
    full = [a]
    for p in pts:
        if math.hypot(p[0] - full[-1][0], p[1] - full[-1][1]) > dedup:
            full.append(p)
    if math.hypot(full[-1][0] - b[0], full[-1][1] - b[1]) > dedup:
        full.append(b)
    else:
        full[-1] = b
    return _shortcut(full, [a, b], harbor, sample)


def land_hits(pts, harbor, sample) -> int:
    n = 0
    for p, q in zip(pts, pts[1:]):
        dist = math.hypot(q[0] - p[0], q[1] - p[1])
        steps = max(1, int(math.ceil(dist / sample)))
        for i in range(steps + 1):
            t = i / steps
            lon = p[0] + (q[0] - p[0]) * t
            lat = p[1] + (q[1] - p[1]) * t
            if math.hypot(lon - pts[0][0], lat - pts[0][1]) < harbor:
                continue
            if math.hypot(lon - pts[-1][0], lat - pts[-1][1]) < harbor:
                continue
            if on_land(lon, lat):
                n += 1
    return n


def route_pairs(ports):
    by_id = {p["id"]: p for p in ports}
    seen = set()
    pairs = []
    for p in ports:
        for cid in p.get("connections", []):
            if cid not in by_id:
                continue
            key = tuple(sorted((p["id"], cid)))
            if key in seen:
                continue
            seen.add(key)
            pairs.append(key)
    return pairs


def check_lanes(ports, frame, numbers, label) -> None:
    grid = LaneGrid(frame, numbers)
    by_id = {p["id"]: p for p in ports}
    harbor = numbers["LANE_HARBOR"]
    worse = []
    focus = {
        "第一章": (("quanzhou", "fuzhou"),),
        "全图": (("guangzhou", "quanzhou"), ("quanzhou", "fuzhou")),
    }
    report = {}
    for a_id, b_id in route_pairs(ports):
        a = (float(by_id[a_id]["lon"]), float(by_id[a_id]["lat"]))
        b = (float(by_id[b_id]["lon"]), float(by_id[b_id]["lat"]))
        sample = numbers["LANE_SAMPLE"]
        straight = land_hits([a, b], harbor, sample)
        bent = land_hits(sea_lane(grid, a, b), harbor, sample)
        report[(a_id, b_id)] = (straight, bent)
        if bent > straight:
            worse.append(f"{by_id[a_id]['name']}-{by_id[b_id]['name']} {straight}->{bent}")
    if worse:
        fail(f"{label}有航线比直线更穿陆地: " + ", ".join(worse))
    else:
        ok(f"{label}航线没有比直线更穿陆地")
    for a_id, b_id in focus.get(label, ()):
        straight, bent = report.get((a_id, b_id), report.get((b_id, a_id), None))
        names = f"{by_id[a_id]['name']}-{by_id[b_id]['name']}"
        if straight is None:
            fail(f"{label}缺少 {names}")
        elif straight == 0 or bent * 2 > straight:
            fail(f"{label}{names} 穿陆 {straight} -> {bent}，没有明显躲开陆地")
        else:
            ok(f"{label}{names} 穿陆 {straight} -> {bent}")


def _seaward(lon, lat) -> int:
    east = west = 0
    for dist in (0.4, 0.85, 1.3):
        east += not on_land(lon + dist, lat)
        west += not on_land(lon - dist, lat)
    if east > west:
        return 1
    if west > east:
        return -1
    return 1


def place_labels(ports, proj, map_rect, measure, cluster_px):
    """近港排成一列。靠海的一侧会盖住别的港时，改放到另一侧。"""
    xy = [proj(float(p["lat"]), float(p["lon"])) for p in ports]
    n = len(ports)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(n):
        for j in range(i + 1, n):
            if math.hypot(xy[i][0] - xy[j][0], xy[i][1] - xy[j][1]) < cluster_px:
                parent[find(j)] = find(i)
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)

    spots = []
    placed = []

    def overlaps(rect, pad):
        grow = (rect[0] - pad, rect[1] - pad, rect[2] + pad, rect[3] + pad)
        for prev in spots:
            if grow[0] < prev[2] and grow[2] > prev[0] and grow[1] < prev[3] and grow[3] > prev[1]:
                return True
        return False

    def covers_port(rect, members, pad=5):
        grow = (rect[0] - pad, rect[1] - pad, rect[2] + pad, rect[3] + pad)
        for i, (x, y) in enumerate(xy):
            if i in members:
                continue
            if grow[0] <= x <= grow[2] and grow[1] <= y <= grow[3]:
                return True
        return False

    clusters = []
    singles = []
    for members in groups.values():
        if len(members) >= 2:
            clusters.append(members)
        else:
            singles.append(members[0])
    clusters.sort(key=len, reverse=True)
    bounds = (map_rect[0] + 4, map_rect[1] + 4, map_rect[2] - 4, map_rect[3] - 4)

    for members in clusters:
        members = sorted(members, key=lambda i: -float(ports[i]["lat"]))
        member_set = set(members)
        sizes = [measure(ports[i]["name"]) for i in members]
        max_w = max(w for w, _h in sizes)
        gap = 2
        total_h = sum(h for _w, h in sizes) + gap * (len(members) - 1)
        lon = sum(float(ports[i]["lon"]) for i in members) / len(members)
        lat = sum(float(ports[i]["lat"]) for i in members) / len(members)
        sea = _seaward(lon, lat)
        max_x = max(xy[i][0] for i in members)
        min_x = min(xy[i][0] for i in members)
        mean_y = sum(xy[i][1] for i in members) / len(members)

        def column_at(side, shift, max_w=max_w, total_h=total_h, sizes=sizes):
            left = max_x + 12 if side > 0 else min_x - 12 - max_w
            top = mean_y - total_h * 0.5 + shift
            left = min(max(left, bounds[0]), max(bounds[0], bounds[2] - max_w))
            top = min(max(top, bounds[1]), max(bounds[1], bounds[3] - total_h))
            rects = []
            xs = []
            y = top
            for w, h in sizes:
                x = left if side > 0 else left + max_w - w
                rects.append((x, y, x + w, y + h))
                xs.append(x)
                y += h + gap
            return xs, rects

        chosen = None
        for side in (sea, -sea):
            for shift in (0, -16, 16, -32, 32, -48, 48, -64, 64):
                xs, rects = column_at(side, shift)
                if any(overlaps(r, 1) or covers_port(r, member_set) for r in rects):
                    continue
                cost = abs(shift) + (0 if side == sea else 6)
                if chosen is None or cost < chosen[0]:
                    chosen = (cost, side, xs, rects)
            if chosen is not None and chosen[0] < 6:
                break
        if chosen is None:
            xs, rects = column_at(sea, 0)
            chosen = (99, sea, xs, rects)
        _cost, side, xs, rects = chosen
        for i, x, rect in zip(members, xs, rects):
            w = rect[2] - rect[0]
            h = rect[3] - rect[1]
            spots.append(rect)
            attach_x = x if side > 0 else x + w
            anchor = xy[i]
            leader = None
            attach = (attach_x, rect[1] + h * 0.5)
            if math.hypot(attach[0] - anchor[0], attach[1] - anchor[1]) > 8:
                leader = (anchor, attach)
            placed.append((ports[i]["name"], (x, rect[1]), rect, leader))

    for i in singles:
        name = ports[i]["name"]
        w, h = measure(name)
        ax, ay = xy[i]
        sea = _seaward(float(ports[i]["lon"]), float(ports[i]["lat"]))
        cands = []
        for dist in (8, 22, 36):
            cands.append((ax + sea * dist - (0 if sea > 0 else w), ay - h * 0.5))
            cands.append((ax + sea * dist - (0 if sea > 0 else w), ay + 4))
            cands.append((ax + sea * dist - (0 if sea > 0 else w), ay - h - 2))
            cands.append((ax - sea * dist - (w if sea > 0 else 0), ay - h * 0.5))
            cands.append((ax - w * 0.5, ay - h - dist))
            cands.append((ax - w * 0.5, ay + dist))
        best = None
        best_cost = 1e9
        for x, y in cands:
            rect = (x, y, x + w, y + h)
            if rect[0] < bounds[0] or rect[1] < bounds[1] or rect[2] > bounds[2] or rect[3] > bounds[3]:
                continue
            cost = 0
            if overlaps(rect, 2):
                cost += 50
            if covers_port(rect, {i}):
                cost += 80
            if sea > 0 and x < ax:
                cost += 3
            if sea < 0 and x + w > ax:
                cost += 3
            if cost < best_cost:
                best_cost = cost
                best = (x, y, rect)
                if cost == 0:
                    break
        if best is None:
            best = (ax + 8, ay - h * 0.5, (ax + 8, ay - h * 0.5, ax + 8 + w, ay - h * 0.5 + h))
        x, y, rect = best
        spots.append(rect)
        placed.append((name, (x, y), rect, None))

    overlaps_at = []
    for i in range(len(spots)):
        a = spots[i]
        for j in range(i + 1, len(spots)):
            b = spots[j]
            if a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]:
                overlaps_at.append(f"{placed[i][0]}/{placed[j][0]}")
    return placed, overlaps_at


def _dashed(draw, a, b, fill, width=1, dash=6, gap=4):
    dist = math.hypot(b[0] - a[0], b[1] - a[1])
    if dist < 1:
        return
    ux, uy = (b[0] - a[0]) / dist, (b[1] - a[1]) / dist
    t = 0.0
    while t < dist:
        t2 = min(dist, t + dash)
        draw.line([(a[0] + ux * t, a[1] + uy * t), (a[0] + ux * t2, a[1] + uy * t2)], fill=fill, width=width)
        t = t2 + gap


def render(path: Path, ports, polys, const, size):
    """跟 SeaChart 的配色和层次对齐，用来肉眼看浅滩、墨线和港口标注。"""
    lat0, lat1, lon0, lon1 = frame_for(ports, const)
    w, h = size
    mean_lat = (lat0 + lat1) * 0.5
    mean_lon = (lon0 + lon1) * 0.5
    kx = math.cos(math.radians(mean_lat))
    span_x = max(0.5, (lon1 - lon0) * kx)
    span_y = max(0.5, lat1 - lat0)
    scale = min(w / span_x, h / span_y)
    mid = (w * 0.5, h * 0.5)

    def proj(lat, lon):
        return (
            mid[0] + (lon - mean_lon) * kx * scale,
            mid[1] - (lat - mean_lat) * scale,
        )

    sea = (18, 45, 64)
    shoal = (51, 115, 138)
    land = (199, 181, 138)
    coast = (74, 59, 41)
    ink = (56, 43, 31)
    grid = (90, 110, 120)
    frame = (209, 189, 140)
    img = Image.new("RGB", (w, h), (10, 14, 18))
    draw = ImageDraw.Draw(img)
    top_left = proj(lat1, lon0)
    bottom_right = proj(lat0, lon1)
    map_rect = [top_left[0], top_left[1], bottom_right[0], bottom_right[1]]
    draw.rectangle(map_rect, fill=sea)

    step = 5.0 if (lat1 - lat0) > 16.0 else 2.0
    lat = math.ceil(lat0 / step) * step
    while lat < lat1 - 0.05:
        draw.line([proj(lat, lon0), proj(lat, lon1)], fill=grid, width=1)
        lat += step
    lon = math.ceil(lon0 / step) * step
    while lon < lon1 - 0.05:
        draw.line([proj(lat0, lon), proj(lat1, lon)], fill=grid, width=1)
        lon += step

    shoal_w = int(round(min(7.5, max(3.0, scale * 0.11))))
    view = box(lon0, lat0, lon1, lat1)
    visible = [poly for poly in polys if poly.intersects(view)]
    for poly in visible:
        for run in _coast_runs(poly, proj, lon0, lat0, lon1, lat1):
            draw.line(run, fill=shoal, width=shoal_w)
    for poly in visible:
        part = poly.intersection(view)
        for piece in explode(part):
            pts = [proj(y, x) for x, y in piece.exterior.coords]
            if len(pts) >= 3:
                draw.polygon(pts, fill=land)
    for poly in visible:
        for run in _coast_runs(poly, proj, lon0, lat0, lon1, lat1):
            draw.line(run, fill=coast, width=2)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", 13)
        font_sea = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", 16)
    except OSError:
        font = ImageFont.load_default()
        font_sea = font

    numbers = lane_numbers()
    lane_grid = LaneGrid((lat0, lat1, lon0, lon1), numbers) if len(numbers) == 7 else None
    by_id = {p["id"]: p for p in ports}
    seen = set()
    for p in ports:
        for cid in p.get("connections", []):
            if cid not in by_id or by_id[cid] not in ports:
                continue
            key = tuple(sorted((p["id"], cid)))
            if key in seen:
                continue
            seen.add(key)
            a = (float(p["lon"]), float(p["lat"]))
            b = (float(by_id[cid]["lon"]), float(by_id[cid]["lat"]))
            pts = sea_lane(lane_grid, a, b) if lane_grid is not None else [a, b]
            screen = [proj(lat, lon) for lon, lat in pts]
            for u, v in zip(screen, screen[1:]):
                _dashed(draw, u, v, (210, 190, 145), width=2)

    land_all = unary_union(polys) if polys else None
    port_xy = [proj(float(p["lat"]), float(p["lon"])) for p in ports]
    for name, slat, slon in (("东海", 27.6, 123.5), ("南海", 15.4, 113.6)):
        if not (lat0 <= slat <= lat1 and lon0 <= slon <= lon1):
            continue
        if land_all is not None and land_all.covers(Point(slon, slat)):
            continue
        v = proj(slat, slon)
        if any(math.hypot(v[0] - x, v[1] - y) < 42 for x, y in port_xy):
            continue
        draw.text((v[0] - 16, v[1] - 10), name, fill=(176, 206, 214), font=font_sea)

    # 罗盘放在离港口最远的一角
    corners = [
        (map_rect[2] - 48, map_rect[3] - 48),
        (map_rect[0] + 48, map_rect[3] - 48),
        (map_rect[0] + 48, map_rect[1] + 52),
        (map_rect[2] - 48, map_rect[1] + 52),
    ]
    center = corners[0]
    for s in corners:
        if all(math.hypot(s[0] - x, s[1] - y) >= 58 for x, y in port_xy):
            center = s
            break
    cx, cy = center
    draw.ellipse((cx - 15, cy - 15, cx + 15, cy + 15), outline=frame)
    draw.line((cx - 13, cy, cx + 13, cy), fill=frame, width=1)
    draw.line((cx, cy + 11, cx, cy - 14), fill=frame, width=2)
    draw.polygon([(cx, cy - 18), (cx - 4, cy - 10), (cx + 4, cy - 10)], fill=frame)
    draw.text((cx - 7, cy - 34), "北", fill=frame, font=font)

    def measure(text):
        box = font.getbbox(text)
        return box[2] - box[0], box[3] - box[1]

    placed = []
    if len(numbers) == 7:
        placed, _overlaps = place_labels(
            ports, proj, tuple(map_rect), measure, numbers["LABEL_CLUSTER_PX"])
    for _text, _xy, _rect, leader in placed:
        if leader:
            draw.line(leader, fill=ink, width=1)
    for p in ports:
        x, y = proj(float(p["lat"]), float(p["lon"]))
        r = 4
        draw.ellipse((x - r - 2, y - r - 2, x + r + 2, y + r + 2), fill=(245, 237, 214))
        draw.ellipse((x - r, y - r, x + r, y + r), outline=ink, width=2)
        draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=ink)
    for text, (x, y), _rect, _leader in placed:
        draw.text((x, y), text, fill=ink, font=font)
    draw.rectangle(map_rect, outline=frame, width=2)
    inner = [map_rect[0] + 4, map_rect[1] + 4, map_rect[2] - 4, map_rect[3] - 4]
    draw.rectangle(inner, outline=frame)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"  预览 {path}")


def main() -> None:
    print("=" * 68)
    print("海图陆地")
    print("=" * 68)
    const = gdscript_numbers()
    if len(const) < 6:
        print(f"\n{len(problems)} 个问题")
        sys.exit(1)

    coast = json.loads(COAST.read_text(encoding="utf-8"))
    ports = json.loads(PORTS.read_text(encoding="utf-8"))["ports"]
    meta = coast.get("meta", {})
    lands = coast.get("lands", [])
    bbox = meta.get("bbox", [])
    if len(bbox) != 4:
        fail("meta.bbox 应为 [lon_min, lat_min, lon_max, lat_max]")
        bbox = [0, 0, 0, 0]

    polys = []
    ids = []
    for land in lands:
        ident = land.get("id", "")
        ids.append(ident)
        ring = land.get("ring", [])
        if len(ring) < 4:
            fail(f"{ident} 顶点不足")
            continue
        if ring[0] != ring[-1]:
            fail(f"{ident} 环未闭合")
        for i in range(len(ring) - 1):
            if ring[i] == ring[i + 1]:
                fail(f"{ident} 有连续重复点")
                break
        for lon, lat in ring:
            if not (bbox[0] - 0.02 <= lon <= bbox[2] + 0.02 and bbox[1] - 0.02 <= lat <= bbox[3] + 0.02):
                fail(f"{ident} 有点落在数据框外: {lon}, {lat}")
                break
        poly = Polygon(ring)
        if not poly.is_valid:
            fail(f"{ident} 多边形自交或无效")
        elif poly.exterior.is_ccw is False:
            fail(f"{ident} 环不是逆时针")
        polys.append(poly)

    for need in ("mainland", "taiwan", "hainan", "kyushu", "jeju", "penghu"):
        if need not in ids:
            fail(f"缺少陆地 {need}")
        else:
            ok(f"有 {need}")

    if polys:
        land = unary_union(polys)
        print()
        print("港口到海岸的距离（负值表示在海上）")
        for p in ports:
            pt = Point(float(p["lon"]), float(p["lat"]))
            near = land.boundary.interpolate(land.boundary.project(pt))
            dist = km(pt.x, pt.y, near.x, near.y)
            inside = land.covers(pt)
            signed = dist if inside else -dist
            flag = ""
            if inside and dist > MAX_INLAND_KM:
                flag = "  腹地过深"
                fail(f"{p['name']} 在陆地内 {dist:.0f} km，超过 {MAX_INLAND_KM:.0f}")
            elif not inside and dist > MAX_OFFSHORE_KM:
                flag = "  离岸过远"
                fail(f"{p['name']} 在海上 {dist:.0f} km，超过 {MAX_OFFSHORE_KM:.0f}")
            print(f"  {p['name']:<8} {signed:7.1f} km{flag}")
        if not any("腹地" in x or "离岸" in x for x in problems):
            ok(f"港口都在岸边 {MAX_OFFSHORE_KM:.0f} km 内或陆地 {MAX_INLAND_KM:.0f} km 内")

    ch1 = [p for p in ports if p.get("unlock") == "ch1"]
    ch1_frame = frame_for(ch1, const)
    full_frame = frame_for(ports, const)
    print()
    print(f"  第一章取景  lat {ch1_frame[0]:.2f}–{ch1_frame[1]:.2f}  lon {ch1_frame[2]:.2f}–{ch1_frame[3]:.2f}")
    print(f"  全图取景    lat {full_frame[0]:.2f}–{full_frame[1]:.2f}  lon {full_frame[2]:.2f}–{full_frame[3]:.2f}")

    def inside(frame, lon, lat, pad=0.0):
        lat0, lat1, lon0, lon1 = frame
        return lat0 - pad <= lat <= lat1 + pad and lon0 - pad <= lon <= lon1 + pad

    for p in ch1:
        if not inside(ch1_frame, float(p["lon"]), float(p["lat"])):
            fail(f"第一章取景装不下 {p['name']}")
    for p in ports:
        if not inside(full_frame, float(p["lon"]), float(p["lat"])):
            fail(f"全图取景装不下 {p['name']}")
    if not any("装不下" in x for x in problems):
        ok("取景框盖住对应港口")

    by_id = {land["id"]: Polygon(land["ring"]).centroid for land in lands if land.get("ring")}
    expect = (
        ("taiwan", ch1_frame),
        ("penghu", ch1_frame),
        ("hainan", full_frame),
        ("kyushu", full_frame),
        ("jeju", full_frame),
    )
    for ident, frame in expect:
        c = by_id.get(ident)
        if c is None:
            continue
        if not inside(frame, c.x, c.y):
            fail(f"{ident} 的中心不在对应取景里 ({c.x:.2f}, {c.y:.2f})")
        else:
            ok(f"{ident} 落在取景内")

    # 数据框要比最大取景宽，裁切直边才不会出现在画面上。
    for frame, label in ((ch1_frame, "第一章"), (full_frame, "全图")):
        lat0, lat1, lon0, lon1 = frame
        if not (bbox[0] < lon0 - 0.4 and bbox[2] > lon1 + 0.4 and bbox[1] < lat0 - 0.4 and bbox[3] > lat1 + 0.4):
            fail(f"{label}取景贴到了陆地数据的裁切边")
    if not any("裁切边" in x for x in problems):
        ok("取景没有贴上数据裁切边")

    bad_tri = 0
    for frame in (ch1_frame, full_frame):
        view = box(frame[2], frame[0], frame[3], frame[1])
        for poly in polys:
            if not poly.intersects(view):
                continue
            part = poly.intersection(view)
            for piece in explode(part):
                if piece.area < 1e-6:
                    continue
                if not earcut_ok(piece):
                    bad_tri += 1
    if bad_tri:
        fail(f"{bad_tri} 块陆地三角化失败")
    else:
        ok("第一章和全图取景里的陆地都能三角化")

    load_land_index(lands)
    numbers = lane_numbers()
    if len(numbers) == 7 and _RINGS:
        check_lanes(ch1, ch1_frame, numbers, "第一章")
        check_lanes(ports, full_frame, numbers, "全图")
        try:
            label_font = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", 13)
        except OSError:
            label_font = None
            fail("缺少中文字体，无法核对港名是否重叠")
        if label_font is not None:
            def measure(text, font=label_font):
                box = font.getbbox(text)
                return box[2] - box[0], box[3] - box[1]

            def layout_of(subset, const, size):
                lat0, lat1, lon0, lon1 = frame_for(subset, const)
                w, h = size
                mean_lat = (lat0 + lat1) * 0.5
                mean_lon = (lon0 + lon1) * 0.5
                kx = math.cos(math.radians(mean_lat))
                scale = min(w / max(0.5, (lon1 - lon0) * kx), h / max(0.5, lat1 - lat0))
                mid = (w * 0.5, h * 0.5)

                def proj(lat, lon):
                    return (
                        mid[0] + (lon - mean_lon) * kx * scale,
                        mid[1] - (lat - mean_lat) * scale,
                    )

                top = proj(lat1, lon0)
                bot = proj(lat0, lon1)
                return proj, (top[0], top[1], bot[0], bot[1])

            for size in ((900, 520), (680, 380)):
                for label, subset in (("第一章", ch1), ("全图", ports)):
                    proj, map_rect = layout_of(subset, const, size)
                    _placed, overlaps = place_labels(
                        subset, proj, map_rect, measure, numbers["LABEL_CLUSTER_PX"])
                    if overlaps:
                        fail(f"{label} {size[0]}×{size[1]} 港名重叠: {', '.join(overlaps)}")
            if not any("港名重叠" in item for item in problems):
                ok("两种图幅下港名都不重叠")

    render(OUT_DIR / "chart_ch1.png", ch1, polys, const, (900, 520))
    render(OUT_DIR / "chart_full.png", ports, polys, const, (900, 520))

    print()
    if problems:
        print(f"{len(problems)} 个问题")
        sys.exit(1)
    print("海图陆地通过")


if __name__ == "__main__":
    main()
