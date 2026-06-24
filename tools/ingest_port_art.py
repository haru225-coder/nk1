#!/usr/bin/env python3
"""校验、归一化并入库港口背景图到 assets/bg_*_port.png。"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
INGESTED = ASSETS / "_ingested"
PROMPTS_MD = ROOT / "docs" / "port_art_prompts.md"

TARGET_W, TARGET_H = 1920, 1080
MIN_BYTES = 50_000

# 已有资产可回退（生成前/缺图时）
FALLBACK_SOURCES: dict[str, str] = {
    "bg_quanzhou_port.png": "bg_quanzhou_harbor_koei.png",
    "bg_quanzhou_port_sunset.png": "bg_quanzhou_harbor_koei.png",
    "bg_quanzhou_harbor_koei.png": "bg_quanzhou_harbor.jpg",
    "bg_guangzhou_port.png": "bg_guangzhou_harbor_koei.png",
    "bg_xinghua_harbor.jpg": "bg_xinghua_harbor_koei.png",
    "bg_keelung_port.png": "bg_keelung_coast.png",
    "bg_penghu_port.png": "bg_penghu_night.png",
    "bg_mingzhou_port.png": "bg_quanzhou_harbor_koei.png",
    "bg_wenzhou_port.png": "bg_quanzhou_harbor_koei.png",
    "bg_hakata_port.png": "bg_western_port.png",
    "bg_champa_port.png": "bg_arab_desert_pass.png",
    "bg_jeju_port.png": "bg_northern_fortress_snow.png",
    "bg_ganpu_port.png": "bg_black_water.png",
    "bg_zhangzhou_port.png": "bg_quanzhou_port_sunset.png",
    "bg_qiongzhou_port.png": "bg_reef_bay_koei.png",
    "bg_sanfoqi_port.png": "bg_arab_mosque.jpg",
    "bg_longyamen_port.png": "bg_black_water.png",
    "bg_bugan_port.png": "bg_temple_gate.jpg",
    "bg_jiaozhi_port.png": "bg_quanzhou_arab_market.png",
    "bg_yeshou_port.png": "bg_temple_library.jpg",
    "bg_tunmen_port.png": "bg_customs_patrol.png",
    "bg_tsushima_port.png": "bg_northern_fortress_snow.png",
    "bg_byland_port.png": "bg_northern_fortress_snow.png",
    "bg_xuwen_port.png": "bg_reef_bay.jpg",
}

# loose grok 文件 → 目标（按 port_art_prompts.md 顺序维护）
LOOSE_PORT_MAP: dict[str, str] = {}


def parse_prompts_md() -> dict[str, dict[str, str]]:
    text = PROMPTS_MD.read_text(encoding="utf-8")
    entries: dict[str, dict[str, str]] = {}
    blocks = re.split(r"\n---\n", text)
    for block in blocks:
        file_m = re.search(r"\*\*文件\*\*:\s*`([^`]+)`", block)
        id_m = re.search(r"\((\w+_port)\)", block)
        prompt_m = re.search(r"```\n([\s\S]*?)```", block)
        if not file_m:
            continue
        fname = file_m.group(1).strip()
        entries[fname] = {
            "port_key": id_m.group(1) if id_m else fname.replace("bg_", "").replace(".png", "").replace(".jpg", ""),
            "prompt": prompt_m.group(1).strip() if prompt_m else "",
        }
    return entries


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
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.suffix.lower() == ".jpg":
            im.save(dest, "JPEG", quality=90, optimize=True)
        else:
            im.save(dest, "PNG", optimize=True)


def archive_loose(path: Path) -> None:
    if path.parent != ASSETS or not path.name.startswith("grok-"):
        return
    INGESTED.mkdir(parents=True, exist_ok=True)
    target = INGESTED / path.name
    if target.exists():
        target.unlink()
    shutil.move(str(path), str(target))


def ingest_loose(src_name: str, dest_name: str) -> str:
    src = ASSETS / src_name
    dest = ASSETS / dest_name
    if not src.exists():
        return f"MISSING  {src_name} -> {dest_name}"
    normalize_background(src, dest)
    archive_loose(src)
    return f"OK  {src_name} -> {dest_name} ({dest.stat().st_size} bytes)"


def ensure_from_fallback(dest_name: str) -> str:
    dest = ASSETS / dest_name
    if dest.exists() and dest.stat().st_size >= MIN_BYTES:
        return f"OK  {dest_name} already present"
    fb = FALLBACK_SOURCES.get(dest_name)
    if not fb:
        return f"MISSING  {dest_name} (no fallback)"
    src = ASSETS / fb
    if not src.exists():
        return f"MISSING  {dest_name} (fallback {fb} absent)"
    normalize_background(src, dest)
    return f"FALLBACK  {dest_name} <- {fb}"


def main() -> None:
    entries = parse_prompts_md()
    print(f"Parsed {len(entries)} port art entries from port_art_prompts.md\n")

    print("=== Ingest loose grok -> port backgrounds ===")
    for src_name, dest_name in LOOSE_PORT_MAP.items():
        print(ingest_loose(src_name, dest_name))

    print("\n=== Ensure all prompt targets exist ===")
    for dest_name in sorted(entries):
        dest = ASSETS / dest_name
        if dest.exists() and dest.stat().st_size >= MIN_BYTES:
            print(f"OK  {dest_name} ({dest.stat().st_size} bytes)")
        else:
            print(ensure_from_fallback(dest_name))

    print("\nDone.")


if __name__ == "__main__":
    main()