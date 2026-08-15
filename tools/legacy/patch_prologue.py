import json

with open('data/scenes.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

prologue = {
    "id": "prologue_tabletop",
    "type": "investigation",
    "location": "tavern",
    "title": "海口酒棚",
    "body": "一张油腻的八仙桌，桌上散落着几件引人注目的物件。你必须摸清现在的局势才能出海。",
    "investigations": [
        {"label": "边防策草稿", "text": "【边防策草稿】大宋水军疲软，北方战事吃紧。", "effects": {"fame": 5}},
        {"label": "沾着盐渍的货引", "text": "【沾着盐渍的货引】蒲氏商帮最近正在严查走私，必须小心。", "effects": {"pu_attention": 5}},
        {"label": "玉湖陈氏族札", "text": "【玉湖陈氏族札】宗族长辈敦促你参加科举，不要出海。", "effects": {"money": -50}}
    ],
    "choices": [
        {"label": "随阿那去泉州（解锁海路）", "next": "port_quanzhou", "effects": {"pu_attention": 10}}
    ]
}

data.setdefault('scenes', []).append(prologue)

with open('data/scenes.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("Prologue patched!")
