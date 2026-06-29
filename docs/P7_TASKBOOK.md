# NK1-P7 任务书 ｜ 月历秩禄制 + 叙事收束

> 颁布者：架构主审（不写代码，只判方向/定设计）
> 执行：由领单模型实现，TDD，遵守 ponytail（极简/YAGNI）
> 基线：563 测试断言不可回退；P5/P6 系统层不动，只加不重构

---

## 0. 锁定的架构决策（不可推翻，除非主审否决）

1. **时间模型 = 混合日历制**：保留实时 WorldMap 航行（SailPhysicsEngine/风/WASD 不动）；新增 年/月/日 日历。航行/休整消耗天数；剧情事件按指定月份触发。= UW4 忠实 + 太阁5 时间轴。**禁拆 WorldMap。**
2. **胜利条件 = 叙事结局经秩禄阶梯**：保留 `items.json` 已声明 3 结局（loyalty/defection/overseas），由秩禄阶梯顶点触发 `EndingResolver` 评估。不新增"秩禄顶点即通关"。
3. **现有 154 场景 = 日历调度改造**：scene JSON 增可选 `schedule` 字段；**缺省回退现行 flag 门控**（向后兼容，非破坏式）。迁移渐进，仅章三 + 关键节拍优先调度。

## 1. 第一性理由

nk1 当前**不可通关**——`chapter2_complete` 已 unlock `chapter3_pu_counter`（`linan.json:822`）但章三场景数=0；3 结局零逻辑。月历秩禄制提供**线性推进脊梁**（太阁5 主命/秩禄感），把已存在的 154 深度内容 + 实时航行 + 深经济串成"可通关、有戏剧高潮"的完整体验。**可完成性 > 重玩性**：用月历节拍给玩家方向感，比堆沙盒数据更能留住卡在死胡同的玩家。

## 2. 关键路径

```
Phase 1 (并行):  P7-T(日历基座) ──┬── P7-S(调度器) ──┐
                  P7-X(过场)    ─┤                  ├── P7-E(结局) ──┐
                  P7-A(章三起草) ─┘  P7-C(秩禄) ─────┘                ├── P7-A(集成)
                                                                   │
依赖: T→{S,C}; E←{C,X}; A←{S,E}(集成), A-起草立即可并行
```

**关键路径：T → {S,C} → E → A-集成**。X 与 A-起草全程并行。

---

## P7-T ｜ CalendarState 日历基座（最先动工，一切前置）

### 目标
净新增 年/月/日 日历状态模块；与现有生存日 tick 同源推进；提供"休整度日"玩家动词。

### 范围
- **新建 `scripts/state/CalendarState.gd`**（与 FleetState/SurvivalState 同列）：
  - `year:int`（绝对年，自 `start_year` 起）、`month:int`(1-12)、`day:int`(1-30，每月固定 30 日简化）
  - `start_year:int`（基线，从 `historical_data/historical_summary.md` 取南宋蒲氏纪年，内容组确认后填常量）
  - `advance_days(n:int) -> Dictionary` → 返回 `{"months_crossed":Array[String]}`（跨过的月份 key 列表，供调度器用）
  - `advance_to_next_month() -> int`（休整至下月，返回消耗天数，驱动生存消耗）
  - `date_key() -> String`（如 `"宝祐3年4月"`，年号映射读 `data/calendar_eras.json`，缺失回退 `"Y{year}M{month}"`）
  - `months_elapsed() -> int`（自起始总月数，调度偏移用）
  - `signal month_changed(month_key:String)`（跨月时发，调度器监听）
  - `to_dict()/from_dict()`（存档）
- **新建 `data/calendar_eras.json`**：年号↔绝对年映射表（宝祐/开庆/景定/咸淳/德祐/景炎/祥兴，1253-1279；系统降级容忍缺失）。基线 = 1255 宝祐三年（现有内容 grep 实证）。
- **挂接 `WorldMap.gd:174`**：`process_daily_consumption()` 调用处同源调 `GameState.calendar.advance_days(n)`（n=本次 tick 天数，需先确认 WorldMap 的日计数单位；若现按 1 日/tick 则 n=1）
- **GameState 集成**：`var calendar: CalendarState = CalendarState.new()`；加 `to_save_dict/from_save_dict` 条目
- **UI**：`PortStatusBar` 加日期显示（年号年月）；`PortScreenController` 加"休整至下月"按钮（调 `advance_to_next_month` + 生存消耗 + 触发月调度）

### 验收
- 航行使日历按天推进；跨月发 `month_changed`
- "休整至下月"可点，消耗对应天数水粮，日历跳至下月 1 日
- `date_key` 格式正确；年号缺失时降级不崩
- 存档/读档恢复日历
- 新增测试组 `[Calendar]`：advance_days 滚月、advance_to_next_month、date_key、存档、跨月信号（≥8 断言）
- **563 断言不回退**

### 架构约束
- 极简：每月固定 30 日，不做农历/节气（YAGNI）
- 不直接操作 story/fleet；只管时间，跨月发信号由他人响应
- 年号映射失败必降级，不阻塞游戏

### 依赖：无

---

## P7-S ｜ CalendarEventScheduler 月调度器

### 目标
按月份+条件触发剧情/过场/效果；非破坏式给 154 场景加日期门控。

### 范围
- **新建 `data/calendar_events.json`**：
```json
{"version":1,"events":[
  {"id":"ch3_pu_summon","fire":{"month_offset":48},
   "condition":{"flag":"chapter2_complete","rank_gte":4},
   "action":{"type":"scene","target":"ch3_pu_summon"},
   "priority":10,"once":true}
]}
```
  - `fire` 支持 `month_offset`（自起始）或 `date:{year,month}`（自 start_year 绝对）
  - `condition`：flag / `rank_gte` / `relationship_gte`（与 CareerState 联动）—— 求值为 AND
  - `action.type`：`scene` | `cutscene` | `effect`
- **新建 `scripts/systems/CalendarEventScheduler.gd`**：
  - 监听 `CalendarState.month_changed` → `check_and_fire(month_keys)`
  - 求 condition（委托 GameState/CareerState 读 flag/rank）；选最高 priority due 事件；触发 action
  - 幂等：`once:true` 触发后记入已发集合，用 `IdempotencyGuard` 防重放
  - 缺省无事件时静默
- **Scene 调度改造**：scene JSON 增可选 `schedule` 字段（`{month_offset}` 或 `{date}`）。SceneManager/加载处：scheduler 触发 `scene` action 即按 id 进入场景；**现有 flag 门控（SceneVariantResolver）不动**，schedule 仅作前置日期闸。缺 `schedule` 的场景行为完全不变（向后兼容）

### 验收
- 到月且条件满足→触发；未到月不触发
- `once:true` 不重放；priority 高者先
- 无 `schedule` 的现有场景行为不变（回归测试全绿）
- 新增 `[Calendar Scheduler]` 测试组（≥10 断言）

### 架构约束
- 只读 flag/rank，不改状态（副作用由 action 的 scene/effect 自身产生）
- 复用 `IdempotencyGuard`，不另造幂等机制

### 依赖：P7-T

---

## P7-C ｜ CareerState 秩禄阶梯

### 目标
太阁5 式秩禄 + 主命（带截止月）阶梯；顶点触发结局评估。

### 范围
- **新建 `data/career.json`**：
```json
{"tiers":[
  {"rank":0,"title":"商船水手","req":{"fame":0}},
  {"rank":1,"title":"副纲首","req":{"fame":50,"flag":"chapter1_complete"},
   "mandate":{"id":"m1","deadline_months":3,"objective":"...","on_complete":"promote"}},
  ...
  {"rank":5,"title":"市舶司都纲","req":{"fame":400,"flag":"chapter2_complete"},"apex":true}
]}
```
- **新建 `scripts/state/CareerState.gd`**：
  - `rank:int`、`current_mandate:Dictionary`、`mandate_deadline_month:int`
  - `check_promotion() -> bool`（求 req：fame/flag/relationship）
  - `promote()`（升秩、发 `signal rank_changed(new_rank)`、分配下一 mandate）
  - `mandate_expired()`（月过截止→ fame/关系惩罚，**非 game over**）
  - `is_apex() -> bool`
  - `to_dict()/from_dict()`
- **GameState 集成**：`var career: CareerState`；存档条目
- **UI**：PortStatusBar 显示秩禄头衔；rank_changed → 触发 P7-X 升秩过场
- **EndingResolver 触发点**：`is_apex()` 为真时调 P7-E 评估

### 验收
- req 满足→可升秩；不满足不可升
- mandate 截止月过期→惩罚生效
- apex 可达；apex 时触发结局评估（与 P7-E 联调）
- 存档恢复
- 新增 `[Career]` 测试组（≥10 断言）

### 架构约束
- req 全配置化（career.json），不硬编码 if-else 链
- rank_changed 走信号，不直连 CutscenePlayer（解耦，CutscenePlayer 订阅）
- mandate 惩罚走 `apply_effects` 已知 key（`GameState.gd:277`），不新增 silent key

### 依赖：P7-T（截止月需日历）

---

## P7-X ｜ CutscenePlayer 过场层

### 目标
数据驱动极简过场播放器；UW4 风格还原最后一块。四处复用：抵达/章节切换/升秩/结局。

### 范围
- **新建 `scenes/CutscenePlayer.tscn` + `scripts/CutscenePlayer.gd`**：
  - 全屏 CG（TextureRect）+ 字幕（Label/RichTextLabel）+ 淡入淡出（Tween）
  - 可选多分镜序列（`data/cutscenes.json` 每条 `panels:Array`）
  - `play(cutscene_id)` / `skip()`（可跳过，太阁5 可跳）
  - 订阅 `CareerState.rank_changed` → 播升秩过场
- **新建 `data/cutscenes.json`**：`{id, cg_alias(走 asset_backgrounds.json), caption, panels?, hook}`
- **钩子点**：港口抵达（替换 `Main._show_port_intro_if_needed:279` 的日志行）/ 章节切换 / 升秩 / 结局
- CG 路径走 `asset_backgrounds.json` 映射 + `ResourcePaths` 常量

### 验收
- 抵达主港触发抵达过场；升秩有过场；可被结局调用
- 可跳过；不破坏现有场景流
- 新增 `[CutscenePlayer]` 测试组（≥6 断言）

### 架构约束
- 极简：全屏图+字幕+淡入淡出足矣，**禁造动画系统**（ponytail）
- 不直接操作 GameState，通过信号/UI 事件通信
- CG 缺失降级为纯字幕，不崩

### 依赖：无（自包含，Phase 1 立即开工）

---

## P7-E ｜ EndingResolver 结局系统

### 目标
3 结局判定与触发，闭合可完成性。

### 范围
- **新建 `data/endings.json`**：
```json
{"endings":[
  {"id":"loyalty_ending","condition":{"rank_apex":true,"flag":"spring_autumn_scroll","linboyuan_gte":50},
   "cutscene":"ending_loyalty","terminal_state":"completed_loyalty"},
  {"id":"defection_ending","condition":{"rank_apex":true,"jia_gte":50},"cutscene":"ending_defection",...},
  {"id":"overseas_ending","condition":{"rank_apex":true,"flag":"overseas_voyage"},...}
]}
```
- **新建 `scripts/systems/EndingResolver.gd`**：
  - `evaluate() -> IntentResult`（CareerState.is_apex() 为前置；求 condition；多满足按 priority 选）
  - 触发 CutscenePlayer 播结局过场
  - 写入终局 flag（`set_story_flag("game_completed", true)` + 具体 ending id），可存档
- 接入：CareerState 升至 apex 时调 `evaluate()`

### 验收
- 3 结局各自可达（构造测试 fixture）
- 多条件同时满足按 priority 选一
- 结局后终局状态写入且可存档
- 新增 `[Endings]` 测试组（≥8 断言，含边界优先级）

### 架构约束
- 判定全配置化（endings.json），不硬编码
- 走 Intent 管线之外但复用 `IntentResult` 模式返回
- 新 flag 在 `StoryState` 登记

### 依赖：P7-C（apex）+ P7-X（播过场）

---

## P7-A ｜ 第三章「蒲氏反击」场景内容

### 目标
补全 chapter_3 场景，闭合叙事脊梁，3 结局分支可达。

### 范围
- **新建 `data/scenes/chapter3_*.json`**（目标 25-35 场景）
- 严格复用现有 scene schema（objective/body/investigations/choices/effects/next）
- 关键场景带 `schedule` 字段（走 P7-S 调度），choices/effects 指向 P7-E 结局分支
- 接入 ≥2 个 `SceneVariantResolver` 变体函数
- 从 `linan.json:822` 的 `chapter3_pu_counter` 自然衔接

### 验收
- 章二末→章三自然衔接；3 结局分支各自可达
- 每场景有 objective/body/choices；文字风格与现有 154 一致
- effects 只用 `apply_effects` 已知 key（`GameState.gd:277`）；新 key 须先在 P7-E/C 登记 handler，**禁用 `_SILENT_KEYS` 兜底**（`GameState.gd:303`）
- 不破坏章一/章二流

### 架构约束
- 起草可与 T/S/E 并行（写作是最长任务，先启动）；最终集成须 S+E 就绪
- 新 flag 在 StoryState 登记

### 依赖：P7-S（调度）+ P7-E（结局分支）就绪后集成；起草立即并行

### P7-A 校准闸协议（强制，针对长篇创作）

长篇叙事创作的 spec 越长越没用——风格漂移是隐形失败，断言抓不到。规矩是**先 1 样本校准，过闸再放量**。此协议对任何执行模型（含强模型）一律适用。

**闸 1 — 单场景样本（起草第一步）**
1. 执行模型先读 `data/scenes/xinghua.json` 的 `scene01_xianghua_school`（章一开篇，风格基准）+ 任一 `linan.json` 章二场景。
2. 写 **1 个**章三场景样本：`data/scenes/chapter3_pu_summon.json`（蒲氏召见开场）。
3. 提交样本，**停手等待校准**，不连续写。

**校准维度（主审或其委托人验）**
- schema 一致：objective / body / investigations / choices / effects / next 字段齐全且类型对
- 文字风格：与现有 154 场景同呼吸（文言骨架 + 白话叙事 + `【人物】："台词"` 格式）
- variant 模式：接入 ≥1 个 `SceneVariantResolver` 变体函数（参照现有 16 个的模式）
- effects 合规：只用 `apply_effects` 已知 key（`GameState.gd:277` 映射表），无新 silent key
- next 衔接：指向合理的章三后续场景 id（可暂占位）

**闸 2 — 放量（校准通过后）**
4. 校准通过 → 执行模型放量写剩余 24-34 场景，分批提交（每批 ≤8 场景）。
5. 每批主审抽验 1-2 场景，风格/schema 漂移则退回整批重写。
6. 3 结局分支场景最后写，须 P7-E `endings.json` 条件定义就绪。

**校准不通过** → 退回，执行模型重写样本，最多 3 轮。3 轮不过换模型或降为人工协作。

### 依赖（更新）：P7-S（调度）+ P7-E（结局分支）就绪后集成；起草（闸1样本）立即并行

---

## 4. 全局铁律（所有流通用）

1. **第一性优先**：每步自问"是否推进可完成性/戏剧化/月历脊梁"，否则不做
2. **TDD**：563 断言基线不可回退；新逻辑先写测试
3. **架构只加不重构**：Intent 管线 / 数据驱动 / 常量集中（`UITheme`/`ResourcePaths`/`GameColors`/`TextKeys`/`FloatingTextConfig`）是好底子，不重构
4. **ponytail**：日历每月 30 日固定、CutscenePlayer 不造动画系统、Career 不造技能树（YAGNI）
5. **禁碰经济深度**：P5/P6 已过深，P7 不新增经济模拟复杂度
6. **向后兼容**：`schedule` 字段缺省=现行行为；新 flag 登记；降级容忍
7. **状态模块单一职责**：CalendarState 只管时间，CareerState 只管秩禄，EndingResolver 只管判定——不互嵌

## 5. 持续技术债（P7 不处理，登记备查）

i18n fallback 硬编码中文 / CombatResult 字符串 / 浮文工厂 / RID 泄漏 / 统一 GameConstants / NPC 对话树（P7-D 候选）/ 沙盒深度（P7-E' 候选：补 20 港经济数据 + 加载 discoveries.json）

---

_主审判定：P7 月历秩禄制 + 叙事收束。关键路径 T→{S,C}→E→A，X 与 A-起草全程并行。_
