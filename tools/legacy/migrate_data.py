import json
import shutil
import os

source_dir = "/Users/snowchan27/d4/east-sea-chronicle/data"
dest_dir = "/Users/snowchan27/nk-1/data"

# Copy non-scene JSON files
files_to_copy = ["goods.json", "ports.json", "npcs.json", "discoveries.json", "world.json"]
for f in files_to_copy:
    src_path = os.path.join(source_dir, f)
    dst_path = os.path.join(dest_dir, f)
    if os.path.exists(src_path):
        shutil.copy2(src_path, dst_path)
        print(f"Copied {f}")

# Merge scenes.json
src_scenes_path = os.path.join(source_dir, "scenes.json")
dst_scenes_path = os.path.join(dest_dir, "scenes.json")

with open(src_scenes_path, "r", encoding="utf-8") as f:
    src_data = json.load(f)

with open(dst_scenes_path, "r", encoding="utf-8") as f:
    dst_data = json.load(f)

# The goal is to keep the massive amount of scenes from src,
# but inject the Godot-specific fields (like type="port" or "title")
# that we added in dst_data.

# Build a map of Godot specific scene data
godot_scene_map = {s["id"]: s for s in dst_data.get("scenes", [])}

merged_scenes = []

# First, process all scenes from the source (HTML version)
src_scene_ids = set()
for src_scene in src_data.get("scenes", []):
    s_id = src_scene["id"]
    src_scene_ids.add(s_id)
    
    if s_id in godot_scene_map:
        # Merge Godot fields into src_scene
        godot_s = godot_scene_map[s_id]
        if "type" in godot_s:
            src_scene["type"] = godot_s["type"]
        if "location" in godot_s:
            src_scene["location"] = godot_s["location"]
        # If godot added facilities, maybe keep them?
        if "facilities" in godot_s and not src_scene.get("facilities"):
            src_scene["facilities"] = godot_s["facilities"]
    merged_scenes.append(src_scene)

# Then, append any NEW scenes that exist only in Godot (like port_quanzhou if it was added)
for godot_s in dst_data.get("scenes", []):
    if godot_s["id"] not in src_scene_ids:
        merged_scenes.append(godot_s)

final_data = {
    "start_scene": dst_data.get("start_scene", "cg_title"),
    "scenes": merged_scenes
}

with open(dst_scenes_path, "w", encoding="utf-8") as f:
    json.dump(final_data, f, ensure_ascii=False, indent=2)

print("Merged scenes.json successfully!")
