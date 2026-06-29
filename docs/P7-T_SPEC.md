# P7-T 接口级 Spec ｜ CalendarState 日历基座

> 颁布者：架构主审。执行模型（MiniMax M3 或同等）领单即照此实现，无歧义。
> TDD 强制：563 断言基线不可回退；本流新增 ≥11 断言。
> 铁律：架构只加不重构 / ponytail 极简 / 禁碰经济深度 / 向后兼容。
> 状态模块单一职责：CalendarState **只管时间**，跨月发信号由他人响应；不操作 fleet/story/survival。

---

## 0. 5 个集成点（钉死，按修改面排序）

> 所有点已读真实代码（`GameState.gd` 1-512 / `WorldMap.gd` 168-192）核实，非臆测。

### 集成点 1：Tick 注入 —— `GameState.process_daily_consumption` 末尾（**关键修复**）

**位置**：`scripts/GameState.gd:151-154` 末尾追加一行 `calendar.advance_days(1)`。

**问题发现**（`WorldMap.gd:168-179` while 循环同源）：
```gdscript
while time_of_day >= 24.0:           # :171  — 一帧可能迭代多次（delta 大时跨多日）
    time_of_day -= 24.0
    GameState.process_daily_consumption()  # :174  每轮 = 一日
    WorldEventTracker.process_day()
    TradeEventGenerator.try_generate()
    TradeEventGenerator.process_day()
    GameState.market.process_daily_economy()  # :179
```

**铁律：tick 必须进 `process_daily_consumption` 末尾，不能进 WorldMap。**

- 理由 A（同源同序）：`process_daily_consumption` 已被 while 循环每轮调一次 = 每日一次，与日历"每日推进"语义同源。追加在此保证 **日历与生存消耗/经济/事件同 tick、同序、同帧**，563 断言里经济时序测试不会崩。
- 理由 B（最小侵入）：WorldMap 是皇冠资产，禁拆；改 WorldMap 等于动 while 循环结构，风险高。改 GameState 一行字，不动 while 循环结构。
- 理由 C（去重）：WorldMap 一帧可能迭代 N 次（极端 delta），若在 WorldMap 内 tick，需要传入 N；进 `process_daily_consumption` 自然 N=1，零参数、零分叉。

**实现**：在 `GameState.gd:154`（`modify_crew` 调用之后、`func` 结束之前）追加 `calendar.advance_days(1)`。共改 **1 行**。

### 集成点 2：状态模块声明 —— `GameState.gd:10-17` 块

**位置**：`scripts/GameState.gd:10-17` 的状态模块实例块，追加 `var calendar: CalendarState = CalendarState.new()`。

**位置选择**：紧接 `var market` (`:15`) 之后、`var economy_log` (`:16`) 之前。理由：calendar 与 market/economy 同属"非叙事性全局状态"，物理相邻便于阅读；不插到 fleet/survival/trade/story（叙事核心）中间避免视觉扰乱叙事模块块。

**共改 1 行**。

### 集成点 3：存档挂接 —— `GameState.gd:484` (to) / `:496` (from)

**`to_save_dict()` (`:484-494`)** 末尾加（`:494` 之前）：
```gdscript
"calendar": calendar.to_dict() if calendar else {},
```

**`from_save_dict()` (`:496-512`)** 末尾加（`:512` 之后，作为新块）：
```gdscript
if data.has("calendar") and calendar:
    calendar.from_dict(data["calendar"])
```

**向后兼容**：`data.has("calendar")` 守卫确保旧存档（无 calendar 字段）正常加载，calendar 保持初值（1255/1/1）。563 断言中存档测试不崩。

**共改 4 行**（1 行插入 + 2 行新块 + 1 行空行调整）。

### 集成点 4：UI 显示 —— `PortStatusBar.gd` 日期 chip

**位置**：`scripts/PortStatusBar.gd` 新增日期 chip。

**模式参照**：现有 chip 模式（`@onready var xxx_value: Label = $Panel/Body/VBox/PrimaryRow/Xxx/Margin/Row/VBox/Value`，:13-33）。建议在 PrimaryRow 末尾追加 `Date` chip（与 Location/Money/Fame/Permit/PuAttention/Cargo 平级），或在 PrimaryRow 与 VoyageRow 之间新增 `DateRow`。

**数据源**：`_ready` 之后或现有刷新回调里调 `GameState.calendar.date_key()` 填值；`month_changed`/`year_changed` 信号触发刷新。

**布局不钉死**：执行模型按现有 chip 风格自洽，遵守 `UITheme`/`GameColors`/`UIBuilder` 约定。禁止新增字体/主题/颜色常量。

### 集成点 5：控制器动作 —— `PortScreenController.gd` 休整按钮

**位置**：`scripts/PortScreenController.gd` 新增"休整至下月"按钮（参照 P6 已实现的 `_show_quick_actions` 模式）。

**动作链**：
1. 调 `GameState.calendar.advance_to_next_month()` → 拿返回天数 `days_consumed`
2. 循环 `days_consumed` 次调 `GameState.process_daily_consumption()` 复用生存消耗（**禁止在 CalendarState 内消耗水粮**）
3. 触发 P7-S 调度器检查（若 S 未就绪，留 `# TODO: P7-S hook` 注释占位，不阻断 P7-T）
4. 刷新 `PortStatusBar` 日期 chip（接集成点 4）

**生存消耗复用**：`SurvivalState.process_daily_consumption(crew_count)` 已存在（`SurvivalState.gd:31`），按返回天数循环调用。**禁止新造消耗逻辑**。

---

## 1. 锁定事实（已读真实文件 / 史料核实）

### 1.1 年号基线 —— 1255 宝祐三年（**剧情锚点**）

**现有内容核实**（grep 全项目场景年代 = `6 处宝祐三年，0 处咸淳`）：
- `data/scenes/xinghua.json` 章一开篇 `time:"宝祐三年六月"`（1255）
- `data/scenes/linan.json` 章二用相对时辰（午后/翌日卯时/黄昏/当夜/丑时）—— 紧接章一
- `data/scenes/chapter3_pu_summon.json` 闸1样本 `time:"宝祐三年八月"` —— 章三紧接章二
- **内部时间线自洽于 1255 宝祐三年。史料作背景参考，不覆盖现有内容纪年。**

**`start_year` 常量 = 1255**（绝对年 = 宋宝祐三年，不可改）。
**年号映射** 读 `data/calendar_eras.json`（详见 §2.2 schema）。
**宝祐3年** 计算：`(1255 - 1253) + 1 = 3`（`start_year=1253`，`start_era_year=1`）。

**年号表范围 1253-1279**（剧情跨度）：
| 年号 | 起 | 止 | start_era_year |
|---|---|---|---|
| 宝祐 | 1253 | 1258 | 1 |
| 开庆 | 1259 | 1260 | 1 |
| 景定 | 1260 | 1265 | 1 |
| 咸淳 | 1265 | 1275 | 1 |
| 德祐 | 1275 | 1276 | 1 |
| 景炎 | 1276 | 1278 | 1 |
| 祥兴 | 1278 | 1279 | 1 |

`year_in_era = abs_year - start_year + start_era_year`。越界/缺失 → 降级 `"Y1255M1"`，不崩。

### 1.2 状态模块落点

`scripts/state/CalendarState.gd`（同列已有 FleetState/SurvivalState/StoryState/NavigationState/MarketState/TradeState/CombatState/ShipState）。参照 `SurvivalState.gd` 的 `class_name X extends RefCounted` + `to_dict/from_dict` 模式。

### 1.3 依赖项（已存在，P7-T 不重写）

- `scripts/systems/IdempotencyGuard.gd` — `static var processed_intents: Dictionary` + `check_and_record(id) -> bool`。P7-S 调度器复用，P7-T 不直接用（仅确认存在）。
- `scripts/PortStatusBar.gd` — 现有 `@onready` 节点链（见集成点 4）。
- `scripts/PortScreenController.gd` — 现有 `_show_quick_actions`（见集成点 5）。

---

## 2. 新建文件

### 2.1 `scripts/state/CalendarState.gd` —— 完整签名

```gdscript
class_name CalendarState extends RefCounted

## 日历状态模块（P7-T）
## 职责：仅管 年/月/日 推进与查询；跨月发信号；不操作其他状态。
## 每月固定 30 日（YAGNI，不做农历/节气/闰月）。
## 剧情起始：宋宝祐三年（1255），兴化乡学开课（章一开篇 `time:"宝祐三年六月"`）。

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const START_YEAR := 1255        ## 剧情起始绝对年（宋宝祐三年，现有内容已锁定）

var year: int = START_YEAR
var month: int = 1              ## 1-12
var day: int = 1                ## 1-30

signal month_changed(month_key: String)   ## 跨月时发，month_key 见 date_key()
signal year_changed(year: int)            ## 跨年时发

## 推进 n 日。返回 {"months_crossed": Array[String], "days_advanced": int}。
## 逐日推进以便每月末准确发信号。n 上限 clampi(0, 400) 防误传巨值。
func advance_days(n: int) -> Dictionary:
    # 实现：for i in range(clampi(n, 0, 400)):
    #   _advance_one_day()
    #   若跨月：months_crossed.append(date_key())
    #       若跨年：year_changed.emit(year)
    #       month_changed.emit(date_key())
    # return {"months_crossed": ..., "days_advanced": clampi(n,0,400)}
    ...

## 休整至下月 1 日。返回消耗天数。调用方负责同步生存消耗（见集成点 5）。
func advance_to_next_month() -> int:
    # days = DAYS_PER_MONTH - day + 1
    # advance_days(days)
    # return days
    ...

## 当前月份 key，格式 "宝祐3年4月"（年号映射读 calendar_eras.json，缺失降级 "Y1255M4"）。
func date_key() -> String:
    # era = _lookup_era(year)  # 读 data/calendar_eras.json（懒加载+缓存于 _eras_cache）
    # if era.is_empty(): return "Y%dM%d" % [year, month]
    # return "%s%d年%d月" % [era.name, era.year_in_era, month]
    ...

## 自起始总月数（调度偏移用，0-indexed）。
func months_elapsed() -> int:
    return (year - START_YEAR) * MONTHS_PER_YEAR + (month - 1)

func to_dict() -> Dictionary:
    return {"year": year, "month": month, "day": day}

func from_dict(d: Dictionary) -> void:
    year = int(d.get("year", START_YEAR))
    month = clampi(int(d.get("month", 1)), 1, MONTHS_PER_YEAR)
    day = clampi(int(d.get("day", 1)), 1, DAYS_PER_MONTH)

## 年号映射（懒加载）。返回 {"name":"咸淳","year_in_era":9} 或空 Dict（降级）。
func _lookup_era(abs_year: int) -> Dictionary:
    # 读 data/calendar_eras.json（懒加载一次，缓存于 _eras_cache）
    # 找到 start_year <= abs_year < end_year 的条目
    # 失败返回 {} → date_key 降级
    ...

var _eras_cache: Dictionary = {}
```

### 2.2 `data/calendar_eras.json`

```json
{
  "version": 1,
  "eras": [
    {"name": "宝祐", "start_year": 1253, "end_year": 1258, "start_era_year": 1},
    {"name": "开庆", "start_year": 1259, "end_year": 1260, "start_era_year": 1},
    {"name": "景定", "start_year": 1260, "end_year": 1265, "start_era_year": 1},
    {"name": "咸淳", "start_year": 1265, "end_year": 1275, "start_era_year": 1},
    {"name": "德祐", "start_year": 1275, "end_year": 1276, "start_era_year": 1},
    {"name": "景炎", "start_year": 1276, "end_year": 1278, "start_era_year": 1},
    {"name": "祥兴", "start_year": 1278, "end_year": 1279, "start_era_year": 1}
  ]
}
```

**匹配规则**：`start_year <= abs_year < end_year`（半开区间，年号起算含 start_year，止年含 end_year 归下一年号）。
**降级**：`abs_year < 1253` 或 `abs_year >= 1279` → `date_key` 返回 `"Y%dM%d"`，`_lookup_era` 返回 `{}`。

---

## 3. 改动现有文件（精确行）

### 3.1 `scripts/GameState.gd`（共 6 行）

| 行号 | 改动 | 内容 |
|---|---|---|
| `:15` 之后 | 插入 1 行 | `var calendar: CalendarState = CalendarState.new()` |
| `:154` 之后 | 插入 1 行 | `calendar.advance_days(1)` |
| `:494` 之前 | 插入 1 行 | `"calendar": calendar.to_dict() if calendar else {},` |
| `:512` 之后 | 插入 2 行 | `if data.has("calendar") and calendar:`<br>`	calendar.from_dict(data["calendar"])` |

### 3.2 `scripts/PortStatusBar.gd`

- 新增 `Date` chip（PrimaryRow 末尾追加或新增 DateRow）。执行模型按现有 chip 模式自洽。
- `_ready` 后或现有刷新函数里调 `GameState.calendar.date_key()` 填值。
- 订阅 `GameState.calendar.month_changed` / `year_changed` 信号触发 chip 刷新。

### 3.3 `scripts/PortScreenController.gd`

- 新增"休整至下月"按钮（参照 P6 `_show_quick_actions` 模式）。
- 点击 → `var days = GameState.calendar.advance_to_next_month()` → 循环 `days` 次 `GameState.process_daily_consumption()` → P7-S 调度器检查（留 hook 注释） → 刷新 PortStatusBar。
- **禁止** 在 CalendarState 内消耗水粮；**禁止** 新造消耗逻辑。

---

## 4. 验收清单

- [ ] 航行使日历按天推进（进港再出航，日历前进）
- [ ] 跨月发 `month_changed`；跨年发 `year_changed`
- [ ] "休整至下月"可点，消耗对应天数水粮，日历跳至下月 1 日
- [ ] `date_key` 格式 "宝祐3年4月"；年号缺失/越界降级 "Y1255M4" 不崩
- [ ] 存档/读档恢复日历（旧存档无 calendar 字段也能加载）
- [ ] `advance_days(0)` 不动；`advance_days(400)` 触发 clamp 不崩
- [ ] **563 断言全绿**（集成后先跑回归再提交，红一即退回）
- [ ] PortStatusBar Date chip 实时显示，跨月/年时刷新
- [ ] WorldMap while 循环一帧迭代 N 次时，日历只增 N（验证同源同序）

## 5. 新增测试组 `[Calendar]`（≥11 断言）

1. `advance_days(1)` 单日推进：day 1→2，month/year 不变，无 month_changed
2. `advance_days(30)` 跨月：month +1（1→2），month_changed 发一次，年不变
3. `advance_days(360)` 跨年：year +1（1255→1256），year_changed 发一次，month_changed 发 12 次
4. `advance_days(0)` 无变化（边界：不动、不发信号）
5. `advance_to_next_month` 从 day 15 → 下月 day 1，返回 16
6. `advance_to_next_month` 从 day 1 → 下月 day 1，返回 30
7. `date_key` 宝祐3年4月（year=1255, month=4）—— 剧情起始锚点（章一六月=1255/6）
8. `date_key` 跨年号：year=1276 → "德祐1年1月"（1275-1276 德祐 1 年）
9. `date_key` 跨年号：year=1276 month=2 → "景炎1年2月"（1276 起景炎）
10. `date_key` 越界降级：year=1300 → "Y1300M4"（1279 之后）；year=1240 → "Y1240M4"（1253 之前）
11. `months_elapsed` 起始=0（1255/1），推进 13 个月=13（1256/2）
12. `to_dict/from_dict` 往返一致
13. `advance_days(400)` clamp 到 400 不崩（边界）
14. `advance_days(-1)` clamp 到 0 无变化（防御性）
15. 同源同序回归：`process_daily_consumption()` 调用一次后 day +1（验证集成点 1 注入位置正确）

测试参照现有 `scripts/systems/TestRunner.gd` 模式（执行模型先读此文件确认断言风格）。

---

## 6. 禁止事项（6 条）

1. **禁拆 WorldMap / SailPhysicsEngine**（皇冠资产；while 循环结构不动）
2. **禁在 CalendarState 内消耗水粮 / 改 fame / 改 flag**（单一职责；生存消耗由集成点 5 在 PortScreenController 侧循环复用）
3. **禁造农历 / 节气 / 闰月**（YAGNI；每月固定 30 日）
4. **禁新增 silent key 兜底**（`GameState.gd:303` 的 `_SILENT_KEYS` 不动）
5. **禁重构 Intent 管线 / 常量集中类**（P5/P6 已沉淀）
6. **禁碰经济模拟复杂度**（P5/P6 已过深；calendar 接入点是 `process_daily_consumption` 末尾，不是经济模块内部）

---

## 7. 修改面汇总

| 文件 | 行号 | 改动类型 | 行数 |
|---|---|---|---|
| `scripts/state/CalendarState.gd` | 新建 | 新文件 | ~80 |
| `data/calendar_eras.json` | 新建 | 新文件 | ~10 |
| `scripts/GameState.gd` | :15, :154, :494, :512 | 插入 | 6 |
| `scripts/PortStatusBar.gd` | 末尾追加 chip | 插入 | ~15 |
| `scripts/PortScreenController.gd` | 新增按钮 + handler | 插入 | ~25 |

**总计**：2 新建 + 3 改动，新增代码 ~130 行（不含测试），修改现有 ~50 行。

---

_主审钉死。5 集成点对应真实代码行；tick 注入点（集成点 1）解决 WorldMap while 循环同源问题；年号 1255 宝祐三年经现有内容 grep 核实（6 处"宝祐三年"，与章一"兴化开学"开篇 time 字段吻合）。领单模型照此实现，无歧义。_
