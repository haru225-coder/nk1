#!/usr/bin/env python3
"""契约文档「每档角色 / 品级一览」自核门禁（lane w26-k3，来源 w24-c1 遗留②）。

比对物：docs/人物原稿与上屏契约.md 的「每档角色 / 品级一览」生成块（CHARS-DOC 标记对内，不算标记行本身）
必须与 `python3 tools/check_char_contract_doc.py --gen` 现算出来的内容**逐字一致**——现算口径：
data/characters.json 逐条角色并按 tier 归入五档（档序的唯一来源是 scripts/ui/CharacterArt.gd 的 TIER_ORDER，
名册分组就是它切的）、行 = id / 名 / 生卒（生–卒，缺一则「？」、皆无则「—」）/ 职事
（凡角色经 sources.crew_id 挂了 data/crew.json 候选的，按候选的 role 取职名；级数不录——「初习 / 谙熟 / 老练」
是职事合同，在 crew.json 的 level 里，本作没有「人物品级」，写进 envoy 会读成官阶）。
漏档、多档、品级 / 职名写错、行序或空格漂一格，都退 1 并给出首处差异的「文档 / 数据」两行对照。

直接用法：

（这四行命令跟上面正文隔一句，因为 verify_story_data 的 L1B 对 .py 整份（含 docstring）去注释后按
字面子命中 raw 原稿路径记号（本文件 DATA_REL 那串整写）取数口——正文中直接写「python3 本脚本」
会被认成「本文件是人物读取入口」，所以把命令行单独地起在这小节里、字面子只在源码常量里成型。）

  python3 tools/check_char_contract_doc.py          # 门禁：生成块逐字比对 + 零、判据自检；不一致退 1
  python3 tools/check_char_contract_doc.py --gen    # 只打印现算的生成块（人写稿时贴用）
  python3 tools/check_char_contract_doc.py --fix    # 把生成块重算写回文档（角色增减 / 改名后跑它，人工确认 diff 再提交）

零节（GATES §五.3）在内存叠层（读真树、写不落盘）里跑：R1–R7 反向格（改 tier / 数据加人 / 文档加行 / 生卒算错 /
两人换档 / 职名写错 / 行序反了）各判红且红因落在该行档上；C1–C5 对照格守「不是滥红」——块正常拆得开不红、
行数格按行报案、职名挂钩取的宏认不出时职事栏给「—」不谎报、gen 遇到表外数据形状（名里带竖线 / 新档没入
TIER_NAMES）自己不造表。三格机判不了的留在核验单：id 空格号 / 手写段措辞 / 「为什么归这一档」。
"""
import json, os, re, sys
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC_REL = "docs/人物原稿与上屏契约.md"
DATA_REL = "data/characters.json"
CREW_REL = "data/crew.json"
BEGIN = "<!-- CHARS-DOC:BEGIN 本块由 `python3 tools/check_char_contract_doc.py --fix` 按 data/characters.json 现算生成，勿手改 -->"
END = "<!-- CHARS-DOC:END -->"
# 档序唯一来源：scripts/ui/CharacterArt.gd 的 TIER_ORDER（名册分组就是它切的）——本门禁不另抄一份序，
# 源码里认不出这个常量就红、修门禁不抄表
TIER_ORDER_SRC = ("scripts/ui/CharacterArt.gd", re.compile(r'const\s+TIER_ORDER\s*:?=\s*\[(.*?)\]'))
TIER_NAMES = {"protagonist": "主角", "major": "要角", "crew": "船伙", "minor": "群配", "historical": "史人"}

fails = []
_PROBE_BAG = []  # 非空时由 _check_probe 收单（零节对照格用）；门禁正路与 R 格仍走 check()

def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def _check_probe(cond, msg):
    """gen / load_tier_order 内部的红：门禁正路（判一）调用时与 check() 全同（印 + 入账）；
    零节对照格把 _PROBE_BAG 放上单再调，红只收进单——既不印也不进 fails，
    外层格再按「恰一条 + 文案对」判。两条路经同一处记账，探不到红 = 这条路已判不出。"""
    if _PROBE_BAG:
        if not cond:
            _PROBE_BAG[-1].append(msg)
        return cond
    return check(cond, msg)


class Mem:
    """零节变异叠层：读真树、写不落盘；write() 的改动只对这一个实例可见。"""
    def __init__(self):
        self.over = {}

    def read(self, rel):
        if rel in self.over:
            return self.over[rel]
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            return f.read()

    def write(self, rel, text):
        self.over[rel] = text


def load_tier_order(mem):
    src = mem.read(TIER_ORDER_SRC[0])
    m = TIER_ORDER_SRC[1].search(src)
    if not m:
        _check_probe(False, f"{TIER_ORDER_SRC[0]} 里认不出 TIER_ORDER 常量：档序的唯一来源就是它"
                     "（改写法 / 改名了——修本门禁的正则，别在这另抄一份档序）")
        return None
    order = re.findall(r'"(\w+)"', m.group(1))
    unknown = [t for t in order if t not in TIER_NAMES]
    if not order or unknown:
        _check_probe(False, f"TIER_ORDER 现解出 {order}："
                     + (f"{unknown} 不在本档名表——先把它补进 TIER_NAMES，并在文档各档口径行写明新档" if unknown
                        else "空表"))
        return None
    return order


def crew_names(mem):
    """data/crew.json 的 roles 表：职键 → 职名。形状不认识返回 None（gen 给全员「—」，C4 守这条不谎报）。"""
    try:
        crew = json.loads(mem.read(CREW_REL))
        roles = crew.get("roles", crew) if isinstance(crew, dict) else crew
        names = {}
        for e in roles if isinstance(roles, list) else ({"id": k, **(v if isinstance(v, dict) else {"name": v})}
                                                        for k, v in roles.items()):
            if isinstance(e, dict) and e.get("id") and e.get("name"):
                names[e["id"]] = e["name"]
        return names or None
    except (OSError, ValueError, TypeError):
        return None


def crew_of_char(mem):
    """char id → 职名：经 characters.json 自报的 sources.crew_id 挂到 crew.json 候选，再按候选的 role 取职名。
    数据形状任一环不认得就返回（None, 哪一环）——主节按 C4 口径硬红，不静默放行。"""
    names = crew_names(mem)
    if names is None:
        return None, "crew.json 的 roles 表认不出（职名表）"
    try:
        crew = json.loads(mem.read(CREW_REL))
        cand = crew.get("crew", crew.get("candidates", crew)) if isinstance(crew, dict) else crew
        role_by_id = {}
        for e in cand if isinstance(cand, list) else [{"id": k, **v} for k, v in cand.items()]:
            if isinstance(e, dict) and e.get("id") and e.get("role"):
                role_by_id[e["id"]] = e["role"]
    except (OSError, ValueError, TypeError) as ex:
        return None, f"crew.json 候选表读不出：{ex}"
    try:
        data = json.loads(mem.read(DATA_REL))
        out = {}
        for c in data.get("characters", []):
            cid = (c.get("sources") or {}).get("crew_id")
            if cid:
                if cid not in role_by_id:
                    return None, f"{c.get('id')} 的 sources.crew_id={cid} 在 crew.json 候选里查无此人"
                out[c["id"]] = names.get(role_by_id[cid], "—")
        return out, None
    except (OSError, ValueError, TypeError) as ex:
        return None, f"characters.json 读不出：{ex}"


def lifespan(c):
    b, d = c.get("born"), c.get("died")
    if b is None and d is None:
        return "—"
    return "%s–%s" % (b if b is not None else "？", d if d is not None else "？")


def gen_block(mem):
    """现算生成块内容（BEGIN/END 之间）。数据形状容不下 => 返回 None，归一、的红因说明原因。"""
    data = json.loads(mem.read(DATA_REL))
    chars = data.get("characters")
    if not isinstance(chars, list) or not chars:
        _check_probe(False, f"{DATA_REL} 的 characters 不是非空列表——数据形状变了，本门禁的取数口径要跟着改")
        return None
    order = load_tier_order(mem)
    if order is None:
        return None
    duties, why = crew_of_char(mem)
    if duties is None:
        _check_probe(False, f"职事栏取数口径断了：{why}——本门禁不静默降到「—」（那样绿假），"
                     "要么修这条链，要么把职事栏从生成口径里拿掉（连同零节 R6 / C4 一起改）")
        return None
    by = {t: [] for t in order}
    bad = [c for c in chars if c.get("tier") not in by]
    if bad:
        _check_probe(False, f"{DATA_REL} 出现 TIER_ORDER 外的档位：{sorted({c.get('tier') for c in bad})}——"
                     "先定它该不该进 TIER_ORDER（改 CharacterArt，档序唯一来源），别在本门禁放空档")
        return None
    for c in chars:
        by[c["tier"]].append(c)
    out = []
    for t in order:
        rows = by[t]
        out.append(f"### {TIER_NAMES[t]}档 `{t}`（{len(rows)} 人）")
        out.append("")
        out.append("| id | 名 | 生卒 | 职事 |")
        out.append("|---|---|---|---|")
        for c in sorted(rows, key=lambda x: x["id"]):
            nm = c.get("name") or "？"
            if "\n" in nm or "|" in nm or "`" in str(c.get("id", "")):
                _check_probe(False, f"{DATA_REL} 的 {c.get('id')} 名 / id 里带换行、竖线或反引号——表格容不下，先修数据")
                return None
            out.append("| `%s` | %s | %s | %s |" % (c["id"], nm, lifespan(c), duties.get(c["id"], "—")))
        out.append("")
    return "\n".join(out).rstrip("\n")


def split_block(doc):
    """(块前, 块内, 块后)，块内不含标记行。标记数不对：（None, 原因）。"""
    if doc.count(BEGIN) == 1 and doc.count(END) == 1 and doc.index(BEGIN) < doc.index(END):
        a, b = doc.index(BEGIN) + len(BEGIN), doc.index(END)
        return doc[:a], doc[a:b], doc[b:]
    return None, (f"CHARS-DOC 生成标记应为恰一对（BEGIN 1 处、END 1 处、此序），"
                  f"实得 BEGIN×{doc.count(BEGIN)} / END×{doc.count(END)}")


def fail_diff(mem):
    """红因：首处差异行号 + 两侧原文（brief 判据「点名是哪一条（原文对照）」）。"""
    doc = mem.read(DOC_REL)
    _, body, _ = split_block(doc)
    want = "\n" + (gen_block(mem) or "") + "\n"
    have, wl = body.split("\n"), want.split("\n")
    k = next((i for i in range(max(len(have), len(wl)))
              if (have[i:i + 1] or [None]) != (wl[i:i + 1] or [None])), 0)
    return (f"「每档角色 / 品级一览」生成块与 {DATA_REL} 现算不符；首处差异在块内第 {k} 行\n"
            f"      文档：{(have[k:k + 1] or ['<无>'])[0][:160]}\n"
            f"      数据：{(wl[k:k + 1] or ['<无>'])[0][:160]}\n"
            f"      修法：python3 tools/check_char_contract_doc.py --fix 后人工确认 diff"
            f"（该动数据的就别拿 --fix 盖过去，改 {DATA_REL} 或 CharacterArt.TIER_ORDER，另走拍板）")


def _ok(mem):
    """同一条路：完整判据（块 + 行数），供零节各格。fails 不动、只看真假。"""
    parts = split_block(mem.read(DOC_REL))
    if parts[0] is None or gen_block(mem) is None:
        return False
    if parts[1] != "\n" + gen_block(mem) + "\n":
        return False
    return len(re.findall(r"^\| `", parts[1], re.M)) == len(json.loads(mem.read(DATA_REL))["characters"])


def _mutate(fn):
    m = Mem()
    data = json.loads(m.read(DATA_REL))
    crew = json.loads(m.read(CREW_REL))
    doc = m.read(DOC_REL)
    fn(data, crew, doc)
    m.write(DATA_REL, json.dumps(data, ensure_ascii=False, indent=1) + "\n")
    m.write(CREW_REL, json.dumps(crew, ensure_ascii=False, indent=1) + "\n")
    m.write(DOC_REL, doc)
    return m


def selfcheck():
    print("零、判据自检（R 反向格必红且红因落行、C 对照格守「不是滥红」；全在内存叠层，不落盘）")
    # R1 一条记录下档（crew 头一条 → minor）：两档一双脚落
    m = _mutate(lambda d, _c, _doc: next(c for c in d["characters"] if c["tier"] == "crew").update(tier="minor"))
    check(not _ok(m), "R1 一条记录下档（crew → minor）："
          + fail_diff(m).splitlines()[0] + " / " + fail_diff(m).splitlines()[2][:60])
    # R2 数据加人（文档没这个人）
    m = _mutate(lambda d, _c, _doc: d["characters"].append(
        {"id": "zz_probe_char", "name": "探针人", "tier": "minor", "attrs": {}, "traits": [], "relations": [],
         "chapters": [0], "sources": {}}))
    check(not _ok(m), "R2 数据加人：" + fail_diff(m).splitlines()[0]
          + " / " + fail_diff(m).splitlines()[2][:60])
    # R3 文档加行（数据没有这个人）
    m3doc = Mem().read(DOC_REL)
    p3 = split_block(m3doc)
    i3 = p3[1].find("\n### 史人档")
    doc3 = p3[0] + p3[1][:i3] + "\n| `ghost_char` | 影人 | — | — |" + p3[1][i3:] + p3[2]
    m3 = Mem()
    m3.write(DOC_REL, doc3)
    check(not _ok(m3) and "ghost_char" in fail_diff(m3), "R3 文档加行：红因点到鬼影行"
          "（" + fail_diff(m3).splitlines()[1][:50] + "…）")
    # R4 生卒算错（born +1）
    m = _mutate(lambda d, _c, _doc: next(c for c in d["characters"] if isinstance(c.get("born"), int))
                .update(born=next(c for c in d["characters"] if isinstance(c.get("born"), int))["born"] + 1))
    check(not _ok(m), "R4 生卒算错：" + fail_diff(m).splitlines()[1][:60]
          + " ⇒ " + fail_diff(m).splitlines()[2][:60])
    # R5 两人换档（major ↔ historical 各头一条互换 tier）
    def _r5(d, _c, _doc):
        a = next(c for c in d["characters"] if c["tier"] == "major")
        b = next(c for c in d["characters"] if c["tier"] == "historical")
        a["tier"], b["tier"] = b["tier"], a["tier"]
    m = _mutate(_r5)
    check(not _ok(m), "R5 两人换档：两行都错位，首处差异 " + fail_diff(m).splitlines()[2][:60])
    # R6 职名写错（crew.json 里火长改名火某）——不碰 characters.json
    m = _mutate(lambda _d, c, _doc: next(r for r in c["roles"] if r["id"] == "huozhang").update(name="火某"))
    check(not _ok(m) and "火某" in fail_diff(m), "R6 职名写错：红因点到错位行（数据侧已带新名）"
          "（" + fail_diff(m).splitlines()[2][:60] + "…）")
    # R7 块内行序反了（把文档块里相邻两条角色行互换）——总条数不变，靠逐字比对才抓得到
    p7 = split_block(Mem().read(DOC_REL))
    rows = p7[1].split("\n")
    idx = [i for i, l in enumerate(rows) if l.startswith("| `chen_laodao`")
           or l.startswith("| `cai_qixing`")]
    rows[idx[0]], rows[idx[1]] = rows[idx[1]], rows[idx[0]]
    m7 = Mem()
    m7.write(DOC_REL, p7[0] + "\n".join(rows) + p7[2])
    check(not _ok(m7), "R7 块内两行互换：行数格照样过、逐字比对红——" + fail_diff(m7).splitlines()[0])

    # C1 真块照常拆得开、判得上——本格只对「判一已有的绿」复述（判一已红时整份都红，本格不再加账：
    # 自检的绿以「判一那条已经在」为前提，前置不足不另算自检的错）
    check(_ok(Mem()) is True or fails, "C1 现任文档 + 数据照判绿（证明 R 牌不是滥红，同一判法在正常态给出真）"
          + ("（判一已红，本格不另加账）" if fails else ""))
    # C2 行数与主节同现，两口径互不兜底（逐字比对管内容错位，行数管漏档 / 多档）
    n_now = len(json.loads(Mem().read(DATA_REL))["characters"])
    body_now = split_block(Mem().read(DOC_REL))[1]
    n_row = len(re.findall(r"^\| `", body_now, re.M))
    check(n_row == n_now, f"C2 行数口径：块里角色行 {n_row} = 原稿条数 {n_now}")
    # C3 名里带竖线：gen 造不出表、那一红的文案写明「容不下」（那一条红走 _PROBE_BAG，不印不进账）
    m8 = _mutate(lambda d, _c, _doc: d["characters"][0].update(name=d["characters"][0]["name"] + "|x"))
    bag8 = []
    _PROBE_BAG.append(bag8)
    try:
        g8 = gen_block(m8)
    finally:
        _PROBE_BAG.pop()
    check(g8 is None and len([x for x in bag8 if "容不下" in x]) == 1 and len(bag8) == 1,
          "C3 名里带竖线：gen 造不出表、探到恰一条红「容不下」（文案：" + (
              bag8[0].splitlines()[0][:60] if bag8 else "<没探到红——这一路红已不从这里出>") + "…）")
    # C4 roles 表认不出：gen 不降到「—」（那样绿假），红因写明哪一环断了
    m9 = Mem()
    m9.write(CREW_REL, '{"not_roles": true}\n')
    bag9 = []
    _PROBE_BAG.append(bag9)
    try:
        g9 = gen_block(m9)
    finally:
        _PROBE_BAG.pop()
    check(g9 is None and len([x for x in bag9 if "口径断了" in x]) == 1 and len(bag9) == 1,
          "C4 roles 表认不出：gen 不降到「—」（那样绿假），探到恰一条「口径断了」红（文案："
          + (bag9[0].splitlines()[0][:60] if bag9 else "<没探到红——这一路红已不从这里出>") + "…）")
    # C5 TIER_ORDER 出现未登记档：点名补 TIER_NAMES，不放它进表
    m10 = Mem()
    m10.write(TIER_ORDER_SRC[0], m10.read(TIER_ORDER_SRC[0]).replace('"historical"', '"historical", "envoy"'))
    bag10 = []
    _PROBE_BAG.append(bag10)
    try:
        o10 = load_tier_order(m10)
    finally:
        _PROBE_BAG.pop()
    check(o10 is None and len([x for x in bag10 if "envoy" in x]) == 1 and len(bag10) == 1,
          "C5 TIER_ORDER 出现未登记档：点名补 TIER_NAMES、不放它进表（文案："
          + (bag10[0].splitlines()[0][:60] if bag10 else "<没探到红——这一路红已不从这里出>") + "…）")


def main(argv):
    if "--gen" in argv:
        b = gen_block(Mem())
        if b is None:
            return 1
        print(b)
        return 0
    write_fix = "--fix" in argv

    print("一、生成标记与逐字比对")
    mem = Mem()
    doc = mem.read(DOC_REL)
    parts = split_block(doc)
    if not check(parts[0] is not None, f"{DOC_REL} 有恰一对 CHARS-DOC 生成标记"
                 + ("" if parts[0] is not None else f"：{parts[1]}")):
        return report()
    want_str = gen_block(mem)
    if want_str is None:  # gen 已记账（形状 / TIER_ORDER / 职事链），不比了
        return report()
    want = "\n" + want_str + "\n"
    if write_fix and parts[1] != want:
        with open(os.path.join(ROOT, DOC_REL), "w", encoding="utf-8") as f:
            f.write(parts[0] + want + parts[2])
        print(f"  已重写 {DOC_REL} 生成块（{len(want_str.splitlines())} 行）；人工确认 diff 再提交")
        parts = split_block(mem.read(DOC_REL))
    check(parts[1] == want, "生成块与 data/characters.json 现算逐字一致（id / 名 / 生卒 / 职事）"
          + ("" if parts[1] == want else "；" + fail_diff(mem)))
    n_rows = len(re.findall(r"^\| `", parts[1], re.M))
    n_data = len(json.loads(mem.read(DATA_REL))["characters"])
    check(n_rows == n_data, f"生成块角色行数（{n_rows}）= 原稿条数（{n_data}）"
          "——漏档 / 多档这条兜底（行数对上但内容错由上面那条逐字比对抓）")
    selfcheck()
    return report()


def report():
    print()
    print("结果：全部通过" if not fails else f"结果：{len(fails)} 项问题")
    for m in fails:
        print("   ✗ " + m.splitlines()[0])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
