# 出海福船观感 + 命中手感（combat-ship-vfx）

## 方向（宋元近海 · 俯视 2D）

不重做 3D 网格：旗舰 / 敌船仍是 `Sprite2D` + `assets/ship_fu.png` / `ship_falcon.png`（512² RGBA，船首朝 -y）。观感升格走三层：

1. **船身着装（dress）** — 接触阴影椭圆、午后暖 rim、帆布微抖（`ship_seagoing.gdshader`）
2. **航迹** — 已有 WakeParticles / BowWave 加色阶淡出与泡沫贴图，速度联动照旧
3. **命中手感** — 舷侧炮口焰（火药烟 + 暖闪）→ 本船中弹甲板颤（scale/roll）+ 镜头轻颤 + 木屑尘烟（CombatFx 既有）

气质：硬帆竹篾撑条、福船尖艏宽艉、砲石/火箭而非近代舰炮火球。色：旧木褐、帆篷米白 / 绛红、午后海面偏暖金。

## 本切片（已落）

| 件 | 作用 |
|---|---|
| `assets/shaders/ship_seagoing.gdshader` | 帆区微抖、暖 rim、轻微对比 |
| `CombatFx.dress_ship` / `muzzle_flash` / `hull_shudder` | 着装、炮口焰、甲板颤 |
| Ship / PirateShip 接线 | 开火 → 炮口焰；中弹 → 颤 |
| `tools/ship_vfx_probe.gd` | 截图门禁 |

## 下一片（未做）

- 手工重绘 `ship_fu` / 分船型 `ship_sampan` / `ship_pirate_boat` 真图
- 帆损分级贴图（焦帆洞、破帆）与 DamageModel.rig 联动
- 真正的 MeshInstance3D 福船（若美术排期）
- 海面反射 / 浸水吃水深的 sprite 裁切

## 海面（本切片一并重做）

旧 `ocean_shader.gdshader`：高频 sin 闪点 + 粗贴图混合，俯视战术图上像脏贴纸。
新写法：墨青 / 青绿分层涌浪（fbm）+ 细碎浪花 + 稀泥金高光；`WorldMap._sync_ocean_look` 按季风改 `wind_angle` / 涌速 / 沫量。贴图 `ocean_water.png` 只当色噪，可下一片换写意海纹图。
