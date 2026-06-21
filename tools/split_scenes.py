import json, os

# 读取原始 scenes.json
with open('data/scenes.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

scenes = data.get('scenes', [])
start_scene = data.get('start_scene', '')

# 分组规则：按 location 字段归类
GROUPS = {
    'prologue.json': lambda s: s.get('location', '') == 'prologue' or s.get('chapter', '') == 'prologue',
    'xinghua.json': lambda s: s.get('location', '') == 'xinghua',
    'quanzhou.json': lambda s: s.get('location', '') == 'quanzhou',
    'sea.json': lambda s: s.get('location', '') in ('sea', 'penghu', 'keelung'),
    'linan.json': lambda s: s.get('location', '') == 'linan',
}

# 创建输出目录
os.makedirs('data/scenes', exist_ok=True)

# 分组
binned = {k: [] for k in GROUPS}
unmatched = []

for s in scenes:
    matched = False
    for filename, matcher in GROUPS.items():
        if matcher(s):
            binned[filename].append(s)
            matched = True
            break
    if not matched:
        unmatched.append(s.get('id', '???'))

# 写入文件
total_written = 0
for filename, group in binned.items():
    if not group:
        continue
    out = {"scenes": group}
    path = os.path.join('data/scenes', filename)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"  {filename}: {len(group)} scenes")
    total_written += len(group)

print(f"\nTotal written: {total_written}/{len(scenes)}")
if unmatched:
    print(f"WARNING: Unmatched scenes: {unmatched}")

# 验证：加载所有拆分文件并合并，确认 scene ID 不重复且数量一致
merged_ids = set()
for filename in os.listdir('data/scenes'):
    if not filename.endswith('.json'):
        continue
    with open(os.path.join('data/scenes', filename), 'r', encoding='utf-8') as f:
        chunk = json.load(f)
    for s in chunk.get('scenes', []):
        sid = s.get('id', '')
        if sid in merged_ids:
            print(f"ERROR: Duplicate scene ID: {sid}")
        merged_ids.add(sid)

print(f"Merged unique IDs: {len(merged_ids)}")
original_ids = {s.get('id') for s in scenes}
if merged_ids == original_ids:
    print("VALIDATION PASSED: All original scenes accounted for")
else:
    missing = original_ids - merged_ids
    extra = merged_ids - original_ids
    if missing:
        print(f"ERROR: Missing IDs: {missing}")
    if extra:
        print(f"ERROR: Extra IDs: {extra}")
