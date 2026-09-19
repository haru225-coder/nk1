#!/usr/bin/env python3
"""海战船图精修管线：生成原稿 → 抠品红底 → 去溢色/羽化 → 归一化尺寸 → assets/ 真 RGBA。

原稿在 tools/art_src/（.gdignore，不进 Godot 导入与导出）。原稿背景为纯品红，
但带笔刷纹理与暗角，不能用单点色键：先在 HSV 空间圈出品红域，再从四边洪水
填充，只删与画布边相连的背景，船体内部的近似色不受影响。

用法：python3 tools/cut_ship_sprites.py
产物：assets/ship_fu.png / assets/ship_falcon.png + /tmp/ship_preview.png（蓝海预览，不进仓库）
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import binary_dilation, binary_propagation, label

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "art_src")
OUT = os.path.join(ROOT, "assets")

CANVAS = 512  # 输出正方形画布
MARGIN = 6    # 抠底后包围盒外留边

SHIPS = {
    # 原稿 → (输出, 长轴像素, 艏尖位置, 压影中心/半径)。艏朝上，引擎内绕中心旋转。
    # 艏尖/压影为占包围盒高度的比例，按 sprite 实测标线手调（帆伸出船体，剖面分不出）。
    "ship_fu_raw.png": ("ship_fu.png", 460, 0.23, 0.58, 0.32),
    "ship_falcon_raw.png": ("ship_falcon.png", 440, 0.29, 0.60, 0.30),
}


def magenta_mask(rgb: np.ndarray) -> np.ndarray:
    """品红域：色相 270°–335°、饱和度与亮度过门槛。木船体/奶油帆/绛红帆都不会落入。"""
    r = rgb[..., 0].astype(np.float32)
    g = rgb[..., 1].astype(np.float32)
    b = rgb[..., 2].astype(np.float32)
    mx = np.maximum(r, np.maximum(g, b))
    mn = np.minimum(r, np.minimum(g, b))
    diff = mx - mn
    sat = diff / np.maximum(mx, 1.0)
    hue = np.zeros_like(mx)
    nz = diff > 0
    idx = nz & (mx == r)
    hue[idx] = (60.0 * ((g[idx] - b[idx]) / diff[idx])) % 360.0
    idx = nz & (mx == g)
    hue[idx] = 60.0 * ((b[idx] - r[idx]) / diff[idx]) + 120.0
    idx = nz & (mx == b)
    hue[idx] = 60.0 * ((r[idx] - g[idx]) / diff[idx]) + 240.0
    strict = (hue >= 270.0) & (hue <= 335.0) & (sat > 0.22) & (mx > 60.0)
    # 生成图会在背景里画浅粉笔触（sat 低、r/g 都高）， strict 圈不住会形成孤岛；
    # 放宽 hue/sat 但必须 r>g+15 且 b>g+5，奶油帆（r≈g）与绛红帆（b<g）仍安全。
    loose = (hue >= 262.0) & (hue <= 342.0) & (sat > 0.10) & (mx > 100.0) & (r > g + 15.0) & (b > g + 5.0)
    return strict | loose


def background_mask(mask: np.ndarray) -> np.ndarray:
    """从四边洪水填充品红域，返回与画布边相连的背景。

    Pillow 12 的 ImageDraw.floodfill 在 L 图上 thresh=0 不扩散，改用
    scipy binary_propagation：种子=边框上的品红像素，在品红域内传播。
    """
    seed = np.zeros_like(mask)
    seed[0, :] = mask[0, :]
    seed[-1, :] = mask[-1, :]
    seed[:, 0] = mask[:, 0]
    seed[:, -1] = mask[:, -1]
    return binary_propagation(seed, mask=mask)


def despill(rgb: np.ndarray) -> np.ndarray:
    """去品红溢色：r/b 明显高出 g 的像素往 g 收。奶油帆 r≈g、绛红帆 b<g，都碰不到。"""
    r = rgb[..., 0].astype(np.float32)
    g = rgb[..., 1].astype(np.float32)
    b = rgb[..., 2].astype(np.float32)
    hit = (r - g > 25.0) & (b - g > 15.0)
    r2 = np.where(hit, g + (r - g) * 0.25, r)
    b2 = np.where(hit, g + (b - g) * 0.25, b)
    out = rgb.copy()
    out[..., 0] = np.clip(r2, 0, 255).astype(np.uint8)
    out[..., 2] = np.clip(b2, 0, 255).astype(np.uint8)
    return out


def waterline(canvas: Image.Image, bbox: tuple[int, int, int, int], bow_f: float, sh_cy: float, sh_ry: float) -> None:
    """在船体下方画水线：软椭圆压影 + 艏部白沫弧。船图艏朝上。

    压影让船「坐」进海面而不是浮贴上去；随船图一起旋转，符合顶视逻辑。
    艏尖与压影位置按包围盒比例给（见 SHIPS 注释）。
    """
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0, y1 - y0
    cx = (x0 + x1) // 2
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rx, ry = int(w * 0.38), int(h * sh_ry)
    cy = y0 + int(h * sh_cy)
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(5, 16, 28, 130))
    layer = layer.filter(ImageFilter.GaussianBlur(8))
    foam = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    f = ImageDraw.Draw(foam)
    bx, by = cx, y0 + int(h * bow_f)
    f.arc((bx - int(w * 0.30), by - 24, bx + int(w * 0.30), by + 28), 195, 345, fill=(230, 243, 248, 150), width=6)
    f.ellipse((bx - int(w * 0.34), by + 2, bx - int(w * 0.34) + 10, by + 14), fill=(230, 243, 248, 90))
    f.ellipse((bx + int(w * 0.34) - 10, by + 2, bx + int(w * 0.34), by + 14), fill=(230, 243, 248, 90))
    foam = foam.filter(ImageFilter.GaussianBlur(2.5))
    canvas.alpha_composite(layer)
    canvas.alpha_composite(foam)


def make_shot() -> Image.Image:
    """铁子 48²：铁球径向明暗 + 软水花晕（炮弹不随速度旋转，晕必须各向同性）。"""
    S = 192
    src = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(src)
    c = S // 2
    d.ellipse((c - 60, c - 60, c + 60, c + 60), fill=(214, 236, 244, 60))
    src = src.filter(ImageFilter.GaussianBlur(10))
    d = ImageDraw.Draw(src)
    for r, col in ((34, (18, 16, 15, 255)), (28, (52, 48, 44, 255)), (20, (78, 70, 62, 255))):
        d.ellipse((c - r, c - r, c + r, c + r), fill=col)
    d.ellipse((c - 16, c - 20, c + 2, c - 2), fill=(208, 196, 172, 220))
    out = src.resize((48, 48), Image.LANCZOS)
    out.save(os.path.join(OUT, "shot_iron.png"))
    print(f"  shot_iron.png: 48²  {os.path.getsize(os.path.join(OUT, 'shot_iron.png'))}B")
    return out


def cut(raw_path: str, out_name: str, long_axis: int, bow_f: float, sh_cy: float, sh_ry: float) -> Image.Image:
    rgb = np.array(Image.open(raw_path).convert("RGB"))
    bg = background_mask(magenta_mask(rgb))

    # 前景连通体筛选：船体为最大体；桨/桅/旗常与船体仅细根相连甚至相离，
    # 所以保留「最大体 30px 邻域内」的所有连通体，只丢远处漂浮的背景残留斑块。
    fg = ~bg
    tags, n = label(fg, structure=np.ones((3, 3), int))
    if n > 1:
        sizes = np.bincount(tags.ravel())
        sizes[0] = 0
        hull = tags == int(sizes.argmax())
        near = binary_dilation(hull, iterations=30)
        dropped = [int(sizes[t]) for t in range(1, n + 1) if not (near & (tags == t)).any()]
        if dropped:
            print(f"    丢远处孤岛 {len(dropped)} 块，像素 {sorted(dropped, reverse=True)[:5]}")
        fg &= near
        bg = ~fg

    # 背景向外扩 2px 吃掉品红毛边，再对 alpha 轻羽化
    bg_arr = bg.astype(np.uint8) * 255
    bg_img = Image.fromarray(bg_arr, "L").filter(ImageFilter.MaxFilter(5))
    alpha = Image.fromarray(255 - np.array(bg_img), "L").filter(ImageFilter.GaussianBlur(1.0))

    rgb = despill(rgb)
    rgba = np.dstack([rgb, np.array(alpha)])

    ys, xs = np.where(rgba[..., 3] > 8)
    if len(xs) == 0:
        raise SystemExit(f"抠底后为空：{raw_path}")
    x0, x1 = max(0, xs.min() - MARGIN), min(rgba.shape[1], xs.max() + MARGIN + 1)
    y0, y1 = max(0, ys.min() - MARGIN), min(rgba.shape[0], ys.max() + MARGIN + 1)
    ship = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")

    scale = long_axis / max(ship.size)
    ship = ship.resize((max(1, round(ship.width * scale)), max(1, round(ship.height * scale))), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    px, py = (CANVAS - ship.width) // 2, (CANVAS - ship.height) // 2
    waterline(canvas, (px, py, px + ship.width, py + ship.height), bow_f, sh_cy, sh_ry)
    canvas.paste(ship, (px, py), ship)
    out_path = os.path.join(OUT, out_name)
    canvas.save(out_path)
    print(f"  {out_name}: 包围盒 {x1 - x0}x{y1 - y0} → {ship.size} → {CANVAS}²  {os.path.getsize(out_path)}B")
    return canvas


def preview(sprites: dict[str, Image.Image]) -> None:
    """蓝海底色 + 引擎缩放后的实际观感，方便肉眼验收，不进仓库。"""
    sea = Image.new("RGBA", (1180, 620), (16, 62, 92, 255))
    px = sea.load()
    for y in range(620):
        for x in range(1180):
            if (x * 7 + y * 13) % 29 == 0:
                px[x, y] = (20, 74, 108, 255)
    for i, (name, spr) in enumerate(sprites.items()):
        w, h = spr.size
        disp = spr.resize((round(w * 0.62), round(h * 0.62)), Image.LANCZOS)
        sea.paste(disp, (90 + i * 420, 150), disp)
    sea.convert("RGB").save("/tmp/ship_preview.png")
    print("  预览 /tmp/ship_preview.png（0.62 即引擎缩放）")


def main() -> None:
    sprites = {}
    for raw_name, (out_name, long_axis, bow_f, sh_cy, sh_ry) in SHIPS.items():
        sprites[out_name] = cut(os.path.join(SRC, raw_name), out_name, long_axis, bow_f, sh_cy, sh_ry)
    sprites["shot_iron.png"] = make_shot()
    preview(sprites)


if __name__ == "__main__":
    main()
