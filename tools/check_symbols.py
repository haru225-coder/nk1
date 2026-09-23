#!/usr/bin/env python3
"""静态检查 GDScript：autoload 单例的跨文件引用是否都真实存在。
GDScript 是动态语言，Autoload.missing_method() 只有跑到那一行才报错。"""
import json, re, os, sys, collections

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

# 6. WorldMap 战斗模式：禁停靠 + 已拆除自由航行刷怪
if "PROCESS_MODE_DISABLED" in wm_src:
    print("  ✓ WorldMap 战斗模式禁用 Ports（停靠出口关闭）")
else:
    print("  ✗ WorldMap 未禁用 Ports（战斗可误停靠）")
    problems.append("WorldMap 未禁用 Ports")
ecology_left = [name for name in ("_process_spawns", "seagull_tex", "whale_tex", "crate_scene")
                if name in wm_src]
if ecology_left:
    print(f"  ✗ WorldMap 仍留自由航行刷怪：{', '.join(ecology_left)}")
    problems.append("WorldMap 仍留自由航行刷怪")
else:
    print("  ✓ WorldMap 已拆除 crate / 海鸟 / 鲸影 / 野海盗刷怪")
if os.path.exists(os.path.join(ROOT, "scripts", "Crate.gd")) or os.path.exists(os.path.join(ROOT, "scenes", "Crate.tscn")):
    print("  ✗ Crate 场景仍在（拾取箱应为死内容，已裁定拆除）")
    problems.append("Crate 场景未拆除")
else:
    print("  ✓ Crate.gd / Crate.tscn 已拆除")
dead_bitmaps = [
    os.path.join(ROOT, "assets", name)
    for name in ("crate_barrel.png", "seagull.png", "whale_shadow.png")
    if os.path.exists(os.path.join(ROOT, "assets", name))
]
if dead_bitmaps:
    print("  ✗ 死生态位图仍在 assets/：%s" % ", ".join(os.path.basename(p) for p in dead_bitmaps))
    problems.append("死生态位图未拆除")
else:
    print("  ✓ crate / 海鸟 / 鲸影位图已从 assets/ 拆除")
wm_tscn = ""
with open(os.path.join(ROOT, "scenes", "WorldMap.tscn"), encoding="utf-8") as f:
    wm_tscn = f.read()
if "ocean_tex_1234" in wm_tscn:
    print("  ✗ WorldMap.tscn 仍用假 UID ocean_tex_1234")
    problems.append("WorldMap.tscn 海洋假 UID")
elif "uid://xnp7vjyfjnp1" in wm_tscn:
    print("  ✓ WorldMap.tscn 海洋贴图用导入 UID")
else:
    print("  ✗ WorldMap.tscn 未引用 ocean_water 导入 UID")
    problems.append("WorldMap.tscn 海洋 UID 未对齐")

# 7. PirateShip 不再掉拾取箱（赏金只走 SeaChart 结算）
if "drops_loot" in pirate_src or "Crate.tscn" in pirate_src:
    print("  ✗ PirateShip 仍引用拾取箱 / drops_loot")
    problems.append("PirateShip 仍掉拾取箱")
else:
    print("  ✓ PirateShip 击沉不再掉拾取箱")

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
print("九、P6 剧情旗标与结局契约")
print("=" * 68)
print("  旗标门槛、酒馆旧事、结局了结、剧情效果字段须有消费方。")

gs_need = (
    "flag_requirement_met", "choice_visible", "scene_unlocked",
    "try_resolve_ending", "has_ended", "pick_ending", "story_hooks_at",
    "ending_id", "network", "merchant_credit", "add_ledger_note",
)
for f in gs_need:
    if f in defined.get("GameState", set()):
        print(f"  ✓ GameState.{f} 已定义")
    else:
        print(f"  ✗ GameState.{f} 未定义")
        problems.append(f"GameState.{f} 未定义")

main_path = os.path.join(SCRIPTS, "Main.gd")
with open(main_path, encoding="utf-8") as f:
    main_src = f.read()
for needle, label in (
    ("choice_visible", "Main.show_choices 过滤不可见选项"),
    ("scene_unlocked", "Main.load_scene 守剧情门槛"),
    ("story_hooks_at", "Main 酒馆接旧事钩子"),
    ('"network"', "Main.apply_effects 写入人脉"),
    ('"merchant_credit"', "Main.apply_effects 写入海商信用"),
    ('"ledger_note"', "Main.apply_effects 写入边记"),
    ("try_advance_chapter", "Main 入港结算晋升/了结"),
):
    if needle in main_src:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}")
        problems.append(label)

crew_src = ""
with open(os.path.join(SCRIPTS, "core", "Crew.gd"), encoding="utf-8") as f:
    crew_src = f.read()
if "flag_requirement_met" in crew_src and "candidates_at" in crew_src:
    print("  ✓ Crew.candidates_at 守旗标门槛")
else:
    print("  ✗ Crew.candidates_at 未守旗标门槛")
    problems.append("Crew.candidates_at 未守旗标")

if '"ending_id"' in gs_src and '"network"' in gs_src and '"merchant_credit"' in gs_src:
    print("  ✓ GameState 存档含 ending_id / network / merchant_credit")
else:
    print("  ✗ GameState 存档缺结局或账本字段")
    problems.append("GameState 存档缺 P6 字段")

print()
print("=" * 68)
print("十、海图 / 海战点验入口")
print("=" * 68)
print("  HUD 写 WASD，工程默认 input map 只有方向键，操船必须另认字母键。")
ship_src = open(os.path.join(SCRIPTS, "Ship.gd"), encoding="utf-8").read()
chart_src = open(os.path.join(SCRIPTS, "SeaChart.gd"), encoding="utf-8").read()
if "KEY_W" in ship_src and "KEY_A" in ship_src and "KEY_D" in ship_src:
    print("  ✓ Ship 认 WASD 升降帆 / 操舵")
else:
    print("  ✗ Ship 未认 WASD——HUD 与手感对不上")
    problems.append("Ship 未认 WASD")
if "pirate_sighting" in defined.get("Voyage", set()):
    print("  ✓ Voyage.pirate_sighting 已定义")
else:
    print("  ✗ Voyage.pirate_sighting 未定义")
    problems.append("Voyage.pirate_sighting 未定义")
if "_debug_force_pirate" in chart_src and "KEY_F10" in chart_src:
    print("  ✓ SeaChart F10 可强行遭遇海盗")
else:
    print("  ✗ SeaChart 无 F10 海盗点验入口")
    problems.append("SeaChart 无 F10")
if "_debug_jump_port" in main_src and "KEY_F11" in main_src:
    print("  ✓ Main F11 可跳到泉州港")
    dbg = re.search(r"func _debug_jump_port.*?(?=\nfunc |\Z)", main_src, re.S)
    if dbg and "fuzhou" in dbg.group(0) and "xinghua" in dbg.group(0):
        print("  ✓ F11 点验链含福州通用港与兴化回访")
    else:
        print("  ✗ F11 不能跳到福州/兴化")
        problems.append("F11 点验链缺福州/兴化")
else:
    print("  ✗ Main 无 F11 进港点验入口")
    problems.append("Main 无 F11")
wm_src = open(os.path.join(SCRIPTS, "WorldMap.gd"), encoding="utf-8").read()
if 'child.get("hull_hp"' in wm_src or 'boarding_target.get("hull_hp"' in wm_src:
    print("  ✗ WorldMap 对 Node 用了两参数 get()——Godot 4.6 编不过")
    problems.append("WorldMap Node.get 两参数")
else:
    print("  ✓ WorldMap 不再对 Node 调用两参数 get()")
if "class_name PirateShip" in open(os.path.join(SCRIPTS, "PirateShip.gd"), encoding="utf-8").read():
    print("  ✓ PirateShip 有 class_name，is PirateShip 可解析")
else:
    print("  ✗ PirateShip 无 class_name")
    problems.append("PirateShip 无 class_name")
if "_format_left_hud" in wm_src:
    print("  ✓ WorldMap._format_left_hud 已定义（左栏 HUD 单独拼）")
else:
    print("  ✗ WorldMap 无 _format_left_hud")
    problems.append("WorldMap 无 _format_left_hud")
spawn_max = re.search(r"COMBAT_SPAWN_DIST_MAX\s*:=\s*([0-9.]+)", wm_src)
if spawn_max and float(spawn_max.group(1)) <= 500.0:
    print("  ✓ 开战刷船距离在镜头内（≤500）")
else:
    print("  ✗ 开战刷船距离过远或未定义")
    problems.append("开战刷船距离过远")
if "COMBAT_FIRE_DELAY" in wm_src and "fire_timer" in wm_src:
    print("  ✓ 开战给敌船接敌延迟，避免首帧齐射秒杀")
else:
    print("  ✗ 开战未给敌船接敌延迟")
    problems.append("开战未给敌船接敌延迟")
if "c is CanvasItem" in chart_src and "_enter_battle" in chart_src:
    print("  ✓ SeaChart 开战收起全屏栏")
else:
    print("  ✗ SeaChart 开战未收起全屏栏")
    problems.append("SeaChart 开战未收起全屏栏")
if "RightPanel/Margin/VBox/FleetStatus" in wm_src:
    print("  ✓ 右栏舰队/天气走 VBox，不再叠字")
else:
    print("  ✗ 右栏 FleetStatus 未改到 VBox")
    problems.append("右栏 FleetStatus 未改到 VBox")
cap = re.search(r"COMBAT_CANNON_CAP\s*:=\s*(\d+)", wm_src)
if cap and int(cap.group(1)) <= 2:
    print("  ✓ 开战敌船齐射封顶（≤2），开局小艍扛得住第一轮")
else:
    print("  ✗ 开战齐射未封顶，开局仍会被一波秒沉")
    problems.append("开战齐射未封顶")
ship_tscn = open(os.path.join(ROOT, "scenes", "Ship.tscn"), encoding="utf-8").read()
pirate_tscn = open(os.path.join(ROOT, "scenes", "PirateShip.tscn"), encoding="utf-8").read()
if "ship_fu.png" in ship_tscn and "ship_falcon.png" in pirate_tscn and "ship_topdown.png" not in ship_tscn:
    print("  ✓ 玩家福船 / 敌船海鹘用精绘精灵，不再用照片底板")
else:
    print("  ✗ 船精灵仍是照片底板或未换新图")
    problems.append("船精灵未换成福船/海鹘")
if "Color(1, 0.5, 0.5)" in pirate_src:
    print("  ✗ 海盗还在用红色 modulate 盖船图")
    problems.append("海盗红色 modulate 会脏掉海鹘精灵")
else:
    print("  ✓ 海盗不再用红色 modulate 盖船图")
cb_tscn = open(os.path.join(ROOT, "scenes", "Cannonball.tscn"), encoding="utf-8").read()
if "shot_iron.png" in cb_tscn and "cannonball.png" not in cb_tscn:
    print("  ✓ 炮弹用铁子精灵")
else:
    print("  ✗ 炮弹仍是大号 RGB 底板")
    problems.append("炮弹未换成铁子")


def png_probe(path):
    """stdlib 解码 PNG（含 Paeth/Up/Sub/Average 反过滤）。
    返回 (宽, 高, 是否 RGBA8, 四角 alpha 是否全 0)；无法解析返回 None。"""
    import struct as _st, zlib as _zl
    try:
        data = open(path, "rb").read()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        pos, idat, w, h, depth, ctype = 8, b"", 0, 0, 0, 0
        while pos < len(data):
            ln = _st.unpack(">I", data[pos:pos + 4])[0]
            typ, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + ln]
            if typ == b"IHDR":
                w, h, depth, ctype = _st.unpack(">IIBB", body[:10])
            elif typ == b"IDAT":
                idat += body
            pos += 12 + ln
        if ctype != 6 or depth != 8:
            return (w, h, False, False)
        raw = _zl.decompress(idat)
        stride = w * 4
        prev = bytearray(stride)
        corners = []
        p = 0
        for y in range(h):
            filt = raw[p]; p += 1
            cur = bytearray(raw[p:p + stride]); p += stride
            if filt == 1:
                for i in range(4, stride):
                    cur[i] = (cur[i] + cur[i - 4]) & 255
            elif filt == 2:
                for i in range(stride):
                    cur[i] = (cur[i] + prev[i]) & 255
            elif filt == 3:
                for i in range(stride):
                    cur[i] = (cur[i] + ((cur[i - 4] if i >= 4 else 0) + prev[i]) // 2) & 255
            elif filt == 4:
                for i in range(stride):
                    a = cur[i - 4] if i >= 4 else 0
                    b, c = prev[i], prev[i - 4] if i >= 4 else 0
                    pp = a + b - c
                    pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                    cur[i] = (cur[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
            if y == 0 or y == h - 1:
                corners += [cur[3], cur[stride - 1]]
            prev = cur
        return (w, h, True, all(a == 0 for a in corners))
    except Exception:
        return None


for rel in ("assets/ship_fu.png", "assets/ship_falcon.png", "assets/shot_iron.png"):
    full = os.path.join(ROOT, rel)
    if not os.path.exists(full):
        print(f"  ✗ 缺 {rel}")
        problems.append(f"缺 {rel}")
        continue
    probe = png_probe(full)
    if probe is None:
        print(f"  ✗ {rel} 不是可解析的 PNG")
        problems.append(f"{rel} 无法解析")
        continue
    w, h, is_rgba, clear_corners = probe
    if not is_rgba:
        print(f"  ✗ {rel} 不是 RGBA8（底板又会烤进图里）")
        problems.append(f"{rel} 非 RGBA")
    elif not clear_corners:
        print(f"  ✗ {rel} 四角不透明（疑似带底板）")
        problems.append(f"{rel} 带底板")
    else:
        print(f"  ✓ {rel} 真 RGBA 且四角透明（{w}x{h}）")
for rel, min_kb in (("assets/ship_fu.png", 60), ("assets/ship_falcon.png", 60)):
    full = os.path.join(ROOT, rel)
    if os.path.exists(full):
        kb = os.path.getsize(full) // 1024
        # 精绘 512² 船图约 110~150KB；扫线平涂占位只有 5KB 量级。
        if kb >= min_kb:
            print(f"  ✓ {rel} {kb}KB，是精绘位图不是平涂占位")
        else:
            print(f"  ✗ {rel} 仅 {kb}KB（<{min_kb}KB），疑似平涂占位图")
            problems.append(f"{rel} 疑似占位图")
_bg_map = os.path.join(ROOT, "assets", "bg_world_map.jpg")
if os.path.exists(_bg_map) and open(_bg_map, "rb").read(2) == b"\xff\xd8":
    print("  ✓ bg_world_map.jpg 在仓库里且是真 JPEG（海图/标题底图）")
else:
    print("  ✗ 缺 bg_world_map.jpg 或不是真 JPEG（海图背景留黑）")
    problems.append("缺 bg_world_map.jpg")

print()
print("=" * 68)
print("十一、绢本弹窗与字阶 / 挑签")
print("=" * 68)
theme_src = ""
with open(os.path.join(ROOT, "scripts", "core", "UiTheme.gd"), encoding="utf-8") as f:
    theme_src = f.read()
if re.search(r"^static func style_dialog\b", theme_src, re.M):
    print("  ✓ UiTheme.style_dialog 已定义")
else:
    print("  ✗ UiTheme.style_dialog 未定义")
    problems.append("UiTheme.style_dialog 未定义")
def _func_body(src: str, name: str) -> str:
    m = re.search(rf"^func {name}\b.*?(?=^func |\Z)", src, re.M | re.S)
    return m.group(0) if m else ""


save_body = _func_body(main_src, "_show_save_dialog")
if "SaveSheet" in save_body and "UiTheme.panel()" in save_body and "AcceptDialog" not in save_body:
    print("  ✓ 航海日志是居中绢本册页")
else:
    print("  ✗ 存档弹窗未套绢本主题")
    problems.append("存档弹窗未套绢本主题")
saveload_src = ""
with open(os.path.join(SCRIPTS, "core", "SaveLoad.gd"), encoding="utf-8") as f:
    saveload_src = f.read()
if (
    "未记" in saveload_src
    and "卷页损了" in saveload_src
    and "未题" in saveload_src
    and "（空）" not in saveload_src
    and "（损坏）" not in saveload_src
    and "（无标签）" not in saveload_src
    and "存档 / 读档" not in main_src
    and "%d 钱" in saveload_src
):
    print("  ✓ 航海日志空卷写成未记")
else:
    print("  ✗ 航海日志仍写空卷括号")
    problems.append("航海日志仍写空卷括号")
chapter_body = _func_body(main_src, "_show_chapter_dialog")
if "ChapterSheet" in chapter_body and "UiTheme.panel()" in chapter_body and "AcceptDialog" not in chapter_body:
    print("  ✓ 升章/了结是居中绢本册页")
else:
    print("  ✗ 升章/了结弹窗未套绢本主题")
    problems.append("升章/了结弹窗未套绢本主题")
market_body = _func_body(main_src, "_setup_market")
if "OptionButton" not in market_body and "_select_market_ship" in market_body:
    print("  ✓ 牙行选船走账条小钮")
else:
    print("  ✗ 牙行仍用系统下拉选船")
    problems.append("牙行仍用系统下拉选船")
if '买%d' not in main_src and '卖%d' not in main_src and "只购得 %d。" in main_src and "钱（" not in main_src:
    print("  ✓ 牙行小钮与买卖日志留出字距")
else:
    print("  ✗ 牙行小钮或买卖日志仍挤在一起")
    problems.append("牙行小钮或买卖日志仍挤在一起")
if "塞　50" in main_src and "关注　减 15" in main_src and "塞 50" not in main_src and "关注减 15" not in main_src and "UiTheme.plain_log(_gather_price_intel" in main_src:
    print("  ✓ 见面册疏通留出字距，行情去掉方括号")
else:
    print("  ✗ 见面册疏通或行情仍是挤字")
    problems.append("见面册疏通或行情仍是挤字")
if (
    "尚无人留意" in main_src
    and "偶有闲话传出" in main_src
    and "起了疑心" in main_src
    and "暗桩已盯死，出港必查" in main_src
    and "（尚无人留意）" not in main_src
    and "（偶有闲话传出）" not in main_src
    and "（蒲氏起了疑心）" not in main_src
    and "（暗桩已盯死，出港必查）" not in main_src
):
    print("  ✓ 市舶司关注四档去掉括号")
else:
    print("  ✗ 市舶司关注仍套括号")
    problems.append("市舶司关注仍套括号")
if (
    "（缺 %d 人）" not in main_src
    and "缺 %d 人" in main_src
    and "（%d/%d）" not in main_src
    and "水手 %d / %d" in main_src
    and "水手 %d/%d" not in main_src
    and "%d / %d 料" in main_src
    and "%d/%d 料" not in main_src
    and "水手不足　%s" in main_src
    and "水手不足：" not in main_src
):
    print("  ✓ 缺员与分船账条写成已有 / 所需，出海拦阻去掉冒号")
else:
    print("  ✗ 缺员或分船账条仍是紧挨斜杠或冒号")
    problems.append("缺员或分船账条仍是紧挨斜杠或冒号")
cal_src = ""
with open(os.path.join(SCRIPTS, "core", "Calendar.gd"), encoding="utf-8") as f:
    cal_src = f.read()
if (
    "东北季风　利南下" in cal_src
    and "西南季风　利北上" in cal_src
    and "季风转换期・风微而多变" in cal_src
    and "（利南下）" not in cal_src
    and "（利北上）" not in cal_src
    and "（风微而多变）" not in cal_src
    and "（五至八月）" not in main_src
    and "（十月至次年二月）" not in main_src
):
    print("  ✓ 风信写成短句")
else:
    print("  ✗ 风信仍套括号")
    problems.append("风信仍套括号")
if "★" not in main_src and "func _skill_rank" in main_src and "Crew.rank_word" in main_src and "func rank_word" in crew_src:
    print("  ✓ 职事品级写成初习/谙熟/老练")
else:
    print("  ✗ 职事仍用星号")
    problems.append("职事仍用星号")
if "func _fit_rank" in main_src and "帆Lv" not in main_src and "Lv%d" not in main_src:
    print("  ✓ 船壳改装写成一等/二等/三等")
else:
    print("  ✗ 船壳改装仍写 Lv")
    problems.append("船壳改装仍写 Lv")
if "func _interior_title" in main_src and "未命名设施" not in main_src:
    print("  ✓ 序章内页改写成港名去处")
else:
    print("  ✗ 序章内页或港卡仍是占位名")
    problems.append("序章内页或港卡仍是占位名")
if "func _interior_lead" in main_src and "static func plain_log" in theme_src and "UiTheme.plain_log" in main_src:
    print("  ✓ 序章内页进门有一句，日志去掉方括号标签")
else:
    print("  ✗ 内页正文或日志标签未收")
    problems.append("内页正文或日志标签未收")
if "【发舶】" not in seachart_src and "UiTheme.plain_log" in seachart_src:
    print("  ✓ 海图日志不再写发舶标签")
else:
    print("  ✗ 海图日志仍写发舶标签")
    problems.append("海图日志仍写发舶标签")
if (
    "func _bearing_phrase" in seachart_src
    and "UiTheme.card()" in seachart_src
    and "回港（不出海）" not in seachart_src
    and "目的：" not in seachart_src
    and "绕过去看看（费 1 日）" not in seachart_src
    and "%d%%" not in seachart_src
    and "°" not in seachart_src
):
    print("  ✓ 海图旁注收成账条，去掉冒号、度数符号和括号教程")
else:
    print("  ✗ 海图旁注仍是冒号或括号教程")
    problems.append("海图旁注仍是冒号或括号教程")
if (
    seachart_src.count("绕了些路。") == 1
    and seachart_src.count("_log_shook_pursuers()") == 3
    and "（绕了些路）" not in seachart_src
    and "（调试）" not in seachart_src
    and "点验　中途遭遇。" in seachart_src
    and "损折：" not in voyage_src
    and "损折　" in voyage_src
):
    print("  ✓ 海图遭遇日志去掉括号，风涛货损去掉冒号")
else:
    print("  ✗ 海图遭遇日志仍有括号或风涛货损仍有冒号")
    problems.append("海图遭遇日志仍有括号")
if (
    "收帆" in wm_src and "半帆" in wm_src and "满帆" in wm_src
    and "操舵　A　D" in wm_src and "齐射　J　K" in wm_src
    and "弃战　B" in wm_src and "接舷　G　弃战　B" in wm_src
    and "A/D" not in wm_src and "J/K" not in wm_src and "B/Esc" not in wm_src
    and "档" not in wm_src
    and "月息每百 %d" in main_src and "月息 %d%%" not in main_src
    and "添 %d 人" in main_src and "+%d" not in main_src
    and "运往 %s　多 %d" in main_src and "→ %s" not in main_src
    and "此帆比光船快" in main_src and "船体伤剩" in main_src
    and "航速 ×" not in main_src and "违禁：" not in main_src
    and "抽解每百 %d" in main_src and "%d%%" not in main_src
    and "水手 %d 至 %d" in main_src and "水粮各 %d　付 %d" in main_src
    and "水手 %d–%d" not in main_src and "各 %d　%d" not in main_src
):
    print("  ✓ 海战栏与船屋账条去掉斜杠、百分号和小数倍率")
else:
    print("  ✗ 海战栏或船屋账条仍有斜杠、百分号或小数倍率")
    problems.append("海战栏或船屋仍是原型记法")
gs_chapter_src = open(os.path.join(SCRIPTS, "GameState.gd"), encoding="utf-8").read()
if (
    "%s　%s　%d / %d" in main_src
    and "%s %s %d/%d" not in main_src
    and "再升一等。" in main_src
    and "再升一等：" not in main_src
    and "拓「%s」　%s" in main_src
    and "拓「%s」：" not in main_src
    and "亲至　" in gs_chapter_src
    and "亲至 " not in gs_chapter_src
    and "水手 %d / %d" in main_src
):
    print("  ✓ 章目写成已行多少，修埠与拓碑去掉冒号")
else:
    print("  ✗ 章目、修埠或拓碑仍是半角或冒号")
    problems.append("章目、修埠或拓碑仍是半角或冒号")
enter_i = main_src.find("func _on_enter_port")
enter_j = main_src.find("\nfunc ", enter_i + 1)
enter_body = main_src[enter_i:enter_j] if enter_i >= 0 and enter_j > enter_i else ""
if "visit_port" in enter_body and enter_body.find("update_status_panel") > enter_body.find("visit_port"):
    print("  ✓ 进港后船籍簿按已走通的港重写")
else:
    print("  ✗ 进港后船籍簿未按已走通的港重写")
    problems.append("进港后船籍簿未重写")
if '" x"' not in wm_src:
    print("  ✓ 海战货舱用乘号")
else:
    print("  ✗ 海战货舱仍用拉丁字母 x")
    problems.append("海战货舱仍用拉丁字母 x")
if 'text = "请选择"' not in main_src and "区域施工中" not in main_src:
    print("  ✓ 调查页用决断，缺页不再写施工中")
else:
    print("  ✗ 调查页仍写请选择或施工中")
    problems.append("调查页仍写请选择或施工中")
main_tscn = ""
with open(os.path.join(ROOT, "scenes", "Main.tscn"), encoding="utf-8") as f:
    main_tscn = f.read()
_placeholder_left = [
    needle for needle in (
        "副标题", "地点标题", "环境描述文本", "NPC Dialog", "NPC Name",
        "情报与状态", "港口名称",
    ) if needle in main_tscn
]
if _placeholder_left:
    print("  ✗ 开场场景仍有原型占位：%s" % "、".join(_placeholder_left))
    problems.append("开场场景仍有原型占位")
else:
    print("  ✓ 开场场景不再写原型占位")


def _node_block(src: str, node_name: str) -> str:
    token = '[node name="%s"' % node_name
    at = src.find(token)
    if at < 0:
        return ""
    nxt = src.find("\n[node ", at + len(token))
    return src[at:] if nxt < 0 else src[at:nxt]


if "visible = false" in _node_block(main_tscn, "InvestigationMode") and "visible = false" in _node_block(main_tscn, "LeftPanel"):
    print("  ✓ 调查页和船籍簿默认收起")
else:
    print("  ✗ 调查页或船籍簿开场仍展开")
    problems.append("开场占位层未收起")
if "按 Enter 停靠" in wm_tscn:
    print("  ✗ 海战港名仍写停靠教程")
    problems.append("海战港名仍写停靠教程")
else:
    print("  ✓ 海战港名不再写停靠教程")
portzone_src = ""
with open(os.path.join(ROOT, "scripts", "PortZone.gd"), encoding="utf-8") as f:
    portzone_src = f.read()
if "name_lbl.text = port_name" in portzone_src:
    print("  ✓ 港区名牌写港口名")
else:
    print("  ✗ 港区名牌未写港口名")
    problems.append("港区名牌未写港口名")
if "Color(0.2, 0.4, 0.6" in main_src:
    print("  ✗ NPC 按钮仍用蓝底硬编码")
    problems.append("NPC 按钮蓝底硬编码")
else:
    print("  ✓ NPC 按钮不再用蓝底硬编码")
if "hook_buttons(npc_actions)" in main_src:
    print("  ✓ 人物对话按钮挂钩 UiTheme")
else:
    print("  ✗ npc_actions 未挂钩 UiTheme")
    problems.append("npc_actions 未挂钩")
for name in ("SIZE_HEAD", "SIZE_BODY", "SIZE_FOOT", "LINE_BODY"):
    if "const %s" % name in theme_src:
        print(f"  ✓ UiTheme.{name} 已锁定")
    else:
        print(f"  ✗ UiTheme.{name} 未定义")
        problems.append(f"UiTheme.{name} 未定义")
if re.search(r"^static func style_choice_button\b", theme_src, re.M):
    print("  ✓ UiTheme.style_choice_button 已定义（挑签）")
else:
    print("  ✗ UiTheme.style_choice_button 未定义")
    problems.append("UiTheme.style_choice_button 未定义")
if "style_choice_button" in main_src and "func show_choices" in main_src:
    print("  ✓ 剧情选项走挑签样式")
else:
    print("  ✗ 剧情选项未走挑签样式")
    problems.append("剧情选项未走挑签")
if "style_heading(scene_title)" in main_src and "style_body(body_text)" in main_src:
    print("  ✓ 调查页标题/正文走字阶")
else:
    print("  ✗ 调查页未接线字阶")
    problems.append("调查页未接线字阶")
if "style_heading(head)" in seachart_src and "style_body(status_label)" in seachart_src:
    print("  ✓ 海图标题/状态栏走字阶")
else:
    print("  ✗ 海图未接线字阶")
    problems.append("海图未接线字阶")
if "event_panel.add_theme_stylebox_override(\"panel\", UiTheme.panel())" in seachart_src:
    print("  ✓ 海图遭遇弹层走绢本面板")
else:
    print("  ✗ 海图遭遇弹层仍用硬编码 StyleBox")
    problems.append("海图遭遇弹层未套绢本")
if "CenterContainer" in seachart_src and "Vector2(360, 200)" not in seachart_src:
    print("  ✓ 海图遭遇弹层居中，不再钉右下")
else:
    print("  ✗ 海图遭遇弹层仍用 360,200 硬坐标")
    problems.append("海图遭遇弹层未居中")
if "func _draw_ink_label" in seachart_src and "draw_string(font, v + Vector2(8, 5)" not in seachart_src:
    print("  ✓ 海图港名走墨底签")
else:
    print("  ✗ 海图港名仍是裸字")
    problems.append("海图港名未垫墨底")
if "func _draw_chart_leaf" in seachart_src and "Color(0.11, 0.08, 0.05, 0.55)" not in seachart_src:
    print("  ✓ 海图中栏是绢纸")
else:
    print("  ✗ 海图中栏仍铺熟漆")
    problems.append("海图中栏未改绢纸")
if "event_actions = VBoxContainer" in seachart_src and "style_choice_button(b)" in seachart_src:
    print("  ✓ 海图遭遇选项走竖排挑签")
else:
    print("  ✗ 海图遭遇选项未走挑签")
    problems.append("海图遭遇未走挑签")
if "StyleBoxFlat.new()" in seachart_src:
    print("  ✗ SeaChart 仍手写 StyleBoxFlat")
    problems.append("SeaChart 手写 StyleBoxFlat")
else:
    print("  ✓ SeaChart 不再手写 StyleBoxFlat")

print()
print("=" * 68)
print("十二、名声换爵与港口投资")
print("=" * 68)
print("  职衔派生自名声；修埠落 Economy；市舶司是唯一入口。")

titles_path = os.path.join(ROOT, "data", "titles.json")
if os.path.isfile(titles_path):
    print("  ✓ data/titles.json 存在")
else:
    print("  ✗ data/titles.json 不存在")
    problems.append("缺 titles.json")

gm_src = open(os.path.join(SCRIPTS, "GameManager.gd"), encoding="utf-8").read()
eco_src = open(os.path.join(SCRIPTS, "core", "Economy.gd"), encoding="utf-8").read()
gs_src = open(os.path.join(SCRIPTS, "GameState.gd"), encoding="utf-8").read()
if "titles_data" in defined.get("GameManager", set()) and "titles.json" in gm_src:
    print("  ✓ GameManager 加载 titles.json")
else:
    print("  ✗ GameManager 未加载 titles.json")
    problems.append("GameManager 未加载 titles")

for f in ("add_fame", "title_rank", "next_title", "title_duty_factor",
          "title_loan_bonus", "title_name", "title_ranks"):
    if f in defined.get("GameState", set()):
        print(f"  ✓ GameState.{f} 已定义")
    else:
        print(f"  ✗ GameState.{f} 未定义")
        problems.append(f"GameState.{f} 未定义")

for f in ("invest", "invest_cost", "investment_level", "invest_edge",
          "investments", "invest_fame_gain"):
    if f in defined.get("Economy", set()):
        print(f"  ✓ Economy.{f} 已定义")
    else:
        print(f"  ✗ Economy.{f} 未定义")
        problems.append(f"Economy.{f} 未定义")

if "title_duty_factor" in eco_src:
    print("  ✓ Economy 定价乘职衔抽解")
else:
    print("  ✗ Economy 定价未乘职衔")
    problems.append("Economy 未乘职衔")
if 'role == "origin"' in eco_src and 'role == "consumer"' in eco_src and "invest_edge" in eco_src:
    print("  ✓ Economy 修埠按产地/消费地同向调单位价")
else:
    print("  ✗ Economy 修埠未按角色同向调价")
    problems.append("Economy 修埠调价未接线")
if '"investments"' in eco_src:
    print("  ✓ Economy 存档含 investments")
else:
    print("  ✗ Economy 存档缺 investments")
    problems.append("Economy 存档缺 investments")
if "title_loan_bonus" in gs_src and "borrow_limit" in gs_src:
    print("  ✓ 赊贷上限吃职衔加成")
else:
    print("  ✗ 赊贷上限未吃职衔加成")
    problems.append("borrow_limit 未接职衔")
if "title_duty_factor" in gs_src and "customs_duty" in gs_src:
    print("  ✓ 货引抽解吃职衔折让")
else:
    print("  ✗ 货引抽解未吃职衔")
    problems.append("customs_duty 未接职衔")
if "add_fame(" in main_src and "fame +=" not in main_src.replace("add_fame", ""):
    print("  ✓ Main 名声走 add_fame")
else:
    if "add_fame(" in main_src:
        print("  ✓ Main 名声走 add_fame")
    else:
        print("  ✗ Main 未走 add_fame")
        problems.append("Main 未走 add_fame")
if "_setup_title_and_invest" in main_src and "向本港投钱修埠" in main_src:
    print("  ✓ 市舶司有职衔说明与修埠钮")
else:
    print("  ✗ 市舶司未接职衔/修埠")
    problems.append("市舶司未接职衔修埠")
dyn = re.search(r"func _setup_dynamic_scene.*?(?=\nfunc )", main_src, re.S)
if dyn and "update_status_panel()" in dyn.group(0):
    print("  ✓ 设施页重载刷新状态栏（修埠/买卖后金钱可见）")
else:
    print("  ✗ _setup_dynamic_scene 未刷新状态栏")
    problems.append("_setup_dynamic_scene 未刷新状态栏")
if "title_name()" in seachart_src:
    print("  ✓ 海图状态栏显示职衔")
else:
    print("  ✗ 海图状态栏无职衔")
    problems.append("海图无职衔")
if "add_fame(3)" in seachart_src:
    print("  ✓ 海战胜仗名声走 add_fame")
else:
    print("  ✗ 海战胜仗仍直接改 fame")
    problems.append("海战名声未走 add_fame")

pressed = re.search(r"func _on_facility_pressed.*?(?=\nfunc |\Z)", main_src, re.S)
if pressed and "REMAPPED_FACILITIES" in pressed.group(0) and "city_inn" in main_src:
    print("  ✓ 旅店按港改写成 {港}_inn（不再 _setup_inn(\"city\")）")
else:
    print("  ✗ 旅店未列入港卡改写")
    problems.append("city_inn 未改写")
if "PROLOGUE_ONLY_FACILITIES" in main_src and 'current_scene_id == "xinghua"' in main_src:
    pressed_body = pressed.group(0) if pressed else ""
    if "visited_ports" in pressed_body and "quanzhou" in pressed_body:
        print("  ✓ 兴化序章调查页仅在未到泉州前；回访走动态页")
    else:
        print("  ✗ 兴化回访仍一律进序章调查页")
        problems.append("兴化回访未切开")
else:
    print("  ✗ 序章设施未与游戏港切开")
    problems.append("序章设施未切开")
gen = re.search(r"const GENERIC_FACILITIES\s*:=\s*\[(.*?)\]", main_src, re.S)
if gen:
    gbody = gen.group(1)
    missing = [fid for fid in (
        "city_guild", "city_exam", "city_residence", "city_temple", "city_yamen",
    ) if fid not in gbody]
    if missing:
        print("  ✗ 通用港缺卡：%s" % ", ".join(missing))
        problems.append("GENERIC_FACILITIES 缺 %s" % ",".join(missing))
    elif gbody.find("city_temple") > gbody.find("city_yamen"):
        print("  ✗ 通用港寺观须排在市舶司之前（右列原市舶司位）")
        problems.append("GENERIC 寺观卡序")
    elif "勘见・拓碑" not in gbody:
        print("  ✗ 通用港寺观副题不是勘见・拓碑")
        problems.append("GENERIC 寺观副题")
    else:
        print("  ✓ 通用港 GENERIC_FACILITIES 含行会/贡院/住宅/寺观")
else:
    print("  ✗ 未找到 GENERIC_FACILITIES")
    problems.append("缺 GENERIC_FACILITIES")
if "begins_with(\"city_\")" in main_src:
    print("  ✓ load_scene 跳过 city_ 前缀，避免盖掉序章 id")
else:
    print("  ✗ load_scene 仍会把 city_guild 收成动态页")
    problems.append("load_scene 未跳过 city_ 前缀")
for fn in (
    "_setup_guild", "_setup_exam", "_setup_residence", "_collect_spreads",
    "_on_exam_copy", "_setup_temple", "_on_temple_look",
    "_on_temple_rub", "_temple_rub_note",
):
    if re.search(r"func %s\b" % fn, main_src):
        print("  ✓ Main.%s 已定义" % fn)
    else:
        print("  ✗ 缺 Main.%s" % fn)
        problems.append("缺 %s" % fn)
if "HOME_RATE" in main_src and "INN_RATE" in main_src:
    home = re.search(r"const HOME_RATE\s*:=\s*(\d+)", main_src)
    inn = re.search(r"const INN_RATE\s*:=\s*(\d+)", main_src)
    if home and inn and int(home.group(1)) < int(inn.group(1)):
        print("  ✓ 住处歇息 %s 钱/日 < 旅店 %s" % (home.group(1), inn.group(1)))
    else:
        print("  ✗ 住处房价未低于旅店")
        problems.append("HOME_RATE 未低于 INN_RATE")
else:
    print("  ✗ 缺 HOME_RATE / INN_RATE")
    problems.append("缺房价常量")
exam_fn = re.search(r"func _on_exam_copy.*?(?=\nfunc |\Z)", main_src, re.S)
if exam_fn and "add_fame" in exam_fn.group(0):
    print("  ✗ 贡院誊录给了名声（会绕过修埠/呈报）")
    problems.append("贡院不得给名声")
elif exam_fn and "scholar_tendency" in exam_fn.group(0):
    print("  ✓ 贡院誊录只加学者倾向，不给名声")
else:
    print("  ✗ 贡院誊录未接线")
    problems.append("贡院誊录未接线")
if all(s in main_src for s in (
    '"_guild"', '"_exam"', '"_residence"', '"_temple"',
    "bg_quanzhou_ledger.jpg", "bg_academy.jpg", "bg_xinghua_study.jpg",
    "bg_temple_library.jpg",
)):
    print("  ✓ 行会/贡院/住宅/寺观有设施背景")
else:
    print("  ✗ 设施缺背景")
    problems.append("设施缺 FACILITY_BG")
for rel in (
    "assets/bg_quanzhou_ledger.jpg",
    "assets/bg_academy.jpg",
    "assets/bg_xinghua_study.jpg",
    "assets/bg_temple_library.jpg",
    "assets/icon_temple.png",
):
    if os.path.isfile(os.path.join(ROOT, rel)):
        print("  ✓ %s 在仓库" % rel)
    else:
        print("  ✗ 缺 %s" % rel)
        problems.append("缺 %s" % rel)
if "discoveries_near" not in defined.get("GameManager", set()):
    print("  ✗ GameManager.discoveries_near 未定义")
    problems.append("缺 discoveries_near")
else:
    print("  ✓ GameManager.discoveries_near 已定义")
temple_fn = re.search(r"func _on_temple_look.*?(?=\nfunc |\Z)", main_src, re.S)
if not temple_fn:
    print("  ✗ 寺观细看未接线")
    problems.append("缺 _on_temple_look")
elif any(tok in temple_fn.group(0) for tok in ("add_fame", "report_discovery")):
    print("  ✗ 寺观勘见给了名声或当场呈报（赏格须回市舶司）")
    problems.append("寺观不得给名声/呈报")
elif "record_discovery" in temple_fn.group(0) and "TEMPLE_LOOK_DAYS" in temple_fn.group(0):
    print("  ✓ 寺观细看只记入册、耗日，不给名声")
else:
    print("  ✗ 寺观细看未走 record_discovery")
    problems.append("寺观未记入册")
rub_fn = re.search(r"func _on_temple_rub.*?(?=\nfunc |\Z)", main_src, re.S)
if not rub_fn:
    print("  ✗ 寺观拓碑未接线")
    problems.append("缺 _on_temple_rub")
elif any(tok in rub_fn.group(0) for tok in ("add_fame", "report_discovery")):
    print("  ✗ 寺观拓碑给了名声或当场呈报")
    problems.append("寺观拓碑不得给名声/呈报")
elif "add_ledger_note" in rub_fn.group(0) and "TEMPLE_RUB_DAYS" in rub_fn.group(0):
    print("  ✓ 寺观拓碑只写入边记、耗日，不给名声")
else:
    print("  ✗ 寺观拓碑未走 add_ledger_note")
    problems.append("寺观未写入边记")
sim_src = open(os.path.join(ROOT, "tools", "simulate_run.py"), encoding="utf-8").read()
if any(tok in sim_src for tok in (
    "scholar_tendency", "誊录", "EXAM_STIPEND", "HOME_RATE",
    "勘见", "TEMPLE_LOOK", "_on_temple_look", "record_discovery",
    "拓碑", "TEMPLE_RUB", "_on_temple_rub",
)):
    print("  ✗ simulate_run 自动走了贡院誊录、住处歇息或寺观勘见/拓碑")
    problems.append("simulate_run 不得自动誊录/住家/勘见/拓碑")
else:
    print("  ✓ simulate_run 不自动誊录、歇住家、勘见、拓碑（贡院/住宅/寺观不进通关主循环）")
if '"_inn"' in main_src and "bg_relay_post.jpg" in main_src:
    print("  ✓ 旅店有设施背景")
else:
    print("  ✗ 旅店缺设施背景")
    problems.append("旅店缺 FACILITY_BG")

lt = re.search(r"func load_texture.*?(?=\nfunc |\Z)", gm_src, re.S)
if lt:
    body = lt.group(0)
    fi = body.find("get_file_as_bytes")
    li = body.find("load(path)")
    if fi >= 0 and (li < 0 or fi < li):
        print("  ✓ load_texture 先按文件头解码（避开 valid=false / 假 PNG 的 ERROR）")
    else:
        print("  ✗ load_texture 仍先走 ResourceLoader.load")
        problems.append("load_texture 仍先 load()")
else:
    print("  ✗ 未找到 load_texture")
    problems.append("缺 load_texture")

scenes_path = os.path.join(ROOT, "data", "scenes.json")
with open(scenes_path, encoding="utf-8") as f:
    scenes_doc = json.load(f)
yamen_titles = set()
market_titles = set()
guild_subs = set()
exam_subs = set()
home_subs = set()
temple_subs = set()
port_ids_with_temple = set()
port_scene_ids = []
for sc in scenes_doc.get("scenes", []):
    if sc.get("type") != "port":
        continue
    sid = sc.get("id", "")
    port_scene_ids.append(sid)
    for fac in sc.get("facilities", []):
        fid = fac.get("id", "")
        if fid == "city_yamen":
            yamen_titles.add(fac.get("title", ""))
        if fid == "city_market":
            market_titles.add(fac.get("title", ""))
        if fid == "city_guild":
            guild_subs.add(fac.get("subtitle", ""))
        if fid == "city_exam":
            exam_subs.add(fac.get("subtitle", ""))
        if fid == "city_residence":
            home_subs.add(fac.get("subtitle", ""))
        if fid == "city_temple":
            temple_subs.add(fac.get("subtitle", ""))
            port_ids_with_temple.add(sid)
if yamen_titles == {"市舶司"}:
    print("  ✓ 港卡 city_yamen 标题是市舶司（不再写衙门）")
else:
    print("  ✗ 港卡市舶司标题漂移：%s" % sorted(yamen_titles))
    problems.append("港卡 yamen 标题不是市舶司")
if market_titles == {"牙行"}:
    print("  ✓ 港卡 city_market 标题是牙行（不再写市场）")
else:
    print("  ✗ 港卡牙行标题漂移：%s" % sorted(market_titles))
    problems.append("港卡 market 标题不是牙行")
if guild_subs == {"行情・信用"}:
    print("  ✓ 港卡行会副题是行情・信用")
else:
    print("  ✗ 行会副题漂移：%s" % sorted(guild_subs))
    problems.append("行会副题未改")
if exam_subs == {"誊录・观礼"}:
    print("  ✓ 港卡贡院副题是誊录・观礼")
else:
    print("  ✗ 贡院副题漂移：%s" % sorted(exam_subs))
    problems.append("贡院副题未改")
if home_subs == {"账本・歇息"}:
    print("  ✓ 港卡住宅副题是账本・歇息")
else:
    print("  ✗ 住宅副题漂移：%s" % sorted(home_subs))
    problems.append("住宅副题未改")
if temple_subs == {"勘见・拓碑"} and set(port_scene_ids) <= port_ids_with_temple:
    print("  ✓ 港卡寺观副题是勘见・拓碑，剧情港均有此卡")
else:
    print("  ✗ 寺观卡漂移：副题 %s，缺卡港 %s" % (
        sorted(temple_subs), sorted(set(port_scene_ids) - port_ids_with_temple),
    ))
    problems.append("寺观港卡未对齐")
disc_path = os.path.join(ROOT, "data", "discoveries.json")
with open(disc_path, encoding="utf-8") as f:
    disc_doc = json.load(f)
note = str(disc_doc.get("meta", {}).get("note", ""))
if "寺观上报" in note or "寺观呈报" in note:
    print("  ✗ discoveries.json 仍写寺观上报（呈报只在市舶司）")
    problems.append("发现录 note 把呈报写到寺观")
else:
    print("  ✓ 发现录 note 不把呈报放到寺观")
ports_path = os.path.join(ROOT, "data", "ports.json")
with open(ports_path, encoding="utf-8") as f:
    ports_doc = json.load(f)
near_ports = set()
for d in disc_doc.get("discoveries", []):
    for pid in d.get("near_ports", []):
        near_ports.add(pid)
bare = [p.get("id") for p in ports_doc.get("ports", []) if p.get("id") not in near_ports]
if bare:
    print("  ✗ 无近侧发现的港口：%s" % ", ".join(bare))
    problems.append("有港无 near_ports 发现")
else:
    print("  ✓ 各港至少一条近侧发现（寺观细看不空）")
fuzhou_ids = [
    d.get("id") for d in disc_doc.get("discoveries", [])
    if "fuzhou" in d.get("near_ports", [])
]
if "beacon_ruin" in fuzhou_ids:
    print("  ✓ 福州近侧含废烽堠")
else:
    print("  ✗ 福州近侧没有废烽堠")
    problems.append("福州缺 beacon_ruin")
title_ui = re.search(r"func _setup_title_and_invest.*?(?=\nfunc |\Z)", main_src, re.S)
if title_ui and "纲首" in title_ui.group(0):
    print("  ✗ 职衔说明文案写了纲首")
    problems.append("职衔 UI 含纲首")
elif title_ui:
    print("  ✓ 职衔说明不写纲首（下一档走 titles.json 的 name）")
else:
    print("  ✗ 未找到 _setup_title_and_invest")
    problems.append("缺 _setup_title_and_invest")

print()
print("=" * 68)
if problems:
    print(f"结果：{len(problems)} 项问题")
    for p in problems:
        print("   ✗", p)
    sys.exit(1)
print("结果：全部通过")
