#!/usr/bin/env python3
"""docs/GATES.md §一（门禁总表 / 门禁开关与附属自检 / 截图门禁明细 / 不算门禁）与 §四（CI 建议步骤）
按 tools/gate_json.py 的注册表生成，本脚本校验二者一致。

  python3 tools/gates_md.py            # 自检：文档与注册表不一致、注册的脚本缺失、接 shot_gate 的截图脚本没入册、
                                       #       附属自检的开关在源码里找不到、§三 一键跑命令与必跑清单不符 → 退 1
  python3 tools/gates_md.py --write    # 按注册表重写 GATES.md 两个标记块（块外手写部分不动），写完再自检
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
BEGIN = "<!-- GATES:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 注册表生成，勿手改 -->"
END = "<!-- GATES:END -->"
CI_BEGIN = "<!-- GATES-CI:BEGIN 本块由 `python3 tools/gates_md.py --write` 按 tools/gate_json.py 的 CI_STEPS 生成，勿手改 -->"
CI_END = "<!-- GATES-CI:END -->"
CI_HEAD = "## 四、CI 建议步骤"
CN = "零一二三四五六七八九十"

fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def cn(n):
    return CN[n] if n <= 10 else ("十" if n < 20 else CN[n // 10] + "十") + (CN[n % 10] if n % 10 else "")


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
    out += ["", f"**截图门禁明细**（接 `tools/shot_gate.gd` 的全部 {len(shots)} 支；TAG / 张数 / 截图目录现读脚本源码。"
                "headless 只验契约：本地命令换 `--headless` 并加 `-- --contract`，`--json` 写 "
                "`godot --headless --quiet --path . -s res://tools/<探针>.gd -- --contract --json`）：", "",
            "| # | 探针 | 接入 | TAG | 张数 | 截图目录 | 本地命令 | `--json` |",
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


def oneclick_block(text):
    """§三「一键人读全跑」下第一段 ```sh 的命令（续行拼回、按 && 与换行切）；找不到返回 None。"""
    m = re.search(r"^一键人读全跑[^\n]*\n+```sh\n(.*?)^```", text, re.M | re.S)
    if not m:
        return None
    body = re.sub(r"\\\n\s*", " ", m.group(1))
    return [c.strip() for ln in body.splitlines() for c in ln.split("&&") if c.strip() and not c.strip().startswith("#")]


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
    for s in shots:
        check(os.path.isfile(os.path.join(ROOT, s["file"])) and None not in (s["tag"], s["shots"], s["out_dir"]),
              f"截图脚本 {s['file']}：TAG={s['tag']} 张数={s['shots']} 目录={s['out_dir']}（源码读得到）")
    ids = {g["id"] for g in gates}
    for c in reg["subchecks"]:
        if not check(c["parent"] in ids and bool(c.get("file")), f"附属自检「{c['id']}」所属门禁 {c['parent']} 在注册表里且有脚本"):
            continue
        try:
            src = open(os.path.join(ROOT, c["file"]), encoding="utf-8", errors="replace").read()
        except OSError:
            src = ""
        lost = [k for k in c["marks"] if k not in src]
        check(not lost, f"附属自检「{c['id']}」的开关 / 判词还在 {c['file']} 里" + (f"；找不到：{lost}" if lost else ""))
    for c in reg["ci_steps"]:
        refs = re.findall(r"tools/[\w./-]+", c["cmd"])
        lost = [r for r in refs if not os.path.exists(os.path.join(ROOT, r))]
        check(not lost, f"CI 步骤「{c['id']}」引用的文件都在" + (f"；缺：{lost}" if lost else ""))
    uses = re.compile(r'preload\(\s*"res://tools/shot_gate\.gd"\s*\)')
    users = [f for f in tools_gd() if f != "tools/shot_gate.gd"
             and uses.search(open(os.path.join(ROOT, f), encoding="utf-8", errors="replace").read())]
    listed = {s["file"] for s in shots}
    missing, stale = sorted(set(users) - listed), sorted(listed - set(users))
    check(not missing, "接 shot_gate 的截图脚本（git 已跟踪）都已入册"
          + (f"；未入册：{', '.join(missing)}" if missing else f"（{len(users)} 支）"))
    check(not stale, "入册的截图脚本都真接了 shot_gate" + (f"；没接：{', '.join(stale)}" if stale else ""))

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
    ci_body = ci_parts[1] if ci_parts else None
    if not check(ci_parts is not None, "GATES.md 的 §四 CI 生成标记有且只有一对"):
        pass
    elif ci_body is None:
        check(False, "GATES.md 还没有 §四 CI 标记块；跑 `python3 tools/gates_md.py --write`")
    else:
        check(ci_body == ci_want, "§四 CI 标记块与 CI_STEPS 逐字一致" + ("" if ci_body == ci_want else "；修法：python3 tools/gates_md.py --write"))
        check(re.search(r"^" + re.escape(CI_HEAD) + r"\n", ci_parts[0], re.M) is not None, f"§四 CI 块在「{CI_HEAD}」小节里")
    ocb = oneclick_block(tail)
    must = reg["oneclick"]
    if check(ocb is not None, "§三 有「一键人读全跑」命令段"):
        diff = [c for c in ocb if c not in must] + [c for c in must if c not in ocb]
        check(ocb == must, f"§三 一键跑命令与必跑档逐条一致（{len(must)} 条）"
              + ("" if ocb == must else f"；不符：{diff or '顺序不同'}（改 §三 手写段或注册表 tier）"))
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
