#!/usr/bin/env python3
"""Inventory Taiko5 DX data layout and map it to nk1 P7 patterns."""

from __future__ import annotations

import json
import re
import struct
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME = Path("/mnt/c/Program Files/Taiko.Risshiden.V.DX.v1.2.1-GoldBerg")
OUT_DIR = ROOT / "assets" / "_taiko5_ref"

TS5_LINE_RE = re.compile(rb"\\[%#][0-9A-Fa-f]+")
GBK_RUN_RE = re.compile(rb"[\x80-\xff][\x00-\xff]{3,200}")


def _size_mb(path: Path) -> float:
    return round(path.stat().st_size / (1024 * 1024), 2)


def _scan_extensions(game: Path) -> dict[str, int]:
    counts: Counter[str] = Counter()
    for path in game.rglob("*"):
        if path.is_file():
            counts[path.suffix.lower() or "<noext>"] += 1
    return dict(counts.most_common())


def _probe_g1t(path: Path) -> dict | None:
    data = path.read_bytes()
    if data[:4] != b"GT1G":
        return None
    _, table_addr, tex_count = struct.unpack_from("<3I", data, 8)
    return {
        "path": str(path.relative_to(game_root)),
        "version": data[4:8].decode("ascii", "replace"),
        "textures": tex_count,
        "table_addr": table_addr,
        "size_mb": _size_mb(path),
    }


def _decode_gbk_runs(data: bytes, limit: int = 12) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for match in GBK_RUN_RE.finditer(data):
        try:
            text = match.group(0).decode("gbk")
        except UnicodeDecodeError:
            continue
        if sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff") < 2:
            continue
        text = re.sub(r"\s+", " ", text).strip()
        if len(text) < 4 or text in seen:
            continue
        seen.add(text)
        found.append(text[:160])
        if len(found) >= limit:
            break
    return found


def _probe_ts5(path: Path) -> dict:
    data = path.read_bytes()
    opcodes = Counter(m.group(0).decode("ascii", "ignore") for m in TS5_LINE_RE.finditer(data))
    return {
        "path": str(path.relative_to(game_root)),
        "size": len(data),
        "opcode_top": [k for k, _ in opcodes.most_common(8)],
        "dialogue_samples": _decode_gbk_runs(data, limit=4),
    }


def _probe_msg_dat(path: Path) -> dict:
    data = path.read_bytes()
    entry_count = struct.unpack_from("<I", data, 0)[0]
    return {
        "path": str(path.relative_to(game_root)),
        "size_mb": _size_mb(path),
        "entry_count": entry_count,
        "note": "index table only; strings are encoded (not plain GBK/UTF-16).",
    }


ARCHITECTURE = {
    "layers": [
        {
            "name": "static_tables",
            "formats": ["TR5", "bin"],
            "role": "Init stats, map topology, character work tables, rank gates.",
            "examples": [
                "data/BASE/SPCDINIT.TR5",
                "data/BASE/SBCDINIT.TR5",
                "data/BASE/MAPROUTE.TR5",
                "data/CMENU/CWTDAT_CN.TR5",
                "data/INFPOW.bin",
            ],
        },
        {
            "name": "event_vm",
            "formats": ["TS5", "TE5"],
            "role": "Paired trigger/effect bytecode. Text via \\#ID, logic via \\%opcode.",
            "examples": ["data/EVENT_SC/*.TS5", "data/EVENT_SC/*.TE5", "Evcon/Taiko5DXEvcon.exe"],
        },
        {
            "name": "text_db",
            "formats": ["DAT"],
            "role": "Message lookup table (JP/SC/TW). Event scripts reference IDs, not inline prose.",
            "examples": [
                "data/TAI5MSG_JP.DAT",
                "data/TAI5MSG_SC.DAT",
                "data/TAI5MSG_TW.DAT",
            ],
        },
        {
            "name": "textures",
            "formats": ["G1T", "MRLK", "RGBA8"],
            "role": "UI atlas, maps, bust-ups, item icons.",
            "examples": [
                "data/UI/UI_COMMON_MSGWIN.G1T",
                "data/JP/NANKAIMAP.G1T",
                "data/TDATA/BUSTUP.G1T",
            ],
        },
        {
            "name": "event_catalog",
            "formats": ["dat"],
            "role": "Encrypted event directory consumed by Evcon launcher.",
            "examples": ["Evcon/T5EvDatTbl_chs.dat"],
        },
    ],
    "nk1_copy_map": {
        "do_copy": [
            {
                "taiko5_pattern": "Month tick drives world + deadlines",
                "nk1_target": "P7-T CalendarState.advance_month()",
                "shape": "year/month/day + consume_days() on sail/rest",
            },
            {
                "taiko5_pattern": "Single career score axis (fame/贡献) + tier table",
                "nk1_target": "P7-C data/career.json tiers[].req.fame",
                "shape": "rank 0..N, each tier lists numeric threshold + flags",
            },
            {
                "taiko5_pattern": "Mandate with deadline month + soft penalty",
                "nk1_target": "P7-C CareerState.current_mandate + mandate_expired()",
                "shape": "{id, deadline_months, objective, on_complete, on_fail_effects}",
            },
            {
                "taiko5_pattern": "Script references text DB by ID",
                "nk1_target": "scenes/*.json + TextKeys + DialogueBox",
                "shape": "scene_id -> lines[]; never embed TS5 bytecode",
            },
            {
                "taiko5_pattern": "Calendar event table with priority + condition",
                "nk1_target": "P7-T data/calendar_events.json",
                "shape": "month + condition{flag,rank_gte} + action{scene,effects}",
            },
            {
                "taiko5_pattern": "Apex rank triggers ending evaluation",
                "nk1_target": "P7-E EndingResolver when CareerState.is_apex()",
                "shape": "ending defs with rank_apex + item/relationship gates",
            },
        ],
        "do_not_copy": [
            "TS5/TE5 bytecode VM (\\% / \\# opcodes) — rebuild as JSON scenes",
            "Evcon/T5EvDatTbl encrypted catalog — use nk1 calendar_events.json",
            "MRLK bust-up container — keep AI/generated portraits pipeline",
            "PBBATTLE 4GB battle pack — out of scope for 南海立志传",
        ],
    },
    "scoring_notes": {
        "player_facing_axes": [
            "fame/名声 — promotion threshold (primary '分')",
            "lord trust — mandate success/fail",
            "stats — combat/craft (separate from rank ladder)",
        ],
        "rank_ladder_feel": "Tier titles unlock facilities/mandates; apex rank opens ending fork.",
        "mandate_feel": "Timed objective from lord; miss = penalty, not game over.",
        "why_json_not_tr5": "Taiko5 packs rank gates into TR5 + event VM. nk1 already chose data/career.json + calendar_events.json — same spine, 1% of the bytes.",
    },
}


def build_report(game: Path) -> dict:
    data_root = game / "data"
    g1t_samples = []
    for rel in [
        "COLOR.G1T",
        "ITEM.G1T",
        "UI/UI_COMMON_MSGWIN.G1T",
        "JP/NANKAIMAP.G1T",
        "TDATA/BUSTUP.G1T",
    ]:
        path = data_root / rel
        if path.exists():
            if path.suffix.upper() == ".G1T":
                info = _probe_g1t(path)
                if info:
                    g1t_samples.append(info)
            else:
                g1t_samples.append(
                    {
                        "path": str(path.relative_to(game)),
                        "magic": path.read_bytes()[:4].decode("latin1", "replace"),
                        "size_mb": _size_mb(path),
                    }
                )

    ts5_samples = []
    event_sc = data_root / "EVENT_SC"
    if event_sc.exists():
        for path in sorted(event_sc.glob("*.TS5"))[:6]:
            ts5_samples.append(_probe_ts5(path))

    msg_dats = []
    for name in ("TAI5MSG_JP.DAT", "TAI5MSG_SC.DAT", "TAI5MSG_TW.DAT"):
        path = data_root / name
        if path.exists():
            msg_dats.append(_probe_msg_dat(path))

    folder_sizes = []
    if data_root.exists():
        for child in sorted(data_root.iterdir()):
            if child.is_dir():
                total = sum(f.stat().st_size for f in child.rglob("*") if f.is_file())
                folder_sizes.append(
                    {"path": str(child.relative_to(game)), "size_mb": round(total / (1024 * 1024), 1)}
                )
        folder_sizes.sort(key=lambda x: x["size_mb"], reverse=True)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "game_root": str(game),
        "extension_counts": _scan_extensions(data_root),
        "data_folder_sizes_mb": folder_sizes[:12],
        "g1t_samples": g1t_samples,
        "ts5_samples": ts5_samples,
        "message_dbs": msg_dats,
        "architecture": ARCHITECTURE,
    }


def main() -> None:
    global game_root
    game_root = DEFAULT_GAME
    if not game_root.exists():
        raise SystemExit(f"game path not found: {game_root}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    report = build_report(game_root)
    out_path = OUT_DIR / "architecture_map.json"
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {out_path}")
    print(f"layers: {len(ARCHITECTURE['layers'])}, copy patterns: {len(ARCHITECTURE['nk1_copy_map']['do_copy'])}")


if __name__ == "__main__":
    main()