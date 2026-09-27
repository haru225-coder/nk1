#!/usr/bin/env python3
"""RefsHostPath（lane gd22）：仓库里不许写本机 Linux 绝对路径（家目录、/workspace 下的仓库根），RefsMacPath 的本机版。

  python3 tools/check_host_paths.py          # 自检；有问题退 1
  python3 tools/check_host_paths.py --json   # 机读（同 docs/GATES.md §二）

为什么：仓库根写死成 /workspace/<仓库>，照抄的命令在隔离 worktree / 软链 / 换机后会悄悄跑主树或直接找不到。
仓库内一律 `--path .`（工作目录为仓库根）、引擎走 PATH / $GODOT，家目录写 `~/…`。
扫什么：git 已跟踪的全部文本文件（读工作树里的内容，已暂存的新文件也算；含 NUL 字节的二进制跳过）。
本脚本自身也扫：PATTERNS 写成 `/home/<用户>` 这类占位不会命中，只放过 ROOTS 登记行里的仓外根（当 owner 看）。
判红：
  · 命中 `/home/<用户>` 或 `/workspace/<目录>`，且不是 ROOTS 登记的仓外根（仓库根本身不在 ROOTS 里，一律红）；
  · ROOTS 登记的仓外根出现在代码行里（.gd / .py / .sh / .gdshader 去掉注释与 .py 文档串），而文件不是该根的 owner——
    代码只许 owner 写一次默认值，其余走 owner / 环境变量（截图根走 ShotGate.out_dir，简报目录读 $NK1_BRIEFS）；
  · ROOTS 条目失效：owner 不在 / 不再跟踪、owner 代码里不再写这个根、owner 里找不到登记的环境变量名。
文档与注释里写仓外根不红（说明默认值落在哪，本来就该写全）。
工作树里未跟踪的文件有命中只记 ⚠、不判红，与 check_mac_paths / check_docs_index 同口径；git 不可用时退回扫盘。
不在此列：Godot 节点路径 `/root/…`、`~/.local/…` 这类家目录相对写法、`/tmp/…`。
"""
import ast, os, re, subprocess, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

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
CODE_EXT = (".gd", ".py", ".sh", ".gdshader")

fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


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


def doc_lines(rel, text):
    """不算代码的行号：非代码文件全算；代码文件里 `#` / `//` 开头的注释行，.py 另加各级文档串。"""
    lines = text.splitlines()
    if not rel.endswith(CODE_EXT):
        return set(range(1, len(lines) + 1))
    out = {n for n, ln in enumerate(lines, 1) if ln.lstrip().startswith(("#", "//"))}
    if rel.endswith(".py"):
        try:
            tree = ast.parse(text)
        except (SyntaxError, ValueError):
            return out
        for node in ast.walk(tree):
            body = getattr(node, "body", None)
            if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                    and isinstance(getattr(body[0], "value", None), ast.Constant) and isinstance(body[0].value.value, str):
                out |= set(range(body[0].lineno, body[0].end_lineno + 1))
    return out


def hits(rel):
    """[(行号, 行, 命中串, 是否文档 / 注释行)]；读不到 / 二进制 → None。"""
    text = read_text(rel)
    if text is None:
        return None
    docs = None
    out = []
    for n, ln in enumerate(text.splitlines(), 1):
        for m in PAT.finditer(ln):
            if docs is None:
                docs = doc_lines(rel, text)
            out.append((n, ln, m.group(0), n in docs))
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

    print("一、仓外根登记（ROOTS）都有效")
    for root, r in ROOTS.items():
        for own in r["owners"]:
            text = read_text(own) if own in tset else None
            if text is None:
                check(False, f"{root}：owner {own} 不在 / 没跟踪，条目失效（改 owners 或删条目）")
                continue
            docs = doc_lines(own, text)
            code = [ln for n, ln in enumerate(text.splitlines(), 1) if n not in docs]
            has_root = any(root in ln for ln in code)
            has_env = any(r["env"] in ln for ln in code)
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
    check(not stray, f"登记外 {sum(len(h) for _, h in stray)} 处命中（扫 {scanned} 个已跟踪文本文件，含本脚本{'' if SELF in tset else '——本脚本未跟踪、没算进来'}）"
          + (f"：{len(stray)} 个文件" if stray else ""))

    for rel in untracked:
        hs = offending(rel, hits(rel) or [])
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
