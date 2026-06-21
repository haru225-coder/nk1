#!/usr/bin/env python3
"""生成状态栏九格纹理与小图标（KOEI 暗金风格）。"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ICONS = ASSETS / "icons_stat"

# 暗木 + 金边，与 main_theme / ui_card 一致
BG_DARK = (18, 14, 10, 235)
BG_CHIP = (26, 20, 14, 220)
GOLD = (196, 158, 72, 255)
GOLD_HI = (232, 200, 120, 255)
GOLD_DIM = (120, 92, 40, 255)
INK = (42, 32, 22, 255)


def _draw_ninepatch_tile(
    size: tuple[int, int],
    margin: int,
    fill: tuple[int, int, int, int],
    top_accent: bool = False,
) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle((1, 1, w - 2, h - 2), fill=fill, outline=GOLD, width=2)
    draw.rectangle((3, 3, w - 4, h - 4), outline=GOLD_DIM, width=1)
    if top_accent:
        draw.rectangle((margin, 1, w - margin - 1, 3), fill=GOLD_HI)
    # 角饰
    for x, y in ((2, 2), (w - 6, 2), (2, h - 6), (w - 6, h - 6)):
        draw.rectangle((x, y, x + 3, y + 3), fill=GOLD_HI)
    return img


def make_status_bar_panel() -> None:
    # 宽条底板：可横向拉伸
    img = _draw_ninepatch_tile((128, 56), 18, BG_DARK, top_accent=True)
    # 底部阴影线
    draw = ImageDraw.Draw(img)
    draw.line((8, 54, 120, 54), fill=(0, 0, 0, 80), width=1)
    out = ASSETS / "ui_status_bar_ninepatch.png"
    img.save(out, optimize=True)
    print(f"  {out.name} 128x56 margin~18")


def make_stat_chip(wide: bool = False) -> None:
    w, h = (72, 44) if wide else (56, 44)
    img = _draw_ninepatch_tile((w, h), 10, BG_CHIP)
    draw = ImageDraw.Draw(img)
    # 左侧图标槽暗区
    draw.rectangle((6, 6, 38, h - 7), fill=(12, 9, 6, 160), outline=GOLD_DIM, width=1)
    name = "ui_stat_chip_wide_ninepatch.png" if wide else "ui_stat_chip_ninepatch.png"
    out = ASSETS / name
    img.save(out, optimize=True)
    print(f"  {out.name} {w}x{h}")


def make_divider() -> None:
    img = Image.new("RGBA", (8, 40), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle((3, 4, 4, 36), fill=GOLD_DIM)
    draw.rectangle((3, 8, 4, 32), fill=GOLD_HI)
    out = ASSETS / "ui_status_divider.png"
    img.save(out, optimize=True)
    print(f"  {out.name}")


def _glow_icon(base: Image.Image, glow_color: tuple[int, int, int, int]) -> Image.Image:
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse((4, 4, 36, 36), fill=glow_color)
    glow = glow.filter(ImageFilter.GaussianBlur(2))
    out = Image.alpha_composite(glow, base)
    return out


def _icon_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def icon_money() -> Image.Image:
    img, draw = _icon_canvas()
    draw.ellipse((6, 10, 34, 32), fill=(200, 168, 64, 255), outline=GOLD_HI, width=2)
    draw.rectangle((16, 16, 24, 26), fill=(40, 28, 12, 255), outline=INK, width=1)
    return _glow_icon(img, (200, 160, 40, 60))


def icon_fame() -> Image.Image:
    img, draw = _icon_canvas()
    draw.polygon([(20, 6), (24, 16), (34, 16), (26, 22), (29, 32), (20, 26), (11, 32), (14, 22), (6, 16), (16, 16)], fill=(220, 190, 90, 255), outline=GOLD)
    return _glow_icon(img, (220, 180, 60, 50))


def icon_permit(ok: bool = False) -> Image.Image:
    img, draw = _icon_canvas()
    scroll = (220, 205, 170, 255) if ok else (180, 165, 140, 255)
    draw.rectangle((10, 8, 30, 34), fill=scroll, outline=GOLD, width=2)
    draw.line((14, 14, 26, 14), fill=INK, width=1)
    draw.line((14, 18, 24, 18), fill=INK, width=1)
    draw.line((14, 22, 26, 22), fill=INK, width=1)
    if ok:
        draw.ellipse((22, 24, 32, 34), fill=(60, 160, 90, 255), outline=(120, 220, 140, 255), width=2)
        draw.line((25, 27, 29, 31), fill=(220, 255, 220, 255), width=2)
        draw.line((29, 27, 25, 31), fill=(220, 255, 220, 255), width=2)
        glow = (60, 180, 90, 70)
    else:
        draw.line((16, 26, 24, 30), fill=(180, 80, 60, 255), width=2)
        glow = (180, 80, 40, 50)
    return _glow_icon(img, glow)


def icon_pu() -> Image.Image:
    img, draw = _icon_canvas()
    draw.ellipse((10, 12, 30, 28), fill=(40, 28, 22, 255), outline=GOLD, width=2)
    draw.ellipse((16, 16, 24, 24), fill=(200, 120, 60, 255))
    draw.ellipse((18, 18, 22, 22), fill=(40, 20, 10, 255))
    return _glow_icon(img, (200, 100, 40, 55))


def icon_cargo() -> Image.Image:
    img, draw = _icon_canvas()
    draw.rectangle((8, 14, 32, 34), fill=(90, 62, 38, 255), outline=GOLD, width=2)
    draw.line((8, 20, 32, 20), fill=GOLD_HI, width=2)
    draw.rectangle((12, 24, 20, 30), fill=(120, 85, 50, 255), outline=GOLD_DIM, width=1)
    draw.rectangle((22, 24, 28, 30), fill=(120, 85, 50, 255), outline=GOLD_DIM, width=1)
    return _glow_icon(img, (140, 100, 50, 45))


def icon_location() -> Image.Image:
    img, draw = _icon_canvas()
    draw.polygon([(20, 6), (30, 18), (20, 36), (10, 18)], fill=(60, 120, 160, 255), outline=GOLD_HI, width=2)
    draw.ellipse((16, 14, 24, 22), fill=(200, 230, 255, 255))
    return _glow_icon(img, (80, 140, 200, 50))


def icon_crew() -> Image.Image:
    img, draw = _icon_canvas()
    draw.ellipse((14, 8, 26, 20), fill=(220, 190, 150, 255), outline=GOLD, width=1)
    draw.polygon([(8, 34), (32, 34), (28, 22), (12, 22)], fill=(70, 100, 140, 255), outline=GOLD_HI, width=2)
    draw.line((20, 20, 20, 24), fill=INK, width=2)
    return _glow_icon(img, (80, 120, 180, 50))


def icon_food() -> Image.Image:
    img, draw = _icon_canvas()
    draw.polygon([(10, 16), (30, 16), (32, 34), (8, 34)], fill=(180, 140, 70, 255), outline=GOLD, width=2)
    draw.line((10, 22, 30, 22), fill=GOLD_HI, width=2)
    draw.ellipse((14, 10, 26, 18), fill=(210, 180, 100, 255), outline=GOLD_DIM, width=1)
    return _glow_icon(img, (200, 150, 60, 50))


def icon_ship() -> Image.Image:
    img, draw = _icon_canvas()
    draw.polygon([(6, 28), (34, 28), (30, 20), (10, 20)], fill=(80, 55, 35, 255), outline=GOLD, width=2)
    draw.polygon([(12, 20), (28, 20), (24, 12), (16, 12)], fill=(110, 78, 48, 255), outline=GOLD_HI, width=1)
    draw.line((20, 8, 20, 12), fill=GOLD_HI, width=2)
    draw.polygon([(18, 8), (22, 8), (20, 4)], fill=(200, 60, 50, 255))
    return _glow_icon(img, (140, 90, 50, 50))


def icon_water() -> Image.Image:
    img, draw = _icon_canvas()
    draw.ellipse((12, 10, 28, 30), fill=(70, 130, 190, 255), outline=GOLD_HI, width=2)
    draw.polygon([(16, 14), (22, 22), (18, 26), (14, 20)], fill=(180, 220, 255, 200))
    draw.ellipse((17, 12, 23, 18), fill=(200, 235, 255, 160))
    return _glow_icon(img, (60, 140, 220, 55))


def save_icons() -> None:
    ICONS.mkdir(parents=True, exist_ok=True)
    pairs = [
        ("icon_stat_money.png", icon_money()),
        ("icon_stat_fame.png", icon_fame()),
        ("icon_stat_permit.png", icon_permit(False)),
        ("icon_stat_permit_ok.png", icon_permit(True)),
        ("icon_stat_pu.png", icon_pu()),
        ("icon_stat_cargo.png", icon_cargo()),
        ("icon_stat_location.png", icon_location()),
        ("icon_stat_crew.png", icon_crew()),
        ("icon_stat_food.png", icon_food()),
        ("icon_stat_water.png", icon_water()),
        ("icon_stat_ship.png", icon_ship()),
    ]
    for name, im in pairs:
        path = ICONS / name
        im.save(path, optimize=True)
        print(f"  icons_stat/{name}")


def main() -> None:
    print("Generating status bar assets...")
    make_status_bar_panel()
    make_stat_chip(wide=False)
    make_stat_chip(wide=True)
    make_divider()
    save_icons()
    print("Done.")


if __name__ == "__main__":
    main()