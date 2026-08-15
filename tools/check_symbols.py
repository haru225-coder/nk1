#!/usr/bin/env python3
"""静态检查 GDScript：autoload 单例的跨文件引用是否都真实存在。
GDScript 是动态语言，Autoload.missing_method() 只有跑到那一行才报错。"""
import re, os, sys, collections

import pathlib
ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
SCRIPTS = os.path.join(ROOT, "scripts")

# autoload 名 -> 脚本路径（须与 project.godot 一致）
AUTOLOADS = {
    "GameManager": "scripts/GameManager.gd",
    "Calendar":    "scripts/core/Calendar.gd",
    "Economy":     "scripts/core/Economy.gd",
    "Fleet":       "scripts/core/Fleet.gd",
    "Crew":        "scripts/core/Crew.gd",
    "Voyage":      "scripts/core/Voyage.gd",
    "GameState":   "scripts/GameState.gd",
    "SaveLoad":    "scripts/core/SaveLoad.gd",
}

def parse_members(path):
    """返回该脚本定义的 func / var / const / signal / enum 名集合"""
    members, enums = set(), {}
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for m in re.finditer(r'^\s*func\s+([A-Za-z_]\w*)', src, re.M):
        members.add(m.group(1))
    for m in re.finditer(r'^\s*(?:@export\s+)?var\s+([A-Za-z_]\w*)', src, re.M):
        members.add(m.group(1))
    for m in re.finditer(r'^\s*const\s+([A-Za-z_]\w*)', src, re.M):
        members.add(m.group(1))
    for m in re.finditer(r'^\s*signal\s+([A-Za-z_]\w*)', src, re.M):
        members.add(m.group(1))
    for m in re.finditer(r'^\s*enum\s+([A-Za-z_]\w*)\s*\{([^}]*)\}', src, re.M | re.S):
        name, body = m.group(1), m.group(2)
        members.add(name)
        vals = {v.split("=")[0].strip() for v in body.split(",") if v.strip()}
        enums[name] = vals
    return members, enums, src

# 收集所有 autoload 的成员
defined, enum_map = {}, {}
for name, rel in AUTOLOADS.items():
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        print(f"  ✗ autoload 脚本不存在: {rel}")
        sys.exit(1)
    defined[name], enum_map[name], _ = parse_members(p)

# 校验 project.godot 的 autoload 与上表一致
with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
    pg = f.read()
declared = dict(re.findall(r'^(\w+)="\*(res://[^"]+)"', pg, re.M))
problems = []

print("=" * 68)
print("一、project.godot 的 autoload 注册")
print("=" * 68)
for name, rel in AUTOLOADS.items():
    want = "res://" + rel
    got = declared.get(name)
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {name:<12} {got or '(未注册)'}")
    if not ok:
        problems.append(f"autoload {name} 注册不符：期望 {want}，实际 {got}")

# autoload 顺序：GameManager 必须在依赖它的模块之前
order = [m.group(1) for m in re.finditer(r'^(\w+)="\*res://', pg, re.M)]
if "GameManager" in order:
    gm_idx = order.index("GameManager")
    for dep in ("Economy", "Fleet", "Voyage"):
        if dep in order and order.index(dep) < gm_idx:
            problems.append(f"{dep} 注册在 GameManager 之前，_ready 时数据尚未加载")
    print(f"\n  加载顺序: {' → '.join(order)}")
    print(f"  {'✓' if all(order.index(d) > gm_idx for d in ('Economy','Fleet','Voyage') if d in order) else '✗'}"
          f" GameManager 先于 Economy/Fleet/Voyage")

print()
print("=" * 68)
print("一之二、_ready 期间的 autoload 依赖顺序")
print("=" * 68)
print("  autoload 按注册顺序逐个 _ready；在 _ready 里碰排在自己后面的 autoload 会拿到 null。")

def func_bodies(src):
    """粗略切分出每个 func 的函数体（按缩进）"""
    out, cur, body = {}, None, []
    for ln in src.split("\n"):
        m = re.match(r'^func\s+([A-Za-z_]\w*)', ln)
        if m:
            if cur: out[cur] = "\n".join(body)
            cur, body = m.group(1), []
        elif cur is not None:
            if ln and not ln[0].isspace() and not ln.startswith(("#", ")")):
                out[cur] = "\n".join(body); cur, body = None, []
            else:
                body.append(ln)
    if cur: out[cur] = "\n".join(body)
    return out

order_idx = {name: i for i, name in enumerate(order)}
ready_problems = []
for name, rel in AUTOLOADS.items():
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        src = f.read()
    bodies = func_bodies(src)
    if "_ready" not in bodies:
        continue
    # 从 _ready 出发展开本地调用链，直到不动点——两层以上的间接依赖同样会崩
    seen_fn = {"_ready"}
    frontier = ["_ready"]
    while frontier:
        fn = frontier.pop()
        for local in re.findall(r'\b([a-z_]\w*)\s*\(', bodies.get(fn, "")):
            if local in bodies and local not in seen_fn:
                seen_fn.add(local)
                frontier.append(local)
    reach = "\n".join(bodies.get(fn, "") for fn in seen_fn)
    touched = {o for o in AUTOLOADS if o != name and re.search(rf'\b{o}\.', reach)}
    for t in touched:
        if order_idx.get(t, 99) > order_idx.get(name, 99):
            ready_problems.append(f"{name}._ready 触及 {t}，但 {t} 注册在其之后")
            print(f"  ✗ {name}._ready → {t}（{t} 排在后面，此时尚未就绪）")
        else:
            print(f"  ✓ {name}._ready → {t}（已就绪）")
if not ready_problems:
    print("  ✓ 无 _ready 期的逆序依赖")
problems.extend(ready_problems)

print()
print("=" * 68)
print("二、跨文件引用检查")
print("=" * 68)

# Godot 内置成员，出现在 autoload 上是合法的
BUILTIN = {
    "new", "free", "queue_free", "connect", "disconnect", "emit", "call",
    "get", "set", "has_method", "get_tree", "add_child", "name", "duplicate",
    "call_deferred", "is_connected", "get_children", "bind", "size", "keys",
}

miss_count = 0
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in sorted(files):
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as f:
            src = f.read()
        # 去掉注释行，避免文档里的示例被当成引用
        src_nc = "\n".join(re.sub(r'#.*$', '', ln) for ln in src.split("\n"))

        file_problems = []
        for auto, members in defined.items():
            # 跳过自身
            if AUTOLOADS[auto] == rel.replace(os.sep, "/"):
                continue
            for m in re.finditer(rf'\b{auto}\.([A-Za-z_]\w*)', src_nc):
                attr = m.group(1)
                if attr in members or attr in BUILTIN:
                    continue
                line = src_nc[:m.start()].count("\n") + 1
                file_problems.append((line, f"{auto}.{attr}"))

        # enum 成员引用 Voyage.EventKind.XXX
        for auto, enums in enum_map.items():
            for ename, evals in enums.items():
                for m in re.finditer(rf'\b{auto}\.{ename}\.([A-Za-z_]\w*)', src_nc):
                    if m.group(1) not in evals:
                        line = src_nc[:m.start()].count("\n") + 1
                        file_problems.append((line, f"{auto}.{ename}.{m.group(1)}"))

        if file_problems:
            print(f"\n  ✗ {rel}")
            for line, ref in sorted(set(file_problems)):
                print(f"      L{line}: {ref}  ← 未定义")
                miss_count += 1
                problems.append(f"{rel}:{line} {ref}")

if miss_count == 0:
    print("  ✓ 所有 autoload 成员引用均已定义")

print()
print("=" * 68)
print("二之二、emit 的信号是否都还存在")
print("=" * 68)
print("  删掉 signal 却漏了某处 emit，只有跑到那一行才炸。")
orphan_total = 0
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in sorted(files):
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dirpath, fn)
        with open(path, encoding="utf-8") as f:
            src = f.read()
        declared = set(re.findall(r'^\s*signal\s+([A-Za-z_]\w*)', src, re.M))
        # 前面带点的是跨对象 emit（Autoload.sig.emit），不归本文件管
        emitted = set(re.findall(r'(?<![.\w])([A-Za-z_]\w*)\.emit\s*\(', src))
        for o in sorted(emitted - declared):
            print(f"  ✗ {os.path.relpath(path, ROOT)}: {o}.emit() 但本文件无此 signal")
            problems.append(f"{os.path.relpath(path, ROOT)} emit 已删除的 {o}")
            orphan_total += 1
if orphan_total == 0:
    print("  ✓ 所有 emit 都有对应的 signal 声明")

print()
print("=" * 68)
print("三、缩进与括号一致性")
print("=" * 68)
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in sorted(files):
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        # GDScript 用 Tab 缩进；混入空格缩进会报错
        bad_indent = [i+1 for i, ln in enumerate(lines)
                      if ln.startswith(" ") and ln.strip() and not ln.lstrip().startswith("#")]
        if bad_indent:
            print(f"  ✗ {rel}: 第 {bad_indent[:5]} 行用空格缩进（GDScript 需 Tab）")
            problems.append(f"{rel} 空格缩进")
        src = "".join(lines)
        for op, cl, label in [("(", ")", "圆括号"), ("[", "]", "方括号"), ("{", "}", "花括号")]:
            # 粗略计数，字符串内的括号会有误差，仅作提示
            n_op = src.count(op)
            n_cl = src.count(cl)
            if n_op != n_cl:
                print(f"  ! {rel}: {label} 数量不等（{n_op} vs {n_cl}），请人工确认")
if not any("空格缩进" in p for p in problems):
    print("  ✓ 所有脚本使用 Tab 缩进")

print()
print("=" * 68)
print("四、场景文件引用的脚本是否存在")
print("=" * 68)
scenes_dir = os.path.join(ROOT, "scenes")
for fn in sorted(os.listdir(scenes_dir)):
    if not fn.endswith(".tscn"):
        continue
    with open(os.path.join(scenes_dir, fn), encoding="utf-8") as f:
        content = f.read()
    for m in re.finditer(r'path="(res://[^"]+\.gd)"', content):
        sp = os.path.join(ROOT, m.group(1).replace("res://", ""))
        if not os.path.exists(sp):
            print(f"  ✗ {fn} 引用了不存在的脚本 {m.group(1)}")
            problems.append(f"{fn} -> {m.group(1)} 缺失")

# 代码里 change_scene_to_file 的目标是否存在
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dirpath, fn)
        with open(path, encoding="utf-8") as f:
            src = f.read()
        for m in re.finditer(r'change_scene_to_file\("(res://[^"]+)"\)', src):
            tp = os.path.join(ROOT, m.group(1).replace("res://", ""))
            rel = os.path.relpath(path, ROOT)
            if not os.path.exists(tp):
                print(f"  ✗ {rel} 切换到不存在的场景 {m.group(1)}")
                problems.append(f"{rel} -> {m.group(1)} 缺失")
            else:
                print(f"  ✓ {rel} → {m.group(1)}")

print()
print("=" * 68)
print("五、Fleet.cargo 只读（分船装载的聚合 getter 禁止赋值）")
print("=" * 68)
print("  Fleet.cargo 已改为只读聚合 getter，数据源在 ships[i].cargo。")
print("  任何 Fleet.cargo = / Fleet.cargo[...] = / Fleet.cargo.xxx = 都会炸或静默无效。")

fleet_rel = AUTOLOADS["Fleet"].replace(os.sep, "/")
cargo_writes = []
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in sorted(files):
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if rel == fleet_rel:
            continue  # Fleet.gd 内部只走 ships[i]["cargo"]
        with open(path, encoding="utf-8") as f:
            src = f.read()
        src_nc = "\n".join(re.sub(r'#.*$', '', ln) for ln in src.split("\n"))
        # 跳过链式访问片段（[..] / .ident），再看是否落到赋值符
        for m in re.finditer(r'\bFleet\.cargo', src_nc):
            pos = m.end()
            while True:
                seg = re.match(r'\s*(\[[^\]]*\]|\.[A-Za-z_]\w*)', src_nc[pos:])
                if not seg:
                    break
                pos += seg.end()
            stripped = src_nc[pos:].lstrip()
            if stripped.startswith("=") and not stripped.startswith(("==", "=>")):
                line = src_nc[:m.start()].count("\n") + 1
                cargo_writes.append((rel, line))

if not cargo_writes:
    print("  ✓ 全 scripts 无 Fleet.cargo 写入")
else:
    for rel, line in sorted(set(cargo_writes)):
        print(f"  ✗ {rel}:L{line} 对 Fleet.cargo 赋值——只读 getter，请改用 add_cargo/remove_cargo")
        problems.append(f"{rel}:{line} Fleet.cargo 只读被违例")

# add_ship 必须为每艘新船初始化独立货舱
with open(os.path.join(ROOT, AUTOLOADS["Fleet"]), encoding="utf-8") as f:
    fleet_src = f.read()
add_ship_body = func_bodies(fleet_src).get("add_ship", "")
if '"cargo"' in add_ship_body:
    print("  ✓ Fleet.add_ship 的船 dict 含独立 cargo 货舱")
else:
    print('  ✗ Fleet.add_ship 的船 dict 缺少 "cargo": {} —— 新船没有独立货舱')
    problems.append("Fleet.add_ship 缺少 cargo 字段")

# 分船船员配置：hire_crew 带 ship_index 默认参数 + 单船 crew 接口契约
print()
print("=" * 68)
print("五之二、分船船员配置契约")
print("=" * 68)
hire_sig = re.search(r'func hire_crew\(([^)]*)\)', fleet_src)
if hire_sig and "ship_index" in hire_sig.group(1):
    print("  ✓ Fleet.hire_crew 带 ship_index 默认参数（-1 聚合 / >=0 指定船）")
else:
    print("  ✗ Fleet.hire_crew 缺少 ship_index 参数")
    problems.append("Fleet.hire_crew 缺少 ship_index")
for f in ("ship_crew", "ship_crew_min", "ship_crew_max", "ship_crew_room",
          "crew_shortfall", "crew_to_min_needed", "hire_to_min"):
    if f in defined["Fleet"]:
        print(f"  ✓ Fleet.{f} 已定义")
    else:
        print(f"  ✗ Fleet.{f} 未定义")
        problems.append(f"Fleet.{f} 未定义")

print()
print("=" * 68)
print("五之三、船体改装契约")
print("=" * 68)
print("  改装：sail_level/armor_level 字段已就绪，须有完整的升级 API 与消费方。")

upgrade_funcs = ("upgrade_sail", "upgrade_armor", "sail_level", "armor_level",
                 "upgrade_cost", "is_sail_max", "is_armor_max",
                 "armor_damage_reduction", "fleet_armor_level")
for f in upgrade_funcs:
    if f in defined["Fleet"]:
        print(f"  ✓ Fleet.{f} 已定义")
    else:
        print(f"  ✗ Fleet.{f} 未定义")
        problems.append(f"Fleet.{f} 未定义")

for c in ("SAIL_LEVEL_MAX", "ARMOR_LEVEL_MAX", "UPGRADE_BASE_RATIO"):
    if c in defined["Fleet"]:
        print(f"  ✓ Fleet.{c} 常量已定义")
    else:
        print(f"  ✗ Fleet.{c} 常量未定义")
        problems.append(f"Fleet.{c} 未定义")

main_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Main.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                main_src = f.read()
if re.search(r'^func\s+_on_upgrade\b', main_src, re.M):
    print("  ✓ Main._on_upgrade 已定义（船屋升级按钮 connect 目标）")
else:
    print("  ✗ Main._on_upgrade 未定义")
    problems.append("Main._on_upgrade 未定义")

# armor 消费方：风暴与海盗船体伤都须经 armor_damage_reduction
voyage_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Voyage.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                voyage_src = f.read()
if "armor_damage_reduction" in voyage_src:
    print("  ✓ Voyage 风暴伤害已乘 armor_damage_reduction")
else:
    print("  ✗ Voyage 风暴伤害未乘 armor_damage_reduction——甲等级无消费点")
    problems.append("Voyage 风暴未消费 armor")

seachart_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "SeaChart.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                seachart_src = f.read()
uses_in_power = "fleet_armor_level" in seachart_src
uses_in_dmg = seachart_src.count("armor_damage_reduction") >= 1
if uses_in_power:
    print("  ✓ SeaChart 战力已计入 fleet_armor_level")
else:
    print("  ✗ SeaChart 战力未计入 fleet_armor_level")
    problems.append("SeaChart 战力未计入 armor")
if uses_in_dmg:
    print("  ✓ SeaChart 海盗船体伤已乘 armor_damage_reduction（P4-1 起结算不补扣耐久，保底 flee 仍乘）")
else:
    print(f"  ✗ SeaChart armor_damage_reduction 使用次数不足（期望 ≥1，实际 {seachart_src.count('armor_damage_reduction')}）")
    problems.append("SeaChart 海盗伤害未消费 armor")

# 升级 API 满级防御：upgrade_* 应返回 bool 且只在非满级时改写等级
for f in ("upgrade_sail", "upgrade_armor"):
    body = func_bodies(fleet_src).get(f, "")
    if "return false" in body and "return true" in body:
        print(f"  ✓ Fleet.{f} 有满级返回 false 的守卫")
    else:
        print(f"  ✗ Fleet.{f} 缺少满级守卫（应满级返回 false）")
        problems.append(f"Fleet.{f} 无满级守卫")

print()
print("=" * 68)
print("六、海战契约（P4-1：WorldMap 战斗接入）")
print("=" * 68)
print("  add_child 叠加方案：SeaChart 保留航行状态，WorldMap 战斗专用化。")

# 读取相关脚本源码
wm_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "WorldMap.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                wm_src = f.read()
ship_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Ship.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                ship_src = f.read()
minimap_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Minimap.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                minimap_src = f.read()
pirate_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "PirateShip.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                pirate_src = f.read()
cannonball_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "Cannonball.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                cannonball_src = f.read()

# 1. GameManager.pending_battle 上下文
if "pending_battle" in defined["GameManager"]:
    print("  ✓ GameManager.pending_battle 已声明（海战上下文）")
else:
    print("  ✗ GameManager.pending_battle 未声明")
    problems.append("GameManager.pending_battle 未声明")

# 2. SeaChart 接入点 + WorldMap preload
for f in ("_enter_battle", "_on_battle_result"):
    if re.search(rf'^func\s+{f}\b', seachart_src, re.M):
        print(f"  ✓ SeaChart.{f} 已定义")
    else:
        print(f"  ✗ SeaChart.{f} 未定义")
        problems.append(f"SeaChart.{f} 未定义")
if "WorldMap.tscn" in seachart_src:
    print("  ✓ SeaChart preload WorldMap.tscn（叠加进入战斗）")
else:
    print("  ✗ SeaChart 未 preload WorldMap.tscn")
    problems.append("SeaChart 未 preload WorldMap.tscn")

# 3. WorldMap 战斗核心
wm_need = ("combat_mode", "_setup_combat", "_spawn_enemy", "_battle_exit",
           "_battle_player_sunk", "_unhandled_input", "_enemies_alive")
wm_members = set(re.findall(r'^func\s+([A-Za-z_]\w*)', wm_src, re.M))
wm_vars = set(re.findall(r'^\s*var\s+([A-Za-z_]\w*)', wm_src, re.M))
for f in wm_need:
    if f in wm_members or f in wm_vars:
        print(f"  ✓ WorldMap.{f} 已定义")
    else:
        print(f"  ✗ WorldMap.{f} 未定义")
        problems.append(f"WorldMap.{f} 未定义")
if "signal battle_finished" in wm_src:
    print("  ✓ WorldMap.battle_finished 信号已声明")
else:
    print("  ✗ WorldMap.battle_finished 信号未声明")
    problems.append("WorldMap.battle_finished 信号未声明")

# 4. Ship._sink_ship 战斗守卫
if "pending_battle" in ship_src and "_battle_player_sunk" in ship_src:
    print("  ✓ Ship._sink_ship 含战斗守卫（战斗期不切场景）")
else:
    print("  ✗ Ship._sink_ship 缺少战斗守卫")
    problems.append("Ship._sink_ship 缺少战斗守卫")

# 5. Minimap 不再依赖 current_scene（add_child 方案必需）——只查非注释行
minimap_nc = "\n".join(re.sub(r'#.*$', '', ln) for ln in minimap_src.split("\n"))
if "current_scene" in minimap_nc:
    print("  ✗ Minimap 仍用 get_tree().current_scene——add_child 方案下会解析到 SeaChart")
    problems.append("Minimap 仍依赖 current_scene")
else:
    print("  ✓ Minimap 已改用父链查找（add_child 兼容）")

# 6. WorldMap 战斗模式：禁停靠 + 禁自动刷怪
if "PROCESS_MODE_DISABLED" in wm_src:
    print("  ✓ WorldMap 战斗模式禁用 Ports（停靠出口关闭）")
else:
    print("  ✗ WorldMap 未禁用 Ports（战斗可误停靠）")
    problems.append("WorldMap 未禁用 Ports")
if "combat_mode" in wm_src and "_process_spawns" in wm_src:
    print("  ✓ WorldMap 战斗模式短路自动刷怪")
else:
    print("  ✗ WorldMap 未短路自动刷怪")
    problems.append("WorldMap 未短路自动刷怪")

# 7. PirateShip.drops_loot 开关
if "drops_loot" in pirate_src and "if drops_loot" in pirate_src:
    print("  ✓ PirateShip.drops_loot 开关已定义（战斗不掉宝箱）")
else:
    print("  ✗ PirateShip.drops_loot 开关缺失")
    problems.append("PirateShip.drops_loot 缺失")

print()
print("=" * 68)
print("七、海战契约（P4-2：接舷/白刃/夺船并入舰队）")
print("=" * 68)
print("  白刃按 水手数 × 士气 × 将领武力 判定；胜方夺船并入舰队。")

# 1. GameState.martial 主角武力（白刃将领武力数据源）
if "martial" in defined.get("GameState", set()):
    print("  ✓ GameState.martial 已声明（主角武力，白刃输入）")
else:
    print("  ✗ GameState.martial 未声明")
    problems.append("GameState.martial 未声明")

# 2. Fleet.captain_power / lose_crew_random
for f in ("captain_power", "lose_crew_random"):
    if f in defined.get("Fleet", set()):
        print(f"  ✓ Fleet.{f} 已定义")
    else:
        print(f"  ✗ Fleet.{f} 未定义")
        problems.append(f"Fleet.{f} 未定义")

# 3. PirateShip 接舷/白刃状态与战力
for f in ("grappled", "ship_type", "ship_name", "crew", "enemy_morale", "captain_force", "combat_strength"):
    if f in set(re.findall(r'^\s*(?:var|func)\s+([A-Za-z_]\w*)', pirate_src, re.M)):
        print(f"  ✓ PirateShip.{f} 已定义")
    else:
        print(f"  ✗ PirateShip.{f} 未定义")
        problems.append(f"PirateShip.{f} 未定义")

# 4. WorldMap 接舷/白刃
wm_need4 = ("BOARD_DISTANCE", "boarding", "boarding_target", "_board_enemy",
            "_nearest_enemy", "_boarding_target_valid", "_show_combat_notice")
wm_all = wm_vars | wm_members | set(re.findall(r'^const\s+([A-Za-z_]\w*)', wm_src, re.M))
for f in wm_need4:
    if f in wm_all:
        print(f"  ✓ WorldMap.{f} 已定义")
    else:
        print(f"  ✗ WorldMap.{f} 未定义")
        problems.append(f"WorldMap.{f} 未定义")

# 5. Ship 白刃禁炮击
if "_can_fire" in ship_src and "boarding" in ship_src:
    print("  ✓ Ship._can_fire 已定义（白刃阶段禁炮击）")
else:
    print("  ✗ Ship._can_fire 缺失（白刃禁炮击）")
    problems.append("Ship._can_fire 缺失")

# 6. 主角武力数据源
with open(os.path.join(ROOT, "data", "npcs.json"), encoding="utf-8") as f:
    npc_src = f.read()
if '"force"' in npc_src and '"chen_wenlong"' in npc_src:
    print("  ✓ npcs.json 主角陈子龙含 force 字段（武力数据源）")
else:
    print("  ✗ npcs.json 主角缺 force 字段")
    problems.append("npcs.json 主角缺 force")

# 7. GameState 存档序列化含 martial
gs_src = ""
for dirpath, _, files in os.walk(SCRIPTS):
    for fn in files:
        if fn == "GameState.gd":
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                gs_src = f.read()
if '"martial"' in gs_src:
    print("  ✓ GameState.to_dict/from_dict 含 martial 存档字段")
else:
    print("  ✗ GameState 存档缺 martial")
    problems.append("GameState 存档缺 martial")

print()
print("=" * 68)
print("八、海战契约（P4-3：Cannonball 弹数挂炮位 + 伤害乘甲）")
print("=" * 68)
print("  玩家齐射弹数挂钩旗舰 cannon_slots；敌船弹数按 scale 缩放；玩家船受击乘甲。")

# 1. Ship：不再写死 range(3) 齐射，且引用 cannon_slots
if "cannon_slots" in ship_src and "range(3)" not in ship_src:
    print("  ✓ Ship 齐射弹数已挂钩 cannon_slots（无 range(3) 写死）")
else:
    print("  ✗ Ship 齐射弹数未挂钩 cannon_slots 或仍写死 range(3)")
    problems.append("Ship 齐射未挂 cannon_slots")

# 2. PirateShip：声明 cannon_count 字段，且 _process_firing 用 range(cannon_count)
if "cannon_count" in pirate_src and "range(cannon_count)" in pirate_src:
    print("  ✓ PirateShip 声明 cannon_count 且 _process_firing 用 range(cannon_count)")
else:
    print("  ✗ PirateShip 缺 cannon_count 字段或未用 range(cannon_count)")
    problems.append("PirateShip 弹数未挂 cannon_count")

# 3. WorldMap：_spawn_enemy 写入 cannon_count
if "cannon_count" in wm_src:
    print("  ✓ WorldMap._spawn_enemy 写入 cannon_count")
else:
    print("  ✗ WorldMap 未写入 cannon_count")
    problems.append("WorldMap 未写 cannon_count")

# 4. Cannonball：引用 armor_damage_reduction（玩家船受击乘甲）
if "armor_damage_reduction" in cannonball_src:
    print("  ✓ Cannonball 伤害已乘 armor_damage_reduction")
else:
    print("  ✗ Cannonball 未引用 armor_damage_reduction——甲等级无实时消费点")
    problems.append("Cannonball 未乘 armor")

print()
print("=" * 68)
if problems:
    print(f"结果：{len(problems)} 项问题")
    for p in problems:
        print("   ✗", p)
    sys.exit(1)
print("结果：全部通过")
