#!/usr/bin/env python3
"""校验、重命名并入库第一章背景到 assets/bg_*.png。"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
INGESTED = ASSETS / "_ingested"

TARGET_W, TARGET_H = 1920, 1080

# loose grok 文件 → 目标背景（与 chapter1_scenes_new.json / AssetPlaceholder 一致）
LOOSE_BG_MAP: dict[str, str] = {
    "grok-01e795fc-22dd-415f-887e-874ced429908.jpg": "bg_xinghua_school.png",
    "grok-6788a01b-2331-47d8-917e-09748fa4090e.jpg": "bg_quanzhou_port.png",
    "grok-e163fc64-44b1-4cd3-86ad-08510ca7a612.jpg": "bg_quanzhou_port_sunset.png",
    "grok-46b72da4-357c-4163-aaee-d759b98c07cd.jpg": "bg_lin_ship.png",
    "grok-e05841fc-39c2-4c39-8864-86667d2a717d.jpg": "bg_departure.png",
    "grok-cccb5ff4-c6df-4d62-aa68-e88de5ce746b.jpg": "bg_penghu_night.png",
    "grok-ffe8e81e-2aca-4715-ba27-7c0687733be7.jpg": "bg_black_water.png",
    "grok-4bc342a0-fb8a-4cc2-9bad-cc67a329903f.jpg": "bg_keelung_coast.png",
}

BG_LABELS: dict[str, str] = {
    "bg_xinghua_school.png": "乡学晨课",
    "bg_quanzhou_port.png": "刺桐港初见",
    "bg_quanzhou_port_sunset.png": "返航章末",
    "bg_lin_ship.png": "林伯渊的船",
    "bg_departure.png": "出港",
    "bg_penghu_night.png": "澎湖一夜",
    "bg_black_water.png": "黑水沟",
    "bg_keelung_coast.png": "基隆海岸",
}


def normalize_background(src: Path, dest: Path) -> None:
    with Image.open(src) as im:
        im = im.convert("RGB")
        w, h = im.size
        target_ratio = TARGET_W / TARGET_H
        current_ratio = w / h
        if current_ratio > target_ratio:
            new_w = int(h * target_ratio)
            left = (w - new_w) // 2
            im = im.crop((left, 0, left + new_w, h))
        else:
            new_h = int(w / target_ratio)
            top = (h - new_h) // 2
            im = im.crop((0, top, w, top + new_h))
        im = im.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
        im.save(dest, "PNG", optimize=True)


def archive_loose(path: Path) -> None:
    if path.parent != ASSETS or not path.name.startswith("grok-"):
        return
    INGESTED.mkdir(parents=True, exist_ok=True)
    target = INGESTED / path.name
    if target.exists():
        target.unlink()
    shutil.move(str(path), str(target))


def main() -> None:
    report: list[str] = []
    for fname, dest_name in LOOSE_BG_MAP.items():
        src = ASSETS / fname
        dest = ASSETS / dest_name
        label = BG_LABELS.get(dest_name, dest_name)
        if not src.exists():
            if dest.exists() and dest.stat().st_size > 50_000:
                report.append(f"OK  {label} — {dest_name} already present")
            else:
                report.append(f"MISSING  {label} — expected {fname}")
            continue
        normalize_background(src, dest)
        report.append(f"OK  {label} <- {fname} -> {dest_name}")
        archive_loose(src)

    print("=== Background ingest report ===")
    for line in report:
        print(line)
    ok = sum(1 for line in report if line.startswith("OK"))
    print(f"\nConfigured: {ok}/{len(LOOSE_BG_MAP)} chapter-1 backgrounds @ 1920x1080 PNG")


if __name__ == "__main__":
    main()