#!/usr/bin/env python3
"""docs 索引自检（lane doc4）：docs/README.md 是 docs/ 的唯一索引，本脚本核它与 docs/ 下的文件对得上。

  python3 tools/check_docs_index.py --check   # 自检（不带开关同）；有问题退 1
  python3 tools/check_docs_index.py --json    # 机读（同 docs/GATES.md §二）

判红：
  · MISSING：git 已跟踪的 docs/**/*.md（README.md 本身除外）没在 README 里以 `[…](路径)` 链到；
  · DEAD：README 里的相对链接指向的文件不存在（`#锚点` 去掉再查；http / mailto 不查）；
  · DUP：README 里同一路径链了不止一次。
只看 git 已跟踪的文档（与 gates_md 的 tools_gd 同口径：别的 lane 没提交的新文档不染红共用树）；
工作树里未跟踪的 docs/*.md 只记 ⚠、不判红。git 不可用时退回扫盘。
新增 / 挪删 docs 下的 .md：在 docs/README.md 对应分组补 / 改一行，再跑本脚本。
"""
import os, re, subprocess, sys
from urllib.parse import unquote

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

DOCS = os.path.join(ROOT, "docs")
INDEX = os.path.join(DOCS, "README.md")
LINK = re.compile(r"\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")

fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def doc_files():
    """(已跟踪, 未跟踪) 的 docs 下 .md，路径相对 docs/，README.md 除外。"""
    def git(*args):
        p = subprocess.run(["git", *args, "-z", "--", "docs"], cwd=ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, check=True)
        return [f for f in p.stdout.decode("utf-8").split("\0") if f]
    try:
        tracked = git("ls-files")
        untracked = git("ls-files", "--others", "--exclude-standard")
    except (OSError, subprocess.CalledProcessError):
        tracked = [os.path.relpath(os.path.join(d, f), ROOT) for d, _, fs in os.walk(DOCS) for f in fs]
        untracked = []

    def keep(fs):
        out = [os.path.relpath(os.path.join(ROOT, f), DOCS).replace(os.sep, "/") for f in fs if f.endswith(".md")]
        return sorted(f for f in out if f != "README.md" and os.path.isfile(os.path.join(DOCS, f)))
    return keep(tracked), keep(untracked)


def index_links(text):
    """README 里的相对链接：[(行号, 规范化后相对 docs/ 的路径, 原文)]。"""
    out = []
    for n, ln in enumerate(text.splitlines(), 1):
        for m in LINK.finditer(ln):
            raw = m.group(1)
            if re.match(r"^[a-z][a-z0-9+.-]*:", raw, re.I) or raw.startswith("#"):
                continue
            path = unquote(raw.split("#", 1)[0])
            out.append((n, os.path.normpath(path).replace(os.sep, "/"), raw))
    return out


def main(argv):
    unknown = [a for a in argv if a not in ("--check",)]
    if unknown:
        print(__doc__)
        print(f"未知参数：{' '.join(unknown)}", file=sys.stderr)
        return 2
    print("一、docs/README.md")
    try:
        with open(INDEX, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        check(False, f"docs/README.md 读不到：{e}")
        return report()
    links = index_links(text)
    check(bool(links), f"索引里有链接（{len(links)} 条）")

    print("二、索引里的路径都存在")
    dead = [f"L{n} {raw}" for n, p, raw in links if not os.path.exists(os.path.join(DOCS, p))]
    check(not dead, "索引链接都指向存在的文件" + (f"；DEAD：{', '.join(dead)}" if dead else f"（{len(links)} 条）"))
    seen, dup = {}, []
    for n, p, _ in links:
        if p in seen:
            dup.append(f"{p}（L{seen[p]} / L{n}）")
        seen.setdefault(p, n)
    check(not dup, "索引里没有重复链接" + (f"；DUP：{', '.join(dup)}" if dup else ""))

    print("三、docs 下每份 .md 都在索引里")
    tracked, untracked = doc_files()
    missing = [f for f in tracked if f not in seen]
    check(not missing, f"git 已跟踪的 docs/**/*.md 都在索引里（{len(tracked)} 份，README.md 除外）"
          + (f"；MISSING：{', '.join(missing)}（在 docs/README.md 补一行）" if missing else ""))
    for f in untracked:
        print(f"  ⚠ 未跟踪：docs/{f}" + ("（已在索引里）" if f in seen else "（不在索引里；提交前在 docs/README.md 补一行）"))
    return report()


def report():
    print()
    print("结果：全部通过" if not fails else f"结果：{len(fails)} 项问题")
    for m in fails:
        print("   ✗ " + m.splitlines()[0])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
