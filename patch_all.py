import json

with open('data/scenes.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Patch Title
data['start_scene'] = 'cg_title'
for scene in data.get('scenes', []):
    if scene['id'] == 'cg_title':
        scene['type'] = 'title'
        scene['cg_title'] = '东亚海域立志传'
        scene['cg_sub'] = '南宋宝祐三年（1255）'
        scene['choices'] = [{"label": "开始旅程", "next": "prologue_tabletop"}]
    elif scene['id'] == 'prologue_tabletop':
        scene['choices'] = [
            {"label": "随阿那去泉州（解锁海路）", "next": "port_quanzhou", "effects": {"pu_attention": 10}},
            {"label": "跟家丁回去（未实装）", "next": "prologue_tabletop", "effects": {"money": 50}}
        ]

# Add port_quanzhou
port_quanzhou = {
    "id": "port_quanzhou", "type": "port", "location": "quanzhou", "title": "泉州",
    "facilities": [
        {"id": "city_shipyard", "next": "quanzhou_shipyard"},
        {"id": "city_guild", "next": "quanzhou_guild"},
        {"id": "city_tavern", "next": "quanzhou_tavern"},
        {"id": "city_market", "next": "quanzhou_market"},
        {"id": "city_inn", "next": "quanzhou_inn"},
        {"id": "city_exam", "next": "quanzhou_exam"},
        {"id": "city_residence", "next": "quanzhou_residence"},
        {"id": "city_yamen", "next": "quanzhou_yamen"}
    ]
}

quanzhou_tavern = {
    "id": "quanzhou_tavern", "chapter": "quanzhou", "title": "泉州酒馆", "location": "quanzhou",
    "body": "人声鼎沸的泉州酒馆，角落里坐着几个老兵在喝闷酒。",
    "investigations": [{"label": "邻桌老兵", "text": "老兵讲北边战局不利。", "effects": {"fame": 1}}],
    "choices": [{"label": "离开酒馆", "next": "port_quanzhou"}]
}

data.setdefault('scenes', []).extend([port_quanzhou, quanzhou_tavern])

with open('data/scenes.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("Patched successfully.")
