#!/usr/bin/env python3
"""RefsHostPath（lane gd22）：仓库里不许写本机 Linux 绝对路径（家目录、/workspace 下的仓库根），RefsMacPath 的本机版。

  python3 tools/check_host_paths.py          # 自检；有问题退 1
  python3 tools/check_host_paths.py --json   # 机读（同 docs/GATES.md §二）

为什么：仓库根写死成 /workspace/<仓库>，照抄的命令在隔离 worktree / 软链 / 换机后会悄悄跑主树或直接找不到。
仓库内一律 `--path .`（工作目录为仓库根）、引擎走 PATH / $GODOT，家目录写 `~/…`。
扫什么：git 已跟踪的全部文本文件（读工作树里的内容，已暂存的新文件也算；含 NUL 字节的二进制跳过）。
本脚本自身也扫：PATTERNS 写成 `/home/<用户>` 这类占位不会命中，只放过 ROOTS 登记行里的仓外根（当 owner 看）；
`SAMPLES = [` 块按行排除（lane cs21，同 check_mac_paths），块里每行须是一条 `r"样本行"`、行数与条目数相等，且每行都得在零节判红，
所以塞不进漏网的路径；块形状不对即判红、整份照扫。
判红：
  · 零、样本自检（lane cs21，每次跑都先过，与 check_mac_paths 的「零」同规格）：SAMPLES 有一行在任一处（.gd 代码行 / 注释行 / .md）
    没判红，或 CLEAN 有一行在任一处判了红，或 ROOTS 每条的 owner 口径（owner 代码行绿；非 owner 代码行、拼接写法红；
    非 owner 行尾注释 / .py 文档串 / .md 绿）有一处不对，即判红——模式表回退 / 改窄了、owner 判断或 path_scan 的注释切法 /
    拼接折叠改坏了在这里先红，不等真文件写进来；
  · 命中 `/home/<用户>` 或 `/workspace/<目录>`，且不是 ROOTS 登记的仓外根（仓库根本身不在 ROOTS 里，一律红）；
  · ROOTS 登记的仓外根出现在代码段里，而文件不是该根的 owner——
    代码只许 owner 写一次默认值，其余走 owner / 环境变量（截图根走 ShotGate.out_dir，简报目录读 $NK1_BRIEFS）；
  · ROOTS 条目失效：owner 不在 / 不再跟踪、owner 代码里不再写这个根、owner 里找不到登记的环境变量名。
文档与注释里写仓外根不红（说明默认值落在哪，本来就该写全）。
代码 / 注释按位置切（lane cs20，口径在 tools/path_scan.py 与 check_mac_paths 共用）：.gd / .py / .sh / .gdshader 每行在注释起点切开，
  切后只有代码段算代码——行尾注释里写仓外根不红，字符串里的 `#`、shell 的 `$#` / `${#a}` 不起注释；.py 文档串、
  GDScript 独占语句的三引号串整段算文档；其余文件整份算文档。
拼接也认（lane cs20，同 path_scan.fold）：`"/<根>" + "/<目录>"`、`.path_join(…)`、`os.path.join(…)`、`Path(…) / …` 折成一段再对模式，
  字面量拆开写照样命中；家目录取法（`OS.get_environment("HOME")` 等）折成 `$HOME`，与 `~/…` 同算合规。
工作树里未跟踪的文件有命中只记 ⚠、不判红，与 check_mac_paths / check_docs_index 同口径；git 不可用时退回扫盘。
不在此列：Godot 节点路径 `/root/…`、`~/.local/…` 这类家目录相对写法、`/tmp/…`。
"""
import os, re, subprocess, sys
from collections import Counter

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

sys.path.insert(0, TOOLS)
import path_scan

SELF = "tools/check_host_paths.py"

# (名字, 正则, 为什么算本机专属)；/workspace 的命中取到第一段目录为止，拿去对 ROOTS
PATTERNS = [
    ("/home/<用户>", r"/home/[A-Za-z_][\w.-]*", "Linux 用户家目录（本机那个用户名；换用户 / 换机即不在，写 `~/…` 或走 PATH）"),
    ("/workspace/<目录>", r"/workspace/[\w.-]+", "本机工作区挂载点（仓库根就在它下面；worktree / 软链 / 换机后就不是当前树，写 `--path .` / 仓库相对路径）"),
]
PAT = re.compile("|".join(f"(?:{p})" for _, p, _ in PATTERNS))

# 已定级、允许写的仓外根：根 → env（覆盖它的环境变量，须在 owner 里出现）、owners（代码里唯一许写它的文件）、why。
# 要加条目先想清楚能不能改成仓库相对 / env；仓库根本身永不进这里。
ROOTS = {
    "/workspace/nk1-qa-shots": {
        "env": "NK1_SHOT_DIR", "owners": ("tools/shot_gate.gd",),
        "why": "共享截图证据根：仓外、刻意写绝对路径（证据图不进仓库，也不随 worktree 走；worktree 自测设 $NK1_SHOT_DIR 另落，lane m3 / gd2）；"
               "代码里只有 shot_gate.gd 的 DEFAULT_SHOT_ROOT 写它，gate_json 读这个常量生成 GATES 表的截图目录列"},
    "/workspace/nk1-agent-briefs": {
        "env": "NK1_BRIEFS", "owners": ("tools/check_decision_refs.py",),
        "why": "lane 简报目录：仓外、不随仓库分发（docs/README.md「协调台账」）；代码里只有 check_decision_refs.py 拿它作 $NK1_BRIEFS 的默认值"},
}
CODE_EXT = path_scan.CODE_EXT

# 样本自检（lane cs21）：每次跑都先过「零」——下面每行放进 .gd 代码行、.gd 注释行、.md 三处都须判红，漏一处即判红（模式表回退 / 改窄了）。
# 头三行是 lane gd22 清掉的原文（探针头注 `--path` 写死仓库根、GATES.md 引擎行写家目录）；末三行是 lane cs20 补认的拼接写法。
# 本块按行排除自扫：块里每行须是一条 r"样本行"，且每行都得判红，所以塞不进漏网的路径。
SAMPLES = [
    r"## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_title_probe.gd   # 截图门禁（须出 5 张）",
    r"##       godot --headless --path /workspace/nk1 -s res://tools/qa_title_probe.gd -- --contract",
    r"- Godot：`/home/box/.local/bin/godot`（4.6.3，下文写 `godot`）；工作目录为仓库根。",
    r'const GODOT := "/home/box/.local/bin/godot"',
    r"cd /workspace/nk1 && python3 tools/check_symbols.py",
    r"git worktree add --detach /workspace/nk1-cs21 HEAD",
    r'OUT = "/workspace/nk1-qa-shots-old/p7"',
    r"B=/workspace/nk1-agent-briefs.bak/lane-x.md",
    r"export PATH=/home/snow.chan/bin:$PATH",
    r'var dir := "/home/_ci/tmp/nk1"',
    r'var repo := "/work" + "space/nk1"',
    r'var d := "/workspace".path_join("nk1-cs21")',
    r'GODOT = os.path.join("/home", "box", ".local/bin/godot")',
]
# 反向样本：同样三处都须不判红（误报即判红）。docstring 末尾「不在此列」那几类 + 占位写法 + 家目录取法拼接 + 登记根写在注释里。
CLEAN = [
    "godot --headless --path . -s res://tools/qa_title_probe.gd",
    "~/.local/bin/godot --version",
    "$HOME/.local/bin/godot",
    'var g := OS.get_environment("HOME").path_join(".local/bin/godot")',
    "get_node(\"/root/Main/HUD\")",
    "git worktree add --detach /tmp/nk1-cs21 HEAD",
    "扫 `/home/<用户>` 与 `/workspace/<目录>` 两类",
    "/homepage/index.html",
    "# 截图默认落 /workspace/nk1-qa-shots/<lane>/，自测设 $NK1_SHOT_DIR",
    "## 简报目录 /workspace/nk1-agent-briefs 由 $NK1_BRIEFS 覆盖",
    'var d := ShotGate.out_dir("p7")  # 默认落 /workspace/nk1-qa-shots/p7',
]
SELF_TEST_CODE, SELF_TEST_DOC = "tools/_host_paths_selftest.gd", "docs/_host_paths_selftest.md"

fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def self_block(name="SAMPLES"):
    """本脚本 SAMPLES 块里条目行的行号集合（自扫按行排除用）；块找不到 / 形状不对 → (None, 原因)。同 check_mac_paths.self_block。"""
    with open(os.path.join(ROOT, SELF), encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    starts = [i for i, ln in enumerate(lines) if ln == f"{name} = ["]
    if len(starts) != 1:
        return None, f"`{name} = [` 行有 {len(starts)} 处（须恰 1 处）"
    a = starts[0]
    b = next((i for i in range(a + 1, len(lines)) if lines[i] == "]"), None)
    if b is None:
        return None, f"`{name} = [` 之后找不到收尾的 `]` 行"
    inner = range(a + 1, b)
    odd = [i + 1 for i in inner if not re.fullmatch(r"""    r(?:"[^"]*"|'[^']*'),""", lines[i])]
    if odd:
        return None, f"块里第 {'、'.join(map(str, odd))} 行不是一条 r\"样本行\""
    if len(inner) != len(SAMPLES):
        return None, f"块里 {len(inner)} 行，{name} {len(SAMPLES)} 条（须一条一行）"
    return {i + 1 for i in inner}, None


def judge(rel, text):
    """把 text 当作文件 rel 的内容走一遍扫文件的同一条路（hits_text → offending），返回不合规命中。"""
    return offending(rel, hits_text(rel, text))


def sample_selftest():
    """「零」：SAMPLES 每行三处都红、CLEAN 每行三处都绿；ROOTS 每条按 owner / 非 owner / 拼接 / 行尾注释 / 文档串 / .md 各判一次。"""
    where = (("代码行", SELF_TEST_CODE, "{}"), ("注释行", SELF_TEST_CODE, "# {}"), (".md", SELF_TEST_DOC, "{}"))

    def missed(ln, want_red):
        return [w for w, rel, fmt in where if bool(judge(rel, fmt.format(ln) + "\n")) != want_red]
    miss = [(ln, m) for ln in SAMPLES if (m := missed(ln, True))]
    check(not miss, f"正向样本 {len(SAMPLES)} 行在 .gd 代码行 / 注释行 / .md 三处都判红（{len(PATTERNS)} 条模式）"
          + ("" if not miss else "；漏判：" + " | ".join(f"{ln}（{'、'.join(m)}）" for ln, m in miss)))
    false = [(ln, m) for ln in CLEAN if (m := missed(ln, False))]
    check(not false, f"反向样本 {len(CLEAN)} 行三处都不判红（`--path .`、`~/…`、`/root/…`、`/tmp/…`、占位、HOME 派生、登记根写在注释里）"
          + ("" if not false else "；误报：" + " | ".join(f"{ln}（{'、'.join(m)}）" for ln, m in false)))
    for root, r in ROOTS.items():
        code = f'DEFAULT_ROOT = "{root}"\n'
        other = next(iter(r["owners"]))
        cases = [(f"owner {other} 代码行", other, code, False),
                 ("非 owner 代码行", SELF_TEST_CODE, code, True),
                 ("非 owner 拼接", SELF_TEST_CODE, f'var d := "{root[:11]}" + "{root[11:]}/x"\n', True),
                 ("非 owner 行尾注释", SELF_TEST_CODE, f'var d := base  # 默认 {root}\n', False),
                 ("非 owner .py 文档串", "tools/_host_paths_selftest.py", f'"""默认根 {root}"""\nX = 1\n', False),
                 ("非 owner .md", SELF_TEST_DOC, f"默认落 `{root}`\n", False)]
        bad = [w + ("该红没红" if want else "不该红却红") for w, rel, text, want in cases if bool(judge(rel, text)) != want]
        check(not bad, f"{root}：owner 代码行绿；非 owner 代码行、拼接写法红；非 owner 行尾注释、.py 文档串、.md 绿"
              + ("" if not bad else "——" + "；".join(bad)))


def repo_files():
    """(已跟踪, 未跟踪未忽略) 的文件，路径相对仓库根。"""
    def git(*args):
        p = subprocess.run(["git", *args, "-z"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
        return [f for f in p.stdout.decode("utf-8").split("\0") if f]
    try:
        return git("ls-files"), git("ls-files", "--others", "--exclude-standard")
    except (OSError, subprocess.CalledProcessError):
        skip = {".git", ".godot", "__pycache__"}
        out = []
        for d, ds, fs in os.walk(ROOT):
            ds[:] = [x for x in ds if x not in skip]
            out += [os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/") for f in fs]
        return sorted(out), []


def read_text(rel):
    """文本内容；读不到 / 二进制 → None。"""
    try:
        with open(os.path.join(ROOT, rel), "rb") as f:
            raw = f.read()
    except OSError:
        return None
    if b"\0" in raw:
        return None
    return raw.decode("utf-8", errors="replace")


def segments(rel, text):
    """[(代码段, 注释 / 文档段)]，逐行；非代码文件整行算文档（切法见 tools/path_scan.py）。"""
    lines = text.splitlines()
    spans = path_scan.comment_spans(rel, text)
    if spans is None:
        return [("", ln) for ln in lines]
    return [path_scan.split(ln, spans.get(n)) for n, ln in enumerate(lines, 1)]


def tokens(seg):
    """一段里的命中串：原文与拼接折后各扫一遍，按串取并集（同一处不重复算）。"""
    raw = Counter(m.group(0) for m in PAT.finditer(seg))
    folded = Counter(m.group(0) for m in PAT.finditer(path_scan.fold(seg))) if seg.strip() else Counter()
    return list((raw | folded).elements())


def hits(rel):
    """[(行号, 行, 命中串, 是否文档 / 注释段)]；读不到 / 二进制 → None。本脚本按行排除 SAMPLES 块（lane cs21）。"""
    text = read_text(rel)
    if text is None:
        return None
    hs = hits_text(rel, text)
    if rel == SELF:
        block, why = self_block()
        if check(block is not None, f"{SELF}：自扫按行排除 SAMPLES 块 {len(block or ())} 行"
                 + ("" if block is not None else f"——{why}；整份照扫")):
            hs = [h for h in hs if h[0] not in block]
    return hs


def hits_text(rel, text):
    """[(行号, 行, 命中串, 是否文档 / 注释段)]，rel 只用来判代码 / 文档（切法见 tools/path_scan.py）。"""
    lines = text.splitlines()
    if not any(tokens(ln) for ln in lines):  # 整行（原文 / 折后）都不中就不必切注释（切 .py 要 tokenize + ast，全仓逐个切太慢）
        return []
    out = []
    for n, (ln, (code, doc)) in enumerate(zip(lines, segments(rel, text)), 1):
        out += [(n, ln, t, False) for t in tokens(code)] + [(n, ln, t, True) for t in tokens(doc)]
    return out


def offending(rel, hs):
    """不合规的命中：不是登记的仓外根，或是登记的根却写在非 owner 的代码行里。"""
    return [h for h in hs if h[2] not in ROOTS or (not h[3] and rel not in ROOTS[h[2]]["owners"] and rel != SELF)]


def show(rel, hs, limit=6):
    for n, ln, tok, _ in hs[:limit]:
        print(f"      {rel}:{n}  {ln.strip()[:140]}  ← {tok}")
    if len(hs) > limit:
        print(f"      …另 {len(hs) - limit} 处")


def main(argv):
    unknown = [a for a in argv if a not in ("--check",)]
    if unknown:
        print(__doc__)
        print(f"未知参数：{' '.join(unknown)}", file=sys.stderr)
        return 2
    tracked, untracked = repo_files()
    tset = set(tracked)

    print("零、样本自检（lane cs21：模式表回退 / 改窄了、owner 判断与 path_scan 切法 / 折叠改坏了在这里先红）")
    sample_selftest()

    print("一、仓外根登记（ROOTS）都有效")
    for root, r in ROOTS.items():
        for own in r["owners"]:
            text = read_text(own) if own in tset else None
            if text is None:
                check(False, f"{root}：owner {own} 不在 / 没跟踪，条目失效（改 owners 或删条目）")
                continue
            code = [c for c, _ in segments(own, text) if c.strip()]
            has_root = any(root in tokens(c) for c in code)
            has_env = any(r["env"] in c for c in code)
            check(has_root and has_env, f"{root}：owner {own} 代码里写这个默认根、可由 ${r['env']} 覆盖"
                  + ("" if has_root else "——代码里已不写它（条目失效：删掉，或挪到新 owner）")
                  + ("" if has_env else f"——代码里找不到 {r['env']}（覆盖口子没了，默认根就成了写死）"))

    print(f"二、git 已跟踪文件里的本机路径（模式 {len(PATTERNS)} 条：{'、'.join(n for n, _, _ in PATTERNS)}）")
    scanned = 0
    stray = []
    doc_n = {root: 0 for root in ROOTS}
    for rel in tracked:
        hs = hits(rel)
        if hs is None:
            continue
        scanned += 1
        bad = offending(rel, hs)
        for h in hs:
            if h[3] and h[2] in ROOTS:
                doc_n[h[2]] += 1
        if bad:
            stray.append((rel, bad))
    for root, r in ROOTS.items():
        print(f"  · {root}：文档 / 注释 {doc_n[root]} 处（不判红；{r['why']}）")
    for rel, hs in stray:
        roots_in_code = sorted({t for _, _, t, _ in hs if t in ROOTS})
        check(False, f"{rel}：{len(hs)} 处本机路径不合规"
              + (f"（代码行写死仓外根 {'、'.join(roots_in_code)}，改走 owner / 环境变量）" if roots_in_code else "")
              + "（仓库根 → `--path .` / 仓库相对路径，家目录 → `~/…`，引擎 → PATH / $GODOT）")
        show(rel, hs)
    check(not stray, f"登记外 {sum(len(h) for _, h in stray)} 处命中（扫 {scanned} 个已跟踪文本文件，含本脚本、其 SAMPLES 块除外{'' if SELF in tset else '——本脚本未跟踪、没算进来'}）"
          + (f"：{len(stray)} 个文件" if stray else ""))

    for rel in untracked:
        hs = offending(rel, (hits(rel) if rel != SELF else None) or [])
        if hs:
            print(f"  ⚠ 未跟踪：{rel} 有 {len(hs)} 处本机路径不合规（不判红；提交前按上面口径改，否则跟踪后即红）")
            show(rel, hs, 3)
    return report()


def report():
    print()
    print("结果：全部通过" if not fails else f"结果：{len(fails)} 项问题")
    for m in fails:
        print("   ✗ " + m.splitlines()[0])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
