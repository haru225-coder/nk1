"""按函数名取函数体 + 取不到即红的记账（lane gd16 / cs9 起于 check_symbols，lane cs14 抽成共用件）。

取不到原先静默给 ""：正向断言（"X" in body）跟着红还算露馅，反向断言（"X" not in body / not any(…)）却照样绿——
函数改了名 / 被删 / 搬走没拼回，断言就空转。手切的（`src.split("func X", 1)`、`src.find("func X")`、
不锚行首 / 名尾的正则）还只按前缀认名字，改名成 X_v2 照样切到它。所以：
  locate_func(src, name)  只认行首 `[static ]func 名字(`（名尾须紧跟括号，不吃前缀、不认注释），
                          体到下一个行首 func / static func 为止；取不到给 "" 并记账。
  body_ask(name, found)   各脚本自带的按名取体 helper（切法与 locate_func 不同的）取完调它记同一本账。
  body_asks / missed()    账本：(调用处在本脚本的行号, 函数名) -> 取到没有；门禁在末节逐条判红。
check_symbols（「十三、」）与 verify_economy（「十一、」）共用这一份，别各起一套。
只想探有没有这支函数、不想判红的，别走这里（check_symbols 用 `name in func_bodies(src)`）。
"""
import re
import sys

body_asks = {}  # (本脚本行号, 函数名) -> 取到没有；同一行多次取（循环 / 变异自检）按一处计，有一次取不到就算取不到


def body_ask(name, found, depth=2):
    """记一笔：depth 数到「写断言那一行」的栈帧（缺省 2 = 调本函数的 helper 的调用方）。"""
    key = (sys._getframe(depth).f_lineno, name)
    body_asks[key] = body_asks.get(key, True) and found


def locate_func(src, name):
    m = re.search(rf"^(?:static\s+)?func\s+{re.escape(name)}\s*\(.*?(?=\n(?:static\s+)?func\s|\Z)", src, re.M | re.S)
    body_ask(name, m is not None)
    return m.group(0) if m else ""


def missed():
    """取不到的 (行号, 函数名)，按行号排。"""
    return sorted(k for k, found in body_asks.items() if not found)
