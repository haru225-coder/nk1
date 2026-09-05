#!/usr/bin/env python3
"""终局数值模拟：窗口宽度、守城胜率、崖山门槛、身份判定。

simulate_run.py 验的是 1255–1256 的经济闭环；本脚本验的是 1268 之后的历史压力段——
玩家此时通常已很富，所以「花钱买过关」是这一段最大的失衡风险。
不跑引擎，直接复刻 GDScript 里的公式；公式改了这里必须同步改（门禁会比对常量）。
"""
import json, os, re, random, statistics, sys, pathlib

ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
random.seed(20260904)
FAIL = []


def load(n):
    with open(os.path.join(ROOT, "data", n), encoding="utf-8") as f:
        return json.load(f)


def src(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def check(cond, msg):
    print(("  \u2713 " if cond else "  \u2717 ") + msg)
    if not cond:
        FAIL.append(msg)


gs = src("scripts/GameState.gd")
main = src("scripts/Main.gd")
ports = {p["id"]: p for p in load("ports.json")["ports"]}
ships = {s["id"]: s for s in load("ships.json")["ships"]}
news = load("news.json")["news"]


def const(name, source=gs, cast=int):
    m = re.search(r"const %s := ([0-9.]+)" % name, source)
    assert m, "找不到常量 " + name
    return cast(m.group(1))


ROUNDS_MAX = const("SIEGE_ROUNDS_MAX")
TROOP_COST = const("SIEGE_TROOP_COST")
GRAIN_PER_ROUND = const("SIEGE_GRAIN_PER_ROUND")

print("=" * 70)
print("终局数值模拟（1268–1285）")
print("=" * 70)

# ── 一、身份判定 ───────────────────────────────────────
print("\n  ── 1268 殿试：身份判定 ──")


def resolve(scholar, sea, hometown, land_first=True):
    if hometown > scholar and hometown > sea:
        return "hometown"
    if scholar > sea or (scholar == sea and land_first):
        return "scholar"
    return "merchant"


cases = [
    (7, 3, 0, True, "scholar"), (3, 7, 0, True, "merchant"),
    (4, 4, 0, True, "scholar"), (4, 4, 0, False, "merchant"),
    (4, 3, 9, True, "hometown"), (9, 3, 9, True, "scholar"),
]
for sc, se, ho, lf, want in cases:
    got = resolve(sc, se, ho, lf)
    check(got == want, f"倾向(士{sc}/海{se}/乡{ho}, 先{'陆' if lf else '海'}) → {got}")

# 乡土可达性：1268 前唯一写入点是玉湖陈宅跑腿 +3/次
m = re.search(r"hometown_tendency \+= (\d+)\n\t\t\tGameManager\.advance_days\((\d+)\)", main)
check(m is not None, "玉湖陈宅跑腿是 1268 前的乡土写入点")
if m:
    gain, days = int(m.group(1)), int(m.group(2))
    # 序章最多给 4 点士人或海路；要压过需 ≥5 点乡土
    need = (4 // gain) + 1
    print(f"    每次 +{gain} 乡土 / {days} 日；压过序章 4 点需 {need} 次（{need*days} 日）")
    check(need * days < 365 * 12, f"1255–1268 有 {365*12} 余日，{need*days} 日可达——乡土线非死分支")

# ── 二、守城胜率 ───────────────────────────────────────
print("\n  ── 守城：三阵胜率与「花钱买过关」风险 ──")


def troop_cap(fame):
    return min(1000, 300 + fame * 12)


def wall_cap():
    m2 = re.search(r"const SIEGE_WALL_MAX := (\d+)", gs)
    return int(m2.group(1)) if m2 else None


def power(troops, morale, shishou, wall):
    return troops * (morale / 100.0) * (1.5 if shishou else 1.0) + wall * 2.0


def enemy(rd):
    return random.uniform(600.0, 1400.0) * (1.0 + 0.25 * (rd - 1))


def run_siege(fame, money, shishou=True, trials=2000):
    """玩家把钱花到上限：兵满、粮足三阵、墙买到上限（若无上限则按钱买）"""
    cap = wall_cap()
    troops = troop_cap(fame)
    spent = troops * TROOP_COST + GRAIN_PER_ROUND * ROUNDS_MAX * 20
    left = max(0, money - spent)
    wall = 60 + (left // 15)
    if cap is not None:
        wall = min(wall, cap)
    wins = 0
    for _ in range(trials):
        morale = 55 + 10 + 12 + (8 if shishou else 0)  # 斩使 / 焚书 / 石手军
        ok = True
        for rd in range(1, ROUNDS_MAX + 1):
            if power(troops, morale, shishou, wall) >= enemy(rd):
                morale = min(100, morale + 8)
            else:
                morale = max(0, morale - 12)
                ok = False
        wins += 1 if ok else 0
    return wins / trials, troops, wall


WEALTH = 200000  # simulate_run 显示 1255 年内即可达数万；1276 年富商远超此数
cap = wall_cap()
print(f"    城墙上限：{cap if cap is not None else '无（可无限买）'}")
for fame in (10, 30, 60, 100):
    rate, troops, wall = run_siege(fame, WEALTH)
    print(f"    名声 {fame:3d}　兵 {troops:4d}　墙 {wall:5d}　三阵全胜率 {rate:5.1%}")

rate_rich, _, wall_rich = run_siege(60, WEALTH)
check(cap is not None, "城墙有上限——否则富商可用钱直接买穿守城")
check(rate_rich < 0.95, f"即便巨富，三阵全胜率 {rate_rich:.1%} < 95%（守城不是买过关）")

# 设计意图：名声定上限，钱把上限填满（倾家产募义兵）。
# 所以真正要验的不是「钱无关」，而是**填满之后边际收益归零**——再多的钱买不到任何东西。
enough = troop_cap(60) * TROOP_COST + GRAIN_PER_ROUND * ROUNDS_MAX * 20 + (cap or 200) * 15
rate_enough, _, _ = run_siege(60, enough)
rate_10x, _, _ = run_siege(60, enough * 10)
print(f"    填满名声上限需 {enough} 钱：{rate_enough:.1%}　十倍身家：{rate_10x:.1%}")
check(abs(rate_10x - rate_enough) < 0.05,
      f"填满后边际收益归零（{enough} 钱 {rate_enough:.1%} vs 十倍 {rate_10x:.1%}）")
# 钱不够填满时确实更弱——这是「倾家」的代价，不是失衡
rate_poor, _, _ = run_siege(60, 8000)
print(f"    只有 8000 钱（募不满兵）：{rate_poor:.1%}　—— 倾家产募义兵的代价，非失衡")
check(rate_poor < rate_enough, "钱不足以填满名声上限时确实更难守")

r_lo, _, _ = run_siege(10, WEALTH)
r_hi, _, _ = run_siege(100, WEALTH)
check(r_hi - r_lo > 0.2, f"名声决定兵额：名声10 {r_lo:.1%} → 名声100 {r_hi:.1%}（差 {r_hi-r_lo:.1%}）")
r_no, _, _ = run_siege(60, WEALTH, shishou=False)
check(rate_rich - r_no > 0.1, f"石手军显著（留 {rate_rich:.1%} / 遣 {r_no:.1%}）")

# ── 三、崖山砍缆门槛 ───────────────────────────────────
print("\n  ── 崖山：砍缆门槛 vs 实际航速 ──")
mt = re.search(r"Fleet\.fleet_speed\(\) > \(([0-9.]+) if known_here else ([0-9.]+)\)", main)
check(mt is not None, "崖山门槛在 Main.gd 可解析")
if mt:
    thr_known, thr_plain = float(mt.group(1)), float(mt.group(2))
    slowest = min(s["base_speed"] for s in ships.values())
    print(f"    门槛 {thr_plain}（借过船 {thr_known}）　最慢船 base_speed {slowest}")
    for morale in (100, 70, 55, 40, 20):
        mf = 0.6 + 0.4 * (morale / 100.0)
        spd = slowest * mf
        print(f"    士气 {morale:3d} → 航速 {spd:5.1f}　{'过' if spd > thr_plain else '砍缆晚了'}"
              f"　借过船：{'过' if spd > thr_known else '砍缆晚了'}")
    fail_morale = None
    for morale in range(100, -1, -1):
        if slowest * (0.6 + 0.4 * morale / 100.0) <= thr_plain:
            fail_morale = morale
            break
    check(fail_morale is not None and 20 < fail_morale < 60,
          f"失败门槛落在士气 {fail_morale}——只有被打残的船队才砍缆不及（不是人人失败，也不是人人过关）")
    check(thr_known < thr_plain, "借过船给张世杰确有优待")

# ── 四、结局窗口 ───────────────────────────────────────
print("\n  ── 结局窗口宽度与预告 ──")
xh = ports["xinghua"]["war"]
windows = {
    "忠肃（守城）": ("1276-11", "1276-12", "n_1276_10_xinghua_muster"),
    "岸上的根（涵江）": ("1277-02", "1277-03", "n_1277_01_chenzan_raises"),
    "海上宋鬼（崖山）": ("1279-01", "1279-03", "n_1278_12_yashan"),
}
by_id = {n["id"]: n for n in news}
for name, (start, end, hint_id) in windows.items():
    hint = by_id.get(hint_id)
    months = (int(end[:4]) - int(start[:4])) * 12 + int(end[5:]) - int(start[5:]) + 1
    hd = hint["date"] if hint else "—"
    print(f"    {name:16s} 窗口 {start}~{end}（{months} 个月）　预告 {hd}")
    check(hint is not None, f"{name} 有预告")
    if hint:
        check(hd < start, f"{name} 预告 {hd} 早于窗口 {start}")
        lead = (int(start[:4]) - int(hd[:4])) * 12 + int(start[5:]) - int(hd[5:])
        check(1 <= lead <= 6, f"{name} 预告提前 {lead} 个月（1–6 个月内，够反应又不至于忘）")
    check(months >= 2, f"{name} 窗口 {months} 个月 ≥ 2（一次远航来得及）")

check(xh.get("1277-02") == "loyal" and xh.get("1277-04") == "fallen",
      "兴化 1277-02~03 复城窗口存在（丙线的四十天）")

# ── 五、经济压力 ───────────────────────────────────────
print("\n  ── 守城开销 vs 1276 年身家 ──")
full = troop_cap(100) * TROOP_COST + GRAIN_PER_ROUND * ROUNDS_MAX * 20 + (cap or 200) * 15
print(f"    打满全套（兵 {troop_cap(100)}、粮 {GRAIN_PER_ROUND*ROUNDS_MAX}、墙至上限）约 {full} 钱")
check(full < WEALTH * 0.5, f"全套开销 {full} 钱不至于逼玩家卖船（占身家 {full/WEALTH:.0%}）")
check(full > 5000, f"全套开销 {full} 钱仍是一笔实数（倾家募义兵）")

print("\n" + "=" * 70)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print("结果：全部通过　—— 终局窗口够宽、胜负由名声与抉择而非钱决定")
