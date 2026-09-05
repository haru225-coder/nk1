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
for s in scenes:
    for c in s.get("choices", []):
        for k in c.get("effects", {}):
            check(k in handled, f"scenes.json {s['id']} 效果键 `{k}` 未被 Main.apply_effects 处理")
        nxt = c.get("next", "")
        # 设施 id（xxx_market 等）与港口 id 由 Main 动态生成，这里只校验 cg_/chapter 类硬跳转
        if nxt.startswith(("cg_", "chapter", "sea_path", "scholar_path", "letter_", "gate_")):
            check(nxt in idset, f"scenes.json {s['id']} 跳转到不存在的 `{nxt}`")

# ── news.json ─────────────────────────────────────────
news = load("news.json")["news"]
nids = [n.get("id", "") for n in news]
check(all(nids), "news.json 有条目缺 id")
check(len(nids) == len(set(nids)), "news.json id 重复")
DATE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
ALLOWED = {"id", "date", "speaker", "text", "text_S", "text_M"}
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

# ── GameState 存档字段对称 ─────────────────────────────
gs = open(os.path.join(ROOT, "scripts", "GameState.gd"), encoding="utf-8").read()
to_d = re.search(r"func to_dict\(\).*?\n\treturn \{(.*?)\n\t\}", gs, re.S)
from_d = re.search(r"func from_dict\(d: Dictionary\).*?(?=\n\nfunc |\Z)", gs, re.S)
if to_d and from_d:
    saved = set(re.findall(r'"([a-z_]+)":', to_d.group(1)))
    loaded = set(re.findall(r'd\.get\("([a-z_]+)"', from_d.group(0)))
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
