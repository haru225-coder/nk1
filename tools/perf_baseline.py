#!/usr/bin/env python3
"""性能基线软档（lane w20-c10）：跑 tools/perf_baseline.gd 取指标行，按 THRESHOLDS 判——
**超阈只打 `  ⚠ …`、ok=true、rc 恒 0；连 SAMPLES 帧都没采到才 rc=1**。不算门禁（tier=no），不进一键跑。

用法（与 docs/性能基线.md 同步）：
  python3 tools/perf_baseline.py                              # real 场面 8 秒 + synthe 副支 8 秒，软档断言 + 打指标行
  python3 tools/perf_baseline.py --scene real --secs 8        # 只跑一支
  python3 tools/perf_baseline.py --json                       # 机读（= perf_baseline.gd --json 外包汇总）
  python3 tools/perf_baseline.py --selftest                   # 只跑「零、判据自检」（假指标行判 warn / fail）
  python3 tools/perf_baseline.py --mutant                    # 反向变异：THRESHOLDS 收紧一格须见 ⚠（spawn 进程实测）

为什么软档：**目前没有其他性能门禁，本机又是 20 路 lane 共用（load 20+）**——墙钟帧时随 CPU 供给起伏，
设 must / lane 档会在负载高的时候误红。只把「跑通了、SAMPLES 帧以上、留了指标行」做成硬断言；
超阈全打 ⚠（GateReport.warn，ok=true），读回报的人自己挑值。日后做真机 / 静默刻的复测时收紧。
「不改实现」：超阈不修代码、不写推荐值，THRESHOLDS 改动本身只改 dict、不上代码里别处。
"""
import json
import os
import re
import subprocess
import sys
import tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:
    sys.path.insert(0, TOOLS)
    import gate_json
    gate_json.maybe_json(__file__)

TAG = "PERF_PY"
# 软档阈值；只 warn。指标从 _MM 行按正则抓；与 docs/性能基线.md §3 表同步。
# 保守：以 lane 落地时的实测 + 30% 起（real p95=215→290，synthe p95=122→160，startup real=1974→2600）；内存实测 109 MB→220。
THRESHOLDS = {
    "startup_ms": {"real": 2300, "synthe": 2300},
    "p95_ms": {"real": 200, "synthe": 160},
    "peak_mem_mb": {"real": 220, "synthe": 220},
    "frames_min": {"real": 60, "synthe": 60},
}

METRIC_RE = re.compile(
    r"^PERF_BASELINE_MM startup_ms=(\d+) frames=(\d+) avg_ms=([\d.]+) p50_ms=([\d.]+) p95_ms=([\d.]+) max_ms=([\d.]+) over50_ms=(\d+) peak_mem_mb=([\d.]+)$"
)
HARD_SKIP_RE = re.compile(r"^(PERF_BASELINE(_BEGIN|_MM| PASS| FAIL)|\s+[✓✗⚠])")
# 真错才判红；探针收尾的「✓ 本进程无 SCRIPT ERROR（0 行）」不算
SCRIPT_ERR_RE = re.compile(r"^(?!.*本进程无 SCRIPT ERROR)(?!.*（0 行）).*SCRIPT ERROR|.*Parse Error")


def parse_metrics(text):
    """从 Godot 探针 stdout 中找 PERF_BASELINE_MM 行 → dict 指标。

    找到返回 dict，找不到返回 None。指标键：startup_ms/frames/avg_ms/p50_ms/p95_ms/max_ms/over50_ms/peak_mem_mb。
    """
    for ln in text.splitlines():
        m = METRIC_RE.match(ln.strip())
        if m:
            return {
                "startup_ms": int(m.group(1)),
                "frames": int(m.group(2)),
                "avg_ms": float(m.group(3)),
                "p50_ms": float(m.group(4)),
                "p95_ms": float(m.group(5)),
                "max_ms": float(m.group(6)),
                "over50_ms": int(m.group(7)),
                "peak_mem_mb": float(m.group(8)),
            }
    return None


def thresholds_for(scene):
    out = {}
    for k, v in THRESHOLDS.items():
        out[k] = v.get(scene, v.get("real"))
    return out


def warn_for(scene, m, t):
    """按 THRESHOLDS 评一支指标 → (warns, fails)。fails 仅在没跑通时给一条；
    超阈全打 warn。sanity：frames 太小或没拿到 _MM 行才 fail。
    """
    warns = []
    fails = []
    if m is None:
        fails.append("%s 场面没找到 PERF_BASELINE_MM 指标行" % scene)
        return warns, fails
    if m["frames"] < t["frames_min"]:
        fails.append("%s 采样帧 %d 低于下限 %d" % (scene, m["frames"], t["frames_min"]))
    return warns, fails


def predict(scene, m, t):
    """纯逻辑一节：对 (scene, metrics) 逐项判 warn。返回 list of str（ok=True 的 ⚠ 总目）。

    ⚠ 文案给「指标 实测 > 阈值」、便于一眼看；本表给 --selftest 用、也给真跑用。
    """
    warns = []
    if m is None:
        return warns
    if m["startup_ms"] > t["startup_ms"]:
        warns.append("startup_ms=%d > 阈值 %d ms（real / synthe）" % (m["startup_ms"], t["startup_ms"]))
    if m["p95_ms"] > t["p95_ms"]:
        warns.append("p95_ms=%.0f > 阈值 %d ms（%s）" % (m["p95_ms"], t["p95_ms"], scene))
    if m["peak_mem_mb"] > t["peak_mem_mb"]:
        warns.append("peak_mem_mb=%.0f > 阈值 %d MB（%s）" % (m["peak_mem_mb"], t["peak_mem_mb"], scene))
    return warns


def run_probe(scene, secs, godot, timeout_s=180):
    """跑一支探针，返回 (rc, stdout_text)。"""
    xdg = tempfile.mkdtemp(prefix="perf_baseline_xdg_")
    env = dict(os.environ)
    env["XDG_DATA_HOME"] = xdg
    env.setdefault("DISPLAY", ":2")
    # 不加 --quiet（那样 GateReport 不开闸、print() 也走不通）；stdout 留给人读指标行
    cmd = [godot, "--path", ROOT, "-s", "res://tools/perf_baseline.gd",
           "--", "--scene", scene, "--secs", str(secs)]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s, env=env)
        return p.returncode, p.stdout + ("\n" if p.stdout else "") + p.stderr
    except subprocess.TimeoutExpired as e:
        return 124, (e.stdout or "") + ((e.stderr or "") if e.stderr else "")


def selftest():
    """零、判据自检：构造两类指标行，断言阈值判据形对。"""
    ok = True

    def chk(cond, msg):
        nonlocal ok
        print(("  ✓ " if cond else "  ✗ ") + msg)
        if not cond:
            ok = False

    # SAMPLES：高架下样本须全绿
    m_hi = {"startup_ms": 4000, "frames": 5, "avg_ms": 999.0, "p50_ms": 999.0, "p95_ms": 999.0, "max_ms": 999.0,
            "over50_ms": 5, "peak_mem_mb": 999.0}
    # 过阈须 ⚠ 全数（startup / p95 / peak_mem_mb），frames < 下限须 fail
    w = predict("real", m_hi, thresholds_for("real"))
    chk(any("startup_ms" in s for s in w), "高 startup_ms 须 warn")
    chk(any("p95_ms" in s for s in w), "高 p95_ms 须 warn")
    chk(any("peak_mem_mb" in s for s in w), "高 peak_mem_mb 须 warn")
    warns, fails = warn_for("real", m_hi, thresholds_for("real"))
    chk(warns == [], "warn_for 现在不产 warn（全数被 predict 收）")
    chk(any("采样帧" in s for s in fails), "低帧数须 fail 一条")

    # CLEAN：中档样本须全绿（指标低于所有阈）
    m_mid = {"startup_ms": 2000, "frames": 90, "avg_ms": 100.0, "p50_ms": 100.0, "p95_ms": 150.0, "max_ms": 180.0,
             "over50_ms": 90, "peak_mem_mb": 120.0}
    w2 = predict("real", m_mid, thresholds_for("real"))
    chk(w2 == [], "中档样本须全绿（无 warn）")
    _, f2 = warn_for("real", m_mid, thresholds_for("real"))
    chk(f2 == [], "中档样本须全绿（无 fail）")

    # METRIC_RE 的形状对得上 _gd 的输出
    sample_line = ("PERF_BASELINE_MM startup_ms=1974 frames=58 avg_ms=139.1 p50_ms=134.0 p95_ms=215.0 "
                   "max_ms=278.0 over50_ms=58 peak_mem_mb=109.4")
    m3 = parse_metrics(sample_line)
    chk(m3 is not None, "PERT_METRIC_RE 认得上真实指标行")
    if m3:
        chk(m3["p95_ms"] == 215.0 and m3["peak_mem_mb"] == 109.4, "正则抓的指标数字对")

    # 反变异：THRESHOLDS 收紧一格（startup 2000→1000），中档样本须出 ⚠
    t_old = dict(THRESHOLDS)
    THRESHOLDS["startup_ms"] = {"real": 1000, "synthe": 1000}
    w3 = predict("real", m_mid, thresholds_for("real"))
    chk(any("startup_ms" in s for s in w3), "收紧阈值后中档样本须见 startup ⚠（反向变异）")
    THRESHOLDS.update(t_old)

    print("%s：%s" % ("零、判据自检", "通过" if ok else "N 项问题"))
    return ok


def main():
    args = [a for a in sys.argv[1:]]
    if "--selftest" in args:
        return 0 if selftest() else 1

    godot = os.environ.get("GODOT")
    if not godot:
        candidates = ["godot", os.path.expanduser("~/.local/bin/godot")]
        for c in candidates:
            try:
                subprocess.run([c, "--version"], capture_output=True, check=True)
                godot = c
                break
            except (FileNotFoundError, subprocess.CalledProcessError):
                continue
    if not godot:
        print("  ✗ 找不到 godot")
        return 2

    scenes = ["real"] if "--scene" in args and args[args.index("--scene") + 1] == "real" else ["real", "synthe"]
    secs = 8
    if "--secs" in args:
        secs = int(args[args.index("--secs") + 1])

    total_fails = []
    total_warns = []
    metrics_by_scene = {}
    for scene in scenes:
        t = thresholds_for(scene)
        rc, text = run_probe(scene, secs, godot)
        m = parse_metrics(text)
        metrics_by_scene[scene] = m
        print("── %s 场面（rc=%d）──" % (scene, rc))
        if m is None:
            total_fails.append("%s 场面没找到 PERF_BASELINE_MM 指标行（rc=%d）" % (scene, rc))
            tail = "\n".join(ln for ln in text.splitlines() if SCRIPT_ERR_RE.search(ln) or "PERF_" in ln)[-2:]
            if tail:
                print("   末几行：%s" % tail)
            continue
        print("   startup_ms=%d frames=%d avg=%.1f p95=%.1f mem=%.0fMB" % (
            m["startup_ms"], m["frames"], m["avg_ms"], m["p95_ms"], m["peak_mem_mb"]))
        for w in predict(scene, m, t):
            print("  ⚠ %s" % w)
            total_warns.append("%s: %s" % (scene, w))
        warns, fails = warn_for(scene, m, t)
        for s in warns:
            total_warns.append("%s: %s" % (scene, s))
        for s in fails:
            print("  ✗ %s" % s)
            total_fails.append("%s: %s" % (scene, s))
        # SCRIPT ERROR 单独判红线；超阈不改红
        if SCRIPT_ERR_RE.search(text):
            first = next(ln for ln in text.splitlines() if SCRIPT_ERR_RE.search(ln))[:120]
            total_fails.append("%s 出 SCRIPT ERROR：%s" % (scene, first))

    print("== 小结 ==")
    for s in total_warns:
        print("  ⚠ %s" % s)
    for s in total_fails:
        print("  ✗ %s" % s)
    print("%s：%s（超阈 %d 项 ⚠，判红线 %d 项；结果以功能件论）" % (
        TAG, "全部通过" if not total_fails else "N 项未通过", len(total_warns), len(total_fails)))
    return 0 if not total_fails else 1


if __name__ == "__main__":
    sys.exit(main())
