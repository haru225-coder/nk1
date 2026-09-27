#!/usr/bin/env python3
"""Godot 侧车门禁（lane ag）：侧车必须跟源文件同进同出。
起因：lane un（7562e69）一次清出 71 项已跟踪源文件缺的 *.uid / *.import 积压——各 lane 提交源文件时
按旧口径「跳过 *.uid/*.import」，侧车就一直漂在工作树里；别处一 clone 会重新生成随机 uid，场景 uid:// 引用断链。

只看 git 索引（`git ls-files`，已暂存也算已跟踪），不看工作树里未跟踪的文件：
  1. 每个已跟踪的 *.gd / *.gdshader 必须有已跟踪的 `<文件>.uid`
  2. 每个已跟踪的可导入素材（图 / 音 / 字体 / 模型 / csv）必须有已跟踪的 `<文件>.import`
  3. 反向：已跟踪的 `.uid` / `.import` 必须有已跟踪的源文件（不许只提侧车）
Godot 不扫的地方不查：带 `.gdignore` 的目录及其子目录、以 `.` 开头的目录/文件（与编辑器文件系统同口径）。
"""
import os, subprocess, sys
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UID_SRC = (".gd", ".gdshader")
IMPORT_SRC = (
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".tga", ".exr", ".hdr", ".dds", ".ktx",
    ".wav", ".ogg", ".mp3",
    ".ttf", ".otf", ".woff", ".woff2", ".fnt", ".font",
    ".glb", ".gltf", ".obj", ".fbx", ".blend", ".dae",
    ".csv",
)
FAIL = []

try:
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], check=True, capture_output=True).stdout
except (OSError, subprocess.CalledProcessError) as e:
    print("FAIL: git ls-files 跑不起来，无法判定已跟踪文件：", e)
    print("结果：1 项失败")
    sys.exit(1)
tracked = {p for p in out.decode("utf-8").split("\0") if p}

ignored_dirs = {os.path.dirname(p) for p in tracked if os.path.basename(p) == ".gdignore"}


def godot_sees(p):
    parts = p.split("/")
    if any(s.startswith(".") for s in parts):
        return False
    d = os.path.dirname(p)
    while d:
        if d in ignored_dirs:
            return False
        d = os.path.dirname(d)
    return "" not in ignored_dirs


n_uid = n_imp = n_side = 0
for p in sorted(tracked):
    if not godot_sees(p):
        continue
    low = p.lower()
    if low.endswith(UID_SRC):
        n_uid += 1
        if p + ".uid" not in tracked:
            FAIL.append(f"{p} 已跟踪，缺已跟踪的 {os.path.basename(p)}.uid")
    elif low.endswith(IMPORT_SRC):
        n_imp += 1
        if p + ".import" not in tracked:
            FAIL.append(f"{p} 已跟踪，缺已跟踪的 {os.path.basename(p)}.import")
    elif low.endswith((".uid", ".import")):
        n_side += 1
        src = p[: p.rfind(".")]
        if src not in tracked:
            FAIL.append(f"{p} 已跟踪，但源文件 {src} 未跟踪（只提侧车不提源）")

print("=" * 68)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print(f"脚本/着色器 {n_uid} 个都有 .uid · 素材 {n_imp} 个都有 .import · 侧车 {n_side} 个都有源文件")
print("结果：全部通过")
