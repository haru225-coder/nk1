#!/usr/bin/env python3
"""过场与动效贴图生成器（cutscene_engine 线）。可重复运行，结果确定（固定随机种子）。

输出到 assets/fx/，全部是粒子与 shader 用的透明底 / 灰度噪声贴图：
  粒子（白色，靠粒子 color 着色，透明底）
    soft_dot.png      64x64    柔光点（通用、雾点、飞沫雾）
    ember.png         32x32    火星：亮芯 + 外晕
    snow_flake.png    32x32    雪片：略不规则的软圆
    mist_puff.png     256x256  雾团：分形噪声 × 径向衰减
    rain_streak.png   8x96     雨丝：细芯 + 两端渐隐
    spray_drop.png    24x24    浪花水滴：实芯软边
    dust_mote.png     16x16    尘埃微粒
    glow_warm.png     128x128  灯晕：1/(1+r²) 式长尾径向
  shader 噪声（灰度，RGB 同值，alpha=255，可平铺）
    noise_ink.png     256x256  墨边噪声：1/f^1.6 分形（周期谱合成，天然可平铺）
    noise_fiber.png   512x512  纸纹：长短纤维 + 低频斑驳
    silk_weave.png    128x128  绢纹：经纬线 + 粗细不匀
    noise_grain.png   256x256  胶片颗粒：高斯白噪声（轻微模糊）

用法：python3 tools/art/build_fx_textures.py [--out DIR] [--preview PATH]
"""
import argparse
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "fx"


def radial(size, cx=None, cy=None):
    cx = (size - 1) / 2.0 if cx is None else cx
    cy = (size - 1) / 2.0 if cy is None else cy
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    return np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (size / 2.0)


def save_alpha(path, alpha, rgb=(255, 255, 255)):
    """白色 + alpha 通道。alpha: 0..1 float 数组。"""
    a = np.clip(alpha, 0.0, 1.0)
    h, w = a.shape
    img = np.zeros((h, w, 4), dtype=np.uint8)
    img[..., 0] = rgb[0]
    img[..., 1] = rgb[1]
    img[..., 2] = rgb[2]
    img[..., 3] = np.round(a * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path, optimize=True)


def save_gray(path, v):
    g = np.round(np.clip(v, 0.0, 1.0) * 255).astype(np.uint8)
    Image.fromarray(np.dstack([g, g, g]), "RGB").save(path, optimize=True)


def periodic_noise(size, beta, rng, octave_cut=None):
    """1/f^beta 谱合成；FFT 周期边界 → 天然无缝平铺。返回 0..1。"""
    white = rng.standard_normal((size, size))
    f = np.fft.fft2(white)
    ky = np.fft.fftfreq(size)[:, None]
    kx = np.fft.fftfreq(size)[None, :]
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1.0
    amp = 1.0 / (k ** beta)
    amp[0, 0] = 0.0
    if octave_cut is not None:
        amp *= np.exp(-(k / octave_cut) ** 2)
    n = np.real(np.fft.ifft2(f * amp))
    n = (n - n.mean()) / (n.std() + 1e-9)
    # 映射到 0..1：±2.6σ 截断，保证对比充足
    return np.clip(0.5 + n / 5.2, 0.0, 1.0)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def build(out: pathlib.Path):
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(1255)
    made = []

    # ── 粒子 ─────────────────────────────────────────
    r = radial(64)
    save_alpha(out / "soft_dot.png", np.exp(-(r ** 2) * 4.2) * smoothstep(1.0, 0.82, r))
    made.append("soft_dot.png")

    r = radial(32)
    core = np.exp(-(r ** 2) * 38.0)
    halo = np.exp(-(r ** 2) * 5.0) * 0.55
    save_alpha(out / "ember.png", np.clip(core + halo, 0, 1) * smoothstep(1.0, 0.8, r))
    made.append("ember.png")

    # 雪片：软圆，边缘用角度噪声扰动成不规则
    s = 32
    y, x = np.mgrid[0:s, 0:s].astype(np.float64)
    cx = cy = (s - 1) / 2.0
    ang = np.arctan2(y - cy, x - cx)
    rr = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (s / 2.0)
    wob = 1.0 + 0.10 * np.sin(ang * 3 + 0.7) + 0.07 * np.sin(ang * 5 + 2.1)
    save_alpha(out / "snow_flake.png", smoothstep(0.78 * wob, 0.30 * wob, rr) * 0.95)
    made.append("snow_flake.png")

    # 雾团：低频噪声 × 径向衰减，边缘彻底透明
    s = 256
    n = periodic_noise(s, 1.9, rng)
    n2 = periodic_noise(s, 1.2, rng)
    rr = radial(s)
    fall = smoothstep(1.0, 0.15, rr)
    cloud = np.clip((n * 0.75 + n2 * 0.25 - 0.28) * 1.9, 0, 1)
    a = cloud * fall ** 1.4
    a = a / max(a.max(), 1e-6) * 0.92
    img = Image.fromarray(np.round(a * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(2.0))
    save_alpha(out / "mist_puff.png", np.asarray(img).astype(np.float64) / 255.0)
    made.append("mist_puff.png")

    # 雨丝：8x96，横向高斯细芯，纵向两端渐隐（头淡尾实，下落时看着有拖尾）
    w, h = 8, 96
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    across = np.exp(-((x - (w - 1) / 2.0) ** 2) / (2 * 0.9 ** 2))
    along = smoothstep(0.0, 0.55, y / (h - 1)) * smoothstep(1.0, 0.86, y / (h - 1))
    save_alpha(out / "rain_streak.png", across * along)
    made.append("rain_streak.png")

    r = radial(24)
    save_alpha(out / "spray_drop.png", smoothstep(0.95, 0.45, r) * 0.9 + np.exp(-(r ** 2) * 9) * 0.1)
    made.append("spray_drop.png")

    r = radial(16)
    save_alpha(out / "dust_mote.png", np.exp(-(r ** 2) * 6.0) * smoothstep(1.0, 0.7, r))
    made.append("dust_mote.png")

    r = radial(128)
    glow = 1.0 / (1.0 + (r * 4.2) ** 2)
    glow = (glow - glow.min())
    glow = glow / glow.max() * smoothstep(1.0, 0.72, r)
    save_alpha(out / "glow_warm.png", glow)
    made.append("glow_warm.png")

    # ── shader 噪声 ─────────────────────────────────
    ink = periodic_noise(256, 1.6, rng)
    save_gray(out / "noise_ink.png", ink)
    made.append("noise_ink.png")

    # 纸纹：纤维在 3x3 平铺画布上画，再切中间一块 → 无缝
    s = 512
    big = Image.new("L", (s * 3, s * 3), 128)
    d = ImageDraw.Draw(big)
    for _ in range(2400):
        x0 = rng.uniform(0, s)
        y0 = rng.uniform(0, s)
        ln = rng.uniform(6, 46)
        ang = rng.uniform(0, math.pi)
        curve = rng.uniform(-0.35, 0.35)
        shade = int(128 + rng.choice([-1, 1]) * rng.uniform(10, 38))
        width = 1 if rng.random() < 0.85 else 2
        pts = []
        for i in range(7):
            t = i / 6.0
            a2 = ang + curve * (t - 0.5)
            pts.append((x0 + math.cos(a2) * ln * t, y0 + math.sin(a2) * ln * t))
        for ox in (0, s, 2 * s):
            for oy in (0, s, 2 * s):
                d.line([(px + ox, py + oy) for px, py in pts], fill=shade, width=width)
    big = big.filter(ImageFilter.GaussianBlur(0.6))
    fib = np.asarray(big.crop((s, s, 2 * s, 2 * s))).astype(np.float64) / 255.0
    mott = periodic_noise(s, 2.2, rng)
    fine = periodic_noise(s, 0.6, rng)
    paper = 0.5 + (fib - 0.5) * 0.9 + (mott - 0.5) * 0.35 + (fine - 0.5) * 0.12
    save_gray(out / "noise_fiber.png", paper)
    made.append("noise_fiber.png")

    # 绢纹：经线（竖）与纬线（横）交织，线粗与亮度带随机不匀
    s = 128
    y, x = np.mgrid[0:s, 0:s].astype(np.float64)
    warp_j = periodic_noise(s, 2.0, rng)[0:1, :] - 0.5      # 每根经线亮度差
    weft_j = periodic_noise(s, 2.0, rng)[:, 0:1] - 0.5
    pitch = 4.0
    wv = 0.5 + 0.5 * np.cos(2 * math.pi * x / pitch)
    wf = 0.5 + 0.5 * np.cos(2 * math.pi * y / pitch)
    over = ((np.floor(x / pitch) + np.floor(y / pitch)) % 2)
    weave = np.where(over > 0.5, wv * 0.8 + wf * 0.2, wf * 0.8 + wv * 0.2)
    weave = 0.5 + (weave - 0.5) * 0.55 + warp_j * 0.35 + weft_j * 0.3
    weave += (periodic_noise(s, 0.4, rng) - 0.5) * 0.10
    save_gray(out / "silk_weave.png", weave)
    made.append("silk_weave.png")

    g = rng.standard_normal((256, 256))
    gi = Image.fromarray(np.round(np.clip(0.5 + g / 6.0, 0, 1) * 255).astype(np.uint8), "L")
    gi = gi.filter(ImageFilter.GaussianBlur(0.45))
    ga = np.asarray(gi).astype(np.float64) / 255.0
    ga = 0.5 + (ga - ga.mean()) / (ga.std() + 1e-9) / 6.0
    save_gray(out / "noise_grain.png", ga)
    made.append("noise_grain.png")
    return made


def preview(out: pathlib.Path, names, path):
    cell = 200
    sheet = Image.new("RGB", (cell * 4, (cell + 20) * ((len(names) + 3) // 4)), (31, 58, 77))
    d = ImageDraw.Draw(sheet)
    for i, nm in enumerate(names):
        im = Image.open(out / nm).convert("RGBA")
        scale = min(cell / im.width, cell / im.height)
        im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.NEAREST if im.width < 64 else Image.BILINEAR)
        x = (i % 4) * cell
        y = (i // 4) * (cell + 20)
        sheet.paste(im, (x + (cell - im.width) // 2, y + 20 + (cell - im.height) // 2), im)
        d.text((x + 4, y + 4), nm, fill=(233, 220, 192))
    sheet.save(path, quality=85)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    o = pathlib.Path(args.out)
    names = build(o)
    print(f"已生成 {len(names)} 张贴图 → {o}")
    for n in names:
        im = Image.open(o / n)
        print(f"  {n:18s} {im.size[0]}x{im.size[1]} {im.mode}")
    if args.preview:
        preview(o, names, args.preview)
        print("总览:", args.preview)
