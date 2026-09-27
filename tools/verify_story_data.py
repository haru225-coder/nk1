#!/usr/bin/env python3
"""剧情数据静态校验：news.json / scenes.json effects / npcs.json。
起因：序章 effects 里的 sea_tendency / scholar_tendency 曾在 Main.apply_effects 里无分支，
静默丢弃了两年。此脚本把「数据里写了的效果键，代码必须接住」做成门禁。"""
import copy, json, os, re, sys, pathlib
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
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
# 七道门禁对此全盲（simulate_run 自管 visited）。此处把「同名必是港」做成静态门禁。
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
check("传闻约卖" in _gs and "func rumor_label" in _gs, "GameState.rumor_label 须保留「传闻约卖」上屏标签")
check("_setup_news_wall" in main_src and "_TAVERN_NEWS_WALL" in main_src,
      "酒馆须接新闻墙上墙（Main._setup_news_wall → _TAVERN_NEWS_WALL）")
_tnw_path = os.path.join(ROOT, "scripts", "ui", "TavernNewsWall.gd")
check(os.path.isfile(_tnw_path), "缺 scripts/ui/TavernNewsWall.gd（市井札薄）")
if os.path.isfile(_tnw_path):
    _tnw = open(_tnw_path, encoding="utf-8").read()
    check("paper_card" in _tnw and "recent_news" in _tnw and "news_text" in _tnw,
          "TavernNewsWall 须用 paper_card 渲 recent_news/news_text")
    check("_TAVERN_NEWS_WALL.mount" in main_src, "Main._setup_news_wall 须调 _TAVERN_NEWS_WALL.mount")

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
    check(any(mk in main_src for mk in markers),
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


def cond_year(cond):
    if cond == "end":
        return 99999
    if isinstance(cond, str) and cond.startswith("c") and cond[1:].isdigit():
        return PHASE_YEAR.get(int(cond[1:]), 99999)
    if isinstance(cond, (int, float)):
        return max(int(cond), START_YEAR)
    return None


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
    for k in ("bio", "short", "lines", "title", "courtesy", "alt"):
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
check('get("bio"' not in codex_src and "codex_bio(" in codex_src, "人物志小传仍读 characters.json 的 bio 原稿")
check('"bio_short"' not in main_src and "codex_short(" in main_src, "见面页简介仍读 characters.json 的 bio_short 原稿")
check("characters_codex.json" in art_src, "CharacterArt 未接人物志上屏文本层")

# ── Astra L1：人物「原稿 vs 上屏」契约（docs/人物原稿与上屏契约.md）────────────
# characters.json 是设定集原稿，characters_codex.json 是上屏文本层。上屏的字只有三条来路：
#   ① 文本层 CODEX_ONSCREEN 各段；② 原稿里 UI 直读或文本层缺省时回落的 CHAR_ONSCREEN 字段、relations[].rel；
#   ③ 原稿 meta 的 attr_def / trait_def 的 name·desc 与 faction_def 的 name。
# 三条来路上出现 ONSCREEN_BAN 即失败；原稿 CHAR_DRAFT（bio / bio_short / 画像备注）与两份 meta.note 只供策划，不上屏。
# 新增字段必须先在这里归类，UI 直读的原稿键必须落在「上屏 / 结构」两类里，否则门禁失败。
ONSCREEN_BAN = re.compile(CODEX_META.pattern + r"|placeholder|TODO|WIP|FIXME|pipeline|LLM|ChatGPT|大模型")
CHAR_ONSCREEN = {"name", "alt_names", "courtesy", "title", "origin", "personality", "look", "lines"}
CHAR_STRUCT = {"id", "faction", "traits", "relations", "born", "died", "tier", "chapters", "attrs",
               "portrait", "portrait_status", "sources", "historical"}  # 键、数值、枚举，不作正文上屏
CHAR_DRAFT = {"bio", "bio_short", "portrait_src", "portrait_note"}
CODEX_ONSCREEN = {"bio", "short", "lines", "title", "courtesy", "alt", "look", "personality"}
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
               "scripts/companions/CompanionPreview.gd"] + sorted(
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
check("codex_bio(" in art_src or "codex_bio(" in codex_src, "上屏层未走 CharacterArt.codex_bio")
check("codex_short(" in art_src or "codex_short(" in main_src, "上屏层未走 CharacterArt.codex_short")
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
    "scripts/Main.gd": ({"api"}, "runtime", "见面页、酒馆募人卡、船籍簿、人物志钮"),
    "scripts/ui/VisionStage.gd": ({"raw", "api"}, "runtime", "异象幕：先走取数口，GameManager 缺席（单跑场景）才兜底直读；只取 id"),
    "scripts/companions/CompanionPreview.gd": ({"api"}, "runtime", "同伴预览立绘"),
    "scripts/chars/CharRoster.gd": ({"api"}, "runtime", "人物名册"),
    "scripts/chars/CharsDemo.gd": ({"api"}, "runtime", "人物演示场"),
    "scripts/chars/CharsShoreOverlay.gd": ({"api"}, "runtime", "岸上人物叠层"),
    "tools/art/ShotTour.gd": ({"raw", "api"}, "dev", "美术巡检截图（开发工具，不进正式流程）"),
    "tools/art/ThemePreview.gd": ({"raw"}, "dev", "主题预览，编辑器下读 portrait_src 找原画（开发工具）"),
    "tools/art/portrait_svg/PortraitWall.gd": ({"raw"}, "dev", "立绘墙（开发工具）"),
    "tools/art/build_portraits.py": ({"raw"}, "dev", "立绘产线：按原稿 portrait / portrait_src 出图"),
    "tools/art/subset_fonts.py": ({"raw"}, "dev", "字库子集：收全部人物文字的字形"),
    "tools/verify_story_data.py": ({"raw", "codex", "api"}, "gate", "本门禁（自证合成源码里写着取数口）"),
    "tools/check_symbols.py": ({"raw", "codex"}, "gate", "L1 工程词 / 展示入口契约"),
    "tools/check_assets.py": ({"raw"}, "gate", "立绘资源存在性"),
    "tools/godot_smoke.gd": ({"raw", "api"}, "gate", "冒烟：阵营表、见面页立绘"),
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
_l1b_files = {}
for p in pathlib.Path(ROOT).rglob("*"):
    if p.suffix in (".gd", ".py", ".tscn", ".tres") and p.is_file() and not (_l1b_skip & set(p.relative_to(ROOT).parts)):
        _l1b_files[p.relative_to(ROOT).as_posix()] = p.read_text(encoding="utf-8", errors="replace")
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

print("=" * 68)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print(f"结局年号对照 {mirrored} · 年号字幕 {era_caps} · scenes {len(scenes)} · news {len(news)} · npcs {len(npcs)} · war 港 {war_ports} · apply_effects 接住 {sorted(handled)}")
print("结果：全部通过")
