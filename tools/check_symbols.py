#!/usr/bin/env python3
"""静态检查 GDScript：autoload 单例的跨文件引用是否都真实存在。
GDScript 是动态语言，Autoload.missing_method() 只有跑到那一行才报错。"""
import json, re, os, sys, collections
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)
# 字符串派发候选提示：`--suggest` 或 CHECK_SYMBOLS_SUGGEST=1 才开（见「二之三」）；不开时输出与退出码一字不变
SUGGEST = "--suggest" in sys.argv[1:] or os.environ.get("CHECK_SYMBOLS_SUGGEST", "") not in ("", "0")

import pathlib
ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
SCRIPTS = os.path.join(ROOT, "scripts")

# autoload 名 -> 脚本路径（须与 project.godot 一致）
AUTOLOADS = {
    "GameManager": "scripts/GameManager.gd",
    "Calendar":    "scripts/core/Calendar.gd",
    "Economy":     "scripts/core/Economy.gd",
    "Fleet":       "scripts/core/Fleet.gd",
    "Crew":        "scripts/core/Crew.gd",
    "Voyage":      "scripts/core/Voyage.gd",
    "GameState":   "scripts/GameState.gd",
    "SaveLoad":    "scripts/core/SaveLoad.gd",
}

# Main.gd 拆出去的件（lane ms 起）。Main 留同名同签名一行转发 `[return |await ]_K.fn(…)`，
# 真身在这些文件里；源码断言照旧读 main_src，由 read_main_src() 拼回「未拆时」的 Main。
# 清单只有一份：tools/main_splits.txt（lane cs13）。本脚本与 godot_smoke 都读它的第一列；它由 tools/gen_main_splits.py
# 从拆解台账 + Main 转发 + git 生成，「一之零」每轮重算对账（手改一格、台账 / 拆出件改了没 --write 都红）。
# 新拆一件：docs/Main拆解台账.md 追加一节，跑 `python3 tools/gen_main_splits.py --write`；登记了却没接上转发会直接判红（见「一之零」）。
# 拼回只对「源码字符串断言」有效（lane cs8，口径见 docs/GATES.md §三.1）：拼出来的行号不对应任何真文件、
# `main.` 前缀已去掉、static / 实例语义不看；这些要读拆出件原文或交 compile / 探针。
# 拼回漏不漏由「一之零」兜住：拆出件头注写「从 Main.gd 原样搬出」却没登记、Main 一行转发到未登记的件、
# Main 里调拆出件却不是一行转发（行尾注释 / 两行 / 折行签名，拼回不认）都判红。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_main_splits
MAIN_SPLITS = gen_main_splits.read_splits()
# Main 里一行转发形状、但目标不是拆出件的委托（本来就是别的模块的 API，不拼回）。新增一条须注明为什么不是拆出件。
# 条目失效判红（lane gd16，见「一之零」）：文件在、Main preload 了它、Main 里真有一行转发到它、转发的目标函数它真有、
# 注明里的「（Main 函数 → 目标函数）」对得上实际转发——任一条不成立就是过时条目（该删 / 该改注），不能留着白放行。
MAIN_NOT_SPLITS = {
    "scripts/cutscene/LivingBackdrop.gd": "过场背景调色（_grade_backdrop → set_grade），公共件，不是从 Main 搬出",
    "scripts/ui/TavernNewsWall.gd": "酒馆市井札薄（_setup_news_wall → mount），自成一件，不是从 Main 搬出",
}
SPLIT_MARK = "从 Main.gd 原样搬出"  # 拆出件头注（前 10 行）的约定字样；有它就必须登记，登记了就必须有它
_SPLIT_FWD = re.compile(r'^\t(?:return |await )?(_[A-Z][A-Z0-9_]*)\.([A-Za-z_]\w*)\((.*)\)\s*$')
_split_report = []
_split_fwd_count = {}
_nonsplit_fwd = {}  # 非拆出件路径 -> [(Main 函数名, 目标函数名)]：Main 里一行转发到它的各支（MAIN_NOT_SPLITS 失效判据用）


def _top_level_chunks(src):
    """按顶格行切块：[(头行, [续行…])]。func 的签名 + 函数体、const、注释都各成一块；
    多行签名 / 括号续行归前一块（缩进行与空行都算续行）。"""
    chunks = []
    for ln in src.split("\n"):
        if chunks and (ln == "" or ln[0].isspace() or ln.startswith(")")):
            chunks[-1][1].append(ln)
        else:
            chunks.append((ln, []))
    return chunks


def _split_args(s):
    out, depth, cur = [], 0, ""
    for c in s:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur.strip())
    return out


def read_main_src():
    """Main.gd + MAIN_SPLITS 拼成一份「未拆时」的 Main 源码：
    - Main 里一行转发到拆出件的 func，函数体就地换成拆出件里那支 static func 的函数体；
      转发时传 self 的形参（如 main），函数体里的 `main.` 前缀去掉、裸 `main` 换回 self——拼出来就是搬走前的原文；
    - 拆出件里没被转发到的其余部分（helper / 常量）追加在末尾，static func 记成 func，func_bodies() 照样切得到。
    拆走函数后，断言不会因为只看见一行转发而假绿（尤其是「某字样不得出现」一类的反向断言）。"""
    _split_report.clear()
    _split_fwd_count.clear()
    _nonsplit_fwd.clear()
    with open(os.path.join(SCRIPTS, "Main.gd"), encoding="utf-8") as f:
        main_text = f.read()
    const_of, other_of = {}, {}
    for m in re.finditer(r'^const\s+(_[A-Z][A-Z0-9_]*)\s*:?=\s*preload\("res://([^"]+)"\)', main_text, re.M):
        (const_of if m.group(2) in MAIN_SPLITS else other_of)[m.group(1)] = m.group(2)
    _uses = re.compile(r'\b(' + "|".join(map(re.escape, const_of)) + r')\.') if const_of else None
    parts = {}
    for rel in MAIN_SPLITS:
        if not os.path.isfile(os.path.join(ROOT, rel)):
            _split_report.append(f"{rel} 登记在 tools/main_splits.txt，文件却不存在（删了拆出件没更新清单），拼回跳过它")
            parts[rel] = {"funcs": {}, "rest": [], "used": set(), "fwd": 0, "gone": True}
            continue
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            funcs, rest = {}, []
            for head, tail in _top_level_chunks(f.read()):
                m = re.match(r'^static\s+func\s+([A-Za-z_]\w*)\s*\(', head)
                if m:
                    funcs[m.group(1)] = (head, tail)
                elif not head.startswith(("extends ", "class_name ")):
                    rest.append((head, tail))
            parts[rel] = {"funcs": funcs, "rest": rest, "used": set(), "fwd": 0}
    out = []
    for head, tail in _top_level_chunks(main_text):
        m = re.match(r'^func\s+[A-Za-z_]\w*', head)
        code = [ln for ln in tail if ln.strip() and not ln.strip().startswith("#")]
        fwd = _SPLIT_FWD.match(code[0]) if m and len(code) == 1 else None
        rel = const_of.get(fwd.group(1)) if fwd else None
        fname = head.split("(")[0]
        if m and rel is None and _uses and _uses.search("\n".join(code)):
            _k = _uses.search("\n".join(code)).group(1)
            _split_report.append(f"{fname} 调了拆出件 {const_of[_k]}（{_k}.…）却不是一行转发，拼回不认、"
                                 f"函数体断言只看得到 Main 这几行（转发须独占函数体：`\\t[return |await ]{_k}.fn(…)`，"
                                 f"行尾不带注释、签名不折行）")
        if fwd and fwd.group(1) in other_of:
            _nonsplit_fwd.setdefault(other_of[fwd.group(1)], []).append((fname[len("func "):].strip(), fwd.group(2)))
        if fwd and fwd.group(1) in other_of and other_of[fwd.group(1)] not in MAIN_NOT_SPLITS:
            _split_report.append(f"{fname} 一行转发到 {other_of[fwd.group(1)]}，它没登记进 MAIN_SPLITS，函数体不拼回"
                                 f"（是拆出件就在 docs/Main拆解台账.md 追加一节、跑 tools/gen_main_splits.py --write；不是就加进 check_symbols 的 MAIN_NOT_SPLITS 并注明）")
        if rel is None:
            out.append((head, tail))
            continue
        part, name = parts[rel], fwd.group(2)
        if name not in part["funcs"]:
            _split_report.append(f"{head.split('(')[0]} 转发到 {rel} 的 {name}，那边没有这支 static func")
            out.append((head, tail))
            continue
        p_head, p_tail = part["funcs"][name]
        part["used"].add(name)
        part["fwd"] += 1
        # 签名可能折行：括号配平、以 : 收尾的那行之后才是函数体
        sig_lines, depth = [], 0
        for ln in [p_head] + p_tail:
            sig_lines.append(ln)
            depth += sum(ln.count(c) for c in "([{") - sum(ln.count(c) for c in ")]}")
            if depth == 0 and ln.rstrip().endswith(":"):
                break
        sig = " ".join(sig_lines)
        sig = sig[sig.index("(") + 1:sig.rindex(")")]
        params = [a.split(":")[0].split("=")[0].strip() for a in _split_args(sig)]
        args = _split_args(fwd.group(3))
        body = "\n".join(p_tail[len(sig_lines) - 1:])
        for pname, arg in zip(params, args):
            if arg == "self" and pname:
                body = re.sub(rf'\b{pname}\.', "", body)
                body = re.sub(rf'\b{pname}\b', "self", body)
        # 转发体里的注释照留，转发那一行由搬来的函数体顶上
        notes = [ln for ln in tail if ln.strip().startswith("#")]
        out.append((head, notes + body.split("\n")))
    for rel in MAIN_SPLITS:
        part = parts[rel]
        _split_fwd_count[rel] = part["fwd"]
        if part.get("gone"):
            continue
        if part["fwd"] == 0:
            _split_report.append(f"{rel} 登记为 Main 拆出件，但 Main 里没有一行转发接到它（或没 preload）")
        out.append((f"# ── 以下自 {rel} 拼入（未被转发的 helper / 常量） ──", []))
        for name, (p_head, p_tail) in part["funcs"].items():
            if name not in part["used"]:
                out.append((re.sub(r'^static\s+', "", p_head), p_tail))
        out.extend(part["rest"])
    return "\n".join("\n".join([h] + t) for h, t in out)

def code_only(src):
    """去掉字符串和注释，只留代码。字符串里的 [color=#…]、Economy.xx 不算语法，
    注释里的 foo.emit() 也不算；字符串/注释里的换行原样保留，行号不走样。"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c in ('"', "'"):
            q = c * 3 if src.startswith(c * 3, i) else c
            start = i
            i += len(q)
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src.startswith(q, i):
                    i += len(q)
                    break
                i += 1
            out.append(" " + "\n" * src.count("\n", start, i))
            continue
        if c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def line_starts_code(src):
    """逐行返回 (行号, 该行是否为「逻辑行」的开头)。
    在括号里续写、在 \\ 之后续写、落在多行字符串里的行，缩进不归 GDScript 管，返回 False。"""
    res = []
    depth, in_str, cont = 0, None, False
    i, n, line = 0, len(src), 1
    res.append((1, True))
    while i < n:
        c = src[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if src.startswith(in_str, i):
                i += len(in_str)
                in_str = None
                continue
            if c == "\n":
                line += 1
                res.append((line, False))
            i += 1
            continue
        if c in ('"', "'"):
            in_str = c * 3 if src.startswith(c * 3, i) else c
            i += len(in_str)
            continue
        if c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth = max(0, depth - 1)
        elif c == "\\" and src.startswith("\n", i + 1):
            cont = True
            i += 1
            continue
        if c == "\n":
            line += 1
            res.append((line, depth == 0 and not cont))
            cont = False
        i += 1
    return dict(res)


def parse_members(path):
    """返回该脚本定义的 func / var / const / signal / enum 名集合"""
    members, enums = set(), {}
    with open(path, encoding="utf-8") as f:
        src = f.read()
    code = code_only(src)
    # 前缀可带注解（@onready / @export_range(…) 等）与 static
    pre = r'^\s*(?:@\w+(?:\([^)\n]*\))?\s+)*(?:static\s+)?'
    for kw in ("func", "var", "const", "signal", "class"):
        for m in re.finditer(pre + kw + r'\s+([A-Za-z_]\w*)', code, re.M):
            members.add(m.group(1))
    for m in re.finditer(r'^\s*enum\s*([A-Za-z_]\w*)?\s*\{([^}]*)\}', code, re.M | re.S):
        name, body = m.group(1), m.group(2)
        vals = {v.split("=")[0].strip() for v in body.split(",") if v.strip()}
        if name:
            members.add(name)
            enums[name] = vals
        else:
            members |= vals  # 匿名 enum 的值直接挂在脚本上
    return members, enums, src

# 检查面（lane cv）：scripts/ 与 tools/ 下全部 .gd（含 tools/art/ 等子目录）。路径里带 legacy 段的目录整棵不查
# （与 check_assets、compile 门禁 inventory 同一排除法）：tools/legacy/ 是已退役的一次性 Python 补丁与 21ce 留档脚本（含 p7_smoke.gd，lane gd8 挪入），没有门禁会跑。
def gd_scope():
    out = []
    for base in (SCRIPTS, os.path.join(ROOT, "tools")):
        for dirpath, dirnames, files in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if d != "legacy")
            out += [os.path.join(dirpath, fn) for fn in sorted(files) if fn.endswith(".gd")]
    return out

GD_FILES = gd_scope()

# project.godot 里注册了、上表却漏写的 autoload：照样纳入检查，免得它的引用整片不受检
with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
    _pg_autoloads = re.findall(r'^(\w+)="\*res://([^"]+\.gd)"', f.read(), re.M)
EXTRA_AUTOLOADS = [n for n, _ in _pg_autoloads if n not in AUTOLOADS]
for _n, _rel in _pg_autoloads:
    AUTOLOADS.setdefault(_n, _rel)

# 收集所有 autoload 的成员
defined, enum_map = {}, {}
for name, rel in AUTOLOADS.items():
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        print(f"  ✗ autoload 脚本不存在: {rel}")
        sys.exit(1)
    defined[name], enum_map[name], _ = parse_members(p)

# 校验 project.godot 的 autoload 与上表一致
with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
    pg = f.read()
declared = dict(re.findall(r'^(\w+)="\*(res://[^"]+)"', pg, re.M))
problems = []

print("=" * 68)
print("一之零、Main.gd 拆出件（MAIN_SPLITS ← tools/main_splits.txt）与转发")
print("=" * 68)
print("  源码断言读的 main_src = Main.gd + 拆出件拼回的「未拆时」Main（read_main_src）。")
print("  拼回只对源码字符串断言有效：行号、`main.` 前缀、static / 实例语义不在此列（见 docs/GATES.md §三.1）。")
read_main_src()  # 填 _split_report / _split_fwd_count
for rel in MAIN_SPLITS:
    _n = _split_fwd_count.get(rel, 0)
    print(f"  {'✓' if _n else '✗'} {rel}：{_n} 支转发拼回函数体")
# 头注约定：写了「从 Main.gd 原样搬出」的件必须登记；登记了的件头注必须写它（新拆一刀忘登记在这里红）
_marked = set()
for _dp, _dn, _fn in os.walk(SCRIPTS):
    for _f in _fn:
        if _f.endswith(".gd"):
            _p = os.path.join(_dp, _f)
            with open(_p, encoding="utf-8") as f:
                if SPLIT_MARK in "".join(f.readline() for _ in range(10)):
                    _marked.add(os.path.relpath(_p, ROOT).replace(os.sep, "/"))
for _rel in sorted(_marked - set(MAIN_SPLITS)):
    _split_report.append(f"{_rel} 头注写「{SPLIT_MARK}」，却没登记进 MAIN_SPLITS（拼回不读它，搬走的函数体断言看不到）")
for _rel in MAIN_SPLITS:
    if _rel not in _marked:
        _split_report.append(f"{_rel} 登记为拆出件，头注前 10 行却没写「{SPLIT_MARK}」（约定字样，漏登记靠它查）")
if not _split_report:
    print(f"  ✓ 头注写「{SPLIT_MARK}」的 {len(_marked)} 件与 MAIN_SPLITS 一一对上；"
          f"Main 调拆出件处都是一行转发；非拆出件的一行委托 {len(MAIN_NOT_SPLITS)} 处都在 MAIN_NOT_SPLITS")
# MAIN_NOT_SPLITS 条目失效判红（lane gd16）：过时条目不放行任何转发，却让人以为那处委托有人看着
_ns_report = []
for _rel, _why in MAIN_NOT_SPLITS.items():
    _fwds = _nonsplit_fwd.get(_rel, [])
    if _rel in MAIN_SPLITS:
        _ns_report.append(f"{_rel} 同时登记在 MAIN_SPLITS 与 MAIN_NOT_SPLITS（二选一）")
    if not os.path.isfile(os.path.join(ROOT, _rel)):
        _ns_report.append(f"MAIN_NOT_SPLITS 条目 {_rel} 文件不存在（条目过时，删掉或改路径）")
        continue
    if not _fwds:
        _ns_report.append(f"MAIN_NOT_SPLITS 条目 {_rel}：Main 没 preload 它或没有一行转发到它（条目过时，删掉）")
        continue
    with open(os.path.join(ROOT, _rel), encoding="utf-8") as f:
        _ns_funcs = set(re.findall(r'^(?:static\s+)?func\s+([A-Za-z_]\w*)', f.read(), re.M))
    for _caller, _callee in _fwds:
        if _callee not in _ns_funcs:
            _ns_report.append(f"func {_caller} 转发到 {_rel} 的 {_callee}，那边没有这支 func（MAIN_NOT_SPLITS 条目指向不存在的目标）")
    for _caller, _callee in re.findall(r'([A-Za-z_]\w*)\s*→\s*([A-Za-z_]\w*)', _why):
        if (_caller, _callee) not in _fwds:
            _ns_report.append(f"MAIN_NOT_SPLITS 条目 {_rel} 注明「{_caller} → {_callee}」，Main 里实际一行转发是 "
                              f"{'、'.join(f'{a} → {b}' for a, b in _fwds)}（注明过时，改注）")
if not _ns_report:
    print(f"  ✓ MAIN_NOT_SPLITS {len(MAIN_NOT_SPLITS)} 条都有效：文件在、Main 一行转发到它、目标函数在、注明与实际转发一致")
_split_report.extend(_ns_report)
for _msg in _split_report:
    print(f"  ✗ {_msg}")
    problems.append(f"Main 拆出件：{_msg}")
if not _split_report:
    print("  ✓ 登记的拆出件都有转发接上，转发目标都在")
# 清单本身：tools/main_splits.txt 与生成器重算逐字节一致（lane cs13：拆出件 / lane ← 台账，拆出函数 ← Main 转发，commit / 行范围 ← git）
if not MAIN_SPLITS:
    print("  ✗ tools/main_splits.txt 不存在或一件都没有（拼回什么都不读，搬走的函数体断言全看不到）")
    problems.append("Main 拆出件：tools/main_splits.txt 读不到拆出件")
_, _ms_lines, _ms_problems = gen_main_splits.check()
for _ln in _ms_lines:
    print("  " + _ln)
problems.extend(f"Main 拆出件：{_p}" for _p in _ms_problems)
# 两边都读它（cs8 定的口径）：godot_smoke 的源码断言也读 Main + 拆出件，它不许再自带一份清单，只读 tools/main_splits.txt
with open(os.path.join(ROOT, "tools", "godot_smoke.gd"), encoding="utf-8") as f:
    _smoke_code = "\n".join(ln for ln in f.read().splitlines() if not ln.lstrip().startswith("#"))
_smoke_bad = []
if not re.search(r'^const MAIN_SPLITS_TXT\s*:?=\s*"res://tools/main_splits\.txt"', _smoke_code, re.M):
    _smoke_bad.append("没有 `const MAIN_SPLITS_TXT := \"res://tools/main_splits.txt\"`")
if not re.search(r'^func _main_family_src\(\)[^\n]*\n(?:\t[^\n]*\n)*?\tfor p in _main_splits\(\):', _smoke_code, re.M):
    _smoke_bad.append("_main_family_src() 不是 `for p in _main_splits():` 读清单")
_smoke_readers = "".join(m.group(0) for m in re.finditer(r'^func _main_(?:splits|family_src)\(\)[^\n]*\n(?:[\t ][^\n]*\n|\n)*', _smoke_code, re.M))
if re.search(r'"res://scripts/ui/\w+\.gd"', _smoke_readers):
    _smoke_bad.append("_main_splits / _main_family_src 里写死了拆出件路径")
if re.search(r'^const MAIN_SPLITS\s*:?=', _smoke_code, re.M):
    _smoke_bad.append("还自带一份 `const MAIN_SPLITS`")
if not _smoke_bad:
    print("  ✓ godot_smoke.gd 与此同读 tools/main_splits.txt（_main_family_src → _main_splits，不自带清单）")
else:
    print(f"  ✗ godot_smoke.gd 没改成读 tools/main_splits.txt：{'；'.join(_smoke_bad)}")
    problems.append("godot_smoke 不读 tools/main_splits.txt")

print("=" * 68)
print("一、project.godot 的 autoload 注册")
print("=" * 68)
for name, rel in AUTOLOADS.items():
    want = "res://" + rel
    got = declared.get(name)
    ok = got == want
    note = "（上表漏写，已自动纳入检查，请补进 AUTOLOADS）" if name in EXTRA_AUTOLOADS else ""
    print(f"  {'✓' if ok else '✗'} {name:<12} {got or '(未注册)'}{note}")
    if not ok:
        problems.append(f"autoload {name} 注册不符：期望 {want}，实际 {got}")

# autoload 顺序：GameManager 必须在依赖它的模块之前
order = [m.group(1) for m in re.finditer(r'^(\w+)="\*res://', pg, re.M)]
if "GameManager" in order:
    gm_idx = order.index("GameManager")
    for dep in ("Economy", "Fleet", "Voyage"):
        if dep in order and order.index(dep) < gm_idx:
            problems.append(f"{dep} 注册在 GameManager 之前，_ready 时数据尚未加载")
    print(f"\n  加载顺序: {' → '.join(order)}")
    print(f"  {'✓' if all(order.index(d) > gm_idx for d in ('Economy','Fleet','Voyage') if d in order) else '✗'}"
          f" GameManager 先于 Economy/Fleet/Voyage")

# 入库版须是 GUI 编辑器的规范形（lane ag3 df01703）：编辑器存盘时按 ConfigFile 重写，
# 只留引擎自带的 7 行文件头、删其余 `;` 注释、删默认值（resizable=true）。手编回那种形式
# 下次开编辑器就被改写，工作树常驻 M。autoload 顺序说明在 GameManager.gd 头部。
PG_HEADER = [
    "; Engine configuration file.",
    "; It's best edited using the editor UI and not directly,",
    "; since the parameters that go here are not all obvious.",
    ";",
    "; Format:",
    ";   [section] ; section goes between []",
    ";   param=value ; assign values to parameters",
]
_pg_lines = pg.split("\n")
_pg_head = 0
while _pg_head < len(_pg_lines) and _pg_lines[_pg_head].lstrip().startswith(";"):
    _pg_head += 1
_pg_stray = [i + 1 for i, ln in enumerate(_pg_lines) if i >= _pg_head and ln.lstrip().startswith(";")]
_pg_badhead = _pg_lines[:_pg_head] not in ([], PG_HEADER)
_pg_resizable = re.search(r'^window/size/resizable=true\s*$', pg, re.M)
if _pg_badhead:
    print(f"  ✗ project.godot 文件头 {_pg_head} 行与编辑器自带头不同（编辑器会改写回去）")
    problems.append("project.godot 文件头非编辑器规范形")
if _pg_stray:
    print(f"  ✗ project.godot 第 {', '.join(map(str, _pg_stray))} 行是 `;` 注释（编辑器存盘会删掉，注释写 GameManager.gd 头部）")
    problems.append("project.godot 含编辑器会删的注释行")
if _pg_resizable:
    print("  ✗ project.godot 写了默认值 window/size/resizable=true（编辑器存盘会删掉）")
    problems.append("project.godot 含默认值 resizable=true")
if not (_pg_badhead or _pg_stray or _pg_resizable):
    print("  ✓ project.godot 是编辑器规范形（无额外 `;` 注释、无 resizable=true 默认值）")

print()
print("=" * 68)
print("一之二、_ready 期间的 autoload 依赖顺序")
print("=" * 68)
print("  autoload 按注册顺序逐个 _ready；在 _ready 里碰排在自己后面的 autoload 会拿到 null。")

# 按函数名取函数体取不到时判红（lane gd16）。取不到原先静默给 ""：正向断言（"X" in body）跟着红还算露馅，
# 反向断言（"X" not in body / not any(…)）却照样绿——函数改了名 / 被删 / 搬走没拼回，断言就空转。
# 所以 `_func_body(src, name)` 与 `func_bodies(src).get(name, …)` 一律记账：取不到记下「本脚本行号 + 函数名」，
# 「十三、按函数名取函数体」逐条判红。只想探有没有这支函数、不想判红的，用 `name in func_bodies(src)`（不记账）。
# 场景节点按名取块的 _node_block 同记这本账（键 `[node name="X"]`，lane cs12）。
# 账本与 _locate_func 在 tools/func_body.py（lane cs14 抽出，verify_economy 共用同一份，别另起一套）：
# _body_asks = (本脚本行号, 函数名) -> 取到没有；同一行多次取（循环 / 变异自检）按一处计，有一次取不到就算取不到。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from func_body import body_asks as _body_asks, body_ask as _body_ask, locate_func as _locate_func


class _Bodies(dict):
    """func_bodies 的结果：.get(name, …) 取不到时记账（见 _body_asks），其余同 dict。"""
    def get(self, name, default=None):
        _body_ask(name, name in self)
        return super().get(name, default)


def func_bodies(src):
    """粗略切分出每个 func 的函数体（按缩进）；返回 _Bodies，.get 取不到判红"""
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
    return _Bodies(out)


# 按名先定位、再取体（lane cs9：函数改名误绿收口）。原先各节手写的切法——`src.find("func X")` 切片、
# `src.split("func X", 1)[-1]`、不锚行首 / 不锚名尾的 `re.search(r"func X.*?")`、_static_body——取不到时各有各的落点：
# 空串、None、整份文件（split 的 [-1]）、最后一个字（find 的 -1），名字又只按前缀认（X 会切到 X_old / 注释里的字样）。
# 函数一改名，正向断言跟着红还算露馅，反向断言（"X" not in body）照样绿。一律改走这里：
#   只认行首 `[static ]func 名字(`（名尾须紧跟括号，不吃前缀、不认注释），体到下一个行首 func / static func 为止；
#   取不到给 "" 并记账（_body_ask），「十三、按函数名取函数体」逐条判红。新写按名取体的断言用它或 _func_body，别再手切。
#   _locate_func 定义在 tools/func_body.py（上面已 import，切法原样搬过去）。


# 按函数定义 / 调用认名（lane cs10：光秃子串存在性断言收口）。`"_can_fire" in ship_src` 这类只按子串认名：
# 函数改名成 `_can_fire_v2`（调用点同改）照样打「已定义」，函数里写什么都不会红。一律改走这两支：
#   _has_func：行首 `[static ]func 名字(`（名尾须紧跟括号，不认 X_v2 / 注释 / 文案里的字样）；
#   _calls：按名调用 `名字(` 或取 Callable `名字.bind(` / `.call(`（名前不接标识符或点、名尾不吃后缀）；
#           名字可带宿主（`ShoreDraft.deal`），宿主前同样不接标识符或点。新写「有没有这支函数 / 调没调」的断言用它们。
def _has_func(src, name):
    return re.search(rf"^[ \t]*(?:static\s+)?func\s+{re.escape(name)}\s*\(", src, re.M) is not None


def _calls(src, name):
    return re.search(rf"(?<![\w.]){re.escape(name)}\s*(?:\(|\.(?:bind|call|callv)\s*\()", src) is not None

order_idx = {name: i for i, name in enumerate(order)}
ready_problems = []
for name, rel in AUTOLOADS.items():
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        src = f.read()
    bodies = func_bodies(src)
    if "_ready" not in bodies:
        continue
    # 从 _ready 出发展开本地调用链，直到不动点——两层以上的间接依赖同样会崩
    seen_fn = {"_ready"}
    frontier = ["_ready"]
    while frontier:
        fn = frontier.pop()
        for local in re.findall(r'\b([a-z_]\w*)\s*\(', bodies.get(fn, "")):
            if local in bodies and local not in seen_fn:
                seen_fn.add(local)
                frontier.append(local)
    reach = "\n".join(bodies.get(fn, "") for fn in seen_fn)
    touched = {o for o in AUTOLOADS if o != name and re.search(rf'\b{o}\.', reach)}
    for t in touched:
        if order_idx.get(t, 99) > order_idx.get(name, 99):
            ready_problems.append(f"{name}._ready 触及 {t}，但 {t} 注册在其之后")
            print(f"  ✗ {name}._ready → {t}（{t} 排在后面，此时尚未就绪）")
        else:
            print(f"  ✓ {name}._ready → {t}（已就绪）")
if not ready_problems:
    print("  ✓ 无 _ready 期的逆序依赖")
problems.extend(ready_problems)

print()
print("=" * 68)
print("二、跨文件引用检查")
print("=" * 68)

# Godot 内置成员，出现在 autoload 上是合法的。lane cs3：不再手写，改读 ClassDB 导出的清单——
#   tools/gen_builtin_list.gd → tools/builtin_api.txt（每类只列本类新增成员，inherits 行给继承链；
#   「== signal ==」之后是只导信号的类，供二之二 / 二之三，lane cs5）；
#   重生成：python3 tools/check_symbols.py --regen。每个 autoload 按自己的 extends 链合并放行。
BUILTIN_LIST = os.path.join(ROOT, "tools", "builtin_api.txt")
# 手写补充段：ClassDB 里查不到、GDScript 语法层却合法的名字（脚本类 .new()、Signal.emit / Callable.bind、容器 size / keys）
BUILTIN_EXTRA = {"new", "emit", "bind", "size", "keys"}


def _godot_bin():
    import shutil
    for c in (os.environ.get("GODOT"), shutil.which("godot"), os.path.expanduser("~/.local/bin/godot")):
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def _regen_builtin_list():
    """--regen：跑 godot 从 ClassDB 重导清单；与现有逐字节比对，不同才落盘。返回是否成功。"""
    import subprocess, tempfile
    godot = _godot_bin()
    if not godot:
        print("  ✗ --regen：找不到 godot（$GODOT / PATH / ~/.local/bin/godot）")
        return False
    fd, tmp = tempfile.mkstemp(suffix=".txt")
    os.close(fd)
    try:
        r = subprocess.run([godot, "--headless", "--path", ROOT, "-s", "res://tools/gen_builtin_list.gd", "--", tmp],
                           capture_output=True, text=True, timeout=300)
        new = open(tmp, encoding="utf-8").read() if os.path.exists(tmp) else ""
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    if r.returncode != 0 or "GEN_BUILTIN_LIST OK" not in r.stdout or not new:
        print(f"  ✗ --regen：gen_builtin_list.gd 失败（rc={r.returncode}）")
        for ln in (r.stdout + r.stderr).strip().splitlines()[-5:]:
            print(f"      {ln}")
        return False
    old = open(BUILTIN_LIST, encoding="utf-8").read() if os.path.exists(BUILTIN_LIST) else ""
    if old == new:
        print("  ✓ --regen：ClassDB 导出与 tools/builtin_api.txt 逐字节一致，未改动")
        return True
    ol, nl = set(old.splitlines()[3:]), set(new.splitlines()[3:])
    with open(BUILTIN_LIST, "w", encoding="utf-8") as f:
        f.write(new)
    print(f"  ↻ --regen：已按 ClassDB 重写 tools/builtin_api.txt（+{len(nl - ol)} / −{len(ol - nl)} 行；请连同提交）")
    return True


def _read_builtin_list():
    """返回 (godot 版本, {类: (父类, 成员集)}, {类: (父类, 信号集)}, 问题列表)。头三行：说明 / godot 版本 / 正文 sha256。"""
    import hashlib
    if not os.path.exists(BUILTIN_LIST):
        return None, {}, {}, ["tools/builtin_api.txt 不存在"]
    text = open(BUILTIN_LIST, encoding="utf-8").read()
    head = text.split("\n", 3)
    if len(head) < 4 or not head[1].startswith("# godot ") or not head[2].startswith("# sha256 "):
        return None, {}, {}, ["tools/builtin_api.txt 头部缺 godot 版本 / sha256 行"]
    ver, want, body = head[1][len("# godot "):], head[2][len("# sha256 "):], head[3]
    errs = []
    if hashlib.sha256(body.encode("utf-8")).hexdigest() != want:
        errs.append("tools/builtin_api.txt 正文与头部 sha256 不符（被手改或截断）")
    # 「== signal ==」之前是全量段（成员放行用）；之后是只导信号的类（lane cs5，二之二 / 二之三认基类信号用）
    full, sigs, cur, sig_only = {}, {}, None, False
    for ln in body.split("\n"):
        if ln == "== signal ==":
            cur, sig_only = None, True
        elif ln.startswith("[") and ln.endswith("]"):
            cur = ln[1:-1]
            sigs[cur] = ["", set()]
            if not sig_only:
                full[cur] = ["", set()]
        elif cur and ln.startswith("inherits"):
            sigs[cur][0] = ln[len("inherits"):].strip()
            if not sig_only:
                full[cur][0] = sigs[cur][0]
        elif cur and ln:
            kind, _, name = ln.partition(" ")
            if kind == "signal":
                sigs[cur][1].add(name)
            if not sig_only:
                full[cur][1].add(name)
    return ver, {k: tuple(v) for k, v in full.items()}, {k: tuple(v) for k, v in sigs.items()}, errs


def builtin_members(cls):
    """cls 及其清单内祖先的全部内置成员；链上有类不在清单里则返回 None。"""
    out, seen = set(), set()
    while cls and cls not in seen:
        seen.add(cls)
        if cls not in BUILTIN_CLASSES:
            return None
        parent, mem = BUILTIN_CLASSES[cls]
        out |= mem
        cls = parent
    return out


if "--regen" in sys.argv[1:] and not _regen_builtin_list():
    problems.append("--regen 重导内置清单失败")
BUILTIN_VER, BUILTIN_CLASSES, BUILTIN_SIGNALS, _bl_errs = _read_builtin_list()
_bl_godot = _godot_bin()
_bl_local = None
if _bl_godot and BUILTIN_VER:
    try:
        import subprocess
        _bl_local = subprocess.run([_bl_godot, "--version"], capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        _bl_local = None
if _bl_local and BUILTIN_VER != _bl_local:
    _bl_errs.append(f"tools/builtin_api.txt 导自 godot {BUILTIN_VER}，本机 godot {_bl_local}，ClassDB 可能已变")
# 各 autoload 按 extends 链放行（不写 extends 的 GDScript 默认 RefCounted）
BUILTIN_FOR = {}
for _auto, _rel in AUTOLOADS.items():
    _ext = re.search(r'^extends\s+([A-Za-z_]\w*|"[^"]*")', code_only(open(os.path.join(ROOT, _rel), encoding="utf-8").read()), re.M)
    _base = _ext.group(1) if _ext else "RefCounted"
    _mem = builtin_members(_base)
    if _mem is None:
        if BUILTIN_CLASSES:
            _bl_errs.append(f"autoload {_auto} extends {_base}，清单链上缺类：把它加进 tools/gen_builtin_list.gd 的 CLASSES")
        _mem = set()
    BUILTIN_FOR[_auto] = _mem | BUILTIN_EXTRA
# 供别节沿用的 Node 链全集（autoload 都 extends Node）
BUILTIN = (builtin_members("Node") or set()) | BUILTIN_EXTRA
if _bl_errs:
    for _e in _bl_errs:
        print(f"  ✗ {_e} → 跑 python3 tools/check_symbols.py --regen")
        problems.append(_e)
else:
    _node_n = len(builtin_members("Node") or ())
    print(f"  ✓ 内置清单 tools/builtin_api.txt（godot {BUILTIN_VER}{'' if _bl_local else '；未找到本机 godot，未比对版本'}）："
          f"{len(BUILTIN_CLASSES)} 类，Object→Node 链 {_node_n} 名 + 手写补充 {len(BUILTIN_EXTRA)} 名")

miss_count = 0
_n_tools = sum(1 for p in GD_FILES if not p.startswith(SCRIPTS + os.sep))
print(f"  检查面：scripts/ {len(GD_FILES) - _n_tools} 个 + tools/ {_n_tools} 个 .gd（带 legacy 段的目录不查）")
for path in GD_FILES:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as f:
            src = f.read()
        # 去掉注释与字符串：文档示例、文案里的 "Economy.xx" 不算引用；
        # 也不能按 # 截行——"[color=#c00]" + str(Economy.xx) 的后半截要照查
        src_nc = code_only(src)

        file_problems = []
        for auto, members in defined.items():
            # 跳过自身
            if AUTOLOADS[auto] == rel.replace(os.sep, "/"):
                continue
            for m in re.finditer(rf'\b{auto}\.([A-Za-z_]\w*)', src_nc):
                attr = m.group(1)
                if attr in members or attr in BUILTIN_FOR[auto]:
                    continue
                line = src_nc[:m.start()].count("\n") + 1
                file_problems.append((line, f"{auto}.{attr}"))

        # enum 成员引用 Voyage.EventKind.XXX
        for auto, enums in enum_map.items():
            for ename, evals in enums.items():
                for m in re.finditer(rf'\b{auto}\.{ename}\.([A-Za-z_]\w*)', src_nc):
                    if m.group(1) not in evals:
                        line = src_nc[:m.start()].count("\n") + 1
                        file_problems.append((line, f"{auto}.{ename}.{m.group(1)}"))

        if file_problems:
            print(f"\n  ✗ {rel}")
            for line, ref in sorted(set(file_problems)):
                print(f"      L{line}: {ref}  ← 未定义")
                miss_count += 1
                problems.append(f"{rel}:{line} {ref}")

if miss_count == 0:
    print("  ✓ 所有 autoload 成员引用均已定义")

print()
print("=" * 68)
print("二之二、emit 的信号是否都还存在")
print("=" * 68)
print("  删掉 signal 却漏了某处 emit，只有跑到那一行才炸。")
print("  本文件 / extends 链上的父脚本 / 引擎基类内置信号 / 声明为 Signal 的变量与形参 都算有来处。")
# 引擎基类的自有信号读 tools/builtin_api.txt（全量段 + 「== signal ==」段，lane cs5 并掉 cs2 手抄表）；
# 链走到清单外的引擎类就不再放宽——照旧只认脚本里的声明。要认新基类：加进 gen_builtin_list.gd 的 SIGNAL_CLASSES 再 --regen


def _native_signals(cls):
    """引擎类 cls 连同祖先的内置信号；链上有类不在清单里返回 None"""
    out, seen = set(), set()
    while cls and cls not in seen:
        seen.add(cls)
        if cls not in BUILTIN_SIGNALS:
            return None
        parent, sigs = BUILTIN_SIGNALS[cls]
        out |= sigs
        cls = parent
    return out


_EXTENDS_RE = re.compile(r'^(?:class_name\s+\w+\s+)?extends\s+("[^"\n]+"|\'[^\'\n]+\'|[A-Za-z_][\w.]*)', re.M)
_CLASS_NAME_RE = re.compile(r'^class_name\s+([A-Za-z_]\w*)', re.M)
_script_meta = {}  # 绝对路径 -> (本文件 signal 集合, 原始 extends 目标 或 None)
_class_paths = {}  # class_name -> 绝对路径
for dirpath, dirnames, files in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if not d.startswith(".")]
    for fn in files:
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dirpath, fn)
        with open(path, encoding="utf-8") as f:
            raw = f.read()
        # extends 目标可以是字符串路径，得在 code_only 抹掉字符串之前取；只认顶格（内部 class 缩进在里面）
        top = "\n".join(ln for ln in raw.split("\n") if not ln.lstrip().startswith("#"))
        ext = _EXTENDS_RE.search(top)
        cn = _CLASS_NAME_RE.search(top)
        if cn:
            _class_paths.setdefault(cn.group(1), path)
        sigs = set(re.findall(r'^\s*signal\s+([A-Za-z_]\w*)', code_only(raw), re.M))
        _script_meta[path] = (sigs, ext.group(1) if ext else None)


def _chain_signals(path):
    """返回 (extends 链上所有可 emit 的信号, 链尾说明)。链尾是表外引擎类 / 找不到的父脚本时不放宽，只带已走到的脚本声明"""
    out, seen, cur = set(), set(), path
    while cur and cur not in seen:
        seen.add(cur)
        sigs, ext = _script_meta.get(cur, (set(), None))
        out |= sigs
        if ext is None:
            ext = "RefCounted"  # Godot 4：不写 extends 即 RefCounted
        if ext[0] in "\"'":
            target = ext[1:-1]
            if target.startswith("res://"):
                cur = os.path.join(ROOT, target[len("res://"):])
            else:
                cur = os.path.normpath(os.path.join(os.path.dirname(cur), target))
            if cur not in _script_meta:
                return out, f"父脚本 {target} 不存在"
            continue
        if ext in _class_paths:
            cur = _class_paths[ext]
            continue
        native = _native_signals(ext)
        if native is None:
            return out, f"基类 {ext} 不在内置信号表"
        return out | native, None
    return out, None


# var s: Signal / var s := Signal(…) / 形参 s: Signal——这些名字 .emit() 是在发一个 Signal 值，不对声明
_SIGNAL_VAR_RE = re.compile(
    r'\bvar\s+([A-Za-z_]\w*)\s*(?::\s*Signal\b|:?=\s*Signal\s*\()'
    r'|[(,]\s*([A-Za-z_]\w*)\s*:\s*Signal\b')

orphan_total = 0
for path in GD_FILES:
        with open(path, encoding="utf-8") as f:
            src = code_only(f.read())  # 注释、字符串里的 xx.emit() 不算
        declared, chain_note = _chain_signals(path)
        signal_vars = {a or b for a, b in _SIGNAL_VAR_RE.findall(src)}
        # 前面带点的是跨对象 emit（Autoload.sig.emit 归第二节、btn.pressed.emit 不核），不归本文件管；self.sig.emit 仍算本文件
        emitted = set(re.findall(r'(?:(?<![.\w])self\.|(?<![.\w]))([A-Za-z_]\w*)\.emit\s*\(', src))
        for o in sorted(emitted - declared - signal_vars):
            where = "本文件与 extends 链上均无此 signal" + (f"（{chain_note}）" if chain_note else "")
            print(f"  ✗ {os.path.relpath(path, ROOT)}: {o}.emit() 但{where}")
            problems.append(f"{os.path.relpath(path, ROOT)} emit 已删除的 {o}")
            orphan_total += 1
if orphan_total == 0:
    print("  ✓ 所有 emit 都有对应的 signal 声明")

if SUGGEST:
    print()
    print("=" * 68)
    print("二之三、字符串派发候选提示（--suggest：只提示，不判红，退出码不变）")
    print("=" * 68)
    print("  emit_signal(\"…\") / X.call|call_deferred|callv(\"…\") / Callable(obj, \"…\") 的字面量当候选名；")
    print("  接收者是本文件（裸写 / self）→ 查本文件及 extends 链，是 autoload → 查该 autoload，")
    print("  裸标识符接收者能静态定型的（lane cs6：preload/load(…gd).new()、Const/ClassName.new()、")
    print("  `: ClassName` 注解含参数、set_script(…)、.tscn.instantiate()、get_node(\"/root/Autoload\")、")
    print("  经局部变量转手）→ 查该类及 extends 链（注解另并子类）；")
    print("  其余类型未知 → 只查全仓 func / signal 并集。名字压根不存在才打 ⚠ WARN，需人工判。")

    def _code_mask(src):
        """逐字符标出「代码」位置（非字符串、非注释），与 code_only 同一扫法。"""
        mask = bytearray(len(src))
        i, n = 0, len(src)
        while i < n:
            c = src[i]
            if c in ('"', "'"):
                q = c * 3 if src.startswith(c * 3, i) else c
                i += len(q)
                while i < n:
                    if src[i] == "\\":
                        i += 2
                        continue
                    if src.startswith(q, i):
                        i += len(q)
                        break
                    i += 1
                continue
            if c == "#":
                while i < n and src[i] != "\n":
                    i += 1
                continue
            mask[i] = 1
            i += 1
        return mask

    # Object / Node / CanvasItem / Control 常见方法——扫描字面量时视为引擎内置，不提示（信号走清单，见 _sg_scope）
    ENGINE_METHODS = BUILTIN | {
        "add_sibling", "queue_redraw", "show", "hide", "grab_focus", "release_focus",
        "set_position", "set_size", "set_visible", "set_modulate", "set_text", "set_process_input",
        "set_anchors_preset", "set_anchors_and_offsets_preset", "play", "stop", "start",
        "_ready", "_process", "_physics_process", "_input", "_unhandled_input", "_draw",
        "_notification", "_enter_tree", "_exit_tree", "_init", "_gui_input",
        # SceneTree（tools/ 探针多 extends SceneTree）
        "quit", "create_timer", "change_scene_to_file", "change_scene_to_packed",
        "reload_current_scene", "call_group", "set_pause",
    }

    _sg_files = []
    for _sg_dir in (SCRIPTS, os.path.join(ROOT, "tools")):
        for dirpath, _, files in os.walk(_sg_dir):
            for fn in sorted(files):
                if fn.endswith(".gd"):
                    _sg_files.append(os.path.join(dirpath, fn))
    _sg_info, _sg_class = {}, {}
    for path in _sg_files:
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        with open(path, encoding="utf-8") as f:
            src = f.read()
        code = code_only(src)
        pre = r'^\s*(?:@\w+(?:\([^)\n]*\))?\s+)*(?:static\s+)?'
        funcs = set(re.findall(pre + r'func\s+([A-Za-z_]\w*)', code, re.M))
        sigs = set(re.findall(pre + r'signal\s+([A-Za-z_]\w*)', code, re.M))
        ext = re.search(r'^extends\s+(?:"res://([^"]+)"|([A-Za-z_]\w*))', src, re.M)
        cls = re.search(r'^class_name\s+([A-Za-z_]\w*)', src, re.M)
        if cls:
            _sg_class[cls.group(1)] = rel
        _sg_info[rel] = {"src": src, "funcs": funcs, "sigs": sigs,
                         "ext": (ext.group(1) or ext.group(2)) if ext else None}

    def _sg_scope(rel, seen=None):
        """本脚本 + extends 链上各脚本的 (func, signal)。func 链尾落到引擎类时补 ENGINE_METHODS；
        signal 与二之二同走 _chain_signals（脚本声明 + 清单里该引擎基类链的信号，链出清单不放宽）。"""
        seen = seen or set()
        info = _sg_info.get(rel)
        if info is None or rel in seen:
            return set(ENGINE_METHODS), set()
        seen.add(rel)
        funcs = set(info["funcs"])
        parent = info["ext"]
        parent_rel = parent if parent and parent.endswith(".gd") else _sg_class.get(parent)
        pf = _sg_scope(parent_rel, seen)[0] if parent_rel else set(ENGINE_METHODS)
        return funcs | pf, _chain_signals(os.path.join(ROOT, rel))[0]

    _sg_all_funcs = set(ENGINE_METHODS).union(*(i["funcs"] for i in _sg_info.values()))
    # 接收者类型未知：清单里全部引擎信号 + 全仓脚本 signal 的并集
    _sg_all_sigs = set().union(*(g for _, g in BUILTIN_SIGNALS.values()), *(i["sigs"] for i in _sg_info.values()))
    _sg_auto = {a: _sg_scope(r) for a, r in AUTOLOADS.items() if r in _sg_info}

    # —— lane cs6：裸标识符接收者的轻量类型推断（宁可推不出，推不出就落回全仓并集）——
    # 定型来源（脚本表达式 S = preload|load("res://X.gd") / 本文件 const 指向 .gd / class_name / 只赋一次的局部别名）：
    # ① `var x := / = S.new()`（可包 `(S as GDScript)`、尾随 `as T`）；② 注解 `var x: ClassName` 与参数
    # `x: ClassName`（ClassName 为 class_name 或本文件 const 脚本）→ 该类 + 全部子类；③ `x.set_script(S)`；
    # ④ `x = y`，y 在该处同样能定型（至多 3 跳）；⑤ `P.instantiate()`，P 为 .tscn 的 preload/load / const / 别名
    # → 场景根节点脚本（根节点无脚本即推不出）；⑥ `root.get_node("Auto")` / `get_node("/root/Auto")`（含 _or_null）
    # → 该 autoload 脚本；⑦ 脚本资源本身（`var s = load("res://X.gd")`，`s.call("静态函数")`）；⑧ 读属性
    # `y.get("p")` / `y.p`（y 能定型、p 在其类型上是能定型的成员 var）。
    # 赋 null 的不计（不改类型），其余只要一处推不出即未知。
    # 无工程类注解时，作用域内对 x 的**每一次**赋值（含声明初值）都须能定型才算定型，取并集；有一处推不出即未知。
    # 作用域：接收者所在 func 里有 `var x` / 参数 x 就按局部，否则按本文件顶层 `var x`（全文件赋值都算）。
    _SG_ID = r'[A-Za-z_]\w*'
    _sg_children = collections.defaultdict(set)  # rel -> 直接子类 rel

    def _sg_parent_rel(rel):
        parent = _sg_info[rel]["ext"]
        return parent if parent and parent.endswith(".gd") else _sg_class.get(parent)

    for _r in _sg_info:
        _pr = _sg_parent_rel(_r)
        if _pr:
            _sg_children[_pr].add(_r)

    def _sg_subtree(rel):
        out, todo = set(), [rel]
        while todo:
            r = todo.pop()
            if r not in out:
                out.add(r)
                todo += _sg_children.get(r, ())
        return out

    def _sg_engine_tail(rel, seen=()):
        """extends 链落到的引擎类名（Control / CanvasLayer …）；链断或成环返回 None。"""
        while rel in _sg_info and rel not in seen:
            seen = seen + (rel,)
            parent = _sg_info[rel]["ext"]
            nxt = _sg_parent_rel(rel)
            if not nxt:
                return parent if parent and not parent.endswith(".gd") else None
            rel = nxt
        return None

    def _sg_type_scope(rels):
        """一组可能类型的 (func, signal) 并集。func 链尾引擎类在 builtin_api.txt 全量段里的，把它的内置成员也并上
        （ENGINE_METHODS 只是 Node 一带）；signal 照 _sg_scope 走 _chain_signals，不另放宽。"""
        funcs, sigs = set(), set()
        for r in rels:
            f, g = _sg_scope(r)
            tail = _sg_engine_tail(r)
            funcs |= f | ((builtin_members(tail) if tail else None) or set())
            sigs |= g
        return funcs, sigs

    _sg_text_cache = {}

    def _sg_text(rel):
        """源码去注释（注释字符换成空格）、字符串原样保留——偏移与原文一一对应。"""
        if rel not in _sg_text_cache:
            src = _sg_info[rel]["src"]
            mask = _code_mask(src)
            out = list(src)
            i, n = 0, len(src)
            while i < n:
                if not mask[i] and src[i] == "#":
                    while i < n and src[i] != "\n":
                        out[i] = " "
                        i += 1
                    continue
                if not mask[i] and src[i] in ('"', "'"):
                    q = src[i] * 3 if src.startswith(src[i] * 3, i) else src[i]
                    i += len(q)
                    while i < n:
                        if src[i] == "\\":
                            i += 2
                            continue
                        if src.startswith(q, i):
                            i += len(q)
                            break
                        i += 1
                    continue
                i += 1
            _sg_text_cache[rel] = "".join(out)
        return _sg_text_cache[rel]

    _sg_consts_cache = {}

    def _sg_consts(rel):
        """本文件顶层 const：名 -> 右值表达式。"""
        if rel not in _sg_consts_cache:
            _sg_consts_cache[rel] = {m.group(1): m.group(2) for m in re.finditer(
                r'^const\s+(' + _SG_ID + r')\s*(?::\s*\w+\s*)?:?=\s*(.+?)\s*$', _sg_text(rel), re.M)}
        return _sg_consts_cache[rel]

    def _sg_balanced(e):
        d = 0
        for c in e:
            d += (c == "(") - (c == ")")
            if d < 0:
                return False
        return d == 0

    def _sg_strip(e):
        e = e.strip()
        while True:
            m = re.fullmatch(r'(.+?)\s+as\s+' + _SG_ID, e, re.S)
            if m and _sg_balanced(m.group(1)):
                e = m.group(1).strip()
                continue
            if e.startswith("(") and e.endswith(")") and _sg_balanced(e[1:-1]):
                e = e[1:-1].strip()
                continue
            return e

    _sg_scene_cache = {}

    def _sg_scene_script(path, depth=0):
        """.tscn 根节点脚本 rel（根是另一场景实例则顺下去）；无脚本 / 读不到返回 None。"""
        if path in _sg_scene_cache:
            return _sg_scene_cache[path]
        _sg_scene_cache[path] = None
        fp = os.path.join(ROOT, path)
        if depth > 4 or not os.path.exists(fp):
            return None
        with open(fp, encoding="utf-8") as f:
            txt = f.read()
        ext = {m.group(2): m.group(1) for m in re.finditer(
            r'^\[ext_resource\b[^\]]*?\bpath="res://([^"]+)"[^\]]*?\bid="([^"]+)"', txt, re.M)}
        ext.update({m.group(1): m.group(2) for m in re.finditer(
            r'^\[ext_resource\b[^\]]*?\bid="([^"]+)"[^\]]*?\bpath="res://([^"]+)"', txt, re.M)})
        root = re.search(r'^\[node\b(?![^\]]*\bparent=)([^\]]*)\]\n((?:(?!\[).*\n?)*)', txt, re.M)
        out = None
        if root:
            sm = re.search(r'^script\s*=\s*ExtResource\(\s*"([^"]+)"\s*\)', root.group(2), re.M)
            im = re.search(r'\binstance=ExtResource\(\s*"([^"]+)"\s*\)', root.group(1))
            if sm and ext.get(sm.group(1), "").endswith(".gd"):
                out = ext[sm.group(1)] if ext[sm.group(1)] in _sg_info else None
            elif not sm and im and ext.get(im.group(1), "").endswith(".tscn"):
                out = _sg_scene_script(ext[im.group(1)], depth + 1)
        _sg_scene_cache[path] = out
        return out

    def _sg_res(e, rel, ctx, depth):
        """资源表达式 → ('gd', rel) | ('tscn', path) | None。ctx=(text, 基准偏移, 所在位置)。"""
        e = _sg_strip(e)
        m = re.fullmatch(r'(?:preload|load|ResourceLoader\.load)\(\s*(?:"res://([^"]+)"|(' + _SG_ID + r'))\s*\)', e)
        if m:
            path = m.group(1)
            if not path:
                c = _sg_consts(rel).get(m.group(2), "")
                path = c[7:-1] if re.fullmatch(r'"res://[^"\\]+"', c) else None
        elif re.fullmatch(_SG_ID, e) and depth < 3:
            c = _sg_consts(rel).get(e)
            if c is not None:
                return _sg_res(c, rel, None, depth + 1)
            if e in _sg_class:
                return ("gd", _sg_class[e])
            if ctx is None:
                return None
            decl = _sg_decl(rel, e, ctx[2])  # 局部别名：作用域里恰好一处赋值
            if decl is None or len(decl[2]) != 1 or decl[2][0][0] is None:
                return None
            return _sg_res(decl[2][0][0], rel, (decl[0], decl[1], decl[2][0][1]), depth + 1)
        else:
            return None
        if path and path.endswith(".gd") and path in _sg_info:
            return ("gd", path)
        if path and path.endswith(".tscn"):
            return ("tscn", path)
        return None

    def _sg_call_head(e, meth):
        """`<head>.meth(…)` → head；否则 None。"""
        e = _sg_strip(e)
        if not e.endswith(")"):
            return None
        d, i = 0, len(e) - 1
        while i >= 0:
            d += (e[i] == ")") - (e[i] == "(")
            if d == 0:
                break
            i -= 1
        head = e[:i].rstrip()
        if i <= 0 or not head.endswith("." + meth) or not _sg_balanced(e[i + 1:-1]):
            return None
        return head[:-len(meth) - 1]

    def _sg_value(e, rel, ctx, depth):
        """赋值右值 → 可能的脚本 rel 集合；推不出 None。"""
        if e is None or depth > 3:
            return None
        h = _sg_call_head(e, "new")
        if h is not None:
            r = _sg_res(h, rel, ctx, depth)
            return {r[1]} if r and r[0] == "gd" else None
        h = _sg_call_head(e, "instantiate")
        if h is not None:
            r = _sg_res(h, rel, ctx, depth)
            s_ = _sg_scene_script(r[1]) if r and r[0] == "tscn" else None
            return {s_} if s_ else None
        e2 = _sg_strip(e)
        if re.fullmatch(r'(?:preload|load|ResourceLoader\.load)\(.*\)', e2):
            r = _sg_res(e2, rel, ctx, depth)  # 脚本资源本身：x.call("静态函数")
            return {r[1]} if r and r[0] == "gd" else None
        pm = re.fullmatch(r'(' + _SG_ID + r')(?:\.get\(\s*&?"(' + _SG_ID + r')"\s*\)|\.(' + _SG_ID + r'))', e2)
        if pm and ctx is not None and pm.group(1) != "self":
            # 读属性：y.get("p") / y.p，y 能定型、p 是其各类型上能定型的成员 var
            owners = _sg_infer(rel, pm.group(1), ctx[2], depth + 1)
            if not owners:
                return None
            out = set()
            for o in owners:
                r = _sg_infer(o, pm.group(2) or pm.group(3), -1, depth + 1)
                if not r:
                    return None
                out |= r
            return out
        am = re.fullmatch(r'(?:(?:root|get_tree\(\)\.root)\.get_node(?:_or_null)?\(\s*"(?:/root/)?|'
                          r'(?:\w+\.)?get_node(?:_or_null)?\(\s*"/root/)(' + _SG_ID + r')"\s*\)', e2)
        if am:
            return {AUTOLOADS[am.group(1)]} if AUTOLOADS.get(am.group(1)) in _sg_info else None
        if re.fullmatch(_SG_ID, e2) and e2 not in ("self", "null") and ctx is not None:
            r = _sg_infer(rel, e2, ctx[2], depth + 1)
            if r is None and (e2 in _sg_class or e2 in _sg_consts(rel)):
                r2 = _sg_res(e2, rel, None, depth)
                r = {r2[1]} if r2 and r2[0] == "gd" else None
            return r
        return None

    def _sg_assigns(name, text, base):
        """text 里对 name 的全部赋值：[(右值 | None, 文件偏移)]。`var name` 无初值不计；续行未合上记 None。"""
        out = []
        pat = re.compile(r'^[ \t]*(?:var\s+' + re.escape(name) + r'\s*(?::\s*[\w.]*\s*)?(:?=)?|(?:self\.)?'
                         + re.escape(name) + r'\s*(=))(?!=)[ \t]*(.*)$', re.M)
        for m in pat.finditer(text):
            if m.group(1) is None and m.group(2) is None:
                continue
            v = m.group(3).strip()
            out.append((v if v and _sg_balanced(v) else None, base + m.start()))
        return out

    def _sg_annot_rel(t, rel):
        if not t:
            return None
        r = _sg_res(t, rel, None, 0)
        return r[1] if r and r[0] == "gd" else None

    _sg_funcspans = {}

    def _sg_enclosing(rel, pos):
        """pos 所在（最内层）func 的 (起点偏移, 签名行, 函数体文本)；不在 func 里返回 None。"""
        if rel not in _sg_funcspans:
            code = _sg_text(rel)
            lines = code.split("\n")
            spans, starts, off = [], [], 0
            for ln in lines:
                starts.append(off)
                off += len(ln) + 1
            for k, ln in enumerate(lines):
                fm = re.match(r'^([ \t]*)(?:static\s+)?func\s+' + _SG_ID, ln)
                if not fm:
                    continue
                ind = len(fm.group(1))
                e = k + 1
                while e < len(lines):
                    t = lines[e]
                    if t.strip() and len(t) - len(t.lstrip()) <= ind and not t.lstrip().startswith(")"):
                        break
                    e += 1
                spans.append((starts[k], starts[e] if e < len(lines) else len(code), ln, "\n".join(lines[k:e])))
            _sg_funcspans[rel] = spans
        best = None
        for a, b, sig, body in _sg_funcspans[rel]:
            if a <= pos < b and (best is None or a >= best[0]):
                best = (a, sig, body)
        return best

    def _sg_decl(rel, name, pos):
        """name 在 pos 处的声明：(作用域文本, 基准偏移, 赋值表, 注解类型名 | None, 是否参数)；找不到 None。"""
        enc = _sg_enclosing(rel, pos)
        if enc is not None:
            base, sig, body = enc
            pm = re.search(r'[(,]\s*' + re.escape(name) + r'\s*(?::\s*(' + _SG_ID + r'))?\s*(?::?=[^,)]*)?\s*[,)]', sig)
            if pm:
                return (body, base, [], pm.group(1), True)
            dm = re.search(r'^[ \t]*var\s+' + re.escape(name) + r'\b\s*(?::\s*(' + _SG_ID + r'))?', body, re.M)
            if dm:
                return (body, base, _sg_assigns(name, body, base), dm.group(1), False)
            if re.search(r'^[ \t]*for\s+' + re.escape(name) + r'\b|\bfunc\s*\([^)]*\b' + re.escape(name) + r'\b',
                         body, re.M):
                return None  # for 变量 / lambda 参数
        code = _sg_text(rel)
        dm = re.search(r'^var\s+' + re.escape(name) + r'\b\s*(?::\s*(' + _SG_ID + r'))?', code, re.M)
        if not dm:
            return None
        return (code, 0, _sg_assigns(name, code, 0), dm.group(1), False)

    def _sg_infer(rel, recv, pos, depth=0):
        """推出接收者可能的脚本 rel 集合；推不出返回 None。"""
        if depth > 3 or not re.fullmatch(_SG_ID, recv) or recv in AUTOLOADS or recv in _sg_class:
            return None
        decl = _sg_decl(rel, recv, pos)
        if decl is None:
            return None
        text, base, vals, annot, is_param = decl
        t = _sg_annot_rel(annot, rel)
        if t:
            return _sg_subtree(t)
        if is_param:
            return None  # 无注解 / 引擎类注解的参数：来路不明
        types = set()
        for sm in re.finditer(r'\b' + re.escape(recv) + r'\.set_script\(', text):
            j, d = sm.end(), 1
            while j < len(text) and d:
                d += (text[j] == "(") - (text[j] == ")")
                j += 1
            r = _sg_res(text[sm.end():j - 1], rel, (text, base, base + sm.start()), depth)
            if not r or r[0] != "gd":
                return None
            types.add(r[1])
        if not types and all(v == "null" for v, _ in vals):
            return None
        for v, at in vals:
            if v == "null":
                continue  # 置空不改类型（对 null 调用本来就会炸，不归这里管）
            if types and (_bm := re.fullmatch(r'(' + _SG_ID + r')\.new\(\s*\)', v or "")) \
                    and _bm.group(1) in BUILTIN_CLASSES and _bm.group(1) not in _sg_consts(rel):
                continue  # 有 set_script 时，`Node.new()` 这类裸引擎对象只是挂脚本前的底子
            r = _sg_value(v, rel, (text, base, at), depth)
            if not r:
                return None
            types |= r
        return types

    _SG_DISPATCH = re.compile(r'\b(emit_signal|call_deferred|callv|call)\s*\(\s*&?"([^"\\\n]*)"')
    _SG_CALLABLE = re.compile(r'\bCallable\s*\(\s*((?:[^,()\n]|\(\))+?)\s*,\s*&?"([^"\\\n]*)"')
    _sg_tally = collections.Counter()
    _sg_warns = []
    for rel in sorted(_sg_info):
        src = _sg_info[rel]["src"]
        mask = _code_mask(src)
        own = _sg_scope(rel)
        hits = []
        for m in _SG_DISPATCH.finditer(src):
            if not mask[m.start()]:
                continue
            before = _sg_text(rel)[:m.start()].rstrip()  # 去注释再看，免得上一行注释末的「.」被当成接收者
            if before.endswith("."):
                rm = re.search(r'([A-Za-z_]\w*)\s*$', before[:-1])
                recv = rm.group(1) if rm and not before[:-1].rstrip()[:rm.start()].rstrip().endswith(".") else None
                recv = recv if recv else "（表达式）"
            else:
                recv = "self"
            hits.append((m.start(), m.group(1), recv, m.group(2), f'{m.group(1)}("{m.group(2)}")'))
        for m in _SG_CALLABLE.finditer(src):
            if mask[m.start()]:
                hits.append((m.start(), "Callable", m.group(1).strip(), m.group(2),
                             f'Callable({m.group(1).strip()}, "{m.group(2)}")'))
        for pos, kind, recv, name, shown in sorted(hits):
            want_sig = kind == "emit_signal"
            if recv == "self":
                scope, where = own[1 if want_sig else 0], "本文件及 extends 链"
                _sg_tally["本文件"] += 1
            elif recv in _sg_auto:
                scope, where = _sg_auto[recv][1 if want_sig else 0], f"autoload {recv}"
                _sg_tally["autoload"] += 1
            elif (_inf := _sg_infer(rel, recv, pos)):
                scope = _sg_type_scope(_inf)[1 if want_sig else 0]
                _names = sorted(os.path.basename(r)[:-3] for r in _inf)
                where = f"推断 {recv}: {' | '.join(_names[:3])}{' …' if len(_names) > 3 else ''} 及 extends 链"
                _sg_tally["推断"] += 1
            else:
                scope = _sg_all_sigs if want_sig else _sg_all_funcs
                where = f"全仓（接收者 {recv} 类型未知）"
                _sg_tally["未知接收者"] += 1
            if name in scope:
                continue
            line = src[:pos].count("\n") + 1
            if recv not in ("self", "（表达式）") and kind != "Callable":
                shown = f"{recv}.{shown}"
            _sg_warns.append(f"{rel}:L{line} {shown}  ← {where}：无此 {'signal' if want_sig else 'func'}")
    print(f"  字面量 {sum(_sg_tally.values())} 处：本文件 {_sg_tally['本文件']} · autoload {_sg_tally['autoload']}"
          f" · 推断定型 {_sg_tally['推断']} · 未知接收者 {_sg_tally['未知接收者']}（扫 scripts/ + tools/ 共 {len(_sg_info)} 个 .gd）")
    for w in _sg_warns:
        print(f"  ⚠ WARN {w}")
    if not _sg_warns:
        print("  （无候选死引用）")

print()
print("=" * 68)
print("三、缩进与括号一致性")
print("=" * 68)
for path in GD_FILES:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        # GDScript 用 Tab 缩进；逻辑行的缩进里混进空格（含 Tab 后跟空格）会报 Parse Error。
        # 括号内 / \\ 后的续行、多行字符串里的行，缩进不作数，不查。
        starts = line_starts_code("".join(lines))
        bad_indent = [i+1 for i, ln in enumerate(lines)
                      if starts.get(i+1) and ln.strip() and not ln.lstrip().startswith("#")
                      and " " in ln[:len(ln) - len(ln.lstrip())]]
        if bad_indent:
            print(f"  ✗ {rel}: 第 {bad_indent[:5]} 行用空格缩进（GDScript 需 Tab）")
            problems.append(f"{rel} 空格缩进")
        src = code_only("".join(lines))
        for op, cl, label in [("(", ")", "圆括号"), ("[", "]", "方括号"), ("{", "}", "花括号")]:
            n_op = src.count(op)
            n_cl = src.count(cl)
            if n_op != n_cl:
                print(f"  ✗ {rel}: {label} 数量不等（{n_op} vs {n_cl}）")
                problems.append(f"{rel} {label}不成对")
if not any("空格缩进" in p for p in problems):
    print("  ✓ 所有脚本使用 Tab 缩进")
if not any("不成对" in p for p in problems):
    print("  ✓ 去掉字符串和注释后，括号成对")

print()
print("=" * 68)
print("四、场景文件引用的脚本是否存在")
print("=" * 68)
scenes_dir = os.path.join(ROOT, "scenes")
# 连子目录（scenes/vision/、scenes/chars/ …）一起查
scene_files = sorted(os.path.relpath(os.path.join(d, x), scenes_dir).replace(os.sep, "/")
                     for d, _, xs in os.walk(scenes_dir) for x in xs if x.endswith(".tscn"))
for fn in scene_files:
    with open(os.path.join(scenes_dir, fn), encoding="utf-8") as f:
        content = f.read()
    for m in re.finditer(r'path="(res://[^"]+\.gd)"', content):
        sp = os.path.join(ROOT, m.group(1).replace("res://", ""))
        if not os.path.exists(sp):
            print(f"  ✗ {fn} 引用了不存在的脚本 {m.group(1)}")
            problems.append(f"{fn} -> {m.group(1)} 缺失")

# 代码里切场景的目标是否存在。lane cs3：扩到 change_scene_to_packed，与「已知常量 / 常量拼接」路径：
# 能静态定值的才核——字面量、本文件 const、Autoload / class_name 的 const（Foo.BAR）、以上各项的 + 拼接、
# preload / load(可定值) [as PackedScene]；变量、函数返回值、% 格式化等未知形式一律不报（宁少报），只计数。
def _code_mask(src):
    """与 code_only 同一套切分，逐字符标注：c 代码 / s 字符串 / # 注释（偏移不走样）。"""
    mask, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in ('"', "'"):
            q = c * 3 if src.startswith(c * 3, i) else c
            j = i + len(q)
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src.startswith(q, j):
                    j += len(q)
                    break
                j += 1
            j = min(j, n)
            mask.extend("s" * (j - i))
            i = j
            continue
        if c == "#":
            j = src.find("\n", i)
            j = n if j < 0 else j
            mask.extend("#" * (j - i))
            i = j
            continue
        mask.append("c")
        i += 1
    return "".join(mask)


def _call_arg(src, mask, pos):
    """pos 指向 '(' 之后：取到配对的 ')'，返回实参原文；不配对返回 None。"""
    depth = 1
    for j in range(pos, len(src)):
        if mask[j] != "c":
            continue
        if src[j] in "([{":
            depth += 1
        elif src[j] in ")]}":
            depth -= 1
            if depth == 0:
                return src[pos:j]
    return None


def _split_plus(expr):
    """在顶层（括号 / 字符串外）按 + 切开。"""
    mask, parts, depth, last = _code_mask(expr), [], 0, 0
    for j, ch in enumerate(expr):
        if mask[j] != "c":
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "+" and depth == 0:
            parts.append(expr[last:j])
            last = j + 1
    parts.append(expr[last:])
    return parts


_SC_CONST = re.compile(r'^[ \t]*const\s+([A-Za-z_]\w*)\s*(?::\s*[A-Za-z_][\w.]*(?:\[[^\]\n]*\])?\s*)?:?=\s*(.*)$', re.M)
_sc_consts = {}   # 文件相对路径 -> {常量名: 右值原文 或 None（同名多处定义，不猜）}
_sc_owner = {}    # Autoload 名 / class_name -> 文件相对路径


def _sc_file_consts(rel):
    if rel not in _sc_consts:
        tab = {}
        p = os.path.join(ROOT, rel)
        src = open(p, encoding="utf-8").read() if os.path.exists(p) else ""
        mask = _code_mask(src)
        for m in _SC_CONST.finditer(src):
            if mask[m.start(1)] != "c":
                continue
            rhs = src[m.start(2):m.end(2)]
            cut = mask[m.start(2):m.end(2)].find("#")
            rhs = (rhs if cut < 0 else rhs[:cut]).strip()
            name = m.group(1)
            tab[name] = rhs if name not in tab or tab[name] == rhs else None
        _sc_consts[rel] = tab
    return _sc_consts[rel]


def _sc_eval(expr, rel, seen=()):
    """静态定值：返回 ("str", 路径) / ("packed", 路径) / None（未知形式）。"""
    expr = expr.strip()
    expr = re.sub(r'\s+as\s+PackedScene$', "", expr)
    parts = _split_plus(expr)
    if len(parts) > 1:
        vals = [_sc_eval(x, rel, seen) for x in parts]
        if all(v and v[0] == "str" for v in vals):
            return ("str", "".join(v[1] for v in vals))
        return None
    m = re.fullmatch(r'"([^"\\\n]*)"|\'([^\'\\\n]*)\'', expr)
    if m:
        return ("str", m.group(1) if m.group(1) is not None else m.group(2))
    m = re.fullmatch(r'\((.*)\)', expr, re.S)
    if m and _call_arg(expr, _code_mask(expr), 1) == m.group(1):
        return _sc_eval(m.group(1), rel, seen)
    m = re.fullmatch(r'(?:preload|load|ResourceLoader\.load)\s*\((.*)\)', expr, re.S)
    if m:
        v = _sc_eval(m.group(1), rel, seen)
        return ("packed", v[1]) if v and v[0] == "str" else None
    m = re.fullmatch(r'(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)', expr)
    if m:
        owner = _sc_owner.get(m.group(1)) if m.group(1) else rel
        key = (owner, m.group(2))
        if not owner or key in seen:
            return None
        rhs = _sc_file_consts(owner).get(m.group(2))
        return _sc_eval(rhs, owner, seen + (key,)) if rhs else None
    return None


_sc_files = sorted(os.path.relpath(os.path.join(d, x), ROOT).replace(os.sep, "/")
                   for d, _, xs in os.walk(SCRIPTS) for x in xs if x.endswith(".gd"))
_sc_owner.update({k: v.replace(os.sep, "/") for k, v in AUTOLOADS.items()})
for _rel in _sc_files:
    _cn = re.search(r'^class_name\s+([A-Za-z_]\w*)', code_only(open(os.path.join(ROOT, _rel), encoding="utf-8").read()), re.M)
    if _cn:
        _sc_owner.setdefault(_cn.group(1), _rel)
_sc_stat = collections.Counter()
for rel in _sc_files:
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    mask = _code_mask(src)
    for m in re.finditer(r'\bchange_scene_to_(file|packed)\s*\(', src):
        if mask[m.start()] != "c":
            continue  # 注释 / 字符串里的不算
        kind, line = m.group(1), src.count("\n", 0, m.start()) + 1
        arg = _call_arg(src, mask, m.end())
        val = _sc_eval(arg, rel) if arg is not None else None
        form = ("字面量" if arg is not None and re.fullmatch(r'\s*"[^"]*"\s*', arg) else
                "拼接" if arg is not None and len(_split_plus(arg)) > 1 else "常量")
        if val is None:
            _sc_stat["未知"] += 1
            print(f"  · {rel}:L{line} change_scene_to_{kind}({(arg or '').strip()}) 形式未知，不核")
            continue
        want = "str" if kind == "file" else "packed"
        if val[0] != want:
            _sc_stat["未知"] += 1
            print(f"  · {rel}:L{line} change_scene_to_{kind}({arg.strip()}) 实参类型对不上（{val[0]}），不核")
            continue
        if kind == "packed":
            form = "packed"
        _sc_stat[form] += 1
        note = "" if form == "字面量" else f"（{form}：{arg.strip()}）"
        tp = val[1]
        if not tp.startswith("res://") or not os.path.exists(os.path.join(ROOT, tp[len("res://"):])):
            print(f"  ✗ {rel}:L{line} 切换到不存在的场景 {tp}{note}")
            problems.append(f"{rel} -> {tp} 缺失")
        else:
            print(f"  ✓ {rel} → {tp}{note}")
_sc_done = sum(v for k, v in _sc_stat.items() if k != "未知")
print(f"  场景切换 {_sc_done + _sc_stat['未知']} 处：已核 {_sc_done}（字面量 {_sc_stat['字面量']} / 常量 {_sc_stat['常量']}"
      f" / 拼接 {_sc_stat['拼接']} / packed {_sc_stat['packed']}），形式未知不核 {_sc_stat['未知']}")

print()
print("=" * 68)
print("五、Fleet.cargo 只读（分船装载的聚合 getter 禁止赋值）")
print("=" * 68)
print("  Fleet.cargo 已改为只读聚合 getter，数据源在 ships[i].cargo。")
print("  任何 Fleet.cargo = / Fleet.cargo[...] = / Fleet.cargo.xxx = 都会炸或静默无效。")

fleet_rel = AUTOLOADS["Fleet"].replace(os.sep, "/")
cargo_writes = []
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in sorted(files):
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if rel == fleet_rel:
            continue  # Fleet.gd 内部只走 ships[i]["cargo"]
        with open(path, encoding="utf-8") as f:
            src = f.read()
        src_nc = code_only(src)
        # 跳过链式访问片段（[..] / .ident），再看是否落到赋值符
        for m in re.finditer(r'\bFleet\.cargo', src_nc):
            pos = m.end()
            while True:
                seg = re.match(r'\s*(\[[^\]]*\]|\.[A-Za-z_]\w*)', src_nc[pos:])
                if not seg:
                    break
                pos += seg.end()
            stripped = src_nc[pos:].lstrip()
            if stripped.startswith("=") and not stripped.startswith(("==", "=>")):
                line = src_nc[:m.start()].count("\n") + 1
                cargo_writes.append((rel, line))

if not cargo_writes:
    print("  ✓ 全 scripts 无 Fleet.cargo 写入")
else:
    for rel, line in sorted(set(cargo_writes)):
        print(f"  ✗ {rel}:L{line} 对 Fleet.cargo 赋值——只读 getter，请改用 add_cargo/remove_cargo")
        problems.append(f"{rel}:{line} Fleet.cargo 只读被违例")

# add_ship 必须为每艘新船初始化独立货舱
with open(os.path.join(ROOT, AUTOLOADS["Fleet"]), encoding="utf-8") as f:
    fleet_src = f.read()
add_ship_body = func_bodies(fleet_src).get("add_ship", "")
if '"cargo"' in add_ship_body:
    print("  ✓ Fleet.add_ship 的船 dict 含独立 cargo 货舱")
else:
    print('  ✗ Fleet.add_ship 的船 dict 缺少 "cargo": {} —— 新船没有独立货舱')
    problems.append("Fleet.add_ship 缺少 cargo 字段")

# 分船船员配置：hire_crew 带 ship_index 默认参数 + 单船 crew 接口契约
print()
print("=" * 68)
print("五之二、分船船员配置契约")
print("=" * 68)
hire_sig = re.search(r'func hire_crew\(([^)]*)\)', fleet_src)
if hire_sig and "ship_index" in hire_sig.group(1):
    print("  ✓ Fleet.hire_crew 带 ship_index 默认参数（-1 聚合 / >=0 指定船）")
else:
    print("  ✗ Fleet.hire_crew 缺少 ship_index 参数")
    problems.append("Fleet.hire_crew 缺少 ship_index")
for f in ("ship_crew", "ship_crew_min", "ship_crew_max", "ship_crew_room",
          "crew_shortfall", "crew_to_min_needed", "hire_to_min"):
    if f in defined["Fleet"]:
        print(f"  ✓ Fleet.{f} 已定义")
    else:
        print(f"  ✗ Fleet.{f} 未定义")
        problems.append(f"Fleet.{f} 未定义")

print()
print("=" * 68)
print("五之三、船体改装契约")
print("=" * 68)
print("  改装：sail_level/armor_level 字段已就绪，须有完整的升级 API 与消费方。")

upgrade_funcs = ("upgrade_sail", "upgrade_armor", "sail_level", "armor_level",
                 "upgrade_cost", "is_sail_max", "is_armor_max",
                 "armor_damage_reduction", "fleet_armor_level")
for f in upgrade_funcs:
    if f in defined["Fleet"]:
        print(f"  ✓ Fleet.{f} 已定义")
    else:
        print(f"  ✗ Fleet.{f} 未定义")
        problems.append(f"Fleet.{f} 未定义")

for c in ("SAIL_LEVEL_MAX", "ARMOR_LEVEL_MAX", "UPGRADE_BASE_RATIO"):
    if c in defined["Fleet"]:
        print(f"  ✓ Fleet.{c} 常量已定义")
    else:
        print(f"  ✗ Fleet.{c} 常量未定义")
        problems.append(f"Fleet.{c} 未定义")

main_src = read_main_src()
if re.search(r'^func\s+_on_upgrade\b', main_src, re.M):
    print("  ✓ Main._on_upgrade 已定义（船屋升级按钮 connect 目标）")
else:
    print("  ✗ Main._on_upgrade 未定义")
    problems.append("Main._on_upgrade 未定义")

# armor 消费方：风暴与海盗船体伤都须经 armor_damage_reduction
voyage_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Voyage.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                voyage_src = f.read()
if "armor_damage_reduction" in voyage_src:
    print("  ✓ Voyage 风暴伤害已乘 armor_damage_reduction")
else:
    print("  ✗ Voyage 风暴伤害未乘 armor_damage_reduction——甲等级无消费点")
    problems.append("Voyage 风暴未消费 armor")

seachart_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "SeaChart.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                seachart_src = f.read()
uses_in_power = "fleet_armor_level" in seachart_src
uses_in_dmg = seachart_src.count("armor_damage_reduction") >= 1
if uses_in_power:
    print("  ✓ SeaChart 战力已计入 fleet_armor_level")
else:
    print("  ✗ SeaChart 战力未计入 fleet_armor_level")
    problems.append("SeaChart 战力未计入 armor")
if uses_in_dmg:
    print("  ✓ SeaChart 海盗船体伤已乘 armor_damage_reduction（P4-1 起结算不补扣耐久，保底 flee 仍乘）")
else:
    print(f"  ✗ SeaChart armor_damage_reduction 使用次数不足（期望 ≥1，实际 {seachart_src.count('armor_damage_reduction')}）")
    problems.append("SeaChart 海盗伤害未消费 armor")

# 升级 API 满级防御：upgrade_* 应返回 bool 且只在非满级时改写等级
for f in ("upgrade_sail", "upgrade_armor"):
    body = func_bodies(fleet_src).get(f, "")
    if "return false" in body and "return true" in body:
        print(f"  ✓ Fleet.{f} 有满级返回 false 的守卫")
    else:
        print(f"  ✗ Fleet.{f} 缺少满级守卫（应满级返回 false）")
        problems.append(f"Fleet.{f} 无满级守卫")

print()
print("=" * 68)
print("六、海战契约（P4-1：WorldMap 战斗接入）")
print("=" * 68)
print("  add_child 叠加方案：SeaChart 保留航行状态，WorldMap 战斗专用化。")

# 读取相关脚本源码
wm_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "WorldMap.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                wm_src = f.read()
ship_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Ship.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                ship_src = f.read()
minimap_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Minimap.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                minimap_src = f.read()
pirate_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "PirateShip.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                pirate_src = f.read()
cannonball_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Cannonball.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                cannonball_src = f.read()

# 1. GameManager.pending_battle 上下文
if "pending_battle" in defined["GameManager"]:
    print("  ✓ GameManager.pending_battle 已声明（海战上下文）")
else:
    print("  ✗ GameManager.pending_battle 未声明")
    problems.append("GameManager.pending_battle 未声明")

# 2. SeaChart 接入点 + WorldMap preload
for f in ("_enter_battle", "_on_battle_result"):
    if re.search(rf'^func\s+{f}\b', seachart_src, re.M):
        print(f"  ✓ SeaChart.{f} 已定义")
    else:
        print(f"  ✗ SeaChart.{f} 未定义")
        problems.append(f"SeaChart.{f} 未定义")
if "WorldMap.tscn" in seachart_src:
    print("  ✓ SeaChart preload WorldMap.tscn（叠加进入战斗）")
else:
    print("  ✗ SeaChart 未 preload WorldMap.tscn")
    problems.append("SeaChart 未 preload WorldMap.tscn")

# 3. WorldMap 战斗核心
wm_need = ("combat_mode", "_setup_combat", "_spawn_enemy", "_battle_exit",
           "_battle_player_sunk", "_unhandled_input", "_enemies_alive")
wm_members = set(re.findall(r'^func\s+([A-Za-z_]\w*)', wm_src, re.M))
wm_vars = set(re.findall(r'^\s*var\s+([A-Za-z_]\w*)', wm_src, re.M))
for f in wm_need:
    if f in wm_members or f in wm_vars:
        print(f"  ✓ WorldMap.{f} 已定义")
    else:
        print(f"  ✗ WorldMap.{f} 未定义")
        problems.append(f"WorldMap.{f} 未定义")
if "signal battle_finished" in wm_src:
    print("  ✓ WorldMap.battle_finished 信号已声明")
else:
    print("  ✗ WorldMap.battle_finished 信号未声明")
    problems.append("WorldMap.battle_finished 信号未声明")

# 4. Ship._sink_ship 战斗守卫
if "pending_battle" in ship_src and "_battle_player_sunk" in ship_src:
    print("  ✓ Ship._sink_ship 含战斗守卫（战斗期不切场景）")
else:
    print("  ✗ Ship._sink_ship 缺少战斗守卫")
    problems.append("Ship._sink_ship 缺少战斗守卫")

# 5. Minimap 不再依赖 current_scene（add_child 方案必需）——只查非注释行
minimap_nc = "\n".join(re.sub(r'#.*$', '', ln) for ln in minimap_src.split("\n"))
if "current_scene" in minimap_nc:
    print("  ✗ Minimap 仍用 get_tree().current_scene——add_child 方案下会解析到 SeaChart")
    problems.append("Minimap 仍依赖 current_scene")
else:
    print("  ✓ Minimap 已改用父链查找（add_child 兼容）")

# 6. WorldMap 战斗模式：禁停靠 + 已拆除自由航行刷怪
if "PROCESS_MODE_DISABLED" in wm_src:
    print("  ✓ WorldMap 战斗模式禁用 Ports（停靠出口关闭）")
else:
    print("  ✗ WorldMap 未禁用 Ports（战斗可误停靠）")
    problems.append("WorldMap 未禁用 Ports")
ecology_left = [name for name in ("_process_spawns", "seagull_tex", "whale_tex", "crate_scene")
                if name in wm_src]
if ecology_left:
    print(f"  ✗ WorldMap 仍留自由航行刷怪：{', '.join(ecology_left)}")
    problems.append("WorldMap 仍留自由航行刷怪")
else:
    print("  ✓ WorldMap 已拆除 crate / 海鸟 / 鲸影 / 野海盗刷怪")
if os.path.exists(os.path.join(ROOT, "scripts", "Crate.gd")) or os.path.exists(os.path.join(ROOT, "scenes", "Crate.tscn")):
    print("  ✗ Crate 场景仍在（拾取箱应为死内容，已裁定拆除）")
    problems.append("Crate 场景未拆除")
else:
    print("  ✓ Crate.gd / Crate.tscn 已拆除")
dead_bitmaps = [
    os.path.join(ROOT, "assets", name)
    for name in ("crate_barrel.png", "seagull.png", "whale_shadow.png")
    if os.path.exists(os.path.join(ROOT, "assets", name))
]
if dead_bitmaps:
    print("  ✗ 死生态位图仍在 assets/：%s" % ", ".join(os.path.basename(p) for p in dead_bitmaps))
    problems.append("死生态位图未拆除")
else:
    print("  ✓ crate / 海鸟 / 鲸影位图已从 assets/ 拆除")
wm_tscn = ""
with open(os.path.join(ROOT, "scenes", "WorldMap.tscn"), encoding="utf-8") as f:
    wm_tscn = f.read()
if "ocean_tex_1234" in wm_tscn:
    print("  ✗ WorldMap.tscn 仍用假 UID ocean_tex_1234")
    problems.append("WorldMap.tscn 海洋假 UID")
elif "uid://xnp7vjyfjnp1" in wm_tscn:
    print("  ✓ WorldMap.tscn 海洋贴图用导入 UID")
else:
    print("  ✗ WorldMap.tscn 未引用 ocean_water 导入 UID")
    problems.append("WorldMap.tscn 海洋 UID 未对齐")

def real_uid(res_path):
    """res:// 资源的真 uid：场景 / 资源读头部，脚本 / 着色器读 .uid 侧车，导入资源读 .import。无则 None。"""
    p = os.path.join(ROOT, res_path[len("res://"):])
    for side, pat in ((p + ".uid", r'^(uid://\S+)'), (p + ".import", r'^uid="(uid://[^"]+)"')):
        if os.path.exists(side):
            with open(side, encoding="utf-8") as f:
                m = re.search(pat, f.read(), re.M)
            return m.group(1) if m else None
    if p.endswith((".tscn", ".tres")) and os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            m = re.match(r'\[gd_(?:scene|resource)\b[^\]]*\buid="(uid://[^"]+)"', f.readline())
        return m.group(1) if m else None
    return None

# 手编假 uid（lane ag3 删掉的 ship_node_1234 同类）：每个 ext_resource 的 uid 须是目标资源自己的 uid
if "ship_node_1234" in wm_tscn:
    print("  ✗ WorldMap.tscn 仍用假 UID ship_node_1234")
    problems.append("WorldMap.tscn Ship 假 UID")
_wm_fake = []
for _m in re.finditer(r'^\[ext_resource\b[^\n]*?\buid="([^"]*)"[^\n]*?\bpath="(res://[^"]+)"', wm_tscn, re.M):
    _uid, _path = _m.groups()
    _want = real_uid(_path)
    if not re.fullmatch(r'uid://[a-y0-9]+', _uid) or _uid != _want:
        _wm_fake.append(f"{_path} 写 {_uid}，目标实为 {_want or '无 uid'}")
if _wm_fake:
    for _x in _wm_fake:
        print(f"  ✗ WorldMap.tscn 手编假 uid：{_x}")
    problems.append("WorldMap.tscn 手编假 uid")
else:
    print("  ✓ WorldMap.tscn 的 ext_resource uid 都与目标资源一致（无手编假 uid）")

# 7. PirateShip 不再掉拾取箱（赏金只走 SeaChart 结算）
if "drops_loot" in pirate_src or "Crate.tscn" in pirate_src:
    print("  ✗ PirateShip 仍引用拾取箱 / drops_loot")
    problems.append("PirateShip 仍掉拾取箱")
else:
    print("  ✓ PirateShip 击沉不再掉拾取箱")

print()
print("=" * 68)
print("七、海战契约（P4-2：接舷/白刃/夺船并入舰队）")
print("=" * 68)
print("  白刃按 水手数 × 士气 × 将领武力 判定；胜方夺船并入舰队。")

# 1. GameState.martial 主角武力（白刃将领武力数据源）
if "martial" in defined.get("GameState", set()):
    print("  ✓ GameState.martial 已声明（主角武力，白刃输入）")
else:
    print("  ✗ GameState.martial 未声明")
    problems.append("GameState.martial 未声明")

# 2. Fleet.captain_power / lose_crew_random
for f in ("captain_power", "lose_crew_random"):
    if f in defined.get("Fleet", set()):
        print(f"  ✓ Fleet.{f} 已定义")
    else:
        print(f"  ✗ Fleet.{f} 未定义")
        problems.append(f"Fleet.{f} 未定义")

# 3. PirateShip 接舷/白刃状态与战力
for f in ("grappled", "ship_type", "ship_name", "crew", "enemy_morale", "captain_force", "combat_strength"):
    if f in set(re.findall(r'^\s*(?:var|func)\s+([A-Za-z_]\w*)', pirate_src, re.M)):
        print(f"  ✓ PirateShip.{f} 已定义")
    else:
        print(f"  ✗ PirateShip.{f} 未定义")
        problems.append(f"PirateShip.{f} 未定义")

# 4. WorldMap 接舷/白刃
wm_need4 = ("BOARD_DISTANCE", "boarding", "boarding_target", "_board_enemy",
            "_nearest_enemy", "_boarding_target_valid", "_show_combat_notice")
wm_all = wm_vars | wm_members | set(re.findall(r'^const\s+([A-Za-z_]\w*)', wm_src, re.M))
for f in wm_need4:
    if f in wm_all:
        print(f"  ✓ WorldMap.{f} 已定义")
    else:
        print(f"  ✗ WorldMap.{f} 未定义")
        problems.append(f"WorldMap.{f} 未定义")

# 5. Ship 白刃禁炮击
if _has_func(ship_src, "_can_fire") and "boarding" in ship_src:
    print("  ✓ Ship._can_fire 已定义（白刃阶段禁炮击）")
else:
    print("  ✗ Ship._can_fire 缺失（白刃禁炮击）")
    problems.append("Ship._can_fire 缺失")

# 6. 主角武力数据源
with open(os.path.join(ROOT, "data", "npcs.json"), encoding="utf-8") as f:
    npc_src = f.read()
if '"force"' in npc_src and '"chen_wenlong"' in npc_src:
    print("  ✓ npcs.json 主角陈子龙含 force 字段（武力数据源）")
else:
    print("  ✗ npcs.json 主角缺 force 字段")
    problems.append("npcs.json 主角缺 force")

# 7. GameState 存档序列化含 martial
gs_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "GameState.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                gs_src = f.read()
if '"martial"' in gs_src:
    print("  ✓ GameState.to_dict/from_dict 含 martial 存档字段")
else:
    print("  ✗ GameState 存档缺 martial")
    problems.append("GameState 存档缺 martial")

print()
print("=" * 68)
print("八、海战契约（P4-3：Cannonball 弹数挂炮位 + 伤害乘甲）")
print("=" * 68)
print("  玩家齐射弹数挂钩旗舰 cannon_slots；敌船弹数按 scale 缩放；玩家船受击乘甲。")

# 1. Ship：不再写死 range(3) 齐射，且引用 cannon_slots
if "cannon_slots" in ship_src and "range(3)" not in ship_src:
    print("  ✓ Ship 齐射弹数已挂钩 cannon_slots（无 range(3) 写死）")
else:
    print("  ✗ Ship 齐射弹数未挂钩 cannon_slots 或仍写死 range(3)")
    problems.append("Ship 齐射未挂 cannon_slots")

# 2. PirateShip：声明 cannon_count 字段（行首 var），且 _process_firing 函数体里用 range(cannon_count)（lane cs11：原先两条都是全文件口径）
if re.search(r'^var\s+cannon_count\b', pirate_src, re.M) and "range(cannon_count)" in _locate_func(pirate_src, "_process_firing"):
    print("  ✓ PirateShip 声明 cannon_count 且 _process_firing 用 range(cannon_count)")
else:
    print("  ✗ PirateShip 缺 cannon_count 字段或 _process_firing 未用 range(cannon_count)")
    problems.append("PirateShip 弹数未挂 cannon_count")

# 3. WorldMap：_spawn_enemy 写入 cannon_count
if "cannon_count" in wm_src:
    print("  ✓ WorldMap._spawn_enemy 写入 cannon_count")
else:
    print("  ✗ WorldMap 未写入 cannon_count")
    problems.append("WorldMap 未写 cannon_count")

# 4. Cannonball：引用 armor_damage_reduction（玩家船受击乘甲）
if "armor_damage_reduction" in cannonball_src:
    print("  ✓ Cannonball 伤害已乘 armor_damage_reduction")
else:
    print("  ✗ Cannonball 未引用 armor_damage_reduction——甲等级无实时消费点")
    problems.append("Cannonball 未乘 armor")

print()
print("=" * 68)
print("九、P6 剧情旗标与结局契约")
print("=" * 68)
print("  旗标门槛、酒馆旧事、结局了结、剧情效果字段须有消费方。")

gs_need = (
    "flag_requirement_met", "choice_visible", "scene_unlocked",
    "try_resolve_ending", "has_ended", "pick_ending", "story_hooks_at",
    "ending_id", "network", "merchant_credit", "add_ledger_note",
)
for f in gs_need:
    if f in defined.get("GameState", set()):
        print(f"  ✓ GameState.{f} 已定义")
    else:
        print(f"  ✗ GameState.{f} 未定义")
        problems.append(f"GameState.{f} 未定义")

main_src = read_main_src()
for ok, label in (
    (_calls(main_src, "GameState.choice_visible"), "Main.show_choices 过滤不可见选项"),
    (_calls(main_src, "GameState.scene_unlocked"), "Main.load_scene 守剧情门槛"),
    (_calls(main_src, "GameState.story_hooks_at"), "Main 酒馆接旧事钩子"),
    ('"network"' in main_src, "Main.apply_effects 写入人脉"),
    ('"merchant_credit"' in main_src, "Main.apply_effects 写入海商信用"),
    ('"ledger_note"' in main_src, "Main.apply_effects 写入边记"),
    (_calls(main_src, "GameState.try_advance_chapter"), "Main 入港结算晋升/了结"),
):
    if ok:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}")
        problems.append(label)

crew_src = ""
with open(os.path.join(SCRIPTS, "core", "Crew.gd"), encoding="utf-8") as f:
    crew_src = f.read()
if "flag_requirement_met" in crew_src and _has_func(crew_src, "candidates_at"):
    print("  ✓ Crew.candidates_at 守旗标门槛")
else:
    print("  ✗ Crew.candidates_at 未守旗标门槛")
    problems.append("Crew.candidates_at 未守旗标")

if '"ending_id"' in gs_src and '"network"' in gs_src and '"merchant_credit"' in gs_src:
    print("  ✓ GameState 存档含 ending_id / network / merchant_credit")
else:
    print("  ✗ GameState 存档缺结局或账本字段")
    problems.append("GameState 存档缺 P6 字段")

print()
print("=" * 68)
print("十、海图 / 海战点验入口")
print("=" * 68)
print("  HUD 写 WASD，工程默认 input map 只有方向键，操船必须另认字母键。")
ship_src = open(os.path.join(SCRIPTS, "Ship.gd"), encoding="utf-8").read()
chart_src = open(os.path.join(SCRIPTS, "SeaChart.gd"), encoding="utf-8").read()
if "KEY_W" in ship_src and "KEY_A" in ship_src and "KEY_D" in ship_src:
    print("  ✓ Ship 认 WASD 升降帆 / 操舵")
else:
    print("  ✗ Ship 未认 WASD——HUD 与手感对不上")
    problems.append("Ship 未认 WASD")
if "pirate_sighting" in defined.get("Voyage", set()):
    print("  ✓ Voyage.pirate_sighting 已定义")
else:
    print("  ✗ Voyage.pirate_sighting 未定义")
    problems.append("Voyage.pirate_sighting 未定义")
if _has_func(chart_src, "_debug_force_pirate") and "KEY_F10" in chart_src:
    print("  ✓ SeaChart F10 可强行遭遇海盗")
else:
    print("  ✗ SeaChart 无 F10 海盗点验入口")
    problems.append("SeaChart 无 F10")
if "_debug_jump_port" in main_src and "KEY_F11" in main_src:
    print("  ✓ Main F11 可跳到泉州港")
    dbg = _locate_func(main_src, "_debug_jump_port")
    if "fuzhou" in dbg and "xinghua" in dbg:
        print("  ✓ F11 点验链含福州通用港与兴化回访")
    else:
        print("  ✗ F11 不能跳到福州/兴化")
        problems.append("F11 点验链缺福州/兴化")
else:
    print("  ✗ Main 无 F11 进港点验入口")
    problems.append("Main 无 F11")
wm_src = open(os.path.join(SCRIPTS, "WorldMap.gd"), encoding="utf-8").read()
if 'child.get("hull_hp"' in wm_src or 'boarding_target.get("hull_hp"' in wm_src:
    print("  ✗ WorldMap 对 Node 用了两参数 get()——Godot 4.6 编不过")
    problems.append("WorldMap Node.get 两参数")
else:
    print("  ✓ WorldMap 不再对 Node 调用两参数 get()")
if "class_name PirateShip" in open(os.path.join(SCRIPTS, "PirateShip.gd"), encoding="utf-8").read():
    print("  ✓ PirateShip 有 class_name，is PirateShip 可解析")
else:
    print("  ✗ PirateShip 无 class_name")
    problems.append("PirateShip 无 class_name")
if _has_func(wm_src, "_format_left_hud"):
    print("  ✓ WorldMap._format_left_hud 已定义（顶匾文案单独拼）")
else:
    print("  ✗ WorldMap 无 _format_left_hud")
    problems.append("WorldMap 无 _format_left_hud")
spawn_max = re.search(r"COMBAT_SPAWN_DIST_MAX\s*:=\s*([0-9.]+)", wm_src)
if spawn_max and float(spawn_max.group(1)) <= 500.0:
    print("  ✓ 开战刷船距离在镜头内（≤500）")
else:
    print("  ✗ 开战刷船距离过远或未定义")
    problems.append("开战刷船距离过远")
if "COMBAT_FIRE_DELAY" in wm_src and "fire_timer" in wm_src:
    print("  ✓ 开战给敌船接敌延迟，避免首帧齐射秒杀")
else:
    print("  ✗ 开战未给敌船接敌延迟")
    problems.append("开战未给敌船接敌延迟")
if "c is CanvasItem" in chart_src and "_enter_battle" in chart_src:
    print("  ✓ SeaChart 开战收起全屏栏")
else:
    print("  ✗ SeaChart 开战未收起全屏栏")
    problems.append("SeaChart 开战未收起全屏栏")
if "TideBar/Margin/Row/VBox/FleetStatus" in wm_src and "RightPanel/Margin/VBox/FleetStatus" not in wm_src:
    print("  ✓ 舰队和天气写在顶匾右侧，仍走 VBox")
else:
    print("  ✗ 海战舰队天气未收进顶匾")
    problems.append("海战舰队天气未收进顶匾")
wm_tscn_hud = open(os.path.join(ROOT, "scenes", "WorldMap.tscn"), encoding="utf-8").read()
if (
    '[node name="TideBar"' in wm_tscn_hud
    and '[node name="LeftPanel"' not in wm_tscn_hud
    and "Vector2(320, 0)" not in wm_tscn_hud
):
    print("  ✓ 海战左右栏收成顶匾")
else:
    print("  ✗ 海战仍铺左右栏")
    problems.append("海战仍铺左右栏")
cap = re.search(r"COMBAT_CANNON_CAP\s*:=\s*(\d+)", wm_src)
if cap and int(cap.group(1)) <= 2:
    print("  ✓ 开战敌船齐射封顶（≤2），开局小艍扛得住第一轮")
else:
    print("  ✗ 开战齐射未封顶，开局仍会被一波秒沉")
    problems.append("开战齐射未封顶")
ship_tscn = open(os.path.join(ROOT, "scenes", "Ship.tscn"), encoding="utf-8").read()
pirate_tscn = open(os.path.join(ROOT, "scenes", "PirateShip.tscn"), encoding="utf-8").read()
if "ship_fu.png" in ship_tscn and "ship_falcon.png" in pirate_tscn and "ship_topdown.png" not in ship_tscn:
    print("  ✓ 玩家福船 / 敌船海鹘用精绘精灵，不再用照片底板")
else:
    print("  ✗ 船精灵仍是照片底板或未换新图")
    problems.append("船精灵未换成福船/海鹘")
if "Color(1, 0.5, 0.5)" in pirate_src:
    print("  ✗ 海盗还在用红色 modulate 盖船图")
    problems.append("海盗红色 modulate 会脏掉海鹘精灵")
else:
    print("  ✓ 海盗不再用红色 modulate 盖船图")
cb_tscn = open(os.path.join(ROOT, "scenes", "Cannonball.tscn"), encoding="utf-8").read()
if "shot_iron.png" in cb_tscn and "cannonball.png" not in cb_tscn:
    print("  ✓ 炮弹用铁子精灵")
else:
    print("  ✗ 炮弹仍是大号 RGB 底板")
    problems.append("炮弹未换成铁子")


def png_probe(path):
    """stdlib 解码 PNG（含 Paeth/Up/Sub/Average 反过滤）。
    返回 (宽, 高, 是否 RGBA8, 四角 alpha 是否全 0)；无法解析返回 None。"""
    import struct as _st, zlib as _zl
    try:
        data = open(path, "rb").read()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        pos, idat, w, h, depth, ctype = 8, b"", 0, 0, 0, 0
        while pos < len(data):
            ln = _st.unpack(">I", data[pos:pos + 4])[0]
            typ, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + ln]
            if typ == b"IHDR":
                w, h, depth, ctype = _st.unpack(">IIBB", body[:10])
            elif typ == b"IDAT":
                idat += body
            pos += 12 + ln
        if ctype != 6 or depth != 8:
            return (w, h, False, False)
        raw = _zl.decompress(idat)
        stride = w * 4
        prev = bytearray(stride)
        corners = []
        p = 0
        for y in range(h):
            filt = raw[p]; p += 1
            cur = bytearray(raw[p:p + stride]); p += stride
            if filt == 1:
                for i in range(4, stride):
                    cur[i] = (cur[i] + cur[i - 4]) & 255
            elif filt == 2:
                for i in range(stride):
                    cur[i] = (cur[i] + prev[i]) & 255
            elif filt == 3:
                for i in range(stride):
                    cur[i] = (cur[i] + ((cur[i - 4] if i >= 4 else 0) + prev[i]) // 2) & 255
            elif filt == 4:
                for i in range(stride):
                    a = cur[i - 4] if i >= 4 else 0
                    b, c = prev[i], prev[i - 4] if i >= 4 else 0
                    pp = a + b - c
                    pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                    cur[i] = (cur[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
            if y == 0 or y == h - 1:
                corners += [cur[3], cur[stride - 1]]
            prev = cur
        return (w, h, True, all(a == 0 for a in corners))
    except Exception:
        return None


for rel in ("assets/ship_fu.png", "assets/ship_falcon.png", "assets/shot_iron.png"):
    full = os.path.join(ROOT, rel)
    if not os.path.exists(full):
        print(f"  ✗ 缺 {rel}")
        problems.append(f"缺 {rel}")
        continue
    probe = png_probe(full)
    if probe is None:
        print(f"  ✗ {rel} 不是可解析的 PNG")
        problems.append(f"{rel} 无法解析")
        continue
    w, h, is_rgba, clear_corners = probe
    if not is_rgba:
        print(f"  ✗ {rel} 不是 RGBA8（底板又会烤进图里）")
        problems.append(f"{rel} 非 RGBA")
    elif not clear_corners:
        print(f"  ✗ {rel} 四角不透明（疑似带底板）")
        problems.append(f"{rel} 带底板")
    else:
        print(f"  ✓ {rel} 真 RGBA 且四角透明（{w}x{h}）")
for rel, min_kb in (("assets/ship_fu.png", 60), ("assets/ship_falcon.png", 60)):
    full = os.path.join(ROOT, rel)
    if os.path.exists(full):
        kb = os.path.getsize(full) // 1024
        # 精绘 512² 船图约 110~150KB；扫线平涂占位只有 5KB 量级。
        if kb >= min_kb:
            print(f"  ✓ {rel} {kb}KB，是精绘位图不是平涂占位")
        else:
            print(f"  ✗ {rel} 仅 {kb}KB（<{min_kb}KB），疑似平涂占位图")
            problems.append(f"{rel} 疑似占位图")
_bg_map = os.path.join(ROOT, "assets", "bg_world_map.jpg")
if os.path.exists(_bg_map) and open(_bg_map, "rb").read(2) == b"\xff\xd8":
    print("  ✓ bg_world_map.jpg 在仓库里且是真 JPEG（海图/标题底图）")
else:
    print("  ✗ 缺 bg_world_map.jpg 或不是真 JPEG（海图背景留黑）")
    problems.append("缺 bg_world_map.jpg")

print()
print("=" * 68)
print("十一、绢本弹窗与字阶 / 挑签")
print("=" * 68)
theme_src = ""
with open(os.path.join(ROOT, "scripts", "core", "UiTheme.gd"), encoding="utf-8") as f:
    theme_src = f.read()
if re.search(r"^static func style_dialog\b", theme_src, re.M):
    print("  ✓ UiTheme.style_dialog 已定义")
else:
    print("  ✗ UiTheme.style_dialog 未定义")
    problems.append("UiTheme.style_dialog 未定义")
def _func_body(src: str, name: str) -> str:
    """取 src 里 `func name` 连签名的函数体；取不到给 "" 并记账判红（见 _body_asks）。"""
    m = re.search(rf"^func {name}\b.*?(?=^func |\Z)", src, re.M | re.S)
    _body_ask(name, m is not None)
    return m.group(0) if m else ""


save_body = _func_body(main_src, "_show_save_dialog")
if "SaveSheet" in save_body and "UiTheme.panel()" in save_body and "AcceptDialog" not in save_body:
    print("  ✓ 航海日志是居中绢本册页")
else:
    print("  ✗ 存档弹窗未套绢本主题")
    problems.append("存档弹窗未套绢本主题")
if (
    "_begin_benches(col)" in save_body
    and "SIZE_SHRINK_CENTER" in save_body
    and "Vector2(520, 0)" not in save_body
    and "style_choice_button(close)" not in save_body
):
    print("  ✓ 航海日志三卷走工席，合上不再拉满宽")
else:
    print("  ✗ 航海日志仍是竖排细条")
    problems.append("航海日志仍是竖排细条")
saveload_src = ""
with open(os.path.join(SCRIPTS, "core", "SaveLoad.gd"), encoding="utf-8") as f:
    saveload_src = f.read()
if (
    "未记" in saveload_src
    and "卷页损了" in saveload_src
    and "未题" in saveload_src
    and "（空）" not in saveload_src
    and "（损坏）" not in saveload_src
    and "（无标签）" not in saveload_src
    and "存档 / 读档" not in main_src
    and "%d 钱" in saveload_src
):
    print("  ✓ 航海日志空卷写成未记")
else:
    print("  ✗ 航海日志仍写空卷括号")
    problems.append("航海日志仍写空卷括号")
chapter_body = _func_body(main_src, "_show_chapter_dialog")
if "ChapterSheet" in chapter_body and "UiTheme.panel()" in chapter_body and "AcceptDialog" not in chapter_body:
    print("  ✓ 升章/了结是居中绢本册页")
else:
    print("  ✗ 升章/了结弹窗未套绢本主题")
    problems.append("升章/了结弹窗未套绢本主题")
market_body = _func_body(main_src, "_setup_market")
if "OptionButton" not in market_body and _calls(market_body, "_select_market_ship"):
    print("  ✓ 牙行选船走账条小钮")
else:
    print("  ✗ 牙行仍用系统下拉选船")
    problems.append("牙行仍用系统下拉选船")
hanjiang_body = _func_body(main_src, "_on_hanjiang_escape")
if "旧避风澳・景炎二年三月" in hanjiang_body and "景炎三年" not in hanjiang_body:
    print("  ✓ 岸上的根结算写景炎二年（1277 卡、ending_root 过场同年）")
else:
    print("  ✗ 岸上的根结算年号不是景炎二年")
    problems.append("岸上的根结算年号错")
if '买%d' not in main_src and '卖%d' not in main_src and "只购得 %d。" in main_src and "钱（" not in main_src:
    print("  ✓ 牙行小钮与买卖日志留出字距")
else:
    print("  ✗ 牙行小钮或买卖日志仍挤在一起")
    problems.append("牙行小钮或买卖日志仍挤在一起")
if "塞　50" in main_src and "关注　减 15" in main_src and "塞 50" not in main_src and "关注减 15" not in main_src and re.search(r"(?<![\w.])UiTheme\.plain_log\(_gather_price_intel\s*\(", main_src):
    print("  ✓ 见面册疏通留出字距，行情去掉方括号")
else:
    print("  ✗ 见面册疏通或行情仍是挤字")
    problems.append("见面册疏通或行情仍是挤字")
if (
    "尚无人留意" in main_src
    and "偶有闲话传出" in main_src
    and "起了疑心" in main_src
    and "暗桩已盯死，出港必查" in main_src
    and "（尚无人留意）" not in main_src
    and "（偶有闲话传出）" not in main_src
    and "（蒲氏起了疑心）" not in main_src
    and "（暗桩已盯死，出港必查）" not in main_src
):
    print("  ✓ 市舶司关注四档去掉括号")
else:
    print("  ✗ 市舶司关注仍套括号")
    problems.append("市舶司关注仍套括号")
if (
    "（缺 %d 人）" not in main_src
    and "缺 %d 人" in main_src
    and "（%d/%d）" not in main_src
    and "水手 %d / %d" in main_src
    and "水手 %d/%d" not in main_src
    and "%d / %d 料" in main_src
    and "%d/%d 料" not in main_src
    and "水手不足　%s" in main_src
    and "水手不足：" not in main_src
):
    print("  ✓ 缺员与分船账条写成已有 / 所需，出海拦阻去掉冒号")
else:
    print("  ✗ 缺员或分船账条仍是紧挨斜杠或冒号")
    problems.append("缺员或分船账条仍是紧挨斜杠或冒号")
cal_src = ""
with open(os.path.join(SCRIPTS, "core", "Calendar.gd"), encoding="utf-8") as f:
    cal_src = f.read()
if (
    "东北季风　利南下" in cal_src
    and "西南季风　利北上" in cal_src
    and "季风转换期・风微而多变" in cal_src
    and "（利南下）" not in cal_src
    and "（利北上）" not in cal_src
    and "（风微而多变）" not in cal_src
    and "（五至八月）" not in main_src
    and "（十月至次年二月）" not in main_src
):
    print("  ✓ 风信写成短句")
else:
    print("  ✗ 风信仍套括号")
    problems.append("风信仍套括号")
theme_src_tide = open(os.path.join(SCRIPTS, "core", "UiTheme.gd"), encoding="utf-8").read()
# 皮肤断言按当前皮肤判（第 2 轮工程 m1：绢本下原句只因注释里还有「夜潮」二字才过，是假 ✓）
_skin_m = re.search(r'const SKIN := "(\w+)"', theme_src_tide)
_skin = _skin_m.group(1) if _skin_m else ""
if _skin == "yechao":
    if "夜潮" in theme_src_tide and "const TIDE" in theme_src_tide and "熟漆面板" not in theme_src_tide:
        print("  ✓ 面板改成夜潮")
    else:
        print("  ✗ 面板仍是熟漆描金")
        problems.append("面板仍是熟漆描金")
else:
    _panel_body = _locate_func(theme_src_tide, "panel")
    if (
        _skin == "juanben"
        and "const JUANBEN := {" in theme_src_tide
        and "const YECHAO := {" in theme_src_tide
        and "if IS_JUANBEN" in _panel_body
        and "_ink_panel(" in _panel_body
        and "熟漆面板" not in theme_src_tide
    ):
        print("  ✓ 面板是绢本暖墨（夜潮原值留在 YECHAO 表里可一键切回）")
    else:
        print("  ✗ 绢本面板没接上，或夜潮原值表丢了")
        problems.append("绢本面板没接上，或夜潮原值表丢了")
draft_src = open(os.path.join(SCRIPTS, "core", "HeadingDraft.gd"), encoding="utf-8").read()
chart_src_draft = open(os.path.join(SCRIPTS, "SeaChart.gd"), encoding="utf-8").read()
gs_src_draft = open(os.path.join(SCRIPTS, "GameState.gd"), encoding="utf-8").read()
if (
    "class_name HeadingDraft" in draft_src
    and "今日风不放这一向。" in chart_src_draft
    and "在船上候了三日，风又换了一手。" in chart_src_draft
    and "就这一向" in chart_src_draft
    and "候风再发" in chart_src_draft
    and "看风" in main_src
    and "升帆出海" not in main_src
    and '"draft_salt"' in gs_src_draft
    and _has_func(theme_src_tide, "heading_card")
    and "port_list" not in chart_src_draft
):
    print("  ✓ 出海改成晨潮三向")
else:
    print("  ✗ 晨潮三向未接上")
    problems.append("晨潮三向未接上")
shore_src = open(os.path.join(SCRIPTS, "core", "ShoreDraft.gd"), encoding="utf-8").read()
if (
    "class_name ShoreDraft" in shore_src
    and "今日此门未开。" in main_src
    and "在岸上又候了一日，门又换了几处。" in main_src
    and "再候一日" in main_src
    and "今日只开三处。" in main_src
    and _calls(main_src, "ShoreDraft.deal")
    and '"shore_salt"' in gs_src_draft
    and "func shore_door" in theme_src_tide
    and "func _add_sail_button" not in main_src
):
    print("  ✓ 进港改成今日只开三处")
else:
    print("  ✗ 岸上三处未接上")
    problems.append("岸上三处未接上")

# Lane Z2：岸门副题与悬停纪实提示（泉州/福州/兴化共用 GENERIC 与剧情港卡）
if (
    "const DOOR_TIP" in main_src
    and "过秤・买卖" in main_src
    and "闻讯・募人" in main_src
    and "修舱・上水・雇手" in main_src
    and "议价・立籍" in main_src
    and "btn.tooltip_text = tip" in main_src
    and "今日未开。再候一日，门或另换。" in main_src
    and os.path.exists(os.path.join(ROOT, "tools", "qa_port_doors_probe.gd"))
):
    print("  ✓ 岸门副题/tooltip 论文纪实（Lane Z2）")
else:
    print("  ✗ 岸门副题/tooltip 未接上（Lane Z2）")
    problems.append("岸门 DOOR_TIP/副题未接")

broker_src = open(os.path.join(SCRIPTS, "core", "BrokerSlip.gd"), encoding="utf-8").read()
market_fn = _func_body(main_src, "_setup_market")
if (
    "class_name BrokerSlip" in broker_src
    and _calls(market_fn, "BrokerSlip.deal")
    and "明日再看" in market_fn
    and (
        "柜上只摆三样。要看别的，明日再来。" in main_src
        or "柜上只摆三样。牙人过秤开票；要看别的，明日再来。" in main_src
    )
    and "这件今日不在柜上。" in main_src
    and "柜上换了一手，日子过了一天。" in main_src
    and '"broker_salt"' in gs_src_draft
    and "OptionButton" not in market_fn
    and _calls(market_fn, "_select_market_ship")
):
    print("  ✓ 牙行改成柜上三样")
else:
    print("  ✗ 柜上三样未接上")
    problems.append("柜上三样未接上")

# Lane AA：牙行/市舶过秤面板——价格行手续脚注、过秤短注、委办细则与修埠短句纪实；数值公式不动
_aa_econ = open(os.path.join(SCRIPTS, "core", "Economy.gd"), encoding="utf-8").read()
_aa_row = _func_body(main_src, "_make_market_row")
_aa_inv = _func_body(main_src, "_setup_title_and_invest")
_aa_contract = _func_body(main_src, "_add_contract_panel")
if (
    '"买 %d　卖 %d" % [buy_p, sell_p]' in _aa_row
    and 'fee_lbl.text = "含抽解・扣佣"' in _aa_row
    and "tariff" not in _aa_row and "broker" not in _aa_row
    and "牙人过秤开票" in market_fn
    and "过秤・买卖" in main_src
    and "牙人过秤开票。买价含抽解，出港验引另纳。" in main_src
    and "市舶抽解另计" not in main_src  # lane ea5：旧句与脚注「含抽解・扣佣」互斥
    and "遇事约赶得上，八成日数逾限，未稳。" in _aa_contract
    and "保货不到八成。不含买路。" in _aa_contract
    and "可接；交不齐则拿不满酬，不加声名。" in _aa_contract
    and "启航后风向或变，日数按逐日累加。" in _aa_contract
    and "埠头加深" in _aa_inv and "市面更宽" in _aa_inv
    and 'rate_hint = "价略平"' in _aa_econ
    and all(bad not in main_src + _aa_econ for bad in ("平均数赶得上", "加深市场", "价平偏低", "小船打不赢", "市场更深", "不够也能接"))
    and "var tariff_rate: float = 0.10" in _aa_econ
    and "var broker_fee: float = 0.05" in _aa_econ
    and os.path.exists(os.path.join(ROOT, "tools", "qa_market_panel_probe.gd"))
):
    print("  ✓ 牙行市舶过秤面板价格行与手续短句纪实（Lane AA）")
else:
    print("  ✗ 牙行市舶过秤面板纪实未接上（Lane AA）")
    problems.append("牙行过秤面板 Lane AA 契约未接")



dry_src = open(os.path.join(SCRIPTS, "core", "DrydockBerth.gd"), encoding="utf-8").read()
yard_fn = _func_body(main_src, "_setup_shipyard")
switch_fn = _func_body(main_src, "_on_berth_switch")
if (
    "class_name DrydockBerth" in dry_src
    and "DrydockBerth.berth_index" in yard_fn
    and _calls(yard_fn, "DrydockBerth.sale_ids")
    and "坞上只搁一艘。帆和甲对着这一艘。水粮与赊贷仍在码头。" in yard_fn
    and "换上　" in yard_fn
    and "把「%s」拖上坞位。帆和甲对着这一艘。" in switch_fn
    and "_begin_slip_scroll" not in yard_fn
    and "advance_days" not in yard_fn
    and "advance_days" not in switch_fn
    and '"berth_index"' in gs_src_draft
    and "func _on_upgrade" in main_src
):
    print("  ✓ 船屋改成坞位一艘")
else:
    print("  ✗ 坞位一艘未接上")
    problems.append("坞位一艘未接上")

# Lane V：船屋成功题签（修船／购入／升帆／升甲／换坞）走 UiTransition.drydock_*；失败不演
ut_src_yard = open(os.path.join(SCRIPTS, "ui", "UiTransition.gd"), encoding="utf-8").read()
repair_fn = _func_body(main_src, "_on_repair_hull")
buy_fn = _func_body(main_src, "_on_buy_ship")
upgrade_fn = _func_body(main_src, "_on_upgrade")
yard_ok_fn = _func_body(main_src, "_yard_success_transition")
if (
    "func drydock_title" in ut_src_yard
    and "func drydock_seal" in ut_src_yard
    and "func drydock_open" in ut_src_yard
    and '"修"' in ut_src_yard and '"购"' in ut_src_yard and '"坞"' in ut_src_yard
    and "drydock_title(" in yard_ok_fn and "drydock_seal(" in yard_ok_fn
    and "_yard_success_transition" in repair_fn and "船匠敲了一日" in repair_fn
    and "_yard_success_transition" in buy_fn and "泊在坞外。水手未齐。" in buy_fn
    and "_yard_success_transition" in switch_fn
    and 'act = "升帆"' in upgrade_fn and 'act = "升甲"' in upgrade_fn
    and os.path.exists(os.path.join(ROOT, "tools", "qa_drydock_probe.gd"))
):
    print("  ✓ 船屋成功题签走 UiTransition.drydock_*（修/购/帆/甲/坞；失败不演）")
else:
    print("  ✗ 船屋成功题签未接上")
    problems.append("船屋成功题签未接上")


_ink_line = 'var ink := INK_SOLID if accent else TEXT'
_focus_ok = True
for _fn in ("style_button", "style_chip"):
    _body = _locate_func(theme_src_tide, _fn)
    if (
        _ink_line not in _body
        or 'font_focus_color", ink)' not in _body
        or 'font_pressed_color", ink)' not in _body
        or 'font_focus_color", TEXT)' in _body
    ):
        _focus_ok = False
        print(f"  ✗ {_fn} 聚焦或按下仍可能是壳白字")
        problems.append(f"{_fn} 珊瑚聚焦字色")
if _focus_ok:
    print("  ✓ 珊瑚主钮和小钮聚焦、按下都用深字")
# 绢本分支另查（第 2 轮工程 m1）：朱砂印钮 / 朱砂小钮聚焦、按下都是印面浅字 SEAL_TEXT
if _skin == "juanben":
    _bj = _locate_func(theme_src_tide, "_style_button_juanben")
    _cj = _locate_func(theme_src_tide, "_style_chip_juanben")
    if (
        'font_focus_color", SEAL_TEXT)' in _bj
        and 'font_pressed_color", SEAL_TEXT)' in _bj
        and "var ink := SEAL_TEXT if accent else TEXT" in _cj
        and 'font_focus_color", ink)' in _cj
        and 'font_pressed_color", ink)' in _cj
    ):
        print("  ✓ 绢本朱砂印钮和小钮聚焦、按下都用印面浅字")
    else:
        print("  ✗ 绢本朱砂钮聚焦或按下字色没锁成 SEAL_TEXT")
        problems.append("绢本朱砂钮聚焦字色")
if (
    "%s　%s%s" in cal_src
    and "%s %s%s" not in cal_src
    and "费一日" in main_src
    and "费 1 日" not in main_src
):
    print("  ✓ 日期留出字距，酒馆行情写成费一日")
else:
    print("  ✗ 日期仍是半角空格，或酒馆行情仍写费 1 日")
    problems.append("日期或酒馆行情仍是半角记法")
tavern_body = _locate_func(main_src, "_setup_tavern")
if "_begin_benches" in tavern_body and tavern_body.find("_add_leave_button") > tavern_body.find("_end_benches"):
    print("  ✓ 酒馆募人排成工席，离开留在下面")
else:
    print("  ✗ 酒馆离开未留在工席下面")
    problems.append("酒馆离开未留在工席下面")

# Lane AB：酒馆募人 / 水手雇请工席纪实文案；费用数值不改
_ab_hire = _func_body(main_src, "_setup_hiring")
_ab_tavern = _func_body(main_src, "_setup_tavern")
_ab_hire_crew = _func_body(main_src, "_on_hire_crew")
_ab_hire_min = _func_body(main_src, "_on_hire_to_min")
_ab_preview = open(os.path.join(SCRIPTS, "ui", "TavernFacilityPreview.gd"), encoding="utf-8").read()
_ab_slip = open(os.path.join(SCRIPTS, "ui", "TavernFacilitySlip.gd"), encoding="utf-8").read()
if (
    "劣酒与潮气同在" in _ab_tavern
    and "本港眼下无人可雇" in _ab_hire
    and "本港可雇" in _ab_hire
    and "一职一人" in _ab_hire
    and "入伙钱当场付清" in _ab_hire
    and 'tooltip_text = "辞退即上岸。入伙钱不退。"' in _ab_hire
    and '"雇入"' in _ab_hire and '"辞退"' in _ab_hire
    and "入伙 %d　月俸 %d" in _ab_hire
    and "添 %d 人" in yard_fn
    and "码头短雇的水手" in yard_fn
    and "码头上雇了" in _ab_hire_crew
    and "码头上雇齐" in _ab_hire_min
    and "名册上查无此人" in crew_src
    and "囊中不足" in crew_src
    and "辞退，背铺盖上岸" in crew_src
    and "闻讯・募人" in _ab_preview
    and "闻讯・募人" in _ab_slip
    and "打听消息・募人" not in _ab_preview
    and "打听消息・募人" not in _ab_slip
    and "+%d" not in main_src
    and os.path.exists(os.path.join(ROOT, "tools", "qa_crew_hire_probe.gd"))
):
    print("  ✓ 酒馆募人/水手雇请工席纪实（Lane AB；费用公式未改）")
else:
    print("  ✗ 酒馆募人/水手雇请纪实未接上（Lane AB）")
    problems.append("酒馆募人 Lane AB 契约未接")
port_body = _locate_func(main_src, "_setup_port_mode")
if (
    "func _mount_status_strip" in main_src
    and "func _lift_ledger" in main_src
    and "func _begin_benches" in main_src
    and "left_panel.visible = true" not in port_body
    and "_show_strip(true)" in port_body
):
    print("  ✓ 船籍簿收成顶栏，进港不再铺回左栏")
else:
    print("  ✗ 船籍簿仍占左栏，或内页没有工席")
    problems.append("船籍簿仍占左栏，或内页没有工席")
if "★" not in main_src and "func _skill_rank" in main_src and "Crew.rank_word" in main_src and "func rank_word" in crew_src:
    print("  ✓ 职事品级写成初习/谙熟/老练")
else:
    print("  ✗ 职事仍用星号")
    problems.append("职事仍用星号")
if "func _fit_rank" in main_src and "帆Lv" not in main_src and "Lv%d" not in main_src:
    print("  ✓ 船壳改装写成一等/二等/三等")
else:
    print("  ✗ 船壳改装仍写 Lv")
    problems.append("船壳改装仍写 Lv")
if "func _interior_title" in main_src and "未命名设施" not in main_src:
    print("  ✓ 序章内页改写成港名去处")
else:
    print("  ✗ 序章内页或港卡仍是占位名")
    problems.append("序章内页或港卡仍是占位名")
if "func _interior_lead" in main_src and "static func plain_log" in theme_src and "UiTheme.plain_log" in main_src:
    print("  ✓ 序章内页进门有一句，日志去掉方括号标签")
else:
    print("  ✗ 内页正文或日志标签未收")
    problems.append("内页正文或日志标签未收")
if "【发舶】" not in seachart_src and "UiTheme.plain_log" in seachart_src:
    print("  ✓ 海图日志不再写发舶标签")
else:
    print("  ✗ 海图日志仍写发舶标签")
    problems.append("海图日志仍写发舶标签")
if (
    "func _bearing_phrase" in seachart_src
    and _calls(seachart_src, "UiTheme.heading_card")
    and "回港（不出海）" not in seachart_src
    and "目的：" not in seachart_src
    and "绕过去看看（费 1 日）" not in seachart_src
    and "%d%%" not in seachart_src
    and "°" not in seachart_src
):
    print("  ✓ 海图旁注收成账条，去掉冒号、度数符号和括号教程")
else:
    print("  ✗ 海图旁注仍是冒号或括号教程")
    problems.append("海图旁注仍是冒号或括号教程")
_fx_src_k = open(os.path.join(SCRIPTS, "combat", "CombatFx.gd"), encoding="utf-8").read() if os.path.isfile(os.path.join(SCRIPTS, "combat", "CombatFx.gd")) else ""
_flee_ok_literal = (
    seachart_src.count("绕了些路。") == 1
    or (("绕了些路。" in _fx_src_k or "绕路若干" in _fx_src_k)
        and "sea_flee_ok_note" in seachart_src)
)
if (
    _flee_ok_literal
    and seachart_src.count("_log_shook_pursuers()") == 3
    and "（绕了些路）" not in seachart_src
    and "（调试）" not in seachart_src
    and "点验　中途遭遇。" in seachart_src
    and "损折：" not in voyage_src
    and "损折　" in voyage_src
):
    print("  ✓ 海图遭遇日志去掉括号，风涛货损去掉冒号")
else:
    print("  ✗ 海图遭遇日志仍有括号或风涛货损仍有冒号")
    problems.append("海图遭遇日志仍有括号")
if (
    "收帆" in wm_src and "半帆" in wm_src and "满帆" in wm_src
    and "操舵　A　D" in wm_src and "齐射　J　K" in wm_src
    and "弃战　B" in wm_src and "接舷　G　弃战　B" in wm_src
    and "A/D" not in wm_src and "J/K" not in wm_src and "B/Esc" not in wm_src
    and "档" not in wm_src
    and "月息每百 %d" in main_src and "月息 %d%%" not in main_src
    and "添 %d 人" in main_src and "+%d" not in main_src
    and "运往 %s　多 %d" in main_src and "→ %s" not in main_src
    and "此帆比光船快" in main_src and "船体伤剩" in main_src
    and "航速 ×" not in main_src and "违禁：" not in main_src
    and "抽解每百 %d" in main_src and "%d%%" not in main_src
    and "水手 %d 至 %d" in main_src and "水粮各 %d　付 %d" in main_src
    and "水手 %d–%d" not in main_src and "各 %d　%d" not in main_src
):
    print("  ✓ 海战栏与船屋账条去掉斜杠、百分号和小数倍率")
else:
    print("  ✗ 海战栏或船屋账条仍有斜杠、百分号或小数倍率")
    problems.append("海战栏或船屋仍是原型记法")
gs_chapter_src = open(os.path.join(SCRIPTS, "GameState.gd"), encoding="utf-8").read()
if (
    "%s　%s　%d / %d" in main_src
    and "%s %s %d/%d" not in main_src
    and ("再升一等。" in main_src or "再修一等" in main_src)
    and "再升一等：" not in main_src
    and "拓「%s」　%s" in main_src
    and "拓「%s」：" not in main_src
    and "亲至　" in gs_chapter_src
    and "亲至 " not in gs_chapter_src
    and "水手 %d / %d" in main_src
):
    print("  ✓ 章目写成已行多少，修埠与拓碑去掉冒号")
else:
    print("  ✗ 章目、修埠或拓碑仍是半角或冒号")
    problems.append("章目、修埠或拓碑仍是半角或冒号")
enter_body = _locate_func(main_src, "_on_enter_port")
if "visit_port" in enter_body and enter_body.find("update_status_panel") > enter_body.find("visit_port"):
    print("  ✓ 进港后船籍簿按已走通的港重写")
else:
    print("  ✗ 进港后船籍簿未按已走通的港重写")
    problems.append("进港后船籍簿未重写")
if (
    "掐指算了算。" in main_src
    and "掐指算了算：" not in main_src
    and "压低声音说。" in main_src
    and "压低声音说：" not in main_src
    and "五至八月" in main_src
    and "十月至次年二月" in main_src
    and "%s　眼下缺%s" in main_src
    and "%s 眼下缺" not in main_src
    and "多得　%d" in main_src
):
    print("  ✓ 候风与打听去掉冒号")
else:
    print("  ✗ 候风或打听仍用冒号领起")
    problems.append("候风或打听仍用冒号领起")
if '" x"' not in wm_src:
    print("  ✓ 海战货舱用乘号")
else:
    print("  ✗ 海战货舱仍用拉丁字母 x")
    problems.append("海战货舱仍用拉丁字母 x")
if 'text = "请选择"' not in main_src and "区域施工中" not in main_src:
    print("  ✓ 调查页用决断，缺页不再写施工中")
else:
    print("  ✗ 调查页仍写请选择或施工中")
    problems.append("调查页仍写请选择或施工中")
main_tscn = ""
with open(os.path.join(ROOT, "scenes", "Main.tscn"), encoding="utf-8") as f:
    main_tscn = f.read()
_placeholder_left = [
    needle for needle in (
        "副标题", "地点标题", "环境描述文本", "NPC Dialog", "NPC Name",
        "情报与状态", "港口名称",
    ) if needle in main_tscn
]
if _placeholder_left:
    print("  ✗ 开场场景仍有原型占位：%s" % "、".join(_placeholder_left))
    problems.append("开场场景仍有原型占位")
else:
    print("  ✓ 开场场景不再写原型占位")


# 按节点名取场景节点块（lane cs12）：与按名取函数体同一本账——节点改名 / 删了 / 挪进子场景时原先静默给 ""，
# 正向断言（"visible = false" in 块）跟着红，红因却写成「仍展开」；反向断言就照样绿。取不到记账，十三节判红。
def _node_block(src: str, node_name: str) -> str:
    token = '[node name="%s"' % node_name
    at = src.find(token)
    _body_ask(token + "]", at >= 0)
    if at < 0:
        return ""
    nxt = src.find("\n[node ", at + len(token))
    return src[at:] if nxt < 0 else src[at:nxt]


if "visible = false" in _node_block(main_tscn, "InvestigationMode") and "visible = false" in _node_block(main_tscn, "LeftPanel"):
    print("  ✓ 调查页和船籍簿默认收起")
else:
    print("  ✗ 调查页或船籍簿开场仍展开")
    problems.append("开场占位层未收起")
if "按 Enter 停靠" in wm_tscn:
    print("  ✗ 海战港名仍写停靠教程")
    problems.append("海战港名仍写停靠教程")
else:
    print("  ✓ 海战港名不再写停靠教程")
portzone_src = ""
with open(os.path.join(ROOT, "scripts", "PortZone.gd"), encoding="utf-8") as f:
    portzone_src = f.read()
if "name_lbl.text = port_name" in portzone_src:
    print("  ✓ 港区名牌写港口名")
else:
    print("  ✗ 港区名牌未写港口名")
    problems.append("港区名牌未写港口名")
if "Color(0.2, 0.4, 0.6" in main_src:
    print("  ✗ NPC 按钮仍用蓝底硬编码")
    problems.append("NPC 按钮蓝底硬编码")
else:
    print("  ✓ NPC 按钮不再用蓝底硬编码")
if "hook_buttons(npc_actions)" in main_src:
    print("  ✓ 人物对话按钮挂钩 UiTheme")
else:
    print("  ✗ npc_actions 未挂钩 UiTheme")
    problems.append("npc_actions 未挂钩")
for name in ("SIZE_HEAD", "SIZE_BODY", "SIZE_FOOT", "LINE_BODY"):
    if "const %s" % name in theme_src:
        print(f"  ✓ UiTheme.{name} 已锁定")
    else:
        print(f"  ✗ UiTheme.{name} 未定义")
        problems.append(f"UiTheme.{name} 未定义")
if re.search(r"^static func style_choice_button\b", theme_src, re.M):
    print("  ✓ UiTheme.style_choice_button 已定义（挑签）")
else:
    print("  ✗ UiTheme.style_choice_button 未定义")
    problems.append("UiTheme.style_choice_button 未定义")
if "style_choice_button" in main_src and "func show_choices" in main_src:
    print("  ✓ 剧情选项走挑签样式")
else:
    print("  ✗ 剧情选项未走挑签样式")
    problems.append("剧情选项未走挑签")
if "style_heading(scene_title)" in main_src and "style_body(body_text)" in main_src:
    print("  ✓ 调查页标题/正文走字阶")
else:
    print("  ✗ 调查页未接线字阶")
    problems.append("调查页未接线字阶")
if "style_heading(head)" in seachart_src and "style_body(status_label)" in seachart_src:
    print("  ✓ 海图标题/状态栏走字阶")
else:
    print("  ✗ 海图未接线字阶")
    problems.append("海图未接线字阶")
if (
    "船况" in seachart_src
    and "func _mount_condition" in seachart_src
    and "Vector2(260, 0)" not in seachart_src
    and "Vector2(300, 0)" not in seachart_src
):
    print("  ✓ 海图左右栏收成顶匾，船况点开才占画面")
else:
    print("  ✗ 海图仍铺左右栏")
    problems.append("海图仍铺左右栏")
meet_body = _func_body(main_src, "_show_npc_mode")
if "_begin_benches(npc_actions)" in meet_body and "SIZE_SHRINK_CENTER" in meet_body:
    print("  ✓ 见面行情走工席，离开不再拉满宽")
else:
    print("  ✗ 见面仍是满宽细条")
    problems.append("见面仍是满宽细条")
if "event_panel.add_theme_stylebox_override(\"panel\", UiTheme.panel())" in seachart_src:
    print("  ✓ 海图遭遇弹层走绢本面板")
else:
    print("  ✗ 海图遭遇弹层仍用硬编码 StyleBox")
    problems.append("海图遭遇弹层未套绢本")
if "event_actions = VBoxContainer" in seachart_src and "event_actions = HBoxContainer" not in seachart_src:
    print("  ✓ 海图遭遇选项竖排挑签")
else:
    print("  ✗ 海图遭遇选项仍横排挤在一行")
    problems.append("海图遭遇选项未竖排")
if "CenterContainer" in seachart_src and "Vector2(360, 200)" not in seachart_src:
    print("  ✓ 海图遭遇弹层居中，不再钉右下")
else:
    print("  ✗ 海图遭遇弹层仍用 360,200 硬坐标")
    problems.append("海图遭遇弹层未居中")
mapview_src_cs = open(os.path.join(ROOT, "scripts", "chart", "MapView.gd"), encoding="utf-8").read() if os.path.exists(os.path.join(ROOT, "scripts", "chart", "MapView.gd")) else ""
# 2026-09-25 海图重制：港名与底图都移到 scripts/chart/MapView.gd——港名走《地理图》式朱砂方框加蛤粉内填，底图是舆图纹理经绢本着色器
if "COL_SHELL" in mapview_src_cs and "draw_rect(box" in mapview_src_cs and "draw_string(font, v + Vector2(8, 5)" not in seachart_src:
    print("  ✓ 海图港名走方框蛤粉签（MapView._draw_ports）")
else:
    print("  ✗ 海图港名仍是裸字")
    problems.append("海图港名未垫墨底")
if "ChartTerrain.gdshader" in mapview_src_cs and "terrain_4096.png" in mapview_src_cs and "Color(0.11, 0.08, 0.05, 0.55)" not in seachart_src:
    print("  ✓ 海图底图是绢本着色的舆图纹理（MapView）")
else:
    print("  ✗ 海图中栏仍铺熟漆")
    problems.append("海图中栏未改绢纸")
if "event_actions = VBoxContainer" in seachart_src and "style_choice_button(b)" in seachart_src:
    print("  ✓ 海图遭遇选项走竖排挑签")
else:
    print("  ✗ 海图遭遇选项未走挑签")
    problems.append("海图遭遇未走挑签")
if "StyleBoxFlat.new()" in seachart_src:
    print("  ✗ SeaChart 仍手写 StyleBoxFlat")
    problems.append("SeaChart 手写 StyleBoxFlat")
else:
    print("  ✓ SeaChart 不再手写 StyleBoxFlat")

print()
print("=" * 68)
print("十二、名声换爵与港口投资")
print("=" * 68)
print("  职衔派生自名声；修埠落 Economy；市舶司是唯一入口。")

titles_path = os.path.join(ROOT, "data", "titles.json")
if os.path.isfile(titles_path):
    print("  ✓ data/titles.json 存在")
else:
    print("  ✗ data/titles.json 不存在")
    problems.append("缺 titles.json")

gm_src = open(os.path.join(SCRIPTS, "GameManager.gd"), encoding="utf-8").read()
eco_src = open(os.path.join(SCRIPTS, "core", "Economy.gd"), encoding="utf-8").read()
gs_src = open(os.path.join(SCRIPTS, "GameState.gd"), encoding="utf-8").read()
if "titles_data" in defined.get("GameManager", set()) and "titles.json" in gm_src:
    print("  ✓ GameManager 加载 titles.json")
else:
    print("  ✗ GameManager 未加载 titles.json")
    problems.append("GameManager 未加载 titles")

for f in ("add_fame", "title_rank", "next_title", "title_duty_factor",
          "title_loan_bonus", "title_name", "title_ranks"):
    if f in defined.get("GameState", set()):
        print(f"  ✓ GameState.{f} 已定义")
    else:
        print(f"  ✗ GameState.{f} 未定义")
        problems.append(f"GameState.{f} 未定义")

for f in ("invest", "invest_cost", "investment_level", "invest_edge",
          "investments", "invest_fame_gain"):
    if f in defined.get("Economy", set()):
        print(f"  ✓ Economy.{f} 已定义")
    else:
        print(f"  ✗ Economy.{f} 未定义")
        problems.append(f"Economy.{f} 未定义")

if "title_duty_factor" in eco_src:
    print("  ✓ Economy 定价乘职衔抽解")
else:
    print("  ✗ Economy 定价未乘职衔")
    problems.append("Economy 未乘职衔")
if 'role == "origin"' in eco_src and 'role == "consumer"' in eco_src and "invest_edge" in eco_src:
    print("  ✓ Economy 修埠按产地/消费地同向调单位价")
else:
    print("  ✗ Economy 修埠未按角色同向调价")
    problems.append("Economy 修埠调价未接线")
if '"investments"' in eco_src:
    print("  ✓ Economy 存档含 investments")
else:
    print("  ✗ Economy 存档缺 investments")
    problems.append("Economy 存档缺 investments")
if "title_loan_bonus" in gs_src and _has_func(gs_src, "borrow_limit"):
    print("  ✓ 赊贷上限吃职衔加成")
else:
    print("  ✗ 赊贷上限未吃职衔加成")
    problems.append("borrow_limit 未接职衔")
if "title_duty_factor" in gs_src and _has_func(gs_src, "customs_duty"):
    print("  ✓ 货引抽解吃职衔折让")
else:
    print("  ✗ 货引抽解未吃职衔")
    problems.append("customs_duty 未接职衔")
if "add_fame(" in main_src and "fame +=" not in main_src.replace("add_fame", ""):
    print("  ✓ Main 名声走 add_fame")
else:
    if "add_fame(" in main_src:
        print("  ✓ Main 名声走 add_fame")
    else:
        print("  ✗ Main 未走 add_fame")
        problems.append("Main 未走 add_fame")
if "_setup_title_and_invest" in main_src and "向本港投钱修埠" in main_src:
    print("  ✓ 市舶司有职衔说明与修埠钮")
else:
    print("  ✗ 市舶司未接职衔/修埠")
    problems.append("市舶司未接职衔修埠")
dyn = _locate_func(main_src, "_setup_dynamic_scene")
if "update_status_panel()" in dyn:
    print("  ✓ 设施页重载刷新状态栏（修埠/买卖后金钱可见）")
else:
    print("  ✗ _setup_dynamic_scene 未刷新状态栏")
    problems.append("_setup_dynamic_scene 未刷新状态栏")
if "title_name()" in seachart_src:
    print("  ✓ 海图状态栏显示职衔")
else:
    print("  ✗ 海图状态栏无职衔")
    problems.append("海图无职衔")
if "add_fame(3)" in seachart_src:
    print("  ✓ 海战胜仗名声走 add_fame")
else:
    print("  ✗ 海战胜仗仍直接改 fame")
    problems.append("海战名声未走 add_fame")

pressed_body = _locate_func(main_src, "_on_facility_pressed")
if "REMAPPED_FACILITIES" in pressed_body and "city_inn" in main_src:
    print("  ✓ 旅店按港改写成 {港}_inn（不再 _setup_inn(\"city\")）")
else:
    print("  ✗ 旅店未列入港卡改写")
    problems.append("city_inn 未改写")
if "PROLOGUE_ONLY_FACILITIES" in main_src and 'current_scene_id == "xinghua"' in main_src:
    if "visited_ports" in pressed_body and "quanzhou" in pressed_body:
        print("  ✓ 兴化序章调查页仅在未到泉州前；回访走动态页")
    else:
        print("  ✗ 兴化回访仍一律进序章调查页")
        problems.append("兴化回访未切开")
else:
    print("  ✗ 序章设施未与游戏港切开")
    problems.append("序章设施未切开")
gen = re.search(r"const GENERIC_FACILITIES\s*:=\s*\[(.*?)\]", main_src, re.S)
if gen:
    gbody = gen.group(1)
    missing = [fid for fid in (
        "city_guild", "city_exam", "city_residence", "city_temple", "city_yamen",
    ) if fid not in gbody]
    if missing:
        print("  ✗ 通用港缺卡：%s" % ", ".join(missing))
        problems.append("GENERIC_FACILITIES 缺 %s" % ",".join(missing))
    elif gbody.find("city_temple") > gbody.find("city_yamen"):
        print("  ✗ 通用港寺观须排在市舶司之前（右列原市舶司位）")
        problems.append("GENERIC 寺观卡序")
    elif "勘见・拓碑" not in gbody:
        print("  ✗ 通用港寺观副题不是勘见・拓碑")
        problems.append("GENERIC 寺观副题")
    else:
        print("  ✓ 通用港 GENERIC_FACILITIES 含行会/贡院/住宅/寺观")
else:
    print("  ✗ 未找到 GENERIC_FACILITIES")
    problems.append("缺 GENERIC_FACILITIES")
if "begins_with(\"city_\")" in main_src:
    print("  ✓ load_scene 跳过 city_ 前缀，避免盖掉序章 id")
else:
    print("  ✗ load_scene 仍会把 city_guild 收成动态页")
    problems.append("load_scene 未跳过 city_ 前缀")
for fn in (
    "_setup_guild", "_setup_exam", "_setup_residence", "_collect_spreads",
    "_on_exam_copy", "_setup_temple", "_on_temple_look",
    "_on_temple_rub", "_temple_rub_note",
):
    if re.search(r"func %s\b" % fn, main_src):
        print("  ✓ Main.%s 已定义" % fn)
    else:
        print("  ✗ 缺 Main.%s" % fn)
        problems.append("缺 %s" % fn)
if "HOME_RATE" in main_src and "INN_RATE" in main_src:
    home = re.search(r"const HOME_RATE\s*:=\s*(\d+)", main_src)
    inn = re.search(r"const INN_RATE\s*:=\s*(\d+)", main_src)
    if home and inn and int(home.group(1)) < int(inn.group(1)):
        print("  ✓ 住处歇息 %s 钱/日 < 旅店 %s" % (home.group(1), inn.group(1)))
    else:
        print("  ✗ 住处房价未低于旅店")
        problems.append("HOME_RATE 未低于 INN_RATE")
else:
    print("  ✗ 缺 HOME_RATE / INN_RATE")
    problems.append("缺房价常量")
exam_fn = _locate_func(main_src, "_on_exam_copy")
if "add_fame" in exam_fn:
    print("  ✗ 贡院誊录给了名声（会绕过修埠/呈报）")
    problems.append("贡院不得给名声")
elif "scholar_tendency" in exam_fn:
    print("  ✓ 贡院誊录只加学者倾向，不给名声")
else:
    print("  ✗ 贡院誊录未接线")
    problems.append("贡院誊录未接线")
# P7 留档：行会入行（泉州 / 博多 / 广州）与贡院赴试（每章一次）
def _p7_code(src):
    return "\n".join(re.sub(r'#.*$', '', ln) for ln in src.split("\n"))
def _const_int(name):
    m = re.search(r"const %s\s*:=\s*(\d+)" % name, main_src)
    return int(m.group(1)) if m else None
join_ports = re.search(r"const GUILD_JOIN_PORTS\s*:=\s*\[(.*?)\]", main_src, re.S)
if join_ports and set(re.findall(r'"(\w+)"', join_ports.group(1))) == {"quanzhou", "hakata", "guangzhou"}:
    print("  ✓ 入行只在泉州 / 博多 / 广州")
else:
    print("  ✗ GUILD_JOIN_PORTS 不是泉州 / 博多 / 广州三港")
    problems.append("入行港口漂移")
if (_const_int("GUILD_JOIN_FEE"), _const_int("GUILD_JOIN_CREDIT"),
        _const_int("GUILD_JOIN_CREDIT_GAIN"), _const_int("GUILD_JOIN_NETWORK_GAIN")) == (2000, 8, 4, 2):
    print("  ✓ 入行会费 2000、商誉门槛 8、商誉 +4、人脉 +2")
else:
    print("  ✗ 入行数值漂移（须 2000 / 8 / +4 / +2）")
    problems.append("入行数值漂移")
p7_bodies = func_bodies(main_src)
join_body = _p7_code(p7_bodies.get("_on_guild_join", ""))
block_body = _p7_code(p7_bodies.get("_guild_join_block", ""))
if not join_body or not block_body or "_add_guild_join_slip" not in p7_bodies.get("_setup_guild", ""):
    print("  ✗ 行会入行未接线（_setup_guild → _add_guild_join_slip / _on_guild_join / _guild_join_block）")
    problems.append("行会入行未接线")
elif any(tok in join_body + block_body for tok in ("Economy", "price_at_rate", "tariff", "commission")):
    print("  ✗ 入行动了行情 / 抽解 / 佣金")
    problems.append("入行不得改行情抽解佣金")
elif not all(tok in block_body for tok in ("GUILD_JOIN_PORTS", "has_flag", "merchant_credit < GUILD_JOIN_CREDIT", "money < GUILD_JOIN_FEE")):
    print("  ✗ 入行缘由未查齐（港口 / 已入行 / 商誉 / 现钱）")
    problems.append("入行门槛不全")
elif not (0 <= join_body.find("_guild_join_block") < join_body.find("spend_money(GUILD_JOIN_FEE)")
          < join_body.find('set_flag("guild_%s" % port_id)')):
    print("  ✗ 入行须先查门槛、再扣会费、后记 guild_<港> 旗标")
    problems.append("入行顺序不对")
elif not ("merchant_credit += GUILD_JOIN_CREDIT_GAIN" in join_body and "network += GUILD_JOIN_NETWORK_GAIN" in join_body):
    print("  ✗ 入行未加商誉 / 人脉")
    problems.append("入行未加商誉人脉")
else:
    print("  ✓ 入行先查门槛再扣 2000，记 guild_<港>，不碰行情抽解佣金")
slip_body = _p7_code(p7_bodies.get("_add_guild_join_slip", ""))
if "has_flag" in slip_body and "本港已入行" in slip_body and slip_body.find("本港已入行") < slip_body.find("_on_guild_join"):
    print("  ✓ 已入行只看账，不再出交费钮")
else:
    print("  ✗ 已入行仍出交费钮")
    problems.append("已入行未改只读")
# 行会入行港 id remap 契约：港卡 city_guild 改写成 current_scene_id + "_guild"，入行判定与 guild_<港> 旗标须落在基港 id。
# 按实际页 id（港页 id 取自 scenes.json port 场景或 ports.json 通用港）推一遍路由，泉州 / 博多 / 广州三港都要认得出、只扣一次；
# 再拿几份变异源码喂同一契约，须个个报错，免得契约本身写成空转。
with open(os.path.join(ROOT, "data", "scenes.json"), encoding="utf-8") as f:
    _gr_scenes = {s.get("id"): s for s in json.load(f).get("scenes", [])}
with open(os.path.join(ROOT, "data", "ports.json"), encoding="utf-8") as f:
    _gr_ports = {p.get("id") for p in json.load(f).get("ports", [])}
GUILD_DESIGN_PORTS = ("quanzhou", "hakata", "guangzhou")
def _gr_strip(helper_body, page_id):
    """按 _guild_port_id 的写法模拟剥后缀：while 剥尽、if/裸 trim_suffix 只剥一次、都没有就原样。"""
    code = _p7_code(helper_body)
    if re.search(r'while\s+\w+\.ends_with\("_guild"\)', code) and 'trim_suffix("_guild")' in code:
        while page_id.endswith("_guild"):
            page_id = page_id[:-len("_guild")]
    elif 'trim_suffix("_guild")' in code and page_id.endswith("_guild"):
        page_id = page_id[:-len("_guild")]
    return page_id
def _gr_first_stmt(body):
    for ln in _p7_code(body).split("\n"):
        if ln.strip():
            return ln.strip()
    return ""
def _guild_remap_contract(src):
    # 本契约也跑在下面的变异源码上：取体一律 `in` 探、缺了记成契约错误，不走 .get 记账——
    # 否则「删掉某函数」的变异会被十三节当成本脚本取不到函数体判红（lane cs12；真源码缺函数照样经「缺 X」判红）
    errs = []
    bodies = func_bodies(src)
    def body(name):
        if name in bodies:
            return bodies[name]
        if "缺 %s" % name not in errs:
            errs.append("缺 %s" % name)
        return ""
    jp = re.search(r"const GUILD_JOIN_PORTS\s*:=\s*\[(.*?)\]", src, re.S)
    join_ports = set(re.findall(r'"(\w+)"', jp.group(1))) if jp else set()
    remapped = re.search(r"const REMAPPED_FACILITIES\s*:=\s*\[(.*?)\]", src, re.S)
    suffixes = re.search(r"const FACILITY_SUFFIXES\s*:=\s*\[(.*?)\]", src, re.S)
    generic = re.search(r"const GENERIC_FACILITIES\s*:=\s*\[(.*?)\]", src, re.S)
    if not remapped or '"city_guild"' not in remapped.group(1):
        errs.append("city_guild 不在 REMAPPED_FACILITIES")
    if 'target_scene = current_scene_id + "_" + target_scene.trim_prefix("city_")' not in src:
        errs.append("港卡改写不再是 current_scene_id + _ + 后缀")
    if not suffixes or '"_guild"' not in suffixes.group(1):
        errs.append("FACILITY_SUFFIXES 缺 _guild")
    dyn = _p7_code(body("_setup_dynamic_scene"))
    if "scene_id.trim_suffix(suffix)" not in dyn or "_setup_guild(base_loc)" not in dyn:
        errs.append("_guild 页未剥后缀进 _setup_guild")
    helper = body("_guild_port_id")
    # 四个入口第一句就归一，port_id 在此之前不许被用
    for fn in ("_setup_guild", "_add_guild_join_slip", "_guild_join_block", "_on_guild_join"):
        if _gr_first_stmt(body(fn)) != "port_id = _guild_port_id(port_id)":
            errs.append("%s 未先按 _guild_port_id 归一" % fn)
    join = _p7_code(body("_on_guild_join"))
    block = _p7_code(body("_guild_join_block"))
    slip = _p7_code(body("_add_guild_join_slip"))
    if join.count("spend_money(") != 1 or "add_money(" in join or "money -=" in join:
        errs.append("_on_guild_join 扣费不止一处")
    flag_set = join.find('set_flag("guild_%s" % port_id)')
    first_await = join.find("await ")
    if flag_set < 0 or (first_await >= 0 and first_await < flag_set):
        errs.append("guild_<港> 旗标须在 await 过渡前写上（过渡中再按会二次扣费）")
    if 'has_flag("guild_%s" % port_id)' not in block:
        errs.append("_guild_join_block 已入行判定与 set_flag 键不同")
    if "_on_guild_join.bind(port_id)" not in slip:
        errs.append("入行钮未绑归一后的 port_id")
    for port in GUILD_DESIGN_PORTS:
        # 港页实际 id：剧情港取 scenes.json 的 port 场景，其余港走 ports.json + GENERIC_FACILITIES
        sc = _gr_scenes.get(port)
        if sc is not None and sc.get("type") == "port":
            has_card = any(f.get("id") == "city_guild" for f in sc.get("facilities", []))
        elif sc is None and port in _gr_ports:
            has_card = bool(generic) and '"city_guild"' in generic.group(1)
        else:
            errs.append("%s 港页 id 不是基港 id（scenes.json 同 id 非 port 场景或 ports.json 缺港）" % port)
            continue
        if not has_card:
            errs.append("%s 港页没有 city_guild 卡" % port)
        page = port + "_guild"
        routed = page[:-len("_guild")]  # _setup_dynamic_scene 的 trim_suffix(suffix)
        keys = set()
        for pid in (routed, page, page + "_guild"):
            base = _gr_strip(helper, pid)
            if base not in join_ports:
                errs.append("%s 行会页经 %s 认不出入行港（得 %s）" % (port, pid, base))
            keys.add("guild_%s" % base)
        if len(keys) != 1:
            errs.append("%s 同港旗标分成 %s，会重复扣会费" % (port, sorted(keys)))
    return errs
_gr_errs = _guild_remap_contract(main_src)
if _gr_errs:
    for e in _gr_errs:
        print("  ✗ 行会 remap：%s" % e)
    problems.append("行会入行港 id remap 契约")
else:
    print("  ✓ 泉州 / 博多 / 广州在实际页 id {港}_guild（含多重 _guild）下归一认港，旗标同键、会费只扣一次")
_gr_helper = func_bodies(main_src).get("_guild_port_id", "")
_gr_mutants = {
    "剥后缀只剥一次": main_src.replace('while base.ends_with("_guild"):', 'if base.ends_with("_guild"):', 1),
    "helper 不剥": main_src.replace(_gr_helper, "\n\treturn page_id\n", 1) if _gr_helper else "",
    "入行处理不归一": main_src.replace("func _on_guild_join(port_id: String) -> void:\n\tport_id = _guild_port_id(port_id)\n",
                                   "func _on_guild_join(port_id: String) -> void:\n", 1),
    "门槛不归一": main_src.replace("func _guild_join_block(port_id: String) -> String:\n\tport_id = _guild_port_id(port_id)\n",
                              "func _guild_join_block(port_id: String) -> String:\n", 1),
    "二次扣费": main_src.replace("\tif not GameState.spend_money(GUILD_JOIN_FEE):\n\t\treturn\n",
                             "\tif not GameState.spend_money(GUILD_JOIN_FEE):\n\t\treturn\n\tGameState.spend_money(GUILD_JOIN_FEE)\n", 1),
    "港卡改写漂移": main_src.replace('target_scene = current_scene_id + "_" + target_scene.trim_prefix("city_")',
                                 'target_scene = target_scene.trim_prefix("city_")', 1),
    # 删函数：契约须以「缺 X」拦下，且不进十三节的账（lane cs12）
    "删入行门槛函数": main_src.replace(_locate_func(main_src, "_guild_join_block"), "", 1),
}
_gr_dead = [name for name, m in _gr_mutants.items() if m == main_src or not m or not _guild_remap_contract(m)]
if _gr_dead:
    print("  ✗ 行会 remap 契约变异自检失灵（变异未被抓）：%s" % "、".join(_gr_dead))
    problems.append("行会 remap 变异自检")
else:
    print("  ✓ 行会 remap 变异自检：%d 份变异源码均被契约拦下" % len(_gr_mutants))
if _const_int("EXAM_SIT_DAYS") == 15:
    print("  ✓ 赴试费 15 日")
else:
    print("  ✗ EXAM_SIT_DAYS 不是 15")
    problems.append("赴试天数漂移")
sit_body = _p7_code(p7_bodies.get("_on_exam_sit", ""))
if not sit_body or "_on_exam_sit" not in p7_bodies.get("_setup_exam", ""):
    print("  ✗ 贡院赴试未接线")
    problems.append("贡院赴试未接线")
elif any(tok in sit_body for tok in ("add_money", "spend_money", "chapter =", "chapter +=", "Fleet.")):
    print("  ✗ 赴试发了钱、跳了章或动了船")
    problems.append("赴试不得发钱跳章改船")
elif not ('"exam_sat_ch%d" % GameState.chapter' in _p7_code(p7_bodies.get("_exam_sat_flag", ""))
          and "_exam_sat_flag()" in sit_body and "has_flag(chapter_flag)" in sit_body
          and "advance_days(EXAM_SIT_DAYS)" in sit_body):
    print("  ✗ 赴试未按 exam_sat_ch<章> 每章一次、费 EXAM_SIT_DAYS")
    problems.append("赴试每章一次未接")
elif not all(tok in sit_body for tok in (
    "scholar_tendency >= GameState.sea_tendency", "add_fame(4)", "scholar_tendency += 2",
    'set_flag("exam_sat")', "add_fame(1)", "sea_tendency += 1",
)):
    print("  ✗ 赴试结算漂移（学者不输海路 +4/+2/exam_sat，否则 +1/海路 +1）")
    problems.append("赴试结算漂移")
elif sit_body.find('set_flag("exam_sat")') > sit_body.find("else:"):
    print("  ✗ exam_sat 记在了海路一支")
    problems.append("exam_sat 分支错")
else:
    print("  ✓ 赴试每章一次、费 15 日；学者不输海路记 exam_sat")
# 身份相关写入必须早于 advance_days：三月下旬赴试会跨入四月触发 _settle_history。
if 0 <= sit_body.find('set_flag("exam_sat")') < sit_body.find("advance_days(EXAM_SIT_DAYS)"):
    print("  ✓ 赴试先写 exam_sat 再 advance_days（跨月身份结算）")
else:
    print("  ✗ 赴试 exam_sat 写在 advance_days 之后（跨月会先锁身份）")
    problems.append("赴试跨月身份时序")
# 誊录同理：工钱与学者倾向须先于 advance_days(EXAM_COPY_DAYS)，三月末誊录跨四月同样触发身份结算。
copy_body = _p7_code(p7_bodies.get("_on_exam_copy", ""))
copy_adv = copy_body.find("advance_days(EXAM_COPY_DAYS)")
if 0 <= copy_body.find("scholar_tendency += 1") < copy_adv and 0 <= copy_body.find("add_money(EXAM_STIPEND)") < copy_adv:
    print("  ✓ 誊录先记工钱与学者倾向再 advance_days（跨月身份结算）")
else:
    print("  ✗ 誊录工钱/学者倾向写在 advance_days 之后（跨月会先锁身份）")
    problems.append("誊录跨月身份时序")
# 赴试只兴化、泉州（P7 §贡院）。city_exam 在通用九卡里，每港都进得了 {港}_exam，须在工席与处理函数两头拦。
sit_ports = re.search(r"const EXAM_SIT_PORTS\s*:=\s*\[(.*?)\]", main_src, re.S)
exam_setup = _p7_code(p7_bodies.get("_setup_exam", ""))
sit_guard = sit_body.find("EXAM_SIT_PORTS.has(port_id)")
if not sit_ports or set(re.findall(r'"(\w+)"', sit_ports.group(1))) != {"xinghua", "quanzhou"}:
    print("  ✗ EXAM_SIT_PORTS 不是兴化 / 泉州二港")
    problems.append("赴试港口漂移")
elif not (0 <= exam_setup.find("EXAM_SIT_PORTS.has(port_id)") < exam_setup.find("本港无贡院科场")
          < exam_setup.find("_on_exam_sit")):
    print("  ✗ 别港贡院仍出赴试钮（_setup_exam 须先按 EXAM_SIT_PORTS 改只读）")
    problems.append("赴试工席未限港")
elif not (0 <= sit_guard < sit_body.find("set_flag(chapter_flag)") and "return" in sit_body[sit_guard:sit_body.find("set_flag(chapter_flag)")]):
    print("  ✗ _on_exam_sit 未先按 EXAM_SIT_PORTS 拦别港")
    problems.append("赴试处理未限港")
elif "_on_exam_copy.bind(port_id)" not in exam_setup or "EXAM_SIT_PORTS" in _p7_code(p7_bodies.get("_on_exam_copy", "")):
    print("  ✗ 誊录工席被限港牵连")
    problems.append("誊录不应限港")
else:
    print("  ✓ 赴试只在兴化 / 泉州；别港贡院只读「本港无贡院科场」，誊录照旧")
ident = _p7_code(func_bodies(gs_src).get("resolve_identity_1268", ""))
tie = re.search(r"if scholar_tendency == sea_tendency:\s*\n\s*scholar_wins = (.*)", ident)
if tie and 0 <= tie.group(1).find('has_flag("exam_sat")') < tie.group(1).find('has_flag("chose_land_first")'):
    print("  ✓ 1268 殿试打平先读 exam_sat，再看 chose_land_first")
else:
    print("  ✗ 1268 殿试打平未优先读 exam_sat")
    problems.append("1268 破平未读 exam_sat")
ge_smoke = os.path.join(ROOT, "tools", "p7_guild_exam_smoke.gd")
ge_src = open(ge_smoke, encoding="utf-8").read() if os.path.exists(ge_smoke) else ""
# lane gd19：行会抄行情条数（商誉 < 8 抄 3 / ≥ 8 抄 5）由 p7 的 _check_spread_rows 判，调用行也须在
if all(tok in ge_src for tok in ("P7_GUILD_EXAM_SMOKE_OK", "交会费入行", "入场赴试", "resolve_identity_1268",
                                 "func _check_spread_rows(", "\t_check_spread_rows(main)")):
    print("  ✓ 入行 / 行情条数 / 赴试行为 smoke 在（tools/p7_guild_exam_smoke.gd）")
else:
    print("  ✗ 缺 tools/p7_guild_exam_smoke.gd 或其断言被删")
    problems.append("入行赴试 smoke 缺失")
# 工席成功态过渡（淡入墨幕 + 题签 + 淡出）：入行 / 赴试成功后经 play_transition 在全黑时 load_scene；
# 过场层不上场（headless / -s 工具脚本）时须当帧调 at_black、不 await，否则 smoke 与巡检量到的是旧页。
ut_path = os.path.join(ROOT, "scripts", "ui", "UiTransition.gd")
ut_src = open(ut_path, encoding="utf-8").read() if os.path.exists(ut_path) else ""
pt_body = _p7_code(p7_bodies.get("play_transition", ""))
_pt_live = pt_body.find("_CINE.live()")
_pt_null = pt_body.find("if node == null:")
if not ut_src or "is_headless()" not in ut_src or "UiTheme." not in ut_src:
    print("  ✗ 缺 scripts/ui/UiTransition.gd，或它没在 headless 下旁路 / 没取 UiTheme 色字")
    problems.append("工席过渡脚本缺失")
elif not (0 <= _pt_live < _pt_null < pt_body.find("at_black.call()") < pt_body.find("return") < pt_body.find("await node.finished")):
    print("  ✗ play_transition 未按 Cinematics.live() 旁路（不上场时须当帧调 at_black 再 return）")
    problems.append("工席过渡未旁路")
elif not all("play_transition(" in b and "load_scene.bind(current_scene_id)" in b and "load_scene(current_scene_id)" not in b
             for b in (join_body, sit_body)):
    print("  ✗ 入行 / 赴试成功未接 play_transition（或仍另调一次 load_scene）")
    problems.append("工席过渡未接钩子")
else:
    print("  ✓ 入行 / 赴试成功走 play_transition（全黑时 load_scene；headless 当帧直通）")
# 序章开卷 / 入酒棚纪实题签（Lane O）：题名与朱印「序」锁在 UiTransition；Main 钩子走 play_transition。
_start_body = _p7_code(p7_bodies.get("_on_start_game_pressed", ""))
if ("prologue_open_title" not in ut_src or "序章・卷首" not in ut_src
        or "prologue_shore_title" not in ut_src or "序章・兴化海口" not in ut_src):
    print("  ✗ UiTransition 缺序章・卷首 / 序章・兴化海口题签助手")
    problems.append("序章题签助手缺失")
elif ("prologue_open_title()" not in _start_body or "prologue_shore_title()" not in _start_body
        or "play_transition(" not in _start_body or 'begins_with("cg_narrate")' not in _start_body):
    print("  ✗ 开卷 / 入酒棚未接序章题签 play_transition")
    problems.append("序章题签未接钩子")
else:
    print("  ✓ 开卷 / 入酒棚走序章纪实题签（play_transition；headless 直通）")
# 守城 / 终局岸带纪实题签（Lane R）：题名与朱印「城」「终」锁在 UiTransition；首次进岸带经 _shore_title_once 演一次
# （UI 态 _shore_title_seen 防重播），墨幕全黑时再排岸带；城防账 / 航海札记共用 _band_head（泥金题 + 印 + 分隔线）。
_build_shore_body = _p7_code(p7_bodies.get("_build_shore", ""))
_once_body = _p7_code(p7_bodies.get("_shore_title_once", ""))
_band_head_body = _p7_code(p7_bodies.get("_band_head", ""))
_siege_port_body = _p7_code(p7_bodies.get("_setup_siege_port", ""))
_ended_port_body = _p7_code(p7_bodies.get("_setup_ended_port", ""))
if ("func siege_title" not in ut_src or "兴化军・围城" not in ut_src
        or "func endgame_title" not in ut_src or '"城")' not in ut_src or '"终")' not in ut_src):
    print("  ✗ UiTransition 缺兴化军・围城 / 港名・结局题签助手（印「城」「终」）")
    problems.append("守城终局题签助手缺失")
elif not ('_shore_title_once("ended", _setup_ended_port)' in _build_shore_body
          and '_shore_title_once("siege", _setup_siege_port)' in _build_shore_body
          and "_shore_title_seen.has(kind)" in _once_body and "play_transition(" in _once_body
          and _once_body.find("_shore_title_seen.has(kind)") < _once_body.find("_shore_title_seen[kind] = true") < _once_body.find("play_transition(")
          and "siege_title()" in _once_body and "endgame_title(" in _once_body
          and "siege_title()" in _siege_port_body and "endgame_title(" in _ended_port_body):
    print("  ✗ 守城 / 终局岸带未经 _shore_title_once 接题签（或未防重播）")
    problems.append("守城终局题签未接钩子")
elif not ("HSeparator.new()" in _band_head_body and "_seal_mark(seal)" in _band_head_body
          and '_band_head(col, "航海札记", "终"' in _p7_code(p7_bodies.get("_epilogue_slip", ""))
          and '"城"' in _p7_code(p7_bodies.get("_siege_stat_slip", "")) and "_band_head(col," in _p7_code(p7_bodies.get("_siege_stat_slip", ""))):
    print("  ✗ 城防账 / 航海札记抬头未走 _band_head（泥金题 + 印 + 分隔线）")
    problems.append("守城终局小笺抬头漂移")
elif not os.path.exists(os.path.join(ROOT, "tools", "qa_siege_endgame_probe.gd")):
    print("  ✗ 缺 tools/qa_siege_endgame_probe.gd")
    problems.append("守城终局探针缺失")
else:
    print("  ✓ 守城 / 终局岸带首进走纪实题签（城 / 终；UI 态防重播；headless 直通），小笺抬头同序章文法")
# 终局「重读结局」入口（Lane X）：札记抬头旁注终局时地、笺脚注文；重读钮仍是动作行主钮（带 tooltip）；
# _on_reread_ending 只翻开既有册页——不传 ending（不再 finish / 不演结局过场）、眉题「重读・时地」钮「合上册页」、不经 _shore_title_once、册页已开不叠。
_epi_body = _p7_code(p7_bodies.get("_epilogue_slip", ""))
_reread_body = _p7_code(p7_bodies.get("_on_reread_ending", ""))
_refresh_body = _p7_code(p7_bodies.get("_refresh_shore", ""))
_show_ch_x = _p7_code(p7_bodies.get("_show_chapter_dialog", ""))
if not ('_band_head(col, "航海札记", "终", GameState.ended_at)' in _epi_body
        and "EpilogueFoot" in _epi_body and "重读结局" in _epi_body and "TEXT_DIM, 16" in _epi_body):
    print("  ✗ 航海札记缺终局时地旁注或笺脚「重读结局」注文")
    problems.append("终局札记抬头/笺脚漂移")
elif not ('_shore_action("重读结局"' in _refresh_body and "RereadEnding" in _refresh_body
          and "tooltip_text" in _refresh_body and "_on_reread_ending" in _refresh_body):
    print("  ✗ 终局动作行「重读结局」主钮缺名或 tooltip")
    problems.append("重读结局钮漂移")
elif not ("_show_chapter_dialog(" in _reread_body and '"ending": ""' in _reread_body
          and '"ok_text": "合上册页"' in _reread_body and '"重读' in _reread_body
          and 'res.get("ok_text", "记下这一纲")' in _show_ch_x
          and 'res.get("kicker", "了结")' in _show_ch_x
          and "is_instance_valid(_chapter_host)" in _reread_body
          and "play_transition(" not in _reread_body and "_shore_title" not in _reread_body
          and "finish(" not in _reread_body):
    print("  ✗ _on_reread_ending 不再只翻开既有册页（或会重播题签 / 叠册页 / 再 finish）")
    problems.append("重读结局入口漂移")
elif not os.path.exists(os.path.join(ROOT, "tools", "qa_ending_reread_probe.gd")):
    print("  ✗ 缺 tools/qa_ending_reread_probe.gd")
    problems.append("终局重读探针缺失")
else:
    print("  ✓ 终局重读结局：札记旁注时地 + 笺脚注文；重读只翻既有册页（眉题重读・合上册页），不重播题签、不叠册页、不再 finish")
# 章晋升册页 / 翻页题签（Lane W）：摘要「这一路」+ 代价分区；skip_years 末行「自…至于…」；
# 确认「承此一路」走 promote_title 印「晋」；不改 SKIP_* / advance_years 数值。
_confirm_ch = _p7_code(p7_bodies.get("_confirm_chapter_sheet", ""))
_era_body = _p7_code(p7_bodies.get("_era_summary_lines", ""))
_show_ch = _p7_code(p7_bodies.get("_show_chapter_dialog", ""))
_gm_skip = open(os.path.join(ROOT, "scripts", "GameManager.gd"), encoding="utf-8").read()
# skip_years 末行（lane cs11：原先「自%s至于%s」查的是整份 GameManager，文案却点名 skip_years 末行；改成取体、看最后一条 lines.append）
_skip_apps = re.findall(r'\blines\.append\((.*)', _locate_func(_gm_skip, "skip_years"))
if ("func promote_title" not in ut_src or "func promote_open" not in ut_src
        or "年后" not in ut_src or '"晋")' not in ut_src):
    print("  ✗ UiTransition 缺晋升翻页题签助手（promote_title / 印「晋」）")
    problems.append("晋升题签助手缺失")
elif not ("promote_title(" in _confirm_ch and "play_transition(" in _confirm_ch
          and '"晋"' in _confirm_ch and "_chapter_advanced" in _confirm_ch):
    print("  ✗ 晋升册页确认未接 promote_title / play_transition（印「晋」）")
    problems.append("晋升翻页题签未接钩子")
elif not ("这一路" in _show_ch and "代价" in _show_ch
          and "_chapter_advanced" in _show_ch and "_chapter_years" in _show_ch):
    print("  ✗ 晋升册页缺「这一路」/「代价」分区或未记住 advanced/years")
    problems.append("晋升册页摘要代价分区漂移")
elif "span :=" not in _era_body:
    print("  ✗ _era_summary_lines 未按跳年数写「这两年/这三年」")
    problems.append("跳年摘要年数笼统")
elif not _skip_apps or "自%s至于%s" not in _skip_apps[-1] or "SKIP_HULL_DECAY" not in _gm_skip:
    print("  ✗ skip_years 末行未改「自…至于…」或 SKIP_* 常量丢失")
    problems.append("跳年代价末行漂移")
elif not os.path.exists(os.path.join(ROOT, "tools", "qa_chapter_promote_probe.gd")):
    print("  ✗ 缺 tools/qa_chapter_promote_probe.gd")
    problems.append("晋升册页探针缺失")
else:
    print("  ✓ 章晋升册页：摘要/代价分区 + 翻页题签印「晋」；skip_years 末行历法纪实；数值未改")
if all(s in main_src for s in (
    '"_guild"', '"_exam"', '"_residence"', '"_temple"',
    "bg_quanzhou_ledger.jpg", "bg_academy.jpg", "bg_xinghua_study.jpg",
    "bg_temple_library.jpg",
)):
    print("  ✓ 行会/贡院/住宅/寺观有设施背景")
else:
    print("  ✗ 设施缺背景")
    problems.append("设施缺 FACILITY_BG")
for rel in (
    "assets/bg_quanzhou_ledger.jpg",
    "assets/bg_academy.jpg",
    "assets/bg_xinghua_study.jpg",
    "assets/bg_temple_library.jpg",
    "assets/icon_temple.png",
):
    if os.path.isfile(os.path.join(ROOT, rel)):
        print("  ✓ %s 在仓库" % rel)
    else:
        print("  ✗ 缺 %s" % rel)
        problems.append("缺 %s" % rel)
if "discoveries_near" not in defined.get("GameManager", set()):
    print("  ✗ GameManager.discoveries_near 未定义")
    problems.append("缺 discoveries_near")
else:
    print("  ✓ GameManager.discoveries_near 已定义")
temple_fn = _locate_func(main_src, "_on_temple_look")
if not temple_fn:
    print("  ✗ 寺观细看未接线")
    problems.append("缺 _on_temple_look")
elif any(tok in temple_fn for tok in ("add_fame", "report_discovery")):
    print("  ✗ 寺观勘见给了名声或当场呈报（赏格须回市舶司）")
    problems.append("寺观不得给名声/呈报")
elif "record_discovery" in temple_fn and "TEMPLE_LOOK_DAYS" in temple_fn:
    print("  ✓ 寺观细看只记入册、耗日，不给名声")
else:
    print("  ✗ 寺观细看未走 record_discovery")
    problems.append("寺观未记入册")
rub_fn = _locate_func(main_src, "_on_temple_rub")
if not rub_fn:
    print("  ✗ 寺观拓碑未接线")
    problems.append("缺 _on_temple_rub")
elif any(tok in rub_fn for tok in ("add_fame", "report_discovery")):
    print("  ✗ 寺观拓碑给了名声或当场呈报")
    problems.append("寺观拓碑不得给名声/呈报")
elif "add_ledger_note" in rub_fn and "TEMPLE_RUB_DAYS" in rub_fn:
    print("  ✓ 寺观拓碑只写入边记、耗日，不给名声")
else:
    print("  ✗ 寺观拓碑未走 add_ledger_note")
    problems.append("寺观未写入边记")
sim_src = open(os.path.join(ROOT, "tools", "simulate_run.py"), encoding="utf-8").read()
if any(tok in sim_src for tok in (
    "scholar_tendency", "誊录", "EXAM_STIPEND", "HOME_RATE",
    "勘见", "TEMPLE_LOOK", "_on_temple_look", "record_discovery",
    "拓碑", "TEMPLE_RUB", "_on_temple_rub",
)):
    print("  ✗ simulate_run 自动走了贡院誊录、住处歇息或寺观勘见/拓碑")
    problems.append("simulate_run 不得自动誊录/住家/勘见/拓碑")
else:
    print("  ✓ simulate_run 不自动誊录、歇住家、勘见、拓碑（贡院/住宅/寺观不进通关主循环）")
if '"_inn"' in main_src and "bg_relay_post.jpg" in main_src:
    print("  ✓ 旅店有设施背景")
else:
    print("  ✗ 旅店缺设施背景")
    problems.append("旅店缺 FACILITY_BG")

body = _locate_func(gm_src, "load_texture")
if body:
    fi = body.find("get_file_as_bytes")
    li = body.find("load(path)")
    if fi >= 0 and (li < 0 or fi < li):
        print("  ✓ load_texture 先按文件头解码（避开 valid=false / 假 PNG 的 ERROR）")
    else:
        print("  ✗ load_texture 仍先走 ResourceLoader.load")
        problems.append("load_texture 仍先 load()")
else:
    print("  ✗ 未找到 load_texture")
    problems.append("缺 load_texture")

scenes_path = os.path.join(ROOT, "data", "scenes.json")
with open(scenes_path, encoding="utf-8") as f:
    scenes_doc = json.load(f)
yamen_titles = set()
market_titles = set()
guild_subs = set()
exam_subs = set()
home_subs = set()
temple_subs = set()
port_ids_with_temple = set()
port_scene_ids = []
for sc in scenes_doc.get("scenes", []):
    if sc.get("type") != "port":
        continue
    sid = sc.get("id", "")
    port_scene_ids.append(sid)
    for fac in sc.get("facilities", []):
        fid = fac.get("id", "")
        if fid == "city_yamen":
            yamen_titles.add(fac.get("title", ""))
        if fid == "city_market":
            market_titles.add(fac.get("title", ""))
        if fid == "city_guild":
            guild_subs.add(fac.get("subtitle", ""))
        if fid == "city_exam":
            exam_subs.add(fac.get("subtitle", ""))
        if fid == "city_residence":
            home_subs.add(fac.get("subtitle", ""))
        if fid == "city_temple":
            temple_subs.add(fac.get("subtitle", ""))
            port_ids_with_temple.add(sid)
if yamen_titles == {"市舶司"}:
    print("  ✓ 港卡 city_yamen 标题是市舶司（不再写衙门）")
else:
    print("  ✗ 港卡市舶司标题漂移：%s" % sorted(yamen_titles))
    problems.append("港卡 yamen 标题不是市舶司")
if market_titles == {"牙行"}:
    print("  ✓ 港卡 city_market 标题是牙行（不再写市场）")
else:
    print("  ✗ 港卡牙行标题漂移：%s" % sorted(market_titles))
    problems.append("港卡 market 标题不是牙行")
if guild_subs == {"议价・立籍"}:
    print("  ✓ 港卡行会副题是议价・立籍")
else:
    print("  ✗ 行会副题漂移：%s" % sorted(guild_subs))
    problems.append("行会副题未改")
if exam_subs == {"誊录・观礼"}:
    print("  ✓ 港卡贡院副题是誊录・观礼")
else:
    print("  ✗ 贡院副题漂移：%s" % sorted(exam_subs))
    problems.append("贡院副题未改")
if home_subs == {"账本・歇息"}:
    print("  ✓ 港卡住宅副题是账本・歇息")
else:
    print("  ✗ 住宅副题漂移：%s" % sorted(home_subs))
    problems.append("住宅副题未改")
if temple_subs == {"勘见・拓碑"} and set(port_scene_ids) <= port_ids_with_temple:
    print("  ✓ 港卡寺观副题是勘见・拓碑，剧情港均有此卡")
else:
    print("  ✗ 寺观卡漂移：副题 %s，缺卡港 %s" % (
        sorted(temple_subs), sorted(set(port_scene_ids) - port_ids_with_temple),
    ))
    problems.append("寺观港卡未对齐")
disc_path = os.path.join(ROOT, "data", "discoveries.json")
with open(disc_path, encoding="utf-8") as f:
    disc_doc = json.load(f)
note = str(disc_doc.get("meta", {}).get("note", ""))
if "寺观上报" in note or "寺观呈报" in note:
    print("  ✗ discoveries.json 仍写寺观上报（呈报只在市舶司）")
    problems.append("发现录 note 把呈报写到寺观")
else:
    print("  ✓ 发现录 note 不把呈报放到寺观")
ports_path = os.path.join(ROOT, "data", "ports.json")
with open(ports_path, encoding="utf-8") as f:
    ports_doc = json.load(f)
near_ports = set()
for d in disc_doc.get("discoveries", []):
    for pid in d.get("near_ports", []):
        near_ports.add(pid)
bare = [p.get("id") for p in ports_doc.get("ports", []) if p.get("id") not in near_ports]
if bare:
    print("  ✗ 无近侧发现的港口：%s" % ", ".join(bare))
    problems.append("有港无 near_ports 发现")
else:
    print("  ✓ 各港至少一条近侧发现（寺观细看不空）")
fuzhou_ids = [
    d.get("id") for d in disc_doc.get("discoveries", [])
    if "fuzhou" in d.get("near_ports", [])
]
if "beacon_ruin" in fuzhou_ids:
    print("  ✓ 福州近侧含废烽堠")
else:
    print("  ✗ 福州近侧没有废烽堠")
    problems.append("福州缺 beacon_ruin")
title_ui = _locate_func(main_src, "_setup_title_and_invest")
if "纲首" in title_ui:
    print("  ✗ 职衔说明文案写了纲首")
    problems.append("职衔 UI 含纲首")
elif title_ui:
    print("  ✓ 职衔说明不写纲首（下一档走 titles.json 的 name）")
else:
    print("  ✗ 未找到 _setup_title_and_invest")
    problems.append("缺 _setup_title_and_invest")
print("九之二、剧情场景不得遮蔽港口 id（云端 be04）")
print("=" * 68)
print("  load_scene 先查 scenes.json。非 port 场景若与港口同 id，入港不记 visited_ports，牙行也进不去。")

with open(os.path.join(ROOT, "data", "ports.json"), encoding="utf-8") as f:
    port_ids = {p.get("id") for p in json.load(f).get("ports", [])}
with open(os.path.join(ROOT, "data", "scenes.json"), encoding="utf-8") as f:
    scene_list = json.load(f).get("scenes", [])
shadowed = [s.get("id") for s in scene_list
            if s.get("id") in port_ids and s.get("type") != "port"]
if shadowed:
    print(f"  ✗ 非 port 剧情场景与港口同 id：{shadowed}")
    problems.append(f"剧情场景遮蔽港口 {shadowed}")
else:
    print("  ✓ 与港口同 id 的场景都是 type=port")

# 主干把设施改写名单收成常量 REMAPPED_FACILITIES（be04 原版查的是行内列表字面量）
rewrite = re.search(r'REMAPPED_FACILITIES\s*:?=\s*\[([^\]]+)\]', main_src, re.S)
if rewrite is None:
    rewrite = re.search(r'target_scene in \[([^\]]+)\]', main_src)
inn_ok = rewrite is not None and "city_inn" in rewrite.group(1)
if inn_ok:
    print("  ✓ 旅店 city_inn 会改写成「当前港口_inn」")
else:
    print("  ✗ 旅店 city_inn 未进入设施改写——会把港口切成 city")
    problems.append("city_inn 未改写")

invest = func_bodies(seachart_src).get("_on_investigate_discovery", "")
# 按钮回调可以指向 _on_event_continue，但不能在同一次点击里直接调用它或 _sail_next_day
if ("advance_days(1)" in invest
        and "_sail_next_day(" not in invest
        and "_on_event_continue()" not in invest):
    print("  ✓ 发现调查只 advance_days(1)，同一次点击不再推进下一日")
else:
    print("  ✗ 发现调查的「费 1 日」仍会再进下一日")
    problems.append("发现调查双日")

# 主干把 \A 解码收进 _unescape_scene_text（be04 原版查的是行内 replace）
if "cg_title" in main_src and ('replace("\\\\A"' in main_src or "_unescape_scene_text(" in main_src):
    print("  ✓ 调查模式在 title/body 为空时回读 cg_title / cg_sub")
else:
    print("  ✗ 调查模式未回读 cg_title，开场五屏正文仍是空的")
    problems.append("开场 cg 未回读")

sink_body = func_bodies(ship_src).get("_sink_ship", "")
battle_at = sink_body.find("pending_battle")
clear_at = sink_body.find("clear_cargo")
# set_flag("return_to_port") 里也有 return 这四个字母，只认独立的 return 语句
ret_stmt = re.search(r'^\t+return\s*$', sink_body, re.M)
ret_at = ret_stmt.start() if ret_stmt else -1
if battle_at >= 0 and ret_at > battle_at and (clear_at < 0 or clear_at > ret_at):
    print("  ✓ 战斗沉没在 return 之后才 clear_cargo，败局可以按比例扣货")
else:
    print("  ✗ 战斗沉没仍先清空货舱")
    problems.append("战斗沉没先清空货舱")
print("九之三、审计硬伤回归（进港 / 旅店 / 发现一日 / 沉船货舱）（云端 c148）")
print("=" * 68)

main_src = read_main_src()
fac_body = _locate_func(main_src, "_on_facility_pressed")
# 主干把改写名单收成常量 REMAPPED_FACILITIES；函数体引用常量、常量里含 city_inn 即算改写
_remap_m = re.search(r'REMAPPED_FACILITIES\s*:?=\s*\[([^\]]+)\]', main_src, re.S)
_remap_has_inn = _remap_m is not None and '"city_inn"' in _remap_m.group(1) and "REMAPPED_FACILITIES" in fac_body
if ('"city_inn"' in fac_body or _remap_has_inn) and "trim_prefix(\"city_\")" in fac_body:
    print("  ✓ 旅店 city_inn 随当前港口改写")
else:
    print("  ✗ 旅店 city_inn 未进设施改写，离开会落到港口 id「city」")
    problems.append("city_inn 未改写")

seachart_src_full = open(os.path.join(ROOT, "scripts/SeaChart.gd"), encoding="utf-8").read()
inv_body = _locate_func(seachart_src_full, "_on_investigate_discovery")
inv_code = "\n".join(re.sub(r'#.*$', '', ln) for ln in inv_body.split("\n"))
if inv_code.count("advance_days") == 1 and "_sail_next_day" not in inv_code and "_on_event_continue()" not in inv_code:
    print("  ✓ 发现调查只 advance_days 一次，不在同一次点击里续航")
else:
    print("  ✗ 发现调查仍会叠日（advance_days 与 _sail_next_day 同一次点击）")
    problems.append("发现调查叠日")

ship_src_full = open(os.path.join(ROOT, "scripts/Ship.gd"), encoding="utf-8").read()
sink_body = _locate_func(ship_src_full, "_sink_ship")
battle_ret = sink_body.find("_battle_player_sunk")
clear_at = sink_body.find("Fleet.clear_cargo()")
if battle_ret != -1 and (clear_at == -1 or clear_at > battle_ret):
    print("  ✓ 战斗沉船先交给败局结算，不先清空全队货舱")
else:
    print("  ✗ Ship._sink_ship 仍在战斗结算前 clear_cargo")
    problems.append("战斗沉船先清货舱")

fleet_src = open(os.path.join(ROOT, "scripts/core/Fleet.gd"), encoding="utf-8").read()
if re.search(r'^func clear_ship_cargo\b', fleet_src, re.M) and "clear_ship_cargo" in seachart_src_full:
    print("  ✓ 旗舰沉没只清该船货舱（clear_ship_cargo）")
else:
    print("  ✗ 败局未走 clear_ship_cargo")
    problems.append("败局未走 clear_ship_cargo")
print("九之四、进港与结算回归（审计硬伤）（云端 00b4）")
print("=" * 68)
print("  海图回港、旅店、发现计日、沉船货损。改数据或结算顺序时这里会红。")

def _code_only(src):
    # 只截字符串外的 #（lane bs）：逐字符扫 ' / " / """ / ''' 引号状态，
    # "[color=#aabbcc]" + Foo.bar 这类行后半截代码不再被当注释丢掉。
    # 单行串到行尾即收（未闭合不吞下一行）；三引号串可跨行；\ 转义下一字符。
    out, quote, i, n = [], None, 0, len(src)
    while i < n:
        ch = src[i]
        if quote is None:
            if ch == "#":
                j = src.find("\n", i)
                i = n if j < 0 else j
                continue
            if ch in "\"'":
                quote = ch * 3 if src.startswith(ch * 3, i) else ch
                out.append(quote)
                i += len(quote)
                continue
        elif ch == "\\":
            out.append(src[i:i + 2])
            i += 2
            continue
        elif src.startswith(quote, i):
            out.append(quote)
            i += len(quote)
            quote = None
            continue
        elif ch == "\n" and len(quote) == 1:
            quote = None
        out.append(ch)
        i += 1
    return "".join(out)

fac = _code_only(func_bodies(main_src).get("_on_facility_pressed", ""))
# 主干把改写名单收成常量 REMAPPED_FACILITIES（含 city_inn）
if ('"city_inn"' in fac or ("REMAPPED_FACILITIES" in fac and _remap_has_inn)) and "trim_prefix(\"city_\")" in fac:
    print("  ✓ 旅店 city_inn 随当前港口改写，离开键不会落到 id=city")
else:
    print("  ✗ 旅店未按当前港口改写")
    problems.append("city_inn 未改写成当前港口")

title_body = _code_only(func_bodies(main_src).get("_setup_title_mode", ""))
# 主干把 \A 解码收进 _unescape_scene_text
if "cg_title" in title_body and "cg_sub" in title_body and ("\\\\A" in title_body or "_unescape_scene_text(" in title_body):
    print("  ✓ 标题模式读 cg_title/cg_sub，并把 \\\\A 换成换行")
else:
    print("  ✗ 标题模式未读卷首正文或未把 \\\\A 换成换行")
    problems.append("标题模式未展示 cg 正文")

inv = _code_only(func_bodies(seachart_src).get("_on_investigate_discovery", ""))
# 取 be04/c148 语义：调查日只 advance_days 一次、不在同一次点击里直接续航（00b4 原版要求不调 advance_days）
if inv.count("advance_days") != 1:
    print("  ✗ 发现调查应恰好 advance_days 一次（现 %d 次）" % inv.count("advance_days"))
    problems.append("发现调查计日次数不对")
elif "_sail_next_day(" in inv or "_on_event_continue()" in inv:
    print("  ✗ 发现调查在同一次点击里直接续航，会与调查日叠成两日")
    problems.append("发现调查双计日")
elif "_on_event_continue" not in inv:
    print("  ✗ 发现调查没有回到航行循环（缺「继续航行」回调）")
    problems.append("发现调查未续航")
else:
    print("  ✓ 发现调查只计一日，续航交给下一次点击")

sink = func_bodies(ship_src).get("_sink_ship", "")
sink_code = _code_only(sink)
cut = sink_code.find("_battle_player_sunk")
if cut < 0:
    print("  ✗ Ship._sink_ship 未把战斗沉没交回 WorldMap")
    problems.append("战斗沉没未交回结算")
elif "clear_cargo" in sink_code[:cut]:
    print("  ✗ 战斗沉没在通知败局前 clear_cargo，25% 货损会落在空舱")
    problems.append("战斗沉没先清舱")
else:
    print("  ✓ 战斗沉没不先清舱，货损留给败局结算")

battle = _code_only(func_bodies(seachart_src).get("_on_battle_result", ""))
i_dur = battle.find("total_durability")
i25 = battle.find("lose_cargo_ratio(0.25)")
if i_dur < 0 or i25 < 0 or not (i_dur < i25):
    print("  ✗ 败局未在 25% 货损之前判断全队是否已经沉没")
    problems.append("败局货损未区分沉船")
else:
    print("  ✓ 全队沉没不走 25% 货损")

sink_voyage = _code_only(func_bodies(seachart_src).get("_sink", ""))
if "clear_cargo" in sink_voyage:
    print("  ✓ 全队沉没仍清空货舱")
else:
    print("  ✗ 全队沉没未清空货舱")
    problems.append("沉船未清舱")
print("九之五、哗变契约（士气低于线时换掉当日随机事件）（云端 7d9f）")
print("=" * 68)
print("  断粮把士气压过线才闹舱。散钱、放人、压住都进 Fleet.resolve_mutiny。")

fleet_src = ""
with open(os.path.join(ROOT, "scripts", "core", "Fleet.gd"), encoding="utf-8") as f:
    fleet_src = f.read()
for f in ("mutiny_ready", "resolve_mutiny", "mutiny_bribe_cost",
          "mutiny_dismiss_count", "mutiny_suppress_succeeds",
          "mutiny_dismiss_blocks_next_sail"):
    if f in defined.get("Fleet", set()):
        print(f"  ✓ Fleet.{f} 已定义")
    else:
        print(f"  ✗ Fleet.{f} 未定义")
        problems.append(f"Fleet.{f} 未定义")
if "MUTINY" in enum_map.get("Voyage", {}).get("EventKind", set()):
    print("  ✓ Voyage.EventKind.MUTINY 已声明（不进随机表）")
else:
    print("  ✗ Voyage.EventKind 缺少 MUTINY")
    problems.append("Voyage.EventKind 缺少 MUTINY")
if "func mutiny_event" in voyage_src and "roll_day_event" in voyage_src:
    roll_body = _locate_func(voyage_src, "roll_day_event")
    if "MUTINY" in roll_body:
        print("  ✗ roll_day_event 把哗变放进了随机表")
        problems.append("哗变进入随机表")
    else:
        print("  ✓ 哗变不在 roll_day_event 的随机表里")
else:
    print("  ✗ Voyage.mutiny_event 未定义")
    problems.append("Voyage.mutiny_event 未定义")
if "Fleet.mutiny_ready()" in seachart_src and "Voyage.EventKind.MUTINY" in seachart_src:
    print("  ✓ SeaChart 在 mutiny_ready 时改走哗变")
else:
    print("  ✗ SeaChart 未把低士气日改成哗变")
    problems.append("SeaChart 未接哗变")
for handler in ("_on_mutiny_bribe", "_on_mutiny_dismiss", "_on_mutiny_suppress"):
    if re.search(rf'^func\s+{handler}\b', seachart_src, re.M):
        print(f"  ✓ SeaChart.{handler} 已定义")
    else:
        print(f"  ✗ SeaChart.{handler} 未定义")
        problems.append(f"SeaChart.{handler} 未定义")
if 'resolve_mutiny("bribe")' in seachart_src and 'resolve_mutiny("dismiss")' in seachart_src and 'resolve_mutiny("suppress")' in seachart_src:
    print("  ✓ 三个选项都进 resolve_mutiny")
else:
    print("  ✗ 哗变选项没有全部进 resolve_mutiny")
    problems.append("哗变选项未进 resolve_mutiny")
if '"mutiny_cooldown"' in fleet_src:
    print("  ✓ 哗变冷却写入舰队存档")
else:
    print("  ✗ mutiny_cooldown 未进 to_dict")
    problems.append("mutiny_cooldown 未存档")
print("九之六、风涛分摊（每艘各吃一份，不把船数乘进旗舰）（云端 storm-7d9f）")
print("=" * 68)
if "damage_each_ship" in defined.get("Fleet", set()):
    print("  ✓ Fleet.damage_each_ship 已定义")
else:
    print("  ✗ Fleet.damage_each_ship 未定义")
    problems.append("Fleet.damage_each_ship 未定义")
storm_body = _locate_func(voyage_src, "_storm_event")
if "damage_each_ship" in storm_body and "damage_fleet" not in storm_body and "ships.size()" not in storm_body:
    print("  ✓ 风涛按艘分摊，不再乘船数打旗舰")
else:
    print("  ✗ 风涛仍把伤害堆进旗舰")
    problems.append("风涛未分摊")
flee_body = _locate_func(seachart_src, "_on_flee_pirates")
if "damage_fleet" in flee_body and "damage_each_ship" not in flee_body:
    print("  ✓ 逃走失败仍只打旗舰")
else:
    print("  ✗ 逃走失败不再打旗舰")
    problems.append("逃走失败误改成分摊")

print()
print("=" * 68)
print("九之七、发现录呈报路径与存档键")
print("=" * 68)
print("  勘见只入 discoveries_found；呈报只在市舶司，挪进 discoveries_reported 才给赏格名声。两键都进存档。")

_disc_gs = open(os.path.join(SCRIPTS, "GameState.gd"), encoding="utf-8").read()
_disc_main = read_main_src()
_disc_gs_fn = func_bodies(_disc_gs)
_disc_main_fn = func_bodies(_disc_main)
for sym in ("discoveries_found", "discoveries_reported", "has_found",
            "record_discovery", "unreported_discoveries", "report_discovery"):
    if sym in defined.get("GameState", set()):
        print(f"  ✓ GameState.{sym} 已定义")
    else:
        print(f"  ✗ GameState.{sym} 未定义")
        problems.append(f"GameState.{sym} 未定义")

_to_d = _code_only(_disc_gs_fn.get("to_dict", ""))
_from_d = _code_only(_disc_gs_fn.get("from_dict", ""))
for key in ("discoveries_found", "discoveries_reported"):
    if re.search(rf'"{key}"\s*:\s*{key}\b', _to_d) and re.search(rf'\b{key}\s*=\s*d\.get\("{key}"', _from_d):
        print(f"  ✓ 存档键 {key} 在 to_dict / from_dict 成对")
    else:
        print(f"  ✗ 存档键 {key} 未在 to_dict / from_dict 成对读写")
        problems.append(f"存档键 {key} 不对称")

_has = _code_only(_disc_gs_fn.get("has_found", ""))
if "discoveries_found" in _has and "discoveries_reported" in _has:
    print("  ✓ has_found 同时认已勘见与已呈报（呈报过的不再入册）")
else:
    print("  ✗ has_found 未同时查两册，呈报后可重复勘见")
    problems.append("has_found 未查两册")

_rec = _code_only(_disc_gs_fn.get("record_discovery", ""))
if ("has_found(" in _rec and "discoveries_found.append" in _rec
        and not any(t in _rec for t in ("discoveries_reported", "add_fame", "add_money"))):
    print("  ✓ record_discovery 去重后只入 discoveries_found，不给钱名")
else:
    print("  ✗ record_discovery 越过勘见册（直入已呈报或当场给钱名）")
    problems.append("record_discovery 越权")

_unrep = _code_only(_disc_gs_fn.get("unreported_discoveries", ""))
if "discoveries_found" in _unrep and "duplicate(" in _unrep:
    print("  ✓ unreported_discoveries 返回 discoveries_found 副本（遍历中呈报不改迭代源）")
else:
    print("  ✗ unreported_discoveries 未返回 discoveries_found 副本")
    problems.append("unreported_discoveries 非副本")

_rep = _code_only(_disc_gs_fn.get("report_discovery", ""))
_i_guard = _rep.find("in discoveries_found")
_i_erase = _rep.find("discoveries_found.erase(")
_i_push = _rep.find("discoveries_reported.append(")
_i_pay = min([i for i in (_rep.find("add_money("), _rep.find("add_fame(")) if i >= 0] or [-1])
if (0 <= _i_guard < _i_erase and 0 <= _i_erase and 0 <= _i_push and _i_pay >= 0
        and max(_i_erase, _i_push) < _i_pay and "add_money(" in _rep and "add_fame(" in _rep):
    print("  ✓ report_discovery 先验在册，挪入 discoveries_reported 后才给赏格与名声")
else:
    print("  ✗ report_discovery 顺序不对（须先验在册、erase + append，再 add_money / add_fame）")
    problems.append("report_discovery 呈报顺序")
for rk in ('"gold"', '"fame"', '"name"', '"promoted"', '"title"'):
    if rk not in _rep:
        print(f"  ✗ report_discovery 回执缺 {rk}（_on_report_discovery 要读）")
        problems.append(f"report_discovery 回执缺 {rk}")
if all(rk in _rep for rk in ('"gold"', '"fame"', '"name"', '"promoted"', '"title"')):
    print("  ✓ report_discovery 回执含 gold / fame / name / promoted / title")

_yamen = _code_only(_disc_main_fn.get("_setup_yamen", ""))
if "_setup_reporting()" in _yamen:
    print("  ✓ 市舶司页 _setup_yamen 挂呈报签")
else:
    print("  ✗ _setup_yamen 未调 _setup_reporting，呈报入口丢失")
    problems.append("市舶司未挂呈报")
_callers = sorted(fn for fn, b in _disc_main_fn.items()
                  if fn != "_setup_reporting" and "_setup_reporting()" in _code_only(b))
if _callers == ["_setup_yamen"]:
    print("  ✓ 呈报签只在市舶司页（别处不挂）")
else:
    print("  ✗ _setup_reporting 调用方漂移：%s" % _callers)
    problems.append("呈报签不止市舶司")

_slips = _code_only(_disc_main_fn.get("_setup_reporting", ""))
if ("GameState.unreported_discoveries()" in _slips
        and re.search(r'_slip_chip\(\s*_slip_row\([^)]*\)\s*,\s*"呈报"\s*,\s*_on_report_discovery\.bind\(', _slips)
        and "report_discovery(" not in _slips.replace("_on_report_discovery", "")):
    print("  ✓ _setup_reporting 按 unreported_discoveries 逐件出「呈报」chip，绑 _on_report_discovery")
else:
    print("  ✗ _setup_reporting 未按未呈报册出「呈报」chip 或当场呈报")
    problems.append("呈报 chip 接线")

_onrep = _code_only(_disc_main_fn.get("_on_report_discovery", ""))
if "GameState.report_discovery(" in _onrep and "load_scene(current_scene_id)" in _onrep:
    print("  ✓ _on_report_discovery 走 GameState.report_discovery 并重载本页")
else:
    print("  ✗ _on_report_discovery 未走 report_discovery 或未重载页面")
    problems.append("_on_report_discovery 接线")

_rep_callers = []
for _dp, _dn, _fs in os.walk(SCRIPTS):
    for _fn in _fs:
        if not _fn.endswith(".gd"):
            continue
        _src = open(os.path.join(_dp, _fn), encoding="utf-8").read()
        for _name, _body in func_bodies(_src).items():
            if re.search(r'(?<![\w_])(?:GameState\.)?report_discovery\(', _code_only(_body)):
                _rep_callers.append(f"{_fn}:{_name}")
if _rep_callers == ["Main.gd:_on_report_discovery"]:
    print("  ✓ report_discovery 只由 Main._on_report_discovery 调（航中/寺观不当场呈报）")
else:
    print("  ✗ report_discovery 调用方漂移：%s" % _rep_callers)
    problems.append("report_discovery 调用方漂移")

# Lane AC：发现录列表与呈报确认改纪实短句；存档键、呈报顺序与赏格公式不动
_ac_slips = _disc_main_fn.get("_setup_reporting", "")
_ac_onrep = _disc_main_fn.get("_on_report_discovery", "")
_ac_temple = _disc_main_fn.get("_setup_temple", "")
_ac_look = _disc_main_fn.get("_on_temple_look", "")
_ac_invest = func_bodies(open(os.path.join(SCRIPTS, "SeaChart.gd"), encoding="utf-8").read()).get("_on_investigate_discovery", "")
_ac_ok = (
    '"赏钱 %d　声名 %d" % [value, maxi(1, value / 10)]' in _ac_slips
    and 'd.get("historical_hook", "")' in _ac_slips
    and "呈报入案，赏钱声名同领。" in _ac_slips
    and "【呈报】「%s」入案。赏钱 %d，声名添 %d。%s" in _ac_onrep
    and '"案册改题「%s」。"' in _ac_onrep
    and '_slip_title(slip, name, "未勘")' in _ac_temple
    and '_slip_title(slip, name, "已入册")' in _ac_temple
    and '_slip_title(slip, name, "已呈案")' in _ac_temple
    and '_slip_note(slip, "赏格回市舶司。")' in _ac_temple
    and "【勘见】廊下细看 %d 日，「%s」记入册子。赏格回市舶司呈报。" in _ac_look
    and "记入册子，赏格回市舶司呈报。" in _ac_invest
    and "GameState.record_discovery(did)" in _ac_look and "TEMPLE_LOOK_DAYS" in _ac_look
)
# 只查代码行：SeaChart 注释里「下一次点击」是开发说明，不算玩家可见文案
_ac_bad = [b for b in ("名声加", "录入案册", "已记入册", '"已呈报"', "点击", "提交", "上报市舶司", "当有赏格")
           if b in _code_only(_ac_slips + _ac_onrep + _ac_temple + _ac_look + _ac_invest)]
if _ac_ok and not _ac_bad:
    print("  ✓ 发现录呈报签 / 确认日志 / 寺观旧迹题签纪实短句（Lane AC）")
else:
    print("  ✗ 发现录文案漂移（Lane AC）%s" % (("：回退 " + "、".join(_ac_bad)) if _ac_bad else ""))
    problems.append("发现录文案 Lane AC")
if os.path.exists(os.path.join(ROOT, "tools", "qa_discovery_probe.gd")):
    print("  ✓ 发现录截图探针 qa_discovery_probe.gd 在册（Lane AC）")
else:
    print("  ✗ 缺 tools/qa_discovery_probe.gd")
    problems.append("缺发现录截图探针")


print()
print("=" * 68)
print("九之八、存档关键旗标清洗契约")
print("=" * 68)
print("  SaveLoad 在写入与读回两端清洗 exam_sat / exam_sat_ch<章> / guild_*，并去重发现录。")

_saveload_path = os.path.join(ROOT, "scripts", "core", "SaveLoad.gd")
_saveload_src = open(_saveload_path, encoding="utf-8").read()
_saveload_fn = func_bodies(_saveload_src)
for _sym in ("_harden_state", "_normalise_flags", "_valid_flag_name", "_normalise_ids"):
    if _sym in _saveload_fn:
        print(f"  ✓ SaveLoad.{_sym} 已定义")
    else:
        print(f"  ✗ SaveLoad.{_sym} 未定义")
        problems.append(f"SaveLoad.{_sym} 未定义")

_save_body = _code_only(_saveload_fn.get("save_game", ""))
_load_body = _code_only(_saveload_fn.get("load_game", ""))
_harden_body = _code_only(_saveload_fn.get("_harden_state", ""))
_flags_body = _code_only(_saveload_fn.get("_normalise_flags", ""))
_flag_name_body = _code_only(_saveload_fn.get("_valid_flag_name", ""))
_ids_body = _code_only(_saveload_fn.get("_normalise_ids", ""))
if "_harden_state(GameState.to_dict())" in _save_body:
    print("  ✓ save_game 写入前清洗 GameState 状态")
else:
    print("  ✗ save_game 未在写入前清洗 GameState 状态")
    problems.append("save_game 未清洗状态")
if "_harden_state(state)" in _load_body and "GameState.from_dict" in _load_body:
    print("  ✓ load_game 读回前清洗状态（坏 state 类型回到空字典）")
else:
    print("  ✗ load_game 未在读回前清洗状态")
    problems.append("load_game 未清洗状态")
# 顶层分区须 Dictionary 兜底，避免坏档 String 传入 from_dict 触发类型错误。
if (
    "_as_dict" in _saveload_src
    and all(tok in _load_body for tok in (
        'Calendar.from_dict(_as_dict(',
        'Economy.from_dict(_as_dict(',
        'Fleet.from_dict(_as_dict(',
        'Crew.from_dict(_as_dict(',
    ))
):
    print("  ✓ load_game 对 calendar/economy/fleet/crew 做 Dictionary 兜底")
else:
    print("  ✗ load_game 分区未做 Dictionary 兜底")
    problems.append("load_game 分区未类型兜底")
# save_label 须走 _read_slot（正式档坏了读 .bak），不得只开正式档。
# lane sv：_read_slot / save_label / slot_source 同经 _resolve 定槽态，经 _resolve 也算。
_label_body = _code_only(_saveload_fn.get("save_label", ""))
_resolve_body = _code_only(_saveload_fn.get("_resolve", ""))
_via_resolve = "_resolve(slot)" in _code_only(_saveload_fn.get("_read_slot", "")) and "_bak_path(slot)" in _resolve_body
if "_read_slot(slot)" in _label_body or (_via_resolve and "_resolve(slot)" in _label_body):
    print("  ✓ save_label 经 _read_slot（含 .bak 回退）")
else:
    print("  ✗ save_label 未走 _read_slot")
    problems.append("save_label 未走 _read_slot")
# Lane T：正本坏、副抄可读时册页须有脚注；提示另走 save_tip，不塞进 save_label。
_source_body = _code_only(_saveload_fn.get("slot_source", ""))
_tip_body = _code_only(_saveload_fn.get("save_tip", ""))
if _via_resolve and "_resolve(slot)" in _source_body:
    _source_body += "\n" + _resolve_body
if (
    all(tok in _source_body for tok in ('"none"', '"primary"', '"bak"', '"corrupt"', "has_save(slot)", "_bak_path(slot)"))
    and ("slot_source(slot)" in _tip_body or (_via_resolve and "_resolve(slot)" in _tip_body))
    # lane sv：新版档第五态 future 须有脚注，且题签不说成「卷页损了」
    and ('"future"' not in _source_body or ("新版所记" in _tip_body and "新版所记" in _label_body))
    and "副抄" in _tip_body and "正本" in _tip_body
    and not re.search(r"（[^）]*）", _tip_body + _source_body + _label_body)
    and "副抄" not in _label_body
):
    print("  ✓ slot_source 分四态，save_tip 以正本/副抄纪实短句作脚注")
else:
    print("  ✗ slot_source/save_tip 缺失、四态不全或提示混入括号词/label")
    problems.append("存档槽坏档提示契约不全")
_save_dialog_code = _code_only(func_bodies(main_src).get("_show_save_dialog", ""))
_load_slot_code = _code_only(func_bodies(main_src).get("_on_load_slot", ""))
_save_slot_code = _code_only(func_bodies(main_src).get("_on_save_slot", ""))
if (
    "SaveLoad.save_label(n)" in _save_dialog_code
    and "SaveLoad.save_tip(n)" in _save_dialog_code
    and "_slip_note(slip, tip" in _save_dialog_code
    and "SaveLoad.slot_source(slot)" in _load_slot_code
    and "副抄" in _load_slot_code
    and "翻不开" not in _load_slot_code
    and "没能记下" not in _save_slot_code
):
    print("  ✓ 航海日志册页挂坏档脚注，翻阅/记录失败写纪实短句")
else:
    print("  ✗ 航海日志册页未挂坏档脚注，或翻阅/记录失败仍是旧句")
    problems.append("航海日志坏档脚注未接入")
# Lane T：四种槽态运行时探针须在库内，供回归复跑。
_tip_probe = os.path.join(ROOT, "tools", "qa_save_slot_tip_probe.gd")
if os.path.isfile(_tip_probe) and "slot_source" in open(_tip_probe, encoding="utf-8").read() and "SAVE_SLOT_TIP_PROBE" in open(_tip_probe, encoding="utf-8").read():
    print("  ✓ tools/qa_save_slot_tip_probe.gd 锁四态 tip")
else:
    print("  ✗ tools/qa_save_slot_tip_probe.gd 缺失或未覆盖 slot_source")
    problems.append("存档槽 tip 探针缺失")

if (
    all(token in _flags_body for token in ("TYPE_DICTIONARY", "TYPE_BOOL", "not raw.get(key)"))
    and all(token in _saveload_src for token in (
        'const EXAM_FLAG := "exam_sat"',
        'const EXAM_FLAG_PREFIX := "exam_sat_ch"',
        'const GUILD_FLAG_PREFIX := "guild_"',
    ))
    and all(token in _flag_name_body for token in ("EXAM_FLAG", "EXAM_FLAG_PREFIX", "GUILD_FLAG_PREFIX"))
):
    print("  ✓ 关键旗标只接受非空名称与 true（exam_sat / guild_*）")
else:
    print("  ✗ 关键旗标缺少字典、true 值或 exam_sat/guild_* 守卫")
    problems.append("关键旗标清洗不完整")
if all(token in _harden_body for token in ("discoveries_found", "discoveries_reported", "reported_set", "_normalise_ids")):
    print("  ✓ 发现录两册均清洗去重，已呈报优先于待呈报")
else:
    print("  ✗ 发现录未成对清洗或未让已呈报优先")
    problems.append("发现录清洗不完整")
if all(token in _ids_body for token in ("TYPE_ARRAY", "TYPE_STRING", "not (did in clean)")):
    print("  ✓ 发现录只保留非空字符串并去重")
else:
    print("  ✗ 发现录未限制字符串或去重")
    problems.append("发现录 id 清洗不完整")

# ── Astra L1：characters.json 工程词 + 展示入口锁 ──────────────
import re as _re_l1
_l1_pat = _re_l1.compile(r"placeholder|本作|玩家|士人线|海商线|乡土线")
_l1_chars = open(os.path.join(ROOT, "data", "characters.json"), encoding="utf-8").read()
_l1_hit = _l1_pat.search(_l1_chars)
if _l1_hit:
    print(f"  ✗ characters.json 仍含工程词「{_l1_hit.group(0)}」")
    problems.append(f"characters.json 工程词 {_l1_hit.group(0)}")
else:
    print("  ✓ characters.json 原稿无工程词（placeholder/本作/玩家/士人线/海商线/乡土线）")
_l1_art = open(os.path.join(ROOT, "scripts", "ui", "CharacterArt.gd"), encoding="utf-8").read()
_l1_codex = open(os.path.join(ROOT, "scripts", "ui", "CharacterCodex.gd"), encoding="utf-8").read()
_l1_main = read_main_src()
if "characters_codex.json" in _l1_art and "codex_bio(" in _l1_codex and "codex_short(" in _l1_main:
    print("  ✓ 展示入口走 characters_codex（CharacterArt/Codex/Main）")
else:
    print("  ✗ 展示入口未锁定 characters_codex")
    problems.append("展示入口未锁 characters_codex")
if 'get("bio"' in _l1_codex or '"bio_short"' in _l1_main:
    print("  ✗ 人物志/见面页仍直读 characters.json bio 原稿")
    problems.append("UI 直读 bio 原稿")
else:
    print("  ✓ 人物志/见面页不直读 bio/bio_short 原稿")

print("=" * 68)
print("Lane N — BoardingStage/CombatFx 真实接舷/海战钩子")
print("=" * 68)
_wm_n = open(os.path.join(SCRIPTS, "WorldMap.gd"), encoding="utf-8").read()
_sc_n = open(os.path.join(SCRIPTS, "SeaChart.gd"), encoding="utf-8").read()
_fx_n = open(os.path.join(SCRIPTS, "combat", "CombatFx.gd"), encoding="utf-8").read()
_main_n = read_main_src()
_hook_path = os.path.join(SCRIPTS, "combat", "CombatShoreHook.gd")
if os.path.isfile(_hook_path):
    print("  ✓ scripts/combat/CombatShoreHook.gd 存在")
else:
    print("  ✗ 缺 CombatShoreHook.gd")
    problems.append("缺 CombatShoreHook.gd")
for ok, label in (
    (_has_func(_wm_n, "_await_boarding_fx"), "WorldMap 等待接舷题签"),
    ("board_begin_subtitle" in _wm_n, "WorldMap 开场副题走 CombatFx"),
    ('"boarded"' in _wm_n, "WorldMap 传 boarded 标记"),
):
    if ok:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}")
        problems.append(label)
for tok, label in (
    ("sea_win_note", "SeaChart 用 CombatFx.sea_win_note"),
    ("_CombatFx", "SeaChart 预载 CombatFx"),
):
    if tok in _sc_n:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}")
        problems.append(label)
for tok in ("sea_win_note", "sea_flee_ok_note", "board_begin_subtitle"):
    if f"func {tok}" in _fx_n or f"static func {tok}" in _fx_n:
        print(f"  ✓ CombatFx.{tok}")
    else:
        print(f"  ✗ CombatFx.{tok} 缺失")
        problems.append(f"CombatFx.{tok}")
if "CombatShoreHook" in _main_n and "KEY_F9" in _main_n:
    print("  ✓ Main F9 薄接入 CombatShoreHook")
else:
    print("  ✗ Main 未薄接入 CombatShoreHook/F9")
    problems.append("Main 未接 CombatShoreHook")
# 营销词不得回潮
for bad in ("惊艳", "沉浸", "视觉盛宴", "夺下敌船"):
    if bad in _fx_n or bad in _wm_n:
        print(f"  ✗ 战斗文案回潮：{bad}")
        problems.append(f"战斗文案回潮:{bad}")
    else:
        print(f"  ✓ 无「{bad}」")

print("=" * 68)
print("Lane L — VisionStage / CombatLetterbox 主流程薄接入")
print("=" * 68)
_main_l = read_main_src()
_sc_l = open(os.path.join(SCRIPTS, "SeaChart.gd"), encoding="utf-8").read()
_wm_l = open(os.path.join(SCRIPTS, "WorldMap.gd"), encoding="utf-8").read()
_vs_path = os.path.join(SCRIPTS, "ui", "VisionStage.gd")
_lb_path = os.path.join(SCRIPTS, "ui", "CombatLetterbox.gd")
if os.path.isfile(_vs_path):
    print("  ✓ scripts/ui/VisionStage.gd 存在")
else:
    print("  ✗ 缺 VisionStage.gd")
    problems.append("缺 VisionStage.gd")
if os.path.isfile(_lb_path):
    print("  ✓ scripts/ui/CombatLetterbox.gd 存在")
else:
    print("  ✗ 缺 CombatLetterbox.gd")
    problems.append("缺 CombatLetterbox.gd")
if "KEY_F8" in _main_l and _has_func(_main_l, "_open_vision_stage") and "市舶纪事" in _main_l:
    print("  ✓ Main F8 / 市舶纪事 → VisionStage")
else:
    print("  ✗ Main 未薄接入 VisionStage（F8 / 市舶纪事）")
    problems.append("Main 未接 VisionStage")
if _has_func(_sc_l, "_battle_sea_name") and '"sea_name"' in _sc_l:
    print("  ✓ SeaChart pending_battle 写 sea_name")
else:
    print("  ✗ SeaChart 未写 sea_name")
    problems.append("SeaChart 缺 sea_name")
if 'pb.get("sea_name"' in _wm_l or "sea_x" in _wm_l:
    print("  ✓ WorldMap letterbox 读 sea_name")
else:
    print("  ✗ WorldMap letterbox 未读 sea_name")
    problems.append("WorldMap 未读 sea_name")
_vs_l = open(_vs_path, encoding="utf-8").read() if os.path.isfile(_vs_path) else ""
for bad in ("惊艳", "沉浸", "打造", "视觉盛宴"):
    if bad in _vs_l or bad in _main_l:
        print(f"  ✗ 观感文案回潮：{bad}")
        problems.append(f"观感文案回潮:{bad}")
    else:
        print(f"  ✓ 无「{bad}」")
_probe_l = os.path.join(ROOT, "tools", "qa_wire_vision_screenshots.gd")
if os.path.isfile(_probe_l):
    print("  ✓ tools/qa_wire_vision_screenshots.gd 存在")
else:
    print("  ✗ 缺 qa_wire_vision_screenshots.gd")
    problems.append("缺 wire 截图探针")

print("=" * 68)
print("Lane AD — CombatLetterbox / VisionStage 题签文案再收一刀")
print("=" * 68)
_vs_ad = open(_vs_path, encoding="utf-8").read() if os.path.isfile(_vs_path) else ""
_lb_ad = open(_lb_path, encoding="utf-8").read() if os.path.isfile(_lb_path) else ""
for bad in ("惊艳", "沉浸", "打造", "视觉盛宴", "离开展示", "立绘裱框"):
    if bad in _vs_ad or bad in _lb_ad:
        print(f"  ✗ 题签现代词回潮：{bad}")
        problems.append(f"题签现代词回潮:{bad}")
    else:
        print(f"  ✓ 无「{bad}」")
if 'HINT_ESC := "B　合上纪事"' in _vs_ad:
    print("  ✓ VisionStage Hint「B　合上纪事」")
else:
    print("  ✗ VisionStage Hint 未改「B　合上纪事」")
    problems.append("VisionStage Hint 未纪实")
if 'NOTE_PORTRAIT := "绢本立像　名册可核"' in _vs_ad:
    print("  ✓ VisionStage 旁注「绢本立像　名册可核」")
else:
    print("  ✗ VisionStage 旁注未改「绢本立像」")
    problems.append("VisionStage 旁注未纪实")
if 'SLIP_TITLE := "市舶纪事"' in _vs_ad and "市舶纪事" in _main_l:
    print("  ✓ 题签主名「市舶纪事」与岸带一致")
else:
    print("  ✗ 市舶纪事题签漂移")
    problems.append("市舶纪事题签漂移")
_ad_probe = os.path.join(ROOT, "tools", "qa_letterbox_copy_probe.gd")
if os.path.isfile(_ad_probe):
    print("  ✓ tools/qa_letterbox_copy_probe.gd 存在")
else:
    print("  ✗ 缺 qa_letterbox_copy_probe.gd")
    problems.append("缺 letterbox 截图探针")

# Lane Q：酒馆新闻墙 / 市井札薄
_tnw_path = os.path.join(ROOT, "scripts", "ui", "TavernNewsWall.gd")
_tnw = open(_tnw_path, encoding="utf-8").read() if os.path.isfile(_tnw_path) else ""
if not _tnw:
    print("  ✗ 缺 TavernNewsWall.gd")
    problems.append("缺 TavernNewsWall.gd")
elif "func mount" not in _tnw or "recent_news" not in _tnw or "paper_card" not in _tnw:
    print("  ✗ TavernNewsWall 未暴露 mount / recent_news / paper_card")
    problems.append("TavernNewsWall 契约不全")
else:
    print("  ✓ _TAVERN_NEWS_WALL.mount + recent_news + paper_card")
if "_TAVERN_NEWS_WALL.mount" not in main_src or "_setup_news_wall" not in main_src:
    print("  ✗ Main 未薄调 _TAVERN_NEWS_WALL.mount（_setup_news_wall）")
    problems.append("Main 未接 TavernNewsWall")
else:
    print("  ✓ Main._setup_news_wall → _TAVERN_NEWS_WALL.mount")
_tnw_probe = os.path.join(ROOT, "tools", "qa_tavern_news_wall_screenshots.gd")
if os.path.isfile(_tnw_probe):
    print("  ✓ tools/qa_tavern_news_wall_screenshots.gd 存在")
else:
    print("  ✗ 缺 qa_tavern_news_wall_screenshots.gd")
    problems.append("缺 tavern 截图探针")
for bad in ("惊艳", "沉浸", "打造", "视觉盛宴"):
    if bad in _tnw:
        print(f"  ✗ 酒馆墙文案回潮：{bad}")
        problems.append(f"酒馆墙文案回潮:{bad}")


print("=" * 68)
print("Lane Z1 — 船况面板 / 航海札记旁注纪实短标签")
print("=" * 68)
_sc_z1 = open(os.path.join(SCRIPTS, "SeaChart.gd"), encoding="utf-8").read()
_voy_z1 = open(os.path.join(SCRIPTS, "core", "Voyage.gd"), encoding="utf-8").read()
_main_z1 = read_main_src()

def _z1_visible(src: str) -> str:
    out = []
    for line in src.splitlines():
        code = line.split("#", 1)[0]
        i = 0
        while True:
            a = code.find('"', i)
            if a < 0:
                break
            b = a + 1
            while b < len(code):
                if code[b] == "\\":
                    b += 2
                    continue
                if code[b] == '"':
                    break
                b += 1
            else:
                break
            out.append(code[a:b + 1])
            i = b + 1
    return "\n".join(out)

_sc_vis = _z1_visible(_sc_z1)
_voy_vis = _z1_visible(_voy_z1)
_main_vis = _z1_visible(_main_z1)
if "[b]船队[/b]" in _sc_z1 and "行成" in _sc_z1 and ("委办已逾" in _sc_z1 or "委办 %d 日" in _sc_z1):
    print("  ✓ 船况段头「船队」+ 航行「行成」+ 顶匾委办短标")
else:
    print("  ✗ 船况短标契约不全（船队/行成/委办）")
    problems.append("船况短标契约不全")
for bad in ("十次约有八次", "逃走没被抢走货", "日速 ×", "今日截止", "已逾期", "[b]舰队[/b]"):
    if bad in _sc_vis:
        print(f"  ✗ SeaChart 可见文案回潮：{bad}")
        problems.append(f"SeaChart 回潮:{bad}")
    else:
        print(f"  ✓ SeaChart 无「{bad}」")
# 查的是 Voyage 全文件可见文案（lane cs11：原文案点名 order_blurb，口径其实是整份文件；不收窄——别的函数写出日速公式同样该红）
if "日速 ×" in _voy_vis:
    print("  ✗ Voyage 可见文案仍写日速公式（「日速 ×」，原在 order_blurb）")
    problems.append("Voyage 可见文案日速公式")
else:
    print("  ✓ Voyage 可见文案无日速公式（order_blurb 等全文件）")
if "限今日" in _main_z1 and "UiTheme.hex(UiTheme.CINNABAR)" in _main_z1 and 'color=#%s' in _main_z1:
    print("  ✓ Main 船籍簿委办短限日 + hex 色")
else:
    print("  ✗ Main 船籍簿委办短限日/色标未对齐")
    problems.append("Main 委办短标未对齐")
for bad in ("十次里大约八次", "逃走没被抢走货", "今日截止", "已逾期"):
    if bad in _main_vis:
        print(f"  ✗ Main 可见文案回潮：{bad}")
        problems.append(f"Main 回潮:{bad}")
    else:
        print(f"  ✓ Main 无「{bad}」")
_z1_probe = os.path.join(ROOT, "tools", "qa_voyage_status_probe.gd")
if os.path.isfile(_z1_probe):
    print("  ✓ tools/qa_voyage_status_probe.gd 存在")
else:
    print("  ✗ 缺 qa_voyage_status_probe.gd")
    problems.append("缺 voyage 截图探针")

print()
print("Lane Z3 — 伙伴草案预览浮页（F7 / CompanionPreview）")
_comp_path = os.path.join(SCRIPTS, "companions", "CompanionPreview.gd")
if os.path.isfile(_comp_path):
    print("  ✓ scripts/companions/CompanionPreview.gd 存在")
    _comp_src = open(_comp_path, encoding="utf-8").read()
else:
    print("  ✗ 缺 CompanionPreview.gd")
    problems.append("缺 CompanionPreview.gd")
    _comp_src = ""
_main_z3 = read_main_src()
if "KEY_F7" in _main_z3 and _has_func(_main_z3, "_toggle_companion_preview") and "_COMPANION_PREVIEW" in _main_z3:
    print("  ✓ Main F7 → CompanionPreview 开关")
else:
    print("  ✗ Main 未薄接入 CompanionPreview/F7")
    problems.append("Main 未接 CompanionPreview/F7")
if "草案预览" in _comp_src and "PREVIEW_IDS" in _comp_src and "招募" in _comp_src:
    print("  ✓ 草案预览题签 + 六人名单 + 非招募声明")
else:
    print("  ✗ CompanionPreview 契约文案不全")
    problems.append("CompanionPreview 契约不全")
# 禁招募入口
for bad in ("hire_crew", "招募确认", "月俸", "加入船队"):
    if bad in _comp_src:
        print(f"  ✗ CompanionPreview 混入招募玩法：{bad}")
        problems.append(f"CompanionPreview 招募玩法:{bad}")
    else:
        print(f"  ✓ 无「{bad}」")
_z3_probe = os.path.join(ROOT, "tools", "qa_companion_preview_screenshots.gd")
if os.path.isfile(_z3_probe):
    print("  ✓ tools/qa_companion_preview_screenshots.gd 存在")
else:
    print("  ✗ 缺 qa_companion_preview_screenshots.gd")
    problems.append("缺 companion 截图探针")

print()
print("=" * 68)
print("十三、按函数名取函数体（lane gd16 / cs9 / cs12：取不到判红）")
print("=" * 68)
_body_missed = sorted(k for k, found in _body_asks.items() if not found)
for _ln, _name in _body_missed:
    if _name.startswith("[node "):  # _node_block（lane cs12）
        print(f"  ✗ check_symbols.py:{_ln} 取场景节点块 {_name} 取不到（节点改名 / 删了 / 挪进子场景），这处断言在空转")
        problems.append(f"取不到场景节点块：{_name}（check_symbols.py:{_ln}）")
        continue
    print(f"  ✗ check_symbols.py:{_ln} 取函数体 {_name} 取不到（改名 / 删了 / 搬走没拼回），这处断言在空转")
    problems.append(f"取不到函数体：{_name}（check_symbols.py:{_ln}）")
if not _body_missed:
    _n_node = sum(1 for _ln, _name in _body_asks if _name.startswith("[node "))
    print(f"  ✓ _func_body / func_bodies().get / _locate_func 的 {len(_body_asks) - _n_node} 处按名取用都取到函数体"
          f"，_node_block 的 {_n_node} 处按名取用都取到场景节点块")

# 断言点名的函数须仍在（lane cs9：函数改名误绿）。按名取体之外，断言还会在字面量里点函数名：
# 反向断言（`"_sail_next_day(" not in body`、`any(tok in body for tok in ("add_fame", …))`）、find 定位锚
# （`body.find("_end_benches")` 取不到得 -1，「A 在 B 之后」照样成立）、存在性探查（`"func shore_door" in src`
# 会认到 shore_door_hover）。被点名的函数一改名，调用点跟着改，这些断言就空转——反向断言照样绿。
# 所以：NAMED_FUNCS 按 (文件, 名字) 登记——键是断言所指那支函数的定义文件，每个名字须在**该文件**仍有行首
# `[static ]func 名字(` 定义（改名 / 删了 / 挪到别的文件都判红，断言跟着改）。lane cs11：原先只查「scripts/ 下有无此定义」，
# finish / mount / advance_days 这类通用名在别的文件还有同名（Calendar.advance_days 之于 GameManager.advance_days），
# 断言所指那支改了名照样绿。scripts/Main.gd 按断言实际读的拼回源码（read_main_src，Main + MAIN_SPLITS）认：搬进拆出件、
# 拼回还读得到的不算挪走。
# 清单齐不齐由本脚本自扫——上面几类字面量里点到、当前确有定义的函数名都须登记（新写这类断言就得登记，漏登判红）；
# 自扫只到名字（字面量看不出指哪个文件），登在哪个文件下由登记的人按断言读的源码定。
# 本来就要「保持删除」的旧函数（`"func _add_sail_button" not in main_src`）没有定义，自扫不收，也不必登记。
NAMED_FUNCS = {
    "scripts/Main.gd": (
        "_add_guild_join_slip", "_add_leave_button", "_begin_benches", "_end_benches", "_fit_rank",
        "_guild_join_block", "_interior_lead", "_interior_title", "_lift_ledger", "_mount_status_strip",
        "_on_exam_sit", "_on_guild_join", "_on_upgrade", "_setup_guild", "_setup_news_wall", "_skill_rank",
        "load_scene", "play_transition", "show_choices", "update_status_panel",
    ),
    "scripts/GameManager.gd": (
        "advance_days", "discoveries_near",
    ),
    "scripts/GameState.gd": (
        "add_fame", "add_money", "finish", "has_flag", "has_found", "next_title", "recent_news",
        "report_discovery", "resolve_identity_1268", "set_flag", "spend_money", "title_duty_factor",
        "title_rank", "visit_port",
    ),
    "scripts/PirateShip.gd": (
        "combat_strength",
    ),
    "scripts/SeaChart.gd": (
        "_bearing_phrase", "_enter_battle", "_log_shook_pursuers", "_mount_condition", "_on_battle_result",
        "_on_event_continue", "_on_mutiny_bribe", "_on_mutiny_dismiss", "_on_mutiny_suppress", "_sail_next_day",
    ),
    "scripts/WorldMap.gd": (
        "_battle_player_sunk",
    ),
    "scripts/combat/CombatFx.gd": (
        "board_begin_subtitle", "sea_flee_ok_note", "sea_win_note",
    ),
    "scripts/core/Crew.gd": (
        "rank_word",
    ),
    "scripts/core/Economy.gd": (
        "invest", "invest_cost", "invest_edge", "investment_level", "price_at_rate",
    ),
    "scripts/core/Fleet.gd": (
        "armor_damage_reduction", "captain_power", "clear_cargo", "damage_each_ship", "damage_fleet",
        "hire_crew", "lose_cargo_ratio", "lose_crew_random", "mutiny_bribe_cost", "mutiny_ready",
        "resolve_mutiny", "ship_crew", "ship_crew_max", "ship_crew_min", "ship_crew_room", "total_durability",
        "upgrade_armor", "upgrade_sail",
    ),
    "scripts/core/SaveLoad.gd": (
        "_bak_path", "_harden_state", "_normalise_flags", "_normalise_ids", "_valid_flag_name", "has_save",
    ),
    "scripts/core/UiTheme.gd": (
        "paper_card", "plain_log", "shore_door", "style_button", "style_chip", "style_choice_button",
    ),
    "scripts/core/Voyage.gd": (
        "mutiny_event",
    ),
    "scripts/cutscene/Cinematics.gd": (
        "live",
    ),
    "scripts/cutscene/cs_kit.gd": (
        "is_headless",
    ),
    "scripts/ui/TavernNewsWall.gd": (
        "mount",
    ),
    "scripts/ui/UiTransition.gd": (
        "drydock_open", "drydock_seal", "drydock_title", "endgame_title", "prologue_open_title",
        "prologue_shore_title", "promote_open", "promote_title", "siege_title",
    ),
}
_NF_VIRTUAL = {"_ready", "_process", "_physics_process", "_input", "_unhandled_input", "_gui_input",
               "_notification", "_init", "_draw", "_enter_tree", "_exit_tree"}
_NF_LIT = r'"((?:[^"\\\n]|\\.)*)"'


def _nf_names(lit):
    """字面量里点到的函数名：`func X` / `static func X`、`X(`、整串就是标识符、`Obj.X` 收尾。"""
    out = set(re.findall(r'([A-Za-z_]\w*)\s*\(', lit)) | set(re.findall(r'\.([A-Za-z_]\w*)\s*$', lit))
    m = re.match(r'(?:static\s+)?func\s+([A-Za-z_]\w*)', lit)
    if m:
        out.add(m.group(1))
    if re.fullmatch(r'[A-Za-z_]\w*', lit):
        out.add(lit)
    return out


_NF_DEF = re.compile(r'^[ \t]*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(', re.M)
_nf_where = {}  # 函数名 -> 定义它的 scripts/ 文件（相对 ROOT）
for _dp, _dn, _fs in os.walk(SCRIPTS):
    for _fn in _fs:
        if _fn.endswith(".gd"):
            _rel = os.path.relpath(os.path.join(_dp, _fn), ROOT).replace(os.sep, "/")
            with open(os.path.join(_dp, _fn), encoding="utf-8") as f:
                for _n in set(_NF_DEF.findall(f.read())):
                    _nf_where.setdefault(_n, []).append(_rel)
_nf_defined = set(_nf_where)
_nf_seen = {}  # 函数名 -> 本脚本里点到它的行号
with open(os.path.abspath(__file__), encoding="utf-8") as f:
    _nf_self = f.read().split("\n")
for _ln_no, _ln in enumerate(_nf_self, 1):
    if _ln.lstrip().startswith("#"):
        continue
    _ms = list(re.finditer(_NF_LIT + r'\s+not\s+in\b', _ln))
    _ms += list(re.finditer(r'\.(?:find|rfind|count)\(\s*' + _NF_LIT, _ln))
    _ms += list(re.finditer(r'"((?:static )?func [A-Za-z_]\w*)"\s+(?:not\s+)?in\b', _ln))
    if re.search(r'\bany\(', _ln) or re.search(r'\bfor\s+\w+\s+in\s+\(', _ln):
        _ms += list(re.finditer(_NF_LIT, _ln))
    for _m in _ms:
        for _n in _nf_names(_m.group(1)):
            if _n in _nf_defined and _n not in _NF_VIRTUAL:
                _nf_seen.setdefault(_n, _ln_no)
_nf_pairs = [(rel, n) for rel, names in NAMED_FUNCS.items() for n in names]
_nf_listed = {n for _, n in _nf_pairs}
_nf_bad = []
for _rel in NAMED_FUNCS:
    _path = os.path.join(ROOT, _rel)
    if not os.path.isfile(_path):
        print(f"  ✗ NAMED_FUNCS 登记的文件 {_rel} 不存在（改名 / 挪目录？登记的函数跟着挪到新路径下）")
        problems.append(f"NAMED_FUNCS 文件不存在：{_rel}")
        _nf_bad.append(_rel)
        continue
    if _rel == "scripts/Main.gd":
        _text = read_main_src()  # 断言读的是拼回的 Main（Main + MAIN_SPLITS）
    else:
        with open(_path, encoding="utf-8") as f:
            _text = f.read()
    _here = set(_NF_DEF.findall(_text))
    for _n in NAMED_FUNCS[_rel]:
        if _n in _here:
            continue
        _else = [r for r in _nf_where.get(_n, []) if r != _rel]
        if _else:
            print(f"  ✗ 断言点名的函数 {_n} 在 {_rel} 已无定义，别处还有同名（{'、'.join(_else)}）——挪走 / 改名了？"
                  f"点到它的反向断言 / find 锚在空转；真挪了就把断言读的源码和 NAMED_FUNCS 登记一起改")
        else:
            print(f"  ✗ 断言点名的函数 {_n} 在 {_rel} 已无定义（scripts/ 下也没有；改名 / 删了？"
                  f"点到它的反向断言 / find 锚在空转，断言跟着改，NAMED_FUNCS 同步）")
        problems.append(f"断言点名的函数已无定义：{_rel} · {_n}")
        _nf_bad.append((_rel, _n))
_nf_unlisted = sorted(n for n in _nf_seen if n not in _nf_listed)
for _n in _nf_unlisted:
    print(f"  ✗ check_symbols.py:{_nf_seen[_n]} 的断言点到函数 {_n}，没登记进 NAMED_FUNCS"
          f"（登在断言所指那支的定义文件下，现定义于 {'、'.join(_nf_where[_n])}；登记后改名 / 挪走才会判红）")
    problems.append(f"NAMED_FUNCS 漏登：{_n}")
if not _nf_bad and not _nf_unlisted:
    print(f"  ✓ 断言点名的 {len(_nf_pairs)} 支函数都还在登记的文件里（{len(NAMED_FUNCS)} 个文件，按 (文件, 名字) 认；"
          f"反向断言 / find 锚 / 存在性探查；NAMED_FUNCS 与本脚本自扫一致）")

print()
print()
print("=" * 68)
if problems:
    print(f"结果：{len(problems)} 项问题")
    for p in problems:
        print("   ✗", p)
    sys.exit(1)
print("结果：全部通过")
