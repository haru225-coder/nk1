"""路径门禁共用的两步（lane cs20）：RefsMacPath（check_mac_paths）与 RefsHostPath（check_host_paths）同一口径，两边都从这里取。

  fold(line) -> str
      把一行里「字面量 / 家目录」之间的字符串拼接折成一段字面量，再交给各自的 PATTERNS：
        `"A" + "B"` → "AB"；`"A".path_join("B")` / `.joinpath("B")` → "A/B"；`os.path.join("A", "B", …)` / 裸 `join(…)` → "A/B/…"；
        `Path("A") / "B"` → "A/B"；`"%s/B" % "A"` → "A/B"（只替第一个 %s）；
      家目录取法先换成字面量 "$HOME"：`OS.get_environment("HOME")`、`System.getenv("HOME")` / `System.get_env("HOME")`、
      `os.getenv("HOME")`、`os.environ["HOME"]` / `.get("HOME")`、`Path.home()`、`os.path.expanduser("~")`，
      f-string 里的 `{…}` 家目录同样摊平。变量名不追（`base + "/x"` 里 base 是什么不管），所以只会比原文多认、不会少认。
  comment_spans(rel, text) -> {行号: [(起, 止), …]}
      代码文件（CODE_EXT）每行里「注释 / 文档串」占的列区间，区间外才是代码段；非代码文件不在此列（整份都算文档）。
        .py      tokenize 取 `#` 注释（字符串里的 `#` 不算），ast 取各级文档串（整行）；解析不了退回下面的通用扫法；
        .gd      `#` 起到行尾（字符串 "…" / '…' / 三引号里的不算）；独占语句的三引号串（GDScript 的块注释写法）整段算文档；
        .sh      `#` 在词首（行首或空白 / ; & | ( 之后）才起注释，`$#`、`${#a}`、引号里的都不算；heredoc 正文不认（照代码判，偏严）；
        .gdshader `//` 起到行尾、`/* … */` 块（可跨行）。
"""
import ast, io, re, tokenize

CODE_EXT = (".gd", ".py", ".sh", ".gdshader")

# ---- fold ----

_LIT = r"""[rRbBfFuU&^]{0,2}(?:"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')"""
_HOME = (r"\bOS\.get_environment\(\s*[\"']HOME[\"']\s*\)"
         r"|\bSystem\.get_?env\(\s*[\"']HOME[\"']\s*\)"
         r"|\bos\.getenv\(\s*[\"']HOME[\"'][^()]*\)"
         r"|\bos\.environ(?:\.get\(\s*[\"']HOME[\"'][^()]*\)|\[\s*[\"']HOME[\"']\s*\])"
         r"|\b(?:pathlib\.)?Path\.home\(\)"
         r"|\bos\.path\.expanduser\(\s*[\"']~[\"']\s*\)")
_TOK = re.compile(f"(?P<h>{_HOME})|(?P<s>{_LIT})")
_FHOME = re.compile(r"\{\s*(?:" + _HOME + r")\s*\}")
_P = "\0(\\d+)\0"  # 字面量占位：第 N 段
_FOLDS = [
    (re.compile(rf"{_P}\s*\+\s*{_P}"), ""),                                                        # "A" + "B"
    (re.compile(rf"{_P}\s*\.\s*(?:path_join|joinpath)\(\s*{_P}\s*\)"), "/"),                       # "A".path_join("B")
    (re.compile(rf"(?<![\w.])(?:(?:os\.)?path\.|posixpath\.)?join\(\s*{_P}\s*,\s*{_P}"), "/join("),  # join("A", "B" …) 逐个吞参
    (re.compile(rf"(?<![\w.])(?:pathlib\.)?(?:Pure)?(?:Posix)?Path\(\s*{_P}\s*\)"), None),        # Path("A") → "A"
    (re.compile(rf"{_P}\s*/\s*{_P}"), "/"),                                                        # Path("A") / "B"
    (re.compile(rf"{_P}\s*%\s*{_P}"), "%"),                                                        # "%s/B" % "A"
]
# 预筛：行里没有「引号紧挨拼接符」、join( / Path( / 家目录取法，就没有可折的，原样返回（全仓逐行跑，省掉九成以上的 fold）
_QUICK = re.compile(r"""["']\s*(?:\+|/|%|\.\s*(?:path_join|joinpath)\()|(?:\+|/|%)\s*[rRbBfFuU&^]{0,2}["']|join\(|Path\b|HOME|expanduser""")
_JOIN_END = re.compile(rf"(?<![\w.])(?:(?:os\.)?path\.|posixpath\.)?join\(\s*{_P}\s*\)")        # 吞完参数的 join("A/B") → "A/B"


def _body(lit):
    """字面量去前缀与引号；f-string 里的家目录 {…} 摊成 $HOME。"""
    i = next(k for k, c in enumerate(lit) if c in "\"'")
    body = lit[i + 1:-1]
    return _FHOME.sub("$HOME", body) if "f" in lit[:i].lower() else body


def _slash(a, b):
    return a.rstrip("/") + "/" + b.lstrip("/") if a and b else a + b


def fold(line):
    """见模块头。返回折完的一行（字面量一律写成 "…"）；预筛不过（没有可折的）原样返回。"""
    if not _QUICK.search(line):
        return line
    parts = []

    def keep(m):
        parts.append("$HOME" if m.group("h") else _body(m.group("s")))
        return f"\0{len(parts) - 1}\0"

    s = _TOK.sub(keep, line)
    if len(parts) > 1 or "join(" in s or "Path(" in s:
        for _ in range(32):
            before = s
            for rx, how in _FOLDS:
                def merge(m):
                    a, b = (parts[int(g)] for g in m.groups()) if how is not None else (parts[int(m.group(1))], None)
                    if how is None:
                        v = a
                    elif how == "%":
                        v = a.replace("%s", b, 1) if "%s" in a else a
                    elif how == "":
                        v = a + b
                    else:
                        v = _slash(a, b)
                    parts.append(v)
                    return (f"join(\0{len(parts) - 1}\0" if how == "/join(" else f"\0{len(parts) - 1}\0")
                s = rx.sub(merge, s)
            s = _JOIN_END.sub(lambda m: m.group(0)[m.group(0).index("\0"):m.group(0).rindex("\0") + 1], s)
            if s == before:
                break
    return re.sub(_P, lambda m: '"' + parts[int(m.group(1))] + '"', s)


# ---- comment_spans ----

def _scan(lines, hash_ok, triple, block, sh):
    """通用扫法：返回 {行号: [(起, 止)]}。hash_ok(ln, i) 判 `#` 是否起注释；triple 认三引号串；block 认 // 与 /* */。"""
    spans = {}
    add = lambda n, a, b: spans.setdefault(n, []).append((a, b))
    state = None          # None | 引号 | 三引号 | "/*"
    doc = None            # 三引号串独占语句时：(起始行, 起始列)
    for n, ln in enumerate(lines, 1):
        i = 0
        if state == "/*":
            j = ln.find("*/")
            if j < 0:
                add(n, 0, len(ln))
                continue
            add(n, 0, j + 2)
            state, i = None, j + 2
        while i < len(ln):
            c = ln[i]
            if state is None:
                if block and ln.startswith("//", i):
                    add(n, i, len(ln))
                    break
                if block and ln.startswith("/*", i):
                    j = ln.find("*/", i + 2)
                    if j < 0:
                        add(n, i, len(ln))
                        state = "/*"
                        break
                    add(n, i, j + 2)
                    i = j + 2
                    continue
                if c == "#" and hash_ok(ln, i):
                    add(n, i, len(ln))
                    break
                if c == "\\" and sh:
                    i += 2
                    continue
                if triple and ln.startswith(('"""', "'''"), i):
                    state = ln[i:i + 3]
                    doc = (n, i) if not ln[:i].strip() else None
                    i += 3
                    continue
                if c in "\"'":
                    state = c
                i += 1
            elif len(state) == 3:
                if c == "\\":
                    i += 2
                    continue
                if ln.startswith(state, i):
                    state, i = None, i + 3
                    rest = ln[i:].lstrip()
                    if doc and (not rest or rest.startswith("#")):
                        (n0, c0) = doc
                        for k in range(n0, n + 1):
                            add(k, c0 if k == n0 else 0, i if k == n else len(lines[k - 1]))
                    doc = None
                    continue
                i += 1
            else:
                if c == "\\" and not (sh and state == "'"):
                    i += 2
                    continue
                if c == state:
                    state = None
                i += 1
        if state in ('"', "'") and not sh:
            state = None      # 单行引号没收尾：GDScript / Python 里不跨行，下一行重来
    return spans


def comment_spans(rel, text):
    """见模块头；非代码文件返回 None（调用方整份当文档）。"""
    if not rel.endswith(CODE_EXT):
        return None
    lines = text.splitlines()
    if rel.endswith(".sh"):
        return _scan(lines, lambda ln, i: i == 0 or ln[i - 1] in " \t;&|()", False, False, True)
    if rel.endswith(".gdshader"):
        return _scan(lines, lambda ln, i: False, False, True, False)
    if rel.endswith(".gd"):
        return _scan(lines, lambda ln, i: True, True, False, False)
    try:
        spans = {}
        for t in tokenize.generate_tokens(io.StringIO(text).readline):
            if t.type == tokenize.COMMENT:
                spans.setdefault(t.start[0], []).append((t.start[1], len(lines[t.start[0] - 1])))
        for node in ast.walk(ast.parse(text)):
            body = getattr(node, "body", None)
            if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                    and isinstance(getattr(body[0], "value", None), ast.Constant) and isinstance(body[0].value.value, str):
                for k in range(body[0].lineno, body[0].end_lineno + 1):
                    spans.setdefault(k, []).append((0, len(lines[k - 1])))
        return spans
    except (SyntaxError, ValueError, tokenize.TokenError, IndentationError):
        return _scan(lines, lambda ln, i: True, True, False, False)


def split(ln, spans):
    """(代码段, 注释 / 文档段)：spans 为该行区间表（None / 空 = 整行代码）；代码段各片之间留一个空格。"""
    if not spans:
        return ln, ""
    code, doc, i = [], [], 0
    for a, b in sorted(spans):
        if a > i:
            code.append(ln[i:a])
        doc.append(ln[max(a, i):b])
        i = max(i, b)
    code.append(ln[i:])
    return " ".join(p for p in code if p.strip()), " ".join(doc)
