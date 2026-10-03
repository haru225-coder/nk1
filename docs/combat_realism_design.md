# 海战写实设计（lane combat01）
> 南宋末 / 东亚近海战术层海战契约。本文件只落**设计与数据约定**；逐帧实现归 combat02–09，门禁与探针归 combat10。
- 时代：南宋末，约1255-1279，东亚近海
- 版本：1 · lane `combat01`
- 数据：`data/combat_phases.json` / `data/weapons.json` / `data/combat_sea_state.json`
- 字段说明：[`combat_phases_schema.md`](combat_phases_schema.md)

## 一、问题与目标

现有海战偏街机：耐久对轰 + 简单接舷比拼。目标改成更接近宋元近海的写实战：风流舷向、矢石有飞时与弹药定额、船体分系统损伤与浸水失火、接舷白刃多合、士气溃逃降幡、敌将有战术意图。本 lane 给出共用阶段图、兵器表与海况词表，让其它 9 路有稳定接口可挂。

## 二、阶段图（遭遇 → 机动 → 舷炮 → 接舷 → 白刃 → 缴获 / 溃逃）

| seq | id | 名 | 可弃战 | 可开火 | 摘要 |
|---|---|---|---|---|---|
| 1 | `encounter` | 遭遇 | 是 | 否 | 遭遇 |
| 2 | `maneuver` | 机动 | 是 | 是 | 机动 |
| 3 | `broadside` | 舷炮 | 是 | 是 | 矢石 |
| 4 | `grapple` | 接舷 | 否 | 否 | 接舷 |
| 5 | `melee` | 白刃 | 否 | 否 | 白刃 |
| 6 | `capture` | 缴获 | 是 | 是 | 缴获 |
| 6 | `rout` | 溃逃 | 是 | 是 | 溃逃 |

转移边表 `transitions`（谓词取 `queries`）：

| id | from → to | 谓词 |
|---|---|---|
| `t_player_sunk` | `['*'] → end` | {'q': 'flagship_sunk', 'op': '==', 'v': True} |
| `t_player_strikes` | `['*'] → end` | {'q': 'order', 'op': '==', 'v': 'strike_colors'} |
| `t_flee_ok` | `['encounter', 'maneuver', 'broadside', 'capture', 'rout'] → end` | {'q': 'flee_roll', 'op': '==', 'v': 'ok'} |
| `t_flee_caught` | `['encounter', 'maneuver', 'broadside', 'capture', 'rout'] → end` | {'q': 'flee_roll', 'op': '==', 'v': 'caught'} |
| `t_deck_lost` | `['melee'] → end` | {'q': 'melee_attacker', 'op': '==', 'v': 'enemy'}, {'q': 'melee_state', 'op': '==', 'v': 'attacker_won'} |
| `t_deck_taken` | `['melee'] → capture` | {'q': 'melee_attacker', 'op': '==', 'v': 'player'}, {'q': 'melee_state', 'op': '==', 'v': 'attacker_won'} |
| `t_deck_held` | `['melee'] → broadside` | {'q': 'melee_state', 'op': '==', 'v': 'defender_held'} |
| `t_hook_held` | `['grapple'] → melee` | {'q': 'grapple_state', 'op': '==', 'v': 'held'} |
| `t_hook_lost` | `['grapple'] → broadside` | {'q': 'grapple_state', 'op': 'in', 'v': ['failed', 'cut']} |
| `t_enemy_struck` | `['maneuver', 'broadside', 'rout'] → capture` | {'q': 'struck_pending', 'op': '>=', 'v': 1} |
| `t_field_clear` | `['maneuver', 'broadside', 'rout'] → end` | {'q': 'enemy_alive', 'op': '==', 'v': 0} |
| `t_capture_end` | `['capture'] → end` | {'q': 'capture_done', 'op': '==', 'v': True}, {'q': 'enemy_alive', 'op': '==', 'v': 0} |
| `t_capture_more` | `['capture'] → maneuver` | {'q': 'capture_done', 'op': '==', 'v': True} |
| `t_hook_start` | `['encounter', 'maneuver', 'broadside', 'rout'] → grapple` | {'q': 'grapple_state', 'op': '==', 'v': 'closing'} |
| `t_enemy_routs` | `['maneuver', 'broadside'] → rout` | {'q': 'enemy_side_morale', 'op': '==', 'v': 'broken'} |
| `t_player_routs` | `['maneuver', 'broadside'] → rout` | {'q': 'own_side_morale', 'op': '==', 'v': 'broken'} |
| `t_enemy_escaped` | `['rout'] → end` | {'q': 'routing_side', 'op': '==', 'v': 'enemy'}, {'q': 'escape_bu', 'op': '>=', 'v': '$escape_bu'} |
| `t_let_go` | `['rout'] → end` | {'q': 'routing_side', 'op': '==', 'v': 'enemy'}, {'q': 'order', 'op': '==', 'v': 'let_go'} |
| `t_player_escaped` | `['rout'] → end` | {'q': 'routing_side', 'op': '==', 'v': 'player'}, {'q': 'escape_bu', 'op': '>=', 'v': '$escape_bu'} |
| `t_rallied` | `['rout'] → maneuver` | {'q': 'routing_side', 'op': '==', 'v': 'none'} |
| `t_encounter_fire` | `['encounter'] → broadside` | {'q': 'phase_elapsed_s', 'op': '>=', 'v': '$encounter_s'}, {'q': 'weapons_bear', 'op': '==', 'v': True} |
| `t_encounter_move` | `['encounter'] → maneuver` | {'q': 'phase_elapsed_s', 'op': '>=', 'v': '$encounter_s'} |
| `t_open_fire` | `['maneuver'] → broadside` | {'q': 'weapons_bear', 'op': '==', 'v': True} |
| `t_cease_fire` | `['broadside'] → maneuver` | {'q': 'out_of_range_s', 'op': '>=', 'v': '$range_hysteresis_s'} |
| `t_time_up` | `['encounter', 'maneuver', 'broadside', 'rout'] → end` | {'q': 'battle_elapsed_s', 'op': '>=', 'v': '$battle_limit_s'} |
| `t_gale` | `['encounter', 'maneuver', 'broadside'] → end` | {'q': 'wind_combat_ok', 'op': '==', 'v': False} |

## 三、系统归属（systems）

| id | 职责 | 落地 lane |
|---|---|---|
| `director` | 阶段机 | combat10 |
| `maneuver_model` | 操船海况 | combat02 |
| `ballistics` | 弹道 | combat03 |
| `reload_ammo` | 装填与矢石 | combat03 |
| `damage_model` | 损伤 | combat04 |
| `flood_fire` | 水火 | combat04 |
| `melee_resolve` | 钩连白刃 | combat05 |
| `combat_morale` | 战时士气 | combat06 |
| `captain_ai` | 敌将 | combat07 |
| `orders_ui` | 指令 | combat08 |
| `status_hud` | 状态条 | combat08 |
| `combat_fx` | 观感 | combat09 |
| `letterbox` | 出战题签 | combat09 |

## 四、海况词表（combat_sea_state）

战术层海况的共用词表与缺省。风级名取唐李淳风《乙巳占》八级，另加静风；风力 wind_strength = 级 × 20，与 Ship.wind_strength、SeaState.wind_speed 同单位（现行海战固定 80 = 四级），也合 CombatStatusHud「风力 ÷ 20 取级」。方位角 0=北 90=东、顺时针；风向叫法按来向（东北风 = 从东北吹来），数值 toward_deg 取吹向，与 Calendar.wind_bearing_of、SeaState.wind_to 同口径。海况的逐帧推演（风向缓转、阵风、洋流、潮流）归 scripts/combat/SeaState.gd（combat02），它在时以它为准；本表给名目、档位与 SeaState 不在时的回落。设计与字段说明见 docs/combat_realism_design.md、docs/combat_phases_schema.md。

风级（唐李淳风《乙巳占》八级 + 静风）：

| id | 名 | 级 | wind_strength |
|---|---|---|---|
| `jing` | 静 | 0 | 0 |
| `dongye` | 一级・动叶 | 1 | 20 |
| `mingtiao` | 二级・鸣条 | 2 | 40 |
| `yaozhi` | 三级・摇枝 | 3 | 60 |
| `duoye` | 四级・堕叶 | 4 | 80 |
| `zhexiaozhi` | 五级・折小枝 | 5 | 100 |
| `zhedazhi` | 六级・折大枝 | 6 | 120 |
| `zhemu` | 七级・折木飞沙 | 7 | 140 |
| `bashu` | 八级・拔树 | 8 | 160 |

缺省（零改动回落）：`{"wind_from": "n", "wind_level": "duoye", "current": "slack", "tide": "man", "tide_amplitude": "zhongchao", "waters": "rumb", "weather": "clear", "shore_deg": 270, "note": "零改动回落：WorldMap 旧海战 wind_vector = Vector2(0, 1)（吹向南 = 北风）、wind_strength = base_wind_strength 80（= 四级・堕叶）、固定晴。SeaState 模块不在、或 pending_battle 不带 sea_state 时用它"}`

方位：0=北 90=东顺时针；风向叫法按**来向**，数值 `toward_deg` 取**吹向**，与 `Calendar.wind_bearing_of` / `SeaState.wind_to` 同口径。距离单位步：1 步 = 8 px（见 `combat_phases.scale`）。

## 五、兵器与矢石（weapons）

宋元近海海战以弓弩矢石为主，床子弩、抛石的旋风炮只上大船，火药兵器是火箭、火炮（火药包）、火毬、火枪（竹筒喷火）一类，数量有限；金属管的火铳这一期船上还没有（见 not_in_era）。本表的「炮」一律指抛石机，不是后世火炮。本表是兵器目录与各船默认武备：射程、装填、人手、存量、年代与特效。命中后的伤害怎么分到船体、帆、舵、人手、漏、火，归 scripts/combat/DamageModel.gd（combat04，按 ammo.damage_kind 取 KINDS）；弹道与装填的逐帧实现归 scripts/combat/Ballistics.gd、ReloadAmmo.gd（combat03，按 ammo.pool 与 weapons.impl_id 对照）；本表数值与这些模块自带常量有出入的，列在设计文档的对齐表。距离单位步（1 步 = 8 px，见 data/combat_phases.json 的 scale）。

| id | 名 | 种 | 射程(步 min/eff/max) | 装填(s) | 人手 |
|---|---|---|---|---|---|
| `gong` | 步弓 | hand | 0/45/80 | 3.0 | 5 |
| `nu` | 弩 | hand | 0/70/120 | 6.0 | 5 |
| `chuangnu` | 床子弩 | mounted | 0/110/180 | 18.0 | 7 |
| `xuanfeng_pao` | 旋风炮 | engine | 12/45/70 | 12.0 | 16 |
| `shou_zhi` | 手掷 | thrown | 0/7/11 | 5.0 | 1 |
| `huoqiang` | 火枪 | contact | 0/2/3 | 0.0 | 1 |
| `tu_huoqiang` | 突火枪 | hand | 0/15/30 | 20.0 | 2 |
| `feigou` | 飞钩 | grapple | 0/10/12 | 4.0 | 2 |
| `zao_chuan` | 凿船 | special | 0/2/4 | 10.0 | 2 |

本表「炮」一律指抛石机。金属管火铳列在 `not_in_era`。命中后的分系统伤害归 DamageModel（combat04）；飞行与装填归 Ballistics / ReloadAmmo（combat03）。

## 六、接舷白刃与士气

白刃参数见 `combat_phases.json` → `melee`（钩连 reach / 相对速度折算、甲板多合、伤亡与溃退）。仓外粗算见 wave 证据 `/tmp/nk1-combat-wave1/combat01/sim_melee.py`。

士气状态：

- `steady`：稳 — 
- `shaken`：动摇 — 
- `broken`：溃 — 
- `struck`：降 — 

细表与阈值以 `data/combat_morale.json`（combat06）为准；本文件只列阶段侧可见的状态名。

## 七、结局与题签

| id | 名 | 说明 |
|---|---|---|
| `enemy_captured` | 夺船 | 现码 CombatFx.board_win_note 同句；末船夺下当帧 _battle_exit(win, boarded=true)，combat11 已清 KNOWN_DEFECTS |
| `enemy_struck` | 敌降 | combat09+11+12 已接：士气收场 morale_verdict=enemy_struck → 题签 surrender「受降」，SeaChart 全赏走 sea_surrender_note；legacy_data.boarded 与实发不符（见§九） |
| `enemy_sunk` | 击沉 | SeaChart 胜：赏 150–600 钱、名声 +3、士气 +5（现码） |
| `enemy_fled` | 敌遁 | combat12 已接：WorldMap 收战把各船下场（沉 / 夺 / 受降 / 遁）记进 win data.fates，SeaChart.win_kind 只在一艘没沉没夺没降、只是遁走时半赏 75–300 走 sea_fled_note，先沉后遁照击沉全赏；题签现码出 repel「击退」，非本表 win（见§九） |
| `player_fled` | 脱战 | 现码 CombatFx.sea_flee_ok_note 同句 |
| `player_caught` | 未能甩脱 | 现码 CombatFx.sea_flee_fail_note 同句 |
| `player_routed` | 溃逃 | combat09+11 已接：CombatMorale 我方溃逃满 player_grace_s → flee{rout, morale_verdict=player_rout} → 题签 rout「溃逃」；SeaChart 仍走通用 flee 分支，flee_ok 由士气件掷骰（见§九） |
| `player_struck` | 降幡 | combat11 已接：CombatMorale 我方降幡 → lose{struck}，题签现码出 yield「请降」，非本表 strike；SeaChart 走败局非沉船分支：货损二成五，log 出 sea_board_lose_note（见§九） |
| `player_overrun` | 失船面 | lane w53-2 已接：敌船先抛钩（PirateShip.boarding_initiator）时 WorldMap._board_enemy 敌攻我守，白刃敌胜即此（转移 t_deck_lost）→ lose{overrun}，接舷题签「失守」、出战题签 lose「败退」；SeaChart 走败局非沉船分支：货损二成五，log 出 sea_board_lose_note（文案同） |
| `player_sunk` | 旗舰沉没 | 现码 CombatFx.sea_sunk_note 同向 |
| `disengaged` | 两散 | combat12 已接（限时一路）：WorldMap 开战满 thresholds.battle_limit_s（300 秒，开战时读本文件；接舷白刃中不计时）→ flee{flee_ok, parted} → 题签 parted「两散」，SeaChart sea_parted_note 与本条 log 同句，不给赏、不绕路；t_gale 一路无来路（见§九） |

与现行 `battle_finished(outcome, data)` 对照写在各 outcome 的 `legacy` 字段；combat09 出战题签按事由取朱印，combat11 起 `WorldMap._battle_exit` 把 data（含士气收场的 `morale_verdict`）原样递给 `CombatLetterbox.exit_for`；combat12 补上敌遁半赏与两散。

## 八、文案口径

上屏文案：纪实短句，不用叹号；不写「玩家」，写我船、本队；用宋代叫法（碇、针盘、纲首、舵工），不写拔锚、罗盘；「炮」指抛石机

## 九、对齐与待接线

已接、不再列：combat11 清空 combat10 `KNOWN_DEFECTS`（夺末船 `boarded=true`、`player_damage` 负值、回写）；敌降「受降」、我方溃逃「溃逃」由 combat09+11 接；敌遁半赏（按各船下场分账，先沉后遁不算敌遁）、限时两散由 combat12 接；失船面（敌船先抛钩、白刃敌胜 → `lose{overrun}`）由 lane w53-2 接。下列是仍未对上的：

- **两散只有限时一路**：阶段图 `t_gale`（风七级以上不能战 → `disengaged`）不收场——`SeaState` 把海战风力封顶在 `WIND_CAP` 130，到不了 `combat_ok: false` 那几级，此路暂无来路。
- **题签键与本表不符**：`player_struck` 本表 `strike`「降幡」，现码出 `yield`「请降」（`strike` 不在 `OUTCOME_ACT`）；`enemy_fled` 本表 `win`「战罢」，现码出 `repel`「击退」。二者择一回写。
- **SeaChart 我方失利不分结局**：我方降幡走败局非沉船分支，log 出 `sea_board_lose_note`「白刃不利」而非本条降幡句；溃逃走通用 flee 分支，不出本条句。士气也不按 `morale_hint`：降幡照败局扣 12（本表 −6），溃逃 flee 分支不扣（本表 −8）。
- **`legacy_data` 与实发 data 不符**：`enemy_struck` 本表带 `boarded: true`，实发 `enemy_struck` / `struck_types` / `morale_verdict`，不带 `boarded`；`player_routed` 本表 `flee_ok: true`，实发由士气件掷骰。
- **本表几乎无玩法代码读**：`morale_hint`、`spoil_rule`、`log`、`precedence` 与 `thresholds`（除 `battle_limit_s`：WorldMap 开战时读，读不到退回 `BATTLE_LIMIT_S` 300）目前只是契约；SeaChart 赏罚与士气写死（敌遁半赏也是 SeaChart 里的 75–300，不读 `spoil_rule`），`CombatDirector` 只查本文件在不在。

数值与实现常量若有出入，以落地模块为准，回写本表时开对齐行。

---

*lane combat01 契约 · combat11/12 接线回写 · 勿 push · 数据基线见 wave1 validate_schema。*
