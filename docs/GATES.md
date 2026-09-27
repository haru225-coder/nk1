# 门禁总表（GATES）

每轮 lane 收尾都要跑的门禁、各自判什么、红了长什么样、怎么机读。
机读开关 `--json`：Python 门禁由 `tools/gate_json.py` 统一实现（纯 stdlib）；GDScript 门禁（smoke / compile / story / p7 / patrol 与全部接 `shot_gate` 的截图探针）另有 `tools/gate_report.gd` 原生实现（lane g2，见 §二末）。**不加开关时每道门禁的人读输出与退出码一字不变**。

- Godot：`/home/box/.local/bin/godot`（4.6.3，下文写 `godot`）；工作目录为仓库根。
- 退出码语义（人读 / `--json` 相同）：`0` 绿，非 `0` 红。`gate_json.py` 自身参数错为 `2`。
- 带窗口的门禁（patrol、截图探针）须 `DISPLAY=:2`。

## 一、总表

<!-- GATES:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 注册表生成，勿手改 -->
| # | 门禁 | 族 | 档 | 一键跑 | 本地命令 | `--json` | 判什么 | 绿长相 | 红长相 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | check_symbols | Python | 必跑 | ✓ | `python3 tools/check_symbols.py` | `python3 tools/check_symbols.py --json` | autoload 注册与跨文件引用真实存在；各 lane 累积的文案 / 接线契约（源码字符串断言）；探针文件存在 | 末行 `结果：全部通过` | `✗ …` 行；末尾 `结果：N 项问题` + 逐条 `   ✗` 复述 |
| 2 | verify_economy | Python | 必跑 | ✓ | `python3 tools/verify_economy.py` | `python3 tools/verify_economy.py --json` | 数据完整性（港/货/航线互引）；复刻 Economy/Voyage 公式验行情、税费、航速、新闻冲击 | `结果：全部通过` | `✗` 行；`结果：N 项未通过` |
| 3 | simulate_run | Python | 必跑 | ✓ | `python3 tools/simulate_run.py` | `python3 tools/simulate_run.py --json` | 开局 1000 钱小艍船端到端一局：卡补给 / 卡舱位 / 卡钱等设计死锁；分船账不变量 | `结果：全部通过　—— 核心循环可闭合…` | `✗` 行；`结果：N 项未通过`（中间 4 格缩进的 `✗ 船i…` 是账目诊断细行，不单独计数） |
| 4 | verify_coastline | Python | 必跑 | ✓ | `python3 tools/verify_coastline.py` | `python3 tools/verify_coastline.py --json` | coastline / sealanes / chart_labels 数据形状；港口贴岸；绕岸航线在海上；海图代码接线；底图尺寸与投影常量 | `环 … · 标注 …` + `结果：全部通过` | `✗` 行；`结果：N 项未通过` |
| 5 | check_assets | Python | 必跑 | ✓ | `python3 tools/check_assets.py` | `python3 tools/check_assets.py --json` | 脚本/场景里 `res://assets/…` 引用、PORT_BG/FACILITY_BG、前缀拼接、人物立绘都存在且有 `.import` | `资产引用 N 个…全部存在` + `结果：全部通过`（**过了不逐条打印**） | `FAIL: …` 行；`结果：N 项失败` |
| 6 | verify_story_data | Python | 必跑 | ✓ | `python3 tools/verify_story_data.py` | `python3 tools/verify_story_data.py --json` | news / scenes effects / npcs / 结局年号 / 人物原稿与上屏字段：数据里写的键代码必须接住 | 一行统计 + `结果：全部通过`（**过了不逐条打印**） | `FAIL: …` 行；`结果：N 项失败` |
| 7 | simulate_endgame | Python | 必跑 | ✓ | `python3 tools/simulate_endgame.py` | `python3 tools/simulate_endgame.py --json` | 1268 后终局：身份判定、守城胜率、崖山门槛、窗口宽度、「花钱买过关」；比对 GameState/Main 常量 | `结果：全部通过　—— 终局窗口够宽…` | `✗` 行 + `FAIL:` 复述；`结果：N 项失败`；常量找不到时 `AssertionError` 崩（无 FAIL 行） |
| 8 | verify_save_robustness | Python | 加跑：动 SaveLoad / 存档 | — | `python3 tools/verify_save_robustness.py [--source X.gd]` | `python3 tools/verify_save_robustness.py [--source X.gd] --json` | （lane t2）SaveLoad 守卫存在性与顺序 + 源码驱动模型跑坏档/好档/槽态 fixture + 变异自检 | `结果：全部通过`；可能有 `⚠ 未体检的强类型字段（不计失败）` | `✗` 行；`结果：N 项问题` |
| 9 | import | Godot | 必跑·步骤（不判红绿） | ✓ | `godot --headless --import --path .` | `python3 tools/gate_json.py --godot import` | 刷新资源导入缓存（`.godot/`、`*.import`）；须先于 check_assets 与 Godot 门禁跑 | exit 0，只有进度条 | **无红长相**（不判红绿） |
| 10 | smoke | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/godot_smoke.gd` | `godot --quiet --headless --path . -s res://tools/godot_smoke.gd -- --json` | autoload 起得来、章节/旗标/结局按数据走、headless 零延迟旁路 | `GODOT SMOKE PASS` | `✗` 行；`GODOT SMOKE FAIL` + 复述 |
| 11 | compile | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/godot_compile_check.gd` | `godot --quiet --headless --path . -s res://tools/godot_compile_check.gd -- --json` | 清单脚本 `load()` + `can_instantiate()`；场景解析（lane m2：ext_resource / 子资源 / 脚本坏）；守护清单 | `COMPILE_CHECK SUMMARY bad=0/N` | `COMPILE_CHECK FAIL …` 行；`bad=k/N` |
| 12 | story | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/godot_story_check.gd` | `godot --quiet --headless --path . -s res://tools/godot_story_check.gd -- --json` | 新闻按月投放不重复、1268 身份结算恰一次、存档 round-trip、真机抵港路由 | `STORY_CHECK SUMMARY fails=0` | `STORY_CHECK FAIL …`；`fails=k` |
| 13 | p7 | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd` | `godot --quiet --headless --path . -s res://tools/p7_guild_exam_smoke.gd -- --json` | 行会入行 / 贡院赴试 / 誊录：扣费门槛、每章一次、跨月结算时序 | `P7_GUILD_EXAM_SMOKE_OK` | `FAIL …` 行；`P7_GUILD_EXAM_SMOKE_FAIL k` |
| 14 | patrol | Godot | 必跑 | ✓ | `DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/patrol_shell.gd -- --json` | 挂主场景走开局、三港、九设施、海图：1280×720 按钮不越界、焦点色、航向牌、终局港口页；截图旁证一色判据（lane pg，一色只记 ⚠） | `PATROL SHELL PASS`（前一行 `✓ 截图旁证 n/n 张非一色`） | `✗` 行；`PATROL SHELL FAIL` + 复述 |
| 15 | 截图门禁（24 支，见下表） | 截图 | 加跑：动画面 / UI / 过场 | — | `NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --path . -s res://tools/<探针>.gd` | `NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --quiet --path . -s res://tools/<探针>.gd -- --json` | （lane m3 立、sg2 扩到全部截图脚本，新截图脚本一律接它）`tools/shot_gate.gd`：零截图 / 空视口 / 一色空图 / 张数不足一律红；契约模式须显式 `-- --contract` | `<TAG>_OK shots=n/n -> 目录`；契约模式 `<TAG>_CONTRACT_OK…` | `✗ …` + `<TAG>_FAIL k（shots=…）`；headless 下 `<TAG>_FAIL headless（…不是画面回归）` |
| 16 | save_robust_probe | Godot | 加跑：动 SaveLoad / 存档 | — | `godot --headless --path . -s res://tools/save_robust_probe.gd` | `python3 tools/gate_json.py --godot save_robust_probe` | （lane h1h2 / rt）坏分区退 .bak、只剩 .bak 取标签、两份皆坏不抛错 | `SAVE_ROBUST_PROBE PASS`（大量 `ERROR: 存档结构异常…` 是故意喂坏档，属预期） | `✗` 行 / 非零退出；输出含 `SCRIPT ERROR` 即算失败 |
| 17 | check_sidecars | Python | 加跑：提交新 .gd / .gdshader / 素材，或挪删它们 | — | `python3 tools/check_sidecars.py` | `python3 tools/check_sidecars.py --json` | （lane ag / ag2）按 git 索引：已跟踪 .gd/.gdshader 须有已跟踪 `.uid`，可导入素材须有 `.import`；反向不许只提侧车 / 多余侧车；侧车内容与源文件、场景引用、VRAM 基线一致，uid 唯一；工作树里已跟踪侧车不许漂移。口径表见 docs/侧车口径.md | `结果：全部通过` | `FAIL: …` 行（缺侧车 / 孤儿·多余侧车 / 内容漂移 / 非基线形态 / 工作树漂移）；`结果：N 项失败` |
| 18 | save_migrate_probe | Godot | 加跑：动存档结构 / save_schema | — | `godot --headless --path . -s res://tools/save_migrate_probe.gd` | `python3 tools/gate_json.py --godot save_migrate_probe` | （lane sv）v1 老档读入补字段、回写 v2、原件留 .v1；未来档明确拒读、不退副抄、文件不动 | `SAVE_MIGRATE_PROBE PASS` | `✗` 行；`SAVE_MIGRATE_PROBE FAIL fails=k`；输出含 `SCRIPT ERROR` 即算失败 |
| 19 | gates_md | Python | 加跑：动门禁清单 / docs/GATES.md | — | `python3 tools/gates_md.py` | `python3 tools/gates_md.py --json` | （lane gd3 / gd4 / gd5；gd5 加 §二 批量巡检块、`.claude/todo.md` 验证段）本注册表 vs docs/GATES.md §一、§二批量巡检、§四三个生成块逐字一致；注册的脚本都在；接 shot_gate 的截图脚本全部入册；附属自检的开关还在源码里；§三 小节编号对得上；§三 与 todo.md 验证段的一键跑命令与必跑档逐条同序 | `结果：全部通过` | `✗` 行（附首处差异）；`结果：N 项问题`；修法 `python3 tools/gates_md.py --write` |

每轮必跑（`.claude/todo.md` 验证段）：先跑步骤 9 import（不判红绿），再跑「七道 Python + smoke/compile/story/p7/patrol」十二道门禁；8、15、16、17、18、19 按 lane 内容加跑（档列写了何时）。「一键跑」列 = §三「一键人读全跑」那段命令。

**门禁开关与附属自检**（4 项；不另立一道门禁，随所属门禁默认跑到的算进一键跑，要开关的手动开；CI 专属步骤见 §四）：

| # | 项 | 所属门禁 | 族 | 一键跑 | 命令 | 期望输出 | 失败含义 |
|---|---|---|---|---|---|---|---|
| 1 | builtin_api 头部自检 | 1. check_symbols（lane cs3） | Python | ✓ | `python3 tools/check_symbols.py` | 「二、跨文件引用检查」首行 `✓ 内置清单 tools/builtin_api.txt（godot 4.6.3…）：N 类，Object→Node 链 M 名 + 手写补充 5 名` | `✗ tools/builtin_api.txt 正文与头部 sha256 不符` / `头部缺 godot 版本 / sha256 行` / `不存在` = 清单被手改或截断；`导自 godot X，本机 godot Y` = 本机换了 Godot 版本；`extends …清单链上缺类` = autoload 基类不在导出范围（先加进 `tools/gen_builtin_list.gd` 的 CLASSES）。都计入 check_symbols 问题、退 1，修法 `--regen` |
| 2 | check_symbols --regen | 1. check_symbols（lane cs3） | Python | — | `python3 tools/check_symbols.py --regen` | `✓ --regen：ClassDB 导出与 tools/builtin_api.txt 逐字节一致，未改动`；有漂移则 `↻ --regen：已按 ClassDB 重写 tools/builtin_api.txt（+a / −b 行；请连同提交）`。之后照常跑完整道 check_symbols，退出码按整道算 | `✗ --regen：找不到 godot` / `gen_builtin_list.gd 失败（rc=…）` → 计入问题、退 1。**会改写 `tools/builtin_api.txt`**，所以不进一键跑；漂移只在 CI 步骤里配 `git diff --exit-code` 判红（见 §四） |
| 3 | check_symbols --suggest | 1. check_symbols（lane cs4） | Python | — | `python3 tools/check_symbols.py --suggest`（或 `CHECK_SYMBOLS_SUGGEST=1 python3 tools/check_symbols.py`） | 多出「二之三、字符串派发候选提示」一节（`emit_signal` / `X.call` / `call_deferred` / `callv` / `Callable(obj, …)` 字面量），没疑点时没有 `⚠ WARN` 行；不开时输出逐字节不变，开了退出码也不变 | **不判红**：`⚠ WARN <文件>:L<行> <调用>  ← <作用域>：无此 func` / `…：无此 signal` = 字面量名在对应作用域里找不到，人工判真死引用 / 误报；`--json --suggest` 里记 `level: warn`（ok=true，不计 pass/fail） |
| 4 | compile 清单自检（inventory） | 11. compile（lane ea4） | Godot | ✓ | `godot --headless --path . -s res://tools/godot_compile_check.gd` | `COMPILE_CHECK OK   inventory SCRIPTS == tracked *.gd under scripts/tools (exempt N)` | `COMPILE_CHECK FAIL inventory <原因> …`（原因 `unlisted` / `listed-missing` / `dup` / `exempt-stale` / `exempt-but-listed`） = `git ls-files` 里已跟踪的 `.gd` 没进 `SCRIPTS`（或 `INVENTORY_EXEMPT` 没写理由）、清单路径不存在 / 重复 / 豁免失效，整体计 bad+1；`COMPILE_CHECK NOTE inventory git ls-files unavailable` = 没 git，退回扫盘（warn，不判红） |

**截图门禁明细**（接 `tools/shot_gate.gd` 的全部 24 支；TAG / 张数 / 截图目录现读脚本源码。headless 只验契约：本地命令换 `--headless` 并加 `-- --contract`，`--json` 写 `godot --headless --quiet --path . -s res://tools/<探针>.gd -- --contract --json`）。「截图目录」列是不设 `NK1_SHOT_DIR` 时的默认（根 `/workspace/nk1-qa-shots`，只在刷新共享证据图时用）；**worktree / 自测推荐一律加前缀 `NK1_SHOT_DIR=/tmp/<lane>/shots`**，全部探针改落 `<该目录>/<子目录>`、patrol 旁证落 `<该目录>/patrol`，默认目录不动：

| # | 探针 | 接入 | TAG | 张数 | 截图目录（默认） | 本地命令 | `--json` |
|---|---|---|---|---|---|---|---|
| 1 | vision_stage_probe | m3 | `VISION_STAGE_PROBE` | 2 | `/workspace/nk1-qa-shots/vision` | `DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/vision_stage_probe.gd -- --json` |
| 2 | vision_letterbox_probe | m3 | `VISION_LETTERBOX_PROBE` | 7 | `/workspace/nk1-qa-shots/vision` | `DISPLAY=:2 godot --path . -s res://tools/vision_letterbox_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/vision_letterbox_probe.gd -- --json` |
| 3 | qa_p7_screenshots | m3 | `QA_P7_SHOTS` | 8 | `/workspace/nk1-qa-shots/polish` | `DISPLAY=:2 godot --path . -s res://tools/qa_p7_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_p7_screenshots.gd -- --json` |
| 4 | combat_vfx_probe | sg2 | `COMBAT_VFX_PROBE` | 4 | `/workspace/nk1-qa-shots/combat` | `DISPLAY=:2 godot --path . -s res://tools/combat_vfx_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/combat_vfx_probe.gd -- --json` |
| 5 | combat_wire_probe | sg2 | `COMBAT_WIRE_PROBE` | 4 | `/workspace/nk1-qa-shots/combat` | `DISPLAY=:2 godot --path . -s res://tools/combat_wire_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/combat_wire_probe.gd -- --json` |
| 6 | qa_companion_preview_screenshots | sg2 | `QA_COMPANION` | 4 | `/workspace/nk1-qa-shots/companions` | `DISPLAY=:2 godot --path . -s res://tools/qa_companion_preview_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_companion_preview_screenshots.gd -- --json` |
| 7 | qa_ending_reread_probe | sg2 | `QA_ENDING` | 6 | `/workspace/nk1-qa-shots/ending` | `DISPLAY=:2 godot --path . -s res://tools/qa_ending_reread_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_ending_reread_probe.gd -- --json` |
| 8 | qa_chart_hud_screenshots | sg2 | `QA_CHART_HUD` | 5 | `/workspace/nk1-qa-shots/chart` | `DISPLAY=:2 godot --path . -s res://tools/qa_chart_hud_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chart_hud_screenshots.gd -- --json` |
| 9 | qa_wire_vision_screenshots | sg2 | `QA_WIRE_VISION` | 2 | `/workspace/nk1-qa-shots/wire` | `DISPLAY=:2 godot --path . -s res://tools/qa_wire_vision_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_wire_vision_screenshots.gd -- --json` |
| 10 | qa_chars_wire_screenshots | sg2 | `QA_CHARS_WIRE` | 4 | `/workspace/nk1-qa-shots/chars` | `DISPLAY=:2 godot --path . -s res://tools/qa_chars_wire_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chars_wire_screenshots.gd -- --json` |
| 11 | qa_title_probe | sg2 | `QA_TITLE` | 5 | `/workspace/nk1-qa-shots/title` | `DISPLAY=:2 godot --path . -s res://tools/qa_title_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_title_probe.gd -- --json` |
| 12 | qa_port_doors_probe | sg2 | `QA_PORT_DOORS` | 5 | `/workspace/nk1-qa-shots/port-doors` | `DISPLAY=:2 godot --path . -s res://tools/qa_port_doors_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_port_doors_probe.gd -- --json` |
| 13 | qa_drydock_probe | sg2 | `QA_DRYDOCK` | 9 | `/workspace/nk1-qa-shots/drydock` | `DISPLAY=:2 godot --path . -s res://tools/qa_drydock_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_drydock_probe.gd -- --json` |
| 14 | qa_siege_endgame_probe | sg2 | `QA_SIEGE` | 8 | `/workspace/nk1-qa-shots/siege` | `DISPLAY=:2 godot --path . -s res://tools/qa_siege_endgame_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_siege_endgame_probe.gd -- --json` |
| 15 | qa_letterbox_copy_probe | sg2 | `QA_LETTERBOX_COPY` | 4 | `/workspace/nk1-qa-shots/letterbox` | `DISPLAY=:2 godot --path . -s res://tools/qa_letterbox_copy_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_letterbox_copy_probe.gd -- --json` |
| 16 | qa_patrol_pack_screenshots | sg2 | `QA_PATROL_PACK` | 11 | `/workspace/nk1-qa-shots/patrol-pack` | `DISPLAY=:2 godot --path . -s res://tools/qa_patrol_pack_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_patrol_pack_screenshots.gd -- --json` |
| 17 | qa_tavern_news_wall_screenshots | sg2 | `QA_TAVERN_NEWS_WALL` | 2 | `/workspace/nk1-qa-shots/tavern` | `DISPLAY=:2 godot --path . -s res://tools/qa_tavern_news_wall_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_tavern_news_wall_screenshots.gd -- --json` |
| 18 | qa_chapter_promote_probe | sg2 | `QA_CHAPTER` | 4 | `/workspace/nk1-qa-shots/chapter` | `DISPLAY=:2 godot --path . -s res://tools/qa_chapter_promote_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chapter_promote_probe.gd -- --json` |
| 19 | qa_voyage_status_probe | sg2 | `QA_VOYAGE` | 6 | `/workspace/nk1-qa-shots/voyage` | `DISPLAY=:2 godot --path . -s res://tools/qa_voyage_status_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_voyage_status_probe.gd -- --json` |
| 20 | qa_crew_hire_probe | sg2 | `QA_CREW_HIRE` | 6 | `/workspace/nk1-qa-shots/crew` | `DISPLAY=:2 godot --path . -s res://tools/qa_crew_hire_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_crew_hire_probe.gd -- --json` |
| 21 | qa_discovery_probe | sg2 | `QA_DISCOVERY` | 5 | `/workspace/nk1-qa-shots/discovery` | `DISPLAY=:2 godot --path . -s res://tools/qa_discovery_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_discovery_probe.gd -- --json` |
| 22 | qa_chars_screenshots | sg2 | `QA_CHARS_SHOTS` | 10 | `/workspace/nk1-qa-shots/chars` | `DISPLAY=:2 godot --path . -s res://tools/qa_chars_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chars_screenshots.gd -- --json` |
| 23 | vision_fill_shots | sg2 | `vision_fill_shots` | 4 | `/workspace/nk1-qa-shots/vision-fill` | `DISPLAY=:2 godot --path . -s res://tools/art/vision_fill_shots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/art/vision_fill_shots.gd -- --json` |
| 24 | qa_market_panel_probe | aa | `QA_MARKET` | 5 | `/workspace/nk1-qa-shots/market` | `DISPLAY=:2 godot --path . -s res://tools/qa_market_panel_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_market_panel_probe.gd -- --json` |

**不算门禁**（别拿来判红绿；想跑照样可以，`--json` 也能用）：

| 脚本 | 本地命令 | `--json` | 为什么不算 |
|---|---|---|---|
| `tools/legacy/verify_narrative.py` | `python3 tools/legacy/verify_narrative.py` | `python3 tools/gate_json.py tools/legacy/verify_narrative.py` | （lane gd2 挪入 legacy）绑定云端 21ce 未收的 P7 平行实现（`borrow_ceiling` / `_discovery_extra` / `seen_scenes` 主干从未有；开局链截断 monk、删 `chapter` 臂与主干设计相反），合并台账第 14 行即定「留档不入门禁」；主干上恒红 23 项属预期，仍成立的「效果键必须接住」由 verify_story_data 覆盖 |
| `tools/legacy/p7_smoke.gd` | `godot --headless --path . -s res://tools/legacy/p7_smoke.gd` | `python3 tools/gate_json.py --godot p7_smoke` | （lane gd8 挪入 legacy）与 verify_narrative 同源，绑定 21ce 未收的 P7 平行实现（开局链进泉州、港口节拍、`seen_scenes`、`borrow_ceiling`），合并台账第 14 行定「留档不入门禁」；主干上 4 项 FAIL 后在 `borrow_ceiling()` 处 SCRIPT ERROR、不 quit 挂死（干净 worktree 同，lane l1 已记）；P7 行会 / 贡院由 p7（`p7_guild_exam_smoke.gd`）接管 |
| 其余 `tools/qa_*_probe.gd` / `*_probe.gd` 专项探针（未接 shot_gate 的） | 见各脚本头注释 | — | 各 lane 的专项探针，只在对应 lane 里跑；要升格为门禁就进 `tools/gate_json.py` 注册表 |
<!-- GATES:END -->

## 二、`--json` 机读输出

### 怎么开

```sh
# Python 门禁：直接加开关（1–8 都有）
python3 tools/check_symbols.py --json
python3 tools/verify_save_robustness.py --source /tmp/old_SaveLoad.gd --json   # 其余参数照传

# Godot 门禁外包一层（不依赖 .gd 自带开关；§一 `--json` 列写原生的见 §二末，import 步骤等未接原生的走这条）：预设 = 注册表里的 Godot 门禁 + 截图脚本
python3 tools/gate_json.py --godot compile
DISPLAY=:2 python3 tools/gate_json.py --godot patrol
# 任意 res:// 脚本：默认 --headless；带窗口加 --display；用户参数放 -- 之后
DISPLAY=:2 python3 tools/gate_json.py --godot res://tools/vision_stage_probe.gd --display
python3 tools/gate_json.py --godot res://tools/vision_stage_probe.gd -- --contract

# 等价写法 / 兜底
python3 tools/gate_json.py tools/verify_economy.py      # = verify_economy.py --json
python3 tools/gate_json.py -- <任意命令 …>               # 通用解析
```

门禁清单本身也能机读：`python3 tools/gate_json.py --list` 输出注册表（`gates[]` 带 `tier` / `family` / `oneclick` / `cmd` / `json` / `why`，`shot_probes[]` 带 `tag` / `shots` / `out_dir`，`subchecks[]` 带 `parent` / `oneclick` / `expect` / `fail`，`oneclick[]` 是一键跑命令，`oneclick_json[]` 是同序的 `{id, tier, json}`，`ci_steps[]` 是 §四），§一、§二「批量巡检」块、§四就是它生成的。

Godot 路径取 `$GODOT`，其次 `PATH` 里的 `godot`，最后 `~/.local/bin/godot`。

### 输出形状

stdout 只有一段 JSON（门禁原本的 stdout/stderr 被捕获解析，不外泄）：

```json
{
 "gate": "check_symbols",
 "ok": true,
 "exit_code": 0,
 "summary": "结果：全部通过",
 "checks": [{"name": "GameManager  res://scripts/GameManager.gd", "ok": true, "detail": "一、project.godot 的 autoload 注册"}],
 "counts": {"total": 405, "pass": 405, "fail": 0, "warn": 0, "engine_errors": 0, "script_errors": 0},
 "cmd": ["python3", "tools/check_symbols.py"]
}
```

| 字段 | 含义 |
|---|---|
| `ok` | **恒等于 `exit_code == 0`**，与人读模式同一判据；`checks` 只是明细，不另立判据 |
| `exit_code` | 门禁原退出码；`--json` 进程也以它退出 |
| `summary` | 收尾判词行（`结果：…` / `… SUMMARY …` / `GODOT SMOKE PASS` / `<TAG>_OK …`） |
| `checks[]` | `{name, ok, detail}`；`detail` 是所在小节（如 `一、数据完整性`）或失败原因（compile 的 `ext-script-broken …`） |
| `checks[].level` | 仅 warn 条目有：`"warn"`（`⚠ …`、`COMPILE_CHECK NOTE …`），ok=true，不计入 pass/fail/total |
| `counts` | `total = pass + fail`（不含 warn）；`engine_errors` 为 Godot `ERROR:` / `SCRIPT ERROR` 类行数，`script_errors` 为其中 `SCRIPT ERROR` 行数——只报数、不改 `ok` |
| `errors` | 有引擎错误行时附前 20 行 |
| `tail` | 红时附原输出末 20 行 |
| `notes` | 如带窗口门禁却没设 `DISPLAY` |

明细怎么来：
- 用 `check(cond, msg)` 的 Python 门禁（2–7）：子进程里挂 `sys.setprofile` 实录每次 `check()` 调用，所以连「过了不打印」的 check_assets / verify_story_data 也有逐条明细（这两道的 `name` 是失败时的措辞，`detail` 标「过时不打印」）。
- 其余（check_symbols、verify_save_robustness、Godot 门禁）：解析 `✓ / ✗ / ⚠ / FAIL: / COMPILE_CHECK / STORY_CHECK / OK   / FAIL ` 行；收尾判词之后的 `✗` 视为复述，不重复计数。
- 红了却一条失败都没解析到（脚本崩溃、提前 `exit`）：补一条 `{"name": "exit_code", "ok": false}`，看 `tail`。

批量巡检（CI / 夜巡；下块由注册表生成——增删必跑门禁、改 `--json` 写法后 `python3 tools/gates_md.py --write` 随之更新，勿手改）：

<!-- GATES-BATCH:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 的 oneclick_json 生成，勿手改 -->
```sh
# 必跑十三条的机读版（与 §四 第 0 步同序，每条换 §一 `--json` 列）；导入步骤不判红绿，落 /tmp/gates/steps/、不进汇总
rm -rf /tmp/gates && mkdir -p /tmp/gates/steps
python3 tools/gate_json.py --godot import > /tmp/gates/steps/import.json
python3 tools/check_symbols.py --json > /tmp/gates/check_symbols.json
python3 tools/verify_economy.py --json > /tmp/gates/verify_economy.json
python3 tools/simulate_run.py --json > /tmp/gates/simulate_run.json
python3 tools/verify_coastline.py --json > /tmp/gates/verify_coastline.json
python3 tools/check_assets.py --json > /tmp/gates/check_assets.json
python3 tools/verify_story_data.py --json > /tmp/gates/verify_story_data.json
python3 tools/simulate_endgame.py --json > /tmp/gates/simulate_endgame.json
godot --quiet --headless --path . -s res://tools/godot_smoke.gd -- --json > /tmp/gates/smoke.json
godot --quiet --headless --path . -s res://tools/godot_compile_check.gd -- --json > /tmp/gates/compile.json
godot --quiet --headless --path . -s res://tools/godot_story_check.gd -- --json > /tmp/gates/story.json
godot --quiet --headless --path . -s res://tools/p7_guild_exam_smoke.gd -- --json > /tmp/gates/p7.json
DISPLAY=:2 godot --quiet --path . -s res://tools/patrol_shell.gd -- --json > /tmp/gates/patrol.json
python3 tools/gate_json.py --judge /tmp/gates/*.json   # 汇总：逐道一行 ✓/✗；任一道红或没有 JSON 行 → 退 1
```
<!-- GATES-BATCH:END -->

### GDScript 门禁原生 `--json`（lane g2，`tools/gate_report.gd`）

```sh
# 用户参数给 --json；加 --quiet 则整段 stdout 恰好一行 JSON
godot --headless --quiet --path . -s res://tools/godot_compile_check.gd -- --json
godot --headless --quiet --path . -s res://tools/godot_smoke.gd -- --json            # story / p7 同法
DISPLAY=:2 godot --quiet --path . -s res://tools/patrol_shell.gd -- --json
DISPLAY=:2 godot --quiet --path . -s res://tools/qa_title_probe.gd -- --json         # 接 shot_gate 的截图探针同法
godot --headless --quiet --path . -s res://tools/qa_title_probe.gd -- --contract --json
```

接了原生的：`godot_smoke` / `godot_compile_check` / `godot_story_check` / `p7_guild_exam_smoke` / `patrol_shell`，以及经 `shot_gate.gd` 三个收尾函数（`finish_shots` / `fail_no_render` / `finish_contract`）收尾的全部截图探针（探针本身未改）。import 步骤（不跑脚本）、`save_robust_probe`、`save_migrate_probe` 未接，照旧走外包 `gate_json.py --godot`。

- 机理：门禁脚本 `preload` 本件；带 `--json` 时本件在 `_static_init`（门禁脚本编译时，早于 `_init`）关掉 `Engine.print_to_stdout`，门禁与游戏代码的 `print` 一律不外泄；收尾 `GateReport.finish()` 临时打开 stdout 打**一行**紧凑 JSON，再照旧 `quit(rc)`。不带 `--json`：只往静态数组记条目，不打印、不挂 logger，人读输出逐字节不变。
- **`--quiet`**：引擎横幅 `Godot Engine v…`（带窗口时还有 `OpenGL API …`）在任何脚本加载前就已打出，脚本关不掉；不加 `--quiet` 时 JSON 是 stdout 的最后一行。人读模式别加 `--quiet`（会吞掉全部人读输出）。
- 形状同上表；`ok` 仍恒等于 `exit_code == 0`。`checks` 由各门禁的检查 helper 显式登记（`GateReport.check / warn`），不解析文本，逐条与外包解析结果相同。
- 截图探针：每张存下的图记一条 `{name: 文件名, ok: true, detail: "shot"}`，`fails` 每条记一条失败；另带 `tag`、`shots`、`expected_shots`、`out_dir`（契约模式带 `contract: true`，headless 判红带 `no_render: true`）。`gate` 取入口脚本文件名（如 `qa_title_probe`）。
- `engine_errors` / `errors` 由一个只数 ERROR / SCRIPT ERROR / SHADER ERROR 的 Logger 收（WARNING 不计），**只收脚本加载之后的**：patrol 开头 3 行 Vulkan 回落，外包记 `engine_errors: 3`，原生记 0。仍只报数、不改 `ok`。
- 与外包的差别：没有 `tail`（stdout 已关，原输出不留）；`cmd` 只含引擎没吞掉的参数（`--headless` / `--path` 不在其中）。
- 崩溃兜底（lane gd7）：带 `--json` 时本件在首帧前给 `root.tree_exiting` 挂钩。门禁没走到 `finish()` 就退出——`finish` 前 `quit()`、窗口被关（`WM_CLOSE_REQUEST` 自动 quit）——SceneTree 收尾拆 root 时补打**一行** `{"ok": false, "error": "no_finish", …}`（`checks` 末尾一条 `no_finish` 失败，前面照录已登记的条目），并把进程退出码改成 1（`quit()` 传的原码 OS 不给读；`ok == (exit_code == 0)` 照旧成立）。走过 `finish()` 的不再打，stdout 仍只一行。**进程被信号杀（`timeout` 掐断卡死的门禁）、引擎崩溃时什么钩子都不走，stdout 仍没有 JSON 行**——这一类只能由消费方判红：
  - `python3 tools/gate_json.py --native <预设|res://….gd> [--display] [--timeout N] [-- 用户参数]`（或 `--native [--timeout N] -- <完整命令>`）：自动补 `--quiet` / `-- --json` 跑原生门禁，原样转出 JSON；没 JSON 行合成 `ok: false, error: "no_json"`（`no_json_line` 条目 + `tail`，退出码沿用，0 也改 1，超时记 124）；JSON 不止一行、`exit_code` 与进程退出码不符、`ok` 与 `exit_code` 不符也判红。
  - `python3 tools/gate_json.py --judge <文件…>`：批量落盘的 stdout 逐个判（同上规则，退出码不可知时只看 JSON），任一红退 1。

## 三、逐道：怎么跑、怎么读、常见红因

一键人读全跑（与 `.claude/todo.md` 验证段一致）：

```sh
godot --headless --import --path .
python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py \
 && python3 tools/verify_coastline.py && python3 tools/check_assets.py \
 && python3 tools/verify_story_data.py && python3 tools/simulate_endgame.py
godot --headless --path . -s res://tools/godot_smoke.gd
godot --headless --path . -s res://tools/godot_compile_check.gd
godot --headless --path . -s res://tools/godot_story_check.gd
godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd
DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd
```

**共同的坑：工作树是多 lane 共用的。** 别的 lane 未提交的改动（例如正在改 `SaveLoad.gd`）会让你的门禁红。判「是不是我弄红的」：`git worktree add --detach /tmp/x HEAD`，只放进自己的改动再跑（Godot 门禁先 `cp -a .godot /tmp/x/` 省掉重新导入）。

### 1. check_symbols
- 读：按「一、二、…」小节打 `✓/✗`；末尾汇总 `结果：N 项问题` 并复述每条。`--json` 的 `detail` 就是小节名。
- 开关与附属自检（`builtin_api.txt` 头部自检、`--regen`、`--suggest`）见 §一「门禁开关与附属自检」；`--regen` 漂移比对是 §四 CI 步骤。
- 常见红因：改了 `Main.gd` 等处的文案 / 函数名，但本脚本里对应 lane 的**源码字符串契约**没同步（这是最常见的一类，改文案先 grep 本脚本）；`project.godot` autoload 与 `AUTOLOADS` 表不符；契约要求存在的 `tools/*.gd` 探针缺失。

### 2. verify_economy
- 读：`一、数据完整性` 起逐节 `✓/✗`；`结果：N 项未通过`。
- 常见红因：`data/ports.json` / `goods.json` 引用悬空（新港、新货、connections 拼错）；`Economy.gd` / `Voyage.gd` 公式或常量改了而脚本里的复刻没同步；新闻冲击倍率越界。

### 3. simulate_run
- 读：前半是模拟流水（`第 N趟 …`，其中 `✗查扣` 是剧情事件不是失败）；`✓/✗` 才是断言；`结果：N 项未通过`。
- 常见红因：`ships.json` / `goods.json` 数值改动造成死锁（舱位装不下补给、钱不够换船）；`Fleet.gd` 分船装载公式改了未同步（会先出一串缩进的 `✗ 船i … 料 > 载重` 诊断行）。

### 4. verify_coastline
- 读：五节（环 / 港口贴岸 / 绕岸航线 / 海名标注 / 接线）；绿时先打一行统计。
- 常见红因：重建 `coastline.json` 后 `meta.points` / `meta.rings` 与实数不符；港口经纬度漂到腹地或外海；`SeaChart.gd` 接线字段改名；底图尺寸与 `chart_projection.json` 不一致。

### 5. check_assets
- 读：绿时只有一行统计；红时每条 `FAIL: … 文件不存在` / `缺 .import`。
- 常见红因：代码引用了还没入库的图；新图没跑过导入步骤（缺 `.import`，先跑 §9）；图坏导入失败则 `.import` 记 `valid=false`，本道判红；挪 / 改名资产没改前缀拼接表。

### 6. verify_story_data
- 读：绿时一行统计（结局年号对照 / scenes / news / npcs …）；红时 `FAIL: …`。
- 常见红因：`scenes.json` 新 effects 键 `Main.apply_effects` 没接；结局题头年号落在触发闸外；人物原稿与上屏字段不符（lane l1，见 `docs/人物原稿与上屏契约.md`）。

### 7. simulate_endgame
- 读：`── 小节 ──` 分段 `✓/✗`，红时另有 `FAIL:` 复述。
- 常见红因：`GameState.gd` / `Main.gd` 常量改名 → 正则取不到直接 `AssertionError: 找不到常量 …` 崩（人读只有 traceback；`--json` 给 `exit_code` 条目 + `tail`）；守城 / 崖山数值改动使窗口过窄或能花钱买过关。

### 8. verify_save_robustness
- 读：`一、SaveLoad 源码契约` → fixture 模型 → 变异自检（每个变体都应「判红」）；`⚠` 行不计失败。
- 常见红因：改 `SaveLoad.gd` 守卫顺序 / 函数名而没同步本脚本的抽取规则；新增强类型字段未进 `_check_partitions`（先以 `⚠` 提示）。`--source X.gd` 可对历史版本自证。

### 9. import（导入步骤，lane gd2 由 editor 降级，不判红绿）
- 命令：`godot --headless --import --path .`（Godot 4.6.3 的 `--import`：起编辑器、等资源导入完再退）。旧写法 `--headless --editor --path . --quit` 实测等价（下表两列逐项相同，新图同样生成 `.import`），仍可用；`gate_json.py --godot editor` 保留为旧名。一键跑里排第一条。
- **为什么不算门禁**（lane gd2 在干净 worktree 逐项注入故障实测；格内为 退出码 / `ERROR` 行数 / `SCRIPT ERROR` 行数）：

  | 注入的故障 | `--editor --quit` | `--import` | 谁判红 |
  |---|---|---|---|
  | 普通脚本语法错（`scripts/FloatingText.gd`） | 0 / 0 / 0 | 0 / 0 / 0 | 11 compile rc=1（`bad=2/79`：脚本 + 挂它的场景） |
  | autoload 脚本语法错（`GameManager.gd`） | 0 / 23 / 18 | 0 / 23 / 18 | 11 compile rc=1 |
  | `class_name` 脚本语法错（`UiTheme.gd`） | 0 / 324 / 322 | 0 / 324 / 322 | 11 compile rc=1 |
  | 主场景 `ext_resource` 写坏（`Main.tscn`） | 0 / 4 / 0 | 0 / 2 / 0 | 11 compile rc=1 |
  | `project.godot` 写坏 | 0 / 2 / 0 | 0 / 2 / 0 | 11 compile rc=1 |
  | 图片坏（随机字节 `.png`） | 0 / 3 / 0 | 0 / 3 / 0 | 5 check_assets rc=1（`.import` 记 `valid=false`） |
  | 无故障 | 0 / 0 / 0 | 0 / 0 / 0 | — |

  两种写法**六类故障全 exit 0**；改用 `--import` 再 grep `SCRIPT ERROR` 也兜不住第一行（普通脚本语法错一行 ERROR 都不打），而它 grep 得到的五类 compile / check_assets 已经判红。所以既不当门禁、也不加 grep 壳，只当导入步骤（注册表 `tier: step`）。
- 必须跑、且先跑：它刷新 `.godot/` 导入缓存与 `*.import`（新资产、新 `class_name` 后尤甚），5 check_assets 的 `.import` 检查与 10–18 的 Godot 门禁都依赖它。输出里的 `ERROR:` 行可作线索，判红绿看 compile / check_assets。
- 副作用：可能改写被跟踪的 `*.import`，提交前看 `git status`，别把导入噪声混进本 lane。

### 10. smoke
- 读：`✓/✗` 行，末行 `GODOT SMOKE PASS/FAIL`，FAIL 后复述。
- 常见红因：`data/chapters.json` / 旗标 / 结局数据改动；headless 旁路（过场层、章节卡）回退。

### 11. compile
- 读：`COMPILE_CHECK OK|FAIL <路径>`；场景失败带 ` :: 原因`（如 `ext-script-broken …`）；`FAIL guard …` 是守护清单里的场景；`NOTE unlisted scene` 是未入清单但照查的场景（`--json` 记 warn）；`SUMMARY bad=k/N`。
- 清单自检（lane ea4）：`COMPILE_CHECK OK|FAIL inventory …` 一项——`scripts/`、`tools/`（除 `tools/legacy/`）下 **git 已跟踪**的每个 `.gd` 都须在 `SCRIPTS` 里或在 `INVENTORY_EXEMPT` 写明理由；失败细分 `unlisted`（漏列）/ `listed-missing`（清单路径不存在）/ `dup` / `exempt-stale` / `exempt-but-listed`。只认已跟踪文件，别的 lane 未提交的新脚本不会让共用树变红；git 不可用时退回扫盘并打 `NOTE`。
- 常见红因：GDScript 语法 / 类型错（同时打 `SCRIPT ERROR: Parse Error`）；新脚本入库了却没加进 `SCRIPTS` 清单（现由 inventory 判红：`FAIL inventory unlisted …`）；场景 `ext_resource` 指向坏脚本或不存在的资源。

### 12. story
- 读：`STORY_CHECK OK|FAIL <断言>`，末行 `SUMMARY fails=k`。中途的 GDScript backtrace（`_set_background_file`）是「缺失背景图回落」用例故意触发的，不是失败。
- 常见红因：`news.json` 月份 / 身份条件改动；1268 身份结算时序；存档字段 round-trip 丢字段。

### 13. p7
- 读：`OK   …` / `FAIL …`，末行 `P7_GUILD_EXAM_SMOKE_OK` 或 `_FAIL k`。
- 常见红因：`GUILD_JOIN_FEE` 等行会 / 贡院常量或门槛改动；「先落袋再推进日期」时序被改回（lane h3 / ec）。

### 14. patrol
- 读：`✓/✗` 行，末行 `PATROL SHELL PASS/FAIL`。开头的 `ERROR: Required extension VK_KHR_surface not found` 等 3 行是 Vulkan 回落 OpenGL 的环境噪声（`--json` 里记 `engine_errors: 3`，不影响 ok）。
- 截图旁证（lane pg）：存盘（默认 `/tmp/patrol-shots/`；设 `NK1_SHOT_DIR=<目录>` 则落 `<目录>/patrol/`，lane pg3）前按像素种类数 / 直方图熵判一色（每 4px 取点、每通道 16 级；种类 ≤ 2 或熵 < 0.1 bit）。一色或拿不到图逐张打 `⚠ 截图旁证 <页> …`，**只记 warn、不改退出码**（`--json` 的 `counts.warn`）；headless 打一行 `⚠ 截图旁证未判（n 张跳过）`。判据开头自检 4 条（纯色 / 量化格边界两色抖动必判一色、杂色图不判、空图判拿不到图），自检 `✗` 即 FAIL。
- 常见红因：没设 `DISPLAY`；按钮越出 1280×720；设施页 / 终局港口页按钮文案改名（断言按文案找钮）。

### 15. 截图门禁（shot_gate.gd + 截图探针）
- 读：`<TAG>_OK shots=n/n -> 目录`；红时先列 `✗ 真失败：…`，再 `<TAG>_FAIL k（shots=…）`。
- headless 不加 `-- --contract` **必红**（`_FAIL headless …此为环境不具备，不是画面回归`）——这是设计，不是回归。只验契约：`godot --headless … -- --contract` → `<TAG>_CONTRACT_OK`。
- 输出目录（lane gd2 / pg3）：默认 `/workspace/nk1-qa-shots/<子目录>`（§一明细表「截图目录（默认）」列）；设 `NK1_SHOT_DIR=<目录>` 则全部 24 支探针整体改落 `<目录>/<子目录>`（`vision/`、`title/`、`chars/`…照原样建），patrol 旁证落 `<目录>/patrol/`（相对路径按 `$PWD` 展开）。**推荐用法：worktree / 自测一律设它**，否则会覆盖共享证据图；不设只用于刷新共享证据图：

  ```sh
  NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd
  NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd   # 旁证 → /tmp/<lane>/shots/patrol/
  ```

  脚本里统一写 `var OUT_DIR := ShotGate.out_dir("<子目录>")`，新探针别再写死绝对路径：gates_md 按这个写法读目录，并判红「截图脚本没走 `ShotGate.out_dir`」「`tools/` 已跟踪 `.gd` 代码行里写死默认根（只许 `shot_gate.gd`）」「patrol_shell 不读 `NK1_SHOT_DIR`」（lane pg3）。
- 常见红因：空视口 / 一色图（窗口没真正绘制）；张数不足。`vision_letterbox_probe` 旧有的「出战合拢时画面中线未全黑（v=0.302）」偶发红不是时序：布景是真海战，约 8–10 s 旗舰被击沉、WorldMap 自起出战墨边顶掉探针那副（lane pg 已冻住布景；再现时会先报「布景海战在墨边演示中自行结算」）。

### 16. save_robust_probe
- 读：`✓` 行 + `SAVE_ROBUST_PROBE PASS`；上百行 `ERROR: 存档结构异常 …` 是探针故意喂的坏档，预期存在；`SCRIPT ERROR` 才算失败。
- 常见红因：`SaveLoad.gd` 判坏档 / 退 `.bak` 路径改动；新强类型字段赋错型时先赋值后判型。

### 17. check_sidecars
- 读：绿时 `结果：全部通过`（前一行报 uid 个数、VRAM 纹理张数与基线、工作树是否查过）；红时每条 `FAIL: …`，末行 `结果：N 项失败`。成对 / 多余 / 内容三类只看 git 索引（已暂存也算），工作树里没跟踪的文件不查；「工作树漂移」一类比对索引与工作树里的已跟踪侧车，`--index-only` 跳过。带 `.gdignore` 的目录与 `.` 开头的路径跳过。
- 口径：哪些侧车必须入库、哪些是生成物 / 编辑器漂移不许带，判定表在 `docs/侧车口径.md`（脚本头部注释同表）。仍是 lane 加跑档（不进一键跑）；CI 里作 §四 步骤 1，紧跟导入步骤之后跑，顺带查导入有没有改写已跟踪侧车（lane gd5）。旧口径「提交时跳过 `*.uid` / `*.import`」只指别人的未跟踪侧车与编辑器顺手改写的已跟踪侧车，本 lane 新增源文件的侧车必须同 commit 带上。
- 常见红因：提交新 `.gd` / 素材时按旧口径跳过了侧车；挪 / 删源文件没带走侧车；挪 / 拷源文件连侧车一起挪 / 拷、没让编辑器重导（`source_file` / 产物名哈希对不上、uid 重复）；ARM / 移动端机器导入把 `terrain_4096.png.import` 写成 etc2 形态后提交（非基线）；跑完编辑器工作树里已跟踪 `.import` 被改写（工作树漂移：不是本 lane 有意改的就 `git checkout --`）。补法是把工作树里编辑器生成的 `<文件>.uid` / `.import` 一并入库（别手写 uid）。

### 18. save_migrate_probe
- 读：`✓/✗` 行 + `SAVE_MIGRATE_PROBE PASS` / `FAIL fails=k`；只动存档位 95，不碰正式位。
- 常见红因：`SaveLoad.gd` 的 `_inspect` / `_resolve` / `_migrate_v1_to_v2` 链改动；新加 state 字段没进迁移补齐；未来档改成了退 `.bak`。

### 19. gates_md（本文件 §一 的自检）
- 读：`一、注册表`（`tools/gate_json.py --list` 能出、注册的脚本都在、接 `shot_gate` 的截图脚本全入册且 TAG / 张数 / 目录读得到、目录都走 `ShotGate.out_dir`，`tools/` 代码里不写死默认截图根、patrol 读 `NK1_SHOT_DIR`（lane pg3）；附属自检的所属门禁在册、开关 / 判词字样还在其源码里；CI 步骤引用的 `tools/…` 都在）→ `二、docs/GATES.md`（生成表格列数整齐；§一、§四 两个标记块逐字一致，红时打首处差异的「文档 / 注册表」两行；§二「批量巡检」标记块逐字一致且在 §二 里；§三 `### N.` 编号对得上；§三「一键人读全跑」与 `.claude/todo.md`「## 验证」代码块拆出的命令（续行拼回、按 `&&` 切、去行尾 `# 注释`）都与必跑档 `cmd` 逐条同序）。
- 改法：**只改 `tools/gate_json.py` 的 `REGISTRY` / `SHOT_PROBES` / `SUBCHECKS` / `CI_STEPS`**，再 `python3 tools/gates_md.py --write`；块外（§二、§三、§四的标题）是手写，编号小节随注册表增删要补，一键跑命令段与 `.claude/todo.md` 验证段随必跑档改（这两处 `--write` 不代写）。
- 常见红因：手改了标记块；改了必跑档只改 §三 没改 `.claude/todo.md` 验证段（gd4 查出的 patrol 缺 `DISPLAY=:2` 即此类）；新截图脚本接了 `shot_gate` 却没进 `SHOT_PROBES`；某道门禁挪走 / 改名（如 `verify_narrative` 挪 `tools/legacy/`）没改注册表；加了门禁没补 §三 小节；改了 `--suggest` / `--regen` 等开关名或判词没改 `SUBCHECKS[].marks`；升降必跑档没同步 §三 一键跑命令段。

## 四、CI 建议步骤

只是建议，**不进 repo 的 CI 配置**（仓库目前没有 CI 文件）。每步退出码非 0 即红；第 0 步就是必跑十三道，其后是只适合在 CI 里跑的步骤（会写文件 / 要干净工作树）。

<!-- GATES-CI:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 的 CI_STEPS 生成，勿手改 -->
```sh
# 0. 必跑十三条（含导入步骤；= §一「一键跑」✓ / §三「一键人读全跑」；无窗口的 CI 机器 patrol 要配 Xvfb 给 DISPLAY）
godot --headless --import --path .
python3 tools/check_symbols.py
python3 tools/verify_economy.py
python3 tools/simulate_run.py
python3 tools/verify_coastline.py
python3 tools/check_assets.py
python3 tools/verify_story_data.py
python3 tools/simulate_endgame.py
godot --headless --path . -s res://tools/godot_smoke.gd
godot --headless --path . -s res://tools/godot_compile_check.gd
godot --headless --path . -s res://tools/godot_story_check.gd
godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd
DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd
# 1. 侧车成对 / 一致
python3 tools/check_sidecars.py
# 2. builtin_api 漂移
python3 tools/check_symbols.py --regen && git diff --exit-code tools/builtin_api.txt
# 3. GATES.md 与注册表一致
python3 tools/gates_md.py
# 4. docs 索引与文件一致
python3 tools/check_docs_index.py --check
```

| # | 步骤 | 接入 | 需要 | 命令 | 期望输出 | 失败含义 |
|---|---|---|---|---|---|---|
| 1 | 侧车成对 / 一致 | ag / ag2 / gd5 | python3 + git（紧跟第 0 步的导入步骤之后跑） | `python3 tools/check_sidecars.py` | `结果：全部通过`（前一行报 uid 个数、VRAM 纹理张数与基线、`工作树侧车无漂移`） | `FAIL: …` 行、退 1 = 提交的 .gd / .gdshader / 素材缺侧车或多了孤儿侧车、侧车内容与源文件 / 场景引用 / VRAM 基线不一致；或第 0 步导入把已跟踪 `.import` / `.uid` 改写了（工作树漂移：CI 机器的 Godot 版本 / 平台与入库基线不符）。口径见 docs/侧车口径.md |
| 2 | builtin_api 漂移 | cs3 / gd4 | godot（与清单头部同版本） | `python3 tools/check_symbols.py --regen && git diff --exit-code tools/builtin_api.txt` | `✓ --regen：…逐字节一致，未改动` + check_symbols `结果：全部通过`，`git diff` 无输出、退 0 | `git diff` 打出 `tools/builtin_api.txt` 的差异、退 1 = 提交的清单与本机 Godot 的 ClassDB 导出不一致（升级了 Godot / 改了 `gen_builtin_list.gd` 的 CLASSES 却没连同提交重导结果）；`--regen` 本身失败则 check_symbols 先退 1 |
| 3 | GATES.md 与注册表一致 | gd3 | python3 + git | `python3 tools/gates_md.py` | `结果：全部通过` | 有人手改了 §一 / §二批量巡检 / §四 生成块、改了注册表没 `--write`、§三 或 `.claude/todo.md` 验证段的一键跑命令与必跑清单不符，或注册的脚本挪走了 |
| 4 | docs 索引与文件一致 | doc3 / doc4 | python3 + git | `python3 tools/check_docs_index.py --check` | `结果：全部通过`（前面报索引链接条数、`git 已跟踪的 docs/**/*.md 都在索引里（N 份…）`；未跟踪的新文档只记 `⚠`） | `✗` 行、退 1：`MISSING` = 提交了 docs 下的 .md 没在 docs/README.md 补一行；`DEAD` = 索引链的文件挪走 / 改名 / 删了；`DUP` = 同一份文档链了两次。修法：改 docs/README.md |
<!-- GATES-CI:END -->
