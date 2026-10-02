#!/usr/bin/env python3
"""存档健壮性回归门禁（纯 Python，不跑 Godot）。

锁住 Astra 审计 H1/H2 的修复（6207d31 + lane-h1h2 46a7c17）：
  H1 坏分区：calendar/economy/fleet/crew/state 非对象（字符串/数组/null/数字）、
     日期缺失或越界、ships 非数组、hired 条目非 id 字符串（v4 起只存候选 id；lane w26-k1）、
     强类型字段错型、version 非数字，
     一律在 _read 判坏档，_read_slot 自然退 .bak；任何输入都不得抛脚本错误。
  H2 只剩 .bak：has_save 认副抄，save_label / slot_source 走同一口径，
     题签可读，任何路径都不对空 FileAccess 调 get_as_text。
  SV 结构版本（lane sv）：save_schema 缺省为 v1；低于本版走 _migrate_vN_to_vN+1 链且链不断档，
     load_game 迁完回写并留原件 <档名>.v<N>；高于本版（或旧头 version 过新）判 future，
     明确拒读、不退 .bak；save_schema 非正整数按坏档退 .bak。
  FX6 人物志已识（lane fx6）：save_schema v3 起 state.met_ids 入档；给了却不是数组即判坏档，
     迁移链末级（v2→v3）摘掉必红；「新版档」fixture 取 SAVE_SCHEMA + 1，不写死。

做法：从 SaveLoad.gd 抽取守卫、体检规则与调用顺序；从四个内核单例与 GameState 的
from_dict 抽取强类型赋值（Godot 4.6 实测：数值/布尔互转可行，Dictionary/Array/String
须同型，int()/float() 拒 null/数组/对象）。据此建「源码驱动」的行为模型，用可复现的
good/bad fixture 在临时目录里跑。体检或守卫被注释掉时模型随之退化——漏判坏档、
抛脚本错误或读不到副抄——门禁转红。另带变异自检：若干「注释掉兜底」的变体必须全部判红。

用法：
  python3 tools/verify_save_robustness.py                 # 查 scripts/core/SaveLoad.gd
  python3 tools/verify_save_robustness.py --source X.gd   # 查别的版本（如 git show 旧版）
  python3 tools/verify_save_robustness.py --dump-fixtures DIR  # 写出 fixture 供 Godot 手测
"""
import json, os, re, sys, tempfile, pathlib
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
from src_probe import has_tok  # 按名认函数的探查一律经 tools/src_probe.py（lane cs15：不按前缀认名）
SAVELOAD = os.path.join(ROOT, "scripts", "core", "SaveLoad.gd")
PARTS = (("calendar", "Calendar"), ("economy", "Economy"), ("fleet", "Fleet"), ("crew", "Crew"))
FROM_DICT_SRC = {
    "calendar": "scripts/core/Calendar.gd",
    "economy": "scripts/core/Economy.gd",
    "fleet": "scripts/core/Fleet.gd",
    "crew": "scripts/core/Crew.gd",
    "state": "scripts/GameState.gd",
}
# v4 起 crew.hired 只存候选 id（wave23-a1）；名册职员键与候选 id 从这份 JSON 读
CANDIDATE_SRC = "data/crew.json"
# _harden_state 读回前清洗的键：不论存档里是什么，喂给 GameState 时都已是合法类型
HARDENED = {"flags", "discoveries_found", "discoveries_reported"}


def func_bodies(src):
    """粗略切分出每个顶格 [static ]func 的函数体（按缩进；与 check_symbols.py 同法，lane cs16 起认 static func）"""
    out, cur, body = {}, None, []
    for ln in src.split("\n"):
        m = re.match(r'^(?:static\s+)?func\s+([A-Za-z_]\w*)', ln)
        if m:
            if cur: out[cur] = "\n".join(body)
            cur, body = m.group(1), []
        elif cur is not None:
            if ln and not ln[0].isspace() and not ln.startswith(("#", ")")):
                out[cur] = "\n".join(body); cur, body = None, []
            else:
                body.append(ln)
    if cur: out[cur] = "\n".join(body)
    return out



def _code_only(src):
    return "\n".join(re.sub(r'#.*$', '', ln) for ln in src.split("\n"))


def _pos(body, pat):
    m = re.search(pat, body)
    return m.start() if m else -1


def _before(body, a, b):
    pa, pb = _pos(body, a), _pos(body, b)
    return pa >= 0 and pb >= 0 and pa < pb


def _live(body):
    """截到第一条函数体顶层 return 为止：其后的代码永远跑不到"""
    mm = re.search(r'^\treturn\b', body, re.M)
    return body[:mm.start()] if mm else body


def _str_list(text):
    return re.findall(r'"([^"]*)"', text)


def _const_list(src, name):
    m = re.search(rf'^const\s+{name}\s*:?=\s*\[([\s\S]*?)\]', _code_only(src), re.M)
    return _str_list(m.group(1)) if m else []


def _const_int(src, name, default=None):
    m = re.search(rf'^const\s+{name}\s*:?=\s*(\d+)', src, re.M)
    return int(m.group(1)) if m else default


# ════════════════════════════════════════════════════════════════════
# 一、从源码抽模型
# ════════════════════════════════════════════════════════════════════

def parse_from_dict(rel):
    """某单例 from_dict 的强类型需求：{键: ("assign", 类型) | ("cast", None) | ("entries_dict", None)}"""
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        return {}
    src = open(path, encoding="utf-8").read()
    types = dict(re.findall(r'^var\s+(\w+)\s*:\s*(\w+)', src, re.M))
    body = _code_only(func_bodies(src).get("from_dict", ""))
    need = {}
    for mm in re.finditer(r'^\t(\w+)\s*=\s*d\.get\("(\w+)"', body, re.M):
        if mm.group(1) in types:
            need.setdefault(mm.group(2), ("assign", types[mm.group(1)]))
    for mm in re.finditer(r'^\tvar\s+\w+\s*:\s*(\w+)\s*=\s*d\.get\("(\w+)"', body, re.M):
        need.setdefault(mm.group(2), ("assign", mm.group(1)))
    for mm in re.finditer(r'\b(?:int|float)\(d\.get\("(\w+)"', body):
        need.setdefault(mm.group(1), ("cast", None))
    # Fleet：for s in ships: s.has(...) —— 条目须为对象
    em = re.search(r'^\t(\w+)\s*=\s*d\.get\("(\w+)"[\s\S]*?for\s+(\w+)\s+in\s+\1\s*:[\s\S]*?\3\.has\(', body, re.M)
    if em:
        need[em.group(2) + "[]"] = ("entries_dict", None)
    return need


# 判坏档的空返回：旧形 return {}，lane sv 起 _inspect 返回 {"status": "missing"/"corrupt"}
RET_BAD = r'return\s*\{\s*(?:"status"\s*:\s*"(?:missing|corrupt)"\s*)?\}'
RET_FUTURE = r'return\s*\{\s*"status"\s*:\s*"future"'
SCHEMA_KEY = "save_schema"


def _const_str(src, name, default=None):
    m = re.search(rf'^const\s+{name}\s*:?=\s*"([^"]*)"', src, re.M)
    return m.group(1) if m else default


def build_model(src):
    fn = {k: _code_only(v) for k, v in func_bodies(src).items()}
    code = _code_only(src)
    m = {"fn": fn, "version": _const_int(src, "VERSION", 0),
         "schema": _const_int(src, "SAVE_SCHEMA"), "schema_key": _const_str(src, "SCHEMA_KEY", SCHEMA_KEY)}

    hs = fn.get("has_save", "")
    m["has_primary"] = has_tok(hs, "_path(slot)") and "file_exists" in hs
    m["has_bak"] = has_tok(hs, "_bak_path(slot)") and "file_exists" in hs

    # lane sv 起守卫都在 _inspect（_read 只是取 data 的薄壳）；旧形仍在 _read
    rd = fn.get("_inspect") or fn.get("_read", "")
    m["read_defined"] = "_read" in fn
    m["read_exists_guard"] = bool(re.search(r'if\s+not\s+FileAccess\.file_exists\(path\)\s*:\s*\n\s*' + RET_BAD, rd))
    m["read_null_guard"] = bool(re.search(r'if\s+(f\s*==\s*null|not\s+f)\s*:\s*\n\s*' + RET_BAD, rd)) \
        and _before(rd, r'f\s*==\s*null|not\s+f\s*:', r'get_as_text')
    m["read_parse_guard"] = bool(re.search(r'\.parse\([^\n]*\)\s*!=\s*OK\s*:[\s\S]*?' + RET_BAD, rd))
    m["read_dict_guard"] = bool(re.search(r'not\s*\(\s*json\.data\s+is\s+Dictionary\s*\)\s*:[\s\S]*?' + RET_BAD, rd))
    isn = fn.get("_is_num", "")
    m["is_num_ok"] = "TYPE_INT" in isn and "TYPE_FLOAT" in isn
    m["version_num_guard"] = m["is_num_ok"] and bool(re.search(
        r'if\s+not\s+_is_num\((\w+)\)\s*:[\s\S]*?' + RET_BAD + r'[\s\S]*?int\(\1\)', rd))
    # —— 结构版本（lane sv）——
    sm = re.search(r'var\s+(\w+)\s*=\s*data\.get\(SCHEMA_KEY,\s*(\w+)\)', rd)
    m["schema_default"] = (int(sm.group(2)) if sm.group(2).isdigit() else None) if sm else None
    m["schema_num_guard"] = bool(sm) and m["is_num_ok"] and bool(re.search(
        rf'if\s+not\s+_is_num\({sm.group(1)}\)\s+or\s+int\({sm.group(1)}\)\s*<\s*1\s*:\s*\n[\s\S]*?' + RET_BAD, rd)) if sm else False
    fm = re.search(r'if\s+([^\n]*):\s*\n(?:\t\t[^\n]*\n)*?\t\t' + RET_FUTURE, rd)
    cond = fm.group(1) if fm else ""
    m["future_status"] = bool(fm)
    m["future_schema"] = bool(re.search(r'\bschema\s*>\s*SAVE_SCHEMA\b', cond))
    m["future_ver"] = bool(re.search(r'\bver\s*>\s*VERSION\b', cond)) \
        or bool(re.search(r'if\s+ver\s*>\s*VERSION\s*:[\s\S]*?' + RET_BAD, rd))
    m["read_version_guard"] = m["future_ver"]
    m["migrates"] = bool(re.search(r'if\s+schema\s*<\s*SAVE_SCHEMA\s*:\s*\n\s*data\s*=\s*_migrate\(data,\s*schema\)', rd)) \
        and _before(rd, r'_migrate\(data', r'_check_partitions\(data\)')
    mg = fn.get("_migrate", "")
    m["chain"] = {int(a): b for a, b in re.findall(
        r'^\t\t\t(\d+)\s*:\s*\n\t\t\t\tout\s*=\s*(_migrate_v\d+_to_v\d+)\(out\)', mg, re.M)}
    m["chain_loop"] = bool(re.search(r'for\s+(\w+)\s+in\s+range\(\w+,\s*SAVE_SCHEMA\)', mg)) \
        and bool(re.search(r'out\[SCHEMA_KEY\]\s*=\s*\w+\s*\+\s*1', mg))
    m["chain_ok"] = m["schema"] is not None and m["chain_loop"] and all(
        m["chain"].get(v) == f"_migrate_v{v}_to_v{v + 1}" and f"_migrate_v{v}_to_v{v + 1}" in fn
        for v in range(1, m["schema"]))
    m["save_writes_schema"] = bool(re.search(r'SCHEMA_KEY\s*:\s*SAVE_SCHEMA', fn.get("save_game", "")))

    # _check_partitions 须在 _read 里调用、坏因非空即判坏档，且排在版本校验之后、return data 之前
    m["read_checks_parts"] = bool(re.search(
        r'var\s+(\w+)\s*:?=\s*_check_partitions\(data\)\s*\n\s*if\s+\1\s*!=\s*""\s*:[\s\S]*?' + RET_BAD, rd)) \
        and _before(rd, r'_check_partitions\(data\)', r'return\s+(?:data\s*$|\{\s*"status"\s*:\s*"ok")')

    # —— _check_partitions 体检规则 ——
    cp = _live(fn.get("_check_partitions", ""))
    rules = {"part_types": [], "required_nums": {}, "ranges": {}, "nums": {}, "dicts": {}, "arrays": {},
             "entries_dict": {}, "values_dict": {}, "values_string": {}, "typed": {}, "roster_checked": False}
    lm = re.search(r'for\s+key\s+in\s+(\w+)\s*(?:\+\s*\[([^\]]*)\])?\s*:\s*\n\s*if\s+data\.has\(key\)\s+and\s+'
                   r'typeof\(data\[key\]\)\s*!=\s*TYPE_DICTIONARY\s*:\s*\n\s*return\s+"', cp)
    if lm:
        rules["part_types"] = _const_list(src, lm.group(1)) + _str_list(lm.group(2) or "")
    var_part = dict(re.findall(r'var\s+(\w+)\s*:\s*Dictionary\s*=\s*_as_dict\(data\.get\("(\w+)"', cp))
    for v, part in var_part.items():
        rm = re.search(rf'for\s+k\s+in\s+\[([^\]]*)\]\s*:\s*\n\s*if\s+not\s+_is_num\({v}\.get\(k\)\)\s*:\s*\n\s*return\s+"', cp)
        if rm and m["is_num_ok"]:
            rules["required_nums"][part] = _str_list(rm.group(1))
        for rg in re.finditer(rf'if\s+int\({v}\["(\w+)"\]\)\s*<\s*(\d+)\s+or\s+int\({v}\["\1"\]\)\s*>\s*(\w+)\.(\w+)\s*:\s*\n\s*return\s+"', cp):
            owner = os.path.join(ROOT, FROM_DICT_SRC.get(rg.group(3).lower(), ""))
            hi = _const_int(open(owner, encoding="utf-8").read(), rg.group(4)) if os.path.isfile(owner) else None
            if hi is not None:
                rules["ranges"].setdefault(part, {})[rg.group(1)] = (int(rg.group(2)), hi)
        bf = re.search(rf'(?:var\s+)?why\s*:?=\s*_bad_fields\({v},\s*(\[[^\]]*\]|\w+),\s*(\[[^\]]*\]|\w+)(?:,\s*(\[[^\]]*\]|\w+))?\)\s*\n'
                       rf'\s*if\s+why\s*!=\s*""\s*:\s*\n\s*return\s', cp)
        if bf:
            def _lst(t):
                if t is None: return []
                return _str_list(t) if t.startswith("[") else _const_list(src, t)
            rules["nums"][part] = _lst(bf.group(1))
            rules["dicts"][part] = _lst(bf.group(2))
            rules["arrays"][part] = _lst(bf.group(3))
        for tm in re.finditer(rf'if\s+{v}\.has\("(\w+)"\)\s*:\s*\n\s*if\s+typeof\({v}\["\1"\]\)\s*!=\s*TYPE_ARRAY\s*:\s*\n\s*return\s+"', cp):
            rules["arrays"].setdefault(part, []).append(tm.group(1))
            em = re.search(rf'for\s+(\w+)\s+in\s+{v}\["{tm.group(1)}"\]\s*:\s*\n\s*if\s+typeof\(\1\)\s*!=\s*TYPE_DICTIONARY\s*:\s*\n\s*return\s+"', cp)
            if em:
                rules["entries_dict"].setdefault(part, []).append(tm.group(1))
        for vm in re.finditer(rf'for\s+(\w+)\s+in\s+_as_dict\({v}\.get\("(\w+)"[^\n]*\)\.values\(\)\s*:\s*\n\s*if\s+typeof\(\1\)\s*!=\s*TYPE_DICTIONARY\s*:\s*\n\s*return\s+"', cp):
            rules["values_dict"].setdefault(part, []).append(vm.group(2))
        for tm in re.finditer(rf'if\s+{v}\.has\("(\w+)"\)\s+and\s+typeof\({v}\["\1"\]\)\s*!=\s*TYPE_(\w+)\s*:\s*\n\s*return\s+"', cp):
            rules["typed"].setdefault(part, {})[tm.group(1)] = tm.group(2)
        # v4：crew.hired 只存候选 id —— 步进各条的值、非 TYPE_STRING 即坏档；
        # 键非职员表 / id 名册查无此人不判坏（按「未雇」对待，见 audit_stale_refs 头注与 Crew.roster 同口径）。
        if part == "crew" and re.search(rf'for\s+\w+\s+in\s+_as_dict\({v}\.get\("hired"[^\n]*\)\.values\(\)\s*:', cp) \
                and re.search(r'typeof\(\w+\)\s*!=\s*TYPE_STRING\s*:\s*\n\s*return\s+"', cp):
            rules["values_string"].setdefault(part, []).append("hired")
            rules["roster_checked"] = True
    bfb = _live(fn.get("_bad_fields", ""))
    if not (has_tok(bfb, "_is_num(part[k])") and "TYPE_DICTIONARY" in bfb and "TYPE_ARRAY" in bfb and m["is_num_ok"]):
        rules["nums"], rules["dicts"], rules["arrays"] = {}, {}, {k: [] for k in rules["arrays"]}
        # ships 等单独写的 TYPE_ARRAY 判断不依赖 _bad_fields，保留
        for tm in re.finditer(r'if\s+(\w+)\.has\("(\w+)"\)\s*:\s*\n\s*if\s+typeof\(\1\["\2"\]\)\s*!=\s*TYPE_ARRAY', cp):
            part = var_part.get(tm.group(1))
            if part: rules["arrays"].setdefault(part, []).append(tm.group(2))
    m["rules"] = rules if m["read_checks_parts"] else None

    rs = fn.get("_read_slot", "")
    rv = fn.get("_resolve", "")
    m["resolve"] = bool(rv) and has_tok(rs, "_resolve(slot)")
    if m["resolve"]:
        # lane sv：_resolve 统一定出 none / primary / bak / future / corrupt
        cut = _pos(rv, r'_inspect\(_bak_path\(slot\)\)')
        pre, post = (rv[:cut], rv[cut:]) if cut >= 0 else (rv, "")
        m["resolve_none"] = bool(re.search(r'if\s+not\s+has_save\(slot\)\s*:\s*\n\s*return\s*\{\s*"source"\s*:\s*"none"', rv))
        m["slot_primary_first"] = _before(rv, r'_inspect\(_path\(slot\)\)', r'_inspect\(_bak_path\(slot\)\)')
        m["slot_bak_fallback"] = bool(re.search(r'"ok"\s*:\s*\n\s*return\s*\{\s*"source"\s*:\s*"bak"', post))
        fut = r'"future"\s*:\s*\n\s*return\s*\{\s*"source"\s*:\s*"future"'
        m["primary_future_stops"] = bool(re.search(fut, pre))
        m["bak_future_reported"] = bool(re.search(fut, post))
    else:
        m["resolve_none"] = False
        m["slot_primary_first"] = _before(rs, r'_read\(_path\(slot\)\)', r'_read\(_bak_path\(slot\)\)') \
            or (has_tok(rs, "_read(_path(slot))") and "_bak_path" not in rs)
        m["slot_bak_fallback"] = bool(re.search(r'if\s+data\.is_empty\(\)\s*:[\s\S]*_read\(_bak_path\(slot\)\)', rs))
        m["primary_future_stops"] = m["bak_future_reported"] = False

    ad = fn.get("_as_dict", "")
    m["as_dict_robust"] = bool(re.search(
        r'return\s+raw\s+if\s+typeof\(raw\)\s*==\s*TYPE_DICTIONARY\s+else\s*\{\}', ad)) \
        or bool(re.search(r'if\s+typeof\(raw\)\s*!=\s*TYPE_DICTIONARY\s*:\s*\n\s*return\s*\{\}', ad))

    lg = fn.get("load_game", "")
    if has_tok(lg, "_read_slot(slot)") or (m["resolve"] and has_tok(lg, "_resolve(slot)")):
        m["load_reader"] = "_read_slot"
    else:
        m["load_reader"] = "_read" if has_tok(lg, "_read(_path(slot))") else None
    m["load_writes_back"] = bool(re.search(
        r'if\s+int\(\w+\["schema"\]\)\s*<\s*SAVE_SCHEMA\s*:\s*\n\s*_write_back_migrated\(', lg)) \
        and _before(lg, r'_write_back_migrated\(', r'\w+\.from_dict\(')
    wb = fn.get("_write_back_migrated", "")
    m["wb_keeps_original"] = bool(re.search(r'var\s+keep\s*:?=\s*"%s\.v%d"\s*%\s*\[path,\s*from_schema\]', wb)) \
        and bool(re.search(r'if\s+not\s+FileAccess\.file_exists\(keep\)\s+and\s+DirAccess\.copy_absolute\(path,\s*keep\)\s*!=\s*OK\s*:'
                           r'\s*\n[^\n]*\n\s*return\s+false', wb)) \
        and _before(wb, r'copy_absolute\(path,\s*keep\)', r'FileAccess\.open\(tmp')
    m["wb_tmp_rename"] = bool(re.search(r'rename_absolute\(tmp,\s*path\)', wb))
    m["load_empty_guard"] = bool(re.search(r'if\s+data\.is_empty\(\)\s*:\s*\n\s*return\s+false', lg)) \
        and _before(lg, r'data\.is_empty\(\)', r'\w+\.from_dict\(')
    m["load_parts"] = {}
    for key, single in PARTS:
        mm = re.search(rf'{single}\.from_dict\((.*)\)\s*$', lg, re.M)
        if not mm:
            m["load_parts"][key] = None
            continue
        arg = mm.group(1)
        m["load_parts"][key] = {"wrapped": arg.startswith("_as_dict(") and f'"{key}"' in arg,
                                "reads_key": f'"{key}"' in arg, "pos": mm.start()}
    m["load_state_wrapped"] = bool(re.search(r'_as_dict\(data\.get\("state"', lg)) \
        or bool(re.search(r'typeof\(\w+\)\s*==\s*TYPE_DICTIONARY', lg))
    m["load_state_hardened"] = bool(re.search(r'GameState\.from_dict\(_harden_state\(', lg))
    parts_pos = [p["pos"] for p in m["load_parts"].values() if p]
    gs = _pos(lg, r'GameState\.from_dict\(')
    m["parts_before_state"] = bool(parts_pos) and gs >= 0 and max(parts_pos) < gs

    sl = fn.get("save_label", "")
    m["label_none_guard"] = bool(re.search(r'if\s+not\s+has_save\(slot\)\s*:\s*\n\s*return\s+"未记"', sl))
    if has_tok(sl, "_read_slot(slot)") or (m["resolve"] and has_tok(sl, "_resolve(slot)")):
        m["label_reader"] = "_read_slot"
    elif has_tok(sl, "_read(_path(slot))"):
        m["label_reader"] = "_read_primary"
    elif re.search(r'FileAccess\.open\(_path\(slot\)', sl):
        m["label_reader"] = "raw_primary"
    else:
        m["label_reader"] = None
    m["label_raw_null_guard"] = bool(re.search(r'if\s+(f\s*==\s*null|not\s+f)\s*:', sl))
    m["label_order"] = _before(sl, r'has_save\(slot\)', r'_read_slot\(slot\)|_resolve\(slot\)|_read\(|FileAccess\.open')
    m["label_future"] = bool(re.search(r'if\s+\w+\["source"\]\s*==\s*"future"\s*:\s*\n\s*return\s+"新版所记"', sl))
    m["label_empty_guard"] = bool(re.search(r'if\s+data\.is_empty\(\)\s*:\s*\n\s*return\s+"卷页损了"', sl))
    m["label_str"] = bool(re.search(r'return\s+str\(data\.get\("label"', sl))

    ss = fn.get("slot_source", "")
    m["source_ok"] = (bool(re.search(r'if\s+not\s+has_save\(slot\)\s*:\s*\n\s*return\s+"none"', ss))
                      and _before(ss, r'_read\(_path\(slot\)\)', r'_read\(_bak_path\(slot\)\)')
                      and all(t in ss for t in ('"primary"', '"bak"', '"corrupt"')))
    if m["resolve"] and re.search(r'return\s+str\(_resolve\(slot\)\["source"\]\)', ss):
        m["source_ok"] = m["resolve_none"] and m["slot_primary_first"] \
            and all(t in rv for t in ('"primary"', '"bak"', '"corrupt"', '"future"'))

    m["scene_via_slot"] = has_tok(fn.get("saved_scene", ""), "_read_slot(slot)")
    m["chained_open"] = bool(re.search(r'FileAccess\.open\([^)]*\)\s*\.\s*get_as_text', code))
    m["from_dict"] = {part: parse_from_dict(rel) for part, rel in FROM_DICT_SRC.items()}
    return m


# ════════════════════════════════════════════════════════════════════
# 二、按模型模拟 GDScript 行为
# ════════════════════════════════════════════════════════════════════

class ScriptError(Exception):
    """模拟 GDScript 运行时脚本错误（空引用 / 类型不符）"""





def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _gd_type(v):
    if v is None: return "Nil"
    if isinstance(v, bool): return "bool"
    if isinstance(v, int): return "int"
    if isinstance(v, float): return "float"
    if isinstance(v, str): return "String"
    if isinstance(v, list): return "Array"
    return "Dictionary"


def _assignable(v, typ):
    """Godot 4.6 实测：int/float/bool 三者互转可行；Dictionary/Array/String 须同型；Nil 一律不行"""
    t = _gd_type(v)
    if typ in ("int", "float", "bool"):
        return t in ("int", "float", "bool")
    if typ in ("Dictionary", "Array", "String"):
        return t == typ
    return True


def _gd_int(v):
    if isinstance(v, (bool, int, float)): return int(v)
    if isinstance(v, str):
        mm = re.match(r'\s*-?\d+', v)
        return int(mm.group(0)) if mm else 0
    raise ScriptError(f"int() 收到 {_gd_type(v)}")


_TYPE_OK = {"BOOL": lambda v: isinstance(v, bool), "STRING": lambda v: isinstance(v, str),
            "INT": lambda v: isinstance(v, int) and not isinstance(v, bool), "FLOAT": lambda v: isinstance(v, float),
            "DICTIONARY": lambda v: isinstance(v, dict), "ARRAY": lambda v: isinstance(v, list)}


def check_partitions(rules, data):
    """_check_partitions 的镜像：按源码抽到的规则体检；返回坏因或空串"""
    for key in rules["part_types"]:
        if key in data and not isinstance(data[key], dict):
            return f"{key} 分区不是对象"
    for part in ("calendar", "economy", "fleet", "crew", "state"):
        d = data.get(part, {})
        d = d if isinstance(d, dict) else {}
        if d and part in rules["required_nums"]:
            for k in rules["required_nums"][part]:
                if not _is_num(d.get(k)):
                    return f"{part}.{k} 缺失或不是数字"
            for k, (lo, hi) in rules["ranges"].get(part, {}).items():
                if not (lo <= int(d[k]) <= hi):
                    return f"{part}.{k} 越界"
        for k in rules["nums"].get(part, []):
            if k in d and not _is_num(d[k]): return f"{part}.{k} 不是数字"
        for k in rules["dicts"].get(part, []):
            if k in d and not isinstance(d[k], dict): return f"{part}.{k} 不是对象"
        for k in rules["arrays"].get(part, []):
            if k in d and not isinstance(d[k], list): return f"{part}.{k} 不是数组"
        for k in rules["entries_dict"].get(part, []):
            if k in d and any(not isinstance(x, dict) for x in d[k]): return f"{part}.{k} 含非对象条目"
        for k in rules["values_dict"].get(part, []):
            sub = d.get(k, {})
            if isinstance(sub, dict) and any(not isinstance(x, dict) for x in sub.values()):
                return f"{part}.{k} 含非对象条目"
        for k in rules["values_string"].get(part, []):
            sub = d.get(k, {})
            if isinstance(sub, dict):
                if any(not isinstance(x, str) for x in sub.values()):
                    return f"{part}.{k} 含非字符串条目（v4 起只存候选 id）"
        for k, t in rules["typed"].get(part, {}).items():
            if k in d and not _TYPE_OK.get(t, lambda v: True)(d[k]):
                return f"{part}.{k} 类型不符"
    return ""


def feed_from_dict(m, part, d):
    """模拟 X.from_dict(d)：按单例源码的强类型赋值逐键检查"""
    for key, (kind, typ) in m["from_dict"].get(part, {}).items():
        if key.endswith("[]"):
            base = key[:-2]
            if isinstance(d.get(base), list) and any(not isinstance(x, dict) for x in d[base]):
                raise ScriptError(f"{part}.{base} 条目非对象却调 .has()")
            continue
        if key not in d or (part == "state" and key in HARDENED and m["load_state_hardened"]):
            continue
        v = d[key]
        if kind == "assign" and not _assignable(v, typ):
            raise ScriptError(f"{part}.{key}：{_gd_type(v)} 赋给 {typ}")
        if kind == "cast" and _gd_type(v) in ("Nil", "Array", "Dictionary"):
            raise ScriptError(f"{part}.{key}：int()/float() 收到 {_gd_type(v)}")


class Sim:
    def __init__(self, model, root):
        self.m, self.root = model, root

    def path(self, slot): return os.path.join(self.root, f"save_{slot}.json")
    def bak(self, slot): return self.path(slot) + ".bak"

    def has_save(self, slot):
        return (self.m["has_primary"] and os.path.exists(self.path(slot))) or \
               (self.m["has_bak"] and os.path.exists(self.bak(slot)))

    def _open_text(self, p, null_guard):
        if not os.path.exists(p):
            if null_guard: return None
            raise ScriptError("对空 FileAccess 调 get_as_text")
        with open(p, encoding="utf-8") as f:
            return f.read()

    def inspect(self, p):
        """_inspect 的镜像：{"status": missing/corrupt/future/ok, "data", "schema"}"""
        m = self.m
        bad = {"status": "corrupt"}
        if not m["read_defined"]:
            raise ScriptError("_read 未定义")
        if m["read_exists_guard"] and not os.path.exists(p):
            return {"status": "missing"}
        text = self._open_text(p, m["read_null_guard"])
        if text is None:
            return bad
        try:
            data = json.loads(text)
        except ValueError:
            if m["read_parse_guard"]: return bad
            raise ScriptError("JSON 解析失败后仍取 json.data")
        if not isinstance(data, dict):
            if m["read_dict_guard"]: return bad
            raise ScriptError("顶层非对象赋给 Dictionary")
        ver_raw = data.get("version", 0)
        if m["version_num_guard"] and not _is_num(ver_raw):
            return bad
        schema = None
        if m["schema"] is not None and m["schema_default"] is not None:
            s_raw = data.get(m["schema_key"], m["schema_default"])
            if m["schema_num_guard"] and (not _is_num(s_raw) or _gd_int(s_raw) < 1):
                return bad
            schema = _gd_int(s_raw)
        ver = _gd_int(ver_raw)
        if (m["future_schema"] and schema is not None and schema > m["schema"]) \
                or (m["future_ver"] and ver > m["version"]):
            return {"status": "future", "schema": schema} if m["future_status"] else bad
        if schema is not None and schema < m["schema"] and m["migrates"]:
            if not m["chain_ok"] or schema < 1:
                return bad  # 迁移链断档：_migrate 报错返回空表
            data = dict(data)
            data[m["schema_key"]] = m["schema"]
            if schema < 4 <= m["schema"]:
                data = dict(data)
                data["_from_v3"] = True  # 模拟 _migrate_v3_to_v4 经 Crew.candidate_def 收掉查无此人的快照
        if m["rules"] is not None:
            why = check_partitions(m["rules"], data)
            if why and not (data.pop("_from_v3", False) and why.startswith("crew.")):
                return bad  # v3 迁移已收掉 hired 里名册查无的格（crew.* 一条不判坏）
        data.pop("_from_v3", None)
        return {"status": "ok", "data": data, "schema": schema}

    def read(self, p):
        return self.inspect(p).get("data", {})

    def resolve(self, slot):
        """_resolve 的镜像：(source, data, 读自哪份, 原结构版本)"""
        m = self.m
        if not self.has_save(slot):
            return "none", {}, None, None
        prim = self.inspect(self.path(slot))
        if prim["status"] == "ok":
            return "primary", prim["data"], self.path(slot), prim["schema"]
        if prim["status"] == "future" and m["primary_future_stops"]:
            return "future", {}, None, prim["schema"]
        if not m["slot_bak_fallback"]:
            return "corrupt", {}, None, None
        bak = self.inspect(self.bak(slot))
        if bak["status"] == "ok":
            return "bak", bak["data"], self.bak(slot), bak["schema"]
        if bak["status"] == "future" and m["bak_future_reported"]:
            return "future", {}, None, bak["schema"]
        return "corrupt", {}, None, None

    def read_slot(self, slot):
        return self.resolve(slot)[1]

    def slot_source(self, slot):
        if not self.has_save(slot): return "none"
        if not self.m["source_ok"]: return "?"
        src = self.resolve(slot)[0]
        return "corrupt" if src == "future" and not self.m["future_status"] else src

    def write_back(self, path, data, from_schema):
        """_write_back_migrated 的镜像：先留原件 .vN，再落位"""
        m = self.m
        keep = f"{path}.v{from_schema}"
        if m["wb_keeps_original"] and not os.path.exists(keep):
            with open(path, encoding="utf-8") as src, open(keep, "w", encoding="utf-8") as dst:
                dst.write(src.read())
        with open(path, "w", encoding="utf-8") as f:
            f.write(_dump(data))

    def load_game(self, slot):
        """返回 (ok, 读入的整份 data)；模拟途中类型不符即抛 ScriptError"""
        m = self.m
        src_path, schema = None, None
        if m["load_reader"] == "_read_slot":
            _src, data, src_path, schema = self.resolve(slot)
        elif m["load_reader"] == "_read":
            data = self.read(self.path(slot))
        else:
            raise ScriptError("load_game 未经 _read_slot 读档")
        if not data:
            if m["load_empty_guard"]: return False, {}
            raise ScriptError("空档仍往下 from_dict")
        if m["load_writes_back"] and schema is not None and m["schema"] is not None and schema < m["schema"]:
            self.write_back(src_path, data, schema)
        for key, single in PARTS:
            info = m["load_parts"][key]
            if info is None or not info["reads_key"]:
                raise ScriptError(f"{key} 分区未读入")
            raw = data.get(key, {})
            if info["wrapped"] and m["as_dict_robust"]:
                raw = raw if isinstance(raw, dict) else {}
            elif not isinstance(raw, dict):
                raise ScriptError(f"{single}.from_dict(d: Dictionary) 收到 {_gd_type(raw)}")
            feed_from_dict(m, key, raw)
        state = data.get("state", {})
        if m["load_state_wrapped"]:
            state = state if isinstance(state, dict) else {}
        elif not isinstance(state, dict):
            raise ScriptError(f"state 分区 {_gd_type(state)} 赋给 Dictionary")
        feed_from_dict(m, "state", state)
        return True, data

    def save_label(self, slot):
        m = self.m
        if m["label_none_guard"] and not self.has_save(slot):
            return "未记"
        r = m["label_reader"]
        if r == "_read_slot":
            src, data, _p, _s = self.resolve(slot)
            if src == "future" and m["label_future"]:
                return "新版所记"
        elif r == "_read_primary":
            data = self.read(self.path(slot))
        elif r == "raw_primary":
            text = self._open_text(self.path(slot), m["label_raw_null_guard"])
            try:
                data = json.loads(text) if text is not None else {}
            except ValueError:
                data = {}
            if not isinstance(data, dict): data = {}
        else:
            raise ScriptError("save_label 读档路径不明")
        if not data:
            return "卷页损了"
        return str(data.get("label", "未题"))


# ════════════════════════════════════════════════════════════════════
# 三、可复现 fixture
# ════════════════════════════════════════════════════════════════════

LBL_P, LBL_B = "景炎二年　泉州　500 钱", "景炎元年　兴化　300 钱"
YEAR_P, YEAR_B = 1256, 1255


CUR_SCHEMA = 4  # fixture 里「本版档」的结构号；SAVE_SCHEMA 再升时这些档照样走迁移，仍须读得通
# 「刚好新一版」的结构号：按库里 SaveLoad.gd 的 SAVE_SCHEMA + 1 取（lane fx6 升 v3 后原写死的 3 成了本版档）；
# --source 查旧版时它仍高于旧版的 SAVE_SCHEMA，照样是新版档。
NEXT_SCHEMA = (_const_int(open(SAVELOAD, encoding="utf-8").read(), "SAVE_SCHEMA", CUR_SCHEMA) or CUR_SCHEMA) + 1


FIXTURE_ROLE = "duogong"


def _fixture_crew():
    """好档 crew 分区的 v4 形状（hired 只存候选 id）：取 data/crew.json 名册首名候选；
    名册缺席回退占位串——只用于「须照读」的好例，坏例另有写死的 v4 形状。"""
    try:
        d = json.load(open(os.path.join(ROOT, CANDIDATE_SRC), encoding="utf-8"))
        c = d["candidates"][0]
        return {"hired": {str(c.get("role", FIXTURE_ROLE)): str(c.get("id", ""))}, "unpaid_months": 0}
    except (OSError, ValueError, IndexError, KeyError):
        return {"hired": {FIXTURE_ROLE: "lin_hua"}, "unpaid_months": 0}


FIXTURE_CREW = _fixture_crew()


def good(label=LBL_P, year=YEAR_P):
    return {
        "version": 3,
        SCHEMA_KEY: CUR_SCHEMA,
        "calendar": {"year": year, "month": 4, "day": 1},
        "economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
        "fleet": {"ships": [{"id": "fuchuan", "cargo": {}}], "water": 20, "food": 20, "morale": 70},
        "crew": FIXTURE_CREW,
        "state": {"flags": {}, "money": 500, "last_port": "quanzhou", "visited_ports": ["quanzhou"]},
        "scene": "",
        "label": label,
    }


def _dump(d):
    return json.dumps(d, ensure_ascii=False, indent="\t")


def bad_cases():
    """(名, 坏正本 dict)——每一份都必须判坏档"""
    for part in ("calendar", "economy", "fleet", "crew", "state"):
        for tag, val in (("字符串", "坏"), ("数组", [1, 2]), ("null", None), ("数字", 7)):
            d = good(); d[part] = val
            yield f"{part} 为{tag}", d
    structural = (
        ("calendar.year 字符串", "calendar", {"year": "景炎", "month": 3, "day": 1}),
        ("calendar.month 越界", "calendar", {"year": 1256, "month": 13, "day": 1}),
        ("calendar.day 为零", "calendar", {"year": 1256, "month": 3, "day": 0}),
        ("calendar.day 缺失", "calendar", {"year": 1256, "month": 3}),
        ("economy.rates 数组", "economy", {"rates": [], "tariff": 0.1, "broker": 0.05, "investments": {}}),
        ("economy.tariff 字符串", "economy", {"rates": {}, "tariff": "一成", "broker": 0.05, "investments": {}}),
        ("fleet.ships 字符串", "fleet", {"ships": "福船", "water": 10, "food": 10, "morale": 70}),
        ("fleet.ships 含数字", "fleet", {"ships": [3], "water": 10, "food": 10, "morale": 70}),
        ("fleet.cargo 数组", "fleet", {"ships": [], "cargo": [1], "water": 10, "food": 10, "morale": 70}),
        ("fleet.water 字符串", "fleet", {"ships": [], "water": "满", "food": 10, "morale": 70}),
        ("fleet.mutiny_cooldown null", "fleet", {"ships": [], "mutiny_cooldown": None}),
        ("crew.hired 数组", "crew", {"hired": [], "unpaid_months": 0}),
        ("crew.hired 条目非 id 字符串", "crew", {"hired": {"duogong": {"id": "lin_hua"}}, "unpaid_months": 0}),
        ("crew.unpaid_months null", "crew", {"hired": {}, "unpaid_months": None}),
        ("state.money 字符串", "state", {"money": "千贯"}),
        ("state.last_port 数字", "state", {"last_port": 3}),
        ("state.visited_ports 对象", "state", {"visited_ports": {}}),
        ("state.met_ids 字符串（lane fx6）", "state", {"met_ids": "林华"}),
        ("state.met_ids 对象（lane fx6）", "state", {"met_ids": {"lin_hua": True}}),
        ("state.has_customs_permit 字符串", "state", {"has_customs_permit": "有"}),
    )
    for name, part, val in structural:
        d = good(); d[part] = val
        yield name, d
    for tag, val in (("字符串", "3"), ("对象", {}), ("null", None)):
        d = good(); d["version"] = val
        yield f"version 为{tag}", d
    for tag, val in (("字符串", "二"), ("零", 0), ("负数", -1), ("数组", [2]), ("null", None), ("对象", {})):
        d = good(); d[SCHEMA_KEY] = val
        yield f"save_schema 为{tag}", d


def v1(label=LBL_P, year=YEAR_P):
    """lane sv 之前写的档：无 save_schema，state 只有早期原型那几样"""
    d = good(label, year)
    del d[SCHEMA_KEY]
    return d


def ok_cases():
    """(名, 正本 dict, 期望题签)——须照读正本"""
    yield "全好", good(), LBL_P
    for part in ("calendar", "economy", "fleet", "crew", "state"):
        d = good(); del d[part]
        yield f"{part} 缺键（from_dict 取默认）", d, LBL_P
    d = good(); d["state"]["flags"] = "坏"; d["state"]["discoveries_found"] = 3
    yield "state.flags/发现录坏（_harden_state 清洗）", d, LBL_P
    d = good(); del d["label"]
    yield "缺 label", d, "未题"
    yield "v1 老档（无 save_schema，迁移后照读）", v1(), LBL_P
    d = v1(); del d["state"]
    yield "v1 老档缺 state", d, LBL_P
    yield "v4 hired 键不在职员表（收作未雇）", {**good(), "crew": {"hired": {"navigator": FIXTURE_CREW["hired"].get(FIXTURE_ROLE, "lin_hua")}, "unpaid_months": 0}}, LBL_P
    yield "v4 hired id 查无此人（收作未雇）", {**good(), "crew": {"hired": {FIXTURE_ROLE: "no_such_cand"}, "unpaid_months": 0}}, LBL_P
    # v3 档形状本就允许快照对象；迁移链收掉取不出 id / 名册查无的格，余下照读
    d = v1(); d[SCHEMA_KEY] = 3; d["crew"] = {"hired": {"navigator": {"id": "x"}}, "unpaid_months": 0}
    yield "v3 档 hired 快照取不出 id（迁移收格）", d, LBL_P
    d = v1(); d[SCHEMA_KEY] = 3; d["crew"] = {"hired": {"duogong": {"id": "no_such"}}, "unpaid_months": 0}
    yield "v3 档 hired id 查无此人（迁移收格）", d, LBL_P


# 槽态 fixture：(名, 正本文本或 None, 副抄文本或 None, 期望 has_save, 期望 label, 期望 load, 期望 slot_source)
SLOT_CASES = (
    ("无档",               None,                     None,              False, "未记",     False, "none"),
    ("仅正本",             _dump(good()),            None,              True,  LBL_P,      True,  "primary"),
    ("正本+副抄",          _dump(good()),            _dump(good(LBL_B, YEAR_B)), True, LBL_P, True, "primary"),
    ("正本半截+副抄",      _dump(good())[:40],       _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("正本缺失+副抄",      None,                     _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("正本空文件+副抄",    "",                       _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("正本顶层数组+副抄",  "[1, 2, 3]",              _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    # lane sv：新版档明确拒读，不退副抄
    ("正本版本过新+副抄",  _dump({**good(), "version": 99}), _dump(good(LBL_B, YEAR_B)), True, "新版所记", False, "future"),
    ("正本结构过新+副抄",  _dump({**good(), SCHEMA_KEY: 99}), _dump(good(LBL_B, YEAR_B)), True, "新版所记", False, "future"),
    ("正本缺失+副抄过新",  None, _dump({**good(LBL_B, YEAR_B), SCHEMA_KEY: NEXT_SCHEMA}), True, "新版所记", False, "future"),
    ("正本半截+副抄过新",  _dump(good())[:40], _dump({**good(LBL_B, YEAR_B), SCHEMA_KEY: NEXT_SCHEMA}), True, "新版所记", False, "future"),
    ("正本 v1+副抄",       _dump(v1()),              _dump(good(LBL_B, YEAR_B)), True, LBL_P, True, "primary"),
    ("正本坏+副抄 v1",     "{",                      _dump(v1(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("两份皆坏",           "{",                      "not json",        True,  "卷页损了", False, "corrupt"),
    ("正本坏+副抄缺",      "{\"version\":",          None,              True,  "卷页损了", False, "corrupt"),
)


def _write(p, content):
    if content is None:
        if os.path.exists(p): os.remove(p)
        return
    with open(p, "w", encoding="utf-8") as f:
        f.write(content)


# ════════════════════════════════════════════════════════════════════
# 四、断言
# ════════════════════════════════════════════════════════════════════

def run_checks(src, verbose=True):
    problems = []
    say = print if verbose else (lambda *a, **k: None)

    def ok(cond, good_msg, bad_msg):
        say(f"  {'✓' if cond else '✗'} {good_msg if cond else bad_msg}")
        if not cond:
            problems.append(bad_msg)

    m = build_model(src)

    say("=" * 68)
    say("一、SaveLoad 源码契约（守卫存在性与顺序）")
    say("=" * 68)
    ok(m["has_primary"] and m["has_bak"], "has_save 认正本与副抄 .bak", "has_save 未同时认正本与 .bak")
    ok(m["read_exists_guard"], "_read 先查 file_exists", "_read 未先查 file_exists")
    ok(m["read_null_guard"], "_read 判空 FileAccess 先于 get_as_text", "_read 未在 get_as_text 前判空")
    ok(m["read_parse_guard"], "_read 解析失败返回空表", "_read 解析失败未返回空表")
    ok(m["read_dict_guard"], "_read 顶层非对象返回空表", "_read 未校验顶层为对象")
    ok(m["version_num_guard"], "_read 先 _is_num(version) 再 int()", "_read 未在 int() 前校验 version 为数字")
    ok(m["read_version_guard"], "_read 版本过新拒读", "_read 未拒读过新版本")
    ok(m["schema"] is not None and m["save_writes_schema"], "SAVE_SCHEMA 存在且 save_game 写出 SCHEMA_KEY",
       "缺 SAVE_SCHEMA 或 save_game 未写 save_schema")
    ok(m["schema_default"] == 1, "save_schema 缺省视为 v1", "save_schema 缺省不是 v1")
    ok(m["schema_num_guard"], "save_schema 非正整数判坏档（先于 int()）", "save_schema 未校验为正整数")
    ok(m["future_status"] and m["future_schema"] and m["future_ver"],
       "save_schema / version 高于本版判 future（不是坏档）", "新版档未单独判 future，或漏了 save_schema / version 之一")
    ok(m["migrates"], "低于本版先 _migrate 再 _check_partitions", "_inspect 未在体检前迁移老结构")
    ok(m["chain_ok"], f"迁移链 v1→v{m['schema']} 逐步挂齐（{len(m['chain'])} 步）",
       f"迁移链断档：SAVE_SCHEMA={m['schema']}，已挂 {sorted(m['chain'])}")
    ok(m["primary_future_stops"], "正本是新版档时不退副抄", "正本是新版档仍会退副抄")
    ok(m["bak_future_reported"], "副抄是新版档时报 future 而非卷页损了", "副抄是新版档被报成坏档")
    ok(m["load_writes_back"], "load_game 迁移后回写（先于 from_dict）", "load_game 迁移后未回写")
    ok(m["wb_keeps_original"] and m["wb_tmp_rename"], "回写先留原件 <档名>.v<N>，留不下不写；经 .tmp 落位",
       "回写未先留原件或未经 .tmp 落位")
    ok(m["label_future"], "save_label 新版档题「新版所记」", "save_label 未区分新版档")
    ok(m["read_checks_parts"], "_read 调 _check_partitions，坏因非空即判坏档", "_read 未以 _check_partitions 判坏档")
    r = m["rules"] or {}
    ok(set(r.get("part_types", [])) >= {"calendar", "economy", "fleet", "crew", "state"},
       "_check_partitions 先查五分区皆为对象", "_check_partitions 未查 calendar/economy/fleet/crew/state 皆为对象")
    ok(set(r.get("required_nums", {}).get("calendar", [])) >= {"year", "month", "day"}
       and set(r.get("ranges", {}).get("calendar", {})) >= {"month", "day"},
       "calendar 年月日须为数字且月日不越界", "calendar 日期体检缺失")
    ok("ships" in r.get("arrays", {}).get("fleet", []) and "ships" in r.get("entries_dict", {}).get("fleet", []),
       "fleet.ships 须为数组且条目皆对象", "fleet.ships 体检缺失")
    ok("hired" in r.get("dicts", {}).get("crew", []) and "hired" in r.get("values_string", {}).get("crew", []),
       "crew.hired 须为对象且条目皆为候选 id 字符串（v4 起只存 id）",
       "crew.hired 体检缺失（v4：对象 / id 字符串）")
    ok(m["slot_primary_first"] and m["slot_bak_fallback"],
       "_read_slot 正本优先，空了才退 .bak", "_read_slot 未按「正本→.bak」顺序回退")
    ok(m["as_dict_robust"], "_as_dict 非 Dictionary 一律回空表", "_as_dict 缺失或不回空表")
    ok(m["load_reader"] == "_read_slot", "load_game 经 _read_slot 读档", "load_game 未经 _read_slot")
    ok(m["load_empty_guard"], "load_game 空档先 return false 再 from_dict", "load_game 空档判定缺失或在 from_dict 之后")
    for key, single in PARTS:
        info = m["load_parts"][key]
        ok(bool(info and info["wrapped"]), f"{single}.from_dict(_as_dict(data.get(\"{key}\"…)))",
           f"{key} 分区未经 _as_dict 兜底")
    ok(m["load_state_wrapped"] and m["load_state_hardened"], "state 分区 Dictionary 兜底后经 _harden_state",
       "state 分区未兜底或未经 _harden_state")
    ok(m["parts_before_state"], "四分区读入在 GameState.from_dict 之前", "分区读入顺序异常（晚于 GameState）")
    ok(m["label_none_guard"] and m["label_order"], "save_label 先 has_save 判「未记」再读档",
       "save_label 未先以 has_save 判「未记」")
    ok(m["label_reader"] == "_read_slot", "save_label 经 _read_slot（含 .bak 回退）", "save_label 未走 _read_slot")
    ok(m["label_empty_guard"], "save_label 读空返回「卷页损了」", "save_label 读空未返回「卷页损了」")
    ok(m["label_str"], "save_label 以 str() 包题签，非字符串不崩", "save_label 题签未经 str() 包裹")
    ok(m["source_ok"], "slot_source 按 none→正本→副抄→corrupt 判定", "slot_source 四态判定顺序异常")
    ok(m["scene_via_slot"], "saved_scene 经 _read_slot", "saved_scene 未经 _read_slot")
    ok(not m["chained_open"], "无 FileAccess.open(...).get_as_text() 链式空引用",
       "存在 FileAccess.open(...).get_as_text() 链式空引用")
    ok(all(m["from_dict"].get(p) for p in FROM_DICT_SRC), "已从五个 from_dict 抽出强类型赋值",
       "未能从 from_dict 抽出强类型赋值")

    with tempfile.TemporaryDirectory(prefix="nk1_save_gate_") as tmp:
        sim = Sim(m, tmp)

        def run_slot(slot, prim, bak):
            _write(sim.path(slot), prim)
            _write(sim.bak(slot), bak)
            has = sim.has_save(slot)
            label = sim.save_label(slot)
            src_state = sim.slot_source(slot)
            loaded, data = sim.load_game(slot)
            return has, label, src_state, loaded, data

        say()
        say("=" * 68)
        say("二、坏档 fixture（判坏档：有副抄读副抄，无副抄「卷页损了」，均不抛错）")
        say("=" * 68)
        for i, (name, d) in enumerate(bad_cases()):
            try:
                a = run_slot(300 + 2 * i, _dump(d), _dump(good(LBL_B, YEAR_B)))
                b = run_slot(301 + 2 * i, _dump(d), None)
            except ScriptError as e:
                ok(False, "", f"坏档「{name}」抛脚本错误：{e}")
                continue
            got_a = a[:4] == (True, LBL_B, "bak", True) and a[4].get("calendar", {}).get("year") == YEAR_B
            got_b = b[:4] == (True, "卷页损了", "corrupt", False)
            ok(got_a and got_b, f"「{name}」判坏档 → 副抄 / 卷页损了",
               f"坏档「{name}」未判坏：有副抄得 {a[1]}/{a[2]}/load={a[3]}，无副抄得 {b[1]}/{b[2]}/load={b[3]}")

        say()
        say("=" * 68)
        say("三、好档 fixture（缺键或可清洗字段不误判为坏档）")
        say("=" * 68)
        for i, (name, d, want) in enumerate(ok_cases()):
            try:
                has, label, st, loaded, _ = run_slot(400 + i, _dump(d), _dump(good(LBL_B, YEAR_B)))
            except ScriptError as e:
                ok(False, "", f"好档「{name}」抛脚本错误：{e}")
                continue
            ok((label, st, loaded) == (want, "primary", True), f"「{name}」照读正本",
               f"好档「{name}」被误判：label=「{label}」source={st} load={loaded}")

        say()
        say("=" * 68)
        say("四、槽态 fixture（仅 .bak 时题签可读、无空引用）")
        say("=" * 68)
        for i, (name, prim, bak, want_has, want_label, want_load, want_src) in enumerate(SLOT_CASES):
            try:
                has, label, st, loaded, _ = run_slot(200 + i, prim, bak)
            except ScriptError as e:
                ok(False, "", f"槽态「{name}」抛脚本错误：{e}")
                continue
            ok((has, label, st, loaded) == (want_has, want_label, want_src, want_load),
               f"「{name}」has_save={has} label=「{label}」source={st} load={loaded}",
               f"槽态「{name}」期望 {want_has}/「{want_label}」/{want_src}/{want_load}，"
               f"实得 {has}/「{label}」/{st}/{loaded}")
        say()
        say("=" * 68)
        say("五、迁移回写（v1 读入 → 回写本版结构、原件另存 .v1、副抄不动、二次读不再迁）")
        say("=" * 68)
        want = m["schema"]
        for i, (name, prim, bak, which) in enumerate((
                ("正本 v1", _dump(v1()), _dump(good(LBL_B, YEAR_B)), "primary"),
                ("正本坏 + 副抄 v1", "{", _dump(v1(LBL_B, YEAR_B)), "bak"))):
            slot = 500 + i
            try:
                _write(sim.path(slot), prim)
                _write(sim.bak(slot), bak)
                loaded, _d = sim.load_game(slot)
                target = sim.path(slot) if which == "primary" else sim.bak(slot)
                other = sim.bak(slot) if which == "primary" else sim.path(slot)
                orig = prim if which == "primary" else bak
                after = json.load(open(target, encoding="utf-8"))
                keep = target + ".v1"
                kept = os.path.exists(keep) and open(keep, encoding="utf-8").read() == orig
                untouched = open(other, encoding="utf-8").read() == (bak if which == "primary" else prim)
                first = open(target, encoding="utf-8").read()
                loaded2, _d = sim.load_game(slot)
                stable = open(target, encoding="utf-8").read() == first and \
                    open(keep, encoding="utf-8").read() == orig if kept else False
            except (ScriptError, OSError, ValueError) as e:
                ok(False, "", f"迁移「{name}」出错：{e}")
                continue
            got = (loaded, after.get(SCHEMA_KEY), kept, untouched, loaded2, stable)
            ok(got == (True, want, True, True, True, True),
               f"「{name}」读入、回写 {SCHEMA_KEY}={want}、原件 .v1 逐字一致、另一份不动、二次读稳定",
               f"迁移「{name}」期望 load/回写/留原件/另一份不动/二次读/稳定 = True/{want}/True/True/True/True，实得 {got}")
    return problems, m


def _comment(pattern):
    """把命中的行前加 #（多行命中逐行加）"""
    return lambda s: re.sub(pattern, lambda mm: "\n".join("#" + ln for ln in mm.group(0).split("\n")), s,
                            count=1, flags=re.M)


def _drop_last_migrate(s):
    """摘掉 _migrate 里最末一级的 match 分支（v{SAVE_SCHEMA-1}→v{SAVE_SCHEMA}）；--source 查旧版时自动对到旧版的末级"""
    hits = list(re.finditer(r'^\t\t\t\d+\s*:\s*\n\t\t\t\tout\s*=\s*_migrate_v\d+_to_v\d+\(out\)\n', s, re.M))
    return s[:hits[-1].start()] + s[hits[-1].end():] if hits else s


# 变异自检：每个变体模拟「兜底被注释掉 / 退回旧写法」，门禁都必须判红。
MUTANTS = (
    ("_read 注释掉 _check_partitions 判坏",
     _comment(r'^\tvar bad := _check_partitions\(data\)\n\tif bad != "":\n.*\n\t\treturn \{"status": "corrupt"\}$')),
    ("_check_partitions 注释掉分区非对象判定",
     _comment(r'^\tfor key in PARTITIONS.*:\n\t\tif data\.has\(key\).*\n\t\t\treturn .*$')),
    ("_check_partitions 注释掉 calendar 年月日数字判定",
     _comment(r'^\t\tfor k in \["year", "month", "day"\]:\n\t\t\tif not _is_num.*\n\t\t\t\treturn .*$')),
    ("_check_partitions 注释掉 ships 条目判定",
     _comment(r'^\t\tfor s in fleet\["ships"\]:\n\t\t\tif typeof\(s\).*\n\t\t\t\treturn .*$')),
    ("_bad_fields 直接 return \"\"",
     lambda s: re.sub(r'(func _bad_fields\([^\n]*\n)', r'\1\treturn ""\n', s, count=1)),
    ("_read 注释掉 version 数字判定",
     _comment(r'^\tif not _is_num\(ver_raw\):\n.*\n\t\treturn \{"status": "corrupt"\}$')),
    ("load_game 四分区去掉 _as_dict",
     lambda s: re.sub(r'(\w+)\.from_dict\(_as_dict\((data\.get\("(?:calendar|economy|fleet|crew)", \{\}\))\)\)',
                      r'\1.from_dict(\2)', s)),
    ("注释掉 Fleet.from_dict 行", _comment(r'^\tFleet\.from_dict\(.*$')),
    ("_resolve 注释掉 .bak 回退",
     _comment(r'^\tvar bak := _inspect\(_bak_path\(slot\)\)$')),
    ("_read 注释掉 f == null 判空", _comment(r'^\tif f == null:\n\t\treturn \{"status": "corrupt"\}$')),
    ("has_save 不认 .bak",
     lambda s: s.replace(" or FileAccess.file_exists(_bak_path(slot))", "")),
    ("save_label 退回只开正式档",
     lambda s: re.sub(r'\tvar got := _resolve\(slot\)\n\tif got\["source"\] == "future":\n\t\treturn "新版所记"\n'
                      r'\tvar data: Dictionary = got\["data"\]\n\tif data\.is_empty\(\):\n\t\treturn "卷页损了"\n\treturn str\(data\.get\("label", "未题"\)\)',
                      "\tvar f := FileAccess.open(_path(slot), FileAccess.READ)\n\tvar json := JSON.new()\n"
                      "\tif json.parse(f.get_as_text()) != OK:\n\t\treturn \"卷页损了\"\n\treturn json.data.get(\"label\", \"未题\")", s)),
    ("load_game 注释掉空档 return false",
     lambda s: re.sub(r'(func load_game[\s\S]*?)\tif data\.is_empty\(\):\n\t\treturn false',
                      r'\1\t#if data.is_empty():\n\t#\treturn false', s, count=1)),
    # —— lane sv：结构版本 ——
    ("_resolve 正本是新版档仍退副抄", _comment(r'^\t\t"future":\n\t\t\treturn \{"source": "future".*$')),
    ("_resolve 副抄是新版档报成坏档",
     lambda s: s[:s.index("_inspect(_bak_path(slot))")] + re.sub(
         r'\t\t"future":\n\t\t\treturn \{"source": "future".*', "\t\tpass", s[s.index("_inspect(_bak_path(slot))"):], count=1)
     if "_inspect(_bak_path(slot))" in s else s),
    ("_inspect 只看旧头 version、不拒新结构",
     lambda s: s.replace("if schema > SAVE_SCHEMA or ver > VERSION:", "if ver > VERSION:")),
    ("_inspect 新版档当坏档（会退副抄）",
     lambda s: s.replace('return {"status": "future", "schema": schema}', 'return {"status": "corrupt"}')),
    ("save_schema 缺省当本版（老档不迁）",
     lambda s: s.replace("data.get(SCHEMA_KEY, 1)", "data.get(SCHEMA_KEY, SAVE_SCHEMA)")),
    ("save_schema 注释掉正整数判定",
     lambda s: s.replace("if not _is_num(schema_raw) or int(schema_raw) < 1:", "if false:")),
    ("_inspect 不迁移", lambda s: s.replace("data = _migrate(data, schema)", "pass")),
    ("迁移链摘掉 v1→v2", lambda s: s.replace("\t\t\t1:\n\t\t\t\tout = _migrate_v1_to_v2(out)\n", "")),
    ("迁移链摘掉最末一级（lane fx6 起为 v2→v3）", lambda s: _drop_last_migrate(s)),
    ("SAVE_SCHEMA 再升一版却没挂迁移",
     lambda s: re.sub(r'^const SAVE_SCHEMA := (\d+)$', lambda mm: f"const SAVE_SCHEMA := {int(mm.group(1)) + 1}", s,
                      count=1, flags=re.M)),
    ("_check_partitions 不给 state.met_ids 判数组（lane fx6）",
     lambda s: s.replace('"crew_history", "met_ids"])', '"crew_history"])')),
    ("load_game 不回写", lambda s: re.sub(r'(\n\t\t)_write_back_migrated\([^\n]*', r'\1pass', s, count=1)),
    ("回写不留原件",
     lambda s: s.replace("if not FileAccess.file_exists(keep) and DirAccess.copy_absolute(path, keep) != OK:", "if false:")),
    ("save_game 不写 save_schema", lambda s: s.replace("\t\tSCHEMA_KEY: SAVE_SCHEMA,\n", "")),
    ("save_label 不区分新版档",
     lambda s: s.replace('\tif got["source"] == "future":\n\t\treturn "新版所记"\n', "")),
)


def known_gaps(m):
    """from_dict 里强类型、但 _check_partitions 未体检的键（不计失败，供后续 lane 参考）"""
    r = m["rules"]
    if r is None:
        return []
    gaps = []
    for part, need in m["from_dict"].items():
        covered = set(r["required_nums"].get(part, [])) | set(r["nums"].get(part, [])) \
            | set(r["dicts"].get(part, [])) | set(r["arrays"].get(part, [])) | set(r["typed"].get(part, {}))
        if part == "state" and m["load_state_hardened"]:
            covered |= HARDENED
        for key in need:
            base = key[:-2] if key.endswith("[]") else key
            if key.endswith("[]") and base in r["entries_dict"].get(part, []):
                continue
            if not key.endswith("[]") and base in covered:
                continue
            gaps.append(f"{part}.{key}")
    return gaps


def main(argv):
    src_path = SAVELOAD
    if "--source" in argv:
        src_path = argv[argv.index("--source") + 1]
    if "--dump-fixtures" in argv:
        out = argv[argv.index("--dump-fixtures") + 1]
        os.makedirs(out, exist_ok=True)
        for i, (name, d) in enumerate(bad_cases()):
            _write(os.path.join(out, f"bad_{i:02d}.json"), _dump(d))
        for i, (name, d, _w) in enumerate(ok_cases()):
            _write(os.path.join(out, f"ok_{i:02d}.json"), _dump(d))
        for i, (name, prim, bak, *_r) in enumerate(SLOT_CASES):
            _write(os.path.join(out, f"slot_{i:02d}.json"), prim)
            _write(os.path.join(out, f"slot_{i:02d}.json.bak"), bak)
        print(f"fixture 已写出：{out}")
        return 0
    if not os.path.isfile(src_path):
        print(f"  ✗ 找不到 {src_path}")
        return 1
    src = open(src_path, encoding="utf-8").read()
    print(f"存档健壮性门禁：{os.path.relpath(os.path.abspath(src_path), ROOT)}")
    problems, model = run_checks(src)

    print()
    print("=" * 68)
    print("六、变异自检（兜底被注释掉时本门禁必须判红）")
    print("=" * 68)
    if problems:
        print("  · 原件已红，跳过变异自检")
    else:
        for name, mutate in MUTANTS:
            mutated = mutate(src)
            if mutated == src:
                print(f"  ✗ 变体「{name}」未能套上（源码形状已变，请同步本门禁）")
                problems.append(f"变体「{name}」未套上")
                continue
            mp, _ = run_checks(mutated, verbose=False)
            if mp:
                print(f"  ✓ 变体「{name}」判红（{len(mp)} 项），如：{mp[0]}")
            else:
                print(f"  ✗ 变体「{name}」仍判绿，门禁失敏")
                problems.append(f"变体「{name}」未被识破")

    gaps = known_gaps(model)
    if gaps:
        print()
        print(f"  ⚠ 未体检的强类型字段（不计失败）：{'、'.join(gaps)}")

    print()
    print("=" * 68)
    if problems:
        print(f"结果：{len(problems)} 项问题")
        for p in problems:
            print("   ✗", p)
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
