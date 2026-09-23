#!/usr/bin/env python3
"""P7 剧情闭环的静态门禁。不启动 Godot。

开局链的判定按任务书 §3.1，不按 §8.3 第一句的字面「剩余场必须 legacy」。
序章 cg_* 与两条 path_start 必须留在开局链上，不能标成 legacy。
§8.3 的可执行条件是：开局链不得再走到 monk，其余不可达草稿必须带 legacy 或 deprecated。
"""
import json, os, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
fails = []

def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)

def load_json(rel):
    with open(ROOT / rel, encoding="utf-8") as f:
        return json.load(f)

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")

WHITELIST = {
    "money", "fame", "days", "flag",
    "sea_tendency", "scholar_tendency", "merchant_credit", "network",
    "ledger_note", "supplies", "cargo", "ship", "cargo_loss", "discovery",
}

LEGACY_IDS = [
    "prologue_wine_shed", "prologue_return_home", "prologue_go_quanzhou",
    "chapter1_scholar_wait", "prologue_draft", "prologue_ledger", "prologue_permit",
    "prologue_veteran", "prologue_catalyst", "study_desk", "family_house", "city_gate",
    "harbor_wine_shed", "ferry_jetty", "messenger_post", "customs_shed", "merchant_house",
    "shipyard", "fuzhou_road", "recommendation_letter", "guest_house", "sutra_room",
    "stele_walk", "guest_hall", "reef_sound", "lead_line", "old_berth_note",
    "academy_gate", "paper_shop", "mulan_bei", "yangji_yuan", "customs_room",
    "yahang", "arab_mosque", "beacon_tower", "relay_post", "fuzhou_yamen",
    "city_tavern", "city_residence", "city_shipyard", "city_guild", "sail",
]

EXPECTED_BEATS = [
    {"id": "xinghua_study", "entry": "start", "port": "xinghua", "order": 10,
     "requires": {}, "stop_before": ["monk"]},
    {"id": "quanzhou_monk", "entry": "monk", "port": "quanzhou", "order": 10,
     "requires": {}, "stop_before": ["merchant"]},
    {"id": "quanzhou_merchant", "entry": "merchant", "port": "quanzhou", "order": 20,
     "requires": {"seen": ["monk"]}, "stop_before": ["dock"]},
    {"id": "quanzhou_dock", "entry": "dock", "port": "quanzhou", "order": 30,
     "requires": {"seen": ["merchant"]}, "stop_before": ["prepare"]},
    {"id": "quanzhou_prepare", "entry": "prepare", "port": "quanzhou", "order": 40,
     "requires": {"seen": ["dock"]}, "stop_before": ["sail"]},
    {"id": "ryukyu_reef", "entry": "ryukyu", "port": "ryukyu", "order": 10,
     "requires": {}, "stop_before": ["hakata", "return_quanzhou"]},
    {"id": "hakata_ledger", "entry": "hakata", "port": "hakata", "order": 10,
     "requires": {"has_flag": ["cargo_hakata"]}, "stop_before": ["return_quanzhou"]},
    {"id": "quanzhou_return", "entry": "return_quanzhou", "port": "quanzhou", "order": 50,
     "requires": {"visited": ["ryukyu"]}, "stop_before": ["chapter2_letter"]},
    {"id": "quanzhou_letter", "entry": "chapter2_letter", "port": "quanzhou", "order": 100,
     "requires": {"chapter_at_least": 2}, "stop_before": []},
]

REQUIRE_KEYS = {"chapter_at_least", "visited", "has_flag", "missing_flag", "seen"}

def func_body(src, name):
    m = re.search(rf'^func {name}\b.*?\n(.*?)(?=^func |\Z)', src, re.S | re.M)
    return m.group(1) if m else ""

def match_arms(src):
    body = func_body(src, "apply_effects")
    mm = re.search(r'match key:\n(.*)', body, re.S)
    if not mm:
        return []
    return re.findall(r'^\t\t\t"([a-z_]+)":', mm.group(1), re.M)

def walk_next(by_id, start, stop_ids):
    """沿 choices/investigations 的 next 走。入口即使与港口同 id 也计入，不走进 stop_ids。"""
    seen = set()
    stack = [start]
    while stack:
        cur = stack.pop()
        if cur in seen or cur not in by_id:
            continue
        seen.add(cur)
        scene = by_id[cur]
        nxts = []
        for c in scene.get("choices") or []:
            if c.get("next"):
                nxts.append(c["next"])
        for inv in scene.get("investigations") or []:
            if isinstance(inv, dict) and inv.get("next"):
                nxts.append(inv["next"])
        for nxt in nxts:
            if nxt not in stop_ids and nxt not in seen:
                stack.append(nxt)
    return seen

def effect_keys(scene):
    keys = []
    blobs = []
    for c in scene.get("choices") or []:
        blobs.append(c.get("effects") or {})
    for inv in scene.get("investigations") or []:
        if isinstance(inv, dict):
            blobs.append(inv.get("effects") or {})
    for e in blobs:
        if isinstance(e, dict):
            keys.extend(e.keys())
    return keys

def borrow_ceiling(credit):
    steps = max(-20, min(40, credit))
    return 3000 + steps * 50

def discovery_width(network, strength):
    extra = max(0.0, min(30.0, float(network))) / 30.0 * 0.03
    return 0.03 + extra

def storm_width(strength):
    return 0.06 + 0.06 * strength

print("=" * 68)
print("一、效果白名单")
print("=" * 68)

main = read("scripts/Main.gd")
arms = match_arms(main)
check(set(arms) == WHITELIST, f"apply_effects 的 match 臂等于白名单（实际 {sorted(arms)}）")
check("chapter" not in arms, "apply_effects 不含 chapter 臂")
check(len(arms) == len(set(arms)), "match 臂无重复")

scenes = load_json("data/scenes.json")["scenes"]
by_id = {s["id"]: s for s in scenes}
bad_keys = []
for s in scenes:
    for k in effect_keys(s):
        if k not in WHITELIST:
            bad_keys.append(f"{s['id']}.{k}")
check(not bad_keys, "scenes.json 效果键都在白名单内" + (f"：{bad_keys[:8]}" if bad_keys else ""))

print()
print("=" * 68)
print("二、开局截断与归档场")
print("=" * 68)

ports = {p["id"] for p in load_json("data/ports.json")["ports"]}
# 开局链：从 cg_title 沿 next 走，进了港口就停（港口本身算可达终点）
opening = set()
stack = ["cg_title"]
while stack:
    cur = stack.pop()
    if cur in opening or cur not in by_id:
        continue
    opening.add(cur)
    if cur in ports and cur != "cg_title":
        continue
    scene = by_id[cur]
    for c in scene.get("choices") or []:
        if c.get("next"):
            stack.append(c["next"])
    for inv in scene.get("investigations") or []:
        if isinstance(inv, dict) and inv.get("next"):
            stack.append(inv["next"])

check("monk" not in opening, "开局链不含 monk")
check("sail" not in opening, "开局链不含 sail")
check("quanzhou" in opening and "xinghua" in opening, "开局链落到泉州与兴化")

stray = []
for sid in opening:
    s = by_id[sid]
    if s.get("type") == "port" or s.get("deprecated") or s.get("legacy"):
        continue
    if sid.startswith("cg_") or sid in ("sea_path_start", "scholar_path_start"):
        continue
    stray.append(sid)
check(not stray, "开局链上其余场只有序章 cg_* 与两条 path_start" + (f"：{stray}" if stray else ""))

def only_next(sid):
    choices = by_id[sid].get("choices") or []
    return [c.get("next") for c in choices]

check(only_next("sea_path_start") == ["quanzhou"], "sea_path_start 的 next 是 quanzhou")
check(only_next("scholar_path_start") == ["xinghua"], "scholar_path_start 的 next 是 xinghua")

missing_mark = []
for sid in LEGACY_IDS:
    s = by_id.get(sid)
    if s is None or not (s.get("legacy") or s.get("deprecated")):
        missing_mark.append(sid)
check(not missing_mark, "第 3.3 节名单都带 legacy 或 deprecated" + (f"：{missing_mark}" if missing_mark else ""))

print()
print("=" * 68)
print("三、港口节拍")
print("=" * 68)

beats_doc = load_json("data/port_beats.json")
beats = beats_doc.get("beats", [])
check(beats == EXPECTED_BEATS, "port_beats.json 与任务书第 3.2 节九行一致")
for b in beats:
    check(b["entry"] in by_id, f"节拍入口 {b['entry']} 存在")
    for sid in b["stop_before"]:
        check(sid in by_id, f"{b['id']} 的 stop_before {sid} 存在")
    check(b["port"] in ports, f"{b['id']} 的港口 {b['port']} 存在")
    extra = set(b["requires"]) - REQUIRE_KEYS
    check(not extra, f"{b['id']} 的 requires 只用允许的键" + (f"：{extra}" if extra else ""))

by_beat = {b["id"]: b for b in beats}
check(by_beat.get("hakata_ledger", {}).get("requires") == {"has_flag": ["cargo_hakata"]},
      "hakata_ledger 要求旗标 cargo_hakata")
check(by_beat.get("quanzhou_letter", {}).get("requires", {}).get("chapter_at_least") == 2,
      "quanzhou_letter 的 chapter_at_least 是 2")
check("ryukyu" in by_beat.get("quanzhou_return", {}).get("requires", {}).get("visited", []),
      "quanzhou_return 要求亲至 ryukyu")

# 谈话内页能从入口走到，且不会穿过 stop_before
for b in beats:
    stop = set(b["stop_before"]) | ports
    pages = walk_next(by_id, b["entry"], stop)
    check(b["entry"] in pages, f"{b['id']} 的谈话包含入口")
    leaked = (pages & set(b["stop_before"])) | ((pages & ports) - {b["entry"]})
    check(not leaked, f"{b['id']} 的谈话不包含停止点" + (f"：{sorted(leaked)}" if leaked else ""))

print()
print("=" * 68)
print("四、终局文案")
print("=" * 68)

brief = read("docs/P7-剧情闭环-任务书.md")
fence = re.search(r"```json\n(\"ending\": \{.*?\n\})\n```", brief, re.S)
check(fence is not None, "任务书第 5 节能抽出终局 JSON")
expected_ending = None
if fence:
    expected_ending = json.loads("{" + fence.group(1) + "}")["ending"]

chapters = load_json("data/chapters.json")["chapters"]
final = [c for c in chapters if not c.get("next_requires")]
check(len(final) == 1 and int(final[0]["id"]) == 4, "最终章仍是第四章")
got = final[0].get("ending") if final else None
if expected_ending and isinstance(got, dict):
    for key in ("sea", "scholar", "both"):
        exp = expected_ending[key]["text"].strip()
        act = (got.get(key) or {}).get("text", "")
        act = act.strip() if isinstance(act, str) else ""
        check(exp == act, f"ending.{key}.text 与任务书逐字一致")
    check(got.get("title", "").strip() == expected_ending["title"].strip(),
          "终局总题与任务书一致")
else:
    check(False, "chapters.json 第四章含 ending")

print()
print("=" * 68)
print("五、旅店改写列表")
print("=" * 68)

suf = re.search(r'const FACILITY_SUFFIXES := \[(.*?)\]', main, re.S)
listed = re.search(r'if target_scene in \[(.*?)\]:', main, re.S)
suffixes = re.findall(r'"(_[a-z]+)"', suf.group(1) if suf else "")
rewritten = set(re.findall(r'"(city_[a-z]+)"', listed.group(1) if listed else ""))
expected_ids = {"city_" + s[1:] for s in suffixes}
check(rewritten == expected_ids,
      f"旅店改写列表与 FACILITY_SUFFIXES 集合相等（{sorted(rewritten)}）")
check("city_inn" in rewritten, "改写列表含 city_inn")

print()
print("=" * 68)
print("六、信用与岸影公式")
print("=" * 68)

gs = read("scripts/GameState.gd")
ceiling_body = func_body(gs, "borrow_ceiling")
limit_body = func_body(gs, "borrow_limit")
check("clampi(merchant_credit, -20, 40)" in ceiling_body and "* 50" in ceiling_body
      and "DEBT_CEILING" in ceiling_body,
      "borrow_ceiling 使用 DEBT_CEILING + clampi(merchant_credit, -20, 40) * 50")
check("borrow_ceiling() - debt" in limit_body, "borrow_limit 从天花板减去 debt")
check(borrow_ceiling(0) == 3000, "borrow_ceiling(0) == 3000")
check(borrow_ceiling(40) == 5000, "borrow_ceiling(40) == 5000")
check(borrow_ceiling(-20) == 2000, "borrow_ceiling(-20) == 2000")
check(borrow_ceiling(100) == 5000, "borrow_ceiling(100) == 5000（消费处钳制）")
check(borrow_ceiling(-100) == 2000, "borrow_ceiling(-100) == 2000（消费处钳制）")

voy = read("scripts/core/Voyage.gd")
storm_lines = [ln for ln in voy.splitlines() if "var storm_chance" in ln]
check(len(storm_lines) == 1 and "network" not in storm_lines[0]
      and "0.06 + 0.06 * monsoon_strength" in storm_lines[0],
      "风涛宽度不随 network 变化")
extra_body = func_body(voy, "_discovery_extra")
check("clampf(float(GameState.network), 0.0, 30.0) / 30.0 * 0.03" in extra_body,
      "_discovery_extra 与任务书公式一致")
check("storm_chance + 0.24 + discovery_extra" in voy, "岸影切片加上 discovery_extra")
check(discovery_width(0, 1) == 0.03, "discovery_width(0, 1) == 0.03")
check(abs(discovery_width(30, 1) - 0.06) < 1e-9, "discovery_width(30, 1) == 0.06")
check(discovery_width(-10, 1) == 0.03, "discovery_width(-10, 1) == 0.03")
check(storm_width(1) == 0.12 and storm_width(0) == 0.06, "风涛宽度仍是 0.06–0.12")

print()
print("=" * 68)
print("七、存档字段")
print("=" * 68)

to_dict = func_body(gs, "to_dict")
keys = set(re.findall(r'"([a-z_]+)"\s*:', to_dict))
needed = ["sea_tendency", "scholar_tendency", "merchant_credit", "network",
          "ledger_notes", "seen_scenes"]
missing_keys = [k for k in needed if k not in keys]
check(not missing_keys, "GameState.to_dict 含剧情账字段" + (f"：缺 {missing_keys}" if missing_keys else ""))

print()
print("=" * 68)
if fails:
    print(f"结果：{len(fails)} 项未通过")
    for f in fails:
        print("   ✗", f)
    sys.exit(1)
print("结果：全部通过")
