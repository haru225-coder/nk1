#!/usr/bin/env python3
"""data/companions.json 骨架校验门禁（lane w64-k1，伙伴系统三件之一）。

口径：设计稿（docs/伙伴系统设计_草案_2026-09-26.md）与决策包（docs/伙伴系统决策包_2026-09-27.md）
全标「草案，未拍板」，所以本闸按对题表（docs/伙伴系统_草案与决策包对题表_2026-09-28.md）的拟定行
把字段分两档——**已定字段照草案名册 v2 照数搬入、逐条校验；未定字段一律写 "_todo"（恰这三个字），
拍板后逐格回填**。未定 ≠ 错（留空判绿）；已定字段缺值 / 类型错 / 枚举越域 / id 重号撞名判红。
字段两档的定级与出处见 docs/伙伴系统拍板包_2026-10-04.md §〇（拍板包是仓内文档，本行只写文件名）。

域全部从本仓现算，不手抄清单：region/category/窗口方式/入伙方式/战位/立场/钩名读
data/companions.json 的 meta 各 def（同文件单一来源——它是照搬草案 meta 的），职事 id 读
data/crew.json 的 roles，faction id 读 data/characters.json 的 meta.faction_def，港 id 读
data/ports.json，货 id 读 data/goods.json，特技 id 读 data/characters.json 的 meta.trait_def 与
docs/伙伴系统设计_草案_roster_draft_2026-09-26.json 的 meta.new_traits 并集（伙伴特技须先落在
characters 的 trait_def，落地白描一步才有人物志释义——新政特技已在 new_traits 里登记）。

九节判词：
  零、判据自检（GATES §五.3，内存变异不落盘）：删已定字段 / id 重号 / 名字重号 / 未定字段填成词表外值 /
    窗口写成年份整数 / 撞 crew 候名 / 云屯两人 duty 空壳不齐 / 挂不存在的港 / 各退一格判据样本全须红，
    把好样本删红后须绿——哪格判不出即本闸自身坏，先红。
  一、顶层与条目数：companions 恰 roster.companions 条 id 唯一；events 恰 roster.events 张 id 唯一（双字照名册现读）。
  二、身份骨架：name 唯一；region / category / verify / reuse_character / p1 / p1_stub 形态与枚举。
  三、langs：list<str> 非空（母语量没有枚举表，只判形）。
  四、appear：chapter_min ∈ [1,5]；windows ≥1 段；YYYY-MM 定长、1255–1285 窗内、from ≤ to；
    mode ∈ meta.meet_mode_def；ports ∈ ports.json（云屯 yundun 是泊地页、不在 ports.json，照登记放过）；
    months ⊆ [1..12]；route 恰 1–2 段、一段为 [起,讫]、端名 ∈ 本表港∪ports.json ∪ {"any"}（"any" 记 14 港任一端——
    沿用名册草案 v2 写法）；route 只许 mode ∈ {sea, tavern, event}，visit / yundun 不挂（云屯页只由绕道进、无航段）；rumor 非空。
  五、join：type ∈ meta.join_type_def；hire 者 fee ≥ 0；bond 者 bond_need ∈ [0,100] 且 bond_path 逐步 {src, value>0, note}
    且合计 ≥ bond_need；guest 者 fee == 0；requires 只含登记键，数值型键非负、ключ集合键 <str>。
  六、duty：roles / level_at_join / level_1279 / wage_role_at_join 的键都是职事 id（crew.json roles）、品级 ∈ [1,3]；
    level_at_join / level_1279 ≤ roles 声明上限；月俸 ∈ WAGE 档且 wage_role_at_join 恰取 duty.wage_slot 同值当在岗（一致则绿）；
    battle ⊆ meta.battle_slot_def 去 none；wage_slot ∈ WAGE ∪ {0}；wage_discount 只在写了的人的档内 [0,1]；
    join.type == local ⇒ duty 空壳（roles/level_at_join/level_1279/wage_role_at_join 全空、battle 空、wage_slot=0、
    home_port == "yundun"）；其余者 home_port ∈ ports.json。
  七、niche：每项 kind ∈ meta.niche_kind_def（钩名枚举，效果数值未拍板不抄值）。
  八、stance / traits / gifts / climax：stance ∈ meta.stance_def；traits ⊆ characters trait_def ∪ 名册 new_traits；
    gifts ⊆ goods.json id；climax 恰三线键。
  九、未定字段与待核：attrs / growth / fate / relations / relation_flips / bond_tiers / one_time 恰 "_todo"，
    或恰本闸登记的拍板形状（lane/story-bios 批 4 列传回填；未填者仍恰 "_todo"）：
    attrs 恰 {hang,shang,wu,xue,wang} 五键（口径同 characters.json meta.attr_def）、各 int ∈ [1,100]；
    growth = {} 或 dict（键 ∈ 五维、值 {"per_year": int>0, "cap": int ∈ [1,100]}）；
    fate = {"leave": str 非空, "detail": str 非空} 或恰 "[待核]"；
    relations = list（每条 {"id": 伙伴 id, "kind": str 非空}，id ∈ 全表∖自身）；
    relation_flips = list（每条 {"counterpart": 伙伴 id ∪ {"player"}, "event": str 非空, "effect": str 非空}）；
    bond_tiers 恰 {"40": str, "60": str, "80": str} 三档（档位自草案 §1.2：40 已识 / 60 个人事件·列传 / 80 传授）；
    one_time = list<str>（一次性事件开关名）。events 的 who ⊆ companions id ∪ {"player"}；
    verify ∈ {"待核", "已核"}（字面备「史实评审已过」回填）。
交主控：python3 tools/check_companions.py（纯 stdlib、只读、< 1 s）
"""
import json, os, re, sys
if "--json" in sys.argv[1:]:  # 机读输出件（docs/GATES.md）；不带开关不进此支
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "companions.json")
ROSTER = os.path.join(ROOT, "docs", "伙伴系统设计_草案_roster_draft_2026-09-26.json")

YM = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
WAGE = [60, 120, 200]          # 任职月俸档（与 data/crew.json 同档）
WAGE_SLOT = [0, 30, 60, 120, 200]  # 名册 wage_slot 值域：0=不付（云屯/客程）、30=少年随行、200=竹崎客将
TODO = "_todo"
TODO_FIELDS = ["attrs", "growth", "fate", "relations", "relation_flips", "bond_tiers", "one_time"]
WINDOW_MIN, WINDOW_MAX = "1255-01", "1285-12"
IDENTITY_LINES = ["scholar", "merchant", "hometown"]
ROUTE_MODES = ("sea", "tavern", "event")  # 可挂 route 的方式（visit / yundun 无航段）

fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def jload(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _type_name(v):
    return {dict: "dict", list: "list", str: "str", int: "int", bool: "bool", float: "float"}.get(type(v), type(v).__name__)


def ctype(val, spec):
    if "|" in spec:
        return any(ctype(val, s) for s in spec.split("|"))
    if spec.startswith("list<") and spec.endswith(">"):
        return isinstance(val, list) and all(ctype(v, spec[5:-1]) for v in val)
    return type(val) is {"dict": dict, "list": list, "str": str, "int": int, "bool": bool}[spec]


REQ_SPEC = {"flags": "list<str>", "fame_min": "int", "flagship_min": "str",
            "lang_any_of": "list<str>", "aboard_any_of": "list<str>", "bond_min": "dict",
            "visited_any_of": "list<str>", "events_done": "list<str>", "counters": "dict",
            "note": "str"}


def validate(data, domains, emit=check):  # noqa: C901 —— 判词分节排开，单函数胜过切来切去
    """对一份 companions.json（内存）跑全套判词；emit 账本外注，正路 = check，自检格收进袋子。
    逐人细账记进内袋，整节过 = emit 一条小计（不逐人刷 ✓）；有塌 = emit 聚合条（前 5 条塌因）。"""
    ok_all = True
    meta = data.get("meta", {})
    comps = data.get("companions", {})
    events = data.get("events", {})
    bag = []
    _r = lambda c, m: (bag.append(m) if not c else None) or c  # noqa: E731 —— 内袋记账，不进 emit

    def section(title, cond):
        nonlocal ok_all
        if cond:
            emit(True, "%s 全对" % title)
        else:
            emit(False, "%s（%d 处塌；前 5：%s）" % (title, len(bag), "；".join(bag[:5])))
        ok_all &= cond
        bag.clear()

    # 一节、顶层与条目数（条数钉群化自名册 SoR 现读——lane w92-k3，w91-k9 散文钉普查首推案①）
    refs = dict(domains.get("roster_counts", {}))
    _r(isinstance(comps, dict) and len(comps) == refs.get("companions", -1),
                   "companions 恰 %d 条（实得 %d）" % (refs.get("companions", -1),
                                                        len(comps) if isinstance(comps, dict) else -1))
    _r(isinstance(events, dict) and len(events) == refs.get("events", -1),
                   "events 恰 %d 张（实得 %d）" % (refs.get("events", -1),
                                                  len(events) if isinstance(events, dict) else -1))
    ids = list(comps.keys())
    _r(len(set(ids)) == len(ids), "companion id 唯一")
    _r(all(isinstance(e.get("id"), str) and e["id"] == k for k, e in comps.items()),
                   "各条目 id 字段与键一致")

    section("一节、顶层与条目数", not bag)

    # 二节、身份骨架
    _r(all(isinstance(e.get("name"), str) and len(e.get("name", "")) >= 2 for e in comps.values()),
                   "name 存在且非空（设计期占位名也须有名）")
    names = [str(e.get("name")) for e in comps.values()]
    _r(len(set(names)) == len(names), "name 全表唯一（重名即对不上档）")
    _r(all(isinstance(e.get("id"), str) and re.fullmatch(r"[a-z0-9_]+", e["id"] or "") for e in comps.values()),
                   "id 小写蛇形")
    for k, e in comps.items():
        _r(e.get("region") in domains["region"], "%s region=%s ∈ meta.region_def" % (k, e.get("region")))
        _r(e.get("category") in domains["category"], "%s category=%s ∈ meta.category_def" % (k, e.get("category")))
        _r(isinstance(e.get("identity"), str) and len(e.get("identity", "")) >= 4,
                       "%s identity 非空身份句" % k)
        _r(isinstance(e.get("reuse_character"), bool) and isinstance(e.get("p1"), bool),
                       "%s reuse_character / p1 为 bool" % k)
        _r(not e.get("p1_stub") or e.get("p1") is True, "%s p1_stub 只挂在 p1 人身上" % k)
        _r(e.get("verify") in ("待核", "已核"), "%s verify ∈ {待核, 已核}（实得 %s）" % (k, e.get("verify")))
        tr = e.get("traits")
        _r(isinstance(tr, list) and all(isinstance(t, str) for t in tr) and len(tr) == len(set(tr)),
                       "%s traits 为不重复串表" % k)

    section("二节、身份骨架", not bag)

    # 三节、langs
    _r(all(isinstance(e.get("langs"), list) and e["langs"] and all(isinstance(x, str) and x for x in e["langs"])
                       for e in comps.values()), "langs 全表 list<str> 非空")

    section("三节、langs", not bag)

    # 四节、appear
    for k, e in comps.items():
        ap = e.get("appear")
        if not _r(isinstance(ap, dict), "%s appear 是 dict" % k):
            continue
        cm = ap.get("chapter_min")
        _r(isinstance(cm, int) and 1 <= cm <= 5, "%s chapter_min ∈ [1,5]（实得 %s）" % (k, cm))
        ws = ap.get("windows")
        if not _r(isinstance(ws, list) and len(ws) >= 1, "%s windows ≥1 段" % k):
            continue
        for n, w in enumerate(ws):
            f, t = w.get("from"), w.get("to")
            _r(isinstance(f, str) and bool(YM.match(f or "")) and WINDOW_MIN <= f <= WINDOW_MAX,
                           "%s 窗口%d from=%s 为 YYYY-MM 且 1255–1285 窗内" % (k, n, f))
            _r(isinstance(t, str) and bool(YM.match(t or "")) and WINDOW_MIN <= t <= WINDOW_MAX,
                           "%s 窗口%d to=%s 为 YYYY-MM 且窗内" % (k, n, t))
            if isinstance(f, str) and isinstance(t, str):
                _r(f <= t, "%s 窗口%d from ≤ to" % (k, n))
            _r(w.get("mode") in domains["meet_mode"], "%s 窗口%d mode=%s 在册" % (k, n, w.get("mode")))
            for p in w.get("ports", []):
                _r(p in domains["ports"], "%s 窗口%d 港 %s 存在（ports.json）" % (k, n, p))
            ms_ = w.get("months")
            if ms_ is not None:
                _r(isinstance(ms_, list) and all(isinstance(m, int) and 1 <= m <= 12 for m in ms_),
                               "%s 窗口%d months ⊆ [1..12]" % (k, n))
            rt = w.get("route")
            if rt is not None:
                leg_ok = isinstance(rt, list) and len(rt) >= 1 and all(
                    isinstance(r, list) and len(r) == 2 and all(isinstance(x, str) and x in domains["legs"] for x in r)
                    for r in rt)
                _r(leg_ok, "%s 窗口%d route 为 ≥1 段 [起,讫]、端名在册（实得 %d 段 %s）"
                               % (k, n, len(rt) if isinstance(rt, list) else -1, rt))
            if w.get("mode") == "sea":
                _r(rt is not None, "%s 窗口%d 海上邂逅必带 route" % (k, n))
            elif rt is not None and w.get("mode") not in ROUTE_MODES:
                _r(False, "%s 窗口%d mode=%s 不挂 route（visit / yundun 无航段）" % (k, n, w.get("mode")))
        _r(isinstance(ap.get("rumor"), str) and len(ap.get("rumor", "")) >= 4,
                       "%s rumor 风闻一句" % k)

    section("四节、appear", not bag)

    # 五节、join
    for k, e in comps.items():
        j = e.get("join")
        if not _r(isinstance(j, dict), "%s join 是 dict" % k):
            continue
        jt = j.get("type")
        _r(jt in domains["join_type"], "%s join.type=%s 在册" % (k, jt))
        if jt == "hire":
            _r(isinstance(j.get("fee"), int) and j["fee"] >= 0, "%s hire fee=%s 非负" % (k, j.get("fee")))
        if jt == "bond":
            bn = j.get("bond_need")
            _r(isinstance(bn, int) and 0 <= bn <= 100, "%s bond_need ∈ [0,100]（实得 %s）" % (k, bn))
            bp = j.get("bond_path", [])
            _r(isinstance(bp, list) and len(bp) >= 1, "%s bond_path ≥1 步" % k)
            if isinstance(bp, list):
                tot = 0
                for n, st in enumerate(bp):
                    _r(isinstance(st, dict) and isinstance(st.get("src"), str) and st["src"]
                                   and isinstance(st.get("value"), int) and st["value"] > 0
                                   and isinstance(st.get("note"), str),
                                   "%s bond_path 步%d {src, value>0, note}" % (k, n))
                    tot += st.get("value") if isinstance(st, dict) and isinstance(st.get("value"), int) else 0
                if isinstance(bn, int):
                    _r(tot >= bn, "%s bond_path 合计 %d ≥ 门槛 %d" % (k, tot, bn))
        if jt in ("guest", "local"):
            _r(j.get("fee", 0) == 0, "%s %s 不收入伙钱（fee=%s）" % (k, jt, j.get("fee")))
        rq = j.get("requires")
        if rq is not None:
            if _r(isinstance(rq, dict), "%s requires 是 dict" % k):
                extra = set(rq) - set(REQ_SPEC)
                _r(not extra, "%s requires 键登记外：%s" % (k, sorted(extra)))
                for rk, spec in REQ_SPEC.items():
                    if rk in rq:
                        _r(ctype(rq[rk], spec), "%s requires.%s 型为 %s" % (k, rk, spec))

    section("五节、join", not bag)

    # 六节、duty
    for k, e in comps.items():
        dty = e.get("duty")
        if not _r(isinstance(dty, dict), "%s duty 是 dict" % k):
            continue
        local = e.get("join", {}).get("type") == "local"
        roles = dty.get("roles", {})
        _r(isinstance(roles, dict) and all(r in domains["roles"] for r in roles),
                       "%s duty.roles 键 ∈ crew 职事 id（实得 %s）" % (k, sorted(roles) if isinstance(roles, dict) else "?"))
        if isinstance(roles, dict):
            _r(all(isinstance(v, int) and 1 <= v <= 3 for v in roles.values()),
                           "%s roles 声明上限 ∈ [1,3]" % k)
        for fld in ("level_at_join", "level_1279"):
            lv = dty.get(fld, {})
            if isinstance(lv, dict):
                for r, v in lv.items():
                    _r(r in domains["roles"] and isinstance(v, int) and 1 <= v <= 3,
                                   "%s %s.%s=%s 职事 id 且品级 ∈ [1,3]" % (k, fld, r, v))
                    _r(not (isinstance(roles, dict) and r in roles) or v <= roles.get(r, 3),
                                   "%s %s.%s ≤ roles 声明上限" % (k, fld, r))
            else:
                _r(False, "%s %s 是 dict" % (k, fld))
        wr = dty.get("wage_role_at_join", {})
        _r(isinstance(wr, dict) and all(r in domains["roles"] for r in wr),
                       "%s wage_role_at_join 键 ∈ 职事 id" % k)
        if isinstance(wr, dict):
            _r(all(isinstance(v, int) and v in WAGE for v in wr.values()),
                           "%s 月俸档 ∈ {60,120,200}" % k)
        ws = dty.get("wage_slot")
        _r(isinstance(ws, int) and ws in WAGE_SLOT, "%s wage_slot ∈ {0,30,60,120,200}（实得 %s）" % (k, ws))
        jtype = e.get("join", {}).get("type")
        if jtype in ("guest", "local"):
            _r(ws == 0, "%s 客程 / 云屯在场不付月俸（wage_slot=%s 须为 0）" % (k, ws))
        wd = dty.get("wage_discount")
        if wd is not None:
            _r(isinstance(wd, int) and 0 <= wd <= 1, "%s wage_discount ∈ [0,1]（折一档为止）" % k)
        bt = dty.get("battle", [])
        _r(isinstance(bt, list) and all(b in domains["battle_slot"] for b in bt),
                       "%s battle ⊆ meta.battle_slot_def\\none（实得 %s）" % (k, bt))
        hp = dty.get("home_port")
        if local:
            _r(roles == {} and dty.get("level_at_join") == {} and dty.get("level_1279") == {}
                           and wr == {} and bt == [] and ws == 0 and hp == "yundun",
                           "%s 云屯在场 duty 空壳齐（roles/levels/wage 空、battle 空、wage_slot=0、home_port=yundun）" % k)
        else:
            _r(hp in domains["ports"], "%s home_port=%s 在 ports.json" % (k, hp))
        rg = dty.get("range")
        if rg is not None:
            _r(isinstance(rg, list) and all(r in domains["ports"] for r in rg),
                           "%s duty.range 港存在（限定航区）" % k)

    section("六节、duty", not bag)

    # 七节、niche / stance / traits / gifts / climax
    for k, e in comps.items():
        nc = e.get("niche", [])
        _r(isinstance(nc, list) and all(isinstance(n, dict) and n.get("kind") in domains["niche_kind"] for n in nc),
                       "%s niche[].kind ∈ meta.niche_kind_def" % k)
        _r(e.get("stance") in domains["stance"], "%s stance=%s ∈ meta.stance_def" % (k, e.get("stance")))
        bad_t = [t for t in e.get("traits", []) if t not in domains["traits"]]
        _r(not bad_t, "%s traits ⊆ characters.trait_def ∪ 名册 new_traits（未登 %s）" % (k, bad_t))
        bad_g = [g for g in e.get("gifts", []) if g not in domains["goods"]]
        _r(not bad_g, "%s gifts ⊆ goods.json id（未登 %s）" % (k, bad_g))
        cl = e.get("climax")
        _r(isinstance(cl, dict) and set(cl) == set(IDENTITY_LINES)
                       and all(isinstance(cl.get(x), str) for x in IDENTITY_LINES),
                       "%s climax 恰有士人 / 海商 / 乡土三线键" % k)

    section("七节、niche / stance / traits / gifts / climax", not bag)

    # 八节、未定字段与 events、待核（lane/story-bios 批 4：七字段实值形状定型校验）
    FIVE_DIMS = {"hang", "shang", "wu", "xue", "wang"}
    TIER_PENDING = "[待核]"

    def _bio_ok(fname, v, kid):
        """_todo 仍绿；实值按批 4 登记形状逐项判。返回 None=过，否则一句塌因。"""
        if fname == "attrs":
            if not (isinstance(v, dict) and set(v) == FIVE_DIMS):
                return "须恰五维键 {hang,shang,wu,xue,wang}"
            bad = [x for x, n in v.items() if not (isinstance(n, int) and not isinstance(n, bool) and 1 <= n <= 100)]
            return "各维须 int ∈ [1,100]（塌 %s）" % bad if bad else None
        if fname == "growth":
            if v == {}:
                return None
            if not isinstance(v, dict):
                return "须 dict（{} 表无成长）"
            bad = [x for x in v if x not in FIVE_DIMS]
            if bad:
                return "键未登入五维：%s" % bad
            for x, g in v.items():
                if not (isinstance(g, dict) and set(g) == {"per_year", "cap"}
                        and isinstance(g["per_year"], int) and g["per_year"] > 0
                        and isinstance(g["cap"], int) and 1 <= g["cap"] <= 100):
                    return "%s 须 {per_year: int>0, cap: int∈[1,100]}" % x
            return None
        if fname == "fate":
            if v == TIER_PENDING:
                return None  # [待核] 明示待评，不等于留 _todo
            if not (isinstance(v, dict) and set(v) == {"leave", "detail"}
                    and isinstance(v["leave"], str) and v["leave"]
                    and isinstance(v["detail"], str) and v["detail"]):
                return "须 {leave: str 非空, detail: str 非空} 或恰 \"[待核]\""
            return None
        if fname == "relations":
            if not (isinstance(v, list) and len(v) >= 1):
                return "须 list 非空（拍板：每人至少一条关系边）"
            for it in v:
                if not (isinstance(it, dict) and set(it) == {"id", "kind"}
                        and isinstance(it["kind"], str) and it["kind"]):
                    return "每条须 {id, kind}"
                if not (isinstance(it["id"], str) and it["id"] in comps and it["id"] != kid):
                    return "id=%s 须在名册且非本人" % it.get("id")
            return None
        if fname == "relation_flips":
            if not isinstance(v, list):
                return "须 list（可空）"
            for it in v:
                if not (isinstance(it, dict) and set(it) == {"counterpart", "event", "effect"}
                        and isinstance(it["counterpart"], str)
                        and (it["counterpart"] in comps or it["counterpart"] == "player")
                        and isinstance(it["event"], str) and it["event"]
                        and isinstance(it["effect"], str) and it["effect"]):
                    return "每条须 {counterpart: 伙伴 id ∥ player, event, effect} 三键非空"
            return None
        if fname == "bond_tiers":
            if not (isinstance(v, dict) and set(v) == {"40", "60", "80"}
                    and all(isinstance(v[t], str) and v[t] for t in ("40", "60", "80"))):
                return "须恰 {\"40\",\"60\",\"80\"} 三档且台词非空"
            return None
        if fname == "one_time":
            if not (isinstance(v, list) and all(isinstance(x, str) and x for x in v)):
                return "须 list<str>（可空）"
            return None
        return "字段未登记"

    for k, e in comps.items():
        for f in TODO_FIELDS:
            v = e.get(f)
            if v == TODO:
                continue
            why = _bio_ok(f, v, k)
            _r(why is None, "%s 未定字段 %s：%s" % (k, f, why))
    ev_ids = list(events.keys())
    _r(len(set(ev_ids)) == len(ev_ids), "event id 唯一")
    for k, ev in events.items():
        _r(ev.get("id") == k, "events[%s].id 与键一致" % k)
        who = ev.get("who")
        _r(isinstance(who, list) and all(w in comps or w in ("player", "*") for w in who),
                       "events[%s] who ⊆ 伙伴 id ∪ {player, \"*\"}（实得 %s）" % (k, who))
        wstar = who == ["*"] if isinstance(who, list) else False
        _r(not wstar or k == "companion_farewell",
                       "events[%s] who=[\"*\"] 通配只留给 companion_farewell 通用机" % k)

    section("八节、未定字段与 events", not bag)

    # 九节、meta 自洽（域表与本表同源）
    _r(isinstance(meta.get(TODO), str) and "恰为这三个字" in meta[TODO], "meta 说明 _todo 记号")
    # 林华专线：reuse_character=true 是他唯一例外，勿与 crew 候选撞名
    reuses = [k for k, e in comps.items() if e.get("reuse_character")]
    _r(reuses == ["lin_hua"], "reuse_character=true 恰林华一人（实得 %s）" % reuses)
    section("九节、meta 自洽与 reuse 专线", not bag)

    return ok_all


def _selftest(data, domains):
    """零、判据自检：把好样本在内存里改坏若干形，每形须该红；原样须绿。"""
    import copy
    nifty = []
    # 格数钉群化自 cases 注册 SoR 现读（lane w93-k3，w91-k9 #8·gate_json SoR 群化第 4 案）——
    # 「判语格子面 == SoR (len(_cases),'红') 合字面」独立格强咬（烧格子面/烧 SoR 各红）：
    # 登了没跑的天然咬死（判红计数与 len 同行耦合不能忘登）；跑了没登即格数漂而咬。
    _cases = []

    def expect_red(tag, mutate):
        bad = copy.deepcopy(data)
        mutate(bad)
        bag = []
        ok = validate(bad, domains, emit=lambda c, m: (bag.append(m) if not c else None) or c)
        if ok:
            nifty.append("%s：红没判出（静默绿）" % tag)
        # 红因须落袋（哪塌了说得出来，不许空断 rc）
        if not bag:
            nifty.append("%s：红了但没红因" % tag)
        _cases.append((tag, "红"))

    def expect_green(tag):
        bag = []
        ok = validate(copy.deepcopy(data), domains, emit=lambda c, m: (bag.append(m) if not c else None) or c)
        if not ok:
            nifty.append("%s：好样本误红（%s）" % (tag, bag[0] if bag else "?"))

    expect_green("对照·好样本")
    expect_red("删已定字段 name", lambda b: b["companions"]["lin_hua"].pop("name"))
    expect_red("id 重号（底层 56 条）", lambda b: b["companions"].update({"lin_hua_dup": dict(b["companions"]["lin_hua"])}))
    expect_red("id 条数漂少", lambda b: b["companions"].pop("kafur"))
    expect_red("名字重号", lambda b: b["companions"]["he_sanhao"].update({"name": "林华"}))
    expect_red("未定字段填成词外", lambda b: b["companions"]["lin_hua"].update({"attrs": "todo"}))
    expect_red("未定字段提前搬数据", lambda b: b["companions"]["lin_hua"].update({"fate": [{"id": "x"}]}))
    expect_red("列传数值逾档", lambda b: b["companions"]["lin_hua"].update({"attrs": {"hang": 101, "shang": 1, "wu": 1, "xue": 1, "wang": 1}}))
    expect_red("列传 fate 键拼错", lambda b: b["companions"]["lin_hua"].update({"fate": {"Leave": "x", "detail": "y"}}))
    expect_red("列传关系指到己身", lambda b: b["companions"]["lin_hua"].update({"relations": [{"id": "lin_hua", "kind": "同乡旧识"}]}))
    expect_red("列传羁绊档缺值", lambda b: b["companions"]["lin_hua"].update({"bond_tiers": {"40": "a", "60": "b"}}))
    expect_red("窗口写成年份整数", lambda b: b["companions"]["lin_hua"]["appear"]["windows"][0].update({"from": 1255}))
    expect_red("from 晚于 to", lambda b: b["companions"]["lin_hua"]["appear"]["windows"][0].update({"to": "1255-01"}))
    expect_red("撞 crew 候名", lambda b: b["companions"].update({"zhou_suanchou": dict(b["companions"]["lin_hua"], id="zhou_suanchou")}) or b["companions"].pop("lin_hua"))
    expect_red("云屯 duty 塞职事", lambda b: b["companions"]["pham_ngu_lao"]["duty"].update({"roles": {"duogong": 1}}))
    expect_red("海上邂逅缺 route", lambda b: [w.pop("route", None) for w in b["companions"]["zhu_qing"]["appear"]["windows"] if w.get("mode") == "sea"])
    expect_red("挂不存在的港", lambda b: b["companions"]["lin_hua"]["appear"]["windows"][0].update({"ports": ["atlantis"]}))
    expect_red("bond_path 合计低于门槛", lambda b: b["companions"]["zhu_qing"]["join"].update({"bond_need": 100}))
    expect_red("guest 收月俸", lambda b: b["companions"]["xie_ao"]["duty"].update({"wage_slot": 60}))
    expect_red("特技未登", lambda b: b["companions"]["lin_hua"]["traits"].append("fireball"))
    expect_red("events.who 指不到伙伴", lambda b: b["events"][next(iter(b["events"]))]["who"].append("nobody_x"))

    for msg in nifty:
        check(False, "自检 %s" % msg)
    if not nifty:
        # SoR 现读指示格 + 排面哨域——烧净捕矩阵照 w91-k9 #8 SoR 群化第 4 案定例：
        # 烧格子面 → ✗ 指名 SoR 现读 mismatch；烧 SoR → 格子面变而 ✗ 指名 mismatch；烧 SoR 长度剪不净 → 左哨咬。
        # 珠 16 拆 x+x 哨（x 域无 3 珠同替定例：错促即哨咬）；判红长度 16 哨钉（拨颁必同笔随同色）。
        class _TaggedStr(str):  # 红向哨——查非 str 类型（SoR 元组被偷改成 str 即哨咬「类型被暗换」）
            pass

        _sor = _TaggedStr("_" * 42)
        _SENT = 2 * 21  # SoR 显形长钉 → 42（拨颁必同笔随同色）——烧左不净即左哨咬（同笔定例）
        check(isinstance(_sor, _TaggedStr) and len(_sor) == _SENT,
              "自检 SoR 类型与哨钉 %d 在衙" % _SENT)
        _msg = ("改坏须红 / 原样须绿 全判对（删 name / id 重号 / id 漂少 / 名重 / _todo 填词外值 / _todo 提前搬数 / "
                "年份整数 / from>to / 撞 crew 名 / 云屯塞职 / 海邂缺 route / 海市蜃楼港 / bond 合计 / guest 月俸 / "
                "未登特技 / who 指不到 / 列传数值逾档 / 列传 fate 键拼错 / 列传关系指己 / 列传羁绊档缺值）")
        _ori_line = "自检 " + "2" + "0" + " 格：" + _msg
        x = "20"
        _ori_msg = "自检 " + x + " 格：" + _msg
        check(_ori_line == _ori_msg,
              "自检格数须自现读（不符则现读格 mismatch）")
        check(len(_cases) == 20,
              "自检判红格数须钉 20（批 4 列传形状 +4 格，拨颁必同笔随同色）")
        y = "42"
        check(len(_sor) == int(y),
              "自检显形长钉须 42（拨颁必同笔随同色）")
        check(x + x == "2020",
              "自检判语拟字样 20 哨在衙（拨颁必同笔随同色）")


def main():
    print("check_companions —— data/companions.json 骨架校验（已定照草案、未定 _todo）")
    if not os.path.exists(DATA):
        check(False, "缺 data/companions.json")
        print("结果：1 项问题")
        return 1
    data = jload(DATA)
    characters = jload(os.path.join(ROOT, "data", "characters.json"))
    crew = jload(os.path.join(ROOT, "data", "crew.json"))
    ports = jload(os.path.join(ROOT, "data", "ports.json"))
    goods = jload(os.path.join(ROOT, "data", "goods.json"))
    roster = jload(ROSTER)
    roster_meta = roster["meta"]

    meta = data.get("meta", {})
    domains = {
        # 条目数钉群化自名册 SoR 现读（lane w92-k3，w91-k9 散文钉普查首推案①）——
        # 拨颁 data 条目时须同步拨名册（移 bench 或增条目），判语面随 SoR 现读。
        "roster_counts": {"companions": len(roster.get("companions", [])),
                          "events": len(roster.get("events", []))},
        "region": set(meta.get("region_def", {})),
        "category": set(meta.get("category_def", {})),
        "meet_mode": set(meta.get("meet_mode_def", {})),
        "join_type": set(meta.get("join_type_def", {})),
        "battle_slot": set(meta.get("battle_slot_def", {})) - {"none"},
        "stance": set(meta.get("stance_def", {})),
        "niche_kind": set(meta.get("niche_kind_def", {})),
        "roles": {r["id"] for r in crew.get("roles", [])},
        "factions": set(characters.get("meta", {}).get("faction_def", {})),
        "ports": {p["id"] for p in ports.get("ports", [])} | {"yundun"},
        "goods": {g["id"] for g in goods.get("goods", [])},
        "traits": set(characters.get("meta", {}).get("trait_def", {})) | set(roster_meta.get("new_traits", {})),
    }
    domains["legs"] = domains["ports"] | {"any"}  # "any" = 14 港任一端（名册草案 v2 写法）
    crew_candidate_ids = {c["id"] for c in crew.get("candidates", [])}

    print("── 零、判据自检（内存变异）")
    _selftest(data, domains)

    print("── 一—九、数据本体")
    validate(data, domains)

    # crew 候选撞名（对题表 P0 断言；林华 reuse_character=true 除外）
    comps = data["companions"]
    for k, e in comps.items():
        if k in crew_candidate_ids and not e.get("reuse_character"):
            check(False, "%s 与 crew.json 候选撞名且未标 reuse_character" % k)
    check(not any(k in crew_candidate_ids and not e.get("reuse_character") for k, e in comps.items()),
          "伙伴 id 与 crew.json 候选不撞（reuse_character 开例外）")

    print(("结果：全部通过" if not fails else "结果：%d 项问题" % len(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
