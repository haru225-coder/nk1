#!/usr/bin/env python3
"""把 Natural Earth 10m 陆地裁成海图用的闭合环，写入 data/coastline.json。

数据是公有领域。只在需要重生成时跑；游戏运行时读 JSON，不依赖这里。
用法：
  python3 tools/build_coastline.py [/path/to/ne_10m_land.geojson]
缺文件时会从 martynafford/natural-earth-geojson 下载。
"""
import json
import sys
import urllib.request
from pathlib import Path

from shapely.geometry import Polygon, box, shape
from shapely.validation import make_valid

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "coastline.json"
DEFAULT_SRC = Path("/tmp/ne/ne_10m_land.geojson")
SRC_URL = (
    "https://raw.githubusercontent.com/martynafford/natural-earth-geojson/"
    "master/10m/physical/ne_10m_land.json"
)

# 比海图最大取景再宽一圈，裁切直边落在画面外。
LON_MIN, LAT_MIN, LON_MAX, LAT_MAX = 100.0, 6.0, 140.0, 42.0
SIMPLIFY_DEG = 0.035
# 约 15 km² 以下的碎礁丢掉；澎湖主岛大约 0.006 平方度，留得住。
MIN_AREA = 0.0015
ROUND = 3


def load_geojson(path: Path) -> dict:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        print(f"下载 {SRC_URL}")
        urllib.request.urlretrieve(SRC_URL, path)
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def explode(geom):
    if geom.is_empty:
        return
    if geom.geom_type == "Polygon":
        yield geom
    elif geom.geom_type in ("MultiPolygon", "GeometryCollection"):
        for g in geom.geoms:
            yield from explode(g)


def clean_ring(coords):
    out = []
    for x, y in coords:
        pt = (round(float(x), ROUND), round(float(y), ROUND))
        if out and pt == out[-1]:
            continue
        out.append(pt)
    if len(out) >= 2 and out[0] == out[-1]:
        out = out[:-1]
    if len(out) < 3:
        return None
    area = 0.0
    for (x1, y1), (x2, y2) in zip(out, out[1:] + out[:1]):
        area += x1 * y2 - x2 * y1
    if abs(area) < 1e-8:
        return None
    if area < 0:
        out.reverse()
    # 去掉共线点，减轻三角化失败。
    kept = []
    n = len(out)
    for i in range(n):
        a = out[(i - 1) % n]
        b = out[i]
        c = out[(i + 1) % n]
        cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if abs(cross) < 1e-9:
            continue
        kept.append(b)
    if len(kept) < 3:
        return None
    kept.append(kept[0])
    return kept


def name_for(poly) -> str:
    c = poly.centroid
    lon, lat = c.x, c.y
    area = poly.area
    rules = (
        ("penghu", 119.35, 23.35, 119.85, 23.85, 0.001, 0.05),
        ("taiwan", 119.9, 21.7, 122.2, 25.5, 0.5, 8),
        ("hainan", 108.4, 17.9, 111.3, 20.4, 0.4, 8),
        ("jeju", 126.05, 33.05, 127.05, 33.65, 0.02, 0.6),
        ("kyushu", 129.3, 30.9, 132.1, 34.2, 0.8, 12),
        ("mainland", 100, 18, 128, 42, 20, 1e9),
    )
    for name, x0, y0, x1, y1, a0, a1 in rules:
        if x0 <= lon <= x1 and y0 <= lat <= y1 and a0 <= area <= a1:
            return name
    return "isle"


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    gj = load_geojson(src)
    clip = box(LON_MIN, LAT_MIN, LON_MAX, LAT_MAX)
    lands = []
    seen = {}
    for feat in gj["features"]:
        geom = shape(feat["geometry"])
        if not geom.intersects(clip):
            continue
        part = geom.intersection(clip)
        part = part.simplify(SIMPLIFY_DEG, preserve_topology=True)
        if not part.is_valid:
            part = make_valid(part)
        for poly in explode(part):
            if poly.area < MIN_AREA:
                continue
            ring = clean_ring(poly.exterior.coords)
            if ring is None:
                continue
            # 取整会让简化后的环自交，再修一次并拆开。
            fixed = Polygon(ring)
            if not fixed.is_valid:
                fixed = make_valid(fixed)
            for piece in explode(fixed):
                if piece.area < MIN_AREA:
                    continue
                ring = clean_ring(piece.exterior.coords)
                if ring is None:
                    continue
                again = Polygon(ring)
                if not again.is_valid or again.area < MIN_AREA:
                    continue
                base = name_for(again)
                n = seen.get(base, 0) + 1
                seen[base] = n
                ident = base if n == 1 else f"{base}_{n}"
                lands.append((again.area, ident, ring))

    lands.sort(key=lambda item: (-item[0], item[1]))
    # 同名只保留第一次（面积最大）。其余小岛仍叫 isle_N。
    used = set()
    payload_lands = []
    for area, ident, ring in lands:
        if ident in used:
            ident = "isle"
        if ident == "isle" or ident in used:
            k = 1
            while f"isle_{k}" in used:
                k += 1
            ident = f"isle_{k}"
        used.add(ident)
        payload_lands.append({"id": ident, "ring": [[x, y] for x, y in ring]})

    verts = sum(len(item["ring"]) for item in payload_lands)
    doc = {
        "meta": {
            "title": "东亚海域海图陆地",
            "source": "Natural Earth 10m land, public domain; clipped and simplified",
            "bbox": [LON_MIN, LAT_MIN, LON_MAX, LAT_MAX],
            "simplify_deg": SIMPLIFY_DEG,
            "rings": len(payload_lands),
            "vertices": verts,
        },
        "lands": payload_lands,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"写入 {OUT}  环 {len(payload_lands)}  顶点 {verts}  {OUT.stat().st_size} 字节")
    named = [item["id"] for item in payload_lands if not item["id"].startswith("isle")]
    print("命名:", ", ".join(named))


if __name__ == "__main__":
    main()
