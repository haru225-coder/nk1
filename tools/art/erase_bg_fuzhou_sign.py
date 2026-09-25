#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：抹掉 bg_fuzhou_yamen.jpg 左上角的伪界面牌（2026-09-26 02 截图点验发现）。

原画左上角天空与屋檐交界处，AI 出图带进来一块赭边半透明牌「进士题名 / 历年名录」，福州港页上像漏掉的控件。
牌子悬在半空、背后是主殿屋顶左端与左侧树冠，换成匾反而更怪（与 fix_bg_signs.py 的做法不同），所以整块抹掉，
改成「树冠挡住屋角」：

1. 补区 = 牌子暖色描边外框（实测 x 124–354、y 242–368）外扩；上沿提到 y 224，把牌子上方悬空的一排屋脊兽一并盖掉。
2. 左半：以补区左沿为轴镜像左侧紧邻的树冠与屋檐（画面左边只剩 117 像素，全取）。
3. 右半：取左上角最密的一簇枝叶，水平翻转，让最密的一列落在右沿，盖住主殿屋顶被截断的左端。
4. 两半之间 60 像素交叉淡化；补区外沿 8 像素高斯羽化。取样都是原画真实像素，雨丝与颗粒自然一致。

幂等：以 git 里 HEAD 的原图为底（git show 只读）；取不到 git 时退回当前文件，但先查补区里是否还有牌子的暖色描边，
没有就说明已修过，直接退出，以免叠画。
用法：python3 tools/art/erase_bg_fuzhou_sign.py
"""
import io
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REL = "assets/bg_fuzhou_yamen.jpg"
SIGN = (124, 242, 354, 368)        # 牌子暖色描边外框（原图 1920×1080 像素）
X0, Y0, X1, Y1 = 117, 224, 361, 375
SEAM = 60
FEATHER = 8


def _warm_px(a):
    sub = a[SIGN[1]:SIGN[3], SIGN[0]:SIGN[2]]
    return int((((sub[..., 0] - sub[..., 2]) > 40 / 255) & (sub[..., 0] > 120 / 255)).sum())


def _source():
    try:
        blob = subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + REL], capture_output=True, check=True).stdout
        img = Image.open(io.BytesIO(blob)).convert("RGB")
        a = np.asarray(img, np.float32) / 255.0
        if _warm_px(a) > 500:
            return a
    except Exception:
        pass
    a = np.asarray(Image.open(os.path.join(ROOT, REL)).convert("RGB"), np.float32) / 255.0
    if _warm_px(a) <= 500:
        print("补区里已没有牌子的暖色描边，视为已修过，退出")
        sys.exit(0)
    return a


def _blur(x, r):
    u8 = Image.fromarray((np.clip(x, 0, 1) * 255).astype(np.uint8))
    return np.asarray(u8.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0


def main():
    a = _source()
    h, w = Y1 - Y0, X1 - X0
    half = X0
    left = a[Y0:Y1, 0:X0][:, ::-1]
    dense = a[18:18 + h, 0:w - half][:, ::-1]
    patch = np.concatenate([left, dense], axis=1)
    t = np.linspace(0, 1, SEAM)[None, :, None]
    patch[:, half - SEAM // 2:half + SEAM // 2] = left[:, -SEAM:] * (1 - t) + dense[:, :SEAM] * t

    full = a.copy()
    full[Y0:Y1, X0:X1] = np.clip(patch, 0, 1)
    fm = np.zeros(a.shape, np.float32)
    fm[Y0:Y1, X0:X1] = 1
    fm = _blur(fm, FEATHER)[..., :1]
    fm = np.where(fm > 0.5, np.minimum(1, (fm - 0.5) * 2 + 0.5), fm)
    out = a * (1 - fm) + full * fm

    left_px = _warm_px(out)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(ROOT, REL), quality=93, subsampling=0)
    print(f"写出 {REL}；补区内残留暖色描边像素 {left_px}（修前 {_warm_px(a)}）")


if __name__ == "__main__":
    main()
