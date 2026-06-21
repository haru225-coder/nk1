import json
import os

def load_json(path):
    try:
        return json.load(open(path, encoding='utf-8'))
    except Exception as e:
        print(f"Error loading {path}: {e}")
        return {}

scenes_data = load_json('data/scenes.json')
ports_data = load_json('data/ports.json')
world_data = load_json('data/world.json')
npcs_data = load_json('data/npcs.json')
discoveries_data = load_json('data/discoveries.json')

scenes = {x['id']: x for x in scenes_data.get('scenes', [])}

# Collect valid locations
valid_locations = set()
for p in world_data.get('ports', []):
    valid_locations.add(p['id'])

for x in scenes.values():
    if 'location' in x:
        # scene location is arbitrary, but let's just collect them? 
        pass

# Check choices
for x in scenes.values():
    for c in x.get('choices', []):
        nxt = c.get('next')
        if nxt and nxt not in scenes and nxt != 'last_port':
            print(f"[scenes.json] Choice in '{x['id']}' points to missing scene: '{nxt}'")
    for f in x.get('facilities', []):
        nxt = f.get('next')
        if nxt and nxt not in scenes:
            if not any(nxt.endswith(suffix) for suffix in ["_market", "_tavern", "_yamen", "_shipyard"]):
                print(f"[scenes.json] Facility in '{x['id']}' points to missing scene: '{nxt}'")

# Check world.json
world_ports = {p['id'] for p in world_data.get('ports', [])}
for p in world_data.get('ports', []):
    for conn in p.get('connections', []):
        if conn not in world_ports:
            print(f"[world.json] Port '{p['id']}' has connection to missing port: '{conn}'")
    for rconn in p.get('rumor_connections', []):
        if rconn not in world_ports:
            print(f"[world.json] Port '{p['id']}' has rumor_connection to missing port: '{rconn}'")

# Check npcs.json
for n in npcs_data.get('npcs', []) if isinstance(npcs_data.get('npcs'), list) else []:
    pass

print("Structure check complete.")
