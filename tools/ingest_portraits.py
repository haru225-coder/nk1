#!/usr/bin/env python3
"""校验、入库 NPC 立绘，同步 npcs.json / asset_backgrounds.json / 说话人别名。"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
PORTRAITS = ASSETS / "portraits"
PLACEHOLDERS = ASSETS / "placeholders"
INGESTED = ASSETS / "_ingested"
NPCS_JSON = ROOT / "data" / "npcs.json"
ASSET_BG_JSON = ROOT / "data" / "asset_backgrounds.json"

TARGET_W, TARGET_H = 512, 640
PLACEHOLDER_BYTES_MAX = 12_000

# 第一章核心 NPC：有 placeholders 兜底
LEGACY_PLACEHOLDER: dict[str, str] = {
    "chen_wenlong": "avatar_chen.png",
    "teacher": "avatar_teacher.png",
    "jia_disciple": "avatar_jia.png",
    "lin_boyuan": "avatar_lin.png",
    "abbas": "avatar_abbas.png",
    "customs_official": "avatar_official.png",
    "ketagalan_elder": "avatar_elder.png",
    "ketagalan_child": "avatar_child.png",
}

LOOSE_FILE_MAP: dict[str, str] = {
    "grok-8f0dce14-91c1-4f22-8f70-427122af5600.jpg": "chen_wenlong",
    "grok-5478506b-c7b4-4e9b-9e5a-aa72f8b3af3b.jpg": "teacher",
    "grok-6c5b069a-be3c-49fe-8f5c-49e81611922a.jpg": "jia_disciple",
    "grok-9ad53751-7868-4725-81b7-2d57c136024a.jpg": "lin_boyuan",
    "grok-848fcc9b-9928-40c7-bf44-7ad2c7728c1a.jpg": "abbas",
    "grok-da6cbda9-e78a-4aab-9a1f-5651661b49d0.jpg": "customs_official",
    "grok-c387c377-f4c8-48f7-9360-92dc3cb6e371.jpg": "ketagalan_elder",
    "grok-664b9a1e-b865-4ab3-a500-cae06946ab25.jpg": "ketagalan_child",
}


def portrait_res_path(stem: str) -> str:
    return f"res://assets/portraits/{stem}.png"


def is_placeholder_file(path: Path) -> bool:
    if not path.exists():
        return True
    if path.stat().st_size <= PLACEHOLDER_BYTES_MAX:
        return True
    try:
        with Image.open(path) as im:
            return im.size == (256, 320) and path.stat().st_size <= PLACEHOLDER_BYTES_MAX
    except OSError:
        return True


def normalize_portrait(src: Path, dest: Path) -> None:
    with Image.open(src) as im:
        im = im.convert("RGBA")
        w, h = im.size
        crop_h = int(h * 0.72)
        crop_w = int(w * 0.88)
        left = (w - crop_w) // 2
        top = int(h * 0.02)
        im = im.crop((left, top, left + crop_w, top + crop_h))
        im = im.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        im.save(dest, "PNG", optimize=True)


def load_npcs() -> list[dict]:
    data = json.loads(NPCS_JSON.read_text(encoding="utf-8"))
    return data.get("npcs", [])


def avatar_stem(npc: dict) -> str:
    avatar = str(npc.get("avatar", ""))
    if avatar:
        return Path(avatar.replace("res://", "")).stem
    return f"portrait_{npc.get('id', '')}"


def collect_loose_sources(npc_ids: set[str]) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for fname, npc_id in LOOSE_FILE_MAP.items():
        if npc_id not in npc_ids:
            continue
        for folder in (ASSETS, INGESTED):
            p = folder / fname
            if p.exists():
                found[npc_id] = p
                break
    return found


def sync_legacy_avatars(npcs: list[dict]) -> None:
    data = json.loads(ASSET_BG_JSON.read_text(encoding="utf-8"))
    legacy: dict[str, str] = {}
    fallback = portrait_res_path("portrait_fallback")
    for npc in npcs:
        npc_id = str(npc.get("id", ""))
        if not npc_id:
            continue
        avatar = str(npc.get("avatar", ""))
        stem = avatar_stem(npc)
        portrait_file = PORTRAITS / f"{stem}.png"
        if portrait_file.exists() and not is_placeholder_file(portrait_file):
            legacy[npc_id] = avatar if avatar else portrait_res_path(stem)
        elif npc_id in LEGACY_PLACEHOLDER:
            legacy[npc_id] = f"res://assets/placeholders/{LEGACY_PLACEHOLDER[npc_id]}"
        else:
            legacy[npc_id] = fallback
    data["legacy_avatars"] = legacy
    ASSET_BG_JSON.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def ensure_fallback() -> None:
    dest = PORTRAITS / "portrait_fallback.png"
    src = PLACEHOLDERS / "avatar_fallback.png"
    if src.exists() and (not dest.exists() or is_placeholder_file(dest)):
        shutil.copy2(src, dest)


def main() -> None:
    PORTRAITS.mkdir(parents=True, exist_ok=True)
    npcs = load_npcs()
    npc_ids = {str(n.get("id", "")) for n in npcs if n.get("id")}
    loose = collect_loose_sources(npc_ids)
    report: list[str] = []
    ok = 0
    missing = 0

    for npc in npcs:
        npc_id = str(npc.get("id", ""))
        name = str(npc.get("name", npc_id))
        stem = avatar_stem(npc)
        dest = PORTRAITS / f"{stem}.png"
        res_path = portrait_res_path(stem)
        npc["avatar"] = res_path

        src = loose.get(npc_id)
        if src and not is_placeholder_file(src):
            normalize_portrait(src, dest)
            report.append(f"INGEST  {name} ({npc_id}) <- {src.name}")
            if src.name.startswith("grok-") and src.parent == ASSETS:
                archive = INGESTED / src.name
                archive.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(src), str(archive))
        elif dest.exists() and not is_placeholder_file(dest):
            report.append(f"OK      {name} ({npc_id}) -> {stem}.png")
            ok += 1
        else:
            report.append(f"MISSING {name} ({npc_id}) — no art at {dest.name}")
            missing += 1

    ensure_fallback()
    sync_legacy_avatars(npcs)

    npc_data = json.loads(NPCS_JSON.read_text(encoding="utf-8"))
    npc_data["npcs"] = npcs
    NPCS_JSON.write_text(
        json.dumps(npc_data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print("=== Portrait ingest report ===")
    for line in report:
        print(line)
    print(f"\nTotal: {ok}/{len(npcs)} portraits on disk | Missing: {missing}")
    print(f"Updated {NPCS_JSON.relative_to(ROOT)} + {ASSET_BG_JSON.relative_to(ROOT)}")


if __name__ == "__main__":
    main()