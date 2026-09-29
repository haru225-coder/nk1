#!/usr/bin/env python3
"""泉州湾南宋海船 — 一条可转的三维船壳（glTF）。

尖底、低干舷、一层露天甲板、艏艉起翘、两桅竹席硬篷。
艉是一只低席拱，口朝艏、拱腹看得见。露天甲板中线三处大舱口，另有一间矮席棚。帆是一整张弯席，竹条贴在面上，后缘一截弧。敌我只差帆色。
船械只按南宋：旋风砲抛霹雳炮、火箭、艏部拍竿。没有炮、没有佛郎机、没有炮门。
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
    """船宽是一条 C2 曲线。不用 max 拼接，肩部和艉肩不再折出棱。"""
    t = clamp(t, 0.0, 1.0)
    bow = smoothstep(0.0, 0.18, t)
    body = 0.64 + 0.36 * math.sin(math.pi * t)
    narrow = 1.0 - 0.22 * smoothstep(0.68, 1.0, t)
    return BEAM * max(1e-4, bow * body * narrow)


def sheer(t: float) -> float:
    """整条舷弧是一段余弦，舯低、艏艉高，中段不再是直线再突然折起。"""
    t = clamp(t, 0.0, 1.0)
    # t=0 → 1.10，t=0.5 → -0.10，t=1 → 0.78。干舷仍低，不是第二层甲板。
    return 0.42 + 0.16 * math.cos(math.pi * t) + 0.52 * math.cos(2.0 * math.pi * t)


def deck_side_y(t: float) -> float:
    # 舯部干舷低，艏艉随舷弧抬起
    return 0.40 + sheer(t)


def keel_y(t: float) -> float:
    # 尖底只露出水线下一窄条，整条水下船壳不画进透明视口
    body = math.sin(math.pi * clamp(t, 0.0, 1.0)) ** 0.90
    return -0.30 * max(body, 0.12 * smoothstep(0.05, 0.2, t) * (1.0 - smoothstep(0.88, 1.0, t)))


def section_pts(t: float):
    """右舷：龙骨尖底 → 甲板边 → 低舷墙。横剖面多切，舷侧是弧不是一叠平板。"""
    bh = beam_half(t)
    deck = deck_side_y(t)
    keel = keel_y(t)
    n = 32
    pts = []
    for i in range(n):
        h = i / (n - 1)
        # 近龙骨先窄，底是尖的。外飘是 h 的平滑项，不在某处折一下。
        flare = 1.0 + 0.045 * (h * h)
        x = bh * (h ** 1.16) * flare
        y = lerp(keel, deck, h ** 1.04)
        pts.append((x, y))
    top_y = deck + 0.15 + 0.025 * math.sin(math.pi * clamp(t, 0.0, 1.0))
    pts.append((bh * 0.985, lerp(deck, top_y, 0.48)))
    pts.append((bh * 0.955, top_y))
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

    def quad_vc_out(self, a, b, c, d, ca, cb, cc, cd, outward, uva=(0.0, 0.0), uvb=(0.0, 0.0), uvc=(0.0, 0.0), uvd=(0.0, 0.0)):
        n = vcross(vsub(b, a), vsub(c, a))
        if vdot(n, outward) < 0.0:
            self.quad_vc(a, d, c, b, ca, cd, cc, cb, uva, uvd, uvc, uvb)
        else:
            self.quad_vc(a, b, c, d, ca, cb, cc, cd, uva, uvb, uvc, uvd)

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


def wood_at(t, j, nstrake, along=0.0):
    """舷板色：水线下松烟，以上桐油。水线朱不涂在壳上。板与板颜色接近，不靠斑马条。"""
    h = j / max(1, nstrake - 1)
    if h < 0.40:
        base = mix(TAR, (0.25, 0.15, 0.09, 1), smoothstep(0.0, 0.40, h))
    else:
        k = clamp((h - 0.40) / 0.60, 0.0, 1.0)
        base = mix(TEAK, TEAK_LT, 0.18 + 0.62 * (k ** 0.85))
    piece = math.floor((along + j * 0.37) / 0.22)
    tone = 0.90 + 0.14 * hsh(j * 13.0 + piece * 5.0)
    grain = 0.97 + 0.05 * math.sin(along * 37.0 + j * 1.7)
    end = 1.0 - 0.08 * max(smoothstep(0.92, 1.0, t), smoothstep(0.08, 0.0, t))
    return tuple(clamp(c * tone * grain * end, 0, 1) if i < 3 else c for i, c in enumerate(base))


def x_at_y(t, y_target):
    ring = section_pts(max(t, 0.004))
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
    """一张席。整张弯向左舷，再绕桅偏一个角度，正视和艉舷都能看见布面而不是后缘的侧影。
    竹条贴在这张面上。不再一格一格地下坠，否则侧看就是一叠板。"""
    n_sub = 8
    n_v = n_bat * n_sub
    # 帆面法线大约朝 118°。己方从艏舷看、敌船从艉舷看，看见的都是布面，不是后缘的一叠架子。
    sail_yaw = 1.08
    cy, sy = math.cos(sail_yaw), math.sin(sail_yaw)
    z_pivot = (z_luff_foot + z_luff_head) * 0.5

    def yaw_pt(p):
        x, y, z = p
        dz = z - z_pivot
        return (x * cy + dz * sy, y, z_pivot - x * sy + dz * cy)

    def sheet_of(u, v):
        # 弯度几乎只沿帆宽走。v 上不再每格鼓一次，否则侧看就是宝塔。
        return (math.sin(math.pi * clamp(u, 0.0, 1.0)) ** 0.80) * (0.94 + 0.06 * math.sin(math.pi * clamp(v, 0.0, 1.0)))

    def scallop_of(v):
        panel = v * n_bat
        nearest = round(panel)
        if abs(panel - nearest) < 1e-4:
            local = 0.0
        else:
            local = panel - math.floor(panel)
        # 竹上是 0 且斜率为 0，布贴回同一张面。
        return math.sin(math.pi * local) ** 2

    def base_pt(u, v):
        z_luff = lerp(z_luff_foot, z_luff_head, v)
        z_leech = lerp(z_leech_foot, z_leech_head, v)
        z_leech += 0.05 * math.sin(math.pi * v)
        z = lerp(z_luff, z_leech, u ** 0.92)
        y = lerp(foot_y, head_y, v)
        y += 0.03 * u * (0.12 + 0.10 * v)
        # 整张弯向左舷（低相机在这一侧），是一张连续的腹。
        x = -abs(camber) * 0.62 * sheet_of(u, v)
        return (x, y, z)

    def sp(u, v):
        # 竹间只鼓一点点，仍是同一张面。鼓出量小于竹条离布的距离，竹还是贴在布上的扁条。
        belly = scallop_of(v)
        p = base_pt(u, v)
        p = (p[0] - belly * 0.007, p[1], p[2])
        return yaw_pt(p), belly, sheet_of(u, v)

    def shade(belly, sheet, u):
        # 竹间略亮，对比很小，不把绛红切成一层层板。篾纹在着色器里。
        g = 0.90 + 0.05 * sheet + 0.055 * belly
        g *= 1.0 - 0.018 * u
        g = clamp(g, 0.86, 1.0)
        return (g, g * 0.988, g * 0.94, 1.0)

    for iv in range(n_v):
        for iu in range(n_u):
            u0, u1 = iu / n_u, (iu + 1) / n_u
            v0, v1 = iv / n_v, (iv + 1) / n_v
            a, ba, sa = sp(u0, v0)
            b, bb, sb = sp(u1, v0)
            c, bc, sc = sp(u1, v1)
            d, bd, sd = sp(u0, v1)
            sail.quad_vc(
                a, b, c, d,
                shade(ba, sa, u0), shade(bb, sb, u1),
                shade(bc, sc, u1), shade(bd, sd, u0),
                (u0, v0), (u1, v0), (u1, v1), (u0, v1),
            )
    # 竹是贴在布上的扁条，不是圆棍。正面看是一条细线；即便稍侧，也没有棍子那么厚。
    # 法线（帆在偏转前朝 -X）转到世界：(-cy, 0, sy)。条贴在这一面，并在背面再贴一条同样细的，两台相机都看得见。
    face_n = vnorm((-cy, 0.0, sy))
    for batten in range(n_bat + 1):
        v = batten / n_bat
        half_h = 0.016 if batten in (0, n_bat) else 0.009
        col = mix(CINNABAR, BATTEN, 0.42 if batten in (0, n_bat) else 0.55)
        steps = n_u * 2
        pts = []
        for iu in range(steps + 1):
            u = iu / steps
            # 收到布边里面，竹头不伸出后缘，后缘才是一条弧
            u = 0.015 + u * 0.955
            pts.append(yaw_pt(base_pt(u, v)))
        for sgn in (1.0, -1.0):
            off = vmul(face_n, 0.010 * sgn)
            prev = None
            for p in pts:
                q = vadd(p, off)
                if prev:
                    up = (0.0, half_h, 0.0)
                    a = vadd(prev, up)
                    b = vadd(q, up)
                    c = vsub(q, up)
                    d = vsub(prev, up)
                    fit.quad_out(a, b, c, d, col, vmul(face_n, sgn))
                prev = q
    for batten in range(1, n_bat, 2):
        v = batten / n_bat
        p = yaw_pt(base_pt(0.72, v))
        p = (p[0] + 0.02 * cy, p[1], p[2] - 0.02 * sy)
        drop = (p[0] + 0.015, p[1] - 0.07, p[2])
        rope(fit, p, drop, 0.004, 0.008, ROPE, n=3)
        add_sphere(fit, drop, 0.016, TEAK_DK, 5, 4)
    prev = None
    for iv in range(0, n_v + 1, 2):
        v = iv / n_v
        p, *_ = sp(1.0, v)
        p = (p[0] + 0.012, p[1], p[2])
        if prev:
            add_cyl(fit, prev, p, 0.006, ROPE, 4, caps=False)
        prev = p


def add_mat_shed(fit):
    """艉部一只矮席拱。只是一张弯席盖在柱上，口朝艏。
    两侧不收到甲板上，所以不是封死的桶。口沿亮，拱里是暗的。"""
    t0, t1 = 0.828, 0.932
    seg_u, seg_v = 18, 6

    def metrics(v):
        t = lerp(t0, t1, v)
        half_w = min(beam_half(t) * 0.72, 1.02) * lerp(1.0, 0.90, v)
        spring = 0.34 * lerp(1.0, 0.82, v)
        rise = 0.78 * lerp(1.0, 0.86, v)
        return t, half_w, spring, rise

    def pt(u, v, lift=0.0):
        t, half_w, spring, rise = metrics(v)
        arch = math.sin(clamp(u, 0.0, 1.0) * math.pi) ** 1.15
        x = lerp(-half_w, half_w, u)
        y = deck_side_y(t) + spring + arch * rise + lift
        return (x, y, z_of(t))

    for iu in range(seg_u):
        for iv in range(seg_v):
            u0, u1 = iu / seg_u, (iu + 1) / seg_u
            v0, v1 = iv / seg_v, (iv + 1) / seg_v
            a, b = pt(u0, v0), pt(u1, v0)
            c, d = pt(u1, v1), pt(u0, v1)
            stripe = 0.62 if iu % 3 == 2 else 1.0
            col = mix(ROOF_DK, mix(ROOF, CINNABAR, 0.14), stripe)
            col = tint(col, 0.95 + 0.07 * hsh(iu * 2.7 + iv))
            fit.quad_out(a, b, c, d, col, (0, 1, 0))
            ai, bi = pt(u0, v0, -0.035), pt(u1, v0, -0.035)
            ci, di = pt(u1, v1, -0.035), pt(u0, v1, -0.035)
            fit.quad_out(ai, di, ci, bi, (0.04, 0.02, 0.014, 1), (0, -1, 0))
    dark = (0.012, 0.007, 0.005, 1)
    # 后壁填满拱口的投影，从甲板一直到席底。嘴是空的。
    bv = 0.82
    t, half_w, spring, rise = metrics(bv)
    y_deck = deck_side_y(t) + 0.04
    z = z_of(t)
    for iu in range(seg_u):
        u0, u1 = iu / seg_u, (iu + 1) / seg_u
        a, b = pt(u0, bv, -0.01), pt(u1, bv, -0.01)
        fa, fb = (a[0], y_deck, z), (b[0], y_deck, z)
        fit.quad_out(fa, fb, b, a, dark, (0, 0, 1))
    # 拱里的暗地板，口才有深度
    ta, ha, sa, ra = metrics(0.04)
    tb, hb, sb, rb = metrics(0.78)
    fit.quad_out(
        (-ha * 0.94, deck_side_y(ta) + 0.05, z_of(ta)),
        (ha * 0.94, deck_side_y(ta) + 0.05, z_of(ta)),
        (hb * 0.94, deck_side_y(tb) + 0.05, z_of(tb)),
        (-hb * 0.94, deck_side_y(tb) + 0.05, z_of(tb)),
        (0.018, 0.01, 0.008, 1),
        (0, 1, 0),
    )
    # 口沿：弯席的前沿加两根落到甲板的柱，剪影是拱门
    rim = mix((0.94, 0.80, 0.52, 1), CINNABAR, 0.10)
    prev = None
    for iu in range(seg_u + 1):
        q = pt(iu / seg_u, 0.0, 0.018)
        if prev:
            add_cyl(fit, prev, q, 0.055, rim, 6, caps=False)
        prev = q
    prev = None
    for iu in range(seg_u + 1):
        q = pt(iu / seg_u, 0.02, -0.05)
        if prev:
            add_cyl(fit, prev, q, 0.030, mix(CINNABAR, (0.30, 0.07, 0.04, 1), 0.2), 5, caps=False)
        prev = q
    for u in (0.0, 1.0):
        foot = pt(u, 0.0, 0.0)
        base_y = deck_side_y(t0) + 0.02
        add_cyl(fit, (foot[0], base_y, foot[2]), foot, 0.048, rim, 6, caps=False)
        back = pt(u, 1.0, 0.0)
        t_back = lerp(t0, t1, 1.0)
        add_cyl(
            fit,
            (back[0], deck_side_y(t_back) + 0.02, back[2]),
            back,
            0.036,
            mix(TEAK_DK, rim, 0.35),
            5,
            caps=False,
        )
    for u in (0.28, 0.50, 0.72):
        prev = None
        for iv in range(seg_v + 1):
            q = pt(u, iv / seg_v, 0.03)
            if prev:
                add_cyl(fit, prev, q, 0.010, BATTEN, 4, caps=False)
            prev = q


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
    """中线一处货舱口。围板压得很矮，口开着，舱里整块是黑的。
    十七度斜看仍能看见舱内，不是围板上的一粒黑点，也不是一叠箱子。"""
    z = z_of(t)
    y = deck_side_y(t) + 0.145
    dark = (0.010, 0.006, 0.004, 1)
    # 舱底盖住甲板弧，整块口都是暗的
    add_box(fit, (0, y - 0.02, z), (w * 0.96, 0.08, length * 0.96), dark)
    # 四壁留在围板里面，不冒出甲板。艉壁略高，艏舷相机正好看见这块暗面。
    wall_h = 0.20
    add_box(fit, (0, y + wall_h * 0.42, z - length * 0.46), (w * 0.90, wall_h, 0.05), dark)
    add_box(fit, (w * 0.46, y + 0.06, z), (0.045, 0.16, length * 0.88), dark)
    add_box(fit, (-w * 0.46, y + 0.06, z), (0.045, 0.16, length * 0.88), dark)
    add_box(fit, (0, y + 0.045, z + length * 0.46), (w * 0.88, 0.10, 0.045), dark)
    beam = 0.075
    # 朝相机的艏沿、左舷沿更矮，口才不被木框吃掉
    wood = mix(TEAK_LT, (0.92, 0.76, 0.48, 1), 0.62)
    add_box(fit, (0, y + 0.035, z + length * 0.5), (w + beam, 0.07, beam), wood)
    add_box(fit, (0, y + 0.055, z - length * 0.5), (w + beam, 0.11, beam), tint(wood, 0.86))
    add_box(fit, (w * 0.5, y + 0.05, z), (beam, 0.10, length), wood)
    add_box(fit, (-w * 0.5, y + 0.03, z), (beam, 0.06, length), wood)
    add_box(fit, (0, y + 0.09, z + length * 0.5 - 0.02), (w * 0.42, 0.028, 0.04), CINNABAR)


def add_low_cabin(fit):
    """左舷一块矮席棚。两根柱加一张弯席，口朝艏。
    不成箱子堆，也不升成第二层甲板。"""
    t = 0.515
    x = -1.36
    z = z_of(t)
    y = deck_side_y(t) + 0.12
    lx, lz = 0.58, 0.72
    wh = 0.36
    for dx, dz in ((-0.24, -0.32), (0.24, -0.32)):
        add_cyl(fit, (x + dx, y, z + dz), (x + dx, y + wh, z + dz), 0.032, TEAK_DK, 5)
    add_box(fit, (x, y + wh * 0.42, z - lz * 0.46), (lx * 0.92, wh * 0.84, 0.04), mix(TEAK_DK, TAR, 0.3))
    seg = 8
    roof_h = 0.22
    for i in range(seg):
        u0 = -0.5 + i / seg
        u1 = -0.5 + (i + 1) / seg

        def ry(u):
            return roof_h * math.cos(clamp(u, -0.5, 0.5) * math.pi) ** 1.15

        y0 = y + wh + ry(u0)
        y1 = y + wh + ry(u1)
        xa = x + u0 * lx
        xb = x + u1 * lx
        z0 = z - lz * 0.50
        z1 = z + lz * 0.48
        col = mix(ROOF, CINNABAR, 0.18 if i % 3 == 2 else 0.04)
        fit.quad_out((xa, y0, z0), (xb, y1, z0), (xb, y1, z1), (xa, y0, z1), col, (0, 1, 0))
        fit.quad_out(
            (xa, y0 - 0.03, z1), (xb, y1 - 0.03, z1),
            (xb, y1 - 0.03, z0), (xa, y0 - 0.03, z0),
            ROOF_DK, (0, -1, 0),
        )
    add_cyl(
        fit,
        (x - lx * 0.48, y + wh + 0.02, z + lz * 0.48),
        (x + lx * 0.48, y + wh + roof_h * 0.35, z + lz * 0.48),
        0.028,
        mix(TEAK_LT, (0.90, 0.74, 0.46, 1), 0.45),
        6,
        caps=False,
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
    """朱水线是一圈木线脚：上下收进缝，中间鼓出朱漆，不是平涂色带。"""
    # y, push, color — push 相对船壳向外
    profile = (
        (-0.020, 0.000, mix(TAR, TEAK_DK, 0.35)),
        (0.000, -0.028, (0.06, 0.032, 0.020, 1)),
        (0.018, 0.004, mix(CINNABAR, (0.18, 0.06, 0.04, 1), 0.55)),
        (0.040, 0.038, mix(CINNABAR, TEAK_DK, 0.25)),
        (0.068, 0.072, CINNABAR),
        (0.096, 0.086, mix(CINNABAR, (0.95, 0.55, 0.32, 1), 0.55)),
        (0.124, 0.058, CINNABAR),
        (0.146, 0.012, mix(CINNABAR, TEAK_DK, 0.40)),
        (0.162, -0.026, (0.07, 0.038, 0.022, 1)),
        (0.180, 0.010, mix(TEAK, (0.78, 0.60, 0.34, 1), 0.62)),
    )
    for i in range(len(stations) - 1):
        t0, z0, _r0 = stations[i]
        t1, z1, _r1 = stations[i + 1]
        wear = 0.94 + 0.08 * hsh(i * 3.7)
        for bi in range(len(profile) - 1):
            y_a, p_a, col_a = profile[bi]
            y_b, p_b, col_b = profile[bi + 1]
            ca = tint(col_a, wear)
            cb = tint(col_b, wear)

            def wp(t, z, y, push):
                return (x_at_y(t, y) + push, y, z)

            a = wp(t0, z0, y_a, p_a)
            b = wp(t1, z1, y_a, p_a)
            c = wp(t1, z1, y_b, p_b)
            d = wp(t0, z0, y_b, p_b)
            fit.quad_vc_out(a, b, c, d, ca, ca, cb, cb, (1, 0, 0))

            def mx(p):
                return (-p[0], p[1], p[2])

            fit.quad_vc_out(mx(a), mx(d), mx(c), mx(b), ca, cb, cb, ca, (-1, 0, 0))


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
    """贴着水线半宽，只在船外留一窄圈，不铺成比甲板还宽的椭圆。"""
    steps = 56
    layers = ((0.00, 0.78, 0.50), (0.78, 0.96, 0.32), (0.96, 1.03, 0.16), (1.03, 1.07, 0.05))
    y = -0.012

    def half_wl(t):
        return max(0.04, x_at_y(clamp(t, 0.012, 0.988), 0.02))

    def emit(z0, z1, h0, h1, alpha_scale):
        for f0, f1, alpha in layers:
            col = (0.012, 0.026, 0.040, alpha * alpha_scale)
            b0, b1 = h0 * f0, h1 * f0
            o0, o1 = h0 * f1, h1 * f1
            shadow.quad((b0, y, z0), (b1, y, z1), (o1, y, z1), (o0, y, z0), col)
            shadow.quad((-b0, y, z0), (-o0, y, z0), (-o1, y, z1), (-b1, y, z1), col)

    for i in range(steps):
        t0 = i / steps
        t1 = (i + 1) / steps
        emit(z_of(t0), z_of(t1), half_wl(t0), half_wl(t1), 1.0)
    # 艏艉只顺船尖收一短截，不另伸出一条方影子
    for i in range(4):
        f0 = i / 4
        f1 = (i + 1) / 4
        s0 = (1.0 - f0) ** 1.55
        s1 = (1.0 - f1) ** 1.55
        emit(
            z_of(0.0) + f0 * 0.16, z_of(0.0) + f1 * 0.16,
            half_wl(0.02) * s0, half_wl(0.02) * s1, 0.65 * s0,
        )
        emit(
            z_of(1.0) - f0 * 0.14, z_of(1.0) - f1 * 0.14,
            half_wl(0.98) * s0, half_wl(0.98) * s1, 0.55 * s0,
        )



def add_bomb(fit, c, r=0.16):
    """纸壳霹雳炮：圆球、绳箍、布捻。不是铁弹。尺寸要在宽景里仍是一颗球。"""
    body = mix((0.72, 0.52, 0.28, 1), (0.38, 0.18, 0.09, 1), hsh(c[0] * 4 + c[2] * 9))
    add_sphere(fit, c, r, body, 8, 6)
    # 两道绳箍，宽景里把球从桅杆圆件里分开
    add_cyl(fit, (c[0] - r * 0.92, c[1], c[2]), (c[0] + r * 0.92, c[1], c[2]), r * 0.18, ROPE, 6, caps=False)
    add_cyl(fit, (c[0], c[1], c[2] - r * 0.92), (c[0], c[1], c[2] + r * 0.92), r * 0.14, mix(ROPE, CINNABAR, 0.35), 6, caps=False)
    fuse = (c[0] + r * 0.12, c[1] + r * 1.45, c[2])
    add_cyl(fit, (c[0], c[1] + r * 0.78, c[2]), fuse, max(0.02, r * 0.18), (0.72, 0.16, 0.06, 1), 5)
    add_sphere(fit, fuse, max(0.035, r * 0.28), (0.95, 0.42, 0.12, 1), 5, 4)



def add_pounder(prim, center, axis, length, width, height, color):
    """石锤：一根压扁的方头石。长轴横在画面里，截面是倒角方，两端平切。不是球。"""
    d = vnorm(axis)
    side = vnorm(vcross(d, (0.0, 1.0, 0.0)))
    up = vnorm(vcross(side, d))
    hw = width * 0.5
    hh = height * 0.5
    # 八边倒角方。直棱，不收成圆。
    k = 0.86
    profile = [
        (hw, hh * k),
        (hw * k, hh),
        (-hw * k, hh),
        (-hw, hh * k),
        (-hw, -hh * k),
        (-hw * k, -hh),
        (hw * k, -hh),
        (hw, -hh * k),
    ]
    n = len(profile)

    def ring(t):
        c = vadd(center, vmul(d, t * length * 0.5))
        pts = []
        for sx, sy in profile:
            pts.append(vadd(c, vadd(vmul(side, sx), vmul(up, sy))))
        return pts, c

    r0, c0 = ring(-1.0)
    r1, c1 = ring(1.0)
    body = color
    end = tint(color, 0.62)
    for j in range(n):
        m = (j + 1) % n
        mid = vmul(vadd(vadd(r0[j], r0[m]), vadd(r1[j], r1[m])), 0.25)
        outward = vsub(mid, center)
        sy = profile[j][1] + profile[m][1]
        sx = abs(profile[j][0]) + abs(profile[m][0])
        if sy > 0.2 * sx:
            face = tint(body, 1.08)
        elif sy < -0.2 * sx:
            face = tint(body, 0.70)
        else:
            face = tint(body, 0.88)
        prim.quad_out(r0[j], r1[j], r1[m], r0[m], face, outward)
    def tri_out(a, b, c, col, outward):
        nrm = vcross(vsub(b, a), vsub(c, a))
        if vdot(nrm, outward) < 0.0:
            prim.tri(a, c, b, col, col, col)
        else:
            prim.tri(a, b, c, col, col, col)

    for j in range(n):
        m = (j + 1) % n
        tri_out(c0, r0[m], r0[j], end, vmul(d, -1.0))
        tri_out(c1, r1[j], r1[m], end, d)


def add_pai_gan(fit):
    """拍竿：艏部可落下的重木，头是横置的石锤。低相机下抬在艏柱上方，不扫帆。不是炮，也不是球。"""
    t = 0.06
    z = z_of(t)
    y0 = deck_side_y(t) + 0.16
    post_h = 1.95
    post_top = y0 + post_h
    add_cyl(fit, (0.0, y0, z), (0.0, post_top, z), 0.13, TEAK_DK, 8)
    add_box(fit, (0.0, y0 + 0.08, z), (0.58, 0.11, 0.36), mix(TEAK, TEAK_DK, 0.25))
    for s in (-1.0, 1.0):
        add_cyl(fit, (s * 0.24, y0 + 0.06, z), (s * 0.03, post_top - 0.10, z), 0.048, TEAK, 6, caps=False)
        add_cyl(fit, (s * 0.58, y0 + 0.04, z - 0.12), (s * 0.04, post_top - 0.32, z), 0.034, mix(TEAK, TEAK_DK, 0.4), 5, caps=False)
    pivot = (0.0, post_top - 0.06, z)
    # 更陡，头在艏柱上方的空里。略偏右舷，低相机看得到整颗石，不挡帆。
    ang = 1.12
    length = 2.15
    direction = vnorm((0.22, math.sin(ang), math.cos(ang) * 0.42))
    head = vadd(pivot, vmul(direction, length))
    # 木杆收到锤背，石头才是头
    spar_end = vadd(head, vmul(direction, -0.20))
    add_cyl(fit, pivot, spar_end, 0.16, mix(TEAK, TEAK_LT, 0.22), 8, caps=False)
    for f in (0.30, 0.62):
        band_c = tuple(lerp(pivot[k], head[k], f) for k in range(3))
        band_d = tuple(lerp(pivot[k], head[k], f + 0.045) for k in range(3))
        add_cyl(fit, band_c, band_d, 0.20, IRON, 8, caps=False)
    add_cyl(fit, pivot, (0.0, pivot[1], pivot[2] + 0.02), 0.18, IRON, 8)
    stone = (0.64, 0.60, 0.54, 1)
    # 长轴取 28°：己方艏舷和敌船艉舷两台相机都不顺着锤轴看，剪影是一条方石，不是圆。
    axis = (math.cos(math.radians(28.0)), 0.0, math.sin(math.radians(28.0)))
    add_pounder(fit, head, axis, 1.62, 0.52, 0.36, stone)
    # 杆插进锤背，铁箍卡住，不再有一根木从石心穿出去
    add_cyl(
        fit,
        vadd(head, vmul(direction, -0.28)),
        vadd(head, vmul(direction, -0.06)),
        0.20,
        mix(stone, IRON, 0.55),
        7,
        caps=False,
    )
    mid = tuple(lerp(pivot[k], head[k], 0.40) for k in range(3))
    for s in (-0.62, 0.62):
        rope(fit, mid, (s, y0 + 0.10, z - 0.06), 0.12, 0.020, ROPE, n=5)


def add_traction_trebuchet(fit):
    """旋风砲：左舷一架。臂朝外舷再扬起，低相机能看出是抛臂，不横过帆面。抛的是纸壳霹雳炮。"""
    t = 0.75
    x = -1.18
    z = z_of(t)
    y = deck_side_y(t) + 0.16
    h = 1.00
    half = 0.50
    leg_r = 0.078
    for s in (-half, half):
        add_cyl(fit, (x + s, y, z - 0.32), (x + s * 0.55, y + h, z - 0.06), leg_r, TEAK_DK, 6)
        add_cyl(fit, (x + s, y, z + 0.32), (x + s * 0.55, y + h, z - 0.06), leg_r, TEAK_DK, 6)
        add_cyl(fit, (x + s, y + 0.48, z - 0.18), (x + s, y + 0.48, z + 0.18), 0.042, TEAK, 5, caps=False)
    axle_l = (x - half * 0.55, y + h, z - 0.06)
    axle_r = (x + half * 0.55, y + h, z - 0.06)
    add_cyl(fit, axle_l, axle_r, 0.055, IRON, 7)
    add_box(fit, (x, y + 0.07, z), (1.05, 0.13, 0.78), TEAK)
    add_cyl(fit, (x - 0.10, y + 0.24, z - 0.62), (x - 0.10, y + 0.24, z + 0.10), 0.060, TEAK_DK, 6)
    for k in range(3):
        zz = z - 0.46 + k * 0.24
        add_cyl(fit, (x - 0.62, y + 0.24, zz), (x + 0.22, y + 0.24, zz), 0.032, mix(TEAK, TEAK_LT, 0.3), 5, caps=False)
    # 臂：向上、向外舷、略向艉。不指向相机，侧面能看出是一根抛臂。
    pivot = (x, y + h, z - 0.06)
    # 臂几乎朝外舷扬起。近景己方和近景敌船都能看见整根臂，又不扫到帆。
    direction = vnorm((-0.94, 0.34, -0.08))
    short_l, long_l = 0.48, 2.30

    def arm_out(dist):
        return vadd(pivot, vmul(direction, dist))

    short = arm_out(-short_l)
    long = arm_out(long_l)
    add_cyl(fit, short, long, 0.145, mix(TEAK, TEAK_LT, 0.18), 7, caps=False)
    for f in (0.34, 0.68):
        a = arm_out(lerp(-short_l, long_l, f))
        b = arm_out(lerp(-short_l, long_l, f + 0.045))
        add_cyl(fit, a, b, 0.175, IRON, 6, caps=False)
    for k in range(4):
        rope(
            fit, short,
            (x + 0.42, y + 0.12, z + (k - 1.5) * 0.13),
            0.08, 0.016, ROPE, n=4,
        )
    pouch = vadd(long, (-0.04, -0.55, -0.02))
    rope(fit, long, (pouch[0], pouch[1] + 0.20, pouch[2]), 0.05, 0.016, ROPE, n=3)
    rope(fit, vadd(long, (0.0, 0.0, 0.08)), pouch, 0.03, 0.014, ROPE, n=3)
    add_bomb(fit, pouch, 0.38)
    crib = (x + 0.05, y + 0.22, z + 0.70)
    add_box(fit, (crib[0], y + 0.08, crib[2]), (0.55, 0.14, 0.42), TEAK_DK)
    for dx, dz in ((-0.12, -0.08), (0.12, 0.06)):
        add_bomb(fit, (crib[0] + dx, crib[1] + 0.04, crib[2] + dz), 0.15)



def deck_surface(t, u):
    ring = section_pts(max(t, 0.012))
    b = ring[-3][0] * 0.90
    y = ring[-3][1] + 0.012 + 0.072 * (1.0 - u * u)
    return (u * b, y, z_of(clamp(t, 0.0, 1.0)))


def add_deck_scarfs(deck):
    """少数斜口接：两截板错叠，斜缝里一条油灰。不在每条板上切齿。"""
    caulk = (0.02, 0.012, 0.008, 1)
    wood_a = (0.74, 0.54, 0.32, 1)
    wood_b = (0.36, 0.22, 0.12, 1)
    # 左舷露天甲板，斜俯近景看得到，不塞进帆和箭槽底下
    spots = (
        (0.34, -0.55),
        (0.50, -0.28),
        (0.63, -0.58),
        (0.74, -0.22),
    )
    for ti, (t, u) in enumerate(spots):
        x, y, z = deck_surface(t, u)
        y += 0.045
        w = 0.20
        wood_l = wood_a if ti % 2 == 0 else wood_b
        wood_r = wood_b if ti % 2 == 0 else wood_a

        def diag_z(xx, z=z, x=x, w=w):
            f = (xx - (x - w)) / (2.0 * w)
            return z - 0.08 + f * 0.28

        z_aft = z - 0.62
        z_fore = z + 0.58
        aft_a = (x - w, y, z_aft)
        aft_b = (x + w, y, z_aft)
        aft_c = (x + w, y, diag_z(x + w) - 0.016)
        aft_d = (x - w, y, diag_z(x - w) - 0.016)
        deck.quad_out(aft_a, aft_d, aft_c, aft_b, wood_l, (0, 1, 0))
        lift = 0.014
        fore_a = (x - w, y + lift, diag_z(x - w) + 0.016)
        fore_b = (x + w, y + lift, diag_z(x + w) + 0.016)
        fore_c = (x + w, y + lift, z_fore)
        fore_d = (x - w, y + lift, z_fore)
        deck.quad_out(fore_a, fore_d, fore_c, fore_b, wood_r, (0, 1, 0))
        gap_a = (x - w, y - 0.008, diag_z(x - w) - 0.014)
        gap_b = (x + w, y - 0.008, diag_z(x + w) - 0.014)
        gap_c = (x + w, y - 0.008, diag_z(x + w) + 0.014)
        gap_d = (x - w, y - 0.008, diag_z(x - w) + 0.014)
        deck.quad_out(gap_a, gap_d, gap_c, gap_b, caulk, (0, 1, 0))
        cheek = (0.05, 0.028, 0.016, 1)
        deck.quad_out(aft_d, (aft_d[0], aft_d[1] - 0.016, aft_d[2]), (aft_c[0], aft_c[1] - 0.016, aft_c[2]), aft_c, cheek, (0, 0, 1))
        deck.quad_out(fore_a, fore_b, (fore_b[0], fore_b[1] - 0.012, fore_b[2]), (fore_a[0], fore_a[1] - 0.012, fore_a[2]), cheek, (0, 0, -1))


def add_stem_detail(fit):
    """艏柱贴着尖端。板头是壳上的薄片，跟着舷弧，不探出成方块。"""
    ring = section_pts(0.02)
    z0 = z_of(0.0)
    idxs = []
    for frac in (0.22, 0.42, 0.62, 0.80, 1.0):
        j = int(round(frac * (len(ring) - 1)))
        if j not in idxs:
            idxs.append(j)
    samples = []
    for j in idxs:
        y = ring[j][1]
        f = j / (len(ring) - 1)
        samples.append((y, z0 + 0.055 + 0.18 * f))
    for i in range(len(samples) - 1):
        y0, z_a = samples[i]
        y1, z_b = samples[i + 1]
        scarf = i in (1, 3)
        jog = 0.04 if scarf else 0.0
        col = (0.16, 0.09, 0.05, 1) if scarf else mix(TEAK_LT, (0.78, 0.58, 0.34, 1), 0.35)
        side = 0.035 if scarf else 0.0
        add_cyl(fit, (side, y0, z_a + jog), (-side * 0.3, y1, z_b), 0.032 if scarf else 0.048, col, 8, caps=False)
        if scarf:
            add_box(
                fit,
                (0.0, (y0 + y1) * 0.5, (z_a + z_b) * 0.5 + 0.04),
                (0.10, 0.04, 0.05),
                (0.03, 0.015, 0.009, 1),
            )
    for s in (-1.0, 1.0):
        for t in (0.028, 0.046, 0.064, 0.084):
            ring_t = section_pts(t)
            z = z_of(t)
            for frac in (0.55, 0.72, 0.88):
                j = int(round(frac * (len(ring_t) - 1)))
                x, y = ring_t[j]
                add_box(
                    fit,
                    (s * x * 0.96, y, z),
                    (0.045, 0.032, 0.07),
                    mix(TEAK_LT, TEAK, 0.25),
                )


def add_fire_arrows(fit, t, x):
    """火箭：四支分开的箭。箭杆、中段红纸筒、箭簇、尾羽，槽边一张弓。
    宽景里要能认出是箭，不是一排红点。不是扇面，不是火门枪。"""
    z = z_of(t)
    y = deck_side_y(t) + 0.20
    inward = -1.0 if x > 0.0 else 1.0
    add_box(fit, (x, y, z), (0.42, 0.10, 0.78), TEAK)
    add_box(fit, (x, y + 0.18, z - 0.36), (0.42, 0.28, 0.07), TEAK_DK)
    add_box(fit, (x, y + 0.16, z + 0.36), (0.42, 0.22, 0.06), TEAK)
    add_box(fit, (x - inward * 0.16, y + 0.12, z), (0.06, 0.18, 0.78), mix(TEAK_DK, TEAK, 0.3))
    shaft = (0.94, 0.91, 0.84, 1)
    tube = (0.82, 0.07, 0.04, 1)
    fletch = (0.72, 0.12, 0.06, 1)
    n_arr = 4
    # 向外舷倾，红纸筒落在帆的空档里，不插进席面，也不伸到拍竿头上
    outward = -inward
    for i in range(n_arr):
        spread = (i - (n_arr - 1) * 0.5) * 0.16
        zz = z + spread
        tail = (x, y + 0.16, zz)
        head = (x + outward * 0.22, y + 1.48, zz)
        add_cyl(fit, tail, head, 0.042, shaft, 6, caps=False)
        a = tuple(lerp(tail[k], head[k], 0.40) for k in range(3))
        b = tuple(lerp(tail[k], head[k], 0.68) for k in range(3))
        add_cyl(fit, a, b, 0.11, tube, 7, caps=False)
        for frac in (0.40, 0.68):
            c0 = tuple(lerp(tail[k], head[k], frac) for k in range(3))
            c1 = tuple(lerp(tail[k], head[k], frac + 0.035) for k in range(3))
            add_cyl(fit, c0, c1, 0.108, ROPE, 6, caps=False)
        tip = tuple(lerp(tail[k], head[k], 0.90) for k in range(3))
        add_cyl(fit, tip, head, 0.030, (0.16, 0.15, 0.13, 1), 5, caps=False)
        add_sphere(fit, head, 0.058, (0.95, 0.45, 0.12, 1), 6, 4)
        feather = tuple(lerp(tail[k], head[k], 0.10) for k in range(3))
        add_box(fit, feather, (0.022, 0.22, 0.12), fletch)
        add_box(fit, feather, (0.12, 0.22, 0.022), fletch)
    bow_z = z + 0.50
    pts = []
    for i in range(9):
        u = i / 8
        pts.append((
            x - inward * 0.02,
            y + 0.04 + math.sin(u * math.pi) * 0.95,
            bow_z + (u - 0.5) * 0.08,
        ))
    for i in range(8):
        add_cyl(fit, pts[i], pts[i + 1], 0.042, mix(TEAK_DK, TEAK, 0.2), 5, caps=False)
    rope(fit, pts[0], pts[-1], 0.05, 0.014, ROPE, n=5)


def add_song_weapons(fit):
    add_pai_gan(fit)
    add_traction_trebuchet(fit)
    # 艏舷空档、两帆之间的左舷。17° 近景看得到红白箭束，不挡绛帆，不挡石锤。
    add_fire_arrows(fit, 0.075, -0.50)
    add_fire_arrows(fit, 0.355, -1.15)


def station_ts():
    """沿船长均匀多切。弯已经是连续函数，站距均匀才不会在拼接处又切出棱。"""
    n = 120
    return [i / n for i in range(n + 1)]


def build():
    hull = Prim("Hull", "Wood")
    deck = Prim("Deck", "Wood")
    fit = Prim("Fittings", "Wood")
    sail = Prim("Sails", "Sail")
    shadow = Prim("Shadow", "Shadow")

    stations = []
    for t in station_ts():
        t_use = max(t, 1e-4)
        ring = section_pts(t_use)
        z = z_of(t)
        stations.append((t, z, ring))
    nst = len(stations)

    for i in range(nst - 1):
        t0, z0, r0 = stations[i]
        t1, z1, r1 = stations[i + 1]
        nring = len(r0)
        along = (t0 + t1) * 0.5
        for j in range(nring - 1):
            col = wood_at(along, j, nring, along)
            # 缝只留在颜色上。壳是同一张弧，不再一板一个鼓面。
            if j % 5 == 0:
                col = mix(col, (0.08, 0.04, 0.022, 1), 0.55)
            a = (r0[j][0], r0[j][1], z0)
            b = (r1[j][0], r1[j][1], z1)
            c = (r1[j + 1][0], r1[j + 1][1], z1)
            d = (r0[j + 1][0], r0[j + 1][1], z0)
            hull.quad_out(a, b, c, d, col, (max(a[0], 0.02), 0.25, 0.0))
            hull.quad_out(
                (-a[0], a[1], a[2]),
                (-d[0], d[1], d[2]),
                (-c[0], c[1], c[2]),
                (-b[0], b[1], b[2]),
                col,
                (-max(a[0], 0.02), 0.25, 0.0),
            )

    def round_end(ring, z_start, sign, steps):
        """sign>0 艏向前收到尖，sign<0 艉向后收到一条弯尾封。端头是弧，不是一块板。"""
        prev = [(x, y, z_start) for x, y in ring]
        nring = len(ring)
        for s in range(1, steps + 1):
            f = s / steps
            e = f * f * (3.0 - 2.0 * f)
            nxt = []
            for j, (x, y) in enumerate(ring):
                hf = j / (nring - 1)
                if sign > 0:
                    shrink = (1.0 - e) ** 0.80
                    z = z_start + (0.015 + 0.22 * (hf ** 0.75)) * e
                    yy = y + 0.04 * hf * e
                    xx = 0.0 if s == steps else x * shrink
                else:
                    shrink = 1.0 - 0.38 * e
                    z = z_start - (0.02 + 0.18 * (hf ** 0.70)) * e
                    yy = y + 0.03 * hf * e
                    xx = x * shrink
                nxt.append((xx, yy, z))
            for j in range(nring - 1):
                col = wood_at(0.015 if sign > 0 else 0.985, j, nring)
                a, b = prev[j], prev[j + 1]
                d, c = nxt[j], nxt[j + 1]
                hull.quad_out(a, b, c, d, col, (max(abs(a[0]), 0.02), 0.2, float(sign)))
                hull.quad_out(
                    (-a[0], a[1], a[2]),
                    (-d[0], d[1], d[2]),
                    (-c[0], c[1], c[2]),
                    (-b[0], b[1], b[2]),
                    col,
                    (-max(abs(a[0]), 0.02), 0.2, float(sign)),
                )
            prev = nxt
        if sign < 0:
            port = [(-pp[0], pp[1], pp[2]) for pp in reversed(prev)]
            full = port + prev[1:]
            rows = [full]
            extra = 7
            for s in range(1, extra + 1):
                f = s / extra
                row = []
                for q in full:
                    row.append((q[0] * (1.0 - 0.22 * f), q[1] - 0.01 * f, q[2] - 0.055 * math.sin(f * math.pi * 0.5)))
                rows.append(row)
            for ri in range(len(rows) - 1):
                row_a, row_b = rows[ri], rows[ri + 1]
                for j in range(len(row_a) - 1):
                    a, b = row_a[j], row_a[j + 1]
                    c, d = row_b[j + 1], row_b[j]
                    col = wood_at(0.99, j % nring, nring)
                    hull.quad_out(a, b, c, d, col, (0.0, 0.15, -1.0))

    round_end(stations[0][2], stations[0][1], 1, 16)
    round_end(stations[-1][2], stations[-1][1], -1, 14)

    hull.smooth()

    caulk = (0.04, 0.022, 0.013, 1)
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
            du = 0.070 / max((b0 + b1) * 0.5, 0.2)
            ua, ub = u0 + du * 0.35, u1 - du * 0.35
            tone = 0.84 + 0.20 * hsh(k * 17.3)
            grain = 0.93 + 0.09 * hsh(k * 9.2 + (i // 6) * 2.3)
            # 一站宽的错缝，不是整段甲板涂黑
            # 错缝仍落在原来均匀 52 站的那些 t 上，只取最近的一站，不因加密变成一排密缝。
            phase = (k * 4 + 3) % 15
            iv = int(round(t0 * 51.0))
            butt = False
            if iv % 15 == phase and 3 < iv < 46:
                seam_t = iv / 51.0
                prev_t = stations[i - 1][0] if i else -1.0
                butt = abs(t0 - seam_t) <= abs(prev_t - seam_t) and abs(t0 - seam_t) < abs(t1 - seam_t)
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
                drop = 0.034
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
            # 横缝：板头这一站沟里填油灰
            if butt:
                cz0 = lerp(z0, z1, 0.36)
                cz1 = lerp(z0, z1, 0.64)
                qa = Dp(ua, b0, y0, cz0, 0.028)
                qb = Dp(ua, b1, y1, cz1, 0.028)
                qc = Dp(ub, b1, y1, cz1, 0.028)
                qd = Dp(ub, b0, y0, cz0, 0.028)
                deck.quad_out(qa, qd, qc, qb, (0.028, 0.014, 0.009, 1), (0, 1, 0))
            # 隔几档一颗木钉。少而粗，近景才不是光板
            ivn = int(round(t0 * 51.0))
            nail_here = False
            if k % 3 == 1 and ivn % 9 == (k * 2) % 9 and 4 < ivn < 45:
                seam_t = ivn / 51.0
                prev_t = stations[i - 1][0] if i else -1.0
                nail_here = abs(t0 - seam_t) <= abs(prev_t - seam_t) and abs(t0 - seam_t) < abs(t1 - seam_t)
            if nail_here:
                um = (ua + ub) * 0.5
                nail = Dp(um, (b0 + b1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5, -0.002)
                add_cyl(
                    deck,
                    (nail[0], nail[1] - 0.006, nail[2]),
                    (nail[0], nail[1] + 0.018, nail[2]),
                    0.018,
                    (0.11, 0.065, 0.035, 1),
                    5,
                )

    # 三处货舱口分开落在中线上：艏、舯、艉。口要大，十七度才看得见舱内。不盖第二层甲板。
    add_hatch(fit, 0.190, 1.42, 1.45)
    add_hatch(fit, 0.430, 1.52, 1.72)
    add_hatch(fit, 0.690, 1.18, 1.82)
    add_low_cabin(fit)
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

    # 帆脚抬高、后缘收到桅后，中线三处舱口和艉拱口才不被席面挡住。仍是一整张席。
    junk_sail(
        sail, fit,
        deck_side_y(0.30) + 1.55, deck_side_y(0.30) + 3.55,
        z_of(0.17), z_of(0.34), z_of(0.20), z_of(0.33),
        camber=1.16, n_bat=7, n_u=16,
    )
    junk_sail(
        sail, fit,
        deck_side_y(0.56) + 1.50, deck_side_y(0.56) + 4.70,
        z_of(0.46), z_of(0.63), z_of(0.49), z_of(0.61),
        camber=1.46, n_bat=9, n_u=18,
    )
    # 整张席平滑法线，低模的分面才不会被光切成一层层板。不叠背面。
    sail.smooth()

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

    last_nail_z = None
    for t, z, ring in stations:
        if t < 0.08 or t > 0.92:
            continue
        if last_nail_z is not None and abs(z - last_nail_z) < 0.55:
            continue
        last_nail_z = z
        x = ring[-2][0]
        y = ring[-4][1]
        add_box(fit, (x, y, z), (0.045, 0.035, 0.06), (0.05, 0.035, 0.028, 1))
        add_box(fit, (-x, y, z), (0.045, 0.035, 0.06), (0.05, 0.035, 0.028, 1))

    add_waterline(fit, stations)
    add_gunwale(fit, stations)
    add_deck_scarfs(deck)
    add_stem_detail(fit)
    add_song_weapons(fit)

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
