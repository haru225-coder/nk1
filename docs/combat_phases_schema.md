# 海战数据字段说明（lane combat01）
> 三份 JSON 的字段契约。实现方按表读写；改字段先改本说明与 `validate_schema.py` 变异。

## 0. 共用约定

- 编码 UTF-8；顶层必有 `meta`（`title` / `era` / `version` / `lane` / `note`）。
- id 唯一非空字符串；同表条目之间不互指（转移另立 `transitions` 边表）。
- 上屏文案禁：叹号、现代腔工程词、「玩家」「罗盘」「拔锚」「炮弹」。
- 距离：步；1 步 = `combat_phases.scale.px_per_bu`（现行 8）px。
- 普查：三份均作 F1 首张 id 表；F2 无自引用（`check_data_family` 口径）。

## 1. `data/combat_phases.json`

战术层海战（WorldMap）的共用契约：阶段 phases 与转移 transitions（边表，谓词取 queries）、门限 thresholds、指令 orders、水手岗位与分派、职事加成、钩连与白刃参数、敌将意图与性情、结局 outcomes（含与现行 battle_finished 的对照）、事件 cues、状态条字段 hud_fields、各系统归属 systems。阶段顺序：遭遇→机动→舷炮→接舷→白刃→缴获/溃逃。设计见 docs/combat_realism_design.md，逐字段说明见 docs/combat_phases_schema.md。同表条目之间不互指（转移另立 transitions 边表），跨表、跨文件引用由字段说明列明。

### 1.1 顶层键

| 键 | 含义 |
|---|---|
| `scale` | dict · 4 条 |
| `phases` | list · 7 条 |
| `transitions` | list · 27 条 |
| `thresholds` | dict · 18 条 |
| `queries` | list · 25 条 |
| `resolve` | dict · 3 条 |
| `systems` | list · 13 条 |
| `subsystems` | list · 7 条 |
| `fire_model` | dict · 8 条 |
| `flood_model` | dict · 9 条 |
| `casualty_rules` | dict · 4 条 |
| `crew_duties` | list · 8 条 |
| `crew_allocs` | list · 7 条 |
| `alloc_rules` | dict · 6 条 |
| `orders` | list · 30 条 |
| `key_rules` | dict · 3 条 |
| `officer_effects` | list · 6 条 |
| `melee` | dict · 24 条 |
| `morale_states` | list · 4 条 |
| `morale_note` | str |
| `intents` | list · 11 条 |
| `captains` | list · 3 条 |
| `captain_rules` | list · 3 条 |
| `outcomes` | list · 11 条 |
| `cues` | list · 38 条 |
| `hud_fields` | list · 16 条 |
| `spoil` | dict · 5 条（lane w53-16 起由 SeaChart 实况读） |

### 1.2 `phases[]`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | — | string |
| `seq` | — | int 1..6（缴获/溃逃同为 6） |
| `name` | — | 上屏短名 |
| `short` | — | 更短标签 |
| `summary` | — | 阶段摘要 |
| `enter_copy` | — | 进入题签 |
| `can_flee` | — | bool 可否弃战 |
| `fire_allowed` | — | bool 可否开火 |
| `orders` | — | string[] 本阶段可用令（∈ orders.id） |
| `systems` | — | string[] 本阶段相关系统 |
| `hud` | — | string[] 状态条字段 |
| `intents` | — | 敌将可用意图 |
| `camera` | — | 镜头提示 |
| `legacy` | — | 与旧 WorldMap 行为对照 |

### 1.3 `transitions[]`

| 字段 | 说明 |
|---|---|
| `id` | 边 id |
| `from` / `to` | 阶段 id |
| `when` / `query` | 谓词，取 `queries[].id` 或内联 |

### 1.4 `orders[]` / `crew_duties` / `crew_allocs`

令 id 供 combat08 号令面板；`crew_allocs[].shares` 合计须为 1。岗位 id 对照 `data/crew.json`。

### 1.5 `melee` / `morale_states` / `outcomes` / `cues` / `hud_fields`

- `melee`：钩连 reach_bu、相对速度折算、多合参数、伤亡与溃退检定。
- `morale_states`：阶段侧可见状态名；阈值见 combat06。
- `outcomes`：须覆盖现行 `battle_finished` 的 win/lose/flee 及夺船/受降/溃逃扩展；`flee` 类须带 `flee_ok`（SeaChart 读）。
- `cues`：短注 id → 上屏 copy。
- `hud_fields`：状态条字段 id，供 combat08。

### 1.6 `thresholds` / `queries` / `resolve`

门限数值（如 `BOARD_DISTANCE` 对齐 WorldMap 140 px）；`queries` 是转移谓词的命名口；`resolve` 描述各结局如何收束到 `battle_finished`。

### 1.7 `spoil`（分赃规则 · lane w53-16 起由 SeaChart 实况读）

| 键 | 说明 |
|---|---|
| `base` | `[150, 600]` 整场赏钱的基区（钱）。方案一页结论 3：赏钱跟打法挂钩 |
| `by_fate` | 各下场（`struck` / `sunk` / `burned` / `fled` / `boarded`）的乘率：击沉 / 焚毁 1/3、遁走 1/2、逼降全赏 1.0、夺船 0（船本身就是赏，不给钱）；混编按下场加权（方案落地：`SeaChart._spoil_by_outcome`） |
| `zashi_spoil_mul_per_level` | 职事「杂事缴获」每级的加赏倍率（0.1）；`officer_effects.zashi.spoil_mul` 0.05 乘二——槽面写一成更顺嘴（方案 §六：「下了锚得好货，杂事会点，多卖一成」） |
| `captured_money` | 夺船给船不另加钱（0） |
| `note` | 口径注记 |

读不到本节（json 打不开、spoil 缺节、base 不足两档）SeaChart 退回旧区间：全灭 150–600 / 敌逃 75–300（legacy）。

## 2. `data/weapons.json`

宋元近海海战以弓弩矢石为主，床子弩、抛石的旋风炮只上大船，火药兵器是火箭、火炮（火药包）、火毬、火枪（竹筒喷火）一类，数量有限；金属管的火铳这一期船上还没有（见 not_in_era）。本表的「炮」一律指抛石机，不是后世火炮。本表是兵器目录与各船默认武备：射程、装填、人手、存量、年代与特效。命中后的伤害怎么分到船体、帆、舵、人手、漏、火，归 scripts/combat/DamageModel.gd（combat04，按 ammo.damage_kind 取 KINDS）；弹道与装填的逐帧实现归 scripts/combat/Ballistics.gd、ReloadAmmo.gd（combat03，按 ammo.pool 与 weapons.impl_id 对照）；本表数值与这些模块自带常量有出入的，列在设计文档的对齐表。距离单位步（1 步 = 8 px，见 data/combat_phases.json 的 scale）。

### 2.1 顶层键

| 键 | 含义 |
|---|---|
| `weapons` | list · 9 |
| `ammo` | list · 16 |
| `ammo_pools` | list · 6 |
| `mounts` | list · 6 |
| `hull_builds` | list · 4 |
| `loadouts` | list · 7 |
| `ship_fits` | list · 8 |
| `ship_fit_rule` | str |
| `sprite_loadouts` | list · 1 |
| `slot_rule` | dict · 11 |
| `hit_rules` | dict · 12 |
| `not_in_era` | list · 5 |

### 2.2 `weapons[]` 主要字段

| 字段 | 说明 |
|---|---|
| `id` / `name` / `kind` | 标识、上屏名、种类 |
| `range_bu` | `{min,eff,max}` 步 |
| `cycle_s` | 装填周期（战术秒） |
| `hands` / `duty` | 人手、岗位 |
| `ammo` | 可用矢石 id 列表 |
| `mount` / `impl_id` | 安装位、实现对照（Ballistics） |
| `trajectory` / `spread_deg` / `wind_mul` | 弹道形、散布、风偏 |
| `availability` / `era_from` | 可得性、入役年 |

### 2.3 `ammo` / `ammo_pools` / `loadouts` / `ship_fits`

- `ammo[].damage_kind` → DamageModel.KINDS。
- `ammo_pools`：船上定额池；告急 / 弹尽行为归 ReloadAmmo。
- `loadouts`：编制预设（如 `pirate_kuaichuan`）；矢石须有兵器用得上。
- `ship_fits`：与 `data/ships.json` 船型一一对上。
- `not_in_era`：本期不上船的兵器（如金属管火铳），只作注释。

## 3. `data/combat_sea_state.json`

战术层海况的共用词表与缺省。风级名取唐李淳风《乙巳占》八级，另加静风；风力 wind_strength = 级 × 20，与 Ship.wind_strength、SeaState.wind_speed 同单位（现行海战固定 80 = 四级），也合 CombatStatusHud「风力 ÷ 20 取级」。方位角 0=北 90=东、顺时针；风向叫法按来向（东北风 = 从东北吹来），数值 toward_deg 取吹向，与 Calendar.wind_bearing_of、SeaState.wind_to 同口径。海况的逐帧推演（风向缓转、阵风、洋流、潮流）归 scripts/combat/SeaState.gd（combat02），它在时以它为准；本表给名目、档位与 SeaState 不在时的回落。设计与字段说明见 docs/combat_realism_design.md、docs/combat_phases_schema.md。

### 3.1 顶层键

| 键 | 含义 |
|---|---|
| `compass` | list · 8 |
| `wind_levels` | list · 9 |
| `wind_level_rule` | str |
| `monsoon_defaults` | list · 3 |
| `waters` | list · 4 |
| `currents` | list · 5 |
| `tides` | list · 4 |
| `tide_amplitude` | list · 3 |
| `sail_polar` | list · 3 |
| `sail_polar_rule` | str |
| `weather` | list · 5 |
| `defaults` | dict · 9 |
| `derive` | dict · 6 |

### 3.2 关键枚举

- `compass[]`：八方 + 别名；`toward_deg` 吹向。
- `wind_levels[]`：`level` 0..8 连号；`wind_strength = level × 20`。
- `monsoon_defaults`：须与 `Calendar` 季风吹向常量一致。
- `waters` / `currents` / `tides` / `tide_amplitude` / `sail_polar` / `weather`：水域、流、潮候、帆型极曲线、天气。
- `defaults`：SeaState 不在时的回落（现行北风四级晴）。

## 4. 校验

```sh
python3 /tmp/nk1-combat-wave1/combat01/validate_schema.py /tmp/nk1-combat01 --mutants
# 期望：基线全过 + 变异 14/14 判红
```

入库后把校验脚本收进 `tools/` 或并入 `check_data_family` 登记表（不在本 lane 强制范围；交后续 hygiene）。

---

*lane combat01 · 与三份 JSON 同车落地。*
