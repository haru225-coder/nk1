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
print(f"scenes {len(scenes)} · news {len(news)} · npcs {len(npcs)} · apply_effects 接住 {sorted(handled)}")
print("结果：全部通过")
