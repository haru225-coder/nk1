#!/usr/bin/env python3
"""复现 Economy.gd / Voyage.gd 的公式，验证核心贸易循环与航海数值是否成立。
不依赖 Godot，纯数学校验。"""
import json, math, sys, os

import pathlib
ROOT = str(pathlib.Path(__file__).resolve().parent.parent)

def load(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
        return json.load(f)

goods = {g["id"]: g for g in load("goods.json")["goods"]}
ports = {p["id"]: p for p in load("ports.json")["ports"]}
ships = {s["id"]: s for s in load("ships.json")["ships"]}

ROLE_MOD = {"origin": 0.65, "normal": 1.0, "consumer": 1.75}
TARIFF = 0.10
BROKER = 0.05
KM_PER_LI = 0.576
EARTH_R = 6371.0

def role(pid, gid):
    return ports[pid].get("market", {}).get(gid)

def unit_value(pid, gid, rate=1.0):
    return goods[gid]["base_value"] * ROLE_MOD[role(pid, gid)] * rate

def buy_price(pid, gid, rate=1.0):
    return round(unit_value(pid, gid, rate) * (1 + TARIFF))

def sell_price(pid, gid, rate=1.0):
    return round(unit_value(pid, gid, rate) * (1 - BROKER))

def distance_li(a, b):
    pa, pb = ports[a], ports[b]
    lat1, lon1 = math.radians(pa["lat"]), math.radians(pa["lon"])
    lat2, lon2 = math.radians(pb["lat"]), math.radians(pb["lon"])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return (EARTH_R * 2 * math.atan2(math.sqrt(h), math.sqrt(1-h))) / KM_PER_LI

def bearing(a, b):
    pa, pb = ports[a], ports[b]
    lat1, lat2 = math.radians(pa["lat"]), math.radians(pb["lat"])
    dlon = math.radians(pb["lon"] - pa["lon"])
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1)*math.sin(lat2) - math.sin(lat1)*math.cos(lat2)*math.cos(dlon)
    return math.degrees(math.atan2(y, x)) % 360

def wind_factor(course, wind_bearing, strength):
    if wind_bearing < 0:
        return 0.85
    diff = math.radians((course - wind_bearing + 180) % 360 - 180)
    raw = 1.0 + math.cos(diff) * 0.6
    raw = 1.0 + (raw - 1.0) * strength
    return max(0.40, min(1.60, raw))

fails = []
def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)

print("=" * 68)
print("一、数据完整性")
print("=" * 68)

# 所有 market 引用的货物 id 必须存在
bad = []
for pid, p in ports.items():
    for gid in p.get("market", {}):
        if gid not in goods:
            bad.append(f"{pid} -> {gid}")
check(not bad, f"港口 market 引用的货物 id 全部存在（{len(bad)} 个悬空）")
if bad:
    for b in bad[:10]:
        print("      悬空:", b)

# 所有 market 的 role 值合法
bad_role = [(pid, gid, r) for pid, p in ports.items()
            for gid, r in p.get("market", {}).items() if r not in ROLE_MOD]
check(not bad_role, f"market 的 role 取值全部合法（{len(bad_role)} 个非法）")

# 不可交易货物不应出现在 market
bad_tradable = [(pid, gid) for pid, p in ports.items()
                for gid in p.get("market", {}) if not goods[gid].get("tradable", False)]
check(not bad_tradable, f"market 中无不可交易货物（{len(bad_tradable)} 个）")

# connections 指向的港口必须存在
bad_conn = [(pid, c) for pid, p in ports.items()
            for c in p.get("connections", []) if c not in ports]
check(not bad_conn, f"connections 指向的港口全部存在（{len(bad_conn)} 个悬空）")
for pid, c in bad_conn[:10]:
    print(f"      悬空: {pid} -> {c}")

# 每个港口必须有坐标与深度
no_geo = [pid for pid, p in ports.items() if "lat" not in p or "lon" not in p or p.get("depth", 0) <= 0]
check(not no_geo, f"所有港口有经纬度与市场深度（缺失 {len(no_geo)}）")

# 每个港口都必须有一条同章节内的盈利出港路线，否则进港即死路
for chapter in ("ch1", "ch2"):
    reachable = [pid for pid, p in ports.items()
                 if p.get("unlock", "ch1") <= chapter]
    dead = []
    for src in reachable:
        ok = False
        for dst in reachable:
            if dst == src:
                continue
            for gid in ports[src].get("market", {}):
                if gid in ports[dst].get("market", {}) and \
                   sell_price(dst, gid) > buy_price(src, gid):
                    ok = True; break
            if ok: break
        if not ok:
            dead.append(ports[src]["name"])
    check(not dead, f"{chapter} 阶段所有港口都有盈利出路（死港：{dead or '无'}）")

print()
print("=" * 68)
print("一之二、章节晋升链是否可达（防死锁）")
print("=" * 68)

chapters = load("chapters.json")["chapters"]
def ch_num(u):  # "ch2" -> 2
    return int(u[2:]) if isinstance(u, str) and u.startswith("ch") else 1

for c in chapters:
    n = int(c["id"])
    req = c.get("next_requires")
    if not req:
        print(f"  · 第{n}章「{c['name']}」为最终章，无晋升条件")
        continue
    # 该章可抵达的港口
    avail = [p for p in ports.values() if ch_num(p.get("unlock", "ch1")) <= n]
    ok_count = len(avail) >= req.get("visited_count", 0)
    check(ok_count,
          f"第{n}章需走通 {req.get('visited_count',0)} 港，该章实际可达 {len(avail)} 港")
    for pid in req.get("must_visit", []):
        reachable = pid in ports and ch_num(ports[pid].get("unlock", "ch1")) <= n
        check(reachable,
              f"第{n}章要求亲至「{ports.get(pid,{}).get('name',pid)}」，该港在本章"
              + ("可达" if reachable else "尚未解锁——死锁"))

# 每一章都必须能通向下一章
max_ch = max(int(c["id"]) for c in chapters)
declared = {ch_num(p.get("unlock", "ch1")) for p in ports.values()}
check(declared <= set(range(1, max_ch + 1)),
      f"ports.json 引用的章节号 {sorted(declared)} 均在 chapters.json 定义范围内(1-{max_ch})")
ship_ch = {ch_num(s.get("unlock", "ch1")) for s in ships.values()}
check(ship_ch <= set(range(1, max_ch + 1)),
      f"ships.json 引用的章节号 {sorted(ship_ch)} 均在定义范围内")

print()
print("=" * 68)
print("二、核心贸易循环：泉州 ⇄ 博多 往返是否双向盈利")
print("=" * 68)

def leg_profit(src, dst, gid):
    b = buy_price(src, gid)
    s = sell_price(dst, gid)
    return b, s, s - b

print("\n  去程（泉州 → 博多）：")
outbound = []
for gid in ports["quanzhou"]["market"]:
    if role("quanzhou", gid) == "origin" and role("hakata", gid) == "consumer":
        b, s, p = leg_profit("quanzhou", "hakata", gid)
        outbound.append((p, gid, b, s))
outbound.sort(reverse=True)
for p, gid, b, s in outbound:
    print(f"    {goods[gid]['name']:<8} 买{b:>4} → 卖{s:>4}   每件赚 {p:>4}  ({p/b*100:>5.1f}%)")
check(len(outbound) >= 3, f"去程有 {len(outbound)} 种产地→消费地货物可套利")
check(all(p > 0 for p, _, _, _ in outbound), "去程所有此类货物均为正利润")

print("\n  回程（博多 → 泉州）：")
inbound = []
for gid in ports["hakata"]["market"]:
    if role("hakata", gid) == "origin" and role("quanzhou", gid) == "consumer":
        b, s, p = leg_profit("hakata", "quanzhou", gid)
        inbound.append((p, gid, b, s))
inbound.sort(reverse=True)
for p, gid, b, s in inbound:
    print(f"    {goods[gid]['name']:<8} 买{b:>4} → 卖{s:>4}   每件赚 {p:>4}  ({p/b*100:>5.1f}%)")
check(len(inbound) >= 3, f"回程有 {len(inbound)} 种产地→消费地货物可套利")
check(all(p > 0 for p, _, _, _ in inbound), "回程所有此类货物均为正利润")

print()
print("=" * 68)
print("三、砸盘效应：一次性倾销是否真的压价")
print("=" * 68)

def sell_revenue(pid, gid, amount, rate=1.0):
    depth = ports[pid]["depth"]
    total, r = 0, rate
    for _ in range(amount):
        total += round(unit_value(pid, gid, r) * (1 - BROKER))
        r = max(0.4, min(2.2, r - 1.0/depth))
    return total

for amt in (10, 50, 200):
    rev = sell_revenue("hakata", "qingbai_porcelain", amt)
    flat = sell_price("hakata", "qingbai_porcelain") * amt
    loss = (1 - rev/flat) * 100
    print(f"    在博多倾销青白瓷 {amt:>3} 件：实得 {rev:>6}  （无砸盘应得 {flat:>6}，缩水 {loss:>4.1f}%）")

r10 = sell_revenue("hakata", "qingbai_porcelain", 10)
r200 = sell_revenue("hakata", "qingbai_porcelain", 200)
check(r200 / 200 < r10 / 10, "大批量倾销的单件均价确实低于小批量（砸盘生效）")

# 小港砸盘应更剧烈
r_small = sell_revenue("penghu", "fujian_porcelain", 50)
flat_small = sell_price("penghu", "fujian_porcelain") * 50
r_big = sell_revenue("quanzhou", "fujian_porcelain", 50)
flat_big = sell_price("quanzhou", "fujian_porcelain") * 50
print(f"\n    同样卖 50 件瓷：澎湖(深度{ports['penghu']['depth']}) 缩水 {(1-r_small/flat_small)*100:.1f}%"
      f"　泉州(深度{ports['quanzhou']['depth']}) 缩水 {(1-r_big/flat_big)*100:.1f}%")
check((1-r_small/flat_small) > (1-r_big/flat_big), "小港比大港更容易被砸盘")

print()
print("=" * 68)
print("四、季风：去日本必须等夏季、回泉州要赶冬季")
print("=" * 68)

NE, SW = 225.0, 45.0   # 东北季风吹向西南 / 西南季风吹向东北

for src, dst in [("quanzhou", "hakata"), ("hakata", "quanzhou")]:
    crs = bearing(src, dst)
    f_sw = wind_factor(crs, SW, 1.0)
    f_ne = wind_factor(crs, NE, 1.0)
    print(f"\n  {ports[src]['name']} → {ports[dst]['name']}  航向 {crs:.0f}°")
    print(f"    西南季风(夏)：×{f_sw:.2f}    东北季风(冬)：×{f_ne:.2f}")

crs_out = bearing("quanzhou", "hakata")
crs_back = bearing("hakata", "quanzhou")
check(wind_factor(crs_out, SW, 1.0) > wind_factor(crs_out, NE, 1.0),
      "泉州→博多：夏季西南风确实比冬季有利（史实「南风回唐山」的北上航段）")
check(wind_factor(crs_back, NE, 1.0) > wind_factor(crs_back, SW, 1.0),
      "博多→泉州：冬季东北风确实比夏季有利（史实「北风下南洋」）")

print()
print("=" * 68)
print("五、航段天数与补给消耗是否可行")
print("=" * 68)

def voyage_days(src, dst, ship_id, wind_b, strength=1.0, morale=70):
    d = distance_li(src, dst)
    crs = bearing(src, dst)
    wf = wind_factor(crs, wind_b, strength)
    morale_f = 0.6 + 0.4 * (morale / 100)
    spd = ships[ship_id]["base_speed"] * morale_f * wf
    return math.ceil(d / spd), d, spd

print()
routes = [("quanzhou", "xinghua"), ("quanzhou", "penghu"), ("quanzhou", "ryukyu"),
          ("quanzhou", "fuzhou"), ("mingzhou", "hakata"), ("quanzhou", "hakata"),
          ("quanzhou", "guangzhou"), ("guangzhou", "champa")]
for src, dst in routes:
    if src not in ports or dst not in ports:
        continue
    days_fav, dist, spd = voyage_days(src, dst, "fu_ship_medium",
                                      SW if bearing(src,dst) < 180 else NE)
    crs = bearing(src, dst)
    best = max(wind_factor(crs, SW, 1.0), wind_factor(crs, NE, 1.0))
    worst = min(wind_factor(crs, SW, 1.0), wind_factor(crs, NE, 1.0))
    mf = 0.6 + 0.4 * 0.7
    d_best = math.ceil(dist / (ships["fu_ship_medium"]["base_speed"] * mf * best))
    d_worst = math.ceil(dist / (ships["fu_ship_medium"]["base_speed"] * mf * worst))
    print(f"    {ports[src]['name']:<5}→{ports[dst]['name']:<7} {dist:>6.0f}里　顺季 {d_best:>3} 日　逆季 {d_worst:>3} 日")

# 福船中型满载补给能撑多久（水粮各占 SUPPLY_BULK 料/份）
SUPPLY_BULK = 0.25
sh = ships["fu_ship_medium"]
crew = 25
cap = sh["capacity"]
# 一半舱位装水粮；每支撑 1 人日需 1 水 + 1 粮 = 2 份 = 2*SUPPLY_BULK 料
supply_units = (cap * 0.5) / SUPPLY_BULK / 2   # 可携带的「人日份」
days_supported = supply_units / crew
d_hakata = math.ceil(distance_li("quanzhou","hakata") /
                     (sh["base_speed"] * (0.6+0.4*0.7) * wind_factor(crs_out, SW, 1.0)))
print(f"\n    福船(中) 载{cap}料，25人，半舱装水粮({supply_units:.0f}份) → 可支撑 {days_supported:.0f} 日")
print(f"    泉州→博多 顺季需 {d_hakata} 日")
check(days_supported > d_hakata, "半舱补给足以支撑泉州→博多的顺季航程（远洋可行）")

# 起步小艍船能否跑近海
sh0 = ships["sampan"]
crew0 = 6
sup0 = (sh0["capacity"] * 0.5) / SUPPLY_BULK / 2
days0 = sup0 / crew0
d_penghu = math.ceil(distance_li("quanzhou","penghu") / (sh0["base_speed"] * (0.6+0.4*0.7) * 1.0))
print(f"\n    小艍船 载{sh0['capacity']}料，6人，半舱水粮({sup0:.0f}份) → 可支撑 {days0:.0f} 日")
print(f"    泉州→澎湖 约需 {d_penghu} 日")
check(days0 > d_penghu * 2, "起步船的补给足以往返近海港口")

print()
print("=" * 68)
print("六、起步可行性：1000 钱能否启动第一笔生意")
print("=" * 68)

start_money = 1000
sampan_cap = ships["sampan"]["capacity"]   # 200 料
# 留一半舱位给水粮
trade_space = sampan_cap * 0.5

best_start = []
for dst in ports:
    if dst == "quanzhou" or ports[dst].get("unlock") != "ch1":
        continue
    for gid in ports["quanzhou"]["market"]:
        if gid not in ports[dst].get("market", {}):
            continue
        b = buy_price("quanzhou", gid)
        s = sell_price(dst, gid)
        if s <= b or b <= 0:
            continue
        bulk = goods[gid]["bulk"]
        qty = min(int(start_money / b), int(trade_space / bulk))
        if qty <= 0:
            continue
        profit = sell_revenue(dst, gid, qty) - b * qty
        best_start.append((profit, gid, dst, qty, b, s))

best_start.sort(reverse=True)
print("\n  从泉州出发、本金 1000 钱、小艍船半舱的最佳前 5 笔生意：")
for profit, gid, dst, qty, b, s in best_start[:5]:
    print(f"    买 {goods[gid]['name']:<6}×{qty:<3} @{b:<4} → 运往 {ports[dst]['name']:<7} 卖 @{s:<4}"
          f"　净赚 {profit:>5}  ({profit/start_money*100:>5.1f}%)")

check(len(best_start) > 0, "开局存在可盈利的贸易路线")
if best_start:
    check(best_start[0][0] > 100, f"最佳开局生意净利 {best_start[0][0]} 钱（足以滚动起来）")
    check(best_start[0][0] < start_money * 3, "开局单笔利润未失衡（不会一趟暴富）")

print()
print("=" * 68)
print("七、违禁品走私的风险回报")
print("=" * 68)

for gid in [g for g in goods if goods[g].get("contraband")]:
    print(f"\n  {goods[gid]['name']}：")
    for dst in ports:
        if gid in ports[dst].get("market", {}) and role(dst, gid) == "consumer":
            src_candidates = [p for p in ports if gid in ports[p].get("market", {})
                              and role(p, gid) in ("origin", "normal")]
            if not src_candidates:
                continue
            src = min(src_candidates, key=lambda p: buy_price(p, gid))
            b, s = buy_price(src, gid), sell_price(dst, gid)
            print(f"    {ports[src]['name']} 买{b} → {ports[dst]['name']} 卖{s}　每件赚 {s-b} ({(s-b)/b*100:.0f}%)")

# 走私利润应显著高于合法贸易。舱位有限，真正该比的是「每料收益」。
def per_li_profit(src, dst, gid):
    return (sell_price(dst, gid) - buy_price(src, gid)) / goods[gid]["bulk"]

legal = [(per_li_profit("quanzhou", "hakata", gid), gid) for _, gid, _, _ in outbound
         if not goods[gid].get("contraband")]
legal.sort(reverse=True)
smug = [(per_li_profit("quanzhou", "hakata", gid), gid) for gid in ports["hakata"]["market"]
        if goods[gid].get("contraband") and gid in ports["quanzhou"]["market"]]
smug.sort(reverse=True)

print("\n  航线一：泉州 → 博多（远洋，13 日）每料收益")
for v, gid in legal[:3]:
    print(f"      合法  {goods[gid]['name']:<6} {v:>6.1f} /料")
for v, gid in smug[:3]:
    print(f"      违禁  {goods[gid]['name']:<6} {v:>6.1f} /料")
check(smug and legal and smug[0][0] > legal[0][0],
      f"博多线走私每料收益（{smug[0][0]:.1f}）高于最佳合法货（{legal[0][0]:.1f}）")

print("\n  航线二：泉州 → 流求（近海，3 日）每料收益")
ry_legal, ry_smug = [], []
for gid in ports["ryukyu"]["market"]:
    if gid not in ports["quanzhou"]["market"]:
        continue
    if role("ryukyu", gid) != "consumer":
        continue
    v = per_li_profit("quanzhou", "ryukyu", gid)
    (ry_smug if goods[gid].get("contraband") else ry_legal).append((v, gid))
ry_legal.sort(reverse=True); ry_smug.sort(reverse=True)
for v, gid in ry_legal[:3]:
    print(f"      合法  {goods[gid]['name']:<6} {v:>6.1f} /料")
for v, gid in ry_smug[:3]:
    print(f"      违禁  {goods[gid]['name']:<6} {v:>6.1f} /料")
check(ry_smug and ry_legal and ry_smug[0][0] > ry_legal[0][0],
      f"流求线走私每料收益（{ry_smug[0][0]:.1f}）高于最佳合法货（{ry_legal[0][0]:.1f}）")

print()
print("=" * 68)
if fails:
    print(f"结果：{len(fails)} 项未通过")
    for f in fails:
        print("   ✗", f)
    sys.exit(1)
print("结果：全部通过")
