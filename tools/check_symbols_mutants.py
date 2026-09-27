#!/usr/bin/env python3
"""check_symbols 反向断言空转的变异对照（lane auditfix3）：_node_block 记账（lane cs12）与 NAMED_FUNCS 按 (文件, 名字)
认（lane cs11）这两道护栏，各有一条真的反向断言、一个真能落上的变异，证明「没有护栏时缺陷在、门禁绿」。

  python3 tools/check_symbols_mutants.py          # 跑全部变异；有问题退 1，环境问题（无 git / 建不了 worktree）退 2
  python3 tools/check_symbols_mutants.py --json   # 机读（同 docs/GATES.md §二）

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
做法：把当前工作树的已跟踪文件（含未提交改动，`git stash create`，不动 stash 列表）检出到临时 worktree，逐格施变异、
跑整道 `python3 tools/check_symbols.py`，比 rc 与「  ✗」行：期望的每条都得出现，期望外的一条也不许有。
判红：任一格 rc 或 ✗ 行与期望不符；变异 / 旧口径补丁没落上（替换处数不对，说明源码改了、这支变异该跟着改）。
只读主树：临时 worktree 跑完即删（`git worktree remove --force`）。一格 2–4 s，全套 13 格约半分钟。
"""
import os, re, shutil, subprocess, sys, tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

SYM = "tools/check_symbols.py"
SELF = "tools/check_symbols_mutants.py"
RENAME_DIRS = ("scenes", "scripts", "tools")


class Miss(Exception):
    """变异 / 补丁没落上：替换处数与期望不符。"""


def _git(*args, cwd=ROOT):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def _read(wt, rel):
    with open(os.path.join(wt, rel), encoding="utf-8") as f:
        return f.read()


def _write(wt, rel, text):
    with open(os.path.join(wt, rel), "w", encoding="utf-8") as f:
        f.write(text)


def sub(wt, rel, pattern, repl, n=1):
    """rel 里按正则替换，须恰好 n 处（n=None：至少 1 处）。"""
    text = _read(wt, rel)
    new, k = re.subn(pattern, repl, text, flags=re.M)
    if (n is None and k == 0) or (n is not None and k != n):
        raise Miss(f"{rel} 里 {pattern!r} 替换了 {k} 处，应 {'≥1' if n is None else n} 处")
    _write(wt, rel, new)


def rename(wt, pattern, repl, skip=(), lines=None):
    """全仓（scenes / scripts / tools 已跟踪文件）改名；skip 的文件不动；lines(path) 给出只改哪些行的判据。"""
    files = _git("ls-files", *RENAME_DIRS, cwd=wt).stdout.split()
    hit = 0
    for rel in files:
        if rel in skip or not rel.endswith((".gd", ".tscn", ".py", ".sh")):
            continue
        text = _read(wt, rel)
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
    return lambda wt: sub(wt, "scripts/Main.gd", r"^(func _setup_shipyard\(port_id: String\) -> void:\n)",
                          r"\1\tGameManager.%s(1)\n" % fn)


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


def f_pre_branch_scan(wt):
    # auditfix3 前：自扫不收分支形反向断言
    sub(wt, SYM, r"^    if re\.match\(r'\\s\*\(\?:el\)\?if\\b.*\n.*# 分支形反向断言（lane auditfix3）\n", "")


NODE_MISS = '取场景节点块 [node name="CenterArea"] 取不到'
NF_MOVED = "断言点名的函数 advance_days 在 scripts/GameManager.gd 已无定义，别处还有同名（scripts/core/Calendar.gd）"
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
]
# 空转对照：旧口径那格 rc=0、现行那格 rc=1，两格同一个变异
_IDLE = "反向断言空转，缺陷在、门禁绿"
PAIRS = [("_node_block（lane cs12）", "N3", "N2", _IDLE), ("NAMED_FUNCS (文件, 名字)（lane cs11）", "F3", "F2", _IDLE),
         ("NAMED_FUNCS 自扫分支形（lane auditfix3）", "F7", "F6", "新反向断言漏登照样绿，日后改名即空转")]


def _run_case(wt, snap, muts):
    if _git("reset", "-q", "--hard", snap, cwd=wt).returncode:
        raise RuntimeError("临时 worktree 复位失败")
    for m in muts:
        m(wt)
    p = subprocess.run([sys.executable, os.path.join(wt, SYM)], cwd=wt, capture_output=True, text=True, timeout=300,
                       env={k: v for k, v in os.environ.items() if k != "CHECK_SYMBOLS_SUGGEST"})
    reds = [ln.strip() for ln in p.stdout.split("\n") if ln.startswith("  ✗")]
    return p.returncode, reds, p.stdout + p.stderr


def main():
    if _git("rev-parse", "--git-dir").returncode:
        print("  ✗ 不在 git 仓库里（要建临时 worktree）")
        return 2
    snap = _git("stash", "create").stdout.strip() or _git("rev-parse", "HEAD").stdout.strip()
    tmp = tempfile.mkdtemp(prefix="nk1-symbols-mutants-")
    wt = os.path.join(tmp, "wt")
    add = _git("worktree", "add", "--detach", "-q", wt, snap)
    if add.returncode:
        print(f"  ✗ 建临时 worktree 失败：{add.stderr.strip()}")
        shutil.rmtree(tmp, ignore_errors=True)
        return 2
    problems, rcs = [], {}
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
