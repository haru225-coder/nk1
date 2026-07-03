#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SCENES_DIR = DATA / "scenes"
FALLBACK_SCENES = DATA / "scenes.json"

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


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"{path.relative_to(ROOT)}: failed to load JSON: {exc}") from exc


def walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def as_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(v) for v in value if str(v)]
    if isinstance(value, str) and value:
        return [value]
    return []


def as_effect_ids(value: Any) -> list[str]:
    if isinstance(value, dict):
        return [str(k) for k in value.keys() if str(k)]
    return as_list(value)


def is_dynamic_scene(target: str) -> bool:
    return target in SPECIAL_TARGETS or target.startswith("city_") or target.endswith(DYNAMIC_SUFFIXES)


def scene_groups() -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    if SCENES_DIR.is_dir():
        modular: list[dict[str, Any]] = []
        for path in sorted(SCENES_DIR.glob("*.json")):
            data = load_json(path)
            modular.extend([s for s in data.get("scenes", []) if isinstance(s, dict)])
        groups["data/scenes/*.json"] = modular

    if FALLBACK_SCENES.exists():
        data = load_json(FALLBACK_SCENES)
        groups["data/scenes.json"] = [s for s in data.get("scenes", []) if isinstance(s, dict)]
    return groups


def collect_action_ids(groups: dict[str, list[dict[str, Any]]]) -> set[str]:
    ids: set[str] = set()
    for scenes in groups.values():
        for scene in scenes:
            for node in walk(scene):
                for key in ("id", "once_flag"):
                    value = str(node.get(key, ""))
                    if value:
                        ids.add(value)
    return ids


def collect_scene_issues(groups: dict[str, list[dict[str, Any]]]) -> list[str]:
    issues: list[str] = []
    for group_name, scenes in groups.items():
        by_id: dict[str, dict[str, Any]] = {}
        seen: set[str] = set()
        for index, scene in enumerate(scenes):
            scene_id = str(scene.get("id", "")).strip()
            if not scene_id:
                issues.append(f"{group_name}: scene index {index} missing id")
                continue
            if scene_id in seen:
                issues.append(f"{group_name}: duplicate scene id '{scene_id}'")
            seen.add(scene_id)
            by_id[scene_id] = scene

        for scene_id, scene in by_id.items():
            for node in walk(scene):
                if "next" not in node:
                    continue
                target = str(node.get("next", "")).strip()
                if not target or target in by_id or is_dynamic_scene(target):
                    continue
                issues.append(f"{group_name}: scene '{scene_id}' points to missing scene '{target}'")
    return sorted(set(issues))


def collect_story_tables() -> tuple[set[str], set[str], set[str], set[str], list[str]]:
    data = load_json(DATA / "story_tables.json") if (DATA / "story_tables.json").exists() else {}
    cards = set((data.get("cards") or {}).keys())
    titles = set((data.get("titles") or {}).keys())
    relationships = set((data.get("relationships") or {}).keys())
    effect_ids: set[str] = set()
    target_issues: list[str] = []

    for node in walk(data):
        node_id = str(node.get("id", ""))
        if node_id:
            effect_ids.add(node_id)
        for key in ("target_action_id", "route_focus_action_id", "focus_action_id"):
            target = str(node.get(key, ""))
            if target:
                target_issues.append(target)
    return cards, titles, relationships, effect_ids, target_issues


def collect_defined_ids(path: Path, root_key: str) -> set[str]:
    if not path.exists():
        return set()
    data = load_json(path)
    values = data.get(root_key, [])
    if isinstance(values, list):
        return {str(item.get("id", "")) for item in values if isinstance(item, dict) and item.get("id")}
    if isinstance(values, dict):
        return set(values.keys())
    return set()


def collect_json_logic() -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    required: dict[str, set[str]] = defaultdict(set)
    produced: dict[str, set[str]] = defaultdict(set)

    for path in sorted(DATA.rglob("*.json")):
        rel = str(path.relative_to(ROOT))
        data = load_json(path)
        for node in walk(data):
            for flag in as_list(node.get("requires_story_flag")):
                required["story_flags"].add(flag)

            for key in ("story_flag2", "story_flag3", "once_flag", "trigger_flag"):
                for flag in as_effect_ids(node.get(key)):
                    produced["story_flags"].add(flag)

            for flag in as_effect_ids(node.get("story_flag")):
                produced["story_flags"].add(flag)

            for flag in as_list(node.get("story_flags_required")):
                required["story_flags"].add(flag)

            for effect_id in as_list(node.get("effects_required")):
                required["effect_ids"].add(effect_id)

            for card_id in as_list(node.get("cards_required")) + as_list(node.get("cards_absent")):
                required["cards"].add(card_id)

            for title_id in as_list(node.get("titles_required")) + as_list(node.get("titles_absent")):
                required["titles"].add(title_id)

            for item_id in as_list(node.get("requires_item")) + as_list(node.get("item_removed")):
                required["items"].add(item_id)

            for item_id in (
                as_list(node.get("item_added"))
                + as_list(node.get("grant_item"))
                + as_list(node.get("item_acquired"))
                + as_list(node.get("acquire_item"))
            ):
                produced["items"].add(item_id)

            for chapter_id in as_list(node.get("chapter_unlock")):
                produced["story_flags"].add("chapter_unlock:" + chapter_id)

            for npc_id in as_list(node.get("relationship_npc_id")) + as_list(node.get("npc_id")) + as_list(node.get("target_npc_id")):
                required["npcs"].add(npc_id)

            if node.get("type") == "set_story_flag":
                for flag in as_list(node.get("key")):
                    produced["story_flags"].add(flag)

            if rel.endswith("story_tables.json"):
                for effect_id in as_list(node.get("id")):
                    produced["effect_ids"].add(effect_id)

    return required, produced


def collect_script_story_flag_producers() -> set[str]:
    flags: set[str] = set()
    pattern = re.compile(r"set_story_flag\(\s*[\"']([^\"']+)[\"']")
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        flags.update(pattern.findall(text))
    return flags


def compare_ids(required: dict[str, set[str]], produced: dict[str, set[str]], action_ids: set[str]) -> list[str]:
    issues: list[str] = []
    cards, titles, relationships, effect_ids, focus_targets = collect_story_tables()
    item_ids = collect_defined_ids(DATA / "items.json", "items")
    npc_ids = collect_defined_ids(DATA / "npcs.json", "npcs")

    all_story_flags = produced["story_flags"] | collect_script_story_flag_producers()
    all_effect_ids = produced["effect_ids"] | effect_ids
    all_npcs = npc_ids | relationships

    for flag in sorted(required["story_flags"] - all_story_flags):
        issues.append(f"required story flag has no producer: {flag}")

    for effect_id in sorted(required["effect_ids"] - all_effect_ids):
        issues.append(f"required unlock/effect id is not defined: {effect_id}")

    for card_id in sorted(required["cards"] - cards):
        issues.append(f"required card id is not defined: {card_id}")

    for title_id in sorted(required["titles"] - titles):
        issues.append(f"required title id is not defined: {title_id}")

    for item_id in sorted(required["items"] - item_ids - produced["items"]):
        issues.append(f"required item id is not defined or produced: {item_id}")

    for npc_id in sorted(required["npcs"] - all_npcs):
        issues.append(f"required npc id is not defined: {npc_id}")

    for target in sorted(set(focus_targets) - action_ids):
        issues.append(f"story table focus action has no matching scene action/once_flag: {target}")

    return issues


def main() -> int:
    groups = scene_groups()
    action_ids = collect_action_ids(groups)
    required, produced = collect_json_logic()

    scene_issues = collect_scene_issues(groups)
    logic_issues = compare_ids(required, produced, action_ids)
    issues = sorted(set(scene_issues + logic_issues))

    for issue in issues:
        print(f"ISSUE: {issue}")

    print(f"scene groups checked: {', '.join(groups.keys())}")
    print(f"scene/action ids checked: {sum(len(v) for v in groups.values())}/{len(action_ids)}")
    print(f"required story flags checked: {len(required['story_flags'])}")
    print(f"required effect ids checked: {len(required['effect_ids'])}")
    print(f"issues: {len(issues)}")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
