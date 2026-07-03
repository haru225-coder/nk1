#!/usr/bin/env python3
"""补齐剩余资产缺口：scenes 挂接、缺失文件、回退立绘。"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
PORTRAITS = ASSETS / "portraits"
SCENES_JSON = ROOT / "data" / "scenes.json"

CHAPTER1_BG: dict[str, str] = {
    "scene01_xianghua_school": "res://assets/bg_xinghua_school.png",
    "scene02_quanzhou_port": "res://assets/bg_quanzhou_port.png",
    "scene03_lin_ship": "res://assets/bg_lin_ship.png",
    "scene04_departure": "res://assets/bg_departure.png",
    "scene05_penghu_night": "res://assets/bg_penghu_night.png",
    "scene06_black_water": "res://assets/bg_black_water.png",
    "scene07_keelung_coast": "res://assets/bg_keelung_coast.png",
    "scene08_return": "res://assets/bg_sea_route_fog.png",
}

COMPAT_COPIES: dict[str, str] = {
    "bg_sea_route_aligned.png": "bg_black_water.png",
}

BG_FALLBACK_SOURCE = "bg_departure.png"
BG_FALLBACK_SIZE = (1920, 1080)


def _font(size: int):
    for name in (
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/mnt/c/Windows/Fonts/msyh.ttc",
        "/mnt/c/Windows/Fonts/simhei.ttf",
    ):
        p = Path(name)
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def make_bg_fallback(dest: Path) -> None:
    """无字样全屏回退：暗色化出海图 + 轻暗角，贴合 Koei 对话遮罩。"""
    src = ASSETS / BG_FALLBACK_SOURCE
    if not src.exists():
        src = ASSETS / "bg_black_water.png"
    tw, th = BG_FALLBACK_SIZE
    with Image.open(src) as im:
        im = im.convert("RGB")
        w, h = im.size
        ratio = tw / th
        cw, ch = w / h, ratio
        if w / h > ratio:
            new_w = int(h * ratio)
            left = (w - new_w) // 2
            im = im.crop((left, 0, left + new_w, h))
        else:
            new_h = int(w / ratio)
            top = (h - new_h) // 2
            im = im.crop((0, top, w, top + new_h))
        im = im.resize((tw, th), Image.Resampling.LANCZOS)
        im = ImageEnhance.Brightness(im).enhance(0.38)
        im = ImageEnhance.Color(im).enhance(0.75)
        overlay = Image.new("RGB", (tw, th), (0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        for y in range(th):
            t = y / th
            edge = max(0.0, (t - 0.55) / 0.45)
            alpha = int(90 * edge)
            if alpha:
                draw.line((0, y, tw, y), fill=(0, 0, 0))
        im = Image.blend(im, overlay, 0.35)
        dest.parent.mkdir(parents=True, exist_ok=True)
        im.save(dest, "PNG", optimize=True)


def make_portrait_fallback(dest: Path) -> None:
    w, h = 512, 640
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    draw.rectangle((16, 16, w - 16, h - 16), fill=(30, 24, 18, 255), outline=(190, 145, 55, 255), width=4)
    cx = w // 2
    tint = (120, 100, 80)
    draw.ellipse((cx - 100, 48, cx + 100, 248), fill=(*tint, 255))
    draw.rectangle((cx - 130, 230, cx + 130, 500), fill=(*tint, 230))
    font = _font(48)
    label = "？"
    bbox = draw.textbbox((0, 0), label, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((w - tw) // 2, (h - th) // 2 - 20), label, fill=(255, 230, 170, 255), font=font)
    font_sm = _font(24)
    sub = "未知人物"
    bbox2 = draw.textbbox((0, 0), sub, font=font_sm)
    tw2 = bbox2[2] - bbox2[0]
    draw.rectangle((12, h - 56, w - 12, h - 12), fill=(40, 12, 10, 230))
    draw.text(((w - tw2) // 2, h - 48), sub, fill=(255, 230, 170, 255), font=font_sm)
    dest.parent.mkdir(parents=True, exist_ok=True)
    base.save(dest, "PNG", optimize=True)


def patch_scenes_json() -> list[str]:
    data = json.loads(SCENES_JSON.read_text(encoding="utf-8"))
    report: list[str] = []
    scenes = {s["id"]: s for s in data.get("scenes", [])}
    for scene_id, bg in CHAPTER1_BG.items():
        if scene_id not in scenes:
            report.append(f"SKIP missing scene {scene_id}")
            continue
        old = scenes[scene_id].get("bg", "")
        scenes[scene_id]["bg"] = bg
        rel = bg.replace("res://assets/", "")
        report.append(f"OK  {scene_id}: {old.split('/')[-1]} -> {rel}")
    SCENES_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def copy_compat_files() -> list[str]:
    report: list[str] = []
    for dest_name, src_name in COMPAT_COPIES.items():
        src = ASSETS / src_name
        dest = ASSETS / dest_name
        if not src.exists():
            report.append(f"MISSING source {src_name} for {dest_name}")
            continue
        shutil.copy2(src, dest)
        report.append(f"OK  {dest_name} <- {src_name}")
    return report


def main() -> None:
    print("=== Patch scenes.json (chapter 1 backgrounds) ===")
    for line in patch_scenes_json():
        print(line)

    print("\n=== Compat asset copies ===")
    for line in copy_compat_files():
        print(line)

    print("\n=== Background fallback (no placeholder text) ===")
    bg_dest = ASSETS / "placeholders" / "bg_fallback.png"
    make_bg_fallback(bg_dest)
    print(f"OK  {bg_dest.relative_to(ROOT)} ({bg_dest.stat().st_size} bytes) <- {BG_FALLBACK_SOURCE}")

    print("\n=== Portrait fallback ===")
    dest = PORTRAITS / "portrait_fallback.png"
    make_portrait_fallback(dest)
    print(f"OK  {dest.relative_to(ROOT)} ({dest.stat().st_size} bytes)")

    print("\nDone. Run: python3 validate_project.py")


if __name__ == "__main__":
    main()
