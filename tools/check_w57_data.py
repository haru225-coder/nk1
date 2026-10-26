#!/usr/bin/env python3
"""城区数据交叉校验（lane w57）：data/districts.json 与 data/districts_pending/*.json。

只读。校验：district / interaction id 全局唯一；港存在或标 pending_port；货在 goods.json；
传闻的港与货有市面；非市面的买卖 impact 须为 false；require_flag 须在某处 effects.flag 里产出；
公凭 id 一致；成本、数量、price_mul、入股数组合理。"""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWED_TYPES = {"buy", "sell", "invest", "hire", "rumor", "favour", "licence", "choice"}
ALLOWED_UNLOCK = {
    "year_min", "year_max", "years", "months", "chapter_min", "war_in", "war_not",
    "require_flag", "hide_if_flag", "favour_min", "needs_licence", "needs_hire",
    "siege", "exam",
}
EXAM_YEARS = [1256, 1259, 1262, 1265, 1268, 1271, 1274]
EXAM_MONTHS = [8, 9, 10]


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def main():
    errors = []
    ports = {p["id"]: p for p in load_json(os.path.join(ROOT, "data", "ports.json"))["ports"]}
    goods = {g["id"]: g for g in load_json(os.path.join(ROOT, "data", "goods.json"))["goods"]}

    files = [os.path.join(ROOT, "data", "districts.json")]
    files += sorted(glob.glob(os.path.join(ROOT, "data", "districts_pending", "*.json")))

    all_rows = []  # (source, district)
    for path in files:
        rel = os.path.relpath(path, ROOT)
        try:
            data = load_json(path)
        except Exception as e:
            errors.append(f"{rel}: JSON 读不了：{e}")
            continue
        if not isinstance(data, dict) or not isinstance(data.get("districts"), list):
            errors.append(f"{rel}: 顶层须为 {{\"districts\":[...]}}")
            continue
        for row in data["districts"]:
            if not isinstance(row, dict):
                errors.append(f"{rel}: district 条目不是对象")
                continue
            all_rows.append((rel, row))

    # unique ids
    district_ids = [r["id"] for _, r in all_rows if isinstance(r.get("id"), str)]
    for did in sorted({x for x in district_ids if district_ids.count(x) > 1}):
        errors.append(f"district id 重复：{did}")
    interaction_ids = []
    for _, row in all_rows:
        for ix in row.get("interactions", []) if isinstance(row.get("interactions"), list) else []:
            if isinstance(ix, dict) and isinstance(ix.get("id"), str):
                interaction_ids.append(ix["id"])
    for iid in sorted({x for x in interaction_ids if interaction_ids.count(x) > 1}):
        errors.append(f"interaction id 重复：{iid}")

    # licence ids
    licence_defs = []
    for _, row in all_rows:
        for ix in row.get("interactions", []) if isinstance(row.get("interactions"), list) else []:
            if isinstance(ix, dict) and ix.get("type") == "licence" and isinstance(ix.get("licence"), str):
                licence_defs.append(ix["licence"])
    for lic in sorted({x for x in licence_defs if licence_defs.count(x) > 1}):
        errors.append(f"licence id 重复：{lic}")

    # hire ids
    hire_ids = {ix["id"] for _, row in all_rows for ix in (row.get("interactions") or [])
                if isinstance(ix, dict) and ix.get("type") == "hire" and isinstance(ix.get("id"), str)}

    # produced flags
    produced_flags = set()
    for _, row in all_rows:
        for ix in row.get("interactions", []) if isinstance(row.get("interactions"), list) else []:
            if not isinstance(ix, dict):
                continue
            for container in (ix,):
                eff = container.get("effects")
                if isinstance(eff, dict) and isinstance(eff.get("flag"), str):
                    produced_flags.add(eff["flag"])
            for opt in ix.get("options", []) if isinstance(ix.get("options"), list) else []:
                if isinstance(opt, dict):
                    eff = opt.get("effects")
                    if isinstance(eff, dict) and isinstance(eff.get("flag"), str):
                        produced_flags.add(eff["flag"])
    required_flags = set()
    for _, row in all_rows:
        for holder in (row,):
            u = holder.get("unlock")
            if isinstance(u, dict) and isinstance(u.get("require_flag"), str):
                required_flags.add(u["require_flag"])
        for ix in row.get("interactions", []) if isinstance(row.get("interactions"), list) else []:
            if isinstance(ix, dict):
                u = ix.get("unlock")
                if isinstance(u, dict) and isinstance(u.get("require_flag"), str):
                    required_flags.add(u["require_flag"])
    for flag in sorted(required_flags - produced_flags):
        errors.append(f"require_flag 未在任何 effects.flag 产出：{flag}")

    for source, row in all_rows:
        did = row.get("id")
        loc = f"{source} {did}" if isinstance(did, str) and did else source
        if not isinstance(did, str) or not did:
            errors.append(f"{source}: district.id 须为非空字符串")
            did = "?"
        port = row.get("port")
        if not isinstance(port, str) or not port:
            errors.append(f"{loc}: port 须为非空字符串")
            port = ""
        if not isinstance(row.get("name"), str) or not row["name"].strip() if isinstance(row.get("name"), str) else True:
            errors.append(f"{loc}: name 须为非空字符串")
        if not isinstance(row.get("kind"), str) or not (isinstance(row.get("kind"), str) and row["kind"].strip()):
            errors.append(f"{loc}: kind 须为非空字符串")
        if not isinstance(row.get("description"), str) or not (isinstance(row.get("description"), str) and row["description"].strip()):
            errors.append(f"{loc}: description 须为非空字符串")
        pending = source.startswith("data/districts_pending/")
        if pending and row.get("pending_art") is not True:
            errors.append(f"{loc}: pending 条目须写 pending_art: true")
        port_exists = port in ports
        pending_port = row.get("pending_port", False)
        if not port_exists:
            if pending_port is not True:
                errors.append(f"{loc}: 港 {port} 不在 ports.json，须标 pending_port: true")
        else:
            if pending_port is True:
                errors.append(f"{loc}: 港 {port} 已在 ports.json，不应标 pending_port: true")
        ru = row.get("unlock")
        if ru is not None:
            if not isinstance(ru, dict):
                errors.append(f"{loc}: unlock 须为对象")
            else:
                for k in ru:
                    if k not in ALLOWED_UNLOCK:
                        errors.append(f"{loc}: unlock 有未登记的键 {k}")
                if isinstance(ru.get("years"), list) and ru.get("years") != sorted(set(ru["years"])):
                    pass
                if "years" in ru and not (isinstance(ru["years"], list) and all(is_int(x) for x in ru["years"])):
                    errors.append(f"{loc}: unlock.years 须为整数数组")
                if "months" in ru and not (isinstance(ru["months"], list) and all(is_int(x) for x in ru["months"])):
                    errors.append(f"{loc}: unlock.months 须为整数数组")
                if "favour_min" in ru and not is_int(ru["favour_min"]):
                    errors.append(f"{loc}: unlock.favour_min 须为整数")
                if isinstance(ru.get("needs_licence"), str) and ru["needs_licence"] not in licence_defs:
                    errors.append(f"{loc}: unlock.needs_licence 指向不存在的公凭 {ru['needs_licence']}")
                if isinstance(ru.get("needs_hire"), str) and ru["needs_hire"] not in hire_ids:
                    errors.append(f"{loc}: unlock.needs_hire 指向不存在的雇人 {ru['needs_hire']}")

        ixs = row.get("interactions")
        if not isinstance(ixs, list) or not ixs:
            errors.append(f"{loc}: interactions 须为非空数组")
            ixs = []
        market = ports.get(port, {}).get("market", {}) if port_exists else {}
        for ix in ixs:
            if not isinstance(ix, dict):
                errors.append(f"{loc}: interaction 条目不是对象")
                continue
            iid = ix.get("id")
            ixloc = f"{loc} {iid}" if isinstance(iid, str) and iid else loc
            if not isinstance(iid, str) or not iid:
                errors.append(f"{ixloc}: interaction.id 须为非空字符串")
            elif iid == did:
                errors.append(f"{ixloc}: interaction.id 不可与 district.id 相同")
            typ = ix.get("type")
            if typ not in ALLOWED_TYPES:
                errors.append(f"{ixloc}: type 不认识：{typ}")
            if not isinstance(ix.get("label"), str) or not str(ix.get("label", "")).strip():
                errors.append(f"{ixloc}: label 须为非空字符串")
            if not isinstance(ix.get("text"), str) or not str(ix.get("text", "")).strip():
                errors.append(f"{ixloc}: text 须为非空字符串")
            if "cost" in ix:
                if not is_int(ix["cost"]) or ix["cost"] < 0:
                    errors.append(f"{ixloc}: cost 须为非负整数")
            u = ix.get("unlock")
            if u is not None:
                if not isinstance(u, dict):
                    errors.append(f"{ixloc}: unlock 须为对象")
                else:
                    for k in u:
                        if k not in ALLOWED_UNLOCK:
                            errors.append(f"{ixloc}: unlock 有未登记的键 {k}")
                    if "years" in u and not (isinstance(u["years"], list) and all(is_int(x) for x in u["years"])):
                        errors.append(f"{ixloc}: unlock.years 须为整数数组")
                    if "months" in u and not (isinstance(u["months"], list) and all(is_int(x) for x in u["months"])):
                        errors.append(f"{ixloc}: unlock.months 须为整数数组")
                    if "favour_min" in u and not is_int(u["favour_min"]):
                        errors.append(f"{ixloc}: unlock.favour_min 须为整数")
                    if isinstance(u.get("needs_licence"), str) and u["needs_licence"] not in licence_defs:
                        errors.append(f"{ixloc}: unlock.needs_licence 指向不存在的公凭 {u['needs_licence']}")
                    if isinstance(u.get("needs_hire"), str) and u["needs_hire"] not in hire_ids:
                        errors.append(f"{ixloc}: unlock.needs_hire 指向不存在的雇人 {u['needs_hire']}")
                    if u.get("exam") is True or ix.get("exam") is True:
                        pass
            if ix.get("exam") is True:
                g = ix.get("unlock", {})
                if not (isinstance(g, dict) and g.get("years") == EXAM_YEARS and g.get("months") == EXAM_MONTHS):
                    errors.append(f"{ixloc}: exam 的 years/months 须为大比之年月")
            if "cooldown_days" in ix and (not is_int(ix["cooldown_days"]) or ix["cooldown_days"] < 0):
                errors.append(f"{ixloc}: cooldown_days 须为非负整数")

            if typ in ("buy", "sell"):
                good = ix.get("good")
                if not isinstance(good, str) or good not in goods:
                    errors.append(f"{ixloc}: good 不在 goods.json：{good}")
                qty = ix.get("qty")
                if not is_int(qty) or qty <= 0:
                    errors.append(f"{ixloc}: qty 须为正整数")
                if "price_mul" in ix:
                    if not is_num(ix["price_mul"]) or ix["price_mul"] <= 0:
                        errors.append(f"{ixloc}: price_mul 须为正数")
                if "impact" in ix and not isinstance(ix["impact"], bool):
                    errors.append(f"{ixloc}: impact 须为布尔")
                if port_exists and isinstance(good, str) and good not in market:
                    if ix.get("impact", True) is True:
                        errors.append(f"{ixloc}: 货 {good} 不在港 {port} 市面，impact 须为 false")
            elif typ == "rumor":
                rport = ix.get("port")
                rgood = ix.get("good")
                if not isinstance(rport, str) or rport not in ports:
                    errors.append(f"{ixloc}: rumor.port 不在 ports.json：{rport}")
                if not isinstance(rgood, str) or rgood not in goods:
                    errors.append(f"{ixloc}: rumor.good 不在 goods.json：{rgood}")
                mul = ix.get("mul")
                if not is_num(mul) or mul <= 0 or mul == 1:
                    errors.append(f"{ixloc}: rumor.mul 须为正数且不为 1")
                if isinstance(rport, str) and rport in ports and isinstance(rgood, str) and rgood in goods:
                    if rgood not in ports[rport].get("market", {}):
                        errors.append(f"{ixloc}: 传闻货 {rgood} 不在港 {rport} 市面")
            elif typ == "invest":
                costs = ix.get("costs")
                monthly = ix.get("monthly")
                if not (isinstance(costs, list) and costs):
                    errors.append(f"{ixloc}: invest.costs 须为非空数组")
                    costs = []
                if not (isinstance(monthly, list) and monthly):
                    errors.append(f"{ixloc}: invest.monthly 须为非空数组")
                    monthly = []
                if len(costs) != len(monthly):
                    errors.append(f"{ixloc}: costs 与 monthly 长度不等")
                for i, c in enumerate(costs):
                    if not is_int(c) or c <= 0:
                        errors.append(f"{ixloc}: costs[{i}] 须为正整数")
                for i, m in enumerate(monthly):
                    if not is_num(m) or m <= 0:
                        errors.append(f"{ixloc}: monthly[{i}] 须为正数")
                if not isinstance(ix.get("shop"), str) or not str(ix.get("shop", "")).strip():
                    errors.append(f"{ixloc}: invest.shop 须为非空字符串")
            elif typ == "hire":
                if not isinstance(ix.get("who"), str) or not str(ix.get("who", "")).strip():
                    errors.append(f"{ixloc}: hire.who 须为非空字符串")
                wage = ix.get("wage")
                if not is_int(wage) or wage <= 0:
                    errors.append(f"{ixloc}: hire.wage 须为正整数")
                if "attention_ease" in ix and (not is_int(ix["attention_ease"]) or ix["attention_ease"] < 0):
                    errors.append(f"{ixloc}: hire.attention_ease 须为非负整数")
                if "hire_bonus" in ix and not isinstance(ix["hire_bonus"], str):
                    errors.append(f"{ixloc}: hire.hire_bonus 须为字符串")
                if "hire_mul" in ix and (not is_num(ix["hire_mul"]) or ix["hire_mul"] <= 0):
                    errors.append(f"{ixloc}: hire.hire_mul 须为正数")
            elif typ == "licence":
                lic = ix.get("licence")
                if not isinstance(lic, str) or not lic.startswith("lic_"):
                    errors.append(f"{ixloc}: licence 须以 lic_ 开头")
            elif typ == "choice":
                opts = ix.get("options")
                if not isinstance(opts, list) or not opts:
                    errors.append(f"{ixloc}: choice.options 须为非空数组")
                    opts = []
                for opt in opts:
                    if not isinstance(opt, dict):
                        errors.append(f"{ixloc}: option 须为对象")
                        continue
                    if not isinstance(opt.get("id"), str) or not str(opt.get("id", "")).strip():
                        errors.append(f"{ixloc}: option.id 须为非空字符串")
                    if "cost" in opt and (not is_int(opt["cost"]) or opt["cost"] < 0):
                        errors.append(f"{ixloc}: option.cost 须为非负整数")
                    rspec = opt.get("rumor")
                    if rspec is not None:
                        if not isinstance(rspec, dict):
                            errors.append(f"{ixloc}: option.rumor 须为对象")
                        else:
                            rport = rspec.get("port")
                            rgood = rspec.get("good")
                            if not isinstance(rport, str) or rport not in ports:
                                errors.append(f"{ixloc}: option.rumor.port 不在 ports.json：{rport}")
                            if not isinstance(rgood, str) or rgood not in goods:
                                errors.append(f"{ixloc}: option.rumor.good 不在 goods.json：{rgood}")
                            mul = rspec.get("mul")
                            if not is_num(mul) or mul <= 0 or mul == 1:
                                errors.append(f"{ixloc}: option.rumor.mul 须为正数且不为 1")
                            if isinstance(rport, str) and rport in ports and isinstance(rgood, str) and rgood in goods:
                                if rgood not in ports[rport].get("market", {}):
                                    errors.append(f"{ixloc}: option.rumor 货 {rgood} 不在港 {rport} 市面")
            # licence consistency for needs_licence already above; needs_licence may be on ix.unlock
            # additional: if type licence, licence id unique checked globally

    print("城区数据交叉校验（data/districts*.json）")
    if not errors:
        print("  ✓ 全部通过")
        print("结果：全部通过")
        return 0
    for e in errors:
        print("  ✗ " + e)
    print(f"结果：{len(errors)} 项问题")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
PY