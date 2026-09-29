#!/usr/bin/env python3
"""泉州湾南宋海船 — 一条可转的三维船壳（glTF）。

尖底、低干舷、一层露天甲板、艏艉起翘、两桅竹席硬篷。
艉是低席拱，不是箱子；帆在竹条之间鼓腹。敌我只差帆色。
船首 +Z，水线 y=0，船长沿 Z，右舷 +X。Y 朝上。

用法：python3 tools/build_song_ship_mesh.py
产物：assets/ships/song_quanzhou.glb
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "ships" / "song_quanzhou.glb"

L = 9.6
HALF = L * 0.5
BEAM = 1.78  # 半宽上限


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
    return math.sqrt(vdot(a, a))


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


# 色：桐油木、水线朱、甲板浅、帆留给材质
TEAK = (0.50, 0.31, 0.16, 1)
TEAK_LT = (0.64, 0.43, 0.24, 1)
TEAK_DK = (0.30, 0.18, 0.09, 1)
TAR = (0.11, 0.075, 0.05, 1)
CINNABAR = (0.58, 0.13, 0.09, 1)
DECK = (0.58, 0.40, 0.22, 1)
DECK_DK = (0.36, 0.23, 0.12, 1)
WALE = (0.28, 0.15, 0.08, 1)
ROOF = (0.34, 0.16, 0.11, 1)
ROOF_DK = (0.20, 0.09, 0.07, 1)
IRON = (0.16, 0.15, 0.14, 1)
IRON_LT = (0.32, 0.30, 0.28, 1)
ROPE = (0.46, 0.34, 0.18, 1)
BATTEN = (0.34, 0.22, 0.12, 1)
EYE_W = (0.90, 0.88, 0.80, 1)
EYE_K = (0.06, 0.05, 0.045, 1)
GOLD = (0.62, 0.44, 0.16, 1)
SHADOW = (0.02, 0.04, 0.06, 0.45)


def z_of(t: float) -> float:
    return HALF - t * L


def beam_half(t: float) -> float:
    bow = smoothstep(0.0, 0.14, t) ** 1.05
    full = math.sin(math.pi * clamp(t, 0.0, 1.0)) ** 0.48
    full = max(full, 0.62 * smoothstep(0.62, 1.0, t))
    transom = 1.0 - 0.34 * smoothstep(0.80, 1.0, t)
    return BEAM * max(0.02, bow * (0.42 + 0.58 * full) * transom)


def sheer(t: float) -> float:
    bow = 1.12 * math.exp(-((t - 0.0) / 0.175) ** 2)
    stern = 0.78 * math.exp(-((t - 1.0) / 0.16) ** 2)
    return 0.015 + bow + stern


def deck_side_y(t: float) -> float:
    # 舯部干舷仍低，但要能看见舷侧板，不是一条贴水的边
    return 0.50 + sheer(t)


def keel_y(t: float) -> float:
    # 只露出吃水线下一窄条尖底，整条水下船壳不画进透明视口
    body = math.sin(math.pi * clamp(t, 0.0, 1.0)) ** 0.75
    return -0.20 * max(body, 0.15 * smoothstep(0.05, 0.2, t) * (1.0 - smoothstep(0.88, 1.0, t)))


def section_pts(t: float):
    """右舷：龙骨 → 舭 → 水线 → 舷墙顶。x,y。"""
    bh = beam_half(t)
    deck = deck_side_y(t)
    keel = keel_y(t)
    # 高度参数 0 龙骨 … 1 甲板边
    pts = []
    n = 9
    for i in range(n):
        h = i / (n - 1)
        # 尖底：近龙骨收得快
        x = bh * (h ** 0.55)
        if h > 0.72:
            flare = (h - 0.72) / 0.28
            x *= 1.0 + 0.06 * flare
        y = lerp(keel, deck, h ** 0.92)
        # 水线附近略外凸，读得出舷
        if 0.55 < h < 0.85:
            x += 0.02 * math.sin((h - 0.55) / 0.30 * math.pi)
        pts.append((x, y))
    # 舷墙：略内倾
    top_y = deck + 0.34 + 0.05 * smoothstep(0.15, 0.45, t) * (1.0 - smoothstep(0.75, 0.95, t))
    pts.append((bh * 0.985, lerp(deck, top_y, 0.45)))
    pts.append((bh * 0.94, top_y))
    return pts


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
        """a-b-c-d，从外看逆时针。"""
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

    def reverse_shell(self, darken=0.72):
        """正面法线平滑之后，补一层背面。不能在平滑前把正反面堆在一起，否则法线对消。"""
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
        cnt = {}
        for i, p in enumerate(self.pos):
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
            acc[key] = vadd(acc.get(key, (0, 0, 0)), self.nrm[i])
            cnt[key] = cnt.get(key, 0) + 1
        for i, p in enumerate(self.pos):
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
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
    # index: x bit 0? I used loops x,y,z so index = ((xi*2+yi)*2+zi)
    def ix(xi, yi, zi):
        return (xi * 2 + yi) * 2 + zi

    faces = [
        (ix(1, 0, 0), ix(1, 1, 0), ix(1, 1, 1), ix(1, 0, 1)),  # +x
        (ix(0, 0, 1), ix(0, 1, 1), ix(0, 1, 0), ix(0, 0, 0)),  # -x
        (ix(0, 1, 0), ix(0, 1, 1), ix(1, 1, 1), ix(1, 1, 0)),  # +y
        (ix(0, 0, 1), ix(0, 0, 0), ix(1, 0, 0), ix(1, 0, 1)),  # -y
        (ix(0, 0, 1), ix(1, 0, 1), ix(1, 1, 1), ix(0, 1, 1)),  # +z
        (ix(1, 0, 0), ix(0, 0, 0), ix(0, 1, 0), ix(1, 1, 0)),  # -z
    ]
    for f in faces:
        prim.quad(corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], color)


def add_cyl(prim: Prim, p0, p1, r, color, n=10, caps=True):
    axis = vsub(p1, p0)
    length = vlen(axis)
    if length < 1e-5:
        return
    d = vnorm(axis)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.9 else (1.0, 0.0, 0.0)
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
        c0, c1 = p0, p1
        for i in range(n):
            j = (i + 1) % n
            prim.tri(c0, ring0[j], ring0[i], color, color, color)
            prim.tri(c1, ring1[i], ring1[j], color, color, color)


def add_sphere(prim: Prim, c, r, color, seg=8, rings=6):
    for i in range(rings):
        v0 = i / rings
        v1 = (i + 1) / rings
        th0 = (v0 - 0.5) * math.pi
        th1 = (v1 - 0.5) * math.pi
        for j in range(seg):
            u0 = j / seg * math.tau
            u1 = (j + 1) / seg * math.tau
            def p(th, u):
                return vadd(c, (
                    r * math.cos(th) * math.cos(u),
                    r * math.sin(th),
                    r * math.cos(th) * math.sin(u),
                ))
            prim.quad(p(th0, u0), p(th0, u1), p(th1, u1), p(th1, u0), color)


def rope(prim, a, b, sag, r, color, n=6):
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


def wood_at(t, j, nstrake):
    """舷板色：水线下松烟，水线一条朱，以上桐油，板缝更暗。"""
    h = j / max(1, nstrake - 1)
    if h < 0.48:
        base = mix(TAR, (0.22, 0.13, 0.08, 1), h / 0.48)
    elif h < 0.58:
        base = CINNABAR
    else:
        k = (h - 0.58) / 0.42
        base = mix(TEAK_DK, TEAK_LT, k)
    jitter = 0.92 + 0.10 * hsh(j * 19.0 + int(t * 80))
    seam = 0.62 if (j % 2 == 0 and 0 < j < nstrake - 1) else 1.0
    # 艏艉略深
    end = 1.0 - 0.12 * (smoothstep(0.0, 0.12, t) * 0 + smoothstep(0.85, 1.0, t))
    end = 1.0 - 0.10 * max(smoothstep(0.0, 0.08, 0.08 - t), smoothstep(0.9, 1.0, t))
    return tuple(clamp(c * jitter * seam * end, 0, 1) if i < 3 else c for i, c in enumerate(base))


def x_at_y(t, y_target):
    ring = section_pts(max(t, 0.012))
    best = ring[-1][0]
    best_d = 1e9
    for j in range(len(ring) - 1):
        x0, y0 = ring[j]
        x1, y1 = ring[j + 1]
        if abs(y1 - y0) < 1e-6:
            continue
        if (y0 - y_target) * (y1 - y_target) <= 0.0:
            f = (y_target - y0) / (y1 - y0)
            return lerp(x0, x1, clamp(f, 0.0, 1.0))
        d = abs(y0 - y_target)
        if d < best_d:
            best_d = d
            best = x0
    return best


def tint(color, k):
    return tuple(clamp(c * k, 0, 1) if i < 3 else c for i, c in enumerate(color))


def junk_sail(sail, fit, foot_y, head_y, z_luff_foot, z_leech_foot, z_luff_head, z_leech_head, camber, n_bat=8, n_u=14):
    """竹条是硬的，布在两条竹之间鼓出去、后缘垂成月牙。不是一块平板。"""
    n_sub = 3
    n_v = n_bat * n_sub

    def sp(u, v):
        z_luff = lerp(z_luff_foot, z_luff_head, v)
        z_leech = lerp(z_leech_foot, z_leech_head, v)
        z_leech += 0.05 * math.sin(math.pi * v)
        z = lerp(z_luff, z_leech, u ** 0.94)
        y = lerp(foot_y, head_y, v)
        y += 0.12 * u * (0.30 + 0.70 * v)
        panel = v * n_bat
        nearest = round(panel)
        if abs(panel - nearest) < 1e-5:
            local = 0.0
        else:
            local = panel - math.floor(panel)
        sag = math.sin(math.pi * local)
        billow = math.sin(math.pi * u) * (0.58 + 0.42 * math.sin(math.pi * v))
        x = camber * billow + sag * camber * 0.36 * math.sin(math.pi * u)
        y -= sag * (0.05 + 0.20 * (u ** 1.15))
        return (x, y, z), sag, local, billow

    def shade(sag, local, billow, u):
        g = 0.32 + 0.48 * billow + 0.30 * sag * math.sin(math.pi * u)
        near = math.exp(-(local * 10.0) ** 2) + math.exp(-((1.0 - local) * 10.0) ** 2)
        g *= 1.0 - 0.42 * min(1.0, near)
        g = clamp(g, 0.16, 1.0)
        return (g, g * 0.985, g * 0.90, 1.0)

    for iv in range(n_v):
        for iu in range(n_u):
            u0, u1 = iu / n_u, (iu + 1) / n_u
            v0, v1 = iv / n_v, (iv + 1) / n_v
            a, sa, la, ba = sp(u0, v0)
            b, sb, lb, bb = sp(u1, v0)
            c, sc, lc, bc = sp(u1, v1)
            d, sd, ld, bd = sp(u0, v1)
            sail.quad_vc(
                a, b, c, d,
                shade(sa, la, ba, u0), shade(sb, lb, bb, u1),
                shade(sc, lc, bc, u1), shade(sd, ld, bd, u0),
                (u0, v0), (u1, v0), (u1, v1), (u0, v1),
            )
    for batten in range(n_bat + 1):
        v = batten / n_bat
        prev = None
        rad = 0.040 if batten in (0, n_bat) else 0.026
        col = mix(BATTEN, TEAK_DK, 0.25 if batten in (0, n_bat) else 0.0)
        steps = n_u * 2
        for iu in range(steps + 1):
            u = iu / steps
            p, *_ = sp(u, v)
            p = (p[0] + 0.032, p[1], p[2])
            if prev:
                add_cyl(fit, prev, p, rad, col, 5, caps=False)
            prev = p
    prev = None
    for iv in range(n_v + 1):
        v = iv / n_v
        p, *_ = sp(1.0, v)
        p = (p[0] + 0.02, p[1], p[2])
        if prev:
            add_cyl(fit, prev, p, 0.011, ROPE, 4, caps=False)
        prev = p


def add_mat_shed(fit):
    """低席棚：拱从舷墙两侧升起，没有箱壁。"""
    t_a, t_b = 0.802, 0.930
    H = 0.58
    seg_u, seg_v = 18, 14

    def pt(u, v, lift=0.0):
        x_norm = u * 2.0 - 1.0
        t = lerp(t_a, t_b, v)
        bh = beam_half(t) * 0.88
        x = x_norm * bh
        arch = math.cos(clamp(x_norm, -1.0, 1.0) * math.pi * 0.5) ** 1.08
        # 纵剖面也收成弧：两端落到舷墙，侧面不是一条平顶箱子
        long_arch = math.sin(clamp(v, 0.0, 1.0) * math.pi) ** 0.72
        y_rail = deck_side_y(t) + 0.30 + 0.05 * (1.0 - x_norm * x_norm)
        y = y_rail + max(0.0, (H * long_arch + lift) * arch)
        return (x, y, z_of(t)), arch

    for iu in range(seg_u):
        for iv in range(seg_v):
            u0, u1 = iu / seg_u, (iu + 1) / seg_u
            v0, v1 = iv / seg_v, (iv + 1) / seg_v
            a, _ = pt(u0, v0)
            b, _ = pt(u1, v0)
            c, _ = pt(u1, v1)
            d, _ = pt(u0, v1)
            col = ROOF if (iu % 2 == 0) else mix(ROOF, ROOF_DK, 0.62)
            col = tint(col, 0.93 + 0.10 * hsh(iu * 5.1 + iv * 0.37))
            fit.quad_out(a, b, c, d, col, (0, 1, 0))
            ai, _ = pt(u0, v0, -0.032)
            bi, _ = pt(u1, v0, -0.032)
            ci, _ = pt(u1, v1, -0.032)
            di, _ = pt(u0, v1, -0.032)
            fit.quad_out(ai, di, ci, bi, mix(ROOF_DK, TAR, 0.40), (0, -1, 0))
    for u in (0.05, 0.20, 0.38, 0.62, 0.80, 0.95):
        prev = None
        rad = 0.024 if u in (0.05, 0.95) else 0.016
        for iv in range(seg_v + 1):
            p, _ = pt(u, iv / seg_v, 0.012)
            if prev:
                add_cyl(fit, prev, p, rad, BATTEN, 5, caps=False)
            prev = p
    for iv in (1, 4, 7, 10, 13):
        prev = None
        v = iv / seg_v
        for iu in range(seg_u + 1):
            p, _ = pt(iu / seg_u, v, 0.02)
            if prev:
                add_cyl(fit, prev, p, 0.013, BATTEN, 5, caps=False)
            prev = p
    for v, rad in ((0.0, 0.030), (1.0, 0.022)):
        prev = None
        for iu in range(seg_u + 1):
            p, _ = pt(iu / seg_u, v, 0.0)
            if prev:
                add_cyl(fit, prev, p, rad, mix(BATTEN, TEAK_DK, 0.35), 6, caps=False)
            prev = p
    for u, v in ((0.04, 0.10), (0.96, 0.10), (0.07, 0.90), (0.93, 0.90)):
        p, _ = pt(u, v, 0.0)
        t = lerp(t_a, t_b, v)
        sgn = -1.0 if u < 0.5 else 1.0
        rail = (sgn * beam_half(t) * 0.90, deck_side_y(t) + 0.32, z_of(t))
        rope(fit, p, rail, 0.03, 0.008, ROPE, n=4)


def add_partner(fit, t, scale):
    z = z_of(t)
    y = deck_side_y(t) + 0.108
    n = 12
    r_out = scale * 0.62
    r_in = max(0.09, scale * 0.24)
    thick = 0.062
    for i in range(n):
        a0 = i / n * math.tau
        a1 = (i + 1) / n * math.tau

        def polar(a, r, yy):
            return (math.cos(a) * r, yy, z + math.sin(a) * r)

        out_n = (math.cos((a0 + a1) * 0.5), 0.0, math.sin((a0 + a1) * 0.5))
        fit.quad_out(
            polar(a0, r_out, y + thick), polar(a1, r_out, y + thick),
            polar(a1, r_in, y + thick), polar(a0, r_in, y + thick),
            TEAK_DK, (0, 1, 0),
        )
        fit.quad_out(
            polar(a0, r_out, y), polar(a1, r_out, y),
            polar(a1, r_out, y + thick), polar(a0, r_out, y + thick),
            TEAK, out_n,
        )
        fit.quad_out(
            polar(a0, r_in, y + thick), polar(a1, r_in, y + thick),
            polar(a1, r_in, y), polar(a0, r_in, y),
            (0.07, 0.045, 0.03, 1), vmul(out_n, -1),
        )
    for k in range(4):
        a = (k + 0.5) * math.tau / 4.0
        inner = (math.cos(a) * r_in * 1.05, y + thick * 0.55, z + math.sin(a) * r_in * 1.05)
        outer = (math.cos(a) * r_out * 0.78, y + thick * 0.72, z + math.sin(a) * r_out * 0.78)
        add_cyl(fit, inner, outer, 0.022, mix(TEAK, TEAK_LT, 0.35), 5, caps=False)
    add_cyl(fit, (0, y + thick, z), (0, y + thick + 0.018, z), r_in * 0.72, IRON, 8)


def add_hatch(fit, t, w, length):
    z = z_of(t)
    y = deck_side_y(t) + 0.095
    well = (0.055, 0.032, 0.022, 1)
    add_box(fit, (0, y - 0.01, z), (w * 0.70, 0.045, length * 0.70), well)
    beam = 0.055
    h = 0.11
    wood = mix(TEAK, TEAK_DK, 0.35)
    add_box(fit, (w * 0.5, y + h * 0.5, z), (beam, h, length), wood)
    add_box(fit, (-w * 0.5, y + h * 0.5, z), (beam, h, length), wood)
    add_box(fit, (0, y + h * 0.5, z + length * 0.5), (w, h, beam), tint(wood, 0.92))
    add_box(fit, (0, y + h * 0.5, z - length * 0.5), (w, h, beam), tint(wood, 0.92))
    npl = 4
    lid_y = y + h * 0.72
    inner_w = w * 0.78
    inner_l = length * 0.76
    for k in range(npl):
        u0 = -0.5 + k / npl
        u1 = -0.5 + (k + 1) / npl
        gap = 0.04
        x0 = (u0 + gap / npl) * inner_w
        x1 = (u1 - gap / npl) * inner_w
        cam = 0.012 * (1.0 - ((u0 + u1) ** 2))
        col = tint(mix(DECK, TEAK_DK, 0.25), 0.90 + 0.12 * hsh(k * 8.2 + t * 20))
        add_box(fit, ((x0 + x1) * 0.5, lid_y + cam, z), (max(0.04, x1 - x0), 0.028, inner_l), col)
    for s in (-0.22, 0.22):
        add_box(fit, (0, lid_y + 0.028, z + s * length), (inner_w * 0.92, 0.022, 0.045), BATTEN)
    for sx in (-1, 1):
        for sz in (-1, 1):
            add_box(
                fit,
                (sx * w * 0.46, y + h * 0.55, z + sz * length * 0.46),
                (0.04, 0.025, 0.04),
                IRON,
            )


def add_rudder(fit):
    """开孔舵：叶面是一块板，孔是真挖空，不是贴在箱子上的圆片。"""
    rud_z = z_of(1.0) - 0.05
    ny, nz = 16, 11
    yb, yt = -0.50, 0.78
    holes = ((0.30, 0.48, 0.10, 0.15), (0.52, 0.50, 0.11, 0.16), (0.74, 0.46, 0.095, 0.145))

    def in_hole(v, s):
        for hv, hs, rv, rs in holes:
            if ((v - hv) / rv) ** 2 + ((s - hs) / rs) ** 2 < 1.0:
                return True
        return False

    def pnt(iy, iz, x):
        v = iy / ny
        s = iz / nz
        y = lerp(yb, yt, v)
        chord = lerp(0.98, 0.36, v ** 0.85)
        z = rud_z - s * chord
        return (x, y, z)

    th = 0.028
    for iy in range(ny):
        for iz in range(nz):
            v = (iy + 0.5) / ny
            s = (iz + 0.5) / nz
            if in_hole(v, s):
                continue
            c00, c10 = pnt(iy, iz, th), pnt(iy + 1, iz, th)
            c11, c01 = pnt(iy + 1, iz + 1, th), pnt(iy, iz + 1, th)
            d00, d10 = pnt(iy, iz, -th), pnt(iy + 1, iz, -th)
            d11, d01 = pnt(iy + 1, iz + 1, -th), pnt(iy, iz + 1, -th)
            col = mix(TEAK, TEAK_DK, 0.35 + 0.10 * hsh(iy * 3.7 + iz))
            fit.quad_out(c00, c01, c11, c10, col, (1, 0, 0))
            fit.quad_out(d00, d10, d11, d01, col, (-1, 0, 0))

            def exposed(niy, niz):
                if niy < 0 or niz < 0 or niy >= ny or niz >= nz:
                    return True
                return in_hole((niy + 0.5) / ny, (niz + 0.5) / nz)

            sides = (
                ((c00, d00, d10, c10), iy - 1, iz, (0, -1, 0)),
                ((c11, d11, d01, c01), iy + 1, iz, (0, 1, 0)),
                ((c01, d01, d00, c00), iy, iz - 1, (0, 0, 1)),
                ((c10, d10, d11, c11), iy, iz + 1, (0, 0, -1)),
            )
            rim = mix(col, TAR, 0.45)
            for quad, niy, niz, outward in sides:
                if exposed(niy, niz):
                    fit.quad_out(quad[0], quad[1], quad[2], quad[3], rim, outward)
    for v in (0.12, 0.40, 0.62, 0.90):
        y = lerp(yb, yt, v)
        chord = lerp(0.98, 0.36, v ** 0.85)
        add_box(fit, (0, y, rud_z - chord * 0.48), (0.07, 0.028, chord * 0.88), IRON)
    stock_top = deck_side_y(0.98) + 0.36
    add_cyl(fit, (0, 0.42, rud_z + 0.02), (0, stock_top, rud_z + 0.02), 0.048, TEAK_DK, 8)
    add_sphere(fit, (0, stock_top + 0.02, rud_z + 0.02), 0.055, IRON, 6, 4)
    add_cyl(
        fit,
        (0.0, stock_top - 0.02, rud_z + 0.02),
        (0.0, deck_side_y(0.95) + 0.16, z_of(0.90)),
        0.026,
        TEAK,
        6,
    )


def add_waterline(fit, stations):
    bands = (
        (-0.05, 0.010, TAR),
        (0.000, 0.018, mix(TAR, CINNABAR, 0.25)),
        (0.038, 0.032, CINNABAR),
        (0.072, 0.028, (0.78, 0.62, 0.40, 1)),
        (0.098, 0.016, WALE),
    )
    for i in range(len(stations) - 1):
        t0, z0, _r0 = stations[i]
        t1, z1, _r1 = stations[i + 1]
        for bi in range(len(bands) - 1):
            y_a, p_a, col = bands[bi]
            y_b, p_b, _col_b = bands[bi + 1]

            def wp(t, z, y, push):
                return (x_at_y(t, y) + push, y, z)

            a = wp(t0, z0, y_a, p_a)
            b = wp(t1, z1, y_a, p_a)
            c = wp(t1, z1, y_b, p_b)
            d = wp(t0, z0, y_b, p_b)
            fit.quad_out(a, b, c, d, col, (1, 0, 0))

            def mx(p):
                return (-p[0], p[1], p[2])

            fit.quad_out(mx(a), mx(d), mx(c), mx(b), col, (-1, 0, 0))


def add_gunwale(fit, stations):
    for i in range(len(stations) - 1):
        _t0, z0, r0 = stations[i]
        _t1, z1, r1 = stations[i + 1]
        a = (r0[-1][0], r0[-1][1], z0)
        b = (r1[-1][0], r1[-1][1], z1)
        c = (b[0] + 0.028, b[1] + 0.04, b[2])
        d = (a[0] + 0.028, a[1] + 0.04, a[2])
        e = (b[0] - 0.012, b[1] + 0.028, b[2])
        f = (a[0] - 0.012, a[1] + 0.028, a[2])
        cap = mix(TEAK_LT, TEAK, 0.35)
        fit.quad_out(a, b, c, d, TEAK_DK, (1, 0.2, 0))
        fit.quad_out(d, c, e, f, cap, (0, 1, 0))

        def mx(p):
            return (-p[0], p[1], p[2])

        fit.quad_out(mx(a), mx(d), mx(c), mx(b), TEAK_DK, (-1, 0.2, 0))
        fit.quad_out(mx(d), mx(f), mx(e), mx(c), cap, (0, 1, 0))


def add_contact_shadow(shadow):
    steps = 40
    layers = ((0.00, 0.55, 0.40), (0.55, 0.82, 0.22), (0.82, 1.08, 0.10), (1.08, 1.28, 0.04))

    def emit(t0, t1, z0, z1, beam_scale, alpha_scale):
        for f0, f1, alpha in layers:
            col = (0.012, 0.028, 0.045, alpha * alpha_scale)

            def xb(t, f):
                return beam_half(clamp(t, 0.02, 0.98)) * f * 1.04 * beam_scale

            b0, b1 = xb(t0, f0), xb(t1, f0)
            o0, o1 = xb(t0, f1), xb(t1, f1)
            y = -0.022
            shadow.quad((b0, y, z0), (b1, y, z1), (o1, y, z1), (o0, y, z0), col)
            shadow.quad((-b0, y, z0), (-o0, y, z0), (-o1, y, z1), (-b1, y, z1), col)

    for i in range(steps):
        t0 = i / steps
        t1 = (i + 1) / steps
        emit(t0, t1, z_of(t0), z_of(t1), 1.0, 1.0)
    for i in range(5):
        f0 = i / 5
        f1 = (i + 1) / 5
        shrink0 = 1.0 - f0
        shrink1 = 1.0 - f1
        emit(0.03, 0.03, z_of(0.0) + 0.02 + f0 * 0.62, z_of(0.0) + 0.02 + f1 * 0.62, (shrink0 + shrink1) * 0.5, 0.55 * shrink0)
        emit(0.97, 0.97, z_of(1.0) - 0.02 - f0 * 0.48, z_of(1.0) - 0.02 - f1 * 0.48, (shrink0 + shrink1) * 0.5, 0.45 * shrink0)


def build():
    hull = Prim("Hull", "Wood")
    deck = Prim("Deck", "Wood")
    fit = Prim("Fittings", "Wood")
    sail = Prim("Sails", "Sail")
    shadow = Prim("Shadow", "Shadow")

    nst = 52
    stations = []
    for i in range(nst):
        t = i / (nst - 1)
        t_use = max(t, 0.012)
        ring = section_pts(t_use)
        z = z_of(t)
        stations.append((t, z, ring))

    for i in range(nst - 1):
        t0, z0, r0 = stations[i]
        t1, z1, r1 = stations[i + 1]
        nring = len(r0)
        for j in range(nring - 1):
            def P(ring, z, j):
                x, y = ring[j]
                if 0 < j < nring - 1 and j % 2 == 0 and j < nring - 3:
                    y -= 0.006
                    x *= 0.992
                return (x, y, z)

            a = P(r0, z0, j)
            b = P(r1, z1, j)
            c = P(r1, z1, j + 1)
            d = P(r0, z0, j + 1)
            col = wood_at((t0 + t1) * 0.5, j, nring)
            mid = vmul(vadd(vadd(a, b), vadd(c, d)), 0.25)
            hull.quad_out(a, b, c, d, col, (mid[0], 0.15, 0.0))

            def mx(p):
                return (-p[0], p[1], p[2])

            hull.quad_out(mx(a), mx(d), mx(c), mx(b), col, (-mid[0], 0.15, 0.0))

    t0, z0, r0 = stations[0]
    stem = []
    for j, (x, y) in enumerate(r0):
        f = j / (len(r0) - 1)
        stem.append((0.0, y + 0.012 * f, z0 + 0.035 + 0.11 * f))
    for j in range(len(r0) - 1):
        a = (r0[j][0], r0[j][1], z0)
        b = (r0[j + 1][0], r0[j + 1][1], z0)
        col = wood_at(0.02, j, len(r0))
        hull.quad_out(a, b, stem[j + 1], stem[j], col, (0, 0.15, 1))
        hull.quad_out((-a[0], a[1], a[2]), stem[j], stem[j + 1], (-b[0], b[1], b[2]), col, (0, 0.15, 1))

    rt = stations[-1][2]
    zt = stations[-1][1]
    for j in range(len(rt) - 1):
        a = (rt[j][0], rt[j][1], zt)
        b = (rt[j + 1][0], rt[j + 1][1], zt)
        c = (-rt[j + 1][0], rt[j + 1][1], zt)
        d = (-rt[j][0], rt[j][1], zt)
        col = wood_at(0.98, j, len(rt))
        hull.quad_out(a, d, c, b, col, (0, 0, -1))

    hull.smooth()

    caulk = (0.09, 0.055, 0.035, 1)
    n_planks = 16
    for i in range(nst - 1):
        t0, z0, r0 = stations[i]
        t1, z1, r1 = stations[i + 1]
        b0 = r0[-3][0] * 0.90
        b1 = r1[-3][0] * 0.90
        y0 = r0[-3][1] + 0.012
        y1 = r1[-3][1] + 0.012

        def deck_y(u, y):
            return y + 0.072 * (1.0 - u * u)

        for k in range(n_planks):
            u0 = -1.0 + 2.0 * k / n_planks
            u1 = -1.0 + 2.0 * (k + 1) / n_planks
            du = 0.018 / max((b0 + b1) * 0.5, 0.2)
            ua, ub = u0 + du * 0.35, u1 - du * 0.35
            tone = 0.84 + 0.20 * hsh(k * 17.3)
            grain = 0.93 + 0.09 * hsh(k * 9.2 + (i // 6) * 2.3)
            # 一站宽的错缝，不是整段甲板涂黑
            butt = (i % 15 == (k * 4 + 3) % 15) and 3 < i < nst - 5
            base = mix(DECK_DK, DECK, tone)
            col = tint(base, grain * (0.72 if butt else 1.0) * (0.86 if abs((u0 + u1) * 0.5) > 0.88 else 1.0))
            if k % 2 == 1:
                col = tint(col, 0.90)

            def Dp(u, b, y, z, drop=0.0):
                return (u * b, deck_y(u, y) - drop, z)

            drop_b = 0.008 if butt else 0.0
            a = Dp(ua, b0, y0, z0, drop_b)
            bpt = Dp(ua, b1, y1, z1, drop_b)
            c = Dp(ub, b1, y1, z1, drop_b)
            d = Dp(ub, b0, y0, z0, drop_b)
            deck.quad_out(a, d, c, bpt, col, (0, 1, 0))
            if k < n_planks - 1:
                s0, s1 = ub, u1 + du * 0.35
                drop = 0.014
                ga = Dp(s0, b0, y0, z0, drop)
                gb = Dp(s0, b1, y1, z1, drop)
                gc = Dp(s1, b1, y1, z1, drop)
                gd = Dp(s1, b0, y0, z0, drop)
                deck.quad_out(ga, gd, gc, gb, caulk, (0, 1, 0))
                la = Dp(s0, b0, y0, z0, 0.0)
                lb = Dp(s0, b1, y1, z1, 0.0)
                deck.quad_out(la, lb, gb, ga, tint(caulk, 1.15), (1 if s0 > 0 else -1, 0, 0))
                ra = Dp(s1, b0, y0, z0, 0.0)
                rb = Dp(s1, b1, y1, z1, 0.0)
                deck.quad_out(gc, gb, rb, ra, tint(caulk, 1.15), (1 if s1 > 0 else -1, 0, 0))

    add_hatch(fit, 0.30, 0.62, 0.78)
    add_hatch(fit, 0.48, 0.70, 0.92)
    add_hatch(fit, 0.66, 0.56, 0.70)
    add_partner(fit, 0.30, 0.40)
    add_partner(fit, 0.56, 0.48)

    def mast(t, height, radius):
        z = z_of(t)
        y0 = deck_side_y(t) + 0.10
        add_cyl(fit, (0, y0, z), (0, y0 + height, z), radius, mix(TEAK_DK, TEAK, 0.4), 8)
        for k in range(4):
            yy = y0 + height * (0.18 + k * 0.18)
            add_cyl(fit, (0, yy, z), (0, yy + 0.028, z), radius * 1.28, IRON, 8)
        add_sphere(fit, (0, y0 + height, z), radius * 1.15, TEAK_DK, 6, 4)
        return (0, y0 + height, z)

    fore_top = mast(0.30, 4.15, 0.055)
    main_top = mast(0.56, 5.35, 0.070)

    junk_sail(
        sail, fit,
        deck_side_y(0.30) + 0.85, deck_side_y(0.30) + 3.55,
        z_of(0.16), z_of(0.40), z_of(0.20), z_of(0.38),
        camber=0.62, n_bat=7, n_u=12,
    )
    junk_sail(
        sail, fit,
        deck_side_y(0.56) + 0.70, deck_side_y(0.56) + 4.70,
        z_of(0.42), z_of(0.72), z_of(0.46), z_of(0.68),
        camber=0.88, n_bat=9, n_u=14,
    )
    sail.smooth()
    sail.reverse_shell(0.70)

    rope(fit, (0.42, deck_side_y(0.40) + 0.95, z_of(0.40)), (0.40, deck_side_y(0.46) + 0.16, z_of(0.46)), 0.12, 0.012, ROPE)
    rope(fit, (0.55, deck_side_y(0.72) + 0.78, z_of(0.72)), (0.42, deck_side_y(0.78) + 0.20, z_of(0.78)), 0.16, 0.014, ROPE)
    rope(fit, (0.0, fore_top[1] * 0.92, fore_top[2]), (0.0, deck_side_y(0.06) + 0.40, z_of(0.04)), 0.05, 0.012, ROPE)
    rope(fit, (0.0, main_top[1] * 0.95, main_top[2]), (0.0, deck_side_y(0.08) + 0.35, z_of(0.06)), 0.08, 0.012, ROPE)

    add_mat_shed(fit)
    add_rudder(fit)

    yb = deck_side_y(0.12) + 0.08
    add_cyl(fit, (-0.28, yb, z_of(0.12)), (0.28, yb, z_of(0.12)), 0.075, TEAK_DK, 8)
    for s in (-1, 1):
        add_cyl(fit, (s * 0.28, yb, z_of(0.12)), (s * 0.36, yb + 0.02, z_of(0.12)), 0.028, TEAK, 5)
    add_box(fit, (0, yb + 0.02, z_of(0.12)), (0.07, 0.07, 0.62), TEAK)
    add_cyl(fit, (0.62, deck_side_y(0.14) + 0.05, z_of(0.14)), (0.92, deck_side_y(0.08) - 0.02, z_of(0.05)), 0.022, IRON, 6)
    add_box(fit, (0.96, deck_side_y(0.08), z_of(0.035)), (0.18, 0.07, 0.07), IRON_LT)

    for t, x in ((0.18, 0.55), (0.18, -0.55), (0.74, 0.48), (0.74, -0.48)):
        y = deck_side_y(t) + 0.05
        add_cyl(fit, (x, y, z_of(t)), (x, y + 0.24, z_of(t)), 0.038, TEAK_DK, 6)
        add_cyl(fit, (x - 0.05, y + 0.20, z_of(t)), (x + 0.05, y + 0.20, z_of(t)), 0.02, TEAK, 5)

    for s in (-1, 1):
        t = 0.07
        x = s * beam_half(t) * 0.72
        y = deck_side_y(t) * 0.55
        z = z_of(t)
        add_sphere(fit, (x, y, z + 0.02), 0.13, EYE_W, 8, 6)
        add_sphere(fit, (x + s * 0.045, y, z + 0.10), 0.05, EYE_K, 6, 5)
        add_cyl(fit, (x, y, z - 0.02), (x, y, z + 0.12), 0.155, GOLD, 8, caps=False)

    for i in range(6, nst - 6, 3):
        t, z, ring = stations[i]
        x = ring[-2][0]
        y = ring[-4][1]
        add_box(fit, (x, y, z), (0.045, 0.035, 0.06), (0.05, 0.035, 0.028, 1))
        add_box(fit, (-x, y, z), (0.045, 0.035, 0.06), (0.05, 0.035, 0.028, 1))

    add_waterline(fit, stations)
    add_gunwale(fit, stations)

    add_cyl(fit, (0.62, deck_side_y(0.50) + 0.02, z_of(0.50)), (0.62, deck_side_y(0.50) + 0.30, z_of(0.50)), 0.11, mix(TEAK, IRON, 0.15), 8)
    add_cyl(fit, (0.62, deck_side_y(0.50) + 0.30, z_of(0.50)), (0.62, deck_side_y(0.50) + 0.33, z_of(0.50)), 0.12, IRON, 8)
    add_cyl(fit, (-0.52, deck_side_y(0.44) + 0.02, z_of(0.44)), (-0.52, deck_side_y(0.44) + 0.18, z_of(0.44)), 0.14, ROPE, 8)

    add_contact_shadow(shadow)
    return [hull, deck, fit, sail, shadow]


def pack_glb(prims):
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
                "baseColorFactor": [0.93, 0.88, 0.74, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.62,
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
    # 稳定顺序
    order = ["Wood", "Sail", "Shadow"]
    used = []
    for p in prims:
        if p.material not in used:
            used.append(p.material)
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

    for pi, prim in enumerate(prims):
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

    root = {"name": "SongQuanzhou", "children": list(range(len(nodes)))}
    nodes.append(root)
    gltf = {
        "asset": {"version": "2.0", "generator": "nk1-song-quanzhou-polish"},
        "extensionsUsed": ["KHR_materials_unlit"],
        "scene": 0,
        "scenes": [{"name": "Song", "nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": [mats[n] for n in order],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    # pad json with spaces
    while len(js) % 4:
        js += b" "
    while len(blob) % 4:
        blob.append(0)
    out = bytearray()
    out.extend(b"glTF")
    out.extend(struct.pack("<I", 2))
    out.extend(struct.pack("<I", 0))  # total later
    out.extend(struct.pack("<I", len(js)))
    out.extend(b"JSON")
    out.extend(js)
    out.extend(struct.pack("<I", len(blob)))
    out.extend(b"BIN\x00")
    out.extend(blob)
    struct.pack_into("<I", out, 8, len(out))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(out)
    # stats
    tris = sum(len(p.idx) // 3 for p in prims)
    xs, ys, zs = [], [], []
    for p in prims:
        for q in p.pos:
            xs.append(q[0]); ys.append(q[1]); zs.append(q[2])
    print(f"wrote {OUT} bytes={len(out)} tris={tris}")
    print(f"bounds x[{min(xs):.2f},{max(xs):.2f}] y[{min(ys):.2f},{max(ys):.2f}] z[{min(zs):.2f},{max(zs):.2f}]")


if __name__ == "__main__":
    pack_glb(build())
