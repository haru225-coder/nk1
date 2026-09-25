# -*- coding: utf-8 -*-
"""墨影人物的持物（画布坐标，挂在 figures.Rig.hands 记下的手位上）。
持物是认人的关键：放大到约一个头宽（0.8–1.4×），斜放、伸出身形之外；画法是「淡墨面 + 焦墨结构线」，
不用白边圆角框。纸、笏、瓷、铜这类浅色物先留白再淡染，深色物（算盘、漆匣、刀鞘）用焦墨结构线勾出形。"""
import math

GOLD = (0.79, 0.63, 0.29)
AMBER = (0.86, 0.58, 0.22)
CINNABAR = (0.62, 0.17, 0.14)


# ───────────────────────── 小工具（画布坐标，尺寸以头部单位×r.s 计） ─────────────────────────
def _u(r, v):
    return v * r.s


def stroke(r, pts, w, ink=0.9, dry=0.35, profile="nail", **kw):
    r.part(dict(kind="stroke", pts=pts, width=_u(r, w), ink=ink, dry=dry, profile=profile, seed=r.n(), **kw))


def sweep(r, pts, w, ink=0.8, side=0.5, pale=0.35, dry=0.35, wet=0.4, profile="sweep", **kw):
    r.part(dict(kind="sweep", pts=pts, width=_u(r, w), ink=ink, side=side, pale=pale, dry=dry, wet=wet, seed=r.n(),
                profile=profile, **kw))


def wash(r, pts, tone, **kw):
    kw.setdefault("edge", 0.25)
    kw.setdefault("bloom", 0.1)
    r.part(dict(kind="wash", pts=pts, tone=tone, **kw))


def cover(r, pts, tone, rough=0.4, **kw):
    r.part(dict(kind="cover", pts=pts, tone=tone, rough=rough, **kw))


def tint(r, pts, rgb, amount=0.5, mode="mul"):
    r.part(dict(kind="tint", pts=pts, rgb=rgb, amount=amount, mode=mode))


def outline(r, pts, w=2.2, ink=0.85, dry=0.35, closed=True):
    stroke(r, list(pts) + ([pts[0]] if closed else []), w, ink=ink, dry=dry, profile="even")


def frame(c, ax_, ay_, pts):
    """局部坐标（沿 ax_、ay_ 两个画布方向的单位向量，已乘 r.s）→ 画布。"""
    return [(c[0] + x * ax_[0] + y * ay_[0], c[1] + x * ax_[1] + y * ay_[1]) for x, y in pts]


def basis(r, ang, sx=1.0):
    a = math.radians(ang)
    s = r.s
    return (math.cos(a) * s * sx, math.sin(a) * s * sx), (-math.sin(a) * s, math.cos(a) * s)


def ell(cx, cy, rx, ry, n=24, a0=0.0, a1=2 * math.pi, rot=0.0):
    cr, sr = math.cos(rot), math.sin(rot)
    out = []
    for i in range(n + 1 if a1 - a0 < 2 * math.pi - 1e-6 else n):
        a = a0 + (a1 - a0) * i / (n if a1 - a0 < 2 * math.pi - 1e-6 else n)
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * cr - y * sr, cy + x * sr + y * cr))
    return out


def hand_of(r, *which):
    for w in which:
        h = r.hands.get(w)
        if h:
            return h
    return None


def mid_hands(r):
    a, b = r.hands.get("near"), r.hands.get("far")
    if a and b:
        return ((a[0][0] + b[0][0]) / 2, (a[0][1] + b[0][1]) / 2)
    return (a or b)[0]


def pick(r, *poses):
    """摆了某种姿态的那只手（优先远侧——远侧手在身前、持物不被身形压住）。"""
    for w in ("far", "near"):
        h = r.hands.get(w)
        if h and h[1] in poses:
            return h
    return r.hands.get("far") or r.hands.get("near")


def fwd(r):
    """人物朝向的画面方向（+1 右 / -1 左）。"""
    return r.sg


def hand(r, h, grip=True, ang=None, size=1.0):
    """手：握拳（持杆、提灯、按剑）时画——淡墨一团、外廓一笔、横三道指节；捧物时不画手，由袖口托住物件
    （减笔人物的常法，也免得两团白手喧宾夺主）。h=(腕, 姿态, 肘)。"""
    if not grip:
        return None
    (wx, wy), _, (ex, ey) = h
    d = (wx - ex, wy - ey)
    ln = math.hypot(*d) or 1
    ux, uy = d[0] / ln, d[1] / ln
    c = (wx + ux * 9 * r.s * size, wy + uy * 9 * r.s * size)
    a = math.degrees(math.atan2(uy, ux)) if ang is None else ang
    X, Y = basis(r, a, 1.0)
    L, Wd = 14 * size, 11 * size
    shape = frame(c, X, Y, [(-L, -Wd * 0.7), (-L * 0.2, -Wd * 1.0), (L * 0.6, -Wd * 0.95), (L * 1.05, -Wd * 0.3),
                            (L * 0.95, Wd * 0.6), (L * 0.3, Wd * 1.05), (-L * 0.5, Wd * 0.9), (-L, Wd * 0.6)])
    r.part(dict(kind="reserve", pts=shape, amount=0.85, rough=0.6))
    wash(r, shape, 0.14, edge=0.35, var=0.4, bloom=0.0)
    stroke(r, shape[1:7], 1.7, ink=0.62, dry=0.4)
    for k in (-0.2, 0.25, 0.65):
        p0 = frame(c, X, Y, [(L * k, -Wd * 0.85)])[0]
        p1 = frame(c, X, Y, [(L * k + 2, Wd * 0.1)])[0]
        stroke(r, [p0, p1], 1.2, ink=0.5, dry=0.45)
    return c


# ───────────────────────── 身后 ─────────────────────────
def behind(r):
    sp = r.spec
    extra = sp.get("behind", [])
    extra = [extra] if isinstance(extra, str) else list(extra)
    ps = sp.get("prop", [])
    ps = ps if isinstance(ps, list) else [ps]
    bk = -r.sg                            # 背侧的画面方向
    hx, hy, s = r.hx, r.hy, r.s
    if "bow" in ps or "bow" in extra:      # 角弓：斜挎背后，弓梢探出肩外
        pts = [(hx + bk * 40 * s, hy - 60 * s), (hx + bk * 140 * s, hy + 10 * s), (hx + bk * 168 * s, hy + 140 * s),
               (hx + bk * 140 * s, hy + 300 * s)]
        sweep(r, pts, 9, ink=0.92, side=0.4, pale=0.5, dry=0.3, wet=0.3, profile="press")
        stroke(r, [pts[0], pts[-1]], 1.4, ink=0.7, dry=0.2, profile="even")
    if sp.get("medbox") or "medbox" in extra:   # 竹药箱：背在身后，箱顶从肩后探出；竹编斜纹
        c = (hx + bk * 150 * s, hy + 130 * s)
        X, Y = basis(r, -6 * bk)
        box = frame(c, X, Y, [(-44, -90), (44, -90), (46, 90), (-46, 90)])
        top = frame(c, X, Y, [(-44, -90), (44, -90), (36, -108), (-36, -108)])
        wash(r, box, 0.42, edge=0.3, var=0.4, sharp=True, dry_edge=0.4, dry_depth=10)
        wash(r, top, 0.7, edge=0.2, sharp=True)
        outline(r, box, 2.6, 0.9)
        for k in range(-3, 4):
            stroke(r, frame(c, X, Y, [(-44, k * 26 - 20), (44, k * 26 + 20)]), 1.4, ink=0.55, dry=0.55)
        stroke(r, frame(c, X, Y, [(-46, -20), (46, -20)]), 3.4, ink=0.92, dry=0.3, profile="even")
    if "luggage" in extra:                 # 身后捆好的箱笼
        for i, (dx, dy, w, h) in enumerate(((150, 250, 120, 86), (170, 160, 96, 72))):
            c = (hx + bk * dx * s, hy + dy * s)
            X, Y = basis(r, bk * (4 - 8 * i))
            box = frame(c, X, Y, [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)])
            wash(r, box, 0.5, edge=0.3, sharp=True, dry_edge=0.5, dry_depth=10)
            outline(r, box, 2.4, 0.88)
            stroke(r, frame(c, X, Y, [(-w / 2, -6), (w / 2, 6)]), 3.0, ink=0.9, dry=0.4)
            stroke(r, frame(c, X, Y, [(-10, -h / 2), (8, h / 2)]), 3.0, ink=0.9, dry=0.4)
    if "spear" in extra:                   # 身后立一杆枪，红缨
        x0 = hx + bk * 176 * s
        stroke(r, [(x0 + bk * 6 * s, 640), (x0, hy - 150 * s)], 5.5, ink=0.88, dry=0.3, profile="even")
        tip = [(x0 - 6 * s, hy - 150 * s), (x0, hy - 206 * s), (x0 + 6 * s, hy - 150 * s)]
        wash(r, tip, 0.9, sharp=True)
        tint(r, [(x0 - 12 * s, hy - 146 * s), (x0 + 12 * s, hy - 146 * s), (x0 + 16 * s, hy - 116 * s),
                 (x0 - 16 * s, hy - 116 * s)], CINNABAR, 0.75, "opaque")


# ───────────────────────── 身前 ─────────────────────────
def front(r):
    sp = r.spec
    r._hand_done = {}
    if sp.get("medbox"):                   # 药箱背带斜过前胸
        a, = r.B3([(-60, 110, 20)])
        b, = r.B3([(40, 200, 40)])
        c, = r.B3([(80, 280, 20)])
        stroke(r, [a, b, c], 5.0, ink=0.9, dry=0.4)
    ps = sp.get("prop", "none")
    i0 = len(r.parts)
    for p in (ps if isinstance(ps, list) else [ps]):
        done = dict(r._hand_done)
        _prop(r, p)
        done.update(r._hand_done)
        r._hand_done = done
    for q in r.parts[i0:]:                 # 持物记进 prop 图层：公服浅绛不罩到持物上
        q.setdefault("layer", "prop")
    if sp.get("tug"):                      # 攥着祖母衣袖：画面外伸进一截衣袖
        bk = -r.sg
        x0 = 0 if bk < 0 else 512
        h = r.hands.get("near")
        (wx, wy) = h[0] if h else (r.hx, r.hy + 200 * r.s)
        pts = [(x0, wy - 60 * r.s), ((x0 + wx) / 2, wy - 30 * r.s), (wx + bk * 20 * r.s, wy - 4 * r.s)]
        sweep(r, pts, 70, ink=0.62, side=0.6, pale=0.3, dry=0.4, wet=0.5, profile="flat")
        stroke(r, [(x0, wy - 20 * r.s), (wx + bk * 30 * r.s, wy + 10 * r.s)], 2.6, ink=0.85, dry=0.5)
        if h:
            hand(r, h, True)
    # 需要露手的姿态：手压在持物上
    for w in ("near", "far"):
        h = r.hands.get(w)
        if not h or h[1] in ("fold", "fold_low", "hang", "back", "empty"):
            continue
        if h[1] in ("hu", "hold", "present") and sp.get("hide_hands", True):
            continue
        if r._hand_done.get(w):
            continue
        hand(r, h, grip=h[1] in ("hilt", "staff", "oar", "one", "lantern", "up", "raise"))


def _prop(r, p):
    sp = r.spec
    rng = r.rng
    s = r.s
    f = fwd(r)
    if p in ("none", "bow"):
        return
    if p == "hu":                          # 象笏：双手合执于胸前，笏头齐颏，微斜
        cx, cy = mid_hands(r)
        X, Y = basis(r, -90 + f * 8)
        c = (cx, cy - 10 * s)
        slip = frame(c, X, Y, [(0, -9), (116, -8), (124, -3), (124, 3), (116, 8), (0, 9)])
        cover(r, slip, 0.06, rough=0.3)
        outline(r, slip, 1.9, 0.72)
        tint(r, slip, (0.93, 0.86, 0.7), 0.2)
    elif p in ("book", "ledger"):          # 线装书 / 账簿：斜透视，书脊四道线订，书口一叠厚页，题签一条
        cx, cy = mid_hands(r)
        rot = sp.get("prop_rot", -10 * f)
        X, Y = basis(r, rot)
        c = (cx + f * 10 * s, cy - 18 * s)
        w, h = 104, 72
        cov = frame(c, X, Y, [(-w / 2, -h / 2), (w / 2, -h / 2 - 4), (w / 2 + 2, h / 2 - 4), (-w / 2, h / 2)])
        pages = frame(c, X, Y, [(-w / 2, h / 2), (w / 2 + 2, h / 2 - 4), (w / 2 + 2, h / 2 + 12), (-w / 2, h / 2 + 16)])
        cover(r, cov, 0.3 if p == "ledger" else 0.22, rough=0.4)
        tint(r, cov, (0.78, 0.6, 0.36), 0.35)
        cover(r, pages, 0.05, rough=0.3)
        outline(r, cov, 2.6, 0.9)
        outline(r, pages, 1.8, 0.7)
        for k in range(1, 4):
            stroke(r, frame(c, X, Y, [(-w / 2, h / 2 + k * 4), (w / 2 + 2, h / 2 - 4 + k * 4)]), 1.1, ink=0.55,
                   dry=0.4)
        for k in range(4):                 # 线订
            y = -h / 2 + 10 + k * (h - 20) / 3.0
            stroke(r, frame(c, X, Y, [(-w / 2 - 2, y), (-w / 2 + 12, y)]), 2.0, ink=0.9, dry=0.2, profile="even")
        wash(r, frame(c, X, Y, [(w / 2 - 30, -h / 2 + 6), (w / 2 - 16, -h / 2 + 5), (w / 2 - 16, h / 2 - 16),
                                (w / 2 - 30, h / 2 - 15)]), 0.2, sharp=True)
        outline(r, frame(c, X, Y, [(w / 2 - 30, -h / 2 + 6), (w / 2 - 16, -h / 2 + 5), (w / 2 - 16, h / 2 - 16),
                                   (w / 2 - 30, h / 2 - 15)]), 1.4, 0.8)
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], False, ang=rot + (0 if w_ == "far" else 180), size=0.9)
    elif p == "scroll":                    # 书卷：斜握，卷轴两头
        cx, cy = mid_hands(r)
        X, Y = basis(r, -28 * f)
        c = (cx, cy - 8 * s)
        body = frame(c, X, Y, [(-70, -13), (70, -13), (70, 13), (-70, 13)])
        cover(r, body, 0.1, rough=0.3)
        outline(r, body, 1.9, 0.75)
        stroke(r, frame(c, X, Y, [(-60, -4), (60, -4)]), 1.2, ink=0.45, dry=0.5)
        for e in (-1, 1):
            cap = [(pt[0], pt[1]) for pt in frame(c, X, Y, [(e * 70 + e * 2 * math.cos(a), 13 * math.sin(a))
                                                           for a in [i * math.pi / 6 for i in range(12)]])]
            wash(r, cap, 0.8, edge=0.2)
            stroke(r, frame(c, X, Y, [(e * 70, -16), (e * 84, -18), (e * 84, 18), (e * 70, 16)]), 3.2, ink=0.9,
                   dry=0.3, profile="even")
        stroke(r, frame(c, X, Y, [(-6, 13), (-10, 36), (-2, 52)]), 1.6, ink=0.7, dry=0.4)
        tint(r, frame(c, X, Y, [(-10, 12), (-4, 12), (0, 52), (-8, 52)]), CINNABAR, 0.6, "opaque")
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], True, size=0.9)
        r._hand_done = {"near": True, "far": True}
    elif p == "letter":                    # 书札：单封竖长，封面一条题签
        h = pick(r, "hold", "one", "present")
        (wx, wy) = mid_hands(r) if sp.get("pose", "").startswith("hold") else h[0]
        X, Y = basis(r, 8 * f)
        c = (wx + f * 8 * s, wy - 40 * s)
        sheet = frame(c, X, Y, [(-22, -50), (22, -52), (24, 46), (-20, 48)])
        cover(r, sheet, 0.06, rough=0.3)
        outline(r, sheet, 2.0, 0.78)
        wash(r, frame(c, X, Y, [(-6, -40), (6, -40), (6, 20), (-6, 20)]), 0.35, sharp=True)
        stroke(r, frame(c, X, Y, [(-16, -30), (16, -26)]), 1.0, ink=0.5, dry=0.3)
    elif p == "letter_up":                 # 高擎过顶的招降书：大张、上端卷起、竖行字
        cx, cy = mid_hands(r)
        X, Y = basis(r, -4 * f)
        c = (cx, cy - 56 * s)
        sheet = frame(c, X, Y, [(-58, -60), (0, -66), (58, -60), (60, 58), (0, 62), (-60, 58)])
        cover(r, sheet, 0.05, rough=0.3)
        outline(r, sheet, 2.2, 0.8)
        for k in range(6):
            x = -44 + k * 17
            stroke(r, frame(c, X, Y, [(x, -48), (x + 1, 40 - rng.uniform(0, 30))]), 1.6, ink=0.6, dry=0.55)
        stroke(r, frame(c, X, Y, [(-60, -58), (0, -70), (60, -58)]), 5.0, ink=0.85, dry=0.3, profile="swell")
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], True, size=0.9)
        r._hand_done = {"near": True, "far": True}
    elif p == "folded":                    # 反复折叠的劝降书：一小方折纸，两道折痕、一角揉皱
        h = pick(r, "one", "up")
        wx, wy = h[0]
        X, Y = basis(r, 18 * f)
        c = (wx + f * 18 * s, wy - 30 * s)
        sheet = frame(c, X, Y, [(-34, -40), (30, -44), (36, 0), (34, 40), (-6, 44), (-30, 38), (-38, 4)])
        cover(r, sheet, 0.06, rough=0.4)
        outline(r, sheet, 2.2, 0.82)
        stroke(r, frame(c, X, Y, [(-36, 2), (-6, -2), (34, 2)]), 1.6, ink=0.6, dry=0.3)
        stroke(r, frame(c, X, Y, [(-2, -42), (0, 0), (-4, 42)]), 1.6, ink=0.6, dry=0.3)
        stroke(r, frame(c, X, Y, [(14, -44), (22, -30), (30, -44)]), 1.4, ink=0.5, dry=0.4)
        for k in range(3):
            stroke(r, frame(c, X, Y, [(-26 + k * 8, -34), (-26 + k * 8, -8)]), 1.1, ink=0.45, dry=0.5)
    elif p == "slips":                     # 一叠货单：扇开三张
        h = pick(r, "one", "up")
        wx, wy = h[0]
        for k, rot in enumerate((-22, -6, 10)):
            X, Y = basis(r, rot * f)
            c = (wx + f * (8 + k * 6) * s, wy - 44 * s)
            sheet = frame(c, X, Y, [(-15, -44), (15, -44), (15, 40), (-15, 40)])
            cover(r, sheet, 0.05 + 0.03 * k, rough=0.3)
            outline(r, sheet, 1.8, 0.75)
            for j in range(2):
                stroke(r, frame(c, X, Y, [(-6 + j * 10, -34), (-5 + j * 10, 20)]), 1.1, ink=0.5, dry=0.5)
    elif p == "memorial":                  # 弹章：折子，四扇之字折，亮扇上有竖行字
        cx, cy = mid_hands(r)
        c = (cx + f * 6 * s, cy - 30 * s)
        X, Y = basis(r, -6 * f)
        xs = [-64, -32, 0, 32, 64]
        for i in range(4):
            lit = i % 2 == 0
            dz = 0 if lit else 6
            pan = frame(c, X, Y, [(xs[i], -46 + dz), (xs[i + 1], -46 + (6 - dz)), (xs[i + 1], 46 - (6 - dz)),
                                  (xs[i], 46 - dz)])
            cover(r, pan, 0.05 if lit else 0.2, rough=0.3)
            outline(r, pan, 1.6, 0.7)
            if lit:
                for k in range(3):
                    x = xs[i] + 8 + k * 8
                    stroke(r, frame(c, X, Y, [(x, -34), (x, 30 - rng.uniform(0, 20))]), 1.2, ink=0.55, dry=0.5)
        stroke(r, frame(c, X, Y, [(-64, -46), (64, -46)]), 2.4, ink=0.85, dry=0.3, profile="even")
    elif p == "abacus":                    # 黑漆算盘：斜透视，框、横梁、竖档、上二下五珠
        cx, cy = mid_hands(r)
        X, Y = basis(r, sp.get("prop_rot", -14 * f))
        c = (cx + f * 4 * s, cy - 18 * s)
        w, h = 150, 66
        sk = 16 * f                       # 透视：上沿后仰、左右不等高
        box = [(-w / 2 + sk, -h / 2), (w / 2 + sk, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
        P = frame(c, X, Y, box)
        cover(r, P, 0.2, rough=0.3)
        tint(r, P, (0.62, 0.42, 0.24), 0.3)
        sweep(r, [P[0], P[1]], 7, ink=0.92, side=0.3, pale=0.6, dry=0.2, wet=0.2, profile="flat")
        sweep(r, [P[3], P[2]], 8, ink=0.92, side=0.3, pale=0.6, dry=0.2, wet=0.2, profile="flat")
        sweep(r, [P[0], P[3]], 7, ink=0.92, side=0.3, pale=0.6, dry=0.2, wet=0.2, profile="flat")
        sweep(r, [P[1], P[2]], 7, ink=0.92, side=0.3, pale=0.6, dry=0.2, wet=0.2, profile="flat")
        beam_y = -h / 2 + h * 0.32
        stroke(r, frame(c, X, Y, [(-w / 2 + sk * 0.68, beam_y), (w / 2 + sk * 0.68, beam_y)]), 3.4, ink=0.9, dry=0.2,
               profile="even")
        n = 9
        for i in range(n):
            u = (i + 0.5) / n
            xt = -w / 2 + sk + w * u
            xb = -w / 2 + w * u
            stroke(r, frame(c, X, Y, [(xt, -h / 2 + 3), (xb, h / 2 - 3)]), 1.0, ink=0.6, dry=0.3, profile="even")
            up2 = rng.random() < 0.4
            lo_n = rng.randint(0, 3)
            for j, v in enumerate((0.12, 0.22)):
                vv = v + (0.06 if up2 and j == 1 else 0)
                x = xt + (xb - xt) * vv
                y = -h / 2 + h * vv
                wash(r, ell(*frame(c, X, Y, [(x, y)])[0], 5.2 * s, 3.4 * s, 10, rot=math.radians(-14 * f)), 0.92,
                     edge=0.1, var=0.1, bloom=0.0)
            for j in range(5):
                vv = 0.42 + j * 0.105 + (0.04 if j >= 5 - lo_n else 0)
                x = xt + (xb - xt) * vv
                y = -h / 2 + h * vv
                wash(r, ell(*frame(c, X, Y, [(x, y)])[0], 5.2 * s, 3.4 * s, 10, rot=math.radians(-14 * f)), 0.92,
                     edge=0.1, var=0.1, bloom=0.0)
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], False, size=0.9)
        r._hand_done = {"near": True, "far": True}
    elif p == "beads":                     # 念珠：一串木珠自手中垂下，末端一束穗
        h = pick(r, "one", "hold", "fold_low")
        wx, wy = h[0]
        n = 18
        for i in range(n):
            a = math.pi * (0.1 + 0.8 * i / (n - 1))
            x = wx + 26 * s * math.cos(a) * 0.8
            y = wy + 14 * s + 62 * s * math.sin(a)
            wash(r, ell(x, y, 5.4 * s, 5.0 * s, 10), 0.7, edge=0.3, var=0.2, bloom=0.0)
            stroke(r, ell(x, y, 5.4 * s, 5.0 * s, 8, math.pi, 2 * math.pi), 1.2, ink=0.9, dry=0.1, profile="even")
        stroke(r, [(wx, wy + 76 * s), (wx + 3 * s, wy + 104 * s)], 5.0, ink=0.8, dry=0.5, profile="taper")
        if h[1] not in ("fold_low", "fold"):
            hand(r, h, True)
            r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p in ("bowl", "jianzhan"):        # 粗陶碗 / 黑釉建盏：俯看的椭圆口沿
        h = pick(r, "one", "hold")
        two = r.hands.get("near") and r.hands.get("far") and r.hands["near"][1] == r.hands["far"][1]
        cx, cy = mid_hands(r) if two else h[0]
        cy -= 18 * s
        cx += f * 8 * s
        rw = 46 if p == "bowl" else 34
        rim = ell(cx, cy, rw * s, rw * 0.32 * s, 28)
        body = [(cx + rw * s * math.cos(a), cy + rw * 0.32 * s * math.sin(a))
                for a in [math.pi * i / 14 for i in range(15)]][::-1]
        body = [(cx - rw * s, cy)] + [(cx - rw * 0.8 * s, cy + rw * 0.46 * s), (cx - rw * 0.42 * s, cy + rw * 0.72 * s),
                                      (cx + rw * 0.42 * s, cy + rw * 0.72 * s), (cx + rw * 0.8 * s, cy + rw * 0.46 * s),
                                      (cx + rw * s, cy)]
        r.part(dict(kind="reserve", pts=body, amount=0.9, rough=0.4))
        wash(r, body, 0.32 if p == "bowl" else 0.86, edge=0.35, var=0.4, bloom=0.15)
        if p == "bowl":
            tint(r, body, (0.72, 0.56, 0.4), 0.4)
        stroke(r, body, 2.4, ink=0.88, dry=0.35, profile="even", )
        cover(r, rim, 0.3 if p == "bowl" else 0.6, rough=0.2)
        stroke(r, rim + rim[:1], 2.2, ink=0.9, dry=0.3, profile="even")
        stroke(r, [(cx - rw * 0.62 * s, cy + rw * 0.18 * s), (cx - rw * 0.4 * s, cy + rw * 0.56 * s)], 3.0, ink=0.15,
               dry=0.4)
        if p == "jianzhan":                # 兔毫纹：几道细丝
            for k in range(5):
                x = cx - rw * 0.6 * s + k * rw * 0.3 * s
                r.part(dict(kind="rstroke", pts=[(x, cy + 4 * s), (x * 0.96 + cx * 0.04, cy + rw * 0.6 * s)],
                            width=1.2 * s, amount=0.35, dry=0.5, profile="nail", seed=r.n()))
        hand(r, h, False)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "stone":                     # 拳大青石
        h = pick(r, "one", "up")
        wx, wy = h[0]
        c = (wx + f * 12 * s, wy - 30 * s)
        pts = [(c[0] - 30 * s, c[1] - 12 * s), (c[0] - 4 * s, c[1] - 34 * s), (c[0] + 28 * s, c[1] - 22 * s),
               (c[0] + 34 * s, c[1] + 10 * s), (c[0] + 4 * s, c[1] + 26 * s), (c[0] - 26 * s, c[1] + 14 * s)]
        wash(r, pts, 0.55, edge=0.4, var=0.5, bloom=0.3, dry_edge=0.3)
        stroke(r, pts + pts[:1], 3.0, ink=0.9, dry=0.55, profile="even")
        stroke(r, [pts[1], (c[0] + 2 * s, c[1] - 4 * s), pts[4]], 1.8, ink=0.6, dry=0.5)
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "compass":                   # 小铜针盘：颈挂于胸前，盘面八向刻度、磁针一道
        c, = r.B3([(8, 178, 46)])
        R = 30 * s
        disk = ell(c[0], c[1], R, R * 0.92, 28)
        cover(r, disk, 0.12, rough=0.2)
        tint(r, disk, GOLD, 0.55)
        stroke(r, disk + disk[:1], 3.2, ink=0.9, dry=0.2, profile="even")
        stroke(r, ell(c[0], c[1], R * 0.6, R * 0.55, 20) + [ell(c[0], c[1], R * 0.6, R * 0.55, 20)[0]], 1.4,
               ink=0.7, dry=0.3, profile="even")
        for k in range(8):
            a = k * math.pi / 4
            stroke(r, [(c[0] + R * 0.72 * math.cos(a), c[1] + R * 0.66 * math.sin(a)),
                       (c[0] + R * 0.9 * math.cos(a), c[1] + R * 0.83 * math.sin(a))], 1.4, ink=0.85, dry=0.2)
        stroke(r, [(c[0] - R * 0.4, c[1] + R * 0.3), (c[0] + R * 0.4, c[1] - R * 0.3)], 3.0, ink=0.95, dry=0.1,
               profile="swell")
        a, = r.B3([(-30, 96, 30)])
        b, = r.B3([(34, 96, 30)])
        stroke(r, [a, (c[0] - R * 0.5, c[1] - R)], 1.8, ink=0.8, dry=0.3, profile="even")
        stroke(r, [b, (c[0] + R * 0.5, c[1] - R)], 1.8, ink=0.8, dry=0.3, profile="even")
    elif p == "whip":                      # 马鞭：杆握在手，鞭梢甩出身外
        h = pick(r, "one", "up", "hang")
        wx, wy = h[0]
        top = (wx + f * 40 * s, wy - 90 * s)
        sweep(r, [(wx - f * 6 * s, wy + 24 * s), top], 7, ink=0.92, side=0.3, pale=0.5, dry=0.25, wet=0.2,
              profile="flat")
        stroke(r, [top, (top[0] + f * 60 * s, top[1] - 70 * s), (top[0] + f * 40 * s, top[1] - 150 * s),
                   (top[0] + f * 90 * s, top[1] - 200 * s)], 2.8, ink=0.88, dry=0.55)
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "lantern":                   # 灯笼：全卡唯一的暖光
        h = pick(r, "lantern", "one")
        wx, wy = h[0]
        lx, ly = wx + f * 30 * s, wy + 70 * s
        stroke(r, [(wx, wy), (wx + f * 16 * s, wy + 12 * s), (lx, ly - 40 * s)], 2.2, ink=0.85, dry=0.2,
               profile="even")
        body = ell(lx, ly, 32 * s, 40 * s, 24)
        r.part(dict(kind="glow", c=(lx, ly), r=170 * s, amount=0.65, falloff=1.6))
        cover(r, body, 0.02, rough=0.3)
        tint(r, body, AMBER, 0.62, "opaque")
        stroke(r, body + body[:1], 2.4, ink=0.8, dry=0.35, profile="even")
        for dx in (-16, 0, 16):
            stroke(r, [(lx + dx * 0.8 * s, ly - 36 * s), (lx + dx * 1.3 * s, ly), (lx + dx * 0.8 * s, ly + 36 * s)],
                   1.3, ink=0.55, dry=0.4, profile="even")
        for yy in (-42, 42):
            wash(r, [(lx - 18 * s, ly + yy * s - 4 * s), (lx + 18 * s, ly + yy * s - 4 * s),
                     (lx + 18 * s, ly + yy * s + 4 * s), (lx - 18 * s, ly + yy * s + 4 * s)], 0.9, sharp=True)
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "whisk":                     # 拂尘：柄斜出肩外，马尾淡墨游丝垂过臂
        h = pick(r, "one", "up")
        wx, wy = h[0]
        top = (wx - f * 30 * s, wy - 110 * s)
        sweep(r, [(wx + f * 6 * s, wy + 22 * s), top], 7, ink=0.92, side=0.3, pale=0.5, dry=0.25, wet=0.2,
              profile="flat")
        tip = (top[0] + f * 60 * s, top[1] + 170 * s)
        sweep(r, [top, (top[0] + f * 30 * s, top[1] + 80 * s), tip], 34, ink=0.16, side=0.2, pale=0.5, dry=0.5,
              wet=0.3, profile="drop")
        for k in range(12):
            a = (top[0] + rng.uniform(-4, 4) * s, top[1] + rng.uniform(-2, 4) * s)
            b = (top[0] + f * rng.uniform(40, 80) * s, top[1] + rng.uniform(130, 190) * s)
            m = ((a[0] + b[0]) / 2 - f * 10 * s, (a[1] + b[1]) / 2)
            stroke(r, [a, m, b], 1.2, ink=0.4, dry=0.5)
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "seal_box":                  # 锦匣所盛传国玺：锦袱包着的匣（顶、前、侧三面），顶上打结
        cx, cy = mid_hands(r)
        c = (cx, cy - 34 * s)
        w, h, d = 92, 54, 30
        X, Y = basis(r, -3 * f)
        dx, dy = f * d * 0.75, -d * 0.55
        front_ = frame(c, X, Y, [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)])
        top = frame(c, X, Y, [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2 + dx, -h / 2 + dy), (-w / 2 + dx, -h / 2 + dy)])
        side = frame(c, X, Y, [(f * w / 2, -h / 2), (f * w / 2 + dx, -h / 2 + dy), (f * w / 2 + dx, h / 2 + dy),
                               (f * w / 2, h / 2)])
        cover(r, front_ + [], 0.34, rough=0.4)
        wash(r, side, 0.5, sharp=True, edge=0.2)
        cover(r, top, 0.16, rough=0.3)
        tint(r, front_ + top, (0.74, 0.42, 0.26), 0.5)
        tint(r, side, (0.6, 0.34, 0.22), 0.5)
        outline(r, front_, 2.4, 0.9)
        outline(r, top, 2.0, 0.85)
        stroke(r, [side[1], side[2], side[3]], 2.2, ink=0.88, dry=0.3, profile="even")
        # 锦纹：前面几朵淡墨团花 + 泥金点
        for x, y in ((-26, -6), (4, 8), (30, -10), (-8, 18)):
            q = frame(c, X, Y, [(x, y)])[0]
            stroke(r, ell(q[0], q[1], 6 * s, 5 * s, 10) + [ell(q[0], q[1], 6 * s, 5 * s, 10)[0]], 1.3, ink=0.55,
                   dry=0.3, profile="even")
            tint(r, ell(q[0], q[1], 2.4 * s, 2.4 * s, 8), GOLD, 0.8, "opaque")
        # 锦袱结：两只布耳 + 一段垂尾
        k = frame(c, X, Y, [(dx * 0.5, -h / 2 + dy * 0.5)])[0]
        for e in (-1, 1):
            ear = [k, (k[0] + e * 20 * s, k[1] - 24 * s), (k[0] + e * 30 * s, k[1] - 6 * s)]
            sweep(r, ear, 14, ink=0.5, side=0.4, pale=0.4, dry=0.3, wet=0.4, profile="press")
        sweep(r, [k, (k[0] - f * 8 * s, k[1] + 30 * s), (k[0] - f * 4 * s, k[1] + 52 * s)], 9, ink=0.5, side=0.4,
              pale=0.4, dry=0.4, wet=0.3, profile="drop")
        tint(r, [(k[0] - 34 * s, k[1] - 30 * s), (k[0] + 34 * s, k[1] - 30 * s), (k[0] + 34 * s, k[1] + 56 * s),
                 (k[0] - 34 * s, k[1] + 56 * s)], (0.66, 0.28, 0.2), 0.35)
        r._hand_done = {"near": True, "far": True}
    elif p == "cricket_jar":               # 蟋蟀罐：矮圆陶罐，3/4 俯看——罐身、带钮的罐盖、两道箍纹
        cx, cy = mid_hands(r)
        c = (cx + f * 4 * s, cy - 28 * s)
        R, Hh, e = 38 * s, 40 * s, 0.34
        top_y, bot_y = c[1] - Hh / 2, c[1] + Hh / 2
        bulge = 1.08
        body = ell(c[0], top_y, R, R * e, 12, 0, math.pi)[::-1]          # 上沿后半（被盖挡住，只取轮廓）
        body = [(c[0] - R, top_y), (c[0] - R * bulge, c[1]), (c[0] - R * 0.96, bot_y)] + \
            ell(c[0], bot_y, R * 0.96, R * 0.96 * e, 14, math.pi, 0)[::-1][1:-1] + \
            [(c[0] + R * 0.96, bot_y), (c[0] + R * bulge, c[1]), (c[0] + R, top_y)]
        body = [(c[0] - R, top_y), (c[0] - R * bulge, c[1]), (c[0] - R * 0.96, bot_y)] + \
            [(c[0] + R * 0.96 * math.cos(a), bot_y + R * 0.96 * e * math.sin(a))
             for a in [math.pi - math.pi * i / 12 for i in range(13)]] + \
            [(c[0] + R * bulge, c[1]), (c[0] + R, top_y)]
        wash(r, body, 0.46, edge=0.4, var=0.45, bloom=0.25)
        tint(r, body, (0.66, 0.52, 0.38), 0.35)
        for yy in (c[1] - Hh * 0.12, c[1] + Hh * 0.22):   # 两道箍纹（前半椭圆）
            rr = R * bulge * 0.99
            stroke(r, [(c[0] + rr * math.cos(a), yy + rr * e * math.sin(a))
                       for a in [math.pi - math.pi * i / 12 for i in range(13)]], 1.6, ink=0.8, dry=0.35,
                   profile="even")
        lid = ell(c[0], top_y, R * 1.06, R * 1.06 * e, 28)
        cover(r, lid, 0.2, rough=0.25)
        stroke(r, lid + lid[:1], 2.4, ink=0.9, dry=0.2, profile="even")
        stroke(r, [(c[0] - R * 1.04, top_y), (c[0] - R * 1.0, top_y + 6 * s)], 2.0, ink=0.85, dry=0.3, profile="even")
        stroke(r, [(c[0] + R * 1.04, top_y), (c[0] + R * 1.0, top_y + 6 * s)], 2.0, ink=0.85, dry=0.3, profile="even")
        wash(r, ell(c[0], top_y - 3 * s, R * 0.2, R * 0.14, 12), 0.9)
        stroke(r, body[:3], 2.6, ink=0.9, dry=0.3, profile="even")
        stroke(r, body[-3:], 2.6, ink=0.9, dry=0.3, profile="even")
        stroke(r, body[2:-2], 2.4, ink=0.88, dry=0.35, profile="even")
        r.part(dict(kind="rstroke", pts=[(c[0] - R * 0.62, top_y + 8 * s), (c[0] - R * 0.66, bot_y - 6 * s)],
                    width=4 * s, amount=0.4, dry=0.5, profile="nail", seed=r.n()))
        r._hand_done = {"near": True, "far": True}
    elif p == "brush":                     # 御笔：笔杆斜出，笔头焦墨
        h = pick(r, "one", "up")
        wx, wy = h[0]
        a = (wx + f * 8 * s, wy + 16 * s)
        b = (wx - f * 34 * s, wy - 96 * s)
        sweep(r, [b, a], 5, ink=0.85, side=0.3, pale=0.6, dry=0.2, wet=0.2, profile="flat")
        tipd = (a[0] + (a[0] - b[0]) * 0.28, a[1] + (a[1] - b[1]) * 0.28)
        sweep(r, [a, tipd], 11, ink=0.95, side=0.2, pale=0.5, dry=0.2, wet=0.3, profile="drop")
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "staff":                     # 竹杖：自下而上，高出肩头；竹节
        h = pick(r, "staff")
        wx, wy = h[0]
        top = (wx - f * 6 * s, wy - 190 * s)
        sweep(r, [(wx + f * 10 * s, 640), (wx, wy), top], 9, ink=0.85, side=0.5, pale=0.4, dry=0.3, wet=0.2,
              profile="flat")
        for k in range(6):
            u = k / 5.0
            y = top[1] + (640 - top[1]) * u
            x = top[0] + (wx + f * 10 * s - top[0]) * u
            stroke(r, [(x - 7 * s, y), (x + 7 * s, y + 1 * s)], 2.4, ink=0.95, dry=0.2, profile="even")
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "keys":                      # 库房铜钥一串：大铜环 + 四把长钥（钥齿）
        h = pick(r, "one", "up")
        if sp.get("keys_waist") or not h or h[1] in ("hang", "fold_low", "fold"):
            c, = r.B3([(-70, 300, 30)])
        else:
            c = (h[0][0] + f * 10 * s, h[0][1] + 6 * s)
        R = 14 * s
        ring = ell(c[0], c[1], R, R, 16)
        stroke(r, ring + ring[:1], 3.2, ink=0.9, dry=0.2, profile="even")
        tint(r, ring, GOLD, 0.35)
        for k, ang in enumerate((-30, -10, 12, 32)):
            a = math.radians(90 + ang)
            p0 = (c[0] + R * math.cos(a), c[1] + R * math.sin(a))
            ln = (62 + 8 * (k % 2)) * s
            p1 = (p0[0] + ln * math.cos(a), p0[1] + ln * math.sin(a))
            sweep(r, [p0, p1], 5, ink=0.9, side=0.3, pale=0.5, dry=0.2, wet=0.2, profile="flat")
            # 钥齿
            nx, ny = -math.sin(a), math.cos(a)
            q0 = (p1[0] - 10 * s * math.cos(a), p1[1] - 10 * s * math.sin(a))
            stroke(r, [q0, (q0[0] + nx * 12 * s, q0[1] + ny * 12 * s)], 3.4, ink=0.9, dry=0.2, profile="even")
            stroke(r, [p1, (p1[0] + nx * 10 * s, p1[1] + ny * 10 * s)], 3.4, ink=0.9, dry=0.2, profile="even")
            tint(r, [(p0[0] - 4 * s, p0[1]), (p0[0] + 4 * s, p0[1]), (p1[0] + 4 * s, p1[1]), (p1[0] - 4 * s, p1[1])],
                 GOLD, 0.3)
        if h and h[1] not in ("hang", "fold_low", "fold") and not sp.get("keys_waist"):
            hand(r, h, True)
            r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "bell":                      # 串铃：一只厚铜环，举在手中摇
        h = pick(r, "one", "up")
        wx, wy = h[0]
        c = (wx + f * 22 * s, wy - 44 * s)
        R = 30 * s
        ring = ell(c[0], c[1], R, R * 0.92, 28)
        sweep(r, ring + ring[:2], 13, ink=0.7, side=0.6, pale=0.4, dry=0.25, wet=0.3, profile="flat")
        tint(r, ring, GOLD, 0.6)
        r.part(dict(kind="rstroke", pts=ell(c[0], c[1], R * 0.86, R * 0.8, 20, math.pi * 1.1, math.pi * 1.6),
                    width=2.2 * s, amount=0.55, dry=0.3, profile="even", seed=r.n()))
        for a in (-0.9, 0.0, 0.9):
            bx, by = c[0] + R * 1.2 * math.sin(a), c[1] + R * 1.12 * math.cos(a)
            wash(r, ell(bx, by, 6 * s, 6 * s, 10), 0.8, edge=0.2)
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "needle_roll":               # 针囊：摊开的布卷，一排银针
        cx, cy = mid_hands(r)
        X, Y = basis(r, -8 * f)
        c = (cx, cy - 26 * s)
        cloth = frame(c, X, Y, [(-62, -30), (62, -34), (64, 30), (-60, 34)])
        wash(r, cloth, 0.45, edge=0.3, var=0.3, sharp=True)
        tint(r, cloth, (0.3, 0.38, 0.48), 0.35)
        outline(r, cloth, 2.2, 0.88)
        stroke(r, frame(c, X, Y, [(-60, 6), (63, 2)]), 2.0, ink=0.85, dry=0.3, profile="even")
        for k in range(9):
            x = -50 + k * 12.5
            r.part(dict(kind="rstroke", pts=frame(c, X, Y, [(x, -40 - (k % 3) * 4), (x + 1, 2)]), width=1.8 * s,
                        amount=0.75, dry=0.2, profile="even", seed=r.n()))
            stroke(r, frame(c, X, Y, [(x - 2, -8), (x + 3, -8)]), 2.0, ink=0.85, dry=0.2, profile="even")
        roll = frame(c, X, Y, [(62, -34), (76, -32), (78, 28), (64, 30)])
        wash(r, roll, 0.7, sharp=True)
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], False, size=0.85)
        r._hand_done = {"near": True, "far": True}
    elif p == "needle_bag":                # 针囊与小药刀：挂在腰间（放大）
        c, = r.B3([(70, 300, 32)])
        bag = [(c[0] - 16 * s, c[1] - 6 * s), (c[0] + 16 * s, c[1] - 6 * s), (c[0] + 20 * s, c[1] + 34 * s),
               (c[0], c[1] + 50 * s), (c[0] - 20 * s, c[1] + 34 * s)]
        wash(r, bag, 0.5, edge=0.3)
        outline(r, bag, 2.4, 0.9)
    elif p == "sword":                     # 佩剑：手按剑首，剑鞘斜挂
        h = pick(r, "hilt")
        wx, wy = h[0]
        bk = -f
        sheath_a = (wx + bk * 4 * s, wy + 20 * s)
        sheath_b = (wx + bk * 80 * s, 640)
        sweep(r, [sheath_a, sheath_b], 13, ink=0.9, side=0.5, pale=0.35, dry=0.3, wet=0.3, profile="flat")
        r.part(dict(kind="rstroke", pts=[(sheath_a[0] + 4 * s, sheath_a[1]), (sheath_b[0] + 4 * s, sheath_b[1])],
                    width=1.8 * s, amount=0.5, dry=0.4, profile="even", seed=r.n()))
        stroke(r, [(wx - 26 * s, wy + 10 * s), (wx + 24 * s, wy + 24 * s)], 6, ink=0.92, dry=0.2, profile="swell")
        stroke(r, [(wx + f * 2 * s, wy + 6 * s), (wx + f * 22 * s, wy - 46 * s)], 7, ink=0.92, dry=0.2,
               profile="even")
        wash(r, ell(wx + f * 24 * s, wy - 50 * s, 6 * s, 6 * s, 10), 0.92)
        if sp.get("sword_gold"):
            tint(r, [(wx - 28 * s, wy + 4 * s), (wx + 26 * s, wy + 18 * s), (wx + 26 * s, wy + 32 * s),
                     (wx - 28 * s, wy + 18 * s)], GOLD, 0.6, "opaque")
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "saber":                     # 弯刀：刀鞘弧挂腰间
        h = pick(r, "hilt")
        wx, wy = h[0]
        bk = -f
        sweep(r, [(wx + bk * 6 * s, wy + 18 * s), (wx + bk * 40 * s, wy + 90 * s), (wx + bk * 100 * s, 640)], 12,
              ink=0.9, side=0.5, pale=0.35, dry=0.3, wet=0.3, profile="flat")
        stroke(r, [(wx, wy + 6 * s), (wx + f * 18 * s, wy - 40 * s), (wx + f * 32 * s, wy - 48 * s)], 7, ink=0.92,
               dry=0.2, profile="even")
        hand(r, h, True)
        r._hand_done = {("far" if h is r.hands.get("far") else "near"): True}
    elif p == "knife":                     # 腰间短刀
        c, = r.B3([(40, 300, 40)])
        sweep(r, [(c[0] - f * 44 * s, c[1] + 18 * s), (c[0] + f * 44 * s, c[1] - 14 * s)], 10, ink=0.9, side=0.5,
              pale=0.35, dry=0.25, wet=0.3, profile="flat")
        stroke(r, [(c[0] + f * 44 * s, c[1] - 14 * s), (c[0] + f * 78 * s, c[1] - 26 * s)], 6, ink=0.9, dry=0.2,
               profile="even")
    elif p == "oar":                       # 橹：斜贯全身，两头伸出身外
        h = pick(r, "oar")
        wx, wy = h[0]
        a = (wx - f * 150 * s, 660)
        b = (wx + f * 150 * s, wy - 250 * s)
        sweep(r, [a, b], 13, ink=0.9, side=0.5, pale=0.4, dry=0.3, wet=0.3, profile="flat")
        blade = [(a[0] - f * 10 * s, 600), (a[0] + f * 30 * s, 560), (a[0] + f * 40 * s, 660), (a[0] - f * 20 * s, 660)]
        wash(r, blade, 0.7, edge=0.3, dry_edge=0.4, dry_depth=10)
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], True)
        r._hand_done = {"near": True, "far": True}
    elif p == "rubbing":                   # 油纸包好的拓本：十字捆绳
        cx, cy = mid_hands(r)
        X, Y = basis(r, -10 * f)
        c = (cx, cy - 16 * s)
        pts = frame(c, X, Y, [(-44, -30), (44, -34), (46, 30), (-42, 34)])
        wash(r, pts, 0.3, edge=0.3, var=0.4, sharp=True)
        tint(r, pts, (0.8, 0.62, 0.36), 0.45)
        outline(r, pts, 2.2, 0.85)
        stroke(r, frame(c, X, Y, [(0, -34), (2, 34)]), 2.2, ink=0.9, dry=0.3, profile="even")
        stroke(r, frame(c, X, Y, [(-44, 0), (46, -2)]), 2.2, ink=0.9, dry=0.3, profile="even")
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], False, size=0.8)
        r._hand_done = {"near": True, "far": True}
    elif p == "register":                  # 鱼鳞图册：摊开的册页（纸页有弧度），田块如鱼鳞；旁一束算筹
        cx, cy = mid_hands(r)
        X, Y = basis(r, -6 * f)
        c = (cx + f * 4 * s, cy - 22 * s)
        for e in (-1, 1):
            page = frame(c, X, Y, [(0, -34), (e * 30, -40), (e * 62, -36), (e * 64, 30), (e * 32, 26), (0, 32)])
            cover(r, page, 0.05, rough=0.3)
            outline(r, page, 1.8, 0.78)
            for i in range(3):             # 鱼鳞田块：一排排小弧
                for j in range(3):
                    x = e * (12 + j * 16 + (i % 2) * 8)
                    y = -24 + i * 16
                    stroke(r, frame(c, X, Y, [(x - 7, y + 4), (x, y - 3), (x + 7, y + 4)]), 1.3, ink=0.6, dry=0.3,
                           profile="even")
        stroke(r, frame(c, X, Y, [(0, -34), (0, 32)]), 2.4, ink=0.85, dry=0.3, profile="even")
        for k in range(5):                 # 算筹
            r.part(dict(kind="stroke", pts=frame(c, X, Y, [(74 + k * 3, -64), (66 + k * 4, 10)]),
                        width=2.2 * s, ink=0.82, dry=0.2, profile="even", seed=r.n()))
        for w_ in ("near", "far"):
            if r.hands.get(w_):
                hand(r, r.hands[w_], False, size=0.85)
        r._hand_done = {"near": True, "far": True}
    elif p == "rods":                      # 算筹一束
        h = pick(r, "one")
        wx, wy = h[0]
        for k in range(5):
            stroke(r, [(wx - 8 * s + k * 4 * s, wy - 60 * s), (wx - 6 * s + k * 4 * s, wy + 4 * s)], 2.2, ink=0.8,
                   dry=0.2, profile="even")
    elif p == "ring":                      # 指上一枚宝石戒：一点朱
        h = r.hands.get("far") or r.hands.get("near")
        wx, wy = h[0]
        tint(r, ell(wx + f * 8 * s, wy, 5 * s, 5 * s, 8), CINNABAR, 0.9, "opaque")
