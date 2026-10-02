#!/usr/bin/env python3
"""VERSION / SAVE_SCHEMA 结对门禁（lane w21-d18，纯 Python、只读）。

守 `scripts/core/SaveLoad.gd:14-15` 的口头契约——
    旧读档器认的头：旧版只拒 version > 3。结构兼容的改动只升 SAVE_SCHEMA，旧版仍能照读新档；
    哪天结构真的不兼容，两者同升，让旧版也拒。
c9 遗留④：「未来的 lane 若动 VERSION 需同步动 SAVE_SCHEMA」原先只是注释里的约定，
没有任何门禁守它；本片把它落成机械判据，三条配对判据各守一型：

  B1 头比旧读档器最后认识的还低：VERSION < 3（降头等于再版废档）
  B2 结构版升了、头没跟：SAVE_SCHEMA > VERSION
     （旧版游戏照样收下新结构档——正是 K3「v1 无 fleet 判好档、静默落缺省」那一型，c9 实测）
  B3 头升了、结构版没跟：VERSION > SAVE_SCHEMA
     （旧版拒读了，但这版游戏自己读不出新结构：迁移链缺级 / 检不到新键，坏档量产）

G「拒读守卫在迁移前置位」是配对关系的前提——守卫不在，三格全绿也护不住。
每次先跑「零、判据自检」（GATES §五.3）：内存变体（单独改 VERSION / 单独改 SAVE_SCHEMA /
拆掉守卫）走同一条 judge() 判路，须全判红；现行源码须全绿。

  python3 tools/check_save_version_contract.py          # 判据全绿 → 退 0
  python3 tools/check_save_version_contract.py --json   # 机读
"""
import os, re, sys
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAVELOAD = os.path.join(ROOT, "scripts", "core", "SaveLoad.gd")

BASE_VERSION = 3  # 旧读档器最后认识的存档头（旧版只拒 version > 3）

fails = []


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def facts(src):
    """从 SaveLoad.gd 源码抽出判据需要的全部事实。取不到的键给 None，judge 按红处理（fail closed）。"""
    out = {}
    mv = re.search(r"^const VERSION := (\d+)$", src, re.M)
    ms = re.search(r"^const SAVE_SCHEMA := (\d+)$", src, re.M)
    out["version"] = int(mv.group(1)) if mv else None
    out["schema"] = int(ms.group(1)) if ms else None
    out["has_reject"] = bool(re.search(r"if schema > SAVE_SCHEMA or ver > VERSION:", src))
    out["has_future"] = bool(re.search(r'return \{"status": "future"', src))
    out["has_migrate"] = bool(re.search(r"if schema < SAVE_SCHEMA:", src))
    block = ""
    m = re.search(r"^(const VERSION := \d+)$", src, re.M)
    if m:
        nxt = re.search(r"^(const \w+|func |static func )", src[m.end():], re.M)
        end = m.end() + nxt.start() if nxt else len(src)
        block = src[m.start():end]
    # 契约注释位于 const VERSION 之前：向上收一个连续的 ## 注释段
    head = src[:m.start()] if m else src
    cms = list(re.finditer(r"((?:^##.*\n)+)$", head, re.M))
    if cms:
        block = cms[-1].group(1) + block
    out["comment_ok"] = block and all(k in block for k in ("旧读档器认的头", "只升 SAVE_SCHEMA", "两者同升"))
    return out


def pair_problem(v, s):
    """VERSION / SAVE_SCHEMA 一对值的问题键；None = 绿。判据热：v / s 同时改档也报出第一条。"""
    if v is None or s is None:
        return "pair"
    if v < BASE_VERSION:
        return "B1"
    if s > v:
        return "B2"
    if v > s:
        return "B3"
    return None


def judge(f):  # noqa: F841  与 pair_problem 同一条路：变体自检与真判走同一函数族
    """单一判路：返回 (配对问题键 or None, 句式问题键 or None)。句式只判一次，不靠结对。"""
    pair = pair_problem(f["version"], f["schema"])
    guard = None if f["has_reject"] and f["has_future"] and f["has_migrate"] else "G"
    return pair, guard


def main(_argv):
    print("零、判据自检（变体须逐项判红，现行源码须全绿，规则表失效即 fail closed）")
    try:
        with open(SAVELOAD, encoding="utf-8") as fh:
            src = fh.read()
    except OSError as e:
        check(False, f"读不了 {os.path.relpath(SAVELOAD, ROOT)}：{e}")
        return report()
    f = facts(src)
    check(f["version"] is not None, "零、判据自检：认得出 const VERSION")
    check(f["schema"] is not None, "零、判据自检：认得出 const SAVE_SCHEMA")
    ref = max(BASE_VERSION, f["version"], f["schema"])
    v1, _g1 = judge(dict(f, version=ref + 1, schema=ref))
    v2, _g2 = judge(dict(f, version=ref, schema=ref + 1))
    v3, _g3 = judge(dict(f, version=ref + 1, schema=ref + 1))
    check(v1 == "B3", f"零、判据自检①：单独改 VERSION={ref + 1}（SAVE_SCHEMA 留 {ref}）须判红 B3")
    check(v2 == "B2", f"零、判据自检②：单独改 SAVE_SCHEMA={ref + 1}（VERSION 留 {ref}）须判红 B2")
    check(v3 is None, f"零、判据自检③：两者同升 VERSION=SAVE_SCHEMA={ref + 1} 须判绿")
    base_pair, base_guard = judge(f)
    check(base_pair is None and base_guard is None,  # a-priori：现行源码有红，正则十行一目见红不修自检
          f"零、判据自检：现行源码须全绿（VERSION={f['version']} / SAVE_SCHEMA={f['schema']}）——"
          "先修下面「一、结对」的红，别改自检判词")
    v0, _g0 = judge(dict(f, version=BASE_VERSION - 1))
    check(v0 == "B1", f"零、判据自检④：VERSION={BASE_VERSION - 1} 降头须判红 B1")
    _p5, g5 = judge(dict(f, has_reject=False))
    check(g5 == "G", "零、判据自检⑤：拆掉拒读守卫（has_reject=False）须判红 G")

    print("一、VERSION / SAVE_SCHEMA 结对")
    fix = {"B1": f"VERSION={f['version']} 比旧读档器最后认的头 {BASE_VERSION} 还小：降头等于再版废档，"
                 "与「旧版只拒 version > 3」一纸契约不符",
           "B2": f"结构版升了（SAVE_SCHEMA={f['schema']}）、头没跟（VERSION={f['version']}）："
                 "旧版游戏照样收下新结构档——K3「v1 无 fleet 判好档、静默落缺省」一型，"
                 "见 docs/存档迁移矩阵.md；结构不兼容的改动须两者同升",
           "B3": f"头升了（VERSION={f['version']}）、结构版没跟（SAVE_SCHEMA={f['schema']}）："
                 "旧版拒读了，本版游戏自己读不出新结构（迁移链缺级 / 检不到新键）"}
    for key in ("B1", "B2", "B3"):
        ok = base_pair != key
        check(ok, f"配对：不出现 {key}（VERSION={f['version']} / SAVE_SCHEMA={f['schema']}）"
                  + ("" if ok else f"——{fix[key]}"))
    check(base_guard is None, "拒读守卫在迁移前置位：源里有 `if schema > SAVE_SCHEMA or ver > VERSION:`、"
                              "`return {\"status\": \"future\"`、`if schema < SAVE_SCHEMA:`"
          + ("" if base_guard is None else "——守卫拆掉了，三格全绿也护不住结对关系"))
    check(bool(f["comment_ok"]), "契约注释三字样（`旧读档器认的头` / `只升 SAVE_SCHEMA` / `两者同升`）都在"
                                 "VERSION / SAVE_SCHEMA 声明块里——改契约就改那份注释，注释与判据同生共死")
    return report()


def report():
    print()
    print("结果：全部通过" if not fails else f"结果：{len(fails)} 项问题")
    for m in fails:
        print("   ✗ " + m.splitlines()[0])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
