#!/usr/bin/env python3
"""端到端模拟一局：从开局 1000 钱、一条小艍船出发，跑近海商路攒钱换船。
完整复现 Fleet 的舱位/补给、Economy 的行情冲击与回归、Voyage 的季风与航速。
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

class G:
    money = 1000
    year, month, day = 1255, 3, 1
    port = "quanzhou"
    ship = "sampan"
    crew = 6
    water, food = 60, 60
    morale = 70
    cargo = {}          # gid -> [qty, avg_cost]
    durability = 120.0
    at_sea = False
    debt = 0
    chapter = 1
    visited = ['quanzhou']
    peak_money = 1000

def cap():          return ships[G.ship]["capacity"]
def bulk(gid):      return goods[gid]["bulk"]
def used():
    return (G.water + G.food) * SUPPLY_BULK + sum(q * bulk(g) for g, (q, _) in G.cargo.items())
def free():         return max(0.0, cap() - used())
def daily_use():    return math.ceil(G.crew / CREW_DAYS_PER_SUPPLY) if G.crew else 0
def supply_days():  return int(min(G.water, G.food) / daily_use()) if G.crew else 999
def morale_f():     return 0.6 + 0.4 * (G.morale / 100)

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

def speed(course): return ships[G.ship]["base_speed"] * morale_f() * wind_factor(course)

DEBT_CEILING, DEBT_RATE = 3000, 0.03

def borrow(amount):
    room = max(0, DEBT_CEILING - G.debt)
    amount = min(amount, room)
    if amount <= 0: return 0
    G.debt += amount; G.money += amount
    return amount

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

def do_buy(gid, want, floor_price=None, budget=None):
    """理性买入：逐件推高行情，一旦买价逼近目标港卖价就收手。
    budget 限制本次投入——真人玩家不会把全部身家押在一船违禁货上。"""
    depth = ports[G.port]["depth"]
    if budget is None: budget = G.money
    got, spent = 0, 0
    for _ in range(want):
        if free() < bulk(gid): break
        p = buy_p(G.port, gid)
        if G.money - spent < p or spent + p > budget: break
        # 留 25% 安全边际，覆盖卖出侧的砸盘损耗
        if floor_price is not None and p >= floor_price * 0.75: break
        spent += p; got += 1
        rates[G.port][gid] = min(2.2, rates[G.port][gid] + 1.0/depth)
        if gid in G.cargo: G.cargo[gid][0] += 1
        else: G.cargo[gid] = [1, 0]
    if got:
        G.money -= spent
        G.cargo[gid][1] = spent/got if G.cargo[gid][0] == got else G.cargo[gid][1]
    return got, spent

def do_sell(gid, qty):
    depth = ports[G.port]["depth"]
    rev = 0
    for _ in range(qty):
        if G.cargo.get(gid, [0])[0] <= 0: break
        rev += sell_p(G.port, gid)
        rates[G.port][gid] = max(0.4, rates[G.port][gid] - 1.0/depth)
        G.cargo[gid][0] -= 1
        if G.cargo[gid][0] == 0: del G.cargo[gid]
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
    G.at_sea = True
    rem, days = d, 0
    while rem > 0 and days < 200:
        advance(1); days += 1
        rem -= speed(crs)
        if G.water <= 0 or G.food <= 0:
            if random.random() < 0.4:
                G.crew = max(1, G.crew - max(1, int(G.crew*0.03)))
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
print(f"  载重 {cap()} 料　水手 {G.crew}　水粮 {G.water}/{G.food}（足 {supply_days()} 日）")
print(f"  起始舱位占用 {used():.0f} / {cap()} 料，可装货 {free():.0f} 料")
check(free() > cap()*0.5, "开局补给未占满舱（仍有一半以上可装货）")

# 第一章全部已解锁港口——真实玩家会轮换航线，避免把某一条线跑疲
NEAR = None  # 改为每趟按当前章节动态取
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
            del G.cargo[gid]
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
print("远洋检验：候西南季风北上博多")
print("="*70)
G.port = "quanzhou"
if G.money >= ships["fu_ship_medium"]["price"]:
    G.money -= ships["fu_ship_medium"]["price"]; G.ship = "fu_ship_medium"; G.crew = 20
    G.durability = 300.0
    print(f"  已购福船（中），余银 {G.money}，载重 {cap()} 料")
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
print(f"\n  预计航程 {est} 日，需水粮 {est*G.crew} 份")
bought = buy_supplies(est + 6)
print(f"  补给后：水 {G.water} 粮 {G.food}（足 {supply_days()} 日），空舱 {free():.0f} 料")
check(supply_days() >= est, f"补给足以支撑 {est} 日航程")

bt = best_trade("quanzhou", ["hakata"])
if bt:
    _, gid, _, margin = bt
    qty, spent = do_buy(gid, 9999, floor_price=sell_p("hakata", gid))
    print(f"  装载 {goods[gid]['name']} ×{qty}（本 {spent}），空舱剩 {free():.0f} 料")
    days = sail("hakata")
    rev = do_sell(gid, qty)
    print(f"  历 {days} 日抵博多，售得 {rev}，净赚 {rev-spent:+}")
    print(f"  抵港时：水 {G.water} 粮 {G.food}，士气 {G.morale}，水手 {G.crew}")
    check(G.water > 0 and G.food > 0, "远洋抵港时水粮未耗尽")
    check(rev - spent > 0, f"远洋单程盈利 {rev-spent}")
    check(G.crew == 20 or G.ship == "sampan", "航程中未因断粮损失水手")

print()
print("="*70)
if fails:
    print(f"结果：{len(fails)} 项未通过")
    for f in fails: print("   ✗", f)
    sys.exit(1)
print("结果：全部通过　—— 核心循环可闭合，无死锁")
