#!/usr/bin/env python3
"""docs/GATES.md §一（门禁总表 / 门禁开关与附属自检 / 截图门禁明细 / 不算门禁）、§二（批量巡检）与 §四（CI 建议步骤）
按 tools/gate_json.py 的注册表生成，本脚本校验二者一致；§三「一键人读全跑」与 .claude/todo.md 验证段是手写，只比对。
附属自检（一键跑把关判据自检「三之一」，lane w20-b3）与 §一 附属表同册：禁带字样 / 漏跑 / 道数不符 / README 道数见 §三.19。
§一 尾句断言（lane w49-k4）与 §一 附属表同册（「二、docs/GATES.md」生成块计数域内）：(a) 道数 = 注册表必跑档条数（纯 must-tier，与生成器§一尾句 M 格同口径；lane w50-k1 拨正——旧判 M=一键跑条数含 step 与生成块实产物 1 位差错位竿红）；(b) lane 枚举行集合 = 注册表 lane 集——w48-k1 升格实证零断言格升格链滞一格零红照补。
「二、docs/GATES.md」另有 SHOT 张数逐条对账格（lane w29-k5）：SHOT_PROBES 每条的注册表张数 ↔ §一 同行张数字段，漂移逐支点名、不回读源码。
「三、docs/GATES.md」另有 SHOT 张数格同型 clone（lane w33-k2，源 w30-k6 交主控 #2 / 审计-wave29 §85）：§四 / §二 生成块整块红一句「首处差异在第 k 行 / 逐字一致✗」不能逐支点名，row_sources(reg) 把两块的注册表出处行映成 (行 → 出处) 表，凡 in known 的行判与注册表块逐字同、漂移逐支点名 id + 出处 + 行文书；known 外零源行（表头 / ``` / 第 0 步命令段等）照旧由整块格逐字一致兜。行格与整块格互补、不回读源码。

  python3 tools/gates_md.py            # 自检：文档与注册表不一致、注册的脚本缺失、接 shot_gate 的截图脚本没入册、
                                       #       附属自检的开关在源码里找不到、§三 一键跑命令 / .claude/todo.md 验证段与必跑清单不符 → 退 1
  python3 tools/gates_md.py --write    # 按注册表重写 GATES.md 三个标记块（块外手写部分、todo.md 不动），写完再自检
  python3 tools/gates_md.py --json     # 机读（同 docs/GATES.md §二）

改门禁清单只改 tools/gate_json.py 的 REGISTRY / SHOT_PROBES / SUBCHECKS / CI_STEPS，再 --write；别手改标记块。
"""
import json, os, re, subprocess, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

DOC = os.path.join(ROOT, "docs", "GATES.md")
TODO = os.path.join(ROOT, ".claude", "todo.md")
BEGIN = "<!-- GATES:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 注册表生成，勿手改 -->"
END = "<!-- GATES:END -->"
CI_BEGIN = "<!-- GATES-CI:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 的 CI_STEPS 生成，勿手改 -->"
CI_END = "<!-- GATES-CI:END -->"
CI_HEAD = "## 四、CI 建议步骤"
BATCH_BEGIN = "<!-- GATES-BATCH:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 的 oneclick_json 生成，勿手改 -->"
BATCH_END = "<!-- GATES-BATCH:END -->"
BATCH_HEAD = "## 二、`--json` 机读输出"
BATCH_DIR = "/tmp/gates"
# 批量巡检收尾汇总交 gate_json.py --judge（lane gd7）：Python / 外包的整段多行 JSON、原生的一行 JSON 都认；
# 原生 --json 被信号杀 / 引擎崩溃时不出 JSON 行（docs/GATES.md §二末），按红计；多行 JSON、ok 与 exit_code 不符也红
BATCH_SUM = "python3 tools/gate_json.py --judge %s/*.json   # 汇总：逐道一行 ✓/✗；任一道红或没有 JSON 行 → 退 1" % BATCH_DIR
CN = "零一二三四五六七八九十"

fails = []


# ── 一键跑把关（lane w20-b3；起因 g8 W1：§三 一键跑段与 todo 验证段被塞进 `--no-ledger-landing` 后，
#    check_symbols / check_decision_refs 仍全 rc=0（红因各自的落点预检被关掉），只有本脚本两条字符串比对红——
#    「一键跑真跑全了」不能只靠文本比对兜，而且比对的红因只印「不符」、不说清是漏跑 / 多条 / 关断）──
# 禁带字样：两枚 LANDING_OFF 关断开关只许变异对照脚本（check_symbols_mutants._run_case / ledger_refs_mutants._det_case）
# 在变异过的 worktree 里自带；样值从两支脚本的 LANDING_OFF 常量现读，不在此另抄（改名 / 挪走即「三之一」红）。
OFF_LIMITS_NOTE = {"check_symbols_mutants": "check_symbols 十四节「落点预检」的关断开关，只许 check_symbols_mutants 在变异 worktree 里带",
                   "ledger_refs_mutants": "check_decision_refs「零之二、落点预检」的关断开关，只许 ledger_refs_mutants 在变异 worktree 里带"}
UNIVERSAL_OFF = {"--help": "带上一道门禁就不干活（打帮助退 0 / 2），一键跑里等于没跑",
                 "--dry-run": "是不是真跑由脚本自定，一键跑里不许赌"}


def off_limits():
    """一键跑命令段禁带字样 → 理由。两枚 LANDING_OFF 从各自脚本 import 现读；读不到记空串占位（「三之一」判红）。"""
    import importlib
    out = {}
    for mod, note in OFF_LIMITS_NOTE.items():
        try:
            out[importlib.import_module(mod).LANDING_OFF] = note
        except (ImportError, AttributeError):
            out[""] = note + "；本脚本 import 不到它的 LANDING_OFF 常量（改名 / 挪走了？）"
    out.update(UNIVERSAL_OFF)
    return out


def oneclick_sweep(cmds, must_cmds, where, by_cmd):
    """一段一键跑命令（已从命令段抠成列表）的三条机判，返回问题行列表（不直接记账，main / 自检共用）：
    ① 禁带字样（关断开关 / --help / --dry-run）；② 必跑档条目缺席（逐条比对红时这里给出「谁漏了」的红因）；
    ③ 条数与必跑档不符（多出来的行没进注册表没人认）。比对本身仍在 main 里照旧逐条跑，本判据与它互补。"""
    probs, ol = [], off_limits()
    if "" in ol:
        probs.append(f"{where}禁带字样读不到 LANDING_OFF 常量：{ol['']}")
    tokens = set().union(*(c.split() for c in cmds)) if cmds else set()
    for flag in sorted(f for f in ol if f and f in tokens):
        probs.append(f"{where}出现禁带字样 {flag}：{ol[flag]}——一键跑不许靠关断 / 空转参数蒙绿（g8 W1）")
    missing = [m for m in must_cmds if m not in cmds]
    if missing:
        probs.append(f"{where}缺席必跑档 {len(missing)} 条（{'、'.join(by_cmd.get(m, m) for m in missing)}）"
                     f"——必跑档在一键跑里漏跑，剩下的照跑照绿（g8 W1 同类）")
    if len(cmds) != len(must_cmds):
        probs.append(f"{where}命令 {len(cmds)} 条，必跑档 {len(must_cmds)} 条——道数不符："
                     f"多出来的行没进注册表没人认，少了就是必跑漏跑（道数口径见 docs/GATES.md §一注册表）")
    return probs


def sweep_selfcheck(mutate=None):
    """「三之一、一键跑把关判据自检」。mutate：内存里把禁带样值换掉（自检的反向变异——改的样值必须立即使自检红）。"""
    print("三之一、一键跑把关判据自检（lane w20-b3：把关判据自己的靶子漂了当场红）")
    ol = off_limits()
    if mutate:
        ol = mutate(ol)
    check("" not in ol and len([f for f in ol if f]) == len(OFF_LIMITS_NOTE) + len(UNIVERSAL_OFF),
          "两枚关断开关字样从 tools/check_symbols_mutants.py / tools/ledger_refs_mutants.py import 现读得到"
          + (f"（LANDING_OFF 常量改名 / 挪走了：{ol.get('', '空串占位进了判据')}）" if "" in ol else ""))
    base = ["python3 tools/check_decision_refs.py"]
    by_cmd = {base[0]: "check_decision_refs"}
    # ① 禁带字样：逐枚注入都须红、不注入须绿
    injected = [p for f in sorted(f for f in ol if f)
                for p in oneclick_sweep([base[0] + " " + f], base, "自检注入", by_cmd) if f in p]
    check(len(injected) == len([f for f in ol if f]) and not oneclick_sweep(base, base, "自检对照", by_cmd),
          f"禁带字样 {len([f for f in ol if f])} 枚逐枚注入命令段都判红（红因点名该字样）、不注入判绿")
    # ② 缺席：删掉必跑条目须红，红因必须说「缺席」
    miss = oneclick_sweep([], base, "自检缺一条", by_cmd)
    check(bool(miss) and any("缺席" in p for p in miss), "删掉必跑条目判红，红因注明「缺席」")
    # ③ 道数：多出一行须红，红因必须说「道数不符」
    more = oneclick_sweep(base + ["python3 tools/x.py"], base, "自检多一条", by_cmd)
    check(bool(more) and any("道数不符" in p for p in more), "多出一行判红，红因注明「道数不符」")


# ── 判词 ↔ SCRIPT ERROR 接线（lane w53-11）：注册表 Godot 门禁的判词称「SCRIPT ERROR 即红」，脚本代码行里就得真挂
#    计数器、收尾真判（判词 judge 与红长相 red 两栏都认：「…SCRIPT ERROR…即红 / 即判红 / 即算失败」；只查 must / lane 档）。起因：wave53 前四支必跑 qa_* 与九支 lane 档的判词都照抄 story 那句，探针却零 Logger——
#    运行期脚本错把断言整段跳过照退 0，判词背书空转了几十波没人发现；文案比对管不到「说了没做」。
#    接法三种都认：共用件 tools/script_err_tally.gd 的 verdicts()、story 自带的 _script_error_check()、
#    自挂 Logger 后判 `.lines.is_empty()`（qa_pirate_boat_probe 式）；接共用件的另须走 _run_guarded 包装
#    （_run 自身出错时 quit 不执行、进程空转到超时，包装层回来即判红）。注释行里的字样不算。──
SCRIPT_ERR_CLAIM = re.compile(r"SCRIPT ERROR`?[^；;。]{0,40}?即(?:判)?(?:红|算失败)")
SCRIPT_ERR_ARM = "OS.add_logger("
SCRIPT_ERR_JUDGE = ("verdicts()", "_script_error_check()", ".lines.is_empty()")
SCRIPT_ERR_SHARED = "script_err_tally.gd"
SCRIPT_ERR_GUARD = ("_run_guarded", "await _run(")


def code_lines(text):
    """去掉整行注释（GDScript / Python 都以 # 起头）后的源码。"""
    return "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith("#"))


def script_err_wiring(judge, src):
    """判词称 SCRIPT ERROR 即红时返回 src（已去注释）缺的接线列表（空 = 接全）；判词不称返回 None（不适用）。"""
    if not SCRIPT_ERR_CLAIM.search(judge or ""):
        return None
    lost = []
    if SCRIPT_ERR_ARM not in src:
        lost.append("挂计数器 OS.add_logger(…)")
    if not any(k in src for k in SCRIPT_ERR_JUDGE):
        lost.append("收尾判（" + " / ".join(SCRIPT_ERR_JUDGE) + " 之一）")
    if SCRIPT_ERR_SHARED in src and not all(k in src for k in SCRIPT_ERR_GUARD):
        lost.append("接共用件须走 _run_guarded 包装（await _run(…) 回来未收尾即判红）")
    return lost


def script_err_section(gates):
    print("一之二、判词 ↔ SCRIPT ERROR 接线（lane w53-11：判词称「SCRIPT ERROR 即红」的 Godot 门禁须真接线）")
    # 零、判据自检（§五.3）：内存样本走同一条判路——该红的探不出即红，该绿的误红也红
    claim = "本进程 SCRIPT ERROR 即红。"
    full = ('const T := preload("res://tools/script_err_tally.gd")\nOS.add_logger(_tally)\n'
            'func _run_guarded() -> void:\n\tawait _run()\nfor v in _tally.verdicts():')
    samples = [
        ("S1 判词称即红、零 Logger", claim, "func _run() -> void:\n\tquit(0)", True),
        ("S2 挂了 Logger、收尾不判", claim, "OS.add_logger(_tally)\nquit(0)", True),
        ("S3 接共用件、没包 _run_guarded", claim,
         'preload("res://tools/script_err_tally.gd")\nOS.add_logger(_tally)\nfor v in _tally.verdicts():', True),
        ("S4 接线只写在注释里", claim, code_lines("# OS.add_logger(_tally)\n\t## for v in _tally.verdicts():"), True),
        ("C1 共用件接全", claim, full, False),
        ("C2 story 式自带判", "运行中出 SCRIPT ERROR（含 Parse Error / Compile Error）即判红",
         "OS.add_logger(_script_errs)\n_script_error_check()", False),
        ("S5 红长相称「即算失败」、零 Logger", "输出含 `SCRIPT ERROR` 即算失败", "quit(0)", True),
        ("C3 判词不称", "autoload 起得来", "quit(0)", None),
    ]
    for name, judge, src, want in samples:
        lost = script_err_wiring(judge, src)
        got = None if lost is None else bool(lost)
        want_s = "不适用" if want is None else ("该红" if want else "该绿")
        check(got == want, f"判据自检 {name}：{want_s}（实得 {lost}）")
    for g in gates:
        if g["kind"] != "godot" or not g.get("file") or g["tier"] not in ("must", "lane"):
            continue
        try:
            src = code_lines(open(os.path.join(ROOT, g["file"]), encoding="utf-8", errors="replace").read())
        except OSError:
            src = ""
        lost = script_err_wiring((g.get("judge") or "") + "\n" + (g.get("red") or ""), src)
        if lost is not None:
            check(not lost, f"{g['id']} 判词 / 红长相称「SCRIPT ERROR 即红」，{g['file']} 代码行里真接了线"
                  + (f"；缺：{'、'.join(lost)}" if lost else ""))


# ── `_run` 断气不空转（lane w53-11 四轮）：注册表 must / lane 档 Godot 门禁的脚本若直接把 `_run` 排进首帧
#    （call_deferred("_run") / _run.call_deferred()），`_run` 自己的代码行一出脚本错，GDScript 只中止 `_run`、后面的 quit
#    永不执行，进程空转到外层超时（rc=124 按规矩当假红重跑，真回归被当成机器噪声）。须改排 _run_guarded 包装
#    （await _run() 回来未收尾即判红退出），或 preload 了 shot_gate（其每帧看门兜底 `_run` 断气）。与判词称不称
#    「SCRIPT ERROR 即红」无关——不判脚本错的门禁照样会挂死。注释行里的字样不算。──
RUN_BARE_ENTRY = re.compile(r'call_deferred\(\s*"_run"\s*\)|\b_run\.call_deferred\(')
RUN_WATCHED = 'preload("res://tools/shot_gate.gd")'


def run_abort_hang(src):
    """src（已去注释）直接排 `_run` 起跑、又没接 shot_gate 看门时返回 True（`_run` 断气会空转到超时）。"""
    return bool(RUN_BARE_ENTRY.search(src)) and RUN_WATCHED not in src


def run_abort_section(gates):
    print("一之三、`_run` 断气不空转（lane w53-11：直接排 `_run` 起跑的 Godot 门禁须有 _run_guarded 包装或 shot_gate 看门）")
    samples = [
        ("R1 直接排 _run、无兜底", 'func _init() -> void:\n\tcall_deferred("_run")', True),
        ("R2 _run.call_deferred() 写法", "func _init() -> void:\n\t_run.call_deferred()", True),
        ("R3 兜底只写在注释里", code_lines('call_deferred("_run")\n# const S := preload("res://tools/shot_gate.gd")'), True),
        ("C1 排 _run_guarded 包装", 'call_deferred("_run_guarded")\nfunc _run_guarded() -> void:\n\tawait _run()', False),
        ("C2 直接排 _run、接了 shot_gate 看门", 'const S := preload("res://tools/shot_gate.gd")\ncall_deferred("_run")', False),
        ("C3 不经 _run（_initialize 同步跑完）", "func _initialize() -> void:\n\tquit(0)", False),
    ]
    for name, src, want in samples:
        got = run_abort_hang(src)
        check(got == want, f"判据自检 {name}：{'该红' if want else '该绿'}（实得 {'红' if got else '绿'}）")
    seen, hang = 0, []
    for g in gates:
        if g["kind"] != "godot" or not g.get("file") or g["tier"] not in ("must", "lane"):
            continue
        try:
            src = code_lines(open(os.path.join(ROOT, g["file"]), encoding="utf-8", errors="replace").read())
        except OSError:
            continue
        seen += 1
        if run_abort_hang(src):
            hang.append(f"{g['id']}（{g['file']}）")
    check(not hang, f"必跑 / 加跑档 Godot 门禁 {seen} 支：直接排 `_run` 起跑的都有兜底（_run_guarded 包装 / shot_gate 看门）"
          + (f"；`_run` 断气会空转到超时：{'、'.join(hang)}" if hang else ""))


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def cn(n):
    return CN[n] if n <= 10 else ("十" if n < 20 else CN[n // 10] + "十") + (CN[n % 10] if n % 10 else "")


def cn_num(s):
    """中文数 → 阿拉伯（与 cn() 同口径，只认 1–99；认不出返回 None）。README 道数句对账用。"""
    if len(s) == 1 and s in CN[1:]:
        return CN.index(s)
    m = re.fullmatch(r"([一二三四五六七八九]?)十([一二三四五六七八九]?)", s)
    if m:
        return (CN.index(m.group(1)) * 10 if m.group(1) else 10) + (CN.index(m.group(2)) if m.group(2) else 0)
    return None


def load_registry():
    p = subprocess.run([sys.executable, os.path.join(TOOLS, "gate_json.py"), "--list"], cwd=ROOT,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return json.loads(p.stdout.decode("utf-8"))


def code(s):
    return "`" + s + "`"


def render(reg):
    gates, shots = reg["gates"], reg["shot_probes"]
    live = [g for g in gates if g["tier"] != "no"]
    out = ["| # | 门禁 | 族 | 档 | 一键跑 | 本地命令 | `--json` | 判什么 | 绿长相 | 红长相 |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    for i, g in enumerate(live, 1):
        name = g["id"] + (f"（{len(shots)} 支，见下表）" if g["kind"] == "shots" else "")
        tier = {"must": "必跑", "step": "必跑·步骤（不判红绿）"}.get(g["tier"]) or "加跑：" + g["when"]
        out.append(f"| {i} | {name} | {g['family']} | {tier} | {yes(g['oneclick'])} | {code(g['cmd'])} | {code(g['json'])} "
                   f"| {g['judge']} | {g['green']} | {g['red']} |")
    must = [g for g in live if g["tier"] == "must"]
    py = [g for g in must if g["kind"] == "py"]
    other = [g["id"] for g in must if g["kind"] != "py"]
    steps = [(i, g["id"]) for i, g in enumerate(live, 1) if g["tier"] == "step"]
    extra = "、".join(str(i) for i, g in enumerate(live, 1) if g["tier"] == "lane")
    pre = "".join(f"先跑步骤 {i} {gid}（不判红绿），再跑" for i, gid in steps)
    out += ["", f"每轮必跑（`.claude/todo.md` 验证段）：{pre}「{cn(len(py))}道 Python + {'/'.join(other)}」{cn(len(must))}道门禁；"
                f"{extra} 按 lane 内容加跑（档列写了何时）。「一键跑」列 = §三「一键人读全跑」那段命令。"]
    subs = reg["subchecks"]
    num = {g["id"]: i for i, g in enumerate(live, 1)}
    out += ["", f"**门禁开关与附属自检**（{len(subs)} 项；不另立一道门禁，随所属门禁默认跑到的算进一键跑，"
                "要开关的手动开；CI 专属步骤见 §四）：", "",
            "| # | 项 | 所属门禁 | 族 | 一键跑 | 命令 | 期望输出 | 失败含义 |", "|---|---|---|---|---|---|---|---|"]
    for i, c in enumerate(subs, 1):
        cmd = code(c["cmd"]) + ("（或 " + code(c["alt"]) + "）" if c.get("alt") else "")
        out.append(f"| {i} | {c['id']} | {num.get(c['parent'], '?')}. {c['parent']}（lane {c['lane']}） | {c['family']} "
                   f"| {yes(c['oneclick'])} | {cmd} | {c['expect']} | {c['fail']} |")
    env = reg["shot_env"]
    out += ["", f"**截图门禁明细**（接 `tools/shot_gate.gd` 的全部 {len(shots)} 支；TAG / 张数 / 截图目录现读脚本源码。"
                "headless 只验契约：本地命令换 `--headless` 并加 `-- --contract`，`--json` 写 "
                "`godot --headless --quiet --path . -s res://tools/<探针>.gd -- --contract --json`）。"
                f"「截图目录」列是不设 `{env['var']}` 时的默认（根 `{env['default_root']}`，只在刷新共享证据图时用）；"
                f"**worktree / 自测推荐一律加前缀 `{env['recommended']}`**，全部探针改落 `<该目录>/<子目录>`、"
                "patrol 旁证落 `<该目录>/patrol`，默认目录不动"
                + "".join(f"；{u['what']}缺省 `{u['default']}` → `<该目录>/{u['sub']}`"
                          + (f"（`{u['flag']}` 仍优先）" if u["flag"] else "")
                          for u in env.get("users", []) if u["sub"] != "patrol")
                + "：", "",
            "| # | 探针 | 接入 | TAG | 张数 | 截图目录（默认） | 本地命令 | `--json` |",
            "|---|---|---|---|---|---|---|---|"]
    for i, s in enumerate(shots, 1):
        out.append(f"| {i} | {s['id']} | {s['lane']} | {code(str(s['tag']))} | {s['shots']} | {code(str(s['out_dir']))} "
                   f"| {code(s['cmd'])} | {code(s['json'])} |")
    out += ["", "**不算门禁**（别拿来判红绿；想跑照样可以，`--json` 也能用）：", "",
            "| 脚本 | 本地命令 | `--json` | 为什么不算 |", "|---|---|---|---|"]
    for g in gates:
        if g["tier"] == "no":
            out.append(f"| {code(g['file'])} | {code(g['cmd'])} | {code(g['json'])} | {g['why']} |")
    out.append("| 其余 `tools/qa_*_probe.gd` / `*_probe.gd` 专项探针（未接 shot_gate 的） | 见各脚本头注释 "
               "| — | 各 lane 的专项探针，只在对应 lane 里跑；要升格为门禁就进 `tools/gate_json.py` 注册表 |")
    return "\n".join(out)


def yes(b):
    return "✓" if b else "—"


def row_gates(reg, where, lines, want_lines):
    """§四 / §二 生成块逐行对账格（lane w33-k2，同型 clone w29-k5「SHOT 张数格」——张数字段只在 §一
    SHOT 表，§四 / §二 没有张数行可点名，clone 过来的是行格体本身）：旧整块格整段红一句
    「首处差异在第 k 行 / 逐字一致✗」不逐支点名，本格把块内每行与注册表供数逐字对，漂移逐支点名 id。
    判定规则：在册行（完整行文本 = 注册表行的某个渲染体位）与注册表逐字同，漂移即 ✗ 点名；
    零源行（``` 首尾 / 表头）只对字面；形状行（# 注释 / 命令 / 步骤表）若不在册，✗ 指其行位指认
    「从注册表可知行中照抄错 / 多贴」；意外注册表外多余行（应被整块格先行拦下）归入缺省段位。"""
    out = []
    if where == "§四":
        steps = reg["ci_steps"]
        titled = {f"# {i}. {c['id']}": (i, c) for i, c in enumerate(steps, 1)}
        body = {c["cmd"]: (i, c) for i, c in enumerate(steps, 1)}
        rowl = {f"| {i} | {c['id']} | {c['lane']} | {c['needs']} | {code(c['cmd'])} | {c['expect']} | {c['fail']} |": (i, c)
                for i, c in enumerate(steps, 1)}
        for l in lines:
            if l in titled or l in body or l in rowl or l in ("```sh", "```", "", "| # | 步骤 | 接入 | 需要 | 命令 | 期望输出 | 失败含义 |",
                                                              "|---|---|---|---|---|---|---|") or l.startswith("# 0."):
                continue  # 在册行与零源行：整块格与其在册渲染同源，逐字已由逐字一致守
            m = re.match(r"# (\d+)\. (.+)$", l)
            if m:
                out.append(f"§四「# {m.group(1)}. …」步骤注释行 {l[:100]!r} 不在 CI_STEPS 第 {m.group(1)} 项渲染里——手改 / 多贴（红因：行格点名 id {m.group(2)}）")
            elif l.startswith("|"):
                out.append(f"§四 步骤表行 {l[:100]!r} 不在 CI_STEPS 渲染里——手改 / 多贴（红因：行格点名首格）")
            elif l and l in want_lines:
                continue  # 第 0 步 oneclick[] 命令行：在注册表一键跑命令段里，出处整段、不逐行点名
            elif l:
                out.append(f"§四 块内多余行 {l[:100]!r}——不在 CI_STEPS 渲染也不在一键跑命令段（行格点名：无出处整行）")
        return out
    # §二
    rows = reg["oneclick_json"]
    rendered = {f"{r['json']} > {BATCH_DIR}/steps/{r['id']}.json" if r["tier"] == "step" else f"{r['json']} > {BATCH_DIR}/{r['id']}.json": r
                for r in rows}
    for l in lines:
        if l in rendered or l in ("```sh", "```", "") or l.startswith("# 必跑") or l.startswith("rm -rf ") or l == BATCH_SUM:
            continue
        out.append(f"§二 命令行 {l[:100]!r} 不在 oneclick_json 渲染里——手改 / 多贴（行格点名整行）")
    return out


def render_ci(reg):
    steps = reg["ci_steps"]
    out = ["```sh", f"# 0. 必跑{cn(len(reg['oneclick']))}条（含导入步骤；= §一「一键跑」✓ / §三「一键人读全跑」；无窗口的 CI 机器 patrol 要配 Xvfb 给 DISPLAY）"]
    out += reg["oneclick"]
    for i, c in enumerate(steps, 1):
        out += [f"# {i}. {c['id']}", c["cmd"]]
    out += ["```", "", "| # | 步骤 | 接入 | 需要 | 命令 | 期望输出 | 失败含义 |", "|---|---|---|---|---|---|---|"]
    for i, c in enumerate(steps, 1):
        out.append(f"| {i} | {c['id']} | {c['lane']} | {c['needs']} | {code(c['cmd'])} | {c['expect']} | {c['fail']} |")
    return "\n".join(out)


def render_batch(reg):
    """§二 批量巡检：一键跑各条换 §一 `--json` 列，stdout 落 /tmp/gates/<id>.json；导入步骤另放 steps/、不进汇总。"""
    rows = reg["oneclick_json"]
    out = ["```sh", f"# 必跑{cn(len(rows))}条的机读版（与 §四 第 0 步同序，每条换 §一 `--json` 列）；"
                    f"导入步骤不判红绿，落 {BATCH_DIR}/steps/、不进汇总",
           f"rm -rf {BATCH_DIR} && mkdir -p {BATCH_DIR}/steps"]
    for r in rows:
        dst = f"{BATCH_DIR}/steps/{r['id']}.json" if r["tier"] == "step" else f"{BATCH_DIR}/{r['id']}.json"
        out.append(f"{r['json']} > {dst}")
    out += [BATCH_SUM, "```"]
    return "\n".join(out)


def split_batch(text):
    """§二 批量巡检块：(块前, 块内, 块后)；标记不是恰好一对返回 None。"""
    if text.count(BATCH_BEGIN) == 1 and text.count(BATCH_END) == 1 and text.index(BATCH_BEGIN) < text.index(BATCH_END):
        a, b = text.index(BATCH_BEGIN) + len(BATCH_BEGIN), text.index(BATCH_END)
        return text[:a], text[a:b], text[b:]
    return None


def oneclick_block(text, head=r"^一键人读全跑[^\n]*\n+```sh\n"):
    """§三「一键人读全跑」下第一段 ```sh 的命令（续行拼回、按 && 与换行切、去行尾 `# 注释`）；找不到返回 None。
    head 换成 `## 验证` 即读 .claude/todo.md 验证段（那里的代码块不写 sh）。"""
    m = re.search(head + r"(.*?)^```", text, re.M | re.S)
    if not m:
        return None
    body = re.sub(r"\\\n\s*", " ", m.group(1))
    body = re.sub(r"(^|\s)#.*$", "", body, flags=re.M)
    return [c.strip() for ln in body.splitlines() for c in ln.split("&&") if c.strip()]


def check_oneclick(cmds, must, where, fix):
    diff = [c for c in cmds if c not in must] + [c for c in must if c not in cmds]
    return check(cmds == must, f"{where}命令与必跑档逐条一致（{len(must)} 条）"
                 + ("" if cmds == must else f"；不符：{diff or '顺序不同'}（{fix}）"))


def tools_gd():
    """tools/ 下 git 已跟踪的 .gd（与 compile 的 inventory 自检同口径：别的 lane 没提交的新脚本不染红共用树）；
    git 不可用时退回扫盘。"""
    try:
        p = subprocess.run(["git", "ls-files", "--", "tools"], cwd=ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, check=True)
        files = p.stdout.decode("utf-8").split("\n")
    except (OSError, subprocess.CalledProcessError):
        files = [os.path.relpath(os.path.join(d, f), ROOT) for d, _, fs in os.walk(TOOLS) for f in fs]
    return sorted(f for f in files if f.endswith(".gd") and os.path.isfile(os.path.join(ROOT, f)))


def split_doc(text):
    """返回 (块前, 块内, 块后)；没有标记时按「## 一、总表」到「## 二、」切（首次迁移用），都找不到返回 None。"""
    if text.count(BEGIN) == 1 and text.count(END) == 1 and text.index(BEGIN) < text.index(END):
        a, b = text.index(BEGIN) + len(BEGIN), text.index(END)
        return text[:a], text[a:b], text[b:]
    m = re.search(r"^## 一、总表\n", text, re.M)
    n = re.search(r"^## 二、", text, re.M)
    if m and n and m.end() < n.start():
        return text[:m.end()] + "\n" + BEGIN, None, END + "\n\n" + text[n.start():]
    return None


def split_ci(text):
    """§四 CI 块：(块前, 块内, 块后)；没有标记时在文末补「## 四、CI 建议步骤」一节（首次迁移用）。"""
    if text.count(CI_BEGIN) == 1 and text.count(CI_END) == 1 and text.index(CI_BEGIN) < text.index(CI_END):
        a, b = text.index(CI_BEGIN) + len(CI_BEGIN), text.index(CI_END)
        return text[:a], text[a:b], text[b:]
    if CI_BEGIN in text or CI_END in text:
        return None
    return (text.rstrip("\n") + "\n\n" + CI_HEAD + "\n\n" + CI_BEGIN, None, CI_END + "\n")


def main(argv):
    write = "--write" in argv
    print("一、注册表")
    try:
        reg = load_registry()
    except ValueError as e:
        check(False, f"tools/gate_json.py --list 不是 JSON：{e}")
        return report()
    gates, shots = reg["gates"], reg["shot_probes"]
    check(True, f"tools/gate_json.py --list：门禁 {len(gates)} 条、截图脚本 {len(shots)} 支")
    for g in gates:
        if g.get("file"):
            check(os.path.isfile(os.path.join(ROOT, g["file"])), f"{g['id']} → {g['file']} 存在")
        if g["tier"] == "lane":
            check(bool(g.get("when")), f"{g['id']} 是加跑档，写了何时跑（when）")
        if g["tier"] in ("no", "step"):
            check(bool(g.get("why")), f"{g['id']} 不算门禁，写了原因（why）")
        if g["tier"] == "no" or (g.get("file") or "").startswith("tools/legacy/"):
            # lane gd9：legacy 条目（p7_smoke 会挂死）gate_json 强制超时，人读命令也得带上限
            t = g.get("timeout")
            check(bool(t) and g["cmd"].startswith(f"timeout {t:g} "),
                  f"{g['id']} 是 legacy 条目，带强制超时（注册表 timeout={t}，本地命令以 `timeout {t}` 开头）")
        if g.get("marks"):
            # lane gd13：登记的输出契约字样（如 tour.sh 的 `TOUR PASS` / `TOUR FAIL`）还在脚本代码行里，注释里写了不算
            try:
                lines = open(os.path.join(ROOT, g["file"]), encoding="utf-8", errors="replace").read().splitlines()
            except OSError:
                lines = []
            src = "\n".join(ln for ln in lines if not ln.lstrip().startswith("#"))
            lost = [k for k in g["marks"] if k not in src]
            check(not lost, f"{g['id']} 的输出契约字样还在 {g['file']} 代码行里" + (f"；找不到：{lost}" if lost else ""))
    for s in shots:
        check(os.path.isfile(os.path.join(ROOT, s["file"])) and None not in (s["tag"], s["shots"], s["out_dir"]),
              f"截图脚本 {s['file']}：TAG={s['tag']} 张数={s['shots']} 目录={s['out_dir']}（源码读得到）")
    ids = {g["id"] for g in gates}
    for c in reg["subchecks"]:
        if not check(c["parent"] in ids and bool(c.get("file")), f"附属自检「{c['id']}」所属门禁 {c['parent']} 在注册表里且有脚本"):
            continue
        src = ""
        for f in [c["file"]] + c.get("also", []):  # also：判词由门禁 import 的共用件印的（lane auditfix6：拼回抽进 main_stitch）
            try:
                src += open(os.path.join(ROOT, f), encoding="utf-8", errors="replace").read()
            except OSError:
                pass
        lost = [k for k in c["marks"] if k not in src]
        where = " / ".join([c["file"]] + c.get("also", []))
        check(not lost, f"附属自检「{c['id']}」的开关 / 判词还在 {where} 里" + (f"；找不到：{lost}" if lost else ""))
    for c in reg["ci_steps"]:
        refs = re.findall(r"tools/[\w./-]+", c["cmd"])
        lost = [r for r in refs if not os.path.exists(os.path.join(ROOT, r))]
        check(not lost, f"CI 步骤「{c['id']}」引用的文件都在" + (f"；缺：{lost}" if lost else ""))
    # lane w33-k2：§四 步骤命令行的裸文本若被贴进第 0 步命令段（= oneclick[]），
    # 该行形与 CI_STEPS 命令行同字面、行格判会吃「无点名」假绿；敲定撞名即点名那条 CI 步骤。
    clash = [c["cmd"] for c in reg["ci_steps"] if c["cmd"] in set(reg["oneclick"])]
    check(not clash, "§四 步骤命令不与一键跑命令段撞名（撞名行格无法点名）" + (f"；撞：{clash}" if clash else ""))
    # lane w42-k2（拍板 E-15，走 A）：§一 json 栅单源化断言——升格为 `--native <id>` 形后禁回裸命令字；
    # `<id>` 反查注册表 id 一致（认不出名即写歪）。
    rows = list(gates) + list(shots)
    bare = [g["id"] for g in rows if "godot --quiet" in g["json"]]
    check(not bare, f"`--json` 栅零裸原生命令（lane gd7 / w42-k2：单源化走 `gate_json.py --native <id>`；{len(rows)} 格）"
                    + (f"；裸命令字：{bare}" if bare else ""))
    jid = {g["id"] for g in rows} | {"<探针>"}
    stray = [f"{g['id']}→{g['json']}" for g in rows
             for m in [re.search(r"--native (\S+)", g["json"])] if m and m.group(1) not in jid]
    check(not stray, f"`--native` 格的 <id> 都在注册表里（含 <探针> 占位；{len(rows)} 格）"
                     + (f"；认不出：{stray}" if stray else ""))
    # lane pg3：截图落盘根一律可由 NK1_SHOT_DIR 改，免得 worktree / 自测覆盖共享证据图
    env = reg.get("shot_env") or {}
    bad = [s["file"] for s in shots if not s.get("sub")]
    check(not bad, f"截图脚本目录都走 ShotGate.out_dir（{env.get('var')} 可改根）" + (f"；写死：{', '.join(bad)}" if bad else ""))
    root = env.get("default_root")
    hard = []
    for f in tools_gd():
        if f == "tools/shot_gate.gd" or not root:
            continue
        for i, ln in enumerate(open(os.path.join(ROOT, f), encoding="utf-8", errors="replace"), 1):
            if root in ln and not ln.lstrip().startswith("#"):
                hard.append(f"{f}:{i}")
    check(not hard, f"tools/ 已跟踪 .gd 代码里不写死默认截图根 {root}（只许 shot_gate.gd）" + (f"；写死：{', '.join(hard)}" if hard else ""))
    # lane pg4：探针以外的出图工具（patrol 旁证 / CutscenePreview --snap / tour.sh）也读 NK1_SHOT_DIR，且源码里还留着各自默认
    users = env.get("users") or []
    check(any(u["file"] == "tools/patrol_shell.gd" for u in users), "注册表 shot_env.users 登记了 patrol_shell.gd")
    for u in users:
        try:
            lines = open(os.path.join(ROOT, u["file"]), encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            lines = []
        src = "\n".join(ln for ln in lines if not ln.lstrip().startswith("#"))  # 只认代码行，注释里写了不算
        sh = u["file"].endswith(".sh")
        lost = [k for k in (env.get("var"), "/" + u["sub"] if sh else f'"{u["sub"]}"',
                            u["default"].replace("~/", "$HOME/") if sh else f'"{u["default"]}"') if k and k not in src]
        check(bool(env.get("var")) and not lost,
              f"{u['file']}（{u['what']}）读 {env.get('var')} → <根>/{u['sub']}，默认 {u['default']}"
              + (f"；源码里找不到：{lost}" if lost else ""))
    uses = re.compile(r'preload\(\s*"res://tools/shot_gate\.gd"\s*\)')
    code_of = {}
    for f in tools_gd():
        if f == "tools/shot_gate.gd":
            continue
        src = open(os.path.join(ROOT, f), encoding="utf-8", errors="replace").read()
        if uses.search(src):
            code_of[f] = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
    # lane gd18：只借 shot_gate 挂压帧、不用它收尾截图的定向探针（letterbox_signal / qa_yard）不算截图脚本、不入册
    users = [f for f, src in code_of.items() if "ShotGate.finish_shots(" in src]
    listed = {s["file"] for s in shots}
    missing, stale = sorted(set(users) - listed), sorted(listed - set(users))
    check(not missing, "接 shot_gate 收尾截图的脚本（git 已跟踪）都已入册"
          + (f"；未入册：{', '.join(missing)}" if missing else f"（{len(users)} 支）"))
    check(not stale, "入册的截图脚本都真接了 shot_gate 收尾" + (f"；没接：{', '.join(stale)}" if stale else ""))
    # lane gd18：「压帧下也绿」是全体有窗口探针的口径——接 shot_gate 的脚本开场都挂 ShotGate.frame_pressure（注释里写了不算）
    bare = sorted(f for f, src in code_of.items() if "ShotGate.frame_pressure(" not in src)
    check(not bare, f"接 shot_gate 的脚本都挂了压帧 ShotGate.frame_pressure（{len(code_of)} 支，NK1_PROBE_SLOW_MS 一个口径）"
          + (f"；漏挂：{', '.join(bare)}" if bare else ""))

    script_err_section(gates)
    run_abort_section(gates)
    print("二、docs/GATES.md")
    gen = render(reg)
    bad_cells = [l for l in (gen + "\n" + render_ci(reg)).splitlines() if l.startswith("|") and "\\|" in l]
    check(not bad_cells, "生成的表格单元里没有转义竖线")
    ragged, width = [], None  # 单元里的 `|`（哪怕在反引号里）GFM 照样切列：每行竖线数须与表头相同
    for l in (gen + "\n\n" + render_ci(reg)).splitlines():
        if not l.startswith("|"):
            width = None
        elif width is None:
            width = l.count("|")
        elif l.count("|") != width:
            ragged.append(l)
    check(not ragged, "生成的表格每行列数与表头一致（单元里没有裸 `|`）"
          + (f"；首行：{ragged[0][:120]}" if ragged else ""))
    with open(DOC, encoding="utf-8") as f:
        text = f.read()
    parts = split_doc(text)
    if not check(parts is not None, "GATES.md 有且只有一对生成标记（或能按「## 一、总表」定位）"):
        return report()
    head, body, tail = parts
    want = "\n" + gen + "\n"
    if write and body != want:
        text = head + want + tail
        with open(DOC, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"  已重写 {os.path.relpath(DOC, ROOT)} §一 标记块（{len(gen.splitlines())} 行）")
        head, body, tail = split_doc(text)
    ci_gen = render_ci(reg)
    ci_want = "\n" + ci_gen + "\n"
    ci_parts = split_ci(text)
    if write and ci_parts is not None and ci_parts[1] != ci_want:
        text = ci_parts[0] + ci_want + ci_parts[2]
        with open(DOC, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"  已重写 {os.path.relpath(DOC, ROOT)} §四 CI 标记块（{len(ci_gen.splitlines())} 行）")
        head, body, tail = split_doc(text)
        ci_parts = split_ci(text)
    batch_want = "\n" + render_batch(reg) + "\n"
    batch_parts = split_batch(text)
    if write and batch_parts is not None and batch_parts[1] != batch_want:
        text = batch_parts[0] + batch_want + batch_parts[2]
        with open(DOC, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"  已重写 {os.path.relpath(DOC, ROOT)} §二 批量巡检标记块（{len(batch_want.splitlines()) - 1} 行）")
        head, body, tail = split_doc(text)
        ci_parts = split_ci(text)
        batch_parts = split_batch(text)
    if body is None:
        check(False, "GATES.md 还没有生成标记块；跑 `python3 tools/gates_md.py --write`")
    else:
        same = body == want
        detail = ""
        if not same:
            have, gl = body.split("\n"), want.split("\n")
            k = next((i for i in range(max(len(have), len(gl))) if (have[i:i + 1] or [None]) != (gl[i:i + 1] or [None])), 0)
            detail = (f"；首处差异在块内第 {k} 行\n      文档：{(have[k:k + 1] or ['<无>'])[0][:160]}"
                      f"\n      注册表：{(gl[k:k + 1] or ['<无>'])[0][:160]}\n      修法：python3 tools/gates_md.py --write")
        check(same, "§一 标记块与注册表逐字一致" + detail)
    # lane w29-k5：SHOT 张数字段级对账——w26-k8 6a81f89 改注册表张数没 --write 时整块红只说「首处差异」，
    # 本格逐支点名那支探针的注册表张数 / 文档张数；与源码读数无关（源码↔注册表张数本就有①段格兜，此格不回读源码）
    shot_rows = {}
    for l in (body or "").splitlines():
        m = re.match(r"\| \d+ \| (\S+) \| \S+ \| `[^`]*` \| (\d+) \|", l)
        if m:
            shot_rows[m.group(1)] = m.group(2)
    drift = [s for s in shots if shot_rows.get(s["id"]) != str(s["shots"])]
    check(not drift, f"SHOT 张数 × {len(shots)}：注册表与 §一 SHOT 表逐条相符" + "".join(
        f"\n  ✗ SHOT 张数漂移：{s['id']} 注册表={s['shots']} 文档={shot_rows.get(s['id'], '无此行')}" for s in drift))
    ci_body = ci_parts[1] if ci_parts else None
    if not check(ci_parts is not None, "GATES.md 的 §四 CI 生成标记有且只有一对"):
        pass
    elif ci_body is None:
        check(False, "GATES.md 还没有 §四 CI 标记块；跑 `python3 tools/gates_md.py --write`")
    else:
        check(ci_body == ci_want, "§四 CI 标记块与 CI_STEPS 逐字一致" + ("" if ci_body == ci_want else "；修法：python3 tools/gates_md.py --write"))
        check(re.search(r"^" + re.escape(CI_HEAD) + r"\n", ci_parts[0], re.M) is not None, f"§四 CI 块在「{CI_HEAD}」小节里")
    if check(batch_parts is not None, "GATES.md 的 §二 批量巡检生成标记有且只有一对（缺了就在 §二 手补一对空标记再 --write）"):
        check(batch_parts[1] == batch_want, "§二 批量巡检标记块与 oneclick_json 逐字一致"
              + ("" if batch_parts[1] == batch_want else "；修法：python3 tools/gates_md.py --write"))
        check(re.search(r"^" + re.escape(BATCH_HEAD) + r"\n", batch_parts[0], re.M) is not None
              and CI_HEAD not in batch_parts[0] and re.search(r"^## 三、", batch_parts[0], re.M) is None,
              f"§二 批量巡检块在「{BATCH_HEAD}」小节里")
    # lane w33-k2：§四 / §二 生成块逐支行格——w30-k6 交主控 #2（审计-wave29 C1 系旁注 §85）载的
    # 「SHOT 张数格同型 clone」真缺即这两块整块红一句「首处差异在第 k 行 / 逐字一致✗」不能逐支点名。
    # 张数字段只出现在 §一 SHOT 表，§四 / §二 没有张数行可点名，clone 过来的是行格体本身：
    # 块内每行判定「∈ 注册表渲染 / ∈ oneclick 第 0 步命令段 / ∈ 零源行」之一；形状行（步骤注释 / 表行 /
    # 命令行）不与注册表渲染逐字同即行格逐支点名；在册行与零源行照旧由上面的整块格逐字一致兜。
    if ci_body is not None:
        off = row_gates(reg, "§四", ci_body.splitlines(), set(ci_want.split("\n")))
        check(not off, f"§四 CI 行格 × {len(ci_body.splitlines())}：块内每行 ∈（CI_STEPS 渲染 ∪ 一键跑命令段 ∪ 零源行）——红因修注册表或 --write" + "".join(
            f"\n  ✗ {x}" for x in off))
    if batch_parts is not None and batch_parts[1] is not None:
        off = row_gates(reg, "§二", batch_parts[1].splitlines(), set(batch_want.split("\n")))
        check(not off, f"§二 BATCH 行格 × {len(batch_parts[1].splitlines())}：块内每行 ∈（oneclick_json 渲染 ∪ 成型行 ∪ 零源行）" + "".join(
            f"\n  ✗ {x}" for x in off))
    ocb = oneclick_block(tail)
    must = reg["oneclick"]
    by_cmd = {g["cmd"]: g["id"] for g in gates}
    if check(ocb is not None, "§三 有「一键人读全跑」命令段"):
        check_oneclick(ocb, must, "§三 一键跑", "改 §三 手写段或注册表 tier")
        for p in oneclick_sweep(ocb, must, "§三 一键跑", by_cmd):  # lane w20-b3：把关判据（与逐条比对互补）
            check(False, p)
    try:
        with open(TODO, encoding="utf-8") as f:
            tcb = oneclick_block(f.read(), r"^## 验证[ \t]*\n+```[^\n]*\n")
    except OSError:
        tcb = None
    if check(tcb is not None, "`.claude/todo.md` 有「## 验证」命令段"):
        check_oneclick(tcb, must, "`.claude/todo.md` 验证段", "改 todo.md 验证段或注册表 tier")
        for p in oneclick_sweep(tcb, must, ".claude/todo.md 验证段", by_cmd):
            check(False, p)
    # lane w20-b3：README「一次改动闭环 = 下面 N 道门禁全绿」的道数与注册表一键跑条数对账；
    # README 的命令注释块（「十道 Python」「六道 Godot」）是讲解口径、不逐条比命令
    try:
        with open(os.path.join(ROOT, "README.md"), encoding="utf-8") as f:
            rm = re.search(r"一次改动闭环\s*=\s*下面([一二三四五六七八九十]+)道门禁全绿", f.read())
        rm_n = cn_num(rm.group(1)) if rm else None
    except OSError:
        rm_n = None
    check(rm_n is not None, "README「验证」段找得到「一次改动闭环 = 下面 N 道」道数句")
    if rm_n is not None:
        check(rm_n == len(must), f"README 道数（{rm.group(1)} = {rm_n}）与注册表一键跑条数（{len(must)}）相符"
              + ("" if rm_n == len(must) else "——「一键跑十六道」一阵子写成别的数，没人看得见（g8 W1 同类）"))
    # lane w49-k4：§一 尾句（每轮必跑本诺句，生成块块内、--write 会按注册表重排，但此前对它零断言——
    # 块外散文 §四 :635 系手拨格只有 prose 对账眼，同义高价值 §一尾句升格链漏一格零红）两断言：
    # (a) 「『N 道 Python + …』M 道门禁」形·M = 纯 must-tier 计数（lane w50-k1 拨正：旧竿 M = oneclick 条数含 step，
    # 与生成器 render() §一尾句 M 格 cn(len(must)) 照）必跑档（纯 must、不含 step 导入步骤格）同口径——
    # (b) lane 枚举行集合 = 注册表 lane 档位置集（doc 行号与注册表 live 序位、set-wise）——
    # 手工枚举 19…n 道中升格 n 次即 n 处手拨断电（w46-k1 / w48-k1 升格都滞一格零竿，w48-k1 起枚举个数错亦零竿）。
    ws = [l for l in (body or "").splitlines() if l.startswith("每轮必跑（")]
    check(len(ws) == 1, f"§一 块内找到唯一「每轮必跑…」尾句行（实得 {len(ws)} 条）")
    if ws:
        line = ws[0]
        live_rows = [g for g in gates if g["tier"] != "no"]
        lane_set = {str(i) for i, g in enumerate(live_rows, 1) if g["tier"] == "lane"}
        steps = [(i, g["id"]) for i, g in enumerate(live_rows, 1) if g["tier"] == "step"]
        ocount = sum(1 for g in reg["gates"] if g["tier"] == "must")  # 必跑档条数 = 纯 must（不含 step 导入步骤），与生成器 §一尾句 M 格同口径
        mc = re.match(r"^每轮必跑（`.claude/todo.md` 验证段）："
                      + "".join(f"先跑步骤 {i} {re.escape(g)}（不判红绿），再跑" for i, g in steps)
                      + "「([一二三四五六七八九十]+)道 Python \\+ ([^」]+)」([一二三四五六七八九十]+)道门禁；"
                      + "([0-9、]*) 按 lane 内容加跑（档列写了何时）。「一键跑」列 = §三「一键人读全跑」那段命令。$", line)
        check(bool(mc), "§一 尾句形状全对（「每轮必跑…『N 道 Python + 名单』M 道门禁；枚举 按 lane…」）"
              + ("" if mc else f"；实读行前 120 字节：{line[:120]!r}——形状变了（手改 / 段式漂移）"))
        if mc:
            no = cn_num(mc.group(3))
            check_part = "「" + mc.group(1) + "道 Python + " + mc.group(2) + "」形"
            check(no == ocount, f"§一尾句道数 {check_part} M 道门禁 M={mc.group(3)} vs 注册表必跑档条数={ocount}"
                  + ("" if no == ocount else "——升格链把本诺句滞一格零红（w48-k1 升格判据 1 M1 真实咬过，w49-k4 补竿）"))
            doc_set = set(filter(None, mc.group(4).split("、"))) if mc.group(4) else set()
            miss = sorted((lane_set - doc_set), key=int)
            extra_x = sorted((doc_set - lane_set), key=int)
            check(not miss and not extra_x,
                  f"§一尾句 lane 枚举 {len(doc_set)} 枚 = 注册表 lane 集 {len(lane_set)} 位"
                  + ("" if not miss and not extra_x else f"；缺格 {miss or '零'} 多格 {extra_x or '零'}"
                     f"——lane 枚举行手拨差（注册表 lane 集 {[int(x) for x in sorted(lane_set, key=int)]}），缺格道未随升格链手拨" ))
    # 把关判据自检（不落盘）：靶子（两支变异脚本的 LANDING_OFF 常量）漂了、判法放宽了当场红
    sweep_selfcheck()
    live = [g["id"] for g in gates if g["tier"] != "no"]
    heads = {int(m.group(1)): m.group(2) for m in re.finditer(r"^### (\d+)\. (.+)$", tail, re.M)}
    for i, gid in enumerate(live, 1):
        h = heads.get(i)
        check(h is not None and h.startswith(gid), f"§三 小节 `### {i}. {gid}` 对得上（文档：{h or '缺'}）")
    extra = sorted(set(heads) - set(range(1, len(live) + 1)))
    check(not extra, "§三 没有注册表之外的编号小节" + (f"：{extra}" if extra else ""))
    return report()


def report():
    print()
    print("结果：全部通过" if not fails else f"结果：{len(fails)} 项问题")
    for m in fails:
        print("   ✗ " + m.splitlines()[0])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
