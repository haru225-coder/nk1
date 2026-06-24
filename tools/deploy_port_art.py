#!/usr/bin/env python3
"""将 session 生成图入库到 assets/。支持 manifest JSON 映射。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

DEFAULT_SESSION = Path(
    "/home/sc/.grok/sessions/%2Fhome%2Fsc/019ef1b5-c923-7dc3-b849-7dc35fcdb9a8/images"
)
ASSETS = Path(__file__).resolve().parents[1] / "assets"
MANIFEST = Path(__file__).resolve().parent / "port_art_manifest.json"
TARGET_W, TARGET_H = 1920, 1080


def normalize(src: Path, dest: Path) -> None:
    with Image.open(src) as im:
        im = im.convert("RGB")
        w, h = im.size
        ratio = TARGET_W / TARGET_H
        if w / h > ratio:
            new_w = int(h * ratio)
            left = (w - new_w) // 2
            im = im.crop((left, 0, left + new_w, h))
        else:
            new_h = int(w / ratio)
            top = (h - new_h) // 2
            im = im.crop((0, top, w, top + new_h))
        im = im.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.suffix.lower() == ".jpg":
            im.save(dest, "JPEG", quality=92, optimize=True)
        else:
            im.save(dest, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", type=Path, default=DEFAULT_SESSION)
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    args = parser.parse_args()

    mapping: dict[str, str] = json.loads(args.manifest.read_text(encoding="utf-8"))
    for src_name, dest_name in mapping.items():
        src = args.session / src_name
        dest = ASSETS / dest_name
        if not src.exists():
            print(f"MISSING source {src_name} -> {dest_name}")
            continue
        normalize(src, dest)
        print(f"OK  {dest_name} ({dest.stat().st_size} bytes)")


if __name__ == "__main__":
    main()