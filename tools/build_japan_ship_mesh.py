#!/usr/bin/env python3
"""十三世纪日本准构造船 — 商船 / 漕战舟，同一条壳（glTF）。

石井谦治据《北野天神缘起》承久本复原：楠木挖空的圆底、上面接舷侧板、
干舷极低。舱内是挖空的暗槽和一圈厚舷缘，不铺甲板条。外壳仍是一根圆木，只有浅锛口。
一根桅、一张软筵（苇丝在着色器里，网格上不放横竹）。漕战去掉小舱、六对小尖叶桨伸出舷外（叶长约一倍半干舷）。
商船只收两三片同样的小叶。不是安宅船，没有硬篷横竹，也没有宋式正中尾舵。

用法：python3 tools/build_japan_ship_mesh.py
产物：assets/ships/japan_quasi.glb
      assets/ships/japan_quasi_war.glb
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "ships"

L = 7.70
HALF = L * 0.5
BEAM = 1.02  # 半宽
N_ST = 72
N_ARC = 16  # 含龙骨与肩。圆底靠这一圈，不是多边形。
N_UP = 4    # 肩以上的板，含舷缘。干舷只有一掌，板不能多。


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


def scale_c(c, s):
    return tuple(clamp(ch * s, 0, 1) if i < 3 else ch for i, ch in enumerate(c))


# 楠木挖底、桧板、筵、麻绳。不涂宋船的水线朱。
CAMPHOR = (0.40, 0.20, 0.09, 1)
CAMPHOR_LT = (0.52, 0.28, 0.13, 1)
CAMPHOR_WET = (0.16, 0.08, 0.045, 1)
HINOKI = (0.82, 0.68, 0.44, 1)
HINOKI_LT = (0.90, 0.78, 0.55, 1)
HINOKI_DK = (0.62, 0.46, 0.26, 1)
WALE_C = (0.16, 0.09, 0.055, 1)
SEAM = (0.10, 0.055, 0.03, 1)
RAIL = (0.40, 0.24, 0.12, 1)
DECK = (0.66, 0.49, 0.30, 1)
DECK_DK = (0.42, 0.28, 0.16, 1)
HOLD = (0.08, 0.05, 0.035, 1)
STRAW = (0.78, 0.62, 0.34, 1)
STRAW_LT = (0.90, 0.76, 0.46, 1)
STRAW_DK = (0.48, 0.34, 0.16, 1)
ROPE = (0.48, 0.34, 0.18, 1)
ROPE_DK = (0.30, 0.20, 0.10, 1)
SKIN = (0.72, 0.52, 0.38, 1)
HAIR = (0.08, 0.06, 0.05, 1)
BARK = (0.34, 0.20, 0.10, 1)


def z_of(t: float) -> float:
    return HALF - t * L


def keel_y(t: float) -> float:
    # 舯部圆底深，两端缓缓抬起。不要在艏下突然劈出一块。
    tt = clamp(t, 0.0, 1.0)
    s = math.sin(math.pi * tt) ** 0.85
    base = lerp(0.02, -0.66, s)
    bow = 1.0 - smoothstep(0.0, 0.18, tt)
    stern = smoothstep(0.82, 1.0, tt)
    return base + 0.20 * (bow + stern)


def shoulder_y(t: float) -> float:
    body = math.sin(math.pi * clamp(t, 0.0, 1.0)) ** 0.72
    y = keel_y(t) + lerp(0.18, 0.70, body)
    return y


def gunwale_y(t: float) -> float:
    # 干舷只有一掌。舷墙不盖住圆底。
    return shoulder_y(t) + 0.11


def half_beam(t: float) -> float:
    s = math.sin(math.pi * clamp(t, 0.0, 1.0)) ** 0.58
    bow = 0.62 + 0.38 * smoothstep(0.0, 0.14, t)
    stern = 1.0 - 0.06 * smoothstep(0.88, 1.0, t)
    return BEAM * max(0.07, (s ** 0.88) * bow * stern)


def deck_base(t: float) -> float:
    """旧甲板高度。桅、筵、茅屋仍用它，免得舱挖深之后帆和屋跟着掉下去。"""
    return shoulder_y(t) + 0.012


def gunwale_x(t: float) -> float:
    """和 section_ring 舷缘外皮同一处。"""
    return half_beam(t) * 0.965 * 0.97


def rim_inset(t: float) -> float:
    """厚舷缘。两端随船收窄，舯部留一掌多的实木边，不是薄甲板压条。"""
    gx = gunwale_x(t)
    body = math.sin(math.pi * clamp(t, 0.0, 1.0)) ** 0.50
    want = lerp(0.045, 0.24, body)
    return min(gx * 0.42, want)


def hollow_col(t: float, _j: float, y: float) -> tuple:
    """挖出来的楠木内膛。下腹几乎一色的暗，靠舷缘才露出木色。不要沿船长分成条。"""
    lip = gunwale_y(t)
    bottom = keel_y(t) + 0.12
    up = smoothstep(bottom + 0.22, lip, y)
    belly = (0.07, 0.040, 0.025, 1)
    wall = mix(CAMPHOR, CAMPHOR_LT, 0.20)
    base = mix(belly, wall, up)
    base = scale_c(base, 0.62 + 0.40 * up)
    grain = 0.97 + 0.04 * hsh(t * 11.0 + y * 6.0)
    return scale_c(base, grain)


SHOULDER_I = N_ARC - 1


def section_ring(t: float):
    """右舷，从龙骨到舷缘。(x, y)。圆底是一段圆弧，不是折线船。"""
    bh = half_beam(t)
    keel = keel_y(t)
    sh = shoulder_y(t)
    gw = gunwale_y(t)
    xs = bh * 0.965
    dy = max(0.12, sh - keel)
    r = (xs * xs + dy * dy) / (2.0 * dy)
    cy = keel + r
    ang_sh = math.atan2(sh - cy, xs)
    pts = []
    for i in range(N_ARC):
        a = lerp(-math.pi * 0.5, ang_sh, i / (N_ARC - 1))
        x = max(0.0, r * math.cos(a))
        y = cy + r * math.sin(a)
        pts.append((x, y))
    pts[-1] = (xs, sh)
    for i in range(1, N_UP + 1):
        u = i / N_UP
        # 舷板几乎直上，最宽处在挖底的肩。圆肚子从侧面露出来。
        tumble = 1.0 - 0.03 * u
        y = lerp(sh, gw, u)
        pts.append((xs * tumble, y))
    return pts


def dugout_col(y, t):
    wet = smoothstep(0.06, -0.45, y)
    base = mix(CAMPHOR_LT, CAMPHOR_WET, wet * 0.92)
    base = mix(base, CAMPHOR, 0.35)
    grain = 0.93 + 0.09 * hsh(t * 37.0 + y * 4.0)
    end = 1.0 - 0.08 * max(smoothstep(0.12, 0.0, t), smoothstep(0.88, 1.0, t))
    return scale_c(base, grain * end)


def strake_col(t, band):
    # 相邻舷板明暗错开，平接，不是叠接。
    tone_b = 0.78 + 0.22 * ((band * 2) % 3) / 2.0
    base = mix(HINOKI_DK, HINOKI_LT, tone_b * 0.55 + 0.2)
    plank = int(t * 9.0 + band * 2.2)
    tone = 0.88 + 0.16 * hsh(plank * 19.1 + band * 6.7)
    local = (t * 9.0 + band * 2.2) - plank
    butt = 0.62 if local < 0.045 else 1.0
    return scale_c(base, tone * butt)


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

    def tri(self, a, b, c, ca, cb, cc, uva=(0, 0), uvb=(0, 0), uvc=(0, 0)):
        n = vnorm(vcross(vsub(b, a), vsub(c, a)))
        ia = self._push(a, n, ca, uva)
        ib = self._push(b, n, cb, uvb)
        ic = self._push(c, n, cc, uvc)
        self.idx.extend((ia, ib, ic))

    def quad(self, a, b, c, d, color, uva=(0, 0), uvb=(0, 0), uvc=(0, 0), uvd=(0, 0)):
        self.tri(a, b, c, color, color, color, uva, uvb, uvc)
        self.tri(a, c, d, color, color, color, uva, uvc, uvd)

    def quad_vc(self, a, b, c, d, ca, cb, cc, cd, uva=(0, 0), uvb=(0, 0), uvc=(0, 0), uvd=(0, 0)):
        self.tri(a, b, c, ca, cb, cc, uva, uvb, uvc)
        self.tri(a, c, d, ca, cc, cd, uva, uvc, uvd)

    def quad_out(self, a, b, c, d, color, outward, uva=(0, 0), uvb=(0, 0), uvc=(0, 0), uvd=(0, 0)):
        n = vcross(vsub(b, a), vsub(c, a))
        if vlen(n) < 1e-8:
            return
        if vdot(n, outward) < 0.0:
            self.quad(a, d, c, b, color, uva, uvd, uvc, uvb)
        else:
            self.quad(a, b, c, d, color, uva, uvb, uvc, uvd)

    def tri_n(self, a, b, c, ca, cb, cc, na, nb, nc, uva=(0, 0), uvb=(0, 0), uvc=(0, 0)):
        ia = self._push(a, na, ca, uva)
        ib = self._push(b, nb, cb, uvb)
        ic = self._push(c, nc, cc, uvc)
        self.idx.extend((ia, ib, ic))

    def quad_n(self, a, b, c, d, ca, cb, cc, cd, na, nb, nc, nd, uva=(0, 0), uvb=(0, 0), uvc=(0, 0), uvd=(0, 0)):
        self.tri_n(a, b, c, ca, cb, cc, na, nb, nc, uva, uvb, uvc)
        self.tri_n(a, c, d, ca, cc, cd, na, nc, nd, uva, uvc, uvd)

    def smooth(self):
        acc = {}
        for i, p in enumerate(self.pos):
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
            acc[key] = vadd(acc.get(key, (0, 0, 0)), self.nrm[i])
        for i, p in enumerate(self.pos):
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
            self.nrm[i] = vnorm(acc[key])

def add_box(prim: Prim, center, size, color, yaw=0.0):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cy, sy = math.cos(yaw), math.sin(yaw)

    def corner(x, y, z):
        xr = x * cy + z * sy
        zr = -x * sy + z * cy
        return vadd(center, (xr, y, zr))

    pts = []
    for xi in (-1, 1):
        for yi in (-1, 1):
            for zi in (-1, 1):
                pts.append(corner(xi * hx, yi * hy, zi * hz))

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
        prim.quad(pts[f[0]], pts[f[1]], pts[f[2]], pts[f[3]], color)


def add_cyl(prim: Prim, p0, p1, r, color, n=8, caps=True):
    axis = vsub(p1, p0)
    length = vlen(axis)
    if length < 1e-5 or r <= 0:
        return
    d = vnorm(axis)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.88 else (1.0, 0.0, 0.0)
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


def rope(prim, a, b, sag, rad, color, n=7):
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((
            lerp(a[0], b[0], t),
            lerp(a[1], b[1], t) - sag * math.sin(math.pi * t),
            lerp(a[2], b[2], t),
        ))
    for i in range(n):
        add_cyl(prim, pts[i], pts[i + 1], rad, color, 5, caps=False)

def loft(prim, stations, j0, j1, color_fn, outward_sign=1.0):
    for i in range(len(stations) - 1):
        t0, z0, r0 = stations[i]
        t1, z1, r1 = stations[i + 1]
        for j in range(j0, j1):
            a = (r0[j][0], r0[j][1], z0)
            d = (r0[j + 1][0], r0[j + 1][1], z0)
            b = (r1[j][0], r1[j][1], z1)
            c = (r1[j + 1][0], r1[j + 1][1], z1)
            tm = (t0 + t1) * 0.5
            ym = (a[1] + d[1]) * 0.5
            col = color_fn(tm, j, ym)
            mid = vmul(vadd(vadd(a, b), vadd(c, d)), 0.25)
            outward = (mid[0] * outward_sign, 0.05, 0.0)
            u0, u1 = t0, t1
            v0, v1 = j / 20.0, (j + 1) / 20.0
            prim.quad_out(a, b, c, d, col, outward, (u0, v0), (u1, v0), (u1, v1), (u0, v1))

            def mx(p):
                return (-p[0], p[1], p[2])

            prim.quad_out(
                mx(a), mx(d), mx(c), mx(b), col, (-mid[0] * outward_sign, 0.05, 0.0),
                (u0, v0), (u0, v1), (u1, v1), (u1, v0),
            )


def cap_end(prim, ring, z, tip, color_fn, t, bow=True):
    outward = (0.0, 0.15, 1.0 if bow else -1.0)
    for j in range(len(ring) - 1):
        a = (ring[j][0], ring[j][1], z)
        b = (ring[j + 1][0], ring[j + 1][1], z)
        col = color_fn(t, j, (a[1] + b[1]) * 0.5)
        n = vcross(vsub(b, a), vsub(tip, a))
        if vlen(n) < 1e-8:
            continue
        if vdot(n, outward) < 0.0:
            prim.tri(a, tip, b, col, col, col)
        else:
            prim.tri(a, b, tip, col, col, col)
        am = (-a[0], a[1], a[2])
        bm = (-b[0], b[1], b[2])
        n2 = vcross(vsub(am, bm), vsub(tip, bm))
        if vdot(n2, outward) < 0.0:
            prim.tri(bm, tip, am, col, col, col)
        else:
            prim.tri(bm, am, tip, col, col, col)


def section_outward(ring, j):
    a = ring[j]
    b = ring[min(j + 1, len(ring) - 1)]
    dx, dy = b[0] - a[0], b[1] - a[1]
    nx, ny = dy, -dx
    if nx * (a[0] + b[0]) < 0.0:
        nx, ny = -nx, -ny
    ln = math.hypot(nx, ny) or 1.0
    return nx / ln, ny / ln


def inner_section(t: float):
    """外皮沿内法线收一圈，得到挖槽。整段都在壳里面，槽底是圆的。"""
    ring = section_ring(t)
    n = len(ring)
    pts = []
    for j, (x, y) in enumerate(ring):
        frac = j / (n - 1)
        if j == 0:
            pts.append((0.0, y + 0.13))
            continue
        if j == n - 1:
            pts.append((max(0.02, x - rim_inset(t)), y - 0.006))
            continue
        nx, ny = section_outward(ring, j)
        thick = lerp(0.13, 0.18, frac ** 1.1)
        px = max(0.0, x - nx * thick)
        py = y - ny * thick
        py = max(py, ring[0][1] + 0.11)
        pts.append((px, py))
    return pts


def floor_at(t: float, x: float) -> float:
    pts = inner_section(t)
    ax = abs(x)
    best = pts[0][1]
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        lo, hi = (x0, x1) if x0 <= x1 else (x1, x0)
        if lo - 1e-4 <= ax <= hi + 1e-4 and abs(x1 - x0) > 1e-6:
            u = clamp((ax - x0) / (x1 - x0), 0.0, 1.0)
            return lerp(y0, y1, u)
        best = y1
    return best


def add_dugout_grooves(prim, stations):
    """挖底上的纵向锛痕。还是一根木头，不是一块块舷板。"""
    js = [3, 6, 9, 12]
    for j in js:
        if j >= SHOULDER_I:
            continue
        for i in range(3, len(stations) - 4):
            t0, z0, r0 = stations[i]
            t1, z1, r1 = stations[i + 1]
            if t0 < 0.06 or t0 > 0.94:
                continue

            def gp(ring, z, lift):
                x, y = ring[j]
                nx, ny = section_outward(ring, j)
                return (x + nx * 0.010, y + ny * 0.010 + lift, z)

            a, d = gp(r0, z0, -0.018), gp(r0, z0, 0.018)
            b, c = gp(r1, z1, -0.018), gp(r1, z1, 0.018)
            col = scale_c(CAMPHOR_WET, 0.72 + 0.08 * hsh(t0 * 11 + j))
            prim.quad_out(a, b, c, d, col, (a[0], 0.0, 0.0))
            ma = (-a[0], a[1], a[2])
            mb = (-b[0], b[1], b[2])
            mc = (-c[0], c[1], c[2])
            md = (-d[0], d[1], d[2])
            prim.quad_out(ma, md, mc, mb, col, (-a[0], 0.0, 0.0))


def add_proud_strakes(prim, stations):
    """肩以上的桧板：每条板中部鼓出，缝里露出深色嵌缝。平接，不叠成维京船。"""
    j0 = SHOULDER_I
    j1 = len(stations[0][2]) - 1
    for j in range(j0, j1):
        band = j - j0
        for i in range(len(stations) - 1):
            t0, z0, r0 = stations[i]
            t1, z1, r1 = stations[i + 1]

            def edge(ring, z, frac):
                a = ring[j]
                b = ring[j + 1]
                x = lerp(a[0], b[0], frac)
                y = lerp(a[1], b[1], frac)
                nx, ny = section_outward(ring, j)
                crown = math.sin(math.pi * frac) ** 0.85
                proud = 0.010 + 0.020 * crown
                return (x + nx * proud, y + ny * proud, z)

            col = strake_col((t0 + t1) * 0.5, band)
            for f0, f1 in ((0.14, 0.50), (0.50, 0.86)):
                a = edge(r0, z0, f0)
                b = edge(r1, z1, f0)
                c = edge(r1, z1, f1)
                d = edge(r0, z0, f1)
                prim.quad_out(a, b, c, d, col, (a[0], 0.2, 0.0))
                ma, mb, mc, md = ((-p[0], p[1], p[2]) for p in (a, b, c, d))
                prim.quad_out(ma, md, mc, mb, col, (-a[0], 0.2, 0.0))
            # 板端接缝：窄而深的一条，错开，远看也是一块一块的板
            if i % 8 == (band * 3) % 8 and 0.08 < t0 < 0.90:
                a = edge(r0, z0, 0.18)
                b = edge(r1, z1, 0.18)
                c = edge(r1, z1, 0.82)
                d = edge(r0, z0, 0.82)
                # 只取这一站距里靠前的一窄条
                def pinch(p, q):
                    return (
                        lerp(p[0], q[0], 0.18),
                        lerp(p[1], q[1], 0.18),
                        lerp(p[2], q[2], 0.18),
                    )
                b, c = pinch(a, b), pinch(d, c)
                dark = scale_c(SEAM, 1.0)
                prim.quad_out(a, b, c, d, dark, (a[0], 0.4, 0.0))
                ma, mb, mc, md = ((-p[0], p[1], p[2]) for p in (a, b, c, d))
                prim.quad_out(ma, md, mc, mb, dark, (-a[0], 0.4, 0.0))


def add_seam_lines(prim, stations):
    """舷板之间的嵌缝，深色，略鼓出，不是朱漆水线。"""
    j0 = SHOULDER_I
    j1 = len(stations[0][2]) - 1
    for j in range(j0, j1 + 1):
        for i in range(1, len(stations) - 2):
            t0, z0, r0 = stations[i]
            t1, z1, r1 = stations[i + 1]

            def sp(ring, z, lift):
                x, y = ring[j]
                nx, ny = section_outward(ring, max(0, j - 1))
                return (x + nx * 0.016, y + ny * 0.016 + lift, z)

            a, d = sp(r0, z0, -0.011), sp(r0, z0, 0.011)
            b, c = sp(r1, z1, -0.011), sp(r1, z1, 0.011)
            col = scale_c(SEAM, 0.9 + 0.15 * hsh(t0 * 17 + j))
            prim.quad_out(a, b, c, d, col, (a[0], 0, 0))
            ma, mb, mc, md = ((-p[0], p[1], p[2]) for p in (a, b, c, d))
            prim.quad_out(ma, md, mc, mb, col, (-a[0], 0, 0))


LEAF_FACE = (0.72, 0.52, 0.28, 1)
LEAF_MID = (0.58, 0.40, 0.20, 1)
LEAF_EDGE = (0.32, 0.16, 0.06, 1)
LEAF_RIB = (0.05, 0.02, 0.01, 1)
LEAF_VEIN = (0.28, 0.14, 0.05, 1)
LEAF_BACK = (0.50, 0.34, 0.16, 1)

# 叶长、叶宽按当地干舷（舷缘高出水面）计。长轴取竖直，镜头里才跟干舷比，不沿舷缩成钉。
# 上一档 1.0×0.78 的宽叶盖住了壳，不要再做成那种黄香蕉。
def row_fb(t: float) -> float:
    return max(0.14, gunwale_y(t))


def blade_len(t: float) -> float:
    return 3.90 * row_fb(t)


def blade_wid(t: float) -> float:
    return 1.05 * row_fb(t)


# 梶用舯部干舷的两倍，不跟艉部抬起的舷缘走。
KAJ_LEN = 2.0 * blade_len(0.48)
KAJ_WID = 2.0 * blade_wid(0.48)


def leaf_half(u: float) -> float:
    """根部收窄，中段保持叶宽，末端收到一个尖。柳叶，不是香蕉，也不是钉子。"""
    u = clamp(u, 0.0, 1.0)
    if u < 0.14:
        return lerp(0.20, 1.0, smoothstep(0.0, 0.14, u))
    if u < 0.40:
        return 1.0
    tt = (u - 0.40) / 0.60
    return max(0.012, (1.0 - tt) ** 1.75)


def _quad_vc_out(prim, a, b, c, d, ca, cb, cc, cd, outward):
    n = vcross(vsub(b, a), vsub(c, a))
    if vlen(n) < 1e-10:
        return
    if vdot(n, outward) < 0.0:
        prim.quad_vc(a, d, c, b, ca, cd, cc, cb)
    else:
        prim.quad_vc(a, b, c, d, ca, cb, cc, cd)


def add_paddle(prim, neck, direction, length, width, face_up=0.85, face_hint=None):
    """叶桨：尖头、浅窝、一条中肋、两条纵脉。脉顺着叶长，没有横骨。
    face_hint 把叶面转向镜头。不给的话仍用 face_up。叶要立起来，不能平贴成一根钉。"""
    d = vnorm(direction)
    side = vnorm(vcross((0.0, 1.0, 0.0), d))
    if vlen(side) < 0.25:
        side = vnorm(vcross((1.0, 0.0, 0.0), d))
    up = vnorm(vcross(d, side))
    if face_hint is None:
        across = vnorm(vadd(vmul(side, 1.0), vmul(up, face_up)))
        face = vnorm(vcross(d, across))
    else:
        face = vsub(face_hint, vmul(d, vdot(face_hint, d)))
        if vlen(face) < 1e-4:
            face = up
        face = vnorm(face)
        across = vnorm(vcross(face, d))
    if face[1] < 0.0:
        face = vmul(face, -1.0)
        across = vmul(across, -1.0)

    n_u, n_s = 18, 13
    front = []
    back = []
    for i in range(n_u):
        u = i / (n_u - 1)
        hw = width * 0.5 * leaf_half(u)
        row_f = []
        row_b = []
        for j in range(n_s):
            s = -1.0 + 2.0 * j / (n_s - 1)
            # 叶面基本朝天，只把两边轻轻抬一点，两边桨都露得出正面。
            rise = abs(s) * hw * 0.20
            rib = math.exp(-((abs(s) * 5.0) ** 2)) * 0.006 * math.sin(math.pi * u)
            base = vadd(neck, vmul(d, (u ** 0.96) * length))
            p = vadd(base, vmul(across, s * hw))
            p = vadd(p, vmul(face, rise + rib))
            thick = 0.008 + 0.005 * (1.0 - abs(s)) * math.sin(math.pi * clamp(u, 0.04, 0.96))
            row_f.append(p)
            row_b.append(vadd(p, vmul(face, -thick)))
        front.append(row_f)
        back.append(row_b)

    def leaf_col(u, s, back_face):
        # 茶色叶面。中肋占叶宽大约五分之一，近黑，插值之后仍是一条细线。
        edge = smoothstep(0.80, 1.0, abs(s))
        rib = 1.0 - smoothstep(0.06, 0.24, abs(s))
        col = mix(LEAF_FACE, LEAF_MID, 0.08 + 0.16 * u)
        col = mix(col, LEAF_RIB, rib)
        col = mix(col, LEAF_EDGE, edge * 0.90)
        col = mix(col, LEAF_EDGE, smoothstep(0.80, 1.0, u) * 0.50)
        if back_face:
            col = scale_c(col, 0.80)
        return col

    for i in range(n_u - 1):
        u0 = i / (n_u - 1)
        u1 = (i + 1) / (n_u - 1)
        for j in range(n_s - 1):
            s0 = -1.0 + 2.0 * j / (n_s - 1)
            s1 = -1.0 + 2.0 * (j + 1) / (n_s - 1)
            sm = (s0 + s1) * 0.5
            a, b = front[i][j], front[i][j + 1]
            c, e = front[i + 1][j + 1], front[i + 1][j]
            _quad_vc_out(
                prim, a, b, c, e,
                leaf_col(u0, s0, False), leaf_col(u0, s1, False),
                leaf_col(u1, s1, False), leaf_col(u1, s0, False),
                face,
            )
            ba, bb = back[i][j], back[i][j + 1]
            bc, be = back[i + 1][j + 1], back[i + 1][j]
            _quad_vc_out(
                prim, ba, bb, bc, be,
                leaf_col(u0, s0, True), leaf_col(u0, s1, True),
                leaf_col(u1, s1, True), leaf_col(u1, s0, True),
                vmul(face, -1.0),
            )
        for s_edge, j in ((-1.0, 0), (1.0, n_s - 1)):
            fa, fb = front[i][j], front[i + 1][j]
            ea, eb = back[i][j], back[i + 1][j]
            outward = vmul(across, s_edge)
            _quad_vc_out(
                prim, fa, fb, eb, ea,
                LEAF_EDGE, LEAF_EDGE, LEAF_EDGE, LEAF_EDGE,
                outward,
            )
    # 中肋和纵脉是铺在叶面上的细带，顺着叶长。不是横档。
    # 带宽按当地叶宽走，尖头自然收掉。
    mid = n_s // 2
    for i in range(1, n_u - 2):
        u0 = i / (n_u - 1)
        u1 = (i + 1) / (n_u - 1)
        hw0 = width * 0.5 * leaf_half(u0)
        hw1 = width * 0.5 * leaf_half(u1)
        lift = 0.010

        def band(s_off, frac, col, hw0=hw0, hw1=hw1, u0=u0):
            if u0 < 0.06 or u0 > 0.92:
                return
            c0 = vadd(front[i][mid], vmul(across, s_off * hw0))
            c1 = vadd(front[i + 1][mid], vmul(across, s_off * hw1))
            w0 = max(0.004, hw0 * frac)
            w1 = max(0.003, hw1 * frac)
            a = vadd(vadd(c0, vmul(across, -w0)), vmul(face, lift))
            b = vadd(vadd(c0, vmul(across, w0)), vmul(face, lift))
            c = vadd(vadd(c1, vmul(across, w1)), vmul(face, lift))
            d = vadd(vadd(c1, vmul(across, -w1)), vmul(face, lift))
            _quad_vc_out(prim, a, b, c, d, col, col, col, col, face)

        # 只有一条中肋。两侧纵脉会把小叶画成香蕉上的条纹。
        band(0.0, 0.22, LEAF_RIB)


def slat_wall(prim, origin, axis_u, axis_v, nu, outward, gap=0.16):
    """苇墙：一条条竖着的席，中间留缝。不是一整块箱子。"""
    for i in range(nu):
        u0 = (i + gap) / nu
        u1 = (i + 1 - gap * 0.35) / nu
        col = scale_c(mix(STRAW_DK, STRAW_LT, 0.25 + 0.7 * hsh(i * 4.4 + nu)), 0.96)
        if i % 2 == 0:
            col = scale_c(col, 0.90)
        pts = []
        for u, v in ((u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0)):
            p = vadd(origin, vadd(vmul(axis_u, u), vmul(axis_v, v)))
            bow = math.sin(math.pi * u) * math.sin(math.pi * v)
            p = vadd(p, vmul(vnorm(outward), 0.018 * bow))
            pts.append(p)
        prim.quad_out(pts[0], pts[1], pts[2], pts[3], col, outward)


def add_thatch_cabin(prim):
    """艉部一小间：柱、苇墙、一张出檐的软茅顶。不是三层箱子，也不铺成屋船。"""
    t_aft, t_fwd = 0.885, 0.745
    z_aft, z_fwd = z_of(t_aft), z_of(t_fwd)
    yb = deck_base(0.82)
    hw = 0.38
    wall_h = 0.28
    # 柱
    for x, z, t in ((-hw, z_aft, t_aft), (hw, z_aft, t_aft), (-hw, z_fwd, t_fwd), (hw, z_fwd, t_fwd)):
        # 柱子落到槽底，墙和茅顶仍停在原来的高度。
        y0 = min(yb, floor_at(t, x))
        add_cyl(prim, (x, y0, z), (x, yb + wall_h + 0.04, z), 0.022, RAIL, 6)
    door = 0.11
    for x in (-door, door):
        add_cyl(prim, (x, yb, z_fwd + 0.01), (x, yb + wall_h * 0.78, z_fwd + 0.01), 0.016, HINOKI_DK, 5)
    add_cyl(prim, (-door, yb + wall_h * 0.78, z_fwd + 0.01), (door, yb + wall_h * 0.78, z_fwd + 0.01), 0.015, RAIL, 5)
    # 门槛横木
    add_cyl(prim, (-hw, yb + 0.03, z_fwd), (hw, yb + 0.03, z_fwd), 0.018, HINOKI_DK, 5)
    add_cyl(prim, (-hw, yb + 0.03, z_aft), (hw, yb + 0.03, z_aft), 0.018, HINOKI_DK, 5)

    # 左右苇墙
    slat_wall(
        prim, (-hw, yb + 0.04, z_aft), (0.0, 0.0, z_fwd - z_aft), (0.0, wall_h - 0.02, 0.0),
        7, (-1.0, 0.15, 0.0),
    )
    slat_wall(
        prim, (hw, yb + 0.04, z_fwd), (0.0, 0.0, z_aft - z_fwd), (0.0, wall_h - 0.02, 0.0),
        7, (1.0, 0.15, 0.0),
    )
    # 艉墙
    slat_wall(
        prim, (hw, yb + 0.04, z_aft), ((-2 * hw), 0.0, 0.0), (0.0, wall_h - 0.02, 0.0),
        6, (0.0, 0.15, -1.0),
    )
    # 朝艏的门：门两侧各一扇，门楣上一截
    slat_wall(
        prim, (-hw, yb + 0.05, z_fwd), ((hw - door) * 0.92, 0.0, 0.0), (0.0, wall_h * 0.74, 0.0),
        3, (0.0, 0.1, 1.0),
    )
    slat_wall(
        prim, (door + 0.02, yb + 0.05, z_fwd), ((hw - door) * 0.92, 0.0, 0.0), (0.0, wall_h * 0.74, 0.0),
        3, (0.0, 0.1, 1.0),
    )
    slat_wall(
        prim, (-hw, yb + wall_h * 0.80, z_fwd), (2 * hw, 0.0, 0.0), (0.0, wall_h * 0.22, 0.0),
        6, (0.0, 0.2, 1.0),
    )
    # 门洞里的暗
    prim.quad_out(
        (-door * 0.92, yb + 0.05, z_fwd - 0.08),
        (door * 0.92, yb + 0.05, z_fwd - 0.08),
        (door * 0.92, yb + wall_h * 0.72, z_fwd - 0.08),
        (-door * 0.92, yb + wall_h * 0.72, z_fwd - 0.08),
        HOLD, (0, 0, 1),
    )

    # 沿坡叠四层草束。一层一条，顺着船长，下缘是深色草头，边是毛的。
    # 还是矮舱上的一张坡：不叠成三层屋檐，不铺瓦，也不换成宋船舱。
    wall_top = yb + wall_h
    ox, oz = 0.34, 0.18
    rise = 0.40
    under_c = (0.20, 0.11, 0.045, 1.0)
    # 从脊到檐。第一层从脊下一点开始，好让脊束压住它。
    cuts = (0.07, 0.30, 0.52, 0.75, 1.0)
    sinks = (0.0, 0.030, 0.062, 0.096)
    nu = 12

    def roof_base(u, v):
        across = (v - 0.5) * 2.0
        arch = math.cos(min(1.0, abs(across)) * math.pi * 0.5) ** 1.05
        end = math.sin(math.pi * clamp(u, 0.0, 1.0))
        x = across * (hw + ox)
        z = lerp(z_aft - oz, z_fwd + oz, u)
        y = wall_top + 0.03 + rise * arch * (0.78 + 0.22 * end)
        y -= (1.0 - arch) * 0.06
        return (x, y, z)

    def q_up(a, b, c, d, ca, cb, cc, cd):
        n = vcross(vsub(b, a), vsub(c, a))
        if vlen(n) < 1e-8:
            return
        if n[1] < 0.0:
            prim.quad_vc(a, d, c, b, ca, cd, cc, cb)
        else:
            prim.quad_vc(a, b, c, d, ca, cb, cc, cd)

    def tone_at(u, ci, side, butt):
        # 沿船长分成一束束，明暗差得开，不是一条均匀的色带。
        bundle = math.floor(clamp(u, 0.0, 0.999) * 7.0)
        jit = 0.76 + 0.30 * hsh(bundle * 5.3 + ci * 2.2 + side)
        jit *= (1.0, 0.95, 1.02, 0.93)[ci]
        if butt < 0.25:
            col = mix(STRAW, STRAW_LT, 0.25 + 0.6 * hsh(bundle * 1.9 + ci))
        else:
            # 只有草头这一窄条是深的。深的是草束的茬，不是画上去的宽条。
            col = mix(STRAW_DK, (0.26, 0.15, 0.05, 1.0), 0.20 + 0.55 * butt)
        return scale_c(col, jit)

    for side in (1.0, -1.0):
        for ci in range(4):
            t0 = cuts[ci]
            t1 = cuts[ci + 1]
            sink = sinks[ci]
            for iu in range(nu):
                u0 = iu / nu
                u1 = (iu + 1) / nu
                jag = (hsh(iu * 2.9 + ci * 6.1 + side) - 0.5) * 0.07
                jag2 = (hsh(iu * 2.9 + ci * 6.1 + side + 4.0) - 0.5) * 0.07
                yjag = (hsh(iu * 4.4 + ci * 1.3 + side) - 0.5) * 0.022

                def vt(s, j, t0=t0, t1=t1):
                    t = lerp(t0, t1, s)
                    if s > 0.72:
                        t += j * (s - 0.72) / 0.28
                    return clamp(0.5 + side * 0.5 * clamp(t, 0.0, 1.05), 0.0, 1.0)

                def pt(u, v, s, sink=sink, side=side, yjag=yjag):
                    p = roof_base(u, v)
                    crown = math.sin(clamp(s, 0.0, 1.0) * math.pi) * 0.016
                    lip = smoothstep(0.70, 1.0, s)
                    # 草头探出坡外再垂下一截，茬口是一条坎，不是贴在同一张面上的宽色带。
                    return (
                        p[0] + side * 0.055 * lip,
                        p[1] + crown - sink - 0.058 * lip + yjag * lip,
                        p[2],
                    )

                # 草身亮，只有最下一窄条是深色草头。层与层靠这条茬分开。
                for s0, s1, butt0, butt1 in ((0.0, 0.74, 0.0, 0.08), (0.74, 1.0, 0.85, 1.0)):
                    v00 = vt(s0, 0.0)
                    v10 = vt(s0, 0.0)
                    v11 = vt(s1, jag2)
                    v01 = vt(s1, jag)
                    a = pt(u0, v00, s0)
                    b = pt(u1, v10, s0)
                    c = pt(u1, v11, s1)
                    d = pt(u0, v01, s1)
                    q_up(
                        a, b, c, d,
                        tone_at(u0, ci, side, butt0),
                        tone_at(u1, ci, side, butt0),
                        tone_at(u1, ci, side, butt1),
                        tone_at(u0, ci, side, butt1),
                    )
                    if s1 >= 0.99:
                        drop = 0.062
                        e = (d[0], d[1] - drop, d[2])
                        f = (c[0], c[1] - drop, c[2])
                        prim.quad_out(e, f, c, d, tone_at((u0 + u1) * 0.5, ci, side, 1.0), (side, -0.55, 0.0))
                        if ci == 3:
                            prim.quad_out(
                                (a[0], a[1] - drop * 0.35, a[2]),
                                e, f,
                                (b[0], b[1] - drop * 0.35, b[2]),
                                under_c, (0.0, -1.0, 0.0),
                            )

                if iu == 0 or iu == nu - 1:
                    u = 0.0 if iu == 0 else 1.0
                    zsign = -1.0 if iu == 0 else 1.0

                    def edge_pt(s, u=u, jag=jag, t0=t0, t1=t1, sink=sink, side=side):
                        t = lerp(t0, t1, s)
                        if s > 0.72:
                            t += jag * (s - 0.72) / 0.28
                        v = clamp(0.5 + side * 0.5 * clamp(t, 0.0, 1.05), 0.0, 1.0)
                        return pt(u, v, s)

                    top_a = edge_pt(0.0)
                    top_b = edge_pt(1.0)
                    bot_a = (top_a[0], top_a[1] - 0.032, top_a[2])
                    bot_b = (top_b[0], top_b[1] - 0.040, top_b[2])
                    prim.quad_out(
                        bot_a, bot_b, top_b, top_a,
                        tone_at(u, ci, side, 0.65),
                        (0.0, -0.15, zsign),
                    )

            # 层缘的草丝。最下一层长一点，上面几层只留短茬，免得盖住空槽和梶。
            step = 1 if ci == 3 else 2
            for iu in range(0, nu, step):
                u = (iu + 0.45) / nu
                if u < 0.14 or u > 0.86:
                    continue
                t = cuts[ci + 1] + (hsh(iu * 3.3 + ci + side) - 0.5) * 0.028
                v = clamp(0.5 + side * 0.5 * t, 0.0, 1.0)
                p = roof_base(u, v)
                lip_y = p[1] - sink - 0.034
                if ci == 3:
                    length = 0.07 + 0.09 * hsh(iu * 8.1 + ci * 2.0 + side)
                    rad = 0.011
                else:
                    length = 0.028 + 0.018 * hsh(iu * 4.4 + ci + side)
                    rad = 0.007
                origin = (p[0] + side * 0.02, lip_y, p[2])
                tip = (
                    p[0] + side * (0.03 + length * 0.65),
                    lip_y - length * 0.85,
                    p[2] + (hsh(iu * 1.3 + side) - 0.5) * 0.04,
                )
                col = STRAW_DK if (iu + ci) % 2 == 0 else mix(STRAW, STRAW_LT, 0.35)
                add_cyl(prim, origin, tip, rad, col, 4, caps=False)

    # 脊上一条软草束，压住两边的第一层。不是瓦脊，也不是一根光管子。
    for iu in range(nu):
        u0 = iu / nu
        u1 = (iu + 1) / nu
        for iv, v0, v1 in ((0, 0.43, 0.50), (1, 0.50, 0.57)):
            def rpt(u, v, iu=iu):
                p = roof_base(u, v)
                hump = math.cos(clamp((v - 0.5) / 0.07, -1.0, 1.0) * math.pi * 0.5)
                return (p[0], p[1] + 0.050 + 0.016 * hump, p[2])

            a, b = rpt(u0, v0), rpt(u1, v0)
            c, d = rpt(u1, v1), rpt(u0, v1)
            col = scale_c(mix(STRAW, STRAW_LT, 0.35 + 0.25 * hsh(iu * 2.2 + iv)), 0.96)
            q_up(a, b, c, d, col, col, col, col)
    for k in range(3):
        u = 0.24 + k * 0.26
        p = roof_base(u, 0.5)
        y = p[1] + 0.072
        add_cyl(prim, (-0.11, y, p[2]), (0.11, y, p[2]), 0.011, ROPE_DK, 5, caps=False)



def sail_surface(mz, deck_y):
    """一张软筵。上缘钉死在桁上，是直的。
    脚是一条弧：两腰高，正中最低。弧底悬在横梁之上，
    十八度侧看弧底下面是海，不是一条横线切在梁上。
    苇沿垂线走，没有横竹、桁梯、苇条。"""
    head_y = deck_y + 3.40
    # 两腰抬高。正中再落下一截，落完仍离开横梁，海才能从弧底露出来。
    leech_foot = deck_y + 2.48
    hem_drop = 0.78
    z_luff = mz + 0.04
    z_leech = mz - 1.78

    def sp(u, v):
        u = clamp(u, 0.0, 1.0)
        v = clamp(v, 0.0, 1.0)
        across = math.sin(math.pi * u)
        # 略大于 1：正中是弧底，两腰还带着坡，不会摊成一条平底横线。
        sag = across ** 1.25
        foot = leech_foot - hem_drop * sag
        # 每根苇从桁直落到自己的脚。长短不同，所以脚是弧，苇仍是直的。
        y = lerp(foot, head_y, v)
        z = lerp(z_luff, z_leech, u)
        # 后缘中段微微外弯。弯得很浅，苇柱只斜一两度。
        z -= 0.14 * (u ** 1.6) * math.sin(math.pi * v)
        # 鼓向近舷。身子一段不随高度变，苇是直的；只在桁下收拢，桁仍是直的。
        taper = smoothstep(0.84, 1.0, v)
        x = 0.38 * across * (1.0 - taper)
        x += 0.022 * math.sin(2.0 * math.pi * u) * (1.0 - 0.65 * taper)
        return (x, y, z)

    return sp


def sail_normal(sp, u, v):
    e = 0.012
    du = vsub(sp(min(1.0, u + e), v), sp(max(0.0, u - e), v))
    dv = vsub(sp(u, min(1.0, v + e)), sp(u, max(0.0, v - e)))
    n = vnorm(vcross(du, dv))
    if n[0] < 0.0:
        n = vmul(n, -1.0)
    return n


def build_sail(sail, sp):
    """一整张席。顶点法线顺着布面走。不另铺横条，也不叠一张背面。
    背面叠上去，缝会在斜光里变成一排横线。正反面交给着色器。"""
    n_u, n_v = 28, 36

    def col_at(u, v):
        belly = math.sin(math.pi * u) ** 1.1
        up = smoothstep(0.0, 0.42, v)
        shade = (0.91 + 0.09 * up) * (1.0 - 0.045 * belly)
        # 只在横向上有极轻的起伏，不是一档一档的深色横条。
        fold = 0.99 + 0.01 * math.sin(u * math.tau)
        return scale_c(mix(STRAW, STRAW_LT, 0.62), shade * fold)

    for iv in range(n_v):
        v0 = iv / n_v
        v1 = (iv + 1) / n_v
        for iu in range(n_u):
            u0 = iu / n_u
            u1 = (iu + 1) / n_u
            a, b = sp(u0, v0), sp(u1, v0)
            c, d = sp(u1, v1), sp(u0, v1)
            na, nb = sail_normal(sp, u0, v0), sail_normal(sp, u1, v0)
            nc, nd = sail_normal(sp, u1, v1), sail_normal(sp, u0, v1)
            sail.quad_n(
                a, b, c, d,
                col_at(u0, v0), col_at(u1, v0), col_at(u1, v1), col_at(u0, v1),
                na, nb, nc, nd,
                (u0, v0), (u1, v0), (u1, v1), (u0, v1),
            )


def add_yard_and_bindings(fit, sp, top):
    yard = []
    for i in range(12):
        u = i / 11
        p = sp(u, 1.0)
        p = (p[0] + 0.02, p[1] + 0.025, p[2])
        yard.append(p)
    for i in range(11):
        rad = 0.020 if i in (0, 10) else 0.028
        add_cyl(fit, yard[i], yard[i + 1], rad, BARK, 6, caps=False)
    add_sphere(fit, yard[0], 0.034, HINOKI_DK, 6, 4)
    add_sphere(fit, yard[-1], 0.034, HINOKI_DK, 6, 4)
    # 只有这一根上桁。席面上不加横绳、不加第二根桁、不加苇条。
    return yard


def add_rigging(fit, sp, top, yard, mz):
    """少量细索。不要在席面上交叉成格子。"""
    clew = sp(1.0, 0.02)
    tack = sp(0.02, 0.04)
    stay_r = 0.005
    run_r = 0.0035
    for side in (-1.0, 1.0):
        rope(fit, top, (side * half_beam(0.48) * 0.82, gunwale_y(0.48) + 0.03, z_of(0.50)), 0.04, stay_r, ROPE, 6)
    rope(fit, top, (0.0, gunwale_y(0.06) + 0.06, z_of(0.045)), 0.04, stay_r, ROPE, 6)
    rope(fit, top, (0.05, gunwale_y(0.93) + 0.04, z_of(0.94)), 0.08, stay_r, ROPE, 6)
    # 升降索贴着桅，不横跨席面。
    rope(fit, top, yard[1], 0.012, run_r, ROPE, 4)
    rope(fit, clew, (0.42, gunwale_y(0.68) + 0.03, z_of(0.70)), 0.10, run_r, ROPE, 6)
    rope(fit, tack, (-0.06, gunwale_y(0.38) + 0.03, mz + 0.12), 0.03, run_r, ROPE, 4)


def add_oar(fit, side, t, rowing, phase):
    z = z_of(t)
    xg = side * half_beam(t) * 0.92
    yg = gunwale_y(t) + 0.02
    thole = (xg, yg, z)
    pin_h = 0.07
    add_cyl(fit, (xg, yg - 0.015, z - 0.03), (xg, yg + pin_h, z - 0.03), 0.012, RAIL, 5)
    add_cyl(fit, (xg, yg - 0.015, z + 0.03), (xg, yg + pin_h, z + 0.03), 0.012, RAIL, 5)
    # 叶面朝舷侧镜头，不朝天。朝天时 18° 只看见侧刃。
    hint = (0.92, 0.32, 0.12)
    length = blade_len(t)
    width = blade_wid(t)
    if rowing:
        grip = (side * half_beam(t) * 0.40, yg + 0.06, z - 0.02)
        if side > 0:
            # 近舷：和梶同一朝向，叶面朝镜头。长轴对着干舷，叶身在壳外。
            neck = (side * (half_beam(t) + 0.16), yg + 0.04, z + 0.02 * math.sin(phase))
            direc = (side * 0.32, -0.72, -0.88)
        else:
            # 远舷和近舷同一片叶、同一下垂。杆从舷缘伸出，叶在舷外。
            # 不抬到空槽上方。
            neck = (side * (half_beam(t) + 0.16), yg + 0.04, z + 0.02 * math.sin(phase))
            direc = (side * 0.32, -0.72, -0.88)
        add_cyl(fit, grip, thole, 0.012, scale_c(HINOKI_DK, 0.85), 5)
        add_cyl(fit, thole, neck, 0.010, scale_c(BARK, 0.95), 5)
        add_paddle(fit, neck, direc, length, width, face_hint=hint)
    else:
        # 收到近舷外，同一片小叶斜立着，叶面朝镜头。
        inner = (side * half_beam(t) * 0.58, yg + 0.02, z + 0.10)
        neck = (side * (half_beam(t) + 0.08), yg + 0.06, z - 0.02)
        add_cyl(fit, inner, neck, 0.010, scale_c(BARK, 0.95), 5)
        add_paddle(
            fit, neck, (side * 0.30, 0.50, -0.88), length, width,
            face_hint=hint,
        )



def add_shallow_chops(prim, stations):
    """圆木上的浅锛口。一小块、只鼓出两三厘米，颜色仍是这块楠木。
    不铺满船壳，也不做成明暗对跳的大平面。"""
    i = 4
    while i < N_ST - 8:
        span = 2 + int(hsh(i * 2.7 + 0.3) * 2)  # 两到三站，大约一掌到一尺
        j0 = 2 + int(hsh(i * 5.1 + 1.2) * max(1, SHOULDER_I - 6))
        j0 = max(1, min(SHOULDER_I - 3, j0))
        j1 = min(SHOULDER_I - 1, j0 + 1 + int(hsh(i * 8.3) * 2))
        i1 = min(N_ST - 3, i + span)
        proud = 0.022 + 0.016 * hsh(i * 4.4 + j0)

        def corner(ii, jj, proud=proud):
            _t, z, ring = stations[ii]
            x, y = ring[jj]
            nx, ny = section_outward(ring, min(jj, len(ring) - 2))
            return (max(0.0, x + nx * proud), y + ny * proud * 0.65, z)

        a = corner(i, j0)
        b = corner(i1, j0)
        c = corner(i1, j1)
        d = corner(i, j1)
        ymid = (a[1] + d[1]) * 0.5
        base = dugout_col(ymid, stations[i][0])
        # 只比原木略新或略旧，相邻块不强制一亮一暗。
        tone = 0.86 + 0.22 * hsh(i * 6.6 + j0 * 2.2)
        col = scale_c(base, tone)

        def emit(a, b, c, d, col):
            mid = vmul(vadd(vadd(a, b), vadd(c, d)), 0.25)
            prim.quad_out(a, b, c, d, col, (mid[0], 0.25, 0.0))

            def mx(pt):
                return (-pt[0], pt[1], pt[2])

            prim.quad_out(mx(a), mx(d), mx(c), mx(b), col, (-mid[0], 0.25, 0.0))

        emit(a, b, c, d, col)
        i += span + 3 + int(hsh(i * 1.9 + 4.0) * 3)


def build(kind: str):
    war = kind == "war"
    dug = Prim("Dugout", "Wood")
    planks = Prim("Strakes", "Wood")
    boards = Prim("Boards", "Wood")
    deck = Prim("Deck", "Wood")
    fit = Prim("Fittings", "Wood")
    sail = Prim("Sails", "Sail")
    shadow = Prim("Shadow", "Shadow")

    stations = []
    for i in range(N_ST):
        t = i / (N_ST - 1)
        t_use = clamp(t, 0.004, 0.996)
        ring = section_ring(t_use)
        stations.append((t_use, z_of(t), ring))

    def c_dug(t, j, y):
        return dugout_col(y, t)

    def c_bed(t, j, y):
        # 舷板底下的嵌缝底，深色，缝里才看得见。
        return scale_c(SEAM, 0.95)

    def c_cap_plank(t, j, y):
        return strake_col(t, max(0, j - SHOULDER_I))

    # 暗色底壳只填锛面之间的缝。整圈都铺，不再只铺肩以上的光滑舷板。
    loft(dug, stations, 0, SHOULDER_I, c_dug)
    loft(planks, stations, SHOULDER_I, len(stations[0][2]) - 1, c_bed)

    t0, z0, r0 = stations[0]
    tip_b = (0.0, lerp(r0[0][1], r0[-1][1], 0.62) + 0.04, z0 + 0.28)
    cap_end(dug, r0[: SHOULDER_I + 1], z0, tip_b, c_dug, 0.01, bow=True)
    cap_end(planks, r0[SHOULDER_I:], z0, tip_b, c_cap_plank, 0.01, bow=True)
    t1, z1, r1 = stations[-1]
    tip_s = (0.0, lerp(r1[0][1], r1[-1][1], 0.58), z1 - 0.22)
    cap_end(dug, r1[: SHOULDER_I + 1], z1, tip_s, c_dug, 0.99, bow=False)
    cap_end(planks, r1[SHOULDER_I:], z1, tip_s, c_cap_plank, 0.99, bow=False)

    # 先收成一根圆木，再在上面另贴浅锛口。锛口不参与平滑，所以还是小平面。
    dug.smooth()
    planks.smooth()
    add_shallow_chops(dug, stations)
    add_dugout_grooves(boards, stations)
    add_seam_lines(boards, stations)
    add_proud_strakes(boards, stations)

    # 挖底和舷板的接缝：一条鼓出来的腰。不是朱漆。
    for i in range(3, N_ST - 4):
        tt0, zz0, rr0 = stations[i]
        tt1, zz1, rr1 = stations[i + 1]
        j = SHOULDER_I

        def wale_pair(ring, z):
            x, y = ring[j]
            o = 1.0 if x >= 0 else -1.0
            nx, ny = section_outward(ring, j)
            a = (x + nx * 0.012, y + ny * 0.004, z)
            b = (x + nx * 0.030, y + ny * 0.004 + 0.026, z)
            c = (x + nx * 0.018, y + ny * 0.004 + 0.012, z)
            return a, b, c

        a0, b0, c0 = wale_pair(rr0, zz0)
        a1, b1, c1 = wale_pair(rr1, zz1)
        fit.quad_out(a0, a1, b1, b0, WALE_C, (a0[0], 0, 0))
        fit.quad_out((-a0[0], a0[1], a0[2]), (-b0[0], b0[1], b0[2]), (-b1[0], b1[1], b1[2]), (-a1[0], a1[1], a1[2]), WALE_C, (-a0[0], 0, 0))

    # 舷缘木
    for i in range(N_ST - 1):
        tt0, zz0, rr0 = stations[i]
        tt1, zz1, rr1 = stations[i + 1]

        def rail_pt(ring, z, lift, inb):
            x, y = ring[-1]
            s = 1.0 if x >= 0 else -1.0
            return (x - s * inb, y + lift, z)

        a = rail_pt(rr0, zz0, 0.0, 0.0)
        b = rail_pt(rr1, zz1, 0.0, 0.0)
        # 厚舷缘的顶面：一整圈实木，不切成甲板条。
        c = rail_pt(rr1, zz1, 0.036, rim_inset(tt1))
        d = rail_pt(rr0, zz0, 0.036, rim_inset(tt0))
        col = scale_c(RAIL, 0.90 + 0.08 * hsh(tt0 * 20))
        fit.quad_out(a, b, c, d, col, (a[0], 1, 0))
        fit.quad_out((-a[0], a[1], a[2]), (-d[0], d[1], d[2]), (-c[0], c[1], c[2]), (-b[0], b[1], b[2]), col, (-a[0], 1, 0))

    # 舷墙内壁
    for i in range(N_ST - 1):
        tt0, zz0, rr0 = stations[i]
        tt1, zz1, rr1 = stations[i + 1]

        def inner_lip(z, t, top):
            lip = inner_section(t)[-1]
            if top:
                return (lip[0], gunwale_y(t) + 0.034, z)
            return (lip[0], lip[1], z)

        a = inner_lip(zz0, tt0, False)
        b = inner_lip(zz1, tt1, False)
        c = inner_lip(zz1, tt1, True)
        d = inner_lip(zz0, tt0, True)
        col = scale_c(mix(CAMPHOR, HOLD, 0.35), 0.95)
        fit.quad_out(a, d, c, b, col, (-a[0], 0, 0))
        fit.quad_out((-a[0], a[1], a[2]), (-b[0], b[1], b[2]), (-c[0], c[1], c[2]), (-d[0], d[1], d[2]), col, (a[0], 0, 0))

    # 挖空的内膛：外皮内侧的一整块圆槽。法线朝舱里。没有纵向甲板条。
    inner_stations = []
    for tt, zz, _ring in stations:
        inner_stations.append((tt, zz, inner_section(tt)))
    loft(deck, inner_stations, 0, len(inner_stations[0][2]) - 1, hollow_col, outward_sign=-1.0)
    deck.smooth()
    # 艏艉把槽封住，免得看成穿通的管子。
    for idx, into_pos in ((0, False), (-1, True)):
        tt, zz, ring = inner_stations[idx]
        outward = (0.0, 0.2, 1.0 if into_pos else -1.0)
        cy = sum(p[1] for p in ring) / len(ring)
        tip = (0.0, cy, zz)
        col = hollow_col(tt, 0, cy)
        for j in range(len(ring) - 1):
            a = (ring[j][0], ring[j][1], zz)
            b = (ring[j + 1][0], ring[j + 1][1], zz)
            n = vcross(vsub(b, a), vsub(tip, a))
            if vlen(n) < 1e-8:
                continue
            if vdot(n, outward) < 0.0:
                deck.tri(a, tip, b, col, col, col)
            else:
                deck.tri(a, b, tip, col, col, col)
            am, bm = (-a[0], a[1], a[2]), (-b[0], b[1], b[2])
            n2 = vcross(vsub(am, bm), vsub(tip, bm))
            if vdot(n2, outward) < 0.0:
                deck.tri(bm, tip, am, col, col, col)
            else:
                deck.tri(bm, am, tip, col, col, col)

    thwart_ts = [0.18, 0.33, 0.46, 0.70, 0.84] if not war else [0.16, 0.26, 0.36, 0.46, 0.56, 0.66, 0.76, 0.86]
    for t in thwart_ts:
        z = z_of(t)
        # 横梁搁在厚舷缘上，横跨空槽，不是铺在底上的板。
        y = gunwale_y(t) - 0.012
        w = (gunwale_x(t) - rim_inset(t) * 0.20) * 2.0
        thick = 0.11 if abs(t - 0.40) < 0.04 else 0.065
        add_box(fit, (0, y, z), (w, 0.048, thick), scale_c(RAIL, 0.95 + 0.08 * hsh(t * 30)))

    mast_t = 0.40
    mz = z_of(mast_t)
    # 桅脚落到槽底。桅头高度仍按原来的甲板线，帆不跟着掉。
    my0 = floor_at(mast_t, 0.0)
    mast_h = 4.15 + (deck_base(mast_t) - 0.02 - my0)
    rake = -0.10
    foot = (0.0, my0, mz)
    top = (0.0, my0 + mast_h, mz + rake)
    add_cyl(fit, foot, top, 0.062, mix(BARK, HINOKI_DK, 0.35), 8)
    add_cyl(fit, foot, (0, my0 + 0.38, mz + rake * 0.08), 0.082, HINOKI_DK, 8)
    for k in range(5):
        yy = 0.18 + k * 0.16
        p = (lerp(foot[0], top[0], yy), lerp(foot[1], top[1], yy), lerp(foot[2], top[2], yy))
        p2 = (p[0], p[1] + 0.028, p[2])
        add_cyl(fit, p, p2, 0.074, ROPE_DK, 8, caps=False)
    add_sphere(fit, top, 0.05, HINOKI_DK, 6, 5)
    add_box(fit, (0, my0 + 0.035, mz), (0.26, 0.06, 0.26), HINOKI_DK)

    sp = sail_surface(mz, deck_base(mast_t))
    build_sail(sail, sp)
    yard = add_yard_and_bindings(fit, sp, top)
    add_rigging(fit, sp, top, yard, mz)

    # 梶：船尾右舷的宽叶舵桨。不在中线，不是宋式尾舵。
    t_kaj = 0.90
    kaj_root = (half_beam(t_kaj) * 0.50, gunwale_y(t_kaj) + 0.04, z_of(t_kaj))
    kaj_neck = (half_beam(t_kaj) + 0.22, gunwale_y(t_kaj) - 0.01, z_of(0.97))
    add_cyl(fit, kaj_root, kaj_neck, 0.014, BARK, 6)
    # 同一片叶子，大约两倍一支漕桨。往后下方伸出，仍是桨，不是帆。
    add_paddle(fit, kaj_neck, (0.28, -0.72, -0.85), KAJ_LEN, KAJ_WID, face_hint=(0.88, 0.38, 0.10))
    add_cyl(fit, kaj_root, (0.02, gunwale_y(0.84) + 0.02, z_of(0.82)), 0.018, HINOKI_DK, 6)
    rope(fit, kaj_root, (0.15, gunwale_y(0.96) + 0.04, z_of(0.97)), 0.04, 0.006, ROPE, 4)

    if war:
        oar_places = [(t, side) for t in (0.22, 0.32, 0.42, 0.52, 0.62, 0.72) for side in (-1, 1)]
    else:
        # 商船只收两三片同样的小叶，放在近舷上，近景才看得见。
        oar_places = [(0.26, 1), (0.40, 1), (0.54, 1)]
    for n, (t, side) in enumerate(oar_places):
        phase = n * 0.85 + (0.4 if side > 0 else 0.0)
        add_oar(fit, side, t, war, phase)

    if not war:
        add_thatch_cabin(fit)
        y = floor_at(0.50, -0.22) + 0.12
        add_cyl(fit, (-0.22, y, z_of(0.52)), (-0.22, y, z_of(0.46)), 0.13, STRAW, 8)
        y = floor_at(0.36, 0.26) + 0.11
        add_cyl(fit, (0.26, y, z_of(0.38)), (0.26, y, z_of(0.32)), 0.12, STRAW_LT, 8)
        y = floor_at(0.24, 0.36) + 0.09
        add_cyl(fit, (0.36, y, z_of(0.24)), (0.36, y + 0.22, z_of(0.24)), 0.09, HINOKI_DK, 8)
    else:
        for t, x in ((0.32, 0.22), (0.48, -0.20), (0.66, 0.16)):
            y = floor_at(t, x) + 0.045
            top = gunwale_y(t) + 0.12
            add_cyl(fit, (x, y, z_of(t)), (x, top, z_of(t)), 0.045, HINOKI_DK, 7)
            add_cyl(fit, (x, top - 0.06, z_of(t)), (x, top + 0.04, z_of(t)), 0.028, HINOKI_DK, 6)
        y0 = floor_at(0.22, -0.18) + 0.04
        y1 = floor_at(0.36, 0.10) + 0.06
        add_cyl(fit, (-0.18, y0, z_of(0.20)), (0.10, y1, z_of(0.36)), 0.022, HINOKI, 5)

    for t, x in ((0.14, 0.35), (0.14, -0.35), (0.88, 0.28), (0.88, -0.28)):
        y = gunwale_y(t) + 0.01
        xx = math.copysign(gunwale_x(t) - rim_inset(t) * 0.45, x)
        add_cyl(fit, (xx, y, z_of(t)), (xx, y + 0.16, z_of(t)), 0.028, RAIL, 6)
        add_cyl(fit, (xx - 0.05, y + 0.14, z_of(t)), (xx + 0.05, y + 0.14, z_of(t)), 0.016, HINOKI, 5)

    for i in range(16):
        a0 = i / 16 * math.tau
        a1 = (i + 1) / 16 * math.tau
        for k in range(4):
            r0 = 0.35 + k * 0.48
            r1 = r0 + 0.48
            alpha = 0.34 * (1.0 - k / 4) ** 1.5
            col = (0.02, 0.03, 0.04, alpha)

            def spp(a, r, a0=a0):
                return (math.cos(a) * r * 0.42, -0.015, math.sin(a) * r * 1.05)

            shadow.quad(spp(a0, r0), spp(a1, r0), spp(a1, r1), spp(a0, r1), col)

    return [dug, planks, boards, deck, fit, sail, shadow]


def pack_glb(prims, path: Path, root_name: str):
    mats = {
        "Wood": {
            "name": "Wood",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.82,
            },
            "doubleSided": False,
        },
        "Sail": {
            "name": "Sail",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.86,
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
        "asset": {"version": "2.0", "generator": "nk1-japan-quasi"},
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
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)
    tris = sum(len(p.idx) // 3 for p in prims)
    xs, ys, zs = [], [], []
    for p in prims:
        for q in p.pos:
            xs.append(q[0])
            ys.append(q[1])
            zs.append(q[2])
    print(f"wrote {path} bytes={len(out)} tris={tris}")
    print(f"bounds x[{min(xs):.2f},{max(xs):.2f}] y[{min(ys):.2f},{max(ys):.2f}] z[{min(zs):.2f},{max(zs):.2f}]")


def main():
    pack_glb(build("merchant"), OUT_DIR / "japan_quasi.glb", "JapanQuasi")
    pack_glb(build("war"), OUT_DIR / "japan_quasi_war.glb", "JapanQuasiWar")


if __name__ == "__main__":
    main()
