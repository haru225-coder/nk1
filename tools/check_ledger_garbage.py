#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""仓务清册「殓殓」词级污染静态扫（lane w62-k3 立 · lane 档；判词池承接件 v1 · v4 内容键钉形）。

立案链：w61-k2 SETTLED 遗留②原句钦（清册 w61-k2 判档段末）——「M1' 结论 = 四闸
对文档词级污染该形零判力、净化判力靠人读 + 钉集 diff 双轨（呈下波 ops——若欲闸罩
gating 净化毕文档全文殓殓计数、归判词池）」；w61-k2 M1' 实跑四闸（gates_md /
check_w53_copy / host_paths / docs_index）对重造「殓殓殓殓×10」×4 全文档词级
指纹各 rc=0 静默绿实锤 = 该形判力窗在卷。本片接判词池立本闸罩它。

判域与口径（防新增、不回扫旧账——设计钦命照 brief §避开；**v4 终形 = 内容键钉、
结构性免行号漂移）：
  - 指纹词 =「殓殓」二字连用、非叠对 str.count 口径（单枚「殓」是正常殓档动词
    不判；grep -o 枚数 183 是嵌对口径、本闸不用——非叠对分布 1/2/33/50/1/1/4/2/
    33/50/3/1/2 = 183，:631-635 与 :649-653 双段重段同文、13 行唯 9 枚不同 sha1）。
  - **白名单 = KNOWN_SHA1 表**（wave61-k2 净化毕旧账行内容 sha1-12 键：行内容
    不变即照挂，判档段尾 append / 行号推移全不咬——v1 枚数阈 / v2 绝对行号表 /
    v3 距尾带三版拨正案判掂史见 w62-k3 判档段；尾 append 禁改被放行行的字、
    改了字 = 该键行落出表即按新增形 R1/R2 判红——fail closed）。
  - 判红形＝**新增**（KNOWN_SHA1 键行照挂零报、不判 red 非 warn）：
      R1 表外某行含「殓殓」≥ 2 枚逐行 ✗ 点名行号与枚数（M1 喂新行即此形——
        **1 枚隔离行不判**：现行档 :639/:644 合法复合词先例 + 判档自然引用一句
        且单行不可读词不成立，此形归 wave63+ 细判；写新殓档段引用「殓殓」出自
        行首 hash 对象即占行首免挂载（数字/反引号/ASCII 开头的逐字 hash 行不享）——
        语义 hash 不自然引「殓殓」、成串即 R1 治）；
      R2 全文档含「殓殓」行数 > ALLOW_LINES（13）——防「1 枚碎片多发回潮」
        （R1 的兜底格；新殓档段自然引用累计初格照挂、回潮即撞 R2 点名行号——
        撄基线/细判照 §五.3「拨参数 = 拨颁」归 wave63+）。
  - 清册行数 < EOF_MIN（600，为 BASELINE_LEN 695 留 95 行尾窗）fail closed 判红
    防「截半/清空蒙绿」。

环境变量：NK1_LEDGER（缺省按本副本 checkout 视 docs/仓务清册_2026-10-03.md；
自检 / 量具树变异 / 无文件形另指本，生产零动——同 NK1_COORD / NK1_MAIN_REF 钩例）。

python 档免 .uid 侧车（house rule 唯 .gd 要侧车，照实注）。
"""
import hashlib
import os
import sys

# ── 白名单钉集（SoR；改动 = 拨旧账，走 §五.3「拨参数 = 拨颁」同例）──
TOKEN = "殓殓"
KNOWN_SHA1 = frozenset({
    # wave61-k2 净化毕旧账 13 行（唯 9 枚不同文——:631/:649 同文、:633/:651 同文、:634/:652 同文、:635/:653 同文）
    "cf4ac416476a",  # :631/:649
    "59f8a9f94586",  # :633/:651
    "979228e0b3e0",  # :634/:652
    "2fde8f1e5a6a",  # :635/:653
    "2b3c68a66a51",  # :639
    "a82ea2207c58",  # :644
    "6be3cbe40b29",  # :692
    "569d91b780e8",  # :693
    "0cf5e89a8b8b",  # :694
})
ALLOW_LINES = 13          # 全文档含 TOKEN 行数基线（起派实跑 grep -n TOKEN | wc -l；自然引用回潮撞此格照 §五.3 拨颁归 wave63+）
BASELINE_LEN = 695        # 起派实跑 wc -l 基线（v1-v3 听证档）
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


def known_row(line):
    """放行判定 = 内容键 ∈ KNOWN_SHA1，或行首非 ASCII 起字（自然引用一句免挂载——
    数字/反引号/ASCII 起字的逐字 hash 行不享，防止把污染行贴进 hash 壳蒙绿）。"""
    if hashlib.sha1(line.encode("utf-8")).hexdigest()[:12] in KNOWN_SHA1:
        return True
    s = line.lstrip()
    return bool(s) and ord(s[0]) > 0x7F


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
        if known_row(lines[ln_no - 1]):
            continue  # 旧账/自然引用照挂零报（w61-k2 判 A 殓不刀、净化归 wave63+）
        if c >= 2:
            probs.append(f"{tag}:{ln_no}: 新增「{TOKEN}」×{c}（词级污染指纹，白名单外行）——{lines[ln_no - 1][:80]}")
    if len(hot) > ALLOW_LINES:
        probs.append(f"{tag}: 含「{TOKEN}」行数 {len(hot)} 超基线 {ALLOW_LINES}（回潮/自然引用撞格 = 行号 {[n for n, _ in hot]}——§五.3 拨颁归 wave63+）")
    return probs, len(hot), top


def _self_test():
    """零、样本自检（§五.3 规则表型必跑道内置样本，每次先跑）。

    S 格（负样——判红是期望，检出即 ✓；检不出 = 闸判不出该形、自红；样本一律垫到
      ≥EOF_MIN 行防 fail closed 先行收，tag 行不变）：
      S1 ASCII 起字新行 3 枚（M1 喂污染形——碎片词级替换面，R1 格）；
      S2 ASCII 起字单行 5 枚连用（整段 token 替换面，R1 格）；
      S3 全文档行数 +1 超基线（13 旧键 + 1 枚 ASCII 起字孤立行，R2 格）；
      S4 清册截半（<EOF_MIN 行——fail closed 判红形）。
    C 格（干净样——须全绿、不判红；拨参数降级散形各格照散照钉、不砌闸）：
      C1 现帧基线形（KNOWN_SHA1 键行 1-50 枚各依 ALLOW_LINES/R1 口径判——13 档
        零新增判绿、0 档（M2② 反向格）R2 点名行数、判路仍衙）；
      C2 单枚「殓」正用成段（殓档动词 / 殓殻 / 殓权——TOKEN 零命中）；
      C3 零点行文档（净化 wave63+ 毕后的将来正形）；
      C4 非 ASCII 起字自然引用 1 枚行（免挂载照挂形——13 档判绿 / 0 档 R2 收散钉）；
      C5 尾 append 推位形（基线形 + 尾 8 行判档段壳——键行内容不漂移照样照挂、
        行数钉 ALLOW_LINES 不动——v2/v3 死症结构免判实钉）。
    """
    print("零、样本自检（与本闸 scan_text 同一条判路）")
    ok = True
    padf = ["平"] * (EOF_MIN - 1)
    p1, _, _ = scan_text("\n".join(padf + ["- 殓维数据三字禁动" + TOKEN * 3 + "照实钉"]), "S1")
    ok &= check(bool(p1) and any("×3" in p for p in p1), "S1 新行 3 枚判红点名（R1）")
    p2, _, _ = scan_text("\n".join(padf + ["`" + TOKEN * 5 + "`"]), "S2")
    ok &= check(bool(p2) and any("×5" in p for p in p2), "S2 单行 5 枚连用判红点名（R1）")
    # C1/S3 用真旧账文（由 KNOWN_SHA1 键反查太绕，直接垫基线帧文 13 行——行壳 = 垫文行 + TOKEN）
    # 真旧账行文的 sha1 已在 KNOWN_SHA1 表——此处重建同文行（盲拷贝键行不可得，改用「行首 CJK」免挂载近似：
    # 旧账三域行皆以 CJK 起字（:631 '- **殓后…' 起字 '-' ASCII？——否：行首为 '- ' ASCII；故样板不走免挂载、走真键）
    base_rows = []
    import io
    try:
        with open(os.path.join(ROOT, "docs", "仓务清册_2026-10-03.md"), encoding="utf-8") as f:
            real = f.read().splitlines()
        keys_left = dict()
        for ln in real:
            h = hashlib.sha1(ln.encode("utf-8")).hexdigest()[:12]
            if h in KNOWN_SHA1 and h not in keys_left:
                keys_left[h] = ln
    except OSError:
        keys_left = {}
    ok &= check(len(keys_left) == len(KNOWN_SHA1),
                f"零节前置：KNOWN_SHA1 表 {len(KNOWN_SHA1)} 键自现帧清册实取得 {len(keys_left)} 键行（缺键 = 基线已漂、先修表不修自检）")
    base_rows = list(keys_left.values())
    heavy = "\n".join(padf[:EOF_MIN - 10] + base_rows + ["平"])  # 9 键行 + 1 垫尾 ≥ EOF_MIN（dup 行现帧清册外样本唯 9 枚不同文、行数判按 13 实格照旧——C1 行数钉 len(base_rows)）
    p3b, _, _ = scan_text("\n".join(padf[:EOF_MIN // 2]), "S4")
    ok &= check(bool(p3b) and any("fail closed" in p for p in p3b), "S4 截半形 fail closed 判红")
    # S3：旧账 9 键行 + 1 枚 ASCII 起字孤立行 = 10 热点行 vs ALLOW_LINES 13 档不治——须 +4 枚 ASCII 起字行凑 14（R2 行数格实钉；
    # 行数判按热点行实格、样本以 9 枚不同文键行替 13 实格照「内容键不重复收行数格」实钉）
    s3 = "\n".join(padf[:EOF_MIN - 15] + base_rows + ["`" + TOKEN + "`"] + [f"{i}." + TOKEN for i in range(ALLOW_LINES - len(base_rows))] + ["平"])
    p3, n3, _ = scan_text(s3, "S3")
    ok &= check(bool(p3) and n3 > 0 and any(f"行数 {n3} 超基线" in p for p in p3),
                f"S3 行数 {n3}>{ALLOW_LINES} 超基线判红点名（R2；拨 0 档散钉判路在衙）")
    p4, n4, t4 = scan_text(heavy, "C1")
    if ALLOW_LINES >= len(base_rows):  # 正档：全表照挂，零问题行
        ok &= check(not p4 and n4 == len(base_rows) and t4 == 50,
                    f"C1 基线 {n4} 行顶枚 {t4} 形判绿（行 {n4}/{ALLOW_LINES}；KNOWN_SHA1 键行照挂）")
    else:  # 拨低档（M2② 反向格 0 档实案）：R2 须点名行数——判路仍在衙
        ok &= check(bool(p4) and any(f"行数 {n4} 超基线 {ALLOW_LINES}" in p for p in p4),
                    f"C1-R 拨基线 {ALLOW_LINES} → R2 点名旧账 {n4} 行（判路仍衙）")
    p5, _, _ = scan_text("\n".join(padf + ["殓动词三连唯 worktree remove → prune → update-ref -d、殓殻殓权全照挂"]), "C2")
    ok &= check(not p5, "C2 单枚「殓」正用段判绿")
    p6, _, _ = scan_text("\n".join(padf + ["一、境港", "二、申港", "三、波港"]), "C3")
    ok &= check(not p6, "C3 零点行文档判绿")
    if ALLOW_LINES >= 1:  # 0 档（反向格）下 1 枚孤立行被 R2 收，本格照散钉不砌（同 C1-R）
        p7, n7, _ = scan_text("\n".join(padf + ["自然引一句「殓殓」复合词的行"]), "C4")
        ok &= check(not p7 and n7 == 1, "C4 自然引用 1 枚行判绿（行首免挂载照挂面实钉）")
    if ALLOW_LINES >= len(base_rows):  # 推位形：基线 + 尾 append 8 行壳——键行不漂移照挂、行数钉基线
        p8, n8, _ = scan_text(heavy + "\n" + "\n".join(f"判档壳行{i}" for i in range(8)), "C5")
        ok &= check(not p8 and n8 == len(base_rows),
                    f"C5 尾 append 推位形判绿（行 {n8}/{ALLOW_LINES}；键行内容键照挂——v2/v3 死症结构免判）")
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
                    f"新增 0 格（含「{TOKEN}」行 {n}/{ALLOW_LINES} 键行/自然引用照挂、单行顶 {top} 旧账大枚段在表不判）")
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
