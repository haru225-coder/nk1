#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""仓务清册判档段「段级结构完整性」静态扫（lane w77-k5 立即升 must · w76-k6 复核牒 v1 承接执行 · 闸体 v1）。

判域 = 清册判档段「段级结构完整性」五格（与 check_ledger_garbage 词级污染轨互补不重叠——
彼闸罩「某行带回词级指纹」、本闸罩「某段被灭 / 换 / 插 / 乱序而词级零污染」）：
  甲·判档段行数下限 SEG_MIN=6（现帧统计 min=6 定基——删段头并入前段 / 截段即破）；
  甲′·判档段数恒等钉 SEG_COUNT_BASE（w77-k5 动手帧重钉 = 72——灭段 / 并段 / 换段即红；
      恒等式轨同 check_ledger_garbage R2，尾 append 新增段须同笔拨钉 §五.3「拨参数 = 拨颁」）；
  乙·§1..§5 行首段键（`- **§k` 口径）「首轮非严格递增」——段内首次出现的 § 键序列不许
      回退（多小节重复段键设计内照挂：w70-k3×2 / w70-k2×3 在卷——w76-k6 牒格乙口径拨正、
      执行片勿回退字面口径）；
  丙·段名唯一（归一化 w<N>-k<M> 名 + 段头整行双轨；历史三对重段 w58-k2×2 / w66-k3×2 /
      w71-k1×2 已核设计内放行——w74-k1 §8② 已裁在卷）；
  丁·纯尾 append 单调（文档层——首个判档段头之后不许再出非判档 H2；主控红清拨正
      不触发：不动段结构、唯改字 / 挪段在判档段域内——w76-k6 牒格丁口径照实注）。

立案链：判力空白三波亲证在卷——w74-k1 M-B1 删段烧照绿首烧 + w75-k1 M-A1 复证 +
w76-k6 第三证（量具树删 w75-k1 判档段头 → ledger rc=0 + decision_refs rc=0 双照绿）；
337b402 清册解析未声明灭 k6+k1 段换 k4+k2 段真案（w74-k1 遗留①）= 段级完整性缺口
实发致「没做实」呈主控。升格判掂毕（§五.2 原条文逐条对，w76-k6 复核牒 v1）：
判掂 1「自己判不准」成立——内容级结构非路径 trigger、append 的 lane 判不出哪一笔
灭段 / 换段 / 中段插入；判掂 2「快」成立——纯文扫原型三跑 24-26 ms ≪1 s；判掂 3「只读」
成立——零写盘开关、唯读清册一档（grep FileAccess/DirAccess/user:// 零命中）；
判掂 4「幂等绿」成立——原型对现帧清册 rc=0 ×3（段数钉 = 现帧段数口径、随判档段落地
同笔拨颁 §五.3）。

环境变量：NK1_LEDGER（同 check_ledger_garbage 钩例——自检 / 量具树变异 / 无文件形
另指本，生产零动）。

python 档免 .uid 侧车（house rule 唯 .gd 要侧车，照实注）。
"""
import os
import re
import sys
from collections import Counter


def _repo_root():
    real_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    return os.path.abspath(real_root)


ROOT = _repo_root()
LEDGER = os.environ.get("NK1_LEDGER") or os.path.join(ROOT, "docs", "仓务清册_2026-10-03.md")

SEG_MIN = 6            # 甲：判档段行数下限（w76-k6 现帧统计 min=6 定基）
SEG_COUNT_BASE = 86    # 甲′：判档段数恒等钉（w81-k2 殓权池判段落动手帧重钉 = 85 段 → w90-k3 --list 判段落拨 86——
                       # 闸体自口径 84（全 H2 93 − 非判档 H2 9 现算吻合；w81-k4 殓段落地拨 82 + w81-k6 scoop 殓段拨 83 起 + w81-k5 判档段尾 append 1 段累进）；
                       # 灭段 / 并段 / 换段即红；恒等式轨同 check_ledger_garbage R2，
                       # 尾 append 新增判档段须同笔拨钉 §五.3「拨参数 = 拨颁」同例）
KEY_RE = re.compile(r"^-\s*\*\*§([1-9])")
NAME_RE = re.compile(r"^## (?:殓权池判档段 · )?(?:w(?:ave)?(\d+)-k(\d+))")

FAILS = []


def check(cond, msg):
    print(("   ✓ " if cond else "   ✗ ") + msg)
    if not cond:
        FAILS.append(msg)
    return cond


def segs_of(lines):
    h2 = [i for i, l in enumerate(lines) if l.startswith("## ")]
    heads = [(i, l) for i, l in enumerate(lines) if l.startswith("## ") and "判档" in l]
    out = []
    for i, l in heads:
        nxt = min([j for j in h2 if j > i] + [len(lines)])
        out.append((i, nxt, l))
    return out, h2


def scan_text(text):
    """同一条判路：自检样本与真文档都走它——返问题行列表（每项带样本 tag / 行号点名）。"""
    lines = text.splitlines()
    probs = []
    segs, h2 = segs_of(lines)

    # 甲：行数下限（删段头并入前段属「段数减一」形、由甲′恒等钉咬；截段短段由本格咬）
    short = [(i + 1, n - i) for i, n, _ in segs if n - i < SEG_MIN]
    if short:
        probs.append(f"甲 判档段行数下限 {SEG_MIN}：违例段 {short[:3]}（截段 / 删段头并入形）")

    # 甲′：段数恒等钉（灭段 / 并段 / 换段即红；尾 append 新增段须同笔拨钉 §五.3）
    if len(segs) != SEG_COUNT_BASE:
        probs.append(f"甲′ 判档段数 {len(segs)} ≠ 恒等钉 {SEG_COUNT_BASE}"
                     "（灭段 / 并段 / 换段即红；尾 append 新增段须同笔拨钉 §五.3）")

    # 乙：§1..§5 行首段键「首轮非严格递增」——段内首次出现的 § 键序列不许回退
    #（多小节重复段键设计内照挂：w70-k3×2 / w70-k2×3 在卷；同段行内引用后续节归口径照挂）。
    bad_order = []
    for i, n, l in segs:
        keys = [int(m.group(1)) for bl in lines[i:n] if (m := KEY_RE.match(bl))]
        first_round = []
        for k in keys:
            if k not in first_round:
                first_round.append(k)
        if first_round != sorted(first_round):
            bad_order.append((i + 1, keys))
    if bad_order:
        probs.append(f"乙 §1..§5 行首段键首轮非严格递增（多小节重复照挂）：违例 {bad_order[:3]}")

    # 丙：段名唯一（归一化 w<N>-k<M> 名 + 段头整行双轨；历史三对重段已核设计内放行）
    HIST_DUP_OK = {("w58-k2", 2), ("w66-k3", 2), ("w71-k1", 2)}  # w74-k1 §8② 已裁在卷
    cnt = Counter()
    for i, n, l in segs:
        m = NAME_RE.match(l)
        nm = ("w%s-k%s" % (m.group(1), m.group(2))) if m else l[:30]
        cnt[nm] += 1
    new_dups = {k: c for k, c in cnt.items() if c > 1 and (k, c) not in HIST_DUP_OK}
    if new_dups:
        probs.append(f"丙 段名唯一（历史已裁 3 对放行）：新增重复 {new_dups}")

    # 丁：纯尾 append 单调性——判档段唯许最末 H2 块域（首个判档段头之后不许再出非判档 H2）
    first_seg = segs[0][0] if segs else len(lines)
    tail_h2 = [i for i in h2 if i > first_seg and "判档" not in lines[i]]
    if tail_h2:
        probs.append(f"丁 纯尾 append 单调（判档段域起于 :{first_seg + 1}）："
                     f"其后混入非判档 H2 行 {[i + 1 for i in tail_h2][:5]}")
    return probs


# ── 自检样本（§五.3 规则表型内置：与真文档同一条 scan_text 判路，不落盘）──
# 段壳各行均以「- 」行首起字（不撞 KEY_RE 段键），行数 / §键 / 段名各格按需调。
def _seg(head, body_keys, pad=3):
    rows = [head]
    for k in body_keys:
        rows.append(f"- **§{k} 节**照挂样文")
    rows += ["- 照挂样文补行"] * pad
    return rows


def _base_doc(nsegs, prefix_pad=30):
    """正形底盘：prefix_pad 行非 H2 前言 + nsegs 个五键正序段（段名唯一、行数达标）。"""
    lines = ["- 前言照挂样文"] * prefix_pad
    lines += ["## 卷首目录（非殓档 H2——段域之前照挂）", "- 目录行"]
    for n in range(1, nsegs + 1):
        lines += _seg(f"## w80-k{n} 判档段 自检底盘样", [1, 2, 3, 4, 5], pad=2)
    return "\n".join(lines)


def _self_test():
    """零、样本自检（§五.3 规则表型必跑道内置样本，每次先跑——与真文档同一条 scan_text 判路）。

    S 格（负样——判红是期望，检出即 ✓；检不出 = 闸判不出该形、闸自身坏先红）：
      S1 整段灭段（甲′咬）；S2 §键乱序（乙咬）；S3 新增重复段名（丙咬）；
      S4 中段插入非判档 H2（丁咬）；S5 短段截段（甲咬）；S6 段数钉不拨回拨 -1（甲′咬——
        拨颁必要性反向格，w76-k6 遗留②钦）。
    C 格（干净样——须全绿；误红面闸——w76-k6 牒格乙 / 格丁口径拨正实钉，勿回退）：
      C1 多小节重复段键照挂判绿（w70-k3×2 / w70-k2×3 同型：键序列 [1,2,3,4,5,1,2] 首轮
        非严格递增照守）；C2 主控红清拨正不触发判绿（段体改字 + 判档段域内段序挪换——
        段数 / 段名 / §键 / 丁格全不动）；C3 历史三对重段放行判绿（w58-k2×2 / w66-k3×2 /
        w71-k1×2 恰 2 次钉集形）；C4 段头整行双轨兜底判绿（无 wN-kM 名的判档段头按
        段头整行前 30 字取名、唯一即绿）；C5 正形底盘全绿（甲 / 甲′ / 乙 / 丙 / 丁五格照守）。
    """
    print("零、样本自检（§五.3 规则表型内置样本，与本闸 scan_text 同一条判路）")
    ok = True
    ok &= check(SEG_COUNT_BASE >= 2, f"段数钉 {SEG_COUNT_BASE} ≥ 2（自检构造可行性兜底）")

    # C5 正形底盘（先立——S 格都在它底盘上烧）
    base = _base_doc(SEG_COUNT_BASE)
    ok &= check(scan_text(base) == [], "C5 正形底盘五格照守判绿（误红面兜底）")

    # S1 整段灭段：底盘删一完整段（段头 + 段体 8 行 = w74-k1 遗留①灭段同型）→ 唯甲′咬
    lines = base.splitlines()
    body_start = lines.index("## w80-k1 判档段 自检底盘样")
    lines2 = lines[:body_start] + lines[body_start + 8:]
    p = scan_text("\n".join(lines2))
    ok &= check(p and all(p.startswith("甲′") for p in p), "S1 整段灭段唯甲′咬（段数钉点名）")

    # S2 §键乱序：末段 §2/§3 行交换（首轮 [1,3,2,4,5] 回退即红）
    lines3 = base.splitlines()
    k2 = next(i for i in range(len(lines3) - 1, -1, -1) if lines3[i].startswith("- **§2"))
    k3 = next(i for i in range(len(lines3) - 1, -1, -1) if lines3[i].startswith("- **§3"))
    lines3[k2], lines3[k3] = lines3[k3], lines3[k2]
    p = scan_text("\n".join(lines3))
    ok &= check(p and all(p.startswith("乙 ") for p in p), "S2 §键乱序唯乙咬（首轮回退点名）")

    # S3 新增重复段名：底盘灭一既有段（w80-k2）、原位换入一段与 w80-k1 同名（灭段换段
    # 同名顶替形）——段数恒 = 钉、唯丙咬（段名格独立咬形实钉）
    lines4 = base.splitlines()
    head2 = next(i for i, l in enumerate(lines4) if l.startswith("## w80-k2 "))
    lines4 = (lines4[:head2]
              + _seg("## w80-k1 判档段 自检底盘样", [1, 2, 3, 4, 5], pad=2)
              + lines4[head2 + 8:])
    p = scan_text("\n".join(lines4))
    ok &= check(p and all(p.startswith("丙 ") for p in p), "S3 新增重复段名唯丙咬（灭段换段顶替形段数钉照挂）")

    # S4 中段插入非判档 H2：判档段域内插一节非判档 H2（丁咬）——插节带 § 键行 +
    # 补齐行数 ≥SEG_MIN，构造满甲格，唯丁咬
    lines5 = base.splitlines()
    ins = next(i for i, l in enumerate(lines5) if l.startswith("## w80-k2 "))
    ins_seg = ["## 插进来的闲章节"] + [f"- **§{k} 节**照挂样文" for k in [1, 2]] + ["- 照挂样文补行"] * 4
    lines5 = lines5[:ins] + ins_seg + lines5[ins:]
    p = scan_text("\n".join(lines5))
    ok &= check(p and all(p.startswith("丁 ") for p in p), "S4 中段插入非判档 H2 唯丁咬（行号点名）")

    # S5 短段截段：末段体砍到 <SEG_MIN 行（甲咬；段数不变、甲′不咬——两格分工实钉）
    lines6 = base.splitlines()
    last_head = max(i for i, l in enumerate(lines6) if l.startswith("## w80-k"))
    lines6 = lines6[:last_head + 1] + ["- **§1 节**照挂样文"]
    p = scan_text("\n".join(lines6))
    ok &= check(p and all(p.startswith("甲 ") for p in p),
                "S5 短段截段唯甲咬（甲′不咬——行数格 / 段数格分工实钉）")

    # S6 段数钉不拨反向格：底盘多 append 一段（段名新、五格余皆正）→ 唯甲′咬
    # = 「钉不拨则新增段照红」拨颁必要性实证（w76-k6 遗留②钦）。
    lines7 = base.splitlines() + _seg("## w80-k99 判档段 自检新增样", [1, 2, 3, 4, 5], pad=2)
    p = scan_text("\n".join(lines7))
    ok &= check(p and all(p.startswith("甲′") for p in p),
                "S6 钉不拨则新增段照红（唯甲′咬——拨颁必要性反向格）")

    # C1 多小节重复段键照挂（w70-k3×2 / w70-k2×3 同型——格乙口径拨正实钉、勿回退）
    lines8 = base.splitlines()
    last_head = max(i for i, l in enumerate(lines8) if l.startswith("## w80-k"))
    lines8 = lines8[:last_head + 1] + [f"- **§{k} 节**照挂样文" for k in [1, 2, 3, 4, 5, 1, 2]] + ["- 补行"] * 2 + lines8[last_head + 1:]
    p = scan_text("\n".join(lines8))
    ok &= check(p == [], "C1 多小节重复段键照挂判绿（乙不咬——误红面闸实钉）")

    # C2 主控红清拨正不触发：段体改字 + 判档段域内段序挪换（段结构五格全不动）
    lines9 = base.splitlines()
    heads_idx = [i for i, l in enumerate(lines9) if l.startswith("## w80-k")]
    a, b = heads_idx[0], heads_idx[1]
    seg_a, seg_b = lines9[a:a + 8], lines9[b:b + 8]
    lines9 = lines9[:a] + seg_b + seg_a + lines9[b + 8:]
    lines9 = [l.replace("照挂样文", "红清拨正改字样") if l.startswith("- 照挂样文") else l for l in lines9]
    p = scan_text("\n".join(lines9))
    ok &= check(p == [], "C2 主控红清拨正（改字 + 域内挪段）五格全不咬判绿")

    # C3 历史三对重段放行（w58-k2×2 / w66-k3×2 / w71-k1×2 恰 2 次钉集形——丙不咬）
    lines10 = _base_doc(SEG_COUNT_BASE - 6).splitlines()
    for nm in ["w58-k2", "w66-k3", "w71-k1"]:
        lines10 += _seg(f"## {nm} 判档段 历史重段放行样", [1, 2, 3, 4, 5], pad=2)
        lines10 += _seg(f"## {nm} 判档段 历史重段放行样（复述）", [1, 2, 3, 4, 5], pad=2)
    p = scan_text("\n".join(lines10))
    ok &= check(p == [], "C3 历史三对重段放行判绿（丙不咬——已裁钉集实钉）")

    # C4 段头整行双轨兜底（无 wN-kM 名的判档段头按段头整行前 30 字取名、唯一即绿）
    lines11 = _base_doc(SEG_COUNT_BASE - 1).splitlines()
    lines11 += _seg("## 殓权池判档段 · 无 wave 名特别件 自检样", [1, 2, 3, 4, 5], pad=2)
    p = scan_text("\n".join(lines11))
    ok &= check(p == [], "C4 无名段头整行双轨取名唯一判绿（丙兜底轨实钉）")
    return ok


def main():
    ok = _self_test()
    print("一、真文档扫描")
    try:
        with open(LEDGER, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        print(f"   ✗ 读不到 {LEDGER}（{e}）——防静默绿：无文件形判红")
        print("结果：1 项问题")
        return 1
    for p in scan_text(text):
        check(False, p)
    if not FAILS:
        n_seg = len(segs_of(text.splitlines())[0])
        print(f"   ✓ 真文档五格照守（{n_seg} 段 = 恒等钉 {SEG_COUNT_BASE}、甲/乙/丙/丁 零违例）")
    print("结果：全部通过" if ok and not FAILS else f"结果：{len(FAILS)} 项问题")
    return 0 if ok and not FAILS else 1


if __name__ == "__main__":
    sys.exit(main())
