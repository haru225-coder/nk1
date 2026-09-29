# 海战船身观感与命中手感（lane ship-vfx）

宋元近海，俯视 2D。船仍是 `Sprite2D` + 船图契约（`assets/ship_<id>.png`，512² RGBA，船首朝 -y），不做 3D 网格。
俯视指海面镜头。船身是 `assets/ships/song_quanzhou.glb` 里的同一条泉州湾宋船（一层甲板、尖底、低干舷、竹席硬篷），由 `scripts/combat/ShipHull3D.gd` 按航向转网格，不自旋一张船图。敌我只差帆色。`ship_fu.png` / `ship_falcon.png` 只是契约用的一张朝向。
一句话：**挨打的是船**——一发砲石打中，是那条船自己一记炽橙、一颤、留下焦痕；镜头只在本船挨打或本船齐射时动；
出手与命中都是短促、有形的分拍，不用软白晕。

## 分工（同一条船上三条线，各管一层，不叠）

| 层 | 归谁 | 件 |
|---|---|---|
| 投影、贴舷白浪、受光 / 背光、横摇纵摇 | combat12-E | `scripts/combat/ShipLook.gd`（HullWater / HullLight 两层，摇曳写 `Sprite2D.offset`） |
| 海面、航迹白练、敌船朱边、旗旒、涟漪、接舷镜头 | lane atmos | `scripts/combat/SeaAtmosphere.gd`、`SeaWake.gd`、`sea_surface.gdshader`、`hull_rim.gdshader` |
| 帆抖、命中一闪、焦痕、船身一颤、齐射 / 命中 / 落水 / 沉船的粒子、本船镜头与屏幕一拍、沉船残影 | 本 lane | `scripts/combat/CombatFx.gd`、`ship_seagoing.gdshader`、`screen_kick.gdshader`、`ImpactExplosion.tscn`、`WaterSplash.tscn` |

船下旧的 `WakeParticles`（软圆点尾迹）由本 lane 的 `FxLook` 隐藏（节点保留），航迹只剩 SeaWake 一条。

## 一、船身（`CombatFx.dress_ship`，Ship / PirateShip `_ready` 调）

- `assets/shaders/ship_seagoing.gdshader`（船图材质）：帆篷微抖只抖奶油硬帆 / 绛红帆色域；午后暖 rim；
  命中处一记炽橙（`hit`，按轻重定半径、逐帧衰减）；焦痕 `scars`（最多 6 处，参差焦黑 + 一圈新茬，随船到终场）；
  modulate / self_modulate（降幡发灰、进水压暗）照乘。
- `FxLook`（`CombatFx._Look`）：写 `hit` / `scars`；旗舰挂屏幕一拍 `ScreenKick`；隐藏 `WakeParticles`。
- 一颤：`hull_shudder` 的 scale / rotation 补间（ShipLook 两层在 frame_pre_draw 抄变换，跟得上）。
- 船图由 `tools/cut_ship_sprites.py` 出，**不再烤水线压影与艏部白沫弧**（`BAKE_WATERLINE = False`）：那道灰弧悬在船头前方、
  烤影随船转，成一圈灰晕；投影与白浪由 ShipLook 实时画。

## 二、命中与齐射（分拍）

贴图 `tools/art/build_combat_fx.py` 出（`assets/fx/`）：`smoke_puff`（菜花形烟团）、`flash_star`（七叉星芒）、
`spark_streak`（火星拖线，粒子开 `align_y`）、`splinter`（参差木屑）、`water_drop`（溅滴）、`foam_ring`（断续白沫环）。
旧的 `glow_warm` / `mist_puff` / `soft_dot` 是高斯软圆，放大当焰、当烟即一团白光——齐射、命中、落水、沉船都不再用。

| 事 | 拍子 |
|---|---|
| 齐射出手 `muzzle_flash` | 每炮位一记星芒（橙黄、顺出手方向拉长，约 0.1 s）+ 白芯 + 火星拖线 + 一小团火药烟（往外推开、鼓大、约 1.9 s 散尽）；船身往反舷一坐；本船镜头反舷推 11 px（旧 30 px 硬甩已去） |
| 矢石命中 `on_missile_hit` | 落点星芒（外层常规混合炽橙——落在奶油帆上也看得见，芯加色）；stone 木屑 + 木尘 + 舷边溅水；bolt 木屑少；fire 火星拖线 + 焦烟；bomb 大一号星芒 + 火星 + 木屑 + 火药烟 |
| 船身挨打 `hull_impact`（Cannonball 交完杀伤后调，敌我同一支） | 命中处一记炽橙、往背着来力的一舷一颤、砲石 / 火器 / 重的留焦痕。挂了 FxLook 的船不再用 modulate 闪红 |
| 本船挨打（`own_hit`） | 镜头顺来力推 5–19 px（`hit_severity`）+ 镜头收 0–3.6 %（约 1 s 缓回）；重的（≥ 0.6）加一拍屏幕错位（红蓝错位 + 四角一暗，约 0.15 s，HUD 不受影响）；combat12 的极短顿帧保留 |
| 落水 `WaterSplash.tscn` | 水柱溅滴顺速度拉长 + 一圈断续白沫环 + 一点水雾（SeaAtmosphere 另在海面上记涟漪） |
| 敌船沉没 `founder` | 船身残影（同贴图、同材质，焦痕都在）先压暗入水色、再歪倒没下去（约 1.8 s）+ 漂木、气泡；真节点照旧当帧释放，计数、结算零改动；大涟漪归 SeaAtmosphere |

打中敌船不动本船镜头（combat09 定的：远处看得见木屑，手上不该跟着抖）。

## 三、验

- 截图：`NK1_SHOT_DIR=<目录> DISPLAY=:2 godot --path . -s res://tools/ship_vfx_probe.gd`（6 张：远景 / 近景 / 齐射出手 / 本船中砲石 / 齐射打到敌船 / 敌船沉没）
- 契约：`godot --headless --path . -s res://tools/ship_vfx_probe.gd -- --contract`（接线、贴图在库、齐射 / 命中 / 落水不用软白晕贴图、齐射不再硬甩 30 px）

## 四、下一片（未做）

- 分船型真图（`ship_sampan` / `ship_pirate_boat` …）；帆损分级（焦帆洞、破帆）接 DamageModel.rig
- 焦痕按命中处是否在船体内取舍（落在舷外的因 alpha 为 0 看不见，但占一个槽位）
- `WorldMap._spawn_enemy` 按每条敌船条目各自从 `PirateShip_1` 起名，两条条目时第二批被引擎改名成 `@PirateShip_1@…`，
  落出所有 `begins_with("PirateShip")` 计数（HUD「存活」少算、胜负可能提前判）——不属本 lane，记给海战线
