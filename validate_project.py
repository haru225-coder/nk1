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

NAVIGATION_HOOK_SCENE = "scene03b_navigation_line_hook"
NAVIGATION_HOOK_NEXT = "scene04_departure"
NAVIGATION_PATH_FLAGS = {
    "nav_path_sea_merchant": "海商",
    "nav_path_private_fleet": "私人舰队",
    "nav_path_trade_merchant": "贸易商人",
    "nav_path_crewman": "船员",
}


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

    check_navigation_hook(scenes_by_id)


def story_flags_from_effects(effects: object) -> set[str]:
    flags: set[str] = set()
    if not isinstance(effects, dict):
        return flags
    for key in ("story_flag", "story_flag2", "story_flag3"):
        raw = effects.get(key)
        if isinstance(raw, str) and raw:
            flags.add(raw)
        elif isinstance(raw, dict):
            flags.update(str(flag) for flag, enabled in raw.items() if enabled)
        elif isinstance(raw, list):
            flags.update(str(flag) for flag in raw if str(flag))
    return flags


def check_navigation_hook(scenes_by_id: dict[str, dict]) -> None:
    lin_ship = scenes_by_id.get("scene03_lin_ship")
    if not isinstance(lin_ship, dict):
        return

    lin_choices = [choice for choice in lin_ship.get("choices", []) if isinstance(choice, dict)]
    if not lin_choices:
        errors.append("navigation hook: scene03_lin_ship has no choices")
    for choice in lin_choices:
        if str(choice.get("next", "")) != NAVIGATION_HOOK_SCENE:
            errors.append(
                "navigation hook: scene03_lin_ship choice "
                f"'{choice.get('label', '')}' must route to {NAVIGATION_HOOK_SCENE}"
            )

    hook = scenes_by_id.get(NAVIGATION_HOOK_SCENE)
    if not isinstance(hook, dict):
        errors.append(f"navigation hook: missing scene '{NAVIGATION_HOOK_SCENE}'")
        return

    hook_choices = [choice for choice in hook.get("choices", []) if isinstance(choice, dict)]
    if len(hook_choices) != len(NAVIGATION_PATH_FLAGS):
        errors.append(
            f"navigation hook: {NAVIGATION_HOOK_SCENE} must expose "
            f"{len(NAVIGATION_PATH_FLAGS)} identity choices"
        )

    flags_by_choice: dict[str, dict] = {}
    for choice in hook_choices:
        if str(choice.get("next", "")) != NAVIGATION_HOOK_NEXT:
            errors.append(
                "navigation hook: identity choice "
                f"'{choice.get('label', '')}' must route to {NAVIGATION_HOOK_NEXT}"
            )
        for flag in story_flags_from_effects(choice.get("effects", {})):
            if flag in NAVIGATION_PATH_FLAGS:
                flags_by_choice[flag] = choice

    for flag, label_part in NAVIGATION_PATH_FLAGS.items():
        choice = flags_by_choice.get(flag)
        if choice is None:
            errors.append(f"navigation hook: missing identity flag '{flag}'")
            continue
        if label_part not in str(choice.get("label", "")):
            errors.append(
                f"navigation hook: choice for '{flag}' must include label text '{label_part}'"
            )

    departure = scenes_by_id.get(NAVIGATION_HOOK_NEXT)
    if not isinstance(departure, dict):
        return
    inv_flags = {
        str(inv.get("requires_story_flag", ""))
        for inv in departure.get("investigations", [])
        if isinstance(inv, dict)
    }
    for flag in NAVIGATION_PATH_FLAGS:
        if flag not in inv_flags:
            errors.append(
                f"navigation hook: {NAVIGATION_HOOK_NEXT} missing route investigation for '{flag}'"
            )


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
