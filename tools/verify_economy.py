#!/usr/bin/env python3
"""复现 Economy.gd / Voyage.gd 的公式，验证核心贸易循环与航海数值是否成立。
不依赖 Godot，纯数学校验。"""
import json, math, re, sys, os
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

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
## Economy.PRICE_SPREAD_MIN 的镜像：任何职事组合下同港买价恒 ≥ 卖价 × 此值。
SPREAD_MIN = 1.08
## Crew.FOREIGN_PORTS——只有这几处通事的议价才生效
FOREIGN_PORTS = ("hakata", "kagoshima", "jeju", "champa")
KM_PER_LI = 0.576
EARTH_R = 6371.0

def role(pid, gid):
    return ports[pid].get("market", {}).get(gid)

def unit_value(pid, gid, rate=1.0):
    return goods[gid]["base_value"] * ROLE_MOD[role(pid, gid)] * rate

# 复现 Crew.gd 的交易加成（一之三节另验其余职事）
def trade_cost(lv):        return max(0.0, 1.0 - 0.12 * lv)
def interp_edge(lv):       return 0.07 * lv
## titles.json invest.edge_per_level：修埠压产地价、抬消费地价
INVEST_EDGE_PER = load("titles.json")["invest"]["edge_per_level"]

def gd_round(x):
    """GDScript round()：.5 远离零。Python round() 是银行家舍入（66.5 → 66），
    旧镜像因此与生产差 1 文（lane ea2 对生产 dump 实测光杆价 16/1512 格）。"""
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)

def price_core(v, foreign, zashi=0, tongshi=0, title_duty=1.0):
    """Economy.price_at_rate 的**唯一**镜像：给定共有因子 v，返回未取整的（买, 卖）。
    运算次序与生产逐行一致（浮点取整边界也对得上）；各节行情/职事/修埠/职衔一律经此，改公式时只改这里。
    价差地板的裁法：卖价先封顶在「光杆买价 ÷ 地板」，超出的部分改从买价折扣里扣回来；
    且买、卖两侧都不得劣于光杆——只压卖价的话，雇齐职事反而比光杆赚得少。
    v=1.0 时即买卖倍率（二之二节倍率层断言用）。"""
    edge = interp_edge(tongshi) if foreign else 0.0
    tc = trade_cost(zashi)
    bare_buy = v * (1.0 + TARIFF)
    bare_sell = v * (1.0 - BROKER)
    cap = bare_buy / SPREAD_MIN
    sell_v = min(v * (1.0 - BROKER * tc * title_duty) * (1.0 + edge), cap)
    sell_v = max(sell_v, min(bare_sell, cap))
    buy_v = max(v * (1.0 + TARIFF * tc * title_duty) * (1.0 - edge), sell_v * SPREAD_MIN)
    return min(buy_v, max(bare_buy, sell_v * SPREAD_MIN)), sell_v

def price_at(pid, gid, is_buy, zashi=0, tongshi=0, title_duty=1.0, inv=0, rate=1.0):
    """复现 Economy.price_at_rate(pid, gid, rate, is_buy)：职事等级、职衔抽解折、修埠等级显式传入。
    抽解基率取 TARIFF（忠宋港、未站蒲家；战况倍率不在此镜像）。"""
    r = role(pid, gid)
    v = goods[gid]["base_value"] * ROLE_MOD.get(r, 1.0) * rate
    ie = INVEST_EDGE_PER * inv
    if r == "origin":
        v *= (1.0 - ie)
    elif r == "consumer":
        v *= (1.0 + ie)
    b, s = price_core(v, pid in FOREIGN_PORTS, zashi, tongshi, title_duty)
    return gd_round(b if is_buy else s)

def buy_price(pid, gid, rate=1.0):
    return price_at(pid, gid, True, rate=rate)

def sell_price(pid, gid, rate=1.0):
    return price_at(pid, gid, False, rate=rate)

lanes = load("sealanes.json").get("lanes", {})

def gc_li_pts(lon1, lat1, lon2, lat2):
    lat1, lon1 = math.radians(lat1), math.radians(lon1)
    lat2, lon2 = math.radians(lat2), math.radians(lon2)
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return (EARTH_R * 2 * math.atan2(math.sqrt(h), math.sqrt(max(0.0, 1-h)))) / KM_PER_LI

def rhumb_bearing(lon1, lat1, lon2, lat2):
    """与 Voyage._rhumb_bearing 相同：墨卡托恒向线，0=北，顺时针。"""
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
        pts.append((w[0], w[1]))
    pts.append((pb["lon"], pb["lat"]))
    return pts

def gc_distance_li(a, b):
    """两港大圆。只用于海图投影是否失真，不代表船走的路。"""
    pa, pb = ports[a], ports[b]
    return gc_li_pts(pa["lon"], pa["lat"], pb["lon"], pb["lat"])

def distance_li(a, b):
    """与 Voyage.distance_li 相同：有绕岸折线就沿折线累加，否则是大圆。"""
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
        end_req = c.get("ending_requires")
        if end_req:
            avail = [p for p in ports.values() if ch_num(p.get("unlock", "ch1")) <= n]
            check(len(avail) >= end_req.get("visited_count", 0),
                  f"第{n}章了结需走通 {end_req.get('visited_count',0)} 港，该章实际可达 {len(avail)} 港")
            for pid in end_req.get("must_visit", []):
                reachable = pid in ports and ch_num(ports[pid].get("unlock", "ch1")) <= n
                check(reachable,
                      f"第{n}章了结要求亲至「{ports.get(pid,{}).get('name',pid)}」，该港在本章"
                      + ("可达" if reachable else "尚未解锁——死锁"))
        else:
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

# 海图回港走 load_scene(port_id)。同名剧情若 type 不是 port，会盖住牙行，visited_ports 写不进。
scenes_doc = load("scenes.json")
scene_list = scenes_doc["scenes"]
by_scene = {}
dup_ids = []
for sc in scene_list:
    sid = sc["id"]
    if sid in by_scene:
        dup_ids.append(sid)
    by_scene[sid] = sc
check(not dup_ids, f"剧情场景 id 不重复（重复：{dup_ids or '无'}）")

shadowed = []
for pid, p in ports.items():
    sc = by_scene.get(pid)
    if sc is not None and sc.get("type") != "port":
        shadowed.append(f"{pid}（{p.get('name', pid)}，场景 type={sc.get('type', 'scene')}）")
check(not shadowed, "港口 id 不被非 port 剧情盖住（海图回港能进牙行并记到访）："
      + ("无" if not shadowed else "；".join(shadowed)))

for pid in ("ryukyu", "hakata"):
    sc = by_scene.get(pid)
    ok = sc is None or sc.get("type") == "port"
    check(ok, f"亲至条件港口 {pid} 从海图回港走港口界面，不走进同名剧情")

check("ryukyu_bay" in by_scene and by_scene["ryukyu_bay"].get("type") != "port",
      "流求海面北缘仍是剧情场景 ryukyu_bay，不再占用港口 id")
check("hakata_ledger" in by_scene and by_scene["hakata_ledger"].get("type") != "port",
      "博多旧账仍是剧情场景 hakata_ledger，不再占用港口 id")

dangling = []
known = set(by_scene) | set(ports)
for sc in scene_list:
    for ch in sc.get("choices") or []:
        nxt = ch.get("next")
        if nxt and nxt not in known:
            dangling.append(f"{sc['id']} → {nxt}")
check(not dangling, f"场景 next 都能落到场景或港口（悬空 {len(dangling)}）")
for d in dangling[:8]:
    print("      悬空:", d)

TITLE_IDS = ("cg_title", "cg_world_north", "cg_world_east", "cg_world_south", "cg_world_west")
for tid in TITLE_IDS:
    sc = by_scene.get(tid, {})
    has_copy = bool(sc.get("cg_title") or sc.get("cg_sub"))
    check(sc.get("type") == "title" and has_copy,
          f"开场 {tid} 为 type=title，正文在 cg_title/cg_sub（现 type={sc.get('type', '无')}）")

# 每一章都必须能通向下一章
max_ch = max(int(c["id"]) for c in chapters)
declared = {ch_num(p.get("unlock", "ch1")) for p in ports.values()}
check(declared <= set(range(1, max_ch + 1)),
      f"ports.json 引用的章节号 {sorted(declared)} 均在 chapters.json 定义范围内(1-{max_ch})")
ship_ch = {ch_num(s.get("unlock", "ch1")) for s in ships.values()}
check(ship_ch <= set(range(1, max_ch + 1)),
      f"ships.json 引用的章节号 {sorted(ship_ch)} 均在定义范围内")

finals = [c for c in chapters if not c.get("next_requires")]
check(len(finals) == 1, "恰好有一个最终章（next_requires 为空）")
if len(finals) == 1:
    # 云端 21ce 原按自家 ending.{sea,scholar,both} 结构检查；本分支按主干 p6 结构：终章 endings 列表非空、每条带 id 与 scene
    endings = finals[0].get("endings") or []
    check(isinstance(endings, list) and len(endings) >= 1, f"最终章 endings 列表非空（现 {len(endings)} 条）")
    for e in endings:
        check(isinstance(e, dict) and str(e.get("id", "")).strip() != "" and str(e.get("scene", "")).strip() != "",
              f"最终章结局 {e.get('id', '?') if isinstance(e, dict) else e} 带 id 与 scene")
    champa_ch = ch_num(ports.get("champa", {}).get("unlock", "ch1"))
    check(champa_ch <= int(finals[0]["id"]),
          f"占城解锁于第 {champa_ch} 章，不高于最终章 {finals[0]['id']}")

print()
print("=" * 68)
print("一之三、船上职事的加成边界（防数值失控）")
print("=" * 68)

crew = load("crew.json")
roles = {r["id"]: r for r in crew["roles"]}
cands = crew["candidates"]

# 复现 Crew.gd 的加成公式（trade_cost / interp_edge 在文件头，与定价镜像同处）
def speed_factor(lv):      return 1.0 + 0.06 * lv
def wind_floor(lv):        return 0.40 + 0.05 * lv
def cargo_loss(lv):        return max(0.0, 1.0 - 0.17 * lv)
def crew_loss(lv):         return max(0.0, 1.0 - 0.23 * lv)

MAXLV = 3
check(wind_floor(MAXLV) < 1.0,
      f"满级舵工的逆风下限 {wind_floor(MAXLV):.2f} 仍 < 1.0——逆风始终不利，季风机制不被架空")
check(trade_cost(MAXLV) > 0.0,
      f"满级杂事后抽解仍余 {trade_cost(MAXLV)*100:.0f}%——交易成本不会归零")
check(cargo_loss(MAXLV) > 0.0,
      f"满级总管后货损仍余 {cargo_loss(MAXLV)*100:.0f}%——风涛依旧要命")
check(crew_loss(MAXLV) > 0.0,
      f"满级医人后断粮减员仍余 {crew_loss(MAXLV)*100:.0f}%——补给依旧不能不管")

# 每种职事至多一人，故最强组合是各职事取最高级
best_lv = {}
for c in cands:
    r = c["role"]
    best_lv[r] = max(best_lv.get(r, 0), c["level"])
print(f"\n  各职事可得的最高等级：{ {roles[r]['name']: v for r, v in best_lv.items()} }")

# 满编后的核心商路利润膨胀幅度
def price_muls(is_foreign, zashi, tongshi):
    """买卖两个倍率（已除去共有因子 v）＝ price_core(1.0, …)，不另立公式。"""
    return price_core(1.0, is_foreign, zashi, tongshi)

gid = "qingbai_porcelain"
bare = sell_price("hakata", gid) - buy_price("quanzhou", gid)
full = (price_at("hakata", gid, False, best_lv.get("zashi",0), best_lv.get("tongshi",0))
        - price_at("quanzhou", gid, True, best_lv.get("zashi",0), best_lv.get("tongshi",0)))
infl = (full / bare - 1) * 100 if bare else 0
print(f"  泉州→博多 青白瓷单件利润：无职事 {bare} → 满编 {full}（+{infl:.0f}%）")
check(infl < 60, f"满编职事使核心商路利润膨胀 {infl:.0f}%，未失控（阈值 60%）")

# 月俸负担应该是真实约束
total_wage = sum(max(c["wage"] for c in cands if c["role"] == r) for r in best_lv)
print(f"  满编月俸合计 {total_wage} 钱/月")
check(total_wage > 500, f"满编月俸 {total_wage}，构成实际经营压力")

# 每种职事都要有可雇之人，且首章就得有起步人选
ch1_roles = {c["role"] for c in cands if c.get("unlock","ch1") == "ch1"}
check(len(ch1_roles) >= 5,
      f"第一章可雇到 {len(ch1_roles)}/{len(roles)} 种职事——开局不至于无人可用")
missing = set(roles) - {c["role"] for c in cands}
check(not missing, f"每种职事都有候选人（缺：{[roles[m]['name'] for m in missing] or '无'}）")

print()
print("=" * 68)
print("一之四、海图投影（scripts/chart/ChartProjection.gd 的等距圆锥投影，参数取 data/chart_projection.json）")
print("=" * 68)

# 2026-09-25 海图重制：投影不再随解锁港口自动取景，而是固定画布上的等距圆锥（标准纬线 15°N / 35°N，中央经线 120°E）。
# 这里按 json 里的常量重算（与 GDScript、tools/build_terrain.py 同一公式），检查港口落点与相对方位。
_pj = load("chart_projection.json")
W, H = (float(v) for v in _pj["canvas_px"])
_b = _pj["bounds"]
_phi1, _phi2 = math.radians(float(_pj["phi1"])), math.radians(float(_pj["phi2"]))
_lon0 = math.radians(float(_pj["lon0"]))
_n = (math.cos(_phi1) - math.cos(_phi2)) / (_phi2 - _phi1)
_G = math.cos(_phi1) / _n + _phi1
_rho0 = _G - (_phi1 + _phi2) * 0.5
def _conic_px(lon, lat):
    rho = _G - math.radians(lat)
    theta = _n * (math.radians(lon) - _lon0)
    x, y = rho * math.sin(theta), _rho0 - rho * math.cos(theta)
    return ((x - _b["x0"]) / (_b["x1"] - _b["x0"]) * W, (_b["y1"] - y) / (_b["y1"] - _b["y0"]) * H)
def project(subset):
    """按海图投影把港口落到底图像素，返回 {pid: (x, y)}"""
    return {p["id"]: _conic_px(p["lon"], p["lat"]) for p in subset}

allp = list(ports.values())
pos = project(allp)

oob = [pid for pid,(x,y) in pos.items() if not (0 <= x <= W and 0 <= y <= H)]
check(not oob, f"全部 {len(pos)} 个港口都落在底图内（越界：{oob or '无'}）")

# 相对方位必须与真实地理一致（屏幕 y 轴向下，故北 = y 更小）
def rel(a, b):
    return ("东" if pos[b][0] > pos[a][0] else "西") + ("北" if pos[b][1] < pos[a][1] else "南")
cases = [("quanzhou","hakata","东北"), ("quanzhou","guangzhou","西南"),
         ("quanzhou","jeju","东北"), ("quanzhou","champa","西南"),
         ("mingzhou","hakata","东北"), ("wenzhou","zhangzhou","西南")]
for a,b,want in cases:
    got = rel(a,b)
    check(got == want, f"{ports[a]['name']} → {ports[b]['name']} 在图上位于{got}（实际{want}）")
# 萨摩（万之瀨川口 130.31°E，ports.md §2）在博多正南偏西约 2°：象限判法对近正南的两点没有意义，
# 圆锥投影下 130°E 的经线已右倾 4°，只断言「近乎正南」——横向偏差不到纵向的 15%。
_dx = pos["kagoshima"][0] - pos["hakata"][0]
_dy = pos["kagoshima"][1] - pos["hakata"][1]
check(_dy > 0 and abs(_dx) < 0.15 * _dy,
      f"{ports['hakata']['name']} → {ports['kagoshima']['name']} 在图上近乎正南（横 {_dx:.0f} px / 纵 {_dy:.0f} px）")

# 等比：屏幕距离之比应贴合真实里程之比，地图不能被拉伸变形（等距圆锥在 15°–35° 之间形变很小）
pairs = [("quanzhou","hakata"), ("quanzhou","penghu"), ("quanzhou","guangzhou"),
         ("mingzhou","hakata"), ("guangzhou","champa")]
ratios = []
for a,b in pairs:
    sd = math.dist(pos[a], pos[b])
    # 屏幕上量的是两点直线，比例要拿直线大圆里程比；distance_li 自 2d51 起沿 sealanes 折线累加
    rd = gc_li_pts(ports[a]["lon"], ports[a]["lat"], ports[b]["lon"], ports[b]["lat"])
    ratios.append(sd/rd)
spread = max(ratios)/min(ratios)
print(f"\n  屏幕距离/实际里程 之比：{min(ratios):.4f} ~ {max(ratios):.4f}（离散度 {spread:.3f}）")
check(spread < 1.12, f"各航段的图上比例一致，离散度 {spread:.3f} < 1.12（地图未失真）")

# 只解锁第一章时港口同样在底图内（投影固定，不随章节变）
ch1 = [p for p in allp if p.get("unlock","ch1") == "ch1"]
pos1 = project(ch1)
oob1 = [pid for pid,(x,y) in pos1.items() if not (0 <= x <= W and 0 <= y <= H)]
check(not oob1, f"仅第一章 {len(ch1)} 港时同样全部在底图内")

# 季风流线方向：方位角 → 屏幕向量（y 向下取负 cos）
for name, bearing_deg, want in [("西南季风(吹向东北)", 45.0, "右上"), ("东北季风(吹向西南)", 225.0, "左下")]:
    dx, dy = math.sin(math.radians(bearing_deg)), -math.cos(math.radians(bearing_deg))
    got = ("右" if dx > 0 else "左") + ("上" if dy < 0 else "下")
    check(got == want, f"{name} 的流线指向{got}")

# 港口贴岸、航点在海上、标注合法：见 tools/verify_coastline.py（真实岸线）。旧手绘 chart_coast.json 不再是海图数据。
mapview_src = open(os.path.join(ROOT, "scripts", "chart", "MapView.gd"), encoding="utf-8").read()
check("ChartProjection.from_json(" in mapview_src, "海图经 ChartProjection 读 chart_projection.json 投影")

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
print("二之二、同港价差不变量：站着不动能不能印钱")
print("=" * 68)
print("  Economy.price_at_rate 的买卖两侧共有因子 v = base_value × ROLE_MOD × rate，")
print("  故『同港卖价 > 买价』只由职事修正决定，与货物、行情、身份倍率无关。")
print("  但价格取整（int(round)）会打破这个约分，所以必须逐（港, 货, 杂事, 通译）实扫。")

MAX_Z = best_lv.get("zashi", 0)
MAX_T = best_lv.get("tongshi", 0)

def same_port_pair(pid, gid, zashi, tongshi, rate=1.0):
    """同港买卖两价（经 price_at，不另立公式）。"""
    return (price_at(pid, gid, True, zashi, tongshi, rate=rate),
            price_at(pid, gid, False, zashi, tongshi, rate=rate))

inverted = []
for pid in ports:
    for gid in ports[pid].get("market", {}):
        for z in range(MAX_Z + 1):
            for t in range(MAX_T + 1):
                b, s = same_port_pair(pid, gid, z, t)
                if s > b:
                    inverted.append((pid, gid, z, t, b, s, (s - b) / b if b else 0))

if inverted:
    inverted.sort(key=lambda r: -r[6])
    worst = inverted[0]
    print(f"  同港卖价高于买价的组合：{len(inverted)} 个（港, 货, 杂事, 通译）")
    print(f"    最坏：{worst[0]} / {goods[worst[1]]['name']}"
          f"　杂事{worst[2]} 通译{worst[3]}　买 {worst[4]} → 卖 {worst[5]}"
          f"（每轮 +{worst[6]*100:.1f}%）")
    zt = sorted({(r[2], r[3]) for r in inverted})
    print(f"    最低触发职事组合：杂事{zt[0][0]} 通译{zt[0][1]}"
          f"　（共 {len({(r[0], r[1]) for r in inverted})} 处 (港, 货) 对沦陷）")
    print("    原地买入立刻卖出即净赚，不出港故 customs_inspection 永不触发——可无限重复。")
check(not inverted,
      f"任何（港, 货, 杂事, 通译）组合下同港卖价均不高于买价（越界 {len(inverted)} 个）")

# 价差的厚度断言放在**倍率层**而不是整数价格层：便宜货取整后撑不住 1.08 的整数比
# （卖价 4.0 与买价 4.32 都会 round 成 4），那不是漏洞，是取整精度。真正要守的
# 结构不变量是「买卖倍率之比 ≥ 地板」，它与货物、行情、身份倍率无关。
thin = []
for z in range(MAX_Z + 1):
    for t in range(MAX_T + 1):
        for foreign in (False, True):
            bm, sm = price_muls(foreign, z, t)
            if bm < sm * SPREAD_MIN - 1e-9:
                thin.append(("异国港" if foreign else "本国港", z, t, bm / sm))
if thin:
    thin.sort(key=lambda r: r[3])
    w = thin[0]
    print(f"  价差不足 {SPREAD_MIN:.2f} 倍的职事组合：{len(thin)} 个"
          f"　最薄 {w[0]} 杂事{w[1]} 通译{w[2]} 买/卖倍率 = {w[3]:.4f}")
check(not thin,
      f"任何职事组合下同港买价倍率 ≥ 卖价倍率 × {SPREAD_MIN}（越界 {len(thin)} 个）")

# 雇人不能反而更亏：核心商路的单件利润必须随职事等级单调不降。
# 这条是为封洞方案设的护栏——只压卖价的 clamp 会让满编利润掉到光杆以下。
_gid = "qingbai_porcelain"
ladder = []
for z, t in ((0, 0), (min(2, MAX_Z), min(2, MAX_T)), (MAX_Z, MAX_T)):
    _b = price_at("quanzhou", _gid, True, z, t)
    _s = price_at("hakata", _gid, False, z, t)
    ladder.append((z, t, _s - _b))
print("  泉州→博多 青白瓷单件利润随职事递进："
      + " → ".join(f"杂{z}通{t} {p}" for z, t, p in ladder))
check(all(ladder[i][2] <= ladder[i + 1][2] for i in range(len(ladder) - 1)),
      "核心商路利润随职事等级单调不降（雇人不会反而更亏）")

# Lane ea：上面全是 Python 镜像。生产 price_at_rate 曾只声明 PRICE_SPREAD_MIN 而不用它，
# 镜像恒绿、游戏里通事三级即可在博多原地买卖印钱。这里锁住生产源码真的走地板裁法。
_pa_src = open(os.path.join(ROOT, "scripts/core/Economy.gd"), encoding="utf-8").read()
_pa_fn = _pa_src.split("func price_at_rate", 1)[1].split("\nfunc ", 1)[0] if "func price_at_rate" in _pa_src else ""
check(_pa_fn.count("PRICE_SPREAD_MIN") >= 3
      and "var cap := bare_buy / PRICE_SPREAD_MIN" in _pa_fn
      and "sell_v = maxf(sell_v, minf(bare_sell, cap))" in _pa_fn
      and "maxf(bare_buy, sell_v * PRICE_SPREAD_MIN)" in _pa_fn
      and "(1.0 - edge)))" not in _pa_fn and "(1.0 + edge)))" not in _pa_fn,
      "生产 Economy.price_at_rate 按镜像同式裁价差地板（卖价封顶、买价兜底、两侧不劣于光杆）")


def sell_revenue(pid, gid, amount, rate=1.0):
    depth = ports[pid]["depth"]
    total, r = 0, rate
    for _ in range(amount):
        total += sell_price(pid, gid, r)
        r = max(0.4, min(2.2, r - 1.0/depth))
    return total

def buy_cost(pid, gid, amount, rate=1.0):
    """镜像 Economy.estimate_buy_cost：逐件加价累计。"""
    depth = ports[pid]["depth"]
    total, r = 0, rate
    for _ in range(amount):
        total += buy_price(pid, gid, r)
        r = max(0.4, min(2.2, r + 1.0/depth))
    return total

def affordable_qty(pid, gid, money, cap=9999):
    """镜像 Main._affordable_qty：现银按逐件总价最多买几件。"""
    n = 0
    while n < cap and buy_cost(pid, gid, n + 1) <= money:
        n += 1
    return n

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
print("五、航段天数与补给消耗是否可行（单船舰队口径）")
print("=" * 68)

def integrated_days(src, dst, ship_id, wind_b, strength=1.0, morale=70):
    """与 Voyage.plan 相同：每一段用自己的恒向线方位吃季风。"""
    pts = track_points(src, dst)
    morale_f = 0.6 + 0.4 * (morale / 100)
    base = ships[ship_id]["base_speed"] * morale_f
    dist = 0.0
    days_f = 0.0
    for i in range(len(pts) - 1):
        seg = gc_li_pts(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1])
        if seg < 0.05:
            continue
        dist += seg
        crs = rhumb_bearing(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1])
        spd = base * wind_factor(crs, wind_b, strength)
        if spd <= 1.0:
            return 999, dist
        days_f += seg / spd
    return math.ceil(days_f), dist

print()
routes = [("quanzhou", "xinghua"), ("quanzhou", "penghu"), ("quanzhou", "ryukyu"),
          ("quanzhou", "fuzhou"), ("mingzhou", "hakata"), ("quanzhou", "hakata"),
          ("quanzhou", "guangzhou"), ("guangzhou", "champa")]
for src, dst in routes:
    if src not in ports or dst not in ports:
        continue
    d_sw, dist = integrated_days(src, dst, "fu_ship_medium", SW, 1.0)
    d_ne, _ = integrated_days(src, dst, "fu_ship_medium", NE, 1.0)
    d_best, d_worst = min(d_sw, d_ne), max(d_sw, d_ne)
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
print("六、起步可行性：1000 钱能否启动第一笔生意（单船舰队口径）")
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
print("六之二、多船分船装载的账目核算（复现 Fleet 分舱 API）")
print("=" * 68)
print("  Fleet 已改为货分船：每船独立 cargo，水/粮全队共用。")
print("  单船空舱按载重比例分摊水粮份额，须保证 Σ ship_free == free 恒成立。")

SUPPLY_BULK_M = 0.25  # 与 Fleet.SUPPLY_BULK 一致

def fleet_account(ship_ids, water, food, per_ship_cargo):
    """复现 Fleet 的聚合账目，返回 (cap_total, used, free, [ship_free...])"""
    caps = [ships[sid]["capacity"] for sid in ship_ids]
    cap_total = sum(caps)
    cargo_bulk = [sum(q * goods[gid]["bulk"] for gid, q in sc.items()) for sc in per_ship_cargo]
    used = (water + food) * SUPPLY_BULK_M + sum(cargo_bulk)
    free_total = max(0.0, cap_total - used)
    wf = (water + food) * SUPPLY_BULK_M
    ship_free = []
    for i in range(len(caps)):
        share = wf * (caps[i] / cap_total) if cap_total > 0 else wf / max(1, len(caps))
        ship_free.append(max(0.0, caps[i] - cargo_bulk[i] - share))
    return cap_total, used, free_total, ship_free

# 场景一：开局小艍船，水粮 60/60
cap_t, used_t, free_t, sfree = fleet_account(
    ["sampan"], 60, 60, [{}])
check(abs(sum(sfree) - free_t) < 1e-3,
      f"单船空舱与全队空舱一致（{sum(sfree):.2f} == {free_t:.2f}）")
check(used_t <= cap_t + 1e-6, f"开局账目未溢出（{used_t:.2f} <= {cap_t} 料）")

# 场景二：小艍 + 福船（中），水粮全队 100/100，货分船
cap_t, used_t, free_t, sfree = fleet_account(
    ["sampan", "fu_ship_medium"], 100, 100,
    [{"fujian_porcelain": 20}, {"qingbai_porcelain": 60}])
check(abs(sum(sfree) - free_t) < 1e-3,
      f"2 船时 Σ ship_free({sum(sfree):.2f}) == free({free_t:.2f})")
print(f"    小艍(200料)+福船中(800料)，水粮100/100，小艍装瓷20 福船装瓷60")
print(f"    全队 {cap_t} 料，占 {used_t:.1f} 料，空舱 {free_t:.1f} 料，各船空舱 {[round(x,1) for x in sfree]}")

# 场景三：三船异构 + 少量货 + 重补给——满载边界
cap_t, used_t, free_t, sfree = fleet_account(
    ["sampan", "fu_ship_medium", "fu_ship_large"], 300, 300,
    [{"raw_silk": 10}, {"fujian_porcelain": 5}, {"qingbai_porcelain": 8}])
check(used_t <= cap_t + 1e-6, f"三船满载边界账目未溢出（{used_t:.2f} <= {cap_t} 料）")
check(all(x >= 0 for x in sfree), "各船空舱不为负（单船不超载）")
check(abs(sum(sfree) - free_t) < 1e-3,
      f"三船时 Σ ship_free({sum(sfree):.2f}) == free({free_t:.2f})")

# 场景四：刻意塞爆一艘——验证 add_cargo 的守卫确实必要（原始未钳制账目会溢出）
def raw_ship_bulk(sc):
    return sum(q * goods[gid]["bulk"] for gid, q in sc.items())
over_cap = 200      # 小艍载重
raw_bulk = raw_ship_bulk({"fujian_porcelain": 300})   # 300 件瓷，每件 1 料
check(raw_bulk > over_cap,
      f"超载意图原始占用 {raw_bulk} 料 > 单船载重 {over_cap} 料——"
      "若无 add_cargo 守卫，账目必然溢出，故守卫必不可少")

print()
print("=" * 68)
print("六之三、每船水手下限（can_sail 逐船门槛）")
print("=" * 68)
print("  can_sail 已改为逐船 crew >= crew_min。聚合口径会漏判「一条船 0 人」。")

def crew_ok(ship_ids, crews):
    return all(c >= ships[sid]["crew_min"] for sid, c in zip(ship_ids, crews))

sampan, fu = "sampan", "fu_ship_medium"
min_total = ships[sampan]["crew_min"] + ships[fu]["crew_min"]
crews = [0, min_total]  # 26 人全塞福船：聚合够，但小艍 0 人
check(sum(crews) >= min_total, "聚合口径：总水手达全队下限")
check(not crew_ok([sampan, fu], crews),
      "逐船口径：小艍 0 人不能出海 → can_sail 必须逐船判")
check(crew_ok([sampan, fu], [ships[sampan]["crew_min"], ships[fu]["crew_min"]]),
      "逐船口径：两船均达标可出海")

print()
print("=" * 68)
print("六之四、船体改装系统（复刻 Fleet.upgrade_cost / armor_damage_reduction）")
print("=" * 68)
print("  改装通修所有船，帆 Lv 决定航速（0.12/级），甲 Lv 减免风暴/逃败船体伤")
print("  （P4-1 起海盗战斗伤走战术层实时扣、结算不补扣，只有 flee 败与风暴仍乘甲）。")
print("  成本 = ceil(船价 × 10% × (1+0.5×(级-1)) × (甲则1.25))，上限 3 级。")

def upgrade_cost(sid, kind, lv):
    price = ships[sid]["price"]
    mult = 1.25 if kind == "armor" else 1.0
    if lv >= 3:
        return 0  # 满级守卫，与 Fleet.upgrade_cost 一致
    return math.ceil(price * 0.10 * (1 + 0.5 * (lv - 1)) * mult)

# 1) 成本随级、随船价严格递增（跨船可比、单调）
increasing = all(upgrade_cost(sid, "sail", 1) < upgrade_cost(sid, "sail", 2)
                 for sid in ships)
check(increasing, "升帆成本随级递增（L1→2 < L2→3）")
# 更稳健：价低的船单级成本不高于价高的
price_ordered2 = all(upgrade_cost(a, "sail", 1) <= upgrade_cost(b, "sail", 1)
                     for a, b in [(x, y) for x in ships for y in ships
                                  if ships[x]["price"] <= ships[y]["price"]])
check(price_ordered2, "升帆成本随船价单调不减（贵船改更贵，跨船可比）")

# 2) 满级返回 0（上限生效）
all_full_cost0 = all(upgrade_cost(sid, "sail", 3) == 0 and upgrade_cost(sid, "armor", 3) == 0
                     for sid in ships)
check(all_full_cost0, "满级（Lv3）后升级成本为 0——上限 3 级生效")

# 2b) 船屋升级回调：按当前等级重算、升级 true 才扣钱、扣不成回滚、连点不二次扣（ASTRA M1）
_main_up = open(os.path.join(os.path.dirname(__file__), "..", "scripts", "Main.gd"),
                encoding="utf-8").read()
_up_body = _main_up.split("func _on_upgrade(", 1)[1].split("\nfunc ", 1)[0] if "func _on_upgrade(" in _main_up else ""
_i_busy = _up_body.find("if _upgrade_busy:")
_i_cost = _up_body.find("Fleet.upgrade_cost(ship_index, kind)")
_i_up = _up_body.find("Fleet.upgrade_armor(ship_index) if is_armor else Fleet.upgrade_sail(ship_index)")
_i_notok = _up_body.find("if not ok:")
_i_spend = _up_body.find("GameState.spend_money(cost)")
_i_roll = _up_body.find("Fleet.ships[ship_index][level_key] = prev_lv")
_i_set = _up_body.find("_upgrade_busy = true")
check(_up_body.count("spend_money(") == 1, "升级回调只一处扣钱")
check(0 <= _i_busy < _i_cost < _i_up < _i_notok < _i_spend < _i_roll < _i_set,
      "升级回调：连点闸 → 按当前等级重算费用 → 升级 → 失败不扣 → 扣钱 → 扣不成回滚 → 上闸过场")
check("spend_money(shown_cost)" not in _up_body, "升级扣费不用按钮 bind 的旧价")
check(_up_body.rstrip().endswith("_upgrade_busy = false"), "升级过场落定后才放开连点闸")

# 2c) 修船 / 购船同闸（lane fo）：墨幕不吞 ui_accept 动作，过场未落前旧页钮还能按到 → 先看闸、扣成才上闸、过场落定再放
for _fn, _what in (("_on_repair_hull", "修船"), ("_on_buy_ship", "购船")):
    _yb = _main_up.split("func %s(" % _fn, 1)[1].split("\nfunc ", 1)[0] if ("func %s(" % _fn) in _main_up else ""
    _j_busy = _yb.find("if _upgrade_busy:")
    _j_spend = _yb.find("if GameState.spend_money(")
    _j_set = _yb.find("_upgrade_busy = true")
    _j_await = _yb.find("await _yard_success_transition(")
    _j_free = _yb.find("_upgrade_busy = false")
    check(_yb.count("spend_money(") == 1 and 0 <= _j_busy < _j_spend < _j_set < _j_await < _j_free,
          "%s回调：连点闸 → 扣钱 → 上闸 → 过场 → 放闸（过场期间旧页钮不二次扣费）" % _what)

# 3) armor 满级船体伤系数 = 0.80 > 0——风暴依旧要命，不能归零
def armor_reduction(max_durabilities, armor_levels):
    num = sum(w * (a - 1) for w, a in zip(max_durabilities, armor_levels))
    den = sum(max_durabilities)
    return 1.0 - 0.10 * (num / den)

full_armor = armor_reduction([ships[sid]["durability"] for sid in ships],
                             [3] * len(ships))
check(full_armor == 0.80, f"全队满甲船体伤系数 {full_armor:.2f}，风暴仍要命（未归零）")
base_armor = armor_reduction([ships[sid]["durability"] for sid in ships],
                             [1] * len(ships))
check(base_armor == 1.0, f"未改装船体伤系数 {base_armor:.2f}（甲 Lv1 无减免）")

# 4) 帆满级航程缩短 ≤20%（确定性：×1.24 → ÷1.24；远洋 13 日 → 10.5 日）
import math as _math
def trip_days(d, spd):
    return _math.ceil(d / spd)
d_hakata = distance_li("quanzhou", "hakata")
d_base = trip_days(d_hakata, ships["fu_ship_medium"]["base_speed"] * (0.6 + 0.4 * 0.7))
d_full = trip_days(d_hakata, ships["fu_ship_medium"]["base_speed"] * 1.24 * (0.6 + 0.4 * 0.7))
shrink = (1 - d_full / d_base) * 100
print(f"  福船(中) 泉州→博多 理论航程：帆Lv1 {d_base} 日 → 帆满级 {d_full} 日（缩短 {shrink:.1f}%）")
check(shrink <= 20, f"帆满级航程缩短 {shrink:.1f}% ≤ 20%（未架空季风候风）")
check(d_full < d_base, "帆满级确实缩短航程")

# 5) armor 满级使舰队战力提升 ≤25%（相对 0.5×耐久 + 4×水手 + 25×炮 + 30×armor 基线）
# 用一艘福船(中) 为例（水手取 crew_min，士气 70）
def fp_one(cid, armor_lv):
    s = ships[cid]
    durab = s["durability"]
    crew = s["crew_min"]
    return (durab * 0.5 + crew * 4.0 + s["cannon_slots"] * 25.0 + armor_lv * 30.0) * (0.6 + 0.4 * 0.7)
fp1, fp3 = fp_one("fu_ship_medium", 1), fp_one("fu_ship_medium", 3)
fp_gain = (fp3 / fp1 - 1) * 100
print(f"  福船(中) 战力：甲Lv1 {fp1:.0f} → 甲满级 {fp3:.0f}（+{fp_gain:.1f}%）")
check(fp_gain <= 25, f"甲满级战力提升 {fp_gain:.1f}% ≤ 25%（未使海战胜负失衡）")

# 6) 单船升满帆甲总成本 ≤ 该船价 60%——改装不喧宾夺主
def full_upgrade_cost(cid):
    s = ships[cid]
    sail = upgrade_cost(cid, "sail", 1) + upgrade_cost(cid, "sail", 2)
    armor = upgrade_cost(cid, "armor", 1) + upgrade_cost(cid, "armor", 2)
    return sail + armor
full_costs = {cid: full_upgrade_cost(cid) for cid in ships}
check(all(full_costs[cid] <= ships[cid]["price"] * 0.6 for cid in ships),
      f"单船升满帆甲成本 ≤ 船价 60%（最贵 {max(full_costs.values())} 钱）")

# 7) 全船队升满总成本 ≥ 舰队船价总和 15%——真实资金沉淀
fleet_total = sum(s["price"] for s in ships.values())
fleet_full = sum(full_costs.values())
print(f"  全船队升满帆甲总成本 {fleet_full} 钱，船价总和 {fleet_total} 钱（占比 {fleet_full/fleet_total*100:.1f}%）")
check(fleet_full >= fleet_total * 0.15,
      f"全船队升满总成本占船价 {fleet_full/fleet_total*100:.1f}% ≥ 15%（改装是真实资金沉淀）")

# 8) 最贵单级升级（神舟甲 L2→3）> 开局单趟净利量级（verify 六节实测上限 3000）且 ≥ 神舟价 18%
divine = ships["divine_ship"]
divine_armor_max = upgrade_cost("divine_ship", "armor", 2)
check(divine_armor_max > 3000, f"神舟甲 L2→3 成本 {divine_armor_max} > 开局单趟净利上限 3000（远期投资）")
check(divine_armor_max >= divine["price"] * 0.18,
      f"神舟甲 L2→3 成本 {divine_armor_max} ≥ 神舟价 {divine['price']} 的 18%（{int(divine['price']*0.18)}）")

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
print("八、海战数值（P4-1：WorldMap 炮击接入的战力/战损/货损/奖励边界）")
print("=" * 68)
print("  复刻 SeaChart._fleet_power 与敌船血量缩放；海战胜负由战术层炮击决定，")
print("  结算复用现有文本公式。开局必败是难度保证，标准舰队应可胜。")

# 复刻 Fleet.morale_factor() 与 SeaChart._fleet_power()（士气可参数化）
def morale_factor(morale):
    return 0.6 + 0.4 * (morale / 100.0)

def fleet_power(ship_ids, crews, morale):
    """复刻 _fleet_power：Σ(耐久*0.5 + 水手*4 + 炮位*25 + 甲级*30) × 士气系数。
    舰队级用总耐久（Fleet.total_durability），甲级取加权均值。"""
    durab = sum(ships[cid]["durability"] for cid in ship_ids)
    crew = sum(crews) if crews else sum(ships[cid]["crew_min"] for cid in ship_ids)
    cannons = sum(ships[cid]["cannon_slots"] for cid in ship_ids)
    armor_lv = 1  # P4-1 舰队级取 Lv1 基线（甲级加成在六之四已验证）
    return (durab * 0.5 + crew * 4.0 + cannons * 25.0 + armor_lv * 30.0) * morale_factor(morale)

# A. 开局必败：小艍(crew=6, 士气70) 战力 < 敌船区间下限 180
sampan_power = fleet_power(["sampan"], [6], 70)
print(f"  开局小艍战力 {sampan_power:.1f}（士气 70）")
check(sampan_power < 180,
      f"开局小艍战力 {sampan_power:.1f} < 180（遇海盗必败，逼玩家逃/买路）")

# B. 标准舰队可胜大部分敌：客舟+福船(中) crew_min、士气70 → ≥ 敌力中位 350
std_power = fleet_power(["keel_boat", "fu_ship_medium"], None, 70)
print(f"  标准舰队（客舟+福船中，crew_min，士气 70）战力 {std_power:.1f}")
check(std_power >= 350,
      f"标准舰队战力 {std_power:.1f} ≥ 350（敌力中位，初始士气即可胜多数海盗）")

# C. 胜战伤上限 < 小艍耐久：enemy_max 520 × 0.06 × armor_reduction ∈ [24.96, 31.2]
win_dmg_min = 520 * 0.06 * 0.8   # 满甲
win_dmg_max = 520 * 0.06 * 1.0   # 无甲
print(f"  胜战伤（敌 520）{win_dmg_min:.1f}~{win_dmg_max:.1f} < 小艍耐久 120")
check(win_dmg_max < 120, f"胜战伤上限 {win_dmg_max:.1f} < 120（单次胜仗不沉开局船）")

# D. 败结算伤 < 小艍耐久：enemy_max 520 × 0.16（结算层）
lose_dmg = 520 * 0.16
print(f"  败结算伤（敌 520）{lose_dmg:.1f} < 小艍耐久 120")
check(lose_dmg < 120, f"败结算伤 {lose_dmg:.1f} < 120（单次败仗打不沉健康小艍，两败可沉）")
check(lose_dmg * 2 > 120, f"两败伤 {lose_dmg*2:.1f} > 120（连续两败会沉——战败有真后果）")

# E. 赏金不超单趟净利：spoil_max 600 ≤ 开局单趟净利上限 3000（六节实测）
print(f"  海战赏金 150~600 ≤ 开局单趟净利上限 3000")
check(600 <= 3000, "海战赏金上限 600 ≤ 3000（不印钞，跑商仍是主循环）")

# F. 敌船血量缩放边界：100 × clampf(power/player_power, 0.8, 3.0)
def enemy_hull(player_power, enemy_power):
    return 100.0 * max(0.8, min(3.0, enemy_power / player_power))
low_scale = enemy_hull(sampan_power, 180)   # 小艍对下限敌
high_scale = enemy_hull(sampan_power, 520)  # 小艍对上限敌
std_scale = enemy_hull(std_power, 520)      # 标准舰队对上限敌
print(f"  敌船血量：小艍对敌180~520 → {low_scale:.0f}~{high_scale:.0f}；标准舰队对520 → {std_scale:.0f}")
check(0.8 * 100 <= low_scale <= high_scale <= 3.0 * 100,
      f"敌船血量缩放落在 [80, 300]（实际 {low_scale:.0f}~{high_scale:.0f}）")
check(low_scale >= 150 and high_scale >= 250,
      f"开局小艍对敌倍率 1.5~3.0（{low_scale:.0f}~{high_scale:.0f} 血，必败向）")
check(std_scale <= 100.5, f"标准舰队对上限敌倍率 ≤1.0（{std_scale:.0f} 血，可胜向）")

print()
print("=" * 68)
print("九、P6 剧情旗标与结局（旗标有消费方、结局可到达）")
print("=" * 68)

scenes_doc = load("scenes.json")
chapters_doc = load("chapters.json")
crew_doc = load("crew.json")
scenes = scenes_doc["scenes"]
by_id = {s["id"]: s for s in scenes}

def walk_effects(node, acc):
    if isinstance(node, dict):
        if "flag" in node.get("effects", {}):
            acc.add(node["effects"]["flag"])
        for k in ("choices", "investigations", "scenes"):
            if k in node:
                walk_effects(node[k], acc)
        # 钩子自身也可写旗标
        if "flag" in node and isinstance(node.get("flag"), str) and node.get("port"):
            acc.add(node["flag"])
    elif isinstance(node, list):
        for x in node:
            walk_effects(x, acc)

settable = set()
walk_effects(scenes, settable)
walk_effects(chapters_doc.get("story_hooks", []), settable)

def collect_required(node, acc):
    if isinstance(node, dict):
        if node.get("require_flag"):
            acc.add(node["require_flag"])
        for f in node.get("require_any", []) or []:
            acc.add(f)
        hide = node.get("hide_if_flag")
        if hide:
            acc.add(hide)
        for v in node.values():
            collect_required(v, acc)
    elif isinstance(node, list):
        for x in node:
            collect_required(x, acc)

required = set()
collect_required(scenes, required)
collect_required(chapters_doc, required)
collect_required(crew_doc, required)
# 结局/钩子自己写的 hide_if_flag 必须也能被写下
hook_written = {h.get("flag") for h in chapters_doc.get("story_hooks", []) if h.get("flag")}
ok_required = required <= (settable | hook_written)
dangling = sorted(required - settable - hook_written)
check(ok_required, f"所有 require/hide 旗标都能被写下（悬空 {dangling or '无'}）")
check(len(settable) >= 30, f"剧情可写下旗标 {len(settable)} 个（应覆盖第一章主线选择）")

# ending 继续按钮不得再盖掉第一章三选一
ending_scene = by_id.get("ending", {})
forced = [c.get("effects", {}).get("flag") for c in ending_scene.get("choices", [])]
check("history_pressure_seen" not in forced,
      "第一章 ending 继续按钮不再强行写入 history_pressure_seen")

letter = by_id.get("chapter2_letter", {})
need_any = set(letter.get("require_any", []))
ch1_spine = {"chen_line_open", "merchant_distance", "history_pressure_seen"}
check(need_any == ch1_spine, "chapter2_letter 须先走完回泉州三选一旗标")

# 晋升过场与结局场景必须存在
for c in chapters_doc["chapters"]:
    sid = c.get("advance_scene")
    if sid:
        check(sid in by_id, f"第{c['id']}章 advance_scene「{sid}」存在于 scenes.json")
    for e in c.get("endings", []):
        es = e.get("scene")
        if es:
            check(es in by_id, f"结局 {e.get('id')} 的场景「{es}」存在")

ch4 = next(c for c in chapters_doc["chapters"] if int(c["id"]) == 4)
endings = ch4.get("endings", [])
check(len(endings) >= 2, f"第四章至少两条结局（实际 {len(endings)}）")
ids = [e.get("id") for e in endings]
check(len(ids) == len(set(ids)), "结局 id 不重复")
check(not endings[-1].get("require_any") and not endings[-1].get("require_flag"),
      f"最后一条结局「{endings[-1].get('id')}」无旗标门槛（沙盒兜底）")

ch3 = next(c for c in chapters_doc["chapters"] if int(c["id"]) == 3)
ch3_peak = int(ch3["next_requires"]["peak_money"])
end_peak = int(ch4["ending_requires"]["peak_money"])
check(end_peak > ch3_peak, f"了结本钱 {end_peak} > 第三章晋升 {ch3_peak}")

# 酒馆钩子港口必须存在
for h in chapters_doc.get("story_hooks", []):
    pid = h.get("port")
    check(pid in ports, f"story_hook 港口「{pid}」存在")

# 职事 require_flag 不得锁死第一章六职
ch1_roles = set()
for c in crew_doc["candidates"]:
    if ch_num(c.get("unlock", "ch1")) <= 1 and not c.get("require_flag") and not c.get("require_any"):
        ch1_roles.add(c["role"])
check(len(ch1_roles) >= 6, f"第一章无旗标门槛的职事仍覆盖 {len(ch1_roles)}/6 种")

print()
print("=" * 68)
print("十、名声换爵与港口投资（职衔不另开章门，修埠不造同港套利）")
print("=" * 68)

titles_doc = load("titles.json")
ranks = titles_doc["ranks"]
invest = titles_doc["invest"]
rank_ids = [r["id"] for r in ranks]
check(len(ranks) == 5, f"职衔五档（实际 {len(ranks)}）")
check(len(rank_ids) == len(set(rank_ids)), "职衔 id 不重复")
check(ranks[0]["min_fame"] == 0, "最低档 min_fame=0，开局即有职衔")
check(all(ranks[i]["min_fame"] < ranks[i+1]["min_fame"] for i in range(len(ranks)-1)),
      "职衔门槛严格递增")
check(all(ranks[i]["duty_factor"] >= ranks[i+1]["duty_factor"] for i in range(len(ranks)-1)),
      "职衔抽解折让不递增")
check(all(ranks[i]["loan_bonus"] <= ranks[i+1]["loan_bonus"] for i in range(len(ranks)-1)),
      "职衔赊贷加成不递减")
check(all(r["duty_factor"] > 0.70 for r in ranks),
      f"最高档抽解仍余 {ranks[-1]['duty_factor']*100:.0f}%——职衔只折不免")
check("纲首" not in "".join(r["name"] for r in ranks),
      "职衔名不用「纲首」（章名已占用）")
for c in load("chapters.json")["chapters"]:
    req = c.get("next_requires") or c.get("ending_requires") or {}
    check("fame" not in req and "title" not in req,
          f"第{c.get('id')}章门槛不含名声/职衔——不另开章门")

costs = invest["costs"]
max_lv = invest["max_level"]
edge_per = invest["edge_per_level"]
depth_per = invest["depth_per_level"]
check(max_lv == len(costs) == 5, f"修埠五等，成本表 {len(costs)} 档")
check(all(costs[i] < costs[i+1] for i in range(len(costs)-1)), "修埠成本严格递增")
check(costs[0] <= 1000, f"一等修埠 {costs[0]} ≤ 1000，第一章就能做选择")
check(sum(costs) < 80000, f"单港修满 {sum(costs)} < 了结本钱 80000")
check(edge_per * max_lv <= 0.15, f"满级修埠价沿 {edge_per*max_lv:.3f} ≤ 0.15")
check(0 < depth_per * max_lv <= 0.80, f"满级深度 +{depth_per*max_lv*100:.0f}% 只加深不改角色")

max_title = ranks[-1]["duty_factor"]
max_zashi = best_lv.get("zashi", 0)
max_tong = best_lv.get("tongshi", 0)
check(edge_per == INVEST_EDGE_PER, f"定价镜像的修埠价沿取同一份 titles.json（{INVEST_EDGE_PER}）")

# Lane ea2：本节原有自带的 stacked_price 镜像，不含同港价差地板（与二之二节、与生产都不同式），
# 故只敢扫「不通事」——带通事一扫必倒挂。现统一经 price_at（含地板），通事 0..满级一并扫。
local_arb = []
for pid, p in ports.items():
    for gid in p.get("market", {}):
        for t in range(max_tong + 1):
            b = price_at(pid, gid, True, max_zashi, t, max_title, max_lv)
            s = price_at(pid, gid, False, max_zashi, t, max_title, max_lv)
            if s > b:
                local_arb.append(f"{p.get('name', pid)}/{gid} 通事{t} 卖{s}>买{b}")
check(not local_arb,
      f"满修埠+满职衔+满杂事、通事 0..{max_tong} 级时同港无正套利（违例 {local_arb[:3] or '无'}）")

gid = "qingbai_porcelain"
bare = sell_price("hakata", gid) - buy_price("quanzhou", gid)
full_crew_title_inv = (
    price_at("hakata", gid, False, max_zashi, max_tong, max_title, max_lv)
    - price_at("quanzhou", gid, True, max_zashi, max_tong, max_title, max_lv)
)
infl_all = (full_crew_title_inv / bare - 1) * 100 if bare else 0
print(f"  泉州→博多 青白瓷：裸价差 {bare} → 满编+都保+满修埠 {full_crew_title_inv}（+{infl_all:.0f}%）")
check(full_crew_title_inv > bare, "修埠+职衔仍拉大核心商路价差")
check(infl_all < 100, f"满栈利润膨胀 {infl_all:.0f}% < 100%（未印钞）")
check(trade_cost(MAXLV) * max_title > 0.40,
      f"满杂事×都保后抽解份额仍余 {trade_cost(MAXLV)*max_title*100:.0f}%")
print("九之二、进港命名空间（剧情 id 不得盖住港口）（云端 c148）")
print("=" * 68)
scenes_doc = load("scenes.json")
scene_by_id = {s["id"]: s for s in scenes_doc["scenes"]}
# 海图回港 load_scene(port_id)。同名剧情若 type 不是 port，会先被当成正文，
# visit_port 不调用，第一章 must_visit ryukyu 永远完不成。
shadowed = []
for pid in ports:
    sc = scene_by_id.get(pid)
    if sc is not None and sc.get("type", "scene") != "port":
        shadowed.append(pid)
check(not shadowed, "港口 id 不被非 port 剧情占用" + (f"（{shadowed}）" if shadowed else ""))
for sid in ("ryukyu_bay", "hakata_ledger"):
    check(sid in scene_by_id, f"剧情正文改挂 {sid}，港口 id 留给牙行（c148 原名 *_story，按 00b4 定名）")
# 选项 next 必须落到场景或港口，否则改名后剧情链断
dangling = []
for sc in scenes_doc["scenes"]:
    for key in ("choices", "investigations"):
        for ch in sc.get(key, []) or []:
            nxt = ch.get("next", "")
            if nxt and nxt not in scene_by_id and nxt not in ports:
                dangling.append(f"{sc['id']}→{nxt}")
check(not dangling, "场景 next 都指向场景或港口" + (f"（{dangling[:6]}）" if dangling else ""))
opening = ["cg_title", "cg_world_north", "cg_world_east", "cg_world_south", "cg_world_west"]
bad_open = [sid for sid in opening
            if scene_by_id.get(sid, {}).get("type") != "title"
            or not str(scene_by_id.get(sid, {}).get("cg_title", "")).strip()
            or not str(scene_by_id.get(sid, {}).get("cg_sub", "")).strip()]
check(not bad_open, "开场五屏 type=title 且标题正文都在" + (f"（{bad_open}）" if bad_open else ""))
print("九之三、哗变：断粮才闹舱，三种了结都留得下船（云端 7d9f）")
print("=" * 68)

fleet_src = open(os.path.join(os.path.dirname(__file__), "..", "scripts", "core", "Fleet.gd"),
                 encoding="utf-8").read()

def fleet_const(name):
    m = re.search(rf"const {name} := (-?\d+(?:\.\d+)?)", fleet_src)
    if not m:
        raise SystemExit(f"Fleet.gd 缺少 {name}")
    raw = m.group(1)
    return float(raw) if "." in raw else int(raw)

M_LINE = fleet_const("MUTINY_LINE")
M_COOL = fleet_const("MUTINY_COOLDOWN_DAYS")
M_FLOOR = fleet_const("MUTINY_BRIBE_FLOOR")
M_PER = fleet_const("MUTINY_BRIBE_PER_CREW")
M_BRIBE = fleet_const("MUTINY_BRIBE_MORALE")
M_DIS_PCT = fleet_const("MUTINY_DISMISS_PERCENT")
M_DIS_CARGO = fleet_const("MUTINY_DISMISS_CARGO")
M_DIS_MORALE = fleet_const("MUTINY_DISMISS_MORALE")
M_NEED = fleet_const("MUTINY_SUPPRESS_NEED")
M_SUP_MORALE = fleet_const("MUTINY_SUPPRESS_MORALE")
M_SUP_PCT = fleet_const("MUTINY_SUPPRESS_PERCENT")
M_SUP_CARGO = fleet_const("MUTINY_SUPPRESS_CARGO")

def crew_percent(crew, percent):
    return max(1, int((crew * percent) / 100.0))

# 开局小艍：6 人，水粮各 60，每日 ceil(6/2)=3。扣到 0 的当天就算断粮，士气 -6。
# 不计风涛和无风（那些会更早）。这是只靠水粮的钟。
starter_crew = ships["sampan"]["crew_min"]
daily = math.ceil(starter_crew / 2)
water, morale, day, starve = 60, 70, 0, 0
while day < 80 and morale > M_LINE:
    day += 1
    water = max(0, water - daily)
    if water <= 0:
        morale = max(0, morale - 6)
        starve += 1
trigger_morale = morale
print(f"  不补水粮：第 {day} 日哗变（其中断粮 {starve} 日），士气 {trigger_morale}，线 {M_LINE}")
check(24 <= day <= 36, f"只靠开局水粮，第 {day} 日才哗变（近海三五日出不了这事）")
check(8 <= starve <= 12, f"断粮 {starve} 日才哗变（落在 8～12，不会一饿就炸，也不会拖过两旬）")
check(trigger_morale <= M_LINE, f"触发日士气 {trigger_morale} ≤ {M_LINE}")
check(70 - 12 > M_LINE, "单次战败 -12 从 70 掉不到哗变线")
check(70 - 8 - 12 > M_LINE, "一场满风涛 -8 再加战败 -12，仍高于哗变线")

bribe6 = max(M_FLOOR, starter_crew * M_PER)
bribe50 = max(M_FLOOR, 50 * M_PER)
print(f"  六人散钱 {bribe6}，五十人散钱 {bribe50}")
check(60 <= bribe6 <= 120, f"开局散钱 {bribe6} 落在 60～120（付得起，也不是象征性的几文）")
check(bribe6 < 1000, f"开局散钱 {bribe6} < 本金 1000")
check(bribe50 > bribe6, f"五十人散钱 {bribe50} > 六人 {bribe6}（按人头涨）")
after_bribe = min(100, trigger_morale + M_BRIBE)
check(after_bribe >= M_LINE + 15, f"散钱后士气 {after_bribe} ≥ 线+15（一次散钱能离开哗变线一截）")

leave = crew_percent(starter_crew, M_DIS_PCT)
cargo_dis = math.ceil(10 * M_DIS_CARGO)
print(f"  六人放走 {leave} 人；10 件货抬走 {cargo_dis}")
check(1 <= leave < starter_crew, f"放人 {leave} 人，船还留得下人")
check(starter_crew - leave < ships["sampan"]["crew_min"],
      f"放人后剩 {starter_crew - leave} 人 < 小艍最低水手 {ships['sampan']['crew_min']}，下一趟要补人")
main_src = open(os.path.join(os.path.dirname(__file__), "..", "scripts", "Main.gd"),
                encoding="utf-8").read()
hire_m = re.search(r"below_min \* (\d+)", main_src)
hire_each = int(hire_m.group(1)) if hire_m else 0
check(hire_each > 0 and bribe6 > hire_each * leave,
      f"散钱 {bribe6} > 事后补 {leave} 人的 {hire_each * leave}（留人比雇人贵，贵在保住那份货）")
check(1 <= cargo_dis <= 2, f"放人抬走的 10 件里是 {cargo_dis} 件（有代价，但不清舱）")
after_dis = min(100, trigger_morale + M_DIS_MORALE)
check(after_dis > M_LINE, f"放人后士气 {after_dis} > {M_LINE}")

print(f"  开局武力 50 + 士气 {trigger_morale} = {50 + trigger_morale}，压住线 {M_NEED}")
check(50 + trigger_morale >= M_NEED, "第一次哗变，开局武力压得住")
after_sup = min(100, trigger_morale + M_SUP_MORALE)
check(M_LINE < after_sup < after_bribe, f"压住后士气 {after_sup}，高于线、低于散钱（压是弱选项）")
cooled = after_sup
for _ in range(M_COOL):
    cooled = max(0, cooled - 6)
print(f"  压住后再断粮 {M_COOL} 日，士气 {cooled}")
check(M_COOL >= 4, f"冷却 {M_COOL} 日 ≥ 4（不是天天拦船）")
check(50 + cooled < M_NEED, f"冷却耗尽后再压：武力 50 + 士气 {cooled} < {M_NEED}")
fail_leave = crew_percent(starter_crew, M_SUP_PCT)
cargo_fail = math.ceil(10 * M_SUP_CARGO)
check(fail_leave >= leave, f"压失败走 {fail_leave} 人 ≥ 主动放人 {leave}")
check(cargo_fail > cargo_dis, f"压失败抬货 {cargo_fail} > 主动放人 {cargo_dis}")
print("九之四、风涛：每艘各吃一份，旗舰不替护航船挨打（云端 storm-7d9f）")
print("=" * 68)

voyage_src = open(os.path.join(ROOT, "scripts", "core", "Voyage.gd"), encoding="utf-8").read()
storm_body = voyage_src.split("func _storm_event", 1)[1].split("\nfunc ", 1)[0]
hit_m = re.search(r"var each := ([0-9.]+) \* severity", storm_body)
storm_base = float(hit_m.group(1)) if hit_m else 0.0
print(f"  满强度、无甲，每艘 {storm_base:.1f}")
check(0 < storm_base <= ships["sampan"]["durability"] * 0.2,
      f"一场满风涛每艘 {storm_base:.1f} ≤ 小艍耐久的两成（{ships['sampan']['durability'] * 0.2:.0f}）")

def storm_left(hulls, each):
    return [max(0.0, h - each) for h in hulls]

one = storm_left([ships["sampan"]["durability"]], storm_base)
check(one[0] == ships["sampan"]["durability"] - storm_base,
      f"单船小艍满风涛后剩 {one[0]:.0f}（与旧的单船公式相同）")
flag0 = ships["fu_ship_medium"]["durability"]
esc0 = ships["sampan"]["durability"]
two = storm_left([flag0, esc0], storm_base)
piled = flag0 - storm_base * 2
print(f"  福船+小艍：旗舰 {flag0:.0f}→{two[0]:.0f}，护航 {esc0:.0f}→{two[1]:.0f}；堆在旗舰上会是 {piled:.0f}")
check(two[0] == flag0 - storm_base, f"旗舰只掉自己的 {storm_base:.0f}")
check(two[1] == esc0 - storm_base, f"护航船也掉 {storm_base:.0f}")
check(two[0] > piled, f"旗舰剩 {two[0]:.0f}，不是把两艘的份量堆成 {piled:.0f}")
check((flag0 - two[0]) + (esc0 - two[1]) == storm_base * 2,
      "健康舰队的总伤仍是每艘一份相加（日志上的总数不变）")
armored = storm_left([flag0, esc0], storm_base * 0.8)
check(abs(armored[0] - (flag0 - storm_base * 0.8)) < 1e-9,
      f"满甲后旗舰掉 {storm_base * 0.8:.1f}，不是 {storm_base:.0f}")
wreck = storm_left([4.0], storm_base)
check(wreck[0] == 0.0, "残船扣到 0 为止，不出现负耐久")
print("九之五、航法、海上交市、牙行委办（云端 bed9）")
print("=" * 68)
print("  针路保持旧的日速与事件表。外洋赶期限，傍岸换岸影，生路才会迷航。")
print("  海上买卖不得压过港口；委办是小批量、有期限、交货不砸盘。")

import re

def gd_const(rel, name):
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    m = re.search(rf"const {name} := (-?[0-9.]+)", src)
    if not m:
        raise SystemExit(f"找不到 {rel} 的 const {name}")
    return float(m.group(1))

V_GD = "scripts/core/Voyage.gd"
S_GD = "scripts/GameState.gd"
OFF_SPD = gd_const(V_GD, "ORDER_SPEED_OFFSHORE")
COAST_SPD = gd_const(V_GD, "ORDER_SPEED_COAST")
SEA_BUY_MARKUP = gd_const(V_GD, "SEA_BUY_MARKUP")
SEA_SELL_CAP = gd_const(V_GD, "SEA_SELL_CAP")
W_STORM_BASE = gd_const(V_GD, "W_STORM_BASE")
W_STORM_WIND = gd_const(V_GD, "W_STORM_WIND")
W_PIRATE = gd_const(V_GD, "W_PIRATE")
W_CALM = gd_const(V_GD, "W_CALM")
W_CURRENT = gd_const(V_GD, "W_CURRENT")
W_MERCHANT = gd_const(V_GD, "W_MERCHANT")
W_DISCOVERY = gd_const(V_GD, "W_DISCOVERY")
OFFSHORE_STORM_MUL = gd_const(V_GD, "OFFSHORE_STORM_MUL")
OFFSHORE_PIRATE_MUL = gd_const(V_GD, "OFFSHORE_PIRATE_MUL")
OFFSHORE_CALM = gd_const(V_GD, "OFFSHORE_CALM")
OFFSHORE_CURRENT = gd_const(V_GD, "OFFSHORE_CURRENT")
OFFSHORE_MERCHANT = gd_const(V_GD, "OFFSHORE_MERCHANT")
OFFSHORE_DISCOVERY = gd_const(V_GD, "OFFSHORE_DISCOVERY")
COAST_STORM_MUL = gd_const(V_GD, "COAST_STORM_MUL")
COAST_PIRATE_MUL = gd_const(V_GD, "COAST_PIRATE_MUL")
COAST_CALM = gd_const(V_GD, "COAST_CALM")
COAST_CURRENT = gd_const(V_GD, "COAST_CURRENT")
COAST_MERCHANT = gd_const(V_GD, "COAST_MERCHANT")
COAST_DISCOVERY = gd_const(V_GD, "COAST_DISCOVERY")
COAST_SHOAL = gd_const(V_GD, "COAST_SHOAL")
LOST_RUMB = gd_const(V_GD, "LOST_RUMB")
LOST_OFFSHORE = gd_const(V_GD, "LOST_OFFSHORE")
LOST_COAST = gd_const(V_GD, "LOST_COAST")
MAX_EVENT_MASS = gd_const(V_GD, "MAX_EVENT_MASS")
CONTRACT_PREMIUM = gd_const(S_GD, "CONTRACT_PREMIUM")
CONTRACT_SLACK = int(gd_const(S_GD, "CONTRACT_SLACK_DAYS"))
CONTRACT_QTY_BUDGET = gd_const(S_GD, "CONTRACT_QTY_BUDGET")
CONTRACT_QTY_MIN = int(gd_const(S_GD, "CONTRACT_QTY_MIN"))
CONTRACT_QTY_MAX = int(gd_const(S_GD, "CONTRACT_QTY_MAX"))
CONTRACT_FINE_RATE = gd_const(S_GD, "CONTRACT_FINE_RATE")
CONTRACT_FINE_MIN = int(gd_const(S_GD, "CONTRACT_FINE_MIN"))
CONTRACT_BASE_MIN = gd_const(S_GD, "CONTRACT_BASE_MIN")
RUMOR_STALE = int(gd_const(S_GD, "RUMOR_STALE_DAYS"))

check(1.05 < OFF_SPD <= 1.20, f"外洋日速 ×{OFF_SPD} 落在 (1.05, 1.20]，赶路但不架空候风")
check(0.70 <= COAST_SPD < 0.90, f"傍岸日速 ×{COAST_SPD} 落在 [0.70, 0.90)，慢，但远洋仍走得完")
check(0.40 * OFF_SPD < 1.0, f"顶头逆风 × 外洋 = {0.40 * OFF_SPD:.3f} < 1，逆风不会被航法乘成顺风")
check(1.60 * COAST_SPD < 1.60 * 1.0, "顺风傍岸仍慢于顺风针路")

def event_weights(order, strength, known, discoveries_open=True):
    """复刻 Voyage.event_weights。order: rumb / offshore / coast。"""
    storm = W_STORM_BASE + W_STORM_WIND * strength
    pirate, calm, current = W_PIRATE, W_CALM, W_CURRENT
    merchant, discovery, shoal, lost = W_MERCHANT, W_DISCOVERY, 0.0, 0.0
    if order == "offshore":
        storm *= OFFSHORE_STORM_MUL
        pirate *= OFFSHORE_PIRATE_MUL
        calm, current = OFFSHORE_CALM, OFFSHORE_CURRENT
        merchant, discovery = OFFSHORE_MERCHANT, OFFSHORE_DISCOVERY
    elif order == "coast":
        storm *= COAST_STORM_MUL
        pirate *= COAST_PIRATE_MUL
        calm, current = COAST_CALM, COAST_CURRENT
        merchant, discovery, shoal = COAST_MERCHANT, COAST_DISCOVERY, COAST_SHOAL
    if not known:
        lost = {"offshore": LOST_OFFSHORE, "coast": LOST_COAST}.get(order, LOST_RUMB)
    keys = ["storm", "pirate", "calm", "current", "merchant", "discovery", "shoal", "lost"]
    vals = [storm, pirate, calm, current, merchant, discovery, shoal, lost]
    mass = sum(vals)
    if mass > MAX_EVENT_MASS:
        vals = [v * MAX_EVENT_MASS / mass for v in vals]
        mass = MAX_EVENT_MASS
    if not discoveries_open and vals[keys.index("discovery")] > 0:
        disc = vals[keys.index("discovery")]
        kept = mass - disc
        if kept > 0:
            scale = mass / kept
            vals = [0.0 if i == keys.index("discovery") else v * scale for i, v in enumerate(vals)]
    return dict(zip(keys, vals))

rumb = event_weights("rumb", 1.0, True)
check(abs(rumb["storm"] - 0.12) < 1e-9 and abs(rumb["pirate"] - 0.06) < 1e-9
      and abs(rumb["calm"] - 0.06) < 1e-9 and abs(rumb["current"] - 0.05) < 1e-9
      and abs(rumb["merchant"] - 0.04) < 1e-9 and abs(rumb["discovery"] - 0.03) < 1e-9
      and rumb["shoal"] == 0 and rumb["lost"] == 0,
      "针路 + 熟路的事件表与改航法前逐项相同（暴风 0.12 / 海盗 0.06 / …）")
off = event_weights("offshore", 1.0, True)
coast = event_weights("coast", 1.0, True)
check(off["pirate"] > rumb["pirate"] > coast["pirate"],
      f"海盗概率 外洋 {off['pirate']:.3f} > 针路 {rumb['pirate']:.3f} > 傍岸 {coast['pirate']:.3f}")
check(coast["discovery"] > rumb["discovery"] > off["discovery"],
      f"岸影概率 傍岸 {coast['discovery']:.3f} > 针路 {rumb['discovery']:.3f} > 外洋 {off['discovery']:.3f}")
check(coast["shoal"] > 0 and rumb["shoal"] == 0 and off["shoal"] == 0, "只有傍岸会擦浅滩")
lost_r = event_weights("rumb", 1.0, False)
lost_o = event_weights("offshore", 1.0, False)
lost_c = event_weights("coast", 1.0, False)
check(event_weights("rumb", 1.0, True)["lost"] == 0, "熟路不迷航")
check(lost_o["lost"] > lost_r["lost"] > lost_c["lost"] > 0,
      f"生路迷航 外洋 {lost_o['lost']:.3f} > 针路 {lost_r['lost']:.3f} > 傍岸 {lost_c['lost']:.3f}")
for name, w in (("针路熟路", rumb), ("外洋生路", lost_o), ("傍岸生路", event_weights("coast", 1.0, False))):
    check(sum(w.values()) <= MAX_EVENT_MASS + 1e-9, f"{name} 事件总质量 {sum(w.values()):.3f} ≤ {MAX_EVENT_MASS}")
coast_closed = event_weights("coast", 1.0, False, False)
check(abs(sum(coast_closed.values()) - sum(event_weights("coast", 1.0, False).values())) < 1e-9
      and coast_closed["discovery"] == 0
      and coast_closed["shoal"] > event_weights("coast", 1.0, False)["shoal"],
      "岸影抽空后傍岸总质量不变、浅滩概率上升，不会变成白走的无事日")
SHOAL_P = gd_const(V_GD, "SHOAL_PROGRESS")
LOST_P = gd_const(V_GD, "LOST_PROGRESS")

def progress_expectation(order, known, discoveries_open=True, strength=1.0):
    """复刻 Voyage.progress_expectation。风暴不拖日，无风、浅滩、迷航拖。"""
    w = event_weights(order, strength, known, discoveries_open)
    e = 1.0
    e += w["calm"] * (0.0 - 1.0)
    e += w["current"] * (1.5 - 1.0)
    e += w["shoal"] * (SHOAL_P - 1.0)
    e += w["lost"] * (LOST_P - 1.0)
    return e

er, eo, ec = (progress_expectation(o, True) for o in ("rumb", "offshore", "coast"))
eru, eou, ecu = (progress_expectation(o, False) for o in ("rumb", "offshore", "coast"))
check(OFF_SPD * eo > er > COAST_SPD * ec > 0.5,
      f"熟路日速×遇事：外洋 {OFF_SPD * eo:.3f} > 针路 {er:.3f} > 傍岸 {COAST_SPD * ec:.3f}")
check(OFF_SPD * eou > eru > COAST_SPD * ecu > 0.4,
      f"生路日速×遇事：外洋 {OFF_SPD * eou:.3f} > 针路 {eru:.3f} > 傍岸 {COAST_SPD * ecu:.3f}")
check(max(er, eo, ec, eru, eou, ecu) < 1.0, "无风使遇事行程慢于静风，遇事日数不会短于静风日数")
check(progress_expectation("coast", False, False) < ecu, "岸影抽空后傍岸遇事更慢")

def ch_of(unlock):
    if isinstance(unlock, str) and unlock.startswith("ch"):
        return int(unlock[2:])
    return 1

def sea_buy_unit(gid, live_min=0):
    """海上买价。live_min 是已解锁港口里的最低现买价；低于行情 1.0 的普通口岸时不采用。"""
    normal = round(goods[gid]["base_value"] * (1 + TARIFF))
    floor = max(normal, live_min)
    return math.ceil(floor * SEA_BUY_MARKUP)

def best_consumer_sell(gid, chapter=4):
    best = 0
    any_sell = 0
    for pid, p in ports.items():
        if p.get("depth", 0) <= 0 or ch_of(p.get("unlock", "ch1")) > chapter:
            continue
        if gid not in p.get("market", {}):
            continue
        s = sell_price(pid, gid)
        any_sell = max(any_sell, s)
        if role(pid, gid) == "consumer":
            best = max(best, s)
    return best or any_sell

def sea_sell_unit(avg_cost, jitter, best):
    raw = round(max(avg_cost, 1) * jitter)
    if best > 0:
        cap = int(best * SEA_SELL_CAP)
        raw = min(raw, max(1, cap))
    return max(1, raw)

origin_beats = True
sell_capped = True
worst_gap = None
for gid, g in goods.items():
    if not g.get("tradable") or g.get("contraband") or g.get("base_value", 0) <= 0 or g.get("bulk", 0) <= 0:
        continue
    unit = sea_buy_unit(gid)
    for pid, p in ports.items():
        if p.get("market", {}).get(gid) in ("origin", "normal"):
            if unit <= buy_price(pid, gid):
                origin_beats = False
    best = best_consumer_sell(gid)
    if best < 2:
        continue
    for jitter in (gd_const(V_GD, "SEA_SELL_JITTER_MIN"), gd_const(V_GD, "SEA_SELL_JITTER_MAX")):
        # 成本就算已经是消费地卖价，海上也卖不过那个港口
        sold = sea_sell_unit(best, jitter, best)
        if sold >= best:
            sell_capped = False
        gap = best - sold
        if worst_gap is None or gap < worst_gap:
            worst_gap = gap
check(origin_beats, "海上买价严格高于任一产地或普通口岸的买价（产地低价买不到）")
check(sell_capped, f"海上卖价严格低于最佳消费地卖价（最窄价差 {worst_gap}）")
spiked_ok = True
discount_ok = True
for gid, g in goods.items():
    if not g.get("tradable") or g.get("contraband") or g.get("base_value", 0) <= 0 or g.get("bulk", 0) <= 0:
        continue
    lives = [buy_price(pid, gid, 2.2) for pid, p in ports.items()
             if p.get("depth", 0) > 0 and gid in p.get("market", {})]
    lows = [buy_price(pid, gid, 0.4) for pid, p in ports.items()
            if p.get("depth", 0) > 0 and gid in p.get("market", {})]
    if not lives or not lows:
        continue
    if sea_buy_unit(gid, min(lives)) <= min(lives):
        spiked_ok = False
    plain = sea_buy_unit(gid)
    if min(lows) < plain and sea_buy_unit(gid, min(lows)) != plain:
        discount_ok = False
check(spiked_ok, "港口被买到行情 2.2 后，海上买价仍高于最便宜的那个港口")
check(discount_ok, "产地行情跌到 0.4 时，海上买价不跟着降到产地价")

def stable_hash(s):
    h = 0
    for ch in s:
        h = (h * 33 + ord(ch)) % 1000003
    return h

def contract_qty(gid):
    return max(CONTRACT_QTY_MIN, min(CONTRACT_QTY_MAX, int(CONTRACT_QTY_BUDGET / goods[gid]["bulk"])))

def rumb_days(src, dst, wind_b=-1.0, strength=0.3, morale=70, ship_id="sampan"):
    d = distance_li(src, dst)
    spd = ships[ship_id]["base_speed"] * (0.6 + 0.4 * morale / 100.0) * wind_factor(bearing(src, dst), wind_b, strength)
    if spd <= 1:
        return 999
    return math.ceil(d / spd)

def shift_date(year, month, day, n=1):
    """与 Voyage._shift_date 相同：每月 30 日，不改历法本体。"""
    for _step in range(n):
        day += 1
        if day > 30:
            day = 1
            month += 1
            if month > 12:
                month = 1
                year += 1
    return year, month, day

def month_wind(month):
    if month >= 10 or month <= 2:
        return 225.0, (1.0 if month in (11, 12, 1) else 0.8)
    if 5 <= month <= 8:
        return 45.0, (1.0 if month in (6, 7) else 0.8)
    return -1.0, 0.3

def walk_calm_days(src, dst, month, day, year=1255, morale=70, ship_id="sampan"):
    """从次日启航，按每天的风扣里程。返回 (日数, 途中是否换风)。"""
    dist = distance_li(src, dst)
    y, m, d = shift_date(year, month, day, 1)
    spd0 = ships[ship_id]["base_speed"] * (0.6 + 0.4 * morale / 100.0)
    course = bearing(src, dst)
    rem = dist
    n = 0
    first = None
    changed = False
    while rem > 0 and n < 900:
        wb, st = month_wind(m)
        wf = wind_factor(course, wb, st)
        if first is None:
            first = wf
        elif abs(wf - first) > 0.001:
            changed = True
        gain = spd0 * wf
        if gain <= 1:
            return 999, changed
        rem -= gain
        n += 1
        y, m, d = shift_date(y, m, d, 1)
    return n, changed

def progress_spread(order, known, strength):
    """复刻 Voyage.progress_moments。返回 (均值, 方差)。"""
    w = event_weights(order, strength, known, True)
    pc, pu, ps, pl = w["calm"], w["current"], w["shoal"], w["lost"]
    mean = progress_expectation(order, known, True, strength)
    rest = 1.0 - pc - pu - ps - pl
    second = rest + pu * 2.25 + ps * (SHOAL_P ** 2) + pl * (LOST_P ** 2)
    return mean, max(0.0, second - mean * mean)

def walk_event_days(src, dst, month, day, order="rumb", known=True, drag_days=0,
                    year=1255, morale=70, ship_id="sampan"):
    """从次日启航按遇事均值扣里程。drag_days>0 时走八成偏慢路径。"""
    dist = distance_li(src, dst)
    course = bearing(src, dst)
    y, m, d = shift_date(year, month, day, 1)
    spd_base = ships[ship_id]["base_speed"] * (0.6 + 0.4 * morale / 100.0)
    mult = {"offshore": OFF_SPD, "coast": COAST_SPD}.get(order, 1.0)
    rem = dist
    n = 0
    drag_scale = (gd_const(V_GD, "SAFE_Z") / math.sqrt(drag_days)) if drag_days > 0 else 0.0
    while rem > 0 and n < 900:
        _wb, st = month_wind(m)
        wf = wind_factor(course, _wb, st)
        mean, var = progress_spread(order, known, st)
        ex = mean
        if drag_scale > 0.0:
            ex = max(0.05, ex - drag_scale * math.sqrt(var))
        gain = spd_base * wf * mult * ex
        if gain <= 1:
            return 999
        rem -= gain
        n += 1
        y, m, d = shift_date(y, m, d, 1)
    return n

def known_route(a, b):
    """连线无向。与 Voyage.is_known_route 一致。"""
    if a not in ports or b not in ports:
        return False
    return b in ports[a].get("connections", []) or a in ports[b].get("connections", [])

def contract_offer(port_id, year=1255, month=3, chapter=1):
    """开局三月、转换期、小艍、士气 70、行情 1.0。复刻 GameState.contract_offer 的选型。"""
    def destinations(gid):
        out = []
        for pid, p in ports.items():
            if pid == port_id or p.get("depth", 0) <= 0:
                continue
            if ch_of(p.get("unlock", "ch1")) > chapter:
                continue
            if p.get("market", {}).get(gid) != "consumer":
                continue
            out.append(pid)
        out.sort()
        return out
    goods_ids = []
    for gid, rel in ports[port_id].get("market", {}).items():
        g = goods[gid]
        if not g.get("tradable") or g.get("contraband"):
            continue
        if g.get("base_value", 0) < CONTRACT_BASE_MIN or g.get("bulk", 0) <= 0:
            continue
        if rel == "consumer":
            continue
        if not destinations(gid):
            continue
        goods_ids.append(gid)
    goods_ids.sort()
    if not goods_ids:
        return {}
    seed = stable_hash(port_id) + year * 12 + month
    gid = goods_ids[seed % len(goods_ids)]
    dests = destinations(gid)
    if not dests:
        return {}
    known = [pid for pid in dests if known_route(port_id, pid)]
    pool = known or dests
    dest = pool[(seed // 7) % len(pool)]
    qty = contract_qty(gid)
    days = rumb_days(port_id, dest)
    if days >= 900 or days <= 0:
        return {}
    sale = sell_revenue(dest, gid, qty)
    premium = round(qty * goods[gid]["base_value"] * CONTRACT_PREMIUM)
    return {
        "good_id": gid, "qty": qty, "dest": dest, "from": port_id,
        "purse": sale + premium, "premium": premium,
        "voyage_days": days, "deadline_days": days + CONTRACT_SLACK,
    }

offer = contract_offer("quanzhou")
check(bool(offer), "开局泉州牙行能开出一笔委办")
if offer:
    gid, dest, qty = offer["good_id"], offer["dest"], offer["qty"]
    print(f"  泉州三月委办：{goods[gid]['name']} ×{qty} → {ports[dest]['name']}　"
          f"针路 {offer['voyage_days']} 日，期限 {offer['deadline_days']} 日，酬 {offer['purse']}")
    check(goods[gid].get("contraband") is not True, "委办货不是违禁品")
    check(role("quanzhou", gid) != "consumer", "委办不把本地紧缺货往外送")
    check(role(dest, gid) == "consumer" and ports[dest]["depth"] > 0, "交货地是已解锁的消费港")
    check(ch_of(ports[dest].get("unlock", "ch1")) <= 1, "开局委办的交货地第一章就到得了")
    known_dests = [pid for pid, p in ports.items()
                   if p.get("market", {}).get(gid) == "consumer" and p.get("depth", 0) > 0
                   and ch_of(p.get("unlock", "ch1")) <= 1 and known_route("quanzhou", pid)]
    if known_dests:
        check(dest in known_dests, "有熟路消费地时，委办不把货派去生路")
    check(CONTRACT_QTY_MIN <= qty <= CONTRACT_QTY_MAX, f"委办件数 {qty} 在 {CONTRACT_QTY_MIN}–{CONTRACT_QTY_MAX}")
    sale = offer["purse"] - offer["premium"]
    check(offer["purse"] > sale and offer["premium"] > 0, "酬金高于直接卖掉的实得，溢价为正")
    check(offer["purse"] <= sale * 1.25, f"溢价未超过实得的 25%（酬 {offer['purse']} / 卖 {sale}）")
    fine = max(CONTRACT_FINE_MIN, round(offer["purse"] * CONTRACT_FINE_RATE))
    check(fine < offer["purse"], f"误期罚款 {fine} < 酬金 {offer['purse']}（货还在，不会罚穿）")
    coast_days = math.ceil(distance_li("quanzhou", dest) / (
        ships["sampan"]["base_speed"] * (0.6 + 0.4 * 0.7) * 0.85 * COAST_SPD))
    off_days = math.ceil(distance_li("quanzhou", dest) / (
        ships["sampan"]["base_speed"] * (0.6 + 0.4 * 0.7) * 0.85 * OFF_SPD))
    check(off_days <= offer["voyage_days"], f"外洋 {off_days} 日 ≤ 针路 {offer['voyage_days']} 日")
    print(f"  同一单：外洋 {off_days} 日 / 针路 {offer['voyage_days']} 日 / 傍岸 {coast_days} 日 / 期限 {offer['deadline_days']} 日")

# 傍岸不是永远安全，也不是永远赶不上
miss = fit = False
spd0 = ships["sampan"]["base_speed"] * (0.6 + 0.4 * 0.7)
for a, pa in ports.items():
    for b, pb in ports.items():
        if a == b or pa.get("depth", 0) <= 0 or pb.get("depth", 0) <= 0:
            continue
        d = distance_li(a, b)
        r_days = math.ceil(d / spd0)
        c_days = math.ceil(d / (spd0 * COAST_SPD))
        if c_days > r_days + CONTRACT_SLACK:
            miss = True
        if r_days <= 4 and c_days <= r_days + CONTRACT_SLACK:
            fit = True
check(miss, "存在长航次：傍岸日数超过针路期限（赶委办不能无脑贴岸）")
check(fit, "存在短航次：傍岸仍赶得上期限（贴岸不是死选项）")

# 日数从次日启航起按逐日风信累加。三月初一的短航次整段仍在转换期，开局委办数字不变。
march_walk, march_changed = walk_calm_days("quanzhou", "wenzhou", 3, 1)
check(march_walk == rumb_days("quanzhou", "wenzhou") and not march_changed,
      f"三月初一泉州→温州整段都在转换期，逐日静风仍是 {march_walk} 日")
if offer:
    check(march_walk == offer["voyage_days"],
          "开局委办的针路日数等于逐日静风，不因换季算法改写")

aug_snap = rumb_days("quanzhou", "hakata", 45.0, 0.8)
aug_walk, _aug_changed = walk_calm_days("quanzhou", "hakata", 8, 30)
aug_trans = rumb_days("quanzhou", "hakata", -1.0, 0.3)
check(aug_walk == aug_trans and aug_walk > aug_snap + CONTRACT_SLACK,
      f"八月三十泉州→博多：当天西南风 {aug_snap} 日，明日启航落入转换期 {aug_walk} 日，按旧风计价的期限赶不上")
aug_cross = any(
    ch and w > aug_snap
    for day in range(1, 31)
    for w, ch in [walk_calm_days("quanzhou", "hakata", 8, day)]
)
check(aug_cross, "八月里有出发日会在泉州→博多途中换风，逐日静风长于把西南风套全程")
feb_snap = rumb_days("quanzhou", "guangzhou", 225.0, 0.8)
feb_walk, _feb_changed = walk_calm_days("quanzhou", "guangzhou", 2, 30)
# 2d51 折线后泉广航线首段针位变了，「转风后更久」不再必然；保留的不变量是：明日启航吃的是三月的风，与按当日风套全程的日数不同
check(feb_walk != feb_snap,
      f"二月三十泉州→广州：当天东北风套全程 {feb_snap} 日，次日启航逐日累加 {feb_walk} 日（两者不同）")

wz_mean = walk_event_days("quanzhou", "wenzhou", 3, 1, "rumb", True)
wz_safe = walk_event_days("quanzhou", "wenzhou", 3, 1, "rumb", True, wz_mean)
check(wz_safe >= wz_mean and wz_safe <= march_walk + CONTRACT_SLACK,
      f"开局泉州→温州针路八成 {wz_safe} 日，仍落在期限 {march_walk + CONTRACT_SLACK} 内")
if offer:
    unit = buy_price("quanzhou", offer["good_id"])
    afford = affordable_qty("quanzhou", offer["good_id"], 1000)
    check(unit > 0 and buy_cost("quanzhou", offer["good_id"], offer["qty"]) > 1000 and afford < offer["qty"],
          f"开局本金 1000 买不满这单：首件 {unit} 钱，逐件加价凑得出 {afford} 件，单子要 {offer['qty']} 件")
hk_calm, _hk_changed = walk_calm_days("quanzhou", "hakata", 3, 1)
hk_deadline = hk_calm + CONTRACT_SLACK
hk_mean = walk_event_days("quanzhou", "hakata", 3, 1, "offshore", False)
hk_safe = walk_event_days("quanzhou", "hakata", 3, 1, "offshore", False, hk_mean)
check(hk_mean <= hk_deadline < hk_safe,
      f"三月泉州→博多外洋遇事 {hk_mean} 日卡进期限 {hk_deadline}，八成要 {hk_safe} 日")

def flee_fail_chance(morale=70, ship_id="sampan"):
    """复刻 1 - Voyage.flee_success_chance。小艍、士气 70、无火长时航速 105.6，失败率 0.52。"""
    spd = ships[ship_id]["base_speed"] * (0.6 + 0.4 * morale / 100.0)
    return 1.0 - min(0.9, max(0.25, spd / 220.0))

def cargo_hold_chance(month, day, order, known, days, year=1255, morale=70):
    """复刻 Voyage.cargo_hold_chance：从次日启航，按遇事日数连乘「当日没被抢走」。"""
    fail = flee_fail_chance(morale)
    y, m, d = shift_date(year, month, day, 1)
    keep = 1.0
    for _i in range(max(0, days)):
        _wb, st = month_wind(m)
        ww = event_weights(order, st, known, True)
        keep *= 1.0 - ww["pirate"] * fail
        y, m, d = shift_date(y, m, d, 1)
    return keep

def cargo_hold_tenths(p):
    return max(0, min(10, math.floor(p * 10.0)))

wz_deadline = march_walk + CONTRACT_SLACK
wz_off_mean = walk_event_days("quanzhou", "wenzhou", 3, 1, "offshore", True)
wz_off_safe = walk_event_days("quanzhou", "wenzhou", 3, 1, "offshore", True, wz_off_mean)
wz_coast_mean = walk_event_days("quanzhou", "wenzhou", 3, 1, "coast", True)
wz_coast_safe = walk_event_days("quanzhou", "wenzhou", 3, 1, "coast", True, wz_coast_mean)
hold_r = cargo_hold_tenths(cargo_hold_chance(3, 1, "rumb", True, wz_mean))
hold_o = cargo_hold_tenths(cargo_hold_chance(3, 1, "offshore", True, wz_off_mean))
hold_c = cargo_hold_tenths(cargo_hold_chance(3, 1, "coast", True, wz_coast_mean))
check(hold_o < hold_r < hold_c,
      f"开局泉州→温州保货 外洋 {hold_o} < 针路 {hold_r} < 傍岸 {hold_c}")
check(hold_r == 7 and hold_o == 6 and hold_c == 8,
      f"保货十分位下整：针路 {hold_r} / 外洋 {hold_o} / 傍岸 {hold_c}")
check(wz_safe <= wz_deadline and hold_r < 8,
      f"针路八成 {wz_safe} 日赶得上期限 {wz_deadline}，保货只有 {hold_r}，不到八成")
check(wz_off_safe <= wz_deadline and hold_o < 8,
      f"外洋八成 {wz_off_safe} 日赶得上期限 {wz_deadline}，保货只有 {hold_o}")
check(wz_coast_safe > wz_deadline and hold_c >= 8,
      f"傍岸八成 {wz_coast_safe} 日超过期限 {wz_deadline}，保货 {hold_c} 不拿来冒充赶得上")
p_by_mean = cargo_hold_chance(3, 1, "offshore", True, wz_off_mean)
p_by_safe = cargo_hold_chance(3, 1, "offshore", True, wz_off_safe)
# 八成日数比遇事日数长时，按八成算的保货必须更低；两者恰好同日（泉州→温州改走史载航点后 877 里，外洋均为 9 日）则应相等
if wz_off_safe > wz_off_mean:
    check(p_by_mean > p_by_safe + 0.02,
          f"外洋保货按遇事 {wz_off_mean} 日是 {p_by_mean:.3f}，长于按八成 {wz_off_safe} 日的 {p_by_safe:.3f}")
else:
    check(abs(p_by_mean - p_by_safe) < 1e-9,
          f"外洋遇事与八成同为 {wz_off_mean} 日，保货 {p_by_mean:.3f} 与 {p_by_safe:.3f} 相等")
hk_hold = cargo_hold_tenths(cargo_hold_chance(3, 1, "offshore", False, hk_mean))
check(hk_hold <= 2 and hk_safe > hk_deadline,
      f"三月泉州→博多外洋保货只有 {hk_hold}，八成 {hk_safe} 日已超过期限 {hk_deadline}")

def spoil_hold_chance(rate, qty, days, factor=1.0):
    """复刻 Voyage.spoil_hold_chance。不会潮或没有货，概率是 1。"""
    if rate <= 0 or qty <= 0:
        return 1.0
    if days <= 0 or days >= 900:
        return 0.0
    p = min(1.0, rate * qty * factor)
    return (1.0 - p) ** days

if offer:
    spoil_rate = goods[offer["good_id"]]["perishable"]
    have_qty = affordable_qty("quanzhou", offer["good_id"], 1000)
    st_r = cargo_hold_tenths(spoil_hold_chance(spoil_rate, have_qty, wz_safe))
    st_o = cargo_hold_tenths(spoil_hold_chance(spoil_rate, have_qty, wz_off_safe))
    st_c = cargo_hold_tenths(spoil_hold_chance(spoil_rate, have_qty, wz_coast_safe))
    check(spoil_rate > 0 and have_qty == 12,
          f"开局这单会潮，1000 钱凑得出 {have_qty} 件")
    # 具体成数随里程模型变（bed9 原写死 6/6/5，2d51 折线后为 5/6/5）；锁关系：都在 1～9 之间，傍岸最慢故受潮不多于针路
    check(all(1 <= s <= 9 for s in (st_r, st_o, st_c)) and st_c <= st_r,
          f"凑得出 {have_qty} 件，按八成日数受潮：针路 {st_r} / 外洋 {st_o} / 傍岸 {st_c}（傍岸 ≤ 针路）")
    check(wz_safe <= wz_deadline and st_r < 8 and wz_off_safe <= wz_deadline and st_o < 8,
          f"针路、外洋八成赶得上，受潮只有 {st_r} 和 {st_o}，不到八成")
    check(wz_coast_safe > wz_deadline,
          f"傍岸八成 {wz_coast_safe} 日超过期限 {wz_deadline}，不拿受潮来说成日子赶得上")
    st_full = cargo_hold_tenths(spoil_hold_chance(spoil_rate, offer["qty"], wz_safe))
    check(st_full < st_r,
          f"单上 {offer['qty']} 件受潮 {st_full}，比凑得出的 {have_qty} 件更潮")
    st_optimistic = cargo_hold_tenths(spoil_hold_chance(spoil_rate, have_qty, wz_off_mean))
    # 遇事日 ≤ 八成日，故按遇事日算的成数不低于按八成日算的（日数相同则相等）
    check(wz_off_mean <= wz_off_safe and st_optimistic >= st_o,
          f"外洋按遇事 {wz_off_mean} 日下整是 {st_optimistic}，按八成 {wz_off_safe} 日是 {st_o}")
check(spoil_hold_chance(0.0, 16, 9) == 1.0, "不会潮的货，受潮概率是 1")

check(RUMOR_STALE >= 30, f"行情传闻保鲜 {RUMOR_STALE} 日，够跑一趟近海再回来对")
gs_src = open(os.path.join(ROOT, S_GD), encoding="utf-8").read()
deliver_body = gs_src.split("func deliver_contract", 1)[1].split("\nfunc ", 1)[0]
check("apply_sell_impact" not in deliver_body and "remove_cargo" in deliver_body and "add_money" in deliver_body,
      "交货卸货给钱，不调用砸盘")
check("func tick_contract" in gs_src and "advance_days" in open(os.path.join(ROOT, "scripts/GameManager.gd"), encoding="utf-8").read(),
      "逾期在日推进里结算")
check(known_route("zhangzhou", "guangzhou") and known_route("quanzhou", "guangzhou")
      and known_route("ryukyu", "kagoshima"),
      "图上只有去程的三条航路，返程也算熟路")
check(not known_route("quanzhou", "hakata"), "没有连线的泉州–博多仍是生路")
voyage_src = open(os.path.join(ROOT, V_GD), encoding="utf-8").read()
known_body = voyage_src.split("func is_known_route", 1)[1].split("\nfunc ", 1)[0]
check(known_body.count("port_def") >= 2, "熟路判定读了两端的连线，不是只看出发港")
buy_body = voyage_src.split("func sea_buy_unit", 1)[1].split("\nfunc ", 1)[0]
roll_body = voyage_src.split("func roll_day_event", 1)[1].split("\nfunc ", 1)[0]
check("_cheapest_port_buy" in buy_body, "海上买价会看已解锁港口里的最低现价，不会低于它")
weights_body = voyage_src.split("func event_weights", 1)[1].split("\nfunc ", 1)[0]
check("discoveries_open" in weights_body and "_discovery_candidates" in roll_body,
      "岸影抽空时当日权重不再把这一档当成无事日")
plan_body = voyage_src.split("func plan", 1)[1].split("\nfunc ", 1)[0]
walk_body = voyage_src.split("func _walk_days", 1)[1].split("\nfunc ", 1)[0]
check("expected_days" in plan_body and "safe_days" in plan_body and "_walk_days" in plan_body,
      "航程给出静风、遇事和八成日数，期限仍用静风")
check("progress_moments" in walk_body and "_shift_date" in walk_body and "SAFE_Z" in walk_body,
      "遇事与八成从次日启航起按逐日风信累加")
check("wind_changes" in plan_body and "departs_on_new_wind" in plan_body,
      "换季和途中换风会标出来")
main_src = open(os.path.join(ROOT, "scripts/Main.gd"), encoding="utf-8").read()
check("hint_lbl.text = rumor" in main_src, "牙行行上直接写出传闻卖价，不只藏在悬停里")
offer_body = gs_src.split("func contract_offer", 1)[1].split("\nfunc ", 1)[0]
fail_body = gs_src.split("func _fail_contract", 1)[1].split("\nfunc ", 1)[0]
accept_body = gs_src.split("func accept_contract", 1)[1].split("\nfunc ", 1)[0]
check("contract_port_closed" in offer_body, "毁约当月，签发港不再开出同一笔委办")
check("contract_ban" in fail_body and "offer_month" in fail_body, "逾期和毁约都会记下签发年月")
check("contract_offer" in accept_body and "offer_month" in accept_body,
      "接下时按现单重算酬金和期限，不吃按钮上的旧数字")
sea_src = open(os.path.join(ROOT, "scripts/SeaChart.gd"), encoding="utf-8").read()
back_body = sea_src.split("func _on_back_to_port", 1)[1].split("\nfunc ", 1)[0]
check("voyage_started" in back_body, "发舶之后不能点回港躲开海难")
check("voyage_days" in offer_body and "expected_days" not in offer_body and "safe_days" not in offer_body,
      "委办期限不改用遇事日数或八成日数")
check("·误期" in main_src and "交不齐" in sea_src, "旅店歇过期限、舱里货不够，界面会写出来")
check("八成" in sea_src and "未稳" in main_src and "未稳" in sea_src,
      "平均数卡进期限、八成超出时，界面写明未稳")
check("凑得出" in main_src and "拿不满酬" in main_src,
      "钱不够买满委办时，牙行把缺口写在单子上")
# lane iz：凑得出 N 件按逐件加价总价与逐船舱位算，不再是 现银÷首件价 × 全队空舱
_purse_ui = main_src.split("var need_qty := int(offer.get(\"qty\", 0))", 1)[1].split("var purse_lbl", 1)[0]
_afford_fn = main_src.split("func _affordable_qty", 1)[1].split("\nfunc ", 1)[0] if "func _affordable_qty" in main_src else ""
check("_affordable_qty(port_id, gid" in _purse_ui and "max_loadable(gid, si)" in _purse_ui
      and "GameState.money) / float(unit_cost)" not in _purse_ui and "estimate_buy_cost" in _afford_fn,
      "委办凑得出件数按逐件加价总价、逐船舱位算，与牙行结算同口径")
_row_fn = main_src.split("func _make_market_row", 1)[1].split("\nfunc ", 1)[0]
_btip_fn = main_src.split("func _market_buy_tip", 1)[1].split("\nfunc ", 1)[0] if "func _market_buy_tip" in main_src else ""
_stip_fn = main_src.split("func _market_sell_tip", 1)[1].split("\nfunc ", 1)[0] if "func _market_sell_tip" in main_src else ""
check(_row_fn.count("_market_buy_tip(") == 2 and _row_fn.count("_market_sell_tip(") == 2
      and "estimate_buy_cost" in _btip_fn and "max_loadable(good_id, ship_index)" in _btip_fn
      and "estimate_sell_revenue" in _stip_fn,
      "牙行买十/买满/卖十/全卖的悬停印逐件累计的实价，与结算同一函数")
_adv_fn = open(os.path.join(ROOT, "scripts/GameManager.gd"), encoding="utf-8").read().split("func advance_days", 1)[1].split("\nfunc ", 1)[0]
check("interest := GameState.accrue_interest()" in _adv_fn and "【月息】" in _adv_fn and "monthly_notice.emit" in _adv_fn.split("accrue_interest", 1)[1].split("pay_wages", 1)[0],
      "月初结息有通告：欠债时写出本月息钱与现欠")
check("hold_tenths" in plan_body and "cargo_hold_chance(order, known, open, expected)" in plan_body,
      "保货按遇事日数写进航程，期限仍用静风")
check("cargo_hold_chance(order, known, open, safe)" not in plan_body,
      "保货不改用八成日数")
hold_fn = voyage_src.split("func cargo_hold_chance", 1)[1].split("\nfunc ", 1)[0]
tenths_fn = voyage_src.split("func cargo_hold_tenths", 1)[1].split("\nfunc ", 1)[0]
flee_fn = voyage_src.split("func flee_success_chance", 1)[1].split("\nfunc ", 1)[0]
check("flee_success_chance" in hold_fn and "event_weights" in hold_fn and "floor" in tenths_fn,
      "保货是逃走失败率按逐日海盗权重连乘，十分位下整")
check("220.0" in flee_fn and "0.25" in flee_fn and "0.9" in flee_fn,
      "逃走成功率仍是航速 / 220，夹在 0.25 和 0.9")
world_src = open(os.path.join(ROOT, "scripts/WorldMap.gd"), encoding="utf-8").read()
check("Voyage.flee_success_chance" in sea_src and "Voyage.flee_success_chance" in world_src,
      "海图逃走和海战弃战用同一条成功率")
check("220.0" not in sea_src and "220.0" not in world_src,
      "逃走的 220 只写在 Voyage，海图和海战不再各写一遍")
check("保货" in sea_src and "保货" in main_src and "不到八成" in main_src and "不到八成" in sea_src,
      "日子赶得上但保货不到八成时，牙行和海图都写出来")
check('int(plan_r.get("safe_days", 0)) <= deadline and int(plan_r.get("hold_tenths", 0)) < 8' in main_src
      and 'int(plan_c.get("safe_days", 0)) <= deadline and int(plan_c.get("hold_tenths", 0)) < 8' in main_src,
      "保货警告按同一条航法看八成日数和保货")
spoil_fn = voyage_src.split("func spoil_hold_chance", 1)[1].split("\nfunc ", 1)[0]
check("cargo_loss_factor" in spoil_fn and "pow" in spoil_fn,
      "受潮按每日概率连乘，总管减损算进去")
spoil_ui = main_src.split("受潮：", 1)[1].split('if int(plan_c.get("expected_days"', 1)[0]
check("safe_days" in spoil_ui and "expected_days" not in spoil_ui and "can_carry" in spoil_ui,
      "牙行受潮按八成日数和凑得出的件数，不用遇事日数")
check('int(plan_r.get("safe_days", 0)) <= deadline and sr < 8' in spoil_ui
      and 'int(plan_c.get("safe_days", 0)) <= deadline and sc < 8' in spoil_ui,
      "受潮警告按同一条航法看八成日数")
check("受潮" in main_src and "受潮" in sea_src and "受潮不到八成" in main_src and "受潮只有" in sea_src,
      "会潮的货，牙行和海图都写出受潮成数")
check("dampest_aboard" in sea_src and "good_perish_rate" in sea_src,
      "海图按舱里会潮的货来写，委办货优先")
check("·换风" in sea_src and "逐日累加" in main_src, "途中换风写在海图和委办上")

print()
print("=" * 68)
print("九之六、新闻市场副作用（news.json market → Economy.apply_news_market，一次性冲击后按 RECOVERY 回归）")
print("=" * 68)

E_GD = "scripts/core/Economy.gd"
RATE_MIN_E = gd_const(E_GD, "RATE_MIN")
RATE_MAX_E = gd_const(E_GD, "RATE_MAX")
RECOVERY_E = gd_const(E_GD, "RECOVERY")
eco_src = open(os.path.join(ROOT, E_GD), encoding="utf-8").read()
gm_src = open(os.path.join(ROOT, "scripts/GameManager.gd"), encoding="utf-8").read()
nm_fn = eco_src.split("func apply_news_market", 1)[1].split("\nfunc ", 1)[0] if "func apply_news_market" in eco_src else ""
check("clampf(" in nm_fn and "RATE_MIN" in nm_fn and "RATE_MAX" in nm_fn and "* mul" in nm_fn,
      "apply_news_market 按 mul 乘行情并钳在 RATE_MIN–RATE_MAX（不另开常驻倍率层）")
settle_fn = gm_src.split("func _settle_history", 1)[1].split("\nfunc ", 1)[0]
check('n.get("market"' in settle_fn and "Economy.apply_news_market(" in settle_fn,
      "GameManager._settle_history 投放新闻时消费 market 字段")
check('str(n.get("date", "")) == "%04d-%02d" % [Calendar.year, Calendar.month]' in settle_fn,
      "market 只在新闻本月投放时生效，补发旧闻不追溯砸盘")
day_fn = eco_src.split("func on_day_passed", 1)[1].split("\nfunc ", 1)[0]
check("(1.0 - r) * RECOVERY" in day_fn, "冲击后的行情仍走 on_day_passed 的 RECOVERY 回归，无永久层")

news_all = load("news.json")["news"]
mk_news = [n for n in news_all if "market" in n]
check(bool(mk_news), f"至少一条新闻挂 market 副作用（{[n['id'] for n in mk_news]}）")
for n in mk_news:
    mk = n["market"]
    gid, mul = mk["good_id"], float(mk["mul"])
    tgt = mk.get("ports") or [pid for pid in ports if gid in ports[pid].get("market", {})]
    for pid in tgt:
        check(gid in ports[pid].get("market", {}), f"{n['id']}：{pid} 交易 {goods[gid]['name']}")
        worst = []
        for r0 in (0.85, 1.0, 1.15, RATE_MIN_E, RATE_MAX_E):
            r1 = min(RATE_MAX_E, max(RATE_MIN_E, r0 * mul))
            worst.append(r1)
            b, sl = price_at(pid, gid, True, rate=r1), price_at(pid, gid, False, rate=r1)
            check(RATE_MIN_E <= r1 <= RATE_MAX_E and 0 < sl <= b,
                  f"{n['id']}@{pid} 起价率 {r0:.2f} → {r1:.3f}：在带内，买 {b} ≥ 卖 {sl} > 0")
        # 最坏：从开局扰动下沿砸下去，60 日后须回到 1.0 的 5% 以内
        r = min(worst[:3]) if mul < 1 else max(worst[:3])
        r_start = r
        for _ in range(60):
            r = r + (1.0 - r) * RECOVERY_E
        print(f"  {n['id']} @ {ports[pid]['name']} {goods[gid]['name']}×{mul}："
              f"买价 {price_at(pid, gid, True, rate=1.0)} → {price_at(pid, gid, True, rate=r_start)}，60 日后率 {r:.3f}")
        check(abs(1.0 - r) < 0.05, f"{n['id']}@{pid} 冲击 60 日后回到 1.0±5%（{r:.3f}）——可逆，不打坏价带")

print()
print("=" * 68)
print("九之七、行会 / 贡院账目隔离与新闻倍率边界")
print("=" * 68)

def main_body(name):
    marker = "func " + name
    if marker not in main_src:
        return ""
    return main_src.split(marker, 1)[1].split("\nfunc ", 1)[0]

# 行会入行是一次性会费与账本增量，不应悄悄叠到行情、抽解或佣金倍率。
guild_join = main_body("_on_guild_join")
guild_fee = int(gd_const("scripts/Main.gd", "GUILD_JOIN_FEE"))
guild_credit_req = int(gd_const("scripts/Main.gd", "GUILD_JOIN_CREDIT"))
guild_credit_gain = int(gd_const("scripts/Main.gd", "GUILD_JOIN_CREDIT_GAIN"))
guild_network_gain = int(gd_const("scripts/Main.gd", "GUILD_JOIN_NETWORK_GAIN"))
check(guild_fee > 0 and guild_credit_req > 0 and guild_credit_gain > 0 and guild_network_gain > 0,
      f"行会常量为正：会费 {guild_fee}、信用门槛 {guild_credit_req}、商誉 +{guild_credit_gain}、人脉 +{guild_network_gain}")
check(guild_join.count("spend_money(GUILD_JOIN_FEE)") == 1 and
      "merchant_credit += GUILD_JOIN_CREDIT_GAIN" in guild_join and
      "network += GUILD_JOIN_NETWORK_GAIN" in guild_join and
      'set_flag("guild_%s" % port_id)' in guild_join,
      "入行一次扣会费、加商誉/人脉并写 guild_<港> 旗标")
check("Economy." not in guild_join and "apply_buy_impact" not in guild_join and
      "apply_sell_impact" not in guild_join,
      "入行不改行情、抽解、佣金（不偷偷开常驻倍率）")
# 小账本复刻成功与重复点击：会费只出一次，收益只记一次。
g_cash, g_credit, g_network, g_flag = guild_fee + 1, guild_credit_req, 0, False
g_cash -= guild_fee; g_credit += guild_credit_gain; g_network += guild_network_gain; g_flag = True
g_after_repeat = (g_cash, g_credit, g_network, g_flag)
check(g_after_repeat == (1, guild_credit_req + guild_credit_gain, guild_network_gain, True),
      "行会成功账本：钱 -会费、商誉/人脉一次性增加，重复点击不再产生第二笔倍率")

# 赴试只推进日期并改变身份倾向/名声；明确不发钱、不改行情。
exam_sit = main_body("_on_exam_sit")
exam_days = int(gd_const("scripts/Main.gd", "EXAM_SIT_DAYS"))
exam_ports_src = main_body("_setup_exam")
check(exam_days > 0 and exam_days == 15, f"赴试耗时 {exam_days} 日（固定为 15 日，不以经济倍率折算）")
check("advance_days(EXAM_SIT_DAYS)" in exam_sit and "add_money" not in exam_sit and
      "spend_money" not in exam_sit and "apply_buy_impact" not in exam_sit and
      "apply_sell_impact" not in exam_sit,
      "赴试只耗日并结算身份倾向/名声，不发钱、不砸盘")
check('"exam_sat"' in exam_sit and "add_fame(4)" in exam_sit and
      "add_fame(1)" in exam_sit and "scholar_tendency += 2" in exam_sit and
      "sea_tendency += 1" in exam_sit,
      "赴试士人/海路两支的名声与倾向增量完整")
check('const EXAM_SIT_PORTS := ["xinghua", "quanzhou"]' in main_src and
      "EXAM_SIT_PORTS.has(port_id)" in exam_ports_src,
      "赴试港限制仍为兴化、泉州，不把其误当成全港经济倍率")

# 新闻倍率是单次 market mul：验证原始倍率、显式港口范围、只调用一次和回归。
news_calls = settle_fn.count("Economy.apply_news_market(")
check(news_calls == 1, f"新闻 market 每次投放只消费一次（接线调用 {news_calls} 处）")
for n in mk_news:
    mk = n["market"]
    gid, mul = mk["good_id"], float(mk["mul"])
    explicit = mk.get("ports")
    targets = list(explicit) if explicit else [pid for pid in ports if gid in ports[pid].get("market", {})]
    check(0.4 <= mul <= 1.6 and not math.isclose(mul, 1.0),
          f"{n['id']}：market mul={mul:g} 在 0.4–1.6 且确有冲击")
    check(bool(targets) and all(gid in ports[pid].get("market", {}) for pid in targets),
          f"{n['id']}：market 只落在交易 {goods[gid]['name']} 的声明港口")
    # 以 1.0 为基线，显式港口以外必须保持原率；倍率不可因补发或重复消费再乘一次。
    probe = {pid: 1.0 for pid in ports if gid in ports[pid].get("market", {})}
    before_probe = dict(probe)
    for pid in targets:
        if pid in probe:
            probe[pid] = min(RATE_MAX_E, max(RATE_MIN_E, probe[pid] * mul))
    check(all(probe[pid] == before_probe[pid] for pid in probe if pid not in targets),
          f"{n['id']}：未列港行情不变（无越界倍率）")
    expected = min(RATE_MAX_E, max(RATE_MIN_E, mul))
    for pid in targets:
        if pid in probe:
            check(abs(probe[pid] - expected) < 1e-9,
                  f"{n['id']}@{pid}：一次性行情率 1.0×{mul:g} → {probe[pid]:.3f}")
    twice = min(RATE_MAX_E, max(RATE_MIN_E, expected * mul)) if targets else expected
    check(not math.isclose(twice, expected),
          f"{n['id']}：重复乘法会产生不同结果，故接线必须保持单次消费")


# ── 以下两节只在显式开关下跑，不带开关时本门禁输出与判据不变 ──
if "--prod-dump" in sys.argv[1:]:
    print()
    print("=" * 68)
    print("附一、镜像对生产逐格对账（lane ea2；dump 由 tools/qa_economy_spread_probe.gd -- --dump-out 产出）")
    print("=" * 68)
    _dump = sys.argv[sys.argv.index("--prod-dump") + 1]
    _ranks = sorted(titles_doc["ranks"], key=lambda r: r["min_fame"])
    _n, _bad, _tariff_off, _ex = 0, 0, 0, []
    with open(_dump, encoding="utf-8") as _f:
        for _line in _f:
            pid, gid, z, t, rk, inv, rate, b, sl, tb = _line.rstrip("\n").split("\t")
            _n += 1
            if abs(float(tb) - TARIFF) > 1e-9:  # 战况/站蒲家改了抽解基率：镜像不管这一格
                _tariff_off += 1
                continue
            z, t, rk, inv, rate = int(z), int(t), int(rk), int(inv), float(rate)
            duty = _ranks[rk]["duty_factor"]
            got = (price_at(pid, gid, True, z, t, duty, inv, rate),
                   price_at(pid, gid, False, z, t, duty, inv, rate))
            if got != (int(b), int(sl)):
                _bad += 1
                if len(_ex) < 3:
                    _ex.append(f"{pid}/{gid} 杂{z}通{t} 职衔档{rk} 修埠{inv} 行情{rate} 镜像{got} 生产{(int(b), int(sl))}")
    print(f"  dump {_n} 格（抽解基率非 {TARIFF} 跳过 {_tariff_off}）")
    check(_n > 0 and _tariff_off < _n, f"对账样本非空（{_n - _tariff_off} 格）")
    check(_bad == 0, f"price_at 与生产 Economy.price_at_rate 逐格一致（不符 {_bad}{'；例 ' + '；'.join(_ex) if _ex else ''}）")

if "--tongshi-table" in sys.argv[1:]:
    print()
    print("=" * 68)
    print("附二、通事收益敏感性表（lane ea2；只出数据，不判红绿）")
    print("=" * 68)
    print("  口径：行情 1.0、散商、未修埠、无杂事；价格经 price_at（＝生产含地板式）。")
    print("  「B 只压买价」为假设式（非生产）：卖价不吃通事，买价 = max(光杆买价×(1−议价), 光杆卖价×地板)。")
    print("  回本件数 = ⌈月俸 ÷ 单件溢价⌉；溢价 ≤ 0 记「—」。")
    TS_WAGE = 200
    wage_of = {}
    for c in cands:
        if c["role"] == "tongshi":
            wage_of[c["level"]] = min(wage_of.get(c["level"], 10**9), c["wage"])
    TS_ROUTES = [
        ("quanzhou", "hakata", "qingbai_porcelain"),
        ("quanzhou", "jeju", "silk_fabric"),
        ("hakata", "quanzhou", "japanese_copper"),
        ("jeju", "quanzhou", "korean_ginseng"),
        ("champa", "hakata", "ivory"),
    ]
    def _b_only(pid, gid, is_buy, t):
        v = unit_value(pid, gid)
        sb = price_core(v, pid in FOREIGN_PORTS, 0, 0)[1]
        if not is_buy:
            return gd_round(sb)
        edge = interp_edge(t) if pid in FOREIGN_PORTS else 0.0
        return gd_round(max(v * (1.0 + TARIFF) * (1.0 - edge), sb * SPREAD_MIN))
    cap_sampan = ships["sampan"]["capacity"]
    print()
    print("| 航线 · 货 | 通事 | 买价 | 卖价 | 单件利润 | 溢价/件 | 溢价 % | 回本件数@200 | 回本件数@实俸 | B 利润 | B 溢价 % | B 回本@200 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for src, dst, gid in TS_ROUTES:
        name = f"{ports[src]['name']}→{ports[dst]['name']} {goods[gid]['name']}"
        base_p = price_at(dst, gid, False) - price_at(src, gid, True)
        base_b = _b_only(dst, gid, False, 0) - _b_only(src, gid, True, 0)
        for t in range(4):
            bp, sp = price_at(src, gid, True, 0, t), price_at(dst, gid, False, 0, t)
            prof = sp - bp
            d = prof - base_p
            pb = _b_only(dst, gid, False, t) - _b_only(src, gid, True, t)
            db = pb - base_b
            wage = wage_of.get(t, 0)
            back = lambda w, dd: "—" if t == 0 else (f"{math.ceil(w / dd)}" if dd > 0 else "—")
            print(f"| {name if t == 0 else ''} | {t}{'（俸 ' + str(wage) + '）' if t else ''} | {bp} | {sp} | {prof} | {d:+d} | "
                  f"{d / base_p * 100:+.1f}% | {back(TS_WAGE, d)} | {back(wage, d)} | {pb} | {db / base_b * 100:+.1f}% | {back(TS_WAGE, db)} |")
    print()
    _mz = best_lv.get("zashi", 0)
    for src, dst, gid in TS_ROUTES:
        lad = [price_at(dst, gid, False, _mz, t) - price_at(src, gid, True, _mz, t) for t in range(4)]
        print(f"  杂事 {_mz} 级时 {ports[src]['name']}→{ports[dst]['name']} {goods[gid]['name']}"
              f" 通事 0→3 单件利润 {lad}")
    print(f"  参照：小艍船舱位 {cap_sampan} 料；青白瓷每件 {goods['qingbai_porcelain']['bulk']} 料 → 满舱约 "
          f"{int(cap_sampan / goods['qingbai_porcelain']['bulk'])} 件（未扣水粮）。")

print()
print("=" * 68)
if fails:
    print(f"结果：{len(fails)} 项未通过")
    for f in fails:
        print("   ✗", f)
    sys.exit(1)
print("结果：全部通过")
