# -*- coding: utf-8 -*-
"""墨影卡合成：旧绢底（经纬、霉斑、绢丝断裂、赭褐晕边、暖光）+ 背景淡墨 + 人物墨影 + 雾带 + 题签朱印。
全部在 2× 画布上算，最后由 build_portraits 缩回 512×640。"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import figures
import inkbrush as ib
import scenes

S, W, H, WS, HS = ib.S, ib.W, ib.H, ib.WS, ib.HS


def _grid():
    return ib._grid()


def grad_map(t, stops):
    pos = np.array([p for p, _ in stops], np.float32)
    cols = np.array([c for _, c in stops], np.float32)
    out = np.empty(t.shape + (3,), np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, cols[:, ch])
    return out


# ───────────────────────── 旧绢 ─────────────────────────
def silk(seed, light=(250, 205), spread=1.0):
    """旧绢：烛光 / 暮光从人物身后铺开一片暖光（覆盖头部与题签），四角与下缘沉成烟熏的赭褐，
    与油画立绘的暗底同调。"""
    rng = np.random.default_rng(seed)
    xx, yy = _grid()
    r = np.sqrt(((xx - light[0]) / (330.0 * spread)) ** 2 + ((yy - light[1]) / (350.0 * spread)) ** 2)
    lf = ib.value_noise((HS, WS), 240 * S, seed + 1, octaves=4)
    mf = ib.value_noise((HS, WS), 50 * S, seed + 2, octaves=4)
    r = r + (lf - 0.5) * 0.16
    base = grad_map(r, [(0.00, (0.84, 0.74, 0.54)), (0.34, (0.75, 0.62, 0.43)), (0.62, (0.55, 0.41, 0.26)),
                        (0.88, (0.34, 0.235, 0.14)), (1.15, (0.2, 0.135, 0.08)), (2.0, (0.12, 0.08, 0.05))])
    # 题签处绢面略亮（题签总写在光处）：竖向椭圆，罩住姓名、身份与印
    xx0, yy0 = _grid()
    tl = np.clip(1 - np.sqrt(((xx0 - 452) / 100.0) ** 2 + ((yy0 - 230) / 260.0) ** 2), 0, 1) ** 1.2 * 0.34
    base = base * (1 + tl[..., None]) + tl[..., None] * np.array([0.05, 0.04, 0.02], np.float32)
    # 经纬：横丝为主（逐行细噪、带一点低频起伏），竖丝很弱；不用周期纹，免得缩小后出摩尔纹
    rows = rng.normal(0, 1, (HS, 1)).astype(np.float32)
    rows = rows * (0.6 + 0.8 * ib.value_noise((HS, 1), 40 * S, seed + 9, octaves=2))
    cols = rng.normal(0, 1, (1, WS)).astype(np.float32)
    thread = ib.value_noise((HS, WS), 30 * S, seed + 8, octaves=2, aspect=12.0)
    weave = rows * 0.010 * (0.5 + thread) + cols * 0.004
    weave += rng.normal(0, 1, (HS, WS)).astype(np.float32) * 0.008
    # 粗节丝：横向短丝
    slub = ib.streak_noise((HS, WS), 90, 26 * S, 0.8 * S, seed + 3)
    weave += (ib.smoothstep(0.78, 0.95, slub) - ib.smoothstep(0.05, 0.2, 1 - slub) * 0.0) * 0.03
    shade = 1.0 + (lf - 0.5) * 0.10 + (mf - 0.5) * 0.06 + weave
    img = base * shade[..., None]
    zhe = np.array((0.54, 0.35, 0.17), np.float32)
    # 水渍：低频噪声的等值线 → 赭色潮线
    v = ib.value_noise((HS, WS), 150 * S, seed + 4, octaves=3)
    tide = np.exp(-((v - 0.56) / 0.006) ** 2) * 0.5 + np.exp(-((v - 0.62) / 0.005) ** 2) * 0.35
    tide = ib.blur(tide.astype(np.float32), 1.2 * S)
    stain = ib.smoothstep(0.56, 0.7, v) * 0.10
    a = np.clip(tide * 0.18 + stain, 0, 1)[..., None]
    img = img * (1 - a) + img * zhe / 0.75 * a
    # 磨损：绢面起毛泛白
    wear = ib.smoothstep(0.66, 0.82, ib.value_noise((HS, WS), 90 * S, seed + 5, octaves=4)) * 0.05
    img = img + wear[..., None] * np.array([0.9, 0.85, 0.7], np.float32)
    # 霉点
    for _ in range(int(rng.integers(6, 12))):
        cx, cy = rng.random() * W, rng.random() * H
        rr = 1.5 + rng.random() * 5
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        sp = np.clip(1 - d / rr, 0, 1) ** 1.5 * (0.10 + rng.random() * 0.14)
        img = img * (1 - sp[..., None] * (1 - zhe / 0.8))
    # 绢丝断裂：几道横向细裂（亮线 + 暗边）
    crack = Image.new("L", (WS, HS), 0)
    dr = ImageDraw.Draw(crack)
    for _ in range(int(rng.integers(4, 9))):
        x0, y0 = rng.random() * W * S, rng.random() * H * S
        ln = rng.uniform(30, 180) * S
        pts = []
        for k in range(12):
            pts.append((x0 + ln * k / 11, y0 + rng.normal(0, 0.6) * S))
        dr.line(pts, fill=255, width=1)
    cr = np.asarray(crack, np.float32) / 255.0
    img = img + (cr * 0.05 - (ib.blur(cr, 1.2) - cr * 0.4) * 0.05)[..., None]
    return np.clip(img, 0, 1).astype(np.float32)


# ───────────────────────── 雾 ─────────────────────────
def mist(spec, seed, tex):
    """人物消散：下缘渐枯入雾 + 横向雾带 + 一侧被留白吃掉。雾高、雾带条数与走向按种子与景别变化。
    返回 (人物雾, 背景雾)。"""
    xx, yy = _grid()
    rng = np.random.default_rng(seed + 50)
    comp = spec.get("comp", {})
    hy, s = comp.get("hy", 190.0), comp.get("s", 0.9)
    # 人物大约在腰下（身坐标 y≈300–420）开始入雾；近景可以一直画到底
    base = hy + s * rng.uniform(300, 420)
    f0 = spec.get("fade", min(600.0, max(430.0, base)))
    lo = tex.low
    hz = ib.value_noise((HS, WS), rng.uniform(50, 90) * S, seed + 51, octaves=4, aspect=rng.uniform(2.5, 5.5))
    slope = rng.uniform(-0.18, 0.18)
    y = yy + (xx - 256) * slope + (lo - 0.5) * 80 + (hz - 0.5) * 70 + (tex.fine - 0.5) * 10
    fig = ib.smoothstep(f0, f0 + rng.uniform(80, 140), y)
    bands = np.zeros_like(fig)
    nb = int(rng.integers(1, 4))
    for k in range(nb):
        yc = f0 - rng.uniform(10, 60) - k * rng.uniform(40, 90)
        amt = (0.75 if k == 0 else 0.3) * rng.uniform(0.7, 1.0)
        win = np.exp(-((yy + (xx - 256) * slope * 1.5 + (hz - 0.5) * 50 - yc) / rng.uniform(20, 40)) ** 2)
        bands = np.maximum(bands, win * ib.smoothstep(0.4, 0.75, hz * 0.75 + lo * 0.25) * amt)
    # 一侧留白：身形边缘被雾吃掉一块（背侧）
    sg = spec.get("eat", -1 if spec.get("turn", 0.5) >= 0 else 1)
    ex = comp.get("hx", 240) + sg * rng.uniform(150, 200)
    ey = rng.uniform(430, 540)
    eat = ib.radial((ex, ey), rng.uniform(90, 150), 1.3) * ib.smoothstep(0.35, 0.65, hz * 0.6 + lo * 0.4)
    figm = np.clip(fig + bands * (1 - fig) + eat * 0.8, 0, 1)
    bgm = np.clip(bands * 0.85 + ib.smoothstep(0.62, 0.8, hz) * ib.smoothstep(470, 560, yy) * 0.5, 0, 1)
    return figm.astype(np.float32), bgm.astype(np.float32)


# ───────────────────────── 题签 ─────────────────────────
def text_mask(text, font_path, px, x_center, y_top, spacing, glyph_font):
    """竖排文字 → 2× 覆盖率。返回 (mask, y_end 1×)。"""
    im = Image.new("L", (WS, HS), 0)
    d = ImageDraw.Draw(im)
    y = y_top * S
    P = int(px * S)
    for ch in text:
        fp, fell = glyph_font(font_path, ch)
        font = ImageFont.truetype(fp, P)
        sw = max(1, P // 40) if fell else 0
        bb = d.textbbox((0, 0), ch, font=font, stroke_width=sw)
        cw = bb[2] - bb[0]
        d.text((x_center * S - cw / 2 - bb[0], y - bb[1] + (P - (bb[3] - bb[1])) / 2), ch, font=font, fill=255,
               stroke_width=sw, stroke_fill=255)
        y += P * spacing
    return np.asarray(im, np.float32) / 255.0, y / S


def ink_text(m, tex, ink=0.95, dry=0.25):
    """字也是墨写的：边缘微洇、笔画里有极淡的飞白丝。"""
    st = tex.streak(0)
    d = ib.blur(m, 0.5) * ink * (1 - dry * ib.smoothstep(0.72, 0.95, st * 0.6 + tex.fine * 0.4))
    d += np.clip(ib.blur(m, 1.6 * S) - m, 0, 1) * 0.10
    return np.clip(d, 0, 0.99)


# ───────────────────────── 合成 ─────────────────────────
JIAO = np.array((13, 11, 9), np.float32) / 255.0


def apply_ink(img, D, k=0.95):
    out = img * (1 - k * D[..., None])
    # 淡墨偏中性：中间调略去饱和
    lum = out.mean(-1, keepdims=True)
    g = (4 * D * (1 - D))[..., None] * 0.18
    out = out * (1 - g) + lum * g
    return np.maximum(out, JIAO * D[..., None] * 0.9)


def paint(spec, seed):
    """人物选角 → 2× 浮点图（不含题签）。返回 (img, tex, info)，info 里有人物 alpha 等（验收用）。"""
    tex = ib.Tex(seed)
    rng = np.random.default_rng(seed + 7)
    comp = spec.get("comp", {})
    hx, hy, s = comp.get("hx", 240.0), comp.get("hy", 190.0), comp.get("s", 0.9)
    # 光：从人物身后铺开，光心在头后略偏（每张不同），夜景更沉
    night = spec.get("night", False)
    lc = (hx + rng.uniform(-60, 80), hy + rng.uniform(-70, 170))
    img = silk(seed, light=lc, spread=rng.uniform(0.8, 1.25) * (0.84 if night else 1.0))
    img = img * (rng.uniform(0.86, 1.06) * (0.88 if night else 1.0))
    # 上下明暗倾斜（有的上亮下沉，有的上沉下亮——海面、雪地反光），每张不同
    tilt_v = rng.uniform(-0.4, 0.4)
    img = img * np.clip(1 + tilt_v * (_grid()[1] - 320) / 320.0, 0.6, 1.4)[..., None]
    halo = ib.radial((hx - spec.get("turn", 0.5) * 20, hy - 10 * s), 190 * s, 1.6) * (0.08 if not night else 0.05)
    img = img * (1 + halo[..., None] * np.array([0.9, 0.8, 0.55], np.float32))
    # 人物
    fig = figures.build(spec, seed)
    fc, fx = ib.render(fig.parts, tex)
    L = fx["layers"]
    face_m = L.get("face", np.zeros((HS, WS), np.float32))
    fig_a = np.clip(np.maximum(ib.blur(fc.D, 3 * S) * 2.4, face_m), 0, 1)
    figm, bgm = mist(spec, seed, tex)
    # 题签列（x≥412、自顶到印下）是留白：人物与背景在这里淡入绢底，题签总写在空处
    te = spec.get("_title_end", 400.0)
    gx, gy = _grid()
    tclear = ib.smoothstep(392, 414, gx) * ib.smoothstep(te + 46, te + 8, gy)
    figm = np.maximum(figm, tclear * 0.94)
    bgm = np.maximum(bgm, tclear * 0.85)
    # 背景意象：线稿先让开人物（乘 1-α·0.85），再合成
    bg_parts = scenes.build(spec, seed)
    bgc, bgx = ib.render(bg_parts, tex)
    bgc.reserve(bgm)
    bgD = bgc.D * (1 - fig_a * 0.85)
    img = apply_ink(img, bgD, 0.9)
    if any(p.get("kind") == "frame" for p in bg_parts):
        img = hanging_frame(img, seed)
    fc.reserve(figm)
    img = apply_ink(img, fc.D)
    # 设色：公服浅绛——罩在整片袍身上（淡墨与绢底透出处着色最显），受光缘再加一道同色细带
    rt = spec.get("robe_tint")
    if rt and "robe" in L:
        rgb = np.array(figures.ROBE_TINTS[rt] if isinstance(rt, str) else rt, np.float32)
        prop_m = np.clip(ib.blur(L.get("prop", np.zeros((HS, WS), np.float32)), 1.5 * S) * 2, 0, 1)
        body = np.clip(ib.blur(L["robe"], 3 * S) * 2.0, 0, 1) * (1 - face_m) * (1 - figm) * (1 - prop_m)
        amt = spec.get("tint_amount", 0.4)
        lum = img.mean(-1, keepdims=True)
        norm = rgb / rgb.mean()
        # 着色在中间调最显、焦墨与留白处收（矿物色罩在墨上）
        mid = np.clip(4 * lum * (1 - lum) * 1.3, 0, 1)
        rec = lum * norm
        a = (body * amt)[..., None] * (0.5 + 0.5 * mid)
        img = img * (1 - a) + rec * a
    if "gold" in L:
        a = np.clip(L["gold"] * 1.2, 0, 1)[..., None] * 0.7
        img = img * (1 - a) + img.mean(-1, keepdims=True) * np.array((1.5, 1.2, 0.55), np.float32) * a
    if "tassel" in L and spec.get("tassel_red", True):
        a = np.clip(L["tassel"] * 1.3, 0, 1)[..., None] * 0.85
        img = img * (1 - a) + np.array((0.6, 0.16, 0.12), np.float32) * (0.7 + 0.3 * img.mean(-1, keepdims=True)) * a
    for a, rgb, mode in fx["tint"]:
        a = a * (1 - figm)
        rgb = np.array(rgb, np.float32)
        if mode == "opaque":
            img = img * (1 - a[..., None]) + (rgb * (0.9 + 0.2 * tex.mid[..., None])) * a[..., None]
        else:
            lum = img.mean(-1, keepdims=True)
            rec = lum * rgb / rgb.mean()
            img = img * (1 - a[..., None]) + rec * a[..., None]
    if spec.get("snow"):                   # 雪落：留白小点，近大远小
        img = snow(img, seed)
    g = np.clip(fx["glow"], 0, 1.5)[..., None]
    if g.max() > 0:
        warm = np.array((1.0, 0.72, 0.36), np.float32)
        img = img * (1 + g * 0.55 * warm) + g * 0.10 * warm
    # 雾处绢色微亮（雾是光）；约四成的卡人物下半身入一片亮雾（海面、雪地、晨雾反光），下缘反而是亮的
    bright = spec.get("bright_mist", rng.random() < 0.42)
    mist_l = (figm * 0.5 + bgm * 0.5)[..., None] * ib.smoothstep(380, 640, _grid()[1])[..., None]
    img = img * (1 + mist_l * (0.42 if bright else 0.1))
    if bright:
        warm = np.array((0.95, 0.86, 0.66), np.float32)
        a = (np.clip(figm * 1.1, 0, 1) * ib.smoothstep(420, 620, _grid()[1]))[..., None] * 0.45
        img = img * (1 - a) + warm * a
    info = {"fig_alpha": np.clip(fig_a * (1 - figm), 0, 1), "fig_raw": fig_a, "fig_d": fc.D, "face": face_m}
    return np.clip(img, 0, 1), tex, info


def snow(img, seed):
    rng = np.random.default_rng(seed + 900)
    im = Image.new("L", (WS, HS), 0)
    d = ImageDraw.Draw(im)
    for _ in range(170):
        x, y = rng.random() * WS, rng.random() * HS * 0.92
        r = (0.8 + rng.random() ** 3 * 2.6) * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=int(150 + rng.random() * 105))
    m = ib.blur(np.asarray(im, np.float32) / 255.0, 0.7 * S)[..., None]
    col = np.array((0.93, 0.89, 0.80), np.float32)
    return img * (1 - m * 0.85) + col * m * 0.85


def hanging_frame(img, seed):
    """祠堂遗像：内衬一道深色裱边 + 上方两条惊燕带。"""
    xx, yy = _grid()
    m = 22
    inner = (xx > m) & (xx < W - m) & (yy > m) & (yy < H - m)
    band = (~inner).astype(np.float32)
    band = ib.blur(band, 1.0 * S)
    col = np.array((0.24, 0.17, 0.11), np.float32)
    img = img * (1 - band[..., None] * 0.8) + col * band[..., None] * 0.8
    edge = np.exp(-((np.minimum.reduce([xx - m, W - m - xx, yy - m, H - m - yy])) / 1.6) ** 2)
    img = img * (1 - edge[..., None] * 0.45)
    for x0 in (150, 262):
        strip = ((xx > x0) & (xx < x0 + 14) & (yy > m) & (yy < 150)).astype(np.float32)
        strip = ib.blur(strip, 0.8 * S)
        img = img * (1 - strip[..., None] * 0.35)
    return img
