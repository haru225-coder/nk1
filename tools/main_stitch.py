"""Main.gd + 拆出件拼回「未拆时」的 Main 源码（lane cs8 立于 check_symbols；lane auditfix6 抽成共用件，verify_economy 也读它）。

Main.gd 拆出去的件（lane ms 起）：Main 留同名同签名一行转发 `[return |await ]_K.fn(…)`，真身在拆出件里。
按名直读 Main.gd 取体，拆走一刀就只取到那一行转发——func_body 记成取不到判红（lane cs17），子串断言跟着假红，
下一刀就得把断言逐条改读拆出件（main10 船屋那刀改了 verify_economy 6 条）。源码断言读 read_main_src() 拼回的这份就不用跟：
  - Main 里一行转发到拆出件的 func，函数体就地换成拆出件里那支 static func 的函数体；
    转发时传 self 的形参（如 main），函数体里的 `main.` 前缀去掉、裸 `main` 换回 self——拼出来就是搬走前的原文；
  - 拆出件里没被转发到的其余部分（helper / 常量）追加在末尾，static func 记成 func，func_bodies() 照样切得到。
拆出件清单只有一份：tools/main_splits.txt（lane cs13，gen_main_splits.read_splits 读第一列）。
拼回只对「源码字符串断言」有效（口径见 docs/GATES.md §三.1）：拼出来的行号不对应任何真文件、`main.` 前缀已去掉、
static / 实例语义不看；这些要读拆出件原文或交 compile / 探针。拼回漏不漏由 check_symbols「一之零」兜住
（读下面 _split_report / _split_fwd_count / _nonsplit_fwd 三张表，每次拼回时重填）。
本来就要读 Main.gd 原文的（「Main 只许一行转发」的钉子、connect 目标得是 Main 自己的成员）别走这里。
not_splits：Main 里一行转发形状、但目标不是拆出件的委托（check_symbols 的 MAIN_NOT_SPLITS），只影响 _split_report 报不报。
"""
import os
import re

import gen_main_splits

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN_SPLITS = gen_main_splits.read_splits()
_SPLIT_FWD = re.compile(r'^\t(?:return |await )?(_[A-Z][A-Z0-9_]*)\.([A-Za-z_]\w*)\((.*)\)\s*$')
_split_report = []
_split_fwd_count = {}
_nonsplit_fwd = {}  # 非拆出件路径 -> [(Main 函数名, 目标函数名)]：Main 里一行转发到它的各支（MAIN_NOT_SPLITS 失效判据用）


def _top_level_chunks(src):
    """按顶格行切块：[(头行, [续行…])]。func 的签名 + 函数体、const、注释都各成一块；
    多行签名 / 括号续行归前一块（缩进行与空行都算续行）。"""
    chunks = []
    for ln in src.split("\n"):
        if chunks and (ln == "" or ln[0].isspace() or ln.startswith(")")):
            chunks[-1][1].append(ln)
        else:
            chunks.append((ln, []))
    return chunks


def _split_args(s):
    out, depth, cur = [], 0, ""
    for c in s:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur.strip())
    return out


def read_main_src(not_splits=()):
    """Main.gd + MAIN_SPLITS 拼成一份「未拆时」的 Main 源码：
    - Main 里一行转发到拆出件的 func，函数体就地换成拆出件里那支 static func 的函数体；
      转发时传 self 的形参（如 main），函数体里的 `main.` 前缀去掉、裸 `main` 换回 self——拼出来就是搬走前的原文；
    - 拆出件里没被转发到的其余部分（helper / 常量）追加在末尾，static func 记成 func，func_bodies() 照样切得到。
    拆走函数后，断言不会因为只看见一行转发而假绿（尤其是「某字样不得出现」一类的反向断言）。"""
    _split_report.clear()
    _split_fwd_count.clear()
    _nonsplit_fwd.clear()
    with open(os.path.join(ROOT, "scripts", "Main.gd"), encoding="utf-8") as f:
        main_text = f.read()
    const_of, other_of = {}, {}
    for m in re.finditer(r'^const\s+(_[A-Z][A-Z0-9_]*)\s*:?=\s*preload\("res://([^"]+)"\)', main_text, re.M):
        (const_of if m.group(2) in MAIN_SPLITS else other_of)[m.group(1)] = m.group(2)
    _uses = re.compile(r'\b(' + "|".join(map(re.escape, const_of)) + r')\.') if const_of else None
    parts = {}
    for rel in MAIN_SPLITS:
        if not os.path.isfile(os.path.join(ROOT, rel)):
            _split_report.append(f"{rel} 登记在 tools/main_splits.txt，文件却不存在（删了拆出件没更新清单），拼回跳过它")
            parts[rel] = {"funcs": {}, "rest": [], "used": set(), "fwd": 0, "gone": True}
            continue
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            funcs, rest = {}, []
            for head, tail in _top_level_chunks(f.read()):
                m = re.match(r'^static\s+func\s+([A-Za-z_]\w*)\s*\(', head)
                if m:
                    funcs[m.group(1)] = (head, tail)
                elif not head.startswith(("extends ", "class_name ")):
                    rest.append((head, tail))
            parts[rel] = {"funcs": funcs, "rest": rest, "used": set(), "fwd": 0}
    out = []
    for head, tail in _top_level_chunks(main_text):
        m = re.match(r'^func\s+[A-Za-z_]\w*', head)
        code = [ln for ln in tail if ln.strip() and not ln.strip().startswith("#")]
        fwd = _SPLIT_FWD.match(code[0]) if m and len(code) == 1 else None
        rel = const_of.get(fwd.group(1)) if fwd else None
        fname = head.split("(")[0]
        if m and rel is None and _uses and _uses.search("\n".join(code)):
            _k = _uses.search("\n".join(code)).group(1)
            _split_report.append(f"{fname} 调了拆出件 {const_of[_k]}（{_k}.…）却不是一行转发，拼回不认、"
                                 f"函数体断言只看得到 Main 这几行（转发须独占函数体：`\\t[return |await ]{_k}.fn(…)`，"
                                 f"行尾不带注释、签名不折行）")
        if fwd and fwd.group(1) in other_of:
            _nonsplit_fwd.setdefault(other_of[fwd.group(1)], []).append((fname[len("func "):].strip(), fwd.group(2)))
        if fwd and fwd.group(1) in other_of and other_of[fwd.group(1)] not in not_splits:
            _split_report.append(f"{fname} 一行转发到 {other_of[fwd.group(1)]}，它没登记进 MAIN_SPLITS，函数体不拼回"
                                 f"（是拆出件就在 docs/Main拆解台账.md 追加一节、跑 tools/gen_main_splits.py --write；不是就加进 check_symbols 的 MAIN_NOT_SPLITS 并注明）")
        if rel is None:
            out.append((head, tail))
            continue
        part, name = parts[rel], fwd.group(2)
        if name not in part["funcs"]:
            _split_report.append(f"{head.split('(')[0]} 转发到 {rel} 的 {name}，那边没有这支 static func")
            out.append((head, tail))
            continue
        p_head, p_tail = part["funcs"][name]
        part["used"].add(name)
        part["fwd"] += 1
        # 签名可能折行：括号配平、以 : 收尾的那行之后才是函数体
        sig_lines, depth = [], 0
        for ln in [p_head] + p_tail:
            sig_lines.append(ln)
            depth += sum(ln.count(c) for c in "([{") - sum(ln.count(c) for c in ")]}")
            if depth == 0 and ln.rstrip().endswith(":"):
                break
        sig = " ".join(sig_lines)
        sig = sig[sig.index("(") + 1:sig.rindex(")")]
        params = [a.split(":")[0].split("=")[0].strip() for a in _split_args(sig)]
        args = _split_args(fwd.group(3))
        body = "\n".join(p_tail[len(sig_lines) - 1:])
        for pname, arg in zip(params, args):
            if arg == "self" and pname:
                body = re.sub(rf'\b{pname}\.', "", body)
                body = re.sub(rf'\b{pname}\b', "self", body)
        # 转发体里的注释照留，转发那一行由搬来的函数体顶上
        notes = [ln for ln in tail if ln.strip().startswith("#")]
        out.append((head, notes + body.split("\n")))
    for rel in MAIN_SPLITS:
        part = parts[rel]
        _split_fwd_count[rel] = part["fwd"]
        if part.get("gone"):
            continue
        if part["fwd"] == 0:
            _split_report.append(f"{rel} 登记为 Main 拆出件，但 Main 里没有一行转发接到它（或没 preload）")
        out.append((f"# ── 以下自 {rel} 拼入（未被转发的 helper / 常量） ──", []))
        for name, (p_head, p_tail) in part["funcs"].items():
            if name not in part["used"]:
                out.append((re.sub(r'^static\s+', "", p_head), p_tail))
        out.extend(part["rest"])
    return "\n".join("\n".join([h] + t) for h, t in out)
