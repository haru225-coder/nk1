#!/usr/bin/env python3
"""NK-1 海图/舆图底图流水线（草稿，验证通过后移入 tools/build_terrain.py）。

输入：
  ETOPO 2022 高程子集（NOAA exportImage，EPSG:4326，bbox 103,1,143,49，4000×4800，F32）
  Natural Earth 1:10m land / minor_islands / rivers / lakes（shapefile）
输出（--out 目录）：
  terrain_<W>.png   舆图底色：绢本色板的分层设色 + 晕渲 + 水深分层
  mapdata_<W>.png   着色器数据：R=陆地高度(0..1) G=海深(0..1) B=离岸距离(0..1, 海侧) A=陆地掩膜
  projection.json   投影与画布参数（GDScript 按同一公式正反算）

投影：等距圆锥（标准纬线 15°N / 35°N，中央经线 120°E）。
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import shapefile
import tifffile
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"

# ── 投影 ──────────────────────────────────────────────
PHI1, PHI2, LON0 = 15.0, 35.0, 120.0
# 画布经纬范围（比港口范围宽一圈，视窗贴边不露白）
LON_W, LON_E, LAT_S, LAT_N = 104.0, 136.0, 6.0, 40.0


class Conic:
    def __init__(self, phi1=PHI1, phi2=PHI2, lon0=LON0):
        p1, p2 = math.radians(phi1), math.radians(phi2)
        self.n = (math.cos(p1) - math.cos(p2)) / (p2 - p1)
        self.G = math.cos(p1) / self.n + p1
        self.lon0 = math.radians(lon0)
        self.phi0 = math.radians((phi1 + phi2) * 0.5)
        self.rho0 = self.G - self.phi0

    def forward(self, lon, lat):
        """度 → 投影平面（单位：地球半径=1，y 向北为正）。支持 numpy 数组。"""
        lam = np.radians(lon)
        phi = np.radians(lat)
        rho = self.G - phi
        theta = self.n * (lam - self.lon0)
        x = rho * np.sin(theta)
        y = self.rho0 - rho * np.cos(theta)
        return x, y

    def inverse(self, x, y):
        rho = np.sign(self.n) * np.sqrt(x * x + (self.rho0 - y) ** 2)
        theta = np.arctan2(x, self.rho0 - y) if self.n > 0 else np.arctan2(-x, -(self.rho0 - y))
        phi = self.G - rho
        lam = self.lon0 + theta / self.n
        return np.degrees(lam), np.degrees(phi)


def canvas_bounds(proj: Conic):
    """画布范围：把经纬框边界密采样后投影，取包络。"""
    lons = np.linspace(LON_W, LON_E, 400)
    lats = np.linspace(LAT_S, LAT_N, 400)
    xs, ys = [], []
    for edge in (
        (lons, np.full_like(lons, LAT_S)),
        (lons, np.full_like(lons, LAT_N)),
        (np.full_like(lats, LON_W), lats),
        (np.full_like(lats, LON_E), lats),
    ):
        x, y = proj.forward(*edge)
        xs.append(x)
        ys.append(y)
    xs = np.concatenate(xs)
    ys = np.concatenate(ys)
    return float(xs.min()), float(xs.max()), float(ys.min()), float(ys.max())


# ── 色板（宋绢本：石青 / 石绿 / 赭石 / 纸绢底） ─────────
def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


PAL = {
    # 海：由浅到深（cartography.md §6.4：头绿浅 / 三青 / 石青 / 石青深——「大洋之水碧黑如淀，有山之水碧而绿」）
    "sea_shallow": hexc("#8DB59A"),   # 头绿浅：近岸浅滩
    "sea_mid": hexc("#7FA3B5"),       # 三青：浅海
    "sea_deep": hexc("#35607F"),      # 石青：中深海
    "sea_abyss": hexc("#1F3A52"),     # 石青深：大洋深水
    # 陆：大青绿「先赭后青绿」——平地赭浅，丘陵赭石，山体叠石绿、石青
    "land_low": hexc("#D7BD90"),      # 赭浅（提亮）：平原
    "land_mid": hexc("#C39A6B"),      # 赭浅：丘陵
    "land_hill": hexc("#9C7A4E"),     # 赭石偏亮：低山
    "land_high": hexc("#5E7F63"),     # 石绿偏暗：中山
    "land_peak": hexc("#4E6B7A"),     # 石青偏灰：高山
    "coast_ink": hexc("#2A241D"),     # 墨
    "paper": hexc("#E4D3AE"),         # 绢底
}


def lerp_ramp(t, stops):
    """t: 0..1 数组；stops: [(pos, color)]。"""
    t = np.clip(t, 0.0, 1.0)
    out = np.zeros(t.shape + (3,), dtype=np.float32)
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        m = (t >= p0) & (t <= p1)
        if not m.any():
            continue
        f = ((t[m] - p0) / max(1e-6, p1 - p0))[:, None]
        out[m] = c0 * (1 - f) + c1 * f
    return out


def hillshade(z, cell, az=315.0, alt=45.0, z_factor=1.0):
    """z: 米；cell: 每像素米数。"""
    gy, gx = np.gradient(z * z_factor, cell)
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    azr, altr = math.radians(az), math.radians(alt)
    hs = np.sin(altr) * np.cos(slope) + np.cos(altr) * np.sin(slope) * np.cos(azr - aspect)
    return np.clip(hs, 0, 1).astype(np.float32)


def rasterize_polys(shapes, proj, x0, x1, y0, y1, W, H, value=255):
    """把 shapefile 多边形（外环填 value，内环挖空）画到掩膜。返回 uint8 数组。"""
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    sx = W / (x1 - x0)
    sy = H / (y1 - y0)

    def to_px(pts):
        pts = np.asarray(pts, dtype=np.float64)
        if pts.ndim != 2 or len(pts) < 3:
            return None
        lon, lat = pts[:, 0], pts[:, 1]
        # 快速剔除：完全在画布经纬框之外的环
        if lon.max() < LON_W - 2 or lon.min() > LON_E + 2 or lat.max() < LAT_S - 2 or lat.min() > LAT_N + 2:
            return None
        x, y = proj.forward(lon, lat)
        px = (x - x0) * sx
        py = (y1 - y) * sy
        return list(zip(px.tolist(), py.tolist()))

    for shp in shapes:
        pts = shp.points
        parts = list(shp.parts) + [len(pts)]
        rings = [pts[parts[i]:parts[i + 1]] for i in range(len(parts) - 1)]
        for ring in rings:
            pp = to_px(ring)
            if pp is None:
                continue
            # shapefile：外环顺时针、内环逆时针
            r = np.asarray(ring)
            area = 0.5 * np.sum(r[:-1, 0] * r[1:, 1] - r[1:, 0] * r[:-1, 1])
            d.polygon(pp, fill=value if area < 0 else 0)
    return np.asarray(img)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--out", default=str(HERE / "out"))
    ap.add_argument("--etopo", default=str(DATA / "etopo_98_0_140_44_4200x4400.tif"))
    ap.add_argument("--etopo-bbox", default="98,0,140,44", help="高程子集的 west,south,east,north")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    proj = Conic()
    x0, x1, y0, y1 = canvas_bounds(proj)
    W = args.width
    H = int(round(W * (y1 - y0) / (x1 - x0)))
    print(f"canvas {W}x{H} bounds x[{x0:.4f},{x1:.4f}] y[{y0:.4f},{y1:.4f}]")

    # ── 高程重投影 ──
    z_src = tifffile.imread(args.etopo).astype(np.float32)  # 行自北向南，列自西向东
    bw, bs, be, bn = (float(v) for v in args.etopo_bbox.split(","))
    S_LON0, S_LAT1 = bw, bn
    PPD = z_src.shape[1] / (be - bw)
    assert abs(z_src.shape[0] / (bn - bs) - PPD) < 1e-6, "高程子集横纵分辨率不一致"
    xs = x0 + (np.arange(W) + 0.5) * (x1 - x0) / W
    ys = y1 - (np.arange(H) + 0.5) * (y1 - y0) / H
    X, Y = np.meshgrid(xs, ys)
    lon, lat = proj.inverse(X, Y)
    col = (lon - S_LON0) * PPD - 0.5
    row = (S_LAT1 - lat) * PPD - 0.5
    z = ndimage.map_coordinates(z_src, [row, col], order=1, mode="nearest").astype(np.float32)
    print("elev reprojected", z.min(), z.max())

    # ── 陆地掩膜（Natural Earth 矢量，海岸线锐利，不用高程的 0 m 线） ──
    land_shapes = shapefile.Reader(str(DATA / "ne_10m_land/ne_10m_land.shp")).shapes()
    isl_shapes = shapefile.Reader(str(DATA / "ne_10m_minor_islands/ne_10m_minor_islands.shp")).shapes()
    land = rasterize_polys(land_shapes, proj, x0, x1, y0, y1, W, H)
    isl = rasterize_polys(isl_shapes, proj, x0, x1, y0, y1, W, H)
    land = np.maximum(land, isl) > 0
    print("land frac", land.mean())

    # 高程与掩膜取齐：海里的正高程压成 -1，陆上的负高程抬到 1
    z = np.where(land, np.maximum(z, 1.0), np.minimum(z, -1.0))

    # ── 像素尺寸（米）：投影单位 = 地球半径 ──
    cell_m = (x1 - x0) / W * 6371000.0
    print("cell m", cell_m)

    # ── 晕渲 ──
    zs = ndimage.gaussian_filter(z, 1.2)
    hs = hillshade(np.where(land, zs, 0.0), cell_m, az=315, alt=42, z_factor=1.6)
    hs2 = hillshade(np.where(land, zs, 0.0), cell_m, az=45, alt=35, z_factor=1.6)
    shade = 0.7 * hs + 0.3 * hs2

    # ── 陆地分层设色 ──
    zl = np.clip(z, 0, 4000)
    t_land = np.clip(np.sqrt(zl / 3000.0), 0, 1)
    land_col = lerp_ramp(t_land, [
        (0.0, PAL["land_low"]), (0.28, PAL["land_mid"]), (0.55, PAL["land_hill"]), (0.85, PAL["land_high"]), (1.0, PAL["land_peak"]),
    ])
    # 晕渲叠加：柔光，山影偏冷、受光偏暖
    sh = (shade - 0.55) * 1.35
    land_col = np.clip(land_col + sh[..., None] * np.array([0.30, 0.26, 0.20], dtype=np.float32), 0, 1)

    # ── 离岸距离（像素） ──
    dist_sea = ndimage.distance_transform_edt(~land)
    dist_land = ndimage.distance_transform_edt(land)

    # ── 海深分层 ──
    depth = np.clip(-z, 0, 6000)
    t_sea = np.clip(np.sqrt(depth / 4000.0), 0, 1)
    sea_ramp = [
        (0.0, PAL["sea_shallow"]), (0.16, PAL["sea_mid"]), (0.50, PAL["sea_deep"]), (1.0, PAL["sea_abyss"]),
    ]
    sea_flat = lerp_ramp(t_sea, sea_ramp)
    # 海底地形淡淡晕渲（陆架坡折、海沟能看出来）。只用海侧高程做平滑，陆上先压平成 0，
    # 否则台湾东岸的三千米山体会被高斯核抹进近岸海面，形成一条与岸平行的假「双线」。
    z_sea_only = np.where(land, 0.0, np.minimum(z, 0.0))
    hs_sea = hillshade(ndimage.gaussian_filter(z_sea_only, 2.0), cell_m, az=315, alt=50, z_factor=0.6)
    sea_col = np.clip(sea_flat + ((hs_sea - 0.6) * 0.30)[..., None] * np.array([0.5, 0.6, 0.7], dtype=np.float32), 0, 1)
    # 海底晕渲在紧贴岸 6 px 内淡出（岸线本身由矢量墨线负责，不让晕渲在岸边结成一道线）
    fade = np.clip(dist_sea / 6.0, 0, 1)[..., None]
    sea_col = sea_col * fade + sea_flat * (1 - fade)
    # 近岸浅水晕（指数衰减，不留硬边）
    near = np.exp(-dist_sea / 11.0)
    sea_col = sea_col * (1 - near[..., None] * 0.55) + PAL["sea_shallow"][None, None, :] * (near[..., None] * 0.55)
    # 岸内墨晕：窄而软（3 px 指数衰减，最大 22%），只让岸线略有厚度
    inner = np.exp(-dist_land / 3.0)
    land_col = land_col * (1 - inner[..., None] * 0.22) + PAL["coast_ink"][None, None, :] * (inner[..., None] * 0.22)

    rgb = np.where(land[..., None], land_col, sea_col)

    # ── 纸绢颗粒（低幅噪声，正式版由 shader 做；底图只带一点点，避免平板） ──
    rng = np.random.default_rng(7)
    grain = ndimage.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 0.8) * 0.018
    rgb = np.clip(rgb + grain[..., None], 0, 1)

    Image.fromarray((rgb * 255).astype(np.uint8), "RGB").save(out / f"terrain_{W}.png", optimize=True)

    # ── 着色器数据图 ──
    r = np.clip(np.sqrt(np.clip(z, 0, 4000) / 4000.0), 0, 1)
    g = np.clip(np.sqrt(np.clip(-z, 0, 6000) / 6000.0), 0, 1)
    b = np.clip(dist_sea / 200.0, 0, 1)
    a = land.astype(np.float32)
    data = np.stack([r, g, b, a], axis=-1)
    Image.fromarray((data * 255).astype(np.uint8), "RGBA").save(out / f"mapdata_{W}.png", optimize=True)

    meta = {
        "projection": "equidistant_conic",
        "phi1": PHI1, "phi2": PHI2, "lon0": LON0,
        "n": proj.n, "G": proj.G, "rho0": proj.rho0,
        "lon_range": [LON_W, LON_E], "lat_range": [LAT_S, LAT_N],
        "canvas_px": [W, H],
        "bounds": {"x0": x0, "x1": x1, "y0": y0, "y1": y1},
        "note": "像素 (px,py) = ((x-x0)/(x1-x0)*W, (y1-y)/(y1-y0)*H)；x,y 为投影平面坐标（地球半径=1）。",
    }
    (out / "projection.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    print("wrote", out)


if __name__ == "__main__":
    main()
