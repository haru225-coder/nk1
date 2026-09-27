#!/usr/bin/env python3
"""门禁机读输出（`--json`）的公共转接层；纯 stdlib，说明见 docs/GATES.md。

两种接法，输出同一形状：
  1. Python 门禁自带开关：`python3 tools/check_symbols.py --json`
     各门禁 import 段后三行 `if "--json" in sys.argv[1:]: … gate_json.maybe_json(__file__)`；
     不带 `--json` 不进这一支、连本模块都不导入，人读输出与退出码与原来逐字相同。带 `--json` 时由本模块起子进程照原样跑一遍，
     捕获 stdout/stderr，再输出 JSON，退出码沿用子进程。
  2. Godot 门禁与任意命令（不改 .gd，外包一层）：
     python3 tools/gate_json.py --godot smoke            # 预设：注册表里的 Godot 门禁与截图脚本（--list 看全）
     python3 tools/gate_json.py --godot res://tools/vision_stage_probe.gd [--display] [-- 用户参数]
     python3 tools/gate_json.py tools/verify_economy.py  # 等同 verify_economy.py --json
     python3 tools/gate_json.py -- <任意命令 ...>
  2b. GDScript 原生 `--json`（tools/gate_report.gd）的消费方（lane gd7）：**stdout 里没有 JSON 行一律判红**
     python3 tools/gate_json.py --native smoke [--timeout 300]          # 预设同 --godot；自动补 --quiet 与 -- --json
     python3 tools/gate_json.py --native res://tools/qa_title_probe.gd --display [-- --contract]
     python3 tools/gate_json.py --native [--timeout N] -- godot --headless --quiet --path . -s res://tools/X.gd -- --json
     python3 tools/gate_json.py --judge /tmp/gates/*.json               # 批量落盘的 stdout 逐个判；缺 JSON / ok=false 即退 1
  2c. legacy 条目（注册表 tier=no，或路径在 tools/legacy/ 下）强制超时（lane gd9）：默认 LEGACY_TIMEOUT 秒（条目可写自己的 timeout，
     如 tour.sh 900 秒，lane gd13），`--timeout N` 可改、不可关；
     到点掐断，照样出 JSON：ok=false、exit_code=124、error="timeout"（p7_smoke 在 SCRIPT ERROR 后不 quit，不加这层会一直挂着）
  3. 门禁清单：`python3 tools/gate_json.py --list` 输出注册表 JSON（REGISTRY + SHOT_PROBES + SUBCHECKS + CI_STEPS）；
     docs/GATES.md §一、§二批量巡检块、§四由它生成，`python3 tools/gates_md.py` 校验、`--write` 重生成。

输出（stdout 只有这一段 JSON）：
  {"gate", "ok", "exit_code", "summary", "checks": [{"name", "ok", "detail"}...],
   "counts": {"total", "pass", "fail", "warn", "engine_errors", "script_errors"}, "cmd", ["errors"], ["tail"]}
  · ok == (exit_code == 0)，与人读模式的退出码同一口径；checks 只是明细，不另立判据。
  · warn 条目（⚠ / COMPILE_CHECK NOTE）ok=true、带 "level": "warn"，不计入 pass/fail/total。
  · engine_errors：Godot 引擎打的 ERROR 类行数；script_errors 是其中 SCRIPT ERROR 行数。只报数，不改判定
    （patrol 的 Vulkan 回落、save_robust_probe 故意喂坏档都会打 ERROR:，属预期）。
  · 红了却没解析到失败行（脚本中途崩、提前 exit）时补一条 name="exit_code" 的失败条目，并附 tail。
  · --native / --judge：原生 JSON 原样转出；没 JSON 行时合成 ok=false、error="no_json"（超时掐断的记 "timeout"；name="no_json_line" 失败条目 + tail），
    exit_code 为进程退出码（0 也改 1）；JSON 与进程退出码对不上、或 JSON 不止一行也判红。
"""
import json, os, re, signal, subprocess, sys, tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
REC_ENV = "NK1_GATE_JSON_REC"
# legacy 条目（tier=no 或 tools/legacy/ 下）跑子进程的强制超时，秒（lane gd9）。p7_smoke 1.7 s 内就走到 SCRIPT ERROR 挂死，
# verify_narrative 0 s 退；60 秒留足余量。到点按 timeout(1) 记 124、error="timeout" 判红
LEGACY_TIMEOUT = 60

# ── 门禁注册表：docs/GATES.md §一（及 §四 CI 块）由它生成（tools/gates_md.py --write），文档与它不一致即 FAIL（tools/gates_md.py）──
# tier：must = 每轮必跑；step = 每轮必跑、先跑但不判红绿的步骤（why 写原因）；lane = 按 lane 内容加跑（when 写何时）；
#       no = 不算门禁（why 写原因）。
# kind：py = python3 tools/<file>；godot = godot <args>；shots = 截图门禁一行（明细见 SHOT_PROBES）；sh = 直接跑的 shell 脚本（<file> <usage>）。
# timeout：legacy 条目（tier=no）的强制超时，缺省 LEGACY_TIMEOUT；marks：输出契约字样，gates_md 判它们还在 <file> 代码行里。
# 改门禁清单（增删、降级、改命令）只改这里，再 `python3 tools/gates_md.py --write`。
REGISTRY = [
    {"id": "check_symbols", "tier": "must", "kind": "py", "file": "tools/check_symbols.py",
     "judge": "autoload 注册与跨文件引用真实存在；各 lane 累积的文案 / 接线契约（源码字符串断言）；探针文件存在",
     "green": "末行 `结果：全部通过`", "red": "`✗ …` 行；末尾 `结果：N 项问题` + 逐条 `   ✗` 复述"},
    {"id": "verify_economy", "tier": "must", "kind": "py", "file": "tools/verify_economy.py",
     "judge": "数据完整性（港/货/航线互引）；复刻 Economy/Voyage 公式验行情、税费、航速、新闻冲击",
     "green": "`结果：全部通过`", "red": "`✗` 行；`结果：N 项未通过`"},
    {"id": "simulate_run", "tier": "must", "kind": "py", "file": "tools/simulate_run.py",
     "judge": "开局 1000 钱小艍船端到端一局：卡补给 / 卡舱位 / 卡钱等设计死锁；分船账不变量",
     "green": "`结果：全部通过　—— 核心循环可闭合…`",
     "red": "`✗` 行；`结果：N 项未通过`（中间 4 格缩进的 `✗ 船i…` 是账目诊断细行，不单独计数）"},
    {"id": "verify_coastline", "tier": "must", "kind": "py", "file": "tools/verify_coastline.py",
     "judge": "coastline / sealanes / chart_labels 数据形状；港口贴岸；绕岸航线在海上；海图代码接线；底图尺寸与投影常量",
     "green": "`环 … · 标注 …` + `结果：全部通过`", "red": "`✗` 行；`结果：N 项未通过`"},
    {"id": "check_assets", "tier": "must", "kind": "py", "file": "tools/check_assets.py",
     "judge": "脚本/场景里 `res://assets/…` 引用、PORT_BG/FACILITY_BG、前缀拼接、人物立绘都存在且有 `.import`",
     "green": "`资产引用 N 个…全部存在` + `结果：全部通过`（**过了不逐条打印**）", "red": "`FAIL: …` 行；`结果：N 项失败`"},
    {"id": "verify_story_data", "tier": "must", "kind": "py", "file": "tools/verify_story_data.py",
     "judge": "news / scenes effects / npcs / 结局年号 / 人物原稿与上屏字段：数据里写的键代码必须接住",
     "green": "一行统计 + `结果：全部通过`（**过了不逐条打印**）", "red": "`FAIL: …` 行；`结果：N 项失败`"},
    {"id": "simulate_endgame", "tier": "must", "kind": "py", "file": "tools/simulate_endgame.py",
     "judge": "1268 后终局：身份判定、守城胜率、崖山门槛、窗口宽度、「花钱买过关」；比对 GameState/Main 常量",
     "green": "`结果：全部通过　—— 终局窗口够宽…`",
     "red": "`✗` 行 + `FAIL:` 复述；`结果：N 项失败`；常量找不到时 `AssertionError` 崩（无 FAIL 行）"},
    {"id": "verify_save_robustness", "tier": "lane", "when": "动 SaveLoad / 存档", "kind": "py",
     "file": "tools/verify_save_robustness.py", "usage": "[--source X.gd]",
     "judge": "（lane t2）SaveLoad 守卫存在性与顺序 + 源码驱动模型跑坏档/好档/槽态 fixture + 变异自检",
     "green": "`结果：全部通过`；可能有 `⚠ 未体检的强类型字段（不计失败）`", "red": "`✗` 行；`结果：N 项问题`"},
    {"id": "import", "gate": "godot_import", "tier": "step", "kind": "godot",
     "args": ["--headless", "--import", "--path", "."],
     "why": "（lane gd2 由 editor 降级）六类故障注入全 exit 0，红由 compile / check_assets 判，见 §三.9",
     "judge": "刷新资源导入缓存（`.godot/`、`*.import`）；须先于 check_assets 与 Godot 门禁跑",
     "green": "exit 0，只有进度条", "red": "**无红长相**（不判红绿）"},
    {"id": "smoke", "gate": "godot_smoke", "tier": "must", "kind": "godot", "file": "tools/godot_smoke.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/godot_smoke.gd"],
     "judge": "autoload 起得来、章节/旗标/结局按数据走、headless 零延迟旁路",
     "green": "`GODOT SMOKE PASS`", "red": "`✗` 行；`GODOT SMOKE FAIL` + 复述"},
    {"id": "compile", "gate": "godot_compile_check", "tier": "must", "kind": "godot", "file": "tools/godot_compile_check.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/godot_compile_check.gd"],
     "judge": "清单脚本 `load()` + `can_instantiate()`；场景解析（lane m2：ext_resource / 子资源 / 脚本坏）；守护清单",
     "green": "`COMPILE_CHECK SUMMARY bad=0/N`", "red": "`COMPILE_CHECK FAIL …` 行；`bad=k/N`"},
    {"id": "story", "gate": "godot_story_check", "tier": "must", "kind": "godot", "file": "tools/godot_story_check.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/godot_story_check.gd"],
     "judge": "新闻按月投放不重复、1268 身份结算恰一次、存档 round-trip、真机抵港路由",
     "green": "`STORY_CHECK SUMMARY fails=0`", "red": "`STORY_CHECK FAIL …`；`fails=k`"},
    {"id": "p7", "gate": "p7_guild_exam_smoke", "tier": "must", "kind": "godot", "file": "tools/p7_guild_exam_smoke.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/p7_guild_exam_smoke.gd"],
     "judge": "行会入行 / 贡院赴试 / 誊录：扣费门槛、每章一次、跨月结算时序",
     "green": "`P7_GUILD_EXAM_SMOKE_OK`", "red": "`FAIL …` 行；`P7_GUILD_EXAM_SMOKE_FAIL k`"},
    {"id": "patrol", "gate": "patrol_shell", "tier": "must", "kind": "godot", "file": "tools/patrol_shell.gd",
     "args": ["--path", ".", "-s", "res://tools/patrol_shell.gd"], "display": True,
     "judge": "挂主场景走开局、三港、九设施、海图：1280×720 按钮不越界、焦点色、航向牌、终局港口页；截图旁证一色判据（lane pg，一色只记 ⚠）",
     "green": "`PATROL SHELL PASS`（前一行 `✓ 截图旁证 n/n 张非一色`）", "red": "`✗` 行；`PATROL SHELL FAIL` + 复述"},
    {"id": "截图门禁", "tier": "lane", "when": "动画面 / UI / 过场", "kind": "shots", "file": "tools/shot_gate.gd",
     "judge": "（lane m3 立、sg2 扩到全部截图脚本，新截图脚本一律接它）`tools/shot_gate.gd`：零截图 / 空视口 / 一色空图 / 张数不足一律红；契约模式须显式 `-- --contract`",
     "green": "`<TAG>_OK shots=n/n -> 目录`；契约模式 `<TAG>_CONTRACT_OK…`",
     "red": "`✗ …` + `<TAG>_FAIL k（shots=…）`；headless 下 `<TAG>_FAIL headless（…不是画面回归）`"},
    {"id": "save_robust_probe", "tier": "lane", "when": "动 SaveLoad / 存档", "kind": "godot", "file": "tools/save_robust_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/save_robust_probe.gd"],
     "judge": "（lane h1h2 / rt）坏分区退 .bak、只剩 .bak 取标签、两份皆坏不抛错",
     "green": "`SAVE_ROBUST_PROBE PASS`（大量 `ERROR: 存档结构异常…` 是故意喂坏档，属预期）",
     "red": "`✗` 行 / 非零退出；输出含 `SCRIPT ERROR` 即算失败"},
    {"id": "check_sidecars", "tier": "lane", "when": "提交新 .gd / .gdshader / 素材，或挪删它们（同车规则：新源文件的侧车同 commit 带上）", "kind": "py",
     "file": "tools/check_sidecars.py",
     "judge": "（lane ag / ag2）按 git 索引：已跟踪 .gd/.gdshader 须有已跟踪 `.uid`，可导入素材须有 `.import`；反向不许只提侧车 / 多余侧车；侧车内容与源文件、场景引用、VRAM 基线一致，uid 唯一；工作树里已跟踪侧车不许漂移。口径表见 docs/侧车口径.md",
     "green": "`结果：全部通过`", "red": "`FAIL: …` 行（缺侧车 / 孤儿·多余侧车 / 内容漂移 / 非基线形态 / 工作树漂移）；`结果：N 项失败`"},
    {"id": "save_migrate_probe", "tier": "lane", "when": "动存档结构 / save_schema", "kind": "godot",
     "file": "tools/save_migrate_probe.gd", "args": ["--headless", "--path", ".", "-s", "res://tools/save_migrate_probe.gd"],
     "judge": "（lane sv）v1 老档读入补字段、回写 v2、原件留 .v1；未来档明确拒读、不退副抄、文件不动",
     "green": "`SAVE_MIGRATE_PROBE PASS`", "red": "`✗` 行；`SAVE_MIGRATE_PROBE FAIL fails=k`；输出含 `SCRIPT ERROR` 即算失败"},
    {"id": "gates_md", "tier": "lane", "when": "动门禁清单 / docs/GATES.md", "kind": "py", "file": "tools/gates_md.py",
     "judge": "（lane gd3 / gd4 / gd5；gd5 加 §二 批量巡检块、`.claude/todo.md` 验证段）本注册表 vs docs/GATES.md §一、§二批量巡检、§四三个生成块逐字一致；注册的脚本都在；接 shot_gate 的截图脚本全部入册；附属自检的开关还在源码里；§三 小节编号对得上；§三 与 todo.md 验证段的一键跑命令与必跑档逐条同序",
     "green": "`结果：全部通过`", "red": "`✗` 行（附首处差异）；`结果：N 项问题`；修法 `python3 tools/gates_md.py --write`"},
    {"id": "verify_narrative", "tier": "no", "kind": "py", "file": "tools/legacy/verify_narrative.py",
     "why": "（lane gd2 挪入 legacy）绑定云端 21ce 未收的 P7 平行实现（`borrow_ceiling` / `_discovery_extra` / `seen_scenes` 主干从未有；开局链截断 monk、删 `chapter` 臂与主干设计相反），合并台账第 14 行即定「留档不入门禁」；主干上恒红 23 项属预期，仍成立的「效果键必须接住」由 verify_story_data 覆盖"},
    {"id": "p7_smoke", "tier": "no", "kind": "godot", "file": "tools/legacy/p7_smoke.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/legacy/p7_smoke.gd"],
     "why": "（lane gd8 挪入 legacy）与 verify_narrative 同源，绑定 21ce 未收的 P7 平行实现（开局链进泉州、港口节拍、`seen_scenes`、`borrow_ceiling`），合并台账第 14 行定「留档不入门禁」；主干上 4 项 FAIL 后在 `borrow_ceiling()` 处 SCRIPT ERROR、不 quit 挂死（干净 worktree 同，lane l1 已记；lane gd9 起 legacy 条目强制超时 60 秒，到点 rc=124 判红）；P7 行会 / 贡院由 p7（`p7_guild_exam_smoke.gd`）接管"},
    {"id": "tour", "tier": "no", "kind": "sh", "file": "tools/art/tour.sh", "usage": "-r <运行副本> [站点…]",
     "display": True, "shots": True, "timeout": 900, "marks": ["TOUR PASS", "TOUR FAIL", "✓", "✗", "TOUR_READY"],
     "why": "（lane gd13 判不进）美术巡检截帧，产物是给人看的 sheet.jpg：每站一个带窗口 Godot（Movie Maker，不能 `--headless`），"
            "全集 21 站实测 348 秒（8 核、负载 8–11；单站 title 17 秒），另要先 `git archive` 出运行副本并导入一次（12 秒）；"
            "只判引擎退出码 / TOUR_READY / 报错计数 / 帧与小样在不在，不看像素——画面回归由截图门禁 24 支探针判。"
            "动 ShotTour / tour_sheet / 过场站点时手跑。输出契约：逐站 `✓` / `✗ …  ← 红因` 一行，末行 `TOUR PASS n/n` / `TOUR FAIL k/n`，"
            "退出码 0 全绿 / 1 有站红 / 2 用法错 · 运行副本不在 · 找不到引擎；`--json` 外包后 checks 逐站一条，强制超时 900 秒"},
]

# 接 shot_gate.gd 的截图脚本（lane m3 三支 + lane sg2 二十支 + 之后各 lane 新接的）。TAG / 张数 / 截图目录从脚本源码现读，不在此抄。
SHOT_PROBES = [
    ("tools/vision_stage_probe.gd", "m3"),
    ("tools/vision_letterbox_probe.gd", "m3"),
    ("tools/qa_p7_screenshots.gd", "m3"),
    ("tools/combat_vfx_probe.gd", "sg2"),
    ("tools/combat_wire_probe.gd", "sg2"),
    ("tools/qa_companion_preview_screenshots.gd", "sg2"),
    ("tools/qa_ending_reread_probe.gd", "sg2"),
    ("tools/qa_chart_hud_screenshots.gd", "sg2"),
    ("tools/qa_wire_vision_screenshots.gd", "sg2"),
    ("tools/qa_chars_wire_screenshots.gd", "sg2"),
    ("tools/qa_title_probe.gd", "sg2"),
    ("tools/qa_port_doors_probe.gd", "sg2"),
    ("tools/qa_drydock_probe.gd", "sg2"),
    ("tools/qa_siege_endgame_probe.gd", "sg2"),
    ("tools/qa_letterbox_copy_probe.gd", "sg2"),
    ("tools/qa_patrol_pack_screenshots.gd", "sg2"),
    ("tools/qa_tavern_news_wall_screenshots.gd", "sg2"),
    ("tools/qa_chapter_promote_probe.gd", "sg2"),
    ("tools/qa_voyage_status_probe.gd", "sg2"),
    ("tools/qa_crew_hire_probe.gd", "sg2"),
    ("tools/qa_discovery_probe.gd", "sg2"),
    ("tools/qa_chars_screenshots.gd", "sg2"),
    ("tools/art/vision_fill_shots.gd", "sg2"),
    ("tools/qa_market_panel_probe.gd", "aa"),
]


# 门禁族：总表「族」列按 kind 定（截图门禁单成一族）；「一键跑」= 必跑档 = docs/GATES.md §三「一键人读全跑」那段命令。
FAMILY = {"py": "Python", "godot": "Godot", "shots": "截图", "sh": "Shell"}

# 门禁开关与附属自检（lane gd4）：不另立一道门禁，随所属门禁（parent，须是 REGISTRY 里的 id）默认跑，或开关手动开。
# oneclick = 随所属门禁的默认命令跑到，即进「一键跑」；marks = 所属门禁源码里必须还在的字样（开关 / 判词改名了 gates_md 判红）。
SUBCHECKS = [
    {"id": "builtin_api 头部自检", "parent": "check_symbols", "lane": "cs3", "oneclick": True,
     "cmd": "python3 tools/check_symbols.py",
     "marks": ["tools/builtin_api.txt", "# sha256 ", "ClassDB 可能已变", "清单链上缺类"],
     "expect": "「二、跨文件引用检查」首行 `✓ 内置清单 tools/builtin_api.txt（godot 4.6.3…）：N 类，Object→Node 链 M 名 + 手写补充 5 名`",
     "fail": "`✗ tools/builtin_api.txt 正文与头部 sha256 不符` / `头部缺 godot 版本 / sha256 行` / `不存在` = 清单被手改或截断；"
             "`导自 godot X，本机 godot Y` = 本机换了 Godot 版本；`extends …清单链上缺类` = autoload 基类不在导出范围"
             "（先加进 `tools/gen_builtin_list.gd` 的 CLASSES）。都计入 check_symbols 问题、退 1，修法 `--regen`"},
    {"id": "check_symbols --regen", "parent": "check_symbols", "lane": "cs3", "oneclick": False,
     "cmd": "python3 tools/check_symbols.py --regen",
     "marks": ['"--regen"', "gen_builtin_list.gd", "逐字节一致，未改动", "已按 ClassDB 重写"],
     "expect": "`✓ --regen：ClassDB 导出与 tools/builtin_api.txt 逐字节一致，未改动`；有漂移则 `↻ --regen：已按 ClassDB 重写 "
               "tools/builtin_api.txt（+a / −b 行；请连同提交）`。之后照常跑完整道 check_symbols，退出码按整道算",
     "fail": "`✗ --regen：找不到 godot` / `gen_builtin_list.gd 失败（rc=…）` → 计入问题、退 1。**会改写 `tools/builtin_api.txt`**，"
             "所以不进一键跑；漂移只在 CI 步骤里配 `git diff --exit-code` 判红（见 §四）"},
    {"id": "check_symbols --suggest", "parent": "check_symbols", "lane": "cs4", "oneclick": False,
     "cmd": "python3 tools/check_symbols.py --suggest",
     "alt": "CHECK_SYMBOLS_SUGGEST=1 python3 tools/check_symbols.py",
     "marks": ['"--suggest"', '"CHECK_SYMBOLS_SUGGEST"', "二之三、字符串派发候选提示"],
     "expect": "多出「二之三、字符串派发候选提示」一节（`emit_signal` / `X.call` / `call_deferred` / `callv` / `Callable(obj, …)` 字面量），"
               "没疑点时没有 `⚠ WARN` 行；不开时输出逐字节不变，开了退出码也不变",
     "fail": "**不判红**：`⚠ WARN <文件>:L<行> <调用>  ← <作用域>：无此 func` / `…：无此 signal` = 字面量名在对应作用域里找不到，"
             "人工判真死引用 / 误报；`--json --suggest` 里记 `level: warn`（ok=true，不计 pass/fail）"},
    {"id": "Main 拆出件拼回（一之零）", "parent": "check_symbols", "lane": "ms / cs8 / gd16", "oneclick": True,
     "cmd": "python3 tools/check_symbols.py",
     "marks": ["一之零、Main.gd 拆出件", "MAIN_NOT_SPLITS", "SPLIT_MARK", "却不是一行转发", "拼回只对源码字符串断言有效",
               "条都有效：文件在、Main 一行转发到它"],
     "expect": "「一之零」每件 `✓ scripts/ui/<件>.gd：N 支转发拼回函数体` + `✓ 头注写「从 Main.gd 原样搬出」的 N 件与 MAIN_SPLITS 一一对上；"
               "Main 调拆出件处都是一行转发；非拆出件的一行委托 N 处都在 MAIN_NOT_SPLITS` + `✓ MAIN_NOT_SPLITS N 条都有效：文件在、Main 一行转发到它、"
               "目标函数在、注明与实际转发一致` + `✓ godot_smoke.gd 的 MAIN_SPLITS 与此一致`。"
               "**拼回只对源码字符串断言有效**：行号、`main.` 前缀、static / 实例语义不在此列（口径见 §三.1）",
     "fail": "`✗ … 转发到 <件> 的 fn，那边没有这支 static func` = 拆出件改名 / 删了没跟转发；`登记为 Main 拆出件，但 Main 里没有一行转发` = 登记了没接；"
             "`调了拆出件 … 却不是一行转发` = 转发带行尾注释 / 两行 / 折行签名，拼回不认；`一行转发到 <件>，它没登记进 MAIN_SPLITS` / "
             "`头注写「从 Main.gd 原样搬出」，却没登记` = 新拆一刀忘登记；`登记为拆出件，头注…没写` = 约定字样丢了；"
             "`godot_smoke.gd 的 MAIN_SPLITS … 不一致` = 两份清单只改了一份；`MAIN_NOT_SPLITS 条目 <件> 文件不存在` / `Main 没 preload 它或没有一行转发到它` / "
             "`转发到 <件> 的 fn，那边没有这支 func（…指向不存在的目标）` / `注明「A → B」，Main 里实际一行转发是 …` / `同时登记在 MAIN_SPLITS 与 MAIN_NOT_SPLITS` "
             "= 放行清单过时（lane gd16），删条目或改注。都计入 check_symbols 问题、退 1"},
    {"id": "按函数名取函数体（十三）", "parent": "check_symbols", "lane": "gd16", "oneclick": True,
     "cmd": "python3 tools/check_symbols.py",
     "marks": ["十三、按函数名取函数体", "class _Bodies(dict)", "_body_ask(name, m is not None)", "处按名取用都取到函数体"],
     "expect": "「十三、按函数名取函数体」`✓ _func_body / func_bodies().get 的 N 处按名取用都取到函数体`（N = 本脚本「行号 + 函数名」去重后的取用处）。"
               "只探有没有这支函数、不想判红的写 `name in func_bodies(src)`（不记账）",
     "fail": "`✗ check_symbols.py:<行> 取函数体 <fn> 取不到（改名 / 删了 / 搬走没拼回），这处断言在空转` = 被读的函数改了名 / 删了 / "
             "搬走没拼回，或断言里函数名写错；改前这里给 `\"\"`，反向断言（`\"X\" not in body`）照样绿。计入 check_symbols 问题、退 1"},
    {"id": "compile 清单自检（inventory）", "parent": "compile", "lane": "ea4", "oneclick": True,
     "cmd": "godot --headless --path . -s res://tools/godot_compile_check.gd",
     "marks": ["inventory SCRIPTS == tracked *.gd", "ls-files", "INVENTORY_EXEMPT", "unlisted", "exempt-stale"],
     "expect": "`COMPILE_CHECK OK   inventory SCRIPTS == tracked *.gd under scripts/tools (exempt N)`",
     "fail": "`COMPILE_CHECK FAIL inventory <原因> …`（原因 `unlisted` / `listed-missing` / `dup` / `exempt-stale` / `exempt-but-listed`） = `git ls-files` 里已跟踪的 "
             "`.gd` 没进 `SCRIPTS`（或 `INVENTORY_EXEMPT` 没写理由）、清单路径不存在 / 重复 / 豁免失效，整体计 bad+1；"
             "`COMPILE_CHECK NOTE inventory git ls-files unavailable` = 没 git，退回扫盘（warn，不判红）"},
]

# CI 建议步骤（lane gd4）：docs/GATES.md §四 由它生成，**只是建议，不进 repo 的 CI 配置**。
# 先跑一键跑十三条（导入步骤 tier=step + 必跑十二道 tier=must 的 cmd），再跑下面这些 CI 专属步骤；每步退出码非 0 即红。
CI_STEPS = [
    {"id": "侧车成对 / 一致", "lane": "ag / ag2 / gd5", "needs": "python3 + git（紧跟第 0 步的导入步骤之后跑）",
     "cmd": "python3 tools/check_sidecars.py",
     "expect": "`结果：全部通过`（前一行报 uid 个数、VRAM 纹理张数与基线、`工作树侧车无漂移`）",
     "fail": "`FAIL: …` 行、退 1 = 提交的 .gd / .gdshader / 素材缺侧车或多了孤儿侧车、侧车内容与源文件 / 场景引用 / VRAM 基线不一致；"
             "或第 0 步导入把已跟踪 `.import` / `.uid` 改写了（工作树漂移：CI 机器的 Godot 版本 / 平台与入库基线不符）。口径见 docs/侧车口径.md"},
    {"id": "builtin_api 漂移", "lane": "cs3 / gd4", "needs": "godot（与清单头部同版本）",
     "cmd": "python3 tools/check_symbols.py --regen && git diff --exit-code tools/builtin_api.txt",
     "expect": "`✓ --regen：…逐字节一致，未改动` + check_symbols `结果：全部通过`，`git diff` 无输出、退 0",
     "fail": "`git diff` 打出 `tools/builtin_api.txt` 的差异、退 1 = 提交的清单与本机 Godot 的 ClassDB 导出不一致"
             "（升级了 Godot / 改了 `gen_builtin_list.gd` 的 CLASSES 却没连同提交重导结果）；`--regen` 本身失败则 check_symbols 先退 1"},
    {"id": "GATES.md 与注册表一致", "lane": "gd3", "needs": "python3 + git",
     "cmd": "python3 tools/gates_md.py",
     "expect": "`结果：全部通过`",
     "fail": "有人手改了 §一 / §二批量巡检 / §四 生成块、改了注册表没 `--write`、§三 或 `.claude/todo.md` 验证段的一键跑命令与必跑清单不符，或注册的脚本挪走了"},
    {"id": "docs 索引与文件一致", "lane": "doc3 / doc4", "needs": "python3 + git",
     "cmd": "python3 tools/check_docs_index.py --check",
     "expect": "`结果：全部通过`（前面报索引链接条数、`git 已跟踪的 docs/**/*.md 都在索引里（N 份…）`；未跟踪的新文档只记 `⚠`）",
     "fail": "`✗` 行、退 1：`MISSING` = 提交了 docs 下的 .md 没在 docs/README.md 补一行；`DEAD` = 索引链的文件挪走 / 改名 / 删了；"
             "`DUP` = 同一份文档链了两次。修法：改 docs/README.md"},
]


def _shot_root():
    try:
        with open(os.path.join(TOOLS, "shot_gate.gd"), encoding="utf-8") as f:
            m = re.search(r'^const DEFAULT_SHOT_ROOT\s*:?=\s*"([^"]+)"', f.read(), re.M)
        return m.group(1) if m else None
    except OSError:  # 读不到：out_dir 记 None，由 gates_md 判红
        return None


SHOT_ROOT = _shot_root()
# 截图落盘根的环境变量（shot_gate.gd 的 out_dir 与 patrol_shell 同读）；worktree / 自测推荐一律带上这个前缀，免得覆盖共享证据图（lane pg3）
SHOT_ENV = "NK1_SHOT_DIR"
SHOT_ENV_PREFIX = SHOT_ENV + "=/tmp/<lane>/shots "
# 截图探针以外也认 NK1_SHOT_DIR 的出图工具：不设走各自默认，设了落 <根>/<sub>；显式参数仍优先（lane pg3 / pg4）。
# patrol 默认留 /tmp（必跑门禁、各 lane 例行不带前缀跑，挪进共享证据根会被每轮覆盖，lane pg4 否证统一默认根）
SHOT_ENV_USERS = [
    {"file": "tools/patrol_shell.gd", "what": "patrol 截图旁证", "default": "/tmp/patrol-shots", "sub": "patrol", "flag": None},
    {"file": "scripts/cutscene/CutscenePreview.gd", "what": "`CutscenePreview --snap` 存图", "default": "/tmp",
     "sub": "cutscene-preview", "flag": "--snapdir"},
    {"file": "tools/art/tour.sh", "what": "`tools/art/tour.sh` 巡检截帧", "default": "~/tmp/nk1-art-work/tour", "sub": "tour", "flag": "-o"},
]


def _shot_probe(path, lane):
    """截图脚本一条：TAG / EXPECTED_SHOTS / 截图目录现读源码；读不到的字段为 None（gates_md 判红）。"""
    src = ""
    try:
        with open(os.path.join(ROOT, path), encoding="utf-8") as f:
            src = f.read()
    except OSError:
        pass
    tag = re.search(r'^const TAG\s*:?=\s*"([^"]+)"', src, re.M)
    n = re.search(r"^const EXPECTED_SHOTS\s*:?=\s*(\d+)", src, re.M)
    out = re.search(r'^(?:const OUT_DIR|var _out_dir)\s*:?=\s*"([^"]+)"', src, re.M)
    out = out.group(1) if out else None
    # lane gd2：`var OUT_DIR := ShotGate.out_dir("vision")` → 默认根 + 子目录（NK1_SHOT_DIR 可整体改根）
    sub = re.search(r'^var (?:OUT_DIR|_out_dir)\s*:?=\s*ShotGate\.out_dir\("([^"]+)"\)', src, re.M)
    if out is None and sub and SHOT_ROOT:
        out = SHOT_ROOT + "/" + sub.group(1)
    res = "res://" + path
    # sub：走 ShotGate.out_dir 的子目录（设 NK1_SHOT_DIR 落 <根>/<sub>）；写死目录的为 None，gates_md 判红（lane pg3）
    return {"id": os.path.splitext(os.path.basename(path))[0], "file": path, "lane": lane,
            "tag": tag.group(1) if tag else None, "shots": int(n.group(1)) if n else None,
            "out_dir": out, "sub": sub.group(1) if sub else None,
            "args": ["--path", ".", "-s", res], "display": True}


def _native_json(path):
    """GDScript 门禁接了 tools/gate_report.gd（lane g2 原生 --json）没有；截图脚本看 shot_gate.gd。"""
    try:
        with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as f:
            return 'preload("res://tools/gate_report.gd")' in f.read()
    except OSError:
        return False


def _legacy(g):
    """legacy 条目：注册表 tier=no，或文件在 tools/legacy/ 下（lane gd9：一律强制超时）。"""
    return g.get("tier") == "no" or (g.get("file") or "").startswith("tools/legacy/")


def _legacy_timeout(*names):
    """命令行指到 legacy 条目（注册表 id、条目文件或 tools/legacy/ 路径，相对 / 绝对 / res:// 均可）时返回其强制超时秒数，否则 None。"""
    for n in names:
        n = str(n).replace(os.sep, "/")
        if n in LEGACY_IDS:
            return LEGACY_IDS[n]
        for f, t in LEGACY_FILES.items():
            if n == f or n.endswith("/" + f):
                return t
        if "tools/legacy/" in n:
            return LEGACY_TIMEOUT
    return None


def registry():
    """`--list` 输出的清单：门禁（带人读 / --json 命令、族、是否一键跑）+ 截图脚本明细 + 附属自检 + 一键跑命令 + CI 步骤。"""
    gates = []
    shots_native = _native_json("tools/shot_gate.gd")
    for g in REGISTRY:
        g = dict(g)
        g.setdefault("gate", g["id"])
        disp = "DISPLAY=:2 " if g.get("display") else ""
        if _legacy(g):  # 人读命令也带上限；`--json` 那条由本脚本内部掐（lane gd9）
            g["timeout"] = g.get("timeout", LEGACY_TIMEOUT)
            disp = f"timeout {g['timeout']:g} " + disp
        if g["kind"] == "sh":
            # shell 脚本（tour.sh）没有原生 --json，由本脚本 `--` 外包；出图的带 NK1_SHOT_DIR 推荐前缀（lane gd13）
            env = (SHOT_ENV_PREFIX if g.get("shots") else "") + ("DISPLAY=:2 " if g.get("display") else "")
            run = " ".join([g["file"]] + ([g["usage"]] if g.get("usage") else []))
            g["cmd"] = (f"timeout {g['timeout']:g} env " if _legacy(g) else "") + env + run
            g["json"] = env + "python3 tools/gate_json.py -- " + run
        elif g["kind"] == "py":
            usage = [g["usage"]] if g.get("usage") else []
            g["cmd"] = disp + " ".join(["python3", g["file"]] + usage)
            # 自带三行转接的写 `--json`，没接的（如 verify_narrative）由本脚本外包
            try:
                with open(os.path.join(ROOT, g["file"]), encoding="utf-8", errors="replace") as f:
                    hooked = "gate_json.maybe_json" in f.read()
            except OSError:  # 文件不在：照出清单，由 gates_md 判红
                hooked = False
            g["json"] = g["cmd"] + " --json" if hooked else " ".join(["python3 tools/gate_json.py", g["file"]] + usage)
        elif g["kind"] == "godot":
            g["cmd"] = disp + "godot " + " ".join(g["args"])
            # 接了 gate_report.gd 的写原生（--quiet 去引擎横幅，stdout 恰一行 JSON）；没接的（editor 等）由本脚本外包
            if g.get("file") and _native_json(g["file"]):
                g["json"] = disp + "godot --quiet " + " ".join(g["args"]) + " -- --json"
            else:
                g["json"] = ("" if _legacy(g) else disp) + "python3 tools/gate_json.py --godot " + g["id"]
        else:
            g["cmd"] = SHOT_ENV_PREFIX + "DISPLAY=:2 godot --path . -s res://tools/<探针>.gd"
            g["json"] = SHOT_ENV_PREFIX + ("DISPLAY=:2 godot --quiet --path . -s res://tools/<探针>.gd -- --json" if shots_native
                                           else "DISPLAY=:2 python3 tools/gate_json.py --godot <探针>")
        gates.append(g)
    shots = [_shot_probe(p, lane) for p, lane in SHOT_PROBES]
    for s in shots:
        s["cmd"] = "DISPLAY=:2 godot " + " ".join(s["args"])
        s["json"] = ("DISPLAY=:2 godot --quiet " + " ".join(s["args"]) + " -- --json" if shots_native
                     else "DISPLAY=:2 python3 tools/gate_json.py --godot " + s["id"])
    for g in gates:
        g["family"] = FAMILY[g["kind"]]
        g["oneclick"] = g["tier"] in ("must", "step")
    by_id = {g["id"]: g for g in gates}
    subs = []
    for c in SUBCHECKS:
        c = dict(c)
        parent = by_id.get(c["parent"])
        c["family"] = parent["family"] if parent else None  # 所属门禁不在注册表：gates_md 判红
        c["file"] = parent.get("file") if parent else None
        subs.append(c)
    # 一键跑顺序：导入步骤（step）先跑，再按注册表顺序跑必跑门禁
    order = [g for g in gates if g["tier"] == "step"] + [g for g in gates if g["tier"] == "must"]
    must = [g["cmd"] for g in order]
    # 同序的机读版（docs/GATES.md §二「批量巡检」块由它生成）；step 不判红绿，消费方另放
    must_json = [{"id": g["id"], "tier": g["tier"], "json": g["json"]} for g in order]
    ci = [dict(c) for c in CI_STEPS]
    return {"gates": gates, "shot_probes": shots, "subchecks": subs, "oneclick": must, "oneclick_json": must_json,
            "ci_steps": ci, "shot_env": {"var": SHOT_ENV, "default_root": SHOT_ROOT, "recommended": SHOT_ENV_PREFIX.strip(),
                         "users": SHOT_ENV_USERS}}


# `--godot <预设>`：注册表里的 Godot 门禁 + 截图脚本（带窗口的不加 --headless）
GODOT_PRESETS = {g["id"]: (g.get("gate", g["id"]), g["args"]) for g in REGISTRY if g["kind"] == "godot"}
LEGACY_IDS = {g["id"]: g.get("timeout", LEGACY_TIMEOUT) for g in REGISTRY if _legacy(g)}
LEGACY_FILES = {g["file"]: g.get("timeout", LEGACY_TIMEOUT) for g in REGISTRY if _legacy(g) and g.get("file")}
GODOT_PRESETS["editor"] = ("godot_editor", ["--headless", "--editor", "--path", ".", "--quit"])  # 旧名，与 import 实测等价
GODOT_PRESETS.update({os.path.splitext(os.path.basename(p))[0]: (os.path.splitext(os.path.basename(p))[0],
                      ["--path", ".", "-s", "res://" + p]) for p, _ in SHOT_PROBES})

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# 收尾判词行；其后的 ✗ 行是复述，不重复计数
# （GODOT SMOKE PASS / PATROL SHELL FAIL / SAVE_ROBUST_PROBE PASS / P7_GUILD_EXAM_SMOKE_FAIL 4 / X_OK shots=… / X_CONTRACT_OK…）
# 小写 TAG（如 vision_fill_shots_OK）只认下划线连写的一个词，免得把普通句子当判词
SUMMARY = re.compile(r"^(结果：.*|(COMPILE_CHECK|STORY_CHECK) SUMMARY.*|[A-Z][A-Z0-9_ ]*[ _](PASS|FAIL|OK)\b.*"
                     r"|[a-z][a-z0-9_]*_(CONTRACT_)?(OK|FAIL)\b.*)$")
PREFIXED = re.compile(r"^(COMPILE_CHECK|STORY_CHECK) (OK|FAIL|NOTE)\s*(.*)$")
ENGINE_ERR = re.compile(r"^(SCRIPT ERROR|ERROR|USER ERROR|Parse Error)\b|^\s*ERROR: ")


def _godot_bin():
    g = os.environ.get("GODOT")
    if g:
        return g
    for p in os.environ.get("PATH", "").split(os.pathsep):
        if p and os.access(os.path.join(p, "godot"), os.X_OK):
            return os.path.join(p, "godot")
    return os.path.expanduser("~/.local/bin/godot")


def parse(text):
    """把人读输出拆成 checks；返回 (checks, summary, engine_errors)。"""
    checks, errors, summary, section, after = [], [], "", "", False
    for raw in text.splitlines():
        line = ANSI.sub("", raw).rstrip()
        s = line.strip()
        if not s:
            continue
        if ENGINE_ERR.search(line):
            errors.append(s)
            continue
        m = PREFIXED.match(s)
        if not m and SUMMARY.match(s):
            summary, after = s, True
            continue
        if m:
            kind, rest = m.group(2), m.group(3).strip()
            if kind == "NOTE":
                checks.append({"name": rest, "ok": True, "detail": m.group(1) + " NOTE", "level": "warn"})
            else:
                name, _, why = rest.partition(" :: ")
                if kind == "FAIL" and name.split(" ", 1)[0] in ("load-null", "guard-unlisted", "guard"):
                    tag, _, name = name.partition(" ")
                    why = (tag + ("：" + why if why else "")).strip()
                checks.append({"name": name.strip(), "ok": kind == "OK", "detail": why or section})
            continue
        if s[0] in "✓✗⚠":
            if after and s[0] == "✗":
                continue
            body = s[1:].strip()
            if s[0] == "⚠":
                checks.append({"name": body, "ok": True, "detail": section, "level": "warn"})
            else:
                checks.append({"name": body, "ok": s[0] == "✓", "detail": section})
            continue
        if s.startswith("FAIL:"):
            checks.append({"name": s[5:].strip(), "ok": False, "detail": section})
            continue
        if line.startswith("OK   ") or line.startswith("FAIL "):  # p7_guild_exam_smoke
            checks.append({"name": line[5:].strip(), "ok": line.startswith("OK"), "detail": section})
            continue
        if re.match(r"^[一二三四五六七八九十]+、", s) or (s.startswith("──") and s.endswith("──")):
            section = s.strip("─ ")
    return checks, summary, errors


def build(gate, cmd, rc, out, recorded=None):
    checks, summary, errors = parse(out)
    if recorded is not None:
        # Python 门禁的 check(cond, msg) 实录：连「过了不打印」的门禁（check_assets / verify_story_data）也有明细。
        # 这类门禁的失败只从 check() 进账，stdout 里别的 ✗ 是诊断细行（如 simulate_run 的分船账），不另计；⚠ 照收。
        where = {c["name"]: c["detail"] for c in checks}
        for c in recorded:
            c["detail"] = where.get(c["name"], "（过时不打印；name 是失败时的措辞）")
        checks = recorded + [c for c in checks if c.get("level") == "warn"]
    if rc != 0 and not any(not c["ok"] for c in checks if c.get("level") != "warn"):
        checks.append({"name": "exit_code", "ok": False, "detail": f"退出码 {rc}，但没解析到失败条目（中途崩溃或提前退出），见 tail"})
    hard = [c for c in checks if c.get("level") != "warn"]
    n_pass = sum(1 for c in hard if c["ok"])
    doc = {"gate": gate, "ok": rc == 0, "exit_code": rc, "summary": summary, "checks": checks,
           "counts": {"total": len(hard), "pass": n_pass, "fail": len(hard) - n_pass,
                      "warn": len(checks) - len(hard), "engine_errors": len(errors),
                      "script_errors": sum(1 for e in errors if e.startswith("SCRIPT ERROR"))}}
    doc["cmd"] = cmd
    if errors:
        doc["errors"] = errors[:20]
    if rc != 0:
        doc["tail"] = [ANSI.sub("", l) for l in out.splitlines()[-20:]]
    return doc


def emit(doc):
    sys.stdout.write(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    sys.stdout.flush()


def _timed_out(doc, timeout, out):
    """子进程被掐断（lane gd9）：ok=false、exit_code=124、error="timeout"，另记一条 timeout 失败条目；已解析到的 FAIL 照留。"""
    doc["checks"] = [c for c in doc["checks"] if c["name"] != "exit_code"]
    doc["checks"].append({"name": "timeout", "ok": False,
                          "detail": f"超时 {timeout:g} 秒被掐断（进程没自己退出：挂死 / 卡死）；见 tail"})
    hard = [c for c in doc["checks"] if c.get("level") != "warn"]
    n_pass = sum(1 for c in hard if c["ok"])
    doc["counts"].update({"total": len(hard), "pass": n_pass, "fail": len(hard) - n_pass})
    doc.update(ok=False, exit_code=124, error="timeout", timeout=timeout)
    doc["tail"] = [ANSI.sub("", l) for l in out.splitlines()[-20:]]
    return doc


def _run(cmd, timeout, **kw):
    """subprocess.run 合并 stdout/stderr；超时掐断时返回 (124, 已有输出, True)。"""
    if timeout is None:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)
        return p.returncode, p.stdout.decode("utf-8", "replace"), False
    # 带超时的（legacy 条目）子进程自成进程组，掐断 / Ctrl-C 时整组杀，同 timeout(1)：
    # 否则 shell 脚本（tour.sh）起的 godot 孙进程在 bash 被杀后照跑（lane gd13）
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True, **kw)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out.decode("utf-8", "replace"), False
    except BaseException as e:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = p.communicate()
        if not isinstance(e, subprocess.TimeoutExpired):
            raise
        return 124, out.decode("utf-8", "replace"), True


def run_python_gate(path, args, timeout=None):
    path = os.path.abspath(path)
    if timeout is None:
        timeout = _legacy_timeout(path)
    fd, rec = tempfile.mkstemp(prefix="gate_json_", suffix=".jsonl")
    os.close(fd)
    env = dict(os.environ, **{REC_ENV: rec, "PYTHONIOENCODING": "utf-8"})
    cmd = [sys.executable, os.path.abspath(__file__), "--child", path] + list(args)
    rc, out, killed = _run(cmd, timeout, cwd=os.getcwd(), env=env)
    recorded = []
    try:
        with open(rec, encoding="utf-8") as f:
            recorded = [json.loads(l) for l in f if l.strip()]
    finally:
        os.unlink(rec)
    gate = os.path.splitext(os.path.basename(path))[0]
    shown = ["python3", os.path.relpath(path, ROOT)] + list(args)
    doc = build(gate, shown, rc, out, recorded or None)
    return _timed_out(doc, timeout, out) if killed else doc


def run_command(gate, cmd, cwd=None, timeout=None):
    rc, out, killed = _run(cmd, timeout, cwd=cwd)
    doc = build(gate, cmd, rc, out)
    return _timed_out(doc, timeout, out) if killed else doc


def _json_lines(text):
    """stdout 里能解析成门禁 JSON（带 gate / ok 的对象）的行；Python 门禁的多行缩进 JSON 整段算一行。"""
    try:
        doc = json.loads(text)
        if isinstance(doc, dict) and "gate" in doc and "ok" in doc:
            return [doc]
    except ValueError:
        pass
    docs = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            doc = json.loads(line)
        except ValueError:
            continue
        if isinstance(doc, dict) and "gate" in doc and "ok" in doc:
            docs.append(doc)
    return docs


def judge_native(gate, cmd, rc, out, err="", timed_out=None):
    """原生 `--json` 的判定：有且只有一行门禁 JSON、且与进程退出码一致才可能绿；没 JSON 行 = 红（lane gd7）。
    rc=None 表示退出码不可知（--judge 读落盘文件），只看 JSON。"""
    docs = _json_lines(out)
    if not docs:
        why = f"stdout 里没有 JSON 行；退出码 {rc}"
        if timed_out:
            why += f"（超时 {timed_out} 秒被掐断）"
        why += "。进程被信号杀 / 引擎崩溃 / 卡死被掐断时 gate_report.gd 的退出钩子不走，只能在这里判红"
        code = rc if rc else 1
        # 超时掐断的记 error="timeout"（lane gd9），其余（信号杀 / 崩溃）记 no_json；两者都带 no_json_line 条目
        doc = {"gate": gate, "ok": False, "exit_code": code, "summary": "", "error": "timeout" if timed_out else "no_json",
               "checks": [{"name": "no_json_line", "ok": False, "detail": why}],
               "counts": {"total": 1, "pass": 0, "fail": 1, "warn": 0, "engine_errors": 0, "script_errors": 0},
               "cmd": cmd}
        if timed_out:
            doc["timeout"] = timed_out
        tail = [ANSI.sub("", l) for l in (out + err).splitlines() if l.strip()][-20:]
        if tail:
            doc["tail"] = tail
        return doc
    doc = docs[-1]
    problems = []
    if len(docs) > 1:
        problems.append(("multi_json", f"stdout 里有 {len(docs)} 行门禁 JSON，只许一行"))
    if rc is not None and rc != doc.get("exit_code"):
        problems.append(("exit_code_mismatch", f"JSON 写 exit_code={doc.get('exit_code')}，进程实际退出 {rc}"))
    if doc.get("ok") != (doc.get("exit_code") == 0):
        problems.append(("ok_mismatch", f"JSON 的 ok={doc.get('ok')} 与 exit_code={doc.get('exit_code')} 不一致"))
    if problems:
        doc = dict(doc, ok=False, checks=list(doc.get("checks", [])))
        for name, why in problems:
            doc["checks"].append({"name": name, "ok": False, "detail": why})
        if not doc.get("exit_code"):
            doc["exit_code"] = rc if rc else 1
        c = dict(doc.get("counts", {}))
        c["total"] = c.get("total", 0) + len(problems)
        c["fail"] = c.get("fail", 0) + len(problems)
        doc["counts"] = c
    return doc


def run_native(gate, cmd, cwd=None, timeout=None):
    timed_out = None
    try:
        p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        rc, out, err = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:  # 同 timeout(1)：记 124
        rc, out, err, timed_out = 124, e.stdout or b"", e.stderr or b"", timeout
    return judge_native(gate, cmd, rc, out.decode("utf-8", "replace"), err.decode("utf-8", "replace"), timed_out)


def judge_files(paths):
    """--judge：每个文件是一道门禁 `--json` 的 stdout 落盘；逐个判，一行一道，任何一道红 / 缺 JSON 即退 1。"""
    red = 0
    for path in paths:
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError as e:
            text = ""
            name += f"（读不到：{e.strerror}）"
        doc = judge_native(name, [], None, text)
        mark = "✓" if doc["ok"] else "✗"
        red += not doc["ok"]
        why = doc.get("error") or ", ".join(c["name"] for c in doc.get("checks", [])
                                             if not c.get("ok") and c.get("level") != "warn")[:120]
        print(f"{mark} {doc.get('gate') or name:28} ok={doc['ok']!s:5} exit={doc.get('exit_code')} "
              f"counts={json.dumps(doc.get('counts', {}), ensure_ascii=False)}" + (f"  ← {why}" if not doc["ok"] else ""))
    print("结果：全部通过" if red == 0 else f"结果：{red} 项失败（共 {len(paths)} 道）")
    return 1 if red else 0


def _child(path, args):
    """子进程：照原样跑门禁，同时实录门禁文件里 check(cond, msg) 的每次调用。"""
    import runpy
    rec = open(os.environ[REC_ENV], "a", encoding="utf-8")

    def prof(frame, event, arg):
        if event == "call" and frame.f_code.co_name == "check" and frame.f_code.co_filename == path:
            names = frame.f_code.co_varnames[:2]
            if len(names) == 2:
                cond, msg = frame.f_locals.get(names[0]), frame.f_locals.get(names[1])
                rec.write(json.dumps({"name": str(msg), "ok": bool(cond), "detail": ""}, ensure_ascii=False) + "\n")
                rec.flush()

    sys.argv = [path] + args
    sys.setprofile(prof)
    try:
        runpy.run_path(path, run_name="__main__")
    finally:
        sys.setprofile(None)
        rec.close()


def maybe_json(gate_file):
    """门禁开头调用：只有命令行带 --json 才接管，否则立即返回、一字不改原行为。"""
    if "--json" not in sys.argv[1:] or os.environ.get(REC_ENV):
        return
    args = [a for a in sys.argv[1:] if a != "--json"]
    doc = run_python_gate(gate_file, args)
    emit(doc)
    sys.exit(doc["exit_code"])


def main(argv):
    if argv[:1] == ["--child"]:
        _child(os.path.abspath(argv[1]), argv[2:])
        return 0
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    if argv[0] == "--list":
        emit(registry())
        return 0
    if argv[0] == "--godot":
        target, rest = argv[1] if len(argv) > 1 else "", argv[2:]
        display = "--display" in rest
        rest = [a for a in rest if a != "--display"]
        timeout = None
        head = rest[:rest.index("--")] if "--" in rest else rest
        if "--timeout" in head:
            i = rest.index("--timeout")
            timeout, rest = float(rest[i + 1]), rest[:i] + rest[i + 2:]
        if timeout is None:
            timeout = _legacy_timeout(target)
        user = rest[rest.index("--"):] if "--" in rest else []
        if target in GODOT_PRESETS:
            gate, gargs = GODOT_PRESETS[target]
            gargs = list(gargs)
        elif target.startswith("res://") and target.endswith(".gd"):
            gate = os.path.splitext(os.path.basename(target))[0]
            gargs = ([] if display else ["--headless"]) + ["--path", ".", "-s", target]
        else:
            print(f"未知 Godot 门禁：{target!r}（预设：{' '.join(GODOT_PRESETS)}，或 res://….gd）", file=sys.stderr)
            return 2
        doc = run_command(gate, [_godot_bin()] + gargs + user, cwd=ROOT, timeout=timeout)
        if "--headless" not in gargs and not os.environ.get("DISPLAY"):
            doc.setdefault("notes", []).append("未设 DISPLAY：带窗口的门禁（patrol / 截图探针）需 DISPLAY=:2")
        emit(doc)
        return doc["exit_code"]
    if argv[0] == "--native":
        rest, timeout = argv[1:], None
        if rest[:1] == ["--timeout"]:
            timeout, rest = float(rest[1]), rest[2:]
        if rest[:1] == ["--"]:
            cmd = rest[1:]
            named = [a for a in cmd if a.endswith(".gd")] or cmd[:1]
            gate = os.path.splitext(os.path.basename(named[0]))[0] if named else ""
            cwd = None
        else:
            target, rest = rest[0] if rest else "", rest[1:]
            display = "--display" in rest
            rest = [a for a in rest if a != "--display"]
            if "--timeout" in rest:
                i = rest.index("--timeout")
                timeout, rest = float(rest[i + 1]), rest[:i] + rest[i + 2:]
            user = rest[rest.index("--") + 1:] if "--" in rest else []
            if target in GODOT_PRESETS:
                gate, gargs = GODOT_PRESETS[target]
            elif target.startswith("res://") and target.endswith(".gd"):
                gate = os.path.splitext(os.path.basename(target))[0]
                gargs = ([] if display else ["--headless"]) + ["--path", ".", "-s", target]
            else:
                print(f"未知 Godot 门禁：{target!r}（预设：{' '.join(GODOT_PRESETS)}，或 res://….gd）", file=sys.stderr)
                return 2
            cmd = [_godot_bin(), "--quiet"] + list(gargs) + ["--"] + [a for a in user if a != "--json"] + ["--json"]
            cwd = ROOT
        if timeout is None:
            timeout = _legacy_timeout(*cmd)
        doc = run_native(gate, cmd, cwd=cwd, timeout=timeout)
        emit(doc)
        return doc["exit_code"]  # judge_native 保证 ok=false 时非 0
    if argv[0] == "--judge":
        return judge_files(argv[1:])
    if argv[0] == "--":
        cmd = argv[1:]
        named = [a for a in cmd if a.endswith((".py", ".gd"))] or cmd[:1]
        doc = run_command(os.path.splitext(os.path.basename(named[0]))[0] if named else "", cmd,
                          timeout=_legacy_timeout(*cmd))
        emit(doc)
        return doc["exit_code"]
    if argv[0].endswith(".py"):
        doc = run_python_gate(argv[0], [a for a in argv[1:] if a != "--json"])
        emit(doc)
        return doc["exit_code"]
    print(f"不认得的参数：{argv[0]!r}；见 --help", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
