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
    lane cs26：刀序起点由「已拆（前N刀…）」段推（gen 不再写死 FIRST_KNIFES = 3）——M2c「前三刀」写成「前四刀」、M2d 整段删掉各红，
    C3 前三刀段改写成三节（第一至第三刀、各带函数表）现行 rc=0、C3′ 起点写死回第四刀 rc=1。
    变异锚按形状定位（lane cs26）：只锚刀号（第四 / 第五 / 第十一刀；刀号一改 C0 先红）、「## 第N刀（」起头的节标题行、那节函数表
    最后一支、「已拆（前N刀…）」段第一件、两支脚本里调用 / 排序的形状；期望 ✗ 字样由定位到的内容现算（Facts），日期 / 题文 /
    形参名 / 件的说明 / 行尾注释改了照样落上，定位不到或不止一处仍判「变异没落上」。
  · 二、输出确定序（check_decision_refs）：同一棵树在 PYTHONHASHSEED = 0 / 1 / 2 / 3 / 42 下各跑一次，stdout 须逐字节同、rc 同。
    D1 清单里前 8 处 `scripts/Main.gd:N` 号 +1、不提交（改号自证对 HEAD 版逐对比出多条 MISMATCH）、D2 同一脏树 `--since HEAD`
    （lane cs26 起相对基；原先钉死历史基 ccb1d57，清单再改多轮条数会掉、历史改写会丢基）：⚠ / ✗ 行不到 2 条就比不出行序，记「变异没落上」。X1 / X2 = 同上、两处排序（Lines.flush 的
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
# lane cs26：变异锚按形状定位，不按字面。原先锚在台账的整行文字上（第十一刀节标题、`_on_rewatch_opening()` 那行、第四刀
# `_seal_chip(btn)`、第五刀 `_on_npc_leave()`、前三刀段的 SlipKit、两支脚本里的调用 / 排序行），改一个字（日期、题文、形参名、
# 件的说明、加一句行尾注释）台账 / 脚本本身照样对，本门禁却「变异没落上」、要人照新文字改（cs26 实测 9 处）。现在只锚三样不会合法变动的：
#   · 刀号（第四 / 第五 / 第十一刀）：台账只往后追加、刀序 ③ 硬校验，刀号一改 gen 自己先红（C0 就红），不存在「合法改了刀号」；
#   · 形状：「## 第N刀（」起头那一行、那节里最后一支函数表行（带行段的取带行段的）、「已拆（前N刀…）」段里第一件；
#   · 期望的 ✗ 字样由定位到的内容现算（函数名、行段、件数、下一刀的刀号），不抄台账原文。
# 定位不到或不止一处照旧判「变异没落上」（不许静默跳过），替换前后文字相同也算没落上。
_DIGITS = "零一二三四五六七八九"


def _cn(n):
    """1–99 的汉字刀号（四 / 十 / 十一 / 二十三）。"""
    tens, ones = divmod(n, 10)
    return (("" if tens == 1 else _DIGITS[tens]) + "十" if tens else "") + (_DIGITS[ones] if ones else "")


def _num(s):
    """「第N刀」「前N刀」的 N（汉字一到九十九或阿拉伯数字）；认不出返回 None。与 gen 的 _cn_num 同口径、各写一份（本门禁不借被测脚本的解析）。"""
    if s.isdigit():
        return int(s)
    tens, sep, ones = s.partition("十")
    if not sep:
        return _DIGITS.index(s) if len(s) == 1 and s in _DIGITS[1:] else None
    if len(tens) > 1 or len(ones) > 1 or (tens and tens not in _DIGITS) or (ones and ones not in _DIGITS):
        return None
    return (_DIGITS.index(tens) if tens else 1) * 10 + (_DIGITS.index(ones) if ones else 0)


FIRST_HEAD = r"^已拆（前([^刀\s（）]{1,4})刀[^\n]*\n(.+?)\n\n"
FIRST_ITEM = r"`(\w+)\.gd`（(\w+)，([^）\n]*)）"
TABLE_ROW = r"^\| `(_?\w+)\([^`\n]*\)` \|(?: (\d+)–(\d+) \|)?[^\n]*$"
K_TITLE, K_TAVERN, K_NPC = 11, 4, 5  # 被变异的三刀：第十一刀（cs23 原探针那一刀）、第四 / 第五刀（lane cs25 补的表）


def _head_re(n):
    return rf"^## 第{_cn(n)}刀（[^\n]*$"


def _section(text, n):
    """第 n 刀那节：(标题 match, 节正文起, 节正文止)；标题须恰好一处。"""
    heads = list(re.finditer(_head_re(n), text, re.M))
    if len(heads) != 1:
        raise Miss(f"{LEDGER} 里「## 第{_cn(n)}刀（」起头的节标题有 {len(heads)} 处，应 1 处")
    h = heads[0]
    nxt = re.search(r"^## ", text[h.end():], re.M)
    return h, h.end(), h.end() + nxt.start() if nxt else len(text)


def _last_row(text, n, ranged):
    """第 n 刀那节函数表的最后一支（ranged：只看带「a–b」行段的）。"""
    _, lo, hi = _section(text, n)
    rows = [m for m in re.finditer(TABLE_ROW, text[lo:hi], re.M) if m.group(2) or not ranged]
    if not rows:
        raise Miss(f"{LEDGER} 第{_cn(n)}刀那节找不到{'带行段的' if ranged else ''}函数表行")
    m = rows[-1]
    return lo + m.start(), lo + m.end(), m


def _first_block(text):
    m = re.search(FIRST_HEAD, text, re.M | re.S)
    if not m:
        raise Miss(f"{LEDGER} 里找不到「已拆（前N刀…）」段")
    return m


def _put(wt, old, new):
    if new == old:
        raise Miss(f"{LEDGER} 变异前后文字相同")
    _write(wt, LEDGER, new)


def l_head(n, fn):
    """第 n 刀节标题整行换成 fn(原行)。"""
    def m(wt):
        text = _read(wt, LEDGER)
        h, _, _ = _section(text, n)
        _put(wt, text, text[:h.start()] + fn(h.group(0)) + text[h.end():])
    return m


def l_row(n, fn, ranged=True):
    """第 n 刀那节最后一支函数表行换成 fn(原行, match)。"""
    def m(wt):
        text = _read(wt, LEDGER)
        a, b, row = _last_row(text, n, ranged)
        _put(wt, text, text[:a] + fn(text[a:b], row) + text[b:])
    return m


def l_drop_row(n):
    def m(wt):
        text = _read(wt, LEDGER)
        a, b, _ = _last_row(text, n, False)
        _put(wt, text, text[:a] + text[b + 1:])
    return m


def l_drop_table(n):
    """第 n 刀那节（到下一个二级标题为止）的函数表行全删。"""
    def m(wt):
        text = _read(wt, LEDGER)
        _, lo, hi = _section(text, n)
        body, k = re.subn(TABLE_ROW + r"\n", "", text[lo:hi], flags=re.M)
        if not k:
            raise Miss(f"{LEDGER} 第{_cn(n)}刀那节没有函数表行可删")
        _put(wt, text, text[:lo] + body + text[hi:])
    return m


def l_first(fn):
    """「已拆（前N刀…）」段：fn(段 match) → (起, 止, 新文字)。"""
    def m(wt):
        text = _read(wt, LEDGER)
        a, b, new = fn(_first_block(text), text)
        _put(wt, text, text[:a] + new + text[b:])
    return m


def _item_paren(blk, text):  # 第一件的「（」改半角
    it = re.search(FIRST_ITEM, blk.group(2))
    if not it:
        raise Miss(f"{LEDGER}「已拆（前N刀…）」段里没有「`X.gd`（lane，…）」写法的件")
    a = blk.start(2) + it.start() + len(it.group(1)) + 4
    return a, a + 1, "("


def _item_drop(blk, text):  # 删掉第一件（连同其后的「 · 」）
    it = re.search(FIRST_ITEM + r"\s*·\s*", blk.group(2))
    if not it:
        raise Miss(f"{LEDGER}「已拆（前N刀…）」段里没有后面还跟着一件的「`X.gd`（lane，…）· 」")
    return blk.start(2) + it.start(), blk.start(2) + it.end(), ""


def _count_up(blk, text):  # 「前N刀」的 N +1，件不动
    n = _num(blk.group(1))
    if n is None:
        raise Miss(f"{LEDGER}「已拆（前{blk.group(1)}刀…）」的刀数认不出")
    return blk.start(1), blk.end(1), _cn(n + 1)


def _block_drop(blk, text):  # 整段删掉、不补节
    return blk.start(), blk.end(), ""


def l_first_as_sections(wt):
    """「已拆（前N刀…）」段改写成 N 节「## 第k刀（lane X，…）：… → `scripts/ui/X.gd`」，每节带函数表（行段不写），
    函数表按清单第 5 列（Main 函数→static func）列全——前三刀日后改写成三节就是这个形状，现行须 rc=0（lane cs26 ②）。"""
    text = _read(wt, LEDGER)
    blk = _first_block(text)
    table = {}
    for ln in _read(wt, TXT).split("\n"):
        cols = ln.split("\t")
        if len(cols) >= 5 and not ln.startswith("#"):
            table[cols[0]] = [p.split("→") for p in cols[4].split()]
    parts = []
    for k, it in enumerate(re.finditer(FIRST_ITEM, blk.group(2)), 1):
        rel = f"scripts/ui/{it.group(1)}.gd"
        if rel not in table:
            raise Miss(f"{TXT} 里没有 {rel} 那行")
        rows = "".join(f"| `{f}()` | — | `{g}` |\n" for f, g in table[rel])
        parts.append(f"## 第{_cn(k)}刀（lane {it.group(2)}，改写）：{it.group(3)} → `{rel}`\n\n"
                     f"| 支 | 行段 | 拆出件 static func |\n|---|---|---|\n{rows}\n")
    if not parts:
        raise Miss(f"{LEDGER}「已拆（前N刀…）」段里一件也认不出")
    _put(wt, text, text[:blk.start()] + "".join(parts) + text[blk.end():])


def _gen_sub(pattern, repl):
    return sub(GEN, pattern, repl)


# 退回 cs23 前：台账格式硬校验两处调用删掉（ledger_splits 照旧认刀，认不出的静默漏掉）。按「行首缩进 + 函数名(」认调用行，
# 参数 / 行尾注释改了照样落上（def 行以 def 起头，不在此列）
g_pre_cs23 = [_gen_sub(r"^[ \t]+_check_first_knifes\([^\n]*\n", ""),
              _gen_sub(r"^[ \t]+_check_ledger_shape\([^\n]*\n", "")]
# 退回 cs25 前：第四 / 第五刀没表照放行——按「紧跟着报『没有函数表』的那个 if」认，条件怎么写都落得上
g_pre_cs25 = [_gen_sub(r'^([ \t]+)if (.+):\n(?=[ \t]+problems\.append\(f"[^\n]*没有函数表)',
                       r'\1if (\2) and rel not in ("scripts/ui/TavernPage.gd", "scripts/ui/NpcPage.gd"):\n')]
# 退回 cs26 前：刀序起点写死第四刀（FIRST_KNIFES = 3）
g_pre_cs26 = [_gen_sub(r"^([ \t]+)want = first \+ 1\b[^\n]*$", r"\1want = 3 + 1")]

M = {
    "M1a": ("①节标题去反引号", [l_head(K_TITLE, lambda h: h.replace("`", ""))]),
    "M1b": ("①节标题写成 ###", [l_head(K_TITLE, lambda h: "#" + h)]),
    "M1c": ("①「##第十一刀」无空格", [l_head(K_TITLE, lambda h: h.replace("## ", "##", 1))]),
    "M1d": ("①半角括号逗号", [l_head(K_TITLE, lambda h: re.sub(r"（(lane \w+)，([^）\n]*)）", r"(\1, \2)", h, count=1))]),
    "M1e": ("①去掉 lane 字样", [l_head(K_TITLE, lambda h: re.sub(r"（lane (\w+)，", r"（\1，", h, count=1))]),
    "M1f": ("①箭头后多字", [l_head(K_TITLE, lambda h: h + "（已落地）")]),
    "M2a": ("②前三刀段第一件半角括号", [l_first(_item_paren)]),
    "M2b": ("②前三刀段删掉一件", [l_first(_item_drop)]),
    "M2c": ("②「前三刀」写成「前四刀」、件不动（lane cs26）", [l_first(_count_up)]),
    "M2d": ("②前三刀段整段删掉、不补节（lane cs26）", [l_first(_block_drop)]),
    "M3a": ("③第十一刀改成第十刀（重号）", [l_head(K_TITLE, lambda h: h.replace(f"第{_cn(K_TITLE)}刀", f"第{_cn(K_TITLE - 1)}刀", 1))]),
    "M3b": ("③第十一刀改成第十三刀（跳号）", [l_head(K_TITLE, lambda h: h.replace(f"第{_cn(K_TITLE)}刀", f"第{_cn(K_TITLE + 2)}刀", 1))]),
    "M3c": ("③刀号写成认不出的「第拾壹刀」", [l_head(K_TITLE, lambda h: h.replace(f"第{_cn(K_TITLE)}刀", "第拾壹刀", 1))]),
    "M4a": ("④函数表行「|」后不空格", [l_row(K_TITLE, lambda ln, r: "|" + ln[2:])]),
    "M4b": ("④行段写 ASCII 连字符且写错", [l_row(K_TITLE, lambda ln, r: ln.replace(f"{r[2]}–{r[3]}", f"{r[2]}-{int(r[3]) + 47}", 1))]),
    "M4c": ("④同一支列两次", [l_row(K_TITLE, lambda ln, r: ln + "\n" + ln)]),
    "M5": ("⑤第十一刀那节删光函数表行", [l_drop_table(K_TITLE)]),
    "M5t": ("⑤第四刀那节删光函数表行（lane cs25 补的表）", [l_drop_table(K_TAVERN)]),
}
SHAPE = "格式硬校验 {}"
RESYNC = "与重算不一致"


class Facts:
    """期望字样现算：从快照的台账里按同一套形状读出被变异那几处的内容（函数名、行段、件数、下一刀）。"""
    def __init__(self, text, wt):
        self.text, self.wt = text, wt
        self.first = _num(_first_block(text).group(1))
        if self.first is None:
            raise Miss(f"{LEDGER}「已拆（前N刀…）」的刀数认不出")
        self.row = _last_row(text, K_TITLE, True)[2]          # 第十一刀：最后一支带行段的
        _, lo, hi = _section(text, K_TITLE)
        self.title_rows = [m.group(1) for m in re.finditer(TABLE_ROW, text[lo:hi], re.M)]
        self.title_rel = re.search(r"`(scripts/[\w/]+\.gd)`\s*$", _section(text, K_TITLE)[0].group(0)).group(1)
        self.tavern_rel = re.search(r"`(scripts/[\w/]+\.gd)`\s*$", _section(text, K_TAVERN)[0].group(0)).group(1)
        self.tavern_last = _last_row(text, K_TAVERN, False)[2].group(1)
        self.npc_row = _last_row(text, K_NPC, True)[2]
        self.has_next = bool(re.search(_head_re(K_TITLE + 1), text, re.M))

    def order(self, got, want):
        return f"「第{_cn(got)}刀」刀序不对：上一刀之后应是第 {want} 刀"

    def cascade(self, want):  # 第十一刀认不出 / 改了号，下一刀（第十二刀）跟着刀序不对；没有下一刀就没有这一条
        return [self.order(K_TITLE + 1, want)] if self.has_next else []

    def want(self, cid):
        name, a, b = self.row.group(1), self.row.group(2), int(self.row.group(3))
        k = K_TITLE
        w = {
            "M1a": [SHAPE.format("①"), RESYNC] + self.cascade(k),
            "M1b": [SHAPE.format("①"), RESYNC] + [f"台账函数表列了 {f}" for f in self.title_rows] + self.cascade(k),
            "M1d": [SHAPE.format("①"), RESYNC] + self.cascade(k), "M1e": [SHAPE.format("①"), RESYNC] + self.cascade(k),
            "M1f": [SHAPE.format("①"), RESYNC] + self.cascade(k),
            "M2a": [SHAPE.format("②"), RESYNC], "M2b": [SHAPE.format("②"), RESYNC],
            "M2c": [f"那段认出 {self.first} 件，应为 {self.first + 1} 件", self.order(self.first + 1, self.first + 2)],
            "M2d": [self.order(self.first + 1, 1), RESYNC],
            "M3a": [self.order(k - 1, k)] + self.cascade(k),
            "M3b": [self.order(k + 2, k)] + self.cascade(k + 3),
            "M3c": ["「第拾壹刀」的刀号认不出"],
            "M4a": [SHAPE.format("④"), f"现 Main.gd 的 {name} 一行转发到本件 "],
            "M4b": [f"{name} 的行段写法不认"], "M4c": [f"函数表把 {name} 列了两次"],
            "M5": [f"（{self.title_rel} 那节）没有函数表"], "M5t": [f"（{self.tavern_rel} 那节）没有函数表"],
            "C1": [f"台账写 {name} 在拆前 Main.gd 的 {a}–{b + 47} 行，重算是 {a}–{b}"],
            "N1": [f"现 Main.gd 的 {self.tavern_last} 一行转发到本件 "],
            "N2": [f"台账写 {self.npc_row.group(1)} 在拆前 Main.gd 的 {self.npc_row.group(2)}–{int(self.npc_row.group(3)) + 2} 行，"
                   f"重算是 {self.npc_row.group(2)}–{self.npc_row.group(3)}"],
        }
        w["M1c"] = w["M1b"]
        return w.get(cid, [])


# (组, 编号, 说明, 变异, 期望对账 rc, 期望 ✗ 行须含的字样（编号 → Facts.want 现算）, 期望 --write 后对账 rc)；--write 判红的一律不许写盘
GEN_CASES = [
    ("对照", "C0", "台账不改", [], 0, [], 0),
    ("对照", "C1", "第十一刀最后一支行段写 en dash 且写错（cs23 前就红）",
     [l_row(K_TITLE, lambda ln, r: ln.replace(f"{r[2]}–{r[3]}", f"{r[2]}–{int(r[3]) + 47}", 1))], 1, "C1", 1),
    ("对照", "C2", "正文里提「第十一刀」（不是标题）",
     [l_head(K_TITLE, lambda h: h + f"\n\n本节即第{_cn(K_TITLE)}刀，承第{_cn(K_TITLE - 1)}刀。")], 0, [], 0),
    ("对照", "C3", "前三刀段改写成三节（第一至第三刀、各带函数表），现行（lane cs26：刀序起点由台账推）",
     [l_first_as_sections], 0, [], 0),
    ("对照", "C3′", "同 C3，刀序起点写死回第四刀（cs26 前）", [l_first_as_sections] + g_pre_cs26, 1,
     ["「第一刀」刀序不对：上一刀之后应是第 4 刀"], 1),
]
# 旧口径那格：同一变异，退回 cs23 前（M5t 退回 cs25 前）——(对账 rc, ✗ 字样)，--write 后对账都是 rc=0（空转）
_OLD = {"M1a": (1, [RESYNC]), "M1d": (1, [RESYNC]), "M1e": (1, [RESYNC]), "M1f": (1, [RESYNC]), "M2a": (1, [RESYNC]),
        "M2b": (1, [RESYNC]), "M2c": (0, []), "M2d": (1, [RESYNC]), "M3a": (0, []), "M3b": (0, []), "M3c": (0, []),
        "M4b": (0, []), "M4c": (0, []), "M5": (0, []), "M5t": (0, [])}
for cid, (what, muts) in M.items():
    grp = "⑤ 函数表（lane cs25）" if cid == "M5t" else "台账格式 " + what[0]
    GEN_CASES.append((grp, cid, what[1:] + "，现行", muts, 1, cid, 1))
    if cid in _OLD:
        rc, reds = _OLD[cid]
        pre = g_pre_cs25 if cid == "M5t" else g_pre_cs23
        GEN_CASES.append((grp, cid + "′", what[1:] + ("，NO_TABLE_OK 放行退回（cs25 前）" if cid == "M5t" else "，硬校验退回 cs23 前"),
                          muts + pre, rc, reds, 0))
GEN_CASES += [
    ("⑤ 函数表（lane cs25）", "N1", "第四刀函数表漏列最后一支（cs22 有表须列全）", [l_drop_row(K_TAVERN)], 1, "N1", 1),
    ("⑤ 函数表（lane cs25）", "N2", "第五刀函数表最后一支行段写错（逐支行段对账）",
     [l_row(K_NPC, lambda ln, r: ln.replace(f"{r[2]}–{r[3]}", f"{r[2]}–{int(r[3]) + 2}", 1))], 1, "N2", 1),
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
# 按形状认（lane cs26）：`sorted(self.rows, key=lambda …)` 那一处去掉排序、`pairs.sort(…)` 那一整行删掉；lambda 的变量名 / 键怎么写都落得上
d_unsort = [sub(REFS, r"sorted\(self\.rows, key=lambda \w+: [^\n]*\)(?=:[ \t]*$)", "self.rows"),
            sub(REFS, r"^[ \t]+pairs\.sort\([^\n]*\n", "")]
# lane cs26 ③：D2 原用历史基 `--since ccb1d57`，清单再改多轮后 ⚠ / ✗ 会少于 2 条、基还可能被改写的历史丢掉。改成相对基：
# 同 D1 把清单前 8 处号 +1 不提交，再 `--since HEAD`——走的是 --since 那条路（默认的改号自证不跑、配对取 REV 版清单），
# 比的是「HEAD 版清单的号 vs 工作树的号」，⚠ / ✗ 条数由变异自己造出来，不随历史变，不会过期。
SINCE = ["--since", "HEAD"]
# (组, 编号, 说明, 变异, 参数, 期望 rc, 期望确定, ⚠ / ✗ 行至少几条)
DET_CASES = [
    ("基线", "D0", "不改、默认口径", [], [], 0, True, 0),
    ("改号自证", "D1", "清单前 8 处 Main.gd 号 +1 不提交、默认口径，现行", [d_dirty], [], 1, True, 2),
    ("改号自证", "X1", "同 D1，两处排序都去掉（cs23 前）", [d_dirty] + d_unsort, [], 1, False, 2),
    ("--since", "D2", "同 D1 的脏树、`--since HEAD`（相对基，lane cs26），现行", [d_dirty], SINCE, 1, True, 2),
    ("--since", "X2", "同 D2，两处排序都去掉（cs23 前）", [d_dirty] + d_unsort, SINCE, 1, False, 2),
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
    _reset(wt, snap, [])
    try:  # 期望字样从快照台账里现算（lane cs26）；台账里连被变异那几处都找不到，要现算的各格一律「变异没落上」
        facts, facts_miss = Facts(_read(wt, LEDGER), wt), None
    except Miss as e:
        facts, facts_miss = None, e
    group = None
    for grp, cid, what, muts, want_rc, want_reds, want_after in GEN_CASES:
        if grp != group:
            print(f"  · {grp}")
            group = grp
        try:
            if isinstance(want_reds, str):
                if facts is None:
                    raise facts_miss
                want_reds = facts.want(want_reds)
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
    if rcs.get("C3′") == 1 and rcs.get("C3") == 0:  # lane cs26 ②：方向与上面相反——旧口径红、现行绿，证明起点真由台账推
        print("  ✓ 刀序起点：C3′ 起点写死第四刀，前三刀改写成三节 rc=1 → C3 现行由「已拆（前N刀…）」段推（段不在从第一刀起）rc=0")
    else:
        print(f"  ✗ 刀序起点：C3′ 写后 rc={rcs.get('C3′')}，C3 写后 rc={rcs.get('C3')}（应 1 → 0）")
        problems.append("空转对照不成立：C3")
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
