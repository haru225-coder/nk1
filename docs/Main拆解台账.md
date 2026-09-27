# Main.gd 拆解台账

`scripts/Main.gd` 按页面簇往 `scripts/ui/` 拆。每刀一节，只往后追加，不改前面各节。
手法（lane ms / mz / ms2 起一直沿用）：隔离 worktree 里改，Main 保留同名同签名的一行转发，信号目标仍是 Main 的同名方法；
新文件登记到 `check_symbols.py` 和 `godot_smoke.gd` 的 `MAIN_SPLITS`，以及 `godot_compile_check.gd` 的 SCRIPTS；
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
