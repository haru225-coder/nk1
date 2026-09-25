#!/usr/bin/env python3
"""字体子集化（fontTools）。可重复运行。

字符集 = GB2312 全部 + 仓库 data/ scripts/ scenes/ docs/ 下出现的全部字符
        + GIT_SOURCES 里别的分支已提交文件的全部字符（git show 读，不切分支；海图重制的繁体地名在这里）
        + ASCII / Latin-1 / 全角 / CJK 标点 / 常用符号 / 假名。
写完自动逐字校验（fontTools 读输出子集的 cmap）：正文字体对全部来源字符零漏字，源字体本身没有的字单列；
马善政只核标题 / 印章用字，缺字单列（运行时 fallback 到文楷）。
源字体从 --src（默认 $NK1_FONT_SRC，再默认 ~/tmp/nk1-art-work/fonts_src/）读，输出到 assets/fonts/，
文件名保持不变（代码只按固定路径引用）：
  res://assets/fonts/LXGWWenKai-Medium.ttf    正文（霞鹜文楷 Medium 1.522 的子集化修改版，内部名已改为 NK1 Body Kai）
  res://assets/fonts/MaShanZheng-Regular.ttf  书法标题（马善政楷书 2.003 子集；上游未声明保留字体名，名字不动）

源字体（上游原版，sha256 已与本机备份逐字节比对一致）：
  LXGWWenKai-Medium.ttf    v1.522  https://github.com/lxgw/LxgwWenKai/releases/tag/v1.522
  MaShanZheng-Regular.ttf  v2.003  https://github.com/google/fonts/tree/main/ofl/mashanzheng
缺源字体时加 --download 自动取回并校验 sha256（换机器 / 清掉 ~/tmp 之后用）。

许可（OFL 1.1 §3 + 霞鹜文楷附加许可）：文楷保留字体名 '霞鹜' '霞鶩' '落霞孤鹜' '落霞孤鶩' 'LXGW'，
附加许可只放行「不改源码重编译」与「纯网页字体分发的子集」。本子集嵌入游戏发行，属修改版，
故子集化后改写 name 表 ID 1/3/4/6/16/17（全部平台与语言）为 NK1 Body Kai；版权行 ID 0、作者 ID 8/9 原样保留。

用法：
  python3 tools/art/subset_fonts.py                 # 默认源目录
  python3 tools/art/subset_fonts.py --src DIR       # 指定原始字体目录
  python3 tools/art/subset_fonts.py --download      # 源目录缺字体时从上游下载并校验 sha256
  python3 tools/art/subset_fonts.py --extra DIR ... # 额外扫描目录（例如新剧本）
  python3 tools/art/subset_fonts.py --check         # 只检查仓库文本是否有字形缺失，不写文件
  python3 tools/art/subset_fonts.py --verify        # 只逐字校验现有子集（不写文件）

新剧情文本落地后重跑一次即可；缺字的会在输出里列出（运行时会走系统字体兜底，风格会不一致）。
"""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_SRC = pathlib.Path(os.environ.get("NK1_FONT_SRC", pathlib.Path.home() / "tmp" / "nk1-art-work" / "fonts_src"))
OUT = ROOT / "assets" / "fonts"
FONTS = ["LXGWWenKai-Medium.ttf", "MaShanZheng-Regular.ttf"]
# 上游出处：版本、下载地址、sha256（2026-09-25 下载核对）
UPSTREAM = {
    "LXGWWenKai-Medium.ttf": {
        "version": "1.522",
        "url": "https://github.com/lxgw/LxgwWenKai/releases/download/v1.522/LXGWWenKai-Medium.ttf",
        "sha256": "d4bdeb38a39151d74d084cba5090f8cb7d20bf83eedb78c35939ae70b9f4e3f6",
    },
    "MaShanZheng-Regular.ttf": {
        "version": "2.003",
        "url": "https://github.com/google/fonts/raw/main/ofl/mashanzheng/MaShanZheng-Regular.ttf",
        "sha256": "6d2546bb189c732a8ca29af9e22457b152387d158aa459e4ac2ce1e51788b7fb",
    },
}
# OFL §3：修改版不得再用保留字体名作主名。只改「字体名」类记录，版权 / 作者 / 网址不动。
RENAME = {
    "LXGWWenKai-Medium.ttf": {
        "reserved": ("LXGW", "霞鹜", "霞鶩", "落霞孤鹜", "落霞孤鶩"),
        "ids": {
            1: "NK1 Body Kai Medium",
            3: "NK1BodyKai-Medium:1.522:nk1-subset",
            4: "NK1 Body Kai Medium",
            6: "NK1BodyKai-Medium",
            16: "NK1 Body Kai",
            17: "Medium",
            # 19 是示例文字（「落霞与孤鹜齐飞」），不算字体名；换成本作用字，免得有人误会
            19: "泉州港 · 市舶司 · 蕃舶云集",
        },
    },
}
SCAN_DIRS = ["data", "scripts", "scenes", "docs"]
# Codex 线（Snow 另一条线）的考据与数据：其他美术/剧情线可能直接搬用其中人名地名，
# 顺带收进子集（目录不存在就跳过，只多约十几个字）。
DEFAULT_EXTRA = [
    pathlib.Path.home() / "tmp" / "nk1-codex" / "historical_data",
    pathlib.Path.home() / "tmp" / "nk1-codex" / "data",
]
# 别的分支上已提交、尚未合进本线的文本（git show 读取，不切分支）。
# 海图重制（feat/chart-remake-cloud，815439a 起）：海图地名一律繁体旧字形（興化、慶元、嶼…约 227 字），
# 写在 data/chart_labels.json 与 data/ports.json 的 chart.label / chart.sub；顺带收该分支改过的海图脚本与设计文档。
# 目录项（以 / 结尾）按 git ls-tree 展开。ref 不在（别的克隆、分支已删）时打 NOTE 跳过。
GIT_SOURCES = {
    "feat/chart-remake-cloud": [
        "data/chart_labels.json", "data/ports.json",
        "data/chapters.json", "data/discoveries.json", "data/sealanes.json", "data/chart_projection.json",
        "scripts/SeaChart.gd", "scripts/chart/", "docs/海图重制设计_2026-09-25.md",
    ],
}
TEXT_EXT = {".json", ".gd", ".tscn", ".md", ".txt", ".tres", ".cfg", ".csv"}


def gb2312_chars() -> set:
    out = set()
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                ch = bytes([hi, lo]).decode("gb2312")
            except UnicodeDecodeError:
                continue
            out.add(ch)
    return out


def range_chars(a: int, b: int) -> set:
    return {chr(c) for c in range(a, b + 1)}


def base_chars() -> set:
    s = set()
    s |= range_chars(0x20, 0x7E)        # ASCII
    s |= range_chars(0xA0, 0xFF)        # Latin-1（·、×、÷、°）
    s |= range_chars(0x2010, 0x205E)    # 常用标点（—、…、‖、‘’“”、※）
    s |= range_chars(0x2160, 0x216B)    # 罗马数字
    s |= range_chars(0x2190, 0x2199)    # 箭头
    s |= range_chars(0x2460, 0x2473)    # ①–⑳
    s |= range_chars(0x2500, 0x257F)    # 制表线（──）
    s |= range_chars(0x25A0, 0x25CF)    # ■□▲△◆◇○●
    s |= range_chars(0x2600, 0x2610)    # ★☆
    s |= range_chars(0x3000, 0x303F)    # CJK 标点（、。〈〉《》「」『』【】〔〕）
    s |= range_chars(0x3040, 0x30FF)    # 假名（博多、日本人名；・U+30FB）
    s |= range_chars(0xFE30, 0xFE4F)    # 竖排标点兼容形
    s |= range_chars(0xFF01, 0xFF5E)    # 全角 ASCII
    s |= range_chars(0xFF5F, 0xFF65)    # 全角括号、半角句读
    s |= range_chars(0xFFE0, 0xFFE6)    # 全角 ¢£¥
    return s


def repo_chars(dirs) -> set:
    s = set()
    for d in dirs:
        base = pathlib.Path(d)
        if not base.is_absolute():
            base = ROOT / d
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.is_file() and p.suffix.lower() in TEXT_EXT and ".godot" not in p.parts:
                try:
                    s |= set(p.read_text(encoding="utf-8"))
                except (UnicodeDecodeError, OSError):
                    pass
    # 控制字符与代理区不进子集
    return {c for c in s if ord(c) >= 0x20 and not (0xD800 <= ord(c) <= 0xDFFF)}


def _git(args: list, cwd: pathlib.Path) -> str:
    r = subprocess.run(["git", "-C", str(cwd)] + args, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode("utf-8", "replace").strip())
    return r.stdout.decode("utf-8", "replace")


def git_chars(notes: list) -> tuple:
    """GIT_SOURCES 里各分支文件的全部字符；返回 (字符集, {来源: 字符集})。"""
    cwd = pathlib.Path(os.environ.get("NK1_GIT_DIR", ROOT))
    out, per = set(), {}
    for ref, paths in GIT_SOURCES.items():
        try:
            _git(["rev-parse", "--verify", "--quiet", ref], cwd)
        except RuntimeError:
            notes.append(f"git ref {ref} 不在（{cwd}），跳过该分支的补字来源")
            continue
        files = []
        for p in paths:
            if p.endswith("/"):
                files += [f for f in _git(["ls-tree", "-r", "--name-only", ref, "--", p], cwd).splitlines()
                          if pathlib.Path(f).suffix.lower() in TEXT_EXT]
            else:
                files.append(p)
        for f in files:
            try:
                txt = _git(["show", f"{ref}:{f}"], cwd)
            except RuntimeError:
                notes.append(f"{ref}:{f} 读不到，跳过")
                continue
            cs = {c for c in txt if ord(c) >= 0x20 and not (0xD800 <= ord(c) <= 0xDFFF)}
            per[f"{ref}:{f}"] = cs
            out |= cs
    return out, per


def _json(path: pathlib.Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def title_chars(extra_git: dict) -> dict:
    """马善政（书法标题字体）实际要写的字：过场标题 / 印文、章节卡、抵港横幅港名、章名、港名、游戏名、人名。
    海图地名（繁体）单列——海图若用马善政写地名才需要。"""
    out = {}
    cs = _json(ROOT / "data" / "cutscenes.json")
    caps = [c.get("text", "") for v in cs.get("cutscenes", {}).values() for s in v.get("shots", [])
            for c in s.get("captions", []) if c.get("style") in ("title", "seal")]
    out["过场 title/seal 字幕"] = "".join(caps)
    out["抵港横幅港名"] = "".join(v.get("name", "") for v in cs.get("port_banners", {}).values())
    out["章节卡 第X章 + 印文"] = "第一二三四五章立志泊"
    out["章名"] = "".join(c.get("name", "") for c in _json(ROOT / "data" / "chapters.json").get("chapters", []))
    out["港名"] = "".join(p.get("name", "") for p in _json(ROOT / "data" / "ports.json").get("ports", []))
    out["游戏名"] = "东亚海域立志传"
    out["人名（立绘卡 / 人物志）"] = "".join(c.get("name", "") for c in
                                     _json(ROOT / "data" / "characters.json").get("characters", []))
    chart = set()
    for k, v in extra_git.items():
        if k.endswith(("chart_labels.json", "ports.json")):
            chart |= v
    out["海图地名（海图重制分支，参考）"] = "".join(sorted(chart))
    return out


def is_han(c: str) -> bool:
    o = ord(c)
    return 0x3400 <= o <= 0x9FFF or 0xF900 <= o <= 0xFAFF or o >= 0x20000


def verify(src: pathlib.Path, repo: set, gitc: set, per_git: dict) -> int:
    """逐字核对输出子集：正文字体须覆盖全部来源字符（源字体本身没有的单列）；马善政只核标题 / 印章用字。"""
    rc = 0
    body = OUT / FONTS[0]
    sub_cmap = TTFont(str(body), lazy=True).getBestCmap()
    src_cmap = TTFont(str(src / FONTS[0]), lazy=True).getBestCmap()
    need = {c for c in (repo | gitc) if not c.isspace() and ord(c) < 0x1F000}
    lost = sorted(c for c in need if ord(c) in src_cmap and ord(c) not in sub_cmap)
    absent = sorted(c for c in need if ord(c) not in src_cmap)
    chart_need = set()
    for k, v in per_git.items():
        if k.endswith(("chart_labels.json", "ports.json")):
            chart_need |= v
    chart_han = {c for c in chart_need if is_han(c)}
    print(f"\n[校验 {FONTS[0]}] 来源字符 {len(need)}（其中海图分支 chart_labels/ports 汉字 {len(chart_han)}），"
          f"子集 cmap {len(sub_cmap)}")
    print(f"  子集漏字（源字体有、子集没有）：{len(lost)} {''.join(lost)}")
    if lost:
        rc = 1
    print(f"  源字体本身没有：{len(absent)} {''.join(absent)}"
          f"{'（其中汉字 ' + ''.join(c for c in absent if is_han(c)) + '）' if any(is_han(c) for c in absent) else '（无汉字）'}")
    if any(is_han(c) for c in absent):
        rc = 1
    ch_lost = sorted(c for c in chart_han if ord(c) not in sub_cmap)
    print(f"  海图繁体地名汉字在子集中缺：{len(ch_lost)} {''.join(ch_lost)}")

    title = OUT / FONTS[1]
    t_cmap = TTFont(str(title), lazy=True).getBestCmap()
    print(f"\n[校验 {FONTS[1]}] 只核标题 / 印章用字；缺的由主题与过场引擎 fallback 到文楷")
    for label, text in title_chars(per_git).items():
        chars = sorted({c for c in text if is_han(c)})
        miss = [c for c in chars if ord(c) not in t_cmap]
        print(f"  {label}：{len(chars)} 字，缺 {len(miss)} {''.join(miss)}")
    return rc


def human(n: int) -> str:
    return f"{n / 1024 / 1024:.2f} MB"


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_source(sp: pathlib.Path, download: bool) -> bool:
    """源字体存在且 sha256 与上游一致才用；缺失时按 --download 取回。"""
    up = UPSTREAM[sp.name]
    if not sp.is_file():
        if not download:
            print(f"缺源字体 {sp}\n  上游 v{up['version']}：{up['url']}\n"
                  f"  sha256 {up['sha256']}\n  加 --download 自动取回，或 --src 指到已有目录（也可设环境变量 NK1_FONT_SRC）")
            return False
        sp.parent.mkdir(parents=True, exist_ok=True)
        print(f"下载 {up['url']}")
        tmp = sp.with_suffix(".part")
        urllib.request.urlretrieve(up["url"], tmp)
        os.replace(tmp, sp)
    got = sha256(sp)
    if got != up["sha256"]:
        print(f"源字体 {sp} sha256 不符：{got}\n  期望 v{up['version']} {up['sha256']}——不是上游原版，拒绝子集化")
        return False
    return True


def rename_font(font: TTFont, name: str) -> list:
    """按 RENAME 改写 name 表；返回改后仍含保留字体名的主名记录（应为空）。"""
    spec = RENAME.get(name)
    if not spec:
        return []
    tbl = font["name"]
    for rec in list(tbl.names):
        if rec.nameID in spec["ids"]:
            tbl.setName(spec["ids"][rec.nameID], rec.nameID, rec.platformID, rec.platEncID, rec.langID)
    # 主名记录（1/3/4/6/16/17/18/21/22）里不许再出现保留名
    primary = {1, 3, 4, 6, 16, 17, 18, 21, 22}
    return [(r.nameID, hex(r.langID), r.toUnicode()) for r in tbl.names
            if r.nameID in primary and any(k in r.toUnicode() for k in spec["reserved"])]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(DEFAULT_SRC))
    ap.add_argument("--extra", nargs="*", default=[])
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--download", action="store_true", help="源目录缺字体时从上游下载（校验 sha256）")
    ap.add_argument("--verify", action="store_true", help="只逐字校验 assets/fonts 里现有子集，不写文件")
    args = ap.parse_args()
    src = pathlib.Path(args.src)

    notes = []
    repo = repo_chars(SCAN_DIRS + [str(p) for p in DEFAULT_EXTRA] + list(args.extra))
    gitc, per_git = git_chars(notes)
    for n in notes:
        print("NOTE", n)
    if args.verify:
        return verify(src, repo, gitc, per_git)
    repo_only = len(repo)
    repo |= gitc
    wanted = gb2312_chars() | base_chars() | repo
    print(f"字符集：GB2312 {len(gb2312_chars())} + 基础 {len(base_chars())} + 仓库文本 {repo_only}"
          f" + 分支补字 {len(gitc)}（{len(per_git)} 个文件）→ 仓库+分支 {len(repo)}，合计 {len(wanted)}")

    rc = 0
    for name in FONTS:
        sp = src / name
        if not ensure_source(sp, args.download):
            return 2
        cmap = TTFont(str(sp), lazy=True).getBestCmap()
        have = {c for c in wanted if ord(c) in cmap}
        miss_repo = sorted(c for c in repo if ord(c) not in cmap and not c.isspace()
                           and ord(c) < 0x1F000)  # emoji 走系统兜底，不计
        print(f"\n[{name}] 源 {human(sp.stat().st_size)}，cmap {len(cmap)}，保留 {len(have)} 字")
        if miss_repo:
            print(f"  仓库文本中该字体缺字 {len(miss_repo)}：{''.join(miss_repo[:80])}")
            miss_han = [c for c in miss_repo if 0x3400 <= ord(c) <= 0x9FFF or ord(c) >= 0x20000]
            if name == FONTS[0] and miss_han:
                # 正文字体缺汉字要处理；符号/emoji 走系统兜底；书法字体缺字由主题 fallback 到文楷
                print(f"  !! 正文字体缺汉字：{''.join(miss_han)}")
                rc = 1
        if args.check:
            continue

        opts = subset.Options()
        opts.layout_features = ["*"]          # 保留 vert/vrt2（竖排）与 kern
        opts.name_IDs = ["*"]
        opts.name_languages = ["*"]
        opts.name_legacy = True
        opts.notdef_outline = True
        opts.glyph_names = False
        opts.hinting = True
        opts.legacy_kern = True
        opts.drop_tables += ["DSIG"]
        font = TTFont(str(sp), recalcTimestamp=False)   # head.modified 沿用源字体 → 重跑逐字节一致
        sub = subset.Subsetter(options=opts)
        sub.populate(unicodes=[ord(c) for c in have])
        sub.subset(font)
        left = rename_font(font, name)
        if left:
            print(f"  !! 改名后主名记录仍含保留字体名：{left}")
            return 3
        if name in RENAME:
            print(f"  内部名改为 {RENAME[name]['ids'][4]}（OFL §3；ID 0 版权与 ID 8/9 作者保留）")
        OUT.mkdir(parents=True, exist_ok=True)
        tmp = OUT / (name + ".tmp")
        font.save(str(tmp))
        os.replace(tmp, OUT / name)
        print(f"  输出 {OUT / name}：{human(sp.stat().st_size)} → {human((OUT / name).stat().st_size)}")
    if not args.check:
        rc = max(rc, verify(src, repo, gitc, per_git))
    return rc


if __name__ == "__main__":
    sys.exit(main())
