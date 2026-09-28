#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""舆图修瑕：标题底图与开场首镜里的西式罗经（风玫瑰）、西式海蛇头颈用程序抹掉（史实纠偏），其余逐字节不动。

来由（考证见 docs/史实核对_兴化1277与底图穿帮_2026-09-26.md 第三节、docs/资产史实待修_2026-09-27.md 的 M1 / M2 / G1）：
  · assets/bg_world_map.jpg（1672x941，标题屏底图，Main.gd 标题页 `_set_background_file("bg_world_map.jpg")`）右下角有一枚
    32 向风玫瑰。这是地中海波特兰海图（13—14 世纪欧洲）的画法，宋人看方位用二十四向针位和针路簿，海图上不画它。
    风玫瑰大半压在龟裂做旧的米黄纸面上，左缘压着蓝色洗染边，底下不是海。它左边的浪花带里还盘着一条西洋古地图式的海蛇，
    也是西式装饰母题。
  · assets/cutscene/cs_world_map_gold.jpg（1792x1008，开场 opening 第 1 镜「舆图总纲」）右上有一枚细线八向风玫瑰，
    落在金纸和淡蓝洗染上，紧贴竖排题字「宋理宗宝祐三年」，镜头前段一直在画内。
  2026-09-28 Snow 拍板走 A′（决策备忘 #4、#5）：程序抹掉这两处，其余不动，两张图共用本脚本。
  原型、试错和引擎内截帧的记录在决策材料 title.md、title_notes.md 里（~/tmp/nk1-arttodo/decide/，未入库）。

抹什么（表驱动：IMAGES 每张图一条，每个待补区一条）：
  · bg / compass：罗经外环圆盘（心 (1474,700)，r113）加四臂墨线。四臂的包络框里取比局部底色（灰度闭运算 r6）暗 16 以上的像素，
    膨胀 4px。x≥1627 不补：东尖离内框竖线（x≈1630）只有 7px。
  · bg / serpent：海蛇只抠头颈和浪花带以上的盘身（多边形），浪花带留作浪头，蛇身余段混进浪花里。两条虚线航路原本汇到蛇头，
    现在止于一团浪。
  · cs / compass：圆盘 r66 加八臂粗线，整体膨胀 3px。
  保护区（羽化权重强制为 0，一个像素都不合成）：bg 的右框线（x≥1628）、下框线（y≥903）、西南角朱印 (1346–1427, 822–903)。

做法（纯 numpy + PIL；不依赖 cv2 / scipy）：
  1. 低频（底色）：先做一次排除洞的归一化模糊（盒式 r10，三遍），再用多重网格 Jacobi 做调和填充。洞里的底色是周边颜色的平滑延续，
     蓝洗到纸面的过渡、右下角的暗角都能自然接上，不出色块边。
  2. 高频（龟裂、纸纹、海纹）：拼贴法（quilting）。块 40px（cs 36px）、重叠 12px，用 FFT 算 SSD 挑供体块。
     代价 = 与已知或已填高频的差 + 0.25 × 供体底色与目标底色的差，所以海面块只配海面、纸面块只配纸面。
     在同一块附近（半块以内）不重复取；重叠处加权平均；洞外 8px 羽化，羽化只混高频。不做镜像拼接
     （09-26 福州 T3 程序补块镜像拼接，留下了竖缝和矩形边）。
  3. 供体池按区分开，各用各的：
     bg 罗经只取纸面（上方 x≥1400 的纸面、罗经四周、下方 x≥1356），海蛇只取海面和浪花。
     原型第一轮两处合用一个池，浪花带底部偏米色，被当成纸面借到罗经南臂边，冒出两道米色小浪花，所以分开。
     罗经那一遍把海蛇区设为「不补、也不当底色参照」，免得蛇身颜色渗进西臂的底色。
  4. 写出：只重编码有改动的 MCU（bg 4:2:0，MCU 16x16；cs 4:4:4，MCU 8x8）。有改动的 MCU 按行合并成若干矩形，
     逐块用原图同一套量化表编码，再用 jpegtran -drop 链式无损嵌回（复用 fix_bg_ledger_qinghua.write_jpeg_mcu，4:2:0 与 4:4:4 都行）。
     块外 DCT 系数原样照搬（djpeg -nosmooth 解码块外 0 变动）。按 libjpeg / PIL 默认的 fancy upsampling 解码时，
     4:2:0 块外紧贴的 1px 会因色度插值有极小变动。两种口径都打印。
     jpegtran / djpeg 走环境变量 NK1_JPEGTRAN / NK1_DJPEG，没设就找 PATH，都取不到就明确报错、不写文件。

幂等：每个待补区先量输入的判据，都低于门槛就判定已处理、跳过；一张图的区全跳过就打印原因、不写文件、rc=0，所以可以直接对仓库文件运行。
  · 罗经：放射纹强度——以罗经心为原点，把一圈环带（bg r20–100，cs r15–60）的亮度按方位角取平均，
    得到的角向剖面在 4 / 8 / 16（/ 32）次谐波上的最大振幅除以均值。罗经的放射尖角正好落在这些谐波上。
    原型实测：bg 0.097 → 0.010，cs 0.088 → 0.011；门槛 RADIAL_MAX=0.03。
    另量外环暗圈深度（半径剖面的中位数减最小值，除以中位数）：bg 0.39 → 0.04，cs 0.30 → 0.03；门槛 RING_MAX=0.15。
    两项都低于门槛才算已处理。
  · 海蛇：焦墨占比——多边形内比局部底色（盒式 r12 三遍）暗一半以上的像素占比。原型 0.145 → 0.005，同图蛇上方海面参照 0.015；
    门槛 INK_MAX=0.05。
  另有锚点核对：每张图两块待补区以外的 32x32 小区均色，对不上说明不是这张画（重导入换了源图、裁切变了等），rc=2、不写。
  渲染用固定随机种子（与原型相同：bg 罗经 1、海蛇 101，cs 1），同一输入两次运行，输出逐字节相同。
  输出与输入同一路径时，必须加 --in-place 才写。

会被谁覆盖：
  · cs_world_map_gold.jpg 由 tools/art/import_cutscene_bgs.py 从旧底 legacy:bg_world_map.jpg（main 9233852 的泥金靛海舆图）导出，
    本脚本登记在它的 POSTFIX 里（`--only cs --in-place`），导出后立即就地跑。清单 .import_manifest.json 的 out_sha1 记修后的图，
    所以 --force 重导也不会把罗经冲回来。开场过场用 ResourceLoader 读导入件（.ctex），只换 jpg 不生效，改完要跑一次
    headless `--import`。
  · bg_world_map.jpg 不经导入清单。标题屏走 GameManager.load_texture 按字节读，换 jpg 就生效。
    tools/art_src/bg_world_map_raw.png 是 09-25 的原稿（实为 1280x720 JPEG，gdignore），没有管线从它生成 bg_world_map.jpg，本脚本不动它。

用法：
  python3 tools/art/erase_world_map_compass.py --in-place                  # 就地处理两张图（已处理过的跳过）
  python3 tools/art/erase_world_map_compass.py --only cs --in-place        # 只处理开场首镜（import_cutscene_bgs 的 POSTFIX 用这一条）
  python3 tools/art/erase_world_map_compass.py --only bg --src A.jpg --out B.jpg   # 只出候选，不动仓库文件
  python3 tools/art/erase_world_map_compass.py --out-dir /tmp/cand         # 两张都出候选到目录（文件名同仓库）
每次运行都打印的自检数字：判据前后值（放射纹强度、暗圈深度、焦墨占比）、锚点、每区补洞像素、羽化像素、拼块数与不同供体数、
补区肌理（亮度减模糊后的标准差：洞内对照供体池和洞外一圈）、接缝色阶 ΔE76（洞内一圈比洞外一圈，洞外两圈之间的自然起伏作参照）、
改动像素与外接框、改动 MCU 数与嵌回块数、块外变动像素（DCT 口径 / 默认解码口径）、羽化外平均绝对差、保护区变动（编码前 / 编码后）。
两张图合计约 40 秒（M 系 CPU）。
"""
import argparse
import hashlib
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fix_bg_customs_jar import srgb_to_lab  # noqa: E402
from fix_bg_ledger_qinghua import changed_mcu_rects, decode_nosmooth, mcu_size, write_jpeg_mcu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ---- 判据门槛（原型实测值见文件头） ----
RADIAL_MAX = 0.03     # 放射纹强度 < 0.03 视为罗经已去（原图 0.088–0.097，处理后 ≈0.010）
RING_MAX = 0.15       # 外环暗圈深度 < 0.15 视为罗经已去（原图 0.30–0.39，处理后 0.03–0.04）
INK_MAX = 0.05        # 海蛇焦墨占比 < 0.05 视为已去（原图 0.145，处理后 0.005，海面参照 0.015）
ANCHOR_TOL = 4.0      # 锚点均色逐通道容差

# ---- 表：图与待补区 ----
# 坐标一律是原图像素（x, y），矩形 (x0, y0, x1, y1) 左闭右开。
IMAGES = [
    dict(key="bg", label="标题底图", path=os.path.join("assets", "bg_world_map.jpg"), size=(1672, 941),
         protect=[("右框线", (1628, 0, 1672, 941)), ("朱印", (1346, 822, 1427, 903)), ("下框线", (0, 903, 1672, 941))],
         anchors=[((96, 96, 128, 128), (132.8, 87.4, 56.6)), ((700, 280, 732, 312), (85.7, 89.5, 80.7))],
         regions=[
             dict(key="compass", label="罗经（32 向风玫瑰）", build="bg_compass",
                  judge=dict(kind="rose", cx=1474, cy=700, r=(20, 100), ks=(4, 8, 16, 32), ring=(60, 125)),
                  # 纸面供体（窗口不许压洞）：上方纸面 x<1400 是带旋涡纹的海缘，不要；下方避开浪花带右缘 x<1350
                  pools=[(1400, 292, 1627, 540), (1330, 540, 1627, 760), (1356, 760, 1627, 903)],
                  # 海蛇区：这一遍不补、不当底色参照（exclude），也不许合成（protect）
                  exclude=["serpent"], T=40, O=12, F=8, lf_r=10, lam=0.25, seed=1),
             dict(key="serpent", label="海蛇头颈", build="bg_serpent",
                  judge=dict(kind="ink", ref=(1175, 480, 1340, 682)),
                  # 海面 / 浪花供体：蛇上方海面、船下方海面、浪花带左段
                  pools=[(1175, 480, 1340, 682), (470, 650, 940, 790), (1000, 806, 1140, 895)],
                  exclude=[], T=40, O=12, F=8, lf_r=10, lam=0.25, seed=101),
         ]),
    dict(key="cs", label="开场首镜「舆图总纲」", path=os.path.join("assets", "cutscene", "cs_world_map_gold.jpg"),
         size=(1792, 1008), protect=[],
         anchors=[((96, 600, 128, 632), (97.7, 67.8, 24.5)), ((900, 300, 932, 332), (45.3, 57.1, 58.7))],
         regions=[
             dict(key="compass", label="罗经（八向细线风玫瑰）", build="cs_compass",
                  judge=dict(kind="rose", cx=1592, cy=314, r=(15, 60), ks=(4, 8, 16), ring=(30, 80)),
                  # 罗经四周的金纸（右侧浪纹边框从 x≈1725 起，池不到那里）
                  pools=[(1505, 110, 1700, 200), (1505, 200, 1700, 425), (1590, 425, 1700, 500)],
                  exclude=[], T=36, O=12, F=8, lf_r=10, lam=0.25, seed=1),
         ]),
]

BG_ARM_ENV = [(1450, 528, 1499, 604),    # 北臂
              (1450, 796, 1499, 878),    # 南臂
              (1316, 676, 1378, 724),    # 西臂
              (1572, 676, 1627, 724)]    # 东臂（止于框线前）
BG_SERPENT = [(1146, 712), (1162, 697), (1250, 695), (1302, 713), (1320, 738), (1321, 802),
              (1290, 808), (1200, 808), (1153, 804), (1153, 768), (1146, 764)]
CS_CENTER = (1592, 314)
CS_ARMS = [(1592, 194, 26), (1592, 414, 24), (1488, 316, 24), (1698, 316, 24),     # (臂尖 x, y, 线宽)
           (1533, 252, 20), (1654, 249, 20), (1649, 371, 20), (1531, 376, 20)]


# ---------- 基础运算（原型 inpaint.py 原样搬入） ----------
def _box1(a, r, axis):
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a, r, passes=3):
    """盒式模糊 r，三遍（近似高斯）。"""
    for _ in range(passes):
        a = _box1(_box1(a, r, 0), r, 1)
    return a


def norm_blur(a, known, r):
    """只在 known 像素里做归一化模糊（洞里的值不进来）。"""
    k = known.astype(np.float32)
    num = blur(a * k[..., None], r)
    den = blur(k, r)[..., None]
    return num / np.maximum(den, 1e-4)


def dilate(m, r):
    """圆盘膨胀（半径 r）。"""
    if r <= 0:
        return m.copy()
    out = m.copy()
    H, W = m.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy * dy + dx * dx > r * r:
                continue
            ys = slice(max(0, dy), H + min(0, dy))
            yd = slice(max(0, -dy), H + min(0, -dy))
            xs = slice(max(0, dx), W + min(0, dx))
            xd = slice(max(0, -dx), W + min(0, -dx))
            out[yd, xd] |= m[ys, xs]
    return out


def erode(m, r):
    return ~dilate(~m, r)


def dist_outside(hole, maxd):
    """洞外到洞的近似欧氏距离，截断到 maxd。"""
    d = np.full(hole.shape, np.inf, np.float32)
    d[hole] = 0
    prev = hole
    for k in range(1, maxd + 1):
        cur = dilate(hole, k)
        d[cur & ~prev] = k
        prev = cur
    return d


def _jacobi(x, hole):
    p = np.pad(x, ((1, 1), (1, 1), (0, 0)), mode="edge")
    avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) * 0.25
    x[hole] = avg[hole]
    return x


def membrane(a, hole, fine_iters=80):
    """把 hole 内的值用周边（Dirichlet 边界）调和插值填上，多重网格。"""
    H, W = hole.shape
    x = a.copy()
    if not hole.any():
        return x
    if min(H, W) <= 24:
        x[hole] = a[~hole].mean(0) if (~hole).any() else 0
        for _ in range(800):
            _jacobi(x, hole)
        return x
    H2, W2 = (H + 1) // 2, (W + 1) // 2
    ap = np.pad(a, ((0, 2 * H2 - H), (0, 2 * W2 - W), (0, 0)), mode="edge")
    kp = np.pad(~hole, ((0, 2 * H2 - H), (0, 2 * W2 - W)), mode="edge").astype(np.float32)
    s = (ap * kp[..., None]).reshape(H2, 2, W2, 2, -1).sum((1, 3))
    c = kp.reshape(H2, 2, W2, 2).sum((1, 3))
    ac = s / np.maximum(c, 1)[..., None]
    hc = c == 0
    xc = membrane(ac, hc, fine_iters)
    up = np.repeat(np.repeat(xc, 2, 0), 2, 1)[:H, :W]
    x[hole] = up[hole]
    for _ in range(fine_iters):
        _jacobi(x, hole)
    return x


def _box_sum_valid(m, T):
    """窗口 TxT 内 m 的和，结果 [y,x] 对应窗口左上角。"""
    c = np.pad(np.cumsum(np.cumsum(m.astype(np.float64), 0), 1), ((1, 0), (1, 0)))
    return c[T:, T:] - c[:-T, T:] - c[T:, :-T] + c[:-T, :-T]


def inpaint(img, hole, pool_rects, protect=None, T=40, O=12, F=8, lf_r=10,
            lam=0.25, seed=1, tol=0.12, exclude=None):
    """img HxWx3 float32；hole 要补的像素；pool_rects [(x0,y0,x1,y1)] 供体区；protect 必须原样保留的像素；
    exclude 不补、也不当已知底色参照的像素（另一处待补区）。返回 (结果, 调试 dict)。"""
    rng = np.random.default_rng(seed)
    H, W, _ = img.shape
    if protect is None:
        protect = np.zeros((H, W), bool)
    known = ~hole
    if exclude is not None:
        known = known & ~exclude
    LFk = norm_blur(img, known, lf_r)
    LFt = membrane(LFk, hole)
    HFimg = img - LFt  # 洞外有效

    # 供体池
    px0 = min(r[0] for r in pool_rects); py0 = min(r[1] for r in pool_rects)
    px1 = max(r[2] for r in pool_rects); py1 = max(r[3] for r in pool_rects)
    allow = np.zeros((H, W), bool)
    for (x0, y0, x1, y1) in pool_rects:
        allow[y0:y1, x0:x1] = True
    allow &= ~dilate(hole, 4)
    allow &= ~protect
    A = allow[py0:py1, px0:px1]
    Hp, Wp = A.shape
    HFp = (img - LFk)[py0:py1, px0:px1] * A[..., None]
    LFp = LFk[py0:py1, px0:px1] * A[..., None]
    valid_pos = _box_sum_valid(~A, T) == 0  # (Hp-T+1, Wp-T+1)
    rf, irf = np.fft.rfft2, np.fft.irfft2
    shp = (Hp, Wp)
    F_HF2 = rf((HFp ** 2).sum(-1))
    F_HF = [rf(HFp[..., c]) for c in range(3)]
    F_LF = [rf(LFp[..., c]) for c in range(3)]
    L1 = _box_sum_valid((LFp ** 2).sum(-1), T)

    fz = dilate(hole, F) & ~protect  # 需要合成高频的区
    ys, xs = np.nonzero(dilate(fz, 1))
    by0, by1 = max(0, ys.min() - O), min(H, ys.max() + O + 1)
    bx0, bx1 = max(0, xs.min() - O), min(W, xs.max() + O + 1)
    acc = np.zeros((H, W, 3), np.float32)
    den = np.zeros((H, W), np.float32)
    S = T - O
    ramp = np.ones(T, np.float32)
    ramp[:O] = np.linspace(0.08, 1, O)
    ramp[-O:] = np.linspace(1, 0.08, O)
    wwin = np.outer(ramp, ramp)
    used = []
    placed = []
    ny = list(range(by0, max(by0 + 1, by1 - T + 1), S))
    nx = list(range(bx0, max(bx0 + 1, bx1 - T + 1), S))
    if ny[-1] + T < by1:
        ny.append(min(by1, H) - T)
    if nx[-1] + T < bx1:
        nx.append(min(bx1, W) - T)
    for ty in ny:
        for tx in nx:
            sl = (slice(ty, ty + T), slice(tx, tx + T))
            if not fz[sl].any():
                continue
            filled = den[sl] > 0
            V = (known[sl] & ~protect[sl]) | filled
            ref = np.where(filled[..., None], acc[sl] / np.maximum(den[sl], 1e-6)[..., None], HFimg[sl])
            ref = np.where(V[..., None], ref, 0)
            Vp = np.zeros(shp, np.float32); Vp[:T, :T] = V
            tot = F_HF2 * np.conj(rf(Vp))
            for c in range(3):
                k = np.zeros(shp, np.float32); k[:T, :T] = ref[..., c]
                tot = tot - 2 * F_HF[c] * np.conj(rf(k))
                k2 = np.zeros(shp, np.float32); k2[:T, :T] = LFt[sl][..., c]
                tot = tot - 2 * lam * F_LF[c] * np.conj(rf(k2))
            cost = irf(tot, s=shp)[: Hp - T + 1, : Wp - T + 1]
            cost = cost + lam * L1 + (ref ** 2).sum() + lam * (LFt[sl] ** 2).sum()
            cost = np.where(valid_pos, cost, np.inf)
            # 避免同一块反复用：已用过的供体位置半块以内不再取（取不到别的才放行）
            c2 = cost.copy()
            for (uy, ux) in used:
                c2[max(0, uy - T // 2): uy + T // 2, max(0, ux - T // 2): ux + T // 2] = np.inf
            if np.isfinite(c2).any():
                cost = c2
            m = cost.min()
            cand = np.argwhere(cost <= m + tol * abs(m) + 1e-3)
            py, pxx = cand[rng.integers(len(cand))]
            used.append((py, pxx))
            placed.append((ty, tx, py + py0, pxx + px0))
            blk = HFp[py:py + T, pxx:pxx + T]
            w = wwin * fz[sl]
            acc[sl] += blk * w[..., None]
            den[sl] += w
    HFs = acc / np.maximum(den, 1e-6)[..., None]
    d = dist_outside(hole, F)
    alpha = np.where(hole, 1.0, np.clip(1 - d / (F + 1), 0, 1)).astype(np.float32)
    alpha[protect] = 0
    alpha[den <= 0] = np.where(hole[den <= 0], 1.0, 0.0)
    syn = LFt + HFs
    out = img * (1 - alpha[..., None]) + syn * alpha[..., None]
    return out, dict(alpha=alpha, placed=placed)


def poly_mask(shape, pts):
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon(pts, fill=255)
    return np.asarray(im) > 0


def disc_mask(shape, cx, cy, r):
    yy, xx = np.mgrid[: shape[0], : shape[1]]
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r


def ink_mask(img, envelope, r=6, thr=18):
    """包络内比局部底色（灰度闭运算，方窗 r）暗 thr 以上的墨线。"""
    L = img.mean(-1)

    def mx(a, r):
        out = a.copy()
        for d in range(1, r + 1):
            out[d:] = np.maximum(out[d:], a[:-d]); out[:-d] = np.maximum(out[:-d], a[d:])
        b = out.copy()
        for d in range(1, r + 1):
            out[:, d:] = np.maximum(out[:, d:], b[:, :-d]); out[:, :-d] = np.maximum(out[:, :-d], b[:, d:])
        return out

    def mn(a, r):
        return -mx(-a, r)
    close = mn(mx(L, r), r)
    return envelope & ((close - L) > thr)


# ---------- 待补区（洞） ----------
def build_hole(name, img):
    H, W, _ = img.shape
    sh = (H, W)
    if name == "bg_compass":
        env = np.zeros(sh, bool)
        for x0, y0, x1, y1 in BG_ARM_ENV:
            env[y0:y1, x0:x1] = True
        ink = ink_mask(img, env, r=6, thr=16)
        m = disc_mask(sh, 1474, 700, 113) | (dilate(ink, 4) & env)
        m[:, 1627:] = False
        return m
    if name == "bg_serpent":
        return poly_mask(sh, BG_SERPENT)
    if name == "cs_compass":
        cx, cy = CS_CENTER
        im = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(im)
        d.ellipse((cx - 66, cy - 66, cx + 66, cy + 66), fill=255)
        for tx, ty, w in CS_ARMS:
            d.line((cx, cy, tx, ty), fill=255, width=w)
        return dilate(np.asarray(im) > 0, 3)
    raise KeyError(name)


def rect_mask(sh, rects):
    m = np.zeros(sh, bool)
    for x0, y0, x1, y1 in rects:
        m[y0:y1, x0:x1] = True
    return m


# ---------- 判据 ----------
def rose_strength(L, cx, cy, r, ks, n=720):
    """放射纹强度：环带 r[0]–r[1] 的亮度按方位角取平均，角向剖面在 ks 次谐波上的最大振幅 / 均值。"""
    H, W = L.shape
    th = np.linspace(0, 2 * np.pi, n, endpoint=False)
    rs = np.arange(r[0], r[1], 1.0)
    xi = np.clip(np.round(cx + np.outer(rs, np.cos(th))).astype(int), 0, W - 1)
    yi = np.clip(np.round(cy + np.outer(rs, np.sin(th))).astype(int), 0, H - 1)
    prof = L[yi, xi].mean(0)
    amp = np.abs(np.fft.rfft(prof - prof.mean())) / n * 2
    return float(max(amp[k] for k in ks) / max(prof.mean(), 1e-3))


def ring_depth(L, cx, cy, r):
    """外环暗圈深度：半径剖面（每个半径一圈的均亮）中位数减最小值，除以中位数。"""
    H, W = L.shape
    th = np.linspace(0, 2 * np.pi, 1440, endpoint=False)
    prof = []
    for rr in np.arange(r[0], r[1], 1.0):
        X = np.round(cx + rr * np.cos(th)).astype(int)
        Y = np.round(cy + rr * np.sin(th)).astype(int)
        ok = (X >= 0) & (X < W) & (Y >= 0) & (Y < H)
        prof.append(L[Y[ok], X[ok]].mean())
    prof = np.array(prof)
    med = float(np.median(prof))
    return (med - float(prof.min())) / max(med, 1e-3)


def ink_share(L, mask):
    """焦墨占比：mask 内比局部底色（盒式 r12 三遍）暗一半以上的像素占比。"""
    return float((L < 0.5 * blur(L, 12))[mask].mean())


def judge(rg, img, masks):
    """返回 (仍需处理, 数值 dict, 说明)。"""
    L = img.mean(-1)
    j = rg["judge"]
    if j["kind"] == "rose":
        rs = rose_strength(L, j["cx"], j["cy"], j["r"], j["ks"])
        rd = ring_depth(L, j["cx"], j["cy"], j["ring"])
        need = rs >= RADIAL_MAX or rd >= RING_MAX
        return need, dict(rose=rs, ring=rd), "放射纹强度 %.4f（门槛 %.2f）、外环暗圈深度 %.3f（门槛 %.2f）" % (
            rs, RADIAL_MAX, rd, RING_MAX)
    m = masks[rg["key"]]
    s = ink_share(L, m)
    ref = ink_share(L, rect_mask(L.shape, [j["ref"]]))
    return s >= INK_MAX, dict(ink=s, ref=ref), "焦墨占比 %.4f（门槛 %.2f；海面参照 %.4f）" % (s, INK_MAX, ref)


def anchors_ok(img, spec):
    rows = []
    ok = True
    for (x0, y0, x1, y1), want in spec["anchors"]:
        got = img[y0:y1, x0:x1].reshape(-1, 3).mean(0)
        dmax = float(np.abs(got - np.array(want)).max())
        ok &= dmax <= ANCHOR_TOL
        rows.append("(%d,%d) 均色 (%.1f,%.1f,%.1f)，差 %.2f" % (x0, y0, *got, dmax))
    return ok, "；".join(rows)


# ---------- 自检 ----------
def hf_std(Y, m):
    return float((Y - blur(Y, 2))[m].std()) if m.any() else float("nan")


def seam_step(after, hole, protect, other, F):
    """接缝色阶：洞内 0–6px 一圈与羽化外 2–8px 一圈，各自归一化模糊（r8）后在洞边上比 ΔE76；
    参照：羽化外 2–8px 与 8–14px 两圈之间同样比（洞外的自然起伏）。返回 (中位, p95, 参照中位, 参照 p95)。"""
    free = ~protect & ~other
    bin_ = hole & ~erode(hole, 6)
    bo1 = dilate(hole, F + 8) & ~dilate(hole, F + 2) & free
    bo2 = dilate(hole, F + 14) & ~dilate(hole, F + 8) & free
    edge = hole & ~erode(hole, 1)
    mid = dilate(hole, F + 8) & ~dilate(hole, F + 7) & free

    def nb(m):
        v = norm_blur(after, m, 8)
        den = blur(m.astype(np.float32), 8)
        return v, den

    def step(a, b, at):
        (va, da), (vb, db) = a, b
        ok = at & (da > 0.05) & (db > 0.05)
        if not ok.any():
            return float("nan"), float("nan")
        la = srgb_to_lab(np.clip(va[ok], 0, 255))
        lb = srgb_to_lab(np.clip(vb[ok], 0, 255))
        dE = np.sqrt(((la - lb) ** 2).sum(-1))
        return float(np.median(dE)), float(np.percentile(dE, 95))

    a, b, c = nb(bin_), nb(bo1), nb(bo2)
    s = step(a, b, edge)
    r = step(b, c, mid)
    return s[0], s[1], r[0], r[1]


def process(spec, src_path, out_path, force=False):
    t0 = time.time()
    raw = open(src_path, "rb").read()
    print("[%s %s] 输入 %s（%d 字节，sha1 %s）" % (spec["key"], spec["label"], os.path.relpath(src_path, ROOT)
                                            if src_path.startswith(ROOT) else src_path, len(raw),
                                            hashlib.sha1(raw).hexdigest()[:12]))
    im = Image.open(src_path)
    if im.format != "JPEG" or im.size != spec["size"]:
        print("  输入不是 %dx%d JPEG（%s %s），不是这张图，跳过、未写。" % (*spec["size"], im.format, im.size))
        return 2
    src = np.asarray(im.convert("RGB"))
    img = src.astype(np.float32)
    ok, why = anchors_ok(img, spec)
    print("  锚点：%s → %s" % (why, "对上" if ok else "对不上"))
    if not ok and not force:
        print("  锚点对不上：不是这张画（换了源图 / 裁切？），未写。")
        return 2
    H, W, _ = img.shape
    sh = (H, W)
    protect = rect_mask(sh, [r for _, r in spec["protect"]])
    masks = {rg["key"]: build_hole(rg["build"], img) for rg in spec["regions"]}
    todo = []
    jb = {}
    for rg in spec["regions"]:
        need, vals, why = judge(rg, img, masks)
        jb[rg["key"]] = vals
        tag = "处理" if (need or force) else "跳过（判定已处理）"
        print("  %-8s %s：%s → %s" % (rg["key"], rg["label"], why, tag))
        if need or force:
            todo.append(rg)
    if not todo:
        print("  没有需要处理的区：判定已处理过，跳过，未写文件。")
        return 0

    cur = img
    alpha_all = np.zeros(sh, np.float32)
    info = {}
    for rg in todo:
        others = np.zeros(sh, bool)
        for k in rg["exclude"]:
            others |= masks[k]
        hole = masks[rg["key"]] & ~protect
        cur, dbg = inpaint(cur, hole, rg["pools"], protect=protect | others, T=rg["T"], O=rg["O"], F=rg["F"],
                           lf_r=rg["lf_r"], lam=rg["lam"], seed=rg["seed"], exclude=others if rg["exclude"] else None)
        alpha_all = np.maximum(alpha_all, dbg["alpha"])
        donors = {(sy, sx) for _, _, sy, sx in dbg["placed"]}
        info[rg["key"]] = dict(hole=hole, others=others, alpha=dbg["alpha"], tiles=len(dbg["placed"]), donors=len(donors))
    new = np.clip(cur + 0.5, 0, 255).astype(np.uint8)
    # 编码前（PNG 口径）：保护区与羽化外必须逐像素不变
    d0 = np.abs(new.astype(np.int16) - src.astype(np.int16)).max(-1)
    pre_protect = int((d0[protect] > 0).sum())
    pre_outside = int((d0[alpha_all == 0] > 0).sum())
    if pre_protect or pre_outside:
        print("  编码前保护区变动 %d px、羽化外变动 %d px：应为 0，中止、未写。" % (pre_protect, pre_outside))
        return 1
    mask = d0 > 0
    mw, mh = mcu_size(im)
    rects, blk = changed_mcu_rects(mask, mw, mh)
    blkmask = np.repeat(np.repeat(blk, mh, 0), mw, 1)[:H, :W]
    ns_before = decode_nosmooth(src_path)          # 就地写之前先解好原图（-nosmooth 口径）
    how = write_jpeg_mcu(src_path, im, new, rects, out_path)
    after = np.asarray(Image.open(out_path).convert("RGB"))
    ns_after = decode_nosmooth(out_path)
    out_raw = open(out_path, "rb").read()

    # ---- 自检 ----
    af = after.astype(np.float32)
    diff = np.abs(after.astype(np.int16) - src.astype(np.int16)).max(-1)
    ch = diff > 0
    ys, xs = np.nonzero(ch)
    bbox = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())) if ch.any() else None
    fringe = dilate(blkmask, 1) & ~blkmask
    ns_out = int((np.abs(ns_before.astype(np.int16) - ns_after.astype(np.int16)).max(-1)[~blkmask] > 0).sum())
    out_alpha0 = alpha_all == 0
    mad0 = float(np.abs(after.astype(np.int16) - src.astype(np.int16))[out_alpha0].mean())
    mad0_blk = float(np.abs(after.astype(np.int16) - src.astype(np.int16))[out_alpha0 & blkmask].mean()) \
        if (out_alpha0 & blkmask).any() else 0.0
    print("  写出 %s（%d 字节，sha1 %s，%s，改动 MCU %d 个，%.1f 秒）" % (
        os.path.relpath(out_path, ROOT) if os.path.abspath(out_path).startswith(ROOT) else out_path, len(out_raw),
        hashlib.sha1(out_raw).hexdigest()[:12], how, int(blk.sum()), time.time() - t0))
    print("  解码后有变动的像素 %d，外接框 x %d–%d、y %d–%d；羽化权重 >0 的像素 %d" % (
        int(ch.sum()), bbox[0], bbox[2], bbox[1], bbox[3], int((alpha_all > 0).sum())))
    print("  改动块外变动像素：DCT 口径（djpeg -nosmooth）%d；默认解码 %d（块外紧贴 1px：%d，1px 以外 %d）" % (
        ns_out, int(ch[~blkmask].sum()), int(ch[fringe].sum()), int(ch[~blkmask & ~fringe].sum())))
    print("  羽化外（权重 0）平均绝对差 %.4f、变动像素 %d；其中改动块内的（重编码误差）平均绝对差 %.3f" % (
        mad0, int(ch[out_alpha0].sum()), mad0_blk))
    for name, (x0, y0, x1, y1) in spec["protect"]:
        pm = rect_mask(sh, [(x0, y0, x1, y1)])
        print("  保护区「%s」(%d,%d)-(%d,%d)：编码前变动 0 px；编码后变动 %d px（最大差 %d，落在改动块内的像素 %d）" % (
            name, x0, y0, x1, y1, int(ch[pm].sum()), int(diff[pm].max()), int((pm & blkmask).sum())))
    Yb, Ya = src.astype(np.float32).mean(-1), af.mean(-1)
    for rg in todo:
        k = rg["key"]
        inf = info[k]
        hole = inf["hole"]
        _, va, why = judge(rg, af, masks)
        vb = jb[k]
        if rg["judge"]["kind"] == "rose":
            jtxt = "放射纹强度 %.4f → %.4f，外环暗圈深度 %.3f → %.3f" % (vb["rose"], va["rose"], vb["ring"], va["ring"])
        else:
            jtxt = "焦墨占比 %.4f → %.4f（海面参照 %.4f → %.4f）" % (vb["ink"], va["ink"], vb["ref"], va["ref"])
        inner = erode(hole, 3)
        ring = dilate(hole, rg["F"] + 20) & ~dilate(hole, rg["F"] + 2) & ~protect & ~inf["others"]
        pool = rect_mask(sh, rg["pools"]) & ~dilate(hole, 4) & ~protect & ~inf["others"]
        s = seam_step(af, hole, protect, inf["others"], rg["F"])
        print("  [%s %s] %s" % (k, rg["label"], jtxt))
        print("    补洞 %d px，羽化合成 %d px；拼块 %d 块、不同供体 %d 处" % (
            int(hole.sum()), int(((inf["alpha"] > 0) & ~hole).sum()), inf["tiles"], inf["donors"]))
        print("    补区肌理 std(Y−模糊)：洞内（内缩 3px）%.2f；供体池 %.2f、洞外一圈 %.2f（原图同圈 %.2f）"
              "→ 洞内/供体池 %.2f" % (hf_std(Ya, inner), hf_std(Yb, pool), hf_std(Ya, ring), hf_std(Yb, ring),
                                   hf_std(Ya, inner) / max(hf_std(Yb, pool), 1e-6)))
        print("    接缝色阶 ΔE76 中位 %.2f、p95 %.2f（参照：洞外两圈之间自然起伏 中位 %.2f、p95 %.2f）" % s)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", choices=[s["key"] for s in IMAGES], help="只处理一张（bg 标题底图 / cs 开场首镜）")
    ap.add_argument("--src", help="输入（需配 --only；缺省为仓库文件）")
    ap.add_argument("--out", help="输出（需配 --only；缺省同输入）")
    ap.add_argument("--out-dir", help="输出到这个目录（文件名同仓库），不动仓库文件")
    ap.add_argument("--in-place", action="store_true", help="允许输出覆盖输入文件")
    ap.add_argument("--force", action="store_true", help="跳过幂等与锚点检查（调试用）")
    args = ap.parse_args(argv)
    if (args.src or args.out) and not args.only:
        ap.error("--src / --out 要配 --only")
    rc = 0
    for spec in IMAGES:
        if args.only and spec["key"] != args.only:
            continue
        src = os.path.abspath(args.src) if args.src else os.path.join(ROOT, spec["path"])
        if args.out_dir:
            out = os.path.join(os.path.abspath(args.out_dir), os.path.basename(spec["path"]))
        else:
            out = os.path.abspath(args.out) if args.out else src
        if os.path.abspath(src) == os.path.abspath(out) and not args.in_place:
            print("[%s] 输出与输入同一路径，需加 --in-place 才写；未写任何文件。" % spec["key"])
            rc = max(rc, 2)
            continue
        rc = max(rc, process(spec, src, out, force=args.force))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
