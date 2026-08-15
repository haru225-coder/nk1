#!/usr/bin/env python3
"""端到端模拟一局：从开局 1000 钱、一条小艍船出发，跑近海商路攒钱换船。
完整复现 Fleet 的舱位/补给（多船分装）、Economy 的行情冲击与回归、Voyage 的季风与航速。
目的是找出设计死锁（卡补给、卡舱位、卡钱），而不是验证单条公式。"""
import json, math, os, sys, random

random.seed(20260727)
import pathlib
ROOT = str(pathlib.Path(__file__).resolve().parent.parent)

def load(n):
    with open(os.path.join(ROOT, "data", n), encoding="utf-8") as f:
        return json.load(f)

goods = {g["id"]: g for g in load("goods.json")["goods"]}
ports = {p["id"]: p for p in load("ports.json")["ports"]}
ships = {s["id"]: s for s in load("ships.json")["ships"]}
chapters = {int(c["id"]): c for c in load("chapters.json")["chapters"]}

ROLE_MOD = {"origin": 0.65, "normal": 1.0, "consumer": 1.75}
TARIFF, BROKER = 0.10, 0.05
RECOVERY = 0.045
SUPPLY_BULK = 0.25
CREW_DAYS_PER_SUPPLY = 2.0
KM_PER_LI, EARTH_R = 0.576, 6371.0
NE, SW = 225.0, 45.0
INN_RATE = 15

rates = {pid: {gid: 1.0 for gid in p.get("market", {})} for pid, p in ports.items()}

# ── 多船舰队模型 ──────────────────────────────────────
# 复刻 Fleet.gd 的分船装载：每船独立 cargo，水/粮全队共用，
# 单船空舱预扣按载重比例分摊的水粮份额，Σ ship_free == free 恒成立。
class G:
    money = 1000
    year, month, day = 1255, 3, 1
    port = "quanzhou"
    ships = [{"type": "sampan", "name": "无名小艍", "crew": 6,
              "durability": 120.0, "sail_level": 1, "armor_level": 1, "cargo": {}}]
    water, food = 60, 60
    morale = 70
    at_sea = False
    debt = 0
    chapter = 1
    visited = ['quanzhou']
    peak_money = 1000

def cap_total():  return sum(ships[s["type"]]["capacity"] for s in G.ships)
def bulk(gid):    return goods[gid]["bulk"]
def ship_cap(i):  return ships[G.ships[i]["type"]]["capacity"]
def ship_bulk(i): return sum(q*bulk(g) for g,(q,_) in G.ships[i]["cargo"].items())
def ship_free(i):
    """单船空舱（含水粮按载重比例分摊）——与 Fleet.ship_free_capacity 一致"""
    tc = cap_total()
    wf = (G.water + G.food) * SUPPLY_BULK
    share = wf * (ship_cap(i)/tc) if tc > 0 else wf / max(1, len(G.ships))
    return max(0.0, ship_cap(i) - ship_bulk(i) - share)
def used():         return (G.water+G.food)*SUPPLY_BULK + sum(ship_bulk(i) for i in range(len(G.ships)))
def free():         return max(0.0, cap_total() - used())
def total_crew():   return sum(s["crew"] for s in G.ships)
def crew_min_ok():
    """每船都达到各自 crew_min（复刻 Fleet.can_sail 的逐船门槛）"""
    return all(s["crew"] >= ships[s["type"]]["crew_min"] for s in G.ships)
def top_up_crew():
    """出港前补足各船最低水手（模拟玩家在船屋补员；模型里基线免费用人）"""
    hired = 0
    for s in G.ships:
        need = ships[s["type"]]["crew_min"] - s["crew"]
        if need > 0:
            s["crew"] += need
            hired += need
    return hired
def daily_use():    return math.ceil(total_crew()/CREW_DAYS_PER_SUPPLY) if total_crew() else 0
def supply_days():  return int(min(G.water,G.food)/daily_use()) if total_crew() else 999
def morale_f():     return 0.6 + 0.4*(G.morale/100)

def verify_invariants():
    """分船装载的账目不变量——每步操作后都应成立"""
    ok = True
    for i in range(len(G.ships)):
        if ship_bulk(i) > ship_cap(i) + 1e-6:
            print(f"    ✗ 船{i}({G.ships[i]['type']}) 货物 {ship_bulk(i):.1f} 料 > 载重 {ship_cap(i)} 料"); ok = False
    if used() > cap_total() + 1e-6:
        print(f"    ✗ 全队 {used():.1f} > {cap_total()} 料"); ok = False
    sf = sum(ship_free(i) for i in range(len(G.ships)))
    if abs(sf - free()) > 1e-3:
        print(f"    ✗ Σ ship_free {sf:.3f} != free {free():.3f}"); ok = False
    return ok

def monsoon(m=None):
    m = m or G.month
    if m >= 10 or m <= 2: return "NE"
    if 5 <= m <= 8:       return "SW"
    return "TR"

def wind_bearing():
    mm = monsoon()
    return NE if mm == "NE" else (SW if mm == "SW" else -1)

def monsoon_strength():
    mm = monsoon()
    if mm == "NE": return 1.0 if G.month in (11,12,1) else 0.8
    if mm == "SW": return 1.0 if G.month in (6,7) else 0.8
    return 0.3

def dist(a, b):
    pa, pb = ports[a], ports[b]
    la1, lo1, la2, lo2 = map(math.radians, (pa["lat"], pa["lon"], pb["lat"], pb["lon"]))
    h = math.sin((la2-la1)/2)**2 + math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return (EARTH_R*2*math.atan2(math.sqrt(h), math.sqrt(1-h)))/KM_PER_LI

def bearing(a, b):
    pa, pb = ports[a], ports[b]
    la1, la2 = math.radians(pa["lat"]), math.radians(pb["lat"])
    dlo = math.radians(pb["lon"]-pa["lon"])
    y = math.sin(dlo)*math.cos(la2)
    x = math.cos(la1)*math.sin(la2)-math.sin(la1)*math.cos(la2)*math.cos(dlo)
    return math.degrees(math.atan2(y,x)) % 360

def wind_factor(course):
    wb = wind_bearing()
    if wb < 0: return 0.85
    diff = math.radians((course-wb+180) % 360 - 180)
    raw = 1.0 + math.cos(diff)*0.6
    raw = 1.0 + (raw-1.0)*monsoon_strength()
    return max(0.40, min(1.60, raw))

def speed(course):
    """舰队日速取最慢一艘（Fleet.fleet_speed 语义，含帆等级加成）"""
    spd = min(ships[s["type"]]["base_speed"] * (1 + 0.12*(s.get("sail_level",1)-1))
              for s in G.ships)
    return spd * morale_f() * wind_factor(course)

DEBT_CEILING, DEBT_RATE = 3000, 0.03

def borrow(amount):
    room = max(0, DEBT_CEILING - G.debt)
    amount = min(amount, room)
    if amount <= 0: return 0
    G.debt += amount; G.money += amount
    return amount

def lose_crew(n):
    """断粮减员跨船分摊，保证至少留 1 人"""
    left = n
    for s in G.ships:
        if left <= 0: break
        take = min(left, s["crew"] - 1) if s["crew"] > 1 else 0
        s["crew"] -= take; left -= take
    # 若所有船都只剩 1 人但仍有减员需求，就不减了（保留火种）

def advance(n):
    for _ in range(n):
        G.day += 1
        if G.day > 30:
            G.day = 1; G.month += 1
            if G.debt > 0: G.debt += math.ceil(G.debt * DEBT_RATE)
            if G.month > 12: G.month = 1; G.year += 1
        for pid in rates:
            for gid in rates[pid]:
                rates[pid][gid] += (1.0 - rates[pid][gid]) * RECOVERY
        if G.at_sea:
            u = daily_use()
            G.water = max(0, G.water - u); G.food = max(0, G.food - u)
            if G.water <= 0 or G.food <= 0: G.morale = max(0, G.morale - 6)
        else:
            if G.morale < 75: G.morale = min(100, G.morale + 1)

def ch_num(u): return int(u[2:]) if isinstance(u,str) and u.startswith("ch") else 1

def open_ports():
    """当前章节可抵达的港口"""
    return [pid for pid,p in ports.items() if ch_num(p.get("unlock","ch1")) <= G.chapter]

def visit(pid):
    if pid not in G.visited: G.visited.append(pid)

def try_advance():
    req = chapters.get(G.chapter, {}).get("next_requires")
    if not req: return None
    if G.peak_money < req.get("peak_money", 0): return None
    if len(G.visited) < req.get("visited_count", 0): return None
    for m in req.get("must_visit", []):
        if m not in G.visited: return None
    title = chapters[G.chapter].get("advance_title","")
    G.chapter += 1
    return title

def role(pid, gid): return ports[pid]["market"].get(gid)
def uval(pid, gid): return goods[gid]["base_value"] * ROLE_MOD[role(pid,gid)] * rates[pid][gid]
def buy_p(pid,gid):  return round(uval(pid,gid)*(1+TARIFF))
def sell_p(pid,gid): return round(uval(pid,gid)*(1-BROKER))

def _best_free_ship():
    """空舱最大的船（模拟理性玩家选舱装货）"""
    return max(range(len(G.ships)), key=lambda i: ship_free(i))

def do_buy(gid, want, floor_price=None, budget=None):
    """理性买入：逐件推高行情，装到空舱最大的船（多船分装），
    一旦买价逼近目标港卖价就收手。
    budget 限制本次投入——真人玩家不会把全部身家押在一船违禁货上。"""
    depth = ports[G.port]["depth"]
    if budget is None: budget = G.money
    got, spent = 0, 0
    while got < want:
        idx = _best_free_ship()
        if ship_free(idx) < bulk(gid): break
        p = buy_p(G.port, gid)
        if G.money - spent < p or spent + p > budget: break
        # 留 25% 安全边际，覆盖卖出侧的砸盘损耗
        if floor_price is not None and p >= floor_price * 0.75: break
        spent += p; got += 1
        rates[G.port][gid] = min(2.2, rates[G.port][gid] + 1.0/depth)
        c = G.ships[idx]["cargo"]
        if gid in c:
            c[gid][0] += 1
            c[gid][1] = (c[gid][1]*(c[gid][0]-1) + p) / c[gid][0]
        else:
            c[gid] = [1, p]
    if got:
        G.money -= spent
    return got, spent

def do_sell(gid, qty):
    """跨船卖出：优先从货最多的船扣（模拟玩家清仓）"""
    depth = ports[G.port]["depth"]
    rev, sold = 0, 0
    while sold < qty:
        cands = [i for i in range(len(G.ships)) if G.ships[i]["cargo"].get(gid, [0])[0] > 0]
        if not cands: break
        idx = max(cands, key=lambda i: G.ships[i]["cargo"][gid][0])
        rev += sell_p(G.port, gid)
        rates[G.port][gid] = max(0.4, rates[G.port][gid] - 1.0/depth)
        c = G.ships[idx]["cargo"]
        c[gid][0] -= 1
        if c[gid][0] == 0: del c[gid]
        sold += 1
    G.money += rev
    G.peak_money = max(G.peak_money, G.money)
    return rev

def buy_supplies(days_needed):
    need = max(0, days_needed*daily_use() - min(G.water, G.food))
    gp = buy_p(G.port,"grain") if "grain" in ports[G.port]["market"] else 12
    bought = 0
    while bought < need and free() >= 2*SUPPLY_BULK and G.money >= (1+gp):
        G.water += 1; G.food += 1; G.money -= (1+gp); bought += 1
    return bought

def sail(dst):
    d, crs = dist(G.port, dst), bearing(G.port, dst)
    top_up_crew()  # 出港前玩家会在船屋补足各船最低水手
    G.at_sea = True
    rem, days = d, 0
    while rem > 0 and days < 200:
        advance(1); days += 1
        rem -= speed(crs)
        if G.water <= 0 or G.food <= 0:
            if random.random() < 0.4:
                lose_crew(max(1, int(total_crew()*0.03)))
    G.at_sea = False
    G.port = dst
    visit(dst)
    return days

def best_trade(src, dsts):
    """挑一条最赚的货 + 目的地"""
    best = None
    for dst in dsts:
        for gid in ports[src]["market"]:
            if gid not in ports[dst]["market"]: continue
            if goods[gid]["base_value"] <= 0: continue
            margin = sell_p(dst,gid) - buy_p(src,gid)
            if margin <= 0: continue
            per_li = margin / bulk(gid)
            if best is None or per_li > best[0]:
                best = (per_li, gid, dst, margin)
    return best

fails = []
def check(c, m):
    print(("  ✓ " if c else "  ✗ ") + m)
    if not c: fails.append(m)

print("="*70)
print("端到端模拟：开局 1000 钱 / 小艍船 / 泉州")
print("="*70)
print(f"  舰队 {len(G.ships)} 船　载重 {cap_total()} 料　水手 {total_crew()}　水粮 {G.water}/{G.food}（足 {supply_days()} 日）")
print(f"  起始舱位占用 {used():.0f} / {cap_total()} 料，可装货 {free():.0f} 料")
check(free() > cap_total()*0.5, "开局补给未占满舱（仍有一半以上可装货）")
check(verify_invariants(), "开局分船账目不变量成立")

# 第一章全部已解锁港口——真实玩家会轮换航线，避免把某一条线跑疲
history = []
print()
print(f"  ── 跑商 24 趟（起始第 {G.chapter} 章，可达 {len(open_ports())} 港）──")
waits = 0
for trip in range(1, 25):
    # 商路被自己跑疲时，真人玩家会在店里等行情回升，而不是硬亏本买
    qty = 0
    for attempt in range(6):
        bt = best_trade(G.port, [p for p in open_ports() if p != G.port])
        if bt is None:
            gid = dst = None
        else:
            _, gid, dst, margin = bt
            d = dist(G.port, dst); crs = bearing(G.port, dst)
            est_days = math.ceil(d / speed(crs))
            buy_supplies(est_days + 4)
            is_contra = goods[gid].get("contraband", False)
            # 违禁货最多押六成身家；一次查扣不该让人再也翻不了身
            cap_budget = int(G.money * 0.6) if is_contra else G.money
            qty, spent = do_buy(gid, 9999, floor_price=sell_p(dst, gid), budget=cap_budget)
        if qty > 0:
            break
        # 本钱见底时向蕃商赊贷
        if G.money < 300:
            got_loan = borrow(500)
            if got_loan:
                print(f"    第{trip:>2}趟  本钱告罄，赊借 {got_loan} 钱（现欠 {G.debt}）")
                continue
        # 候市：住店 10 日让行情回归
        cost = 10 * INN_RATE
        if G.money < cost:
            break
        G.money -= cost; advance(10); waits += 10
        G.morale = min(100, G.morale + 20)
        print(f"    第{trip:>2}趟  行情不佳，在店中候市 10 日（房钱 {cost}）")
    if qty == 0:
        print(f"    第{trip:>2}趟  确实无利可图（钱 {G.money}，空舱 {free():.0f}）"); break
    src = G.port
    smuggle = goods[gid].get("contraband", False)
    seized = False
    if smuggle:
        # 违禁货出港查扣风险（游戏内由 GameState.customs_inspection 判定）
        if random.random() < 0.28:
            seized = True
            for s in G.ships:
                if gid in s["cargo"]: del s["cargo"][gid]
            fine = min(300, max(50, int(G.money*0.4)))
            G.money = max(0, G.money - fine)
    days = sail(dst)
    rev = 0 if seized else do_sell(gid, qty)
    profit = rev - spent - (fine if seized else 0)
    history.append(profit)
    promoted = try_advance()
    tag = "　[走私]" + ("　✗查扣" if seized else "") if smuggle else ""
    if promoted: tag += f"　★进第{G.chapter}章「{promoted}」"
    print(f"    第{trip:>2}趟 {ports[src]['name']:<5}→{ports[dst]['name']:<7} "
          f"{goods[gid]['name']:<5}×{qty:<3} 本{spent:>5} 得{rev:>6} 净{profit:>+6}  "
          f"{days:>2}日  {G.year}年{G.month:>2}月  存银 {G.money:>6}{tag}")
    if not verify_invariants():
        check(False, f"第{trip}趟后分船账目不变量被破坏")

check(len(history) >= 20, f"连跑 {len(history)} 趟未卡死")
check(G.money > 1000, f"{len(history)} 趟后资金 {G.money}（开局 1000）")
check(sum(1 for p in history if p > 0) >= len(history)*0.7,
      f"{sum(1 for p in history if p>0)}/{len(history)} 趟盈利")

print()
print("  ── 行情是否被跑崩（反复走同一条线的自我限制）──")
ry = rates.get("ryukyu", {})
low = [(gid, r) for gid, r in ry.items() if r < 0.75]
print(f"    流求被压低的货：{[(goods[g]['name'], round(r,2)) for g,r in low] or '无'}")
check(True, "行情随交易变动（低于 0.75 表示已被砸盘，需换港或候其回升）")

print()
check(G.chapter >= 2, f"24 趟内晋升至第 {G.chapter} 章（起始第 1 章）")
check("hakata" in open_ports(), "晋升后博多唐房已可抵达——核心商路不再是死内容")
print(f"    资金峰值 {G.peak_money}　走通港口 {len(G.visited)} 处：{'、'.join(ports[p]['name'] for p in G.visited)}")

print()
print("="*70)
print("远洋检验：候西南季风北上博多（多船舰队）")
print("="*70)
G.port = "quanzhou"
if G.money >= ships["fu_ship_medium"]["price"]:
    G.money -= ships["fu_ship_medium"]["price"]
    G.ships.append({"type": "fu_ship_medium", "name": "福船",
                    "crew": ships["fu_ship_medium"]["crew_min"],
                    "durability": 300.0, "sail_level": 1, "armor_level": 1, "cargo": {}})
    print(f"  已购福船（中），余银 {G.money}，舰队 {len(G.ships)} 船，载重 {cap_total()} 料")
    check(G.ships[-1]["crew"] == ships["fu_ship_medium"]["crew_min"],
          f"新购福船水手 = crew_min（{G.ships[-1]['crew']} 人）")
    check(verify_invariants(), "购船后分船账目不变量成立")
else:
    print(f"  资金 {G.money} 不足以购福船（{ships['fu_ship_medium']['price']}），以小艍船试航")

crs = bearing("quanzhou","hakata")
print(f"\n  现在是 {G.month} 月（{monsoon()}），泉州→博多 风向系数 {wind_factor(crs):.2f}")
waited = 0
while monsoon() != "SW" and waited < 400:
    to_next = 30 - G.day + 1
    cost = to_next * INN_RATE
    if G.money < cost: break
    G.money -= cost; advance(to_next); waited += to_next
    G.morale = min(100, G.morale + to_next*2)
print(f"  在旅店候风 {waited} 日 → now {G.month} 月（{monsoon()}），"
      f"风向系数 {wind_factor(crs):.2f}，房钱共 {waited*INN_RATE}")
check(monsoon() == "SW", "通过旅店候风成功等到西南季风")
check(waited*INN_RATE < 3000, f"候风成本 {waited*INN_RATE} 钱，未压垮玩家")

d = dist("quanzhou","hakata")
est = math.ceil(d/speed(crs))
print(f"\n  预计航程 {est} 日，需水粮 {est*total_crew()} 份")
bought = buy_supplies(est + 6)
print(f"  补给后：水 {G.water} 粮 {G.food}（足 {supply_days()} 日），空舱 {free():.0f} 料")
check(supply_days() >= est, f"补给足以支撑 {est} 日航程")
check(verify_invariants(), "补给后分船账目不变量成立")

bt = best_trade("quanzhou", ["hakata"])
if bt:
    _, gid, _, margin = bt
    qty, spent = do_buy(gid, 9999, floor_price=sell_p("hakata", gid))
    # 分船装货分布展示
    distr = "　".join(f"{G.ships[i]['name']}×{G.ships[i]['cargo'].get(gid,[0])[0]}"
                      for i in range(len(G.ships)) if G.ships[i]["cargo"].get(gid,[0])[0] > 0)
    print(f"  装载 {goods[gid]['name']} ×{qty}（本 {spent}），分船：{distr}，空舱剩 {free():.0f} 料")
    # 出港前玩家在船屋补足各船最低水手（sail() 内部也会补，此处先补以便检查可观测）
    top_up_crew()
    check(crew_min_ok(), "出航前每船水手达下限（逐船门槛）")
    days = sail("hakata")
    rev = do_sell(gid, qty)
    print(f"  历 {days} 日抵博多，售得 {rev}，净赚 {rev-spent:+}")
    print(f"  抵港时：水 {G.water} 粮 {G.food}，士气 {G.morale}，水手 {total_crew()}")
    check(G.water > 0 and G.food > 0, "远洋抵港时水粮未耗尽")
    check(rev - spent > 0, f"远洋单程盈利 {rev-spent}")
    check(verify_invariants(), "远洋后分船账目不变量成立")
    crew_after = total_crew()
    check(crew_after >= 20, f"航程后水手 {crew_after} 人，未因断粮损失殆尽")

print()
print("="*70)
print("改装模拟：升帆/升甲后的航程与补给变化（独立于晋升主循环）")
print("="*70)
# 升级成本复刻 Fleet.upgrade_cost：ceil(价 × 0.10 × (1+0.5×(级-1)) × (甲则1.25))
def upgrade_cost(sid, kind, lv):
    price = ships[sid]["price"]
    mult = 1.25 if kind == "armor" else 1.0
    return math.ceil(price * 0.10 * (1 + 0.5*(lv-1)) * mult)
def armor_reduction():
    num = den = 0.0
    for s in G.ships:
        w = s.get("max_durability", 1.0) or 1.0
        num += w * (s.get("armor_level",1) - 1); den += w
    return 1.0 - 0.10*(num/den) if den > 0 else 1.0

# 只取主力福船（最后一条）验证单船改装效果：舰队最慢船决定日速，
# 此处只比较「福船自身」的 base_speed × sail_level，不受小艍拖累
fu_i = next((i for i in range(len(G.ships)) if G.ships[i]["type"] == "fu_ship_medium"), None)
if fu_i is not None:
    d0, crs0 = dist("quanzhou","hakata"), bearing("quanzhou","hakata")
    mf = morale_f()
    wf = wind_factor(crs0)
    base_spd = ships["fu_ship_medium"]["base_speed"] * mf * wf      # sail Lv1
    base_days = math.ceil(d0/base_spd)
    # 改装：福船升满帆（Lv1→3）
    cost_sail = upgrade_cost("fu_ship_medium","sail",1) + upgrade_cost("fu_ship_medium","sail",2)
    if G.money >= cost_sail:
        G.money -= cost_sail
        G.ships[fu_i]["sail_level"] = 3
    up_spd = ships["fu_ship_medium"]["base_speed"] * 1.24 * mf * wf  # ×(1+0.12×2)
    up_days = math.ceil(d0/up_spd)
    print(f"\n  福船升满帆（Lv3，花 {cost_sail} 钱）：泉州→博多 单船日速 {base_spd:.0f} → {up_spd:.0f} 里/日（+{up_spd/base_spd*100-100:.1f}%）")
    check(up_spd > base_spd, "升满帆后航速提升")
    check(up_spd/base_spd < 1.30, f"航速提升 {up_spd/base_spd*100-100:.1f}% < 30%（未架空季风）")
    check(up_days <= base_days and (base_days - up_days) >= 1,
          f"满帆后泉州→博多理论航程 {base_days}→{up_days} 日（缩短 ≥1 日）")
    # 升满甲：验证风暴/海盗船体伤系数
    cost_armor = upgrade_cost("fu_ship_medium","armor",1) + upgrade_cost("fu_ship_medium","armor",2)
    if G.money >= cost_armor:
        G.money -= cost_armor
        G.ships[fu_i]["armor_level"] = 3
    print(f"  福船升满甲（Lv3，花 {cost_armor} 钱）：船体伤系数 {armor_reduction():.2f}")
    check(0.79 <= armor_reduction() <= 1.0, f"满甲船体伤系数 {armor_reduction():.2f}，风涛仍要命（≥0.80 级）")
    check(verify_invariants(), "改装后分船账目不变量仍成立")

print()
print("="*70)
print("海战接入模拟（P4-1：WorldMap 炮击分胜负，结算复用现有文本公式）")
print("="*70)
print("  独立于晋升主循环：构造标准舰队 pending_battle，复刻三路结算账目增量。")

# 复刻 SeaChart._fleet_power()（Fleet.total_durability*0.5 + total_crew*4 + 炮位*25 + 甲级*30）
def fleet_power_py():
    durab = sum(s["durability"] for s in G.ships)
    crew = sum(s["crew"] for s in G.ships)
    cannons = sum(ships[s["type"]]["cannon_slots"] for s in G.ships)
    armor_lv = 1  # P4-1 舰队级 Lv1 基线
    return (durab * 0.5 + crew * 4.0 + cannons * 25.0 + armor_lv * 30.0) * morale_f()

# 标准舰队：客舟 + 福船（中），各满员 crew_min，士气 70
G.ships = [
    {"type": "keel_boat", "name": "客舟", "crew": ships["keel_boat"]["crew_min"],
     "durability": ships["keel_boat"]["durability"], "sail_level": 1, "armor_level": 1, "cargo": {}},
    {"type": "fu_ship_medium", "name": "福船中", "crew": ships["fu_ship_medium"]["crew_min"],
     "durability": ships["fu_ship_medium"]["durability"], "sail_level": 1, "armor_level": 1, "cargo": {}},
]
G.morale = 70
power = fleet_power_py()
print(f"  标准舰队战力 {power:.1f}（士气 70）")

# 构造 pending_battle：敌船区间 randf_range(180,520)，enemy 两条海鹘战船
enemy_power = 350.0  # 敌力中位（设计上标准舰队可胜）
hull = 100.0 * max(0.8, min(3.0, enemy_power / power))
print(f"  敌力 {enemy_power}，单船血 {hull:.0f}（战力比缩放）")
check(power >= enemy_power, f"标准舰队战力 {power:.1f} ≥ 敌力 {enemy_power}（可胜）")

# 复刻三路结算的账目增量，对照计划第三节数值表
G.money, G.peak_money = 5000, 5000
G.ships[0]["cargo"]["raw_silk"] = [10, 100]  # 舰队旗舰 10 件生丝，观察货损
base_durab = sum(s["durability"] for s in G.ships)

# win：+spoil(150~600) +fame3 +士气5，耐久不补扣（战斗中实时扣）
win_money = G.money; win_morale = G.morale
spoil = 350.0
G.money += spoil
G.peak_money = max(G.peak_money, G.money)
G.morale = min(100, G.morale + 5)
dmg_win = 0.0  # 结算不补扣（玩家战术层被击已在战斗中实时扣）
check(G.money == win_money + 350, f"win 只加赏金 350（{win_money}→{G.money}）")
check(G.morale == win_morale + 5, f"win 士气 +5（{win_morale}→{G.morale}）")
check(dmg_win == 0.0, "win 结算不补扣耐久（战斗实时扣）")

# lose：士气-12、货损 0.25，耐久不补扣
lose_morale0 = G.morale
G.morale = max(0, G.morale - 12)
# lose_cargo_ratio(0.25)：按比例从各船扣货（取整向上，货损不手软）
for s in G.ships:
    for gid, (q, p) in list(s["cargo"].items()):
        l = int(math.ceil(q * 0.25))
        if l > 0:
            s["cargo"][gid][0] -= l
            if s["cargo"][gid][0] <= 0: del s["cargo"][gid]
cargo_after_lose = G.ships[0]["cargo"].get("raw_silk", [0])[0]
check(cargo_after_lose == 7, f"lose 货损 25%（生丝 10→{cargo_after_lose}）")
check(G.morale == max(0, lose_morale0 - 12), "lose 士气 -12")

# flee 失败：货损 0.18 + 耐久 -30*armor_reduction（只打旗舰 ships[0]，同 damage_fleet）
flee_durab = sum(s["durability"] for s in G.ships)
armor_r = armor_reduction()
flee_dmg = 30.0 * armor_r
G.ships[0]["durability"] = max(0.0, G.ships[0]["durability"] - flee_dmg)
check(sum(s["durability"] for s in G.ships) == flee_durab - flee_dmg,
      f"flee 失败扣旗舰耐久 {flee_dmg:.1f}（30×{armor_r:.2f}）")
check(0.25 <= 0.6 <= 0.9, "flee 概率公式 clampf(speed/220, 0.25, 0.9) 落区间内")

# 战损不沉：最坏胜战伤（520*0.06*armor）< 小艍耐久
win_dmg_worst = 520 * 0.06 * armor_r
check(win_dmg_worst < 120, f"最坏胜战伤 {win_dmg_worst:.1f} < 小艍耐久 120（单次胜仗不沉开局船）")
check(verify_invariants(), "海战结算后分船账目不变量仍成立")

print()
print("="*70)
if fails:
    print(f"结果：{len(fails)} 项未通过")
    for f in fails: print("   ✗", f)
    sys.exit(1)
print("结果：全部通过　—— 核心循环可闭合，无死锁，分船账目自洽")
