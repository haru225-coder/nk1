"""手绘感炮焰 / 水花序列帧。帧格、炮口、水线与 vision_fill_gen.gd 一致，别改尺寸。"""
import math
import random
from PIL import Image

random.seed(11)


def _dot(px, x, y, w, h, rgb, a):
    if a <= 0 or x < 0 or y < 0 or x >= w or y >= h:
        return
    o = px[x, y]
    t = min(255, o[3] + a)
    if o[3] == 0:
        px[x, y] = (*rgb, t)
        return
    k = a / 255.0
    px[x, y] = (
        int(o[0] * (1 - k) + rgb[0] * k),
        int(o[1] * (1 - k) + rgb[1] * k),
        int(o[2] * (1 - k) + rgb[2] * k),
        t,
    )


def _brush(px, w, h, x, y, rx, ry, rgb, a, n=18):
    for _ in range(n):
        ang = random.random() * math.tau
        rad = random.random() ** 0.6
        _dot(px, int(x + math.cos(ang) * rx * rad), int(y + math.sin(ang) * ry * rad), w, h, rgb, a)


def paint_muzzle(path):
    w, h = 1024, 64
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    core = (255, 236, 184)
    flame = (196, 112, 48)
    edge = (140, 42, 32)
    smoke = (92, 72, 52)
    for f in range(8):
        ox = f * 128
        mx, my = ox + 6, 32
        if f == 0:
            length, tongue = 10, 0.2
        elif f == 1:
            length, tongue = 90, 1.0
        elif f == 2:
            length, tongue = 84, 0.85
        elif f == 3:
            length, tongue = 36, 0.35
        elif f == 4:
            length, tongue = 18, 0.12
        else:
            length, tongue = 0, 0
        if tongue > 0:
            for i in range(length):
                t = i / max(length, 1)
                y = my - int(6 * math.sin(t * math.pi) * (1 if f < 3 else 0.4))
                wide = (1 - t) * (7 if f in (1, 2) else 4)
                col = core if t < 0.15 else (flame if t < 0.7 else edge)
                _brush(px, w, h, mx + i, y, max(1, wide), max(1, wide * 0.55), col, int(210 * (1 - t) * tongue), 8)
        if f >= 3:
            puff = f - 2
            sx = mx + 28 + puff * 14
            sy = my - puff * 4
            for k in range(3):
                _brush(
                    px, w, h,
                    sx + k * 10, sy - k * 3,
                    10 + puff * 2, 6 + puff,
                    smoke, int(90 - puff * 12), 22,
                )
        for x in range(ox, ox + 4):
            for y in range(h):
                px[x, y] = (0, 0, 0, 0)
    im.save(path)


def paint_splash(path):
    w, h = 768, 128
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    silk = (246, 238, 220)
    indigo = (40, 70, 90)
    ink = (28, 22, 16)
    heights = [14, 48, 78, 100, 72, 36, 16, 0]
    rings = [6, 8, 12, 16, 22, 28, 34, 40]
    for f in range(8):
        ox = f * 96
        wx, wy = ox + 48, 112
        ht = heights[f]
        if ht > 0:
            for i in range(ht):
                t = i / ht
                wide = 3 + (1 - t) * 8 + (4 if f == 3 and t > 0.75 else 0)
                col = indigo if (i % 7 == 0) else silk
                _brush(px, w, h, wx, wy - i, wide, 2.2, col, int(200 * (0.45 + 0.55 * (1 - t))), 6)
                if i % 5 == 0:
                    _brush(px, w, h, wx - wide, wy - i, 1.2, 2, ink, 80, 3)
            if f >= 4:
                for k in range(12):
                    ang = k / 12 * math.tau
                    _brush(
                        px, w, h,
                        wx + math.cos(ang) * (10 + f * 3),
                        wy - ht * 0.4 + math.sin(ang) * 8,
                        2, 2, silk, 140, 4,
                    )
        rw = rings[f]
        for deg in range(0, 360, 8):
            ang = math.radians(deg)
            _brush(px, w, h, wx + math.cos(ang) * rw, wy + math.sin(ang) * rw * 0.28, 1.4, 1.1, ink, 70, 2)
    im.save(path)


if __name__ == "__main__":
    root = r"C:\nk1\scenes\vision\fill"
    paint_muzzle(root + r"\vs_muzzle_strip.png")
    paint_splash(root + r"\vs_splash_strip.png")
    print("strips ok")
