"""按名认函数的源码探查（lane cs10 起于 check_symbols，lane cs15 抽成共用件）。

光秃子串认名只按前缀认：`"X" in src` 认到 X_v2，`"X(" in body` 认到 _X( / fooX(，`src.find("X")` 定位锚落到 _X 上。
函数一改名（调用点同改），这些正向断言照样打「已定义 / 已调用」，函数里写什么都不会红。一律改走这里：
  has_func(src, name)        行首 `[static ]func 名字(`（名尾须紧跟括号，不认 X_v2 / 注释 / 文案里的字样）；
                             static=True 时须带 static（原写 `"static func X" in src` 的）。
  calls(src, name)           按名调用 `名字(` 或取 Callable `名字.bind(` / `.call(` / `.callv(`；名前不接标识符或点
                             （名字可带宿主 `ShoreDraft.deal`，宿主前同样不接标识符或点）。
  has_tok(src, lit)          字面量按标识符边界认：头是标识符字符就要求前面不接标识符字符（`add_fame(3)` 不认
                             `_add_fame(3)`，认 `GameState.add_fame(3)`），尾是标识符字符就要求后面不接（`X` 不认 X_v2）。
                             call=True：lit 是（可带宿主的）名字，后面须紧跟 `(` 或 `.bind(` 等——即 `\\bX\\s*\\(`，宿主不限。
  tok_find / tok_count       同一口径的 find / count（find 取不到给 -1，与 str.find 同）。
每处新条件都严格蕴含旧的子串条件（正则命中必然含旧子串），只收紧不放宽。
"""
import re

_CALL_TAIL = r"\s*(?:\(|\.(?:bind|call|callv)\s*\()"


def has_func(src, name, static=False):
    head = r"static\s+" if static else r"(?:static\s+)?"
    return re.search(rf"^[ \t]*{head}func\s+{re.escape(name)}\s*\(", src, re.M) is not None


def calls(src, name):
    return re.search(rf"(?<![\w.]){re.escape(name)}{_CALL_TAIL}", src) is not None


def tok_rx(lit, call=False):
    p = re.escape(lit)
    if re.match(r"\w", lit):
        p = r"(?<!\w)" + p
    if call:
        p += _CALL_TAIL
    elif re.search(r"\w$", lit):
        p += r"(?!\w)"
    return re.compile(p)


def has_tok(src, lit, call=False):
    return tok_rx(lit, call).search(src) is not None


def tok_find(src, lit, start=0, call=False):
    m = tok_rx(lit, call).search(src, start)
    return m.start() if m else -1


def tok_count(src, lit, call=False):
    return len(tok_rx(lit, call).findall(src))
