#!/usr/bin/env python3
"""拍板清单行号自检 + 自动跟号（lane dec3 立；lane dec4 加跟号 / --fix）：清单里反引号内的每处「文件:行」，
核它在工作树里还在不在、指的还是不是锚定提交那一行的内容；挪了位的，算出新号。

  python3 tools/check_decision_refs.py                  # 查 docs/待策划拍板清单_2026-09-28.md；有问题退 1
  python3 tools/check_decision_refs.py 清单.md          # 查别的清单（同一套写法）
  python3 tools/check_decision_refs.py --anchor REV     # 不用清单头部写的锚，改按 REV 比对（例：按旧锚看挪了多少）
  python3 tools/check_decision_refs.py --show           # 逐处印出所引行的原文，供回读
  python3 tools/check_decision_refs.py --fix            # 自动跟号：跟得上的改成新号、头部锚改成 HEAD，跟不上的打「跟号待核」
  python3 tools/check_decision_refs.py --since REV      # 重锚自证：REV 版清单里的引用，改到新行号后指的还是不是同一段内容

锚：清单头部「行号：……按 HEAD `xxxxxxx`」那个提交。清单里写的行号，都是那个提交里的行号。
判红：
  · NOFILE：引的文件在工作树里不存在，且跟号也找不到它的去处（裸文件名 `Main.gd:12` 按 git 已跟踪文件的文件名找，
    找不到或不止一个也算）；
  · OOR：行号超出文件行数（工作树里，或锚定提交里）；
  · DRIFT：锚定提交里那几行，和工作树里同一行号的内容不一样了——多半是别的 lane 拆 / 改了文件，行号挪了位。
    每处都会跟号（见下），印成「可跟号 → 新号（凭什么）」或「跟不上」加线索；
  · 待核：清单里还留着 --fix 打的「〔跟号待核：…〕」标记（人工回读、改号后删掉标记才算过）。
跟号（lane dec4）：锚里那段在工作树里的新位置，按下面顺序找，头一个找到的算：
  ① diff：`git diff 锚 -- 文件` 里这几行没动过，照 diff 的增删把行号推过去（重名行也不会认错）；
  ② 同文件原文：那段原文在锚里和工作树里都只出现一次；
  ③ 按函数名：那段在锚里所在的 `func` / `def` / md 标题，在工作树里找到同名函数（Main.gd 拆出去的照 tools/main_splits.txt
     的改名表找拆出件里的新函数名），函数体里按「去首尾空白；.gd 去掉 `main.` 前缀、`static func` 当 `func`、
     函数头照改名表换名」只对上一处（.gd 函数体到下一处顶层声明为止，多行字符串里顶格的行不算）；
  ④ 跨文件原文：同后缀的仓内文件里，归一化后的那段在锚里本文件、工作树全仓都只出现一次（太短的行不认，免得撞车）。
  都找不到就是「跟不上」：印出所在函数现在在哪、同偏移是哪行、函数体里最像的一行（顶层散代码给同文件最像的几行），交人工。
--fix：先要求所引文件在工作树里和 HEAD 一致（没提交的改动先提交，不然新锚对不上）。跟得上的全改成新号
  （搬到别的文件的改写成全路径，后面挂在它身上的裸 `:行` 也按需补全路径），跟不上的在引用后面插「〔跟号待核：锚 X 里是 文件:行〕」，
  头部锚改成 HEAD，再按新锚复查一遍。有「待核」就退 1。
--since REV（改行号那一片自证用）：取 REV 里的清单和它头部的锚，把新旧两版的引用配对（先按「同一清单行骨架 +
  行内序号」配，只改了号 / 搬了文件的靠这一步配上；改了文字的行再按文件名序列对齐），对上的每一对都要
  「旧锚里旧行号那段 == 工作树里新行号那段」（.gd 按上面的归一化比，搬进拆出件的函数头照改名表比），不等判红（MISMATCH：行号改错了，或有意换了所指——后者在 Verify 里写明）；
  新版多出来的引用只计数，要 --show 人工回读。
  · 改号自证（lane auditfix1，默认跑，--since 时不跑）：和上一版清单（工作树改了没提交 → HEAD 版；否则 → 最近改清单那个提交的父版）
    按 --since 的口径配对，「旧锚旧号那段 == 本版锚本版号那段」，不等且旧那段原文在新处文件里还找得到 → MISMATCH（号写歪了）。
    锚 = HEAD 时，号写歪了锚里那行和工作树同号那行照样一致，DRIFT 看不出来，靠这一步。旧那段原文已找不到（所指那段自己被改写，
    --fix 给「跟不上」的多是这种）只记 ⚠ 改指未验，不判红——人工回读、改号是 --fix 流程本来就要做的。
    有意把引用换指别处（旧那段还在）的，同一行括注「原文作 `:旧号`」认账（原文作括注本就不查，见下）。
不判红：
  · 「原文作 `:N`」括注里的行号：清单有意保留的原稿旧行号，跳过（从「原文作」到下一个「）」「，」「；」为止）；
  · 仓外 brief（`lane-*.md` / `COORDINATION*.md`，在 $NK1_BRIEFS，默认 /workspace/nk1-agent-briefs）：只查行号不越界，不跟号；
    brief 目录不存在时只记 ⚠。
解析口径：一个反引号 token 若是「路径[:行]」（或简称 `终局系统化 :30`，按文件名前缀唯一找）就记为当前文件；
同一行里后面的裸 `:行` 挂在最近的文件上——反引号外的文字点了别的文件名、后面却跟裸 `:行` 的，本脚本会挂错，
清单里这种地方写全路径（`--show` 回读时看得出来）。
为什么不把清单改成「按符号名」锚（lane dec4 评估）：清单里六成引用是 md / json 行（没有函数名可锚），
而且策划要的是点得开的 `文件:行`；函数名也会改（拆出件把 `_setup_yamen` 改成 `setup_yamen`）。所以清单照旧写行号，
符号名只当跟号的线索（③），由脚本把行号跟上。
改了清单所引文件（拆 Main / 改 check_symbols 之类）的 lane，收尾跑本脚本：红了就 --fix，回读「待核」，提交清单。
lane auditfix1 起进必跑门禁（一键跑末条，docs/GATES.md §三.22）：dec3 入库后没进注册表，自 cs14 `a8ff603` 起主干一直红
（到 `abb3f05` 积了 DRIFT 47）没人看见。任何 lane 挪动所引文件的行都会让它红，这正是它要报的；--fix 只认已提交的文件，
所以改了所引文件的 lane 先提交代码，再 --fix、回读「待核」、另提一笔清单（拆 Main 的与 gen_main_splits --write 补哈希同一笔），
两笔同一次落地，一键跑以第二笔之后的 rc 为准。
  python3 tools/check_decision_refs.py --json           # 机读（同 docs/GATES.md §二）
"""
import argparse, difflib, os, re, subprocess, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)
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
MARK = re.compile(r"〔跟号待核：[^〕]*〕")
ANCHOR = re.compile(r"(行号：[^\n]*?按 HEAD `)([0-9a-f]{7,40})(`)")
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
FUNC_GD = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(")
DECL_GD = re.compile(r"^(?:static\s+)?(?:const|var|enum|signal)\s+(\w+)")
# .gd 顶层声明：函数体到下一处顶层声明为止（多行字符串里顶格的行不算）
TOP_GD = re.compile(r"^(?:static\s+|@\w+(?:\([^)]*\))?\s+)*(?:func|var|const|signal|enum|class|class_name|extends)\b")
DEF_PY = re.compile(r"^(\s*)(?:async\s+)?(?:def|class)\s+(\w+)")
HEAD_MD = re.compile(r"^(#{1,6})\s+(.*\S)")
MIN_CROSS = 16  # ④ 跨文件认原文：归一化后这么多字以下的段不认


def git(*args):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def offrepo(path):
    return path.startswith("lane-") or path.startswith("COORDINATION")


def span_str(a, b):
    return f"{a}-{b}" if b != a else f"{a}"


def parse_doc(lines):
    """逐行解析引用。返回 (refs, skipped, toks)：
    refs = [(清单行号, 文件, 起, 止, token 下标)]；toks[清单行号] = 该行 token 列表
    （dict：kind=file/label/bare、span=含反引号的区间、name=文件写法、a/b=行号或 None、old=在「原文作」里）。"""
    refs, skipped, toks = [], 0, {}
    for ln, line in enumerate(lines, 1):
        old = [m.span() for m in OLD_NOTE.finditer(line)]
        cur, row = None, []
        for m in TOKEN.finditer(line):
            s = m.group(1).strip()
            in_old = any(a <= m.start() < b for a, b in old)
            fm, lm, bm = FILEREF.match(s), LABEL.match(s), BARE.match(s)
            if fm:
                cur = fm.group(1)
                t = dict(kind="file", name=cur, g=fm)
            elif lm:
                cur = "@" + lm.group(1)
                t = dict(kind="label", name=cur, g=lm)
            elif bm and cur:
                t = dict(kind="bare", name=cur, g=bm)
            else:
                continue
            g = t.pop("g")
            num = 2 if t["kind"] != "bare" else 1
            t.update(span=m.span(), old=in_old,
                     a=int(g.group(num)) if g.group(num) else None,
                     b=int(g.group(num + 1) or g.group(num)) if g.group(num) else None)
            row.append(t)
            if t["a"] is None:
                continue
            if in_old:
                skipped += 1
                continue
            refs.append((ln, cur, t["a"], t["b"], len(row) - 1))
        if row:
            toks[ln] = row
    return refs, skipped, toks


def parse_refs(lines):
    """[(清单行号, 文件, 起, 止)]，另返回跳过的「原文作」处数（dec3 的接口，照旧留着）。"""
    refs, skipped, _ = parse_doc(lines)
    return [r[:4] for r in refs], skipped


def anchor_of(text):
    m = ANCHOR.search(text)
    return m.group(2) if m else None


def ext_of(path):
    return path.rsplit(".", 1)[-1] if "." in os.path.basename(path) else ""


def norm(line, ext):
    s = line.strip()
    if ext == "gd":
        s = re.sub(r"\bmain\.", "", re.sub(r"^static\s+func\b", "func", s))
    return re.sub(r"\s+", " ", s)


def find_seg(hay, seg, lo=0, hi=None):
    hi = len(hay) if hi is None else hi
    n = len(seg)
    return [i + 1 for i in range(lo, hi - n + 1) if hay[i:i + n] == seg]


class Repo:
    def __init__(self):
        tracked = (git("-c", "core.quotePath=false", "ls-files") or "").splitlines()
        self.tracked = set(tracked)
        self.by_name = {}
        for p in tracked:
            self.by_name.setdefault(os.path.basename(p), []).append(p)
        self.cache = {}

    def resolve(self, f):
        """(路径, 错误)；仓外 brief 原样返回。"""
        if offrepo(f) or "/" in f:
            return f, None
        cand = self.by_name.get(f, []) if not f.startswith("@") else \
            [p for n, ps in self.by_name.items() if n.startswith(f[1:]) for p in ps]
        if len(cand) != 1:
            return None, "裸文件名在已跟踪文件里" + ("找不到" if not cand else "不唯一：" + " / ".join(cand))
        return cand[0], None

    def work(self, path):
        if ("W", path) not in self.cache:
            base = BRIEFS if offrepo(path) else ROOT
            fp = os.path.join(base, path)
            self.cache[("W", path)] = open(fp, encoding="utf-8", errors="replace").read().splitlines() \
                if os.path.isfile(fp) else None
        return self.cache[("W", path)]

    def at_rev(self, rev, path):
        if (rev, path) not in self.cache:
            s = git("show", f"{rev}:{path}")
            self.cache[(rev, path)] = s.splitlines() if s is not None else None
        return self.cache[(rev, path)]

    def candidates(self, ext):
        """工作树里同后缀的仓内文件（已跟踪 + 未跟踪未忽略，拆出件还没提交也找得到）。"""
        if ("C", ext) not in self.cache:
            out = git("-c", "core.quotePath=false", "ls-files", "--cached", "--others", "--exclude-standard") or ""
            self.cache[("C", ext)] = sorted({p for p in out.splitlines() if ext_of(p) == ext})
        return self.cache[("C", ext)]

    def hunks(self, anchor, path):
        if ("D", anchor, path) not in self.cache:
            out = git("-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "--histogram",
                      "-U0", anchor, "--", path) or ""
            hs = []
            for l in out.splitlines():
                m = HUNK.match(l)
                if m:
                    hs.append((int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1),
                               int(m.group(3)), int(m.group(4) if m.group(4) is not None else 1)))
            self.cache[("D", anchor, path)] = hs
        return self.cache[("D", anchor, path)]

    def map_line(self, anchor, path, L):
        """锚里 path 第 L 行在工作树里的行号；那行被改 / 删了返回 None。"""
        off = 0
        for s, n, _t, m in self.hunks(anchor, path):
            if n == 0:  # 纯插入：插在旧第 s 行之后
                if L > s:
                    off += m
                    continue
                break
            if L < s:
                break
            if L <= s + n - 1:
                return None
            off += m - n
        return L + off

    def splits(self):
        """Main.gd 拆出件改名表 {Main 函数名: (拆出件, 新函数名)}，读工作树的 tools/main_splits.txt。"""
        if "S" not in self.cache:
            tab = {}
            for l in self.work("tools/main_splits.txt") or []:
                cols = l.split("\t")
                if l.startswith("#") or len(cols) < 5:
                    continue
                for pair in cols[4].split():
                    if "→" in pair:
                        old, new = pair.split("→", 1)
                        tab[old] = (cols[0], new)
            self.cache["S"] = tab
        return self.cache["S"]


def enclosing(lines, a, ext):
    """锚里第 a 行所在的符号：(类别, 名字, 定义行号)；顶层散行 / 不认识的后缀返回 None。"""
    if ext == "gd":
        m = DECL_GD.match(lines[a - 1])
        if m:
            return ("decl", m.group(1), a)
        for i in range(a - 1, -1, -1):
            t = lines[i]
            m = FUNC_GD.match(t)
            if m:
                return ("func", m.group(1), i + 1)
            if i != a - 1 and TOP_GD.match(t):
                return None
    elif ext == "py":
        ind = len(lines[a - 1]) - len(lines[a - 1].lstrip())
        for i in range(a - 1, -1, -1):
            m = DEF_PY.match(lines[i])
            if m and (i == a - 1 or len(m.group(1)) < ind):
                return ("func", m.group(2), i + 1)
    elif ext == "md":
        for i in range(a - 1, -1, -1):
            m = HEAD_MD.match(lines[i])
            if m:
                return ("head", lines[i].strip(), i + 1)
    return None


def body_end(lines, start, kind, ext):
    """符号从第 start 行起的体到哪一行为止（含）。"""
    if kind == "decl":
        return start
    if ext == "md":
        lv = len(HEAD_MD.match(lines[start - 1]).group(1))
        for i in range(start, len(lines)):
            m = HEAD_MD.match(lines[i])
            if m and len(m.group(1)) <= lv:
                return i
        return len(lines)
    if ext == "py":
        ind = len(lines[start - 1]) - len(lines[start - 1].lstrip())
        for i in range(start, len(lines)):
            t = lines[i]
            if t.strip() and not t.lstrip().startswith("#") and len(t) - len(t.lstrip()) <= ind:
                return i
        return len(lines)
    for i in range(start, len(lines)):
        if TOP_GD.match(lines[i]):
            while i > start and (not lines[i - 1].strip() or lines[i - 1].startswith("#")):
                i -= 1  # 紧贴下一个函数的空行 / 注释不算本函数体
            return i
    return len(lines)


def locate(repo, path, sym, ext):
    """工作树里这个符号可能的落点 [(路径, 定义行号, 体末行号, 说明, 改名 (旧, 新) 或 None)]：同文件 → 拆出件改名表 → 全仓唯一同名。"""
    kind, name, _ = sym
    out = []

    def defs(p, nm):
        w = repo.work(p) or []
        if kind == "head":
            return [i + 1 for i, t in enumerate(w) if t.strip() == nm]
        pat = FUNC_GD if (ext == "gd" and kind == "func") else DECL_GD if ext == "gd" else None
        hits = []
        for i, t in enumerate(w):
            if pat:
                m = pat.match(t)
                if m and m.group(1) == nm:
                    hits.append(i + 1)
            else:
                m = DEF_PY.match(t)
                if m and m.group(2) == nm:
                    hits.append(i + 1)
        return hits

    for d in defs(path, name):
        out.append((path, d, body_end(repo.work(path), d, kind, ext), f"同文件 {name}", None))
    if ext == "gd" and kind == "func" and path == "scripts/Main.gd" and name in repo.splits():
        sp, nn = repo.splits()[name]
        for d in defs(sp, nn):
            out.append((sp, d, body_end(repo.work(sp), d, kind, ext), f"拆出件 {name}→{nn}", (name, nn)))
    if not out and kind != "head":
        glob = [(p, d) for p in repo.candidates(ext) if p != path for d in defs(p, name)]
        if len(glob) == 1:
            p, d = glob[0]
            out.append((p, d, body_end(repo.work(p), d, kind, ext), f"全仓唯一 {name}", None))
    return out


def track(repo, anchor, path, a, b):
    """锚里 path:a-b 那段在工作树里的去处。
    跟得上：(新路径, 新起, 新止, 凭什么)；跟不上：(None, 线索)。"""
    old = repo.at_rev(anchor, path)
    seg = old[a - 1:b]
    ext = ext_of(path)
    w = repo.work(path)
    if w is not None:
        mapped = [repo.map_line(anchor, path, L) for L in range(a, b + 1)]
        if all(x is not None for x in mapped) and mapped == list(range(mapped[0], mapped[0] + b - a + 1)):
            return (path, mapped[0], mapped[-1], "diff")
        pos = find_seg(w, seg)
        if len(pos) == 1 and len(find_seg(old, seg)) == 1:
            return (path, pos[0], pos[0] + b - a, "同文件原文唯一")
    nseg = [norm(x, ext) for x in seg]
    hints = []
    sym = enclosing(old, a, ext)
    if sym:
        k = a - sym[2]
        for p, d, e, why, ren in locate(repo, path, sym, ext):
            wl = repo.work(p)
            nb = [norm(x, ext) for x in wl[d - 1:e]]
            want = nseg if not ren else [renamed(x, repo, p) for x in nseg]
            pos = find_seg(nb, want)
            if len(pos) == 1:
                na = d - 1 + pos[0]
                return (p, na, na + b - a, f"按函数（{why}）")
            best = max(((difflib.SequenceMatcher(None, want[0], x).ratio(), d + i) for i, x in enumerate(nb) if x),
                       default=(0, None))
            hint = f"{why} 现在在 {p}:{d}（锚里在 :{sym[2]}，同偏移 :{d + k}"
            if best[1] and best[0] >= 0.6:
                hint += f"，体里最像的一行 :{best[1]} 相似 {best[0]:.2f}"
            hints.append(hint + "）")
        if not hints:
            hints.append(f"所在 {sym[0]} `{sym[1]}`（锚里 :{sym[2]}）工作树里找不到")
    if sum(len(x) for x in nseg) >= MIN_CROSS:
        nold = [norm(x, ext) for x in old]
        if len(find_seg(nold, nseg)) == 1:
            hits = []
            for p in repo.candidates(ext):
                wl = repo.work(p)
                if wl is None:
                    continue
                hits += [(p, i) for i in find_seg([norm(x, ext) for x in wl], nseg)]
                if len(hits) > 1:
                    break
            if len(hits) == 1:
                p, i = hits[0]
                return (p, i, i + b - a, "跨文件归一化唯一")
    if not hints and w is not None and nseg[0]:
        sims = []
        for i, x in enumerate(w):
            x = norm(x, ext)
            sm = difflib.SequenceMatcher(None, nseg[0], x)
            if x and sm.real_quick_ratio() >= 0.6 and sm.quick_ratio() >= 0.6:
                r = sm.ratio()
                if r >= 0.6:
                    sims.append((r, i + 1))
        sims.sort(key=lambda t: (-t[0], t[1]))
        if sims:
            hints.append("没有所在函数可循；同文件最像的行 " + "、".join(f":{i} 相似 {r:.2f}" for r, i in sims[:3]))
    return (None, "；".join(hints) or "工作树里找不到原内容，也没有所在函数可循")


def check(o, doc_text, repo, anchor, quiet=False):
    """逐处核引用。返回 (计数 dict, 跟号结果 {refs 下标: (新路径, 新起, 新止, 凭什么) | (None, 线索)}, refs, toks)。"""
    say = (lambda *_: None) if quiet else print
    lines = doc_text.splitlines()
    refs, skipped, toks = parse_doc(lines)
    n = dict(bad=0, drift=0, auto=0, manual=0, brief=0, marks=0, skipped=skipped, refs=len(refs))
    fixes = {}
    warned_briefs = False
    for k, (ln, f, a, b, _ti) in enumerate(refs):
        tag = f"L{ln} `{f}:{span_str(a, b)}`"
        if offrepo(f):
            n["brief"] += 1
            if not os.path.isdir(BRIEFS):
                if not warned_briefs:
                    say(f"  ⚠ brief 目录 {BRIEFS} 不存在，仓外引用只跳过不判")
                    warned_briefs = True
                continue
        path, err = repo.resolve(f)
        if err:
            say(f"  ✗ NOFILE {tag}：{err}")
            n["bad"] += 1
            continue
        w = repo.work(path)
        old = None if offrepo(f) else repo.at_rev(anchor, path)
        if w is None and old is None:
            say(f"  ✗ NOFILE {tag}：{path} 不存在")
            n["bad"] += 1
            continue
        if w is not None and (a < 1 or b < a or b > len(w)) and (offrepo(f) or old is None):
            say(f"  ✗ OOR {tag}：{path} 只有 {len(w)} 行")
            n["bad"] += 1
            continue
        if o.show and w is not None and b <= len(w):
            for i in range(a, b + 1):
                say(f"    {tag} → {path}:{i}: {w[i - 1].strip()[:140]}")
        if offrepo(f):
            continue
        if old is None:
            say(f"  ✗ DRIFT {tag}：锚 {anchor} 里没有 {path}（新文件？把头部的锚改到含它的提交）")
            n["drift"] += 1
            n["manual"] += 1
            fixes[k] = (None, "锚里没有这个文件")
            continue
        if a < 1 or b < a or b > len(old):
            say(f"  ✗ OOR {tag}：锚 {anchor} 里 {path} 只有 {len(old)} 行")
            n["bad"] += 1
            continue
        if w is not None and w[a - 1:b] == old[a - 1:b]:
            continue
        n["drift"] += 1
        t = track(repo, anchor, path, a, b)
        fixes[k] = t
        gone = "工作树里没有这个文件了" if w is None else "该处内容变了"
        if t[0]:
            n["auto"] += 1
            where = (f"{t[0]}:" if t[0] != path else ":") + span_str(t[1], t[2])
            say(f"  ✗ DRIFT {tag}：{path} {gone}；可跟号 → {where}（{t[3]}）")
        else:
            n["manual"] += 1
            say(f"  ✗ DRIFT {tag}：{path} {gone}；跟不上，要人工：{t[1]}")
    for ln, line in enumerate(lines, 1):
        for m in MARK.finditer(line):
            n["marks"] += 1
            say(f"  ✗ 待核 L{ln}：{m.group(0)}（回读、改号后删掉这个标记）")
    say(f"  锚 {anchor}：引用 {n['refs']} 处（仓外 brief {n['brief']} 处只查越界），"
        f"跳过「原文作」{skipped} 处；NOFILE/OOR {n['bad']}，DRIFT {n['drift']}"
        f"（可自动跟号 {n['auto']}、要人工 {n['manual']}），待核标记 {n['marks']}")
    return n, fixes, refs, toks


def render(line, row, targets, repo):
    """按新目标重写一行里的引用 token。targets[token 下标] = (新路径, 新起, 新止) 或 ("MARK", 标记文字)。
    改指了别的文件的写全路径；后面原本挂在旧文件上的裸 `:行`，挂不上了就补全路径（解析口径见 docstring）。"""
    out, pos, cur = [], 0, None
    for ti, t in enumerate(row):
        s, e = t["span"]
        out.append(line[pos:s])
        pos = e
        orig = repo.resolve(t["name"])[0]
        tgt, mark = targets.get(ti), ""
        if tgt and tgt[0] == "MARK":
            tgt, mark = None, tgt[1]
        p, num = (tgt[0], span_str(tgt[1], tgt[2])) if tgt else (orig, None)
        if t["kind"] == "bare":
            if p == cur:
                txt = f"`:{num}`" if tgt else line[s:e]
            else:
                txt = f"`{p}:{num or span_str(t['a'], t['b'])}`"
        elif not tgt:
            txt = line[s:e]
        elif p == orig:
            txt = f"`{t['name']}:{num}`" if t["kind"] == "file" else f"`{t['name'][1:]} :{num}`"
        else:
            txt = f"`{p}:{num}`"
        out.append(txt + mark)
        cur = p
    out.append(line[pos:])
    return "".join(out)


def do_fix(o, text, repo, anchor):
    n, fixes, refs, toks = check(o, text, repo, anchor)
    if not n["drift"]:
        print("--fix：没有 DRIFT，不用改")
        return 0 if not (n["bad"] or n["marks"]) else 1
    head = (git("rev-parse", "--short=7", "HEAD") or "").strip()
    paths = sorted({repo.resolve(f)[0] for _, f, *_ in refs if not offrepo(f) and repo.resolve(f)[0]}
                   | {t[0] for t in fixes.values() if t[0]})
    dirty = git("-c", "core.quotePath=false", "status", "--porcelain", "--", *paths)
    if dirty is None or dirty.strip():
        print("--fix：所引文件在工作树里和 HEAD 不一致，新锚会对不上；先提交代码再跑 --fix：")
        print("".join("    " + l + "\n" for l in (dirty or "").splitlines()[:12]), end="")
        return 1
    lines = text.splitlines(keepends=True)
    by_line = {}
    for k, t in fixes.items():
        ln, f, a, b, ti = refs[k]
        path = repo.resolve(f)[0]
        by_line.setdefault(ln, {})[ti] = t[:3] if t[0] else \
            ("MARK", f"〔跟号待核：锚 {anchor} 里是 {path}:{span_str(a, b)}〕")
    print(f"--fix：锚 {anchor} → {head}；改号 {n['auto']} 处，打「待核」{n['manual']} 处")
    for ln in sorted(by_line):
        body = lines[ln - 1].rstrip("\n")
        new = render(body, toks[ln], by_line[ln], repo)
        lines[ln - 1] = new + lines[ln - 1][len(body):]
        for ti, tgt in sorted(by_line[ln].items()):
            t = toks[ln][ti]
            print(f"    L{ln} `{t['name']}:{span_str(t['a'], t['b'])}` → " +
                  (f"`{tgt[0]}:{span_str(tgt[1], tgt[2])}`" if tgt[0] != "MARK" else tgt[1]))
    new_text = ANCHOR.sub(lambda m: m.group(1) + head + m.group(3), "".join(lines), count=1)
    with open(o.doc, "w", encoding="utf-8") as fh:
        fh.write(new_text)
    print(f"--fix：已写 {os.path.relpath(o.doc, ROOT)}，按新锚 {head} 复查：")
    n2, *_ = check(argparse.Namespace(show=False), new_text, Repo(), head)
    return 1 if (n2["bad"] or n2["drift"] or n2["marks"]) else 0


def renamed(x, repo, split):
    """归一化后的一行若是 Main 函数头、且该函数按改名表搬进了 split，换成拆出件里的新名字。"""
    m = FUNC_GD.match(x)
    if m and repo.splits().get(m.group(1), ("",))[0] == split:
        return f"func {repo.splits()[m.group(1)][1]}" + x[m.end(1):]
    return x


def skeleton(line):
    return MARK.sub("", TOKEN.sub("§", line))


def since(o, repo, refs, lines, rev=None, new_rev=None, label=None):
    """rev 版清单（缺省 o.since）的引用与本版逐对比内容，返回 MISMATCH 数（取不到 rev 版清单返回 None）。
    new_rev：本版引用按这个提交里的内容比（改号自证传本版头部的锚），缺省比工作树（--since）；
    传了 new_rev 的，内容不同而旧锚那段原文在新处文件里已经找不到（所指那段自己被改写了）只记 ⚠、不判红。"""
    rev = rev or o.since
    label = label or f"--since {rev}"
    rel = os.path.relpath(os.path.abspath(o.doc), ROOT)
    old_text = git("show", f"{rev}:{rel}")
    old_anchor = old_text and anchor_of(old_text)
    if not old_anchor:
        print(f"  ✗ {label}：取不到 {rel} 或它头部的锚")
        return None
    old_lines = old_text.splitlines()
    old_refs, _ = parse_refs(old_lines)
    refs = [r[:4] for r in refs]
    # 第一轮：按「同一清单行骨架（引用 token 抹掉）+ 行内序号」配对，两边都唯一才配——只改了号 / 改指别的文件的，靠这一步配上
    def keys(rs, ls):
        out = {}
        for idx, r in enumerate(rs):
            key = (skeleton(ls[r[0] - 1]), sum(1 for x in rs[:idx] if x[0] == r[0]))
            out.setdefault(key, []).append(idx)
        return {k: v[0] for k, v in out.items() if len(v) == 1}
    ko, kn = keys(old_refs, old_lines), keys(refs, lines)
    pairs = [(ko[k], kn[k]) for k in ko.keys() & kn.keys()]
    # 第二轮：剩下的（改了文字的行）按文件名序列对齐（dec3 口径）
    po, pn = {i for i, _ in pairs}, {j for _, j in pairs}
    ro = [i for i in range(len(old_refs)) if i not in po]
    rn = [j for j in range(len(refs)) if j not in pn]
    sm = difflib.SequenceMatcher(None, [old_refs[i][1] for i in ro], [refs[j][1] for j in rn], autojunk=False)
    pairs += [(ro[i + k], rn[j + k]) for i, j, n in sm.get_matching_blocks() for k in range(n)]
    # 同一行里同一文件新插了一处引用时，按文件名对齐会错位：先看同一行里还没对上的新引用有没有正好是旧内容的
    unpaired = set(range(len(refs))) - {j for _, j in pairs}
    same = moved = mismatch = marked = rewritten = acked = 0

    def new_lines(p):
        return repo.at_rev(new_rev, p) if new_rev else repo.work(p)

    def content(k):
        p, e = repo.resolve(refs[k][1])
        w = new_lines(p) if not e else None
        return [norm(x, ext_of(p)) for x in w[refs[k][2] - 1:refs[k][3]]] if w is not None else None
    for i, j in pairs:
        ol, f, oa, ob = old_refs[i]
        if offrepo(f):
            continue
        path, err = repo.resolve(f)
        if err:
            continue
        ov = repo.at_rev(old_anchor, path)
        if ov is None:
            continue
        want = [norm(x, ext_of(path)) for x in ov[oa - 1:ob]]
        np_ = repo.resolve(refs[j][1])[0]
        if path == "scripts/Main.gd" and np_ != path:  # 搬进拆出件的，函数头照改名表比
            want = [renamed(x, repo, np_) for x in want]
        if content(j) != want:
            alt = [k for k in sorted(unpaired) if refs[k][0] == refs[j][0] and content(k) == want]
            if not alt:
                if f"里是 {path}:{span_str(oa, ob)}〕" in lines[refs[j][0] - 1]:
                    marked += 1
                    continue
                tag = f"L{refs[j][0]} `{refs[j][1]}:{span_str(refs[j][2], refs[j][3])}`（旧版 L{ol} `{f}:{span_str(oa, ob)}` @ {old_anchor}）"
                if new_rev:
                    # 改号自证（lane auditfix1）：旧锚那段原文在新处文件里还找得到 → 号改歪了；找不到 → 那段自己被改写，只能人工回读；
                    # 有意换了所指的，本行括注「原文作 `:旧号`」认账
                    nl = [norm(x, ext_of(np_)) for x in (new_lines(np_) or [])]
                    still = find_seg(nl, want)
                    line = lines[refs[j][0] - 1]
                    old_ref = span_str(oa, ob)
                    noted = {m.group(1).strip() for a, b in (x.span() for x in OLD_NOTE.finditer(line))
                             for m in TOKEN.finditer(line[a:b])}
                    if noted & {f":{old_ref}", f"{f}:{old_ref}", f"{path}:{old_ref}"}:
                        acked += 1
                        continue
                    if not still:
                        rewritten += 1
                        print(f"  ⚠ 改指未验 {tag}：旧锚那段在 {new_rev} 的 {np_} 里已找不到原文（所指那段被改写过），人工回读过就不用管")
                        continue
                    mismatch += 1
                    print(f"  ✗ MISMATCH {tag}：两处内容不同，旧锚那段原文在 {new_rev} 里还在 {np_}:"
                          + "、:".join(span_str(i, i + ob - oa) for i in still[:3]) + "——行号改歪了？")
                    continue
                mismatch += 1
                print(f"  ✗ MISMATCH {tag}：两处内容不同")
                continue
            unpaired.discard(alt[0])
            unpaired.add(j)
            j = alt[0]
        if (repo.resolve(refs[j][1])[0], refs[j][2], refs[j][3]) == (path, oa, ob):
            same += 1
        else:
            moved += 1
    print(f"  {label}（旧锚 {old_anchor}{f' → 新锚 {new_rev}' if new_rev else ''}）：对上 {same + moved + mismatch + marked + rewritten + acked} 对（仓外 brief 不比），行号没变 {same}、"
          f"改了行号且内容一致 {moved}、MISMATCH {mismatch}、所在行带「待核」不比 {marked}"
          + (f"、所指那段被改写（⚠ 改指未验）{rewritten}、括注「原文作」认账改指 {acked}" if new_rev else "") + "；"
          f"新版多出 {len(unpaired)} 处引用（--show 回读）")
    return mismatch


def prev_rev(doc):
    """改号自证的比对基准：工作树里的清单和 HEAD 版不同 → HEAD；相同 → 最近一次改清单那个提交的父版。
    返回 (rev | None, 说明)；None = 没有可比的上一版（清单首版 / 还没提交 / 浅克隆取不到父版）。"""
    rel = os.path.relpath(os.path.abspath(doc), ROOT)
    head_text = git("show", f"HEAD:{rel}")
    if head_text is None:
        return None, "清单还没提交过"
    if head_text != open(doc, encoding="utf-8").read():
        return "HEAD", "工作树里的清单改过、未提交：对 HEAD 版"
    c = (git("log", "-1", "--format=%h", "--", rel) or "").strip()
    if not c or git("rev-parse", "--verify", "-q", c + "^") is None:
        return None, "取不到最近改清单那个提交的父版（浅克隆？）"
    if git("show", f"{c}^:{rel}") is None:
        return None, f"清单是 {c} 新建的，没有上一版"
    return c + "^", f"清单最近改于 {c}：对它的父版"


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("doc", nargs="?", default=DEFAULT_DOC)
    ap.add_argument("--anchor", help="比对用的提交（缺省取清单头部「按 HEAD `…`」）")
    ap.add_argument("--since", help="重锚自证：和 REV 版清单逐对比内容")
    ap.add_argument("--show", action="store_true", help="逐处印出所引行原文")
    ap.add_argument("--fix", action="store_true", help="自动跟号并把头部锚改成 HEAD（所引文件须已提交）")
    o = ap.parse_args()

    text = open(o.doc, encoding="utf-8").read()
    anchor = o.anchor or anchor_of(text)
    if not anchor:
        print("  ✗ 清单头部没有「行号：……按 HEAD `提交`」，用 --anchor 指定")
        return 1
    if git("rev-parse", "--verify", "-q", anchor + "^{commit}") is None:
        print(f"  ✗ 锚 {anchor} 不是本仓的提交")
        return 1
    repo = Repo()
    if o.fix:
        if o.anchor or o.since:
            print("  ✗ --fix 只按清单头部的锚改，别和 --anchor / --since 一起用")
            return 1
        return do_fix(o, text, repo, anchor)

    n, _fixes, refs, _toks = check(o, text, repo, anchor)
    mismatch = 0
    if o.since:
        mismatch = since(o, repo, refs, text.splitlines())
        if mismatch is None:
            return 1
    else:
        # 改号自证（lane auditfix1）：锚 = HEAD 时清单里的号写歪了，锚里那行和工作树同号那行照样一致，上面的 DRIFT 看不出来；
        # 所以再和上一版清单逐对比：旧锚旧号那段 == 本版锚本版号那段
        rev, why = prev_rev(o.doc)
        if rev is None:
            print(f"  ⚠ 改号自证跳过：{why}")
        else:
            mismatch = since(o, repo, refs, text.splitlines(), rev=rev, new_rev=anchor, label=f"改号自证 [{why}]")
            if mismatch is None:
                return 1

    if n["bad"] or n["drift"] or n["marks"] or mismatch:
        how = []
        if n["bad"] or n["drift"] or n["marks"]:
            how.append("DRIFT 先跑 --fix 自动跟号；「要人工」「待核」的回读后改号、删标记，再提交清单")
        if mismatch and not o.since:
            how.append("MISMATCH 是本版清单的号和上一版指的不是同一段：改回提示的号；确是有意换了所指，在那处引用后括注「原文作 `:旧号`」")
        print(f"结果：有问题（{'；'.join(how) or '见上'}）")
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
