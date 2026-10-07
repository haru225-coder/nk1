#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""patrol 实机截图数闸（lane w171-k4-live-shots 立 · 闸体 v1）。

判域 = patrol 旁证落盘目录里的 PNG 数与「巡逻应出张数」对账——
「门禁没说谎但也没覆盖」一型的敞口直查（巡检过了、截图张数却 0）：

  壹·缺目录格——落盘根（$NK1_SHOT_DIR，缺省 /tmp/patrol-shots）下的 patrol/ 子目录不在，
      即「根本没跑过、或目录被搬到别处」；预期 11 张巡逻旁证，报缺 11 张、rc=1。
  贰·张数格——目录在则数 *.png；张数 < 预期钉（11，见 patrol_shell.gd 的 _save_shot 战场）即 ✗
      点名缺几张、rc=1。张数 ≥ 11 即本格绿（不判一色 / 尺寸，一色判据仍归 patrol_shell 自身）。
  叁·自检每次先跑（§五.3 规则表型轨：内存样本扫同一 scan_text 判路）——
      S1 目录不在须红点名 11 张缺 / S2 目录在而张数 0..10 须红点名缺张 / S3 目录在而张数 11 须绿 /
      S4 目录在而张数 12 须绿。自检不过先退 2（判语面点名自检红行）。
  钉拨颁规矩照 §五.3——patrol 加截一张（_save_shot 多一发）须在本脚本 EXPECTED_PATROL_SHOTS 同笔拨钉随同色，
      两闸收尾绿才算合法。

闸位：tier=must（一键跑末段）。w150/w153/w154/w156 四帧 patrol rc=1 出门（X11 不在、DISPLAY 不通）
而 gates 照红——红对了但没说「连一张图都没出」；本闸把张数变成必跑闸的一行，巡逻真出 0 张当帧就红，
不再靠人看目录详。run.log 的 grep 行也已过（SUMMARY/PASS/FAIL 列都是 patrol_shell 内里判词），对不上张数。

  python3 tools/check_patrol_shot_count.py             # 自检 + 真档判路；张数不足退 1
  python3 tools/check_patrol_shot_count.py --json      # 机读（同 docs/GATES.md §二）
  NK1_SHOT_DIR=/tmp/<lane>/shots python3 tools/check_patrol_shot_count.py   # 自测指定根

退出码：0=自检 4 格全过＋真档张数格绿；1=任一 ✗（含自检样本判不出点名形）；
2=工具面断（patrol_shell.gd 读不到——判据 SoR 拿不到，防静默绿）。
"""
import argparse
import os
import re
import sys

if "--json" in sys.argv[1:]:  # 机读输出件（docs/GATES.md）；不带开关不进此支
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json
    gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
PATROL_GD = os.path.join(ROOT, "patrol_shell.gd")

# ── 与 patrol_shell.gd 同 SoR 的张数钉（拨颁必同笔随同色 §五.3）──
EXPECTED_PATROL_SHOTS = 11

FAILS = []


def shot_dir():
    """落盘根：NK1_SHOT_DIR 缺省 /tmp/patrol-shots（patrol_shell._shot_dir 同口径）。"""
    root = os.environ.get("NK1_SHOT_DIR", "").strip()
    if not root:
        root = "/tmp/patrol-shots"
    if not os.path.isabs(root):
        root = os.path.join(os.environ.get("PWD", os.getcwd()), root)
    return os.path.join(root, "patrol")


def read_expected():
    """从 patrol_shell.gd 现读应出张数 SoR；读不到 → 判据面断。
    = 字面串标签的 `_check_screen("…", true)` 处 + 循环内一次 `_check_screen(port, true)` ×PORTS 实扫数
      + `_shot_chart(chart, "…")` 字面串串标签处 + 直白 `_save_shot("…")` 字面串标签处。
    """
    if not os.path.isfile(PATROL_GD):
        return None
    src = open(PATROL_GD, encoding="utf-8").read()
    n_literal_screen = len(re.findall(r'_check_screen\(\s*"[^"]+"\s*,\s*true\s*\)', src))
    ports_m = re.search(r"^const PORTS\s*:?=\s*\[([^\]]+)\]", src, re.M)
    if ports_m and len(re.findall(r'_check_screen\(\s*port\s*,\s*true\s*\)', src)) >= 1:
        n_ports = len(re.findall(r'"[^"]+"', ports_m.group(1)))
    else:
        n_ports = 0
    n_chart = len(re.findall(r'_shot_chart\(\s*\w+\s*,\s*"[^"]+"\s*\)', src))
    n_blade = len(re.findall(r'_save_shot\(\s*"[^"]+"\s*\)', src))
    return n_literal_screen + n_ports + n_chart + n_blade


def scan_text(path, expected):
    """一条判路：目录 path 的 *.png 数对预期 expected。返回（张数, ✗句 或 None）。"""
    if not os.path.isdir(path):
        return 0, f"patrol 旁证目录不在：{path}（预期落 {expected} 张；巡检根本没跑过或目录被挪）"
    n = len([f for f in os.listdir(path) if f.endswith(".png")])
    if n < expected:
        return n, f"patrol 旁证实出 {n} 张 < 应出 {expected} 张（缺 {expected - n} 张；巡逻真出 0 / 半截）"
    return n, None


def selftest():
    """零、判据自检（内存样本）：过同一条 scan_text 判路。"""
    import tempfile
    ok = True
    with tempfile.TemporaryDirectory() as td:
        missing = os.path.join(td, "nope")
        n, bad = scan_text(missing, 11)
        if not (bad is not None and n == 0 and "路径" not in bad and "目录不在" in bad):
            FAILS.append(f"S1 目录不在须红点名缺 11 张（现 bad={bad!r}）")
            ok = False
        for k in (0, 1, 10):
            d = os.path.join(td, f"n{k}")
            os.makedirs(d)
            for i in range(k):
                open(os.path.join(d, f"x{i}.png"), "wb").write(b"x")
            n, bad = scan_text(d, 11)
            if bad is None or n != k or f"缺 {11 - k} 张" not in bad:
                FAILS.append(f"S2 张数 {k} 须红点名缺 {11 - k}（现 n={n} bad={bad!r}）")
                ok = False
        d = os.path.join(td, "ok")
        os.makedirs(d)
        for i in range(11):
            open(os.path.join(d, f"x{i}.png"), "wb").write(b"x")
        n, bad = scan_text(d, 11)
        if bad is not None or n != 11:
            FAILS.append(f"S3 张数 11 须绿（现 n={n} bad={bad!r}）")
            ok = False
        d = os.path.join(td, "more")
        os.makedirs(d)
        for i in range(12):
            open(os.path.join(d, f"x{i}.png"), "wb").write(b"x")
        n, bad = scan_text(d, 11)
        if bad is not None or n != 12:
            FAILS.append(f"S4 张数 12 须绿（现 n={n} bad={bad!r}）")
            ok = False
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    print("零、判据自检（S1..S4）")
    if not selftest():
        for f in FAILS:
            print("  ✗", f)
        print("结果：%d 项问题" % len(FAILS))
        return 1
    print("  ✓ 自检 4 格全过")

    expected = read_expected()
    print("一、读 patrol_shell.gd 应出张数")
    if expected is None:
        FAILS.append("读不到 tools/patrol_shell.gd（判据 SoR 拿不到，防静默绿）")
        for f in FAILS:
            print("  ✗", f)
        print("结果：%d 项问题" % len(FAILS))
        return 2
    if expected != EXPECTED_PATROL_SHOTS:
        FAILS.append(f"patrol_shell.gd 现读应出 {expected} 张 ≠ 钉 {EXPECTED_PATROL_SHOTS}（应出张数变了，拨钉未到 §五.3）")
    else:
        print(f"  ✓ 现读应出 {expected} 张 = 钉 {EXPECTED_PATROL_SHOTS}")

    print("二、数实落张数")
    n, bad = scan_text(shot_dir(), EXPECTED_PATROL_SHOTS)
    if bad is not None:
        FAILS.append(bad)
        print("  ✗", bad)
    else:
        print(f"  ✓ 实落 {n} 张 ≥ 应出 {EXPECTED_PATROL_SHOTS} 张（落点 {shot_dir()}）")

    if FAILS:
        print("结果：%d 项问题" % len(FAILS))
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
