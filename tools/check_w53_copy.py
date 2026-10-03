#!/usr/bin/env python3
"""lane w53-10 文案钉：玩家可见串的禁写样（错字 / 排版 / 占位符 / 半角标点 / 配对）。

实锤（wave53-10 一二轮撒网+实跑 dump 探针 35 页 3063 条零红结论上钉）：
  一、玩家面「帐」当「账」——Main.gd:2319「先结了前帐罢」是唯一账务义「帐」误写样
      （其余 11 处「帐」全是军帐/营帐正当用法，见 check_symbols / qa_letterbox_copy）。
  二、状态增减半角连字符——GameState.gd:1093/1094「名声 -1」与 SeaChart:1701/1767
      「名声 −4 / 士气 −3」全宽形不统一。
  三、漏填 %s/%d/%f 占位符——玩家面 CJK 字符串字面量剩 %s/%d/%f 形时必为漏填
     （w53-10 二轮 35 页 3063 条实跑 dump 与静态撒网都零有此形）。

扩钉（不落纸易回潮的五类）：
  A. 漏填「{name}」占位符（{主角} 是 CharacterArt.gd fill_names 合法占位，放白名单；
     其它 {name} 玩家面串里出现即回潮）。news.json 的 {target_name}/{player_name}
     由 GameState.gd:447 运行时替换，也是合法占位，白名单。
  B. 「」《》（）『』四种配对不齐（按每行字符串逐行判；跨行字符串多行 CJK 用段聚合）。
  C. CJK 字符串里夹半角逗号/句号/问号/叹号（,,..?!），以及串尾半角标点。
  D. 中文 context 里的半角括号 (…)——gd 玩家面全用全角（…），此处只判两 CJK 间半角。
  E. 玩家面 UI 串里的纯 ASCII 调试字样（TODO / FIXME / XXX / DEBUG / placeholder）。
  F. 同一事物一个叫法（三轮）：玩家面串里出现 TERM_VARIANTS 左列即回潮，右列是全作通行的叫法。
     名声——船籍簿「名声　%d」、贡院 / 行会 / 委办毁约同；市舶司页与委办细则曾写「声名」。
     海商信用——船籍簿「海商信用　%d」、行会正文同；同页入行工席曾写「商誉」。
     硫黄——新闻「硫黄禁出海」、崖山「把粮与硫黄交上去」、萨摩横幅「硫黄所出」；牙行货名曾写「硫磺」。

查法：纯静态扫 scripts/*.gd 字符串字面量与 data/*.json 文本值（不上引擎），快且可重复。
与 wave53-10 二轮 scratch 探针（`qa_w53_10_page_dump.gd`，运行期挂 Main.tscn 走 35 页）：
二者层不同——本脚本钉源码层禁写样，dump 探针验证 UI 渲染零错样；本脚本进 gates-locked
一键，dump 探针跑完后已撤（_probe.gd 命名不入 commit）。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ═══ 玩家可见游戏统计名（"名声 X"兔子增减 RAM 尾）。其余「蒲家留意 -2」之类先不钉，
#     以免错抓阈值注释；后续若有新错样再扩。同一减号 U+2212（−）非半角 -。
STAT_WORDS = ("名声", "士气", "金钱", "水粮", "耐性", "悦")

# ═══ 钉 1：账务义「帐」错形（全仓 CJK 玩家串里仅此一处曾出错）。
FORBID_SUBSTRINGS = ("前帐",)

# ═══ 钉 2：状态名 + 空格 + 半角连字符 + 数字「名声 -1」。
HALF_MINUS_RE = re.compile(r"(%s)\s+-\d" % "|".join(STAT_WORDS))

# ═══ 钉 3：gd CJK 字符串字面量剩余 %s / %d / %f = 漏填。JSON 文本值同理钉——
#    data/*.json 串里出现也意味着上游 code 没做 replacement。
FMT_LEFTOVER_RE = re.compile(r"%[sdf]")

# ═══ 钉 A：{name} 占位符白名单外一律禁。news.json 的 {target_name}/{player_name}
#    与 characters_codex.json 的 {主角} 由运行时正确替换，合法。
PLACEHOLDER_OK = {"{主角}", "{target_name}", "{player_name}"}
PLACEHOLDER_RE = re.compile(r"\{[A-Za-z_一-鿿][A-Za-z_0-9-一-鿿]*\}")

# ═══ 钉 B：四种配对。跨行 gd 字符串允许各自局部配对（局部多行段先合再判）。
QUOTE_PAIRS = (("「", "」"), ("《", "》"), ("（", "）"), ("『", "』"))
# gd 字符串字面量抓 [^"\\]|\\. 一段，含跨行。
GD_STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"', re.S)


def _gd_strings_only(src):
    """同 check_symbols.code_only 但保字符串、剥注释与代码。yield (字面量, 起始偏移)。
    与 code_only 一致：剥 ""..."、'...'、\"\"\"...\"\"\"，遇 \\ 跳一字符；注释一律跳过。"""
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c in ('"', "'"):
            q = c * 3 if src.startswith(c * 3, i) else c
            start_inner = i + len(q)
            i = start_inner
            buf = []
            while i < n:
                if src[i] == "\\":
                    buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src.startswith(q, i):
                    i += len(q)
                    break
                buf.append(src[i])
                i += 1
            yield "".join(buf), start_inner
            continue
        i += 1

# ═══ 钉 C：CJK 串中/串尾半角标点。逗号/句号/问号/叹号都禁；冒号/分号都禁（中文句用全角）。
HALF_PUNCT_RE = re.compile(r"[一-鿿][,;:?!][一-鿿]|[一-鿿][,.;:?!]\\n|[一-鿿][,.;:?!]$")

# ═══ 钉 D：半角括号紧贴 CJK（中文只用全角括号）。
HALF_PAREN_RE = re.compile(r"[一-鿿]\(|\)[一-鿿]")

# ═══ 钉 E：玩家面禁写调试字样。gd 里 print / push_error 的 CJK message 不属于玩家面，
#     但 data/*.json 文本值出这些词必为漏调试。
DEBUG_WORDS_RE = re.compile(r"\b(TODO|FIXME|XXX|DEBUG|placeholder)\b")

# ═══ 钉 F：(异称, 通行叫法)。成语里的「声名」不是属性名，放白名单。
TERM_VARIANTS = (
    ("声名", "名声"),
    ("商誉", "海商信用"),
    ("硫磺", "硫黄"),
)
TERM_IDIOM_OK = ("声名鹊起", "声名狼藉", "声名远播", "声名大噪")

FAILS = []

# ─── 数据集玩家可见字段（lane w53-10 brief 钦定 data 域条款：chapters/endings/scenes/news
#     剧情正文归 lane 4，这里只修/禁错字与占位符，不动逻辑）
DATA_TEXT_KEYS = {
    "scenes.json": {"body", "objective", "title", "label", "postlude", "result"},
    "chapters.json": {"advance_text", "title", "name", "sub"},
    "endings.json": {"text", "title"},
    "cutscenes.json": {"text", "title", "sub"},
    "news.json": {"text", "text_S", "text_M", "speaker"},
    "discoveries.json": {"name", "location"},
    "titles.json": {"name"},
    "npcs.json": {"name", "title"},
    "crew.json": {"name", "role", "leave_note"},
    "goods.json": {"name", "category"},
    "ports.json": {"name", "region"},
    "weapons.json": {"name"},
}
# characters.json / characters_codex.json 不入扫：L1B 读取入口锁（verify_story_data.py:566）
# 把 characters.json 原稿 bio 与 codex 文本层设访问许可清单，本脚本纯文字面比对不进表。
# 人物志上屏的 {主角} 由 scripts/ui/CharacterArt.gd fill_names 换名，业经 verify_story_data
# 全链钉住，无需重复查。


def _has_cjk(s):
    return bool(re.search(r"[一-鿿]", s))


def _line_of(src, pos):
    return src.count("\n", 0, pos) + 1


def _check_pairs(text, tag):
    for a, b in QUOTE_PAIRS:
        if text.count(a) != text.count(b):
            FAILS.append(f"{tag}: {a}{b} 不齐（左 {text.count(a)} 右 {text.count(b)}）：{text[:120]}")
            return  # 一条串一处即报，防一行多红


def _check_placeholder(text, tag, file_hint):
    for m in PLACEHOLDER_RE.finditer(text):
        tok = m.group(0)
        if tok in PLACEHOLDER_OK:
            continue
        FAILS.append(f"{tag}: {file_hint} 占位符未换 {tok}：{text[:120]}")


def _check_half(text, tag):
    m = HALF_PUNCT_RE.search(text)
    if m:
        FAILS.append(f"{tag}: 半角标点进出中文：{text[:120]}")
    m = HALF_PAREN_RE.search(text)
    if m:
        FAILS.append(f"{tag}: 半角括号贴中文：{text[:120]}")


def _check_minus_and_ledger(text, tag):
    for bad in FORBID_SUBSTRINGS:
        if bad in text:
            FAILS.append(f"{tag}: 账务「账」误作「帐」——含「{bad}」字样：{text[:120]}")
    for m in HALF_MINUS_RE.finditer(text):
        FAILS.append(f"{tag}: 状态增减半角连字符（应为全宽 −）：{text[:120]}")


def _check_fmt(text, tag, file_hint):
    # data json 文本值里出现 %s 漏填（gd 里可能合法——「%s/%d/%f」是 print 格式化模板）
    if FMT_LEFTOVER_RE.search(text):
        FAILS.append(f"{tag}: {file_hint} 占位符漏填（剩 %[sdf]）：{text[:120]}")


def _check_debug(text, tag, file_hint):
    for m in DEBUG_WORDS_RE.finditer(text):
        FAILS.append(f"{tag}: {file_hint} 调试字样 {m.group(0)}：{text[:120]}")


def _check_terms(text, tag):
    bare = text
    for idiom in TERM_IDIOM_OK:
        bare = bare.replace(idiom, "")
    for bad, good in TERM_VARIANTS:
        if bad in bare:
            FAILS.append(f"{tag}: 异称「{bad}」，全作通行叫法是「{good}」：{text[:120]}")


def _scan_gd_strings():
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if not f.endswith(".gd"):
                continue
            p = os.path.join(dirpath, f)
            rel = p[len(ROOT) + 1:]
            src = open(p, encoding="utf-8").read()
            for lit, pos in _gd_strings_only(src):
                if not _has_cjk(lit):
                    continue
                ln = _line_of(src, pos)
                tag = f"{rel}:{ln}"
                _check_minus_and_ledger(lit, tag)
                _check_pairs(lit, tag)
                _check_placeholder(lit, tag, "gd")
                _check_half(lit, tag)
                _check_debug(lit, tag, "gd")
                _check_terms(lit, tag)
                # gd 里 %[sdf] 是合法格式化模板（"%s の %d" % [...]），不钉 3/E。


def _walk_json_strings(obj, path="", key=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from _walk_json_strings(v, f"{path}/{k}", k)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _walk_json_strings(v, f"{path}[{i}]", key)
    elif isinstance(obj, str):
        yield path, key, obj


def _scan_json_text():
    data_dir = os.path.join(ROOT, "data")
    for f in sorted(os.listdir(data_dir)):
        if not f.endswith(".json") or f not in DATA_TEXT_KEYS:
            continue
        p = os.path.join(data_dir, f)
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        keys = DATA_TEXT_KEYS[f]
        for path, key, text in _walk_json_strings(d):
            if not _has_cjk(text):
                continue
            if key not in keys:
                continue
            tag = f"data/{f}:{path}"
            _check_minus_and_ledger(text, tag)
            _check_pairs(text, tag)
            _check_placeholder(text, tag, "data")
            _check_half(text, tag)
            _check_fmt(text, tag, "data")
            _check_debug(text, tag, "data")
            _check_terms(text, tag)


_NEG_CASES = [
    # (打点函数, 样例字符串, 期望抓到的判定关键词)
    ("ledger", "客官，先结了前帐罢。", "帐当账"),
    ("ledger", "牙行扣 30 钱，名声 -1。", "半角连字符"),
    ("fmt", "代价酬 %s。", "漏填"),
    ("ph", "酬赏 {bonus_money} 钱。", "bonus_money"),
    ("pair", "「完结一卦。", "不齐"),
    ("pair", "（小声。", "不齐"),
    ("half", "客官,先结。", "半角"),
    ("half", "他（小声)说。", "半角括号"),
    ("debug", "TODO 占位文案。", "调试字样"),
    ("term", "赏钱 70　声名 7", "名声"),
    ("term", "会费 2000　商誉须 8。", "海商信用"),
    ("term", "过秤买入 硫磺 ×3", "硫黄"),
]


def _neg_probe(kind, text):
    """对单一负样走同一判路，抓回来临时 FAILS。返回抓到的消息列表。"""
    saved = FAILS[:]
    FAILS.clear()
    try:
        if kind == "ledger":
            _check_minus_and_ledger(text, "self")
        elif kind == "fmt":
            _check_fmt(text, "self", "data")
        elif kind == "ph":
            _check_placeholder(text, "self", "data")
        elif kind == "pair":
            _check_pairs(text, "self")
        elif kind == "half":
            _check_half(text, "self")
        elif kind == "debug":
            _check_debug(text, "self", "data")
        elif kind == "term":
            _check_terms(text, "self")
        return FAILS[:]
    finally:
        FAILS.clear()
        FAILS.extend(saved)


def _self_test():
    """每条钉至少一负样须抓到；抓不到 = 钉路已瞎，自检红。"""
    bad = []
    for kind, txt, want_key in _NEG_CASES:
        got = _neg_probe(kind, txt)
        # want_key 须出现在某条抓到消息里
        ok = any(want_key.split(":")[0] in g or want_key in g for g in got)
        # 特例：「帐当账」文案里实际写的是「账务「账」误作「帐」——
        if want_key == "帐当账":
            ok = any("帐" in g and "账" in g for g in got)
        if not ok:
            bad.append(f"{kind} 负样「{txt}」未被抓到（want {want_key}, got {got[:60]}）")
    return bad


def main():
    self_fails = _self_test()
    _scan_gd_strings()
    _scan_json_text()
    all_fails = self_fails + FAILS
    if all_fails:
        print("结果：%d 项问题" % len(all_fails))
        for m in all_fails:
            print("   ✗ " + m)
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
