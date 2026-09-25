# -*- coding: utf-8 -*-
"""墨影人物的头面、发冠与须（减笔法）。

面：梁楷《泼墨仙人》《李白行吟图》一路的减笔——淡墨一染成面（不敷肤色），焦墨只落在眉、眼、鼻翼、口角几处，
面廓是断续的淡墨游丝；头按一个简化的三维头模转向（figures.Rig 负责投影），所以 3/4 侧脸时五官自然挤向朝向一侧，
耳在背侧露出，鼻、唇、颏在侧身大时带出剪影起伏。
发与冠：焦墨一团，与面在发际处直接相接（不另起颈柱、不留中缝）；冠帽轮廓按「绕竖轴的回转体」处理——
侧身时轮廓宽度不变、只随头骨轴心平移，冠上的纹线贴着冠面转。
坐标：头部局部单位（面宽约 94，发际 y≈-60，颏 y≈63，x 为人物左侧，z 朝观者）。"""
import math

INK, DARK, GREY, PALE = 0.92, 0.8, 0.45, 0.16


def _interp(tab, y):
    ys = [a for a, _ in tab]
    vs = [b for _, b in tab]
    if y <= ys[0]:
        return vs[0]
    if y >= ys[-1]:
        return vs[-1]
    for i in range(len(ys) - 1):
        if ys[i] <= y <= ys[i + 1]:
            t = (y - ys[i]) / (ys[i + 1] - ys[i])
            return vs[i] + (vs[i + 1] - vs[i]) * t
    return vs[-1]


# 头模：半宽 AX(y)、前深 AZ(y)、正中线凸起 MID(y)（眉弓、鼻、唇、颏）
AX = [(-86, 26), (-66, 40), (-44, 45.5), (-20, 47), (0, 47), (18, 45), (32, 40), (44, 33), (54, 25), (61, 15),
      (65, 5)]
AZ = [(-86, 24), (-66, 38), (-44, 46), (-24, 50), (-10, 46), (0, 48), (20, 50), (38, 46), (50, 43), (58, 40),
      (65, 30)]
MID = [(-62, 0), (-28, 3), (-22, 4), (-13, 0), (-4, 2), (8, 7), (17, 14), (21, 13), (25, 4), (30, 2), (35, 4),
       (40, 2), (45, 4), (51, 0), (58, 4), (64, 1)]


_FACE = {"w": 1.0, "jaw": 1.0}


def ax(y):
    t = min(1.0, max(0.0, (y - 10) / 50.0))
    return _interp(AX, y) * _FACE["w"] * (1 + (_FACE["jaw"] - 1) * t)


def surf_z(x, y):
    a = max(ax(y), 1.0)
    q = max(0.0, 1 - (x / a) ** 2)
    return _interp(AZ, y) * math.sqrt(q) + _interp(MID, y) * math.exp(-(x / 10.0) ** 2)


def S3(x, y, dz=0.0):
    """面上一点（正视 x, y）→ 头部 3D 点。"""
    return (x, y, surf_z(x, y) + dz)


def face_edges(th, y):
    """某一高度上面部的朝向侧轮廓 xf 与背侧轮廓 xb（已投影、未翻转，th≥0）。"""
    a = ax(y)
    c, s = math.cos(th), math.sin(th)
    best, worst = -1e9, 1e9
    for i in range(41):
        x = -a + 2 * a * i / 40.0
        xp = x * c + surf_z(x, y) * s
        best = max(best, xp)
        worst = min(worst, xp)
    return best, worst


# ───────────────────────── 面 ─────────────────────────
def face_geom(r):
    """算出面在当前转向下的前后轮廓与颈（只算，不画）。"""
    th = r.th
    child = r.spec.get("child", False)
    _FACE["w"] = r.spec.get("face_w", 1.06 if child else 1.0)
    _FACE["jaw"] = r.spec.get("jaw", 0.88 if child else 1.0)
    bald = r.spec.get("head", "") == "bald"
    top = -84 if bald else -60
    ys = [top + (63 - top) * i / 24.0 for i in range(25)]
    front, back = [], []
    for y in ys:
        xf, xb = face_edges(th, y)
        front.append((xf, y))
        back.append((xb * 0.985, y))
    r.face_front = front
    r.face_back = back
    s = math.sin(th)
    nc = -12 * s
    nf, nb = nc + 24, nc - 24
    r.neck_x = (nf, nb)
    r.neck_poly = [(front[-6][0] - 6, 44), (nf, 66), (nf + 2, 92), (nb - 4, 92), (nb, 62), (back[-4][0] + 6, 52)]
    r.face_poly = front + [(front[-1][0] - 8, 66), (back[-1][0] + 8, 66)] + list(reversed(back))


def back(r):
    """面之前画的：头后的冠饰（软脚、巾尾、顿项、髻……）与发团（头骨一团焦墨，面随后在其上留白）。"""
    face_geom(r)
    behind_head(r)
    sp = r.spec
    hg = sp.get("head", "topknot")
    if hg == "bald":
        return
    ht = {"ink": INK, "grey": 0.84}.get(sp.get("hair_tone", "ink"), INK)
    hair_mass(r, ht, full=hg in ("topknot", "topknot_band", "zongjiao", "messy", "lowbun", "gaoji", "tongguan"))


def behind_head(r):
    """在头后面的部件：先画，面与冠随后压上（远侧的一片不会横穿面部）。"""
    sp = r.spec
    hg = sp.get("head", "topknot")
    t = {"ink": INK, "dark": DARK, "grey": GREY, "pale": PALE, "white": PALE}.get(sp.get("hat_tone", "ink"), INK)
    ht = {"ink": INK, "grey": 0.84}.get(sp.get("hair_tone", "ink"), INK)

    def sw(pts, w, ink, side=0.4, pale=0.5, dry=0.35, wet=0.3, profile="press"):
        r.part(dict(kind="sweep", pts=r.H3(pts), width=w * r.s, ink=ink, side=side, pale=pale, dry=dry, wet=wet,
                    seed=r.n(), profile=profile, layer="head"))

    if hg in ("zhanjiao", "zhijiao"):     # 展脚：两根平直长脚（3D 横杆，侧身时一脚挑起、一脚压低）
        span = sp.get("wing", 128)
        for sd in (-1, 1):
            L = span
            for _ in range(40):            # 朝题签一侧的脚收在题签左侧（x≤392）
                pts = [(sd * 30, -66, -16), (sd * (30 + L * 0.5), -67, -16), (sd * (30 + L), -65, -16)]
                P = r.H3([pts[-1]])[0]
                if -60 <= P[0] <= 392:
                    break
                L -= 5
            sw(pts, 8.5, t, side=0.3, pale=0.6, dry=0.2, profile="flat")
    elif hg == "ruanjiao":                # 软脚：两根软脚自脑后垂下
        for sd in (-1, 1):
            sw([(sd * 20, -70, -48), (sd * 36, -52, -60), (sd * 40, -10, -62), (sd * 36, 34, -60)], 10, t, dry=0.4)
    elif hg == "jiaojiao":                # 交脚：两脚自脑后上翘交叉
        for sd in (-1, 1):
            sw([(sd * 22, -80, -40), (-sd * 16, -118, -44), (-sd * 58, -150, -40)], 8, t, side=0.3)
    elif hg == "xiaofutou":
        for sd in (-1, 1):
            sw([(sd * 22, -62, -50), (sd * 40, -50, -60), (sd * 46, -28, -58)], 8, t, dry=0.35)
    elif hg == "fujin":                   # 巾尾自脑后垂到肩上
        sw([(-4, -86, -56), (-10, -60, -66), (-14, -10, -68), (-12, 44, -62)], 18, max(t, 0.3), side=0.5, pale=0.4,
           dry=0.5, profile="sweep")
    elif hg == "bandana":                 # 结在脑后、两尾飘出
        for k, tip in enumerate(((-40, -56), (-26, -8))):
            sw([(-6, -50, -60), (-20, (-50 + tip[1]) / 2, -76), (tip[0], tip[1], -96)], 14 - k * 3, t, side=0.5,
               pale=0.4, dry=0.45)
    elif hg in ("helmet", "fengchi"):     # 顿项：自盔下缘两侧披到肩头的浓墨披片（两道留白甲缝），不是垂发
        for sd, w in ((-1, 1.0), (1, 0.75)):
            flap = [(sd * 40, -30, -16), (sd * 58, -28, -22), (sd * (62 + 26 * w), 30, -26), (sd * (74 + 30 * w), 84, -18),
                    (sd * 50, 86, -10), (sd * 42, 30, -14)]
            r.part(dict(kind="wash", pts=r.H3(flap), tone=t * 0.86, edge=0.35, var=0.35, dry_edge=0.6,
                        dry_side=(0, 1), dry_depth=10, bloom=0.1, layer="head"))
            for yk in (8, 42):
                r.part(dict(kind="rstroke", pts=r.H3([(sd * 44, yk, -14), (sd * (60 + 26 * w), yk + 14, -24)]),
                            width=2.2 * r.s, amount=0.42, dry=0.5, profile="nail", seed=r.n()))
    elif hg == "boli":                    # 帽下蒙古辫（婆焦）：耳后一小段焦墨辫下垂，不是耳环
        exs = -ax(0) * 0.98
        sw([(exs - 6, 8, -20), (exs - 14, 28, -26), (exs - 10, 50, -22)], 7, INK, side=0.3, pale=0.5, dry=0.4,
           profile="drop")
    elif hg == "huachai":                 # 博鬓：两扇宽翅平贴鬓边
        for sd in (-1, 1):
            sw([(sd * 50, -70, -20), (sd * 92, -40, -30), (sd * 110, 10, -30)], 22, t, side=0.5, pale=0.4)
    elif hg == "lowbun":                  # 低髻素簪：髻盘在脑后
        r.part(dict(kind="wash", pts=r.Hs([(-40, -70), (-48, -94), (-30, -112), (0, -116), (30, -112), (48, -94),
                                           (40, -70)], -34, 1.0), tone=ht, edge=0.22, var=0.28, dry_edge=0.3,
                    dry_depth=8, bloom=0.08, layer="head"))
        r.stroke3([(-52, -96, -30), (0, -100, -40), (54, -88, -30)], 3.0, ink=0.55, dry=0.3, profile="even")


def face(r):
    """面与颈：先把面颈处的墨留白（身形墨与发团不透上来），再淡墨一染，面廓断续游丝。"""
    sp = r.spec
    ft = sp.get("face_tone", 0.0)
    bald = sp.get("head", "") == "bald"
    front, back_ = r.face_front, r.face_back
    back = back_
    poly, neck = r.face_poly, r.neck_poly
    nf, nb = r.neck_x
    # 留白：面 + 颈
    r.part(dict(kind="reserve", pts=r.Hp(poly), amount=1.0, rough=0.5, soft=0.8))
    r.part(dict(kind="reserve", pts=r.Hp(neck), amount=1.0, rough=0.6, soft=0.8))
    # 淡墨成面，再罩一层赭石（浅绛人物的常法，不是粉彩肤色）。面要落在中间调、受光结构与油画一致：
    # 朝向侧受暖侧光、背光侧沉下去，不做「白纸面」（第 1 轮评审：104px 网格里白脸像面具，比油画低几档）
    base = 0.34 + ft
    r.part(dict(kind="wash", pts=r.Hp(poly), tone=max(0.04, base), edge=0.3, var=0.3, bloom=0.12, bleed=0.3,
                streak=0.02, soft=1.2))
    r.part(dict(kind="wash", pts=r.Hp(neck), tone=max(0.06, base + 0.14), edge=0.2, var=0.3, bloom=0.0, bleed=0.2))
    # 渲染：背光侧半张面一片淡墨（软边、宽到鼻梁背侧），给面体积与侧光
    inner = [(x + 46, y) for x, y in back[3:20]]
    r.part(dict(kind="wash", pts=r.Hp(back[3:20] + list(reversed(inner))), tone=0.26, edge=0.0, soft=11.0, var=0.3,
                bloom=0.0, bleed=0.1))
    # 赭石罩得更足：墨压下来的明度由赭色补暖，面是暖褐中间调而不是灰面
    zhe = sp.get("face_zhe", 0.74)
    if zhe > 0:
        r.part(dict(kind="tint", pts=r.Hp(poly), rgb=(0.78, 0.50, 0.29), amount=zhe, mode="mul"))
        r.part(dict(kind="tint", pts=r.Hp(neck), rgb=(0.74, 0.48, 0.29), amount=zhe * 0.9, mode="mul"))
    # 颏下阴影：颏与颈交界一抹淡墨（窄）
    jaw = [(back[-7][0] + 10, 54), (front[-2][0] - 10, 62), (nf - 6, 72), (nb + 10, 70)]
    r.part(dict(kind="wash", pts=r.Hp(jaw), tone=0.12, edge=0.05, var=0.4, soft=4.0, bloom=0.0, bleed=0.1))
    # 面侧渲染：沿朝向侧轮廓内一道淡墨（给体积，不成五官）
    inner = [(x - 10, y) for x, y in front[3:-3]]
    r.part(dict(kind="wash", pts=r.Hp(front[3:-3] + list(reversed(inner))), tone=0.08, edge=0.0, soft=4.0,
                var=0.3, bloom=0.0, bleed=0.1))
    if sp.get("face_tint"):                # 丁大全「面青蓝如铁」：只在面上罩一层靛青（收到 0.24：0.5 时网格里像蓝皮人）
        r.part(dict(kind="tint", pts=r.Hp(poly), rgb=sp["face_tint"], amount=sp.get("face_tint_amount", 0.24),
                    mode="mul"))
    # 面廓：朝向侧一笔（额→眉弓→鼻→唇→颏）；侧身小时是颧颊线
    lw = 1.9
    k0 = 5 if not bald else 9
    seg1 = [front[i] for i in range(k0, 14)]
    seg2 = [front[i] for i in range(13, 25)]
    r.stroke_h(seg1, lw, ink=0.55, dry=0.35, profile="nail")
    r.stroke_h(seg2, lw * 1.1, ink=0.6, dry=0.3, profile="nail")
    # 背侧下颌：自耳下到颏
    jawl = [back[i] for i in range(15, 25)] + [(front[-1][0] - 10, 64)]
    r.stroke_h(jawl, lw, ink=0.5, dry=0.45, profile="nail")
    # 颈线
    r.stroke_h([(nf - 1, 58), (nf, 74), (nf + 2, 90)], 1.6, ink=0.42, dry=0.5, profile="nail")
    r.stroke_h([(nb + 2, 40), (nb, 66), (nb - 3, 90)], 1.6, ink=0.38, dry=0.55, profile="nail")
    if bald:                               # 光头：头顶一道淡墨轮廓 + 头皮青
        r.stroke_h([back[1], (back[0][0] * 0.6 + front[0][0] * 0.4, -90), front[0]], 2.0, ink=0.5, dry=0.3,
                   profile="even")
        cap = [(back[0][0], -80), (back[0][0] * 0.5 + front[0][0] * 0.5, -92), (front[0][0], -80),
               (front[2][0], -58), (back[2][0], -58)]
        r.part(dict(kind="wash", pts=r.Hp(cap), tone=0.1, edge=0.0, soft=6.0, bloom=0.0, var=0.5))


def features(r):
    """减笔五官：眉、眼（上睑一笔 + 瞳一点 + 下睑一丝）、鼻（鼻梁背侧一线 + 鼻翼一勾）、口（一笔）、耳。
    孩童：五官整体下移、收小，眼更大（额大面圆）。"""
    sp = r.spec
    th = r.th
    age = sp.get("age", 40)
    brow = sp.get("brow", 0.0)            # 眉势：>0 上挑（刚）<0 下垂（愁）
    eye = sp.get("eye", 1.0)              # 眼长
    mouth = sp.get("mouth", 0.0)          # 口角：>0 笑 <0 撇
    child = sp.get("child", False) or age < 13
    far_vis = th < math.radians(58)
    k = 0.78 if child else 1.0            # 五官间距
    dy = 7 if child else 0                # 孩童五官下移

    def F(x, y):
        return S3(x * k, (y + dy - 8) * k + 8 - (0 if not child else -4))

    # 眉
    for sd in (-1, 1):
        if sd > 0 and not far_vis:
            continue
        xi, xo = sd * 7, sd * 32
        yi, yo = -21, -24 - brow * 7
        pts = [F(xi, yi), F((xi + xo) / 2, -26 - brow * 3), F(xo, yo)]
        w = (8.0 if not child else 5.0) * (0.75 if sd > 0 else 1.0) * sp.get("brow_w", 1.0)
        r.stroke3(pts, w, ink=0.9, dry=0.3, profile="nail")
    # 眼
    for sd in (-1, 1):
        if sd > 0 and not far_vis:
            continue
        ew = 20 * eye * (1.15 if child else 1.0)
        xi, xo = sd * 8, sd * (8 + ew)
        yc = -7
        lift = 3.2 if not child else 4.2
        pts = [F(xi, yc + 1), F(xi + sd * ew * 0.45, yc - lift), F(xo, yc + 0.5 - brow * 1.5)]
        w = 5.4 if not child else 4.6
        r.stroke3(pts, w * (0.8 if sd > 0 else 1.0), ink=0.94, dry=0.15, profile="taper")
        # 瞳：朝向一侧偏
        px = xi + sd * ew * 0.5 + 3
        r.dot3(F(px, yc + 1.2), (6.0 if not child else 6.8) * (0.85 if sd > 0 else 1.0), ink=0.96)
        # 下睑一丝
        r.stroke3([F(xi + sd * 2, yc + 4.5), F(xo - sd * 3, yc + 3.5)], 1.1, ink=0.3 if age < 50 else 0.42, dry=0.5,
                  profile="nail")
    # 鼻：背侧一线自山根下行，鼻翼一勾
    nk = 0.8 if child else 1.0
    r.stroke3([F(-5, -12), F(-7, 8 * nk), F(-8, 20 * nk)], 1.7, ink=0.45, dry=0.45, profile="nail")
    r.stroke3([F(-12, 18 * nk), F(-14, 22 * nk), F(-9, 25 * nk), F(-3, 24 * nk)], 2.9, ink=0.85, dry=0.25,
              profile="nail")
    if far_vis:
        r.stroke3([F(6, 24 * nk), F(10, 23 * nk)], 1.8, ink=0.7, dry=0.3, profile="nail")
    # 口
    mw = 15 if not child else 11
    cy = 40 if not child else 34
    pts = [F(-mw, cy + 1 - mouth * 3), F(-4, cy), F(4, cy + 0.5),
           F(mw * (0.85 if far_vis else 0.3), cy + 1 - mouth * 3)]
    r.stroke3(pts, 3.6, ink=0.9, dry=0.25, profile="nail")
    r.stroke3([F(-6, cy + 7), F(4, cy + 7)], 1.3, ink=0.3, dry=0.5, profile="nail")
    # 面上渲染：眉下眼窝、鼻底、下唇下各一抹淡墨（软边，给体积，不成五官）
    for pts, tn in (([F(-34, -20), F(-4, -22), F(-2, 0), F(-32, 2)], 0.18),
                    ([F(4, -20), F(30, -20), F(28, 0), F(4, 0)], 0.14),
                    ([F(-14, 24), F(8, 24), F(6, 30), F(-12, 30)], 0.12),
                    ([F(-10, 46), F(8, 46), F(6, 54), F(-8, 54)], 0.1),
                    ([F(-42, 8), F(-24, 12), F(-24, 36), F(-42, 32)], 0.06)):
        r.part(dict(kind="wash", pts=r.H3(pts), tone=tn, edge=0.0, soft=6.0, var=0.3, bloom=0.0, bleed=0.1))
    # 耳：背侧一勾
    exs = -ax(0) * 0.98
    ear = [(exs, -14, -6), (exs - 7, -12, -12), (exs - 9, 2, -14), (exs - 5, 16, -10), (exs, 20, -6)]
    r.stroke3(ear, 2.0, ink=0.55, dry=0.3, profile="nail")
    r.stroke3([(exs - 2, -6, -9), (exs - 5, 4, -11), (exs - 2, 10, -9)], 1.3, ink=0.4, dry=0.4, profile="nail")
    # 年纪：法令、额纹、眼尾
    if age >= 45:
        r.stroke3([S3(-15, 24), S3(-22, 34), S3(-24, 46)], 1.5, ink=0.4, dry=0.5, profile="nail")
        if far_vis:
            r.stroke3([S3(14, 26), S3(19, 36)], 1.3, ink=0.34, dry=0.5, profile="nail")
    if age >= 55:
        for y in (-42, -35):
            r.stroke3([S3(-22, y), S3(0, y - 2), S3(20, y)], 1.3, ink=0.32, dry=0.6, profile="nail")
        r.stroke3([S3(-31, -5), S3(-38, -2)], 1.2, ink=0.34, dry=0.5, profile="nail")
    if sp.get("scar"):
        r.stroke3([S3(-30, -20), S3(-22, 4), S3(-16, 20)], 1.7, ink=0.55, dry=0.4, profile="nail")


# ───────────────────────── 发 ─────────────────────────
def skull_sil(r, grow=0.0, y_cut=None):
    """头骨（含发）在当前转向下的投影轮廓（未翻转、头局部）。"""
    th = r.th
    c, s = math.cos(th), math.sin(th)
    rx, ry, rz, zc, yc = 51 + grow, 70 + grow, 60 + grow, -8, -20
    hw = math.sqrt((rx * c) ** 2 + (rz * s) ** 2)
    xc = zc * s
    pts = []
    for i in range(48):
        a = 2 * math.pi * i / 48
        x, y = xc + hw * math.cos(a), yc + ry * math.sin(a)
        if y_cut is not None and y > y_cut:
            y = y_cut
        pts.append((x, y))
    return pts


def hair_mass(r, tone=INK, full=True):
    """发团：头骨一团焦墨（面随后在其上留白，发际处直接接上），顺发势几笔侧锋，边上枯。"""
    sil = skull_sil(r, y_cut=26)
    r.part(dict(kind="wash", pts=r.Hp(sil), tone=tone * 0.95, edge=0.25, var=0.3, dry_edge=0.35, dry_depth=8,
                bloom=0.08, layer="head"))
    if full:
        for k in range(3):
            a0 = sil[30 + k * 4]
            a1 = sil[38 + k * 3]
            r.part(dict(kind="sweep", pts=r.Hp([a0, ((a0[0] + a1[0]) / 2 + 6, (a0[1] + a1[1]) / 2 - 4), a1]),
                        width=14 * r.s, ink=tone, side=0.6, pale=0.3, dry=0.55, wet=0.2, seed=r.n(), layer="head"))


def hair(r, tone=INK, full=True):
    """发际与鬓角（面之后画，压住面顶）。"""
    fr, bk = r.face_front, r.face_back
    line = [bk[8], bk[5], bk[2], bk[0], (bk[0][0] * 0.5 + fr[0][0] * 0.5, -62), fr[0], fr[2], fr[4]]
    r.part(dict(kind="sweep", pts=r.Hp(line), width=9 * r.s, ink=tone, side=0.5, pale=0.5, dry=0.3, wet=0.3,
                seed=r.n(), profile="flat", layer="head"))
    r.part(dict(kind="sweep", pts=r.Hp([bk[4], (bk[7][0] + 4, bk[7][1]), (bk[11][0] + 6, bk[11][1])]),
                width=11 * r.s, ink=tone, side=-0.3, pale=0.4, dry=0.45, wet=0.2, seed=r.n(), profile="drop",
                layer="head"))


def silver(r, n=7):
    """花白发：几道留白银丝。"""
    sil = skull_sil(r)
    for k in range(n):
        a = sil[26 + k * 2]
        b = sil[33 + k * 2]
        r.part(dict(kind="rstroke", pts=r.Hp([a, ((a[0] + b[0]) / 2 + 4, (a[1] + b[1]) / 2), b]), width=1.6 * r.s,
                    amount=0.55, dry=0.55, profile="nail", seed=r.n()))


# ───────────────────────── 冠帽 ─────────────────────────
def crown(r, pts, tone=INK, zc=-6, ratio=1.15, dry=0.3, **kw):
    """冠体（回转体轮廓）焦墨一团；深冠在受光一侧留一道淡白（漆纱的反光），不是剪纸式的一块黑。"""
    P = r.Hs(pts, zc, ratio)
    r.part(dict(kind="wash", pts=P, tone=tone, edge=0.22, var=0.28, dry_edge=dry, dry_depth=8,
                bloom=0.08, layer="head", **kw))
    if tone >= 0.6 and len(pts) >= 6:
        xs = [p[0] for p in P]
        ys = [p[1] for p in P]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        lx = x0 + (x1 - x0) * 0.22
        r.part(dict(kind="rstroke", pts=[(lx + (x1 - x0) * 0.04, y0 + (y1 - y0) * 0.18), (lx, y0 + (y1 - y0) * 0.5),
                                         (lx + (x1 - x0) * 0.03, y0 + (y1 - y0) * 0.8)],
                    width=max(3.0, (x1 - x0) * 0.07), amount=0.28, dry=0.6, profile="nail", seed=r.n()))


def band(r, y, rx=50, rz=58, zc=-6, w=3.0, amount=0.55, tone=None, ink=0.85):
    """冠上一道横纹（贴冠面转）：深冠留白，浅冠墨线。"""
    pts = []
    for i in range(13):
        a = math.pi * (0.08 + 0.84 * i / 12)
        pts.append((rx * math.cos(a), y, zc + rz * math.sin(a)))
    pts = [(x, y, z) for x, y, z in pts]
    if tone is None or tone >= 0.35:
        r.part(dict(kind="rstroke", pts=r.H3(pts), width=w * r.s, amount=amount, dry=0.4, profile="even",
                    seed=r.n()))
    else:
        r.stroke3(pts, w, ink=ink, dry=0.4, profile="even")


def brim(r, y, R, tone=INK, w=10, ratio=1.0, lift=0.0):
    """帽檐：水平圆盘，投影成扁椭圆；前缘一笔焦墨。"""
    pts = [(R * math.cos(2 * math.pi * i / 36), y - lift * (0.5 + 0.5 * math.sin(2 * math.pi * i / 36)),
            -6 + R * ratio * math.sin(2 * math.pi * i / 36)) for i in range(36)]
    P = r.H3(pts)
    r.part(dict(kind="wash", pts=P, tone=tone * 0.9, edge=0.3, var=0.3, dry_edge=0.3, dry_depth=6, layer="head",
                bloom=0.1))
    front = [pts[i] for i in range(0, 19)]
    r.part(dict(kind="sweep", pts=r.H3(front), width=w * r.s * 0.6, ink=tone, side=0.6, pale=0.5, dry=0.3, wet=0.3,
                seed=r.n(), profile="flat", layer="head"))


def hat(r):
    sp = r.spec
    hg = sp.get("head", "topknot")
    t = {"ink": INK, "dark": DARK, "grey": GREY, "pale": PALE, "white": PALE}.get(sp.get("hat_tone", "ink"), INK)
    ht = {"ink": INK, "grey": 0.84}.get(sp.get("hair_tone", "ink"), INK)
    grey_hair = sp.get("hair_tone") == "grey"
    rng = r.rng
    th = r.th

    def futou_body(h=100, w=51):
        crown(r, [(-w, -30), (-w - 2, -58), (-w + 8, -72), (-32, -74), (-30, -h + 2), (-18, -h - 10), (18, -h - 10),
                  (30, -h + 2), (32, -74), (w - 8, -72), (w + 2, -58), (w, -30), (26, -40), (0, -44), (-26, -40)],
              t)
        band(r, -70, tone=t, w=2.8, amount=0.5)

    if hg in ("topknot", "topknot_band", "zongjiao", "messy", "lowbun", "gaoji", "tongguan", "bald") \
            and hg != "bald":
        hair(r, ht)
        if grey_hair:
            silver(r)
    if hg in ("zhanjiao", "zhijiao"):     # 展脚 / 直脚幞头（两脚在 behind_head 里）
        hair(r, ht, full=False)
        futou_body(104)
    elif hg == "ruanjiao":                # 软脚幞头（软脚在 behind_head 里）
        hair(r, ht, full=False)
        futou_body(96)
    elif hg == "jiaojiao":                # 交脚幞头
        hair(r, ht, full=False)
        futou_body(98)
    elif hg == "xiaofutou":               # 小幞头（内侍）
        hair(r, ht, full=False)
        crown(r, [(-50, -30), (-51, -58), (-36, -80), (0, -88), (36, -80), (51, -58), (50, -30), (24, -40), (0, -44),
                  (-24, -40)], t)
    elif hg == "fujin":                   # 幅巾：软巾裹头，巾尾自脑后垂到肩上
        if t >= 0.35:
            hair(r, ht, full=False)
            crown(r, [(-53, -22), (-58, -60), (-44, -92), (0, -106), (44, -92), (58, -60), (53, -22), (28, -38),
                      (0, -42), (-28, -38)], t, ratio=1.2)
            band(r, -50, tone=t, w=2.6, amount=0.45)
            band(r, -80, rx=40, rz=48, tone=t, w=2.2, amount=0.35)
        else:                              # 素巾（孝服白巾）：淡墨 + 墨线
            hair(r, ht, full=False)
            r.part(dict(kind="cover", pts=r.Hs([(-53, -22), (-58, -60), (-44, -92), (0, -106), (44, -92), (58, -60),
                                                (53, -22), (28, -38), (0, -42), (-28, -38)], -6, 1.2), tone=0.12,
                        rough=0.5, layer="head"))
            r.stroke_h(r_sil([(-53, -22), (-58, -60), (-44, -92), (0, -106), (44, -92), (58, -60), (53, -22)]), 2.2,
                       ink=0.75, dry=0.4, profile="even", sil=True)
            band(r, -52, tone=t, w=1.6, ink=0.6)
        if sp.get("askew"):
            crown(r, [(8, -98), (40, -116), (66, -104), (52, -88)], t)
    elif hg == "gaojin":                  # 高装巾子（东坡巾式）
        hair(r, ht, full=False)
        crown(r, [(-38, -60), (-37, -150), (-28, -158), (28, -158), (37, -150), (38, -60)], t, ratio=1.0)
        crown(r, [(-52, -22), (-54, -104), (-46, -112), (-10, -112), (0, -96), (10, -112), (46, -112), (54, -104),
                  (52, -22), (26, -36), (0, -40), (-26, -36)], t, ratio=1.1)
        band(r, -104, tone=t, w=2.4, amount=0.45)
    elif hg == "chantou":                 # 缠头：宽笔淡墨一圈圈绕，留一两处白
        hair(r, INK, full=False)
        tt = 0.5 if t < 0.35 else t
        base = [(-60, -24), (-68, -60), (-60, -100), (-34, -124), (0, -130), (34, -124), (60, -100), (68, -60),
                (60, -24), (30, -38), (0, -42), (-30, -38)]
        r.part(dict(kind="cover", pts=r.Hs(base, -6, 1.12), tone=0.14 if t < 0.35 else tt * 0.6, rough=0.5,
                    layer="head"))
        for k, (y0, y1, w) in enumerate(((-34, -70, 22), (-58, -98, 20), (-84, -118, 17), (-44, -84, 16))):
            a = [(-62 + k * 3, y0, -10), (-20, y0 - 10, 50), (30, (y0 + y1) / 2, 52), (62 - k * 4, y1, -6)]
            r.part(dict(kind="sweep", pts=r.H3(a), width=w * r.s, ink=tt, side=0.7 * (1 if k % 2 else -1), pale=0.25,
                        dry=0.35 + 0.1 * k, wet=0.4, seed=r.n(), profile="press", layer="head"))
        r.stroke_h(r_sil(base[:9]), 2.0, ink=0.7, dry=0.45, profile="even", sil=True)
    elif hg == "bandana":                 # 布缠头（海上人），结在脑后、两尾飘出
        hair(r, ht, full=False)
        crown(r, [(-52, -14), (-56, -52), (-40, -80), (0, -90), (40, -80), (56, -52), (52, -14), (30, -36), (0, -42),
                  (-30, -36)], t, ratio=1.1)
        band(r, -40, tone=t, w=2.4, amount=0.4)
    elif hg == "douli":                   # 竹笠：尖顶宽檐
        hair(r, ht, full=False)
        crown(r, [(0, -150), (-30, -120), (-64, -82), (-64, -60), (64, -60), (64, -82), (30, -120)], t, ratio=1.0,
              sharp=True)
        brim(r, -58, 138, t, w=12, lift=6)
        for x in (-50, -22, 8, 36):
            r.stroke_h([(0, -146), (x * 1.6, -62)], 1.4, ink=0.4, dry=0.5, profile="even", sil=True, rstroke=True)
    elif hg == "zhanli":                  # 破毡笠
        hair(r, ht, full=False)
        crown(r, [(-46, -44), (-45, -100), (-24, -118), (0, -122), (24, -118), (45, -100), (46, -44)], t)
        brim(r, -46, 92, t, w=10, lift=8)
    elif hg in ("helmet", "fengchi"):     # 兜鍪：盔体 + 顿项 + 顶缨
        crown(r, [(-58, -22), (-61, -70), (-44, -106), (0, -120), (44, -106), (61, -70), (58, -22), (26, -36),
                  (0, -30), (-26, -36)], t, ratio=1.1)
        for y in (-44, -80):
            band(r, y, tone=t, w=2.6, amount=0.55)
        r.part(dict(kind="sweep", pts=r.H3([(0, -118, -6), (0, -140, -6)]), width=7 * r.s, ink=t, side=0, pale=0.8,
                    dry=0.2, wet=0.2, seed=r.n(), profile="flat", layer="head"))
        tassel = [(0, -144, -6), (-8, -170, -4), (4, -196, -8)]
        r.part(dict(kind="sweep", pts=r.H3(tassel), width=20 * r.s, ink=0.55, side=0.2, pale=0.5, dry=0.6, wet=0.5,
                    seed=r.n(), profile="press", layer="tassel"))
        if hg == "fengchi":                # 凤翅：贴盔两侧展开的宽翅，翅梢微卷，三道翎纹（不是两只角）
            for sd in (-1, 1):
                wing = [(sd * 50, -46, -10), (sd * 84, -38, -14), (sd * 116, -52, -16), (sd * 136, -82, -16),
                        (sd * 128, -98, -16), (sd * 108, -84, -14), (sd * 84, -74, -12), (sd * 58, -70, -10)]
                r.part(dict(kind="wash", pts=r.H3(wing), tone=t * 0.88, edge=0.3, var=0.3, dry_edge=0.5,
                            dry_depth=8, bloom=0.1, layer="head"))
                for k in range(3):
                    u = 0.25 + k * 0.25
                    a = (sd * (56 + 60 * u), -58 - 14 * u, -12)
                    b = (sd * (70 + 64 * u), -44 - 40 * u, -14)
                    r.part(dict(kind="rstroke", pts=r.H3([a, b]), width=2.0 * r.s, amount=0.45, dry=0.5,
                                profile="nail", seed=r.n()))
    elif hg == "boli":                    # 钹笠帽：圆顶 + 平檐；帽下辫环（小，缩在耳后）
        hair(r, ht, full=False)
        crown(r, [(-47, -56), (-44, -92), (-22, -106), (0, -110), (22, -106), (44, -92), (47, -56)], t)
        brim(r, -58, 84, t, w=9, lift=4)
        r.part(dict(kind="wash", pts=r.Hs([(-5, -110), (5, -110), (5, -122), (-5, -122)], -6, 1.0), tone=t,
                    layer="head"))
    elif hg == "nuanmao":                 # 暖帽：翻沿皮檐 + 顶珠
        hair(r, ht, full=False)
        ft = {"ink": INK, "grey": GREY, "pale": PALE}.get(sp.get("fur_tone", "grey"), GREY)
        tc = t if t >= 0.35 else 0.14
        if t < 0.35:
            r.part(dict(kind="cover", pts=r.Hs([(-44, -60), (-42, -104), (-22, -118), (0, -122), (22, -118),
                                                (42, -104), (44, -60)], -6, 1.1), tone=tc, rough=0.5, layer="head"))
            r.stroke_h(r_sil([(-44, -60), (-42, -104), (-22, -118), (0, -122), (22, -118), (42, -104), (44, -60)]), 2.2,
                       ink=0.72, dry=0.4, profile="even", sil=True)
        else:
            crown(r, [(-44, -60), (-42, -104), (-22, -118), (0, -122), (22, -118), (42, -104), (44, -60)], t)
        # 皮檐：一圈破墨软块（不画刺）
        rim = [(-64, -26), (-68, -62), (-44, -80), (0, -84), (44, -80), (68, -62), (64, -26), (34, -40), (0, -44),
               (-34, -40)]
        r.part(dict(kind="wash", pts=r.Hs(rim, -6, 1.12), tone=max(ft, 0.4) * 0.9, edge=0.35, var=0.55, bleed=1.2,
                    soft=2.4, dry_edge=0.5, dry_depth=6, bloom=0.3, layer="head"))
        r.part(dict(kind="wash", pts=r.Hs([(-7, -122), (7, -122), (7, -136), (-7, -136)], -6, 1.0), tone=INK,
                    layer="head"))
        if sp.get("gold_top"):
            r.part(dict(kind="tint", pts=r.Hs([(-10, -120), (10, -120), (10, -140), (-10, -140)], -6, 1.0),
                        rgb=(0.79, 0.63, 0.29), amount=0.85, mode="opaque"))
        if sp.get("jewel"):                # 帽前一颗宝石：小（约头宽 0.1）
            r.part(dict(kind="tint", pts=r.H3([(-4, -98, 46), (4, -98, 46), (4, -91, 47), (-4, -91, 47)]),
                        rgb=(0.62, 0.17, 0.14), amount=0.8, mode="opaque"))
    elif hg == "gaoji":                   # 高髻（妇人）
        crown(r, [(-24, -80), (-34, -110), (-22, -140), (0, -148), (22, -140), (34, -110), (24, -80)], ht, zc=-20)
    elif hg == "lowbun":                  # 低髻素簪：髻盘在脑后（在 behind_head 里），簪在髻上
        pass
    elif hg == "huachai":                 # 花钗冠 + 博鬓
        hair(r, ht, full=False)
        crown(r, [(-60, -50), (-68, -86), (-56, -120), (-28, -140), (0, -146), (28, -140), (56, -120), (68, -86),
                  (60, -50), (0, -58)], t, ratio=1.1)
        for x, y in ((-36, -96), (-12, -120), (14, -118), (38, -94), (0, -80)):
            p = (x, y, surf_z(0, -40) * 0.4 + 30)
            r.dot3(p, 5.5, ink=0.2, reserve=True)
        r.part(dict(kind="tint", pts=r.Hs([(-60, -50), (-68, -86), (-56, -120), (-28, -140), (0, -146), (28, -140),
                                           (56, -120), (68, -86), (60, -50), (0, -58)], -6, 1.1),
                    rgb=(0.79, 0.63, 0.29), amount=0.3, mode="mul"))
    elif hg == "zongjiao":                # 总角：两个小髻
        for sd in (-1, 1):
            r.part(dict(kind="wash", pts=r.Hs([(sd * 20, -66), (sd * 24, -88), (sd * 40, -96), (sd * 56, -88),
                                                (sd * 56, -66), (sd * 42, -58)], -8, 1.0), tone=ht, edge=0.2,
                        dry_edge=0.3, layer="head"))
    elif hg == "tongguan":                # 童冠
        crown(r, [(-47, -36), (-48, -64), (-34, -84), (0, -90), (34, -84), (48, -64), (47, -36), (24, -46), (0, -48),
                  (-24, -46)], t)
        crown(r, [(-16, -84), (-14, -112), (0, -120), (14, -112), (16, -84)], t)
        band(r, -58, tone=t, w=2.4, amount=0.5)
    elif hg == "eboshi":                  # 立乌帽（镰仓）
        hair(r, ht, full=False)
        crown(r, [(-46, -34), (-48, -80), (-42, -140), (-22, -178), (8, -190), (34, -174), (46, -126), (48, -76),
                  (46, -34), (0, -44)], t, ratio=0.9)
        band(r, -100, rx=44, rz=40, tone=t, w=2.2, amount=0.4)
    elif hg == "gat":                     # 高丽黑笠：高筒 + 宽檐（马尾编，半透）
        hair(r, ht, full=False)
        crown(r, [(-34, -62), (-32, -150), (32, -150), (34, -62)], 0.62, ratio=1.0, sharp=True)
        brim(r, -62, 118, 0.55, w=8, lift=2)
        for sd in (-1, 1):
            r.stroke3([(sd * 44, -50, 10), (sd * 40, 16, 20), (sd * 20, 62, 30), (0, 70, 34)], 1.4, ink=0.6, dry=0.3,
                      profile="even")
    if hg == "topknot_band":
        crown(r, [(-18, -78), (-20, -98), (0, -106), (20, -98), (18, -78)], ht, zc=-10)
        band(r, -40, tone=INK, w=4.0, amount=0.5)
    elif hg == "topknot":
        crown(r, [(-18, -78), (-20, -98), (0, -106), (20, -98), (18, -78)], ht, zc=-10)
        r.stroke3([(-26, -92, -10), (26, -86, -10)], 2.4, ink=0.85, dry=0.3, profile="even")
    elif hg == "messy":                   # 草挽乱髻 + 散发
        crown(r, [(-22, -76), (-28, -98), (-10, -114), (12, -110), (26, -96), (20, -76)], ht, zc=-14)
        for a, b in (((-40, -50, -40), (-64, 20, -50)), ((-30, -60, -50), (-50, 40, -60)), ((20, -70, -30),
                                                                                              (36, -120, -30))):
            r.stroke3([a, ((a[0] + b[0]) / 2 - 6, (a[1] + b[1]) / 2, a[2]), b], 3.0, ink=0.85, dry=0.5,
                      profile="nail")
        if grey_hair:
            silver(r, 5)


def r_sil(pts):
    return pts


# ───────────────────────── 须 ─────────────────────────
def beard(r):
    """须：一绺一笔侧锋（头大尾尖，笔尾自然枯成须丝），再补两三根游丝；白须是淡墨底上的留白游丝。"""
    sp = r.spec
    b = sp.get("beard", "none")
    if b == "none":
        return
    bt = sp.get("beard_tone", "ink")
    white = bt == "white"
    grey = bt == "grey"
    ink = 0.9 if not (white or grey) else (0.3 if white else 0.62)
    rng = r.rng
    wind = sp.get("wind", 0.0)
    th = r.th
    far_ok = th < math.radians(58)

    def lock(x, y, length, width, bend=0.0, n_hair=3, dry=0.55):
        """一绺：根在面上 (x,y)，顺重力下垂（画布里接着画）。"""
        P = r.H3([S3(x, y, 1)])[0]
        ln = length * r.s * rng.uniform(0.9, 1.1)
        dx = (bend * 30 + wind * 26 + rng.uniform(-3, 3)) * r.s * r.sg
        mid = (P[0] + dx * 0.35, P[1] + ln * 0.5)
        tip = (P[0] + dx, P[1] + ln)
        r.part(dict(kind="sweep", pts=[P, mid, tip], width=width * r.s, ink=ink, side=0.3 * r.sg, pale=0.5,
                    dry=dry, wet=0.3, seed=r.n(), profile="drop", streak=0.6))
        for k in range(n_hair):
            o = rng.uniform(-0.4, 0.4) * width * r.s
            t2 = (tip[0] + o + rng.uniform(-6, 6) * r.s, tip[1] + rng.uniform(4, 18) * r.s)
            r.part(dict(kind="stroke", pts=[(P[0] + o * 0.5, P[1] + ln * 0.3), (mid[0] + o, mid[1]), t2],
                        width=1.3 * r.s, ink=ink * (0.9 if not white else 1.4), dry=0.55, profile="nail",
                        seed=r.n()))
        if white:                           # 白须：留两三道白丝
            for k in range(2):
                o = rng.uniform(-0.3, 0.3) * width * r.s
                r.part(dict(kind="rstroke", pts=[(P[0] + o, P[1] + 4), (mid[0] + o, mid[1]), (tip[0] + o, tip[1])],
                            width=1.4 * r.s, amount=0.5, dry=0.5, profile="nail", seed=r.n()))

    # 髭：唇上两撇
    if b in ("long3", "goatee", "short", "moustache", "full"):
        for sd in (-1, 1):
            if sd > 0 and not far_ok:
                continue
            a = r.H3([S3(sd * 3, 31, 1)])[0]
            ex = 18 if b != "moustache" else 24
            ey = 40 if b != "moustache" else 52
            c = r.H3([S3(sd * ex, ey, 1)])[0]
            m = ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2 - 2 * r.s)
            r.part(dict(kind="sweep", pts=[a, m, c], width=(6 if b != "moustache" else 8) * r.s, ink=ink, side=0.4,
                        pale=0.5, dry=0.35, wet=0.3, seed=r.n(), profile="drop"))
    if b == "long3":                          # 三绺长须：颏下一绺、两颊各一绺
        lock(0, 58, 104, 18, bend=0.1, n_hair=3)
        lock(-26, 42, 70, 12, bend=-0.15, n_hair=2)
        if far_ok:
            lock(24, 42, 64, 10, bend=0.15, n_hair=1)
    elif b == "full":                         # 络腮胡：沿下颌一团破墨 + 几绺
        fr, bk = r.face_front, r.face_back
        mx, my = r._p3(*S3(0, 47), r.th)
        mass = [bk[15], bk[18], bk[21], bk[24], ((bk[24][0] + fr[24][0]) / 2, 88), (fr[24][0] + 2, 76), fr[23],
                fr[21], fr[19], (mx, my + 2), ((mx + bk[15][0]) / 2, 36)]
        r.part(dict(kind="wash", pts=r.Hp(mass), tone=ink * (0.8 if not white else 0.6), edge=0.35, var=0.5,
                    bleed=1.0, bloom=0.2, dry_edge=0.7, dry_side=(0, 1), dry_depth=12, soft=1.4))
        lock(-2, 62, 44, 24, bend=0.05, n_hair=3)
        lock(-32, 52, 30, 14, bend=-0.2, n_hair=2)
    elif b == "short":
        lock(0, 58, 24, 24, n_hair=2, dry=0.5)
        lock(-22, 50, 18, 14, n_hair=1, dry=0.5)
    elif b == "goatee":
        lock(0, 60, 40, 12, n_hair=2)
