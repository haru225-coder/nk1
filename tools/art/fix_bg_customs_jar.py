#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：市舶司内景的青花大罐改成龙泉窑粉青素面大罐（史实纠偏）。

来由：bg_customs_room.jpg（南宋末泉州市舶司内景，纲首过场第 2 镜 / 衙门内页底图）后排矮柜上摆着一只
青花大罐（外框约 (1055,503)-(1134,577)），钴蓝浓艳、腹部满绘开光缠枝，是至正型乃至明清民窑的样子，
比 1277/1285 的剧情年代晚六七十年以上。陶瓷考证的结论：改成龙泉窑粉青（南宋晚期至元初，白胎厚釉）
素面大罐——新安船（1323）两万件中国瓷里龙泉青瓷约占六成，是当时泉州港最体面的瓷器；罐形沿用原轮廓
（直口短颈圆鼓腹 = 荷叶盖罐去盖的罐身，遂宁金鱼村窖藏有南宋大件实物），改釉不改形。
罐左侧那只深色撇口瓶、案上两只小罐实测不带青花（深色瓶的「蓝」全在 V<0.10 的暗部，是阴影色偏；
小罐 B-R 为 -26/-17 的暖灰绿），一律不动。

做法：
1. 罐身 mask：按逐行实测的外轮廓节点（左右边界，亚像素）4 倍超采样求覆盖率 C；融合用的 alpha
   再往里收 0.5px、羽化 0.6px，外轮廓那一圈原本就是「罐 + 红墙/柜面」的混色，留原像素，免得起光晕或硬边。
2. 明暗：罐身亮度取局部 80 分位（白地才反映受光，蓝花是暗的）再做 mask 内归一化模糊，得到「白地等效受光」；
   按回转体轮廓求每点表面法向，用设计光源（左上前方，对原罐白地网格搜索取 R² 最高的一组）求干净球面明暗，
   线性标定到白地受光；原图大尺度残差按 0.35 叠回，γ=1.35 对比、轮廓边掠射压暗。青花纹样的高频对比全部压掉。
   口沿—颈—肩：取最大腹径那一行同一经线的亮度 × 逐行比例（比例取原罐逐行受光的实测：唇面亮、唇下阴影、
   颈部留唇口投影、颈肩转折低于唇口）；圈足按原图米灰带逐行明暗。
3. 釉层：低频釉层厚薄场（肩部釉薄偏淡、下腹近足积釉偏深、厚薄不匀）+ 两道极淡竖向垂流（沿经线走，积釉处色深）；
   中频肌理借同画原生灰绿釉罐（前景麻绳罐）腹部的釉面起伏（旋坯横痕、积釉、流釉，截掉它自己的高光与铁斑），
   按受光加权铺上——同一支「笔」画的，比合成噪点更像这张画；不叠均匀噪点。
4. 着色：按场景白点乘釉的本色。场景白点取原罐白地像素（原图 B-R<2 的同批像素）的平均色 (1, .958, .858)，
   即「白瓷在这盏暖光下」的样子；粉青本色取 G/R ≈1.07、B/R ≈1.00（本色守 G>R、B≈R），画面上约 G/R 1.03、B/R 0.85。
   罐身亮度压到原白地的 ≈0.93 倍（青釉不能比它换掉的白瓷还亮）。积釉处色度加深、釉薄处与受光处色度变淡；
   右侧暗部受红墙反光略偏橄榄暖灰。
5. 亮釉：左上肩柔光强度减半（r1 的 0.40→0.20）、σ 5→2.8 收窄、改带光源色（中性略暖）；在原罐镜面点的位置
   补一块 2–3px 暖白窗光（主点 + 贴着的窗棂下格，L* ≈65，同画其他亮釉器都有）和一粒淡的釉面亮点；
   左轮廓内一道窗光反射、右轮廓内一道极淡红墙反光；唇口一粒暖白受光点。
   口沿釉薄泛白（出筋）一道淡亮线落在唇面 505 行；颈肩转折只留一道比唇口暗的 0.4px 淡线，免得颈部像套了个圆筒。
   不画开片、不画火石红、不画莲瓣（按南宋晚期白胎粉青素面做）。
6. 写出：改动只落在罐所在的 8×8 块里。改过的块按块对齐裁出，用原图同一套量化表编码，再用
   jpegtran -drop 无损嵌回原图字节流——块外像素与原图逐字节一致；没有 jpegtran 时退回 PIL 同量化表整图重编码
   （实测整图重编码平均绝对差 ≈0.002）。
轮次：r1 首版；r2 按两份评审改第 3–5 步（白点、亮度、镜面高光、中频釉层肌理、口沿），mask/羽化/写出不变。

幂等：先量输入里罐身 mask 内（V≥0.10）的蓝像素占比，原图 10.0%、处理后 0.0%；低于 3% 视为已经处理过
（或罐已不是青花），打印原因后跳过、不写任何文件。所以日后可以直接对仓库文件运行。渲染用固定随机种子，
同一输入两次运行输出逐字节相同。输出与输入同路径时必须加 --in-place 才写。

用法：
  python3 tools/art/fix_bg_customs_jar.py --in-place           # 就地处理 assets/bg_customs_room.jpg（已处理过则跳过）
  python3 tools/art/fix_bg_customs_jar.py --out /tmp/cand.jpg  # 只出候选，不动仓库文件
  python3 tools/art/fix_bg_customs_jar.py --src A.jpg --out B.jpg
自检数字（蓝像素占比前后、mask 外平均绝对差、边界 ΔE、白点比、肌理 HF3/MF9、L* 峰值）每次运行都会打印。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import warnings

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from PIL import Image, JpegImagePlugin

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_SRC = os.path.join(ROOT, "assets", "bg_customs_room.jpg")
DEFAULT_OUT = DEFAULT_SRC
SIZE = (1920, 1080)

# 罐外轮廓：y -> (左, 右)，原图像素坐标（像素中心在 +0.5），逐行实测后取节点，中间线性插值
KNOTS = [
    (503.6, 1073.6, 1113.6),   # 口沿上缘
    (504.5, 1073.2, 1115.0),
    (506.5, 1073.3, 1114.6),
    (507.5, 1074.3, 1112.8),   # 口沿下缘
    (508.5, 1075.2, 1112.2),   # 颈
    (513.0, 1075.2, 1113.4),
    (515.5, 1074.8, 1114.0),
    (517.0, 1073.6, 1115.4),   # 颈肩转折
    (518.0, 1071.8, 1116.0),
    (519.0, 1069.6, 1116.6),
    (520.0, 1067.4, 1118.8),
    (521.0, 1065.6, 1119.8),
    (522.0, 1064.2, 1121.8),
    (524.0, 1061.6, 1124.8),
    (526.0, 1059.6, 1126.9),
    (528.0, 1058.4, 1128.5),
    (530.0, 1057.3, 1130.4),
    (533.0, 1056.2, 1131.8),
    (536.0, 1055.6, 1132.8),   # 最大腹径
    (541.0, 1055.5, 1133.1),
    (546.0, 1056.2, 1133.2),
    (550.0, 1057.2, 1132.7),
    (555.0, 1058.4, 1131.4),
    (560.0, 1060.2, 1129.4),
    (564.0, 1062.4, 1127.0),
    (568.0, 1065.2, 1124.4),
    (571.0, 1068.0, 1121.2),
    (573.2, 1069.0, 1116.0),   # 下腹收进圈足
    (574.0, 1068.8, 1114.0),   # 圈足
    (576.6, 1069.6, 1113.0),
]
RIM_TOP, NECK_SHOULDER_Y = 503.6, 517.4
FOOT_Y = 573.2
WORK = (1032, 488, 1152, 592)          # 处理窗（含模糊余量），8 对齐

# ---- 明暗（r1 标定，不变） ----
CONTRAST = 1.35             # 球面明暗对比（γ，对均值）
LIGHT_DIR = (-0.35, -0.42, 0.84)   # 左上前方来光（屏幕 x 右正、y 下正、z 朝观者）；对原罐白地受光网格搜索 R²=0.75 的最优
LIGHT_WRAP, LIGHT_POW = 0.10, 2.0
LIMB_L, LIMB_R = 0.35, 0.15        # 轮廓边压暗：左侧掠射反射身后暗柜更深，右侧受红墙反光浅一些
RESID_MIX = 0.35            # 原图大尺度受光残差叠回比例
# 口沿—颈—肩逐行明暗：相对最大腹径那一行（y=REF_ROW，正对观者）同一经线的亮度。取自原罐逐行受光（中左段 p75）
# 的实测比例：原图唇面 505–506 行是腹身的 1.45–1.52 倍、唇下 507 行 0.83、颈肩转折 517 行 1.47。
# r2 调整：唇面照原图抬回（r1 比原图暗 7 L*）；颈部留唇口投影（0.86–0.92）；颈肩转折只到 1.06，
# 明显低于唇口，免得「颈部像套了个圆筒」（r1 颈肩线比唇口还亮 4 L*）。
REF_ROW = 541
ROW_REL = {503: 0.62, 504: 1.00, 505: 1.46, 506: 1.36, 507: 0.80, 508: 0.86, 509: 0.92, 510: 0.92,
           511: 0.89, 512: 0.88, 513: 0.88, 514: 0.87, 515: 0.86, 516: 0.94, 517: 1.06, 518: 1.03,
           519: 0.95}
TOP_BLEND = (518.5, 523.0)  # 这一段里逐行结构渐变回球面明暗
# 圈足逐行（相对腹身，r1 标定）：573 腹足间暗缝；圈足与原图米灰带同亮
ROW_MOD = {573: 0.82, 574: 0.90, 575: 1.02, 576: 0.96}

# ---- 釉层厚薄与肌理（r2：有结构的中频起伏，不叠均匀噪点） ----
THICK_DARK = 0.12           # 釉厚一档压暗比例（积釉深、釉薄淡）
THICK_NOISE = 0.55          # 厚薄不匀幅度（相对厚薄场）
THICK_SIGMA = (3.0, 4.5)    # 厚薄不匀的模糊尺度 (x, y)：顺着釉往下流的方向略拉长（拉太长成瓜棱竖纹，试过）
POOL = 0.16                 # 下腹近足积釉额外压暗
# 竖向垂流：(经线位置 u, 起点 y, 长度, 半宽 px, 厚度)，沿经线走，积釉处色深，受光一侧起一点棱
DRIPS = [(-0.30, 528.0, 26.0, 1.0, 0.75), (0.31, 533.0, 22.0, 0.9, 0.55)]
DRIP_RIDGE = 0.05           # 垂流受光棱的明暗幅度（厚 1.4/棱 0.10 时成一道直竖线，像瓜棱，试过）
FLOW_AMP = 0.012            # 细流纹（竖向）幅度
GRAIN_AMP = 0.0             # 合成颗粒：r2 起不用（肌理改借原生罐，HF3 以同画原生青釉罐 ≈3% 为准）
# 借同画原生灰绿釉罐（前景麻绳罐）腹部的釉面肌理：同一支「笔」画的积釉、旋坯痕与流釉，比合成噪点像这张画。
# 取其亮度相对 σ3 平滑的起伏，截掉亮端（它自己的高光点，位置与本罐光路不合）和最暗的铁斑，再铺到罐身。
TEX_SRC = (1060, 938, 1140, 990)      # 原生罐腹部干净区（避开麻绳与提梁）
TEX_DST = (1054.0, 518.0, 1135.0, 575.0)
TEX_AMP = 2.5                         # 相对原生罐自身起伏的倍数（原生罐所在处更亮、受光更平，本罐暗处要放大才同感）
TEX_LIT = (0.5, 1.2)                  # 肌理随受光：amp × (a + b × 归一化光照)
TEX_CLIP = (-0.15, 0.05)
TEX_SOFT = 1.0                        # 借来的肌理先轻糊，只留中频（1px 级细碎会被 JPEG 放大，HF3 超标）

# ---- 着色：场景白点 × 粉青本色 ----
TARGET_LUMA = 39.5          # 罐身（C>0.99）平均亮度目标；白地同批像素上约为原白地的 0.9 倍
SCENE_WHITE = np.array((1.0, 0.958, 0.858), np.float32)   # 原罐白地同批像素（原图 B-R<2）的平均色：暖光下的白
ALBEDO = np.array((1.0, 1.105, 1.00), np.float32)         # 粉青本色（相对 R）：G>R、B≈R；落盘后白地同批像素折本色 ≈1.07/1.00
CHROMA_THICK = 0.50         # 积釉色度加深 / 釉薄色度变淡（按厚薄场）
CHROMA_HI_DROP = 0.45       # 受光最亮处色度减淡（亮釉反光带光源色）
WARM_RIGHT = 0.07           # 右侧暗部受红墙反光：R 抬、B 压的比例

# ---- 亮釉反光 ----
GLOW_CENTER, GLOW_SIGMA, GLOW_MIX = (1079.0, 531.0), 2.8, 0.20       # 左上肩柔光：r1 σ5/0.40 → 强度减半、收窄
GLOW_RGB = np.array((116.0, 112.0, 100.0), np.float32)                # 光源色（中性略暖），不带釉色
SPEC_RGB = np.array((166.0, 160.0, 144.0), np.float32)                # 窗光镜面点：中性略暖
SPECS = [(1078.6, 531.2, 1.00, 1.45, 0.98),       # (x, y, σx, σy, 强度)：主点，原罐镜面点位置；窗形略竖长
         (1079.1, 534.5, 0.65, 0.75, 0.40)]       # 窗棂下格：贴着主点，读成一块断开的窗影而不是两颗点
SPEC_HALO = (1078.8, 532.2, 2.1, 0.20)            # 镜面点四周的一圈釉光：(x, y, σ, 强度)
# 釉面微起伏在高光带里挑出的细碎亮点：只留一粒淡的（原罐自己在此处也有一粒白点）；r2 试过四粒，散成星点像贴片
GLINTS = [(1093.3, 536.5, 0.70, 0.22)]            # (x, y, σ, 强度)
LIP_SPEC = (1090.8, 505.2, 1.3, 0.5, 0.45)        # 唇口受光点（原图同位置有一粒暖白）
LIP_RGB = np.array((142.0, 134.0, 118.0), np.float32)
LIMB_REFL = (-0.84, 526.0, 563.0, 0.75, 0.46)     # 左轮廓内竖向窗光反射：(u, y 起, y 止, 半宽, 强度)
LIMB_DARK = (-0.66, 1.3, 0.05)                    # 窗影内侧一道暗柜反射：(u, 半宽, 压暗)（0.10 时与垂流凑成一排竖纹）
WALL_REFL = (0.84, 530.0, 566.0, 0.9, 0.28)       # 右轮廓内红墙反光：(u, y 起, y 止, 半宽, 强度)
WALL_RGB = np.array((1.25, 0.95, 0.80), np.float32)   # 红墙反光色（乘在当地亮度上）
RIM_LINE, SHOULDER_LINE = 0.35, 0.10              # 口沿出筋亮线 / 颈肩转折淡线（r1 为 0.50/0.35）
RIM_LINE_Y = (504.6, 505.2, 505.9, 506.6)         # 出筋亮线落在唇面最亮的 505 行（r1 落在 504 行，偏上）

BLUE_HUE = (190.0, 250.0)
BLUE_SAT = 0.18
BLUE_VMIN = 0.10
SKIP_BELOW = 0.03                       # mask 内蓝像素占比低于此值视为已处理
TEX_RECT = (1068, 515, 1122, 565)       # 肌理量测框（评审口径）
TEX_REF = (1050, 915, 1130, 980)        # 同画原生灰绿釉罐（前景麻绳罐）肌理参照框


# ---------- 小工具 ----------
def gauss1d(s):
    r = max(1, int(np.ceil(3 * s)))
    x = np.arange(-r, r + 1, dtype=np.float32)
    k = np.exp(-0.5 * (x / s) ** 2)
    return k / k.sum()


def blur_xy(img, sx, sy):
    """可分离高斯模糊（边缘复制），x/y 可不同尺度；img 为 2D 或 HxWxC。"""
    out = img.astype(np.float32)
    extra = ((0, 0),) * (img.ndim - 2)
    if sy > 0:
        k = gauss1d(sy)
        r = len(k) // 2
        p = np.pad(out, ((r, r), (0, 0)) + extra, mode="edge")
        out = sum(k[i] * p[i:i + img.shape[0]] for i in range(len(k)))
    if sx > 0:
        k = gauss1d(sx)
        r = len(k) // 2
        p = np.pad(out, ((0, 0), (r, r)) + extra, mode="edge")
        out = sum(k[i] * p[:, i:i + img.shape[1]] for i in range(len(k)))
    return out if (sx > 0 or sy > 0) else out.copy()


def blur(img, s):
    return blur_xy(img, s, s)


def nblur(img, m, s):
    """mask 内归一化模糊：只让 mask 里的像素互相平均，不把背景拉进来。"""
    mm = m if img.ndim == 2 else m[..., None]
    return blur(img * mm, s) / np.maximum(blur(mm, s), 1e-4)


def local_pct(img, m, r, q):
    pad = np.pad(np.where(m, img, np.nan), r, mode="constant", constant_values=np.nan)
    win = sliding_window_view(pad, (2 * r + 1, 2 * r + 1)).reshape(img.shape[0], img.shape[1], -1)
    with np.errstate(all="ignore"), warnings.catch_warnings():
        warnings.simplefilter("ignore")
        out = np.nanpercentile(win, q, axis=-1)
    return np.where(np.isnan(out), img, out)


def box_mean(x, r):
    k = 2 * r + 1
    p = np.pad(x, r, mode="edge")
    c = np.pad(p.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def luma(rgb):
    return rgb @ np.array([0.299, 0.587, 0.114], np.float32)


def hsv_blue(rgb255, vmin=0.0):
    r = rgb255.astype(np.float32) / 255.0
    mx = r.max(-1)
    mn = r.min(-1)
    d = mx - mn
    sat = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    R, G, B = r[..., 0], r[..., 1], r[..., 2]
    h = np.zeros_like(mx)
    nz = d > 1e-6
    dd = np.maximum(d, 1e-6)
    rr = (mx == R) & nz
    gg = (mx == G) & nz & ~rr
    bb = (mx == B) & nz & ~rr & ~gg
    h[rr] = (60 * ((G - B) / dd) % 360)[rr]
    h[gg] = (60 * ((B - R) / dd) + 120)[gg]
    h[bb] = (60 * ((R - G) / dd) + 240)[bb]
    return (h >= BLUE_HUE[0]) & (h <= BLUE_HUE[1]) & (sat > BLUE_SAT) & (mx >= vmin)


def srgb_to_lab(rgb255):
    c = rgb255.astype(np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > (6 / 29) ** 3, np.cbrt(xyz), xyz / (3 * (6 / 29) ** 2) + 4 / 29)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], -1)


def texture(img, rect):
    """评审口径的肌理：亮度减 3×3 / 9×9 盒均值后的标准差 ÷ 框内均亮。"""
    Y = luma(img.astype(np.float32)).astype(np.float64)
    x0, y0, x1, y1 = rect
    m = Y[y0:y1, x0:x1].mean()
    hf = (Y - box_mean(Y, 1))[y0:y1, x0:x1].std() / m
    mf = (Y - box_mean(Y, 4))[y0:y1, x0:x1].std() / m
    return float(m), float(hf), float(mf)


# ---------- 几何 ----------
class Geo:
    """处理窗内的覆盖率、alpha 与回转体法向。"""

    def __init__(self, work=WORK, ss=4):
        self.x0, self.y0, self.x1, self.y1 = work
        self.h, self.w = self.y1 - self.y0, self.x1 - self.x0
        ky = np.array([k[0] for k in KNOTS])
        kl = np.array([k[1] for k in KNOTS])
        kr = np.array([k[2] for k in KNOTS])
        self.ky, self.kl, self.kr = ky, kl, kr
        self.C = self._cover(0.0, ss)                 # 真实覆盖率
        inner = self._cover(0.5, ss)                  # 向内收 0.5px
        self.A = np.clip(blur(inner, 0.6), 0, 1) * (self.C > 0)   # 融合 alpha，不越出轮廓
        self.A[self.A < 1.0 / 512] = 0.0
        yc = np.arange(self.h, dtype=np.float32) + 0.5 + self.y0
        xc = np.arange(self.w, dtype=np.float32) + 0.5 + self.x0
        self.Y, self.X = np.meshgrid(yc, xc, indexing="ij")
        L = np.interp(yc, ky, kl)
        R = np.interp(yc, ky, kr)
        ctr = (L + R) / 2
        hw = np.maximum((R - L) / 2, 1.0)
        # 半径对 y 的导数（先按 1px 平滑，免得节点折线产生台阶）
        fine = np.arange(ky[0] - 4, ky[-1] + 4, 0.25)
        hw_f = (np.interp(fine, ky, kr) - np.interp(fine, ky, kl)) / 2
        k = gauss1d(4.0)
        hw_f = np.convolve(np.pad(hw_f, len(k) // 2, mode="edge"), k, mode="valid")
        dr = np.gradient(hw_f, fine)
        drdy = np.interp(yc, fine, dr)
        self.u = np.clip((self.X - ctr[:, None]) / hw[:, None], -1.0, 1.0)
        nz = np.sqrt(np.clip(1 - self.u ** 2, 0, 1))
        ny = -np.repeat(drdy[:, None], self.w, 1) * nz        # 回转体：法向 y 分量 ∝ -r'(y)·cosθ
        nrm = np.sqrt(self.u ** 2 + ny ** 2 + nz ** 2) + 1e-6
        self.nx, self.ny, self.nz = self.u / nrm, ny / nrm, nz / nrm
        self.ctr, self.hw = ctr, hw

    def _cover(self, shrink, ss):
        ys = (np.arange(self.h * ss) + 0.5) / ss + self.y0
        xs = (np.arange(self.w * ss) + 0.5) / ss + self.x0
        L = np.interp(ys, self.ky, self.kl) + shrink
        R = np.interp(ys, self.ky, self.kr) - shrink
        ok = (ys >= self.ky[0] + shrink) & (ys <= self.ky[-1] - shrink * 0.6)
        m = (xs[None, :] >= L[:, None]) & (xs[None, :] <= R[:, None]) & ok[:, None]
        return m.reshape(self.h, ss, self.w, ss).mean(axis=(1, 3)).astype(np.float32)

    def full(self, arr, fill=0.0):
        out = np.full(SIZE[::-1] + arr.shape[2:], fill, arr.dtype)
        out[self.y0:self.y1, self.x0:self.x1] = arr
        return out

    def meridian_x(self, u0):
        """经线 u=u0 在每行的屏幕 x（回转体正视，经线即 u 为常数）。"""
        return (self.ctr + u0 * self.hw)[:, None]


# ---------- 核心 ----------
def blue_stats(img, geo):
    win = img[geo.y0:geo.y1, geo.x0:geo.x1]
    m = geo.C > 0.99
    return (float(hsv_blue(win)[m].mean()), float(hsv_blue(win, BLUE_VMIN)[m].mean()))


def glaze_thickness(geo, rng):
    """釉层厚薄场 T（负=釉薄、正=积釉）与垂流受光棱 ridge。"""
    Y, X = geo.Y, geo.X
    shoulder = smoothstep(517.5, 521.0, Y) * (1 - smoothstep(527.0, 535.0, Y))
    pool = smoothstep(547.0, 571.0, Y)
    T = -0.8 * shoulder + 1.0 * pool
    n = blur_xy(rng.normal(0, 1, Y.shape).astype(np.float32), *THICK_SIGMA)
    n /= n.std() + 1e-6
    T = T + THICK_NOISE * n * (0.45 + 0.55 * smoothstep(524.0, 556.0, Y))
    ridge = np.zeros_like(Y)
    for u0, y0, length, w, a in DRIPS:
        xc = geo.meridian_x(u0) + 0.6 * np.sin((Y - y0) / 6.5)
        ww = w * (1 + 0.6 * smoothstep(y0, y0 + length, Y))            # 往下越流越宽，末端成泪滴
        along = smoothstep(y0, y0 + 5.0, Y) * (1 - smoothstep(y0 + length - 3.0, y0 + length + 1.5, Y))
        along = along * (0.7 + 0.3 * smoothstep(y0, y0 + length, Y))
        prof = np.exp(-0.5 * ((X - xc) / ww) ** 2) * along
        T = T + a * prof
        ridge = ridge - a * np.gradient(prof, axis=1) * ww           # 左坡朝窗 → 亮，右坡 → 暗
    return T, ridge


def borrowed_texture(src, geo):
    """同画原生青釉罐的釉面起伏（相对量），重采样铺到本罐罐身范围；范围外为 0。"""
    x0, y0, x1, y1 = TEX_SRC
    Y = luma(src[y0:y1, x0:x1].astype(np.float32))
    t = Y / np.maximum(blur(Y, 3.0), 1.0) - 1.0
    t = np.clip(t, *TEX_CLIP)
    t = blur(t, TEX_SOFT)
    t -= t.mean()
    dx0, dy0, dx1, dy1 = TEX_DST
    # 目标像素中心映射回源坐标，双线性取样
    sx = (geo.X - dx0) / (dx1 - dx0) * (x1 - x0) - 0.5
    sy = (geo.Y - dy0) / (dy1 - dy0) * (y1 - y0) - 0.5
    inside = (sx >= 0) & (sx <= x1 - x0 - 1) & (sy >= 0) & (sy <= y1 - y0 - 1)
    sx = np.clip(sx, 0, x1 - x0 - 1.001)
    sy = np.clip(sy, 0, y1 - y0 - 1.001)
    ix, iy = sx.astype(int), sy.astype(int)
    fx, fy = sx - ix, sy - iy
    v = (t[iy, ix] * (1 - fx) * (1 - fy) + t[iy, ix + 1] * fx * (1 - fy)
         + t[iy + 1, ix] * (1 - fx) * fy + t[iy + 1, ix + 1] * fx * fy)
    return np.where(inside, v, 0.0).astype(np.float32)


def render(src, geo, seed=1277):
    win = src[geo.y0:geo.y1, geo.x0:geo.x1].astype(np.float32)
    lum = luma(win)
    inner = geo.C > 0.99
    rng = np.random.default_rng(seed)
    # 1) 白地等效受光：局部 80 分位压掉蓝花，再 mask 内模糊
    env = local_pct(lum, inner, 3, 80)
    env = nblur(env, inner.astype(np.float32), 3.0)
    # 2) 设计光源求干净球面明暗，线性标定到原图白地受光；原图大尺度残差按比例叠回
    l = np.array(LIGHT_DIR, np.float32)
    l /= np.linalg.norm(l)
    ndl = geo.nx * l[0] + geo.ny * l[1] + geo.nz * l[2]
    shade = np.clip((ndl + LIGHT_WRAP) / (1 + LIGHT_WRAP), 0, 1) ** LIGHT_POW
    Amat = np.stack([np.ones_like(shade), shade], -1)
    coef, *_ = np.linalg.lstsq(Amat[inner], env[inner], rcond=None)
    fit = Amat @ coef
    resid = nblur(env - fit, inner.astype(np.float32), 8.0)
    I = fit + RESID_MIX * resid * smoothstep(519.0, 526.0, geo.Y)
    m0 = float(I[inner].mean())
    I = m0 * np.power(np.maximum(I, 1e-3) / m0, CONTRAST)
    edge = (1 - geo.nz) ** 1.5
    I = I * (1.0 - LIMB_L * edge * smoothstep(0.0, -0.6, geo.u) - LIMB_R * edge * smoothstep(0.0, 0.6, geo.u))
    # 3) 口沿—颈—肩：取最大腹径那一行同一经线的亮度（带左亮右沉与轮廓压暗）× 逐行比例；圈足逐行
    rows = np.arange(geo.h) + geo.y0
    ri = REF_ROW - geo.y0
    ref_u, ref_I = geo.u[ri], I[ri]
    keep = geo.C[ri] > 0.99
    Iref = np.interp(geo.u, ref_u[keep], ref_I[keep])
    rel = np.array([ROW_REL.get(int(y), 1.0) for y in rows], np.float32)[:, None]
    wt = 1 - smoothstep(TOP_BLEND[0], TOP_BLEND[1], geo.Y)
    I = I * (1 - wt) + Iref * rel * wt
    mod = np.array([ROW_MOD.get(int(y), 1.0) for y in rows], np.float32)
    I = I * mod[:, None]
    # 4) 釉层：厚薄场（肩薄、积釉、竖向不匀、垂流）→ 明暗；积釉近足再压一档
    T, ridge = glaze_thickness(geo, rng)
    body = smoothstep(518.0, 522.0, geo.Y) * (1 - smoothstep(FOOT_Y - 0.5, FOOT_Y + 0.8, geo.Y))
    I = I * (1.0 - THICK_DARK * T * body) * (1.0 + DRIP_RIDGE * ridge * body)
    I = I * (1.0 - POOL * smoothstep(552.0, FOOT_Y, geo.Y) * (geo.Y < FOOT_Y + 0.8))
    flow = blur_xy(rng.normal(0, 1, I.shape).astype(np.float32), 0.7, 3.5)
    flow /= flow.std() + 1e-6
    grain = blur(rng.normal(0, 1, I.shape).astype(np.float32), 0.8)
    grain /= grain.std() + 1e-6
    I = I * (1.0 + FLOW_AMP * flow * (0.4 + 0.6 * smoothstep(528.0, 566.0, geo.Y)) + GRAIN_AMP * grain)
    if TEX_AMP > 0:
        # 亮釉的面起伏主要在受光处借反光显出来：受光越强肌理越显（背光处只剩一半）
        lit = TEX_LIT[0] + TEX_LIT[1] * shade / max(float(shade[inner].max()), 1e-3)
        I = I * (1.0 + TEX_AMP * lit * borrowed_texture(src, geo) * body)
    # 5) 亮度：整体乘 k 使罐身均亮 = TARGET_LUMA；s 为归一化明暗（0 暗 / 1 亮）
    k = TARGET_LUMA / float(I[inner].mean())
    Ln = I * k
    lo, hi = np.percentile(I[inner], [4, 97])
    s = np.clip((I - lo) / (hi - lo), 0, 1)
    # 6) 着色：场景白点 × 粉青本色；积釉色深、釉薄/受光色淡
    base = SCENE_WHITE * ALBEDO
    base = base / float(luma(base))
    f = 1.0 + CHROMA_THICK * np.clip(T, -1.2, 1.5) * body - CHROMA_HI_DROP * smoothstep(0.65, 1.0, s)
    f = np.clip(f, 0.2, 1.8)[..., None]
    white = SCENE_WHITE / float(luma(SCENE_WHITE))
    ratio = white + f * (base - white)
    ratio = ratio / luma(ratio)[..., None]
    col = Ln[..., None] * ratio
    # 右侧暗部受红墙反光：偏橄榄暖灰
    t = smoothstep(0.15, 0.95, geo.u) * np.clip(1.2 - 1.6 * s, 0, 1)
    col *= np.stack([1 + WARM_RIGHT * t, 1 - 0.01 * t, 1 - 0.8 * WARM_RIGHT * t], -1)
    # 圈足：足墙釉薄、色淡偏灰，足端近露胎处略暖（原图这一圈是中性米灰 (48,48,44)）
    foot = smoothstep(FOOT_Y + 0.2, FOOT_Y + 1.0, geo.Y)[..., None]
    lum_c = luma(col)[..., None]
    warm = np.stack([np.ones_like(geo.Y), np.ones_like(geo.Y) * 0.985, np.ones_like(geo.Y) * 0.93], -1)
    warm = 1 + (warm - 1) * smoothstep(575.2, 576.4, geo.Y)[..., None]
    col = col * (1 - foot) + (lum_c + 0.4 * (col - lum_c)) * warm * foot
    # 7) 口沿出筋：唇沿釉薄泛白一道亮线；颈肩转折只留一道比唇口暗的细淡线
    thin = (Ln * 1.28)[..., None] * (white + 0.45 * (base - white)) / float(luma(white + 0.45 * (base - white)))
    r0, r1_, r2_, r3 = RIM_LINE_Y
    rim = smoothstep(r0, r1_, geo.Y) * (1 - smoothstep(r2_, r3, geo.Y))
    sh_y = NECK_SHOULDER_Y + 0.9 * (1 - np.clip(geo.u, -1, 1) ** 2)
    shoulder = np.exp(-0.5 * ((geo.Y - sh_y) / 0.40) ** 2) * smoothstep(0.98, 0.7, np.abs(geo.u))
    line = np.clip(RIM_LINE * rim + SHOULDER_LINE * shoulder, 0, 1)[..., None]
    col = col * (1 - line) + thin * line
    # 8) 左上肩柔光：光源色、强度为 r1 的一半、收窄
    g = np.exp(-0.5 * (((geo.X - GLOW_CENTER[0]) ** 2 + (geo.Y - GLOW_CENTER[1]) ** 2) / GLOW_SIGMA ** 2))
    g = (GLOW_MIX * g)[..., None]
    col = col * (1 - g) + GLOW_RGB * g
    # 9) 与油画同一种柔度：轻糊 0.5px（只在罐内平均）
    col = nblur(col, (geo.C > 0.5).astype(np.float32), 0.5)
    # 10) 亮釉反光（糊之后画，自带柔边）：环境反射（左窗影 + 内侧暗柜影、右红墙反光）、窗光镜面点、唇口受光点
    def band(u0, hw_r, ya=None, yb=None):
        b = np.exp(-0.5 * ((geo.X - geo.meridian_x(u0)) / hw_r) ** 2)
        if ya is not None:
            b = b * smoothstep(ya, ya + 6.0, geo.Y) * (1 - smoothstep(yb - 8.0, yb, geo.Y))
        return b * (geo.C > 0.5)
    u0, hw_r, amt = LIMB_DARK
    col = col * (1 - amt * band(u0, hw_r, 524.0, 566.0))[..., None]
    u0, ya, yb, hw_r, amt = LIMB_REFL
    a = (amt * band(u0, hw_r, ya, yb))[..., None]
    col = col * (1 - a) + (Ln * 1.75)[..., None] * white * a
    u0, ya, yb, hw_r, amt = WALL_REFL
    a = (amt * band(u0, hw_r, ya, yb))[..., None]
    col = col * (1 - a) + (Ln * 1.35)[..., None] * WALL_RGB / float(luma(WALL_RGB)) * a
    hx, hy, hs, hamt = SPEC_HALO
    a = (hamt * np.exp(-0.5 * ((geo.X - hx) ** 2 + (geo.Y - hy) ** 2) / hs ** 2))[..., None]
    col = col * (1 - a) + SPEC_RGB * 0.72 * a
    glints = [(x, y, s_, s_, a_) for x, y, s_, a_ in GLINTS]
    for (cx, cy, sx, sy, amt), rgb in ([(sp, SPEC_RGB) for sp in SPECS] + [(gl, SPEC_RGB) for gl in glints]
                                       + [(LIP_SPEC, LIP_RGB)]):
        a = amt * np.exp(-0.5 * (((geo.X - cx) / sx) ** 2 + ((geo.Y - cy) / sy) ** 2))
        a = a[..., None]
        col = col * (1 - a) + rgb * a
    A = geo.A[..., None]
    out = win * (1 - A) + col * A
    return np.clip(out + 0.5, 0, 255).astype(np.uint8), dict(coef=coef, I=I, T=T)


def changed_blocks_bbox(geo):
    ys, xs = np.nonzero(geo.A > 0)
    x0 = (xs.min() + geo.x0) // 8 * 8
    y0 = (ys.min() + geo.y0) // 8 * 8
    x1 = -(-(xs.max() + geo.x0 + 1) // 8) * 8
    y1 = -(-(ys.max() + geo.y0 + 1) // 8) * 8
    return int(x0), int(y0), int(x1), int(y1)


def write_jpeg(src_path, src_img, new_img, box, out_path):
    """jpegtran -drop 无损嵌回；不可用时整图同量化表重编码。返回所用方法。"""
    qt = src_img.quantization
    sampling = JpegImagePlugin.get_sampling(src_img)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    jt = shutil.which("jpegtran")
    if jt and sampling == 0:
        x0, y0, x1, y1 = box
        with tempfile.TemporaryDirectory() as td:
            drop = os.path.join(td, "drop.jpg")
            tmp_out = os.path.join(td, "out.jpg")
            Image.fromarray(new_img[y0:y1, x0:x1]).save(drop, "JPEG", qtables=qt, subsampling=sampling)
            r = subprocess.run([jt, "-copy", "all", "-drop", "+%d+%d" % (x0, y0), drop, "-outfile", tmp_out, src_path],
                               capture_output=True, text=True)
            if r.returncode == 0:
                chk = np.asarray(Image.open(tmp_out).convert("RGB"))
                outside = np.ones(chk.shape[:2], bool)
                outside[y0:y1, x0:x1] = False
                ref = np.asarray(src_img.convert("RGB"))
                if np.array_equal(chk[outside], ref[outside]):
                    shutil.copyfile(tmp_out, out_path)
                    return "jpegtran -drop +%d+%d（块 %dx%d）" % (x0, y0, x1 - x0, y1 - y0)
            print("  jpegtran 路径未通过（rc=%s %s），退回整图重编码" % (r.returncode, r.stderr.strip()[:80]))
    Image.fromarray(new_img).save(out_path, "JPEG", qtables=qt, subsampling=sampling if sampling >= 0 else 0)
    return "PIL 整图重编码（同量化表）"


def _erode(m, k):
    r = m.copy()
    for _ in range(k):
        r = r & np.roll(r, 1, 0) & np.roll(r, -1, 0) & np.roll(r, 1, 1) & np.roll(r, -1, 1)
    return r


def self_check(before, after, geo, box):
    rep = {}
    b_all, b_v = blue_stats(before, geo)
    a_all, a_v = blue_stats(after, geo)
    rep["blue_before"] = (b_all, b_v)
    rep["blue_after"] = (a_all, a_v)
    A = geo.full(geo.A)
    C = geo.full(geo.C)
    diff = np.abs(after.astype(np.int16) - before.astype(np.int16))
    outside = A == 0
    rep["outside_mad"] = float(diff[outside].mean())
    rep["outside_max"] = int(diff[outside].max())
    rep["outside_changed_px"] = int((diff[outside].max(-1) > 0).sum())
    x0, y0, x1, y1 = box
    inbox = np.zeros(A.shape, bool)
    inbox[y0:y1, x0:x1] = True
    rep["outside_box_changed_px"] = int((diff[~inbox].max(-1) > 0).sum())
    rep["ring_in_box_mad"] = float(diff[outside & inbox].mean())
    # 边界 ΔE：外轮廓外侧 1–3px 一圈（应≈0）、轮廓混色圈（0<C<1）、内侧 1–2px
    labb = srgb_to_lab(before)
    laba = srgb_to_lab(after)
    dE = np.sqrt(((laba - labb) ** 2).sum(-1))
    Cw = geo.C
    dil = [Cw > 0]
    for _ in range(3):
        m = dil[-1]
        dil.append(m | np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1))
    ring_out = geo.full((dil[3] & ~dil[0]).astype(np.uint8)).astype(bool)
    ring_edge = (C > 0) & (C < 1)
    ero = Cw >= 1
    e2 = _erode(ero, 2)
    ring_in = geo.full((ero & ~e2).astype(np.uint8)).astype(bool)
    rep["dE_ring_out"] = float(dE[ring_out].mean())
    rep["dE_ring_edge"] = float(dE[ring_edge].mean())
    rep["dE_ring_in"] = float(dE[ring_in].mean())
    Lb, La = labb[..., 0], laba[..., 0]
    yy, xx = np.mgrid[0:A.shape[0], 0:A.shape[1]]
    steps = {}
    for name, sel in (("左(深色瓶)", xx < 1070), ("右(红墙)", xx > 1118), ("底(柜面)", yy > 569)):
        si, so = ring_in & sel, ring_out & sel
        if si.sum() and so.sum():
            steps[name] = (float(Lb[si].mean() - Lb[so].mean()), float(La[si].mean() - La[so].mean()))
    rep["edge_step_L"] = steps
    m = geo.full((geo.C > 0.99).astype(np.uint8)).astype(bool)
    rep["jar_mean_before"] = before[m].mean(0)
    rep["jar_mean_after"] = after[m].mean(0)
    rep["jar_luma"] = (float(luma(before[m].astype(np.float32)).mean()), float(luma(after[m].astype(np.float32)).mean()))
    rep["jar_Lmax"] = (float(Lb[m].max()), float(La[m].max()))
    # 场景白点：内缩 3px 的罐身里，原图非蓝（B-R<2）的「白地」像素，比较同批像素改前改后
    core = geo.full(_erode(geo.C > 0.99, 3).astype(np.uint8)).astype(bool)
    wg = core & ((before[..., 2].astype(np.int16) - before[..., 0].astype(np.int16)) < 2)
    wb, wa = before[wg].astype(np.float64).mean(0), after[wg].astype(np.float64).mean(0)
    rep["wg"] = dict(n=int(wg.sum()), luma_b=float(luma(wb)), luma_a=float(luma(wa)),
                     gr_b=wb[1] / wb[0], br_b=wb[2] / wb[0], gr_a=wa[1] / wa[0], br_a=wa[2] / wa[0])
    rep["tex_before"] = texture(before, TEX_RECT)
    rep["tex_after"] = texture(after, TEX_RECT)
    rep["tex_ref"] = texture(before, TEX_REF)
    return rep


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", default=DEFAULT_SRC)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--in-place", action="store_true", help="允许输出覆盖输入文件")
    ap.add_argument("--force", action="store_true", help="跳过幂等检查（调试用）")
    args = ap.parse_args(argv)
    if os.path.abspath(args.src) == os.path.abspath(args.out) and not args.in_place:
        print("输出与输入同一路径，需加 --in-place 才写；未写任何文件。")
        return 2
    im = Image.open(args.src)
    if im.size != SIZE or im.format != "JPEG":
        print("输入不是 1920x1080 JPEG（%s %s），不是这张底图，跳过。" % (im.format, im.size))
        return 2
    src = np.asarray(im.convert("RGB"))
    geo = Geo()
    b_all, b_v = blue_stats(src, geo)
    print("输入 %s（%d 字节）：罐身 mask 内蓝像素 %.1f%%（V≥%.2f 时 %.1f%%）"
          % (args.src, os.path.getsize(args.src), 100 * b_all, BLUE_VMIN, 100 * b_v))
    if b_v < SKIP_BELOW and not args.force:
        m = geo.C > 0.99
        win = src[geo.y0:geo.y1, geo.x0:geo.x1].astype(np.float32)[m].mean(0)
        print("  蓝像素占比 < %.0f%%，罐身均色 (%.0f,%.0f,%.0f)：判定已处理过（或罐已非青花），跳过，未写文件。"
              % (100 * SKIP_BELOW, *win))
        return 0
    win_new, info = render(src, geo)
    new = src.copy()
    new[geo.y0:geo.y1, geo.x0:geo.x1] = win_new
    box = changed_blocks_bbox(geo)
    how = write_jpeg(args.src, im, new, box, args.out)
    after = np.asarray(Image.open(args.out).convert("RGB"))
    rep = self_check(src, after, geo, box)
    w = rep["wg"]
    print("写出 %s（%d 字节，%s）" % (args.out, os.path.getsize(args.out), how))
    print("  光照标定 白地受光 ≈ %.1f + %.1f × 设计光照" % tuple(info["coef"]))
    print("  蓝像素占比 前 %.1f%%/%.1f%%(V≥%.2f) → 后 %.2f%%/%.2f%%"
          % (100 * rep["blue_before"][0], 100 * rep["blue_before"][1], BLUE_VMIN, 100 * rep["blue_after"][0], 100 * rep["blue_after"][1]))
    print("  mask 外（alpha=0）平均绝对差 %.4f、最大 %d、变动像素 %d；改动块外变动像素 %d；块内 mask 外平均绝对差 %.3f"
          % (rep["outside_mad"], rep["outside_max"], rep["outside_changed_px"], rep["outside_box_changed_px"], rep["ring_in_box_mad"]))
    print("  边界 ΔE76：轮廓外 1–3px %.2f，轮廓混色圈 %.2f，内侧 1–2px %.2f"
          % (rep["dE_ring_out"], rep["dE_ring_edge"], rep["dE_ring_in"]))
    print("  跨轮廓 L* 台阶（内−外，前→后）：" + "；".join("%s %.1f→%.1f" % (k, *v) for k, v in rep["edge_step_L"].items()))
    print("  罐身均色 前 (%.0f,%.0f,%.0f) → 后 (%.0f,%.0f,%.0f)；亮度 %.1f → %.1f；L* 峰值 %.1f → %.1f"
          % (*rep["jar_mean_before"], *rep["jar_mean_after"], *rep["jar_luma"], *rep["jar_Lmax"]))
    print("  白地同批像素 n=%d：亮度 %.1f → %.1f（×%.3f）；G/R %.3f→%.3f、B/R %.3f→%.3f（折成本色 %.3f / %.3f）"
          % (w["n"], w["luma_b"], w["luma_a"], w["luma_a"] / w["luma_b"], w["gr_b"], w["gr_a"], w["br_b"], w["br_a"],
             w["gr_a"] / w["gr_b"], w["br_a"] / w["br_b"]))
    print("  肌理（框 %s，均亮/HF3/MF9）：前 %.1f/%.1f%%/%.1f%% → 后 %.1f/%.1f%%/%.1f%%；同画原生灰绿釉罐 %.1f/%.1f%%/%.1f%%"
          % (TEX_RECT, rep["tex_before"][0], 100 * rep["tex_before"][1], 100 * rep["tex_before"][2],
             rep["tex_after"][0], 100 * rep["tex_after"][1], 100 * rep["tex_after"][2],
             rep["tex_ref"][0], 100 * rep["tex_ref"][1], 100 * rep["tex_ref"][2]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
