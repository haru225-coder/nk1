#!/usr/bin/env python3
"""探针「注册或豁免」闸（lane w27-k4，来源 k11 审计「最该补的门禁」第 2 条——
原文：「每支不被一键跑引用的探针，compile 门禁之外加一道『注册或豁免』闸——SCRIPTS 登记只管编译，
不管被跑；以 gate_json.py families / not_family 同款思路收编 tools/ 下 *_probe.gd，防『探针立了坟』式
欠账再发生（本批即有 b2 一支漏网）」。k11 抽样总表末行 qa_rest_days_probe 漏注册一支由 wave27 k3 收，
本片是普查所有同类漏网并把闸建起来）。

覆盖名单两处（探针满足其一即算在册）：
  一、gate_json.REGISTRY 里 file 恰为 tools/<探针>（qa_pirate_boat / save_robust / save_migrate 三支）；
  二、gate_json.SHOT_PROBES 截图册（16 支）——截图脚本走 shot_gate 收尾、已在批量巡检批量跑，算「被跑」。

既不在册也不在 EXEMPT 的探针，每支行首红字点名，退 1（漏网 = 探针立坟，k11 原话）。

EXEMPT 每行三格（形状卡死，缺格判红）：探针名 / lane 或来源 / 理由一句。
登记豁免的原则（与 rules-table 型门禁同规矩，五.3）：探针确实已在仓库里、只是「被谁跑、何时跑」还没挂上
注册表时才登记豁免；探针已删，先删名单行——名单指着不存在的探针（act 格）、名单漏格（形状格）都判红。

直接用法：

  python3 tools/check_probe_registry.py          # 门禁：普查 git 已跟踪 tools/*_probe.gd，漏册漏豁免退 1
  python3 tools/check_probe_registry.py --json   # 机读（gate_json 转接，docs/GATES.md §二）

零节（GATES §五.3）每次先在内存里跑：E1 拼错一个豁免名（对不上任何探针）须红、E2 删一格豁免放一支漏网须红、
E3 移动覆盖名单把 qa_pirate_boat 挪出 REGISTRY 须红、C1 现网名单须全绿、形状格（缺 lane / 缺理由）须红。
"""
import os, re, subprocess, sys
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)

# ── 豁免名单（每行：探针名 / lane·来源 / 理由一句；行序按探针名字典序，新行插对位置）──
EXEMPT = [
    ("atmos_water_probe.gd", "c1f0e5a feat(atmos)", "海面着色器观感探针，只判「起得来、出图」式观感，入册口径未定"),
    ("combat_outcomes_probe.gd", "98a76c9 feat(combat)", "海战胜负三维演出探针，战果接线已归 combat_realism 锚点档"),
    ("combat_realism_probe.gd", "38e4584 feat(combat10)", "写实海战冒烟探针，剧情挂钩锚点验证完即留档，尚无 when 判据"),
    ("japan_ship_probe.gd", "f7a6dc5 feat(ships)", "船近景四支之一，已接 shot_gate 压帧（gates_md 入册判据认它），截图档待挂"),
    ("letterbox_signal_probe.gd", "7a47d15 lane-gd12", "墨边收尾信号契约探针，已挂 shot_gate 压帧，不属于截图册 finish_shots 系"),
    ("qa_bribe_probe.gd", "2552fa8 lane-w23-a5", "塞钱 48 格实测表：断言全注掉的纯取证探针（现态留档，不判红绿）"),
    ("qa_calendar_probe.gd", "f3f092e lane-w26-k9", "日历推进 / 改元显示断言探针：k11 因果链第三支漏网，本闸普查首红支，注册归后续 lane"),
    ("qa_contract_destinations_probe.gd", "5f41ab4 lane-w23-a8", "V0928 委办目的园取证探针（零断言纯取证，现态×A+ 豁免镜像留档）"),
    ("qa_contract_stock_probe.gd", "160c99e lane-iz2", "委办「凑得出」现货口径专项探针，断言随 lane-iz2 落地即验过"),
    ("qa_customs_duty_probe.gd", "2bbd7b7 lane-ea3", "市舶验引税率专项探针，税率公式归 verify_economy 必跑档复判"),
    ("qa_economy_spread_probe.gd", "e072e92 lane-ea", "同港价差地板专项探针，价差公式归 verify_economy 必跑档复判"),
    ("qa_fine_text_probe.gd", "9413160 lane-ae", "罚金文案夹现银专项探针，文案归 lane-ae 落地验收、无常驻 when"),
    ("qa_iz_skip_notice_probe.gd", "5207390 lane-w23-a7", "候一日压月初通告专项探针（P7 IZ2-3① 取证留档）"),
    ("qa_money_notices_probe.gd", "ebe8496 lane-fo", "买卖扣钱/出舱返回值专项探针，随 lane-fo 落地验过留档"),
    ("qa_port_beats_probe.gd", "53c0499 lane-w26-k7", "PortBeats.due 终局守卫探针，接口下沉后 when 判据未定"),
    ("qa_save_slot_tip_probe.gd", "e92d2be lane-t", "航海日志坏档/.bak 纪实提示探针与契约锁，随 lane-t 落地验过留档"),
    ("qa_seachart_advance_probe.gd", "lane-w28-k3", "上屏断言 sweep③——SeaChart 海图「航段」名号跨月推进时序：w26-k9 交主控 5 的新探针，注册挂哪档归后续 lane"),
    ("qa_shore_wait_notice_probe.gd", "802e54d lane-w26-k5 族", "岸上等待通告专项探针，随该族落地验过留档"),
    ("qa_yard_transition_probe.gd", "f842d3e lane-fo", "船屋修购船过场上闸探针，已挂 shot_gate 压帧，不属于截图册 finish_shots 系"),
    ("save_stale_refs_probe.gd", "c0fcb77 lane-w25-j3", "旧卷引用已删名目读档提示探针（audit_stale_refs 五类勾稽），when 判据未定"),
    ("ship_dashi_probe.gd", "802e54d feat(ships)", "船近景四支之二，已接 shot_gate 压帧，截图档待挂"),
    ("ship_exquisite_probe.gd", "f7a6dc5 feat(ships)", "船近景四支之三，已接 shot_gate 压帧，截图档待挂"),
    ("src_probe.gd", "4ba967b lane-cs15", "子串存在性探查共用件（py+gd 一对），归 check_symbols 附属档使用、不当独立门禁"),
]

fails = []

def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def tracked_probes():
    """git 已跟踪的 tools/*_probe.gd（与 check_docs_index / check_sidecars 同口径：未跟踪的不染红共用树）。"""
    out = subprocess.run(["git", "ls-files", "tools/*_probe.gd"],
                         cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:  # find: git 不可用时整道跑不了，退 2 不归红绿
        print("check_probe_registry: git ls-files 失败：" + out.stderr.strip())
        sys.exit(2)
    return sorted(os.path.basename(p) for p in out.stdout.split())


def covered(reg_module):
    """gate_json 的 REGISTRY file 列 + SHOT_PROBES 第一列（探针基名集合）。"""
    reg = {os.path.basename(g.get("file", "")) for g in reg_module.REGISTRY if g.get("file")}
    shots = {os.path.basename(p) for p, _lane in reg_module.SHOT_PROBES}
    return reg | shots


def exempt_names(exempt=EXEMPT):
    return {e[0] for e in exempt}


def run_census(probes, cov, exempt):
    """普查正路：返回 (漏网列表, 问题列表)。probes / cov / exempt 都是基名集合——零节与正路走同一函数。"""
    missing = [p for p in probes if p not in cov and p not in exempt]
    return missing


def head_exempt():
    print("一、探针普查（git 已跟踪 tools/*_probe.gd；注册 = gate_json REGISTRY file 列 ∪ SHOT_PROBES 截图册；"
          "都不沾的须登 EXEMPT 豁免名单）")
    probes = tracked_probes()
    try:
        sys.path.insert(0, TOOLS)
        import gate_json as reg
    finally:
        sys.path.remove(TOOLS)
    cov = covered(reg)
    exempt = exempt_names()
    check(bool(probes), f"git 已跟踪探针 {len(probes)} 支（0 支 = git ls-files 口径漂了）")
    stale = sorted(exempt - set(probes))
    check(not stale, "豁免名单每行都指着在仓探针"
          + (f"（{len(exempt)} 行）" if not stale else f"——{stale} 已不在仓 / 名写错：探针删了先删名单行，改名跟名单"))
    reg_probe_entries = sorted(os.path.basename(g["file"]) for g in reg.REGISTRY
                               if g.get("file", "").endswith("_probe.gd"))
    check(len(reg_probe_entries) == len(set(reg_probe_entries)),
          f"REGISTRY 里 *_probe.gd 条目不重号（{len(reg_probe_entries)} 条）")
    missing = run_census(probes, cov, exempt)
    for p in missing:
        check(False, f"探针漏册：tools/{p}——不在 REGISTRY / SHOT_PROBES，也未登豁免；"
              "修法：登进 gate_json REGISTRY（tier 按 §五.1 定），确属留档 / 取证件的登记 EXEMPT 一行带理由")
    check(not missing, f"漏注册且漏豁免 {len(missing)} 支"
          + ("（全绿）" if not missing else "（行首逐支点名如上）"))
    ok_shots = sorted({os.path.basename(p) for p, _ in reg.SHOT_PROBES} & set(probes))
    check(len(ok_shots) >= 1, f"SHOT_PROBES 截图册认到 {len(ok_shots)} 支在册探针（0 支 = SHOT_PROBES 口径漂了）")


def head_shape():
    print("二、豁免名单形状（每行三格：探针名 / lane·来源 / 理由；缺格判红——rules-table 型门禁的表自守，§五.3）")
    for i, e in enumerate(EXEMPT):
        check(len(e) == 3 and all(isinstance(x, str) and x.strip() for x in e),
              f"EXEMPT 第 {i + 1} 行三格齐（探针 {e[0] if e else '?'}）")
        if len(e) >= 2:
            check(bool(re.search(r"[0-9a-f]{7}|lane|wave", e[1])),
                  f"EXEMPT 第 {i + 1} 行来源格带 lane 名或 commit（{e[0]}）")
    names = [e[0] for e in EXEMPT]
    check(len(names) == len(set(names)), f"豁免名单不重名（{len(names)} 行）")
    check(names == sorted(names), "豁免名单按探针名字典序排（新行插对位置，别堆尾）")


def overlay_mutate(kind):
    """零节变异（内存量具，不落盘）：返回 (probes, cov, exempt) 三集合的变体。"""
    probes = set(tracked_probes())
    sys.path.insert(0, TOOLS)
    try:
        import gate_json as reg
        cov = covered(reg)
    finally:
        sys.path.remove(TOOLS)
    exempt = set(exempt_names())
    if kind == "E1":  # 拼错一个豁免名——对不上任何探针，须整闸红
        exempt = {n.replace(".gd", "X.gd") if n == "qa_fine_text_probe.gd" else n for n in exempt}
    elif kind == "E2":  # 删一格豁免——现网留档探针 qa_calendar_probe 漏网，须整闸红
        exempt.discard("qa_calendar_probe.gd")
    elif kind == "E3":  # 覆盖名单缺一支（k11 原罪形：REGISTRY 里没有它）——须整闸红
        cov.discard("qa_pirate_boat_probe.gd")
    return sorted(probes), cov, exempt


def head_selftest():
    print("零、判据自检（GATES §五.3：内存变体走同一条判路，不落盘）")
    # 对照格：现网名单须全绿
    probes, cov, exempt = overlay_mutate("C0")
    miss0 = run_census(probes, cov, exempt)
    check(not miss0, f"C0 现网名单普查全绿（漏网 {len(miss0)} 支）")
    # 反向格：E1 / E2 / E3 各须红且点的是那一支
    expects = {"E1": "qa_fine_text_probe.gd", "E2": "qa_calendar_probe.gd", "E3": "qa_pirate_boat_probe.gd"}
    for kind, want in expects.items():
        probes, cov, exempt = overlay_mutate(kind)
        miss = run_census(probes, cov, exempt)
        check(want in miss, f"{kind} 反向格：{want} 漏网被点出（实点 {len(miss)} 支" +
              ("" if len(miss) > 3 else f"：{miss}") + "）——探不到 = 此闸已判不出这一形")


def main():
    head_selftest()
    head_exempt()
    head_shape()
    if fails:
        print(f"结果：{len(fails)} 项问题")
        for m in fails:
            print("   ✗ " + m)
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
