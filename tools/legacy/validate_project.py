# 【历史留档，勿运行】（lane doc7 定级）早期一次性自查：只读 data/scenes.json 查 choices 断链，不写文件；不在门禁注册表里，结果不作红绿依据
# （现行剧情数据校验看 tools/verify_story_data.py）。
# 不是门禁、无调用方，仅供查来历。
import json

with open('data/scenes.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

scenes = {s['id']: s for s in data.get('scenes', [])}
errors = []

for s_id, s in scenes.items():
    # Check choices
    for c in s.get('choices', []):
        next_id = c.get('next')
        if next_id and next_id not in scenes:
            errors.append(f"Scene '{s_id}' choice '{c.get('label')}' points to missing scene: '{next_id}'")
            
    # Check facilities
    for f in s.get('facilities', []):
        next_id = f.get('next')
        # Some facilities are hardcoded in Main.gd (ends with _market, _yamen), but let's check anyway
        # Actually dynamic scenes are handled in Main.gd without being in scenes.json!
        # Let's see what is missing that doesn't end with _market, _yamen, etc.
        pass

if errors:
    for e in errors:
        print(e)
else:
    print("No broken links found in scenes.json.")
