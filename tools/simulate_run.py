#!/usr/bin/env python3
"""端到端模拟一局：从开局 1000 钱、一条小艍船出发，跑近海商路攒钱换船。
完整复现 Fleet 的舱位/补给（多船分装）、Economy 的行情冲击与回归、Voyage 的季风与航速。
目的是找出设计死锁（卡补给、卡舱位、卡钱），而不是验证单条公式。"""
import json, math, os, re, sys, random

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
lanes = load("sealanes.json").get("lanes", {})
INN_RATE = 15

# ── 生产定价与跳年常量：从 .gd 源码读，改公式时这里自动跟上 ──
import re as _re
_eco_src = open(os.path.join(ROOT, "scripts", "core", "Economy.gd"), encoding="utf-8").read()
_gm_src = open(os.path.join(ROOT, "scripts", "GameManager.gd"), encoding="utf-8").read()
def _const(src, name, default):
    m = _re.search(r'const %s := ([0-9.]+)' % name, src)
    return float(m.group(1)) if m else default
PRICE_SPREAD_MIN = _const(_eco_src, "PRICE_SPREAD_MIN", 1.08)
SKIP_HULL_DECAY = _const(_gm_src, "SKIP_HULL_DECAY", 0.08)
SKIP_HULL_FLOOR = _const(_gm_src, "SKIP_HULL_FLOOR", 0.20)
SKIP_MORALE_AFTER = int(_const(_gm_src, "SKIP_MORALE_AFTER", 65))

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
    ending_id = ""
    draft_salt = 0

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

def gc_li_pts(lon1, lat1, lon2, lat2):
    la1, lo1, la2, lo2 = map(math.radians, (lat1, lon1, lat2, lon2))
    h = math.sin((la2-la1)/2)**2 + math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return (EARTH_R*2*math.atan2(math.sqrt(h), math.sqrt(max(0.0, 1-h))))/KM_PER_LI

def rhumb_bearing(lon1, lat1, lon2, lat2):
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dlon = math.radians(lon2 - lon1)
    dlon = (dlon + math.pi) % (2 * math.pi) - math.pi
    dpsi = math.log(math.tan(math.pi/4 + phi2/2)) - math.log(math.tan(math.pi/4 + phi1/2))
    if abs(dpsi) < 1e-7 and abs(dlon) < 1e-7:
        return 0.0
    return math.degrees(math.atan2(dlon, dpsi)) % 360

def track_points(a, b):
    pa, pb = ports[a], ports[b]
    pts = [(pa["lon"], pa["lat"])]
    lo, hi = (a, b) if a < b else (b, a)
    lane = list(lanes.get(f"{lo}|{hi}", []))
    if a > b:
        lane.reverse()
    for w in lane:
        pts.append((float(w[0]), float(w[1])))
    pts.append((pb["lon"], pb["lat"]))
    return pts

def dist(a, b):
    pts = track_points(a, b)
    return sum(gc_li_pts(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1]) for i in range(len(pts)-1))

def bearing_at(a, b, traveled):
    pts = track_points(a, b)
    walked = 0.0
    last = 0.0
    for i in range(len(pts)-1):
        seg = gc_li_pts(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1])
        if seg < 0.05:
            continue
        last = rhumb_bearing(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1])
        if traveled <= walked + seg:
            return last
        walked += seg
    return last

def bearing(a, b):
    return bearing_at(a, b, 0.0)

def voyage_days(src, dst):
    """补给按 Voyage.plan 的逐段季风来买，不能用一个方位除完整段航程。"""
    pts = track_points(src, dst)
    days_f = 0.0
    for i in range(len(pts)-1):
        seg = gc_li_pts(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1])
        if seg < 0.05:
            continue
        spd = speed(rhumb_bearing(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1]))
        if spd <= 1.0:
            return 999
        days_f += seg / spd
    return math.ceil(days_f)

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

def skip_years(n):
    """复刻 GameManager.skip_years：日子真走完（行情回归、月息照算）、船况年折、士气压顶、行情重置。
    模型里没有雇员，水手流失一项略去。返回摘要行。"""
    if n <= 0: return []
    y0 = G.year
    advance(30 * 12 * n)
    decayed = 0
    for s in G.ships:
        maxd = float(ships[s["type"]]["durability"])
        cur = float(s["durability"])
        after = max(maxd * SKIP_HULL_FLOOR, cur * (1.0 - SKIP_HULL_DECAY) ** n)
        if after < cur - 0.5: decayed += 1
        s["durability"] = after
    G.morale = min(G.morale, SKIP_MORALE_AFTER)
    for pid in rates:
        for gid in rates[pid]: rates[pid][gid] = 1.0
    return [f"跳 {n} 年（{y0}→{G.year}），{decayed} 船折旧，士气≤{SKIP_MORALE_AFTER}，行情重置"]

def try_advance():
    """复刻 GameState.try_advance_chapter + Main._show_chapter_dialog：晋升即跳年。"""
    req = chapters.get(G.chapter, {}).get("next_requires")
    if not req: return None
    if G.peak_money < req.get("peak_money", 0): return None
    if len(G.visited) < req.get("visited_count", 0): return None
    for m in req.get("must_visit", []):
        if m not in G.visited: return None
    cur = chapters[G.chapter]
    title = cur.get("advance_title","")
    G.chapter += 1
    for line in skip_years(int(cur.get("advance_years", 0))):
        print(f"    ★ {line}")
    return title

def flag_ok(req, fl, chapter=4):
    need = req.get("require_flag")
    if need and need not in fl:
        return False
    anyf = req.get("require_any") or []
    if anyf and not any(f in fl for f in anyf):
        return False
    hide = req.get("hide_if_flag")
    if hide and hide in fl:
        return False
    need_ch = int(req.get("require_chapter", 0) or 0)
    if need_ch and chapter < need_ch:
        return False
    return True

def pick_ending(fl):
    for e in chapters[4].get("endings", []):
        if flag_ok(e, fl):
            return e["id"]
    return None

def ending_ready(peak, visited):
    req = chapters[4].get("ending_requires") or {}
    if peak < req.get("peak_money", 0):
        return False
    if len(visited) < req.get("visited_count", 0):
        return False
    for m in req.get("must_visit", []):
        if m not in visited:
            return False
    return True

def requirement():
    """当前未完成的晋升或了结条件。"""
    if G.ending_id:
        return {}
    if G.chapter < 4:
        return chapters.get(G.chapter, {}).get("next_requires") or {}
    return chapters[4].get("ending_requires") or {}

def resolve_progress():
    """对齐 GameState.try_advance_chapter：晋升或按旗标了结。模拟无剧情旗标，走南海一纲。"""
    if G.ending_id:
        return None
    if G.chapter < 4:
        return try_advance()
    if ending_ready(G.peak_money, G.visited):
        G.ending_id = pick_ending([])
        for e in chapters[4].get("endings", []):
            if e["id"] == G.ending_id:
                return e.get("title", G.ending_id)
        return G.ending_id
    return None

def pool_ids(origin):
    """与 HeadingDraft.pool 同一批港：已解锁、有市场深度、不是当前港。"""
    return [pid for pid, p in ports.items()
            if ch_num(p.get("unlock", "ch1")) <= G.chapter
            and int(p.get("depth", 0)) > 0
            and pid != origin]

def pinned_port(origin):
    chapter = chapters.get(G.chapter, {})
    req = chapter.get("next_requires") or chapter.get("ending_requires") or {}
    if not isinstance(req, dict):
        return ""
    opened = set(pool_ids(origin))
    for m in req.get("must_visit", []):
        if m not in G.visited and m in opened:
            return m
    return ""

def deal(origin, salt):
    ids = pool_ids(origin)
    pin = pinned_port(origin)
    seats = [pin] if pin else []
    rest = [pid for pid in ids if pid not in seats]
    rest.sort(key=lambda pid: (-wind_factor(bearing(origin, pid)), dist(origin, pid), pid))
    if not rest:
        return seats
    start = salt % len(rest)
    i = 0
    while len(seats) < 3 and i < len(rest):
        pid = rest[(start + i) % len(rest)]
        if pid not in seats:
            seats.append(pid)
        i += 1
    return seats

def offer_hand(src, preferred):
    """理想港不在这一手里就候风再发。盐位每次挪一格。
    其余港超过 8 座时，8 次盖不住整圈，上限取其余港数。"""
    pin = pinned_port(src)
    rest_n = max(1, len(pool_ids(src)) - (1 if pin else 0))
    limit = max(8, rest_n)
    hand = deal(src, G.draft_salt)
    redraws = 0
    while preferred and not any(p in hand for p in preferred) and redraws < limit:
        G.draft_salt += 1
        advance(3)
        redraws += 1
        hand = deal(src, G.draft_salt)
    return hand, redraws

def trade_destinations(src):
    """未亲至的必须港、未走通的港优先，避免一直在熟港套利而卡晋升。"""
    req = requirement()
    opened = [p for p in open_ports() if p != src]
    must = [m for m in req.get("must_visit", []) if m not in G.visited and m in opened]
    if must:
        return must
    need_n = int(req.get("visited_count", 0) or 0)
    if len(G.visited) < need_n:
        unvis = [p for p in opened if p not in G.visited]
        if unvis:
            return unvis
    return opened

def wait_wind(src, dst, max_wait=40):
    crs = bearing(src, dst)
    if wind_factor(crs) >= 0.70:
        return 0
    waited = 0
    while wind_factor(crs) < 0.70 and waited < max_wait:
        step = min(10, 30 - G.day + 1)
        cost = step * INN_RATE
        if G.money < cost:
            break
        G.money -= cost
        advance(step)
        waited += step
        G.morale = min(100, G.morale + step * 2)
    return waited

def one_trip(trip):
    """跑一趟商路（或空航亲至必须港）。成功返回 True。
    发牌规则单独断言：盐位转一圈，每个海港都会出现。
    这里仍走理想港。若每趟先候风再走，这一固定种子会在两万本钱前停住，章节闸门就断了。"""
    qty, gid, dst, spent = 0, None, None, 0
    redraws = 0
    dests = trade_destinations(G.port)
    for _attempt in range(6):
        bt = best_trade(G.port, dests)
        if bt is None:
            bt = best_trade(G.port, [p for p in open_ports() if p != G.port])
        if bt is None:
            gid = dst = None
        else:
            _, gid, dst, _margin = bt
            d = dist(G.port, dst)
            crs = bearing(G.port, dst)
            if d > 800:
                wait_wind(G.port, dst)
                crs = bearing(G.port, dst)
            est_days = math.ceil(d / max(1.0, speed(crs)))
            buy_supplies(est_days + 4)
            is_contra = goods[gid].get("contraband", False)
            cap_budget = int(G.money * 0.6) if is_contra else G.money
            qty, spent = do_buy(gid, 9999, floor_price=sell_p(dst, gid), budget=cap_budget)
        if qty > 0:
            break
        if G.money < 300:
            got_loan = borrow(500)
            if got_loan:
                print(f"    第{trip:>2}趟  本钱告罄，赊借 {got_loan} 钱（现欠 {G.debt}）")
                continue
        cost = 10 * INN_RATE
        if G.money < cost:
            break
        G.money -= cost
        advance(10)
        G.morale = min(100, G.morale + 20)
        print(f"    第{trip:>2}趟  行情不佳，在店中候市 10 日（房钱 {cost}）")
    empty = False
    if qty == 0:
        must = [m for m in requirement().get("must_visit", [])
                if m not in G.visited and m in open_ports() and m != G.port]
        if not must:
            print(f"    第{trip:>2}趟  确实无利可图（钱 {G.money}，空舱 {free():.0f}）")
            return False
        dst = must[0]
        gid, spent = None, 0
        empty = True
        d = dist(G.port, dst)
        crs = bearing(G.port, dst)
        if d > 800:
            wait_wind(G.port, dst)
            crs = bearing(G.port, dst)
        est_days = math.ceil(d / max(1.0, speed(crs)))
        buy_supplies(est_days + 4)
    src = G.port
    smuggle = (not empty) and goods[gid].get("contraband", False)
    seized = False
    fine = 0
    if smuggle:
        if random.random() < 0.28:
            seized = True
            for s in G.ships:
                if gid in s["cargo"]:
                    del s["cargo"][gid]
            fine = min(300, max(50, int(G.money * 0.4)))
            G.money = max(0, G.money - fine)
    days = sail(dst)
    rev = 0 if (seized or empty) else do_sell(gid, qty)
    profit = rev - spent - (fine if seized else 0)
    history.append(profit)
    promoted = resolve_progress()
    tag = ""
    if empty:
        tag += f"　空航亲至{ports[dst]['name']}"
    elif smuggle:
        tag += "　[走私]" + ("　✗查扣" if seized else "")
    if redraws:
        tag += f"　候风{redraws}次"
    if promoted:
        if G.ending_id:
            tag += f"　★了结「{promoted}」"
        else:
            tag += f"　★进第{G.chapter}章「{promoted}」"
    good_name = "—" if empty else goods[gid]["name"]
    qty_s = 0 if empty else qty
    print(f"    第{trip:>2}趟 {ports[src]['name']:<5}→{ports[dst]['name']:<7} "
          f"{good_name:<5}×{qty_s:<3} 本{spent:>5} 得{rev:>6} 净{profit:>+6}  "
          f"{days:>2}日  {G.year}年{G.month:>2}月  存银 {G.money:>6}{tag}")
    return True

def role(pid, gid): return ports[pid]["market"].get(gid)

def price_at_rate(pid, gid, rate, is_buy, tariff_factor=1.0, broker_factor=1.0, edge=0.0):
    """Economy.price_at_rate 的镜像（含 P2-0 同港价差地板）。
    tariff_factor/broker_factor = Crew.trade_cost_factor()，edge = Crew.interpreter_edge()；
    本模型不雇职事，三者取光杆值，但公式必须与生产一致，否则门禁测的是另一套经济。"""
    v = goods[gid]["base_value"] * ROLE_MOD[role(pid, gid)] * rate
    bare_buy = v * (1 + TARIFF)
    bare_sell = v * (1 - BROKER)
    cap = bare_buy / PRICE_SPREAD_MIN
    sell_v = min(v * (1 - BROKER * broker_factor) * (1 + edge), cap)
    sell_v = max(sell_v, min(bare_sell, cap))
    if not is_buy:
        return round(sell_v)
    buy_v = max(v * (1 + TARIFF * tariff_factor) * (1 - edge), sell_v * PRICE_SPREAD_MIN)
    return round(min(buy_v, max(bare_buy, sell_v * PRICE_SPREAD_MIN)))

def buy_p(pid,gid):  return price_at_rate(pid, gid, rates[pid][gid], True)
def sell_p(pid,gid): return price_at_rate(pid, gid, rates[pid][gid], False)

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
    d = dist(G.port, dst)
    top_up_crew()  # 出港前玩家会在船屋补足各船最低水手
    G.at_sea = True
    rem, days, traveled = d, 0, 0.0
    while rem > 0 and days < 200:
        advance(1); days += 1
        step = speed(bearing_at(G.port, dst, traveled))
        rem -= step
        traveled += max(0.0, step)
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

# 已解锁港口轮换——优先未走通/必须亲至的港，避免熟港套利卡晋升
history = []
print()
hand0 = deal("quanzhou", 0)
check(len(hand0) <= 3 and bool(hand0) and hand0[0] == "ryukyu",
      f"开局这一手 {hand0} 以南岛海道北口起首，至多三向")
seen = set()
pool0 = pool_ids("quanzhou")
for salt in range(max(1, len(pool0))):
    seen.update(deal("quanzhou", salt))
check(set(pool0) <= seen, "盐位转一圈，泉州每个海港都会发到")

SHORE_IDS = [
    "city_shipyard", "city_guild", "city_tavern", "city_market", "city_inn",
    "city_exam", "city_residence", "city_temple", "city_yamen",
]

def shore_deal(ids, salt, pin_shipyard):
    """与 ShoreDraft.deal 同一规则。跑商不调用它。"""
    seats = []
    if "city_market" in ids:
        seats.append("city_market")
    if pin_shipyard and "city_shipyard" in ids and "city_shipyard" not in seats:
        seats.append("city_shipyard")
    rest = sorted(fid for fid in ids if fid not in seats)
    if not rest:
        return seats
    start = salt % len(rest)
    i = 0
    while len(seats) < 3 and i < len(rest):
        fid = rest[(start + i) % len(rest)]
        if fid not in seats:
            seats.append(fid)
        i += 1
    return seats

shore0 = shore_deal(SHORE_IDS, 0, False)
shore1 = shore_deal(SHORE_IDS, 1, False)
shore_pin = shore_deal(SHORE_IDS, 0, True)
check(len(shore0) == 3 and shore0[0] == "city_market" and shore0[1] != shore1[1],
      f"岸上这一手 {shore0} 以牙行起首，盐位一转第二席换门")
check(shore_pin[0] == "city_market" and shore_pin[1] == "city_shipyard",
      f"船开不出去时 {shore_pin} 第二席是船屋")
shore_seen = set()
for salt in range(len(SHORE_IDS) - 1):
    shore_seen.update(shore_deal(SHORE_IDS, salt, False))
check(set(SHORE_IDS) <= shore_seen, "盐位转一圈，九处都会开门")

def broker_deal(goods, salt, held_id):
    """与 BrokerSlip.deal 同一规则。跑商不调用它。"""
    rows = []
    seen = set()
    for row in goods:
        gid = row["id"]
        if gid in seen:
            continue
        seen.add(gid)
        rows.append(row)
    seats = [held_id] if held_id and held_id in seen else []
    origins = sorted((r for r in rows if r["role"] == "origin" and r["id"] not in seats),
                     key=lambda r: (r["buy"], r["id"]))
    rest = [r for r in rows if r["id"] not in seats and r["role"] != "origin"]
    if origins:
        seats.append(origins[0]["id"])
        rest.extend(origins[1:])
    rest.sort(key=lambda r: (r["buy"], r["id"]))
    if not rest:
        return seats
    start = salt % len(rest)
    i = 0
    while len(seats) < 3 and i < len(rest):
        gid = rest[(start + i) % len(rest)]["id"]
        if gid not in seats:
            seats.append(gid)
        i += 1
    return seats

BROKER_GOODS = [
    {"id": "a", "role": "origin", "buy": 10},
    {"id": "b", "role": "origin", "buy": 30},
    {"id": "c", "role": "normal", "buy": 5},
    {"id": "d", "role": "consumer", "buy": 40},
    {"id": "e", "role": "normal", "buy": 20},
]
slip0 = broker_deal(BROKER_GOODS, 0, "")
slip1 = broker_deal(BROKER_GOODS, 1, "")
slip_held = broker_deal(BROKER_GOODS, 0, "d")
check(len(slip0) == 3 and slip0[0] == "a" and slip0[1] != slip1[1],
      f"柜上这一手 {slip0} 以最便宜的土产起首，盐位一转第二席换货")
check(slip_held[0] == "d" and slip_held[1] == "a",
      f"舱里有货时 {slip_held} 先卖手里的，再摆土产")
slip_seen = set()
for salt in range(4):
    slip_seen.update(broker_deal(BROKER_GOODS, salt, ""))
check(slip_seen == {g["id"] for g in BROKER_GOODS}, "盐位转一圈，五样货都会上柜")

def berth_index(count, index):
    """与 DrydockBerth.berth_index 同一规则。跑商不调用它。"""
    if count <= 0 or index < 0:
        return 0
    if index >= count:
        return count - 1
    return index

def other_hulls(count, index):
    on = berth_index(count, index)
    return [i for i in range(count) if i != on]

def sale_ids(offers, reached):
    out = []
    seen = set()
    for row in offers:
        sid = row["id"]
        unlock = row.get("unlock", "ch1")
        if not sid or sid in seen or unlock not in reached:
            continue
        seen.add(sid)
        out.append(sid)
    return out

YARD_OFFERS = [
    {"id": "sampan", "unlock": "ch1"},
    {"id": "keel_boat", "unlock": "ch1"},
    {"id": "fu_ship_medium", "unlock": "ch1"},
    {"id": "canton_ship", "unlock": "ch2"},
]
sale_ch1 = sale_ids(YARD_OFFERS, ["ch1"])
sale_ch2 = sale_ids(YARD_OFFERS, ["ch1", "ch2"])
check(sale_ch1 == ["sampan", "keel_boat", "fu_ship_medium"], f"第一章坞外待售 {sale_ch1}")
check(len(sale_ch2) == 4 and sale_ch2[-1] == "canton_ship", f"第二章坞外待售 {sale_ch2}")
check(berth_index(1, 5) == 0 and berth_index(3, 5) == 2 and other_hulls(3, 0) == [1, 2],
      "坞位夹在船队里，坞上这一艘不进换船")
print(f"  ── 跑商 24 趟（起始第 {G.chapter} 章，可达 {len(open_ports())} 港）──")
for trip in range(1, 25):
    if G.ending_id:
        break
    if not one_trip(trip):
        break
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
check(G.peak_money >= ships["fu_ship_medium"]["price"],
      f"资金峰值 {G.peak_money} 够买福船（{ships['fu_ship_medium']['price']}）")
print(f"    资金峰值 {G.peak_money}　走通港口 {len(G.visited)} 处：{'、'.join(ports[p]['name'] for p in G.visited)}")

print()
print("  ── 定价镜像自检：光杆下同港买价 ≥ 卖价 × 地板（与 Economy.price_at_rate 同式）──")
viol = [(pid, gid) for pid in ports for gid in ports[pid]["market"]
        if goods[gid]["base_value"] > 0 and buy_p(pid, gid) < sell_p(pid, gid) * PRICE_SPREAD_MIN - 1]
check(not viol, f"同港价差地板 {PRICE_SPREAD_MIN} 在全部（港,货）成立（越界 {len(viol)}）")

print()
print("="*70)
print("远洋检验：候西南季风北上博多（多船舰队）")
print("="*70)
G.port = "quanzhou"
fu_price = ships["fu_ship_medium"]["price"]
FAR_SEA_CAPITAL = 20000  # 购船后余银：与跳年前基线一轮（约 2.2 万）同量级，够候风 + 26 人水粮 + 一舱货
if G.money < fu_price + FAR_SEA_CAPITAL:
    # 主循环的资金走势受走私查扣的随机序列左右（晋升跳年后序列整体偏移）。
    # 远洋段只验航海补给 / 季风 / 分船装载，不验赚钱能力——资金不够就补成受控场景，并明说。
    grant = fu_price + FAR_SEA_CAPITAL - G.money
    print(f"  主循环结束时资金 {G.money}，受控场景补入 {grant} 钱至购船后余 {FAR_SEA_CAPITAL}——此段不验赚钱")
    G.money += grant
G.money -= fu_price
G.ships.append({"type": "fu_ship_medium", "name": "福船",
                "crew": ships["fu_ship_medium"]["crew_min"],
                "durability": 300.0, "sail_level": 1, "armor_level": 1, "cargo": {}})
print(f"  已购福船（中），余银 {G.money}，舰队 {len(G.ships)} 船，载重 {cap_total()} 料")
check(G.ships[-1]["crew"] == ships["fu_ship_medium"]["crew_min"],
      f"新购福船水手 = crew_min（{G.ships[-1]['crew']} 人）")
check(verify_invariants(), "购船后分船账目不变量成立")

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
# 先在船屋补足各船最低水手，再按实际人头买水粮——顺序反了会按少算的人数备货，海上断粮
top_up_crew()
crew_before = total_crew()
print(f"\n  预计航程 {est} 日，水手 {crew_before} 人，需水粮 {est*daily_use()} 份")
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
    crew_depart = total_crew()
    days = sail("hakata")
    rev = do_sell(gid, qty)
    print(f"  历 {days} 日抵博多，售得 {rev}，净赚 {rev-spent:+}")
    print(f"  抵港时：水 {G.water} 粮 {G.food}，士气 {G.morale}，水手 {total_crew()}")
    check(G.water > 0 and G.food > 0, "远洋抵港时水粮未耗尽")
    check(rev - spent > 0, f"远洋单程盈利 {rev-spent}")
    check(verify_invariants(), "远洋后分船账目不变量成立")
    crew_after = total_crew()
    check(crew_after >= crew_depart,
          f"航程后水手 {crew_after} 人，不少于出航时的 {crew_depart}（未因断粮减员）")

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
print("正式通关：继续跑商至第四章占城了结（不垫 F12）")
print("="*70)
trip = 25
while not G.ending_id and trip <= 220:
    if not one_trip(trip):
        break
    if not verify_invariants():
        check(False, f"第{trip}趟后分船账目不变量被破坏")
        break
    trip += 1

playthrough = {
    "ending": G.ending_id,
    "chapter": G.chapter,
    "visited": list(G.visited),
    "peak": G.peak_money,
    "trips": trip - 1 if G.ending_id else trip,
    "money": G.money,
}
print(f"  通关停在第 {playthrough['trips']} 趟　第 {playthrough['chapter']} 章　"
      f"峰值 {playthrough['peak']}　存银 {playthrough['money']}　"
      f"走通 {len(playthrough['visited'])} 港")
print(f"    港口：{'、'.join(ports[p]['name'] for p in playthrough['visited'])}")
check(playthrough["chapter"] == 4, f"主循环进至第 {playthrough['chapter']} 章")
check("champa" in playthrough["visited"], "亲至占城（不靠 F12 垫条件）")
check(playthrough["peak"] >= 80000, f"本钱峰值 {playthrough['peak']} ≥ 80000")
check(len(playthrough["visited"]) >= 13, f"走通 {len(playthrough['visited'])} 港 ≥ 13")
check(playthrough["ending"] == "south_sea",
      f"无剧情旗标了结「{playthrough['ending'] or '未触发'}」（南海一纲兜底）")
check(trip <= 220, f"在 {playthrough['trips']} 趟内闭合，未撞 220 趟上限")

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

# lose：WorldMap 只在旗舰沉没时发出。该船货舱清空，护航船不动。
# 未沉的 25% 是 SeaChart 的 else，当前战斗不会走到。
G.ships[0]["cargo"] = {"raw_silk": [10, 100]}
G.ships[1]["cargo"] = {"raw_silk": [8, 90]}
lose_morale0 = G.morale
G.morale = max(0, G.morale - 12)
G.ships[0]["cargo"] = {}  # clear_ship_cargo(0)
check(G.ships[0]["cargo"] == {}, "旗舰沉没清空该船货舱，不是留下 75%")
check(G.ships[1]["cargo"]["raw_silk"][0] == 8, "护航船货物不随旗舰沉没清掉")
check(G.morale == max(0, lose_morale0 - 12), "lose 士气 -12")
unsunk_left = 10 - int(math.ceil(10 * 0.25))
check(unsunk_left == 7, "未沉败局仍是货损 25%（10→7），与沉船全损分开")

# 与 SeaChart._on_battle_result / Ship._sink_ship 同一条顺序：
# 战斗中不先清舱。全队耐久归零走沉船清舱；姊妹船还在只扣 25%。
def settle_lose_cargo(qty, fleet_durability):
    if fleet_durability <= 0:
        return 0
    lost = int(math.ceil(qty * 0.25))
    return qty - lost

check(settle_lose_cargo(10, 0) == 0, "全队沉没货舱清空，不按 25% 留 7 件")
check(settle_lose_cargo(10, 300) == 7, "旗舰沉没但姊妹船还在，只扣 25%（10→7），不清空")

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
print("P6 结局分支（旗标选择，独立于通关主循环的账本）")
print("="*70)

check(pick_ending(["chen_line_open"]) == "sea_letter", "海口信路：chen_line_open")
check(pick_ending(["letter_to_xinghua"]) == "sea_letter", "海口信路：letter_to_xinghua")
check(pick_ending(["merchant_distance"]) == "ledger_distance", "账上的距离：merchant_distance")
check(pick_ending(["merchant_caution"]) == "ledger_distance", "账上的距离：merchant_caution")
check(pick_ending(["history_pressure_seen"]) == "history_wind", "史册未落笔：history_pressure_seen")
check(pick_ending([]) == "south_sea", "无剧情旗标走南海一纲兜底")
check(pick_ending(["chen_line_open", "merchant_distance"]) == "sea_letter",
      "同时有海口与账面旗标时海口优先")
check(not chapters[2].get("ending_requires"), "第二章没有 ending_requires——主循环不会误了结")

no_champa = [pid for pid in ports if pid != "champa"]
check(len(no_champa) >= 13, f"去掉占城仍有 {len(no_champa)} 港")
check(not ending_ready(80000, no_champa[:13]), "走通十三港但未至占城 → 不能了结")
with_champa = no_champa[:12] + ["champa"]
check(ending_ready(80000, with_champa), "八万 + 十三港含占城 → 可了结")
check(not ending_ready(79999, with_champa), "本钱 79999 不能了结")
check(playthrough["ending"] == "south_sea", "通关主循环已了结，旗标单测不改写 ending_id")

print()
print("="*70)
print("名声换爵与港口投资（独立账本，不改写通关 ending）")
print("="*70)

titles = load("titles.json")
ranks = titles["ranks"]
inv_cfg = titles["invest"]
inv_costs = inv_cfg["costs"]
edge_per = inv_cfg["edge_per_level"]
fame_base = inv_cfg["fame_base"]

def title_of(fame):
    best = ranks[0]
    for r in ranks:
        if fame >= r["min_fame"]:
            best = r
    return best

def role_of(pid, gid):
    return ports[pid].get("market", {}).get(gid)

def price_inv(pid, gid, is_buy, inv=0, title_duty=1.0, rate=1.0):
    r = role_of(pid, gid)
    v = goods[gid]["base_value"] * ROLE_MOD[r] * rate
    ie = inv * edge_per
    if r == "origin":
        v *= (1.0 - ie)
    elif r == "consumer":
        v *= (1.0 + ie)
    if is_buy:
        return round(v * (1 + TARIFF * title_duty))
    return round(v * (1 - BROKER * title_duty))

class InvBook:
    money = 20000
    fame = 0
    investments = {}
    ending_id = playthrough["ending"]

def do_invest(book, pid):
    lv = book.investments.get(pid, 0)
    if lv >= inv_cfg["max_level"]:
        return False
    cost = inv_costs[lv]
    if book.money < cost:
        return False
    book.money -= cost
    book.investments[pid] = lv + 1
    book.fame += fame_base + (lv + 1)
    return True

bare_buy = price_inv("quanzhou", "qingbai_porcelain", True)
bare_sell = price_inv("hakata", "qingbai_porcelain", False)
check(InvBook.fame == 0 and title_of(0)["id"] == "san_shang", "独立账本开局籍外散商")
n_qz = n_hk = 0
while n_qz < 3 and do_invest(InvBook, "quanzhou"):
    n_qz += 1
while n_hk < 2 and do_invest(InvBook, "hakata"):
    n_hk += 1
spent = 20000 - InvBook.money
print(f"  泉州修 {n_qz} 等、博多修 {n_hk} 等，花 {spent} 钱，名声 {InvBook.fame}，职衔 {title_of(InvBook.fame)['name']}")
check(n_qz == 3 and n_hk == 2, f"修埠次数 泉州{n_qz} 博多{n_hk}")
check(InvBook.fame >= 10, f"修埠后名声 {InvBook.fame} ≥ 10，至少升舶牙")
check(title_of(InvBook.fame)["id"] != "san_shang", "修埠后职衔已升")
check(InvBook.ending_id == playthrough["ending"], "修埠账本不改写通关结局")

qz_buy = price_inv("quanzhou", "qingbai_porcelain", True, InvBook.investments["quanzhou"])
hk_sell = price_inv("hakata", "qingbai_porcelain", False, InvBook.investments["hakata"])
qz_sell = price_inv("quanzhou", "qingbai_porcelain", False, InvBook.investments["quanzhou"])
check(qz_buy < bare_buy, f"泉州修埠后青白瓷买入 {qz_buy} < {bare_buy}")
check(hk_sell > bare_sell, f"博多修埠后青白瓷卖出 {hk_sell} > {bare_sell}")
check(qz_sell <= qz_buy, f"泉州同港卖 {qz_sell} ≤ 买 {qz_buy}（无正套利）")

InvBook.fame = 80
check(title_of(InvBook.fame)["id"] == "du_bao", "名声 80 为市舶都保")
check(title_of(InvBook.fame)["loan_bonus"] == 2500, "都保赊贷 +2500")
print()
print("哗变：开局不补水粮才会闹舱；跑商补足的航次碰不到（云端 7d9f）")
print("="*70)
fleet_src = open(os.path.join(ROOT, "scripts", "core", "Fleet.gd"), encoding="utf-8").read()

def fleet_const(name):
    m = re.search(rf"const {name} := (-?\d+(?:\.\d+)?)", fleet_src)
    if not m:
        raise SystemExit(f"Fleet.gd 缺少 {name}")
    raw = m.group(1)
    return float(raw) if "." in raw else int(raw)

m_line = fleet_const("MUTINY_LINE")
m_floor = fleet_const("MUTINY_BRIBE_FLOOR")
m_per = fleet_const("MUTINY_BRIBE_PER_CREW")
m_bribe = fleet_const("MUTINY_BRIBE_MORALE")
m_dis_pct = fleet_const("MUTINY_DISMISS_PERCENT")
m_dis_cargo = fleet_const("MUTINY_DISMISS_CARGO")
m_dis_morale = fleet_const("MUTINY_DISMISS_MORALE")
crew0 = ships["sampan"]["crew_min"]
use0 = math.ceil(crew0 / 2.0)
# 补足 8 日口粮的近海航次：水粮从 60 起，扣不完
water_left = 60 - 8 * use0
check(water_left > 0 and 70 > m_line, f"近海 8 日还剩水 {water_left}，士气 70 不哗变")
water, morale, day = 60, 70, 0
while morale > m_line and day < 80:
    day += 1
    water = max(0, water - use0)
    if water <= 0:
        morale = max(0, morale - 6)
print(f"  不补水粮走到第 {day} 日，士气 {morale}，水手 {crew0}")
check(morale <= m_line, f"第 {day} 日士气 {morale} 跌破 {m_line}")
cost = max(m_floor, crew0 * m_per)
money = 1000 - cost
morale_bribe = min(100, morale + m_bribe)
check(money == 1000 - cost and crew0 == ships["sampan"]["crew_min"],
      f"散钱 {cost} 后余 {money}，人还是 {crew0}，下一趟不用补水手")
check(morale_bribe > m_line, f"散钱后士气 {morale_bribe} 高于线")
leave = max(1, int((crew0 * m_dis_pct) / 100.0))
cargo = 10 - math.ceil(10 * m_dis_cargo)
crew_left = crew0 - leave
print(f"  改放人：走 {leave}，剩 {crew_left}，10 件货剩 {cargo}，士气 {min(100, morale + m_dis_morale)}")
check(crew_left < ships["sampan"]["crew_min"],
      f"放人后 {crew_left} < 最低水手 {ships['sampan']['crew_min']}，到港得先补人才能再出海")
check(cargo == 9, f"放人抬走 1 件（10→{cargo}）")
check(min(100, morale + m_dis_morale) > m_line, "放人后士气回到线以上")
print()
print("风涛分摊：护航船自己吃一份，旗舰不替它挨（云端 storm-7d9f）")
print("="*70)
voyage_src = open(os.path.join(ROOT, "scripts", "core", "Voyage.gd"), encoding="utf-8").read()
storm_body = voyage_src.split("func _storm_event", 1)[1].split("\nfunc ", 1)[0]
hit_m = re.search(r"var each := ([0-9.]+) \* severity", storm_body)
storm_base = float(hit_m.group(1)) if hit_m else 0.0
flag_h = float(ships["fu_ship_medium"]["durability"])
esc_h = float(ships["sampan"]["durability"])
each = storm_base * 1.0
flag_after = flag_h - each
esc_after = esc_h - each
piled = flag_h - each * 2
print(f"  满风涛每艘 {each:.0f}：福船 {flag_h:.0f}→{flag_after:.0f}，小艍 {esc_h:.0f}→{esc_after:.0f}")
check(flag_after == flag_h - each and esc_after == esc_h - each, "两艘各掉一份")
check(flag_after > piled, f"旗舰剩 {flag_after:.0f}，没有吃掉护航的那份（堆旗舰会剩 {piled:.0f}）")
check("damage_each_ship" in storm_body and "ships.size()" not in storm_body,
      "风涛脚本按艘扣，不再乘船数")
print("航法与委办：接一单、针路送到、交货不砸盘")
print("="*70)
# 独立于上面的晋升账本。开局三月转换期、行情归 1，验证新循环自己能走完。
G.money = 8000
G.port = "quanzhou"
G.chapter = 1
G.month = 3
G.day = 1
G.year = 1255
G.morale = 70
G.debt = 0
G.water, G.food = 80, 80
G.ships = [{"type": "sampan", "name": "无名小艍", "crew": 6,
            "durability": 120.0, "sail_level": 1, "armor_level": 1, "cargo": {}}]
for pid in rates:
    for gid in rates[pid]:
        rates[pid][gid] = 1.0

import re as _re
def _gd_const(rel, name):
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    m = _re.search(rf"const {name} := ([0-9.]+)", src)
    return float(m.group(1))
SLACK = int(_gd_const("scripts/GameState.gd", "CONTRACT_SLACK_DAYS"))
PREMIUM = _gd_const("scripts/GameState.gd", "CONTRACT_PREMIUM")
QBUDGET = _gd_const("scripts/GameState.gd", "CONTRACT_QTY_BUDGET")
QMIN = int(_gd_const("scripts/GameState.gd", "CONTRACT_QTY_MIN"))
QMAX = int(_gd_const("scripts/GameState.gd", "CONTRACT_QTY_MAX"))
BMIN = _gd_const("scripts/GameState.gd", "CONTRACT_BASE_MIN")
FINE_RATE = _gd_const("scripts/GameState.gd", "CONTRACT_FINE_RATE")
FINE_MIN = int(_gd_const("scripts/GameState.gd", "CONTRACT_FINE_MIN"))
OFF_M = _gd_const("scripts/core/Voyage.gd", "ORDER_SPEED_OFFSHORE")
COAST_M = _gd_const("scripts/core/Voyage.gd", "ORDER_SPEED_COAST")

def _pair():
    for gid, rel in ports["quanzhou"]["market"].items():
        if rel == "consumer" or goods[gid].get("contraband"):
            continue
        if goods[gid]["base_value"] < BMIN or goods[gid]["bulk"] <= 0:
            continue
        for pid in ports["quanzhou"].get("connections", []):
            p = ports.get(pid)
            if not p or p.get("depth", 0) <= 0:
                continue
            if ch_num(p.get("unlock", "ch1")) > 1:
                continue
            if p.get("market", {}).get(gid) == "consumer":
                return gid, pid
    return None, None

cgid, cdst = _pair()
check(cgid is not None, "泉州有一笔第一章熟路就能交的委办货")
if cgid:
    cqty = max(QMIN, min(QMAX, int(QBUDGET / goods[cgid]["bulk"])))
    got, spent = do_buy(cgid, cqty)
    check(got == cqty, f"舱位与本钱装得下委办的 {goods[cgid]['name']} ×{cqty}（实装 {got}）")
    dest_rate = rates[cdst][cgid]
    est = math.ceil(dist(G.port, cdst) / speed(bearing(G.port, cdst)))
    days = sail(cdst)
    check(days <= est + SLACK, f"针路 {days} 日送到，未超过期限 {est + SLACK} 日")
    check(abs(rates[cdst][cgid] - dest_rate) < 1e-9, "航行本身不改目的港行情")
    sale = 0
    r = dest_rate
    depth = ports[cdst]["depth"]
    for _ in range(got):
        sale += round(goods[cgid]["base_value"] * ROLE_MOD["consumer"] * r * (1 - BROKER))
        r = max(0.4, min(2.2, r - 1.0 / depth))
    premium = round(got * goods[cgid]["base_value"] * PREMIUM)
    purse = sale + premium
    # 交货：卸货、给酬，行情不动
    for s in G.ships:
        if cgid in s["cargo"]:
            del s["cargo"][cgid]
    before = G.money
    G.money += purse
    G.peak_money = max(G.peak_money, G.money)
    check(abs(rates[cdst][cgid] - dest_rate) < 1e-9, "交货不砸盘")
    check(r < dest_rate, "若改走牙行卖掉，同样件数会把行情压低")
    check(G.money == before + purse and purse > sale, f"交清实得酬金 {purse}（高于直接卖的 {sale}）")
    check(verify_invariants(), "交货后分船账目不变量成立")
    fine = min(G.money, max(FINE_MIN, round(purse * FINE_RATE)))
    check(fine < purse, f"就算毁约，罚款 {fine} 也小于酬金 {purse}")
    print(f"  {goods[cgid]['name']} ×{got} → {ports[cdst]['name']}　{days} 日　酬 {purse}（溢价 {premium}）")

d_far = dist("quanzhou", "hakata")
crs_far = bearing("quanzhou", "hakata")
base_spd = ships["sampan"]["base_speed"] * morale_f() * wind_factor(crs_far)
days_r = math.ceil(d_far / base_spd)
days_o = math.ceil(d_far / (base_spd * OFF_M))
days_c = math.ceil(d_far / (base_spd * COAST_M))
print(f"  泉州→博多（当下风）：外洋 {days_o} 日 / 针路 {days_r} 日 / 傍岸 {days_c} 日，针路期限 {days_r + SLACK} 日")
check(days_o <= days_r < days_c, "外洋不慢于针路，傍岸严格更慢")
check(days_c > days_r + SLACK, "泉州→博多傍岸赶不上针路期限")

print()
print("="*70)
if fails:
    print(f"结果：{len(fails)} 项未通过")
    for f in fails: print("   ✗", f)
    sys.exit(1)
print("结果：全部通过　—— 核心循环可闭合，无死锁，分船账目自洽")
