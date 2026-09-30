#!/usr/bin/env python3
"""check_symbols 反向断言空转的变异对照（lane auditfix3 / auditfix5）：_node_block 记账（lane cs12）与 NAMED_FUNCS 按 (文件, 名字)
认（lane cs11）这两道护栏，各有一条真的反向断言、一个真能落上的变异，证明「没有护栏时缺陷在、门禁绿」。

  python3 tools/check_symbols_mutants.py          # 跑全部变异；有问题退 1，环境问题（无 git / 建不了 worktree）退 2
  python3 tools/check_symbols_mutants.py --json   # 机读（同 docs/GATES.md §二）
  python3 tools/check_symbols_mutants.py --landing  # 只跑落点预检（不建 worktree、不跑 check_symbols，约 1 s）；check_symbols 十四节每次调它

为什么：独立审计 audit1 判 cs12 / cs11「半实」——_node_block 两处调用都是正向断言，改节点名正向断言先红；
(文件, 名字) 只有 advance_days 一支同名，改名后赴试 / 誊录的正向断言先红：护栏在现状下没有能单独触发的实例。
护栏只在「反向断言 + 改名」时才是唯一的红：反向断言（`"X" not in 块`）取的东西一改名就空转，照样绿。
所以这里各立一支：
  · _node_block：check_symbols「底图 / 外层横排 / 中区开场不收起」（Background / HBoxContainer / CenterArea 块里不许
    `visible = false`）。变异：全仓把 CenterArea 改名 CenterStage、只有这条反向断言没跟（它不红，没人想得起），再把中区收起。
  · NAMED_FUNCS：船屋「`"advance_days" not in yard_fn`」（换坞不推日子）。变异：全仓把 GameManager.advance_days 改名
    pass_days（Calendar.advance_days 不动），check_symbols 里只改跟着红的正向断言、把 pass_days 补登进 NAMED_FUNCS，
    两行反向断言没跟；再让船屋推一天。
每支都有五格：缺陷本身判红 → 改名 + 缺陷（现行）只有护栏那一行红 → 同上但护栏退回旧口径（cs12 前 / cs11 前）rc=0
（这就是空转）→ 改名跟全 + 缺陷由反向断言本身判红 → 改名跟全、无缺陷 rc=0（变异本身不带出别的红）。
另两格（F6 / F7）守 NAMED_FUNCS 自扫：单行 `if …"X(" in 体:` 下一行打 ✗ 的分支形反向断言原先不在自扫形状里，
新写一条不登记照样绿（日后 X 改名即空转、无人报）；现漏登判红，退回旧扫法 rc=0。
lane auditfix5 加三组：
  · F2c / F3c：F2 之后按红字把 advance_days 改登到还有定义的 Calendar.gd 下（auditfix3 @1494633 实测 rc=0 的那一手）：
    现行由 NF 标注判红（断言行标明 GameManager.advance_days，登记却在 Calendar.gd），不查标注 rc=0。
  · S0–S9：分支形七形（条件折多行 / ✗ 在 else 支 / ✗ 不在紧下一行 / match / match 守卫 / any 元组折行 / _calls 与
    re.search 当条件）逐形漏登判红；七形一起退回 auditfix3 口径（单行条件 + 下一行 ✗）rc=0；S0 证明旧口径补丁如实还原。
  · T1–T6：NF 标注（同名多处定义的名字断言行须标 `# NF: 接收者.名字`）——没标 / 日后出现同名各有现行红、不查 rc=0 一对，
    另有接收者写错、标错行两格。
做法：把当前工作树的已跟踪文件（含未提交改动，`git stash create`，不动 stash 列表）检出到临时 worktree，逐格施变异、
跑整道 `python3 tools/check_symbols.py`，比 rc 与「  ✗」行：期望的每条都得出现，期望外的一条也不许有。
判红：任一格 rc 或 ✗ 行与期望不符；变异 / 旧口径补丁没落上（替换处数不对，说明源码改了、这支变异该跟着改）。
往函数体里插行的变异按当前源码找真身（lane cs24，locate_body）：给的是 check_symbols 读的那支（Main.gd 的 _setup_shipyard），
取到一行转发（func_body.forward_of，与十三节同一判据）就顺 preload 常量 / 同文件别名跟到真身再插；找不到 / 同名多处 /
转发目标认不出文件 → 变异没落上、判红。lane main10 把 _setup_shipyard 拆去 ShipyardPage 后，原先按签名行直插 Main 仍「落上 1 处」
——插进的是一行转发，F1–F4 连带一串转发判据的红（61e17bf–5d5920c 七笔全红，auditfix5 c020050 手改靶子才绿）；跟转发后
下一刀再拆也不用手改。「零、靶子定位自检」每次先跑：临时目录里的合成样本逐格判落点（旧定位法落在转发上 / 新定位法落在真身），
不跑 check_symbols、不要 worktree。
只读主树：临时 worktree 跑完即删（`git worktree remove --force`）。一格 2–4 s，全套 31 格约一分钟（10 路并发负载下实测 94 s）。

生命周期（lane cs27，auditfix7 W8）：全量要 git worktree、一分钟上下，升不了必跑（GATES §五.2），仍是 lane 档；可 W8 那次
（aec1ea6 07:37 落地，main10 61e17bf 07:48 拆走 _setup_shipyard 即红，到 auditfix5 c020050 08:48 才绿，first-parent 7 笔）红因
是「靶子漂了、变异没落上 / 落歪」，这一类不用跑 check_symbols 就判得出。所以另立 `landing()` 落点预检：内存里（Mem 叠层，读主树
工作树、写不落盘）把 CASES 每格的变异 / 旧口径补丁逐格施一遍、只看落不落得上（替换处数、插行靶子的真身），外加「零、」K0–K10；
挂在必跑的 check_symbols 十四节，一键跑每次都跑到。靶子漂了当场在挪靶子那一笔的一键跑里红，不再等下一个动护栏的人。
全量才判得出的（期望 ✗ 字样、rc、空转对照）仍靠 lane 档的 when（GATES §三.23「谁在什么时候跑它」）。
全量跑时 check_symbols 在变异过的 worktree 里跑，十四节必然红（变异本身让别的格落不上），所以 _run_case 传 `--no-mutants-landing`
关掉它——这个开关只给本脚本用，一键跑命令里不许带（gates_md 逐条比一键跑命令）。
"""
import os, re, shutil, subprocess, sys, tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if __name__ == "__main__" and "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；被 check_symbols import（十四节）时不接管
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

sys.path.insert(0, TOOLS)
from func_body import forward_of  # noqa: E402  判「一行转发」与 check_symbols 十三节同一份（lane cs17 / gd23）

SYM = "tools/check_symbols.py"
SELF = "tools/check_symbols_mutants.py"
RENAME_DIRS = ("scenes", "scripts", "tools")


class Miss(Exception):
    """变异 / 补丁没落上：替换处数与期望不符。"""


def _git(*args, cwd=ROOT):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


class Mem:
    """内存工作树（lane cs27 落点预检）：读先看本格写过的，再落到 base 目录（主树工作树，读一次缓存）；写只进 dict、不落盘。
    base=None 是空树（「零、」合成样本用）。"""
    _disk = {}

    def __init__(self, base, files=()):
        self.base, self.over, self.files = base, {}, files

    def read(self, rel):
        if rel in self.over:
            return self.over[rel]
        if self.base is None:
            raise FileNotFoundError(rel)
        key = os.path.join(self.base, rel)
        if key not in Mem._disk:
            with open(key, encoding="utf-8") as f:
                Mem._disk[key] = f.read()
        return Mem._disk[key]


def _read(wt, rel):
    if isinstance(wt, Mem):
        return wt.read(rel)
    with open(os.path.join(wt, rel), encoding="utf-8") as f:
        return f.read()


def _write(wt, rel, text):
    if isinstance(wt, Mem):
        wt.over[rel] = text
        return
    with open(os.path.join(wt, rel), "w", encoding="utf-8") as f:
        f.write(text)


def sub(wt, rel, pattern, repl, n=1):
    """rel 里按正则替换，须恰好 n 处（n=None：至少 1 处）。文件不在（改名 / 挪走）同算没落上。"""
    try:
        text = _read(wt, rel)
    except OSError:
        raise Miss(f"{rel} 不在（改名 / 挪走了？）")
    new, k = re.subn(pattern, repl, text, flags=re.M)
    if (n is None and k == 0) or (n is not None and k != n):
        raise Miss(f"{rel} 里 {pattern!r} 替换了 {k} 处，应 {'≥1' if n is None else n} 处")
    _write(wt, rel, new)


_HAS = {}


def _has(rx, text):
    """rx 在 text 里有无命中；按 (模式, 原文) 记住——预检各格读的是同一份主树原文（同一个 str 对象），不必每格重扫。"""
    key = (rx.pattern, text)
    if key not in _HAS:
        _HAS[key] = rx.search(text) is not None
    return _HAS[key]


def rename(wt, pattern, repl, skip=(), lines=None):
    """全仓（scenes / scripts / tools 已跟踪文件）改名；skip 的文件不动；lines(path) 给出只改哪些行的判据。"""
    files = wt.files if isinstance(wt, Mem) else _git("ls-files", *RENAME_DIRS, cwd=wt).stdout.split()
    hit, rx = 0, re.compile(pattern)
    for rel in files:
        if rel in skip or not rel.endswith((".gd", ".tscn", ".py", ".sh")):
            continue
        text = _read(wt, rel)
        if not _has(rx, text):  # 整份没有一处命中，逐行也不会命中（lane cs27：预检每格都扫全仓，先整份筛）
            continue
        keep = lines(rel) if lines else None
        out = []
        for ln in text.split("\n"):
            if keep is None or keep(ln):
                ln, k = re.subn(pattern, repl, ln)
                hit += k
            out.append(ln)
        new = "\n".join(out)
        if new != text:
            _write(wt, rel, new)
    if not hit:
        raise Miss(f"全仓改名 {pattern!r} 一处没落上")


def _func_re(name):
    return re.compile(rf"^(?:static\s+)?func\s+{re.escape(name)}\s*\(", re.M)


def _sig_end(text, at):
    """at = 签名左括号之后；给签名行（可折行）行尾换行之后的偏移。签名同行带函数体的（`func x(): pass`）插不进，给 None。"""
    depth, i = 1, at
    while i < len(text) and depth:
        depth += {"(": 1, ")": -1}.get(text[i], 0)
        i += 1
    colon, nl = text.find(":", i), text.find("\n", i)
    if colon < 0 or nl < 0 or colon > nl or re.sub(r"#.*", "", text[colon + 1:nl]).strip():
        return None
    return nl + 1


def locate_body(wt, rel, name, hops=4):
    """按当前源码找 rel 里 name 的真身（lane cs24）：签名须恰好一处；体是一行转发（forward_of）就跟——`_K.fn(…)` 顺
    `const _K := preload("res://…")` 到拆出件的 fn、不带点号的是同文件别名。给 (真身文件, 函数名, 插行偏移, 路径)；落不上抛 Miss。"""
    trail = []
    for _ in range(hops):
        try:
            text = _read(wt, rel)
        except OSError:
            raise Miss(f"{' → '.join(trail + [rel])}：文件不在")
        heads = list(_func_re(name).finditer(text))
        where = f"{rel}:{text.count(chr(10), 0, heads[0].start()) + 1} {name}" if len(heads) == 1 else f"{rel} {name}"
        trail.append(where)
        if len(heads) != 1:
            raise Miss(f"{' → '.join(trail)}：func {name}( 有 {len(heads)} 处，应 1 处")
        body = re.compile(_func_re(name).pattern + r".*?(?=\n(?:static\s+)?func\s|\Z)", re.M | re.S).search(text).group(0)
        fwd = forward_of(body, text)
        if not fwd:
            at = _sig_end(text, heads[0].end())
            if at is None:
                raise Miss(f"{' → '.join(trail)}：签名认不出行尾 / 同行带函数体，插不进")
            return rel, name, at, trail
        recv, _, fn = fwd.rpartition(".")
        if recv:
            pm = re.search(rf'^const\s+{re.escape(recv)}\b[^=\n]*=\s*preload\("res://([^"]+)"\)', text, re.M)
            if not pm:
                raise Miss(f"{' → '.join(trail)}：是一行转发到 {fwd}，{recv} 不是 preload 常量、认不出真身在哪个文件")
            rel = pm.group(1)
        name = fn
    raise Miss(f"{' → '.join(trail)}：转发超过 {hops} 层")


LANDED = {}  # (文件, 函数名) -> 真身路径（「三、靶子落点」打印）


def inject(wt, rel, name, line):
    """往 rel 里 name 的真身（locate_body）函数体第一行前插 `\t<line>`。"""
    got, fn, at, trail = locate_body(wt, rel, name)
    LANDED[(rel, name)] = trail
    text = _read(wt, got)
    _write(wt, got, text[:at] + "\t" + line + "\n" + text[at:])


# ---- _node_block 一支（lane cs12 护栏） ----------------------------------------------------------------------
def n_hide(name):
    return lambda wt: sub(wt, "scenes/Main.tscn", r'^(\[node name="%s"[^\n]*\n)' % name, r"\1visible = false\n")


def n_rename_all_but_assert(wt):
    rename(wt, r"\bCenterArea\b", "CenterStage", skip=(SYM, SELF))


def n_rename_all(wt):
    rename(wt, r"\bCenterArea\b", "CenterStage", skip=(SELF,))


def n_pre_cs12(wt):
    # cs12 前：_node_block 取不到只给 ""，不记账
    sub(wt, SYM, r'^    _body_ask\(token \+ "\]", at >= 0\)\n', "")


# ---- NAMED_FUNCS 一支（lane cs11 护栏） ----------------------------------------------------------------------
_ADV = r"(?<!Calendar\.)\badvance_days\b"


def f_yard_step(fn):
    # 靶子写 check_symbols 读的那支（yard_fn = main_src 的 _setup_shipyard）；lane main10 起 Main 只留一行转发、真身在
    # ShipyardPage.setup_shipyard，locate_body 顺转发跟过去（往转发里插一行，转发判据先红——61e17bf–5d5920c 就是这么红的）
    return lambda wt: inject(wt, "scripts/Main.gd", "_setup_shipyard", "GameManager.%s(1)" % fn)


def f_rename_fix_reds(wt):
    # 源码全改；check_symbols 里跟着红的正向断言（赴试 / 誊录 / 发现调查的调用、定位、计数）都改，只有两行
    # `"advance_days" not in` 反向断言不红、没跟，NAMED_FUNCS 登记行不动；自扫报「漏登 pass_days」→ 补登在 GameManager.gd 下
    rename(wt, _ADV, "pass_days", skip=(SELF, "scripts/core/Calendar.gd"),
           lines=lambda rel: (lambda ln: not ln.lstrip().startswith("#") and '"advance_days" not in' not in ln
                              and not ln.startswith('        "advance_days", ')) if rel == SYM else None)
    sub(wt, SYM, r'^(        "advance_days", "discoveries_near",)$', r'\1 "pass_days",')


def f_rename_all(wt):
    rename(wt, _ADV, "pass_days", skip=(SELF, "scripts/core/Calendar.gd"))


def f_pre_cs11(wt):
    # cs11 前：名字在 scripts/ 下任一文件有定义就算
    sub(wt, SYM, r"^    _here = set\(_NF_DEF\.findall\(_text\)\)$", "    _here = _nf_defined")


def f_branch_assert(wt):
    # 新写一条分支形反向断言（船屋不报季风），点到的 _monsoon_short 没登记
    sub(wt, SYM, r'^(    problems\.append\("坞位一艘未接上"\)\n)',
        r'\1if "_monsoon_short(" in yard_fn:\n    print("  ✗ 船屋报季风")\n    problems.append("船屋报季风")\n')


_AST_SCAN = r"^for _ln_no, _ns in sorted\(_nf_branch_sites\(.*# 分支形反向断言（lane auditfix5）\n    _nf_take\(_ln_no, _ns\)\n"


def f_pre_branch_scan(wt):
    # auditfix3 前：自扫不收分支形反向断言
    sub(wt, SYM, _AST_SCAN, "")


def f_af3_branch_scan(wt):
    # auditfix5 前（auditfix3 口径）：分支形只认「单行 `if / elif …"X" in …:`、下一行就打 ✗」
    sub(wt, SYM, _AST_SCAN, "")
    sub(wt, SYM, r"^(    for _m in _ms:\n        _nf_take\(_ln_no, _nf_names\(_m\.group\(1\)\)\)\n)",
        lambda m: ("    if re.match(r'\\s*(?:el)?if\\b.*:\\s*$', _ln) and _ln_no < len(_nf_self) and \"✗\" in _nf_self[_ln_no]:\n"
                   "        _ms += list(re.finditer(_NF_LIT + r'\\s+in\\b', _ln))\n") + m.group(1))


# 分支形各形状（lane auditfix5）：都点到 _seal_mark（只 Main 一处定义、未登记；船屋两支里本来没有），插在「坞位一艘」之后
_BRANCH = {
    "multiline": ('if (\n    "_seal_mark(" in yard_fn\n    or "_seal_mark(" in switch_fn\n):\n'
                  '    print("  ✗ 船屋盖了朱印")\n    problems.append("船屋盖印")\n'),
    "else": ('if not ("_seal_mark(" in yard_fn):\n    print("  ✓ 船屋不盖印")\nelse:\n'
             '    print("  ✗ 船屋盖了朱印")\n    problems.append("船屋盖印")\n'),
    "later": ('if "_seal_mark(" in yard_fn:\n    _why = "船屋盖了朱印"\n    print(f"  ✗ {_why}")\n'
              '    problems.append(_why)\n'),
    "match": ('match "_seal_mark(" in yard_fn:\n    case True:\n        print("  ✗ 船屋盖了朱印")\n'
              '        problems.append("船屋盖印")\n'),
    "guard": ('match yard_fn:\n    case _ if "_seal_mark(" in yard_fn:\n        print("  ✗ 船屋盖了朱印")\n'
              '        problems.append("船屋盖印")\n'),
    "anyfold": ('if any(tok in yard_fn for tok in (\n    "_seal_mark(",\n)):\n'
                '    print("  ✗ 船屋盖了朱印")\n    problems.append("船屋盖印")\n'),
    "probe": ('if _calls(yard_fn, "_seal_mark") or re.search(r"\\b_seal_mark\\(", switch_fn):\n'
              '    print("  ✗ 船屋盖了朱印")\n    problems.append("船屋盖印")\n'),
}


def f_branch(*kinds):
    return lambda wt: sub(wt, SYM, r'^(    problems\.append\("坞位一艘未接上"\)\n)',
                          lambda m: m.group(1) + "".join(_BRANCH[k] for k in kinds))


# ---- NF 标注（lane auditfix5：同名多处定义须在断言行标明指哪支） --------------------------------------------------
def f_move_reg_calendar(wt):
    # F2 之后「按红字把 advance_days 改登到还有定义的 Calendar.gd 下」——auditfix3 @1494633 实测 rc=0 的那一手
    sub(wt, SYM, r'^        "advance_days", "discoveries_near", "pass_days",$',
        '        "discoveries_near", "pass_days",\n    ),\n    "scripts/core/Calendar.gd": (\n        "advance_days",')


def f_pre_af5_tag(wt):
    # auditfix5 前：不查 NF 标注
    sub(wt, SYM, r"^_nf_tag_bad = _nf_tag_check\(\)", "_nf_tag_bad = []")


def f_untag_yard(wt):
    # 新写 / 挪动的断言没标：船屋那行的标注掉了
    sub(wt, SYM, r'^(    and "advance_days" not in yard_fn)  # NF: GameManager\.advance_days$', r"\1")


def f_new_homonym(wt):
    # 日后别的文件也定义了同名函数：Economy 加一支 record_discovery，simulate_run 那条 `any(tok in sim_src …)` 反向断言没标
    sub(wt, "scripts/core/Economy.gd", r"\Z", "\n\nfunc record_discovery() -> void:\n\tpass\n")


def f_bad_recv(wt):
    sub(wt, SYM, r'^(    and "advance_days" not in switch_fn  # NF: )GameManager(\.advance_days)$', r"\1GameManagr\2")


def f_stale_tag(wt):
    sub(wt, SYM, r'^(yard_fn = _func_body\(main_src, "_setup_shipyard"\))$', r"\1  # NF: GameManager.advance_days")


NODE_MISS = '取场景节点块 [node name="CenterArea"] 取不到'
NF_MOVED = "断言点名的函数 advance_days 在 scripts/GameManager.gd 已无定义，别处还有同名（scripts/core/Calendar.gd）"
NF_WRONG = "的断言标明指 scripts/GameManager.gd 的 advance_days，NAMED_FUNCS 却登在 scripts/core/Calendar.gd"
NF_UNTAGGED = "的断言点到同名多处定义的函数 advance_days（scripts/GameManager.gd、scripts/core/Calendar.gd）"
NF_HOMONYM = "的断言点到同名多处定义的函数 record_discovery（scripts/GameState.gd、scripts/core/Economy.gd）"
NF_BADRECV = "的 NF 标注 GameManagr.advance_days 认不出文件"
SEAL = "的断言点到函数 _seal_mark，没登记进 NAMED_FUNCS"
# (组, 编号, 说明, 变异, 期望 rc, 期望 ✗ 行须含的字样)
CASES = [
    ("—", "B0", "基线（不变异）", [], 0, []),
    ("_node_block", "N1", "缺陷：中区 CenterArea 开场收起", [n_hide("CenterArea")], 1,
     ["Main.tscn 开场收起了 CenterArea"]),
    ("_node_block", "N2", "改名 CenterArea→CenterStage（反向断言没跟）+ 缺陷，现行",
     [n_rename_all_but_assert, n_hide("CenterStage")], 1, [NODE_MISS]),
    ("_node_block", "N3", "同 N2，_node_block 退回 cs12 前（不记账）",
     [n_rename_all_but_assert, n_hide("CenterStage"), n_pre_cs12], 0, []),
    ("_node_block", "N4", "改名跟全（反向断言也改）+ 缺陷", [n_rename_all, n_hide("CenterStage")], 1,
     ["Main.tscn 开场收起了 CenterStage"]),
    ("_node_block", "N5", "改名跟全、无缺陷", [n_rename_all], 0, []),
    ("NAMED_FUNCS", "F1", "缺陷：船屋 _setup_shipyard 推一天", [f_yard_step("advance_days")], 1, ["坞位一艘未接上"]),
    ("NAMED_FUNCS", "F2", "改名 GameManager.advance_days→pass_days（只修弹红的正向断言、补登 pass_days）+ 缺陷，现行",
     [f_rename_fix_reds, f_yard_step("pass_days")], 1, [NF_MOVED]),
    ("NAMED_FUNCS", "F3", "同 F2，NAMED_FUNCS 退回 cs11 前（scripts/ 下有定义就算）",
     [f_rename_fix_reds, f_yard_step("pass_days"), f_pre_cs11], 0, []),
    ("NAMED_FUNCS", "F4", "改名跟全（反向断言与登记也改）+ 缺陷", [f_rename_all, f_yard_step("pass_days")], 1,
     ["坞位一艘未接上"]),
    ("NAMED_FUNCS", "F5", "改名跟全、无缺陷", [f_rename_all], 0, []),
    ("NAMED_FUNCS", "F6", "新写分支形反向断言 `if \"_monsoon_short(\" in yard_fn:` 没登记，现行", [f_branch_assert], 1,
     ["的断言点到函数 _monsoon_short，没登记进 NAMED_FUNCS"]),
    ("NAMED_FUNCS", "F7", "同 F6，自扫退回 auditfix3 前（不收分支形）", [f_branch_assert, f_pre_branch_scan], 0, []),
    ("NAMED_FUNCS", "F2c", "同 F2，再按红字把 advance_days 改登到 Calendar.gd 下，现行", [f_rename_fix_reds,
     f_yard_step("pass_days"), f_move_reg_calendar], 1, [NF_WRONG]),
    ("NAMED_FUNCS", "F3c", "同 F2c，不查 NF 标注（auditfix5 前；auditfix3 @1494633 实测的缺口）", [f_rename_fix_reds,
     f_yard_step("pass_days"), f_move_reg_calendar, f_pre_af5_tag], 0, []),
    ("分支形", "S0", "F6 那条单行分支形，分支形退回 auditfix3 口径（旧口径本来收得到：补丁如实还原）",
     [f_branch_assert, f_af3_branch_scan], 1, ["的断言点到函数 _monsoon_short，没登记进 NAMED_FUNCS"]),
    ("分支形", "S1", "条件折成多行 `if (\\n \"X(\" in 体 … \\n):`", [f_branch("multiline")], 1, [SEAL]),
    ("分支形", "S2", "✗ 在 else 支 `if not (\"X(\" in 体): ✓ else: ✗`", [f_branch("else")], 1, [SEAL]),
    ("分支形", "S3", "✗ 不在紧下一行（先起变量、f 串打 ✗）", [f_branch("later")], 1, [SEAL]),
    ("分支形", "S4", "match 分支 `match \"X(\" in 体: case True: ✗`", [f_branch("match")], 1, [SEAL]),
    ("分支形", "S5", "match 守卫 `case _ if \"X(\" in 体: ✗`", [f_branch("guard")], 1, [SEAL]),
    ("分支形", "S6", "`any(t in 体 for t in (\\n \"X(\",\\n))` 折行", [f_branch("anyfold")], 1, [SEAL]),
    ("分支形", "S7", "`_calls(体, \"X\")` / `re.search(r\"\\bX\\(\", 体)` 当条件", [f_branch("probe")], 1, [SEAL]),
    ("分支形", "S8", "S1–S7 七形一起、现行", [f_branch(*_BRANCH)], 1, [SEAL]),
    ("分支形", "S9", "同 S8，分支形退回 auditfix3 口径（单行条件 + 下一行 ✗）", [f_branch(*_BRANCH), f_af3_branch_scan], 0,
     []),
    ("NF 标注", "T1", "同名多处定义的 advance_days，船屋那行标注掉了，现行", [f_untag_yard], 1, [NF_UNTAGGED]),
    ("NF 标注", "T2", "同 T1，不查 NF 标注（auditfix5 前）", [f_untag_yard, f_pre_af5_tag], 0, []),
    ("NF 标注", "T3", "日后别处也定义 record_discovery（simulate_run 那条反向断言没标），现行", [f_new_homonym], 1, [NF_HOMONYM]),
    ("NF 标注", "T4", "同 T3，不查 NF 标注（auditfix5 前）", [f_new_homonym, f_pre_af5_tag], 0, []),
    ("NF 标注", "T5", "标注的接收者写错（GameManagr）", [f_bad_recv], 1, [NF_BADRECV, NF_UNTAGGED]),
    ("NF 标注", "T6", "标注写在没点到这个名字的行上", [f_stale_tag], 1, ["的 NF 标注 GameManager.advance_days：这一行自扫没点到"]),
]
# 空转对照：旧口径那格 rc=0、现行那格 rc=1，两格同一个变异
_IDLE = "反向断言空转，缺陷在、门禁绿"
_UNREG = "新反向断言漏登照样绿，日后改名即空转"
PAIRS = [("_node_block（lane cs12）", "N3", "N2", _IDLE), ("NAMED_FUNCS (文件, 名字)（lane cs11）", "F3", "F2", _IDLE),
         ("NAMED_FUNCS 自扫分支形（lane auditfix3）", "F7", "F6", _UNREG),
         ("NAMED_FUNCS 错登同名另一支（lane auditfix5）", "F3c", "F2c", "登到还有定义的 Calendar.gd 下即绿，" + _IDLE),
         ("NAMED_FUNCS 自扫分支形七形（lane auditfix5）", "S9", "S8", "多行 / else / match / 折行 any / 探查函数 七形全漏，" + _UNREG),
         ("NF 标注：同名多处须标明（lane auditfix5）", "T2", "T1", "没标照样绿，登在哪个文件无从判"),
         ("NF 标注：日后出现同名（lane auditfix5）", "T4", "T3", "新同名一出现，原先不含糊的字面量就含糊了，照样绿")]


# ---- 零、靶子定位自检（lane cs24）：合成样本，不跑 check_symbols、不要 worktree --------------------------------------
_DRILL_FILES = {
    "scripts/Main.gd": (
        'extends Control\nconst _P := preload("res://scripts/ui/P.gd")\nconst _TINT := {"a": 1}\n\n'
        "func _a(x: int) -> void:\n\t_P.a(self, x)\n\n"
        "func _b() -> void:\n\t_b_real()\n\nfunc _b_real() -> void:\n\tpass\n\n"
        "func _c(x: int) -> void:\n\t_Q.c(self, x)\n\n"
        "func _d(x: int) -> void:\n\t_P.d2(self, x)\n\n"
        "func _e(x: int) -> void:\n\tGameManager.e(x)\n\n"
        "func _f(x: int) -> void:\n\t_P.gone(self, x)\n\n"
        "func _g() -> void:\n\tpass\n\nfunc _g() -> void:\n\tpass\n\n"
        "func _h(\n\tx: int,\n\ty: int\n) -> void:  # 签名折行\n\t_P.h(self, x, y)\n\n"
        "func _i() -> void: pass\n"),
    "scripts/ui/P.gd": (
        'const _R := preload("res://scripts/ui/R.gd")\n\n'
        "static func a(main: Control, x: int) -> void:\n\tprint(x)\n\n"
        "static func d2(main: Control, x: int) -> void:\n\t_R.d3(main, x)\n\n"
        "static func h(main: Control, x: int, y: int) -> void:\n\tprint(x + y)\n"),
    "scripts/ui/R.gd": "static func d3(main: Control, x: int) -> void:\n\tprint(x)\n",
}
# (编号, 说明, Main.gd 里的函数名, 期望落点 (文件, 函数名) / None = 须判「变异没落上」且报错含该字样)
DRILL = [
    ("K1", "一行转发 `_P.a(self, x)` → 拆出件", "_a", ("scripts/ui/P.gd", "a"), None),
    ("K2", "拆出件再转发一层 `_R.d3(main, x)`", "_d", ("scripts/ui/R.gd", "d3"), None),
    ("K3", "同文件别名 `_b_real()`", "_b", ("scripts/Main.gd", "_b_real"), None),
    ("K4", "签名折行的转发", "_h", ("scripts/ui/P.gd", "h"), None),
    ("K5", "转发到 `_Q.c`，_Q 不是 preload 常量", "_c", None, "不是 preload 常量"),
    ("K6", "转发到 autoload `GameManager.e(x)`", "_e", None, "不是 preload 常量"),
    ("K7", "拆出件里没有转发目标", "_f", None, "func gone( 有 0 处"),
    ("K8", "同名两处定义", "_g", None, "func _g( 有 2 处"),
    ("K9", "函数不在", "_nope", None, "func _nope( 有 0 处"),
    ("K10", "签名同行带函数体", "_i", None, "插不进"),
]


def drill(root, quiet=False, tag=""):
    """给 problems 条目列表（quiet：✓ 行不印、✗ 行前加 tag，落点预检用）。K0：旧定位法（按签名行直插，c020050 前 f_yard_step 的写法）落上 1 处、落的却是一行转发。"""
    for rel, text in _DRILL_FILES.items():
        if not isinstance(root, Mem):
            os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
        _write(root, rel, text)
    bad = []
    text = _read(root, "scripts/Main.gd")
    k = len(re.findall(r"^func _a\(x: int\) -> void:\n", text, re.M))
    body = re.search(r"^func _a\(.*?(?=\n(?:static\s+)?func\s|\Z)", text, re.M | re.S).group(0)
    if k == 1 and forward_of(body, text):
        quiet or print(f"  ✓ K0 旧定位法（按签名行直插 Main.gd _a）：落上 {k} 处——落的是一行转发 {forward_of(body, text)}（61e17bf–5d5920c 的形状）")
    else:
        print(f"  ✗ {tag}K0 合成样本没复现旧形状（签名 {k} 处、转发 {forward_of(body, text)!r}）")
        bad.append("K0 合成样本失效")
    for cid, what, name, want, why in DRILL:
        try:
            got, fn, at, trail = locate_body(root, "scripts/Main.gd", name)
        except Miss as e:
            if want is None and why in str(e):
                quiet or print(f"  ✓ {cid} {what}：变异没落上（{e}）")
            else:
                print(f"  ✗ {tag}{cid} {what}：期望落在 {want}，实得没落上——{e}")
                bad.append(f"{cid} 靶子定位与期望不符")
            continue
        src = _read(root, got)
        ok = want == (got, fn) and _func_re(fn).search(src[:at]) and not src[at:].startswith(("func", "static func"))
        if ok:
            quiet or print(f"  ✓ {cid} {what}：落在 {' → '.join(trail)}")
        else:
            print(f"  ✗ {tag}{cid} {what}：期望 {'没落上' if want is None else want}，实得落在 {' → '.join(trail)}")
            bad.append(f"{cid} 靶子定位与期望不符")
    return bad


LANDING_OFF = "--no-mutants-landing"  # check_symbols 十四节的关断开关：只给 _run_case 用（变异过的 worktree 里十四节必红）


def landing(root=ROOT):
    """落点预检（lane cs27）：CASES 每格的变异与旧口径补丁在 root 当前工作树上逐格施一遍（Mem 叠层，不落盘、不建 worktree、
    不跑 check_symbols），只判落不落得上；外加「零、」K0–K10。给 (problems, 摘要)；✗ 行已打印。
    判不出的（期望 ✗ 字样 / rc / 空转对照）归全量，见 docs/GATES.md §三.23。"""
    tag = "check_symbols_mutants 落点预检 · "
    problems = [f"落点预检 {b}" for b in drill(Mem(None), quiet=True, tag=tag)]
    try:
        files = _git("ls-files", *RENAME_DIRS, cwd=root).stdout.split()
    except OSError as e:
        files = None
        print(f"  ✗ {tag}找不到 git（全仓改名要 ls-files）：{e}")
        problems.append("落点预检 找不到 git")
    LANDED.clear()
    if files is not None:
        for grp, cid, what, muts, want_rc, want_reds in CASES:
            wt = Mem(root, files)
            try:
                for m in muts:
                    m(wt)
            except Miss as e:
                print(f"  ✗ {tag}{cid} {what}：变异没落上——{e}（靶子漂了：照新源码改 {SELF} 的 CASES，改完跑全量 python3 {SELF}）")
                problems.append(f"落点预检 {cid} 变异没落上")
    spots = "；".join(f"插行靶子 {rel} {name} → {trail[-1]}" for (rel, name), trail in sorted(LANDED.items()))
    return problems, f"K0–K{len(DRILL)} {len(DRILL) + 1} 格判对；{len(CASES)} 格变异在当前源码上都落得上（{spots}）"


def _run_case(wt, snap, muts):
    if _git("reset", "-q", "--hard", snap, cwd=wt).returncode:
        raise RuntimeError("临时 worktree 复位失败")
    for m in muts:
        m(wt)
    p = subprocess.run([sys.executable, os.path.join(wt, SYM), LANDING_OFF], cwd=wt, capture_output=True, text=True, timeout=300,
                       env={k: v for k, v in os.environ.items() if k != "CHECK_SYMBOLS_SUGGEST"})
    reds = [ln.strip() for ln in p.stdout.split("\n") if ln.startswith("  ✗")]
    return p.returncode, reds, p.stdout + p.stderr


def main():
    if "--landing" in sys.argv[1:]:
        problems, summary = landing()
        if not problems:
            print(f"  ✓ check_symbols_mutants 落点预检：{summary}")
        print("结果：全部通过" if not problems else f"结果：{len(problems)} 项问题")
        return 1 if problems else 0
    try:
        in_git = _git("rev-parse", "--git-dir").returncode == 0
    except OSError as e:  # PATH 里没有 git（lane cs24 前这里抛 FileNotFoundError、退 1）
        print(f"  ✗ 找不到 git（要建临时 worktree）：{e}")
        return 2
    if not in_git:
        print("  ✗ 不在 git 仓库里（要建临时 worktree）")
        return 2
    tmp = tempfile.mkdtemp(prefix="nk1-symbols-mutants-")
    print("=" * 68)
    print("零、靶子定位自检（合成样本：往函数体插行的变异顺一行转发找真身，落不上判红）")
    print("=" * 68)
    problems, rcs = drill(os.path.join(tmp, "drill")), {}
    print()
    snap = _git("stash", "create").stdout.strip() or _git("rev-parse", "HEAD").stdout.strip()
    wt = os.path.join(tmp, "wt")
    add = _git("worktree", "add", "--detach", "-q", wt, snap)
    if add.returncode:
        print(f"  ✗ 建临时 worktree 失败：{add.stderr.strip()}")
        shutil.rmtree(tmp, ignore_errors=True)
        return 2
    try:
        print("=" * 68)
        print("一、逐格变异（临时 worktree 跑整道 check_symbols，比 rc 与「  ✗」行）")
        print("=" * 68)
        group = None
        for grp, cid, what, muts, want_rc, want_reds in CASES:
            if grp != group:
                print(f"  · {grp}")
                group = grp
            try:
                rc, reds, out = _run_case(wt, snap, muts)
            except Miss as e:
                print(f"  ✗ {cid} {what}：变异没落上——{e}")
                problems.append(f"{cid} 变异没落上")
                continue
            rcs[cid] = rc
            missing = [w for w in want_reds if not any(w in r for r in reds)]
            extra = [r for r in reds if not any(w in r for w in want_reds)]
            if rc == want_rc and not missing and not extra:
                tail = "；红的是 " + " / ".join(reds) if reds else ""
                print(f"  ✓ {cid} {what}：rc={rc}{tail}")
                continue
            print(f"  ✗ {cid} {what}：期望 rc={want_rc}，实得 rc={rc}")
            for w in missing:
                print(f"      缺 ✗ …{w}…")
            for r in extra:
                print(f"      多 {r}")
            if rc not in (0, 1):
                print("      " + "\n      ".join(out.strip().split("\n")[-8:]))
            problems.append(f"{cid} rc / ✗ 行与期望不符")
        print()
        print("=" * 68)
        print("二、空转对照（同一个变异：旧口径 rc=0 → 现行 rc=1）")
        print("=" * 68)
        for name, old, new, note in PAIRS:
            if rcs.get(old) == 0 and rcs.get(new) == 1:
                print(f"  ✓ {name}：{old} 旧口径 rc=0（{note}）→ {new} 现行 rc=1（只有护栏那一行红）")
            else:
                print(f"  ✗ {name}：{old} rc={rcs.get(old)}，{new} rc={rcs.get(new)}（应 0 → 1）")
                problems.append(f"空转对照不成立：{name}")
        print()
        print("=" * 68)
        print("三、靶子落点（往函数体插行的变异，按当前源码顺转发找到的真身）")
        print("=" * 68)
        for (rel, name), trail in sorted(LANDED.items()):
            print(f"  ✓ {rel} {name}：{' → '.join(trail)}")
    finally:
        _git("worktree", "remove", "--force", wt)
        shutil.rmtree(tmp, ignore_errors=True)
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
    sys.exit(main())
