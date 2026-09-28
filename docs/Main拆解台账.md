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
- `tools/gen_main_splits.py` 生成它：拆出件、顺序、lane 读本台账（开头「已拆（前三刀…）」那行 + 各刀节标题），所以**节标题的写法是契约**：``## 第N刀（lane X，日期）：… → `scripts/ui/X.gd` ``。拆出函数读 Main 的一行转发，commit 和行范围读 git（拆出 commit 父版的 Main.gd）；各刀一节的函数表（「| `_fn(…)` |」行）与 Main 转发双向对账：表里列了的，现 Main 须仍一行转发到本件（lane cs18，挪回 Main / 改名 / 转去别件没改表即红）；那节有表的，现 Main 一行转发到本件的每支都须列在表里（lane cs22，有表就须列全）；表格行写了逐支行段的，再与拆出 commit 父版 Main.gd 重算的行段逐支对账。没有函数表的节（前三刀、第四 / 五刀）不查这两条。
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

---

## 第十刀（lane main10，2026-09-28）：船屋 → `scripts/ui/ShipyardPage.gd`

### 切面（基 `abb3f05`：Main.gd 4527 行，第九刀之后；开工时基 `26bca91`、4612 行，main9 落地后 rebase，C 簇整体 +4 行、内容逐字节同）

第七 / 八刀台账的下一刀候选里，Y、T 之后只剩 A / C / E / H / I / K。C 是其中唯一的「中高」（其余都是高：核心流程、互调或被多道门禁直读），
lane main10 的 brief 也点了「把 verify_economy / smoke 的直读改到拆出件」，C 被 verify_economy 直读 6 条，又是剩下几簇里风险最低的，所以本刀拆 C。
连续一段：**1883–2203，321 行 / 15 支**（簇首 `# ── 船屋 ──` 起，到 `_on_buy_supplies` 末行；第七刀按基 59254f5 记 1964–2281、318 行；按开工基 26bca91 是 1879–2199）。

| 支 | 行段（含 `##`） | 做什么 | 被谁调（Main 内 / 他处） |
|---|---|---|---|
| `_yard_port_name()` | 1886–1891 | `{港}_shipyard` 剥尾取港名，取不到回 `last_port` | 簇内 1 处（题签） |
| `_yard_success_transition(act)` | 1894–1901 | `await play_transition(drydock_title, 历法日期, load_scene 本页, drydock_seal)` | 簇内 4 处（换坞 / 修船 / 购入 / 升级） |
| `_setup_shipyard(port_id)` | 1904–2046 | 坞位一艘（升帆 / 升甲 / 添人 / 换上）→ 补给（水粮 30 / 100、修船、补齐人手）→ 蕃商赊贷（赊 500 / 2000、还）→ 坞外待售 → 离开钮 | `_setup_dynamic_scene`（1111） |
| `_yard_offer(catalog, sid)` | 2049–2056 | 按 id 在船表里找一行，非字典跳过 | 簇内 1 处 |
| `_on_berth_switch(ship_index)` | 2059–2066 | 夹回船队 → 同一艘不理 → 写 `berth_index` → 记事 → 换坞题签 | 「换上」钮 |
| `_on_repair_hull(cost)` | 2069–2081 | 连点闸 → 扣钱 → 上闸 → 修 → 题签 → 放闸；钱不够重载 | 「修船」钮 |
| `_on_hire_to_min(cost)` | 2084–2090 | 付钱雇齐各船最低人手 | 「补齐 N 人」钮 |
| `_on_borrow(amt)` | 2093–2098 | `GameState.borrow` → 记事 → 重载 | 「赊 N」钮 |
| `_on_repay(pay)` | 2101–2104 | `GameState.repay` → 记事 → 重载 | 「还 N」钮 |
| `_on_buy_ship(type_id, price)` | 2107–2119 | 连点闸 → 扣钱 → 上闸 → 添船 → 题签 → 放闸 | 「购入」钮 |
| `_on_dismiss_crew(role_id)` | 2122–2126 | `Crew.dismiss` → 记事 → 重载 | TavernPage「辞退」钮经 `main.` 接 |
| `_on_hire_candidate(crew_id)` | 2129–2132 | `Crew.hire` → 记事 → 重载 | TavernPage「雇入」钮经 `main.` 接 |
| `_on_hire_crew(ship_index, hire_n, hire_cost)` | 2135–2142 | 付钱给坞上这一艘添人 | 「添 N 人」钮 |
| `_on_upgrade(ship_index, kind, shown_cost)` | 2145–2188 | 连点闸 → 坏下标 / 满级拦 → 按当前等级重算价 → 升级 → 扣钱（扣不成回滚）→ 上闸 → 记事 → 题签 → 放闸 | 「升帆」「升甲」钮 |
| `_on_buy_supplies(n, wp, gp)` | 2191–2203 | 舱位够、钱够才补水粮各 n 份 | 「水粮各 N」钮 |

`_on_dismiss_crew` / `_on_hire_candidate` 是酒馆页的钮目标，函数一直写在船屋簇里（第四刀起的调查都把它们算进 C），本刀照原位一起搬，TavernPage 仍经 `main.` 调 Main 的同名转发。

**跨切依赖**（全部经 `main.` 取，搬出件不存状态）：
- Main 成员：`current_scene_id` 17、`_upgrade_busy` 9（读写，连点闸，唯一的簇状态；qa_yard_transition_probe 直读 Main 的它，留 Main）、`scene_title` / `body_text` / `choices_label` 各 1。
- Main 方法：`log_msg` 23、`load_scene` 15、`_slip_chip` 10、`_slip_note` 7、`_slip_body` / `_slip_row` / `_slip_title` 各 5、`_fit_rank` 4、`_begin_benches` / `_end_benches` / `_add_leave_button` / `_sail_fit_phrase` / `_armor_fit_phrase` / `play_transition` 各 1、常量 `_UI_TRANSITION` 2；
  簇内互调（`_yard_port_name` / `_yard_offer` / `_yard_success_transition` ×4）与 10 个信号目标（`_on_upgrade.bind` ×2、`_on_hire_crew` / `_on_berth_switch` / `_on_buy_supplies` / `_on_repair_hull` / `_on_hire_to_min` / `_on_borrow` / `_on_repay` / `_on_buy_ship` 的 `.bind`）也经 `main.` 走 Main 的转发。
- autoload：`Fleet` 47、`GameState` 30、`DrydockBerth` 4（class_name）、`GameManager` 3、`Economy` / `Crew` / `UiTheme` 各 2、`Calendar` 1。

**断言 / 探针引用点**（拆前逐个核过）：

| 引用点 | 怎么读 | 拆后 |
|---|---|---|
| verify_economy 二之 2b / 2c（升级回调 4 条、修船 / 购船同闸 2 条） | **直读 Main.gd**（`_main_up`），`_locate_func` 切 `_on_upgrade` / `_on_repair_hull` / `_on_buy_ship` | 会切到一行转发，6 条里 5 条假红（实测）→ **改去 ShipyardPage.gd 里切** `on_upgrade` / `on_repair_hull` / `on_buy_ship`，切前去 `main.` 前缀；条件原样 |
| verify_economy 哗变「散钱 > 事后补 N 人」 | **直读 Main.gd** 全文正则 `below_min \* (\d+)` | 字样随 `_setup_shipyard` 搬走，补人单价取成 0、假红（实测）→ **改去 ShipyardPage 里按名取 `setup_shipyard` 的函数体再找**（原先在整份 Main 泛搜，现在只认这一支，只收紧；取不到进「十一、按函数名取函数体」判红） |
| verify_economy 其余直读 Main.gd 的（牙行 `_affordable_qty` / `_setup_market` …、委办字样、`INN_RATE` / `GUILD_*` / `EXAM_*` 常量、住处 `_setup_residence` / `_on_rest`） | 直读 Main.gd | 都不在 C 簇里（逐条核过），不用改 |
| check_symbols「船屋改成坞位一艘」「船屋成功题签」、Lane AB 雇请文案（`_on_hire_crew` / `_on_hire_to_min`）、「Main._on_upgrade 已定义」 | `_func_body` / 正则读 `read_main_src()` | 转发就地换回拆出件函数体、去 `main.` 前缀 → **不用改**（拆出件进 `main_splits.txt` 即可） |
| smoke「船屋加成写成成数…」（`月息每百 %d`、`添 %d 人`、`水手 %d 至 %d`、`水粮各 %d　付 %d` 正向；`月息 %d%%`、`+%d` 反向） | `_main_family_src()` 全文 `find` | 拆出件进 `main_splits.txt` 后字样仍在扫描范围内 → 不用改（漏登记则正向红） |
| smoke `yard_node.call("_sail_fit_phrase" / "_armor_fit_phrase" / "_duty_per_hundred", …)`、`func _fit_rank` | 直调 / family src | 这几支不属本簇、留 Main → 不用改 |
| qa_drydock_probe / qa_yard_transition_probe / qa_money_notices_probe | `load_scene("quanzhou_shipyard")`、按钮文找钮、`_main.get("_upgrade_busy")` | 页面、钮文不变，闸留 Main → 不用改 |
| simulate_run / verify_story_data / check_assets / simulate_endgame | 不读这 15 支 | 无关 |

### 落地

- `scripts/ui/ShipyardPage.gd`（新增，332 行，`.uid` 同 commit）：15 支原样搬成 `static func`（yard_port_name / yard_success_transition / setup_shipyard / yard_offer / on_berth_switch / on_repair_hull / on_hire_to_min / on_borrow / on_repay / on_buy_ship / on_dismiss_crew / on_hire_candidate / on_hire_crew / on_upgrade / on_buy_supplies）。
  `yard_offer` 不碰 Main，不带 `main` 形参；其余 Main 成员一律加 `main.` 前缀。经 `main.` 取值推断不出类型，19 处 `:=` 改为与原推断相同的显式类型（VBoxContainer ×5、HFlowContainer ×5、Button ×5、String ×3、Dictionary）。
- Main.gd **4527 → 4275（−252）**（开工基 26bca91 上是 4612 → 4360），func 数不变：15 支都留同名同签名一行转发（`const _YARD := preload(...)`），五支协程（`_yard_success_transition` / `_on_berth_switch` / `_on_repair_hull` / `_on_buy_ship` / `_on_upgrade`）转发写 `await`，协程语义不变。
  留在 Main 的：`_upgrade_busy`、`_fit_rank` / `_sail_fit_phrase` / `_armor_fit_phrase`（smoke 直调、LedgerPage 也用）、`play_transition`、`_UI_TRANSITION`、工席小件、`_add_leave_button`。
- 门禁同步：本节标题登记后跑 `gen_main_splits.py --write`（`tools/main_splits.txt` 多一行）；`godot_compile_check` 的 SCRIPTS 加 1 行；verify_economy 两处直读改切拆出件（上表）。**断言条件一条没改、没放宽。**
- 新加一条钉子（check_symbols 九之七，只收紧，口径照第八刀那条）：15 支在 Main 里须是一行转发到 `_YARD` 的同名 static func、拆出件里真有那支、Main 真 preload 了它。
- 拼回原文：`read_main_src()` 拼回的 15 支和基线逐行比，只差上面 19 行 `:=`。

### 下一刀候选（行数按基 abb3f05）

1. 剩下的 **A 牙行 / E 岸带 / H 守城·终局 / I 调查页 / K 场景分发** 全是高风险。A 被 verify_economy 直读最多（`_affordable_qty` / `_setup_market` / `_add_contract_panel` / `_make_market_row` / 两支 tip，另有 `_purse_ui` 这类按锚文切片段），拆它之前先把 verify_economy 的「直读 Main」统一接到 check_symbols 的 `read_main_src()` 拼回（cs14 待议 2），不然每拆一簇都要手改一批切片。
2. 第八刀和本刀各手写了一条「真身钉在拆出件」的钉子（main8 待议 3）。两条同形，可以改由 `main_splits.txt` 的「拆出函数」列反查、对全部拆出件生效，但要先定口径（不能靠 `--write` 自愈）。

---

## 第十一刀（lane main11，2026-09-28）：标题页 / 开场 → `scripts/ui/TitlePage.gd`

### 调查（基 `c9d0e14`：Main.gd 4275 行，233 支 func，第十刀之后；开工基 `08ca2a4` 上 4527 行，第十刀船屋 C 由 lane main10 同时在做、先落地，本刀不碰，rebase 后按本基重算）

口径：把 Main 里**还没拆**的函数（一行转发不算）按源码位置 / 页面归成 16 簇（开工基上是 17 簇，C 船屋 15 支 1.6 排第 6，归 main10 第十刀），逐簇算
「引用数 = 被簇外调（Main 内簇外非注释行按名出现次数，含 `call_deferred("start_game")` 这类字符串名）+ 他处引用（scripts / tools / scenes 其余文件去掉注释行后按名出现次数，含已拆出件经 `main.` 调）」，
再除以支数，按比值升序排。「直读 Main.gd 的门禁」只列不经 `read_main_src()` / `_main_family_src()`、会切到一行转发的读法；「写 Main 成员」是函数体里对 Main 顶层 var 的赋值。

| # | 簇（基 c9d0e14 行段） | 支 / 行 | 簇外调 | 他处（代码） | 引用 / 支 | 直读 Main.gd 的门禁 | 写 Main 成员 | 风险 |
|---|---|---|---|---|---|---|---|---|
| 1 | P 开局 / 开场（`_on_monthly_notice` … `_on_rewatch_opening`，615–652） | 5 / 30 | 3 | 0 | **0.6** | 无 | `_arrival_banner` | 低（start_game 是开局入口，见下） |
| 2 | R 玉湖陈宅（`_setup_residence_chen`，1960–2006） | 1 / 47 | 0 | 1（ResidencePage） | 1.0 | 无 | 无 | 低，但只 1 支 |
| 3 | A 牙行（`_setup_market` … `_on_sell`，1133–1778） | 15 / 618 | 1 | 20 | 1.4 | verify_economy 12、qa_contract_stock 3、qa_money_notices 1 | 4 个（`_market_ship` / `_market_hold` / `broker_hand` / `_contract_detail_open`） | 高 |
| 4 | Q 标题页（`_setup_title_mode` / `_on_start_game_pressed`，2296–2354） | 2 / 57 | 1 | 2（check_symbols，经 read_main_src） | 1.5 | 无 | `title_button_connected` | 低 |
| 5 | H 守城 / 终局（`_check_absent_from_xinghua` … `_special_cards`，3349–4272） | 27 / 833 | 14 | 29 | 1.6 | verify_story_data 4、check_assets 1、verify_economy 1、smoke 1 | `_shore_mode` / `_shore_facilities` | 高 |
| 6 | D 调试（`_debug_jump_port` / `_debug_preview_ending`，3287–3324） | 2 / 36 | 2 | 2 | 2.0 | 无 | 无 | 低，但只是 F11 / F12 点验钩子 |
| 7 | E 岸带（`_setup_port_mode` … `_on_set_sail`，2357–2862） | 19 / 469 | 15 | 27 | 2.2 | smoke 1、ShotTour 1 | 4 个 | 高 |
| 8 | O 浮页（`_open_codex` … `_close_vision_stage`，655–750） | 8 / 82 | 6 | 14 | 2.5 | qa_wire_vision 2、qa_letterbox_copy 1（直读 Main.gd 查 `_open_vision_stage` 字样） | 4 个浮页句柄 | 中（两个 lambda 回写句柄） |
| 9 | F 船况措辞（`_fit_rank` … `_duty_per_hundred`，789–833） | 5 / 37 | 0 | 19 | 3.8 | smoke 8（Main 实例直调） | 无 | 中低（船屋 / 船籍簿 / 市舶司三个拆出件共用） |
| 10 | M 店中杂项（`_monsoon_forecast` … `_gather_price_intel`，2171–2257） | 5 / 79 | 0 | 19 | 3.8 | verify_economy 5、smoke 1 | 无 | 中 |
| 11 | N 内景题（`_interior_title` / `_interior_lead`，836–871） | 2 / 34 | 2 | 6 | 4.0 | smoke 2 | 无 | 中低 |
| 12 | I 调查页 / 选项 / 效果（2993–3284） | 14 / 266 | 14 | 55 | 4.9 | verify_story_data 6、smoke 1 | 无 | 高（`_gui_input` / `_unhandled_input` 虚函数） |
| 13 | B 壳 / 装裱（`_ready` … `_fit_dialogue`，227–612） | 14 / 312 | 10 | 65 | 5.4 | ShotTour 1 | 6 个 | 高（`_ready`） |
| 14 | X 入港 / 设施分发（`_on_enter_port` / `_select_market_ship` / `_cn_chapter` / `_on_facility_pressed`，2891–2990） | 4 / 70 | 5 | 20 | 6.2 | verify_story_data 1、smoke 2、ShotTour 1 | 2 个 | 高（章节推进入口） |
| 15 | W 工席台（`_begin_benches` … `_uncenter_benches`，1815–1848） | 4 / 28 | 1 | 34 | 8.8 | smoke 5 | `_slip_host` | 中（9 个拆出件都在用） |
| 16 | K 场景加载 / 分发（`load_scene` … `_setup_dynamic_scene`，878–1128） | 10 / 223 | 54 | 156 | 21.0 | 多处 | 4 个 | 高（所有页面都经过） |

（另有一支 `_add_save_button`（3340–3345）全仓 0 调用方，是死代码，不归簇、本刀不动。）

**为什么选「标题页 / 开场」**：按比值，P（0.6）和 Q（1.5）一个排第 1、一个排第 4。两簇其实是同一张页，只是在源码里分成两段：
Q 的 `_setup_title_mode` 排卷首标题页和四方沙盘（type=title 各页），`_on_start_game_pressed` 是「开卷 / 翻页」钮的回调；
P 里的 `_play_opening` / `_on_opening_finished` / `_on_rewatch_opening` 是标题页上「重看开场」钮和开场演完后重演标题演出的那一套，和 Q 共用 `title_mode`、TitleStage、`_rewatch_button`。
P 另外两支 `start_game`（开局入口，`_ready` 里 `call_deferred("start_game")`、海图回港也走它）和 `_on_monthly_notice`（月报信号）是开局流程，不属页面，**不搬**。
合起来 5 支：簇外调 3（`start_game` → `_play_opening`、`_dress_title` 接「重看开场」钮、`_load_scene_inner` → `_setup_title_mode`），他处代码引用 2（check_symbols 两处，都经 read_main_src），**引用 / 支 = 1.0**。
没有门禁直读 Main.gd 切这 5 支，verify_economy / smoke / verify_story_data 都不读它们；唯一写的 Main 成员是 `title_button_connected`；不含虚函数；没有 lambda。
比值更低或相近的其余几簇：A、H 高风险（理由见第五 / 七刀）；R 只 1 支，是住处的兴化分支，更适合以后并进 ResidencePage；D 只是两支调试钩子。

**切面**（两段；`start_game` / `_on_monthly_notice` 夹在第一段前面，留 Main）：

| 支 | 行段（含 `##`） | 做什么 | 被谁调（Main 内 / 他处） |
|---|---|---|---|
| `_play_opening(from_black := false)` | 636–639 | `_CS_PLAYER.play` 起播开场；有节点就把 `finished` 一次性接到 `_on_opening_finished` | `start_game`（新开一局）、`_on_rewatch_opening` |
| `_on_opening_finished()` | 642–648 | 开场演完：还停在标题页就让 TitleStage `replay` | 开场过场 `finished` 信号 |
| `_on_rewatch_opening()` | 651–652 | `_play_opening(false)` | 「重看开场」钮（`_dress_title` 接线） |
| `_setup_title_mode(scene_data)` | 2296–2338 | 切到标题模式，题名 / 副题换行居中，断开旧连接后把「开卷」钮 bind 到 `_on_start_game_pressed(next)`，占位钮文改「开卷 / 翻页」，三副钮显隐，`_TITLE_STAGE.present` | `_load_scene_inner`（type=title） |
| `_on_start_game_pressed(next_scene)` | 2341–2354 | 从卷首 / 入酒棚走序章题签 `play_transition`（全黑时 `load_scene`），沙盘中间翻页直接 `load_scene` | 「开卷 / 翻页」钮（协程） |

**跨切依赖**（全部经 `main.` 取，搬出件不存状态）：
- state：写 `title_button_connected` 1 处（读 1 处）；读 `current_scene_id` 2。
- ui：`start_button` 7、`main_title` 5、`title_mode` / `sub_title` / `_rewatch_button` 各 4、`_resume_button` / `_codex_title_button` 各 3，`port_mode` / `npc_mode` / `investigation_mode` 各 1；`_show_strip` / `_close_ledger` / `_unescape_scene_text` 各 1。
- msg：`load_scene` 3（1 直调 + 2 个 bind）、`play_transition` 2。
- 常量（preload）：`_CINE` 4、`_CS_PLAYER` / `_UI_TRANSITION` 各 2、`_TITLE_STAGE` 1，都留 Main。
- autoload：GameManager 3、Calendar 2、SaveLoad 2、UiTheme 1。
- 回连的信号目标 3 个：`_on_start_game_pressed.bind(next_scene)`、`_on_opening_finished`（CONNECT_ONE_SHOT）、`_on_rewatch_opening`（在 `_dress_title` 里接），都仍指向 Main。

**断言 / 探针引用点**（拆前逐个核过，行号按基 `c9d0e14`）：

| 引用点 | 怎么读 | 拆后 |
|---|---|---|
| `check_symbols.py:3270`（序章开卷 / 入酒棚走 `play_transition` + 两个题签助手 + `begins_with("cg_narrate")`） | `func_bodies(read_main_src())` 取 `_on_start_game_pressed` | 拼回即原文 → **不用改**（登记 main_splits 即可；漏登记实测红，cs17 另报「只取到一行转发」） |
| `check_symbols.py:3692`（标题模式读 cg_title / cg_sub、`\A` 经 `_unescape_scene_text` 换行） | 同上，取 `_setup_title_mode` | 同上 |
| `qa_title_probe.gd`（卷首 / 序章题签截图 5 张；`--contract` 验非渲染断言）、ShotTour title / title_anim / page_cg_* 站点、`qa_companion_preview_screenshots.gd` | 走真页面（`load_scene("cg_title")`、按「开卷」「重看开场」钮、找 TitleStage） | 页面、钮文、节点名都不变，不用改 |
| `p7_guild_exam_smoke.gd`、`legacy/p7_smoke.gd`、`godot_story_check.gd`、ShotTour 里提到 `start_game` 的几处 | 注释 / `call_deferred("start_game")` 的等待 | `start_game` 留 Main，不用改 |
| verify_economy / smoke / verify_story_data / check_assets / simulate_* | 不读这 5 支 | 无关 |

### 落地

- `scripts/ui/TitlePage.gd`（新增，`.uid` 同 commit）：5 支原样搬成 `static func`（play_opening / on_opening_finished / on_rewatch_opening / setup_title_mode / on_start_game_pressed），都带 `main` 形参，Main 成员一律加 `main.` 前缀，簇内互调、信号目标也经 `main.` 走 Main 的转发；
  `_CS_PLAYER.play(self, …)` 的 `self` 写成 `main`（拼回规则把裸 `main` 换回 `self`）。经 `main.` 取值推断不出类型，3 处 `:=` 改为与原推断相同的显式类型（Node、bool ×2）。
- Main.gd **4275 → 4220（−55）**（开工基 `08ca2a4` 上是 4527 → 4472），func 数不变（233）：5 支都留同名同签名一行转发（`const _TITLE := preload(...)`）；`_on_start_game_pressed` 转发写 `await`，协程语义不变。
- 门禁同步：本节标题登记拆出件，`python3 tools/gen_main_splits.py --write` 重生成 `tools/main_splits.txt`；`godot_compile_check` 的 SCRIPTS 加 1 行。
  verify_economy / smoke 没有读这 5 支的切片，**读取口径不用改**；check_symbols 两处源码断言经 read_main_src 拼回，条件一条没改、没放宽。
  verify_story_data 的 L1B 人物原稿读取入口清单加 `scripts/ui/TitlePage.gd`（`{"api"}`：标题页「人物志」钮显隐的 `all_characters()` 随 `_setup_title_mode` 搬过来；不登记实测红「不在 L1B 读取入口清单却读人物数据」）。清单按类别与实际读取一字不差比，Main.gd 岸带仍读 `all_characters()`，它那条照留、只改说明。
- 新加一条钉子（check_symbols 九之七，只收紧，口径同第八刀市舶司页）：5 支在 Main 里须是一行转发到 `_TITLE` 的同名 static func、拆出件里真有那支、Main 真 preload 了它；5 个名字登记进 `NAMED_FUNCS` 的 `scripts/Main.gd` 组。
  起因：只把某一支挪回 Main 再跑 `gen_main_splits --write`，清单跟着改、「一之零」变绿，两处源码断言拼回的还是同一段原文，也绿（lane cs18 在收的那类静默跳过）。
- 拼回原文：`read_main_src()` 拼回的 5 支和基线逐行比，只差上面 3 行 `:=`。

### 下一刀候选（行数按基 c9d0e14）

1. **R 玉湖陈宅**（1 / 47）并进 ResidencePage：只 ResidencePage 经 `main.` 调它，没有门禁直读；住处这一页就齐了。
2. **D 调试**（2 / 36）：check_symbols 一处经 read_main_src 读 `_debug_jump_port`，F11 / F12 键位判断留在 `_unhandled_input`。顺带定一下死代码 `_add_save_button` 删不删（要拍板，不归拆刀）。
3. **O 浮页**（8 / 82）：两个 lambda 回写 Main 的浮页句柄，qa_wire_vision / qa_letterbox_copy 直读 Main.gd 查 `_open_vision_stage` 字样（转发留名，不会红）；中风险。
4. **A / E / H / I / K / B / X** 风险高，仍先做「Main 家族源码」共用 helper 的门禁 lane（第五 / 七 / 九刀候选）。

---

## 第十二刀（lane main12，2026-09-28）：调试钩子 → `scripts/ui/DebugHooks.gd`

### 调查（基 `a4ed909`：Main.gd 4211 行，232 支 func；即 `ff82b17` 删掉死代码 `_add_save_button` 之后，见下「死代码」）

口径同第十一刀（lane main11 的算法原样复用：在基 `c9d0e14` 上重跑，16 簇的比值与第十一刀表逐格相同）：Main 里**还没拆**的函数（一行转发不算）按源码位置 / 页面归簇，
「引用数 = 被簇外调（Main 内簇外非注释行按名出现次数）+ 他处引用（scripts / tools / scenes 其余文件去掉注释行后按名出现次数，含已拆出件经 `main.` 调）」，除以支数，按比值升序。
第十一刀拆走 P 里的开场三支与 Q 整簇，剩 15 簇；P 只剩 `start_game` / `_on_monthly_notice` 两支。「直读 Main.gd 的门禁」只列不经 `read_main_src()` / `_main_family_src()`、拆了会切到一行转发的读法。

| # | 簇（基 a4ed909 行段） | 支 / 行 | 簇外调 | 他处（代码） | 引用 / 支 | 直读 Main.gd 的门禁 | 写 Main 成员 | 风险 |
|---|---|---|---|---|---|---|---|---|
| 1 | P 开局（`_on_monthly_notice` / `start_game`，619–637） | 2 / 17 | 2 | 0 | **1.0** | 无 | `_arrival_banner` | 不拆：开局入口（`_ready` 里 `call_deferred("start_game")`、海图回港也走它）与月报信号，不属页面 |
| 2 | R 玉湖陈宅（`_setup_residence_chen`，1958–2004） | 1 / 47 | 0 | 1（ResidencePage） | **1.0** | **simulate_endgame 1**（`:77` 在 Main.gd 全文正则 `hometown_tendency \+= (\d+)\n\t\t\tGameManager\.advance_days`，「玉湖陈宅跑腿是 1268 前的乡土写入点」；第十一刀记「无」，漏了这处） | 无（两个 lambda 回调） | 低中：要改一道门禁；自然归宿是并进 ResidencePage，但 main_splits 一件一刀（见下） |
| 3 | A 牙行（`_setup_market` … `_on_sell`，1131–1776） | 15 / 618 | 1 | 20 | 1.4 | verify_economy 12、qa_contract_stock 3、qa_money_notices 1 | 4 个 | 高 |
| 4 | H 守城 / 终局（`_check_absent_from_xinghua` … `_special_cards`，3285–4208） | 27 / 833 | 14 | 29 | 1.6 | verify_story_data 4、check_assets 1、verify_economy 1、smoke 1 | `_shore_mode` / `_shore_facilities` | 高 |
| 5 | **D 调试（`_debug_jump_port` / `_debug_preview_ending`，3232–3269）** | **2 / 36** | 2（`_unhandled_input` 的 F11 / F12） | 2（check_symbols，经 read_main_src） | **2.0** | **无** | **无** | **低 → 本刀** |
| 6 | E 岸带（`_setup_port_mode` … `_on_set_sail`，2302–2807） | 19 / 469 | 15 | 27 | 2.2 | smoke 1、ShotTour 1 | 4 个 | 高 |
| 7 | O 浮页（`_open_codex` … `_close_vision_stage`，653–748） | 8 / 82 | 6 | 14 | 2.5 | qa_wire_vision 2、qa_letterbox_copy 1 | 4 个浮页句柄 | 中（两个 lambda 回写句柄） |
| 8 | F 船况措辞（`_fit_rank` … `_duty_per_hundred`，787–831） | 5 / 37 | 0 | 19 | 3.8 | smoke 8（Main 实例直调） | 无 | 中低 |
| 9 | M 店中杂项（`_monsoon_forecast` … `_gather_price_intel`，2169–2255） | 5 / 79 | 0 | 19 | 3.8 | verify_economy 5、smoke 1 | 无 | 中 |
| 10 | N 内景题（`_interior_title` / `_interior_lead`，834–869） | 2 / 34 | 2 | 6 | 4.0 | smoke 2 | 无 | 中低 |
| 11 | I 调查页 / 选项 / 效果（2938–3229） | 14 / 266 | 14 | 55 | 4.9 | verify_story_data 6、smoke 1 | 无 | 高（`_gui_input` / `_unhandled_input` 虚函数） |
| 12 | B 壳 / 装裱（`_ready` … `_fit_dialogue`，231–616） | 14 / 312 | 10 | 65 | 5.4 | ShotTour 1 | 6 个 | 高（`_ready`） |
| 13 | X 入港 / 设施分发（2836–2935 里 4 支） | 4 / 70 | 5 | 20 | 6.2 | verify_story_data 1、smoke 2、ShotTour 1 | 2 个 | 高（章节推进入口） |
| 14 | W 工席台（`_begin_benches` … `_uncenter_benches`，1813–1846） | 4 / 28 | 1 | 34 | 8.8 | smoke 5 | `_slip_host` | 中（9 个拆出件都在用） |
| 15 | K 场景加载 / 分发（`load_scene` … `_setup_dynamic_scene`，876–1126） | 10 / 223 | 50 | 160 | 21.0 | 多处 | 4 个 | 高（所有页面都经过） |

（开工基 `ff82b17` 上同一张表只多一行：`_add_save_button` 1 支 0 引用，比值 0.0；其余各簇比值相同，H / 之后的行段多 9 行。）

**为什么选 D，不选 R**：比值上 R（1.0）排在 D（2.0）前面，P 不属页面不拆。R 不做本刀，有三条原因：
1. 它的自然归宿是并进第九刀的 `ResidencePage.gd`（住处这一页，`setup_residence` 在兴化就转它）。可 `gen_main_splits.py` 是一件一刀：同一个拆出件在台账里登记两次即判红；commit / 原 Main 行范围两列按「新增这个文件的 commit」取。往已有拆出件里追加一刀，现行清单表达不了。硬写的话，行范围会记成 `ebd28e7^` 里陈宅的旧位置，名不副实；不登记节标题又没有 cs18「台账函数表列了的须仍转发」这道判据，挪回 Main 再 `--write` 会全绿。单开一个一支的拆出件则是把一页拆成两份。要做 R，先给 gen_main_splits 加「追加刀」的口径（记待议）。
2. 第十一刀记它「没有门禁直读」，实测不对：simulate_endgame `:77` 在整份 Main.gd 里按三层缩进正则找陈宅跑腿（上表）。拆了要改这道门禁的读取口径。
3. 陈宅两个钮回调是 lambda（捕获 `log_msg` / `load_scene` / `current_scene_id`），搬成 static func 后要改成捕获 `main`。

D 两支连续一段，不含 lambda，不写 Main 成员，不碰引擎虚函数：F11 / F12 键位判断在 `_unhandled_input` 里，留在 Main，照旧调 Main 的同名方法。
没有门禁直读 Main.gd 切这两支。check_symbols 的 F11 断言经 `read_main_src()` 读，verify_economy / smoke / verify_story_data / simulate_* / 探针都不读它们。风险最低，又是第十一刀「下一刀候选」第 2 条。

### 死代码 `_add_save_button`（第十一刀待议 3）：删

- **来历**：只查得到根提交 `908b46f`（2026-09-26，仓库历史从这笔压平的导入开始，更早的提交不在本仓）。那一版里它就已经 0 调用方（`git show 908b46f:scripts/Main.gd` 里只有定义一处）。
  它排在 Main.gd 那条横线 `# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══` 底下，是 `docs/云端优先合并台账_2026-09-25.md` 规则⑤「本地 main 冲突让位云端、纯新增保留」补回来的本地 main 旧件。
  它做的事是往旧右栏 `right_facilities` 塞一颗「航海日志」钮。
- **现状**：云端港页不用左右栏，`_clear_shore` / `_refresh_shore` 每次都把 `left_facilities` / `right_facilities` 清空并设 `visible = false`。
  航海日志早由岸带动作行 `_shore_action("航海日志", …, _show_save_dialog)` 接上（基 `a4ed909` Main.gd `:2496`），标题页「续卷」也另接了 `_show_save_dialog.bind(true)`。
  `git log -G'_add_save_button'` 只有三笔：908b46f（定义）、7c00b06（第六刀台账记它是 `_show_save_dialog` 的调用方之一，那是按函数名数的，它自己从没被调过）、e2bf505（第十一刀台账记死代码）。
- **处置：删**。接线只会在一直隐藏的栏里多一颗重复的钮；留注释没有读者。
  `9631b00` 删 9 行（函数 6 行 + 其后多余空行），func 233 → 232，Main.gd 4220 → 4211。`a4ed909` 让拍板清单跟号（DRIFT 23 → 0）。
  全仓 `grep -rn _add_save_button --include=*.gd --include=*.py` 删后 0 处。门禁全绿的证据见 lane main12 brief 的 Verify §2：`a4ed909` 上 23 道 rc=0，check_symbols ✓ 431 = 431 且逐行输出与 `ff82b17` 相同，smoke 160 = 160，verify_economy 320 = 320。

### 切面

| 支 | 行段（含 `##`） | 做什么 | 被谁调（Main 内 / 他处） |
|---|---|---|---|
| `_debug_jump_port()` | 3232–3250 | 设施页先剥 `FACILITY_SUFFIXES` 回基港；泉州 → 福州 → 兴化 → 泉州轮着跳（写 `last_port` 再 `load_scene`） | `_unhandled_input` F11（调试构建） |
| `_debug_preview_ending()` | 3253–3269 | 沙盒凑齐第四章、八万钱（`peak_money` 同抬）、十三港、没有结局线旗标就补 `chen_line_open`，落在占城，再 `try_resolve_ending`：了结就开升章册页，没了结记一句 | `_unhandled_input` F12（调试构建） |

**跨切依赖**（全部经 `main.` 取，搬出件不存状态）：
- state：读 `current_scene_id` 1；不写 Main 成员。
- 常量：`FACILITY_SUFFIXES` 1，留在 Main（`_load_scene_inner` 也用）。
- msg：`load_scene` 3、`_show_chapter_dialog` 1（转 ChapterSheet）、`log_msg` 1、`update_status_panel` 1。
- autoload：GameState 17（`last_port` 4、`has_flag` 3、`money` / `peak_money` 各 2、`chapter` / `add_money` / `visit_port` / `set_flag` / `try_resolve_ending` 各 1）。
- 信号目标：无。两支只由 `_unhandled_input` 直调。

**断言 / 探针引用点**（拆前逐个核过，行号按基 `a4ed909`）：

| 引用点 | 怎么读 | 拆后 |
|---|---|---|
| `check_symbols.py:2008`「Main F11 可跳到泉州港」（`_has_func(main_src, "_debug_jump_port") and "KEY_F11" in main_src`）、`:2010`「F11 点验链含福州通用港与兴化回访」（`_locate_func(main_src, "_debug_jump_port")` 里要有 `fuzhou` / `xinghua`） | `main_src = read_main_src()`（`:1953`） | 拼回即原文 → **不用改**。登记 main_splits 即可；实测漏登记红 3 条：「F11 不能跳到福州/兴化」、cs17「取函数体 `_debug_jump_port` 只取到一行转发」，外加「一之零」3 条 |
| `KEY_F11` / `KEY_F12` 键位判断（Main `_unhandled_input` `:3200–3206`） | — | 留在 Main，不用改 |
| verify_economy / smoke / verify_story_data / check_assets / simulate_run / simulate_endgame / 各 qa 探针 | 不读这两支（全仓 grep 只有 check_symbols 两处） | 无关 |
| check_symbols「X 只由 … 调」一类扫真文件的调用方断言（第八刀那类 `func_bodies` 不认 `static func` 的坑） | 两支调的 `try_resolve_ending` / `visit_port` / `set_flag` / `add_money` 都没有这类断言（实测拆后未同步时只红上面那几条） | 无关 |

### 落地

- `scripts/ui/DebugHooks.gd`（新增，`.uid` 同 commit）：2 支原样搬成 `static func`（debug_jump_port / debug_preview_ending），都带 `main` 形参，Main 成员一律加 `main.` 前缀。
  经 `main.` 取值推断不出类型，1 处 `:=` 改为与原推断相同的显式类型（`var here: String = main.current_scene_id`）；`var res := GameState.try_resolve_ending()` 经 autoload 取，照留。
- Main.gd **4211 → 4185（−26）**（相对开工基 `ff82b17` 的 4220 共 −35），func 数不变（232）：2 支都留同名同签名一行转发（`const _DEBUG := preload(...)`，都不是协程）。
- 门禁同步：本节标题登记拆出件，跑 `python3 tools/gen_main_splits.py --write` 重生成 `tools/main_splits.txt`；`godot_compile_check` 的 SCRIPTS 加 1 行。
  verify_economy / smoke / verify_story_data 没有读这两支的切片，**读取口径不用改**；check_symbols 两处源码断言经 read_main_src 拼回，条件一条没改、没放宽。
- 新加一条钉子（check_symbols 九之七，只收紧，口径同第十一刀标题页那条）：2 支在 Main 里须是一行转发到 `_DEBUG` 的同名 static func，拆出件里真有那支，Main 真 preload 了它；2 个名字登记进 `NAMED_FUNCS` 的 `scripts/Main.gd` 组。
  cs18 之后「挪回 + `--write`」已由 gen_main_splits 判红，钉子独有的是 preload 常量名与「拆出件真有那支」两项（第十一刀待议 1 建议抽成通用判据，本刀照惯例先手写）。
- 拼回原文：`read_main_src()` 拼回的 2 支和基线逐行比，只差上面 1 行 `:=`。

### 下一刀候选（行数按基 a4ed909）

1. **R 玉湖陈宅**（1 / 47）并进 ResidencePage：先给 `gen_main_splits.py` 定「往已有拆出件追加一刀」的口径（台账节标题怎么写、commit / 行范围列记哪一刀），再改 simulate_endgame `:77` 的读取口径（改读 ResidencePage、去 `main.` 前缀，不回落切 Main），两个 lambda 改捕获 `main`。
2. **O 浮页**（8 / 82）：两个 lambda 回写 Main 的浮页句柄；qa_wire_vision / qa_letterbox_copy 直读 Main.gd 查 `_open_vision_stage` 字样（转发留名，不会红）；中风险。
3. **F 船况措辞 / N 内景题**（中低）：smoke 在 Main 实例上直调，转发留名即可；F 被船屋 / 船籍簿 / 市舶司三个拆出件经 `main.` 共用。
4. **A / E / H / I / K / B / X** 风险高，仍先做「Main 家族源码」共用 helper 的门禁 lane（第五 / 七 / 九刀候选）。
