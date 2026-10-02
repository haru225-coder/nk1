#!/usr/bin/env python3
"""大食蕃商缝合船 — 新资产，不改泉州宋船。

十三世纪印度洋缝合商船（游戏方案「大食蕃商」）：
椰索缀板（缝里的圆索，收进首尾柱，不是铁钉、不是叠接），一根前倾桅，
大斜桁上的三角软帆（无横竹），船尾两侧舵桨。
没有尾封板、没有正中尾轴舵、没有硬篷、没有水密隔舱。
武装护舶是同一条壳：货少、两舷齐胸栏杆上挂圆盾、几支矛尖，不是加莱。

船首 +Z，水线 y=0，右舷 +X，Y 朝上。尺度小于泉州福船。

用法：python3 tools/build_dashi_ship_mesh.py
产物：assets/ships/dashi_sewn_merchant.glb
      assets/ships/dashi_sewn_armed.glb
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "ships"

L = 7.35
HALF = L * 0.5
BEAM = 1.32  # 半宽。福船半宽 1.78、长 9.6，这条更短更瘦一圈
NSTRAKE = 7
NST = 40


def clamp(v, a, b):
    return a if v < a else b if v > b else v


def smoothstep(a, b, x):
    if b <= a:
        return 1.0 if x >= b else 0.0
    t = clamp((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vcross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def vlen(a):
    return math.sqrt(max(0.0, vdot(a, a)))


def vnorm(a):
    n = vlen(a)
    if n < 1e-8:
        return (0.0, 1.0, 0.0)
    return (a[0] / n, a[1] / n, a[2] / n)


def hsh(i: float) -> float:
    x = math.sin(i * 127.1 + 311.7) * 43758.5453
    return x - math.floor(x)


def mix(c, d, t):
    return tuple(lerp(a, b, t) for a, b in zip(c, d))


# 蜜色柚木、水下鱼油，没有宋船的水线朱。缝是椰索。
HONEY = (0.67, 0.46, 0.26, 1)
HONEY_LT = (0.80, 0.60, 0.38, 1)
HONEY_DK = (0.46, 0.29, 0.15, 1)
OIL = (0.20, 0.12, 0.07, 1)
OIL_LT = (0.30, 0.18, 0.10, 1)
# 两股都是椰色，不是白。近白的浅股在关深度的情况下会盖成一条白饰带。
# 深股是湿椰皮，浅股是干椰皮。浅股停在焦糖，不往米色走。
COIR = (0.62, 0.44, 0.22, 1)
COIR_DK = (0.16, 0.07, 0.03, 1)
COIR_LT = (0.55, 0.36, 0.16, 1)
# 板缝斜杠专用。中棕比柚木暗，比深股浅，近景两色交叉，不会漂成白饰带。
SEAM_MID = (0.58, 0.36, 0.16, 1)
COIR_ON_OIL = (0.90, 0.74, 0.40, 1)
WAD = (0.58, 0.42, 0.24, 1)
WAD_DK = (0.40, 0.28, 0.15, 1)
DECK = (0.72, 0.52, 0.31, 1)
DECK_DK = (0.50, 0.34, 0.18, 1)
CLAY = (0.76, 0.62, 0.46, 1)
CLAY_DK = (0.58, 0.42, 0.30, 1)
GLAZE = (0.20, 0.38, 0.34, 1)
GLAZE_LT = (0.40, 0.55, 0.46, 1)
INDIGO = (0.16, 0.20, 0.38, 1)
MADDER = (0.50, 0.18, 0.14, 1)
CLOTH = (0.64, 0.52, 0.36, 1)
LEATHER = (0.55, 0.34, 0.18, 1)
BRASS = (0.66, 0.50, 0.22, 1)
SAIL = (0.93, 0.88, 0.76, 1)
SAIL_DK = (0.62, 0.56, 0.46, 1)
RIB = (0.40, 0.25, 0.13, 1)


def z_of(t: float) -> float:
    return HALF - t * L


def beam_half(t: float) -> float:
    """两端收尖。最宽在舯前，货舱那段，不是宋船尾封板的宽艉。"""
    u = clamp(t, 0.0, 1.0)
    if u < 0.40:
        k = u / 0.40
        w = math.sin(k * math.pi * 0.5) ** 0.80
    else:
        k = (u - 0.40) / 0.60
        w = math.cos(k * math.pi * 0.5) ** 0.62
    return BEAM * max(0.03, w)


def sheer_deck(t: float) -> float:
    """低干舷，首尾抬起，艉略高于艏，给侧舵桨让出位置。不是楼。"""
    u = clamp(t, 0.0, 1.0)
    bow = 0.70 * math.exp(-((u - 0.0) / 0.20) ** 2)
    stern = 0.98 * math.exp(-((u - 1.0) / 0.20) ** 2)
    return 0.50 + bow + stern


def keel_y(t: float) -> float:
    u = clamp(t, 0.0, 1.0)
    rock = math.sin(math.pi * u) ** 0.60
    return -0.22 * max(0.22, rock)


def section_ring(t: float):
    """圆舭收到水线，水线以上干舷近乎竖直。

    侧视 18° 时，外撇的舷面会把板缝压成一条边。竖直干舷上每一条缝都露在舷外。
    """
    bh = beam_half(t)
    deck = sheer_deck(t)
    keel = keel_y(t)
    water = 0.04
    pts = []
    for i in range(NSTRAKE + 1):
        h = i / NSTRAKE
        if h <= 0.40:
            k = h / 0.40
            x = bh * 0.90 * (math.sin(k * math.pi * 0.5) ** 0.72)
            y = lerp(keel, water, k ** 0.80)
        else:
            k = (h - 0.40) / 0.60
            # 略向外，仍然是一堵矮舷，不是甲板那样的斜面。
            x = bh * (0.90 + 0.10 * (k ** 0.85))
            y = lerp(water, deck, k ** 0.92)
        pts.append((x, y))
    return pts


def stem_at(h: float):
    """艏柱前倾：柱头伸向船首上方。h 0 龙骨，1 柱头。"""
    y = lerp(keel_y(0.12) - 0.02, sheer_deck(0.04) + 0.46, h ** 0.92)
    z = lerp(z_of(0.07) + 0.02, z_of(0.0) + 0.58, smoothstep(0.0, 1.0, h))
    return (0.0, y, z)


def stern_at(h: float):
    """艉柱后倾，仍是尖的。没有尾封板。"""
    y = lerp(keel_y(0.88) - 0.02, sheer_deck(0.96) + 0.58, h ** 0.88)
    z = lerp(z_of(0.93) - 0.02, z_of(1.0) - 0.42, smoothstep(0.0, 1.0, h))
    return (0.0, y, z)


class Prim:
    def __init__(self, name: str, material: str):
        self.name = name
        self.material = material
        self.pos = []
        self.nrm = []
        self.col = []
        self.uv = []
        self.idx = []

    def _push(self, p, n, c, uv=(0.0, 0.0)):
        self.pos.append(p)
        self.nrm.append(n)
        self.col.append(c)
        self.uv.append(uv)
        return len(self.pos) - 1

    def tri(self, a, b, c, ca, cb, cc, uva=(0.0, 0.0), uvb=(0.0, 0.0), uvc=(0.0, 0.0)):
        n = vnorm(vcross(vsub(b, a), vsub(c, a)))
        ia = self._push(a, n, ca, uva)
        ib = self._push(b, n, cb, uvb)
        ic = self._push(c, n, cc, uvc)
        self.idx.extend((ia, ib, ic))

    def quad(self, a, b, c, d, color, uva=(0.0, 0.0), uvb=(0.0, 0.0), uvc=(0.0, 0.0), uvd=(0.0, 0.0)):
        self.tri(a, b, c, color, color, color, uva, uvb, uvc)
        self.tri(a, c, d, color, color, color, uva, uvc, uvd)

    def quad_vc(self, a, b, c, d, ca, cb, cc, cd, uva=(0.0, 0.0), uvb=(0.0, 0.0), uvc=(0.0, 0.0), uvd=(0.0, 0.0)):
        self.tri(a, b, c, ca, cb, cc, uva, uvb, uvc)
        self.tri(a, c, d, ca, cc, cd, uva, uvc, uvd)

    def quad_out(self, a, b, c, d, color, outward, uva=(0.0, 0.0), uvb=(0.0, 0.0), uvc=(0.0, 0.0), uvd=(0.0, 0.0)):
        n = vcross(vsub(b, a), vsub(c, a))
        if vdot(n, outward) < 0.0:
            self.quad(a, d, c, b, color, uva, uvd, uvc, uvb)
        else:
            self.quad(a, b, c, d, color, uva, uvb, uvc, uvd)

    def quad_out_vc(self, a, b, c, d, ca, cb, cc, cd, outward):
        n = vcross(vsub(b, a), vsub(c, a))
        if vdot(n, outward) < 0.0:
            self.quad_vc(a, d, c, b, ca, cd, cc, cb)
        else:
            self.quad_vc(a, b, c, d, ca, cb, cc, cd)

    def reverse_shell(self, darken=0.62):
        base = len(self.pos)
        for i in range(base):
            self.pos.append(self.pos[i])
            self.nrm.append(vmul(self.nrm[i], -1.0))
            c = self.col[i]
            self.col.append((c[0] * darken, c[1] * darken, c[2] * darken, c[3]))
            self.uv.append(self.uv[i])
        old = list(self.idx)
        for i in range(0, len(old), 3):
            a, b, c = old[i], old[i + 1], old[i + 2]
            self.idx.extend((a + base, c + base, b + base))

    def smooth(self):
        acc = {}
        for i, p in enumerate(self.pos):
            key = (round(p[0], 3), round(p[1], 3), round(p[2], 3))
            acc[key] = vadd(acc.get(key, (0, 0, 0)), self.nrm[i])
        for i, p in enumerate(self.pos):
            key = (round(p[0], 3), round(p[1], 3), round(p[2], 3))
            self.nrm[i] = vnorm(acc[key])


def add_box(prim: Prim, center, size, color, yaw=0.0):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cy, sy = math.cos(yaw), math.sin(yaw)
    corners = []
    for xi in (0, 1):
        for yi in (0, 1):
            for zi in (0, 1):
                x = -hx if xi == 0 else hx
                y = -hy if yi == 0 else hy
                z = -hz if zi == 0 else hz
                xr = x * cy + z * sy
                zr = -x * sy + z * cy
                corners.append(vadd(center, (xr, y, zr)))

    def ix(xi, yi, zi):
        return (xi * 2 + yi) * 2 + zi

    faces = [
        (ix(1, 0, 0), ix(1, 1, 0), ix(1, 1, 1), ix(1, 0, 1)),
        (ix(0, 0, 1), ix(0, 1, 1), ix(0, 1, 0), ix(0, 0, 0)),
        (ix(0, 1, 0), ix(0, 1, 1), ix(1, 1, 1), ix(1, 1, 0)),
        (ix(0, 0, 1), ix(0, 0, 0), ix(1, 0, 0), ix(1, 0, 1)),
        (ix(0, 0, 1), ix(1, 0, 1), ix(1, 1, 1), ix(0, 1, 1)),
        (ix(1, 0, 0), ix(0, 0, 0), ix(0, 1, 0), ix(1, 1, 0)),
    ]
    for f in faces:
        prim.quad(corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], color)


def add_cyl(prim: Prim, p0, p1, r, color, n=8, caps=True):
    axis = vsub(p1, p0)
    length = vlen(axis)
    if length < 1e-5 or r <= 0:
        return
    d = vnorm(axis)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.92 else (1.0, 0.0, 0.0)
    x = vnorm(vcross(d, up))
    y = vnorm(vcross(d, x))
    ring0, ring1 = [], []
    for i in range(n):
        a = i / n * math.tau
        o = vadd(vmul(x, math.cos(a) * r), vmul(y, math.sin(a) * r))
        ring0.append(vadd(p0, o))
        ring1.append(vadd(p1, o))
    for i in range(n):
        j = (i + 1) % n
        prim.quad(ring0[i], ring1[i], ring1[j], ring0[j], color)
    if caps:
        for i in range(n):
            j = (i + 1) % n
            prim.tri(p0, ring0[j], ring0[i], color, color, color)
            prim.tri(p1, ring1[i], ring1[j], color, color, color)



def add_cone(prim, base, tip, r, color, n=7):
    axis = vsub(tip, base)
    if vlen(axis) < 1e-5 or r <= 0:
        return
    d = vnorm(axis)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.92 else (1.0, 0.0, 0.0)
    x = vnorm(vcross(d, up))
    y = vnorm(vcross(d, x))
    ring = []
    for i in range(n):
        a = i / n * math.tau
        o = vadd(vmul(x, math.cos(a) * r), vmul(y, math.sin(a) * r))
        ring.append(vadd(base, o))
    for i in range(n):
        j = (i + 1) % n
        prim.tri(ring[i], ring[j], tip, color, color, color)
        prim.tri(base, ring[j], ring[i], color, color, color)


def add_sphere(prim: Prim, c, r, color, seg=8, rings=6):
    for i in range(rings):
        th0 = (i / rings - 0.5) * math.pi
        th1 = ((i + 1) / rings - 0.5) * math.pi
        for j in range(seg):
            u0 = j / seg * math.tau
            u1 = (j + 1) / seg * math.tau

            def p(th, u, c=c, r=r):
                return vadd(c, (
                    r * math.cos(th) * math.cos(u),
                    r * math.sin(th),
                    r * math.cos(th) * math.sin(u),
                ))

            prim.quad(p(th0, u0), p(th0, u1), p(th1, u1), p(th1, u0), color)


def rope(prim, a, b, sag, r, color, n=7):
    pts = []
    for i in range(n + 1):
        t = i / n
        p = (
            lerp(a[0], b[0], t),
            lerp(a[1], b[1], t) - sag * math.sin(math.pi * t),
            lerp(a[2], b[2], t),
        )
        pts.append(p)
    for i in range(n):
        add_cyl(prim, pts[i], pts[i + 1], r, color, 5, caps=False)


def plank_colors(y_mid, j, t):
    """水下鱼油，水上蜜色柚木。板缘压暗，留出绳缝的位置。没有朱红水线。"""
    if y_mid < 0.02:
        base = mix(OIL, OIL_LT, clamp((y_mid + 0.22) / 0.24, 0, 1))
    else:
        k = clamp((y_mid - 0.02) / 0.9, 0, 1)
        base = mix(HONEY_DK, HONEY_LT, 0.35 + 0.55 * k)
    jitter = 0.94 + 0.08 * hsh(j * 19.0 + t * 3.0)
    base = tuple(clamp(c * jitter, 0, 1) if i < 3 else c for i, c in enumerate(base))
    edge = tuple(clamp(c * 0.62, 0, 1) if i < 3 else c for i, c in enumerate(base))
    return base, edge


def seam_frame(ring, j):
    """缝在两列板的交线上，不在板心。返回切向（沿板面跨过缝）和舷外法向。"""
    j = int(clamp(j, 0, NSTRAKE))
    if 0 < j < NSTRAKE:
        t = (ring[j + 1][0] - ring[j - 1][0], ring[j + 1][1] - ring[j - 1][1])
    elif j == 0:
        t = (ring[1][0] - ring[0][0], ring[1][1] - ring[0][1])
    else:
        t = (ring[j][0] - ring[j - 1][0], ring[j][1] - ring[j - 1][1])
    tl = math.hypot(t[0], t[1]) or 1.0
    t = (t[0] / tl, t[1] / tl)
    n = (t[1], -t[0])
    if n[0] < 0.0:
        n = (-n[0], -n[1])
    return t, n

def add_cord(prim, a, b, r, col, n=5):
    if vlen(vsub(b, a)) < 1e-4:
        return
    add_cyl(prim, a, b, r, col, n, caps=False)


def _across_out(ring, j, sign):
    """板缝的横向（沿板面、跨过缝）和舷外法向。斜杠只在这个平面里歪，绳心不甩。"""
    tang, nrm = seam_frame(ring, j)
    across = (sign * tang[0], tang[1], 0.0)
    outward = (sign * nrm[0], nrm[1], 0.0)
    return vnorm(across), vnorm(outward)


# 近景整船大约 70 像素/米，一条水上板大约 0.11 米（缝与缝之间的木带）。
# 0.40 米的 45° 臂盖住整块板，舷侧读成网。0.22 米贴着缝（约 24°）近景只剩一道短杠。
# 臂长大约一块板高（略长一点，近景才看得出两根杠在交叉）。臂尖停在下一条缝之前，板心仍是一条木带。
# 每条水上缝大约六只分开的叉：深棕、中棕两根盒子在缝心交叉。板边不弯。
X_ARM = 0.175
X_WIDTH = 0.038
X_THICK = 0.022
# 沿缝权重。1 是 45°。再贴缝，近景两臂叠成一条杠。
X_ALONG = 1.05


def add_oriented_box(prim, center, long_axis, width_axis, length, width, thick, color):
    """细长盒子。long 是臂，width 在板面上横过臂，thick 朝舷外。"""
    u = vnorm(long_axis)
    v = vsub(width_axis, vmul(u, vdot(width_axis, u)))
    if vlen(v) < 1e-6 or length <= 0.0 or width <= 0.0 or thick <= 0.0:
        return
    v = vnorm(v)
    w = vnorm(vcross(u, v))
    hl, hw, ht = length * 0.5, width * 0.5, thick * 0.5

    def corner(su, sv, sw):
        return vadd(
            center,
            vadd(vadd(vmul(u, su * hl), vmul(v, sv * hw)), vmul(w, sw * ht)),
        )

    def face(a, b, c, d):
        prim.quad(a, b, c, d, color)

    face(corner(1, -1, -1), corner(1, 1, -1), corner(1, 1, 1), corner(1, -1, 1))
    face(corner(-1, 1, -1), corner(-1, -1, -1), corner(-1, -1, 1), corner(-1, 1, 1))
    face(corner(-1, 1, -1), corner(-1, 1, 1), corner(1, 1, 1), corner(1, 1, -1))
    face(corner(1, -1, -1), corner(1, -1, 1), corner(-1, -1, 1), corner(-1, -1, -1))
    face(corner(-1, -1, 1), corner(-1, 1, 1), corner(1, 1, 1), corner(1, -1, 1))
    face(corner(-1, 1, -1), corner(-1, -1, -1), corner(1, -1, -1), corner(1, 1, -1))


def _poly_len(samples):
    total = 0.0
    for i in range(len(samples) - 1):
        total += vlen(vsub(samples[i + 1][0], samples[i][0]))
    return total


def _at_dist(samples, dist):
    left = max(0.0, dist)
    for i in range(len(samples) - 1):
        d = vlen(vsub(samples[i + 1][0], samples[i][0]))
        if left <= d or i == len(samples) - 2:
            t = 0.0 if d < 1e-8 else clamp(left / d, 0.0, 1.0)
            a, b = samples[i], samples[i + 1]
            pos = tuple(lerp(a[0][c], b[0][c], t) for c in range(3))
            across = vnorm(tuple(lerp(a[1][c], b[1][c], t) for c in range(3)))
            outward = vnorm(tuple(lerp(a[2][c], b[2][c], t) for c in range(3)))
            tangent = vnorm(vsub(b[0], a[0]))
            return pos, across, outward, tangent
        left -= d
    return None


def add_stitch_x(prim, center, seam_dir, across, outward):
    """一只叉：两根细盒在缝心交叉。深棕与中棕，臂贴着直缝。不连到下一只。"""
    seam_dir = vnorm(seam_dir)
    across = vsub(across, vmul(seam_dir, vdot(across, seam_dir)))
    if vlen(across) < 1e-6:
        return False
    across = vnorm(across)
    outward = vnorm(outward)
    if vdot(outward, vcross(seam_dir, across)) < 0.0:
        outward = vmul(outward, -1.0)
    slash = vnorm(vadd(vmul(seam_dir, X_ALONG), across))
    back = vnorm(vsub(vmul(seam_dir, X_ALONG), across))
    sin_t = abs(vdot(slash, across))
    cos_t = max(0.15, abs(vdot(slash, seam_dir)))
    arm = X_ARM
    # 贴着水面的缝把整只叉缩小，留在水线上，避免切成半截的点。
    half = arm * 0.5 * sin_t + X_WIDTH * 0.5 * cos_t
    if center[1] - half < 0.04:
        room = center[1] - 0.04
        if room < 0.012 or half < 1e-6:
            return False
        arm = X_ARM * min(1.0, room / half)
        if arm < 0.06:
            return False
    width = X_WIDTH * (arm / X_ARM)
    thick = X_THICK
    # 中棕略抬出，交叉处压在深棕前面，两色都露出来，面不共面。
    c_dark = vadd(center, vmul(outward, thick * 0.15))
    c_mid = vadd(center, vmul(outward, thick * 0.85))
    add_oriented_box(prim, c_dark, slash, vcross(outward, slash), arm, width, thick, COIR_DK)
    add_oriented_box(prim, c_mid, back, vcross(outward, back), arm, width, thick, SEAM_MID)
    return True


def add_seam_xs(prim, samples, phase):
    """一条连续水上缝上大约六只分开的叉。短缝按长度少放，不挤成点。"""
    if len(samples) < 2:
        return 0
    length = _poly_len(samples)
    if length < 0.55:
        return 0
    # 整条舷缝大约 6 米，放 6 只。更短的露出段按同一间距少放。
    spacing = 1.02
    n = int(round(length / spacing))
    n = max(1, min(6, n))
    placed = 0
    for i in range(n):
        u = (i + 0.5 + phase) / n
        u = u - math.floor(u)
        # 两端留出半只叉，避免和收进柱子的叉叠在一起。
        dist = (0.08 + 0.84 * u) * length
        hit = _at_dist(samples, dist)
        if hit is None:
            continue
        pos, across, outward, tangent = hit
        if add_stitch_x(prim, pos, tangent, across, outward):
            placed += 1
    return placed


def add_seam_lace(prim, stations, j, sign):
    """水线以上每一条直缝。板边本身不动，缝上只放分开的叉。"""
    if j < 3:
        return 0
    # 最上一条略下移，舷缘木保持一根光边。
    if j >= NSTRAKE - 1:
        down, push = 0.045, 0.055
    else:
        down, push = 0.0, 0.055
    samples = []
    placed = 0
    # 相邻缝错开，叉不叠成一列。
    phase = (j * 0.37) % 1.0

    def flush():
        nonlocal samples, placed
        if len(samples) >= 2:
            placed += add_seam_xs(prim, samples, phase)
        samples = []

    for _t, z, ring in stations:
        if ring[j][1] < 0.07:
            flush()
            continue
        tang, nrm = seam_frame(ring, j)
        px = ring[j][0] - tang[0] * down
        py = ring[j][1] - tang[1] * down
        pos = (
            sign * px + sign * nrm[0] * push,
            py + nrm[1] * push,
            z,
        )
        across, outward = _across_out(ring, j, sign)
        samples.append((pos, across, outward))
    flush()
    return placed


def add_post_lace(prim, ring, z, post_fn, sign):
    """缝收到柱上：同一只叉，不是柱边的点。"""
    placed = 0
    for j in range(3, NSTRAKE):
        if ring[j][1] < 0.10:
            continue
        across, outward = _across_out(ring, j, sign)
        p = ring[j]
        start = (
            sign * p[0] + sign * outward[0] * 0.050,
            p[1] + outward[1] * 0.050,
            z,
        )
        post = post_fn(j / NSTRAKE)
        end = (
            post[0] + sign * 0.055,
            post[1] + 0.01,
            post[2] + (0.07 if post[2] > 0.0 else -0.07),
        )
        mid = (
            lerp(start[0], end[0], 0.55),
            lerp(start[1], end[1], 0.55),
            lerp(start[2], end[2], 0.55),
        )
        samples = [(start, across, outward), (mid, across, outward), (end, across, outward)]
        placed += add_seam_xs(prim, samples, (j * 0.17) % 1.0)
    return placed


def lash_post(prim, post_fn, push_z):
    """柱身上几圈椰索，板是缝上去的，不是钉上去的。"""
    for h in (0.22, 0.40, 0.58, 0.76):
        c = post_fn(h)
        c = (c[0], c[1] + 0.012, c[2] + push_z)
        prev = None
        first = None
        for i in range(7):
            a = i / 6 * math.tau
            p = (
                c[0] + math.cos(a) * 0.098,
                c[1] + math.sin(a) * 0.016,
                c[2] + math.sin(a) * 0.098,
            )
            if first is None:
                first = p
            if prev is not None:
                add_cord(prim, prev, p, 0.012, COIR_LT if i % 2 == 0 else COIR_DK, 4)
            prev = p
        add_cord(prim, prev, first, 0.011, COIR_DK, 4)


# 一条结构列板在 18° 侧视里大约 0.11 米，近景只剩几块胖木带。
# 每条再直剖成窄板。板心仍是柚木，板与板之间一条深色缝。缝沿原来的直边，板不外移、不打弯。
# 缝上的小叉不在这里加减或放大，仍只钉在原来的结构缝上。
SIDE_NARROW = 3
SEAM_FRAC = 0.36


def emit_plank(prim, a, b, c, d, base, outward, j=0):
    """a-b 下缘，d-c 上缘。沿高度剖成窄直板，板间深缝。外轮廓四个角不动。"""
    def mixp(p, q, t):
        return (lerp(p[0], q[0], t), lerp(p[1], q[1], t), lerp(p[2], q[2], t))

    def darken(col, k):
        return tuple(clamp(ch * k, 0, 1) if i < 3 else ch for i, ch in enumerate(col))

    seam = darken(base, 0.30)
    for s in range(SIDE_NARROW):
        t0 = s / SIDE_NARROW
        t1 = (s + 1) / SIDE_NARROW
        span = t1 - t0
        # 深缝只占这条窄板的上沿，和下一条的木面相接，两条缝不叠成一条黑带。
        wood1 = t0 + span * (1.0 - SEAM_FRAC)
        tone = 0.88 + 0.16 * hsh(j * 23.0 + s * 7.0)
        wood = tuple(clamp(ch * tone, 0, 1) if i < 3 else ch for i, ch in enumerate(base))
        prim.quad_out(
            mixp(a, d, t0), mixp(b, c, t0), mixp(b, c, wood1), mixp(a, d, wood1),
            wood, outward,
        )
        prim.quad_out(
            mixp(a, d, wood1), mixp(b, c, wood1), mixp(b, c, t1), mixp(a, d, t1),
            seam, outward,
        )


def build(kind: str):
    armed = kind == "armed"
    hull = Prim("Hull", "Wood")
    deck = Prim("Deck", "Wood")
    fit = Prim("Fittings", "Wood")
    stitch = Prim("Stitches", "Wood")
    sail = Prim("Sails", "Sail")
    shadow = Prim("Shadow", "Shadow")

    t0s, t1s = 0.075, 0.925
    stations = []
    for i in range(NST):
        t = lerp(t0s, t1s, i / (NST - 1))
        stations.append((t, z_of(t), section_ring(t)))

    def P(ring, j, z):
        return (ring[j][0], ring[j][1], z)

    for i in range(NST - 1):
        ta, za, ra = stations[i]
        tb, zb, rb = stations[i + 1]
        for j in range(NSTRAKE):
            a = P(ra, j, za)
            b = P(rb, j, zb)
            c = P(rb, j + 1, zb)
            d = P(ra, j + 1, za)
            mid = vmul(vadd(vadd(a, b), vadd(c, d)), 0.25)
            base, edge = plank_colors(mid[1], j, (ta + tb) * 0.5)
            outward = (mid[0], 0.25, 0.0)

            def mx(p):
                return (-p[0], p[1], p[2])

            emit_plank(hull, a, b, c, d, base, outward, j)
            emit_plank(hull, mx(a), mx(b), mx(c), mx(d), base, (-outward[0], outward[1], 0.0), j)

            # 缝不在这里点。整条板缝在下面是拧紧的两股椰索。

    # 艏柱、艉柱：板收到尖，再覆一根柱。没有尾封板。
    def fan_to_post(ring, z, post_fn, outward_z):
        for j in range(NSTRAKE):
            h0 = j / NSTRAKE
            h1 = (j + 1) / NSTRAKE
            a = (ring[j][0], ring[j][1], z)
            b = (ring[j + 1][0], ring[j + 1][1], z)
            c = post_fn(h1)
            d = post_fn(h0)
            midy = (a[1] + b[1] + c[1] + d[1]) * 0.25
            base, edge = plank_colors(midy, j, 0.02 if outward_z > 0 else 0.98)
            # 窄板收到尖，外轮廓仍是柱和这一站的边，没有尾封板。
            emit_plank(hull, a, d, c, b, base, (a[0], 0.2, outward_z), j)
            emit_plank(
                hull,
                (-a[0], a[1], a[2]),
                d,
                c,
                (-b[0], b[1], b[2]),
                base,
                (-a[0], 0.2, outward_z),
                j,
            )

    fan_to_post(stations[0][2], stations[0][1], stem_at, 1.0)
    fan_to_post(stations[-1][2], stations[-1][1], stern_at, -1.0)
    seam_xs = 0
    for j in range(1, NSTRAKE):
        for sgn in (1.0, -1.0):
            seam_xs += add_seam_lace(stitch, stations, j, sgn)
    post_xs = 0
    for sgn in (1.0, -1.0):
        post_xs += add_post_lace(stitch, stations[0][2], stations[0][1], stem_at, sgn)
        post_xs += add_post_lace(stitch, stations[-1][2], stations[-1][1], stern_at, sgn)
    print(f"stitch xs seam={seam_xs} post={post_xs}")

    def lay_post(fn, color, push_z):
        # 柱身移出板缝，避免和收尖的面挤在同一层上闪黑边。
        pts = []
        for i in range(11):
            q = fn(i / 10)
            pts.append((q[0], q[1] + 0.01, q[2] + push_z))
        for i in range(10):
            add_cyl(fit, pts[i], pts[i + 1], 0.055, color, 6, caps=False)
        add_sphere(fit, pts[-1], 0.08, color, 8, 6)
        return pts[-1]

    stem_head = lay_post(stem_at, HONEY_DK, 0.05)
    lay_post(stern_at, HONEY_DK, -0.05)
    lash_post(stitch, stem_at, 0.05)
    lash_post(stitch, stern_at, -0.05)
    add_sphere(fit, vadd(stem_head, (0, 0.03, 0.02)), 0.042, BRASS, 6, 5)

    hull.smooth()
    hull.reverse_shell(0.58)

    # 甲板：纵铺。舱口留空，看得见一整个货舱，没有隔板。
    hatch0, hatch1 = (0.46, 0.60) if armed else (0.40, 0.66)
    hatch_frac = 0.42 if armed else 0.58

    def in_hatch(t, x, beam):
        return hatch0 < t < hatch1 and abs(x) < beam * hatch_frac

    for i in range(NST - 1):
        ta, za, ra = stations[i]
        tb, zb, rb = stations[i + 1]
        b0 = ra[-1][0] * 0.90
        b1 = rb[-1][0] * 0.90
        y0 = ra[-1][1]
        y1 = rb[-1][1]
        n_across = 18
        for k in range(n_across):
            u0 = -1.0 + 2.0 * k / n_across
            u1 = -1.0 + 2.0 * (k + 1) / n_across

            def dp(u, b, y, z, t):
                x = u * b
                cam = 0.055 * (1.0 - (abs(u) ** 2))
                return (x, y + 0.02 + cam, z), t

            a, _ = dp(u0, b0, y0, za, ta)
            b, _ = dp(u0, b1, y1, zb, tb)
            c, _ = dp(u1, b1, y1, zb, tb)
            d, _ = dp(u1, b0, y0, za, ta)
            mx_ = (a[0] + c[0]) * 0.5
            mt = (ta + tb) * 0.5
            if in_hatch(mt, mx_, (b0 + b1) * 0.5):
                continue
            tone = 0.90 + 0.12 * hsh(k * 13.1)
            base = mix(DECK_DK, DECK, tone)
            if k % 2 == 1:
                base = tuple(clamp(ch * 0.88, 0, 1) if ii < 3 else ch for ii, ch in enumerate(base))
            deck.quad_out(a, d, c, b, base, (0, 1, 0))

    # 舱口围板
    z_h0, z_h1 = z_of(hatch1), z_of(hatch0)
    t_mid = (hatch0 + hatch1) * 0.5
    y_h = sheer_deck(t_mid) + 0.02
    half_w = beam_half(t_mid) * 0.90 * hatch_frac
    coam_h = 0.07
    # 四边
    add_box(fit, (0, y_h + coam_h * 0.5, z_h0), (half_w * 2.0, coam_h, 0.045), HONEY_DK)
    add_box(fit, (0, y_h + coam_h * 0.5, z_h1), (half_w * 2.0, coam_h, 0.045), HONEY_DK)
    add_box(fit, (-half_w, y_h + coam_h * 0.5, (z_h0 + z_h1) * 0.5), (0.045, coam_h, abs(z_h1 - z_h0)), HONEY_DK)
    add_box(fit, (half_w, y_h + coam_h * 0.5, (z_h0 + z_h1) * 0.5), (0.045, coam_h, abs(z_h1 - z_h0)), HONEY_DK)

    # 肋骨：稀疏，绑在板上。舱里能从这一头看到那一头，没有水密隔舱。
    for t in (0.44, 0.50, 0.56, 0.62):
        ring = section_ring(t)
        z = z_of(t)
        pts = []
        for x, y in ring:
            pts.append((x * 0.78, max(y, 0.02) * 0.92 + 0.04, z))
        for s in (1.0, -1.0):
            seq = [(p[0] * s, p[1], p[2]) for p in pts]
            # 只画舱内看得到的下半，避免穿出甲板
            for a, b in zip(seq, seq[1:]):
                if a[1] > sheer_deck(t) - 0.02 and b[1] > sheer_deck(t) - 0.02:
                    continue
                add_cyl(fit, a, b, 0.028, RIB, 5, caps=False)

    # 舱底几块松板，货搁在上面。不是隔舱壁。
    floor_y = 0.06
    for k, t in enumerate((0.46, 0.52, 0.58)):
        add_box(fit, (0, floor_y, z_of(t)), (beam_half(t) * 0.70, 0.035, 0.22), DECK_DK)

    # 舷墙顶木
    for i in range(0, NST - 1, 1):
        ta, za, ra = stations[i]
        tb, zb, rb = stations[i + 1]
        for s in (1.0, -1.0):
            a = (s * ra[-1][0], ra[-1][1], za)
            b = (s * rb[-1][0], rb[-1][1], zb)
            c = (b[0] * 0.96, b[1] + 0.16, b[2])
            d = (a[0] * 0.96, a[1] + 0.16, a[2])
            fit.quad_out(a, b, c, d, HONEY_DK, (s, 0.4, 0))
            e = (d[0] * 0.97, d[1] + 0.040, d[2])
            f = (c[0] * 0.97, c[1] + 0.040, c[2])
            fit.quad_out(d, c, f, e, HONEY, (0, 1, 0))

    # —— 桅：前倾。一根。 ——
    t_mast = 0.36
    foot = (0.0, sheer_deck(t_mast) + 0.02, z_of(t_mast))
    rake = math.radians(28.0)
    mast_h = 4.55
    top = (
        0.0,
        foot[1] + mast_h * math.cos(rake),
        foot[2] + mast_h * math.sin(rake),
    )
    # 桅身略收分：两段
    mid_m = vadd(vmul(foot, 0.45), vmul(top, 0.55))
    add_cyl(fit, foot, mid_m, 0.075, HONEY_DK, 8)
    add_cyl(fit, mid_m, top, 0.048, mix(HONEY_DK, HONEY, 0.45), 8)
    # 椰索桅箍，不是铁箍
    for k in range(4):
        p = vadd(vmul(foot, 1.0 - (0.22 + k * 0.16)), vmul(top, 0.22 + k * 0.16))
        p2 = vadd(p, vmul(vnorm(vsub(top, foot)), 0.045))
        add_cyl(fit, p, p2, 0.09 if k == 0 else 0.078, WAD_DK, 8, caps=False)
    # 桅座
    add_box(fit, (foot[0], foot[1] + 0.02, foot[2]), (0.28, 0.06, 0.36), HONEY_DK)

    # —— 斜桁三角软帆。桁低的一头在艏，高的一头在后上方。没有横竹。 ——
    # 布心鼓成一个软肚子，不是抬出去的平板。布心只比边暖一档奶油色，不是一块深棕污渍。
    # 三个角钉死。肚子留在舷墙之上，甲板、货、挡板从帆边上露出来。
    tack = (0.04, sheer_deck(0.03) + 0.70, z_of(0.0) + 0.18)
    peak = (0.04, foot[1] + 4.65, z_of(0.56))
    clew = (0.62, sheer_deck(0.38) + 0.92, z_of(0.36))
    sail_n = vnorm(vcross(vsub(peak, tack), vsub(clew, tack)))
    if sail_n[0] < 0.0:
        sail_n = vmul(sail_n, -1.0)
    nu, nv = 24, 14
    # 肚子只在布心暖一档。比边布略黄、仍是浅奶油，不能落成深棕污点。
    BELLY = (0.98, 0.91, 0.74, 1)

    def sail_p(u, v):
        yard = (
            lerp(tack[0], peak[0], u),
            lerp(tack[1], peak[1], u),
            lerp(tack[2], peak[2], u),
        )
        foot_pt = (
            lerp(tack[0], clew[0], u),
            lerp(tack[1], clew[1], u),
            lerp(tack[2], clew[2], u),
        )
        # 下缘中段下垂，仍是三个角。垂幅不大，不盖住干舷。
        sag = math.sin(math.pi * u) ** 0.85
        foot_pt = (
            foot_pt[0] + 0.28 * sag,
            foot_pt[1] - 0.26 * sag,
            foot_pt[2] - 0.08 * sag,
        )
        p = (
            lerp(yard[0], foot_pt[0], v),
            lerp(yard[1], foot_pt[1], v),
            lerp(yard[2], foot_pt[2], v),
        )
        # 指数大于 1：弧顶在布心，不是边上一抬、中间仍是平板。
        billow = (math.sin(math.pi * u) ** 1.45) * (math.sin(math.pi * clamp(v, 0.0, 1.0)) ** 1.35)
        roach = math.sin(math.pi * v) * math.exp(-((u - 1.0) / 0.34) ** 2)
        amp = 0.62 * billow + 0.10 * roach
        p = vadd(p, vmul(sail_n, amp))
        p = (p[0], p[1] - 0.12 * billow * v, p[2])
        return p, billow

    def sail_col(u, v, billow):
        # 布心略暖的奶油，三个角仍是浅边。没有第二条色带，也没有横竹。
        col = mix(SAIL, BELLY, billow ** 1.85)
        if 0.055 < v < 0.11:
            col = mix(col, INDIGO, 0.42)
        elif v < 0.03 or v > 0.97 or u < 0.025 or u > 0.975:
            col = mix(col, SAIL_DK, 0.55)
        return col

    for iu in range(nu):
        for iv in range(nv):
            u0, u1 = iu / nu, (iu + 1) / nu
            v0, v1 = iv / nv, (iv + 1) / nv
            a, ba = sail_p(u0, v0)
            b, bb = sail_p(u1, v0)
            c, bc = sail_p(u1, v1)
            d, bd = sail_p(u0, v1)
            sail.quad_vc(
                a, b, c, d,
                sail_col(u0, v0, ba),
                sail_col(u1, v0, bb),
                sail_col(u1, v1, bc),
                sail_col(u0, v1, bd),
                (u0, v0), (u1, v0), (u1, v1), (u0, v1),
            )

    # 先把正面法线磨顺，再翻一层背面。正反面叠在同一点上不能一起磨，会对消。
    sail.smooth()
    sail.reverse_shell(0.90)

    # 斜桁离开帆布一掌，中间粗、两头细。远看是一根木，不是帆的一条边。
    def yard_at(u):
        base = (
            lerp(tack[0], peak[0], u),
            lerp(tack[1], peak[1], u),
            lerp(tack[2], peak[2], u),
        )
        lift = vadd((0.0, 0.18, 0.0), vmul(sail_n, -0.14))
        return vadd(base, lift)

    steps = 14
    for i in range(steps):
        u0, u1 = i / steps, (i + 1) / steps
        r = 0.055 + 0.048 * math.sin(math.pi * (u0 + u1) * 0.5)
        add_cyl(fit, yard_at(u0), yard_at(u1), r, HONEY_DK, 7, caps=False)
    add_sphere(fit, yard_at(0.0), 0.055, HONEY_DK, 6, 4)
    add_sphere(fit, yard_at(1.0), 0.048, HONEY_DK, 6, 4)
    # 下缘、后缘一条镶绳，剪影有粗细，不是刀切的三角。
    for i in range(nu):
        u0, u1 = i / nu, (i + 1) / nu
        fa, _ = sail_p(u0, 1.0)
        fb, _ = sail_p(u1, 1.0)
        add_cyl(fit, fa, fb, 0.018, WAD_DK, 4, caps=False)
    for i in range(nv):
        v0, v1 = i / nv, (i + 1) / nv
        fa, _ = sail_p(1.0, v0)
        fb, _ = sail_p(1.0, v1)
        add_cyl(fit, fa, fb, 0.016, WAD_DK, 4, caps=False)

    # 桁与桅的绑扎（大约在桁的前三分之一）
    lash = yard_at(0.34)
    add_cyl(fit, vadd(lash, (-0.02, -0.08, 0)), vadd(lash, (0.02, 0.06, 0)), 0.055, WAD_DK, 6, caps=False)
    rope(fit, tack, (0.0, sheer_deck(0.05) + 0.15, stem_at(0.4)[2]), 0.05, 0.012, WAD_DK, 5)
    rope(fit, clew, (0.35, sheer_deck(0.86) + 0.15, z_of(0.88)), 0.10, 0.014, WAD_DK, 6)
    rope(fit, peak, (0.0, top[1] - 0.05, top[2]), 0.04, 0.012, WAD_DK, 4)
    # 前支索、后支索。软，没有硬帆的升降索那么密。
    rope(fit, top, (0.0, sheer_deck(0.06) + 0.35, stem_at(0.85)[2]), 0.06, 0.014, WAD_DK, 6)
    rope(fit, top, (0.15, sheer_deck(0.90) + 0.25, z_of(0.92)), 0.12, 0.013, WAD_DK, 6)
    rope(fit, top, (-0.15, sheer_deck(0.90) + 0.25, z_of(0.92)), 0.12, 0.013, WAD_DK, 6)

    # 桅顶小旗，靛色，不是宋军牙旗
    pennant_root = top
    pennant_tip = (top[0] - 0.55, top[1] - 0.18, top[2] - 0.15)
    pennant_mid = (top[0] - 0.28, top[1] - 0.22, top[2] - 0.05)
    sail.tri(pennant_root, pennant_mid, pennant_tip, INDIGO, INDIGO, mix(INDIGO, SAIL, 0.4))
    sail.tri(pennant_root, pennant_tip, pennant_mid, mix(INDIGO, (0, 0, 0, 1), 0.25), INDIGO, INDIGO)

    # —— 尾侧舵桨。两支，绑在两根横梁之间。不是正中尾舵，也不是一排桨。 ——
    t_a, t_b = 0.78, 0.86
    y_beam = sheer_deck(0.82) + 0.10
    # 横梁收到舷内，不从船壳里戳出去。
    add_box(fit, (0, y_beam, z_of(t_a)), (beam_half(0.78) * 1.72, 0.08, 0.10), HONEY_DK)
    add_box(fit, (0, y_beam, z_of(t_b)), (beam_half(0.86) * 1.55, 0.08, 0.10), HONEY_DK)
    def add_oar_blade(center, axis, across, thick, face, edge):
        """外端一块扁木叶。比杆宽出一截，两头收，不是方铲，也不是棍子。"""
        stations = (
            (-0.50, 0.062),
            (-0.26, 0.18),
            (0.02, 0.28),
            (0.24, 0.25),
            (0.48, 0.075),
        )
        ht = 0.030
        rings = []
        for s, hw in stations:
            c = vadd(center, vmul(axis, s))
            rings.append((
                vadd(c, vmul(across, -hw)),
                vadd(c, vmul(across, hw)),
            ))
        for i in range(len(rings) - 1):
            a0, d0 = rings[i]
            b0, c0 = rings[i + 1]
            a = vadd(a0, vmul(thick, ht))
            b = vadd(b0, vmul(thick, ht))
            c = vadd(c0, vmul(thick, ht))
            d = vadd(d0, vmul(thick, ht))
            fit.quad_out(a, b, c, d, face, thick)
            a2 = vadd(a0, vmul(thick, -ht))
            b2 = vadd(b0, vmul(thick, -ht))
            c2 = vadd(c0, vmul(thick, -ht))
            d2 = vadd(d0, vmul(thick, -ht))
            fit.quad_out(a2, d2, c2, b2, mix(face, OIL, 0.35), vmul(thick, -1))
            fit.quad_out(a, a2, b2, b, edge, vmul(across, -1))
            fit.quad_out(d, c, c2, d2, edge, across)
        # 叶根、叶尖封口
        a0, d0 = rings[0]
        fit.quad_out(
            vadd(a0, vmul(thick, ht)),
            vadd(d0, vmul(thick, ht)),
            vadd(d0, vmul(thick, -ht)),
            vadd(a0, vmul(thick, -ht)),
            edge,
            vmul(axis, -1),
        )
        b0, c0 = rings[-1]
        fit.quad_out(
            vadd(b0, vmul(thick, ht)),
            vadd(b0, vmul(thick, -ht)),
            vadd(c0, vmul(thick, -ht)),
            vadd(c0, vmul(thick, ht)),
            edge,
            axis,
        )

    def quarter_rudder(sign):
        z = (z_of(t_a) + z_of(t_b)) * 0.5 - 0.15
        # 两支都甩到舷外、再伸向艉后。不是正中尾轴舵。
        x = sign * (beam_half(0.84) + 0.30)
        pivot = (x, y_beam + 0.04, z)
        # 扁叶在外端，整片在艉柱之后、水线之上，18° 两侧都能看见比杆宽的平面。
        tip = (x + sign * 0.50, 0.26, z - 2.20)
        axis = vnorm(vsub(tip, pivot))
        # 叶面大致竖直、法线朝外。侧看是扁叶，不是朝镜头翻开的方板。
        thick = vnorm((sign * 0.92, 0.12, 0.28))
        thick = vnorm(vsub(thick, vmul(axis, vdot(thick, axis))))
        across = vnorm(vcross(thick, axis))
        if across[1] < 0.0:
            across = vmul(across, -1.0)
            thick = vmul(thick, -1.0)
        center = vadd(tip, vmul(axis, -0.48))
        root = vadd(center, vmul(axis, -0.50))
        add_cyl(fit, pivot, root, 0.040, HONEY_DK, 6)
        face = mix(HONEY_LT, HONEY, 0.40)
        add_oar_blade(center, axis, across, thick, face, HONEY_DK)
        tiller = (sign * 0.55, y_beam + 0.22, z + 0.35)
        add_cyl(fit, pivot, tiller, 0.028, HONEY, 5)
        for zz in (z_of(t_a), z_of(t_b)):
            rope(fit, (sign * beam_half(0.82) * 0.85, y_beam, zz), pivot, 0.06, 0.014, COIR, 4)

    quarter_rudder(1.0)
    quarter_rudder(-1.0)

    # 舵手站的地方只是甲板升高一掌，不是艉楼
    add_box(fit, (0, sheer_deck(0.90) + 0.05, z_of(0.90)), (beam_half(0.90) * 1.15, 0.06, 0.55), DECK)

    # 系缆羊角
    for t, x in ((0.16, 0.28), (0.16, -0.28), (0.70, 0.32), (0.70, -0.32)):
        y = sheer_deck(t) + 0.08
        add_cyl(fit, (x, y, z_of(t)), (x, y + 0.16, z_of(t)), 0.028, HONEY_DK, 5)
        add_cyl(fit, (x - 0.07, y + 0.14, z_of(t)), (x + 0.07, y + 0.14, z_of(t)), 0.018, HONEY, 5, caps=False)

    # 艏一盘椰索
    coil_c = (0.0, sheer_deck(0.14) + 0.08, z_of(0.14))
    for k in range(5):
        r = 0.10 + k * 0.028
        prev = None
        for i in range(9):
            a = i / 8 * math.tau
            p = (coil_c[0] + math.cos(a) * r, coil_c[1] + (0.01 if k % 2 else 0), coil_c[2] + math.sin(a) * r * 0.72)
            if prev:
                add_cyl(fit, prev, p, 0.012, WAD_DK, 4, caps=False)
            prev = p

    if not armed:
        # 商船：舱口堆货。罐子、布包、没有隔舱把它们分开。
        def jar(pos, h, r, body, neck):
            add_sphere(fit, (pos[0], pos[1] + h * 0.42, pos[2]), r, body, 8, 6)
            add_cyl(fit, (pos[0], pos[1] + h * 0.62, pos[2]), (pos[0], pos[1] + h, pos[2]), r * 0.34, neck, 6)
            add_sphere(fit, (pos[0], pos[1] + h * 0.95, pos[2]), r * 0.22, neck, 6, 4)
        yb = y_h + 0.02
        zc = z_of(0.52)
        jar((0.22, yb, zc + 0.28), 0.50, 0.16, CLAY, CLAY_DK)
        jar((-0.20, yb, zc + 0.22), 0.42, 0.14, CLAY, CLAY_DK)
        jar((0.05, yb, zc - 0.05), 0.58, 0.18, GLAZE, GLAZE_LT)
        jar((-0.08, yb, zc + 0.48), 0.36, 0.12, CLAY_DK, CLAY)
        jar((0.28, yb, zc - 0.28), 0.40, 0.13, CLAY, CLAY_DK)
        # 甲板布包，绳捆
        def bale(pos, size, color):
            add_box(fit, pos, size, color)
            y = pos[1] + size[1] * 0.5
            add_cyl(fit, (pos[0] - size[0] * 0.5, y, pos[2]), (pos[0] + size[0] * 0.5, y, pos[2]), 0.012, WAD_DK, 4, caps=False)
            add_cyl(fit, (pos[0], y, pos[2] - size[2] * 0.5), (pos[0], y, pos[2] + size[2] * 0.5), 0.012, WAD_DK, 4, caps=False)
        bale((0.48, sheer_deck(0.28) + 0.16, z_of(0.26)), (0.40, 0.28, 0.46), INDIGO)
        bale((-0.42, sheer_deck(0.30) + 0.14, z_of(0.30)), (0.36, 0.24, 0.40), MADDER)
        bale((0.15, sheer_deck(0.72) + 0.12, z_of(0.70)), (0.42, 0.22, 0.36), CLOTH)
        # 一捆短木料，横放，不是桨
        for k in range(3):
            add_cyl(
                fit,
                (-0.35, sheer_deck(0.22) + 0.08 + k * 0.06, z_of(0.20)),
                (-0.35, sheer_deck(0.22) + 0.08 + k * 0.06, z_of(0.20) - 0.7),
                0.035,
                HONEY_DK,
                5,
            )
    else:
        # 护舶：同一条壳，货只留一罐。两舷一根齐胸栏杆，圆盾挂在栏下，几支矛尖探出栏上。
        # 栏下是空的，看得到甲板。不是挡板箱子，不是楼，不是第二层甲板，也不是加莱。
        rail_h = 1.05
        post_ts = (0.43, 0.53, 0.63, 0.73)
        rail_col = mix(HONEY, HONEY_DK, 0.25)
        for sign in (1.0, -1.0):
            posts = []
            for t in post_ts:
                ring = section_ring(t)
                x = sign * ring[-1][0] * 0.97
                y0 = ring[-1][1] + 0.22
                y1 = ring[-1][1] + rail_h
                z = z_of(t)
                posts.append((x, y0, y1, z))
                add_cyl(fit, (x, y0, z), (x, y1 + 0.02, z), 0.050, HONEY_DK, 6)
            for i in range(len(posts) - 1):
                a, b = posts[i], posts[i + 1]
                add_cyl(fit, (a[0], a[2], a[3]), (b[0], b[2], b[3]), 0.062, rail_col, 6, caps=False)
            for i, t in enumerate((0.48, 0.58, 0.68)):
                ring = section_ring(t)
                y = ring[-1][1] + 0.62
                z = z_of(t)
                x = sign * ring[-1][0] * 0.97
                face = LEATHER if i != 1 else mix(MADDER, LEATHER, 0.40)
                rim = mix(face, (0.10, 0.05, 0.03, 1), 0.55)
                # 盾面朝外，上沿刚好接到栏杆，中间是圆盾不是板子上的圆点。
                add_cyl(fit, (x, y, z), (x + sign * 0.016, y, z), 0.24, rim, 16, caps=True)
                add_cyl(fit, (x + sign * 0.012, y, z), (x + sign * 0.042, y, z), 0.195, face, 16, caps=True)
                add_sphere(fit, (x + sign * 0.050, y, z), 0.046, BRASS, 7, 5)
                add_cyl(
                    fit,
                    (x + sign * 0.02, y + 0.20, z),
                    (x, ring[-1][1] + rail_h, z),
                    0.014,
                    COIR_DK,
                    4,
                    caps=False,
                )
            for k, t in enumerate((0.50, 0.60, 0.70)):
                ring = section_ring(t)
                z = z_of(t) + (k - 1) * 0.04
                yb = ring[-1][1] + 0.10
                xb = sign * ring[-1][0] * 0.42
                xt = sign * (ring[-1][0] * 0.97 + 0.10)
                yt = ring[-1][1] + rail_h + 0.48
                shaft_end = (lerp(xb, xt, 0.74), lerp(yb, yt, 0.74), z)
                tip = (xt, yt, z)
                add_cyl(fit, (xb, yb, z), shaft_end, 0.018, HONEY_DK, 5, caps=False)
                add_cone(fit, shaft_end, tip, 0.040, BRASS, 7)
        # 一罐，搁在艉甲板，不挡栏杆。
        jz = z_of(0.86)
        jy = sheer_deck(0.86) + 0.04
        add_sphere(fit, (-0.16, jy + 0.15, jz), 0.14, CLAY, 8, 6)
        add_cyl(fit, (-0.16, jy + 0.22, jz), (-0.16, jy + 0.38, jz), 0.048, CLAY_DK, 6)
        add_sphere(fit, (-0.16, jy + 0.36, jz), 0.032, CLAY_DK, 6, 4)

    # 接触阴影贴在水线正下方，和水线轮廓对齐。龙骨仍在水下，阴影不悬在船肚中间。
    for i in range(28):
        a0 = i / 28 * math.tau
        a1 = (i + 1) / 28 * math.tau
        for k in range(4):
            r0 = 0.15 + k * 0.48
            r1 = r0 + 0.48
            alpha = 0.55 * (1.0 - k / 4) ** 1.15
            col = (0.02, 0.05, 0.07, alpha)

            def sp(a, r, col=col):
                # 比水线轮廓宽一圈，斜俯时露在壳外面，贴着切开的船底。
                return (math.cos(a) * (0.70 + r * 0.95), -0.02, math.sin(a) * (1.85 + r * 1.25))

            shadow.quad(sp(a0, r0), sp(a1, r0), sp(a1, r1), sp(a0, r1), col)

    return [hull, deck, fit, stitch, sail, shadow]


def _lerp_vert(a, b, t):
    def lp(x, y):
        return tuple(lerp(u, v, t) for u, v in zip(x, y))
    return lp(a[0], b[0]), lp(a[1], b[1]), lp(a[2], b[2]), lp(a[3], b[3])


def clip_above(prim: Prim, y0: float):
    """把壳切在水线。船底不再整块悬在海面上；切边就是水线。"""
    pos, nrm, col, uv, idx = [], [], [], [], []

    def push(v):
        pos.append(v[0])
        nrm.append(vnorm(v[1]))
        col.append(v[2])
        uv.append(v[3])
        return len(pos) - 1

    for i in range(0, len(prim.idx), 3):
        verts = []
        for k in prim.idx[i:i + 3]:
            verts.append((prim.pos[k], prim.nrm[k], prim.col[k], prim.uv[k]))
        out = []
        for n in range(3):
            cur = verts[n]
            prv = verts[n - 1]
            cy, py = cur[0][1], prv[0][1]
            cin, pin = cy >= y0 - 1e-8, py >= y0 - 1e-8
            if cin and pin:
                out.append(cur)
            elif pin and not cin:
                denom = cy - py
                t = 0.0 if abs(denom) < 1e-8 else (y0 - py) / denom
                out.append(_lerp_vert(prv, cur, t))
            elif cin and not pin:
                denom = cy - py
                t = 0.0 if abs(denom) < 1e-8 else (y0 - py) / denom
                out.append(_lerp_vert(prv, cur, t))
                out.append(cur)
        if len(out) < 3:
            continue
        ids = [push(v) for v in out]
        for k in range(1, len(ids) - 1):
            idx.extend((ids[0], ids[k], ids[k + 1]))
    prim.pos, prim.nrm, prim.col, prim.uv, prim.idx = pos, nrm, col, uv, idx


def pack_glb(prims, out: Path, root_name: str):
    mats = {
        "Wood": {
            "name": "Wood",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.84,
            },
            "doubleSided": False,
        },
        "Sail": {
            "name": "Sail",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.72,
            },
            "doubleSided": True,
        },
        "Shadow": {
            "name": "Shadow",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
            "alphaMode": "BLEND",
            "doubleSided": True,
            "extensions": {"KHR_materials_unlit": {}},
        },
    }
    order = ["Wood", "Sail", "Shadow"]
    mat_index = {name: i for i, name in enumerate(order)}

    blob = bytearray()
    buffer_views = []
    accessors = []
    meshes = []
    nodes = []

    def align(n=4):
        while len(blob) % n:
            blob.append(0)

    def push_floats(data):
        align(4)
        off = len(blob)
        for v in data:
            blob.extend(struct.pack("<f", float(v)))
        return off, len(blob) - off

    def push_idx(data):
        align(4)
        off = len(blob)
        for v in data:
            blob.extend(struct.pack("<I", int(v)))
        return off, len(blob) - off

    for prim in prims:
        if not prim.idx:
            continue
        xs = [p[0] for p in prim.pos]
        ys = [p[1] for p in prim.pos]
        zs = [p[2] for p in prim.pos]
        flat_p = [c for p in prim.pos for c in p]
        flat_n = [c for p in prim.nrm for c in p]
        flat_c = [c for p in prim.col for c in p]
        flat_uv = [c for p in prim.uv for c in p]
        op, lp = push_floats(flat_p)
        on, ln = push_floats(flat_n)
        oc, lc = push_floats(flat_c)
        ou, lu = push_floats(flat_uv)
        oi, li = push_idx(prim.idx)
        bv0 = len(buffer_views)
        buffer_views.append({"buffer": 0, "byteOffset": op, "byteLength": lp, "target": 34962})
        buffer_views.append({"buffer": 0, "byteOffset": on, "byteLength": ln, "target": 34962})
        buffer_views.append({"buffer": 0, "byteOffset": oc, "byteLength": lc, "target": 34962})
        buffer_views.append({"buffer": 0, "byteOffset": ou, "byteLength": lu, "target": 34962})
        buffer_views.append({"buffer": 0, "byteOffset": oi, "byteLength": li, "target": 34963})
        a0 = len(accessors)
        accessors.append({
            "bufferView": bv0, "componentType": 5126, "count": len(prim.pos), "type": "VEC3",
            "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)],
        })
        accessors.append({"bufferView": bv0 + 1, "componentType": 5126, "count": len(prim.pos), "type": "VEC3"})
        accessors.append({"bufferView": bv0 + 2, "componentType": 5126, "count": len(prim.pos), "type": "VEC4"})
        accessors.append({"bufferView": bv0 + 3, "componentType": 5126, "count": len(prim.pos), "type": "VEC2"})
        accessors.append({"bufferView": bv0 + 4, "componentType": 5125, "count": len(prim.idx), "type": "SCALAR"})
        meshes.append({
            "name": prim.name,
            "primitives": [{
                "attributes": {"POSITION": a0, "NORMAL": a0 + 1, "COLOR_0": a0 + 2, "TEXCOORD_0": a0 + 3},
                "indices": a0 + 4,
                "material": mat_index[prim.material],
            }],
        })
        nodes.append({"name": prim.name, "mesh": len(meshes) - 1})

    root = {"name": root_name, "children": list(range(len(nodes)))}
    nodes.append(root)
    gltf = {
        "asset": {"version": "2.0", "generator": "nk1-dashi-sewn"},
        "extensionsUsed": ["KHR_materials_unlit"],
        "scene": 0,
        "scenes": [{"name": root_name, "nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": [mats[n] for n in order],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(blob) % 4:
        blob.append(0)
    outb = bytearray()
    outb.extend(b"glTF")
    outb.extend(struct.pack("<I", 2))
    outb.extend(struct.pack("<I", 0))
    outb.extend(struct.pack("<I", len(js)))
    outb.extend(b"JSON")
    outb.extend(js)
    outb.extend(struct.pack("<I", len(blob)))
    outb.extend(b"BIN\x00")
    outb.extend(blob)
    struct.pack_into("<I", outb, 8, len(outb))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(outb)
    tris = sum(len(p.idx) // 3 for p in prims)
    xs, ys, zs = [], [], []
    for p in prims:
        for q in p.pos:
            xs.append(q[0])
            ys.append(q[1])
            zs.append(q[2])
    print(f"wrote {out} bytes={len(outb)} tris={tris}")
    print(f"bounds x[{min(xs):.2f},{max(xs):.2f}] y[{min(ys):.2f},{max(ys):.2f}] z[{min(zs):.2f},{max(zs):.2f}]")


def main():
    for kind, name in (("merchant", "DashiSewnMerchant"), ("armed", "DashiSewnArmed")):
        prims = build(kind)
        for prim in prims:
            if prim.name in ("Hull", "Stitches", "Fittings"):
                clip_above(prim, -0.012)
        pack_glb(prims, OUT_DIR / f"dashi_sewn_{kind}.glb", name)


if __name__ == "__main__":
    main()
