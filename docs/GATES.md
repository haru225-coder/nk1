# 门禁总表（GATES）

每轮 lane 收尾都要跑的门禁、各自判什么、红了长什么样、怎么机读。
机读开关 `--json` 由 `tools/gate_json.py` 统一实现（纯 stdlib）；**不加开关时每道门禁的人读输出与退出码一字不变**。

- Godot：`/home/box/.local/bin/godot`（4.6.3，下文写 `godot`）；工作目录为仓库根。
- 退出码语义（人读 / `--json` 相同）：`0` 绿，非 `0` 红。`gate_json.py` 自身参数错为 `2`。
- 带窗口的门禁（patrol、截图探针）须 `DISPLAY=:2`。

## 一、总表

| # | 门禁 | 本地命令 | 判什么 | 绿长相 | 红长相 |
|---|---|---|---|---|---|
| 1 | check_symbols | `python3 tools/check_symbols.py` | autoload 注册与跨文件引用真实存在；各 lane 累积的文案 / 接线契约（源码字符串断言）；探针文件存在 | 末行 `结果：全部通过` | `✗ …` 行；末尾 `结果：N 项问题` + 逐条 `   ✗` 复述 |
| 2 | verify_economy | `python3 tools/verify_economy.py` | 数据完整性（港/货/航线互引）；复刻 Economy/Voyage 公式验行情、税费、航速、新闻冲击 | `结果：全部通过` | `✗` 行；`结果：N 项未通过` |
| 3 | simulate_run | `python3 tools/simulate_run.py` | 开局 1000 钱小艍船端到端一局：卡补给 / 卡舱位 / 卡钱等设计死锁；分船账不变量 | `结果：全部通过　—— 核心循环可闭合…` | `✗` 行；`结果：N 项未通过`（中间 4 格缩进的 `✗ 船i…` 是账目诊断细行，不单独计数） |
| 4 | verify_coastline | `python3 tools/verify_coastline.py` | coastline / sealanes / chart_labels 数据形状；港口贴岸；绕岸航线在海上；海图代码接线；底图尺寸与投影常量 | `环 … · 标注 …` + `结果：全部通过` | `✗` 行；`结果：N 项未通过` |
| 5 | check_assets | `python3 tools/check_assets.py` | 脚本/场景里 `res://assets/…` 引用、PORT_BG/FACILITY_BG、前缀拼接、人物立绘都存在且有 `.import` | `资产引用 N 个…全部存在` + `结果：全部通过`（**过了不逐条打印**） | `FAIL: …` 行；`结果：N 项失败` |
| 6 | verify_story_data | `python3 tools/verify_story_data.py` | news / scenes effects / npcs / 结局年号 / 人物原稿与上屏字段：数据里写的键代码必须接住 | 一行统计 + `结果：全部通过`（**过了不逐条打印**） | `FAIL: …` 行；`结果：N 项失败` |
| 7 | simulate_endgame | `python3 tools/simulate_endgame.py` | 1268 后终局：身份判定、守城胜率、崖山门槛、窗口宽度、「花钱买过关」；比对 GameState/Main 常量 | `结果：全部通过　—— 终局窗口够宽…` | `✗` 行 + `FAIL:` 复述；`结果：N 项失败`；常量找不到时 `AssertionError` 崩（无 FAIL 行） |
| 8 | verify_save_robustness | `python3 tools/verify_save_robustness.py [--source X.gd]` | （lane t2）SaveLoad 守卫存在性与顺序 + 源码驱动模型跑坏档/好档/槽态 fixture + 变异自检 | `结果：全部通过`；可能有 `⚠ 未体检的强类型字段（不计失败）` | `✗` 行；`结果：N 项问题` |
| 9 | editor | `godot --headless --editor --path . --quit` | 工程能打开、资源导入缓存（`.godot/`、`*.import`）刷新 | exit 0，只有进度条 | exit 非 0（**注意：脚本语法错它照样 exit 0，见 §三.9**） |
| 10 | smoke | `godot --headless --path . -s res://tools/godot_smoke.gd` | autoload 起得来、章节/旗标/结局按数据走、headless 零延迟旁路 | `GODOT SMOKE PASS` | `✗` 行；`GODOT SMOKE FAIL` + 复述 |
| 11 | compile | `godot --headless --path . -s res://tools/godot_compile_check.gd` | 清单脚本 `load()` + `can_instantiate()`；场景解析（lane m2：ext_resource / 子资源 / 脚本坏）；守护清单 | `COMPILE_CHECK SUMMARY bad=0/N` | `COMPILE_CHECK FAIL …` 行；`bad=k/N` |
| 12 | story | `godot --headless --path . -s res://tools/godot_story_check.gd` | 新闻按月投放不重复、1268 身份结算恰一次、存档 round-trip、真机抵港路由 | `STORY_CHECK SUMMARY fails=0` | `STORY_CHECK FAIL …`；`fails=k` |
| 13 | p7 | `godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd` | 行会入行 / 贡院赴试 / 誊录：扣费门槛、每章一次、跨月结算时序 | `P7_GUILD_EXAM_SMOKE_OK` | `FAIL …` 行；`P7_GUILD_EXAM_SMOKE_FAIL k` |
| 14 | patrol | `DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd` | 挂主场景走开局、三港、九设施、海图：1280×720 按钮不越界、焦点色、航向牌、终局港口页 | `PATROL SHELL PASS` | `✗` 行；`PATROL SHELL FAIL` + 复述 |
| 15 | 截图门禁 | `DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd`（同法：`vision_letterbox_probe.gd`、`qa_p7_screenshots.gd`） | （lane m3）`tools/shot_gate.gd`：零截图 / 空视口 / 一色空图 / 张数不足一律红；契约模式须显式 `-- --contract` | `<TAG>_OK shots=n/n -> 目录`；契约模式 `<TAG>_CONTRACT_OK…` | `✗ …` + `<TAG>_FAIL k（shots=…）`；headless 下 `<TAG>_FAIL headless（…不是画面回归）` |
| 16 | save_robust_probe | `godot --headless --path . -s res://tools/save_robust_probe.gd` | （lane h1h2 / rt）坏分区退 .bak、只剩 .bak 取标签、两份皆坏不抛错 | `SAVE_ROBUST_PROBE PASS`（大量 `ERROR: 存档结构异常…` 是故意喂坏档，属预期） | `✗` 行 / 非零退出；输出含 `SCRIPT ERROR` 即算失败 |

「七道 Python + editor/smoke/compile/story/p7/patrol」是每轮必跑的十三道（`.claude/todo.md` 验证段）；8、15、16 按 lane 内容加跑。

**不算门禁**（别拿来判红绿）：
- `tools/verify_narrative.py`：P7 剧情闭环旧静态门禁，当前 main 上本来就红（开局链 / borrow_ceiling 等旧契约），未列入必跑。
- `tools/p7_smoke.gd`：旧 P7 冒烟，`borrow_ceiling` 一带早已失配，干净 worktree 也红（lane l1 已记）。
- `tools/qa_*_probe.gd` / `qa_*_screenshots.gd` / `combat_*_probe.gd`：各 lane 的专项探针，只在对应 lane 里跑。

## 二、`--json` 机读输出

### 怎么开

```sh
# Python 门禁：直接加开关（1–8 都有）
python3 tools/check_symbols.py --json
python3 tools/verify_save_robustness.py --source /tmp/old_SaveLoad.gd --json   # 其余参数照传

# Godot 门禁：不改 .gd，由 gate_json.py 包一层（预设 editor smoke compile story p7 patrol）
python3 tools/gate_json.py --godot compile
DISPLAY=:2 python3 tools/gate_json.py --godot patrol
# 任意 res:// 脚本：默认 --headless；带窗口加 --display；用户参数放 -- 之后
DISPLAY=:2 python3 tools/gate_json.py --godot res://tools/vision_stage_probe.gd --display
python3 tools/gate_json.py --godot res://tools/vision_stage_probe.gd -- --contract

# 等价写法 / 兜底
python3 tools/gate_json.py tools/verify_economy.py      # = verify_economy.py --json
python3 tools/gate_json.py -- <任意命令 …>               # 通用解析
```

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

批量巡检示例（CI / 夜巡）：

```sh
mkdir -p /tmp/gates
for g in check_symbols verify_economy simulate_run verify_coastline check_assets verify_story_data simulate_endgame; do
  python3 tools/$g.py --json > /tmp/gates/$g.json
done
for g in editor smoke compile story p7; do python3 tools/gate_json.py --godot $g > /tmp/gates/$g.json; done
DISPLAY=:2 python3 tools/gate_json.py --godot patrol > /tmp/gates/patrol.json
python3 -c "import json,glob;[print(f'{d[\"gate\"]:24}',d['ok'],d['counts']) for d in map(lambda p: json.load(open(p)), sorted(glob.glob('/tmp/gates/*.json')))]"
```

## 三、逐道：怎么跑、怎么读、常见红因

一键人读全跑（与 `.claude/todo.md` 验证段一致）：

```sh
python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py \
 && python3 tools/verify_coastline.py && python3 tools/check_assets.py \
 && python3 tools/verify_story_data.py && python3 tools/simulate_endgame.py
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/godot_smoke.gd
godot --headless --path . -s res://tools/godot_compile_check.gd
godot --headless --path . -s res://tools/godot_story_check.gd
godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd
DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd
```

**共同的坑：工作树是多 lane 共用的。** 别的 lane 未提交的改动（例如正在改 `SaveLoad.gd`）会让你的门禁红。判「是不是我弄红的」：`git worktree add --detach /tmp/x HEAD`，只放进自己的改动再跑（Godot 门禁先 `cp -a .godot /tmp/x/` 省掉重新导入）。

### 1. check_symbols
- 读：按「一、二、…」小节打 `✓/✗`；末尾汇总 `结果：N 项问题` 并复述每条。`--json` 的 `detail` 就是小节名。
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
- 常见红因：代码引用了还没入库的图；新图没跑过 editor 导入（缺 `.import`，先跑 §9）；挪 / 改名资产没改前缀拼接表。

### 6. verify_story_data
- 读：绿时一行统计（结局年号对照 / scenes / news / npcs …）；红时 `FAIL: …`。
- 常见红因：`scenes.json` 新 effects 键 `Main.apply_effects` 没接；结局题头年号落在触发闸外；人物原稿与上屏字段不符（lane l1，见 `docs/人物原稿与上屏契约.md`）。

### 7. simulate_endgame
- 读：`── 小节 ──` 分段 `✓/✗`，红时另有 `FAIL:` 复述。
- 常见红因：`GameState.gd` / `Main.gd` 常量改名 → 正则取不到直接 `AssertionError: 找不到常量 …` 崩（人读只有 traceback；`--json` 给 `exit_code` 条目 + `tail`）；守城 / 崖山数值改动使窗口过窄或能花钱买过关。

### 8. verify_save_robustness
- 读：`一、SaveLoad 源码契约` → fixture 模型 → 变异自检（每个变体都应「判红」）；`⚠` 行不计失败。
- 常见红因：改 `SaveLoad.gd` 守卫顺序 / 函数名而没同步本脚本的抽取规则；新增强类型字段未进 `_check_partitions`（先以 `⚠` 提示）。`--source X.gd` 可对历史版本自证。

### 9. editor
- 读：只看退出码；输出是导入进度条。
- **它不判脚本语法**：本轮实测给 `scripts/FloatingText.gd` 塞语法错，`--editor --quit` 仍 exit 0 且不打任何 ERROR；语法 / 场景解析靠 §11 compile。它的作用是刷新 `.godot/` 导入缓存（新资产、新 `class_name` 后先跑它，check_assets 的 `.import` 也靠它）。
- 常见红因：工程文件损坏、`project.godot` 写坏。

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
- 常见红因：没设 `DISPLAY`；按钮越出 1280×720；设施页 / 终局港口页按钮文案改名（断言按文案找钮）。

### 15. 截图门禁（shot_gate.gd + 截图探针）
- 读：`<TAG>_OK shots=n/n -> 目录`；红时先列 `✗ 真失败：…`，再 `<TAG>_FAIL k（shots=…）`。
- headless 不加 `-- --contract` **必红**（`_FAIL headless …此为环境不具备，不是画面回归`）——这是设计，不是回归。只验契约：`godot --headless … -- --contract` → `<TAG>_CONTRACT_OK`。
- 注意：截图落在**绝对路径** `/workspace/nk1-qa-shots/…`，任何 worktree 里跑都会覆盖同一批证据图。
- 常见红因：空视口 / 一色图（窗口没真正绘制）；张数不足；letterbox 类时序断言（如「出战合拢时画面中线未全黑」）在机器繁忙时可能偶发。

### 16. save_robust_probe
- 读：`✓` 行 + `SAVE_ROBUST_PROBE PASS`；上百行 `ERROR: 存档结构异常 …` 是探针故意喂的坏档，预期存在；`SCRIPT ERROR` 才算失败。
- 常见红因：`SaveLoad.gd` 判坏档 / 退 `.bak` 路径改动；新强类型字段赋错型时先赋值后判型。
