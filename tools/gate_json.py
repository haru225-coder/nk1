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
     "judge": "news / scenes effects / npcs / 结局年号 / 人物原稿与上屏字段：数据里写的键代码必须接住；（lane seq3）scenes.json 结构：字段齐备 / 类型 / 引用 id 存在 / 无孤儿（归档场登记 `SCENE_ARCHIVE`），附 24 类反向自证；L1B 人物数据读取只扫 git 已跟踪文件（lane w19-g11：未跟踪 / 忽略的 `tools/verify_*` 探针不扫）",
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
     "judge": "autoload 起得来、章节/旗标/结局按数据走、headless 零延迟旁路；（lane w53-11）运行中出 SCRIPT ERROR（含 Parse Error）即判红——原先子函数 / 游戏代码里的脚本错把断言整段跳过照退 0、_run 自身出错则空转到超时",
     "green": "`GODOT SMOKE PASS`", "red": "`✗` 行；`GODOT SMOKE FAIL` + 复述"},
    {"id": "compile", "gate": "godot_compile_check", "tier": "must", "kind": "godot", "file": "tools/godot_compile_check.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/godot_compile_check.gd"],
     "judge": "清单脚本 `load()` + `can_instantiate()`；场景解析（lane m2：ext_resource / 子资源 / 脚本坏）；守护清单",
     "green": "`COMPILE_CHECK SUMMARY bad=0/N`", "red": "`COMPILE_CHECK FAIL …` 行；`bad=k/N`"},
    {"id": "story", "gate": "godot_story_check", "tier": "must", "kind": "godot", "file": "tools/godot_story_check.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/godot_story_check.gd"],
     "judge": "新闻按月投放不重复、1268 身份结算恰一次、存档 round-trip、真机抵港路由；（lane w19-g11）运行中出 SCRIPT ERROR（含 Parse Error / Compile Error）即判红，原先依赖脚本解析失败、断言整段跳过也退 0",
     "green": "`STORY_CHECK SUMMARY fails=0`（前一行 `STORY_CHECK OK   运行中无 SCRIPT ERROR / Parse Error（0 条）`）", "red": "`STORY_CHECK FAIL …`（含 `运行中无 SCRIPT ERROR / Parse Error（N 条，首条：…）`）；`fails=k`"},
    {"id": "p7", "gate": "p7_guild_exam_smoke", "tier": "must", "kind": "godot", "file": "tools/p7_guild_exam_smoke.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/p7_guild_exam_smoke.gd"],
     "judge": "行会入行 / 行情抄本条数 / 贡院赴试 / 誊录：扣费门槛、商誉 3 / 5 条、每章一次、跨月结算时序；（lane w53-11）运行中出 SCRIPT ERROR（含 Parse Error）即判红——原先子函数 / 游戏代码里的脚本错把断言整段跳过照退 0、_run 自身出错则空转到超时",
     "green": "`P7_GUILD_EXAM_SMOKE_OK`", "red": "`FAIL …` 行；`P7_GUILD_EXAM_SMOKE_FAIL k`"},
    {"id": "patrol", "gate": "patrol_shell", "tier": "must", "kind": "godot", "file": "tools/patrol_shell.gd",
     "args": ["--path", ".", "-s", "res://tools/patrol_shell.gd"], "display": True,
     "judge": "挂主场景走开局、三港、九设施、海图：1280×720 按钮不越界、焦点色、航向牌、终局港口页；截图旁证一色判据（lane pg，一色只记 ⚠）；"
              "（lane w20-a2，g1 遗留② / g13 遗留④）白刃两条窗口支路：末艘「夺船」题签按游戏时停满 T_HOLD 八成（相位判据）、出战墨边写「・夺船」；"
              "白刃失利支「脱钩」题签同判据、不收战、不出墨边（不再用 0.44 s 墙钟边界）；（lane w53-11）运行中出 SCRIPT ERROR（含 Parse Error）即判红——原先子函数 / 游戏代码里的脚本错把断言整段跳过照退 0、_run 自身出错则空转到超时",
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
    {"id": "check_sidecars", "tier": "must", "when": "提交新 .gd / .gdshader / 素材，或挪删它们（同车规则：新源文件的侧车同 commit 带上）", "kind": "py",
     "file": "tools/check_sidecars.py",
     "judge": "（lane ag / ag2）按 git 索引：已跟踪 .gd/.gdshader 须有已跟踪 `.uid`，可导入素材须有 `.import`；反向不许只提侧车 / 多余侧车；侧车内容与源文件、场景引用、VRAM 基线一致，uid 唯一；工作树里已跟踪侧车不许漂移。口径表见 docs/侧车口径.md",
     "green": "`结果：全部通过`", "red": "`FAIL: …` 行（缺侧车 / 孤儿·多余侧车 / 内容漂移 / 非基线形态 / 工作树漂移）；`结果：N 项失败`"},
    {"id": "save_migrate_probe", "tier": "lane", "when": "动存档结构 / save_schema", "kind": "godot",
     "file": "tools/save_migrate_probe.gd", "args": ["--headless", "--path", ".", "-s", "res://tools/save_migrate_probe.gd"],
     "judge": "（lane sv / fx6；w20-c9 加迁移矩阵关键字段档）老档沿迁移链逐级升到本版（`SaveLoad.SAVE_SCHEMA`，现为 3：v1→v2→v3）：v1 老档读入补字段、回写本版、原件留 .v1；"
              "v2 档（无 `state.met_ids`）按雇用记录 / 在船职事 / 守城见林华回填人物志「已识」、推不出留空、回写本版、原件留 .v2；未来档明确拒读、不退副抄、文件不动；"
              "w20-c9 关键字段过链 K1–K4b：v1/v2 旗（含玉湖事件标记 chen_zan_stake）、发现录、水粮、船式样读回不丢，v1 无 fleet 分区判好档但落缺省（高危档回归），v2 已有 met_ids 不被回填顶掉——详见 docs/存档迁移矩阵.md",
     "green": "`SAVE_MIGRATE_PROBE PASS`", "red": "`✗` 行；`SAVE_MIGRATE_PROBE FAIL fails=k`；输出含 `SCRIPT ERROR` 即算失败"},
    # lane w21-d18：c9 遗留④「动 VERSION 需同步动 SAVE_SCHEMA」原先只是 SaveLoad.gd 注释里的口头约定，没有任何门禁守
    {"id": "check_save_version_contract", "tier": "lane", "when": "动 SaveLoad 的 VERSION / SAVE_SCHEMA / 存档头拒读口径", "kind": "py",
     "file": "tools/check_save_version_contract.py",
     "judge": "（lane w21-d18）`scripts/core/SaveLoad.gd` 的存档头 VERSION 与结构版 SAVE_SCHEMA 结对：三条配对判据全部机械判——"
              "B1 `VERSION < 3`（降头等于再版废档，比旧读档器最后认的头还小）、B2 `SAVE_SCHEMA > VERSION`（结构版升了头没跟，"
              "旧版游戏照样收下新结构档，即 K3 静默落缺省一型，见 docs/存档迁移矩阵.md）、B3 `VERSION > SAVE_SCHEMA`"
              "（头升了结构版没跟，本版读不出自己写的档）；另守「拒读守卫在迁移前置位」句式（`if schema > … or ver > …` → future → 迁移）"
              "与契约注释三字样在声明块里；每次先跑「零、判据自检」：内存变体单独改 VERSION 须红 B3、单独改 SAVE_SCHEMA 须红 B2、"
              "两者同升须绿、降头须红 B1、拆守卫须红 G",
     "green": "`结果：全部通过`（零、判据自检 8 条 ✓ + 一、结对 5 条 ✓）",
     "red": "`✗` 行：配对三条各写明修法（B2 引 docs/存档迁移矩阵.md）；`结果：N 项问题`"},
    # lane w22-h3（原题 w21-d2）：doc4 立了门禁没进注册表——索引缺 5 份散红到别的片才被发现（同 g12/b6 漏登记一型）
    {"id": "check_docs_index", "tier": "lane", "when": "docs/ 下 .md 增删，或 docs/README.md 索引行变更（d4 规约：纯文档 lane 收尾必跑两道之一）", "kind": "py",
     "file": "tools/check_docs_index.py", "usage": "[--check]",
     "judge": "（lane doc4 立，w22-h3 入册）`docs/README.md` 是 docs/ 的唯一索引，核它与 docs/ 下的文件对得上："
              "MISSING = git 已跟踪的 docs/**/*.md（README.md 本身除外）没在 README 里以 `[…](路径)` 链到；"
              "DEAD = README 里的相对链接指向不存在的文件（`#锚点` 去掉再查，http / mailto 不查）；DUP = 同一路径链了不止一次；"
              "只看 git 已跟踪的文档（别的 lane 没提交的新文档不染红共用树，与 tools_gd 同口径），未跟踪的只记 `⚠`；git 不可用时退回扫盘",
     "green": "`✓ 索引里有链接… / ✓ 索引链接都指向存在的文件… / ✓ 索引里没有重复链接 / ✓ git 已跟踪的 docs/**/*.md 都在索引里…` + `结果：全部通过`",
     "red": "`✗ …；DEAD：…` / `✗ …；MISSING：<文件>…（在 docs/README.md 补一行）` / `✗ …；DUP：…`；`结果：N 项问题`"},
    # lane w40-k3 升进必跑（拍板 E-14，照 §五.2 三条件：「登记与文档同步没同步」别的 lane 自己判不准——gd4 patrol 缺 DISPLAY=:2 即此类；实测 0.14 s；只读纯 stdlib 不写盘）：升前进一键跑就自相咬尾——本道逐条比 §三 / todo.md 两处一键跑段（含自己那条 cmd），放进一键跑才合法；原为 lane 加跑档 + CI §四 步骤 3（照 gd21 / cs21 先例步骤随之删掉）
    {"id": "gates_md", "tier": "must", "kind": "py", "file": "tools/gates_md.py",
     "judge": "（lane gd3 / gd4 / gd5；gd5 加 §二 批量巡检块、`.claude/todo.md` 验证段；w20-b3 加一键跑把关与 README 道数对账）本注册表 vs docs/GATES.md §一、§二批量巡检、§四三个生成块逐字一致；注册的脚本都在；接 shot_gate 收尾截图的脚本全部入册、接 shot_gate 的脚本都挂压帧 `ShotGate.frame_pressure`（lane gd18）；附属自检的开关还在源码里；§三 小节编号对得上；§三 与 todo.md 验证段的一键跑命令与必跑档逐条同序；一键跑把关（w20-b3，判据自检见附属「三之一」）：两处一键跑命令段不许带关断开关 / `--help` / `--dry-run`、必跑档不许缺席、条数不许不符，README「下面 N 道」的道数与注册表一键跑条数对得上",
     "green": "`结果：全部通过`", "red": "`✗` 行（附首处差异）；`结果：N 项问题`；修法 `python3 tools/gates_md.py --write`"},
    # lane gd21 升进必跑：「写没写外部路径」自己判不准（照抄命令 / 默认根最容易带进来），跑一次 <1s、只要 python3 + git、不写盘
    {"id": "RefsMacPath", "tier": "must", "kind": "py",
     "file": "tools/check_mac_paths.py",
     "judge": "（lane doc9）git 已跟踪的文本文件里不许写 Mac / Homebrew 专属绝对路径（Mac 家目录、Homebrew 前缀、Godot 应用包、用户资料库目录等 10 条，"
              "模式与理由见脚本 `PATTERNS`；lane cs20 起每行另把字面量 / 家目录之间的拼接折成一段再对，与 RefsHostPath 共用 `tools/path_scan.py`；lane gd21 起脚本自身也扫，只按行排除 `PATTERNS` / `SAMPLES` 块的条目行，块里夹了别的行即判红）；每次先跑「零、模式自检」（lane auditfix2）：`SAMPLES` 正向样本（含独立审计原反例两行）须全认出、`CLEAN` 反向样本须全不命中；已定级的留档进白名单 `ALLOW`：按文件登记命中行数、头部横幅 / 回指注字样与理由，"
              "行数不符、字样丢了、条目失效都判红；未跟踪文件只记 `⚠`",
     "green": "`白名单外 0 处命中（扫 N 个已跟踪文本文件，含本脚本、其 PATTERNS / SAMPLES 块除外）` + `结果：全部通过`",
     "red": "`✗` 行（白名单外命中逐行列 `文件:行 … ← 命中串`；白名单文件行数不符；横幅 / 回指注丢了；失效条目；本脚本 PATTERNS / SAMPLES 块形状不对；零节样本漏认 / 误报）；`结果：N 项问题`"},
    # lane cs21 升进必跑（同 gd21 升 RefsMacPath）：「写没写本机路径」自己判不准，跑一次 <1s、只要 python3 + git、不写盘
    {"id": "RefsHostPath", "tier": "must", "kind": "py",
     "file": "tools/check_host_paths.py",
     "judge": "（lane gd22）git 已跟踪的文本文件里不许写本机 Linux 绝对路径：`/home/<用户>` 与 `/workspace/<目录>`（仓库根本身一律红，"
              "命令写 `--path .`）；仓外根登记在脚本 `ROOTS`（截图根 `NK1_SHOT_DIR`、简报目录 `NK1_BRIEFS` 两条）：文档 / 注释（lane cs20 起按注释起点切行，行尾注释也算）里随便写，"
              "代码段只许 owner 写一次默认值（字面量拼接折成一段再判，与 RefsMacPath 共用 `tools/path_scan.py`），owner 丢了默认值或环境变量名判失效；每次先跑「零、样本自检」（lane cs21）：`SAMPLES` 正向样本"
              "（含 gd22 清掉的原文三行、cs20 的拼接写法）在 .gd 代码段 / 注释行 / .md 三处须全判红、`CLEAN` 反向样本三处须全不判红、"
              "`ROOTS` 每条按 owner 代码行 / 非 owner 代码行 / 拼接 / 行尾注释 / .py 文档串 / .md 各判一次；"
              "本脚本自身也扫（只放过 `ROOTS` 登记行，按行排除 `SAMPLES` 块，块形状不对即判红），未跟踪文件只记 `⚠`",
     "green": "`登记外 0 处命中（扫 N 个已跟踪文本文件，含本脚本、其 SAMPLES 块除外）` + `结果：全部通过`",
     "red": "`✗` 行（逐行列 `文件:行 … ← 命中串`；非 owner 代码行写死仓外根另注；ROOTS 条目失效；本脚本 SAMPLES 块形状不对；零节样本漏判 / 误报、owner 口径不对）；`结果：N 项问题`"},
    # lane auditfix1 入册即必跑（一键跑末条）：dec3 立了没进注册表，自 cs14 a8ff603 起主干红到 abb3f05（DRIFT 47）没人看见；跑一次 ~1s、只读不写盘
    {"id": "check_decision_refs", "tier": "must", "kind": "py", "file": "tools/check_decision_refs.py",
     "judge": "（lane dec3 / dec4）`docs/待策划拍板清单_2026-09-28.md` 反引号里的每处「文件:行」：文件在、行号不越界、"
              "指的还是清单头部锚（「行号：……按 HEAD `x`」）那个提交里的同一段内容；挪了位的按 diff / 同文件原文 / 函数名（照 main_splits 改名表进拆出件）/ 跨文件原文四层算出新号；"
              "清单里不许留 `--fix` 打的「〔跟号待核：…〕」；改号自证：和上一版清单逐对比「旧锚旧号那段 == 本版锚本版号那段」，旧那段原文还在别处即号写歪了（lane auditfix1）；"
              "仓外 brief 引用只查越界（`$NK1_BRIEFS` 不在只记 `⚠`）；落点所在函数只剩一行转发（func_body.forward_of）的穿透到真体再跟号，穿透不下去报「跟到一行转发」，"
              "每次先跑内存里的「转发穿透自检」10 形（lane auditfix6）；输出确定序（lane cs23）：逐处的 ⚠ / ✗ 行先收齐、按「清单行号 → 行内第几处引用 → 类别」排好再印，"
              "`--since` / 改号自证的新旧配对也按新版引用的清单顺序逐对比——原先配对取 `ko.keys() & kn.keys()`（集合，遍历顺序随 PYTHONHASHSEED 变），有 2 处以上 ⚠ / MISMATCH 时同基连跑每次行序不同、「逐字节同」比对偶发假 DIFF（lane cs18 待议 4）；"
              "头部锚须在 HEAD 的历史上（lane w53-12：lane --fix 打的锚主控 rebase 落地后悬空，本机共用对象库照绿、新克隆退 1——main 上 107 版清单 28 版如此，b241992 / f3f092e / 1665423 三回推上了 origin），"
              "上一版清单的锚取不到时改号自证明印「没比成」（原先静默「对上 0 对」）",
     "green": "`✓ 转发穿透自检 10/10（…）` + `✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异…都落得上（…）；…`（lane w19-g8，SUBCHECKS）+ `锚 X：引用 N 处（…）…；NOFILE/OOR 0，DRIFT 0（…），待核标记 0` + `改号自证 […]…MISMATCH 0…` + `结果：全部通过`（`⚠ 改指未验` 不判红）。同一基连跑 5 次 stdout 逐字节同（lane cs23 实测：六个历史基 × 默认 / `--show`、5 个 `--since` 旧版与号写歪的脏树各 5 次同 md5）；lane cs25 起由 ledger_refs_mutants 二节固化（5 个固定种子、去掉排序须判不确定）",
     "red": "`✗ NOFILE` / `✗ OOR` / `✗ DRIFT L行 文件:行：…可跟号 → :新号（凭什么）` 或 `…跟不上，要人工：…` / `✗ 待核 L行` / `✗ MISMATCH L行 …旧锚那段原文在 X 里还在 文件:行——行号改歪了？`；"
            "`…可跟号 → 文件:新号（穿透一行转发 …）` / `…跟不上，要人工：跟到一行转发：…` / `✗ 转发穿透自检 S… 期望 … 实得 …`（脚本自身坏了）；"
            "`✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——…`（变异靶子漂了，lane w19-g8，见 SUBCHECKS）；"
            "`✗ 锚悬空 X：本机对象库里查得到，却不在 HEAD 的历史上…`（lane w53-12；`--fix` 没有 DRIFT 也改锚到 HEAD）/ `✗ 锚 X 不是本仓的提交（lane rebase 前的提交、没推上来？…）`；"
            "`结果：有问题（DRIFT 先跑 --fix 自动跟号…）`；修法 `python3 tools/check_decision_refs.py --fix`（所引文件先提交）"},
    # lane auditfix3：审计 audit1 判 cs12 / cs11「半实」（护栏现状下无能单独触发的实例），这里固化实例；跑一次约一分钟（负载下 94 s）、要 git worktree。
    # lane cs27（auditfix7 W8）：升不了 must（§五.2 快 / 不写盘两条不成立），靶子漂移一类由 check_symbols 十四节「落点预检」每次一键跑判（SUBCHECKS）；
    # when 补上 W8 漏掉的那一手——动了变异的靶子（拆 Main 挪走船屋、改 Main.tscn 中区、改 advance_days / 船屋断言）也要跑全量
    {"id": "check_symbols_mutants", "tier": "lane",
     "when": "① 动 check_symbols 十三节的护栏（_node_block 记账 / NAMED_FUNCS 按 (文件, 名字) 认 / 自扫形状 / NF 标注）、它们守的反向断言或判词，"
             "或动 tools/check_symbols_mutants.py / tools/func_body.py；② 动了变异的靶子：船屋 `_setup_shipyard`（Main.gd / ShipyardPage.gd，拆 Main 挪走它或改转发）、"
             "Main.tscn 的 CenterArea 节点、GameManager / Calendar 的 advance_days、船屋两行反向断言；③ 一键跑 check_symbols 十四节「落点预检」红了——改完 CASES 必跑一次全量",
     "kind": "py", "file": "tools/check_symbols_mutants.py",
     "judge": "（lane auditfix3）check_symbols 反向断言空转的变异对照：当前工作树检出到临时 worktree，逐格施变异、跑整道 check_symbols 比 rc 与 `  ✗` 行。"
              "_node_block 一支（「底图 / 外层横排 / 中区开场不收起」+ 全仓改名 CenterArea、只漏这条反向断言、再收起中区）与 NAMED_FUNCS 一支"
              "（船屋 `\"advance_days\" not in yard_fn` + 改名 GameManager.advance_days、只修弹红的正向断言、再让船屋推一天）各五格；"
              "护栏退回旧口径（cs12 前不记账 / cs11 前 scripts/ 下有定义就算）那格须 rc=0、现行须 rc=1 且只有护栏那一行红；另两格守自扫收分支形反向断言。"
              "lane auditfix5 加：F2c / F3c（F2 之后按红字把 advance_days 改登到 Calendar.gd 下：现行 NF 标注不符一行红 / 不查标注 rc=0）；"
              "S0–S9 分支形七形（条件折多行 / else 支 / ✗ 不在紧下一行 / match / match 守卫 / 折行 any / 探查函数与正则当条件）逐形漏登判红、"
              "退回 auditfix3 口径（单行条件 + 下一行 ✗）rc=0；T1–T6 NF 标注（同名多处没标 / 日后出现同名 / 接收者认不出 / 标错行）",
     "green": "「零、靶子定位自检」K0–K10 11 格 `✓`（lane cs24：插行变异顺一行转发找真身）+ `✓ B0 …` 起 31 格逐格 `✓ <编号> … rc=N` + 「二、空转对照」7 条 `✓ … 旧口径 rc=0 → … 现行 rc=1` + 「三、靶子落点」+ `结果：全部通过`。"
              "`--landing` 只跑落点预检（= check_symbols 十四节，约 0.5 s）：`✓ check_symbols_mutants 落点预检：K0–K10 11 格判对；31 格变异在当前源码上都落得上（…）` + `结果：全部通过`",
     "red": "`✗ <编号> …：期望 rc=a，实得 rc=b` 附 `缺 ✗ …` / `多 ✗ …`；`变异没落上` = 源码改了、这支变异的替换处数不对 / 插行靶子找不到真身（同名多处、转发目标认不出文件）；`✗ K<n>` 靶子定位判据变了；空转对照 `应 0 → 1`；`结果：N 项问题`；无 git（不在仓库 / PATH 里没有）/ 建不了 worktree 退 2；"
            "`--landing`：`✗ check_symbols_mutants 落点预检 · <编号> …：变异没落上——…` 退 1"},
    # lane seq4：scenes.json 那套结构检查参数化成多文件（清单 tools/data_family.json），加跑不进必跑——口径仍 16 道；跑一次 <1s、只读不写盘
    {"id": "check_data_family", "tier": "lane", "when": "动 data/ 下同族文件（scenes.json / ports.json / port_beats.json）的条目 / 字段 / 引用，新增 data/*.json，或动 tools/data_family.json",
     "kind": "py", "file": "tools/check_data_family.py",
     "judge": "（lane seq4 / seq6）普查 data/*.json：F1 带唯一字符串 id 的条目表 + F2 字段指回同表 id（过半）+ F3 scripts/ scenes/ 的代码读它（seq6：# 注释不算、cutscenes.json 不算 scenes.json）的候选，须登在清单 families（同族）或 not_family（写明图为何无入口）；"
              "候补 watch（seq6）按登记的 key 判 F1 / F2 须仍成立，F3 一成立即红（w20-c2：port_beats.json 已按 E-10 接回运行时、升入 families，watch 现空）；"
              "对每个同族文件跑四项：一、字段齐备 / 类型（按形查必填、类型、未登记字段，嵌套列表再查一层；scenes 的形也是 verify_story_data 的形状表，单一来源）；二、引用 id 存在（refs 每一路落在本表 / 别的数据文件 / GDScript 常量的并集）；"
              "二之一、无向图的单向登记须全在 one_way_ok 基线（seq6，只减不增）；三、普查出的自引用路径（过半与部分命中）都登了 refs 或 not_edges；四、从 roots 沿 edge 走不到的条目 = 孤儿（形上 orphan_ok 与 known_orphans 基线放过，基线登了却已可达 / 已删即红）；"
              "每次先跑「零、变异自检」（GATES §五.3；内存里改：同族删必填 / 删边字段 / 改类型 / 悬空 / 拼错字段 / 孤儿 / 新添指回本表的字段 / 基线失效 / 入口与常量改名 / 部分命中漏登 / 单向登记新添与补齐 / 漏登 / 只剩注释读它 / 候补接回运行时须红且只红在该文件，非族 goods / characters / crew 改了须与基线一致；w20-c2：格数随 families 与清单 mutant_skip 走，port_beats 按 entry 成账、可达针不带回指，形状格登记跳过）；"
              "seq6 起锚按形状挑（兜底形、可达、边字段非空的第一条），常量 / 入口名读清单，id 改名自己跟上，挑不到即红「锚落不上」（清单 mutant_skip 登记跳过的格除外，须写明为什么这种形状在本表不存在）；`--mutants` 逐格打印）；"
              "scenes 的孤儿基线与 lane seq3 共用 verify_story_data.SCENE_ARCHIVE",
     "green": "`✓ N 格全对：…` + `== <文件>` 下逐项 `✓ 一、…` 至 `✓ 四、…`（四：`可达 a / n；不可达 k = 形放过 x + 已登记基线 y`）+ `结果：全部通过`",
     "red": "`✗ …` 行（`缺必填字段` / `类型应为` / `未登记字段` / `悬空` / `是孤儿` / `known_orphans 登了 X，它已从入口可达` / `满足 F1–F3…却没登记` / `X→Y 单向登记` / `基线里的 X→Y 已不是单向` / `（未过半…）…却没登 refs` / `已被运行时读…登进 families` / `✗ 变异自检 <编号> …`，其中 `锚落不上：…` = 数据里已没有那种形状的条目、照提示改挑选条件）；`结果：N 项问题`"},
    # lane gd25：「靠多停几帧碰运气变绿」的跨跑判据；不升 must：全集两档约 25 分钟（gd25 当时 26 支；现 31 支）、要 DISPLAY、写截图盘，触发条件按路径判得准（§五.2）
    {"id": "probe_pressure", "tier": "lane", "when": "改了探针集里的 .gd（tools/ 下代码行调 `ShotGate.frame_pressure` 的），或 tools/probe_clock.gd / shot_gate.gd / combat_probe_stage.gd",
     "kind": "py", "file": "tools/probe_pressure.py", "usage": "[--only a,b] [--levels 0,300] [--mutants]", "display": True,
     "judge": "（lane gd25）有窗口探针（代码行调了 `ShotGate.frame_pressure` 的已跟踪 .gd，截图册 + 定向探针）各在两档 `NK1_PROBE_SLOW_MS`"
              "（默认 0 不封顶 / 300 封顶）下跑 `-- --json`，结论（exit_code / error / SCRIPT ERROR / 逐条 checks，名字里的 ms·s·帧读数掩掉）须全同且绿；"
              "每跑各给空 XDG_DATA_HOME。每次先跑「零、判据自检」样本；`--mutants` 在临时 worktree 把两支探针的完成判据改回固定帧数，须判不一致。"
              "像素不比，归 `tools/shot_consistency.gd`（结尾印出交接命令）",
     "green": "逐支 `✓ <探针>：两档一致绿——档 0：绿 n/n（s） ｜ 档 300：绿 n/n（s）` + `共 N 支：一致绿 N / …` + `结果：全部通过`",
     "red": "`✗ <探针>：两档结论不同——…` 附 `rc：档 0 = … · 档 300 = …` / `只在档 X：✗ …`；`✗ …：两档同红`（探针自身红）；`✗ …：跑不成`（没 JSON 行 / 超时）；"
            "`--mutants`：`✗ B0 …` 基线不绿 / `✗ M<k> …——期望「两档结论不同」` / `变异没落上`；`结果：N 项问题`；找不到 godot / 参数错退 2"},
    # lane cs25：cs23 的仓外探针（/tmp/cs23/{mut_gen,det,mut_det}.py）入库；不升 must：约半分钟、要 git worktree（写临时盘），
    # 触发条件按路径判得准（改了那两支脚本 / 台账被变异锚住的几节），同 check_symbols_mutants（§五.2）。
    # lane w19-g8（照 cs27）：全量仍升不了 must；靶子漂移一类由 check_decision_refs「零之二、落点预检」每次一键跑判（SUBCHECKS）；
    # when 补上「动了靶子」——拆 Main 改台账第十一刀函数表 / 清单 Main.gd 引用改指拆出件，也要跑全量
    {"id": "ledger_refs_mutants", "tier": "lane",
     "when": "① 动 tools/gen_main_splits.py（台账格式硬校验 / 函数表对账）或 tools/check_decision_refs.py（逐处行的排序 / since 配对）或 tools/ledger_refs_mutants.py；"
             "② 动了变异的靶子：台账 docs/Main拆解台账.md 已有的「已拆（前三刀…）」段、第四 / 第五 / 第十一刀节的结构（节标题形状、函数表增删行 / 行段写法；"
             "lane cs26 起变异按形状定位：日期 / 题文 / 形参名 / 说明字改了不必跑），拍板清单里 `scripts/Main.gd:N` 引用增删 / 改指；"
             "③ 一键跑 check_decision_refs「零之二、落点预检」红了——改完 M / GEN_CASES / DET_CASES 必跑一次全量",
     "kind": "py", "file": "tools/ledger_refs_mutants.py",
     "judge": "（lane cs25，固化 lane cs23 的探针）当前工作树检出到临时 worktree，逐格施变异、比期望表。"
              "一、gen_main_splits 台账格式硬校验 ①–⑤：逐格改台账（节标题去反引号 / ### / 无空格 / 半角括号 / 去 lane / 箭头后多字、"
              "前三刀段半角括号 / 删一件 /「前N刀」写错 / 整段删掉、刀号重号 / 跳号 / 认不出、函数表行少空格 / ASCII 连字符 / 列两次、删光函数表），"
              "各跑对账 / `--write` / 写后对账：现行对账 rc=1 且 ✗ 行对得上、`--write` 不写盘、写后仍 rc=1；硬校验退回 cs23 前（删两处调用）"
              "同一变异 `--write` 后 rc=0（漏认、清单跟着少、gen 自己绿）；第四刀删表（M5t）现行红、`NO_TABLE_OK` 放行退回 rc=0，"
              "N1 / N2 第四、第五刀补的表漏列一支 / 行段写错各一行红；对照 C0–C2；C3 前三刀段改写成三节现行 rc=0、C3′ 刀序起点写死回第四刀 rc=1（lane cs26）。"
              "变异锚按形状定位（lane cs26）：只锚刀号与形状（「## 第N刀（」起头的标题行、那节函数表最后一支、前三刀段第一件、两支脚本里调用 / 排序的形状），期望 ✗ 字样由定位到的内容现算。"
              "二、check_decision_refs 输出确定序：PYTHONHASHSEED=0/1/2/3/42 各跑一次，D0 基线 / D1 清单前 8 处 Main.gd 号 +1 不提交 / "
              "D2 同一脏树 `--since HEAD`（lane cs26 起相对基，原钉死 ccb1d57）stdout 须逐字节同；X1 / X2 同 D1 / D2 但两处排序（Lines.flush、since 配对）都去掉，须出 ≥2 种",
     "green": "`✓ C0 …` 起 40 格逐格 `✓ <编号> …：对账 rc=N，--write rc=N，写后对账 rc=N` + 二节 5 格 `✓ <编号> …：rc=N，⚠ / ✗ k 条，stdout 1 种`（X1 / X2 `5 种`）"
              " + 「三、空转对照」18 条 `✓ … 旧口径 … rc=0 → … 现行 …`（含 `✓ 刀序起点：C3′ … rc=1 → C3 … rc=0`）+ `结果：全部通过`。"
              "`--landing` 只跑落点预检（= check_decision_refs「零之二」，约 0.1 s）：`✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异…都落得上（…）` + `结果：全部通过`",
     "red": "`✗ <编号> …：期望对账 rc=a / 写后 rc=b，实得 …` 附 `缺 ✗ …` / `多 ✗ …` / `--write 判红却写了盘`；"
            "`✗ D<k> …：期望 rc=a、逐字节同，实得 … stdout n 种`；`变异没落上` = 按形状也定位不到（第四 / 第五 / 第十一刀节标题不止或不到一处、那节没有函数表行、前三刀段认不出、两支脚本里调用 / 排序的形状改了）、这支变异该跟着改；"
            "空转对照 `应 0 → 1` / `应 否 → 是`；`结果：N 项问题`；无 git / 建不了 worktree 退 2；"
            "`--landing`：`✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——…` / `· Z<n> …预检空转` 退 1"},
    # lane w19-g3：专项探针跟现行代码改绿后入册——不入册时 09-30 合并（夺船存名 / 士气挂件 / 3D 船身）把它悄悄弄红、没人看见（§五.1「入库不等于入册」）。
    # 不升 must：headless 约 2 s、写 user:// 存档位 93（跑完删），触发条件按路径 / 函数判得准（§五.2）
    {"id": "qa_pirate_boat_probe", "tier": "lane",
     "when": "动 SeaChart 敌船条目（PIRATE_ENEMY / PATROL_ENEMY）、WorldMap 的 _spawn_enemy / _board_enemy / _note_fate / _battle_exit、"
             "Fleet 的 add_ship / prize_name / display_name（夺船存名，V0928-10 拍板落地时必跑）、CombatFx.ship_sprite_path 船图契约、"
             "PirateShip / Ship 的 apply_sprite / apply_type_sprite、ShipHull3D 或 Ship.tscn / PirateShip.tscn 的 HullRig，或收 / 删 assets/ship_*.png",
     "kind": "godot", "file": "tools/qa_pirate_boat_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_pirate_boat_probe.gd"],
     "judge": "（lane pirate-boat-0928 立，lane w19-g3 跟现行代码、入册）真走 SeaChart 两条敌船条目 → WorldMap 开战：海寇 pirate_boat「快船」两艘、元军哨船 sea_falcon「海鹘」挂 sprite=yuan_patrol；"
              "海战船身是 ShipHull3D 的 3D 宋船视口（敌红帆我素帆），船图契约 ship_<id>.png 有就用、缺图回落（期望按图在不在现算）；"
              "停士气挂件后清零敌船水手、白刃夺下两艘：存名都是「快船」（V0928-10 待拍板，不按序号起名）、上屏 display_name 加「・甲」「・乙」、下场记 boarded、末艘以 win + boarded 收战；"
              "带海鹘与快船的船队存读档（位 93）船型原样；本进程 SCRIPT ERROR 即红。`-- --shots <目录>` 有窗口另截 5 张（不接 shot_gate）",
     "green": "逐条 `  ✓ …` + `QA_PIRATE_BOAT_PROBE PASS（0 项不合；截图 0 张）`",
     "red": "`  ✗ …` 行（如 `夺来的船…存名沿用敌船名「快船」…得 pirate_boat / 快船・一`、`第一艘记下场 boarded…得 [\"pirate_boat/struck\"]`、`…船身接 3D 宋船视口…Sprite2D 没贴 3D 视口`、`本进程无 SCRIPT ERROR（1 行：…）`）；`QA_PIRATE_BOAT_PROBE FAIL（k 项不合；…）`"},
    {"id": "verify_narrative", "tier": "no", "kind": "py", "file": "tools/legacy/verify_narrative.py",
     "why": "（lane gd2 挪入 legacy）绑定云端 21ce 未收的 P7 平行实现（`borrow_ceiling` / `_discovery_extra` / `seen_scenes` 主干从未有；开局链截断 monk、删 `chapter` 臂与主干设计相反），合并台账第 14 行即定「留档不入门禁」；主干上恒红 23 项属预期，仍成立的「效果键必须接住」由 verify_story_data 覆盖"},
    {"id": "p7_smoke", "tier": "no", "kind": "godot", "file": "tools/legacy/p7_smoke.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/legacy/p7_smoke.gd"],
     "why": "（lane gd8 挪入 legacy）与 verify_narrative 同源，绑定 21ce 未收的 P7 平行实现（开局链进泉州、港口节拍、`seen_scenes`、`borrow_ceiling`），合并台账第 14 行定「留档不入门禁」；主干上 4 项 FAIL 后在 `borrow_ceiling()` 处 SCRIPT ERROR、不 quit 挂死（干净 worktree 同，lane l1 已记；lane gd9 起 legacy 条目强制超时 60 秒，到点 rc=124 判红）；P7 行会 / 贡院由 p7（`p7_guild_exam_smoke.gd`）接管"},
    {"id": "tour", "tier": "no", "kind": "sh", "file": "tools/art/tour.sh", "usage": "-r <运行副本> [站点…]",
     "display": True, "shots": True, "timeout": 900, "marks": ["TOUR PASS", "TOUR FAIL", "✓", "✗", "TOUR_READY"],
     "why": "（lane gd13 判不进）美术巡检截帧，产物是给人看的 sheet.jpg：每站一个带窗口 Godot（Movie Maker，不能 `--headless`），"
            "全集 21 站实测 348 秒（8 核、负载 8–11；单站 title 17 秒），另要先 `git archive` 出运行副本并导入一次（12 秒）；"
            "只判引擎退出码 / TOUR_READY / 报错计数 / 帧与小样在不在，不看像素——画面回归由截图门禁 25 支探针判。"
            "动 ShotTour / tour_sheet / 过场站点时手跑。输出契约：逐站 `✓` / `✗ …  ← 红因` 一行，末行 `TOUR PASS n/n` / `TOUR FAIL k/n`，"
            "退出码 0 全绿 / 1 有站红 / 2 用法错 · 运行副本不在 · 找不到引擎；`--json` 外包后 checks 逐站一条，强制超时 900 秒"},
    # lane w20-c10：性能基线。只求「跑通了、留指标行」底线红，超阈全 ⚠ 不判红——本机 20 路 lane 共用（load 20+）下
    # 帧时墙钟随 CPU 供给起伏，设 must 会天天误红；先立口径（帧时各分位 / 峰值内存 / 启动到可玩 + 软档阈值），
    # 日后做真机 / 静音刻复测时收紧。基线表与意义见 docs/性能基线.md；本条目占 lane 档「帧时口径」位。
    {"id": "perf_baseline", "tier": "lane",
     "when": "动 Main.tscn / SeaChart.tscn / SeaChart.gd 航行主环 / 渲染管线（UiTheme / MapView 改动），或动 tools/perf_baseline.gd 本身 / 提高 THRESHOLDS；做帧时重测 / 复测基线时手跑",
     "kind": "py", "file": "tools/perf_baseline.py",
     "usage": "[--scene 场面] [--secs N]",
     "marks": ["PERF_BASELINE", "PERF_BASELINE_MM", "PERF_PY"],
     "judge": "（lane w20-c10 立，软档）跑 `tools/perf_baseline.gd` 取指标行，按 `THRESHOLDS`（与 docs/性能基线.md §3 同步）软档判：仅「采样帧 < 下限 / 没拿到指标行 / 有 SCRIPT ERROR」算红，超阈全 `GateReport.warn`（ok=true、rc=0）；"
            "`--selftest` 零、判据自检（伪造高 / 中档指标行各判 warn / fail、`_MM` 正则抓数对、收紧一格后中档须见 ⚠——反向变异自证）；"
            "两次跑之间阈值波动可达 30%+（8 vCPU / 20 路 lane），红绿判据只盯「跑通了」这一底线、指标交人读——本仓首份性能口径，不判「帧时快慢」",
     "green": "`PERF_BASELINE PASS（0 项不合；synthe / real 帧起了 N）`；`PERF_PY：<结果>`（全部通过 / N 项未通过）",
     "red": "`PERF_BASELINE FAIL（…）`；`PERF_PY：N 项未通过`；`✗ real: <理由>`（采样帧不足 / 拿不到指标行 / SCRIPT ERROR）"},
    # lane w25-j5：拍板清单 E-16 升格——40.8 秒挂了约 30 小时没人看见（lane g5）才升的档，升格判据见 docs/GATES.md §五.2
    {"id": "cutscene_data_only", "tier": "must", "kind": "py",
     "file": "tools/art/import_cutscene_bgs.py", "usage": "--data-only",
     "judge": "（lane w20-a7 去 PIL，w25-j5 升必须跑）过场数据守门：`data/cutscenes.json` 逐镜时长合计落在 20–40 / 60–90 秒窗内（不含章末了结的 20–35 秒档）、cam 在 cover_view 上夹得动、字幕 t 离镜头结束 ≥1.5 秒；镜头 / 字幕 / 章节卡 / bg_alt 只认播放器认的键、字幕与 bg_alt 的 if_flag / unless_flag 须是有人立的旗、字幕 hold ≥1.5 秒（lane w53-9）；每次跑带七格内存样本自检，哪条判据被退掉即红（lane w53-12 S1–S5、w53-9 S6–S7，§五.3）；.import_manifest.json 的 sha1 / size / crop 与产物一致；来源目录一律不看（PIL 也不需要）",
     "green": "`import_cutscene_bgs --check：N 张背景合规［产物（按清单 sha1）］；data/cutscenes.json 契约校验通过`",
     "red": "`FAIL …` 行（如 `FAIL cutscenes.ending_root 共 5 镜 40.3 秒，要求 3–5 镜、20–40 秒`；判据被退掉时 `FAIL 契约样本自检 S<n> …：漏判——…`），rc=1"},
    # lane w26-k3：w24-c1 遗留②「契约文档每档角色 / 品级一览人工维护、与 characters.json 无自动核对」。
    # 快（约 0.2 s）、只读，触发条件照 §五.2 按路径也判得准（动 characters.json / 契约文档），故 lane 档不升 must；
    #「为什么归这一档」是写作口径、机器不答（文档里点明留人）。本条三处把原稿文件名写成
    # data/characters_{suffix}.json：写全名 data/characters.json 会让 verify_story_data L1B 把本文件
    # 认成「读原稿的入口」（它的 raw 子按字面子命中、不分串注，.py 同样扫），本文件不是入口。
    {"id": "check_char_contract_doc", "tier": "lane",
     "when": "动 docs/人物原稿与上屏契约.md 的「每档角色 / 品级一览」生成块（CHARS-DOC 标记对内）、"
             "data/characters_{suffix}.json 的角色条目 / tier / 名 / 生卒、data/crew.json 的 roles 职名 / "
             "candidates 挂钩（sources.crew_id 那条链）、scripts/ui/CharacterArt.gd 的 TIER_ORDER，或动本脚本自身",
     "kind": "py", "file": "tools/check_char_contract_doc.py",
     "judge": "（lane w26-k3）契约文档「每档角色 / 品级一览」生成块（CHARS-DOC 标记对内）与 data/characters_{suffix}.json 现算逐字一致：档序照 CharacterArt.TIER_ORDER（唯一来源，源码里认不出它即红、不在此另抄档序），行 = id / 名 / 生卒（生–卒，缺一则「？」、皆无「—」）/ 职事（凡 sources.crew_id 挂了 data/crew.json 候选的按候选 role 取职名；「初习 / 谙熟 / 老练」是职事合同 level、不录这里——本作没有「人物品级」，写上会读成官阶）；漏档 / 多档 / 名 / 生卒 / 职名写错、行序或空格漂一格都按首处差异「文档 / 数据」两行对照报案。`--fix` 重贴生成块（会写盘，不进一键跑），`--gen` 只打印。零、判据自检每次在内存叠层里跑：R1–R7 反向格（改 tier / 数据加人 / 文档加行 / 生卒算错 / 两人换档 / 职名写错 / 行序反了各红且红因落行）、C1–C5 对照格（正常态照判绿、行数口径、名带竖线 / roles 表报废 / 新档未登记三格 gen 不瞎造表、红因写明哪一环断了——探不到那一红即格红）。三格机判不了的留人工：id 空格号、手写段措辞、「为什么归这一档」。",
     "green": "`✓ docs/人物原稿与上屏契约.md 有恰一对 CHARS-DOC 生成标记` + `✓ 生成块与 data/characters_{suffix}.json 现算逐字一致（id / 名 / 生卒 / 职事）` + `✓ 生成块角色行数（N）= 原稿条数（N）…` + 零节 R1–R7 / C1–C5 全 `✓` + `结果：全部通过`",
     "red": "`✗ …首处差异在块内第 k 行\\n      文档：…\\n      数据：…\\n      修法：python3 tools/check_char_contract_doc.py --fix …`（对照两行就是点名）；`✗…CHARS-DOC 生成标记应为恰一对…`；`✗…行数（a）= 原稿条数（b）`；`✗…认不出 TIER_ORDER…` / `…不在本档名表…`；`✗…职事栏取数口径断了…`；`✗ <格号>…——这一路红已不从这里出`（自检对不上）；`结果：N 项问题`"},

    {"id": "qa_rest_days_probe", "tier": "must",
     "why": "升格：lane w48-k1 依 w42-k6 判词表「可升级升格片（五判全齐）」授权锚第四件、照 w47-k1 牒备件五节 (i)–(v) 套牒升进必跑（注册表 REGISTRY 序原位 :33）。"
            "判不准成立——歇宿钮面 ↔ 实扣钩跨五路写口（TavernPage/ResidencePage 歇候钮绑定与钮面措辞、Main._on_rest、歇价/月供/月息月结链、探针自身），改动 lane 多半想不起加跑这条 lane 当次只加跑的探针；"
            "速档按 §五.2 自书 GDScript 引擎实测牒不咎一键跑既有 Godot must 本辑（一键跑自含 smoke 8.0s / compile 3.3s / story 104s / patrol 24s，§五.2 自书基线总约 60s），本支三跑 3.65–3.95s 仍 < smoke 8.0s、≪ story/patrol、居快翼；"
            "只读零写盘成立——源码零 FileAccess/DirAccess/user:///save(/ResourceSaver，摆场只 in-memory 置开局态 + 真场景树读钮按下，经 advance_days 月结推日不落 user:// 存档位；误红面不扩（无 ⚠ 放行面）。",
     "kind": "godot", "file": "tools/qa_rest_days_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_rest_days_probe.gd"],
     "judge": "（探针 9827daa 立，w27-k3 入册——审计 wave2425「最该补的门禁」第 1 条：原先只手工召、CI/一键不会响；变异已证值得响，+1 日即 fails=7）"
              "真场景树 C1–C7 把旅店 / 住处「歇・候 N 日」钮面 ↔ 实扣钉成运行时真断言：钮面日数 = DAYS_PER_MONTH − day + 1（候钮落次月 1 日，含今天在店的整日数）、"
              "扣钱恰为钮面印数；跨年（12 月中按候钮）落次年 1 月、月息结在 1 月；欠债跨月旅途月供真实到账（月息通告 ≥1 则）；月初清晨只印「候 30 日」一枚；"
              "钱不够任何钮按不动、日子不推且有话术；住处 3 日一钮多钱不够第二路径同钉。本进程 SCRIPT ERROR 即红。末行 `REST_DAYS cases=N fails=0`，fails>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `REST_DAYS cases=N fails=0`",
     "red": "`  ✗ …` 行（如钮面缺枚 / 实扣与印数不符 / 落日漂移 / 跨月月息未到账 / 钱不够照扣）+ 末行 `REST_DAYS cases=N fails=M`（M>0），退 1"},

    {"id": "qa_ledger_strip_probe", "tier": "lane",
     "when": "动 HUD 顶匾（scripts/ui/LedgerPage.gd 的 refresh_strip / _status_line 上行文案格）、scripts/Main.gd 的 "
             "update_status_panel、钱账口（GameState.money / spend_money）、水粮天数口径（Fleet.supply_days / 日耗 / at_sea），"
             "或动 tools/qa_ledger_strip_probe.gd 自身",
     "kind": "godot", "file": "tools/qa_ledger_strip_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_ledger_strip_probe.gd"],
     "judge": "（探针 104c0a7 立，w29-k3 入册——审计-wave27「最该补的门禁」第 3 条：落地时被「注册或豁免」闸收编为 EXEMPT 只是缓兵）"
              "真场景树 C1–C4 把 HUD 顶匾上行「钱 N　水粮 D 日」钉成运行时真断言：账变屏真变（spend_money / 出海 advance 扣水粮后改印新值、整行与旧行不同、旧值不再印）；"
              "泊港 advance 水粮天数不动是设计（反向钉「不是 bug」）；正月三十 +1 落二月初一跨月当天顶匾仍印新值（防月结静默清空）；"
              "直拨水粮池 water=food=10→3 日 + 整行须同时含「钱 」「水粮 」「 日」三个骨架格（LCD 尾哨）。本进程 SCRIPT ERROR 即红。"
              "末行 `LEDGER_STRIP_PROBE cases=N fails=0`，fails>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `LEDGER_STRIP_PROBE cases=N fails=0`",
     "red": "`  ✗ …` 行（如顶匾缺格 / 账变屏不变（LCD）/ 泊港水粮被扣 / 跨月静默清空 / 旧值仍印）+ 末行 `LEDGER_STRIP_PROBE cases=N fails=N`（N>0），退 1"},

    {"id": "qa_economy_panel_probe", "tier": "must",
     "why": "升格判掂毕（lane w62-k4 执行窗，w61-k4 牒备件 v1，照 §五.2 三判据对原文）：判据 1「自己判不准」成立——触发条件具跨文件隐藏面："
            "名声栏级别名（GameState.add_fame / 名声跳级阈值与级别名表 / update_status_panel 名声行）、跳年册页代价截文案"
            "（try_advance_chapter / scripts/ui/ChapterSheet.gd）、札记折叠头与折叠内【月息】原文（skip_years / advance_days 月结"
            " / 「蕃商结息 N 钱，现欠 M。」）五路写口分处四文件（scripts/GameState.gd / scripts/ui/Main.gd / scripts/ui/ChapterSheet.gd"
            " / 探针自身），文案格式笔 lane 自己判不出该加跑哪条——§一 / §三.35 旧口径「按路径判得准、三条件只取第一」与 §五.2「三条同时成立」相悖"
            "就此勾销（w49-k1 同型拨正先例）；判据 2「快」成立——Godot 真场景树探针 glock 实测三跑 real 3.007 / 3.196 / 4.061 s（w62-k4 起派帧实贴），"
            "与本辑既有 Godot must 探针族（qa_rest_days 24 / qa_rest_scenarios 33 / qa_debt_strip 4 / qa_cargo_strip 27 · Godot 真场景树冷启 2-4 s）"
            "同族冷启档位同格（w61-k4 双轨判掂先例：族内类推成）；判据 3「只读」成立——源码 grep FileAccess / DirAccess / user:// / save / store_"
            "全零命中、零写盘、摆场全是内存 GameState 字典 seed；判据 4 main 尖幂等绿——glock 三跑连绿 rc=0、末行 ECON_PANEL_PROBE cases=N fails=0（N=19 = 17 断言行"
            " + script_err_tally 接线 2 格）。",
     "kind": "godot", "file": "tools/qa_economy_panel_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_economy_panel_probe.gd"],
     "judge": "（探针 1b7608f 立，w29-k3 入册——审计-wave27「最该补的门禁」第 3 条：与 qa_ledger_strip 同案缓兵两条的第二支）"
              "真场景树 C1–C2：名望 9→11 过跳级阈值后名声栏真印新级别名「名声　11　在册舶牙」（白走一年不晋升则旧名照印，时间不得造真）；"
              "欠债 1000 跳 2 年：册页代价截题头「【两年后・咸淳元年　十月三十】」与「——自…至于…。」起讫句、札记折叠头起讫年月名"
              "「自景定四年　冬月初一至于咸淳元年　十月初一」与则数凡月数、折叠内【月息】恰 24 则、末则原文「蕃商结息 N 钱，现欠 M。」与探针自对照账"
              "（3% 月复利 24 期，不引 GameState 常量防共同变量同错）字字相符；无债跳年册页与札记全本俱不见「蕃商结息」「现欠」（反向格）。"
              "本进程 SCRIPT ERROR 即红。末行 `ECON_PANEL_PROBE cases=N fails=0`，fails>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `ECON_PANEL_PROBE cases=N fails=0`",
     "red": "`  ✗ …` 行（如级别名不跳 / 白走一年造真 / 册页题头或起讫句变 / 折叠头则数凡月数漂移 / 【月息】原文与对照账不符 / 无债跳年见息字）"
            "+ 末行 `ECON_PANEL_PROBE cases=N fails=N`（N>0），退 1"},

    {"id": "qa_fold_notice_probe", "tier": "must",
     "why": "升格判掂毕（lane w74-k3 执行窗，w73-k5 复核牒 v1，照 §五.2 原条文逐条对）：判据 1「自己判不准」成立——触发条件具跨文件隐藏面：欠饷文案与欠月数口径（Crew.pay_wages / monthly_wage）、月结调用链（GameManager.advance_days :173 monthly_notice.emit）、札记通告上墨口（LogFold.push_notice / Main._log_lines·_notice_run 一则一墨 / _on_monthly_notice）、改元历名页首印年（Calendar._era_row / LedgerPage.update_panel / update_status_panel）五域写口分处六文件（scripts/core/Crew.gd / scripts/GameManager.gd / scripts/core/LogFold.gd / scripts/Main.gd / scripts/core/Calendar.gd / scripts/ui/LedgerPage.gd / 探针自身），文案格式笔 lane 自己判不出该加跑哪条——§三.36 旧口径「按路径判得准、三条件只取第一」与 §五.2「三条同时成立」相悖就此勾销（w49-k1 同型拨正先例）；判据 2「快」成立——Godot 真场景树探针 glock 实测三跑 real 2.015 / 1.982 / 1.985 s（w73-k5 动手帧实贴），与本辑既有 Godot must 探针族（rest_days / rest_scenarios / debt_strip / cargo_strip / economy_panel 2-4 s 冷启）同族同格且居快翼（w61-k4 双轨判掂先例）；判据 3「只读」成立——源码 grep FileAccess / DirAccess / user:// / save / store_ 全零命中、零写盘、摆场全是内存字典 seed；判据 4 main 尖幂等绿——glock 三跑连绿 rc=0、末行 FOLD_NOTICE cases=N fails=0（N=15：13 断言行 + script_err_tally 接线 2 格）。",
     "kind": "godot", "file": "tools/qa_fold_notice_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_fold_notice_probe.gd"],
     "judge": "（探针 896fd67 随 w28-k2 落地，w30-k1 入册——落地当轮漏注册只被「注册或豁免」闸点名待收，w30 立案根治）"
              "真场景树 C1–C2：现银摆 0、雇火长吴针（月俸 60）——欠饷当月札记顶则原文「本月工食 60 未发。船上人心浮动。」，"
              "连欠两月两则同句；欠满三月顶则原文「工食欠满三月，吴针 不告而去。」、人去册空欠月数归零；"
              "反向：人走后当月札记不添新墨，顶批仍是上月三则。C2【改元】：1278 四月历走一页抵五月，"
              "页首「景炎三年」换印「祥兴元年」、旧号「景炎」不再上屏；改元无札记通告，全本札记不着「改元」「祥兴」字样（反向格）。"
              "本进程 SCRIPT ERROR 即红。末行 `FOLD_NOTICE cases=N fails=0`，fails>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `FOLD_NOTICE cases=N fails=0`",
     "red": "`  ✗ …` 行（如欠饷原文变 / 欠满三月不走 / 人去仍添墨 / 元历不换印 / 旧年号残留 / 札记见息义字样）"
            "+ 末行 `FOLD_NOTICE cases=N fails=N`（N>0），退 1"},

    {"id": "qa_rest_scenarios_probe", "tier": "must",
     "why": "升格：lane w49-k1 依 w42-k6 判词表「可升级升格片（五判全齐）」授权锚第五件、照 w48-k4 牒备件五节 (i)–(v) 套牒升进必跑（注册表 REGISTRY 序原位 :37）。"
            "判不准成立——歇宿钮面 ↔ 两贴文路径同亮钩跨六路写口（TavernPage.setup_inn 与 ResidencePage._setup_residence 歇候钮绑定、Main._slip_chip / _contract_rest_mark / INN_RATE·HOME_RATE 歇价契文、寺观 hook_xinghua_asked 贴文反驾路、探针自身），改动 lane 多半想不起加跑这条 lane 当次只加跑的探针；"
            "速档按 §五.2 自书 GDScript 引擎实测牒不咎一键跑既有 Godot must 本辑（一键跑自含 smoke 8.0s / compile 3.3s / story 104s / patrol 24s，§五.2 自书基线总约 60s），本支三跑 2.45–2.64s 与 cargo_strip 同带居快翼（现 33 案形与 18 案形耗时同带，k5 并网判已落定）；"
            "只读零写盘成立——源码零 FileAccess/DirAccess/user:///save(/write/store_ 出口，摆场只 in-memory 置开局态 + 真场景树读钮面枚举态，advance_days 摆日不落盘；误红面不扩（无 ⚠ 放行面）。",
     "kind": "godot", "file": "tools/qa_rest_scenarios_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_rest_scenarios_probe.gd"],
     "judge": "（探针 09bb75a 随 w28-k1 落地，w30-k1 入册——与 qa_fold_notice 同案漏网两支的第二支；"
              "qa_rest_days 钉了旅店一景的印数与实扣，本探针钉同一批钮在两条贴文路径下各自亮起）"
              "真场景树（兴化旅店 / 泉州住处 1277-10-19 钱足）：旅店一景「歇 1 日　15 / 歇 10 日　150 / 候 12 日　180」"
              "三钮恰 3 枚同出一枚钮行、枚枚文字逐字对且 visible / 可按 / 焦态逐字同；住处一景「歇 1 日　5 / 歇 3 日　15」"
              "恰 2 枚同出一行、无候风钮——旅店那枚随日候钮不把印数带去住处（两路并列同一见证串各亮各的）；"
              "反驾：寺观工席走同一管贴文路（钩旗放进 hook_xinghua_asked 后确有贴文但不进歇息这条），歇息 / 候钮 0 枚混出。"
              "本进程 SCRIPT ERROR 即红。末行 `REST_SCENARIOS cases=N fails=M`，M>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `REST_SCENARIOS cases=N fails=0`",
     "red": "`  ✗ …` 行（如钮缺枚 / 同出一行不齐 / 见・暗・焦不符 / 候钮串住处 / 寺观该暗亮出）"
            "+ 末行 `REST_SCENARIOS cases=N fails=M`（M>0），退 1"},

    {"id": "qa_debt_strip_probe", "tier": "must",
     "why": "lane w43-k3 升格落地（w42-k6 判词表「可升级升格片」五判全齐唯一授权锚）：欠债格钩在 HUD 顶匾上行"
            "（GameState.debt 增减 / LedgerPage 顶匾格 / Economy 月结三路写口），改动 lane 多半想不起加跑，"
            "按 §五.2 判该升必跑。升格判据勘定：§五.2 速档字面「1 秒量级」依其自书 GDScript 引擎实测牒"
            "（RefsMac 0.23s / RefsHost 0.70–1.02s / decision 0.5–0.6s）原不咎一键跑本辑五支 Godot must"
            "（一键跑本自含 smoke 8.0s / compile 3.3s / story 104s / patrol 24s 远档，§五.2 自书基线总约 60s），本支三跑"
            "2.07–2.47s 居本辑快翼；判据 3 只读成立——源码零 FileAccess / DirAccess / user:// / save( / "
            "ResourceSaver，摆场只 in-memory 置 gs.debt 后 update_status_panel 重排，不经月结、不写盘。"
            "w42-k6 C1–C5 原判全齐照引。",
     "kind": "godot", "file": "tools/qa_debt_strip_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_debt_strip_probe.gd"],
     "judge": "（探针 dc30a97 随 w30-k2 落地，w31-k3 入册——落地当轮漏注册只被「注册或豁免」闸点名待收，"
              "wave31 立案根治，与 w29-k3 / w30-k1 同型 8170079 母本）"
              "真场景树 D0–D3 把 HUD 顶匾上行欠债格钉成运行时真断言：debt=0 时上行不印「欠 」（反向格，"
              "LedgerPage.gd:167 的 debt 变量在欠债清零为空串）；摆 debt=835 / 100 / 10000 三档，"
              "上行各逐字印「欠 835」「欠 100」「欠 10000」（bbcode 源文里 [color=#…]欠 N[/color]，数字裸排）。"
              "本进程 SCRIPT ERROR 即红。末行 `DEBT_STRIP cases=N fails=M`，M>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `DEBT_STRIP cases=N fails=0`",
     "red": "`  ✗ …` 行（如无债仍印「欠 」/ 三档欠数逐字不符——红行带实读前 110 字节）"
            "+ 末行 `DEBT_STRIP cases=N fails=M`（M>0），退 1"},

    {"id": "qa_crew_fold_probe", "tier": "lane",
     "when": "动欠饷链（scripts/core/Crew.gd 的雇佣 / 月俸合计 / 欠月数 / 不告而去口径、"
             "scripts/core/Economy.gd 月结扣工食）、札记折叠渲染（scripts/core/LogFold.gd 的 render "
             "fold:i 折头 /（点开）/（收起）/ 月行引子与淡色缩进），或动 tools/qa_crew_fold_probe.gd / "
             "tools/qa_crew_fold_host.gd 自身",
     "kind": "godot", "file": "tools/qa_crew_fold_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_crew_fold_probe.gd"],
     "judge": "（探针 e6fd6f1 随 w30-k3 落地，w31-k3 入册——与 qa_debt_strip 同案漏网两支的第二支）"
              "真场景树 C1：泉州名册现读窄样本两人（俸居首一名 + 最薄一名，合计现算），现银摆 0——"
              "札记顶则「本月工食 <合计> 未发。船上人心浮动。」逐字钉两月；欠满三月「工食欠满三月，<名> 不告而去。」"
              "现排名册逐字钉、俸居首者先走、走后册余合计 60 转句再连欠六月、册空后当批一则不添。"
              "C2：仿作宿主 qa_crew_fold_host 直调 LogFold.render（不经屏控件）——"
              "折起「[url=fold:0]【同一折句】（点开）[/url]」、点开后折头转（收起）、月行 "
              "`[url=fold:0:<ym>]` 引子与（点开 / 收起）、原文缩一格淡一档「　」逐字钉。"
              "本进程 SCRIPT ERROR 即红。末行 `CREW_FOLD cases=N fails=M`，M>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `CREW_FOLD cases=N fails=0`",
     "red": "`  ✗ …` 行（如工食合计数不符 / 欠满三月不走 / 册空仍添墨 / 折头或月行字样漂移 / 淡色缩进变）"
            "+ 末行 `CREW_FOLD cases=N fails=M`（M>0），退 1"},

    {"id": "qa_cargo_strip_probe", "tier": "must",
     "why": "lane w44-k1 牒备件定稿、w46-k1 依其套牒升格（w42-k6 判词表「可升级升格片」五判全齐授权锚第三件）："
            "船舱段货载钩在船籍簿页正文（scripts/core/Fleet.gd 的 cargo / add_cargo / remove_cargo 与容量口径、"
            "scripts/ui/LedgerPage.gd 船舱段 cargo_str 拼排、水粮占舱折算三路写口），改动 lane 多半想不起加跑，"
            "按 §五.2 判该升必跑。升格判据勘定：§五.2 速档字面「1 秒量级」依其自书 GDScript 引擎实测牒"
            "（RefsMac 0.23s / RefsHost 0.70–1.02s / decision 0.5–0.6s）原不咎一键跑本辑五支 Godot must"
            "（一键跑本自含 smoke 8.0s / compile 3.3s / story 104s / patrol 24s 远档，§五.2 自书基线总约 60s），本支三跑"
            "2.07–2.19s 居本辑快翼、与 w43-k3 qa_debt_strip 2.07–2.47s 同带；判据 3 只读成立——源码零 FileAccess / "
            "DirAccess / user:// / save( / ResourceSaver，摆场只 in-memory 置 gs/cal 开局态后 update_status_panel 重排，"
            "不经月结、不写盘。w42-k6 C1–C5 原判全齐照引。",
     "kind": "godot", "file": "tools/qa_cargo_strip_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_cargo_strip_probe.gd"],
     "judge": "（探针 0ef543a 随 w29-k2 落地，w31-k3 入册——其落地晚于 w29-k3 注册片，隔波留账一并收编）"
              "真场景树 C1–C6 把船籍簿页「船舱」段上屏原文钉成运行时真断言：空舱印「[b]船舱[/b][/color]\\n空\\n」"
              "与「舱位　30 / 200 料」（sampan 200 料 − 水粮 30 料）、「足 20 日」同屏；进茶叶 ×10 / 苏木 ×12 逐字上屏、"
              "舱位 30→47 料随变；再加 ×5 改印「茶叶 ×15」旧值退；出货清空回「空」；账变不刷陈旧哨（读缓存副本即红）；"
              "重排后整页须过空仓变化 + 仍含「[b]船舱[/b]」格 +「船舱」不得漏进顶匾上行。"
              "本进程 SCRIPT ERROR 即红。末行 `CARGO_STRIP cases=N fails=M`，M>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `CARGO_STRIP cases=N fails=0`",
     "red": "`  ✗ …` 行（如空舱形态变 / 品名数量逐字不符 / 舱位不随货变 / 旧值仍印 / 陈旧哨落网 / 船舱字漏上顶匾）"
            "+ 末行 `CARGO_STRIP cases=N fails=M`（M>0），退 1"},

    {"id": "qa_fold_dim_probe", "tier": "lane",
     "when": "动札记折叠低色链（scripts/core/LogFold.gd 的 render dim_rest=true 分支——"
             "港页记事栏头则宣纸色、其余淡一档的折行 / 月行上屏形态），"
             "或动 tools/qa_fold_dim_probe.gd / tools/qa_crew_fold_host.gd 自身",
     "kind": "godot", "file": "tools/qa_fold_dim_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_fold_dim_probe.gd"],
     "judge": "（探针随 w32-k2 落地即入册——w30-k3 交主控末条「按月分组的 fold:i:ym 展开后单列那一月」"
              "未守面实查：qa_crew_fold_probe C2 三次直调全是 render(host, \"\\n\", false) 海图札记档，"
              "dim_rest=true 分支日常由港页记事栏跑、此前全仓无一探针点过；与 w29-k3 / w30-k1 / w31-k3 "
              "同型 8170079 母本登 lane 档，不 EXEMPT）"
              "仿作宿主 qa_crew_fold_host（w30-k3 同件）直调 LogFold.render（不经屏控件）8 案："
              "D1 单条染字——次则折起行裹一层暗色、折头（点开）引子 [url=fold:1] 原样在内；"
              "头则平常句照原墨不裹色、次则平常句整句裹色。"
              "D2 折行排头——点开之折当次则：折头（收起）与其下头一行月行各裹各的一层暗色、"
              "引子 [url=fold:1:<ym>] 与「通告 1 则（点开）」逐字在内。"
              "D3 相变——同一摆场 dim=false 全串无 [color=，转 true 次则折头裹色（褪色随档转、不是常染）。"
              "本进程 SCRIPT ERROR 即红。末行 `FOLD_DIM cases=N fails=M`，M>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `FOLD_DIM cases=N fails=0`",
     "red": "`  ✗ …` 行（如次则不褪色 / 头则误染色 / 折行排头双层变 / 换档不转色）"
            "+ 末行 `FOLD_DIM cases=N fails=M`（M>0），退 1"},

    {"id": "qa_seachart_advance_probe", "tier": "lane",
     "when": "动 SeaChart 海图「航段」名号链（scripts/ui/SeaChart.gd 的 _course_detail_text / 面板刷新——"
             "泊港选定航向印「航段　<目的地>」名号、advance_days 跨月当日面板改印静风日数与月份名串、"
             "出航后名号自面板隐去），或动 GameManager.advance_days 跨月路径，"
             "或动 tools/qa_seachart_advance_probe.gd 自身",
     "kind": "godot", "file": "tools/qa_seachart_advance_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_seachart_advance_probe.gd"],
     "judge": "（lane w28-k3 立、w35-k2 收编——EXEMPT 挂账 21 波已收，同 w31-k3 / w35-k1 收编先例）"
              "真场景树 C1–C4 把 SeaChart 海图「航段」名号跨月推进时序钉成运行时真断言："
              "C1 泊港选定航向印「航段　澎湖」名号 + 静风日数；"
              "C2 advance_days 跨月当日面板立即改印，不隔帧才变、不留旧月值；"
              "C3 出航正隐——sailing 时「航段」名号自面板隐去、抵港后随原名号复现；"
              "C4 跨越多月长程：泉州→博多跨 ≥1 月，「航段　博多唐房」名号随当值月风逐月仍在。"
              "本进程 SCRIPT ERROR 即红。末行 `SEACHART_ADV cases=N fails=M`，M>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `SEACHART_ADV cases=N fails=0`",
     "red": "`  ✗ …` 行（如名号缺字 / 静风日数不合 / 跨月不改印 / 留旧月值 / 出航不隐 / 抵港不复现 / 长程跨月名号消失）"
            "+ 末行 `SEACHART_ADV cases=N fails=M`（M>0），退 1"},
    {"id": "qa_calendar_probe", "tier": "lane",
     "when": "动 scripts/core/Calendar.gd（日推进 / 改元表 / ERA_START / _era_row / 中文数字月日名）"
             "或船籍簿页首行上屏链（LedgerPage.update_panel 的日历行 / Main.status_label / update_status_panel），"
             "或动 tools/qa_calendar_probe.gd 自身",
     "kind": "godot", "file": "tools/qa_calendar_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_calendar_probe.gd"],
     "judge": "（探针 f3f092e lane-w26-k9 立、EXEMPT 挂账实过 26 波，w35-k1 收编——同 w31-k3 8170079 收编先例）"
              "真场景树 C1–C3 把「宝祐三年　三月初一」是会被玩家推进的真日历钉成运行时断言 36 案："
              "C1 开局挂树页首印「宝祐三年　三月初一」，advance_days(29) 印「三月三十」、再 +1 跨月印「四月初一」；"
              "C2 页首月名 = 探针自拼参考月名（不引 Calendar.CN_NUM，防共同变量同错）12 月逐月各核 + 与前月页文不同（LCD）；"
              "C3 改元与纪年——景定元年正月一改元、页首年号 = 日历 _era_row() 同一基准不抄表；"
              "1276-04 印「德祐二年」、1276-05 印「景炎元年」逐月切换（w32-k2 自荐料：景炎 1276-05 起用，ERA_START 1276,5）、"
              "1276-06 印「景炎元年　六月初五」、1278-05 印「祥兴元年」、祥兴元年正月三十 +1 日 = 「二月初一」年号不变。"
              "本进程 SCRIPT ERROR 即红。末行 `CALENDAR_PROBE cases=N fails=M`，M>0 退 1",
     "green": "逐条 `  ✓ …` + 末行 `CALENDAR_PROBE cases=N fails=0`",
     "red": "`  ✗ …` 行（如开局日不对 / 推进页首不随动 / 月名对不上或同值漏检 / 改元切换错位 / 正月三十跨月不进）"
            "+ 末行 `CALENDAR_PROBE cases=N fails=M`（M>0），退 1"},


    {"id": "qa_siege_destinations_probe", "tier": "lane",
     "when": "动委办目的地链（scripts/GameState.gd 的 _contract_destinations / contract_offer / _contract_seed——"
             "出队排除口径、报价优选针路已知池、月份种子），或动 Economy.war_status / is_market_open / 数据行 ports.json war 表，"
             "或动 tools/qa_siege_destinations_probe.gd 自身",
     "kind": "godot", "file": "tools/qa_siege_destinations_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_siege_destinations_probe.gd"],
     "judge": "（lane w36-k2 立作 V0928-1 复现档；lane w53-14 定 A+ 并修：_contract_destinations 排牙行闭门港，"
              "本探针转回归档，红即回退）"
              "态 A 真场景摆场六案（兴化 1276-11 / 1277-09、福州 1276-10、广州 1276-11 围城，博多唐房、萨摩 1274-11 封港——"
              "数据行 war 表现表）直调 _contract_destinations / contract_offer 真输出：闭门港不掺任何一份出队目的地、"
              "报价目的不落当月闭门港；另 192 月窗（1274-01 起）逐月逐港逐代表货扫描，出队里有当月闭门港即印 "
              "`QA_SIEGE_DEST_HIT` 并计红。态 B 未闭门月 1275-06 反向基：广州发香药兴化上队、泉州报价非空、泉州发茶博多上队。"
              "态 C 不误伤：闭门月里没闭门的港（已陷的福州、未围的兴化、封港月的澎湖广州）照旧在出队里。"
              "M1 附加参 `--mutate-siege-always` 把闭门判值倒成恒真（只动探针读口）→ 态 A 扫描与态 B 红。"
              "本进程 SCRIPT ERROR 另立 S 档即红（w53-11：`QA_SIEGE_DEST_S fails=K` 计入总 fails，态 A / B / C 判据不动）；"
              "_run 半路被脚本错掐断由收尾包装判红退 1、不印末行——判绿仍须 rc=0 且末行 `QA_SIEGE_DEST_END` 在。"
              "必跑面另有 verify_economy 的复刻选型与 `is_market_open` 取体钉（同一缺陷两头都红）。",
     "green": "`QA_SIEGE_DEST_HIT （无）` + 末三行 `SIEGE_DEST hits=0 ok=M fails=0` + `结果：全部通过` + `QA_SIEGE_DEST_END`，退 0",
     "red": "`  ✗ …` 行（闭门港掺队 / 报价目的落闭门港 / 192 月窗扫出 `QA_SIEGE_DEST_HIT` = 排除链回退；"
            "`✗ … 出队仍含 …` = 排得太宽、误伤开着的港）"
            "+ 末行 `SIEGE_DEST … fails=K`（K>0），退 1；本进程脚本错 `✗ 运行中无 SCRIPT ERROR …` + `QA_SIEGE_DEST_S fails=K`（K>0）；"
            "`QA_SIEGE_DEST_END` 缺且 rc=124 = 超时中断，不计红绿"},


    {"id": "qa_save_stale_count1_probe", "tier": "lane",
     "when": "动 scripts/core/SaveLoad.gd 的 audit_stale_refs 港类核验（_flag_port / out[\"port\"] 落键口径），"
             "或动 tools/qa_save_stale_count1_probe.gd 自身",
     "kind": "godot", "file": "tools/qa_save_stale_count1_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_save_stale_count1_probe.gd"],
     "judge": "（lane w38-k1 · 无门禁 sweep 补位——j3mut 退化纹钉件，w36-k3 交主控 #2 A 类原句立）"
              "「恰 1 枚已删港名目」存档直调 load_game → last_stale（母本 save_stale_refs_probe.gd 同型写信道位 97）："
              "现网 audit_stale_refs 对恰 1 枚须落 out[\"port\"][\"count\"]==1、sample==该 id、examples erase。"
              "K1 现网临界（visited_ports 恰 1 枚）；K2 三个触发位各仅 1 处指向 stale 港（visited_ports / last_port / "
              "contract.from）各落 count==1；K3 对照 0 枚（port 键不在）/ 双旧港 count==2 / 同 id 双现去重仍 count==1。"
              "`> 0` 被退化成 `> 1`（j3mut 实证在卷）则 K1/K2 整段漏报 → 本探针 fails≥1 诱曝，现样全绿。"
              "本进程 SCRIPT ERROR 即红（w53-11：K1–K3 七案外另计两判——计数器自证 + 运行中 0 条；_run 半路被脚本错掐断由收尾包装判红退 1、不印末行）。"
              "末两行 `STALE_COUNT1 cases=N fails=M` + `QA_STALE_COUNT1_END`，M>0 退 1。",
     "green": "逐条 `  ✓ …` + 末两行 `STALE_COUNT1 cases=N fails=0` + `QA_STALE_COUNT1_END`，退 0",
     "red": "`  ✗ …count 期望 1 实得 0…`（`> 0→> 1` 漏报恰 1 枚——j3mut 退化纹）/ `… sample 期望 …` / "
            "`… examples 未 erase …` 各指名行 + 末两行 `STALE_COUNT1 cases=N fails=M`（M>0），退 1"},
    # lane w56-k3 升格：w53-10 SETTLED :954 落 tools/check_w53_copy.py（@79ab7e0）注册挂账未拍——w55-k3 判档段
    # 帧注 gate_json grep 0 命中照实注①、w53-12 同窗 @0893e47 寄挂 check_symbols 十五节（未入主实锤）双轨并现；
    # 本片照 §五.2 三判据原文逐项签 + 第四格「不许扩大误红面」判掂 = 升 must 档，判语原文签成 why 段：
    {"id": "check_w53_copy", "tier": "must", "kind": "py", "file": "tools/check_w53_copy.py",
     "why": "升格（lane w56-k3 依 w53-10 SETTLED :954 钦命 + w55-k3 判档段帧注 gate_json 0 命中 + w53-12 @0893e47 寄挂双轨并现——"
            "寄挂单未入主实锤）：照 §五.2 三判据逐项判语原文签——"
            "① trigger 判不准成立：两枚回潮错样都是文案修笔顺手带进——半角「前帐」误「前账」（scripts/Main.gd 玩家可见 CJK 日志）"
            "与状态增减半角 -N 误全宽 −N（GameState.gd 委办毁约 / 逾期两条），lane 自己写文案 / 按教程照抄顺手带回的一类，"
            "与 gd21 Mac 白字 / cs21 Host 白字同型——when 写不到判不准那类；"
            "② 快 1 秒量级成立：起派实跑 time python3 tools/check_w53_copy.py 三跑 real 0.075 s / 0.086 s / 0.080 s"
            "（8 vCPU / load 20+ 帧），≪ 一键跑既有 python must 闸任一支；"
            "③ 只读零写盘成立：源 grep -nE 'write|FileAccess|DirAccess|user://|store_|--regen|--write' 0 命中（rc=1 预期），"
            "脚本唯 open() 读 scripts/*.gd 与 data/*.json 静态扫，零写盘开关；"
            "＋第四格不许扩大误红面成立：CI_STEPS 现帧不含 check_w53_copy → §五.2 五处同步第 ④ 处零动照实注；"
            "主树未跟踪文件 git ls-files --others --exclude-standard 0 行照桩；w53-{1,10,12} 同窗现场（pid 活）"
            "其 lane 域（scripts/GameState.gd / docs/待策划拍板清单_* / tools/qa_w53_* / tools/_tmp_wave53_1_*）零动——"
            "本闸扫主树玩家可见 CJK 串、扫自己属于其 lane 域照扫不互相染红；"
            "＋「升 must 的前提是 main 尖上它是绿的」成立：起派帧 main HEAD = 296b194、本闸起派实跑 rc=0「结果：全部通过」。",
     "judge": "（lane w53-10 立，w56-k3 升 must 入册）玩家可见 CJK 串两类回潮钉静态扫（scripts/*.gd + data/*.json）："
              "一、规则一禁「前帐」字样（FORBID_SUBSTRINGS——「先结了前帐罢」是唯一账务「帐」误「账」，"
              "其余「帐」全是军帐 / 营帐正用，check_symbols / qa_letterbox_copy 域不扫「帐」整字符）；"
              "二、规则二禁「名声 -」「士气 -」「金钱 -」「水粮 -」「耐性 -」「悦 -」半角连字符紧接着数字"
              "（HALF_MINUS_RE = 「名声」「士气」「金钱」「水粮」「耐性」「悦」一字样 + 空白 + - + 数字——玩家面统一全宽 −（U+2212），"
              "STAT_WORDS 钉死枚举不扩「蒲家留意 -2」类）；扫域是含 CJK 的字符串字面量 / JSON 文本值；"
              "负样本自检每次先跑（「前帐」样与「名声 -1」样各须被自家检出、不检出即自红）",
     "green": "末行 `结果：全部通过`（含前置 `_self_test` 负样自检两格全判红、扫真源码 0 hit）",
     "red": "`结果：N 项问题` + ✗ 行点名（`scripts/Main.gd:<行号>: 账务「账」误作「帐」——含「前帐」字样：<原文 120 字>`"
            " / `scripts/<X>.gd:<行号>: 状态增减半角连字符（应为全宽 −）——<原文 120 字>` / data/<f>.json 同类两行）"},
    # lane w57-k2 立：w53-4 SETTLED 行署「CAS fbc7580→e3a7d10 真 ff」而其 branch wave54→wave57
    # 三波曾未入主 = 断链型 lane（史上首次 SETTLED 与 branch 未入主并存超波）——先 lane 档挂账：
    # trigger 判不准（lane 自身 CAS 撞窗主控零碰 / lane-self 权域那类判不到），判掂应用 = 判不准即挂账。
    {"id": "check_lane_orphans", "tier": "must", "kind": "py", "file": "tools/check_lane_orphans.py",
     "why": "升格（lane w60-k3 wd20 依 w57-k2 SETTLED 钦 + w59-k3 牒备件 §五.2 三判据逐项签毕；主控 wave60 ops 采形 = 形 B）："
            "① trigger 判不准成立——trigger 域 = 仓外 COORDINATION 行首格式 × refs/lane SHA 链 × main 史祖先关系，"
            "非仓内路径可锚（§五.1 lane 档判据文「按改了哪些路径客观判定」写不出）；w53-4 断链三波实案在案；"
            "② 快——形 B 批量化：w59-k3 牒量具实测 light 层 0.047-0.157s / 批量化 0.368-0.558s 达 1 秒档"
            "（生产形 6.1-6.9s 不升；w60-k3 承办实跑落笔 = 一轮 rev-list 建主史集 + 短形主史 7 位前缀拼，"
            "3 跑墙钟 ≤1 s、判语 0 字节 identical）；"
            "③ 只读零写盘——三 grep 零命中 + NK1_COORD/NK1_MAIN_REF 量具钩非写口 + errors='replace' 读档（w60-k3 承办补："
            "代替崩 UnicodeDecodeError；受损区字面 SHA 不再匹配即「未在册」等效，判红管道照常）。",
     "judge": "断链预防闸：扫仓外 nk1-agent-briefs/COORDINATION.md 行首 SETTLED 行抽 lane id 集、"
              "对每条 lane 四格全中才红——① 行首 ^w 数字-[字母]数字 SETTLED 在（时间戳前缀 / SETTLED-ADD 修订 / "
              "文内提及不算，同 lane 多行取最新一行）；② 行 SHA 链自洽探：一轮 git rev-list main 建主史集，"
              "全形查集 / 短形按主史 7 位前缀拼（对象在主史零命中 anc=F——cat-file 补缺防 w30-k5 d09d20a 短形叛绿实锤），"
              "全在史照桩，ancestor=F 且行署 未CAS/承接/收编/重链/未入主/撞窗/悬空/归轨道/零动/殓/遗留 类判语 = lane 自报置笔未入主照采信，"
              "只有 ancestor=F 且零判语（署名失实）入红集；③ refs/heads/lane/<lane>-* 在册且尖 ancestor=F；"
              "④ main..branch 尖 count>0（lane-committed 未入主、尚无人承接）且 ② 有未释 SHA。"
              "唯 NK1_COORD/NK1_MAIN_REF 两环境变量供量具变异；生产零 env。",
     "when": "每轮必跑（现牒 = 升 must 完毕：§三一键跑 / todo 验证段 / README 二十六皆同步）",
     "green": "末行 `结果：全部通过`（各 lane branch 或已入主 / 或 SHA 在史 / 或 lane 自报置笔未入主照采信 / "
              "或 SETTLED 行缺失照桩）",
     "red": "✗ `lane <id> SETTLED（COORDINATION:<行号>）但行 SHA <sha> 未入主（ancestor=F）且行零未CAS/承接/收编/重链判语"
            "（署名实锤失实）+ branch <ref> sha <sha> main..count=N（承接窗断链）` 逐条点名 + 首行 `结果：N 项问题`，退 1"},
    # lane w62-k3 立：w61-k2 SETTLED 遗留②原句钦（判词池承接件 v1）——M1' 实跑四闸对文档词级
    # 污染该形 rc=0 静默绿实锤的判力窗，立本闸罩「殓殓」词级指纹（防新增、不回扫旧账）。
    {"id": "check_ledger_garbage", "tier": "must", "kind": "py", "file": "tools/check_ledger_garbage.py",
     "why": "升格判掂毕（lane w68-k1 执行窗，w65-k2 牒备件 v1 五处同步牒 §三 (i)–(v) 全案，照 §五.2 原条文逐条对）："
            "判掂 1「自己判不准」成立——「殓殓」词级指纹是内容级污染非路径级 trigger，写殓档段的 lane 判不出哪一笔带它"
            "（新一轮判档段 append / 主控 CAS 承接 / 照抄参考句盲拷贝 / 判词池承接 / 快照承接 5 路写口；"
            "w61-k2 M1' 实锤四闸 rc=0 静默绿在卷 = 判力窗）；判掂 2「快」成立——纯文扫单判道墙钟 <0.1 s"
            "（与 w56-k3 check_w53_copy 0.075 s 同档）；判掂 3「只读」成立——零写盘开关、唯读清册一档；"
            "判掂 4「幂等绿」成立——v5 闸体承接毕 rc=0 连绿、基线 rc=1（:742/:816 自然引用）顺手拨颁销账 13→15；"
            "判掂 5「五处同步」毕——§三一键跑段 / todo 验证段 / README 道数 27→28 全衔 + COORDINATION_INDEX 口径注补。"
            "v5 闸体承接自 lane/w65-k2@5f2331e 逐字节（R1 单枚细判窗 + R2 ≠ 恒等基线双端红 + W5/W6 自检格）。",
     "judge": "扫 docs/仓务清册_2026-10-03.md「殓殓」词级污染指纹（非叠对 str.count 口径）："
              "R1 白名单 KNOWN 表（现帧 15 行 11 键）外某行「殓殓」≥ 1 枚逐行 ✗ 点名行号与枚数（v5 单枚细判窗——"
              "合法自然引用走行首 CJK 免挂载 :639/:644 先例 + KEY 钉行全收、ASCII/数字/反引号起字行不享防 hash 壳蒙绿）；"
              "R2 全文档含「殓殓」行数 ≠ TOKEN_LINES_LINEBASE（现帧 15）恒等式判红——超线/欠线两头皆红"
              "（删行藏污形也落红）；KNOWN 表行照挂零报；零、样本自检每次先跑（S1 新行 3 枚 / S2 单行 5 枚 / "
              "S3 行数超线 / S5 单枚 ASCII 壳 / S6 欠线五格须判红，C1 基线形 / C2 「殓」正用 / C5 尾 append 推位 "
              "须判绿、C3/C4 零点档恒等式勾稽在衙，同一条 scan_text 判路）；清册读不到 rc≠0（无文件形判红防静默绿）。"
              "唯 NK1_LEDGER 一环境变量供量具变异，生产零 env。",
     "when": "每轮必跑（升 must 完毕：§三一键跑 / todo 验证段 / README 二十八 皆同步；拨钉走 §五.3）",
     "green": "末行 `结果：全部通过`（零节 12 格 ✓ + 真文档 `新增 0 格（含「殓殓」行 15/15 键行照挂）` ✓）",
     "red": "✗ `<档>:<行号>: 新增「殓殓」×N（词级污染指纹，白名单外行）` / ✗ `含「殓殓」行数 N ≠ 恒等基线 15` "
            "逐条点名 + 自检 ✗ / 读不到清册 ✗——首行后 `结果：N 项问题`，退 1"},
    # lane w64-k1 伙伴系统三件落地（承接笔 789a226）带两件入仓、本波 w71-k3 收编注册档——
    # ① check_companions（companions.json 骨架校验闸、w64-k1 三件之一）；② qa_companion_preview_probe
    # （预览浮页运行时探针、w64-k1 三件之二、其 EXEMPT 挂账行「本波落地后随稽登记注册档」本波收编摘行）。
    # 判掂照 §五.2 原条文：trigger 自己判不准（改 companions.json / CompanionPreview.gd 的 lane 想不起加跑这两件）、
    # 快（check_companions 纯 stdlib <1 s；探针 headless 秒级）、只读零写盘（皆零写盘开关）——lane 档非 must 不动必跑集合。
    {"id": "check_companions", "tier": "lane", "when": "动 data/companions.json 或 tools/check_companions.py",
     "kind": "py", "file": "tools/check_companions.py",
     "judge": "（lane w64-k1 立，w71-k3 收编注册档入册——承接笔 789a226 入主后挂账收编）data/companions.json 骨架校验："
              "字段两档（已定字段照草案名册 v2 照数搬入逐条校验；未定字段一律恰写 \"_todo\"、留空判绿不判红）；"
              "域全从本仓现算不手抄（region/category/窗口方式/入伙方式/战位/立场读 companions.json meta 各 def，职事 id 读 crew.json roles，"
              "faction id 读 characters.json meta.faction_def，港 id 读 ports.json，货 id 读 goods.json，特技 id 读 characters trait_def ∪ 名册 new_traits）；"
              "九节判词——零、判据自检（内存变异：删已定字段 / id 重号 / 名字重号 / 未定填词表外值 / 窗口写年份整数 / 撞 crew 候名 / "
              "云屯两人 duty 空壳不齐 / 挂不存在的港各须红、好样本删红须绿，判不出即闸自身坏先红）；一、顶层与条目数（companions 恰 40、events 恰 60 各 id 唯一）；"
              "二、身份骨架（name 唯一、region/category/verify/reuse_character/p1/p1_stub 形态与枚举）；三、langs list<str> 非空；"
              "四、appear（chapter_min∈[1,5]、windows≥1 段、YYYY-MM 定长 1255–1285 窗内 from≤to、mode∈meet_mode_def、ports∈ports.json、route 1–2 段端名∈本表港∪ports∪{any}、rumor 非空）；"
              "五、join（type∈join_type_def、hire 者 fee≥0、bond 者 bond_need∈[0,100] 且 bond_path 合计≥bond_need、guest 者 fee==0、requires 只含登记键）；"
              "六、duty（键皆职事 id、品级∈[1,3]、月俸∈WAGE 档、battle⊆battle_slot_def 去 none、local 型 duty 空壳、其余 home_port∈ports.json）；"
              "七、niche kind∈niche_kind_def；八、stance/traits/gifts/climax 枚举与子集；九、未定字段恰 \"_todo\"、events 的 who⊆companions id∪{player}、verify∈{待核,已核}）。纯 stdlib 只读 <1 s",
     "green": "零节 `✓ 自检 16 格…全判对` + 一—九节各 `✓ …全对` + `✓ 伙伴 id 与 crew.json 候选不撞` + 末行 `结果：全部通过`",
     "red": "✗ 行点名（`✗ 第 k 条 <id>：…` 字段缺值 / 类型错 / 枚举越域 / id 重号撞名 / `_todo` 误填词表外值）+ 自检 ✗——首行后 `结果：N 项问题`，退 1"},
    {"id": "qa_companion_preview_probe", "tier": "lane",
     "when": "动 scripts/companions/CompanionPreview.gd（浮页上屏文案 / 钮面 / 字段 / PREVIEW_IDS 名单）、"
             "data/characters*.json 的六预览人物 display_name，或动 tools/qa_companion_preview_probe.gd 自身",
     "kind": "godot", "file": "tools/qa_companion_preview_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/qa_companion_preview_probe.gd"],
     "judge": "（探针 w64-k1 立，w71-k3 收编入册摘 EXEMPT——其挂账行原语「本波落地后随稽登记注册档」；"
              "承 w27-k1 顶匾同工：CompanionPreview 浮页此前只有截图探针判图不判字，上屏物运行时断言零）"
              "真场景树 13 案钉「上屏可见物」运行时断言（不读内部变量）：C1 F7 打开浮页真实挂上；C2「草案预览」戳上屏；"
              "C3 合上钮在、字恰「合上」；C4 题签「同舟草签」；C5 卡格恰 6 张对齐 PREVIEW_IDS；C6 六卡名签逐字=PREVIEW_IDS 对应 display_name；"
              "C7 每卡有 Identity 或 Note 一格；C8 每卡有「剪影」标记；C9 脚注「只读示意　不入存档　非招募系统」逐字；"
              "C10 再按 F7 合上；C11 港页再开戳与卡数仍对；C12 关浮页重进不串档；C13 本进程 SCRIPT ERROR 即红（script_err_tally）。",
     "green": "逐条 `  ✓ …` + 末行 `COMPANION_PREVIEW cases=N fails=0`",
     "red": "`  ✗ …` 行（戳 / 钮面 / 卡数 / 名签 / 脚注缺或漂 / SCRIPT ERROR）+ 末行 `COMPANION_PREVIEW cases=N fails=M`（M≥1）退 1"},
]

# w27-k4 CHECK FOLLOWS
# lane w27-k4：探针「注册或豁免」闸——k11 审计「最该补的门禁」第 2 条（「每支不被一键跑引用的探针，
# compile 门禁之外加一道『注册或豁免』闸」；qa_rest_days_probe 漏注册是 k11 原罪支（wave27 k3 已收编进 head REGISTRY lane 档），
# 本道普查所有同类漏网）。放 CHECK 章节而非 REGISTRY 头段：与 wave27 k3 同文件并行不冲突（k3 在头段 REGISTRY 追加）。
# 三条 §五.2 升格理由齐备——触发条件自己判不准（新探针入库的人想不起来要注册，qa_rest_days 漏 3 个月）、
# 快（实测 <1 s）、只读（git ls-files + 读名单，不写盘）；故入册即 must，进一键跑末条。
# w28-k4 续扫实况（落地基线 0f217b9，2026-10-03）：「注册或豁免」闸本身全绿（探针 44 支 / 豁免 24 行），
# w28 k1–k3 三支新探针（qa_rest_scenarios / qa_fold_notice / qa_seachart_advance）与 w27 残留 j4 的 qa_narrow_ui_probe
# 落地时均未 CAS 上主树，无件可登；k8 的 qa_chars_wire_screenshots 已随 6a81f89 落 SHOT_PROBES 截图册（主树收 k8 时带走的）——
# 零新增 / 零豁免，存此实况备查，下波有探针落地先过本道闸。
CHECK = [
    {"id": "check_probe_registry", "tier": "must", "kind": "py", "file": "tools/check_probe_registry.py",
     "judge": "（lane w27-k4，k11 审计「最该补的门禁」第 2 条）tools/ 下每支 git 已跟踪 `*_probe.gd` 要么被点名"
              "（REGISTRY file 列，或 SHOT_PROBES 截图册——截图脚本走 shot_gate 批量跑，算被跑），要么登进"
              " `tools/check_probe_registry.py` 的 EXEMPT 豁免名单（每行三格：探针名 / lane·来源 / 理由一句，"
              "形状缺格即红）；漏注册且漏豁免一律行首红字点名。豁免名单指着不在仓的探针（删探针没删名单行）也红。"
              "零、判据自检每次先在内存跑：C0 现网名单须全绿；E1 拼错豁免名 / E2 删一格豁免 / E3 覆盖名单缺一支，"
              "三格反向变异各须点出那一支红。豁免名单全表与逐条理由见脚本头注；"
              "（qa_rest_days_probe 一支已由 wave27 k3 登进头段 REGISTRY lane 档，8170079——不在豁免名单。）",
     "green": "零节 C0 + E1–E3 全 `✓` → 一节 5 条 `✓`（末条 `✓ 漏注册且漏豁免 0 支（全绿）`）→ 二节名单形状 `✓` → `结果：全部通过`",
     "red": "`✗ C0 现网名单普查全绿（漏网 N 支）`（豁免名单与注册表对不上现网——先修名单不修自检）/"
            "`✗ EXEMPT 第 k 行…`（名单形状 / 来源格缺 lane·commit）/"
            "`✗ 豁免名单每行都指着在仓探针——[…] 已不在仓 / 名写错` / `✗ 探针漏册：tools/<X>_probe.gd——不在 REGISTRY / SHOT_PROBES，也未登豁免`（逐支点名）/"
            "`✗ En 反向格：…`（自检对不上 = 闸判不出这一形）；`结果：N 项问题`"},
]

# 接 shot_gate.gd 的截图脚本（lane m3 三支 + lane sg2 二十支 + 之后各 lane 新接的）。TAG / 张数 / 截图目录从脚本源码现读，不在此抄。
SHOT_PROBES = [
    ("tools/vision_stage_probe.gd", "m3"),
    ("tools/vision_letterbox_probe.gd", "m3"),
    ("tools/qa_p7_screenshots.gd", "m3"),
    ("tools/combat_vfx_probe.gd", "sg2"),
    ("tools/ship_vfx_probe.gd", "ship-vfx"),  # 出海船观感 + 命中手感（lane ship-vfx）
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
    {"id": "Main 拆出件拼回（一之零）", "parent": "check_symbols", "lane": "ms / cs8 / gd16 / cs13", "oneclick": True,
     "cmd": "python3 tools/check_symbols.py", "also": ["tools/main_stitch.py"],  # 拼回本体（lane auditfix6 抽出，verify_economy 共用）
     "marks": ["一之零、Main.gd 拆出件", "MAIN_NOT_SPLITS", "SPLIT_MARK", "却不是一行转发", "拼回只对源码字符串断言有效",
               "条都有效：文件在、Main 一行转发到它", "gen_main_splits.read_splits()", "gen_main_splits.check()",
               "同读 tools/main_splits.txt", "文件却不存在（删了拆出件没更新清单）"],
     "expect": "「一之零」每件 `✓ scripts/ui/<件>.gd：N 支转发拼回函数体` + `✓ 头注写「从 Main.gd 原样搬出」的 N 件与 MAIN_SPLITS 一一对上；"
               "Main 调拆出件处都是一行转发；非拆出件的一行委托 N 处都在 MAIN_NOT_SPLITS` + `✓ MAIN_NOT_SPLITS N 条都有效：文件在、Main 一行转发到它、"
               "目标函数在、注明与实际转发一致` + `✓ tools/main_splits.txt 与重算逐字节一致（N 件；…）` + "
               "`✓ godot_smoke.gd 与此同读 tools/main_splits.txt（_main_family_src → _main_splits，不自带清单）`。"
               "清单只有 `tools/main_splits.txt` 一份（lane cs13），两边都读它的第一列；"
               "**拼回只对源码字符串断言有效**：行号、`main.` 前缀、static / 实例语义不在此列（口径见 §三.1）",
     "fail": "`✗ … 转发到 <件> 的 fn，那边没有这支 static func` = 拆出件改名 / 删了没跟转发；`登记为 Main 拆出件，但 Main 里没有一行转发` = 登记了没接；"
             "`调了拆出件 … 却不是一行转发` = 转发带行尾注释 / 两行 / 折行签名，拼回不认；`一行转发到 <件>，它没登记进 MAIN_SPLITS` / "
             "`头注写「从 Main.gd 原样搬出」，却没登记` = 新拆一刀忘登记；`登记为拆出件，头注…没写` = 约定字样丢了；"
             "`tools/main_splits.txt 第 N 行与重算不一致` = 手改了清单，或台账 / 拆出件 / Main 转发改了没 `gen_main_splits.py --write`；"
             "`台账登记的拆出件 … 文件不存在` / `登记在 tools/main_splits.txt，文件却不存在` = 删了拆出件没更新台账和清单；"
             "`godot_smoke.gd 没改成读 tools/main_splits.txt` = smoke 又自带了一份清单 / 写死了路径；`MAIN_NOT_SPLITS 条目 <件> 文件不存在` / `Main 没 preload 它或没有一行转发到它` / "
             "`转发到 <件> 的 fn，那边没有这支 func（…指向不存在的目标）` / `注明「A → B」，Main 里实际一行转发是 …` / `同时登记在 MAIN_SPLITS 与 MAIN_NOT_SPLITS` "
             "= 放行清单过时（lane gd16），删条目或改注。都计入 check_symbols 问题、退 1"},
    {"id": "gen_main_splits --write", "parent": "check_symbols", "lane": "cs13", "oneclick": False,
     "file": "tools/gen_main_splits.py",
     "cmd": "python3 tools/gen_main_splits.py --write",
     "alt": "python3 tools/gen_main_splits.py",
     "marks": ['"--write"', "docs/Main拆解台账.md", "与重算逐字节一致，未改动", "已重写", "未验", "拆出 commit 自己记的 `-`：HEAD 就是它时照认", "已不是 HEAD", "格式硬校验"],
     "expect": "`✓ --write：tools/main_splits.txt 与重算逐字节一致，未改动`；有差异则 `↻ --write：已重写 tools/main_splits.txt（N 件；请连同提交）`，"
               "之后照常对账一遍、`结果：全部通过`。不带 `--write` 只对账不写盘（与 check_symbols「一之零」同一个 check()）。"
               "拆出件 / lane ← 台账节标题，拆出函数 ← Main 一行转发，commit / 原 Main 行范围 ← git（拆出 commit 父版 Main.gd），"
               "台账写了逐支行段的逐支对账；台账函数表列了的函数现 Main 须仍一行转发到本件（lane cs18），反过来那节有函数表的、现 Main 一行转发到本件的每支都须列在表里（lane cs22，有表就须列全）。"
               "另加台账格式硬校验（lane cs23 / docs/Main拆解台账.md 头注；台账写坏时原先这些形状被正则静默漏掉、重算跟着少一件 / 少一支、--write 照写、gen 自己绿）："
               "① 标题以「第…刀」开头却不合节标题正则的行；②「已拆（前N刀…）」那段里的 `X.gd` 没按「`X.gd`（lane，…」写，或认出来的不是 N 件、N 认不出；③ 刀序（从「前N刀」的下一刀起逐刀 +1，现为第四刀；那段不在则从第一刀起——lane cs26 起起点由台账推、不再写死 3；重号 / 跳号 / 认不出的刀号）；"
               "④ 像函数表行（竖线起头、反引号里 `名字(`）却不合写法、行段写成 ASCII 连字符 / 写错、同一节同一支列两次；⑤ 拆刀节没有函数表（lane cs25 起无例外：第四、第五刀补了表、删了 `NO_TABLE_OK` 放行）。有任一条时 `--write` 也判红、不写盘；①–⑤ 的变异对照见 ledger_refs_mutants（lane cs25）。"
               "浅克隆取不到拆出 commit 父版时那一行报 `⚠ … 未验`、沿用清单原值，不判红。"
               "commit 列的 `-`：只在 HEAD 就是拆出 commit 时照认（lane auditfix1），HEAD 往前走了对账即红、`--write` 补成哈希",
     "fail": "`✗ --write：有问题，tools/main_splits.txt 未改动` + 各条 `✗`（台账登记的拆出件不存在、拆出件有 static func 没有 Main 转发、"
             "拆前 Main.gd 里找不到转发的 Main 函数、台账逐支行段与重算不符、台账格式硬校验 ①–⑤（`… 标题以「第…刀」开头，却不合拆刀节标题写法 …本脚本认不出这一刀、会整件漏掉` / `…「已拆（前三刀…）」那段的 X.gd 没按 …写` / `… 刀序不对：上一刀之后应是第 N 刀` / `… 的刀号认不出` / `…像函数表行、却不合…写法` / `… 的行段写法不认` / `… 函数表把 X 列了两次` / `…那节没有函数表`，lane cs23）、`<lane> 族 <件>：台账函数表列了 fn（期望拆前 Main.gd a–b 行）…没有一行转发到本件` = 挪回 Main / 改名 / 转去别件没改台账，lane cs18；`<lane> 族 <件>：现 Main.gd 的 fn 一行转发到本件 X，台账那节函数表却没列它` = 新搬一支进本件没补台账表，lane cs22）→ 退 1。**会改写 `tools/main_splits.txt`**，"
             "所以不进一键跑；新拆一刀的 lane 追加台账一节后跑它、连同提交。"
             "对账（check_symbols「一之零」）的 `✗ <件>：拆出 commit X 已不是 HEAD（其后又有 N 个提交），清单 commit 列还记 -…` = "
             "拆分那笔之后没补哈希（lane auditfix1 前这一格放行到下一刀才补）：跑 `--write`、另提一笔，与拆分同一次落地"},
    {"id": "按函数名取函数体（十三）", "parent": "check_symbols", "lane": "gd16 / cs9 / cs12 / cs11 / cs17 / gd23", "oneclick": True,
     "cmd": "python3 tools/check_symbols.py",
     "marks": ["十三、按函数名取函数体", "class _Bodies(dict)", "_body_ask(name, m is not None, body=m and m.group(0), src=src)", "处按名取用都取到函数体",
               "_miss_why(", "forward_ok=True", "src=self.src", "if bodies.forward(name):",
               "from func_body import", "NAMED_FUNCS = {", "支函数都还在登记的文件里", "def _nf_branch_sites(src):",
               "_nf_tag_bad = _nf_tag_check()", "逐行标明、与登记一致",
               '_body_ask(token + "]", at >= 0)', "处按名取用都取到场景节点块", "def body(name):"],
     "expect": "「十三、按函数名取函数体」`✓ _func_body / func_bodies().get / _locate_func 的 N 处按名取用都取到函数体，_node_block 的 M 处按名取用都取到场景节点块`"
               "（N / M = 本脚本「行号 + 名字」去重后的取用处；_node_block 按 `[node name=\"X\"` 取场景节点块，lane cs12 纳入同一本账）。"
               "各节按名取体一律先定位再取体（lane cs9：原先手切的 find / split / 无锚正则 / _static_body 都收进 `_locate_func`，只认行首 `[static ]func 名字(`）；"
               "取到的只是一行转发（`func X(…):\\n\\t_K.x(self, …)` / 原样传形参给别的函数 / 零实参调同文件另一支，判据 `func_body.forward_of(body, src)`）同样记成取不到（lane cs17 / gd23，三片口径对账见 §三 1）；"
               "本来就读转发那一行的（顺调用链展开、钉「Main 只许一行转发」）写 `.get(name, …, forward_ok=True)`。"
               "只探有没有这支函数、不想判红的写 `name in func_bodies(src)`（不记账）；本身要跑在变异源码上的契约（`_guild_remap_contract`）一律 `in` 探、缺了记成契约错误「缺 X」、只剩一行转发记成「X 只剩一行转发」，不走 .get 记账（lane cs12 / gd23）。"
               "+ `✓ 断言点名的 N 支函数都还在登记的文件里（M 个文件，按 (文件, 名字) 认；反向断言 / find 锚 / 存在性探查 / 分支形；NAMED_FUNCS 与本脚本自扫一致；"
               "同名多处定义的 K 支（…）逐行标明、与登记一致）`（lane cs9 / cs11 / auditfix5）",
     "fail": "`✗ check_symbols.py:<行> 取函数体 <fn> 取不到（改名 / 删了 / 搬走没拼回），这处断言在空转` = 被读的函数改了名 / 删了 / "
             "搬走没拼回，或断言里函数名写错；`✗ check_symbols.py:<行> 取函数体 <fn> 只取到一行转发（→ <目标>），真身不在这份源码里（拆走没拼回 / 该改读拆出件），这处断言在空转` = "
             "读的那份源码里这支只剩一行转发（Main 拆走一刀、转发到没登记 / 没 preload 的件，或直读 Main.gd / 别的文件时切到转发），改读真身所在的文件（lane cs17）；"
             "`✗ check_symbols.py:<行> 取函数体 <fn> 只取到一行转发（→ <g>），真身是同一份源码里的 <g>（改名后留了别名 / 该改取 <g>），这处断言在空转` = 同文件改名后原名只剩零实参 / 原样传形参的别名，改取 <g>（lane gd23）；"
             "`✗ check_symbols.py:<行> 取场景节点块 [node name=\"X\"] 取不到（节点改名 / 删了 / 挪进子场景）` = 同上、对象是 .tscn 节点（lane cs12）；改前这里给 `\"\"`（手切的还会落到整份文件 / 最后一个字 / 前缀同名的别的函数），"
             "反向断言（`\"X\" not in body`）照样绿；`✗ 断言点名的函数 X 在 <文件> 已无定义，别处还有同名（…）` / `…（scripts/ 下也没有…）` = "
             "反向断言 / find 锚 / 存在性探查点到的函数在登记的文件里改了名、删了或挪到别的文件（lane cs11：同名函数在别的文件还在也红），"
             "断言与 NAMED_FUNCS 跟着改；`✗ NAMED_FUNCS 登记的文件 <文件> 不存在` = 登记路径写错 / 文件挪了目录；"
             "`✗ check_symbols.py:<行> 的断言点到函数 X，没登记进 NAMED_FUNCS` = 新写这类断言没登记；"
             "`✗ check_symbols.py:<行…> 的断言点到同名多处定义的函数 X（…），字面量看不出指哪一支…` = X 在 scripts/ 下 ≥ 2 个文件有定义（Main 拆出件并回 Main），"
             "这几行没在行尾标 `# NF: 接收者.X`；`✗ …的断言标明指 <文件> 的 X，NAMED_FUNCS 却登在 <文件>…` = 错登到同名的另一支（登记跟断言读的那支走）；"
             "`✗ …的 NF 标注 … 认不出文件` / `…这一行自扫没点到 X` = 标注写错 / 标错行（lane auditfix5）。计入 check_symbols 问题、退 1"},
    {"id": "check_symbols_mutants 落点预检（十四）", "parent": "check_symbols", "lane": "cs27", "oneclick": True,
     "cmd": "python3 tools/check_symbols.py", "also": ["tools/check_symbols_mutants.py"],  # 判词由 check_symbols_mutants.landing() 印
     "marks": ["十四、check_symbols_mutants 落点预检", "import check_symbols_mutants as _csm", "_csm.landing(ROOT)",
               "def landing(root=ROOT):", "class Mem:", 'LANDING_OFF = "--no-mutants-landing"', "SYM), LANDING_OFF]", "变异在当前源码上都落得上"],
     "expect": "「十四、」`✓ check_symbols_mutants 落点预检：K0–K10 11 格判对；31 格变异在当前源码上都落得上（插行靶子 scripts/Main.gd _setup_shipyard → …）；"
               "期望 ✗ 字样 / rc / 空转对照归全量（lane 档，docs/GATES.md §三.23）`。check_symbols_mutants（lane 档，全量要 git worktree、约一分钟）的 CASES 逐格"
               "在当前工作树上内存里施一遍（`Mem` 叠层：读主树工作树、写不落盘，不建 worktree、不跑 check_symbols，约 0.5 s），只判变异 / 旧口径补丁落不落得上"
               "（替换处数、插行靶子顺一行转发找真身）+「零、」K0–K10。起因 auditfix7 W8：aec1ea6 入库 11 分钟后 main10 拆走 `_setup_shipyard`，全量红满 60 分钟、"
               "7 笔没人跑（lane cs27，§五.5 例三）。关断开关 `--no-mutants-landing` 只给 check_symbols_mutants 在变异过的 worktree 里用（印一行 `⚠ 落点预检未跑`），一键跑命令不许带",
     "fail": "`✗ check_symbols_mutants 落点预检 · <编号> <说明>：变异没落上——<文件> 里 <模式> 替换了 k 处，应 n 处` / `…func X( 有 k 处，应 1 处` / "
             "`…是一行转发到 …，… 不是 preload 常量` = 变异的靶子被挪了 / 改了（拆 Main、改节点名、改船屋断言），全量跑下去这一格就是 `变异没落上`；"
             "`✗ check_symbols_mutants 落点预检 · K<n> …` = locate_body / forward_of 判据变了。修法：照新源码改 tools/check_symbols_mutants.py 的 CASES，"
             "再跑一次全量 `python3 tools/check_symbols_mutants.py`。计入 check_symbols 问题、退 1"},
    {"id": "ledger_refs_mutants 落点预检（零之二）", "parent": "check_decision_refs", "lane": "w19-g8", "oneclick": True,
     "cmd": "python3 tools/check_decision_refs.py", "also": ["tools/ledger_refs_mutants.py"],  # 判词由 ledger_refs_mutants.landing() 印
     "marks": ["零之二、ledger_refs_mutants 落点预检", "import ledger_refs_mutants as lrm", "lrm.landing(ROOT)",
               'LANDING_OFF = "--no-ledger-landing"', "landing_bad = ledger_landing(o.no_landing)",
               "def landing(root=ROOT):", "class Mem:", "args + [LANDING_OFF]", "DRILL = [", "变异在当前台账 / 两支脚本 / 清单上都落得上"],
     "expect": "转发穿透自检之后一行 `✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异在当前台账 / 两支脚本 / 清单上都落得上（前三刀段；第十一刀 → scripts/ui/TitlePage.gd 最后一支 …；"
               "第四刀 → …；第五刀 → …；清单 Main.gd 引用 N 处）；rc / 期望 ✗ 字样 / 写盘 / 确定性 / 空转对照归全量（lane 档，docs/GATES.md §三.26）`。"
               "ledger_refs_mutants（lane 档，全量要 git worktree、约 40 s）的 GEN_CASES / DET_CASES 逐格在当前工作树上内存里施一遍（`Mem` 叠层：读主树工作树、写不落盘，"
               "不建 worktree、不跑 gen / check_decision_refs，约 0.1 s），Facts 现算一遍，只判变异 / 旧口径补丁落不落得上；另跑「零、」Z1–Z5：把真树上的靶子按合法 / 等价写法挪一下"
               "（第十一刀标题 ###、那节行段写「—」、gen 改名 `_check_first_knives`、`pairs = sorted(pairs, …)`、清单 Main.gd 引用只剩 7 处），预检须点名对应格没落上。"
               "起因同 check_symbols_mutants 十四节（auditfix7 W8，lane cs27）：lane 档的变异对照靶子被别的片挪了，全量红着没人跑。--fix 时不跑。"
               "关断开关 `--no-ledger-landing` 只给 ledger_refs_mutants 二节在变异过的 worktree 里用（印一行 `⚠ ledger_refs_mutants 落点预检未跑`，不计入 ⚠ / ✗ 条数），一键跑命令不许带",
     "fail": "`✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——<文件> 里「## 第十一刀（」起头的节标题有 k 处，应 1 处` / `…那节找不到带行段的函数表行` / "
             "`…替换了 k 处，应 n 处` / `…引用只有 k 处，应 ≥8` = 变异的靶子被挪了 / 换了写法（拆 Main 改台账、改 gen / 本脚本的调用或排序写法、清单引用改指），全量跑下去这一格就是 `变异没落上`；"
             "`✗ … · Z<n> …预检空转` / `…造漂移没落上` = 预检自己的判法被放宽 / 靶子已换形状。修法：照新形状改 tools/ledger_refs_mutants.py 的 M / GEN_CASES / DET_CASES（或 DRILL），"
             "再跑一次全量 `python3 tools/ledger_refs_mutants.py`。计入 check_decision_refs 问题、退 1"},
    {"id": "按函数名取函数体（十一）", "parent": "verify_economy", "lane": "cs14 / cs17 / gd23", "oneclick": True,
     "cmd": "python3 tools/verify_economy.py",
     "marks": ["十一、按函数名取函数体", "from func_body import", "_body_ask(name, m is not None, body=m and m.group(0)", "处按名取用都取到函数体",
               "_miss_why(", "forward_ok=True", "src=src)"],
     "expect": "「十一、按函数名取函数体」`✓ _locate_func / _gd_body / _gd_fn 的 N 处按名取用都取到函数体`（N = 本脚本「行号 + 函数名」去重后的取用处）。"
               "账本与 `_locate_func` 在 `tools/func_body.py`，与 check_symbols 十三节同一份（lane cs14）；原先手切的 "
               "`src.split(\"func X\", 1)[1].split(\"\\nfunc \", 1)[0]`（有 / 无 `in` 守卫）与 `guild_body` 一律改走 `_locate_func`，"
               "`_gd_body` / `_gd_fn` 切法不变、取完记同一本账。取到的只是一行转发同样记成取不到（lane cs17 / gd23，判据 `func_body.forward_of(body, src)`，与 check_symbols 同一口径）；"
               "`_on_npc_bribe` 那处本来就读 Main 的转发再顺藤去 NpcPage 取真身，写 `forward_ok=True`",
     "fail": "`✗ verify_economy.py:<行> 取函数体 <fn> 取不到（改名 / 删了 / 搬走没拼回），这处断言在空转` = 被读的函数改了名 / 删了 / 搬走（Main 拆出件没跟着改读哪份），"
             "或断言里函数名写错；改前守卫版给 `\"\"`、`or 整份文件` 兜底，无守卫 split 按前缀认名（`X` 改成 `X_v2` 照样切到它），反向断言照样绿。"
             "`✗ verify_economy.py:<行> 取函数体 <fn> 只取到一行转发（→ <目标>），…这处断言在空转` = 直读的 Main.gd / 别的文件里这支已拆走、只剩一行转发，"
             "改读拆出件（去 `main.` 前缀）或真身所在文件（lane cs17；如 main9 把 `_setup_residence` 改读 ResidencePage.setup_residence）；"
             "`…只取到一行转发（→ <g>），真身是同一份源码里的 <g>…` = 同文件别名，改取 <g>（lane gd23）。"
             "计入 verify_economy 未通过项、退 1"},
    {"id": "scenes.json 结构自证", "parent": "verify_story_data", "lane": "seq3", "oneclick": True,
     "cmd": "python3 tools/verify_story_data.py",
     "marks": ["def scene_structure_problems", "SCENE_ARCHIVE", "SCENE_ARCHIVE_MAX", "_SV_MUTANTS", "scenes.json 结构门禁自证",
               "def scene_shapes_from_manifest", "_SHAPE_MUTANTS", "scenes 形状单一来源自证"],
     "expect": "末尾统计行 `scenes 104（结构：入口可达 N · 归档 M · deprecated K · 自证 24 类 + 形状单一来源 6 类，形状读 tools/data_family.json）`；结构没问题时本节零输出。"
               "形状（各形必填 / 可选键、列表子形、按字段名的类型）不在本脚本另写，读 `tools/data_family.json` 里 data/scenes.json 那条的 kinds / shapes，"
               "与 check_data_family 同读一份（lane seq6）；另 6 类形状自证改清单副本（删可选键 / 改必填 / 删子形键 / 同名字段类型不一 / 类型写法坏 / 缺 scenes 那条），本门禁须跟着报。"
               "每次跑先在整份 scenes.json 上判结构（形状必填 / 形状外键 / 类型与在册取值 / 引用存在 / 从真机入口走不到的非 deprecated 幕须在 `SCENE_ARCHIVE`），"
               "再拿 24 类反向变异副本（删必填、next / 调查项 id / start_scene / chapters / 港卡 / 旗标 / 货 / 发现悬空、跳 deprecated、类型错、bool 冒充 int、"
               "键拼错、枚举外、id 重复、新孤儿、归档场接回、归档名单悬空）逐类喂同一个 `scene_structure_problems`，每类须报出指定字样；"
               "每格的锚不写死幕 id，按清单形状从现数据里挑头一条合条件的幕 / 选项 / 章（如主锚 = 兜底形、非 deprecated、不在归档、从入口可达、choices[0] 指向非 deprecated 幕），"
               "幕改名自己跟上，悬空名现造不撞现有 id（lane w19-g7）；`--anchors` 逐格打印本次挑到的锚与须报字样",
     "fail": "`FAIL: scenes.json <幕>… 缺必填字段 / 有形状外的字段 / 类型应为 / 不在册 / 悬空 / 没人写 / 是孤儿 / 却已接回入口` = 数据结构坏了（修数据，或新字段 / 新形状先登记进 tools/data_family.json 的 scenes kinds / shapes）；"
             "`FAIL: tools/data_family.json …读不了 / 没有 data/scenes.json 那条 / 类型写法 … 认不出 / 同名字段 … 各形类型不一` 与 `FAIL: scenes 形状单一来源自证：「X」…` = 形状清单坏了或本门禁又不读它了（lane seq6）；"
             "`FAIL: SCENE_ARCHIVE 只许减不许增` = 有人把新孤儿塞进归档名单（接入口，别登记）；"
             "`FAIL: scenes.json 结构门禁自证：「X」后没报出…` = 某类检查失明；`…「X」锚落不上：…找不到「<挑选条件>」…` = 数据里已没有这种形状的条目（照新数据改 _SV_MUTANTS 这一格的挑选条件，不许删格）；"
             "`…锚挑到了、变异却套不上` = 挑选条件与变异手法不一致（lane w19-g7）。都计入 verify_story_data 失败、退 1"},
    {"id": "一键跑把关判据自检（三之一）", "parent": "gates_md", "lane": "w20-b3", "oneclick": False,
     "cmd": "python3 tools/gates_md.py",
     "marks": ["off_limits()", "def oneclick_sweep", "def sweep_selfcheck", "LANDING_OFF", "三之一、一键跑把关判据自检",
               "出现禁带字样", "缺席必跑档", "道数不符", "README 道数"],
     "expect": "「三之一、一键跑把关判据自检」4 条 `✓`（两枚关断开关字样从两支变异脚本 import 现读得到；4 枚禁带字样逐个注入内存命令段都判红；"
               "删一条 / 多一条必跑档分别红「缺席」「道数不符」）。起因 g8 W1：一键跑段 / todo 验证段被塞 `--no-ledger-landing` 后 check_symbols / "
               "check_decision_refs 全 rc=0，只有逐条字符串比对红——准入判据 ① 一键跑两处命令段不许带 LANDING_OFF 关断开关 / `--help` / `--dry-run`"
               "（开关样值从 check_symbols_mutants / ledger_refs_mutants 的 LANDING_OFF 常量现读，不在本表另抄）；② 必跑档条目不许在一键跑里缺席"
               "（红因点名是谁）；③ 命令条数与必跑档条数必须相符；④ README「一次改动闭环 = 下面 N 道」的道数与注册表一键跑条数对账。与逐条比对互补、"
               "随 gates_md 每次跑（lane 档，与逐条比对同寿命）",
     "fail": "`✗ §三 一键跑 / .claude/todo.md 验证段出现禁带字样 --…：…只许 … 在变异 worktree 里带` = 一键跑被塞了关断开关，落点预检被关掉、"
             "其余门禁照样 0（g8 W1 误绿点）；`✗ …缺席必跑档 N 条（…）` = 必跑档在一键跑里漏跑；`✗ …命令 N 条，必跑档 M 条——道数不符` = "
             "多出来的行没人认 / 必跑漏跑；`✗ README 道数（…）与注册表一键跑条数（…）不符` = README「N 道」写漂移了；"
             "`✗ 两枚关断开关字样…import 现读得到（LANDING_OFF 常量改名 / 挪走了）` = 开关常量改名，本判据靶子要跟"},
    {"id": "compile 清单自检（inventory）", "parent": "compile", "lane": "ea4", "oneclick": True,
     "cmd": "godot --headless --path . -s res://tools/godot_compile_check.gd",
     "marks": ["inventory SCRIPTS == tracked *.gd", "ls-files", "INVENTORY_EXEMPT", "unlisted", "exempt-stale"],
     "expect": "`COMPILE_CHECK OK   inventory SCRIPTS == tracked *.gd under scripts/tools (exempt N)`",
     "fail": "`COMPILE_CHECK FAIL inventory <原因> …`（原因 `unlisted` / `listed-missing` / `dup` / `exempt-stale` / `exempt-but-listed`） = `git ls-files` 里已跟踪的 "
             "`.gd` 没进 `SCRIPTS`（或 `INVENTORY_EXEMPT` 没写理由）、清单路径不存在 / 重复 / 豁免失效，整体计 bad+1；"
             "`COMPILE_CHECK NOTE inventory git ls-files unavailable` = 没 git，退回扫盘（warn，不判红）"},
]

# CI 建议步骤（lane gd4）：docs/GATES.md §四 由它生成，**只是建议，不进 repo 的 CI 配置**。
# 先跑一键跑二十条（导入步骤 tier=step + 必跑十九道 tier=must 的 cmd），再跑下面这些 CI 专属步骤；每步退出码非 0 即红。
CI_STEPS = [
    {"id": "builtin_api 漂移", "lane": "cs3 / gd4", "needs": "godot（与清单头部同版本）",
     "cmd": "python3 tools/check_symbols.py --regen && git diff --exit-code tools/builtin_api.txt",
     "expect": "`✓ --regen：…逐字节一致，未改动` + check_symbols `结果：全部通过`，`git diff` 无输出、退 0",
     "fail": "`git diff` 打出 `tools/builtin_api.txt` 的差异、退 1 = 提交的清单与本机 Godot 的 ClassDB 导出不一致"
             "（升级了 Godot / 改了 `gen_builtin_list.gd` 的 CLASSES 却没连同提交重导结果）；`--regen` 本身失败则 check_symbols 先退 1"},
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
    for g in REGISTRY + CHECK:  # CHECK（lane w27-k4）：普查类门禁追加节，同 REGISTRY 形状、同走一键 / 批量块
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
                # lane w42-k2（拍板 E-15 走 A）：cmd 单源化——json 格不再手写裸原生命令，
                # 写 `--native <id>` 由本脚本按注册表 args 反查重造（--quiet 与 -- --json 自动补，
                # 与 godot <args> -- --json 等价；display 条目自动补 --display）
                g["json"] = "python3 tools/gate_json.py --native " + g["id"] + (" --display" if g.get("display") else "")
            else:
                g["json"] = ("" if _legacy(g) else disp) + "python3 tools/gate_json.py --godot " + g["id"]
        else:
            g["cmd"] = SHOT_ENV_PREFIX + "DISPLAY=:2 godot --path . -s res://tools/<探针>.gd"
            g["json"] = SHOT_ENV_PREFIX + ("DISPLAY=:2 python3 tools/gate_json.py --native <探针> --display" if shots_native
                                           else "DISPLAY=:2 python3 tools/gate_json.py --godot <探针>")
        gates.append(g)
    shots = [_shot_probe(p, lane) for p, lane in SHOT_PROBES]
    for s in shots:
        s["cmd"] = "DISPLAY=:2 godot " + " ".join(s["args"])
        s["json"] = ("DISPLAY=:2 python3 tools/gate_json.py --native " + s["id"] + " --display" if shots_native  # lane w42-k2：同 cmd 单源化
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
        c["file"] = c.get("file") or (parent.get("file") if parent else None)  # 附属自检的开关不在所属门禁脚本里的，自报 file（lane cs13）
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
