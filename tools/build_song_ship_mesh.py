#!/usr/bin/env python3
"""泉州湾南宋海船 — 一条可转的三维船壳（glTF）。

尖底、低干舷、一层露天甲板、艏艉起翘、两桅竹席硬篷。
敌我只差帆色，由 Godot 改 Sail 材质，不另做一条船。
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
        self.idx = []

    def _push(self, p, n, c):
        self.pos.append(p)
        self.nrm.append(n)
        self.col.append(c)
        return len(self.pos) - 1

    def tri(self, a, b, c, ca, cb, cc):
        n = vnorm(vcross(vsub(b, a), vsub(c, a)))
        ia = self._push(a, n, ca)
        ib = self._push(b, n, cb)
        ic = self._push(c, n, cc)
        self.idx.extend((ia, ib, ic))

    def quad(self, a, b, c, d, color):
        """a-b-c-d，从外看逆时针。"""
        self.tri(a, b, c, color, color, color)
        self.tri(a, c, d, color, color, color)

    def quad_out(self, a, b, c, d, color, outward):
        n = vcross(vsub(b, a), vsub(c, a))
        if vdot(n, outward) < 0.0:
            self.quad(a, d, c, b, color)
        else:
            self.quad(a, b, c, d, color)

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
        # 艏站不要完全缩成点，留一根艏柱
        t_use = max(t, 0.012)
        ring = section_pts(t_use)
        z = z_of(t)
        stations.append((t, z, ring))

    # 船壳 loft
    for i in range(nst - 1):
        t0, z0, r0 = stations[i]
        t1, z1, r1 = stations[i + 1]
        nring = len(r0)
        for j in range(nring - 1):
            def P(ring, z, j, t):
                x, y = ring[j]
                # 板缝内收
                if 0 < j < nring - 1 and j % 2 == 0 and j < nring - 3:
                    y -= 0.006
                    x *= 0.992
                return (x, y, z), t

            a, _ = P(r0, z0, j, t0)
            b, _ = P(r1, z1, j, t1)
            c, _ = P(r1, z1, j + 1, t1)
            d, _ = P(r0, z0, j + 1, t0)
            col = wood_at((t0 + t1) * 0.5, j, nring)
            mid = vmul(vadd(vadd(a, b), vadd(c, d)), 0.25)
            outward = (mid[0], 0.15, 0.0)
            hull.quad_out(a, b, c, d, col, outward)
            # 左舷
            def mx(p):
                return (-p[0], p[1], p[2])
            hull.quad_out(mx(a), mx(d), mx(c), mx(b), col, (-mid[0], 0.15, 0.0))

    # 艏柱封口（最前一圈收到中线）
    t0, z0, r0 = stations[0]
    stem_top = (0.0, r0[-1][1] + 0.05, z0 + 0.05)
    stem_bot = (0.0, r0[0][1], z0 + 0.02)
    for j in range(len(r0) - 1):
        a = (r0[j][0], r0[j][1], z0)
        b = (r0[j + 1][0], r0[j + 1][1], z0)
        col = wood_at(0.02, j, len(r0))
        hull.quad_out(a, b, stem_top if j > len(r0) // 2 else stem_bot, stem_bot if j <= len(r0) // 2 else stem_top, col, (0, 0, 1))
        hull.quad_out(
            (-a[0], a[1], a[2]),
            stem_top if j > len(r0) // 2 else stem_bot,
            stem_top if j > len(r0) // 2 else stem_bot,
            (-b[0], b[1], b[2]),
            col,
            (0, 0, 1),
        )
    # 上面那个左舷封口写乱了。重做左舷艏：镜像右舷三角形
    # （右舷已画；左舷单独再画一遍干净的）
    # 为避免重复，上面左舷循环是错的。我改成在函数外不这么写。
    # —— 见下方 rebuild：实际上 quad_out 可能叠了坏面。这里清掉策略：
    # 不在此处补左舷艏。改为下面用镜像复制整个 hull 的做法。
    # 先把错误的左舷艏面留着会穿帮。改结构：只 loft 右舷，再镜像所有右舷三角形。

    hull.smooth()

    # 甲板
    n_across = 26
    for i in range(nst - 1):
        t0, z0, r0 = stations[i]
        t1, z1, r1 = stations[i + 1]
        b0 = r0[-3][0] * 0.90  # 舷墙内侧
        b1 = r1[-3][0] * 0.90
        y0 = r0[-3][1] + 0.01
        y1 = r1[-3][1] + 0.01
        for k in range(n_across):
            u0 = -1.0 + 2.0 * k / n_across
            u1 = -1.0 + 2.0 * (k + 1) / n_across
            def deck_p(u, b, y, z):
                x = u * b
                cam = 0.07 * (1.0 - (x / max(b, 0.05)) ** 2)
                return (x, y + cam, z)
            a = deck_p(u0, b0, y0, z0)
            b = deck_p(u0, b1, y1, z1)
            c = deck_p(u1, b1, y1, z1)
            d = deck_p(u1, b0, y0, z0)
            # 板沿船长走：同一条 x 上的颜色连续，只在板与板之间换色，避免格子布
            tone = 0.90 + 0.14 * hsh(k * 17.3)
            grain = 0.96 + 0.06 * hsh(k * 3.1 + i * 0.17)
            seam = 0.62 if (k % 2 == 0) else 1.0
            # 靠舷墙的几条压暗，甲板中线被人踩得浅一点
            edge = 0.82 if abs(u0) > 0.82 else 1.0
            base = mix(DECK_DK, DECK, tone)
            col = tuple(clamp(ch * grain * (0.84 if seam < 1 and False else 1) * edge, 0, 1) if ii < 3 else ch for ii, ch in enumerate(base))
            # 奇数条整板略深，偶数条浅，形成纵缝而不是棋盘
            if k % 2 == 1:
                col = tuple(clamp(ch * 0.86, 0, 1) if ii < 3 else ch for ii, ch in enumerate(col))
            deck.quad_out(a, d, c, b, col, (0, 1, 0))

    # 舱口三处
    def hatch_at(t, w, length, label_shade=0.0):
        # 找最近站
        z = z_of(t)
        bh = beam_half(t) * 0.9
        y = deck_side_y(t) + 0.045
        coam_h = 0.07
        add_box(fit, (0, y + coam_h * 0.5, z), (w, coam_h, length), TEAK_DK)
        # 盖：席纹，略低于围板顶
        add_box(fit, (0, y + coam_h + 0.012, z), (w * 0.88, 0.025, length * 0.86), mix(DECK, TEAK_DK, 0.35))
        # 横格
        for k in range(-1, 2):
            add_box(fit, (0, y + coam_h + 0.03, z + k * length * 0.22), (w * 0.82, 0.018, 0.025), BATTEN)

    hatch_at(0.30, 0.55, 0.72)
    hatch_at(0.48, 0.62, 0.86)
    hatch_at(0.64, 0.50, 0.64)

    # 桅座
    def partner(t, s):
        z = z_of(t)
        y = deck_side_y(t) + 0.02
        add_box(fit, (0, y + 0.025, z), (s, 0.05, s), TEAK_DK)

    partner(0.30, 0.42)
    partner(0.56, 0.50)

    # 桅
    def mast(t, height, radius):
        z = z_of(t)
        y0 = deck_side_y(t)
        add_cyl(fit, (0, y0, z), (0, y0 + height, z), radius, mix(TEAK_DK, TEAK, 0.4), 8)
        # 桅箍
        for k in range(3):
            yy = y0 + height * (0.25 + k * 0.22)
            add_cyl(fit, (0, yy, z), (0, yy + 0.03, z), radius * 1.35, IRON, 8)
        return (0, y0 + height, z), (0, y0, z)

    fore_top, fore_foot = mast(0.30, 4.15, 0.055)
    main_top, main_foot = mast(0.56, 5.35, 0.07)

    # 硬篷：沿船长方向的弯面，竹条鼓出
    def junk_sail(mast_z, foot_y, head_y, z_fwd, z_aft, camber, n_bat=8, n_u=12, shade=1.0):
        mast_x = 0.0
        # 帆在桅的一侧略偏，大部分面积在桅后（船尾方向 -Z 为后）
        for b in range(n_bat):
            v0 = b / n_bat
            v1 = (b + 1) / n_bat
            for u in range(n_u):
                u0 = u / n_u
                u1 = (u + 1) / n_u

                def sp(u, v):
                    z = lerp(z_fwd, z_aft, u)
                    y = lerp(foot_y, head_y, v)
                    # 上扬的桁：头略抬、略向前
                    y += 0.18 * v * math.sin(math.pi * u)
                    billow = math.sin(math.pi * u) * math.sin(math.pi * v)
                    x = camber * billow
                    # 靠桅的一边收一点
                    return (x, y, z)

                a, bpt, c, d = sp(u0, v0), sp(u1, v0), sp(u1, v1), sp(u0, v1)
                # 阴影：鼓起的中间更亮（受光），折缝更暗
                light = 0.72 + 0.28 * math.sin(math.pi * ((u0 + u1) * 0.5)) * (0.65 + 0.35 * v0)
                # 每根竹条下缘压一条暗
                if b % 1 == 0:
                    light *= 0.96
                g = light * shade
                # 顶点色只存明暗（给帆 shader 乘色相）。布是暖的，折缝更暗。
                col = (g, g * 0.98, g * 0.92, 1.0)
                sail.quad(a, bpt, c, d, col)
                back = tuple(c * 0.78 for c in col[:3]) + (1,)
                sail.quad(a, d, c, bpt, back)
            # 竹条：沿这一格的上沿
            if b > 0:
                p_prev = None
                v = v0
                for u in range(n_u + 1):
                    uu = u / n_u
                    z = lerp(z_fwd, z_aft, uu)
                    y = lerp(foot_y, head_y, v) + 0.18 * v * math.sin(math.pi * uu)
                    x = camber * math.sin(math.pi * uu) * math.sin(math.pi * v)
                    p = (x, y, z)
                    if p_prev:
                        rad = 0.034 if b in (1, n_bat - 1) else 0.026
                        add_cyl(fit, (p_prev[0] + 0.04, p_prev[1], p_prev[2]), (p[0] + 0.04, p[1], p[2]), rad, BATTEN, 6, caps=False)
                    p_prev = p

    # 前帆、主帆。camber 朝 +X，转航向时是同一条船的不同面
    junk_sail(
        z_of(0.30),
        deck_side_y(0.30) + 0.85,
        deck_side_y(0.30) + 3.55,
        z_of(0.18),
        z_of(0.40),
        camber=0.42,
        n_bat=7,
        n_u=10,
    )
    junk_sail(
        z_of(0.56),
        deck_side_y(0.56) + 0.7,
        deck_side_y(0.56) + 4.7,
        z_of(0.42),
        z_of(0.70),
        camber=0.55,
        n_bat=9,
        n_u=12,
    )

    # 缭绳：帆后下角到甲板
    rope(fit, (0.35, deck_side_y(0.40) + 0.9, z_of(0.40)), (0.35, deck_side_y(0.46) + 0.15, z_of(0.46)), 0.12, 0.012, ROPE)
    rope(fit, (0.45, deck_side_y(0.70) + 0.75, z_of(0.70)), (0.40, deck_side_y(0.78) + 0.2, z_of(0.78)), 0.15, 0.014, ROPE)
    # 头索
    rope(fit, (0.0, fore_top[1] * 0.92, fore_top[2]), (0.0, deck_side_y(0.06) + 0.4, z_of(0.04)), 0.05, 0.012, ROPE)
    rope(fit, (0.0, main_top[1] * 0.95, main_top[2]), (0.0, deck_side_y(0.08) + 0.35, z_of(0.06)), 0.08, 0.012, ROPE)

    # 低艉棚（一层，不是楼）
    t_cab0, t_cab1 = 0.78, 0.93
    zc0, zc1 = z_of(t_cab1), z_of(t_cab0)  # zc0 更靠艉（更小）
    zc = (zc0 + zc1) * 0.5
    cab_l = abs(zc1 - zc0)
    y_base = deck_side_y(0.86) + 0.02
    cab_w = beam_half(0.86) * 1.35
    cab_h = 0.62
    add_box(fit, (0, y_base + cab_h * 0.5, zc), (cab_w, cab_h, cab_l), mix(TEAK, TEAK_DK, 0.25))
    # 卷棚：一整片拱顶，瓦沟横过船身，不再是几根方木
    seg_x, seg_z = 12, 10
    for ix in range(seg_x):
        for iz in range(seg_z):
            def rp(ix, iz, seg_x=seg_x, seg_z=seg_z):
                u = ix / seg_x
                v = iz / seg_z
                x = lerp(-cab_w * 0.58, cab_w * 0.58, u)
                z = lerp(zc0 - 0.02, zc1 + 0.02, v)
                arch = math.sin(clamp(u, 0, 1) * math.pi)
                y = y_base + cab_h + 0.03 + 0.20 * arch
                return (x, y, z)
            a, b = rp(ix, iz), rp(ix + 1, iz)
            c, d = rp(ix + 1, iz + 1), rp(ix, iz + 1)
            col = ROOF_DK if (iz % 2 == 0) else ROOF
            fit.quad_out(a, b, c, d, col, (0, 1, 0))
    # 窗：暗洞 + 格子
    for s in (-1, 1):
        add_box(fit, (s * cab_w * 0.52, y_base + cab_h * 0.55, zc), (0.04, 0.22, 0.28), (0.08, 0.06, 0.05, 1))
        add_box(fit, (s * (cab_w * 0.52 + 0.01), y_base + cab_h * 0.55, zc), (0.015, 0.24, 0.02), TEAK_LT)
        add_box(fit, (s * (cab_w * 0.52 + 0.01), y_base + cab_h * 0.55, zc), (0.015, 0.02, 0.30), TEAK_LT)
    # 艉门
    add_box(fit, (0, y_base + 0.22, zc0 - 0.01), (0.28, 0.40, 0.04), (0.10, 0.07, 0.05, 1))

    # 舵：开孔用深色圆饼贴在舵叶上
    rud_z = z_of(1.0) - 0.05
    add_box(fit, (0, 0.05, rud_z - 0.12), (0.07, 1.45, 0.78), mix(TEAK_DK, TAR, 0.35))
    for yy in (0.42, 0.08, -0.28):
        add_cyl(fit, (-0.05, yy, rud_z - 0.12), (0.05, yy, rud_z - 0.12), 0.09, (0.04, 0.03, 0.028, 1), 8)
    # 舵杆升上甲板
    add_cyl(fit, (0, 0.5, rud_z + 0.05), (0, deck_side_y(0.98) + 0.55, z_of(0.95)), 0.045, TEAK_DK, 7)
    # 舵柄
    add_box(fit, (0.0, deck_side_y(0.96) + 0.48, z_of(0.90)), (0.08, 0.05, 0.7), TEAK)

    # 绞盘 / 锚
    yb = deck_side_y(0.10) + 0.05
    add_cyl(fit, (-0.22, yb, z_of(0.10)), (0.22, yb, z_of(0.10)), 0.07, TEAK_DK, 8)
    add_box(fit, (0, yb + 0.02, z_of(0.10)), (0.08, 0.08, 0.55), TEAK)
    # 锚
    add_cyl(fit, (0.55, deck_side_y(0.12), z_of(0.12)), (0.85, deck_side_y(0.08) - 0.05, z_of(0.05)), 0.025, IRON, 6)
    add_box(fit, (0.88, deck_side_y(0.08), z_of(0.04)), (0.16, 0.08, 0.08), IRON_LT)

    # 系缆桩
    for t, x in ((0.16, 0.45), (0.16, -0.45), (0.72, 0.40), (0.72, -0.40)):
        y = deck_side_y(t) + 0.02
        add_cyl(fit, (x, y, z_of(t)), (x, y + 0.22, z_of(t)), 0.035, TEAK_DK, 6)
        add_cyl(fit, (x, y + 0.20, z_of(t) - 0.04), (x, y + 0.20, z_of(t) + 0.04), 0.02, TEAK, 5)

    # 船眼（泉州船眼睛）
    for s in (-1, 1):
        t = 0.07
        x = s * beam_half(t) * 0.72
        y = deck_side_y(t) * 0.55
        z = z_of(t)
        add_sphere(fit, (x, y, z + 0.02), 0.13, EYE_W, 8, 6)
        add_sphere(fit, (x + s * 0.045, y, z + 0.10), 0.05, EYE_K, 6, 5)
        add_cyl(fit, (x, y, z - 0.02), (x, y, z + 0.12), 0.155, GOLD, 8, caps=False)

    # 舷墙排水孔：一排小暗块
    for i in range(6, nst - 6, 3):
        t, z, ring = stations[i]
        x = ring[-2][0]
        y = ring[-4][1]
        add_box(fit, (x, y, z), (0.05, 0.04, 0.07), (0.05, 0.04, 0.03, 1))
        add_box(fit, (-x, y, z), (0.05, 0.04, 0.07), (0.05, 0.04, 0.03, 1))

    # 水线厚腰板（外飘一条）
    for i in range(nst - 1):
        t0, z0, r0 = stations[i]
        t1, z1, r1 = stations[i + 1]
        # 取近甲板的一圈外推
        for ring, z, t in ((r0, z0, t0),):
            pass
        j = len(r0) - 4
        def wale_pt(ring, z, push):
            x, y = ring[j]
            return (x * (1 + push) + (0.03 if x > 0 else 0), y, z)
        a = wale_pt(r0, z0, 0.0)
        b = wale_pt(r1, z1, 0.0)
        c = (b[0] + 0.035, b[1] + 0.05, b[2])
        d = (a[0] + 0.035, a[1] + 0.05, a[2])
        fit.quad(a, b, c, d, WALE)
        fit.quad((-a[0], a[1], a[2]), (-d[0], d[1], d[2]), (-c[0], c[1], c[2]), (-b[0], b[1], b[2]), WALE)

    # 桶与箩
    add_cyl(fit, (0.55, deck_side_y(0.50), z_of(0.50)), (0.55, deck_side_y(0.50) + 0.28, z_of(0.50)), 0.11, mix(TEAK, IRON, 0.2), 8)
    add_cyl(fit, (-0.48, deck_side_y(0.44), z_of(0.44)), (-0.48, deck_side_y(0.44) + 0.16, z_of(0.44)), 0.13, ROPE, 8)

    # 接触阴影
    for i in range(14):
        a0 = i / 14 * math.tau
        a1 = (i + 1) / 14 * math.tau
        for k in range(4):
            r0 = 0.4 + k * 0.55
            r1 = r0 + 0.55
            alpha = 0.38 * (1.0 - k / 4) ** 1.4
            col = (0.01, 0.03, 0.05, alpha)
            def sp(a, r):
                return (math.cos(a) * r * 0.55, -0.02, math.sin(a) * r * 1.15)
            shadow.quad(sp(a0, r0), sp(a1, r0), sp(a1, r1), sp(a0, r1), col)

    # 修复艏封口：上面左舷那笔是坏的。把 hull 里法线长度异常的丢掉做不到。
    # 重画一个干净的艏斜面盖住。
    r = stations[0][2]
    z = stations[0][1]
    for j in range(len(r) - 1):
        a = (-r[j][0], r[j][1], z)
        b = (-r[j + 1][0], r[j + 1][1], z)
        tip = (0.0, lerp(r[j][1], r[j + 1][1], 0.5) + 0.02, z + 0.12)
        col = wood_at(0.02, j, len(r))
        hull.tri(a, tip, b, col, col, col)

    # 艉封板
    rt = stations[-1][2]
    zt = stations[-1][1]
    for j in range(len(rt) - 1):
        a = (rt[j][0], rt[j][1], zt)
        b = (rt[j + 1][0], rt[j + 1][1], zt)
        c = (-rt[j + 1][0], rt[j + 1][1], zt)
        d = (-rt[j][0], rt[j][1], zt)
        col = wood_at(0.98, j, len(rt))
        hull.quad_out(a, d, c, b, col, (0, 0, -1))

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
        op, lp = push_floats(flat_p)
        on, ln = push_floats(flat_n)
        oc, lc = push_floats(flat_c)
        oi, li = push_idx(prim.idx)
        bv0 = len(buffer_views)
        buffer_views.append({"buffer": 0, "byteOffset": op, "byteLength": lp, "target": 34962})
        buffer_views.append({"buffer": 0, "byteOffset": on, "byteLength": ln, "target": 34962})
        buffer_views.append({"buffer": 0, "byteOffset": oc, "byteLength": lc, "target": 34962})
        buffer_views.append({"buffer": 0, "byteOffset": oi, "byteLength": li, "target": 34963})
        a0 = len(accessors)
        accessors.append({
            "bufferView": bv0, "componentType": 5126, "count": len(prim.pos), "type": "VEC3",
            "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)],
        })
        accessors.append({"bufferView": bv0 + 1, "componentType": 5126, "count": len(prim.pos), "type": "VEC3"})
        accessors.append({"bufferView": bv0 + 2, "componentType": 5126, "count": len(prim.pos), "type": "VEC4"})
        accessors.append({"bufferView": bv0 + 3, "componentType": 5125, "count": len(prim.idx), "type": "SCALAR"})
        meshes.append({
            "name": prim.name,
            "primitives": [{
                "attributes": {"POSITION": a0, "NORMAL": a0 + 1, "COLOR_0": a0 + 2},
                "indices": a0 + 3,
                "material": mat_index[prim.material],
            }],
        })
        nodes.append({"name": prim.name, "mesh": len(meshes) - 1})

    root = {"name": "SongQuanzhou", "children": list(range(len(nodes)))}
    nodes.append(root)
    gltf = {
        "asset": {"version": "2.0", "generator": "nk1-song-quanzhou"},
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
