#!/usr/bin/env python3
"""拍板清单行号自检（lane dec3；口径沿用 lane dec2 的比对脚本）：清单里反引号内的每处「文件:行」，
核它在工作树里还在不在、指的还是不是锚定提交那一行的内容。

  python3 tools/check_decision_refs.py                  # 查 docs/待策划拍板清单_2026-09-28.md；有问题退 1
  python3 tools/check_decision_refs.py 清单.md          # 查别的清单（同一套写法）
  python3 tools/check_decision_refs.py --anchor REV     # 不用清单头部写的锚，改按 REV 比对（例：按旧锚看挪了多少）
  python3 tools/check_decision_refs.py --show           # 逐处印出所引行的原文，供回读
  python3 tools/check_decision_refs.py --since REV      # 重锚自证：REV 版清单里的引用，改到新行号后指的还是不是同一段内容

锚：清单头部「行号：……按 HEAD `xxxxxxx`」那个提交。清单里写的行号，都是那个提交里的行号。
判红：
  · NOFILE：引的文件在工作树里不存在（裸文件名 `Main.gd:12` 按 git 已跟踪文件的文件名找，找不到或不止一个也算）；
  · OOR：行号超出文件行数（工作树里，或锚定提交里）；
  · DRIFT：锚定提交里那几行，和工作树里同一行号的内容不一样了——多半是别的 lane 拆 / 改了文件，行号挪了位。
    会顺带印出那段内容在工作树里的新位置（找得到的话），照着改清单，再把头部的锚改成当前 HEAD。
--since REV（改行号那一片自证用）：取 REV 里的清单和它头部的锚，把新旧两版的引用按文件名序列对齐，
  对上的每一对都要「旧锚里旧行号那段 == 工作树里新行号那段」，不等判红（MISMATCH：行号改错了，或有意换了所指——
  后者在 Verify 里写明）；新版多出来的引用只计数，要 --show 人工回读。
不判红：
  · 「原文作 `:N`」括注里的行号：清单有意保留的原稿旧行号，跳过（从「原文作」到下一个「）」「，」「；」为止）；
  · 仓外 brief（`lane-*.md` / `COORDINATION*.md`，在 $NK1_BRIEFS，默认 /workspace/nk1-agent-briefs）：只查行号不越界；
    brief 目录不存在时只记 ⚠。
解析口径：一个反引号 token 若是「路径[:行]」（或简称 `终局系统化 :30`，按文件名前缀唯一找）就记为当前文件；
同一行里后面的裸 `:行` 挂在最近的文件上——反引号外的文字点了别的文件名、后面却跟裸 `:行` 的，本脚本会挂错，
清单里这种地方写全路径（`--show` 回读时看得出来）。
改清单行号后跑本脚本到 rc=0；本脚本不进必跑门禁（任何 lane 挪动所引文件的行都会让它红，这正是它要报的）。
"""
import argparse, difflib, os, re, subprocess, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
DEFAULT_DOC = os.path.join(ROOT, "docs", "待策划拍板清单_2026-09-28.md")
BRIEFS = os.environ.get("NK1_BRIEFS", "/workspace/nk1-agent-briefs")

TOKEN = re.compile(r"`([^`]*?)`")
# 带目录的仓内路径 / 仓外 brief / 裸文件名；后面可带 :行 或 :行-行
FILEREF = re.compile(
    r"^((?:docs|scripts|tools|data|assets|\.claude)/[^\s`:：（）()]+"
    r"|lane-[A-Za-z0-9\-]+\.md|COORDINATION(?:_INDEX)?\.md"
    r"|[^\s`:：（）()/]+\.(?:gd|py|json|md|sh|txt|tscn|cfg|godot))"
    r"(?::(\d+)(?:-(\d+))?)?$")
BARE = re.compile(r"^:(\d+)(?:-(\d+))?$")
# 简称写法 `终局系统化 :30`：简称按已跟踪文件的文件名前缀找（唯一才算）
LABEL = re.compile(r"^([^\s`:：/]+) :(\d+)(?:-(\d+))?$")
OLD_NOTE = re.compile(r"原文作[^）；，]*")


def git(*args):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def offrepo(path):
    return path.startswith("lane-") or path.startswith("COORDINATION")


def parse_refs(lines):
    """[(清单行号, 文件, 起, 止)]，另返回跳过的「原文作」处数。"""
    refs, skipped = [], 0
    for ln, line in enumerate(lines, 1):
        old = [m.span() for m in OLD_NOTE.finditer(line)]
        cur = None
        for m in TOKEN.finditer(line):
            s = m.group(1).strip()
            in_old = any(a <= m.start() < b for a, b in old)
            fm = FILEREF.match(s)
            if fm:
                cur = fm.group(1)
                if fm.group(2):
                    if in_old:
                        skipped += 1
                    else:
                        a = int(fm.group(2))
                        refs.append((ln, cur, a, int(fm.group(3) or a)))
                continue
            lm = LABEL.match(s)
            if lm:
                cur = "@" + lm.group(1)
                if in_old:
                    skipped += 1
                else:
                    a = int(lm.group(2))
                    refs.append((ln, cur, a, int(lm.group(3) or a)))
                continue
            bm = BARE.match(s)
            if bm and cur:
                if in_old:
                    skipped += 1
                    continue
                a = int(bm.group(1))
                refs.append((ln, cur, a, int(bm.group(2) or a)))
    return refs, skipped


def anchor_of(text):
    m = re.search(r"行号：[^\n]*?按 HEAD `([0-9a-f]{7,40})`", text)
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("doc", nargs="?", default=DEFAULT_DOC)
    ap.add_argument("--anchor", help="比对用的提交（缺省取清单头部「按 HEAD `…`」）")
    ap.add_argument("--since", help="重锚自证：和 REV 版清单逐对比内容")
    ap.add_argument("--show", action="store_true", help="逐处印出所引行原文")
    o = ap.parse_args()

    text = open(o.doc, encoding="utf-8").read()
    lines = text.splitlines()
    anchor = o.anchor or anchor_of(text)
    if not anchor:
        print("  ✗ 清单头部没有「行号：……按 HEAD `提交`」，用 --anchor 指定")
        return 1
    if git("rev-parse", "--verify", "-q", anchor + "^{commit}") is None:
        print(f"  ✗ 锚 {anchor} 不是本仓的提交")
        return 1

    tracked = (git("-c", "core.quotePath=false", "ls-files") or "").splitlines()
    by_name = {}
    for p in tracked:
        by_name.setdefault(os.path.basename(p), []).append(p)

    def resolve(f):
        """(路径, 错误)；仓外 brief 原样返回。"""
        if offrepo(f) or "/" in f:
            return f, None
        cand = by_name.get(f, []) if not f.startswith("@") else \
            [p for n, ps in by_name.items() if n.startswith(f[1:]) for p in ps]
        if len(cand) != 1:
            return None, "裸文件名在已跟踪文件里" + ("找不到" if not cand else "不唯一：" + " / ".join(cand))
        return cand[0], None

    cache = {}

    def work(path):
        if ("W", path) not in cache:
            base = BRIEFS if offrepo(path) else ROOT
            fp = os.path.join(base, path)
            cache[("W", path)] = open(fp, encoding="utf-8", errors="replace").read().splitlines() \
                if os.path.isfile(fp) else None
        return cache[("W", path)]

    def at_rev(rev, path):
        if (rev, path) not in cache:
            s = git("show", f"{rev}:{path}")
            cache[(rev, path)] = s.splitlines() if s is not None else None
        return cache[(rev, path)]

    refs, skipped = parse_refs(lines)
    bad = drift = brief_n = 0
    warned_briefs = False
    for ln, f, a, b in refs:
        tag = f"L{ln} `{f}:{a}" + (f"-{b}`" if b != a else "`")
        if offrepo(f):
            brief_n += 1
            if not os.path.isdir(BRIEFS):
                if not warned_briefs:
                    print(f"  ⚠ brief 目录 {BRIEFS} 不存在，仓外引用只跳过不判")
                    warned_briefs = True
                continue
        path, err = resolve(f)
        if err:
            print(f"  ✗ NOFILE {tag}：{err}")
            bad += 1
            continue
        w = work(path)
        if w is None:
            print(f"  ✗ NOFILE {tag}：{path} 不存在")
            bad += 1
            continue
        if a < 1 or b < a or b > len(w):
            print(f"  ✗ OOR {tag}：{path} 只有 {len(w)} 行")
            bad += 1
            continue
        if o.show:
            for i in range(a, b + 1):
                print(f"    {tag} → {path}:{i}: {w[i - 1].strip()[:140]}")
        if offrepo(f):
            continue
        old = at_rev(anchor, path)
        if old is None:
            print(f"  ✗ DRIFT {tag}：锚 {anchor} 里没有 {path}（新文件？把头部的锚改到含它的提交）")
            drift += 1
            continue
        if b > len(old):
            print(f"  ✗ OOR {tag}：锚 {anchor} 里 {path} 只有 {len(old)} 行")
            bad += 1
            continue
        seg = old[a - 1:b]
        if w[a - 1:b] == seg:
            continue
        pos = [i + 1 for i in range(len(w) - len(seg) + 1) if w[i:i + len(seg)] == seg]
        where = "、".join(f":{p}" + (f"-{p + b - a}" if b != a else "") for p in pos[:4]) or "工作树里找不到原内容"
        print(f"  ✗ DRIFT {tag}：{path} 该处内容变了；锚里那段现在在 {where}")
        drift += 1

    print(f"  锚 {anchor}：引用 {len(refs)} 处（仓外 brief {brief_n} 处只查越界），"
          f"跳过「原文作」{skipped} 处；NOFILE/OOR {bad}，DRIFT {drift}")

    mismatch = 0
    if o.since:
        rel = os.path.relpath(os.path.abspath(o.doc), ROOT)
        old_text = git("show", f"{o.since}:{rel}")
        old_anchor = old_text and anchor_of(old_text)
        if not old_anchor:
            print(f"  ✗ --since {o.since}：取不到 {rel} 或它头部的锚")
            return 1
        old_refs, _ = parse_refs(old_text.splitlines())
        sm = difflib.SequenceMatcher(None, [r[1] for r in old_refs], [r[1] for r in refs], autojunk=False)
        pairs = [(i + k, j + k) for i, j, n in sm.get_matching_blocks() for k in range(n)]
        # 同一行里同一文件新插了一处引用时，按文件名对齐会错位：先看同一行里还没对上的新引用有没有正好是旧内容的
        unpaired = set(range(len(refs))) - {j for _, j in pairs}
        same = moved = 0
        for i, j in pairs:
            ol, f, oa, ob = old_refs[i]
            if offrepo(f):
                continue
            path, err = resolve(f)
            if err:
                continue
            ov = at_rev(old_anchor, path)
            if ov is None:
                continue
            want = ov[oa - 1:ob]

            def content(k):
                p, e = resolve(refs[k][1])
                w = work(p) if not e else None
                return w[refs[k][2] - 1:refs[k][3]] if w is not None else None
            if content(j) != want:
                alt = [k for k in sorted(unpaired) if refs[k][0] == refs[j][0]
                       and resolve(refs[k][1])[0] == path and content(k) == want]
                if not alt:
                    mismatch += 1
                    print(f"  ✗ MISMATCH L{refs[j][0]} `{f}:{refs[j][2]}`（旧版 L{ol} `:{oa}` @ {old_anchor}）：两处内容不同")
                    continue
                unpaired.discard(alt[0])
                unpaired.add(j)
                j = alt[0]
            if (oa, ob) == refs[j][2:]:
                same += 1
            else:
                moved += 1
        print(f"  --since {o.since}（旧锚 {old_anchor}）：对上 {same + moved + mismatch} 对（仓外 brief 不比），行号没变 {same}、"
              f"改了行号且内容一致 {moved}、MISMATCH {mismatch}；新版多出 {len(unpaired)} 处引用（--show 回读）")

    if bad or drift or mismatch:
        print("结果：有问题（照上面 ✗ 行改清单行号，改完把头部锚改成当前 HEAD）")
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
