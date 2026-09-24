#!/usr/bin/env python3
"""剧情数据静态校验：news.json / scenes.json effects / npcs.json。
起因：序章 effects 里的 sea_tendency / scholar_tendency 曾在 Main.apply_effects 里无分支，
静默丢弃了两年。此脚本把「数据里写了的效果键，代码必须接住」做成门禁。"""
import json, os, re, sys, pathlib

ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
FAIL = []


def load(n):
    with open(os.path.join(ROOT, "data", n), encoding="utf-8") as f:
        return json.load(f)


def check(cond, msg):
    if not cond:
        FAIL.append(msg)


# ── apply_effects 实际接住的键 ─────────────────────────
main_src = open(os.path.join(ROOT, "scripts", "Main.gd"), encoding="utf-8").read()
m = re.search(r"func apply_effects\(.*?\n(?=\nfunc |\Z)", main_src, re.S)
check(m is not None, "Main.gd 缺 apply_effects")
handled = set()
if m:
    for arm in re.findall(r'^\s*((?:"[a-z_]+"\s*,\s*)*"[a-z_]+"):\s*$', m.group(0), re.M):
        handled |= set(re.findall(r'"([a-z_]+)"', arm))
check(len(handled) >= 5, f"apply_effects 只接住 {sorted(handled)}，疑似解析失败")

# ── scenes.json：所有 effects 键必须被接住 ────────────
scenes = load("scenes.json")["scenes"]
ids = [s["id"] for s in scenes]
check(len(ids) == len(set(ids)), "scenes.json 场景 id 重复")
idset = set(ids)
ports_all = load("ports.json")["ports"]
port_ids = {p["id"] for p in ports_all}
port_unlock = {p["id"]: int(str(p.get("unlock", "ch1"))[2:] or 1) for p in ports_all}
# Main.FACILITY_SUFFIXES 的镜像：xxx_market 等由 Main 动态生成
fac_m = re.search(r'const FACILITY_SUFFIXES := \[(.*?)\]', main_src, re.S)
FACILITY_SUFFIXES = tuple(re.findall(r'"(_[a-z]+)"', fac_m.group(1))) if fac_m else ()
check(len(FACILITY_SUFFIXES) >= 4, "Main.FACILITY_SUFFIXES 解析失败")
placeholder_m = re.search(r'const FACILITY_PLACEHOLDER := \{(.*?)\n\}', main_src, re.S)
PLACEHOLDERS = set(re.findall(r'^\t"([a-z_]+)":', placeholder_m.group(1), re.M)) if placeholder_m else set()


def next_resolves(nxt: str) -> bool:
    """Main.load_scene 的解析顺序：设施后缀 → scenes.json → ports.json → 占位页。
    起始场景以外，任何 next 都必须落到这四类之一，否则真机是「区域施工中」。"""
    if nxt in idset or nxt in port_ids or nxt in PLACEHOLDERS:
        return True
    for suf in FACILITY_SUFFIXES:
        if nxt.endswith(suf) and nxt[: -len(suf)] in port_ids | idset:
            return True
    return False


for s in scenes:
    for c in s.get("choices", []):
        for k in c.get("effects", {}):
            check(k in handled, f"scenes.json {s['id']} 效果键 `{k}` 未被 Main.apply_effects 处理")
        nxt = c.get("next", "")
        if nxt:
            check(next_resolves(nxt), f"scenes.json {s['id']} 跳转到无法解析的 `{nxt}`（不在 scenes/ports/设施/占位任何一类）")

# 2026-09-14 审计 P0：剧情幕 id 与港口 id 同名却不是 type=port 时，海图抵港 load_scene 命中剧情表、
# 走调查页而不调 _on_enter_port，visited_ports 永不记录——章节 must_visit 在真机上不可完成。
# 七道门禁对此全盲（simulate_run 自管 visited）。此处把「同名必是港」做成静态门禁。
for s in scenes:
    if s["id"] in port_ids:
        check(s.get("type") == "port",
              f"scenes.json `{s['id']}` 与 ports.json 港口同名但 type={s.get('type')!r}——抵港会被调查页吞掉，"
              f"visited_ports 不记录；剧情幕请改独立 id（如 {s['id']}_survey）")

# ── chapters.json：must_visit 港必须存在且本章就能到 ──
chapters = load("chapters.json")["chapters"]
for ch in chapters:
    cid = int(ch["id"])
    req = ch.get("next_requires") or {}
    for pid in req.get("must_visit", []):
        check(pid in port_ids, f"chapters {cid} must_visit `{pid}` 不在 ports.json")
        if pid in port_ids:
            check(port_unlock[pid] <= cid,
                  f"chapters {cid} must_visit `{pid}` 要到第 {port_unlock[pid]} 章才解锁，本章永远晋升不了")
    need = int(req.get("visited_count", 0))
    reachable = sum(1 for p in port_ids if port_unlock[p] <= cid)
    check(need <= reachable, f"chapters {cid} visited_count={need} 超过本章可达港口数 {reachable}")

# ── news.json ─────────────────────────────────────────
news = load("news.json")["news"]
nids = [n.get("id", "") for n in news]
check(all(nids), "news.json 有条目缺 id")
check(len(nids) == len(set(nids)), "news.json id 重复")
DATE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
ALLOWED = {"id", "date", "speaker", "text", "text_S", "text_M", "only", "flag"}
IDENTITIES = {"scholar", "merchant", "hometown"}
for n in news:
    nid = n.get("id", "?")
    check(DATE.match(str(n.get("date", ""))) is not None, f"news {nid} date 须为 YYYY-MM")
    check("speaker" in n, f"news {nid} 缺 speaker（可为空串）")
    has_text = "text" in n or ("text_S" in n and "text_M" in n)
    check(has_text, f"news {nid} 须有 text，或同时有 text_S 与 text_M")
    extra = set(n) - ALLOWED
    check(not extra, f"news {nid} 含未被消费的字段 {sorted(extra)}（反模式：数据写了代码不读）")
    for f in ("text", "text_S", "text_M"):
        for tok in re.findall(r"\{([a-z_]+)\}", str(n.get(f, ""))):
            check(tok in ("target_name", "player_name"), f"news {nid}.{f} 未知占位符 {{{tok}}}（GameState.news_text 只替换 target_name/player_name）")
    if "only" in n:
        check(n["only"] in IDENTITIES, f"news {nid} only=`{n['only']}` 不是合法身份 {sorted(IDENTITIES)}")
        check(str(n.get("date", "")) > "1268-04", f"news {nid} 带 only 但日期早于 1268-04 殿试结算，那时 identity 还是 undecided，永远发不出去")
    y = int(str(n.get("date", "0000"))[:4] or 0)
    check(1255 <= y <= 1279, f"news {nid} 年份 {y} 超出 1255–1279")

# 1268 结算月之前不得出现任何依赖 identity 锁定的措辞（S/M 双版允许，按倾向选）
# 这里只保证 1268-04 那个月本身没有新闻抢在结算前投放
check(not any(n.get("date") == "1268-04" for n in news), "news.json 不得在 1268-04 投放（与殿试结算同月）")

# ── npcs.json ─────────────────────────────────────────
npcs = load("npcs.json")["npcs"]
pids = [p["id"] for p in npcs]
check(len(pids) == len(set(pids)), "npcs.json id 重复")
for p in npcs:
    check(p.get("name") and p.get("role") and p.get("function"), f"npcs {p.get('id')} 缺 name/role/function")

# ── ports.json war 表 ─────────────────────────────────
econ = open(os.path.join(ROOT, "scripts", "core", "Economy.gd"), encoding="utf-8").read()
ws = re.search(r'const WAR_STATUSES := \[(.*?)\]', econ, re.S)
statuses = set(re.findall(r'"([a-z]+)"', ws.group(1))) if ws else set()
check(len(statuses) >= 4, "Economy.WAR_STATUSES 解析失败")
for tbl in ("WAR_LABEL", "WAR_TARIFF", "WAR_INSPECTION"):
    m2 = re.search(r'const %s := \{(.*?)\}' % tbl, econ, re.S)
    keys = set(re.findall(r'"([a-z]+)":', m2.group(1))) if m2 else set()
    check(keys == statuses, f"Economy.{tbl} 键 {sorted(keys)} 与 WAR_STATUSES {sorted(statuses)} 不一致")
ports = load("ports.json")["ports"]
war_ports = 0
for p in ports:
    war = p.get("war")
    if war is None:
        continue
    war_ports += 1
    pid = p["id"]
    check(isinstance(war, dict) and war, f"ports {pid} war 须为非空对象")
    prev = ""
    for ym in war:
        check(DATE.match(ym) is not None, f"ports {pid} war 日期 `{ym}` 须为 YYYY-MM")
        check(war[ym] in statuses, f"ports {pid} war[{ym}]=`{war[ym]}` 不在 {sorted(statuses)}")
        check(1273 <= int(ym[:4]) <= 1279, f"ports {pid} war[{ym}] 年份超出 1273–1279")
    seq = list(war.items())
    for a, b in zip(seq, seq[1:]):
        check(a[0] < b[0], f"ports {pid} war 日期须升序：{a[0]} → {b[0]}")
        check(a[1] != b[1], f"ports {pid} war 相邻状态重复：{a[0]}/{b[0]} 都是 {a[1]}")
check(war_ports >= 8, f"ports.json 只有 {war_ports} 港有 war 表，1276 年闽粤沿海不应如此安静")
# 兴化 / 兴化海口是同一座城的两个节点，战况必须同步
xh = next((p for p in ports if p["id"] == "xinghua"), {}).get("war")
xhh = next((p for p in ports if p["id"] == "xinghua_harbor"), {}).get("war")
check(xh == xhh, "xinghua 与 xinghua_harbor 的 war 表须一致")

# ── 守城卡路由完整 ─────────────────────────────────────
card_ids = set(re.findall(r'const (CARD_SIEGE_\w+) := "(\w+)"', main_src))
routed = set(re.findall(r'^\t\t(CARD_SIEGE_\w+):', main_src, re.M))
declared = {c[0] for c in card_ids}
check(declared, "Main.gd 未声明守城卡常量")
check(declared == routed, f"守城卡常量与 _on_siege_card 分支不一致：仅声明 {sorted(declared-routed)} 仅路由 {sorted(routed-declared)}")
for _n, v in card_ids:
    check(v.startswith("siege_"), f"守城卡 id `{v}` 须以 siege_ 开头（_on_facility_pressed 按前缀路由）")

# ── identity 三值都要可达且有归宿 ──────────────────────
gs_src = open(os.path.join(ROOT, "scripts", "GameState.gd"), encoding="utf-8").read()
assigned = set(re.findall(r'identity = "(\w+)"', gs_src))
check(IDENTITIES <= assigned, f"GameState 未赋值的身份：{sorted(IDENTITIES - assigned)}（死分支）")
# 每个身份在 Main 里都要有至少一处收束（结局卡 / 结局判定 / 等价旗标）
# scholar 的收束走 renamed_wenlong 旗标（守城与「未归」），不走 identity 比较
IDENT_MARKERS = {
    "scholar":  ['identity == "scholar"', 'has_flag("renamed_wenlong")'],
    "merchant": ['identity == "merchant"', 'identity != "scholar"'],
    "hometown": ['identity == "hometown"', 'identity != "scholar"'],
}
for ident in sorted(IDENTITIES):
    markers = IDENT_MARKERS.get(ident, [f'identity == "{ident}"'])
    check(any(mk in main_src for mk in markers),
          f"身份 {ident} 在 Main.gd 无任何收束分支（找过：{markers}）")

# ── GameState 存档字段对称 ─────────────────────────────
gs = open(os.path.join(ROOT, "scripts", "GameState.gd"), encoding="utf-8").read()
to_d = re.search(r"func to_dict\(\).*?\n\treturn \{(.*?)\n\t\}", gs, re.S)
from_d = re.search(r"func from_dict\(d: Dictionary\).*?(?=\n\nfunc |\Z)", gs, re.S)
if to_d and from_d:
    saved = set(re.findall(r'"([a-z_]+)":', to_d.group(1)))
    loaded = set(re.findall(r'(?<![A-Za-z_])d\.get\("([a-z_]+)"', from_d.group(0)))  # 只认 d.get，不把 saved.get 当成 d.get
    check(saved == loaded, f"GameState to_dict/from_dict 字段不对称：仅存 {sorted(saved-loaded)} 仅读 {sorted(loaded-saved)}")
else:
    check(False, "GameState.gd 未找到 to_dict/from_dict")

print("=" * 68)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print(f"scenes {len(scenes)} · news {len(news)} · npcs {len(npcs)} · war 港 {war_ports} · apply_effects 接住 {sorted(handled)}")
print("结果：全部通过")
