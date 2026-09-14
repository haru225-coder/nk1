#!/usr/bin/env python3
"""资产存在性门禁。
起因：2026-09-14 审计发现 `res://assets/bg_world_map.jpg`（标题屏 + 海图底图）被代码引用却不存在，
七道门禁无一检查资产——headless 编译不加载贴图，黑图只有真机能看见。

检查三类引用：
  1. 脚本/场景里的 `res://assets/<完整文件名>` 字面量
  2. Main.gd 的 PORT_BG / FACILITY_BG 表值（纯文件名，运行时再拼 res://assets/）
  3. 前缀拼接（`res://assets/sprite_` + id、`icon_` + 设施名）：按数据表逐个展开
"""
import json, os, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
FAIL = []


def check(cond, msg):
    if not cond:
        FAIL.append(msg)


def exists(name: str) -> bool:
    return (ASSETS / name).is_file()


def load(n):
    with open(ROOT / "data" / n, encoding="utf-8") as f:
        return json.load(f)


sources = {}
for sub in ("scripts", "scenes", "tools"):
    for p in (ROOT / sub).rglob("*"):
        if p.suffix in (".gd", ".tscn") and "legacy" not in p.parts:
            sources[p] = p.read_text(encoding="utf-8")

# ── 1. 完整路径字面量 ───────────────────────────────────
FULL = re.compile(r'res://assets/([A-Za-z0-9_./-]+\.[A-Za-z0-9]+)')
seen = set()
for p, src in sources.items():
    for name in FULL.findall(src):
        if name in seen:
            continue
        seen.add(name)
        check(exists(name), f"{p.relative_to(ROOT)} 引用 res://assets/{name}，文件不存在")

# ── 2. Main.gd 背景表 ───────────────────────────────────
main_src = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
port_bg_keys = set()
for tbl in ("PORT_BG", "FACILITY_BG", "ENDING_BG"):
    m = re.search(r'const %s := \{(.*?)\n\}' % tbl, main_src, re.S)
    check(m is not None, f"Main.gd 缺 {tbl}")
    if not m:
        continue
    for key, name in re.findall(r'"([^"]+)":\s*"([^"]+\.(?:jpg|png|webp))"', m.group(1)):
        check(exists(name), f"Main.{tbl}[{key}] = {name}，文件不存在")
        if tbl == "PORT_BG":
            port_bg_keys.add(key)
fb = re.search(r'const FALLBACK_BG := "([^"]+)"', main_src)
check(fb is not None and exists(fb.group(1)), "Main.FALLBACK_BG 缺失或文件不存在——回落底图本身不能缺")
# 每个港口都该有专属底图；漏了会静默回落通用航海图（2026-09-14 前漳州/温州/明州/济州就是这样）
for p in load("ports.json")["ports"]:
    check(p["id"] in port_bg_keys, f"ports.json 港口 {p['id']} 无 PORT_BG 映射，会回落通用图")
# 每个结局名都该有结算图：结局名 = _show_notice_dialog 第四个实参（只认整个调用写在一行、第四参是字面量的写法；
# 多行调用抓不到，靠 ENDING_BG 注释「键须与 finish() 收到的结局名一字不差」人工兜）
ending_names = set(re.findall(r'^\s*_show_notice_dialog\("[^"\n]*",\s*[^\n]*?,\s*"([^"\n]+)"\)\s*$', main_src, re.M))
em = re.search(r'const ENDING_BG := \{(.*?)\n\}', main_src, re.S)
ending_keys = set(re.findall(r'"([^"]+)":', em.group(1))) if em else set()
for nm in sorted(ending_names):
    check(nm in ending_keys, f"结局「{nm}」无 ENDING_BG 结算图映射")

# ── 3. 前缀拼接 ────────────────────────────────────────
# sprite_<npc id>.png：Main._add_npc_button 之类按 NPC id 拼；只有实际被引用的 id 才要求
for p, src in sources.items():
    if 'res://assets/sprite_' in src:
        m = re.search(r'res://assets/sprite_"\s*\+\s*([a-z_]+)', src)
        # 动态变量无法静态展开，退而检查：assets 里至少有一张 sprite_*.png，且代码对 null 有兜底
        check(any(f.name.startswith("sprite_") for f in ASSETS.iterdir()),
              f"{p.relative_to(ROOT)} 拼接 sprite_ 前缀但 assets 无任何 sprite_*.png")
    if 'res://assets/icon_' in src:
        # icon_<设施名>.png：设施名来自 scenes.json facilities[].id 去掉 city_ 前缀 + GENERIC_FACILITIES
        fac_ids = set()
        for s in load("scenes.json")["scenes"]:
            for f in s.get("facilities", []):
                fac_ids.add(str(f.get("id", "")).replace("city_", ""))
        gm = re.search(r'const GENERIC_FACILITIES := \[(.*?)\n\]', main_src, re.S)
        if gm:
            for fid in re.findall(r'"id":\s*"city_([a-z_]+)"', gm.group(1)):
                fac_ids.add(fid)
        for fid in sorted(fac_ids):
            if fid and not fid.startswith(("siege", "card")):
                check(exists(f"icon_{fid}.png"), f"设施 {fid} 需要 assets/icon_{fid}.png（{p.relative_to(ROOT)} 按前缀拼接）")

# ── 4. 伪装扩展名与过期导入 ─────────────────────────────
# .png 实为 JPEG：Godot 导入器按扩展名选解码器会失败，.import 写下 valid=false；
# 之后源 md5 不变就永不重导，纵使把文件换成真 PNG 也照旧走不了资源系统（2026-09-14 实测 11 个）。
# GameManager.load_texture 有按文件头解码的兜底，游戏不黑图，但每次加载刷一行 ERROR，且丢掉压缩纹理。
for f in sorted(ASSETS.glob("*.png")):
    with open(f, "rb") as fh:
        head = fh.read(3)
    check(head != b"\xff\xd8\xff", f"{f.name} 扩展名 .png 实为 JPEG——用 sips -s format png 转成真 PNG，并删掉对应 .import 让编辑器重导")
for imp in sorted(ASSETS.glob("*.import")):
    txt = imp.read_text(encoding="utf-8", errors="replace")
    check("valid=false" not in txt, f"{imp.name} 记录 valid=false（上次导入失败且不会自动重试）——删掉它，rsync 到临时目录跑一次编辑器扫描再拷回")

print("=" * 68)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print(f"资产引用 {len(seen)} 个完整路径 + PORT_BG/FACILITY_BG 表 + 前缀拼接展开，全部存在")
print("结果：全部通过")
