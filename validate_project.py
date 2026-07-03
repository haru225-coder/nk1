#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCENE_DIR = ROOT / "data" / "scenes"
SCENE_FALLBACK = ROOT / "data" / "scenes.json"

SPECIAL_TARGETS = {"last_port", "world_map"}
DYNAMIC_SUFFIXES = (
    "_market",
    "_guild",
    "_residence",
    "_inn",
    "_exam",
    "_tavern",
    "_yamen",
    "_shipyard",
    "_temple",
)

errors: list[str] = []
warnings: list[str] = []


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{path.relative_to(ROOT)}: failed to load JSON: {exc}")
        return {}


def load_scene_data() -> dict:
    scenes: list[dict] = []
    if SCENE_DIR.is_dir():
        for path in sorted(SCENE_DIR.glob("*.json")):
            data = load_json(path)
            chunk_scenes = data.get("scenes", [])
            if isinstance(chunk_scenes, list):
                scenes.extend(s for s in chunk_scenes if isinstance(s, dict))
            else:
                errors.append(f"{path.relative_to(ROOT)}: scenes must be a list")
        if scenes:
            return {"start_scene": "cg_title", "scenes": scenes}
    return load_json(SCENE_FALLBACK)


def is_dynamic_scene(target: str) -> bool:
    return target in SPECIAL_TARGETS or target.startswith("city_") or target.endswith(DYNAMIC_SUFFIXES)


def check_scene_target(source_id: str, label: str, target: str, scenes_by_id: dict[str, dict]) -> None:
    if not target or target in scenes_by_id or is_dynamic_scene(target):
        return
    errors.append(f"scene {source_id}: {label} points to missing scene '{target}'")


def check_scenes(data: dict) -> None:
    scenes_by_id: dict[str, dict] = {}
    for index, scene in enumerate(data.get("scenes", [])):
        scene_id = str(scene.get("id", "")).strip()
        if not scene_id:
            errors.append(f"scene index {index}: missing id")
            continue
        if scene_id in scenes_by_id:
            errors.append(f"scene {scene_id}: duplicate id")
        scenes_by_id[scene_id] = scene

    start_scene = str(data.get("start_scene", "cg_title"))
    if start_scene and start_scene not in scenes_by_id:
        errors.append(f"start_scene points to missing scene '{start_scene}'")

    for scene_id, scene in scenes_by_id.items():
        for choice in scene.get("choices", []):
            if isinstance(choice, dict):
                check_scene_target(scene_id, "choice", str(choice.get("next", "")), scenes_by_id)
        for facility in scene.get("facilities", []):
            if isinstance(facility, dict):
                target = str(facility.get("next", facility.get("id", "")))
                check_scene_target(scene_id, "facility", target, scenes_by_id)
        for investigation in scene.get("investigations", []):
            if isinstance(investigation, dict):
                check_scene_target(scene_id, "investigation", str(investigation.get("next", "")), scenes_by_id)
        bg = str(scene.get("bg", ""))
        if bg.startswith("res://") and not res_to_path(bg).exists():
            warnings.append(f"scene {scene_id}: missing bg resource '{bg}'")


def res_to_path(uri: str) -> Path:
    return ROOT / uri.removeprefix("res://")


def check_autoloads() -> None:
    project = ROOT / "project.godot"
    if not project.exists():
        errors.append("project.godot is missing")
        return
    for line in project.read_text(encoding="utf-8", errors="ignore").splitlines():
        match = re.search(r'="\*?(res://[^"]+)"', line)
        if match and not res_to_path(match.group(1)).exists():
            errors.append(f"autoload missing: {match.group(1)}")


def unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def print_items(label: str, items: list[str], limit: int = 40) -> None:
    for item in items[:limit]:
        print(f"{label}: {item}")
    extra = len(items) - limit
    if extra > 0:
        print(f"{label}: ... {extra} more")


def main() -> int:
    data = load_scene_data()
    check_scenes(data)
    check_autoloads()

    deduped_warnings = unique(warnings)
    deduped_errors = unique(errors)
    print_items("WARN", deduped_warnings)
    print_items("ERROR", deduped_errors)

    if deduped_errors:
        print(f"Project validation failed: {len(deduped_errors)} error(s), {len(deduped_warnings)} warning(s).")
        return 1
    print(f"Project validation passed: {len(deduped_warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
