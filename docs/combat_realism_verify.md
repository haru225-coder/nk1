# 写实海战冒烟探针：怎么跑、怎么读（lane combat10）

`tools/combat_realism_probe.gd` 是一支 headless 探针，验海战从「血条对轰」改写实（hali-combat-wave1，combat01–09）后的五块机制：风流机动、弹道·装填·缺弹、损伤·浸水·失火、接舷白刃、士气·溃逃；另外验剧情挂钩「遇盗 → 开战 → 夺船 → 回写」。哪块模块还没落地，那一块就记 **⚠ 跳过，不算通过**，判词行会写明跳过了哪几块。模块登记表、剧情锚点表在 `scripts/combat/CombatDirector.gd`，这个文件只做装配和探测，玩法代码不调它。

## 一、怎么跑

```sh
godot --headless --path . -s res://tools/combat_realism_probe.gd                          # 人读
godot --headless --quiet --path . -s res://tools/combat_realism_probe.gd -- --json          # 一行 JSON（tools/gate_report.gd）
godot --headless --path . -s res://tools/combat_realism_probe.gd -- --strict                # 跳过 / 已知缺陷一律判红
godot --headless --path . -s res://tools/combat_realism_probe.gd -- --only=melee,story       # 只跑几节，零节照跑
godot --headless --path . -s res://tools/combat_realism_probe.gd -- --mutants               # 零节逐支打印样本（缺省每组一行）
python3 tools/gate_json.py --native res://tools/combat_realism_probe.gd                     # 外包：超时、没 JSON 行也判红
```

`--only` 可选的节 id：`maneuver`（一）、`ballistics`（二）、`damage`（三）、`melee`（四）、`morale`（五）、`story`（六）、`census`（七）。不用 `DISPLAY`，不截图，不写存档。只改内存里的 Fleet、GameState 和 `GameManager.pending_battle`，跑完就还原。在本机实测一次约 3 秒。

改了下面这些文件的，照样要跑的门禁：`scripts/combat/**`、`WorldMap.gd`、`Ship.gd`、`PirateShip.gd`、`Cannonball.gd`、`SeaChart.gd` 的开战与结算、`data/combat_*.json`。

- 本探针，带 `--strict` 再跑一遍，看哪块还在跳过。
- `combat_wire_probe`（`-- --contract`，以及带窗口的 4 张截图）。
- `combat_vfx_probe`。
- `godot_compile_check`：新脚本要登记进 `SCRIPTS`。
- 改了 `combat_wire_probe.gd` / `combat_probe_stage.gd` 的，另加 `DISPLAY=:2 python3 tools/probe_pressure.py --only combat_wire_probe`。

## 二、判词与退出码

| 行首 | 意思 | 算不算红 |
|---|---|---|
| `✓` | 这条判据过了 | — |
| `✗` | 这条判据没过 | 红（rc=1） |
| `⚠ 跳过 …不在（combatNN 未落地）` | 模块文件不在，这一块没验 | 默认不红；`--strict` 红 |
| `⚠ 已知缺陷 <key>：…；属主 …；修法：…` | 登记在 `KNOWN_DEFECTS` 里的缺陷，这次仍然红着 | 默认不红；`--strict` 红 |
| `✗ …已修好，请把 KNOWN_DEFECTS["<key>"] 删掉` | 登记过的缺陷转绿了，登记还没删 | 红：登记不许烂在表里，同 check_data_family 的 known_orphans 基线 |
| `✗ 本节跑出引擎 / 脚本错误 n 条` | 这一节跑的时候出了带脚本来源的 ERROR / SCRIPT ERROR | 红 |
| `· …` | 七节普查，只报不判 | — |

判词行有三种样子：

- 全过：`COMBAT_REALISM_PROBE PASS　验过 N 节（…）；跳过 K 块（…：模块未落地，未验、不算通过）；已知缺陷 D 条（…）`
- 有红：`COMBAT_REALISM_PROBE FAIL k　…`，后面逐条复述 `✗`。
- `--json` 时 JSON 另带 `verified`、`skipped`、`known_defects`、`strict` 四个字段。跳过和已知缺陷记成 `level: warn`，不计入 pass / fail。

**PASS 不等于写实海战已经做完**。PASS 只说明验到的那几节没红。整波都落地以后要用 `--strict` 判，那时跳过和已知缺陷都算红。

## 三、各节验什么

判据的 key 是稳定的：零节的变异按 key 认，`KNOWN_DEFECTS` 也按 key 登记。模块用 `CombatDirector.load_module(id)` 取；取不到时，文件在就判「编不过」为红，文件不在就跳过。API 先按 `get_script_method_list()` 查方法名和实参个数，对不上的直接记 `X.api` 红，不去调，免得跑出 SCRIPT ERROR。

| 节 | 模块（lane） | 判据 |
|---|---|---|
| 一 | `SeaState.gd`（combat02） | `sea.force_wind` 定风「吹向正南、风力 100」时 wind_at ≈ (0, 100) · `sea.name` 风按来向叫：吹向正南的是「北风」 · `sea.current` 定流照读 · `sea.step_bounds` 逐帧演化 60 秒，风力在 (0, 150)、不出 NaN（150 是 `Ship._process_storm_damage` 的风暴伤线；海战固定无风暴伤）· `sea.seed` 同种子可复现 |
| 一 | `ManeuverModel.gd`（combat02） | `man.headwind` 顶风比侧风、斜顺风都慢 · `man.no_go` 当头不可行：顶风不过最佳帆向的两成五 · `man.wind_gain` 斜顺风时风大船快 · `man.leeway` 侧风把船往下风推，正顺风不横漂 · `man.turn_by_type` 福船（大）转向半径大于小艍船 · `man.fire_arc` 正横目标在射界，正船首的不在 · `man.boarding` 并舷同速钩得上，远了够不着，对冲挂不住 · `man.weather` 上风位不记反 · `man.step` 逐帧推进：侧风满帆起速，顶风起不来 |
| 二 | `Ballistics.gd`（combat03） | `bal.table` 每样武器有中文名、装填 > 0、有效射程不超过最远射程 · `bal.flight` 飞行有时，越远越久 · `bal.spread` 越远越难中 · `bal.bearing` 正横最好，往首尾不升，打不过对舷；射界最窄那样偏出正横 80° 射效降 |
| 二 | `ReloadAmmo.gd`（combat03） | `ammo.fire` 满装在 300 px 放得出 · `ammo.consume` 放一轮耗弹 · `ammo.reload` 刚放完再放被拒 · `ammo.reload_time` 1–60 秒内装好 · `ammo.empty` 弹尽（`ammo_mult: 0`）时远射一律拒，`is_spent` 为真 · `ammo.low_slow` 余量一成时装得比满装慢（短缺惩罚） |
| 三 | `DamageModel.gd`（combat04） | `dmg.fresh` 新船不进水、无火 · `dmg.flood` 水线下中弹进水 · `dmg.damage_control` 同样的漏，戽水令比迎敌令水少 · `dmg.slows` 进水拖慢航速 · `dmg.rudder` 艉部中弹，转向变钝 · `dmg.fire_starts` 火器引火 · `dmg.founder` 满身窟窿又不救，会沉 |
| 三 | `FloodFire.gd`（combat04） | `ff.spread` 火不救会烧到邻处 · `ff.douse` 有人救能扑灭 · `ff.leak` 漏着越灌越多 · `ff.bail` 堵漏戽水能减 · `ff.bulkhead` 水密隔舱：隔舱板不破，水不过舱 |
| 三/六 | `EnemyFloodFire.gd`（w53-p3a，`enemy_flood_fire`）| 敌船也挂进水失火簿（只 FloodFire 一件，不挂 DamageModel）。脚本径（判在本探针自检方）：`eff.timed_hit` 时级命中照 hull 开漏 · `eff.ballistic_leak` / `eff.ballistic_fire` 现矢（重弹水线下开漏 / 火弹点着）· `eff.shrink.calm/draws` 无险装填满舷、有水火抽人压出膛（不抽空）· `eff.frozen` 已降 / 被钩 / 白刃 / 已结算冻结 · `eff.plug` 人手堵漏 · `eff.state` 敌情列读口五键 · `eff.step.flood` / `eff.step.fire_grows` 漏真的涨水、火不救烧到四邻。节点径（六节真起海战场，开关开/关两态）：`eff.node.off_has_method` 开关关 `Cannonball._hit_method` 不指 `take_ballistic_hit`（回 take_damage 基线）· `eff.node.on_hit_method` / `eff.node.foe_hit_method` 开 + 簿在两闸齐才指 · `eff.node.ballistic_fire` / `eff.node.ballistic_leak` 火弹 / 水线下重弹接进簿 · `eff.node.step_flood` 敌船也步步涨水 · `eff.node.frozen_struck` 已降冻结 · `eff.node.founder_explode` 火烧穿船体照 `take_ballistic_hit → take_damage → _explode` 收（与击沉同一条路） |
| 四 | `MeleeResolve.gd`（combat05） | `melee.grapple.*` 钩牢率在 (0, 1]，随相对速度、风急下降，够不着为 0 · `melee.capture` / `melee.repel` 人多气盛得船，人少气衰被击退 · `melee.rounds` 均势时甲板打多合 · `melee.result` 了局在册、伤亡不越界 · `melee.seed` 可复现 · `melee.hook_miss` 落空时不开打 · `melee.approach` 从两船节点取接舷态势（ManeuverModel 在就并进它的键，跨 lane 接口在这一条跑到）· `melee.self_check` 模块自带的自检 |
| 五 | `CombatMorale.gd`（combat06） | `mor.fresh` 开局不溃不降 · `mor.casualties` 死伤压士气 · `mor.fire` 失火压士气 · `mor.rout_threshold` 过溃逃线才溃，线上不溃 · `mor.strike` 被钩、陷围、矢石尽时会降幡 · `mor.strike_pressure` 没有压力时只溃不降 · `mor.data` / `mor.data_bands` `data/combat_morale.json` 合规，溃逃线落在降幡线与动摇线之间 |
| 六 | 剧情挂钩 | 锚点字样 9 条（见 §五）· 真跑三场：遇盗夺船、弃战、哨船沉旗舰 · `KNOWN_DEFECTS` 表形状 |
| 七 | 接线普查 | 各模块能不能加载、被哪些现役脚本按文件名引用。只报不判：接线不在本波强制范围 |

## 四、零节：判据自检（红 / 绿自证）

每次跑都先过零节，不另开开关。零节拿本文件末尾的内部类当样本模块，喂给和真模块同一套判据：

- 好样本（`_FakeSea` / `_FakeManeuver` / `_FakeBallistics` / `_FakeReload` / `_FakeDamage` / `_FakeFloodFire` / `_FakeMelee` / `_FakeMorale`）须全绿。
- 每个变异是好样本的子类，只坏一处，比如「顶风照走」「弹尽照放」「一放就装好」「没有隔舱」「从不溃逃」「无压也降」。变异须在它点名的 key 上判红，其余 key 须绿。多红、没红都算零节红。
- 剧情锚点：照锚点表给每个文件合成一份最小源码当好样本，与真文件无关，所以真源码的锚点断了只在六节红、零节照绿。每支变异把一条锚点的第一条字样从它的函数体里抹掉，须恰好那条锚点红。
- 现有 10 组、47 支变异。缺省每组只印一行 `✓ <组>：好样本 N 条判据全绿，变异 K 支各只在点名处判红`，有一支不对就在这一行后面列出是哪支、没红什么、多红什么；`--mutants` 逐支都印。

所以判据写空了（永远绿）或写反了（好样本红），零节先红，不用等真模块落地。样本模块的 API 照各 lane 在 hali-combat-wave1 写的签名。真模块改了签名，先红的是 `X.api`，改判据时样本要一起改。

外置变异对照（Verify 贴的那种）：把某条判据声称能抓的缺陷造回真文件，现行探针须 rc=1；复原后须 rc=0。例：

```sh
# 锚点：把 WorldMap._board_enemy 里 boarded=true 的收战抹掉 → 锚点 capture_ship 红（combat_wire_probe 的剧情锚点也红）
sed -i 's/_battle_exit("win", {"boarded": true})/_battle_exit("win", {})/' scripts/WorldMap.gd
godot --headless --path . -s res://tools/combat_realism_probe.gd -- --only=story   # rc=1
git checkout -- scripts/WorldMap.gd                                                  # 复原后 rc=0
```

## 五、剧情挂钩锚点（遇盗 → 开战 → 夺船 → 回写）

剧情日后要在「遇盗开打」「夺得敌船」上挂旗标或新闻，就挂在下面这几支函数上。锚点表是 `CombatDirector.STORY_ANCHORS`。本探针六节和 `combat_wire_probe` 的 `_check_wiring` 都逐条验（在函数体里认原文子串），锚点一动先红。

| 锚点 id | 函数 | 那里必须还有 | 管什么 |
|---|---|---|---|
| encounter_roll | `Voyage.pirate_sighting` | `EventKind.PIRATE` | 逐日抽签抽到海盗，返回「不明船影」事件 |
| encounter_choice | `SeaChart._show_event` | `Voyage.EventKind.PIRATE`、`_add_event_action("迎战", _on_fight_pirates)` | 事件浮层：迎战 / 扬帆逃走 / 献上买路财 |
| encounter_battle | `SeaChart._on_fight_pirates` | `GameManager.pending_battle`、`PIRATE_ENEMY`、`"source": {"scene": "SeaChart", "event": "pirate"}`、`_enter_battle()` | 写战斗上下文再开战 |
| patrol_battle | `SeaChart._on_fight_patrol` | 同上，`"event": "yuan_patrol"`、`PATROL_ENEMY` | 元军哨船走同一条开战路 |
| battle_enter | `SeaChart._enter_battle` | `WorldMap.tscn`、`battle_finished.connect(_on_battle_result)` | WorldMap 叠上海图，战果信号接回来 |
| battle_setup | `WorldMap._ready` | `GameManager.pending_battle`、`_setup_combat(` | 读上下文，进战斗 |
| capture_ship | `WorldMap._board_enemy` | `Fleet.add_ship(`、`_battle_exit("win", {"boarded": true})` | 白刃胜：敌船按船型并入舰队；夺下末一艘即以 boarded 收战 |
| battle_exit | `WorldMap._battle_exit` | `battle_finished.emit(outcome, data)`、`"player_damage"` | 收战发信号，data 带战损 |
| result_writeback | `SeaChart._on_battle_result` | `"boarded"`、`接舷既定。`、`GameManager.pending_battle = {}` | 海图结算，boarded 记「接舷既定」 |

两处数据契约，剧情读的就是这两样：

- `GameManager.pending_battle`：`battle`、`power`、`player_power`、`enemy[]`（`{type, count, hull_hp[, sprite]}`）、`sea_name`，以及 `source`（`{scene: "SeaChart", event: "pirate" | "yuan_patrol"}`，剧情靠它分辨是哪一场遭遇）。combat02 另认三个可选键 `sea_seed`、`wind_bearing`、`wind_strength`，剧情定场时可以写，SeaChart 自己不写。
- `battle_finished(outcome, data)`：outcome 取 `win` / `lose` / `flee`。`data.player_damage` 恒有；另外按结局带 `boarded`（win：末一艘是接舷夺下的）、`sunk`（lose：旗舰沉）、`flee_ok`（flee：甩脱了）。常量写在 `CombatDirector.OUTCOMES` / `STORY_KEYS`——**lane w23-a10 起这对常量有真消费者了，不再是只被文档传抄的死码**：本探针六节 `_judge_outcome_contract`（判据 `story.outcome.detached` / `story.outcome.constants`）与独立可跑的 `tools/combat_outcomes_probe.gd`（`末梢自检 / 接线在册 / 战果契约在册`）都直读这两份表判红绿；摘掉常量 → 编译即红（`godot_compile_check`）+ 两探针红。判据明细与反向自证见 `docs/工程遗留收束_2026-10-03.md` 第 2 件。

六节真跑的三场（headless，SeaChart 起在泉州，`remaining_li` 设成还有路可走，但 `sailing` 为假，所以战后不抵港、不续航）：

1. **遇盗夺船**：`_on_fight_pirates()` 写 pending_battle，WorldMap 叠上来并刷出 2 艘快船。冻住敌炮、把敌船水手清零，先后 `_board_enemy` 两艘，得 2 艘「快船」入列。之后 battle_finished 恰好一次，海图清掉 pending_battle，钱入账，札记记「接舷既定」。
2. **弃战**：`_battle_exit("flee", {flee_ok})`，海图记 `CombatFx.sea_flee_ok_note()`。
3. **哨船迎战、旗舰沉**：`_on_fight_patrol()` 的 source.event 是 yuan_patrol。`_battle_player_sunk()` 之后海图记 `CombatFx.sea_sunk_note(…)`。札记的期望文案按 CombatFx 现拼，combat09 改了措辞也跟得上。

## 六、已知缺陷（`KNOWN_DEFECTS`，修好即删）

**已清（combat11）**：`story.capture.boarded` / `story.capture.damage` / `story.capture.writeback` 三条属主 `scripts/WorldMap.gd`——夺船前 `hull_hp=0` 且 `_is_live_pirate` 排除 `is_queued_for_deletion()`；战损只按开战在册船（`_roster_durability`）；末船接舷夺下走 `boarded=true` 收战，海图记「接舷既定」。`KNOWN_DEFECTS` 表现空。

## 七、和别的门禁的关系

- **没入册**：`tools/gate_json.py` 的 REGISTRY 里没有它，不进一键跑，只算专项探针（GATES §一「不算门禁」表末行、§五.1）。要升成 lane 档门禁，得在注册表加条目、跑 `gates_md.py --write`、在 §三 加小节。这两处不在 combat10 的范围，待议。
- `combat_wire_probe`：旧契约（接舷题签「接舷 → 夺船 / 脱钩」、CombatFx 注记、岸上预览）一条没动。`_check_wiring` 另加剧情锚点 9 条，契约模式和截图模式都跑。
- `godot_compile_check`：`tools/combat_realism_probe.gd` 与 `scripts/combat/CombatDirector.gd` 登记在 `SCRIPTS` 里（inventory 自检要求已跟踪的 .gd 必须列上）。
- 本探针不接 `shot_gate`，不截图，所以 gates_md 的「截图脚本都入册」管不到它。

## 八、常见红因

- `X.api` 红：模块改了方法名或实参个数。先对一对是不是有意改的；是的话，判据和零节样本一起改。
- 某条行为判据红：先看零节。零节全绿、只有真模块那一节红，那就是模块回归，或者口径变了（比如改了射界、改了溃逃线）。口径变了，改判据，同时在本文件 §三 记一笔。
- `本节跑出引擎 / 脚本错误`：模块运行期出错，常见是跨 lane 调用对不上签名。combat05 → combat02 的 `boarding_approach` 就是在 `melee.approach` 这一条上跑到的。
- `…已修好，请把 KNOWN_DEFECTS[…] 删掉`：属主修好了。删掉那条登记，同时删本文件 §六 的对应行。
- 六节 `story.chart.ready` 红：SeaChart 在 headless 下起不来（界面搭建报错），后面几条都不跑。
