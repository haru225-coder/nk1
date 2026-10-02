#!/usr/bin/env python3
"""data/ 同族文件结构门禁（lane seq4）：scenes.json 那一套结构检查参数化成多文件适用，文件清单在 tools/data_family.json。

同族判据（F1–F3 脚本自动普查，F4 人判、写进清单）：
  F1 顶层有一张「条目表」：dict 的列表，每条都有非空字符串 id 且不重复
  F2 条目里有字段指向同表的 id（非空字符串值过半落在本表 id 里），即条目之间成一张图
  F3 游戏运行时读它：scripts/ 或 scenes/ 的代码里写了这个文件名（lane seq6：.gd 的 # 注释不算；文件名前一个字不许是
     字母 / 数字 / _ / -，cutscenes.json 不算 scenes.json 的读者）
  F4 图有入口，「从入口走不到 = 孤儿」有定义（清单 roots）
data/ 下满足 F1–F3 的文件必须登在清单 families（同族）或 not_family（写明 F4 为何不成立）之一，漏登即红；
登了同族却不再满足 F1/F2、登了非族却已不是候选，都判失效。
候补 watch（lane seq6）：图不按 id 走的（port_beats.json 按 entry）登 {"file", "table", "key"}：普查按该 key 判 F1 / F2 须仍成立
  （不成立 = 本条失效），F3 一成立（运行时读它了）即红，照下文「接入」登进 families（id 写该 key）

对 families 里每个文件跑四项（与 scenes.json 同一套）：
  一、字段齐备 / 类型：顶层键；按 kinds 首个命中的「形」查必填字段（`名?` 为可选）、类型、未登记字段；
      嵌套列表按 shapes 再查一层。类型写法：str / int / num（int 或 float）/ bool / dict / list / null / any /
      list<str> / list<@shape名>，`|` 分隔多选
  二、引用 id 存在：refs 每一路（路径写法：`a.b` 取键、`a[]` 遍历列表、`a{}` 取字典的键）的值必须落在 to 的并集里：
      {"self": true} 本表 id；{"file", "path"} 别的数据文件；{"gd_const": 文件, "name": 常量} GDScript 常量里的字符串；
      {"py_const": 文件, "name": 常量} Python 模块级字面量里的字符串（ast 取，不执行）；edge=true 的一路是图的边
  三、自引用覆盖：F2 普查出的每条自引用路径，要么是 refs 里的一路（不成边的写 why 说为什么），要么登在 not_edges（写原因），
      新添的引用字段不许漏管；lane seq6 起同族文件里「部分命中」（有值是本表 id、但没过半）的路径同样须登
      （F2 的过半阈值只用于判谁是候选，不用于放过同族文件里的引用字段）
  四、无孤儿：从 roots 出发沿 edge 路（undirected=true 时按无向）走不到的条目 = 孤儿；形上写了 orphan_ok 的放过，
      known_orphans 登记的基线放过（登记了却已可达 / 已不在表里即判失效，基线只许缩）
      roots 写法：{"path"} 本文件顶层键；{"file", "path"} 别的数据文件；{"gd_calls": 函数名} scripts/ 里该函数的字符串字面量实参；
      {"gd_regex": 文件, "pattern"} 源码里正则第 1 组；"must": true 的入口取不到 / 不在表里即红
      refs 的 "edge_if"（同 to 的来源写法）：值落在该集合里才成边（scenes 的港卡门只有 PROLOGUE_ONLY_FACILITIES 直进同名幕）；
      known_orphans 每组写 "ids" 列表，或 "from": {"py_const": 文件, "name": 常量} 与别的门禁共用一份基线（scenes 用 lane seq3 的
      verify_story_data.SCENE_ARCHIVE），来源取不到即红
  二之一、单向登记（undirected=true 的文件，lane seq6）：edge 路里 A 列了 B、B 没列回 A 的对须全在 one_way_ok.pairs 基线里；
      新添的单向即红（补对侧，或登进基线写原因），基线里的某对已补齐 / 连线已删也红（基线只减不增）
  零、变异自检：每次先跑（GATES §五.3）——内存里逐格改数据 / 清单 / 源码跑上面同一套检查，同族那几格须红且只红在该文件，
      非族文件（goods / characters / crew）改了须与基线逐条一致；`--mutants` 逐格打印。
      锚按形状定位（lane seq6）：每个同族文件的通用格（删必填 / 删边字段 / 改类型 / 悬空 / 拼错字段 / 新孤儿 / 新添指回本表的字段）
      现挑「兜底形、从入口可达、边字段非空」的第一条当锚，常量 / 入口 / 基线的名字现读清单——id 改名自己跟上；
      挑不到锚（数据里已没有那种形状的条目）即红「锚落不上」并写明挑选条件，不静默绿

接入（将来 data/ 新增同族文件）：普查会先红「F1–F3 成立却没登记」。在 tools/data_family.json 的 families 加一条
  file / table / id / top / kinds（至少一个 when 为 {} 的兜底形）/ shapes / refs（自引用那路 edge=true）/ roots / known_orphans，
  跑 `python3 tools/check_data_family.py` 把现存违规逐条修掉或登进 known_orphans（写原因）；零节按形状自动给它生成通用格
  （lane seq6 起不用手补），`--mutants` 逐格看过，报「锚落不上」的照提示补数据或改挑选条件；
  图没有入口的（如 characters.json 的 relations）登 not_family 写明原因。

  python3 tools/check_data_family.py              # 门禁：普查覆盖 + 各同族文件四项；有问题退 1
  python3 tools/check_data_family.py --survey     # 另打 data/ 全部 json 的普查表（markdown）
  python3 tools/check_data_family.py --mutants    # 零节逐格打印（零节每次都跑，这里只是展开）
"""
import ast, copy, functools, glob, json, os, re, sys
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = "tools/data_family.json"


class Ctx:
    """一次检查用到的全部输入：数据文件（按相对路径缓存）、清单、源码。变异自证改的就是它的副本。"""

    def __init__(self, root):
        self.root, self.files = root, {}
        self.manifest = self.load(MANIFEST)
        self.py = {}  # py_const 读的 Python 源码另放，不许混进 src（F3 只认 scripts/ scenes/）
        self.src = {}
        for pat in ("scripts/**/*.gd", "scenes/**/*.tscn"):
            for p in sorted(glob.glob(os.path.join(root, pat), recursive=True)):
                with open(p, encoding="utf-8") as f:
                    self.src[os.path.relpath(p, root)] = f.read()

    def load(self, rel):
        if rel not in self.files:
            p = os.path.join(self.root, rel)
            if not os.path.isfile(p):
                self.files[rel] = None
            else:
                with open(p, encoding="utf-8") as f:
                    self.files[rel] = json.load(f)
        return self.files[rel]

    def data_files(self):
        return sorted("data/" + os.path.basename(p) for p in glob.glob(os.path.join(self.root, "data", "*.json")))


# ── 路径与类型 ───────────────────────────────────────────
def walk(obj, path):
    """按 `a.b[]` / `a{}` 取值，缺键 / 类型不符的分支静默跳过（有没有由字段检查管）。返回 [(位置, 值)]。"""
    cur = [("", obj)]
    for seg in path.split("."):
        mode = "[]" if seg.endswith("[]") else "{}" if seg.endswith("{}") else ""
        key = seg[:-2] if mode else seg
        nxt = []
        for where, o in cur:
            if not isinstance(o, dict) or key not in o:
                continue
            v, w = o[key], (where + "." if where else "") + key
            if mode == "[]":
                nxt += [(f"{w}[{i}]", x) for i, x in enumerate(v)] if isinstance(v, list) else []
            elif mode == "{}":
                nxt += [(f"{w}{{{k}}}", k) for k in v] if isinstance(v, dict) else []
            else:
                nxt.append((w, v))
        cur = nxt
    return cur


def tname(v):
    return {bool: "bool", int: "int", float: "float", str: "str", list: "list", dict: "dict", type(None): "null"}.get(type(v), type(v).__name__)


def type_errors(v, spec, shapes, where):
    alts = [a.strip() for a in spec.split("|")]
    per = []
    for a in alts:
        errs = one_type(v, a, shapes, where)
        if not errs:
            return []
        per.append(errs)
    return per[0] if len(alts) == 1 else [f"{where} 类型应为 {spec}，实为 {tname(v)}"]


def one_type(v, a, shapes, where):
    simple = {"str": lambda x: isinstance(x, str), "int": lambda x: isinstance(x, int) and not isinstance(x, bool),
              "num": lambda x: isinstance(x, (int, float)) and not isinstance(x, bool), "bool": lambda x: isinstance(x, bool),
              "dict": lambda x: isinstance(x, dict), "list": lambda x: isinstance(x, list), "null": lambda x: x is None,
              "any": lambda x: True}
    if a in simple:
        return [] if simple[a](v) else [f"{where} 类型应为 {a}，实为 {tname(v)}"]
    m = re.fullmatch(r"list<(@?[a-z_]+)>", a)
    if not m:
        return [f"清单类型写法不认：{a!r}（{where}）"]
    if not isinstance(v, list):
        return [f"{where} 类型应为 {a}，实为 {tname(v)}"]
    inner, out = m.group(1), []
    for i, x in enumerate(v):
        w = f"{where}[{i}]"
        if inner.startswith("@"):
            if inner[1:] not in shapes:
                return [f"清单 shapes 里没有 {inner[1:]}（{where}）"]
            out += field_errors(x, shapes[inner[1:]], shapes, w, inner[1:])
        else:
            out += one_type(x, inner, shapes, w)
    return out


def field_errors(entry, fields, shapes, where, kind):
    if not isinstance(entry, dict):
        return [f"{where} 应为对象，实为 {tname(entry)}（形 {kind}）"]
    out, declared = [], set()
    for k, spec in fields.items():
        opt = k.endswith("?")
        k = k.rstrip("?")
        declared.add(k)
        if k not in entry:
            if not opt:
                out.append(f"{where} 缺必填字段 {k}（形 {kind}）")
            continue
        out += type_errors(entry[k], spec, shapes, f"{where}.{k}")
    out += [f"{where} 有未登记字段 {k}（形 {kind}；拼错了，或该在清单里登记）" for k in entry if k not in declared]
    return out


def kind_of(entry, kinds):
    for kd in kinds:
        w = kd["when"]
        if not w or ("field" in w and entry.get(w["field"]) == w["eq"]) or ("has" in w and w["has"] in entry):
            return kd
    return None


# ── 源码取值 ─────────────────────────────────────────────
def code_lines(src):
    return "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))


def gd_const(ctx, rel, name):
    src = ctx.src.get(rel)
    if src is None:
        return None
    m = re.search(r"^const " + re.escape(name) + r"\b[^\n=]*:?=\s*([\[{])", src, re.M)
    if not m:
        return None
    depth, i, close = 0, m.start(1), {"[": "]", "{": "}"}[m.group(1)]
    for j in range(i, len(src)):
        depth += src[j] == m.group(1)
        depth -= src[j] == close
        if depth == 0:
            return set(re.findall(r'"([^"\n]*)"', code_lines(src[i:j + 1])))
    return None


@functools.lru_cache(maxsize=None)
def _py_ast(src):
    return ast.parse(src)


def py_const(ctx, rel, name):
    """Python 源文件模块级 `NAME = {字面量}` → 其中的字符串集合（ast 取，不执行）。取不到给 None。"""
    if rel not in ctx.py:
        p = os.path.join(ctx.root, rel)
        ctx.py[rel] = open(p, encoding="utf-8").read() if os.path.isfile(p) else None
    if ctx.py[rel] is None:
        return None
    for node in _py_ast(ctx.py[rel]).body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            try:
                v = ast.literal_eval(node.value)
            except ValueError:
                return None
            return {x for x in v if isinstance(x, str)} if isinstance(v, (set, list, tuple, frozenset)) else None
    return None


def gd_calls(ctx, func):
    rx = re.compile(r"\b" + re.escape(func) + r'\(\s*"([^"\n]+)"\s*\)')
    return {v for rel, s in ctx.src.items() if rel.endswith(".gd") for v in rx.findall(code_lines(s))}


def source_values(ctx, spec, own_rel, own_ids):
    """refs.to / roots 的一条来源 → (值集合, 说明)。取不到给 None。"""
    if spec.get("self"):
        return set(own_ids), "本表 id"
    if "gd_const" in spec:
        return gd_const(ctx, spec["gd_const"], spec["name"]), f"{spec['gd_const']} 常量 {spec['name']}"
    if "gd_calls" in spec:
        return gd_calls(ctx, spec["gd_calls"]), f"scripts/ 里 {spec['gd_calls']}(\"…\")"
    if "py_const" in spec:
        return py_const(ctx, spec["py_const"], spec["name"]), f"{spec['py_const']} 常量 {spec['name']}"
    if "gd_regex" in spec:
        src = ctx.src.get(spec["gd_regex"])
        m = re.search(spec["pattern"], src or "", re.M)
        return ({m.group(1)} if m else None), f"{spec['gd_regex']} /{spec['pattern']}/"
    rel = spec.get("file", own_rel)
    data = ctx.load(rel)
    if data is None:
        return None, f"{rel}（文件不在）"
    return {v for _, v in walk(data, spec["path"]) if isinstance(v, str)}, f"{rel} {spec['path']}"


# ── 普查（F1–F3）────────────────────────────────────────
def leaf_paths(obj, pre=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from leaf_paths(v, f"{pre}.{k}" if pre else k)
    elif isinstance(obj, list):
        for v in obj:
            yield from leaf_paths(v, pre + "[]")
    else:
        yield pre, obj


def _gd_code_part(line):
    """一行 GDScript 去掉 # 注释（引号里的 # 不算）。"""
    q, i = None, 0
    while i < len(line):
        ch = line[i]
        if q:
            if ch == "\\":
                i += 2
                continue
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
        elif ch == "#":
            return line[:i]
        i += 1
    return line


@functools.lru_cache(maxsize=None)
def code_only(rel, src):
    """F3 用的「代码」：.gd 逐行去 # 注释（lane seq6，原先注释里提一句文件名也算读者）；.tscn 原样。"""
    return "\n".join(_gd_code_part(l) for l in src.splitlines()) if rel.endswith(".gd") else src


@functools.lru_cache(maxsize=None)
def reads_file(rel, src, base):
    """rel 的代码里写了文件名 base：前一个字不许是字母 / 数字 / _ / -（lane seq6：cutscenes.json 原先被算成 scenes.json 的读者）。"""
    return base in src and re.search(r"(?<![\w-])" + re.escape(base), code_only(rel, src)) is not None


def survey_file(ctx, rel, key="id", table=None):
    """key：条目主键字段（默认 id；family 用清单 id，watch 用清单 key）；table：只看这张表（默认取首张 F1 表）。
    self_refs = 过半命中本表主键的路径（F2 判据）；partial = 有命中、没过半的路径（lane seq6：同族文件里也要登）。"""
    data = ctx.load(rel)
    base = os.path.basename(rel)
    readers = sorted(r for r, s in ctx.src.items() if reads_file(r, s, base))
    info = {"file": rel, "key": key, "readers": readers, "tables": [], "f1": None, "self_refs": {}, "partial": {}}
    if isinstance(data, dict):
        for tk, v in data.items():
            if isinstance(v, list) and v and all(isinstance(e, dict) for e in v):
                ids = [e.get(key) for e in v]
                f1 = all(isinstance(i, str) and i for i in ids) and len(set(ids)) == len(ids)
                info["tables"].append((tk, len(v), "list", f1))
                if f1 and info["f1"] is None and table in (None, tk):
                    idset, acc = set(ids), {}
                    for e in v:
                        for p, x in leaf_paths(e):
                            if p != key and isinstance(x, str) and x:
                                acc.setdefault(p, []).append(x)
                    info["f1"] = tk
                    hits = {p: (sum(x in idset for x in xs), len(xs)) for p, xs in acc.items()}
                    info["self_refs"] = {p: hn for p, hn in hits.items() if 2 * hn[0] > hn[1]}
                    info["partial"] = {p: hn for p, hn in hits.items() if 0 < hn[0] and 2 * hn[0] <= hn[1]}
            elif isinstance(v, (list, dict)) and tk != "meta":
                info["tables"].append((tk, len(v), "list" if isinstance(v, list) else "dict", False))
    info["candidate"] = bool(info["f1"] and info["self_refs"] and info["readers"])
    return info


# ── 检查 ─────────────────────────────────────────────────
def run(ctx, verbose=True):
    fails, out = [], []

    def ok(cond, good, bad_lines):
        if cond:
            out.append("  ✓ " + good)
        else:
            for b in bad_lines:
                out.append("  ✗ " + b)
                fails.append(b)

    man = ctx.manifest
    fam = {f["file"]: f for f in man.get("families", [])}
    nf = {f["file"]: f for f in man.get("not_family", [])}
    watch = {w["file"]: w for w in man.get("watch", [])}
    reach = {}
    ctx.reach = reach  # 各同族文件从入口可达的 id；零节按形状挑锚用

    out.append("== 普查：data/ 下 F1–F3 候选必须登在 families / not_family")
    surveys = {rel: survey_file(ctx, rel) for rel in ctx.data_files()}
    cands = [r for r, s in surveys.items() if s["candidate"]]
    missing = [r for r in cands if r not in fam and r not in nf]
    ok(not missing, f"候选 {len(cands)} 个（{'、'.join(cands)}）全部登记：同族 {len(fam)}、非族 {len(nf)}",
       [f"{r} 满足 F1–F3（自引用 {'、'.join(surveys[r]['self_refs'])}；运行时读它的有 {len(surveys[r]['readers'])} 个文件）"
        f"却没登记——同族加进 tools/data_family.json 的 families，图没有入口的登 not_family 写原因" for r in missing])
    dup = sorted(set(fam) & set(nf))
    stale_nf = [r for r in nf if r not in surveys or not surveys[r]["candidate"]]
    ok(not dup and not stale_nf, "not_family 条目都还是候选、不与 families 重登",
       [f"{r} 同时登在 families 与 not_family" for r in dup]
       + [f"not_family 登了 {r}，它已不满足 F1–F3（文件不在 / 无自引用 / 运行时不读）——删掉这条" for r in stale_nf])
    for r, f in nf.items():
        ok(bool(f.get("why")), f"not_family {r} 写了原因", [f"not_family {r} 没写 why"])
    for r, w in watch.items():  # 候补（lane seq6）：图不按 id 走、运行时还不读的
        sw = survey_file(ctx, r, key=w.get("key", "id"), table=w.get("table"))
        bad = []
        if r in fam or r in nf:
            bad.append(f"watch 登了 {r}，它已登在 {'families' if r in fam else 'not_family'}——从 watch 删掉")
        elif ctx.load(r) is None:
            bad.append(f"watch 登了 {r}，文件不在——删掉这条")
        elif sw["f1"] != w.get("table") or not sw["self_refs"]:
            bad.append(f"watch {r} 按 key={w.get('key')} 已不满足 F1 / F2（首张表 {sw['f1']!r}，自引用 {sw['self_refs']}）——本条失效，改 key 或删掉")
        elif sw["readers"]:
            bad.append(f"{r} 已被运行时读（{'、'.join(sw['readers'])}），按 {w.get('key')} 自引用 {'、'.join(sw['self_refs'])} 成图——"
                       f"照文档串「接入」登进 families（id: {w.get('key')}），并从 watch 删掉")
        if not w.get("why"):
            bad.append(f"watch {r} 没写 why")
        ok(not bad, f"候补 {r}：按 {w.get('key')} F1 / F2 仍成立（自引用 " + "、".join(f"{p} {a}/{b}" for p, (a, b) in sw["self_refs"].items())
           + "），运行时不读——留档；F3 一成立即红", bad)

    for rel, spec in fam.items():
        data = ctx.load(rel)
        out.append(f"== {rel}")
        if data is None:
            ok(False, "", [f"{rel} 登在 families，文件不在"])
            continue
        sv = survey_file(ctx, rel, key=spec["id"], table=spec["table"])
        f2_min = int(spec.get("f2_min_refs", 1))
        ok(sv["f1"] == spec["table"] and len(sv["self_refs"]) >= f2_min, f"F1 / F2 成立（表 {spec['table']}，自引用 {'、'.join(sv['self_refs'])}）",
           [f"{rel} 登为同族，但普查已不满足 F1 / F2（首张 id 表 {sv['f1']!r}，自引用 {sv['self_refs']}）——改清单或移出 families"]
           + ([] if not (sv["f1"] == spec["table"] and len(sv["self_refs"]) >= 1) or len(sv["self_refs"]) >= f2_min else
              [f"{rel} 自引用只剩 {len(sv['self_refs'])} 路，低于清单 f2_min_refs={f2_min}（本表钉了至少两路自引用；数据瘦身到这个形即登记失效，改数据 / 改清单须同步）"]))
        ok(bool(sv["readers"]), f"F3 运行时读它（{len(sv['readers'])} 个文件）", [f"{rel} 登为同族，但 scripts/ scenes/ 已不读它"])

        # 一、字段齐备 / 类型
        errs = []
        if not isinstance(data, dict):
            errs.append(f"{rel} 顶层应为对象")
            data = {}
        errs += [e.replace("<top>.", "", 1) for e in field_errors(data, {k: ("list" if k == spec["table"] else t) for k, t in spec["top"].items()},
                                                             {}, "<top>", "顶层")]
        entries = data.get(spec["table"]) if isinstance(data.get(spec["table"]), list) else []
        ids, kinds_seen = [], {}
        for i, e in enumerate(entries):
            eid = e.get(spec["id"]) if isinstance(e, dict) else None
            where = f"{rel} " + (eid if isinstance(eid, str) and eid else f"{spec['table']}[{i}]")
            if not isinstance(eid, str) or not eid:
                errs.append(f"{where} 缺 {spec['id']} 或不是非空字符串")
            else:
                ids.append(eid)
            kd = kind_of(e, spec["kinds"]) if isinstance(e, dict) else None
            if kd is None:
                errs.append(f"{where} 没有命中任何形（kinds 缺 when 为 {{}} 的兜底形）")
                continue
            kinds_seen[kd["name"]] = kinds_seen.get(kd["name"], 0) + 1
            errs += field_errors(e, kd["fields"], spec.get("shapes", {}), where, kd["name"])
        dups = sorted({i for i in ids if ids.count(i) > 1})
        errs += [f"{rel} id 重复：{d}" for d in dups]
        ok(not errs, f"一、字段齐备 / 类型：{len(entries)} 条（形 " + "、".join(f"{k} {v}" for k, v in kinds_seen.items()) + "）全对", errs)
        idset = set(ids)
        by_id = {e.get(spec["id"]): e for e in entries if isinstance(e, dict)}

        # 二、引用 id 存在
        errs, counts, edges, directed = [], [], {i: set() for i in idset}, set()
        for ref in spec.get("refs", []):
            targets, descs = set(), []
            for t in ref["to"]:
                vals, d = source_values(ctx, t, rel, idset)
                if vals is None or (not vals and not t.get("self")):
                    errs.append(f"{rel} 引用 {ref['path']} 的目标「{d}」取不到（文件不在 / 常量改名 / 解析失败）")
                    vals = set()
                targets |= vals
                descs.append(d)
            gate = None
            if ref.get("edge_if"):
                gate, d = source_values(ctx, ref["edge_if"], rel, idset)
                if not gate:
                    errs.append(f"{rel} 引用 {ref['path']} 的成边条件「{d}」取不到（常量改名 / 解析失败）")
                    gate = set()
            n = 0
            for eid, e in by_id.items():
                for where, v in walk(e, ref["path"]):
                    n += 1
                    if v == "" and ref.get("allow_empty"):
                        continue
                    if not isinstance(v, str) or v not in targets:
                        errs.append(f"{rel} {eid}.{where} = {v!r} 悬空（应落在：{' ∪ '.join(descs)}）")
                    elif ref.get("edge") and v in idset and (gate is None or v in gate):
                        edges[eid].add(v)
                        directed.add((eid, v))
                        if spec.get("undirected"):
                            edges[v].add(eid)
            counts.append(f"{ref['path']} {n}")
        ok(not errs, "二、引用 id 存在：" + "、".join(counts) + " 全部落地", errs)

        # 二之一、单向登记（lane seq6）：无向图里 A 列了 B、B 没列回 A
        ow = spec.get("one_way_ok")
        if spec.get("undirected"):
            one = sorted((a, b) for a, b in directed if a != b and (b, a) not in directed)
            basel = [tuple(x) for x in (ow or {}).get("pairs", [])]
            new_ow = [x for x in one if x not in basel]
            gone = [x for x in basel if x not in one]
            ok(not new_ow and not gone and (not basel or bool((ow or {}).get("why"))),
               f"二之一、单向登记：{len(one)} 对（{'、'.join(f'{a}→{b}' for a, b in one) or '无'}）= one_way_ok 基线 {len(basel)} 对",
               [f"{rel} {a}→{b} 单向登记（{b} 没列回 {a}）：按无向口径走得通，但不在 one_way_ok 基线——补对侧，或登进基线写原因（基线只减不增）" for a, b in new_ow]
               + [f"{rel} 基线里的 {a}→{b} 已不是单向（对侧补齐了 / 连线删了）——从 one_way_ok 删掉（只减不增）" for a, b in gone]
               + ([f"{rel} one_way_ok 没写 why"] if basel and not (ow or {}).get("why") else []))
        elif ow:
            ok(False, "", [f"{rel} 写了 one_way_ok，但不是 undirected 图——删掉"])

        # 三、自引用覆盖
        covered = {r["path"] for r in spec.get("refs", [])} | {r["path"] for r in spec.get("not_edges", [])}
        bare = lambda p: re.sub(r"\{\}$", "", p)
        hits = {**sv["self_refs"], **sv["partial"]}
        miss = [p for p in hits if p not in covered and bare(p) not in covered]
        stale = [r["path"] for r in spec.get("not_edges", []) if r["path"] not in hits]
        ok(not miss and not stale, f"三、自引用覆盖：普查 {len(sv['self_refs'])} 路过半 + {len(sv['partial'])} 路部分命中"
           + ("（" + "、".join(f"{p} {a}/{b}" for p, (a, b) in sv["partial"].items()) + "）" if sv["partial"] else "") + f" 都已登记（refs {len(spec.get('refs', []))} 路，其中成边 {len([r for r in spec.get('refs', []) if r.get('edge')])} 路；not_edges {len(spec.get('not_edges', []))} 路）",
           [f"{rel} 字段 {p} 有 {hits[p][0]}/{hits[p][1]} 个值是本表 id" + ("" if p in sv["self_refs"] else "（未过半，F2 普查不算它，同族文件里照样要登）")
            + "，却没登 refs 也没登 not_edges" for p in miss]
           + [f"{rel} not_edges 登了 {p}，普查已不认它是自引用——删掉这条" for p in stale]
           + [f"{rel} not_edges {r['path']} 没写 why" for r in spec.get("not_edges", []) if not r.get("why")])

        # 四、无孤儿
        errs, starts = [], set()
        for rt in spec.get("roots", []):
            vals, d = source_values(ctx, rt, rel, idset)
            vals = vals or set()
            if rt.get("must") and not (vals & idset):
                errs.append(f"{rel} 入口「{d}」取不到或不在本表（取到 {sorted(vals)}）")
            starts |= vals & idset
        seen, stack = set(), sorted(starts)
        while stack:
            x = stack.pop()
            if x not in seen:
                seen.add(x)
                stack += sorted(edges.get(x, set()) - seen)
        reach[rel] = (seen, set(starts))
        known = {}
        for g in spec.get("known_orphans", []):
            ids_g = g.get("ids")
            if "from" in g:
                ids_g, d = source_values(ctx, g["from"], rel, idset)
                if not ids_g:
                    errs.append(f"{rel} known_orphans 的来源「{d}」取不到（文件不在 / 常量改名 / 解析失败）")
                    ids_g = set()
            for i in sorted(ids_g or ()):
                known[i] = g
            if not g.get("why"):
                errs.append(f"{rel} known_orphans 有一组没写 why")
        okd = {k["name"] for k in spec["kinds"] if k.get("orphan_ok")}
        incoming = {}
        for a, bs in edges.items():
            for b in bs:
                incoming.setdefault(b, set()).add(a)
        n_ok = n_known = 0
        for eid in ids:
            if eid in seen:
                continue
            kd = kind_of(by_id[eid], spec["kinds"])
            if kd and kd["name"] in okd:
                n_ok += 1
            elif eid in known:
                n_known += 1
            else:
                inc = sorted(incoming.get(eid, set()))
                errs.append(f"{rel} {eid} 是孤儿：从入口走不到（" + (f"有入边 {len(inc)} 条，来自 {'、'.join(inc[:4])}，但它们本身也走不到" if inc else "没有任何入边") + "）")
        for i in known:
            if i not in idset:
                errs.append(f"{rel} known_orphans 登了 {i}，表里已没有——从清单删掉（基线只许缩）")
            elif i in seen:
                errs.append(f"{rel} known_orphans 登了 {i}，它已从入口可达——从清单删掉（基线只许缩）")
            elif (kind_of(by_id[i], spec["kinds"]) or {}).get("name") in okd:
                errs.append(f"{rel} known_orphans 登了 {i}，它的形已 orphan_ok——重登了，删掉")
        ok(not errs, f"四、无孤儿：入口 {len(starts)} 个，可达 {len(seen)} / {len(ids)}；不可达 {len(ids) - len(seen)} = 形放过 {n_ok} + 已登记基线 {n_known}",
           errs)

    if verbose:
        print("\n".join(out))
    return fails


# ── 普查表 ───────────────────────────────────────────────
def print_survey(ctx):
    man = ctx.manifest
    fam = {f["file"] for f in man.get("families", [])}
    nf = {f["file"] for f in man.get("not_family", [])}
    watch = {w["file"]: w for w in man.get("watch", [])}
    fkey = {f["file"]: (f["id"], f["table"]) for f in man.get("families", [])}
    sim = {}
    for p in ("tools/simulate_run.py", "tools/simulate_endgame.py"):
        with open(os.path.join(ctx.root, p), encoding="utf-8") as f:
            sim[p] = f.read()
    print("| 文件 | 顶层表（`[]` 列表 / `{}` 字典，条目数；meta 不计） | 运行时读（scripts/ scenes/ 代码，不算注释） | sim 读 | F1 id 表 | F2 自引用（命中/值数） | 部分命中（未过半） | 判定 |")
    print("|---|---|---|---|---|---|---|---|")
    for rel in ctx.data_files():
        k, t = fkey.get(rel) or ((watch[rel]["key"], watch[rel]["table"]) if rel in watch else ("id", None))
        s = survey_file(ctx, rel, key=k, table=t)
        data = ctx.load(rel)
        tabs = "、".join(f"{k}{'{}' if t == 'dict' else '[]'} {n}" for k, n, t, _ in s["tables"]) or "—"
        readers = "、".join(os.path.splitext(os.path.basename(r))[0] for r in s["readers"]) or "**不读**"
        simr = "、".join(os.path.basename(p)[:-3] for p, src in sim.items() if os.path.basename(rel) in src) or "—"
        f2 = "、".join(f"`{p}` {a}/{b}" for p, (a, b) in s["self_refs"].items()) or "—"
        part = "、".join(f"`{p}` {a}/{b}" for p, (a, b) in s["partial"].items()) or "—"
        verdict = ("**同族**" if rel in fam else "近亲·非族（F4 不成立）" if rel in nf
                   else f"候补（按 {k}；F3 成立即须入族）" if rel in watch else "非族")
        print(f"| `{rel}` | {tabs} | {readers} | {simr} | {s['f1'] or '—'}{'' if k == 'id' else f'（主键 {k}）'} | {f2} | {part} | {verdict} |")


# ── 变异自证 ─────────────────────────────────────────────
class NoAnchor(Exception):
    """按形状挑不到锚：数据里已没有那种形状的条目。零节判红并写明挑选条件（lane seq6：不许静默绿）。"""


def _top(path):
    return re.split(r"[.\[{]", path, maxsplit=1)[0]


def _leaf(path):
    return re.sub(r"(\[\]|\{\})$", "", path.split(".")[-1])


def _set_first(e, path, val):
    """按 `a[].b` / `a[]` / `a` 把第一处值改成 val（锚已保证非空）。"""
    segs = path.split(".")
    for i, seg in enumerate(segs):
        k, last = seg[:-2] if seg.endswith("[]") else seg, i == len(segs) - 1
        if seg.endswith("[]"):
            if last:
                e[k][0] = val
            else:
                e = e[k][0]
        elif last:
            e[k] = val
        else:
            e = e[k]


def _unread(src, rel, base):
    """把 rel 代码里「真读」base 的写法换掉，# 注释与更长的文件名（cutscenes.json 之于 scenes.json）原样留着。"""
    if base not in src:
        return src
    rx = re.compile(r"(?<![\w-])" + re.escape(base))
    if not rel.endswith(".gd"):
        return rx.sub(base[:-5] + "_mut.json", src)
    out = []
    for line in src.splitlines(keepends=True):
        code = _gd_code_part(line.rstrip("\n"))
        out.append(rx.sub(base[:-5] + "_mut.json", code) + line[len(code):])
    return "".join(out)


def mutants(ctx):
    """内存变异逐格跑 run()，返回 [(过否, 一行)]。每次门禁都先跑（零节），--mutants 逐格打印。
    lane seq6：同族文件的格按清单与形状生成（锚 = 兜底形、从入口可达、边字段非空的第一条；常量 / 入口 / 基线名读清单），
    id 改名自己跟上；挑不到锚即红「锚落不上」。"""
    base = run(ctx, verbose=False)
    reach, man = ctx.reach, ctx.manifest
    fams = man.get("families", [])
    M, res = [], []

    def cell(mid, build):
        try:
            desc, fn, want = build()
        except NoAnchor as e:
            res.append((False, f"{mid} 锚落不上：{e}——数据里已没有这种形状的条目，照新数据改 mutants() 里这一格的挑选条件（不许删格了事）"))
            return
        M.append((mid, desc, fn, want))

    def ent(c, spec, eid):
        return next(e for e in c.files[spec["file"]][spec["table"]] if e.get(spec["id"]) == eid)

    def fallback(spec):
        kd = next((k for k in spec["kinds"] if not k["when"]), None)
        if kd is None:
            raise NoAnchor(f"{spec['file']} 的 kinds 没有 when 为 {{}} 的兜底形")
        return kd

    def edge_ref(spec):
        er = next((r for r in spec.get("refs", []) if r.get("edge")), None)
        if er is None:
            raise NoAnchor(f"{spec['file']} 的 refs 没有 edge=true 的一路")
        return er

    def anchor(spec, skip=()):
        rel, kd, er = spec["file"], fallback(spec), edge_ref(spec)
        top = _top(er["path"])
        seen = reach.get(rel, (set(), set()))[0]
        if top not in kd["fields"]:
            raise NoAnchor(f"{rel} 兜底形 {kd['name']} 没有必填的边字段 {top}")
        for e in ctx.files[rel][spec["table"]]:
            eid = e.get(spec["id"])
            if eid in seen and eid not in skip and kind_of(e, spec["kinds"]) is kd and walk(e, er["path"]):
                return eid
        raise NoAnchor(f"{rel} 找不到「兜底形 {kd['name']}、从入口可达、{er['path']} 非空」" + (f"、不是 {'、'.join(skip)}" if skip else "") + " 的条目")

    def str_fields(spec, kd):
        fs = [k for k, t in kd["fields"].items() if not k.endswith("?") and k != spec["id"] and t == "str"]
        if not fs:
            raise NoAnchor(f"{spec['file']} 兜底形 {kd['name']} 没有必填的 str 字段")
        return fs

    # lane w20-c2：清单 mutant_skip 登掉的格（锚挑不到不是因为检查被放宽，而是这表的图就没有那种形状——
    # port_beats 按 entry 记演出账、可达的针没一条带成边回指）。只许跳形状格，skips 与天生的形状格一起记数
    used_tags = set()
    for spec in fams:
        rel, key = spec["file"], spec["id"]
        skips = set(spec.get("mutant_skip", []))
        tag = spec["table"][0].upper()
        tag = tag if tag not in used_tags else spec["table"]
        used_tags.add(tag)
        n = iter(range(1, 100))

        def g_del_req(spec=spec, rel=rel):
            aid, f = anchor(spec), str_fields(spec, fallback(spec))[0]
            return (f"{rel} {aid} 删必填 {f}", lambda c: ent(c, spec, aid).pop(f), (f"{aid} 缺必填字段 {f}", rel))

        def g_del_edge(spec=spec, rel=rel):
            aid, top = anchor(spec), _top(edge_ref(spec)["path"])
            return (f"{rel} {aid} 删边字段 {top}", lambda c: ent(c, spec, aid).pop(top), (f"{aid} 缺必填字段 {top}", rel))

        def g_type(spec=spec, rel=rel):
            aid, f = anchor(spec), str_fields(spec, fallback(spec))[-1]
            return (f"{rel} {aid}.{f} 改成数字", lambda c: ent(c, spec, aid).__setitem__(f, 123), (f"{aid}.{f} 类型应为 str", rel))

        def g_dangle(spec=spec, rel=rel):
            aid, p = anchor(spec), edge_ref(spec)["path"]
            return (f"{rel} {aid} 的 {p} 首个值改悬空", lambda c: _set_first(ent(c, spec, aid), p, "nowhere_mut"), ("'nowhere_mut' 悬空", rel))

        def g_typo(spec=spec, rel=rel):
            aid, p = anchor(spec), edge_ref(spec)["path"]
            top, mis = _top(p), _leaf(p)[:-1]
            if "." in p:
                fn = lambda c: ent(c, spec, aid)[top][0].__setitem__(mis, "x")
            else:
                fn = lambda c: ent(c, spec, aid).__setitem__(mis, list(ent(c, spec, aid)[top]))
            return (f"{rel} {aid} 多一个拼错的 {mis}（{_leaf(p)}）", fn, (f"未登记字段 {mis}", rel))

        def g_orphan(spec=spec, rel=rel, key=key):
            aid = anchor(spec)
            tops = {_top(r["path"]) for r in spec.get("refs", []) if r.get("edge")}

            def fn(c):
                e = copy.deepcopy(ent(c, spec, aid))
                e[key] = "zz_mut_orphan"
                for t in tops & set(e):
                    e[t] = [] if isinstance(e[t], list) else e[t]
                c.files[rel][spec["table"]].append(e)
            return (f"{rel} 照 {aid} 新增一条、边字段清空、没人指向", fn, ("zz_mut_orphan 是孤儿", rel))

        def g_selfref(spec=spec, rel=rel):
            a = anchor(spec)
            b = anchor(spec, skip=(a,))

            def fn(c):
                ent(c, spec, a)["back_mut"] = b
                ent(c, spec, b)["back_mut"] = a
            return (f"{rel} {a} / {b} 新添互指的 back_mut 没登记", fn, ("未登记字段 back_mut", rel))

        for nm, build in (("del_req", g_del_req), ("del_edge", g_del_edge), ("type", g_type), ("dangle", g_dangle),
                          ("typo", g_typo), ("orphan", g_orphan), ("selfref", g_selfref)):
            if nm in skips:
                res.append((True, f"{tag}{next(n)} {rel} 跳过 {nm}（清单 mutant_skip 登记：{spec.get('mutant_skip_why', '没写原因')}）"))
                continue
            cell(f"{tag}{next(n)}", build)

        # 基线里的条目被接回主线
        if spec.get("known_orphans") and "known" not in skips:
            def g_known(spec=spec, rel=rel):
                known = set()
                for g in spec["known_orphans"]:
                    vals = source_values(ctx, g["from"], rel, set())[0] if "from" in g else g.get("ids")
                    known |= set(vals or ())
                ids = {e.get(spec["id"]) for e in ctx.files[rel][spec["table"]]}
                seen = reach.get(rel, (set(), set()))[0]
                ko = next((i for i in sorted(known) if i in ids and i not in seen), None)
                if ko is None:
                    raise NoAnchor(f"{rel} known_orphans 里没有还在表里、仍不可达的 id")
                aid, p = anchor(spec), edge_ref(spec)["path"]
                top = _top(p)

                def fn(c):
                    e = ent(c, spec, aid)
                    if "." in p:
                        item = copy.deepcopy(e[top][0])
                        _set_first({top: [item]}, p, ko)
                        e[top].append(item)
                    else:
                        e[top].append(ko)
                return (f"{rel} 基线孤儿 {ko} 被 {aid} 接回主线", fn, (f"known_orphans 登了 {ko}，它已从入口可达", rel))
            cell(f"{tag}{next(n)}", g_known)

        # 清单里点名的源码常量 / 入口 / 共用基线改名（名字现读清单）
        for ref in spec.get("refs", []):
            for t in ref["to"] + ([ref["edge_if"]] if ref.get("edge_if") else []):
                if "gd_const" in t:
                    frag = "成边条件" if t is ref.get("edge_if") else "取不到"

                    def g_const(t=t, rel=rel, frag=frag):
                        f, nm = t["gd_const"], t["name"]
                        if f"const {nm}" not in ctx.src.get(f, ""):
                            raise NoAnchor(f"{f} 里没有 const {nm}")
                        return (f"{f} {nm} 改名", lambda c: c.src.__setitem__(f, c.src[f].replace(f"const {nm}", f"const {nm}_MUT")), (frag, rel))
                    cell(f"{tag}{next(n)}", g_const)
        for g in spec.get("known_orphans", []):
            if "py_const" in g.get("from", {}):
                def g_py(g=g, rel=rel):
                    f, nm = g["from"]["py_const"], g["from"]["name"]

                    def fn(c):
                        py_const(c, f, nm)
                        c.py[f] = re.sub(rf"^{re.escape(nm)}(\s*=)", rf"{nm}_MUT\1", c.py[f], flags=re.M)
                    return (f"{f} {nm} 改名（共用基线断了）", fn, ("known_orphans 的来源", rel))
                cell(f"{tag}{next(n)}", g_py)
        for rt in spec.get("roots", []):
            if "gd_regex" in rt and rt.get("must"):
                def g_root(rt=rt, rel=rel):
                    f = rt["gd_regex"]
                    m = re.search(rt["pattern"], ctx.src.get(f, ""), re.M)
                    if not m:
                        raise NoAnchor(f"{f} 里匹配不到入口 /{rt['pattern']}/")
                    s0, s1 = m.span(1)
                    return (f"{f} 入口 {m.group(1)} 改成不存在的 id", lambda c: c.src.__setitem__(f, c.src[f][:s0] + "lost_mut" + c.src[f][s1:]), ("入口", rel))
                cell(f"{tag}{next(n)}", g_root)

        # ③ 部分命中的自引用路径漏登（lane seq6）
        sv = survey_file(ctx, rel, key=key, table=spec["table"])
        part = [r["path"] for r in spec.get("refs", []) if r["path"] in sv["partial"]]
        if part:
            def g_part(spec=spec, rel=rel, p=part[0]):
                def fn(c):
                    s2 = next(f for f in c.manifest["families"] if f["file"] == rel)
                    s2["refs"] = [r for r in s2["refs"] if r["path"] != p]
                return (f"清单删掉 {rel} 部分命中的一路 {p}（{sv['partial'][p][0]}/{sv['partial'][p][1]}）", fn, ([f"字段 {p} 有", "未过半"], rel))
            cell(f"{tag}{next(n)}", g_part)

        # ① 单向登记（lane seq6）
        if spec.get("undirected"):
            def g_ow_new(spec=spec, rel=rel):
                top = _top(edge_ref(spec)["path"])
                a = anchor(spec)
                ea = ent(ctx, spec, a)
                b = next((e.get(spec["id"]) for e in ctx.files[rel][spec["table"]]
                          if e.get(spec["id"]) != a and e.get(spec["id"]) not in ea[top] and a not in (e.get(top) or [])), None)
                if b is None:
                    raise NoAnchor(f"{rel} 找不到与 {a} 两边都没列的条目")
                return (f"{rel} {a} 新列 {b}、{b} 没列回", lambda c: ent(c, spec, a)[top].append(b), (f"{a}→{b} 单向登记", rel))
            cell(f"{tag}{next(n)}", g_ow_new)
            if (spec.get("one_way_ok") or {}).get("pairs"):
                def g_ow_fix(spec=spec, rel=rel):
                    top = _top(edge_ref(spec)["path"])
                    ids = {e.get(spec["id"]) for e in ctx.files[rel][spec["table"]]}
                    pr = next((p for p in spec["one_way_ok"]["pairs"] if set(p) <= ids), None)
                    if pr is None:
                        raise NoAnchor(f"{rel} one_way_ok 基线里没有两端都还在表里的对")
                    a, b = pr
                    return (f"{rel} 基线单向 {a}→{b} 补齐对侧", lambda c: ent(c, spec, b)[top].append(a), (f"基线里的 {a}→{b} 已不是单向", rel))
                cell(f"{tag}{next(n)}", g_ow_fix)

    # 普查 / 登记
    c_pref = man.get("mutant_register_order", [])
    c_last = next((f["file"] for f in reversed(fams) if f["file"] in c_pref), fams[-1]["file"] if fams else None)
    if c_last is not None:
        last = c_last

        def m_unregister(c, r=last):
            c.manifest["families"] = [f for f in c.manifest["families"] if f["file"] != r]
        M.append(("C1", f"清单漏登同族 {last}", m_unregister, (f"{last} 满足 F1–F3", f"{last} 满足")))
    if man.get("not_family"):
        nf0 = man["not_family"][0]["file"]
        M.append(("C2", f"清单漏登非族 {nf0}", lambda c: c.manifest.__setitem__("not_family", []), (f"{nf0} 满足 F1–F3", f"{nf0} 满足")))
    if c_last is not None:
        bl = os.path.basename(c_last)

        def m_unread_all(c, bl=bl):
            for k in c.src:
                c.src[k] = c.src[k].replace(bl, "zz_mut.json")
        M.append(("C3", f"scripts/ scenes/ 不再提 {bl}（别的门禁还读它不算 F3）", m_unread_all, (f"{last} 登为同族，但 scripts/ scenes/ 已不读它", last)))
    for i, spec in enumerate(fams):  # ④ 只剩注释 / 更长的文件名里带着它（lane seq6）
        rel, bn = spec["file"], os.path.basename(spec["file"])
        left = sum(1 for r, s in ctx.src.items() if bn in _unread(s, r, bn))

        def m_unread_code(c, bn=bn):
            for k in c.src:
                c.src[k] = _unread(c.src[k], k, bn)
        M.append((f"C{4 + i}", f"代码不再读 {bn}（注释 / 更长的文件名里还剩 {left} 个文件提到它）", m_unread_code,
                  (f"{rel} 登为同族，但 scripts/ scenes/ 已不读它", rel)))
    k = 4 + len(fams)
    for w in man.get("watch", []):  # ⑥ 候补被接回运行时（lane seq6）
        r = w["file"]

        def m_read(c, r=r):
            c.src["scripts/zz_mut_reader.gd"] = f'const _P := "res://{r}"\n'

        def m_key(c, r=r):
            next(x for x in c.manifest["watch"] if x["file"] == r)["key"] = "id"
        M.append((f"C{k}", f"scripts/ 新读 {r}（候补接回运行时）", m_read, (f"{r} 已被运行时读", r)))
        M.append((f"C{k + 1}", f"候补 {r} 的 key 改回 id（按 id 认不出图）", m_key, (f"watch {r} 按 key=id 已不满足", f"watch {r}")))
        k += 2

    def m_goods(c):
        c.files["data/goods.json"]["goods"][0].pop("name")
        c.files["data/goods.json"]["goods"][1]["base_value"] = "贵"

    def m_chars(c):
        c.files["data/characters.json"]["characters"][0].pop("name")
        c.files["data/characters.json"]["characters"][0]["relations"].append({"id": "nobody_seq4", "rel": "变异"})

    def m_crew(c):
        c.files["data/crew.json"]["candidates"][0]["role"] = "no_such_role"
        c.files["data/crew.json"]["candidates"][1].pop("wage")

    # (编号, 说明, 变异, 期望：None = 与基线一致（不误红）；否则 (必须同处一行的 ✗ 片段, 只许红在哪些文件的前缀))
    M += [
        ("N1", "非族 goods.json 删 name、base_value 改字符串", m_goods, None),
        ("N2", "非族 characters.json 删 name、relations 加悬空 id", m_chars, None),
        ("N3", "非族 crew.json role 改悬空、删 wage", m_crew, None),
    ]
    deep = {f["file"] for f in fams} | {w["file"] for w in man.get("watch", [])} | {"data/goods.json", "data/characters.json", "data/crew.json"}
    for mid, desc, fn, want in M:
        c = copy.copy(ctx)
        c.files, c.manifest, c.src, c.py = dict(ctx.files), copy.deepcopy(ctx.manifest), dict(ctx.src), dict(ctx.py)
        for rel in sorted(deep):  # 只深拷变异会改的文件，其余共用（只读）
            c.load(rel)
            c.files[rel] = copy.deepcopy(c.files[rel])
        try:
            fn(c)
            miss = None
        except (KeyError, IndexError, StopIteration, AttributeError, TypeError) as e:
            miss = f"{type(e).__name__} {e}"  # 数据里那处已经不是变异锚的样子（可能缺陷本来就在，下面照判）
        got = run(c, verbose=False)
        new = [f for f in got if f not in base]
        if want is None:
            good = got == base and miss is None
            res.append((good, f"{mid} {desc} → 与基线一致（{len(got)} 项），不误红" + ("" if got == base else f"；多出：{new[:3]}")
                        + (f"；变异没落上（{miss}）——照新数据改这一格" if miss else "")))
        else:
            frag, prefix = want
            frags = frag if isinstance(frag, list) else [frag]
            # 判「期望的 ✗ 在」而不是「期望的 ✗ 是新的」：真数据本来就带这处缺陷时，零节不跟着红，缺陷只在正文报一次
            hit = [f for f in got if all(x in f for x in frags)]
            stray = [f for f in new if not f.startswith(prefix)]
            good = bool(hit) and not stray
            res.append((good, f"{mid} {desc} → 红 {len(new)} 项" + (f"：{hit[0]}" if hit else f"；缺含「{'」+「'.join(frags)}」的 ✗")
                        + (f"（变异没落上：{miss}——照新数据改这一格）" if miss and not hit else "")
                        + (f"；别的文件也红了：{stray[:3]}" if stray else "")))
    rest = sorted(f["file"] for f in fams if not any(w and isinstance(w[1], str) and w[1].startswith(f["file"]) for _, _, _, w in M))
    if rest:
        res.append((False, f"同族 {rest} 没有变异格（通用格全落不上？见上面「锚落不上」）"))
    return res


def main():
    ctx = Ctx(ROOT)
    print(f"data/ 同族结构门禁（清单 {MANIFEST}）")
    if "--survey" in sys.argv[1:]:
        print_survey(ctx)
        return 0
    res = mutants(ctx)
    bad = [line for good, line in res if not good]
    print("== 零、变异自检（内存里改数据 / 清单 / 源码，逐格跑下面同一套检查）")
    if "--mutants" in sys.argv[1:]:
        print("\n".join(("  ✓ " if good else "  ✗ ") + line for good, line in res))
        print(f"结果：{'全部通过' if not bad else f'{len(bad)} 项问题'}（变异 {len(res)} 格）")
        return 1 if bad else 0
    n_red = sum(1 for good, line in res if " → 红 " in line)
    if not bad:
        print(f"  ✓ {len(res)} 格全对：同族变异 {n_red} 格判红且只红在该文件，非族 / 对照 {len(res) - n_red} 格与基线一致（逐格见 --mutants）")
    for line in bad:
        print("  ✗ 变异自检 " + line)
    fails = bad + run(ctx)
    print("结果：全部通过" if not fails else f"结果：{len(fails)} 项问题")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
