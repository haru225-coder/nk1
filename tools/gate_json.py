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
  3. 门禁清单：`python3 tools/gate_json.py --list` 输出注册表 JSON（REGISTRY + SHOT_PROBES）；
     docs/GATES.md §一由它生成，`python3 tools/gates_md.py` 校验、`--write` 重生成。

输出（stdout 只有这一段 JSON）：
  {"gate", "ok", "exit_code", "summary", "checks": [{"name", "ok", "detail"}...],
   "counts": {"total", "pass", "fail", "warn", "engine_errors", "script_errors"}, "cmd", ["errors"], ["tail"]}
  · ok == (exit_code == 0)，与人读模式的退出码同一口径；checks 只是明细，不另立判据。
  · warn 条目（⚠ / COMPILE_CHECK NOTE）ok=true、带 "level": "warn"，不计入 pass/fail/total。
  · engine_errors：Godot 引擎打的 ERROR 类行数；script_errors 是其中 SCRIPT ERROR 行数。只报数，不改判定
    （patrol 的 Vulkan 回落、save_robust_probe 故意喂坏档都会打 ERROR:，属预期）。
  · 红了却没解析到失败行（脚本中途崩、提前 exit）时补一条 name="exit_code" 的失败条目，并附 tail。
"""
import json, os, re, subprocess, sys, tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
REC_ENV = "NK1_GATE_JSON_REC"

# ── 门禁注册表：docs/GATES.md §一 由它生成（tools/gates_md.py --write），文档与它不一致即 FAIL（tools/gates_md.py）──
# tier：must = 每轮必跑；lane = 按 lane 内容加跑（when 写何时）；no = 不算门禁（why 写原因）。
# kind：py = python3 tools/<file>；godot = godot <args>；shots = 截图门禁一行（明细见 SHOT_PROBES）。
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
    {"id": "editor", "gate": "godot_editor", "tier": "must", "kind": "godot",
     "args": ["--headless", "--editor", "--path", ".", "--quit"],
     "judge": "工程能打开、资源导入缓存（`.godot/`、`*.import`）刷新",
     "green": "exit 0，只有进度条", "red": "exit 非 0（**注意：脚本语法错它照样 exit 0，见 §三.9**）"},
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
     "judge": "挂主场景走开局、三港、九设施、海图：1280×720 按钮不越界、焦点色、航向牌、终局港口页",
     "green": "`PATROL SHELL PASS`", "red": "`✗` 行；`PATROL SHELL FAIL` + 复述"},
    {"id": "截图门禁", "tier": "lane", "when": "动画面 / UI / 过场", "kind": "shots", "file": "tools/shot_gate.gd",
     "judge": "（lane m3 立、sg2 扩到全部截图脚本，新截图脚本一律接它）`tools/shot_gate.gd`：零截图 / 空视口 / 一色空图 / 张数不足一律红；契约模式须显式 `-- --contract`",
     "green": "`<TAG>_OK shots=n/n -> 目录`；契约模式 `<TAG>_CONTRACT_OK…`",
     "red": "`✗ …` + `<TAG>_FAIL k（shots=…）`；headless 下 `<TAG>_FAIL headless（…不是画面回归）`"},
    {"id": "save_robust_probe", "tier": "lane", "when": "动 SaveLoad / 存档", "kind": "godot", "file": "tools/save_robust_probe.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/save_robust_probe.gd"],
     "judge": "（lane h1h2 / rt）坏分区退 .bak、只剩 .bak 取标签、两份皆坏不抛错",
     "green": "`SAVE_ROBUST_PROBE PASS`（大量 `ERROR: 存档结构异常…` 是故意喂坏档，属预期）",
     "red": "`✗` 行 / 非零退出；输出含 `SCRIPT ERROR` 即算失败"},
    {"id": "check_sidecars", "tier": "lane", "when": "提交新 .gd / .gdshader / 素材，或挪删它们", "kind": "py",
     "file": "tools/check_sidecars.py",
     "judge": "（lane ag）只看 git 索引：已跟踪 .gd/.gdshader 须有已跟踪 `.uid`，可导入素材须有 `.import`；反向不许只提侧车",
     "green": "`结果：全部通过`", "red": "`FAIL: …` 行（缺侧车 / 孤儿侧车）；`结果：N 项失败`"},
    {"id": "save_migrate_probe", "tier": "lane", "when": "动存档结构 / save_schema", "kind": "godot",
     "file": "tools/save_migrate_probe.gd", "args": ["--headless", "--path", ".", "-s", "res://tools/save_migrate_probe.gd"],
     "judge": "（lane sv）v1 老档读入补字段、回写 v2、原件留 .v1；未来档明确拒读、不退副抄、文件不动",
     "green": "`SAVE_MIGRATE_PROBE PASS`", "red": "`✗` 行；`SAVE_MIGRATE_PROBE FAIL fails=k`；输出含 `SCRIPT ERROR` 即算失败"},
    {"id": "gates_md", "tier": "lane", "when": "动门禁清单 / docs/GATES.md", "kind": "py", "file": "tools/gates_md.py",
     "judge": "（lane gd3）本注册表 vs docs/GATES.md §一逐字一致；注册的脚本都在；接 shot_gate 的截图脚本全部入册；§三 小节编号对得上",
     "green": "`结果：全部通过`", "red": "`✗` 行（附首处差异）；`结果：N 项问题`；修法 `python3 tools/gates_md.py --write`"},
    {"id": "verify_narrative", "tier": "no", "kind": "py", "file": "tools/verify_narrative.py",
     "why": "P7 剧情闭环旧静态门禁，当前 main 上本来就红（开局链 monk / borrow_ceiling 等旧契约），长期红、未列入必跑；修契约还是挪 `tools/legacy/` 待 lane gd2 拍板"},
    {"id": "p7_smoke", "tier": "no", "kind": "godot", "file": "tools/p7_smoke.gd",
     "args": ["--headless", "--path", ".", "-s", "res://tools/p7_smoke.gd"],
     "why": "旧 P7 冒烟，`borrow_ceiling` 一带早已失配，干净 worktree 也红（lane l1 已记）；P7 行会 / 贡院由 p7（`p7_guild_exam_smoke.gd`）接管"},
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
    res = "res://" + path
    return {"id": os.path.splitext(os.path.basename(path))[0], "file": path, "lane": lane,
            "tag": tag.group(1) if tag else None, "shots": int(n.group(1)) if n else None,
            "out_dir": out.group(1) if out else None, "args": ["--path", ".", "-s", res], "display": True}


def registry():
    """`--list` 输出的清单：门禁（带人读 / --json 命令）+ 截图脚本明细。"""
    gates = []
    for g in REGISTRY:
        g = dict(g)
        g.setdefault("gate", g["id"])
        disp = "DISPLAY=:2 " if g.get("display") else ""
        if g["kind"] == "py":
            usage = [g["usage"]] if g.get("usage") else []
            g["cmd"] = " ".join(["python3", g["file"]] + usage)
            # 自带三行转接的写 `--json`，没接的（如 verify_narrative）由本脚本外包
            try:
                with open(os.path.join(ROOT, g["file"]), encoding="utf-8", errors="replace") as f:
                    hooked = "gate_json.maybe_json" in f.read()
            except OSError:  # 文件不在：照出清单，由 gates_md 判红
                hooked = False
            g["json"] = g["cmd"] + " --json" if hooked else " ".join(["python3 tools/gate_json.py", g["file"]] + usage)
        elif g["kind"] == "godot":
            g["cmd"] = disp + "godot " + " ".join(g["args"])
            g["json"] = disp + "python3 tools/gate_json.py --godot " + g["id"]
        else:
            g["cmd"] = "DISPLAY=:2 godot --path . -s res://tools/<探针>.gd"
            g["json"] = "DISPLAY=:2 python3 tools/gate_json.py --godot <探针>"
        gates.append(g)
    shots = [_shot_probe(p, lane) for p, lane in SHOT_PROBES]
    for s in shots:
        s["cmd"] = "DISPLAY=:2 godot " + " ".join(s["args"])
        s["json"] = "DISPLAY=:2 python3 tools/gate_json.py --godot " + s["id"]
    return {"gates": gates, "shot_probes": shots}


# `--godot <预设>`：注册表里的 Godot 门禁 + 截图脚本（带窗口的不加 --headless）
GODOT_PRESETS = {g["id"]: (g.get("gate", g["id"]), g["args"]) for g in REGISTRY if g["kind"] == "godot"}
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


def run_python_gate(path, args):
    path = os.path.abspath(path)
    fd, rec = tempfile.mkstemp(prefix="gate_json_", suffix=".jsonl")
    os.close(fd)
    env = dict(os.environ, **{REC_ENV: rec, "PYTHONIOENCODING": "utf-8"})
    cmd = [sys.executable, os.path.abspath(__file__), "--child", path] + list(args)
    p = subprocess.run(cmd, cwd=os.getcwd(), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    recorded = []
    try:
        with open(rec, encoding="utf-8") as f:
            recorded = [json.loads(l) for l in f if l.strip()]
    finally:
        os.unlink(rec)
    gate = os.path.splitext(os.path.basename(path))[0]
    shown = ["python3", os.path.relpath(path, ROOT)] + list(args)
    return build(gate, shown, p.returncode, out, recorded or None)


def run_command(gate, cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return build(gate, cmd, p.returncode, p.stdout.decode("utf-8", "replace"))


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
        doc = run_command(gate, [_godot_bin()] + gargs + user, cwd=ROOT)
        if "--headless" not in gargs and not os.environ.get("DISPLAY"):
            doc.setdefault("notes", []).append("未设 DISPLAY：带窗口的门禁（patrol / 截图探针）需 DISPLAY=:2")
        emit(doc)
        return doc["exit_code"]
    if argv[0] == "--":
        cmd = argv[1:]
        named = [a for a in cmd if a.endswith((".py", ".gd"))] or cmd[:1]
        doc = run_command(os.path.splitext(os.path.basename(named[0]))[0] if named else "", cmd)
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
