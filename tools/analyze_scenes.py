import json, sys

with open('data/scenes.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

scenes = data.get('scenes', [])
print(f"Total scenes: {len(scenes)}")
print(f"Top keys: {list(data.keys())}")
print()

# Group by location
from collections import defaultdict
by_location = defaultdict(list)
by_chapter = defaultdict(list)

for s in scenes:
    loc = s.get('location', 'unknown')
    ch = s.get('chapter', 'unknown')
    sid = s.get('id', '???')
    by_location[loc].append(sid)
    by_chapter[ch].append(sid)

print("=== By Location ===")
for loc, ids in sorted(by_location.items()):
    print(f"  {loc} ({len(ids)}): {ids}")

print()
print("=== By Chapter ===")
for ch, ids in sorted(by_chapter.items()):
    print(f"  {ch} ({len(ids)}): {ids}")

print()
print(f"start_scene: {data.get('start_scene', 'N/A')}")
