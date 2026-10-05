#!/usr/bin/env python3
"""拍板清单行号自检 + 自动跟号（lane dec3 立；lane dec4 加跟号 / --fix）：清单里反引号内的每处「文件:行」，
核它在工作树里还在不在、指的还是不是锚定提交那一行的内容；挪了位的，算出新号。

  python3 tools/check_decision_refs.py                  # 查 docs/待策划拍板清单_2026-09-28.md；有问题退 1
  python3 tools/check_decision_refs.py 清单.md          # 查别的清单（同一套写法）
  python3 tools/check_decision_refs.py --anchor REV     # 不用清单头部写的锚，改按 REV 比对（例：按旧锚看挪了多少）
  python3 tools/check_decision_refs.py --show           # 逐处印出所引行的原文，供回读
  python3 tools/check_decision_refs.py --fix            # 自动跟号：跟得上的改成新号、头部锚改成 HEAD，跟不上的打「跟号待核」
  python3 tools/check_decision_refs.py --since REV      # 重锚自证：REV 版清单里的引用，改到新行号后指的还是不是同一段内容

两种引用写法（lane w26-k5；b1 遗留③：只认行号的写法，改动落在引用行之前的插入 / 删除都会把它连带平移）：
  · 行号锚 `文件:行`（老写法，行为一字不变）：内容比对随清单头部锚，行号由跟号 / --fix 跟上；
  · 符号锚 `文件::符号`（`scripts/WorldMap.gd::COMBAT_FIRE_DELAY`）：按锚定提交里那个符号的定义行核——.gd 认 const / var /
    enum / signal 声明与 func，.py 认 def / class，.md 认标题行；行号跟工作树现址走，定义行照补，符号挪几行 / 挪到别处都
    照样对得上，锚文件里改别处不报 DRIFT；符号在工作树里找不到 → DRIFT「找不到」（不猜落点、--fix 打「待核」交人工）。
    挂法与行号锚同：同一行里后面的裸 `::符号` 挂在最近的文件上；「原文作」括注里的符号锚同样跳过。

锚：清单头部「行号：……按 HEAD `xxxxxxx`」那个提交。清单里写的行号，都是那个提交里的行号。
判红：
  · NOFILE：引的文件在工作树里不存在，且跟号也找不到它的去处（裸文件名 `Main.gd:12` 按 git 已跟踪文件的文件名找，
    找不到或不止一个也算）；
  · OOR：行号超出文件行数（工作树里，或锚定提交里）；
  · DRIFT：锚定提交里那几行，和工作树里同一行号的内容不一样了——多半是别的 lane 拆 / 改了文件，行号挪了位。
    每处都会跟号（见下），印成「可跟号 → 新号（凭什么）」或「跟不上」加线索；
  · 待核：清单里还留着 --fix 打的「〔跟号待核：…〕」标记（人工回读、改号后删掉标记才算过）；
  · 锚悬空（lane w53-12）：头部锚在本仓查得到、却不在 HEAD 的历史上。lane 跑 --fix 打的锚是 lane 自己的提交，主控 rebase
    落地后那个 SHA 悬空：本机各 worktree 共用对象库照样查得到、原先本脚本照绿，新克隆 / origin 上却「不是本仓的提交」退 1
    （main 上 107 版清单有 28 版的锚不在自己的历史上；b241992 / f3f092e / 1665423 三回带着它推上 origin，10-03 07:15–16:11 新克隆一直红）。
    修法 --fix（没有 DRIFT 也把锚改到 HEAD）；--anchor 指定的锚不查这条。
跟号（lane dec4）：锚里那段在工作树里的新位置，按下面顺序找，头一个找到的算：
  ① diff：`git diff 锚 -- 文件` 里这几行没动过，照 diff 的增删把行号推过去（重名行也不会认错）；
  ② 同文件原文：那段原文在锚里和工作树里都只出现一次；
  ③ 按函数名：那段在锚里所在的 `func` / `def` / md 标题，在工作树里找到同名函数（Main.gd 拆出去的照 tools/main_splits.txt
     的改名表找拆出件里的新函数名），函数体里按「去首尾空白；.gd 去掉 `main.` 前缀、`static func` 当 `func`、
     函数头照改名表换名」只对上一处（.gd 函数体到下一处顶层声明为止，多行字符串里顶格的行不算）；
  ④ 跨文件原文：同后缀的仓内文件里，归一化后的那段在锚里本文件、工作树全仓都只出现一次（太短的行不认，免得撞车）。
  都找不到就是「跟不上」：印出所在函数现在在哪、同偏移是哪行、函数体里最像的一行（顶层散代码给同文件最像的几行），交人工。
  穿透一行转发（lane auditfix6）：锚里那段在一支真函数里，落点（① ~ ④ 找到的、或原号原文都没动）所在的 .gd 函数却只剩一行转发
  （判据就是 func_body.forward_of，与 check_symbols 十三节 / verify_economy 十一节同一份）——拆走一刀后函数头原样留在 Main、
  体搬进拆出件，diff 会把函数头跟到转发上，原号没挪的连 DRIFT 都不报。现在顺转发走到真体（`_K.fn` 按 preload 常量、
  `Crew.fn` 按 autoload / class_name、`fn` / `self.fn` 在本文件，最多 4 跳），在真体里重找那段（含函数头的段只比头之后几行，
  头认真体那支的头——换了名、多了 main 形参）；③ 按名找到的那支是转发的，也先穿透再比。找到印「穿透一行转发 …」可跟号，
  穿透不下去（目标解析不到 / 那段在真体里对不上）印「跟到一行转发」交人工，都判红，不许静默落在转发上。
  锚里那支本来就是转发的（清单有意指着转发，如 EA6-4 的 `scripts/Main.gd:1781`）不穿透。
  零、转发穿透自检：每次先在内存里造一对锚 / 工作树跑 10 种形状（见 _ST_CASES + S10），不过就退 1——穿透逻辑被改坏，必跑门禁先红。
  零之二、ledger_refs_mutants 落点预检（lane w19-g8）：ledger_refs_mutants（台账格式硬校验 / 本脚本输出确定序的变异对照）全量要
    git worktree、约 40 s，只能是 lane 档；它的变异锚在台账第四 / 五 / 十一刀节、前三刀段、gen_main_splits 的调用行、本脚本的两处排序、
    本清单的 `scripts/Main.gd:N` 引用上，这些被别的片挪了（auditfix7 W8 同形），全量红着没人跑。所以每次在内存里逐格试落
    （ledger_refs_mutants.landing()：不落盘、不建 worktree、不跑 gen，约 0.1 s），落不上计入问题、退 1；--fix 时不跑。
    关断开关 --no-ledger-landing 只给 ledger_refs_mutants 在变异过的 worktree 里用，一键跑命令里不许带（gates_md 逐条比）。
--fix：先要求所引文件在工作树里和 HEAD 一致（没提交的改动先提交，不然新锚对不上）。跟得上的全改成新号
  （搬到别的文件的改写成全路径，后面挂在它身上的裸 `:行` 也按需补全路径），跟不上的在引用后面插「〔跟号待核：锚 X 里是 文件:行〕」，
  头部锚改成 HEAD，再按新锚复查一遍。有「待核」就退 1。锚悬空的（见上），没有 DRIFT 也照样改锚到 HEAD（lane w53-12）。
--since REV（改行号那一片自证用）：取 REV 里的清单和它头部的锚，把新旧两版的引用配对（先按「同一清单行骨架 +
  行内序号」配，只改了号 / 搬了文件的靠这一步配上；改了文字的行再按文件名序列对齐），对上的每一对都要
  「旧锚里旧行号那段 == 工作树里新行号那段」（.gd 按上面的归一化比，搬进拆出件的函数头照改名表比；旧那段所在函数已成一行转发的，
  只认穿透算出的那一行，别的号判 MISMATCH），不等判红（MISMATCH：行号改错了，或有意换了所指——后者在 Verify 里写明）；
  新版多出来的引用只计数，要 --show 人工回读。
  · 改号自证（lane auditfix1，默认跑，--since 时不跑）：和上一版清单（工作树改了没提交 → HEAD 版；否则 → 最近改清单那个提交的父版）
    按 --since 的口径配对，「旧锚旧号那段 == 本版锚本版号那段」，不等且旧那段原文在新处文件里还找得到 → MISMATCH（号写歪了）。
    锚 = HEAD 时，号写歪了锚里那行和工作树同号那行照样一致，DRIFT 看不出来，靠这一步。旧那段原文已找不到（所指那段自己被改写，
    --fix 给「跟不上」的多是这种）只记 ⚠ 改指未验，不判红——人工回读、改号是 --fix 流程本来就要做的。
    有意把引用换指别处（旧那段还在）的，同一行括注「原文作 `:旧号`」认账（原文作括注本就不查，见下）。
    上一版清单的锚在本仓取不到（悬空锚改掉之后的新克隆里就是这样）印一行「⚠ 改号自证 […]：没比成」、不判红——原先逐对取不到旧锚的
    内容就跳过，静默印「对上 0 对」照绿（lane w53-12）；--since 指定的旧版锚取不到则判红（比不了）。
不判红：
  · 「原文作 `:N`」括注里的行号：清单有意保留的原稿旧行号，跳过（从「原文作」到下一个「）」「，」「；」为止）；
  · 仓外 brief（`lane-*.md` / `COORDINATION*.md`，在 $NK1_BRIEFS，默认 /workspace/nk1-agent-briefs）：只查行号不越界，不跟号；
    brief 目录不存在时只记 ⚠。
解析口径：一个反引号 token 若是「路径[:行]」「路径::符号」（或简称 `终局系统化 :30`，按文件名前缀唯一找）就记为当前文件；
同一行里后面的裸 `:行` / `::符号` 挂在最近的文件上——反引号外的文字点了别的文件名、后面却跟裸 `:行` 的，本脚本会挂错，
清单里这种地方写全路径（`--show` 回读时看得出来）。
输出确定序（lane cs23）：逐处的 ⚠ / ✗ 行（NOFILE / OOR / DRIFT 跟号 / 待核 / MISMATCH / 改指未验）先收齐、再按
「清单行号 → 行内第几处引用 → 类别」排好印（--show 的原文行跟在所属引用的 DRIFT 前，待核标记排在全部引用之后）；
--since / 改号自证的新旧配对也按新版引用的清单顺序逐对比。原先配对取 `ko.keys() & kn.keys()`（集合，遍历顺序随
PYTHONHASHSEED 变），有 2 处以上 ⚠ / MISMATCH 时同一基连跑每次行序不同、「逐字节同」比对会偶发假 DIFF（lane cs18 待议 4）。
清零判竿格（lane w50-k4，无门禁 sweep 第二格 / w49-k4 同型）：正文行里实读的六处收收性计数格——`bad`（NOFILE/OOR）、
`drift`（DRIFT 总计）、`manual`（要人工）、`marks`（待核标记）、MISMATCH、`rewritten`（⚠ 改指未验）——逐格断言 = 0
（六格本都在判红路径里、竿断言在现存体系下静默绿；竿守的是「格位字面漂移 / 判红路径被退化」的元层——格位改了字、
或哪一格被摘出判红路径，竿位自检（Z-R1/Z-R2/Z-R3）先红）。『原文作』认账改指 `acked` 是设计内挂账认账格，
补竿即格位字面定定不许演化成判 0（判 0 是不允许的状态减法——自查判格 Z-R1 互证）。
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
sys.path.insert(0, TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    import gate_json; gate_json.maybe_json(__file__)
from func_body import forward_of  # 一行转发判据只有这一份（lane cs17 / gd23），本脚本不另起
DEFAULT_DOC = os.path.join(ROOT, "docs", "待策划拍板清单_2026-09-28.md")
BRIEFS = os.environ.get("NK1_BRIEFS", "/workspace/nk1-agent-briefs")

TOKEN = re.compile(r"`([^`]*?)`")
# 带目录的仓内路径 / 仓外 brief / 裸文件名；后面可带 :行、:行-行 或 ::符号（行号 / 符号至多一个；全角「：：」不算）
FILEREF = re.compile(
    r"^((?:docs|scripts|tools|data|assets|\.claude)/[^\s`:：（）()]+"
    r"|lane-[A-Za-z0-9\-]+\.md|COORDINATION(?:_INDEX)?\.md"
    r"|[^\s`:：（）()/]+\.(?:gd|py|json|md|sh|txt|tscn|cfg|godot))"
    r"(?::(\d+)(?:-(\d+))?|::([^\s:：]+))?$")
BARE = re.compile(r"^:(\d+)(?:-(\d+))?$")
BARESYM = re.compile(r"^::([^\s:：]+)$")
# 简称写法 `终局系统化 :30`：简称按已跟踪文件的文件名前缀找（唯一才算）
LABEL = re.compile(r"^([^\s`:：/]+) :(\d+)(?:-(\d+))?$")
OLD_NOTE = re.compile(r"原文作[^）；，]*")
MARK = re.compile(r"〔跟号待核：[^〕]*〕")
ANCHOR = re.compile(r"(行号：[^\n]*?按 HEAD `)([0-9a-f]{7,40})(`)")
# 符号锚的 defs() 按下面的模式找定义行（行号锚照旧走 diff / 原文 / 函数名 / 跨文件四条）
SYM_GD = re.compile(r"^(?:@(?:export(?:_\w+)?|onready|rpc|static(?:_var)?|tool|warn_deprecated)\b[^\n]*\n)*"
                    r"(?:static\s+)?(?:const|var|enum|signal)\s+(\w+)")
SYM_PY = re.compile(r"^\s*(?:async\s+)?(?:def|class)\s+(\w+)")
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
FUNC_GD = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(")
DECL_GD = re.compile(r"^(?:static\s+)?(?:const|var|enum|signal)\s+(\w+)")
# .gd 顶层声明：函数体到下一处顶层声明为止（多行字符串里顶格的行不算）
TOP_GD = re.compile(r"^(?:static\s+|@\w+(?:\([^)]*\))?\s+)*(?:func|var|const|signal|enum|class|class_name|extends)\b")
DEF_PY = re.compile(r"^(\s*)(?:async\s+)?(?:def|class)\s+(\w+)")
HEAD_MD = re.compile(r"^(#{1,6})\s+(.*\S)")
MIN_CROSS = 16  # ④ 跨文件认原文：归一化后这么多字以下的段不认
PRELOAD = r'^const\s+{}\b[^=\n]*=\s*preload\("res://([^"]+)"\)'
FWD_HOPS = 4  # 转发链最多走几跳（Main → 拆出件 → 再转一手）


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
    （dict：kind=file/label/bare/sym、span=含反引号的区间、name=文件写法、a/b=行号或 None、sym=符号名或 None、
    old=在「原文作」里）。行号锚照旧（a/b 起止）、符号锚 kind=sym、refs 的 (起, 止) 收工作树现址。"""
    refs, skipped, toks = [], 0, {}
    for ln, line in enumerate(lines, 1):
        old = [m.span() for m in OLD_NOTE.finditer(line)]
        cur, row = None, []
        for m in TOKEN.finditer(line):
            s = m.group(1).strip()
            in_old = any(a <= m.start() < b for a, b in old)
            fm, lm, bm, sm = FILEREF.match(s), LABEL.match(s), BARE.match(s), BARESYM.match(s)
            if fm and not fm.group(4):
                cur = fm.group(1)
                t = dict(kind="file", name=cur, g=fm)
            elif fm:
                cur = fm.group(1)
                t = dict(kind="sym", name=cur, sym=fm.group(4), g=fm)
            elif lm:
                cur = "@" + lm.group(1)
                t = dict(kind="label", name=cur, g=lm)
            elif (bm or sm) and cur:
                t = dict(kind="bare" if bm else "sym", name=cur, g=bm or sm)
                if sm:
                    t["sym"] = sm.group(1)
            else:
                continue
            g = t.pop("g")
            num = 2 if t["kind"] == "file" else 1
            if t["kind"] == "sym":
                t.update(span=m.span(), old=in_old, sym=t.get("sym"), a=None, b=None)
            else:
                t.update(span=m.span(), old=in_old, sym=t.get("sym"),
                         a=int(g.group(num)) if g.group(num) else None,
                         b=int(g.group(num + 1) or g.group(num)) if g.group(num) else None)
            row.append(t)
            if t["a"] is None and t["kind"] != "sym":
                continue
            if in_old:
                skipped += 1
                continue
            refs.append((ln, cur, t["a"] if t["kind"] != "sym" else 1, t["b"] if t["kind"] != "sym" else 1, len(row) - 1))
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


def anchor_state(anchor, run=git):
    """锚的三态（lane w53-12）：None = 在 HEAD 的历史上；"missing" = 本仓查不到；"off" = 查得到、却不在 HEAD 的历史上（悬空）。
    只查 rev-parse 的话，lane rebase 前的 SHA 在本机共用的对象库里照样查得到，悬空锚本机照绿、新克隆才红。run 自检时传假的。"""
    if run("rev-parse", "--verify", "-q", anchor + "^{commit}") is None:
        return "missing"
    return "off" if run("merge-base", "--is-ancestor", anchor, "HEAD") is None else None


# --list（lane w90-k3）：docs/GATES.md 生成块标记锚（字面 + 正则可编译性照 GATES.md 现帧三对必在）。
# is_generated 每次现读 GATES.md、按含标记锚的行定界——只取各锚首次命中（三对不嵌套；禁写死行号区间，咨牒 §五.4）。
GEN_MARKS = ("GATES:BEGIN", "GATES-BATCH:BEGIN", "GATES-CI:BEGIN")


def gen_mark_block(lines):
    """GATES.md 现帧含生成块锚的首个 enclosing 块，返回 (块名, 起行, 止行)；锚全删（焚净断言即按 GEN_MARKS 钉）→ None。
    块名 = BEGIN 锚字面（如 GATES-BATCH:BEGIN）；配对 = 同在 GEN_MARKS 的同族 BEGIN/END（按字面缝对）。"""
    marks = [(i, m) for i, x in enumerate(lines, 1) for m in GEN_MARKS if m in x]
    if not marks:
        return None
    i0, name = min(marks)
    stem = name.split(":")[0]
    ends = [j for j, x in enumerate(lines, 1) if j >= i0 and f"{stem}:END" in x]
    return (name, i0, ends[0] if ends else len(lines))


def is_generated(repo, path, a):
    """path 第 a 行是否落在 docs/GATES.md 的生成块里（现帧读标记锚定界，区间含注释标记行）。
    非 GATES.md / 锚被删（焚净断言按 GEN_MARKS 硬钉）→ False。红线：禁写死区间行号（w89-k6 咨牒 §五.4）。"""
    if path != "docs/GATES.md":
        return False
    w = repo.work("docs/GATES.md")
    if w is None:
        return False
    blk = gen_mark_block(w)
    return blk is not None and blk[1] <= a <= blk[2]


def list_lines(o, repo, refs, toks, fixes, say=print):
    """--list（lane w90-k3，w89-k6 咨牒案 (a) 主控裁准）：逐 DRIFT 一行 LIST 附列，gen 标记点名生成块内引用
    （这类跟号须走国道 --write 重建生成块、而非 --fix 手跟）。纯附加打印、零新增读盘（is_generated 现读的
    一份 GATES.md 走 repo.work 缓存）、零写盘；永不自称「通过」、不进判红路径（§五.2 防静默绿轨）。
    输出顺序与汇总前的逐处 DRIFT 行同序（清单行号升序）；零 DRIFT 印「LIST 无 DRIFT 可列」一行。"""
    for k in sorted(fixes):
        ln, f, a, b, ti = refs[k]
        src = repo.resolve(f)[0] or f
        t = fixes[k]
        tx = toks.get(ln) or []
        kind = tx[ti].get("kind", "line") if ti < len(tx) else "line"
        kind = "sym" if kind == "sym" else "line"
        if t[0]:
            tgt, auto, how, na = f"{t[0]}:{span_str(t[1], t[2])}", 1, t[3], t[1]
        else:
            tgt, auto, how, na = "—", 0, t[1], 0
        gen = 1 if src == "docs/GATES.md" and is_generated(repo, src, na or a) else 0
        note = f"(?{gen_mark_block(repo.work('docs/GATES.md') or [''])[0]})" if gen else ""
        say(f"  LIST L{ln} {kind} {src}:{span_str(a, b)} → {tgt}  auto={auto} gen={gen}{note}  how={how}")
    if not fixes:
        say("  LIST 无 DRIFT 可列")


# --list 自检内存样本（lane w90-k3；忆轨 w53-9 契约判据配样本自检 / GATES §五.3 轨）：
# 首条引用挪后仍落生成块内（gen 须 1、带 (?块名)）；次条挪到块外纯内容区（gen 须 0）；
# 块外次条落点在 END 锚下一行、判据 5 锚挪位面用 —— block 内有 drum-wave 纯内容行与锚行共同定界（禁写死区间）；
# 锚挪位与锚焚净两格硬钉：焚净不单删锚判断 —— 现帧 read list_lines 不再 gen=1、is_generated=False。
_ST_LIST_W = ("# aaaa bbbb\n"
              "# bbbb cccc\n"
              "# cccc dddd\n"
              "# dddd eeee\n"
              "# eeee ffff\n"
              "# ffff gggg\n"
              "# gggg hhhh\n"
              "# hhhh iiii\n"
              "# iiii jjjj\n")
_ST_LIST_W_RAW = ("# aaaa bbbb\n"
                  "<!-- GATES:BEGIN 生成块锚 -->\n"
                  "# bbbb cccc x\n"
                  "# cccc dddd x\n"
                  "<!-- GATES:END 配对锚 -->\n"
                  "# dddd eeee\n"
                  "# eeee ffff\n"
                  "# ffff gggg\n"
                  "# iiii jjjj x\n")
_ST_LIST_DOC = ("行号：按 HEAD `0000000`\n"
                "- 块内引用 `docs/GATES.md:3`（挪后仍指向生成块内同一行——gen 须 1、带 (?GATES:BEGIN)）\n"
                "- 块外引用 `docs/GATES.md:9`（挪到块外——gen 须 0）\n")


def listself(repo):
    """按 _ST_LIST_DOC 走真 check+list_lines，捕获 LIST 行。判据 7 烧闸面：反相注入点 = is_generated 的
    `blk[1] <= a <= blk[2]` 判式被摘/反相（list_lines 与 list_self_check 同一份现读，烧反相此格先红）。"""
    got = []
    n, fixes, refs, toks = check(argparse.Namespace(show=False), _ST_LIST_DOC, repo, "0000000", quiet=True)
    list_lines(argparse.Namespace(), repo, refs, toks, fixes, say=got.append)
    gens = [int(m.group(1)) for x in got for m in [re.search(r"gen=(\d)", x)] if m]
    return n, gens, got


def list_self_check():
    """--list 自检（w90-k3）：三格全用同一份 _ST_LIST_* 内存样本，不走 open()、不在判红路径。
    三格：① LIST 行 gen 判对＋锚定界现读；② 锚挪位（BEGIN/END 行内挪带鼓波行）仍判对——禁写死区间自证（咨牒 §五.4）；
    ③ 焚净：GEN_MARKS 锚删净 → gen_mark_block=None / is_generated=False。"""
    bad = 0
    repo = MemRepo({"docs/GATES.md": _ST_LIST_W}, {"docs/GATES.md": _ST_LIST_W_RAW})
    n, gens, got = listself(repo)
    blk = gen_mark_block(repo.work("docs/GATES.md") or [])
    if n["drift"] != 2 or gens != [1, 0] or blk != ("GATES:BEGIN", 2, 5) or "(?GATES:BEGIN)" not in got[0]:
        bad += 1
        print(f"  ✗ --list 自检：期望 DRIFT 2、LIST gen=[1, 0]（首条带 (?GATES:BEGIN)）、块定界 (:2-:5)，实得 "
              f"drift={n['drift']} gens={gens} blk={blk}；行={got}——--list 输出 / 生成块锚判退化（判据 7 烧反相此格先红（烧注入点：把 is_generated 判式 `blk[1] &lt;= a &lt;= blk[2]` 反相或 gen=1 恒 0））")
    else:
        print("  ✓ --list 自检 2/2（首条 gen=1(?GATES:BEGIN) 块内点名 / 次条 gen=0 块外；锚定界现读非写死）")
    # ② 锚挪位：BEGIN 挪到 :4、END 挪到 :6（中间夹纯内容行）——is_generated 现读锚重判，:4-:6 含锚行在内都是块内
    mv = ("# aaaa bbbb\n"
          "# bbbb cccc\n"
          "# cccc dddd\n"
          "<!-- GATES:BEGIN 锚挪位 -->\n"
          "# eeee ffff\n"
          "<!-- GATES:END 配对锚 -->\n"
          "# gggg hhhh\n"
          "# hhhh iiii\n"
          "# iiii jjjj\n")
    mr = MemRepo({"docs/GATES.md": _ST_LIST_W}, {"docs/GATES.md": mv})
    if not is_generated(mr, "docs/GATES.md", 4) or not is_generated(mr, "docs/GATES.md", 6) or \
            is_generated(mr, "docs/GATES.md", 3) or gen_mark_block(mv.splitlines()) != ("GATES:BEGIN", 4, 6):
        bad += 1
        print(f"  ✗ --list 自检锚挪位格：挪后块定界须 (:4-:6)、:3 块外——实得 blk={gen_mark_block(mv.splitlines())} "
              f"g4={is_generated(mr, 'docs/GATES.md', 4)} g3={is_generated(mr, 'docs/GATES.md', 3)}（写死区间 = 此格先红）")
    else:
        print("  ✓ --list 自检锚挪位格：BEGIN/END 挪位后块定界 (:4-:6) 现帧重判、:3 判块外（禁写死区间自证）")
    # ③ 焚净：锚删净
    burnt = MemRepo({"docs/GATES.md": _ST_LIST_W}, {"docs/GATES.md": "\n".join(
        x for x in _ST_LIST_W_RAW.splitlines() if not any(m in x for m in GEN_MARKS)) + "\n"})
    if gen_mark_block(burnt.work("docs/GATES.md") or []) is not None or is_generated(burnt, "docs/GATES.md", 3):
        bad += 1
        print("  ✗ --list 自检焚净格：GEN_MARKS 锚删净后 gen_mark_block 仍配对 / is_generated 仍真——焚净面须 None/False")
    else:
        print("  ✓ --list 自检焚净格：锚删净 → gen_mark_block=None、is_generated=False（锚字面按 GEN_MARKS 硬钉）")
    return bad


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


class Lines:
    """逐处问题行先收齐、按键排好再印（lane cs23：输出确定序，不随集合遍历顺序 / PYTHONHASHSEED 变）。
    键 = (组, 清单行号, 行内第几处引用, 类别, 次序)：组 0 = 逐处引用、1 = 清单里的「待核」标记；类别见各处调用。"""
    def __init__(self, say):
        self.say, self.rows = say, []

    def add(self, key, text):
        self.rows.append((key, text))

    def flush(self):
        for _, text in sorted(self.rows, key=lambda r: r[0]):
            self.say(text)
        self.rows = []


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

    def class_file(self, name):
        """autoload（project.godot）/ class_name 的名字 → 工作树里的脚本路径；找不到或不唯一给 None（穿透转发 `Crew.x(…)` 用）。"""
        if "K" not in self.cache:
            tab = {}
            for l in self.work("project.godot") or []:
                m = re.match(r'^(\w+)="\*?res://([^"]+)"', l)
                if m:
                    tab.setdefault(m.group(1), set()).add(m.group(2))
            for p in self.candidates("gd"):
                for l in self.work(p) or []:
                    m = re.match(r"^class_name\s+(\w+)", l)
                    if m:
                        tab.setdefault(m.group(1), set()).add(p)
            self.cache["K"] = {k: v.pop() for k, v in tab.items() if len(v) == 1}
        return self.cache["K"].get(name)

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


def defs(w, p, nm, kind, ext):
    """定义行号列表（1 起）：w = 文件的行（None 当空），kind = decl / func / head（md 标题）。"""
    w = w or []
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


def locate(repo, path, sym, ext):
    """工作树里这个符号可能的落点 [(路径, 定义行号, 体末行号, 说明, 改名 (旧, 新) 或 None)]：同文件 → 拆出件改名表 → 全仓唯一同名。"""
    kind, name, _ = sym
    out = []

    for d in defs(repo.work(path), path, name, kind, ext):
        out.append((path, d, body_end(repo.work(path), d, kind, ext), f"同文件 {name}", None))
    if ext == "gd" and kind == "func" and path == "scripts/Main.gd" and name in repo.splits():
        sp, nn = repo.splits()[name]
        for d in defs(repo.work(sp), sp, nn, kind, ext):
            out.append((sp, d, body_end(repo.work(sp), d, kind, ext), f"拆出件 {name}→{nn}", (name, nn)))
    if not out and kind != "head":
        glob = [(p, d) for p in repo.candidates(ext) if p != path for d in defs(repo.work(p), p, name, kind, ext)]
        if len(glob) == 1:
            p, d = glob[0]
            out.append((p, d, body_end(repo.work(p), d, kind, ext), f"全仓唯一 {name}", None))
    return out


def sym_kind(line, ext):
    """这一行算哪种符号定义：(kind, 名)；不算符号（不认识的后缀 / 普通语句）给 None。"""
    if ext == "gd":
        m = SYM_GD.match(line)
        if m:
            return ("decl", m.group(1))
        m = FUNC_GD.match(line)
        if m:
            return ("func", m.group(1))
    elif ext == "py":
        m = SYM_PY.match(line)
        if m:
            return ("func", m.group(1))
    elif ext == "md":
        line = line.strip()
        if HEAD_MD.match(line):
            return ("head", line)
    return None


def sym_defs(lines, name, ext):
    """工作树 / 锚里某份行表里符号 name 的定义行号（1 起），只认一份；找不到 / 不止一份都算找不到。
    .gd 同认 decl 与 func（符号锚不区分 const / var / func），同一行先按 decl、再按 func，同名两条都算找不到。"""
    lines = lines or []
    if ext == "gd":
        hits = []
        for i, t in enumerate(lines):
            m = SYM_GD.match(t) or FUNC_GD.match(t)
            if m and m.group(1) == name:
                hits.append(i + 1)
        return hits if len(hits) == 1 else None
    if ext == "py":
        hits = [i + 1 for i, t in enumerate(lines) if (m := SYM_PY.match(t)) and m.group(1) == name]
        return hits if len(hits) == 1 else None
    if ext == "md":
        hits = [i + 1 for i, t in enumerate(lines) if t.strip() == name and HEAD_MD.match(t.strip())]
        return hits if len(hits) == 1 else None
    return None


def sym_locate(repo, anchor, path, name, ext):
    """符号锚 `path::name` 的现址：(路径, 定义行, 体末行, 说明) 或 (None, 为什么)。锚里有这个符号的定义、工作树同文件也
    定位到唯一一份 → 现址（行号锚的四层跟号照旧管不到符号锚：符号不跟着挪行，只认存在唯一）。找不到 → (None, 线索)。"""
    old = repo.at_rev(anchor, path)
    if old is None:
        return None, f"锚 {anchor} 里没有 {path}"
    if sym_defs(old, name, ext) is None:
        return None, f"锚 {anchor} 里 {path} 没有唯一的符号 {name} 定义"
    w = repo.work(path)
    got = sym_defs(w, name, ext)
    if got:
        nd = got[0]
        line = w[nd - 1]
        kind = "func" if (ext == "py" or FUNC_GD.match(line)) else "head" if ext == "md" else "decl"
        return (path, nd, body_end(w, nd, kind, ext), f"符号 {name}")
    return None, f"工作树里 {path} 没有唯一的符号 {name} 定义（改了名？）"


def fwd_of_func(lines, d):
    """lines 第 d 行起的 .gd func 若只是一行转发，给转发目标（`_K.fn` / `obj.fn` / 同文件的 `fn`），否则 None。
    判据就是 func_body.forward_of(体, 源码)——check_symbols 十三节 / verify_economy 十一节「只取到一行转发」同一份（lane cs17 / gd23）。"""
    e = body_end(lines, d, "func", "gd")
    return forward_of("\n".join(lines[d - 1:e]), "\n".join(lines))


def fwd_dest(repo, path, lines, target):
    """转发目标 → (真身所在文件, 函数名)；解析不到给 None。`_K.fn` 按本文件 `const _K := preload(…)` 找，
    `fn` / `self.fn` 在本文件，`Crew.fn` 一类按 autoload / class_name 找；转给形参（`main._x(…)`）的不猜。"""
    if "." not in target:
        return path, target
    recv, fn = target.rsplit(".", 1)
    if recv == "self":
        return path, fn
    if "." in recv:
        return None
    m = re.search(PRELOAD.format(re.escape(recv)), "\n".join(lines), re.M)
    if m:
        return m.group(1), fn
    p = repo.class_file(recv)
    return (p, fn) if p else None


def through(repo, path, d, get):
    """顺一行转发走到真体（lane auditfix6）。path 第 d 行起的 func 不是转发 → None；
    是转发：走通给 (真体文件, 定义行, 体末行, [每跳说明])，走不通给 (None, [每跳说明 + 断在哪])。get(路径) 取那份文件的行。"""
    chain = []
    for _ in range(FWD_HOPS):
        lines = get(path)
        tgt = fwd_of_func(lines, d) if lines else None
        if not tgt:
            return (path, d, body_end(lines, d, "func", "gd"), chain) if chain else None
        chain.append(f"{path}:{d} → `{tgt}`")
        dest = fwd_dest(repo, path, lines, tgt)
        if not dest:
            return None, chain + [f"`{tgt}` 解析不到所在文件"]
        p2, fn = dest
        defs = [i + 1 for i, t in enumerate(get(p2) or []) if (m := FUNC_GD.match(t)) and m.group(1) == fn]
        if len(defs) != 1:
            return None, chain + [f"{p2} 里{'没有' if not defs else '不止一处'} func {fn}"]
        path, d = p2, defs[0]
    return None, chain + [f"转发链超过 {FWD_HOPS} 跳"]


def seg_at(want, lines, d, e, k):
    """want（归一化后的锚里那段；k = 它的首行离所在函数头几行）落在 lines 的函数 d..e 里哪一行（1 起），对不上 / 不唯一给 None。
    穿透转发用：真体的函数头换了名、多了 main 形参，所以含函数头的段（k == 0）只比头之后那几行，头就认真体那支的头。"""
    if k == 0:
        rest = want[1:]
        return d if [norm(x, "gd") for x in lines[d:d + len(rest)]] == rest else None
    pos = find_seg([norm(x, "gd") for x in lines[d - 1:e]], want)
    return d - 1 + pos[0] if len(pos) == 1 else None


def anchored_real(repo, anchor, path, a):
    """锚里 path 第 a 行所在的 .gd func（不是转发的）：(名字, 定义行)；不在 func 里、或锚里那支本就是一行转发（清单有意指着转发，
    如 EA6-4 的 `scripts/Main.gd:1781`）给 None——这种不穿透。"""
    if ext_of(path) != "gd":
        return None
    old = repo.at_rev(anchor, path)
    so = old and enclosing(old, a, "gd")
    if not so or so[0] != "func" or fwd_of_func(old, so[2]):
        return None
    return so[1], so[2]


def via_forward(repo, anchor, path, a, b, np, na, get=None):
    """锚里 path:a-b 在一支真函数里、落点 np:na 所在的函数却只剩一行转发（拆走 / 改名留别名）时，穿透到真体里重找那段（lane auditfix6）。
    不涉转发 → None；穿透找到 → (真体文件, 起, 止, 凭什么)；找不到 → (None, 「跟到一行转发」线索)——不许静默落在转发上。"""
    real = anchored_real(repo, anchor, path, a)
    if not real or ext_of(np) != "gd":
        return None
    get = get or repo.work
    nl = get(np)
    sn = nl and enclosing(nl, na, "gd")
    if not sn or sn[0] != "func":
        return None
    th = through(repo, np, sn[2], get)
    if th is None:
        return None
    if th[0] is None:
        return None, f"跟到一行转发：落点 {np}:{na} 所在 `{sn[1]}` 只剩一行转发，穿透不下去（{'；'.join(th[1])}）"
    rp, rd, re_, chain = th
    want = [norm(x, "gd") for x in repo.at_rev(anchor, path)[a - 1:b]]
    hit = seg_at(want, get(rp), rd, re_, a - real[1])
    if hit:
        return rp, hit, hit + b - a, f"穿透一行转发 {'；'.join(chain)}"
    return None, (f"跟到一行转发：落点 {np}:{na} 所在 `{sn[1]}` 只剩一行转发，真体在 {rp}:{rd}（{'；'.join(chain)}），"
                  f"但那段在真体里对不上（改写过？）")


def track(repo, anchor, path, a, b):
    """锚里 path:a-b 那段在工作树里的去处。落点所在函数只剩一行转发的，穿透到真体（via_forward）。
    跟得上：(新路径, 新起, 新止, 凭什么)；跟不上：(None, 线索)。"""
    t = track_raw(repo, anchor, path, a, b)
    return (t if not t[0] else via_forward(repo, anchor, path, a, b, t[0], t[1]) or t)


def track_raw(repo, anchor, path, a, b):
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
        real = sym[0] == "func" and anchored_real(repo, anchor, path, a)
        for p, d, e, why, ren in locate(repo, path, sym, ext):
            th = through(repo, p, d, repo.work) if real else None
            if th and th[0] is None:
                hints.append(f"{why} 现在在 {p}:{d}，跟到一行转发、穿透不下去（{'；'.join(th[1])}）")
                continue
            if th:  # 按名找到的那支只剩一行转发：去真体里找，不在转发上认
                rp, rd, re_, chain = th
                hit = seg_at(nseg, repo.work(rp), rd, re_, k)
                if hit:
                    return (rp, hit, hit + b - a, f"按函数（{why}）穿透一行转发 {'；'.join(chain)}")
                hints.append(f"{why} 现在在 {p}:{d}，只剩一行转发，真体在 {rp}:{rd}（{'；'.join(chain)}），那段在真体里对不上")
                continue
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
    n = dict(bad=0, drift=0, auto=0, manual=0, fwd=0, brief=0, marks=0, skipped=skipped, refs=len(refs))
    fixes = {}
    warned_briefs = False
    out = Lines(say)
    for k, (ln, f, a, b, ti) in enumerate(refs):
        t = toks[ln][ti]
        is_sym = t["kind"] == "sym"
        tag = f"L{ln} `{f}::{t['sym']}`" if is_sym else f"L{ln} `{f}:{span_str(a, b)}`"
        key = lambda cat, sub=0: (0, ln, ti, cat, sub)  # 类别：0 ⚠ brief 目录、1 NOFILE / OOR、2 --show 原文、3 DRIFT
        if offrepo(f):
            n["brief"] += 1
            if not os.path.isdir(BRIEFS):
                if not warned_briefs:
                    out.add(key(0), f"  ⚠ brief 目录 {BRIEFS} 不存在，仓外引用只跳过不判")
                    warned_briefs = True
                continue
        path, err = repo.resolve(f)
        if err:
            out.add(key(1), f"  ✗ NOFILE {tag}：{err}")
            n["bad"] += 1
            continue
        w = repo.work(path)
        old = None if offrepo(f) else repo.at_rev(anchor, path)
        if w is None and old is None:
            out.add(key(1), f"  ✗ NOFILE {tag}：{path} 不存在")
            n["bad"] += 1
            continue
        if w is not None and (a < 1 or b < a or b > len(w)) and (offrepo(f) or old is None) and not is_sym:
            out.add(key(1), f"  ✗ OOR {tag}：{path} 只有 {len(w)} 行")
            n["bad"] += 1
            continue
        if o.show and w is not None and (b <= len(w) or is_sym):
            if is_sym:
                hits = sym_defs(w, t["sym"], ext_of(path)) or []
                for d in hits:
                    out.add(key(2, d), f"    {tag} → {path}:{d}: {w[d - 1].strip()[:140]}")
            else:
                for i in range(a, b + 1):
                    out.add(key(2, i), f"    {tag} → {path}:{i}: {w[i - 1].strip()[:140]}")
        if offrepo(f):
            continue
        if is_sym:
            got = sym_locate(repo, anchor, path, t["sym"], ext_of(path))
            if got[0] is None:
                fixes[k] = got
                out.add(key(3), f"  ✗ DRIFT {tag}：{got[1]}（符号锚只认存在、不猜落点；人工回读后改符号名或改回行号锚）")
                n["drift"] += 1
                n["manual"] += 1
            continue
        if old is None:
            out.add(key(3), f"  ✗ DRIFT {tag}：锚 {anchor} 里没有 {path}（新文件？把头部的锚改到含它的提交）")
            n["drift"] += 1
            n["manual"] += 1
            fixes[k] = (None, "锚里没有这个文件")
            continue
        if a < 1 or b < a or b > len(old):
            out.add(key(1), f"  ✗ OOR {tag}：锚 {anchor} 里 {path} 只有 {len(old)} 行")
            n["bad"] += 1
            continue
        if w is not None and w[a - 1:b] == old[a - 1:b]:
            # 原号原文都没动，所在函数却成了一行转发（函数头留在原行、体搬走了）：不穿透就静默绿、清单指着转发（lane auditfix6）
            t = via_forward(repo, anchor, path, a, b, path, a)
            if t is None:
                continue
            gone = "原号那几行没变，但所在函数只剩一行转发"
        else:
            t = track(repo, anchor, path, a, b)
            gone = "工作树里没有这个文件了" if w is None else "该处内容变了"
        n["drift"] += 1
        if "一行转发" in (t[3] if t[0] else t[1]):
            n["fwd"] += 1
        fixes[k] = t
        if t[0]:
            n["auto"] += 1
            where = (f"{t[0]}:" if t[0] != path else ":") + span_str(t[1], t[2])
            out.add(key(3), f"  ✗ DRIFT {tag}：{path} {gone}；可跟号 → {where}（{t[3]}）")
        else:
            n["manual"] += 1
            out.add(key(3), f"  ✗ DRIFT {tag}：{path} {gone}；跟不上，要人工：{t[1]}")
    for ln, line in enumerate(lines, 1):
        for m in MARK.finditer(line):
            n["marks"] += 1
            out.add((1, ln, m.start(), 4, 0), f"  ✗ 待核 L{ln}：{m.group(0)}（回读、改号后删掉这个标记）")
    out.flush()
    say(f"  锚 {anchor}：引用 {n['refs']} 处（仓外 brief {n['brief']} 处只查越界），"
        f"跳过「原文作」{skipped} 处；NOFILE/OOR {n['bad']}，DRIFT {n['drift']}"
        f"（可自动跟号 {n['auto']}、要人工 {n['manual']}"
        + (f"；其中跟到一行转发 {n['fwd']}" if n["fwd"] else "") + f"），待核标记 {n['marks']}")
    return n, fixes, refs, toks


def render(line, row, targets, repo):
    """按新目标重写一行里的引用 token。targets[token 下标] = (新路径, 新起, 新止) 或 ("MARK", 标记文字)。
    改指了别的文件的写全路径；后面原本挂在旧文件上的裸 `:行`，挂不上了就补全路径（解析口径见 docstring）。
    符号锚（kind=sym）不重写 —— 符号只判存在、不跟号，--fix 只会在找不到时挂「待核」标记。"""
    out, pos, cur = [], 0, None
    for ti, t in enumerate(row):
        s, e = t["span"]
        out.append(line[pos:s])
        pos = e
        orig = repo.resolve(t["name"])[0]
        tgt, mark = targets.get(ti), ""
        if t["kind"] == "sym":
            txt = line[s:e]
            if tgt and tgt[0] == "MARK":
                mark = tgt[1]
            out.append(txt + mark)
            cur = orig or t["name"]
            continue
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


def do_fix(o, text, repo, anchor, dangling=False):
    n, fixes, refs, toks = check(o, text, repo, anchor)
    if o.list:
        list_lines(o, repo, refs, toks, fixes)
    if not n["drift"]:
        if not dangling:
            print("--fix：没有 DRIFT，不用改")
            return 0 if not (n["bad"] or n["marks"]) else 1
        print(f"--fix：没有 DRIFT，但锚 {anchor} 不在 HEAD 的历史上（悬空），只把锚改到 HEAD")
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
        tt = toks[ln][ti]
        if tt["kind"] == "sym":
            assert not t[0], "符号锚不会产生可跟号落点"
            mark = f"〔跟号待核：工作树里找不到唯一符号 {tt['sym']}（在 {path}）〕"
            by_line.setdefault(ln, {})[ti] = ("MARK", mark)
            continue
        by_line.setdefault(ln, {})[ti] = t[:3] if t[0] else \
            ("MARK", f"〔跟号待核：锚 {anchor} 里是 {path}:{span_str(a, b)}〕")
    print(f"--fix：锚 {anchor} → {head}；改号 {n['auto']} 处，打「待核」{n['manual']} 处")
    for ln in sorted(by_line):
        body = lines[ln - 1].rstrip("\n")
        new = render(body, toks[ln], by_line[ln], repo)
        lines[ln - 1] = new + lines[ln - 1][len(body):]
        for ti, tgt in sorted(by_line[ln].items()):
            t = toks[ln][ti]
            if t["kind"] == "sym":
                print(f"    L{ln} `{t['name']}::{t['sym']}` → " + (tgt[1] if tgt[0] == "MARK" else "（不重写）"))
                continue
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


def thru_target(repo, old_anchor, path, oa, ob, get):
    """旧锚 path:oa-ob 所在的真函数，在新版里（get 取文件行）按名找回、它只剩一行转发时穿透到真体：给 (真体文件, 起)，否则 None。
    --fix 穿透改的号函数头换了名、多了 main 形参，逐字比不上，改号自证 / --since 按这个认（lane auditfix6）。"""
    real = anchored_real(repo, old_anchor, path, oa)
    for i, t in enumerate(get(path) or [] if real else []):
        m = FUNC_GD.match(t)
        if m and m.group(1) == real[0]:
            v = via_forward(repo, old_anchor, path, oa, ob, path, i + 1, get)
            return (v[0], v[1]) if v and v[0] else None
    return None


def skeleton(line):
    return MARK.sub("", TOKEN.sub("§", line))


def since(o, repo, refs, lines, rev=None, new_rev=None, label=None, toks=None):
    """rev 版清单（缺省 o.since）的引用与本版逐对比内容，返回 MISMATCH 数（取不到 rev 版清单返回 None）。
    new_rev：本版引用按这个提交里的内容比（改号自证传本版头部的锚），缺省比工作树（--since）；
    传了 new_rev 的，内容不同而旧锚那段原文在新处文件里已经找不到（所指那段自己被改写了）只记 ⚠、不判红。
    （lane w50-k4 清零判竿需要 ⚠ 改指未验的格值，since() 把它存成属性 since.last_rewritten——返回值口径不变。）"""
    rev = rev or o.since
    label = label or f"--since {rev}"
    rel = os.path.relpath(os.path.abspath(o.doc), ROOT)
    old_text = git("show", f"{rev}:{rel}")
    old_anchor = old_text and anchor_of(old_text)
    if not old_anchor:
        print(f"  ✗ {label}：取不到 {rel} 或它头部的锚")
        return None
    if anchor_state(old_anchor) == "missing":
        # lane w53-12：旧锚取不到，下面逐对 at_rev 全是 None 被跳过、原先静默印「对上 0 对」照绿。改号自证时不判红——
        # 悬空锚改掉之后，新克隆里上一版清单的锚永远取不到，判红就红到下回改清单为止
        if new_rev:
            print(f"  ⚠ {label}：没比成——上一版清单（{rev}）的锚 {old_anchor} 在本仓取不到（lane rebase 前的提交、"
                  f"没推上来？），本版的号只经上面的 DRIFT 核过")
            return 0
        print(f"  ✗ {label}：{rev} 版清单的锚 {old_anchor} 在本仓取不到，比不了")
        return None
    old_lines = old_text.splitlines()
    old_refs, _ = parse_refs(old_lines)
    # 符号锚（kind=sym）在 toks 里取符号名；refs[j][2]/[3] 只是占位，不拿来比内容
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
    # 按新版引用的清单顺序逐对比（lane cs23）：上面集合交集的遍历顺序随 PYTHONHASHSEED 变，下面同一行里的换位认领
    # （unpaired 增删）和计数都吃这个顺序，不排就连同 ⚠ / MISMATCH 行序一起每次跑不同
    pairs.sort(key=lambda p: (p[1], p[0]))
    # 同一行里同一文件新插了一处引用时，按文件名对齐会错位：先看同一行里还没对上的新引用有没有正好是旧内容的
    unpaired = set(range(len(refs))) - {j for _, j in pairs}
    same = moved = mismatch = marked = rewritten = acked = 0
    out = Lines(print)  # 键 (0, 新版清单行号, 新版引用序号, 类别 0 ⚠ 改指未验 / 1 MISMATCH, 0)

    def new_lines(p):
        return repo.at_rev(new_rev, p) if new_rev else repo.work(p)

    def content(k):
        p, e = repo.resolve(refs[k][1])
        w = new_lines(p) if not e else None
        return [norm(x, ext_of(p)) for x in w[refs[k][2] - 1:refs[k][3]]] if w is not None else None
    for i, j in pairs:
        ol, f, oa, ob = old_refs[i][:4]
        if offrepo(f):
            continue
        path, err = repo.resolve(f)
        if err:
            continue
        ov = repo.at_rev(old_anchor, path)
        if ov is None:
            continue
        np_ = repo.resolve(refs[j][1])[0]
        if len(refs[j]) == 5 and toks is not None and toks.get(refs[j][0]):
            is_sym_j = toks[refs[j][0]][refs[j][4]]["kind"] == "sym"
        else:
            is_sym_j = False
        if is_sym_j:
            # 符号锚：不逐行比，按存在 + 内容等价判。符号名 在旧版清单 = 行号锚的，+1 判 MISMATCH。
            sym_name = toks[refs[j][0]][refs[j][4]]["sym"]
            got = sym_locate(repo, old_anchor, np_, sym_name, ext_of(np_))
            if got[0] is None:
                mismatch += 1
                out.add((0, refs[j][0], j, 1, 0),
                        f"  ✗ MISMATCH L{refs[j][0]} `{refs[j][1]}::{sym_name}`（旧版 L{ol} `{f}:{span_str(oa, ob)}` @ {old_anchor}）："
                        f"符号锚按旧锚里那份内容对不上：{got[1]}——行号锚改了写法 / 符号改名了，须照新写法回读")
            else:
                # 旧锚旧行号的内容 vs 现符号定义行起、同样长的段：不一致才算「符号已换义」。
                old_seg = [norm(x, ext_of(path)) for x in ov[oa - 1:ob]]
                cur_body = [norm(x, ext_of(np_)) for x in (new_lines(np_) or [])[got[1] - 1:got[1] - 1 + ob - oa + 1]]
                if cur_body == old_seg:
                    same += 1
                else:
                    # 行号锚改写成符号锚的分歧是预期（lane w26-k5）。本行「原文作」已经记着旧行号里指的那段
                    # （符号 def 行的旧编号，由 got[1] 现址反推锚里的同一行——同一 anchor，等于记录的是符号
                    # 的原行号），算认账改指，不判红；没记着的才算「符号已换义」。
                    noted = {m.group(1).strip()
                             for a_, b_ in (x.span() for x in OLD_NOTE.finditer(lines[refs[j][0] - 1]))
                             for m in TOKEN.finditer(lines[refs[j][0] - 1][a_:b_])}
                    def_line_old = (sym_defs(ov, sym_name, ext_of(np_)) or [None])[0]
                    refs_old_def = {f":{def_line_old}", f"{f}:{def_line_old}", f"{np_}:{def_line_old}"} \
                        if def_line_old else set()
                    if def_line_old and (noted & refs_old_def):
                        acked += 1
                        continue
                    mismatch += 1
                    out.add((0, refs[j][0], j, 1, 0),
                            f"  ✗ MISMATCH L{refs[j][0]} `{refs[j][1]}::{sym_name}`（旧版 L{ol} `{f}:{span_str(oa, ob)}` @ {old_anchor}）："
                            f"符号那几行内容与旧锚里指的不同（{np_}:{got[1]}）——符号锚指偏了或符号被改写"
                            + (f"；有意改指在本行「原文作 `:…`」里记着原行号 {def_line_old} 即可认账" if def_line_old else ""))
            continue
        want = [norm(x, ext_of(path)) for x in ov[oa - 1:ob]]
        if path == "scripts/Main.gd" and np_ != path:  # 搬进拆出件的，函数头照改名表比
            want = [renamed(x, repo, np_) for x in want]
        tt = content(j) != want and thru_target(repo, old_anchor, path, oa, ob, new_lines)
        if tt and tt[0] == np_:  # 所在函数成了一行转发、号改进了真体（lane auditfix6）：只认穿透算出的那一行
            if tt[1] == refs[j][2]:
                moved += 1
                continue
            mismatch += 1
            out.add((0, refs[j][0], j, 1, 0),
                    f"  ✗ MISMATCH L{refs[j][0]} `{refs[j][1]}:{span_str(refs[j][2], refs[j][3])}`（旧版 L{ol} `{f}:{span_str(oa, ob)}` @ {old_anchor}）："
                    f"旧锚那段所在函数已只剩一行转发，穿透到真体应是 {np_}:{span_str(tt[1], tt[1] + ob - oa)}——行号改歪了？")
            continue
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
                        out.add((0, refs[j][0], j, 0, 0),
                                f"  ⚠ 改指未验 {tag}：旧锚那段在 {new_rev} 的 {np_} 里已找不到原文（所指那段被改写过），人工回读过就不用管")
                        continue
                    mismatch += 1
                    out.add((0, refs[j][0], j, 1, 0), f"  ✗ MISMATCH {tag}：两处内容不同，旧锚那段原文在 {new_rev} 里还在 {np_}:"
                            + "、:".join(span_str(i, i + ob - oa) for i in still[:3]) + "——行号改歪了？")
                    continue
                mismatch += 1
                out.add((0, refs[j][0], j, 1, 0), f"  ✗ MISMATCH {tag}：两处内容不同")
                continue
            unpaired.discard(alt[0])
            unpaired.add(j)
            j = alt[0]
        if (repo.resolve(refs[j][1])[0], refs[j][2], refs[j][3]) == (path, oa, ob):
            same += 1
        else:
            moved += 1
    out.flush()
    since.last_rewritten = rewritten
    print(f"  {label}（旧锚 {old_anchor}{f' → 新锚 {new_rev}' if new_rev else ''}）：对上 {same + moved + mismatch + marked + rewritten + acked} 对（仓外 brief 不比），行号没变 {same}、"
          f"改了行号且内容一致 {moved}、MISMATCH {mismatch}、所在行带「待核」不比 {marked}"
          + (f"、所指那段被改写（⚠ 改指未验）{rewritten}、括注「原文作」认账改指 {acked}" if new_rev else "") + "；"
          f"新版多出 {len(unpaired)} 处引用（--show 回读）")
    return mismatch


# 清零判竿格（lane w50-k4，无门禁 sweep 第二格）：竿位格键 — 判语 — 正文行实读出处。六格正文行照计照印，
# 器只兜末行绿、格值 N>0 没人看得见（w48-k1/c700e7f 挂账认账改指 3 三波照绿即实证）——竿断言逐格 = 0。
# 这些格原本都在判红路径里（final gate if 逐格非零即退 1），竿给它们立的是「格位字面不许退化成不挂判」的元断言；
# 竿位自检在 self_check()（Z-R1 认账格 acked 不判 0 / Z-R2 清格 rc=0 / Z-R3 「原文作」区段新引用被另算 rc=1）。
ROD_CHECKS = (
    ("bad", "NOFILE/OOR 计数格（正文行「NOFILE/OOR N」）"),
    ("drift", "DRIFT 计数格（正文行「DRIFT N」）"),
    ("manual", "要人工计数格（正文行「要人工 N」，drift 子格收编）"),
    ("marks", "待核标记计数格（正文行「待核标记 N」）"),
)


def rod_assert(n, mismatch, rewritten, run, quiet=False):
    """逐格断言收收性计数格 = 0；N>0 即点名红（竿格名 + 格值 + 判语），返回判红条数（0 = 竿绿）。
    n/mismatch/rewritten 来源同 final gate——『原文作』认账改指 acked 不在此判（挂账认账格不判 0）。
    --since 改走比较内容支路时 ⚠ 改指未验格不进自证（那边不比内容），传 0——竿照常绿、格位不降格。
    quiet=True 只计数不印（自检格 Z-R1/Z-R2 拿它当纯判定器用）。"""
    say = (lambda *_: None) if quiet else print
    bad = 0
    for key, why in ROD_CHECKS:
        if n[key]:
            say(f"  ✗ 清零判竿红 {why}实读 = {n[key]}（竿断言 =0）")
            bad += 1
    if mismatch:
        say(f"  ✗ 清零判竿红 MISMATCH 计数格（正文行「MISMATCH N」）实读 = {mismatch}（竿断言 =0）")
        bad += 1
    if rewritten:
        say(f"  ✗ 清零判竿红 ⚠ 改指未验计数格（正文行「所指那段被改写（⚠ 改指未验）N」）实读 = {rewritten}（竿断言 =0）")
        bad += 1
    if not bad:
        say(f"  ✓ 清零判竿六格全 0（NOFILE/OOR、DRIFT、要人工、待核、MISMATCH、⚠ 改指未验；竿判得住挂账 N>0 即点名红，"
            f"竿自证格在 self_check()）——{run}")
    return bad


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


class MemRepo(Repo):
    """自检用：锚 / 工作树都在内存里（{路径: 文本}），不碰 git；diff 用 difflib 算成 `git diff -U0` 的块。"""

    def __init__(self, before, after):
        self.files = {"A": before, "W": after}
        self.tracked = set(before) | set(after)
        self.by_name = {}
        for p in sorted(self.tracked):
            self.by_name.setdefault(os.path.basename(p), []).append(p)
        self.cache = {}

    def work(self, path):
        t = self.files["W"].get(path)
        return t.splitlines() if t is not None else None

    def at_rev(self, rev, path):
        t = self.files["A"].get(path)
        return t.splitlines() if t is not None else None

    def candidates(self, ext):
        return sorted(p for p in self.files["W"] if ext_of(p) == ext)

    def hunks(self, anchor, path):
        a, b = self.at_rev(anchor, path) or [], self.work(path) or []
        return [(i1 + 1 if i2 > i1 else i1, i2 - i1, j1 + 1 if j2 > j1 else j1, j2 - j1)
                for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes() if tag != "equal"]


# 零、转发穿透自检（lane auditfix6）：每次都跑，在内存里造一对「锚 / 工作树」，钉住按名锚穿透一行转发的几种形状。
# 去掉穿透（via_forward / ③ 里的 through）、或 forward_of 判据退化，这里先红——反向自证跟着必跑门禁进 CI，不靠 lane 手跑变异。
_ST_HOST_A = """extends Node
const _PAGE := preload("res://scripts/t/Page.gd")


func open_page(port_id: String) -> void:
	title.text = "市舶司・%s" % port_id
	var duty := GameState.customs_duty()
	add_chip("请领　%d" % duty, _on_apply)


func stay_forward(n: int) -> void:
	_PAGE.stay_forward(self, n)


func lost_forward(n: int) -> void:
	var lost_total := n * 7 + 1
	print_rich("lost %d" % lost_total)


func chain_fn(n: int) -> int:
	var chained := n * 11
	return chained - 2


func keep_real(n: int) -> int:
	var total := n * 3
	return total + 1
"""
_ST_HOST_W = """extends Node
const _PAGE := preload("res://scripts/t/Page.gd")


func open_page(port_id: String) -> void:
	_PAGE.open_page(self, port_id)


func stay_forward(n: int) -> void:
	_PAGE.stay_forward(self, n)


func lost_forward(n: int) -> void:
	Nowhere.lost_forward(n)


func chain_fn(n: int) -> int:
	return _PAGE.chain_fn(self, n)


func keep_real(n: int) -> int:
	var total := n * 3
	return total + 1
"""
_ST_PAGE_A = """extends RefCounted


static func stay_forward(main, n: int) -> void:
	main.print(n)
"""
_ST_PAGE_W = """extends RefCounted
const _DEEP := preload("res://scripts/t/Deep.gd")


static func stay_forward(main, n: int) -> void:
	main.print(n)


static func open_page(main, port_id: String) -> void:
	main.title.text = "市舶司・%s" % port_id
	var duty := GameState.customs_duty()
	main.add_chip("请领　%d" % duty, main._on_apply)


static func chain_fn(main, n: int) -> int:
	return _DEEP.chain_fn(main, n)
"""
_ST_DEEP_W = """extends RefCounted


static func chain_fn(main, n: int) -> int:
	var chained := n * 11
	return chained - 2
"""
# (清单里的引用, 期望)：期望 = (文件, 起, 止) 须跟到这里；"MANUAL" = 须报「跟到一行转发」交人工；None = 原号不动、不算 DRIFT
_ST_CASES = [
    ("scripts/t/Host.gd:5", ("scripts/t/Page.gd", 9, 9), "S1 函数头原号没挪、体成了转发：旧版静默绿"),
    ("scripts/t/Host.gd:8", ("scripts/t/Page.gd", 12, 12), "S2 体里一行：按名找到的是转发，穿透进真体"),
    ("scripts/t/Host.gd:5-7", ("scripts/t/Page.gd", 9, 11), "S3 函数头连体：真体头换名加 main 形参"),
    ("scripts/t/Host.gd:15", "MANUAL", "S4 转发目标解析不到（Nowhere.x）：报跟到转发，不静默"),
    ("scripts/t/Host.gd:16", "MANUAL", "S5 解析不到的转发、引的是体里一行"),
    ("scripts/t/Host.gd:20-22", ("scripts/t/Deep.gd", 4, 6), "S6 两跳转发链 Host → Page → Deep"),
    ("scripts/t/Host.gd:11", ("scripts/t/Host.gd", 9, 9), "S7 锚里本就是转发（有意指着转发）：照 diff 跟到转发，不穿透"),
    ("scripts/t/Host.gd:25-27", ("scripts/t/Host.gd", 21, 23), "S8 真函数只挪了号：照旧 diff，不误穿透"),
    ("scripts/t/Host.gd:2", None, "S9 顶层 const 没动：不算 DRIFT"),
]

# lane w26-k5 符号锚四格：用一对「常量被插了一行」的内存工作树（与 _ST_* 无关——那边的 Host.gd 同名不同形，
# 符号锚要单起副本，才钉得住自己那条只判存在 / 不挪行的支路）。
_ST_SYM_A = """extends Node

const COMBAT_FIRE_DELAY := 3.5

func idle():
	pass
"""
_ST_SYM_W_INS = """extends Node

# 在符号前面插了一行（check 须照旧认定，DRIFT 0）
const COMBAT_FIRE_DELAY := 3.5

func idle():
	pass
"""
_ST_SYM_W_TYPO = """extends Node

const COMBAT_FIRE_DELY := 3.5

func idle():
	pass
"""
# (清单里的引用, 工作树, 期望 DRIFT 数, 期望 rc / --fix 行为)；rc 只看这条引用带来的 DRIFT 计数
_ST_SYM_CASES = [
    ("scripts/t/Const.gd:3", _ST_SYM_A, 0, "A1 基线：行号锚照旧，对得上不报"),
    ("scripts/t/Const.gd::COMBAT_FIRE_DELAY", _ST_SYM_A, 0, "A2 符号锚没动：认定"),
    ("scripts/t/Const.gd::COMBAT_FIRE_DELAY", _ST_SYM_W_INS, 0, "A3 符号前插一行：行号锚会漂、符号锚不漂"),
    ("scripts/t/Const.gd::COMBAT_FIRE_DELAY", _ST_SYM_W_TYPO, 1, "A4 符号名错一个字母：符号锚报 DRIFT"),
]


def self_check():
    """跑自检，返回判红的条数（0 = 过）。"""
    repo = MemRepo({"scripts/t/Host.gd": _ST_HOST_A, "scripts/t/Page.gd": _ST_PAGE_A},
                   {"scripts/t/Host.gd": _ST_HOST_W, "scripts/t/Page.gd": _ST_PAGE_W, "scripts/t/Deep.gd": _ST_DEEP_W})
    doc = "行号：按 HEAD `0000000`\n" + "".join(f"- `{r}`\n" for r, _, _ in _ST_CASES)
    _n, fixes, refs, _ = check(argparse.Namespace(show=False), doc, repo, "0000000", quiet=True)
    bad = 0
    for k, (ref, want, why) in enumerate(_ST_CASES):
        got = fixes.get(k)
        ok = (got is None) if want is None else \
            (got is not None and got[0] is None and "跟到一行转发" in got[1]) if want == "MANUAL" else \
            (got is not None and tuple(got[:3]) == want)
        if not ok:
            bad += 1
            print(f"  ✗ 转发穿透自检 {why}：`{ref}` 期望 {want or '不算 DRIFT'}，实得 {got}")
    # 改号自证 / --since 那一侧：S1 那段按名找回、穿透后须正落在真体函数头（--fix 穿透改的号它才认，别的号判 MISMATCH）
    tt = thru_target(repo, "0000000", "scripts/t/Host.gd", 5, 5, repo.work)
    if tt != ("scripts/t/Page.gd", 9):
        bad += 1
        print(f"  ✗ 转发穿透自检 S10 改号自证按名找回穿透：`scripts/t/Host.gd:5` 期望 ('scripts/t/Page.gd', 9)，实得 {tt}")
    if not bad:
        print(f"  ✓ 转发穿透自检 {len(_ST_CASES) + 1}/{len(_ST_CASES) + 1}（函数成了一行转发：穿透到真体 / 穿透不下去报「跟到一行转发」；"
              "锚里本就是转发的、只挪了号的真函数不穿透；改号自证按穿透认号）")
    # 符号锚四格（lane w26-k5）：行号锚对照、符号锚认定 / 抗插一行 / 误名报 DRIFT。每组单起 repo + 单行清单，
    # 在 quiet=True 下走 check()，只看那一条带来的 DRIFT 计数（符号锚 fixes 不落点，所以不走 _ST_CASES 的 fixes 断言）。
    for ref, work, want_drift, why in _ST_SYM_CASES:
        single = MemRepo({"scripts/t/Const.gd": _ST_SYM_A}, {"scripts/t/Const.gd": work})
        doc2 = "行号：按 HEAD `0000000`\n- `" + ref + "`\n"
        n2, _f2, _r2, _t2 = check(argparse.Namespace(show=False), doc2, single, "0000000", quiet=True)
        if n2["drift"] != want_drift:
            bad += 1
            print(f"  ✗ 符号锚自检 {why}：`{ref}` 期望 DRIFT {want_drift}，实得 {n2['drift']}")
    if not bad:
        print(f"  ✓ 符号锚自检 {len(_ST_SYM_CASES)}/{len(_ST_SYM_CASES)}（行号锚照旧；符号锚认定；插一行不漂；误名报 DRIFT）")
    # 清零判竿位自检三格（lane w50-k4）：竿断言在场判据体系下主业静默绿，这两格把竿自己的规约钉死——
    # Z-R1：『原文作』认账改指 acked 是认账挂账格，不判 0（补竿即定死的格位字面，不许演化成状态减法）；
    # Z-R2：六格全 0 时竿断言静默（竿不误伤清档）；
    # Z-R3：区段规则——「原文作」括注里的新引用被另算 DRIFT（OLD_NOTE 收敛觉化 / 区段退化，竿域外判红路径先红）。
    # Z-R1：认账挂账盘——『原文作』认账格 acked（挂账盘 N>0）出现在六格全 0 的清单里、竿照旧绿；
    # 认账格不判 0 是竿的格位字面（判语判的就是 acked 不进竿域、不进判红）。
    doc_r1 = ("行号：按 HEAD `0000000`\n"
              "- 旧版那几行 `Z-R1-Fake.gd:1`（原文作 `:50` 认了账，挂账认账盘 N>0 不计进竿的六格——竿是清零判不是认账判）\n")
    n_r1, _f, _r, _t = check(argparse.Namespace(show=False), doc_r1,
                             MemRepo({"Z-R1-Fake.gd": "x\n"}, {"Z-R1-Fake.gd": "x\n"}), "0000000", quiet=True)
    rod_r1 = rod_assert(n_r1, 0, 0, "竿位自检 Z-R1（清格盘 + 挂账认账盘 N>0 同票绿）", quiet=True)
    noted_r1 = {m.group(1).strip() for a, b in (x.span() for x in OLD_NOTE.finditer(doc_r1.splitlines()[1]))
                for m in TOKEN.finditer(doc_r1.splitlines()[1][a:b])}
    if n_r1["refs"] != 1 or n_r1["skipped"] != 1 or rod_r1 != 0 or f":50" not in noted_r1 or \
            any(n_r1[k] for k, _why in ROD_CHECKS):
        bad += 1
        print(f"  ✗ 清零判竿位自检 Z-R1：「原文作」认账盘被另计入竿六格（refs={n_r1['refs']} skipped={n_r1['skipped']} "
              f"rod={rod_r1}）——挂账认账格判 0 是不允许的状态减法、盘票被增殖时竿须出红")
    else:
        print("  ✓ 清零判竿位自检 Z-R1：「原文作 `:50`」认账挂账盘 N>0 同票绿、认账格位不判 0（挂账 = 0 是不允许的状态减法——盘票被增殖进竿六格才出红）")
    doc_r2 = "行号：按 HEAD `0000000`\n- `Z-R2-Fake.gd:1`\n"
    n_r2, _f, _r, _t = check(argparse.Namespace(show=False), doc_r2,
                             MemRepo({"Z-R2-Fake.gd": "x\n"}, {"Z-R2-Fake.gd": "x\n"}), "0000000", quiet=True)
    if rod_assert(n_r2, 0, 0, "竿位自检 Z-R2", quiet=True) != 0:
        bad += 1
        print("  ✗ 清零判竿位自检 Z-R2：六格全 0 的清单竿断言误伤红——竿格被退化时不指望它绿，但完好竿不许冤判")
    else:
        print("  ✓ 清零判竿位自检 Z-R2：六格全 0 竿断言静默绿（竿位在场、无误伤；竿格摘除时本格当不了哨兵——靠 Z-R3 的反向判语锁定）")
    doc_r3 = ("行号：按 HEAD `0000000`\n"
              "- 旧版 `Z-R3-Fake.gd:1`（原文作 `:1`；`Z-R3-Fake.gd:5` 区段后的同文件新引用——区段遇 '；' 即截，不许把 5 吞进括注里）\n")
    n_r3, _f, _r, _t = check(argparse.Namespace(show=False), doc_r3,
                             MemRepo({"Z-R3-Fake.gd": "x\n"}, {"Z-R3-Fake.gd": "x\n"}), "0000000", quiet=True)
    if len(_r) != 2 or n_r3["refs"] != 2 or rod_assert(n_r3, 0, 0, "竿位自检 Z-R3", quiet=True) == 0 or not n_r3["bad"]:
        bad += 1
        print(f"  ✗ 清零判竿位自检 Z-R3：「原文作」区段后的新引用没被另算、或竿格被摘除（refs={n_r3['refs']} bad={n_r3['bad']} rod 判语行数不对）——"
              f"区段遇 '；' 收截的格位字面，或 ROD_CHECKS 六格被抽空（竿死 silent 绿 = Z-R3 先拦）")
    else:
        print("  ✓ 清零判竿位自检 Z-R3：「原文作」区段遇 '；' 即截——区段后的同文件新引用被另算 OOR、竿判定 rc=1 点名红（区段区间规则在场）")
    # 锚悬空三态（lane w53-12）：假 git 只认「rev-parse 查得到 aaaaaaa / bbbbbbb」与「aaaaaaa 是 HEAD 的祖先」这两种问法——
    # 只查 rev-parse（原先的口径）则 bbbbbbb 判「在」，--is-ancestor 两个参数写反则 aaaaaaa 判「悬空」，都在这里红
    def fake_git(*a):
        return "" if a in {("rev-parse", "--verify", "-q", c + "^{commit}") for c in ("aaaaaaa", "bbbbbbb")} | \
            {("merge-base", "--is-ancestor", "aaaaaaa", "HEAD")} else None
    got_as = {c: anchor_state(c, fake_git) for c in ("aaaaaaa", "bbbbbbb", "ccccccc")}
    if got_as != {"aaaaaaa": None, "bbbbbbb": "off", "ccccccc": "missing"}:
        bad += 1
        print(f"  ✗ 锚悬空自检：期望 在 HEAD 历史上 → None、查得到却不在 → off、查不到 → missing，实得 {got_as}")
    else:
        print("  ✓ 锚悬空自检 3/3（在 HEAD 历史上 / 本仓查得到却不在 HEAD 历史上 = 悬空、判红 / 查不到）")
    bad += list_self_check()  # --list 三格（lane w90-k3）
    return bad


LANDING_OFF = "--no-ledger-landing"  # 与 ledger_refs_mutants.LANDING_OFF 同值（那边 import 不到本脚本的常量，各写一份，gates_md 查两处 marks）


def ledger_landing(off):
    """零之二、ledger_refs_mutants 落点预检（lane w19-g8）：返回判红条数；✗ / ✓ 行已打印。"""
    if off:
        print(f"  ⚠ ledger_refs_mutants 落点预检未跑（{LANDING_OFF}：只给 ledger_refs_mutants 在变异 worktree 里用）")
        return 0
    import ledger_refs_mutants as lrm
    bad, summary = lrm.landing(ROOT)
    if not bad:
        print(f"  ✓ ledger_refs_mutants 落点预检：{summary}；rc / 期望 ✗ 字样 / 写盘 / 确定性 / 空转对照归全量（lane 档，docs/GATES.md §三.26）")
    return len(bad)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("doc", nargs="?", default=DEFAULT_DOC)
    ap.add_argument("--anchor", help="比对用的提交（缺省取清单头部「按 HEAD `…`」）")
    ap.add_argument("--since", help="重锚自证：和 REV 版清单逐对比内容")
    ap.add_argument("--show", action="store_true", help="逐处印出所引行原文")
    ap.add_argument("--list", action="store_true",
                    help="在汇总结论前附列逐 DRIFT 一行 LIST（gen 标记点名生成块内引用——那类跟号须走 --write 而非 --fix）；纯附加打印，rc / 判据 / 落点预检照旧")
    ap.add_argument("--fix", action="store_true", help="自动跟号并把头部锚改成 HEAD（所引文件须已提交）")
    ap.add_argument(LANDING_OFF, dest="no_landing", action="store_true",
                    help="不跑 ledger_refs_mutants 落点预检（只给 ledger_refs_mutants 在变异过的 worktree 里用，一键跑不许带）")
    o = ap.parse_args()

    text = open(o.doc, encoding="utf-8").read()
    anchor = o.anchor or anchor_of(text)
    if not anchor:
        print("  ✗ 清单头部没有「行号：……按 HEAD `提交`」，用 --anchor 指定")
        return 1
    state = anchor_state(anchor)
    if state == "missing":
        print(f"  ✗ 锚 {anchor} 不是本仓的提交" +
              ("" if o.anchor else "（lane rebase 前的提交、没推上来？到还查得到它的机器上跑 --fix 改到 HEAD）"))
        return 1
    dangling = state == "off" and not o.anchor  # lane w53-12：--anchor 指定的不查
    since.last_rewritten = 0  # lane w50-k4：清零判竿的 ⚠ 改指未验格值，since() 每跑必覆写；没跑到（--fix 支路）保持 0
    if self_check():
        print("结果：有问题（自检没过：本脚本的跟号 / 清零判竿逻辑坏了，先修脚本，清单的结果不可信）")
        return 1
    repo = Repo()
    if o.fix:
        if o.anchor or o.since:
            print("  ✗ --fix 只按清单头部的锚改，别和 --anchor / --since 一起用")
            return 1
        return do_fix(o, text, repo, anchor, dangling)
    landing_bad = ledger_landing(o.no_landing)
    if dangling:
        print(f"  ✗ 锚悬空 {anchor}：本机对象库里查得到，却不在 HEAD 的历史上（lane rebase 前的提交？主控落地后即悬空）——"
              "新克隆 / origin 上本脚本直接退 1「不是本仓的提交」；--fix 改到 HEAD（没有 DRIFT 也改锚）")

    n, _fixes, refs, _toks = check(o, text, repo, anchor)
    mismatch = 0
    if o.since:
        mismatch = since(o, repo, refs, text.splitlines(), toks=_toks)
        if mismatch is None:
            return 1
    else:
        # 改号自证（lane auditfix1）：锚 = HEAD 时清单里的号写歪了，锚里那行和工作树同号那行照样一致，上面的 DRIFT 看不出来；
        # 所以再和上一版清单逐对比：旧锚旧号那段 == 本版锚本版号那段
        rev, why = prev_rev(o.doc)
        if rev is None:
            print(f"  ⚠ 改号自证跳过：{why}")
        else:
            mismatch = since(o, repo, refs, text.splitlines(), rev=rev, new_rev=anchor, label=f"改号自证 [{why}]", toks=_toks)
            if mismatch is None:
                return 1
    n2_rewritten = 0 if o.since else since.last_rewritten  # 清零判竿第六格（⚠ 改指未验）格值：--since 不分内容、格位不降格传 0

    if n["bad"] or n["drift"] or n["marks"] or mismatch or landing_bad or dangling:
        how = []
        if n["bad"] or n["drift"] or n["marks"]:
            how.append("DRIFT 先跑 --fix 自动跟号；「要人工」「待核」的回读后改号、删标记，再提交清单")
        if mismatch and not o.since:
            how.append("MISMATCH 是本版清单的号和上一版指的不是同一段：改回提示的号；确是有意换了所指，在那处引用后括注「原文作 `:旧号`」")
        if dangling:
            how.append("锚悬空：跑 --fix 把头部锚改到 HEAD（没有 DRIFT 也改锚），提交清单")
        if landing_bad:
            how.append(f"落点预检 {landing_bad} 项：ledger_refs_mutants 的变异靶子漂了，照新形状改 tools/ledger_refs_mutants.py、跑一次全量")
        if o.list:
            list_lines(o, repo, refs, _toks, _fixes)  # 附加附列贴在汇总结论前，不进判红路径
        print(f"结果：有问题（{'；'.join(how) or '见上'}）")
        return 1
    # 清零判竿格（lane w50-k4）：全部通过前逐格断言六处收收性计数格 = 0。这六格本都在上面的判红路径里
    # （任一格非零即退 1），竿断言在现存判据体系下静默绿；竿守的是「格位字面漂移 / 判语被放宽」的元层——
    # 格位改了字、或者哪一格被摘出判红路径，竿位自检（Z-R1/Z-R2/Z-R3）先红。
    rod_assert(n, mismatch or 0, 0 if o.since else n2_rewritten,
               "本档" if not o.since else "本档（--since 比内容、改指未验格不进）")
    if o.list:
        list_lines(o, repo, refs, _toks, _fixes)
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
