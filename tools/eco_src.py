#!/usr/bin/env python3
"""经济镜像常量从生产 .gd 源码现读（lane w53-3）：verify_economy / simulate_run 两支镜像共用一份读法，
simulate_run 镜像闸 C 也用这里的改写法在临时副本里改值、验两支镜像跟着变。

原先两支镜像把抽解 / 佣金 / 价差地板 / 产地消费地系数 / 行情上下限与回归 / 通事生效港 / 杂事通事每级系数 /
水粮占舱与人日 / 赊贷上限与月息各硬编一份，生产改值时镜像悄悄散、门禁照绿。读不出（写法换了）一律退出，不落回旧值。

认的写法（类成员顶格声明；缩进的函数局部变量不认）：
  · 数：`const NAME := 1.08`、`var NAME: float = 0.10`、`var NAME := 0.10`
  · 字面量：`const NAME := {"origin": 0.65, …}` / `[…]`，单行、JSON 同形
  · 系数：函数体里 `<数> * level_of("<职>")`（Crew 各职事每级系数：杂事 0.12、通事 0.07、火长 0.06、舵工 0.05、总管 0.17、医人 0.23）
  · 底数：函数体里 `return <底数> + <数> * level_of("<职>")`（Crew.wind_floor 的 0.40）
"""
import json, os, re

_NUM = r'^((?:const|var)\s+%s\s*(?::\s*\w+\s*)?:?=\s*)(-?[0-9]+(?:\.[0-9]+)?)'
_LIT = r'^(const\s+%s\s*:=\s*)(\{[^\n]*\}|\[[^\n]*\])[ \t]*$'
_FUNC = r'^(?:static\s+)?func\s+%s\s*\([^\n]*\n(?:[ \t]+[^\n]*\n|[ \t]*\n)*'
_COEFF = r'(-?[0-9]+(?:\.[0-9]+)?)(\s*\*\s*level_of\("%s"\))'
_OFFSET = r'(return\s+)(-?[0-9]+(?:\.[0-9]+)?)(\s*\+\s*-?[0-9]+(?:\.[0-9]+)?\s*\*\s*level_of\("%s"\))'


class EcoSrc:
    """按仓库根读 .gd 源码（同一文件只读一次）；who 写进认不出时的退出原因。"""

    def __init__(self, root, who="eco_src"):
        self.root, self.who, self._src = root, who, {}

    def src(self, rel):
        if rel not in self._src:
            with open(os.path.join(self.root, rel), encoding="utf-8") as f:
                self._src[rel] = f.read()
        return self._src[rel]

    def _fail(self, rel, what):
        raise SystemExit(f"{self.who}：{rel} 里认不出 {what}（写法换了就改 tools/eco_src.py 的读法，别在镜像里写回字面量）")

    def num(self, rel, name, default=None):
        """数值初值；default 为 None 时认不出即退出。"""
        m = re.search(_NUM % re.escape(name), self.src(rel), re.M)
        if m:
            return float(m.group(2))
        if default is None:
            self._fail(rel, f"{name} 的数值初值")
        return default

    def literal(self, rel, name):
        """单行 {…} / […] 字面量（JSON 同形）。"""
        m = re.search(_LIT % re.escape(name), self.src(rel), re.M)
        try:
            return json.loads(m.group(2)) if m else self._fail(rel, f"{name} 的字面量")
        except ValueError:
            self._fail(rel, f"{name} 的字面量（不是 JSON 同形）")

    def coeff(self, rel, func, role):
        """func 函数体里 `<数> * level_of("<role>")` 的那个数。"""
        f = re.search(_FUNC % re.escape(func), self.src(rel), re.M)
        m = re.search(_COEFF % re.escape(role), f.group(0)) if f else None
        if not m:
            self._fail(rel, f"{func} 里 <数> * level_of(\"{role}\") 的系数")
        return float(m.group(1))

    def offset(self, rel, func, role):
        """func 函数体里 `return <底数> + <数> * level_of("<role>")` 的底数（Crew.wind_floor 的 0.40）。"""
        f = re.search(_FUNC % re.escape(func), self.src(rel), re.M)
        m = re.search(_OFFSET % re.escape(role), f.group(0)) if f else None
        if not m:
            self._fail(rel, f"{func} 里 return <底数> + <数> * level_of(\"{role}\") 的底数")
        return float(m.group(2))


## ── 改写（镜像闸 C 在临时副本里用）：返回 (改后的源码, 改中几处)，与上面的读法同一套正则 ──

def edit_num(src, name, val):
    return re.subn(_NUM % re.escape(name), lambda m: m.group(1) + repr(val), src, count=1, flags=re.M)


def edit_literal(src, name, val):
    return re.subn(_LIT % re.escape(name), lambda m: m.group(1) + json.dumps(val, ensure_ascii=False), src, count=1, flags=re.M)


def edit_coeff(src, func, role, val):
    f = re.search(_FUNC % re.escape(func), src, re.M)
    if not f:
        return src, 0
    body, n = re.subn(_COEFF % re.escape(role), lambda m: repr(val) + m.group(2), f.group(0), count=1)
    return src[:f.start()] + body + src[f.end():], n


def edit_offset(src, func, role, val):
    f = re.search(_FUNC % re.escape(func), src, re.M)
    if not f:
        return src, 0
    body, n = re.subn(_OFFSET % re.escape(role), lambda m: m.group(1) + repr(val) + m.group(3), f.group(0), count=1)
    return src[:f.start()] + body + src[f.end():], n
