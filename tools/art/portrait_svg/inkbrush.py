# -*- coding: utf-8 -*-
"""「墨影」兜底卡的墨法底层：噪声、栅格化、积墨合成、泼墨块面、毛笔笔触（逐根笔毫，自带枯笔飞白）。

坐标一律写 512×640 的 1× 画布坐标，内部按 S 倍超采样（默认 2×，即 1024×1280；环境变量
NK1_INK_S=1 可出快速小样）栅格化，成品在 build_portraits.py 里缩回 512×640。
每个部件只在自己的包围盒里计算（crop），整卡只在合成时碰全幅。

墨的合成用「透过率」T（0=焦墨满覆盖，1=白绢）：每叠一层浓度 d，T *= (1-d)，即积墨——
同一处反复上墨会越叠越深，但永远到不了纯黑，淡墨处透出绢色与绢纹。留白（reserve）把 T 拉回 1。
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 512, 640
S = int(os.environ.get("NK1_INK_S", "2"))
WS, HS = W * S, H * S


# ───────────────────────── 数值小工具 ─────────────────────────
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


def blur(a, sigma):
    """三次盒滤波近似高斯（sigma 以当前数组像素计）。"""
    if sigma <= 0.3:
        return a
    r = max(1, int(round(math.sqrt(12 * sigma * sigma / 3 + 1) / 2)))
    out = a
    for _ in range(3):
        out = _box1d(_box1d(out, r, 0), r, 1)
    return out


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def value_noise(shape, scale, seed, octaves=5, persist=0.5, aspect=1.0):
    """多倍频值噪声，0..1（scale = 最粗一层的格距，像素；aspect>1 横向拉长）。"""
    rng = np.random.default_rng(seed)
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2.0, scale / (2 ** o))
        sx = s * aspect
        gh, gw = int(h / s) + 3, int(w / sx) + 3
        g = rng.random((gh, gw)).astype(np.float32)
        im = Image.fromarray(g, mode="F").resize((int(gw * sx), int(gh * s)), Image.BICUBIC)
        out += np.asarray(im, np.float32)[:h, :w] * amp
        tot += amp
        amp *= persist
    return np.clip(out / tot, 0, 1)


def streak_noise(shape, angle, length, width, seed, octaves=3):
    """各向异性噪声：沿 angle（度，0=竖直，90=水平）拉长的丝缕，用来做笔刷走向与枯笔丝。"""
    h, w = shape
    d = int(math.hypot(h, w)) + 8
    rng = np.random.default_rng(seed)
    acc = np.zeros((d, d), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        ln = max(2.0, length / (1.7 ** o))
        wd = max(1.0, width / (1.7 ** o))
        gh, gw = int(d / ln) + 3, int(d / wd) + 3
        g = rng.random((gh, gw)).astype(np.float32)
        im = Image.fromarray(g, mode="F").resize((int(gw * wd), int(gh * ln)), Image.BICUBIC)
        acc += np.asarray(im, np.float32)[:d, :d] * amp
        tot += amp
        amp *= 0.55
    acc /= tot
    im = Image.fromarray(acc, mode="F").rotate(angle, resample=Image.BICUBIC)
    y0, x0 = (d - h) // 2, (d - w) // 2
    out = np.asarray(im, np.float32)[y0:y0 + h, x0:x0 + w]
    lo, hi = np.percentile(out, 1), np.percentile(out, 99)
    return np.clip((out - lo) / max(hi - lo, 1e-4), 0, 1)


def dilate(m, r):
    im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.MaxFilter(2 * r + 1)), np.float32) / 255.0


# ───────────────────────── 包围盒 ─────────────────────────
def box_of(pts, pad):
    """1× 点列 + 1× 边距 → S× 像素包围盒 (x0, y0, x1, y1)，裁在画布内；全在画外返回 None。"""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0 = int(math.floor((min(xs) - pad) * S))
    y0 = int(math.floor((min(ys) - pad) * S))
    x1 = int(math.ceil((max(xs) + pad) * S))
    y1 = int(math.ceil((max(ys) + pad) * S))
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(WS, x1), min(HS, y1)
    if x1 - x0 < 2 or y1 - y0 < 2:
        return None
    return (x0, y0, x1, y1)


def sl(a, bx):
    x0, y0, x1, y1 = bx
    return a[y0:y1, x0:x1]


# ───────────────────────── 曲线 ─────────────────────────
def catmull(pts, closed=False, per=None):
    """Catmull-Rom 插值成稠密点列（1× 坐标）。相邻重复点即成尖角。"""
    pts = [tuple(map(float, p)) for p in pts]
    n = len(pts)
    if n < 3:
        if n == 2:
            (x0, y0), (x1, y1) = pts
            k = max(2, int(math.hypot(x1 - x0, y1 - y0) / 2))
            return [(x0 + (x1 - x0) * i / k, y0 + (y1 - y0) * i / k) for i in range(k + 1)]
        return pts
    out = []
    last = n if closed else n - 1
    for i in range(last):
        p0 = pts[(i - 1) % n] if (closed or i > 0) else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (closed or i + 2 < n) else p2
        seg = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        k = max(2, min(40, int(seg / 3) + 2)) if per is None else max(2, int(per * max(1.0, seg / 30)))
        for j in range(k):
            t = j / k
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(pts[-1])
    return out


def resample(path, step):
    """按弧长等距重采样。"""
    p = np.asarray(path, np.float64)
    if len(p) < 2:
        return p
    seg = np.hypot(*(p[1:] - p[:-1]).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    if total < 1e-6:
        return p[:1]
    n = max(2, int(total / step) + 1)
    s = np.linspace(0, total, n)
    return np.stack([np.interp(s, cum, p[:, 0]), np.interp(s, cum, p[:, 1])], 1)


# ───────────────────────── 栅格化 ─────────────────────────
def fill(pts, bx, sharp=False):
    """闭合形 → 包围盒 bx 内的覆盖率 0..1。sharp=True 时点列按折线处理（不插值）。"""
    dense = pts if sharp else catmull(pts, closed=True)
    x0, y0, x1, y1 = bx
    im = Image.new("L", ((x1 - x0) * 2, (y1 - y0) * 2), 0)
    ImageDraw.Draw(im).polygon([((x * S - x0) * 2, (y * S - y0) * 2) for x, y in dense], fill=255)
    im = im.resize((x1 - x0, y1 - y0), Image.BOX)
    return np.asarray(im, np.float32) / 255.0


# ───────────────────────── 纹理 ─────────────────────────
class Tex:
    """一张卡共享的全幅纹理（按种子生成一次）；view(bx) 取包围盒切片。"""

    def __init__(self, seed):
        self.seed = seed
        sh = (HS, WS)
        self.low = value_noise(sh, 180 * S, seed + 1, octaves=4)       # 墨韵：大片深浅
        self.mid = value_noise(sh, 40 * S, seed + 2, octaves=4)
        self.fine = value_noise(sh, 5 * S, seed + 3, octaves=3)        # 边缘毛涩
        self.fiber = streak_noise(sh, 70, 18 * S, 1.2 * S, seed + 4)    # 绢丝方向的洇
        self._st = {}

    def streak(self, angle):
        key = int(round(angle / 10.0)) * 10
        if key not in self._st:
            self._st[key] = streak_noise((HS, WS), key, 90 * S, 4.0 * S, self.seed + 100 + key)
        return self._st[key]

    def view(self, bx):
        return TexView(self, bx)


class TexView:
    def __init__(self, tex, bx):
        self.t, self.bx = tex, bx
        self.low, self.mid, self.fine, self.fiber = (sl(tex.low, bx), sl(tex.mid, bx), sl(tex.fine, bx),
                                                     sl(tex.fiber, bx))

    def streak(self, angle):
        return sl(self.t.streak(angle), self.bx)


class Canvas:
    """S× 画布上的墨层：T 透过率。"""

    def __init__(self):
        self.T = np.ones((HS, WS), np.float32)

    def ink(self, d, bx=None):
        if bx is None:
            self.T *= 1.0 - np.clip(d, 0, 0.995)
        else:
            sl(self.T, bx)[...] *= 1.0 - np.clip(d, 0, 0.995)

    def reserve(self, r, bx=None):
        """留白：把 T 往 1 拉（r=1 完全露绢）。"""
        t = self.T if bx is None else sl(self.T, bx)
        r = np.clip(r, 0, 1)
        t[...] = t * (1 - r) + r

    @property
    def D(self):
        return 1.0 - self.T


# ───────────────────────── 毛笔 ─────────────────────────
def profile(kind, n, press=1.0):
    """笔画宽度曲线（0..1），n 个采样。
    nail  钉头鼠尾：起笔一顿、行笔渐收、出锋尖细（衣纹、须）
    even  起收略顿、中段匀（轮廓长线）
    swell 两头尖中间饱（帽翅、飘带）
    broad 大笔铺面：起笔饱满、收笔略收
    """
    t = np.linspace(0, 1, n)
    if kind == "nail":
        w = 0.55 + 0.45 * np.exp(-((t - 0.04) / 0.07) ** 2)
        w = w * (1 - t) ** 0.8 + 0.06
    elif kind == "even":
        w = 0.78 + 0.22 * np.exp(-((t - 0.03) / 0.06) ** 2) + 0.12 * np.exp(-((t - 0.97) / 0.05) ** 2)
        w *= np.clip(np.minimum(t, 1 - t) / 0.03, 0.35, 1)
    elif kind == "swell":
        w = np.sin(np.pi * np.clip(t, 0, 1)) ** 0.7 + 0.04
    elif kind == "broad":
        w = 0.86 + 0.14 * np.exp(-((t - 0.06) / 0.09) ** 2) - 0.16 * t ** 2
    elif kind == "taper":            # 起笔饱满、一路收尖
        w = (1 - t) ** 0.6 * 0.95 + 0.05
    else:
        w = np.ones(n)
    return np.clip(w, 0, 1.3) * press


def brush(path, width, ink=0.9, dry=0.35, seed=0, kind="nail", closed=False, wet=1.0, bristle_px=1.3,
          jitter=0.12, split=0.0, grain=1.0, fade=0.0):
    """毛笔一笔：path 为 1× 坐标控制点（Catmull-Rom 插值），width 为最宽处（1× px）。
    逐根笔毫画折线；每根毫有自己的含墨量，沿笔程递减，含墨不足处断开 → 枯笔飞白。
    dry：0 湿笔实画，1 很快枯。split：笔锋开叉。grain：飞白丝的长短（>1 丝更长更少）；fade：墨色沿笔程变淡。
    返回 (浓度图, 包围盒)；全在画外时返回 (None, None)。"""
    rng = np.random.default_rng(seed)
    dense = catmull(path, closed=closed)
    bx = box_of(dense, width * (1 + split) + 4)
    if bx is None:
        return None, None
    x0, y0, x1, y1 = bx
    P = resample(dense, 0.7) * S - np.array([x0, y0])
    n = len(P)
    if n < 2:
        return None, None
    tang = np.gradient(P, axis=0)
    tl = np.hypot(tang[:, 0], tang[:, 1])[:, None]
    tang = tang / np.maximum(tl, 1e-6)
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    wprof = profile(kind, n) * width * S if isinstance(kind, str) else np.asarray(kind) * width * S
    nb = int(np.clip(width * S / bristle_px, 4, 72))
    im = Image.new("L", (x1 - x0, y1 - y0), 0)
    dr = ImageDraw.Draw(im)
    t = np.linspace(0, 1, n)
    length = n * 0.7 * S
    head = min(0.25, (width * S * 0.55) / max(length, 1))   # 起笔圆头：侧锋毫晚到
    m = max(3, int(n / (22 * grain)))
    xs = np.linspace(0, m - 1, n)
    bristles = []
    for i in range(nb):
        o = (i + 0.5) / nb - 0.5
        o += rng.normal(0, 0.45 / nb)
        edge = min(1.0, abs(o) * 2)  # 0 中锋 → 1 侧锋
        cap = rng.uniform(0.8, 1.2) * wet
        k = rng.uniform(0.7, 1.3)
        nz = np.interp(xs, np.arange(m), rng.normal(0, 1, m))
        m3 = max(3, int(m * 3 / max(grain, 0.3)))
        nz2 = np.interp(np.linspace(0, m3 - 1, n), np.arange(m3), rng.normal(0, 1, m3))
        inkamt = (cap - dry * k * (0.25 + 1.5 * t ** 1.1) - dry * edge ** 1.6 * 1.1
                  + nz * 0.10 + nz2 * (0.06 + 0.16 * dry))
        on = inkamt > 0.22
        t0 = head * (1 - math.sqrt(max(0.0, 1 - edge * edge))) * rng.uniform(0.7, 1.3)
        t1 = 1 - 0.04 * edge * rng.uniform(0, 1.5)
        on &= (t >= t0) & (t <= t1)
        spread = 1.0 + split * edge * t ** 1.5
        wob = np.interp(xs, np.arange(m), rng.normal(0, 1, m)) * (jitter * (0.3 + edge)) / nb
        off = (o * spread + wob)[:, None] * wprof[:, None] * nrm
        val = float(np.clip(180 + 75 * (cap / 1.2) * (1 - 0.25 * edge), 150, 255))
        bristles.append((val, on, P + off))
    bw = np.maximum(1.0, wprof / nb * 2.3)
    fadev = 1 - fade * t
    # 浅的先画、深的后画 → 重叠处取较深者，内部留下细微的毫痕
    for val, on, Q in sorted(bristles, key=lambda b: b[0]):
        j = 0
        while j < n - 1:
            if not on[j]:
                j += 1
                continue
            j2 = j
            while j2 < n - 1 and on[j2 + 1] and j2 - j < 12:
                j2 += 1
            if j2 > j:
                seg = [tuple(q) for q in Q[j:j2 + 1]]
                dr.line(seg, fill=int(val * fadev[j]), width=int(round(bw[j:j2 + 1].mean())), joint="curve")
            j = j2 if j2 > j else j + 1
    a = np.asarray(im, np.float32) / 255.0
    a = blur(a, 0.3 * S)
    return np.clip(a, 0, 1) * ink, bx


# ───────────────────────── 侧锋大笔 ─────────────────────────
def _bilerp(G, fu, fs):
    """小随机网格 G[nu, ns] 在小数坐标上做平滑双线性采样。"""
    nu, ns = G.shape
    fu = np.clip(fu, 0, nu - 1.001)
    fs = np.clip(fs, 0, ns - 1.001)
    i0 = fu.astype(np.int32)
    j0 = fs.astype(np.int32)
    a = fu - i0
    b = fs - j0
    a = a * a * (3 - 2 * a)
    b = b * b * (3 - 2 * b)
    g00, g10, g01, g11 = G[i0, j0], G[i0 + 1, j0], G[i0, j0 + 1], G[i0 + 1, j0 + 1]
    return ((g00 * (1 - a) + g10 * a) * (1 - b) + (g01 * (1 - a) + g11 * a) * b).astype(np.float32)


def sweep_profile(kind, n):
    t = np.linspace(0, 1, n)
    if kind == "sweep":          # 起笔一按（略圆）、行笔饱满、收笔渐提
        w = np.clip(0.62 + 0.38 * smoothstep(0.0, 0.10, t), 0, 1) * (1 - 0.45 * smoothstep(0.55, 1.0, t))
    elif kind == "press":        # 按下去再提起：中段最宽
        w = 0.35 + 0.65 * np.sin(np.pi * np.clip(t, 0, 1)) ** 0.8
    elif kind == "flat":         # 平拖
        w = np.clip(0.8 + 0.2 * smoothstep(0.0, 0.08, t), 0, 1) * (1 - 0.15 * t)
    elif kind == "drop":         # 点厾：头大尾尖
        w = (1 - t) ** 0.7 * 0.9 + 0.1
    else:
        w = np.ones(n)
    return w


def sweep(path, width, tv, ink=0.8, side=0.6, pale=0.3, dry=0.35, wet=0.4, seed=0, kind="sweep",
          streak=1.0, rough=1.0, cap=1.0):
    """侧锋大笔一笔：笔肚含淡墨、笔尖蘸浓墨，一侧浓一侧淡（side：+1 浓边在路径左法线侧，-1 在右侧，0 中锋）。
    笔毫纹理沿笔程拉长；含墨沿笔程递减，干处断成飞白（dry 越大越早枯），边上的毫比中间的先枯。
    wet：湿笔边缘积墨与外洇。tv 为全卡 Tex 的切片（在返回的包围盒上）——所以调用方先要包围盒：
    这里接受 tv 为 Tex（整幅），内部自己切。返回 (浓度图, 包围盒)。"""
    rng = np.random.default_rng(seed)
    dense = catmull(path)
    bx = box_of(dense, width * 0.75 + 8)
    if bx is None:
        return None, None
    x0, y0, x1, y1 = bx
    P = resample(dense, 1.2 / S) * S - np.array([x0, y0])
    n = len(P)
    if n < 3:
        return None, None
    tang = np.gradient(P, axis=0)
    tang /= np.maximum(np.hypot(tang[:, 0], tang[:, 1])[:, None], 1e-6)
    N = np.stack([-tang[:, 1], tang[:, 0]], 1)
    prof = sweep_profile(kind, n) if isinstance(kind, str) else np.interp(np.linspace(0, 1, n),
                                                                           np.linspace(0, 1, len(kind)), kind)
    hw = np.maximum(prof * width * S * 0.5, 0.8)
    seg = np.hypot(*(P[1:] - P[:-1]).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = max(cum[-1], 1.0)
    w_, h_ = x1 - x0, y1 - y0
    im = Image.new("I", (w_, h_), 0)
    dr = ImageDraw.Draw(im)
    r0 = hw[0] * 1.25 + 3
    dr.ellipse([P[0][0] - r0, P[0][1] - r0, P[0][0] + r0, P[0][1] + r0], fill=1)
    ext = 1.25
    for i in range(n - 1):
        a, b = P[i], P[i + 1]
        wa, wb = hw[i] * ext + 3, hw[i + 1] * ext + 3
        dr.polygon([tuple(a + N[i] * wa), tuple(b + N[i + 1] * wb), tuple(b - N[i + 1] * wb), tuple(a - N[i] * wa)],
                   fill=i + 1)
    r1 = hw[-1] * 1.25 + 3
    dr.ellipse([P[-1][0] - r1, P[-1][1] - r1, P[-1][0] + r1, P[-1][1] + r1], fill=n - 1)
    idx = np.asarray(im, np.int32)
    valid = idx > 0
    k = np.clip(idx - 1, 0, n - 2)
    yy, xx = np.mgrid[0:h_, 0:w_].astype(np.float32)
    dx = xx + 0.5 - P[k, 0]
    dy = yy + 0.5 - P[k, 1]
    along = dx * tang[k, 0] + dy * tang[k, 1]
    across = dx * N[k, 0] + dy * N[k, 1]
    s_px = cum[k] + along
    wk = hw[k] + (hw[np.minimum(k + 1, n - 1)] - hw[k]) * np.clip(along / np.maximum(seg[k], 1e-3), 0, 1)
    u = across / wk
    # 两端圆头：形状按到端点的距离算，纹理仍按横向坐标（否则毫痕成同心圈）
    pre = s_px < 0
    post = s_px > total
    ush = np.where(pre, np.hypot(along, across) / hw[0], np.abs(u))
    ue = np.hypot(xx + 0.5 - P[-1, 0], yy + 0.5 - P[-1, 1]) / hw[-1]
    ush = np.where(post, ue, ush)
    s = np.clip(s_px / total, 0, 1)
    sp = s_px.clip(0, total)
    tvv = tv.view(bx) if isinstance(tv, Tex) else tv
    # 笔毫：细毫（毫痕）+ 成簇的粗毫（含墨多少），都沿笔程拉长
    nb = int(np.clip(width / 1.7, 12, 150))
    nc = max(3, nb // 6)
    Lf, Lc = 34 * S * streak, 80 * S * streak
    Gf = rng.random((nb + 3, int(total / Lf) + 3)).astype(np.float32)
    Gc = rng.random((nc + 3, int(total / Lc) + 3)).astype(np.float32)
    fu = (np.clip(u, -1.3, 1.3) + 1.3) / 2.6
    fine = _bilerp(Gf, fu * (nb + 1), sp / Lf)
    clump = _bilerp(Gc, fu * (nc + 1), sp / Lc)
    au = np.clip(np.abs(u), 0, 1.3)
    load = 1.0 - dry * (0.08 + 1.45 * s ** 1.5)
    remain = (load + (clump - 0.5) * (0.45 + 0.9 * dry) + (fine - 0.5) * (0.2 + 0.6 * dry)
              - dry * 0.85 * au ** 2.5)
    on = smoothstep(0.0, 0.07, remain)
    # 边：以像素计的毛涩硬边（±3px 抖动），不是整条软边
    dist = (1 - ush) * np.where(pre, hw[0], np.where(post, hw[-1], wk))
    jag = (tvv.fine - 0.5) * 5.0 * S * rough + (tvv.mid - 0.5) * 4.0 * S * rough + (fine - 0.5) * 2.0 * S
    inside = smoothstep(-0.6 * S, 0.9 * S, dist + jag) * valid
    sg = (1 + side * np.clip(u, -1, 1)) / 2
    tone = pale + (1 - pale) * sg ** 1.3
    d = ink * tone * on * inside * (0.70 + 0.42 * fine) * (0.88 + 0.24 * clump) * (0.9 + 0.2 * tvv.mid)
    if wet > 0:
        ring = np.clip(inside - blur(inside, 1.6 * S), 0, 1) * on
        d = d + ring * wet * 0.55 * ink
        halo = np.clip(blur(inside * on, 2.4 * S) - inside, 0, 1) * wet * 0.22 * ink
        d = d + halo * (0.5 + 0.9 * tvv.fiber)
    d = blur(d.astype(np.float32), 0.3 * S)
    return np.clip(d * cap, 0, 0.995), bx


# ───────────────────────── 泼墨块面 ─────────────────────────
def wash(m, tone, tv, angle=0.0, edge=0.3, bleed=0.5, var=0.4, streak=0.06, dry_edge=0.0, dry_side=None,
         dry_depth=14.0, soft=1.0, bloom=0.12):
    """泼墨块面（包围盒内）：m 为覆盖率，tone 为主浓度（标量或同形数组），tv 为 TexView。
    edge：边缘积墨；bleed：外缘洇开的毛涩与淡晕；var：内部浓淡（低频）；streak：笔刷丝缕（沿 angle）；
    bloom：水渍花；dry_edge：边缘枯笔飞白强度，dry_depth 为飞白吃进去的深度（1× px）；
    dry_side：只在某侧起飞白（(nx,ny) 朝外方向），None 为全边。"""
    sm = blur(m, 1.0 * S * soft)
    n = (tv.fine - 0.5) * 0.5 + (tv.mid - 0.5) * 0.35 + (tv.fiber - 0.5) * 0.15 * bleed
    a = np.clip((sm - 0.5 + n * 0.45) * 3.0 + 0.5, 0, 1)
    a = np.minimum(a, np.clip(sm * 2.0, 0, 1))
    st = tv.streak(angle)
    body = tone * (1 - var / 2 + var * tv.low) * (1 - streak / 2 + streak * st) * (0.92 + 0.16 * tv.mid)
    ring = np.clip(a - blur(a, 3 * S), 0, 1) * (0.4 + 1.0 * tv.mid)
    d = body * a + ring * edge * 1.6 * np.minimum(1.0, tone + 0.25)
    if bloom > 0:
        v = tv.mid * 0.7 + tv.low * 0.3
        ln = np.exp(-((v - 0.52) / 0.012) ** 2) + np.exp(-((v - 0.40) / 0.010) ** 2) * 0.7
        d = d + blur(ln.astype(np.float32), 0.8 * S) * a * bloom * tone * 0.5
    if dry_edge > 0:
        depth = np.clip(blur(a, dry_depth * S * 0.5) * 1.9 - 0.9, 0, 1)
        band = (1 - depth) * a
        if dry_side is not None:
            gy, gx = np.gradient(blur(a, 6 * S))
            g = -(gx * dry_side[0] + gy * dry_side[1])
            band = band * smoothstep(0.0, 0.004 * 2 / S, g)
        thr = (1 - depth) * 0.9
        kill = smoothstep(thr - 0.12, thr + 0.12, 1 - (st * 0.8 + tv.fine * 0.2)) * band * dry_edge
        d = d * (1 - np.clip(kill, 0, 1))
    halo = np.clip(blur(m, 4 * S) - a, 0, 1) * 0.12 * bleed * tone
    return np.clip(d + halo, 0, 0.995)


def rough_alpha(m, tv, rough=1.0, soft=1.0):
    """覆盖率 → 带毛涩边的 alpha（留白、遮挡用）。"""
    sm = blur(m, 1.0 * S * soft)
    n = (tv.fine - 0.5) * 0.5 + (tv.mid - 0.5) * 0.35
    a = np.clip((sm - 0.5 + n * 0.45 * rough) * 3.0 + 0.5, 0, 1)
    return np.minimum(a, np.clip(sm * 2.0, 0, 1))


_GRID = {}


def _grid():
    if "g" not in _GRID:
        yy, xx = np.mgrid[0:HS, 0:WS].astype(np.float32)
        _GRID["g"] = ((xx + 0.5) / S, (yy + 0.5) / S)
    return _GRID["g"]


def grad_field(g, bx=None):
    """线性渐变：g = ((x0,y0),(x1,y1),v0,v1)，1× 坐标。"""
    (x0, y0), (x1, y1), v0, v1 = g
    xx, yy = _grid()
    if bx is not None:
        xx, yy = sl(xx, bx), sl(yy, bx)
    dx, dy = x1 - x0, y1 - y0
    L2 = max(dx * dx + dy * dy, 1e-6)
    t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / L2, 0, 1)
    return (v0 + (v1 - v0) * t).astype(np.float32)


def radial(c, r, falloff=2.0):
    xx, yy = _grid()
    d = np.sqrt((xx - c[0]) ** 2 + (yy - c[1]) ** 2) / r
    return np.clip(1 - d, 0, 1) ** falloff


def _pad(p):
    k = p["kind"]
    if k == "wash":
        return max(24.0, p.get("dry_depth", 14.0) * 1.2 + 10)
    return 16.0


def render(parts, tex, cv=None):
    """按顺序合成 figures / scenes 产出的部件表。返回 (Canvas, extras)。
    extras['glow']：暖光（加色）；extras['tint']：[(alpha 全幅, rgb, mode)] 设色层。"""
    cv = cv or Canvas()
    glow = np.zeros((HS, WS), np.float32)
    tints = []
    layers = {}

    def _layer(p, d, bx):
        name = p.get("layer")
        if not name or d is None:
            return
        if name not in layers:
            layers[name] = np.zeros((HS, WS), np.float32)
        t = sl(layers[name], bx)
        t[...] = 1 - (1 - t) * (1 - np.clip(d, 0, 1))

    for p in parts:
        k = p["kind"]
        if k == "sweep":
            d, bx = sweep(p["pts"], p["width"], tex, ink=p.get("ink", 0.8), side=p.get("side", 0.6),
                          pale=p.get("pale", 0.3), dry=p.get("dry", 0.35), wet=p.get("wet", 0.4), seed=p.get("seed", 0),
                          kind=p.get("profile", "sweep"), streak=p.get("streak", 1.0), rough=p.get("rough", 1.0))
            if d is None:
                continue
            if p.get("mode") == "reserve":
                cv.reserve(d, bx)
            else:
                cv.ink(d, bx)
            _layer(p, d, bx)
            continue
        if k == "mask":                     # 只记图层，不上墨（遮挡、避让用）
            bx = box_of(p["pts"], 8)
            if bx is None:
                continue
            _layer(p, blur(fill(p["pts"], bx), p.get("soft", 2.0) * S), bx)
            continue
        if k == "sil":
            allp = [q for poly in p["polys"] for q in poly]
            bx = box_of(allp, max(30.0, p.get("dry_depth", 14.0) * 1.2 + 10))
            if bx is None:
                continue
            tv = tex.view(bx)
            m = np.zeros((bx[3] - bx[1], bx[2] - bx[0]), np.float32)
            for poly in p["polys"]:
                m = np.maximum(m, fill(poly, bx, sharp=p.get("sharp", False)))
            tone = p.get("tone", 0.7)
            if isinstance(tone, tuple):
                tone = grad_field(tone, bx)
            d = wash(m, tone, tv, angle=p.get("angle", 0.0), edge=p.get("edge", 0.3), bleed=p.get("bleed", 0.5),
                     var=p.get("var", 0.4), streak=p.get("streak", 0.06), dry_edge=p.get("dry_edge", 0.0),
                     dry_side=p.get("dry_side"), dry_depth=p.get("dry_depth", 14.0), soft=p.get("soft", 1.0),
                     bloom=p.get("bloom", 0.12))
            cv.ink(d, bx)
            _layer(p, d, bx)
            if p.get("rim"):
                # 逆光轮廓：受光一侧沿边留一道细白（光从绢面后透过来）
                lx, ly, w, amt = p["rim"]
                a = rough_alpha(m, tv, 0.5)
                band = np.clip((a - blur(a, w * S)) * 2.6, 0, 1)
                gy, gx = np.gradient(blur(a, 2.5 * S))
                gl = np.sqrt(gx * gx + gy * gy) + 1e-5
                facing = smoothstep(0.15, 0.75, (-(gx * lx + gy * ly)) / gl)
                brk = smoothstep(0.25, 0.55, tv.mid * 0.6 + tv.fine * 0.4)
                cv.reserve(band * facing * brk * amt, bx)
            continue
        if k in ("wash", "cover", "reserve") or (k == "tint" and "pts" in p):
            bx = box_of(p["pts"], _pad(p))
            if bx is None:
                continue
            tv = tex.view(bx)
            m = fill(p["pts"], bx, sharp=p.get("sharp", False))
            tone = p.get("tone", 0.5)
            if isinstance(tone, tuple):
                tone = grad_field(tone, bx)
            if k == "wash":
                d = wash(m, tone, tv, angle=p.get("angle", 0.0), edge=p.get("edge", 0.3),
                         bleed=p.get("bleed", 0.5), var=p.get("var", 0.4), streak=p.get("streak", 0.06),
                         dry_edge=p.get("dry_edge", 0.0), dry_side=p.get("dry_side"),
                         dry_depth=p.get("dry_depth", 14.0), soft=p.get("soft", 1.0),
                         bloom=p.get("bloom", 0.12))
                cv.ink(d, bx)
                _layer(p, d, bx)
            elif k == "cover":
                a = rough_alpha(m, tv, p.get("rough", 0.6), p.get("soft", 1.0))
                cv.reserve(a * p.get("amount", 1.0), bx)
                _layer(p, a, bx)
                if not np.isscalar(tone) or tone > 0:
                    cv.ink(wash(m, tone, tv, angle=p.get("angle", 0.0), edge=p.get("edge", 0.2), bleed=0.2,
                                var=p.get("var", 0.3), streak=p.get("streak", 0.08), bloom=p.get("bloom", 0.1),
                                soft=p.get("soft", 1.0)), bx)
            elif k == "reserve":
                cv.reserve(rough_alpha(m, tv, p.get("rough", 0.8), p.get("soft", 1.0)) * p.get("amount", 1.0), bx)
            else:
                full = np.zeros((HS, WS), np.float32)
                sl(full, bx)[...] = rough_alpha(m, tv, 0.8) * p.get("amount", 0.5)
                tints.append((full, p["rgb"], p.get("mode", "mul")))
        elif k in ("stroke", "rstroke") or k == "tint":
            path = p.get("pts") if k != "tint" else p["path"]
            amt = p.get("ink", 0.9) if k == "stroke" else p.get("amount", 0.85)
            d, bx = brush(path, p["width"], ink=amt, dry=p.get("dry", 0.35), seed=p.get("seed", 0),
                          kind=p.get("profile", "nail"), split=p.get("split", 0.0), grain=p.get("grain", 1.0),
                          fade=p.get("fade", 0.0), wet=p.get("wet", 1.0), jitter=p.get("jitter", 0.12))
            if d is None:
                continue
            _layer(p, d, bx)
            if k == "stroke":
                cv.ink(d, bx)
            elif k == "rstroke":
                cv.reserve(d, bx)
            else:
                full = np.zeros((HS, WS), np.float32)
                sl(full, bx)[...] = d
                tints.append((full, p["rgb"], p.get("mode", "opaque")))
        elif k == "glow":
            glow += radial(p["c"], p["r"], p.get("falloff", 2.0)) * p.get("amount", 1.0)
    return cv, {"glow": glow, "tint": tints, "layers": layers}
