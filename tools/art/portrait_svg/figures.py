# -*- coding: utf-8 -*-
"""墨影（减笔泼墨）人物骨架：把 cast.json 一条选角拼成一串墨法部件（parts），交给 inkbrush.render 合成。

画法取南宋梁楷一路的减笔泼墨：
  · 身形不是整块填色，而是几笔侧锋大笔横扫叠出（肩背一笔、前襟一笔、两袖各一笔，大袖另垂一笔袖袋），
    每笔一侧浓一侧淡，笔程越往下越枯、自然断成飞白；衣纹、领缘是焦墨钉头鼠尾；
  · 面是淡墨一染，眉眼鼻口只落几笔焦墨（heads.py），发冠焦墨与面在发际处相接；
  · 头与身各按一个转角投影（头转得比身多），侧身、歪头、前倾、驼背都在三维里做，不再是同一张正面模板。

坐标：头部局部单位（面宽约 94），身坐标与头同原点（颈根约 y=86，肩约 y=110）；x 为人物左侧，z 朝观者。
Rig 以 |turn| 投影后按朝向翻转，所以「近侧」（离观者近、画面上靠后的一侧）恒为局部 -x。

cast.json 字段（缺省即默认）：
  comp   {"s": 比例, "hx": 头心 x, "hy": 头心 y}——构图（景别由比例决定，头心须落在小头像取景框内）
  body   robe 大袖袍 / narrow 窄袖 / short 短褐 / bare 赤膊 / armor 甲 / mongol 质孙 / mongol_armor /
         kasaya 袈裟 / woman 褙子 / onearm 独臂
  pose   "近侧手+远侧手"：fold 拱手 / fold_low 袖手 / hu 执笏 / hold 捧物 / present 奉书 / raise 高擎 / hang 垂手 /
         back 负手 / one 当胸持物 / hilt 按剑 / lantern 提灯 / staff 拄杖 / oar 持橹 / up 举物
  turn -1..1（正值面朝画面右）；body_k 身随头转的比例；tilt 歪头（度）；lean 前倾；stoop 驼背；wide 胖瘦
  tone 身上主墨；age 年纪（皱纹）；brow 眉势；eye 眼长；mouth 口角；wind 衣袂须髯被风吹向朝向一侧
  head / beard 见 heads.py；prop / behind 见 props.py；scene 见 scenes.py
"""
import math
import random

import heads
import props


# 公服浅绛（紫、绯、青、绿、赭黄……）：色相要落在该色的区间里，所以色度给足
ROBE_TINTS = {"zi": (0.52, 0.24, 0.52), "fei": (0.82, 0.25, 0.19), "qing": (0.20, 0.44, 0.50),
              "lv": (0.28, 0.54, 0.30), "zhe": (0.84, 0.58, 0.20), "lan": (0.22, 0.33, 0.58),
              "gold": (0.80, 0.63, 0.28), "hui": (0.5, 0.5, 0.5)}


def _lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


class Rig:
    def __init__(self, spec, seed):
        self.spec = spec
        self.seed = seed
        self.rng = random.Random(seed)
        self._n = seed * 7919
        turn = spec.get("turn", 0.5)
        self.sg = 1 if turn >= 0 else -1
        self.th = math.radians(abs(turn) * 74)
        self.tb = math.radians(abs(turn) * 74 * spec.get("body_k", 0.88))
        self.tilt = math.radians(spec.get("tilt", 0.0))
        self.lean = spec.get("lean", 0.0)
        self.stoop = spec.get("stoop", 0.0)
        self.wide = spec.get("wide", 1.0)
        comp = spec.get("comp", {})
        self.s = comp.get("s", 0.9)
        self.bs = spec.get("bs", 0.68 if spec.get("child") else (0.92 if spec.get("youth") else 1.0))
        self.hx = comp.get("hx", 240.0)
        self.hy = comp.get("hy", 190.0)
        self.elev = 0.12
        self.hoff = (self.sg * (self.stoop * 28 + self.lean * 18), self.stoop * 20 + self.lean * 10)
        self.parts = []
        self.hands = {}
        self.sil_polys = []
        self.skin_polys = []
        self.late = []
        self.face_front = self.face_back = None

    def n(self):
        self._n += 1
        return self._n

    def part(self, p):
        self.parts.append(p)

    # ── 投影 ──
    def _p3(self, x, y, z, th):
        c, s = math.cos(th), math.sin(th)
        x1 = x * c + z * s
        z1 = -x * s + z * c
        return x1, y + z1 * self.elev

    def Hp(self, pts):
        """头部投影坐标（未翻转）→ 画布：翻转、绕颈歪头、缩放平移。"""
        ct, st = math.cos(self.tilt * self.sg), math.sin(self.tilt * self.sg)
        out = []
        for x, y in pts:
            X = self.sg * x
            dx, dy = X, y - 72
            rx = dx * ct - dy * st
            ry = dx * st + dy * ct + 72
            out.append((self.hx + self.s * rx, self.hy + self.s * ry))
        return out

    def H3(self, pts):
        return self.Hp([self._p3(x, y, z, self.th) for x, y, z in pts])

    def Hs(self, pts, zc=-6, ratio=1.15):
        """回转体（冠帽）正视轮廓 → 画布：侧身时轮廓宽度按椭圆截面变化、随轴心平移。"""
        c, s = math.cos(self.th), math.sin(self.th)
        k = math.sqrt(c * c + (ratio * s) ** 2)
        return self.Hp([(x * k + zc * s, y) for x, y in pts])

    def B3(self, pts):
        bs = self.bs
        out = []
        for x, y, z in pts:
            x, y, z = x * bs, 80 + (y - 80) * bs, z * bs
            x1, y1 = self._p3(x * self.wide, y, z, self.tb)
            X = self.sg * x1
            if self.stoop:
                k = max(0.0, min(1.0, (230 - y) / 170.0))
                X += self.sg * self.stoop * 30 * k
                y1 += self.stoop * 18 * k
            out.append((self.hx + self.s * (X - self.hoff[0]), self.hy + self.s * (y1 - self.hoff[1])))
        return out

    # ── 部件 ──
    def stroke3(self, pts, w, ink=0.9, dry=0.35, profile="nail", **kw):
        self.part(dict(kind="stroke", pts=self.H3(pts), width=w * self.s, ink=ink, dry=dry, profile=profile,
                       seed=self.n(), **kw))

    def dot3(self, p, r, ink=0.9, reserve=False):
        (cx, cy), = self.H3([p])
        rr = r * self.s * 0.5
        pts = [(cx + rr * math.cos(2 * math.pi * i / 10), cy + rr * math.sin(2 * math.pi * i / 10) * 0.9)
               for i in range(10)]
        if reserve:
            self.part(dict(kind="reserve", pts=pts, amount=0.7, rough=0.3))
        else:
            self.part(dict(kind="wash", pts=pts, tone=ink, edge=0.1, var=0.1, bloom=0.0, soft=0.5))

    def stroke_h(self, pts, w, ink=0.8, dry=0.35, profile="nail", sil=False, rstroke=False, zc=-6, ratio=1.15):
        P = self.Hs(pts, zc, ratio) if sil else self.Hp(pts)
        if rstroke:
            self.part(dict(kind="rstroke", pts=P, width=w * self.s, amount=ink, dry=dry, profile=profile,
                           seed=self.n()))
        else:
            self.part(dict(kind="stroke", pts=P, width=w * self.s, ink=ink, dry=dry, profile=profile, seed=self.n()))

    def sweep_b(self, pts3, width, ink=0.8, side=0.6, pale=0.3, dry=0.35, wet=0.4, profile="sweep", layer="robe",
                **kw):
        self.part(dict(kind="sweep", pts=self.B3(pts3), width=width * self.s, ink=ink, side=side * self.sg, pale=pale,
                       dry=dry, wet=wet, seed=self.n(), profile=profile, layer=layer, **kw))

    def line_b(self, pts3, w, ink=0.9, dry=0.4, profile="nail", **kw):
        self.part(dict(kind="stroke", pts=self.B3(pts3), width=w * self.s, ink=ink, dry=dry, profile=profile,
                       seed=self.n(), **kw))

    def white_b(self, pts3, w, amount=0.6, dry=0.4, profile="nail"):
        self.part(dict(kind="rstroke", pts=self.B3(pts3), width=w * self.s, amount=amount, dry=dry, profile=profile,
                       seed=self.n()))

    def wash_b(self, pts3, tone, **kw):
        self.part(dict(kind="wash", pts=self.B3(pts3), tone=tone, **kw))


# ───────────────────────── 身形 ─────────────────────────
BODY = {
    #              肩半宽 肩落 下摆  主墨  袖型     (上臂, 肘, 袖口)
    "robe":         (112, 22, 128, 0.74, "wide", (46, 58, 86)),
    "kasaya":       (110, 22, 124, 0.70, "wide", (44, 56, 80)),
    "woman":        (92, 26, 106, 0.66, "wide", (36, 44, 58)),
    "narrow":       (104, 18, 112, 0.72, "narrow", (40, 38, 32)),
    "short":        (108, 14, 110, 0.72, "narrow", (42, 38, 32)),
    "bare":         (116, 10, 104, 0.34, "bare", (40, 34, 28)),
    "onearm":       (104, 20, 110, 0.72, "narrow", (40, 38, 32)),
    "armor":        (126, 8, 126, 0.80, "narrow", (52, 44, 36)),
    "mongol":       (112, 14, 120, 0.72, "narrow", (44, 40, 34)),
    "mongol_armor": (124, 10, 124, 0.80, "narrow", (50, 44, 36)),
}

# 近侧手（局部 -x）的 (肘, 腕)；远侧手取 x 镜像。z 为向前。
POSES = {
    "fold":     ((-1.06, 222, 12), (-12, 214, 70)),
    "fold_low": ((-1.04, 246, 6), (-12, 272, 62)),
    "hu":       ((-1.04, 228, 14), (-8, 206, 74)),
    "hold":     ((-1.02, 232, 10), (-36, 222, 66)),
    "present":  ((-1.04, 206, 22), (-28, 168, 74)),
    "raise":    ((-1.30, 70, 26), (-42, -108, 34)),
    "hang":     ((-1.10, 250, -2), (-1.12, 390, 6)),
    "back":     ((-1.06, 248, -22), (-40, 330, -46)),
    "one":      ((-1.08, 236, 14), (-44, 194, 70)),
    "up":       ((-1.14, 200, 22), (-70, 120, 66)),
    "hilt":     ((-1.18, 238, 2), (-0.86, 292, 34)),
    "lantern":  ((-1.12, 232, 22), (-1.02, 206, 92)),
    "staff":    ((-1.22, 244, 16), (-1.20, 200, 62)),
    "oar":      ((-1.0, 252, 34), (-40, 262, 70)),
}
HANDS_OUT = ("hu", "hold", "present", "raise", "one", "up", "hilt", "lantern", "staff", "oar")


def _joint(v, sw):
    x, y, z = v
    return (x * sw if abs(x) < 2 else x, y, z)


def chain2d(P, W):
    """画布折线 + 每点宽（px）→ 闭合轮廓。"""
    A, Bs = [], []
    n = len(P)
    for i in range(n):
        if i == 0:
            dx, dy = P[1][0] - P[0][0], P[1][1] - P[0][1]
        elif i == n - 1:
            dx, dy = P[i][0] - P[i - 1][0], P[i][1] - P[i - 1][1]
        else:
            dx, dy = P[i + 1][0] - P[i - 1][0], P[i + 1][1] - P[i - 1][1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        w = W[i] / 2
        A.append((P[i][0] + nx * w, P[i][1] + ny * w))
        Bs.append((P[i][0] - nx * w, P[i][1] - ny * w))
    return A + list(reversed(Bs))


def torso_poly(r, sw, slope, hem, bt):
    """躯干轮廓：按椭圆柱截面投影（侧身时轮廓宽度按截面变化，不再左右对称压缩）。"""
    c_, s_ = math.cos(r.tb), math.sin(r.tb)
    sq = bt in ("armor", "mongol_armor")
    rows = [(92 + slope * 0.2, sw * 0.42), (100 + slope * 0.5, sw * (0.8 if not sq else 0.9)),
            (114 + slope, sw * (0.97 if not sq else 1.04)), (160 + slope, sw * 1.02), (240, sw * 0.97),
            (330, hem * 0.96), (430, hem), (560, hem * 1.03)]
    L, R = [], []
    for y, a in rows:
        c = a * 0.46
        phi = math.atan2(c * s_, a * c_)
        R.append((a * math.cos(phi), y, c * math.sin(phi)))
        L.append((-a * math.cos(phi), y, -c * math.sin(phi)))
    return r.B3([(0, 86, 0)] + L + list(reversed(R)))


def arm(r, sd, pose, bt, sw, slope, widths, tone, sleeve):
    """一只手臂一笔（侧锋，外浓内淡）；大袖在前臂下再垂一笔袖袋。sd=-1 近侧，+1 远侧。"""
    E, Wr = POSES[pose]
    E, Wr = _joint(E, sw), _joint(Wr, sw)
    if sd > 0:
        E, Wr = (-E[0], E[1], E[2]), (-Wr[0], Wr[1], Wr[2])
    Sh = (sd * sw * 0.9, 112 + slope, -6)
    wu, we, ww = widths
    far = sd > 0
    ink = min(0.96, tone * 1.12) if not far else tone * 0.8
    path = [Sh, _lerp(Sh, E, 0.55), E, _lerp(E, Wr, 0.5), Wr]
    prof = [wu / ww * 0.95, (wu + we) / 2 / ww, we / ww, (we + ww) / 2 / ww, 1.0]
    Pc = r.B3(path)
    Wd = [p * ww * r.s for p in prof]
    ch = chain2d(Pc, Wd)
    r.sil_polys.append(ch)
    # 臂与身的交界：一道有起收的留白（钉头鼠尾），把袖从身形里分出来
    nP = len(Pc)
    A_, B_ = ch[:nP], list(reversed(ch[nP:]))
    if pose not in ("hang", "back") and sleeve != "bare":
        sa, sb = A_[2:5], B_[2:5]
        up = sa if sum(p[1] for p in sa) < sum(p[1] for p in sb) else sb
        r.late.append(dict(kind="rstroke", pts=up, width=3.0 * r.s, amount=0.5, dry=0.5, profile="nail", seed=r.n()))
    elif sleeve != "bare":
        cx = r.hx
        inner = A_ if abs(A_[2][0] - cx) < abs(B_[2][0] - cx) else B_
        r.late.append(dict(kind="rstroke", pts=inner[1:5], width=2.6 * r.s, amount=0.45, dry=0.55, profile="nail",
                           seed=r.n()))
    if sleeve == "bare":                  # 赤膊：臂是淡墨皮肉，外缘一线
        r.skin_polys.append(r.sil_polys.pop())
        r.sweep_b(path, ww * 1.2, ink=0.2, side=0.8 * -sd, pale=0.4, dry=0.3, wet=0.2, profile=prof, layer="skin")
        r.line_b(path, 2.6, ink=0.7, dry=0.4)
    else:
        r.sweep_b(path, ww * 0.9, ink=ink, side=0.75 * -sd, pale=0.35, dry=0.45, wet=0.5, profile=prof)
    hang = pose in ("hang", "back")
    if sleeve == "wide" and not hang and pose != "raise":
        # 袖袋：自肘下垂、至腕下收
        bag = [_lerp(E, Wr, 0.1), (E[0] * 0.8 + Wr[0] * 0.2, E[1] + 70, E[2] + 10),
               (Wr[0] * 0.8 + E[0] * 0.2, Wr[1] + 88, Wr[2]), (Wr[0], Wr[1] + 36, Wr[2])]
        r.sil_polys.append(chain2d(r.B3(bag), [w * ww * r.s for w in (0.55, 0.95, 0.95, 0.6)]))
        r.sweep_b(bag, ww * 0.85, ink=ink * 0.85, side=0.6, pale=0.3, dry=0.55, wet=0.4, profile="press")
        r.line_b(bag[1:], 3.4, ink=0.92, dry=0.5)
    elif sleeve == "wide" and hang:
        r.line_b([E, (E[0] * 1.04, E[1] + 80, E[2]), (E[0] * 0.98, E[1] + 150, E[2])], 3.0, ink=0.9, dry=0.5)
    # 外缘焦墨一笔（肩→肘→袖底），侧锋，定住身形的毛涩硬边
    if not far and sleeve != "bare":
        r.sweep_b([(Sh[0] * 1.04, Sh[1] - 8, Sh[2]), _lerp(Sh, E, 0.5), (E[0] * 1.05, E[1] + 12, E[2]),
                   (E[0] * 1.0 + Wr[0] * 0.0, E[1] + (60 if sleeve == "wide" and not hang else 30), E[2])], 11,
                  ink=0.95, side=0.8, pale=0.5, dry=0.5, wet=0.4, profile="press")
    # 袖口：一笔有粗细的焦墨（不是胶囊）
    if pose in HANDS_OUT or pose in ("fold", "fold_low"):
        d = (Wr[0] - E[0], Wr[1] - E[1])
        ln = math.hypot(*d) or 1
        nx, ny = -d[1] / ln, d[0] / ln
        half = ww * 0.5
        a = (Wr[0] + nx * half, Wr[1] + ny * half, Wr[2])
        b = (Wr[0] - nx * half, Wr[1] - ny * half, Wr[2])
        r.line_b([a, (Wr[0] + d[0] / ln * 4, Wr[1] + d[1] / ln * 4, Wr[2]), b], 3.4, ink=0.9, dry=0.3,
                 profile="swell")
    # 衣纹两道
    if sleeve != "bare":
        for k in (0.35, 0.7):
            p0 = _lerp(Sh, E, k)
            p1 = _lerp(E, Wr, k * 0.6)
            r.line_b([p0, _lerp(p0, p1, 0.5), p1], 2.0, ink=0.85, dry=0.6)
    wr_c = r.B3([Wr])[0]
    el_c = r.B3([E])[0]
    r.hands["far" if far else "near"] = (wr_c, pose, el_c)


def torso(r, bt, sw, slope, hem, tone):
    """躯干：近侧半身一笔、远侧半身一笔（侧锋、上浓下枯），中间留一线淡处。"""
    sg = 1
    pale = 0.25
    if bt == "bare":
        # 赤膊：淡墨皮肉 + 胸腹几道轮廓
        r.skin_polys.append(torso_poly(r, sw, slope, hem, bt))
        r.sweep_b([(-sw * 0.5, 104, 20), (-sw * 0.52, 220, 34), (-sw * 0.5, 330, 30)], sw * 1.05, ink=0.24,
                  side=0.7, pale=0.4, dry=0.4, wet=0.2, layer="skin")
        r.sweep_b([(sw * 0.45, 108, 26), (sw * 0.48, 220, 36), (sw * 0.45, 330, 30)], sw * 0.95, ink=0.18,
                  side=-0.6, pale=0.4, dry=0.45, wet=0.2, layer="skin")
        r.line_b([(-sw, 118, -4), (-sw * 0.96, 190, 10), (-sw * 0.8, 290, 20)], 3.0, ink=0.8, dry=0.45)
        r.line_b([(-sw * 0.62, 150, 34), (-sw * 0.25, 176, 42), (0, 168, 44)], 2.2, ink=0.6, dry=0.5)
        r.line_b([(sw * 0.62, 150, 34), (sw * 0.25, 176, 42), (0, 168, 44)], 2.0, ink=0.5, dry=0.5)
        r.line_b([(-10, 200, 44), (-8, 250, 44), (-12, 300, 40)], 1.6, ink=0.45, dry=0.6)
        # 腰间缠布
        r.sweep_b([(-sw * 1.02, 296, -4), (-sw * 0.3, 312, 40), (sw * 0.4, 312, 40), (sw * 1.0, 296, -4)], 34,
                  ink=0.7, side=0.6, pale=0.3, dry=0.5, wet=0.3, profile="flat")
        return
    t_n = tone
    t_f = tone * 0.74
    r.sil_polys.append(torso_poly(r, sw, slope, hem, bt))
    # 近侧半身、远侧半身各一笔（外浓内淡），中间前襟淡——笔与笔之间透出底墨
    r.sweep_b([(-sw * 0.66, 100 + slope * 0.5, -10), (-sw * 0.72, 230, 24), (-hem * 0.7, 470, 24)],
              sw * 0.8, ink=t_n, side=0.85, pale=0.3, dry=0.5, wet=0.5)
    r.sweep_b([(sw * 0.6, 104 + slope * 0.5, -6), (sw * 0.64, 232, 30), (hem * 0.66, 470, 26)],
              sw * 0.66, ink=t_f, side=-0.75, pale=0.3, dry=0.55, wet=0.45)
    # 衣褶：两三道焦墨钉头鼠尾，自胸前顺身势垂下（近侧长、远侧短）
    rng = r.rng
    for k, (xf, y0, ln) in enumerate(((-0.42, 150, 230), (0.18, 170, 170), (-0.12, 210, 150))[:int(rng.uniform(2, 3.99))]):
        x0 = (xf + rng.uniform(-0.08, 0.08)) * sw
        z = 34 * math.sqrt(max(0.0, 1 - (x0 / (sw * 1.05)) ** 2))
        bend = rng.uniform(-18, 18)
        r.line_b([(x0, y0, z), (x0 + bend * 0.5, y0 + ln * 0.45, z), (x0 + bend, y0 + ln, z)], rng.uniform(2.4, 3.4),
                 ink=0.92, dry=0.55)
    # 肩背一笔：自颈后压过近侧肩头，定住轮廓
    r.sweep_b([(-12, 82, -30), (-sw * 0.62, 94 + slope * 0.6, -24), (-sw * 1.0, 124 + slope, -10),
               (-sw * 1.06, 190, 0)], 30, ink=min(0.95, tone + 0.15), side=0.9, pale=0.3, dry=0.45, wet=0.5,
              profile="press")
    r.sweep_b([(12, 84, -26), (sw * 0.6, 96 + slope * 0.6, -20), (sw * 0.96, 124 + slope, -8)], 20,
              ink=tone * 0.9, side=-0.8, pale=0.35, dry=0.5, wet=0.4, profile="press")


def collar(r, bt, kind):
    if bt == "bare":
        return
    if kind == "round":         # 圆领：绕颈一圈，内露中单白领（一线）
        ring = [(34 * math.cos(a), 86 + 10 * math.sin(a) * 0.3, 30 * math.sin(a))
                for a in [math.pi * (1.08 - 1.16 * i / 14) for i in range(15)]]
        ring = [(x, y + (8 if z > 20 else 0), z) for x, y, z in ring]
        r.sweep_b(ring, 11, ink=0.9, side=0.3, pale=0.5, dry=0.3, wet=0.3, profile="press")
        inner = [(x * 0.82, y - 7, z * 0.9) for x, y, z in ring[2:-2]]
        r.white_b(inner, 3.0, amount=0.55, dry=0.35, profile="even")
        # 圆领右开的一道衣缘（近侧腋下）
        r.line_b([(-30, 100, 22), (-60, 150, 30), (-76, 210, 28)], 2.4, ink=0.8, dry=0.5)
    elif kind == "cross":       # 交领右衽：领缘一笔有粗细的焦墨，旁留一线白色中单领
        a = [(28, 82, -4), (14, 104, 28), (-12, 152, 38), (-40, 222, 34)]
        r.sweep_b(a, 12, ink=0.92, side=0.4, pale=0.5, dry=0.35, wet=0.35, profile="press")
        r.white_b([(p[0] + 7, p[1] - 3, p[2]) for p in a[:3]], 3.0, amount=0.55, dry=0.4)
        r.line_b([(-26, 84, -4), (-12, 106, 26), (-2, 128, 36)], 5.0, ink=0.85, dry=0.4, profile="swell")
    elif kind == "beizi":       # 褙子对襟：两道直领缘
        for s_ in (-1, 1):
            r.sweep_b([(s_ * 18, 86, 22), (s_ * 22, 200, 36), (s_ * 26, 420, 34)], 10, ink=0.85, side=0.3, pale=0.5,
                      dry=0.45, wet=0.3, profile="flat")
        r.white_b([(-14, 90, 26), (0, 100, 30), (14, 90, 26)], 2.6, amount=0.5, profile="even")
    elif kind == "mongol":      # 质孙右衽弧领
        a = [(-26, 84, 10), (4, 116, 34), (50, 150, 34), (92, 168, 10)]
        r.sweep_b(a, 12, ink=0.9, side=0.4, pale=0.5, dry=0.35, wet=0.35, profile="press")
        r.white_b([(p[0], p[1] - 7, p[2]) for p in a[:3]], 2.6, amount=0.5)
    elif kind == "kasaya":      # 袈裟：远侧肩斜搭过胸到近侧腰，环扣一枚
        a = [(80, 104, 0), (30, 160, 34), (-30, 236, 38), (-90, 320, 20)]
        r.sweep_b(a, 44, ink=0.9, side=0.5, pale=0.35, dry=0.4, wet=0.4, profile="flat")
        r.white_b([(p[0] + 20, p[1] - 12, p[2]) for p in a], 2.8, amount=0.5, dry=0.4)
        r.line_b([(26, 82, -4), (10, 104, 28), (-6, 132, 36)], 5.0, ink=0.85, dry=0.4, profile="swell")
        cx, cy = r.B3([(56, 132, 30)])[0]
        rr = 7 * r.s
        ring = [(cx + rr * math.cos(i * 0.52), cy + rr * math.sin(i * 0.52)) for i in range(13)]
        r.part(dict(kind="stroke", pts=ring, width=2.4 * r.s, ink=0.9, dry=0.2, profile="even", seed=r.n()))
        if r.spec.get("futian"):
            for u in (0.3, 0.62):
                p = _lerp(a[1], a[2], u)
                r.white_b([(p[0] - 30, p[1] - 20, p[2]), (p[0] + 30, p[1] + 20, p[2])], 2.0, amount=0.4)


def belt(r, bt, sw):
    if bt in ("narrow", "short", "mongol", "onearm") and not r.spec.get("cape"):
        pts = [(-sw * 1.02, 290, -4), (-sw * 0.4, 304, 38), (sw * 0.3, 306, 40), (sw * 0.98, 292, -4)]
        r.sweep_b(pts, 14, ink=0.9, side=0.5, pale=0.4, dry=0.45, wet=0.3, profile="flat")
    if bt == "robe" and r.spec.get("belt_band", False):
        pts = [(-sw * 1.06, 300, -4), (-sw * 0.4, 314, 38), (sw * 0.3, 316, 40), (sw * 1.02, 302, -4)]
        r.sweep_b(pts, 12, ink=0.9, side=0.5, pale=0.4, dry=0.45, wet=0.3, profile="flat")


def armor(r, bt, sw):
    """甲：披膊两笔、甲片改点厾（随机抖动的干笔点，留大块空白），腰带一笔。"""
    rng = r.rng
    for sd in (-1, 1):
        for k, y in enumerate((116, 146)):
            r.sweep_b([(sd * 64, y - 6, 10), (sd * 112, y + 8, 0), (sd * (sw + 14), y + 40, -8)], 22 - k * 4,
                      ink=0.9, side=0.6 * sd, pale=0.3, dry=0.5, wet=0.3, profile="press")
            r.white_b([(sd * 70, y - 12, 12), (sd * 118, y + 1, 2), (sd * (sw + 8), y + 30, -6)], 2.2, amount=0.45)
    lam = bt == "mongol_armor"
    n = 70 if not lam else 60
    for _ in range(n):
        x = rng.uniform(-sw * 0.85, sw * 0.85)
        y = rng.uniform(162, 290)
        if rng.random() < 0.35:            # 留空白
            continue
        z = 36 * math.sqrt(max(0.0, 1 - (x / (sw * 1.05)) ** 2))
        if lam:
            a, b = (x, y - 7, z), (x + rng.uniform(-1, 1), y + 7, z)
        else:
            a, b = (x - 6, y, z), (x + 4, y + 3 + rng.uniform(-2, 2), z)
        if rng.random() < 0.5:
            r.white_b([a, b], rng.uniform(2.2, 3.4), amount=rng.uniform(0.35, 0.55), dry=0.6)
        else:
            r.line_b([a, b], rng.uniform(2.6, 4.0), ink=0.95, dry=0.6, profile="nail")
    r.sweep_b([(-sw * 1.06, 292, -4), (-sw * 0.4, 308, 38), (sw * 0.3, 310, 40), (sw * 1.04, 294, -4)], 16, ink=0.92,
              side=0.5, pale=0.4, dry=0.45, wet=0.3, profile="flat")
    if r.spec.get("armor_light"):          # 亮银甲：甲面提亮
        r.wash_b([(-sw * 0.8, 160, 30), (sw * 0.8, 160, 30), (sw * 0.8, 280, 30), (-sw * 0.8, 280, 30)], 0.0)
        r.part(dict(kind="reserve", pts=r.B3([(-sw * 0.7, 164, 30), (sw * 0.6, 164, 30), (sw * 0.64, 276, 30),
                                             (-sw * 0.7, 276, 30)]), amount=0.35, soft=6.0, rough=1.0))
    if r.spec.get("mirror"):               # 护心镜
        cx, cy = r.B3([(-10, 200, 42)])[0]
        rr = 20 * r.s
        ring = [(cx + rr * math.cos(i * 0.4), cy + rr * math.sin(i * 0.4) * 1.05) for i in range(17)]
        r.part(dict(kind="stroke", pts=ring, width=3.0 * r.s, ink=0.9, dry=0.3, profile="even", seed=r.n()))


def extras(r, bt, sw):
    sp = r.spec
    rng = r.rng
    if sp.get("vest"):                     # 赤膊外罩短褂：两片深色褂身
        for sd in (-1, 1):
            r.sweep_b([(sd * sw * 0.72, 104, -4), (sd * sw * 0.8, 200, 20), (sd * sw * 0.74, 300, 22)], 44, ink=0.72,
                      side=0.6 * sd, pale=0.3, dry=0.5, wet=0.3)
    if sp.get("apron"):                    # 油布围裙
        r.sweep_b([(-4, 280, 44), (-6, 360, 44), (-8, 440, 40)], sw * 1.4, ink=0.4, side=0.4, pale=0.4, dry=0.35,
                  wet=0.5, profile="flat")
        r.line_b([(-sw * 0.7, 282, 30), (0, 290, 44), (sw * 0.7, 282, 30)], 3.0, ink=0.85, dry=0.4)
    if sp.get("fur"):                      # 貂领 / 羊皮坎肩：一团破墨软块，不画刺
        a = [(-sw * 1.0, 124, -10), (-sw * 0.6, 102, 20), (0, 100, 38), (sw * 0.6, 104, 20), (sw * 1.0, 128, -10)]
        r.sweep_b(a, 44, ink=0.72, side=0.2, pale=0.5, dry=0.25, wet=1.0, profile="press", rough=2.6, layer="fur")
        r.sweep_b(a[1:4], 22, ink=0.9, side=0.6, pale=0.4, dry=0.35, wet=0.6, profile="press", rough=2.0, layer="fur")
    if sp.get("cape"):                     # 蓑衣：肩上一大团干笔，草茎顺势下垂
        r.sweep_b([(-sw * 1.2, 150, -6), (-sw * 0.5, 110, 30), (sw * 0.5, 112, 30), (sw * 1.2, 150, -6)], 90,
                  ink=0.75, side=0.3, pale=0.4, dry=0.7, wet=0.2, profile="press", streak=0.4)
        for i in range(26):
            x = -sw * 1.2 + sw * 2.4 * i / 25.0 + rng.uniform(-6, 6)
            y0 = 140 - 36 * (1 - (x / (sw * 1.2)) ** 2)
            z = 30 * math.sqrt(max(0.0, 1 - (x / (sw * 1.25)) ** 2))
            r.line_b([(x, y0, z), (x * 1.04 + rng.uniform(-4, 4), y0 + rng.uniform(70, 120), z)], 2.4, ink=0.85,
                     dry=0.65, profile="taper")
    if sp.get("necklace"):                 # 贝珠串：一圈留白小点
        for i in range(11):
            a = math.pi * (0.15 + 0.7 * i / 10.0)
            x, y = 50 * math.cos(a), 104 + 40 * math.sin(a)
            z = 34 + 8 * math.sin(a)
            (cx, cy), = r.B3([(x, y, z)])
            rr = 4.6 * r.s
            r.part(dict(kind="cover", pts=[(cx - rr, cy - rr), (cx + rr, cy - rr), (cx + rr, cy + rr),
                                           (cx - rr, cy + rr)], tone=0.12, rough=0.3))
    if sp.get("belt_gold"):                # 金带
        pts = [(-sw * 1.04, 298, -4), (-sw * 0.4, 312, 38), (sw * 0.3, 314, 40), (sw * 1.0, 300, -4)]
        r.sweep_b(pts, 14, ink=0.6, side=0.5, pale=0.4, dry=0.3, wet=0.3, profile="flat", layer="gold")


def empty_sleeve(r, sw, slope):
    """独臂：近侧空袖塌下，掖进腰带。"""
    x0 = -sw * 0.92
    path = [(x0, 116 + slope, -6), (x0 - 10, 190, 4), (x0 + 26, 290, 24)]
    r.sil_polys.append(chain2d(r.B3(path), [30 * r.s, 34 * r.s, 22 * r.s]))
    r.sweep_b(path, 26, ink=0.62, side=0.6, pale=0.3, dry=0.5, wet=0.4, profile="press")
    r.line_b([(x0 - 6, 150, 0), (x0 - 12, 210, 6), (x0 + 22, 288, 24)], 2.4, ink=0.85, dry=0.5)
    r.hands["near"] = (r.B3([(x0 + 26, 290, 24)])[0], "empty", r.B3([(x0 - 10, 190, 4)])[0])


def build(spec, seed):
    """一位人物 → Rig（parts 已按合成顺序排好）。"""
    r = Rig(spec, seed)
    bt = spec.get("body", "robe")
    sw, slope, hem, base_tone, sleeve, widths = BODY[bt]
    tone = spec.get("tone", base_tone)
    props.behind(r)
    heads.back(r)                          # 发团（面随后在上面留白）
    start = len(r.parts)
    torso(r, bt, sw, slope, hem, tone)
    pose = spec.get("pose", "fold")
    near, far = (pose.split("+") + [None])[:2]
    far = far or near
    if bt == "onearm":
        empty_sleeve(r, sw, slope)
    else:
        arm(r, -1, near, bt, sw, slope, widths, tone, sleeve)
    arm(r, 1, far, bt, sw, slope, widths, tone, sleeve)
    # 身形底墨：躯干与两臂并成一片，湿墨一泼（上浓下淡、水渍花、边缘洇开、下缘枯），笔都叠在它上面
    (_, y_top), = r.B3([(0, 100, 0)])
    (_, y_bot), = r.B3([(0, 470, 0)])
    base = spec.get("under", 0.6)
    if r.sil_polys:
        r.parts.insert(start, dict(kind="sil", polys=list(r.sil_polys), tone=((0, y_top), (0, y_bot), tone * base,
                                                                                tone * base * 0.62),
                                   angle=4, edge=0.4, var=0.6, bleed=1.0, bloom=0.3, streak=0.05, dry_edge=0.6,
                                   dry_side=(0, 1), dry_depth=40, soft=1.6, layer="robe"))
    if r.skin_polys:
        r.parts.insert(start, dict(kind="sil", polys=list(r.skin_polys), tone=0.14, edge=0.3, var=0.5, bleed=0.6,
                                   bloom=0.2, streak=0.03, dry_edge=0.4, dry_side=(0, 1), dry_depth=30, soft=1.4,
                                   layer="skin"))
    if bt in ("armor", "mongol_armor"):
        armor(r, bt, sw)
    belt(r, bt, sw)
    extras(r, bt, sw)
    r.parts.extend(r.late)                 # 臂身交界的留白线：压在所有身形笔之上
    heads.face(r)                          # 面颈留白 + 淡墨成面（压在身形墨上）
    collar(r, bt, spec.get("collar", {"robe": "round", "woman": "beizi", "mongol": "mongol",
                                      "mongol_armor": "mongol", "kasaya": "kasaya"}.get(bt, "cross")))
    heads.hat(r)                           # 发与冠
    heads.features(r)                      # 减笔五官
    heads.beard(r)
    props.front(r)                         # 手中持物 + 手
    # 人物轮廓（避让用，不上墨）：面 + 颈
    r.part(dict(kind="mask", pts=r.Hp(r.face_poly), layer="face", soft=2.0))
    r.part(dict(kind="mask", pts=r.Hp(r.neck_poly), layer="face", soft=2.0))
    return r
