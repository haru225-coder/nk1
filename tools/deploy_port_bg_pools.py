#!/usr/bin/env python3
"""Deploy classified port backgrounds into res://assets/port_pools/ and update asset_backgrounds.json."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

SRC = Path("/mnt/c/Users/SC/Downloads/grok-images-classified")
DST_ROOT = Path("/mnt/c/nk1/assets/port_pools")
CONFIG = Path("/mnt/c/nk1/data/asset_backgrounds.json")

# classified folder -> canonical scene bg key
POOL_TO_BG: dict[str, str] = {
    "quanzhou": "res://assets/bg_quanzhou_port.png",
    "quanzhou_sunset": "res://assets/bg_quanzhou_port_sunset.png",
    "xinghua": "res://assets/bg_xinghua_harbor.jpg",
    "mingzhou": "res://assets/bg_mingzhou_port.png",
    "jeju": "res://assets/bg_jeju_port.png",
    "tunmen": "res://assets/bg_tunmen_port.png",
    "zhangzhou": "res://assets/bg_zhangzhou_port.png",
    "wenzhou": "res://assets/bg_wenzhou_port.png",
    "ganpu": "res://assets/bg_ganpu_port.png",
    "guangzhou": "res://assets/bg_guangzhou_port.png",
    "penghu_night": "res://assets/bg_penghu_night.png",
    "keelung": "res://assets/bg_keelung_port.png",
    "champa": "res://assets/bg_champa_port.png",
    "bugan": "res://assets/bg_bugan_port.png",
    "tsushima": "res://assets/bg_tsushima_port.png",
}

# Additional scene bg keys that share the same image pool.
POOL_EXTRA_BG: dict[str, list[str]] = {
    "penghu_night": ["res://assets/bg_penghu_port.png"],
    "keelung": ["res://assets/bg_keelung_coast.png"],
}


def collect_images(pool_name: str) -> list[Path]:
    paths: list[Path] = []
    for base in (SRC / pool_name, SRC / "_review" / pool_name):
        if not base.is_dir():
            continue
        for pattern in ("*.jpg", "*.jpeg", "*.png", "*.webp"):
            paths.extend(base.glob(pattern))
    paths.sort(key=lambda p: p.name.lower())
    # stable dedupe by resolved path
    seen: set[str] = set()
    out: list[Path] = []
    for p in paths:
        key = str(p.resolve())
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def main() -> None:
    if not SRC.is_dir():
        raise SystemExit(f"Source not found: {SRC}")

    DST_ROOT.mkdir(parents=True, exist_ok=True)

    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    bg_pools: dict[str, str] = dict(data.get("bg_pools", {}))
    summary: dict[str, int] = {}

    for pool_name, bg_key in POOL_TO_BG.items():
        images = collect_images(pool_name)
        pool_dir = DST_ROOT / pool_name
        if not images:
            if pool_dir.is_dir():
                kept = len(list(pool_dir.glob("*.jpg"))) + len(list(pool_dir.glob("*.png")))
                print(f"{pool_name}: keep existing {kept} (no new source)")
            continue
        if pool_dir.exists():
            shutil.rmtree(pool_dir)
        pool_dir.mkdir(parents=True)
        rel_paths: list[str] = []
        for i, src in enumerate(images, start=1):
            ext = src.suffix.lower() if src.suffix else ".jpg"
            if ext not in {".jpg", ".jpeg", ".png", ".webp"}:
                ext = ".jpg"
            dest = pool_dir / f"{i:03d}{ext}"
            shutil.copy2(src, dest)
            rel_paths.append(f"res://assets/port_pools/{pool_name}/{dest.name}")

        pool_res_dir = f"res://assets/port_pools/{pool_name}/"
        for key in [bg_key, *POOL_EXTRA_BG.get(pool_name, [])]:
            bg_pools[key] = pool_res_dir
        summary[pool_name] = len(rel_paths)
        print(f"{pool_name}: deployed {len(rel_paths)} -> {bg_key}")

    aliases: dict[str, str] = data.get("bg_aliases", {})

    # Pools replace single-file aliases for covered ports.
    for bg_key in bg_pools:
        aliases.pop(bg_key, None)

    data["version"] = 2
    data["bg_pools"] = bg_pools
    data["bg_aliases"] = aliases
    data["_comment_pools"] = (
        "进港背景轮换：bg_pools 键=场景 bg 路径，值=图池目录；"
        "AssetPlaceholder.pick_background_path() 按序轮播目录内 jpg。"
    )

    CONFIG.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nWrote {CONFIG}")
    print(f"Pools: {len(bg_pools)} keys, {sum(summary.values())} images")


if __name__ == "__main__":
    main()