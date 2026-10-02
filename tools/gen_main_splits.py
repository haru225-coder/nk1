#!/usr/bin/env python3
"""tools/main_splits.txt 的生成器 / 对账（lane cs13，拍板清单 E-5）。

  python3 tools/gen_main_splits.py            # 对账：重算一遍，与 tools/main_splits.txt 逐字节比，不一致退 1（不写盘）
  python3 tools/gen_main_splits.py --write    # 按重算结果重写 tools/main_splits.txt，写完再对账一遍

main_splits.txt 是 Main.gd 拆出件的唯一清单：check_symbols（一之零 / read_main_src）和 godot_smoke（_main_family_src）
都读它的第一列，两份脚本里不再各自抄一份 MAIN_SPLITS。其余各列是拆分台账，check_symbols 每轮调本脚本的 check() 对账，
所以别手改——手改任何一格都会红；新拆一刀：在 docs/Main拆解台账.md 追加「## 第N刀（lane X，…）… → `scripts/ui/X.gd`」一节，
再跑 --write，连同拆出件一起提交。

各列从哪来（都是重算，没有一格手抄）：
  · 拆出件、顺序、lane ← docs/Main拆解台账.md：开头「已拆（前三刀…）」那行 + 各「## 第N刀[二]（lane X，…）… → `路径`」节标题
    （「前N刀」的 N 就是那段该登记的件数、也是刀序起点：之后的节标题从第 N+1 刀起；lane cs26 起由台账自己推，脚本里不再写死 3。
    那段整段不在 = N 为 0、节标题从第一刀起——前三刀日后改写成三节就是这个形状，不用改脚本。
    「二」= lane w20-a9 起的追加刀：「## 第N刀二（…）：… → `已有拆出件`」，往前面某刀已登记的拆出件里追加搬入函数，
    lane 记这一刀自己的；标题写了「二」而路径是新的、或该拆出件还没建过刀，都是格式硬校验 ③）
  · 拆出函数 ← 现 Main.gd 的一行转发「Main 函数→拆出件 static func」，按拆出件里 static func 的顺序；
    拆出件里有 static func 不是 Main 转发过去的，记问题（拆出件只装从 Main 搬出的东西）
  · 拆出 commit ← git 里新增该文件的 commit；文件还没提交记 `-`
  · 原 Main 行范围 ← 拆出 commit 父版的 Main.gd（还没提交就用 HEAD 版）里这些函数的行段（含紧贴其上的 # / ## 注释），
    只隔空行的相邻段并成一段；台账里写了逐支行段的（表格行「| `_fn(…)` | a–b」），与重算的逐支行段对账
    （追加刀记这一刀自己新增的函数：行范围的支段 = 普通刀那几段 + 本刀那几段，逐支行段按各刀自己的拆出 commit 父版对账）
  · 台账那节函数表（「| `_fn(…)` |」行，写没写行段都算）列了的函数，现 Main 必须仍一行转发到本件，否则判红
    （lane cs18：挪回 Main 再 --write，拆出函数 / 行范围两栏跟着缩、清单照样逐字节一致，不查这条就一路全绿）；
    反过来，那节有函数表的，现 Main 一行转发到本件的每支也都得列在表里，漏列即判红（lane cs22：有表就须列全）。
    前三刀没有自己的节，两个方向都不查；第四刀起每节都须有表（⑤）

台账格式硬校验（lane cs23：台账写坏了，原先那一刀 / 那一行被正则漏掉，重算跟着少一件 / 少一支，--write 照写、gen 自己绿，
只靠 check_symbols 下游兜，单独跑本脚本的人看不到）。下面几种形状本脚本直接判红，--write 也不写盘：
  ① 标题文字以「第…刀」开头、却不合节标题正则（`## 第N刀（lane X，…）：… → `scripts/…/X.gd``）的行——少了反引号 / lane /
    全角括号、写成 ### 或 ##第N刀、路径不在 scripts/ 下、箭头后面还有字；
  ② 「已拆（前N刀…）」那段里的 `X.gd` 没按「`X.gd`（lane，…」写（那一件会被漏掉），或认出来的不是 N 件、N 认不出；
  ③ 刀序：节标题「第N刀」的 N（汉字或数字）须从「前N刀」的下一刀起（现为第四刀）逐刀 +1，重号 / 跳号 / 认不出的数都红；
  ④ 拆刀节里像函数表行的（「| `名字(`」起头）却不合函数表行写法，或第二格以数字起头却不是「a–b」（en dash）行段——
    前者整行漏认（cs18 的「列了却不转发」查不到它），后者行段对账静默跳过；同一节函数表同一支列两次；
    同一拆出件被建刀节和追加刀节加起来列了两次，同样判红（追加刀与建刀重了件 / 函数，cs18 两个方向的对账有一方漏查）；
  ⑤ 拆刀节没有函数表：没表时 cs18 / cs22 两个方向的对账都不查，整节空转。第四、第五刀早于函数表惯例，原先登记在 NO_TABLE_OK 放行，
    lane cs25 给两节补了表、删了放行，现无例外。

以上五种的变异对照（现行判红、退回 cs23 前 / 放行退回时 --write 后 rc=0）固化在 tools/ledger_refs_mutants.py（lane cs25）。

追加刀的口径（lane w20-a9，台账头注与 build() 前的注释各写一份，别只改代码）：
  · 标题写成「## 第N刀二（lane Y，…）：… → `已有拆出件`」（N 是刀序数字；「二」后不再加「三」「四」——要再追加就再算一刀 N+1）；
  · lane 一格记追加刀自己的 lane；commit / 行范围两格记**建刀**那一刀（按「新增这个文件的 commit」取），追加刀自己的
    commit / 行段只写进台账节和函数表，不进清单——清单行数 = 拆出件数，一件一行；
  · 追加刀函数表的行段 = 追加刀自己的拆出 commit 的父版 Main.gd 重算；同一件各刀的逐支行段按各刀自己的父版逐版对账；

git 历史的两条放行（其余一律逐字节比）：
  · 拆出的那个 commit 自己不可能写进自己的哈希：清单里记 `-`、该 commit 版的清单也记 `-`、且 **HEAD 就是这个 commit** 的，照认；
    HEAD 已往前走（拆出 commit 之后又有提交）还记 `-` 即判红，要 --write 补上哈希（lane auditfix1：原先不看 HEAD，
    `-` 能一直绿下去，只等下一刀顺手补）。所以拆 Main 的 lane 提交拆分后紧跟着 --write、另提一笔补哈希，两笔同一次落地；
  · 浅克隆取不到拆出 commit 或其父版（如 CI 只拉 1 层）：这一行的 commit / 行范围两格沿用清单原值，报「未验」，不判红。
    追加刀自己的拆出 commit 浅克隆取不到时，只跳过这一刀自增函数的逐支行段对账（同一处报 ⚠ 未验），建刀那几段照旧对。
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
    "# 往已有拆出件追加一刀（lane w20-a9 的口径）：标题写「## 第N刀二（…）」、lane 记这一刀的；commit / 行范围记建刀那一刀，逐支行段按各刀自己的拆出 commit 父版对账。\n"
    "# 列（制表符分隔）：拆出件\tlane\t拆出 commit（`-` = 尚未提交 / 拆出 commit 自己）\t"
    "原 Main 行范围（拆出 commit 父版 Main.gd，含紧贴的注释）\t拆出函数（Main 函数→拆出件 static func）\n"
)
COLS = 5
# 拆刀节标题 / 函数表行（lane cs18 / cs22 / cs23）：ledger_splits 按它认刀、build 按它读表（两个方向与逐支行段对账），格式硬校验也按同一对正则判
# 「[二]」= 追加刀（lane w20-a9）：「## 第N刀二（…）：… → `已有拆出件`」，往已登记的拆出件里追加搬入函数；lane 记这一刀自己的
KNIFE_HEAD = re.compile(r'^## 第(\S+?)刀(二)?（lane ([\w-]+)，[^）\n]*）：[^\n]*→ `(scripts/[\w/]+\.gd)`\s*$', re.M)
KNIFE_LIKE = re.compile(r'^#{1,6}[ \t]*第[^（(\n]{1,12}?刀二?')  # 标题文字以「第…刀[二]」开头的行（「### 同刀门禁…（第四刀…）」不算）
LISTED_ROW = re.compile(r'^\| `(_?\w+)\([^`]*\)` \|(?: (\d+)–(\d+))?', re.M)
FN_ROW_LIKE = re.compile(r'^\|\s*`[A-Za-z_]\w*\(')  # 像函数表行：「| `名字(」起头（引用点表是「| `文件:行`」，不在此列）
# 「已拆（前N刀…）」那段（lane cs26：N 从这里读，原先 FIRST_KNIFES = 3 写死）：N = 那段登记的件数，之后的节标题从第 N+1 刀起
FIRST_HEAD = re.compile(r'^已拆（前([^刀\s（）]{1,4})刀[^\n]*\n(.+?)\n\n', re.M | re.S)
_CN_DIGIT = {c: i for i, c in enumerate("零一二三四五六七八九")}


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
    head = FIRST_HEAD.search(text)
    first = 0  # 没有「已拆（前N刀…）」段：前面没有只登一行的刀，节标题从第一刀起（③ 按这个起点查刀序）
    if head:
        for name, lane in re.findall(r'`(\w+\.gd)`（(\w+)，', head.group(2)):
            out.append({"rel": "scripts/ui/" + name, "lane": lane, "second": False, "section": ""})
        first = _cn_num(head.group(1))
        _check_first_knifes(head.group(1), head.group(2), len(out), problems)
        if first is None:
            first = len(out)
    for m in KNIFE_HEAD.finditer(text):
        nxt = re.search(r'^## ', text[m.end():], re.M)  # 节到下一个二级标题为止（含别的 lane 追加的非拆刀节）
        out.append({"rel": m.group(4), "lane": m.group(3), "second": bool(m.group(2)),
                    "section": text[m.end():m.end() + nxt.start()] if nxt else text[m.end():]})
    _check_ledger_shape(text, first, bool(head), problems)
    return out


def _cn_num(s):
    """「第N刀」的 N：阿拉伯数字，或一到九十九的汉字写法（四 / 十 / 十一 / 二十三）。认不出返回 None。"""
    if s.isdigit():
        return int(s)
    tens, sep, ones = s.partition("十")
    if not sep:
        return _CN_DIGIT.get(s) if len(s) == 1 else None
    if len(tens) > 1 or len(ones) > 1 or (tens and tens not in _CN_DIGIT) or (ones and ones not in _CN_DIGIT):
        return None
    return (_CN_DIGIT[tens] if tens else 1) * 10 + (_CN_DIGIT[ones] if ones else 0)


def _check_first_knifes(num, block, n, problems):
    """「已拆（前N刀…）」那段（lane cs23 ②）：反引号里的 X.gd 都得按「`X.gd`（lane，…」写，认出来的正好 N 件（lane cs26：N 读自段首）。"""
    named = re.findall(r'`([^`\n]+\.gd)`', block)
    ok = re.findall(r'`(\w+\.gd)`（\w+，', block)
    bad = [x for x in named if x not in ok]
    if bad:
        problems.append(f"{LEDGER_REL}「已拆（前{num}刀…）」那段的 {'、'.join(bad)} 没按「`X.gd`（lane，…」写，"
                        f"本脚本认不出，这件会被漏掉（格式硬校验 ②）")
    want = _cn_num(num)
    if want is None:
        problems.append(f"{LEDGER_REL}「已拆（前{num}刀…）」的刀数认不出（写汉字一到九十九或阿拉伯数字，格式硬校验 ②）")
    elif n != want:
        problems.append(f"{LEDGER_REL}「已拆（前{num}刀…）」那段认出 {n} 件，应为 {want} 件（格式硬校验 ②）")


def _check_ledger_shape(text, first, has_head, problems):
    """台账格式硬校验（lane cs23 ①③④⑤）：结构写坏、原先被正则静默漏掉的形状，一律判红。"""
    lines = text.split("\n")
    heads = {text.count("\n", 0, m.start()) + 1: m for m in KNIFE_HEAD.finditer(text)}
    for i, ln in enumerate(lines, 1):  # ① 像拆刀节标题、却不合节标题正则
        if KNIFE_LIKE.match(ln) and i not in heads:
            problems.append(f"{LEDGER_REL}:{i} 标题以「第…刀」开头，却不合拆刀节标题写法"
                            f"「## 第N刀（lane X，…）：… → `scripts/…/X.gd`」，本脚本认不出这一刀、会整件漏掉"
                            f"（格式硬校验 ①）：{ln.strip()[:120]}")
    want = first + 1  # 起点由「已拆（前N刀…）」段推（lane cs26）
    origin = (f"；起点：「已拆（前N刀…）」段 N = {first}" if has_head else
              "；起点：台账没有「已拆（前N刀…）」段，从第一刀起")
    built = set()  # 已建刀的拆出件（追加刀的 rel 必须在其中；lane w20-a9）
    for k, (i, m) in enumerate(sorted(heads.items())):  # ③ 刀序 + 追加刀的 rel
        n = _cn_num(m.group(1))
        tail = origin if k == 0 else ""
        if n is None:
            problems.append(f"{LEDGER_REL}:{i}「第{m.group(1)}刀」的刀号认不出（写汉字一到九十九或阿拉伯数字，格式硬校验 ③）")
        elif n != want:
            problems.append(f"{LEDGER_REL}:{i}「第{m.group(1)}刀」刀序不对：上一刀之后应是第 {want} 刀（重号 / 跳号，格式硬校验 ③{tail}）")
        if m.group(2):  # 追加刀「第N刀二」
            if m.group(4) not in built:
                problems.append(f"{LEDGER_REL}:{i} 是追加刀「第{m.group(1)}刀二」，指向的拆出件 {m.group(4)} 还没建过刀"
                                f"（追加刀只往已登记的拆出件里加；新件写成「第N刀」建刀节，格式硬校验 ③）")
        else:
            built.add(m.group(4))
        want = (n if n is not None else want) + 1
    func_seen = {}  # 函数名 -> (刀节标题行号, 所属节刀号文字)：台账各节函数表通查，同一拆出件两节列同一支即红（lane w20-a9 ④）
    knife_rel = {}  # 节标题行号 -> (rel, 刀号文字, 该刀第一个函数表行号)；跨节查重时报错要带「列在谁那节」
    for i, m in sorted(heads.items()):  # ④ 函数表行写法、⑤ 有没有表
        rel = m.group(4)
        nxt = re.search(r'^## ', text[m.end():], re.M)
        end = i + text[m.end():m.end() + nxt.start()].count("\n") if nxt else len(lines)
        seen = {}
        for k in range(i + 1, end + 1):
            ln = lines[k - 1]
            if not FN_ROW_LIKE.match(ln):
                continue
            row = LISTED_ROW.match(ln)
            if not row:
                problems.append(f"{LEDGER_REL}:{k}（{rel} 那节）像函数表行、却不合「| `名字(…)` | a–b | …」写法，"
                                f"本脚本漏认这一支（格式硬校验 ④）：{ln.strip()[:120]}")
                continue
            if not row.group(2) and re.match(r'\s*\d', ln[row.end():]):
                problems.append(f"{LEDGER_REL}:{k}（{rel} 那节）{row.group(1)} 的行段写法不认（要「a–b」、en dash、"
                                f"「|」后一个空格），逐支行段对账会静默跳过（格式硬校验 ④）：{ln.strip()[:120]}")
            if row.group(1) in seen:
                problems.append(f"{LEDGER_REL}:{k}（{rel} 那节）函数表把 {row.group(1)} 列了两次"
                                f"（另一处 :{seen[row.group(1)]}，格式硬校验 ④）")
            seen.setdefault(row.group(1), k)
            knife_rel.setdefault(i, (rel, m.group(1) + ("二" if m.group(2) else "")))
            name = row.group(1)
            where = func_seen.get(name)
            if where and where[0] != knife_rel[i][1]:
                problems.append(f"{LEDGER_REL}:{k}（第{knife_rel[i][1]}刀那节 {rel}）函数表把 {name} 列了两次"
                                f"（追加刀与建刀重了件 / 函数：建刀那节还列着它 :{where[1]}，格式硬校验 ④）")
            func_seen.setdefault(name, (knife_rel[i][1], k))
        if not seen:
            problems.append(f"{LEDGER_REL}:{i}（{rel} 那节）没有函数表（「| `名字(…)` | a–b | …」行），"
                            f"「台账列了却不转发」无从对账（格式硬校验 ⑤）")


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


def _knife_spans_report(problems, rel, lane, listed, spans, kdesc):
    """一刀的逐支行段对账：listed 里写了行段的支、spans 里有且与台账不符即红；spans is None（父版取不到）只报未验，不归 problems。"""
    if spans is None:
        return
    for fn, a, b in listed:
        if a and fn in spans and spans[fn] != (int(a), int(b)):
            problems.append(f"{rel}：台账写 {fn} 在{kdesc} 的 {a}–{b} 行，重算是 {spans[fn][0]}–{spans[fn][1]}")


def _append_parent_main(fnames):
    """追加刀这一刀的「拆前 Main.gd」：工作区 / 提交前那一刻的 Main.gd——追加刀节落地时本 lane 正把它
    改成一行转发；本节函数表的行号 = 改成转发前那一版（未提交时就是工作区的 Main.gd）。已提交后再对账，
    行号是一次性快照、不再回来改，所以这里仍读工作区 Main.gd——它仍装着转发前原文时的行号；
    真改成转发后再对账，行段差异自然红。读不到时返回 None。"""
    try:
        with open(os.path.join(ROOT, MAIN_REL), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def build(old_rows=None, backfill=False):
    """重算清单。返回 (全文, 问题列表, 备注列表)。old_rows：现清单按路径的各列，git 取不到时沿用。
    backfill：--write 用，拆出 commit 自己记的 `-` 补成哈希；对账时不补（HEAD 就是拆出 commit 才照认 `-`，否则判红）。

    lane w20-a9 起的「追加刀」：台账可以加「## 第N刀二（lane Y，…）→ `已有拆出件`」。清单仍一件一行：
    commit / lane 两列记建刀（新增该文件的 `--diff-filter=A`）那一刀；行范围列 = 各刀段合并；
    逐支行段按各刀自己的拆前 Main.gd 对账——建刀读「建刀 commit 的父版」，追加刀读「追加刀提交时的 HEAD」。
    浅克隆 / 未提交取不到时，只那一刀那几支报未验，行范围沿用清单原值，其余刀照常。
    """
    problems, notes = [], []
    old_rows = old_rows or {}
    try:
        with open(os.path.join(ROOT, MAIN_REL), encoding="utf-8") as f:
            fwd = _forwards(f.read())
    except OSError:
        problems.append(f"{MAIN_REL} 读不到")
        fwd = {}
    rows = []
    splits = ledger_splits(problems)
    tabled = {}
    for sp in splits:
        for fn, _, _ in LISTED_ROW.findall(sp["section"]):
            tabled.setdefault(fn, []).append(sp["rel"])
    grouped = {}
    order = []
    for sp in splits:
        rel = sp["rel"]
        if rel not in grouped:
            grouped[rel] = {"build": None, "appends": []}
            order.append(rel)
        if sp["second"]:
            if grouped[rel]["build"] is not None:
                grouped[rel]["appends"].append(sp)
            continue
        if grouped[rel]["build"] is not None:
            problems.append(f"{sp['lane']} 族 {rel}：同一拆出件有两个建刀节（第二次登记须写成追加刀「第N刀二」；按台账顺序首见算建刀）")
        else:
            grouped[rel]["build"] = sp
    for rel in order:
        grp = grouped[rel]
        build_sp = grp["build"]
        if build_sp is None:
            continue
        lane, section = build_sp["lane"], build_sp["section"]
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
        knives = [(lane, LISTED_ROW.findall(section))]
        for asp in grp["appends"]:
            knives.append((asp["lane"], LISTED_ROW.findall(asp["section"])))
        moved = {m for m, _ in pairs}
        all_names = {fn for _kl, listed in knives for fn, _, _ in listed}
        for klane, listed in knives:
            for fn, a, b in listed:
                if fn not in moved:
                    elsewhere = [r for r, g in fwd.items() if r != rel and fn in g.values()]
                    problems.append(f"{klane} 族 {rel}：台账函数表列了 {fn}（期望拆前 Main.gd {f'{a}–{b} 行' if a else '行段台账未写'}），"
                                    f"现 Main.gd 却{f'一行转发到 {elsewhere[0]}' if elsewhere else '没有一行转发到本件'}"
                                    f"（挪回 Main / 改名 / 转去别件了？台账、拆出件、清单要一起改）")
        # 反向（lane cs22）：有表就须列全——本件各刀函数表的并集须覆盖「现 Main 一行转发到本件」的全部支，缺的记一次
        # （不再按刀各红一次；追加刀的表只装本刀自增的，建刀的表照旧装建刀那几支）
        if any(listed for _kl, listed in knives):
            for m, s in pairs:
                if m not in all_names:
                    other = [r for r in tabled.get(m, ()) if r != rel]
                    problems.append(f"{lane} 族 {rel}：现 Main.gd 的 {m} 一行转发到本件 {s}，台账函数表（建刀 + 追加刀）里却没列它"
                                    f"（{f'表里列在了 {other[0]} 那节；' if other else ''}"
                                    f"新搬进本件的补一行「| `{m}(…)` | 拆前行段 |」，有函数表就须列全）")
        for klane, listed in knives:
            pass  # 逐刀「台账列了须仍转发」在上面按 all_names 查过；逐支行段对账在下方各刀各算各的
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
            build_spans_all = func_spans(pre, {m for m, _ in pairs})
            lost = [m for m, _ in pairs if m not in build_spans_all]
            build_names = {fn for fn, _, _ in knives[0][1]}  # 建刀函数表列的（其余是后来追加刀加进来的，建刀的父版里本来就没有它们）
            lost_in_build = [m for m in lost if m in build_names or not any(fn == m for _kl, lst in knives[1:] for fn, _, _ in lst)]
            if lost_in_build:
                problems.append(f"{rel}：拆出前的 Main.gd{f'（{commit}^）' if commit else '（HEAD）'}里找不到 "
                                f"func {'、'.join(lost_in_build)}（拆分时改了名？Main 函数须与拆前同名）")
            # 清单第 4 列只并「建刀函数表 + 各追加刀函数表」的支段；建刀的父版里可能也有追加刀的自增函数
            # （它先于建刀在 Main 里出现过），那些不算建刀的段，留给追加刀自己的父版记。
            # 前三刀那类「开头一行、没有自己节 / 函数表」的（knives[0][1] 空），没有追加刀，build_names 为空集
            # 会错杀全部支——那种口径照原样：spans 全用
            build_spans = build_spans_all if not any(listed for _kl, listed in knives[1:]) else \
                {fn: sp for fn, sp in build_spans_all.items() if fn in build_names}
            spans_all = list(build_spans.values())
            _knife_spans_report(problems, rel, lane, knives[0][1], build_spans, "拆前 Main.gd")
            appends_spans = []
            head_main = None
            for asp, (klane, listed) in zip(grp["appends"], knives[1:]):
                if head_main is None:
                    head_main = _append_parent_main([fn for fn, _, _ in listed])
                if head_main is None:
                    for fn, a, b in listed:
                        if a:
                            notes.append(f"{rel}：追加刀（{klane}）的拆前 Main.gd 取不到，{fn} 的逐支行段对账跳过，未验")
                    continue
                aspans = func_spans(head_main, {fn for fn, _, _ in listed})
                spans_all.extend(aspans.values())
                appends_spans.append((klane, listed, aspans))
            rng = merge_spans(pre, spans_all) or "-"
            for klane, listed, aspans in appends_spans:
                _knife_spans_report(problems, rel, klane, listed, aspans, "追加刀拆后的转发快照（Main.gd）")
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
