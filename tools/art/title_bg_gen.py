#!/usr/bin/env python3
"""nk-1 标题底图「候选 B」—— 宋绢本程序化重绘。numpy + 标准库，确定性种子，可重复运行。

绢底（经纬平纹 + 纬线条干 + 水渍霉点 + 卷轴折痕）上用淡墨勾真实岸线（data/coastline.json，
只读），近岸三道晕线、远海鱼鳞细浪、陆上宋图山形符号、计里画方淡格；中央留白给标题衬底，
右上（或左上）留空白题签位；兴化按宋《地理图》「州府加方框」点一枚朱砂小框——朱砂是唯一强调色。
不画西式罗盘玫瑰、海怪、经纬网，不做外发光 / 滤镜。

色板取 docs/海图重制设计_2026-09-25.md §六（宋绢本矿物色）与 docs/美术规范.md §2。

产物**不入库**，默认写 ~/tmp/nk1-art-work/title_bg/：
  title_bg_B1_sujuan.png   素绢（浅，纯墨）
  title_bg_B2_jiujuan.png  旧绢（中，淡设色：近岸石青 / 陆上赭浅）
  title_bg_B3_gujuan.png   古绢（深茶褐，贴近现底图的明度）
  sheet.png                三张并排小样
  NOTES.md                 尺寸 / 主色 / 与现底图的差异

用法：
  python3 tools/art/title_bg_gen.py                    # 全部，1920×1080
  python3 tools/art/title_bg_gen.py --only B1,B3
  python3 tools/art/title_bg_gen.py --out /tmp/tbg --width 1280
"""
import argparse
import json
import math
import pathlib
import struct
import zlib

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
COAST = ROOT / "data" / "coastline.json"
PROJ = ROOT / "data" / "chart_projection.json"
OUT = pathlib.Path.home() / "tmp" / "nk1-art-work" / "title_bg"


def hexc(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


# 色板（docs/海图重制设计 §六 / docs/美术规范.md §2 同源）
JUAN = hexc("#e4d3ae")      # 绢底
JIUJUAN = hexc("#cdb88f")   # 旧绢
GEFEN = hexc("#f2ebda")     # 蛤粉
MO = hexc("#2a241d")        # 墨
DANMO = hexc("#5c5247")     # 淡墨
ZHUSHA = hexc("#a8322a")    # 朱砂
SHIQING = hexc("#35607f")   # 石青
SANQING = hexc("#7fa3b5")   # 三青
ZHESHI = hexc("#8c5e34")    # 赭石
ZHEQIAN = hexc("#c39a6b")   # 赭浅

# 兴化（data/ports.json 同坐标）
XINGHUA = (119.01, 25.43)


# ════════════════════════════════════════════════════════════════ 基础工具
def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float32) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def noise(h, w, beta=1.0, seed=0, stretch=(1.0, 1.0), hi=None):
    """谱噪声，零均值单位方差。|F| ∝ f^-beta；stretch=(sx,sy) 把纹理沿 x/y 拉长；hi 为低通边界。"""
    rng = np.random.default_rng(seed)
    F = np.fft.rfft2(rng.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    f = np.sqrt((fx * stretch[0]) ** 2 + (fy * stretch[1]) ** 2)
    f[0, 0] = 1.0
    amp = f ** (-beta)
    if hi:
        amp = amp * np.exp(-(f / hi) ** 2)
    amp[0, 0] = 0
    n = np.fft.irfft2(F * amp, s=(h, w))
    return ((n - n.mean()) / (n.std() + 1e-9)).astype(np.float32)


def smooth1d(n, rng, corr):
    x = rng.standard_normal(n)
    f = np.fft.rfftfreq(n)
    y = np.fft.irfft(np.fft.rfft(x) * np.exp(-2 * (math.pi * corr * f) ** 2), n)
    return ((y - y.mean()) / (y.std() + 1e-9)).astype(np.float32)


def blur(a, sigma):
    """高斯模糊（FFT），边缘复制填充，避免岸线从画幅另一侧绕回来。"""
    a = np.asarray(a, np.float32)
    if sigma <= 0:
        return a
    pad = int(3 * sigma) + 2
    b = np.pad(a, pad, mode="edge")
    h, w = b.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    r = np.fft.irfft2(np.fft.rfft2(b) * g, s=(h, w)).astype(np.float32)
    return r[pad:pad + a.shape[0], pad:pad + a.shape[1]]


def grid(W, H):
    x = np.arange(W, dtype=np.float32)[None, :] + 0.5
    y = np.arange(H, dtype=np.float32)[:, None] + 0.5
    return x, y


def downsample(a, k):
    h, w = a.shape[0] // k, a.shape[1] // k
    return a[:h * k, :w * k].reshape(h, k, w, k).mean(axis=(1, 3))


def contour_line(field, level, width, grad_floor=1e-4):
    """标量场 field 在 level 处的等值线，宽 width 像素（高斯剖面）。|∇f| 近似有号距离。"""
    gy, gx = np.gradient(field)
    g = np.sqrt(gx * gx + gy * gy)
    s = (field - level) / np.maximum(g, grad_floor)
    return np.exp(-(s / np.maximum(width, 1e-3)) ** 2) * (g > grad_floor)


def stroke(alpha, pts, width, value=1.0):
    """在 alpha 上画折线（到线段距离的软边），只算包围盒内。pts: [(x,y),…] 像素坐标。"""
    pts = np.asarray(pts, np.float32)
    H, W = alpha.shape
    pad = width * 2 + 2
    x0 = int(max(0, math.floor(pts[:, 0].min() - pad)))
    x1 = int(min(W, math.ceil(pts[:, 0].max() + pad)))
    y0 = int(max(0, math.floor(pts[:, 1].min() - pad)))
    y1 = int(min(H, math.ceil(pts[:, 1].max() + pad)))
    if x1 <= x0 or y1 <= y0:
        return
    xs = np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5
    ys = np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5
    d = np.full((y1 - y0, x1 - x0), 1e9, np.float32)
    for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
        vx, vy = bx - ax, by - ay
        L2 = max(vx * vx + vy * vy, 1e-6)
        t = np.clip(((xs - ax) * vx + (ys - ay) * vy) / L2, 0, 1)
        d = np.minimum(d, np.hypot(xs - (ax + t * vx), ys - (ay + t * vy)))
    a = np.clip(width * 0.5 + 0.5 - d, 0, 1) * value
    sub = alpha[y0:y1, x0:x1]
    np.maximum(sub, a, out=sub)


def ink(col, a, rgb, weave=None, bite=0.18):
    """墨/色落在绢上：相乘混合——标准绢底上呈 rgb 本色，旧绢上按底色同比压暗（不发灰）；绢纹咬墨（经纬凸处墨略浅）。"""
    a = np.clip(a, 0, 1)
    if weave is not None:
        a = a * (1 - bite + bite * weave)
    target = np.clip(col * (np.asarray(rgb, np.float32) / JUAN), 0, 1)
    return lerp(col, target, a[..., None])


def wash(col, a, rgb):
    """平涂设色（透明水色，直接按 a 混向色值）。"""
    return lerp(col, np.asarray(rgb, np.float32), np.clip(a, 0, 1)[..., None])


# ════════════════════════════════════════════════════════════════ 投影 / 岸线
def load_projection():
    p = json.loads(PROJ.read_text(encoding="utf-8"))
    n, G, rho0, lon0 = p["n"], p["G"], p["rho0"], p["lon0"]

    def proj(lon, lat):
        lon = np.asarray(lon, np.float64)
        lat = np.asarray(lat, np.float64)
        rho = G - np.radians(lat)
        th = n * np.radians(lon - lon0)
        return rho * np.sin(th), rho0 - rho * np.cos(th)
    return proj


def make_view(proj, W, H, center, lon_span):
    """以 center=(lon,lat) 为画心、横向覆盖 lon_span 度，返回 (lon,lat)->像素 的函数。"""
    cx, cy = proj(*center)
    xl, _ = proj(center[0] - lon_span / 2, center[1])
    xr, _ = proj(center[0] + lon_span / 2, center[1])
    scale = W / float(xr - xl)

    def to_px(lon, lat):
        x, y = proj(lon, lat)
        return (x - cx) * scale + W / 2, (cy - y) * scale + H / 2
    return to_px


def raster_land(to_px, W, H, ss=2):
    """把 coastline.json 的陆地环扫描线填充（奇偶规则），ss 倍超采样后缩回 → 抗锯齿陆地覆盖率。"""
    rings = json.loads(COAST.read_text(encoding="utf-8"))["land"]
    Ws, Hs = W * ss, H * ss
    rows, cols = [], []
    for ring in rings:
        r = np.asarray(ring, np.float64)
        px, py = to_px(r[:, 0], r[:, 1])
        px, py = px * ss, py * ss
        if px.max() < -Ws or px.min() > 2 * Ws or py.max() < 0 or py.min() > Hs:
            continue
        ax, ay = px, py
        bx, by = np.roll(px, -1), np.roll(py, -1)
        ylo, yhi = np.minimum(ay, by), np.maximum(ay, by)
        # 扫描线取像素中心 y = k + 0.5；每条边覆盖 k ∈ [ceil(ylo-0.5), ceil(yhi-0.5))
        k0 = np.ceil(ylo - 0.5).astype(np.int64)
        k1 = np.ceil(yhi - 0.5).astype(np.int64)
        k0 = np.clip(k0, 0, Hs)
        k1 = np.clip(k1, 0, Hs)
        cnt = k1 - k0
        keep = cnt > 0
        if not keep.any():
            continue
        ax, ay, bx, by, k0, cnt = ax[keep], ay[keep], bx[keep], by[keep], k0[keep], cnt[keep]
        idx = np.repeat(np.arange(len(k0)), cnt)
        ks = k0[idx] + (np.arange(cnt.sum()) - np.repeat(np.cumsum(cnt) - cnt, cnt))
        yc = ks + 0.5
        t = (yc - ay[idx]) / (by[idx] - ay[idx])
        xc = ax[idx] + t * (bx[idx] - ax[idx])
        xi = np.clip(np.ceil(xc - 0.5).astype(np.int64), 0, Ws)
        rows.append(ks)
        cols.append(xi)
    acc = np.zeros((Hs, Ws + 1), np.int32)
    if rows:
        np.add.at(acc, (np.concatenate(rows), np.concatenate(cols)), 1)
    mask = (np.cumsum(acc, axis=1)[:, :Ws] % 2).astype(np.float32)
    return downsample(mask, ss)


# ════════════════════════════════════════════════════════════════ 绢底
def silk(W, H, seed, base, age=1.0, tone=(1.0, 1.0, 1.0)):
    """画幅绢底：平纹经纬（2px 节距）+ 纬线条干 + 低频明暗 + 水渍潮线 + 霉点 + 卷轴竖折痕 + 四边旧色。
    返回 (rgb, weave)，weave∈[0,1] 供墨色「咬绢」。"""
    rng = np.random.default_rng(seed)
    x, y = grid(W, H)
    pitch = 2
    xi = (np.arange(W) // pitch)
    yi = (np.arange(H) // pitch)
    warp_b = 0.6 * smooth1d(W // pitch + 1, rng, 3) + 0.8 * rng.standard_normal(W // pitch + 1).astype(np.float32)
    weft_b = 0.7 * smooth1d(H // pitch + 1, rng, 6) + 0.9 * rng.standard_normal(H // pitch + 1).astype(np.float32)
    top = ((xi[None, :] + yi[:, None]) % 2 == 0)
    weave = np.where(top, 0.75 + 0.25 * np.tanh(warp_b[xi])[None, :], 0.55 + 0.25 * np.tanh(weft_b[yi])[:, None])
    weave = weave.astype(np.float32)
    slub = noise(H, W, 1.0, seed + 1, stretch=(14, 1))          # 纬线粗细不匀：横向长条
    slub_w = noise(H, W, 1.0, seed + 2, stretch=(1, 14))
    low = noise(H, W, 1.8, seed + 3)
    mid = noise(H, W, 1.0, seed + 4, hi=0.03)
    L = (1 + 0.030 * (weave - 0.65) + 0.016 * slub + 0.007 * slub_w
         + 0.022 * age * low + 0.008 * mid)
    col = base[None, None, :] * L[..., None]
    # 水渍：低频噪声阈上的斑块，边缘一圈潮线更深
    sn = noise(H, W, 2.0, seed + 5)
    st = sstep(1.1, 1.9, sn)
    tide = np.exp(-((sn - 1.15) / 0.05) ** 2) * sstep(0.6, 1.4, noise(H, W, 1.2, seed + 6))
    col = lerp(col, col * np.array([0.90, 0.82, 0.68], np.float32), (0.35 * st + 0.28 * tide)[..., None] * age)
    # 霉点（foxing）
    n_fox = int(W * H / 26000 * age)
    fox = np.zeros((H, W), np.float32)
    for _ in range(n_fox):
        cx, cy, r = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0.8, 3.2)
        x0, x1 = int(max(0, cx - 4 * r)), int(min(W, cx + 4 * r + 1))
        y0, y1 = int(max(0, cy - 4 * r)), int(min(H, cy + 4 * r + 1))
        d2 = (x[:, x0:x1] - cx) ** 2 + (y[y0:y1, :] - cy) ** 2
        np.maximum(fox[y0:y1, x0:x1], np.exp(-d2 / (r * r)) * rng.uniform(0.3, 1.0), out=fox[y0:y1, x0:x1])
    col = lerp(col, col * np.array([0.80, 0.68, 0.52], np.float32), 0.40 * fox[..., None] * age)
    # 卷轴竖折痕：一明一暗成对，沿长度断续
    for i in range(1, 6):
        cxr = W * i / 6 + rng.uniform(-0.04, 0.04) * W
        amp = sstep(-0.8, 0.6, noise(1, H, 1.5, seed + 20 + i)[0])[:, None]
        dark = np.exp(-((x - cxr) / 1.3) ** 2)
        light = np.exp(-((x - cxr - 2.2) / 1.8) ** 2)
        col = col * (1 - 0.07 * age * dark * amp)[..., None] + 0.035 * age * (light * amp)[..., None]
    # 四边旧色：越近画边越黄褐、越暗（绢边受潮与手泽）
    dx = np.minimum(x, W - x) / W
    dy = np.minimum(y, H - y) / H
    edge = 1 - sstep(0.0, 0.16, np.minimum(dx * 1.6, dy * 2.2) + 0.02 * low)
    col = lerp(col, col * np.array([0.80, 0.70, 0.55], np.float32), (0.55 * edge * age)[..., None])
    col = col * np.asarray(tone, np.float32)
    return np.clip(col, 0, 1).astype(np.float32), weave


# ════════════════════════════════════════════════════════════════ 图面
def reserve_mask(W, H, cy=0.47, rx=0.29, ry=0.34):
    """中央留白：标题衬底（TitleStage 的 TitlePlaque，1280 基准约 720×400 居中）所在处图线淡出。1=保留线条。"""
    x, y = grid(W, H)
    r = np.sqrt(((x / W - 0.5) / rx) ** 2 + ((y / H - cy) / ry) ** 2)
    return sstep(0.72, 1.12, r)


def slip_box(W, H, side):
    """空白题签位（竖签），1920 基准约 78×330，距上边 7.5%；side='right'|'left'。"""
    s = W / 1920.0
    w, h = 78 * s, 330 * s
    top = 0.075 * H
    left = W * 0.925 - w if side == "right" else W * 0.075
    return left, top, w, h


def draw_slip(col, box, weave, seed):
    x, y = grid(col.shape[1], col.shape[0])
    left, top, w, h = box
    inside = sstep(-0.8, 0.8, np.minimum(np.minimum(x - left, left + w - x), np.minimum(y - top, top + h - y)))
    # 投影一丝（签条贴在绢上略浮起）
    sh = sstep(-0.8, 0.8, np.minimum(np.minimum(x - left - 3, left + w + 3 - x), np.minimum(y - top - 4, top + h + 4 - y)))
    shadow = blur(sh, 3.0) * (1 - inside)
    col = col * (1 - 0.10 * shadow)[..., None]
    # 签纸比所在绢面提亮一档、向蛤粉靠三成：浅绢上近白，古绢上是旧纸色，不跳出画面
    l0, t0 = int(left), int(top)
    local = col[t0:t0 + int(h), l0:l0 + int(w)].mean(axis=(0, 1))
    paper = lerp(np.clip(local * 1.22, 0, 1), GEFEN, 0.3)
    paper = paper[None, None, :] * (0.97 + 0.03 * noise(*col.shape[:2], 1.2, seed))[..., None]
    col = lerp(col, paper, inside[..., None])
    a = np.zeros(col.shape[:2], np.float32)
    s = w / 78.0
    for inset, wd in ((4 * s, 1.6 * s), (8 * s, 0.8 * s)):
        l, t, r, b = left + inset, top + inset, left + w - inset, top + h - inset
        stroke(a, [(l, t), (r, t), (r, b), (l, b), (l, t)], wd)
    return ink(col, 0.78 * a, MO, weave)


def mountain_glyph(alpha, cx, cy, size, rng, value):
    """宋图山形符号：两三座尖峰的外廓 + 一两笔皴线。"""
    n_peaks = rng.integers(2, 4)
    xs = np.linspace(-1, 1, n_peaks * 2 + 1)
    pts = []
    for i, xv in enumerate(xs):
        if i % 2 == 0:
            yv = rng.uniform(-0.05, 0.1) if 0 < i < len(xs) - 1 else 0.15
        else:
            yv = -rng.uniform(0.55, 1.0) * (1.15 if i == n_peaks else 0.9)
        pts.append((cx + xv * size, cy + yv * size * 0.8))
    w = max(1.0, size * 0.09)
    stroke(alpha, pts, w, value)
    # 皴线：峰下一笔斜短线
    for i in range(1, len(pts) - 1, 2):
        px, py = pts[i]
        if rng.random() < 0.8:
            stroke(alpha, [(px - size * 0.05, py + size * 0.25), (px - size * 0.28, py + size * 0.62)],
                   w * 0.8, value * 0.7)


def fish_scale(W, H, period, seed):
    """鱼鳞细浪：错行排列的上半圆弧。返回线条强度 [0,1]。"""
    x, y = grid(W, H)
    row_h = period * 0.5
    row = np.floor(y / row_h)
    xo = x + (row % 2) * period * 0.5
    cx = (np.floor(xo / period) + 0.5) * period
    cy = (row + 1.0) * row_h
    d = np.hypot(xo - cx, (y - cy) * 1.1)
    arc = np.exp(-((d - period * 0.46) / 0.7) ** 2) * (y < cy)
    return arc * sstep(-0.2, 0.6, noise(H, W, 1.3, seed))


def water_lines(W, H, period, seed):
    """水纹：随低频噪声缓缓起伏的横向长波线，按段断开（一笔一笔的短波，不连成等高线）。"""
    x, y = grid(W, H)
    warp = 1.8 * period * noise(H, W, 2.8, seed)
    wob = 0.22 * period * np.sin(x / (period * 1.3) + 3.0 * noise(H, W, 2.6, seed + 1))
    ph = (y + warp + wob) / period
    ln = np.exp(-(((ph - np.floor(ph)) - 0.5) * period / 0.8) ** 2)
    return ln * sstep(0.1, 0.7, noise(H, W, 1.1, seed + 2, stretch=(0.25, 3.0)))


def compose(spec, W, H):
    s = W / 1920.0
    seed = spec["seed"]
    rng = np.random.default_rng(seed)
    proj = load_projection()
    to_px = make_view(proj, W, H, spec["center"], spec["lon_span"])
    land = raster_land(to_px, W, H)

    col, weave = silk(W, H, seed, spec["base"], spec["age"], spec.get("tone", (1, 1, 1)))
    keep = reserve_mask(W, H)
    slip = slip_box(W, H, spec["slip"])
    x, y = grid(W, H)
    l, t, w, h = slip
    slip_clear = sstep(10 * s, 40 * s, np.maximum(np.maximum(l - x, x - l - w), np.maximum(t - y, y - t - h)))
    keep = keep * slip_clear
    dry = sstep(-1.3, -0.2, noise(H, W, 1.4, seed + 31))           # 干笔飞白：线条断续
    press = 0.75 + 0.25 * sstep(-1, 1, noise(H, W, 1.6, seed + 32))  # 行笔轻重

    b_small = blur(land, 1.0 * s)
    b10 = blur(land, 10 * s)
    b40 = blur(land, 40 * s)
    b90 = blur(land, 90 * s)

    # 图框内才落笔（宋图界画：图面止于边框，框外只剩绢边）
    ix = H * 0.036
    clip = sstep(0.0, 2.0 * s, np.minimum(np.minimum(x - ix, W - ix - x), np.minimum(y - ix, H - ix - y)))
    keep = keep * clip
    sea = (1 - land) * clip

    # 设色（B2/B3）：近岸石青晕、陆上赭浅；透明薄涂，避开留白区中心
    if spec.get("sea_wash"):
        near = (1 - land) * sstep(0.0, 0.35, b90) * (1 - b_small)
        col = wash(col, spec["sea_wash"] * near * (0.4 + 0.6 * keep) * clip, spec.get("sea_rgb", SHIQING))
    if spec.get("land_wash"):
        inner = land * sstep(0.55, 0.95, b40)
        col = wash(col, spec["land_wash"] * inner * (0.5 + 0.5 * keep) * clip, ZHEQIAN)

    # 计里画方：极淡方格，断续，海陆皆有（《禹迹图》法）
    if spec.get("grid"):
        cell = 120 * s
        gx = np.abs(((x - W / 2) % cell) - cell / 2) - cell / 2
        gy = np.abs(((y - H / 2) % cell) - cell / 2) - cell / 2
        gl = np.maximum(np.exp(-(gx / (0.55 * s)) ** 2), np.exp(-(gy / (0.55 * s)) ** 2))
        col = ink(col, spec["grid"] * gl * dry * (0.3 + 0.7 * keep) * clip, DANMO, weave)

    # 水纹：海面满铺细长波线（近岸密而显、远海疏而淡），陆上不着一笔——海陆靠水纹分开
    wl = water_lines(W, H, 11 * s, seed + 42)
    near_w = 0.35 + 0.65 * sstep(0.0, 0.25, b90)
    col = ink(col, 1.8 * spec["wave"] * wl * near_w * sea * (1 - b10) * keep * (0.4 + 0.6 * dry), DANMO, weave)

    # 远海鱼鳞细浪：成片出现
    far = (1 - b90) ** 2
    fs = fish_scale(W, H, 24 * s, seed + 40) * far * keep * sea * sstep(0.3, 1.2, noise(H, W, 2.0, seed + 41))
    col = ink(col, 1.4 * spec["wave"] * fs, DANMO, weave)

    # 近岸三道晕线（外扩渐淡、渐平滑）
    for sig, lev, a_line in ((6, 0.16, 0.42), (13, 0.12, 0.28), (24, 0.09, 0.17)):
        f = blur(land, sig * s)
        ln = contour_line(f, lev, 0.75 * s) * (1 - land)
        col = ink(col, spec["line"] * a_line * ln * dry * press * (0.15 + 0.85 * keep) * clip, DANMO, weave)

    # 岸线本笔（留白区里只淡到三成，不挖洞）
    coast = contour_line(b_small, 0.5, (0.85 + 0.45 * press) * s)
    col = ink(col, spec["line"] * 0.86 * coast * (0.55 + 0.45 * dry) * (0.3 + 0.7 * keep) * clip,
              spec["coast_rgb"], weave)

    # 山形符号：成列成簇（山脉随低频噪声走），近岸密、腹地疏
    m = np.zeros((H, W), np.float32)
    ridge = sstep(-0.1, 1.0, noise(H, W, 2.4, seed + 60))
    cand = (land > 0.99) & (b10 > 0.97) & (keep > 0.6)
    ys_, xs_ = np.nonzero(cand[::5, ::5])
    order = rng.permutation(len(xs_))
    placed = []
    min_d = 30 * s
    for i in order[:20000]:
        px, py = xs_[i] * 5 + 2, ys_[i] * 5 + 2
        p_acc = 0.06 + float(ridge[py, px]) * (0.4 + 0.6 * (1 - float(b90[py, px])))
        if rng.random() > p_acc:
            continue
        if any((px - qx) ** 2 + (py - qy) ** 2 < min_d * min_d for qx, qy in placed):
            continue
        placed.append((px, py))
        if len(placed) >= spec["mountains"]:
            break
    for px, py in placed:
        r = float(ridge[py, px])
        mountain_glyph(m, px, py, (11 + 8 * r * rng.uniform(0.5, 1.0)) * s, rng, rng.uniform(0.5, 0.8) + 0.2 * r)
    col = ink(col, spec["line"] * 0.62 * m * (0.6 + 0.4 * dry), DANMO, weave)

    # 兴化：朱砂方框、蛤粉内填（州府加方框）
    hx, hy = to_px(*XINGHUA)
    hx, hy = float(hx), float(hy)
    half = 7 * s
    fill = sstep(-0.6, 0.6, np.minimum(half - np.abs(x - hx), half - np.abs(y - hy)))
    col = lerp(col, np.clip(col * 1.25, 0, 1), 0.9 * fill[..., None])
    sq = np.zeros((H, W), np.float32)
    stroke(sq, [(hx - half, hy - half), (hx + half, hy - half), (hx + half, hy + half),
                (hx - half, hy + half), (hx - half, hy - half)], 1.9 * s)
    col = ink(col, 0.92 * sq, ZHUSHA, weave, bite=0.1)

    # 双边框：外粗内细（宋图界画）
    fr = np.zeros((H, W), np.float32)
    for inset, wd in ((0.030, 2.2), (0.036, 0.9)):
        ix = iy = H * inset  # 四边等距
        stroke(fr, [(ix, iy), (W - ix, iy), (W - ix, H - iy), (ix, H - iy), (ix, iy)], wd * s)
    col = ink(col, 0.70 * fr * (0.6 + 0.4 * dry), MO, weave)

    col = draw_slip(col, slip, weave, seed + 50)
    return np.clip(col, 0, 1), land


SPECS = {
    "B1": dict(
        name="title_bg_B1_sujuan", title="素绢", seed=1101,
        base=JUAN, age=0.75, center=(124.3, 28.4), lon_span=24.0,
        slip="right", line=1.0, coast_rgb=DANMO, wave=0.20, grid=0.07, mountains=150,
    ),
    "B2": dict(
        name="title_bg_B2_jiujuan", title="旧绢", seed=2202,
        base=JIUJUAN, age=1.0, center=(124.3, 28.4), lon_span=24.0,
        slip="right", line=1.05, coast_rgb=MO, wave=0.22, grid=0.0, mountains=150,
        sea_wash=0.34, sea_rgb=lerp(SHIQING, SANQING, 0.5), land_wash=0.30,
    ),
    "B3": dict(
        name="title_bg_B3_gujuan", title="古绢", seed=3303,
        base=hexc("#9a7f59"), age=1.15, tone=(0.92, 0.90, 0.86), center=(121.2, 26.4), lon_span=17.0,
        slip="left", line=1.25, coast_rgb=MO, wave=0.26, grid=0.0, mountains=110,
        sea_wash=0.22, sea_rgb=SHIQING,
    ),
}

NOTES = {
    "B1": "浅绢底（绢底 #E4D3AE），纯墨线稿：淡墨岸线 + 三道近岸晕线 + 远海鱼鳞浪 + 计里画方淡格 + 山形符号；"
          "朱砂只点兴化一框。明度远高于现底图，标题宣纸字要靠 TitlePlaque 淡墨晕托底（现有），衬底外的按钮区会更亮。",
    "B2": "旧绢底（旧绢 #CDB88F），淡设色：近岸石青—三青薄晕、陆内赭浅薄涂，岸线用墨（#2A241D）更肯定。"
          "中明度，海陆色相与现底图同向（陆黄海青），但去掉满屏靛蓝重彩与龟裂做旧。",
    "B3": "古绢茶褐底（传世宋绢的实际旧色），视野收近到闽浙—台湾一带（兴化海口居左中），竖签移左上；"
          "明度最接近现底图，标题现有宣纸 / 亮泥金字色与按钮不需任何改动即可压住。",
}


RECOMMEND = (
    "进游戏看（标题屏 neutral 调色会把底图整体压暗，中央另有 TitlePlaque 云状淡墨晕）：B3 古绢的明度与现底图最近，"
    "淡墨晕几乎融进茶褐绢面，泥金题字、宣纸副题、朱砂「开卷」都不用改——**建议选 B3 直接替换**。"
    "B2 旧绢海陆设色最好认，但浅底上淡墨晕的云状外缘会显成一块墨渍；若选 B2，宜同时把 TitlePlaque 边缘收淡（另开 lane）。"
    "B1 素绢最「宋图」，但同样有墨渍问题，且亮度与序章其他深底页落差最大，只作备选。"
    "换资产（转 JPG、命名、改 Main.gd 的 `bg_world_map.jpg` 引用）由 Snow 定，本 lane 不动 assets/。"
)


# ════════════════════════════════════════════════════════════════ 输出
def write_png(path, rgb):
    a = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, _ = a.shape
    raw = b"".join(b"\x00" + a[i].tobytes() for i in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    path.write_bytes(png)


def main_colors(rgb, land, k=5):
    """主色：按 4bit/通道量化后取像素最多的 k 档（报十六进制与占比）+ 海 / 陆均值 + 平均亮度。"""
    a = (np.clip(rgb, 0, 1) * 255).astype(np.int32)
    q = (a >> 4)
    key = (q[..., 0] << 8) | (q[..., 1] << 4) | q[..., 2]
    vals, counts = np.unique(key, return_counts=True)
    top = np.argsort(-counts)[:k]
    out = []
    flat = key.ravel()
    ar = a.reshape(-1, 3)
    for i in top:
        sel = flat == vals[i]
        c = ar[sel].mean(axis=0)
        out.append(("#%02x%02x%02x" % tuple(int(v) for v in c), counts[i] / flat.size))
    lum = (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]).mean()
    sea = rgb[land < 0.5].mean(axis=0) if (land < 0.5).any() else rgb.mean(axis=(0, 1))
    ld = rgb[land >= 0.5].mean(axis=0) if (land >= 0.5).any() else rgb.mean(axis=(0, 1))
    hx = lambda c: "#%02x%02x%02x" % tuple(int(v * 255 + 0.5) for v in c)
    return out, float(lum), hx(sea), hx(ld)


def sheet(imgs, path, tw=640):
    th = tw * 9 // 16
    gap = 12
    Wt = gap + len(imgs) * (tw + gap)
    canvas = np.full((th + 2 * gap, Wt, 3), 0.10, np.float32)
    for i, im in enumerate(imgs):
        k = im.shape[1] // tw
        sm = np.stack([downsample(im[..., c], k) for c in range(3)], -1)[:th, :tw]
        x0 = gap + i * (tw + gap)
        canvas[gap:gap + sm.shape[0], x0:x0 + sm.shape[1]] = sm
    write_png(path, canvas)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="逗号分隔：B1,B2,B3")
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--width", type=int, default=1920, help="宽（高按 16:9）")
    args = ap.parse_args()
    out = pathlib.Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    W = args.width
    H = W * 9 // 16
    keys = [k.strip() for k in args.only.split(",") if k.strip()] or list(SPECS)
    lines = ["# 标题底图候选 B（程序化宋绢本）", "",
             "生成：`python3 tools/art/title_bg_gen.py`（确定性种子，可复跑）。",
             "现底图：`assets/bg_world_map.jpg`（西式罗盘玫瑰、海怪、满屏靛蓝重彩 + 龟裂做旧）；本组全部不画罗盘 / 海怪 / 经纬网。",
             "现底图实测（2026-09-27）：1672×941 JPG，均色 `#605643`，平均亮度 0.34，"
             "主色 `#384848`/`#283838`（靛墨海）与 `#987858`/`#b89868`（黄褐陆）。",
             ""]
    imgs = []
    for k in keys:
        spec = SPECS[k]
        rgb, land = compose(spec, W, H)
        p = out / (spec["name"] + ".png")
        write_png(p, rgb)
        imgs.append(rgb)
        cols, lum, sea, ld = main_colors(rgb, land)
        print("wrote %s  %dx%d  mean_luma=%.3f sea=%s land=%s" % (p, W, H, lum, sea, ld))
        lines += ["## %s %s — `%s`" % (k, spec["title"], p.name), "",
                  "- 尺寸：%d×%d（16:9，RGB PNG，%.1f MB）" % (W, H, p.stat().st_size / 1e6),
                  "- 主色（4bit 量化前五档）：" + "、".join("`%s` %.0f%%" % (c, r * 100) for c, r in cols),
                  "- 海面均色 `%s`，陆面均色 `%s`，平均亮度 %.2f" % (sea, ld, lum),
                  "- 与现底图差异：" + NOTES[k], ""]
    if len(imgs) > 1:
        sheet(imgs, out / "sheet.png")
    lines += ["## 选稿建议", "", RECOMMEND, ""]
    (out / "NOTES.md").write_text("\n".join(lines), encoding="utf-8")
    print("notes", out / "NOTES.md")


if __name__ == "__main__":
    main()
