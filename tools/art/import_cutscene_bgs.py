#!/usr/bin/env python3
"""过场背景导入（cutscene_content 线）。

把选定的油画从只读来源复制到 assets/cutscene/cs_<语义名>.jpg：
  · 只裁不放大：最长边 > 1920 才等比缩小，否则保持原尺寸；
  · JPEG 质量 90，统一 RGB、去掉 EXIF / ICC 以外的元数据；
  · 可选 crop（源图像素坐标 x0,y0,x1,y1）——用于切掉画家签名、做旧黑边，或把竖幅立绘截成 16:9 横带。

选图理由与每镜用途见 docs/过场分镜.md。来源全部只读，本脚本不改动来源文件。

用法：
  python3 tools/art/import_cutscene_bgs.py              # 导入（已存在且来源未变则跳过）
  python3 tools/art/import_cutscene_bgs.py --force      # 全部重导
  python3 tools/art/import_cutscene_bgs.py --check      # 校验：产物规格 + 数据契约；来源目录在就顺带核对来源与裁切
  python3 tools/art/import_cutscene_bgs.py --data-only  # 只校验产物（按 .import_manifest.json 的 sha1/尺寸）+ 数据契约，不碰来源——CI 用这个

来源目录（Codex 线 assets/）默认 /Users/snowchan27/tmp/nk1-codex/assets，可用环境变量 NK1_CODEX_ASSETS 覆盖。
旧底来源（第一轮 worktree 的 assets/，即 main 9233852 落地、云端 da29e49 又换掉的旧图）默认
/Users/snowchan27/tmp/nk1-art/assets，可用 NK1_LEGACY_ASSETS 覆盖。
来源目录不在时（新克隆、别的机器、合回 main 后），--check 自动退化为 --data-only：只核对产物与清单一致，不报「来源缺失」。
"""
import hashlib
import json
import os
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "cutscene"
STAMP = OUT_DIR / ".import_manifest.json"
CODEX = pathlib.Path(os.environ.get("NK1_CODEX_ASSETS", "/Users/snowchan27/tmp/nk1-codex/assets"))
POOLS = CODEX / "port_pools"
INGESTED = CODEX / "_ingested"
LEGACY = pathlib.Path(os.environ.get("NK1_LEGACY_ASSETS", "/Users/snowchan27/tmp/nk1-art/assets"))
# 仓库自己 assets/ 里、游戏没引用的旧图（如 bg_gpt_*.png）：转成 16:9 JPEG 供过场用，来源永远在
REPO_ASSETS = ROOT / "assets"

MAX_EDGE = 1920
QUALITY = 90
# 故意保留竖幅的图：过场里用竖摇（cam cy 变化）看全身，不是漏裁
TALL_OK = {"cs_ziling_portrait.jpg"}

# (产物名, 来源, crop 或 None, 备注)
MANIFEST = [
    ("cs_north_mongol.jpg", CODEX / "bg_mongol_camp.png", None,
     "开场·北：漠北营帐与骑兵，远处河谷"),
    ("cs_west_caravan.jpg", POOLS / "quanzhou" / "021.jpg", None,
     "开场·西：驼队西行、圆顶城郭"),
    ("cs_south_champa.jpg", POOLS / "champa" / "001.png", None,
     "开场·南：占城港，塔寺与稻米装船"),
    ("cs_ziling_portrait.jpg", INGESTED / "grok-8f0dce14-91c1-4f22-8f70-427122af5600.jpg", None,
     "开场末镜/忠肃帐中：陈子龙半身像（与 Codex 线 portrait_chen_wenlong 同源）。整幅竖图保留，"
     "过场里靠 cam 的 cy 在脸（0.30）与《春秋左传》（0.72）之间竖摇"),
    ("cs_jeju_north.jpg", POOLS / "jeju" / "004.jpg", None,
     "第二章：耽罗雪山、石墙、海女，北线寒色"),
    ("cs_guangzhou_guangta.jpg", POOLS / "guangzhou" / "001.jpg", (600, 0, 1792, 670),
     "第三章卡专用：章节卡墨晕窗只露 cover 取景的中间一竖条（约 49% 宽），整幅导入时光塔落在窗边；"
     "改裁右上 16:9 块，让光塔落在窗中偏左、蕃坊拱廊在右；同时切掉右下角画家签名"),
    ("cs_nanhai_dusk.jpg", POOLS / "keelung" / "004.png", None,
     "第四章：南海岸夕照，独木舟与远帆"),
    ("cs_xinghua_seawall.jpg", POOLS / "xinghua" / "004.jpg", (0, 0, 1792, 940),
     "忠肃·城楼：风暴下的临海城墙；切掉右下角签名"),
    ("cs_fleet_armored.jpg", POOLS / "zhangzhou" / "041.jpg", None,
     "海上宋鬼·崖山：甲士立船，舰队连樯"),
    ("cs_quanzhou_fanfang.jpg", POOLS / "quanzhou" / "005.jpg", None,
     "泉州蒲氏的船：蕃坊、礼拜塔与番商"),
    ("cs_citywall_sunset.jpg", INGESTED / "grok-e163fc64-44b1-4cd3-86ad-08510ca7a612.jpg", (52, 44, 1740, 964),
     "未归/蒲氏：夕照城楼与码头人影；切掉做旧黑边"),
    ("cs_fleet_sunset.jpg", POOLS / "quanzhou" / "009.jpg", None,
     "纲首：夕照里的船队"),
    ("cs_hanjiang_night.jpg", POOLS / "zhangzhou" / "031.jpg", None,
     "岸上的根·涵江海口：月夜搬箱上船，远处城灯"),
    ("cs_shore_soldiers.jpg", POOLS / "wenzhou" / "021.jpg", None,
     "岸上的根·出海口：岸上兵影，小船出港，云破日出"),
    ("cs_taijiang_dawn.jpg", POOLS / "mingzhou" / "027.jpg", None,
     "五段结局后记「一百多年后・福州台江」：晨雾江岸、石桥、远帆与渔船（原先借用兴化海口，地理不对）"),
    # ── 云端集成（port 线，2026-09-25）──
    ("cs_world_map_gold.jpg", LEGACY / "bg_world_map.jpg", None,
     "开场首镜「舆图总纲」：旧底 main 9233852 的泥金靛海舆图（华南海岸、台湾、琉球弧、日本）。云端 da29e49 把 "
     "assets/bg_world_map.jpg 换成了带西式罗盘玫瑰与海怪、海岸不对应真实地理的另一张（标题页仍用它），"
     "开场镜头是按旧图取景的，改指这张"),
    ("cs_quanzhou_bay_gold.jpg", POOLS / "quanzhou" / "003.jpg", None,
     "章末了结·南海一纲首镜：泉州湾金色天光，连樯出港，湾里有蕃舶三角帆（泉州蕃舶本色）"),
    ("cs_night_surf.jpg", POOLS / "keelung" / "002.png", None,
     "章末了结·史册未落笔首镜「占城夜里潮声很重」：黑礁白浪、泊船硬帆；镜头只取右半（左侧岸上人物不入画），调夜色"),
    ("cs_counting_house.jpg", REPO_ASSETS / "bg_gpt_1.png", None,
     "章末了结·账上的距离第 2 镜「只有进出清楚的货，和脚钱」：货栈账房，麻包、算盘、摊开的账册"
     "（仓库内 bg_gpt_1.png，游戏未引用；镜头压在案面与货堆，避开左侧青花罐与上方匾额字）"),
]


def _digest(path: pathlib.Path, crop) -> str:
    h = hashlib.sha1()
    h.update(path.read_bytes())
    h.update(repr(crop).encode())
    h.update(f"{MAX_EDGE}/{QUALITY}".encode())
    return h.hexdigest()[:16]


def _file_sha1(path: pathlib.Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def _src_root(src: pathlib.Path) -> pathlib.Path:
    for root in (LEGACY, REPO_ASSETS):
        try:
            src.relative_to(root)
            return root
        except ValueError:
            pass
    return CODEX


def _src_label(src: pathlib.Path) -> str:
    """清单里记来源相对 Codex assets/（或旧底 / 仓库 assets/）的路径（不写本机绝对路径）。"""
    for tag, root in (("codex", CODEX), ("legacy", LEGACY), ("repo", REPO_ASSETS)):
        try:
            return f"{tag}:" + src.relative_to(root).as_posix()
        except ValueError:
            pass
    return src.name


def _load_stamp() -> dict:
    try:
        return json.loads(STAMP.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def convert(src: pathlib.Path, dst: pathlib.Path, crop) -> tuple:
    im = Image.open(src)
    im.load()
    im = im.convert("RGB")
    if crop is not None:
        x0, y0, x1, y1 = crop
        if not (0 <= x0 < x1 <= im.width and 0 <= y0 < y1 <= im.height):
            raise ValueError(f"{src.name} crop {crop} 越出 {im.size}")
        im = im.crop(crop)
    edge = max(im.size)
    if edge > MAX_EDGE:
        s = MAX_EDGE / edge
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst, "JPEG", quality=QUALITY, optimize=True, progressive=False, subsampling=0)
    return im.size


def run(force: bool) -> int:
    if not CODEX.is_dir():
        print(f"FAIL 来源目录不在：{CODEX}（导入需要来源；只校验请用 --check / --data-only）")
        return 1
    stamp = _load_stamp()
    changed = 0
    for name, src, crop, note in MANIFEST:
        if not src.is_file():
            print(f"FAIL 来源缺失：{src}")
            return 1
        dst = OUT_DIR / name
        dg = _digest(src, crop)
        old = stamp.get(name, {})
        if not force and dst.is_file() and old.get("digest") == dg:
            # 旧清单没有产物 sha1 / 相对来源的，就地补上（不重编码图）
            old.update({"source": _src_label(src), "out_sha1": _file_sha1(dst), "note": note})
            print(f"skip {name}")
            continue
        size = convert(src, dst, crop)
        stamp[name] = {"digest": dg, "source": _src_label(src), "crop": list(crop) if crop else None,
                       "size": list(size), "out_sha1": _file_sha1(dst), "note": note}
        changed += 1
        print(f"write {name} {size[0]}x{size[1]} ← {_src_label(src)}")
    # 清理清单里已不存在的旧条目（只动 stamp，不删图）
    names = {m[0] for m in MANIFEST}
    stamp = {k: v for k, v in stamp.items() if k in names}
    STAMP.write_text(json.dumps(stamp, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"完成：{len(MANIFEST)} 张，本次写入 {changed} 张 → {OUT_DIR.relative_to(ROOT)}/")
    return 0


def check(data_only: bool) -> int:
    bad = []
    notes = []
    with_src = not data_only and CODEX.is_dir()
    if not data_only and not with_src:
        notes.append(f"来源目录不在（{CODEX}），跳过来源核对，只按 .import_manifest.json 核对产物")
    stamp = _load_stamp()
    if len(MANIFEST) > 24:
        bad.append(f"新增图 {len(MANIFEST)} 张，超过 24 张上限")
    for name, src, crop, _ in MANIFEST:
        dst = OUT_DIR / name
        ent = stamp.get(name)
        if not dst.is_file():
            bad.append(f"产物缺失 {dst.relative_to(ROOT)}（先跑一次导入）")
            continue
        if not isinstance(ent, dict):
            bad.append(f"{name} 不在 .import_manifest.json 里（先跑一次导入）")
            continue
        with Image.open(dst) as im:
            w, h = im.size
            fmt = im.format
        if fmt != "JPEG":
            bad.append(f"{name} 不是 JPEG（{fmt}）")
        if max(w, h) > MAX_EDGE:
            bad.append(f"{name} 最长边 {max(w, h)} > {MAX_EDGE}")
        if w / h < 16 / 9 - 0.03 and name not in TALL_OK:
            bad.append(f"{name} 宽高比 {w / h:.3f} 明显窄于 16:9，cover 铺满会裁掉过多上下")
        # 产物 = 清单记录的那一张（不依赖来源目录）
        if ent.get("out_sha1") != _file_sha1(dst):
            bad.append(f"{name} 与 .import_manifest.json 记录的 sha1 不符——图被改过或没经本脚本导入")
        if list(ent.get("size", [])) != [w, h]:
            bad.append(f"{name} 尺寸 {w}x{h} ≠ 清单记录 {ent.get('size')}")
        want_crop = list(crop) if crop else None
        if ent.get("crop") != want_crop:
            bad.append(f"{name} 清单裁切 {ent.get('crop')} ≠ MANIFEST {want_crop}——改了裁切没重导")
        if not with_src:
            continue
        if not _src_root(src).is_dir():
            notes.append(f"{name} 的来源目录不在（{_src_root(src)}），跳过来源核对，只按清单 sha1 核对产物")
            continue
        if not src.is_file():
            bad.append(f"来源缺失 {src}")
            continue
        if ent.get("digest") != _digest(src, crop):
            bad.append(f"{name} 来源或裁切变了，产物过期——重跑导入")
        with Image.open(src) as s:
            sw, sh = s.size
        cw, ch = (crop[2] - crop[0], crop[3] - crop[1]) if crop else (sw, sh)
        if w > cw or h > ch:
            bad.append(f"{name} {w}x{h} 大于源裁切 {cw}x{ch}——放大了")
    for f in sorted(OUT_DIR.glob("cs_*.jpg")):
        if f.name not in {m[0] for m in MANIFEST}:
            bad.append(f"{f.name} 不在导入清单里（来源不明）")
    bad += check_data()
    for n in notes:
        print("NOTE", n)
    if bad:
        for b in bad:
            print("FAIL", b)
        return 1
    mode = "产物+来源" if with_src else "产物（按清单 sha1）"
    print(f"import_cutscene_bgs --check：{len(MANIFEST)} 张背景合规［{mode}］；data/cutscenes.json 契约校验通过")
    return 0


# ── data/cutscenes.json 契约校验 ─────────────────────────────
GRADES = {"neutral", "dusk", "dawn", "night", "fire", "cold", "sepia"}
FX = {"mist", "embers", "snow", "rain", "sea_spray", "dust", "lantern_glow"}
TRANS = {"ink", "fade", "cut", "flash"}
STYLES = {"title", "era", "line", "narration", "seal"}
POSES = {"center", "bottom", "lower_left", "right_vertical", "left_vertical"}
CANVAS = (1280, 720)
# 与 CutscenePlayer.STYLES / _make_caption 的排版上限对应：超了会折行，这里要求一律单行（竖排为单列）
H_LIMIT = {("narration", "lower_left"): 22, ("line", "bottom"): 32, ("line", "center"): 32,
           ("title", "center"): 10, ("era", "lower_left"): 22}
V_LIMIT = {"era": 13, "title": 5, "line": 15, "narration": 16}
CN_DIGIT = {"〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def _res_file(res: str) -> pathlib.Path:
    return ROOT / res[len("res://"):]


def _cover_view(tex, center, zoom):
    """复刻 cs_kit.cover_view：返回 (请求中心, 夹紧后中心, 视窗宽高)。"""
    ta = tex[0] / tex[1]
    ca = CANVAS[0] / CANVAS[1]
    w, h = (ca / ta, 1.0) if ta > ca else (1.0, ta / ca)
    w /= zoom
    h /= zoom
    cx = min(max(center[0], w / 2), 1 - w / 2)
    cy = min(max(center[1], h / 2), 1 - h / 2)
    return (cx, cy), (w, h)


def _era_table():
    src = (ROOT / "scripts" / "core" / "Calendar.gd").read_text(encoding="utf-8")
    import re
    return [(int(a), int(b), n) for a, b, n in re.findall(r'\[(\d{4}),\s*(\d{4}),\s*"([^"]+)"\]', src)]


def _cn_era_year(n: int) -> str:
    if n == 1:
        return "元"
    digits = "〇一二三四五六七八九"
    if n < 10:
        return digits[n]
    if n < 20:
        return "十" + (digits[n - 10] if n > 10 else "")
    return digits[n // 10] + "十" + (digits[n % 10] if n % 10 else "")


def check_data() -> list:
    import re
    bad = []
    path = ROOT / "data" / "cutscenes.json"
    try:
        d = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return [f"data/cutscenes.json 读不了：{e}"]
    if d.get("version") != 1:
        bad.append("version 必须为 1")
    cs_all = d.get("cutscenes", {})
    used_cs_files = set()
    size_cache = {}
    for cid, cs in cs_all.items():
        where = f"cutscenes.{cid}"
        if not isinstance(cs.get("title"), str) or not isinstance(cs.get("letterbox"), bool):
            bad.append(f"{where} 缺 title(str) / letterbox(bool)")
        shots = cs.get("shots")
        if not isinstance(shots, list) or not shots:
            bad.append(f"{where} 没有镜头")
            continue
        total = 0.0
        for i, s in enumerate(shots):
            w = f"{where}[{i + 1}]"
            bg = s.get("bg", "")
            if not (isinstance(bg, str) and bg.startswith("res://assets/") and bg.endswith(".jpg")):
                bad.append(f"{w} bg 须为 res://assets/…jpg：{bg}")
                continue
            f = _res_file(bg)
            if not f.is_file():
                bad.append(f"{w} bg 文件不存在：{bg}")
                continue
            if f.parent == OUT_DIR:
                used_cs_files.add(f.name)
            if f not in size_cache:
                with Image.open(f) as im:
                    size_cache[f] = im.size
            dur = s.get("duration")
            if not isinstance(dur, (int, float)) or dur <= 0:
                bad.append(f"{w} duration 非正数")
                continue
            total += dur
            for key in ("cam_from", "cam_to"):
                c = s.get(key)
                if not (isinstance(c, list) and len(c) == 3 and all(isinstance(v, (int, float)) for v in c)):
                    bad.append(f"{w} {key} 须为 [cx, cy, zoom]")
                    continue
                if not (0 <= c[0] <= 1 and 0 <= c[1] <= 1):
                    bad.append(f"{w} {key} 中心越出 0..1")
                if c[2] < 1.0:
                    bad.append(f"{w} {key} zoom {c[2]} < 1")
                    continue
                (cx, cy), _ = _cover_view(size_cache[f], c[:2], c[2])
                if abs(cx - c[0]) > 0.012 or abs(cy - c[1]) > 0.012:
                    bad.append(f"{w} {key} {c} 会被引擎夹紧到 ({cx:.3f}, {cy:.3f})——镜头推不到想要的位置")
            if s.get("grade") not in GRADES:
                bad.append(f"{w} grade 非法：{s.get('grade')}")
            fx = s.get("fx")
            if not isinstance(fx, list) or not set(fx) <= FX:
                bad.append(f"{w} fx 非法：{fx}")
            if s.get("transition_in") not in TRANS:
                bad.append(f"{w} transition_in 非法：{s.get('transition_in')}")
            sh = s.get("shake")
            if not isinstance(sh, (int, float)) or not 0 <= sh <= 1:
                bad.append(f"{w} shake 须在 0..1")
            for j, c in enumerate(s.get("captions", [])):
                wc = f"{w}.captions[{j + 1}]"
                t = c.get("t")
                if not isinstance(t, (int, float)) or not 0 <= t < dur:
                    bad.append(f"{wc} t={t} 不在 [0, duration={dur})")
                    continue
                st, pos, txt = c.get("style"), c.get("pos"), c.get("text", "")
                if st not in STYLES or pos not in POSES:
                    bad.append(f"{wc} style/pos 非法：{st}/{pos}")
                if not isinstance(txt, str) or not txt.strip():
                    bad.append(f"{wc} text 为空")
                    continue
                hold = c.get("hold")
                if hold is not None and (not isinstance(hold, (int, float)) or hold <= 0 or t + hold > dur + 1e-6):
                    bad.append(f"{wc} hold={hold} 越过镜头末尾（t+hold > {dur}）")
                if t > dur - 1.5 and st != "seal":
                    bad.append(f"{wc} t={t} 离镜头结束不足 1.5 秒，读不完")
                for para in txt.split("\n"):
                    n = len(para)
                    if pos in ("right_vertical", "left_vertical"):
                        lim = V_LIMIT.get(st, 99)
                    else:
                        lim = H_LIMIT.get((st, pos), 99)
                    if st != "seal" and n > lim:
                        bad.append(f"{wc}「{para}」{n} 字，超出 {st}/{pos} 单行上限 {lim}")
                if st == "seal" and len(txt) > 4:
                    bad.append(f"{wc} 印文过长：{txt}")
        if cid == "opening":
            if not 60 <= total <= 90 or not 6 <= len(shots) <= 9:
                bad.append(f"{where} 共 {len(shots)} 镜 {total:.1f} 秒，要求 6–9 镜、60–90 秒")
        elif cid.startswith("ending_"):
            if not 20 <= total <= 40 or not 3 <= len(shots) <= 5:
                bad.append(f"{where} 共 {len(shots)} 镜 {total:.1f} 秒，要求 3–5 镜、20–40 秒")
    # 结局键 = Main.gd 的 ENDING_BG 键（终局六结局名）∪ chapters.json 终章 endings 的 id（云端四个章末了结）
    main_src = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    m = re.search(r'const ENDING_BG := \{(.*?)\n\}', main_src, re.S)
    keys = set(re.findall(r'"([^"]+)":', m.group(1))) if m else set()
    chapters_json = json.loads((ROOT / "data" / "chapters.json").read_text(encoding="utf-8"))["chapters"]
    ch_end_ids = {str(e.get("id")) for c in chapters_json for e in (c.get("endings") or [])}
    if not keys:
        bad.append("Main.gd 里找不到 const ENDING_BG")
    if keys & ch_end_ids:
        bad.append(f"ENDING_BG 结局名与章末了结 id 撞名：{sorted(keys & ch_end_ids)}")
    keys |= ch_end_ids
    ends = d.get("endings", {})
    if set(ends.keys()) != keys:
        bad.append(f"endings 键 {sorted(ends.keys())} ≠ Main.ENDING_BG 键 ∪ 章末了结 id {sorted(keys)}")
    for k, v in ends.items():
        if v not in cs_all:
            bad.append(f"endings.{k} → {v} 不是已有过场")
            continue
        if k in ch_end_ids:
            shots = cs_all[v].get("shots") or []
            tot = sum(s.get("duration", 0) for s in shots if isinstance(s.get("duration"), (int, float)))
            if not 20 <= tot <= 35 or not 3 <= len(shots) <= 5:
                bad.append(f"章末了结 {k} → {v} 共 {len(shots)} 镜 {tot:.1f} 秒，要求 3–5 镜、20–35 秒")
    # 章节卡：1–4 章齐全；年号文字与 Calendar.ERAS 一致；年份 = 开局年 + 前几章 advance_years 之和
    # （晋升当场 GameManager.skip_years(advance_years)，所以第 n 章最早开场年 = 开局年 + Σ 前 n−1 章 advance_years）
    eras = _era_table()
    cal_src = (ROOT / "scripts" / "core" / "Calendar.gd").read_text(encoding="utf-8")
    ym = re.search(r"var year: int = (\d{4})", cal_src)
    start_year = int(ym.group(1)) if ym else None
    if start_year is None:
        bad.append("Calendar.gd 里找不到开局年 var year: int = ****")
    adv = {int(c["id"]): int(c.get("advance_years", 0)) for c in chapters_json}
    chs = d.get("chapters", {})
    if sorted(chs.keys()) != ["1", "2", "3", "4"]:
        bad.append(f"chapters 须恰为 1–4：{sorted(chs.keys())}")
    for k, c in chs.items():
        for fld in ("bg", "epigraph", "epigraph_src", "year_text"):
            if not isinstance(c.get(fld), str):
                bad.append(f"chapters.{k}.{fld} 须为字符串")
        bgf = _res_file(c.get("bg", "res://"))
        if not bgf.is_file():
            bad.append(f"chapters.{k}.bg 不存在：{c.get('bg')}")
        elif bgf.parent == OUT_DIR:
            used_cs_files.add(bgf.name)
        yt = c.get("year_text", "")
        mm = re.fullmatch(r"(.+?)(元|[一二三四五六七八九十]+)年・([〇一二三四五六七八九]{4})", yt)
        if not mm:
            bad.append(f"chapters.{k}.year_text 格式应为「宝祐三年・一二五五」：{yt}")
            continue
        year = int("".join(str(CN_DIGIT[ch]) for ch in mm.group(3)))
        if start_year is not None and k.isdigit():
            want_year = start_year + sum(adv.get(i, 0) for i in range(1, int(k)))
            if year != want_year:
                bad.append(f"chapters.{k}.year_text 年份 {year} ≠ 开局 {start_year} + 前几章 advance_years 之和 = {want_year}")
        era = next((e for e in eras if e[0] <= year <= e[1]), None)
        want = f"{era[2]}{_cn_era_year(year - era[0] + 1)}年・{mm.group(3)}" if era else "?"
        if yt != want:
            bad.append(f"chapters.{k}.year_text「{yt}」与 Calendar.ERAS 推算「{want}」不符")
    # 抵港横幅：覆盖 ports.json 全部港口，港名一致
    ports = json.loads((ROOT / "data" / "ports.json").read_text(encoding="utf-8"))["ports"]
    pb = d.get("port_banners", {})
    ids = {p["id"]: p["name"] for p in ports}
    if set(pb.keys()) != set(ids):
        bad.append(f"port_banners 与 ports.json 不一致：缺 {sorted(set(ids) - set(pb))}，多 {sorted(set(pb) - set(ids))}")
    for pid, e in pb.items():
        if pid in ids and e.get("name") != ids[pid]:
            bad.append(f"port_banners.{pid}.name「{e.get('name')}」≠ ports.json「{ids[pid]}」")
        if not isinstance(e.get("sub"), str) or not 0 < len(e.get("sub", "")) <= 14:
            bad.append(f"port_banners.{pid}.sub 须为 1–14 字")
    # 导入的背景都要真的用上
    for name, *_ in MANIFEST:
        if name not in used_cs_files:
            bad.append(f"assets/cutscene/{name} 导入了但数据里没用到")
    return bad


if __name__ == "__main__":
    if "--data-only" in sys.argv:
        sys.exit(check(data_only=True))
    if "--check" in sys.argv:
        sys.exit(check(data_only=False))
    sys.exit(run("--force" in sys.argv))
