#!/usr/bin/env python3
"""Normalize port facility icons to 128px thumbnails for runtime UI."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
SIZE = 128
ICON_IDS = [
    "guild", "tavern", "market", "inn",
    "shipyard", "yamen", "residence", "exam",
]


def polish_icon(src: Path, dst: Path) -> None:
    img = Image.open(src).convert("RGBA")
    img = img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst, optimize=True)
    print(f"  {dst.name} ({SIZE}x{SIZE})")


def make_card_ninepatch(dst: Path) -> None:
    """Small gold-bordered panel tile for facility cards."""
    tile = 64
    margin = 14
    img = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    inner = (18, 14, 10, 220)
    gold = (196, 158, 72, 255)
    gold_hi = (232, 200, 120, 255)
    draw.rectangle((2, 2, tile - 3, tile - 3), fill=inner, outline=gold, width=2)
    draw.rectangle((5, 5, tile - 6, tile - 6), outline=gold_hi, width=1)
    # corner accents
    for x, y in ((4, 4), (tile - 8, 4), (4, tile - 8), (tile - 8, tile - 8)):
        draw.rectangle((x, y, x + 3, y + 3), fill=gold_hi)
    img.save(dst, optimize=True)
    print(f"  {dst.name} (ninepatch tile {tile}x{tile}, margin ~{margin})")


def main() -> None:
    print("Polishing port icons...")
    out_dir = ASSETS / "icons_128"
    for icon_id in ICON_IDS:
        src = ASSETS / f"icon_{icon_id}_koei.png"
        if not src.exists():
            print(f"  SKIP missing {src.name}")
            continue
        polish_icon(src, out_dir / f"icon_{icon_id}_koei.png")
    make_card_ninepatch(ASSETS / "ui_card_ninepatch.png")
    print("Done.")


if __name__ == "__main__":
    main()