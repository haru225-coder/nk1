# Main.gd 拆解台账

`scripts/Main.gd` 按页面簇往 `scripts/ui/` 拆。每刀一节，只往后追加，不改前面各节。
手法（lane ms / mz / ms2 起一直沿用）：隔离 worktree 里改，Main 保留同名同签名的一行转发，信号目标仍是 Main 的同名方法；
新文件登记：本台账追加一节、节标题写成「## 第N刀（lane X，日期）：… → `scripts/ui/X.gd`」，跑 `python3 tools/gen_main_splits.py --write` 重生成 `tools/main_splits.txt`（lane cs13 起；check_symbols 和 godot_smoke 都只读它），另加 `godot_compile_check.gd` 的 SCRIPTS；
新文件头注写「从 Main.gd 原样搬出」，转发独占函数体、行尾不带注释（漏一样 check_symbols「一之零」判红，口径见 `docs/GATES.md` §三.1，lane cs8）；
拆分前后跑同一组固定种子探针，输出逐字节对比；最后用 `update-ref` 带旧值 CAS 快进 main。

已拆（前三刀，详见各 lane brief 的 Verify）：
`SlipKit.gd`（ms，工席纸条小件）· `LedgerPage.gd`（mz，船籍簿整页）· `ChapterSheet.gd`（ms2，升章 / 了结册页）。

---

## 第四刀（lane main4，2026-09-28）：调查 + 酒馆 / 旅店 → `scripts/ui/TavernPage.gd`

### 调查（基 `d56ba1d`：Main.gd 5327 行，233 支 func）

簇按函数跨度量（首支 func 行 → 末支 func 最后一行，含簇内 `##` 注释，不含簇间常量块）。
「被簇外调」指 Main 里被本簇以外的代码调用的函数。「他处引用」按函数名统计（不含 Main.gd，也不含本刀新增的 TavernPage.gd）。
「直读 Main.gd 的门禁」指不经 `read_main_src()` / `_main_family_src()`、直接打开 Main.gd 切片或正则的地方。
这类引用一拆就会假红或假绿，是风险的主要来源。

第 6 到第 8 名（J 257 / K 255 / D 241）只差 16 行，按行数算是并列，所以表里列了 8 簇。
ms2 台账的口径是「页面簇」，不计 I、K 两段核心流程，那样 D 排第 5。

| # | 簇（行段） | 行 / 支 | 被簇外调 | 他处引用 | 跨切依赖：Main 成员 / autoload / log_msg·load_scene | 直读 Main.gd 的门禁 | 风险 |
|---|---|---|---|---|---|---|---|
| 1 | H 守城 / 终局（`_check_absent_from_xinghua` … `_special_cards`，4401–5327） | 927 / 27 | 15 | check_symbols 10、verify_story_data 8、ShotTour 7、ChapterSheet 5、check_assets 2、story 1、smoke 1 | 8 个：choices_container 26、current_scene_id 21、body_text 12；GameState 155、Fleet 17；log_msg 18、load_scene 16 | verify_story_data 切 `_special_cards` / `_check_absent_from_xinghua`，正则扫 `_show_notice_dialog` 与 `CARD_SIEGE_*`；check_assets 读 `ENDING_BG` 和结局名；simulate_endgame 读崖山门槛 | 高 |
| 2 | A 牙行（`_setup_market` … `_on_sell`，1229–1878） | 650 / 15 | 1 | verify_economy 16、qa_contract_stock 4、check_symbols 4、qa_economy_spread 2、qa_money_notices 1 | 10 个：_market_ship 12、broker_hand 8、_market_hold 5、_contract_detail_open 5；Economy 24、Fleet 21、GameState 20、Voyage 14；log_msg 15 | verify_economy 两处直读（切 `_make_market_row` / `_affordable_qty` / 各 tip） | 高 |
| 3 | E 岸带（`_setup_port_mode` … `_on_set_sail`，3308–3817） | 510 / 19 | 7（`_band_*` 被守城 / 终局复用） | check_symbols 20、smoke 2、port_doors / siege / ending_reread 探针各 2、patrol 1、SlipKit 1、ChapterSheet 1 | 14 个：shore_hand、_shore_mode、_shore_facilities、_shore_title_seen、port_mode…；GameState 17；update_status_panel 6 | smoke 按 family src 切 `_setup_port_mode` 函数体（拆了就只切到转发） | 高：状态最散，和 H 互调 |
| 4 | C 船屋（`_yard_port_name` … `_on_buy_supplies`，2081–2407） | 327 / 15 | 3（`_on_dismiss_crew` / `_on_hire_candidate` 是酒馆钮的目标） | check_symbols 16、verify_economy 5 | 5 个：current_scene_id 17、_upgrade_busy 9；Fleet 47、GameState 30；log_msg 23、load_scene 14 | verify_economy 直读 5 处（`below_min * N` 等） | 中高 |
| 5 | I 调查页 / 选项 / 效果（`_setup_investigation_mode` … `_activate_first_choice`，4045–4340） | 296 / 14 | 3（`_add_leave_button` 全部设施页都用） | check_symbols 9、verify_story_data 7，另有 WorldMap / SeaChart / MapView / CharacterCodex / GameState 各 1–2 | 14 个；GameState 15、Fleet 7；含 `_gui_input` / `_unhandled_input` 两个引擎虚函数 | verify_story_data 直接切 `func apply_effects`（效果字段消费方） | 高：核心流程，虚函数不宜转发 |
| 6 | J 见面页（`_frame_portrait` … `_fill_npc_profile` 498–643，加上 `_add_npc_button` … `_on_npc_leave` 3133–3242） | 257 / 11 | 3 | smoke 2、ShotTour 2、check_assets 1、check_symbols 1 | 13 个：_npc_profile 14、npc_portrait 11、_npc_codex_btn 11、npc_name_lbl / npc_dialog_lbl 各 7；GameState 4；log_msg 0 | smoke 有两处切 `_show_npc_mode`，一处直读 Main.gd、一处读 family src；verify_story_data 直读 Main.gd 查 `codex_short(`；两段都拆走后 Main 就不再读人物 API，L1B 里 Main 的登记要跟着改 | 中：两段分离，_ready 里要装版面，要改 4 处门禁 |
| 7 | K 场景加载 / 分发（`load_scene` … `_setup_dynamic_scene`，974–1228） | 255 / 11 | 5 | check_symbols 20、story 19、p7 11、ShotTour 11、patrol 8、各 qa 探针 6–8 | 15 个；GameState 10 | 常量表 `PORT_BG` / `FACILITY_BG` / `FACILITY_SUFFIXES` 被 check_assets 和 verify_story_data 直读（常量可留在 Main） | 高：所有页面都经过这里 |
| 8 | **D 酒馆 / 旅店（`_setup_tavern` … `_setup_inn`，2457–2697）** | **241 / 11** | 4（`_person_slip` / `_person_foot` 被见面页复用） | check_symbols 8、qa_tavern_news_wall 4、verify_story_data 3、smoke 1、TavernNewsWall 1、LedgerPage 1（`_skill_rank`） | **5 个**：choices_container 3、current_scene_id 3、scene_title / body_text / choices_label 各 2；Crew 8、GameManager 5、Calendar 4、GameState 3；log_msg 2、load_scene 2 | verify_story_data 与 qa_tavern_news_wall 直读 Main.gd 查 `_TAVERN_NEWS_WALL.mount`（`_setup_news_wall` 留在 Main，不受影响）；simulate_run 直读 `const INN_RATE`（常量留在 Main）；smoke 按 family src 切 `_setup_tavern`（本刀改去 TavernPage 里切）；L1B 新增一个 character_for_crew 读取口要登记 | **最低 → 本刀** |

另两簇更小，也都独立：F 航海日志 127 / 5（只用 `_save_host`，Python 门禁里没有直读它的）；G2 行会 / 贡院 203 / 11（check_symbols 有 66 处源码断言，p7 专门盯它）。

**为什么选 D**：连续一段，簇内不存状态（只读 5 个 Main 的 UI 成员），回调全是 bind 到 Main 的同名方法。
直读 Main.gd 的门禁里，3 处可以原地不动（`_setup_news_wall` 和 `INN_RATE` 本来就留在 Main），1 处改切拆出件，1 处在 L1B 登记新入口，一共只改 2 道门禁。
J 与它大小相当，但要改 4 处门禁，还牵涉 Main 在 L1B 的登记；I / K / E / H 都在核心流程上或互相调用；A / C 被 verify_economy 直读。

### 落地

- `scripts/ui/TavernPage.gd`（新增，243 行）：9 支 `static func` 原样搬出（setup_tavern / setup_story_hooks / on_story_hook / on_gather_intel / setup_hiring / person_slip / person_foot / seal_chip / setup_inn）。
  Main 里原本的调用都改写成 `main.` 前缀。经 `main.` 取值推断不出类型，12 处 `:=` 改为显式类型（VBoxContainer / HBoxContainer / Button / HFlowContainer）。
- Main.gd **5327 → 5134（−193）**。Main 里保留同名同签名的一行转发（`const _TAVERN := preload(...)`）；
  `_setup_news_wall`、`_skill_rank`、`INN_RATE`、`HIRE_PIC` 不动（原因见表）。
- 门禁同步：两处 `MAIN_SPLITS` 都加 TavernPage.gd；`godot_compile_check` 的 SCRIPTS 加 1 行；
  `godot_smoke` 的「酒馆募人排成工席」改去 TavernPage 里切 `static func setup_tavern(`；
  `verify_story_data` 的 `L1B_READERS` 加上 TavernPage.gd（`{"api"}`，读 character_for_crew）。
- 拼回原文：用 `read_main_src()` 拼回的 9 支和基线 Main 逐行比，除上面 12 行 `:=` 外完全一致。

### 下一刀候选（行数按基 d56ba1d）

1. **F 航海日志**（127 / 5）风险低，和 ChapterSheet 同属浮层册页，可以直接做。
2. **J 见面页**（257 / 11）风险中。要改 smoke 的两处切片，verify_story_data 查 `codex_short(` 的那处改读 family src；两段都拆走后 Main 不再读人物 API，L1B 里 Main 的登记要改。
3. **G2 行会 / 贡院**（203 / 11）风险中。check_symbols 有 66 处断言，都经 read_main_src 读；p7 只经方法名调用。`play_transition` 是公共件，不要一起搬。
4. **A / C / H / I / K** 风险高。先单开一个门禁 lane，给 verify_economy / verify_story_data / check_assets / simulate_endgame / simulate_run 共用一个「读 Main 家族源码」的 helper。
5. 门禁小事：`MAIN_SPLITS` 已经登记到第 4 件，建议抽成 `tools/main_splits.txt`，check_symbols 和 smoke 共读（ms2 待议 6）。

---

## 第五刀（lane main5，2026-09-28）：调查 + 见面页 → `scripts/ui/NpcPage.gd`

### 调查（基 `6ff3d01`：Main.gd 5134 行，第四刀之后）

口径同第四刀：簇跨度从首支 func 行算到末支 func 的最后一行，含簇内 `##` 注释，不含簇间常量块和分节横线。
「被簇外调」「他处引用」「直读 Main.gd 的门禁」的含义也同上（他处引用不含 Main.gd，也不含本刀新增的 NpcPage.gd）。
按纯行数，第 6 名 K（251）和第 7 名 J（250）只差 1 行，算并列，所以表里列 7 簇。
按 ms2 的「页面簇」口径，I、K 两段核心流程不算，前 6 是 H / A / E / C / J / G2。两种口径 J 都在前 6。

| # | 簇（行段） | 行 / 支 | 被簇外调 | 他处引用 | 跨切依赖：Main 成员 / autoload / log_msg·load_scene | 直读 Main.gd 的门禁 | 风险 |
|---|---|---|---|---|---|---|---|
| 1 | H 守城 / 终局（`_check_absent_from_xinghua` … `_special_cards`，4208–5131） | 924 / 27 | 15 | check_symbols 10、verify_story_data 8、ShotTour 7、ChapterSheet 5、check_assets 2、story 1、smoke 1 | 8 个：choices_container 26、current_scene_id 21、body_text 12；GameState 155、Fleet 17；log_msg 18、load_scene 16 | verify_story_data 切 `_special_cards` / `_check_absent_from_xinghua`；check_assets 读 `ENDING_BG` 和结局名；simulate_endgame 读崖山门槛 | 高 |
| 2 | A 牙行（`_setup_market` … `_on_sell`，1233–1878） | 646 / 15 | 1 | verify_economy 16、qa_contract_stock 4、check_symbols 4、qa_economy_spread 2、qa_money_notices 1 | 10 个：_market_ship 12、broker_hand 8、_market_hold 5、_contract_detail_open 5；Economy 24、Fleet 21、GameState 20、Voyage 14；log_msg 15 | verify_economy 直读（切 `_setup_market` / `_add_contract_panel` / `_make_market_row` / `_affordable_qty` / 各 tip） | 高 |
| 3 | E 岸带（`_setup_port_mode` … `_on_set_sail`，3115–3620） | 506 / 19 | 7（`_band_*` 被守城 / 终局复用） | check_symbols 20、smoke 2、port_doors / siege / ending_reread 探针各 2、patrol 1、SlipKit 1、ChapterSheet 1 | 14 个：shore_hand、_shore_mode、_shore_facilities、_shore_title_seen、port_mode…；GameState 17；update_status_panel 6 | smoke 按 family src 切 `_setup_port_mode` | 高：状态最散，和 H 互调 |
| 4 | C 船屋（`_yard_port_name` … `_on_buy_supplies`，2083–2401） | 319 / 15 | 1（`_on_dismiss_crew` / `_on_hire_candidate` 由 TavernPage 经 main. 接钮） | check_symbols 16、verify_economy 5、TavernPage 2 | 5 个：current_scene_id 17、_upgrade_busy 9；Fleet 47、GameState 30；log_msg 23、load_scene 14 | verify_economy 直读 5 处 | 中高 |
| 5 | I 调查页 / 选项 / 效果（`_setup_investigation_mode` … `_activate_first_choice`，3852–4143） | 292 / 14 | 3（`_add_leave_button` 全部设施页都用） | check_symbols 9、verify_story_data 7、CharacterCodex / TavernPage 各 2，WorldMap / SeaChart / MapView / GameState 各 1 | 14 个；GameState 15、Fleet 7；含 `_gui_input` / `_unhandled_input` 两个引擎虚函数 | verify_story_data 直接切 `func apply_effects` | 高：核心流程，虚函数不宜转发 |
| 6 | K 场景加载 / 分发（`load_scene` … `_setup_dynamic_scene`，978–1228） | 251 / 11 | 5 | check_symbols 20、story 19、p7 11、ShotTour 11、patrol 8、各 qa 探针 6–8 | 15 个；GameState 10 | `PORT_BG` / `FACILITY_BG` / `FACILITY_SUFFIXES` 被 check_assets、verify_story_data 直读（常量可留在 Main） | 高：所有页面都经过这里 |
| 7 | **J 见面页（`_frame_portrait` … `_fill_npc_profile` 502–643，`_add_npc_button` … `_on_npc_leave` 2940–3047）** | **250 / 11** | 3（`_frame_portrait` / `_dress_npc_sheet` 在 `_ready`；`_add_npc_button` 被市舶司页与 TavernPage 调） | TavernPage 2、smoke 2、ShotTour 2、check_assets 1（注释）、check_symbols 1 | 13 个：_npc_profile 14、npc_portrait 11、_npc_codex_btn 11、npc_name_lbl / npc_dialog_lbl 各 7、npc_actions 6；GameState 4、GameManager 4；log_msg 0、load_scene 0 | smoke 两处切 `_show_npc_mode`（一处直读 Main.gd、一处读 family src，都会切到转发）；verify_story_data 直读 Main.gd 查 `codex_short(`；L1B / L1 上屏入口要登记新文件 | **中 → 本刀** |

另外两簇更小：G2 行会 / 贡院 200 / 11（check_symbols 有 66 处引用，都经 read_main_src；p7 专门盯它；`play_transition` 是公共件）；F 航海日志 120 / 5（`_show_save_dialog` … `_on_load_slot`，只用 `_save_host`，Python 门禁里没有直读它的）。

**为什么选 J**：前 6 名（两种口径都算）里只有 J 不是高或中高。簇内不存状态，11 个状态成员都留在 Main、经 `main.` 取；回调都 bind 到 Main 的同名方法。
J 只调 GameState / GameManager 各 4 处，不碰 log_msg / load_scene。要改的门禁有 4 处：smoke 两处切片、verify_story_data 的 `codex_short(`，以及 L1B / L1 登记。
第四刀台账预计「两段都拆走后 Main 就不再读人物 API」，实测不对：Main 的人物志钮还调 `all_characters()`，所以 Main 仍留在 L1B，只改了说明文字。
H / A / E / I / K 在核心流程上或被 Python 门禁多处直读；C 被 verify_economy 直读 5 处，本刀新加的旅店门禁（见下）也直读 Main 的 `_on_rest` / `_setup_residence`。

### 落地

- `scripts/ui/NpcPage.gd`（新增，264 行，`.uid` 同 commit）：11 支原样搬成 `static func`（frame_portrait / dress_npc_sheet / mount_npc_profile / fill_npc_profile / add_npc_button / on_meet_npc / show_npc_mode / set_npc_speech / on_npc_intel / on_npc_bribe / on_npc_leave），招呼常量 `NPC_GREETING` 随簇搬走。
  Main 成员一律加 `main.` 前缀。经 `main.` 取值推断不出类型，13 处 `:=` 改成与原推断相同的显式类型（Node / int / String / Label / VBoxContainer / HBoxContainer）。
  人物志钮仍是一个 lambda（`main._open_codex(main._npc_codex_id)`），按下时才读 id，行为不变。
- Main.gd **5134 → 4929（−205）**。Main 保留同名同签名的一行转发（`const _NPC := preload(...)`）。
  11 个状态成员（npc_mode / npc_portrait / npc_name_lbl / npc_dialog_lbl / npc_actions / _npc_speech / _npc_courtesy / _npc_faction / _npc_profile / _npc_codex_btn / _npc_codex_id）和 `_CHAR_ART` 留在 Main。
- 门禁同步：
  - 两处 `MAIN_SPLITS` 都加 NpcPage.gd；`godot_compile_check` 的 SCRIPTS 加 1 行。
  - `godot_smoke` 的「见面行情走工席」「见面页立绘先认 characters.json」两处改去 NpcPage 里切 `static func show_npc_mode(`（前一处切完去掉 `main.` 前缀再比）。
    「见面册疏通留出字距」查 `UiTheme.plain_log(_gather_price_intel` 的那半句，改成在去掉 `main.` 前缀的 family src 里查：smoke 的 family src 只把文件拼在一起，不像 check_symbols 的 read_main_src 会去前缀。
  - `verify_story_data`：见面页简介改查 NpcPage（Main 里仍不许出现 `"bio_short"`）；`L1B_READERS` 加 NpcPage（`{"api"}`，读 character_for_npc），Main 那条的说明文字改掉；`L1_UI_FILES` 加 NpcPage，让搬走的 `ch.get(...)` 仍在上屏字段白名单的扫描范围内。
- 拼回原文：`read_main_src()` 拼回的 11 支和基线 Main 逐行比，除上面 13 行 `:=` 外完全一致。

### 同刀门禁：旅店房钱算式（第四刀待议 2）

`verify_economy.py` 加 4 条源码断言：
1. `_on_rest` 默认费率 INN_RATE，扣钱 = 日数 × 费率，扣的和记事写的是同一笔；
2. 旅店（`TavernPage.setup_inn`）每个接 `_on_rest` 的钮：钮文里的日数、价的日数、bind 的日数是同一个变量，价的费率是 INN_RATE，bind 不另塞费率；
3. 住处（`Main._setup_residence`）同理，走 HOME_RATE；
4. Main 的 INN_RATE 等于 simulate_run 算候风成本用的 INN_RATE。

第四刀的 M11（`nights * 16`）原样改回去，现在判红。

### 下一刀候选（行数按基 6ff3d01）

1. **F 航海日志**（120 / 5）风险低，和 ChapterSheet 同属浮层册页。check_symbols 的 `_show_save_dialog` / `_on_save_slot` / `_on_load_slot` 断言都经 read_main_src，不用改；smoke 有一处在 family src 里切 `func _show_save_dialog`（会切到转发），要改去拆出件里切。
2. **G2 行会 / 贡院**（200 / 11）风险中。check_symbols 的 66 处引用都经 read_main_src；verify_economy / simulate_run 用 `gd_const("scripts/Main.gd", "GUILD_*")` 直读常量，常量留在 Main 就不受影响。`play_transition` 不要一起搬。
3. **A / C / H / I / K / E** 风险高。先单开一个门禁 lane，给 verify_economy / verify_story_data / check_assets / simulate_endgame / simulate_run 共用一个「读 Main 家族源码」的 helper。本刀的旅店断言直接读 TavernPage.gd，也应该改走这个 helper。
4. 门禁小事：`MAIN_SPLITS` 已经登记到第 5 件，两份清单（check_symbols / smoke）靠对账同步，建议抽成 `tools/main_splits.txt` 共读（ms2 待议 6、第四刀候选 5）。

---

## 第六刀（lane main6，2026-09-28）：航海日志 → `scripts/ui/SaveSheet.gd`

### 调查（基 `537826b`：Main.gd 4929 行，第五刀之后）

口径同前两刀（跨度从簇首 `##` 注释算到末支 func 最后一行；「他处引用」不含 Main.gd，也不含本刀新增的 SaveSheet.gd）。
F 航海日志是第五刀台账列的下一刀首选，连续一段：**3419–3538，120 行 / 5 支**。

| 支 | 行段 | 行 | 做什么 | 被簇外调（Main 内 / 他处） |
|---|---|---|---|---|
| `_show_save_dialog(read_only := false)` | 3419–3501（含 `##` 注释） | 83 | 旧 host 先释放 → 让开港名匾 → 建 `SaveSheet` 浮层（暗幕 + 居中绢本册页 + 标题「航海日志」）→ 三卷工席（卷号、题签、坏档脚注、「记录」「翻阅」）→ 按两行工席高定 Benches 高 →「合上」→ `pop_in` | Main 3 处：标题页「续卷」`.bind(true)`（454）、岸带动作行「航海日志」（3104）、`_add_save_button`（3998）；ShotTour `_site_save` 1 处 `call` |
| `_on_save_dim_input(event)` | 3504–3508 | 5 | 暗幕上鼠标**按下**才合上（松开、移动不合） | 无（只是暗幕 `gui_input` 的目标） |
| `_close_save_sheet()` | 3511–3516 | 6 | 释放 host、清 `_save_host`；港页可见且升章册页不在时港名匾回来 | Main 1 处：`_unhandled_input` 的 ui_accept（3905） |
| `_on_save_slot(slot)` | 3519–3524 | 6 | `SaveLoad.save_game(slot, current_scene_id)`；失败记「誊写未成」、册页不合；成了先合上再记事 | 无（「记录」钮的目标） |
| `_on_load_slot(slot)` | 3527–3538 | 12 | 先取卷里的场景和是否副抄 → `load_game`；失败记 `load_fail_note`、册页不合；成了合上 → 刷状态栏 → `load_scene`（卷里没场景就回 `last_port`）→ 记事，副抄另记一句 | 无（「翻阅」钮的目标） |

**跨切依赖**（全部经 `main.` 取，搬出件不存状态）：
- Main 成员：`_save_host` 6（读写，唯一的簇状态，留在 Main；`_unhandled_input` 也读它）、`port_mode` 2、`_chapter_host` 1、`current_scene_id` 1。
- Main 方法：`log_msg` 5、`_show_port_layer` 2、`_slip_chip` 2、`_slip_body` / `_slip_title` / `_slip_note` / `_slip_row` / `_begin_benches` / `_end_benches` / `_cn_chapter` / `_dismiss_banner` / `update_status_panel` / `load_scene` 各 1；还有回连的 4 个信号目标 `_on_save_dim_input` / `_on_save_slot` / `_on_load_slot` / `_close_save_sheet`。
- autoload：`SaveLoad` 10、`UiTheme` 7、`GameState` 1（`last_port`）、`Calendar` 1。

**断言 / 探针引用点**（拆前逐个核过）：

| 引用点 | 怎么读 | 拆后 |
|---|---|---|
| `godot_smoke.gd:388`「航海日志三卷走工席，合上不再拉满宽」 | 在 `_main_family_src()`（Main + MAIN_SPLITS **原样拼接**，不去前缀、不换函数体）里切 `func _show_save_dialog` | 会切到一行转发，假红 → **改去 SaveSheet.gd 里切** `static func show_save_dialog(`，切完去 `main.` 前缀再比；5 个子条件原样不动 |
| `godot_smoke.gd:380-386`「航海日志空卷写成未记」里的 `main_src.find("存档 / 读档") < 0` | family src 全文反向查 | MAIN_SPLITS 加上 SaveSheet 后搬走的文字仍在扫描范围内，不用改 |
| `check_symbols.py:2034` 两条（绢本册页 / 三卷走工席） | `_func_body(main_src, "_show_save_dialog")`，`main_src = read_main_src()`（1792 行） | `read_main_src()` 把转发就地换回 SaveSheet 的函数体、去 `main.` 前缀，切到的就是原文 → **不用改**（加 MAIN_SPLITS 登记即可；漏登记则这几条判红，见 Verify M10） |
| `check_symbols.py:3854-3856`（坏档脚注 / 翻阅副抄句 / 记录失败句） | `func_bodies(main_src)` 取 `_show_save_dialog` / `_on_load_slot` / `_on_save_slot`，`main_src = read_main_src()`（3429 行） | 同上，不用改 |
| `tools/art/ShotTour.gd:577` `_site_save` | `_main.call("_show_save_dialog")` | Main 保留同名转发，不用改 |
| `tools/art/ShotTour.gd:172` 浮层清单 | 按节点名 `SaveSheet` 找 | 节点名不变，不用改 |
| `tools/qa_save_slot_tip_probe.gd` | 只读 SaveLoad 槽态，不碰册页 | 无关 |

**为什么现在做 F**：簇内只有一个状态成员（留 Main），5 支全是浮层自己的建与回调，不碰核心流程；
Python 门禁里没有直读 Main.gd 的（全经 `read_main_src()`），只有 smoke 一处要改切片位置。剩下的 G2（200 / 11）风险中，A / C / E / H / I / K 风险高（理由见第五刀）。

### 落地

- `scripts/ui/SaveSheet.gd`（新增，131 行，`.uid` `uid://cjwulshq3w8jx` 同 commit）：5 支原样搬成 `static func`（show_save_dialog / on_save_dim_input / close_save_sheet / on_save_slot / on_load_slot），Main 成员一律加 `main.` 前缀。
  信号目标仍是 Main 的同名方法（`main._on_save_dim_input` / `main._on_save_slot.bind(n)` / `main._on_load_slot.bind(n)` / `main._close_save_sheet`），`read_main_src()` 去前缀后与原文同。
  经 `main.` 取值推断不出类型，4 处 `:=` 改为与原推断相同的显式类型（`slip: VBoxContainer`、`row: HFlowContainer`、`write` / `read: Button`）。
- Main.gd **4929 → 4831（−98）**，func 数不变（233，5 支都留同名同签名一行转发，`const _SAVE := preload(...)`）；`_save_host` 与 `_unhandled_input` 留在 Main。
- 门禁同步：两处 `MAIN_SPLITS`（check_symbols / smoke）都加 SaveSheet.gd；`godot_compile_check` 的 SCRIPTS 加 1 行（124 → 125）；smoke 的那一处切片改去 SaveSheet 里切（上表）。**断言条件一条没改、没放宽。**
- 拼回原文：`read_main_src()` 拼回的 5 支和基线逐行比，除上面 4 行 `:=` 外完全一致（末支后少一个空行，是拼接时拆出件文件尾只有一个换行，断言不看空行）。

### 下一刀候选（行数按基 537826b）

1. **G2 行会 / 贡院**（200 / 11）是剩下唯一风险「中」的页面簇：check_symbols 的 66 处引用都经 read_main_src；verify_economy / simulate_run 用 `gd_const("scripts/Main.gd", "GUILD_*")` 直读常量（常量留 Main 即可）；p7 只经方法名调用；`play_transition` 是公共件，不要一起搬。
2. **A / C / E / H / I / K** 风险高，先做「Main 家族源码」共用 helper 的门禁 lane（第五刀候选 3）。
3. `MAIN_SPLITS` 已到第 6 件，两份清单靠对账同步，建议抽 `tools/main_splits.txt` 共读（ms2 待议 6 起一直挂着）。

---

## 第七刀（lane main7，2026-09-28）：调查 + 行会 / 贡院 → `scripts/ui/GuildExamPage.gd`

### 调查（基 `59254f5`：Main.gd 4831 行，233 支 func，第六刀之后）

口径同前三刀：簇跨度从簇首 `##` 注释算到末支 func 的最后一行，不含簇间常量块和分节横线。
「被簇外调」「他处引用」「直读 Main.gd 的门禁」的含义也同上（他处引用按函数名统计，不含 Main.gd，也不含本刀新增的 GuildExamPage.gd）。
直读门禁的行号都是基 `59254f5` 的行号。

剩余最大 6 簇都是高或中高风险。按纯行数，G2 排第 7；按 ms2 的「页面簇」口径（I、K 两段核心流程不算），前 6 是 H / A / E / C / **G2** / Y。
所以表里列 7 簇。

| # | 簇（行段） | 行 / 支 | 被簇外调 | 他处引用 | 跨切依赖：Main 成员（state / ui）/ autoload / log_msg·load_scene（msg） | 直读 Main.gd 的门禁 | 风险 |
|---|---|---|---|---|---|---|---|
| 1 | H 守城 / 终局（`_check_absent_from_xinghua` … `_special_cards`，3905–4828） | 924 / 27 | 15 | check_symbols 10、verify_story_data 8、ShotTour 7、ChapterSheet 5、check_assets 2、story 1、smoke 1 | 8 个：choices_container 26、current_scene_id 21、body_text 12、scene_title / choices_label 各 7；GameState 155、Fleet 17、UiTheme 12；log_msg 18、load_scene 16 | verify_story_data 正则扫 `CARD_SIEGE_*`（:210）、切 `_special_cards`（:846）；check_assets 读 `ENDING_BG`（:54）；simulate_endgame 读崖山门槛（:195） | 高 |
| 2 | A 牙行（`_setup_market` … `_on_sell`，1113–1758） | 646 / 15 | 1 | verify_economy 16、qa_contract_stock 4、check_symbols 4、qa_economy_spread 2、qa_money_notices 1 | 10 个：_market_ship 12、broker_hand 8、_market_hold 5、_contract_detail_open 5；UiTheme 32、Economy 24、Fleet 21、GameState 20、Voyage 14；log_msg 15、load_scene 7 | verify_economy 直读 Main.gd 切 `_affordable_qty` / `_setup_market` / `_add_contract_panel` / `_make_market_row`（:1940–1951） | 高 |
| 3 | E 岸带（`_setup_port_mode` … `_on_set_sail`，2913–3418） | 506 / 19 | 7（`_band_*` 被守城 / 终局复用） | check_symbols 20、smoke 2、port_doors / siege / ending_reread 探针各 2、patrol 1、SlipKit 1、ChapterSheet 1、story 1 | 14 个：shore_hand 6、port_mode 5、_shore_mode 5、_shore_facilities 4…；UiTheme 39、GameState 17；log_msg 7、update_status_panel 6 | smoke 在 family src 里切 `func _setup_port_mode`（:451） | 高：状态最散，和 H 互调 |
| 4 | C 船屋（`_yard_port_name` … `_on_buy_supplies`，1964–2281） | 318 / 15 | 1（`_on_dismiss_crew` / `_on_hire_candidate` 另由 TavernPage 经 main. 接钮） | check_symbols 16、verify_economy 5、TavernPage 2 | 5 个：current_scene_id 17、_upgrade_busy 9；Fleet 47、GameState 30；log_msg 23、load_scene 14 | verify_economy 直读 Main.gd 切 `_on_upgrade` / `_on_repair_hull` / `_on_buy_ship`（:838–855）、`below_min * N`（:1304） | 中高 |
| 5 | I 调查页 / 选项 / 效果（`_setup_investigation_mode` … `_activate_first_choice`，3549–3840） | 292 / 14 | 3（`_add_leave_button` 全部设施页都用，本刀的 G2 也用） | check_symbols 9、verify_story_data 7、CharacterCodex / TavernPage 各 2，WorldMap / SeaChart / MapView / GameState / TavernFacilitySlip 各 1 | 14 个；GameState 15、Fleet 7；含 `_gui_input` / `_unhandled_input` 两个引擎虚函数 | verify_story_data 直切 `func apply_effects`（:26） | 高：核心流程，虚函数不宜转发 |
| 6 | K 场景加载 / 分发（`load_scene` … `_setup_dynamic_scene`，858–1108） | 251 / 11 | 5 | check_symbols 20、story 19、p7 11、ShotTour 11、qa_money_notices / patrol 各 8、qa_crew_hire 7、qa_contract_stock 6 | 15 个；GameState 10 | `PORT_BG` / `FACILITY_BG` 被 check_assets 直读（:54，常量可留 Main）；check_symbols 查 `_setup_dynamic_scene` 里的 `_setup_guild(base_loc)` | 高：所有页面都经过这里 |
| 7 | **G2 行会 / 贡院（`_guild_port_id` … `_on_guild_join` 2404–2500，`_setup_exam` … `_on_exam_sit` 2519–2605）** | **184 / 10** | 2（`_setup_guild` / `_setup_exam`，都由 `_setup_dynamic_scene` 调） | check_symbols 51、p7 5、verify_economy 3、smoke 3 | **4 个**：current_scene_id 3、scene_title / body_text / choices_label 各 2；GameState 36、GameManager 8、Calendar 4、UiTheme 1；log_msg 6、load_scene 3（1 直调 + 2 个 bind）、play_transition 2 | verify_economy 直读 Main.gd 切 `_on_guild_join` / `_on_exam_sit` / `_setup_exam`（:2099 / 2122 / 2124）；verify_economy / simulate_run 直读 `GUILD_*` / `EXAM_*` 常量（常量留 Main）；smoke 在 family src 里切 `func _on_exam_copy`（:557） | **中 → 本刀** |

表外还有两簇，都比 G2 小：Y 市舶司 / 呈报 / 职衔 119 / 7（`_setup_yamen` … `_attention_desc` 1763–1881，只有 check_symbols 29 处引用、全经 read_main_src，qa_discovery_probe 经 Main 调 `_on_report_discovery`）；T 住处 / 寺观 117 / 6（`_setup_residence` … `_on_temple_rub` 2608–2724，smoke 两处在 family src 里切 `_on_temple_look` / `_on_temple_rub`，verify_economy 直读 `_setup_residence`）。

**G2 的切面**（中间夹着的 `play_transition` 2503–2516 是公共件：入行 / 赴试 / 章节卡 / 船屋都用，不搬）：

| 支 | 行段（含 `##`） | 行 | 做什么 | 被谁调（Main 内 / 他处） |
|---|---|---|---|---|
| `_guild_port_id(page_id)` | 2404–2410 | 7 | 尾部 `_guild` 剥尽回基港 id | 簇内 4 处；check_symbols remap 契约 |
| `_setup_guild(port_id)` | 2413–2442 | 30 | 行会页：正文、按商誉抄 3 / 5 条出港行情（`_collect_spreads`）、会籍工席、离开钮 | `_setup_dynamic_scene`（1101）；smoke / check_symbols 查定义 |
| `_add_guild_join_slip(port_id)` | 2445–2467 | 23 | 会籍 / 入行工席：非三港「本港无会籍」、已入行「本港已入行」、否则「交会费入行」朱钮 | 簇内 1 处 |
| `_guild_join_block(port_id)` | 2470–2481 | 12 | 返回不收的缘由（港 / 已入行 / 商誉 / 现钱），空串即可入行 | 簇内 1 处 |
| `_on_guild_join(port_id)` | 2484–2500 | 17 | 查门槛 → 扣会费 → 商誉 / 人脉 → 写 `guild_<港>` → 记事 → `await play_transition` 全黑时重载本页 | 「交会费入行」钮；p7 直调 4 处 |
| `_setup_exam(port_id)` | 2519–2548 | 30 | 贡院页：誊录工席 + 赴试工席（别港「本港无贡院科场」、本章已赴只读） | `_setup_dynamic_scene`（1103） |
| `_exam_slip()` | 2551–2556 | 6 | 卡压到 `EXAM_SLIP_MIN_H`、行距 6 | 簇内 2 处 |
| `_on_exam_copy(_port_id)` | 2559–2568 | 10 | 工钱 + 学者倾向先落袋，再 advance_days，重载本页 | 「替人抄三日」钮 |
| `_exam_sat_flag()` | 2571–2572 | 2 | `exam_sat_ch<章>` | 簇内 2 处 |
| `_on_exam_sit(port_id)` | 2575–2605 | 31 | 拦别港 / 本章已赴 → 写章旗标 → 学者 / 海路两支 → 晋升改题 → advance_days → 记事 → `await play_transition` | 「入场赴试」钮；p7 直调 1 处 |

**跨切依赖**（全部经 `main.` 取，搬出件不存状态）：
- state：簇内**没有**状态成员；读 Main 的 `current_scene_id` 3 次（重载本页）。
- ui：`scene_title` / `body_text` / `choices_label` 各 2；工席小件 `_slip_note` 13、`_slip_title` 7、`_slip_row` 7、`_slip_body` 4、`_slip_stamp` 4、`_slip_chip` 3、`_slip_whole` 3、`_begin_benches` / `_center_benches` / `_end_benches` / `_add_leave_button` 各 2、`_collect_spreads` 1。
- msg：`log_msg` 6、`play_transition` 2、`load_scene` 3。
- 常量：`GUILD_JOIN_FEE` 5、`GUILD_JOIN_CREDIT` 3、`EXAM_STIPEND` / `EXAM_SIT_DAYS` / `EXAM_COPY_DAYS` 各 3、`GUILD_JOIN_PORTS` / `GUILD_JOIN_CREDIT_GAIN` / `GUILD_JOIN_NETWORK_GAIN` / `EXAM_SIT_PORTS` 各 2、`GUILD_CREDIT_WIDE` / `EXAM_SLIP_MIN_H` 各 1，全都留在 Main。
- autoload：GameState 36、GameManager 8、Calendar 4、UiTheme 1。
- 回连的信号目标 3 个：`_on_guild_join.bind(port_id)` / `_on_exam_copy.bind(port_id)` / `_on_exam_sit.bind(port_id)`。

**断言 / 探针引用点**（拆前逐个核过，行号按基 `59254f5`）：

| 引用点 | 怎么读 | 拆后 |
|---|---|---|
| `verify_economy.py:2099 / 2122 / 2124`（九之七：入行一次扣费、赴试不发钱、两支增量、赴试港限制，共 4 条） | `main_body()` **直读 Main.gd**，切 `func _on_guild_join` / `_on_exam_sit` / `_setup_exam` | 会切到一行转发，4 条假红（实测）→ **改去 GuildExamPage.gd 里切** `static func on_guild_join(` / `on_exam_sit(` / `setup_exam(`，切前去 `main.` 前缀；条件原样。`main_body()` 再没有别的调用方，一起删掉 |
| `verify_economy.py:2100–2103 / 2123 / 2134`、`simulate_run.py:1147–1151` | `gd_const` / `main_const` 直读 Main.gd 的 `GUILD_*` / `EXAM_*` 常量、`const EXAM_SIT_PORTS` 字面 | 常量留在 Main，不用改 |
| `godot_smoke.gd:557`「贡院誊录只加学者倾向、不给名声」 | 在 `_main_family_src()` 里切 `func _on_exam_copy` | 会切到转发，假红（实测）→ **改去 GuildExamPage.gd 里切** `static func on_exam_copy(`，去 `main.` 前缀再比；条件原样 |
| `godot_smoke.gd:499`、`check_symbols.py:2487`（账条字样：`"运往 %s　多 %d"` 须在） | family src / `read_main_src()` 全文查 | 这句随 `_setup_guild` 搬走；MAIN_SPLITS 登记上就还在扫描范围内。**漏登记就判红**（实测两道都红） |
| `godot_smoke.gd:552`（四个动态页有定义） | family src 查 `func _setup_guild` / `func _setup_exam` | Main 留着同名转发，不用改 |
| `check_symbols.py:2819 / 2835 / 2862–3060`（函数定义、誊录不给名声、入行接线 / 门槛 / 已入行、remap 契约 `_guild_remap_contract`、赴试每章一次 / 时序 / 港限制、誊录时序） | 都经 `read_main_src()`（:1793），`func_bodies` / 正则切 | `read_main_src()` 把转发就地换回拆出件的函数体、去 `main.` 前缀 → **不用改**（登记 MAIN_SPLITS 即可） |
| `check_symbols.py:2979` remap 变异自检（6 份变异源码） | 在 `read_main_src()` 结果上做**逐字字符串替换**（如 `"func _on_guild_join(port_id: String) -> void:\n\tport_id = _guild_port_id(port_id)\n"`） | 拼回文本和原文逐字相同，替换仍然命中；拆后「6 份变异均被拦下」照旧 |
| `check_symbols.py:2926`（`_setup_dynamic_scene` 里有 `_setup_guild(base_loc)`） | `read_main_src()` | `_setup_dynamic_scene` 留在 Main，不用改 |
| `tools/p7_guild_exam_smoke.gd:101–276` | `load_scene("*_guild" / "*_exam")` 走真页面；直调 `main._on_guild_join(...)` ×4、`main._on_exam_sit(...)` ×1 | Main 保留同名转发（带 `await`），不用改 |
| `tools/qa_p7_screenshots.gd` / `qa_patrol_pack_screenshots.gd` | 按场景 id 开页、按钮文找「交会费入行」 | 页面、钮文不变，不用改 |

**为什么选 G2**：排在它前面的 6 簇都是高或中高风险（理由见上表和第五刀）。G2 簇内不存状态，只读 4 个 Main 的 UI 成员；3 个回调都 bind 到 Main 的同名方法，页面入口只有 `_setup_dynamic_scene` 一处。
check_symbols 的 51 处引用都经 read_main_src。要改的门禁有 2 道：verify_economy 的 3 处直读切片和 smoke 的 1 处切片，另外两份 MAIN_SPLITS 和 compile 清单要登记。

### 落地

- `scripts/ui/GuildExamPage.gd`（新增，197 行，`.uid` `uid://dohf12o33y82h` 同 commit）：10 支原样搬成 `static func`（guild_port_id / setup_guild / add_guild_join_slip / guild_join_block / on_guild_join / setup_exam / exam_slip / on_exam_copy / exam_sat_flag / on_exam_sit）。
  `guild_port_id` / `exam_sat_flag` 不碰 Main，不带 `main` 形参；其余的 Main 成员一律加 `main.` 前缀，簇内互调也经 `main.` 走转发（这样拼回后才是原文）。
  经 `main.` 取值推断不出类型，10 处 `:=` 改为与原推断相同的显式类型（VBoxContainer ×6、Label、Button、String ×2）。
- Main.gd **4831 → 4699（−132）**，func 数不变（233）：10 支都留同名同签名一行转发（`const _GUILD := preload(...)`）。`_on_guild_join` / `_on_exam_sit` 转发写 `await`，协程语义不变。
  留在 Main 的：`GUILD_*` / `EXAM_*` 常量、`play_transition`、`_collect_spreads`、工席小件。
- 门禁同步：两处 `MAIN_SPLITS`（check_symbols / smoke）都加 GuildExamPage.gd；`godot_compile_check` 的 SCRIPTS 加 1 行（126 → 127）；
  smoke 的誊录切片、verify_economy 的 3 处切片改去 GuildExamPage 里切（见上表）。**断言条件一条没改、没放宽。**
- 拼回原文：`read_main_src()` 拼回的 10 支和基线逐行比，只差上面 10 行 `:=`（末支后少一个空行，原因同第六刀：拆出件文件尾只有一个换行）。

### 下一刀候选（行数按基 59254f5）

1. **Y 市舶司 / 呈报 / 职衔**（119 / 7）风险低：Python 门禁只有 check_symbols 引用它，全经 read_main_src；探针只有 qa_discovery_probe 经 Main 调 `_on_report_discovery`。
2. **T 住处 / 寺观**（117 / 6）风险中低：smoke 有两处在 family src 里切 `_on_temple_look` / `_on_temple_rub`，verify_economy 的旅店门禁直读 Main 的 `_setup_residence`（第五刀加的），都要改切片位置。
3. **A / C / E / H / I / K** 风险高。先做「Main 家族源码」共用 helper 的门禁 lane（第五刀候选 3）。本刀又给 verify_economy 加了一处「直接读拆出件」的切片，和旅店那处（TavernPage）是同一种写法，应该一起收进这个 helper。
4. `MAIN_SPLITS` 已到第 7 件，两份清单靠对账同步，建议抽 `tools/main_splits.txt` 共读（ms2 待议 6 起一直挂着）。

---

## 拆出件清单改由本台账生成（lane cs13，2026-09-28）

不是一刀，只登记门禁变化（拍板清单 E-5；ms2 待议 6、上面第四 / 五 / 六 / 七刀的候选里一直挂着的那条）。

- `tools/main_splits.txt`：拆出件唯一清单，每件一行（拆出件 / lane / 拆出 commit / 原 Main 行范围 / 拆出函数）。`check_symbols` 与 `godot_smoke` 都只读第一列，两份脚本里的 `MAIN_SPLITS` 常量删掉了。
- `tools/gen_main_splits.py` 生成它：拆出件、顺序、lane 读本台账（开头「已拆（前三刀…）」那行 + 各刀节标题），所以**节标题的写法是契约**：``## 第N刀（lane X，日期）：… → `scripts/ui/X.gd` ``。拆出函数读 Main 的一行转发，commit 和行范围读 git（拆出 commit 父版的 Main.gd）；本台账表格里写了逐支行段的（第六、七刀共 15 支），生成时逐支对账。
- check_symbols「一之零」每轮重算、与清单逐字节比：手改清单、台账加了一刀没 `--write`、删了拆出件没更新，都判红。

---

## 第八刀（lane main8，2026-09-28）：市舶司 / 呈报 / 职衔 → `scripts/ui/MaritimeOfficePage.gd`

### 切面（基 `e8b8221`：Main.gd 4699 行，第七刀之后）

Y 是第七刀台账列的下一刀首选，连续一段：**1766–1886，121 行 / 7 支**（簇首 `# ── 市舶司 ──` 起，到 `_attention_desc` 末行；第七刀按基 59254f5 记 1763–1881、119 行）。

| 支 | 做什么 | 被簇外调（Main 内 / 他处） |
|---|---|---|
| `_setup_yamen(port_id)` | 题签 / 正文 → 市舶司小吏 → 货引工席（已在手 / 请领钮、违禁提示、蒲家留意）→ 呈报 → 泉州对峙征船名册 → 职衔与修埠 → 离开钮 | Main 1 处：`_setup_dynamic_scene` 的 `_yamen`（1100） |
| `_on_apply_permit()` | `GameState.apply_for_permit()` → 记事 → 重载本页 | 无（「请领」钮的目标） |
| `_setup_reporting()` | 未呈报发现逐件一张工席（赏钱 / 声名、「呈报」钮、地点 + 史实钩子 tooltip） | 无（簇内 `_setup_yamen` 调） |
| `_on_report_discovery(did)` | `GameState.report_discovery` → 呈报记事（升衔另记「案册改题」）→ 重载 | qa_discovery_probe 经 Main `call` 1 处（「呈报」钮的目标） |
| `_setup_title_and_invest(port_id)` | 职衔工席（抽解每百 / 赊贷上限 / 下一档还差几声名）+ 修埠工席（等级、短句、投钱钮） | 无（簇内调） |
| `_on_invest_port(port_id)` | `Economy.invest` → 记事 → 重载 | 无（「投钱」钮的目标） |
| `_attention_desc()` | 蒲家留意四档短句 | 无（簇内调；smoke 在 family src 里查四档字样） |

**跨切依赖**（全部经 `main.` 取，搬出件不存状态）：
- Main 成员：`current_scene_id` 3、`scene_title` / `body_text` / `choices_label` 各 1。
- Main 方法：`_slip_note` 8、`_slip_title` 5、`_slip_body` 4、`_slip_row` / `_slip_chip` / `log_msg` / `load_scene` 各 3，`_begin_benches` / `_end_benches` / `_add_npc_button` / `_add_leave_button` / `_duty_per_hundred` / `_setup_quanzhou_standoff` 各 1；
  簇内互调与 3 个信号目标（`_on_apply_permit` / `_on_report_discovery.bind` / `_on_invest_port.bind`）也经 `main.` 走 Main 的转发。
- autoload：`GameState` 13、`Economy` 3、`GameManager` 2、`UiTheme` 2。

**断言 / 探针引用点**（拆前逐个核过）：

| 引用点 | 怎么读 | 拆后 |
|---|---|---|
| check_symbols 九之七「report_discovery 只由 … 调」 | **扫 scripts/ 下真文件**，`func_bodies` 只认顶格 `func`，期望 `["Main.gd:_on_report_discovery"]` | 第七刀台账说 Y「全经 read_main_src」，这一条例外：不改就红（实测 `调用方漂移：[]`，拆出件里的 `static func` 扫不到）→ **改指新文件**：扫描前把 `static func` 记成 `func`，期望改成 `["MaritimeOfficePage.gd:on_report_discovery"]`，仍是整列表相等（顺带补上「拆出件里另有调用方也扫不到」的旧洞，只收紧） |
| check_symbols 九之七其余 5 条（挂呈报签、呈报签只在市舶司、呈报 chip 绑定、回调接线）、Lane AC 文案、Lane AA 修埠短句、「市舶司有职衔说明与修埠钮」、「职衔说明不写纲首」 | `func_bodies` / `_func_body` / `_locate_func` 读 `read_main_src()` | 转发就地换回拆出件函数体、去 `main.` 前缀 → **不用改**（拆出件进 `main_splits.txt` 即可） |
| smoke「蒲家留意四档不带括号」「抽解每百 %d」 | `_main_family_src()` 全文正 / 反向 `find` | 拆出件进 `main_splits.txt` 后字样仍在扫描范围内 → 不用改 |
| smoke `yard_node.call("_duty_per_hundred", …)` | 直调 Main | `_duty_per_hundred` 留 Main → 不用改 |
| qa_discovery_probe / qa_market_panel_probe | `load_scene("quanzhou_yamen")`、`call("_on_report_discovery", …)` | Main 保留同名转发 → 不用改 |
| verify_economy / simulate_run / verify_story_data | 不读这 7 支 | 无关 |

### 落地

- `scripts/ui/MaritimeOfficePage.gd`（新增，129 行，`.uid` 同 commit）：7 支原样搬成 `static func`（setup_yamen / on_apply_permit / setup_reporting / on_report_discovery / setup_title_and_invest / on_invest_port / attention_desc）。
  `attention_desc` 不碰 Main，不带 `main` 形参；其余 Main 成员一律加 `main.` 前缀。经 `main.` 取值推断不出类型，6 处 `:=` 改为与原推断相同的显式类型（VBoxContainer ×4、Button ×2）。
- Main.gd **4699 → 4612（−87）**，func 数不变：7 支都留同名同签名一行转发（`const _MARITIME := preload(...)`，均非协程）。
  留在 Main 的：`_setup_quanzhou_standoff`（终局 H 簇）、`_duty_per_hundred`（smoke 直调，不属页面簇）、工席小件、`_add_npc_button`、`_add_leave_button`。
- 门禁同步：按 cs13 的新流程，本节标题登记后跑 `gen_main_splits.py --write`，`tools/main_splits.txt` 多一行（check_symbols / smoke 都读它）；`godot_compile_check` 的 SCRIPTS 加 1 行（128 → 129）；check_symbols 调用方那一条改指新文件（上表）。**别的断言条件一条没改、没放宽。**
- 新加一条钉子（check_symbols 九之七，只收紧）：7 支在 Main 里须是一行转发到 `_MARITIME` 的同名 static func、拆出件里真有那支、Main 真 preload 了它。
  起因：只把某一支挪回 Main（整支写回、或拆出件留一份副本），「一之零」不红（件里还有别的转发），除 `_on_report_discovery` 外别的断言也不红。
  7 个函数名按 cs9 / cs11 口径登记进 `NAMED_FUNCS` 的 `scripts/Main.gd` 组（按拼回源码认；共 100 → 107 支），改名也红。
- 拼回原文：`read_main_src()` 拼回的 7 支和基线逐行比，只差 6 行 `:=`，外加 1 行注释「本地 main：泉州对峙期…」被拼回规则（裸 `main` → `self`）改成「本地 self」——在注释里，`code_only` 不看，断言不受影响。

### 下一刀候选（行数按基 e8b8221）

1. **T 住处 / 寺观**（117 / 6）风险中低：smoke 两处在 family src 里切 `_on_temple_look` / `_on_temple_rub`，verify_economy 直读 Main 的 `_setup_residence`，都要改切片位置（lane main9 已派）。
2. 做拆分前先 grep 门禁里「扫真文件 + `func_bodies`」的写法：`func_bodies` 不认 `static func`，拆走的函数在这类断言里会消失（本刀那一条是这样红的）。建议并进「Main 家族源码」共用 helper lane。
3. **A / C / E / H / I / K** 风险高，先做上面那个 helper lane。拆出件到第 8 件（`tools/main_splits.txt` 已由 cs13 落地）。

---

## 第九刀（lane main9，2026-09-28）：住处 / 寺观 → `scripts/ui/ResidencePage.gd`

基 `26bca91`（第八刀之后，Main.gd 4612 行，233 支 func；开工时基 `e8b8221`，第八刀落地后 rebase，T 簇行号整体 −87）。本刀是第七刀「下一刀候选」第 2 条 T 簇（第 1 条 Y 市舶司即第八刀），两刀不重叠。

**T 的切面**（2389–2505，117 行 / 6 支；夹在中间的 `TEMPLE_LOOK_DAYS` / `TEMPLE_RUB_DAYS` 2422–2423 是簇间常量，不搬）：

| 支 | 行段（含 `##`） | 做什么 | 被谁调（Main 内 / 他处） |
|---|---|---|---|
| `_setup_residence(port_id)` | 2389–2419 | 兴化转 `_setup_residence_chen`；别港「边记」卡（倾向 + ledger_notes）+「歇息」卡（歇 1 / 3 日，钮文 `nights * HOME_RATE`，bind `_on_rest(nights, port_id, HOME_RATE, "下处")`） | `_setup_dynamic_scene`（1115） |
| `_setup_temple(port_id)` | 2426–2463 | 近侧旧迹逐张工席：未勘「细看一日」、已入册 / 已呈案、已拓 / 「拓碑一日」；`japan_temple_network` 加一句 | `_setup_dynamic_scene`（1117） |
| `_temple_rub_note(name, hook)` | 2466–2470 | 拓记字样 `拓「名」　hook` / `拓「名」。` | 簇内 1 处；smoke 在 Main 实例上直调 |
| `_has_temple_rub(name)` | 2473–2478 | ledger_notes 里有 `拓「名」` 开头的记事（旧冒号也算） | 簇内 2 处；smoke 直调 |
| `_on_temple_look(did, name)` | 2481–2489 | advance_days → `record_discovery` → 记事 → 重载本页 | 「细看一日」钮 |
| `_on_temple_rub(did, name, hook)` | 2492–2505 | 未勘 / 空 id 拦下；advance_days → 未拓则 `add_ledger_note` → 记事 → 重载本页 | 「拓碑一日」钮 |

**跨切依赖**（全部经 `main.` 取，搬出件不存状态）：
- state：簇内没有状态成员；读 `current_scene_id` 3 次（重载本页）。
- ui：`scene_title` / `body_text` / `choices_label`；工席小件 `_slip_body` / `_slip_title` / `_slip_note` / `_slip_row` / `_slip_chip`、`_begin_benches` / `_end_benches` / `_add_leave_button`。
- msg：`log_msg` 5、`load_scene` 3。
- 留在 Main 的：`HOME_RATE`（verify_economy / check_symbols / smoke 直读 Main.gd）、`TEMPLE_LOOK_DAYS` / `TEMPLE_RUB_DAYS`、`_setup_residence_chen`（兴化玉湖陈宅，别的簇）、`_on_rest`（旅店 / 住处共用）。
- 回连的信号目标 3 个：`_on_rest.bind(...)`、`_on_temple_look.bind(did, name)`、`_on_temple_rub.bind(did, name, hook)`，都仍指向 Main。

**断言 / 探针引用点**（拆前逐个核过，行号按基 `26bca91`）：

| 引用点 | 怎么读 | 拆后 |
|---|---|---|
| `verify_economy.py:2057`（lane main5 住处歇息门禁：钮文日数 = 价的日数 = bind 日数，费率 HOME_RATE） | `_gd_fn(main_src, "_setup_residence")` **直读 Main.gd** | 切到一行转发，0 处钮 → 假红（实测）→ **改去 ResidencePage.gd 里切** `setup_residence`（去 `main.` 前缀，和旅店切 TavernPage 同一写法）；**不回落去切 Main**（旅店那行有 `or _gd_fn(main_src, "_setup_inn")` 回落，这里不加：挪回 Main 就该红）。条件原样 |
| `godot_smoke.gd:579 / 585`「寺观细看只记入册」「寺观拓碑只写入边记」 | 在 `_main_family_src()` 里切 `func _on_temple_look` / `_on_temple_rub` | 切到转发，假红（实测）→ **改去 ResidencePage.gd 里切** `static func on_temple_look(` / `on_temple_rub(`，去 `main.` 前缀；`on_temple_rub` 是拆出件末支，切到文件尾。条件原样 |
| `godot_smoke.gd:568 / 570`（四个动态页有定义、HOME_RATE / INN_RATE 都在） | family src 全文查 | Main 留同名转发、常量留 Main，不用改 |
| `godot_smoke.gd:597–603`（拓记字样、旧冒号仍算拓过） | 在 Main 实例上 `call("_temple_rub_note")` / `call("_has_temple_rub")` | 走转发，不用改 |
| `check_symbols.py:2619`（`拓「%s」　%s` 须在、`拓「%s」：` 不得在）、`:2930–2932`（函数定义）、`:2939`（HOME_RATE < INN_RATE）、`:3342 / 3354`（细看走 record_discovery、拓碑走 add_ledger_note）、`:3368`、`:3896–3911`（Lane AC 寺观题签 / 勘见记事） | 都经 `read_main_src()` | 拼回即原文 → **不用改**（登记 MAIN_SPLITS 即可；漏登记实测 13 条红） |

### 落地

- `scripts/ui/ResidencePage.gd`（新增，`.uid` `uid://cc0mjjqawj626` 同 commit）：6 支原样搬成 `static func`（setup_residence / setup_temple / temple_rub_note / has_temple_rub / on_temple_look / on_temple_rub）。
  `temple_rub_note` / `has_temple_rub` 不碰 Main，不带 `main` 形参；其余的 Main 成员一律加 `main.` 前缀，簇内互调也经 `main.` 走转发。
  7 处 `:=` 改为与原推断相同的显式类型（VBoxContainer ×4、HFlowContainer、Button ×2）。
- Main.gd **4612 → 4527（−85）**，func 数不变（233）：6 支都留同名同签名一行转发（`const _RESIDENCE := preload(...)`）。
- 门禁同步：本节标题登记拆出件，`python3 tools/gen_main_splits.py --write` 重生成 `tools/main_splits.txt`（lane cs13 起 check_symbols / smoke 都只读它）；`godot_compile_check` 的 SCRIPTS 加 1 行；smoke 两处切片、verify_economy 一处切片改去 ResidencePage 里切（见上表）。**断言条件一条没改、没放宽。**
- 拼回原文：`read_main_src()` 拼回的 6 支和基线逐行比，只差上面 7 行 `:=`。

### 下一刀候选

1. **A / C / E / H / I / K** 风险高（理由见第五 / 七刀）。先做「Main 家族源码」共用 helper 的门禁 lane：verify_economy 直读拆出件的写法已有旅店（TavernPage）、行会 / 贡院（GuildExamPage）、住处（ResidencePage）三处，smoke 也有贡院、寺观三处，应一起收进 helper。
