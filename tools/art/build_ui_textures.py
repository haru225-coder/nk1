#!/usr/bin/env python3
"""nk-1 UI 贴图生成器 ——「绢本墨笔」。PIL + numpy，确定性种子，可重复运行。

全部按 2× 出图：贴图像素 = 逻辑像素 × 2（基准 1280×720）。输出 assets/ui/nk1/。
ninepatch 类贴图由 tools/art/build_theme.gd 包成 size_override=½ 的
PortableCompressedTexture2D，StyleBoxTexture 按逻辑像素切九宫、按 2× 采样（高分屏不糊）。

用法：
  python3 tools/art/build_ui_textures.py                 # 全部
  python3 tools/art/build_ui_textures.py --only seal,logo
  python3 tools/art/build_ui_textures.py --sheet /tmp/sheet.jpg   # 另出一张总览小样
"""
import argparse
import io
import math
import pathlib
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "ui" / "nk1"
MASHAN = str(ROOT / "assets" / "fonts" / "MaShanZheng-Regular.ttf")
WENKAI = str(ROOT / "assets" / "fonts" / "LXGWWenKai-Medium.ttf")
RSVG = "/opt/homebrew/bin/rsvg-convert"


def hexc(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


# 色板（docs/美术规范.md 同源）
JIAOMO = hexc("#0d0b09")    # 焦墨
MO = hexc("#1a1612")        # 墨
XUAN = hexc("#e9dcc0")      # 宣纸
JIUJUAN = hexc("#cdb88f")   # 旧绢
NIJIN = hexc("#c9a14a")     # 泥金
ZHUSHA = hexc("#b0302a")    # 朱砂
DIANQING = hexc("#1f3a4d")  # 靛青
SHIQING = hexc("#3b6e7a")   # 石青
ZHESHI = hexc("#8a5a2b")    # 赭石
YUEBAI = hexc("#d6e4e8")    # 月白
GOLD_HI = hexc("#ecd08a")
GOLD_LO = hexc("#8f6a26")

GENERATORS = {}
MADE = []


def gen(name):
    def deco(fn):
        GENERATORS[name] = fn
        return fn
    return deco


# ════════════════════════════════════════════════════════════════ 基础工具
def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float32) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def noise(h, w, beta=1.0, seed=0, stretch=(1.0, 1.0), angle=0.0, lo=None, hi=None):
    """周期（可平铺）谱噪声，零均值单位方差。|F| ∝ f^-beta；stretch=(sx,sy) 把纹理沿 x/y 拉长；
    angle 旋转拉长方向；lo/hi 为带通边界（周期/像素）。"""
    rng = np.random.default_rng(seed)
    F = np.fft.fft2(rng.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    ca, sa = math.cos(angle), math.sin(angle)
    u = fx * ca + fy * sa
    v = -fx * sa + fy * ca
    f = np.sqrt((u * stretch[0]) ** 2 + (v * stretch[1]) ** 2)
    f[0, 0] = 1.0
    amp = f ** (-beta)
    if lo:
        amp = amp * (1 - np.exp(-(f / lo) ** 2))
    if hi:
        amp = amp * np.exp(-(f / hi) ** 2)
    amp[0, 0] = 0
    n = np.real(np.fft.ifft2(F * amp))
    return ((n - n.mean()) / (n.std() + 1e-9)).astype(np.float32)


def smooth1d(n, rng, corr):
    """长度 n 的平滑随机序列（单位方差），相关长度 corr 采样点。"""
    x = rng.standard_normal(n)
    f = np.fft.rfftfreq(n)
    y = np.fft.irfft(np.fft.rfft(x) * np.exp(-2 * (math.pi * corr * f) ** 2), n)
    return (y - y.mean()) / (y.std() + 1e-9)


def blur(a, sigma, wrap=False):
    """高斯模糊（FFT）。wrap=True 周期边界（平铺贴图用），否则零填充。"""
    a = np.asarray(a, np.float32)
    if sigma <= 0:
        return a
    if a.ndim == 3:
        return np.stack([blur(a[..., i], sigma, wrap) for i in range(a.shape[2])], -1)
    pad = 0 if wrap else int(3 * sigma) + 2
    b = np.pad(a, pad) if pad else a
    h, w = b.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    r = np.real(np.fft.ifft2(np.fft.fft2(b) * g)).astype(np.float32)
    return r[pad:pad + a.shape[0], pad:pad + a.shape[1]] if pad else r


def band(d, a, b):
    """像素中心距离 d 落在 [a,b] 区间的覆盖率（盒式抗锯齿）。a/b 可为数组。"""
    return np.clip(np.minimum(d + 0.5, b) - np.maximum(d - 0.5, a), 0.0, 1.0)


def grid(W, H):
    x = np.arange(W, dtype=np.float32)[None, :] + 0.5
    y = np.arange(H, dtype=np.float32)[:, None] + 0.5
    return x, y


def rect_dist(W, H, inset=0.0, chamfer=0.0):
    """到（内缩 inset 的）矩形边的距离，内正外负；chamfer>0 时四角切角（古建委角）。"""
    x, y = grid(W, H)
    dx = np.minimum(x - inset, W - x - inset)
    dy = np.minimum(y - inset, H - y - inset)
    d = np.minimum(dx, dy)
    if chamfer > 0:
        d = np.minimum(d, (dx + dy - chamfer) / math.sqrt(2))
    return d


def tile_sample(tile, W, H, ox, oy):
    """把周期贴图铺到 W×H 画布，使画布 (ox,oy) 对应贴图原点——九宫中段即一整个周期。"""
    ph, pw = tile.shape[:2]
    ys = (np.arange(H) - oy) % ph
    xs = (np.arange(W) - ox) % pw
    return tile[ys][:, xs]


def over(base_rgb, base_a, rgb, a):
    """Porter-Duff over：把 (rgb,a) 叠到 (base_rgb,base_a) 上。rgb 可为 3 元色或数组。"""
    a = np.clip(np.asarray(a, np.float32), 0, 1)
    rgb = np.broadcast_to(np.asarray(rgb, np.float32), base_rgb.shape)
    out_a = a + base_a * (1 - a)
    num = rgb * a[..., None] + base_rgb * (base_a * (1 - a))[..., None]
    safe = np.maximum(out_a, 1e-6)[..., None]
    out_rgb = np.where(out_a[..., None] > 1e-6, num / safe, rgb)
    return out_rgb.astype(np.float32), out_a.astype(np.float32)


def canvas(W, H, rgb=MO):
    return np.broadcast_to(np.asarray(rgb, np.float32), (H, W, 3)).copy(), np.zeros((H, W), np.float32)


def save(name, rgb, a=None):
    OUT.mkdir(parents=True, exist_ok=True)
    rgb = np.clip(rgb, 0, 1)
    if a is not None and (rgb.shape[0] % 2 or rgb.shape[1] % 2):
        # 2× 贴图保持偶数边长，逻辑尺寸 = 像素 ÷ 2 恰为整数（补一行 / 一列全透明）
        ph, pw = rgb.shape[0] % 2, rgb.shape[1] % 2
        rgb = np.pad(rgb, ((0, ph), (0, pw), (0, 0)), mode="edge")
        a = np.pad(np.clip(a, 0, 1), ((0, ph), (0, pw)))
    if a is None:
        img = Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB")
    else:
        arr = np.dstack([rgb, np.clip(a, 0, 1)[..., None]])
        img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")
    p = OUT / name
    img.save(p, optimize=True)
    MADE.append(name)
    print(f"  {name:32s} {img.size[0]}×{img.size[1]}  {p.stat().st_size / 1024:.0f} KB")


def svg_rgba(body, W, H, vb=None):
    vb = vb or f"0 0 {W} {H}"
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="{vb}">{body}</svg>')
    out = subprocess.run([RSVG, "-w", str(W), "-h", str(H)], input=svg.encode(),
                         capture_output=True, check=True).stdout
    return np.asarray(Image.open(io.BytesIO(out)).convert("RGBA"), np.float32) / 255.0


def svg_alpha(body, W, H, vb=None):
    return svg_rgba(body, W, H, vb)[..., 3]


def gold_color(H, W, seed, bright=1.0):
    """泥金：竖向明暗 + 金箔颗粒 + 零星闪点。返回 H×W×3。"""
    n = noise(H, W, 0.9, seed)
    fine = noise(H, W, 0.2, seed + 1)
    t = sstep(-1.6, 1.6, n)[..., None]
    col = lerp(GOLD_LO, GOLD_HI, 0.35 + 0.45 * t) * (1 + 0.06 * fine[..., None])
    spark = sstep(2.4, 3.2, fine)[..., None]
    col = lerp(col, np.array([1.0, 0.95, 0.8], np.float32), 0.6 * spark)
    return np.clip(col * bright, 0, 1)


def fibers(h, w, count, seed, length=(20, 90), width=(0.6, 1.4), curl=0.08, val=(0.4, 1.0), ss=3):
    """可平铺的纤维层（抄纸纤维 / 草屑 / 绢丝裂）：逐根随机游走折线，越界处环绕绘制。"""
    rng = np.random.default_rng(seed)
    img = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        ang = rng.uniform(0, math.pi * 2)
        L = rng.uniform(*length)
        steps = max(4, int(L / 3))
        da = rng.normal(0, curl)
        pts = []
        for _ in range(steps):
            pts.append((x, y))
            ang += da + rng.normal(0, curl * 0.6)
            x += math.cos(ang) * L / steps
            y += math.sin(ang) * L / steps
        wid = max(1, int(round(rng.uniform(*width) * ss)))
        v = int(255 * rng.uniform(*val))
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for ox in (-w, 0, w):
            if max(xs) + ox < -2 or min(xs) + ox > w + 2:
                continue
            for oy in (-h, 0, h):
                if max(ys) + oy < -2 or min(ys) + oy > h + 2:
                    continue
                d.line([((px + ox) * ss, (py + oy) * ss) for px, py in pts], fill=v, width=wid, joint="curve")
    return np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0


def specks(h, w, count, seed, r=(0.6, 2.2)):
    """可平铺的小墨点。"""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for _ in range(count):
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        rad = rng.uniform(*r)
        dx = (xx - cx + w / 2) % w - w / 2
        dy = (yy - cy + h / 2) % h - h / 2
        out = np.maximum(out, rng.uniform(0.3, 1.0) * np.exp(-(dx * dx + dy * dy) / (2 * rad * rad)))
    return out


# ════════════════════════════════════════════════════════════════ 平铺底纹
def paper_tile(S, seed=100, base=XUAN, lowfreq=1.0):
    """宣纸：云状絮纹 + 长纤维 + 帘纹链纹 + 草屑 + 细微墨渍。
    lowfreq：低频成分（云絮明暗、暖黄斑、污渍、墨点）的强度。九宫中段按周期平铺，低频斑块会排成网格，
    面板中段用 0.25–0.35，只留纤维 / 帘纹这类高频质感。"""
    clouds = noise(S, S, 1.5, seed)
    mid = noise(S, S, 0.9, seed + 1, hi=0.12)
    grain = noise(S, S, 0.25, seed + 2)
    f_light = fibers(S, S, int(S * S / 480), seed + 3, length=(16, 110), width=(0.5, 1.2), curl=0.05, val=(0.3, 1.0))
    f_dark = fibers(S, S, int(S * S / 3000), seed + 4, length=(4, 22), width=(0.5, 1.0), curl=0.2, val=(0.3, 1.0))
    x, y = grid(S, S)
    laid = (0.5 + 0.5 * np.cos(2 * np.pi * y / 8)) * (0.6 + 0.4 * noise(S, S, 1.2, seed + 5))
    chain = np.exp(-(((x % 128) - 64) / 2.0) ** 2) * (0.5 + 0.5 * sstep(-1, 1, noise(S, S, 1.4, seed + 6)))
    n_ink = int(round(max(2, S // 170) * lowfreq)) if lowfreq >= 0.5 else 0
    ink = specks(S, S, n_ink, seed + 7, r=(0.5, 1.6)) if n_ink else np.zeros((S, S), np.float32)
    smudge = sstep(1.6, 2.8, noise(S, S, 1.7, seed + 8))
    L = (1 + 0.028 * lowfreq * clouds + 0.010 * mid + 0.010 * grain + 0.040 * f_light - 0.11 * f_dark
         - 0.007 * laid - 0.014 * chain - 0.30 * ink - 0.035 * lowfreq * smudge)
    col = base[None, None, :] * L[..., None]
    warm = sstep(0.3, 2.0, -clouds)[..., None]
    col = lerp(col, col * np.array([1.0, 0.955, 0.87], np.float32), 0.55 * lowfreq * warm)
    return np.clip(col, 0, 1).astype(np.float32)


def silk_tile(S, seed=200, base=JIUJUAN, age=1.0, lowfreq=1.0):
    """旧绢：平纹经纬（4px 节距）+ 纬线粗细不匀的横向长条纹 + 水渍 + 霉点 + 绢裂。
    lowfreq：低频明暗 / 水渍 / 霉点 / 磨损的强度（面板中段平铺用 0.25–0.4，见 paper_tile）。"""
    pitch = 4
    rng = np.random.default_rng(seed)
    x = np.arange(S)
    wi, hi_ = x // pitch, x // pitch
    n_thr = S // pitch
    warp_b = 0.6 * smooth1d(n_thr, rng, 3) + 0.8 * rng.standard_normal(n_thr)
    weft_b = 0.7 * smooth1d(n_thr, rng, 5) + 0.9 * rng.standard_normal(n_thr)
    slub_weft = noise(S, S, 1.0, seed + 1, stretch=(10, 1))
    slub_warp = noise(S, S, 1.0, seed + 2, stretch=(1, 10))
    px = ((x % pitch) + 0.5) / pitch
    prof_warp = np.sin(np.pi * px)[None, :]
    prof_weft = np.sin(np.pi * px)[:, None]
    top = ((wi[None, :] + hi_[:, None]) % 2 == 0)
    weave = np.where(top, np.broadcast_to(prof_warp, (S, S)), np.broadcast_to(prof_weft, (S, S)))
    L = (1 + 0.036 * (weave - 0.64) + 0.013 * weft_b[hi_][:, None] + 0.007 * warp_b[wi][None, :]
         + 0.013 * slub_weft + 0.006 * slub_warp)
    low = noise(S, S, 1.6, seed + 3)
    L = L + 0.034 * lowfreq * low + 0.012 * noise(S, S, 0.8, seed + 8, hi=0.08)
    cracks = fibers(S, S, int(S * S / 9000), seed + 4, length=(30, 140), width=(0.5, 0.8), curl=0.03, val=(0.4, 1.0))
    L = L - 0.06 * age * cracks
    col = base[None, None, :] * L[..., None]
    stain = sstep(0.7, 2.4, noise(S, S, 1.8, seed + 5))[..., None] * age * lowfreq
    col = lerp(col, col * np.array([0.86, 0.77, 0.63], np.float32), 0.45 * stain)
    n_fox = int(round(max(2, int(S * S / 30000)) * lowfreq)) if lowfreq >= 0.5 else 0
    if n_fox:
        fox = specks(S, S, n_fox, seed + 6, r=(1.5, 5.0))[..., None] * age
        col = lerp(col, col * np.array([0.78, 0.66, 0.50], np.float32), 0.45 * fox)
    wear = sstep(1.2, 2.6, noise(S, S, 1.3, seed + 7))[..., None] * age * lowfreq
    col = lerp(col, col * 1.05 + 0.02, 0.5 * wear)
    return np.clip(col, 0, 1).astype(np.float32)


def ink_tile(S, seed=300, alpha=0.86):
    """深墨（靛墨）：焦墨底 + 靛青晕 + 横向刷痕 + 极淡绢纹；返回 (rgb, a)。"""
    c = noise(S, S, 1.9, seed)                      # 大片、缓的靛晕（不要迷彩斑）
    streak = noise(S, S, 1.0, seed + 2, stretch=(9, 1))
    t = sstep(-2.0, 2.0, c)[..., None]
    col = lerp(JIAOMO * 1.05, DIANQING * 0.72 + JIAOMO * 0.28, 0.20 + 0.36 * t)
    col = col * (1 + 0.045 * streak[..., None] + 0.02 * noise(S, S, 0.6, seed + 4)[..., None])
    weave = silk_tile(S, seed + 3, base=np.array([1, 1, 1], np.float32), age=0.0)[..., 0]
    col = col * (0.9 + 0.1 * weave[..., None] / weave.mean())
    a = np.clip(alpha + 0.035 * c, alpha - 0.07, min(0.97, alpha + 0.07))
    return np.clip(col, 0, 1).astype(np.float32), a.astype(np.float32)


@gen("tiles")
def gen_tiles():
    save("tex_paper_xuan.png", paper_tile(512, 101, lowfreq=0.5))
    save("tex_silk_old.png", silk_tile(512, 201, lowfreq=0.5))
    rgb, a = ink_tile(512, 301)
    save("tex_ink_wash.png", rgb, a)
    # 不透明版：AcceptDialog 正文底（嵌入式窗口本身会清成灰底，半透明墨会透灰）
    rgb, _ = ink_tile(256, 302, 1.0)
    save("tex_ink_solid.png", rgb)


# ════════════════════════════════════════════════════════════════ 面板 ninepatch
def dry_gaps(W, H, P, TM, seed, strength=0.5):
    """沿边走向的飞白缺口：横边用横向拉长噪声，竖边用竖向拉长噪声（均按 P 周期，九宫平铺无缝）。"""
    nh = tile_sample(noise(P, P, 1.0, seed, stretch=(14, 1))[..., None], W, H, TM, TM)[..., 0]
    nv = tile_sample(noise(P, P, 1.0, seed + 1, stretch=(1, 14))[..., None], W, H, TM, TM)[..., 0]
    x, y = grid(W, H)
    horiz = np.minimum(y, H - y) < np.minimum(x, W - x)
    n = np.where(horiz, nh, nv)
    return 1 - strength * sstep(0.9, 1.9, n)


def corner_boxes(W, H, TM):
    x, y = grid(W, H)
    return ((x < TM) | (x > W - TM)) & ((y < TM) | (y > H - TM))


def four_corners(mask_tl, W, H):
    """把左上角的 TM×TM 贴片镜像到四角，返回整幅遮罩。"""
    m = np.zeros((H, W), np.float32)
    k = mask_tl.shape[0]
    m[:k, :k] = np.maximum(m[:k, :k], mask_tl)
    m[:k, W - k:] = np.maximum(m[:k, W - k:], mask_tl[:, ::-1])
    m[H - k:, :k] = np.maximum(m[H - k:, :k], mask_tl[::-1, :])
    m[H - k:, W - k:] = np.maximum(m[H - k:, W - k:], mask_tl[::-1, ::-1])
    return m


def shadow_layer(d, SH, strength=0.5):
    out = np.clip(-d, 0, None)
    return strength * np.clip(1 - out / SH, 0, 1) ** 2.2 * (d < 0.5)


def silk_corner_svg(TM, g, sw=2.4):
    """绢面板角花（左上）：泥金内线在角上委角内折，折角方池里嵌一枚回纹。"""
    s = 17
    n = g + s
    e = TM + 1
    q = g + 3.2      # 回纹外框
    r = n - 3.2
    return (f'<g fill="none" stroke="#fff" stroke-linecap="square" stroke-linejoin="miter">'
            f'<path d="M{e},{g} H{n} V{n} H{g} V{e}" stroke-width="{sw}"/>'
            f'<path d="M{q},{r} V{q} H{r} V{r} H{q + 4} V{q + 4} H{r - 4} V{r - 4.2}" stroke-width="1.9"/>'
            f'</g>')


def silk_corner_ink_svg(TM, g):
    """绢面板角花的墨线部分：沿委角内侧再走一道发丝墨线，成双线委角。"""
    k = g + 5.5
    n = g + 17 + 5.5
    e = TM + 1
    return (f'<path d="M{e},{k} H{n} V{n} H{k} V{e}" fill="none" stroke="#fff" stroke-width="1.3" '
            f'stroke-linecap="square" stroke-linejoin="miter"/>')


@gen("panel_silk")
def gen_panel_silk():
    """绢面板：旧绢画心 + 焦墨细边 + 泥金委角内线 + 回纹角花 + 外投影。
    中段周期 512（逻辑 256），低频水渍压到 0.25：大面板（文书）上不再排出重复的污渍网格。"""
    P, SH, B = 512, 12, 44
    TM = SH + B
    W = H = 2 * TM + P
    d = rect_dist(W, H, SH)
    body = np.clip(d + 0.5, 0, 1)
    silk = tile_sample(silk_tile(P, 211, lowfreq=0.25), W, H, TM, TM)
    # 画心向边缘微暗（旧绢四边受潮发黄）
    silk = silk * (1 - 0.10 * np.exp(-np.maximum(d, 0) / 26.0))[..., None]
    rgb, a = canvas(W, H, JIAOMO)
    rgb, a = over(rgb, a, JIAOMO, shadow_layer(d, SH, 0.55))
    rgb, a = over(rgb, a, silk, body)
    n1 = tile_sample(noise(P, P, 1.0, 212)[..., None], W, H, TM, TM)[..., 0]
    ink = band(d, 0, 3.2 + 0.35 * n1) * dry_gaps(W, H, P, TM, 213, 0.3)
    rgb, a = over(rgb, a, JIAOMO, ink * 0.96)
    g = SH + 11  # 泥金线中心（画布坐标）
    cb = corner_boxes(W, H, TM)
    straight = band(d, 9.8, 12.2) * (~cb)
    corner = four_corners(svg_alpha(silk_corner_svg(TM, g), TM, TM), W, H) * cb
    gold_m = np.maximum(straight, corner)
    ink_c = four_corners(svg_alpha(silk_corner_ink_svg(TM, g), TM, TM), W, H) * cb
    rgb, a = over(rgb, a, MO, ink_c * 0.62)
    # 金线下压一道极淡墨影，浅绢上也能看清；金色取偏深的泥金（浅底上亮金会发灰）
    shade = np.roll(np.roll(gold_m, 1, 0), 1, 1) * (1 - gold_m)
    rgb, a = over(rgb, a, JIAOMO, 0.22 * shade * body)
    rgb, a = over(rgb, a, gold_color(H, W, 214, 0.80), gold_m)
    save("panel_silk.png", rgb, a)


@gen("panel_paper")
def gen_panel_paper():
    """宣纸卡：宣纸底 + 焦墨干笔外框 + 发丝内线 + 角上小墨钩。给设施卡 / 募人卡 / 提示框用。"""
    for name, P, SH, B, lw in (("panel_paper.png", 512, 10, 30, 4.2), ("panel_tip.png", 128, 6, 14, 2.6)):
        TM = SH + B
        W = H = 2 * TM + P
        d = rect_dist(W, H, SH)
        body = np.clip(d + 0.5, 0, 1)
        paper = tile_sample(paper_tile(P, 111 + P, lowfreq=0.3), W, H, TM, TM)
        paper = paper * (1 - 0.07 * np.exp(-np.maximum(d, 0) / 18.0))[..., None]
        rgb, a = canvas(W, H, JIAOMO)
        rgb, a = over(rgb, a, JIAOMO, shadow_layer(d, SH, 0.5))
        rgb, a = over(rgb, a, paper, body)
        n1 = tile_sample(noise(P, P, 1.1, 115 + P)[..., None], W, H, TM, TM)[..., 0]
        ink = band(d, 0, lw + 1.0 * n1) * dry_gaps(W, H, P, TM, 116 + P, 0.6)
        rgb, a = over(rgb, a, JIAOMO, ink)
        hair = band(d, lw + 4, lw + 5.2) * 0.55
        rgb, a = over(rgb, a, MO, hair)
        if B >= 30:
            k = TM
            tl = svg_alpha(f'<path d="M{k + 1},{SH + lw + 10} H{SH + lw + 10} V{k + 1}" fill="none" stroke="#fff" '
                           f'stroke-width="2.4" stroke-linecap="square"/>'
                           f'<rect x="{SH + lw + 6}" y="{SH + lw + 6}" width="5" height="5" fill="#fff"/>', k, k)
            rgb, a = over(rgb, a, MO, four_corners(tl, W, H) * corner_boxes(W, H, TM) * 0.85)
        save(name, rgb, a)


@gen("panel_ink")
def gen_panel_ink():
    """深墨面板：半透明靛墨 + 焦墨边 + 淡泥金内线 + 包角金钩。状态栏 / 对话压底。"""
    P, SH, B = 512, 8, 32
    TM = SH + B
    W = H = 2 * TM + P
    d = rect_dist(W, H, SH)
    body = np.clip(d + 0.5, 0, 1)
    irgb, ia = ink_tile(P, 311, 0.89)
    irgb = tile_sample(irgb, W, H, TM, TM)
    ia = tile_sample(ia[..., None], W, H, TM, TM)[..., 0]
    # 边缘略加深，面板边界在亮背景上也立得住
    ia = np.clip(ia + 0.08 * np.exp(-np.maximum(d, 0) / 14.0), 0, 0.97)
    rgb, a = canvas(W, H, JIAOMO)
    rgb, a = over(rgb, a, JIAOMO, shadow_layer(d, SH, 0.35))
    rgb, a = over(rgb, a, irgb, body * ia)
    rgb, a = over(rgb, a, JIAOMO, band(d, 0, 2.5) * 0.9)
    gm = band(d, 8, 10)
    x, y = grid(W, H)
    ex = np.minimum(x - SH, W - SH - x)
    ey = np.minimum(y - SH, H - SH - y)
    near = (ex < TM - SH - 1) & (ey < TM - SH - 1)      # 包角只落在九宫角块里，免得边段平铺出金点
    bracket = band(d, 7, 11) * near * ((ex < 11.5) | (ey < 11.5))
    dot = (np.abs(ex - 16) < 2.6) & (np.abs(ey - 16) < 2.6)
    gold = gold_color(H, W, 314)
    rgb, a = over(rgb, a, gold, gm * 0.42 * (~near))
    rgb, a = over(rgb, a, gold, np.maximum(bracket, dot.astype(np.float32) * 0.9))
    save("panel_ink.png", rgb, a)


@gen("window_frame")
def gen_window_frame():
    """嵌入式窗口（AcceptDialog）外框：顶上一条旧绢题签（马善政墨字标题），四周靛墨裱边 + 泥金线。
    画布（贴图像素）：投影 10 + 边 12；顶部另有 72 的题签。九宫边距见 build_theme.gd。"""
    P, SH = 256, 10
    side, top, inner = 12, 84, 20
    ML = SH + side + inner
    MT = SH + top + inner
    W, H = 2 * ML + P, MT + P + ML
    d = rect_dist(W, H, SH)
    body = np.clip(d + 0.5, 0, 1)
    irgb, ia = ink_tile(P, 321, 0.95)
    irgb = tile_sample(irgb, W, H, ML, MT)
    ia = tile_sample(ia[..., None], W, H, ML, MT)[..., 0]
    x, y = grid(W, H)
    rgb, a = canvas(W, H, JIAOMO)
    rgb, a = over(rgb, a, JIAOMO, shadow_layer(d, SH, 0.5))
    rgb, a = over(rgb, a, irgb, body * np.clip(ia + 0.03, 0, 0.98))
    # 裱边：靛青绫
    mount = band(d, 2.5, side)
    rgb, a = over(rgb, a, DIANQING * 0.55 + JIAOMO * 0.45, mount * 0.9)
    rgb, a = over(rgb, a, JIAOMO, band(d, 0, 2.5))
    gold = gold_color(H, W, 322)
    rgb, a = over(rgb, a, gold, band(d, 7.5, 9.3) * 0.85)
    # 题签：旧绢条（横向按 P 周期取样，九宫横铺无缝）
    ty0, ty1 = SH + side, SH + top - 4
    strip = ((y > ty0) & (y < ty1) & (x > SH + side) & (x < W - SH - side)).astype(np.float32)
    silk = tile_sample(silk_tile(P, 323, lowfreq=0.35), W, H, ML, 0)
    silk = silk * (1 - 0.12 * sstep(0, 1, (y - ty0) / (ty1 - ty0)) ** 2)[..., None]
    rgb, a = over(rgb, a, silk, strip)
    rgb, a = over(rgb, a, gold, band(np.abs(y - (ty1 + 1)), -1, 1.2) * (d > 8))
    rgb, a = over(rgb, a, JIAOMO, band(np.abs(y - (ty1 + 3.2)), -1, 1.0) * (d > 8) * 0.9)
    # 包角金钩（四角）
    ex = np.minimum(x - SH, W - SH - x)
    ey = np.minimum(y - SH, H - SH - y)
    near = (ex < ML - SH - 1) & (ey < ML - SH - 1)
    bracket = band(d, 6.5, 10.5) * near * ((ex < 10.5) | (ey < 10.5))
    rgb, a = over(rgb, a, gold_color(H, W, 324, 1.1), bracket)
    save("window_frame.png", rgb, a)


def button_tex(kind, state, seed):
    """按钮九宫：P=128 横向平铺，左右边 24、上下边 20（贴图像素），高 88（逻辑 44）。
    kind: ink（墨底泥金边）/ seal（朱砂主按钮）。"""
    P, ML, MT, H = 128, 24, 20, 88
    W = 2 * ML + P
    x, y = grid(W, H)
    rough = tile_sample(noise(H, P, 1.0, seed)[..., None], W, H, ML, 0)[..., 0]
    d = rect_dist(W, H, 2, chamfer=9) + (0.35 if kind == "ink" else 0.5) * rough
    body = np.clip(d + 0.5, 0, 1)
    streak = tile_sample(noise(H, P, 1.0, seed + 1, stretch=(8, 1))[..., None], W, H, ML, 0)[..., 0]
    fine = tile_sample(noise(H, P, 0.3, seed + 2)[..., None], W, H, ML, 0)[..., 0]
    t = sstep(0, 1, (y - 2) / (H - 4))[..., None]
    rgb, a = canvas(W, H, JIAOMO)
    if kind == "ink":
        top_c, bot_c, line_a, line_b, alpha = {
            "normal": ((0.125, 0.108, 0.092), (0.060, 0.064, 0.076), 0.80, 0.86, 0.94),
            "hover": ((0.170, 0.142, 0.110), (0.085, 0.082, 0.088), 1.00, 1.12, 0.96),
            "pressed": ((0.045, 0.040, 0.036), (0.040, 0.046, 0.058), 0.62, 0.72, 0.96),
            "disabled": ((0.160, 0.152, 0.142), (0.118, 0.114, 0.110), 0.42, 0.60, 0.70),
        }[state]
        col = lerp(np.array(top_c, np.float32), np.array(bot_c, np.float32), t)
        col = col * (1 + 0.10 * streak[..., None] + 0.03 * fine[..., None])
    else:
        top_c, bot_c, line_a, line_b, alpha = {
            "normal": ((0.690, 0.195, 0.160), (0.560, 0.145, 0.125), 0.55, 1.0, 0.97),
            "hover": ((0.770, 0.245, 0.190), (0.635, 0.180, 0.150), 0.95, 1.1, 0.98),
            "pressed": ((0.540, 0.140, 0.120), (0.470, 0.115, 0.100), 0.40, 0.9, 0.98),
            "disabled": ((0.420, 0.320, 0.300), (0.350, 0.270, 0.255), 0.30, 0.8, 0.72),
        }[state]
        col = lerp(np.array(top_c, np.float32), np.array(bot_c, np.float32), t)
        mott = tile_sample(noise(H, P, 1.4, seed + 3)[..., None], W, H, ML, 0)[..., 0]
        col = col * (1 + 0.06 * mott[..., None] + 0.015 * fine[..., None] + 0.03 * streak[..., None])
        # 印泥未着处：零星透出纸色的小白点
        holes = sstep(2.7, 3.3, fine) * 0.45
        col = lerp(col, XUAN * 0.9, holes[..., None])
    if state == "pressed":
        col = col * (1 - 0.45 * np.exp(-(y - 2) / 9.0))[..., None]
    rgb, a = over(rgb, a, np.clip(col, 0, 1), body * alpha)
    dl = rect_dist(W, H, 2, chamfer=9)
    line = band(dl, 5.6, 7.6)
    if kind == "ink":
        lc = gold_color(H, W, seed + 4, line_b) if state != "disabled" else np.array([0.42, 0.40, 0.36], np.float32)
        if state == "hover":
            glow = 0.22 * np.exp(-np.maximum(dl - 7.6, 0) / 7.0) * (dl > 7.6)
            rgb, a = over(rgb, a, GOLD_HI, glow * body)
        rgb, a = over(rgb, a, lc, line * line_a)
        # 四角各一粒金方胜
        ex = np.minimum(x - 2, W - 2 - x)
        ey = np.minimum(y - 2, H - 2 - y)
        nub = ((np.abs(ex - 13) + np.abs(ey - 13)) < 3.2).astype(np.float32)
        rgb, a = over(rgb, a, lc, nub * line_a)
    else:
        lc = XUAN if state not in ("hover",) else GOLD_HI
        rgb, a = over(rgb, a, lc, line * line_a)
    return rgb, a


@gen("buttons")
def gen_buttons():
    for kind, seed in (("ink", 400), ("seal", 450)):
        for state in ("normal", "hover", "pressed", "disabled"):
            rgb, a = button_tex(kind, state, seed)
            save(f"btn_{kind}_{state}.png", rgb, a)


@gen("focus")
def gen_focus():
    """焦点框：四角泥金角钩（键盘/手柄焦点），中间全透明。九宫边距 20。"""
    M, P = 20, 64
    W = H = 2 * M + P
    x, y = grid(W, H)
    d = rect_dist(W, H, 0)
    ex = np.minimum(x, W - x)
    ey = np.minimum(y, H - y)
    m = band(d, 0, 3.2) * (ex < 17) * (ey < 17)
    rgb, a = canvas(W, H, GOLD_HI)
    rgb, a = over(rgb, a, JIAOMO, np.roll(np.roll(m, 1, 0), 1, 1) * 0.6)
    rgb, a = over(rgb, a, gold_color(H, W, 460, 1.15), m)
    save("focus_frame.png", rgb, a)


@gen("hover_band")
def gen_hover_band():
    """列表 / 菜单悬停条：淡泥金晕 + 左侧金签。九宫 左右 12、上下 12。"""
    M, P = 12, 64
    W, H = 2 * M + P, 2 * M + 24
    x, y = grid(W, H)
    rgb, a = canvas(W, H, NIJIN)
    fill = 0.20 * (1 - 0.35 * sstep(0, W, x)) * (y > 1) * (y < H - 1)
    rgb, a = over(rgb, a, NIJIN, fill)
    rgb, a = over(rgb, a, GOLD_HI, band(np.abs(y - 1.2), -1, 0.9) * 0.35)
    rgb, a = over(rgb, a, GOLD_HI, band(np.abs(y - (H - 1.2)), -1, 0.9) * 0.35)
    rgb, a = over(rgb, a, gold_color(H, W, 470, 1.1), band(x, 1, 5) * (y > 3) * (y < H - 3))
    save("hover_band.png", rgb, a)


@gen("field")
def gen_field():
    """输入框：半透明墨底 + 底部旧绢线 + 两端小竖钩；focus 版底线换亮泥金并起微光。"""
    M, P = 24, 128
    W, H = 2 * M + P, 64
    x, y = grid(W, H)
    streak = tile_sample(noise(H, P, 1.0, 480, stretch=(8, 1))[..., None], W, H, M, 0)[..., 0]
    for name, lc, la, glow in (("field_normal.png", JIUJUAN, 0.75, 0.0), ("field_focus.png", GOLD_HI, 1.0, 0.25)):
        rgb, a = canvas(W, H, JIAOMO)
        d = rect_dist(W, H, 1)
        rgb, a = over(rgb, a, JIAOMO * (1 + 0.6 * streak[..., None]) + 0.02, np.clip(d + 0.5, 0, 1) * 0.58)
        if glow:
            rgb, a = over(rgb, a, NIJIN, glow * np.exp(-np.maximum(H - 5 - y, 0) / 10.0) * (d > 0))
        rgb, a = over(rgb, a, lc, band(y, H - 5, H - 2.6) * (x > 2) * (x < W - 2) * la)
        tick = (band(x, 1, 3.4) + band(W - x, 1, 3.4)) * (y > H - 14) * (y < H - 2.6)
        rgb, a = over(rgb, a, lc, tick * la)
        save(name, rgb, a)


@gen("tabs")
def gen_tabs():
    """页签：选中＝深墨签 + 泥金顶线（与下方深墨面板连成一片）；未选＝半透明墨签；悬停＝略亮。"""
    M, P = 16, 64
    W, H = 2 * M + P, 64
    x, y = grid(W, H)
    for name, fa, ga, gb in (("tab_selected.png", 0.93, 1.0, 1.1), ("tab_unselected.png", 0.55, 0.30, 0.8),
                             ("tab_hover.png", 0.75, 0.70, 1.0)):
        irgb, ia = ink_tile(P, 490, 0.9)
        irgb = tile_sample(irgb, W, H, M, 0)
        dx = np.minimum(x, W - x)
        d = np.minimum(dx, y)
        body = np.clip(np.minimum(d, (dx + y - 8) / math.sqrt(2)) + 0.5, 0, 1)
        rgb, a = canvas(W, H, JIAOMO)
        rgb, a = over(rgb, a, irgb, body * fa)
        gl = band(y, 1.5, 4.5) * (dx > 6) + band(dx, 1, 2.4) * (y > 6) * 0.5
        rgb, a = over(rgb, a, gold_color(H, W, 491, gb), gl * ga)
        save(name, rgb, a)


def divider_tex(kind, seed):
    """横向分隔线：墨线两端收锋（ink）/ 泥金细线两端方胜（gold）。九宫 左右 160、上下 12，中段 P=256。"""
    P, M, H = 256, 160, 24
    W = 2 * M + P
    x, y = grid(W, H)
    nw = tile_sample(noise(H, P, 1.3, seed)[..., None], W, H, M, 0)[..., 0]
    wob = tile_sample(noise(8, P, 1.6, seed + 1)[..., None], W, 8, M, 0)[0, :, 0][None, :]
    streak = tile_sample(noise(H, P, 1.0, seed + 2, stretch=(16, 1))[..., None], W, H, M, 0)[..., 0]
    rgb, a = canvas(W, H, JIAOMO if kind == "ink" else NIJIN)
    if kind == "ink":
        prof = sstep(8, 118, x) ** 0.8 * sstep(8, 150, W - x) ** 0.9
        hw = (2.3 + 0.35 * nw) * prof + 0.25 * (x < 60) * sstep(20, 50, x) * (1 - sstep(50, 90, x))
        dy = np.abs(y - (H / 2 + 0.8 * wob))
        m = band(dy, -hw, hw) * (1 - 0.55 * sstep(0.9, 1.9, streak))
        rgb, a = over(rgb, a, JIAOMO, m * 0.95)
    else:
        prof = sstep(20, 70, x) * sstep(20, 70, W - x)
        dy = np.abs(y - H / 2)
        m = band(dy, -1.25 * prof, 1.25 * prof)
        dia = np.maximum(((np.abs(x - 12) + dy) < 5.5), ((np.abs(W - x - 12) + dy) < 5.5)).astype(np.float32)
        gold = gold_color(H, W, seed + 3, 1.05)
        rgb, a = over(rgb, a, JIAOMO, np.roll(np.maximum(m, dia), 1, 0) * 0.5)
        rgb, a = over(rgb, a, gold, np.maximum(m * 0.95, dia))
    return rgb, a


@gen("dividers")
def gen_dividers():
    for kind, seed in (("ink", 500), ("gold", 510)):
        rgb, a = divider_tex(kind, seed)
        save(f"divider_{kind}.png", rgb, a)
        save(f"vdivider_{kind}.png", np.ascontiguousarray(rgb.transpose(1, 0, 2)), np.ascontiguousarray(a.T))


def huiwen_path(units, u, oy):
    """回纹（带底线的连续回纹），一单元 12 格，u=每格像素。"""
    ps = []
    for i in range(units + 1):
        o = 12 * i
        ps.append(f"M{(o - 0.2) * u},{oy + 11.2 * u} H{(o + 12.2) * u}")
        ps.append(f"M{(o + 1.4) * u},{oy + 11.2 * u} V{oy + 1 * u} H{(o + 11) * u} V{oy + 8.8 * u} "
                  f"H{(o + 4) * u} V{oy + 4 * u} H{(o + 8) * u} V{oy + 6.4 * u}")
    return " ".join(ps)


def cloud_path(units, u, oy):
    """卷云纹：一单元 24 格，首尾相接。"""
    ps = []
    for i in range(units + 1):
        o = 24 * i

        def P(px, py):
            return f"{(o + px) * u},{oy + py * u}"
        ps.append(f"M{P(0, 9)} Q{P(6, 9)} {P(6, 5.5)} Q{P(6, 2.2)} {P(9.2, 2.2)} Q{P(12.4, 2.2)} {P(12.4, 5.5)} "
                  f"Q{P(12.4, 8.2)} {P(9.8, 8.2)} Q{P(8, 8.2)} {P(8, 6.4)} Q{P(8, 4.8)} {P(9.6, 4.8)}")
        ps.append(f"M{P(12.4, 5.5)} Q{P(12.6, 9)} {P(18, 9)} L{P(24.1, 9)}")
    return " ".join(ps)


@gen("bands")
def gen_bands():
    """边饰条（横向可平铺）：回纹金 / 回纹墨 / 云纹金。上下各一道细边线。"""
    for name, path_fn, unit_w, color in (("band_huiwen_gold.png", huiwen_path, 12, "gold"),
                                         ("band_huiwen_ink.png", huiwen_path, 12, "ink"),
                                         ("band_cloud_gold.png", cloud_path, 24, "gold")):
        u = 40 / 12.0
        units = 10 if unit_w == 12 else 5
        W = int(round(unit_w * u * units))
        H = 56
        sw = 1.25 * u if unit_w == 12 else 1.05 * u
        body = (f'<path d="{path_fn(units, u, 8)}" fill="none" stroke="#fff" stroke-width="{sw:.2f}" '
                f'stroke-linecap="butt" stroke-linejoin="miter"/>'
                f'<rect x="0" y="1.6" width="{W}" height="2.4" fill="#fff"/>'
                f'<rect x="0" y="{H - 4}" width="{W}" height="2.4" fill="#fff"/>')
        m = svg_alpha(body, W, H)
        rgb, a = canvas(W, H, JIAOMO)
        if color == "gold":
            rgb, a = over(rgb, a, JIAOMO, np.roll(np.roll(m, 1, 0), 1, 1) * 0.55)
            rgb, a = over(rgb, a, gold_color(H, W, 520 + len(name), 1.0), m)
        else:
            dry = 1 - 0.35 * sstep(1.0, 2.0, noise(H, W, 1.0, 530, stretch=(6, 1)))
            rgb, a = over(rgb, a, JIAOMO, m * dry * 0.95)
        save(name, rgb, a)


@gen("corners")
def gen_corners():
    """独立角花（左上朝向，其余三角由集成者 flip_h / flip_v）：回纹委角 / 如意云头。"""
    S = 160
    g = 6
    hw = (f'<g fill="none" stroke="#fff" stroke-linecap="square" stroke-linejoin="miter">'
          f'<path d="M{S},{g} H40 V40 H{g} V{S}" stroke-width="4"/>'
          f'<path d="M{S},{g + 12} H52 V52 H{g + 12} V{S}" stroke-width="2.2"/>'
          f'<path d="M12,34 V12 H34 V34 H19 V19 H28 V27" stroke-width="3.2"/>'
          f'</g><rect x="58" y="58" width="9" height="9" fill="#fff" transform="rotate(45 62.5 62.5)"/>')
    m = svg_alpha(hw, S, S)
    rgb, a = canvas(S, S, NIJIN)
    rgb, a = over(rgb, a, JIAOMO, np.roll(np.roll(m, 2, 0), 2, 1) * 0.6)
    rgb, a = over(rgb, a, gold_color(S, S, 540, 1.0), m)
    save("corner_huiwen.png", rgb, a)
    ry = ('<g fill="none" stroke="#fff" stroke-linecap="round" stroke-linejoin="round">'
          '<path d="M160,8 H64 C52,8 44,12 40,20" stroke-width="3.4"/>'
          '<path d="M8,160 V64 C8,52 12,44 20,40" stroke-width="3.4"/>'
          '<path d="M40,20 C30,10 12,14 12,30 C12,40 20,44 26,42 C20,48 20,58 30,60 C38,62 44,54 42,46 '
          'C50,48 58,42 58,34 C58,24 46,20 40,26 C44,18 44,14 40,20 Z" stroke-width="3.2"/>'
          '<path d="M30,36 C26,32 30,26 35,29 C39,32 36,38 32,37" stroke-width="2.4"/>'
          '<path d="M160,22 H76 C66,22 60,26 58,34" stroke-width="1.8"/>'
          '<path d="M22,160 V76 C22,66 26,60 34,58" stroke-width="1.8"/></g>')
    m = svg_alpha(ry, S, S)
    rgb, a = canvas(S, S, NIJIN)
    rgb, a = over(rgb, a, JIAOMO, np.roll(np.roll(m, 2, 0), 2, 1) * 0.6)
    rgb, a = over(rgb, a, gold_color(S, S, 541, 1.0), m)
    save("corner_ruyi.png", rgb, a)


@gen("portrait_frame")
def gen_portrait_frame():
    """立绘画框：窗口正好 512×640（=立绘原图，逻辑 256×320），旧绢裱边 + 泥金线 + 内阴影 + 底部名牌。
    整幅 592×800（逻辑 296×400）。窗口 (40,40)-(552,680)；名牌 (96,700)-(496,776)。"""
    W, H = 592, 800
    wx0, wy0, wx1, wy1 = 40, 40, 552, 680
    x, y = grid(W, H)
    d = rect_dist(W, H, 0)
    silk = tile_sample(silk_tile(256, 551, lowfreq=0.4), W, H, 0, 0) * 0.93
    rgb, a = canvas(W, H, JIAOMO)
    rgb, a = over(rgb, a, silk, np.ones((H, W), np.float32))
    # 窗口距离（窗口内为正）
    wdx = np.minimum(x - wx0, wx1 - x)
    wdy = np.minimum(y - wy0, wy1 - y)
    wd = np.minimum(wdx, wdy)
    inwin = np.clip(wd + 0.5, 0, 1)
    # 裱边微暗 + 外边焦墨
    rgb = rgb * (1 - 0.14 * np.exp(-d / 30.0))[..., None]
    n1 = noise(H, W, 1.1, 552)
    rgb, a = over(rgb, a, JIAOMO, band(d, 0, 5.2 + 0.6 * n1))
    gold = gold_color(H, W, 553, 0.85)
    rgb, a = over(rgb, a, gold, band(d, 11, 13))
    # 贴窗：外侧泥金线 + 墨发丝
    rgb, a = over(rgb, a, gold, band(-wd, 5, 7.4))
    rgb, a = over(rgb, a, JIAOMO, band(-wd, 0, 2.6) * 0.9)
    # 窗口：挖空 + 向内的阴影（压在立绘边缘上，立绘显得嵌进去）
    inner_sh = 0.55 * np.exp(-np.maximum(wd, 0) / 9.0) * inwin
    a = a * (1 - inwin)
    rgb, a = over(rgb, a, JIAOMO, inner_sh)
    # 四角回纹（外框金线内侧）
    k = 40
    cm = svg_alpha('<g fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="square">'
                   '<path d="M18,32 V18 H32 V32 H23 V23 H28 V28"/></g>', k, k)
    corners = four_corners(cm, W, H)
    rgb, a = over(rgb, a, gold, corners)
    # 名牌：靛墨匾 + 泥金线 + 两端方胜。四角「委角」＝向内折的方缺角（泥金内线随之折角），
    # 不用小圆角 / 小斜角——缩到 0.6 倍时那两种都会看成圆角
    px0, py0, px1, py1 = 96, 700, 496, 776
    pdx = np.minimum(x - px0, px1 - x)
    pdy = np.minimum(y - py0, py1 - y)
    notch = 14
    pd = np.minimum(np.minimum(pdx, pdy), np.maximum(pdx - notch, pdy - notch))
    irgb, ia = ink_tile(256, 554, 0.95)
    irgb = tile_sample(irgb, W, H, 0, 0)
    rgb, a = over(rgb, a, JIAOMO, 0.45 * np.exp(-np.maximum(-pd, 0) / 5.0) * (pd < 0))
    rgb, a = over(rgb, a, irgb, np.clip(pd + 0.5, 0, 1) * 0.96)
    rgb, a = over(rgb, a, gold_color(H, W, 555, 1.05), band(pd, 4.5, 6.7))
    cy = (py0 + py1) / 2
    for cx in (px0 - 14, px1 + 14):
        dia = ((np.abs(x - cx) + np.abs(y - cy)) < 7).astype(np.float32)
        rgb, a = over(rgb, a, gold_color(H, W, 556, 1.05), dia)
    save("portrait_frame.png", rgb, a)


def bar_tex(W, H, ML, MT, kind, seed):
    x, y = grid(W, H)
    P = W - 2 * ML
    rgb, a = canvas(W, H, JIAOMO)
    streak = tile_sample(noise(H, P, 1.0, seed, stretch=(10, 1))[..., None], W, H, ML, 0)[..., 0]
    if kind == "bg":
        d = rect_dist(W, H, 1)
        rgb, a = over(rgb, a, JIAOMO * (1 + 0.5 * streak[..., None]), np.clip(d + 0.5, 0, 1) * 0.74)
        rgb, a = over(rgb, a, JIAOMO, 0.5 * np.exp(-np.maximum(y - 1, 0) / 3.0) * (d > 0))
        rgb, a = over(rgb, a, gold_color(H, W, seed + 1, 0.9), band(d, 0, 1.6) * 0.6)
        return rgb, a
    col = {"gold": (GOLD_HI, GOLD_LO), "teal": (hexc("#6fa3ad"), hexc("#274f5a")),
           "red": (hexc("#d9573f"), hexc("#8e2420"))}[kind]
    ins = 3.0
    t = sstep(ins, H - ins, y)[..., None]
    c = lerp(col[0], col[1], t) * (1 + 0.10 * streak[..., None])
    tip = sstep(W - ins, W - ML + 1, x + 2.5 * streak)       # 右端干笔收尾
    m = band(np.minimum(y - ins, H - ins - y), 0, 99) * sstep(ins - 0.5, ins + 1.5, x) * tip
    m = m * (1 - 0.35 * sstep(1.2, 2.2, streak))
    rgb, a = over(rgb, a, np.clip(c, 0, 1), m)
    rgb, a = over(rgb, a, np.array([1, 0.97, 0.88], np.float32), band(np.abs(y - (ins + 1.2)), -1, 0.7) * m * 0.35)
    return rgb, a


@gen("bars")
def gen_bars():
    """进度条 / 属性条：墨槽 + 泥金发丝框；填充为刷笔质感，右端干笔收尾（任意长度都落在右边距里）。"""
    for prefix, W, H, ML, MT in (("bar", 152, 28, 12, 12), ("attr", 148, 20, 10, 8)):
        for kind in ("bg", "gold", "teal", "red"):
            if prefix == "attr" and kind in ("teal", "red"):
                continue
            rgb, a = bar_tex(W, H, ML, MT, kind, 600 + W + len(kind))
            name = f"{prefix}_{kind}.png" if kind == "bg" else f"{prefix}_fill_{kind}.png"
            save(name, rgb, a)


@gen("scroll")
def gen_scroll():
    """滚动条：竖向 24 宽（逻辑 12）。槽＝一道淡旧绢细线；滑块＝两头出锋的笔杆。横向版为转置。"""
    M, P = 16, 64
    W, H = 24, 2 * M + P
    x, y = grid(W, H)
    cx = W / 2
    ey = np.minimum(y, H - y)
    out = {}
    rgb, a = canvas(W, H, JIUJUAN)
    rgb, a = over(rgb, a, JIUJUAN, band(np.abs(x - cx), -1.3, 1.3) * sstep(2, 14, ey) * 0.32)
    out["scroll_track"] = (rgb, a)
    streak = tile_sample(noise(P, W, 1.0, 620, stretch=(1, 10))[..., None], W, H, 0, M)[..., 0]
    for name, col, al in (("scroll_grabber", JIUJUAN, 0.78), ("scroll_grabber_hl", GOLD_HI, 0.95),
                          ("scroll_grabber_pressed", NIJIN * 0.8, 1.0)):
        hw = 3.8 * sstep(0, 13, ey) ** 0.7
        m = band(np.abs(x - cx), -hw, hw) * (1 - 0.3 * sstep(1.0, 2.0, streak))
        rgb, a = canvas(W, H, col)
        rgb, a = over(rgb, a, JIAOMO, np.roll(m, 1, 1) * 0.5)
        rgb, a = over(rgb, a, np.asarray(col, np.float32) * (1 + 0.08 * streak[..., None]), m * al)
        out[name] = (rgb, a)
    for name, (rgb, a) in out.items():
        save(f"{name}_v.png", rgb, a)
        save(f"{name}_h.png", np.ascontiguousarray(rgb.transpose(1, 0, 2)), np.ascontiguousarray(a.T))


ICONS = {
    # 关闭钮不在此：改为栅格朱印（close_seal），与整套印章同一崩边 / 印泥质感
    "icon_check_off": (20, '<rect x="2.5" y="2.5" width="15" height="15" fill="#0d0b09" fill-opacity="0.45" stroke="#cdb88f" stroke-width="1.4"/>'),
    "icon_check_on": (20, '<rect x="2.5" y="2.5" width="15" height="15" fill="#0d0b09" fill-opacity="0.45" stroke="#c9a14a" stroke-width="1.4"/>'
                          '<rect x="5" y="5" width="10" height="10" fill="#b0302a"/>'
                          '<path d="M6.8,10.2 L9.2,12.6 L13.6,7.2" stroke="#f0e4c8" stroke-width="1.7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
    "icon_radio_off": (20, '<circle cx="10" cy="10" r="7.4" fill="#0d0b09" fill-opacity="0.45" stroke="#cdb88f" stroke-width="1.4"/>'),
    "icon_radio_on": (20, '<circle cx="10" cy="10" r="7.4" fill="#0d0b09" fill-opacity="0.45" stroke="#c9a14a" stroke-width="1.4"/>'
                          '<circle cx="10" cy="10" r="4.2" fill="#b0302a"/>'),
    "icon_arrow_down": (16, '<path d="M3.2,5.6 C6,8.4 7,9.6 8,11 C9,9.6 10.4,8 12.8,5.4" stroke="#cdb88f" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
    "icon_arrow_right": (16, '<path d="M5.6,3.2 C8.4,6 9.6,7 11,8 C9.6,9 8,10.4 5.4,12.8" stroke="#cdb88f" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
}


@gen("icons")
def gen_icons():
    """小图标：SVG 原稿（build_theme.gd 读成 DPITexture，随缩放重新栅格化）+ 2× PNG。
    关闭钮是程序生成的矢量朱印（close_seal_svg）：崩边外廓、印泥斑驳、刻两刀、漏印白点，与整套印章同法。
    （不用 2× 栅格 + PortableCompressedTexture2D：size_override 只对 StyleBoxTexture 生效，
    Window 画关闭钮按 get_size() 取原始像素，会画成 44 逻辑像素。）"""
    d = OUT / "icons"
    d.mkdir(parents=True, exist_ok=True)
    icons = dict(ICONS)
    icons["icon_close_seal"] = (22, close_seal_svg(980, "#b0302a", "#8e2420", "#c9493b"))
    icons["icon_close_seal_pressed"] = (22, close_seal_svg(980, "#7e211d", "#63190f", "#94302a"))
    for name, (sz, body) in icons.items():
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{sz}" height="{sz}" viewBox="0 0 {sz} {sz}">'
               f'{body}</svg>\n')
        (d / f"{name}.svg").write_text(svg, encoding="utf-8")
        rgba = svg_rgba(body, sz * 2, sz * 2, f"0 0 {sz} {sz}")
        save(f"icons/{name}@2x.png", rgba[..., :3], rgba[..., 3])


def close_seal_svg(seed, fill, dark, light):
    """关闭钮（逻辑 22×22）：白文小朱印，刻「乂」两刀——撇右上起刀重、左下收轻，捺左上轻、右下重。
    外廓逐边抖动 + 几处崩口；印面叠几团深浅印泥；刀口与漏印点填宣纸色（像纸从印泥里透出来）。"""
    rng = np.random.default_rng(seed)
    x0, y0, x1, y1 = 1.7, 1.7, 20.3, 20.3

    def edge(ax, ay, bx, by, n=11):
        pts = []
        chips = set(rng.choice(np.arange(2, n - 1), size=int(rng.integers(1, 3)), replace=False).tolist())
        for i in range(n):
            t = i / n
            px, py = ax + (bx - ax) * t, ay + (by - ay) * t
            nx_, ny_ = (by - ay), -(bx - ax)
            ln = math.hypot(nx_, ny_)
            nx_, ny_ = nx_ / ln, ny_ / ln
            j = rng.normal(0, 0.16)
            if i in chips:
                j -= rng.uniform(0.55, 1.0)          # 崩口：向内咬一口
            pts.append((px + nx_ * j, py + ny_ * j))
        return pts
    outline = (edge(x0, y0, x1, y0) + edge(x1, y0, x1, y1) + edge(x1, y1, x0, y1) + edge(x0, y1, x0, y0))
    path = "M" + " L".join(f"{px:.2f},{py:.2f}" for px, py in outline) + " Z"
    parts = [f'<defs><clipPath id="s"><path d="{path}"/></clipPath></defs>', f'<path d="{path}" fill="{fill}"/>',
             '<g clip-path="url(#s)">']
    for _ in range(7):                                  # 印泥深浅团块
        cx, cy = rng.uniform(3, 19, 2)
        parts.append(f'<ellipse cx="{cx:.2f}" cy="{cy:.2f}" rx="{rng.uniform(2, 5):.2f}" ry="{rng.uniform(1.5, 4):.2f}" '
                     f'fill="{dark if rng.uniform() < 0.55 else light}" fill-opacity="{rng.uniform(0.18, 0.32):.2f}" '
                     f'transform="rotate({rng.uniform(0, 180):.0f} {cx:.2f} {cy:.2f})"/>')
    parts.append('</g>')

    def knife(p0, p1, w0, w1):
        (ax, ay), (bx, by) = p0, p1
        ln = math.hypot(bx - ax, by - ay)
        ux, uy = (bx - ax) / ln, (by - ay) / ln
        nx_, ny_ = -uy, ux
        side_a, side_b = [], []
        for i in range(7):
            t = i / 6
            w = (w0 + (w1 - w0) * t) * (0.62 + 0.38 * math.sin(math.pi * t) ** 0.3) / 2
            cx, cy = ax + ux * ln * t, ay + uy * ln * t
            side_a.append((cx + nx_ * (w + rng.normal(0, 0.05)), cy + ny_ * (w + rng.normal(0, 0.05))))
            side_b.append((cx - nx_ * (w + rng.normal(0, 0.05)), cy - ny_ * (w + rng.normal(0, 0.05))))
        pts = side_a + side_b[::-1]
        return "M" + " L".join(f"{px:.2f},{py:.2f}" for px, py in pts) + " Z"
    paper = "#ecdfc4"
    parts.append(f'<path d="{knife((15.2, 6.0), (6.6, 15.9), 2.6, 1.5)}" fill="{paper}"/>')     # 撇
    parts.append(f'<path d="{knife((6.8, 6.4), (15.5, 15.7), 1.5, 2.8)}" fill="{paper}"/>')     # 捺
    for _ in range(5):                                  # 漏印白点
        cx, cy = rng.uniform(3, 19, 2)
        parts.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{rng.uniform(0.18, 0.4):.2f}" fill="{paper}" '
                     f'fill-opacity="{rng.uniform(0.6, 0.95):.2f}"/>')
    return "".join(parts)


def glyph_mask(ch, size, font=MASHAN):
    """单字墨迹遮罩（紧包围盒）。"""
    ft = ImageFont.truetype(font, size)
    im = Image.new("L", (int(size * 1.7), int(size * 1.7)), 0)
    ImageDraw.Draw(im).text((size * 0.35, size * 0.35), ch, font=ft, fill=255)
    return np.asarray(im.crop(im.getbbox()), np.float32) / 255.0


def paste_max(dst, src, x0, y0):
    h, w = src.shape
    H, W = dst.shape
    xa, ya = max(0, x0), max(0, y0)
    xb, yb = min(W, x0 + w), min(H, y0 + h)
    if xb <= xa or yb <= ya:
        return
    dst[ya:yb, xa:xb] = np.maximum(dst[ya:yb, xa:xb], src[ya - y0:yb - y0, xa - x0:xb - x0])


def resize_f(a, w, h):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((max(1, int(w)), max(1, int(h))),
                                                                                        Image.LANCZOS), np.float32) / 255.0


def dilate(m, r):
    """近似圆形膨胀（高斯 + 阈值）。"""
    return sstep(0.08, 0.30, blur(m, r * 0.75))


def seal_tex(chars, kind, W, H, seed):
    """朱印。kind: zhu（朱文，字与边框着朱）/ bai（白文，印面着朱、字挖白）/ blank（空白印底）。
    字序按传统右起竖读：四字＝右列上下、左列上下；两字＝一列上下。"""
    ss = 3
    Wb, Hb = W * ss, H * ss
    rng = np.random.default_rng(seed)
    x, y = grid(Wb, Hb)
    rough = noise(Hb, Wb, 1.0, seed, hi=0.05)
    d = rect_dist(Wb, Hb, 2.5 * ss, chamfer=3.0 * ss) + 1.1 * ss * rough
    block = sstep(-0.6 * ss, 0.6 * ss, d)
    text = np.zeros((Hb, Wb), np.float32)
    if chars:
        mm = (0.13 if kind == "zhu" else 0.105) * min(Wb, Hb)
        n = len(chars)
        cols, rows = (2, 2) if n == 4 else (1, n)
        gap = 0.035 * min(Wb, Hb)
        cw = (Wb - 2 * mm - gap * (cols - 1)) / cols
        ch = (Hb - 2 * mm - gap * (rows - 1)) / rows
        for i, c in enumerate(chars):
            col = cols - 1 - i // rows
            row = i % rows
            g = glyph_mask(c, int(ch * 1.4))
            g = resize_f(g, cw * 0.96, ch * 0.96)
            g = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(
                __import__("PIL.ImageFilter", fromlist=["MaxFilter"]).MaxFilter(3 if kind == "zhu" else 5)), np.float32) / 255
            gx = int(mm + col * (cw + gap) + (cw - g.shape[1]) / 2 + rng.normal(0, 0.6 * ss))
            gy = int(mm + row * (ch + gap) + (ch - g.shape[0]) / 2 + rng.normal(0, 0.6 * ss))
            paste_max(text, g, gx, gy)
        text = sstep(0.35, 0.65, blur(text, 0.8 * ss) + 0.12 * noise(Hb, Wb, 0.8, seed + 1, hi=0.08))
    if kind == "zhu":
        fw = 0.055 * min(Wb, Hb)
        alpha = np.maximum(band(d, 0, fw + 0.8 * ss * noise(Hb, Wb, 1.2, seed + 2)), text) * block
    elif kind == "bai":
        alpha = block * (1 - text)
    else:
        alpha = block
    # 崩口：沿外缘随机咬掉几口
    for _ in range(int(rng.integers(5, 10))):
        side = rng.integers(4)
        t = rng.uniform(0.08, 0.92)
        px_, py_ = [(t * Wb, 2.5 * ss), (Wb - 2.5 * ss, t * Hb), (t * Wb, Hb - 2.5 * ss), (2.5 * ss, t * Hb)][side]
        r = rng.uniform(1.2, 4.5) * ss
        alpha = alpha * sstep(r * 0.7, r * 1.2, np.hypot(x - px_, y - py_))
    # 印泥不匀：团块 + 颗粒 + 漏印小点 + 一侧按压略轻
    clump = noise(Hb, Wb, 1.3, seed + 3)
    grain = noise(Hb, Wb, 0.35, seed + 4)
    alpha = alpha * np.clip(0.91 + 0.07 * clump + 0.06 * grain, 0, 1)
    alpha = alpha * (1 - 0.85 * sstep(2.1, 2.7, noise(Hb, Wb, 0.5, seed + 5)))
    press = lerp(0.86, 1.0, sstep(-0.2, 1.2, (x / Wb) * 0.6 + (y / Hb) * 0.4 + 0.15 * noise(Hb, Wb, 1.8, seed + 6)))
    alpha = alpha * press
    col = ZHUSHA[None, None, :] * (0.93 + 0.08 * clump[..., None]) * (1.04 - 0.08 * alpha[..., None])
    arr = np.dstack([np.clip(col, 0, 1), np.clip(alpha, 0, 1)[..., None]])
    img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA").resize((W, H), Image.LANCZOS)
    a = np.asarray(img, np.float32) / 255.0
    return a[..., :3], a[..., 3]


SEALS = [("lizhi", "立志"), ("haishang", "海商"), ("daihui", "待绘"), ("dongya", "东亚海域"), ("xinghua", "兴化陈氏")]


@gen("seals")
def gen_seals():
    for i, (key, chars) in enumerate(SEALS):
        W, H = (256, 256) if len(chars) == 4 else (168, 280)
        for kind in ("zhu", "bai"):
            rgb, a = seal_tex(chars, kind, W, H, 700 + i * 10 + (kind == "bai"))
            save(f"seal_{key}_{kind}.png", rgb, a)
    rgb, a = seal_tex("", "blank", 256, 256, 790)
    save("seal_blank.png", rgb, a)


def lic(tex, vx, vy, steps=14, h=1.0):
    """线积分卷积：沿笔势方向场抹开噪声 → 顺笔锋的丝缕（飞白 / 笔触纹理）。
    方向场只定到 ±π（结构张量），积分时逐步与上一步同向，避免来回折返。"""
    H, W = tex.shape
    acc = tex.copy()
    cnt = 1.0
    X0 = np.tile(np.arange(W, dtype=np.float32), (H, 1))
    Y0 = np.tile(np.arange(H, dtype=np.float32)[:, None], (1, W))
    for sgn in (1.0, -1.0):
        X, Y = X0.copy(), Y0.copy()
        pvx, pvy = sgn * vx, sgn * vy
        for _ in range(steps):
            xi = np.clip(X.round().astype(np.int32), 0, W - 1)
            yi = np.clip(Y.round().astype(np.int32), 0, H - 1)
            ux, uy = vx[yi, xi], vy[yi, xi]
            flip = (ux * pvx + uy * pvy) < 0
            ux = np.where(flip, -ux, ux)
            uy = np.where(flip, -uy, uy)
            X = X + ux * h
            Y = Y + uy * h
            pvx, pvy = ux, uy
            xi = np.clip(X.round().astype(np.int32), 0, W - 1)
            yi = np.clip(Y.round().astype(np.int32), 0, H - 1)
            acc += tex[yi, xi]
            cnt += 1
    return acc / cnt


def calligraphy(mask, seed, gold_body=False):
    """书法字迹质感：墨边洇化 + 顺笔势飞白（只落在笔势一致的长笔画上）+ 泥金描边 + 柔影。返回 (rgb, a)。"""
    H, W = mask.shape
    nr = noise(H, W, 0.9, seed, hi=0.22)
    Mr = sstep(0.40, 0.60, blur(mask, 1.4) + 0.10 * nr)
    gy, gx = np.gradient(blur(Mr, 2.5))
    jxx, jyy, jxy = blur(gx * gx, 7), blur(gy * gy, 7), blur(gx * gy, 7)
    theta = 0.5 * np.arctan2(2 * jxy, jxx - jyy)
    vx, vy = (-np.sin(theta)).astype(np.float32), np.cos(theta).astype(np.float32)
    coh = ((jxx - jyy) ** 2 + 4 * jxy ** 2) / ((jxx + jyy) ** 2 + 1e-12)
    rng = np.random.default_rng(seed + 1)
    white = blur(rng.standard_normal((H, W)).astype(np.float32), 0.7)
    L = lic(white, vx, vy, 18, 1.0)
    L = (L - L.mean()) / (L.std() + 1e-9)
    gate = sstep(0.1, 1.1, noise(H, W, 1.7, seed + 2)) * sstep(0.45, 0.8, coh)
    fb = sstep(0.85, 1.6, L) * gate                       # 飞白
    tone = L * 0.5
    dil = dilate(Mr, 5.5)
    outline = dilate(Mr, 8.5)
    sh = blur(dilate(Mr, 9), 16) * 0.6
    rgb, a = canvas(W, H, JIAOMO)
    rgb, a = over(rgb, a, JIAOMO, sh)
    yy = (np.arange(H, dtype=np.float32) / H)[:, None, None]
    gold = lerp(GOLD_HI, GOLD_LO, np.broadcast_to(yy, (H, W, 1)) * 0.9) * (1 + 0.05 * noise(H, W, 0.3, seed + 3)[..., None])
    spark = sstep(2.3, 3.0, noise(H, W, 0.2, seed + 4))[..., None]
    gold = np.clip(lerp(gold, np.array([1, 0.96, 0.82], np.float32), 0.6 * spark), 0, 1)
    if not gold_body:
        rgb, a = over(rgb, a, gold, dil)
        ink_rgb = JIAOMO[None, None, :] * (1 + 0.25 * np.clip(tone, -1, 2)[..., None]) + 0.01
        rgb, a = over(rgb, a, np.clip(ink_rgb, 0, 1), Mr * (1 - 0.70 * fb))
    else:
        rgb, a = over(rgb, a, JIAOMO, outline)
        rgb, a = over(rgb, a, gold * 0.55, dil)
        body = gold * (1 + 0.08 * np.clip(tone, -2, 2)[..., None])
        body = lerp(body, gold * 0.42, 0.8 * fb[..., None])
        rgb, a = over(rgb, a, np.clip(body, 0, 1), Mr)
    return rgb, a


def logo_layout(text, vertical, em):
    sizes = [1.0, 0.9, 1.1, 0.98, 0.9, 1.05, 0.98]
    offs = [0.00, 0.03, -0.03, 0.02, 0.04, -0.02, 0.01]
    rots = [-1.5, 1.2, -2.0, 0.8, 1.6, -1.0, 1.8]
    glyphs = []
    for i, ch in enumerate(text):
        g = glyph_mask(ch, int(em * sizes[i]))
        im = Image.fromarray((g * 255).astype(np.uint8)).rotate(rots[i], resample=Image.BICUBIC, expand=True)
        glyphs.append(np.asarray(im, np.float32) / 255.0)
    pad = 110
    gap = -0.03 * em
    if not vertical:
        W = int(sum(g.shape[1] for g in glyphs) + gap * (len(glyphs) - 1) + 2 * pad + 0.5 * em)
        H = int(max(g.shape[0] for g in glyphs) + 2 * pad + 0.12 * em)
    else:
        W = int(max(g.shape[1] for g in glyphs) + 2 * pad + 0.12 * em + 0.5 * em)
        H = int(sum(g.shape[0] for g in glyphs) + gap * (len(glyphs) - 1) + 2 * pad)
    M = np.zeros((H, W), np.float32)
    cur = pad
    for i, g in enumerate(glyphs):
        if not vertical:
            yc = H / 2 + offs[i] * em
            paste_max(M, g, int(cur), int(yc - g.shape[0] / 2))
            cur += g.shape[1] + gap
        else:
            xc = (W - 0.5 * em) / 2 + offs[i] * em
            paste_max(M, g, int(xc - g.shape[1] / 2), int(cur))
            cur += g.shape[0] + gap
    return M, cur


@gen("logo")
def gen_logo():
    """标题书法 logo「东亚海域立志传」：横版宽约 2400、竖版高约 2600；墨字泥金描边（默认）/ 泥金字墨描边（_gold）。
    末尾钤一方「立志」朱文小印。透明底，自带柔影。"""
    seal_rgb, seal_a = seal_tex("立志", "bai", 132, 220, 795)
    for vertical in (False, True):
        M, end = logo_layout("东亚海域立志传", vertical, 380)
        H, W = M.shape
        for gold_body in (False, True):
            rgb, a = calligraphy(M, 800 + vertical * 10, gold_body)
            if not vertical:
                sx, sy = int(end + 0.06 * 380), int(H / 2 - 0.05 * 380)
            else:
                sx, sy = int(W - 0.5 * 380 - 40), int(end - 330)
            s_rgb = np.zeros((H, W, 3), np.float32)
            s_a = np.zeros((H, W), np.float32)
            sh_, sw_ = seal_a.shape
            s_rgb[sy:sy + sh_, sx:sx + sw_] = seal_rgb
            s_a[sy:sy + sh_, sx:sx + sw_] = seal_a
            rgb, a = over(rgb, a, s_rgb, s_a * 0.96)
            # 裁掉四周全透明
            ys, xs = np.where(a > 0.004)
            y0, y1, x0, x1 = max(0, ys.min() - 4), min(H, ys.max() + 5), max(0, xs.min() - 4), min(W, xs.max() + 5)
            name = f"logo_title_{'v' if vertical else 'h'}{'_gold' if gold_body else ''}.png"
            save(name, rgb[y0:y1, x0:x1], a[y0:y1, x0:x1])


def splat_paths(W, H, pts_x, pts_y, w):
    idx_all, w_all = [], []
    x0 = np.floor(pts_x).astype(np.int64)
    y0 = np.floor(pts_y).astype(np.int64)
    fx = pts_x - x0
    fy = pts_y - y0
    for dx, dy, ww in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        xi, yi = x0 + dx, y0 + dy
        m = (xi >= 0) & (xi < W) & (yi >= 0) & (yi < H)
        idx_all.append((yi[m] * W + xi[m]))
        w_all.append((w * ww)[m])
    return np.bincount(np.concatenate(idx_all), np.concatenate(w_all), minlength=W * H).reshape(H, W).astype(np.float32)


def bristle_stroke(W, H, path, hw_fn, seed, n=170, dry=0.85, dry_start=0.5, load=1.0, step=0.55, spread=1.0,
                   head=0.0, tail=0.0, fray=0.0, clumps=0, fade=0.18, wet_fill=0.0, edge_wob=0.0):
    """鬃毛笔触：n 根鬃毛沿中心线各走一条，按余墨量显隐 → 自然的飞白、分叉与收锋。返回墨量密度。

    head  起笔圆头长度（占笔长）：外侧鬃毛按半圆晚落笔，笔头圆钝，不再是一条垂直切线。
    tail  收笔抖动（占笔长）：每根鬃毛的终点在 [1-tail, 1] 内随机、外侧更早收；
          终点前 fade（占该鬃毛行程）一段余墨与压力降到 0 → 收锋参差、渐干渐淡，不会齐刷刷切断。
    fray  收笔时鬃毛向两侧散开（占半宽）；clumps>0 时鬃毛分成若干束，束内同进退 → 开叉、成缕的飞白。
    wet_fill  湿墨洇开填缝：按余墨量把鬃毛间的细缝洇满（湿段实心、干段才露飞白），免得实心段拉出一条条直划痕。
    """
    rng = np.random.default_rng(seed)
    path = np.asarray(path, np.float64)
    seg = np.hypot(*np.diff(path, axis=0).T)
    s = np.concatenate([[0], np.cumsum(seg)])
    N = max(8, int(s[-1] / step))
    ss_ = np.linspace(0, s[-1], N)
    px = np.interp(ss_, s, path[:, 0])
    py = np.interp(ss_, s, path[:, 1])
    t = ss_ / s[-1]
    tx, ty = np.gradient(px), np.gradient(py)
    nn = np.hypot(tx, ty) + 1e-9
    nx, ny = -ty / nn, tx / nn
    hw = hw_fn(t)
    if edge_wob > 0:
        # 笔锋按压起伏：宽度与中线各有一条缓慢起伏，上下两边不再像尺子画的
        hw = hw * (1 + edge_wob * smooth1d(N, rng, 300))
        mid = 0.5 * edge_wob * smooth1d(N, rng, 450)
    else:
        mid = 0.0
    # 束：每束一条横向漂移曲线 + 一条干湿曲线
    k = max(1, clumps)
    c_drift = [smooth1d(N, rng, 160) for _ in range(k)]
    c_dry = [smooth1d(N, rng, 90) for _ in range(k)]
    c_end = rng.uniform(0, 1, k) ** 0.8
    xs, ys, ws, wets = [], [], [], []
    for _ in range(n):
        off = rng.uniform(-1, 1) * spread
        e = min(1.0, abs(off))
        ci = int(rng.integers(k)) if clumps else 0
        ld = load * rng.uniform(0.7, 1.0) * (1 - 0.3 * e)
        ds = dry_start + rng.normal(0, 0.14) - 0.25 * e
        remain = ld * (1 - dry * sstep(ds, ds + 0.45, t))
        t0 = 0.0
        if head > 0:
            t0 = head * (1 - math.sqrt(max(0.0, 1 - e * e))) + abs(rng.normal(0, 0.06 * head))
            remain = remain * sstep(t0, t0 + 0.004, t)
        t1 = 1.0
        if tail > 0:
            # 同束鬃毛终点相近（束内抖动小），外侧早收
            ce = c_end[ci] if clumps else rng.uniform(0, 1) ** 0.8
            t1 = 1 - tail * np.clip(0.75 * ce + 0.25 * rng.uniform(0, 1), 0, 1) - 0.35 * tail * e * e
            fl = max(0.02, fade * (t1 - t0))
            remain = remain * sstep(t1, t1 - fl, t)
        wet = 0.22 * smooth1d(N, rng, 25)
        if clumps:
            wet = wet + 0.16 * c_dry[ci] * sstep(ds - 0.1, ds + 0.3, t)
        vis = sstep(0.16, 0.36, remain + wet) * ((t >= t0) & (t <= t1))
        wob = 0.03 * smooth1d(N, rng, 220)
        o = off + wob + mid
        if fray > 0 and tail > 0:
            ft = sstep(t1 - 1.6 * tail, t1, t)
            o = o * (1 + fray * ft) + (0.35 * fray * c_drift[ci] * ft if clumps else 0)
        xs.append(px + nx * o * hw)
        ys.append(py + ny * o * hw)
        ws.append(vis * 0.55)
        if wet_fill > 0:
            wets.append(vis * 0.55 * np.clip((remain - 0.45) / 0.5, 0, 1))
    X, Y = np.concatenate(xs), np.concatenate(ys)
    dens = splat_paths(W, H, X, Y, np.concatenate(ws))
    if wet_fill > 0:
        dens = dens + wet_fill * blur(splat_paths(W, H, X, Y, np.concatenate(wets)), 3.5)
    return dens


def ink_finish(dens, seed, k=5.0, grain=0.10, tooth=0.0):
    """墨量密度 → alpha。tooth>0：干笔处（密度低）被纸面纹理咬断，孤立的鬃毛线成断续的灰丝而非实黑线。"""
    H, W = dens.shape
    db = blur(dens, 1.2)
    a = 1 - np.exp(-k * db)
    pap = noise(H, W, 0.5, seed)
    a = a * (1 - grain * sstep(0.3, 2.0, pap))
    if tooth > 0:
        tp = noise(H, W, 0.35, seed + 7)
        a = a * (1 - tooth * sstep(-0.5, 0.8, tp) * (1 - sstep(0.30, 1.10, db)))
    edge = np.clip(a - blur(a, 3.0), 0, 1)
    return np.clip(a + 0.4 * edge, 0, 1)


def blob(W, H, cx, cy, R, seed, rough=0.22, soft=2.0):
    """噪声扰动的墨团（边缘有洇化毛边）。"""
    x, y = grid(W, H)
    ang = np.arctan2(y - cy, x - cx)
    r = np.hypot(x - cx, y - cy)
    rng = np.random.default_rng(seed)
    wob = np.zeros_like(r)
    for k in (3, 5, 8, 13, 21):
        wob += rng.uniform(0.3, 1.0) / k ** 0.6 * np.cos(k * ang + rng.uniform(0, 6.3))
    wob = wob / 2.2
    fine = noise(H, W, 0.9, seed + 1, hi=0.1)
    edge = R * (1 + rough * wob) + 0.05 * R * fine
    return sstep(soft, -soft, r - edge)


def save_ink(name, a, seed):
    H, W = a.shape
    t = noise(H, W, 1.4, seed)
    rgb = np.broadcast_to(JIAOMO, (H, W, 3)) * (1 + 0.25 * t[..., None] * (1 - a[..., None]))
    ys, xs = np.where(a > 0.004)
    y0, y1, x0, x1 = max(0, ys.min() - 4), min(H, ys.max() + 5), max(0, xs.min() - 4), min(W, xs.max() + 5)
    save(name, np.clip(rgb, 0, 1)[y0:y1, x0:x1], a[y0:y1, x0:x1])
    return x0, y0


def head_pool(W, H, path, hw0, seed, along=1.1, across=1.04, back=0.92, rough=0.10, rot=0.0):
    """起笔顿笔处的积墨：沿笔向的椭圆墨团（毛边），以「密度」返回，与鬃毛密度相加后统一走 ink_finish，
    笔头与笔身之间不再有并集接缝。back＝墨团中心离起点的距离（占 hw0）；rot＝椭圆长轴相对笔向的偏角（度），
    模拟逆锋斜切入纸，笔头成斜圆而不是胶囊头。"""
    p = np.asarray(path, np.float64)
    d0 = p[min(len(p) - 1, 3)] - p[0]
    ux, uy = d0 / (np.hypot(*d0) + 1e-9)
    cx, cy = p[0, 0] + ux * back * hw0, p[0, 1] + uy * back * hw0
    if rot:
        ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        ux, uy = ux * ca - uy * sa, ux * sa + uy * ca
    x, y = grid(W, H)
    u = ((x - cx) * ux + (y - cy) * uy) / (along * hw0)
    v = (-(x - cx) * uy + (y - cy) * ux) / (across * hw0)
    r = np.hypot(u, v)
    ang = np.arctan2(v, u)
    rng = np.random.default_rng(seed)
    wob = np.zeros_like(r)
    for kk in (3, 5, 8, 13, 21, 34):
        wob += rng.uniform(0.3, 1.0) / kk ** 0.7 * np.cos(kk * ang + rng.uniform(0, 6.3))
    fine = noise(H, W, 0.9, seed + 1, hi=0.1)
    edge = 1 + rough * wob / 1.8 + 0.025 * fine
    core = sstep(0.02, -0.02, r - edge)
    # 洇边：贴着墨团外缘一圈纤维状毛刺（高频噪声阈值），不是高斯糊边
    fib = noise(H, W, 0.4, seed + 2)
    rim = sstep(0.07, 0.0, r - edge) * (r > edge - 0.01)
    bleed = rim * sstep(0.5, 1.3, fib + 1.2 * (1 - (r - edge) / 0.07))
    return blur(core, 1.0) * 1.6 + blur(bleed, 0.8) * 0.45


def plate_zone(a, thr=0.75, need=0.62):
    """墨刷底的「可写字实心段」：逐列统计 alpha≥thr 的最长连续段，取占该列墨高 ≥need 的列 → 打印像素 / 逻辑坐标。"""
    H, W = a.shape
    good = a >= thr
    cols = []
    for xcol in range(0, W, 4):
        g = good[:, xcol]
        if not g.any():
            continue
        best, run, y0b, y0 = 0, 0, 0, 0
        for yy, v in enumerate(g):
            if v:
                if run == 0:
                    y0 = yy
                run += 1
                if run > best:
                    best, y0b = run, y0
            else:
                run = 0
        ink = np.where(a[:, xcol] > 0.05)[0]
        if len(ink) and best >= need * (ink[-1] - ink[0] + 1):
            cols.append((xcol, y0b, y0b + best))
    if not cols:
        return None
    x0, x1 = cols[0][0], cols[-1][0]
    ya = max(c[1] for c in cols if x0 + (x1 - x0) * 0.15 <= c[0] <= x1 - (x1 - x0) * 0.15)
    yb = min(c[2] for c in cols if x0 + (x1 - x0) * 0.15 <= c[0] <= x1 - (x1 - x0) * 0.15)
    return x0, x1, ya, yb


@gen("ink")
def gen_ink():
    """章节卡用大号墨迹（透明底，焦墨色；叠在宣纸 / 画面上用 modulate 调浓淡）。
    要朱色 / 泥金色墨迹：挂 assets/theme/ink_tint.gdshader（按贴图 alpha 着任意色），见 docs/美术规范.md 第 5 节。"""
    # 1 横扫：起笔顿笔积墨，向右上扫出，后三成干笔飞白、鬃毛参差收锋
    W, H = 2100, 760
    t = np.linspace(0, 1, 400)
    path = np.stack([200 + 1740 * t, 440 - 150 * t - 70 * np.sin(np.pi * t)], 1)
    L = 1800.0
    hw0 = 176.0
    dens = bristle_stroke(W, H, path, lambda u: hw0 * (1 + 0.05 * np.exp(-u / 0.04)) * (1 - 0.32 * u) + 8, 901,
                          n=560, dry=0.97, dry_start=0.46, head=hw0 / L, tail=0.20, fray=0.12, clumps=22,
                          wet_fill=0.9, edge_wob=0.035)
    dens = dens + head_pool(W, H, path, hw0, 903, along=1.12, across=0.94, back=1.0, rot=28)
    a = ink_finish(dens, 902, tooth=0.55)
    save_ink("ink_splash_sweep.png", a, 904)
    # 1b 港名 / 章节名墨刷底：近水平一笔，前六成实心可写字，后段飞白收锋
    W, H = 1760, 480
    t = np.linspace(0, 1, 400)
    path = np.stack([150 + 1480 * t, 252 - 26 * np.sin(np.pi * t) - 14 * t], 1)
    L = 1480.0
    hw0 = 150.0
    dens = bristle_stroke(W, H, path, lambda u: hw0 * (1 + 0.04 * np.exp(-u / 0.05)) * (1 - 0.14 * u) + 6, 905,
                          n=520, dry=0.97, dry_start=0.62, head=hw0 / L, tail=0.16, fray=0.10, clumps=20,
                          wet_fill=1.0, edge_wob=0.03)
    dens = dens + head_pool(W, H, path, hw0, 906, along=1.12, across=0.94, back=1.0, rot=28)
    a = ink_finish(dens, 907, tooth=0.55)
    ox, oy = save_ink("ink_splash_plate.png", a, 908)
    z = plate_zone(a)
    if z:
        print(f"    plate 实心段（贴图像素）x {z[0] - ox}–{z[1] - ox}，y {z[2] - oy}–{z[3] - oy}")
    # 2 泼墨：中心墨团 + 淡晕 + 放射飞溅
    W = H = 1400
    rng = np.random.default_rng(910)
    core = blob(W, H, 700, 700, 300, 911, 0.30, 4)
    halo = blob(W, H, 700, 700, 400, 912, 0.30, 6) * blur(blob(W, H, 700, 700, 380, 915, 0.3, 30), 30) * 0.28
    a = np.maximum(core * 0.95, halo)
    x, y = grid(W, H)
    for i in range(260):
        ang = rng.uniform(0, 2 * np.pi)
        big = i < 40
        dist = 300 * (rng.uniform(1.0, 1.9) if big else rng.uniform(1.05, 2.3) ** 1.2)
        r = min(24.0, 14 * rng.pareto(2.2) + 6) if big else rng.uniform(1.2, 5.0)
        cx, cy = 700 + np.cos(ang) * dist, 700 + np.sin(ang) * dist
        if not (r + 6 < cx < W - r - 6 and r + 6 < cy < H - r - 6):
            continue
        x0, x1, y0, y1 = int(cx - 3 * r - 4), int(cx + 3 * r + 5), int(cy - 3 * r - 4), int(cy + 3 * r + 5)
        el = 1 + (rng.uniform(0.2, 1.4) if big else rng.uniform(0, 0.5))
        ca, sa = np.cos(ang), np.sin(ang)
        dx, dy = x[:, x0:x1] - cx, y[y0:y1, :] - cy
        u = (dx * ca + dy * sa) / el
        v = -dx * sa + dy * ca
        rr = np.hypot(u, v) * (1 + 0.18 * np.sin(np.arctan2(v, u) * rng.integers(3, 7) + rng.uniform(0, 6)))
        a[y0:y1, x0:x1] = np.maximum(a[y0:y1, x0:x1], rng.uniform(0.8, 0.97) * sstep(1.2, -1.2, rr - r))
    for _ in range(6):
        ang = rng.uniform(0, 2 * np.pi)
        Ls = rng.uniform(160, 300)
        tt = np.linspace(0, 1, 60)
        p = np.stack([700 + np.cos(ang) * (230 + Ls * tt), 700 + np.sin(ang) * (230 + Ls * tt)], 1)
        dens = bristle_stroke(W, H, p, lambda u: 16 * (1 - u) + 1.5, int(rng.integers(1e6)), n=30, dry=0.9,
                              dry_start=0.35, tail=0.12)
        a = np.maximum(a, ink_finish(dens, 913))
    save_ink("ink_splash_burst.png", np.clip(a, 0, 1), 914)
    # 3 悬针竖：顿笔起，末端出锋（出锋尖细，收笔抖动小）
    W, H = 700, 1950
    t = np.linspace(0, 1, 300)
    path = np.stack([350 + 18 * np.sin(np.pi * t * 1.2), 190 + 1620 * t], 1)
    hw0 = 112.0
    dens = bristle_stroke(W, H, path, lambda u: hw0 * (1 + 0.04 * np.exp(-u / 0.03)) * (1 - u ** 1.6) + 3,
                          920, n=300, dry=0.8, dry_start=0.58, head=hw0 / 1620, tail=0.05, fray=0.06, clumps=10,
                          wet_fill=0.8)
    dens = dens + head_pool(W, H, path, hw0, 922, along=1.0, across=0.98, back=0.95)
    a = ink_finish(dens, 921, tooth=0.45)
    save_ink("ink_splash_stroke.png", a, 923)
    # 4 圆相：一笔绕圆，收笔干枯、鬃毛散开
    W = H = 1500
    t = np.linspace(0, 1, 700)
    ang = np.deg2rad(-110 + 322 * t)
    R = 560 + 25 * np.sin(3 * np.pi * t)
    path = np.stack([750 + R * np.cos(ang), 750 + R * np.sin(ang)], 1)
    hw0 = 88.0
    Lr = float(np.hypot(*np.diff(path, axis=0).T).sum())
    dens = bristle_stroke(W, H, path, lambda u: hw0 * (1 + 0.05 * np.exp(-u / 0.02)) * (1 - 0.40 * u) + 5, 930,
                          n=280, dry=0.97, dry_start=0.55, head=hw0 / Lr, tail=0.16, fray=0.14, clumps=14,
                          wet_fill=0.9, edge_wob=0.035)
    dens = dens + head_pool(W, H, path, hw0, 933, along=1.1, across=0.95, back=1.0, rot=24)
    a = ink_finish(dens, 931, tooth=0.55)
    save_ink("ink_splash_ring.png", a, 932)
    # 5 晕染：几团淡墨叠化，边缘水痕积墨
    W, H = 1900, 1050
    a = np.zeros((H, W), np.float32)
    for i, (cx, cy, R, al) in enumerate(((760, 520, 360, 0.58), (1180, 470, 300, 0.46), (520, 600, 230, 0.40),
                                         (1420, 610, 200, 0.34))):
        m = blob(W, H, cx, cy, R, 940 + i, 0.30, 5)
        body = blur(m, 34) * (0.8 + 0.2 * noise(H, W, 1.9, 950 + i))
        rim = np.clip(m - blur(m, 7), 0, 1)
        layer = np.clip(al * (0.6 * body + 0.4 * m) + 0.75 * al * rim, 0, 1)
        a = 1 - (1 - a) * (1 - layer)
    save_ink("ink_splash_wash.png", a, 970)


# ==== END GENERATORS ====


def contact_sheet(path):
    bg = Image.open(ROOT / "assets" / "bg_quanzhou_harbor.jpg").convert("RGB")
    tiles = []
    for name in MADE:
        im = Image.open(OUT / name).convert("RGBA")
        im.thumbnail((360, 300))
        cell = Image.new("RGB", (380, 330), (40, 40, 40))
        back = bg.resize((380, 214)).crop((0, 0, 380, 214))
        cell.paste(back.resize((380, 310)), (0, 0))
        cell.paste(Image.new("RGB", (190, 310), (233, 220, 192)), (190, 0))
        cell.paste(im, ((380 - im.size[0]) // 2, (310 - im.size[1]) // 2), im)
        ImageDraw.Draw(cell).text((4, 312), name, fill=(255, 255, 160), font=ImageFont.truetype(WENKAI, 14))
        tiles.append(cell)
    cols = 5
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 380, rows * 330), (20, 20, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * 380, (i // cols) * 330))
    sheet.save(path, quality=88)
    print("总览：", path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--sheet", default="")
    args = ap.parse_args()
    names = [n for n in args.only.split(",") if n] or list(GENERATORS)
    for n in names:
        if n not in GENERATORS:
            print("未知生成器", n, "可选：", ",".join(GENERATORS))
            return 2
        print(f"[{n}]")
        GENERATORS[n]()
    if args.sheet:
        contact_sheet(args.sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
