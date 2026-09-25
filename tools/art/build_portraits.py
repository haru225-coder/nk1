#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""立绘构建：产出 assets/portraits/<人物 id>.png（512×640，与 Codex 立绘同规格）。

两类产物，全部以 data/characters.json 为准：
  1. painted（portrait_status=painted）：从 Codex / main 旧油画按人物逐张修瑕后落地——
     去日文招牌字、阿那紫皮改古铜并做厚涂化、净海换掉樱花和式寺檐、市舶小吏压掉明式补子、
     施那帏蓝天改暮色等，处理逐条写在 PAINTED 表里，可复现。
  2. placeholder：在油画到位前，生成一套同规格「绢本墨影」兜底卡——旧绢底、焦墨人物剪影
     （按冠服拼装：展脚幞头 / 兜鍪 / 缠头 / 钹笠帽 / 高髻 …，见 tools/art/portrait_svg/）、
     马善政楷书竖排姓名、朱砂阵营印。SVG 用 rsvg-convert 渲染，纸纹墨韵用 numpy 合成。

用法（仓库根）：
  python3 tools/art/build_portraits.py                  # 全部 74 张
  python3 tools/art/build_portraits.py --only veteran,pilot_ana
  python3 tools/art/build_portraits.py --painted-only | --cards-only
  python3 tools/art/build_portraits.py --sheet /tmp/sheet.jpg   # 另出一张带编号的总览小样
依赖：python3 + Pillow + numpy；/opt/homebrew/bin/rsvg-convert（或 PATH 里的 rsvg-convert）。
Codex 源图在仓库外（nk1-codex），缺源图时跳过该张、保留已有产物。
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(HERE, "portrait_svg"))
import figures  # noqa: E402

OUT_DIR = os.path.join(ROOT, "assets", "portraits")
CODEX = os.environ.get("NK1_CODEX_PORTRAITS", "/Users/snowchan27/tmp/nk1-codex/assets/portraits")
MAIN = os.path.join(ROOT, "assets")
FONT_TITLE = os.path.join(ROOT, "assets", "fonts", "MaShanZheng-Regular.ttf")
FONT_BODY = os.path.join(ROOT, "assets", "fonts", "LXGWWenKai-Medium.ttf")
W, H = 512, 640

# 色板（美术规范）
JIAOMO = (13, 11, 9)
MO = (26, 22, 18)
XUANZHI = (233, 220, 192)
JIUJUAN = (205, 184, 143)
NIJIN = (201, 161, 74)
ZHUSHA = (176, 48, 42)
ZHESHI = (138, 90, 43)


# ───────────────────────── numpy 小工具 ─────────────────────────
def f32(im):
    return np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))


def _box1d(a, r, axis):
    if r < 1:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def box(a, r):
    return _box1d(_box1d(a, r, 0), r, 1)


def gblur(a, sigma):
    """三次盒滤波近似高斯。"""
    if sigma <= 0:
        return a
    r = max(1, int(round(np.sqrt(12 * sigma * sigma / 3 + 1) / 2)))
    out = a
    for _ in range(3):
        out = box(out, r)
    return out


def masked_blur(img, m, sigma):
    """只用 m=1 处的像素做模糊（前景色不会渗进背景）。"""
    m3 = m[..., None] if img.ndim == 3 else m
    num = gblur(img * m3, sigma)
    den = gblur(m3, sigma)
    return num / np.maximum(den, 1e-4)


def poly_mask(points, size=(W, H), feather=2.0, ss=4):
    w, h = size
    im = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(im).polygon([(x * ss, y * ss) for x, y in points], fill=255)
    im = im.resize((w, h), Image.LANCZOS)
    m = np.asarray(im, dtype=np.float32) / 255.0
    return np.clip(gblur(m, feather), 0, 1) if feather > 0 else m


def luma(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def rgb2hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(-1)
    mn = a.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rr = nz & (mx == r)
    gg = nz & (mx == g) & ~rr
    bb = nz & ~rr & ~gg
    h[rr] = ((g - b)[rr] / d[rr]) % 6
    h[gg] = (b - r)[gg] / d[gg] + 2
    h[bb] = (r - g)[bb] / d[bb] + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def grad_map(t, stops):
    """t∈[0,1] → 按 [(pos,(r,g,b)),…] 线性插值的颜色。"""
    pos = np.array([p for p, _ in stops], dtype=np.float32)
    cols = np.array([c for _, c in stops], dtype=np.float32) / 255.0
    out = np.empty(t.shape + (3,), dtype=np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, cols[:, ch])
    return out


def inpaint(img, m, iters=400):
    """调和插值补洞：m=1 为待补区。先用大半径归一化卷积给初值，再 Jacobi 迭代。"""
    keep = 1.0 - m
    out = img.copy()
    init = masked_blur(img, keep, 12)
    out[m > 0.5] = init[m > 0.5]
    hole = m > 0.5
    for _ in range(iters):
        p = np.pad(out, ((1, 1), (1, 1), (0, 0)), mode="edge")
        avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) * 0.25
        out[hole] = avg[hole]
    return out


def add_grain(img, m, amount, seed):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, img.shape[:2]).astype(np.float32)
    n = n - gblur(n, 2)
    return img + (n * amount * m)[..., None]


def dilate(m, r):
    im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.MaxFilter(2 * r + 1)), dtype=np.float32) / 255.0


def erode(m, r):
    im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.MinFilter(2 * r + 1)), dtype=np.float32) / 255.0


def kuwahara(img, r):
    """高斯加权的 Kuwahara 平滑：四个偏移窗口中取亮度方差最小者的均值，数码硬线→厚涂色块。"""
    lum = luma(img)
    sig = max(1.0, r * 0.6)
    mean_c = np.stack([gblur(img[..., c], sig) for c in range(3)], -1)
    mean_l = gblur(lum, sig)
    var_l = gblur(lum * lum, sig) - mean_l * mean_l
    means, vars_ = [], []
    for dy, dx in ((-r, -r), (-r, r), (r, -r), (r, r), (0, 0)):
        means.append(np.roll(mean_c, (dy, dx), axis=(0, 1)))
        vars_.append(np.roll(var_l, (dy, dx), axis=(0, 1)))
    wts = np.stack([1.0 / (v + 1e-4) ** 2 for v in vars_], 0)
    wts /= wts.sum(0, keepdims=True)
    out = np.zeros_like(img)
    for i in range(len(means)):
        out += means[i] * wts[i][..., None]
    return out


def warm_grade(img, lift=0.0, warmth=0.04, gamma=1.0):
    out = np.clip(img, 0, 1) ** gamma
    out = out * (1 - lift) + lift
    out[..., 0] *= 1 + warmth
    out[..., 2] *= 1 - warmth * 1.2
    return np.clip(out, 0, 1)


def fit_4x5(im, box_):
    return im.crop(box_).resize((W, H), Image.LANCZOS)


def matte(img, poly, band=0, choke=0):
    """手描轮廓抠像：轮廓（逐点对着 16px 网格放大图描，误差约 2px）超采样栅格化，向内收 0.6px、
    羽化 1px。试过颜色投影法（α=(I−B)·(F−B)/|F−B|²），樱花背景明暗双峰，边上反而出噪点，弃用。
    band>0 时把边带内的像素向内侧前景色收拢一点，压掉残留的一圈原背景色。"""
    p = poly_mask(poly, feather=0.0)
    if choke > 0:
        p = erode((p > 0.5).astype(np.float32), choke)
    alpha = np.clip(gblur(p, 1.0) * 1.12 - 0.12, 0, 1)
    fe = img
    if band > 0:
        fg = erode((p > 0.5).astype(np.float32), band)
        F = masked_blur(img, fg, band * 1.2)
        edge = np.clip(p - fg, 0, 1)[..., None]
        fe = img * (1 - edge * 0.35) + F * edge * 0.35
    return alpha, fe


# ───────────────────────── painted：逐张修瑕 ─────────────────────────
def fix_merchant_lin(src):
    """灯笼下字「処」、左罐「銘酒」、右竖招牌「千客萬来」是日文用字，300px 下可读——补成素面。
    灯笼上字「酒」是正经宋式酒招，保留。"""
    a = f32(src)
    lum = luma(a)
    local = gblur(lum, 6)
    out = a.copy()
    # (框, 暗笔阈值, 纹理方向)：灯笼竹篾是横纹，招牌木纹是竖纹，陶罐无向
    for (x0, y0, x1, y1), k, grain in (((14, 76, 100, 132), 0.80, "row"),    # 処
                                       ((8, 214, 62, 282), 0.82, None),      # 銘酒
                                       ((402, 110, 460, 284), 0.84, "col")):  # 千客萬来
        reg = np.zeros(lum.shape, np.float32)
        reg[y0:y1, x0:x1] = 1
        m = reg * (lum < local * k)
        m = dilate(m, 2) * reg
        hole = (m > 0.5).astype(np.float32)
        py0, py1, px0, px1 = max(0, y0 - 24), min(H, y1 + 24), max(0, x0 - 24), min(W, x1 + 24)
        filled = out.copy()
        filled[py0:py1, px0:px1] = inpaint(out[py0:py1, px0:px1], hole[py0:py1, px0:px1], iters=600)
        if grain:
            # 从同一行（或列）未被遮住的像素里取高频纹理，补回平涂区
            hp = lum - gblur(lum, 2.5)
            sub_hp = hp[y0:y1, x0:x1]
            keep = hole[y0:y1, x0:x1] < 0.5
            ax = 1 if grain == "row" else 0
            cnt = keep.sum(axis=ax)
            prof = np.where(cnt > 0, (sub_hp * keep).sum(axis=ax) / np.maximum(cnt, 1), 0).astype(np.float32)
            det = np.zeros(lum.shape, np.float32)
            if grain == "row":
                det[y0:y1, x0:x1] = prof[:, None]
            else:
                det[y0:y1, x0:x1] = prof[None, :]
            filled = filled + det[..., None] * 0.9
        filled = add_grain(filled, hole, 0.008, x0 + y0)
        mm = gblur(hole, 0.8)
        out = out * (1 - mm[..., None]) + filled * mm[..., None]
    return to_img(out)


def fix_pilot_ana(src):
    """sprite_ana：AI 把「紫黑」画成紫色。按亮度重映射到日晒古铜渐变（不再做色相旋转，避免青绿斑），
    再做 Kuwahara 厚涂化并套暖调，贴近 Codex 立绘的油画笔触；去画框、4:5 以人物为中心裁切。"""
    a = f32(src)
    h, s, v = rgb2hsv(a)
    skin = ((h >= 262) & (h <= 350) & (s > 0.10) & (v > 0.03)).astype(np.float32)
    # 闭运算填水珠高光与青色油光，再去掉衣服上零星的紫点
    skin = erode(dilate(skin, 6), 6)
    skin = dilate(erode(skin, 2), 2)
    # 皮肤邻域内低饱和的青绿/灰紫高光也并入
    near = dilate(skin, 4)
    cool = (near > 0.5) & (((h >= 60) & (h <= 262)) | (s < 0.12))
    skin = np.maximum(skin, cool.astype(np.float32) * (luma(a) > 0.10))
    skin = np.clip(gblur(skin, 1.5), 0, 1)
    # 红缠头暗部有品红像素，排除
    band = poly_mask([(385, 200), (395, 120), (440, 80), (470, 70), (560, 72), (620, 100), (630, 150),
                      (640, 210), (665, 320), (665, 400), (618, 400), (616, 300), (612, 230), (590, 180),
                      (560, 162), (488, 150), (424, 163), (402, 200)], size=(a.shape[1], a.shape[0]), feather=1.5)
    skin = skin * (1 - band)
    t = np.clip(v * 0.62 + a.mean(-1) * 0.38, 0, 1)
    t = np.clip((t - 0.02) / 0.80, 0, 1) ** 0.95
    bronze = grad_map(t, [(0.00, (16, 9, 6)), (0.14, (42, 25, 15)), (0.30, (78, 47, 28)),
                          (0.48, (116, 75, 44)), (0.66, (156, 106, 66)), (0.84, (198, 150, 104)),
                          (1.00, (236, 212, 180))])
    a = a * (1 - skin[..., None]) + bronze * skin[..., None]
    a = kuwahara(a, 2)
    a = warm_grade(a, lift=0.012, warmth=0.035, gamma=1.03)
    im = to_img(a)
    return fit_4x5(im, (146, 14, 146 + 797, 14 + 996))


def fix_chen_servant(src):
    """sprite_servant：去木画框（内缘 x≈40、y≈40、下缘 y≈976），4:5 以跪姿人物为中心裁切。"""
    return fit_4x5(src, (56, 44, 56 + 744, 44 + 930))


MONK_FIG = [(0, 640), (0, 478), (6, 462), (12, 446), (18, 430), (24, 410), (30, 392), (38, 372), (44, 356),
            (50, 340), (56, 326), (64, 312), (76, 300), (92, 290), (112, 281), (132, 274), (156, 267), (176, 261),
            (196, 254), (209, 250), (209, 227), (207, 207), (209, 187), (207, 170), (207, 153), (209, 137),
            (211, 120), (216, 103), (219, 87), (226, 73), (239, 57), (256, 47), (277, 38), (300, 35), (323, 38),
            (343, 50), (360, 67), (370, 83), (373, 103), (372, 120), (371, 137), (378, 142), (382, 160),
            (378, 180), (371, 194), (356, 206), (346, 210), (342, 222), (350, 238), (360, 254), (372, 266),
            (386, 272), (400, 280), (416, 290), (432, 300), (446, 310), (460, 319), (474, 330), (488, 346),
            (500, 362), (508, 376), (512, 384), (512, 640)]


def fix_monk_jinghai(src):
    """Codex「博多老僧」：樱花、和式寺檐、石灯笼。抠出人物（颜色投影去污），背景就地重画：
    景深虚化到读不出檐式，樱粉褪成暮色赭金、整体压暗，与全套暖烛光同调；袈裟两枚家纹式团纹
    用上下相邻的织金缘平移盖掉，衣上飘落的花瓣补掉。"""
    a = f32(src)
    alpha, fe = matte(a, MONK_FIG, band=3)
    bgm = np.clip(1 - dilate(alpha, 2), 0, 1)
    b = masked_blur(a, bgm, 9.0)
    t = luma(b)
    dusk = grad_map(np.clip(t * 1.05, 0, 1), [(0.00, (20, 14, 10)), (0.30, (70, 48, 30)), (0.55, (132, 94, 56)),
                                              (0.75, (186, 140, 86)), (0.92, (222, 184, 124)), (1.0, (236, 206, 150))])
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    xx = np.linspace(-1, 1, W, dtype=np.float32)[None, :]
    light = np.clip(0.86 - 0.30 * yy - 0.10 * np.abs(xx), 0.3, 1)
    b = dusk * light[..., None]
    b = b + (_noise((H, W), 40, 5)[..., None] - 0.5) * 0.04
    # 家纹式团纹：沿织金缘方向从上方 64px 处平移覆盖
    fe2 = fe.copy()
    for cx, cy, r, dx, dy in ((212, 427, 27, -6, -64), (393, 410, 26, 6, -62)):
        yy2, xx2 = np.mgrid[0:H, 0:W]
        dist = np.sqrt((xx2 - cx) ** 2 + (yy2 - cy) ** 2)
        cm = np.clip((r + 3 - dist) / 5, 0, 1).astype(np.float32)[..., None]
        shifted = np.roll(fe, (-dy, -dx), axis=(0, 1))
        fe2 = fe2 * (1 - cm) + shifted * cm
    # 衣上两片飘落的樱瓣（位置实测），补掉
    yy3, xx3 = np.mgrid[0:H, 0:W]
    petal = np.zeros((H, W), np.float32)
    for px, py, pr in ((67, 432, 9), (21, 397, 8)):
        petal = np.maximum(petal, (np.sqrt((xx3 - px) ** 2 + (yy3 - py) ** 2) < pr).astype(np.float32))
    petal = gblur(petal, 1.5)
    fe2 = fe2 * (1 - petal[..., None]) + np.roll(fe2, (24, -4), axis=(0, 1)) * petal[..., None]
    out = fe2 * alpha[..., None] + b * (1 - alpha[..., None])
    return to_img(warm_grade(out, warmth=0.02))


def fix_customs_official(src):
    """胸前明式补子（凤纹方补）是开局第一眼就看到的硬伤：用其上方同列的皂色暗云纹袍面平移平铺覆盖
    （接缝处交叉淡化），保留右侧货账；左胸一列清式盘扣用左侧袍面平移盖掉。
    立领与短翅乌纱属画作本体，留待重绘（见 portrait_note）。"""
    a = f32(src)
    # 1) 盘扣：x≈138–166 一列，用往左 30px 的袍面覆盖
    clean = a.copy()
    shifted = np.roll(a, 30, axis=1)
    mk = poly_mask([(134, 438), (170, 438), (170, 640), (134, 640)], feather=3.0)
    clean = clean * (1 - mk[..., None]) + shifted * mk[..., None]
    # 2) 补子：以 438–503 行袍面按行周期平铺（周期内末 14 行向上一周期交叉淡化，保证无缝），
    #    袍襟竖线位置不变
    per, ov, lo, hi = 66, 14, 438, 504
    tgt = clean.copy()
    for y in range(hi - ov, hi):               # 顶边：原图行向「上一周期」过渡，接上平铺
        w = (y - (hi - ov) + 1) / float(ov)
        tgt[y] = clean[y] * (1 - w) + clean[y - per] * w
    for y in range(hi, H):
        s = lo + (y - lo) % per
        row = clean[s]
        if s >= hi - ov:
            w = (s - (hi - ov) + 1) / float(ov)
            row = row * (1 - w) + clean[s - per] * w
        tgt[y] = row
    yy = np.linspace(0, 1, H - hi, dtype=np.float32)[:, None, None]
    tgt[hi:] = tgt[hi:] * (0.97 - 0.10 * yy)
    m = poly_mask([(136, 480), (360, 480), (360, 546), (316, 546), (312, 640), (136, 640)], feather=3.0)
    m[:hi - ov] = 0
    m = gblur(m, 1.0)
    out = clean * (1 - m[..., None]) + tgt * m[..., None]
    out = add_grain(out, m, 0.01, 11)
    return to_img(out)


SHI_FIG = [(128, 640), (133, 610), (139, 580), (146, 550), (153, 520), (157, 490), (160, 465), (163, 440),
           (168, 420), (176, 405), (188, 395), (206, 385), (221, 375), (225, 360), (226, 330), (225, 300),
           (222, 280), (217, 265), (213, 252), (211, 234), (209, 212), (205, 196), (195, 180), (191, 162),
           (190, 144), (191, 126), (197, 112), (206, 98), (216, 89), (231, 84), (249, 80), (259, 76), (270, 71),
           (288, 69), (306, 71), (324, 76), (341, 84), (356, 94), (370, 109), (384, 126), (395, 144), (402, 162),
           (406, 180), (406, 196), (403, 206), (400, 214), (397, 223), (390, 233), (373, 247), (372, 260),
           (373, 273), (380, 283), (383, 293), (385, 307), (385, 320), (390, 327), (400, 333), (410, 343),
           (423, 353), (437, 360), (453, 367), (470, 377), (483, 387), (497, 400), (510, 413), (512, 414),
           (512, 640)]


def fix_shi_naowei(src):
    """全套唯一的正午蓝天碧海：抠出人物，背景按亮度映射到暮色（蓝→赭金，参照 chen_laodao 夕照）
    并压暗约 30%；右侧欧式绳梯索具与雕花舷栏加重虚化到读不出形制。"""
    a = f32(src)
    alpha, fe = matte(a, SHI_FIG, band=3, choke=3)
    bgm = np.clip(1 - dilate(alpha, 2), 0, 1)
    b1 = masked_blur(a, bgm, 2.2)
    b2 = masked_blur(a, bgm, 7.0)
    xx = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    rig = np.clip((xx - 0.66) / 0.12, 0, 1)[..., None] * np.ones((H, 1, 1), np.float32)
    b = b1 * (1 - rig) + b2 * rig
    t = luma(b)
    dusk = grad_map(np.clip(t * 1.08, 0, 1), [(0.00, (16, 12, 12)), (0.22, (48, 34, 28)), (0.42, (96, 64, 38)),
                                              (0.62, (156, 108, 58)), (0.80, (208, 158, 90)), (1.00, (242, 212, 150))])
    graded = dusk * 0.88 + t[..., None] * np.array([0.12, 0.10, 0.08], np.float32)
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    graded = graded * (0.76 - 0.14 * yy)[..., None]
    # 左侧海平线一团夕照，给暮色一个光源
    yy2, xx2 = np.mgrid[0:H, 0:W].astype(np.float32)
    glow = np.exp(-(((xx2 - 70) / 170) ** 2 + ((yy2 - 285) / 90) ** 2))
    graded = graded + glow[..., None] * np.array([0.20, 0.12, 0.04], np.float32)
    # 头巾上的饱和蓝条纹收一收，与暮色同调
    h, s, v = rgb2hsv(fe)
    blue = ((h > 185) & (h < 250) & (s > 0.18)).astype(np.float32)
    blue = gblur(blue, 1.0)
    gray = luma(fe)[..., None] * np.array([1.0, 0.97, 0.93], dtype=np.float32)
    fe = fe * (1 - blue[..., None] * 0.45) + gray * blue[..., None] * 0.45
    out = fe * alpha[..., None] + graded * (1 - alpha[..., None])
    return to_img(warm_grade(out, warmth=0.03))


# id → (源图, 处理函数)。源图 codex: 走 CODEX 目录，main: 走仓库 assets/
PAINTED = {
    "chen_wenlong": ("codex:portrait_chen_wenlong.png", None),
    "merchant_lin": ("codex:portrait_mingzhou_merchant.png", fix_merchant_lin),
    "pilot_ana": ("main:sprite_ana.png", fix_pilot_ana),
    "monk_jinghai": ("codex:portrait_old_monk.png", fix_monk_jinghai),
    "customs_official": ("codex:portrait_customs_official.png", fix_customs_official),
    "xinghua_messenger": ("codex:portrait_linan_passerby.png", None),
    "lin_hua": ("codex:portrait_patrol_soldier.png", None),
    "huang_quan": ("codex:portrait_jiaozhi_temple_keeper.png", None),
    "veteran_son": ("codex:portrait_tavern_guest.png", None),
    "chen_servant": ("main:sprite_servant.png", fix_chen_servant),
    "cai_qixing": ("codex:portrait_broken_eyebrow.png", None),
    "chen_laodao": ("codex:portrait_jiaozhi_old_merchant.png", None),
    "he_wenzhou": ("codex:portrait_one_finger_sailor.png", None),
    "shi_naowei": ("codex:portrait_abbas.png", fix_shi_naowei),
    "zhou_suanchou": ("codex:portrait_inn_scholar.png", None),
    "huang_zhangfang": ("codex:portrait_innkeeper.png", None),
    "ye_shibo": ("codex:portrait_jeju_official.png", None),
    "wen_tianxiang": ("codex:portrait_jia_disciple.png", None),
}


def src_path(spec):
    kind, name = spec.split(":", 1)
    return os.path.join(CODEX if kind == "codex" else MAIN, name)


def build_painted(cid, spec, fn):
    p = src_path(spec)
    if not os.path.isfile(p):
        print("  [skip] %s 源图不在：%s" % (cid, p))
        return None
    src = Image.open(p).convert("RGB")
    im = fn(src) if fn else src
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return im


# ───────────────────────── placeholder：绢本墨影兜底卡 ─────────────────────────
def _noise(shape, scale, seed):
    """多倍频值噪声，0..1。"""
    rng = np.random.default_rng(seed)
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(5):
        s = max(2, int(scale / (2 ** o)))
        gh, gw = h // s + 2, w // s + 2
        g = rng.random((gh, gw)).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((gw * s, gh * s), Image.BICUBIC)
        out += np.asarray(im, np.float32)[:h, :w] / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def silk_ground(seed, scale=2):
    """旧绢底：经纬丝纹 + 低频霉斑 + 赭石晕边 + 零星水渍。"""
    w, h = W * scale, H * scale
    rng = np.random.default_rng(seed)
    base = np.ones((h, w, 3), np.float32) * (np.array(JIUJUAN, np.float32) / 255.0)
    # 经纬：逐行/逐列细噪
    rows = rng.normal(0, 1, (h, 1)).astype(np.float32)
    cols = rng.normal(0, 1, (1, w)).astype(np.float32)
    weave = rows * 0.010 + cols * 0.008
    weave += (rng.normal(0, 1, (h, w)).astype(np.float32)) * 0.012
    # 低频：大片深浅不匀（绢面陈旧）
    lf = _noise((h, w), 260 * scale / 2, seed + 1) - 0.5
    mf = _noise((h, w), 60 * scale / 2, seed + 2) - 0.5
    shade = 1.0 + lf * 0.16 + mf * 0.06 + weave
    img = base * shade[..., None]
    # 宣纸色提亮的「圆光」由调用方另画；这里压赭石晕边
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = (xx / w - 0.5) * 2
    dy = (yy / h - 0.5) * 2
    vig = np.clip((np.sqrt(dx ** 2 * 0.9 + dy ** 2 * 0.75) - 0.55) / 0.75, 0, 1) ** 1.6
    zhe = np.array(ZHESHI, np.float32) / 255.0
    img = img * (1 - vig[..., None] * 0.55) + (img * zhe * 1.1) * vig[..., None] * 0.55
    # 霉点
    for _ in range(int(rng.integers(5, 11))):
        cx, cy = rng.random() * w, rng.random() * h
        r = (2 + rng.random() * 7) * scale
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        sp = np.clip(1 - d / r, 0, 1) ** 2 * (0.10 + rng.random() * 0.12)
        img = img * (1 - sp[..., None]) + img * zhe[None, None] * sp[..., None]
    return np.clip(img, 0, 1)


def render_svg(svg_text, w, h):
    exe = shutil.which("rsvg-convert") or "/opt/homebrew/bin/rsvg-convert"
    with tempfile.TemporaryDirectory() as td:
        sp = os.path.join(td, "f.svg")
        pp = os.path.join(td, "f.png")
        with open(sp, "w", encoding="utf-8") as f:
            f.write(svg_text)
        subprocess.run([exe, "-w", str(w), "-h", str(h), "-o", pp, sp], check=True)
        return np.asarray(Image.open(pp).convert("RGBA"), np.float32) / 255.0


def ink_layer(rgba, seed, scale):
    """把 SVG 剪影层变成墨：边缘积墨、内部浓淡随机、边缘轻微毛涩。
    SVG 约定：R 通道=墨浓度（255 为焦墨，128 为淡墨面部），A=覆盖，G 通道>0 的描线为留白（绢色）。"""
    a = rgba[..., 3]
    dens = rgba[..., 0]
    white = rgba[..., 1] * a
    pig = rgba[..., 2] * a
    h, w = a.shape
    # 毛涩边：对 alpha 加高频噪声后重新阈值
    n = _noise((h, w), 6 * scale, seed + 7) - 0.5
    soft = gblur(a, 1.2 * scale)
    a2 = np.clip((soft + n * 0.35 - 0.5) * 3.0 + 0.5, 0, 1)
    a2 = np.minimum(a2, np.clip(soft * 1.6, 0, 1))
    # 积墨：边内侧更浓
    inner = gblur(a, 7 * scale)
    edge = np.clip(a - inner, 0, 1)
    lf = _noise((h, w), 90 * scale, seed + 8)
    ink = np.clip(dens * (0.80 + 0.14 * lf) + edge * 0.22, 0, 1)
    return a2, ink, white, pig


def seal_image(text, size, seed):
    """朱砂阴文印：朱底、宣纸色字、边缘残缺、印泥不匀。返回 RGBA float。"""
    sw, sh = size
    s = 4
    im = Image.new("RGBA", (sw * s, sh * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, sw * s - 1, sh * s - 1], fill=ZHUSHA + (255,))
    n = len(text)
    font_px = int(min(sw * 0.78, sh * 0.86 / n) * s)
    total = font_px * n
    y = (sh * s - total) / 2
    for ch in text:
        font = ImageFont.truetype(glyph_font(FONT_TITLE, ch)[0], font_px)
        bb = d.textbbox((0, 0), ch, font=font)
        cw = bb[2] - bb[0]
        d.text(((sw * s - cw) / 2 - bb[0], y - bb[1] + (font_px - (bb[3] - bb[1])) / 2), ch,
               font=font, fill=XUANZHI + (255,))
        y += font_px
    im = im.resize((sw, sh), Image.LANCZOS)
    arr = np.asarray(im, np.float32) / 255.0
    rng = np.random.default_rng(seed)
    n1 = _noise((sh, sw), 5, seed)
    # 印泥不匀：字外的朱色随机变淡，边缘残缺
    red = (arr[..., 0] > arr[..., 1] + 0.2).astype(np.float32)
    fade = np.clip((n1 - 0.18) * 3, 0, 1)
    arr[..., 3] = arr[..., 3] * np.where(red > 0.5, 0.35 + 0.65 * fade, 1.0)
    yy, xx = np.mgrid[0:sh, 0:sw]
    border = np.minimum.reduce([xx, yy, sw - 1 - xx, sh - 1 - yy]).astype(np.float32)
    chip = (border < 2.5) & (rng.random((sh, sw)) < 0.35)
    arr[..., 3][chip] *= 0.2
    arr[..., 3] *= 0.92
    return arr


_CMAP = {}
_FONT_SRC = os.path.expanduser("~/tmp/nk1-art-work/fonts_src")


def _has(path, ch):
    from fontTools.ttLib import TTFont
    if path not in _CMAP:
        _CMAP[path] = set(TTFont(path).getBestCmap().keys()) if os.path.isfile(path) else set()
    return ord(ch) in _CMAP[path]


def glyph_font(path, ch):
    """逐字选字体：马善政缺的僻字（璥、溍、爚、恮……）回落霞鹜文楷，仓库子集缺则再回落 fonts_src 原字体。
    返回 (字体路径, 是否回落)。产物是烘焙好的 PNG，不依赖运行时字体。"""
    chain = [path]
    if path == FONT_TITLE:
        chain += [os.path.join(_FONT_SRC, os.path.basename(FONT_TITLE)), FONT_BODY]
    chain.append(os.path.join(_FONT_SRC, os.path.basename(FONT_BODY)))
    for p in chain:
        if _has(p, ch):
            return p, p != path and os.path.basename(p) != os.path.basename(path)
    raise SystemExit("所有字体都缺「%s」(U+%04X)" % (ch, ord(ch)))


def draw_vertical(img, text, font_path, px, x_center, y_top, color, spacing=1.0):
    d = ImageDraw.Draw(img)
    y = y_top
    for ch in text:
        fp, fell = glyph_font(font_path, ch)
        font = ImageFont.truetype(fp, px)
        sw = max(1, px // 40) if fell else 0      # 文楷比马善政细，回落字加一点笔重
        bb = d.textbbox((0, 0), ch, font=font, stroke_width=sw)
        cw = bb[2] - bb[0]
        d.text((x_center - cw / 2 - bb[0], y - bb[1] + (px - (bb[3] - bb[1])) / 2), ch, font=font, fill=color,
               stroke_width=sw, stroke_fill=color)
        y += px * spacing
    return y


def vertical_title(t):
    """竖排身份：括号与间隔号换成竖排可读的「・」。"""
    return t.replace("（", "・").replace("）", "").replace("·", "・")


SEAL_TEXT = {"yuhu_chen": "陈氏", "song_court": "宋廷", "quanxing": "权幸", "mongol_yuan": "蒙元",
             "fanfang": "蕃坊", "quanzhou_merchants": "海商", "seafarers": "海上", "temple": "寺院",
             "local_officials": "吏员", "townsfolk": "市井", "foreign": "异国"}


def build_card(c, cast):
    scale = 2
    seed = sum(ord(ch) * (i + 1) for i, ch in enumerate(c["id"])) % 100000
    ground = silk_ground(seed, scale)
    hh, ww = ground.shape[:2]
    spec = cast[c["id"]]
    # 1) 背景意象（淡墨）与圆光（宣纸色）
    back_svg = figures.backdrop_svg(spec, W, H)
    back = render_svg(back_svg, ww, hh)
    xz = np.array(XUANZHI, np.float32) / 255.0
    mo = np.array(MO, np.float32) / 255.0
    glow = back[..., 1] * back[..., 3]
    img = ground * (1 - glow[..., None] * 0.55) + (xz * (0.97 + 0.05 * _noise((hh, ww), 40, seed + 3))[..., None]) * glow[..., None] * 0.55
    wash = back[..., 0] * back[..., 3]
    wash = gblur(wash, 2.5 * scale) * (0.75 + 0.5 * _noise((hh, ww), 50, seed + 4))
    img = img * (1 - wash[..., None]) + (img * mo * 2.2) * wash[..., None]
    # 2) 人物剪影
    fig = render_svg(figures.figure_svg(spec, W, H), ww, hh)
    a2, ink, white, pig = ink_layer(fig, seed, scale)
    # 下半身淡出：墨色自腰下渐枯，飞白散入绢底（人物画常见收法）
    yy = np.linspace(0, 1, hh, dtype=np.float32)[:, None]
    # 竖向枯笔丝：x 向高频、y 向拉长的噪声，既用于墨色深浅，也用于收笔飞白
    st = np.asarray(Image.fromarray((_noise((hh // 30 + 2, ww // 2 + 2), 2, seed + 12) * 255).astype(np.uint8))
                    .resize((ww, hh), Image.BICUBIC), np.float32) / 255.0
    st2 = np.asarray(Image.fromarray((_noise((hh // 8 + 2, ww // 6 + 2), 3, seed + 13) * 255).astype(np.uint8))
                     .resize((ww, hh), Image.BICUBIC), np.float32) / 255.0
    fn = _noise((hh, ww), 60 * scale, seed + 11)
    fg_ = _noise((hh, ww), 4 * scale, seed + 14)
    fade = np.clip((1.02 - yy) / 0.27 + (fn - 0.5) * 0.7 + (fg_ - 0.5) * 0.35 + (st - 0.5) * 0.25, 0, 1)
    fade = np.clip((fade - 0.1) / 0.75, 0, 1) ** 1.2
    a2 = a2 * fade
    white = white * fade
    pig = pig * fade
    ink = np.clip(ink * (0.9 + 0.12 * st) * (0.95 + 0.05 * st2), 0, 1)
    jiao = np.array(JIAOMO, np.float32) / 255.0
    # 墨色 = 绢底 × (1-ink) + 焦墨 × ink（透出绢纹）
    inked = img * (1 - ink[..., None]) + jiao * ink[..., None]
    img = img * (1 - a2[..., None]) + inked * a2[..., None]
    # 留白描线：回到绢色（略暗），带一点飞白
    fb = np.clip(_noise((hh, ww), 3 * scale, seed + 9) * 1.4 - 0.1, 0, 1)
    wl = np.clip(white * (0.55 + 0.45 * fb), 0, 1) * 0.62
    img = img * (1 - wl[..., None]) + (ground * 0.92) * wl[..., None]
    # 粉彩：面与手敷一层浅暖粉，透绢纹
    # 粉彩通道值：255 = 浅暖粉（士人面、手、象笏、纸），110 = 日晒古铜（海上人）
    fen = np.array((236, 214, 180), np.float32) / 255.0
    bronze = np.array((150, 104, 68), np.float32) / 255.0
    amt = np.clip(pig * 4.0, 0, 1)
    val = np.clip((pig / np.maximum(amt, 1e-3) - 0.43) / 0.57, 0, 1)[..., None]
    col = bronze * (1 - val) + fen * val
    pg = amt[..., None] * 0.8
    img = img * (1 - pg) + (col * (0.9 + 0.1 * ground / ground.mean())) * pg
    out = to_img(img).resize((W, H), Image.LANCZOS)
    # 3) 题签：竖排姓名（马善政）+ 身份（文楷）
    name = c["name"]
    npx = 66 if len(name) <= 3 else (60 if len(name) == 4 else 52)
    x_name = 462
    y0 = 58
    y_end = draw_vertical(out, name, FONT_TITLE, npx, x_name, y0, JIAOMO, spacing=1.04)
    title = vertical_title(c["title"])
    tpx = 26
    draw_vertical(out, title, FONT_BODY, tpx, x_name - npx / 2 - 22, y0 + 8, MO, spacing=1.06)
    # 4) 朱砂印（阵营）
    st = SEAL_TEXT.get(c["faction"], "")
    if st:
        seal = seal_image(st, (44, 84), seed)
        sy = int(y_end + 12)
        sx = int(x_name - 22)
        base = f32(out)
        sh_, sw_ = seal.shape[:2]
        reg = base[sy:sy + sh_, sx:sx + sw_]
        al = seal[..., 3:4]
        # 印泥叠在绢上：乘法感
        reg[:] = reg * (1 - al) + (seal[..., :3] * (0.72 + 0.28 * reg)) * al
        out = to_img(base)
    return out


# ───────────────────────── 主流程 ─────────────────────────
def load_chars():
    with open(os.path.join(ROOT, "data", "characters.json"), encoding="utf-8") as f:
        return json.load(f)["characters"]


def load_cast():
    with open(os.path.join(HERE, "portrait_svg", "cast.json"), encoding="utf-8") as f:
        return json.load(f)


def contact_sheet(ids, path, cols=10, tw=128):
    th = tw * 5 // 4
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + 18)), (20, 18, 16))
    font = ImageFont.truetype(FONT_BODY, 13)
    d = ImageDraw.Draw(sheet)
    for i, cid in enumerate(ids):
        p = os.path.join(OUT_DIR, cid + ".png")
        if not os.path.isfile(p):
            continue
        im = Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS)
        x, y = (i % cols) * tw, (i // cols) * (th + 18)
        sheet.paste(im, (x, y))
        d.text((x + 3, y + th + 1), "%d %s" % (i + 1, cid), fill=(230, 220, 200), font=font)
    sheet.save(path, quality=88)
    print("sheet →", path)


def main(argv):
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    do_p = "--cards-only" not in argv
    do_c = "--painted-only" not in argv
    chars = load_chars()
    cast = load_cast()
    os.makedirs(OUT_DIR, exist_ok=True)
    n_p = n_c = 0
    for c in chars:
        cid = c["id"]
        if only and cid not in only:
            continue
        dst = os.path.join(OUT_DIR, cid + ".png")
        if c["portrait_status"] == "painted":
            if not do_p:
                continue
            if cid not in PAINTED:
                # 新出的油画（portrait_src=gen:…）直接放在 assets/portraits/，脚本不碰它
                if not os.path.isfile(dst):
                    raise SystemExit("painted 人物 %s 既不在 PAINTED 表、仓库里也没有 %s" % (cid, dst))
                print("  %-18s keep（新油画，保留现有文件）" % cid)
                continue
            spec, fn = PAINTED[cid]
            im = build_painted(cid, spec, fn)
            if im is None:
                continue
            im.save(dst, optimize=True)
            n_p += 1
        else:
            if not do_c:
                continue
            if cid not in cast:
                raise SystemExit("placeholder 人物 %s 不在 portrait_svg/cast.json" % cid)
            # 兜底卡是单色调，256 色调色板 + 误差扩散：体积减半，平均误差 <1/255
            card = build_card(c, cast).quantize(colors=256, method=Image.Quantize.MEDIANCUT,
                                                dither=Image.Dither.FLOYDSTEINBERG)
            card.save(dst, optimize=True)
            n_c += 1
        print("  %-18s %s" % (cid, "painted" if c["portrait_status"] == "painted" else "card"))
    print("done: painted %d, cards %d → %s" % (n_p, n_c, OUT_DIR))
    if "--sheet" in argv:
        contact_sheet([c["id"] for c in chars], argv[argv.index("--sheet") + 1])


if __name__ == "__main__":
    main(sys.argv[1:])
