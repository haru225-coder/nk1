#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：抹掉 bg_relay_post.jpg（旅店 / 急递铺设施页底图）右上角的伪界面牌。

来由：原画右上、檐下到窗扇之间，AI 出图带进来一块现代界面牌——半透明棕色圆角框（外框 x 1045–1610、
y 180–350，4px 棕黄描边，右下偏移 (+8,+8) 的硬投影）、框顶一道细亮线、简体黑体「急递铺路牌 / 福州→临安→襄阳」
加箭头。它不是场景里的实物，整块抹掉，还原框后面本来的画面：挂灯笼右半、远屋瓦面、廊柱、黄泥墙、窗框竖梃与斜顶梁、窗扇木板。

做法（实测数字与各轮试错见 nk1-fix2-work/signs/notes.md）：
1. 反混合（CORE：x 1057–1598、y 208–338）：框体是均匀半透明层，框内 O = g·B + off（逐通道）。g、off 用框内外 6 块
   同材质区（瓦、柱、墙、竖梃、窗板、右侧窗板）的均值回归求出，实测 g ≈ (0.129, 0.137, 0.121)、off ≈ (97.5, 65.4, 35.8)，
   即只透 13% 左右。B = (O − off)/g 能把框后结构还原，但 JPEG 误差同时被放大约 8 倍：
   - 亮度：先去块（8×8 块边界上的「超额跳变」< DEBLOCK_T 时线性摊到跨边界 8px），再自引导滤波（r2、ε30）；
   - 色度：4:2:0 色度块斑放大后成片发紫发绿，不信反混合；按列用框下同材质原画拟合的「亮度 → Cb/Cr」线性模型重建
     （瓦面几列框下不是瓦，改取灯笼左边的瓦）。
2. 电平校正：下缝（柱/墙/竖梃/窗板竖穿下沿）、右缝（窗板横纹穿右沿）两侧内容连续，把「外 − 内」差当狄利克雷边、
   上沿与左沿（暗梁、灯笼，真边）取零法向导数，DST 精确解一次拉普拉斯方程，调和场加进框内——框内与框外逐处对齐。
   瓦面几列另按行对齐灯笼左边同高度的瓦（×0.8）。
3. 字与箭头（不透明笔画；反混合后字周振铃要到 9–10px 才回到远处水平，所以外扩 9px）：12px 小格按环带已知比例逐格补——
   先只在框内已还原区、放宽后才到框下/框右原画里找环带 SSD 最小的平移源块照搬（含同高横向远取、竖向远取，越远越罚，
   与邻格同一平移打折），再按环带差解拉普拉斯膜；补完字区低频改取反混合的低频（σ10，避开笔画 7px），
   格子缝再按 12px 网格去块一遍，色度同样按列模型重建。字形带通相关（σ0.8–4 / 2–10）从原图 −0.96 降到 ≈0.01。
4. 四条边带（描边、框外 4px JPEG 振铃、框内被放大的振铃、顶部细线、右/下投影全落在里面）：
   上 y 176–207、下 y 339–361、左 x 1041–1056、右 x 1599–1622。
   - 上带 x<1340：外半（缝 y188 以上）照上方原画镜像，内半补块；暗梁、暗木块那几列（真边）内半补块时不看缝以上，
     缝上下 1 行轻合，暗梁下沿成一道自然硬边；内半不用镜像——否则框内顶上 20 行上下对称地出现两遍，4 倍下读成方斑；
   - 上带 x≥1340（竖梃顶、窗扇斜顶梁斜穿上沿）、右带、下带：全补块（平移源顺着窗板横纹、斜顶梁走，镜像会折成人字）；
   - 左带最后补：外侧层按灯笼中轴（x 1032.5）镜像补回被框压住的灯笼右半，外沿按与原画 x 1040 之差逐行补偏移、12px 收到 0；
     灯笼那几行整条带取灯笼，其余行在 x 1049 与内侧镜像 6px 交叉淡化。
5. 窗扇与墙面重建（第 2 轮评审意见 A–E：窗框左上角黑块、斜顶梁断、右带 1px 竖缝、墙上段发糊、木板发糊与亮点格）。
   第 1–4 步之后，把窗扇左上一带（x 1184–1622）按结构重做，只改改动区以内：
   - 透视：窗扇的横向线（顶横档上沿、下沿亮线、板缝）汇于一点。顶边按原画可见段逐列亚像素拟合为
     y = 140.49 − 0.2193·(x − 1640)（残差 0.77px），灭点取在顶边线上 x = −250（框下原画板缝最锐；与横档下沿亮线斜率 −0.206 相符）。
     以 (u = x, v = 该点所在汇聚线在 x 1640 处的 y) 建「矫正域」，板缝在其中是水平线；框右原画与框内反混合的板缝剖面在其中对得上。
   - 木板与顶横档：在矫正域里合成——结构取当前结果（只信反混合区）与原画已知像素沿板向的归一化平滑（缝是沿板向的直线，
     15–20px 的亮点格、补块格子、反混合噪声被抹掉），横档与木板分开平滑，再沿 v 轻锐化缝；木纹细节取框下原画木板沿板向的残差，
     按 v 折返、每折换一个 u 平移，乘性叠加。取回整图后，与改动区外原画的低频失配沿缝平滑、向内指数衰减补上，
     右缝、下缝再与「沿板向镜像的原画」交叉淡化 5px。顶横档因此沿斜率一直接到左竖梃（x 1335），上沿直、锐。
   - 左竖梃顶：原结果竖梃在字区那段左沿错到 x 1329、顶上是一条纯黑横块；改取下方 64px 处位置正确的竖梃平移上来，
     按竖梃身的亮度趋势压暗，暗部下限 12（原画窗扇转角最暗 1% 在 10–20），顶端沿顶边线切齐，与横档成转角。
   - 墙：肌理整块平移自窗扇上方原画墙（(x+146, y−132)，同一平移、墙内处处连续）；竖梃左侧墙面（D）低频保留原结果的檐影，
     肌理乘性补回（增益 0.7）；横档以上与 x≥1300 的顶几行低频取缝上方原画，紧贴改动区上沿 5 行与镜像交叉淡化。
   - 合成：顶边以下为窗扇、以上为墙，过渡 2.4px；D 向左（柱影）、向下（y 285–300）淡入原结果，竖梃在 y 256–268 淡入。
6. 墙面投影下沿残影（第 3 轮评审意见 F）：第 4 步下带在墙面 x≈1228–1268 按 12px 格补块，y 348–359 那一格偏亮、
   与 y 360 起的格子之间留一条平直水平底线，正落在原投影下沿（原图 y 357/358），4 倍下读成「亮斑 + 底线」
   （y359→360 行跳变 24px 段 −16.4，同处自然 99 分位 4.4–4.9；y352–358 比框下 y361–367 亮 +17 至 +31）。
   只改 x 1224–1272、y 344–361：逐行、逐通道取沿 x 的低通（σ3，12px 格的台阶要 σ≤3–4 才抹得掉），把它换成框下原画
   y 362–367 均值的同一低通（y 358→361 再渐变到原画 y 362 行本身，逐行接上），自 y 344 起 9 行渐入、左右 4–6px 淡出；
   低通以外的肌理原样保留（加性校正）。
   （评审另提可选改进「y 353–357 低频改用原图阴影 ÷0.63 逐行反推」试过：结构相关 0.19 → 0.90、隔 6 行相关 0.986 → 0.45，
   但 8px 段 y352–358 − y361–367 到 +15.3，越出 ±10 验收，未采用。）
7. 柱左沿瓦片越界（第 3 轮第 2 次，四边扫描在上边柱左沿比 ≈5）：第 4 步上带内半补块把远屋瓦片高光带进柱身 8–10px
   （x 1123–1133、y 188–204，柱列亮到 100–138；反混合此处是柱身 70–100，瓦面止于 x 1122），4–6 倍下读成「瓦压在柱前」。
   不回头改第 4 步（补块按环带已知比例逐格排序，换一格的源会牵动整条上带后续格子，连带第 5 步的 D 区），另加一步
   只改 x 1123–1156、y 187–207：柱列低频逐列在上参照（y 184–187，上带外半镜像的柱身）与下参照（y 208–210，反混合柱身）之间
   沿 y 线性插值（柱身自檐下往下渐亮），竖向细节取框上方原画柱身 (x, y − 56) 的相对高通（÷ 沿 y σ4 低通 − 1，增益 1.2），
   乘性叠加，最底 4 行细节淡出；上缘 2 行渐入、x 1146–1157 向原结果淡出，x < 1123 的瓦面不动。
   柱左沿 x 1123 由此从梁底 y 187 直通下去，瓦片高光止于 x 1122。
8. 写出：改动只落在 x 1024–1631、y 160–367 的 MCU（16×16，本图 4:2:0、progressive）里。改过的 MCU 按块对齐裁出，
   用原图同一套量化表与色度抽样编码，jpegtran -drop 无损嵌回（保持 progressive）——块外 DCT 系数与原图逐字节一致
   （djpeg -nosmooth 解码核对为 0 差；PIL 默认的色度平滑上采样只会让紧贴块边的 1px 有 ±1–2 级差）。
   fix_bg_customs_jar.write_jpeg 只处理 4:4:4，这里另写 MCU 版；其余小工具（模糊、盒均值、smoothstep、Lab）从它 import 复用。

幂等：先量描边环带里「牌子棕黄」像素的占比（原图 100%，抹后 ≈8%，与框下同形环带的自然占比相当）；低于 20% 视为已经抹过，
打印原因后跳过、不写文件（rc=0），所以日后可以直接对仓库文件运行。全程确定性，同一输入两次运行输出逐字节相同。
输出与输入同路径时必须加 --in-place 才写。整条流程以带牌子的原图为起点（第 5 步要用第 1 步的反混合）；
要重做时先把 git 里的原图取出来再跑：git show <带牌子的版本>:assets/bg_relay_post.jpg > /tmp/orig.jpg。

用法：
  python3 tools/art/erase_bg_relay_sign.py --in-place            # 就地处理 assets/bg_relay_post.jpg（已抹过则跳过）
  python3 tools/art/erase_bg_relay_sign.py --out /tmp/cand.jpg   # 只出候选，不动仓库文件
  python3 tools/art/erase_bg_relay_sign.py --src A.jpg --out B.jpg
自检数字（残留描边占比、字形带通相关、细线/描边/投影对比、改动区内外台阶与 ΔE、改动区外平均绝对差、MCU 外变动像素、
高频肌理、第 2 轮评审各项：木板/墙面高通 std、顶边逐列边强与直度、x1615 列梯度、窗角最暗、右/下/上缝跳变；
第 3 轮：墙面投影下沿 24px 段行跳变与上下均值差、原牌四边残影扫描、柱左沿逐行均亮偏离）每次运行都会打印。
原牌四边残影扫描：沿原牌四边（上 y 172–210、下 y 336–367 的行跳变，左 x 1036–1060、右 x 1596–1628 的列跳变，
含外框、框内沿、顶线、投影下沿 y≈358、改动区边）按 24px 段（步 8）取段均值跳变，除以同段在该边外侧改动区外原画的
自然 99 分位（上 y 120–172、下 y 364–420、左 x 984–1036、右 x 1628–1700；远屋瓦面列另取灯笼左边的瓦 x 950–1000，
取大；下限 1.5），比 <2 为无残影。上边不计四条结构边：梁底（x 1046–1126、y 186–188）、墙上方暗木块底
（x 1176–1300、y 186–188，与梁底同高，第 1 步反混合看得到）、顶横档上沿（顶边拟合线 ±2 行）与下沿亮线（矫正域 v 165–172，±2 行）
——这几列在该行的像素不进段均值。对原图跑同一扫描最大比 ≈59（牌子本身），用作这把尺子灵敏的对照。
柱左沿逐行均亮偏离：x 1124–1133 每行均亮与「上 4 行 → 下 3 行」线性插值之差的最大绝对值，y 188–207 与同法量的
框上方原画柱身（y 131–150）、反混合区柱身（y 240–259）并列打印。
单次约 2–3 分钟（补块的候选平移全量搜索）。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, JpegImagePlugin

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fix_bg_customs_jar import blur, blur_xy, box_mean, smoothstep, srgb_to_lab  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_SRC = os.path.join(ROOT, "assets", "bg_relay_post.jpg")
SIZE = (1920, 1080)

# ---- 牌子几何（原图像素，右/下为开区间） ----
OUTER = (1045, 180, 1611, 351, 7)      # 外框（含描边），圆角半径
INNER = (1049, 184, 1607, 347, 3)      # 框内（描边以内）
SHADOW = (1053, 188, 1619, 358, 8)     # 投影（框偏移 +8,+8）
BORDER_RGB = np.array((148.0, 105.0, 62.0))
WIN = (992, 144, 1648, 560)            # 处理窗（含镜像取样与补块取源余量）
MOD = (1041, 176, 1623, 362)           # 改动矩形 = 四条边带的外沿
TOP_BAND = (176, 208)                  # 行（顶线 192–193 的振铃放大后压暗到 200–207 行，一并归入上带）
BOT_BAND = (339, 362)
LEFT_BAND = (1041, 1057)               # 列
RIGHT_BAND = (1599, 1623)
CORE = (1057, 208, 1599, 339)          # 反混合区（x0, y0, x1, y1）
# 框左沿压着一盏挂灯笼（左缘 x≈1004.5、吊绳 x≈1031，框内反混合看得到右缘 x≈1060）：左带外侧层按灯笼中轴镜像
LANTERN_AXIS = 1032.5
LANTERN_ROWS = (212, 318)
TOP_CELLS_X = 1340                     # 上带在此以右（竖梃顶、窗扇斜顶梁斜穿上沿）改用补块，以左镜像（暗梁下沿是真边，镜像拼得出硬边）
TEXT_LOWPASS = 10.0        # 字区低频取反混合（σ10 归一化模糊）：补块源的受光与檐下不同，按反混合低频把明暗拉回
TEXT_LP_EXCL = 7           # 取低频时避开笔画外扩 7px（笔画外 5–9px 有振铃正瓣，偏亮）
TOP_CRISP_X = [(1057, 1125), (1180, 1300)]   # 上沿真边的列：远屋瓦面上方暗梁、墙上方暗木块
NO_SOURCE = [(1380, 420, 1600, 560)]   # 不许取源的区域：框下窗前兵士的头与茶盏
# 远屋瓦面（框内 x<1125）：框下不是瓦，下缝电平校正对它无效；改按行对齐灯笼左边同高度的瓦（x 950–1000）的亮度
TILE_REF_X = (950, 1000)
TILE_MATCH = 0.8           # 对齐比例（行均亮差 × 0.8，σ10 行平滑）
TILE_TAPER = (1116, 1127)  # 向廊柱渐隐

# ---- 反混合 ----
FIT_REGIONS = [  # (名称, 框内 x0,x1,y0,y1, 框外 x0,x1,y0,y1)：同一材质框内/框外各取一块
    ("瓦", (1052, 1120, 300, 345), (1052, 1120, 362, 395)),
    ("柱", (1135, 1168, 300, 345), (1135, 1168, 362, 395)),
    ("墙", (1195, 1320, 312, 345), (1195, 1320, 362, 395)),
    ("竖梃", (1338, 1356, 312, 345), (1338, 1356, 362, 395)),
    ("窗板", (1400, 1590, 312, 345), (1400, 1590, 362, 395)),
    ("右窗板", (1590, 1606, 200, 340), (1620, 1650, 200, 340)),
]
TEXT_Y = 70.0              # 框内亮度低于此为字 / 箭头笔画（框底色最暗处 O≈73）
LINE_ROWS = (190, 196)     # 框顶细线所在行
DEBLOCK_T, DEBLOCK_ITERS = 20.0, 3
LUMA_GF = (2, 30.0)        # 亮度自引导滤波 (r, ε)
TEXT_DILATE = 9            # 字外扩：反混合后字周振铃的亮度偏差到 9–10px 才回到远处水平（实测）
# 色度模型：每列取框下同材质原画（y 362–420、x±8）拟合 Cb/Cr = a·Y + b；远屋瓦面那几列框下不是瓦，改取灯笼左边的瓦
CHROMA_SRC_ROWS = (362, 420)
CHROMA_HALF = 8
CHROMA_EPS = 40.0
TILE_X1 = 1125
TILE_CHROMA_SRC = (950, 1000, 200, 330)

# ---- 补块 ----
CELL = 12
SEARCH = 36
SEARCH_V = 200             # 另加竖向远取（|dx|≤6），好从框下原画取墙、竖梃
SEARCH_H = 120             # 另加横向远取（|dy|≤8）：同一高度的墙受光相同（檐下阴影随高度变），优先取同高处
DIST_PENALTY = 0.3         # 源越远 SSD 加得越多（每像素平移）
RING = 3
COHERE = 0.8               # 与已补邻格同一平移时 SSD 打折，免得碎成百衲衣
CELL_SEAM_T = 25.0         # 字区格子缝去块门槛

# ---- 边带拼缝与电平校正 ----
SEAM_SOFT, SEAM_HARD = 8.0, 1.5
SEAM_D = (6.0, 18.0)       # 两侧亮度差在此区间内由软拼过渡到硬拼
SKIP_BORDER_FRAC = 0.20

M_YCC = np.array([[0.299, 0.587, 0.114], [-0.168736, -0.331264, 0.5], [0.5, -0.418688, -0.081312]])
M_RGB = np.linalg.inv(M_YCC)


# ---------- 小工具 ----------
def rrect(win, x0, y0, x1, y1, r):
    """处理窗内的圆角矩形（像素中心判定）。"""
    wx0, wy0, wx1, wy1 = win
    yy, xx = np.mgrid[wy0:wy1, wx0:wx1] + 0.5
    dx = np.maximum(np.maximum(x0 + r - xx, 0), xx - (x1 - r))
    dy = np.maximum(np.maximum(y0 + r - yy, 0), yy - (y1 - r))
    inside = (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)
    return inside & (dx * dx + dy * dy <= r * r)


def dilate(m, k):
    r = m.copy()
    for _ in range(k):
        r = r | np.roll(r, 1, 0) | np.roll(r, -1, 0) | np.roll(r, 1, 1) | np.roll(r, -1, 1)
    return r


def mbox(p, m, r):
    """掩膜内盒均值（只让有效像素参与）。"""
    if p.ndim == 3:
        return np.stack([mbox(p[..., c], m, r) for c in range(p.shape[2])], -1)
    return box_mean(p * m, r) / np.maximum(box_mean(m, r), 1e-6)


def guided(I, p, m, r, eps):
    """掩膜引导滤波（He et al.）：输出 = 局部 a·I + b，a、b 只由有效像素估计。"""
    mI, mp = mbox(I, m, r), mbox(p, m, r)
    cov = mbox(I * p, m, r) - mI * mp
    var = mbox(I * I, m, r) - mI * mI
    a = cov / (var + eps)
    b = mp - a * mI
    wa = box_mean(m, r) > 1e-3
    return np.where(wa, mbox(a, m, r) * I + mbox(b, m, r), np.nan)


def nblur(p, m, s):
    if p.ndim == 3:
        return np.stack([nblur(p[..., c], m, s) for c in range(p.shape[2])], -1)
    return blur(p * m, s) / np.maximum(blur(m, s), 1e-12)


def deblock(Y, valid, T, iters, size=8, grid_origin=(0, 0)):
    """块边界去块：边界处超出两侧局部梯度的跳变（|J|<T 才算块效应）线性摊到跨边界 8px。
    默认按整图原点的 8×8 JPEG 块网格；补块的格子网格用 size=CELL、grid_origin=处理窗原点。Y 可为 2D 或 H×W×C。"""
    Y = Y.copy()
    ox, oy = (WIN[0] - grid_origin[0]) % size, (WIN[1] - grid_origin[1]) % size
    for _ in range(iters):
        for axis, org in ((1, ox), (0, oy)):
            n = Y.shape[axis]
            for b in range((size - org) % size or size, n - 4, size):
                if b < 4:
                    continue
                def sl(i):
                    return (slice(None), b + i) if axis == 1 else (b + i, slice(None))
                p = [Y[sl(i)] for i in (-4, -3, -2, -1)]
                q = [Y[sl(i)] for i in (0, 1, 2, 3)]
                ok = np.all([valid[sl(i)] for i in range(-4, 4)], axis=0)
                if Y.ndim == 3:
                    ok = ok[..., None]
                J = (q[0] - p[3]) - 0.5 * ((p[3] - p[2]) + (q[1] - q[0]))
                J = np.where(ok & (np.abs(J) < T), J, 0.0)
                for i, idx in enumerate((-4, -3, -2, -1)):
                    Y[sl(idx)] += J * (i + 1) / 8
                for i, idx in enumerate((0, 1, 2, 3)):
                    Y[sl(idx)] -= J * (4 - i) / 8
    return Y


def membrane(delta_known, known, region, iters=300):
    """region 内解拉普拉斯方程：4 邻域里 known 的像素取 delta_known 作狄利克雷边界，其余邻居（未知）不参与（诺伊曼）。"""
    ys, xs = np.nonzero(region)
    y0, y1 = max(ys.min() - 1, 0), min(ys.max() + 2, region.shape[0])
    x0, x1 = max(xs.min() - 1, 0), min(xs.max() + 2, region.shape[1])
    R = region[y0:y1, x0:x1]
    K = known[y0:y1, x0:x1] & ~R
    D = delta_known[y0:y1, x0:x1]
    C = D.shape[2]
    val = np.where(K[..., None], D, 0.0)
    # 初值：环带差值的均值
    init = D[K].mean(0) if K.any() else np.zeros(C)
    cur = np.where(R[..., None], init, val)
    use = (R | K).astype(np.float64)
    for _ in range(iters):
        acc = np.zeros_like(cur)
        cnt = np.zeros(R.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(cur, dy, 0), dx, 1)
            su = np.roll(np.roll(use, dy, 0), dx, 1)
            acc += sh * su[..., None]
            cnt += su
        new = acc / np.maximum(cnt, 1)[..., None]
        cur = np.where(R[..., None], new, val)
    out = np.zeros(region.shape + (C,))
    out[y0:y1, x0:x1] = np.where(R[..., None], cur, 0.0)
    return out


def ycc(rgb):
    return rgb @ M_YCC.T


def to_rgb(y):
    return y @ M_RGB.T


def lum(rgb):
    return rgb @ M_YCC[0]


# ---------- 几何与检测 ----------
class Geo:
    def __init__(self, O):
        self.O = O                                    # 处理窗内原图（float）
        wx0, wy0 = WIN[0], WIN[1]
        self.h, self.w = O.shape[:2]
        self.outer = rrect(WIN, *OUTER)
        self.inner = rrect(WIN, *INNER)
        self.shadow = rrect(WIN, *SHADOW) & ~self.outer
        self.border = self.outer & ~self.inner
        yy, xx = np.mgrid[wy0:WIN[3], wx0:WIN[2]]
        self.yy, self.xx = yy, xx
        cx0, cy0, cx1, cy1 = CORE
        self.core = (xx >= cx0) & (xx < cx1) & (yy >= cy0) & (yy < cy1)
        mx0, my0, mx1, my1 = MOD
        self.mod = (xx >= mx0) & (xx < mx1) & (yy >= my0) & (yy < my1)
        Y = lum(O)
        self.text = self.inner & (Y < TEXT_Y)
        self.line = self.inner & (yy >= LINE_ROWS[0]) & (yy < LINE_ROWS[1]) & (Y > 88)
        self.text_d = dilate(self.text, TEXT_DILATE) & self.core


def border_fraction(O, geo):
    """描边环带（外框内缩 1px 到框内外扩 1px 之间的 2px 核心）里「牌子棕黄」像素的占比。"""
    core = geo.outer & ~dilate(geo.inner, 1) & ~dilate(~geo.outer, 1)
    d = np.abs(O[core] - BORDER_RGB).max(-1)
    return float((d < 22).mean()), int(core.sum())


# ---------- 1. 反混合 ----------
def fit_unblend(O):
    """框内外同材质区均值回归 O_in = g·B_out + off（逐通道）。O 为整图。"""
    ins, outs = [], []
    for _, (x0, x1, y0, y1), (u0, u1, v0, v1) in FIT_REGIONS:
        ins.append(O[y0:y1, x0:x1].reshape(-1, 3).mean(0))
        outs.append(O[v0:v1, u0:u1].reshape(-1, 3).mean(0))
    ins, outs = np.array(ins), np.array(outs)
    g, off = np.zeros(3), np.zeros(3)
    for c in range(3):
        A = np.stack([outs[:, c], np.ones(len(ins))], 1)
        (g[c], off[c]), *_ = np.linalg.lstsq(A, ins[:, c], rcond=None)
    return g, off


def chroma_model(ext_ycc):
    """每列一个 Cb/Cr = a·Y + b 的线性模型（取框下同材质原画；瓦面几列取灯笼左边的瓦）。返回 (CORE 宽, 2, 2)。"""
    cx0, cx1 = CORE[0], CORE[2]
    A = np.zeros((cx1 - cx0, 2, 2))
    for i, x in enumerate(range(cx0, cx1)):
        if x < TILE_X1:
            x0, x1, y0, y1 = TILE_CHROMA_SRC
        else:
            x0, x1 = x - CHROMA_HALF, x + CHROMA_HALF + 1
            y0, y1 = CHROMA_SRC_ROWS
        p = ext_ycc[y0:y1, x0:x1].reshape(-1, 3)
        Yv = p[:, 0]
        vY = Yv.var()
        for c in (1, 2):
            a = ((Yv - Yv.mean()) * (p[:, c] - p[:, c].mean())).mean() / (vY + CHROMA_EPS)
            A[i, c - 1] = (a, p[:, c].mean() - a * Yv.mean())
    return A


def unblend_core(geo, g, off, full):
    """框内反混合：亮度去块 + 自引导滤波；色度不信反混合（放大 8 倍的 4:2:0 色度块斑），按列用框外同材质的亮度→色度模型重建。"""
    O = geo.O
    B = (O - off) / g
    Yc = ycc(B)
    lval = geo.core & ~geo.text_d
    Yd = deblock(Yc[..., 0], lval, DEBLOCK_T, DEBLOCK_ITERS)
    Yg = guided(Yd, Yd, lval.astype(np.float64), *LUMA_GF)
    Yg = np.where(np.isnan(Yg), Yd, Yg)
    return apply_chroma_model(Yg, chroma_model(ycc(full.astype(np.float64))))


def apply_chroma_model(Y, A):
    """亮度 Y（处理窗）按列套色度模型，返回 RGB。"""
    cx0 = CORE[0] - WIN[0]
    cols = np.clip(np.arange(Y.shape[1]) - cx0, 0, A.shape[0] - 1)
    out = np.stack([Y, A[cols, 0, 0][None] * Y + A[cols, 0, 1][None], A[cols, 1, 0][None] * Y + A[cols, 1, 1][None]], -1)
    return to_rgb(out)


# ---------- 2. 补块 ----------
def make_offsets(search=SEARCH, search_v=SEARCH_V, search_h=SEARCH_H):
    sq = [(dy, dx) for dy in range(-search, search + 1) for dx in range(-search, search + 1) if max(abs(dy), abs(dx)) >= 4]
    far = [(dy, dx) for dy in range(-search_v, search_v + 1) for dx in range(-6, 7) if abs(dy) > search]
    far_h = [(dy, dx) for dy in range(-8, 9) for dx in range(-search_h, search_h + 1) if abs(dx) > search]
    return np.array(sq + far + far_h)


FILL_LOG = []              # 补块记录 (格左上 x, y, dx, dy, 源档, SSD)，调试与笔记用


def fill_cells(img, known, todo, src_ok, src_region, cell=CELL, ring=RING, offs=None, ring_ok=None):
    """把 todo 分成 cell×cell 小格，按「环带已知比例」从高到低逐格补：环带 SSD 最小的平移源块 + 拉普拉斯膜。
    与已补邻格同一平移的候选 SSD 打 COHERE 折，让相邻格倾向整片照搬同一处，少拼缝。
    src_ok 是由严到宽的若干源掩膜：先在第一档里找整块可用的源，找不到再放宽；都不行时最后再加上 src_region 里已补好的像素。"""
    img = img.copy()
    known = known.copy()
    if isinstance(src_ok, np.ndarray):
        src_ok = (src_ok,)
    h, w = todo.shape
    if offs is None:
        offs = make_offsets()
    if ring_ok is None:
        ring_ok = np.ones_like(todo)
    cells = [(y0, x0) for y0 in range(0, h, cell) for x0 in range(0, w, cell) if todo[y0:y0 + cell, x0:x0 + cell].any()]
    done = {}

    def local(y0, x0):
        """格子外扩 ring+1 的局部窗与其中的格内待补像素、环带（只取 ring_ok 里的像素）。"""
        ly0, lx0 = max(y0 - ring - 1, 0), max(x0 - ring - 1, 0)
        ly1, lx1 = min(y0 + cell + ring + 1, h), min(x0 + cell + ring + 1, w)
        P = np.zeros((ly1 - ly0, lx1 - lx0), bool)
        P[y0 - ly0:y0 - ly0 + cell, x0 - lx0:x0 - lx0 + cell] = todo[y0:y0 + cell, x0:x0 + cell]
        R = dilate(P, ring) & ~P & ring_ok[ly0:ly1, lx0:lx1]
        return ly0, lx0, ly1, lx1, P, R

    used = []
    while cells:
        scores = []
        for y0, x0 in cells:
            ly0, lx0, ly1, lx1, P, R = local(y0, x0)
            scores.append((known[ly0:ly1, lx0:lx1] & R).sum() / max(R.sum(), 1))
        y0, x0 = cells.pop(int(np.argmax(scores)))
        ly0, lx0, ly1, lx1, Pl, Rl = local(y0, x0)
        Rl &= known[ly0:ly1, lx0:lx1]
        P = np.zeros_like(todo)
        P[ly0:ly1, lx0:lx1] = Pl
        py, px = np.nonzero(Pl)
        ry, rx = np.nonzero(Rl)
        py, px, ry, rx = py + ly0, px + lx0, ry + ly0, rx + lx0
        nb = {done[k] for k in ((y0 - cell, x0), (y0 + cell, x0), (y0, x0 - cell), (y0, x0 + cell)) if k in done}
        nb_arr = np.array(sorted(nb)) if nb else np.zeros((0, 2), int)
        best, bo = None, None
        # 先只用原本就干净的像素作源；整块都找不到时（字太密）再放宽到「框内已补好的像素」
        for tier, valid in enumerate(tuple(src_ok) + (src_ok[-1] | (known & src_region),)):
            for chunk in np.array_split(offs, 16):
                sy = py[None, :] + chunk[:, :1]
                sx = px[None, :] + chunk[:, 1:]
                ok = ((sy >= 0) & (sy < h) & (sx >= 0) & (sx < w)).all(1)
                sy, sx = np.clip(sy, 0, h - 1), np.clip(sx, 0, w - 1)
                ok &= valid[sy, sx].all(1)
                if not ok.any():
                    continue
                ch = chunk[ok]
                qy = np.clip(ry[None, :] + ch[:, :1], 0, h - 1)
                qx = np.clip(rx[None, :] + ch[:, 1:], 0, w - 1)
                diff = img[qy, qx] - img[ry, rx][None]
                ssd = (diff ** 2).sum(-1).mean(1) + DIST_PENALTY * (np.abs(ch).sum(1))
                if len(nb_arr):
                    same = (ch[:, None, :] == nb_arr[None]).all(-1).any(1)
                    ssd = np.where(same, ssd * COHERE, ssd)
                j = int(np.argmin(ssd))
                if best is None or ssd[j] < best:
                    best, bo = ssd[j], ch[j]
            if bo is not None:
                break
        if bo is None:
            raise RuntimeError("补块：找不到可用的平移源块")
        dy, dx = int(bo[0]), int(bo[1])
        done[(y0, x0)] = (dy, dx)
        FILL_LOG.append((x0 + WIN[0], y0 + WIN[1], dx, dy, tier, float(best)))
        src = np.roll(np.roll(img, -dy, 0), -dx, 1)
        delta = np.where(known[..., None], img - src, 0.0)
        img[P] = src[P]
        adj = dilate(P, 1) & ~P & known & ring_ok
        img[P] += membrane(delta, adj, P)[P]
        known |= P
        used.append((dy, dx))
    return img, used


# ---------- 3. 边带 ----------
def band_layers(img, band, axis, seam, outer_side):
    """返回 (外侧镜像层, 内侧镜像层, 带内坐标 t（向内为正）)。axis=0 行带、1 列带。"""
    a0, a1 = band
    idx = np.arange(a0, a1)
    off0 = WIN[1] if axis == 0 else WIN[0]
    if outer_side == "low":         # 外侧在小坐标一侧（上带、左带）
        o_src = 2 * a0 - 1 - idx
        i_src = 2 * a1 - 1 - idx
        t = idx + 0.5 - seam
    else:                           # 外侧在大坐标一侧（下带、右带）
        o_src = 2 * a1 - 1 - idx
        i_src = 2 * a0 - 1 - idx
        t = seam - (idx + 0.5)
    take = (lambda s: img[s - off0]) if axis == 0 else (lambda s: img[:, s - off0])
    Lo = np.stack([take(s) for s in o_src], axis)
    Li = np.stack([take(s) for s in i_src], axis)
    return Lo, Li, t


def span_slice(span, axis):
    """沿缝方向的坐标区间 → 处理窗内切片。axis=0 行带沿 x，axis=1 列带沿 y。"""
    s0, s1 = span
    o = WIN[0] if axis == 0 else WIN[1]
    return slice(s0 - o, s1 - o)


def seam_profile(Lo, Li, t, axis):
    """缝两侧 4 行/列的均值差（外 − 内，逐通道）与亮度差绝对值，沿缝方向 σ4 平滑。"""
    so = (t < 0) & (t > -4.5)
    si = (t > 0) & (t < 4.5)
    if axis == 0:
        do = Lo[so].mean(0) - Li[si].mean(0)       # (沿缝, 3)
    else:
        do = Lo[:, so].mean(1) - Li[:, si].mean(1)
    k = np.exp(-0.5 * (np.arange(-12, 13) / 4.0) ** 2)
    k /= k.sum()
    sm = np.stack([np.convolve(np.pad(do[:, c], 12, mode="edge"), k, mode="valid") for c in range(3)], -1)
    return sm, np.abs(lum(sm))


def band_cut(img, band, axis, seam, side, span):
    """两侧镜像层切到 span（沿缝方向）。"""
    Lo, Li, t = band_layers(img, band, axis, seam, side)
    ss = span_slice(span, axis)
    if axis == 0:
        return Lo[:, ss], Li[:, ss], t
    return Lo[ss], Li[ss], t


def blend_band(img, band, axis, seam, side, span):
    """在 span（沿缝方向的坐标区间）内用两侧镜像拼出边带，缝宽按两侧差自适应。"""
    Lo, Li, t = band_cut(img, band, axis, seam, side, span)
    diff, d = seam_profile(Lo, Li, t, axis)
    fw = SEAM_HARD + (SEAM_SOFT - SEAM_HARD) * (1 - smoothstep(SEAM_D[0], SEAM_D[1], d))
    if axis == 0:
        wgt = smoothstep(-0.5, 0.5, t[:, None] / fw[None, :])[..., None]
    else:
        wgt = smoothstep(-0.5, 0.5, t[None, :] / fw[:, None])[..., None]
    out = Lo * (1 - wgt) + Li * wgt
    a0, a1 = band
    ss = span_slice(span, axis)
    if axis == 0:
        img[a0 - WIN[1]:a1 - WIN[1], ss] = out
    else:
        img[ss, a0 - WIN[0]:a1 - WIN[0]] = out
    return fw


def left_band(img):
    """左带：外侧层按灯笼中轴镜像（灯笼右半被框压住，镜像左半补回，右缘落在 x≈1060 与框内反混合接上），
    内侧层镜像框内；灯笼那几行缝推到带内沿（整条带取灯笼），其余行缝在 x 1049、6px 交叉淡化。"""
    a0, a1 = LEFT_BAND
    wx0, wy0 = WIN[0], WIN[1]
    xs = np.arange(a0, a1)
    ys = np.arange(MOD[1], MOD[3]).astype(np.float64)
    rs = slice(MOD[1] - wy0, MOD[3] - wy0)
    Lo = img[rs][:, np.round(2 * LANTERN_AXIS - xs).astype(int) - wx0]
    # 中轴镜像在带外沿（x 1041）与原画 x 1040 并不相邻：按两者之差逐行补一个偏移，跨 12px 线性收到 0，免得留竖缝
    step = img[rs, a0 - 1 - wx0] - Lo[:, 0]
    k = np.exp(-0.5 * (np.arange(-9, 10) / 3.0) ** 2)
    k /= k.sum()
    step = np.stack([np.convolve(np.pad(step[:, c], 9, mode="edge"), k, mode="valid") for c in range(3)], -1)
    Lo = Lo + step[:, None, :] * np.clip(1 - (xs - a0 + 0.5) / 12.0, 0, 1)[None, :, None]
    Li = img[rs][:, (2 * a1 - 1 - xs) - wx0]
    r0, r1 = LANTERN_ROWS
    lan = smoothstep(r0 - 4, r0 + 4, ys) * (1 - smoothstep(r1 - 4, r1 + 4, ys))
    seam = 1049.0 + 8.0 * lan
    t = xs[None, :] + 0.5 - seam[:, None]
    wgt = smoothstep(-0.5, 0.5, t / 6.0)[..., None]
    img[rs, a0 - wx0:a1 - wx0] = Lo * (1 - wgt) + Li * wgt


SEAMS = {  # 名称: (带, axis, 缝坐标, 外侧在哪边)
    "top": (TOP_BAND, 0, 188.0, "low"),
    "bot": (BOT_BAND, 0, 351.0, "high"),
    "right": (RIGHT_BAND, 1, 1611.0, "high"),
}


def dst1(x, axis):
    """DST-I（经 FFT 奇延拓）。"""
    x = np.moveaxis(x, axis, 0)
    n = x.shape[0]
    z = np.zeros((1,) + x.shape[1:])
    y = np.concatenate([z, x, z, -x[::-1]], 0)
    X = -np.fft.fft(y, axis=0).imag[1:n + 1] / 2
    return np.moveaxis(X, 0, axis)


def laplace_br(bottom, right):
    """CORE 矩形上的调和插值：底边外一行取 bottom、右边外一列取 right（狄利克雷），顶边、左边零法向导数（诺伊曼）。
    诺伊曼边用镜像把区域扩成 2h×2w、四边全狄利克雷，再用 DST-I 精确求解五点拉普拉斯。bottom (w,C)、right (h,C)。"""
    w, h = bottom.shape[0], right.shape[0]
    C = bottom.shape[1]
    H2, W2 = 2 * h, 2 * w
    bot = np.concatenate([bottom[::-1], bottom], 0)          # 扩展后底边（与顶边相同）
    rgt = np.concatenate([right[::-1], right], 0)            # 扩展后右边（与左边相同）
    f = np.zeros((H2, W2, C))
    f[-1] -= bot
    f[0] -= bot
    f[:, -1] -= rgt
    f[:, 0] -= rgt
    F = dst1(dst1(f, 0), 1)
    k = np.arange(1, H2 + 1)[:, None]
    l = np.arange(1, W2 + 1)[None, :]
    lam = (2 * np.cos(np.pi * k / (H2 + 1)) - 2) + (2 * np.cos(np.pi * l / (W2 + 1)) - 2)
    U = dst1(dst1(F / lam[..., None], 0), 1) * (2 / (H2 + 1)) * (2 / (W2 + 1))
    return U[h:, w:]


def seam_diff(img, name, span):
    band, axis, seam, side = SEAMS[name]
    Lo, Li, t = band_cut(img, band, axis, seam, side, span)
    return seam_profile(Lo, Li, t, axis)


def tile_rows_delta(img, full):
    """远屋瓦面几列的亮度偏移：逐行对齐灯笼左边同高度的瓦（行均亮差 × TILE_MATCH，σ10 行平滑），向廊柱渐隐。"""
    cx0, cy0, cx1, cy1 = CORE
    wx0, wy0 = WIN[0], WIN[1]
    rows = np.arange(cy0, cy1)
    ext = lum(full[cy0:cy1, TILE_REF_X[0]:TILE_REF_X[1]].astype(np.float64)).mean(1)
    inn = lum(img[cy0 - wy0:cy1 - wy0, cx0 + 3 - wx0:TILE_TAPER[0] - wx0]).mean(1)
    d = TILE_MATCH * (ext - inn)
    k = np.exp(-0.5 * (np.arange(-30, 31) / 10.0) ** 2)
    k /= k.sum()
    d = np.convolve(np.pad(d, 30, mode="edge"), k, mode="valid")
    out = np.zeros(img.shape)
    xs = np.arange(img.shape[1]) + wx0
    wx = 1 - smoothstep(TILE_TAPER[0], TILE_TAPER[1], xs.astype(np.float64))
    wx[xs < cx0] = 0
    out[cy0 - wy0:cy1 - wy0] = (d[:, None] * wx[None, :])[..., None]
    assert len(rows) == len(d)
    return out


def delta_full(delta, shape):
    """CORE 上的电平校正场摊回处理窗大小（CORE 外为 0）。"""
    out = np.zeros(shape)
    cx0, cy0, cx1, cy1 = CORE
    out[cy0 - WIN[1]:cy1 - WIN[1], cx0 - WIN[0]:cx1 - WIN[0]] = delta
    return out


# ---------- 5. 窗扇与墙面重建（第 2 轮） ----------
# 透视：窗扇横向线（顶边、横档下沿、板缝）汇于灭点 (VP_X, VP_Y)；顶边 y = T_Y + T_SLOPE·(x − T_XR)（原画可见段逐列拟合）
VP_X, T_XR, T_Y, T_SLOPE = -250.0, 1640.0, 140.49, -0.2193
VP_Y = T_Y - T_SLOPE * (T_XR - VP_X)
RECT_U = (1330, 1690)                   # 矫正域：u = x，v = 过该点的汇聚线在 x = T_XR 处的 y（板缝在矫正域里是水平线）
RECT_V = (120.0, 480.0, 0.5)
RAIL_V1 = 172.0                         # 顶横档：v 140.49（顶边）到 172（下沿亮线与缝之下）
STILE = (1335, 1362)                    # 左竖梃（x 1358–1361 为它与木板之间的暗缝）
PLANK_GAIN = 1.3                        # 木纹细节增益（E 区高通 std 目标 ≥4.5，框下同板 5.6）
DET_SRC_V = (361.0, 397.0)              # 木纹细节取源：框下原画木板（避开兵士头部）
DET_SRC_U = (1364, 1674)
DET_SHIFTS = (0, 97, -61, 143, -29, 71, -113, 37)   # 细节按 v 折返取源，每折换一个 u 平移，免得上下重复
EDGE_W = 2.4                            # 顶边过渡宽（px）
STILE_SHIFT, STILE_END = 64, (256, 268) # 竖梃顶：取下方 64px 处的竖梃平移上来，在 y 256–268 淡入原结果
STILE_FLOOR = (18.0, 12.0)              # 竖梃暗部：亮度 <18 的压到 12–18（原画窗扇转角最暗 1% 在 10–20）
WALL_SHIFT = (146, 132)                 # 墙面肌理平移源 (x+146, y−132)：窗扇上方原画墙（x 1330–1624、y 44–168）
WALL_SIGMA = 6.0                        # 墙面低频 / 肌理分界（σ）
WALL_GAIN = 0.7                         # 竖梃左侧墙面（D）肌理增益（目标高通 std ≥2.8）
D_BOX = (1184, 189, 1335, 300)          # 竖梃左侧墙面（x0, y0, x1, y1）
SEAM_XF = 5.0                           # 右缝、下缝与「沿板向镜像的原画」交叉淡化宽度
SEAM_LF = (5.0, 8.0)                    # 右缝、下缝、横档上缝低频失配：沿缝 σ5 平滑，向内 exp(−d/8) 衰减


def v_of(x, y):
    return VP_Y + (y - VP_Y) * (T_XR - VP_X) / (x - VP_X)


def y_of(u, v):
    return VP_Y + (v - VP_Y) * (u - VP_X) / (T_XR - VP_X)


def top_edge(x):
    return T_Y + T_SLOPE * (x - T_XR)


def in_mod(x, y):
    return (x >= MOD[0]) & (x < MOD[2]) & (y >= MOD[1]) & (y < MOD[3])


def sample_y(I, x, y):
    """整图 I 在整数列 x、实数行 y 处取样（沿 y 线性插值）。"""
    yi = np.clip(np.floor(y).astype(int), 0, I.shape[0] - 2)
    f = (y - yi)[..., None]
    return (1 - f) * I[yi, x] + f * I[yi + 1, x]


def nc_u(P, Wt, s):
    """矫正域里沿 u（第 1 轴）的归一化高斯平滑，返回 (平滑值, 权重和)。"""
    r = int(3 * s) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)

    def conv(a):
        pad = np.pad(a, ((0, 0), (r, r)) + ((0, 0),) * (a.ndim - 2))
        out = np.zeros_like(a)
        for i, kv in enumerate(k):
            out += kv * pad[:, i:i + a.shape[1]]
        return out
    den = conv(Wt)
    if P.ndim == 3:
        return conv(P * Wt[..., None]) / np.maximum(den, 1e-9)[..., None], den
    return conv(P * Wt) / np.maximum(den, 1e-9), den


def g_v(P, s):
    """沿 v（第 0 轴）高斯平滑（边缘复制）。"""
    r = int(3 * s) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
    k /= k.sum()
    pad = np.pad(P, ((r, r),) + ((0, 0),) * (P.ndim - 1), mode="edge")
    out = np.zeros_like(P)
    for i, kv in enumerate(k):
        out += kv * pad[i:i + P.shape[0]]
    return out


def pingpong(t, n):
    """t 折返映射进 [0, n)，返回 (折后坐标, 第几折)。"""
    k = np.floor(t / n).astype(int)
    r = t - k * n
    return np.where(k % 2 == 0, r, n - 1e-6 - r), k


def gauss_nc(P, Wt, s):
    if P.ndim == 3:
        return np.stack([gauss_nc(P[..., c], Wt, s) for c in range(P.shape[2])], -1)
    return blur(P * Wt, s) / np.maximum(blur(Wt, s), 1e-9)


def blur_rgb(I, s):
    return np.stack([blur(I[..., c], s) for c in range(I.shape[2])], -1)


def shutter_rect(O, C, reliable):
    """矫正域里合成顶横档与木板，返回矫正域 RGB 图。O 原图、C 当前结果（整图 float），reliable 为 C 中可信（反混合区）的像素。
    结构（缝、板间明暗、大块受光）= C（只信 reliable）与原画已知像素沿板向（u）的归一化平滑：缝是沿 u 的直线不受影响，
      15–20px 的亮点格、反混合噪声、补块格子被抹掉；σ10 → 40 → 120 逐级兜底（字压住处）；顶横档与木板分开平滑
      （横档暗得多，不能串）；再沿 v 轻锐化缝。
    细节 = 框下原画木板沿板向的残差（木纹、短条纹、疤；缝与板间明暗沿 u 不变，自然被去掉），按 v 折返、每折换一个
      u 平移贴过来，乘性叠加（亮度随受光走）。"""
    U, V = np.meshgrid(np.arange(*RECT_U), np.arange(*RECT_V))
    Yr = y_of(U, V)
    Or = sample_y(O, U, Yr)
    Cr = sample_y(C, U, Yr)
    yi = np.floor(Yr).astype(int)
    known = ~in_mod(U, yi) & ~in_mod(U, yi + 1)
    rel = reliable[np.clip(yi, 0, SIZE[1] - 1), U] & reliable[np.clip(yi + 1, 0, SIZE[1] - 1), U]
    base = np.where(known[..., None], Or, Cr)
    wt = ((known | rel) & (U >= STILE[1])).astype(np.float64)
    rail = V < RAIL_V1
    A = np.zeros_like(base)
    for sel in (rail, ~rail):
        w = wt * sel
        a1, d1 = nc_u(base, w, 10.0)
        a2, d2 = nc_u(base, w, 40.0)
        a3, _ = nc_u(base, w, 120.0)
        m1 = smoothstep(0.5, 2.0, d1)[..., None]
        m2 = smoothstep(0.5, 2.0, d2)[..., None]
        A = np.where(sel[..., None], a1 * m1 + (1 - m1) * (a2 * m2 + (1 - m2) * a3), A)
    A = A + 0.8 * (A - g_v(A, 1.5 / RECT_V[2]))
    Ol = lum(Or)
    ok = known & (V >= DET_SRC_V[0]) & (V < DET_SRC_V[1]) & (U >= DET_SRC_U[0]) & (U < DET_SRC_U[1])
    sm, _ = nc_u(Ol, ok.astype(np.float64), 8.0)
    d_src = np.where(ok, Ol / np.maximum(sm, 1) - 1, 0.0)
    dv = RECT_V[2]
    n_v = int(round((DET_SRC_V[1] - DET_SRC_V[0]) / dv))
    iv0 = int(round((DET_SRC_V[0] - RECT_V[0]) / dv))
    tv, k = pingpong((V - T_Y) / dv, n_v)
    sv = iv0 + np.floor(tv).astype(int)
    sh = np.array(DET_SHIFTS)[k % len(DET_SHIFTS)]
    su, _ = pingpong((U - DET_SRC_U[0] + sh).astype(np.float64), DET_SRC_U[1] - DET_SRC_U[0])
    su = DET_SRC_U[0] + np.floor(su).astype(int) - RECT_U[0]
    return A * (1 + PLANK_GAIN * d_src[sv, su][..., None])


def rect_to_image(R, x0, x1, y0, y1):
    """矫正域图取回整图坐标 [y0,y1)×[x0,x1)（沿 v 线性插值）。"""
    yy, xx = np.mgrid[y0:y1, x0:x1]
    fv = (v_of(xx.astype(np.float64), yy.astype(np.float64)) - RECT_V[0]) / RECT_V[2]
    iv = np.clip(np.floor(fv).astype(int), 0, R.shape[0] - 2)
    f = np.clip(fv - iv, 0, 1)[..., None]
    iu = xx - RECT_U[0]
    return (1 - f) * R[iv, iu] + f * R[iv + 1, iu]


def shutter_image(O, C, reliable):
    """木板 + 顶横档取回整图（x 1362–1640、y 140–380 的外扩框），并与改动区外原画接缝：
    低频失配（原画 − 合成，在缝外 10px 的窗扇像素上量）沿缝 σ5 平滑后向内 exp(−d/8) 衰减加上；
    右缝、下缝再与「沿板向镜像的原画」交叉淡化 5px，让木纹跨缝连续（右缝在矫正域里沿 u 镜像＝沿板缝方向，不会折成人字；
    下缝在矫正域同列沿 v 镜像，等价于整图竖直镜像）。"""
    x0, x1, y0, y1 = STILE[1], 1640, 140, 380
    Ti = rect_to_image(shutter_rect(O, C, reliable), x0, x1, y0, y1)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    xf, yf = xx.astype(np.float64), yy.astype(np.float64)
    te = top_edge(xf)
    ring = ~in_mod(xx, yy) & (yf >= te + 1.5) & (
        ((xx >= MOD[2]) & (xx < MOD[2] + 10)) | ((yy >= MOD[3]) & (yy < MOD[3] + 10)) | (yy < MOD[1]))
    Mf = gauss_nc(O[y0:y1, x0:x1] - Ti, ring.astype(np.float64), SEAM_LF[0])
    dist = np.minimum(MOD[2] - xf - 0.5, MOD[3] - yf - 0.5)
    dist = np.where(xx >= 1477, np.minimum(dist, yf + 0.5 - MOD[1]), dist)   # 横档上沿在 x≥1477 越出改动区上沿
    inside = in_mod(xx, yy)
    Ti = Ti + np.where(inside, np.exp(-np.maximum(dist, 0) / SEAM_LF[1]), 0.0)[..., None] * Mf
    xm = 2 * MOD[2] - 1 - xx
    right = sample_y(O, np.clip(xm, 0, SIZE[0] - 1), y_of(xm.astype(np.float64), v_of(xf, yf)))
    cr = (1 - smoothstep(-1.0, SEAM_XF, MOD[2] - xf - 0.5)) * inside
    Ti = Ti * (1 - cr[..., None]) + right * cr[..., None]
    cb = (1 - smoothstep(-1.0, SEAM_XF, MOD[3] - yf - 0.5)) * inside
    Ti = Ti * (1 - cb[..., None]) + O[np.clip(2 * MOD[3] - 1 - yy, 0, SIZE[1] - 1), xx] * cb[..., None]
    return Ti, (x0, x1, y0, y1)


def rebuild_shutter(O, C, reliable):
    """在当前结果 C（整图 float）上重建窗扇左上一带：木板重铺、顶横档接到左竖梃、竖梃顶、横档以上的墙、竖梃左侧墙面补肌理。
    只改改动区（MOD）以内、x ≥ 1184 的像素，返回新的整图 float。"""
    N = C.copy()
    X0, Y0, X1, Y1 = D_BOX[0], MOD[1], MOD[2], MOD[3]
    yy, xx = np.mgrid[Y0:Y1, X0:X1]
    xf, yf = xx.astype(np.float64), yy.astype(np.float64)
    te = top_edge(xf)
    # 5a) 木板 + 顶横档
    Ts, (sx0, _, sy0, _) = shutter_image(O, C, reliable)
    Ti = np.zeros(xx.shape + (3,))
    Ti[:, sx0 - X0:] = Ts[Y0 - sy0:Y1 - sy0, :X1 - sx0]
    # 5b) 竖梃顶：取下方 64px 的竖梃平移上来，亮度按竖梃身（C 的 y 224–335）的线性趋势压暗，暗部设下限
    rows = np.arange(224, 336)
    a, b = np.polyfit(rows, lum(C[224:336, 1338:1356]).mean(1), 1)
    st = C[np.clip(yy + STILE_SHIFT, 0, SIZE[1] - 1), xx] * ((a * yf + b) / (a * (yf + STILE_SHIFT) + b))[..., None]
    ls = np.maximum(lum(st), 1e-3)
    f0, f1 = STILE_FLOOR
    st = st * (np.where(ls < f0, f1 + (f0 - f1) * ls / f0, ls) / ls)[..., None]
    # 5c) 墙：肌理整块平移自窗扇上方原画墙（同一平移，墙内处处连续）；低频在竖梃左侧（D）取 C（檐影），
    #     竖梃顶以上与 x≥1300 的顶几行取「缝上方原画镜像」的低频；紧贴改动区上沿 5 行与镜像本身交叉淡化
    Mi = O[np.clip(2 * MOD[1] - 1 - yy, 0, SIZE[1] - 1), xx]
    Tr = O[np.clip(yy - WALL_SHIFT[1], 0, SIZE[1] - 1), np.clip(xx + WALL_SHIFT[0], 0, SIZE[0] - 1)]
    Ytr = lum(Tr)
    rel_w = Ytr / np.maximum(blur(Ytr, WALL_SIGMA), 1) - 1
    wt = ((xx >= 1180) & (xx < STILE[0]) & (yy >= D_BOX[1]) & (yy < 340)).astype(np.float64)
    wt[(xx >= 1328) & (yy < 262)] = 0          # C 里竖梃在 y<262 这段左沿错到 1329，不当墙用
    Lt = gauss_nc(C[Y0:Y1, X0:X1], wt, WALL_SIGMA)
    Lu = blur_rgb(Mi, WALL_SIGMA)
    wU = smoothstep(1300, 1312, xf) * (1 - smoothstep(D_BOX[1], D_BOX[1] + 11, yf))
    wR = smoothstep(1318, STILE[0], xf) * (1 - smoothstep(te - 4, te + 6, yf))
    wm = np.maximum(np.maximum(wU, wR), (xx >= STILE[0]).astype(np.float64))
    L = Lt * (1 - wm[..., None]) + Lu * wm[..., None]
    wall = L * (1 + (WALL_GAIN + (1 - WALL_GAIN) * wm) * rel_w)[..., None]
    c = smoothstep(MOD[1], MOD[1] + 5.5, yf)[..., None]
    wall = np.where((xx >= 1300)[..., None], Mi * (1 - c) + wall * c, wall)
    # 合成：顶边以下为窗扇（竖梃 / 木板横档），以上为墙；x<1335 全是墙
    al = np.clip((yf - te) / EDGE_W + 0.5, 0, 1)[..., None]
    below = np.where((xx < STILE[1])[..., None], st, Ti)
    comp = np.where((xx >= STILE[0])[..., None], wall * (1 - al) + below * al, wall)
    # 写回权重：D 向左 1184–1192、向下 285–300 淡入 C；竖梃在 256–268 淡入；x≥1300 的上带几行照写
    sxm = (xx >= STILE[0]) & (xx < STILE[1])
    wD = smoothstep(1184, 1192, xf) * (1 - smoothstep(285, 300, yf)) * ((yy >= D_BOX[1]) & (xx < STILE[0]))
    wS = np.where(sxm & (yf < te + 1), 1.0, sxm * (1 - smoothstep(STILE_END[0], STILE_END[1], yf)))
    wgt = np.maximum.reduce([wD, wS, (xx >= STILE[1]).astype(np.float64)])
    wgt = np.where((xx < STILE[0]) & (yy < D_BOX[1]), smoothstep(1300, 1306, xf), wgt)
    reg = C[Y0:Y1, X0:X1]
    new = reg * (1 - wgt[..., None]) + comp * wgt[..., None]
    N[Y0:Y1, X0:X1] = np.where(in_mod(xx, yy)[..., None], new, reg)
    return N


# ---------- 6. 墙面投影下沿残影（第 3 轮） ----------
FOOT_BOX = (1224, 344, 1272, 362)       # 只改这里（x0, y0, x1, y1）：墙面、原投影下沿（原图 y 357/358）以上
FOOT_REF_ROWS = (362, 368)              # 低频目标：框下原画 y 362–367（y 361 还在第 4 步下带里，不当原画）
FOOT_SIGMA_X = 3.0                      # 逐行沿 x 的低通 σ（σ6 时 x 1256–1267 的格缝在 4px 段上还剩 −11，σ3 剩 ≤ −6）
FOOT_RAMP = (344.0, 353.0)              # 自上而下 9 行渐入
FOOT_JOIN = (358, 362)                  # y 358→361 的目标由 362–367 均值渐变到原画 y 362 行本身，与下方逐行接上
FOOT_XFADE = (1224.0, 1228.0, 1266.0, 1272.0)   # 左右淡出（x 1268 起是另一格，本就没有台阶）
FOOT_PAD = 40                           # 取低通时左右多带的上下文


def fix_wall_foot(O, C):
    """墙面 x 1224–1272 的旧投影下沿残影：第 4 步下带的补块格（y 348–359）偏亮，与 y 360 起的格子之间留一条平直底线。
    逐行、逐通道取沿 x 的低通（σ3），换成框下原画 y 362–367 均值的同一低通（y 358→361 渐变到原画 y 362 行本身），
    FOOT_RAMP 自上而下渐入、FOOT_XFADE 左右淡出；低通以外的肌理原样保留（加性）。O、C 为整图 float，返回新整图。"""
    bx0, by0, bx1, by1 = FOOT_BOX
    xs0, xs1 = bx0 - FOOT_PAD, bx1 + FOOT_PAD

    def xlow(rows):
        return blur_xy(rows[:, xs0:xs1], FOOT_SIGMA_X, 0)[:, FOOT_PAD:FOOT_PAD + bx1 - bx0].astype(np.float64)
    ref = xlow(O[FOOT_REF_ROWS[0]:FOOT_REF_ROWS[1]].mean(0, keepdims=True))[0]
    base = xlow(O[by1:by1 + 1])[0]
    rows = np.arange(by0, by1)
    v = np.clip((rows - FOOT_JOIN[0]) / (FOOT_JOIN[1] - FOOT_JOIN[0]), 0, 1)
    target = ref[None] + v[:, None, None] * (base - ref)[None]
    wy = smoothstep(FOOT_RAMP[0], FOOT_RAMP[1], rows + 0.5)
    xc = np.arange(bx0, bx1) + 0.5
    a, b, c, d = FOOT_XFADE
    wx = smoothstep(a, b, xc) * (1 - smoothstep(c, d, xc))
    N = C.copy()
    N[by0:by1, bx0:bx1] += (wy[:, None] * wx[None, :])[..., None] * (target - xlow(C[by0:by1]))
    return N


# ---------- 7. 柱左沿瓦片越界（第 3 轮第 2 次） ----------
PILLAR_BOX = (1123, 187, 1157, 208)     # 只改这里（x0, y0, x1, y1）：x0 = 柱左沿（框上方原画、框内反混合都在 x 1123）
PILLAR_TOP_ROWS = (184, 188)            # 上参照：第 4 步上带外半（缝 188 以上）照上方原画镜像的柱身
PILLAR_BOT_ROWS = (208, 211)            # 下参照：反混合区的柱身
PILLAR_RAMP = (186.5, 189.0)            # 上缘渐入（y 187–188 与镜像柱身合）
PILLAR_XFADE = (1146.0, 1157.0)         # 右侧向原结果淡出（柱右沿 ≈1150 以右是暗面，原结果本来就对）
PILLAR_DET_SHIFT = 56                   # 竖向细节取源：框上方原画柱身 (x, y − 56)，即 y 131–151；避开上带镜像的来源 164–175，免得上下呼应
PILLAR_DET_SIGMA = 4.0                  # 细节 = 亮度 ÷ 沿 y 的 σ4 低通 − 1
PILLAR_DET_GAIN = 1.2                   # 结果相对细节 std 0.065（反混合区柱身 0.064，框上方原画 0.074–0.081）
PILLAR_DET_FADE = (204.0, 209.0)        # 细节在最底几行淡出，与反混合区柱身接上


def fix_pillar_edge(O, C):
    """柱左沿：第 4 步上带内半补块把远屋瓦片高光带进柱身 8–10px（x 1123–1133、y 188–204），4 倍下读成「瓦压在柱前」。
    x ≥ 1123 的柱列按柱身重做：低频逐列在上参照（y 184–187，镜像柱身）与下参照（y 208–210，反混合柱身）之间沿 y 线性插值
    （柱身自檐下往下渐亮，横向木纹轮廓由两端交叉淡化带过来），竖向细节取框上方原画柱身的相对高通，乘性叠加；
    上缘 2 行渐入、右侧淡出，x < 1123 的瓦面不动 —— 柱左沿由此从梁底 y 187 一直直通下去。O、C 为整图 float，返回新整图。"""
    x0, y0, x1, y1 = PILLAR_BOX
    t0, t1 = PILLAR_TOP_ROWS
    b0, b1 = PILLAR_BOT_ROWS
    Pt = C[t0:t1, x0:x1].mean(0)
    Pb = C[b0:b1, x0:x1].mean(0)
    ys = np.arange(y0, y1).astype(np.float64)
    t = ((ys - (t0 + t1 - 1) / 2.0) / ((b0 + b1 - 1) / 2.0 - (t0 + t1 - 1) / 2.0))[:, None, None]
    base = (1 - t) * Pt[None] + t * Pb[None]
    pad, sh = 20, PILLAR_DET_SHIFT
    S = lum(O[y0 - sh - pad:y1 - sh + pad, x0:x1])
    rel = (S / np.maximum(blur_xy(S, 0, PILLAR_DET_SIGMA).astype(np.float64), 1) - 1)[pad:-pad]
    rel = rel * (1 - smoothstep(*PILLAR_DET_FADE, ys + 0.5))[:, None]
    new = base * (1 + PILLAR_DET_GAIN * rel)[..., None]
    wx = 1 - smoothstep(*PILLAR_XFADE, np.arange(x0, x1) + 0.5)
    wy = smoothstep(*PILLAR_RAMP, ys + 0.5)
    w = (wy[:, None] * wx[None, :])[..., None]
    N = C.copy()
    N[y0:y1, x0:x1] = C[y0:y1, x0:x1] * (1 - w) + new * w
    return N


def process(full):
    O_full = full.astype(np.float64)
    g, off = fit_unblend(O_full)
    wx0, wy0, wx1, wy1 = WIN
    O = O_full[wy0:wy1, wx0:wx1]
    geo = Geo(O)
    img = O.copy()
    # 1) 反混合（字区外）
    core_rgb = unblend_core(geo, g, off, full)
    lval = geo.core & ~geo.text_d
    img[lval] = core_rgb[lval]
    # 2) 电平校正：下缝、右缝两侧内容连续（柱/墙/竖梃/窗板竖穿下沿，窗板横纹穿右沿），外 − 内差作狄利克雷边；
    #    上沿（暗梁、窗扇斜顶梁）与左沿（灯笼）是真边，取零法向导数，不拿来校
    cx0, cy0, cx1, cy1 = CORE
    bdiff, _ = seam_diff(img, "bot", (cx0, cx1))
    rdiff, _ = seam_diff(img, "right", (cy0, cy1))
    delta = laplace_br(bdiff, rdiff)
    cs = (slice(cy0 - wy0, cy1 - wy0), slice(cx0 - wx0, cx1 - wx0))
    img[cs] += delta
    # 2b) 远屋瓦面：按行对齐灯笼左边同高度的瓦
    tile_d = tile_rows_delta(img, full)
    img += tile_d
    # 3) 补字区：源先只取框内已还原区（肌理与四周同一个样），整块找不到再放宽到框下/框右原画
    #    （不取框上暗梁、左边灯笼，也不取兵士头部）
    xx, yy = geo.xx, geo.yy
    src = (~geo.mod & ((yy >= MOD[3]) | (xx >= MOD[2]))) | lval
    for x0, y0, x1, y1 in NO_SOURCE:
        src &= ~((xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1))
    img, used = fill_cells(img, ~geo.mod | lval, geo.text_d, (lval, src), geo.core)
    # 3b) 字区低频改取反混合：补块从框下亮墙取源时会把受光带进檐下暗处，按反混合的低频把明暗拉回
    if TEXT_LOWPASS > 0:
        ref = lum(core_rgb) + lum(delta_full(delta, img.shape)) + tile_d[..., 0]
        m2 = (geo.core & ~dilate(geo.text, TEXT_LP_EXCL)).astype(np.float64)
        cm = geo.core.astype(np.float64)
        corr = nblur(ref, m2, TEXT_LOWPASS) - nblur(lum(img), cm, TEXT_LOWPASS)
        wz = np.clip(blur(geo.text_d.astype(np.float64), 2.0) * 1.5, 0, 1) * geo.core
        img += (corr * wz)[..., None]
    # 3c) 字区格子缝去块（补块按 12px 格网拼，膜只保证格边连续到一阶，受光不同的源块之间还会留一道台阶），
    #     再把字区色度同框内其余处一样按列模型重建（补块源色相与模型略有出入，会显出块）
    zc = geo.text_d
    Yz = lum(img)
    img += (deblock(Yz, dilate(zc, 4) & geo.core, CELL_SEAM_T, 2, size=CELL, grid_origin=WIN[:2]) - Yz)[..., None]
    img[zc] = apply_chroma_model(lum(img), chroma_model(ycc(full.astype(np.float64))))[zc]
    # 4) 边带：上带左段先两侧镜像拼，再只保留外半（缝以上，暗梁/墙/柱照上方原画镜像），内半改补块——内半若也镜像，
    #    框内顶上 20 行会上下对称地出现两遍，4 倍下读成一块方斑。暗梁、暗木块那几列（真边）内半补块时不看缝以上，
    #    免得拉普拉斯膜把墙往暗梁上抹；缝上下 1 行再轻轻合一下，边不至于数码硬。
    #    上带右段（竖梃顶、斜顶梁）、右带、下带全补块；左带最后按灯笼中轴镜像拼。
    fws = {}
    fws["top"] = blend_band(img, TOP_BAND, 0, SEAMS["top"][2], "low", (LEFT_BAND[1], TOP_CELLS_X))
    left = geo.mod & (xx < LEFT_BAND[1])
    seam_y = int(SEAMS["top"][2])
    top_inner = (yy >= seam_y) & (yy < TOP_BAND[1]) & (xx >= LEFT_BAND[1]) & (xx < TOP_CELLS_X)
    todo = geo.mod & ~left & (((yy < TOP_BAND[1]) & (xx >= TOP_CELLS_X)) | (xx >= RIGHT_BAND[0]) | (yy >= BOT_BAND[0])
                              | top_inner)
    crisp_x = np.zeros_like(todo)
    for a, b in TOP_CRISP_X:
        crisp_x |= (xx >= a) & (xx < b)
    ring_ok = ~((yy >= TOP_BAND[0]) & (yy < seam_y) & crisp_x)
    src2 = ~geo.mod | lval
    for x0, y0, x1, y1 in NO_SOURCE:
        src2 &= ~((xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1))
    img, used2 = fill_cells(img, ~todo & ~left, todo, src2, geo.core, offs=make_offsets(40, 0), ring_ok=ring_ok)
    r = seam_y - WIN[1]
    cx = crisp_x[r]
    a_, b_ = img[r - 1, cx].copy(), img[r, cx].copy()
    img[r - 1, cx] = 0.75 * a_ + 0.25 * b_
    img[r, cx] = 0.25 * a_ + 0.75 * b_
    left_band(img)
    # 5) 窗扇与墙面重建（第 2 轮）：在整图坐标上做，C = 原图 + 第 1–4 步结果（改动区内）
    C = O_full.copy()
    C[wy0:wy1, wx0:wx1][geo.mod] = img[geo.mod]
    reliable = np.zeros(full.shape[:2], bool)
    reliable[wy0:wy1, wx0:wx1] = lval
    reliable[:, RIGHT_BAND[0]:] = False                    # 右带是格子补块，不当结构依据
    C = rebuild_shutter(O_full, C, reliable)
    # 6) 墙面投影下沿残影（第 3 轮）
    C = fix_wall_foot(O_full, C)
    # 7) 柱左沿瓦片越界（第 3 轮第 2 次）
    C = fix_pillar_edge(O_full, C)
    out = full.copy()
    win = np.clip(C[wy0:wy1, wx0:wx1] + 0.5, 0, 255).astype(np.uint8)
    out[wy0:wy1, wx0:wx1][geo.mod] = win[geo.mod]
    info = dict(g=g, off=off, cells=len(used) + len(used2), fws=fws, geo=geo,
                delta=(float(np.abs(delta).mean()), float(np.abs(delta).max())),
                tile=float(np.abs(tile_d[..., 0]).max()))
    return out, info


# ---------- 写出 ----------
def mcu_box():
    ms = 16
    x0 = (MOD[0] - 2) // ms * ms
    y0 = (MOD[1] - 2) // ms * ms
    x1 = -(-(MOD[2] + 2) // ms) * ms
    y1 = -(-(MOD[3] + 2) // ms) * ms
    return x0, y0, x1, y1


def write_jpeg_mcu(src_path, src_img, new_img, box, out_path):
    """jpegtran -drop 无损嵌回（支持 4:2:0 / 4:4:4，box 须按 MCU 对齐）；原图 progressive 则输出也 progressive。"""
    sampling = JpegImagePlugin.get_sampling(src_img)
    mcu = {0: 8, 1: 16, 2: 16}.get(sampling)
    jt = shutil.which("jpegtran")
    x0, y0, x1, y1 = box
    if jt is None or mcu is None or any(v % mcu for v in box):
        raise RuntimeError("需要 jpegtran，且嵌回框须按 MCU(%s) 对齐：%s" % (mcu, box))
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        drop = os.path.join(td, "drop.jpg")
        tmp_out = os.path.join(td, "out.jpg")
        Image.fromarray(new_img[y0:y1, x0:x1]).save(drop, "JPEG", qtables=src_img.quantization, subsampling=sampling)
        cmd = [jt, "-copy", "all"]
        if src_img.info.get("progressive"):
            cmd.append("-progressive")
        cmd += ["-drop", "+%d+%d" % (x0, y0), drop, "-outfile", tmp_out, src_path]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("jpegtran 失败：%s" % r.stderr.strip()[:200])
        shutil.copyfile(tmp_out, out_path)
    return "jpegtran -drop +%d+%d（MCU %d，块 %dx%d%s）" % (x0, y0, mcu, x1 - x0, y1 - y0,
                                                        "，progressive" if src_img.info.get("progressive") else "")


def djpeg_nosmooth(path):
    dj = shutil.which("djpeg")
    if not dj:
        return None
    r = subprocess.run([dj, "-nosmooth", "-pnm", path], capture_output=True)
    if r.returncode != 0:
        return None
    import io
    return np.asarray(Image.open(io.BytesIO(r.stdout)).convert("RGB"))


# ---------- 自检 ----------
def contrast_ring(Y, m, k0, k1):
    """m 内均值 − m 外扩 k0..k1 环带均值。"""
    ring = dilate(m, k1) & ~dilate(m, k0)
    return float(Y[m].mean() - Y[ring].mean())


def self_check(before, after, box, geo, src_path, out_path):
    rep = {}
    wx0, wy0, wx1, wy1 = WIN
    b = before[wy0:wy1, wx0:wx1].astype(np.float64)
    a = after[wy0:wy1, wx0:wx1].astype(np.float64)
    Yb, Ya = lum(b), lum(a)
    # 残留：描边、字、细线相对周边的亮度对比；投影带相对外侧
    border_core = geo.outer & ~dilate(geo.inner, 1) & ~dilate(~geo.outer, 1)
    rep["border_frac"] = (border_fraction(b, geo)[0], border_fraction(a, geo)[0])
    # 对照：同形环带下移 190px（框下窗扇、墙、柱）在原画里「牌子棕黄」的自然占比
    ctrl = np.roll(border_core, 190, 0)
    rep["border_frac_ctrl"] = float((np.abs(b[ctrl] - BORDER_RGB).max(-1) < 22).mean())
    # 文字鬼影：亮度带通（σ0.8–4、σ2–10）与字形掩膜同一带通的相关系数及回归幅度（级 / 单位字形）
    T = geo.text.astype(np.float64)
    ghost = {}
    for s0, s1 in ((0.8, 4.0), (2.0, 10.0)):
        tb = blur(T, s0) - blur(T, s1)
        vals = []
        for Y in (Yb, Ya):
            bp = blur(Y, s0) - blur(Y, s1)
            vals.append((float(np.corrcoef(bp[geo.core], tb[geo.core])[0, 1]),
                         float((bp[geo.core] * tb[geo.core]).sum() / (tb[geo.core] ** 2).sum())))
        ghost["σ%.1f–%g" % (s0, s1)] = vals
    rep["ghost"] = ghost
    rep["text"] = (contrast_ring(Yb, geo.text, 3, 6), contrast_ring(Ya, geo.text, 3, 6))
    line = geo.line & ~dilate(geo.text, 2)
    rep["line"] = (contrast_ring(Yb, line, 2, 4), contrast_ring(Ya, line, 2, 4))
    rep["border"] = (contrast_ring(Yb, border_core, 3, 6), contrast_ring(Ya, border_core, 3, 6))
    sh = geo.shadow & ~dilate(geo.outer, 1)
    rep["shadow"] = (contrast_ring(Yb, sh, 3, 6), contrast_ring(Ya, sh, 3, 6))
    # 框内相对框外：改动矩形内 4px 环与外 4px 环的 ΔE（after），对照同图其他位置同尺寸矩形的自然值
    lab_a = srgb_to_lab(np.clip(a, 0, 255))
    lab_b = srgb_to_lab(np.clip(b, 0, 255))
    mod = geo.mod
    inring = mod & dilate(~mod, 4)
    outring = dilate(mod, 4) & ~mod
    rep["dE_step"] = float(np.sqrt(((lab_a[inring].mean(0) - lab_a[outring].mean(0)) ** 2).sum()))
    # 各边分别
    steps = {}
    for name, sel in (("上", geo.yy < MOD[1] + 4), ("下", geo.yy >= MOD[3] - 4), ("左", geo.xx < MOD[0] + 4), ("右", geo.xx >= MOD[2] - 4)):
        si = inring & sel
        so = outring & dilate(sel & mod, 5)
        steps[name] = float(Ya[si].mean() - Ya[so].mean())
    rep["steps_L"] = steps
    dE = np.sqrt(((lab_a - lab_b) ** 2).sum(-1))
    rep["dE_ring_out"] = float(dE[outring].mean())
    # 块外
    diff = np.abs(after.astype(np.int16) - before.astype(np.int16)).max(-1)
    x0, y0, x1, y1 = box
    inbox = np.zeros(diff.shape, bool)
    inbox[y0:y1, x0:x1] = True
    modfull = np.zeros(diff.shape, bool)
    modfull[MOD[1]:MOD[3], MOD[0]:MOD[2]] = True
    rep["outside_box_changed"] = int((diff[~inbox] > 0).sum())
    rep["outside_box_maxdiff"] = int(diff[~inbox].max())
    ring1 = ~inbox & dilate(inbox, 1)
    rep["outside_box_changed_not_ring1"] = int((diff[~inbox & ~ring1] > 0).sum())
    rep["outside_mod_mad"] = float(np.abs(after.astype(np.int16) - before.astype(np.int16))[~modfull].mean())
    rep["box_not_mod_mad"] = float(np.abs(after.astype(np.int16) - before.astype(np.int16))[inbox & ~modfull].mean())
    nb, na = djpeg_nosmooth(src_path), djpeg_nosmooth(out_path)
    if nb is not None and na is not None:
        d2 = np.abs(na.astype(np.int16) - nb.astype(np.int16)).max(-1)
        rep["nosmooth_outside_box_changed"] = int((d2[~inbox] > 0).sum())
    # 高频肌理：框内还原区与框下同材质
    def hf(Y):
        return Y - box_mean(Y, 1)
    tex = {}
    Yf = lum(after.astype(np.float64))
    for name, (x0_, x1_), yin, (u0, u1), yout in (
            ("墙", (1195, 1320), (310, 338), (1195, 1320), (365, 395)),
            ("窗板", (1400, 1590), (310, 338), (1400, 1590), (365, 395)),
            ("柱", (1135, 1168), (310, 338), (1135, 1168), (365, 395)),
            ("瓦", (1060, 1118), (230, 330), (950, 1000), (230, 330))):
        tex[name] = (float(hf(Yf)[yin[0]:yin[1], x0_:x1_].std()), float(hf(Yf)[yout[0]:yout[1], u0:u1].std()))
    rep["tex"] = tex
    rep["r2"] = review_r2(Yf)
    rep["r3"] = review_r3(Yf, lum(before.astype(np.float64)))
    return rep


def review_r2(Y):
    """第 2 轮评审各项复测（Y 为整图亮度）。高通 = Y − 5×5 盒均值（与评审同口径）。"""
    H = Y - box_mean(Y, 2)
    r = {}
    r["木板高通"] = (float(H[215:340, 1420:1600].std()), float(H[365:470, 1420:1600].std()))
    r["墙高通"] = (float(H[195:270, 1190:1325].std()), float(H[100:170, 1300:1480].std()))

    def edge(xs):
        st, pos = [], []
        for x in xs:
            t = top_edge(float(x))
            y0 = int(t) - 6
            if y0 + 13 > MOD[1] + 3 and x >= 1484:        # 原画可见段只量改动区以上
                continue
            d = -np.diff(Y[y0:y0 + 13, x])
            i = int(np.argmax(d))
            st.append(d[i])
            pos.append(y0 + i + 0.5 - t)
        return np.array(st), np.array(pos)
    st, pos = edge(range(1396, 1485))
    st0, _ = edge(range(1484, 1617))
    r["顶边边强"] = (float(st.mean()), float(np.percentile(st, 10)), float(st0.mean()))
    r["顶边位置"] = (float(pos.mean()), float(pos.std()))
    g = np.abs(np.diff(Y[250:264, 1605:1624], axis=1)).mean(0)      # g[i] = |Y[1606+i] − Y[1605+i]|
    r["x1615列梯度"] = (float(g[1615 - 1606]), float(g[1616 - 1606]), float(np.median(g)))
    c = Y[195:222, 1330:1400]
    r["窗角最暗"] = (float(c.min()), float(np.percentile(c, 1)))
    r["右缝"] = (float(np.abs(Y[176:362, 1622] - Y[176:362, 1623]).mean()),
                 float(np.abs(Y[176:362, 1623] - Y[176:362, 1624]).mean()))
    r["下缝"] = (float(np.abs(Y[361, 1362:1623] - Y[362, 1362:1623]).mean()),
                 float(np.abs(Y[362, 1362:1623] - Y[363, 1362:1623]).mean()))
    r["上缝"] = (float(np.abs(Y[176, 1300:1623] - Y[175, 1300:1623]).mean()),
                 float(np.abs(Y[175, 1300:1623] - Y[174, 1300:1623]).mean()))
    L = blur(Y, 2.0) - blur(Y, 4.0)

    def blobs(y0, y1, x0, x1, thr=2.0):
        s = L[y0:y1, x0:x1]
        m = s > thr
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            m &= s >= np.roll(np.roll(s, dy, 0), dx, 1)
        return float(m.sum() / s.size * 1e4)
    r["亮斑密度"] = (blobs(215, 340, 1420, 1600), blobs(365, 470, 1420, 1600))
    return r


# ---- 第 3 轮自检：原牌四边残影扫描 ----
EDGE_SEG, EDGE_STEP, EDGE_FLOOR, EDGE_RATIO = 24, 8, 1.5, 2.0
EDGE_SCAN = {  # 边: (轴, 跳变位置区间 [p0, p1)（y→y+1 或 x→x+1）, 自然参照：该边外侧改动区外的原画行 / 列)
    "上": (0, (172, 210), (120, 172)),     # 改动区上沿 176、外框 179/180、框内沿 184、缝 188、顶线 190–196、上带内沿 208
    "下": (0, (336, 367), (364, 420)),     # 下带 339、框内沿 347、外框 351、投影下沿 358、改动区下沿 362
    "左": (1, (1036, 1060), (984, 1036)),  # 改动区 1041、外框 1045、框内沿 1049、左带内沿 1057
    "右": (1, (1596, 1628), (1628, 1700)),  # 右带 1599、框内沿 1607、外框 1611、投影 1619、改动区 1623
}
EDGE_TILE_REF = ((TILE_REF_X[0], TILE_REF_X[1] - EDGE_SEG), (200, 330))   # 远屋瓦面列的同材质参照：灯笼左边的瓦
EDGE_STRUCT = [((1046, 1126), (186, 188)),   # 远屋瓦面上方暗梁的梁底
               ((1176, 1300), (186, 188))]   # 墙上方暗木块的底（与梁底同高的一道横木，反混合看得到）
RAIL_LO_V = (165.0, 172.0)                   # 顶横档下沿亮线与其下暗缝（矫正域 v）


def edge_struct_cols(xs, p):
    """上边第 p→p+1 行跳变里属于结构边的列：梁底 / 暗木块底（列区间 × 行 186–188），
    顶横档上沿（该列顶边拟合线 ±2 行）与下沿亮线（该列 v 165–172 所跨的行 ±2）。"""
    m = np.zeros(len(xs), bool)
    for (ex0, ex1), (py0, py1) in EDGE_STRUCT:
        if py0 <= p <= py1:
            m |= (xs >= ex0) & (xs < ex1)
    c = p + 0.5
    xf = xs.astype(np.float64)
    m |= (xs >= STILE[0]) & (np.abs(c - top_edge(xf)) <= 2)
    m |= (xs >= STILE[1]) & (c >= y_of(xf, RAIL_LO_V[0]) - 2) & (c <= y_of(xf, RAIL_LO_V[1]) + 2)
    return m


def edge_scan(Y, Yb):
    """沿原牌四边按 24px 段（步 8）算行 / 列跳变（段均值差），除以同段在该边外侧改动区外原画 Yb 的自然 99 分位
    （远屋瓦面列另取灯笼左边的瓦，取大；下限 EDGE_FLOOR）。返回 [(比, 边, 段起, 位置, 跳变, 阈), …]，按比降序。"""
    def steps(A, lo, hi, seg):
        return (A[lo + 1:hi + 1, seg] - A[lo:hi, seg]).mean(1)
    res = []
    for name, (axis, (p0, p1), (r0, r1)) in EDGE_SCAN.items():
        A, B = (Y, Yb) if axis == 0 else (Y.T, Yb.T)
        s0, s1 = (MOD[0], MOD[2]) if axis == 0 else (MOD[1], MOD[3])
        for a in range(s0, s1 - EDGE_SEG + 1, EDGE_STEP):
            seg = slice(a, a + EDGE_SEG)
            p99 = [np.percentile(np.abs(steps(B, r0, r1, seg)), 99)]
            if axis == 0 and a + EDGE_SEG / 2 < TILE_X1:
                us, (v0, v1) = EDGE_TILE_REF
                p99 += [np.percentile(np.abs(steps(Yb, v0, v1, slice(u, u + EDGE_SEG))), 99) for u in us]
            thr = max(max(p99), EDGE_FLOOR)
            xs = np.arange(a, a + EDGE_SEG)
            for p in range(p0, p1):
                d = A[p + 1, seg] - A[p, seg]
                if name == "上":
                    keep = ~edge_struct_cols(xs, p)
                    if keep.sum() < EDGE_SEG / 2:
                        continue
                    d = d[keep]
                s = float(d.mean())
                res.append((abs(s) / thr, name, a, p, s, thr))
    res.sort(key=lambda t: -t[0])
    return res


def pillar_dev(Y, y0, y1, x0=1124, x1=1134):
    """柱左沿内侧 x 1124–1133 的逐行均亮偏离「上参照 4 行 → 下参照 3 行」线性插值的最大绝对值（瓦片高光越界时这里凸起）。"""
    top, bot = Y[y0 - 4:y0, x0:x1].mean(), Y[y1:y1 + 3, x0:x1].mean()
    ct, cb = y0 - 2.5, y1 + 1.0
    rows = np.arange(y0, y1)
    interp = top + (rows - ct) / (cb - ct) * (bot - top)
    return float(np.abs(Y[y0:y1, x0:x1].mean(1) - interp).max())


def review_r3(Y, Yb):
    """第 3 轮评审项复测（整图亮度，Y 为结果、Yb 为原图）：墙面投影下沿（F）、原牌四边残影扫描、柱左沿。"""
    r = {}
    r["柱左沿"] = (pillar_dev(Y, 188, 208), pillar_dev(Yb, 131, 151), pillar_dev(Y, 240, 260))
    bx0, _, bx1, _ = FOOT_BOX
    segs = range(bx0, bx1 - EDGE_SEG + 1)
    r["F跳变"] = max(abs(float((Y[y + 1, a:a + EDGE_SEG] - Y[y, a:a + EDGE_SEG]).mean())) for y in range(356, 362) for a in segs)
    r["F自然"] = min(float(np.percentile(np.abs((Yb[365:421, a:a + EDGE_SEG] - Yb[364:420, a:a + EDGE_SEG]).mean(1)), 99))
                   for a in segs)
    dm = [float(Y[352:359, a:a + 8].mean() - Y[361:368, a:a + 8].mean()) for a in range(1230, 1262, 8)]
    r["F上下差"] = (min(dm), max(dm))
    res = edge_scan(Y, Yb)
    r["四边"] = res
    r["四边各边"] = {k: max(t[0] for t in res if t[1] == k) for k in EDGE_SCAN}
    r["四边原图"] = edge_scan(Yb, Yb)[0][0]
    return r


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", default=DEFAULT_SRC)
    ap.add_argument("--out", default=None, help="默认与 --src 相同（须加 --in-place）")
    ap.add_argument("--in-place", action="store_true", help="允许输出覆盖输入文件")
    ap.add_argument("--force", action="store_true", help="跳过幂等检查（调试用）")
    args = ap.parse_args(argv)
    out_path = args.out or args.src
    if os.path.abspath(args.src) == os.path.abspath(out_path) and not args.in_place:
        print("输出与输入同一路径，需加 --in-place 才写；未写任何文件。")
        return 2
    im = Image.open(args.src)
    if im.size != SIZE or im.format != "JPEG":
        print("输入不是 1920x1080 JPEG（%s %s），不是这张底图，跳过。" % (im.format, im.size))
        return 2
    src = np.asarray(im.convert("RGB"))
    wx0, wy0, wx1, wy1 = WIN
    geo = Geo(src[wy0:wy1, wx0:wx1].astype(np.float64))
    frac, n = border_fraction(geo.O, geo)
    print("输入 %s（%d 字节）：描边环带 %d 像素里牌子棕黄占 %.1f%%" % (args.src, os.path.getsize(args.src), n, 100 * frac))
    if frac < SKIP_BORDER_FRAC and not args.force:
        print("  棕黄描边占比 < %.0f%%：判定牌子已抹过，跳过，未写文件。" % (100 * SKIP_BORDER_FRAC))
        return 0
    new, info = process(src)
    box = mcu_box()
    with tempfile.TemporaryDirectory() as td:
        before_path = os.path.join(td, "before.jpg")      # 就地写时留一份输入字节，块外 DCT 核对用
        shutil.copyfile(args.src, before_path)
        how = write_jpeg_mcu(before_path, im, new, box, out_path)
        after = np.asarray(Image.open(out_path).convert("RGB"))
        rep = self_check(src, after, box, info["geo"], before_path, out_path)
    print("写出 %s（%d 字节，%s）" % (out_path, os.path.getsize(out_path), how))
    print("  反混合 g = (%.4f, %.4f, %.4f)，off = (%.1f, %.1f, %.1f)；补字 %d 格；电平校正 |Δ| 均 %.2f、最大 %.2f"
          % (*info["g"], *info["off"], info["cells"], *info["delta"]))
    print("  残留（前 → 后）：棕黄描边占比 %.1f%% → %.1f%%（同形环带下移 190px 的自然占比 %.1f%%）；字/箭头相对周边亮度 %.1f → %.2f；"
          "顶线 %.1f → %.2f；描边 %.1f → %.2f；投影带 %.1f → %.2f"
          % (100 * rep["border_frac"][0], 100 * rep["border_frac"][1], 100 * rep["border_frac_ctrl"],
             *rep["text"], *rep["line"], *rep["border"], *rep["shadow"]))
    print("  文字鬼影（亮度带通与字形相关 r / 幅度 级，前 → 后）：" + "；".join(
        "%s r %.3f/%.1f → %.3f/%.2f" % (k, v[0][0], v[0][1], v[1][0], v[1][1]) for k, v in rep["ghost"].items()))
    print("  改动矩形内外 4px 环：均色 ΔE76 %.2f；亮度台阶 %s；外环前后 ΔE %.3f"
          % (rep["dE_step"], "、".join("%s %.2f" % kv for kv in rep["steps_L"].items()), rep["dE_ring_out"]))
    print("  改动矩形外平均绝对差 %.4f；MCU 框内非改动区平均绝对差 %.3f"
          % (rep["outside_mod_mad"], rep["box_not_mod_mad"]))
    print("  MCU 框外变动像素 %d（最大差 %d；除紧贴框边 1px 外 %d）；djpeg -nosmooth 解码 MCU 框外变动像素 %s"
          % (rep["outside_box_changed"], rep["outside_box_maxdiff"], rep["outside_box_changed_not_ring1"],
             rep.get("nosmooth_outside_box_changed", "n/a")))
    print("  高频肌理 std（还原区 / 框外同材质）：" + "；".join("%s %.2f/%.2f" % (k, *v) for k, v in rep["tex"].items()))
    r2 = rep["r2"]
    print("  第 2 轮评审项：木板高通 %.2f（框下同板 %.2f，目标 ≥4.5）；墙高通 %.2f（框上方同墙 %.2f，目标 ≥2.8）；"
          "木板亮斑密度 %.1f/万像素（框下同板 %.1f）" % (*r2["木板高通"], *r2["墙高通"], *r2["亮斑密度"]))
    print("  顶边 x1396–1484：逐列 1px 最大跳变均值 %.1f、10%% 分位 %.1f（原画可见段 %.1f，目标 ≥11）；边位置偏离拟合线均值 %.2f、std %.2f px"
          % (*r2["顶边边强"], *r2["顶边位置"]))
    print("  x1615 列梯度 %.2f、x1616 %.2f（邻列中位 %.2f）；窗角 x1330–1400×y195–222 最暗 %.1f、1%% 分位 %.1f"
          % (*r2["x1615列梯度"], *r2["窗角最暗"]))
    print("  缝跳变（缝上一对 / 缝外相邻一对，均亮度差绝对值）：右 %.2f/%.2f、下 %.2f/%.2f、上 %.2f/%.2f"
          % (*r2["右缝"], *r2["下缝"], *r2["上缝"]))
    r3 = rep["r3"]
    print("  第 3 轮评审项 F（墙面投影下沿 x %d–%d）：24px 段 y356–362 行跳变最大 |Δ| %.2f（门槛 5；同处自然 99 分位 ≥%.2f）；"
          "y352–358 − y361–367（8px 段，x 1230–1262）%+.1f 至 %+.1f（门槛 ±10）"
          % (FOOT_BOX[0], FOOT_BOX[2], r3["F跳变"], r3["F自然"], *r3["F上下差"]))
    hits = [t for t in r3["四边"] if t[0] >= EDGE_RATIO]
    print("  原牌四边残影扫描（24px 段跳变 / 同处自然 99 分位，门槛 <%g；原图同一扫描最大 %.1f）：各边最大 %s；≥%g 的 %d 处%s"
          % (EDGE_RATIO, r3["四边原图"], "、".join("%s %.2f" % kv for kv in r3["四边各边"].items()), EDGE_RATIO, len(hits),
             ("：" + "；".join("%s 段 x/y %d 位置 %d 跳变 %+.1f 比 %.2f" % (t[1], t[2], t[3], t[4], t[0]) for t in hits[:6])
              + ("…" if len(hits) > 6 else "")) if hits else ""))
    print("  柱左沿 x1124–1133 逐行均亮偏离上下参照插值：y188–207 最大 %.2f（同法自然：框上方原画柱身 y131–150 %.2f、"
          "反混合区柱身 y240–259 %.2f）" % r3["柱左沿"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
