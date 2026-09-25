# -*- coding: utf-8 -*-
"""「绢本墨影」兜底卡的人物部件库：按冠服拼装正面半身剪影，输出 SVG 文本。

build_portraits.py 调用 figure_svg(spec) / backdrop_svg(spec)，用 rsvg-convert 渲染后再做纸纹墨韵。
颜色是「通道编码」，不是最终颜色：
  人物层  R = 墨浓度（255 焦墨 / 150 中墨：白须素服 / 100 淡墨），
          G > 0 = 留白描线（渲染成绢色），B > 0 = 粉彩（面、手、象笏、纸张：浅暖粉，白描勾边），A = 覆盖。
  背景层  R = 淡墨意象（远山、海浪、屏风……），G = 圆光（宣纸色提亮）。
坐标：人物以面部中心为原点、面宽 96 为单位写，Fig 负责平移缩放到 512×640 画布（人物居左，右侧留题签）。

cast.json 每人一条：body 身形、head 冠帽、beard 须、pose 手势、prop 持物、scene 背景，
另有 collar（round 圆领 / cross 交领）、tone（ink / grey 素服）、hat_tone、hair_tone、extra 附件。
"""

INK = "rgb(255,0,0)"
GREY = "rgb(150,0,0)"
WASH = "rgb(100,0,0)"
SKIN = "rgb(0,0,255)"
TAN = "rgb(0,0,110)"      # 日晒古铜：粉彩通道取低值 → 合成时偏赭
PALE = "rgb(0,0,255)"
WHITE = "rgb(255,255,0)"

TONE = {"ink": INK, "grey": GREY, "wash": WASH, "pale": PALE}


def _fmt(p):
    return "%.1f,%.1f" % p


def smooth(pts, closed=True, k=1.0):
    """Catmull-Rom → 三次贝塞尔。相邻重复点即成尖角。"""
    n = len(pts)
    if n < 3:
        return "M" + " L".join(_fmt(p) for p in pts)
    d = ["M" + _fmt(pts[0])]
    last = n if closed else n - 1
    for i in range(last):
        p0 = pts[(i - 1) % n] if (closed or i > 0) else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (closed or i + 2 < n) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) * k / 6.0, p1[1] + (p2[1] - p0[1]) * k / 6.0)
        c2 = (p2[0] - (p3[0] - p1[0]) * k / 6.0, p2[1] - (p3[1] - p1[1]) * k / 6.0)
        d.append("C%s %s %s" % (_fmt(c1), _fmt(c2), _fmt(p2)))
    if closed:
        d.append("Z")
    return " ".join(d)


def poly(pts):
    return "M" + " L".join(_fmt(p) for p in pts) + " Z"


def mir(pts):
    """左半边点列 → 右半边（x 取反、逆序）。"""
    return [(-x, y) for x, y in reversed(pts)]


def sym(half):
    """half：从顶中线沿左侧到底中线；返回左右对称的闭合点列。"""
    return list(half) + [(-x, y) for x, y in reversed(half[1:-1])]


class Fig:
    ORDER = ["back", "body", "bodyd", "arms", "neck", "face", "feat", "beard", "hat", "hatd", "prop", "propd"]

    def __init__(self, cx=205.0, fy=250.0, s=1.0):
        self.cx, self.fy, self.s = cx, fy, s
        self.L = {k: [] for k in self.ORDER}

    def T(self, pts):
        return [(self.cx + x * self.s, self.fy + y * self.s) for x, y in pts]

    def fill(self, layer, pts, color=INK, curve=True, k=1.0, op=1.0):
        d = smooth(self.T(pts), True, k) if curve else poly(self.T(pts))
        o = "" if op >= 1 else ' fill-opacity="%.2f"' % op
        self.L[layer].append('<path d="%s" fill="%s"%s/>' % (d, color, o))

    def ell(self, layer, c, rx, ry, color=INK, stroke=None, sw=0.0):
        (x, y), = self.T([c])
        f = color if stroke is None else "none"
        st = "" if stroke is None else ' stroke="%s" stroke-width="%.1f"' % (stroke, sw * self.s)
        self.L[layer].append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"%s/>'
                             % (x, y, rx * self.s, ry * self.s, f, st))

    def line(self, layer, pts, w=3.2, color=WHITE, curve=True, op=1.0, cap="round"):
        d = smooth(self.T(pts), False) if curve and len(pts) > 2 else "M" + " L".join(_fmt(p) for p in self.T(pts))
        o = "" if op >= 1 else ' stroke-opacity="%.2f"' % op
        self.L[layer].append('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="%s" '
                             'stroke-linejoin="round"%s/>' % (d, color, w * self.s, cap, o))

    def cap(self, layer, a, b, wa, wb, color=INK):
        """两端粗细不同的圆头棒（手臂、飘带、杖），参数用人物单位坐标。"""
        import math
        (ax, ay), (bx, by) = a, b
        dx, dy = bx - ax, by - ay
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        pts = [(ax + nx * wa / 2, ay + ny * wa / 2), (bx + nx * wb / 2, by + ny * wb / 2),
               (bx - nx * wb / 2, by - ny * wb / 2), (ax - nx * wa / 2, ay - ny * wa / 2)]
        self.fill(layer, pts, color, curve=False)
        self.ell(layer, a, wa / 2, wa / 2, color)
        self.ell(layer, b, wb / 2, wb / 2, color)

    def svg(self, w, h):
        body = "\n".join(e for k in self.ORDER for e in self.L[k])
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n%s\n</svg>'
                % (w, h, w, h, body))


# ───────────────────────── 头面 ─────────────────────────
FACE = sym([(0, -62), (-30, -56), (-47, -32), (-49, -2), (-45, 24), (-34, 46), (-17, 60), (0, 64)])


def head(f, spec):
    hair_tone = TONE[spec.get("hair_tone", "ink")]
    skin = TAN if spec.get("skin") == "tan" else SKIN
    f.fill("neck", [(-21, 30), (21, 30), (24, 104), (-24, 104)], skin, curve=False)
    for sgn in (-1, 1):
        f.ell("face", (sgn * 50, 4), 8, 15, skin)
        f.ell("face", (sgn * 50, 4), 8, 15, None, stroke=INK, sw=1.8)
    hg = spec.get("head", "topknot")
    if hg == "bald":
        shape = sym([(0, -80), (-36, -72), (-52, -44), (-50, -2), (-45, 24), (-34, 46), (-17, 60), (0, 64)])
    else:
        shape = FACE
    f.fill("face", shape, skin)
    f.line("face", shape + shape[:2], 2.2, INK, op=0.7)
    if spec.get("features", True):
        feat(f, spec)
    if hg in ("topknot", "topknot_band", "lowbun", "gaoji", "zongjiao", "messy"):
        f.fill("hat", [(-50, -2), (-53, -40), (-40, -68), (0, -78), (40, -68), (53, -40), (50, -2),
                       (44, -24), (24, -38), (0, -41), (-24, -38), (-44, -24)], hair_tone)


def feat(f, spec):
    """白描五官：柳叶眉、杏仁眼（实墨）、鼻线、平口，笔意克制。"""
    k = spec.get("face", "man")
    bw = 3.2 if k == "man" else 2.4
    for sgn in (-1, 1):
        f.line("feat", [(sgn * 36, -13), (sgn * 25, -19), (sgn * 10, -16)], bw, INK, op=0.9)
        f.fill("feat", [(sgn * 30, -3), (sgn * 22, -7), (sgn * 13, -5), (sgn * 11, -3), (sgn * 21, -1)], INK, op=0.9)
    f.line("feat", [(3, -2), (6, 15), (0, 20)], 1.8, INK, op=0.6)
    if spec.get("beard", "none") in ("none", "goatee", "long3", "short", "moustache"):
        f.line("feat", [(-9, 37), (0, 36.5), (9, 37.5)], 2.0, INK, op=0.75)


def beard(f, spec):
    b = spec.get("beard", "none")
    c = TONE[spec.get("beard_tone", "ink")]
    if b == "none":
        return
    must = [(-24, 31), (-10, 26), (0, 28), (10, 26), (24, 31), (14, 35), (0, 33), (-14, 35)]
    if b == "short":
        f.fill("beard", must, c)
        f.fill("beard", [(-15, 46), (0, 44), (15, 46), (11, 70), (0, 78), (-11, 70)], c)
    elif b == "goatee":
        f.fill("beard", [(-28, 40), (-16, 28), (0, 30), (16, 28), (28, 40), (22, 41), (12, 34), (0, 35),
                         (-12, 34), (-22, 41)], c)
        f.fill("beard", [(-7, 52), (0, 50), (7, 52), (4, 76), (0, 88), (-4, 76)], c)
    elif b == "long3":
        f.fill("beard", must, c)
        f.fill("beard", [(-15, 46), (0, 44), (15, 46), (18, 96), (8, 146), (0, 164), (-8, 146), (-18, 96)], c)
        f.fill("beard", [(-26, 32), (-20, 34), (-26, 80), (-30, 118), (-34, 112), (-32, 72)], c)
        f.fill("beard", [(26, 32), (20, 34), (26, 80), (30, 118), (34, 112), (32, 72)], c)
    elif b == "full":
        f.fill("beard", [(-49, -2), (-52, 30), (-46, 66), (-26, 94), (0, 104), (26, 94), (46, 66), (52, 30),
                         (49, -2), (42, 22), (28, 38), (12, 40), (0, 38), (-12, 40), (-28, 38), (-42, 22)], c)
        f.fill("beard", must, c)
        f.line("beard", [(-9, 37), (0, 39), (9, 37)], 2.4, WHITE, op=0.5)
    elif b == "moustache":
        f.fill("beard", [(-36, 46), (-26, 29), (0, 31), (26, 29), (36, 46), (31, 54), (20, 39), (0, 38),
                         (-20, 39), (-31, 54)], c)


# ───────────────────────── 冠帽 ─────────────────────────
def hat(f, spec):
    hg = spec.get("head", "topknot")
    t = TONE[spec.get("hat_tone", "ink")]
    light = t in (WASH, PALE, GREY)
    dl = INK if light else WHITE      # 冠上描线：深冠留白，浅冠墨线
    if hg == "zhanjiao":             # 展脚幞头
        for sgn in (-1, 1):
            f.fill("hat", [(sgn * 40, -70), (sgn * 172, -70), (sgn * 180, -73), (sgn * 184, -56),
                           (sgn * 172, -58), (sgn * 40, -58)], t, curve=False)
        f.fill("hat", [(-51, -24), (-53, -58), (-44, -72), (-34, -74), (-33, -100), (-20, -113), (20, -113),
                       (33, -100), (34, -74), (44, -72), (53, -58), (51, -24), (26, -32), (0, -34), (-26, -32)], t)
        f.line("hatd", [(-44, -72), (0, -76), (44, -72)], 2.8, dl, op=0.8)
    elif hg == "ruanjiao":           # 软脚幞头：两根软脚垂在脑后两侧
        for sgn in (-1, 1):
            f.fill("back", [(sgn * 30, -84), (sgn * 56, -70), (sgn * 72, -34), (sgn * 78, 16), (sgn * 72, 56),
                            (sgn * 64, 54), (sgn * 66, 14), (sgn * 58, -30), (sgn * 38, -64)], t)
        f.fill("hat", [(-51, -22), (-53, -56), (-44, -70), (-30, -72), (-28, -94), (-14, -104), (14, -104),
                       (28, -94), (30, -72), (44, -70), (53, -56), (51, -22), (26, -30), (0, -32), (-26, -30)], t)
        f.line("hatd", [(-44, -70), (0, -74), (44, -70)], 2.8, dl, op=0.8)
    elif hg == "xiaofutou":          # 小幞头（内侍）
        f.fill("hat", [(-49, -24), (-50, -54), (-34, -78), (0, -84), (34, -78), (50, -54), (49, -24), (24, -32),
                       (0, -34), (-24, -32)], t)
        for sgn in (-1, 1):
            f.fill("back", [(sgn * 34, -60), (sgn * 56, -52), (sgn * 64, -22), (sgn * 56, -20), (sgn * 48, -46)], t)
    elif hg == "fujin":              # 幅巾：软巾裹头，巾尾垂一侧
        f.fill("back", [(34, -76), (62, -52), (76, -8), (80, 44), (70, 70), (62, 60), (64, 18), (56, -30),
                        (40, -58)], t)
        f.fill("hat", [(-52, -18), (-57, -58), (-42, -90), (0, -104), (42, -90), (57, -58), (52, -18), (28, -30),
                       (0, -33), (-28, -30)], t)
        f.line("hatd", [(-48, -44), (-10, -62), (46, -50)], 2.8, dl, op=0.75)
        f.line("hatd", [(-30, -84), (4, -92), (36, -80)], 2.4, dl, op=0.55)
        if spec.get("askew"):
            f.line("hatd", [(20, -100), (44, -110), (64, -100)], 5, INK)
    elif hg == "gaojin":             # 高装巾子（东坡巾式：内高外低、前有开衩）
        f.fill("hat", [(-38, -40), (-37, -148), (-28, -156), (28, -156), (37, -148), (38, -40)], t, curve=False)
        f.fill("hat", [(-52, -18), (-54, -102), (-46, -110), (-10, -110), (0, -94), (10, -110), (46, -110),
                       (54, -102), (52, -18), (26, -28), (0, -31), (-26, -28)], t, k=0.6)
        f.line("hatd", [(-48, -104), (-8, -104)], 2.6, dl, op=0.8)
        f.line("hatd", [(8, -104), (48, -104)], 2.6, dl, op=0.8)
        f.line("hatd", [(-30, -110), (-30, -150)], 2.2, dl, op=0.5)
        f.line("hatd", [(30, -110), (30, -150)], 2.2, dl, op=0.5)
    elif hg == "chantou":            # 缠头
        f.fill("hat", [(-58, -18), (-67, -58), (-58, -98), (-32, -121), (0, -128), (32, -121), (58, -98),
                       (67, -58), (58, -18), (30, -30), (0, -34), (-30, -30)], t)
        f.line("hatd", [(-62, -40), (-12, -76), (58, -94)], 3.0, dl, op=0.8)
        f.line("hatd", [(-62, -70), (-4, -104), (44, -116)], 3.0, dl, op=0.7)
        f.line("hatd", [(-46, -28), (8, -56), (64, -60)], 3.0, dl, op=0.7)
    elif hg == "bandana":            # 布缠头（海上人），结在右侧、两尾飘出
        f.fill("hat", [(-51, -10), (-55, -48), (-40, -76), (0, -85), (40, -76), (55, -48), (51, -10),
                       (30, -30), (0, -36), (-30, -30)], t)
        f.fill("hat", [(48, -52), (80, -66), (108, -62), (100, -50), (78, -46), (54, -36)], t)
        f.fill("hat", [(50, -42), (78, -30), (100, -12), (90, -6), (70, -20), (50, -30)], t)
        f.line("hatd", [(-50, -30), (0, -52), (50, -44)], 2.6, dl, op=0.6)
    elif hg == "douli":              # 竹笠
        f.fill("hat", [(0, -152), (0, -152), (-34, -118), (-74, -80), (-112, -56), (-136, -44), (-130, -34),
                       (-84, -38), (-40, -42), (0, -44), (40, -42), (84, -38), (130, -34), (136, -44),
                       (112, -56), (74, -80), (34, -118)], t, k=0.8)
        for x in (-90, -54, -20, 16, 52, 88):
            f.line("hatd", [(0, -146), (x, -44 - abs(x) * 0.06)], 1.8, dl, op=0.55, curve=False)
    elif hg == "zhanli":             # 破毡笠
        f.fill("hat", [(-46, -34), (-45, -96), (-24, -116), (0, -120), (24, -116), (45, -96), (46, -34)], t)
        f.fill("hat", [(-96, -30), (-88, -48), (-50, -56), (0, -58), (50, -56), (88, -48), (96, -30), (80, -26),
                       (74, -34), (60, -30), (40, -40), (0, -42), (-40, -40), (-62, -30), (-78, -32), (-86, -24)], t)
        f.line("hatd", [(-44, -60), (0, -64), (44, -60)], 2.6, dl, op=0.7)
    elif hg == "helmet" or hg == "fengchi":   # 兜鍪（带顿项、顶缨）
        f.fill("back", [(-52, -40), (-66, 10), (-88, 72), (-110, 104), (110, 104), (88, 72), (66, 10), (52, -40)], t)
        f.fill("hat", [(-56, -22), (-59, -68), (-42, -104), (0, -118), (42, -104), (59, -68), (56, -22), (24, -30),
                       (0, -26), (-24, -30)], t)
        f.fill("hat", [(-4, -116), (4, -116), (4, -140), (-4, -140)], t, curve=False)
        f.ell("hat", (0, -146), 8, 8, t)
        f.fill("hat", [(0, -150), (-14, -164), (-6, -190), (1, -204), (8, -186), (15, -166)], t)
        f.line("hatd", [(-54, -42), (0, -48), (54, -42)], 3.0, dl, op=0.8)
        f.line("hatd", [(0, -48), (0, -112)], 2.4, dl, op=0.6)
        f.line("hatd", [(-30, -46), (-24, -104)], 2.2, dl, op=0.5)
        f.line("hatd", [(30, -46), (24, -104)], 2.2, dl, op=0.5)
        for y in (20, 50, 80):
            f.line("hatd", [(-60 - y * 0.35, y), (-100 - y * 0.1, y + 18)], 2.2, dl, op=0.45)
            f.line("hatd", [(60 + y * 0.35, y), (100 + y * 0.1, y + 18)], 2.2, dl, op=0.45)
        if hg == "fengchi":
            for sgn in (-1, 1):
                f.fill("hat", [(sgn * 54, -44), (sgn * 92, -52), (sgn * 124, -70), (sgn * 146, -96),
                               (sgn * 136, -96), (sgn * 132, -86), (sgn * 122, -92), (sgn * 116, -80),
                               (sgn * 104, -84), (sgn * 96, -72), (sgn * 82, -74), (sgn * 58, -64)], t, k=0.5)
                f.line("hatd", [(sgn * 62, -54), (sgn * 100, -64), (sgn * 132, -88)], 2.2, dl, op=0.6)
    elif hg == "boli":               # 钹笠帽 + 辫环
        for sgn in (-1, 1):
            f.ell("back", (sgn * 54, 30), 8, 15, None, stroke=INK, sw=6)
        f.fill("hat", [(-47, -50), (-44, -88), (-22, -102), (0, -106), (22, -102), (44, -88), (47, -50)], t)
        f.fill("hat", [(-114, -52), (-100, -62), (-50, -68), (0, -70), (50, -68), (100, -62), (114, -52),
                       (100, -42), (50, -38), (0, -37), (-50, -38), (-100, -42)], t)
        f.ell("hat", (0, -112), 6, 6, t)
        f.line("hatd", [(-100, -50), (0, -54), (100, -50)], 2.2, dl, op=0.6)
    elif hg == "nuanmao":            # 暖帽：翻沿皮檐 + 顶珠
        ft = TONE[spec.get("fur_tone", "grey")]
        f.fill("hat", [(-44, -54), (-42, -100), (-22, -114), (0, -118), (22, -114), (42, -100), (44, -54)], t)
        zz = []
        for i in range(13):
            x = -62 + i * (124 / 12.0)
            zz.append((x, -72 - (6 if i % 2 else 0) - 4 * (1 - abs(x) / 62.0)))
        f.fill("hat", [(-60, -22)] + zz + [(60, -22), (30, -30), (0, -32), (-30, -30)], ft, curve=False)
        f.ell("hat", (0, -124), 7, 7, INK)
        if spec.get("jewel"):
            f.ell("hatd", (0, -86), 8, 10, None, stroke=WHITE, sw=2.6)
    elif hg == "gaoji":              # 高髻（妇人）
        ht = TONE[spec.get("hair_tone", "ink")]
        f.fill("hat", [(-54, -4), (-62, -40), (-52, -72), (-22, -86), (22, -86), (52, -72), (62, -40), (54, -4),
                       (42, -28), (0, -42), (-42, -28)], ht)
        f.fill("hat", [(-26, -80), (-32, -110), (-16, -130), (0, -134), (16, -130), (32, -110), (26, -80)], ht)
        f.line("hatd", [(-46, -104), (0, -110), (48, -116)], 3.0, dl if ht == INK else INK, op=0.8)
    elif hg == "lowbun":             # 低髻素簪
        ht = TONE[spec.get("hair_tone", "ink")]
        f.fill("hat", [(-54, -4), (-60, -40), (-50, -70), (-20, -84), (20, -84), (50, -70), (60, -40), (54, -4),
                       (42, -28), (0, -42), (-42, -28)], ht)
        f.ell("hat", (0, -84), 30, 18, ht)
        f.line("hatd", [(-40, -88), (42, -80)], 3.2, INK if ht != INK else WHITE, op=0.85)
    elif hg == "huachai":            # 花钗冠 + 博鬓（后妃像）
        for sgn in (-1, 1):
            for dy, ln in ((0, 1.0), (26, 0.8)):
                x0, y0 = sgn * 50, -70 + dy
                tip = (sgn * (50 + 92 * ln), 40 + dy)
                f.fill("back", [(x0, y0), (sgn * (50 + 40 * ln), -58 + dy), (sgn * (50 + 80 * ln), -14 + dy),
                                (tip[0], tip[1]), (sgn * (50 + 78 * ln), 36 + dy), (sgn * (50 + 50 * ln), -8 + dy),
                                (sgn * (50 + 16 * ln), -46 + dy)], t, k=0.7)
                f.line("hatd", [(sgn * 58, -60 + dy), (sgn * (50 + 60 * ln), -20 + dy), (sgn * (50 + 86 * ln), 30 + dy)],
                       2.0, dl, op=0.6)
        f.fill("hat", [(-54, -4), (-62, -40), (-52, -70), (0, -80), (52, -70), (62, -40), (54, -4), (42, -28),
                       (0, -42), (-42, -28)], t)
        f.fill("hat", [(-60, -50), (-68, -86), (-56, -120), (-28, -140), (0, -146), (28, -140), (56, -120),
                       (68, -86), (60, -50), (0, -58)], t)
        for x, y in ((-40, -92), (-18, -114), (0, -128), (18, -114), (40, -92), (-28, -70), (28, -70), (0, -96)):
            f.ell("hatd", (x, y), 6, 6, None, stroke=dl, sw=2.2)
        for sgn in (-1, 1):               # 冠顶两侧花钗（贴冠，短）
            f.fill("hat", [(sgn * 40, -128), (sgn * 58, -142), (sgn * 70, -140), (sgn * 64, -128), (sgn * 50, -122)], t)
        f.line("hatd", [(-66, -60), (0, -70), (66, -60)], 2.6, dl, op=0.8)
    elif hg == "zongjiao":           # 总角
        ht = TONE[spec.get("hair_tone", "ink")]
        f.ell("hat", (-38, -66), 17, 17, ht)
        f.ell("hat", (38, -66), 17, 17, ht)
    elif hg == "tongguan":           # 童冠（幼帝）
        f.fill("hat", [(-46, -26), (-47, -60), (-34, -80), (0, -86), (34, -80), (47, -60), (46, -26), (24, -32),
                       (0, -34), (-24, -32)], t)
        f.fill("hat", [(-16, -80), (-14, -108), (0, -116), (14, -108), (16, -80)], t)
        f.line("hatd", [(-44, -46), (0, -52), (44, -46)], 2.4, dl, op=0.7)
        f.ell("hatd", (0, -98), 5, 5, None, stroke=dl, sw=2.0)
    elif hg == "eboshi":             # 立乌帽（镰仓）
        f.fill("hat", [(-46, -24), (-48, -76), (-42, -138), (-22, -176), (8, -188), (34, -172), (46, -124),
                       (48, -72), (46, -24), (0, -34)], t)
        f.line("hatd", [(-44, -96), (0, -104), (44, -98)], 2.4, dl, op=0.6)
        f.line("hatd", [(-40, -130), (-4, -142), (40, -134)], 2.2, dl, op=0.5)
    elif hg == "gat":                # 高丽黑笠（马尾笠，半透）
        f.fill("hat", [(-34, -58), (-32, -150), (32, -150), (34, -58)], t, curve=False, op=0.85)
        f.fill("hat", [(-118, -54), (-100, -64), (0, -68), (100, -64), (118, -54), (100, -44), (0, -41),
                       (-100, -44)], t, op=0.85)
        f.line("hatd", [(-110, -54), (0, -58), (110, -54)], 1.8, dl, op=0.5)
        f.line("hat", [(-46, -46), (-40, 20), (-20, 62), (0, 70)], 1.8, INK, op=0.6)
        f.line("hat", [(46, -46), (40, 20), (20, 62), (0, 70)], 1.8, INK, op=0.6)
    if hg == "topknot_band":
        f.ell("hat", (0, -86), 18, 15, TONE[spec.get("hair_tone", "ink")])
        f.line("hatd", [(-50, -34), (0, -46), (50, -34)], 4.0, WHITE, op=0.55)
    elif hg == "topknot":
        f.ell("hat", (0, -86), 18, 15, TONE[spec.get("hair_tone", "ink")])
        f.line("hatd", [(-12, -80), (12, -80)], 3.0, WHITE, op=0.6)
    elif hg == "messy":              # 草挽乱髻
        ht = TONE[spec.get("hair_tone", "ink")]
        f.fill("hat", [(-22, -76), (-28, -96), (-10, -112), (12, -108), (26, -94), (20, -76)], ht)
        f.line("hat", [(-50, -10), (-58, 30), (-54, 70)], 3.0, ht)
        f.line("hat", [(50, -10), (58, 28), (62, 60)], 3.0, ht)
        f.line("hat", [(10, -110), (24, -126)], 2.6, ht)


# ───────────────────────── 身形 ─────────────────────────
ROBE = sym([(0, 72), (-24, 78), (-40, 88), (-78, 100), (-118, 118), (-146, 144), (-162, 182), (-172, 232),
            (-182, 296), (-194, 360), (-204, 420), (-204, 420), (0, 420)])
NARROW = sym([(0, 72), (-24, 78), (-42, 90), (-80, 100), (-120, 112), (-146, 132), (-158, 166), (-164, 214),
              (-166, 262), (-170, 322), (-176, 382), (-180, 420), (-180, 420), (0, 420)])
SHORT = sym([(0, 72), (-26, 76), (-46, 88), (-92, 98), (-134, 110), (-160, 128), (-172, 160), (-176, 200),
             (-174, 246), (-146, 256), (-138, 300), (-140, 360), (-144, 420), (-144, 420), (0, 420)])
ARMOR = sym([(0, 70), (-28, 74), (-56, 84), (-104, 90), (-150, 104), (-182, 128), (-192, 162), (-188, 214),
             (-182, 262), (-178, 322), (-180, 382), (-184, 420), (-184, 420), (0, 420)])
WOMAN = sym([(0, 70), (-20, 74), (-40, 88), (-78, 102), (-112, 122), (-128, 152), (-136, 204), (-144, 262),
             (-154, 322), (-164, 382), (-170, 420), (-170, 420), (0, 420)])

BODY_OUT = {"robe": ROBE, "narrow": NARROW, "short": SHORT, "bare": SHORT, "armor": ARMOR, "mongol": NARROW,
            "mongol_armor": ARMOR, "kasaya": ROBE, "woman": WOMAN, "onearm": None}


def collar(f, kind, dl=WHITE):
    if kind == "round":
        f.line("bodyd", [(-44, 88), (0, 116), (44, 88)], 3.4, dl)
        f.line("bodyd", [(44, 88), (70, 112)], 2.6, dl, op=0.7)
    elif kind == "cross":
        f.line("bodyd", [(26, 80), (-8, 140), (-58, 214)], 3.4, dl)
        f.line("bodyd", [(40, 86), (4, 150), (-44, 222)], 3.0, dl, op=0.8)
        f.line("bodyd", [(-26, 80), (-8, 110), (2, 124)], 3.0, dl, op=0.8)
    elif kind == "beizi":             # 褙子对襟：两道直领缘
        for sgn in (-1, 1):
            f.line("bodyd", [(sgn * 18, 80), (sgn * 22, 200), (sgn * 26, 420)], 3.2, dl)
            f.line("bodyd", [(sgn * 30, 84), (sgn * 34, 200), (sgn * 38, 420)], 2.6, dl, op=0.7)
        f.line("bodyd", [(-18, 82), (0, 112), (18, 82)], 2.4, dl, op=0.7)
    elif kind == "mongol":            # 质孙服：右衽弧领
        f.line("bodyd", [(-24, 80), (10, 118), (60, 146), (104, 156)], 3.4, dl)
        f.line("bodyd", [(-36, 88), (0, 130), (56, 160), (102, 170)], 2.6, dl, op=0.7)


def body(f, spec):
    b = spec.get("body", "robe")
    tone = TONE[spec.get("tone", "ink")]
    dl = WHITE
    if b == "onearm":
        # 独臂：左肩塌、空袖掖进腰带
        out = [(0, 72), (-26, 76), (-46, 88), (-88, 100), (-124, 116), (-140, 142), (-142, 190), (-138, 250),
               (-138, 300), (-140, 360), (-144, 420), (-144, 420), (0, 420)] + mir(
            [(0, 72), (-26, 76), (-46, 88), (-92, 98), (-134, 110), (-160, 128), (-172, 160), (-176, 200),
             (-174, 246), (-146, 256), (-138, 300), (-140, 360), (-144, 420), (-144, 420), (0, 420)])[1:-1]
        f.fill("body", out, tone)
        f.line("bodyd", [(-126, 128), (-132, 180), (-124, 230), (-108, 272)], 3.0, dl)
        f.line("bodyd", [(-108, 272), (-96, 286), (-84, 282)], 2.6, dl, op=0.8)
        f.line("bodyd", [(-138, 276), (0, 290), (138, 276)], 5.0, dl, op=0.75)
        collar(f, "cross", dl)
        return
    f.fill("body", BODY_OUT[b], tone)
    if b in ("robe", "kasaya", "narrow", "woman", "mongol"):
        # 衣纹：肩臂几道顺势的折线
        for sgn in (-1, 1):
            f.line("bodyd", [(sgn * 96, 108), (sgn * 124, 150), (sgn * 132, 200)], 2.2, dl, op=0.45)
            f.line("bodyd", [(sgn * 150, 170), (sgn * 156, 230), (sgn * 150, 280)], 2.0, dl, op=0.35)
    if b in ("robe", "kasaya"):
        collar(f, spec.get("collar", "round"), dl)
    elif b in ("narrow",):
        collar(f, spec.get("collar", "round"), dl)
        f.line("bodyd", [(-150, 268), (0, 286), (150, 268)], 4.0, dl, op=0.65)
    elif b in ("short", "bare"):
        if b == "short":
            collar(f, "cross", dl)
        f.line("bodyd", [(-138, 272), (0, 288), (138, 272)], 5.0, dl, op=0.75)
        f.line("bodyd", [(30, 288), (40, 330), (34, 372)], 3.0, dl, op=0.6)
    elif b == "woman":
        collar(f, "beizi", dl)
    elif b in ("armor", "mongol_armor"):
        for sgn in (-1, 1):
            for i, y in enumerate((96, 118, 140)):
                f.line("bodyd", [(sgn * 70, y), (sgn * 140, y + 10 + i * 6), (sgn * 188, y + 44 + i * 10)], 2.6, dl,
                       op=0.7)
        for r, y in enumerate(range(160, 262, 15)):
            off = 9 if r % 2 else 0
            for x in range(-96 + off, 100, 19):
                f.line("bodyd", [(x - 6, y), (x + 6, y)], 2.2, dl, op=0.5, curve=False)
        if b == "armor":
            f.ell("bodyd", (-46, 176), 17, 17, None, stroke=dl, sw=3.0)
            f.ell("bodyd", (46, 176), 17, 17, None, stroke=dl, sw=3.0)
        else:
            collar(f, "mongol", dl)
        f.line("bodyd", [(-150, 274), (0, 290), (150, 274)], 5.0, dl, op=0.8)
        f.line("bodyd", [(-40, 292), (-70, 360), (-96, 420)], 2.6, dl, op=0.5)
        f.line("bodyd", [(40, 292), (70, 360), (96, 420)], 2.6, dl, op=0.5)
    if b == "mongol":
        collar(f, "mongol", dl)
        f.line("bodyd", [(-150, 270), (0, 286), (150, 270)], 5.0, dl, op=0.75)
    if b == "kasaya":
        f.line("bodyd", [(58, 92), (-20, 220), (-120, 330)], 3.4, dl)
        f.line("bodyd", [(100, 100), (20, 236), (-70, 352)], 3.4, dl)
        f.ell("bodyd", (70, 150), 10, 10, None, stroke=dl, sw=3.0)
        if spec.get("futian"):
            for x in (-120, -60, 60, 120):
                f.line("bodyd", [(x, 160 if abs(x) > 90 else 130), (x * 1.04, 420)], 2.0, dl, op=0.4, curve=False)
            for y in (230, 330):
                f.line("bodyd", [(-170, y), (170, y)], 2.0, dl, op=0.4, curve=False)
    if spec.get("fur"):             # 貂领 / 羊皮坎肩：毛边浅墨
        ft = TONE[spec.get("fur_tone", "grey")]
        zz = []
        for i in range(19):
            x = -150 + i * (300 / 18.0)
            zz.append((x, 150 + (10 if i % 2 else 0) - 30 * (1 - (x / 150.0) ** 2)))
        f.fill("bodyd", [(-40, 82), (-100, 98), (-146, 118)] + zz + [(146, 118), (100, 98), (40, 82), (0, 110)],
               ft, curve=False)
    if spec.get("cape"):            # 蓑衣
        zz = []
        for i in range(21):
            x = -178 + i * (356 / 20.0)
            zz.append((x, 232 + (16 if i % 2 else 0) - 26 * (1 - (x / 178.0) ** 2)))
        f.fill("bodyd", [(-30, 76), (-90, 92), (-150, 116), (-178, 160)] + zz + [(178, 160), (150, 116), (90, 92),
                                                                                  (30, 76)], INK, curve=False)
        for x in range(-150, 160, 22):
            f.line("bodyd", [(x * 0.5, 100), (x, 226 - abs(x) * 0.1)], 1.8, dl, op=0.5, curve=False)
    if spec.get("apron"):
        f.fill("bodyd", [(-96, 280), (96, 280), (104, 420), (-104, 420)], GREY, curve=False)
    if spec.get("vest"):            # 赤膊外罩短褂：前胸敞开露肤
        f.fill("bodyd", [(-44, 84), (44, 84), (52, 160), (40, 272), (-40, 272), (-52, 160)],
               TAN if spec.get("skin") == "tan" else SKIN)
        f.line("bodyd", [(-44, 86), (-52, 160), (-40, 272)], 3.0, dl, op=0.7)
        f.line("bodyd", [(44, 86), (52, 160), (40, 272)], 3.0, dl, op=0.7)
    if spec.get("barechest"):       # 赤膊（只穿短裤，腰缠布）
        f.fill("bodyd", [(-26, 76), (-46, 88), (-92, 98), (-134, 110), (-160, 128), (-172, 160), (-176, 200),
                         (-172, 246), (-146, 256), (-138, 272), (138, 272), (146, 256), (172, 246), (176, 200),
                         (172, 160), (160, 128), (134, 110), (92, 98), (46, 88), (26, 76)],
               TAN if spec.get("skin") == "tan" else SKIN)
        f.line("bodyd", [(-60, 150), (0, 164), (60, 150)], 2.2, INK, op=0.35)
        f.line("bodyd", [(-138, 276), (0, 292), (138, 276)], 12.0, INK)


# ───────────────────────── 手势 ─────────────────────────
POSE = {
    #          肘            手           袖宽(肘,腕)
    "fold": None,
    "hang": ((166, 250), (158, 380), (46, 36)),
    "chest": ((156, 250), (34, 206), (48, 38)),
    "hilt": ((160, 256), (70, 226), (46, 36)),
    "present": ((150, 232), (36, 176), (48, 38)),
}


def arms(f, spec):
    """pose：fold 拱手笼袖 / hang 垂手 / chest 双手当胸持物 / hilt 按剑 / present 双手奉书。
    sides=right 时只有右手（画面右侧）摆 pose，左手垂下。"""
    b = spec.get("body", "robe")
    pose = spec.get("pose", "fold")
    tone = TONE[spec.get("tone", "ink")]
    skin = TAN if spec.get("skin") == "tan" else SKIN
    if pose == "fold":
        wide = b in ("robe", "kasaya", "woman", "armor")
        y0 = 262 if b == "woman" else 205
        k = 1.0 if wide else 0.82
        for sgn in (-1, 1):
            f.line("bodyd", [(sgn * 140 * k, 150), (sgn * 120 * k, y0 - 10), (sgn * 70 * k, y0 + 12),
                             (sgn * 16, y0 + 2)], 3.2, WHITE)
            if wide:
                f.line("bodyd", [(sgn * 178, y0 + 92), (sgn * 130, y0 + 138), (sgn * 60, y0 + 140),
                                 (sgn * 8, y0 + 124)], 3.2, WHITE)
            else:
                f.line("bodyd", [(sgn * 120, y0 + 60), (sgn * 80, y0 + 84), (sgn * 30, y0 + 84),
                                 (sgn * 6, y0 + 70)], 3.0, WHITE)
        f.line("bodyd", [(0, y0 + 8), (0, y0 + (122 if wide else 70))], 2.6, WHITE, op=0.7)
        if spec.get("prop") == "hu":      # 执笏：双手露出握住笏下端；否则笼手于袖
            hand = [(-20, y0 - 8), (0, y0 - 16), (20, y0 - 8), (18, y0 + 12), (0, y0 + 16), (-18, y0 + 12)]
            f.fill("arms", hand, skin)
            f.line("arms", hand + hand[:2], 1.8, INK, op=0.6)
        else:                             # 两袖口相合处一道弧
            f.line("bodyd", [(-40, y0 - 4), (0, y0 + 8), (40, y0 - 4)], 3.0, WHITE, op=0.8)
        return
    sides = spec.get("sides", "both")
    skin_arm = b in ("short", "bare", "onearm")
    for sgn in (-1, 1):
        if b == "onearm" and sgn < 0:
            continue
        p = POSE[pose] if (sides == "both" or sgn > 0) else POSE["hang"]
        (ex, ey), (hx, hy), (we, ww) = p
        e = (sgn * ex, ey)
        h = (sgn * hx, hy)
        this_pose = pose if (sides == "both" or sgn > 0) else "hang"
        if this_pose == "hang":
            # 垂手：手落在下半身淡出区，只画袖筒，不画手
            f.cap("arms", e, h, we, ww, tone if not skin_arm or b != "bare" else skin)
            f.line("arms", [(e[0] - sgn * 12, e[1] - 10), (h[0] - sgn * 10, h[1] - 30)], 2.2, WHITE, op=0.4,
                   curve=False)
            continue
        if skin_arm:
            f.cap("arms", e, h, we + 4, ww, INK)
            f.cap("arms", e, h, we, ww - 4, skin)
        else:
            f.cap("arms", e, h, we, ww, tone)
            f.line("arms", [(e[0] - sgn * 10, e[1] - 12), (h[0] + sgn * 4, h[1] - 12)], 2.4, WHITE, op=0.45,
                   curve=False)
        f.ell("arms", (h[0] - sgn * 2, h[1] + 6), 15, 17, skin)
        f.ell("arms", (h[0] - sgn * 2, h[1] + 6), 15, 17, None, stroke=INK, sw=1.8)


# ───────────────────────── 持物 ─────────────────────────
def prop(f, spec):
    p = spec.get("prop", "none")
    if p == "none":
        return
    if p == "hu":                    # 象笏
        hu = [(-13, 122), (-6, 114), (6, 114), (13, 122), (15, 202), (-15, 202)]
        f.fill("prop", hu, PALE, curve=False)
        f.line("propd", hu + hu[:1], 1.6, INK, op=0.55, curve=False)
    elif p == "book":
        f.fill("prop", [(-48, 186), (46, 178), (50, 226), (-44, 234)], PALE, curve=False)
        f.line("propd", [(0, 182), (3, 230)], 2.0, INK, op=0.7, curve=False)
        f.line("propd", [(-40, 196), (-8, 192)], 1.6, INK, op=0.4, curve=False)
    elif p == "letter":
        f.fill("prop", [(-18, 142), (20, 138), (24, 214), (-14, 218)], PALE, curve=False)
        for y in (156, 172, 188):
            f.line("propd", [(-8, y), (-6, y + 20)], 1.4, INK, op=0.45, curve=False)
            f.line("propd", [(6, y - 2), (8, y + 18)], 1.4, INK, op=0.45, curve=False)
    elif p == "memorial":            # 弹章：展开的奏纸
        f.fill("prop", [(-54, 170), (54, 164), (56, 206), (-52, 212)], PALE, curve=False)
        for x in range(-40, 50, 12):
            f.line("propd", [(x, 176), (x + 1, 202)], 1.3, INK, op=0.45, curve=False)
    elif p == "abacus":
        f.fill("prop", [(-62, 184), (62, 178), (64, 232), (-60, 238)], INK, curve=False)
        for x in range(-50, 58, 12):
            f.line("propd", [(x, 186), (x + 1, 232)], 1.4, WHITE, op=0.55, curve=False)
            f.ell("propd", (x + 0.5, 200 + (x % 3) * 3), 3.2, 2.6, WHITE)
            f.ell("propd", (x + 0.5, 222 - (x % 2) * 3), 3.2, 2.6, WHITE)
        f.line("propd", [(-60, 208), (62, 204)], 1.8, WHITE, op=0.7, curve=False)
    elif p == "beads":
        import math
        for i in range(15):
            a = math.pi * (0.1 + 0.8 * i / 14.0)
            f.ell("prop", (26 + 34 * math.cos(a) - 34 * 0.0, 212 + 60 * math.sin(a)), 5, 5, INK)
            f.ell("propd", (26 + 34 * math.cos(a), 212 + 60 * math.sin(a)), 5, 5, None, stroke=WHITE, sw=1.2)
    elif p == "bowl":
        f.fill("prop", [(-42, 190), (42, 190), (36, 208), (20, 222), (-20, 222), (-36, 208)], GREY, k=0.7)
        f.line("propd", [(-42, 190), (42, 190)], 2.4, WHITE, op=0.8, curve=False)
    elif p == "jianzhan":            # 黑釉建盏
        f.fill("prop", [(-32, 188), (32, 188), (26, 206), (10, 218), (-10, 218), (-26, 206)], GREY, k=0.7)
        f.line("propd", [(-32, 188), (32, 188)], 2.4, WHITE, op=0.9, curve=False)
        f.line("propd", [(-26, 206), (0, 212), (26, 206)], 1.6, WHITE, op=0.5)
    elif p == "stone":
        f.fill("prop", [(128, 212), (150, 200), (170, 212), (172, 236), (152, 248), (130, 240)], GREY)
    elif p == "compass":
        f.line("prop", [(-26, 86), (0, 126), (26, 86)], 1.8, INK, op=0.8)
        f.ell("prop", (0, 138), 16, 16, PALE)
        f.line("propd", [(0, 126), (0, 150)], 1.6, INK, curve=False)
        f.line("propd", [(-12, 138), (12, 138)], 1.6, INK, curve=False)
    elif p == "whip":
        f.line("prop", [(158, 386), (190, 300)], 5.0, INK, curve=False)
        f.line("prop", [(190, 300), (214, 250), (200, 200), (216, 150)], 2.2, INK)
    elif p == "lantern":
        f.line("prop", [(158, 392), (162, 408)], 2.0, INK, curve=False)
        f.fill("prop", [(162, 408), (190, 420), (196, 456), (184, 488), (162, 496), (140, 488), (128, 456),
                        (134, 420)], PALE)
        f.fill("prop", [(146, 404), (178, 404), (178, 412), (146, 412)], INK, curve=False)
        f.fill("prop", [(148, 490), (176, 490), (176, 498), (148, 498)], INK, curve=False)
        for x in (146, 162, 178):
            f.line("propd", [(x, 414), (x + (x - 162) * 0.15, 488)], 1.2, INK, op=0.35)
    elif p == "whisk":
        f.line("prop", [(22, 206), (-34, 118)], 5.0, INK, curve=False)
        f.fill("prop", [(20, 212), (36, 238), (58, 300), (66, 360), (48, 350), (32, 290), (14, 232)], GREY)
    elif p == "seal_box":
        f.fill("prop", [(-50, 176), (50, 176), (50, 236), (-50, 236)], INK, curve=False)
        f.line("propd", [(-50, 190), (50, 190)], 2.4, WHITE, op=0.8, curve=False)
        f.line("propd", [(0, 176), (0, 236)], 2.0, WHITE, op=0.5, curve=False)
        f.ell("propd", (0, 206), 7, 7, None, stroke=WHITE, sw=2.0)
    elif p == "cricket_jar":
        f.ell("prop", (0, 206), 32, 24, GREY)
        f.fill("prop", [(-26, 186), (26, 186), (22, 176), (-22, 176)], INK, curve=False)
    elif p == "brush":
        f.line("prop", [(34, 212), (74, 128)], 4.0, INK, curve=False)
        f.fill("prop", [(30, 212), (40, 214), (34, 234), (28, 226)], INK, curve=False)
    elif p == "staff":
        f.line("prop", [(-160, 60), (-156, 420)], 6.0, INK, curve=False)
        for y in (120, 200, 290, 370):
            f.line("propd", [(-165, y), (-151, y)], 2.0, WHITE, op=0.7, curve=False)
    elif p == "keys":
        for i, (x, y) in enumerate(((-86, 296), (-76, 310), (-94, 312), (-84, 324))):
            f.ell("prop", (x, y), 6, 8, None, stroke=GREY, sw=3.0)
    elif p == "bell":
        f.ell("prop", (150, 196), 22, 22, None, stroke=INK, sw=6)
        for a in (0, 1, 2):
            f.ell("prop", (134 + a * 16, 222), 6, 6, INK)
    elif p == "orange":
        f.ell("prop", (158, 390), 13, 12, PALE)
    elif p == "sword":                # 佩剑在画面右侧腰间，剑柄斜出，右手按柄
        f.line("back", [(60, 240), (10, 420)], 12.0, INK, curve=False)
        f.line("prop", [(60, 238), (86, 188)], 7.0, INK, curve=False)
        f.line("prop", [(44, 232), (76, 248)], 6.0, INK, curve=False)
        f.ell("prop", (88, 184), 6, 6, INK)
        f.line("propd", [(40, 244), (76, 250)], 1.6, WHITE, op=0.6, curve=False)
    elif p == "bow":
        f.line("back", [(110, -40), (170, 60), (176, 180), (140, 300)], 7.0, INK)
        f.line("back", [(110, -40), (140, 300)], 1.4, INK, curve=False)
    if spec.get("medbox"):
        f.fill("back", [(92, 36), (146, 48), (146, 140), (92, 128)], INK, curve=False)
        for y in (54, 76):
            f.line("back", [(96, y), (142, y + 12)], 1.8, WHITE, op=0.5, curve=False)
    if spec.get("necklace"):
        import math
        for i in range(11):
            a = math.pi * (0.12 + 0.76 * i / 10.0)
            f.ell("propd", (60 * math.cos(a), 82 + 44 * math.sin(a)), 5, 5, PALE)


def figure_svg(spec, w=512, h=640):
    child = spec.get("child", False)
    youth = spec.get("youth", False)
    if child:
        f = Fig(205, 336, 0.8)
    elif youth:
        f = Fig(205, 262, 0.94)
    else:
        f = Fig(205, 250, 1.0)
    body(f, spec)
    arms(f, spec)
    head(f, spec)
    beard(f, spec)
    hat(f, spec)
    prop(f, spec)
    return f.svg(w, h)


# ───────────────────────── 背景意象 ─────────────────────────
def backdrop_svg(spec, w=512, h=640):
    sc = spec.get("scene", "none")
    child = spec.get("child", False)
    gy = 250 if not child else 330
    E = []
    E.append('<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">'
             '<stop offset="0" stop-color="rgb(0,255,0)" stop-opacity="1"/>'
             '<stop offset="0.62" stop-color="rgb(0,255,0)" stop-opacity="0.75"/>'
             '<stop offset="1" stop-color="rgb(0,255,0)" stop-opacity="0"/></radialGradient>'
             '<linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">'
             '<stop offset="0" stop-color="rgb(255,0,0)" stop-opacity="0"/>'
             '<stop offset="1" stop-color="rgb(255,0,0)" stop-opacity="0.9"/></linearGradient></defs>')
    E.append('<circle cx="205" cy="%d" r="170" fill="url(#g)"/>' % (gy - 30))

    def wash(d, op):
        E.append('<path d="%s" fill="rgb(255,0,0)" fill-opacity="%.2f"/>' % (d, op))

    def stroke(d, op, sw):
        E.append('<path d="%s" fill="none" stroke="rgb(255,0,0)" stroke-opacity="%.2f" stroke-width="%.1f" '
                 'stroke-linecap="round"/>' % (d, op, sw))

    if sc in ("mountain", "steppe", "temple", "city", "tent", "domes", "arch"):
        far = smooth([(0, 470), (60, 430), (110, 452), (170, 400), (240, 446), (300, 418), (370, 440), (430, 396),
                      (512, 430), (512, 640), (0, 640)], True, 0.8) if sc != "steppe" else \
            smooth([(0, 500), (120, 478), (260, 492), (400, 470), (512, 484), (512, 640), (0, 640)], True)
        wash(far, 0.30)
    if sc == "mountain":
        wash(smooth([(0, 530), (80, 496), (150, 520), (230, 480), (330, 526), (420, 500), (512, 520), (512, 640),
                     (0, 640)], True, 0.8), 0.42)
    if sc == "sea":
        wash("M0,470 L512,470 L512,640 L0,640 Z", 0.18)
        for i, y in enumerate((492, 520, 552, 588, 626)):
            for x0 in range(-40 + (i % 2) * 50, 520, 100):
                stroke("M%d,%d q18,-14 36,0 q18,14 36,0" % (x0, y), 0.55 - i * 0.05, 2.6 + i * 0.4)
        stroke("M0,470 L512,470", 0.5, 1.6)
    if sc == "harbor":
        wash("M0,500 L512,500 L512,640 L0,640 Z", 0.2)
        for x, hh in ((40, 250), (88, 200), (360, 230), (420, 270), (470, 210)):
            stroke("M%d,500 L%d,%d" % (x, x, 500 - hh), 0.55, 3.0)
            wash(poly([(x - 30, 520 - hh), (x + 26, 510 - hh), (x + 22, 590 - hh), (x - 26, 596 - hh)]), 0.26)
        for x0 in range(0, 512, 90):
            stroke("M%d,560 q20,-10 40,0 q20,10 40,0" % x0, 0.4, 2.2)
    if sc == "court" or sc == "throne":
        E.append('<rect x="24" y="92" width="360" height="440" fill="none" stroke="rgb(255,0,0)" '
                 'stroke-opacity="0.30" stroke-width="5"/>')
        for x in (144, 264):
            stroke("M%d,96 L%d,528" % (x, x), 0.22, 3)
        for y0 in (140, 220):
            stroke("M40,%d q30,-24 60,0 q20,16 40,0" % y0, 0.28, 3)
            stroke("M300,%d q30,-24 60,0 q20,16 40,0" % (y0 + 30), 0.28, 3)
    if sc == "throne":                # 障扇
        for cxs in (42, 368):
            E.append('<ellipse cx="%d" cy="150" rx="46" ry="54" fill="rgb(255,0,0)" fill-opacity="0.32"/>' % cxs)
            stroke("M%d,204 L%d,560" % (cxs, cxs), 0.4, 5)
    if sc == "temple":
        x = 356
        for i, (ww, y) in enumerate(((70, 300), (60, 340), (52, 376), (44, 408), (38, 436))):
            wash(poly([(x - ww, y + 12), (x + ww, y + 12), (x + ww - 14, y), (x - ww + 14, y)]), 0.34)
            wash(poly([(x - ww * 0.55, y + 12), (x + ww * 0.55, y + 12), (x + ww * 0.55, y + 30),
                       (x - ww * 0.55, y + 30)]), 0.22)
        stroke("M356,300 L356,262", 0.4, 4)
        E.append('<circle cx="205" cy="%d" r="150" fill="none" stroke="rgb(255,0,0)" stroke-opacity="0.16" '
                 'stroke-width="10"/>' % (gy - 30))
    if sc == "shrine":                # 祠堂遗像：挂轴
        E.append('<rect x="36" y="58" width="340" height="560" fill="rgb(255,0,0)" fill-opacity="0.16"/>')
        E.append('<rect x="36" y="58" width="340" height="560" fill="none" stroke="rgb(255,0,0)" '
                 'stroke-opacity="0.45" stroke-width="4"/>')
        stroke("M24,52 L388,52", 0.7, 9)
    if sc == "city":
        top = 430
        pts = [(0, top)]
        x = 0
        while x < 512:
            pts += [(x, top), (x + 22, top), (x + 22, top + 16), (x + 40, top + 16), (x + 40, top)]
            x += 40
        pts += [(512, top), (512, 640), (0, 640)]
        wash(poly(pts), 0.36)
        wash(poly([(330, 430), (330, 360), (318, 360), (360, 326), (402, 360), (390, 360), (390, 430)]), 0.34)
    if sc == "steppe":
        stroke("M400,480 L400,300", 0.45, 4)
        wash(poly([(400, 300), (440, 312), (404, 330)]), 0.4)
    if sc == "tent":
        for x0, ww in ((40, 90), (360, 110)):
            wash(smooth([(x0, 520), (x0 + ww * 0.1, 470), (x0 + ww / 2, 440), (x0 + ww * 0.9, 470),
                         (x0 + ww, 520)], True), 0.32)
    if sc == "domes":
        for x0, r in ((60, 40), (380, 54), (450, 34)):
            E.append('<circle cx="%d" cy="470" r="%d" fill="rgb(255,0,0)" fill-opacity="0.30"/>' % (x0, r))
            stroke("M%d,%d L%d,%d" % (x0, 470 - r, x0, 470 - r - 30), 0.4, 3)
        wash(smooth([(300, 380), (340, 330), (320, 280), (360, 240), (340, 200)], True), 0.12)
    if sc == "arch":                  # 清净寺式尖拱门
        E.append('<path d="M60,600 L60,300 Q60,150 205,110 Q350,150 350,300 L350,600" fill="none" '
                 'stroke="rgb(255,0,0)" stroke-opacity="0.30" stroke-width="14"/>')
        E.append('<path d="M92,600 L92,310 Q92,186 205,150 Q318,186 318,310 L318,600" fill="none" '
                 'stroke="rgb(255,0,0)" stroke-opacity="0.18" stroke-width="5"/>')
    if sc == "parasol":               # 伞盖
        wash(smooth([(60, 150), (205, 70), (350, 150), (330, 160), (205, 150), (80, 160)], True, 0.8), 0.34)
        for x in range(80, 340, 18):
            stroke("M%d,158 L%d,186" % (x, x), 0.3, 2.4)
        stroke("M205,150 L205,40", 0.4, 5)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n%s\n</svg>' % (
        w, h, w, h, "\n".join(E))
