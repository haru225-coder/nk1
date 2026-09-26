#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：底图里露出的简体印刷字招牌换成宋式匾（第 2 轮美术 minor 13）。

bg_customs_room.jpg（市舶司见面页 / 衙门内页底图）右上有一块后期贴上去的说明牌：浅棕圆角框、简体无衬线
「香药抽二成 / 瓷器抽一成」，像界面标签，见面页面板收窄后正露在立绘框上方。牌本身不透明（实测框内外颜色
线性回归斜率 ≈0），抹字只会剩一块发糊的棕框，于是整块换成一方黑漆金字匾「市舶抽解」：
漆底横向木纹、四边起线、一道泥金内线，马善政泥金字带磨损；受光随画里的左窗（左亮右沉）。
匾文从右往左排（古代横匾右起读）：画面上从左到右依次是「解 抽 舶 市」，右起读作「市舶抽解」。
（2026-09-26 前的版本是左起横排，已按此改正；匾文、字体、漆色、做法都没变，只是字序排版。）

写出：只改匾所在的 8×8 块（本图 4:4:4）。改过的块按块对齐裁出、用原图同一套量化表编码，复用
fix_bg_customs_jar.write_jpeg 以 jpegtran -drop 无损嵌回——块外（包括已改色的市舶司大罐 x 1048–1136、y 496–584）
与输入逐字节一致；写之前先在临时文件上核对块外像素全等，不等就不写（绝不退回整图重编码）。
只有输入还是 4:2:0 的最初原图（带说明牌）时，write_jpeg 才退回整图同量化表重编码（那时罐子也还没改）。

幂等：以当前文件为底，先判定匾区状态——
  · 与「右起」渲染的匾逐像素相符（匾心平均绝对差 < 3 级）：已处理，打印原因后跳过（rc=0）；
  · 与「左起」旧版渲染相符：只把字所在的块换成右起排版（匾框、漆底、泥金线与旧版逐像素同一渲染，不动）；
  · 都不符但匾区偏亮（最初原图的浅棕说明牌）：整块换匾（外沿 1.5px 羽化贴进画里）；
  · 其他情况（被别的东西改过）：报告后退出（rc=1），不写文件。
所以日后可以直接对仓库文件运行；渲染确定性（固定种子），同一输入两次运行输出逐字节相同。
用法：
  python3 tools/art/fix_bg_signs.py                          # 就地处理 SIGNS 里的每张图（已处理过则跳过）
  python3 tools/art/fix_bg_signs.py --out /tmp/cand.jpg      # 只出候选（SIGNS 第一项），不动仓库文件
  python3 tools/art/fix_bg_signs.py --src A.jpg --out B.jpg
"""
import argparse
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, JpegImagePlugin

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fix_bg_customs_jar import write_jpeg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = os.path.expanduser(os.environ.get("NK1_FONT_SRC", "~/tmp/nk1-art-work/fonts_src")) + "/MaShanZheng-Regular.ttf"
if not os.path.isfile(FONT):
    FONT = os.path.join(ROOT, "assets", "fonts", "MaShanZheng-Regular.ttf")
# (文件, 牌外框 x0,y0,x1,y1（原图像素，含浅色描边）, 匾文（按读序）)
SIGNS = [
    ("assets/bg_customs_room.jpg", (1283, 115, 1719, 297), "市舶抽解"),
]
LACQUER = np.array((0.20, 0.095, 0.060), np.float32)
FRAME = np.array((0.30, 0.16, 0.095), np.float32)
GOLD = np.array((0.74, 0.58, 0.30), np.float32)
MATCH_MAD = 3.0            # 匾心与渲染的平均绝对差（8 位级）低于此视为同一块匾
ORIG_SIGN_LUMA = 52.0      # 匾区平均亮度高于此视为最初原图的浅棕说明牌（黑漆匾 ≈44，原牌 ≈60）
KEEP = [("市舶司大罐", (1048, 496, 1136, 584))]   # 必须与输入逐字节一致的区域（自检用）


def plaque(w, h, text, seed=1255, rtl=True):
    """渲染匾。text 按读序给；rtl=True 时右起排（第一个字在最右），rtl=False 为旧版左起排。"""
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
    # 匾文：马善政泥金，整行居中；右起时从右往左一个字一个字排（字距、字宽与旧版相同）
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    fs = int(h * 0.44)
    font = ImageFont.truetype(FONT, fs)
    spacing = int(fs * 0.22)
    widths = [d.textbbox((0, 0), ch, font=font)[2] - d.textbbox((0, 0), ch, font=font)[0] for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    if rtl:
        x = (w + total) / 2
        for ch, cw in zip(text, widths):
            x -= cw
            bb = d.textbbox((0, 0), ch, font=font)
            d.text((x - bb[0], (h - (bb[3] - bb[1])) / 2 - bb[1]), ch, font=font, fill=255)
            x -= spacing
    else:
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


def edge_alpha(w, h):
    """贴进画里的羽化：外沿 1.5px 从 0 升到 1。"""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    return np.clip(edge / 1.5, 0, 1)


def block_box(mask, off, size):
    """mask（局部坐标）为 True 的像素所在 8×8 块的并集外框（整图坐标，8 对齐，夹在图内）。"""
    ys, xs = np.nonzero(mask)
    x0 = (xs.min() + off[0]) // 8 * 8
    y0 = (ys.min() + off[1]) // 8 * 8
    x1 = min(-(-(xs.max() + off[0] + 1) // 8) * 8, size[0])
    y1 = min(-(-(ys.max() + off[1] + 1) // 8) * 8, size[1])
    return int(x0), int(y0), int(x1), int(y1)


def fix_one(src_path, out_path, box, text):
    im = Image.open(src_path)
    cur = np.asarray(im.convert("RGB"))
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    region = cur[y0:y1, x0:x1].astype(np.float32) / 255.0
    a = edge_alpha(w, h)
    core = a >= 1
    p_new = plaque(w, h, text, rtl=True)
    p_old = plaque(w, h, text, rtl=False)
    mad_new = float(np.abs(region - p_new)[core].mean() * 255)
    mad_old = float(np.abs(region - p_old)[core].mean() * 255)
    luma = float((region[core] @ np.array([0.299, 0.587, 0.114], np.float32)).mean() * 255)
    name = os.path.basename(src_path)
    print("  %s：匾区与右起渲染差 %.2f 级、与左起旧版差 %.2f 级，匾区均亮 %.1f" % (name, mad_new, mad_old, luma))
    if mad_new < MATCH_MAD:
        print("  已是右起横排的「%s」匾，跳过，未写文件。" % text)
        return 0
    if mad_old < MATCH_MAD:
        state = "旧版左起横排匾 → 只换字所在的块"
        changed = np.abs(p_new - p_old).max(-1) > 0
        out = region.copy()
        out[core] = p_new[core]
    elif luma > ORIG_SIGN_LUMA:
        state = "最初原图的说明牌 → 整块换匾"
        changed = np.ones((h, w), bool)
        out = region * (1 - a[..., None]) + p_new * a[..., None]
    else:
        print("  匾区既不像右起/左起渲染的匾，也不像最初的说明牌，可能被别的改动覆盖过；未写文件。")
        return 1
    new = cur.copy()
    new[y0:y1, x0:x1] = (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)
    blk = block_box(changed, (x0, y0), im.size)
    sampling = JpegImagePlugin.get_sampling(im)
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "out.jpg")
        how = write_jpeg(src_path, im, new, blk, tmp)
        after = np.asarray(Image.open(tmp).convert("RGB"))
        outside = np.ones(cur.shape[:2], bool)
        outside[blk[1]:blk[3], blk[0]:blk[2]] = False
        same_outside = bool(np.array_equal(after[outside], cur[outside]))
        if not same_outside and sampling == 0:
            print("  嵌回后块外像素与输入不一致（%s），未写文件。" % how)
            return 1
        shutil.copyfile(tmp, out_path)
    diff = np.abs(after.astype(np.int16) - cur.astype(np.int16)).max(-1)
    print("  %s：%s；写出 %s（%s）" % (name, state, out_path, how))
    print("  改动块 %s；块外变动像素 %d；块内平均绝对差 %.2f"
          % (blk, int((diff[outside] > 0).sum()), float(diff[~outside].mean())))
    for label, (kx0, ky0, kx1, ky1) in KEEP:
        eq = np.array_equal(after[ky0:ky1, kx0:kx1], cur[ky0:ky1, kx0:kx1])
        print("  %s（%d,%d)-(%d,%d) 与输入逐字节一致：%s" % (label, kx0, ky0, kx1, ky1, "是" if eq else "否"))
    reg2 = after[y0:y1, x0:x1].astype(np.float32) / 255.0
    print("  写后匾区与右起渲染差 %.2f 级、与左起旧版差 %.2f 级"
          % (float(np.abs(reg2 - p_new)[core].mean() * 255), float(np.abs(reg2 - p_old)[core].mean() * 255)))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", default=None, help="输入图（默认 SIGNS 里的仓库文件）；给了就只处理 SIGNS 第一项")
    ap.add_argument("--out", default=None, help="输出路径（默认与输入相同，即就地）")
    args = ap.parse_args(argv)
    rc = 0
    for i, (rel, box, text) in enumerate(SIGNS):
        if (args.src or args.out) and i > 0:
            break
        src = args.src or os.path.join(ROOT, rel)
        rc = max(rc, fix_one(src, args.out or src, box, text))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
