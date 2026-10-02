#!/usr/bin/env python3
"""剧情数据静态校验：news.json / scenes.json effects / npcs.json。
起因：序章 effects 里的 sea_tendency / scholar_tendency 曾在 Main.apply_effects 里无分支，
静默丢弃了两年。此脚本把「数据里写了的效果键，代码必须接住」做成门禁。"""
import copy, json, os, re, sys, pathlib
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
from src_probe import has_func, calls, has_tok  # 按名认函数的探查一律经 tools/src_probe.py（lane cs15：不按前缀认名）
FAIL = []


def load(n):
    with open(os.path.join(ROOT, "data", n), encoding="utf-8") as f:
        return json.load(f)


def check(cond, msg):
    if not cond:
        FAIL.append(msg)


# ── apply_effects 实际接住的键 ─────────────────────────
main_src = open(os.path.join(ROOT, "scripts", "Main.gd"), encoding="utf-8").read()
m = re.search(r"func apply_effects\(.*?\n(?=\nfunc |\Z)", main_src, re.S)
check(m is not None, "Main.gd 缺 apply_effects")
handled = set()
if m:
    for arm in re.findall(r'^\s*((?:"[a-z_]+"\s*,\s*)*"[a-z_]+"):\s*$', m.group(0), re.M):
        handled |= set(re.findall(r'"([a-z_]+)"', arm))
check(len(handled) >= 5, f"apply_effects 只接住 {sorted(handled)}，疑似解析失败")

# ── scenes.json：所有 effects 键必须被接住 ────────────
scenes = load("scenes.json")["scenes"]
ids = [s["id"] for s in scenes]
check(len(ids) == len(set(ids)), "scenes.json 场景 id 重复")
idset = set(ids)
ports_all = load("ports.json")["ports"]
port_ids = {p["id"] for p in ports_all}
port_unlock = {p["id"]: int(str(p.get("unlock", "ch1"))[2:] or 1) for p in ports_all}
# Main.FACILITY_SUFFIXES 的镜像：xxx_market 等由 Main 动态生成
fac_m = re.search(r'const FACILITY_SUFFIXES := \[(.*?)\]', main_src, re.S)
FACILITY_SUFFIXES = tuple(re.findall(r'"(_[a-z]+)"', fac_m.group(1))) if fac_m else ()
check(len(FACILITY_SUFFIXES) >= 4, "Main.FACILITY_SUFFIXES 解析失败")
placeholder_m = re.search(r'const FACILITY_PLACEHOLDER := \{(.*?)\n\}', main_src, re.S)
PLACEHOLDERS = set(re.findall(r'^\t"([a-z_]+)":', placeholder_m.group(1), re.M)) if placeholder_m else set()


def next_resolves(nxt: str) -> bool:
    """Main.load_scene 的解析顺序：设施后缀 → scenes.json → ports.json → 占位页。
    起始场景以外，任何 next 都必须落到这四类之一，否则真机是「区域施工中」。"""
    if nxt in idset or nxt in port_ids or nxt in PLACEHOLDERS:
        return True
    for suf in FACILITY_SUFFIXES:
        if nxt.endswith(suf) and nxt[: -len(suf)] in port_ids | idset:
            return True
    return False


for s in scenes:
    for c in s.get("choices", []):
        for k in c.get("effects", {}):
            check(k in handled, f"scenes.json {s['id']} 效果键 `{k}` 未被 Main.apply_effects 处理")
        nxt = c.get("next", "")
        if nxt:
            check(next_resolves(nxt), f"scenes.json {s['id']} 跳转到无法解析的 `{nxt}`（不在 scenes/ports/设施/占位任何一类）")

# 2026-09-14 审计 P0：剧情幕 id 与港口 id 同名却不是 type=port 时，海图抵港 load_scene 命中剧情表、
# 走调查页而不调 _on_enter_port，visited_ports 永不记录——章节 must_visit 在真机上不可完成。
# 七道门禁（2026-09-14 审计时口径；现行 16 道）对此全盲（simulate_run 自管 visited）。此处把「同名必是港」做成静态门禁。
for s in scenes:
    if s["id"] in port_ids:
        check(s.get("type") == "port",
              f"scenes.json `{s['id']}` 与 ports.json 港口同名但 type={s.get('type')!r}——抵港会被调查页吞掉，"
              f"visited_ports 不记录；剧情幕请改独立 id（如 {s['id']}_survey）")

# ── chapters.json：must_visit 港必须存在且本章就能到 ──
chapters = load("chapters.json")["chapters"]
for ch in chapters:
    cid = int(ch["id"])
    req = ch.get("next_requires") or {}
    for pid in req.get("must_visit", []):
        check(pid in port_ids, f"chapters {cid} must_visit `{pid}` 不在 ports.json")
        if pid in port_ids:
            check(port_unlock[pid] <= cid,
                  f"chapters {cid} must_visit `{pid}` 要到第 {port_unlock[pid]} 章才解锁，本章永远晋升不了")
    need = int(req.get("visited_count", 0))
    reachable = sum(1 for p in port_ids if port_unlock[p] <= cid)
    check(need <= reachable, f"chapters {cid} visited_count={need} 超过本章可达港口数 {reachable}")

# ── news.json ─────────────────────────────────────────
news = load("news.json")["news"]
nids = [n.get("id", "") for n in news]
check(all(nids), "news.json 有条目缺 id")
check(len(nids) == len(set(nids)), "news.json id 重复")
DATE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
ALLOWED = {"id", "date", "speaker", "text", "text_S", "text_M", "only", "flag", "market"}
IDENTITIES = {"scholar", "merchant", "hometown"}
NEWS_GOODS = {g["id"] for g in load("goods.json")["goods"]}
NEWS_PORTS = {p["id"]: p for p in load("ports.json")["ports"]}
for n in news:
    nid = n.get("id", "?")
    check(DATE.match(str(n.get("date", ""))) is not None, f"news {nid} date 须为 YYYY-MM")
    check("speaker" in n, f"news {nid} 缺 speaker（可为空串）")
    has_text = "text" in n or ("text_S" in n and "text_M" in n)
    check(has_text, f"news {nid} 须有 text，或同时有 text_S 与 text_M")
    extra = set(n) - ALLOWED
    check(not extra, f"news {nid} 含未被消费的字段 {sorted(extra)}（反模式：数据写了代码不读）")
    for f in ("text", "text_S", "text_M"):
        for tok in re.findall(r"\{([a-z_]+)\}", str(n.get(f, ""))):
            check(tok in ("target_name", "player_name"), f"news {nid}.{f} 未知占位符 {{{tok}}}（GameState.news_text 只替换 target_name/player_name）")
    if "only" in n:
        check(n["only"] in IDENTITIES, f"news {nid} only=`{n['only']}` 不是合法身份 {sorted(IDENTITIES)}")
        check(str(n.get("date", "")) > "1268-04", f"news {nid} 带 only 但日期早于 1268-04 殿试结算，那时 identity 还是 undecided，永远发不出去")
    if "market" in n:
        mk = n["market"]
        check(isinstance(mk, dict) and set(mk) <= {"good_id", "mul", "ports"},
              f"news {nid}.market 只认 good_id/mul/ports（Economy.apply_news_market 不读别的键）")
        gid = mk.get("good_id", "") if isinstance(mk, dict) else ""
        check(gid in NEWS_GOODS, f"news {nid}.market good_id=`{gid}` 不在 goods.json")
        mul = mk.get("mul") if isinstance(mk, dict) else None
        check(isinstance(mul, (int, float)) and 0.4 <= mul <= 1.6 and mul != 1.0,
              f"news {nid}.market mul={mul} 须在 0.4–1.6 且 ≠1（冲击在 RATE_MIN–RATE_MAX 内才有意义）")
        mports = mk.get("ports", None) if isinstance(mk, dict) else None
        traders = [pid for pid, p in NEWS_PORTS.items() if gid in p.get("market", {})]
        if mports is None:
            check(bool(traders), f"news {nid}.market 省略 ports 但无港交易 {gid}")
        else:
            check(isinstance(mports, list) and mports and all(pid in traders for pid in mports),
                  f"news {nid}.market ports={mports} 须全部是交易 {gid} 的港口（否则冲击落空）")
    y = int(str(n.get("date", "0000"))[:4] or 0)
    check(1255 <= y <= 1279, f"news {nid} 年份 {y} 超出 1255–1279")

# 1268 结算月之前不得出现任何依赖 identity 锁定的措辞（S/M 双版允许，按倾向选）
# 这里只保证 1268-04 那个月本身没有新闻抢在结算前投放
check(not any(n.get("date") == "1268-04" for n in news), "news.json 不得在 1268-04 投放（与殿试结算同月）")
panic = next((n for n in news if n.get("id") == "n_1273_03_fanfang_panic"), {})
check(panic.get("market", {}).get("good_id") == "aromatic_medicine" and panic.get("market", {}).get("mul", 1) < 1,
      "1273-03 蕃坊恐慌挂香药抛售 market（剧情打磨 §二：香药 −40%）")

# Lane P：新闻上屏字段禁工程/现代/AI 腔；酒馆墙与传闻标签仍被消费
_NEWS_ENG = re.compile(
    r"placeholder|本作|玩家|士人线|海商线|乡土线|TODO|WIP|pipeline|LLM|ChatGPT|大模型|"
    r"玩法循环|核心循环|用户体验|垂直切片|沉浸式|赋能|视觉盛宴"
)
for n in news:
    nid = n.get("id", "?")
    for f in ("text", "text_S", "text_M", "speaker"):
        raw = str(n.get(f, ""))
        if not raw:
            continue
        hit = _NEWS_ENG.search(raw)
        check(hit is None, f"news {nid}.{f} 含工程/现代腔「{hit.group(0) if hit else ''}」")
_gm = open(os.path.join(ROOT, "scripts", "GameManager.gd"), encoding="utf-8").read()
_gs = open(os.path.join(ROOT, "scripts", "GameState.gd"), encoding="utf-8").read()
check("【酒馆传闻】" in _gm, "GameManager 投放新闻须用【酒馆传闻】前缀（空 speaker）")
check("传闻约卖" in _gs and has_func(_gs, "rumor_label"), "GameState.rumor_label 须保留「传闻约卖」上屏标签")
check(has_func(main_src, "_setup_news_wall") and "_TAVERN_NEWS_WALL" in main_src,
      "酒馆须接新闻墙上墙（Main._setup_news_wall → _TAVERN_NEWS_WALL）")
_tnw_path = os.path.join(ROOT, "scripts", "ui", "TavernNewsWall.gd")
check(os.path.isfile(_tnw_path), "缺 scripts/ui/TavernNewsWall.gd（市井札薄）")
if os.path.isfile(_tnw_path):
    _tnw = open(_tnw_path, encoding="utf-8").read()
    check(has_tok(_tnw, "paper_card", call=True) and has_tok(_tnw, "recent_news", call=True) and has_tok(_tnw, "news_text", call=True),
          "TavernNewsWall 须用 paper_card 渲 recent_news/news_text")
    check(calls(main_src, "_TAVERN_NEWS_WALL.mount"), "Main._setup_news_wall 须调 _TAVERN_NEWS_WALL.mount")

# ── npcs.json ─────────────────────────────────────────
npcs = load("npcs.json")["npcs"]
pids = [p["id"] for p in npcs]
check(len(pids) == len(set(pids)), "npcs.json id 重复")
for p in npcs:
    check(p.get("name") and p.get("role") and p.get("function"), f"npcs {p.get('id')} 缺 name/role/function")

# ── ports.json war 表 ─────────────────────────────────
econ = open(os.path.join(ROOT, "scripts", "core", "Economy.gd"), encoding="utf-8").read()
ws = re.search(r'const WAR_STATUSES := \[(.*?)\]', econ, re.S)
statuses = set(re.findall(r'"([a-z]+)"', ws.group(1))) if ws else set()
check(len(statuses) >= 4, "Economy.WAR_STATUSES 解析失败")
for tbl in ("WAR_LABEL", "WAR_TARIFF", "WAR_INSPECTION"):
    m2 = re.search(r'const %s := \{(.*?)\}' % tbl, econ, re.S)
    keys = set(re.findall(r'"([a-z]+)":', m2.group(1))) if m2 else set()
    check(keys == statuses, f"Economy.{tbl} 键 {sorted(keys)} 与 WAR_STATUSES {sorted(statuses)} 不一致")
ports = load("ports.json")["ports"]
war_ports = 0
for p in ports:
    war = p.get("war")
    if war is None:
        continue
    war_ports += 1
    pid = p["id"]
    check(isinstance(war, dict) and war, f"ports {pid} war 须为非空对象")
    prev = ""
    for ym in war:
        check(DATE.match(ym) is not None, f"ports {pid} war 日期 `{ym}` 须为 YYYY-MM")
        check(war[ym] in statuses, f"ports {pid} war[{ym}]=`{war[ym]}` 不在 {sorted(statuses)}")
        check(1273 <= int(ym[:4]) <= 1279, f"ports {pid} war[{ym}] 年份超出 1273–1279")
    seq = list(war.items())
    for a, b in zip(seq, seq[1:]):
        check(a[0] < b[0], f"ports {pid} war 日期须升序：{a[0]} → {b[0]}")
        check(a[1] != b[1], f"ports {pid} war 相邻状态重复：{a[0]}/{b[0]} 都是 {a[1]}")
check(war_ports >= 8, f"ports.json 只有 {war_ports} 港有 war 表，1276 年闽粤沿海不应如此安静")
# 兴化 / 兴化海口是同一座城的两个节点，战况必须同步
xh = next((p for p in ports if p["id"] == "xinghua"), {}).get("war")
xhh = next((p for p in ports if p["id"] == "xinghua_harbor"), {}).get("war")
check(xh == xhh, "xinghua 与 xinghua_harbor 的 war 表须一致")
# war_notice：按节点覆写月初战况通告（Economy.on_month_changed 有就用、没有用通用句）。
# 键必须是本港 war 表里的节点（别处的月份不会翻牌、写了也不出），文案非空、不自带【战况】头（代码统一加）
notice_ports = 0
for p in ports:
    wn = p.get("war_notice")
    if wn is None:
        continue
    notice_ports += 1
    pid = p["id"]
    war = p.get("war") or {}
    check(isinstance(wn, dict) and wn, f"ports {pid} war_notice 须为非空对象")
    for ym, txt in (wn.items() if isinstance(wn, dict) else []):
        check(ym in war, f"ports {pid} war_notice[{ym}] 不是本港 war 表里的节点（{sorted(war)}），月初不会翻牌")
        check(isinstance(txt, str) and txt.strip() != "" and not txt.startswith("【"),
              f"ports {pid} war_notice[{ym}] 须为非空文案、不带【战况】头")
# 兴化 1277 秋是破城巷战、不是开门降：再陷那一节点城与海口都须覆写，且都不写「降元」（通用句对开城降的港口才对）。
# 城写城破；海口只写海口自己换旗，不重抄城里的首句——两条同一天连发，重抄读着像一件事记了两遍（09-29 复核）
_xh_fall2 = sorted(k for k, v in (xh or {}).items() if v == "fallen")[-1:] if xh else []
_xh_wn = next((p for p in ports if p["id"] == "xinghua"), {}).get("war_notice") or {}
_xhh_wn = next((p for p in ports if p["id"] == "xinghua_harbor"), {}).get("war_notice") or {}
for ym in _xh_fall2:
    check("城破" in _xh_wn.get(ym, "") and "降元" not in _xh_wn.get(ym, ""),
          f"ports xinghua war_notice[{ym}]（兴化再陷）须写城破、不写降元（现「{_xh_wn.get(ym, '')}」）")
    check("海口" in _xhh_wn.get(ym, "") and "换了旗" in _xhh_wn.get(ym, "") and "降元" not in _xhh_wn.get(ym, ""),
          f"ports xinghua_harbor war_notice[{ym}]（兴化再陷）须写海口换旗、不写降元（现「{_xhh_wn.get(ym, '')}」）")
# 城与海口同月都有覆写的节点：海口那条不重抄城里那条的首句
for ym in sorted(set(_xh_wn) & set(_xhh_wn)):
    _city_head = str(_xh_wn[ym]).split("。")[0]
    check(_city_head == "" or _city_head not in str(_xhh_wn[ym]),
          f"ports xinghua_harbor war_notice[{ym}] 重抄了城里那条的首句「{_city_head}」")
check(notice_ports >= 2, f"ports.json 只有 {notice_ports} 港有 war_notice，兴化与兴化海口的再陷通告须覆写")

# ── 守城卡路由完整 ─────────────────────────────────────
card_ids = set(re.findall(r'const (CARD_SIEGE_\w+) := "(\w+)"', main_src))
routed = set(re.findall(r'^\t\t(CARD_SIEGE_\w+):', main_src, re.M))
declared = {c[0] for c in card_ids}
check(declared, "Main.gd 未声明守城卡常量")
check(declared == routed, f"守城卡常量与 _on_siege_card 分支不一致：仅声明 {sorted(declared-routed)} 仅路由 {sorted(routed-declared)}")
for _n, v in card_ids:
    check(v.startswith("siege_"), f"守城卡 id `{v}` 须以 siege_ 开头（_on_facility_pressed 按前缀路由）")

# ── identity 三值都要可达且有归宿 ──────────────────────
gs_src = open(os.path.join(ROOT, "scripts", "GameState.gd"), encoding="utf-8").read()
assigned = set(re.findall(r'identity = "(\w+)"', gs_src))
check(IDENTITIES <= assigned, f"GameState 未赋值的身份：{sorted(IDENTITIES - assigned)}（死分支）")
# 每个身份在 Main 里都要有至少一处收束（结局卡 / 结局判定 / 等价旗标）
# scholar 的收束走 renamed_wenlong 旗标（守城与「未归」），不走 identity 比较
IDENT_MARKERS = {
    "scholar":  ['identity == "scholar"', 'has_flag("renamed_wenlong")'],
    "merchant": ['identity == "merchant"', 'identity != "scholar"'],
    "hometown": ['identity == "hometown"', 'identity != "scholar"'],
}
for ident in sorted(IDENTITIES):
    markers = IDENT_MARKERS.get(ident, [f'identity == "{ident}"'])
    check(any(has_tok(main_src, mk) for mk in markers),
          f"身份 {ident} 在 Main.gd 无任何收束分支（找过：{markers}）")

# ── GameState 存档字段对称 ─────────────────────────────
gs = open(os.path.join(ROOT, "scripts", "GameState.gd"), encoding="utf-8").read()
to_d = re.search(r"func to_dict\(\).*?\n\treturn \{(.*?)\n\t\}", gs, re.S)
from_d = re.search(r"func from_dict\(d: Dictionary\).*?(?=\n\nfunc |\Z)", gs, re.S)
if to_d and from_d:
    saved = set(re.findall(r'"([a-z_]+)":', to_d.group(1)))
    loaded = set(re.findall(r'(?<![A-Za-z_])d\.get\("([a-z_]+)"', from_d.group(0)))  # 只认 d.get，不把 saved.get 当成 d.get
    check(saved == loaded, f"GameState to_dict/from_dict 字段不对称：仅存 {sorted(saved-loaded)} 仅读 {sorted(loaded-saved)}")
else:
    check(False, "GameState.gd 未找到 to_dict/from_dict")

# ── 人物志 / 见面页上屏文本（第 1 轮评审 UX B1 / M1）──────────────
# characters.json 的 bio / bio_short 是设定集原稿，不上屏；上屏的字一律走 data/characters_codex.json。
# 凡会上屏的字段不许出现策划腔；每段按可见条件分级，段里写到的最晚年份不得晚于该段的可见年
# （0 段 = 开局即可见，只许写 1255 年及以前的事）。
CODEX_META = re.compile(r"本作|玩家|士人线|海商线|乡土线|暗线|性格锚|全作|选项|设定|第.章|月俸|可雇|雇到|结局|序章|终局|"
                        r"开局|一屏|结算|码头卡|三选一|这就是设计")
_ERA0 = {"宝庆": 1225, "绍定": 1228, "端平": 1234, "嘉熙": 1237, "淳祐": 1241, "宝祐": 1253, "开庆": 1259,
         "景定": 1260, "咸淳": 1265, "德祐": 1275, "景炎": 1276, "祥兴": 1278, "至元": 1264, "文永": 1264,
         "绍兴": 1131, "乾道": 1165, "淳熙": 1174, "隆兴": 1163, "宣和": 1119, "至治": 1321}
_CNN = {"元": 1, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}
START_YEAR = 1255
# 进度段（c1…c5）最早落在哪一年：序章走完仍在 1255，第二章起按云端 advance_years 2 / 3 / 4 累加，终局 1275 年十二月起
PHASE_YEAR = {1: 1255, 2: 1257, 3: 1260, 4: 1264, 5: 1275}


def _cn_n(s):
    if s in _CNN:
        return _CNN[s]
    if "十" in s:
        a, _, b = s.partition("十")
        return (_CNN.get(a, 1) if a else 1) * 10 + (_CNN.get(b, 0) if b else 0)
    return 1


def latest_year(text):
    ys = [int(y) for y in re.findall(r"(?<!\d)(1[1-3]\d\d)(?!\d)", text)]
    for era, n in re.findall(r"(" + "|".join(_ERA0) + r")([元一二三四五六七八九十]{1,3})年", text):
        ys.append(_ERA0[era] + _cn_n(n) - 1)
    for era in re.findall(r"(德祐|景炎|祥兴|咸淳|景定|开庆)(?![元一二三四五六七八九十])", text):
        ys.append(_ERA0[era])
    return max(ys) if ys else 0


# 可见条件的写法与 scripts/ui/CharacterArt.gd segment_visible 一一对应（09-28 visual 线扩键）：
#   0 / 公元年 / "YYYY-MM" / "c2"…"c5" / "end"；按世界线的 "end:结局|结局"、"id:身份|身份"、"flag:旗标|旗标"；
#   「&」连写、一截前加「!」取反。返回这一段最早可能露出的年份（写到的最晚年份不得晚于它），认不得返回 None。
# 结局名、身份、旗标都要真有：结局名取 Main.ENDING_BG 的键，旗标须在 scripts 里 set_flag 过或是 news.json 的 flag。
_YM = re.compile(r"^(1[1-3]\d\d)-(0[1-9]|1[0-2])$")
_IDS = {"scholar", "merchant", "hometown", "undecided"}
_eb = re.search(r"const ENDING_BG := \{(.*?)\n\}", main_src, re.S)
ENDINGS = set(re.findall(r'"([^"]+)":', _eb.group(1))) if _eb else set()
check(len(ENDINGS) >= 6, f"Main.ENDING_BG 只认出 {len(ENDINGS)} 个结局名，可见条件 end:… 无从核对")
_scripts_src = "\n".join(p.read_text(encoding="utf-8") for p in pathlib.Path(ROOT, "scripts").rglob("*.gd"))
KNOWN_FLAGS = set(re.findall(r'set_flag\("([a-z0-9_]+)"\)', _scripts_src))
KNOWN_FLAGS |= {str(n.get("flag")) for n in load("news.json").get("news", []) if n.get("flag")}
check("renamed_wenlong" in KNOWN_FLAGS, "旗标表里没有 renamed_wenlong，可见条件 flag:… 无从核对")


def cond_year(cond):
    if isinstance(cond, bool):
        return None
    if isinstance(cond, (int, float)):
        return max(int(cond), START_YEAR)
    if not isinstance(cond, str):
        return None
    s = cond.strip()
    if "&" in s:
        parts = s.split("&")
        ys = [cond_year(p) for p in parts]
        if any(p == "" for p in parts) or any(y is None for y in ys):
            return None
        return max(ys)
    if s.startswith("!"):
        # 取反没有时间下界：按一直可见算（写到的年份仍要靠同段别的截来担保）
        return None if cond_year(s[1:]) is None else START_YEAR
    if s == "end":
        return 99999
    if s.startswith("end:"):
        names = [x for x in s[4:].split("|") if x]
        return 99999 if names and all(x in ENDINGS for x in names) else None
    if s.startswith("id:"):
        ids = [x for x in s[3:].split("|") if x]
        return START_YEAR if ids and all(x in _IDS for x in ids) else None
    if s.startswith("flag:"):
        fl = [x for x in s[5:].split("|") if x]
        return START_YEAR if fl and all(x in KNOWN_FLAGS for x in fl) else None
    m = _YM.match(s)
    if m:
        return max(int(m.group(1)), START_YEAR)
    if s.startswith("c") and s[1:].isdigit():
        return PHASE_YEAR.get(int(s[1:]), 99999)
    if s.isdigit():
        return max(int(s), START_YEAR)
    return None


# 自证：新键认得、写错的认不得（结局名、身份、旗标拼错都要抓到）
for _c, _want in (("1277-11", 1277), ("1279-04", 1279), ("end:忠肃|未归", 99999), ("id:merchant|hometown", START_YEAR),
                  ("flag:renamed_wenlong", START_YEAR), ("1268&flag:renamed_wenlong", 1268), ("end&!end:忠肃", 99999),
                  ("c3&id:merchant|undecided", PHASE_YEAR[3]), (0, START_YEAR), (1276, 1276), ("c2", PHASE_YEAR[2]), ("end", 99999)):
    check(cond_year(_c) == _want, f"可见条件自证：{_c!r} 应认作 {_want}，实得 {cond_year(_c)}")
for _c in ("1277-13", "end:忠烈", "id:pirate", "flag:no_such_flag_xyz", "1268&", "&", "YYYY-MM", "!", "lately"):
    check(cond_year(_c) is None, f"可见条件自证：写错的 {_c!r} 应认不得，实得 {cond_year(_c)}")


chars_all = load("characters.json").get("characters", [])
codex_path = os.path.join(ROOT, "data", "characters_codex.json")
check(os.path.isfile(codex_path), "缺 data/characters_codex.json（人物志上屏文本层）")
codex = {}
if os.path.isfile(codex_path):
    try:
        codex = load("characters_codex.json").get("characters", {})
    except (ValueError, OSError) as e:
        check(False, f"characters_codex.json 解析失败：{e}")
codex_segs = 0
for c in chars_all:
    cid = c.get("id", "")
    e = codex.get(cid)
    check(isinstance(e, dict) and e.get("bio") and e.get("short"), f"人物志文本层缺 {cid} 的 bio / short")
    if not isinstance(e, dict):
        continue
    fields = {}
    for k in ("bio", "short", "lines", "title", "courtesy", "alt", "annal"):
        if k in e:
            fields[k] = e[k]
    if "alt" not in e:
        fields["alt"] = [[0, str(x)] for x in c.get("alt_names", [])]
    # 文本层没覆写的上屏字段：用设定集原稿，但同样查策划腔（原稿当作一直可见）
    for k in ("title", "courtesy"):
        if k not in e and c.get(k):
            fields[k] = [[0, str(c.get(k))]]
    if "lines" not in e:
        fields["lines"] = [[0, str(x)] for x in c.get("lines", [])]
    for k in ("look", "personality"):
        v = e.get(k, c.get(k, ""))
        if v:
            fields[k] = [[0, str(v)]]
    for k, segs in fields.items():
        check(isinstance(segs, list), f"{cid}.{k} 应为 [[可见条件, 文字], …]")
        if not isinstance(segs, list):
            continue
        for s in segs:
            ok = isinstance(s, list) and len(s) == 2 and isinstance(s[1], str)
            check(ok, f"{cid}.{k} 有一段不是 [可见条件, 文字]：{s!r}"[:120])
            if not ok:
                continue
            cy = cond_year(s[0])
            check(cy is not None, f"{cid}.{k} 可见条件无法识别：{s[0]!r}")
            txt = s[1]
            hit = CODEX_META.search(txt)
            check(hit is None, f"{cid}.{k} 上屏文字含策划腔「{hit.group(0) if hit else ''}」：{txt[:40]}")
            # 称谓（未识格也露）不许带「后为……」透底；原稿 title 里的由运行时截掉，文本层覆写的一律不许有
            check(not (k == "title" and k in e and "后为" in txt), f"{cid}.title 含「后为」透底：{txt[:40]}")
            ly = latest_year(txt)
            if cy is not None and cy < 99999 and ly > 0 and k != "look":
                check(ly <= cy, f"{cid}.{k} 一段写到 {ly} 年，却在 {cy} 年就可见：{txt[:40]}")
            codex_segs += 1
check(codex_segs >= 300, f"人物志文本层只有 {codex_segs} 段，疑似载入不全")
# 关系签的可见条件：键必须是设定集里真有的签，条件可识别
all_rels = {r.get("rel", "") for c in chars_all for r in c.get("relations", [])}
rel_from = load("characters_codex.json").get("rel_from", {}) if os.path.isfile(codex_path) else {}
for rk, rv in rel_from.items():
    check(rk in all_rels, f"characters_codex.rel_from 的「{rk}」不是设定集里的关系签")
    check(cond_year(rv) is not None, f"characters_codex.rel_from「{rk}」可见条件无法识别：{rv!r}")
# 上屏出口必须读文本层：人物志小传不再读 bio 原稿，见面页简介不再读 bio_short 原稿
codex_src = open(os.path.join(ROOT, "scripts", "ui", "CharacterCodex.gd"), encoding="utf-8").read()
art_src = open(os.path.join(ROOT, "scripts", "ui", "CharacterArt.gd"), encoding="utf-8").read()
check('get("bio"' not in codex_src and has_tok(codex_src, "codex_bio("), "人物志小传仍读 characters.json 的 bio 原稿")
# 见面页在 NpcPage（Lane main5 自 Main 拆出）：简介在那边读，Main 里也不许回头读原稿
npc_src = open(os.path.join(ROOT, "scripts", "ui", "NpcPage.gd"), encoding="utf-8").read()
check('"bio_short"' not in main_src and '"bio_short"' not in npc_src and has_tok(npc_src, "codex_short("),
      "见面页简介仍读 characters.json 的 bio_short 原稿")
check("characters_codex.json" in art_src, "CharacterArt 未接人物志上屏文本层")

# ── Astra L1：人物「原稿 vs 上屏」契约（docs/人物原稿与上屏契约.md）────────────
# characters.json 是设定集原稿，characters_codex.json 是上屏文本层。上屏的字只有三条来路：
#   ① 文本层 CODEX_ONSCREEN 各段；② 原稿里 UI 直读或文本层缺省时回落的 CHAR_ONSCREEN 字段、relations[].rel；
#   ③ 原稿 meta 的 attr_def / trait_def 的 name·desc 与 faction_def 的 name。
# 三条来路上出现 ONSCREEN_BAN 即失败；原稿 CHAR_DRAFT（bio / bio_short / 画像备注）与两份 meta.note 只供策划，不上屏。
# 新增字段必须先在这里归类，UI 直读的原稿键必须落在「上屏 / 结构」两类里，否则门禁失败。
ONSCREEN_BAN = re.compile(CODEX_META.pattern + r"|placeholder|TODO|WIP|FIXME|pipeline|LLM|ChatGPT|大模型")
CHAR_ONSCREEN = {"name", "alt_names", "courtesy", "title", "origin", "personality", "look", "lines"}
CHAR_STRUCT = {"id", "faction", "traits", "relations", "born", "died", "died_ym", "tier", "chapters", "attrs",
               "portrait", "portrait_before", "portrait_status", "sources", "historical"}  # 键、数值、枚举，不作正文上屏
CHAR_DRAFT = {"bio", "bio_short", "portrait_src", "portrait_note"}
CODEX_ONSCREEN = {"bio", "short", "lines", "title", "courtesy", "alt", "look", "personality", "annal"}
check(not (CHAR_ONSCREEN & CHAR_STRUCT or CHAR_ONSCREEN & CHAR_DRAFT or CHAR_STRUCT & CHAR_DRAFT), "L1 字段分类有交叠")


def onscreen_texts(chars_doc, codex_doc):
    """列出人物线全部上屏文字 (出处, 文字)。门禁与自证共用同一份清单。"""
    out = []
    meta = chars_doc.get("meta", {})
    for a in meta.get("attr_def", []):
        for k in ("name", "desc"):
            out.append((f"meta.attr_def.{a.get('key', '?')}.{k}", str(a.get(k, ""))))
    for tk, t in meta.get("trait_def", {}).items():
        for k in ("name", "desc"):
            out.append((f"meta.trait_def.{tk}.{k}", str(t.get(k, ""))))
    for fk, fd in meta.get("faction_def", {}).items():
        out.append((f"meta.faction_def.{fk}.name", str(fd.get("name", ""))))
    for c in chars_doc.get("characters", []):
        cid = c.get("id", "?")
        for k in sorted(CHAR_ONSCREEN):
            v = c.get(k)
            for i, s in enumerate(v if isinstance(v, list) else [v]):
                if s is not None:
                    out.append((f"characters.json {cid}.{k}[{i}]", str(s)))
        for r in c.get("relations", []):
            out.append((f"characters.json {cid}.relations→{r.get('id', '?')}", str(r.get("rel", ""))))
    for cid, e in codex_doc.get("characters", {}).items():
        for k in CODEX_ONSCREEN & set(e):
            segs = e[k]
            for i, s in enumerate(segs if isinstance(segs, list) else [segs]):
                txt = s[1] if isinstance(s, list) and len(s) == 2 else s
                out.append((f"characters_codex.json {cid}.{k}[{i}]", str(txt)))
    return out


def onscreen_hits(chars_doc, codex_doc):
    return [(w, m.group(0), t) for w, t in onscreen_texts(chars_doc, codex_doc) for m in [ONSCREEN_BAN.search(t)] if m]


_chars_doc = load("characters.json")
_codex_doc = load("characters_codex.json") if os.path.isfile(codex_path) else {"characters": {}}
for c in _chars_doc.get("characters", []):
    unk = set(c) - CHAR_ONSCREEN - CHAR_STRUCT - CHAR_DRAFT
    check(not unk, f"characters.json {c.get('id', '?')} 有未归类字段 {sorted(unk)}：先在 L1 契约里定上屏 / 结构 / 原稿")
    # died_ym（CharacterArt.died_known）：卒年从哪一月起写。须是 YYYY-MM、要有 died，年份落在卒年或次年
    if "died_ym" in c:
        _dm = _YM.match(str(c.get("died_ym", "")))
        _dd = c.get("died")
        check(_dm is not None and isinstance(_dd, int) and _dd <= int(_dm.group(1)) <= _dd + 1,
              f"characters.json {c.get('id', '?')} 的 died_ym {c.get('died_ym')!r} 须为卒年（{_dd}）或次年的 YYYY-MM")
for cid, e in _codex_doc.get("characters", {}).items():
    unk = set(e) - CODEX_ONSCREEN
    check(not unk, f"characters_codex.json {cid} 有未登记字段 {sorted(unk)}：上屏文本层字段须进 CODEX_ONSCREEN 受查")
_onscreen = onscreen_texts(_chars_doc, _codex_doc)
check(len(_onscreen) >= 1200, f"人物上屏文字只收到 {len(_onscreen)} 条，疑似清单漏载")
for where, word, txt in onscreen_hits(_chars_doc, _codex_doc):
    check(False, f"{where} 上屏字段含禁词「{word}」：{txt[:40]}")

# 自证：往每条来路各塞一个带记号的禁词，扫描必须逐条抓到那个记号（防止日后改清单时某条来路静默失明）
_PROBE = "placeholder·L1自证"
_probe_paths = []
if _chars_doc.get("characters") and _codex_doc.get("characters"):
    _x0 = next(iter(_codex_doc["characters"]))
    _probe_paths = [("attr", lambda cd, xd: cd["meta"]["attr_def"][0].__setitem__("desc", _PROBE)),
                    ("trait", lambda cd, xd: next(iter(cd["meta"]["trait_def"].values())).__setitem__("name", _PROBE)),
                    ("faction", lambda cd, xd: next(iter(cd["meta"]["faction_def"].values())).__setitem__("name", _PROBE)),
                    ("rel", lambda cd, xd: cd["characters"][0]["relations"].append({"id": "x", "rel": _PROBE}))]
    for k in sorted(CHAR_ONSCREEN):
        _probe_paths.append((f"raw.{k}", lambda cd, xd, k=k: cd["characters"][0].__setitem__(k, [_PROBE])))
    for k in sorted(CODEX_ONSCREEN):
        _probe_paths.append((f"codex.{k}", lambda cd, xd, k=k: xd["characters"][_x0].__setitem__(k, [[0, _PROBE]])))
for tag, poke in _probe_paths:
    cd, xd = copy.deepcopy(_chars_doc), copy.deepcopy(_codex_doc)
    poke(cd, xd)
    check(any(_PROBE in t for _, _, t in onscreen_hits(cd, xd)), f"L1 自证：往 {tag} 塞禁词后门禁没抓到，该上屏来路失明")
check(len(_probe_paths) >= 20, f"L1 自证只探了 {len(_probe_paths)} 条来路")
# 原稿兜底：设定集整份仍不许出现最硬的六个工程词（bio / bio_short 原稿亦然，防止回落时带出）
_CHARS_ENG = re.compile(r"placeholder|本作|玩家|士人线|海商线|乡土线")
_chars_raw = open(os.path.join(ROOT, "data", "characters.json"), encoding="utf-8").read()
_eng_hit = _CHARS_ENG.search(_chars_raw)
check(_eng_hit is None, f"characters.json 原稿仍含工程词「{_eng_hit.group(0) if _eng_hit else ''}」")

# UI 读取入口锁：凡拿人物字典直读的 .get("键")，键只许是「上屏 / 结构」两类；文本层 layer(ch).get 只许 CODEX_ONSCREEN
L1_UI_FILES = ["scripts/ui/CharacterArt.gd", "scripts/ui/CharacterCodex.gd", "scripts/ui/VisionStage.gd", "scripts/Main.gd",
               "scripts/ui/NpcPage.gd", "scripts/companions/CompanionPreview.gd"] + sorted(
    os.path.relpath(str(p), ROOT) for p in pathlib.Path(ROOT, "scripts", "chars").glob("*.gd"))
_ui_raw_keys = 0
for rel in L1_UI_FILES:
    p = os.path.join(ROOT, rel)
    check(os.path.isfile(p), f"L1 上屏入口 {rel} 不见了：改了路径须同步契约")
    if not os.path.isfile(p):
        continue
    src = open(p, encoding="utf-8").read()
    for k in re.findall(r'(?<![A-Za-z_])(?:ch|cch|other|character)\.get\("([a-z_]+)"', src):
        _ui_raw_keys += 1
        check(k in CHAR_ONSCREEN | CHAR_STRUCT, f"{rel} 直读人物原稿字段「{k}」：不在 L1 上屏 / 结构白名单")
    for k in re.findall(r'layer\([^)]*\)\.get\("([a-z_]+)"', src):
        check(k in CODEX_ONSCREEN, f"{rel} 读文本层未登记字段「{k}」：须进 CODEX_ONSCREEN 受查")
    for k in re.findall(r'character_meta\(\)\.get\("([a-z_]+)"', src):
        check(k in {"attr_def", "trait_def", "faction_def"}, f"{rel} 读设定集 meta.{k}：meta 只许三张定义表上屏")
    check(re.search(r'"bio_short"|"portrait_note"|"portrait_src"', src) is None,
          f"{rel} 出现原稿专用键（bio_short / portrait_note / portrait_src）")
check(_ui_raw_keys >= 40, f"L1 只扫到 {_ui_raw_keys} 处人物字典直读，疑似正则失效")
# CharacterArt / CharacterCodex / Main 上屏路径：bio 原稿不得经 get("bio") / bio_short 直出
check(has_tok(art_src, "codex_bio(") or has_tok(codex_src, "codex_bio("), "上屏层未走 CharacterArt.codex_bio")
check(has_tok(art_src, "codex_short(") or has_tok(main_src, "codex_short("), "上屏层未走 CharacterArt.codex_short")
# 禁止 UI 脚本直接 FileAccess 打开 characters.json 的 bio 字段上屏（VisionStage 只取立绘允许）
_vs_path = os.path.join(ROOT, "scripts", "ui", "VisionStage.gd")
if os.path.isfile(_vs_path):
    _vs = open(_vs_path, encoding="utf-8").read()
    check('get("bio"' not in _vs, "VisionStage 疑似把 characters.json bio 送到控件")
# 人物志与见面页不得出现「直接读 GameManager.characters[*].bio」类路径
check('["bio"]' not in codex_src and ".bio_short" not in codex_src,
      "CharacterCodex 仍直接读 bio/bio_short 原稿字段")

# ── Astra L1b：人物原稿读取入口锁（docs/人物原稿与上屏契约.md §读取入口）────────────
# 上面那段只查「已知几个 UI 文件读了哪些键」；新脚本绕过它直接开 characters.json、或自己调 GameManager 取数口
# 把原稿送上屏，上面一条都不会响。这里把入口锁成清单：
#   ① 全仓 .gd / .py / .tscn / .tres（去注释）里凡是 raw（characters.json 路径 / CHARACTERS_PATH / characters_data）、
#      codex（characters_codex.json / CODEX_PATH）、api（get_character / character_for_npc / character_for_crew /
#      all_characters / character_meta）三类读取，文件必须登记在 L1B_READERS，且实际读取类别与登记一字不差
#      （多读即越权，少读即清单过宽，都失败）；开发工具可读原稿，但正式流程（scripts/ scenes/ project.godot）不得引用它们。
#   ② 上屏字段锁：运行时入口（L1_UI_FILES ∪ 清单里 scripts/ 下的文件）按变量追踪人物字典——ch / cch / other / character、
#      由取数口赋值的变量、遍历 all_characters() 的循环变量；对它们的 .get("键") / ["键"] / .键 以及取数口链式读取，
#      键只许 CHAR_ONSCREEN | CHAR_STRUCT；动态键、整份 keys() / values() / str() / stringify 一律失败（门禁无法核对）。
#      清单外的 scripts/ 文件拿 ch / cch / character 读人物专有键，同样失败（没登记就在读人物字典）。
#   ③ 自证：往扫描器喂合成源码，六种越界写法必须逐条判红、两种合法写法必须判绿。
L1B_READERS = {  # 路径: (读取类别, 身份, 为什么许它读)
    "scripts/GameManager.gd": ({"raw", "api"}, "runtime", "原稿唯一运行时加载器：建索引，对外只给取数口"),
    "scripts/ui/CharacterArt.gd": ({"codex", "api"}, "runtime", "文本层唯一加载器；立绘 / 五维 / 特技 / 称谓取数"),
    "scripts/ui/CharacterCodex.gd": ({"api"}, "runtime", "人物志：列表、关系、小传（小传走 codex_bio）"),
    "scripts/Main.gd": ({"api"}, "runtime", "岸带人物志钮（all_characters；标题页人物志钮、见面页 / 酒馆募人卡已拆去 TitlePage / NpcPage / TavernPage）"),
    "scripts/ui/LedgerPage.gd": ({"api"}, "runtime", "船籍簿职事小头像（character_for_crew；Lane mz 自 Main 拆出）"),
    "scripts/ui/TavernPage.gd": ({"api"}, "runtime", "酒馆募人卡：在船 / 候选人物卡（character_for_crew；Lane main4 自 Main 拆出）"),
    "scripts/ui/NpcPage.gd": ({"api"}, "runtime", "见面页立绘 / 人物栏、设施页在侧人物卡（character_for_npc；Lane main5 自 Main 拆出）"),
    "scripts/ui/TitlePage.gd": ({"api"}, "runtime", "卷首标题页「人物志」钮显隐（all_characters；Lane main11 自 Main 拆出）"),
    "scripts/ui/VisionStage.gd": ({"raw", "api"}, "runtime", "异象幕：先走取数口，GameManager 缺席（单跑场景）才兜底直读；只取 id"),
    "scripts/companions/CompanionPreview.gd": ({"api"}, "runtime", "同伴预览立绘"),
    "scripts/chars/CharRoster.gd": ({"api"}, "runtime", "人物名册"),
    "scripts/chars/CharsDemo.gd": ({"api"}, "runtime", "人物演示场"),
    "scripts/chars/CharsShoreOverlay.gd": ({"api"}, "runtime", "岸上人物叠层"),
    "scripts/core/SaveLoad.gd": ({"api"}, "runtime", "存档迁移 v2→v3 回填人物志已识：职事候选 id → 人物 id（character_for_crew，只取 id；lane fx6）"),
    "tools/CharsDemo.gd": ({"api"}, "dev", "w26-k2 薄包装：extends scripts/chars/CharsDemo.gd 继承运行线真身，以 dev 身份走同一人物数据（GameManager 取数口）做接线自证，不进 scripts/ 不被 scenes/ project.godot 引用（开发工具，不进正式流程）"),
    "tools/art/ShotTour.gd": ({"raw", "api"}, "dev", "美术巡检截图（开发工具，不进正式流程）"),
    "tools/art/ThemePreview.gd": ({"raw"}, "dev", "主题预览，编辑器下读 portrait_src 找原画（开发工具）"),
    "tools/art/portrait_svg/PortraitWall.gd": ({"raw"}, "dev", "立绘墙（开发工具）"),
    "tools/art/build_portraits.py": ({"raw"}, "dev", "立绘产线：按原稿 portrait / portrait_src 出图"),
    "tools/art/subset_fonts.py": ({"raw"}, "dev", "字库子集：收全部人物文字的字形"),
    "tools/verify_story_data.py": ({"raw", "codex", "api"}, "gate", "本门禁（自证合成源码里写着取数口）"),
    "tools/check_symbols.py": ({"raw", "codex"}, "gate", "L1 工程词 / 展示入口契约"),
    "tools/check_assets.py": ({"raw"}, "gate", "立绘资源存在性"),
    "tools/check_data_family.py": ({"raw"}, "gate", "data/ 同族结构门禁：普查 data/*.json 的 id 表 / 自引用（characters.json 是候选、登 not_family），变异自证改它验不误红；不上屏"),
    "tools/check_char_contract_doc.py": ({"raw"}, "gate", "（lane w26-k3）契约文档「每档角色 / 品级一览」自核：对原稿与这份文档做逐字比对，只生成文档表、不上屏；不向 UI 供字"),
    "tools/godot_smoke.gd": ({"raw", "api"}, "gate", "冒烟：阵营表、见面页立绘"),
    "tools/godot_story_check.gd": ({"api"}, "gate", "剧情门禁：生卒一行（主角卒年只在「忠肃」写、卒年到次年才写），实建人物志 / 立绘面板 / 见面页看上屏字"),
}
_L1B_KIND_RE = {
    "raw": re.compile(r"characters\.json|\bCHARACTERS_PATH\b|\bcharacters_data\b"),
    "codex": re.compile(r"characters_codex\.json|\bCODEX_PATH\b"),
    "api": re.compile(r"\b(?:get_character|character_for_npc|character_for_crew|all_characters|character_meta)\s*\(|"
                      r"[\"'](?:get_character|character_for_npc|character_for_crew|all_characters|character_meta)[\"']"),
}
_L1B_ACC = r"(?:get_character|character_for_npc|character_for_crew|_resolve_character)\s*\("
_L1B_SPECIFIC = {"alt_names", "courtesy", "tier", "attrs", "traits", "portrait", "portrait_status"} | CHAR_DRAFT - {"bio"}


def _l1b_strip(src):
    """去掉 # 注释（GDScript / Python 同法），字符串原样保留；单行串遇换行即收，防一个孤引号吞掉后文。"""
    out, i, n, q = [], 0, len(src), None
    while i < n:
        c = src[i]
        if q:
            if c == "\\":
                out.append(src[i:i + 2]); i += 2; continue
            if src.startswith(q, i):
                out.append(q); i += len(q); q = None; continue
            if c == "\n" and len(q) == 1:
                q = None
            out.append(c); i += 1; continue
        if c == "#":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if c in "\"'":
            q = src[i:i + 3] if src[i:i + 3] in ('"""', "'''") else c
            out.append(q); i += len(q); continue
        out.append(c); i += 1
    return "".join(out)


def _l1b_code(rel, src):
    return _l1b_strip(src) if rel.endswith((".gd", ".py")) else src


def _l1b_kinds(code):
    return {k for k, r in _L1B_KIND_RE.items() if r.search(code)}


def _l1b_char_vars(code):
    names = {"ch", "cch", "other", "character"}
    names |= set(re.findall(r"\bvar\s+([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?:?=\s*(?:[\w.]+\.)?" + _L1B_ACC, code))
    names |= set(re.findall(r"(?m)^\s*([A-Za-z_]\w*)\s*=\s*(?:[\w.]+\.)?" + _L1B_ACC, code))
    lists = set(re.findall(r"\bvar\s+([A-Za-z_]\w*)\s*(?::\s*[\w\[\]]+\s*)?:?=\s*(?:[\w.]+\.)?all_characters\s*\(", code))
    for v, it in re.findall(r"\bfor\s+([A-Za-z_]\w*)(?:\s*:\s*\w+)?\s+in\s+([^\n]*?):\s*$", code, re.M):
        if re.search(r"\ball_characters\s*\(", it) or it.strip() in lists:
            names.add(v)
    return names


def _l1b_field_problems(rel, code):
    """运行时上屏入口：对人物字典读到的键 → [(键或写法, 出错说明)]；另回读取次数供防失明。"""
    out, reads = [], 0
    alt = "|".join(sorted(_l1b_char_vars(code)))
    recv = r"(?<![\w.])(?:" + alt + r")"
    for m in re.finditer(recv + r"\s*(?:\.get\(\s*\"(\w+)\"|\[\s*\"(\w+)\"\s*\]|\.([a-z_]\w*)\b(?!\s*\())", code):
        k = m.group(1) or m.group(2) or m.group(3)
        reads += 1
        if k not in CHAR_ONSCREEN | CHAR_STRUCT:
            out.append((k, f"{rel} 读人物字典「{m.group(0).strip()}」：键「{k}」不在 L1 上屏 / 结构白名单"))
    for m in re.finditer(_L1B_ACC + r"[^()\n]*\)\s*(?:\.get\(\s*\"(\w+)\"|\[\s*\"(\w+)\"\s*\]|\.([a-z_]\w*)\b(?!\s*\())", code):
        k = m.group(1) or m.group(2) or m.group(3)
        reads += 1
        if k not in CHAR_ONSCREEN | CHAR_STRUCT:
            out.append((k, f"{rel} 取数口链式读「{m.group(0).strip()}」：键「{k}」不在 L1 上屏 / 结构白名单"))
    for m in re.finditer(recv + r"\s*(?:\.get\(\s*(?![\s\"])|\[\s*(?![\s\"\]]))", code):
        out.append(("<动态键>", f"{rel} 以动态键读人物字典「{m.group(0).strip()}…」：门禁无法核对，改写成字面键"))
    for m in re.finditer(recv + r"\s*\.(?:keys|values)\s*\(|(?:\bstr|stringify)\(\s*(?:" + alt + r")\s*\)", code):
        out.append(("<整份>", f"{rel} 整份倒出人物字典「{m.group(0).strip()}」：原稿字段会跟着上屏"))
    return out, reads


def _l1b_scan_file(rel, src, field_files, listed):
    """单个文件的入口 / 字段问题 → [(类别, 说明)]；自证与真仓共用。"""
    code = _l1b_code(rel, src)
    probs = []
    kinds = _l1b_kinds(code)
    if rel in listed:
        want = listed[rel][0]
        if kinds - want:
            probs.append(("entry", f"{rel} 越权读人物数据 {sorted(kinds - want)}（清单只许 {sorted(want)}）"))
        if not kinds:
            probs.append(("stale", f"{rel} 已不读人物数据，却仍登记在 L1B_READERS：从清单删去"))
        elif want - kinds:
            probs.append(("stale", f"{rel} 登记了 {sorted(want - kinds)} 却已不读：清单收窄到 {sorted(kinds)}"))
    elif kinds:
        probs.append(("entry", f"{rel} 不在 L1B 读取入口清单却读人物数据 {sorted(kinds)}：原稿只许经清单里的入口，上屏走文本层"))
    reads = 0
    if rel in field_files:
        fp, reads = _l1b_field_problems(rel, code)
        probs += [("field", msg) for _, msg in fp]
    elif rel.startswith("scripts/") and rel.endswith(".gd"):
        for k in re.findall(r"(?<![\w.])(?:ch|cch|character)\s*(?:\.get\(\s*\"(\w+)\"|\[\s*\"(\w+)\"\s*\])", code):
            k = k[0] or k[1]
            if k in _L1B_SPECIFIC:
                probs.append(("field", f"{rel} 未登记为上屏入口，却在读人物字典专有键「{k}」：先进 L1B_READERS / L1_UI_FILES"))
    return probs, reads


_l1b_skip = {".git", ".godot", "__pycache__"}
_L1B_SUFFIX = (".gd", ".py", ".tscn", ".tres")


def _l1b_list(root):
    """L1B 扫描集：只认 git 已跟踪（含已暂存）的文件，工作树里未跟踪 / 被忽略的 tools/verify_* 探针不扫
    （lane w19-g11：原先 rglob 全盘，放着探针就 FAIL，各线只能跑门禁前挪开）。已跟踪却在工作树删了的跳过。
    没 git（不在仓库 / PATH 里没有）时退回扫盘并印一行 ⚠，退出码不因此变。"""
    import subprocess
    try:
        out = subprocess.run(["git", "ls-files", "-z"], cwd=root, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, check=True).stdout.decode("utf-8")
        rels = [r for r in out.split("\0") if r]
    except (OSError, subprocess.CalledProcessError):
        print("⚠ L1B：取不到 git ls-files，退回扫盘（未跟踪的探针也会扫到）")
        rels = [p.relative_to(root).as_posix() for p in pathlib.Path(root).rglob("*")]
    return sorted(r for r in rels if r.endswith(_L1B_SUFFIX) and not (_l1b_skip & set(r.split("/")))
                  and os.path.isfile(os.path.join(root, r)))


_l1b_files = {rel: pathlib.Path(ROOT, rel).read_text(encoding="utf-8", errors="replace") for rel in _l1b_list(ROOT)}
L1B_FIELD_FILES = set(L1_UI_FILES) | {r for r, v in L1B_READERS.items() if v[1] == "runtime"}
for rel in sorted(L1B_READERS):
    check(rel in _l1b_files, f"L1B 读取入口 {rel} 不见了：改了路径须同步 L1B_READERS")
_l1b_found, _l1b_reads = {}, 0
for rel, src in sorted(_l1b_files.items()):
    kinds = _l1b_kinds(_l1b_code(rel, src))
    if kinds:
        _l1b_found[rel] = kinds
    probs, n = _l1b_scan_file(rel, src, L1B_FIELD_FILES, L1B_READERS)
    _l1b_reads += n
    for _, msg in probs:
        check(False, msg)
check(len(_l1b_found) >= 15, f"L1B 只扫到 {len(_l1b_found)} 个人物数据读取点，疑似扫描失明")
check(_l1b_reads >= 40, f"L1B 运行时入口只追到 {_l1b_reads} 处人物字典读取，疑似变量追踪失效")
check(sum(1 for v in L1B_READERS.values() if "raw" in v[0] and v[1] == "runtime") <= 2,
      "L1B：运行时直读原稿的入口超过 GameManager + VisionStage 兜底两处")
# 开发工具可读原稿，但正式流程不得引用（否则原稿经工具脚本上屏）
_l1b_prod = "\n".join(src for rel, src in _l1b_files.items() if rel.startswith(("scripts/", "scenes/")))
_l1b_prod += open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
for rel, (_, role, _) in L1B_READERS.items():
    if role != "runtime":
        check(("res://" + rel) not in _l1b_prod, f"正式流程引用了只许开发 / 门禁用的原稿读取者 {rel}")

# 自证：非白名单直读 / 非白名单取数 / 白名单读 bio 原稿 / 链式读原稿 / 循环变量读原稿 / 动态键——必须逐条判红
_l1b_red = [
    ("entry", "scripts/ui/EvilPanel.gd", 'func f():\n\tvar s := FileAccess.get_file_as_string("res://data/characters.json")\n'),
    ("entry", "scripts/ui/EvilPanel.gd", 'func f(id):\n\tlbl.text = str(GameManager.get_character(id).get("name", ""))\n'),
    ("entry", "scenes/Evil.tscn", '[sub_resource type="GDScript"]\nscript/source = "var d = GameManager.characters_data"\n'),
    ("field", "scripts/Main.gd", 'func f(id):\n\tvar p: Dictionary = GameManager.get_character(id)\n\tlbl.text = p.get("bio", "")\n'),
    ("field", "scripts/Main.gd", 'func f(id):\n\tlbl.text = GameManager.character_for_npc(id).get("portrait_note", "")\n'),
    ("field", "scripts/ui/CharacterCodex.gd", 'func f():\n\tfor who in GameManager.all_characters():\n\t\tlbl.text = who["bio_short"]\n'),
    ("field", "scripts/ui/CharacterCodex.gd", 'func f(k):\n\tlbl.text = str(ch.get(k, ""))\n'),
    ("field", "scripts/ui/CharacterArt.gd", 'func f():\n\tlbl.text = ch.bio\n'),
    ("field", "scripts/ui/NewCard.gd", 'func f(ch):\n\tlbl.text = ch.get("portrait_src", "")\n'),
]
for want, rel, src in _l1b_red:
    got = {kind for kind, _ in _l1b_scan_file(rel, src, L1B_FIELD_FILES, {r: v for r, v in L1B_READERS.items() if r != rel})[0]}
    check(want in got, f"L1B 自证：{rel} 合成越界（{src.strip().splitlines()[-1].strip()}）门禁没判红")
_l1b_green = [
    ("scripts/ui/Note.gd", '# 立绘以 characters.json 的 portrait 为准；GameManager.get_character(id) 只在注释里\nfunc f():\n\tpass\n'),
    ("scripts/Main.gd", 'func f(id):\n\tvar ch: Dictionary = GameManager.character_for_npc(id)\n\tlbl.text = Art.codex_short(ch) + str(ch.get("name", ""))\n'),
]
for rel, src in _l1b_green:
    got = [msg for _, msg in _l1b_scan_file(rel, src, L1B_FIELD_FILES, {"scripts/Main.gd": ({"api"}, "runtime", "")})[0]]
    check(not got, f"L1B 自证：合法写法被误判 {got[:1]}")

# 上屏的场景文字（标题、正文、选项、调查项、speaker）引号一律用「」『』，不用 “” ‘’（第 2 轮 UX M7：
# 人物志、册页、见面页、过场全用「」，只有 scenes.json 混着西式引号）。deprecated 场景不上屏，不查。
# 序章正文不得点破主角结局（岳王庙、孤城、改名陈文龙）与现代腔（世界地图的迷雾、命运的指针、宏大沙盘）。
PROLOGUE_SPOIL = re.compile(r"岳王庙|兵不满千|孤城|改名为陈文龙|世界地图的迷雾|命运的指针|宏大沙盘")
def _scene_texts(s):
    for k in ("title", "cg_title", "cg_sub", "body", "speaker"):
        v = s.get(k)
        if isinstance(v, str):
            yield k, v
    for c in s.get("choices", []) or []:
        if isinstance(c, dict) and isinstance(c.get("label"), str):
            yield "choice", c["label"]
    for inv in s.get("investigations", []) or []:
        if isinstance(inv, dict):
            for k in ("label", "text"):
                if isinstance(inv.get(k), str):
                    yield "inv." + k, inv[k]
    for k in ("lines",):
        for v in s.get(k, []) or []:
            if isinstance(v, str):
                yield k, v
bad_quotes = 0
for s in scenes:
    if s.get("deprecated"):
        continue
    for k, v in _scene_texts(s):
        if any(q in v for q in "“”‘’"):
            bad_quotes += 1
            check(False, f"scenes.json {s.get('id')}.{k} 用了西式引号：{v[:40]}")
        if s.get("chapter") == "prologue" or str(s.get("id", "")).startswith("cg_") or s.get("id") == "start":
            hit = PROLOGUE_SPOIL.search(v)
            check(hit is None, f"scenes.json {s.get('id')}.{k} 序章文字剧透 / 现代腔「{hit.group(0) if hit else ''}」")

# 序章史实校勘必修 5 处（docs/剧情打磨_序章与终局_2026-09-04.md §一）：小暑与三月开局矛盾、1255 年襄阳未战、
# 丁大全 1258 才拜相、蒙哥南征非「大捷」、青瓷当私盐抄不通、陈文龙非绞刑、「新大陆」现代词——锁住不回退。
# cg_world_north / cg_decision 已按后续稿重写（改后原句含「孤城 / 岳王庙」，与上面的剧透禁词冲突），只查不回退旧写法。
# （lane w20-b5）**按幕 id 登记**：锁的是「校勘定的是哪一幕的那句」——挪到别幕即另一事件，改幕名须随本表。
PROLOGUE_HISTORY_OLD = re.compile(r"小暑|襄阳|汉水|排斥异己|大捷|当私盐抄|绞索|新大陆")
PROLOGUE_HISTORY_KEEP = {
    "cg_narrate_table": "三月，春雷，暴雨将至",
    "cg_veteran_3": "大理去岁也叫鞑子拿了，下一步就是绕到咱们背后来",
    "cg_world_north": "宦官董宋臣",
    "cg_ana_speak_3": "箱底垫的是什么，市舶司不问也知道",
    "cg_decision": "没有官图的海",
}
_scene_by_id = {s.get("id"): s for s in scenes}
for sid, keep in PROLOGUE_HISTORY_KEEP.items():
    s = _scene_by_id.get(sid)
    check(s is not None, f"scenes.json 缺序章场景 {sid}")
    if s is None:
        continue
    texts = [v for _, v in _scene_texts(s)] + [s.get("objective") or ""]
    check(any(keep in v for v in texts), f"scenes.json {sid} 史实校勘改后文字丢失：{keep}")
    for v in texts:
        hit = PROLOGUE_HISTORY_OLD.search(v)
        check(hit is None, f"scenes.json {sid} 回退到史实校勘前写法「{hit.group(0) if hit else ''}」")

# 序章史实校勘建议 6–7（Q11）：阿那进场是赤脚踩水不是木屐（读者第一反应是日本）；南宋无「路试」，
# 士人线入口是 1256 临安太学补试。只锁这两处正文；#8 家丁「明年丙辰大考」口吻允许不准确，不查。
# （lane w20-b5）**按幕 id 登记**：同 PROLOGUE_HISTORY_KEEP ——锁的是那一幕的那一句，不是任何幕出现这句话。
PROLOGUE_SUGGEST = {
    "cg_ana_enter": ("赤脚踩水的啪啪声", re.compile(r"木屐")),
    "scholar_path_start": ("临安太学补试是第一步", re.compile(r"福州路试")),
}
for sid, (keep, old) in PROLOGUE_SUGGEST.items():
    body = (_scene_by_id.get(sid) or {}).get("body") or ""
    check(keep in body, f"scenes.json {sid}.body 史实校勘建议改后文字丢失：{keep}")
    hit = old.search(body)
    check(hit is None, f"scenes.json {sid}.body 回退到史实校勘建议前写法「{hit.group(0) if hit else ''}」")

# 序章长文去现代腔（Q5）：开卷、四方沙盘、酒棚各幕与旧 prologue_* 长文（含 deprecated，防复活时带回）
# 不得再写「新大陆 / 崭新大陆 / 历史车轮 / 绞索 / 注定要砸下来的孤城」，开局是三月春雷，不得出现小暑。
PROLOGUE_MODERN = re.compile(r"新大陆|历史车轮|绞索|注定要砸|小暑")
for s in scenes:
    sid = str(s.get("id", ""))
    if not (s.get("chapter") == "prologue" or sid.startswith(("cg_", "prologue_")) or sid == "start"):
        continue
    for k, v in list(_scene_texts(s)) + [("objective", s.get("objective") or "")]:
        hit = PROLOGUE_MODERN.search(v)
        check(hit is None, f"scenes.json {sid}.{k} 序章现代腔 / 开局季节矛盾「{hit.group(0) if hit else ''}」")

# 场景文案二轮去现代腔（lane seq1 / seq2）：全文件非 deprecated 场景的全部上屏字段（_scene_texts 之外还有
# objective、result、设施 title / subtitle / body、调查项）不得回退到已改掉的现代 / 工程 / 外来词与存疑判改项
# （大马士革 1255 非大食都城、拔锚→解缆、罗盘→针盘、船厂→船场、福州的贡院、南宋无路试），不得有西式引号，
# 标题分隔号只用「・」。lane seq3 收口 seq2 留的镜像句：林阿舶「中继路」→「半程的水路」、商长「按照大宋律例」→
# 「依大宋律」（characters.json lines 同步改，镜像见下方 SEQ3_MIRRORS）；1255 年襄阳无战，city_tavern「溃兵讲襄阳的仗」→
# 蜀口、yangji_yuan 改写成二十年前（端平三年）襄阳城破逃来的人。
SCENE_MODERN = re.compile(
    r"期票|单方面|违约|路径入口|海商路径|网络|中继|证据|样本|交付成果|风险|防波堤|羊皮纸|催款单|通行证|"
    r"接头人|瞬间凝固|战局|科考|税率表|文书训练|沉默本身|对你而言|这个时代|人生|点触|点击|"
    r"大马士革|拔锚|罗盘|船厂|福州的贡院|路试|番商|番文|蝉声|按照大宋律例|襄阳的仗|讲襄阳逃来"
)
def _scene_onscreen(s):
    yield from _scene_texts(s)
    for k in ("objective",):
        if isinstance(s.get(k), str):
            yield k, s[k]
    res = s.get("result")
    for i, v in enumerate(res if isinstance(res, list) else [res]):
        if isinstance(v, str):
            yield f"result[{i}]", v
    for i, fac in enumerate(s.get("facilities", []) or []):
        for k in ("title", "subtitle", "body"):
            if isinstance(fac, dict) and isinstance(fac.get(k), str):
                yield f"facilities[{i}].{k}", fac[k]
    for o in s.get("options", []) or []:
        if isinstance(o, dict) and isinstance(o.get("label"), str):
            yield "option", o["label"]
def _scene_modern_hits(s):
    out = []
    for k, v in _scene_onscreen(s):
        hit = SCENE_MODERN.search(v)
        if hit:
            out.append(f"scenes.json {s.get('id')}.{k} 回退到现代腔 / 已判改写法「{hit.group(0)}」")
        if any(q in v for q in "\"“”‘’"):
            out.append(f"scenes.json {s.get('id')}.{k} 用了西式引号：{v[:40]}")
    t = s.get("title")
    if isinstance(t, str) and ("·" in t or " " in t):
        out.append(f"scenes.json {s.get('id')}.title 分隔号须用「・」，不用「·」或半角空格：{t}")
    return out
for s in scenes:
    if not s.get("deprecated"):
        for msg in _scene_modern_hits(s):
            check(False, msg)
# 自证：每条上屏来路各塞一个禁词，扫描须逐条抓到（防日后改 _scene_onscreen 时某条来路静默失明）
for tag, probe in (("body", {"body": "寺社网络"}), ("objective", {"objective": "科举路径入口"}),
                   ("result[]", {"result": ["", "羊皮纸"]}), ("result", {"result": "税率表"}),
                   ("facility", {"facilities": [{"body": "船厂"}]}), ("inv", {"investigations": [{"text": "瞬间凝固"}]}),
                   ("choice", {"choices": [{"label": "拔锚"}]}), ("option", {"options": [{"label": "点击"}]}),
                   ("quote", {"result": ["“陈公子”"]}), ("title", {"title": "兴化海口 · 酒棚"})):
    check(bool(_scene_modern_hits(dict(probe, id="_probe"))), f"SCENE_MODERN 自证：往 {tag} 塞禁词后门禁没抓到，该上屏来路失明")

# lane seq3：seq2 留下的镜像句两头一起改，此后两头必须逐字同在；旧写法在 scenes.json 之外的出处（人物原稿 / 文本层 /
# 职事表 / 航程旁白）也不许回来。SCENE_MODERN 只扫 scenes.json，这里补上镜像与场外四处。
# （lane w20-b5，两张表判法与下方「──── 结构门禁登记表口径 ────」同段）：
#   键（镜像句原文、包装禁词、文件行禁词） = 内容本身 —— **按内容登记**，文本改名则本条整行删 / 整行改；
#   SEQ3_MIRRORS 的「characters 收句人」按台词反查（不登 id，不随改名）、「scenes 落幕」仍**按幕 id**——
#   镜像合同写的是「这两处具体产品」要逐字同在，落幕是审计锚、不是形状锚（判法见下段口径②）。
SEQ3_MIRRORS = {  # 镜像句 → (characters 收句人 —— 只做存在性自查, scenes 落幕 id —— 跟随改幕名)
    "这趟先验半程的水路。货不能潮，信不能皱。": ("merchant_lin", "merchant"),
    "依大宋律，同居共财，这笔债自然落到了你的名下。": ("guild_head", "prologue_ledger"),
}
_chars = load("characters.json").get("characters", [])

def _mirror_owner(line, chars):
    return [str(ch.get("id")) for ch in chars if line in (ch.get("lines") or [])]

def _mirror_scenes(line, scs):
    return [str(x.get("id")) for x in scs if any(line in v for _, v in _scene_onscreen(x))]

for line, (cid_expect, sid_expect) in SEQ3_MIRRORS.items():
    check(line in [ln for ch in _chars for ln in ch.get("lines", []) or []],
          f"characters.json lines 里找不到镜像句「{line}」（lane seq3 与 scenes.json {sid_expect} 同步改的）")
    own = _mirror_owner(line, _chars)
    check(len(own) == 1 and own[0] == cid_expect,
          f"镜像句「{line}」的 characters.json 收句人须恰为 `{cid_expect}` 一位（实为 {sorted(own)}；"
          f"改名该人物不动本表，删句即删行）")
    hits = _mirror_scenes(line, scenes)
    check(hits == [sid_expect],
          f"镜像句「{line}」在 scenes.json 的上屏出现须恰落 `{sid_expect}` 一幕（实为 {sorted(hits)}；"
          "落幕 id 属 SEQ3 镜像登记的审计锚（**按幕 id 登记**、口径见 file head②），改幕名跟随此列；"
          "若他幕也要上这一句，在本表另起一行）")

_SEQ3_MIRROR_SELF = {  # 自证两项：误植收句人 / 误植第二落幕均须被上面 checks 抓出
    "误植 characters 次收句人": lambda: len(_mirror_owner("这趟先验半程的水路。货不能潮，信不能皱。",
        list(_chars) + [{"id": "_probe_ch", "lines": ["这趟先验半程的水路。货不能潮，信不能皱。"]}])) != 1,
    "误植 scenes 第二落幕": lambda: _mirror_scenes("依大宋律，同居共财，这笔债自然落到了你的名下。",
        list(scenes) + [{"id": "_probe_sc", "body": "依大宋律，同居共财，这笔债自然落到了你的名下。"}]) != ["prologue_ledger"],
}
for tag, probe in _SEQ3_MIRROR_SELF.items():
    check(probe(), f"SEQ3_MIRRORS 自证失明：{tag}（误植后应判与登记不符）")
# 去强度自证：把 SEQ3_MIRRORS 的任意一行删掉都应被上项 checks 红住（防静默放过删行）。
# 本表只有 2 行时两行都要测；日后增行此处本格自动覆盖。
# 去强度自证：这 2 行不是孤证 —— 至少 2 条镜句登记的锁定动作在下方已经体现（不算自证块内的判定）。
# 删任何行本表都不红 —— 那要靠另一个独立证据等于把这行删了另一个证据顶不住。
# 在本文件 SEQ3_MIRRORS 本体之外再把同样的 2 条的「characters 收句人 = X」影印一处：
# 影印散掉（改名 / 挪人 / 删句）即红，SEQ3_MIRRORS 整行删掉它也红 —— 双表同理印证，删一处另一处仍守。
_SEQ3_MIRROR_PIN = {  # 影印登记（不读 SEQ3_MIRRORS —— 若是硬同步复制，加行 / 改 owner 时两处一处改即可红）
    "merchant_lin": "这趟先验半程的水路",
    "guild_head": "依大宋律，同居共财",
}
for _cid, _frag in _SEQ3_MIRROR_PIN.items():
    _ch = next((c for c in _chars if str(c.get("id")) == _cid), None)
    check(_ch is not None, f"SEQ3_MIRRORS 影印：`{_cid}` 在 characters.json 里没有这条人物（删人物 / 改名 → 本处红）")
    check(_ch and any(_frag in ln for ln in _ch.get("lines") or []),
          f"SEQ3_MIRRORS 影印：`{_cid}` 的 lines 里没有「{_frag}」——若 SEQ3_MIRRORS 整行删去仍能在此红")

SEQ3_ELSEWHERE = [  # (扫哪里, 禁写法) —— 无「按幕 id」落点：键 = 出处文件，值 = 包装禁词；.gd 只查字符串字面量
    # （SeaChart 注释里画罗盘的「罗盘」是控件名，不上屏）；改幕名 / 挪幕不用跟
    ("data/characters.json", re.compile(r"中继路|按照大宋律例|防波堤")),
    ("data/characters_codex.json", re.compile(r"中继|按照大宋律例|防波堤")),
    ("data/crew.json", re.compile(r"罗盘")),
    ("scripts/core/Voyage.gd", re.compile(r"罗盘")),
]
for rel, pat in SEQ3_ELSEWHERE:
    _f = os.path.join(ROOT, rel)
    check(os.path.isfile(_f), f"SEQ3_ELSEWHERE 登的 {rel} 不存在（挪文件时同删本行）")
    if not os.path.isfile(_f):
        continue
    src_inner = open(_f, encoding="utf-8").read()
    for ln, row in enumerate(src_inner.splitlines(), 1):
        texts = re.findall(r'"(?:[^"\\\n]|\\.)*"', row) if rel.endswith(".gd") else [row]
        for t in texts:
            hit = pat.search(t)
            check(hit is None, f"{rel}:{ln} 回退到 lane seq2 / seq3 已判改的写法「{hit.group(0) if hit else ''}」")
_SEQ3_ELSEWHERE_SELF = "我在防波堤上等你"
check(any(p.search(v) for _, p in SEQ3_ELSEWHERE for v in (f'"{_SEQ3_ELSEWHERE_SELF}"', _SEQ3_ELSEWHERE_SELF)),
      "SEQ3_ELSEWHERE 自证失明：往探串里塞禁词「防波堤」逐模式没抓到")
# 去强度自证：在每条 SEQ3_ELSEWHERE 上造一个该条独有禁写法的红样本（防模式被改成永不中 / 行被删）
_seq3_elsewhere_probe = {  # 文件 → 该条独有的禁词
    "data/characters.json": "中继路",
    "data/characters_codex.json": "中继",
    "data/crew.json": "罗盘",
    "scripts/core/Voyage.gd": "罗盘",
}
for rel, pat in SEQ3_ELSEWHERE:
    _probe_word = _seq3_elsewhere_probe.get(rel)
    check(_probe_word is not None and pat.search(_probe_word) is not None,
          f"SEQ3_ELSEWHERE 自证失明：{rel} 的禁写法在样本上没命中（模式改了 / 该条被删 / 本表漏登记样本词）")
_elsewhere_files = {rel for rel, _ in SEQ3_ELSEWHERE}
check(_elsewhere_files == set(_seq3_elsewhere_probe),
      f"SEQ3_ELSEWHERE 自证登记不齐（表里 {sorted(_elsewhere_files)}，样本词表 {sorted(_seq3_elsewhere_probe)}）")

# ──── 结构门禁登记表口径（lane w20-b5，SEQ3_MIRRORS / SEQ3_ELSEWHERE / SCENE_ARCHIVE / 卷首题名表）────
# 按「登记对象是内容本身还是数据上的具体幕」分两支——
#   ① **按内容登记**：键 = 句子 / 包装禁词 / 卷首题字原文，改幕 id / 挪幕不用跟；删内容即删整行。
#      SEQ3_ELSEWHERE、TITLE_QUAD_CG（卷首题名表）都属此类。往表里加一条等价于新禁令。
#      SEQ3_MIRRORS 的镜像句原文也属此类 —— 改字即改整行（两处镜像须一同换字）。
#   ② **按幕 id 登记**：登记的是「这些具体的幕 / 这些具体的修订」——不记那些幕名就是没登记这个事件。
#      SCENE_ARCHIVE（归档名册）、PROLOGUE_HISTORY_KEEP / PROLOGUE_SUGGEST（史实校勘按幕守）、
#      SEQ3_MIRRORS 的落幕列（该一句在哪一幕上屏的那处具体产品）都属此类；改幕名须随这些表同改，
#      不然门禁以「id 悬空 / 与登记不符」红。
# 标识：① 类的表头行尾带「**按内容登记**」；② 类的表头行尾带「**按幕 id 登记**」。
# ── scenes.json 结构门禁（lane seq3）────────────────────────────────
# seq1 / seq2 的「结构不变」只在 /tmp 里的一次性 prove.py 证过（改前 vs 改后逐键比），没进库，下一次改文案没人再证。
# 这里不和旧版比，直接把结构本身锁住：
#   ① 字段齐备：顶层只许 start_scene / scenes；每幕按形状取必填键，不许有形状外的键（键拼错 Main 读不到，按缺省静默走）；
#      choices / investigations / facilities / options 每条同理。形状：type=title 卷首四方、type=port 港页、
#      type=investigation 兴化调查页；不写 type 的，有 result 是「详情场」（调查项的长稿，归档不上屏），否则是剧情幕。
#   ② 类型与取值：str / list / dict / int（bool 不算 int）/ bool；type、chapter、location、cg、require_chapter 只许在册的值；
#      效果值按 SCENE_EFFECT_TYPES 定型。
#   ③ 引用存在：start_scene；choices / investigations 的 next（四类，同上面 next_resolves）；调查项 id → 同名详情场；
#      港页设施 id → Main.REMAPPED_FACILITIES；require_any / require_flag / hide_if_flag 的旗标要有人写
#      （scenes.json 的 flag 效果或 scripts/ 里 set_flag("…") 字面量）；cargo → goods.json；discovery → discoveries.json 名或 id；
#      chapters.json 的 advance_scene / endings[].scene → scenes.json；非 deprecated 幕不许跳进 deprecated 幕。
#   ④ 无孤儿：从真机入口走——start_scene、type=port 幕（海图抵港）、chapters.json 引的幕（晋升册页 / 结局）、
#      Main.PROLOGUE_ONLY_FACILITIES 里港卡直进的幕（其余 city_* 港卡被 REMAPPED 改写成 {港}_{后缀} 动态页，进不到 scenes.json）——
#      沿 choices / investigations 的 next 走不到的非 deprecated 幕，必须登记在 SCENE_ARCHIVE。
#      名单外走不到 → 红（新加的幕忘了接入口）；名单里的被接回入口 → 红（从名单删掉）；名单里的 id 不存在或是 deprecated → 红。
# 结构没变时本节零输出；改了结构（加键、加形状、接回归档场）要先改表，改表即留痕。
# 形状表（lane seq6）：必填 / 可选键与字段类型不在本文件另写，读 tools/data_family.json 里 data/scenes.json 那条的 kinds / shapes
# （check_data_family 与本门禁同读一份，改一处两边同时认，不会再分叉）；本文件只留在册取值、效果定型、旗标、归档等 scenes 专属规则。
SCENE_ARCHIVE = {
    # docs/P7-剧情闭环-任务书.md §3.3 / 裁定 J：剧情图不可达、不是入口的旧稿，「归档场不删除、不做入口」。
    # 当时名单 42 个（对 993edc1）；P7 的实现没有并进 main，本表按 ff82b17 现走一遍重列：
    # 其中 city_guild / city_residence 经 PROLOGUE_ONLY_FACILITIES 可进、sail 在海路链上，不在此表；共 39 个。
    # 剧情幕 4：云端旧开局（酒棚总页、回家 / 去泉州两分支、候试页）
    "prologue_wine_shed", "prologue_return_home", "prologue_go_quanzhou", "chapter1_scholar_wait",
    # 调查页 2：港卡 city_tavern / city_shipyard 在 REMAPPED 里、不在 PROLOGUE_ONLY，真机进的是 {港}_tavern / {港}_shipyard 动态页
    "city_tavern", "city_shipyard",
    # 详情场 33：result 长稿。Main 不读 result / options（scripts/ 里 0 处），调查页上屏的是 investigations[].text
    "prologue_draft", "prologue_ledger", "prologue_permit", "prologue_veteran", "prologue_catalyst",
    "study_desk", "family_house", "city_gate", "harbor_wine_shed", "ferry_jetty", "messenger_post", "customs_shed",
    "merchant_house", "shipyard", "fuzhou_road", "recommendation_letter", "guest_house", "sutra_room", "stele_walk",
    "guest_hall", "reef_sound", "lead_line", "old_berth_note", "academy_gate", "paper_shop", "mulan_bei", "yangji_yuan",
    "customs_room", "yahang", "arab_mosque", "beacon_tower", "relay_post", "fuzhou_yamen",
}
# （lane w20-b5）**按幕 id 登记**：这是策划对 ff82b17 时点旧稿的清册，不许形状挑 / 形状锚化
# （「所有走不到的非 deprecated 幕」是宽限、会放过未接入口的新幕；和「这 39 个曾是入口就撤了」的历史事实不同）。
# 放行口子的到期判据（GATES §五.3）：名单只减不增。条目被接回入口即红、要删；幕删了即红、要删；新孤儿不许登记进来
# （接上入口，或标 deprecated）。上界随删减往下调，不许往上调；P7 港口节拍（data/port_beats.json，拍板清单 E-10）若接回，逐条删。
SCENE_ARCHIVE_MAX = 39
check(len(SCENE_ARCHIVE) <= SCENE_ARCHIVE_MAX,
      f"SCENE_ARCHIVE 只许减不许增：现 {len(SCENE_ARCHIVE)} 条 > 上界 {SCENE_ARCHIVE_MAX}（新孤儿要接入口，不要登记）")
SCENE_FAMILY_MANIFEST = "tools/data_family.json"
_PY_OF = {"str": str, "int": int, "num": (int, float), "bool": bool, "dict": dict, "list": list}


def _spec_types(spec):
    """清单类型写法（str / int / list<@choice> / str|list<str> …）→ Python 类型（元组 = 多选）。认不出给 None。"""
    out = []
    for a in (x.strip() for x in spec.split("|")):
        t = list if a.startswith("list<") else _PY_OF.get(a)
        if t is None:
            return None
        out += list(t) if isinstance(t, tuple) else [t]
    return out[0] if len(out) == 1 else tuple(dict.fromkeys(out))


def scene_shapes_from_manifest(man):
    """data_family.json → (SCENE_KINDS [(形名, when, 必填键, 可选键)], SCENE_SUB_SHAPES {列表字段: (必填, 可选)},
    SCENE_FIELD_TYPES {字段名: 类型}, 问题列表)。纯函数，自证拿改过的副本喂它。"""
    probs, kinds, subs, types = [], [], {}, {}
    fam = next((f for f in (man or {}).get("families", []) if f.get("file") == "data/scenes.json"), None)
    if fam is None:
        return [], {}, {}, [f"{SCENE_FAMILY_MANIFEST} 里没有 data/scenes.json 那条（scenes 形状表的唯一来源）"]
    shapes = fam.get("shapes", {})

    def split(fields, where):
        req, opt = set(), set()
        for k, spec in fields.items():
            name = k.rstrip("?")
            (opt if k.endswith("?") else req).add(name)
            t = _spec_types(spec)
            if t is None:
                probs.append(f"{SCENE_FAMILY_MANIFEST} scenes {where}.{name} 类型写法 {spec!r} 认不出")
            elif types.setdefault(name, t) != t:
                probs.append(f"{SCENE_FAMILY_MANIFEST} scenes 同名字段 {name} 各形类型不一（{types[name]} / {t}）：本门禁按字段名定型，须统一")
            sub = re.fullmatch(r"list<@([a-z_]+)>", spec)
            if sub:
                if sub.group(1) not in shapes:
                    probs.append(f"{SCENE_FAMILY_MANIFEST} scenes {where}.{name} 指的子形 {sub.group(1)} 不在 shapes 里")
                elif subs.setdefault(name, sub.group(1)) != sub.group(1):
                    probs.append(f"{SCENE_FAMILY_MANIFEST} scenes 列表字段 {name} 各形指的子形不一（{subs[name]} / {sub.group(1)}）")
        return req, opt

    for kd in fam.get("kinds", []):
        req, opt = split(kd.get("fields", {}), kd.get("name", "?"))
        kinds.append((kd.get("name"), kd.get("when", {}), req, opt))
    sub_shapes = {lst: split(shapes[sh], sh) for lst, sh in subs.items() if sh in shapes}
    if not any(not w for _, w, _, _ in kinds):
        probs.append(f"{SCENE_FAMILY_MANIFEST} scenes kinds 缺 when 为 {{}} 的兜底形")
    return kinds, sub_shapes, types, probs


def scene_kind(s, kinds):
    """与 check_data_family.kind_of 同一判法：按清单顺序取首个命中的形。"""
    for name, w, req, opt in kinds:
        if not w or ("field" in w and s.get(w["field"]) == w["eq"]) or ("has" in w and w["has"] in s):
            return name, req, opt
    return None


try:
    with open(os.path.join(ROOT, SCENE_FAMILY_MANIFEST), encoding="utf-8") as _f:
        _FAMILY_MAN = json.load(_f)
except (OSError, ValueError) as _e:
    _FAMILY_MAN = None
    check(False, f"{SCENE_FAMILY_MANIFEST} 读不了（{_e}）：scenes 形状表的唯一来源")
SCENE_KINDS, SCENE_SUB_SHAPES, SCENE_FIELD_TYPES, _shape_probs = scene_shapes_from_manifest(_FAMILY_MAN)
for _p in _shape_probs:
    check(False, _p)
check({"title", "port", "investigation", "story"} <= {k[0] for k in SCENE_KINDS} and {"choices", "investigations", "facilities"} <= set(SCENE_SUB_SHAPES),
      f"{SCENE_FAMILY_MANIFEST} 的 scenes 形状解析不全（形 {[k[0] for k in SCENE_KINDS]}，子形 {sorted(SCENE_SUB_SHAPES)}）")

# 卷首题名表（lane w20-b5 立）：「type=title 形 + cg_title 非空」四方字幕是序章旁白给玩家看到的世界四字题，
# 文本即内容。**按内容登记**——表里不写幕 id、不写 scenes 顺序，只锁「这几段四方题字当前仍是这几个字」；
# 改幕 id / 挪幕 / 改 cg_title 的其他键都不用跟，真改题字文本才在这一行改 / 删整行。
TITLE_QUAD_CG = {  # cg_title 原文（现 5 条：东亚起、四方分）；新四方新立一行、改字即改整行，不许原位添字
    "东亚海域立志传", "北方：漠北兵起　湖上犹歌", "东方：博多唐房　钱去硫来", "南方：占城稻熟　海峡之口", "西方：驼道尘起　白达将倾",
}
_title_cg_found = [s.get("cg_title") for s in scenes if s.get("type") == "title" and isinstance(s.get("cg_title"), str)]
check(sorted(_title_cg_found) == sorted(TITLE_QUAD_CG),
      f"scenes.json 卷首题名字幕与登记不符（现 {len(_title_cg_found)} 条，登 {len(TITLE_QUAD_CG)} 条；差 "
        f"{sorted(set(TITLE_QUAD_CG) ^ set(_title_cg_found))}）——**按内容登记**：改字即改本行，新四方新立一行，无需联系幕 id")
_TITLE_QUAD_SELF_add = sorted([*TITLE_QUAD_CG, "封控题字探一条"])
_TITLE_QUAD_SELF_sub = sorted(list(TITLE_QUAD_CG)[:-1])
check(_TITLE_QUAD_SELF_add != sorted(_title_cg_found) and _TITLE_QUAD_SELF_sub != sorted(_title_cg_found),
      "卷首题名表自证失明（加 / 减一条后应与现数据不等，未判差）")
# 去强度自证：删任意一条登记都应与现数据不等（防登记被裁剩若干仍判等）
for _probe in TITLE_QUAD_CG:
    _red_set = sorted(set(TITLE_QUAD_CG) - {_probe}) != sorted(_title_cg_found)
    check(_red_set, f"TITLE_QUAD_CG 自证失明：删掉「{_probe[:12]}」后仍判与现数据相等，删登记可混过")
del _title_cg_found, _TITLE_QUAD_SELF_add, _TITLE_QUAD_SELF_sub, _probe, _red_set
SCENE_EFFECT_TYPES = {
    **{k: int for k in ("money", "fame", "days", "chapter", "network", "merchant_credit", "supplies", "ship",
                        "sea_tendency", "scholar_tendency")},
    **{k: str for k in ("flag", "ledger_note", "cargo_loss", "discovery")},
    "cargo": list,
}
# Main 现不读 cg（背景按 type / location / cg_ 前缀定）；只收现有两个值，防拼错。location "sea" 只有 sail 一幕，落 FALLBACK_BG。
SCENE_CG = {"dark", "fade"}
SCENE_LOCATION_EXTRA = {"sea"}
check(set(SCENE_EFFECT_TYPES) >= handled, f"SCENE_EFFECT_TYPES 缺 Main.apply_effects 新接的键 {sorted(handled - set(SCENE_EFFECT_TYPES))}：先定类型")


def _main_const_list(name):
    m = re.search(rf"const {name} := \[(.*?)\]", main_src, re.S)
    check(m is not None, f"Main.gd 缺 {name}（scenes.json 结构门禁要读它）")
    return re.findall(r'"([a-z_]+)"', m.group(1)) if m else []


SCENE_CTX = {
    "ports": port_ids,
    "chapters": load("chapters.json"),
    "goods": {g.get("id") for g in load("goods.json").get("goods", [])},
    "discoveries": {x for d in load("discoveries.json").get("discoveries", []) for x in (d.get("id"), d.get("name"))},
    "remapped": set(_main_const_list("REMAPPED_FACILITIES")),
    "prologue_only": set(_main_const_list("PROLOGUE_ONLY_FACILITIES")),
    "code_flags": {f for p in pathlib.Path(ROOT, "scripts").rglob("*.gd")
                   for f in re.findall(r'set_flag\("([a-z0-9_]+)"\)', p.read_text(encoding="utf-8"))},
    "archive": SCENE_ARCHIVE,
}
check(len(SCENE_CTX["remapped"]) >= 9 and SCENE_CTX["prologue_only"], "Main.REMAPPED / PROLOGUE_ONLY_FACILITIES 解析失败")


def _is_type(v, t):
    ts = t if isinstance(t, tuple) else (t,)
    return any(isinstance(v, x) and not (x is int and isinstance(v, bool)) for x in ts)


def scene_structure_problems(doc, ctx):
    """scenes.json 整份 → 结构问题列表（空 = 过）。纯函数，自证拿改过的副本喂它。"""
    out = []
    kinds, sub_shapes, ftypes = ctx.get("kinds", SCENE_KINDS), ctx.get("sub_shapes", SCENE_SUB_SHAPES), ctx.get("field_types", SCENE_FIELD_TYPES)
    if not isinstance(doc, dict) or set(doc) != {"start_scene", "scenes"}:
        return [f"scenes.json 顶层键须恰为 start_scene / scenes，实为 {sorted(doc) if isinstance(doc, dict) else type(doc).__name__}"]
    scs = doc["scenes"]
    if not isinstance(scs, list) or not all(isinstance(s, dict) for s in scs):
        return ["scenes.json scenes 须为对象列表"]
    by = {}
    for s in scs:
        sid = s.get("id")
        if not isinstance(sid, str) or not sid:
            out.append(f"scenes.json 有幕缺 id 或 id 不是非空字符串：{str(s)[:60]}")
        elif sid in by:
            out.append(f"scenes.json 幕 id 重复：{sid}")
        else:
            by[sid] = s
    chdoc = ctx["chapters"]
    ch_ids = [int(c.get("id", 0)) for c in chdoc.get("chapters", [])]
    enums = {"type": {"title", "port", "investigation"},
             "chapter": {"prologue"} | {f"chapter_{i}" for i in ch_ids},
             "location": set(ctx["ports"]) | SCENE_LOCATION_EXTRA, "cg": SCENE_CG}
    ids = set(by)
    writers = set(ctx["code_flags"])
    for s in scs:
        for lst in ("choices", "investigations"):
            for c in s.get(lst) or []:
                eff = c.get("effects") if isinstance(c, dict) else None
                if isinstance(eff, dict) and isinstance(eff.get("flag"), str):
                    writers.add(eff["flag"])

    def resolves(nxt):
        if nxt in ids or nxt in ctx["ports"] or nxt in PLACEHOLDERS:
            return True
        return any(nxt.endswith(suf) and nxt[: -len(suf)] in set(ctx["ports"]) | ids for suf in FACILITY_SUFFIXES)

    def fields(where, obj, req, opt):
        for k in sorted(req - set(obj)):
            out.append(f"{where} 缺必填字段 `{k}`")
        for k in sorted(set(obj) - req - opt):
            out.append(f"{where} 有形状外的字段 `{k}`（拼错？新字段先登记进 {SCENE_FAMILY_MANIFEST} 的 scenes kinds / shapes）")
        for k, v in obj.items():
            t = ftypes.get(k)
            if t is not None and not _is_type(v, t):
                out.append(f"{where}.{k} 类型应为 {getattr(t, '__name__', t)}，实为 {type(v).__name__}")
            elif k in enums and v not in enums[k]:
                out.append(f"{where}.{k} = {v!r} 不在册（可选 {sorted(enums[k])}）")
        if isinstance(obj.get("require_any"), list):
            for f in obj["require_any"]:
                if not isinstance(f, str) or f not in writers:
                    out.append(f"{where}.require_any 旗标 `{f}` 没人写（scenes flag 效果与 scripts/ set_flag 都没有）")
        for k in ("require_flag", "hide_if_flag"):
            if isinstance(obj.get(k), str) and obj[k] not in writers:
                out.append(f"{where}.{k} 旗标 `{obj[k]}` 没人写")
        rc = obj.get("require_chapter")
        if _is_type(rc, int) and not (1 <= rc <= max(ch_ids or [1])):
            out.append(f"{where}.require_chapter = {rc} 不在 1..{max(ch_ids or [1])}")

    for s in scs:
        sid = s.get("id")
        t = s.get("type")
        if "type" in s and t not in enums["type"]:
            out.append(f"scenes.json {sid}.type = {t!r} 不在册（可选 {sorted(enums['type'])}）")
            continue
        kd = scene_kind(s, kinds)
        if kd is None:
            out.append(f"scenes.json {sid} 没有命中任何形（{SCENE_FAMILY_MANIFEST} scenes kinds 缺兜底形）")
            continue
        shape, req, opt = kd
        fields(f"scenes.json {sid}", s, req, opt)
        if s.get("deprecated") is False:
            out.append(f"scenes.json {sid}.deprecated 只许写 true（不废弃就删掉这个键）")
        res = s.get("result")
        if isinstance(res, list) and not all(isinstance(x, str) for x in res):
            out.append(f"scenes.json {sid}.result 列表里须全是字符串")
        for lst, (sreq, sopt) in sub_shapes.items():
            items = s.get(lst)
            if not isinstance(items, list):
                continue
            for i, c in enumerate(items):
                where = f"scenes.json {sid}.{lst}[{i}]"
                if not isinstance(c, dict):
                    out.append(f"{where} 须为对象")
                    continue
                fields(where, c, sreq, sopt)
                for ek, ev in (c.get("effects") or {}).items() if isinstance(c.get("effects"), dict) else ():
                    et = SCENE_EFFECT_TYPES.get(ek)
                    if et is None:
                        out.append(f"{where}.effects 键 `{ek}` 未定类型（Main.apply_effects 也不接）")
                    elif not _is_type(ev, et):
                        out.append(f"{where}.effects.{ek} 类型应为 {et.__name__}，实为 {type(ev).__name__}")
                    elif ek == "cargo" and any(g not in ctx["goods"] for g in ev):
                        out.append(f"{where}.effects.cargo 有 goods.json 里没有的货 {[g for g in ev if g not in ctx['goods']]}")
                    elif ek == "discovery" and ev not in ctx["discoveries"]:
                        out.append(f"{where}.effects.discovery `{ev}` 不是 discoveries.json 的名或 id")
                nxt = c.get("next")
                if lst in ("choices", "investigations") and isinstance(nxt, str):
                    if lst == "choices" and not nxt:
                        out.append(f"{where}.next 为空（选项必须有去处）")
                    elif nxt and not resolves(nxt):
                        out.append(f"{where}.next `{nxt}` 悬空（不在 scenes / ports / 设施 / 占位任何一类）")
                    elif nxt in by and by[nxt].get("deprecated") and not s.get("deprecated"):
                        out.append(f"{where}.next `{nxt}` 跳进了 deprecated 幕")
                cid = c.get("id")
                if lst == "investigations" and isinstance(cid, str) and "result" not in by.get(cid, {}):
                    out.append(f"{where}.id `{cid}` 没有同名详情场（带 result 的幕）")
                if lst == "facilities" and isinstance(cid, str) and cid not in ctx["remapped"]:
                    out.append(f"{where}.id `{cid}` 不是 Main.REMAPPED_FACILITIES 里的港卡")
        if shape == "port" and sid not in ctx["ports"]:
            out.append(f"scenes.json {sid} 是 type=port 却不在 ports.json（海图到不了）")

    start = doc.get("start_scene")
    if not isinstance(start, str) or start not in by or by[start].get("deprecated"):
        out.append(f"scenes.json start_scene `{start}` 悬空或是 deprecated 幕")
    ch_refs = []
    for c in chdoc.get("chapters", []):
        if c.get("advance_scene"):
            ch_refs.append((f"chapters {c.get('id')}.advance_scene", c["advance_scene"]))
        for j, e in enumerate(c.get("endings") or []):
            if isinstance(e, dict) and e.get("scene"):
                ch_refs.append((f"chapters {c.get('id')}.endings[{j}].scene", e["scene"]))
    for where, ref in ch_refs:
        if ref not in by:
            out.append(f"{where} `{ref}` 在 scenes.json 里不存在")

    # ④ 孤儿：真机入口出发，沿 next 走
    roots = {start} | {x for x, s in by.items() if s.get("type") == "port"} | {r for _, r in ch_refs}
    for s in by.values():
        for f in s.get("facilities") or []:
            if isinstance(f, dict) and (f.get("id") in ctx["prologue_only"] or f.get("id") not in ctx["remapped"]):
                roots.add(f.get("id"))
    seen, todo = set(), [r for r in roots if r in by]
    while todo:
        x = todo.pop()
        if x in seen:
            continue
        seen.add(x)
        for lst in ("choices", "investigations"):
            for c in by[x].get(lst) or []:
                if isinstance(c, dict) and c.get("next") in by:
                    todo.append(c["next"])
    for x, s in by.items():
        if s.get("deprecated"):
            continue
        if x not in seen and x not in ctx["archive"]:
            out.append(f"scenes.json {x} 是孤儿：从 start_scene / 港页 / chapters.json / 港卡直进都走不到，也不在 SCENE_ARCHIVE")
        if x in seen and x in ctx["archive"]:
            out.append(f"scenes.json {x} 在 SCENE_ARCHIVE 里却已接回入口：从归档名单删掉")
    for x in sorted(set(ctx["archive"]) - set(by)):
        out.append(f"SCENE_ARCHIVE 里的 `{x}` 在 scenes.json 里不存在")
    for x in sorted(x for x in ctx["archive"] if by.get(x, {}).get("deprecated")):
        out.append(f"SCENE_ARCHIVE 里的 `{x}` 已是 deprecated，不必再登记")
    scene_structure_problems.seen = seen
    scene_structure_problems.stats = f"入口可达 {len(seen)} · 归档 {len(set(ctx['archive']) & set(by))} · deprecated {sum(1 for s in by.values() if s.get('deprecated'))}"
    return out


_scene_doc = load("scenes.json")
for msg in scene_structure_problems(_scene_doc, SCENE_CTX):
    check(False, msg)
SCENE_STRUCT_STATS = scene_structure_problems.stats
# 反向自证：每类问题各造一个副本，必须报出含指定字样的那一条（防日后改表 / 改遍历时某类静默失明）。
# 锚按形状挑（lane w19-g7 落地，lane w20-a10 口径补精）：每格不锚字面 id，按清单形状 + 本文件自有的判定特征
# 挑 scenes.json 里顺序头一条合条件的幕 / 选项 / 章（形名、必填键、子形都读 SCENE_KINDS / SCENE_SUB_SHAPES，
# 即 tools/data_family.json），幕改名自己跟上；挑不到即红「锚落不上」并写明挑选条件，不静默绿、不崩。
# 变异用的悬空名都现造、先验不撞现有 id。
#
# ── 表头口径 · 判定分支（lane w20-a10）─────────────────────────────────────────────
#   每格判定 = 两岔口，写完造格时先行定死、不再后查：
#   (A) 按形状挑 —— 挑选条件只由【形状单一来源（清单 kinds / shapes / 字段表）+
#       本文件判定特征（非 deprecated / 不在 SCENE_ARCHIVE / 从入口可达 / 列表非空 / 字段类型在册 / 旗标有人写）、
#       不指名幕 id】组成。——24 类里的 22 类。
#   (B) 必须按 id —— 变异动作本身须【抓住一个具体 id 不放】（造一个以它为蓝本的孪生 / 只许它重复），
#       没有可脱开 id 的形状谓语。——24 类里的 2 类：「id 重复」「新孤儿」。
#       这两格不置形状谓语，改在 _SV_MUTANTS 表尾的 _SV_ID_REQUIRED 表逐条写明理由；形状挑不出这两格的替身。
# 改名演练（自证 ①，breif 文案「把某幕 id 改掉，门禁不许红」）走本片 brief 的 Verify 节达标：
#   对全部 24 类把现挑到的锚 id 做一次大改名后再整门禁，须仍全绿；24 类任一格红即「此条锚确实按 id」。
class _NoAnchor(Exception):
    pass


_SV_SEEN = getattr(scene_structure_problems, "seen", set())
_SV_BY = {s.get("id"): s for s in _scene_doc.get("scenes", []) if isinstance(s, dict)} if isinstance(_scene_doc, dict) else {}
_SV_FALLBACK = next((k for k in SCENE_KINDS if not k[1]), None)
_SV_DETAIL = next((k for k in SCENE_KINDS if "has" in k[1]), None)
_SV_TAKEN = (set(_SV_BY) | set(SCENE_CTX["ports"]) | set(PLACEHOLDERS) | SCENE_CTX["remapped"] | SCENE_CTX["goods"]
             | SCENE_CTX["discoveries"] | SCENE_CTX["code_flags"])


def _sv_fresh(base):
    """现造一个不撞任何现有 id / 港 / 占位 / 港卡 / 货 / 发现 / 旗标的名字（也不以设施后缀拼回现有港 / 幕）。"""
    n, name = 0, f"zz_mut_{base}"
    while name in _SV_TAKEN or any(name.endswith(x) for x in FACILITY_SUFFIXES):
        n += 1
        name = f"zz_mut_{base}{n}"
    return name


def _sv_kind(s):
    k = scene_kind(s, SCENE_KINDS)
    return k[0] if k else None


def _sv_live(s):
    return not s.get("deprecated") and s.get("id") not in SCENE_ARCHIVE


def _sv_pick(cond, pred):
    """scenes.json 顺序里头一条 pred 为真的幕 id；没有即 _NoAnchor（带挑选条件）。"""
    for s in _SV_BY.values():
        try:
            if pred(s):
                return s["id"]
        except (KeyError, IndexError, TypeError, AttributeError):
            continue
    raise _NoAnchor(f"scenes.json 找不到「{cond}」的幕")


def _sv_first_dict(s, lst):
    xs = s.get(lst)
    return xs[0] if isinstance(xs, list) and xs and isinstance(xs[0], dict) else None


def _sv_story():
    """主锚：兜底形（剧情幕）、非 deprecated、不在归档、从真机入口可达、location 是字符串、choices[0] 的 next 指向非 deprecated 幕。"""
    if _SV_FALLBACK is None:
        raise _NoAnchor(f"{SCENE_FAMILY_MANIFEST} scenes kinds 没有 when 为 {{}} 的兜底形")
    fb = _SV_FALLBACK[0]

    def ok(s):
        c = _sv_first_dict(s, "choices")
        return (_sv_kind(s) == fb and _sv_live(s) and s["id"] in _SV_SEEN and isinstance(s.get("location"), str) and c is not None
                and isinstance(c.get("next"), str) and c["next"] in _SV_BY and not _SV_BY[c["next"]].get("deprecated"))
    return _sv_pick(f"兜底形 {fb}、非 deprecated、不在 SCENE_ARCHIVE、从入口可达、location 是字符串、choices[0] 的 next 指向非 deprecated 幕", ok)


def _sv_req_field(req, kind_desc, exclude=("id",), typ=str):
    fs = sorted(k for k in req if k not in exclude and SCENE_FIELD_TYPES.get(k) is typ)
    if not fs:
        raise _NoAnchor(f"{SCENE_FAMILY_MANIFEST} {kind_desc} 没有 {typ.__name__} 型的必填字段（id 除外）")
    return fs[0]


def _sv_sub(lst):
    if lst not in SCENE_SUB_SHAPES:
        raise _NoAnchor(f"{SCENE_FAMILY_MANIFEST} scenes 没有列表字段 {lst} 的子形")
    return SCENE_SUB_SHAPES[lst]


def _sv_has_list(lst):
    return _sv_pick(f"{lst} 是非空列表、{lst}[0] 是对象", lambda s: _sv_first_dict(s, lst) is not None)


def _sv_choice_eff(key, want_type=None):
    """效果锚：头一条 choices[i].effects 已有 key（want_type 给了则按 SCENE_EFFECT_TYPES 找该型的首个键）的非 deprecated 幕 → (幕, i, 键)；
    都没有则退到头一条 effects 是对象的非 deprecated 幕选项（照原样往里写这个键）。"""
    fallback = None
    for s in _SV_BY.values():
        if s.get("deprecated") or not isinstance(s.get("choices"), list):
            continue
        for i, c in enumerate(s["choices"]):
            eff = c.get("effects") if isinstance(c, dict) else None
            if not isinstance(eff, dict):
                continue
            ks = [k for k in eff if SCENE_EFFECT_TYPES.get(k) is want_type] if want_type else ([key] if key in eff else [])
            if ks:
                return s["id"], i, ks[0]
            if fallback is None and key:
                fallback = (s["id"], i, key)
    if fallback:
        return fallback
    what = f"效果键为 {want_type.__name__} 型" if want_type else f"effects 有 {key}，或 effects 是对象"
    raise _NoAnchor(f"scenes.json 找不到「非 deprecated 幕的 choices[i]、{what}」的选项")


def _sv_archived():
    return _sv_pick("在 SCENE_ARCHIVE、非 deprecated", lambda s: s["id"] in SCENE_ARCHIVE and not s.get("deprecated"))


def _sv_mut(fn, chapters=None):
    d = copy.deepcopy(_scene_doc)
    fn(d, {s["id"]: s for s in d["scenes"]})
    ctx = dict(SCENE_CTX, chapters=chapters) if chapters is not None else SCENE_CTX
    return scene_structure_problems(d, ctx)


def _sv_ch(fn):
    c = copy.deepcopy(SCENE_CTX["chapters"])
    fn(c)
    return c


# 每格：(类名, 造格) —— 造格现挑锚，返回 (改副本的 fn(d, b), 改过的 chapters 或 None, 须报出的字样)
# 每支 docstring 头行写「判定分支A 挑选条件 = …」（22 类）；判定分支 B 的两支在函数体里写明必须有 id 的理由。
def _m_del_body():
    """判定分支A 挑选条件 = 主锚（兜底形 + 非 deprecated + 不在归档 + 入口可达 + location 是字符串 + choices[0].next 指到非 deprecated 幕）；
    删的键 = 清单兜底形 str 型必填里字母序头一个。"""
    a = _sv_story()
    f = _sv_req_field(_SV_FALLBACK[2], f"兜底形 {_SV_FALLBACK[0]}")
    return lambda d, b: b[a].pop(f), None, f"scenes.json {a} 缺必填字段 `{f}`"


def _m_del_next():
    """判定分支A 挑选条件 = 主锚；前提 = 清单 choice 子形的 next 是必填（清单不一致时落「锚落不上」明示）。"""
    a = _sv_story()
    if "next" not in _sv_sub("choices")[0]:
        raise _NoAnchor(f"{SCENE_FAMILY_MANIFEST} choice 子形的 next 不是必填")
    return lambda d, b: b[a]["choices"][0].pop("next"), None, f"scenes.json {a}.choices[0] 缺必填字段 `next`"


def _m_del_fac():
    """判定分支A 挑选条件 = 头一条 facilities 是非空列表且首条是对象的幕（不指名哪张港页）；删的键 = facility 子形 str 型必填头一个。"""
    a = _sv_has_list("facilities")
    f = _sv_req_field(_sv_sub("facilities")[0], "facility 子形")
    return lambda d, b: b[a]["facilities"][0].pop(f), None, f"scenes.json {a}.facilities[0] 缺必填字段 `{f}`"


def _m_del_result():
    """判定分支A 挑选条件 = 清单里以 "has" 判形的那一张（详情场）；删的键 = 判形键本身（'has' 的值，不靠字面读）。"""
    if _SV_DETAIL is None:
        raise _NoAnchor(f"{SCENE_FAMILY_MANIFEST} scenes kinds 没有按 has 判的详情形")
    k = _SV_DETAIL[1]["has"]
    a = _sv_pick(f"形 {_SV_DETAIL[0]}（带 {k}）", lambda s: _sv_kind(s) == _SV_DETAIL[0])
    return lambda d, b: b[a].pop(k), None, f"scenes.json {a} 缺必填字段"


def _m_next_dangle():
    """判定分支A 挑选条件 = 主锚；变异值 = 现造、不撞任何在册名字的悬空 next。"""
    a, bad = _sv_story(), _sv_fresh("next")
    return lambda d, b: b[a]["choices"][0].update(next=bad), None, f"scenes.json {a}.choices[0].next `{bad}` 悬空"


def _m_inv_next():
    """判定分支A 挑选条件 = 头一条 investigations 非空、首条是对象的幕（不指名哪一页）；变异值现造。"""
    a, bad = _sv_has_list("investigations"), _sv_fresh("inv_next")
    return lambda d, b: b[a]["investigations"][0].update(next=bad), None, f"scenes.json {a}.investigations[0].next `{bad}` 悬空"


def _m_inv_id():
    """判定分支A 挑选条件 = 同上（investigations 非空）；变异动 id 字段——判「没有同名详情场」那条。"""
    a, bad = _sv_has_list("investigations"), _sv_fresh("inv_id")
    return lambda d, b: b[a]["investigations"][0].update(id=bad), None, f"scenes.json {a}.investigations[0].id `{bad}` 没有同名详情场"


def _m_start():
    """判定分支A 挑选条件 = 文档顶层的 start_scene 是字符串（顶层形状，不指名其值）；变异值现造。"""
    st = _scene_doc.get("start_scene") if isinstance(_scene_doc, dict) else None
    if not isinstance(st, str):
        raise _NoAnchor("scenes.json 没有字符串 start_scene")
    bad = _sv_fresh("start")
    return lambda d, b: d.update(start_scene=bad), None, f"start_scene `{bad}` 悬空"


def _m_chapters():
    """判定分支A 挑选条件 = chapters.json 里 advance_scene 非空的头一章（章表形状，不指名第几章）；变异值现造。"""
    chs = SCENE_CTX["chapters"].get("chapters", [])
    i = next((j for j, c in enumerate(chs) if isinstance(c, dict) and c.get("advance_scene")), None)
    if i is None:
        raise _NoAnchor("chapters.json 找不到「advance_scene 非空」的章")
    bad = _sv_fresh("advance")
    return lambda d, b: None, _sv_ch(lambda c: c["chapters"][i].update(advance_scene=bad)), f"`{bad}` 在 scenes.json 里不存在"


def _m_fac_id():
    """判定分支A 挑选条件 = 头一条 facilities 非空的幕；变异值现造、不以设施后缀拼回现有港。"""
    a, bad = _sv_has_list("facilities"), _sv_fresh("city")
    return lambda d, b: b[a]["facilities"][0].update(id=bad), None, f"scenes.json {a}.facilities[0].id `{bad}` 不是 Main.REMAPPED_FACILITIES"


def _m_flag():
    """判定分支A 挑选条件 = 头一条 require_any 是列表的幕（数据形状，不指名哪个剧情旗标）；变异值现造、不入 code_flags。"""
    a = _sv_pick("幕上 require_any 是列表", lambda s: isinstance(s.get("require_any"), list))
    bad = _sv_fresh("flag")
    return lambda d, b: b[a]["require_any"].append(bad), None, f"scenes.json {a}.require_any 旗标 `{bad}` 没人写"


def _m_cargo():
    """判定分支A 挑选条件 = 头一个非 deprecated 幕的 choices[i].effects 有 cargo（没有则退头一个 effects 是对象的）。"""
    a, i, k = _sv_choice_eff("cargo")
    bad = _sv_fresh("cargo")
    return lambda d, b: b[a]["choices"][i]["effects"].update(cargo=[bad]), None, f"scenes.json {a}.choices[{i}].effects.cargo 有 goods.json 里没有的货"


def _m_discovery():
    """判定分支A 挑选条件 = 同 _m_cargo 调口径，key 改 discovery。"""
    a, i, k = _sv_choice_eff("discovery")
    bad = _sv_fresh("discovery")
    return lambda d, b: b[a]["choices"][i]["effects"].update(discovery=bad), None, f"scenes.json {a}.choices[{i}].effects.discovery `{bad}` 不是 discoveries.json"


def _m_to_dep():
    """判定分支A 挑选条件 = 主锚 × 头一条 deprecated: true 的幕（形状特征 'deprecated is True'，不指名哪个 id）。"""
    a = _sv_story()
    dep = _sv_pick("deprecated: true", lambda s: s.get("deprecated") is True)
    return lambda d, b: b[a]["choices"][0].update(next=dep), None, f"scenes.json {a}.choices[0].next `{dep}` 跳进了 deprecated 幕"


def _m_int_str():
    """判定分支A 挑选条件 = 头一条带 int 型清单字段且现值是 int 的幕；写的键 = 清单 int 型字段字典序头一个。"""
    ints = sorted(k for k, t in SCENE_FIELD_TYPES.items() if t is int)
    hit = [None]

    def pred(s):
        hit[0] = next((k for k in ints if k in s and _is_type(s[k], int)), None)
        return hit[0] is not None
    a = _sv_pick(f"幕上有 int 型字段（{' / '.join(ints) or '清单里没有 int 型字段'}）且值是 int", pred)
    k = hit[0]
    return lambda d, b: b[a].update({k: str(b[a][k])}), None, f"scenes.json {a}.{k} 类型应为 int"


def _m_bool_int():
    """判定分支A 挑选条件 = 头一个非 deprecated 幕的 choices[i].effects 有 int 型键（本身不指名键名）。"""
    a, i, k = _sv_choice_eff(None, want_type=int)
    return lambda d, b: b[a]["choices"][i]["effects"].update({k: True}), None, f"scenes.json {a}.choices[{i}].effects.{k} 类型应为 int"


def _m_list_str():
    """判定分支A 挑选条件 = 主锚；变异把 choices 整个换成 str（'list→str' 这一形状错）。"""
    a = _sv_story()
    return lambda d, b: b[a].update(choices="x"), None, f"scenes.json {a}.choices 类型应为 list"


def _m_typo():
    """判定分支A 挑选条件 = 主锚；变异加 shape req∪opt 之外的名（现挑 'nxet'，清单已收则退现造串）。"""
    a = _sv_story()
    sreq, sopt = _sv_sub("choices")
    typo = "nxet" if "nxet" not in sreq | sopt else _sv_fresh("key")
    return lambda d, b: b[a]["choices"][0].update({typo: "x"}), None, f"scenes.json {a}.choices[0] 有形状外的字段 `{typo}`"


def _m_location():
    """判定分支A 挑选条件 = 主锚（自带 location 是字符串）；变异值 = 以现 location 为底现造、在册外的名。"""
    a = _sv_story()
    bad = _sv_fresh(_SV_BY[a]["location"])
    return lambda d, b: b[a].update(location=bad), None, f"scenes.json {a}.location = {bad!r} 不在册"


def _m_chapter():
    """判定分支A 挑选条件 = 主锚；变异值 = chapter_ 加 chapters.json 最大章号 +5，必出册外。"""
    a = _sv_story()
    ids = [int(c.get("id", 0)) for c in SCENE_CTX["chapters"].get("chapters", [])]
    bad = f"chapter_{max(ids or [0]) + 5}"
    return lambda d, b: b[a].update(chapter=bad), None, f"scenes.json {a}.chapter = {bad!r} 不在册"


def _m_dup():
    """判定分支B 必须按 id。理由：变异 = 把这一份幕 dict 原样 push 进表尾（dict(b[a]) 保留 id），所以须报告的
    「幕 id 重复：X」的 X 就是被复制的那个 id 本身——形状谓语拿不出「x 要出现两次」这种替身。"""
    a = _sv_story()
    return lambda d, b: d["scenes"].append(dict(b[a])), None, f"幕 id 重复：{a}"


def _m_orphan():
    """判定分支B 必须按 id。理由：变异 = 以主锚为蓝本深拷一份、id 现造推进表尾，须报告的是那个现造名是孤儿；
    现造名虽是现造、却以「主锚对象」为形状载体（承载 location/chapter/type/旗标等所有被枚举判的字段），
    无法用「任何一个合形谓语」替身。"""
    a, oid = _sv_story(), _sv_fresh("orphan")

    def fn(d, b):
        o = copy.deepcopy(b[a])
        o["id"] = oid
        d["scenes"].append(o)
    return fn, None, f"scenes.json {oid} 是孤儿"


def _m_archive_back():
    """判定分支A 挑选条件 = 主锚 × 头一条「在 SCENE_ARCHIVE 且非 deprecated」的幕（归档名单由集合判定，不指名 id）。"""
    a, r = _sv_story(), _sv_archived()
    return lambda d, b: b[a]["choices"][0].update(next=r), None, f"scenes.json {r} 在 SCENE_ARCHIVE 里却已接回入口"


def _m_archive_gone():
    """判定分支A 挑选条件 = 头一条「在 SCENE_ARCHIVE 且非 deprecated」的幕（同 _m_archive_back，锚由集合挑不指名字面）。"""
    r = _sv_archived()
    return lambda d, b: d["scenes"].remove(b[r]), None, f"SCENE_ARCHIVE 里的 `{r}` 在 scenes.json 里不存在"


_SV_MUTANTS = [
    ("删幕必填字段", _m_del_body), ("删选项 next", _m_del_next), ("删设施必填", _m_del_fac), ("删详情场判形键", _m_del_result),
    ("next 悬空", _m_next_dangle), ("调查项 next 悬空", _m_inv_next), ("调查项 id 悬空", _m_inv_id), ("start_scene 悬空", _m_start),
    ("chapters 引用悬空", _m_chapters), ("设施 id 悬空", _m_fac_id), ("旗标没人写", _m_flag), ("货 id 悬空", _m_cargo),
    ("发现悬空", _m_discovery), ("跳进 deprecated", _m_to_dep), ("类型错 int→str", _m_int_str), ("bool 冒充 int", _m_bool_int),
    ("类型错 list→str", _m_list_str), ("键拼错", _m_typo), ("枚举外 location", _m_location), ("枚举外 chapter", _m_chapter),
    ("id 重复", _m_dup), ("新孤儿", _m_orphan), ("归档场接回", _m_archive_back), ("归档名单悬空", _m_archive_gone),
]
# 「必须按 id」逐格注明表（lane w20-a10）：形状挑不出的只有这两格；改这两格前先把理由推翻，否则不许转成形状谓语。
_SV_ID_REQUIRED = {
    "id 重复": "变异 push 进表尾的是主锚的 dict 拷贝（含 id 原样），须报字样直指被复制的 id 本身——是「让这一 id 出现两次」，替身不存在。",
    "新孤儿": "变异以主锚整份对象为蓝本做深拷换 id 推进表尾，须报「该现造名是孤儿」与蓝本对象的所有枚举字段绑定，替身不存在。",
}
check(set(_SV_ID_REQUIRED) <= {t for t, _ in _SV_MUTANTS}, "_SV_ID_REQUIRED 里登了 _SV_MUTANTS 表外的类名")
SV_ANCHORS = {}
for tag, build in _SV_MUTANTS:
    try:
        fn, chs, want = build()
    except _NoAnchor as e:
        check(False, f"scenes.json 结构门禁自证：「{tag}」锚落不上：{e}——数据里已没有这种形状的条目，照新数据改 _SV_MUTANTS 里这一格的挑选条件（不许删格了事）")
        continue
    SV_ANCHORS[tag] = want
    try:
        got = _sv_mut(fn, chs)
    except (KeyError, IndexError, ValueError, AttributeError, TypeError) as e:
        check(False, f"scenes.json 结构门禁自证：「{tag}」锚挑到了、变异却套不上（{e!r}）——挑选条件与变异手法不一致，改 _SV_MUTANTS 这一格")
        continue
    check(any(want in m for m in got), f"scenes.json 结构门禁自证：「{tag}」后没报出「{want}」（实报 {got[:2]}）")
if "--anchors" in sys.argv[1:]:  # 逐格打印本次挑到的锚与须报字样（查锚用；不带开关不打印）
    for tag, want in SV_ANCHORS.items():
        print(f"  自证锚 {tag}：须报「{want}」")


# 形状单一来源自证（lane seq6）：改 data_family.json 的副本，本门禁须跟着认——形状只在清单里写一份，不许又在这里另起一张表
def _man_mut(fn):
    m = copy.deepcopy(_FAMILY_MAN)
    fn(m, next(f for f in m["families"] if f["file"] == "data/scenes.json"))
    kinds, subs, types, probs = scene_shapes_from_manifest(m)
    return probs + scene_structure_problems(_scene_doc, dict(SCENE_CTX, kinds=kinds, sub_shapes=subs, field_types=types))
def _kind_fields(fam, name):
    return next(k for k in fam["kinds"] if k["name"] == name)["fields"]
_SHAPE_MUTANTS = [
    ("清单 story 形删可选 speaker", lambda m, f: _kind_fields(f, "story").pop("speaker?"), "形状外的字段 `speaker`"),
    ("清单 story 形 objective 改必填", lambda m, f: _kind_fields(f, "story").__setitem__("objective", _kind_fields(f, "story").pop("objective?")), "缺必填字段 `objective`"),
    ("清单 choice 子形删可选 effects", lambda m, f: f["shapes"]["choice"].pop("effects?"), "形状外的字段 `effects`"),
    ("清单 story 形 body 改 int", lambda m, f: _kind_fields(f, "story").__setitem__("body", "int"), "各形类型不一"),
    ("清单类型写法坏", lambda m, f: _kind_fields(f, "port").__setitem__("title", "string"), "类型写法 'string' 认不出"),
    ("清单缺 scenes 那条", lambda m, f: m.__setitem__("families", [x for x in m["families"] if x is not f]), "没有 data/scenes.json 那条"),
]
if _FAMILY_MAN is not None:
    for tag, fn, want in _SHAPE_MUTANTS:
        try:
            got = _man_mut(fn)
        except (KeyError, StopIteration, TypeError) as e:
            check(False, f"scenes 形状单一来源自证：「{tag}」套不上现清单（{e!r}）——{SCENE_FAMILY_MANIFEST} 的 scenes 形改了名，改 _SHAPE_MUTANTS")
            continue
        check(any(want in x for x in got), f"scenes 形状单一来源自证：「{tag}」后没报出「{want}」（实报 {got[:2]}）")

# 「去强度」自身也是强度问题（lane w20-a10 自证 ②）：24 类的形状判定不许丢。删格 / 加格 /
# 把格改成恒绿都先在这里红——判定分支已与格一一绑定，不许半截。
check(len(_SV_MUTANTS) == 24 and len({t for t, _ in _SV_MUTANTS}) == 24,
      f"_SV_MUTANTS 现 {len(_SV_MUTANTS)} 类（去重后 {len({t for t, _ in _SV_MUTANTS})}）≠ 24（去强度变异：删格 / 加格都是强度变化，要改先动 24 类形状判定表）")

# ── 结局年号：过场 ↔ 结算册页 ↔ Calendar（Q8）───────────────
# 「岸上的根」曾写景炎三年三月，而该卡只在 1277（景炎二年）出现。结局年号有三处镜像：cutscenes.json 过场的
# era 字幕、Main._show_notice_dialog 的册页题头、触发该结局的 Calendar 日期闸；年号推算以 Calendar.ERAS /
# ERA_START 为准（照 Calendar._era_row 抄）。三处任一漂移即红。忠肃 / 岸上的根 / 纲首必须在对照之列。
cal_src = open(os.path.join(ROOT, "scripts", "core", "Calendar.gd"), encoding="utf-8").read()
_eras_m = re.search(r"const ERAS := \[(.*?)\n\]", cal_src, re.S)
CAL_ERAS = [(int(a), int(b), n) for a, b, n in re.findall(r'\[(\d{4}), (\d{4}), "(.+?)"\]', _eras_m.group(1))] if _eras_m else []
_start_m = re.search(r"const ERA_START := \{(.*?)\n\}", cal_src, re.S)
CAL_ERA_START = {n: (int(y), int(m)) for n, y, m in re.findall(r'"(.+?)": \[(\d{4}), (\d+)\]', _start_m.group(1))} if _start_m else {}
check(len(CAL_ERAS) >= 6 and {"景炎", "祥兴", "至元"} <= set(CAL_ERA_START), "Calendar.ERAS / ERA_START 解析失败")
_cal_y = re.search(r"var year: int = (\d{4})", cal_src)
_cal_mo = re.search(r"var month: int = (\d+)", cal_src)


def cal_era(year, month):
    """Calendar._era_row + get_era_year 的镜像：→ (年号, 年号年数)，表外 None。"""
    found = None
    for e0, e1, name in CAL_ERAS:
        sy, sm = CAL_ERA_START.get(name, (e0, 1))
        if (year > sy or (year == sy and month >= sm)) and year <= e1:
            found = (name, year - e0 + 1)
    return found


_SEASON = {"春": {1, 2, 3}, "夏": {4, 5, 6}, "秋": {7, 8, 9}, "冬": {10, 11, 12}}
_ERA_NAMES = "|".join(sorted({e[2] for e in CAL_ERAS}, key=len, reverse=True)) or "宝祐"
_DATE_RE = re.compile(r"(" + _ERA_NAMES + r")(?:([元一二三四五六七八九十]{1,3})年(?:(正|冬|腊|[一二三四五六七八九十]{1,2})月|([春夏秋冬]))?|年间)")


def parse_era_date(s):
    """「兴化・景炎元年十二月」→ {era, n, ce, months}；「至元年间」n/ce 为 None。无年号 → None。"""
    m = _DATE_RE.search(s or "")
    if not m:
        return None
    era, n, mo, season = m.groups()
    d = {"era": era, "n": None, "ce": None, "months": set(range(1, 13)), "text": m.group(0)}
    if n:
        d["n"] = _cn_n(n)
        e0 = next((e[0] for e in CAL_ERAS if e[2] == era), None)
        d["ce"] = e0 + d["n"] - 1 if e0 is not None else None
    if mo:
        d["months"] = {{"正": 1, "冬": 11, "腊": 12}.get(mo) or _cn_n(mo)}
    elif season:
        d["months"] = set(_SEASON[season])
    return d


def cal_ok(d):
    """年号年数落在 Calendar 会显示该年号的某个月里（如景炎元年须五月后、祥兴二年不得到至元）。"""
    if d["ce"] is None:
        return any(e[2] == d["era"] for e in CAL_ERAS)
    return any(cal_era(d["ce"], mo) == (d["era"], d["n"]) for mo in d["months"])


# 全部过场的 era 字幕都要是 Calendar 推得出的年号年
cutscenes_all = load("cutscenes.json")
era_caps = 0
for cid, cs in cutscenes_all.get("cutscenes", {}).items():
    for shot in cs.get("shots", []) or []:
        for cap in shot.get("captions", []) or []:
            if cap.get("style") != "era":
                continue
            d = parse_era_date(cap.get("text", ""))
            if d:
                era_caps += 1
                check(cal_ok(d), f"cutscenes.{cid} 年号字幕「{cap.get('text')}」与 Calendar.ERAS 推算不符")
check(era_caps >= 8, f"cutscenes.json 只认出 {era_caps} 条年号字幕，疑似解析失败")
# 开场字幕 = Calendar 开局年月
_open = next((parse_era_date(c.get("text", "")) for sh in cutscenes_all["cutscenes"].get("opening", {}).get("shots", [])
              for c in sh.get("captions", []) if c.get("style") == "era" and parse_era_date(c.get("text", ""))), None)
if _cal_y and _cal_mo and _open:
    check(_open["ce"] == int(_cal_y.group(1)) and cal_era(int(_cal_y.group(1)), int(_cal_mo.group(1))) == (_open["era"], _open["n"]),
          f"开场字幕「{_open['text']}」≠ Calendar 开局 {_cal_y.group(1)}-{_cal_mo.group(1)}")
else:
    check(False, "开场过场年号字幕或 Calendar 开局年月解析失败")


def _enclosing_func(src, pos):
    a = src.rfind("\nfunc ", 0, pos)
    b = src.find("\nfunc ", pos)
    return src[a:b if b >= 0 else len(src)]


# 册页题头：_show_notice_dialog(标题, 题头, …)；标题可是 "甲" if … else "乙"，题头可是本函数里的 var head := "…"
notice_head = {}
for m in re.finditer(r'_show_notice_dialog\(\s*([^,\n]*?),\s*("[^"\n]*"|[A-Za-z_]\w*)\s*,', main_src):
    titles = re.findall(r'"([^"\n]*)"', m.group(1))
    head = m.group(2)
    if not head.startswith('"'):
        hv = re.search(r"var " + head + r' := "([^"\n]*)"', _enclosing_func(main_src, m.start()))
        head = hv.group(1) if hv else ""
    else:
        head = head.strip('"')
    for t in titles:
        notice_head.setdefault(t, head)


def _cs_eras(cid):
    return [d for sh in cutscenes_all["cutscenes"].get(cid, {}).get("shots", []) or []
            for c in sh.get("captions", []) or [] if c.get("style") == "era" and (d := parse_era_date(c.get("text", "")))]


# 触发日期闸：_special_cards 各卡的 Calendar 条件；忠肃 / 未归共用兴化城破日（_check_absent_from_xinghua）
_special = re.search(r"func _special_cards\(.*?\n(?=\nfunc |\Z)", main_src, re.S)
_special_src = _special.group(0) if _special else ""


def _card_gate(card):
    chunks = _special_src.split("out.append(")
    for i, ch in enumerate(chunks[1:], 1):
        if ch.lstrip().startswith('{"id": ' + card):
            return chunks[i - 1].rsplit("\n\n", 1)[-1]
    return ""


def _gate_from(src):
    """→ (年下限, 年上限, 允许月份)；认 Calendar.year ==/>= N 与 Calendar.month in [...] / <= / >= N。"""
    y = re.search(r"Calendar\.year (==|>=) (\d{4})", src)
    if not y:
        return None
    lo = int(y.group(2))
    hi = lo if y.group(1) == "==" else 99999
    months = set(range(1, 13))
    if (mi := re.search(r"Calendar\.month in \[([\d, ]+)\]", src)):
        months = {int(x) for x in re.findall(r"\d+", mi.group(1))}
    elif (ml := re.search(r"Calendar\.month (<=|>=) (\d+)", src)):
        k = int(ml.group(2))
        months = set(range(1, k + 1)) if ml.group(1) == "<=" else set(range(k, 13))
    return lo, hi, months


_absent = re.search(r"func _check_absent_from_xinghua\(.*?\n(?=\nfunc |\Z)", main_src, re.S)
_fall_m = re.search(r"Calendar\.year == (\d{4}) and Calendar\.month >= (\d+)", _absent.group(0) if _absent else "")
_fall_gate = (int(_fall_m.group(1)), int(_fall_m.group(1)), set(range(int(_fall_m.group(2)), 13))) if _fall_m else None
ENDING_GATE = {
    "忠肃": _fall_gate, "未归": _fall_gate,
    "岸上的根": _gate_from(_card_gate("CARD_HANJIANG")),
    "海上宋鬼": _gate_from(_card_gate("CARD_YASHAN")),
    "纲首": _gate_from(_card_gate("CARD_GANGSHOU")),
    "泉州蒲氏的船": _gate_from(_card_gate("CARD_GANGSHOU")),
}
for must in ("忠肃", "岸上的根", "纲首"):
    check(ENDING_GATE.get(must) is not None, f"结局「{must}」的 Calendar 触发闸解析失败")
    check(must in notice_head and must in cutscenes_all.get("endings", {}), f"结局「{must}」缺册页题头或过场，年号无从对照")

def _mo(ms):
    return "全年" if len(ms) == 12 else f"{sorted(ms)} 月"


mirrored = 0
for title, cid in cutscenes_all.get("endings", {}).items():
    head = notice_head.get(title)
    if head is None:
        continue
    # 过场可跨年（蒲氏的船：景炎元年冬 → 至元年间），字幕须按时序；册页题头对的是最后落定的那一年
    cds = _cs_eras(cid)
    ces = [d["ce"] for d in cds if d["ce"] is not None]
    check(ces == sorted(ces), f"结局「{title}」过场 {cid} 年号字幕不按时序：{[d['text'] for d in cds]}")
    hd, cd = parse_era_date(head), (cds[-1] if cds else None)
    if title in ENDING_GATE:
        check(hd is not None and hd["ce"] is not None, f"结局「{title}」册页题头「{head}」没有年号年")
        check(cd is not None, f"结局「{title}」过场 {cid} 没有年号字幕")
    if hd is None or cd is None:
        continue
    mirrored += 1
    check(cal_ok(hd), f"结局「{title}」册页题头「{head}」与 Calendar.ERAS 推算不符")
    # 过场 ↔ 册页：同一年号；两边都写到年数时年数相同；两边都写到月 / 季时须有交集（「冬」含十二月）
    same = hd["era"] == cd["era"] and (hd["n"] is None or cd["n"] is None or hd["n"] == cd["n"]) \
        and bool(hd["months"] & cd["months"])
    check(same, f"结局「{title}」过场 {cid}「{cd['text']}」与册页题头「{hd['text']}」年号不一致")
    gate = ENDING_GATE.get(title)
    if gate and hd["ce"] is not None:
        lo, hi, months = gate
        check(lo <= hd["ce"] <= hi and bool(hd["months"] & months),
              f"结局「{title}」题头「{hd['text']}」（{hd['ce']} 年 {_mo(hd['months'])}）落在触发闸 "
              f"{lo}{'' if hi == lo else '+'} 年 {_mo(months)}之外")
check(mirrored >= 5, f"结局年号只对照到 {mirrored} 个，疑似解析失败")
# 「岸上的根」题头只写到年：卡闸跨九、十两月，题头写死哪一月都会和落款错月。
# 这是 09-28 Snow 定 B 方案时一并定的；云端 beaa9d0 曾写死「景炎二年三月」，合并时别冲回去。
_root_hd = parse_era_date(notice_head.get("岸上的根", ""))
_root_gate = ENDING_GATE.get("岸上的根")
if _root_hd is not None and _root_gate is not None and len(_root_gate[2]) >= 2:
    check(len(_root_hd["months"]) == 12,
          f"结局「岸上的根」题头「{notice_head.get('岸上的根')}」写了月份，而卡闸跨 {_mo(_root_gate[2])}——"
          f"只写年号年（09-28 Snow 定）")

# 过场底图按旗换（lane fx5）：镜头可选 bg_alt，每项与字幕同一套旗标写法（if_flag / unless_flag），CutscenePlayer._shot_view 取第一条成立的。
# 各项旗标须有人写（scripts set_flag / news flag），底图文件须在；「未归」第 1 镜在兴化海口结算（weigui_at_harbor）换成
# 兴化海口港页那张图（Main.PORT_BG["xinghua_harbor"]），与同镜字幕换句是同一个旗，别处结算照旧海上图
bg_alts = 0
for cid, cs in cutscenes_all.get("cutscenes", {}).items():
    for i, shot in enumerate(cs.get("shots", []) or []):
        for a in shot.get("bg_alt", []) or []:
            bg_alts += 1
            for k in ("if_flag", "unless_flag"):
                if a.get(k):
                    check(a[k] in KNOWN_FLAGS, f"cutscenes.{cid}[{i + 1}].bg_alt {k} 旗标 `{a[k]}` 没人写（scripts set_flag 与 news flag 都没有）")
            abg = str(a.get("bg", ""))
            check(abg.startswith("res://assets/") and os.path.isfile(os.path.join(ROOT, abg[len("res://"):])),
                  f"cutscenes.{cid}[{i + 1}].bg_alt 底图不存在：{abg}")
_pb = re.search(r"const PORT_BG := \{(.*?)\n\}", main_src, re.S)
_harbor_bg = dict(re.findall(r'"([a-z_]+)":\s*"([^"]+)"', _pb.group(1))).get("xinghua_harbor", "") if _pb else ""
_wg_id = str(cutscenes_all.get("endings", {}).get("未归", ""))
_wg = ((cutscenes_all.get("cutscenes", {}).get(_wg_id, {}).get("shots") or [{}])[0])
_wg_alt = [a for a in _wg.get("bg_alt", []) or [] if a.get("if_flag") == "weigui_at_harbor"]
_wg_cap_flags = {c.get(k) for c in _wg.get("captions", []) or [] for k in ("if_flag", "unless_flag")}
check(bool(_harbor_bg) and bool(_wg_alt) and _wg_alt[0].get("bg") == "res://assets/" + _harbor_bg
      and "weigui_at_harbor" in _wg_cap_flags and _wg.get("bg") != _wg_alt[0].get("bg"),
      f"「未归」（{_wg_id}）第 1 镜：海口结算（weigui_at_harbor）底图须换兴化海口港页图 res://assets/{_harbor_bg}，"
      f"与字幕换句同旗，别处照旧本镜 bg（现 bg={_wg.get('bg')} bg_alt={_wg.get('bg_alt')}）")

print("=" * 68)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print(f"结局年号对照 {mirrored} · 年号字幕 {era_caps} · 底图按旗换 {bg_alts} · scenes {len(scenes)}（结构：{SCENE_STRUCT_STATS} · 自证 {len(_SV_MUTANTS)} 类 + 形状单一来源 {len(_SHAPE_MUTANTS)} 类，形状读 {SCENE_FAMILY_MANIFEST}）· news {len(news)} · npcs {len(npcs)} · war 港 {war_ports} · apply_effects 接住 {sorted(handled)}")
print("结果：全部通过")
