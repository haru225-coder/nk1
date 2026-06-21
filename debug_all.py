#!/usr/bin/env python3
"""Full-project static debug checks for 南海立志传."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RES_RE = re.compile(r'(?:preload|load)\(\s*"(res://[^"]+)"\s*\)')
PATH_RE = re.compile(r'res://[A-Za-z0-9_./-]+')

errors: list[str] = []
warnings: list[str] = []


def res_to_path(uri: str) -> Path:
    return ROOT / uri.removeprefix("res://")


def check_json_data() -> None:
    scenes_path = ROOT / "data/scenes.json"
    data = json.loads(scenes_path.read_text(encoding="utf-8"))
    scenes = {s["id"]: s for s in data.get("scenes", [])}
    for s_id, scene in scenes.items():
        for c in scene.get("choices", []):
            nxt = c.get("next")
            if nxt and nxt not in scenes and nxt not in ("last_port", "world_map"):
                errors.append(f"scenes.json: {s_id} choice -> missing scene '{nxt}'")
        bg = scene.get("bg", "")
        if bg.startswith("res://") and not res_to_path(bg).exists():
            warnings.append(f"scenes.json: {s_id} missing bg '{bg}'")


def check_res_paths() -> None:
    seen: set[str] = set()
    for gd in ROOT.rglob("*.gd"):
        text = gd.read_text(encoding="utf-8", errors="ignore")
        for uri in set(RES_RE.findall(text)) | set(PATH_RE.findall(text)):
            if not uri.startswith("res://"):
                continue
            if uri in seen:
                continue
            seen.add(uri)
            if uri.endswith("_"):
                continue
            p = res_to_path(uri)
            if not p.exists():
                warnings.append(f"Missing resource: {uri} (from {gd.relative_to(ROOT)})")

    for tscn in ROOT.rglob("*.tscn"):
        text = tscn.read_text(encoding="utf-8", errors="ignore")
        for uri in re.findall(r'path="(res://[^"]+)"', text):
            if not res_to_path(uri).exists():
                warnings.append(f"Missing resource: {uri} (from {tscn.relative_to(ROOT)})")


def check_autoloads() -> None:
    godot = (ROOT / "project.godot").read_text(encoding="utf-8")
    for line in godot.splitlines():
        if '="*res://' in line:
            uri = line.split('="*', 1)[1].strip('"')
            if not res_to_path(uri).exists():
                errors.append(f"Autoload missing: {uri}")


def check_scene_scripts() -> None:
    pairs = [
        ("scenes/Main.tscn", "scripts/Main.gd"),
        ("scenes/DialogueBox.tscn", "scripts/DialogueBox.gd"),
        ("scenes/WorldMap.tscn", "scripts/WorldMap.gd"),
    ]
    for scene_rel, script_rel in pairs:
        scene = (ROOT / scene_rel).read_text(encoding="utf-8")
        if f'path="res://{script_rel}"' not in scene:
            warnings.append(f"{scene_rel} may not reference {script_rel}")


def main() -> int:
    print("=== 南海立志传 debug_all ===\n")
    check_json_data()
    check_autoloads()
    check_res_paths()
    check_scene_scripts()

    if errors:
        print(f"ERRORS ({len(errors)}):")
        for e in errors:
            print(f"  [E] {e}")
        print()

    if warnings:
        print(f"WARNINGS ({len(warnings)}):")
        for w in sorted(set(warnings))[:60]:
            print(f"  [W] {w}")
        if len(set(warnings)) > 60:
            print(f"  ... and {len(set(warnings)) - 60} more")
        print()

    if not errors and not warnings:
        print("All checks passed.")
        return 0
    print(f"Summary: {len(errors)} errors, {len(set(warnings))} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())