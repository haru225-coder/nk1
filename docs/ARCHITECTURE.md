# nk1 架构一页纸（P7-B）

> 南海立志传 · Godot 4.6 · 2026-07-09  
> 目的：给后续 agent/开发者对齐现状；**不**替代任务书。

## 四层

```
Presentation   Main.tscn (GameShell + modes)  ↔  WorldMap.tscn（双根，P8 再并）
Controllers    Port / Investigation / Market / Tavern / Shipyard …
Systems        IntentResolver → Handlers → Ledger/Cargo/Economy/Calendar/Ending
State          GameState facade → fleet/survival/trade/story/market/calendar/career
Content        GameManager + data/*.json + data/scenes/*
```

## 场景路由（阶段 B）+ 单根壳（P8 首刀）

**入口**：`project.godot` → `scenes/AppRoot.tscn`（常驻）

```
AppRoot
├── NarrativeMain   ← instances Main.tscn（港内/剧情壳，切换时隐藏不销毁）
└── VoyageWorldMap  ← instances WorldMap.tscn（出海时挂上，回港 queue_free）
```

`Main.load_scene` → **`SceneRouter.classify`** →

| Kind | 行为 |
|------|------|
| `world_map` | `sail_world_map` → **`ModeStack.go_voyage`**（无宿主回退 change_scene） |
| `market` | 动态挂 `MarketScreenController` overlay |
| `narrative` | `resolve_scene_data` → Presenter + GameShell |

回港：`PortZone` / `WorldMap` ESC / 沉船 → **`ModeStack.go_narrative`**（无宿主回退 change_scene）。

新形态：**先扩 SceneRouter Kind，再在 Main 接线**。禁止把 if 链写回 `load_scene`。

## 写入路径

- 交易/船坞/贿赂等 → `Intent` → Handler → Ledger（幂等双保险）
- 剧情 choice effects → `GameState.apply_effects`（含 `career_promote` 连升）
- 月历 → `CalendarState.month_changed` → `CalendarEventScheduler`
- 结局 → career apex → `EndingResolver.evaluate`

## 边界冻结（P7 窗口）

| 模块 | 规则 |
|------|------|
| `GameState` | 新逻辑进 state/systems；少加顶层代理 |
| `MarketState` | 字段冻结；规则进 System/Event |
| `WorldMap` | 不塞新玩法系统；日历 tick / HUD 可接 |
| `Main` | 只做绑定 + 路由执行；分类/解析在 SceneRouter |

## P8 进度

| 项 | 状态 |
|----|------|
| AppRoot 入口 | 已上 |
| ModeStack.go_voyage / go_narrative | 已上 |
| 四条 change_scene 改为优先 ModeStack | 已上 |
| 港内壳出海后保留 | 已上（Main process_mode 禁用） |
| 统一状态条出海 | 已上（ChromeLayer 抬升 PortStatusBar + sea_mode） |
| 航海事件写入港内消息栏 | 已上（AppRoot.log_event → Main.append_shell_log） |
| WorldMap 自建左右 HUD | 保留；P8-5 有壳层时下移避让 + 精简重复 |
| Combat 进 ModeStack | 已上（AppRoot.show_combat，暂停 voyage） |
| Cutscene 进 ModeStack | 已上（抬升 CutscenePlayer + MODE_CUTSCENE） |

## 通关主路径（P7-A）

章一收束 → 章二收束 → 月历/「应召入蒲府」→ 章三三分支 → apex → 三结局之一。

## 通关后 UX（Ending UX）

```
career.rank_changed(apex)
  → GameState.ending_resolver.evaluate
  → 写 game_completed / ending_id / terminal_state
  → play ending_* cutscene（可与章三收束串播）
  → GameState.ending_resolved
  → AppRoot：过场空闲后 EndingSettlementController
      回标题 | 再启航程(begin_new_run) | 保存终局
```

结算文案来自 `data/endings.json` 的 title/summary/epilogue，秩禄/日期由 `build_display` 补。

## 测试

```bash
godot --headless -s scripts/systems/TestRunner.gd
```

基线以最新 DEVLOG 断言数为准。
