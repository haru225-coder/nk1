"""按函数名取函数体 + 取不到即红的记账（lane gd16 / cs9 起于 check_symbols，lane cs14 抽成共用件）。

取不到原先静默给 ""：正向断言（"X" in body）跟着红还算露馅，反向断言（"X" not in body / not any(…)）却照样绿——
函数改了名 / 被删 / 搬走没拼回，断言就空转。手切的（`src.split("func X", 1)`、`src.find("func X")`、
不锚行首 / 名尾的正则）还只按前缀认名字，改名成 X_v2 照样切到它。所以：
  locate_func(src, name)  只认行首 `[static ]func 名字(`（名尾须紧跟括号，不吃前缀、不认注释），
                          体到下一个行首 func / static func 为止；取不到给 "" 并记账。
  body_ask(name, found)   各脚本自带的按名取体 helper（切法与 locate_func 不同的）取完调它记同一本账。
  body_asks / missed()    账本：(调用处在本脚本的行号, 函数名) -> 取到没有；门禁在末节逐条判红。
一行转发也算取不到（lane cs17）：Main 拆走一刀后留下 `func X(…):\n\t_K.x(self, …)`，按名切 Main 照样切得到，
体里却只有一行调用——真身在别的文件，正向断言跟着红还算露馅，反向断言照样绿。forward_of(body) 认这种形状：
  去掉签名后函数体（缩进块，签名同行冒号后的也算）只剩一行代码（注释 / 空行不算），整行是 `[return ][await ]callee(实参)`，并且
  (a) callee 是 `_大写常量.fn`（Main 拆出件 / preload 件的转发写法，实参不限），或
  (b) callee 是点号名（`fn` / `obj.fn`），实参至少一个、个个都是本函数的形参或 self——原样传参给别的函数
      （`func get_monsoon(month): return monsoon_of(month)`、NpcPage 转回 Main 的 `main._show_npc_mode(npc_id, …)`）。
      (b) 要看形参，body 须带签名；不带签名的只按 (a) 认。
  (c) callee 是同一份源码里的另一支 func（不带点号），零实参——同文件改名后留的别名（`func _x():\n\t_x_real()`，lane gd23）。
  给了 src（取体那份源码）再按它收口（lane gd23，与 cs8 拼回口径对齐，见 docs/GATES.md §三「转发判据三片对账」）：
    (a) 的 `_K` 须是 preload 常量——src 里 `const _K := {…}` / `Color(…)` 一类的是容器 / 值，`_K.get(k)` 是真实现；
    (b) / (c) 不带点号的 callee 须是 src 里的 func——`str(x)` / `abs(x)` 一类内建不算；
        (b) 带点号的，接收者须是形参 / self、大写开头的名字（autoload / class_name）或 preload 常量——
        小写成员变量（`_cache.has(key)`、`_json_cache.erase(path)`）是内建容器方法，没有可取的真身。
  一行 `return <expr>` 不一概算：实参里有运算 / 嵌套调用 / 常量 / 零实参的是真实现（`return clampf(Fleet.fleet_speed() / 220.0, 0.25, 0.9)`、
  `DirAccess.make_dir_recursive_absolute(SAVE_DIR)`、`return discoveries_found.duplicate()`），不算转发；
  两行以上的不认（「体只有一行」才判）。
locate_func / body_ask(…, body=体) 取到转发一律记成取不到（账上另记转发目标，门禁报「只取到一行转发」）；
本来就要读转发那一行的，传 forward_ok=True 放行——只给这三类：顺调用链展开（转发照跟）、钉「Main 只许一行转发」、
先读转发再顺藤去拆出件取真身（取真身那一下照常记账）。别拿它给「该改读拆出件」的断言消红。
check_symbols（「十三、」）与 verify_economy（「十一、」）共用这一份，别各起一套。
只想探有没有这支函数、不想判红的，别走这里（check_symbols 用 `name in func_bodies(src)`）。
"""
import re
import sys

body_asks = {}  # (本脚本行号, 函数名) -> 取到没有；同一行多次取（循环 / 变异自检）按一处计，有一次取不到就算取不到
forwards = {}   # (本脚本行号, 函数名) -> 转发目标（`_K.fn` / 同文件的 `fn`）：这处取到的只是一行转发，已记成取不到

_FWD_CALL = re.compile(r"(?:return\s+)?(?:await\s+)?([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\((.*)\)")


def _split_top(s):
    """实参按顶层逗号切；括号不配平给 None（整行不是一个调用，如 `f(a) + g(b)`）。"""
    out, depth, cur, quote, esc = [], 0, "", None, False
    for c in s:
        if quote:
            quote, esc = (None if c == quote and not esc else quote), (c == "\\" and not esc)
        elif c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth < 0:
                return None
        elif c == "," and depth == 0:
            out.append(cur.strip()); cur = ""
            continue
        cur += c
    if depth or quote:
        return None
    return out + [cur.strip()] if cur.strip() else out


def _const_kind(src, k):
    """src 里 `const k` 的右值：preload 给 "preload"，别的给 "value"，没有这个常量给 None。"""
    m = re.search(rf"^const\s+{re.escape(k)}\b[^=\n]*=\s*(\S)", src, re.M)
    return None if not m else ("preload" if src.startswith("preload(", m.start(1)) else "value")


def _has_func(src, name):
    return re.search(rf"^(?:static\s+)?func\s+{re.escape(name)}\s*\(", src, re.M) is not None


def forward_of(body, src=None):
    """body 是一行转发就给转发目标（callee 字样），否则 None。body 带不带 `func X(…):` 签名都行；
    src = 取体的那份源码（给了才按它收口 (a) / (b)、才认 (c)，见模块头注）。"""
    code, params = body, None
    head = re.match(r"\s*(?:static\s+)?func\s+[A-Za-z_]\w*\s*\(", code)
    if head:  # 去签名：括号配平后第一个冒号之后才是函数体（签名可折行、可带 -> 返回类型）
        depth, i = 1, head.end()
        while i < len(code) and depth:
            depth += {"(": 1, ")": -1}.get(code[i], 0)
            i += 1
        params = {re.match(r"\s*(\w*)", a).group(1) for a in (_split_top(code[head.end():i - 1]) or [])} | {"self"}
        colon = code.find(":", i)
        code = code[colon + 1:] if colon >= 0 else ""
    # 函数体 = 签名同一行冒号后的余下 + 其后的缩进行；遇到顶格代码行（locate_func 会把其后的顶格 const / var 一起切进来）即止
    first, *rest = code.split("\n")
    block = [first]
    for ln in rest:
        if ln.strip() and not ln[0].isspace() and not ln.startswith("#"):
            break
        block.append(ln)
    lines = [re.sub(r"\s+#[^\"']*$", "", ln.strip()) for ln in block if ln.strip() and not ln.strip().startswith("#")]
    if len(lines) != 1:
        return None
    m = _FWD_CALL.fullmatch(lines[0])
    args = _split_top(m.group(2)) if m else None
    if args is None:
        return None
    callee = m.group(1)
    recv = callee.split(".")[0] if "." in callee else None
    if re.match(r"_[A-Z][A-Z0-9_]*\.", callee):  # (a)
        return callee if src is None or _const_kind(src, recv) != "value" else None
    if src is not None:
        if recv is None and not _has_func(src, callee):
            return None  # 内建 / 全局函数，没有可取的真身
        if recv is not None and not (recv in (params or ()) or recv == "self" or recv[0].isupper()
                                     or (recv[0] == "_" and recv[1:2].isupper() and _const_kind(src, recv) != "value")):
            return None  # 接收者是成员变量：内建容器方法
        if recv is None and not args:  # (c)
            return callee
    if params and args and all(a in params for a in args):  # (b)
        return callee
    return None


def body_ask(name, found, depth=2, body=None, forward_ok=False, src=None):
    """记一笔：depth 数到「写断言那一行」的栈帧（缺省 2 = 调本函数的 helper 的调用方）。
    给了 body 且它只是一行转发（forward_of；src = 取体的那份源码），不传 forward_ok 就记成取不到。"""
    key = (sys._getframe(depth).f_lineno, name)
    fwd = forward_of(body, src) if found and body and not forward_ok else None
    if fwd:
        forwards[key] = fwd
    body_asks[key] = body_asks.get(key, True) and found and not fwd


def locate_func(src, name, forward_ok=False):
    m = re.search(rf"^(?:static\s+)?func\s+{re.escape(name)}\s*\(.*?(?=\n(?:static\s+)?func\s|\Z)", src, re.M | re.S)
    body_ask(name, m is not None, body=m and m.group(0), forward_ok=forward_ok, src=src)
    return m.group(0) if m else ""


def missed():
    """取不到的 (行号, 函数名)，按行号排（含只取到一行转发的，见 forwards）。"""
    return sorted(k for k, found in body_asks.items() if not found)


def forward_note(target):
    """「只取到一行转发」后半句：转发目标不带点号 = 同文件别名（lane gd23），带点号 = 真身在别的文件 / 对象上。"""
    if "." not in target:
        return f"只取到一行转发（→ {target}），真身是同一份源码里的 {target}（改名后留了别名 / 该改取 {target}）"
    return f"只取到一行转发（→ {target}），真身不在这份源码里（拆走没拼回 / 该改读拆出件）"


def miss_why(key, file):
    """十三 / 十一节判红的那句话：取不到 / 只取到一行转发分开说。"""
    ln, name = key
    if key in forwards:
        return f"{file}:{ln} 取函数体 {name} {forward_note(forwards[key])}，这处断言在空转"
    return f"{file}:{ln} 取函数体 {name} 取不到（改名 / 删了 / 搬走没拼回），这处断言在空转"
