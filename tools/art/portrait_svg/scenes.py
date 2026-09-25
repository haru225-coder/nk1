# -*- coding: utf-8 -*-
"""墨影卡的背景意象：下缘淡墨山水 / 海浪 / 城堞……与少量身后陈设。画布 1× 坐标，直接产出部件表。
背景全部是淡墨（≤0.35），下缘晕开，交给 build_portraits 与雾带合成。"""
import math
import random


def _ridge(rng, x0, x1, base, amp, n=9, rough=0.55):
    """中点位移山脊。"""
    pts = [(x0, base + rng.uniform(-amp, 0) * 0.3), (x1, base + rng.uniform(-amp, 0) * 0.3)]
    for _ in range(n):
        nxt = [pts[0]]
        for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
            mx = (ax + bx) / 2 + rng.uniform(-1, 1) * (bx - ax) * 0.08
            my = (ay + by) / 2 + rng.uniform(-1, 1) * amp * rough
            nxt += [(mx, my), (bx, by)]
        pts = nxt
        amp *= 0.55
        if len(pts) > 40:
            break
    return pts


def wash(pts, tone, **kw):
    return dict(kind="wash", pts=pts, tone=tone, **kw)


def stroke(pts, width, ink, dry=0.45, profile="nail", seed=0, **kw):
    return dict(kind="stroke", pts=pts, width=width, ink=ink, dry=dry, profile=profile, seed=seed, **kw)


def mountains(rng, P, layers=((500, 60, 0.16), (556, 50, 0.26)), sd=0):
    for i, (base, amp, tone) in enumerate(layers):
        top = _ridge(rng, -20, 532, base, amp)
        pts = top + [(532, 660), (-20, 660)]
        ymin = min(y for _, y in top)
        P.append(wash(pts, ((0, ymin), (0, ymin + 110), tone, tone * 0.15), edge=0.25, var=0.5, bloom=0.3,
                      dry_edge=0.3, dry_side=(0, -1), angle=70, sharp=True))
        # 山脊披麻：顺坡几笔短皴
        for k in range(10 + i * 4):
            j = rng.randrange(2, len(top) - 2)
            x, y = top[j]
            P.append(stroke([(x, y + 2), (x + rng.uniform(-10, 10), y + rng.uniform(16, 34))], rng.uniform(2, 3.2),
                            tone + 0.14, dry=0.6, seed=sd + i * 50 + k))
        P.append(stroke(top[::2], 2.4, tone + 0.18, dry=0.65, profile="even", seed=sd + 400 + i))


def waves(rng, P, y0=548, rows=4, tone=0.3, sd=0):
    """马远《水图》式：长而缓的水纹，每行两三笔贯通画面，间或卷起一个浪头；越近越粗越疏，远处入雾。"""
    P.append(wash([(-20, y0 - 16), (532, y0 - 18), (532, 660), (-20, 660)], ((0, y0 - 16), (0, 660), 0.03, 0.18),
                  edge=0.0, var=0.6, bloom=0.3, sharp=True))
    y = y0
    for row in range(rows):
        sc = 0.7 + row * 0.3
        x = -60 + rng.uniform(-30, 30)
        while x < 520:
            ln = rng.uniform(220, 360) * sc
            amp = rng.uniform(2.5, 5) * sc
            n = 9
            ph = rng.uniform(0, 6)
            pts = [(x + ln * i / (n - 1), y + math.sin(i * 0.9 + ph) * amp + rng.uniform(-0.8, 0.8))
                   for i in range(n)]
            P.append(stroke(pts, 1.3 + row * 0.5, tone + row * 0.04, dry=0.6, profile="nail",
                            seed=sd + int(x * 7 + row * 1000)))
            if rng.random() < 0.3:           # 浪头：一笔卷起再回勾
                cx, cy = pts[rng.randrange(3, 6)]
                h = rng.uniform(8, 13) * sc
                P.append(stroke([(cx - 24 * sc, cy + 2), (cx - 6 * sc, cy - h), (cx + 12 * sc, cy - h * 0.9),
                                 (cx + 16 * sc, cy - h * 0.35), (cx + 8 * sc, cy - h * 0.2)],
                                1.5 + row * 0.45, tone + 0.06 + row * 0.04, dry=0.5, profile="nail",
                                seed=sd + int(x * 3 + row * 77)))
            x += ln * rng.uniform(0.85, 1.1) + rng.uniform(20, 60)
        y += 16 * sc + rng.uniform(4, 10)


def junk(P, x, y, sz, tone, sd, flip=1):
    """远处一只福船：弧形船身 + 两面撑条竹篷帆（很淡，只是一个认得出的剪影）。"""
    hull = [(x - 60 * sz * flip, y - 10 * sz), (x + 64 * sz * flip, y - 16 * sz), (x + 48 * sz * flip, y + 6 * sz),
            (x - 44 * sz * flip, y + 8 * sz)]
    P.append(wash(hull, tone * 1.2, edge=0.3, var=0.3, bloom=0.1))
    for k, (mx, mh, mw) in enumerate(((-8, 150, 70), (38, 110, 52))):
        bx = x + mx * sz * flip
        top = y - (mh + 14) * sz
        P.append(stroke([(bx, y - 10 * sz), (bx, top)], 2.2, tone + 0.1, dry=0.35, profile="even", seed=sd + k))
        sail = [(bx - mw * 0.2 * sz * flip, top + 8 * sz), (bx + mw * 0.8 * sz * flip, top + 20 * sz),
                (bx + mw * 0.9 * sz * flip, y - 30 * sz), (bx - mw * 0.1 * sz * flip, y - 26 * sz)]
        P.append(wash(sail, tone * 0.8, edge=0.25, var=0.4, bloom=0.2))
        for j in range(5):
            t = (j + 1) / 6.0
            a = (sail[0][0] + (sail[3][0] - sail[0][0]) * t, sail[0][1] + (sail[3][1] - sail[0][1]) * t)
            b = (sail[1][0] + (sail[2][0] - sail[1][0]) * t, sail[1][1] + (sail[2][1] - sail[1][1]) * t)
            P.append(stroke([a, b], 1.2, tone + 0.06, dry=0.5, profile="even", seed=sd + 10 + k * 10 + j))


def build(spec, seed):
    rng = random.Random(seed * 31 + 7)
    sc = spec.get("scene", "none")
    P = []
    sd = seed * 13
    if sc in ("mountain", "temple", "steppe", "tent", "domes", "arch", "city", "shrine"):
        mountains(rng, P, sd=sd,
                  layers=((522, 30, 0.18), (578, 22, 0.28)) if sc in ("steppe", "tent", "domes") else
                  ((492, 70, 0.22), (556, 54, 0.34)))
    if sc in ("sea", "harbor"):
        if sc == "sea":                        # 远岸一抹
            top = _ridge(rng, -20, 532, 536, 16)
            P.append(wash(top + [(532, 560), (-20, 560)], 0.16, edge=0.2, var=0.5, sharp=True, dry_edge=0.3,
                          dry_side=(0, -1)))
        waves(rng, P, y0=566 if sc == "sea" else 584, tone=0.38, sd=sd)
    if sc == "harbor":                         # 远处福船两只（在人物背侧），近岸一抹
        side = -1 if spec.get("turn", 0.5) >= 0 else 1
        x0 = 70 if side < 0 else 400
        junk(P, x0, 520, 0.8, 0.14, sd + 11, flip=-side)
        junk(P, x0 + side * -70, 540, 0.5, 0.1, sd + 31, flip=-side)
        P.append(wash([(0, 556), (180, 548), (170, 580), (10, 584)], 0.2, edge=0.2, dry_edge=0.4))
    if sc == "city":                           # 城堞
        top = 470
        pts = [(-10, top)]
        x = -10
        while x < 530:
            pts += [(x, top), (x + 22, top), (x + 22, top + 14), (x + 38, top + 14), (x + 38, top)]
            x += 38
        pts += [(530, top), (530, 660), (-10, 660)]
        P.append(wash(pts, ((0, top), (0, top + 150), 0.26, 0.06), edge=0.3, var=0.5, sharp=True, dry_edge=0.3))
        P.append(wash([(20, 470), (20, 404), (8, 404), (64, 364), (120, 404), (108, 404), (108, 470)],
                      0.2, edge=0.3, sharp=True))
    if sc in ("court", "throne", "shrine"):    # 帷幔：顶上一道垂幔，三四个垂弧，褶线与流苏
        n = rng.choice([3, 4])
        yb = rng.uniform(46, 84)
        dip = rng.uniform(14, 26)
        edge = []
        for i in range(n * 10 + 1):
            x = -20 + 552 * i / (n * 10)
            u = (i % 10) / 10.0
            edge.append((x, yb + dip * math.sin(math.pi * u)))
        P.append(wash([(-20, -20), (532, -20)] + list(reversed(edge)), ((0, 0), (0, yb + dip), 0.46, 0.3), edge=0.35,
                      var=0.5, bloom=0.25, dry_edge=0.4, dry_side=(0, 1), dry_depth=10, sharp=True))
        for k in range(n):
            x0 = -20 + 552 * (k + 0.5) / n
            for j in (-1, 0, 1):
                P.append(stroke([(x0 + j * 30, 0), (x0 + j * 22, yb * 0.6), (x0 + j * 10, yb + dip * 0.8)], 1.6, 0.5,
                                dry=0.55, profile="nail", seed=sd + 300 + k * 7 + j))
            xk = -20 + 552 * k / n
            P.append(stroke([(xk, yb), (xk + 2, yb + 44)], 4.0, 0.55, dry=0.5, profile="taper", seed=sd + 350 + k))
    if sc == "tent":                           # 帐顶：一片暗帐与哈那格
        P.append(wash([(-20, -20), (532, -20), (532, 60), (256, 96), (-20, 60)], ((0, 0), (0, 96), 0.5, 0.3),
                      edge=0.3, var=0.5, bloom=0.2, dry_edge=0.4, dry_side=(0, 1), sharp=True))
        for k in range(9):
            x = -20 + k * 70
            P.append(stroke([(x, 0), (256 + (x - 256) * 0.3, 90)], 1.6, 0.5, dry=0.5, profile="even", seed=sd + 400 + k))
    if sc in ("court", "throne"):              # 屏风：淡墨框与水纹
        P.append(stroke([(26, 96), (26, 540)], 5, 0.26, dry=0.5, profile="even", seed=sd + 1))
        P.append(stroke([(20, 92), (386, 92)], 6, 0.26, dry=0.5, profile="even", seed=sd + 2))
        for i, y in enumerate((150, 210, 270)):
            P.append(stroke([(34, y), (70, y - 16), (110, y), (150, y - 14), (190, y)], 2.2, 0.18, dry=0.6,
                            seed=sd + 10 + i))
        P.append(wash([(0, 520), (512, 520), (512, 660), (0, 660)], ((0, 520), (0, 640), 0.02, 0.2), edge=0.0,
                      sharp=True))
        for x in (40, 150, 260, 370):
            P.append(stroke([(x - 60, 610), (x + 60, 604)], 2.0, 0.22, dry=0.6, profile="even", seed=sd + x))
    if sc == "throne":                         # 障扇：长柄团扇，扇面有骨
        cx, cy = 52, 150
        fan = [(cx + 44 * math.cos(2 * math.pi * i / 20), cy + 50 * math.sin(2 * math.pi * i / 20))
               for i in range(20)]
        P.append(wash(fan, 0.22, edge=0.35, bloom=0.3))
        P.append(stroke(fan + fan[:1], 2.6, 0.36, dry=0.5, profile="even", seed=sd + 4))
        for k in range(7):
            a = math.pi * (0.2 + 0.6 * k / 6)
            P.append(stroke([(cx, cy + 40), (cx - 42 * math.cos(a), cy + 40 - 86 * math.sin(a))], 1.4, 0.3,
                            dry=0.6, profile="nail", seed=sd + 20 + k))
        P.append(stroke([(cx, cy + 50), (cx + 2, 560)], 5, 0.32, dry=0.5, profile="even", seed=sd + 5))
    if sc == "temple":                         # 远塔
        x = 66
        for i, (ww, y) in enumerate(((44, 330), (38, 362), (33, 392), (28, 420), (24, 446))):
            P.append(wash([(x - ww, y + 10), (x + ww, y + 10), (x + ww - 10, y), (x - ww + 10, y)], 0.24,
                          edge=0.2, sharp=True))
            P.append(wash([(x - ww * 0.5, y + 10), (x + ww * 0.5, y + 10), (x + ww * 0.5, y + 30),
                           (x - ww * 0.5, y + 30)], 0.14, edge=0.1, sharp=True))
        P.append(stroke([(x, 330), (x, 290)], 3, 0.3, dry=0.3, profile="even", seed=sd + 3))
    if sc == "shrine":                         # 祠堂遗像：挂轴裱边
        P.append(dict(kind="frame"))
    if sc == "steppe":                         # 草原纛
        P.append(stroke([(60, 520), (58, 250)], 4, 0.34, dry=0.4, profile="even", seed=sd + 1))
        P.append(wash([(58, 256), (22, 280), (40, 300), (18, 330), (60, 318)], 0.3, edge=0.2, dry_edge=0.6))
    if sc == "tent":                           # 穹帐
        for x0, ww in ((-20, 120), (400, 130)):
            P.append(wash([(x0, 560), (x0 + ww * 0.08, 506), (x0 + ww / 2, 476), (x0 + ww * 0.92, 506),
                           (x0 + ww, 560)], 0.24, edge=0.3))
    if sc == "domes":                          # 烟火中的圆顶城
        for x0, r in ((50, 36), (112, 24), (440, 30)):
            pts = [(x0 + r * math.cos(math.pi * (1 + i / 12.0)), 500 + r * math.sin(math.pi * (1 + i / 12.0)))
                   for i in range(13)]
            P.append(wash(pts + [(x0 + r, 540), (x0 - r, 540)], 0.26, edge=0.3))
            P.append(stroke([(x0, 500 - r), (x0, 500 - r - 24)], 2.4, 0.3, dry=0.4, profile="even", seed=sd + x0))
        for k in range(3):
            P.append(stroke([(80 + k * 20, 470), (60 + k * 30, 380), (90 + k * 10, 300)], 26, 0.1, dry=0.7,
                            profile="swell", seed=sd + 70 + k))
    if sc == "arch":                           # 清净寺尖拱
        P.append(stroke([(52, 600), (52, 300), (80, 190), (205, 118)], 12, 0.2, dry=0.55, profile="even",
                        seed=sd + 1))
        P.append(stroke([(205, 118), (330, 190), (358, 300), (358, 600)], 12, 0.2, dry=0.55, profile="even",
                        seed=sd + 2))
        P.append(stroke([(86, 600), (86, 310), (110, 222), (205, 156), (300, 222), (324, 310), (324, 600)], 4,
                        0.14, dry=0.6, profile="even", seed=sd + 3))
    if sc == "parasol":                        # 伞盖
        P.append(wash([(40, 170), (205, 92), (370, 170), (344, 182), (205, 170), (66, 182)], 0.3, edge=0.3,
                      bloom=0.3))
        for x in range(64, 350, 16):
            P.append(stroke([(x, 176), (x + 1, 204)], 2.2, 0.26, dry=0.5, profile="even", seed=sd + x))
        P.append(stroke([(205, 170), (205, 60)], 5, 0.3, dry=0.3, profile="even", seed=sd + 9))
        mountains(rng, P, sd=sd, layers=((540, 30, 0.14),))
    if sc == "gate":                           # 城门门闩
        P.append(wash([(0, 120), (120, 120), (120, 640), (0, 640)], 0.14, edge=0.2, sharp=True))
        P.append(stroke([(0, 330), (150, 336)], 14, 0.3, dry=0.5, profile="even", seed=sd + 1))
        for y in (180, 260, 420, 500):
            P.append(stroke([(10, y), (110, y + 2)], 2.2, 0.2, dry=0.6, profile="even", seed=sd + y))
    return P
