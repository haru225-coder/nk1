#!/usr/bin/env python3
"""校验、重命名并入库 NPC 立绘到 assets/portraits/。"""

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

TARGET_W, TARGET_H = 512, 640
PLACEHOLDER_BYTES_MAX = 12_000

NPCS: dict[str, dict[str, str]] = {
    "chen_wenlong": {"name": "陈子龙", "legacy": "avatar_chen.png"},
    "teacher": {"name": "先生", "legacy": "avatar_teacher.png"},
    "jia_disciple": {"name": "贾府门生", "legacy": "avatar_jia.png"},
    "lin_boyuan": {"name": "林伯渊", "legacy": "avatar_lin.png"},
    "abbas": {"name": "阿巴斯", "legacy": "avatar_abbas.png"},
    "customs_official": {"name": "市舶司小吏", "legacy": "avatar_official.png"},
    "ketagalan_elder": {"name": "凯达格兰老人", "legacy": "avatar_elder.png"},
    "ketagalan_child": {"name": "凯达格兰孩子", "legacy": "avatar_child.png"},
}

# loose grok 文件 → npc_id（按画面内容映射）
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


def portrait_filename(npc_id: str) -> str:
    return f"portrait_{npc_id}.png"


def portrait_res_path(npc_id: str) -> str:
    return f"res://assets/portraits/{portrait_filename(npc_id)}"


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
        # 半身立绘：保留上方约 72% 高度，水平居中 88% 宽度
        crop_h = int(h * 0.72)
        crop_w = int(w * 0.88)
        left = (w - crop_w) // 2
        top = int(h * 0.02)
        im = im.crop((left, top, left + crop_w, top + crop_h))
        im = im.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        im.save(dest, "PNG", optimize=True)


def collect_loose_sources() -> dict[str, Path]:
    found: dict[str, Path] = {}
    # 显式映射的 grok 源文件优先于已入库立绘（便于覆盖更新）
    for fname, npc_id in LOOSE_FILE_MAP.items():
        for folder in (ASSETS, INGESTED):
            p = folder / fname
            if p.exists():
                found[npc_id] = p
                break

    for npc_id, meta in NPCS.items():
        if npc_id in found:
            continue
        direct = PORTRAITS / portrait_filename(npc_id)
        for candidate in (
            ASSETS / portrait_filename(npc_id),
            ASSETS / f"portrait_{npc_id}.jpg",
            ASSETS / f"portrait_{npc_id}.png",
            ASSETS / meta["legacy"],
            PLACEHOLDERS / meta["legacy"],
        ):
            if candidate.exists() and not is_placeholder_file(candidate):
                found[npc_id] = candidate
                break
    return found


def update_npcs_json() -> None:
    data = json.loads(NPCS_JSON.read_text(encoding="utf-8"))
    for npc in data.get("npcs", []):
        npc_id = npc.get("id", "")
        if npc_id in NPCS:
            npc["avatar"] = portrait_res_path(npc_id)
    NPCS_JSON.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    PORTRAITS.mkdir(parents=True, exist_ok=True)
    sources = collect_loose_sources()
    report: list[str] = []

    for npc_id, meta in NPCS.items():
        dest = PORTRAITS / portrait_filename(npc_id)
        src = sources.get(npc_id)
        if src and not is_placeholder_file(src):
            normalize_portrait(src, dest)
            report.append(f"OK  {meta['name']} ({npc_id}) <- {src.name}")
            if src.name.startswith("grok-") and src.parent == ASSETS:
                archive = INGESTED / src.name
                archive.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(src), str(archive))
                report.append(f"    archived loose file -> {archive.relative_to(ROOT)}")
        else:
            if dest.exists() and is_placeholder_file(dest):
                dest.unlink()
            legacy = PLACEHOLDERS / meta["legacy"]
            if legacy.exists():
                report.append(
                    f"PLACEHOLDER  {meta['name']} ({npc_id}) — awaiting art; runtime falls back to {meta['legacy']}"
                )
            else:
                report.append(f"MISSING  {meta['name']} ({npc_id})")

    fallback_dest = PORTRAITS / "portrait_fallback.png"
    fallback_src = PLACEHOLDERS / "avatar_fallback.png"
    if fallback_src.exists():
        shutil.copy2(fallback_src, fallback_dest)

    update_npcs_json()

    print("=== Portrait ingest report ===")
    for line in report:
        print(line)
    print(f"\nConfigured paths in {NPCS_JSON.relative_to(ROOT)}")
    real = sum(1 for line in report if line.startswith("OK"))
    ph = sum(1 for line in report if line.startswith("PLACEHOLDER"))
    print(f"Real art: {real}/8 NPCs | Placeholder fallback: {ph}/8")


if __name__ == "__main__":
    main()