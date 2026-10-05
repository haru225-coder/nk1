#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GATES §五.1 信念段＋gate_json 开局段守卫闸（lane w100-k3 立 · w99-k2 案丙敞口承接执行 · 闸体 v1）。

判域 = 两处「手抄信念段」（机器生成块之外、注册表镜子照不到的语义文字）的形状钉：

  区一 = `docs/GATES.md` 「### 五.1 入册：进注册表、定档」节（头行起到下一 `### ` 头止）：
    非空行数 / 顶层 bullet 行数 / 编号步骤行数（`  N. ` 起首）三数钉——删一行、添一步即红；
    关键词哨（什么算门禁 / 入册一次做齐 / 四档与 CI 名单 / 生成格口诀等），每词各钉在衙行数
    ——改一字关键词（「SUBCHECKS」→「SUBCHECK」）即该词行数格红。
  区二 = `tools/gate_json.py` 开局 docstring 段（首个三引号开串行起到闭串行止）：
    段行数 / 非空行数钉＋关键词哨（机读输出 / 门禁清单 / REGISTRY / SUBCHECKS / CI_STEPS），
    每词各钉在衙行数——删一句即行数格红。

量全自被守卫件现读、零手抄字面（w96-k6 钦钉形 / 群化轨）：拨项拨颁规矩照 §五.3——
挪段 / 改段须在本脚本 BELIEF_PINS 同笔随同色，五闸收尾绿。

w99-k2 审计牒案丙实锤在卷（<auto>/logs/w99-k2-audit-w93-k1k6-exec.md :39/:44）：
焐域 GATES.md 整档回退 main 纯 blob → gates_md rc=0【烧而不红】——§五.1 手写信念段
（生成格口诀登记链落区）现行无判面守卫闸，本闸即收编该敞口。

  python3 tools/check_gates_belief_section.py          # 自检 + 真档两区照扫；有问题退 1
  python3 tools/check_gates_belief_section.py --json   # 机读（同 docs/GATES.md §二）

零、判据自检每次先跑（§五.3 规则表型轨：内存样本扫同一 scan_text 判路）——
S1 区一删一非空行须红 / S2 区一关键词换字须红该词点名 / S3 单区钉表空壳须红 /
C1 完好区一样本须绿 / C2 完好区二样本须绿。自检不过先退 2（判语面点名自检红行）。
读出区一落空（节头找不到）照计零行 → 行数格红——信念段被灭即红、不静默绿。

退出码：0=自检 5 格全过＋真档两区全格绿；1=任一 ✗（含自检样本判不出点名形）；
2=工具面断（gate_json.py 读不到 / docstring 找不到 / 自检红——防静默绿）。
"""
import io
import os
import re
import sys
if "--json" in sys.argv[1:]:  # 机读输出件（docs/GATES.md）；不带开关不进此支
    import gate_json
    gate_json.maybe_json(__file__)

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
GATES_MD = os.path.join(ROOT, "docs", "GATES.md")
GATE_JSON = os.path.join(TOOLS, "gate_json.py")

# ── 关键词哨面（第 2 格 = 在衙行数钉；拨颁必同笔随同色 §五.3）──
PP_KEYS = [
    ("什么算门禁", 1),
    ("入册一次做齐", 1),
    ("REGISTRY", 4),
    ("SUBCHECKS", 2),
    ("CI_STEPS", 3),
    ("四档与 CI 名单", 1),
    ("生成格口诀", 1),
]
GJ_KEYS = [
    ("机读输出", 1),
    ("门禁清单", 1),
    ("REGISTRY", 1),
    ("SUBCHECKS", 1),
    ("CI_STEPS", 1),
]

BELIEF_PINS = {
    "pp": {"lines": 16, "bullets": 4, "steps": 5, "keys": PP_KEYS},
    "gj": {"lines": 34, "nonblank": 32, "keys": GJ_KEYS},
}
# Truth 钉注（本片不写后续注册片钉——BELIEF_PINS 对「末态文档」单 SoR 已足：
# §五.1 +1 登句与 §三 小节均手写行、拨颁必同笔随同色照 §五.3，临窗 stub 不入持钉）。

STEP_RE = re.compile(r"\s+\d+\.\s")


def _pp_metrics(text):
    """区一度量：§五.1 节 = 「### 五.1 」头行起到下一 `### ` 头止（头行不计）。"""
    lines = text.splitlines()
    hs = [i for i, l in enumerate(lines) if l.startswith("### 五.1 ")]
    if len(hs) != 1:
        return None, hs
    s = hs[0]
    nx = [i for i in range(s + 1, len(lines)) if lines[i].startswith("### ")]
    e = nx[0] if nx else len(lines)
    sec = lines[s + 1:e]
    keys = [(kw, sum(1 for l in sec if kw in l)) for kw, _ in PP_KEYS]
    return {"lines": sum(1 for l in sec if l.strip()),
            "bullets": sum(1 for l in sec if l.startswith("- ")),
            "steps": sum(1 for l in sec if STEP_RE.match(l)),
            "keys": keys}, None


def _gj_metrics(text):
    """区二度量：首个三引号开串行起到首个以三引号收尾的行止（含头尾两行）。"""
    lines = text.splitlines()
    hi = [i for i, l in enumerate(lines) if l.lstrip().startswith('"""')]
    if not hi:
        return None
    s = hi[0]
    ei = [i for i in range(s, len(lines))
          if lines[i].rstrip().endswith('"""') and len(lines[i].strip()) >= 3 and (i > s or lines[i].count('"""') >= 2)]
    if not ei:
        return None
    e = ei[0]
    seg = lines[s:e + 1]
    keys = [(kw, sum(1 for l in seg if kw in l)) for kw, _ in GJ_KEYS]
    return {"lines": len(seg),
            "nonblank": sum(1 for l in seg if l.strip()),
            "keys": keys}


FAILS = []


def check(cond, msg):
    print(("   ✓ " if cond else "   ✗ ") + msg)
    if not cond:
        FAILS.append(msg)
    return cond


def scan_pp(text, pins, tag=""):
    """同一条判路：生产与自检样本都走它。返 problems 列表。"""
    probs = []
    met, heads = _pp_metrics(text)
    if met is None:
        return [f"{tag}区一节头识别不齐（`### 五.1 ` 头行应有恰 1 处，实得 {len(heads)}）——信念段被灭判红"]
    if met["lines"] != pins["lines"]:
        probs.append(f"{tag}区一 §五.1 非空行数 {met['lines']} ≠ 钉 {pins['lines']}（删行 / 添行即红；挪段改段须同笔拨颁 BELIEF_PINS）")
    if met["bullets"] != pins["bullets"]:
        probs.append(f"{tag}区一顶层 bullet 行数 {met['bullets']} ≠ 钉 {pins['bullets']}")
    if met["steps"] != pins["steps"]:
        probs.append(f"{tag}区一编号步骤行数 {met['steps']} ≠ 钉 {pins['steps']}（入册五步灭一步即此格红）")
    for (kw, want), (_, got) in zip(pins["keys"], met["keys"]):
        if got != want:
            probs.append(f"{tag}区一关键词哨 `{kw}` 在衙行数 {got} ≠ 钉 {want}（改字 / 灭词即红）")
    return probs


def scan_gj(text, pins, tag=""):
    probs = []
    if not pins["keys"]:
        probs.append(f"{tag}哨集为空（钉表被偷空防静默绿）")
    met = _gj_metrics(text)
    if met is None:
        return probs + [f"{tag}区二 docstring 找不到（开局段被灭判红）"]
    if met["lines"] != pins["lines"]:
        probs.append(f"{tag}区二开局 docstring 段行数 {met['lines']} ≠ 钉 {pins['lines']}（删一句即红）")
    if met["nonblank"] != pins["nonblank"]:
        probs.append(f"{tag}区二 docstring 非空行数 {met['nonblank']} ≠ 钉 {pins['nonblank']}")
    for (kw, want), (_, got) in zip(pins["keys"], met["keys"]):
        if got != want:
            probs.append(f"{tag}区二关键词哨 `{kw}` 在衙行数 {got} ≠ 钉 {want}（改字 / 灭词即红）")
    return probs


def _pp_c1_text():
    """自检 C1 样本：自真档 §五.1 非空体行生成（钉面照真钉拼合，零手抄字面）。"""
    with io.open(GATES_MD, encoding="utf-8", errors="replace") as f:
        glines = f.read().splitlines()
    hs = [i for i, l in enumerate(glines) if l.startswith("### 五.1 ")]
    sec_nb = [l for l in glines[hs[0] + 1:] if l.strip()][:14] if hs else []
    # 节体非空行前 14 行 + 隔一空行 + 余 2 行 → 段内非空行数 = BELIEF_PINS.pp.lines、含 2 空行
    all_nb = [l for l in glines[hs[0] + 1:] if l.strip()] if hs else []
    out = ["### 五.1 入册：进注册表、定档", ""]
    out += all_nb[:14]
    out.append("")
    out += all_nb[14:]
    return "\n".join(out) + "\n\n### 五.2 次节\n"

_GJ_SAMPLE = '""' + '"开局段 机读输出 A。\n门禁清单 一行 REGISTRY / SUBCHECKS / CI_STEPS。\n' + '""' + '"'


def _selftest():
    ok = True
    pins = BELIEF_PINS
    sample = _pp_c1_text()
    # C1 完好区一样本须绿（样本自我真档生成、钉面即真钉）
    p = scan_pp(sample, pins["pp"], tag="[C1] ")
    ok &= check(not p, "自检 C1 完好区一样本须判绿（零 ✗）")
    for x in p[:3]:
        print("      违例：" + x)
    # S1 区一删一纯散文非空行须红（保 bullets/steps/哨词零变——行数格独咬）
    kws = [kw for kw, _ in pins["pp"]["keys"]]
    cl = sample.splitlines()
    victim = next((i for i, l in enumerate(cl)
                   if l.strip() and not l.startswith(("- ", "### "))
                   and not STEP_RE.match(l) and not any(k in l for k in kws)), None)
    burned = "\n".join(cl[:victim] + cl[victim + 1:]) if victim is not None else ""
    p = scan_pp(burned, pins["pp"], tag="[S1] ")
    ok &= check(any("非空行数" in x for x in p),
                "自检 S1 区一删一非空行须判红（行数格点名）")
    for x in p[:3]:
        print("      点名：" + x)
    # S2 区一关键词换字须红该词点名
    burned_kw = sample.replace("入册一次做齐", "入册一次做", 1)
    p = scan_pp(burned_kw, pins["pp"], tag="[S2] ")
    ok &= check(any("入册一次做齐" in x for x in p),
                "自检 S2 区一关键词换字须判红点名该词")
    for x in p[:3]:
        print("      点名：" + x)
    # S3 钉表空壳须红（防静默绿：单区关键词哨集为零先咬）
    p = scan_gj(_GJ_SAMPLE, dict(pins["gj"], keys=[]), tag="[S3] ")
    ok &= check(any("哨集为空" in x for x in p),
                "自检 S3 钉表哨集空壳须判红（防静默绿）")
    # C2 完好区二样本须绿（钉面自样本现算——形状钉路对 3 行替身）
    good_gj = dict(pins["gj"])
    good_gj["lines"] = 3
    good_gj["nonblank"] = sum(1 for l in _GJ_SAMPLE.splitlines() if l.strip())
    good_gj["keys"] = [(kw, sum(1 for l in _GJ_SAMPLE.splitlines() if kw in l)) for kw, _ in GJ_KEYS]
    p = scan_gj(_GJ_SAMPLE, good_gj, tag="[C2] ")
    ok &= check(not p, "自检 C2 完好区二样本须判绿（零 ✗）")
    for x in p[:3]:
        print("      违例：" + x)
    return ok


def main():
    print("check_gates_belief_section：GATES §五.1 信念段＋gate_json 开局段守卫")
    if not os.path.isfile(GATES_MD):
        check(False, f"docs/GATES.md 读不到：{GATES_MD}")
        print("结果：1 项问题")
        return 1
    if not os.path.isfile(GATE_JSON):
        check(False, f"tools/gate_json.py 读不到（无文件形防静默绿）：{GATE_JSON}")
        print("结果：1 项问题")
        return 2
    with io.open(GATES_MD, encoding="utf-8", errors="replace") as f:
        gtext = f.read()
    with io.open(GATE_JSON, encoding="utf-8", errors="replace") as f:
        jtext = f.read()

    # 哨集空壳防静默绿（§五.3 S3 形）：任一区哨集为零先咬
    if not BELIEF_PINS["pp"]["keys"] or not BELIEF_PINS["gj"]["keys"]:
        check(False, "哨集空壳：BELIEF_PINS 关键词哨集为零（钉表被偷空即此格红）")
        print(f"结果：{len(FAILS)} 项问题")
        return 1

    # 真档两区先扫先印（真红行永远落袋，不被自检绿格违例截断——判语形轨：真档红因可读）
    probs = scan_pp(gtext, BELIEF_PINS["pp"]) + scan_gj(jtext, BELIEF_PINS["gj"])
    ok = check(not probs, "两区真档照钉：§五.1 行数/bullets/steps/关键词 与 开局 docstring 行数/关键词 全格绿")
    for x in probs:
        print("   " + x)
    if not _selftest():
        print("结果：自检红（脚本判路坏了，先修脚本）")
        return 1
    if ok:
        print("结果：全部通过")
        return 0
    print(f"结果：{len(FAILS)} 项问题")
    return 1


if __name__ == "__main__":
    sys.exit(main())
