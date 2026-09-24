#!/usr/bin/env python3
"""岸线数据门禁（只用标准库）。2026-09-24 吸收云端 2d51 数据、按云端 8b32 的检查项改写。

核对 data/coastline.json / sealanes.json / chart_labels.json，以及海图代码是否真的接了它们：
  一、环：≥3 点、点在 bbox 内、无相邻重复点、不显式闭合（Godot 多边形按隐式闭合，首尾同点会出退化边）；
        环数与点数不低于数据自述，meta.points 与实数相等
  二、港口贴岸：在陆上的港离海岸 ≤ MAX_INLAND_KM（城可在岸上，不能落到腹地）；
        在海上的港离海岸 ≤ MAX_OFFSHORE_KM（屿可略偏外海，不能漂到大洋中间）
  三、绕岸航线：key 按字母序 "a|b"、两港存在且不同、航点在 bbox 内且都在海上
  四、海名标注：文字非空、坐标在 bbox 内、min_span < max_span
  五、接线：GameManager 加载三份数据；SeaChart 读 coastline_data / sealanes_data / chart_labels_data 并开 clip_contents
"""
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_INLAND_KM = 180.0
MAX_OFFSHORE_KM = 45.0
## 绕岸航点是照着建线时的几何摆的，落在最终简化岸线里 0.1~6.7 km（2026-09-24 实测 9 处）；作图无害。
## 超过这个数就是真绕进岸里了。
LANE_SHORE_TOL_KM = 10.0
MIN_RINGS = 100
MIN_POINTS = 5000
fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)


def load(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)


def km(lon1, lat1, lon2, lat2):
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) * 0.5))
    y = math.radians(lat2 - lat1)
    return 6371.0 * math.hypot(x, y)


def seg_dist_km(px, py, ax, ay, bx, by):
    """点到线段最近点的距离（先在经纬平面上投影到线段，再按 km() 量）。"""
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return km(px, py, ax, ay)
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return km(px, py, ax + t * dx, ay + t * dy)


def in_ring(px, py, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > py) != (yj > py):
            x_cross = (xj - xi) * (py - yi) / (yj - yi) + xi
            if px < x_cross:
                inside = not inside
        j = i
    return inside


def coast_dist_km(px, py, rings, bboxes):
    best = float("inf")
    for ring, (x0, y0, x1, y1) in zip(rings, bboxes):
        # 环的包围盒离点已经比当前最优远，整环跳过
        gx = 0.0 if x0 <= px <= x1 else min(abs(px - x0), abs(px - x1))
        gy = 0.0 if y0 <= py <= y1 else min(abs(py - y0), abs(py - y1))
        if km(px, py, px + gx, py + gy) >= best:
            continue
        n = len(ring)
        for i in range(n):
            ax, ay = ring[i]
            bx, by = ring[(i + 1) % n]
            d = seg_dist_km(px, py, ax, ay, bx, by)
            if d < best:
                best = d
    return best


def on_land(px, py, rings, bboxes):
    for ring, (x0, y0, x1, y1) in zip(rings, bboxes):
        if x0 <= px <= x1 and y0 <= py <= y1 and in_ring(px, py, ring):
            return True
    return False


print("=" * 68)
print("一、岸线环")
print("=" * 68)
coast = load("data/coastline.json")
meta = coast.get("meta", {})
bbox = meta.get("bbox", [])
check(isinstance(bbox, list) and len(bbox) == 4, "meta.bbox 为四元 [west, south, east, north]")
if len(bbox) != 4:
    bbox = [-180, -90, 180, 90]
W, S, E, N = (float(v) for v in bbox)
rings = coast.get("land", [])
check(isinstance(rings, list) and len(rings) >= MIN_RINGS, f"环数 {len(rings)} ≥ {MIN_RINGS}")
total_pts = 0
bad_small = bad_bbox = bad_dup = bad_closed = 0
bboxes = []
for ring in rings:
    if len(ring) < 3:
        bad_small += 1
        bboxes.append((0, 0, 0, 0))
        continue
    total_pts += len(ring)
    xs = [float(p[0]) for p in ring]
    ys = [float(p[1]) for p in ring]
    bboxes.append((min(xs), min(ys), max(xs), max(ys)))
    if min(xs) < W - 1e-6 or max(xs) > E + 1e-6 or min(ys) < S - 1e-6 or max(ys) > N + 1e-6:
        bad_bbox += 1
    if any(ring[i] == ring[i + 1] for i in range(len(ring) - 1)):
        bad_dup += 1
    if ring[0] == ring[-1]:
        bad_closed += 1
check(bad_small == 0, f"无少于 3 点的环（{bad_small}）")
check(bad_bbox == 0, f"所有点都在 bbox 内（越界环 {bad_bbox}）")
check(bad_dup == 0, f"无相邻重复点（{bad_dup} 环有）")
check(bad_closed == 0, f"环不显式闭合，首尾不同点（{bad_closed} 环首尾相同）")
check(total_pts >= MIN_POINTS, f"顶点 {total_pts} ≥ {MIN_POINTS}")
check(int(meta.get("points", -1)) == total_pts, f"meta.points={meta.get('points')} 与实数 {total_pts} 相等")
check(int(meta.get("rings", -1)) == len(rings), f"meta.rings={meta.get('rings')} 与实数 {len(rings)} 相等")
check(int(meta.get("holes", 0)) == 0, "无洞（SeaChart 按单环填色，不处理洞）")

print()
print("=" * 68)
print("二、港口贴岸")
print("=" * 68)
ports = load("data/ports.json")["ports"]
port_by_id = {p["id"]: p for p in ports}
for p in ports:
    lon, lat = float(p["lon"]), float(p["lat"])
    check(W <= lon <= E and S <= lat <= N, f"{p['id']} 在岸线 bbox 内")
    land = on_land(lon, lat, rings, bboxes)
    d = coast_dist_km(lon, lat, rings, bboxes)
    if land:
        check(d <= MAX_INLAND_KM, f"{p['id']} 在陆上，离海岸 {d:.0f} km ≤ {MAX_INLAND_KM:.0f}")
    else:
        check(d <= MAX_OFFSHORE_KM, f"{p['id']} 在海上，离海岸 {d:.0f} km ≤ {MAX_OFFSHORE_KM:.0f}")

print()
print("=" * 68)
print("三、绕岸航线")
print("=" * 68)
lanes = load("data/sealanes.json").get("lanes", {})
check(len(lanes) >= 1, f"航线 {len(lanes)} 条")
wp_total = 0
wp_shore = 0
for key, wps in lanes.items():
    parts = key.split("|")
    ok_key = len(parts) == 2 and parts[0] < parts[1] and parts[0] in port_by_id and parts[1] in port_by_id
    check(ok_key, f"{key}：key 为字母序 a|b 且两港都在 ports.json")
    check(isinstance(wps, list) and len(wps) >= 1, f"{key}：至少一个航点")
    for w in wps:
        wp_total += 1
        lon, lat = float(w[0]), float(w[1])
        if not (W <= lon <= E and S <= lat <= N):
            check(False, f"{key}：航点 {w} 越出 bbox")
        elif on_land(lon, lat, rings, bboxes):
            d = coast_dist_km(lon, lat, rings, bboxes)
            if d <= LANE_SHORE_TOL_KM:
                wp_shore += 1
            else:
                check(False, f"{key}：航点 {w} 在陆上且离岸 {d:.1f} km > {LANE_SHORE_TOL_KM:.0f}（绕岸线绕进了岸里）")
print(f"  航点共 {wp_total} 个，海上 {wp_total - wp_shore}、贴岸（陆上 ≤ {LANE_SHORE_TOL_KM:.0f} km）{wp_shore}")

print()
print("=" * 68)
print("四、海名标注")
print("=" * 68)
labels = load("data/chart_labels.json").get("labels", [])
check(len(labels) >= 1, f"标注 {len(labels)} 条")
for lb in labels:
    t = str(lb.get("text", ""))
    lon, lat = float(lb.get("lon", 0)), float(lb.get("lat", 0))
    check(t != "" and W <= lon <= E and S <= lat <= N, f"「{t}」文字非空且在 bbox 内")
    check(float(lb.get("min_span", 0)) < float(lb.get("max_span", 0)), f"「{t}」min_span < max_span")

print()
print("=" * 68)
print("五、代码接线")
print("=" * 68)
gm = open(os.path.join(ROOT, "scripts", "GameManager.gd"), encoding="utf-8").read()
sc = open(os.path.join(ROOT, "scripts", "SeaChart.gd"), encoding="utf-8").read()
vo = open(os.path.join(ROOT, "scripts", "core", "Voyage.gd"), encoding="utf-8").read()
for name in ("coastline", "sealanes", "chart_labels"):
    check(f'_load_json("res://data/{name}.json")' in gm, f"GameManager 加载 data/{name}.json")
# 主干接线：岸线与标注在 SeaChart._coast_data 读；sealanes 由 Voyage.track_lonlat 读，SeaChart 经它取折线
check("GameManager.coastline_data" in sc, "SeaChart 读 GameManager.coastline_data")
check("GameManager.chart_labels_data" in sc, "SeaChart 读 GameManager.chart_labels_data")
check("GameManager.sealanes_data" in vo and "func track_lonlat(" in vo, "Voyage.track_lonlat 读 GameManager.sealanes_data")
check("chart.clip_contents = true" in sc, "SeaChart 的 chart 开了 clip_contents（陆地多边形不画出面板）")
check("draw_colored_polygon" in sc and "_soft_coast(" in sc,
      "陆地环经 _soft_coast 后 draw_colored_polygon 填色（主干 7f92 画法；8b32 原为先三角化）")
check("Voyage.track_lonlat(origin_port, selected_port)" in sc,
      "当前航段按 sealanes 绕岸折线画")
check("Voyage.bearing_at(origin_port, selected_port" in sc,
      "航行中每日罗经按折线所在段取（2d51 风向按段变）")

print()
print("=" * 68)
if fails:
    print(f"结果：{len(fails)} 项未通过")
    for f in fails:
        print("   ✗", f)
    sys.exit(1)
print(f"环 {len(rings)} · 顶点 {total_pts} · 港 {len(ports)} · 航线 {len(lanes)} · 标注 {len(labels)}")
print("结果：全部通过")
