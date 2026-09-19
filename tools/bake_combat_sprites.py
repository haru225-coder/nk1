#!/usr/bin/env python3
"""海图图式战斗精灵：福船 / 海鹘 / 铁子。真 RGBA，不再用 RGB 照片底板。"""
from __future__ import annotations

import os
import struct
import zlib
import binascii

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets")


def new_canvas(w: int, h: int):
    return [[(0, 0, 0, 0) for _ in range(w)] for _ in range(h)], w, h


def blend(dst, x, y, rgba):
    if x < 0 or y < 0 or y >= len(dst) or x >= len(dst[0]):
        return
    r, g, b, a = rgba
    if a <= 0:
        return
    or_, og, ob, oa = dst[y][x]
    if a >= 255 or oa == 0:
        dst[y][x] = (r, g, b, a if a >= 255 else max(a, oa))
        if a < 255 and oa:
            ia = a / 255.0
            dst[y][x] = (
                int(or_ * (1 - ia) + r * ia),
                int(og * (1 - ia) + g * ia),
                int(ob * (1 - ia) + b * ia),
                min(255, oa + a),
            )
        return
    ia = a / 255.0
    oa_f = oa / 255.0
    out_a = ia + oa_f * (1 - ia)
    if out_a <= 0:
        return
    dst[y][x] = (
        int((r * ia + or_ * oa_f * (1 - ia)) / out_a),
        int((g * ia + og * oa_f * (1 - ia)) / out_a),
        int((b * ia + ob * oa_f * (1 - ia)) / out_a),
        int(out_a * 255),
    )


def pset(dst, x, y, rgba):
    blend(dst, int(round(x)), int(round(y)), rgba)


def fill_ellipse(dst, cx, cy, rx, ry, rgba):
    rx = max(1, int(rx))
    ry = max(1, int(ry))
    for y in range(-ry, ry + 1):
        yy = y / ry
        span = (1 - yy * yy) ** 0.5
        w = int(rx * span)
        for x in range(-w, w + 1):
            # soft edge
            nx, ny = (x / rx), yy
            d = nx * nx + ny * ny
            a = rgba[3]
            if d > 0.86:
                a = int(a * max(0.0, 1.0 - (d - 0.86) / 0.14))
            if a > 0:
                blend(dst, cx + x, cy + y, (rgba[0], rgba[1], rgba[2], a))


def fill_rect(dst, x0, y0, x1, y1, rgba):
    if x0 > x1:
        x0, x1 = x1, x0
    if y0 > y1:
        y0, y1 = y1, y0
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            blend(dst, x, y, rgba)


def line(dst, x0, y0, x1, y1, rgba, width=1):
    x0, y0, x1, y1 = float(x0), float(y0), float(x1), float(y1)
    dx, dy = x1 - x0, y1 - y0
    n = int(max(abs(dx), abs(dy), 1)) + 1
    hw = max(0, (width - 1) / 2)
    for i in range(n + 1):
        t = i / n
        x, y = x0 + dx * t, y0 + dy * t
        if hw <= 0:
            pset(dst, x, y, rgba)
        else:
            for ox in range(-int(hw) - 1, int(hw) + 2):
                for oy in range(-int(hw) - 1, int(hw) + 2):
                    if ox * ox + oy * oy <= hw * hw + 0.7:
                        pset(dst, x + ox, y + oy, rgba)


def fill_poly(dst, pts, rgba):
    if len(pts) < 3:
        return
    ys = [p[1] for p in pts]
    y0, y1 = int(min(ys)), int(max(ys))
    n = len(pts)
    for y in range(y0, y1 + 1):
        xs = []
        for i in range(n):
            x1, y1_ = pts[i]
            x2, y2 = pts[(i + 1) % n]
            if (y1_ <= y < y2) or (y2 <= y < y1_):
                if y2 == y1_:
                    continue
                xs.append(x1 + (y - y1_) * (x2 - x1) / (y2 - y1_))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            xa, xb = int(xs[i]), int(xs[i + 1])
            if xa > xb:
                xa, xb = xb, xa
            for x in range(xa, xb + 1):
                blend(dst, x, y, rgba)


def stroke_poly(dst, pts, rgba, width=2, close=True):
    n = len(pts)
    last = n if close else n - 1
    for i in range(last):
        a, b = pts[i], pts[(i + 1) % n]
        line(dst, a[0], a[1], b[0], b[1], rgba, width)


def downsample(src, tw, th):
    sh, sw = len(src), len(src[0])
    out = [[(0, 0, 0, 0) for _ in range(tw)] for _ in range(th)]
    for y in range(th):
        for x in range(tw):
            x0, x1 = int(x * sw / tw), int((x + 1) * sw / tw)
            y0, y1 = int(y * sh / th), int((y + 1) * sh / th)
            r = g = b = a = c = 0
            for yy in range(y0, max(y1, y0 + 1)):
                for xx in range(x0, max(x1, x0 + 1)):
                    pr, pg, pb, pa = src[yy][xx]
                    r += pr * pa
                    g += pg * pa
                    b += pb * pa
                    a += pa
                    c += 1
            if a <= 0 or c <= 0:
                continue
            out[y][x] = (int(r / a), int(g / a), int(b / a), min(255, int(a / c)))
    return out


def write_png(path, pix):
    h, w = len(pix), len(pix[0])
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for r, g, b, a in pix[y]:
            raw.extend((r, g, b, a))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", binascii.crc32(t + d) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print(f"  wrote {path} {w}x{h} {len(data)}B")


# ── palettes：墨线平涂，奶油帆 / 绛红帆在蓝海上要跳出来 ──
INK = (32, 20, 14, 255)
PLAYER = {
    "hull": (176, 108, 58, 255),
    "hull_dk": (112, 62, 32, 255),
    "hull_lt": (214, 154, 88, 255),
    "deck": (232, 196, 132, 255),
    "sail": (255, 244, 214, 255),
    "sail_lt": (255, 252, 236, 255),
    "sail_sh": (214, 186, 140, 255),
    "flag": (36, 122, 96, 255),
    "flag_lt": (86, 168, 132, 255),
    "mast": (86, 54, 34, 255),
    "trim": (212, 164, 64, 255),
}
PIRATE = {
    "hull": (52, 32, 28, 255),
    "hull_dk": (28, 16, 14, 255),
    "hull_lt": (92, 54, 46, 255),
    "deck": (118, 72, 58, 255),
    "sail": (196, 48, 44, 255),
    "sail_lt": (224, 86, 72, 255),
    "sail_sh": (120, 28, 26, 255),
    "flag": (18, 16, 16, 255),
    "flag_lt": (72, 40, 40, 255),
    "mast": (40, 26, 22, 255),
    "trim": (168, 52, 44, 255),
}


def draw_junk_sail(dst, mast_x, top, bot, out_top, out_bot, pal, battens=6, lean=12):
    """硬帆整块在桅右侧，必须伸出船体，否则又会被读成甲板涂色。"""
    sail = [
        (mast_x + 3, top),
        (mast_x + out_top + lean, top + 8),
        (mast_x + out_bot, bot),
        (mast_x + 3, bot - 6),
    ]
    fill_poly(dst, [(x + 10, y + 12) for x, y in sail], (8, 10, 14, 80))
    fill_poly(dst, sail, pal["sail"])
    inner = [
        (mast_x + 8, top + 10),
        (mast_x + 22, top + 14),
        (mast_x + 24, bot - 16),
        (mast_x + 8, bot - 14),
    ]
    fill_poly(dst, inner, pal["sail_lt"])
    height = max(1, bot - top)
    for k in range(1, battens + 1):
        t = k / (battens + 1.0)
        y = top + height * t
        x1 = mast_x + out_top + (out_bot - out_top) * t + lean * (1.0 - t) - 4
        line(dst, mast_x + 6, y, x1, y + 1, pal["sail_sh"], 3)
    stroke_poly(dst, sail, INK, 4)
    line(dst, mast_x, top - 18, mast_x, bot + 28, pal["mast"], 7)
    fill_ellipse(dst, mast_x, top - 10, 6, 6, INK)


def draw_ship(kind: str):
    """侧视立帆、艏朝上。左船体、右硬帆，剪影必须能分开。"""
    pal = PLAYER if kind == "player" else PIRATE
    src, _, _ = new_canvas(384, 512)
    player = kind == "player"

    fill_ellipse(src, 118, 310, 28, 155, (6, 14, 24, 85))

    if player:
        # 福船船体只占左半：尖艏、弧龙骨、方高艉
        hull = [
            (148, 48),
            (188, 78),
            (198, 150),
            (200, 250),
            (194, 340),
            (186, 390),
            (168, 458),
            (118, 442),
            (88, 340),
            (80, 240),
            (92, 140),
            (118, 78),
            (138, 52),
        ]
        keel = [
            (148, 48),
            (138, 52),
            (118, 78),
            (92, 140),
            (80, 240),
            (88, 340),
            (118, 442),
            (168, 458),
            (148, 420),
            (112, 340),
            (104, 240),
            (116, 140),
            (136, 80),
        ]
        castle = [
            (168, 368),
            (248, 378),
            (242, 468),
            (150, 462),
            (146, 400),
        ]
        deck_x = 188
    else:
        hull = [
            (156, 36),
            (190, 68),
            (196, 140),
            (196, 250),
            (190, 360),
            (176, 430),
            (154, 462),
            (122, 444),
            (96, 350),
            (86, 240),
            (98, 130),
            (124, 64),
            (146, 40),
        ]
        keel = [
            (156, 36),
            (146, 40),
            (124, 64),
            (98, 130),
            (86, 240),
            (96, 350),
            (122, 444),
            (154, 462),
            (138, 400),
            (112, 300),
            (108, 200),
            (122, 100),
        ]
        castle = [
            (154, 400),
            (204, 408),
            (198, 458),
            (142, 454),
        ]
        deck_x = 184
        wing = [(36, 200), (90, 188), (96, 336), (40, 344)]
        fill_poly(src, wing, pal["hull_lt"])
        stroke_poly(src, wing, INK, 4)
        line(src, 40, 210, 40, 340, pal["mast"], 4)

    fill_poly(src, hull, pal["hull"])
    fill_poly(src, keel, pal["hull_dk"])
    # 右舷甲板亮带，把船体和帆切开
    rail = [
        (deck_x - 8, 70),
        (deck_x + 10, 80),
        (deck_x + 12, 380),
        (deck_x - 10, 400),
    ]
    fill_poly(src, rail, pal["deck"])
    fill_poly(src, castle, pal["hull_lt"])
    stroke_poly(src, hull, INK, 5)
    stroke_poly(src, castle, INK, 4)
    line(src, deck_x + 2, 78, deck_x + 4, 392, INK, 3)

    ports = (120, 175, 230, 285, 335) if player else (110, 175, 240, 305, 370)
    for y in ports:
        fill_rect(src, 142, y - 8, 164, y + 8, pal["hull_dk"])
        stroke_poly(src, [(142, y - 8), (164, y - 8), (164, y + 8), (142, y + 8)], INK, 2)
        fill_ellipse(src, 153, y, 5, 5, (16, 12, 10, 255))

    eye_y = 82 if player else 68
    fill_ellipse(src, 158, eye_y, 12, 9, pal["trim"])
    fill_ellipse(src, 160, eye_y, 6, 5, INK)
    fill_ellipse(src, 162, eye_y - 2, 2, 2, (250, 240, 220, 255))

    rudder = (
        [(98, 448), (130, 444), (126, 500), (90, 496)]
        if player
        else [(104, 436), (132, 432), (128, 478), (98, 474)]
    )
    fill_poly(src, rudder, pal["hull_dk"])
    stroke_poly(src, rudder, INK, 3)

    # 桅贴在甲板右缘，帆向右伸出到画布边
    if player:
        draw_junk_sail(src, 204, 28, 210, 118, 148, pal, battens=7, lean=14)
        draw_junk_sail(src, 196, 70, 188, 72, 96, pal, battens=5, lean=8)
        draw_junk_sail(src, 212, 248, 384, 88, 112, pal, battens=5, lean=10)
        fx, fy = 214, 18
    else:
        draw_junk_sail(src, 202, 16, 216, 128, 156, pal, battens=6, lean=18)
        draw_junk_sail(src, 194, 56, 176, 70, 92, pal, battens=4, lean=10)
        draw_junk_sail(src, 206, 232, 368, 80, 104, pal, battens=4, lean=12)
        fx, fy = 212, 8

    flag = [(fx, fy), (fx + 54, fy + 10), (fx + 44, fy + 30), (fx, fy + 22)]
    fill_poly(src, flag, pal["flag"])
    fill_poly(src, [(fx, fy), (fx + 54, fy + 10), (fx + 50, fy + 16), (fx, fy + 8)], pal["flag_lt"])
    stroke_poly(src, flag, INK, 3)
    if not player:
        line(src, fx + 10, fy + 20, fx + 40, fy + 12, (236, 220, 200, 255), 4)

    if player:
        fill_rect(src, 188, 400, 210, 436, pal["hull_dk"])
        fill_rect(src, 216, 404, 236, 438, pal["hull_dk"])
        stroke_poly(src, [(188, 400), (210, 400), (210, 436), (188, 436)], INK, 2)
        stroke_poly(src, [(216, 404), (236, 404), (236, 438), (216, 438)], INK, 2)
        fill_rect(src, 184, 376, 236, 388, pal["trim"])
        stroke_poly(src, [(184, 376), (236, 376), (236, 388), (184, 388)], INK, 2)

    return downsample(src, 160, 214)


def draw_shot():
    src, _, _ = new_canvas(80, 80)
    # 短尾焰，铁子本体
    fill_ellipse(src, 28, 46, 8, 5, (220, 96, 36, 90))
    fill_ellipse(src, 24, 50, 10, 6, (40, 36, 34, 60))
    fill_ellipse(src, 44, 36, 16, 16, (22, 18, 16, 255))
    fill_ellipse(src, 44, 36, 13, 13, (64, 56, 50, 255))
    fill_ellipse(src, 44, 36, 10, 10, (86, 76, 68, 255))
    fill_ellipse(src, 39, 31, 5, 4, (220, 204, 176, 210))
    fill_ellipse(src, 54, 24, 4, 4, (236, 132, 40, 230))
    fill_ellipse(src, 58, 19, 2, 2, (255, 214, 110, 200))
    return downsample(src, 32, 32)


def _preview():
    """蓝海上并排，方便肉眼看剪影，不进仓库。"""
    fu = draw_ship("player")
    fal = draw_ship("pirate")
    shot = draw_shot()
    canvas, _, _ = new_canvas(520, 300)
    for y in range(300):
        for x in range(520):
            canvas[y][x] = (18, 78, 112, 255) if (x + y) % 17 else (14, 66, 98, 255)
    def blit(dst, src, ox, oy):
        for y, row in enumerate(src):
            for x, px in enumerate(row):
                blend(dst, ox + x, oy + y, px)
    blit(canvas, fu, 28, 36)
    blit(canvas, fal, 280, 36)
    blit(canvas, shot, 244, 250)
    write_png("/tmp/combat_sprite_preview.png", canvas)


def main():
    write_png(os.path.join(OUT, "ship_fu.png"), draw_ship("player"))
    write_png(os.path.join(OUT, "ship_falcon.png"), draw_ship("pirate"))
    write_png(os.path.join(OUT, "shot_iron.png"), draw_shot())
    _preview()


if __name__ == "__main__":
    main()
