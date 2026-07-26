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
if problems:
    print(f"结果：{len(problems)} 项问题")
    for p in problems:
        print("   ✗", p)
    sys.exit(1)
print("结果：全部通过")
