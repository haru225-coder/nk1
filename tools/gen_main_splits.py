#!/usr/bin/env python3
"""tools/main_splits.txt 的生成器 / 对账（lane cs13，拍板清单 E-5）。

  python3 tools/gen_main_splits.py            # 对账：重算一遍，与 tools/main_splits.txt 逐字节比，不一致退 1（不写盘）
  python3 tools/gen_main_splits.py --write    # 按重算结果重写 tools/main_splits.txt，写完再对账一遍

main_splits.txt 是 Main.gd 拆出件的唯一清单：check_symbols（一之零 / read_main_src）和 godot_smoke（_main_family_src）
都读它的第一列，两份脚本里不再各自抄一份 MAIN_SPLITS。其余各列是拆分台账，check_symbols 每轮调本脚本的 check() 对账，
所以别手改——手改任何一格都会红；新拆一刀：在 docs/Main拆解台账.md 追加「## 第N刀（lane X，…）… → `scripts/ui/X.gd`」一节，
再跑 --write，连同拆出件一起提交。

各列从哪来（都是重算，没有一格手抄）：
  · 拆出件、顺序、lane ← docs/Main拆解台账.md：开头「已拆（前三刀…）」那行 + 各「## 第N刀（lane X，…）… → `路径`」节标题
  · 拆出函数 ← 现 Main.gd 的一行转发「Main 函数→拆出件 static func」，按拆出件里 static func 的顺序；
    拆出件里有 static func 不是 Main 转发过去的，记问题（拆出件只装从 Main 搬出的东西）
  · 拆出 commit ← git 里新增该文件的 commit；文件还没提交记 `-`
  · 原 Main 行范围 ← 拆出 commit 父版的 Main.gd（还没提交就用 HEAD 版）里这些函数的行段（含紧贴其上的 # / ## 注释），
    只隔空行的相邻段并成一段；台账里写了逐支行段的（表格行「| `_fn(…)` | a–b」），与重算的逐支行段对账
  · 台账那节函数表（「| `_fn(…)` |」行，写没写行段都算）列了的函数，现 Main 必须仍一行转发到本件，否则判红
    （lane cs18：挪回 Main 再 --write，拆出函数 / 行范围两栏跟着缩、清单照样逐字节一致，不查这条就一路全绿）

git 历史的两条放行（其余一律逐字节比）：
  · 拆出的那个 commit 自己不可能写进自己的哈希：清单里记 `-`、该 commit 版的清单也记 `-`、且 **HEAD 就是这个 commit** 的，照认；
    HEAD 已往前走（拆出 commit 之后又有提交）还记 `-` 即判红，要 --write 补上哈希（lane auditfix1：原先不看 HEAD，
    `-` 能一直绿下去，只等下一刀顺手补）。所以拆 Main 的 lane 提交拆分后紧跟着 --write、另提一笔补哈希，两笔同一次落地；
  · 浅克隆取不到拆出 commit 或其父版（如 CI 只拉 1 层）：这一行的 commit / 行范围两格沿用清单原值，报「未验」，不判红。
"""
import os, re, subprocess, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
TXT_REL = "tools/main_splits.txt"
TXT = os.path.join(ROOT, TXT_REL)
LEDGER_REL = "docs/Main拆解台账.md"
MAIN_REL = "scripts/Main.gd"
HEADER = (
    "# Main.gd 拆出件清单（lane cs13）。由 `python3 tools/gen_main_splits.py --write` 生成，别手改：check_symbols 每轮重算对账，改一格就红。\n"
    "# 读者：tools/check_symbols.py（一之零 / read_main_src 拼回）、tools/godot_smoke.gd（_main_family_src）都只读第一列。\n"
    "# 新拆一刀：docs/Main拆解台账.md 追加「## 第N刀（lane X，…）… → `scripts/ui/X.gd`」一节，再 --write。\n"
    "# 列（制表符分隔）：拆出件\tlane\t拆出 commit（`-` = 尚未提交 / 拆出 commit 自己）\t"
    "原 Main 行范围（拆出 commit 父版 Main.gd，含紧贴的注释）\t拆出函数（Main 函数→拆出件 static func）\n"
)
COLS = 5


def read_splits(path=TXT):
    """清单第一列（拆出件路径，相对仓库根），按文件顺序。读不到返回 ()。godot_smoke 的 _main_splits() 同一口径：
    跳过空行与 # 开头的行，取第一个制表符前的部分。"""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return ()
    return tuple(ln.split("\t")[0].strip() for ln in text.split("\n") if ln.strip() and not ln.startswith("#"))


def _git(*args):
    try:
        p = subprocess.run(["git", *args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return None
    return p.stdout.decode("utf-8", "replace") if p.returncode == 0 else None


def ledger_splits(problems):
    """[(路径, lane, 该刀台账那节正文)]，按台账顺序。前三刀只有开头一行，没有自己的节，正文记空。"""
    try:
        with open(os.path.join(ROOT, LEDGER_REL), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        problems.append(f"{LEDGER_REL} 读不到，拆出件清单无从生成")
        return []
    out = []
    head = re.search(r'^已拆（前三刀[^\n]*\n(.+?)\n\n', text, re.M | re.S)
    if not head:
        problems.append(f"{LEDGER_REL} 里找不到「已拆（前三刀…）」那行（前三刀拆出件的登记）")
    else:
        for name, lane in re.findall(r'`(\w+\.gd)`（(\w+)，', head.group(1)):
            out.append(("scripts/ui/" + name, lane, ""))
    heads = re.finditer(r'^## 第\S+?刀（lane (\w+)，[^）\n]*）：[^\n]*→ `(scripts/[\w/]+\.gd)`\s*$', text, re.M)
    for m in heads:
        nxt = re.search(r'^## ', text[m.end():], re.M)  # 节到下一个二级标题为止（含别的 lane 追加的非拆刀节）
        out.append((m.group(2), m.group(1), text[m.end():m.end() + nxt.start()] if nxt else text[m.end():]))
    seen = set()
    for rel, _, _ in out:
        if rel in seen:
            problems.append(f"{LEDGER_REL} 把 {rel} 登记了两次")
        seen.add(rel)
    return out


def _forwards(main_text):
    """现 Main.gd 里一行转发：{拆出件路径: {件内 static func: Main 函数}}（与 check_symbols 的 _SPLIT_FWD 同一形状）。"""
    consts = dict(re.findall(r'^const\s+(_[A-Z][A-Z0-9_]*)\s*:?=\s*preload\("res://([^"]+)"\)', main_text, re.M))
    out = {}
    for m in re.finditer(r'^func\s+([A-Za-z_]\w*)\s*\([^\n]*\n((?:\t#[^\n]*\n|[ \t]*\n)*)'
                         r'\t(?:return |await )?(_[A-Z][A-Z0-9_]*)\.([A-Za-z_]\w*)\(', main_text, re.M):
        if m.group(3) in consts:
            out.setdefault(consts[m.group(3)], {}).setdefault(m.group(4), m.group(1))
    return out


def func_spans(src, names):
    """src 里各 func 的行段 {名: (起, 止)}（1 起算）：起 = 紧贴 func 行之上的连续注释行的第一行，止 = 函数体最后一个非空行。"""
    lines = src.split("\n")
    spans = {}
    for i, ln in enumerate(lines):
        m = re.match(r'^func\s+([A-Za-z_]\w*)\s*\(', ln)
        if not m or m.group(1) not in names:
            continue
        a = i
        while a > 0 and lines[a - 1].startswith("#"):
            a -= 1
        b = i + 1
        while b < len(lines) and (lines[b] == "" or lines[b][0].isspace() or lines[b].startswith(")")):
            b += 1
        while b - 1 > i and not lines[b - 1].strip():
            b -= 1
        spans[m.group(1)] = (a + 1, b)
    return spans


def merge_spans(src, spans):
    """逐支行段并段：两段之间只隔空行就并成一段。返回 "a-b,c-d"。"""
    lines = src.split("\n")
    out = []
    for a, b in sorted(spans):
        if out and all(not lines[k].strip() for k in range(out[-1][1], a - 1)):
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return ",".join(f"{a}-{b}" for a, b in out)


def _add_commit(rel):
    """(新增该文件的 commit 短哈希 | None, 其父版 Main.gd 全文 | None)。没提交过：(None, HEAD 版 Main.gd)。"""
    log = _git("log", "--diff-filter=A", "-1", "--format=%h", "--", rel)
    if log is None:
        return None, None
    c = log.strip()
    if not c:
        return None, _git("show", "HEAD:" + MAIN_REL)
    return c, _git("show", f"{c}^:{MAIN_REL}")  # 浅克隆的边界 commit 看起来「新增了所有文件」，但取不到父版 → None


def build(old_rows=None, backfill=False):
    """重算清单。返回 (全文, 问题列表, 备注列表)。old_rows：现清单按路径的各列，git 取不到时沿用。
    backfill：--write 用，拆出 commit 自己记的 `-` 补成哈希；对账时不补（HEAD 就是拆出 commit 才照认 `-`，否则判红）。"""
    problems, notes = [], []
    old_rows = old_rows or {}
    try:
        with open(os.path.join(ROOT, MAIN_REL), encoding="utf-8") as f:
            fwd = _forwards(f.read())
    except OSError:
        problems.append(f"{MAIN_REL} 读不到")
        fwd = {}
    rows = []
    for rel, lane, section in ledger_splits(problems):
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            problems.append(f"台账登记的拆出件 {rel} 文件不存在（删了拆出件就把台账那条和清单一起改掉）")
            continue
        with open(path, encoding="utf-8") as f:
            statics = re.findall(r'^static\s+func\s+([A-Za-z_]\w*)\s*\(', f.read(), re.M)
        got = fwd.get(rel, {})
        orphan = [s for s in statics if s not in got]
        if orphan:
            problems.append(f"{rel} 的 static func {'、'.join(orphan)} 没有 Main 一行转发过来（拆出件只装从 Main 搬出的函数）")
        pairs = [(got[s], s) for s in statics if s in got]
        if not pairs:
            problems.append(f"{rel}：Main 里没有一行转发到它，拆出函数一栏是空的")
        # 台账那节函数表列了的（「| `_fn(…)` |」行，写没写逐支行段都算）须仍是 Main 一行转发到本件的：
        # 挪回 Main / 改名 / 转去别件后再 --write，重算结果里就没有它了，不在这里判红就只剩清单跟着改、一路全绿
        listed = re.findall(r'^\| `(_?\w+)\([^`]*\)` \|(?: (\d+)–(\d+))?', section, re.M)
        moved = {m for m, _ in pairs}
        for fn, a, b in listed:
            if fn not in moved:
                elsewhere = [r for r, g in fwd.items() if r != rel and fn in g.values()]
                problems.append(f"{lane} 族 {rel}：台账函数表列了 {fn}（期望拆前 Main.gd {f'{a}–{b} 行' if a else '行段台账未写'}），"
                                f"现 Main.gd 却{f'一行转发到 {elsewhere[0]}' if elsewhere else '没有一行转发到本件'}"
                                f"（挪回 Main / 改名 / 转去别件了？台账、拆出件、清单要一起改）")
        commit, pre = _add_commit(rel)
        old = old_rows.get(rel)
        if pre is None:
            if old:
                commit, rng = old[2], old[3]
                notes.append(f"{rel}：git 取不到拆出 commit 或其父版（浅克隆？），commit / 行范围沿用清单原值 {commit} / {rng}，未验")
            else:
                commit, rng = "-", "-"
                problems.append(f"{rel}：git 取不到拆出 commit 或其父版，清单里也没有这一行，行范围无从生成")
        else:
            spans = func_spans(pre, {m for m, _ in pairs})
            lost = [m for m, _ in pairs if m not in spans]
            if lost:
                problems.append(f"{rel}：拆出前的 Main.gd{f'（{commit}^）' if commit else '（HEAD）'}里找不到 "
                                f"func {'、'.join(lost)}（拆分时改了名？Main 函数须与拆前同名）")
            rng = merge_spans(pre, list(spans.values())) or "-"
            # 台账里写了逐支行段的，逐支对账（行号同是拆前 Main 的行号）；不在 spans 的上面已判红（不转发 / 拆前找不到），不重复报
            for fn, a, b in listed:
                if a and fn in spans and spans[fn] != (int(a), int(b)):
                    problems.append(f"{rel}：台账写 {fn} 在拆前 Main.gd 的 {a}–{b} 行，重算是 {spans[fn][0]}–{spans[fn][1]}")
            if commit is None:
                commit = "-"
            elif old and old[2] == "-" and not backfill:
                was = _git("show", f"{commit}:{TXT_REL}")
                if was is not None and any(ln.split("\t")[:3] == [rel, lane, "-"] for ln in was.split("\n")):
                    head, full = _git("rev-parse", "HEAD"), _git("rev-parse", commit)
                    if not (head and full and head.strip() == full.strip()):
                        # lane auditfix1：只在 HEAD 就是拆出 commit 时放行。原先只看「该 commit 版的清单也记 `-`」，
                        # 那永远成立，`-` 就一直绿到下一刀 --write 才补（main8 的 `-` 靠 main9 顺手补上，main9 的留成敞口）
                        n = (_git("rev-list", "--count", f"{commit}..HEAD") or "?").strip()
                        problems.append(f"{rel}：拆出 commit {commit} 已不是 HEAD（其后又有 {n} 个提交），清单 commit 列还记 `-`"
                                        f"——跑 python3 tools/gen_main_splits.py --write 补成 {commit} 并提交"
                                        f"（拆 Main 的 lane 提交拆分后就补，另提一笔、与拆分同一次落地）")
                    commit = "-"  # 拆出 commit 自己记的 `-`：HEAD 就是它时照认（不是 HEAD 的上面已记问题，这里不再重复报逐字节不一致）
        rows.append([rel, lane, commit, rng, " ".join(f"{m}→{s}" for m, s in pairs)])
    return HEADER + "".join("\t".join(r) + "\n" for r in rows), problems, notes


def _old_rows(text):
    return {r[0]: r for r in (ln.split("\t") for ln in text.split("\n") if ln.strip() and not ln.startswith("#"))
            if len(r) == COLS}


def check():
    """供 check_symbols 调：(是否一致, ✓/✗/⚠ 行列表, 问题列表)。"""
    try:
        with open(TXT, encoding="utf-8") as f:
            cur = f.read()
    except OSError:
        return False, [f"✗ {TXT_REL} 不存在（跑 python3 tools/gen_main_splits.py --write）"], [f"{TXT_REL} 不存在"]
    gen, problems, notes = build(_old_rows(cur))
    out = [f"⚠ {n}" for n in notes]
    problems = list(problems)
    if gen != cur:
        a, b = cur.split("\n"), gen.split("\n")
        for i in range(max(len(a), len(b))):
            x, y = (a[i] if i < len(a) else "（无此行）"), (b[i] if i < len(b) else "（无此行）")
            if x != y:
                problems.append(f"{TXT_REL} 第 {i + 1} 行与重算不一致（手改了清单，或台账 / 拆出件 / Main 转发改了没 --write）："
                                f"清单「{x[:160]}」≠ 重算「{y[:160]}」")
    for p in problems:
        out.append(f"✗ {p}")
    if not problems:
        n = len(read_splits())
        out.append(f"✓ {TXT_REL} 与重算逐字节一致（{n} 件；拆出件 / lane ← 台账，拆出函数 ← Main 一行转发，commit / 行范围 ← git）")
    return not problems, out, problems


def main(argv):
    if "--write" in argv:
        try:
            with open(TXT, encoding="utf-8") as f:
                cur = f.read()
        except OSError:
            cur = ""
        gen, problems, notes = build(_old_rows(cur), backfill=True)
        if problems:
            for p in problems:
                print(f"  ✗ {p}")
            print(f"  ✗ --write：有问题，{TXT_REL} 未改动")
            return 1
        if gen == cur:
            print(f"  ✓ --write：{TXT_REL} 与重算逐字节一致，未改动")
        else:
            with open(TXT, "w", encoding="utf-8") as f:
                f.write(gen)
            print(f"  ↻ --write：已重写 {TXT_REL}（{len(read_splits())} 件；请连同提交）")
    ok, lines, _ = check()
    for ln in lines:
        print("  " + ln)
    print("结果：" + ("全部通过" if ok else "有问题"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
