#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""立绘构建：产出 assets/portraits/<人物 id>.png（512×640，与 Codex 立绘同规格）。

两类产物，全部以 data/characters.json 为准：
  1. painted（portrait_status=painted）：从 Codex / main 旧油画按人物逐张修瑕后落地——
     去日文招牌字、阿那紫皮改古铜并做厚涂化、净海换掉樱花和式寺檐、市舶小吏压掉明式补子、
     施那帏蓝天改暮色等，处理逐条写在 PAINTED 表里，可复现。
  2. placeholder：在油画到位前，生成一套同规格「绢本墨影」兜底卡——减笔泼墨（梁楷一路）：人物立在暖光旧绢前，
     焦墨发冠、淡墨加赭石的中间调面（朝向侧受暖侧光、背光侧沉下）、几笔焦墨眉眼，身形三层墨（湿墨底、侧锋大笔、
     焦墨外廓），下缘淡墨山水 / 海浪入雾。游戏用无字版（不烤姓名题签与阵营印，名牌由界面给）；
     带题签版只在 --titled DIR 时另出。部件与墨法见 tools/art/portrait_svg/
     （figures 骨架、heads 冠帽须发、props 持物、scenes 背景、inkbrush 墨法底层、inkcard 合成、cast.json 选角）。

用法（仓库根）：
  python3 tools/art/build_portraits.py                  # 全部
  python3 tools/art/build_portraits.py --only veteran,pilot_ana
  python3 tools/art/build_portraits.py --painted-only | --cards-only
  python3 tools/art/build_portraits.py --sheet /tmp/sheet.jpg   # 另出一张带编号的总览小样
  python3 tools/art/build_portraits.py --cards-only --mix /tmp/mix.jpg   # 人物志网格尺寸混排（104×130）
  python3 tools/art/build_portraits.py --cards-only --titled /tmp/titled  # 另出带题签版（仓库外，单张展示用）
  NK1_INK_S=1 python3 tools/art/build_portraits.py ...          # 1× 快速小样（默认 2× 超采样出成品）
依赖：python3 + Pillow + numpy + fontTools。同一 id 同一结果（随机数全部按 id 取种子）。
Codex 源图在仓库外（nk1-codex），缺源图时跳过该张、保留已有产物。
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(HERE, "portrait_svg"))
import inkbrush  # noqa: E402
import inkcard  # noqa: E402

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


def fix_customs_collar(src):
    """第 2 轮返工（美术 M6）：市舶小吏仍是清式立领（翻领尖）+ 前襟竖缝 + 胸前一排横向盘扣纹。PIL 修图：
    1) 翻领尖、前襟竖缝、盘扣纹整片盖掉：左右两侧同一件袍的暗云纹平移过来（左半取左、右半取右，中间交叉淡化，
       不镜像，免得出万花筒纹），按原图低频明暗重新打光；
    2) 颈根改成宋式圆领：一道 18px 的黑缎领圈贴着颈根走（随头的朝向略歪），领圈上沿露一线白纻护领（约 5px，#d8ccb4），
       下沿一线缎光。宋代公服是圆领（曲领）袍，吏员常服亦多圆领；评审建议的交领右衽要在颈前重画一块皮肤与 V 口，
       本机无出图模型，PIL 硬画出来是一块平涂三角（试过，比原画更出戏），故取改动小、同样去掉清式特征的圆领。
    3) 叠 σ3 噪声匹配画布纹。"""
    a = f32(src)
    out = a.copy()
    lum = luma(a)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # 领圈上沿（颈根）：随头略向画面右转，右侧高、左侧低
    t_x = np.array([170, 195, 230, 262, 300, 330, 356], np.float32)
    t_y = np.array([360, 352, 368, 378, 364, 334, 324], np.float32)
    top = np.interp(xx[0], t_x, t_y)
    top = gblur(top[None, :], 3.0)[0]
    band_w = 18.0
    bot = top + band_w
    # 1) 袍面补片：领下一段（y<470）取右肩同一件袍（右移 150、下移 40，落在肩与右胸的实袍面上），胸前那一列（y≥440）取左胸（x−72）——
    #    右边往下是书、往上是肩线外的底色，左边往上也是底色，各取不越界的一块，上下交叉淡化
    src_r = np.roll(np.roll(a, -150, axis=1), -40, axis=0)
    src_l = np.roll(a, 72, axis=1)
    wl_ = sstep_np(440.0, 480.0, yy)
    fill = src_r * (1 - wl_[..., None]) + src_l * wl_[..., None]
    lo_a = gblur(lum, 20.0)
    lo_f = gblur(luma(fill), 20.0)
    fill = fill * np.clip(lo_a / np.maximum(lo_f, 1e-3), 0.5, 1.7)[..., None]
    under_collar = (xx >= 158) & (xx <= 334) & (yy >= bot[None, :] - 1) & (yy <= 470)
    column = (xx >= 160) & (xx <= 318) & (yy >= 440)
    m = gblur((under_collar | column).astype(np.float32), 2.5)
    book = poly_mask([(318, 540), (512, 520), (512, 640), (300, 640)], feather=2.0)
    m = m * (1 - book)
    out = out * (1 - m[..., None]) + fill * m[..., None]
    # 2) 圆领领圈：黑缎（取补片的纹理起伏），两端淡入两侧原有的立领（颈侧本就是黑缎）
    side = sstep_np(172.0, 190.0, xx) * (1 - sstep_np(336.0, 354.0, xx))
    band = sstep_np(-1.0, 1.0, yy - top[None, :]) * (1 - sstep_np(-1.0, 1.0, yy - bot[None, :])) * side
    fl = luma(fill)
    ftex = np.clip(gblur(fl, 1.2) / max(float(fl.mean()), 1e-3), 0.3, 2.0)[..., None]
    band_col = np.array((0.068, 0.060, 0.054), np.float32) * (0.8 + 0.25 * ftex)
    # 缎面受光：领圈中上段略亮（光从右上来）
    band_col = band_col * (1 + 0.35 * np.exp(-((yy - top[None, :] - 6) / 5.0) ** 2)[..., None] * sstep_np(230, 330, xx)[..., None])
    out = out * (1 - band[..., None]) + band_col * band[..., None]
    # 白纻护领：领圈上沿一线（约 3.5px，压在缎上 α0.72，不是一条亮白贴纸）
    white = np.array((0.847, 0.800, 0.706), np.float32)            # #d8ccb4
    wl = sstep_np(-1.0, 0.3, yy - top[None, :]) * (1 - sstep_np(2.4, 3.8, yy - top[None, :])) * side
    shade = np.clip(0.62 + 0.3 * sstep_np(200, 320, xx), 0.6, 0.95)[..., None]
    out = out * (1 - wl[..., None] * 0.72) + white * shade * (wl[..., None] * 0.72)
    # 下沿缎光一线
    gl = np.exp(-((yy - bot[None, :] + 1.5) / 1.2) ** 2) * side * (1 - book)
    out = out + gl[..., None] * np.array((0.10, 0.085, 0.06), np.float32)
    # 3) 画布纹
    touched = np.clip(m + band, 0, 1)
    out = add_grain(out, touched, 3.0 / 255.0, 57)
    return to_img(out)


def sstep_np(e0, e1, x):
    t = np.clip((np.asarray(x, np.float32) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def fix_customs_official_v2(src):
    return paint_unify(fix_customs_collar(fix_customs_official(src)))


def paint_unify(im, strength=1.0):
    """油画内部画风拉齐（第 2 轮美术 minor 10）：净海、市舶小吏近照片，周算筹偶像脸，阿那同乡卡通大笑，与林阿舶、吴针的厚涂有差。
    统一过一遍：Kuwahara r=3 做笔触（与原图六四开，眼神细节不糊）、色调向港画均值压暖（色相约 35°，两成）、叠一层画布纹 α0.06。"""
    a = f32(im)
    k = kuwahara(a, 3)
    out = a * (1 - 0.6 * strength) + k * (0.6 * strength)
    lum = luma(out)[..., None]
    warm = np.array((1.0, 0.82, 0.60), np.float32)
    warm = warm / float(warm[0] * 0.2126 + warm[1] * 0.7152 + warm[2] * 0.0722)
    out = out * (1 - 0.2 * strength) + lum * warm * (0.2 * strength)
    # 画布纹：细斜纹 + 颗粒（亮部显、暗部收），乘法叠 α0.06
    yy, xx = np.mgrid[0:out.shape[0], 0:out.shape[1]].astype(np.float32)
    weave = 0.5 + 0.25 * np.sin((xx + yy) * 1.9) + 0.25 * np.sin((xx - yy) * 2.3)
    grain = _noise(out.shape[:2], 3, 77)
    canvas_t = (weave * 0.6 + grain * 0.4)[..., None]
    out = out * (1 + 0.06 * strength * (canvas_t - 0.5) * 2 * (0.4 + 0.6 * lum))
    return to_img(np.clip(out, 0, 1))


def fix_monk_jinghai_v2(src):
    return paint_unify(fix_monk_jinghai(src))


def fix_ana_tongxiang_v2(src):
    return paint_unify(fix_ana_tongxiang(src))


def fix_zhou_suanchou(src):
    return paint_unify(src.resize((W, H), Image.LANCZOS) if src.size != (W, H) else src)


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


def _shift_fill(out, mask, dx, dy, grain_seed):
    """用沿 (dx, dy) 平移过来的邻近画面盖住 mask（带原笔触纹理，比扩散补洞自然），边缘 1px 羽化。"""
    src = np.roll(out, (dy, dx), axis=(0, 1))
    mm = gblur(mask, 1.0)[..., None]
    res = out * (1 - mm) + src * mm
    return add_grain(res, mask, 0.006, grain_seed)


def _line_mask(p0, p1, width):
    x0, y0 = p0
    x1, y1 = p1
    n = np.array([y0 - y1, x1 - x0], np.float32)
    n = n / max(1e-6, float(np.hypot(*n))) * width / 2
    return poly_mask([(x0 + n[0], y0 + n[1]), (x1 + n[0], y1 + n[1]), (x1 - n[0], y1 - n[1]),
                      (x0 - n[0], y0 - n[1])], feather=0.6)


def fix_wu_zhen(src):
    """Codex「澎湖渔夫」→ 吴针（竹笠、蓑衣、麻布短褐，与设定形貌一致）。口衔一支长烟杆：烟草明末才入华，
    是硬伤。烟杆沿垂直杆身方向从下方 9px 平移画面盖掉（带胡须 / 云霞原纹理），烟锅与烟缕用右侧海面、
    上方晚霞平移补。"""
    a = f32(src)
    out = a.copy()
    # 杆身两段：近口一段（压在胡须上）取下方 12px 的胡须，远端一段（压在晚霞上）取上方 13px 的云霞
    near = np.maximum(_line_mask((294, 209.5), (326, 222.5), 12.0), _line_mask((288, 206), (300, 212), 7.0))
    far = _line_mask((322, 224.5), (399, 257.5), 15.0) * (1 - near)
    out = _shift_fill(out, near, 5, -12, 31)
    # 远端压在平缓的晚霞上：上方 13px 正好是笠沿暗边，平移会复制出一道线，改用扩散补洞 + 细颗粒
    hole = (far > 0.2).astype(np.float32)
    y0, y1, x0, x1 = 196, 286, 300, 420
    filled = out.copy()
    filled[y0:y1, x0:x1] = inpaint(out[y0:y1, x0:x1], hole[y0:y1, x0:x1], iters=500)
    filled = add_grain(filled, hole, 0.01, 33)
    fm = gblur(far, 0.8)[..., None]
    out = out * (1 - fm) + filled * fm
    bowl = poly_mask([(385, 242), (408, 242), (410, 270), (385, 272)], feather=1.0)
    out = _shift_fill(out, bowl, -24, 0, 32)
    smoke = poly_mask([(384, 222), (410, 222), (410, 244), (384, 244)], feather=4.0)
    out = out * (1 - smoke[..., None] * 0.7) + np.roll(out, (0, 26), axis=(0, 1)) * smoke[..., None] * 0.7
    return to_img(out)


def fix_ana_tongxiang(src):
    """Codex「琉球舵手」→ 阿那同乡（赤膊、靛蓝缠头、贝珠串、络腮胡、槟榔红牙、手持粗陶碗，与形貌逐项对上）。
    背景是全套最亮的正午碧海蓝天：只把画面里偏青蓝、饱和的像素（海、天）与上缘的白云映射到暮色赭金并压暗，
    人物暖色皮肉天然不入选；缠头、飘带、胸前贝珠、腰下布裙这几处本身就是青蓝，用保护区排除。"""
    a = f32(src)
    h, s, v = rgb2hsv(a)
    keep = np.clip(poly_mask([(118, 110), (150, 75), (200, 60), (255, 55), (290, 65), (300, 95), (298, 125),
                              (270, 110), (220, 105), (175, 120), (150, 150), (125, 175), (112, 150)],
                             feather=1.5)                                            # 缠头
                   + poly_mask([(20, 150), (45, 132), (80, 126), (100, 138), (128, 148), (135, 170), (112, 185),
                                (95, 215), (85, 250), (65, 270), (35, 280), (12, 265), (25, 230), (40, 200),
                                (60, 175), (40, 170), (22, 168)], feather=1.5)      # 飘带
                   + poly_mask([(165, 262), (318, 262), (335, 300), (345, 480), (160, 480)], feather=2.0)  # 贝珠
                   + poly_mask([(60, 540), (470, 530), (470, 640), (60, 640)], feather=2.0), 0, 1)  # 腰下
    sea = ((h > 160) & (h < 245) & (s > 0.16) & (v > 0.08)).astype(np.float32)
    # 缠头与飘带的布边会透出亮碧海：保护区里仍把亮青绿像素（布是暗靛紫，色相 >215、明度低）算作海
    bright_sea = ((h > 172) & (h < 216) & (s > 0.40) & (v > 0.50)).astype(np.float32)
    beads = poly_mask([(165, 262), (318, 262), (335, 300), (345, 480), (160, 480)], feather=2.0)
    keep = np.clip(keep - bright_sea * (1 - beads), 0, 1)
    yy = np.mgrid[0:H, 0:W][0].astype(np.float32)
    cloud = ((s < 0.32) & (v > 0.62) & (yy < 150)).astype(np.float32)
    bg = np.clip(gblur(np.maximum(sea, cloud), 1.2) * 1.2, 0, 1) * (1 - keep)
    t = luma(a)
    dusk = grad_map(np.clip(t * 1.02, 0, 1), [(0.00, (14, 11, 10)), (0.22, (44, 31, 24)), (0.42, (88, 58, 34)),
                                              (0.62, (146, 98, 52)), (0.80, (198, 148, 84)), (1.00, (238, 204, 140))])
    xx = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    light = (0.74 - 0.16 * (yy / H)) * (0.86 + 0.22 * xx)
    graded = dusk * light[..., None]
    # 右上海天交界一团夕照
    yy2, xx2 = np.mgrid[0:H, 0:W].astype(np.float32)
    glow = np.exp(-(((xx2 - 440) / 150) ** 2 + ((yy2 - 125) / 70) ** 2))
    graded = graded + glow[..., None] * np.array([0.16, 0.09, 0.03], np.float32)
    out = a * (1 - bg[..., None]) + graded * bg[..., None]
    # 轻度厚涂化（与 fix_pilot_ana 同法）：压掉 CG 的光滑皮肤，贴近全套油画笔触
    out = kuwahara(out, 2)
    return to_img(warm_grade(out, warmth=0.025))


def fix_pu_steward(src):
    """Codex「波斯酒家掌柜」→ 蒲家账房（月白缠头、石青暗花袍、深目高鼻、蕃坊陈设）。左上招牌写
    「波斯酒家 / 廣州蕃坊」——蒲家在泉州，也不是酒家：把招牌上的亮字抹成素面木匾（亮笔画按局部均值取出、
    扩散补平，再按行补回木纹）。执壶斟的红浆就当蕃坊的舍里八（果露）。"""
    a = f32(src)
    lum = luma(a)
    local = gblur(lum, 7)
    out = a.copy()
    x0, y0, x1, y1 = 20, 4, 222, 104
    reg = np.zeros(lum.shape, np.float32)
    reg[y0:y1, x0:x1] = 1
    m = dilate(reg * (lum > local * 1.10) * (lum > 0.10), 2) * reg
    hole = (m > 0.5).astype(np.float32)
    py0, py1, px0, px1 = 0, min(H, y1 + 24), 0, min(W, x1 + 24)
    filled = out.copy()
    filled[py0:py1, px0:px1] = inpaint(out[py0:py1, px0:px1], hole[py0:py1, px0:px1], iters=700)
    hp = lum - gblur(lum, 2.5)
    sub_hp = hp[y0:y1, x0:x1]
    keepm = hole[y0:y1, x0:x1] < 0.5
    cnt = keepm.sum(axis=1)
    prof = np.where(cnt > 0, (sub_hp * keepm).sum(axis=1) / np.maximum(cnt, 1), 0).astype(np.float32)
    det = np.zeros(lum.shape, np.float32)
    det[y0:y1, x0:x1] = prof[:, None]
    filled = add_grain(filled + det[..., None] * 0.9, hole, 0.008, 41)
    mm = gblur(hole, 0.8)[..., None]
    out = out * (1 - mm) + filled * mm
    return to_img(warm_grade(out, warmth=0.015))


# id → (源图, 处理函数)。源图 codex: 走 CODEX 目录，main: 走仓库 assets/
PAINTED = {
    "chen_wenlong": ("codex:portrait_chen_wenlong.png", None),
    "merchant_lin": ("codex:portrait_mingzhou_merchant.png", fix_merchant_lin),
    "pilot_ana": ("main:sprite_ana.png", fix_pilot_ana),
    "monk_jinghai": ("codex:portrait_old_monk.png", fix_monk_jinghai_v2),
    "customs_official": ("codex:portrait_customs_official.png", fix_customs_official_v2),
    "xinghua_messenger": ("codex:portrait_linan_passerby.png", None),
    "lin_hua": ("codex:portrait_patrol_soldier.png", None),
    "huang_quan": ("codex:portrait_jiaozhi_temple_keeper.png", None),
    "veteran_son": ("codex:portrait_tavern_guest.png", None),
    "chen_servant": ("main:sprite_servant.png", fix_chen_servant),
    "cai_qixing": ("codex:portrait_broken_eyebrow.png", None),
    "chen_laodao": ("codex:portrait_jiaozhi_old_merchant.png", None),
    "he_wenzhou": ("codex:portrait_one_finger_sailor.png", None),
    "shi_naowei": ("codex:portrait_abbas.png", fix_shi_naowei),
    "zhou_suanchou": ("codex:portrait_inn_scholar.png", fix_zhou_suanchou),
    "huang_zhangfang": ("codex:portrait_innkeeper.png", None),
    "ye_shibo": ("codex:portrait_jeju_official.png", None),
    "wen_tianxiang": ("codex:portrait_jia_disciple.png", None),
    # 第 1 轮返工：酒馆首屏职事与蕃坊人物改用 Codex 未用油画（形貌对得上的才用）
    "wu_zhen": ("codex:portrait_penghu_fisherman.png", fix_wu_zhen),
    "ana_tongxiang": ("codex:portrait_ryukyu_pilot.png", fix_ana_tongxiang_v2),
    "pu_steward": ("codex:portrait_persian_tavernkeeper.png", fix_pu_steward),
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


def seal_image(text, size, seed):
    """朱文印：朱色字 + 一圈残缺边栏（绢底透出，不是一块红标签）；笔画刀口式腐蚀、边栏崩口，
    印泥从一角向对角渐淡，按 seed 旋转 ±1.5°、浓淡不同。返回 RGBA float。"""
    sw, sh = size
    s = 4
    rng = np.random.default_rng(seed)
    W4, H4 = sw * s, sh * s
    im = Image.new("L", (W4, H4), 0)
    d = ImageDraw.Draw(im)
    bw = int(2.3 * s * inkbrush.S)
    d.rectangle([bw // 2, bw // 2, W4 - 1 - bw // 2, H4 - 1 - bw // 2], outline=255, width=bw)
    n = len(text)
    pad = bw * 2.2
    font_px = int(min((W4 - pad * 2) * 0.98, (H4 - pad * 2) / n * 1.0))
    total = font_px * n
    y = (H4 - total) / 2
    for ch in text:
        font = ImageFont.truetype(glyph_font(FONT_TITLE, ch)[0], font_px)
        bb = d.textbbox((0, 0), ch, font=font, stroke_width=int(font_px * 0.03))
        cw = bb[2] - bb[0]
        d.text(((W4 - cw) / 2 - bb[0], y - bb[1] + (font_px - (bb[3] - bb[1])) / 2), ch, font=font, fill=255,
               stroke_width=int(font_px * 0.03), stroke_fill=255)
        y += font_px
    m = np.asarray(im, np.float32) / 255.0
    # 刀口：高频噪声阈值腐蚀笔画边缘（边缘成锯齿、不圆），再小片崩口
    n1 = _noise((H4, W4), 6 * s, seed + 1)
    n2 = _noise((H4, W4), 40 * s, seed + 2)
    er = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5)), np.float32) / 255
    edge = np.clip(m - er, 0, 1)
    m = m * (1 - edge * (n1 > 0.5))
    yy, xx = np.mgrid[0:H4, 0:W4].astype(np.float32)
    # 从一角向对角渐淡（按印时用力不匀）
    cx0, cy0 = (0, 0) if rng.random() < 0.5 else (W4, H4)
    if rng.random() < 0.5:
        cx0 = W4 - cx0
    dist = np.sqrt((xx - cx0) ** 2 + (yy - cy0) ** 2) / math.hypot(W4, H4)
    fade = np.clip(1.05 - dist * rng.uniform(0.35, 0.6), 0.45, 1.0)
    # 边栏崩口：几段缺
    border = np.minimum.reduce([xx, yy, W4 - 1 - xx, H4 - 1 - yy]) < bw * 1.2
    for _ in range(int(rng.integers(2, 5))):
        if rng.random() < 0.5:
            x0 = rng.uniform(0, W4)
            chip = (np.abs(xx - x0) < rng.uniform(2, 6) * s) & border & ((yy < H4 / 2) == (rng.random() < 0.5))
        else:
            y0 = rng.uniform(0, H4)
            chip = (np.abs(yy - y0) < rng.uniform(2, 7) * s) & border & ((xx < W4 / 2) == (rng.random() < 0.5))
        m = m * (1 - chip)
    ink = rng.uniform(0.82, 0.96)
    a = m * fade * (0.7 + 0.3 * np.clip((n2 - 0.2) * 2, 0, 1)) * ink
    ang = rng.uniform(-1.5, 1.5)
    A = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).rotate(ang, resample=Image.BICUBIC, expand=False)
    A = np.asarray(A.resize((sw, sh), Image.LANCZOS), np.float32) / 255.0
    col = np.array(ZHUSHA, np.float32) / 255.0 * rng.uniform(0.92, 1.05)
    out = np.zeros((sh, sw, 4), np.float32)
    out[..., :3] = col
    out[..., 3] = A
    return out


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


def vertical_title(t):
    """竖排身份：括号与间隔号换成竖排可读的「・」。"""
    return t.replace("（", "・").replace("）", "").replace("·", "・")


SEAL_TEXT = {"yuhu_chen": "陈氏", "song_court": "宋廷", "quanxing": "权幸", "mongol_yuan": "蒙元",
             "fanfang": "蕃坊", "quanzhou_merchants": "海商", "seafarers": "海上", "temple": "寺院",
             "local_officials": "吏员", "townsfolk": "市井", "foreign": "异国"}


def card_seed(cid):
    return sum(ord(ch) * (i + 1) for i, ch in enumerate(cid)) % 100000


def name_px(name):
    return {1: 74, 2: 74, 3: 72, 4: 62, 5: 54}.get(len(name), 46)


# 题签位置：姓名列与身份小字都在 x≥412，人物志/名册的 34px 小头像（CharacterArt.HEAD_REGION = 104..408）
# 裁不到字
X_NAME, X_ID, ID_PX, Y0 = 472, 424, 20, 42


def title_layout(c):
    name = c["name"]
    npx = name_px(name)
    fb = any(glyph_font(FONT_TITLE, ch)[1] for ch in name)
    return npx, fb, Y0 + npx * 1.02 * len(name)


def build_card(c, cast, titled=False):
    """墨影卡：旧绢暖光底 + 减笔泼墨人物 + 下缘淡墨山水 / 海浪入雾（+ titled 时题签朱印）。
    游戏里一律用无字版（titled=False）：人物志、酒馆卡、见面页都有自己的名牌，卡上再烤一遍竖排姓名与
    阵营印会在缩略图里成噪点、详页同名三处（第 1 轮评审 B1）；无字版也和 18 张油画同一种画面结构。
    带题签的只给单张展示 / 出图台用（--titled DIR）。"""
    S = inkbrush.S
    seed = card_seed(c["id"])
    spec = dict(cast[c["id"]])
    if not titled:
        # 无题签：不留题签列（inkcard.paint 的 tclear 整片为 0），人物与背景铺满整卡
        spec["_title_end"] = -400.0
        img, tex, info = inkcard.paint(spec, seed)
        return to_img(img).resize((W, H), Image.LANCZOS), info
    npx, fb, y_name_end = title_layout(c)
    st = SEAL_TEXT.get(c["faction"], "")
    sw_, sh_ = 46, 46 + 38 * max(1, len(st) - 1)
    spec["_title_end"] = y_name_end + (10 + sh_ if st else 0)
    img, tex, info = inkcard.paint(spec, seed)
    # 题签处绢面保亮：量姓名列的底色，不够亮就把这一带（软边竖椭圆）提到对比够用（大字 ≥3:1，取 4.5 作余量）
    ys0, ys1 = int(Y0 * S), int(spec["_title_end"] * S)
    xs0, xs1 = int((X_NAME - npx * 0.55) * S), int((X_NAME + npx * 0.55) * S)
    lb = float(np.percentile(luma(img[ys0:ys1, xs0:xs1]), 60))
    want = 0.6
    if lb < want:
        # 宽而软的高斯渐变（不留平台、不见边），像题签处本就落在光里
        yy, xx = np.mgrid[0:H * S, 0:W * S].astype(np.float32) / S
        cy = (Y0 + spec["_title_end"]) / 2
        ry = (spec["_title_end"] - Y0) / 2 + 70
        band = np.exp(-(((xx - X_NAME + 10) / 110.0) ** 2 + ((yy - cy) / ry) ** 2) * 1.6)[..., None]
        gain = want / max(lb, 0.05)
        img = np.clip(img * (1 + (gain - 1) * band), 0, 1)
    # 题签：马善政竖排姓名（名中有马善政缺的字时，整列改文楷，免得一列里两种字形）+ 文楷身份小字，朱文阵营印
    name = c["name"]
    font_n = FONT_BODY if fb else FONT_TITLE
    m, y_end = inkcard.text_mask(name, font_n, npx * (0.92 if fb else 1.0), X_NAME, Y0, 1.02 if not fb else 1.1,
                                 glyph_font)
    img = inkcard.apply_ink(img, inkcard.ink_text(m, tex, 0.96, 0.22))
    title = vertical_title(c["title"])
    tm, _ = inkcard.text_mask(title, FONT_BODY, ID_PX, X_ID, Y0 + 12, 1.1, glyph_font)
    img = inkcard.apply_ink(img, inkcard.ink_text(tm, tex, 0.86, 0.1))
    if st:
        seal = seal_image(st, (sw_ * S, sh_ * S), seed)
        sy = int((y_end + 10) * S)
        sx = int(X_NAME * S - sw_ * S / 2)
        reg = img[sy:sy + sh_ * S, sx:sx + sw_ * S]
        al = seal[..., 3:4]
        reg[:] = reg * (1 - al) + (seal[..., :3] * (0.72 + 0.28 * reg)) * al
    return to_img(img).resize((W, H), Image.LANCZOS), info


# ───────────────────────── silhouette：逆光剪影卡（第 2 轮返工起的默认占位） ─────────────────────────
# 第 2 轮美术 B1：墨影卡「给了脸，但画得粗」，木偶脸与油画混排跳脱；而「未识」压暗后反倒协调——暗剪影本身不违和。
# 于是占位改成逆光剪影：人形只留焦墨剪影（不画五官），外缘一道泥金轮廓光（α≈0.5，像油画里的侧逆光），
# 背景是此人籍贯港的油画高斯模糊、压暖（色相约 35°），保住油画的明度结构；右下角钤一方「待绘」。
# 人形轮廓仍取墨影卡同一套选角（cast.json → figures.py 骨架、heads 冠帽、props 持物），与将来重绘的构图一致。
# 按 origin 关键词取底图（先匹配先得），取不到按阵营兜底；同一张底图按 id 取不同的取景，不雷同。
ORIGIN_BG = [
    ("蕃坊", "cutscene/cs_quanzhou_fanfang.jpg"), ("大食", "cutscene/cs_quanzhou_fanfang.jpg"),
    ("泉州", "bg_quanzhou_harbor.jpg"),
    ("兴化海口", "cutscene/cs_xinghua_seawall.jpg"),
    ("玉湖", "bg_xinghua_study.jpg"), ("莆田", "bg_xinghua_study.jpg"),
    ("兴化", "bg_xinghua_harbor.jpg"),
    ("福州", "cutscene/cs_taijiang_dawn.jpg"), ("漳州", "bg_zhangzhou.jpg"), ("温州", "bg_wenzhou.jpg"),
    ("博多", "bg_hakata.jpg"), ("镰仓", "bg_hakata.jpg"), ("日本", "bg_hakata.jpg"),
    ("耽罗", "cutscene/cs_jeju_north.jpg"), ("高丽", "bg_jeju.jpg"),
    ("蒙古", "cutscene/cs_north_mongol.jpg"), ("真定", "cutscene/cs_north_mongol.jpg"),
    ("临安", "bg_linan.jpg"), ("绍兴", "bg_linan.jpg"), ("台州", "bg_linan.jpg"), ("镇江", "bg_linan.jpg"),
    ("楚州", "cutscene/cs_fleet_armored.jpg"), ("涿州", "cutscene/cs_fleet_armored.jpg"),
    ("安丰", "cutscene/cs_citywall_sunset.jpg"), ("潭州", "cutscene/cs_citywall_sunset.jpg"),
    ("相州", "bg_end_temple.jpg"), ("端平", "bg_xinghua_wine_shed.jpg"),
]
FACTION_BG = {
    "temple": "bg_temple_library.jpg", "song_court": "bg_palace_exam.jpg", "quanxing": "bg_linan.jpg",
    "mongol_yuan": "cutscene/cs_north_mongol.jpg", "local_officials": "bg_quanzhou_office.jpg",
    "yuhu_chen": "bg_xinghua_study.jpg", "townsfolk": "bg_xinghua_harbor.jpg", "seafarers": "bg_reef_bay.jpg",
    "quanzhou_merchants": "bg_quanzhou_harbor.jpg", "fanfang": "cutscene/cs_quanzhou_fanfang.jpg",
    "foreign": "bg_hakata.jpg",
}
# 阵营先于籍贯的：寺院（泉州 / 博多的僧人都进经阁）、州郡吏员（衙署）
FACTION_FIRST = ("temple", "local_officials")
DAIHUI_SEAL = os.path.join(ROOT, "assets", "ui", "nk1", "seal_daihui_zhu.png")
SIL_INK = np.array((0.098, 0.082, 0.066), np.float32)     # 焦墨剪影 v≈0.1，略暖
RIM_GOLD = np.array((0.96, 0.80, 0.47), np.float32)       # 泥金轮廓光（亮一档，压在剪影上才读得出是光）


def silhouette_bg_path(c):
    fac = c.get("faction", "")
    if fac in FACTION_FIRST and fac in FACTION_BG:
        return os.path.join(MAIN, FACTION_BG[fac])
    origin = str(c.get("origin", ""))
    for key, rel in ORIGIN_BG:
        if key in origin:
            return os.path.join(MAIN, rel)
    return os.path.join(MAIN, FACTION_BG.get(fac, "bg_xinghua_harbor.jpg"))


def _shift(m, dx, dy):
    """整数像素平移（边外补 0）。"""
    out = np.zeros_like(m)
    h, w = m.shape
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    out[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx] = m[ys0:ys1, xs0:xs1]
    return out


def silhouette_background(c, seed, spec, WS_, HS_):
    """籍贯港油画：按 id 取一块 4:5 取景（横图里左右游走、略偏上），高斯模糊 r≈18（1×），压暖到色相约 35°，
    头后一团暖光（逆光的光源），四角沉下去。返回 2× 浮点图。"""
    rng = np.random.default_rng(seed + 900)
    src = Image.open(silhouette_bg_path(c)).convert("RGB")
    sw, sh = src.size
    want = WS_ / HS_
    ch_ = sh * rng.uniform(0.78, 0.95)
    cw_ = ch_ * want
    if cw_ > sw:
        cw_ = sw
        ch_ = cw_ / want
    x0 = rng.uniform(0, max(1.0, sw - cw_))
    y0 = rng.uniform(0, max(1.0, sh - ch_)) * 0.6
    crop = src.crop((int(x0), int(y0), int(x0 + cw_), int(y0 + ch_))).resize((WS_ // 4, HS_ // 4), Image.LANCZOS)
    a = f32(crop)
    a = gblur(a, 9.0)   # 256 宽上 σ9 ≈ 512 成品上 r18
    a = np.asarray(to_img(a).resize((WS_, HS_), Image.BICUBIC), np.float32) / 255.0
    lum = luma(a)[..., None]
    warm = np.array((1.0, 0.78, 0.52), np.float32)
    warm = warm / luma(warm[None, None, :])[..., None][0, 0]
    a = a * 0.35 + lum * warm * 0.65
    # 明度：整体提到中调（逆光的天光），头后一团暖光，四角沉下
    yy, xx = np.mgrid[0:HS_, 0:WS_].astype(np.float32) / inkbrush.S
    comp = spec.get("comp", {})
    hx, hy = comp.get("hx", 250.0), comp.get("hy", 200.0)
    lx = hx + float(np.sign(spec.get("turn", 0.3) or 0.3)) * -40.0
    glow = np.exp(-(((xx - lx) / 250.0) ** 2 + ((yy - hy - 30.0) / 300.0) ** 2))
    lm = float(lum.mean())
    a = a * (0.55 / max(lm, 0.05)) ** 0.6
    a = a * (0.62 + 0.78 * glow[..., None]) + glow[..., None] * np.array((0.10, 0.07, 0.03), np.float32)
    r = np.sqrt(((xx - 256) / 300.0) ** 2 + ((yy - 300) / 380.0) ** 2)
    a = a * np.clip(1.15 - 0.55 * r, 0.35, 1.0)[..., None]
    return np.clip(a, 0, 1)


def _fill_holes(m):
    """剪影里的空洞（白质孙、白头巾这些淡墨处笔触稀）补实：从画框四周漫灌出「外面」，没灌到的就是洞。"""
    # .copy()：fromarray 出来的图与数组共用只读内存，floodfill 会静默不生效（Pillow 12 实测）
    b = Image.fromarray(((m > 0.5) * 255).astype(np.uint8)).copy()
    h, w = m.shape
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    seeds += [(x, 0) for x in range(0, w, 16)] + [(0, y) for y in range(0, h, 16)] + [(w - 1, y) for y in range(0, h, 16)]
    seeds += [(x, h - 1) for x in range(0, w, 16)]
    for sx, sy in seeds:
        if b.getpixel((sx, sy)) == 0:
            ImageDraw.floodfill(b, (sx, sy), 128)
    a = np.asarray(b)
    holes = (a == 0).astype(np.float32)
    return np.maximum(m, holes)


def build_silhouette(c, cast):
    """逆光剪影卡（无字、无五官）：籍贯港油画模糊压暖作底 + 焦墨剪影 + 泥金轮廓光 +「待绘」小印。"""
    S = inkbrush.S
    seed = card_seed(c["id"])
    spec = dict(cast[c["id"]])
    spec["_title_end"] = -400.0
    _img, _tex, info = inkcard.paint(spec, seed)
    raw = info["fig_raw"]
    HS_, WS_ = raw.shape
    # 剪影：墨影人形的笔触密度（只轻糊 0.8 纹素，留得住冠翅、须梢、袖口的外形）做闭运算补掉飞白，
    # 再并上大糊过的密度场补实身躯；边缘 1 纹素的软边
    d = inkbrush.blur(info["fig_d"], 0.8 * S)
    crisp = inkbrush.smoothstep(0.10, 0.28, d)
    r_close = int(round(5 * S))
    crisp = erode(dilate(crisp, r_close), r_close)
    body = inkbrush.smoothstep(0.30, 0.55, raw)
    body = np.maximum(body, inkbrush.smoothstep(0.18, 0.40, inkbrush.blur(raw, 1.5 * S)))
    sil = np.clip(np.maximum(crisp, body), 0, 1)
    sil = np.maximum(sil, np.clip(info["face"] * 1.5, 0, 1))
    sil = _fill_holes(sil)
    sil = inkbrush.blur(sil, 0.5 * S)
    bg = silhouette_background(c, seed, spec, WS_, HS_)
    # 剪影里极淡的明暗：受光一侧略提（反光），下半身略沉，不是一块死黑
    turn = float(spec.get("turn", 0.3) or 0.3)
    lx = -1 if turn >= 0 else 1          # 光从人物背后一侧来（面朝右则光在左后）
    ly = -1
    yy, xx = np.mgrid[0:HS_, 0:WS_].astype(np.float32) / S
    body_shade = 1.0 + 0.10 * np.clip(lx * (xx - 256) / 256.0, -1, 1) - 0.12 * np.clip((yy - 300) / 340.0, 0, 1)
    fine = _noise((HS_, WS_), 60 * S, seed + 31)
    ink = SIL_INK[None, None, :] * (body_shade[..., None] * (0.96 + 0.08 * fine[..., None]))
    # 轮廓光：受光一侧 3 纹素（1×）宽的亮边 + 四周一圈极细的弱光；再向外晕一点（halation）
    k = int(round(3 * S))
    lit = np.clip(sil - _shift(sil, lx * k, ly * k), 0, 1)
    ring = np.clip(sil - erode(sil, max(1, int(round(1.2 * S)))), 0, 1)
    rim = np.clip(lit * 1.0 + ring * 0.35, 0, 1)
    rim = inkbrush.blur(rim, 0.6 * S)
    halo = inkbrush.blur(lit, 5 * S) * (1 - sil)
    out = bg * (1 - sil[..., None]) + ink * sil[..., None]
    out = out * (1 - 0.5 * rim[..., None]) + RIM_GOLD * (0.5 * rim[..., None])
    out = out + halo[..., None] * RIM_GOLD * 0.18
    # 下缘薄雾：剪影脚下淡入暖雾，免得人像被画框一刀切
    fog = inkbrush.smoothstep(560, 640, yy)[..., None] * 0.35
    out = out * (1 - fog) + bg * fog
    img = to_img(np.clip(out, 0, 1)).resize((W, H), Image.LANCZOS)
    # 「待绘」小印：UI 线的成品朱文印，逻辑 22px 宽（2× 画 44px），右下角，略歪
    if os.path.isfile(DAIHUI_SEAL):
        seal = Image.open(DAIHUI_SEAL).convert("RGBA")
        sw_ = 44
        sh_ = int(round(seal.size[1] * sw_ / seal.size[0]))
        seal = seal.resize((sw_, sh_), Image.LANCZOS).rotate(-3.0, resample=Image.BICUBIC, expand=True)
        sa = np.asarray(seal, np.float32) / 255.0
        sa[..., 3] *= 0.9
        seal = Image.fromarray((sa * 255 + 0.5).astype(np.uint8))
        img = img.convert("RGBA")
        img.alpha_composite(seal, (W - seal.size[0] - 16, H - seal.size[1] - 16))
        img = img.convert("RGB")
    return img, info


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


HEAD_REGION = (104, 40, 304, 304)          # 与 scripts/ui/CharacterArt.gd 一致
CELL = (104, 130)                          # scripts/ui/CharacterCodex.gd CELL_PIC


def mix_sheet(chars, path, cols=10, gap=6):
    """验收图（按 characters.json 原顺序穿插，不分组）：
    path          人物志格子尺寸 104×130 的混排网格（名字在格下）；
    path 同名 _heads   CharacterArt.HEAD_REGION 裁出的 34px 小头像（放大 2× 看），查有无字残片、头像空不空。"""
    tw, th = CELL
    lab = 16
    font = ImageFont.truetype(FONT_BODY, 12)
    rows = (len(chars) + cols - 1) // cols
    sheet = Image.new("RGB", (gap + cols * (tw + gap), gap + rows * (th + lab + gap)), (30, 26, 22))
    d = ImageDraw.Draw(sheet)
    hs = 34 * 2
    hsheet = Image.new("RGB", (gap + 15 * (hs + gap), gap + ((len(chars) + 14) // 15) * (hs + gap)), (30, 26, 22))
    for i, c in enumerate(chars):
        p = os.path.join(OUT_DIR, c["id"] + ".png")
        if not os.path.isfile(p):
            continue
        im = Image.open(p).convert("RGB")
        x, y = gap + (i % cols) * (tw + gap), gap + (i // cols) * (th + lab + gap)
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, y))
        d.text((x + 2, y + th + 1), c["name"], fill=(225, 214, 190), font=font)
        hx, hy, hw, hh = HEAD_REGION
        hd = im.crop((hx, hy, hx + hw, hy + hh)).resize((34, 34), Image.LANCZOS).resize((hs, hs), Image.NEAREST)
        hsheet.paste(hd, (gap + (i % 15) * (hs + gap), gap + (i // 15) * (hs + gap)))
    sheet.save(path, quality=92)
    root, ext = os.path.splitext(path)
    hsheet.save(root + "_heads" + ext, quality=92)
    print("mix →", path, "/", root + "_heads" + ext)


def metrics(chars, titled_dir=""):
    """自检：暗部轮廓两两 IoU（luma<0.18 / <0.22）、整卡逐行亮度曲线两两相关、头像框里的「空」（绢底占比）；
    另量面部中间调（头心 comp.hx/hy 附近 40×40 的平均亮度，墨影与油画各自的分布）。
    墨影与油画分开算，油画是参照。题签对比度只在出了带题签版（--titled DIR）时量。"""
    def load(cid):
        a = np.asarray(Image.open(os.path.join(OUT_DIR, cid + ".png")).convert("RGB").resize((128, 160),
                                                                                             Image.LANCZOS),
                       np.float32) / 255.0
        return luma(a)
    out = {}
    for kind in ("card", "painted"):
        ids = [c["id"] for c in chars if (c["portrait_status"] == "painted") == (kind == "painted")]
        L = [load(i) for i in ids]
        res = {}
        for thr in (0.18, 0.22):
            M = [(l < thr) for l in L]
            v = []
            for i in range(len(M)):
                for j in range(i + 1, len(M)):
                    u = np.logical_or(M[i], M[j]).sum()
                    v.append(np.logical_and(M[i], M[j]).sum() / u if u else 0.0)
            res["iou_%.2f" % thr] = (float(np.mean(v)), float(np.max(v)))
        R = np.stack([l.mean(1) for l in L])
        C = np.corrcoef(R)
        iu = np.triu_indices(len(L), 1)
        res["row_corr"] = (float(C[iu].mean()), float(C[iu].max()))
        res["luma"] = (float(np.mean([l.mean() for l in L])), float(np.min([l.mean() for l in L])),
                       float(np.max([l.mean() for l in L])))
        out[kind] = res
    for k, v in out.items():
        print("[metrics] %-7s " % k + "  ".join("%s mean %.3f max %.3f" % (kk, vv[0], vv[1]) if len(vv) == 2 else
                                                "%s mean %.3f (%.3f–%.3f)" % (kk, vv[0], vv[1], vv[2])
                                                for kk, vv in v.items()))
    # 题签可读：姓名列 85 分位作底、3 分位作字，WCAG 相对亮度对比（只量带题签版）
    def rel(a):
        a = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
        return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722
    if not titled_dir:
        return out
    crs = []
    for c in chars:
        if c["portrait_status"] == "painted":
            continue
        tp = os.path.join(titled_dir, c["id"] + ".png")
        if not os.path.isfile(tp):
            continue
        a = np.asarray(Image.open(tp).convert("RGB"), np.float32) / 255.0
        npx, fb, ye = title_layout(c)
        reg = rel(a[int(Y0):int(ye), int(X_NAME - npx * 0.5):int(X_NAME + npx * 0.5)])
        lb, lf = np.percentile(reg, 85), np.percentile(reg, 3)
        crs.append(((lb + 0.05) / (lf + 0.05), c["id"]))
    crs.sort()
    print("[metrics] name contrast min %.2f (%s)  median %.2f" % (crs[0][0], crs[0][1], crs[len(crs) // 2][0]))
    out["name_contrast"] = (crs[0][0], crs[len(crs) // 2][0])
    return out


def main(argv):
    global OUT_DIR
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    do_p = "--cards-only" not in argv
    do_c = "--painted-only" not in argv
    # 占位卡画法：silhouette（逆光剪影，第 2 轮返工起默认）/ ink（墨影减笔，第 1 轮）
    mode = "silhouette"
    for a in argv:
        if a.startswith("--mode="):
            mode = a.split("=", 1)[1]
    if "--mode" in argv:
        mode = argv[argv.index("--mode") + 1]
    if mode not in ("silhouette", "ink"):
        raise SystemExit("--mode 只认 silhouette / ink")
    # --preview DIR：出到仓库外的目录看小样，不动 assets/portraits
    if "--preview" in argv:
        OUT_DIR = argv[argv.index("--preview") + 1]
    titled_dir = argv[argv.index("--titled") + 1] if "--titled" in argv else ""
    if titled_dir:
        os.makedirs(titled_dir, exist_ok=True)
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
            # 墨影卡有灯笼暖光、公服浅绛与朱印，256 色调色板会在这些渐变上起色阶（实测灯笼处误差 1.0–2.5/255
            # 且肉眼可见条带），故存 RGB
            if mode == "silhouette":
                card, _info = build_silhouette(c, cast)
            else:
                card, _info = build_card(c, cast)
            card.save(dst, optimize=True)
            if titled_dir:
                tcard, _ = build_card(c, cast, titled=True)
                tcard.save(os.path.join(titled_dir, cid + ".png"), optimize=True)
            n_c += 1
        print("  %-18s %s" % (cid, "painted" if c["portrait_status"] == "painted" else "card"))
    print("done: painted %d, cards %d → %s" % (n_p, n_c, OUT_DIR))
    if "--sheet" in argv:
        contact_sheet([c["id"] for c in chars], argv[argv.index("--sheet") + 1])
    if "--mix" in argv:
        mix_sheet(chars, argv[argv.index("--mix") + 1])
    if "--metrics" in argv or "--mix" in argv:
        metrics(chars, titled_dir)


if __name__ == "__main__":
    main(sys.argv[1:])
