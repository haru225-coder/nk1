#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""仓务清册「殓殓」词级污染静态扫（lane w62-k3 立 · lane 档；判词池承接件 v1）。

立案链：w61-k2 SETTLED 遗留②原句钦（清册 w61-k2 判档段末）——「M1' 结论 = 四闸
对文档词级污染该形零判力、净化判力靠人读 + 钉集 diff 双轨（呈下波 ops——若欲闸罩
gating 净化毕文档全文殓殓计数、归判词池）」；w61-k2 M1' 实跑四闸（gates_md /
check_w53_copy / host_paths / docs_index）对重造的「殓殓殓殓×10」×4 全文档词级
指纹各 rc=0 静默绿实锤 = 该形判力窗在卷。本片接判词池立本闸罩它。

判域与口径（防新增、不回扫旧账——设计钦命照 brief §避开）：
  - 指纹词 =「殓殓」二字连用（单枚「殓」是正常殓档动词，不判）。
  - 现帧残存基线（wave61-k2 净化毕帧 = KNOWN 表 13 行，起派实贴；**grep -o 枚数
    183 是嵌对口径、本闸全用 str.count 非叠对口径**）分布 :631/:633/:634/:635
    /:649/:651/:652/:653（§四 wave58-k2 判档段双域——整段 token 替换域，
    「殓殓」非叠对枚数 1/2/33/50/4/2/33/50 = 183 嵌对对半口径，w61-k2 已判 A
    殓不刀照挂、净化归 wave63+）＋ :639/:644（§四 wave59-k1 段句内合法复合词
    照挂）＋ :692/:693/:694（w61-{1,2,3} 判档段原文逐字引用行，合法引用照挂）——
    **三域全白名单照挂**。**行号漂移口径（w62-k3 v3 补）**：判档段尾 append 会把
    引用行往下推——KNOWN 判法 = 绝对行号 ∈ KNOWN_ABS，**或**行号 ∈ 距档尾
    KNOWN_FROM_END（4/3/2，即末 4 行引用带）；清册行数 < EOF_MIN（600，为
    BASELINE_LEN 695 留 95 行尾窗）即 fail closed 判红防「清空蒙绿」。
  - 判红形＝**新增**（KNOWN 表行照挂零报、不判 red 非 warn）：
      R1 KNOWN 表外某行含「殓殓」≥ 2 枚（M1 喂 3 枚新行即此形——**1 枚隔离行
        不判**：现行档 :639/:644 合法复合词先例 + 上屏判档自然引用一句且单行
        不可读词不成立，此形归 wave63+ 细判）；
      R2 全文档含「殓殓」行数 > ALLOW_LINES（13）——防「1 枚碎片多发回潮」
        （R1 的兜底格；M2② 反向格把 ALLOW_LINES 拨 0 即此形点名旧账）。
  - 绿＝「≤ 基线」逐格（现帧 n=13/top=50 即「净化毕 + 旧账全在表内」正形）。

环境变量：NK1_LEDGER（缺省按本副本 checkout 视 docs/仓务清册_2026-10-03.md；
自检 / 量具树变异 / 无文件形另指本，生产零动——同 NK1_COORD / NK1_MAIN_REF 钩例）。

python 档免 .uid 侧车（house rule 唯 .gd 要侧车，照实注）。
"""
import os, re, sys

# ── 白名单钉集（SoR；改动 = 拨旧账，走 §五.3「拨参数 = 拨颁」同例）──
TOKEN = "殓殓"
KNOWN_ABS = frozenset((631, 633, 634, 635, 639, 644, 649, 651, 652, 653, 692, 693, 694))
KNOWN_FROM_END = frozenset((4, 3, 2))  # 引用带 = 距档尾 4/3/2 行（尾 append 推位下照样照挂）
ALLOW_LINES = 13          # 全文档含 TOKEN 行数基线（起派实跑 grep -n TOKEN | wc -l）
BASELINE_LEN = 695        # 起派实跑 wc -l 基线（v3 听证档）
EOF_MIN = 600             # 清册行数下限（尾窗 95 行供本片及其后判档段 append；低于 = 截半/清空形 fail closed）

FAILS = []


def _repo_root():
    real_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    return os.path.abspath(real_root)


ROOT = _repo_root()
LEDGER = os.environ.get("NK1_LEDGER") or os.path.join(ROOT, "docs", "仓务清册_2026-10-03.md")


def check(cond, msg):
    """与 check_mac_paths 同形：cond 真印 ✓、假印 ✗ 并收 FAILS。"""
    if cond:
        print("   ✓ " + msg)
    else:
        FAILS.append(msg)
        print("   ✗ " + msg)
    return cond


def known_at(ln_no, n_lines):
    """行号 ∈ KNOWN 判定（绝对表 ∪ 距尾引用带）——尾 append 推位下引用行照样照挂。"""
    return ln_no in KNOWN_ABS or (n_lines - ln_no + 1) in KNOWN_FROM_END


def scan_text(text, tag):
    """同一条判路：自检样本与真文档都走它——返 (问题行列表, 含 TOKEN 行数, 单行顶枚数)。"""
    probs = []
    lines = text.splitlines()
    n_lines = len(lines)
    if n_lines < EOF_MIN:
        return [f"{tag}: 清册实得 {n_lines} 行 < 下限 {EOF_MIN}（截半/清空形，fail closed 防蒙绿）"], 0, 0
    hot = [(i + 1, ln.count(TOKEN)) for i, ln in enumerate(lines) if TOKEN in ln]
    top = max((c for _, c in hot), default=0)
    for ln_no, c in hot:
        if known_at(ln_no, n_lines):
            continue  # 旧账白名单照挂零报（w61-k2 判 A 殓不刀、净化归 wave63+）
        if c >= 2:
            probs.append(f"{tag}:{ln_no}: 新增「{TOKEN}」×{c}（词级污染指纹，白名单外行）——{lines[ln_no - 1][:80]}")
    if len(hot) > ALLOW_LINES:
        probs.append(f"{tag}: 含「{TOKEN}」行数 {len(hot)} 超基线 {ALLOW_LINES}（新增 = 行号 {[n for n, _ in hot if not known_at(n, n_lines)]}）")
    return probs, len(hot), top


def _self_test():
    """零、样本自检（§五.3 规则表型必跑道内置样本，每次先跑）。

    S 格（负样——判红是期望，检出即 ✓；检不出 = 闸判不出该形、自红；样本一律垫到
      ≥EOF_MIN 行防 fail closed 先行收，tag 行不变；S4 截半形另列）：
      S1 新行 3 枚（M1 喂污染形——碎片词级替换面，R1 格）；
      S2 单行 5 枚连用（整段 token 替换面，R1 格）；
      S3 全文档第 14 热点行 1 枚（行数 +1 超基线，R2 格）；
      S4 清册截半（<EOF_MIN 行——fail closed 判红形）。
    C 格（干净样——须全绿、不判红；拨参数降级散形各格照散照钉、不砌闸）：
      C1 现帧基线形（KNOWN 表行 1-50 枚各依 ALLOW_LINES/R1 口径判——13 档零新增判绿、
        0 档（M2② 反向格）R2 点名旧账、判路仍衙）；
      C2 单枚「殓」正用成段（殓档动词 / 殓殻 / 殓权——TOKEN 零命中）；
      C3 零点行文档（净化 wave63+ 毕后的将来正形）；
      C4 白名单外行 1 枚（判档自然引用一句形、R1 不治——13 档判绿 / 0 档 R2 收
        散钉判路在衙）；
      C5 尾 append 推位形（基线形 + 尾 8 行判档段壳——引用行漂出绝对表、凭
        KNOWN_FROM_END 距尾带照挂判绿，行数钉 ALLOW_LINES 不动）。
    """
    print("零、样本自检（与本闸 scan_text 同一条判路）")
    ok = True
    padf = ["平"] * (EOF_MIN - 1)
    p1, _, _ = scan_text("\n".join(padf + ["殓维数据三字禁动" + TOKEN * 3 + "照实钉"]), "S1")
    ok &= check(bool(p1) and any("×3" in p for p in p1), "S1 新行 3 枚判红点名（R1）")
    p2, _, _ = scan_text("\n".join(padf + [TOKEN * 5]), "S2")
    ok &= check(bool(p2) and any("×5" in p for p in p2), "S2 单行 5 枚连用判红点名（R1）")
    pad = lambda d: ["平"] * (min(d) - 1) + [d.get(i, "平") for i in range(min(d), max(d) + 1)]
    heavy_d = {l: (TOKEN * 50 if l in (635, 653) else TOKEN * 3) for l in sorted(KNOWN_ABS)}
    heavy = "\n".join(pad(heavy_d))
    p3b, _, _ = scan_text("\n".join(["平"] * (EOF_MIN // 2)), "S4")
    ok &= check(bool(p3b) and any("fail closed" in p for p in p3b), "S4 截半形 fail closed 判红")
    # S3：恰好 ALLOW_LINES+1 行含 TOKEN（13 档 = KNOWN 13 行 + 1 枚孤立新行 14——R1 ≥2 不治、唯 R2 行数 +1 形）；
    # 绝对表引用行（:692-694）落 heavy 引用带内 = 距尾 KNOWN_FROM_END 带同位（基线长 695 口径钉）
    s3d = dict(heavy_d)
    s3d[max(KNOWN_ABS) + 4] = TOKEN  # 白名单外 +1 行且 1 枚（R1 不治）——13 档 n=14 / 0 档 n=1，各恰 ALLOW_LINES+1
    n3 = len(s3d)
    p3, _, _ = scan_text("\n".join(pad(s3d)), "S3")
    ok &= check(bool(p3) and n3 > 0 and any(f"行数 {n3} 超基线" in p for p in p3),
                f"S3 行数 {n3}>{ALLOW_LINES} 超基线判红点名（R2；拨 0 档散钉判路在衙）")
    p4, n4, t4 = scan_text(heavy, "C1")
    if ALLOW_LINES >= len(KNOWN_ABS):  # 正档：全表照挂，零问题行
        ok &= check(not p4 and n4 == ALLOW_LINES and t4 == 50,
                    f"C1 基线 {n4} 行顶枚 {t4} 形判绿（行 {n4}/{ALLOW_LINES}；KNOWN 绝对表照挂）")
    else:  # 拨低档（M2② 反向格 0 档实案）：R2 须点名旧账——判路仍在衙
        ok &= check(bool(p4) and any(f"行数 {n4} 超基线 {ALLOW_LINES}" in p for p in p4),
                    f"C1-R 拨基线 {ALLOW_LINES} → R2 点名旧账 {n4} 行（判路仍衙）")
    p5, _, _ = scan_text("\n".join(padf + ["殓动词三连唯 worktree remove → prune → update-ref -d、殓殻殓权全照挂"]), "C2")
    ok &= check(not p5, "C2 单枚「殓」正用段判绿")
    p6, _, _ = scan_text("\n".join(padf + ["一、境港", "二、申港", "三、波港"]), "C3")
    ok &= check(not p6, "C3 零点行文档判绿")
    if ALLOW_LINES >= 1:  # 0 档（反向格）下 1 枚孤立行被 R2 收，本格照散钉不砌（同 C1-R）
        p7, n7, _ = scan_text("\n".join(padf + ["自然引一句「殓殓」复合词的行"]), "C4")
        ok &= check(not p7 and n7 == 1, "C4 白名单外行 1 枚判绿（R1 ≥2 才治、照挂面实钉）")
    if ALLOW_LINES >= len(KNOWN_ABS):  # 推位形：基线 + 尾 append 8 行壳——漂出行凭距尾带照挂、行数钉基线
        p8, n8, _ = scan_text(heavy + "\n" + "\n".join(f"判档壳行{i}" for i in range(8)), "C5")
        ok &= check(not p8 and n8 == ALLOW_LINES,
                    f"C5 尾 append 推位形判绿（行 {n8}/{ALLOW_LINES}；引用行凭距尾带照挂）")
    return ok


def main():
    ok = _self_test()
    print("一、真文档扫描")
    try:
        with open(LEDGER, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        msg = f"读不到 {LEDGER}（{e.strerror or e}）——防静默绿：无文件形判红，修 NK1_LEDGER 或还原清册"
        FAILS.append(msg)
        print("   ✗ " + msg)
        ok = False
        text = None
    if text is not None:
        probs, n, top = scan_text(text, os.path.relpath(LEDGER, ROOT))
        ok &= check(not probs,
                    f"新增 0 格（含「{TOKEN}」行 {n}/{ALLOW_LINES} 全 = KNOWN 白名单照挂、单行顶 {top} 旧账大枚段在表不判）")
        for p in probs:
            FAILS.append(p)
            print("   ✗ " + p)
    if FAILS:
        print("结果：%d 项问题" % len(FAILS))
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
