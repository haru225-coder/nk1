#!/usr/bin/env python3
"""Extract KOEI G1T texture archives from a Taiko5 DX install."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME = Path("/mnt/c/Program Files/Taiko.Risshiden.V.DX.v1.2.1-GoldBerg")
DEFAULT_OUT = ROOT / "assets" / "_taiko5_ref" / "g1t"

# High-signal packs for nk1 UI/map study (not the 4GB PBBATTLE dump).
PRESETS: dict[str, list[str]] = {
    "ui": [
        "data/UI/UI_COMMON_MSGWIN.G1T",
        "data/UI/UI_COMMON_ICONS.G1T",
        "data/UI/UI_COMMON_CURSOR.G1T",
        "data/UI/UI_COMMON_KEYGUIDE.G1T",
        "data/UI/UI_COMMON_STAWIN.G1T",
        "data/UI/UI_MAP_MMAP.G1T",
        "data/CMENU/INITBG.G1T",
        "data/CMENU/INITBK.G1T",
        "data/CMENU/INITFUDA.G1T",
    ],
    "map": [
        "data/JP/NANKAIMAP.G1T",
        "data/JP/JAPANMAP.G1T",
        "data/JP/JAPANMMAP.G1T",
        "data/BASE/JMAPKYOTEN.G1T",
        "data/BASE/LOADING.G1T",
    ],
    "item": [
        "data/ITEM.G1T",
        "data/FUDA.G1T",
        "data/TRITEM.G1T",
        "data/INFPOW.G1T",
    ],
}


def _decode_bc(raw: bytes, comp: int, width: int, height: int) -> bytes:
    try:
        import texture2ddecoder as t2d
    except ImportError as exc:
        raise SystemExit(
            "texture2ddecoder is required. Create a venv and pip install texture2ddecoder pillow."
        ) from exc

    if comp in (0x59, 0x06):
        return t2d.decode_bc1(raw, width, height)
    if comp in (0x5B, 0x08):
        return t2d.decode_bc3(raw, width, height)
    if comp in (0x01, 0x02):
        return raw[: width * height * 4]
    raise ValueError(f"unsupported compression 0x{comp:02X}")


def _parse_g1t(data: bytes) -> list[dict]:
    if data[:4] != b"GT1G":
        raise ValueError("not a GT1G archive")

    version = data[4:8].decode("ascii", "replace")
    _, table_addr, tex_count = struct.unpack_from("<3I", data, 8)
    offsets = struct.unpack_from(f"<{tex_count}I", data, 28 + 4 * tex_count)

    textures: list[dict] = []
    for index, rel_off in enumerate(offsets):
        off = table_addr + rel_off
        comp = data[off + 1]
        dims = struct.unpack_from("<h", data, off + 2)[0]
        width = 2 ** (dims & 0xF)
        height = 2 ** (dims >> 4)
        flags = struct.unpack_from("<I", data, off + 4)[0]
        pos = off + 8 + (12 if (flags >> 24) == 0x10 else 0)

        if comp in (0x59, 0x06):
            size = width * height // 2
        elif comp in (0x5B, 0x08):
            size = width * height
        elif comp in (0x01, 0x02):
            size = width * height * 4
        else:
            continue

        textures.append(
            {
                "index": index,
                "version": version,
                "width": width,
                "height": height,
                "comp": comp,
                "rgba": _decode_bc(data[pos : pos + size], comp, width, height),
            }
        )
    return textures


def extract_archive(src: Path, out_dir: Path) -> int:
    try:
        from PIL import Image
    except ImportError as exc:
        raise SystemExit("pillow is required for PNG export") from exc

    textures = _parse_g1t(src.read_bytes())
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = src.stem.lower()
    for tex in textures:
        img = Image.frombytes("RGBA", (tex["width"], tex["height"]), tex["rgba"])
        name = f"{stem}_{tex['index']:03d}_{tex['width']}x{tex['height']}.png"
        img.save(out_dir / name)
    return len(textures)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME, help="Taiko5 DX install root")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="PNG output directory")
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        action="append",
        help="Extract a curated pack (ui/map/item). Repeatable.",
    )
    parser.add_argument("paths", nargs="*", help="Relative paths under game root")
    args = parser.parse_args()

    rel_paths: list[str] = []
    if args.preset:
        for preset in args.preset:
            rel_paths.extend(PRESETS[preset])
    rel_paths.extend(args.paths)

    if not rel_paths:
        rel_paths = PRESETS["ui"] + PRESETS["map"]

    game = args.game
    if not game.exists():
        raise SystemExit(f"game path not found: {game}")

    total = 0
    for rel in rel_paths:
        src = game / rel
        if not src.exists():
            print(f"skip missing {rel}", file=sys.stderr)
            continue
        bucket = args.out / Path(rel).parent.name.lower()
        try:
            count = extract_archive(src, bucket)
        except ValueError as exc:
            print(f"skip {rel}: {exc}", file=sys.stderr)
            continue
        print(f"{rel}: {count} textures -> {bucket}")
        total += count

    print(f"done, {total} textures")


if __name__ == "__main__":
    main()