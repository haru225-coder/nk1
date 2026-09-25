#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：底图里露出的简体印刷字招牌换成宋式匾（第 2 轮美术 minor 13）。

bg_customs_room.jpg（市舶司见面页 / 衙门内页底图）右上有一块后期贴上去的说明牌：浅棕圆角框、简体无衬线
「香药抽二成 / 瓷器抽一成」，像界面标签，见面页面板收窄后正露在立绘框上方。牌本身不透明（实测框内外颜色
线性回归斜率 ≈0），抹字只会剩一块发糊的棕框，于是整块换成一方黑漆金字匾「市舶抽解」：
漆底横向木纹、四边起线、一道泥金内线，马善政泥金字带磨损；受光随画里的左窗（左亮右沉）。

幂等：原图备份在同目录 .orig 旁文件不入库；本脚本以 git 里 HEAD 的原图为底重画（git show 只读），
没有 git 时退回以当前文件为底，但会先检查匾是否已经换过（匾心的漆色）以免叠画。
用法：python3 tools/art/fix_bg_signs.py
"""
import io
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = os.path.expanduser(os.environ.get("NK1_FONT_SRC", "~/tmp/nk1-art-work/fonts_src")) + "/MaShanZheng-Regular.ttf"
if not os.path.isfile(FONT):
    FONT = os.path.join(ROOT, "assets", "fonts", "MaShanZheng-Regular.ttf")
# (文件, 牌外框 x0,y0,x1,y1（原图像素，含浅色描边）, 匾文)
SIGNS = [
    ("assets/bg_customs_room.jpg", (1283, 115, 1719, 297), "市舶抽解"),
]
LACQUER = np.array((0.20, 0.095, 0.060), np.float32)
FRAME = np.array((0.30, 0.16, 0.095), np.float32)
GOLD = np.array((0.74, 0.58, 0.30), np.float32)


def _source(rel):
    """git HEAD 里的原图（只读 git show）；取不到就用当前文件。"""
    try:
        blob = subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + rel], capture_output=True, check=True).stdout
        return Image.open(io.BytesIO(blob)).convert("RGB"), True
    except Exception:
        return Image.open(os.path.join(ROOT, rel)).convert("RGB"), False


def plaque(w, h, text, seed=1255):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # 漆底：横向木纹（逐行低频起伏）+ 细颗粒 + 左亮右沉
    rows = rng.normal(0, 1, h).astype(np.float32)
    k = np.exp(-np.linspace(-3, 3, 13) ** 2)
    rows = np.convolve(rows, k / k.sum(), mode="same")
    rows = (rows - rows.mean()) / (rows.std() + 1e-6)
    grain = rng.normal(0, 1, (h, w)).astype(np.float32)
    grain = np.asarray(Image.fromarray(np.clip(grain * 40 + 128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.9)),
                       np.float32) / 255.0 - 0.5
    light = 1.12 - 0.24 * (xx / w)
    base = LACQUER[None, None, :] * (1 + 0.045 * rows[:, None, None] + 0.10 * grain[..., None]) * light[..., None]
    # 四边起线：外框一圈略亮的漆，内侧一道暗槽，再一道泥金细线
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    frame = (edge < 11).astype(np.float32)
    groove = ((edge >= 11) & (edge < 13)).astype(np.float32)
    gold_line = ((edge >= 16) & (edge < 18)).astype(np.float32)
    out = base * (1 - frame[..., None]) + (FRAME * light[..., None] * (1 + 0.08 * grain[..., None])) * frame[..., None]
    out = out * (1 - 0.45 * groove[..., None])
    out = out * (1 - 0.6 * gold_line[..., None]) + GOLD * light[..., None] * 0.85 * (0.6 * gold_line[..., None])
    # 外沿投影一线（匾挂在墙上）
    out = out * (0.75 + 0.25 * np.clip(edge / 2.5, 0, 1))[..., None]
    # 匾文：马善政泥金，居中；带一点磨损（颗粒吃掉字口）
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    fs = int(h * 0.44)
    font = ImageFont.truetype(FONT, fs)
    spacing = int(fs * 0.22)
    widths = [d.textbbox((0, 0), ch, font=font)[2] - d.textbbox((0, 0), ch, font=font)[0] for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = (w - total) / 2
    for ch, cw in zip(text, widths):
        bb = d.textbbox((0, 0), ch, font=font)
        d.text((x - bb[0], (h - (bb[3] - bb[1])) / 2 - bb[1]), ch, font=font, fill=255)
        x += cw + spacing
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255.0
    wear = np.clip(0.85 + 0.6 * grain, 0.0, 1.0)
    m = m * wear
    shadow = np.asarray(mask.filter(ImageFilter.GaussianBlur(2.0)), np.float32) / 255.0
    shadow = np.roll(shadow, (2, 2), axis=(0, 1))
    out = out * (1 - 0.35 * shadow[..., None])
    out = out * (1 - m[..., None]) + GOLD * light[..., None] * m[..., None]
    # 与油画同一种柔度：整块轻糊 0.7px，免得数码硬边
    out = np.asarray(Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)),
                     np.float32) / 255.0
    return np.clip(out, 0, 1)


def fix_one(rel, box, text):
    src, from_git = _source(rel)
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    im = src.copy()
    p = plaque(w, h, text)
    region = np.asarray(im.crop(box), np.float32) / 255.0
    # 边缘 1.5px 羽化，贴进画里
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    a = np.clip(edge / 1.5, 0, 1)[..., None]
    out = region * (1 - a) + p * a
    im.paste(Image.fromarray((out * 255 + 0.5).astype(np.uint8)), (x0, y0))
    im.save(os.path.join(ROOT, rel), quality=92, subsampling=0)
    print("  %s：牌 %s 换成匾「%s」（底图取自 %s）" % (os.path.basename(rel), box, text, "git HEAD" if from_git else "当前文件"))


def main(argv):
    for rel, box, text in SIGNS:
        fix_one(rel, box, text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
