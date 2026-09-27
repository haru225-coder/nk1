#!/usr/bin/env python3
"""存档健壮性回归门禁（纯 Python，不跑 Godot）。

锁住 Astra 审计 H1/H2 的修复（6207d31 + lane-h1h2 46a7c17）：
  H1 坏分区：calendar/economy/fleet/crew/state 非对象（字符串/数组/null/数字）、
     日期缺失或越界、ships 非数组、hired 条目非对象、强类型字段错型、version 非数字，
     一律在 _read 判坏档，_read_slot 自然退 .bak；任何输入都不得抛脚本错误。
  H2 只剩 .bak：has_save 认副抄，save_label / slot_source 走同一口径，
     题签可读，任何路径都不对空 FileAccess 调 get_as_text。

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

ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
SAVELOAD = os.path.join(ROOT, "scripts", "core", "SaveLoad.gd")
PARTS = (("calendar", "Calendar"), ("economy", "Economy"), ("fleet", "Fleet"), ("crew", "Crew"))
FROM_DICT_SRC = {
    "calendar": "scripts/core/Calendar.gd",
    "economy": "scripts/core/Economy.gd",
    "fleet": "scripts/core/Fleet.gd",
    "crew": "scripts/core/Crew.gd",
    "state": "scripts/GameState.gd",
}
# _harden_state 读回前清洗的键：不论存档里是什么，喂给 GameState 时都已是合法类型
HARDENED = {"flags", "discoveries_found", "discoveries_reported"}


def func_bodies(src):
    """粗略切分出每个 func 的函数体（按缩进；与 check_symbols.py 同法）"""
    out, cur, body = {}, None, []
    for ln in src.split("\n"):
        m = re.match(r'^func\s+([A-Za-z_]\w*)', ln)
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


def build_model(src):
    fn = {k: _code_only(v) for k, v in func_bodies(src).items()}
    code = _code_only(src)
    m = {"fn": fn, "version": _const_int(src, "VERSION", 0)}

    hs = fn.get("has_save", "")
    m["has_primary"] = "_path(slot)" in hs and "file_exists" in hs
    m["has_bak"] = "_bak_path(slot)" in hs and "file_exists" in hs

    rd = fn.get("_read", "")
    m["read_defined"] = "_read" in fn
    m["read_exists_guard"] = bool(re.search(r'if\s+not\s+FileAccess\.file_exists\(path\)\s*:\s*\n\s*return\s*\{\}', rd))
    m["read_null_guard"] = bool(re.search(r'if\s+(f\s*==\s*null|not\s+f)\s*:\s*\n\s*return\s*\{\}', rd)) \
        and _before(rd, r'f\s*==\s*null|not\s+f\s*:', r'get_as_text')
    m["read_parse_guard"] = bool(re.search(r'\.parse\([^\n]*\)\s*!=\s*OK\s*:[\s\S]*?return\s*\{\}', rd))
    m["read_dict_guard"] = bool(re.search(r'not\s*\(\s*json\.data\s+is\s+Dictionary\s*\)\s*:[\s\S]*?return\s*\{\}', rd))
    m["read_version_guard"] = bool(re.search(r'ver\s*>\s*VERSION\s*:[\s\S]*?return\s*\{\}', rd))
    isn = fn.get("_is_num", "")
    m["is_num_ok"] = "TYPE_INT" in isn and "TYPE_FLOAT" in isn
    m["version_num_guard"] = m["is_num_ok"] and bool(re.search(
        r'if\s+not\s+_is_num\((\w+)\)\s*:[\s\S]*?return\s*\{\}[\s\S]*?int\(\1\)', rd))
    # _check_partitions 须在 _read 里调用、坏因非空即 return {}，且排在版本校验之后、return data 之前
    m["read_checks_parts"] = bool(re.search(
        r'var\s+(\w+)\s*:?=\s*_check_partitions\(data\)\s*\n\s*if\s+\1\s*!=\s*""\s*:[\s\S]*?return\s*\{\}', rd)) \
        and _before(rd, r'_check_partitions\(data\)', r'return\s+data\s*$')

    # —— _check_partitions 体检规则 ——
    cp = _live(fn.get("_check_partitions", ""))
    rules = {"part_types": [], "required_nums": {}, "ranges": {}, "nums": {}, "dicts": {}, "arrays": {},
             "entries_dict": {}, "values_dict": {}, "typed": {}}
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
    bfb = _live(fn.get("_bad_fields", ""))
    if not ("_is_num(part[k])" in bfb and "TYPE_DICTIONARY" in bfb and "TYPE_ARRAY" in bfb and m["is_num_ok"]):
        rules["nums"], rules["dicts"], rules["arrays"] = {}, {}, {k: [] for k in rules["arrays"]}
        # ships 等单独写的 TYPE_ARRAY 判断不依赖 _bad_fields，保留
        for tm in re.finditer(r'if\s+(\w+)\.has\("(\w+)"\)\s*:\s*\n\s*if\s+typeof\(\1\["\2"\]\)\s*!=\s*TYPE_ARRAY', cp):
            part = var_part.get(tm.group(1))
            if part: rules["arrays"].setdefault(part, []).append(tm.group(2))
    m["rules"] = rules if m["read_checks_parts"] else None

    rs = fn.get("_read_slot", "")
    m["slot_primary_first"] = _before(rs, r'_read\(_path\(slot\)\)', r'_read\(_bak_path\(slot\)\)') \
        or ("_read(_path(slot))" in rs and "_bak_path" not in rs)
    m["slot_bak_fallback"] = bool(re.search(r'if\s+data\.is_empty\(\)\s*:[\s\S]*_read\(_bak_path\(slot\)\)', rs))

    ad = fn.get("_as_dict", "")
    m["as_dict_robust"] = bool(re.search(
        r'return\s+raw\s+if\s+typeof\(raw\)\s*==\s*TYPE_DICTIONARY\s+else\s*\{\}', ad)) \
        or bool(re.search(r'if\s+typeof\(raw\)\s*!=\s*TYPE_DICTIONARY\s*:\s*\n\s*return\s*\{\}', ad))

    lg = fn.get("load_game", "")
    m["load_reader"] = "_read_slot" if "_read_slot(slot)" in lg else ("_read" if "_read(_path(slot))" in lg else None)
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
    if "_read_slot(slot)" in sl:
        m["label_reader"] = "_read_slot"
    elif "_read(_path(slot))" in sl:
        m["label_reader"] = "_read_primary"
    elif re.search(r'FileAccess\.open\(_path\(slot\)', sl):
        m["label_reader"] = "raw_primary"
    else:
        m["label_reader"] = None
    m["label_raw_null_guard"] = bool(re.search(r'if\s+(f\s*==\s*null|not\s+f)\s*:', sl))
    m["label_order"] = _before(sl, r'has_save\(slot\)', r'_read_slot\(slot\)|_read\(|FileAccess\.open')
    m["label_empty_guard"] = bool(re.search(r'if\s+data\.is_empty\(\)\s*:\s*\n\s*return\s+"卷页损了"', sl))
    m["label_str"] = bool(re.search(r'return\s+str\(data\.get\("label"', sl))

    ss = fn.get("slot_source", "")
    m["source_ok"] = bool(re.search(r'if\s+not\s+has_save\(slot\)\s*:\s*\n\s*return\s+"none"', ss)) \
        and _before(ss, r'_read\(_path\(slot\)\)', r'_read\(_bak_path\(slot\)\)') \
        and all(t in ss for t in ('"primary"', '"bak"', '"corrupt"'))

    m["scene_via_slot"] = "_read_slot(slot)" in fn.get("saved_scene", "")
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

    def read(self, p):
        m = self.m
        if not m["read_defined"]:
            raise ScriptError("_read 未定义")
        if m["read_exists_guard"] and not os.path.exists(p):
            return {}
        text = self._open_text(p, m["read_null_guard"])
        if text is None:
            return {}
        try:
            data = json.loads(text)
        except ValueError:
            if m["read_parse_guard"]: return {}
            raise ScriptError("JSON 解析失败后仍取 json.data")
        if not isinstance(data, dict):
            if m["read_dict_guard"]: return {}
            raise ScriptError("顶层非对象赋给 Dictionary")
        ver_raw = data.get("version", 0)
        if m["version_num_guard"] and not _is_num(ver_raw):
            return {}
        ver = _gd_int(ver_raw)
        if m["read_version_guard"] and ver > m["version"]:
            return {}
        if m["rules"] is not None and check_partitions(m["rules"], data):
            return {}
        return data

    def read_slot(self, slot):
        data = self.read(self.path(slot))
        if not data and self.m["slot_bak_fallback"]:
            return self.read(self.bak(slot))
        return data

    def slot_source(self, slot):
        if not self.has_save(slot): return "none"
        if not self.m["source_ok"]: return "?"
        if self.read(self.path(slot)): return "primary"
        if self.read(self.bak(slot)): return "bak"
        return "corrupt"

    def load_game(self, slot):
        """返回 (ok, 读入的整份 data)；模拟途中类型不符即抛 ScriptError"""
        m = self.m
        if m["load_reader"] == "_read_slot":
            data = self.read_slot(slot)
        elif m["load_reader"] == "_read":
            data = self.read(self.path(slot))
        else:
            raise ScriptError("load_game 未经 _read_slot 读档")
        if not data:
            if m["load_empty_guard"]: return False, {}
            raise ScriptError("空档仍往下 from_dict")
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
            data = self.read_slot(slot)
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


def good(label=LBL_P, year=YEAR_P):
    return {
        "version": 3,
        "calendar": {"year": year, "month": 4, "day": 1},
        "economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
        "fleet": {"ships": [{"id": "fuchuan", "cargo": {}}], "water": 20, "food": 20, "morale": 70},
        "crew": {"hired": {"navigator": {"id": "navigator"}}, "unpaid_months": 0},
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
        ("crew.hired 条目非对象", "crew", {"hired": {"navigator": "老周"}, "unpaid_months": 0}),
        ("crew.unpaid_months null", "crew", {"hired": {}, "unpaid_months": None}),
        ("state.money 字符串", "state", {"money": "千贯"}),
        ("state.last_port 数字", "state", {"last_port": 3}),
        ("state.visited_ports 对象", "state", {"visited_ports": {}}),
        ("state.has_customs_permit 字符串", "state", {"has_customs_permit": "有"}),
    )
    for name, part, val in structural:
        d = good(); d[part] = val
        yield name, d
    for tag, val in (("字符串", "3"), ("对象", {}), ("null", None)):
        d = good(); d["version"] = val
        yield f"version 为{tag}", d


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


# 槽态 fixture：(名, 正本文本或 None, 副抄文本或 None, 期望 has_save, 期望 label, 期望 load, 期望 slot_source)
SLOT_CASES = (
    ("无档",               None,                     None,              False, "未记",     False, "none"),
    ("仅正本",             _dump(good()),            None,              True,  LBL_P,      True,  "primary"),
    ("正本+副抄",          _dump(good()),            _dump(good(LBL_B, YEAR_B)), True, LBL_P, True, "primary"),
    ("正本半截+副抄",      _dump(good())[:40],       _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("正本缺失+副抄",      None,                     _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("正本空文件+副抄",    "",                       _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("正本顶层数组+副抄",  "[1, 2, 3]",              _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
    ("正本版本过新+副抄",  _dump({**good(), "version": 99}), _dump(good(LBL_B, YEAR_B)), True, LBL_B, True, "bak"),
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
    ok(m["read_checks_parts"], "_read 调 _check_partitions，坏因非空即判坏档", "_read 未以 _check_partitions 判坏档")
    r = m["rules"] or {}
    ok(set(r.get("part_types", [])) >= {"calendar", "economy", "fleet", "crew", "state"},
       "_check_partitions 先查五分区皆为对象", "_check_partitions 未查 calendar/economy/fleet/crew/state 皆为对象")
    ok(set(r.get("required_nums", {}).get("calendar", [])) >= {"year", "month", "day"}
       and set(r.get("ranges", {}).get("calendar", {})) >= {"month", "day"},
       "calendar 年月日须为数字且月日不越界", "calendar 日期体检缺失")
    ok("ships" in r.get("arrays", {}).get("fleet", []) and "ships" in r.get("entries_dict", {}).get("fleet", []),
       "fleet.ships 须为数组且条目皆对象", "fleet.ships 体检缺失")
    ok("hired" in r.get("dicts", {}).get("crew", []) and "hired" in r.get("values_dict", {}).get("crew", []),
       "crew.hired 须为对象且条目皆对象", "crew.hired 体检缺失")
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
    return problems, m


def _comment(pattern):
    """把命中的行前加 #（多行命中逐行加）"""
    return lambda s: re.sub(pattern, lambda mm: "\n".join("#" + ln for ln in mm.group(0).split("\n")), s,
                            count=1, flags=re.M)


# 变异自检：每个变体模拟「兜底被注释掉 / 退回旧写法」，门禁都必须判红。
MUTANTS = (
    ("_read 注释掉 _check_partitions 判坏",
     _comment(r'^\tvar bad := _check_partitions\(data\)\n\tif bad != "":\n.*\n\t\treturn \{\}$')),
    ("_check_partitions 注释掉分区非对象判定",
     _comment(r'^\tfor key in PARTITIONS.*:\n\t\tif data\.has\(key\).*\n\t\t\treturn .*$')),
    ("_check_partitions 注释掉 calendar 年月日数字判定",
     _comment(r'^\t\tfor k in \["year", "month", "day"\]:\n\t\t\tif not _is_num.*\n\t\t\t\treturn .*$')),
    ("_check_partitions 注释掉 ships 条目判定",
     _comment(r'^\t\tfor s in fleet\["ships"\]:\n\t\t\tif typeof\(s\).*\n\t\t\t\treturn .*$')),
    ("_bad_fields 直接 return \"\"",
     lambda s: re.sub(r'(func _bad_fields\([^\n]*\n)', r'\1\treturn ""\n', s, count=1)),
    ("_read 注释掉 version 数字判定",
     _comment(r'^\tif not _is_num\(ver_raw\):\n.*\n\t\treturn \{\}$')),
    ("load_game 四分区去掉 _as_dict",
     lambda s: re.sub(r'(\w+)\.from_dict\(_as_dict\((data\.get\("(?:calendar|economy|fleet|crew)", \{\}\))\)\)',
                      r'\1.from_dict(\2)', s)),
    ("注释掉 Fleet.from_dict 行", _comment(r'^\tFleet\.from_dict\(.*$')),
    ("_read_slot 注释掉 .bak 回退",
     _comment(r'^\tif data\.is_empty\(\):\n\t\tvar bak := _read\(_bak_path\(slot\)\)$')),
    ("_read 注释掉 f == null 判空", _comment(r'^\tif f == null:\n\t\treturn \{\}$')),
    ("has_save 不认 .bak",
     lambda s: s.replace(" or FileAccess.file_exists(_bak_path(slot))", "")),
    ("save_label 退回只开正式档",
     lambda s: re.sub(r'\tvar data := _read_slot\(slot\)\n\tif data\.is_empty\(\):\n\t\treturn "卷页损了"\n\treturn str\(data\.get\("label", "未题"\)\)',
                      "\tvar f := FileAccess.open(_path(slot), FileAccess.READ)\n\tvar json := JSON.new()\n"
                      "\tif json.parse(f.get_as_text()) != OK:\n\t\treturn \"卷页损了\"\n\treturn json.data.get(\"label\", \"未题\")", s)),
    ("load_game 注释掉空档 return false",
     lambda s: re.sub(r'(func load_game[\s\S]*?)\tif data\.is_empty\(\):\n\t\treturn false',
                      r'\1\t#if data.is_empty():\n\t#\treturn false', s, count=1)),
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
    print("五、变异自检（兜底被注释掉时本门禁必须判红）")
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
