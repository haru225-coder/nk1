#!/usr/bin/env python3
"""海战命中 / 齐射粒子贴图（lane ship-vfx polish）。可重复运行，结果确定（固定随机种子）。

旧贴图 soft_dot / glow_warm / mist_puff 都是高斯软圆，放大当炮口焰、烟、水花用就成一团白晕。
这里出一组边缘清楚、有形状的贴图，白 / 灰度底，靠粒子 color 着色：
    smoke_puff.png   128x128  火药烟团：几个圆瓣叠成的菜花形，瓣边 2–3 px 软边，瓣内左上亮右下暗
    flash_star.png    64x64   齐射 / 命中一闪：七叉星芒 + 亮芯，叉尖利
    spark_streak.png   8x32   火星拖线：细芯、头亮尾淡（粒子开 align_y 顺速度拉长）
    splinter.png      16x8    木屑：参差长条，一侧新茬浅
    water_drop.png    12x24   水柱溅滴：椭圆实芯 + 高光
    foam_ring.png     64x64   落水白沫圈：断续细环
用法：python3 tools/art/build_combat_fx.py [--out DIR]
"""
import argparse
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "fx"
SS = 4  # 超采样倍数：先画大图再缩，边缘干净


def _save(img: Image.Image, out: pathlib.Path, name: str, size) -> None:
    img = img.resize(size, Image.LANCZOS)
    img.save(out / name)
    print(f"  {name} {size[0]}x{size[1]}")


def smoke_puff(out):
    rng = np.random.default_rng(7)
    n = 128 * SS
    y, x = np.mgrid[0:n, 0:n].astype(np.float64) / n
    alpha = np.zeros((n, n))
    lobes = [(0.5, 0.53, 0.24), (0.43, 0.47, 0.17), (0.58, 0.46, 0.16)]
    for i in range(13):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.06, 0.15)
        d = rng.uniform(0.16, 0.40 - r)
        lobes.append((0.5 + math.cos(a) * d, 0.52 + math.sin(a) * d * 0.9, r))
    for cx, cy, r in lobes:
        dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
        alpha = np.maximum(alpha, np.clip((1.0 - dist) * r * 90.0, 0.0, 1.0))
    # 整团当一块起伏：模糊后的 alpha 当高度，取梯度打左上光
    h = np.array(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(SS * 7))) / 255.0
    gy, gx = np.gradient(h)
    k = 1.0 / (np.abs(gx).max() + 1e-6)
    lit = np.clip(0.62 + (-gx * -0.55 + -gy * -0.75) * k * 0.55 + (h - 0.5) * 0.35, 0.0, 1.0)
    grain = rng.normal(0.0, 1.0, (24, 24))
    grain = np.array(Image.fromarray(((grain - grain.min()) / np.ptp(grain) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
    v = np.clip(lit * (0.88 + 0.12 * grain), 0.0, 1.0)
    rgb = (0.40 + 0.60 * v) * 255
    a = alpha * (0.82 + 0.18 * grain) * 255
    img = np.dstack([rgb, rgb, rgb, a]).astype(np.uint8)
    _save(Image.fromarray(img, "RGBA"), out, "smoke_puff.png", (128, 128))


def flash_star(out):
    n = 64 * SS
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    c = n / 2
    rng = np.random.default_rng(11)
    spikes = 7
    pts = []
    for i in range(spikes * 2):
        a = i / (spikes * 2) * math.tau + 0.2
        if i % 2 == 0:
            r = n * 0.5 * rng.uniform(0.78, 0.98)
        else:
            r = n * 0.5 * 0.2
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=150)
    d.ellipse((c - n * 0.2, c - n * 0.2, c + n * 0.2, c + n * 0.2), fill=225)
    d.ellipse((c - n * 0.1, c - n * 0.1, c + n * 0.1, c + n * 0.1), fill=255)
    img = img.filter(ImageFilter.GaussianBlur(SS * 0.8))
    a = np.array(img)
    rgba = np.dstack([np.full_like(a, 255)] * 3 + [a])
    _save(Image.fromarray(rgba, "RGBA"), out, "flash_star.png", (64, 64))


def spark_streak(out):
    w, h = 8 * SS, 32 * SS
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    core = np.exp(-(((x - (w - 1) / 2) / (w * 0.16)) ** 2))
    along = np.clip(y / h, 0, 1)  # 头在下（+y 顺速度）
    a = core * along ** 1.6
    rgba = np.dstack([np.full((h, w), 255)] * 3 + [a * 255]).astype(np.uint8)
    _save(Image.fromarray(rgba, "RGBA"), out, "spark_streak.png", (8, 32))


def splinter(out):
    w, h = 16 * SS, 8 * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = [(0, h * 0.55), (w * 0.2, h * 0.2), (w * 0.55, h * 0.3), (w * 0.8, h * 0.05), (w, h * 0.45),
           (w * 0.75, h * 0.75), (w * 0.45, h * 0.95), (w * 0.15, h * 0.8)]
    d.polygon(pts, fill=(150, 150, 150, 255))
    d.line([(w * 0.15, h * 0.38), (w * 0.85, h * 0.25)], fill=(255, 255, 255, 255), width=SS * 2)
    _save(img, out, "splinter.png", (16, 8))


def water_drop(out):
    w, h = 12 * SS, 24 * SS
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    nx = (x - (w - 1) / 2) / (w * 0.42)
    ny = (y - h * 0.58) / (h * 0.42)
    ny = np.where(ny < 0, ny * 0.8, ny)
    dist = np.sqrt(nx ** 2 + ny ** 2)
    a = np.clip((1.0 - dist) * 6.0, 0, 1)
    hl = np.exp(-(((x - w * 0.38) / (w * 0.12)) ** 2 + ((y - h * 0.5) / (h * 0.14)) ** 2))
    v = np.clip(0.78 + 0.22 * hl, 0, 1) * 255
    rgba = np.dstack([v, v, v, a * 255]).astype(np.uint8)
    _save(Image.fromarray(rgba, "RGBA"), out, "water_drop.png", (12, 24))


def foam_ring(out):
    rng = np.random.default_rng(5)
    n = 64 * SS
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / (n / 2)
    ang = np.arctan2(y - c, x - c)
    wob = 0.03 * np.sin(ang * 7 + 1.3) + 0.02 * np.sin(ang * 13)
    ring = np.exp(-(((r - 0.78 - wob) / 0.07) ** 2))
    breaks = 0.55 + 0.45 * np.sin(ang * 5 + rng.uniform(0, 6)) * np.sin(ang * 3 + 0.7)
    a = np.clip(ring * (0.35 + 0.65 * np.clip(breaks, 0, 1)) * 1.3, 0, 1)
    rgba = np.dstack([np.full((n, n), 255)] * 3 + [a * 255]).astype(np.uint8)
    _save(Image.fromarray(rgba, "RGBA"), out, "foam_ring.png", (64, 64))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    out = pathlib.Path(ap.parse_args().out)
    out.mkdir(parents=True, exist_ok=True)
    for fn in (smoke_puff, flash_star, spark_streak, splinter, water_drop, foam_ring):
        fn(out)


if __name__ == "__main__":
    main()
