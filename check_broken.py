import json
d = json.load(open('data/scenes.json', encoding='utf-8'))
s = {x['id'] for x in d['scenes']}
for x in d['scenes']:
    for c in x.get('choices', []):
        nxt = c.get('next')
        if nxt and nxt not in s and nxt != 'last_port':
            print(f"Choice {x['id']} -> {nxt}")
    for f in x.get('facilities', []):
        nxt = f.get('next')
        # Also facility names like port_quanzhou_market might not be explicitly in scenes.json,
        # but they are dynamically generated. We can ignore if it ends with _market, _tavern, _yamen, _shipyard
        if nxt and nxt not in s:
            if not any(nxt.endswith(suffix) for suffix in ["_market", "_tavern", "_yamen", "_shipyard"]):
                print(f"Facility {x['id']} -> {nxt}")
