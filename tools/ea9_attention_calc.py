#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EA9-1 机械前置复算（主控 wave24 拍定入库，原 lane w23-a6 仓外 calc.py 同口径改写入库）。

逐港逐月算「无引出港线 N = 50 / war_mul」映射表，供 docs/关注映射表_2026-10-03.md 对账。

口径照 brief 与代码实读（行号随码漂移属正常，语义不变即可对账）：
- war 表：data/ports.json 每港 war: {"YYYY-MM": status}，取 ≤ 当月的最新一条
  （scripts/core/Economy.gd `war_status`，入库基 d1a9504 时在 :251-263）。
- 缉私倍率：scripts/core/Economy.gd `WAR_INSPECTION`
  = {loyal 1.0, contested 1.3, besieged 1.0, fallen 2.0, closed 1.0}（入库基上在 :44）。
- 无引出港线：scripts/GameState.gd `customs_inspection()`「关注 × 缉私倍率 > 50 整舱查扣」
  → N = 50 / war_mul；关注 **> N** 才扣（判定为严格大于，恰等于 N 不扣）。
- 月份轴：1255-03（开局，scripts/core/Calendar.gd :8-11）至 1279-02，闭月序，共 288 个月。
- 未设 war 表三港（澎湖 / 南岛海道北口 / 占城）war_status 落 "loyal" → 恒 50；与 besieged 同值。

输出两段：
A) compact 逐港紧凑表（状态切换才列行，起止月闭区间），对账映射表文档正文；
B) verify  全量逐月校验（每格一行，共 14 港 × 288 月 = 4032 行），抽查对账用。

用法：
  python3 tools/ea9_attention_calc.py [--ports <路径>]            # compact（默认）
  python3 tools/ea9_attention_calc.py verify [--ports <路径>]     # 全量
  python3 tools/ea9_attention_calc.py --help

--ports 默认 data/ports.json（相对仓库根现解析，任意 cwd / worktree 下可跑）。
纯 stdlib，无任何绝对路径写死。
"""
import argparse
import json
import os
import sys

WAR_INSPECTION = {"loyal": 1.0, "contested": 1.3, "besieged": 1.0, "fallen": 2.0, "closed": 1.0}

START = (1255, 3)
END = (1279, 2)


def default_ports_path():
    # tools/ 上一级即仓库根
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "data", "ports.json")


def months():
    y, m = START
    while (y, m) <= END:
        yield "%04d-%02d" % (y, m)
        m += 1
        if m > 12:
            m = 1
            y += 1


ALL = list(months())
assert len(ALL) == 288, len(ALL)


def war_status(war, ym):
    if not war:
        return "loyal"
    best_k, best = "", "loyal"
    for k, v in war.items():
        if k <= ym and k > best_k:
            best_k, best = k, v
    return best


def fmt_n(mul):
    n = 50.0 / mul
    return ("%.2f" % n).rstrip("0").rstrip(".")


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="EA9-1 关注映射表复算：逐港逐月算无引出港线 N = 50 / 缉私倍率"
                    "（口径照 scripts/core/Economy.gd WAR_INSPECTION / war_status 与"
                    " scripts/GameState.gd customs_inspection 实读）")
    ap.add_argument("mode", nargs="?", default="compact", choices=("compact", "verify"),
                    help="compact = 逐港紧凑表（状态切换才列行，默认）；verify = 全量逐月 4032 行")
    ap.add_argument("--ports", default=default_ports_path(),
                    help="data/ports.json 路径（默认：仓库内 data/ports.json，任意 cwd 可跑）")
    args = ap.parse_args(argv)

    with open(args.ports, encoding="utf-8") as f:
        ports = json.load(f)["ports"]

    if args.mode == "verify":
        # B) 全量 4032 行：港id|港名|月|状态|倍率|N
        n_rows = 0
        for p in ports:
            war = p.get("war") or {}
            for ym in ALL:
                st = war_status(war, ym)
                mul = WAR_INSPECTION.get(st, 1.0)
                print("|".join([p["id"], p["name"], ym, st, "%.1f" % mul, "%.2f" % (50.0 / mul)]))
                n_rows += 1
        print("全量行数: %d" % n_rows, file=sys.stderr)
        return 0

    # A) 紧凑表
    print("# 紧凑映射表（状态切换才列行；N = 50 / 缉私倍率，关注 > N 无引必扣）")
    print("月份轴 1255-03 ～ 1279-02（288 个月）")
    total_cells = 0
    for p in ports:
        pid, name = p["id"], p["name"]
        war = p.get("war") or {}
        segs = []  # (起, 止, 状态, 倍率, N)
        cur_st, cur_mul, start_ym = None, None, ALL[0]
        prev_ym = ALL[0]
        for ym in ALL:
            st = war_status(war, ym)
            mul = WAR_INSPECTION.get(st, 1.0)
            if cur_st is None:
                cur_st, cur_mul = st, mul
            elif (st, mul) != (cur_st, cur_mul):
                segs.append((start_ym, prev_ym, cur_st, cur_mul, fmt_n(cur_mul)))
                cur_st, cur_mul, start_ym = st, mul, ym
            prev_ym = ym
        segs.append((start_ym, prev_ym, cur_st, cur_mul, fmt_n(cur_mul)))
        total_cells += len(ALL)
        print("\n## %s（%s）%s" % (name, pid, "" if war else "［无 war 表，恒 loyal］"))
        for s in segs:
            print("  %s ~ %s : %-9s 倍率 %.1f → N = %s" % (s[0], s[1], s[2], s[3], s[4]))
    print("\n总格数（港×月）: %d" % total_cells)
    return 0


if __name__ == "__main__":
    sys.exit(main())
