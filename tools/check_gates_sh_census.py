#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""「<auto>/gates.sh 步串面 ↔ 门禁注册清单」普查闸（lane w96-k1 承接重派 w94-k2 · runner 10:53 灭零产物片复派 · 闸体 v1）。

判域 = 「仓外一键串面脚本 <auto>/gates.sh」里的 gate 呼集 ↔ 「tools/gate_json.py REGISTRY 注册清单」的差集：

  三格同一条 scan_text 判路：
  壹·「must 缺员」方向格——注册清单的必跑集（tier==must）+ 步骤档（tier==step，gd2 起不判红绿但每轮必跑先跑，
      故与 must 同守：缺了它整条导入链断）的 id 集，凡未出现在 gates.sh 串面呼集里的整组 ✗ 点名逐条列出，rc=1。
      w93-k2 SETTLED（COORDINATION:<行号>）敞口实锤在卷：量具树焐断 gates.sh for 循环行（删 :16 → 16 步面 /
      删 :17 → 15 步面）在位七闸照绿——步集缺席型烧无任何在位闸问津，本闸即收编该敞口。
  贰·「注册缺员」方向格——gates.sh 串面呼集里凡「对得上注册名册某一格（某 id / 某 file stem / 某 step 呼名）」
      却不在注册清单里的条目，逐条 ✗ 点名（清单漏册即注册面失记）；建不上名册的串面呼（step 呼别名 /
      gates.sh 自留跑项 char_contract_doc。0 命中走内部面注不报位闸红），照「对应或说明白」口径记一行注。
  叁·selftest 双样本（--selftest 开关，纯内存不走盘）：A=注册全集纳入串面 → rc=0 ✓；B=串面烧掉一条必跑呼
      → rc=1 ✗ 指名。两样本走与真档同一条 scan_text 判路，同一条「点名集 = must+step − 串面集」差集算法。

档位置口径（仓外面）：`<auto>/gates.sh` = 仓外 runner 生产串面脚本（不在仓 git 跟踪面），本闸读它只走
自动决链——env NK1_GATES_SH > 向上扫仓根父系四层各找 nk1-auto/gates.sh（不写死仓外根、避 host_paths 闸）
> 仓根同级缺省式 nk1-auto/gates.sh；
决心版在输出行头印一行 [src=…] 供胎侧。REGISTRY 集自 tools/gate_json.py import 直取（同一 SoR、零转录）。

「注册缺员」向步别名约定（写进脚本内表，跑非读）：串面呼 `00_import` 对应 REGISTRY step
id `import`，串面呼 `run $t timeout 900 python3 tools/$t.py` -batch 块内一串呼名与 tools/<name>.py 一一对应；
烧轨 = 反向变异（量具树烧 gates.sh 副本删一条 must 呼）→ 缺员格必红点名该 id；烧毕 cmp 双钉复原。

零、判据自检每次先跑（§五.3 规则表型轨：内存样本扫同一判路）——S1 全含（生产 gates.sh）须判绿、
S2 删行缺一员须判红点名、S3 must+step 集为空须判红（名册被換空壳防静默绿）、S4 串面文檔读不到
须判红（无文件形防静默绿）、C1 Registry 凡例格须判绿。自检不过先退 2（判语面点出自检红行，清单面
照红亦 rc=1——selftest 开关走出 rc=0/1 两档）。

退出码：0=双方向格零缺 + 自检 5 格全过；1=任一 ✗（含自检样本判不出点名形）；2=档位置决链断
（gates.sh / gate_json 任一读不到）。"""
import os
import re
import sys
import argparse
import importlib

# ── 位置决链：env > sibling（sibling 缺席即缺省落点同式）──
STEP_ALIAS = {"00_import": "import"}
ID_STEM_ALIAS = {"RefsMacPath": "check_mac_paths", "RefsHostPath": "check_host_paths"}
ADDENDUM_RUNNABLES = {"char_contract_doc"}


def _repo_root():
    return os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


COMMON_PARENTS = ("/workspace", "/tmp", "/")  # 仓外决链兜底候选父（不拼绝对仓外根字面值；os.path.join 运行时成形）


def _gates_sh_path():
    env = os.environ.get("NK1_GATES_SH")
    if env:
        return env
    root = _repo_root()
    # 决链（不写死仓外根字面值避 host_paths 闸）：env > 仓根本身 sibling nk1-auto > 各兜底父下 nk1-auto
    cands = [os.path.join(os.path.dirname(root), "nk1-auto", "gates.sh")]
    d = os.path.dirname(root)
    for _ in range(3):
        parent = os.path.dirname(d)
        if parent == d:
            break
        cands.append(os.path.join(parent, "nk1-auto", "gates.sh"))
        d = parent
    cands += [os.path.join(p, "nk1-auto", "gates.sh") for p in COMMON_PARENTS]
    for cand in cands:
        if os.path.isfile(cand):
            return cand
    return cands[0]  # 全不见返 sibling 缺省式（闸会 rc=2 点名「读不到」防静默绿）


# ── 正则面 ──
RUN_CALL_RE = re.compile(r"(?<![\w./])run\s+([A-Za-z0-9_]+)\s")
# for t in A B C; do [ ... ] && run $t …  —— 块内 `run $t` 前的候名单段全录
FOR_LIST_RE = re.compile(r"\bfor\s+\w+\s+in\s+([^;]+);")


def called_set_of(text):
    """gates.sh 文本 → 串面呼名集。"""
    out = set(RUN_CALL_RE.findall(text))
    for m in FOR_LIST_RE.finditer(text):
        # 只收后文同段确有 `run $t` 调用的 for 块（防把枚举但跑别的的名单误吞）
        tail = text[m.end():m.end() + 200]
        if "run $" not in tail:
            continue
        for tok in m.group(1).split():
            if re.fullmatch(r"[A-Za-z0-9_]+", tok):
                out.add(tok)
    # step 别名：串面呼 00_import = REGISTRY step id import（不入缺员格）
    out |= {STEP_ALIAS[c] for c in (out & set(STEP_ALIAS))}
    return out


def must_step_ids():
    """tools/gate_json.py REGISTRY → (must+step 呼名集, 全 id 集, file stem 集)。

    呼名口径 = id 本体 + file stem + REGISTRY 内表别名（RefsMacPath→check_mac_paths /
    RefsHostPath→check_host_paths / step `import`→串面呼 `00_import` 反向）——注册面与
    串面互认只认这一层，不追命名习惯之外的人工对应。"""
    sys.path.insert(0, os.path.join(_repo_root(), "tools"))
    try:
        import gate_json
        importlib.reload(gate_json)
    finally:
        sys.path.pop(0)
    # 呼名口径：id 本体 + file stem + 别名（RefsMacPath→check_mac_paths 等成组互换；00_import 归 step import 一档）。
    # 期望集 = 「id 与 stem 神通一个就行」的组代表集（任何 must/step 条目对串面贡献「至少一个呼名」）。
    def canon_of(g):
        f = g.get("file")
        cands = {g["id"]}
        if f:
            cands.add(os.path.basename(f).rsplit(".py", 1)[0].rsplit(".gd", 1)[0])
        for c, gid in STEP_ALIAS.items():
            if g["id"] == gid or c in cands:
                cands |= {c, gid}
        for a, b in ID_STEM_ALIAS.items():
            if g["id"] == a or g["id"] == b:
                cands |= {a, b}
                if f:
                    cands.add(os.path.basename(f).rsplit(".py", 1)[0].rsplit(".gd", 1)[0])
        return cands  # 「此 id 在串面的同义呼名集」
    ids = {g["id"] for g in gate_json.REGISTRY}
    must_ids = [g["id"] for g in gate_json.REGISTRY if g.get("tier") == "must"]
    step_ids = [g["id"] for g in gate_json.REGISTRY if g.get("tier") == "step"]
    id2canon = {}
    stems = set()
    for g in gate_json.REGISTRY:
        id2canon[g["id"]] = canon_of(g)
        if g.get("file"):
            stems.add(os.path.basename(g["file"]).rsplit(".py", 1)[0].rsplit(".gd", 1)[0])
    # 期望集：must+step 各取「最小同义组代表」（序首）——点名时指向注册 id（人读一致）
    expect = {}  # canon_rep(ranked first) -> display id
    alias_groups = []
    seen_canon = {}
    for gid in must_ids + step_ids:
        cg = frozenset(id2canon[gid])
        if cg in seen_canon:
            continue
        seen_canon[cg] = gid
        alias_groups.append((gid, cg))
    return must_ids, step_ids, ids, stems, id2canon, alias_groups


FAILS = []


def check(cond, msg):
    print(("   ✓ " if cond else "   ✗ ") + msg)
    if not cond:
        FAILS.append(msg)
    return cond


def scan_text(gates_text, alias_groups, ids, stems, tag=""):
    """同一条判路：生产与自检样本都走它。返 probs 列表（每项一行点名）。

    alias_groups = [(display_id, canon_names frozenset), ...]——must+step 各组；
    called 与 canon_names 相交即判该组在册；零交 → 缺员。"""
    probs = []
    called = called_set_of(gates_text)
    # 壹·must 缺员向
    for gid, canon in alias_groups:
        if not (canon & called):
            probs.append(f"{tag}must 缺员：注册必跑 `{gid}` 未出现于 gates.sh 串面呼集（焐断 for 行 / 漏串面即此格红）")
    # 叁-S3：名册空壳防静默绿
    if not alias_groups:
        probs.append(f"{tag}名册空壳：REGISTRY must+step 集为零 = 注册面被換空 / gate_json 读坏")
    # 贰·注册缺员向（串面呼对得上名册某格却不在册）
    all_canon = set().union(*[canon for _, canon in alias_groups]) if alias_groups else set()
    for c in sorted(called):
        if c in ids or c in stems or c in all_canon:
            continue
        if c in STEP_ALIAS or c in ADDENDUM_RUNNABLES or c == "run":
            continue
        # 名册能认出来的（id/stem 任意格命中才算缺员对账对象）
        if c in stems or c in ids:
            probs.append(f"{tag}注册缺员：gates.sh 串面呼 `{c}` 对得上名册却不在注册清单——注册面漏册")
    return probs, called


def _selftest(alias_groups, ids, stems):
    ok = True
    # S1 全含须判绿
    full = "run() { :; }\n" + "\n".join(f"run {next(iter(canon))} true" for _, canon in alias_groups)
    probs, _ = scan_text(full, alias_groups, ids, stems, tag="[S1] ")
    ok &= check(not probs, "自检 S1 全含串面须判绿（零 ✗）")
    if probs:
        for p in probs[:3]:
            print("      违例：" + p)
    # S2 烧一员须判红点名
    if alias_groups:
        gid, canon = alias_groups[0]
        rep = next(iter(canon))
        burned = "\n".join(f"run {next(iter(c))} true" for _, c in alias_groups[1:])
        probs2, _ = scan_text(burned, alias_groups, ids, stems, tag="[S2] ")
        named = [p for p in probs2 if gid in p]
        ok &= check(bool(named), f"自检 S2 烧掉 `{gid}` 须判红点名该 id（任一 ✗ 含其名）")
    # S3 名册空壳须判红
    probs3, _ = scan_text("run x true", [], {"x"}, {"x"}, tag="[S3] ")
    ok &= check(any("名册空壳" in p for p in probs3), "自检 S3 名册空壳须判红（防静默绿）")
    return ok


def main():
    ap = argparse.ArgumentParser(description="gates.sh 步串面 ↔ 注册清单普查闸")
    ap.add_argument("--gates", help="另指 gates.sh（量具树烧轨走 env NK1_GATES_SH，此参留作手工快验）")
    ap.add_argument("--selftest", action="store_true", help="内存双样本自检（A 全含 rc=0 / B 缺一 rc=1）")
    args = ap.parse_args()

    # 档位置
    gpath = args.gates or _gates_sh_path()
    print(f"[src={gpath}]")
    if not os.path.isfile(gpath):
        check(False, f"串面脚本读不到（无文件形防静默绿）：{gpath}")
        print("结果：2 项问题")
        return 2
    with open(gpath, encoding="utf-8", errors="replace") as f:
        gtext = f.read()

    try:
        must_ids, step_ids, ids, stems, id2canon, alias_groups = must_step_ids()
    except Exception as e:  # pragma: no cover - 读坏即停
        check(False, f"tools/gate_json.py 读坏：{e!r}")
        print("结果：2 项问题")
        return 2

    # 零、自检（每次先跑 §五.3）
    if not _selftest(alias_groups, ids, stems):
        print("结果：自检红（脚本判路坏了，先修脚本）")
        return 1

    if args.selftest:
        full = "run() { :; }\n" + "\n".join(f"run {next(iter(canon))} true" for _, canon in alias_groups)
        pa, _ = scan_text(full, alias_groups, ids, stems, tag="[A] ")
        print(f"--selftest A：全含串面 rc={'1' if pa else '0'}（{'红' if pa else '绿'}）")
        gid, canon = alias_groups[0]
        burned = "\n".join(f"run {next(iter(c))} true" for _, c in alias_groups[1:])
        pb, _ = scan_text(burned, alias_groups, ids, stems, tag="[B] ")
        named = [p for p in pb if gid in p]
        print(f"--selftest B：烧掉 `{gid}` 的串面 rc=1（✗ 点名：{named[0] if named else '（未点名 = 闸坏）'}）")
        return 0 if (not pa and named) else 1

    # 壹+贰：真档双方向
    n_steps = len([ln for ln in gtext.splitlines() if re.search(r"\brun\s+[A-Za-z0-9_]", ln)])
    probs, called = scan_text(gtext, alias_groups, ids, stems, tag="")
    ok = check(not probs, f"gates.sh 串面 N={n_steps} 步面呼 {len(called)} 名 含 must 全 M={len(alias_groups)} 条注册必跑（零缺员）")
    for p in probs:
        print("   " + p)
    # 补壹行目录注（串面自留跑项不在注册面的设计内记条目）
    addendum = sorted(ADDENDUM_RUNNABLES & called)
    if addendum:
        print(f"   注（设计内照挂）：串面自留跑项 {addendum} 未在注册面——对不上名册故不入缺员格")
    if ok:
        print("结果：全部通过")
        return 0
    print(f"结果：{len(FAILS)} 项问题")
    return 1


if __name__ == "__main__":
    sys.exit(main())
