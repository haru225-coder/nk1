#!/usr/bin/env python3
"""资产存在性门禁。
起因：2026-09-14 审计发现 `res://assets/bg_world_map.jpg`（标题屏 + 海图底图）被代码引用却不存在，
七道门禁（2026-09-14 审计时口径；现行 16 道）无一检查资产——headless 编译不加载贴图，黑图只有真机能看见。

检查三类引用：
  1. 脚本/场景里的 `res://assets/<完整文件名>` 字面量
  2. Main.gd 的 PORT_BG / FACILITY_BG / ENDING_BG / PROLOGUE_PAGE_BG 表值（纯文件名，运行时再拼 res://assets/）；
     scripts/ 里 `_set_background_file("…")` 直接写的文件名与常量；H2 港页变体 bg_<港 id>_<后缀>.jpg 的后缀拼写
  3. 前缀拼接（`res://assets/sprite_` + id、`icon_` + 设施名）：按数据表逐个展开；牙行货图 assets/goods/good_<id>.png 的 id
"""
import json, os, re, sys, pathlib
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

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
        if p.suffix in (".gd", ".tscn") and "legacy" not in p.parts and p.name != "godot_smoke.gd":  # 云端 smoke 故意引用已拆除的死生态位图以断言其不存在
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
for tbl in ("PORT_BG", "FACILITY_BG", "ENDING_BG", "PROLOGUE_PAGE_BG"):
    m = re.search(r'const %s := \{(.*?)\n\}' % tbl, main_src, re.S)
    check(m is not None, f"Main.gd 缺 {tbl}")
    if not m:
        continue
    for key, name in re.findall(r'"([^"]+)":\s*"([^"]+\.(?:jpg|png|webp))"', m.group(1)):
        check(exists(name), f"Main.{tbl}[{key}] = {name}，文件不存在")
        if tbl == "PORT_BG":
            port_bg_keys.add(key)
        if tbl == "PROLOGUE_PAGE_BG":
            # H4 序章分页：键写错就永远查不到（静默照旧压酒棚）；cg_title 不进表（godot_story_check 断言标题屏压 bg_world_map.jpg）
            check(key.startswith("cg_") and key in {s.get("id") for s in load("scenes.json")["scenes"]},
                  f"Main.PROLOGUE_PAGE_BG 的键 {key} 不是 scenes.json 里的 cg_ 序章页")
            check(key != "cg_title", "Main.PROLOGUE_PAGE_BG 不许收 cg_title（标题屏须压 bg_world_map.jpg）")
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

# ── 2b. _set_background_file 直接写的文件名 ───────────────
# 它缺图时不报错，静默回落海路图 FALLBACK_BG；上面三张表查不到直接写进调用里的名字（2026-09-28 补：如 bg_linan.jpg）。
# 只查 scripts/：tools 里的门禁故意拿不存在的名字试回落。实参是大写常量的，按同文件或 Main.gd 的 const 字符串解开再查。
SBF_LIT = re.compile(r'_set_background_file\(\s*"([^"\n]+)"\s*\)')
SBF_CONST = re.compile(r'_set_background_file\(\s*(?:main\.)?([A-Z][A-Z0-9_]*)\s*\)')
sbf_n = 0
for p, src in sources.items():
    if "scripts" not in p.relative_to(ROOT).parts[:1]:
        continue
    for name in SBF_LIT.findall(src):
        sbf_n += 1
        check(exists(name), f"{p.relative_to(ROOT)} 写 _set_background_file(\"{name}\")，assets/{name} 不存在——缺图会静默回落海路图")
    for const in SBF_CONST.findall(src):
        cm = re.search(r'^const %s := "([^"\n]+)"' % const, src, re.M) or re.search(r'^const %s := "([^"\n]+)"' % const, main_src, re.M)
        check(cm is not None, f"{p.relative_to(ROOT)} 写 _set_background_file({const})，找不到这个字符串常量，查不了文件在不在")
        if cm:
            sbf_n += 1
            check(exists(cm.group(1)), f"{p.relative_to(ROOT)} 写 _set_background_file({const})，{const} = {cm.group(1)} 不存在——缺图会静默回落海路图")

# ── 2c. 港页变体拼写（H2）─────────────────────────────────
# Main._port_bg 按 bg_<港 id>_<后缀>.jpg 找图，后缀只认：非 loyal 战况（Economy.WAR_LABEL）、季节（PORT_SEASON_BY_MONTH）、
# PORT_YEAR_BG 给该港登记的年份。拼错的图不报错，只是永远不上屏。判法：assets/ 根下的 bg_* 图取最长的港 id 前缀——
# 后缀合法即变体，须是 .jpg；后缀不合法、或港 id 不对，而代码与数据里又没有一处写到这个文件名 → FAIL。
econ_src = (ROOT / "scripts" / "core" / "Economy.gd").read_text(encoding="utf-8")
wl = re.search(r'const WAR_LABEL := \{(.*?)\}', econ_src, re.S)
war_suffix = set(re.findall(r'"([a-z_]+)":', wl.group(1))) - {"loyal"} if wl else set()
check(bool(war_suffix), "Economy.gd 缺 WAR_LABEL 或其中没有非 loyal 战况——港页变体拼写检查取不到战况名")
sm = re.search(r'const PORT_SEASON_BY_MONTH := \[(.*?)\]', main_src, re.S)
season_suffix = set(re.findall(r'"([a-z]+)"', sm.group(1))) if sm else set()
check(bool(season_suffix), "Main.gd 缺 PORT_SEASON_BY_MONTH——港页变体拼写检查取不到季节名")
ym = re.search(r'const PORT_YEAR_BG := \{(.*?)\}\n', main_src, re.S)
port_years = {k: set(re.findall(r'\d{4}', v)) for k, v in re.findall(r'"([a-z_]+)":\s*\[([^\]]*)\]', ym.group(1))} if ym else {}
check(ym is not None, "Main.gd 缺 PORT_YEAR_BG")
port_ids = sorted((p["id"] for p in load("ports.json")["ports"]), key=len, reverse=True)
bm = re.search(r'const PORT_SEASON_BORROW := \{(.*?)\n', main_src)
for pid in list(port_years) + (re.findall(r'"([a-z_]+)":\s*\{', bm.group(1)) if bm else []):
    check(pid in port_ids, f"Main.PORT_YEAR_BG / PORT_SEASON_BORROW 的键 {pid} 不是 ports.json 的港 id")
ref_text = "\n".join(src for p, src in sources.items() if "scripts" in p.relative_to(ROOT).parts[:1] or p.suffix == ".tscn")
ref_text += "\n".join(f.read_text(encoding="utf-8") for f in (ROOT / "data").rglob("*.json"))
variant_n = 0
for f in sorted(ASSETS.glob("bg_*")):
    if f.suffix.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
        continue
    stem = f.stem[len("bg_"):]
    pid = next((q for q in port_ids if stem.startswith(q + "_")), "")
    suffix = stem[len(pid) + 1:] if pid else stem.rsplit("_", 1)[-1]
    legal = suffix in war_suffix or suffix in season_suffix or (pid != "" and suffix in port_years.get(pid, set()))
    if pid and legal:
        variant_n += 1
        check(f.suffix == ".jpg", f"assets/{f.name}：港页变体只认 .jpg（Main._port_bg 拼 bg_{pid}_{suffix}.jpg），这张永远不上屏")
        continue
    if f.name in ref_text:
        continue  # 不是变体：有代码或数据用着的普通底图（bg_xinghua_study.jpg 之类）
    if pid and suffix.isdigit():
        check(False, f"assets/{f.name}：{pid} 没在 Main.PORT_YEAR_BG 登记 {suffix} 年，年份档不会上屏")
    elif pid:
        check(False, f"assets/{f.name}：后缀「{suffix}」不是合法战况 {sorted(war_suffix)}、季节 {sorted(season_suffix)} 或登记年份，也没有代码引用——拼错了永远不上屏")
    elif legal:
        check(False, f"assets/{f.name}：后缀是港页变体，但「{stem[:-len(suffix) - 1]}」不是 ports.json 的港 id，永远不上屏")

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

# ── 3b. 牙行货卡货图 assets/goods/good_<id>.png（06 批）────────
# Main._make_market_row 按货 id 拼路径，图在才挂；文件名里的 id 拼错不报错，只是永远上不了卡，所以 id 须在 goods.json。
gm_path = re.search(r'"res://assets/(goods)/(good_)%s\.png"', main_src)
check(gm_path is not None, "Main.gd 找不到牙行货图路径 res://assets/goods/good_%s.png——取图路径改了，这里跟着改")
good_ids = {str(g.get("id", "")) for g in load("goods.json")["goods"]}
good_icon_n = 0
if (ASSETS / "goods").is_dir():
    for f in sorted((ASSETS / "goods").iterdir()):
        if f.name.startswith(".") or f.suffix in (".import", ".uid"):
            continue
        m = re.fullmatch(r'good_([a-z0-9_]+)\.png', f.name)
        check(m is not None and m.group(1) in good_ids,
              f"assets/goods/{f.name}：货卡只认 good_<goods.json 里的 id>.png，这张永远上不了卡")
        good_icon_n += 1

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

# ── 5. 人物立绘（characters 线）──────────────────────────
# Main 见面页、酒馆人物卡、船籍簿小头像、人物志都按 data/characters.json 的 portrait 取图（GameManager 读表）。
# 逐人遍历：路径须在 res://assets/ 下、文件在、且有 .import（没导入的 PNG load() 取不到，只剩回落图）。人数不写死。
portrait_checked = 0
chars_file = ROOT / "data" / "characters.json"
check(chars_file.is_file(), "data/characters.json 不存在（人物志与立绘的数据源）")
if chars_file.is_file():
    try:
        chars = json.loads(chars_file.read_text(encoding="utf-8")).get("characters", [])
    except (ValueError, AttributeError) as e:
        chars = []
        check(False, f"data/characters.json 解析失败：{e}")
    check(isinstance(chars, list) and len(chars) > 0, "data/characters.json 没有 characters 表或为空")
    for c in chars if isinstance(chars, list) else []:
        cid = c.get("id", "?") if isinstance(c, dict) else "?"
        pth = str(c.get("portrait", "")) if isinstance(c, dict) else ""
        if not pth.startswith("res://assets/"):
            check(False, f"人物 {cid} 的 portrait 不在 res://assets/ 下：{pth!r}")
            continue
        rel = pth[len("res://assets/"):]
        check(exists(rel), f"人物 {cid} 的立绘 {pth} 文件不存在")
        check((ASSETS / (rel + ".import")).is_file(), f"人物 {cid} 的立绘 {pth} 缺 .import（编辑器未导入，load() 取不到）")
        portrait_checked += 1

print("=" * 68)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print(f"资产引用 {len(seen)} 个完整路径 + PORT_BG/FACILITY_BG/ENDING_BG/PROLOGUE_PAGE_BG 表 + _set_background_file 直写 {sbf_n} 处"
      f" + 港页变体 {variant_n} 张 + 前缀拼接展开 + 货图 {good_icon_n} 张 + 人物立绘 {portrait_checked} 张，全部存在")
print("结果：全部通过")
