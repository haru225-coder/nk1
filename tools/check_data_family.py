#!/usr/bin/env python3
"""data/ 同族文件结构门禁（lane seq4）：scenes.json 那一套结构检查参数化成多文件适用，文件清单在 tools/data_family.json。

同族判据（F1–F3 脚本自动普查，F4 人判、写进清单）：
  F1 顶层有一张「条目表」：dict 的列表，每条都有非空字符串 id 且不重复
  F2 条目里有字段指向同表的 id（非空字符串值过半落在本表 id 里），即条目之间成一张图
  F3 游戏运行时读它：scripts/ 或 scenes/ 里写了这个文件名
  F4 图有入口，「从入口走不到 = 孤儿」有定义（清单 roots）
data/ 下满足 F1–F3 的文件必须登在清单 families（同族）或 not_family（写明 F4 为何不成立）之一，漏登即红；
登了同族却不再满足 F1/F2、登了非族却已不是候选，都判失效。

对 families 里每个文件跑四项（与 scenes.json 同一套）：
  一、字段齐备 / 类型：顶层键；按 kinds 首个命中的「形」查必填字段（`名?` 为可选）、类型、未登记字段；
      嵌套列表按 shapes 再查一层。类型写法：str / int / num（int 或 float）/ bool / dict / list / null / any /
      list<str> / list<@shape名>，`|` 分隔多选
  二、引用 id 存在：refs 每一路（路径写法：`a.b` 取键、`a[]` 遍历列表、`a{}` 取字典的键）的值必须落在 to 的并集里：
      {"self": true} 本表 id；{"file", "path"} 别的数据文件；{"gd_const": 文件, "name": 常量} GDScript 常量里的字符串；
      {"py_const": 文件, "name": 常量} Python 模块级字面量里的字符串（ast 取，不执行）；edge=true 的一路是图的边
  三、自引用覆盖：F2 普查出的每条自引用路径，要么是 refs 里的一路（不成边的写 why 说为什么），要么登在 not_edges（写原因），
      新添的引用字段不许漏管
  四、无孤儿：从 roots 出发沿 edge 路（undirected=true 时按无向）走不到的条目 = 孤儿；形上写了 orphan_ok 的放过，
      known_orphans 登记的基线放过（登记了却已可达 / 已不在表里即判失效，基线只许缩）
      roots 写法：{"path"} 本文件顶层键；{"file", "path"} 别的数据文件；{"gd_calls": 函数名} scripts/ 里该函数的字符串字面量实参；
      {"gd_regex": 文件, "pattern"} 源码里正则第 1 组；"must": true 的入口取不到 / 不在表里即红
      refs 的 "edge_if"（同 to 的来源写法）：值落在该集合里才成边（scenes 的港卡门只有 PROLOGUE_ONLY_FACILITIES 直进同名幕）；
      known_orphans 每组写 "ids" 列表，或 "from": {"py_const": 文件, "name": 常量} 与别的门禁共用一份基线（scenes 用 lane seq3 的
      verify_story_data.SCENE_ARCHIVE），来源取不到即红
  零、变异自检：每次先跑（GATES §五.3）——内存里逐格改数据 / 清单 / 源码跑上面同一套检查，同族那几格须红且只红在该文件，
      非族文件（goods / characters / crew）改了须与基线逐条一致；`--mutants` 逐格打印

接入（将来 data/ 新增同族文件）：普查会先红「F1–F3 成立却没登记」。在 tools/data_family.json 的 families 加一条
  file / table / id / top / kinds（至少一个 when 为 {} 的兜底形）/ shapes / refs（自引用那路 edge=true）/ roots / known_orphans，
  跑 `python3 tools/check_data_family.py` 把现存违规逐条修掉或登进 known_orphans（写原因）；零节会报「同族 X 没有变异格」，
  在 mutants() 里给它补删必填 / 悬空 / 孤儿三格（期望前缀写该文件），`--mutants` 逐格看过；
  图没有入口的（如 characters.json 的 relations）登 not_family 写明原因。

  python3 tools/check_data_family.py              # 门禁：普查覆盖 + 各同族文件四项；有问题退 1
  python3 tools/check_data_family.py --survey     # 另打 data/ 全部 json 的普查表（markdown）
  python3 tools/check_data_family.py --mutants    # 零节逐格打印（零节每次都跑，这里只是展开）
"""
import ast, copy, glob, json, os, re, sys
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


def py_const(ctx, rel, name):
    """Python 源文件模块级 `NAME = {字面量}` → 其中的字符串集合（ast 取，不执行）。取不到给 None。"""
    if rel not in ctx.py:
        p = os.path.join(ctx.root, rel)
        ctx.py[rel] = open(p, encoding="utf-8").read() if os.path.isfile(p) else None
    if ctx.py[rel] is None:
        return None
    for node in ast.parse(ctx.py[rel]).body:
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


def survey_file(ctx, rel):
    data = ctx.load(rel)
    base = os.path.basename(rel)
    readers = sorted(r for r, s in ctx.src.items() if base in s)
    info = {"file": rel, "readers": readers, "tables": [], "f1": None, "self_refs": {}}
    if isinstance(data, dict):
        for key, v in data.items():
            if isinstance(v, list) and v and all(isinstance(e, dict) for e in v):
                ids = [e.get("id") for e in v]
                f1 = all(isinstance(i, str) and i for i in ids) and len(set(ids)) == len(ids)
                info["tables"].append((key, len(v), "list", f1))
                if f1 and info["f1"] is None:
                    idset, acc = set(ids), {}
                    for e in v:
                        for p, x in leaf_paths(e):
                            if p != "id" and isinstance(x, str) and x:
                                acc.setdefault(p, []).append(x)
                    info["f1"] = key
                    info["self_refs"] = {p: (sum(x in idset for x in xs), len(xs)) for p, xs in acc.items()
                                         if 2 * sum(x in idset for x in xs) > len(xs)}
            elif isinstance(v, (list, dict)) and key != "meta":
                info["tables"].append((key, len(v), "list" if isinstance(v, list) else "dict", False))
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

    for rel, spec in fam.items():
        data = ctx.load(rel)
        out.append(f"== {rel}")
        if data is None:
            ok(False, "", [f"{rel} 登在 families，文件不在"])
            continue
        sv = surveys.get(rel) or survey_file(ctx, rel)
        ok(sv["f1"] == spec["table"] and bool(sv["self_refs"]), f"F1 / F2 成立（表 {spec['table']}，自引用 {'、'.join(sv['self_refs'])}）",
           [f"{rel} 登为同族，但普查已不满足 F1 / F2（首张 id 表 {sv['f1']!r}，自引用 {sv['self_refs']}）——改清单或移出 families"])
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
        errs, counts, edges = [], [], {i: set() for i in idset}
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
                        if spec.get("undirected"):
                            edges[v].add(eid)
            counts.append(f"{ref['path']} {n}")
        ok(not errs, "二、引用 id 存在：" + "、".join(counts) + " 全部落地", errs)

        # 三、自引用覆盖
        covered = {r["path"] for r in spec.get("refs", [])} | {r["path"] for r in spec.get("not_edges", [])}
        bare = lambda p: re.sub(r"\{\}$", "", p)
        miss = [p for p in sv["self_refs"] if p not in covered and bare(p) not in covered]
        stale = [r["path"] for r in spec.get("not_edges", []) if r["path"] not in sv["self_refs"]]
        ok(not miss and not stale, f"三、自引用覆盖：普查 {len(sv['self_refs'])} 路都已登记（refs {len(spec.get('refs', []))} 路，其中成边 {len([r for r in spec.get('refs', []) if r.get('edge')])} 路；not_edges {len(spec.get('not_edges', []))} 路）",
           [f"{rel} 字段 {p} 有 {sv['self_refs'][p][0]}/{sv['self_refs'][p][1]} 个值是本表 id，却没登 refs 也没登 not_edges" for p in miss]
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
    sim = {}
    for p in ("tools/simulate_run.py", "tools/simulate_endgame.py"):
        with open(os.path.join(ctx.root, p), encoding="utf-8") as f:
            sim[p] = f.read()
    print("| 文件 | 顶层表（`[]` 列表 / `{}` 字典，条目数；meta 不计） | 运行时读（scripts/ scenes/） | sim 读 | F1 id 表 | F2 自引用（命中/值数） | 判定 |")
    print("|---|---|---|---|---|---|---|")
    for rel in ctx.data_files():
        s = survey_file(ctx, rel)
        data = ctx.load(rel)
        tabs = "、".join(f"{k}{'{}' if t == 'dict' else '[]'} {n}" for k, n, t, _ in s["tables"]) or "—"
        readers = "、".join(os.path.splitext(os.path.basename(r))[0] for r in s["readers"]) or "**不读**"
        simr = "、".join(os.path.basename(p)[:-3] for p, src in sim.items() if os.path.basename(rel) in src) or "—"
        f2 = "、".join(f"`{p}` {a}/{b}" for p, (a, b) in s["self_refs"].items()) or "—"
        verdict = "**同族**" if rel in fam else "近亲·非族（F4 不成立）" if rel in nf else "非族"
        print(f"| `{rel}` | {tabs} | {readers} | {simr} | {s['f1'] or '—'} | {f2} | {verdict} |")


# ── 变异自证 ─────────────────────────────────────────────
def mutants(ctx):
    """内存变异逐格跑 run()，返回 [(过否, 一行)]。每次门禁都先跑（零节），--mutants 逐格打印。"""
    base = run(ctx, verbose=False)
    fam = {f["file"] for f in ctx.manifest["families"]}

    def ent(c, rel, table, eid):
        return next(e for e in c.files[rel][table] if e.get("id") == eid)

    def m_del(rel, table, eid, key):
        return lambda c: ent(c, rel, table, eid).pop(key)

    def m_set(rel, table, eid, key, val):
        return lambda c: ent(c, rel, table, eid).__setitem__(key, val)

    def m_isolate_champa(c):
        for p in c.files["data/ports.json"]["ports"]:
            p["connections"] = [x for x in p["connections"] if x != "champa"]
        ent(c, "data/ports.json", "ports", "champa")["connections"] = []

    def m_add_orphan(c):
        c.files["data/scenes.json"]["scenes"].append({"id": "zz_seq4_orphan", "chapter": "ch1", "title": "变异", "location": "quanzhou",
                                                    "body": "变异", "choices": [{"label": "回港", "next": "quanzhou", "effects": {}}]})

    def m_known_reach(c):
        ent(c, "data/scenes.json", "scenes", "monk")["choices"].append({"label": "变异", "next": "shipyard"})

    def m_unregister_ports(c):
        c.manifest["families"] = [f for f in c.manifest["families"] if f["file"] != "data/ports.json"]

    def m_unregister_chars(c):
        c.manifest["not_family"] = []

    def m_new_selfref(c):
        ent(c, "data/ports.json", "ports", "quanzhou")["rival"] = "fuzhou"
        ent(c, "data/ports.json", "ports", "fuzhou")["rival"] = "quanzhou"

    def m_root_drift(c):
        c.src["scripts/GameState.gd"] = c.src["scripts/GameState.gd"].replace('var last_port: String = "quanzhou"', 'var last_port: String = "lost_port"')

    def m_const_gone(c):
        c.src["scripts/Main.gd"] = c.src["scripts/Main.gd"].replace("const REMAPPED_FACILITIES", "const REMAPPED_FACILITY_IDS")

    def m_prologue_gone(c):
        c.src["scripts/Main.gd"] = c.src["scripts/Main.gd"].replace("const PROLOGUE_ONLY_FACILITIES", "const PROLOGUE_FACILITIES")

    def m_archive_gone(c):
        py_const(c, "tools/verify_story_data.py", "SCENE_ARCHIVE")
        c.py["tools/verify_story_data.py"] = c.py["tools/verify_story_data.py"].replace("SCENE_ARCHIVE = {", "SCENE_ARCHIVED = {")

    def m_unread_ports(c):
        for k in c.src:
            if k.startswith(("scripts/", "scenes/")):
                c.src[k] = c.src[k].replace("ports.json", "harbors.json")

    def m_goods(c):
        c.files["data/goods.json"]["goods"][0].pop("name")
        c.files["data/goods.json"]["goods"][1]["base_value"] = "贵"

    def m_chars(c):
        c.files["data/characters.json"]["characters"][0].pop("name")
        c.files["data/characters.json"]["characters"][0]["relations"].append({"id": "nobody_seq4", "rel": "变异"})

    def m_crew(c):
        c.files["data/crew.json"]["candidates"][0]["role"] = "no_such_role"
        c.files["data/crew.json"]["candidates"][1].pop("wage")

    # (编号, 说明, 变异, 期望：None = 与基线一致（不误红）；否则 (必须出现的 ✗ 片段, 只许红在哪些文件的前缀))
    M = [
        ("S1", "scenes.json monk 删必填 title", m_del("data/scenes.json", "scenes", "monk", "title"), ("monk 缺必填字段 title", "data/scenes.json")),
        ("S2", "scenes.json monk 删必填 choices", m_del("data/scenes.json", "scenes", "monk", "choices"), ("monk 缺必填字段 choices", "data/scenes.json")),
        ("S3", "scenes.json monk.body 改成数字", m_set("data/scenes.json", "scenes", "monk", "body", 123), ("monk.body 类型应为 str", "data/scenes.json")),
        ("S4", "scenes.json monk 首个选项 next 改悬空", lambda c: ent(c, "data/scenes.json", "scenes", "monk")["choices"][0].__setitem__("next", "nowhere_seq4"),
         ("'nowhere_seq4' 悬空", "data/scenes.json")),
        ("S5", "scenes.json monk 首个选项多一个拼错的 nxt", lambda c: ent(c, "data/scenes.json", "scenes", "monk")["choices"][0].__setitem__("nxt", "dock"),
         ("未登记字段 nxt", "data/scenes.json")),
        ("S6", "scenes.json 新增一幕没人指向", m_add_orphan, ("zz_seq4_orphan 是孤儿", "data/scenes.json")),
        ("S7", "scenes.json 登记的留档孤儿 shipyard 被接回主线", m_known_reach, ("known_orphans 登了 shipyard，它已从入口可达", "data/scenes.json")),
        ("S8", "Main.gd REMAPPED_FACILITIES 改名", m_const_gone, ("取不到", "data/scenes.json")),
        ("S9", "Main.gd PROLOGUE_ONLY_FACILITIES 改名", m_prologue_gone, ("成边条件", "data/scenes.json")),
        ("S10", "verify_story_data.SCENE_ARCHIVE 改名（共用基线断了）", m_archive_gone, ("known_orphans 的来源", "data/scenes.json")),
        ("P1", "ports.json champa 删必填 connections", m_del("data/ports.json", "ports", "champa", "connections"), ("champa 缺必填字段 connections", "data/ports.json")),
        ("P2", "ports.json fuzhou 删必填 lat", m_del("data/ports.json", "ports", "fuzhou", "lat"), ("fuzhou 缺必填字段 lat", "data/ports.json")),
        ("P3", "ports.json guangzhou 连线 champa 拼错", lambda c: ent(c, "data/ports.json", "ports", "guangzhou").__setitem__("connections", ["zhangzhou", "quanzhou", "champaa"]),
         ("'champaa' 悬空", "data/ports.json")),
        ("P4", "ports.json champa 所有熟路连线拆掉", m_isolate_champa, ("champa 是孤儿", "data/ports.json")),
        ("P5", "ports.json 新添自引用字段 rival 没登记", m_new_selfref, ("未登记字段 rival", "data/ports.json")),
        ("P6", "GameState.last_port 缺省改成不存在的港", m_root_drift, ("入口", "data/ports.json")),
        ("C1", "清单漏登同族 ports.json", m_unregister_ports, ("data/ports.json 满足 F1–F3", "data/ports.json 满足")),
        ("C2", "清单漏登非族 characters.json", m_unregister_chars, ("data/characters.json 满足 F1–F3", "data/characters.json 满足")),
        ("C3", "scripts/ scenes/ 不再读 ports.json（别的门禁还读它不算 F3）", m_unread_ports, ("data/ports.json 登为同族，但 scripts/ scenes/ 已不读它", "data/ports.json")),
        ("N1", "非族 goods.json 删 name、base_value 改字符串", m_goods, None),
        ("N2", "非族 characters.json 删 name、relations 加悬空 id", m_chars, None),
        ("N3", "非族 crew.json role 改悬空、删 wage", m_crew, None),
    ]
    res = []
    for mid, desc, fn, want in M:
        c = copy.copy(ctx)
        c.files, c.manifest, c.src, c.py = copy.deepcopy(ctx.files), copy.deepcopy(ctx.manifest), dict(ctx.src), dict(ctx.py)
        for rel in ("data/goods.json", "data/characters.json", "data/crew.json"):
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
            # 判「期望的 ✗ 在」而不是「期望的 ✗ 是新的」：真数据本来就带这处缺陷时，零节不跟着红，缺陷只在正文报一次
            hit = [f for f in got if frag in f]
            stray = [f for f in new if not f.startswith(prefix)]
            good = bool(hit) and not stray
            res.append((good, f"{mid} {desc} → 红 {len(new)} 项" + (f"：{hit[0]}" if hit else f"；缺含「{frag}」的 ✗")
                        + (f"（变异没落上：{miss}——照新数据改这一格）" if miss and not hit else "")
                        + (f"；别的文件也红了：{stray[:3]}" if stray else "")))
    rest = sorted(f for f in fam if not any(w and w[1].startswith(f) for _, _, _, w in M))
    if rest:
        res.append((False, f"同族 {rest} 没有变异格（新接入的同族文件要在 mutants() 里补删必填 / 悬空 / 孤儿三格）"))
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
