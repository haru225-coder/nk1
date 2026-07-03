#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_EXTS = {
    ".cfg",
    ".gd",
    ".godot",
    ".json",
    ".tres",
    ".tscn",
}
SKIP_DIRS = {
    ".agents",
    ".codex",
    ".git",
    ".godot",
    ".venv",
    ".venv-taiko5",
    "__pycache__",
    "references",
}
ASSET_RE = re.compile(r"res://assets/[^\"'`,\s,)\\\]<>]+")
IGNORED_URIS = {
    "res://assets/bg_nonexistent.png",
}


def iter_text_files():
    for current, dirs, files in os.walk(ROOT):
        dirs[:] = [name for name in dirs if name not in SKIP_DIRS]
        base = Path(current)
        for name in files:
            path = base / name
            if path.suffix.lower() in TEXT_EXTS or path.name == "project.godot":
                yield path


def main() -> int:
    refs: list[tuple[str, str]] = []
    for path in iter_text_files():
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for match in ASSET_RE.finditer(text):
            refs.append((str(path.relative_to(ROOT)), match.group(0)))

    missing = sorted(
        {
            (src, uri)
            for src, uri in refs
            if "%" not in uri
            and uri not in IGNORED_URIS
            and not (ROOT / uri.removeprefix("res://")).exists()
        }
    )

    orphan_imports = sorted(
        str(path.relative_to(ROOT))
        for path in (ROOT / "assets").rglob("*.import")
        if not Path(str(path)[:-7]).exists()
    )

    images_without_import = sorted(
        str(path.relative_to(ROOT))
        for path in (ROOT / "assets").rglob("*")
        if path.is_file()
        and path.suffix.lower() in {".png", ".jpg", ".jpeg"}
        and not Path(str(path) + ".import").exists()
    )

    for src, uri in missing:
        print(f"MISSING_REF: {src} -> {uri}")
    for path in orphan_imports:
        print(f"ORPHAN_IMPORT: {path}")
    for path in images_without_import:
        print(f"NO_IMPORT: {path}")

    print(f"asset refs: {len(refs)}")
    print(f"unique asset refs: {len({uri for _, uri in refs})}")
    print(f"missing refs: {len(missing)}")
    print(f"orphan imports: {len(orphan_imports)}")
    print(f"images without import: {len(images_without_import)}")
    return 1 if missing or images_without_import else 0


if __name__ == "__main__":
    sys.exit(main())
