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
     "judge": "autoload 起得来、章节/旗标/结局按数据走、headless 零延迟旁路",
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
     "judge": "行会入行 / 行情抄本条数 / 贡院赴试 / 誊录：扣费门槛、商誉 3 / 5 条、每章一次、跨月结算时序",
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
     "judge": "（lane sv / fx6）老档沿迁移链逐级升到本版（`SaveLoad.SAVE_SCHEMA`，现为 3：v1→v2→v3）：v1 老档读入补字段、回写本版、原件留 .v1；"
              "v2 档（无 `state.met_ids`）按雇用记录 / 在船职事 / 守城见林华回填人物志「已识」、推不出留空、回写本版、原件留 .v2；未来档明确拒读、不退副抄、文件不动",
     "green": "`SAVE_MIGRATE_PROBE PASS`", "red": "`✗` 行；`SAVE_MIGRATE_PROBE FAIL fails=k`；输出含 `SCRIPT ERROR` 即算失败"},
    {"id": "gates_md", "tier": "lane", "when": "动门禁清单 / docs/GATES.md", "kind": "py", "file": "tools/gates_md.py",
     "judge": "（lane gd3 / gd4 / gd5；gd5 加 §二 批量巡检块、`.claude/todo.md` 验证段）本注册表 vs docs/GATES.md §一、§二批量巡检、§四三个生成块逐字一致；注册的脚本都在；接 shot_gate 收尾截图的脚本全部入册、接 shot_gate 的脚本都挂压帧 `ShotGate.frame_pressure`（lane gd18）；附属自检的开关还在源码里；§三 小节编号对得上；§三 与 todo.md 验证段的一键跑命令与必跑档逐条同序",
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
              "`--since` / 改号自证的新旧配对也按新版引用的清单顺序逐对比——原先配对取 `ko.keys() & kn.keys()`（集合，遍历顺序随 PYTHONHASHSEED 变），有 2 处以上 ⚠ / MISMATCH 时同基连跑每次行序不同、「逐字节同」比对偶发假 DIFF（lane cs18 待议 4）",
     "green": "`✓ 转发穿透自检 10/10（…）` + `✓ ledger_refs_mutants 落点预检：Z1–Z5 5 格判对；40 + 5 格变异…都落得上（…）；…`（lane w19-g8，SUBCHECKS）+ `锚 X：引用 N 处（…）…；NOFILE/OOR 0，DRIFT 0（…），待核标记 0` + `改号自证 […]…MISMATCH 0…` + `结果：全部通过`（`⚠ 改指未验` 不判红）。同一基连跑 5 次 stdout 逐字节同（lane cs23 实测：六个历史基 × 默认 / `--show`、5 个 `--since` 旧版与号写歪的脏树各 5 次同 md5）；lane cs25 起由 ledger_refs_mutants 二节固化（5 个固定种子、去掉排序须判不确定）",
     "red": "`✗ NOFILE` / `✗ OOR` / `✗ DRIFT L行 文件:行：…可跟号 → :新号（凭什么）` 或 `…跟不上，要人工：…` / `✗ 待核 L行` / `✗ MISMATCH L行 …旧锚那段原文在 X 里还在 文件:行——行号改歪了？`；"
            "`…可跟号 → 文件:新号（穿透一行转发 …）` / `…跟不上，要人工：跟到一行转发：…` / `✗ 转发穿透自检 S… 期望 … 实得 …`（脚本自身坏了）；"
            "`✗ ledger_refs_mutants 落点预检 · <编号>：变异没落上——…`（变异靶子漂了，lane w19-g8，见 SUBCHECKS）；"
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
    {"id": "check_data_family", "tier": "lane", "when": "动 data/ 下同族文件（scenes.json / ports.json）的条目 / 字段 / 引用，新增 data/*.json，或动 tools/data_family.json",
     "kind": "py", "file": "tools/check_data_family.py",
     "judge": "（lane seq4 / seq6）普查 data/*.json：F1 带唯一字符串 id 的条目表 + F2 字段指回同表 id（过半）+ F3 scripts/ scenes/ 的代码读它（seq6：# 注释不算、cutscenes.json 不算 scenes.json）的候选，须登在清单 families（同族）或 not_family（写明图为何无入口）；"
              "候补 watch（seq6，port_beats.json 按 entry 成图）按登记的 key 判 F1 / F2 须仍成立，F3 一成立即红；"
              "对每个同族文件跑四项：一、字段齐备 / 类型（按形查必填、类型、未登记字段，嵌套列表再查一层；scenes 的形也是 verify_story_data 的形状表，单一来源）；二、引用 id 存在（refs 每一路落在本表 / 别的数据文件 / GDScript 常量的并集）；"
              "二之一、无向图的单向登记须全在 one_way_ok 基线（seq6，只减不增）；三、普查出的自引用路径（过半与部分命中）都登了 refs 或 not_edges；四、从 roots 沿 edge 走不到的条目 = 孤儿（形上 orphan_ok 与 known_orphans 基线放过，基线登了却已可达 / 已删即红）；"
              "每次先跑「零、变异自检」32 格（GATES §五.3；内存里改：同族删必填 / 删边字段 / 改类型 / 悬空 / 拼错字段 / 孤儿 / 新添指回本表的字段 / 基线失效 / 入口与常量改名 / 部分命中漏登 / 单向登记新添与补齐 / 漏登 / 只剩注释读它 / 候补接回运行时须红且只红在该文件，非族 goods / characters / crew 改了须与基线一致；"
              "seq6 起锚按形状挑（兜底形、可达、边字段非空的第一条），常量 / 入口名读清单，id 改名自己跟上，挑不到即红「锚落不上」；`--mutants` 逐格打印）；"
              "scenes 的孤儿基线与 lane seq3 共用 verify_story_data.SCENE_ARCHIVE",
     "green": "`✓ 32 格全对：…` + `✓ 候补 data/port_beats.json：…` + `== <文件>` 下逐项 `✓ 一、…` 至 `✓ 四、…`（四：`可达 a / n；不可达 k = 形放过 x + 已登记基线 y`）+ `结果：全部通过`",
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
    {"id": "compile 清单自检（inventory）", "parent": "compile", "lane": "ea4", "oneclick": True,
     "cmd": "godot --headless --path . -s res://tools/godot_compile_check.gd",
     "marks": ["inventory SCRIPTS == tracked *.gd", "ls-files", "INVENTORY_EXEMPT", "unlisted", "exempt-stale"],
     "expect": "`COMPILE_CHECK OK   inventory SCRIPTS == tracked *.gd under scripts/tools (exempt N)`",
     "fail": "`COMPILE_CHECK FAIL inventory <原因> …`（原因 `unlisted` / `listed-missing` / `dup` / `exempt-stale` / `exempt-but-listed`） = `git ls-files` 里已跟踪的 "
             "`.gd` 没进 `SCRIPTS`（或 `INVENTORY_EXEMPT` 没写理由）、清单路径不存在 / 重复 / 豁免失效，整体计 bad+1；"
             "`COMPILE_CHECK NOTE inventory git ls-files unavailable` = 没 git，退回扫盘（warn，不判红）"},
]

# CI 建议步骤（lane gd4）：docs/GATES.md §四 由它生成，**只是建议，不进 repo 的 CI 配置**。
# 先跑一键跑十六条（导入步骤 tier=step + 必跑十五道 tier=must 的 cmd），再跑下面这些 CI 专属步骤；每步退出码非 0 即红。
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
