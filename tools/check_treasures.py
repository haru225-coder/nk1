#!/usr/bin/env python3
"""data/treasures.json 骨架校验门禁（lane treas1/treas2，宝物系统 v1/v2）。

宝物是单件收藏，不是 bulk cargo：本闸只读 data/treasures.json，域从仓内现算：
港 id 读 data/ports.json，发现 id 读 data/discoveries.json，货 id / 名读 data/goods.json，
职事 id 读 data/crew.json 的 roles 与 data/companions.json 的 duty.roles。

判词：
  零、判据自检（GATES §五.3，内存变异不落盘）：删字段 / id 重号 / 名字重号 / 类目越域 /
    品第计数错 / 价越界 / 港不存在 / 发现不存在 / 无来源 / effect 越域 / 职事不存在 /
    非 GB2312 / era_note 重句 / 年号物名越界 / 撞货名 / 待鉴数错 / event-only /
    传闻港 / 近港越界 / 传闻 hint 非 GB2312，各退一格须红；好样本须绿。
  一、顶层：meta 标题 / 年代 / 说明非空；treasures 恰 27 条。
  二、身份：字段恰登记键；id 蛇形唯一、name 唯一；不与 goods id / name 撞。
  三、品第与类目：category ∈ 七类；grade ∈ 甲乙丙丁；甲 3 / 乙 12 / 丙 10 / 丁 2。
  四、价与出处：value 120–2600；origin 非空；era_note 非空、GB2312、无明清年号物名。
  五、来源：sources 非空；shop 港在 ports；discovery 在 discoveries；rumor 港 / 近港在 ports、
    hint 非空且 GB2312；event 只作形态；每件至少一条 shop / discovery / rumor；
    恰 7 个售港、恰 5 个发现钩子、恰 5 件传闻宝物。
  六、效果：kind ∈ fame / duty / appraise_only；fame 额 > 0；duty 职事在册、bonus ≥ 1；
    duty_note 可选，给了须为 GB2312。
  七、待鉴：unidentified_name 可选、非空、GB2312；恰 6 件。
  八、文案：era_note 逐条不同；首尾六字不同；任意 8 字窗不跨条重复。
交主控：python3 tools/check_treasures.py（纯 stdlib、只读、< 1 s）
"""
import copy
import json
import os
import re
import sys

if "--json" in sys.argv[1:]:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json
    gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "treasures.json")
EXPECT_COUNT = 27
GRADE_COUNT = {"甲": 3, "乙": 12, "丙": 10, "丁": 2}
CATEGORIES = {"瓷器", "茶器", "香药", "铜器", "书画碑帖", "航海器物", "舶来"}
SHOP_HOOKS = {"quanzhou", "mingzhou", "guangzhou", "hakata", "champa", "wenzhou", "fuzhou"}
DISC_HOOKS = {"penghu_channel", "jiuri_wind_stele", "champa_old_port", "lingshan_tombs", "qingjing_arabic_gate"}
RUMOR_HOOKS = {"sunk_cargo_porcelain", "houzhu_sunk_incense", "goryeo_silver_inlay_kundika",
               "champa_ivory_carving", "srivijaya_rhino_horn"}
ITEM_KEYS = {"id", "name", "unidentified_name", "category", "grade", "value", "origin", "era_note", "sources", "effect", "duty_note"}
ANACHRONISM = ("宣德", "青花", "成化", "景泰蓝", "紫砂", "珐琅", "粉彩", "五彩", "斗彩",
               "洪武", "永乐", "嘉靖", "万历", "康熙", "雍正", "乾隆", "嘉庆", "道光",
               "同治", "光绪", "民国", "郑和", "哥窑")

fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def jload(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def is_int(v):
    return type(v) is int


def gb(text):
    if not isinstance(text, str) or text == "":
        return False
    try:
        text.encode("gb2312")
        return True
    except UnicodeEncodeError:
        return False


def norm_note(text):
    return re.sub(r"[\s，。；：、「」《》·]", "", text)


def _domains():
    ports = {str(p.get("id", "")) for p in jload(os.path.join(ROOT, "data", "ports.json")).get("ports", [])}
    discoveries = {str(d.get("id", "")) for d in jload(os.path.join(ROOT, "data", "discoveries.json")).get("discoveries", [])}
    goods_rows = jload(os.path.join(ROOT, "data", "goods.json")).get("goods", [])
    goods_ids = {str(g.get("id", "")) for g in goods_rows}
    goods_names = {str(g.get("name", "")) for g in goods_rows}
    roles = {str(r.get("id", "")) for r in jload(os.path.join(ROOT, "data", "crew.json")).get("roles", [])}
    comps = jload(os.path.join(ROOT, "data", "companions.json")).get("companions", {})
    for c in comps.values():
        for rid in (c.get("duty", {}) or {}).get("roles", {}):
            roles.add(str(rid))
    return ports, discoveries, goods_ids, goods_names, roles


def validate(data, domains):
    ports, discoveries, goods_ids, goods_names, roles = domains
    errs = []
    if not isinstance(data, dict):
        return ["顶层不是对象"]
    meta = data.get("meta", {})
    if not isinstance(meta, dict):
        return ["meta 不是对象"]
    for key, label in (("title", "标题"), ("era", "年代"), ("note", "说明")):
        if not gb(meta.get(key, "")):
            errs.append("meta.%s 缺失或不是 GB2312 文本" % label)
    rows = data.get("treasures", [])
    if not isinstance(rows, list):
        return errs + ["treasures 不是数组"]
    if len(rows) != EXPECT_COUNT:
        errs.append("宝物数 %d ≠ %d" % (len(rows), EXPECT_COUNT))

    ids = set()
    names = set()
    grades = {g: 0 for g in GRADE_COUNT}
    shops = set()
    discs = set()
    rumors = set()
    unids = 0
    notes = []
    for i, row in enumerate(rows):
        tag = "第 %d 条" % (i + 1)
        if not isinstance(row, dict):
            errs.append(tag + " 不是对象")
            continue
        unknown = set(row) - ITEM_KEYS
        if unknown:
            errs.append(tag + " 有未登记字段：%s" % "、".join(sorted(unknown)))
        for key in ITEM_KEYS - {"unidentified_name", "duty_note"}:
            if key not in row:
                errs.append(tag + " 缺字段 " + key)
        tid = row.get("id", "")
        if not isinstance(tid, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", tid):
            errs.append(tag + " id 不是蛇形小写")
        elif tid in ids:
            errs.append(tag + " id 重号 " + tid)
        else:
            ids.add(tid)
        tag = "第 %d 条 %s" % (i + 1, tid or "?")
        name = row.get("name", "")
        if not gb(name):
            errs.append(tag + " name 缺失或不是 GB2312")
        elif name in names:
            errs.append(tag + " name 重号 " + name)
        else:
            names.add(name)
        if isinstance(name, str) and (name in goods_names or name in goods_ids):
            errs.append(tag + " name 与货名撞车")
        if isinstance(tid, str) and tid in goods_ids:
            errs.append(tag + " id 与货 id 撞车")
        cat = row.get("category")
        if cat not in CATEGORIES:
            errs.append(tag + " category 越域 " + str(cat))
        grade = row.get("grade")
        if grade not in GRADE_COUNT:
            errs.append(tag + " grade 越域 " + str(grade))
        else:
            grades[grade] += 1
        value = row.get("value")
        if not is_int(value) or not (120 <= value <= 2600):
            errs.append(tag + " value 须为 120–2600 的整数")
        origin = row.get("origin", "")
        if not gb(origin):
            errs.append(tag + " origin 缺失或不是 GB2312")
        note = row.get("era_note", "")
        if not gb(note):
            errs.append(tag + " era_note 缺失或不是 GB2312")
        else:
            notes.append((tag, note))
            for bad in ANACHRONISM:
                if bad in note or (isinstance(name, str) and bad in name) or (isinstance(origin, str) and bad in origin):
                    errs.append(tag + " 含明清 / 后世名物「%s」" % bad)
        if "unidentified_name" in row:
            unid = row.get("unidentified_name")
            if not gb(unid):
                errs.append(tag + " unidentified_name 须为非空 GB2312")
            else:
                unids += 1
        if "duty_note" in row and not gb(row.get("duty_note")):
            errs.append(tag + " duty_note 须为非空 GB2312")

        sources = row.get("sources")
        if not isinstance(sources, list) or not sources:
            errs.append(tag + " sources 须为非空数组")
            sources = []
        kinds = set()
        has_obtain = False
        for src in sources:
            if not isinstance(src, dict):
                errs.append(tag + " sources 条目不是对象")
                continue
            st = src.get("type")
            kinds.add(st)
            if st == "shop":
                if set(src) != {"type", "port"}:
                    errs.append(tag + " shop 来源字段须恰为 type/port")
                port = str(src.get("port", ""))
                if port not in ports:
                    errs.append(tag + " shop 港不存在 " + port)
                else:
                    shops.add(port)
                    has_obtain = True
            elif st == "discovery":
                if set(src) != {"type", "id"}:
                    errs.append(tag + " discovery 来源字段须恰为 type/id")
                did = str(src.get("id", ""))
                if did not in discoveries:
                    errs.append(tag + " discovery 不存在 " + did)
                else:
                    discs.add(did)
                    has_obtain = True
            elif st == "rumor":
                if set(src) != {"type", "port", "near_ports", "hint"}:
                    errs.append(tag + " rumor 来源字段须恰为 type/port/near_ports/hint")
                port = str(src.get("port", ""))
                if port not in ports:
                    errs.append(tag + " rumor 港不存在 " + port)
                near = src.get("near_ports")
                if not isinstance(near, list) or not near:
                    errs.append(tag + " rumor near_ports 须为非空数组")
                else:
                    for np in near:
                        if not isinstance(np, str) or np not in ports:
                            errs.append(tag + " rumor near_ports 港不存在 " + str(np))
                    if port in ports and port not in near:
                        errs.append(tag + " rumor 港须列入 near_ports " + port)
                if not gb(src.get("hint")):
                    errs.append(tag + " rumor hint 须为非空 GB2312")
                if port in ports and isinstance(tid, str):
                    rumors.add(tid)
                has_obtain = True
            elif st == "event":
                if set(src) != {"type"}:
                    errs.append(tag + " event 来源只作形态，不得带条件")
            else:
                errs.append(tag + " source.type 越域 " + str(st))
        if not has_obtain:
            errs.append(tag + " 无 shop / discovery / rumor 获取途径")

        eff = row.get("effect")
        if not isinstance(eff, dict):
            errs.append(tag + " effect 不是对象")
        else:
            kind = eff.get("kind")
            if kind == "fame":
                if set(eff) != {"kind", "amount"} or not is_int(eff.get("amount")) or eff.get("amount", 0) <= 0:
                    errs.append(tag + " fame effect 须为 {kind, amount>0}")
            elif kind == "duty":
                if set(eff) != {"kind", "role", "bonus"}:
                    errs.append(tag + " duty effect 字段须恰为 kind/role/bonus")
                if str(eff.get("role", "")) not in roles:
                    errs.append(tag + " duty 职事不在册 " + str(eff.get("role", "")))
                if not is_int(eff.get("bonus")) or eff.get("bonus", 0) < 1:
                    errs.append(tag + " duty bonus 须为正整数")
            elif kind == "appraise_only":
                if set(eff) != {"kind"}:
                    errs.append(tag + " appraise_only 不得带参数")
            else:
                errs.append(tag + " effect.kind 越域 " + str(kind))

    if grades != GRADE_COUNT:
        errs.append("品第计数 %s ≠ %s" % (grades, GRADE_COUNT))
    if len(shops) != 7:
        errs.append("售港数 %d ≠ 7" % len(shops))
    if discs != DISC_HOOKS:
        errs.append("发现钩子 %s ≠ 登记五处" % sorted(discs))
    if rumors != RUMOR_HOOKS:
        errs.append("传闻宝物 %s ≠ 登记五件" % sorted(rumors))
    if unids != 6:
        errs.append("待鉴宝物 %d ≠ 6" % unids)

    frames = {}
    shingles = {}
    grams = {}
    for tag, note in notes:
        clean = norm_note(note)
        if note in frames:
            errs.append(tag + " era_note 与 %s 重句" % frames[note])
        else:
            frames[note] = tag
        frame = clean[:6] + "|" + clean[-6:]
        if frame in shingles:
            errs.append(tag + " era_note 首尾与 %s 同框" % shingles[frame])
        else:
            shingles[frame] = tag
        for j in range(max(0, len(clean) - 7)):
            gram = clean[j:j + 8]
            if gram in grams and grams[gram] != tag:
                errs.append(tag + " era_note 与 %s 共 8 字窗「%s」" % (grams[gram], gram))
                break
            grams[gram] = tag
    return errs


def _selftest(data, domains):
    good = validate(copy.deepcopy(data), domains)
    cases = []

    def case(tag, mutate, needle):
        bad = copy.deepcopy(data)
        mutate(bad)
        errs = validate(bad, domains)
        cases.append((tag, bool(errs), needle in "；".join(errs)))

    case("删字段", lambda b: b["treasures"][0].pop("origin"), "缺字段 origin")
    case("id 重号", lambda b: b["treasures"][1].__setitem__("id", b["treasures"][0]["id"]), "id 重号")
    case("名字重号", lambda b: b["treasures"][1].__setitem__("name", b["treasures"][0]["name"]), "name 重号")
    case("类目越域", lambda b: b["treasures"][0].__setitem__("category", "杂项"), "category 越域")
    case("品第计数", lambda b: b["treasures"][0].__setitem__("grade", "乙"), "品第计数")
    case("价越界", lambda b: b["treasures"][0].__setitem__("value", 1), "value 须为")
    case("港不存在", lambda b: b["treasures"][0]["sources"][0].__setitem__("port", "atlantis"), "shop 港不存在")
    case("发现不存在", lambda b: b["treasures"][4]["sources"][0].__setitem__("id", "nowhere"), "discovery 不存在")
    case("无来源", lambda b: b["treasures"][0].__setitem__("sources", []), "sources 须为非空")
    case("event-only", lambda b: b["treasures"][0].__setitem__("sources", [{"type": "event"}]), "无 shop / discovery")
    case("效果越域", lambda b: b["treasures"][0].__setitem__("effect", {"kind": "buff"}), "effect.kind 越域")
    case("职事不存在", lambda b: b["treasures"][6].__setitem__("effect", {"kind": "duty", "role": "nobody", "bonus": 1}), "职事不在册")
    case("非 GB2312", lambda b: b["treasures"][0].__setitem__("era_note", b["treasures"][0]["era_note"] + "彧"), "GB2312")
    case("重句", lambda b: b["treasures"][1].__setitem__("era_note", b["treasures"][0]["era_note"]), "重句")
    case("后世物名", lambda b: b["treasures"][0].__setitem__("name", "青花瓷瓶"), "后世名物")
    case("撞货名", lambda b: b["treasures"][0].__setitem__("name", "青白瓷"), "与货名撞车")
    case("待鉴数错", lambda b: b["treasures"][0].pop("unidentified_name"), "待鉴宝物")
    case("传闻港不存在", lambda b: b["treasures"][22]["sources"][0].__setitem__("port", "atlantis"), "rumor 港不存在")
    case("传闻近港不存在", lambda b: b["treasures"][22]["sources"][0]["near_ports"].__setitem__(0, "atlantis"), "near_ports 港不存在")
    case("传闻 hint 非 GB2312", lambda b: b["treasures"][22]["sources"][0].__setitem__("hint", "老渔人说彧"), "rumor hint")
    case("传闻件数错", lambda b: b["treasures"][22].__setitem__("id", "sunk_cargo_porcelain_x"), "传闻宝物")
    case("duty_note 非 GB2312", lambda b: b["treasures"][6].__setitem__("duty_note", "火长彧"), "duty_note")

    ok = not good
    check(ok, "自检好样本须绿%s" % ("" if ok else "（塌因：%s）" % "；".join(good[:5])))
    for tag, red, needle in cases:
        check(red and needle, "自检 %s 须红且点名" % tag)
    return True


def main():
    data = jload(DATA)
    domains = _domains()
    print("守护 data/treasures.json：%d 件" % len(data.get("treasures", [])))
    _selftest(data, domains)
    errs = validate(data, domains)
    for err in errs:
        check(False, err)
    if not errs:
        check(True, "顶层 / 身份 / 品第 / 来源 / 效果 / 待鉴 / 文案 全对")
    print("结果：" + ("全部通过" if not fails else "%d 项问题" % len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
