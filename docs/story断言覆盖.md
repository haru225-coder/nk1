# story 断言覆盖表（lane w20-c6，2026-10-02）

盘点范围：`tools/godot_story_check.gd`（现 439 处 `_check` 调用 + 5 处 `_c6_check` 位置；`STORY_CHECK TOTAL asserts run=` 走运行时计数，story 那道 102s）。
本文件只做覆盖盘点与补白清单；过场门禁升级归 w20-c3。

「断言面」记法中 4 座结局各自成功就位 + 两份失败断（落定后再试拒、摘旗回退兜底），实际子断言数见 §二列序。

## 一、覆盖账

### 1. 结局面 × 有无断言

「面」的识别口径：终章四条走 `chapters.json[3].endings`（结算幕表，GameState 的 `try_resolve_ending`）；
历史六条走 `finish("…")` 落定 `ended`（题头 / 过场在 `cutscenes.json:endings`）。两套路径分开记。

| 来源 | 局面 | 结局名 | 旗标门槛 | 断言面 | 断言位置 |
|---|---|---|---|---|---|
| chapters 终章 | 海商线信件路 | 海口信路（`sea_letter`） | `chen_line_open / letter_to_xinghua / temple_route` | **有（c6 新）** | `_c6_endings_gate_check` B 组逐面 |
| chapters 终章 | 海商线账路 | 账上的距离（`ledger_distance`） | `merchant_distance / merchant_caution` | **有（c6 新）** | 同上 |
| chapters 终章 | 士人线风路 | 史册未落笔（`history_wind`） | `history_pressure_seen` | **有（c6 新）** | 同上 |
| chapters 终章 | 兜底 | 南海一纲（`south_sea`） | 无（殿后） | **有（c6 新）** | 同上 D 组「摘旗回落」 |
| finish 历史 | 士人线城破 | 忠肃（`ending_zhongsu`） | 城破结算 | **有** | `_v0928_siege_check` 全节 + 涵江卡结语 |
| finish 历史 | 士人线错过守城 | 未归（`ending_weigui`） | 旗标 `renamed_wenlong` + 兴化 fallen + 未开城防 | **有** | `_initialize` 「未归」节（两条支路） |
| finish 历史 | 海商线在外 | 海上宋鬼 | — | **无**（只断 finish 可落定，未断窗 / 旗标语义） | — |
| finish 历史 | 海商线站蒲 | 泉州蒲氏的船 | — | **有（部分）** | 蒲家折扣断言 + 「未归判据可排除」旁路 |
| finish 历史 | 海商线收场 | 纲首（`ending_gangshou`） | — | **有** | `finish("纲首", "正文若干")` round-trip |
| finish 历史 | 乡土线收场 | 岸上的根（`ending_root`） | — | **有** | 终局态节 + `_g9_log_fold_check` `_life_line_check` |

注：前三条历史局面的「结算幕正文 / 题头 / 过场键」归 w20-c3，本片不判。

### 2. 事件（news）× 有无断言

news.json 现 26 条。三类覆盖：
- **全量断言**（`_run_case`）：按月到期投放、1277-01 前应投数 = 实投数、不重复——覆盖全部 26 条。
- **点名断言**：11 条被 `_check` 明确点到（n_1256_03_taixue / n_1256_05_wentianxiang / n_1273_03_fanfang_panic /
  n_1276_12_quanzhou_falls / n_1272_03_no_draft / n_1273_02_dismissed / n_1273_02_xiangyang_falls /
  n_1276_10_xinghua_muster / n_1277_01_chenzan_raises / n_1277_07_xinghua_again / n_1278_12_yashan）。
- **字段枚举断言（c6 新）**：`_c6_news_only_enum_check` 26 条逐条断 `only ∈ {scholar, merchant, hometown, ""}`，
  补「公共 / 专线条数」底线（scholar+merchant 至少各一条、公共条数 > 0）。

### 3. 事件（过场 cutscenes）× 有无断言

cutscenes.json：`cutscenes`（11 终局过场 + `opening` 序章）、`chapters`（章回）、`port_banners`。
- 既有断言：`_v0928_siege_check` 只点名 忠肃 / 未归 两条过场拿 caption 字串走 `_v0928_siege_caps`。
- 其余 9 条终局过场 + opening + chapters + port_banners：story_check 不判，归 **w20-c3 过场门禁升级**（本片不做）。

### 4. scenes.json 幕 × 有无断言

104 幕按形状分四类（运行时 / 数据层都不以一种全覆盖）：
- **调查幕 `type=investigation`（4 座）**：city_tavern / city_residence / city_shipyard / city_guild。
  仅 `city_tavern` 由 抵港路由 `load_scene("ryukyu_bay"→"xinghua"→"city_tavern")` 真机走通，其余三座未点名。
- **结算幕（`result` 字段，32 座）**：142 行中 31 座由 finish / try_advance 触发，未点名断言其 result 形状。
- **剧情幕（choices，54 座）**：只数路经点附近的几座（nameless_shelter_bay / ryukyu_bay / hakata_ledger / wang_letter / burned_shrine 等）。
- **题签幕 / 港页幕 / 别型（13 座）**：题名 / 章节 / 港页 4 座各有周边断言，未列字段形状断言。

c6 补白按「形状枚举」收掉 **调查幕** 与 **结算幕** 两类的形状断言（`_c6_investigation_result_enum_check`）：
调查幕五键齐（id / label / text / effects / next）；结算幕 result 为 String 或非空 String 数组、且不同时挂 choices。
54 座剧情幕不做单幕断言——剧情幕是 GM 真机路由 + 旗标门 + 文案，已由 verify_story_data 的孤儿 / SCENE_ARCHIVE 判定覆盖；story_check 不重复。

### 5. 存档 round-trip × 已断字段

既有断言覆盖：news_seen / identity / player_name / siege（轮次 / 兵 / 石手军）/ met_ids（守城档回补读档）
/ visited_ports / ledger_notes / money / Cal 历法 / ended / ended_text / ended_at / flags（局部）。
c6 新断言补上此前缺的六项：met_ids / era_routes / era_trips / merchant_credit / last_port / hometown_tendency + ended_head
（`_c6_roundtrip_fields_check`，含 from_dict({}) 退化默认的对照断言）。

## 二、本批新断言（落库后 STORY_CHECK TOTAL asserts run=673 = 基线 525 + c6 补白 148）

1. **`_c6_endings_gate_check`**（main-hook，子断言 ~44）——终章四条的「面」三层：
   - A. 未就绪：`ready=false` / `try_resolve` 拒 / `ending_id` 未写；
   - B / C：每面按表内旗标（`require_any[0]` 或 `require_flag`）`try_resolve_ending` 命中本线，落定后再试了结被拒；
   - D：摘旗标后 `pick_ending` 回落兜底（表次序即优先级）；
   - E：落定态随存档 round-trip（`ending_id` 保留、`chapter_progress.ended=true`）。
   数据驱动读 chapters.json 现值（旗标 / 门槛现查），不抄数值；新面 / 改旗标自动跟上。
2. **`_c6_roundtrip_fields_check`**（init-hook，7 条）——存档 round-trip 的 6 个新字段 + ended_head 对照。
3. **`_c6_endings_semantics_check`**（main-hook，3 条）——结局面落定 ≠ `is_ended()`；
   `try_resolve_ending` 落定后 `ended` 仍空，须 `finish` 才翻 `is_ended`（两条路径分走）。
4. **`_c6_investigation_result_enum_check`**（main-hook，子断言 ~105，随幕数走）——调查幕 4 座逐座断考题五键齐；
   结算幕逐座断 result 形状；discoveries 14 座逐座断 name 非空（调查幕线以 id == 发现名为底）。
5. **`_c6_news_only_enum_check`**（init-hook，30 条）——news 26 条 only 枚举 + 公共 / 专线条数底线。

SUMMARY 行上一行新增断言计数：`STORY_CHECK TOTAL asserts run=673；lane w20-c6 补白新增 c6_asserts=148`（在 `fails=` 之前）。

## 三、仍空白（原因）

- **海上宋鬼 / 泉州蒲氏的船**：finish 窗 / 旗标语义的完整三层未断。蒲氏的折扣断言已局部覆盖；
  海上宋鬼暂无明显断言点（finish 后可断的 `ended_at` / `ended_text` 均通）。
- **过场 cutscenes 9 条 + opening**：归 w20-c3 过场门禁升级，本片不做（brief「不做」明写）。
- **54 座剧情幕的逐幕覆盖**：走 verify_story_data 的孤儿判定 / SCENE_ARCHIVE；story_check 若逐幕 load_scene 会重复它的判定边界。
- **investigations_done / 勘见证账（discoveries_reported 类）**：报告期不在本波断言抄；只断了「勘见面 name 非空」免责形状。
- **结算幕 result 逐幕文案走 Main 真机**：文案内容 / 题名属剧情，story_check 只断形状 / 就位，文案归实机 screenshot 门禁。

## 四、改动面

- `tools/godot_story_check.gd`：文件末尾新增 5 支 `_c6_*` 检查函数 + 3 处接线（`_initialize` 尾 / `_route_check` 尾 / `_process` SUMMARY 前一行）。
  不动既有断言；两个 `_process_c6_*_hook` 函数在文件最末，与 a1/a4/a6 的中段插行不冲突。
- 本文件。无其它改动。
