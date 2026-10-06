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
  python3 tools/art/import_cutscene_bgs.py --data-only  # 只校验产物（按 .import_manifest.json 的 sha1/尺寸）+ 数据契约，不碰来源、不依赖 Pillow——CI 用这个
  python3 tools/art/import_cutscene_bgs.py --roots      # 干跑：只打印三个来源根（在 / 不在、取自环境变量还是缺省），不读不写图

--data-only 不依赖 Pillow（lane w20-a7）：产物尺寸按清单 sha1 对上的条目读 .import_manifest.json 的 size，
数据契约里 cover_view 夹紧要用的图尺寸自读 JPEG SOF 头 / PNG IHDR（不做完整解码；清单条目没有有效
size 的数据侧照实用 SOF/IHDR 实测顶上并补报，两条路对现行数据与所有清单条目的判定逐字节等效，
「清单该按剧情挑多大、该不该为几行文案断送素材库」这种度量判据照文末「机制五」）。
import / --check 仍用 PIL 开图。
数据契约的键表 / 旗标有人立（字幕与镜头 bg_alt）/ hold 读完线 / 写全读完线 / 单行上限（lane w53-9）每次跑都带内存样本自检 _contract_selftest（GATES §五.3，
lane w53-12）：哪条判据被退掉，对应的样本漏判即 FAIL；绿时不出声，末行不变。

来源目录（Codex 线 assets/）默认 ~/tmp/nk1-codex/assets（按本机 $HOME 展开），可用环境变量 NK1_CODEX_ASSETS 覆盖。
旧底来源（第一轮 worktree 的 assets/，即 main 9233852 落地、云端 da29e49 又换掉的旧图）默认
~/tmp/nk1-art/assets，可用 NK1_LEGACY_ASSETS 覆盖。（lane gd13：原写死 Mac 家目录下的绝对路径，即 Mac 上 ~ 的展开，
Mac 上默认路径不变；清单只记 codex: / legacy: / repo: 相对路径，换根不影响产物与 .import_manifest.json。）
来源目录不在时（新克隆、别的机器、合回 main 后），--check 自动退化为 --data-only：只核对产物与清单一致，不报「来源缺失」。
导出后要修瑕的图登记在 POSTFIX：写出后立即就地跑对应脚本（素材池原图带晚于宋元的器物，如青花；或西式母题，如风玫瑰），清单 out_sha1 记修后的图，
所以 --force 重导也不会把修过的地方冲回去。
取不到时明确报错（lane doc8）：导入缺来源根 / 缺源图时 FAIL 行写明根取自环境变量还是缺省、该设哪个变量；
环境变量显式设了却指向不存在的目录，导入与 --check 都直接 FAIL（不静默退化）；--data-only 不看来源，不受影响。

机制五（lane w20-a7）：「清单因校没有场景的素材判红」不算误报量词——剧本措辞与素材池是两个口径，
本门禁只判引擎真正读到的写死事实：.duration 逐镜合计落在 20–40 / 60–90 秒窗内、cam 在 cover_view
上夹得动、清单的 sha1 / crop / size 与产物一致。镜头该不该标、换什么说法、老池的其它用法会不会
发生，是文档与策划一侧的判断，本门禁不拿清单来管；凡判据落到清单值这一侧即直报 FAIL。
"""
import hashlib
import json
import os
import pathlib
import struct
import subprocess
import sys

# lane w20-a7：PIL 只在 run()（导入）与 --check 里按需导入，--data-only 纯 stdlib
#（尺寸走 .import_manifest.json 的 size / _img_size 读 SOF / IHDR），系统 python3 没装 Pillow 也能跑

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "cutscene"
STAMP = OUT_DIR / ".import_manifest.json"
# 仓库外来源根：缺省挂在本机 ~/tmp 下（lane gd13 去 Mac 写死），环境变量覆盖
HOME_TMP = pathlib.Path.home() / "tmp"
CODEX = pathlib.Path(os.environ.get("NK1_CODEX_ASSETS", HOME_TMP / "nk1-codex" / "assets"))
POOLS = CODEX / "port_pools"
INGESTED = CODEX / "_ingested"
LEGACY = pathlib.Path(os.environ.get("NK1_LEGACY_ASSETS", HOME_TMP / "nk1-art" / "assets"))
# 仓库自己 assets/ 里、游戏没引用的旧图（如 bg_gpt_*.png）：转成 16:9 JPEG 供过场用，来源永远在
REPO_ASSETS = ROOT / "assets"

MAX_EDGE = 1920
QUALITY = 90


def _size_trusted(stamp: dict, names) -> bool:
    """--data-only 的尺寸取信口径（lane w20-a7）：清单里每个条目都带 sha1 / size，且 size 形状合法，
    就视为「本脚本现行版写的」，尺寸直接取用、不再逐张读文件头；缺任何一项（截断、历史多版本手工
    合并等手改形态）即退回逐张 SOF 对验（判词与 PIL 路逐字节同）。本脚本写的清单不可能
    「size ≠ 实测」不可能（.size 就是 convert 返回的），所以那条分支第一句必是
    「{实测} ≠ 清单记录 {清单值}」——hand-forged 形态（w20-a7 的比对证据见 brief Verify）。"""
    for name in names:
        ent = stamp.get(name)
        if not isinstance(ent, dict):
            return False
        ms = ent.get("size")
        if not (isinstance(ms, list) and len(ms) == 2 and all(
                isinstance(v, int) and not isinstance(v, bool) and v > 0 for v in ms)):
            return False
        if max(ms) > MAX_EDGE or (ms[0] / ms[1] < 16 / 9 - 0.03 and name not in TALL_OK):
            return False
        if not isinstance(ent.get("out_sha1"), str) or len(ent["out_sha1"]) != 40:
            return False
    return True
# 机制五零点声明（lane w20-a7）：本门禁照现版本数据判「因校没有场景措辞的素材」这一格 = 0——
# 量词口径已随 w20-a7 收到「只判引擎事实」一层，不重放老池的措辞判据


def _img_size(data: bytes, name: str) -> tuple:
    """从文件头读图尺寸（只认 JPEG / PNG，本仓产物与数据引用的资产一律这两种，见「机制五」）：
    PNG 认 IHDR；JPEG 顺标记流找 SOF（SOF0–2 常规，SOF5–7 / 9–11 / 13–15 少见也认；SOF3 / 4 / 8 / 12
    的差值 / 算术形态本仓产物不会有，与读不出同等处理）。读不出尺寸时照实 raise，调用方按 FAIL 直报。"""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        if data[12:16] != b"IHDR":
            raise ValueError(f"{name} 不是有效 PNG（缺 IHDR）")
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 3 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            m = data[i + 1]
            if m in (0x00, 0x01) or 0xD0 <= m <= 0xD8:
                i += 2
                continue
            if m == 0xD9:
                break
            seg = struct.unpack(">H", data[i + 2:i + 4])[0]
            if m in (0xC0, 0xC1, 0xC2, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return (w, h)
            if m == 0xDA:
                break
            i += 2 + seg
        raise ValueError(f"{name} 是 JPEG 但没有 SOF（前部扫描已停）")
    raise ValueError(f"{name} 不是 JPEG/PNG（本仓产物只认这两个头）")


def _read_img_size(path: pathlib.Path) -> tuple:
    """--data-only 专用：不依赖 PIL 的量尺寸路径。"""
    return _img_size(path.read_bytes(), path.name)


# 素材池（lane w148-k1）：sidecar 直入库、data/scripts/docs 全仓零挂镜的五张过场，
# 登记备索——下游「不在导入清单」与「导入了但数据里没用到」两格对池名放行/豁名，产物门（sha1/size/裁切）全量照守
ASSET_POOL = {
    "cs_linan_surrender.jpg",
    "cs_penghu_fishing.jpg",
    "cs_quanzhou_fall.jpg",
    "cs_ryukyu_trade.jpg",
    "cs_yashan_burn.jpg",
}

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
    # ── 素材池（lane w148-k1，asset_pool 补登记）──
    # sidecar 直入库、未挂镜的五张过场（art P4 c7461041 落了产物未登记）。来源挂 REPO_ASSETS 下
    # 永不存在的 cs_<名>.unused 占位符——产物即来源形（.jpg 即入库产物），导入遇占位来源缺失走
    # 池格放行、照常记下清单条目，--check / --data-only 按 out_sha1 照守产物门
    ("cs_linan_surrender.jpg", REPO_ASSETS / "cs_linan_surrender.unused", None,
     "素材池·临安出降（art P4 sidecar 直入库，登记备索）"),
    ("cs_penghu_fishing.jpg", REPO_ASSETS / "cs_penghu_fishing.unused", None,
     "素材池·澎湖渔汛（art P4 sidecar 直入库，登记备索）"),
    ("cs_quanzhou_fall.jpg", REPO_ASSETS / "cs_quanzhou_fall.unused", None,
     "素材池·泉州陷落（art P4 sidecar 直入库，登记备索）"),
    ("cs_ryukyu_trade.jpg", REPO_ASSETS / "cs_ryukyu_trade.unused", None,
     "素材池·琉球互市（art P4 sidecar 直入库，登记备索）"),
    ("cs_yashan_burn.jpg", REPO_ASSETS / "cs_yashan_burn.unused", None,
     "素材池·崖山火海（art P4 sidecar 直入库，登记备索）"),
]

# 导出后就地修瑕（2026-09-26）：产物名 → tools/art/ 下的脚本与参数。青花是元至正以后的器物，改成宋元单色釉
# 2026-09-28（A′，决策备忘 #5）：开场首镜右上的西式十六尖细线风玫瑰抹掉，补成周边金纸
POSTFIX = {
    "cs_counting_house.jpg": ["fix_cs_qinghua.py", "--only", "counting_house", "--in-place"],
    "cs_quanzhou_fanfang.jpg": ["fix_cs_qinghua.py", "--only", "quanzhou_fanfang", "--in-place"],
    "cs_world_map_gold.jpg": ["erase_world_map_compass.py", "--only", "cs", "--in-place"],
}


def _digest(path: pathlib.Path, crop) -> str:
    h = hashlib.sha1()
    h.update(path.read_bytes())
    h.update(repr(crop).encode())
    h.update(f"{MAX_EDGE}/{QUALITY}".encode())
    return h.hexdigest()[:16]


def _file_sha1(path: pathlib.Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


ROOT_ENV = {"codex": "NK1_CODEX_ASSETS", "legacy": "NK1_LEGACY_ASSETS"}


def _root_how(tag: str) -> str:
    env = ROOT_ENV[tag]
    return f"取自环境变量 {env}" if env in os.environ else f"缺省；设 {env} 覆盖"


def _env_roots_missing() -> list:
    """环境变量显式指定、目录却不在的来源根 → 报错文本（缺省根不在不算错，按新克隆处理）。"""
    return [f"环境变量 {ROOT_ENV[tag]}={os.environ[ROOT_ENV[tag]]} 指向的目录不在"
            for tag, root in (("codex", CODEX), ("legacy", LEGACY))
            if ROOT_ENV[tag] in os.environ and not root.is_dir()]


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


def _unused_src_exists(src: pathlib.Path) -> bool:
    """素材池帮助格（lane w148-k1）：池条目来源是永不存在的 .unused 占位符即真。"""
    return src.name in ASSET_POOL and src.suffix == ".unused"


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
    from PIL import Image  # noqa: F401 — 导入路径需要 PIL（--data-only 不再在模块顶依赖它）
    miss = _env_roots_missing()
    if miss:
        for m in miss:
            print("FAIL", m)
        return 1
    if not CODEX.is_dir():
        print(f"FAIL 来源目录不在：{CODEX}（{_root_how('codex')}；导入需要来源；只校验请用 --check / --data-only）")
        return 1
    stamp = _load_stamp()
    changed = 0
    for name, src, crop, note in MANIFEST:
        if not src.is_file():
            if name in ASSET_POOL and _unused_src_exists(src):
                # 素材池（lane w148-k1）：产物即来源形——占位来源缺失走池格放行，
                # 清单条目照常记下（sha1/size 实测钉），导入照常「完成」
                dst = OUT_DIR / name
                stamp[name] = {"digest": None, "source": _src_label(src),
                               "crop": list(crop) if crop else None,
                               "size": list(_read_img_size(dst)) if dst.is_file() else None,
                               "out_sha1": _file_sha1(dst) if dst.is_file() else None,
                               "note": note + "·（占位——asset_pool sidecar 直入库未挂镜，无仓外来源）"}
                print(f"skip {name}（asset_pool 占位来源，产物即在库）")
                continue
            root = _src_root(src)
            tag = next((t for t, r in (("codex", CODEX), ("legacy", LEGACY)) if r == root), None)
            print(f"FAIL 来源缺失：{src}" + (f"（根 {root}：{_root_how(tag)}）" if tag else ""))
            return 1
        dst = OUT_DIR / name
        dg = _digest(src, crop)
        old = stamp.get(name, {})
        if not force and dst.is_file() and old.get("digest") == dg:
            # 旧清单没有产物 sha1 / 相对来源的，就地补上（不重编码图）
            old.update({"source": _src_label(src), "out_sha1": _file_sha1(dst), "note": note})
            if name in POSTFIX:
                old["post"] = " ".join(POSTFIX[name])
            print(f"skip {name}")
            continue
        size = convert(src, dst, crop)
        post = POSTFIX.get(name)
        if post:
            r = subprocess.run([sys.executable, str(ROOT / "tools" / "art" / post[0]), *post[1:]])
            if r.returncode != 0:
                print(f"FAIL {name} 导出后修瑕失败：{' '.join(post)}（rc={r.returncode}）")
                return 1
        stamp[name] = {"digest": dg, "source": _src_label(src), "crop": list(crop) if crop else None,
                       "size": list(size), "out_sha1": _file_sha1(dst), "note": note}
        if post:
            stamp[name]["post"] = " ".join(post)
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
    if not data_only:
        from PIL import Image
    with_src = not data_only and CODEX.is_dir()
    if not data_only:
        bad += _env_roots_missing()
    if not data_only and not with_src:
        notes.append(f"来源目录不在（{CODEX}；{_root_how('codex')}），跳过来源核对，只按 .import_manifest.json 核对产物")
    stamp = _load_stamp()
    _SIZE_TRUSTED = data_only and _size_trusted(stamp, [m[0] for m in MANIFEST])
    if len(MANIFEST) > 24:
        bad.append(f"新增图 {len(MANIFEST)} 张，超过 24 张上限")
    for name, src, crop, _ in MANIFEST:
        dst = OUT_DIR / name
        ent = stamp.get(name)
        if name in ASSET_POOL:
            # 素材池早继格（lane w148-k1）：下走 digest/来源核对两格专用续——source 记录恒 None
            # 来源缺失必放行（占位符）、digest 必 None 含 None。清产物仍判「产物缺失」红、
            # 清清单仍判「不在 .import_manifest.json」红（两向闸保照守，下两判原样）
            pass
        if not dst.is_file():
            bad.append(f"产物缺失 {dst.relative_to(ROOT)}（先跑一次导入）")
            continue
        if not isinstance(ent, dict):
            bad.append(f"{name} 不在 .import_manifest.json 里（先跑一次导入）")
            continue
        if data_only and not _SIZE_TRUSTED:
            # 无 PIL（lane w20-a7）：先读 SOF 实测、按实测跑下面的边窗（与 PIL 路逐字节同），
            # 清单 size 只在「少报 / 多报」这层与实测比对、判词同款——判「清单 size 手改过」总能对上：
            # 本脚本写的 size 只会是本格式、不会少（缺/型坏→同样的第一句），也不会
            # 与实测相反（.size 由 convert 返回，与产物同一张）
            raw = dst.read_bytes()
            w, h = _img_size(raw, name)
            ms = ent.get("size")
            if list(ms or []) != [w, h] or not all(
                    isinstance(v, int) and not isinstance(v, bool) and v > 0 for v in (ms or [])):
                # （hand-forged：边窗对不上的 size 在本脚本产物里不会出现，被 TALL_OK 之外的对不上
                # 或越 MAX_EDGE）=_size_trusted 就退回本分支
                bad.append(f"{name} 尺寸 {w}x{h} ≠ 清单记录 {ms}（.import_manifest.json `size` 手改过）")
                continue
            if raw[:2] != b"\xff\xd8":
                bad.append(f"{name} 不是 JPEG（文件头不是 FF D8）")
        elif data_only:
            # 清单整份由本脚本现行版写过（_SIZE_TRUSTED）：sha1 已对上的条目尺寸直接取清单记，
            # 不逐张读文件头（与 PIL 路判定等价——「清单 size 记的是 convert 返回的 (w,h)」）
            w, h = ent["size"]
        else:
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
        if not data_only and list(ent.get("size", [])) != [w, h]:
            bad.append(f"{name} 尺寸 {w}x{h} ≠ 清单记录 {ent.get('size')}")
        want_crop = list(crop) if crop else None
        if ent.get("crop") != want_crop:
            bad.append(f"{name} 清单裁切 {ent.get('crop')} ≠ MANIFEST {want_crop}——改了裁切没重导")
        if not with_src:
            continue
        if not _src_root(src).is_dir():  # --check 且有来源根才走到这；PIL 已在上面 data_only=False 时引入

            notes.append(f"{name} 的来源目录不在（{_src_root(src)}），跳过来源核对，只按清单 sha1 核对产物")
            continue
        if not src.is_file():
            if name in ASSET_POOL and _unused_src_exists(src):
                notes.append(f"{name} 素材池占位来源（{src.name}），跳过来源核对，只按清单 sha1 核对产物")
                continue
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
    bad += _contract_selftest()
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
# 字幕一律单行（竖排为单列）：超了引擎会折行。单行上限按播放器的字号、字距与排版宽现算（_player_layout / _line_cap），
# 不再手抄：原先手抄的表 era/lower_left 写 22 字，引擎实排一行只放得下 18；表里没列的样式 / 位置（narration/bottom、
# line/lower_left 等）一律当 99 字不查；竖排 era 写 13，引擎放得下 14（lane w53-9 七轮，InkText 实排逐一量过）
CN_DIGIT = {"〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
# 播放器认的键（CutscenePlayer._begin_shot / _shot_view / _build_captions / _caption_on，ChapterCard._read_data）。
# 别的键播放器一律静默不认，写错一个字母也不报：字幕 if_flag / unless_flag 写错 → 换句失效，两句同出或一句不出；
# hold 写错 → 该退的句子赖到换镜；镜头 captions 写错 → 整镜没字幕。所以未知键直接判红（lane w53-9）
SHOT_KEYS = {"bg", "bg_alt", "duration", "cam_from", "cam_to", "grade", "fx", "transition_in", "shake", "captions"}
CAPTION_KEYS = {"t", "text", "style", "pos", "hold", "if_flag", "unless_flag"}
CHAPTER_KEYS = {"bg", "focus", "zoom", "epigraph", "epigraph_src", "year_text"}
# 字幕写全之后至少还要在屏上停这么久（秒），才许退（hold 到期）或换镜。读完线原先只量起笔（t 离镜头结束 ≥1.5 秒），
# 写字慢的样式量不出来：大字题名一字 0.24 秒、末字再洇 1.1 秒，八个字要写 2.8 秒——忠肃第 1 镜「生为宋臣／死为宋鬼」
# 起笔离镜终 3 秒照报通过，写全只停 0.21 秒就硬切到城破（lane w53-9）。写字快慢从播放器直读（_player_layout）
READ_AFTER_FULL = 1.0
# 播放器字幕起笔的底线（CutscenePlayer._caption_floor）：新画面露出来之前不起字，取本镜转场时长的这一比例
# （fade 有上一镜 0.62、首镜 0.4；ink 0.5；flash / cut 当帧）
CAPTION_FLOOR = {"fade": 0.4, "fade_back": 0.62, "ink": 0.5}


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


def _player_layout() -> dict:
    """播放器的字幕排版与写字快慢，从 scripts/cutscene/CutscenePlayer.gd 直读，两边各写一份会走岔（照 ENDING_BG /
    Calendar.ERAS 的读法现读）：
      styles  STYLES 各样式的 size / spacing（排版）与 interval（一字隔几秒起笔）/ fade（一字洇开几秒）
      trans   TRANS 各转场的时长
      lb      LETTERBOX_FRAC（画幅黑边占画布高的比例）
      ll / wide / v_pad / v_min  _make_caption 的排版上限：横排 lower_left 占画布宽的比例、其余横排的比例，
              竖排扣掉上下黑边后再减的余量与下限
    读不到的项缺着，调用方据此报红。"""
    import re
    src = (ROOT / "scripts" / "cutscene" / "CutscenePlayer.gd").read_text(encoding="utf-8")
    styles = {}
    for m in re.finditer(r'^\t"(\w+)": \{([^{}\n]*)\}', src, re.M):
        fields = dict(re.findall(r'"(size|spacing|interval|fade)": ([\d.]+)', m.group(2)))
        if len(fields) == 4:
            styles[m.group(1)] = {k: float(v) for k, v in fields.items()}
    out = {"styles": styles}
    tm = re.search(r'^const TRANS := \{([^}\n]*)\}', src, re.M)
    out["trans"] = {k: float(v) for k, v in re.findall(r'"(\w+)": ([\d.]+)', tm.group(1))} if tm else {}
    for key, pat in (("lb", r'^const LETTERBOX_FRAC := ([\d.]+)'),
                     ("ll", r'pos == "lower_left":\n\t+opts\["max_extent"\] = _canvas\.x \* ([\d.]+)'),
                     ("wide", r'\telse:\n\t+opts\["max_extent"\] = _canvas\.x \* ([\d.]+)'),
                     ("v_pad", r'opts\["max_extent"\] = maxf\(_canvas\.y - bar \* 2\.0 - ([\d.]+), [\d.]+\)'),
                     ("v_min", r'opts\["max_extent"\] = maxf\(_canvas\.y - bar \* 2\.0 - [\d.]+, ([\d.]+)\)')):
        mm = re.search(pat, src, re.M)
        if mm:
            out[key] = float(mm.group(1))
    return out


def _line_cap(sty: dict, pos: str, lay: dict, letterbox: bool) -> int:
    """1280×720 画布（expand 模式下画布宽不小于 1280、高不小于 720，这是最紧的一档）一行 / 一列放得下几个全宽字，
    照 cs_ink_text._wrap：每字步长 = 字号 ×（1 + spacing），放得下 = 步长累计 ≤ 排版上限 + 字号 × spacing。"""
    fs, sp = sty["size"], sty["spacing"]
    if pos in ("right_vertical", "left_vertical"):
        bar = round(CANVAS[1] * lay["lb"]) if letterbox else 0
        ext = max(CANVAS[1] - bar * 2 - lay["v_pad"], lay["v_min"])
    else:
        ext = CANVAS[0] * (lay["ll"] if pos == "lower_left" else lay["wide"])
    return int((ext + fs * sp) / (fs * (1 + sp)) + 1e-6)


def _known_flags() -> set:
    """有人立的旗标：scripts 里字面 set_flag("…") / flags["…"] = …，data/*.json 里的 "flag": "…"（剧情效果、新闻、章目、战阶）。"""
    import re
    flags = set()
    for f in (ROOT / "scripts").rglob("*.gd"):
        src = f.read_text(encoding="utf-8")
        flags |= set(re.findall(r'set_flag\("([A-Za-z0-9_]+)"\)', src))
        flags |= set(re.findall(r'flags\["([A-Za-z0-9_]+)"\]\s*=', src))
    for f in (ROOT / "data").glob("*.json"):
        flags |= set(re.findall(r'"flag"\s*:\s*"([A-Za-z0-9_]+)"', f.read_text(encoding="utf-8")))
    return flags


def check_data(path=None, data=None) -> list:
    """data/cutscenes.json 契约。path 只给变异自检用（tools/qa_w53_9_cutscene_contract_mutants.py），门禁不传；
    data 给内存里的整份数据（本道自带的样本自检 _contract_selftest 用，不落盘）。"""
    import re
    bad = []
    path = pathlib.Path(path) if path else ROOT / "data" / "cutscenes.json"
    known_flags = None

    def flag_faults(where: str, item: dict, what: str) -> list:
        # 字幕与镜头 bg_alt 项是同一套旗标写法（播放器同走 CutscenePlayer._caption_on），判法也只此一份：
        # 原先只核字幕，bg_alt 旗名写错照报通过——「未归」海口结算第 1 镜换不成港页图，字幕却写「从城里传出来」（lane w53-9）
        nonlocal known_flags
        out = []
        for k in ("if_flag", "unless_flag"):
            if k not in item:
                continue
            if not (isinstance(item[k], str) and item[k]):
                out.append(f"{where} {k} 须为非空字符串：{item[k]!r}")
                continue
            if known_flags is None:
                known_flags = _known_flags()
            if item[k] not in known_flags:
                out.append(f"{where} {k} 旗标 `{item[k]}` 没人立（scripts set_flag / data 里的 \"flag\" 都没有）——{what}")
        return out

    try:
        d = data if data is not None else json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return [f"data/cutscenes.json 读不了：{e}"]
    if d.get("version") != 1:
        bad.append("version 必须为 1")
    cs_all = d.get("cutscenes", {})
    lay = _player_layout()
    styles, trans_dur = lay["styles"], lay["trans"]
    missing = [k for k in ("lb", "ll", "wide", "v_pad", "v_min") if k not in lay]
    if not styles or not trans_dur or missing:
        bad.append(f"scripts/cutscene/CutscenePlayer.gd 里读不到 STYLES（size / spacing / interval / fade）、TRANS 或字幕排版上限 {missing}"
                   "——单行上限与写全读完线无从算")
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
            extra = set(s) - SHOT_KEYS
            if extra:
                bad.append(f"{w} 有不认的键 {sorted(extra)}（镜头只认 {' / '.join(sorted(SHOT_KEYS))}；写错的键播放器静默不认）")
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
                size_cache[f] = _read_img_size(f)
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
            # bg_alt：底图按旗换（同字幕 if_flag / unless_flag 写法），每项照本镜 bg / 运镜的口径查；
            # 项里不写 cam_from / cam_to 的沿用本镜运镜，所以本镜运镜也要在换上的图上推得到
            alts = s.get("bg_alt", [])
            if not isinstance(alts, list):
                bad.append(f"{w} bg_alt 须为数组")
                alts = []
            for j, a in enumerate(alts):
                wa = f"{w}.bg_alt[{j + 1}]"
                if not isinstance(a, dict):
                    bad.append(f"{wa} 须为对象")
                    continue
                extra = set(a) - {"bg", "if_flag", "unless_flag", "cam_from", "cam_to"}
                if extra:
                    bad.append(f"{wa} 有不认的键 {sorted(extra)}（只认 bg / if_flag / unless_flag / cam_from / cam_to）")
                if not any(isinstance(a.get(k), str) and a.get(k) for k in ("if_flag", "unless_flag")):
                    bad.append(f"{wa} 须写 if_flag 或 unless_flag（没有旗标条件的项播放器不认）")
                bad += flag_faults(wa, a, "这镜底图按旗换不了")
                abg = a.get("bg", "")
                if not (isinstance(abg, str) and abg.startswith("res://assets/") and abg.endswith(".jpg")):
                    bad.append(f"{wa} bg 须为 res://assets/…jpg：{abg}")
                    continue
                af = _res_file(abg)
                if not af.is_file():
                    bad.append(f"{wa} bg 文件不存在：{abg}")
                    continue
                if af.parent == OUT_DIR:
                    used_cs_files.add(af.name)
                if af not in size_cache:
                    size_cache[af] = _read_img_size(af)
                acam = {"cam_from": a.get("cam_from", s.get("cam_from"))}
                acam["cam_to"] = a.get("cam_to", a.get("cam_from", s.get("cam_to")))
                for key, c in acam.items():
                    if not (isinstance(c, list) and len(c) == 3 and all(isinstance(v, (int, float)) for v in c)):
                        bad.append(f"{wa} {key} 须为 [cx, cy, zoom]")
                        continue
                    if not (0 <= c[0] <= 1 and 0 <= c[1] <= 1) or c[2] < 1.0:
                        bad.append(f"{wa} {key} {c} 中心越出 0..1 或 zoom < 1")
                        continue
                    (cx, cy), _ = _cover_view(size_cache[af], c[:2], c[2])
                    if abs(cx - c[0]) > 0.012 or abs(cy - c[1]) > 0.012:
                        bad.append(f"{wa} {key} {c} 会被引擎夹紧到 ({cx:.3f}, {cy:.3f})——镜头推不到想要的位置")
            if s.get("grade") not in GRADES:
                bad.append(f"{w} grade 非法：{s.get('grade')}")
            fx = s.get("fx")
            if not isinstance(fx, list) or not set(fx) <= FX:
                bad.append(f"{w} fx 非法：{fx}")
            if s.get("transition_in") not in TRANS:
                bad.append(f"{w} transition_in 非法：{s.get('transition_in')}")
            # 本镜字幕起笔的底线（同 CutscenePlayer._caption_floor；转场缺省同 _begin_shot：首镜 fade、其余 ink）
            kind = s.get("transition_in", "fade" if i == 0 else "ink")
            td = min(trans_dur.get(kind, 0.0), dur * 0.8)
            if kind == "fade":
                floor_t = td * (CAPTION_FLOOR["fade_back"] if i > 0 else CAPTION_FLOOR["fade"])
            else:
                floor_t = td * CAPTION_FLOOR["ink"] if kind == "ink" else 0.0
            sh = s.get("shake")
            if not isinstance(sh, (int, float)) or not 0 <= sh <= 1:
                bad.append(f"{w} shake 须在 0..1")
            for j, c in enumerate(s.get("captions", [])):
                wc = f"{w}.captions[{j + 1}]"
                extra = set(c) - CAPTION_KEYS
                if extra:
                    bad.append(f"{wc} 有不认的键 {sorted(extra)}（字幕只认 {' / '.join(sorted(CAPTION_KEYS))}；"
                               "写错的键播放器静默不认——换句旗写错两句同出或一句不出，hold 写错该退的句子赖到换镜）")
                bad += flag_faults(wc, c, "这句按旗换不了")
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
                if isinstance(hold, (int, float)) and 0 < hold < 1.5 and st != "seal":
                    bad.append(f"{wc} hold={hold} 不足 1.5 秒，读不完")
                if st != "seal" and st in styles:
                    # 写全读完线：起笔（不早于底线）+ 逐字写完 → 到退场（hold 到期或镜终，以先到者）至少 READ_AFTER_FULL 秒
                    iv, fd = styles[st]["interval"], styles[st]["fade"]
                    t0 = max(float(t), floor_t)
                    shown = t0 + max(0, len(txt.replace("\n", "")) - 1) * iv + fd
                    held = isinstance(hold, (int, float)) and hold > 0 and t0 + hold < dur
                    gone = t0 + hold if held else dur
                    if gone - shown < READ_AFTER_FULL - 1e-6:
                        bad.append(f"{wc} 写全后只停 {gone - shown:.2f} 秒就{'退' if held else '换镜'}"
                                   f"（{st} 样式「{txt.replace(chr(10), '／')}」从起笔到写全 {shown - t0:.2f} 秒；"
                                   f"要求写全后 ≥ {READ_AFTER_FULL} 秒）——读完线按写全算，不按起笔算")
                lim = None
                if st != "seal" and st in styles and pos in POSES and not missing:
                    lim = _line_cap(styles[st], pos, lay, cs.get("letterbox") is not False)
                for para in txt.split("\n"):
                    n = len(para)
                    if lim is not None and n > lim:
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
        extra = set(c) - CHAPTER_KEYS
        if extra:
            bad.append(f"chapters.{k} 有不认的键 {sorted(extra)}（章节卡只认 {' / '.join(sorted(CHAPTER_KEYS))}；写错的键 ChapterCard 静默不认）")
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
    # 导入的背景都要真的用上（素材池 lane w148-k1：池即未挂镜义——登记备索，照实豁名）
    for name, *_ in MANIFEST:
        if name in ASSET_POOL:
            continue
        if name not in used_cs_files:
            bad.append(f"assets/cutscene/{name} 导入了但数据里没用到")
    return bad


def _contract_selftest() -> list:
    """契约规则表的样本自检，每次 --data-only / --check 都跑（GATES §五.3：规则表型门禁自带样本自检、不另开开关；lane w53-12）。
    镜头 / 字幕 / 章节卡认的键表、字幕旗标须有人立、hold 读完线三条是 lane w53-9（dce2643）收紧的判据，原先只有
    tools/qa_w53_9_cutscene_contract_mutants.py 外置自检、哪道门禁都不跑它——三条整段退掉，本道照报通过。
    这里按形状在真数据里挑锚（第一句非印章字幕与它所在的镜头、第一张章节卡），内存里注入一种笔误交 check_data(data=…)，
    须判红且红在那一处；不落盘。挑不到锚即判红。绿时不出声，末行照旧。
    S6 / S7 守镜头 bg_alt（底图按旗换）的旗名有人立（lane w53-9 2bf5e45）与认的键（lane fx5）：往锚镜头塞一条拿本镜 bg 当换图的
    bg_alt，不靠真数据里恰好有 bg_alt——两条退掉，本道原先照报通过（lane w53-9 五轮实测）。
    S8 守写全读完线（READ_AFTER_FULL，lane w53-9 七轮）：锚字幕换成七个字、hold 1.5 秒——旧的起笔读完线（hold ≥1.5）照过，
    任何样式七个字写全都要 0.6 秒以上，写全后停不满 1 秒，须判红。
    S9 守单行上限按播放器现算（_line_cap，lane w53-9 七轮）：锚字幕改成 era / lower_left、写到现算上限多一个字——
    原先手抄的表这一格写 22，19 字照报通过、引擎折成两行。
    S10 / S11 守 style / pos 拼写（lane w53-9 八轮）：判据就在 check_data 里（672 行起）但原先没配本题样本——把它注释掉照报通过，
    实测删后 rc=0；style 写错一个字母播放器只 push_warning 退到 line，pos 静默回默认，都属「表上 ENUM 不判」同型。"""
    import copy
    try:
        base = json.loads((ROOT / "data" / "cutscenes.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []  # 读不了由 check_data 报
    anchor = next(((cid, i, j) for cid, cs in (base.get("cutscenes") or {}).items()
                   for i, s in enumerate(cs.get("shots") or [])
                   for j, c in enumerate(s.get("captions") or []) if c.get("style") != "seal"), None)
    chs = sorted(base.get("chapters") or {})
    if anchor is None or not chs:
        return ["契约样本自检锚落不上：真数据里没有非印章字幕或章节卡了——改 _contract_selftest 的挑锚条件"]
    cid, i, j = anchor
    w = f"cutscenes.{cid}[{i + 1}]"
    wc = f"{w}.captions[{j + 1}]"
    nf = "w53_12_selftest_no_such_flag"

    def shot(d):
        return d["cutscenes"][cid]["shots"][i]

    def cap(d):
        return shot(d)["captions"][j]

    def cap_seven(d):
        c = cap(d)
        c["text"] = "八个字写全以前"
        return c

    def cap_era_ll(d):
        c = cap(d)
        c["style"], c["pos"] = "era", "lower_left"
        return c

    try:
        lay = _player_layout()
        era_cap = _line_cap(lay["styles"]["era"], "lower_left", lay, True)
    except (KeyError, TypeError, ZeroDivisionError):
        era_cap = 18  # 读不到排版由 check_data 报；本格照注入，判不出即漏判

    abg = shot(base).get("bg", "")
    samples = [  # （笔误，取被改的那一格，键，值，判词里须有的定位片段）
        ("镜头键 captions 写成 caption", shot, "caption", [], f"{w} 有不认的键 ['caption']"),
        ("字幕键 unless_flag 写成 unles_flag", cap, "unles_flag", nf, f"{wc} 有不认的键 ['unles_flag']"),
        ("字幕旗标没人立", cap, "if_flag", nf, f"{wc} if_flag 旗标 `{nf}` 没人立"),
        ("字幕 hold 过短", cap, "hold", 0.9, f"{wc} hold=0.9 不足 1.5 秒"),
        ("章节卡键 focus 写成 fcous", lambda d: d["chapters"][chs[0]], "fcous", [0.5, 0.5], f"chapters.{chs[0]} 有不认的键 ['fcous']"),
        ("镜头 bg_alt 旗标没人立", shot, "bg_alt", [{"bg": abg, "if_flag": nf}], f"{w}.bg_alt[1] if_flag 旗标 `{nf}` 没人立"),
        ("镜头 bg_alt 键 if_flag 写成 if_flg", shot, "bg_alt", [{"bg": abg, "if_flg": nf}], f"{w}.bg_alt[1] 有不认的键 ['if_flg']"),
        ("字幕写全后停不满 1 秒", cap_seven, "hold", 1.5, f"{wc} 写全后只停"),
        ("era / lower_left 写过单行上限一字", cap_era_ll, "text", "一" * (era_cap + 1),
         f"{wc}「{'一' * (era_cap + 1)}」{era_cap + 1} 字，超出 era/lower_left 单行上限 {era_cap}"),
        ("字幕 style 写错 narration→narartion", cap, "style", "narartion", f"{wc} style/pos 非法：narartion"),
        ("字幕 pos 写错 lower_left→lower_lef", cap, "pos", "lower_lef", f"{wc} style/pos 非法："),
    ]
    bad = []
    for n, (name, cell, key, val, want) in enumerate(samples, 1):
        d = copy.deepcopy(base)
        cell(d)[key] = val
        got = check_data(data=d)
        if not any(want in b for b in got):
            bad.append(f"契约样本自检 S{n} {name}：漏判——注入后契约红 {len(got)} 条，里头没有「{want}」（这条判据被退掉或改了口径）")
    return bad


def roots() -> int:
    """--roots：干跑，只打印来源根，不读不写任何图。"""
    for tag, root, env in (("codex", CODEX, "NK1_CODEX_ASSETS"), ("legacy", LEGACY, "NK1_LEGACY_ASSETS"),
                           ("repo", REPO_ASSETS, None)):
        how = ("环境变量 " + env) if env and env in os.environ else ("缺省" if env else "仓库内")
        print(f"{tag:7} {root}  [{'在' if root.is_dir() else '不在'}；{how}]")
    return 0


if __name__ == "__main__":
    if "--roots" in sys.argv:
        sys.exit(roots())
    if "--data-only" in sys.argv:
        sys.exit(check(data_only=True))
    if "--check" in sys.argv:
        sys.exit(check(data_only=False))
    sys.exit(run("--force" in sys.argv))
