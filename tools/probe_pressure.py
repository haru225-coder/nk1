#!/usr/bin/env python3
"""截图 / 信号探针「压帧双档结论一致」门禁（lane gd25）：同一支探针在两档 NK1_PROBE_SLOW_MS 下各跑一遍，结论必须一样。

  python3 tools/probe_pressure.py                         # 全部有窗口探针 × 档 0 / 300；有不一致或跑不成退 1
  python3 tools/probe_pressure.py --only qa_title_probe,letterbox_signal_probe [--levels 0,60,300] [--jobs 2]
  python3 tools/probe_pressure.py --mutants               # 反向变异自证：固定帧数碰运气的两支变异须判不一致（约 5 分钟）
  python3 tools/probe_pressure.py --selftest              # 只跑「零、判据自检」（不起 Godot）
  python3 tools/probe_pressure.py --json                  # 机读（同 docs/GATES.md §二）

为什么：「靠多停几帧碰运气变绿」没有门禁。lane gd20 的 letterbox_signal 超上界时 4 行靠多停的 4 帧碰上 finished 变绿；
gd24 在 ShotGate 收尾补了进程内兜底（本进程有等待撞了墙钟上界而没判红 → 补红），但它只看 probe_clock 的账——
**等待根本不经 Clock（数固定帧数）的探针，它看不见**：数 36 帧在 30 fps 下正好落在墨幕停拍里、封顶慢帧下已整幕收场，
一档绿一档红，单跑哪一档都「有理」。本门禁不看探针内部怎么等，只比两档跑出来的结论。

探针集：tools/ 下 git 已跟踪的 .gd 里代码行调了 `ShotGate.frame_pressure(` 的（与 gates_md「接 shot_gate 的都挂压帧」同一口径，
即截图册 24 支 + 只借 shot_gate 挂压帧的定向探针 letterbox_signal / qa_yard_transition），新探针挂上压帧即自动入集。

档：默认 0（不压）与 300。两档必须一档不封顶、一档封顶：引擎每帧 delta 最多记 8 个物理步（8/60 ≈ 0.133 s），
慢过 7.5 fps（每帧 ≥ 134 ms）后每帧游戏时间恒定，150 与 300 两档相位落在同一帧（lane gd20「四」），只差墙钟——
数帧碰运气的探针在两档封顶的对照下照样一致。300 在已测各支上界之内（最紧 letterbox_copy ≈ 625 ms / 帧，probe_clock「三」）。
`--levels` 可加档（如 0,60,300），每一档都与第一档比。档 0 在满载机器上也可能跑到封顶区，所以每跑记墙钟秒数，人读输出与报表都带上。

结论：探针 `-- --json` 的那一行（tools/gate_report.gd）取 exit_code、error、SCRIPT ERROR 有无、逐条 checks（ok / warn / 名字）。
没接 --json 的（qa_yard_transition：不 preload gate_report、不走 ShotGate 收尾）在 TEXT_PROBES 登记人读判词正则（逐路行 + 末行），
不加 --quiet 跑、按判词造同形结论；没登记的判「跑不成」。入口：`extends SceneTree / MainLoop` 的用 `-s`，否则跑同名 .tscn。
名字里的读数（`ms=2921`、`15000 ms`、`3.5 s`、`16 帧`、`frames=`）掩成 `#`：墙钟本来就随档变，不算结论；计数（`caption=1`）不掩。
判：两档结论全同且都绿 = ✓；不同 = ✗「两档结论不同」（报支名 + 各档结论 + 只在某档出现的条目）；两档同红 = ✗「两档同红」
（探针自身红，红因归截图门禁 / 该探针，这里只不放它绿）；某档没 JSON 行 / 超时 = ✗「跑不成」。
每跑各给一个空的 XDG_DATA_HOME（user:// 存档 / 设置从零起），两档起点相同、并行跑也互不串档；截图落 <out>/L<档>/（NK1_SHOT_DIR）。

与 lane gd20 `tools/shot_consistency.gd` 的分工（不重复）：
  · shot_consistency 比**像素**：两个已截好的目录逐张 8×8 格比，抓「两档都绿、截的却不是同一个画面」（相位漂移、半透明层没演完）；
    不跑探针、不看 rc / checks，没有截图的信号探针（letterbox_signal / qa_yard_transition）它比不了；装饰钟 / 随机数（gd20 R1–R5）
    让原图 76/109 张不同，不冻钟进不了 CI。
  · 本门禁比**结论**：自己跑探针，比 rc / error / 逐条 checks，抓「一档绿一档红」「红的行不同」；截图只数张数与文件名、不看像素，
    两档都绿而画面不同它不报。
  · 交接：本门禁把两档截图留在 <out>/L0、<out>/L300，结尾印出对这两个目录跑 shot_consistency 的命令——要看像素时接着跑，这里不代跑。
"""
import json, os, re, shutil, signal, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

ENV_SLOW = "NK1_PROBE_SLOW_MS"
LEVELS = (0, 300)
RUN_TIMEOUT = 900  # 秒，每跑一支一档；gd20 实测最慢一支压帧 300 约 90 s
DEFAULT_OUT = os.path.join(tempfile.gettempdir(), "probe_pressure")
USES = re.compile(r'preload\(\s*"res://tools/shot_gate\.gd"\s*\)')

# 名字里的读数：墙钟 / 游戏时间 / 帧数随档变，掩掉；计数（caption=1、shots=5/5）不掩
MEASURE = re.compile(r"(?:(?<=ms=)|(?<=frames=))\d+|\d+(?:\.\d+)?(?=\s*(?:ms|s\b|秒|帧|fps))")


def mask(s):
    return MEASURE.sub("#", s)


def probes(root=ROOT):
    """tools/ 下 git 已跟踪 .gd 里代码行调了 ShotGate.frame_pressure( 的（注释里写了不算），按路径排序。"""
    out = subprocess.run(["git", "ls-files", "--", "tools"], cwd=root, capture_output=True, text=True, check=True).stdout
    found = []
    for f in sorted(out.split("\n")):
        if not f.endswith(".gd") or f == "tools/shot_gate.gd":
            continue
        try:
            src = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
        if USES.search(code) and "ShotGate.frame_pressure(" in code:
            found.append(f)
    return found


def name_of(f):
    return os.path.splitext(os.path.basename(f))[0]


def conclusion(doc):
    """探针 JSON 行 → 可比的结论。doc 为 None（没 JSON 行 / 超时）时带 run_error。"""
    if doc.get("run_error"):
        return {"rc": doc.get("exit_code"), "error": doc["run_error"], "script_errors": False, "checks": ()}
    checks = tuple(sorted(("warn" if c.get("level") == "warn" else ("ok" if c.get("ok") else "fail"), mask(str(c.get("name", ""))))
                          for c in doc.get("checks") or []))
    return {"rc": doc.get("exit_code"), "error": doc.get("error") or "",
            "script_errors": int((doc.get("counts") or {}).get("script_errors") or 0) > 0, "checks": checks}


def green(c):
    return c["rc"] == 0 and not c["error"] and not c["script_errors"]


def brief(c):
    """一档结论一句话：绿 n/n / 红 rc=… error=… ✗k。"""
    if c["error"] in ("no_json", "timeout"):
        return f"跑不成（{c['error']}，rc={c['rc']}）"
    ok = sum(1 for k, _ in c["checks"] if k == "ok")
    bad = sum(1 for k, _ in c["checks"] if k == "fail")
    warn = sum(1 for k, _ in c["checks"] if k == "warn")
    w = f" ⚠{warn}" if warn else ""
    se = " SCRIPT ERROR" if c["script_errors"] else ""
    if green(c):
        return f"绿 {ok}/{ok + bad}{w}"
    err = f" error={c['error']}" if c["error"] else ""
    return f"红 rc={c['rc']}{err} ✗{bad}/{ok + bad}{w}{se}"


def compare(cs):
    """cs：[(档, 结论)...]，第一档为基准。返回 (类, 明细行)：类 = same_green / same_red / broken / differ。"""
    base_lv, base = cs[0]
    if any(c["error"] in ("no_json", "timeout") for _, c in cs):
        return "broken", []
    lines = []
    for lv, c in cs[1:]:
        if c == base:
            continue
        for key in ("rc", "error", "script_errors"):
            if c[key] != base[key]:
                lines.append(f"{key}：档 {base_lv} = {base[key]!r} · 档 {lv} = {c[key]!r}")
        a, b = set(base["checks"]), set(c["checks"])
        for k, n in sorted(a - b):
            lines.append(f"只在档 {base_lv}：{'✓' if k == 'ok' else '✗' if k == 'fail' else '⚠'} {n}")
        for k, n in sorted(b - a):
            lines.append(f"只在档 {lv}：{'✓' if k == 'ok' else '✗' if k == 'fail' else '⚠'} {n}")
        if not lines:  # 集合相同、重数不同
            lines.append(f"条目重数不同：档 {base_lv} {len(base['checks'])} 条 · 档 {lv} {len(c['checks'])} 条")
    if lines:
        return "differ", lines
    return ("same_green" if green(base) else "same_red"), []


# 没接 --json 的探针（既不 preload gate_report.gd、也不走 ShotGate 收尾）登记人读判词：(逐路行正则, 末行正则)，
# 逐路行取「路 + 判词」两组、判词为 OK 才算过；末行整句（读数掩掉）进结论。没登记的判「跑不成」（fail closed：新探针要么接 --json、要么来这里登记）
TEXT_PROBES = {
    "qa_yard_transition_probe": (r"^FO_CASE (\S+) (\S+)", r"^YARD_TRANSITION_PROBE (?:OK|FAIL \d+).*"),
}


def entry(root, f):
    """(命令行入口, 走 JSON 与否)。`extends SceneTree / MainLoop` 的用 `-s`；否则跑同名 .tscn（-s 起非 MainLoop 脚本，Godot 弹 xmessage 挂住）。"""
    src = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
    code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
    native = 'preload("res://tools/gate_report.gd")' in code or "ShotGate.finish_" in code
    if re.search(r"^extends\s+(SceneTree|MainLoop)\b", src, re.M):
        return ["-s", "res://" + f], native
    scn = os.path.splitext(f)[0] + ".tscn"
    return (["res://" + scn] if os.path.exists(os.path.join(root, scn)) else ["-s", "res://" + f]), native


def text_doc(probe, stdout, rc):
    """人读输出 → 与 JSON 行同形的文档（TEXT_PROBES 登记的探针）。"""
    case_re, tail_re = (re.compile(x) for x in TEXT_PROBES[probe])
    checks = []
    tail = None
    for ln in stdout.splitlines():
        m = case_re.match(ln)
        if m:
            checks.append({"name": f"{m.group(1)} {m.group(2)}", "ok": m.group(2) == "OK"})
        elif tail_re.match(ln):
            tail = ln
    if tail is None:
        return {"run_error": "no_json", "exit_code": rc}
    checks.append({"name": tail, "ok": rc == 0})
    return {"exit_code": rc, "checks": checks, "counts": {"script_errors": stdout.count("SCRIPT ERROR")}}


def _json_line(stdout):
    rows = [ln for ln in stdout.splitlines() if ln.startswith("{")]
    for ln in reversed(rows):
        try:
            return json.loads(ln)
        except ValueError:
            continue
    return None


def run_one(godot, root, f, level, out):
    """跑一支一档，落 <out>/L<档>/<支>.json / .log，返回 (JSON 或 run_error 文档, 墙钟秒)。"""
    lv_dir = os.path.join(out, f"L{level}")
    os.makedirs(lv_dir, exist_ok=True)
    xdg = os.path.join(out, "xdg", f"L{level}", name_of(f))
    shutil.rmtree(xdg, ignore_errors=True)
    os.makedirs(xdg)
    env = dict(os.environ)
    env.pop(ENV_SLOW, None)
    env.pop("NK1_SHOT_CONTRACT", None)
    if level > 0:
        env[ENV_SLOW] = str(level)
    env["NK1_SHOT_DIR"] = lv_dir
    env["XDG_DATA_HOME"] = xdg
    env.setdefault("DISPLAY", ":2")
    args, native = entry(root, f)
    # --quiet 静掉全部 print（JSON 行由 gate_report 临时打开 stdout 打出）；人读判词型不能加
    cmd = [godot, *(["--quiet"] if native else []), "--path", root, *args] + (["--", "--json"] if native else [])
    t0 = time.time()
    # 自成进程组：超时连 Godot 起的子进程（xmessage 报错框等）一起杀，不留孤儿
    p = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = p.communicate(timeout=RUN_TIMEOUT)
        rc = p.returncode
        if native:
            doc = _json_line(stdout) or {"run_error": "no_json", "exit_code": rc}
        elif name_of(f) in TEXT_PROBES:
            doc = text_doc(name_of(f), stdout, rc)
        else:
            doc = {"run_error": "no_json", "exit_code": rc}
            stderr += "\n[probe_pressure] 探针没接 --json、也没在 TEXT_PROBES 登记人读判词，结论取不到"
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        stdout, stderr = p.communicate()
        doc = {"run_error": "timeout", "exit_code": 124}
    secs = time.time() - t0
    base = os.path.join(lv_dir, name_of(f))
    with open(base + ".json", "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False)
    with open(base + ".log", "w", encoding="utf-8") as fh:
        fh.write(" ".join(cmd) + f"\n# {ENV_SLOW}={env.get(ENV_SLOW, '')} secs={secs:.1f}\n" + stdout + "\n--- stderr ---\n" + stderr)
    return doc, secs


def sweep(godot, root, files, levels, out, jobs, say=print):
    """全部 支 × 档 跑完，逐支比。返回 [{probe, levels: {档: (结论, 秒)}, kind, lines}]。"""
    tasks = [(f, lv) for f in files for lv in levels]
    tasks.sort(key=lambda t: -t[1])  # 慢档先起，尾巴短
    res = {}
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
        futs = {(f, lv): ex.submit(run_one, godot, root, f, lv, out) for f, lv in tasks}
        for key, fu in futs.items():
            doc, secs = fu.result()
            res[key] = (conclusion(doc), secs)
    rows = []
    for f in files:
        cs = [(lv, res[(f, lv)][0]) for lv in levels]
        kind, lines = compare(cs)
        rows.append({"probe": name_of(f), "file": f, "levels": {lv: res[(f, lv)] for lv in levels}, "kind": kind, "lines": lines})
    return rows


# ── 零、判据自检：比较器对造出来的结论对判得对（不起 Godot）──
def _doc(rc=0, checks=(), error=None, se=0):
    d = {"exit_code": rc, "checks": [{"name": n, "ok": ok} for ok, n in checks], "counts": {"script_errors": se}}
    if error:
        d["error"] = error
    return d


# gd20 原反例（letterbox_signal 超上界 950 ms / 帧，gd14 版：正常全绿；压帧下 1 行误诊挂死、4 行靠多停 4 帧碰上 finished 变绿）与
# 本片 M1 实测（qa_title 数 36 帧：档 0 绿、档 300 两张停拍图红）原文收在最前两对
_GD20_OK = "finish/出战带on_black  caption=1 covered=1 on_black=1 finished=1 raw_await=resumed ms=3561"
SAMPLES = [
    ("gd20 原反例：压帧下 1 行误诊挂死", _doc(0, [(True, _GD20_OK), (True, "finish/入战  caption=1 covered=0 on_black=0 finished=1 raw_await=resumed ms=2933")]),
     _doc(1, [(True, _GD20_OK.replace("3561", "24086")),
              (False, "finish/入战：裸 await finished 没醒（等待方挂死）  [caption=1 covered=0 on_black=0 finished=0 raw_await=HUNG ms=20017]")]), "differ"),
    ("M1 实测：数 36 帧，档 300 停拍已过", _doc(0, [(True, "03_transition_prologue_open.png"), (True, "04_transition_prologue_shore.png")]),
     _doc(1, [(True, "03_transition_prologue_open.png"), (False, "03_transition_prologue_open 截图时墨幕已过停拍"),
              (True, "04_transition_prologue_shore.png"), (False, "04_transition_prologue_shore 截图时墨幕已过停拍")]), "differ"),
    ("同绿（读数不同）", _doc(0, [(True, "finish/入战  caption=1 raw_await=resumed ms=2921"), (True, "01_title_start.png")]),
     _doc(0, [(True, "finish/入战  caption=1 raw_await=resumed ms=8467"), (True, "01_title_start.png")]), "same_green"),
    ("rc 不同（一档绿一档红）", _doc(0, [(True, "04_x.png")]),
     _doc(1, [(False, "04_x 截图时墨幕已过停拍")]), "differ"),
    ("同 rc、红的行不同", _doc(1, [(False, "行 A 红")]), _doc(1, [(False, "行 B 红")]), "differ"),
    ("同红同行（读数不同）", _doc(1, [(False, "布景自带的入战墨边 15000 ms 内没收场（16 帧）")], "no_signal"),
     _doc(1, [(False, "布景自带的入战墨边 15000 ms 内没收场（24 帧）")], "no_signal"), "same_red"),
    ("error 码不同", _doc(1, [(False, "x")], "no_signal"), _doc(1, [(False, "x")], "wall_clock"), "differ"),
    ("计数不掩（caption=0 vs 1）", _doc(0, [(True, "row caption=0")]), _doc(0, [(True, "row caption=1")]), "differ"),
    ("张数不同（少一张）", _doc(0, [(True, "01.png"), (True, "02.png")]), _doc(0, [(True, "01.png")]), "differ"),
    ("只一档有 warn", _doc(0, [(True, "01.png")]), {**_doc(0, [(True, "01.png")]),
                                                  "checks": [{"name": "01.png", "ok": True}, {"name": "演出没静下来", "ok": True, "level": "warn"}]}, "differ"),
    ("只一档 SCRIPT ERROR", _doc(0, [(True, "01.png")]), _doc(0, [(True, "01.png")], se=1), "differ"),
    ("一档没 JSON 行", _doc(0, [(True, "01.png")]), {"run_error": "no_json", "exit_code": 0}, "broken"),
    ("一档超时", _doc(0, [(True, "01.png")]), {"run_error": "timeout", "exit_code": 124}, "broken"),
]


def selftest():
    bad = []
    for name, a, b, want in SAMPLES:
        got, _ = compare([(0, conclusion(a)), (300, conclusion(b))])
        if got != want:
            bad.append(f"{name}：期望 {want}，实得 {got}")
    # 人读判词型（TEXT_PROBES）：逐路行取「路 + 判词」、读数不进结论；末行丢了取不到结论
    out = ("FO_CASE repair/mouse OK rc=80 first=80 ready=2f/960ms\nFO_CASE buy_ship/emit DOUBLE_CHARGE price=900\n"
           "YARD_TRANSITION_PROBE FAIL 1（OK=1 DOUBLE_CHARGE=1）\n")
    d = text_doc("qa_yard_transition_probe", out, 1)
    if [(c["name"], c["ok"]) for c in d.get("checks", [])] != [("repair/mouse OK", True), ("buy_ship/emit DOUBLE_CHARGE", False),
                                                              ("YARD_TRANSITION_PROBE FAIL 1（OK=1 DOUBLE_CHARGE=1）", False)]:
        bad.append(f"人读判词解析不对：{d}")
    if text_doc("qa_yard_transition_probe", out.rsplit("YARD", 1)[0], 0).get("run_error") != "no_json":
        bad.append("人读判词型缺末行没判成取不到结论")
    if mask("ms=2921 15000 ms 3.5 s 16 帧 frames=40 caption=1 shots=5/5 01_title.png") != "ms=# # ms # s # 帧 frames=# caption=1 shots=5/5 01_title.png":
        bad.append("读数掩码不对：" + mask("ms=2921 15000 ms 3.5 s 16 帧 frames=40 caption=1 shots=5/5 01_title.png"))
    return bad


# ── 反向变异：探针的完成判据从信号 / 相位改回固定帧数（碰运气），须判两档结论不同 ──
# (编号, 探针, 说明, [(正则, 替换, 处数)])
MUTANTS = [
    ("M1", "tools/qa_title_probe.gd", "墨幕停拍改回数 36 帧（gd14 前原写法），不再 Clock.wait_hold 按相位等",
     [(r"^\tvar why := await Clock\.wait_hold\(self, node\)\n", "\tfor _i in 36:\n\t\tawait process_frame\n\tvar why := \"\"\n", 1)]),
    ("M2", "tools/letterbox_signal_probe.gd", "_settle 不等 raw_await（finished 信号），改成先停 40 帧、条件恒真",
     [(r"^(func _settle\(w: Dictionary\) -> void:\n)", r"\1\tawait _frames(40)\n", 1),
      (r"return w\.raw_await, SCENE_MS\):", "return true, SCENE_MS):", 1)]),
]


def _apply(wt, rel, subs):
    p = os.path.join(wt, rel)
    text = open(p, encoding="utf-8").read()
    for pat, repl, n in subs:
        text, k = re.subn(pat, repl, text, flags=re.M)
        if k != n:
            return f"变异没落上：{rel} 里 {pat!r} 替换 {k} 处（期望 {n}），源码改了、这支变异跟着改"
    open(p, "w", encoding="utf-8").write(text)
    return ""


def mutants(godot, levels, out, jobs, say):
    """临时 worktree（当前工作树已跟踪文件，含未提交改动）：B0 未变异两档须一致绿，M1 / M2 须两档结论不同。"""
    problems = []
    st = subprocess.run(["git", "stash", "create"], cwd=ROOT, capture_output=True, text=True)
    if st.returncode != 0:  # 索引里有未解决的冲突等：报出来，不把报错文本当 ref 用
        say(f"  ✗ git stash create 失败（rc={st.returncode}）：{(st.stderr or st.stdout).strip()}")
        return ["stash"], 2
    snap = st.stdout.strip() or "HEAD"
    wt = tempfile.mkdtemp(prefix="probe_pressure_wt_")
    os.rmdir(wt)
    r = subprocess.run(["git", "worktree", "add", "--detach", wt, snap], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        say(f"  ✗ 建不了临时 worktree：{r.stderr.strip()}")
        return ["worktree"], 2
    try:
        subprocess.run([godot, "--headless", "--import", "--path", wt], capture_output=True, timeout=600)
        files = [f for _, f, _, _ in MUTANTS]
        base = sweep(godot, wt, files, levels, os.path.join(out, "B0"), jobs)
        for row in base:
            ok = row["kind"] == "same_green"
            say(f"  {'✓' if ok else '✗'} B0 {row['probe']}（未变异）：{_levels_brief(row)}"
                + ("" if ok else f"——基线须两档一致绿，实得 {KIND[row['kind']]}"))
            if not ok:
                problems.append(f"B0 {row['probe']}")
        for mid, f, why, subs in MUTANTS:
            miss = _apply(wt, f, subs)
            if miss:
                say(f"  ✗ {mid} {name_of(f)}：{miss}")
                problems.append(mid)
                continue
            row = sweep(godot, wt, [f], levels, os.path.join(out, mid), jobs)[0]
            ok = row["kind"] == "differ"
            say(f"  {'✓' if ok else '✗'} {mid} {row['probe']}（{why}）：{_levels_brief(row)} → {KIND[row['kind']]}"
                + ("" if ok else "——期望「两档结论不同」"))
            for ln in row["lines"][:6]:
                say(f"       {ln}")
            if not ok:
                problems.append(mid)
            subprocess.run(["git", "checkout", "--", f], cwd=wt, capture_output=True)
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", wt], cwd=ROOT, capture_output=True)
    return problems, 0


KIND = {"same_green": "两档一致绿", "same_red": "两档同红", "broken": "跑不成", "differ": "两档结论不同"}


def _levels_brief(row):
    return " ｜ ".join(f"档 {lv}：{brief(c)}（{s:.0f} s）" for lv, (c, s) in row["levels"].items())


def _arg(name, default):
    for a in sys.argv[1:]:
        if a.startswith(f"--{name}="):
            return a.split("=", 1)[1]
    if f"--{name}" in sys.argv[1:]:
        i = sys.argv.index(f"--{name}")
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


def main():
    problems = []
    print("零、判据自检（造出来的结论对，不起 Godot）")
    bad = selftest()
    for b in bad:
        print(f"  ✗ {b}")
    if not bad:
        print(f"  ✓ {len(SAMPLES)} 对样本判对（同绿 / 同红读数不同算一致；rc、error、红的行、计数、张数、warn、SCRIPT ERROR、"
              "没 JSON、超时各判得出），读数掩码对，人读判词解析对")
    problems += bad
    if "--selftest" in sys.argv[1:]:
        print("结果：全部通过" if not problems else f"结果：{len(problems)} 项问题")
        return 1 if problems else 0
    godot = shutil.which("godot")
    if not godot:
        print("  ✗ 找不到 godot（PATH）")
        print("结果：1 项问题")
        return 2
    try:
        levels = tuple(int(x) for x in _arg("levels", ",".join(map(str, LEVELS))).split(","))
    except ValueError:
        print("  ✗ --levels 要逗号分隔的整数毫秒")
        return 2
    if len(levels) < 2 or len(set(levels)) != len(levels):
        print("  ✗ --levels 至少两档、不许重复")
        return 2
    if not any(lv * 1.0 < 1000 / 7.5 for lv in levels) or not any(lv >= 1000 / 7.5 for lv in levels):
        print(f"  ⚠ 档 {levels} 没有同时含不封顶（< 134 ms）与封顶（≥ 134 ms）两类：数固定帧数碰运气的探针在这组档下可能照样一致")
    jobs = int(_arg("jobs", "2"))
    out = os.path.abspath(_arg("out", DEFAULT_OUT))
    os.makedirs(out, exist_ok=True)

    if "--mutants" in sys.argv[1:]:
        print(f"一、反向变异（临时 worktree，档 {' / '.join(map(str, levels))} ms；B0 须一致绿，变异须两档结论不同）")
        probs, code = mutants(godot, levels, os.path.join(out, "mutants"), jobs, print)
        if code:
            print(f"结果：{len(probs)} 项问题")
            return code
        problems += probs
        print("结果：全部通过" if not problems else f"结果：{len(problems)} 项问题")
        return 1 if problems else 0

    files = probes()
    only = _arg("only", "")
    if only:
        want = [w.strip() for w in only.split(",") if w.strip()]
        unknown = [w for w in want if w not in {name_of(f) for f in files}]
        if unknown:
            print(f"  ✗ --only 里不在探针集：{', '.join(unknown)}（探针集 = 代码行调了 ShotGate.frame_pressure 的已跟踪 .gd）")
            print("结果：1 项问题")
            return 2
        files = [f for f in files if name_of(f) in want]
    print(f"一、逐支双档（{len(files)} 支 × 档 {' / '.join(map(str, levels))} ms，{ENV_SLOW}；jobs={jobs}；落 {out}/L<档>/）")
    t0 = time.time()
    rows = sweep(godot, ROOT, files, levels, out, jobs)
    for row in rows:
        ok = row["kind"] == "same_green"
        print(f"  {'✓' if ok else '✗'} {row['probe']}：{KIND[row['kind']]}——{_levels_brief(row)}")
        for ln in row["lines"]:
            print(f"       {ln}")
        if not ok:
            problems.append(row["probe"])
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump([{"probe": r["probe"], "kind": r["kind"], "lines": r["lines"],
                    "levels": {str(lv): {"brief": brief(c), "secs": round(s, 1), "rc": c["rc"], "error": c["error"]}
                               for lv, (c, s) in r["levels"].items()}} for r in rows], fh, ensure_ascii=False, indent=1)
    n = {k: sum(1 for r in rows if r["kind"] == k) for k in KIND}
    print(f"  共 {len(rows)} 支：一致绿 {n['same_green']} / 两档结论不同 {n['differ']} / 两档同红 {n['same_red']} / 跑不成 {n['broken']}"
          f"（墙钟 {time.time() - t0:.0f} s；逐跑 JSON / 日志在 {out}/L<档>/，汇总 {out}/summary.json）")
    print("二、交接 shot_consistency（像素归它，本门禁不代跑）")
    print(f"  godot --headless --path . -s res://tools/shot_consistency.gd -- --a={out}/L{levels[0]} --b={out}/L{levels[-1]}")
    print("结果：全部通过" if not problems else f"结果：{len(problems)} 项问题")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
