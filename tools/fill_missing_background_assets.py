#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SCENE_PATHS = [ROOT / "data" / "scenes.json", *sorted((ROOT / "data" / "scenes").glob("*.json"))]
TARGET_SIZE = (1920, 1080)


def walk_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from walk_strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from walk_strings(item)


def missing_asset_uris(refresh_generated: bool = True) -> list[str]:
    uris: set[str] = set()
    for path in SCENE_PATHS:
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        for text in walk_strings(data):
            if text.startswith("res://assets/"):
                rel = text.removeprefix("res://")
                target = ROOT / rel
                is_generated_bg = target.name.startswith("bg_") and target.suffix.lower() == ".png"
                needs_refresh = refresh_generated and is_generated_bg and target.exists() and not Path(str(target) + ".import").exists()
                if not target.exists() or needs_refresh:
                    uris.add(text)
    return sorted(uris)


def existing_image(path: Path) -> bool:
    return path.suffix.lower() in {".png", ".jpg", ".jpeg"} and path.exists()


def pool_images(port: str) -> list[Path]:
    pool = ASSETS / "port_pools" / port
    if not pool.is_dir():
        return []
    return [p for p in sorted(pool.iterdir()) if p.suffix.lower() in {".png", ".jpg", ".jpeg"}]


def seed_index(name: str, count: int) -> int:
    digest = hashlib.sha1(name.encode("utf-8")).digest()
    return int.from_bytes(digest[:2], "big") % count


def candidates_for(uri: str) -> list[Path]:
    name = Path(uri).name
    stem = Path(uri).stem
    parts = stem.split("_")
    port = parts[1] if len(parts) > 1 else ""
    role = parts[-1] if len(parts) > 2 else "port"

    role_fallbacks = {
        "tavern": ["bg_quanzhou_arab_market.png", "bg_xinghua_tavern.png"],
        "market": ["bg_city_market_street.png", "bg_quanzhou_arab_market.png"],
        "wharf": ["bg_departure.png", "bg_sea_route_koei.png"],
        "pier": ["bg_departure.png", "bg_sea_route_koei.png"],
        "hut": ["bg_xinghua_residence.png", "bg_champa_port.png"],
        "shack": ["bg_xinghua_residence.png", "bg_ganpu_port.png"],
        "temple": ["bg_temple_gate.jpg", "bg_arab_mosque.jpg"],
        "mosque": ["bg_arab_mosque.jpg", "bg_temple_gate.jpg"],
        "lookout": ["bg_beacon_tower_koei.png", "bg_sea_route_koei.png"],
        "anchor": ["bg_sea_route_koei.png", "bg_departure.png"],
        "salt": ["bg_ganpu_port.png", "bg_city_market_street.png"],
        "smuggler": ["bg_quanzhou_harbor_koei.png", "bg_sea_route_fog.png"],
        "den": ["bg_quanzhou_arab_market.png", "bg_zhangzhou_port.png"],
    }
    role_first = {
        "tavern",
        "market",
        "hut",
        "shack",
        "temple",
        "mosque",
        "lookout",
        "anchor",
        "salt",
        "smuggler",
        "den",
    }
    port_first = {"map", "port", "wharf", "pier"}

    candidates: list[Path] = []

    def add_role_fallbacks() -> None:
        for fallback in role_fallbacks.get(role, []):
            p = ASSETS / fallback
            if existing_image(p):
                candidates.append(p)

    def add_port_fallbacks() -> None:
        for pattern in [
        f"bg_{port}_port.png",
        f"bg_{port}_port.jpg",
        f"bg_{port}_harbor_koei.png",
        f"bg_{port}_harbor.jpg",
        ]:
            p = ASSETS / pattern
            if existing_image(p):
                candidates.append(p)

    def add_pool_fallback() -> None:
        pool = pool_images(port)
        if pool:
            candidates.append(pool[seed_index(role, len(pool))])

    if role in role_first:
        add_role_fallbacks()
        add_port_fallbacks()
        add_pool_fallback()
    elif role in port_first:
        add_port_fallbacks()
        add_pool_fallback()
        add_role_fallbacks()
    else:
        add_pool_fallback()
        add_port_fallbacks()
        add_role_fallbacks()

    generic = ASSETS / "bg_quanzhou_harbor_koei.png"
    if existing_image(generic):
        candidates.append(generic)
    return candidates


def crop_cover(image: Image.Image) -> Image.Image:
    image = image.convert("RGB")
    src_w, src_h = image.size
    dst_w, dst_h = TARGET_SIZE
    scale = max(dst_w / src_w, dst_h / src_h)
    resized = image.resize((round(src_w * scale), round(src_h * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - dst_w) // 2
    top = (resized.height - dst_h) // 2
    return resized.crop((left, top, left + dst_w, top + dst_h))


def transform(image: Image.Image, uri: str) -> Image.Image:
    digest = hashlib.sha1(uri.encode("utf-8")).digest()
    brightness = 0.92 + digest[0] / 255 * 0.18
    contrast = 0.95 + digest[1] / 255 * 0.14
    color = 0.92 + digest[2] / 255 * 0.16
    image = ImageEnhance.Brightness(image).enhance(brightness)
    image = ImageEnhance.Contrast(image).enhance(contrast)
    image = ImageEnhance.Color(image).enhance(color)
    if digest[3] % 5 == 0:
        image = image.filter(ImageFilter.GaussianBlur(radius=0.35))
    return image


def save_image(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() in {".jpg", ".jpeg"}:
        image.save(path, quality=92, optimize=True)
    else:
        image.save(path, optimize=True)


def main() -> int:
    made: list[str] = []
    skipped: list[str] = []
    for uri in missing_asset_uris():
        out = ROOT / uri.removeprefix("res://")
        candidates = [p for p in candidates_for(uri) if p.resolve() != out.resolve()]
        if not candidates:
            skipped.append(uri)
            continue
        source = candidates[0]
        image = transform(crop_cover(Image.open(source)), uri)
        save_image(image, out)
        made.append(f"{uri} <- {source.relative_to(ROOT)}")

    print(f"generated {len(made)} asset(s)")
    for line in made:
        print(line)
    if skipped:
        print(f"skipped {len(skipped)} asset(s)")
        for line in skipped:
            print(line)
    return 1 if skipped else 0


if __name__ == "__main__":
    raise SystemExit(main())
