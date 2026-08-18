# DEVLOG — 南海立志传 (nk1) 开发日志

> 项目：南海立志传 (nk1) — Godot 4 / GDScript
> 引擎：Godot 4.6.3 stable (Forward Plus)
> 起始基线：commit `54e4b75` (2026-06-24) — 86 个测试断言
> 截至：2026-08-19 — 经济价差/读档自洽（2303 断言）
> 主线剧情任务：NK1-P2 ~ P7-A（经济深化 + polish + 月历秩禄 + **可通关竖切**）

---

## 阶段总览

| 阶段 | 任务书 | 焦点 | 起始断言 | 结束断言 | 新增 |
|---|---|---|---|---|---|
| 5 | NK1-P5-ECON-002 | 动态经济系统深化（跨港口联动、长期影响、可感知性） | 86 | 193 | +107 |
| 5 | NK1-P5-ECON-003 | 经济内容扩展（3 新事件 + 港口好感度 + 日志系统） | 193 | 261 | +68 |
| 6 | NK1-P6-GAMEPLAY-001 | 玩法与体验优化（航行手感/港口交互/世界感知） | 261 | 261 | 0 (体验优化) |
| 6 | NK1-P6-POLISH-001 | 技术债务清理 #1（魔法数字提取 + 日志系统） | 261 | 357 | +96 |
| 6 | NK1-P6-POLISH-002 | 技术债务清理 #2（Theme/Path/事件配置外部化） | 357 | 357 | 0 (重构) |
| 6 | NK1-P6-POLISH-003 | 技术债务清理 #3（颜色/Intent 类型/UI 预制体） | 357 | 515 | +158 |
| 6 | NK1-P6-POLISH-004 | 技术债务清理 #4（AssetPlaceholder/TextKeys/浮文参数） | 515 | 563 | +48 |
| 7 | P7-A 通关竖切 | 章一/二/三→三结局可闭合；秩禄连升；月历节拍 | ~P7 中间 | 1785 | 全绿 |
| 7 | P7-B SceneRouter | 路由抽离 + 边界冻结 + ARCHITECTURE 一页 | 1785 | 1802 | +17 |
| 8 | P8 ModeStack 首刀 | AppRoot 单根壳，出海/回港不 change_scene | 1802 | 1824 | +22 |
| 8 | P8-2 共用 Chrome | 状态条抬升 + 航海日志回写 | 1824 | 1831 | +7 |
| 8 | P8-3 Combat 壳 | 海战挂 AppRoot / ModeStack | 1831 | 1840 | +9 |
| 8 | P8-4 Cutscene 壳 | 过场抬升 AppRoot / MODE_CUTSCENE | 1840 | 1856 | +16 |
| 8 | P8-5 HUD 对齐 | WorldMap 避让状态条 + 精简重复 | 1856 | 1860 | +4 |
| 9 | 内容体验 | 章三续进 + 月历风声 + 经济月报 | 1860 | 1875 | +15 |
| 9 | 章三收束过场 | 三线短 CG + play_cutscene 串播 | 1875 | 1886 | +11 |
| 9 | 视觉 UI 补齐 | 指令栏图标 + 过场字幕 + 市集信息 | 1886 | 1897 | +11 |
| 9 | 视觉 UI 续 | 城镇热区图标板 + 标题 KOEI 外框 | 1897 | 1910 | +13 |
| 9 | 视觉 UI 续2 | TownMapView 木框 NinePatch | 1910 | 1920 | +10 |
| 9 | 视觉细节 | 热区/提示牌/标题金线/图标 import | 1920 | 1923 | +3 |
| 10 | Ending UX | 结算屏 + 回标题/再启航程 | 1923 | 1952 | +29 |
| 10 | 设施双列 | 无城镇图港口 KOEI 左右列 | 1952 | 1968 | +16 |
| 10 | 航海反馈 | SeaFeedback 海战/海遇壳层文案 | 1968 | 1987 | +19 |
| 10 | 经济手感 | 市集三策 + 邻港差价可感知 | 1987 | 2000 | +13 |
| 10 | 情报账本 | 付费信息差 IntelNotes | 2000 | 2019 | +19 |
| 11 | 经济漏洞 | 同港倒货/宝箱/Handler 报价/剧情重领 | 2019 | 2240 | +221 |
| 11 | 价差文案 | 三策/市集挂牌收购对齐 0.85 卖出价 | 2240 | 2287 | +47 |
| 11 | 读档自洽 | 负值/超舱/空舰队；CI 自测挂进 TestRunner | 2287 | **2303** | +16 |

测试断言增长曲线：86 → … → 2019 → 2240 → 2287 → **2303**

---

## P7-A — 可通关竖切（2026-07-09）

**焦点**：打通「章一 → 章二 → 月历/应召章三 → 三结局」主路径，不重做架构。

### 盘点出的阻断点（已修）

1. **秩禄无自然入口**：`career.promote` 几乎只被 `career_promote` 调用，且每次只 +1 阶 → 永远到不了 apex  
2. **章一错误写关系**：`story_flag2.linboyuan_relationship = "neutral_positive"` 未进整数关系字段 → rank2 条件永假  
3. **月历章三锁 rank≥4**：玩家在章二后通常 rank 不够 → 召见永不触发  
4. **章末 fame 不足连升**：章一/二几乎不给升秩 fame；章三 +120 不够 400 门槛  

### 落地改动

| 层 | 改动 |
|----|------|
| CareerState | `promote_while_eligible`；关系读取对齐 `linboyuan_relationship`/`jia_relationship` |
| GameState | `career_promote` 连升；`linboyuan`/`jia` 同步 `npc_relationships` |
| 场景 JSON | 章一/二收束 fame+promote；章三三结局 fame≥150 |
| calendar_events | 6 条节拍；召见 rank≥1 + `unless_flag`；迟到召见备份 |
| PortScreen | 「请旨升秩」「应召入蒲府」备份入口 |
| CalendarScheduler | 支持 `unless_flag` |
| 测试 | `[Completion Vertical Slice]` 三结局串联；unless_flag 断言 |

### 手玩通关路径（最小）

1. 打完章一 `scene08_return` → 自动升秩 + 林伯渊关系  
2. 进临安走章二至 `chapter2_end` → 再升秩  
3. 在港「应召入蒲府」或休整跨月触发月历  
4. 三选一：交书（投附）/ 拒召（忠义，需仍持《春秋》）/ 烧帖（远航）  
5. 收束 choice 触发 `career_promote` 连升 apex → `EndingResolver` 写 `game_completed`

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1785 assertions)
```

---

## P7-B — SceneRouter + 边界冻结（2026-07-09）

**焦点**：行为不变，消除 `Main.load_scene` if 链惯性；文档对齐。

### 改动

| 项 | 说明 |
|----|------|
| `scripts/SceneRouter.gd` | classify / resolve_scene_data / market_port_id |
| `Main.gd` | load_scene → match Kind → `_route_*` |
| GameState / MarketState | 边界冻结注释 |
| `docs/ARCHITECTURE.md` | 一页架构 |
| 测试 | `[SceneRouter]` 分类与回退 |

### 约束

- 新场景形态先加 SceneRouter Kind，禁止把 if 写回 Main
- GameState 少加顶层代理；MarketState 字段冻结
- 双根并壳仍属 P8，本阶段不动

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1802 assertions)
```

---

## P8 — ModeStack 首刀（2026-07-09）

**焦点**：Main ↔ WorldMap 不再 `change_scene` 互撕；AppRoot 常驻。

### 改动

| 文件 | 说明 |
|------|------|
| `scripts/AppRoot.gd` + `scenes/AppRoot.tscn` | 单根壳：NarrativeMain / VoyageWorldMap |
| `scripts/ModeStack.gd` | find_host / go_voyage / go_narrative |
| `project.godot` | main_scene → AppRoot.tscn |
| Main / PortZone / WorldMap / Ship | 优先 ModeStack，失败回退 change_scene |
| 测试 | `[ModeStack]` stub 宿主 |

### 行为

- 出港：隐藏 Main（`PROCESS_MODE_DISABLED`），挂 WorldMap  
- 回港：释放 WorldMap，恢复 Main，按 `return_to_port` 进港  
- 沉船：回 `start_scene`（默认 cg_title）  
- 无 AppRoot 时（旧入口/测试）仍 `change_scene`，不炸  

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1824 assertions)
```

### 未做（后续）

- ~~出海共用 PortStatusBar / 消息栏~~ → P8-2  
- 战斗/过场进 ModeStack  

---

## P8-2 — 共用状态条与消息栏（2026-07-09）

**焦点**：出海时仍显示同一 `PortStatusBar`；航海日志回写港内消息栏。

### 改动

| 项 | 说明 |
|----|------|
| AppRoot.ChromeLayer | 出海抬升 StatusBar，layer=90 压在 WorldMap 上 |
| PortStatusBar.set_sea_mode | 强制航程行；位置显示「海上/航向」 |
| WorldMap | `_refresh_app_chrome` / `_shell_log`（风景·经济·近港） |
| Main.append_shell_log | 供壳层写入 |

### 行为

- 出港：状态条不销毁，从 Main 挪到 AppRoot  
- 回港：状态条归还 Main.StatusLayer，sea_mode 关  
- 海景/经济/近港提示 → 回港后左栏仍可见  

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1831 assertions)
```

---

## P8-3 — Combat 进 ModeStack（2026-07-09）

**焦点**：海战 UI 挂到 AppRoot，不再依赖 WorldMap 子树；战斗中暂停航海。

### 改动

| 项 | 说明 |
|----|------|
| ModeStack | `MODE_COMBAT` / `start_combat` / `is_combat` |
| AppRoot.show_combat | 挂 CombatSessionController，voyage `PROCESS_MODE_DISABLED` |
| CombatSessionController.start_combat | 优先路由到 AppRoot（防递归） |
| 日志 | 开战/结束写入壳层消息栏 |

### 流程

```
遭遇 → SeaEvent → Intent combat_request
  → CombatSessionController.start_combat
  → AppRoot.show_combat（壳层 CanvasLayer）
  → 结束 combat_finished → 恢复 voyage process
  → SeaEvent 结算 LootResolver
```

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1840 assertions)
```

### 未做

- ~~Cutscene 进 ModeStack~~ → P8-4  

---

## P8-4 — Cutscene 进 ModeStack（2026-07-09）

**焦点**：CutscenePlayer 抬到 AppRoot；出海/Main 禁用时仍可播；过场中暂停航海。

### 改动

| 项 | 说明 |
|----|------|
| ModeStack | `MODE_CUTSCENE` / `play_cutscene` / `get_cutscene_player` / `is_cutscene` |
| AppRoot | 从 Main 收养 CutscenePlayer；`play_cutscene`；started/finished 管模式 |
| CutscenePlayer | `process_mode=ALWAYS`；`is_playing`；`started` 信号 |
| Main | 解析壳层 cutscene；月历 `cutscene_requested` 走 ModeStack |

### 行为

- 港内/结局/升秩/进港 intro：仍可 `player.play`，壳监听 `started` 进入 cutscene 模式  
- 出海：Cutscene 不随 Main 禁用  
- 结束：`finished` → 恢复 voyage process  

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1856 assertions)
```

---

## P8-5 — WorldMap HUD 与壳层对齐（2026-07-09）

**焦点**：有 PortStatusBar 壳层时，航海 HUD 不压状态条；去掉重复的水粮/金钱面板。

### 改动

| 项 | 说明 |
|----|------|
| `GameUILayout.sea_hud_top_margin` | 有 chrome 时 top = 状态条高 + 8 |
| WorldMap | `_apply_shell_chrome_layout`；壳层模式下精简左右 HUD 文案 |

### 行为

- **有 AppRoot 状态条**：左=舵法/气象，右=船货+天气；顶边下移  
- **无壳（旧 change_scene）**：完整旧 HUD，边距 20  

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1860 assertions)
```

---

## 内容/体验 — 章三节奏 + 经济可感知（2026-07-09）

**焦点**：章三中途可续进、月历有风声；休整/市集/月报能看见经济。

### 章三节奏

| 项 | 说明 |
|----|------|
| `resolve_chapter3_resume_scene` | 按 flag 回到投附/拒召/烧帖最近节点 |
| 港口按钮 | 「应召入蒲府」/「续·章三线」 |
| 进港时局提示 | 未完结章三时刷【时局】文案 |
| 月历 | 城中风声、榜前压力、分支催促 + shell_log |

### 经济可感知

| 项 | 说明 |
|----|------|
| `shell_log` effect | 场景/月历写入消息栏 |
| `economy_pulse` | 跨月商情 → EconomyLog + 消息栏 |
| 休整 | 展示最近 2 条经济日志 |
| 市集 | 最近 3 条经济动态分行显示 |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1875 assertions)
```

---

## 章三收束短过场（2026-07-09）

**焦点**：三条章三终点各一段 2 镜短 CG，并可与结局 CG 串播。

### 改动

| 项 | 说明 |
|----|------|
| `cutscenes.json` | `ch3_end_comply` / `refuse` / `burn` 各 2 镜 |
| 章三终点 effects | `play_cutscene` + `shell_log` |
| `GameState.play_cutscene` | 走 ModeStack / CutscenePlayer |
| `CutscenePlayer` 队列 | 播放中再 `play` 则入队串播 |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1886 assertions)
```

---

## 视觉 UI 补齐（2026-07-09）

**焦点**：指令栏空图标、过场字幕、市集经济信息可读性。

### 改动

| 项 | 说明 |
|----|------|
| `FacilityResolver.icon_keys_for` | id/标题 → market/tavern/wharf/temple… |
| `CommandBar` | 设施按钮复用 `resolve_facility_icon`；选择支带 sail/continue 图标 |
| `assets/ui/icons/*` | 新生成 KOEI 圆盘金字图标（札/寺/望/津…） |
| `CutscenePlayer.tscn` | 宋体、铜框字幕条、跳过提示 |
| 市集经济栏 | 4 行、加宽，分行显示商情 |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1897 assertions)
```

---

## 视觉 UI 续 — 城镇热区 + 标题 KOEI 框（2026-07-09）

**焦点**：城镇地图热区可见设施图标；标题屏木框 chrome 对齐 DialogueBox。

### 改动

| 项 | 说明 |
|----|------|
| `TownMapHotspot.gd` | 延迟布局后贴图标；黄铜 `IconPlate` 圆盘；悬停缩放/高亮 |
| `TitleScreenController.gd` | `KoeiOuterFrame` NinePatch（`ui_frame_koei.png`，patch 72/56）；副标题下金线分隔 |
| `main_theme.tres` TitlePanel | 清理重复键；深海底 + 铜边 4px + 圆角 ≤8 |
| 测试 | `[Title + Hotspot Visual]`；MapVisualStyle 补 TitlePanel 边重/色相断言 |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1910 assertions)
```

---

## 视觉 UI 续2 — TownMapView 木框（2026-07-09）

**焦点**：港口城镇地图外缘对齐 DialogueBox KOEI 木框（R4）。

### 改动

| 项 | 说明 |
|----|------|
| `TownMapView.tscn` | `MapFrame` NinePatch（`ui_frame_koei.png`，patch 72/56/72/72） |
| 结构 | `MapFrame` → `MapClip`（裁切+内边距）→ MapTexture / HotspotLayer / MapHint |
| `TownMapView.gd` | 节点路径更新；`_ensure_koei_frame` 兜底 patch / 不抢点击 |
| 测试 | MapFrame 贴图、patch、mouse_filter、层级断言 |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1920 assertions)
```

---

## 视觉细节打磨（2026-07-09）

**焦点**：热区层级/状态色、地图底提示牌、标题金线、设施图标 import。

### 改动

| 项 | 说明 |
|----|------|
| `TownMapHotspot` | 牌匾阴影；任务加粗铜边；完成态图标压暗；图标略收；悬停微调 |
| `TownMapView` | `HintPlaque` 深海铜框底条；提示字铜金呼吸 |
| `TitleScreenController` | 三段金线分隔；「— 航行记录 —」铜金标题 |
| `PortScreenController` | FacilityHint 铜金色 |
| `assets/ui/icons/*` | 补 `.import` 并 reimport（消除 No loader 报错） |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1923 assertions)
```

---

## Ending UX — 通关结算与回标题（2026-07-09）

**焦点**：apex 后不只写 flag，还有结算屏与回环。

### 改动

| 项 | 说明 |
|----|------|
| `data/endings.json` | 三结局 `title` / `subtitle` / `summary` / `epilogue` |
| `EndingResolver` | `last_result`、`get_ending_def`、`build_display` |
| `GameState` | `ending_resolved` 信号；`begin_new_run`；`build_ending_display` |
| `EndingSettlementController` | KOEI 木框结算：摘要 + 回标题 / 再启航程 / 保存终局 |
| `AppRoot` | 过场空闲且 `game_completed` → 弹出结算；接线三按钮 |

### 流程

```
career apex → evaluate → 结局 CG（可与章三串播）
  → 过场结束且无排队 → 结算屏
  → 回标题 | 再启航程(reset) | 保存终局
```

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1952 assertions)
```

---

## 设施双列 KOEI（2026-07-09）

**焦点**：无城镇地图港口（兴化/临安等）设施入口按太阁左右列分类与视觉统一。

### 改动

| 项 | 说明 |
|----|------|
| `FacilityResolver.split_facility_columns` | 左=社交/情报，右=海洋/贸易；rest 交错；列内排序 |
| `PortScreenController` | 用 resolver 分列；列头「社交·情报 / 海洋·贸易」；壳用 MarketShell |
| `FacilitySlotBuilder` | 更大图标、任务 ★、默认副文案、tooltip |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1968 assertions)
```

---

## 航海反馈 — SeaFeedback（2026-07-09）

**焦点**：海遇/海战结果写回港内消息栏，战斗 UI 文案统一铜金可读。

### 改动

| 项 | 说明 |
|----|------|
| `SeaFeedback.gd` | 开战/结束摘要、海遇开闭、bbcode 接敌/阶段/回合 |
| `AppRoot` | 海战 start/finish 用 SeaFeedback |
| `CombatSessionController` | 接敌/阶段色/胜负按钮文案 |
| `SeaEventController` | 开场/结果/升级开战 → push_shell |
| `WorldMap` | 接近遭遇 + 航线恢复日志 |

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (1987 assertions)
```

---

## 经济手感 — 市集三策（2026-07-09）

**焦点**：不改计价公式；让玩家在市集里**看见**稳/赌/搬三条合理路径。

### 改动

| 项 | 说明 |
|----|------|
| `EconomyFeel.gd` | `strategy_triad` / `best_arbitrage` / `trade_decision_hint` |
| `MarketScreenController` | 信息栏展示三策；选货预览附商策 |
| `GameState.economy_pulse` | 月报可带邻港差价耳语 |

### 三策（fun-economy 对齐）

1. **稳** — 兑现来货或收特产再走（买卖不同价，同货对倒必亏）  
2. **赌** — 事件/库存窗口，等或不等  
3. **搬** — 本港挂牌买 → 邻港收购卖，利润来自航线  

> 初稿曾写「本港即买即卖」。卖出价差落地后已改，避免教玩家亏钱路径。  

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (2000 assertions)
```

---

## 情报账本 — 信息差（2026-07-09）

**焦点**：情报是可买资产；三档清晰度不同，写入账本并在市集/三策可见。

### 改动

| 项 | 说明 |
|----|------|
| `IntelNotes.gd` | 账本 + 档位摘要（t1 模糊 / t2 窗口 / t3 点名） |
| `GameState.intel_notes` | 存档字段；`begin_new_run` 清空 |
| `BuyIntelHandler` | 购买成功 → `record` |
| `TavernController` | 按钮文案标清晰度；空池 `try_generate`；消息栏回写 |
| `MarketScreenController` | 【已知情报】块 |
| `EconomyFeel` | 【赌】优先读玩家情报 |

### 三档

1. ★ 20 — 有变故，不点名  
2. ★★ 50 — 时间窗 + 类型感  
3. ★★★ 120 — 港口 + 事件标签 + 布局/观望提示  

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (2019 assertions)
```

---

## 经济完整性 — 价差、刷取与读档（2026-08-19）

**焦点**：堵住单机玩法洞（不是 Web 安全），让市集文案跟成交价一致，读档后状态自洽。明文改高余额有意不拦。

### 玩法洞

| 严重度 | 洞 | 修法 |
|---|---|---|
| P0 | 同港买完立刻卖 | 买入限库存；成交后库存定价；卖出价 ×0.85；每日回补 5% |
| P0 | 海上宝箱挂机刷钱 | 45–90s，场上最多 3，每天 8 次，钱 15–40 |
| P1 | 回港口大厅清投资冷却 | 仅出港 `clear_visit_cooldown` |
| P1 | Handler 信 Intent 里的 cost | 修理/改装/补给/招募服务端重算 |
| P2 | 好感度买卖同一修正 | 买 1−aff，卖 1+aff |
| P2 | 剧情钱可重领 / 海遇连点打捞 | 已结算标记 + 立刻禁用按钮 |
| P2 | 20 钱补满大舱 | 缺额 ×0.5，下限 20；补给 intent 不再塞一口价 |
| P2 | 存档改 total 刷舱位 | 读档按货物重算；负数量丢掉 |

### 文案 / 读档

| 项 | 说明 |
|----|------|
| `EconomyFeel` | 稳策不再教对倒；搬货用挂牌买 / 收购卖 |
| `MarketScreenController` | 货舱走收购价；特产列 `买/收/余` |
| `SaveManager` + 各 `from_dict` | 负余额/粮水/库存抬 0；超舱压回；空舰队补旗舰 |
| TestRunner | 挂上 CI 四套 SelfTest，避免本地绿、Validate 红 |

### 有意不动

- 单机明文存档改高余额
- 补满一口价下限仍 20

### 验收

```
godot --headless -s scripts/systems/TestRunner.gd
→ ALL TESTS PASSED (2303 assertions)
```

---

## NK1-P5-ECON-002 — 动态经济系统深化

**焦点**：在基础跨港口联动和事件衰减恢复机制之上，让经济变化更具策略深度、长期影响和玩家可感知性。

### 完成项

1. **强化供需链与跨港口反馈**
   - PriceEngine 新增 `SUPPLY_CHAIN_BLEED=0.20`（供应链渗透强度）
   - PriceEngine 新增 `REGIONAL_PRESSURE_BLEED=0.15`（区域压力渗透强度）
   - EconomySystem 实现 `_get_upstream_ratio()` / `_get_downstream_avg_ratio()` / `_get_regional_avg_ratio()`
   - `calculate_price_deep()` 新函数整合全部修正因子
   - 实际效果：泉州断供 → 琉球涨价 92→154（端到端验证）

2. **玩家行为长期影响**
   - MarketState 新增 `trade_history: Dictionary`（每港每货物净流入追踪）
   - MarketState 新增 `port_prosperity: Dictionary`（港口繁荣度 0.7~1.3）
   - 实现了 `get_saturation_mod()` / `get_prosperity()` / `apply_prosperity_shock/boost()` / `process_daily_economy()`
   - 实际效果：20 次倾销后泉州瓷器价格 72→29（饱和生效）

3. **经济可感知性**
   - 新建 `EconomyLog` 类（_MAX_ENTRIES_PER_CATEGORY=20，3 个工厂方法）
   - WorldMap 接入 EconomyLog，断粮/风暴/经济变化时记录
   - MarketScreenController 新增经济信息栏（事件原因+繁荣/声誉+日志）
   - 4 处 `EconomyLog` 工厂方法（`make_dump_notice`/`make_disaster_notice`/`make_recovery_notice`/`make_prosperity_rise`/`make_supply_chain_notice`）

4. **事件与经济互动深度**
   - WorldEventTracker 新增 `event_chain_bias` 系统（灾难后恢复事件权重 +2.0~3.0）
   - `set_chain_bias()` / `get_chain_bias()` / `_decay_chain_bias()` API
   - 事件 activate/on_expire 中调用 `apply_prosperity_shock/boost`

5. **MarketState 重大重构**
   - `apply_disaster_zero` 从 0% 库存改为 20%（避免价格永久封顶）
   - `apply_partial_recovery` 引入繁荣度修正（繁荣港恢复更快）
   - `on_expire` 新增事件钩子（恢复库存 + 设置链偏置 + 记录日志）

### 新建文件
- `scripts/systems/EconomyLog.gd` — 统一经济日志类

### 测试
- 新增 `[Trade History & Saturation]` / `[Prosperity]` / `[EconomyLog]` / `[Economy Stability]` / `[Economy Integration]` 共 5 组测试

---

## NK1-P5-ECON-003 — 经济内容扩展

**焦点**：同步扩展内容与机制深度，让经济系统有更多可玩性和策略空间。

### 完成项

1. **3 个新世界事件类型**
   - `SupplyShortageEvent` — 特定商品在多港同时短缺，触发供应链连锁
   - `TradeBoomEvent` — 区域贸易繁荣期，繁荣度激增，结束时注入市场饱和
   - `EconomicRippleEvent` — 复合事件，重大经济事件波及整个区域

2. **现有事件与经济机制深度整合**
   - `PirateAttackEvent` / `TradeDisasterEvent` / `TradeRecoveryEvent` 接入繁荣度冲击与链偏置
   - 所有 6 个事件 `activate()` 调用 `apply_prosperity_shock`
   - 所有 6 个事件 `on_expire()` 调用 `apply_prosperity_boost` + 设置恢复事件链偏置

3. **玩家港口好感度系统**
   - MarketState 新增 `port_affinity: Dictionary`（-20~20 范围）
   - `get_affinity_price_mod()` 价格修正（0.88~1.12）
   - 7 级标签系统（敬重/友善/好感/中立/冷淡/排斥/敌意）
   - 交易自动累积好感度（买入 0.06/笔，卖出 0.04/笔）
   - 每日衰减 0.02 向 0 回归

4. **统一分类日志系统**
   - 新建 `GameLog` 类（3 级 × 5 分类，共 15 组合）
   - WorldMap 接入：断粮/风暴触发 WARNING + VOYAGE
   - 容量管理：每分类最多 20 条

5. **事件日志工厂方法扩展**
   - 新增 8 个工厂方法（短缺/繁荣/涟漪/海盗/恢复/许可变化等）

### 新建文件
- `scripts/events/SupplyShortageEvent.gd`
- `scripts/events/TradeBoomEvent.gd`
- `scripts/events/EconomicRippleEvent.gd`
- `scripts/systems/GameLog.gd` — 统一分类日志

### 测试
- 新增 `[New Event Registry]` / `[SupplyShortageEvent]` / `[TradeBoomEvent]` / `[EconomicRippleEvent]` / `[Port Affinity]` / `[Event-Economy Integration]` 共 6 组测试

---

## NK1-P6-GAMEPLAY-001 — 玩法与体验优化

**焦点**：在系统架构和经济机制已相对成熟的基础上，优化玩家核心循环的体验感和节奏感。

### 完成项

1. **世界地图与航海节奏优化**
   - Ship.gd: `turn_efficiency` 在 sail_gear=0 时从 0.0 改为 0.20（可转向）
   - Ship.gd: 基础转向 1.8→2.2，半帆效率新增 0.75
   - SailPhysicsEngine: 加速 lerp 0.8→1.5×delta，死风 0.4→0.8，停船 3.0→2.0
   - HUD 新增航速和风向标签（顺风/侧风/逆风）

2. **航行反馈增强**
   - WorldMap 新增航海风景日志（10 条风景池，每 25-45 秒随机弹出）
   - WorldMap 新增经济动态检查（每 20 秒检测 EconomyLog）
   - WorldMap 新增港口接近提示（<300px 时显示港口名+入港提示）
   - WorldMap 新增 `_check_economy_updates()` / `_show_voyage_scenery()` / `_check_port_proximity()`

3. **港口停留与交互体验**
   - PortScreenController 新增 `_show_quick_actions()`（3-click→1-click）
     - 一键补满水粮 / 一键全量修理 / 升帆出港
   - PortScreenController 新增 `_show_economy_summary()`（繁荣/声誉/事件数）
   - Main.gd: `left_panel.visible = true` 启用（之前一直 false）
   - _set_port_guide 显示港市状况/声誉

4. **出港准备流程**
   - ShipyardController 新增"⚡ 一键整备"按钮（补给+修理一键完成）

5. **信息反馈**
   - Main.gd `_refresh_message_panel` 显示最新经济动态
   - PortStatusBar 显示 voyage 行（met_lin_boyuan 或 chapter1_complete 标志后）

### 测试
- 无新测试（任务书未要求，专注体验优化）

---

## NK1-P6-POLISH-001 — 技术债务清理 #1

**焦点**：系统性技术债务清理和代码质量提升。

### 完成项

1. **魔法数字提取与常量化（32 个 CombatState 常量）**
   - `BASE_CANNON_DAMAGE_PER_ARTILLERY=8.0` / `DODGE_PER_MANEUVER=0.04` / `SWORDPLAY_POWER_COEFF=0.15` / `DAMAGE_CREW_LOSS_RATIO=0.05`
   - 28 个新增常量：MANEUVER_*_THRESHOLD/MULT、FLEE_*_THRESHOLD/BONUS、BOARDING_*_RATIO/THRESHOLD、SWORDPLAY_BONUS_*、DUEL_*_THRESHOLDS/ROUNDS、ENEMY_AI_*_RATIO/CHANCE、DEFAULT_ENEMY_*（5 个）

2. **TradeState 常量提取**
   - `CUSTOMS_FINE_MAX=200` / `CUSTOMS_BRIBE_AMOUNT=50` / `CUSTOMS_BRIBE_ATTENTION_DELTA=3`

3. **SurvivalState 常量提取**
   - `DEFAULT_FOOD/WATER=30` / `MAX_FOOD/WATER=100` / `MAX_CARGO=200` / `DAILY_CONSUME_DIVISOR=10` / `STARVATION_DEATH_RATIO=0.1`

4. **Handler 默认值常量**
   - BribeHandler: `DEFAULT_BRIBE_AMOUNT=50` / `DEFAULT_ATTENTION_DELTA=3` / `PU_ATTENTION_MAX=20`
   - BuySuppliesHandler: `SUPPLY_FILL_FLAT_COST=20`
   - HireCrewHandler: `DEFAULT_COST_PER_CREW=10`
   - ShipyardController 引用 Handler 常量（单一来源）

5. **PriceEngine 常量**
   - `PRICE_FLOOR=1` / `PRICE_CAP_MULT=5`
   - `SUPPLY_CHAIN_MOD_MIN/MAX=0.7/1.3` / `REGIONAL_PRESSURE_MOD_MIN/MAX=0.85/1.15`
   - `DOWNSTREAM_DEMAND_SURGE_THRESHOLD/BLEED_FACTOR=1.2/0.5`

6. **统一分类日志系统** — 见 P5-ECON-003 GameLog

7. **代码质量小清理**
   - Main.gd 移除硬编码 debug 事件 `PirateAttackEvent` 触发
   - 修复 CombatState 中 `_roll`/`_calc_cannon_damage` 函数缩进 bug（被误嵌套在 `execute_round` 中）
   - ShipyardController 引用 Handler 常量（`HIRE_CREW_COST_PER := HireCrewHandler.DEFAULT_COST_PER_CREW`）

### 测试
- 新增 `[Polish Constants]` (50) + `[GameLog]` (18) = 68 个断言

---

## NK1-P6-POLISH-002 — 技术债务清理 #2

**焦点**：UI 构建迁移 / Theme 字符串 / 资源路径 / 事件配置外部化。

### 完成项

1. **UITheme.gd 创建**（28 个常量）
   - 按钮 (5): `BTN_ACTION` / `BTN_CHOICE` / `BTN_SET_SAIL` / `BTN_TITLE_MENU` / `BTN_NPC`
   - 市集 (5): `MARKET_SHELL` / `MARKET_TITLE` / `MARKET_ALERT` / `MARKET_PANEL` / `MARKET_PREVIEW`
   - 设施 (7): `CARD_FACILITY` / `CARD_FACILITY_QUEST` / `TITLE_FACILITY` / `SUBTITLE_FACILITY` / `BTN_FACILITY_CARD` / `BADGE_FACILITY_QUEST` / `FRAME_FACILITY_ICON`
   - 港状态栏 (3) / 事件对话 (5) / 标题 (1) / 通用 (1)
   - `assert_all_known(theme_name)` 静态验证方法
   - 75 处全项目替换

2. **ResourcePaths.gd 创建**（40+ 路径常量）
   - 主题样式 (3) / 纹理 (5) / 场景 (9) / 事件脚本 (7) / Handler 脚本 (11) / 资源目录 (5) / 数据文件 (3)
   - 56 处全项目替换

3. **UIBuilder 工具类**（13 个工厂方法）
   - `make_button/text/label/panel` 通用
   - `make_action/choice/set_sail/npc_button` 按钮快捷
   - `make_market_preview/alert/title/panel/shell` 市集快捷
   - `make_facility_card(is_quest)` 设施卡快捷
   - `make_port_stat_chip(caption, value)` 港状态栏三件套
   - `make_rich_text(text, theme, bbcode)` / `make_section_label(text)`

4. **UIButton 预制体**（scenes/UIButton.tscn + UIButton.gd）
   - 首个 .tscn 复用预制体，支持 `theme_variation` / `min_height` 属性

5. **事件配置外部化**
   - 新建 `data/events_config.json`（version=1，6 个事件 + 生成器配置）
   - 新建 `EventConfigLoader.gd`（懒加载 + 缓存 + `clear_cache` 热重载）
   - `apply_config(event, id)` / `get_event_config(id)` / `get_generator_config()` / `get_initial_duration()`
   - 3 个事件迁移：PirateAttackEvent / TradeDisasterEvent / TradeRecoveryEvent
   - TradeEventGenerator 集成配置（DAILY_EVENT_CHANCE, rumor_delay 等）

6. **UIBuilder 推广**（10 站点）
   - ChoiceHandler / TavernController / PortMarketController / NPCController / PortScreenController

### 新建文件
- `scripts/UITheme.gd`
- `scripts/ResourcePaths.gd`
- `scripts/controllers/UIBuilder.gd`
- `scripts/UIButton.gd`
- `scenes/UIButton.tscn`
- `data/events_config.json`
- `scripts/systems/EventConfigLoader.gd`

### 测试
- 新增 `[UITheme Constants]` (32) + `[ResourcePaths]` (38) + `[Event Config]` (28) + `[UIBuilder]` (18) = 116 个断言（部分测试在 P3 中重做）

---

## NK1-P6-POLISH-003 — 技术债务清理 #3

**焦点**：颜色常量化 / Intent 类型 / 事件配置继续外部化 / UIBuilder 推广。

### 完成项

1. **GameColors.gd 创建**（50+ 颜色常量 + 3 辅助方法）
   - 状态色 (15): `WARNING` / `DAMAGE` / `WARNING_SOFT` / `DANGER_TEXT` / `PIRATE_RED` / `ENEMY_BLIP` / `SUCCESS` / `PERMIT_OK` / `PRICE_CRASH` / `PRICE_DROP` / `PORT_BLIP` / `INFO` / `SCENERY` / `PATROL_BLUE` / `NAVY_HUD` / `RADAR_RING`
   - UI 文字色 (7) / 港状态栏色 (3) / 浮文色 (4) / 天气时间色 (9) / 模态遮罩 (4) / 通用 (3)
   - `get_price_trend_color(ratio)` / `get_prosperity_color(prosperity)` / `get_ratio_status_color(ratio)`
   - 47 处全项目替换

2. **IntentTypes.gd 创建**（14 个 Intent 类型常量 + 2 辅助方法）
   - 交易类 (4): `PAYMENT` / `TRADE_REQUEST` / `MARKET_BUY` / `MARKET_SELL`
   - 经济活动 (6): `BRIBE` / `REPAIR_SHIP` / `REFIT_SHIP` / `HIRE_CREW` / `BUY_SUPPLIES` / `BUY_INTEL`
   - 战斗海战 (3): `COMBAT_REQUEST` / `INSPECTION_PASS` / `ESCAPE_ATTEMPT`
   - 系统 (1): `IGNORE`
   - `is_known(type)` / `all_types()`
   - 93 处全项目替换

3. **事件配置继续外部化**
   - SupplyShortageEvent / TradeBoomEvent / EconomicRippleEvent 全部迁移到 JSON
   - JSON 配置：每个事件 10-15 个可调参数

4. **UIBuilder 推广**（10 站点）
   - PortScreenController（3 quick actions）/ ChoiceHandler / TavernController / PortMarketController / NPCController

5. **修复已知 bug**
   - UIBuilder 静态函数中 `VBox.new()` 类型问题 → 改为 `VBoxContainer.new()`（GDScript 静态上下文不能解析 VBox）
   - PortMarketController for 循环缩进被破坏（导致"无法解析 PortMarketController"）

### 新建文件
- `scripts/GameColors.gd`
- `scripts/IntentTypes.gd`

### 测试
- 新增 `[GameColors]` (50) + `[IntentTypes]` (18) + `[All Event Config]` (30) + `[UIBuilder]` 重测 (20+) = 158 个断言

---

## NK1-P6-POLISH-004 — 技术债务清理 #4

**焦点**：AssetPlaceholder 外部化 / TextKeys 常量 / UIBuilder 继续推广 / 浮文参数常量化。

### 完成项

1. **AssetPlaceholder 背景映射 JSON 化**
   - 新建 `data/asset_backgrounds.json`（29 BG 别名 + 8 NPC 头像）
   - 懒加载 `_ensure_config_loaded()` + 缓存
   - 公开 API `get_background_path(alias_key)` / `get_legacy_avatar_path(npc_id)`
   - 热重载 `reload_config()`（测试用）
   - JSON 失败时降级到 `_FALLBACK_BG_ALIASES` / `_FALLBACK_LEGACY_AVATARS`
   - 原 `const BG_ALIASES` / `const LEGACY_AVATAR_BY_NPC` 替换为运行时 var

2. **TextKeys.gd 创建**（68 个 TextMap key 常量）
   - Intent 成功 (16): `INTENT_OK` / `INTENT_PAYMENT_SUCCESS` / `INTENT_MARKET_BUY/SELL_SUCCESS` / ... / `INTENT_INSPECTION_FINED/CLEARED`
   - Error 消息 (52): `ERROR_INTENT_MISSING_TYPE` / `ERROR_MARKET_NO_PORT` / `ERROR_COMBAT_NO_FLEET` / ... 等
   - 静态方法: `all_intent_success_keys()` / `all_error_keys()` / `is_intent_success(key)` / `is_error(key)`
   - 80 处全项目替换
   - IntentResult.ok() 默认参数从 `"intent.ok"` 改为 `TextKeys.INTENT_OK`

3. **FloatingTextConfig.gd 创建**（浮文参数 + 风景池）
   - 基础参数: `DEFAULT_FLOAT_SPEED=50.0` / `DEFAULT_LIFETIME=1.5` / `RANDOM_JITTER=20.0` / `Z_INDEX_DEFAULT=100`
   - 5 类偏移量: `OFFSET_CREW_LOSS` / `OFFSET_SCENERY` / `OFFSET_ECONOMY` / `OFFSET_PORT_NEAR` / `OFFSET_PICKUP`
   - 5 类生命周期: `LIFETIME_CREW_LOSS=2.0` / `LIFETIME_SCENERY=3.0` / `LIFETIME_ECONOMY=4.0` / `LIFETIME_PORT_NEAR=3.5` / `LIFETIME_PICKUP=1.5`
   - `VOYAGE_SCENERY` 池 (10 条) — 从 WorldMap 迁移
   - FloatingText.gd 默认值从 config 读取
   - WorldMap.gd 4 个浮文调用站点使用 config 偏移和生命周期
   - Crate.gd 拾取浮文使用 `OFFSET_PICKUP` + `GameColors.FLOATING_PICKUP`

4. **UIBuilder 推广**（15 站点）
   - InvestigationController (3): 互动/遇见人物/离开
   - ShipyardController (10): 剧情/整备/出港/修理×2/招募×2/补给×3/改装
   - CityNavBuilder (2): 回城关/设施导航

### 新建文件
- `data/asset_backgrounds.json`
- `scripts/TextKeys.gd`
- `scripts/FloatingTextConfig.gd`

### 测试
- 新增 `[AssetPlaceholder JSON]` (18) + `[TextKeys]` (16) + `[FloatingTextConfig]` (14) = 48 个断言

---

## 累计成果统计

### 测试断言
- 起始: 86
- 结束: 563
- 新增: 477
- 增长: +553%

### 新建文件
- `data/events_config.json`
- `data/asset_backgrounds.json`
- `scenes/UIButton.tscn`
- `scripts/systems/EconomyLog.gd`
- `scripts/systems/GameLog.gd`
- `scripts/systems/EventConfigLoader.gd`
- `scripts/events/SupplyShortageEvent.gd`
- `scripts/events/TradeBoomEvent.gd`
- `scripts/events/EconomicRippleEvent.gd`
- `scripts/UITheme.gd`
- `scripts/ResourcePaths.gd`
- `scripts/GameColors.gd`
- `scripts/IntentTypes.gd`
- `scripts/TextKeys.gd`
- `scripts/FloatingTextConfig.gd`
- `scripts/controllers/UIBuilder.gd`
- `scripts/UIButton.gd`

### 关键常量类（按创建顺序）
1. `EconomyLog` (P5) — 事件经济日志
2. `GameLog` (P5) — 统一分类日志（5 类 × 3 级）
3. `UITheme` (P6-P2) — 28 个 Theme 字符串
4. `ResourcePaths` (P6-P2) — 40+ 资源路径
5. `GameColors` (P6-P3) — 50+ 颜色
6. `IntentTypes` (P6-P3) — 14 个 Intent 类型
7. `TextKeys` (P6-P4) — 68 个 TextMap key
8. `FloatingTextConfig` (P6-P4) — 浮文参数

### 事件配置外部化进度
- P2: 3/6 事件（pirate_attack / trade_disaster / trade_recovery）
- P3: 6/6 事件（全部迁移到 data/events_config.json）
- 总参数: 100+ 个可调事件参数全部从 JSON 加载

### 颜色替换覆盖
- 47 处全项目颜色字面量 → GameColors.*
- 覆盖 14 个 .gd 文件
- 涵盖 UI 文字、价格趋势、天气时间、模态遮罩、浮文等

### UIButton 预制体推广
- 35+ 处 Button.new() 迁移到 UIBuilder.make_*_button()
- 覆盖 13+ 个 .gd 文件

### Intent 类型字符串
- 93 处 → IntentTypes.*
- 覆盖 23 个 .gd 文件

### TextMap key 字符串
- 80 处 → TextKeys.*
- 覆盖 13 个 .gd 文件

### 资源路径
- 56 处 → ResourcePaths.*
- 覆盖 18 个 .gd 文件

### Theme 字符串
- 75 处 → UITheme.*
- 覆盖 19 个 .gd 文件

### 已知的已修复 bug
1. **CombatState 函数缩进 bug** — `_roll` 和 `_calc_cannon_damage` 的 `func` 关键字被错误地缩进到 `execute_round` 内部
2. **PortScreenController.max() Variant warning** — `max()` 返回 Variant 导致类型推断错误（P4 修复为 `int(max(...))`）
3. **PortMarketController for 循环缩进** — P3-003 迁移时 for 循环体被错误地放到循环外，导致"无法解析 PortMarketController"类错误
4. **UIBuilder 静态方法 VBox.new()** — GDScript 静态函数中 VBox 类型不可用，改为 VBoxContainer
5. **GameLog.log() 递归调用** — `info/warning/debug` 调用 `log()` 时被解析为 EconomyLog 的 1 参数版本，改为 `add_entry`
6. **GameLog.get_entries() 类型转换** — `arr.duplicate()` 返回 Array，需 `as Array[String]` 转换

---

## 持续技术债务（已识别但未处理）

1. **多语言支持**: `data/localization/zh_cn.json` 是 i18n 基础，但 TextMap fallback 字符串仍是中文硬编码
2. **CombatResult 字符串**: `CombatSessionController` 中 Phase 标签和战斗文本仍硬编码
3. **UI 浮文工厂方法**: 5 个 `ResourceManager.FloatingText.instantiate()` 调用各有 5 行模板代码，可封装为工厂
4. **Event log 字符串模板**: "【商情急报】%s遭海盗袭击..."等模板可全部提取到 EconomyLog
5. **Crate 拾取字符串**: `+ ` + str(amount) + ` 钱` / `货舱已满` 字符串可集中
6. **RID 泄漏**: 测试运行后有 1 个 TextureStorage + 12 个 ShapedTextData 泄漏（Godot 4.6 清理问题）
7. **GameConstants.gd 统一类**: 可建统一的游戏常量类（替代分散的 CombatState/PriceEngine/SurvivalState/TradeState 常量）
8. **更深入事件配置化**: 可加入更多动态调整项（如 AI 行为、伤害缩放、UI 阈值等）
9. **TextMap 缺失条目**: `_format_intent_failure` 等处的 fallback 字符串硬编码
10. **PortMarketController 进一步 UIBuilder 化**: 其余 3 个按钮站点（minus/plus/confirm/back）尚未迁移

---

## 开发方法论总结

1. **先扫描后提取**: 每次任务先用 explore agent 完整扫描相关模块，再设计常量位置
2. **Python 脚本批量替换**: 用 Python 脚本批量替换字符串/路径/颜色字面量（5 次任务都用此方法）
3. **测试驱动验证**: 每次新功能/常量提取都新增对应测试组
4. **优雅降级**: JSON 配置失败时回退到硬编码 fallback（如 AssetPlaceholder）
5. **跨类一致性**: ShipyardController 引用 Handler 常量作为单一来源
6. **覆盖广度**: 每任务 13+ 个 .gd 文件跨模块改动
7. **迭代修复**: 多次发现并修复编译错误（缩进、类型推断、命名冲突）

---

## 2026-06-30 — 船只系统 + 港口背景图池轮换

**焦点**：船只玩法补全、进港背景从单图别名升级为按港轮换图池、四港新美术落盘。

**测试断言**：563 → **657**（+94）

### 提交链

| Commit | 摘要 |
|--------|------|
| `a66ad2f` | 船只系统：船型 JSON、`ShipVisual` 程序化船模、船坞改装、小地图船型 |
| `3337307` | 巡防福船解锁条件、沉没 2s 动画后回港 |
| `a06e3dd` | 离港保存海上坐标、战斗界面船型信息、`ships.json` visual 块 |
| `eb14512` | 11 港图池 + `pick_background_path()` 进港按序轮换 |
| `46fb65a` | 基隆/占城/蒲甘/对马提示词模块 + deploy 脚本接四港 |
| `d78508a` | 四港 PNG 落盘部署（各 4 张），全项目 15 池 187 图 |

### 船只系统（`a66ad2f` ~ `a06e3dd`）

1. **数据与改装**
   - `data/ships.json`：福船/广船/巡防福船属性 + `visual` 几何配色块
   - `ShipSystem`：不依赖 `GameState`，船坞 `REFIT_SHIP`（hull/sail）
   - `ShipModelLibrary.get_model()` 优先读 JSON visual，硬编码 fallback

2. **世界地图**
   - `NavigationState` 保存 `world_map_position/rotation`；B/Esc/停靠写 pose，再出海恢复，沉没清除
   - 港口出生偏移按船型碰撞半径；小地图船型轮廓 dirty redraw

3. **战斗/UI**
   - `CombatSessionController._format_fleet` 显示船型·帆型·炮·机动
   - `ShipSystem.format_combat_ship_detail()` / `format_ship_summary()`

### 港口背景图池（`eb14512` ~ `d78508a`）

**问题**：14+ 港口仅 `bg_aliases` 回退旧 KOEI 图，重复进港同一张。

**方案**：

```
场景 bg 键 → data/asset_backgrounds.json bg_pools → assets/port_pools/{港}/
进港 (type==port) → AssetPlaceholder.pick_background_path() → 001→002→… 循环
```

**图池覆盖（15 目录 / 17 bg 键 / 187 张）**

| 图池目录 | 张数 | 场景 bg 键 |
|----------|------|------------|
| quanzhou | 21 | `bg_quanzhou_port.png` |
| quanzhou_sunset | 1 | `bg_quanzhou_port_sunset.png` |
| xinghua | 12 | `bg_xinghua_harbor.jpg` |
| mingzhou | 31 | `bg_mingzhou_port.png` |
| jeju | 16 | `bg_jeju_port.png` |
| tunmen | 3 | `bg_tunmen_port.png` |
| zhangzhou | 47 | `bg_zhangzhou_port.png` |
| wenzhou | 32 | `bg_wenzhou_port.png` |
| ganpu | 2 | `bg_ganpu_port.png` |
| guangzhou | 5 | `bg_guangzhou_port.png` |
| penghu_night | 1 | `bg_penghu_night.png`, `bg_penghu_port.png` |
| **keelung** | **4** | `bg_keelung_port.png`, `bg_keelung_coast.png` |
| **champa** | **4** | `bg_champa_port.png` |
| **bugan** | **4** | `bg_bugan_port.png`（蒲甘，非「博干」） |
| **tsushima** | **4** | `bg_tsushima_port.png` |

**仍走 alias fallback（无图池）**：博多、琼州、三佛齐、龙牙门、交趾、阇婆、碧澜渡、徐闻等（13 条，见 `asset_backgrounds.json`）。

### 美术管线

1. **分类源**：`C:\Users\SC\Downloads\grok-images-classified\{港}/`（含 `_review/{港}/` 低置信度图）
2. **提示词**：`docs/port_prompts/{keelung,champa,bugan,tsushima}.md` + `_STYLE_SUFFIX.txt`
3. **部署**：`python3 tools/deploy_port_bg_pools.py`
   - 支持 `jpg/jpeg/png/webp`；增量模式（无新源则保留已有池）
   - 有图池的港口自动从 `bg_aliases` 移除

### 关键文件

| 区域 | 路径 |
|------|------|
| 图池配置 | `data/asset_backgrounds.json` |
| 轮换逻辑 | `scripts/AssetPlaceholder.gd` → `pick_background_path()` |
| 进港触发 | `scripts/Main.gd`（`type == "port"`） |
| 部署脚本 | `tools/deploy_port_bg_pools.py` |
| 提示词总表 | `docs/port_art_prompts.md` |

### 运维备忘

- 换图：改 `grok-images-classified/{港}/` → 重跑 deploy（单港有源则只刷新该池）
- 删坏图：直接删 `assets/port_pools/{港}/00X.png`，不必重跑全量
- 验收：同港连续进 4 次，背景应循环；屯门仅 3 张最易肉眼确认
