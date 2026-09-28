#!/usr/bin/env python3
"""gen_main_splits 台账格式硬校验与 check_decision_refs 输出确定序的变异对照（lane cs25，固化 lane cs23 的探针）。

  python3 tools/ledger_refs_mutants.py          # 跑全部变异；有问题退 1，环境问题（无 git / 建不了 worktree）退 2
  python3 tools/ledger_refs_mutants.py --json   # 机读（同 docs/GATES.md §二）

为什么：lane cs23 收了两处「门禁自己绿、下游才兜 / 偶发假 DIFF」的缺口，变异实测只在仓外探针
（/tmp/cs23/{mut_gen,det,mut_det}.py）里跑过，没入库；日后放宽了、正则改了、排序删了，没人会再跑那几支探针。
这里按 check_symbols_mutants（lane auditfix3）的规格固化：期望表逐格比，另立「旧口径 rc=0 → 现行 rc=1」空转对照。
  · 一、台账格式硬校验（gen_main_splits ①–⑤）：逐格改 docs/Main拆解台账.md，各跑三遍 gen——对账、`--write`、`--write` 后再对账。
    现行须对账 rc=1 且 ✗ 行对得上期望、`--write` 不写盘、写后对账仍 rc=1；把硬校验退回 cs23 前（删两处调用），同一变异
    `--write` 后对账 rc=0——这一刀 / 这一行被正则漏掉、清单跟着少，gen 自己绿（cs23 原探针 15 例里旧 gen 12 例这样）。
    lane cs25 给第四、第五刀补了函数表、删了 NO_TABLE_OK：M5t 删第四刀的表现行判红，放行退回（cs25 前）rc=0；N1 / N2 证明补的
    两张表真在对账（漏列一支 / 行段写错各一行红）。对照 C0–C2：不改、原来就红的（en dash 行段写错）、正文里提「第十一刀」。
  · 二、输出确定序（check_decision_refs）：同一棵树在 PYTHONHASHSEED = 0 / 1 / 2 / 3 / 42 下各跑一次，stdout 须逐字节同、rc 同。
    D1 清单里前 8 处 `scripts/Main.gd:N` 号 +1、不提交（改号自证对 HEAD 版逐对比出多条 MISMATCH）、D2 `--since ccb1d57`
    （多条 ⚠ / MISMATCH）：⚠ / ✗ 行不到 2 条就比不出行序，记「变异没落上」。X1 / X2 = 同上、两处排序（Lines.flush 的
    sorted、since() 的 pairs.sort）都去掉——cs23 前的写法，须 5 个种子出 ≥2 种 stdout；只去一处仍确定（cs23 实测，另一处兜得住），
    所以变异两处一起去。种子固定，本门禁自己的结论逐次相同。
做法：把当前工作树的已跟踪文件（含未提交改动，`git stash create`，不动 stash 列表）检出到临时 worktree，逐格复位、施变异、跑；
判红：任一格 rc / ✗ 行 / 写盘 / 确定性与期望不符；变异 / 旧口径补丁没落上（替换处数不对，说明源码或台账改了、这支变异该跟着改）。
只读主树：临时 worktree 跑完即删（`git worktree remove --force`）。全套约半分钟。
"""
import hashlib, os, re, shutil, subprocess, sys, tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

GEN = "tools/gen_main_splits.py"
TXT = "tools/main_splits.txt"
LEDGER = "docs/Main拆解台账.md"
REFS = "tools/check_decision_refs.py"
DOC = "docs/待策划拍板清单_2026-09-28.md"
SEEDS = (0, 1, 2, 3, 42)


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


def sub(rel, pattern, repl, n=1):
    """rel 里按正则替换，须恰好 n 处。"""
    def m(wt):
        text = _read(wt, rel)
        new, k = re.subn(pattern, repl, text, flags=re.M)
        if k != n:
            raise Miss(f"{rel} 里 {pattern!r} 替换了 {k} 处，应 {n} 处")
        _write(wt, rel, new)
    return m


# ---- 一、台账格式硬校验 -------------------------------------------------------------------------------------
H11 = r"^## 第十一刀（lane main11，2026-09-28）：标题页 / 开场 → `scripts/ui/TitlePage\.gd`$"
ROW = r"^\| `_on_rewatch_opening\(\)` \| 651–652 \|"


def l_sub(pattern, repl):
    return sub(LEDGER, pattern, repl)


def l_head(fn):
    """第十一刀节标题整行换成 fn(原行)。"""
    return sub(LEDGER, H11, lambda m: fn(m.group(0)))


def l_drop_table(head):
    """head 那节（到下一个二级标题为止）的函数表行全删。"""
    def m(wt):
        text = _read(wt, LEDGER)
        h = re.search(head, text, re.M)
        if not h:
            raise Miss(f"{LEDGER} 里找不到节标题 {head!r}")
        nxt = re.search(r"^## ", text[h.end():], re.M)
        end = h.end() + nxt.start() if nxt else len(text)
        body, k = re.subn(r"^\| `_\w+\(.*\n", "", text[h.end():end], flags=re.M)
        if not k:
            raise Miss(f"{LEDGER} {head!r} 那节没有函数表行可删")
        _write(wt, LEDGER, text[:h.end()] + body + text[end:])
    return m


H4 = r"^## 第四刀（lane main4，[^\n]*`scripts/ui/TavernPage\.gd`$"
# 退回 cs23 前：台账格式硬校验两处调用删掉（ledger_splits 照旧认刀，认不出的静默漏掉）
g_pre_cs23 = [sub(GEN, r"^        _check_first_knifes\(head\.group\(1\), len\(out\), problems\)\n", ""),
              sub(GEN, r"^    _check_ledger_shape\(text, problems\)\n", "")]
# 退回 cs25 前：第四 / 第五刀没表照放行
g_pre_cs25 = [sub(GEN, r"^        if not seen:$",
                  '        if not seen and rel not in ("scripts/ui/TavernPage.gd", "scripts/ui/NpcPage.gd"):')]

M = {
    "M1a": ("①节标题去反引号", [l_head(lambda h: h.replace("`", ""))]),
    "M1b": ("①节标题写成 ###", [l_head(lambda h: "#" + h)]),
    "M1c": ("①「##第十一刀」无空格", [l_head(lambda h: h.replace("## ", "##", 1))]),
    "M1d": ("①半角括号逗号", [l_head(lambda h: h.replace("（lane main11，2026-09-28）", "(lane main11, 2026-09-28)"))]),
    "M1e": ("①去掉 lane 字样", [l_head(lambda h: h.replace("lane main11", "main11"))]),
    "M1f": ("①箭头后多字", [l_head(lambda h: h + "（已落地）")]),
    "M2a": ("②前三刀 SlipKit 半角括号", [l_sub(r"`SlipKit\.gd`（ms，", "`SlipKit.gd`(ms，")]),
    "M2b": ("②前三刀删掉一件", [l_sub(r"`SlipKit\.gd`（ms，工席纸条小件）· ", "")]),
    "M3a": ("③第十一刀改成第十刀（重号）", [l_head(lambda h: h.replace("第十一刀", "第十刀"))]),
    "M3b": ("③第十一刀改成第十三刀（跳号）", [l_head(lambda h: h.replace("第十一刀", "第十三刀"))]),
    "M3c": ("③刀号写成认不出的「第拾壹刀」", [l_head(lambda h: h.replace("第十一刀", "第拾壹刀"))]),
    "M4a": ("④函数表行「|」后不空格", [l_sub(ROW, "|`_on_rewatch_opening()` | 651–652 |")]),
    "M4b": ("④行段写 ASCII 连字符且写错", [l_sub(ROW, "| `_on_rewatch_opening()` | 651-699 |")]),
    "M4c": ("④同一支列两次", [l_sub(r"^(\| `_on_rewatch_opening\(\)` \| 651–652 \|[^\n]*\n)", r"\1\1")]),
    "M5": ("⑤第十一刀那节删光函数表行", [l_drop_table(H11)]),
    "M5t": ("⑤第四刀那节删光函数表行（lane cs25 补的表）", [l_drop_table(H4)]),
}
SHAPE = "格式硬校验 {}"
RESYNC = "与重算不一致"
# (组, 编号, 说明, 变异, 期望对账 rc, 期望 ✗ 行须含的字样, 期望 --write 后对账 rc)；--write 判红的一律不许写盘
GEN_CASES = [
    ("对照", "C0", "台账不改", [], 0, [], 0),
    ("对照", "C1", "行段写 en dash 且写错（cs23 前就红）", [l_sub(ROW, "| `_on_rewatch_opening()` | 651–699 |")], 1,
     ["台账写 _on_rewatch_opening 在拆前 Main.gd 的 651–699 行，重算是 651–652"], 1),
    ("对照", "C2", "正文里提「第十一刀」（不是标题）", [l_head(lambda h: h + "\n\n本节即第十一刀，承第十刀。")], 0, [], 0),
]
_WANT = {  # 现行各格的 ✗ 字样；旧口径各格的（下面 _OLD）
    "M1a": [SHAPE.format("①"), RESYNC], "M1b": [SHAPE.format("①"), "台账函数表列了 _play_opening", "台账函数表列了 _on_opening_finished",
                                                "台账函数表列了 _on_rewatch_opening", "台账函数表列了 _setup_title_mode",
                                                "台账函数表列了 _on_start_game_pressed"],
    "M1d": [SHAPE.format("①"), RESYNC], "M1e": [SHAPE.format("①"), RESYNC], "M1f": [SHAPE.format("①"), RESYNC],
    "M2a": [SHAPE.format("②"), RESYNC], "M2b": [SHAPE.format("②"), RESYNC],
    "M3a": ["「第十刀」刀序不对：上一刀之后应是第 11 刀"], "M3b": ["「第十三刀」刀序不对：上一刀之后应是第 11 刀",
                                                      "「第十二刀」刀序不对：上一刀之后应是第 14 刀"],
    "M3c": ["「第拾壹刀」的刀号认不出"],
    "M4a": [SHAPE.format("④"), "现 Main.gd 的 _on_rewatch_opening 一行转发到本件 on_rewatch_opening，台账那节函数表却没列它"],
    "M4b": ["_on_rewatch_opening 的行段写法不认"], "M4c": ["函数表把 _on_rewatch_opening 列了两次"],
    "M5": ["（scripts/ui/TitlePage.gd 那节）没有函数表"], "M5t": ["（scripts/ui/TavernPage.gd 那节）没有函数表"],
}
_WANT["M1c"] = _WANT["M1b"] = _WANT["M1b"] + [RESYNC]
# 第十一刀认不出 / 改了号，后面的第十二刀（lane main12）跟着刀序不对——cs23 实测时还没有第十二刀
for _cid in ("M1a", "M1b", "M1c", "M1d", "M1e", "M1f", "M3a"):
    _WANT[_cid].append("「第十二刀」刀序不对：上一刀之后应是第 11 刀")
# 旧口径那格：同一变异，退回 cs23 前（M5t 退回 cs25 前）——(对账 rc, ✗ 字样)，--write 后对账都是 rc=0（空转）
_OLD = {"M1a": (1, [RESYNC]), "M1d": (1, [RESYNC]), "M1e": (1, [RESYNC]), "M1f": (1, [RESYNC]), "M2a": (1, [RESYNC]),
        "M2b": (1, [RESYNC]), "M3a": (0, []), "M3b": (0, []), "M3c": (0, []), "M4b": (0, []), "M4c": (0, []), "M5": (0, []),
        "M5t": (0, [])}
for cid, (what, muts) in M.items():
    grp = "⑤ 函数表（lane cs25）" if cid == "M5t" else "台账格式 " + what[0]
    GEN_CASES.append((grp, cid, what[1:] + "，现行", muts, 1, _WANT[cid], 1))
    if cid in _OLD:
        rc, reds = _OLD[cid]
        pre = g_pre_cs25 if cid == "M5t" else g_pre_cs23
        GEN_CASES.append((grp, cid + "′", what[1:] + ("，NO_TABLE_OK 放行退回（cs25 前）" if cid == "M5t" else "，硬校验退回 cs23 前"),
                          muts + pre, rc, reds, 0))
GEN_CASES += [
    ("⑤ 函数表（lane cs25）", "N1", "第四刀函数表漏列 _seal_chip（cs22 有表须列全）",
     [l_sub(r"^\| `_seal_chip\(btn\)` \|[^\n]*\n", "")], 1,
     ["现 Main.gd 的 _seal_chip 一行转发到本件 seal_chip，台账那节函数表却没列它"], 1),
    ("⑤ 函数表（lane cs25）", "N2", "第五刀函数表 _on_npc_leave 行段写错（逐支行段对账）",
     [l_sub(r"^(\| `_on_npc_leave\(\)` \| )3045–3047", r"\g<1>3045–3049")], 1,
     ["台账写 _on_npc_leave 在拆前 Main.gd 的 3045–3049 行，重算是 3045–3047"], 1),
]
GEN_PAIRS = [(cid + "′", cid) for cid in M if cid in _OLD]


# ---- 二、输出确定序 ---------------------------------------------------------------------------------------------
def d_dirty(wt):
    """清单里前 8 处 `scripts/Main.gd:N` 号 +1、不提交：改号自证对 HEAD 版逐对比，每处 MISMATCH / ⚠ 一行。"""
    text = _read(wt, DOC)
    hits = list(re.finditer(r"`scripts/Main\.gd:(\d+)`", text))[:8]
    if len(hits) < 8:
        raise Miss(f"{DOC} 里 `scripts/Main.gd:N` 引用只有 {len(hits)} 处，应 ≥8")
    for m in reversed(hits):
        text = text[:m.start(1)] + str(int(m.group(1)) + 1) + text[m.end(1):]
    _write(wt, DOC, text)


# cs23 前的写法：逐处行不排序直接印、since() 的配对不排序（集合交集的遍历顺序随 PYTHONHASHSEED 变）
d_unsort = [sub(REFS, r"^        for _, text in sorted\(self\.rows, key=lambda r: r\[0\]\):$", "        for _, text in self.rows:"),
            sub(REFS, r"^    pairs\.sort\(key=lambda p: \(p\[1\], p\[0\]\)\)\n", "")]
SINCE = ["--since", "ccb1d57"]
# (组, 编号, 说明, 变异, 参数, 期望 rc, 期望确定, ⚠ / ✗ 行至少几条)
DET_CASES = [
    ("基线", "D0", "不改、默认口径", [], [], 0, True, 0),
    ("改号自证", "D1", "清单前 8 处 Main.gd 号 +1 不提交、默认口径，现行", [d_dirty], [], 1, True, 2),
    ("改号自证", "X1", "同 D1，两处排序都去掉（cs23 前）", [d_dirty] + d_unsort, [], 1, False, 2),
    ("--since", "D2", "`--since ccb1d57`，现行", [], SINCE, 1, True, 2),
    ("--since", "X2", "同 D2，两处排序都去掉（cs23 前）", d_unsort, SINCE, 1, False, 2),
]
DET_PAIRS = [("X1", "D1"), ("X2", "D2")]


def _reset(wt, snap, muts):
    if _git("reset", "-q", "--hard", snap, cwd=wt).returncode:
        raise RuntimeError("临时 worktree 复位失败")
    for m in muts:
        m(wt)


def _py(wt, rel, args, seed=None):
    env = {k: v for k, v in os.environ.items() if k != "PYTHONHASHSEED"}
    if seed is not None:
        env["PYTHONHASHSEED"] = str(seed)
    return subprocess.run([sys.executable, os.path.join(wt, rel), *args], cwd=wt, capture_output=True, text=True,
                          timeout=300, env=env)


def _reds(out):
    return [ln.strip() for ln in out.split("\n") if ln.startswith("  ✗")]


def _gen_case(wt, snap, muts):
    _reset(wt, snap, muts)
    before = _read(wt, TXT)
    p0 = _py(wt, GEN, [])
    pw = _py(wt, GEN, ["--write"])
    wrote = _read(wt, TXT) != before
    p1 = _py(wt, GEN, [])
    return p0.returncode, _reds(p0.stdout), pw.returncode, wrote, p1.returncode, p0.stdout + p0.stderr


def _det_case(wt, snap, muts, args):
    _reset(wt, snap, muts)
    runs = [_py(wt, REFS, args, seed) for seed in SEEDS]
    kinds = {hashlib.md5(r.stdout.encode()).hexdigest()[:8] for r in runs}
    rcs = sorted({r.returncode for r in runs})
    lines = sum(1 for ln in runs[0].stdout.split("\n") if ln.lstrip().startswith(("⚠", "✗")))
    return rcs, kinds, lines, runs[0].stdout + runs[0].stderr


def _bad(problems, cid, what):
    problems.append(f"{cid} {what}")


def run(wt, snap, problems):
    rcs = {}
    print("=" * 68)
    print("一、台账格式硬校验（临时 worktree 改台账，gen_main_splits 对账 / --write / 写后对账，比 rc 与「  ✗」行）")
    print("=" * 68)
    group = None
    for grp, cid, what, muts, want_rc, want_reds, want_after in GEN_CASES:
        if grp != group:
            print(f"  · {grp}")
            group = grp
        try:
            rc, reds, wrc, wrote, after, out = _gen_case(wt, snap, muts)
        except Miss as e:
            print(f"  ✗ {cid} {what}：变异没落上——{e}")
            _bad(problems, cid, "变异没落上")
            continue
        rcs[cid] = after
        missing = [w for w in want_reds if not any(w in r for r in reds)]
        extra = [r for r in reds if not any(w in r for w in want_reds)]
        leak = wrc != 0 and wrote
        if rc == want_rc and after == want_after and not missing and not extra and not leak:
            tail = "；红的是 " + " / ".join(r[:90] for r in reds[:2]) + (f" 等 {len(reds)} 条" if len(reds) > 2 else "") if reds else ""
            print(f"  ✓ {cid} {what}：对账 rc={rc}，--write rc={wrc}{'（写了盘）' if wrote else ''}，写后对账 rc={after}{tail}")
            continue
        print(f"  ✗ {cid} {what}：期望对账 rc={want_rc} / 写后 rc={want_after}，实得 {rc} / {after}（--write rc={wrc}）")
        for w in missing:
            print(f"      缺 ✗ …{w}…")
        for r in extra:
            print(f"      多 {r[:200]}")
        if leak:
            print("      --write 判红却写了盘")
        if rc not in (0, 1):
            print("      " + "\n      ".join(out.strip().split("\n")[-8:]))
        _bad(problems, cid, "rc / ✗ 行 / 写盘与期望不符")
    print()
    print("=" * 68)
    print(f"二、输出确定序（check_decision_refs 在 PYTHONHASHSEED={'/'.join(map(str, SEEDS))} 下各跑一次，比 stdout md5 与 rc）")
    print("=" * 68)
    det = {}
    group = None
    for grp, cid, what, muts, args, want_rc, want_det, min_lines in DET_CASES:
        if grp != group:
            print(f"  · {grp}")
            group = grp
        try:
            got_rcs, kinds, lines, out = _det_case(wt, snap, muts, args)
        except Miss as e:
            print(f"  ✗ {cid} {what}：变异没落上——{e}")
            _bad(problems, cid, "变异没落上")
            continue
        if lines < min_lines:
            print(f"  ✗ {cid} {what}：⚠ / ✗ 行只有 {lines} 条，应 ≥{min_lines}（比不出行序：变异没落上，或清单 / 历史变了、换一个口径）")
            _bad(problems, cid, "变异没落上")
            continue
        det[cid] = len(kinds) == 1
        state = f"rc={'/'.join(map(str, got_rcs))}，⚠ / ✗ {lines} 条，stdout {len(kinds)} 种（{' '.join(sorted(kinds))}）"
        if got_rcs == [want_rc] and det[cid] == want_det:
            print(f"  ✓ {cid} {what}：{state}")
            continue
        print(f"  ✗ {cid} {what}：期望 rc={want_rc}、{'逐字节同' if want_det else '≥2 种'}，实得 {state}")
        if any(r not in (0, 1) for r in got_rcs):
            print("      " + "\n      ".join(out.strip().split("\n")[-8:]))
        _bad(problems, cid, "rc / 确定性与期望不符")
    print()
    print("=" * 68)
    print("三、空转对照（同一个变异：旧口径 → 现行）")
    print("=" * 68)
    for old, new in GEN_PAIRS:
        what = M[new][0][1:]
        if rcs.get(old) == 0 and rcs.get(new) == 1:
            print(f"  ✓ {what}：{old} 旧口径 --write 后 rc=0（漏认、清单跟着少，gen 自己绿）→ {new} 现行 rc=1、不写盘")
        else:
            print(f"  ✗ {what}：{old} 写后 rc={rcs.get(old)}，{new} 写后 rc={rcs.get(new)}（应 0 → 1）")
            problems.append(f"空转对照不成立：{new}")
    for old, new in DET_PAIRS:
        if det.get(old) is False and det.get(new) is True:
            print(f"  ✓ 输出确定序：{old} cs23 前 5 个种子 stdout 不止一种（「逐字节同」比对偶发假 DIFF）→ {new} 现行逐字节同")
        else:
            print(f"  ✗ 输出确定序：{old} 确定={det.get(old)}，{new} 确定={det.get(new)}（应 否 → 是）")
            problems.append(f"空转对照不成立：{new}")


def main():
    if _git("rev-parse", "--git-dir").returncode:
        print("  ✗ 不在 git 仓库里（要建临时 worktree）")
        return 2
    snap = _git("stash", "create").stdout.strip() or _git("rev-parse", "HEAD").stdout.strip()
    tmp = tempfile.mkdtemp(prefix="nk1-ledger-refs-mutants-")
    wt = os.path.join(tmp, "wt")
    add = _git("worktree", "add", "--detach", "-q", wt, snap)
    if add.returncode:
        print(f"  ✗ 建临时 worktree 失败：{add.stderr.strip()}")
        shutil.rmtree(tmp, ignore_errors=True)
        return 2
    problems = []
    try:
        run(wt, snap, problems)
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
