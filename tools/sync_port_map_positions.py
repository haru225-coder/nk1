#!/usr/bin/env python3
"""Sync ports.json map_pos/position from a geographic pin table.

Pins are real lat/lon projected onto the world_bounds UV frame:
    u = (lon - 92) / 42      (92°E..134°E, west→east)
    v = (42 - lat) / 52      (42°N..10°S, north→south)
Keep this table in sync when adding ports, then run to write JSON.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PORTS = ROOT / "data" / "ports.json"

# 世界边界：42°N→10°S (52°纬) × 92°E→134°E (42°经)，竖向 aspect 0.808
# 量级保持与旧 bounds 同级，航速/遭遇/小地图体感不变
WORLD_BOUNDS = {"x_min": -13000, "x_max": 13000, "y_min": -5000, "y_max": 27200}
MAP_TEXTURE = "res://assets/map_east_asia.png"
MAP_SEA_MASK = "res://assets/map_east_asia_sea_mask.png"

# port_id -> (lat, lon). ponytail: hardcoded pins, one game, no config file.
MAP_POS: dict[str, tuple[float, float]] = {
    "byland":     (39.0,  125.7),   # 平壤
    "jeju":       (33.5,  126.5),   # 济州
    "tsushima":   (34.3,  129.3),   # 对马
    "hakata":     (33.6,  130.4),   # 博多
    "kagoshima":  (31.6,  130.6),   # 萨摩
    "ryukyu":     (26.3,  127.9),   # 琉球
    "keelung":    (25.1,  121.7),   # 基隆
    "penghu":     (23.6,  119.6),   # 澎湖
    "mingzhou":   (29.9,  121.6),   # 明州/宁波
    "wenzhou":    (28.0,  120.7),   # 温州
    "ganpu":      (30.4,  121.1),   # 澉浦
    "xinghua":    (25.4,  119.0),   # 兴化/莆田
    "quanzhou":   (24.9,  118.6),   # 泉州
    "zhangzhou":  (24.5,  117.7),   # 漳州
    "guangzhou":  (23.1,  113.3),   # 广州
    "tunmen":     (22.3,  113.9),   # 屯门
    "qiongzhou":  (20.0,  110.3),   # 琼州
    "xuwen":      (20.3,  110.2),   # 徐闻
    "jiaozhi":    (20.9,  105.9),   # 交趾/河内
    "champa":     (15.9,  108.3),   # 占城
    "bugan":      (21.2,   94.9),   # 蒲甘 (内陆伊洛瓦底江畔)
    "longyamen":  (1.3,   103.8),   # 龙牙门/新加坡
    "sanfoqi":    (-3.0,  104.8),   # 三佛齐/巨港
    "yeshou":     (-7.5,  110.4),   # 阇婆/爪哇
    "bassein":    (16.78,  94.74),  # 勃生 (伊洛瓦底江海口中转)
    "zhenla":     (10.5,   107.0),  # 真腊 (湄公河口/Prey Nokor，吴哥帝国海上门户)
    "xianluo":    (14.7,   100.6),  # 暹罗 (华富里/Lavo，湄南河流域，素可泰时代)
    "mayi":       (13.0,   120.5),  # 麻逸 (民都洛，菲律宾，诸蕃志载麻逸国)
    "boni":       (4.9,    114.9),  # 渤泥 (文莱，婆罗洲北岸，南海东南贸易节点)
}

# Irrawaddy river waypoints bugan->bassein (lat,lon), excludes endpoints.
IRRAWADDY_WAYPOINTS: list[tuple[float, float]] = [
    (20.88, 94.85),   # 卓 Chauk
    (20.15, 94.93),   # 马圭 Magway
    (18.84, 94.83),   # 卑谬 Pyay
    (17.90, 95.46),   # 兴实达 Hinthada (江道东拐)
    (16.90, 95.05),   # 三角洲分汊
]


def project(lat: float, lon: float) -> tuple[float, float]:
    return round((lon - 92) / 42, 3), round((42 - lat) / 52, 3)


def uv_to_world(u: float, v: float, wb: dict) -> dict[str, int]:
    x_min, x_max = wb["x_min"], wb["x_max"]
    y_min, y_max = wb["y_min"], wb["y_max"]
    return {
        "x": int(x_min + u * (x_max - x_min)),
        "y": int(y_min + v * (y_max - y_min)),
    }


def main() -> None:
    data = json.loads(PORTS.read_text(encoding="utf-8"))
    # world_bounds + texture/sea_mask (single source for map meta)
    data["meta"]["map_layout"]["world_bounds"] = WORLD_BOUNDS
    data["meta"]["map_layout"]["texture"] = MAP_TEXTURE
    data["meta"]["map_layout"]["sea_mask"] = MAP_SEA_MASK
    wb = data["meta"]["map_layout"]["world_bounds"]
    ports = data["ports"]
    by_id = {p["id"]: p for p in ports}

    # 1. 新增港 (bassein 河口中转 + 4 港填区域空白)
    NEW_PORTS: list[dict] = [
        {"id": "bassein", "name": "勃生", "region": "缅甸海口", "status": "distant",
         "tags": ["河海中转", "象牙玉石", "驳船"], "connections": ["bugan", "champa", "longyamen"],
         "bg": "res://assets/bg_bugan_port.png"},
        {"id": "zhenla", "name": "真腊", "region": "中南半岛", "status": "distant",
         "tags": ["吴哥", "湄公河", "象牙", "沉香"], "connections": ["champa", "jiaozhi", "xianluo"],
         "bg": "res://assets/bg_champa_port.png"},
        {"id": "xianluo", "name": "暹罗", "region": "中南半岛", "status": "distant",
         "tags": ["素可泰", "湄南河", "象牙", "犀角"], "connections": ["zhenla", "champa", "longyamen"],
         "bg": "res://assets/bg_champa_port.png"},
        {"id": "mayi", "name": "麻逸", "region": "吕宋海面", "status": "distant",
         "tags": ["菲律宾", "吕宋", "珍珠", "槟榔"], "connections": ["keelung", "boni", "quanzhou"],
         "bg": "res://assets/bg_keelung_port.png"},
        {"id": "boni", "name": "渤泥", "region": "婆罗洲", "status": "distant",
         "tags": ["文莱", "婆罗洲", "龙脑", "胡椒"], "connections": ["mayi", "yeshou", "longyamen"],
         "bg": "res://assets/bg_yeshou_map.png"},
    ]
    for np in NEW_PORTS:
        if np["id"] not in by_id:
            ports.append(np)
            by_id[np["id"]] = np
        else:
            by_id[np["id"]]["connections"] = np["connections"]  # 幂等同步连接

    # 2. 蒲甘远洋连接转给勃生 (内陆港只连河口；仅首次迁移)
    bugan = by_id["bugan"]
    bassein = by_id["bassein"]
    ocean = [c for c in bugan.get("connections", []) if c != "bassein"]
    if ocean:  # bugan 仍有远洋连接 → 迁移到 bassein；已迁移则跳过
        bugan["connections"] = ["bassein"]

    # 3. 其他港 connections: bugan -> bassein
    for p in ports:
        if p["id"] in ("bugan", "bassein"):
            continue
        p["connections"] = ["bassein" if c == "bugan" else c for c in p.get("connections", [])]

    # 4. map_pos + position
    for port in ports:
        pid = port["id"]
        if pid not in MAP_POS:
            continue
        u, v = project(*MAP_POS[pid])
        port["map_pos"] = {"u": u, "v": v}
        port["position"] = uv_to_world(u, v, wb)

    # 5. 伊洛瓦底江河道折线 (绘制层专用)
    bugan["river_routes"] = [{
        "to": "bassein", "type": "river",
        "waypoints": [{"u": u, "v": v} for u, v in (project(*wp) for wp in IRRAWADDY_WAYPOINTS)],
    }]

    PORTS.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # 6. 自检
    us = [p["map_pos"]["u"] for p in ports if "map_pos" in p]
    vs = [p["map_pos"]["v"] for p in ports if "map_pos" in p]
    assert all(0.0 <= u <= 1.0 and 0.0 <= v <= 1.0 for u, v in zip(us, vs)), "uv out of [0,1]"
    assert bassein["connections"][0] == "bugan", "bassein must connect bugan"
    assert bugan["connections"] == ["bassein"], "bugan must connect only bassein"
    print(f"synced {len(ports)} ports  u:[{min(us):.3f}..{max(us):.3f}]  v:[{min(vs):.3f}..{max(vs):.3f}]")
    print(f"bassein: {bassein['map_pos']}  conn={bassein['connections']}")
    print(f"bugan:   {bugan['map_pos']}  conn={bugan['connections']}  river_wp={len(IRRAWADDY_WAYPOINTS)}")
    print(f"bugan->bassein waypoints: {bugan['river_routes'][0]['waypoints']}")


if __name__ == "__main__":
    main()
