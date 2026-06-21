#!/usr/bin/env python3
"""入库立绘 + 第一章背景，并补齐 scenes 挂接与兼容文件。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    for script in (
        "ingest_portraits.py",
        "ingest_backgrounds.py",
        "generate_status_bar_assets.py",
        "finish_assets.py",
    ):
        print(f"\n>>> {script}")
        subprocess.run([sys.executable, str(ROOT / "tools" / script)], check=True)


if __name__ == "__main__":
    main()