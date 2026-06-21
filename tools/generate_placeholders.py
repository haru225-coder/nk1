#!/usr/bin/env python3
"""生成占位资产并补齐 chapter1 缺失背景文件名。"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
OUT = ASSETS / "placeholders"

BG_ALIASES = {
    "bg_xinghua_school.png": "bg_xinghua_residence.png",
    "bg_quanzhou_port.png": "bg_quanzhou_harbor_koei.png",
    "bg_quanzhou_port_sunset.png": "bg_quanzhou_harbor_koei.png",
    "bg_lin_ship.png": "bg_shipyard.jpg",
    "bg_departure.png": "bg_sea_route_ship.png",
    "bg_penghu_night.png": "bg_reef_bay_koei.png",
    "bg_black_water.png": "bg_sea_route_aligned.png",
    "bg_keelung_coast.png": "bg_reef_bay.jpg",
}

AVATARS = {
    "avatar_fallback.png": ("？", (120, 100, 80)),
    "avatar_chen.png": ("陈子龙", (180, 140, 100)),
    "avatar_teacher.png": ("先生", (100, 120, 140)),
    "avatar_jia.png": ("贾府门生", (160, 110, 130)),
    "avatar_lin.png": ("林伯渊", (90, 100, 120)),
    "avatar_abbas.png": ("阿巴斯", (130, 115, 95)),
    "avatar_official.png": ("市舶小吏", (110, 130, 150)),
    "avatar_elder.png": ("凯达格兰老人", (100, 90, 75)),
    "avatar_child.png": ("凯达格兰孩子", (140, 120, 100)),
}


def _font(size: int):
    for name in (
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/mnt/c/Windows/Fonts/msyh.ttc",
        "/mnt/c/Windows/Fonts/simhei.ttf",
    ):
        p = Path(name)
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def make_bg_fallback(path: Path) -> None:
    import importlib.util

    fin = Path(__file__).resolve().parent / "finish_assets.py"
    spec = importlib.util.spec_from_file_location("finish_assets", fin)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    mod.make_bg_fallback(path)
    print("wrote", path.relative_to(ROOT))


def make_avatar(path: Path, caption: str, tint: tuple[int, int, int]) -> None:
    w, h = 256, 320
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    draw.rectangle((12, 12, w - 12, h - 12), fill=(30, 24, 18, 255), outline=(190, 145, 55, 255), width=3)
    # bust silhouette
    cx = w // 2
    draw.ellipse((cx - 52, 36, cx + 52, 140), fill=(*tint, 255))
    draw.rectangle((cx - 70, 130, cx + 70, 250), fill=(*tint, 230))
    font = _font(22)
    bbox = draw.textbbox((0, 0), caption, font=font)
    tw = bbox[2] - bbox[0]
    draw.rectangle((8, h - 44, w - 8, h - 8), fill=(40, 12, 10, 230))
    draw.text(((w - tw) // 2, h - 38), caption, fill=(255, 230, 170, 255), font=font)
    base.save(path, "PNG")
    print("wrote", path.relative_to(ROOT))


def copy_bg_aliases() -> None:
    for dest_name, src_name in BG_ALIASES.items():
        src = ASSETS / src_name
        dest = ASSETS / dest_name
        if not src.exists():
            print("skip alias, missing source:", src_name)
            continue
        shutil.copy2(src, dest)
        print("alias", dest_name, "<-", src_name)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    make_bg_fallback(OUT / "bg_fallback.png")
    for fname, (caption, tint) in AVATARS.items():
        make_avatar(OUT / fname, caption, tint)
    copy_bg_aliases()
    print("done.")


if __name__ == "__main__":
    main()