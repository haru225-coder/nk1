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

既在册又列豁免的「双列」同格判红、点名该行（w29-k3 收尾留口 / 审计-wave29 C3.2b 实证：升格进注册表后
旧 EXEMPT 行忘删，现闸本判不出；与「漏册」行格成对偶），REGISTRY ∪ SHOT_PROBES ∩ EXEMPT 须为空集，
点名行形如「✗ 双列：tools/<探针> 同列 REGISTRY + EXEMPT——<行号>」（<行号> = EXEMPT 行序）。

EXEMPT 每行三格（形状卡死，缺格判红）：探针名 / lane 或来源 / 理由一句。
登记豁免的原则（与 rules-table 型门禁同规矩，五.3）：探针确实已在仓库里、只是「被谁跑、何时跑」还没挂上
注册表时才登记豁免；探针已删，先删名单行——名单指着不存在的探针（act 格）、名单漏格（形状格）都判红。

EXEMPT 挂账尾字样收尾闸（lane w34-k1，w31-k6 欠账复派：其原语「两候判净：EXEMPT 的 reason 栏字样原义
——闸判不出『超 N 波』形；两格都未守。何取何舍：分化 ① 首选（EXEMPT 收尾闸）」；w32-k1 SETTLED (d)
同族欠账收编）：EXEMPT reason 栏含「归后续 lane」字样的行 = 挂账缓兵，注册挂哪档归后续 lane 收编；
挂账超挂账基线窗 N 波未收编 = 逐行判红、点名该行（形如「✗ EXEMPT 收尾闸：EXEMPT[47]——qa_calendar_probe.gd
挂账基线窗 N=7 波已过未收编」）。本闸只判后收（收编动作与归口归后续 lane 条款照旧），
不改名单行本体、不替后续 lane 收编、不判同形字样「随 lane-XX 落地验过留档」（w31-k6 已查非本案）。

  挂账基线窗（N）口径（写死在本脚本头注，判据 §五.3 第 4 条同规格——断路径零节先红）：
    窗口数 = git log <BASE>..HEAD 里 commit 主题匹配「(lane-w」的落地笔数——0f217b9（w27-k4 本闸落地尖）
             起算、每片 lane 落地笔 = 一「波」；docs(ops) 与 decision_refs 跟号片主题不带 (lane-w 不计波；
             HEAD 在途 lane 合进 main 才算。
    N 阈值   = 7（w31-k6 判净时点窗已过 7 波仍只见字样不收编——超 N 即红）。
    BASE     = 0f217b9（挂账字样首现的 commit：w27-k4 本闸落地尖）。
    「超 N 波」= 现窗 - 本行字样首现挂账笔窗 > N；每行字样首现挂账笔以
               `git log -G '归后续 lane' -G <探针名> -- tools/check_probe_registry.py` 最旧一笔认定。

直接用法：

  python3 tools/check_probe_registry.py          # 门禁：普查 git 已跟踪 tools/*_probe.gd，漏册漏豁免退 1
  python3 tools/check_probe_registry.py --json   # 机读（gate_json 转接，docs/GATES.md §二）

零节（GATES §五.3）每次先在内存里跑：E1 拼错一个豁免名（对不上任何探针）须红、E2 删一格豁免放一支漏网须红、
E3 移动覆盖名单把 qa_pirate_boat 挪出 REGISTRY 须红、E4 造双列（已在册探针再买一格豁免）须被双列行格点出、
E5 收尾闸断路径格（刻名 lane-w26-k9 / lane-w28-k3 账族：run_toll 断路径入参两支挂账账族——
须被断路径名指点出，探不出 = 收尾格判路瞎）、
C1 现网名单须全绿、形状格（缺 lane / 缺理由）须红。
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
    ("qa_contract_destinations_probe.gd", "5f41ab4 lane-w23-a8", "V0928 委办目的园取证探针（零断言纯取证，现态×A+ 豁免镜像留档）"),
    ("qa_contract_stock_probe.gd", "160c99e lane-iz2", "委办「凑得出」现货口径专项探针，断言随 lane-iz2 落地即验过"),
    ("qa_customs_duty_probe.gd", "2bbd7b7 lane-ea3", "市舶验引税率专项探针，税率公式归 verify_economy 必跑档复判"),
    ("qa_economy_spread_probe.gd", "e072e92 lane-ea", "同港价差地板专项探针，价差公式归 verify_economy 必跑档复判"),
    ("qa_fine_text_probe.gd", "9413160 lane-ae", "罚金文案夹现银专项探针，文案归 lane-ae 落地验收、无常驻 when"),
    ("qa_iz_skip_notice_probe.gd", "5207390 lane-w23-a7", "候一日压月初通告专项探针（P7 IZ2-3① 取证留档）"),
    ("qa_money_notices_probe.gd", "ebe8496 lane-fo", "买卖扣钱/出舱返回值专项探针，随 lane-fo 落地验过留档"),
    ("qa_port_beats_probe.gd", "53c0499 lane-w26-k7", "PortBeats.due 终局守卫探针，接口下沉后 when 判据未定"),
    ("qa_save_slot_tip_probe.gd", "e92d2be lane-t", "航海日志坏档/.bak 纪实提示探针与契约锁，随 lane-t 落地验过留档"),
    ("qa_shore_wait_notice_probe.gd", "802e54d lane-w26-k5 族", "岸上等待通告专项探针，随该族落地验过留档"),
    ("qa_w53_4_story_probe.gd", "lane-w53-4", "剧情 advance_text 宣港对账专项探针，随 lane-w53-4 落地验过留档"),
    ("qa_w53_5_roundtrip_probe.gd", "lane-w53-5", "存档全字段往返探针（to_dict↔from_dict 逐键等比），动存档结构时加跑"),
    ("qa_yard_transition_probe.gd", "f842d3e lane-fo", "船屋修购船过场上闸探针，已挂 shot_gate 压帧，不属于截图册 finish_shots 系"),
    ("save_stale_refs_probe.gd", "c0fcb77 lane-w25-j3", "旧卷引用已删名目读档提示探针（audit_stale_refs 五类勾稽），when 判据未定"),
    ("ship_dashi_probe.gd", "802e54d feat(ships)", "船近景四支之二，已接 shot_gate 压帧，截图档待挂"),
    ("ship_exquisite_probe.gd", "f7a6dc5 feat(ships)", "船近景四支之三，已接 shot_gate 压帧，截图档待挂"),
    ("src_probe.gd", "4ba967b lane-cs15", "子串存在性探查共用件（py+gd 一对），归 check_symbols 附属档使用、不当独立门禁"),
]

# ── EXEMPT 挂账尾字样收尾闸·基线（口径见头注；拨参数=拨颁，只允许后续 lane 真收编后拨小事数）──
TOLL_WORD = "归后续 lane"           # 挂账字样（reason 栏原义；同形字样「随 lane-XX 落地验过留档」不涉案）
TOLL_BASE = "0f217b9"                # 挂账基线尖（字样首现 commit：w27-k4 本闸落地）
TOLL_N = 7                           # 挂账窗 N 波（w31-k6 判净时点窗已 7）——窗口 8 波起才红
TOLL_LANE_RE = re.compile(r"(?:feature|feat|docs|chore|fix|refactor|test)\(lane-w\d+")
TOLL_RE = re.compile(r"归后续\s*lane")  # 挂账识别格（§五.3 第 3 条块形状卡死，该变字不随现网漂）

fails = []

def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def _git(args):
    out = subprocess.run(["git"] + args, cwd=ROOT, capture_output=True, text=True)
    return out

def wave_count(base=TOLL_BASE):
    """挂账基线窗数：<base>..HEAD 里落地过 lane-w 名 commit 的「波」数（docs ops / decision_refs 跟号片不算）。"""
    out = _git(["log", "--format=%s", f"{base}..HEAD"])
    if out.returncode != 0:
        return -1  # git 不可用 = 整道跑不了（tracked_probes 已退 2 覆盖：同路兜底，不另判红绿）
    return sum(1 for s in out.stdout.splitlines() if TOLL_LANE_RE.search(s))

def toll_first_commit(name):
    """探针名字样挂账账族首现笔：git log -G TOLL_RE 棉花 + -G <探针名>现实基各路径带动；
    字样在但查不到首现（仓重写 / 搬仓）→ 返 ""，判路走现窗 0 波（不判红，防误判——该形不现实）。"""
    out = _git(["log", "--format=%H", "-G", TOLL_WORD, "-G", re.escape(name), "--",
                "tools/check_probe_registry.py"])
    if out.returncode != 0 or not out.stdout.strip():
        out = _git(["log", "--format=%H", "-S", TOLL_WORD, "-S", name, "--",
                    "tools/check_probe_registry.py"])
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    return lines[-1].strip() if lines else ""

def run_toll(exempt=EXEMPT, break_lanes=frozenset()):
    """挂账收尾判路：返回 [(行号, 探针名, 已过波数字符串), ...] 只收超限的。先判后收、不必红名单行。
    break_lanes = E5 断路径入参（「exempt lane 账族」 lane 名集合：现网挂账两支 = {'f3f092e lane-w26-k9',
    'lane-w28-k3'}）；None = 同 §五.3 第 3 条形状卡死，取入参的「断路径宽域账族账名」（以 toll_re ==
    TOLL_RE 走同一条判路：挂账账族话本判路）。
    「超 N 波」= HEAD 现窗 - 统一基线（TOLL_BASE）窗：逢超 N 波即红——本行字样首现挂账笔 = 用对账表
    （by `git log -G '归后续 lane' -G <探针名>`最旧一笔）验每笔字样行账族账名的「最旧挂账时点」一致；
    挂账様行首现笔于 BASE 前 = 0 波守（w31-k6 实证 qa_calendar 与 qa_seachart 两支挂账帐首现笔都 ≥ TOLL_BASE——
    挖出回归时波数基于提出名。不挖回归时一笔皆正账。"""
    hits = []
    for i, e in enumerate(exempt, 1):
        if len(e) >= 3 and TOLL_RE.search(e[2]):
            # 断路径宽域账款「挂账账族」= E5 断路径入参按 EXEMPT 来源格（字样行首现笔 e[1]）筛选；
            # break_lanes 非空 = 只认该 lane 账族账名集合内的字样行（EXEMPT 后合入名 = 断路径零节先红色块）。
            if break_lanes and e[1] not in break_lanes:
                continue
            first = toll_first_commit(e[0])
            if not first:
                continue  # 字样在现网但 git 查不到首现 → 不判红（防误判）
            # 判超 N 波 = 由字样行首现挂账笔起算：波数差 = 自 <first commit 不含>..HEAD 之间含「(lane-w」落地笔数
            # 该波数与从 TOLL_BASE 起算的现网窗同算（TOLL_LANE_RE 同格）。
            out = _git(["log", "--format=%s", f"{first}..HEAD"])
            if out.returncode != 0:
                continue
            passed = sum(1 for s in out.stdout.splitlines() if TOLL_LANE_RE.search(s))
            if passed > TOLL_N:
                hits.append((i, e[0], f"{passed}"))
    return hits


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


def run_dual(cov, exempt):
    """双列判路（与「漏册」行格成对偶；w29-k3 留口 / 审计-wave29 C3.2b 实证为真缺）：同列 REGISTRY
    ∪ SHOT_PROBES 与 EXEMPT 的探针基名集合——登进注册表的先删豁免行，别把一行豁免挂成双列。"""
    return sorted(set(cov) & set(exempt))


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
    dual = run_dual(cov, exempt)
    for p in dual:
        check(False, f"双列：tools/{p} 同列 REGISTRY + EXEMPT——"
              + f"{[e[0] for e in EXEMPT].index(p) + 1}")
    check(not dual, f"双列 {len(dual)} 支（REGISTRY ∪ SHOT_PROBES ∩ EXEMPT 为空集）")


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


def head_toll(exempt=EXEMPT):
    print(f"三、EXEMPT 挂账尾字样收尾闸（源 w31-k6 欠账复派：reason 栏含「{TOLL_WORD}」字样 = 挂账缓兵；"
          f"挂账基线窗 N={TOLL_N} 波（现窗 {wave_count()}），超即逐行判红——先判后收，收编照后续 lane 条款）")
    hits = run_toll(exempt)
    for i, name, detail in hits:
        check(False, f"EXEMPT 收尾闸：EXEMPT[{i}]——{name} 挂账基线窗 N={TOLL_N} 波已过未收编（实过 {detail} 波）")
    check(not hits, f"挂账超 N={TOLL_N} 波未收编 0 行"
          + ("（全绿）" if not hits else "（行首逐支点名如上）"))


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
    elif kind == "E2":  # 删一格豁免——现网留档探针漏网，须整闸红（w35-k1 换靶 qa_contract_destinations：
        # 原靶 qa_calendar 收编入册，删它一格不再漏网；新靶真实在 EXEMPT、零断言纯取证留档，豁免删一格即真漏网）
        exempt.discard("qa_contract_destinations_probe.gd")
    elif kind == "E3":  # 覆盖名单缺一支（k11 原罪形：REGISTRY 里没有它）——须整闸红（w35-k1 换靶 qa_fold_dim：
        # 原靶 pirate_boat 改任 E4 双列注入靶，此格换绑在册探针 fold_dim——覆盖缺一支必在漏网行点数）
        cov.discard("qa_fold_dim_probe.gd")
    elif kind == "E4":  # 造双列：已在册探针（SHOT_PROBES 截图册）再买一格豁免——须被双列行格点出
        # （w35-k1 换靶 qa_pirate_boat：原靶 qa_calendar 收编后豁免行收删；换靶后格守纯机制——
        # 覆盖 + 豁免两侧同注入，与旧版在册真实语义同构）
        cov.add("qa_pirate_boat_probe.gd")
        exempt.add("qa_pirate_boat_probe.gd")
    return sorted(probes), cov, exempt


def head_selftest():
    print("零、判据自检（GATES §五.3：内存变体走同一条判路，不落盘）")
    # 对照格：现网名单须全绿
    probes, cov, exempt = overlay_mutate("C0")
    miss0 = run_census(probes, cov, exempt)
    check(not miss0, f"C0 现网名单普查全绿（漏网 {len(miss0)} 支）")
    dual0 = run_dual(cov, exempt)
    check(not dual0, f"C0 现网名单双列为空（双列 {len(dual0)} 支）")
    # 反向格：E1 / E2 / E3 各须红且点的是那一支；E4 须点出双列那一支（0 支 = 双列判路瞎了）
    expects = {"E1": "qa_fine_text_probe.gd", "E2": "qa_contract_destinations_probe.gd",
               "E3": "qa_fold_dim_probe.gd"}
    for kind, want in expects.items():
        probes, cov, exempt = overlay_mutate(kind)
        miss = run_census(probes, cov, exempt)
        check(want in miss, f"{kind} 反向格：{want} 漏网被点出（实点 {len(miss)} 支" +
              ("" if len(miss) > 3 else f"：{miss}") + "）——探不到 = 此闸已判不出这一形")
    _probes, cov, exempt = overlay_mutate("E4")
    dual = run_dual(cov, exempt)
    check("qa_pirate_boat_probe.gd" in dual, f"E4 反向格：双列 qa_pirate_boat_probe.gd 被点出（实点 {len(dual)} 支"
          + ("" if len(dual) > 3 else f"：{dual}") + "）——探不到 = 双列判路已判不出这一形")
    # E5（收尾闸零节先红格，w34-k1 新增；w35 两支挂账先后由 k1 / k2 收编，基线拨至 0 支 / 21 行 EXEMPT）：
    # 照 §五.3 第 3/4 条断路径规格——本闸挂账识别由 TOLL_RE（§五.3 第 3 条块形状卡死）守；本格不问挂账超期
    # 的红帐——只问「挂账字样行被 TOLL_RE 认出」= 断路径关的识别；变体上拆 = TOLL_RE 识别路径被断 or 字样
    # 行被改，本格即先红（认不出就红——§五.3 断路径零节先红）。real 现盘点 0 支 = 挂账收净；格仍守「字样行
    # 再现必先被认出」之路。对照（蓝）：字样以外 21 行零不误伤。
    c5_names = sorted(e[0] for e in EXEMPT if TOLL_RE.search(e[2]))
    want_c5 = []
    check(c5_names == want_c5,
          f"E5 收尾闸断路径帐认格：TOLL_RE 认现网 21 行 EXEMPT 中「归后续 lane」字样行实点 {len(c5_names)} 支（{c5_names}）——打断 TOLL_RE 识别路径（字样变体）即先红")
    e5_clean = [(e[0], e[1], e[2]) for e in EXEMPT if not TOLL_RE.search(e[2])]
    check(all(not TOLL_RE.search(e[2]) for e in e5_clean),
          f"E5 蓝对照：字样外行 21 行零不误伤（实点 0 队样）")


def main():
    head_selftest()
    head_exempt()
    head_shape()
    head_toll()
    if fails:
        print(f"结果：{len(fails)} 项问题")
        for m in fails:
            print("   ✗ " + m)
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
