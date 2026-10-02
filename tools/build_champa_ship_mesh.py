#!/usr/bin/env python3
"""占城绑耳船 — 一条可转的三维船壳（glTF），战、商两个节点。

两端尖、平龙骨板、舷低。肋骨绑在板内侧的耳块上（绑耳）。舷缘外同一站位另有探出壳外的木耳，外脸是看得见的椰索十字，不是贴上去的金方，也不是沿舷通长的宋式板条。不是大食那种外缝索。
舵是船尾两侧的短舵桨，没有宋式尾轴舵，没有水密隔舱。
帆是竖着挂在桅上的一整块软布：横矩形，有上桁下桁，比高略宽，中间软鼓，正中一道竖缝。没有横竹。布面直立，不是平铺在甲板上的板。
战舟短、一舷约八桨、一张帆。货船更长、大舱口、两张帆、不设桨。
船首 +Z，水线 y=0，右舷 +X。一个 glb，运行时按航向转，不烘焙十六份。

用法：python3 tools/build_champa_ship_mesh.py
产物：assets/ships/champa.glb
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "ships" / "champa.glb"

TAR = (0.07, 0.045, 0.03, 1)
TAR_WET = (0.12, 0.08, 0.05, 1)
WOOD_DK = (0.34, 0.17, 0.08, 1)
WOOD = (0.50, 0.28, 0.13, 1)
WOOD_LT = (0.70, 0.50, 0.30, 1)
BRICK = (0.58, 0.20, 0.11, 1)
SALT = (0.78, 0.74, 0.66, 1)
SEAM = (0.05, 0.035, 0.025, 1)
DECK = (0.63, 0.46, 0.27, 1)
DECK_DK = (0.40, 0.26, 0.14, 1)
HOLD = (0.20, 0.12, 0.07, 1)
COIR = (0.68, 0.48, 0.22, 1)
JAR = (0.74, 0.48, 0.30, 1)
JAR_DK = (0.36, 0.20, 0.12, 1)
BALE = (0.48, 0.40, 0.28, 1)
ALOES = (0.26, 0.14, 0.08, 1)
SAIL_COL = (0.96, 0.90, 0.76, 1)


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
        self.pos.append((float(p[0]), float(p[1]), float(p[2])))
        self.nrm.append((float(n[0]), float(n[1]), float(n[2])))
        self.col.append((float(c[0]), float(c[1]), float(c[2]), float(c[3]) if len(c) > 3 else 1.0))
        self.uv.append((float(uv[0]), float(uv[1])))
        return len(self.pos) - 1

    def tri(self, a, b, c, ca, cb, cc, uva=(0.0, 0.0), uvb=(0.0, 0.0), uvc=(0.0, 0.0)):
        n = vcross(vsub(b, a), vsub(c, a))
        if vlen(n) < 1e-10:
            return
        n = vnorm(n)
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

    def quad_out(self, a, b, c, d, color, outward, uva=(0, 0), uvb=(0, 0), uvc=(0, 0), uvd=(0, 0)):
        n = vcross(vsub(b, a), vsub(c, a))
        if vlen(n) < 1e-10:
            return
        if vdot(n, outward) < 0.0:
            self.quad(a, d, c, b, color, uva, uvd, uvc, uvb)
        else:
            self.quad(a, b, c, d, color, uva, uvb, uvc, uvd)

    def quad_out_vc(self, a, b, c, d, ca, cb, cc, cd, outward):
        n = vcross(vsub(b, a), vsub(c, a))
        if vlen(n) < 1e-10:
            return
        if vdot(n, outward) < 0.0:
            self.quad_vc(a, d, c, b, ca, cd, cc, cb)
        else:
            self.quad_vc(a, b, c, d, ca, cb, cc, cd)

    def smooth(self, split_u=None):
        acc = {}
        keys = []
        for i, p in enumerate(self.pos):
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
            # 竖缝两侧不要平均成一块平板，折痕才吃得到光
            if split_u is not None:
                key = key + (0 if self.uv[i][0] < split_u else 1,)
            keys.append(key)
            acc[key] = vadd(acc.get(key, (0, 0, 0)), self.nrm[i])
        for i, key in enumerate(keys):
            self.nrm[i] = vnorm(acc[key])


def add_box(prim: Prim, center, size, color, yaw=0.0):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cy, sy = math.cos(yaw), math.sin(yaw)
    corners = []
    for x in (-hx, hx):
        for y in (-hy, hy):
            for z in (-hz, hz):
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


def add_taper(prim: Prim, p0, p1, r0, r1, color, n=8):
    axis = vsub(p1, p0)
    if vlen(axis) < 1e-5:
        return
    d = vnorm(axis)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.92 else (1.0, 0.0, 0.0)
    x = vnorm(vcross(d, up))
    y = vnorm(vcross(d, x))
    ring0, ring1 = [], []
    for i in range(n):
        a = i / n * math.tau
        o = vadd(vmul(x, math.cos(a)), vmul(y, math.sin(a)))
        ring0.append(vadd(p0, vmul(o, r0)))
        ring1.append(vadd(p1, vmul(o, r1)))
    for i in range(n):
        j = (i + 1) % n
        prim.quad(ring0[i], ring1[i], ring1[j], ring0[j], color)


def add_lathe(prim: Prim, origin, profile, color, n=10):
    rings = []
    for y, r in profile:
        ring = []
        for i in range(n):
            a = i / n * math.tau
            ring.append(vadd(origin, (math.cos(a) * r, y, math.sin(a) * r)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            prim.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], color)
    c0 = vadd(origin, (0, profile[0][0], 0))
    c1 = vadd(origin, (0, profile[-1][0], 0))
    for i in range(n):
        j = (i + 1) % n
        prim.tri(c0, rings[0][j], rings[0][i], color, color, color)
        prim.tri(c1, rings[-1][i], rings[-1][j], color, color, color)

def rope(prim, a, b, sag, r, color, n=5):
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


def add_blade(prim, root, tip, width, color, thick=0.012, width_axis=None):
    axis = vsub(tip, root)
    if vlen(axis) < 1e-4:
        return
    d = vnorm(axis)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.9 else (1.0, 0.0, 0.0)
    side = vnorm(width_axis) if width_axis is not None else vnorm(vcross(d, up))
    # 叶面：根窄、中宽、梢收，略有厚度
    def at(t, w, lift):
        return vadd(vadd(root, vmul(axis, t)), vadd(vmul(side, w), vmul(up, lift)))

    samples = [i / 12 for i in range(13)]
    widths = [math.sin(t * math.pi) ** 0.72 * (0.55 + 0.45 * math.sin(t * math.pi)) for t in samples]
    widths[0] = 0.16
    widths[-1] = 0.05
    pts_l, pts_r = [], []
    for t, w in zip(samples, widths):
        ww = width * w
        pts_l.append(at(t, ww, thick))
        pts_r.append(at(t, -ww, thick))
    for i in range(len(samples) - 1):
        prim.quad(pts_r[i], pts_l[i], pts_l[i + 1], pts_r[i + 1], color)
        # 背面
        bl = at(samples[i], widths[i] * width, -thick)
        br = at(samples[i], -widths[i] * width, -thick)
        bl2 = at(samples[i + 1], widths[i + 1] * width, -thick)
        br2 = at(samples[i + 1], -widths[i + 1] * width, -thick)
        prim.quad(bl, br, br2, bl2, mix(color, TAR, 0.25))


class Field:
    def __init__(self, L, beam, freeboard, bow_rise, stern_rise, mid_depth, tar=0.0):
        self.L = L
        self.half = L * 0.5
        self.beam = beam
        self.freeboard = freeboard
        self.bow_rise = bow_rise
        self.stern_rise = stern_rise
        self.mid_depth = mid_depth
        self.tar = tar
        self.n_s = 20

    def z(self, t):
        return self.half - t * self.L

    def beam_half(self, t):
        u = clamp(t, 0.0, 1.0)
        # 幂高一些，艏艉才尖，不会收成方驳
        s = math.sin(math.pi * u) ** 0.82
        s *= 1.0 + 0.04 * math.sin(math.pi * u) * (u - 0.40)
        return self.beam * max(0.012, s)

    def sheer_y(self, t):
        bow = self.bow_rise * math.exp(-((t - 0.0) / 0.16) ** 2)
        stern = self.stern_rise * math.exp(-((t - 1.0) / 0.145) ** 2)
        return self.freeboard + bow + stern

    def depth(self, t):
        body = math.sin(math.pi * clamp(t, 0.0, 1.0)) ** 0.58
        return 0.07 + self.mid_depth * body

    def keel_y(self, t):
        return self.sheer_y(t) - self.depth(t)

    def section(self, t):
        """平龙骨板，舭圆，上舷外撇。不留一段竖直舷墙，否则远看是盒子。"""
        bh = self.beam_half(t)
        keel_half = min(0.055, max(0.020, bh * 0.09))
        gy = self.sheer_y(t)
        ky = self.keel_y(t)
        pts = []
        n = self.n_s
        for i in range(n + 1):
            h = i / n
            # 舭在下半段就张开，上舷继续外撇，没有直壁
            s = math.sin(h * math.pi * 0.5) ** 0.40
            x = lerp(keel_half, bh * 0.86, s)
            if h > 0.48:
                flare = smoothstep(0.48, 1.0, h)
                x = lerp(x, bh * 1.02, flare)
            y = lerp(ky, gy, h ** 0.70)
            pts.append((x, y))
        return pts

    def sample(self, t, h, side, inset=0.0):
        ring = self.section(t)
        n = len(ring) - 1
        f = clamp(h, 0.0, 1.0) * n
        i = min(n - 1, int(f))
        a = f - i
        x = lerp(ring[i][0], ring[i + 1][0], a)
        y = lerp(ring[i][1], ring[i + 1][1], a)
        x = max(0.0, x - inset)
        return (side * x, y, self.z(t))
SPECS = {
    "Merchant": dict(
        L=8.8, beam=1.26, freeboard=0.64, bow_rise=0.50, stern_rise=0.68,
        mid_depth=0.72, tar=0.0, oars=0, sails=2, hatch=True, shields=False,
        role="merchant",
    ),
    "War": dict(
        L=6.15, beam=0.70, freeboard=0.42, bow_rise=0.32, stern_rise=0.44,
        mid_depth=0.50, tar=0.05, oars=8, sails=1, hatch=False, shields=False,
        role="war",
    ),
}


def build_variant(name, sp):
    hull = Prim("Hull", "Wood")
    fit = Prim("Fit", "Wood")
    sail = Prim("Sails", "Sail")
    f = Field(sp["L"], sp["beam"], sp["freeboard"], sp["bow_rise"], sp["stern_rise"], sp["mid_depth"], sp["tar"])
    n_t = 64
    n_s = f.n_s

    def P(i, j, side, inset=0.0):
        t = i / (n_t - 1)
        h = j / n_s
        return f.sample(t, h, side, inset)

    # 舷侧列板。沿吃水均分，每道都窄，板缝凹进并且整条是深色。
    # 以前靠顶点色在七道宽条上抹渐变，18° 近景会糊成三四条粗带。
    # 外板仍贴原来的截面，舷弧、吃水和两端尖的轮廓不动。
    N_STR = 16
    SEAM_FRAC = 0.50
    Y_EXP = 0.70  # 与 section() 里 y = h**0.70 成对，侧视每道板才一样窄
    UV_PLANK = 0.20
    UV_SEAM = 0.85
    SEAM_COL = (0.012, 0.008, 0.006, 1.0)

    def h_of_s(s):
        return clamp(s, 0.0, 1.0) ** (1.0 / Y_EXP)

    def skin(t, s, side, recessed):
        h = h_of_s(s)
        outer = f.sample(t, h, side, 0.0)
        if not recessed:
            return outer
        ins = min(0.045, abs(outer[0]) * 0.55)
        return f.sample(t, h, side, ins)

    def plank_col(pidx, y):
        # 板面要明显亮过缝。缝若只比湿板暗一档，18° 近景仍是一条深色宽带。
        if y < 0.0:
            base = (0.30, 0.17, 0.09, 1.0)
        else:
            base = (0.58, 0.36, 0.18, 1.0)
            base = mix(base, WOOD_LT, 0.05 + 0.10 * hsh(pidx * 13.7 + 2.0))
        if pidx % 2 == 0:
            base = mix(base, WOOD_DK, 0.10)
        if pidx == N_STR - 1:
            base = mix(WOOD_DK, BRICK, 0.30)
        if f.tar:
            base = mix(base, TAR, f.tar)
        j = 0.96 + 0.06 * hsh(pidx * 5.1 + 8.0)
        return tuple(clamp(c * j, 0.0, 1.0) if ii < 3 else c for ii, c in enumerate(base))

    def emit(a, b, c, d, col, outward, u):
        hull.quad_out(
            a, b, c, d, col, outward,
            (u, 0.0), (u, 0.0), (u, 1.0), (u, 1.0),
        )

    for i in range(n_t - 1):
        t0 = i / (n_t - 1)
        t1 = (i + 1) / (n_t - 1)
        for pidx in range(N_STR):
            s0 = pidx / N_STR
            s1 = (pidx + 1) / N_STR
            sm = s0 + SEAM_FRAC * (s1 - s0)
            for side in (1, -1):
                outward = (side * 1.0, 0.12, 0.0)
                a = skin(t0, s0, side, True)
                b = skin(t1, s0, side, True)
                c = skin(t1, sm, side, True)
                d = skin(t0, sm, side, True)
                emit(a, b, c, d, SEAM_COL, outward, UV_SEAM)
                a2 = skin(t0, sm, side, False)
                b2 = skin(t1, sm, side, False)
                # 缝上沿的台阶朝下，近景里是一条暗线
                emit(a, b, b2, a2, SEAM_COL, (0.0, -1.0, 0.0), UV_SEAM)
                if pidx > 0:
                    ao = skin(t0, s0, side, False)
                    bo = skin(t1, s0, side, False)
                    emit(ao, bo, b, a, SEAM_COL, (0.0, 1.0, 0.0), UV_SEAM)
                c2 = skin(t1, s1, side, False)
                d2 = skin(t0, s1, side, False)
                ymid = (a2[1] + b2[1] + c2[1] + d2[1]) * 0.25
                emit(a2, b2, c2, d2, plank_col(pidx, ymid), outward, UV_PLANK)

    # 内壳也是列板。18° 近景会从舷缘看进敞口，光滑内壁会被看成一条宽深带。
    # 不封隔舱，只沿舷铺窄板和深缝。
    def skin_in(t, s, side, recessed):
        h = h_of_s(s)
        outer = f.sample(t, h, side, 0.0)
        base_ins = min(0.050, abs(outer[0]) * 0.20)
        extra = min(0.028, abs(outer[0]) * 0.10) if recessed else 0.0
        return f.sample(t, h, side, base_ins + extra)

    def inner_col(pidx):
        base = (0.46, 0.27, 0.13, 1.0)
        if pidx % 2 == 0:
            base = mix(base, WOOD_DK, 0.16)
        j = 0.96 + 0.05 * hsh(pidx * 3.3 + 1.1)
        return tuple(clamp(c * j, 0.0, 1.0) if ii < 3 else c for ii, c in enumerate(base))

    for i in range(4, n_t - 5):
        t0 = i / (n_t - 1)
        t1 = (i + 1) / (n_t - 1)
        for pidx in range(N_STR):
            s0 = pidx / N_STR
            s1 = (pidx + 1) / N_STR
            sm = s0 + SEAM_FRAC * (s1 - s0)
            for side in (1, -1):
                outward = (-side * 1.0, 0.05, 0.0)
                a = skin_in(t0, s0, side, True)
                b = skin_in(t1, s0, side, True)
                c = skin_in(t1, sm, side, True)
                d = skin_in(t0, sm, side, True)
                emit(a, b, c, d, SEAM_COL, outward, UV_SEAM)
                a2 = skin_in(t0, sm, side, False)
                b2 = skin_in(t1, sm, side, False)
                emit(a, b, b2, a2, SEAM_COL, (0.0, -1.0, 0.0), UV_SEAM)
                c2 = skin_in(t1, s1, side, False)
                d2 = skin_in(t0, s1, side, False)
                emit(a2, b2, c2, d2, inner_col(pidx), outward, UV_PLANK)

    # 艏艉柱：往外耙，两端尖
    def end_post(t, z_rake, up_extra):
        ring = f.section(t)
        z = f.z(t)
        foot = (0.0, ring[0][1] + 0.02, z + z_rake * 0.25)
        head = (0.0, ring[-1][1] + up_extra, z + z_rake)
        add_taper(fit, foot, head, 0.055, 0.028, mix(WOOD_DK, BRICK, 0.25), 8)
        # 艏艉封板跟列板同一套边界，避免板缝在柱边错开
        bounds = [0.0]
        for pidx in range(N_STR):
            s0 = pidx / N_STR
            s1 = (pidx + 1) / N_STR
            bounds.append(s0 + SEAM_FRAC * (s1 - s0))
            bounds.append(s1)
        for k in range(len(bounds) - 1):
            sa, sb = bounds[k], bounds[k + 1]
            recessed = any(abs(sa - (pidx / N_STR)) < 1e-6 for pidx in range(N_STR))
            pidx = min(N_STR - 1, int(sa * N_STR + 1e-6))
            for side in (1, -1):
                a = skin(t, sa, side, recessed)
                b = skin(t, sb, side, recessed)
                fa = (0.0, lerp(foot[1], head[1], sa), lerp(foot[2], head[2], sa))
                fb = (0.0, lerp(foot[1], head[1], sb), lerp(foot[2], head[2], sb))
                col = SEAM_COL if recessed else plank_col(pidx, (a[1] + b[1]) * 0.5)
                outward = (side, 0.2, 1.0 if t < 0.5 else -1.0)
                emit(a, fa, fb, b, col, outward, UV_SEAM if recessed else UV_PLANK)

    end_post(0.0, 0.20, 0.10)
    end_post(1.0, -0.22, 0.14)

    # 龙骨板：平、窄，不是宋船深尖底
    for i in range(3, n_t - 4):
        t0 = i / (n_t - 1)
        t1 = (i + 1) / (n_t - 1)
        def keel_pt(t, side, lift):
            half = max(abs(f.sample(t, 0.0, 1)[0]) + 0.02, 0.04)
            return (side * half, f.keel_y(t) - 0.012 + lift, f.z(t))
        a = keel_pt(t0, -1, 0)
        b = keel_pt(t1, -1, 0)
        c = keel_pt(t1, 1, 0)
        d = keel_pt(t0, 1, 0)
        col = mix(TAR, WOOD_DK, 0.25)
        hull.quad_out(a, b, c, d, col, (0, -1, 0))
        # 侧面一点厚度
        a2 = keel_pt(t0, -1, 0.025)
        b2 = keel_pt(t1, -1, 0.025)
        hull.quad_out(a, a2, b2, b, col, (-1, 0, 0))
        c2 = keel_pt(t1, 1, 0.025)
        d2 = keel_pt(t0, 1, 0.025)
        hull.quad_out(d, c, c2, d2, col, (1, 0, 0))

    # 板和缝的 uv 分开，平滑时不要把缝的法线抹进板里
    hull.smooth(split_u=0.5)

    # 甲板 / 舱底
    hatch = None
    if sp["hatch"]:
        hatch = (0.32, 0.72, 0.62)  # t0, t1, half-width fraction of local beam
    deck_lo, deck_hi = (0.08, 0.93) if sp["role"] == "merchant" else (0.08, 0.20)
    # 战舟只留艏部小平台；舯部敞开。艉另有舵手踏板。
    spans = [(deck_lo, deck_hi)]
    if sp["role"] == "war":
        spans = [(0.06, 0.18), (0.80, 0.94)]

    def deck_strip(t0, t1, gap=False):
        steps = max(2, int(abs(t1 - t0) * 28))
        across = 8
        for iv in range(steps):
            if gap and iv % 3 == 1:
                continue
            ta = lerp(t0, t1, iv / steps)
            tb = lerp(t0, t1, (iv + 1) / steps)
            for iu in range(across):
                def xp(t, iu_, edge):
                    bh = f.beam_half(t) * 0.90
                    return lerp(-bh, bh, (iu_ + edge) / across)
                ya = f.sheer_y(ta) - 0.035
                yb = f.sheer_y(tb) - 0.035
                a = (xp(ta, iu, 0), ya, f.z(ta))
                b = (xp(tb, iu, 0), yb, f.z(tb))
                c = (xp(tb, iu, 1), yb, f.z(tb))
                d = (xp(ta, iu, 1), ya, f.z(ta))
                if hatch:
                    tm = (ta + tb) * 0.5
                    xm = (a[0] + c[0]) * 0.5
                    limit = f.beam_half(tm) * hatch[2]
                    if hatch[0] < tm < hatch[1] and abs(xm) < limit:
                        continue
                col = DECK if iu % 2 == 0 else mix(DECK, DECK_DK, 0.18)
                if iu % 2 == 1:
                    col = mix(col, SEAM, 0.15)
                fit.quad_out(a, d, c, b, col, (0, 1, 0))

    for a, b in spans:
        deck_strip(a, b, gap=False)
    if sp["role"] == "war":
        # 敞舱底的疏板，能看见肋骨，不是隔舱
        deck_y_floor = 0.02
        # 临时：用 sample 的舱底高度附近铺疏板
        steps = 16
        for iv in range(steps):
            if iv % 2 == 1:
                continue
            ta = lerp(0.20, 0.76, iv / steps)
            tb = lerp(0.20, 0.76, (iv + 0.55) / steps)
            bh0 = abs(f.sample(ta, 0.22, 1)[0]) * 0.72
            bh1 = abs(f.sample(tb, 0.22, 1)[0]) * 0.72
            y = max(0.02, f.keel_y((ta + tb) * 0.5) + 0.10)
            a = (-bh0, y, f.z(ta))
            b = (-bh1, y, f.z(tb))
            c = (bh1, y, f.z(tb))
            d = (bh0, y, f.z(ta))
            fit.quad_out(a, d, c, b, mix(DECK_DK, HOLD, 0.35), (0, 1, 0))

    if hatch:
        t0, t1, frac = hatch
        # 舱口围板
        def coaming_ring(t, side_sign_only=False):
            return
        y_top = f.sheer_y(0.5) - 0.01
        y_bot = y_top - 0.09
        # 四条围板，沿舱口
        def beam_at(t):
            return f.beam_half(t) * frac
        # 沿纵向两条
        for side in (1, -1):
            a = (side * beam_at(t0), y_bot, f.z(t0))
            b = (side * beam_at(t1), y_bot, f.z(t1))
            c = (side * beam_at(t1), y_top, f.z(t1))
            d = (side * beam_at(t0), y_top, f.z(t0))
            fit.quad_out(a, b, c, d, WOOD, (side, 0, 0))
            fit.quad_out(d, c, b, a, mix(WOOD, HOLD, 0.4), (-side, 0, 0))
        for t, zdir in ((t0, 1), (t1, -1)):
            x0 = beam_at(t)
            yb, yt = y_bot, y_top
            a = (-x0, yb, f.z(t))
            b = (x0, yb, f.z(t))
            c = (x0, yt, f.z(t))
            d = (-x0, yt, f.z(t))
            fit.quad_out(a, b, c, d, WOOD, (0, 0, zdir))
        # 舱底
        floor_y = 0.03
        x0 = abs(f.sample(t0, 0.18, 1)[0]) * 0.8
        x1 = abs(f.sample(t1, 0.18, 1)[0]) * 0.8
        a = (-x0, floor_y, f.z(t0))
        b = (-x1, floor_y, f.z(t1))
        c = (x1, floor_y, f.z(t1))
        d = (x0, floor_y, f.z(t0))
        fit.quad_out(a, d, c, b, HOLD, (0, 1, 0))
        # 一道活动横梁，不是隔舱壁
        for tt in (0.52,):
            x = beam_at(tt) * 0.98
            y = y_top + 0.02
            add_box(fit, (0, y, f.z(tt)), (x * 2.0, 0.045, 0.06), mix(WOOD_DK, BRICK, 0.15))
        # 货：陶罐、沉香段、布包。都在舱里。
        cz = f.z((t0 + t1) * 0.5)
        jar_h = 0.48
        positions = [(-0.28, f.z(0.40)), (0.30, f.z(0.42)), (-0.22, f.z(0.62)), (0.26, f.z(0.60)), (0.0, f.z(0.52))]
        for ix, (x, z) in enumerate(positions):
            r = 0.16 if ix < 4 else 0.12
            col = JAR if ix % 2 == 0 else mix(JAR, JAR_DK, 0.35)
            add_lathe(
                fit, (x, floor_y, z),
                [(0.0, r * 0.55), (0.04, r * 0.72), (0.12, r), (0.20, r * 0.92), (0.25, r * 0.42), (jar_h, r * 0.48)],
                col, n=8,
            )
        # 沉香：一捆深色短木
        for k, dz in enumerate((-0.18, 0.0, 0.16)):
            add_box(fit, (0.0, floor_y + 0.05, cz + dz), (0.46, 0.07, 0.09), mix(ALOES, WOOD_DK, 0.15 * k))
        add_box(fit, (-0.34, floor_y + 0.07, cz + 0.05), (0.16, 0.10, 0.22), BALE)
        add_box(fit, (0.36, floor_y + 0.06, cz - 0.08), (0.14, 0.09, 0.18), mix(BALE, BRICK, 0.2))

    # 绑耳 + 肋骨。耳在板内侧，索只绑在肋骨站位，不沿板缝通缝。
    # 斜视整船时，耳必须落在敞口里（货舱口 / 战舟敞舱），不能埋在舷甲板下面。
    rib_ts = [0.22, 0.34, 0.46, 0.58, 0.70]
    if sp["role"] == "merchant":
        rib_ts = [0.18, 0.28, 0.38, 0.48, 0.58, 0.68, 0.78]
    # 舱内耳是木头，不是浅金方块
    lug_col = (0.62, 0.40, 0.20, 1)
    coir = (0.72, 0.50, 0.26, 1)
    open_lo, open_hi = (0.22, 0.74) if sp["role"] == "war" else (0.34, 0.70)

    def add_visible_lug(t, side, drop, reach):
        """浅色耳块从内舷伸进敞口，椰索十字绑到肋骨上。整只耳落在能看见的开口里。"""
        bh = f.beam_half(t)
        y = f.sheer_y(t) - drop
        best, bestd = None, 1e9
        for j in range(n_s + 1):
            q = f.sample(t, j / n_s, side, 0.04)
            d = abs(q[1] - y)
            if d < bestd:
                bestd, best = d, q
        wall_x = best[0]
        # 货舱口只开到舷宽的 0.62。耳从开口边缘伸进去，不埋在舷甲板下。
        if sp["role"] == "merchant":
            lip = side * bh * 0.58
            if abs(wall_x) > abs(lip):
                x_out = lip
            else:
                x_out = wall_x * 0.92
        else:
            x_out = wall_x * 0.90
        x_in = side * bh * reach
        if abs(x_in) > abs(x_out) - 0.10:
            x_in = x_out - side * 0.18
        span = abs(x_out - x_in)
        if span < 0.08:
            return
        z = f.z(t)
        # 让开战舟桨座横梁，耳不要被梁盖住
        if sp["role"] == "war":
            for tt in (0.30, 0.46, 0.62):
                if abs(t - tt) < 0.035:
                    z += 0.14
                    break
        cx = (x_out + x_in) * 0.5
        add_box(fit, (cx, y, z), (span, 0.11, 0.18), lug_col)
        add_box(fit, (x_out - side * 0.02, y, z), (0.08, 0.14, 0.22), mix(lug_col, WOOD, 0.25))
        rib_x = x_in - side * 0.04
        add_cyl(fit, (rib_x, y - 0.18, z), (rib_x, y + 0.12, z), 0.028, WOOD_DK, 6, caps=False)
        rope(fit, (x_out, y + 0.05, z - 0.08), (rib_x, y - 0.05, z + 0.07), 0.01, 0.020, coir, n=4)
        rope(fit, (x_out, y + 0.05, z + 0.08), (rib_x, y - 0.05, z - 0.07), 0.01, 0.020, coir, n=4)
        rope(fit, (cx, y + 0.06, z - 0.09), (cx, y + 0.06, z + 0.09), 0.02, 0.015, mix(coir, WOOD_DK, 0.15), n=3)

    # 外脸是端面木色。顶面明显更浅，近景才分得开顶和端面。索是椰绳，不要亮成金贴纸。
    lug_end = (0.34, 0.17, 0.07, 1)
    lug_side = (0.48, 0.28, 0.12, 1)
    lug_top = (0.86, 0.68, 0.40, 1)
    lug_bot = (0.26, 0.14, 0.06, 1)
    lug_rope = (0.70, 0.48, 0.22, 1)
    lug_rope_dk = (0.32, 0.16, 0.07, 1)

    def add_sheer_lug(t, side):
        """舷缘下的短绑耳。

        水平探出量短于端面的高和长，所以不是梁。
        一根舷缘的直径在 18° 近景里只剩大约两个像素，顶面看不见，会读成贴在壳上的方板。
        探出取几倍舷缘厚，仍短于端面，顶面才是一块浅色矩形。
        外脸椰索十字，四角留木色。法线水平向外。
        """
        gunwale_r = 0.030
        if sp["role"] == "merchant":
            tall, along_len, prot, rw = 0.36, 0.44, 0.32, 0.052
        else:
            tall, along_len, prot, rw = 0.28, 0.34, 0.22, 0.042
        fore = f.sample(max(0.04, t - 0.015), 0.92, side, 0.0)
        aft = f.sample(min(0.96, t + 0.015), 0.92, side, 0.0)
        along = vnorm(vsub(aft, fore))
        outward = (along[2], 0.0, -along[0])
        if vlen(outward) < 1e-6:
            outward = (float(side), 0.0, 0.0)
        else:
            outward = vnorm(outward)
        if outward[0] * side < 0.0:
            outward = vmul(outward, -1.0)
        up = (0.0, 1.0, 0.0)
        # 与舷缘纵桁同一套偏移：中心在壳外 0.016、上移 0.016，半径 0.030。
        gun = f.sample(t, 1.0, side, -0.016)
        gun = (gun[0], gun[1] + 0.016, gun[2])
        gun_outer = vadd(gun, vmul(outward, gunwale_r))
        # 顶面贴在纵桁下沿，不被桁盖住，也不压到甲板上。
        top_y = gun[1] - gunwale_r - 0.010
        bury = 0.045
        hx = (prot + bury) * 0.5
        hy = tall * 0.5
        hz = along_len * 0.5
        center = vadd(gun_outer, vmul(outward, (prot - bury) * 0.5))
        center = (center[0], top_y - hy, center[2])

        def corner(sx, sy, sz):
            return vadd(center, vadd(vadd(vmul(outward, sx * hx), vmul(up, sy * hy)), vmul(along, sz * hz)))

        c = corner
        fit.quad_out(c(1, -1, -1), c(1, -1, 1), c(1, 1, 1), c(1, 1, -1), lug_end, outward)
        fit.quad_out(c(-1, -1, 1), c(-1, -1, -1), c(-1, 1, -1), c(-1, 1, 1), lug_side, vmul(outward, -1.0))
        fit.quad_out(c(-1, 1, -1), c(1, 1, -1), c(1, 1, 1), c(-1, 1, 1), lug_top, up)
        fit.quad_out(c(-1, -1, 1), c(1, -1, 1), c(1, -1, -1), c(-1, -1, -1), lug_bot, (0.0, -1.0, 0.0))
        fit.quad_out(c(1, -1, 1), c(-1, -1, 1), c(-1, 1, 1), c(1, 1, 1), lug_side, along)
        fit.quad_out(c(-1, -1, -1), c(1, -1, -1), c(1, 1, -1), c(-1, 1, -1), lug_side, vmul(along, -1.0))

        # 十字只画在探出的外脸上。臂长占端面大约四分之三，四角留木色。
        face = vadd(center, vmul(outward, hx + 0.004))
        ha = along_len * 0.36
        hu = tall * 0.36

        def crn(sa, su):
            return vadd(face, vadd(vmul(along, sa * ha), vmul(up, su * hu)))

        def ribbon(a, b, width, color, lift):
            d = vsub(b, a)
            if vlen(d) < 1e-5:
                return
            d = vnorm(d)
            waxis = vnorm(vcross(outward, d))
            hw = width * 0.5
            a0 = vadd(vadd(a, vmul(waxis, -hw)), vmul(outward, lift))
            a1 = vadd(vadd(a, vmul(waxis, hw)), vmul(outward, lift))
            b0 = vadd(vadd(b, vmul(waxis, -hw)), vmul(outward, lift))
            b1 = vadd(vadd(b, vmul(waxis, hw)), vmul(outward, lift))
            fit.quad_out(a0, b0, b1, a1, color, outward)
            back = vmul(outward, -0.008)
            fit.quad_out(
                vadd(a1, back), vadd(b1, back), vadd(b0, back), vadd(a0, back),
                mix(color, WOOD_DK, 0.45), vmul(outward, -1.0),
            )
            fit.quad_out(a0, a1, vadd(a1, back), vadd(a0, back), color, waxis)
            fit.quad_out(b1, b0, vadd(b0, back), vadd(b1, back), color, vmul(waxis, -1.0))

        def cross(width, color, lift):
            ribbon(crn(-1.0, -1.0), crn(1.0, 1.0), width, color, lift)
            ribbon(crn(-1.0, 1.0), crn(1.0, -1.0), width, color, lift)

        cross(rw * 1.45, lug_rope_dk, 0.006)
        cross(rw, lug_rope, 0.014)
        knot = vadd(face, vmul(outward, 0.012))
        add_cyl(fit, knot, vadd(knot, vmul(outward, 0.016)), rw * 0.62, lug_rope, 6, caps=True)

    for ti, t in enumerate(rib_ts):
        for side in (1, -1):
            prev = None
            for j in range(0, n_s + 1, 2):
                p = f.sample(t, j / n_s, side, 0.08)
                if prev is not None:
                    add_cyl(fit, prev, p, 0.022, mix(WOOD_DK, coir, 0.15), 6, caps=False)
                prev = p
            if open_lo <= t <= open_hi:
                if sp["role"] == "merchant":
                    add_visible_lug(t, side, 0.18, 0.34)
                    add_visible_lug(t, side, 0.36, 0.40)
                else:
                    add_visible_lug(t, side, 0.20, 0.36)
            # 舷外同一肋骨一只探出的绑耳。木块伸出壳，外脸椰索十字。不是金方贴纸，也不是通长板条。
            add_sheer_lug(t, side)
        # 船底横材，把两舷肋骨连上，仍是一帧不是一堵壁
        pl = f.sample(t, 0.08, -1, 0.06)
        pr = f.sample(t, 0.08, 1, 0.06)
        pl = (pl[0], pl[1] + 0.03, pl[2])
        pr = (pr[0], pr[1] + 0.03, pr[2])
        add_cyl(fit, pl, pr, 0.026, WOOD_DK, 6, caps=False)

    # 舷缘纵桁
    for side in (1, -1):
        pts = []
        for i in range(0, n_t, 2):
            t = i / (n_t - 1)
            p = f.sample(t, 1.0, side, -0.016)
            p = (p[0], p[1] + 0.016, p[2])
            pts.append(p)
        for i in range(len(pts) - 1):
            add_cyl(fit, pts[i], pts[i + 1], 0.030, mix(WOOD_DK, BRICK, 0.40), 7, caps=False)

    # 战舟桨座横梁，敞舱里隔开肋骨，不是隔舱壁
    if sp["role"] == "war":
        for t in (0.30, 0.46, 0.62):
            y = f.sheer_y(t) - 0.06
            x = f.beam_half(t) * 0.78
            add_box(fit, (0.0, y, f.z(t)), (x * 2.0, 0.045, 0.07), mix(DECK, WOOD_DK, 0.25))

    # 桨：只有战舟。商船是货壳，不把桨伸出去跟战舟搅在一起。侧舵另算。
    if sp["oars"] > 0:
        n_oars = sp["oars"]
        oar_ts = [lerp(0.24, 0.70, i / (n_oars - 1)) for i in range(n_oars)]
        for i, t in enumerate(oar_ts):
            for side in (1, -1):
                pin = f.sample(t, 1.0, side, -0.012)
                pin = (pin[0], pin[1] + 0.015, pin[2])
                add_cyl(fit, (pin[0], pin[1] - 0.03, pin[2]), (pin[0], pin[1] + 0.07, pin[2]), 0.014, WOOD_DK, 5, caps=False)
                # 一列桨库：都向后、略向下，角度差不多。左右只错半拍，不往上、不往外炸开。
                raised = ((i + (0 if side > 0 else 1)) % 2 == 0)
                lat = 0.36 if raised else 0.40
                aft = 0.34 if raised else 0.40
                tip_y = pin[1] - (0.10 if raised else 0.16)
                tip = (pin[0] + side * lat, tip_y, pin[2] - aft)
                blade_root = (
                    lerp(pin[0], tip[0], 0.72),
                    lerp(pin[1], tip[1], 0.72),
                    lerp(pin[2], tip[2], 0.72),
                )
                grip = (pin[0] - side * 0.10, pin[1] + 0.06, pin[2] + 0.02)
                neck = (pin[0] + side * 0.04, pin[1] + 0.01, pin[2] - 0.02)
                loom_c = WOOD if raised else mix(WOOD, TAR_WET, 0.30)
                blade_c = mix(WOOD_LT, SALT, 0.30) if raised else mix(WOOD_LT, TAR_WET, 0.22)
                add_taper(fit, grip, neck, 0.016, 0.018, loom_c, 5)
                add_taper(fit, neck, blade_root, 0.016, 0.012, mix(loom_c, WOOD_LT, 0.2), 5)
                shaft = vnorm(vsub(tip, blade_root))
                horiz = vnorm(vcross(shaft, (0.0, 1.0, 0.0)))
                add_blade(fit, blade_root, tip, 0.090, blade_c, thick=0.010, width_axis=vnorm(vadd(vmul(horiz, 0.88), (0.0, 0.40, 0.0))))

    # 侧舵桨：船尾两舷各一支，叶面短，不在中线。
    add_quarter_rudders(fit, f, sp["role"])

    # 帆：横矩形软帆。桁几乎平，布比高宽。
    # 布面直立：drop 是帆高，必须明显大于厚度，脚边留在舷缘之上。
    if sp["sails"] == 1:
        add_lug_sail(fit, sail, f, 0.42, yard=2.70, drop=1.95, height=2.42, camber=0.40, role=sp["role"])
    else:
        add_lug_sail(fit, sail, f, 0.24, yard=2.40, drop=1.72, height=2.18, camber=0.64, role=sp["role"])
        add_lug_sail(fit, sail, f, 0.60, yard=2.95, drop=2.10, height=2.62, camber=0.78, role=sp["role"])

    # 货帆的竖缝要留成折，不能跟整面布平滑成一块板
    sail.smooth(0.5 if sp["role"] == "merchant" else None)
    return [hull, fit, sail]


SAIL_DEBUG = []


def add_quarter_rudders(fit, f: Field, role):
    """船尾两舷各一支舵桨。轴长、叶短，斜着伸出后四分之一，不当成船最大的那一块。"""
    t = 0.88 if role == "merchant" else 0.84
    # 从舷缘向下、向后、向外。叶面只占外端一小段。
    if role == "merchant":
        length = 1.28
        blade_len = 0.36
        blade_w = 0.13
        out = 0.42
        down = 0.78
        aft = 0.48
    else:
        length = 1.05
        blade_len = 0.30
        blade_w = 0.11
        out = 0.46
        down = 0.76
        aft = 0.46
    for side in (1, -1):
        gun = f.sample(t, 1.0, side, -0.01)
        gun = (gun[0], gun[1] + 0.02, gun[2])
        direction = vnorm((side * out, -down, -aft))
        tip = vadd(gun, vmul(direction, length))
        # 叶面贴着水面，不往深里扎成一把巨桨
        if tip[1] < -0.12:
            tip = (tip[0], -0.12, tip[2])
            direction = vnorm(vsub(tip, gun))
        loom = (gun[0] - side * 0.08, gun[1] + 0.28, gun[2] + 0.04)
        blade_root = vadd(tip, vmul(direction, -blade_len))
        add_taper(fit, loom, gun, 0.026, 0.032, mix(WOOD, BRICK, 0.15), 6)
        add_taper(fit, gun, blade_root, 0.028, 0.018, WOOD_DK, 6)
        # 叶面朝向斜后方，艉舷四分之三才能两片都看见，不让远舷那片剩一条棱
        preferred = vnorm((side * 0.45, 0.35, -0.82))
        face_n = vnorm(vsub(preferred, vmul(direction, vdot(preferred, direction))))
        width_axis = vnorm(vcross(face_n, direction))
        add_blade(
            fit, blade_root, tip, blade_w,
            mix(WOOD_LT, SALT, 0.22), thick=0.012,
            width_axis=width_axis,
        )
        add_cyl(fit, (gun[0], gun[1] - 0.03, gun[2]), (gun[0], gun[1] + 0.10, gun[2]), 0.022, mix(WOOD_DK, BRICK, 0.4), 6)
        rope(fit, loom, (gun[0] - side * 0.01, gun[1] + 0.06, gun[2]), 0.03, 0.010, (0.72, 0.52, 0.24, 1), n=3)
        tiller = (gun[0] - side * 0.28, gun[1] + 0.10, gun[2] + 0.02)
        add_taper(fit, loom, tiller, 0.018, 0.012, mix(WOOD, BRICK, 0.25), 5)


def add_lug_sail(fit, sail, f: Field, t, yard, drop, height, camber, role="merchant"):
    """直立的横矩形软帆。一整块布挂在桅上，上桁下桁几乎水平，布面朝舷侧。
    比高略宽，中间软鼓，正中一道竖缝，没有横竹，四角不收成尖。不是平铺在甲板上方的薄板。"""
    tilt = math.radians(6.0)
    sheet = math.radians(8.0)
    horiz = (math.sin(sheet), 0.0, math.cos(sheet))
    yard_dir = vnorm((horiz[0] * math.cos(tilt), -math.sin(tilt), horiz[2] * math.cos(tilt)))
    # 帆面法线朝右舷，斜俯的艉舷机能看见整幅布，而不是一条棱
    normal = vnorm(vcross((0.0, 1.0, 0.0), yard_dir))
    if normal[0] < 0.0:
        normal = vmul(normal, -1.0)
    down = vnorm(vcross(normal, yard_dir))
    if down[1] > 0.0:
        down = vmul(down, -1.0)

    base = (0.0, f.sheer_y(t) + 0.02, f.z(t))
    head = (base[0] + 0.02, base[1] + height, base[2] + height * 0.05)
    add_taper(fit, base, head, 0.050, 0.026, mix(WOOD_DK, WOOD, 0.35), 7)
    add_lathe(fit, (head[0], head[1] - 0.01, head[2]), [(0, 0.035), (0.05, 0.016)], WOOD, n=6)

    attach = vadd(head, (0.0, -height * 0.04, 0.0))
    # 斜桁：桅绑在距前端约三分之一处，前段短、后段长
    fwd = vadd(attach, vmul(yard_dir, yard * 0.34))
    aft = vadd(attach, vmul(yard_dir, -yard * 0.66))
    add_taper(fit, aft, fwd, 0.034, 0.022, mix(WOOD_DK, BRICK, 0.22), 6)
    add_cyl(fit, attach, vadd(attach, vmul(normal, 0.07)), 0.022, COIR, 5, caps=False)

    # 下桁与上桁平行，把布绷成矩形。晚帆没有这根下桁。
    foot_fwd = vadd(fwd, vmul(down, drop))
    foot_aft = vadd(aft, vmul(down, drop))
    add_taper(fit, foot_aft, foot_fwd, 0.026, 0.018, mix(WOOD, WOOD_DK, 0.35), 6)
    SAIL_DEBUG.append((role, t, fwd, aft, foot_fwd, foot_aft))

    # 一整块布。中间软鼓，正中收回成一道竖缝。没有横竹，也不分成好几幅。
    nu, nv = 32, 18
    grid = []
    for iu in range(nu + 1):
        col = []
        u = iu / nu
        head_p = (
            lerp(fwd[0], aft[0], u),
            lerp(fwd[1], aft[1], u),
            lerp(fwd[2], aft[2], u),
        )
        # 下缘只微微下垂，四角仍落在下桁上，不会收成一个尖
        roach = math.sin(math.pi * u) * drop * 0.04
        foot_p = vadd(head_p, vmul(down, drop + roach))
        for iv in range(nv + 1):
            v = iv / nv
            p = (
                lerp(head_p[0], foot_p[0], v),
                lerp(head_p[1], foot_p[1], v),
                lerp(head_p[2], foot_p[2], v),
            )
            belly = math.sin(math.pi * u) ** 0.82 * math.sin(math.pi * v) ** 0.78
            # 竖缝是布上的一道折，不是第二张帆，也不是横竹。
            # 货帆在 18° 近景里更小，折要更深、更暗，才不会看成一块平板。
            seam_w = 0.040 if role == "merchant" else 0.028
            seam_pull = 0.92 if role == "merchant" else 0.62
            tuck = 0.055 if role == "merchant" else 0.0
            seam = math.exp(-((u - 0.5) / seam_w) ** 2)
            edge = smoothstep(0.10, 0.0, min(u, 1.0 - u))
            puff = camber * belly * (1.0 - seam_pull * seam) - edge * 0.02 - tuck * seam
            p = vadd(p, vmul(normal, puff))
            # 鼓处亮、缝上暗。着色器再把缝收成一条线。战舟维持原来的明暗。
            if role == "merchant":
                shade = 0.36 + 0.64 * belly
                shade *= 1.0 - 0.82 * seam
            else:
                shade = 0.50 + 0.50 * belly
                shade *= 1.0 - 0.48 * seam
            shade *= 0.93 + 0.07 * (1.0 - v)
            col.append((p, shade, u, v))
        grid.append(col)
    face_dot = None
    for iu in range(nu):
        for iv in range(nv):
            a, b = grid[iu][iv], grid[iu + 1][iv]
            c, d = grid[iu + 1][iv + 1], grid[iu][iv + 1]
            def sc(item, _a=a):
                lo = 0.10 if role == "merchant" else 0.18
                s = clamp(item[1], lo, 1.0)
                return (SAIL_COL[0] * s, SAIL_COL[1] * s, SAIL_COL[2] * s, 1.0)
            def uv_of(item, bias):
                uu, vv = item[2], item[3]
                if abs(uu - 0.5) < 1e-6:
                    uu = 0.5 + bias
                return (uu, vv)
            # 货帆缝上的顶点按左右各记一档 UV，平滑时才不会把折痕抹平。片元仍会跨过 0.5。
            bias = 0.0
            if role == "merchant":
                bias = -0.001 if iu < nu * 0.5 else 0.001
            # 法线朝右舷（镜头那一侧）。反了的话整面帆只剩环境光，鼓腹看不见。
            n = vcross(vsub(b[0], a[0]), vsub(c[0], a[0]))
            if face_dot is None and vlen(n) > 1e-8:
                face_dot = vdot(vnorm(n), normal)
            if vdot(n, normal) < 0.0:
                sail.quad_vc(
                    a[0], d[0], c[0], b[0], sc(a), sc(d), sc(c), sc(b),
                    uv_of(a, bias), uv_of(d, bias), uv_of(c, bias), uv_of(b, bias),
                )
            else:
                sail.quad_vc(
                    a[0], b[0], c[0], d[0], sc(a), sc(b), sc(c), sc(d),
                    uv_of(a, bias), uv_of(b, bias), uv_of(c, bias), uv_of(d, bias),
                )
    if face_dot is not None:
        print(f"  sail-face role={role} t={t:.2f} raw_ndot={face_dot:.2f}")
    # 索收到桨列外面。战舟的侧索若落在桨列中间，宽景会跟桨搅成一蓬。
    if role == "war":
        rope(fit, head, (0.0, f.sheer_y(0.10) + 0.04, f.z(0.10)), 0.05, 0.006, COIR, n=3)
        for side in (1, -1):
            g = f.sample(0.86, 1.0, side)
            rope(fit, head, (g[0], g[1] + 0.03, g[2]), 0.04, 0.006, COIR, n=3)
        sheet_to = f.sample(0.88, 1.0, 1)
        tack_to = f.sample(0.14, 1.0, 1)
    else:
        rope(fit, head, (0.0, f.sheer_y(max(0.02, t - 0.18)) + 0.04, f.z(max(0.02, t - 0.18))), 0.06, 0.007, COIR, n=4)
        for side in (1, -1):
            g = f.sample(min(0.92, t + 0.10), 1.0, side)
            rope(fit, head, (g[0], g[1] + 0.03, g[2]), 0.05, 0.006, COIR, n=3)
        sheet_to = f.sample(min(0.92, t + 0.18), 1.0, 1)
        tack_to = f.sample(max(0.06, t - 0.12), 1.0, 1)
    rope(fit, foot_aft, (sheet_to[0], sheet_to[1] + 0.04, sheet_to[2]), 0.04, 0.007, COIR, n=3)
    rope(fit, foot_fwd, (tack_to[0], tack_to[1] + 0.03, tack_to[2]), 0.03, 0.006, COIR, n=3)
    # 桅顶小幡挂在木头上，不进帆的材质，免得被画成帆尖
    pen_a = head
    pen_b = (head[0] + 0.05, head[1] - 0.02, head[2] - 0.22)
    pen_c = (head[0] + 0.02, head[1] - 0.16, head[2] - 0.06)
    fit.tri(pen_a, pen_b, pen_c, BRICK, mix(BRICK, SALT, 0.25), BRICK)


def pack_glb(groups):
    mats = {
        "Wood": {
            "name": "Wood",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.78,
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
    }
    order = ["Wood", "Sail"]
    mat_index = {n: i for i, n in enumerate(order)}
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

    for node_name, prims in groups:
        primitives = []
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
            buffer_views += [
                {"buffer": 0, "byteOffset": op, "byteLength": lp, "target": 34962},
                {"buffer": 0, "byteOffset": on, "byteLength": ln, "target": 34962},
                {"buffer": 0, "byteOffset": oc, "byteLength": lc, "target": 34962},
                {"buffer": 0, "byteOffset": ou, "byteLength": lu, "target": 34962},
                {"buffer": 0, "byteOffset": oi, "byteLength": li, "target": 34963},
            ]
            a0 = len(accessors)
            accessors += [
                {
                    "bufferView": bv0, "componentType": 5126, "count": len(prim.pos), "type": "VEC3",
                    "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)],
                },
                {"bufferView": bv0 + 1, "componentType": 5126, "count": len(prim.pos), "type": "VEC3"},
                {"bufferView": bv0 + 2, "componentType": 5126, "count": len(prim.pos), "type": "VEC4"},
                {"bufferView": bv0 + 3, "componentType": 5126, "count": len(prim.pos), "type": "VEC2"},
                {"bufferView": bv0 + 4, "componentType": 5125, "count": len(prim.idx), "type": "SCALAR"},
            ]
            primitives.append({
                "attributes": {"POSITION": a0, "NORMAL": a0 + 1, "COLOR_0": a0 + 2, "TEXCOORD_0": a0 + 3},
                "indices": a0 + 4,
                "material": mat_index[prim.material],
            })
        meshes.append({"name": node_name, "primitives": primitives})
        nodes.append({"name": node_name, "mesh": len(meshes) - 1})

    root = {"name": "Champa", "children": list(range(len(nodes)))}
    nodes.append(root)
    gltf = {
        "asset": {"version": "2.0", "generator": "nk1-champa-lashed-lug"},
        "scene": 0,
        "scenes": [{"name": "Champa", "nodes": [len(nodes) - 1]}],
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
    out = bytearray()
    out.extend(b"glTF")
    out.extend(struct.pack("<I", 2))
    out.extend(struct.pack("<I", 0))
    out.extend(struct.pack("<I", len(js)))
    out.extend(b"JSON")
    out.extend(js)
    out.extend(struct.pack("<I", len(blob)))
    out.extend(b"BIN\x00")
    out.extend(blob)
    struct.pack_into("<I", out, 8, len(out))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(out)
    tris = 0
    for _, prims in groups:
        for p in prims:
            tris += len(p.idx) // 3
    print(f"wrote {OUT} bytes={len(out)} tris={tris}")


def _report_sails():
    """远相机下上桁应近乎水平，并且比侧边长。近相机的假透视会把矩形拧成菱形，这里不用。"""
    look = (0.0, 1.55, -0.15)
    dist = 18.4
    headings = [("HERO", 0.42), ("A04", 4 * math.tau / 16.0), ("A00", 0.0), ("A02", 2 * math.tau / 16.0)]
    for role, tm, fwd, aft, ff, fa in SAIL_DEBUG:
        if role != "merchant":
            continue
        for tag, h in headings:
            c, s = math.cos(h), math.sin(h)
            ox = 1.15 * c + -1.05 * s
            oy = 0.58
            oz = -1.15 * s + -1.05 * c
            n = math.sqrt(ox * ox + oy * oy + oz * oz)
            cam = (look[0] + ox / n * dist, look[1] + oy / n * dist, look[2] + oz / n * dist)
            forward = vnorm(vsub(look, cam))
            right = vnorm(vcross(forward, (0.0, 1.0, 0.0)))
            up = vnorm(vcross(right, forward))
            def proj(p, _cam=cam, _f=forward, _r=right, _u=up):
                d = vsub(p, _cam)
                depth = max(0.2, vdot(d, _f))
                return (vdot(d, _r) / depth, vdot(d, _u) / depth)
            pts = [proj(fwd), proj(aft), proj(ff), proj(fa)]
            dx, dy = pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]
            head = math.hypot(dx, dy)
            side = 0.5 * (
                math.hypot(pts[0][0] - pts[2][0], pts[0][1] - pts[2][1])
                + math.hypot(pts[1][0] - pts[3][0], pts[1][1] - pts[3][1])
            )
            slope = abs(math.degrees(math.atan2(dy, dx)))
            if slope > 90.0:
                slope = 180.0 - slope
            above = min(pts[0][1], pts[1][1]) > max(pts[2][1], pts[3][1]) - 0.004
            print(f"  sail t={tm:.2f} {tag} above={above} aspect={head/max(side,1e-4):.2f} slope={slope:.1f}")


def main():
    groups = []
    for name in ("Merchant", "War"):
        prims = build_variant(name, SPECS[name])
        groups.append((name, prims))
        tris = sum(len(p.idx) // 3 for p in prims)
        print(f"  {name} tris={tris} L={SPECS[name]['L']} oars/side={SPECS[name]['oars']} sails={SPECS[name]['sails']}")
    _report_sails()
    pack_glb(groups)


if __name__ == "__main__":
    main()
