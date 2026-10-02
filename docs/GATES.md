# 门禁总表（GATES）

每轮 lane 收尾都要跑的门禁、各自判什么、红了长什么样、怎么机读；新门禁怎样才算活的（入册 / 必跑 / 自证 / 跟号）见 §五。
机读开关 `--json`：Python 门禁由 `tools/gate_json.py` 统一实现（纯 stdlib）；GDScript 门禁（smoke / compile / story / p7 / patrol 与全部接 `shot_gate` 的截图探针）另有 `tools/gate_report.gd` 原生实现（lane g2，见 §二末）。**不加开关时每道门禁的人读输出与退出码一字不变**。

- Godot：4.6.3，下文写 `godot`，须在 PATH 上（本机装在 `~/.local/bin/godot`；Python 侧调引擎的先认 `$GODOT`）；工作目录为仓库根，命令一律 `--path .`，不写本机绝对路径（lane gd22，`RefsHostPath` 守）。
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
| 6 | verify_story_data | Python | 必跑 | ✓ | `python3 tools/verify_story_data.py` | `python3 tools/verify_story_data.py --json` | news / scenes effects / npcs / 结局年号 / 人物原稿与上屏字段：数据里写的键代码必须接住；（lane seq3）scenes.json 结构：字段齐备 / 类型 / 引用 id 存在 / 无孤儿（归档场登记 `SCENE_ARCHIVE`），附 24 类反向自证；L1B 人物数据读取只扫 git 已跟踪文件（lane w19-g11：未跟踪 / 忽略的 `tools/verify_*` 探针不扫） | 一行统计 + `结果：全部通过`（**过了不逐条打印**） | `FAIL: …` 行；`结果：N 项失败` |
| 7 | simulate_endgame | Python | 必跑 | ✓ | `python3 tools/simulate_endgame.py` | `python3 tools/simulate_endgame.py --json` | 1268 后终局：身份判定、守城胜率、崖山门槛、窗口宽度、「花钱买过关」；比对 GameState/Main 常量 | `结果：全部通过　—— 终局窗口够宽…` | `✗` 行 + `FAIL:` 复述；`结果：N 项失败`；常量找不到时 `AssertionError` 崩（无 FAIL 行） |
| 8 | verify_save_robustness | Python | 加跑：动 SaveLoad / 存档 | — | `python3 tools/verify_save_robustness.py [--source X.gd]` | `python3 tools/verify_save_robustness.py [--source X.gd] --json` | （lane t2）SaveLoad 守卫存在性与顺序 + 源码驱动模型跑坏档/好档/槽态 fixture + 变异自检 | `结果：全部通过`；可能有 `⚠ 未体检的强类型字段（不计失败）` | `✗` 行；`结果：N 项问题` |
| 9 | import | Godot | 必跑·步骤（不判红绿） | ✓ | `godot --headless --import --path .` | `python3 tools/gate_json.py --godot import` | 刷新资源导入缓存（`.godot/`、`*.import`）；须先于 check_assets 与 Godot 门禁跑 | exit 0，只有进度条 | **无红长相**（不判红绿） |
| 10 | smoke | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/godot_smoke.gd` | `godot --quiet --headless --path . -s res://tools/godot_smoke.gd -- --json` | autoload 起得来、章节/旗标/结局按数据走、headless 零延迟旁路 | `GODOT SMOKE PASS` | `✗` 行；`GODOT SMOKE FAIL` + 复述 |
| 11 | compile | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/godot_compile_check.gd` | `godot --quiet --headless --path . -s res://tools/godot_compile_check.gd -- --json` | 清单脚本 `load()` + `can_instantiate()`；场景解析（lane m2：ext_resource / 子资源 / 脚本坏）；守护清单 | `COMPILE_CHECK SUMMARY bad=0/N` | `COMPILE_CHECK FAIL …` 行；`bad=k/N` |
| 12 | story | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/godot_story_check.gd` | `godot --quiet --headless --path . -s res://tools/godot_story_check.gd -- --json` | 新闻按月投放不重复、1268 身份结算恰一次、存档 round-trip、真机抵港路由；（lane w19-g11）运行中出 SCRIPT ERROR（含 Parse Error / Compile Error）即判红，原先依赖脚本解析失败、断言整段跳过也退 0 | `STORY_CHECK SUMMARY fails=0`（前一行 `STORY_CHECK OK   运行中无 SCRIPT ERROR / Parse Error（0 条）`） | `STORY_CHECK FAIL …`（含 `运行中无 SCRIPT ERROR / Parse Error（N 条，首条：…）`）；`fails=k` |
| 13 | p7 | Godot | 必跑 | ✓ | `godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd` | `godot --quiet --headless --path . -s res://tools/p7_guild_exam_smoke.gd -- --json` | 行会入行 / 行情抄本条数 / 贡院赴试 / 誊录：扣费门槛、商誉 3 / 5 条、每章一次、跨月结算时序 | `P7_GUILD_EXAM_SMOKE_OK` | `FAIL …` 行；`P7_GUILD_EXAM_SMOKE_FAIL k` |
| 14 | patrol | Godot | 必跑 | ✓ | `DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/patrol_shell.gd -- --json` | 挂主场景走开局、三港、九设施、海图：1280×720 按钮不越界、焦点色、航向牌、终局港口页；截图旁证一色判据（lane pg，一色只记 ⚠）；（lane w20-a2，g1 遗留② / g13 遗留④）白刃两条窗口支路：末艘「夺船」题签按游戏时停满 T_HOLD 八成（相位判据）、出战墨边写「・夺船」；白刃失利支「脱钩」题签同判据、不收战、不出墨边（不再用 0.44 s 墙钟边界） | `PATROL SHELL PASS`（前一行 `✓ 截图旁证 n/n 张非一色`） | `✗` 行；`PATROL SHELL FAIL` + 复述 |
| 15 | 截图门禁（25 支，见下表） | 截图 | 加跑：动画面 / UI / 过场 | — | `NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --path . -s res://tools/<探针>.gd` | `NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --quiet --path . -s res://tools/<探针>.gd -- --json` | （lane m3 立、sg2 扩到全部截图脚本，新截图脚本一律接它）`tools/shot_gate.gd`：零截图 / 空视口 / 一色空图 / 张数不足一律红；契约模式须显式 `-- --contract` | `<TAG>_OK shots=n/n -> 目录`；契约模式 `<TAG>_CONTRACT_OK…` | `✗ …` + `<TAG>_FAIL k（shots=…）`；headless 下 `<TAG>_FAIL headless（…不是画面回归）` |
| 16 | save_robust_probe | Godot | 加跑：动 SaveLoad / 存档 | — | `godot --headless --path . -s res://tools/save_robust_probe.gd` | `python3 tools/gate_json.py --godot save_robust_probe` | （lane h1h2 / rt）坏分区退 .bak、只剩 .bak 取标签、两份皆坏不抛错 | `SAVE_ROBUST_PROBE PASS`（大量 `ERROR: 存档结构异常…` 是故意喂坏档，属预期） | `✗` 行 / 非零退出；输出含 `SCRIPT ERROR` 即算失败 |
| 17 | check_sidecars | Python | 加跑：提交新 .gd / .gdshader / 素材，或挪删它们（同车规则：新源文件的侧车同 commit 带上） | — | `python3 tools/check_sidecars.py` | `python3 tools/check_sidecars.py --json` | （lane ag / ag2）按 git 索引：已跟踪 .gd/.gdshader 须有已跟踪 `.uid`，可导入素材须有 `.import`；反向不许只提侧车 / 多余侧车；侧车内容与源文件、场景引用、VRAM 基线一致，uid 唯一；工作树里已跟踪侧车不许漂移。口径表见 docs/侧车口径.md | `结果：全部通过` | `FAIL: …` 行（缺侧车 / 孤儿·多余侧车 / 内容漂移 / 非基线形态 / 工作树漂移）；`结果：N 项失败` |
| 18 | save_migrate_probe | Godot | 加跑：动存档结构 / save_schema | — | `godot --headless --path . -s res://tools/save_migrate_probe.gd` | `python3 tools/gate_json.py --godot save_migrate_probe` | （lane sv / fx6）老档沿迁移链逐级升到本版（`SaveLoad.SAVE_SCHEMA`，现为 3：v1→v2→v3）：v1 老档读入补字段、回写本版、原件留 .v1；v2 档（无 `state.met_ids`）按雇用记录 / 在船职事 / 守城见林华回填人物志「已识」、推不出留空、回写本版、原件留 .v2；未来档明确拒读、不退副抄、文件不动 | `SAVE_MIGRATE_PROBE PASS` | `✗` 行；`SAVE_MIGRATE_PROBE FAIL fails=k`；输出含 `SCRIPT ERROR` 即算失败 |
| 19 | gates_md | Python | 加跑：动门禁清单 / docs/GATES.md，或改 README「验证」段的道数句 | — | `python3 tools/gates_md.py` | `python3 tools/gates_md.py --json` | （lane gd3 / gd4 / gd5；gd5 加 §二 批量巡检块、`.claude/todo.md` 验证段；w20-b3 加一键跑把关与 README 道数对账）本注册表 vs docs/GATES.md §一、§二批量巡检、§四三个生成块逐字一致；注册的脚本都在；接 shot_gate 收尾截图的脚本全部入册、接 shot_gate 的脚本都挂压帧 `ShotGate.frame_pressure`（lane gd18）；附属自检的开关还在源码里；§三 小节编号对得上；§三 与 todo.md 验证段的一键跑命令与必跑档逐条同序；一键跑把关（w20-b3，判据自检见附属「三之一」）：两处一键跑命令段不许带关断开关 / `--help` / `--dry-run`、必跑档不许缺席、条数不许不符，README「下面 N 道」的道数与注册表一键跑条数对得上 | `结果：全部通过` | `✗` 行（附首处差异）；`结果：N 项问题`；修法 `python3 tools/gates_md.py --write` |
| 20 | RefsMacPath | Python | 必跑 | ✓ | `python3 tools/check_mac_paths.py` | `python3 tools/check_mac_paths.py --json` | （lane doc9）git 已跟踪的文本文件里不许写 Mac / Homebrew 专属绝对路径（Mac 家目录、Homebrew 前缀、Godot 应用包、用户资料库目录等 10 条，模式与理由见脚本 `PATTERNS`；lane cs20 起每行另把字面量 / 家目录之间的拼接折成一段再对，与 RefsHostPath 共用 `tools/path_scan.py`；lane gd21 起脚本自身也扫，只按行排除 `PATTERNS` / `SAMPLES` 块的条目行，块里夹了别的行即判红）；每次先跑「零、模式自检」（lane auditfix2）：`SAMPLES` 正向样本（含独立审计原反例两行）须全认出、`CLEAN` 反向样本须全不命中；已定级的留档进白名单 `ALLOW`：按文件登记命中行数、头部横幅 / 回指注字样与理由，行数不符、字样丢了、条目失效都判红；未跟踪文件只记 `⚠` | `白名单外 0 处命中（扫 N 个已跟踪文本文件，含本脚本、其 PATTERNS / SAMPLES 块除外）` + `结果：全部通过` | `✗` 行（白名单外命中逐行列 `文件:行 … ← 命中串`；白名单文件行数不符；横幅 / 回指注丢了；失效条目；本脚本 PATTERNS / SAMPLES 块形状不对；零节样本漏认 / 误报）；`结果：N 项问题` |
| 21 | RefsHostPath | Python | 必跑 | ✓ | `python3 tools/check_host_paths.py` | `python3 tools/check_host_paths.py --json` | （lane gd22）git 已跟踪的文本文件里不许写本机 Linux 绝对路径：`/home/<用户>` 与 `/workspace/<目录>`（仓库根本身一律红，命令写 `--path .`）；仓外根登记在脚本 `ROOTS`（截图根 `NK1_SHOT_DIR`、简报目录 `NK1_BRIEFS` 两条）：文档 / 注释（lane cs20 起按注释起点切行，行尾注释也算）里随便写，代码段只许 owner 写一次默认值（字面量拼接折成一段再判，与 RefsMacPath 共用 `tools/path_scan.py`），owner 丢了默认值或环境变量名判失效；每次先跑「零、样本自检」（lane cs21）：`SAMPLES` 正向样本（含 gd22 清掉的原文三行、cs20 的拼接写法）在 .gd 代码段 / 注释行 / .md 三处须全判红、`CLEAN` 反向样本三处须全不判红、`ROOTS` 每条按 owner 代码行 / 非 owner 代码行 / 拼接 / 行尾注释 / .py 文档串 / .md 各判一次；本脚本自身也扫（只放过 `ROOTS` 登记行，按行排除 `SAMPLES` 块，块形状不对即判红），未跟踪文件只记 `⚠` | `登记外 0 处命中（扫 N 个已跟踪文本文件，含本脚本、其 SAMPLES 块除外）` + `结果：全部通过` | `✗` 行（逐行列 `文件:行 … ← 命中串`；非 owner 代码行写死仓外根另注；ROOTS 条目失效；本脚本 SAMPLES 块形状不对；零节样本漏判 / 误报、owner 口径不对）；`结果：N 项问题` |
| 22 | check_decision_refs | Python | 必跑 | ✓ | `python3 tools/check_decision_refs.py` | `python3 tools/check_decision_refs.py --json` | （lane dec3 / dec4）`docs/待策划拍板清单_2026-09-28.md` 反引号里的每处「文件:行」：文件在、行号不越界、指的还是清单头部锚（「行号：……按 HEAD `x`」）那个提交里的同一段内容；挪了位的按 diff / 同文件原文 / 函数名（照 main_splits 改名表进拆出件）/ 跨文件原文四层算出新号；清单里不许留 `--fix` 打的「〔跟号待核：…〕」；改号自证：和上一版清单逐对比「旧锚旧号那段 == 本版锚本版号那段」，旧那段原文还在别处即号写歪了（lane auditfix1）；仓外 brief 引用只查越界（`$NK1_BRIEFS` 不在只记 `⚠`）；落点所在函数只剩一行转发（func_body.forward_of）的穿透到真体再跟号，穿透不下去报「跟到一行转发」，每次先跑内存里的「转发穿透自检」10 形（lane auditfix6）；输出确定序（lane cs23）：逐处的 ⚠ / ✗ 行先收齐、按「清单行号 → 行内第几处引用 → 类别」排好再印，`--since` / 改号自证的新旧配对也按新版引用的清单顺序逐对比——原先配对取 `ko.keys() & kn.keys()`（集合，遍历顺序随 PYTHONHASHSEED 变），有 2 处以上 ⚠ / MISMATCH 时同基连跑每次行序不同、「逐字节同」比对偶发假 DIFF（lane cs18 待议 4） | `✓ 转发穿透自检 10/10（…）` + `✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异…都落得上（…）；…`（lane w19-g8，SUBCHECKS）+ `锚 X：引用 N 处（…）…；NOFILE/OOR 0，DRIFT 0（…），待核标记 0` + `改号自证 […]…MISMATCH 0…` + `结果：全部通过`（`⚠ 改指未验` 不判红）。同一基连跑 5 次 stdout 逐字节同（lane cs23 实测：六个历史基 × 默认 / `--show`、5 个 `--since` 旧版与号写歪的脏树各 5 次同 md5）；lane cs25 起由 ledger_refs_mutants 二节固化（5 个固定种子、去掉排序须判不确定） | `✗ NOFILE` / `✗ OOR` / `✗ DRIFT L行 文件:行：…可跟号 → :新号（凭什么）` 或 `…跟不上，要人工：…` / `✗ 待核 L行` / `✗ MISMATCH L行 …旧锚那段原文在 X 里还在 文件:行——行号改歪了？`；`…可跟号 → 文件:新号（穿透一行转发 …）` / `…跟不上，要人工：跟到一行转发：…` / `✗ 转发穿透自检 S… 期望 … 实得 …`（脚本自身坏了）；`✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——…`（变异靶子漂了，lane w19-g8，见 SUBCHECKS）；`结果：有问题（DRIFT 先跑 --fix 自动跟号…）`；修法 `python3 tools/check_decision_refs.py --fix`（所引文件先提交） |
| 23 | check_symbols_mutants | Python | 加跑：① 动 check_symbols 十三节的护栏（_node_block 记账 / NAMED_FUNCS 按 (文件, 名字) 认 / 自扫形状 / NF 标注）、它们守的反向断言或判词，或动 tools/check_symbols_mutants.py / tools/func_body.py；② 动了变异的靶子：船屋 `_setup_shipyard`（Main.gd / ShipyardPage.gd，拆 Main 挪走它或改转发）、Main.tscn 的 CenterArea 节点、GameManager / Calendar 的 advance_days、船屋两行反向断言；③ 一键跑 check_symbols 十四节「落点预检」红了——改完 CASES 必跑一次全量 | — | `python3 tools/check_symbols_mutants.py` | `python3 tools/check_symbols_mutants.py --json` | （lane auditfix3）check_symbols 反向断言空转的变异对照：当前工作树检出到临时 worktree，逐格施变异、跑整道 check_symbols 比 rc 与 `  ✗` 行。_node_block 一支（「底图 / 外层横排 / 中区开场不收起」+ 全仓改名 CenterArea、只漏这条反向断言、再收起中区）与 NAMED_FUNCS 一支（船屋 `"advance_days" not in yard_fn` + 改名 GameManager.advance_days、只修弹红的正向断言、再让船屋推一天）各五格；护栏退回旧口径（cs12 前不记账 / cs11 前 scripts/ 下有定义就算）那格须 rc=0、现行须 rc=1 且只有护栏那一行红；另两格守自扫收分支形反向断言。lane auditfix5 加：F2c / F3c（F2 之后按红字把 advance_days 改登到 Calendar.gd 下：现行 NF 标注不符一行红 / 不查标注 rc=0）；S0–S9 分支形七形（条件折多行 / else 支 / ✗ 不在紧下一行 / match / match 守卫 / 折行 any / 探查函数与正则当条件）逐形漏登判红、退回 auditfix3 口径（单行条件 + 下一行 ✗）rc=0；T1–T6 NF 标注（同名多处没标 / 日后出现同名 / 接收者认不出 / 标错行） | 「零、靶子定位自检」K0–K10 11 格 `✓`（lane cs24：插行变异顺一行转发找真身）+ `✓ B0 …` 起 31 格逐格 `✓ <编号> … rc=N` + 「二、空转对照」7 条 `✓ … 旧口径 rc=0 → … 现行 rc=1` + 「三、靶子落点」+ `结果：全部通过`。`--landing` 只跑落点预检（= check_symbols 十四节，约 0.5 s）：`✓ check_symbols_mutants 落点预检：K0–K10 11 格判对；31 格变异在当前源码上都落得上（…）` + `结果：全部通过` | `✗ <编号> …：期望 rc=a，实得 rc=b` 附 `缺 ✗ …` / `多 ✗ …`；`变异没落上` = 源码改了、这支变异的替换处数不对 / 插行靶子找不到真身（同名多处、转发目标认不出文件）；`✗ K<n>` 靶子定位判据变了；空转对照 `应 0 → 1`；`结果：N 项问题`；无 git（不在仓库 / PATH 里没有）/ 建不了 worktree 退 2；`--landing`：`✗ check_symbols_mutants 落点预检 · <编号> …：变异没落上——…` 退 1 |
| 24 | check_data_family | Python | 加跑：动 data/ 下同族文件（scenes.json / ports.json / port_beats.json）的条目 / 字段 / 引用，新增 data/*.json，或动 tools/data_family.json | — | `python3 tools/check_data_family.py` | `python3 tools/check_data_family.py --json` | （lane seq4 / seq6）普查 data/*.json：F1 带唯一字符串 id 的条目表 + F2 字段指回同表 id（过半）+ F3 scripts/ scenes/ 的代码读它（seq6：# 注释不算、cutscenes.json 不算 scenes.json）的候选，须登在清单 families（同族）或 not_family（写明图为何无入口）；候补 watch（seq6）按登记的 key 判 F1 / F2 须仍成立，F3 一成立即红（w20-c2：port_beats.json 已按 E-10 接回运行时、升入 families，watch 现空）；对每个同族文件跑四项：一、字段齐备 / 类型（按形查必填、类型、未登记字段，嵌套列表再查一层；scenes 的形也是 verify_story_data 的形状表，单一来源）；二、引用 id 存在（refs 每一路落在本表 / 别的数据文件 / GDScript 常量的并集）；二之一、无向图的单向登记须全在 one_way_ok 基线（seq6，只减不增）；三、普查出的自引用路径（过半与部分命中）都登了 refs 或 not_edges；四、从 roots 沿 edge 走不到的条目 = 孤儿（形上 orphan_ok 与 known_orphans 基线放过，基线登了却已可达 / 已删即红）；每次先跑「零、变异自检」（GATES §五.3；内存里改：同族删必填 / 删边字段 / 改类型 / 悬空 / 拼错字段 / 孤儿 / 新添指回本表的字段 / 基线失效 / 入口与常量改名 / 部分命中漏登 / 单向登记新添与补齐 / 漏登 / 只剩注释读它 / 候补接回运行时须红且只红在该文件，非族 goods / characters / crew 改了须与基线一致；w20-c2：格数随 families 与清单 mutant_skip 走，port_beats 按 entry 成账、可达针不带回指，形状格登记跳过）；seq6 起锚按形状挑（兜底形、可达、边字段非空的第一条），常量 / 入口名读清单，id 改名自己跟上，挑不到即红「锚落不上」（清单 mutant_skip 登记跳过的格除外，须写明为什么这种形状在本表不存在）；`--mutants` 逐格打印）；scenes 的孤儿基线与 lane seq3 共用 verify_story_data.SCENE_ARCHIVE | `✓ N 格全对：…` + `== <文件>` 下逐项 `✓ 一、…` 至 `✓ 四、…`（四：`可达 a / n；不可达 k = 形放过 x + 已登记基线 y`）+ `结果：全部通过` | `✗ …` 行（`缺必填字段` / `类型应为` / `未登记字段` / `悬空` / `是孤儿` / `known_orphans 登了 X，它已从入口可达` / `满足 F1–F3…却没登记` / `X→Y 单向登记` / `基线里的 X→Y 已不是单向` / `（未过半…）…却没登 refs` / `已被运行时读…登进 families` / `✗ 变异自检 <编号> …`，其中 `锚落不上：…` = 数据里已没有那种形状的条目、照提示改挑选条件）；`结果：N 项问题` |
| 25 | probe_pressure | Python | 加跑：改了探针集里的 .gd（tools/ 下代码行调 `ShotGate.frame_pressure` 的），或 tools/probe_clock.gd / shot_gate.gd / combat_probe_stage.gd | — | `DISPLAY=:2 python3 tools/probe_pressure.py [--only a,b] [--levels 0,300] [--mutants]` | `DISPLAY=:2 python3 tools/probe_pressure.py [--only a,b] [--levels 0,300] [--mutants] --json` | （lane gd25）有窗口探针（代码行调了 `ShotGate.frame_pressure` 的已跟踪 .gd，截图册 + 定向探针）各在两档 `NK1_PROBE_SLOW_MS`（默认 0 不封顶 / 300 封顶）下跑 `-- --json`，结论（exit_code / error / SCRIPT ERROR / 逐条 checks，名字里的 ms·s·帧读数掩掉）须全同且绿；每跑各给空 XDG_DATA_HOME。每次先跑「零、判据自检」样本；`--mutants` 在临时 worktree 把两支探针的完成判据改回固定帧数，须判不一致。像素不比，归 `tools/shot_consistency.gd`（结尾印出交接命令） | 逐支 `✓ <探针>：两档一致绿——档 0：绿 n/n（s） ｜ 档 300：绿 n/n（s）` + `共 N 支：一致绿 N / …` + `结果：全部通过` | `✗ <探针>：两档结论不同——…` 附 `rc：档 0 = … · 档 300 = …` / `只在档 X：✗ …`；`✗ …：两档同红`（探针自身红）；`✗ …：跑不成`（没 JSON 行 / 超时）；`--mutants`：`✗ B0 …` 基线不绿 / `✗ M<k> …——期望「两档结论不同」` / `变异没落上`；`结果：N 项问题`；找不到 godot / 参数错退 2 |
| 26 | ledger_refs_mutants | Python | 加跑：① 动 tools/gen_main_splits.py（台账格式硬校验 / 函数表对账）或 tools/check_decision_refs.py（逐处行的排序 / since 配对）或 tools/ledger_refs_mutants.py；② 动了变异的靶子：台账 docs/Main拆解台账.md 已有的「已拆（前三刀…）」段、第四 / 第五 / 第十一刀节的结构（节标题形状、函数表增删行 / 行段写法；lane cs26 起变异按形状定位：日期 / 题文 / 形参名 / 说明字改了不必跑），拍板清单里 `scripts/Main.gd:N` 引用增删 / 改指；③ 一键跑 check_decision_refs「零之二、落点预检」红了——改完 M / GEN_CASES / DET_CASES 必跑一次全量 | — | `python3 tools/ledger_refs_mutants.py` | `python3 tools/ledger_refs_mutants.py --json` | （lane cs25，固化 lane cs23 的探针）当前工作树检出到临时 worktree，逐格施变异、比期望表。一、gen_main_splits 台账格式硬校验 ①–⑤：逐格改台账（节标题去反引号 / ### / 无空格 / 半角括号 / 去 lane / 箭头后多字、前三刀段半角括号 / 删一件 /「前N刀」写错 / 整段删掉、刀号重号 / 跳号 / 认不出、函数表行少空格 / ASCII 连字符 / 列两次、删光函数表），各跑对账 / `--write` / 写后对账：现行对账 rc=1 且 ✗ 行对得上、`--write` 不写盘、写后仍 rc=1；硬校验退回 cs23 前（删两处调用）同一变异 `--write` 后 rc=0（漏认、清单跟着少、gen 自己绿）；第四刀删表（M5t）现行红、`NO_TABLE_OK` 放行退回 rc=0，N1 / N2 第四、第五刀补的表漏列一支 / 行段写错各一行红；对照 C0–C2；C3 前三刀段改写成三节现行 rc=0、C3′ 刀序起点写死回第四刀 rc=1（lane cs26）。变异锚按形状定位（lane cs26）：只锚刀号与形状（「## 第N刀（」起头的标题行、那节函数表最后一支、前三刀段第一件、两支脚本里调用 / 排序的形状），期望 ✗ 字样由定位到的内容现算。二、check_decision_refs 输出确定序：PYTHONHASHSEED=0/1/2/3/42 各跑一次，D0 基线 / D1 清单前 8 处 Main.gd 号 +1 不提交 / D2 同一脏树 `--since HEAD`（lane cs26 起相对基，原钉死 ccb1d57）stdout 须逐字节同；X1 / X2 同 D1 / D2 但两处排序（Lines.flush、since 配对）都去掉，须出 ≥2 种 | `✓ C0 …` 起 40 格逐格 `✓ <编号> …：对账 rc=N，--write rc=N，写后对账 rc=N` + 二节 5 格 `✓ <编号> …：rc=N，⚠ / ✗ k 条，stdout 1 种`（X1 / X2 `5 种`） + 「三、空转对照」18 条 `✓ … 旧口径 … rc=0 → … 现行 …`（含 `✓ 刀序起点：C3′ … rc=1 → C3 … rc=0`）+ `结果：全部通过`。`--landing` 只跑落点预检（= check_decision_refs「零之二」，约 0.1 s）：`✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异…都落得上（…）` + `结果：全部通过` | `✗ <编号> …：期望对账 rc=a / 写后 rc=b，实得 …` 附 `缺 ✗ …` / `多 ✗ …` / `--write 判红却写了盘`；`✗ D<k> …：期望 rc=a、逐字节同，实得 … stdout n 种`；`变异没落上` = 按形状也定位不到（第四 / 第五 / 第十一刀节标题不止或不到一处、那节没有函数表行、前三刀段认不出、两支脚本里调用 / 排序的形状改了）、这支变异该跟着改；空转对照 `应 0 → 1` / `应 否 → 是`；`结果：N 项问题`；无 git / 建不了 worktree 退 2；`--landing`：`✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——…` / `· Z<n> …预检空转` 退 1 |
| 27 | qa_pirate_boat_probe | Godot | 加跑：动 SeaChart 敌船条目（PIRATE_ENEMY / PATROL_ENEMY）、WorldMap 的 _spawn_enemy / _board_enemy / _note_fate / _battle_exit、Fleet 的 add_ship / prize_name / display_name（夺船存名，V0928-10 拍板落地时必跑）、CombatFx.ship_sprite_path 船图契约、PirateShip / Ship 的 apply_sprite / apply_type_sprite、ShipHull3D 或 Ship.tscn / PirateShip.tscn 的 HullRig，或收 / 删 assets/ship_*.png | — | `godot --headless --path . -s res://tools/qa_pirate_boat_probe.gd` | `godot --quiet --headless --path . -s res://tools/qa_pirate_boat_probe.gd -- --json` | （lane pirate-boat-0928 立，lane w19-g3 跟现行代码、入册）真走 SeaChart 两条敌船条目 → WorldMap 开战：海寇 pirate_boat「快船」两艘、元军哨船 sea_falcon「海鹘」挂 sprite=yuan_patrol；海战船身是 ShipHull3D 的 3D 宋船视口（敌红帆我素帆），船图契约 ship_<id>.png 有就用、缺图回落（期望按图在不在现算）；停士气挂件后清零敌船水手、白刃夺下两艘：存名都是「快船」（V0928-10 待拍板，不按序号起名）、上屏 display_name 加「・甲」「・乙」、下场记 boarded、末艘以 win + boarded 收战；带海鹘与快船的船队存读档（位 93）船型原样；本进程 SCRIPT ERROR 即红。`-- --shots <目录>` 有窗口另截 5 张（不接 shot_gate） | 逐条 `  ✓ …` + `QA_PIRATE_BOAT_PROBE PASS（0 项不合；截图 0 张）` | `  ✗ …` 行（如 `夺来的船…存名沿用敌船名「快船」…得 pirate_boat / 快船・一`、`第一艘记下场 boarded…得 ["pirate_boat/struck"]`、`…船身接 3D 宋船视口…Sprite2D 没贴 3D 视口`、`本进程无 SCRIPT ERROR（1 行：…）`）；`QA_PIRATE_BOAT_PROBE FAIL（k 项不合；…）` |
| 28 | perf_baseline | Python | 加跑：动 Main.tscn / SeaChart.tscn / SeaChart.gd 航行主环 / 渲染管线（UiTheme / MapView 改动），或动 tools/perf_baseline.gd 本身 / 提高 THRESHOLDS；做帧时重测 / 复测基线时手跑 | — | `python3 tools/perf_baseline.py [--scene 场面] [--secs N]` | `python3 tools/perf_baseline.py [--scene 场面] [--secs N] --json` | （lane w20-c10 立，软档）跑 `tools/perf_baseline.gd` 取指标行，按 `THRESHOLDS`（与 docs/性能基线.md §3 同步）软档判：仅「采样帧 < 下限 / 没拿到指标行 / 有 SCRIPT ERROR」算红，超阈全 `GateReport.warn`（ok=true、rc=0）；`--selftest` 零、判据自检（伪造高 / 中档指标行各判 warn / fail、`_MM` 正则抓数对、收紧一格后中档须见 ⚠——反向变异自证）；两次跑之间阈值波动可达 30%+（8 vCPU / 20 路 lane），红绿判据只盯「跑通了」这一底线、指标交人读——本仓首份性能口径，不判「帧时快慢」 | `PERF_BASELINE PASS（0 项不合；synthe / real 帧起了 N）`；`PERF_PY：<结果>`（全部通过 / N 项未通过） | `PERF_BASELINE FAIL（…）`；`PERF_PY：N 项未通过`；`✗ real: <理由>`（采样帧不足 / 拿不到指标行 / SCRIPT ERROR） |

每轮必跑（`.claude/todo.md` 验证段）：先跑步骤 9 import（不判红绿），再跑「十道 Python + smoke/compile/story/p7/patrol」十五道门禁；8、15、16、17、18、19、23、24、25、26、27、28 按 lane 内容加跑（档列写了何时）。「一键跑」列 = §三「一键人读全跑」那段命令。

**门禁开关与附属自检**（12 项；不另立一道门禁，随所属门禁默认跑到的算进一键跑，要开关的手动开；CI 专属步骤见 §四）：

| # | 项 | 所属门禁 | 族 | 一键跑 | 命令 | 期望输出 | 失败含义 |
|---|---|---|---|---|---|---|---|
| 1 | builtin_api 头部自检 | 1. check_symbols（lane cs3） | Python | ✓ | `python3 tools/check_symbols.py` | 「二、跨文件引用检查」首行 `✓ 内置清单 tools/builtin_api.txt（godot 4.6.3…）：N 类，Object→Node 链 M 名 + 手写补充 5 名` | `✗ tools/builtin_api.txt 正文与头部 sha256 不符` / `头部缺 godot 版本 / sha256 行` / `不存在` = 清单被手改或截断；`导自 godot X，本机 godot Y` = 本机换了 Godot 版本；`extends …清单链上缺类` = autoload 基类不在导出范围（先加进 `tools/gen_builtin_list.gd` 的 CLASSES）。都计入 check_symbols 问题、退 1，修法 `--regen` |
| 2 | check_symbols --regen | 1. check_symbols（lane cs3） | Python | — | `python3 tools/check_symbols.py --regen` | `✓ --regen：ClassDB 导出与 tools/builtin_api.txt 逐字节一致，未改动`；有漂移则 `↻ --regen：已按 ClassDB 重写 tools/builtin_api.txt（+a / −b 行；请连同提交）`。之后照常跑完整道 check_symbols，退出码按整道算 | `✗ --regen：找不到 godot` / `gen_builtin_list.gd 失败（rc=…）` → 计入问题、退 1。**会改写 `tools/builtin_api.txt`**，所以不进一键跑；漂移只在 CI 步骤里配 `git diff --exit-code` 判红（见 §四） |
| 3 | check_symbols --suggest | 1. check_symbols（lane cs4） | Python | — | `python3 tools/check_symbols.py --suggest`（或 `CHECK_SYMBOLS_SUGGEST=1 python3 tools/check_symbols.py`） | 多出「二之三、字符串派发候选提示」一节（`emit_signal` / `X.call` / `call_deferred` / `callv` / `Callable(obj, …)` 字面量），没疑点时没有 `⚠ WARN` 行；不开时输出逐字节不变，开了退出码也不变 | **不判红**：`⚠ WARN <文件>:L<行> <调用>  ← <作用域>：无此 func` / `…：无此 signal` = 字面量名在对应作用域里找不到，人工判真死引用 / 误报；`--json --suggest` 里记 `level: warn`（ok=true，不计 pass/fail） |
| 4 | Main 拆出件拼回（一之零） | 1. check_symbols（lane ms / cs8 / gd16 / cs13） | Python | ✓ | `python3 tools/check_symbols.py` | 「一之零」每件 `✓ scripts/ui/<件>.gd：N 支转发拼回函数体` + `✓ 头注写「从 Main.gd 原样搬出」的 N 件与 MAIN_SPLITS 一一对上；Main 调拆出件处都是一行转发；非拆出件的一行委托 N 处都在 MAIN_NOT_SPLITS` + `✓ MAIN_NOT_SPLITS N 条都有效：文件在、Main 一行转发到它、目标函数在、注明与实际转发一致` + `✓ tools/main_splits.txt 与重算逐字节一致（N 件；…）` + `✓ godot_smoke.gd 与此同读 tools/main_splits.txt（_main_family_src → _main_splits，不自带清单）`。清单只有 `tools/main_splits.txt` 一份（lane cs13），两边都读它的第一列；**拼回只对源码字符串断言有效**：行号、`main.` 前缀、static / 实例语义不在此列（口径见 §三.1） | `✗ … 转发到 <件> 的 fn，那边没有这支 static func` = 拆出件改名 / 删了没跟转发；`登记为 Main 拆出件，但 Main 里没有一行转发` = 登记了没接；`调了拆出件 … 却不是一行转发` = 转发带行尾注释 / 两行 / 折行签名，拼回不认；`一行转发到 <件>，它没登记进 MAIN_SPLITS` / `头注写「从 Main.gd 原样搬出」，却没登记` = 新拆一刀忘登记；`登记为拆出件，头注…没写` = 约定字样丢了；`tools/main_splits.txt 第 N 行与重算不一致` = 手改了清单，或台账 / 拆出件 / Main 转发改了没 `gen_main_splits.py --write`；`台账登记的拆出件 … 文件不存在` / `登记在 tools/main_splits.txt，文件却不存在` = 删了拆出件没更新台账和清单；`godot_smoke.gd 没改成读 tools/main_splits.txt` = smoke 又自带了一份清单 / 写死了路径；`MAIN_NOT_SPLITS 条目 <件> 文件不存在` / `Main 没 preload 它或没有一行转发到它` / `转发到 <件> 的 fn，那边没有这支 func（…指向不存在的目标）` / `注明「A → B」，Main 里实际一行转发是 …` / `同时登记在 MAIN_SPLITS 与 MAIN_NOT_SPLITS` = 放行清单过时（lane gd16），删条目或改注。都计入 check_symbols 问题、退 1 |
| 5 | gen_main_splits --write | 1. check_symbols（lane cs13） | Python | — | `python3 tools/gen_main_splits.py --write`（或 `python3 tools/gen_main_splits.py`） | `✓ --write：tools/main_splits.txt 与重算逐字节一致，未改动`；有差异则 `↻ --write：已重写 tools/main_splits.txt（N 件；请连同提交）`，之后照常对账一遍、`结果：全部通过`。不带 `--write` 只对账不写盘（与 check_symbols「一之零」同一个 check()）。拆出件 / lane ← 台账节标题，拆出函数 ← Main 一行转发，commit / 原 Main 行范围 ← git（拆出 commit 父版 Main.gd），台账写了逐支行段的逐支对账；台账函数表列了的函数现 Main 须仍一行转发到本件（lane cs18），反过来那节有函数表的、现 Main 一行转发到本件的每支都须列在表里（lane cs22，有表就须列全）。另加台账格式硬校验（lane cs23 / docs/Main拆解台账.md 头注；台账写坏时原先这些形状被正则静默漏掉、重算跟着少一件 / 少一支、--write 照写、gen 自己绿）：① 标题以「第…刀」开头却不合节标题正则的行；②「已拆（前N刀…）」那段里的 `X.gd` 没按「`X.gd`（lane，…」写，或认出来的不是 N 件、N 认不出；③ 刀序（从「前N刀」的下一刀起逐刀 +1，现为第四刀；那段不在则从第一刀起——lane cs26 起起点由台账推、不再写死 3；重号 / 跳号 / 认不出的刀号）；④ 像函数表行（竖线起头、反引号里 `名字(`）却不合写法、行段写成 ASCII 连字符 / 写错、同一节同一支列两次；⑤ 拆刀节没有函数表（lane cs25 起无例外：第四、第五刀补了表、删了 `NO_TABLE_OK` 放行）。有任一条时 `--write` 也判红、不写盘；①–⑤ 的变异对照见 ledger_refs_mutants（lane cs25）。浅克隆取不到拆出 commit 父版时那一行报 `⚠ … 未验`、沿用清单原值，不判红。commit 列的 `-`：只在 HEAD 就是拆出 commit 时照认（lane auditfix1），HEAD 往前走了对账即红、`--write` 补成哈希 | `✗ --write：有问题，tools/main_splits.txt 未改动` + 各条 `✗`（台账登记的拆出件不存在、拆出件有 static func 没有 Main 转发、拆前 Main.gd 里找不到转发的 Main 函数、台账逐支行段与重算不符、台账格式硬校验 ①–⑤（`… 标题以「第…刀」开头，却不合拆刀节标题写法 …本脚本认不出这一刀、会整件漏掉` / `…「已拆（前三刀…）」那段的 X.gd 没按 …写` / `… 刀序不对：上一刀之后应是第 N 刀` / `… 的刀号认不出` / `…像函数表行、却不合…写法` / `… 的行段写法不认` / `… 函数表把 X 列了两次` / `…那节没有函数表`，lane cs23）、`<lane> 族 <件>：台账函数表列了 fn（期望拆前 Main.gd a–b 行）…没有一行转发到本件` = 挪回 Main / 改名 / 转去别件没改台账，lane cs18；`<lane> 族 <件>：现 Main.gd 的 fn 一行转发到本件 X，台账那节函数表却没列它` = 新搬一支进本件没补台账表，lane cs22）→ 退 1。**会改写 `tools/main_splits.txt`**，所以不进一键跑；新拆一刀的 lane 追加台账一节后跑它、连同提交。对账（check_symbols「一之零」）的 `✗ <件>：拆出 commit X 已不是 HEAD（其后又有 N 个提交），清单 commit 列还记 -…` = 拆分那笔之后没补哈希（lane auditfix1 前这一格放行到下一刀才补）：跑 `--write`、另提一笔，与拆分同一次落地 |
| 6 | 按函数名取函数体（十三） | 1. check_symbols（lane gd16 / cs9 / cs12 / cs11 / cs17 / gd23） | Python | ✓ | `python3 tools/check_symbols.py` | 「十三、按函数名取函数体」`✓ _func_body / func_bodies().get / _locate_func 的 N 处按名取用都取到函数体，_node_block 的 M 处按名取用都取到场景节点块`（N / M = 本脚本「行号 + 名字」去重后的取用处；_node_block 按 `[node name="X"` 取场景节点块，lane cs12 纳入同一本账）。各节按名取体一律先定位再取体（lane cs9：原先手切的 find / split / 无锚正则 / _static_body 都收进 `_locate_func`，只认行首 `[static ]func 名字(`）；取到的只是一行转发（`func X(…):\n\t_K.x(self, …)` / 原样传形参给别的函数 / 零实参调同文件另一支，判据 `func_body.forward_of(body, src)`）同样记成取不到（lane cs17 / gd23，三片口径对账见 §三 1）；本来就读转发那一行的（顺调用链展开、钉「Main 只许一行转发」）写 `.get(name, …, forward_ok=True)`。只探有没有这支函数、不想判红的写 `name in func_bodies(src)`（不记账）；本身要跑在变异源码上的契约（`_guild_remap_contract`）一律 `in` 探、缺了记成契约错误「缺 X」、只剩一行转发记成「X 只剩一行转发」，不走 .get 记账（lane cs12 / gd23）。+ `✓ 断言点名的 N 支函数都还在登记的文件里（M 个文件，按 (文件, 名字) 认；反向断言 / find 锚 / 存在性探查 / 分支形；NAMED_FUNCS 与本脚本自扫一致；同名多处定义的 K 支（…）逐行标明、与登记一致）`（lane cs9 / cs11 / auditfix5） | `✗ check_symbols.py:<行> 取函数体 <fn> 取不到（改名 / 删了 / 搬走没拼回），这处断言在空转` = 被读的函数改了名 / 删了 / 搬走没拼回，或断言里函数名写错；`✗ check_symbols.py:<行> 取函数体 <fn> 只取到一行转发（→ <目标>），真身不在这份源码里（拆走没拼回 / 该改读拆出件），这处断言在空转` = 读的那份源码里这支只剩一行转发（Main 拆走一刀、转发到没登记 / 没 preload 的件，或直读 Main.gd / 别的文件时切到转发），改读真身所在的文件（lane cs17）；`✗ check_symbols.py:<行> 取函数体 <fn> 只取到一行转发（→ <g>），真身是同一份源码里的 <g>（改名后留了别名 / 该改取 <g>），这处断言在空转` = 同文件改名后原名只剩零实参 / 原样传形参的别名，改取 <g>（lane gd23）；`✗ check_symbols.py:<行> 取场景节点块 [node name="X"] 取不到（节点改名 / 删了 / 挪进子场景）` = 同上、对象是 .tscn 节点（lane cs12）；改前这里给 `""`（手切的还会落到整份文件 / 最后一个字 / 前缀同名的别的函数），反向断言（`"X" not in body`）照样绿；`✗ 断言点名的函数 X 在 <文件> 已无定义，别处还有同名（…）` / `…（scripts/ 下也没有…）` = 反向断言 / find 锚 / 存在性探查点到的函数在登记的文件里改了名、删了或挪到别的文件（lane cs11：同名函数在别的文件还在也红），断言与 NAMED_FUNCS 跟着改；`✗ NAMED_FUNCS 登记的文件 <文件> 不存在` = 登记路径写错 / 文件挪了目录；`✗ check_symbols.py:<行> 的断言点到函数 X，没登记进 NAMED_FUNCS` = 新写这类断言没登记；`✗ check_symbols.py:<行…> 的断言点到同名多处定义的函数 X（…），字面量看不出指哪一支…` = X 在 scripts/ 下 ≥ 2 个文件有定义（Main 拆出件并回 Main），这几行没在行尾标 `# NF: 接收者.X`；`✗ …的断言标明指 <文件> 的 X，NAMED_FUNCS 却登在 <文件>…` = 错登到同名的另一支（登记跟断言读的那支走）；`✗ …的 NF 标注 … 认不出文件` / `…这一行自扫没点到 X` = 标注写错 / 标错行（lane auditfix5）。计入 check_symbols 问题、退 1 |
| 7 | check_symbols_mutants 落点预检（十四） | 1. check_symbols（lane cs27） | Python | ✓ | `python3 tools/check_symbols.py` | 「十四、」`✓ check_symbols_mutants 落点预检：K0–K10 11 格判对；31 格变异在当前源码上都落得上（插行靶子 scripts/Main.gd _setup_shipyard → …）；期望 ✗ 字样 / rc / 空转对照归全量（lane 档，docs/GATES.md §三.23）`。check_symbols_mutants（lane 档，全量要 git worktree、约一分钟）的 CASES 逐格在当前工作树上内存里施一遍（`Mem` 叠层：读主树工作树、写不落盘，不建 worktree、不跑 check_symbols，约 0.5 s），只判变异 / 旧口径补丁落不落得上（替换处数、插行靶子顺一行转发找真身）+「零、」K0–K10。起因 auditfix7 W8：aec1ea6 入库 11 分钟后 main10 拆走 `_setup_shipyard`，全量红满 60 分钟、7 笔没人跑（lane cs27，§五.5 例三）。关断开关 `--no-mutants-landing` 只给 check_symbols_mutants 在变异过的 worktree 里用（印一行 `⚠ 落点预检未跑`），一键跑命令不许带 | `✗ check_symbols_mutants 落点预检 · <编号> <说明>：变异没落上——<文件> 里 <模式> 替换了 k 处，应 n 处` / `…func X( 有 k 处，应 1 处` / `…是一行转发到 …，… 不是 preload 常量` = 变异的靶子被挪了 / 改了（拆 Main、改节点名、改船屋断言），全量跑下去这一格就是 `变异没落上`；`✗ check_symbols_mutants 落点预检 · K<n> …` = locate_body / forward_of 判据变了。修法：照新源码改 tools/check_symbols_mutants.py 的 CASES，再跑一次全量 `python3 tools/check_symbols_mutants.py`。计入 check_symbols 问题、退 1 |
| 8 | ledger_refs_mutants 落点预检（零之二） | 22. check_decision_refs（lane w19-g8） | Python | ✓ | `python3 tools/check_decision_refs.py` | 转发穿透自检之后一行 `✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异在当前台账 / 两支脚本 / 清单上都落得上（前三刀段；第十一刀 → scripts/ui/TitlePage.gd 最后一支 …；第四刀 → …；第五刀 → …；清单 Main.gd 引用 N 处）；rc / 期望 ✗ 字样 / 写盘 / 确定性 / 空转对照归全量（lane 档，docs/GATES.md §三.26）`。ledger_refs_mutants（lane 档，全量要 git worktree、约 40 s）的 GEN_CASES / DET_CASES 逐格在当前工作树上内存里施一遍（`Mem` 叠层：读主树工作树、写不落盘，不建 worktree、不跑 gen / check_decision_refs，约 0.1 s），Facts 现算一遍，只判变异 / 旧口径补丁落不落得上；另跑「零、」Z1–Z5：把真树上的靶子按合法 / 等价写法挪一下（第十一刀标题 ###、那节行段写「—」、gen 改名 `_check_first_knives`、`pairs = sorted(pairs, …)`、清单 Main.gd 引用只剩 7 处），预检须点名对应格没落上。起因同 check_symbols_mutants 十四节（auditfix7 W8，lane cs27）：lane 档的变异对照靶子被别的片挪了，全量红着没人跑。--fix 时不跑。关断开关 `--no-ledger-landing` 只给 ledger_refs_mutants 二节在变异过的 worktree 里用（印一行 `⚠ ledger_refs_mutants 落点预检未跑`，不计入 ⚠ / ✗ 条数），一键跑命令不许带 | `✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——<文件> 里「## 第十一刀（」起头的节标题有 k 处，应 1 处` / `…那节找不到带行段的函数表行` / `…替换了 k 处，应 n 处` / `…引用只有 k 处，应 ≥8` = 变异的靶子被挪了 / 换了写法（拆 Main 改台账、改 gen / 本脚本的调用或排序写法、清单引用改指），全量跑下去这一格就是 `变异没落上`；`✗ … · Z<n> …预检空转` / `…造漂移没落上` = 预检自己的判法被放宽 / 靶子已换形状。修法：照新形状改 tools/ledger_refs_mutants.py 的 M / GEN_CASES / DET_CASES（或 DRILL），再跑一次全量 `python3 tools/ledger_refs_mutants.py`。计入 check_decision_refs 问题、退 1 |
| 9 | 按函数名取函数体（十一） | 2. verify_economy（lane cs14 / cs17 / gd23） | Python | ✓ | `python3 tools/verify_economy.py` | 「十一、按函数名取函数体」`✓ _locate_func / _gd_body / _gd_fn 的 N 处按名取用都取到函数体`（N = 本脚本「行号 + 函数名」去重后的取用处）。账本与 `_locate_func` 在 `tools/func_body.py`，与 check_symbols 十三节同一份（lane cs14）；原先手切的 `src.split("func X", 1)[1].split("\nfunc ", 1)[0]`（有 / 无 `in` 守卫）与 `guild_body` 一律改走 `_locate_func`，`_gd_body` / `_gd_fn` 切法不变、取完记同一本账。取到的只是一行转发同样记成取不到（lane cs17 / gd23，判据 `func_body.forward_of(body, src)`，与 check_symbols 同一口径）；`_on_npc_bribe` 那处本来就读 Main 的转发再顺藤去 NpcPage 取真身，写 `forward_ok=True` | `✗ verify_economy.py:<行> 取函数体 <fn> 取不到（改名 / 删了 / 搬走没拼回），这处断言在空转` = 被读的函数改了名 / 删了 / 搬走（Main 拆出件没跟着改读哪份），或断言里函数名写错；改前守卫版给 `""`、`or 整份文件` 兜底，无守卫 split 按前缀认名（`X` 改成 `X_v2` 照样切到它），反向断言照样绿。`✗ verify_economy.py:<行> 取函数体 <fn> 只取到一行转发（→ <目标>），…这处断言在空转` = 直读的 Main.gd / 别的文件里这支已拆走、只剩一行转发，改读拆出件（去 `main.` 前缀）或真身所在文件（lane cs17；如 main9 把 `_setup_residence` 改读 ResidencePage.setup_residence）；`…只取到一行转发（→ <g>），真身是同一份源码里的 <g>…` = 同文件别名，改取 <g>（lane gd23）。计入 verify_economy 未通过项、退 1 |
| 10 | scenes.json 结构自证 | 6. verify_story_data（lane seq3） | Python | ✓ | `python3 tools/verify_story_data.py` | 末尾统计行 `scenes 104（结构：入口可达 N · 归档 M · deprecated K · 自证 24 类 + 形状单一来源 6 类，形状读 tools/data_family.json）`；结构没问题时本节零输出。形状（各形必填 / 可选键、列表子形、按字段名的类型）不在本脚本另写，读 `tools/data_family.json` 里 data/scenes.json 那条的 kinds / shapes，与 check_data_family 同读一份（lane seq6）；另 6 类形状自证改清单副本（删可选键 / 改必填 / 删子形键 / 同名字段类型不一 / 类型写法坏 / 缺 scenes 那条），本门禁须跟着报。每次跑先在整份 scenes.json 上判结构（形状必填 / 形状外键 / 类型与在册取值 / 引用存在 / 从真机入口走不到的非 deprecated 幕须在 `SCENE_ARCHIVE`），再拿 24 类反向变异副本（删必填、next / 调查项 id / start_scene / chapters / 港卡 / 旗标 / 货 / 发现悬空、跳 deprecated、类型错、bool 冒充 int、键拼错、枚举外、id 重复、新孤儿、归档场接回、归档名单悬空）逐类喂同一个 `scene_structure_problems`，每类须报出指定字样；每格的锚不写死幕 id，按清单形状从现数据里挑头一条合条件的幕 / 选项 / 章（如主锚 = 兜底形、非 deprecated、不在归档、从入口可达、choices[0] 指向非 deprecated 幕），幕改名自己跟上，悬空名现造不撞现有 id（lane w19-g7）；`--anchors` 逐格打印本次挑到的锚与须报字样 | `FAIL: scenes.json <幕>… 缺必填字段 / 有形状外的字段 / 类型应为 / 不在册 / 悬空 / 没人写 / 是孤儿 / 却已接回入口` = 数据结构坏了（修数据，或新字段 / 新形状先登记进 tools/data_family.json 的 scenes kinds / shapes）；`FAIL: tools/data_family.json …读不了 / 没有 data/scenes.json 那条 / 类型写法 … 认不出 / 同名字段 … 各形类型不一` 与 `FAIL: scenes 形状单一来源自证：「X」…` = 形状清单坏了或本门禁又不读它了（lane seq6）；`FAIL: SCENE_ARCHIVE 只许减不许增` = 有人把新孤儿塞进归档名单（接入口，别登记）；`FAIL: scenes.json 结构门禁自证：「X」后没报出…` = 某类检查失明；`…「X」锚落不上：…找不到「<挑选条件>」…` = 数据里已没有这种形状的条目（照新数据改 _SV_MUTANTS 这一格的挑选条件，不许删格）；`…锚挑到了、变异却套不上` = 挑选条件与变异手法不一致（lane w19-g7）。都计入 verify_story_data 失败、退 1 |
| 11 | 一键跑把关判据自检（三之一） | 19. gates_md（lane w20-b3） | Python | — | `python3 tools/gates_md.py` | 「三之一、一键跑把关判据自检」4 条 `✓`（两枚关断开关字样从两支变异脚本 import 现读得到；4 枚禁带字样逐个注入内存命令段都判红；删一条 / 多一条必跑档分别红「缺席」「道数不符」）。起因 g8 W1：一键跑段 / todo 验证段被塞 `--no-ledger-landing` 后 check_symbols / check_decision_refs 全 rc=0，只有逐条字符串比对红——准入判据 ① 一键跑两处命令段不许带 LANDING_OFF 关断开关 / `--help` / `--dry-run`（开关样值从 check_symbols_mutants / ledger_refs_mutants 的 LANDING_OFF 常量现读，不在本表另抄）；② 必跑档条目不许在一键跑里缺席（红因点名是谁）；③ 命令条数与必跑档条数必须相符；④ README「一次改动闭环 = 下面 N 道」的道数与注册表一键跑条数对账。与逐条比对互补、随 gates_md 每次跑（lane 档，与逐条比对同寿命） | `✗ §三 一键跑 / .claude/todo.md 验证段出现禁带字样 --…：…只许 … 在变异 worktree 里带` = 一键跑被塞了关断开关，落点预检被关掉、其余门禁照样 0（g8 W1 误绿点）；`✗ …缺席必跑档 N 条（…）` = 必跑档在一键跑里漏跑；`✗ …命令 N 条，必跑档 M 条——道数不符` = 多出来的行没人认 / 必跑漏跑；`✗ README 道数（…）与注册表一键跑条数（…）不符` = README「N 道」写漂移了；`✗ 两枚关断开关字样…import 现读得到（LANDING_OFF 常量改名 / 挪走了）` = 开关常量改名，本判据靶子要跟 |
| 12 | compile 清单自检（inventory） | 11. compile（lane ea4） | Godot | ✓ | `godot --headless --path . -s res://tools/godot_compile_check.gd` | `COMPILE_CHECK OK   inventory SCRIPTS == tracked *.gd under scripts/tools (exempt N)` | `COMPILE_CHECK FAIL inventory <原因> …`（原因 `unlisted` / `listed-missing` / `dup` / `exempt-stale` / `exempt-but-listed`） = `git ls-files` 里已跟踪的 `.gd` 没进 `SCRIPTS`（或 `INVENTORY_EXEMPT` 没写理由）、清单路径不存在 / 重复 / 豁免失效，整体计 bad+1；`COMPILE_CHECK NOTE inventory git ls-files unavailable` = 没 git，退回扫盘（warn，不判红） |

**截图门禁明细**（接 `tools/shot_gate.gd` 的全部 25 支；TAG / 张数 / 截图目录现读脚本源码。headless 只验契约：本地命令换 `--headless` 并加 `-- --contract`，`--json` 写 `godot --headless --quiet --path . -s res://tools/<探针>.gd -- --contract --json`）。「截图目录」列是不设 `NK1_SHOT_DIR` 时的默认（根 `/workspace/nk1-qa-shots`，只在刷新共享证据图时用）；**worktree / 自测推荐一律加前缀 `NK1_SHOT_DIR=/tmp/<lane>/shots`**，全部探针改落 `<该目录>/<子目录>`、patrol 旁证落 `<该目录>/patrol`，默认目录不动；`CutscenePreview --snap` 存图缺省 `/tmp` → `<该目录>/cutscene-preview`（`--snapdir` 仍优先）；`tools/art/tour.sh` 巡检截帧缺省 `~/tmp/nk1-art-work/tour` → `<该目录>/tour`（`-o` 仍优先）：

| # | 探针 | 接入 | TAG | 张数 | 截图目录（默认） | 本地命令 | `--json` |
|---|---|---|---|---|---|---|---|
| 1 | vision_stage_probe | m3 | `VISION_STAGE_PROBE` | 2 | `/workspace/nk1-qa-shots/vision` | `DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/vision_stage_probe.gd -- --json` |
| 2 | vision_letterbox_probe | m3 | `VISION_LETTERBOX_PROBE` | 7 | `/workspace/nk1-qa-shots/vision` | `DISPLAY=:2 godot --path . -s res://tools/vision_letterbox_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/vision_letterbox_probe.gd -- --json` |
| 3 | qa_p7_screenshots | m3 | `QA_P7_SHOTS` | 8 | `/workspace/nk1-qa-shots/polish` | `DISPLAY=:2 godot --path . -s res://tools/qa_p7_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_p7_screenshots.gd -- --json` |
| 4 | combat_vfx_probe | sg2 | `COMBAT_VFX_PROBE` | 4 | `/workspace/nk1-qa-shots/combat` | `DISPLAY=:2 godot --path . -s res://tools/combat_vfx_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/combat_vfx_probe.gd -- --json` |
| 5 | ship_vfx_probe | ship-vfx | `SHIP_VFX_PROBE` | 6 | `/workspace/nk1-qa-shots/ship-vfx` | `DISPLAY=:2 godot --path . -s res://tools/ship_vfx_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/ship_vfx_probe.gd -- --json` |
| 6 | combat_wire_probe | sg2 | `COMBAT_WIRE_PROBE` | 4 | `/workspace/nk1-qa-shots/combat` | `DISPLAY=:2 godot --path . -s res://tools/combat_wire_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/combat_wire_probe.gd -- --json` |
| 7 | qa_companion_preview_screenshots | sg2 | `QA_COMPANION` | 4 | `/workspace/nk1-qa-shots/companions` | `DISPLAY=:2 godot --path . -s res://tools/qa_companion_preview_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_companion_preview_screenshots.gd -- --json` |
| 8 | qa_ending_reread_probe | sg2 | `QA_ENDING` | 6 | `/workspace/nk1-qa-shots/ending` | `DISPLAY=:2 godot --path . -s res://tools/qa_ending_reread_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_ending_reread_probe.gd -- --json` |
| 9 | qa_chart_hud_screenshots | sg2 | `QA_CHART_HUD` | 5 | `/workspace/nk1-qa-shots/chart` | `DISPLAY=:2 godot --path . -s res://tools/qa_chart_hud_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chart_hud_screenshots.gd -- --json` |
| 10 | qa_wire_vision_screenshots | sg2 | `QA_WIRE_VISION` | 2 | `/workspace/nk1-qa-shots/wire` | `DISPLAY=:2 godot --path . -s res://tools/qa_wire_vision_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_wire_vision_screenshots.gd -- --json` |
| 11 | qa_chars_wire_screenshots | sg2 | `QA_CHARS_WIRE` | 4 | `/workspace/nk1-qa-shots/chars` | `DISPLAY=:2 godot --path . -s res://tools/qa_chars_wire_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chars_wire_screenshots.gd -- --json` |
| 12 | qa_title_probe | sg2 | `QA_TITLE` | 5 | `/workspace/nk1-qa-shots/title` | `DISPLAY=:2 godot --path . -s res://tools/qa_title_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_title_probe.gd -- --json` |
| 13 | qa_port_doors_probe | sg2 | `QA_PORT_DOORS` | 5 | `/workspace/nk1-qa-shots/port-doors` | `DISPLAY=:2 godot --path . -s res://tools/qa_port_doors_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_port_doors_probe.gd -- --json` |
| 14 | qa_drydock_probe | sg2 | `QA_DRYDOCK` | 9 | `/workspace/nk1-qa-shots/drydock` | `DISPLAY=:2 godot --path . -s res://tools/qa_drydock_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_drydock_probe.gd -- --json` |
| 15 | qa_siege_endgame_probe | sg2 | `QA_SIEGE` | 8 | `/workspace/nk1-qa-shots/siege` | `DISPLAY=:2 godot --path . -s res://tools/qa_siege_endgame_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_siege_endgame_probe.gd -- --json` |
| 16 | qa_letterbox_copy_probe | sg2 | `QA_LETTERBOX_COPY` | 4 | `/workspace/nk1-qa-shots/letterbox` | `DISPLAY=:2 godot --path . -s res://tools/qa_letterbox_copy_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_letterbox_copy_probe.gd -- --json` |
| 17 | qa_patrol_pack_screenshots | sg2 | `QA_PATROL_PACK` | 11 | `/workspace/nk1-qa-shots/patrol-pack` | `DISPLAY=:2 godot --path . -s res://tools/qa_patrol_pack_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_patrol_pack_screenshots.gd -- --json` |
| 18 | qa_tavern_news_wall_screenshots | sg2 | `QA_TAVERN_NEWS_WALL` | 2 | `/workspace/nk1-qa-shots/tavern` | `DISPLAY=:2 godot --path . -s res://tools/qa_tavern_news_wall_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_tavern_news_wall_screenshots.gd -- --json` |
| 19 | qa_chapter_promote_probe | sg2 | `QA_CHAPTER` | 4 | `/workspace/nk1-qa-shots/chapter` | `DISPLAY=:2 godot --path . -s res://tools/qa_chapter_promote_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chapter_promote_probe.gd -- --json` |
| 20 | qa_voyage_status_probe | sg2 | `QA_VOYAGE` | 6 | `/workspace/nk1-qa-shots/voyage` | `DISPLAY=:2 godot --path . -s res://tools/qa_voyage_status_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_voyage_status_probe.gd -- --json` |
| 21 | qa_crew_hire_probe | sg2 | `QA_CREW_HIRE` | 6 | `/workspace/nk1-qa-shots/crew` | `DISPLAY=:2 godot --path . -s res://tools/qa_crew_hire_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_crew_hire_probe.gd -- --json` |
| 22 | qa_discovery_probe | sg2 | `QA_DISCOVERY` | 5 | `/workspace/nk1-qa-shots/discovery` | `DISPLAY=:2 godot --path . -s res://tools/qa_discovery_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_discovery_probe.gd -- --json` |
| 23 | qa_chars_screenshots | sg2 | `QA_CHARS_SHOTS` | 10 | `/workspace/nk1-qa-shots/chars` | `DISPLAY=:2 godot --path . -s res://tools/qa_chars_screenshots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_chars_screenshots.gd -- --json` |
| 24 | vision_fill_shots | sg2 | `vision_fill_shots` | 4 | `/workspace/nk1-qa-shots/vision-fill` | `DISPLAY=:2 godot --path . -s res://tools/art/vision_fill_shots.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/art/vision_fill_shots.gd -- --json` |
| 25 | qa_market_panel_probe | aa | `QA_MARKET` | 5 | `/workspace/nk1-qa-shots/market` | `DISPLAY=:2 godot --path . -s res://tools/qa_market_panel_probe.gd` | `DISPLAY=:2 godot --quiet --path . -s res://tools/qa_market_panel_probe.gd -- --json` |

**不算门禁**（别拿来判红绿；想跑照样可以，`--json` 也能用）：

| 脚本 | 本地命令 | `--json` | 为什么不算 |
|---|---|---|---|
| `tools/legacy/verify_narrative.py` | `timeout 60 python3 tools/legacy/verify_narrative.py` | `python3 tools/gate_json.py tools/legacy/verify_narrative.py` | （lane gd2 挪入 legacy）绑定云端 21ce 未收的 P7 平行实现（`borrow_ceiling` / `_discovery_extra` / `seen_scenes` 主干从未有；开局链截断 monk、删 `chapter` 臂与主干设计相反），合并台账第 14 行即定「留档不入门禁」；主干上恒红 23 项属预期，仍成立的「效果键必须接住」由 verify_story_data 覆盖 |
| `tools/legacy/p7_smoke.gd` | `timeout 60 godot --headless --path . -s res://tools/legacy/p7_smoke.gd` | `python3 tools/gate_json.py --godot p7_smoke` | （lane gd8 挪入 legacy）与 verify_narrative 同源，绑定 21ce 未收的 P7 平行实现（开局链进泉州、港口节拍、`seen_scenes`、`borrow_ceiling`），合并台账第 14 行定「留档不入门禁」；主干上 4 项 FAIL 后在 `borrow_ceiling()` 处 SCRIPT ERROR、不 quit 挂死（干净 worktree 同，lane l1 已记；lane gd9 起 legacy 条目强制超时 60 秒，到点 rc=124 判红）；P7 行会 / 贡院由 p7（`p7_guild_exam_smoke.gd`）接管 |
| `tools/art/tour.sh` | `timeout 900 env NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 tools/art/tour.sh -r <运行副本> [站点…]` | `NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 python3 tools/gate_json.py -- tools/art/tour.sh -r <运行副本> [站点…]` | （lane gd13 判不进）美术巡检截帧，产物是给人看的 sheet.jpg：每站一个带窗口 Godot（Movie Maker，不能 `--headless`），全集 21 站实测 348 秒（8 核、负载 8–11；单站 title 17 秒），另要先 `git archive` 出运行副本并导入一次（12 秒）；只判引擎退出码 / TOUR_READY / 报错计数 / 帧与小样在不在，不看像素——画面回归由截图门禁 25 支探针判。动 ShotTour / tour_sheet / 过场站点时手跑。输出契约：逐站 `✓` / `✗ …  ← 红因` 一行，末行 `TOUR PASS n/n` / `TOUR FAIL k/n`，退出码 0 全绿 / 1 有站红 / 2 用法错 · 运行副本不在 · 找不到引擎；`--json` 外包后 checks 逐站一条，强制超时 900 秒 |
| 其余 `tools/qa_*_probe.gd` / `*_probe.gd` 专项探针（未接 shot_gate 的） | 见各脚本头注释 | — | 各 lane 的专项探针，只在对应 lane 里跑；要升格为门禁就进 `tools/gate_json.py` 注册表 |
<!-- GATES:END -->

## 二、`--json` 机读输出

### 怎么开

```sh
# Python 门禁：直接加开关（1–8、17、19–26 都有）
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
- 用 `check(cond, msg)` 的 Python 门禁（2–7、19–21）：子进程里挂 `sys.setprofile` 实录每次 `check()` 调用，所以连「过了不打印」的 check_assets / verify_story_data 也有逐条明细（这两道的 `name` 是失败时的措辞，`detail` 标「过时不打印」）。22 check_decision_refs 另有同名 `check(o, doc_text, …)`（不是 `(cond, msg)` 形），钩子照样会录，明细被录成一条 name 为清单首行的假条目（`ok` 与退出码不受影响；lane doc11 待议）。
- 其余（check_symbols、verify_save_robustness、check_sidecars、check_symbols_mutants、check_data_family、probe_pressure、ledger_refs_mutants、Godot 门禁）：解析 `✓ / ✗ / ⚠ / FAIL: / COMPILE_CHECK / STORY_CHECK / OK   / FAIL ` 行；收尾判词之后的 `✗` 视为复述，不重复计数。
- 红了却一条失败都没解析到（脚本崩溃、提前 `exit`）：补一条 `{"name": "exit_code", "ok": false}`，看 `tail`。

批量巡检（CI / 夜巡；下块由注册表生成——增删必跑门禁、改 `--json` 写法后 `python3 tools/gates_md.py --write` 随之更新，勿手改）：

<!-- GATES-BATCH:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 的 oneclick_json 生成，勿手改 -->
```sh
# 必跑十六条的机读版（与 §四 第 0 步同序，每条换 §一 `--json` 列）；导入步骤不判红绿，落 /tmp/gates/steps/、不进汇总
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
python3 tools/check_mac_paths.py --json > /tmp/gates/RefsMacPath.json
python3 tools/check_host_paths.py --json > /tmp/gates/RefsHostPath.json
python3 tools/check_decision_refs.py --json > /tmp/gates/check_decision_refs.json
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

接了原生的：`godot_smoke` / `godot_compile_check` / `godot_story_check` / `p7_guild_exam_smoke` / `patrol_shell` / `qa_pirate_boat_probe`（lane w19-g3），以及经 `shot_gate.gd` 三个收尾函数（`finish_shots` / `fail_no_render` / `finish_contract`）收尾的全部截图探针（探针本身未改）。import 步骤（不跑脚本）、`save_robust_probe`、`save_migrate_probe` 未接，照旧走外包 `gate_json.py --godot`。

- 机理：门禁脚本 `preload` 本件；带 `--json` 时本件在 `_static_init`（门禁脚本编译时，早于 `_init`）关掉 `Engine.print_to_stdout`，门禁与游戏代码的 `print` 一律不外泄；收尾 `GateReport.finish()` 临时打开 stdout 打**一行**紧凑 JSON，再照旧 `quit(rc)`。不带 `--json`：只往静态数组记条目，不打印、不挂 logger，人读输出逐字节不变。
- **`--quiet`**：引擎横幅 `Godot Engine v…`（带窗口时还有 `OpenGL API …`）在任何脚本加载前就已打出，脚本关不掉；不加 `--quiet` 时 JSON 是 stdout 的最后一行。人读模式别加 `--quiet`（会吞掉全部人读输出）。
- 形状同上表；`ok` 仍恒等于 `exit_code == 0`。`checks` 由各门禁的检查 helper 显式登记（`GateReport.check / warn`），不解析文本，逐条与外包解析结果相同。
- 截图探针：每张存下的图记一条 `{name: 文件名, ok: true, detail: "shot"}`，`fails` 每条记一条失败；另带 `tag`、`shots`、`expected_shots`、`out_dir`（契约模式带 `contract: true`，headless 判红带 `no_render: true`）。`gate` 取入口脚本文件名（如 `qa_title_probe`）。
- `engine_errors` / `errors` 由一个只数 ERROR / SCRIPT ERROR / SHADER ERROR 的 Logger 收（WARNING 不计），**只收脚本加载之后的**：patrol 开头 3 行 Vulkan 回落，外包记 `engine_errors: 3`，原生记 0。仍只报数、不改 `ok`。
- 与外包的差别：没有 `tail`（stdout 已关，原输出不留）；`cmd` 只含引擎没吞掉的参数（`--headless` / `--path` 不在其中）。
- 崩溃兜底（lane gd7）：带 `--json` 时本件在首帧前给 `root.tree_exiting` 挂钩。门禁没走到 `finish()` 就退出——`finish` 前 `quit()`、窗口被关（`WM_CLOSE_REQUEST` 自动 quit）——SceneTree 收尾拆 root 时补打**一行** `{"ok": false, "error": "no_finish", …}`（`checks` 末尾一条 `no_finish` 失败，前面照录已登记的条目），并把进程退出码改成 1（`quit()` 传的原码 OS 不给读；`ok == (exit_code == 0)` 照旧成立）。走过 `finish()` 的不再打，stdout 仍只一行。**进程被信号杀（`timeout` 掐断卡死的门禁）、引擎崩溃时什么钩子都不走，stdout 仍没有 JSON 行**——这一类只能由消费方判红：
  - `python3 tools/gate_json.py --native <预设|res://….gd> [--display] [--timeout N] [-- 用户参数]`（或 `--native [--timeout N] -- <完整命令>`）：自动补 `--quiet` / `-- --json` 跑原生门禁，原样转出 JSON；没 JSON 行合成 `ok: false, error: "no_json"`（`no_json_line` 条目 + `tail`，退出码沿用，0 也改 1；超时记 124、`error: "timeout"`）；JSON 不止一行、`exit_code` 与进程退出码不符、`ok` 与 `exit_code` 不符也判红。
  - `python3 tools/gate_json.py --judge <文件…>`：批量落盘的 stdout 逐个判（同上规则，退出码不可知时只看 JSON），任一红退 1。
- legacy 条目强制超时（lane gd9）：注册表 `tier=no` 的条目，或命令里指到 `tools/legacy/` 下的脚本（`--godot` / `--native` 的预设名或 `res://tools/legacy/…`、`gate_json.py tools/legacy/….py`、`-- <命令>`），`gate_json.py` 一律带 `LEGACY_TIMEOUT`（60 秒）跑子进程，`--timeout N` 可改、不可关；到点掐断照样出 JSON：`ok: false, exit_code: 124, error: "timeout", timeout: 60`，外包的另记一条 `timeout` 失败条目，已解析到的 FAIL 与 `tail` 照留。§一「不算门禁」表的本地命令也由注册表加了 `timeout 60` 前缀；`gates_md.py` 逐条校验 legacy 条目带 `timeout` 且本地命令以 `timeout N` 开头，缺了判红。起因：`tools/legacy/p7_smoke.gd` 在 `borrow_ceiling()` 处 SCRIPT ERROR 后不 quit，旧版 `--godot p7_smoke` 会一直挂着、0 字节输出。

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
python3 tools/check_mac_paths.py
python3 tools/check_host_paths.py
python3 tools/check_decision_refs.py
```

**共同的坑：工作树是多 lane 共用的。** 别的 lane 未提交的改动（例如正在改 `SaveLoad.gd`）会让你的门禁红。判「是不是我弄红的」：`git worktree add --detach /tmp/x HEAD`，只放进自己的改动再跑（Godot 门禁先 `cp -a .godot /tmp/x/` 省掉重新导入）。

### 1. check_symbols
- 读：按「一、二、…」小节打 `✓/✗`；末尾汇总 `结果：N 项问题` 并复述每条。`--json` 的 `detail` 就是小节名。
- 开关与附属自检（`builtin_api.txt` 头部自检、`--regen`、`--suggest`、Main 拆出件拼回）见 §一「门禁开关与附属自检」；`--regen` 漂移比对是 §四 CI 步骤。
- **Main 拆出件的切片口径（lane cs8 定）：保持拼回，不改成显式读拆出件。** 断言照旧读 `main_src = read_main_src()`：Main.gd 里每支一行转发 `\t[return |await ]_K.fn(…)` 就地换回拆出件那支 `static func` 的函数体（传 `self` 的形参去掉 `main.` 前缀、裸 `main` 换回 `self`），拆出件里没被转发的 helper / 常量追加在末尾。所以断言写的是「Main 这页该有什么」，与函数搬到哪个文件无关，再拆一刀不用改断言。
  - **拼回只对源码字符串断言有效**：拼出来的文本行号不对应任何真文件（报错别按它找行）；`main.` 前缀已去掉，断言分不出「经 main 取」和「本地取」；static / 实例语义、运行时行为一概不看（交 compile / smoke / 探针）。要断言「某段代码必须在哪个文件」「拆出件自己的 helper 名」这类位置 / 结构事实，直接读拆出件原文（`_locate_func` / `_func_body` / `func_bodies` 都认顶格 `static func`，lane cs16），别借拼回。
  - 拼回会漏的只有「函数体没被换回」一种，`一之零` 全部判红：拆出件改名 / 删了没跟转发；转发带行尾注释、写成两行、签名折行（正则不认）；新拆一刀忘登记（Main 一行转发到未登记的件，或件的头注写了「从 Main.gd 原样搬出」却没登记）。改前这几种都会让「函数体里不得出现 X」一类反向断言误绿（cs8 反例：`_on_save_slot` 转发行尾加注释后，失败句改回「没能记下」仍全绿）。
  - 拼回的实现在 `tools/main_stitch.py`（lane auditfix6 从 check_symbols 抽出，`check_symbols.read_main_src()` 只是包一层传 `MAIN_NOT_SPLITS`）。verify_economy 的 Main 源码断言（`main_src`、泉州对峙 `_setup_quanzhou_standoff` 取体、`gd_const("scripts/Main.gd", …)`）也读它（`main_family_src()`），只剩 `_on_npc_bribe` 先读转发那一行再顺藤去 NpcPage 一处照旧直读——台账「A 牙行被 verify_economy 直读」这条风险就此收掉。
  - 不在拼回范围：其余 Python 门禁（simulate_run / verify_story_data / check_assets / simulate_endgame）直读 Main.gd，下一刀搬走它们读的函数前先查 `docs/Main拆解台账.md`「直读 Main.gd 的门禁」；smoke 的 `_main_family_src()` 只原样拼接、不换函数体、不去前缀，按 func 切的断言要去拆出件里切。
  - 清单职责（lane cs13 起）：拆出件清单只有 **`tools/main_splits.txt` 一份**，`check_symbols`（`MAIN_SPLITS = gen_main_splits.read_splits()`）和 `godot_smoke`（`_main_family_src → _main_splits()`）**两边都读它的第一列**，两份脚本里不再各抄一份。它由 **`tools/gen_main_splits.py` 生成**（拆出件 / 顺序 / lane ← `docs/Main拆解台账.md` 的「已拆（前三刀…）」行与「## 第N刀（lane X，…）… → `路径`」节标题；拆出函数 ← Main 一行转发；拆出 commit / 原 Main 行范围 ← git，拆出 commit 父版 Main.gd；台账写了逐支行段的逐支对账；台账那节函数表列了的函数现 Main 须仍一行转发到本件，否则判红——lane cs18，挪回 Main 再 `--write` 不再一路全绿；反过来那节有函数表的，现 Main 一行转发到本件的每支也都须列在表里，漏列判红——lane cs22，有表就须列全，新搬一支进来没补台账表不再一路全绿），别手改。做拆分的 lane：台账追加一节 → `python3 tools/gen_main_splits.py --write` → 与拆出件同 commit 提交（另加 `godot_compile_check.gd` 的 SCRIPTS）。**`check_symbols` 一之零 是唯一校验者**：清单与重算逐字节比（手改一格、台账 / 拆出件 / 转发改了没 `--write` 都红）、登记的件文件不在就红、smoke 不读清单（自带 `const MAIN_SPLITS` / 写死路径）就红，加上面各条；smoke 自己只查清单非空、各件读得到。两条放行：拆出 commit 自己写不进自己的哈希，记 `-` 照认（下次 `--write` 补）；浅克隆取不到拆出 commit 父版，commit / 行范围沿用清单原值、报 `⚠ 未验`。Main 里一行转发形状、但目标本来就不是拆出件的委托，登记在 `MAIN_NOT_SPLITS` 并注明理由（写成「（Main 函数 → 目标函数，…）」）；**条目失效判红**（lane gd16）：文件不在、Main 没 preload 它 / 没有一行转发到它、转发的目标函数那边没有、注明的「A → B」与实际转发对不上、与 `MAIN_SPLITS` 重登，任一条都算过时条目，删掉或改注。原先的「两份 MAIN_SPLITS 逐项对账」已由「两边都读 `tools/main_splits.txt`」取代（lane cs13，拍板清单 E-5），其余判据不变。
  - 台账格式硬校验（lane cs23，cs18 待议 2）：台账写坏时原先那一刀 / 那一行被 `gen_main_splits` 的正则静默漏掉，重算跟着少一件 / 少一支，`--write` 照写、gen 自己绿，只靠 check_symbols 下游兜，单独跑 gen 的人看不到。现由 gen 直接判红（`--write` 也不写盘）：① 标题以「第…刀」开头却不合节标题正则；②「已拆（前N刀…）」那段的 `X.gd` 没按「`X.gd`（lane，…」写、或认出的不是 N 件；③ 刀序（从「前N刀」的下一刀起逐刀 +1，现为第四刀；lane cs26 起起点由台账推、不再写死 3，那段整段不在就从第一刀起——前三刀日后改写成三节不用改脚本）；④ 像函数表行的却不合写法、行段不是 en dash「a–b」、同一节同一支列两次；⑤ 拆刀节没有函数表（第四、第五刀早于函数表惯例，原登记 `NO_TABLE_OK` 放行；lane cs25 给两节补了表、删了放行，现无例外）。清单与变异实测见 lane cs23 brief 的 Verify；lane cs25 起固化为 `tools/ledger_refs_mutants.py`（§三.26）。
- **按函数名取函数体取不到判红（lane gd16）**：`_func_body(src, name)` / `func_bodies(src).get(name, …)` 取不到时原先静默给 `""`，正向断言跟着红（红因却写成「未接线」一类），反向断言（`"X" not in body`）照样绿——gd16 逐处置空实测 111 处取用里 18 处改前会误绿。现在每处取用按「本脚本行号 + 函数名」记账，「十三、按函数名取函数体」逐条 `✗ check_symbols.py:<行> 取函数体 <fn> 取不到`。只想探有没有这支函数、不想判红，写 `name in func_bodies(src)`（不记账）。
- **按名取体一律先定位、再取体（lane cs9：函数改名误绿）**：各节原先手切函数体的 find 切片 / `split("func X", 1)[-1]` / 不锚行首、不锚名尾的 `re.search(r"func X.*?")` / `_static_body` 共 21 处，取不到时各落各处（空串、None、`split` 落到整份文件、`find` 的 -1 落到最后一个字），名字只按前缀认（`X` 会切到 `X_old`、注释里的 `func X`）。现在一律走 `_locate_func(src, name)`：只认行首 `[static ]func 名字(`，体到下一个行首 `func` / `static func`，取不到与 `_func_body` 同一本账，十三节判红；同一份源码上改前后 21 处取出的文本逐字节相同（只差两处原先多带末尾换行、三处 split 原先不带 `func 名字` 字头），断言输出不变。**新写按名取体的断言用 `_func_body` / `func_bodies().get` / `_locate_func`，别再手切**。
- **两道护栏的真实反向实例（lane auditfix3）**：审计 audit1 判 cs12（_node_block 记账）、cs11（(文件, 名字)）「半实」——现状下没有反向断言靠它们判红。现各有一条：十一节「底图 / 外层横排 / 中区开场不收起」（`_node_block` 读 `Background` / `HBoxContainer` / `CenterArea`，块里 `visible = false` 判红）、船屋 `"advance_days" not in yard_fn`（本来就有，缺的是能落上的变异）；「改名 + 只漏反向断言」变异下护栏是唯一的红、退回旧口径 rc=0，由 §三.23 `check_symbols_mutants` 逐格固化。
- **场景节点块与变异契约也归这本账（lane cs12）**：`_node_block(tscn, name)`（按 `[node name="X"` 切 .tscn 节点块）取不到原先也给 `""`，现记账键 `[node name="X"]`，十三节 `✗ check_symbols.py:<行> 取场景节点块 [node name="X"] 取不到`；节点改名时正向断言原先红因写成「仍展开」，反向断言照样绿。`_guild_remap_contract` 本身要跑在变异源码上，取体改走 `in` 探、缺了记成契约错误「缺 X」，不走 `.get` 记账——否则「删函数」变异（现第 7 支「删入行门槛函数」）会被十三节误判成本脚本取不到函数体；真源码缺函数照样经「行会 remap：缺 X」判红。cs9 之后各节已无手写正则切函数体（剩下的 `re.search(r"^func X\b")` 只探存在性、不取体）。
- **账本抽成共用件（lane cs14）**：`_body_asks` / `_body_ask` / `_locate_func` 搬进 `tools/func_body.py`（切法原样），check_symbols 与 verify_economy 都从这里 import，别各起一套；check_symbols 输出与改前逐字节相同。verify_economy 的按名取体也记这本账，末节「十一、」判红（见 §三 2）。
- **`func_bodies` / `_func_body` 认顶格 `static func`（lane cs16）**：原先只认 `func`，拆出件 / UiTheme 一类的 `static func` 在「扫真文件」的断言里静默不在视野——遍历 `.items()` 的扫不到它、`in` 展开调用链的展不到它（「一之二」`_ready` 链：把一支读 GameState 的 static func 搬进 Economy.gd 并从 `_ready` 调到，改前 rc=0、改后判红），`_func_body` 还会把紧跟其后的 static func 吞进上一支的体里（正向断言借到别人的字样误绿）。现在两者都认 `[static ]func`，`_func_body` 的体到下一个顶格 `[static ]func` 为止；九之七「report_discovery 只由 … 调」原先扫描前手动把 `static func` 记成 `func`，这层绕行已去掉。同一份源码上 check_symbols / verify_save_robustness 输出与改前逐字节相同（现有断言都没取到 static func）。`verify_save_robustness` 自带的一份 `func_bodies` 同改，它不记账（取不到仍给 `""`）。
- **一行转发算取不到（lane cs17）**：Main 拆走一刀后留同名一行转发（`func X(…):` + `\t_K.x(self, …)`），直读 Main.gd（不经 `read_main_src()` 拼回）按名切照样切得到，体里却只有一行调用——真身在拆出件，正向断言跟着红（红因写偏），反向断言照样绿。现在 `tools/func_body.py` 的 `forward_of(body)` 认这种形状：签名后的缩进块（签名同行冒号后的也算）只剩一行代码，整行是 `[return ][await ]callee(实参)`，且 callee 是 `_大写常量.fn`（实参不限），或 callee 是点号名、实参至少一个且个个都是本函数形参 / `self`（原样传参给别的函数）。一行 `return <expr>` 不一概算：实参带运算 / 嵌套调用 / 常量 / 零实参的是真实现（`flee_success_chance` 的 `return clampf(…)`、`SaveLoad._ready`、`unreported_discoveries`），照绿。`locate_func` / `_func_body` / `func_bodies().get` / `_gd_body` / `_gd_fn` 取到转发一律记成取不到，十三 / 十一节报 `只取到一行转发（→ 目标）`；本来就读转发那一行的（「一之二」顺 `_ready` 调用链展开、main8 钉「Main 只许一行转发到 _MARITIME」、verify_economy 先读 `_on_npc_bribe` 转发再顺藤取 NpcPage 真身）写 `forward_ok=True`。同一份源码上两道默认输出只差节标题；全量扫 105 个取体目标（去重，基 abb3f05）逐一改成一行转发，104 个十三 / 十一节点名（余 1 个 `_add_contract_panel` 先在 verify_economy 按锚文手切处抛 IndexError，照样 rc=1），其中 `Voyage.event_weights`（verify_economy）/ `Voyage.roll_day_event`（check_symbols）改前 rc=0 误绿。不在账本里的同类切法（smoke 的 `find("func X")` 切 `_main_family_src()`、verify_story_data 的 `apply_effects` / `_special_cards` / `_check_absent_from_xinghua`、simulate_run 的 `_storm_event`）未收，见 lane cs17 brief 待议。
- **实例方法存在性探查 `inst_func_missing`（lane cs19）**：cs16 留下的 5 处 `re.search(r'^func X')`（外加复用同一 `wm_members` 的「六·4 接舷」一处）逐支变异过：改成 `static func` 全判红，且被探的都是 connect 目标 / 引擎回调 / 读写实例状态的方法，static 化本身编不过（compile 同红）——所以**照旧只认非 static**，改走 `inst_func_missing(src, name)`，红词写明「成了 static func」而不是「未定义」。假绿是别的口子，已收：`Main._on_upgrade` 查 `Main.gd` 原文（拼回的 main_src 会把拆出件里没被转发的普通 `func` 原样追加，搬走不留转发照样「已定义」）；WorldMap 成员变量只认顶格 `[@注解 ]var`（原 `^\s*var` 把函数里的局部 var 也算上）；`clear_ship_cargo` 调用点走 `code_only`（原先 SeaChart 只剩注释提到它也绿，且 compile / smoke / story 全绿）。普查同改：godot_smoke `_main_splits` / `_main_family_src` 两支形状断言认 `[static ]func`（只认 `func` 时 `_main_splits` 改 static 后「不许写死拆出件路径」扫不到任何字）；「行会 / 贡院 / 住处」9 支 `func %s\b` 改成行首锚、查 Main.gd 原文（原先注释里一句「func _x」就算有）。同一份源码上输出与改前逐字节相同。
- **转发判据三片对账（lane gd23）**：「取到的是一行转发」与「取到了真身」分开判，全在 `func_body.forward_of(body, src)` 一处；cs8 拼回（`_SPLIT_FWD` + 一之零）、cs14 取不到判红、cs17 转发判据三片分工如下，gd23 只在不一致处收口，不另起一套：

  | 维度 | cs8 拼回 / 一之零 | cs14 | cs17 `forward_of` | gd23 裁决 |
  |---|---|---|---|---|
  | 管什么 | Main 转发到拆出件的，就地换回拆出件真身；换不回的形状判红 | 按名取不到 → 记账判红 | 取到一行转发 → 记成取不到 | 仍是 cs17 这一层；**报「只取到一行转发」，不自动穿透**：拼回是 cs8 定的唯一穿透通道，直读处该改读真身所在文件，自动穿透会把「该改读」藏起来 |
  | 行形状 | `^\t[return \|await ]_K.fn(…)$` 独占一行，不带行尾注释，签名不折行 | — | 任意缩进、签名同行、去掉行尾注释、`return await` 都认 | 不动。两层各判一件事：形状写歪 → 拼回换不回 → 一之零红（所有读 `main_src` 的断言都受影响）；读到那支的取体处 → 十三红（这一处断言空转）。一处写歪可能两节同红，改掉一处就都绿，不算重复收紧 |
  | `_K` 目标 | Main 里的 `preload` 常量，还须登记进 MAIN_SPLITS（没登记 → 一之零红；MAIN_NOT_SPLITS 放行、不拼回） | — | 任一 `_大写常量`，不看是不是 preload | **向 cs8 对齐**：给了 src 时，`_K` 在 src 里是值常量（`const _K := {…}` / `Color(…)`）就不算转发（`_K.get(k)` 是真实现）；src 里找不到定义的（拆出件引用外来常量）照旧算 |
  | 同文件 / 跨对象 | 不管（拼回只认 `_K.`） | — | (b) 实参至少一个、全是形参 / self，callee 不限 | **收口**：不带点号的 callee 须是同一份 src 里的 func（`str(x)`、`abs(x)` 一类内建不算）；带点号的，接收者须是形参 / self、大写开头的名字（autoload / class_name）或 preload 常量——小写成员变量（`_cache.has(key)`、`_json_cache.erase(path)`）是内建容器方法，没有真身可取。代价：`_page.refresh(x)` 这种转发给成员节点的认不出来（与 cs17 放过零实参同理：宁漏不误） |
  | 零实参 | `_K.fn()` 照认 | — | 零实参一律不算（为放过 `discoveries_found.duplicate()`） | **补 (c)**：零实参、callee 不带点号、是同一份 src 里的 func（`func _x():\n\t_x_real()`，同文件改名后留下的别名）算转发。带点号的零实参仍不算 |
  | 放行 | MAIN_NOT_SPLITS | — | `forward_ok=True`，只限三类 | 不新增放行 |
  | 不记账的取体 | — | `name in func_bodies(src)` 只探有没有 | 同 | `_guild_remap_contract` 的 `body()` 本来不走记账（变异源码上也跑，cs12），现在也按 `forward_of` 判，记契约错误「X 只剩一行转发（→ …）」，仍然不记账 |
  | 报法 | 一之零「…不是一行转发」 | 「取不到」 | 「只取到一行转发（→ `_K.fn`），真身不在这份源码里」 | 同文件别名另写：「只取到一行转发（→ `fn`），真身是同一份源码里的 fn（改名后留了别名 / 该改取 fn）」 |

  各取体处（`_Bodies.get` / `_func_body` / `locate_func` / `_gd_body` / `_gd_fn`）一律传 src。同一份源码上两道默认输出与改前逐字节相同。`scripts/` 1431 支 func 新旧判据只差 7 支：新认 5 支零实参同文件别名（`GameManager._ready`、`Economy._ready`、`TavernFacilitySlip._ready`、`GameState.confiscate_contraband`、`Voyage._pirate_event`），不再误认 2 支容器方法（`SfxSynth.is_cached`、`cs_kit.forget_json`），7 支现在都没有断言取它们的体。
- **断言点名的函数须仍在（lane cs9）**：不取体、只在字面量里点函数名的断言——反向断言（`"_sail_next_day(" not in body`、`any(tok in body for tok in ("add_fame", …))`）、find 定位锚（`body.find("_end_benches")` 取不到得 -1，「A 在 B 之后」照样成立）、存在性探查（`"func shore_door" in src` 会认到 `shore_door_hover`）——被点名的函数一改名、调用点跟着改，断言就空转。现登记在 `check_symbols.py` 的 `NAMED_FUNCS`，按 **(文件, 名字)** 登记（lane cs11，`{定义文件: (名字, …)}`）：每个名字须在**登记的那个文件**仍有行首 `[static ]func 名字(` 定义，改名 / 删了 / 挪到别的文件都判红（十三节 `✗ 断言点名的函数 X 在 <文件> 已无定义，别处还有同名（…）` 或 `…（scripts/ 下也没有…）`），登记的文件不存在另判 `✗ NAMED_FUNCS 登记的文件 <文件> 不存在`；`scripts/Main.gd` 按断言实际读的拼回源码（Main + MAIN_SPLITS）认，搬进拆出件、拼回读得到的不算挪走；清单齐不齐由 check_symbols 自扫本脚本（上述几类字面量里点到、当前确有定义的函数名，不含 `_ready` 等引擎回调），漏登 `✗ check_symbols.py:<行> 的断言点到函数 X，没登记进 NAMED_FUNCS`。本来就要「保持删除」的旧函数（`"func _add_sail_button" not in main_src`）没有定义，自扫不收、不必登记。自扫只到名字（字面量看不出指哪个文件），登在哪个文件下由登记的人按断言读的源码定；原先（cs9）只查「全仓有无此定义」，`advance_days`（GameManager / Calendar 两处）这类同名函数在别的文件还在时不红，cs11 收口。自扫的字面量形状（lane auditfix3 补）：`"X" not in`、`.find / .rfind / .count("X")`、`"func X" (not) in`、`any(…)` / `for … in (…)` 行里的字面量，外加**分支形反向断言**——`if / elif …"X(" in 体…:` 那一支打 `✗`（`elif "_sail_next_day(" in inv …:`）；原先这一形不在自扫里，现有 3 处点到的 4 个名字碰巧别处也点过才登上，新写一条不登记照样绿。**lane auditfix5 把分支形改按 AST 认**（`_nf_branch_sites`）：条件里的 `"X" in 体`（`not` / `not in` 翻极性）、`any/all(t in 体 for t in ("X", …))`、`_has_tok / _calls / _has_func(体, "X")`、`re.search / match / fullmatch / findall(r"…X\(", 体)`，只要「X 在时走进的那一支」自己直接打 `✗`（if / else / 条件表达式 / `match` 的 `case True / False`、`case` 守卫与字面量模式）就收，条件折几行都一样；不收的两种：X 在时落进的是 elif 链（「这条过了、查下一条」，后面各支的 ✗ 不归 X）、✗ 嵌在那一支里层的 if / for / match 里。改后多收 3 支真漏登的（:3420 `any(tok in sim_src for tok in (` 元组折行里的 `_on_temple_look` / `_on_temple_rub` / `record_discovery`），已补登。
- **登在哪个文件：同名多处定义须在断言行标明（lane auditfix5）**：字面量 `"advance_days"` 看不出指 GameManager 还是 Calendar 那一支，登记键是人定的——auditfix3 实测改名后把 `advance_days` 改登到 `scripts/core/Calendar.gd` 下即 rc=0。字面量本身判不了，所以把限定挪到断言那一行：名字在 scripts/ 下 ≥ 2 个文件有定义（Main 拆出件并回 Main 算一处）时，自扫点到它的**每一行**行尾须标 `# NF: 接收者.名字`（接收者按 project.godot 的 autoload 名 / `class_name` 认文件；或写 `# NF: scripts/….gd:名字`），标明的文件须与 NAMED_FUNCS 登记一致。判红四种：没标（`✗ check_symbols.py:<行…> 的断言点到同名多处定义的函数 X（…），字面量看不出指哪一支`）、标明的与登记不符（`✗ …的断言标明指 <文件> 的 X，NAMED_FUNCS 却登在 <文件>——错登到同名的另一支了？`）、接收者认不出文件、标了却那一行自扫没点到 X。现只有 `advance_days` 一支同名（7 行都标 `GameManager.advance_days`）；日后别的文件也定义了某个已登记的名字，原先点到它的行随即判「没标」。**仍管不到的**：改名后连断言行的标注也一并改成 `Calendar.advance_days`——那是在断言那一行上明着改指向，已不是「只修弹红的」，机判不了（要判得知道断言读的 `yard_fn` 取自哪份源码、那份源码里 `advance_days(` 解析到谁，check_symbols 里取体变量的来历没有统一写法）；替代：错登那一步现在的红字点到断言行号，改指向必须改那一行，落在 diff 里由评审看。
- **「有没有这支函数 / 调没调」按定义 / 调用正则认名，不按光秃子串（lane cs10）**：`"_can_fire" in ship_src`、`"_format_left_hud" in wm_src`、`"ShoreDraft.deal" in main_src` 这类正向存在性探查只按子串认名，函数改名成 `X_v2`（调用点同改）照样打「已定义」——cs9 保留前缀改名普查里剩的 35 支中 16 支是这类（其余 19 支只出现在 print 文案 / 注释 / Python 变量名，改名本该绿）。现在一律走 `_has_func(src, name)`（行首 `[static ]func 名字(`）或 `_calls(src, name)`（`名字(` / `名字.bind(` / `.call(`，名前不接标识符或点、名尾不吃后缀，名字可带宿主如 `UiTheme.heading_card`）；逐支改名 `X_v2` 变异改前 rc=0、改后 rc=1。**新写这类断言用 `_has_func` / `_calls`，别再写 `"X" in src`**。同形子串另有约 39 处（改名已由 `NAMED_FUNCS` / 十三节取体兜住，普查不绿）尚未改写，也没有自扫护栏（待议；lane cs15 已改写，见下条）。
- **带参调用、定位锚、计数也按标识符边界认（lane cs15：子串存在性探查收尾）**：cs10 之后仍有一批正向探查按前缀认名——`"add_fame(3)" in src` 认到 `_add_fame(3)`，`"func _mount_condition" in src` / `split("func _storm_event")` 认到 `X_v2`，`body.find("visit_port")` 定位锚落到别的名字上。check_symbols / verify_economy / verify_save_robustness / verify_story_data / simulate_run / verify_coastline 约 190 处、godot_smoke 32 处与 6 支 qa 探针改走共用件 **`tools/src_probe.py`**（GD 侧 `tools/src_probe.gd`，口径同）：`has_func`（行首 `[static ]func 名字(`，`static=True` 须带 static）/ `calls`（cs10 的调用口径）/ `has_tok` / `tok_find` / `tok_count`（字面量头尾是标识符字符就要求外侧不接标识符字符；`call=True` 时名字后须紧跟 `(` 或 `.bind(` 等，宿主不限）。每处新条件都严格蕴含旧子串条件，六支 Python 门禁输出与改前逐字节相同。**反向断言（`not in` / `find < 0`）不改**：按前缀认只会多红，收成有界反而放过改名后的调用；check_symbols 里它们由 `NAMED_FUNCS` 兜改名，自扫另认 `_tok_find(` / `_tok_count(` 的字面量。**新写「有没有 / 调没调 / 在谁之后」的断言用 src_probe，别再写 `"X" in src` / `src.find("X")`**。
- 常见红因：改了 `Main.gd` 等处的文案 / 函数名，但本脚本里对应 lane 的**源码字符串契约**没同步（这是最常见的一类，改文案先 grep 本脚本）；`project.godot` autoload 与 `AUTOLOADS` 表不符；契约要求存在的 `tools/*.gd` 探针缺失。

### 2. verify_economy
- 读：`一、数据完整性` 起逐节 `✓/✗`；`结果：N 项未通过`。
- 常见红因：`data/ports.json` / `goods.json` 引用悬空（新港、新货、connections 拼错）；`Economy.gd` / `Voyage.gd` 公式或常量改了而脚本里的复刻没同步；新闻冲击倍率越界。
- `✗ verify_economy.py:<行> 取函数体 <fn> 取不到`（「十一、按函数名取函数体」，lane cs14）：该行读的 GDScript 函数改名 / 删了 / 搬进拆出件没跟着改读哪份。原先按名取体是手切 `split("func X", 1)`（按前缀认名，`X` 改成 `X_v2` 照样切到它）或取不到给 `""` / 整份文件，反向断言空转变绿；现在一律 `_locate_func`（只认行首 `[static ]func X(`）或 `_gd_body` / `_gd_fn`（到 `const` / `##` 为止），取不到逐条判红。改前后 33 处手切取出的函数体除多带 `func X` 字头外逐字节相同，其余节输出不变。

### 3. simulate_run
- 读：前半是模拟流水（`第 N趟 …`，其中 `✗查扣` 是剧情事件不是失败）；`✓/✗` 才是断言；`结果：N 项未通过`。
- 常见红因：`ships.json` / `goods.json` 数值改动造成死锁（舱位装不下补给、钱不够换船）；`Fleet.gd` 分船装载公式改了未同步（会先出一串缩进的 `✗ 船i … 料 > 载重` 诊断行）。

### 4. verify_coastline
- 读：五节（环 / 港口贴岸 / 绕岸航线 / 海名标注 / 接线）；绿时先打一行统计。
- 常见红因：重建 `coastline.json` 后 `meta.points` / `meta.rings` 与实数不符；港口经纬度漂到腹地或外海；`SeaChart.gd` 接线字段改名；底图尺寸与 `chart_projection.json` 不一致。

### 5. check_assets
- 读：绿时只有一行统计；红时每条 `FAIL: … 文件不存在` / `缺 .import`。
- 常见红因：代码引用了还没入库的图；新图没跑过导入步骤（缺 `.import`，先跑 §9）；图坏导入失败则 `.import` 记 `valid=false`，本道判红；挪 / 改名资产没改前缀拼接表。
- 2026-09-28 补（扩充包钩子第一批）：`PROLOGUE_PAGE_BG` 也按表查值，键须是 scenes.json 的 cg_ 页且不收 `cg_title`；scripts/ 里 `_set_background_file("…")` 直写的文件名与大写常量实参逐个查（缺图原先静默回落海路图）；`assets/bg_<港 id>_<后缀>.*` 后缀须是该港 ports.json 战况表里的非 loyal 战况 / 没被 `PORT_SEASON_BORROW` 借走的季节 / `PORT_YEAR_BG` 登记年份且是 `.jpg`，拼错或该港用不上又无人引用即红（09-28 评审补：原先只和 WAR_LABEL 全集比，`bg_quanzhou_besieged` 这类该港没有的战况能过）；`assets/goods/good_<id>.png` 的 id 须在 goods.json。

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
- 截图旁证（lane pg）：存盘（默认 `/tmp/patrol-shots/`；设 `NK1_SHOT_DIR=<目录>` 则落 `<目录>/patrol/`，lane pg3。默认**有意不放进** `/workspace/nk1-qa-shots/patrol`：patrol 是必跑门禁，§二 批量块、§四 CI、`.claude/todo.md` 验证段都不带前缀跑，挪进共享证据根就成了每条 lane 每轮都覆盖证据图，lane pg4 否证）前按像素种类数 / 直方图熵判一色（每 4px 取点、每通道 16 级；种类 ≤ 2 或熵 < 0.1 bit）。一色或拿不到图逐张打 `⚠ 截图旁证 <页> …`，**只记 warn、不改退出码**（`--json` 的 `counts.warn`）；headless 打一行 `⚠ 截图旁证未判（n 张跳过）`。判据开头自检 4 条（纯色 / 量化格边界两色抖动必判一色、杂色图不判、空图判拿不到图），自检 `✗` 即 FAIL。
- 常见红因：没设 `DISPLAY`；按钮越出 1280×720；设施页 / 终局港口页按钮文案改名（断言按文案找钮）。

### 15. 截图门禁（shot_gate.gd + 截图探针）
- 读：`<TAG>_OK shots=n/n -> 目录`；红时先列 `✗ 真失败：…`，再 `<TAG>_FAIL k（shots=…）`。
- headless 不加 `-- --contract` **必红**（`_FAIL headless …此为环境不具备，不是画面回归`）——这是设计，不是回归。只验契约：`godot --headless … -- --contract` → `<TAG>_CONTRACT_OK`。
- 输出目录（lane gd2 / pg3）：默认 `/workspace/nk1-qa-shots/<子目录>`（§一明细表「截图目录（默认）」列）；设 `NK1_SHOT_DIR=<目录>` 则全部 25 支探针整体改落 `<目录>/<子目录>`（`vision/`、`title/`、`chars/`…照原样建），patrol 旁证落 `<目录>/patrol/`；截图门禁以外的两个出图工具也认它（lane pg4）：`CutscenePreview --snap` 缺省 `/tmp` → `<目录>/cutscene-preview/`（给了 `--snapdir` 仍按它），`tools/art/tour.sh` 缺省 `~/tmp/nk1-art-work/tour` → `<目录>/tour/`（给了 `-o` 仍按它）。相对路径一律按 `$PWD` 展开。**推荐用法：worktree / 自测一律设它**，否则会覆盖共享证据图；不设只用于刷新共享证据图：

  ```sh
  NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd
  NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd   # 旁证 → /tmp/<lane>/shots/patrol/
  NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 godot --path . res://scenes/cutscene/CutscenePreview.tscn -- --cs=<id> --snap=1.5 --autoquit   # → /tmp/<lane>/shots/cutscene-preview/
  NK1_SHOT_DIR=/tmp/<lane>/shots DISPLAY=:2 tools/art/tour.sh -r <运行副本> title   # → /tmp/<lane>/shots/tour/title/（含 last.png / sheet.jpg：tools/art/tour_sheet.gd 用 Godot 拼，不要 PIL，lane pg5）
  ```

  脚本里统一写 `var OUT_DIR := ShotGate.out_dir("<子目录>")`，新探针别再写死绝对路径：gates_md 按这个写法读目录，并判红「截图脚本没走 `ShotGate.out_dir`」「`tools/` 已跟踪 `.gd` 代码行里写死默认根（只许 `shot_gate.gd`）」「patrol_shell 不读 `NK1_SHOT_DIR`」（lane pg3）；注册表 `shot_env.users` 登记的 patrol / CutscenePreview / tour.sh 代码行里读不到 `NK1_SHOT_DIR`、子目录或原默认也判红（lane pg4）。
- `tools/art/tour.sh` 巡检截帧**不算门禁**（lane gd13 实测判定，理由写在 §一「不算门禁」表）：全集 21 站实测 348 秒、另要运行副本并导入一次（12 秒），要 DISPLAY；只判引擎退出码 / TOUR_READY / 报错计数 / 帧与小样在不在，不看像素，画面回归归上面的截图探针。动 ShotTour / tour_sheet / 过场站点时手跑。输出契约固定：逐站一行 `✓ <站点> rc= frames= errors= …` / `✗ …  ← 红因`（引擎退出码 · 未就位 · 报错 k 行 · 一帧没出 · 小样没出），末行 `TOUR PASS n/n` / `TOUR FAIL k/n`，退出码 0 全绿 / 1 有站红 / 2 用法错 · 运行副本不在 · 找不到引擎；机读 `python3 tools/gate_json.py -- tools/art/tour.sh -r <运行副本> [站点…]`（checks 逐站一条、summary 取末行，注册表 timeout 强制 900 秒）；gates_md 判这几个字样还在 tour.sh 代码行里。
- 常见红因：空视口 / 一色图（窗口没真正绘制）；张数不足。`vision_letterbox_probe` 旧有的「出战合拢时画面中线未全黑（v=0.302）」偶发红不是时序：布景是真海战，约 8–10 s 旗舰被击沉、WorldMap 自起出战墨边顶掉探针那副（lane pg 已冻住布景；再现时会先报「布景海战在墨边演示中自行结算」）。

### 16. save_robust_probe
- 读：`✓` 行 + `SAVE_ROBUST_PROBE PASS`；上百行 `ERROR: 存档结构异常 …` 是探针故意喂的坏档，预期存在；`SCRIPT ERROR` 才算失败。
- 常见红因：`SaveLoad.gd` 判坏档 / 退 `.bak` 路径改动；新强类型字段赋错型时先赋值后判型。

### 17. check_sidecars
- 读：绿时 `结果：全部通过`（前一行报 uid 个数、VRAM 纹理张数与基线、工作树是否查过）；红时每条 `FAIL: …`，末行 `结果：N 项失败`。成对 / 多余 / 内容三类只看 git 索引（已暂存也算），工作树里没跟踪的文件不查；「工作树漂移」一类比对索引与工作树里的已跟踪侧车，`--index-only` 跳过。带 `.gdignore` 的目录与 `.` 开头的路径跳过。
- 口径：哪些侧车必须入库、哪些是生成物 / 编辑器漂移不许带，判定表在 `docs/侧车口径.md`（脚本头部注释同表）。仍是 lane 加跑档（不进一键跑）；CI 里作 §四 步骤 1，紧跟导入步骤之后跑，顺带查导入有没有改写已跟踪侧车（lane gd5）。旧口径「提交时跳过 `*.uid` / `*.import`」只指别人的未跟踪侧车与编辑器顺手改写的已跟踪侧车，本 lane 新增源文件的侧车必须同 commit 带上（同车规则：编辑器生成 → 显式 pathspec 与源文件一起 `git add` → 本 lane 不新增 FAIL，步骤见 `docs/侧车口径.md`「同车规则」；lane 简报头部模板同句，见 `COORDINATION.md`）。
- 常见红因：提交新 `.gd` / 素材时按旧口径跳过了侧车；挪 / 删源文件没带走侧车；挪 / 拷源文件连侧车一起挪 / 拷、没让编辑器重导（`source_file` / 产物名哈希对不上、uid 重复）；ARM / 移动端机器导入把 `terrain_4096.png.import` 写成 etc2 形态后提交（非基线）；跑完编辑器工作树里已跟踪 `.import` 被改写（工作树漂移：不是本 lane 有意改的就 `git checkout --`）。补法是把工作树里编辑器生成的 `<文件>.uid` / `.import` 一并入库（别手写 uid）。

### 18. save_migrate_probe
- 读：`✓/✗` 行 + `SAVE_MIGRATE_PROBE PASS` / `FAIL fails=k`；只动存档位 95，不碰正式位。
- 覆盖（现 `SAVE_SCHEMA` 3，迁移链 v1→v2→v3）：v1 老档（无 `save_schema`）读入补字段、回写本版、原件留 `.v1`（正本坏时从副抄迁、另存 `.bak.v1`）；v2 档（lane fx6，无 `state.met_ids`）按雇用记录 / 在船职事 / 守城见林华回填人物志「已识」、推不出留空、原件留 `.v2`，再验本版档带 `met_ids` 存—读来回；未来档（`save_schema` / `version` 高于本版）拒读、不退副抄、文件不动。
- 常见红因：`SaveLoad.gd` 的 `_inspect` / `_resolve` / `_migrate` 迁移链（现 `_migrate_v1_to_v2` → `_migrate_v2_to_v3`）改动；新加 state 字段没进迁移补齐（结构不兼容的改动升 `SAVE_SCHEMA` 就要再挂一级 `_migrate_vN_to_vN+1`，本探针补一节该级回填）；未来档改成了退 `.bak`。

### 19. gates_md（本文件 §一 的自检）
- 读：`一、注册表`（`tools/gate_json.py --list` 能出、注册的脚本都在、用 `ShotGate.finish_shots` 收尾的截图脚本全入册且 TAG / 张数 / 目录读得到、目录都走 `ShotGate.out_dir`，接 `shot_gate` 的脚本（现 31 支：截图册 25 支，加只借它挂压帧、不走 `finish_shots` 收尾的 letterbox_signal / qa_yard_transition 与船近景四支 japan_ship_probe / ship_dashi_probe / ship_exquisite_probe / shot_champa_ship）代码行里都调了 `ShotGate.frame_pressure`（lane gd18，`NK1_PROBE_SLOW_MS` 压帧一个口径），`tools/` 代码里不写死默认截图根、patrol 读 `NK1_SHOT_DIR`（lane pg3）；附属自检的所属门禁在册、开关 / 判词字样还在其源码里；CI 步骤引用的 `tools/…` 都在）→ `二、docs/GATES.md`（生成表格列数整齐；§一、§四 两个标记块逐字一致，红时打首处差异的「文档 / 注册表」两行；§二「批量巡检」标记块逐字一致且在 §二 里；§三 `### N.` 编号对得上；§三「一键人读全跑」与 `.claude/todo.md`「## 验证」代码块拆出的命令（续行拼回、按 `&&` 切、去行尾 `# 注释`）都与必跑档 `cmd` 逐条同序）。
- 改法：**只改 `tools/gate_json.py` 的 `REGISTRY` / `SHOT_PROBES` / `SUBCHECKS` / `CI_STEPS`**，再 `python3 tools/gates_md.py --write`；块外（§二、§三、§四的标题）是手写，编号小节随注册表增删要补，一键跑命令段与 `.claude/todo.md` 验证段随必跑档改（这两处 `--write` 不代写）。新门禁入册、升降档的全套步骤（含 gates_md 管不到的 CI_STEPS / README / 在途口径）见 §五.1 / §五.2。
- 常见红因：手改了标记块；改了必跑档只改 §三 没改 `.claude/todo.md` 验证段（gd4 查出的 patrol 缺 `DISPLAY=:2` 即此类）；新截图脚本接了 `shot_gate` 却没进 `SHOT_PROBES`；某道门禁挪走 / 改名（如 `verify_narrative` 挪 `tools/legacy/`）没改注册表；加了门禁没补 §三 小节；改了 `--suggest` / `--regen` 等开关名或判词没改 `SUBCHECKS[].marks`；升降必跑档没同步 §三 一键跑命令段。

### 20. RefsMacPath（`tools/check_mac_paths.py`，Mac 专属绝对路径防回归）
- 读：`零、模式自检`（lane auditfix2，每次跑都先过：`✓ 正向样本 N 行都被认出` / `✓ 反向样本 N 行都不命中` / `✓ 独立审计原反例…整段扫出 2/2 行`；`SAMPLES` 里有一行漏认或 `CLEAN` 里有一行误报即 `✗`，模式表回退 / 改窄了在这里先红，不等真文件写进来）→ `一、白名单条目都有效`（`ALLOW` 每条：文件在且已跟踪、头 5 行还有登记的横幅 / 回指注字样）→ `二、git 已跟踪文件里的 Mac 路径`（白名单文件逐条 `命中 N 行，登记 N 行（理由）`，本脚本自扫两条 `✓ tools/check_mac_paths.py：自扫按行排除 PATTERNS 块 10 行`（lane gd21）、`…SAMPLES 块 N 行`（lane auditfix2）；末条 `白名单外 0 处命中（扫 N 个已跟踪文本文件，含本脚本、其 PATTERNS / SAMPLES 块除外）`）；红时白名单外的命中逐行列 `文件:行  原文  ← 命中串`。读工作树内容（已暂存的新文件也扫），二进制跳过；本脚本自身也扫（lane gd21）：只按行排除 `PATTERNS = [` 到 `]` 之间的条目行，块里每行须是一条 `("名字", r"正则", "理由")` 且行数等于条目数，夹进注释 / 别的字符串即 `✗ tools/check_mac_paths.py：自扫按行排除 PATTERNS 块…——块里第 N 行不是一条…`；`SAMPLES = [` 块同理（每行须是一条 `r"样本行"`，且每行都得被零节认出，塞不进漏网的路径），块外（docstring、ALLOW、判词）写了 Mac 路径照常按白名单外命中判红；未跟踪文件有命中只记 `⚠`（别的 lane 没提交的不染红共用树，同 check_docs_index）。模式 10 条及每条为什么算 Mac 专属写在脚本 `PATTERNS`（lane auditfix2 补：家目录写成 `$HOME` / `${HOME}` / `"$HOME"` / `Path.home()` 拼接的资料库目录，Intel Homebrew 前缀下的 opt / Caskroom 目录）；`~/tmp/…` 草稿区、走查署名、安装提示里的 `brew install`、下载 URL 里的 `macos` 字样不算。拼接也认（lane cs20）：每行先按原文对模式，不中再用 `tools/path_scan.py` 的 `fold` 把「字面量 / 家目录」之间的 `+`、`.path_join(…)`、`os.path.join(…)`、`Path(…) / …`、`% …` 折成一段再对一遍——GDScript / Java / Python 取 HOME 环境变量（`OS.get_environment` / `System.getenv` / `os.getenv` / `os.environ`）、`Path.home()`、f-string 里的家目录都折成 `$HOME`，所以家目录派生再拼资料库目录、字面量拆开写都中；变量名不追。`fold` 与 §三.21 共用一份。本道不分代码 / 注释：注释、文档串里的 Mac 路径照红（Mac 路径在活跃文件里没有该写的场合，留档走 `ALLOW`），这是与 §三.21「仓外根在注释里放行」刻意不同之处。
- 口径：lane doc7 / doc8 / gd13 清完后剩下的命中只有 `tools/legacy/` 5 支（带「勿运行」横幅）与 2 份带日期的历史稿（头部回指注），都登记在 `ALLOW`，按命中行数卡死——往留档里再加一行也红。加白名单条目须写理由，且只限留档 / 历史稿；活跃脚本与文档一律改成本机口径（env → PATH → 取不到明确报错，见 `build_ui_textures.py` 的 `NK1_RSVG`、`tour.sh` 的 `GODOT`）。lane gd21 升进必跑档、排一键跑末条（其后 lane cs21 的 RefsHostPath、lane auditfix1 的 check_decision_refs 又排在它后面；原为 lane 加跑档 + CI §四 步骤 5，步骤 5 随之删掉）。升格判据（自己判不准 / 1 秒量级 / 只读不写盘 / 未跟踪只 `⚠`）见 §五.2；本道：「写了外部路径」自己判不准——照抄 Mac 上的命令、默认根最容易顺手带进来；实测 0.23 s（lane gd21 Verify）。零节的规格即 §五.3 的规则表型自证，由来见 §五.5 例二。
- 常见红因：照抄 Mac 上的命令 / 默认根进脚本或文档；清掉了留档里的几处却没改 `ALLOW` 的行数；挪 / 删了留档文件没删条目。

### 21. RefsHostPath（`tools/check_host_paths.py`，本机 Linux 绝对路径防回归）
- 读：`零、样本自检`（lane cs21，每次跑都先过，与 §三.20 的「零」同规格：`✓ 正向样本 N 行在 .gd 代码行 / 注释行 / .md 三处都判红` / `✓ 反向样本 N 行三处都不判红` / 每条仓外根一行 `✓ 根：owner 代码行绿；非 owner 代码行、拼接写法红；非 owner 行尾注释、.py 文档串、.md 绿`；`SAMPLES` 有一行在某处没判红、`CLEAN` 有一行在某处判了红、owner 口径有一处不对即 `✗`，并注明漏在哪一处——模式表回退 / 改窄了、`offending` 的 owner 判断或 `path_scan` 的注释切法 / 拼接折叠改坏了在这里先红，不等真文件写进来）→ `一、仓外根登记（ROOTS）都有效`（每条：owner 已跟踪、代码行里还写着这个默认根、还读登记的环境变量）→ `二、git 已跟踪文件里的本机路径`（每个仓外根一行 `· 根：文档 / 注释 N 处（不判红；理由）`；本脚本自扫一条 `✓ tools/check_host_paths.py：自扫按行排除 SAMPLES 块 N 行`；末条 `登记外 0 处命中（扫 N 个已跟踪文本文件，含本脚本、其 SAMPLES 块除外）`）；红时逐行列 `文件:行  原文  ← 命中串`。读工作树内容（已暂存的新文件也扫），二进制跳过；未跟踪文件只记 `⚠`（同 §三.20）。本脚本自身也扫：模式写成占位不会自命中，只放过 `ROOTS` 登记行；`SAMPLES = [` 块按行排除（lane cs21），块里每行须是一条 `r"样本行"` 且行数等于条目数，夹进注释 / 别的行即 `✗ tools/check_host_paths.py：自扫按行排除 SAMPLES 块…——块里第 N 行不是一条 r"样本行"；整份照扫`，块里每行又都得在零节判红，塞不进漏网的路径。
- 口径：模式 2 条——`/home/<用户>`（家目录，写 `~/…` 或走 PATH / `$GODOT`）、`/workspace/<目录>`（本机工作区；仓库根本身永不登记，命令一律 `--path .`，否则在隔离 worktree / 软链里照抄会悄悄跑主树）。登记的仓外根只有两条：截图证据根 `/workspace/nk1-qa-shots`（owner `tools/shot_gate.gd` 的 `DEFAULT_SHOT_ROOT`，`NK1_SHOT_DIR` 覆盖）与简报目录 `/workspace/nk1-agent-briefs`（owner `tools/check_decision_refs.py`，`NK1_BRIEFS` 覆盖）；文档与注释里写它们不红，代码段只许 owner 写。代码 / 注释按位置切（lane cs20，切法在 `tools/path_scan.py` 的 `comment_spans`）：.gd / .py / .sh / .gdshader 每行在注释起点切开，切后只有代码段算代码——行尾注释里写仓外根不红（改前整行算代码、偏严）；字符串里的 `#`、shell 的 `$#` / `${#a}` 不起注释；.py 各级文档串、GDScript 独占语句的三引号串（块注释写法）整段算文档，赋给变量的三引号串仍是代码；.sh 的 heredoc 正文不认（照代码判，偏严）；其余文件整份算文档。ROOTS 一节同口径：owner 的默认根只剩行尾注释里写着即判条目失效。拼接也认（lane cs20，与 §三.20 共用 `path_scan.fold`）：`"/<根>" + "/<目录>"`、`.path_join(…)`、`os.path.join(…)`、`Path(…) / …` 折成一段再对模式，字面量拆开写照样命中；家目录取法折成 `$HOME`，与 `~/…` 同算合规（所以 HOME 派生只在 §三.20 那边可能红）。与 §三.19 gates_md「`tools/` 代码里不写死默认截图根」同向，本道扫全仓、两条根都管。Godot 节点路径 `/root/…`、`~/.local/…`、`/tmp/…` 不算。lane cs21 升进必跑档、排一键跑 RefsMacPath 之后（原为 lane 加跑档 + CI §四 步骤 5（lane gd22），步骤 5 随之删掉）。升格判据见 §五.2，与 §三.20 同；本道：「写了本机路径」自己判不准，照抄本机命令、`--path` 写仓库根最容易顺手带进来；实测墙钟 0.70–1.02 s（lane cs21 Verify）。零节与 §三.20 同规格（§五.3）。
- 常见红因：照抄本机命令把仓库根写成 `--path /workspace/<仓库>`（改 `--path .`）；文档写引擎绝对路径 `/home/<用户>/.local/bin/godot`（写 `godot` / `~/.local/bin/godot`）；新探针在代码里拼 `/workspace/nk1-qa-shots/…`（改走 `ShotGate.out_dir`）；挪了 owner 文件没改 `ROOTS`；改了 `PATTERNS` / `offending` / `tools/path_scan.py` 没跑通零节（改窄了就补 `SAMPLES` 看它红，放宽了就补 `CLEAN` 看它不误报）。

### 22. check_decision_refs（`tools/check_decision_refs.py`，拍板清单「文件:行」跟号）
- 读：逐处问题一行 `✗ NOFILE` / `✗ OOR` / `✗ DRIFT L<清单行> 文件:行：…该处内容变了；可跟号 → :新号（diff / 同文件原文 / 函数名 / 跨文件原文）` 或 `跟不上，要人工：…`（附所在函数现在在哪、同文件最像的行）/ `✗ 待核 L<清单行>`；末两行 `锚 X：引用 N 处（仓外 brief M 处只查越界），跳过「原文作」K 处；NOFILE/OOR 0，DRIFT 0（可自动跟号 0、要人工 0），待核标记 0` + `结果：全部通过`。比的是清单头部锚（「行号：……按 HEAD 某提交」）那个提交里的原文和**工作树**里同一行号的原文，所以没提交的改动也会让它红（同 check_symbols）；`--show` 逐处印原文回读，`--since REV` 自证改号前后指的是同一段（MISMATCH = 号改错了或有意换了所指，后者在 Verify 里写明）。仓外 brief（`lane-*.md` / `COORDINATION*.md`，`$NK1_BRIEFS`）只查越界，目录不在只记 `⚠`。
- 改号自证（lane auditfix1，默认跑）：`改号自证 [对 HEAD 版 / 对最近改清单那笔的父版]（旧锚 A → 新锚 B）：对上 N 对，…MISMATCH 0…`。为什么要这步：锚 = HEAD 时，清单里的号写歪了，锚里那行和工作树同号那行照样一致，上面的 DRIFT 看不出来（本片实测：`:1942` 改成 `:1941` 改前 rc=0）。所以和上一版清单（工作树改了没提交 → HEAD 版；没改 → 最近改清单那个提交的父版）按 `--since` 的口径配对，要「旧锚旧号那段 == 本版锚本版号那段」；不等、而旧那段原文在新处文件里还找得到 → `✗ MISMATCH …旧锚那段原文在 B 里还在 文件:行——行号改歪了？`。旧那段原文已找不到（所指那段自己被改写了，`--fix` 给「跟不上」的多是这种）只记 `⚠ 改指未验`，不判红；确是有意把引用换指到别处的，在那处引用后括注「原文作 `:旧号`」认账。
- 穿透一行转发（lane auditfix6）：拆走一刀后函数头原样留在 Main、体搬进拆出件，diff 会把指着函数头的引用跟到那行转发上（EA6-4 实例：锚 `2651531` 的 `scripts/Main.gd:1768` 被旧版跟成 `:1781`，那是 `_MARITIME.setup_yamen(self, port_id)` 转发），原号没挪的连 DRIFT 都不报。现在锚里那段在一支真函数里、落点所在函数却只剩一行转发（判据 = `func_body.forward_of`，与 §三.1 cs17 / gd23 同一份）的，顺转发（`_K.fn` 按 preload 常量、`Crew.fn` 按 autoload / class_name、同文件 `fn`，最多 4 跳）到真体里重找那段，印 `可跟号 → 真体文件:行（穿透一行转发 …）`；穿透不下去印 `跟不上，要人工：跟到一行转发：…`，都判红。锚里那支本就是转发的（清单有意指着转发）不穿透。改号自证 / `--since` 对这类只认穿透算出的那一行，写歪判 MISMATCH（旧版只记 ⚠）。每次先跑内存里的「转发穿透自检」10 形（`_ST_CASES`），去掉穿透 / forward_of 退化即 `✗ 转发穿透自检 …`、退 1——反向自证随必跑门禁进 CI。
- 口径：lane dec3 立、dec4 加四层跟号与 `--fix`，lane auditfix1 入册即必跑、排一键跑末条（原先不在注册表里，自 cs14 `a8ff603` 起主干一直红、到 `abb3f05` 积了 DRIFT 47 没人看见，独立审计 audit1 点名）。跑一次约 1s（auditfix1 实测 0.5–0.6 s），只要 python3 + git，不带 `--fix` 只读不写盘；入册缺位的教训见 §五.5 例一。修法：`python3 tools/check_decision_refs.py --fix`——跟得上的改号、头部锚改成 HEAD，跟不上的插「〔跟号待核：锚 X 里是 文件:行〕」；`--fix` 要求所引文件与 HEAD 一致。谁来跟（挪了被引行的那一片自己跟，不交下一片）、两笔式落地（代码 → `--fix` 另提清单，拆 Main 的与 `gen_main_splits.py --write` 同一笔）、人工回读口径，统一见 §五.4。
- 输出确定序（lane cs23，cs18 待议 4）：逐处的 ⚠ / ✗ 行先收齐、按「清单行号 → 行内第几处引用 → 类别」排好再印（`--show` 原文行跟在所属引用前、「待核」标记排在全部引用之后），`--since` / 改号自证的新旧配对按新版引用的清单顺序逐对比。原先配对取集合交集、遍历顺序随 PYTHONHASHSEED 变：有 2 处以上 ⚠ / MISMATCH 时同基连跑每次行序不同（实测 `--since abb3f05` 5 次 5 个 md5），「逐字节同」的快照比对会偶发假 DIFF。原本就确定的输出（DRIFT 行、0～1 处 ⚠）逐字节不变。
- 零之二、ledger_refs_mutants 落点预检（lane w19-g8）：转发穿透自检之后一行 `✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异在当前台账 / 两支脚本 / 清单上都落得上（…）`。ledger_refs_mutants（§三.26，lane 档）的变异锚在台账、gen_main_splits、本脚本的两处排序和本清单的 `scripts/Main.gd:N` 引用上，靶子被挪了由这里当场判红（`✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——…`，计入问题、退 1）；内存里跑、不落盘，本道 0.33 s → 0.43 s。`--fix` 时不跑；关断开关 `--no-ledger-landing` 只给 ledger_refs_mutants 二节用（印一行 `⚠ … 落点预检未跑`），一键跑不许带。判档与「谁在什么时候跑」见 §三.26「生命周期」。
- 常见红因：拆 Main / 往 check_symbols、verify_economy 里加断言挪了清单所引的行（DRIFT，`--fix` 多半全自动跟上）；所引那段自己被改写（cs10 收紧正则、cs14 改取体写法这类，`--fix` 给「跟不上，要人工」，按线索找同一条断言的新行）；`--fix` 打的「待核」标记没删；清单头部锚被手改成不存在的提交。

### 23. check_symbols_mutants（`tools/check_symbols_mutants.py`，反向断言空转的变异对照）
- 读：先 `零、靶子定位自检`（lane cs24）`K0`–`K10` 逐格 `✓ K<n> …：落在 <文件:行 函数> → …` / `✓ K<n> …：变异没落上（…）`；再 `一、逐格变异`——`B0` 基线、`N1`–`N5`（_node_block 一支）、`F1`–`F7` / `F2c` / `F3c`（NAMED_FUNCS 一支）、`S0`–`S9`（分支形）、`T1`–`T6`（NF 标注）逐格 `✓ <编号> <说明>：rc=N；红的是 ✗ …`；`二、空转对照` 7 条 `✓ <护栏>：<旧格> 旧口径 rc=0（…）→ <现行格> 现行 rc=1（只有护栏那一行红）`；`三、靶子落点` 逐支 `✓ <文件> <函数>：<签名处> → <真身处>`。每格都是把当前工作树的已跟踪文件（含未提交改动，`git stash create`，不动 stash 列表）检出到临时 worktree、施变异、跑**整道** `check_symbols`，比 rc 与全部 `  ✗` 行（期望的须出现，期望外的一条也不许有）；跑完删 worktree。约一分钟（31 格）。
- 口径（lane auditfix3）：审计 audit1 判 cs12 / cs11「半实」——_node_block 两处调用都是正向断言、(文件, 名字) 只有 `advance_days` 一支同名，改名时正向断言先红，护栏在现状下没有能单独触发的实例。护栏只在「反向断言 + 改名」时是唯一的红，所以各立一支真实的：① check_symbols 十一节「底图 / 外层横排 / 中区开场不收起」（`Background` / `HBoxContainer` / `CenterArea` 三块 Main.gd 从不改 visible，块里不许 `visible = false`）；变异 = 全仓把 `CenterArea` 改名 `CenterStage`、只有这条反向断言没跟，再收起中区——现行只有十三节「取场景节点块 … 取不到」一行红，`_node_block` 退回 cs12 前（不记账）rc=0。② 船屋 `"advance_days" not in yard_fn`；变异 = 全仓把 `GameManager.advance_days` 改名 `pass_days`（`Calendar.advance_days` 不动），check_symbols 里只改跟着红的正向断言（赴试 / 誊录 / 发现调查）、按自扫提示补登 `pass_days`，两行反向断言没跟，再让船屋推一天——现行只有「advance_days 在 GameManager.gd 已无定义，别处还有同名」一行红，NAMED_FUNCS 退回 cs11 前（scripts/ 下有定义就算）rc=0。③ `F6` / `F7`：自扫收分支形反向断言（见 §三.1），新写一条 `if "_monsoon_short(" in yard_fn:` 不登记，现行漏登判红、退回旧扫法 rc=0。④（lane auditfix5）`F2c` / `F3c`：② 之后再按红字把 `advance_days` 改登到还有定义的 `Calendar.gd` 下——现行只有「船屋两行（`"advance_days" not in yard_fn / switch_fn`）的断言标明指 scripts/GameManager.gd 的 advance_days，NAMED_FUNCS 却登在 scripts/core/Calendar.gd」一行红，不查 NF 标注（auditfix5 前）rc=0，即 auditfix3 @1494633 实测的缺口。⑤ `S1`–`S7`：分支形七形（条件折多行 / ✗ 在 else 支 / ✗ 不在紧下一行 / `match … case True` / `case _ if …` 守卫 / `any(…)` 元组折行 / `_calls` 与 `re.search` 当条件）各插一条点到 `_seal_mark`（只 Main 一处定义、未登记）的反向断言，逐形只有漏登一行红；`S8` 七形一起现行红、`S9` 同 S8 退回 auditfix3 口径（单行条件 + 下一行 ✗）rc=0；`S0` 是 F6 那条单行形在 auditfix3 口径下照样红（旧口径补丁如实还原，不是删光了扫描）。⑥ `T1`–`T6`：船屋那行标注掉了 → 「没标」红 / 不查标注 rc=0；Economy 新加一支 `record_discovery`（日后出现同名）→ simulate_run 那条 `any(tok in sim_src …)` 反向断言「没标」红 / 不查标注 rc=0；接收者写错、标错行各一格。各支另有「缺陷本身判红」「改名跟全 + 缺陷由反向断言本身判红」「改名跟全、无缺陷 rc=0」三格，证明变异本身不带出别的红。lane 加跑档（不进一键跑）：要 git worktree、约一分钟，只在动这几道护栏或它们的靶子时有意义；靶子漂移一类另由 check_symbols 十四节「落点预检」每次一键跑判（lane cs27，见下「生命周期」）。
- 管不到的（lane auditfix3 实测，lane auditfix5 收窄）：auditfix3 时 NAMED_FUNCS 登在哪个文件下全凭登记的人——② 的变异里把 `advance_days` 改登到 `scripts/core/Calendar.gd` 下即 rc=0。auditfix5 起同名多处定义的名字须在断言行标 `# NF: 接收者.名字`、与登记一致（④ `F2c` 现红）；剩下管不到的只有「连断言行的标注也改成 Calendar」这一手：那是在断言那一行明着改指向，机判不了（要知道断言读的取体变量取自哪份源码，check_symbols 里没有统一写法），落在 diff 里由评审看。
- 常见红因：`变异没落上`——check_symbols / Main.gd / ShipyardPage.gd / Main.tscn 里变异锚的那几行改了（例如船屋断言改写、`_node_block` 改了记账写法；lane main10 把 `_setup_shipyard` 拆去 ShipyardPage 后，船屋推一天的变异原先还往 Main 的一行转发里插，F1–F4 连带出一串转发判据的红——61e17bf–5d5920c 七笔全红，auditfix5 c020050 手改靶子才绿；lane cs24 起插行变异按当前源码顺一行转发找真身，见下），照新源码改 `CASES` 里的变异；某格 `多 ✗ …`——别的断言也开始读被改名的对象（正向断言会先红，这支就不再是「唯一的红」，换一支变异或把新断言算进期望）；空转对照 `应 0 → 1` 而现行格 rc=0——护栏被放宽了；`零、` 里 `✗ K<n>`——locate_body 或 func_body.forward_of 的判据改了，合成样本与期望对不上。
- 靶子漂移（lane cs24）：往函数体插行的变异（现只船屋推一天 `f_yard_step`）靶子写 check_symbols 读的那支（`Main.gd` 的 `_setup_shipyard`），`locate_body` 按当前源码找真身：签名须恰好一处；体是一行转发（`func_body.forward_of`，与十三节同一判据）就跟——`_K.fn(…)` 顺 `const _K := preload("res://…")` 到拆出件、不带点号的是同文件别名，至多 4 层；找不到 / 同名多处 / 转发目标不是 preload 常量（autoload、形参）/ 签名同行带体 → `变异没落上` 判红。原先按签名行直插，Main 留下的一行转发照样「落上 1 处」（`K0` 复现这一形状），下一刀再拆靶子不用手改。其余变异是按行替换 / 全仓改名，靶子漂了替换处数就不对（`sub` 须恰好 n 处）或期望的 `✗` 行对不上，不会静默绿。环境问题退 2：不在 git 仓库、PATH 里没有 git（cs24 前抛 FileNotFoundError 退 1）、建不了 worktree。

- 生命周期（lane cs27，auditfix7 W8）：按 §五 四件套逐件判档——

  | 件 | 判据 | 本道实测 | 结论 |
  |---|---|---|---|
  | 入册 | 进 `REGISTRY`、写 `when` | auditfix3 起在册（lane 档） | 已做 |
  | 必跑 | §五.2 三条同时成立：自己判不准 / 1 秒量级 / 只读不写盘 | ① 判不准：成立（W8 就是拆 Main 的 main10 不知道要跑）；② 快：**不成立**，全量 31 格 94–108 s（10 路并发负载，lane cs27 实测；空载约一分钟），一键跑其余合计约 60 s；③ 只读：**不成立**，每次 `git worktree add` / `remove`（写 `.git/worktrees`、临时盘）、每格 `reset --hard` | **全量不升 must**，留 lane 档 |
  | 自证 | §五.3 护栏型：旧口径格 rc=0、现行格 rc=1 且只有护栏那一行红 | 「二、空转对照」7 对 | 已做 |
  | 跟号 | 靶子被挪了由挪的那一片跟 | 原先没有机制：靶子漂了只在全量里红，全量没人跑（W8） | **补：落点预检进一键跑** |

  **替代机制：拆成两层。** 全量判得出的红分两类：(a) 靶子漂了——变异 / 旧口径补丁落不上（替换处数不对、插行靶子找不到真身），W8 就是这一类；(b) 靶子没动、check_symbols 的判法 / 判词变了——rc、期望 ✗ 字样、空转对照对不上。(a) 不用跑 check_symbols 就判得出：`landing()` 在内存叠层（`Mem`：读主树工作树、写不落盘）里把 `CASES` 每格的变异逐格施一遍、只看落不落得上，再跑「零、」K0–K10，约 0.5 s、不建 worktree——三条升格判据都成立，挂在必跑的 check_symbols 十四节（§一「门禁开关与附属自检」第 7 项），每次一键跑都跑到。(b) 只有全量判得出，按下表的 `when` 跑。

  **谁在什么时候跑它**：

  | 什么时候 | 谁 | 跑什么 | 凭什么知道要跑 |
  |---|---|---|---|
  | 每轮收尾（一键跑第 1 道 check_symbols） | 每一片 | 十四节落点预检（`python3 tools/check_symbols.py` 里自带；单跑 `python3 tools/check_symbols_mutants.py --landing`） | 必跑，不用记 |
  | 十四节红了 | 挪了靶子的那一片（谁挪谁跟，同 §五.4） | 照新源码改 `CASES` → 全量 `python3 tools/check_symbols_mutants.py` rc=0，与挪靶子的代码同一次落地 | 一键跑红字点名格号与靶子 |
  | 动了护栏 / 反向断言 / 判词，或 `check_symbols_mutants.py` / `func_body.py`（`when` ①） | 动的那一片 | 全量 | 按路径判得准（改的就是这几个文件 / 这几节） |
  | 动了变异的靶子（`when` ②：船屋 `_setup_shipyard` 所在的 Main.gd / ShipyardPage.gd、Main.tscn 的 CenterArea、advance_days、船屋两行反向断言） | 动的那一片 | 全量（落点预检绿了也跑：靶子挪了但还落得上时，期望 ✗ 可能跟着变） | 按路径判得准；拆 Main 的刀挪走船屋那一支时 check_symbols「一之零」/ 台账本来就要动 |

  关断开关 `--no-mutants-landing`：全量在变异过的 worktree 里跑 check_symbols，十四节必红（变异本身让别的格落不上），所以 `_run_case` 带它关掉十四节、印一行 `⚠ 落点预检未跑`。**只给全量用**，一键跑命令不许带（gates_md 把 §三 一键跑段、`.claude/todo.md` 验证段与注册表 `cmd` 逐条比，带了即红）。

  **管不到的**：(b) 类在全量之外没有兜底——例：只把十三节判词「取不到」改成「没取到」，check_symbols 绿、落点预检绿，全量 N2 `缺 ✗ …取不到…` rc=1（lane cs27 V3 实测）；这类改的是 check_symbols 自己的判词，落在 `when` ①，按路径判得准。事故由来见 §五.5 例三。

### 24. check_data_family（`tools/check_data_family.py`，data/ 同族文件结构门禁）
- 读：先 `== 零、变异自检`（GATES §五.3，每次都跑）：内存里逐格改数据 / 清单 / 源码、跑下面同一套检查，`✓ N 格全对：同族变异 k 格判红且只红在该文件，非族 / 对照 m 格与基线一致`（格数随 families 数与清单 `mutant_skip` 走；w20-c2 收 port_beats 进 families 后 37 格），`--mutants` 逐格打印（含登记跳过的格及其原因）。再 `== 普查`：data/ 下 F1–F3 候选（带唯一字符串 id 的条目表、字段指回同表 id、scripts/ scenes/ 的代码读它）都登在 `tools/data_family.json` 的 `families` 或 `not_family`；候补 `watch`（w20-c2 起为空——port_beats.json 已按拍板 E-10 接回运行时升入 families）登了的按 key 判 F1 / F2 须成立、F3 一成立即红。每个同族文件一段 `== data/<文件>`：F1–F3 仍成立，再逐项 `✓ 一、字段齐备 / 类型` `✓ 二、引用 id 存在`（无向图另有 `✓ 二之一、单向登记`）`✓ 三、自引用覆盖`（`普查 a 路过半 + b 路部分命中`）`✓ 四、无孤儿`（`可达 a / n；不可达 k = 形放过 x + 已登记基线 y`）。`--survey` 另打 data/ 全部 json 的普查表。
- 口径（lane seq4）：lane seq3 在 verify_story_data 里给 scenes.json 立的结构门禁（字段 / 类型 / 引用 / 孤儿）参数化成「一个脚本 + 文件清单」。同族现为 `scenes.json`（`choices[].next` / `investigations[].next` 成边，港卡门只有 `Main.PROLOGUE_ONLY_FACILITIES` 成边；入口 = `start_scene` + 港 id + 升章 / 结局幕 + `load_scene("…")` 字面量）与 `ports.json`（`connections[]` 按无向成图，入口 = `GameState.last_port` 缺省值）；`port_beats.json`（w20-c2 起，见口径⑦）与 `characters.json`（有自引用但图无入口，登 `not_family`）。scenes 的 42 个不可达幕 = 3 个 `deprecated`（形放过）+ 39 个基线，基线直接读 `verify_story_data.SCENE_ARCHIVE`（与 seq3 共用一份，只减不增归那边的 `SCENE_ARCHIVE_MAX`）。scenes 专属的在册取值、效果定型、旗标有人写、不跳 deprecated 等仍只在 verify_story_data（必跑）里。lane 加跑档（不进一键跑，口径仍 16 道）。
- 口径（lane seq6，接 seq4 待议六条）：① `ports.json` 单向登记 3 对判留（运行时只有 `Voyage.is_known_route` 与 `MapView._draw_lanes` 读 connections，都按无向认；实测补齐对侧 sim / endgame / economy 输出逐字节不变——补不补归数据片，门禁片不改数据），钉成 `one_way_ok` 基线，新添单向 / 基线补齐都红；② scenes 的形状只在清单写一份：verify_story_data 不再自带 `SCENE_SHAPES` / `SCENE_SUB_SHAPES` / `SCENE_FIELD_TYPES`，由 `scene_shapes_from_manifest` 从清单推出（附 6 类自证）；③ F2 过半阈值只用于判候选，同族文件里部分命中的路径（scenes `location` 29/67、`facilities[].id` 16/36）也须登 refs / not_edges；④ F3 只认代码：.gd 的 `#` 注释不算，文件名前一个字不许是字母 / 数字 / `_` / `-`（原先 `cutscenes.json` 被算成 scenes.json 的读者，scenes 读者 10 → 1、ports 5 → 2）；⑤ 零节锚按形状挑，常量 / 入口 / 基线名读清单，同族文件的通用 7 格自动生成，挑不到锚即红「锚落不上」；⑥ `port_beats.json` 登 `watch`（key = entry），接回运行时即红、照「接入」登进 families。⑦ w20-c2（拍板 E-10 / G1014 选「接回」）：`port_beats.json` 升出 watch 进 families——主键 = entry（图按 entry 走、不按 id），成边路 = `requires.seen[]` 与 `requires.visited[]` 里落回本表 entry 的（`stop_before[]` 记名不成边；requires.visited 的流求一格 ryukyu_bay = 节拍里的「到过流求」针），入口 = `PortBeats.START_ENTRIES` 常量（序章已演的 start + 各港 requires 全空的开场针），章二信针与条件收线针等由运行时按条件路由接演的登 known_orphans；接入顺手修掉两枚悬空（ryukyu_reef 的 entry / stop_before 「hakata」→ 落 hakata_ledger，prepare 的 stop_before 「sail」→ ryukyu_bay）；清单 families 新三个可选键（`f2_min_refs` 钉自引用路数下限 / `mutant_skip`+`mutant_skip_why` 登记形状格跳过——本表「兜底形 + 可达 + 边非空」的形状在全表不存在 / `mutant_register_order` 钉 C1–C3 用哪一族当落点）；运行时接入 = GameManager 按开关 nk1/port_beats_runtime（默认开）读进 port_beats_data，Main._on_enter_port 经 scripts/core/PortBeats.gd 演拍、记 GameState.beats_seen（入存档），story_check 有 _w20c2_port_beats_check 一组断言（开关两边 + 拍序推进 + 收线）。
- 常见红因：删 / 改了幕或港没同步指向它的 `next` / `connections`（`悬空`）；新加字段没登进清单的形（`未登记字段`）；新写的幕没人指向（`是孤儿`，接进入口或标 deprecated）；归档幕被接回主线或删了（`known_orphans 登了 X…`，去 `SCENE_ARCHIVE` 删掉）；data/ 新增了带自引用的 id 表（`满足 F1–F3…却没登记`，照脚本文档串「接入」一段登记）；`✗ 变异自检 <编号>`：检查被放宽了；`锚落不上` = 数据里已没有那种形状的条目（照提示改挑选条件，lane seq6 起 id 改名不再红）；无向图新添 / 补齐单向登记（`X→Y 单向登记` / `基线里的 X→Y 已不是单向`，补对侧或改 `one_way_ok`）；同族文件新添部分命中的引用字段（`（未过半…）…却没登`）；watch 候补被运行时读了（`已被运行时读…登进 families`）；`锚落不上` 而清单已登 `mutant_skip` 的格 = 该表的图就没有那种形状（格不落空、写明原因）。

### 25. probe_pressure（`tools/probe_pressure.py`，探针压帧双档结论一致）
- 读：`零、判据自检` 一行 `✓ N 对样本判对…读数掩码对`；`一、逐支双档` 每支一行 `✓ <探针>：两档一致绿——档 0：绿 n/n（s） ｜ 档 300：绿 n/n（s）`，红的是 `✗ <探针>：两档结论不同——…`，下挂 `rc：档 0 = 0 · 档 300 = 1` / `只在档 0：✓ 04_x.png` / `只在档 300：✗ 04_x 截图时墨幕已过停拍` 这类差异行；`✗ …：两档同红`（探针自身两档都红，红因看该探针 / 截图门禁）；`✗ …：跑不成`（某档没 JSON 行 / 超时 900 s）。汇总行 `共 N 支：一致绿 … / 两档结论不同 … / 两档同红 … / 跑不成 …`，末行 `结果：全部通过` / `结果：N 项问题`。逐跑的 JSON 行与日志落 `--out`（默认系统临时目录下 `probe_pressure/`）的 `L<档>/<探针>.json|.log`，截图落 `L<档>/<子目录>/`，汇总 `summary.json`。
- 口径（lane gd25）：探针集 = `tools/` 下已跟踪 `.gd` 里代码行调了 `ShotGate.frame_pressure(` 的（与 §三.19 gates_md「接 shot_gate 的都挂压帧」同一口径：截图册 25 支 + 定向探针 6 支——letterbox_signal / qa_yard_transition 与船近景四支 japan_ship_probe / ship_dashi_probe / ship_exquisite_probe / shot_champa_ship，现共 31 支），新探针挂上压帧即入集。每支在每档跑一次 `godot --quiet --path . -s res://<探针> -- --json`，各给一个空的 `XDG_DATA_HOME`（user:// 从零起，两档起点相同、`--jobs` 并行不串档），比结论：exit_code、error、有无 SCRIPT ERROR、逐条 checks（ok / fail / warn + 名字；名字里的 `ms=`、`N ms`、`N s`、`N 帧`、`frames=` 读数掩成 `#`，计数如 `caption=1` 不掩）。没接 `--json` 的探针（现只 qa_yard_transition：`extends Node`，按同名 `.tscn` 起，`-s` 起会弹 xmessage 挂住）在脚本 `TEXT_PROBES` 登记人读判词正则（逐路 `FO_CASE <路> <判词>` + 末行 `YARD_TRANSITION_PROBE OK|FAIL k`），不加 `--quiet` 跑、按判词造同形结论；新探针没接 `--json` 又没登记的判「跑不成」。档默认 **0 与 300**：必须一档不封顶、一档封顶——每帧 delta 最多 8/60 s，慢过 7.5 fps 后游戏时间每帧恒定，150 与 300 两档相位落在同一帧（lane gd20「四」），数固定帧数碰运气的探针在两个封顶档下照样一致；`--levels` 不同时含两类只打 `⚠`。300 在已测各支墙钟上界之内（最紧 letterbox_copy ≈ 625 ms / 帧，见 `tools/probe_clock.gd` 头注「三」）。满载机器上档 0 也可能跑进封顶区，每跑墙钟秒数都印出来。
- 与 gd24 ShotGate 收尾兜底、gd20 `shot_consistency` 的分工：gd24 兜底在**进程内**看 probe_clock 的账（有等待撞了墙钟上界而没判红即补红），等待不经 Clock（数固定帧数）它看不见——本门禁不看探针怎么等，只比两档跑出的结论，一档绿一档红、红的行不同都判红。`shot_consistency` 比**像素**（两个已截目录逐张 8×8 格），抓「两档都绿、截的却不是同一个画面」，不跑探针、不看 rc / checks，没截图的信号探针比不了；本门禁不比像素，两档都绿而画面不同它不报。两者不重复，结尾 `二、交接` 印出对 `L0` / `L300` 两目录跑 `shot_consistency` 的命令，要看像素接着跑。
- `--mutants`（反向变异自证）：当前工作树已跟踪文件（含未提交改动，`git stash create`）检出到临时 worktree，导入一次，`B0` 未变异两支须两档一致绿；`M1` qa_title_probe 墨幕停拍改回数 36 帧（gd14 前原写法）、`M2` letterbox_signal_probe `_settle` 不等 finished 改为先停 40 帧——须判「两档结论不同」；跑完删 worktree。约 5 分钟。`变异没落上` = 两支探针源码改了，照新源码改 `MUTANTS`。
- lane 加跑档（不进一键跑）：全集 31 支 × 2 档（lane gd25 实测时 26 支约 25 分钟，`--jobs 2`），要 `DISPLAY`；动探针的等待写法、`probe_clock` / `shot_gate` / `combat_probe_stage` 时跑全集，只动一两支用 `--only`。
- 常见红因：探针有一处等待是数帧（或撞了上界不看返回）——档 0 截在相位里、档 300 相位已过（或反过来），修法是按信号 / 相位等（`Clock.until` / `wait_hold`，见 probe_clock 头注）；跑时机器满载到档 300 越过某支墙钟上界——该支会两档不同且档 300 带 `error=wall_clock`，降负载重跑或查上界表；截图张数随档不同（某档少截一张）。

### 26. ledger_refs_mutants（`tools/ledger_refs_mutants.py`，台账格式硬校验与拍板清单输出确定序的变异对照）
- 读：`一、台账格式硬校验`——`C0`–`C3′` 对照（C3 前三刀段改写成三节须绿、C3′ 刀序起点写死回第四刀须红）、`M1a`–`M5` 逐格变异（现行）与带 `′` 的同一变异退回 cs23 前、`M5t` / `M5t′`（第四刀删表：现行 / `NO_TABLE_OK` 放行退回）、`N1` / `N2`（第四 / 第五刀补的表漏列一支 / 行段写错），逐格 `✓ <编号> <说明>：对账 rc=a，--write rc=b（写了盘），写后对账 rc=c；红的是 ✗ …`；`二、输出确定序`——`D0` 基线、`D1` 清单前 8 处 `scripts/Main.gd:N` 号 +1 不提交、`D2` 同一脏树 `--since HEAD`、`X1` / `X2` 同 D1 / D2 但两处排序都去掉，逐格 `✓ <编号> …：rc=1，⚠ / ✗ k 条，stdout n 种（md5…）`；`三、空转对照` 18 条 `✓ … 旧口径 … rc=0 → … 现行 rc=1、不写盘` / `✓ 刀序起点：C3′ … rc=1 → C3 … rc=0` / `✓ 输出确定序：X1 … 不止一种 → D1 现行逐字节同`。每格都是把当前工作树的已跟踪文件（含未提交改动，`git stash create`）检出到临时 worktree、复位、施变异再跑；跑完删 worktree。约 40 秒（45 格，一节每格跑 gen 三遍，二节每格跑 check_decision_refs 五遍）。
- 口径（lane cs25，固化 lane cs23 待议 ③ 的仓外探针 `/tmp/cs23/{mut_gen,det,mut_det}.py`）：一节比的是 cs23 的那个缺口——台账写坏时原先那一刀 / 那一行被正则漏掉，重算跟着少，`--write` 照写、gen 自己绿。所以每格跑三遍：对账、`--write`、写后对账，现行须三步都红且 `--write` 不写盘，旧口径（`_check_first_knifes` / `_check_ledger_shape` 两处调用删掉）须写后对账 rc=0；M1b / M1c / M4a 旧口径下游本来就红（节标题写成 `###` 后那节并进上一刀、cs18 / cs22 红），只列现行格。二节比 cs23 的另一处：`since()` 配对取 `ko.keys() & kn.keys()`（集合，遍历序随 PYTHONHASHSEED 变），有 2 处以上 ⚠ / MISMATCH 时同基连跑行序不同。种子固定为 0 / 1 / 2 / 3 / 42，本门禁的结论逐次相同；两处排序（`Lines.flush` 的 `sorted`、`pairs.sort`）只去一处时输出仍确定（cs23 实测另一处兜得住），变异两处一起去。⚠ / ✗ 行不到 2 条的格比不出行序，记「变异没落上」。
- 变异锚按形状定位（lane cs26）：原先锚在台账 / 脚本的整行文字上，改一个字（节标题日期或题文、函数表形参名、前三刀件的说明、调用行加行尾注释、lambda 变量名）台账和脚本都还对，本门禁却「变异没落上」（cs26 实测 9 处，无一处「改了仍绿」）。现在只锚刀号（第四 / 第五 / 第十一刀——台账只追加、刀序 ③ 硬校验，刀号一改 C0 先红）与形状：「## 第N刀（」起头的标题行、那节函数表最后一支（带行段的取带行段的）、「已拆（前N刀…）」段第一件、`_check_first_knifes(` / `_check_ledger_shape(` 调用行、紧跟「没有函数表」的那个 `if`、`sorted(self.rows, key=lambda …)` 与 `pairs.sort(…)`；期望 ✗ 字样（函数名、行段、件数、下一刀的刀号）由定位到的内容现算（`Facts`）。定位不到、不止一处、替换前后相同，仍判「变异没落上」。刀序起点（lane cs26 ②）：gen 按「已拆（前N刀…）」段的 N 推，段不在从第一刀起，C3 / C3′ 与 M2c / M2d 守这一条。D2（lane cs26 ③）改相对基 `--since HEAD`，⚠ / ✗ 条数由变异自己造出，不随清单历史变、不会过期。
- lane 加跑档（不进一键跑，口径仍 16 道）：动 `gen_main_splits.py` / `check_decision_refs.py` / `ledger_refs_mutants.py`，或改台账「已拆（前三刀…）」段、第四 / 第五 / 第十一刀节的结构（增删函数表行、改节标题形状、行段写法），或拍板清单的 `scripts/Main.gd:N` 引用增删 / 改指时跑；只改说明文字不必跑。靶子漂移一类另由 check_decision_refs「零之二、落点预检」每次一键跑判（lane w19-g8，见下「生命周期」）。
- 常见红因：`变异没落上`——按形状也定位不到：第四 / 第五 / 第十一刀节标题不止或不到一处、那节没有函数表行、前三刀段认不出，或两支脚本里调用 / 排序的写法变了形（如 `pairs.sort` 改成 `pairs = sorted(…)`），照新形状改 `M` / `GEN_CASES` / `d_unsort` / `g_pre_*`；某格 `多 ✗ …`——台账多了一刀 / 一节，变异带出了新的连带红，核实是连带就补进 `Facts.want`；`⚠ / ✗ 行只有 k 条`——d_dirty 取到的清单号不到 8 处或改号自证不再逐对比；现行格 rc=0 或 `--write` 写了盘、D 格 stdout 不止一种——对应的硬校验 / 排序被放宽或删了。

- 生命周期（lane w19-g8，照 §三.23 cs27 的做法；cs26r 遗留 ③）：按 §五 四件套逐件判档——

  | 件 | 判据 | 本道实测 | 结论 |
  |---|---|---|---|
  | 入册 | 进 `REGISTRY`、写 `when` | cs25 `06490c7` 起在册（lane 档） | 已做 |
  | 必跑 | §五.2 三条同时成立：自己判不准 / 1 秒量级 / 只读不写盘 | ① 判不准：**成立**——靶子在台账第十一刀函数表、清单 `scripts/Main.gd:N` 引用上，拆 Main / 跟号的片天天在动，原 `when` 只写「动两支脚本 / 改那几节结构」，改行段写法、清单引用改指拆出件的片不知道要跑（W8 同形）；② 快：**不成立**，全量 63 项（45 格 + 18 条对照）44.8 s（负载约 10，lane w19-g8 实测；cs26r 实测 38–44 s），一键跑其余合计约 60 s；③ 只读：**不成立**，每次 `git worktree add` / `remove`、每格 `reset --hard`，一节 `--write` 写临时树 | **全量不升 must**，留 lane 档 |
  | 自证 | §五.3 护栏型：旧口径格 rc=0、现行格 rc=1 | 「三、空转对照」18 条 | 已做 |
  | 跟号 | 靶子被挪了由挪的那一片跟 | 原先没有机制：靶子漂了只在全量里红，全量没人跑 | **补：落点预检进一键跑** |

  **替代机制：拆成两层**（同 §三.23）。(a) 靶子漂了——按形状也定位不到：「## 第十一刀（」节标题不到 / 不止一处、那节没有带行段的函数表行、前三刀段认不出、gen 的 `_check_first_knifes(` / `_check_ledger_shape(` 调用行或「没有函数表」那个 `if` 改了形、本脚本的 `sorted(self.rows, …)` / `pairs.sort(…)` 换了写法、清单 `scripts/Main.gd:N` 不到 8 处；(b) 靶子没动、gen / check_decision_refs 的判法 / 判词变了——rc、期望 ✗ 字样、写盘、确定性、空转对照对不上。(a) 不用跑 gen / check_decision_refs 就判得出：`ledger_refs_mutants.landing()` 在内存叠层（`Mem`：读主树工作树、写不落盘）里把 `GEN_CASES` / `DET_CASES` 每格的变异与旧口径补丁逐格施一遍、`Facts` 现算一遍，只看落不落得上；外加「零、」Z1–Z5 预检自证（把真树的靶子按合法 / 等价写法挪一下，预检须点名对应格没落上，放宽了就 `预检空转` 红）。约 0.1 s、不建 worktree，三条升格判据都成立，挂在必跑的 check_decision_refs「零之二」（§一「门禁开关与附属自检」第 8 项），每次一键跑都跑到。宿主选 check_decision_refs 不选 check_symbols：二节本来就在变异过的树上跑它（关断开关真有人用），清单引用是靶子之一、它本来就读，且 check_symbols 是多片共改的大文件。(b) 只有全量判得出，按下表的 `when` 跑。

  **谁在什么时候跑它**：

  | 什么时候 | 谁 | 跑什么 | 凭什么知道要跑 |
  |---|---|---|---|
  | 每轮收尾（一键跑末条 check_decision_refs） | 每一片 | 零之二落点预检（`python3 tools/check_decision_refs.py` 里自带；单跑 `python3 tools/ledger_refs_mutants.py --landing`） | 必跑，不用记 |
  | 零之二红了 | 挪了靶子的那一片（谁挪谁跟，同 §五.4） | 照新形状改 `M` / `GEN_CASES` / `DET_CASES`（或 `DRILL`）→ 全量 `python3 tools/ledger_refs_mutants.py` rc=0，与挪靶子的代码同一次落地 | 一键跑红字点名格号与靶子 |
  | 动了 gen_main_splits / check_decision_refs / ledger_refs_mutants（`when` ①） | 动的那一片 | 全量 | 按路径判得准 |
  | 动了变异的靶子（`when` ②：台账前三刀段、第四 / 第五 / 第十一刀节的结构，清单 `scripts/Main.gd:N` 引用增删 / 改指） | 动的那一片 | 全量（落点预检绿了也跑：靶子挪了但还落得上时，期望 ✗ 可能跟着变） | 按路径判得准；拆 Main 改台账、跟号改清单的片本来就要动这两份 |

  关断开关 `--no-ledger-landing`：二节在变异过的 worktree 里跑 check_decision_refs（X1 / X2 去了排序，预检必红），所以 `_det_case` 带它关掉零之二、印一行 `⚠ ledger_refs_mutants 落点预检未跑`（不计入二节的 ⚠ / ✗ 条数，免得替变异凑数）。**只给全量用**，一键跑命令不许带（gates_md 把 §三 一键跑段、`.claude/todo.md` 验证段与注册表 `cmd` 逐条比，带了即红）。

  **管不到的**：(b) 类在全量之外没有兜底——例：gen 的红字「刀序不对」改成「刀序不符」（cs26r A12），gen / check_symbols / check_decision_refs 全绿、落点预检绿，全量 C3′、M1a、M1b 等 11 格期望的 `✗ …刀序不对…` 对不上、rc=1（lane w19-g8 V5 实测，父版同）；这类改的是 gen 自己的判词，落在 `when` ①，按路径判得准。

### 27. qa_pirate_boat_probe（`tools/qa_pirate_boat_probe.gd`，海寇快船 / 夺船入列 / 船图契约与 3D 船身）
- 读：逐条 `  ✓ …` / `  ✗ …`，末行 `QA_PIRATE_BOAT_PROBE PASS（0 项不合；截图 0 张）` / `…FAIL（k 项不合；…）`。五段：一、SeaChart 两条敌船条目形状；二、海寇一战（旗舰 / 敌船船身接 `ShipHull3D` 视口、船图契约、两艘都夺下、末艘收战）；三、元军哨船一战（type 不动、sprite 传下去、船名「海鹘」）；四、船图契约拿未进树的 `Ship.tscn` / `PirateShip.tscn` 实例验有图就用、缺图回落（期望 `_want` 按 `assets/ship_<id>.png` 在不在现算，收图不变红）；五、存档位 93 存读带海鹘与快船的船队（跑完删）。末条 `本进程无 SCRIPT ERROR` 由探针自挂的 Logger 数。`-- --json` 原生机读（`tools/gate_report.gd`）；`DISPLAY=:2 … -- --shots <目录>` 另截海战 5 张给人看（不接 shot_gate、不入截图册），有窗口时改验「夺船」题签副题写白刃经过、有题签时浮字不再说夺船那句（lane w19-g1 `ae27f4b`），headless 验夺船句走浮字兜底。
- 口径（lane w19-g3 跟现行代码）：夺船存名沿用敌船名「快船」——`Fleet.prize_name`（「快船・一」）在库但本地线 WorldMap 没调，V0928-10 待拍板；拍了、改了起名，这道门禁照拍板结果改期望。白刃必胜的手段是**先停士气挂件**（`wm._morale` 置 `PROCESS_MODE_DISABLED`，同 lane fx8 在 patrol 里的做法）再清零敌船水手：不停的话窗口下接舷停拍 0.42 s 里敌船降幡、走受降（下场 `struck`），headless 下挂件不跑物理帧才碰巧绿。海战里 Sprite2D 贴的是 3D 宋船的 SubViewport 视口，不是 `ship_<id>.png`，所以战中不再比贴图路径，改判「HullRig 挂 ShipHull3D、船模载上、帆色合敌我、Sprite2D 贴它的视口」。
- lane 加跑档（不进一键跑，口径仍 16 道）：`when` 见 §一；headless 约 2 s。不升 must：写 user:// 存档位（跑完删），触发条件按路径 / 函数判得准（§五.2）。
- 常见红因：`存名沿用敌船名「快船」…得 快船・一` = 夺船改接了 `prize_name`（V0928-10 落地）而没改期望；`第一艘记下场 boarded…得 [struck]` = 士气挂件没停住（挂件节点改名 / 不再是 `_morale`）或 `_note_fate` 口径变了；`Sprite2D 没贴 3D 视口（得 res://assets/ship_*.png）` / `船模没载上` / `帆色不对` = ShipHull3D 绑定、`assets/ships/song_quanzhou.glb`、场景里 HullRig 的 `sail_crimson` 变了；`海寇生成 k 艘` = SeaChart 条目 `count` 或 `_spawn_enemy` 变了；`本进程无 SCRIPT ERROR（…）` 看那一行的文件与行号。

### 28. perf_baseline（`tools/perf_baseline.py` + `tools/perf_baseline.gd`，帧时 / 峰值内存 / 启动到可玩基线软档）
- 读：`── real 场面（rc=…）──` 下贴 startup / frames / avg / p95 / mem 一行指标 + `  ⚠ …` 软警；末行 `PERF_PY：全部通过（超阈 N 项 ⚠，判红线 0 项…）` / `…N 项未通过`。脚本探针再出一段 `<TAG>_MM startup_ms=… frames=… avg_ms=… p95_ms=… peak_mem_mb=…` 人读行与一行 GateReport JSON（`--json` 时唯一 stdout）。基线表与口径全文见 `docs/性能基线.md`。
- 软档语义：本仓**首份**性能口径，断言**只认**「跑通了 —— 采样帧 ≥ `frames_min`、拿到了 `_MM` 指标行、本进程无 SCRIPT ERROR」；超阈只 `GateReport.warn`（ok=true、rc=0），不进一键跑——**先前没有性能门禁、20 路 lane 共用一台 8 vCPU（load 20+），帧时墙钟随 CPU 供给起伏 30%+，设 must 会天天误红**。指标交给 `docs/性能基线.md` 的人读判词与日后真机 / 静默刻复测。
- `when` 见 §一：动 Main / SeaChart 航行主环 / 渲染管线 / 提高 THRESHOLDS，或定期重测时手跑。命令 `DISPLAY=:2 python3 tools/perf_baseline.py [--scene 场面] [--secs N]`。
- **自带零、判据自检**（`--selftest`）与反向变异：缩一格 `THRESHOLDS` 打中档指标须见对应 `⚠`；`_MM` 正则抓数对得上。
- 常见红因：`✗ real: 采样帧 < 下限` = 探针卡住 / 系统轰满载；`✗ real: 没拿到指标行` = 探针脚本崩溃 / `.tscn` load 失败（如 SeaChart 解析错——别的人 WIP 接得上 / 接不上签名时出）/ 进程被 timeout；`✗ real: 本进程无 SCRIPT ERROR` = 探针 / 同探针路径上的脚本运行错。

## 四、CI 建议步骤

只是建议，**不进 repo 的 CI 配置**（仓库目前没有 CI 文件）。每步退出码非 0 即红；第 0 步就是必跑十六道（含导入步骤），其后是只适合在 CI 里跑的步骤（会写文件 / 要干净工作树）。

<!-- GATES-CI:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 的 CI_STEPS 生成，勿手改 -->
```sh
# 0. 必跑十六条（含导入步骤；= §一「一键跑」✓ / §三「一键人读全跑」；无窗口的 CI 机器 patrol 要配 Xvfb 给 DISPLAY）
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
python3 tools/check_mac_paths.py
python3 tools/check_host_paths.py
python3 tools/check_decision_refs.py
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

## 五、门禁生命周期：入册 / 必跑 / 自证 / 跟号（lane doc10）

§一–§四 写的是「有哪几道、怎么跑、红了什么样」；本节写**一道门禁怎样才算活的**：入册、必跑、自证、跟号四件都做到才算。缺一件，门禁本身做实了也没人会看见它红——独立审计 audit1 的结论就是「实质缺口在门禁的生命周期而非门禁本身」。规矩从哪来见 五.5 的三例事故。本节和 §三 各小节、`.claude/todo.md` 验证段、`COORDINATION.md` 头部模板、`COORDINATION_INDEX.md` 头部口径与 §七 ④（后两份在简报目录，不在 git 里）有重合的地方，**以本节为准**，逐条裁决见 五.6。

### 五.1 入册：进注册表、定档

- **什么算门禁**：能判红绿（退出码 0 / 非 0）、判什么写得出来、要别的 lane 据它下结论的，都进 `tools/gate_json.py` 的 `REGISTRY`。不进注册表的就是专项探针，只在自己的 lane 里跑，别人不认它的绿（§一「不算门禁」表末行）。**脚本入库不等于入册**：没入册的门禁，它的 rc 没人会看（五.5 例一）。
- **入册一次做齐**（前三步漏了哪步，gates_md 就在哪步红）：
  1. `REGISTRY` 条目写全 `id` / `tier` / `kind` / `file` / `judge` / `green` / `red`；lane 档写 `when`，step / no 档写 `why`；开关与附属自检进 `SUBCHECKS`（`marks` 写判词字样，改名了 gates_md 红）；CI 专属步骤进 `CI_STEPS`。
  2. `--json`：Python 门禁接 `gate_json` 的三行转接（check_decision_refs 在 auditfix1 的接法），Godot 门禁接 `tools/gate_report.gd`（§二末）。
  3. `python3 tools/gates_md.py --write` 重生成 §一 / §二批量 / §四；§三 手写小节 `### N. <id>`，编号跟注册表顺序（gates_md 判）。
  4. 定的是 must，另做 五.2 的升格同步。
  5. Verify 贴入册证据：`grep -n <id> tools/gate_json.py docs/GATES.md` 有命中；`python3 tools/gates_md.py` rc=0；带上它的一键跑（lane 档跑 `when` 那条命令）rc=0。
- **四档与 CI 名单**：档由 `REGISTRY` 头注定义，只有 must / step / lane / no 四档。口头说的「ci 档」其实是 `CI_STEPS` 名单，跟档是两回事，一个步骤可以既是 lane 档又在 CI 名单里（check_sidecars、gates_md 就是）。

| 档 | 含义 | 判据 | 现例（数目以 §一「档」列为准） |
|---|---|---|---|
| must | 每轮必跑，进一键跑 | 见 五.2 | 十道 Python + smoke / compile / story / p7 / patrol |
| step | 每轮必跑、最先跑，不判红绿 | 别的门禁依赖它的副作用 | import（lane gd2 由 editor 降级） |
| lane | 按 lane 内容加跑 | `when` 要能**按「改了哪些路径 / 哪类东西」客观判定**；lane 自己判不准该不该跑的，不许放 lane 档，要么升 must，要么别入册 | verify_save_robustness、截图门禁、check_sidecars、gates_md、check_symbols_mutants 等 |
| no | 不算门禁 | `why` 写原因；legacy 条目强制超时（lane gd9） | verify_narrative、p7_smoke、tour |
| `CI_STEPS`（不是档） | 只适合放 CI 跑：会写盘（`--regen`），或要干净工作树 / 导入后的状态 | 本仓没有 CI 文件，§四 只是建议，所以**只挂在 `CI_STEPS` 上的步骤等于没人跑**：CI 步骤必须另有 `REGISTRY` 条目（给出 lane 档和 `when`），或者挂在某道门禁的 `SUBCHECKS` 下，写明什么时候手跑 | check_sidecars / gates_md（lane 档 + CI）；builtin_api 漂移（check_symbols 的 `--regen` 附属自检） |

### 五.2 必跑：什么时候升 must

- **下面三条同时成立就升**。先例两次：lane gd21 升 RefsMacPath、lane cs21 升 RefsHostPath，理由逐字相同；lane auditfix1 让 check_decision_refs 入册即 must，也是同一理由：
  1. **触发条件自己判不准**：lane 自己说不清这次改动该不该跑它。Mac 路径、本机路径恰恰是照抄命令、照抄默认根时顺手带进来的，这时候正想不起来要加跑；拍板清单引了哪几行，挪行的人多半不知道。
  2. **快**：跑一次在 1 秒量级。实测：RefsMacPath 0.23 s（gd21）；RefsHostPath 墙钟 0.70–1.02 s（cs21，负载约 20 / 8 核）；check_decision_refs 0.5–0.6 s（auditfix1）。对照：一键跑其余各道合计约 60 s，patrol 一道就占 24 s。
  3. **只读、不写盘**：只要 python3 + git。会改写入库文件的开关（`--regen` / `--write` / `--fix`）永远不进一键跑，只当修法用。
  另有一条前提：**不许扩大误红面**。未跟踪文件只记 `⚠`（同 check_docs_index），共用工作树里别的 lane 没提交的东西不许把它染红。
- **判定不升的，写清理由和上界**（gd21 brief 的「二选一，要理由」）。例：check_symbols_mutants 全量约一分钟（负载下 94–108 s）、要 git worktree → lane 档，其中判得快的一层（靶子落不落得上，约 0.5 s、不落盘）拆出来挂进必跑的 check_symbols 十四节（lane cs27，五.5 例三）——**全量升不了，就把能升的那一层拆出来升**；ledger_refs_mutants 同理（全量约 40 s、要 worktree），落点预检（约 0.1 s）挂进必跑的 check_decision_refs「零之二」（lane w19-g8，§三.26「生命周期」）；tour.sh 全集 348 s，产物是给人看的 sheet → no 档。
- **升格要同步五处**：
  1. 注册表 `tier` 改 must，然后 `gates_md --write`（§一 必跑句、§二批量块、§四第 0 步随之更新）；
  2. §三「一键人读全跑」段；
  3. `.claude/todo.md` 验证段（与第 2 处同序；gates_md 逐条比这两处，漏一处即红：gd21 / cs21 的接线变异 W1 / W2）；
  4. 原先在 `CI_STEPS` 里的删掉，免得 CI 跑两遍（gd21、cs21 各删了一次步骤 5）；
  5. README 的「N 道」，以及在途 lane 的口径：在 `COORDINATION_INDEX.md` 头部补〔口径注〕（cs21 的做法；历史行照当时口径，不回改）。
  gates_md 只查得到第 1–3 处，第 4、5 处靠人。**降档也是这五处**，还要写明理由：为什么现在自己判得准了。
- **升 must 的前提是 main 尖上它是绿的**。入册时就是红的，先在同一片里把现存的红收到 0 再升（auditfix1 同片做到 DRIFT 47 → 0）。否则一键跑从此恒红，谁也分不清哪条红是新的。

### 五.3 自证：门禁自己会红

- **最低要求**：每道新门禁、每次收紧，Verify 里都要贴**反向变异**：把它声称能抓的缺陷造回去，现行版 rc=1；在父版上做同一变异 rc=0，这就是「改前误绿、改后判红」。审计 audit1 判「做实 / 半实」用的就是这个标准。变异跑完原样复原，`cmp` 或 porcelain 0 为证。
- **规则表型门禁**（按模式表 / 登记表判的）另外**必须自带样本自检**：每次跑都先过这一节，不另开开关。规格照 check_mac_paths 的「零、模式自检」（lane auditfix2）和 check_host_paths 的「零、样本自检」（lane cs21），两份同规格：
  1. 正向样本 `SAMPLES` 必须全判红，**事故原反例原样收进去**（mac 版头两行就是 audit1 追加进 tour.sh 的那两行）；反向样本 `CLEAN` 必须全不判红，边界例要有（`/usr/local/optional`、`${HOME_RATE}`、占位 `/home/<用户>`、行尾注释里写登记根）。
  2. 样本走扫真文件的同一条路（`hits_text` / `judge`），不另写一套判法。host 版的样本放进 `.gd` 代码行、注释行、`.md` 三处各判一次；登记根按 owner / 非 owner / 拼接 / 行尾注释 / 文档串逐格判。
  3. 脚本扫自己，只按行排除模式块和样本块，块形状卡死：每行必须是一条条目，行数 = 条目数；形状不对就整份照扫（fail closed）。块里每行又都必须在零节判红，所以塞不进漏网的路径（gd21 / auditfix2 / cs21）。
  4. 对照：删一条模式，或把模式退回旧版，零节必须先红（auditfix2 R3、cs21 M1；本片在 `ff82b17` 上复跑见 五.5 例二）。
- **护栏型门禁**（内置不了样本的）用外置变异对照，例如 check_symbols_mutants（lane auditfix3）：护栏退回旧口径那一格必须 rc=0；现行那一格必须 rc=1，而且只有护栏那一行红。
- **放行口子要写到期判据**。`⚠ 只记`、`-` 照认这类放行，必须写明什么时候失效，否则就是永久敞口。例：cs13 在 main_splits 里对 `-` 的放行，main8 落地后一直绿着，直到 auditfix1 收成「只在 HEAD 就是拆出 commit 时照认」（auditfix1 变异 V10 / V11）。

### 五.4 跟号：改了被引文件，就把清单跟上

- **对象**：`docs/待策划拍板清单_2026-09-28.md` 反引号里的「文件:行」。check_decision_refs 只管这一份，读法见 §三.22。
- **谁跟：挪了被引行的那一片自己跟**。清单跟号算在任何 lane 的范围内，不另派 decide 片。auditfix1 起它是必跑，每片都会跑到；「改了被引文件」（拆 Main，改 check_symbols / verify_economy / godot_smoke 之类）这个条件现在决定的是**谁来修**，不再决定跑不跑。
- **怎么跟**（dec4 的 `--fix` 四层跟号 + auditfix1 的改号自证 + main10 / main11 的两笔式）：
  1. **代码先提交**。`--fix` 要求所引文件与 HEAD 一致，没提交就拒绝（dec4 T1）。
  2. `python3 tools/check_decision_refs.py --fix`：跟得上的改成新号，头部锚改成 HEAD；跟不上的插「〔跟号待核：锚 X 里是 文件:行〕」。
  3. **人工回读**，口径照 auditfix1 那 4 处：
     - 每处待核按线索（所在函数的新位置、同文件最像的行），`sed -n` 逐行对照旧锚那段和新号那段；认定是同一条断言、同一段内容后再改号、删标记。改法和依据写进 Verify：`清单行 | 旧锚号 | 现号 | 依据`。
     - `--fix` 只改带行号的 token，不动描述文字（如「改 `scripts/Main.gd` `_setup_yamen`」）。照它印出的「旧 → 新」对照表回读、手改（main10 改 EA6-4 / EA9-1）。
     - 有意换指的，在那处引用后括注「原文作 `:旧号`」认账。
  4. **默认跑到 rc=0**：DRIFT 0、待核 0、改号自证 MISMATCH 0。auditfix1 起默认模式就和上一版清单比，不必另跑 `--since`；只有清单跨了好几笔、要对某个基线比时，才加 `--since <改前 HEAD>`。`⚠ 改指未验` 不判红，下次改清单时自然消失。
  5. **清单单独一笔**，显式 pathspec。拆 Main 的，`gen_main_splits.py --write` 回填拆出 commit 也放进这一笔（main10 `c9d0e14`、main11 `ff82b17`）。两笔一次 CAS 落地。代码那笔单看是红的，因为锚必须是真实存在的 commit；一键跑以第二笔之后的 rc 为准。
- **不许**：把 DRIFT 留在 main 上交给下一片；手改头部锚、不跑 `--fix`；为了绿删引用。

### 五.5 规矩从哪来：三例事故

**例一：check_decision_refs 入库了没入册，DRIFT 挂了 1 小时 39 分（缺的是入册 + 必跑）**
- dec3 `b432862`（05:26）入库时 rc=0；下一笔 cs14 `a8ff603`（05:28:45）起就是 rc=1。注册表和 GATES.md 里都没有它，一直到 auditfix1 `7f266d4`（07:06:50）才入册，`c20b3f1`（07:07:35）收到 DRIFT 0。main 上一共红了 18 笔（`a8ff603`…`7f266d4`）。
- 看见了也没人修：`COORDINATION.md` 第 500–519 行里有 8 条 SETTLED 行（cs14 / cr3 / cs11 / main8 / cs16 / gd22 / cr4 / cs17）记了它是红的，多半注一句「非必跑」就收了。**没进必跑，就没有哪一片有义务把它修绿**。
- 复现（lane doc10 在隔离 worktree 里逐个检出实跑）：

| 提交 | `grep -c check_decision_refs tools/gate_json.py` | `python3 tools/check_decision_refs.py` |
|---|---|---|
| `b432862` dec3 | 0 | rc=0，DRIFT 0 |
| `a8ff603` cs14 | 0 | rc=1，DRIFT 6 |
| `26bca91` gd14 | 0 | rc=1，DRIFT 47 |
| `08ca2a4` cs17（auditfix1 的基） | 0 | rc=1，DRIFT 47（可自动跟号 43、要人工 4） |
| `7f266d4` auditfix1 入册 | 2 | rc=1，DRIFT 47（入册那笔还没收清单） |
| `c20b3f1` auditfix1 清单 | 2 | rc=0，DRIFT 0 |
| `ff82b17` main11（本节写成时） | 2 | rc=0，DRIFT 0 |

- 留下的规矩：五.1「入库不等于入册」、五.2「入册时就是红的，先收到 0 再升」、五.4「谁挪谁跟，不许交下一片」。

**例二：check_mac_paths 模式缺口，升了必跑也没人复核（缺的是自证）**
- doc9 `442b2f8`（05:24）立 RefsMacPath，10 条模式，但家目录写成 `$HOME` / `${HOME}` 再拼用户资料库目录的写法、Intel Homebrew 前缀下的 opt 目录都不在表里（资料库分支只认字面 `~`）。gd21 `b9a9040`（06:27）把它升进必跑时，只验了自扫和插一行 Mac 家目录路径（变异 M1–M7），没有复核模式覆盖。缺口一直开到 audit1 拿反例打出来，auditfix2 `7181c7f`（06:56）补模式、加零节；期间 main 上 16 笔都带着这个缺口。
- 复现（审计原命令：往 `tools/art/tour.sh` 末尾追加两行再跑门禁；那两行 auditfix2 已原样收作 `SAMPLES` 头两行，这里从那一笔取出，免得本文自己写 Mac 路径被 RefsMacPath 判红。lane doc10 在隔离 worktree 里逐个检出实跑，跑完 `git checkout -- tools/art/tour.sh`，复原后 rc=0）：
  ```sh
  git show 7181c7f:tools/check_mac_paths.py | sed -n '/^SAMPLES = \[/{n;p;n;p;q}' | sed -E 's/^    r"(.*)",$/\1/' >> tools/art/tour.sh
  python3 tools/check_mac_paths.py
  ```

| 提交 | 反例 rc | 输出 |
|---|---|---|
| `442b2f8` doc9 立门禁 | 0 | `结果：全部通过` |
| `b9a9040` gd21 升必跑 | 0 | `结果：全部通过` |
| `abb3f05`（= `7181c7f^`） | 0 | `结果：全部通过` |
| `7181c7f` auditfix2 | 1 | `✗ tools/art/tour.sh：2 行 Mac 专属路径，不在白名单…`；`结果：2 项问题` |
| `ff82b17` 本节写成时 | 1 | 同上（扫 685 个文件） |

- 自证对照（`ff82b17` 上实跑，改完即复原）：
  - 把 PATTERNS 的两行退回 `442b2f8` 版：零节自己红，rc=1，`✗ 正向样本 19 行都被认出（10 条模式）；漏认：<审计原反例两行> | …`（共 8 行），外加 `✗ 独立审计原反例…整段扫出 0/2 行`。这一刀不用等真文件写进来就能抓到。
  - check_host_paths 删掉 `/home/<用户>` 模式：rc=1，`✗ 正向样本 13 行在 .gd 代码行 / 注释行 / .md 三处都判红（1 条模式）；漏判：…`。
- 留下的规矩：五.3「规则表型门禁必须自带样本自检，原反例原样收进去」；五.2 升格时要连覆盖一起复核，不能只验「它会跑」。

**例三：check_symbols_mutants 入 lane 档，靶子被下一刀挪走，红了 60 分钟没人跑（缺的是跟号：靶子漂了没人知道）**
- auditfix3 `aec1ea6`（落地 07:37:37）入库时 rc=0，档位 lane，`when` 只写「动 check_symbols 十三节的护栏或它们守的反向断言」。11 分钟后 main10 `61e17bf`（落地 07:48:36，作者时间 06:41：写在 auditfix3 落地之前的基上，rebase 后落地）把 `_setup_shipyard` 拆去 ShipyardPage、Main 只留一行转发；当时的插行变异按签名行直插，照样「落上 1 处」，插进的却是转发，F1–F4 连带一串转发判据的红。此后 first-parent 7 笔全红（`61e17bf` `c9d0e14` `e2bf505` `ff82b17` `5bd85e9` `d9ab507` `5d5920c`，lane cs24 逐笔实跑），到 auditfix5 `c020050`（08:48:27）手改靶子才绿：**59 分 51 秒**。
- 它当时在哪、谁该跑：lane 档，不在一键跑里。按 `when` 字面，7 笔里没有一笔「动护栏」——main10 / main11 拆 Main、登 NAMED_FUNCS，doc10 / doc11 / cs22 改文档与 gen_main_splits——所以**没有哪一片有义务跑它**；main10 写的时候这道门禁还不存在，它的 brief 与门禁清单里也就没有。auditfix5 改的是 NAMED_FUNCS 自扫（`when` 命中），跑了才撞见、顺手修。审计 auditfix7 在 `ff82b17` 复跑 rc=1，记 W8。
- 本质：`when` 按「谁动护栏」写，漏了「谁动靶子」；而靶子（船屋、Main.tscn、advance_days）在 Main 上，每一刀拆分都可能碰到——触发条件是「自己判不准」的那一类，放 lane 档不合 五.1 的判据。可全量又升不了（慢、写盘，§三.23 生命周期表）。
- 修法（lane cs24 + cs27）：cs24 让插行变异顺转发找真身、落不上判红（这一形不再落歪）；cs27 把「落不落得上」拆成 0.5 s 的内存预检挂进必跑的 check_symbols 十四节，`when` 补上「动了靶子」「十四节红了」两条。复现（lane cs27，隔离 worktree，改完即复原）：船屋那行 NF 标注换成等价写法 `# NF: scripts/GameManager.gd:advance_days`——父版 `dba7dec` check_symbols rc=0（W8 同形：一键跑全绿、全量 T1 / T2 `变异没落上`），现行 check_symbols rc=1（十四节 `✗ … T1 … 变异没落上` 两行）；船屋断言的汇总字样改成「船屋坞位一艘未接上」——父版 rc=0，现行 rc=1（F6 / F7 / S0–S9 十二格）。
- 留下的规矩：五.2「全量升不了，就把能升的那一层拆出来升」；lane 档的 `when` 要写到「动了它读的东西」（靶子 / 样本 / 锚），不止「动了它自己」。lane w19-g8 照此给同是 lane 档变异对照的 ledger_refs_mutants 补了同一层（check_decision_refs「零之二」，§三.26）。

### 五.6 与既有口径的对齐（重复的合并、矛盾的裁决）

| 出处 | 原说法 | 处置 |
|---|---|---|
| §三.20 / §三.21 口径段 | 各写一遍升格理由（自己判不准 / <1 s / 只读不写盘 / 未跟踪只 ⚠） | **合并**：理由统一收到 五.2，两小节只留本道的实测数和「见 §五.2」 |
| §三.22 口径段 | 「先提交代码，再 `--fix`、另提一笔清单，两笔同一次落地」 | **合并**：流程收到 五.4，§三.22 只留修法命令和「见 §五.4」 |
| §三.19 改法 | 「只改注册表再 `--write`；§三 小节、一键跑段、todo 验证段随必跑档改」 | 不矛盾，是 五.1 第 3 步、五.2 第 1–3 处的机械部分；补一句指向 §五 |
| `.claude/todo.md` 验证段 | 16 行命令，与 §三 一键跑同序 | 一致（gates_md 逐条比）；段后补一行指向 §五 |
| `COORDINATION.md` 头部模板「清单跟号」句（lane dec4） | 「改了被引文件的收尾**必跑**…；跟不上又不在本 lane 范围的，SETTLED 行写 DRIFT N 交 decide 片」 | **裁决**：auditfix1 起它是 must，「交 decide 片」等于让 main 尖恒红，这一条**作废**，改为「谁挪谁跟、清单算在本 lane 范围」（五.4）。「必跑」的条件也改成「每片都跑，挪了被引行的负责修」。`--since <改前 HEAD>` MISMATCH 0 改为默认跑 MISMATCH 0（`--since` 可选）。模板句已按此改写 |
| `COORDINATION_INDEX.md` 头部「拍板清单跟号（lane dec4 口径）」 | 同上两句 | 同上裁决；那份索引由 cr 片重生成、各 lane 不改写，所以只补〔口径注 · lane doc10〕，下一个 cr 片重生成时带上 |
| `COORDINATION_INDEX.md` §七 ④（lane cr3） | 「按 ✗ 行的提示改号，并把锚改成自己的 commit；清单不在范围的，SETTLED 行写 DRIFT N 交下一个 decide 片」 | 前半句早已被 dec4 的 `--fix` 取代（dec4 口径里写了「§七 ④ 的做法不变，只是改号不必再手算」），后半句同上**作废**；补〔口径注〕 |
| `COORDINATION.md` 头部「门禁 = Python 7 + editor / smoke / compile / story / p7 / patrol」 | 09-27 的口径 | 已过时。道数以 §一 注册表为准（现在一键跑 16 条：导入步骤 + 十五道）；补〔口径注〕，不改写 |
