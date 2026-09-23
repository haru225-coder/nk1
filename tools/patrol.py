#!/usr/bin/env python3
"""一次巡检。

顺序固定：符号 → 经济 → 通关模拟 →（有 Godot 时）无头冒烟 → 主场景走查。
前一层失败就停，不把后面的输出叠上来。
没有 Godot 时静态三套仍算闭环，和本机长期无引擎的情况一致。
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(cmd):
    print("\n$ " + " ".join(cmd), flush=True)
    result = subprocess.run(cmd, cwd=ROOT)
    if result.returncode != 0:
        print(f"\n巡检停在：{' '.join(cmd)}（退出 {result.returncode}）")
        sys.exit(result.returncode)


def main():
    py = sys.executable or "python3"
    for script in ("check_symbols.py", "verify_economy.py", "simulate_run.py"):
        run([py, os.path.join(ROOT, "tools", script)])

    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot:
        print("\n未找到 godot，引擎两层跳过。静态三套已通过。")
        return 0

    run([godot, "--headless", "--path", ROOT, "-s", "res://tools/godot_smoke.gd"])

    shell = [godot, "--path", ROOT, "-s", "res://tools/patrol_shell.gd"]
    if os.environ.get("DISPLAY"):
        run(shell)
    else:
        xvfb = shutil.which("xvfb-run")
        if not xvfb:
            print("\n有 godot，但没有 DISPLAY，也没有 xvfb-run，主场景走查没跑成。")
            return 1
        run([xvfb, "-a", "-s", "-screen 0 1400x900x24", *shell])

    print("\n巡检通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
