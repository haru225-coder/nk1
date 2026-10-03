#!/usr/bin/env python3
"""lane w53-10 文案钉：玩家可见串的禁写样（半角「前帐」应为「前账」、状态增减半角 -N 应为全宽 −N）。

覆盖两枚 wave53-10 实锤：
  一、玩家面「帐」当「账」——scripts/Main.gd:2319「先结了前帐罢」是唯一一处把账务「账」误写成「帐」
      的玩家可见日志（其余「帐」全是军帐/营帐，见 check_symbols/qa_letterbox_copy 域）。全仓任何 CJK
      玩家字符串都不许再出「前帐」，以防回潮。
  二、状态增减半角连字符——「名声 -1」「士气 -1」类的半角 -N 实际是 U+2212（−）的误写；
      同伴样式「SeaChart.gd:1701 名声 −4」「GameState.gd:1052 名声 +1」都用 −/+，只有 GameState.gd
      :1093/:1094 委办毁约/逾期两条用了半角 -1。玩家面玩家通读「名声 −1」统一形，半角连字符即回潮。

查法：python3 静态扫 scripts/*.gd 与 data/*.json，把「玩家可见 CJK 串」（含 CJK 的字符串字面量或 JSON 文本值）
逐段断言。规则一：禁「前帐」字样；规则二：禁「名声 -」「士气 -」「金钱 -」半角连字符紧接着数字（应为 −）。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 玩家可见游戏统计名（“名声 X”“士气 X”一类的 RAM 增减）。其余「蒲家留意 -2」之类先不钉，
# 以免错抓阈值注释；后续若有新错样再扩。
STAT_WORDS = ("名声", "士气", "金钱", "水粮", "耐性", "悦")

# 规则一：账务义「帐」错形。这是 w53-10 实锤坐标，钉死「前帐」这个具体错形即可，
# 别扩到「帐」整字符（军帐/营帐是正当用法）。
FORBID_SUBSTRINGS = ("前帐",)

# 规则二：状态名 + 空格 + 半角连字符 + 数字——即「名声 -1」。玩家面统一是全宽 −（U+2212），
# 半角即错样。
HALF_MINUS_RE = re.compile(r"(%s)\s+-\d" % "|".join(STAT_WORDS))

FAILS = []


def _check_scope(lines, src_label):
    for ln, line in enumerate(lines, 1):
        for bad in FORBID_SUBSTRINGS:
            if bad in line:
                FAILS.append(f"{src_label}:{ln}: 账务「账」误作「帐」——含「{bad}」字样：{line.rstrip()[:120]}")
        for m in HALF_MINUS_RE.finditer(line):
            FAILS.append(f"{src_label}:{ln}: 状态增减半角连字符（应为全宽 −）——{line.rstrip()[:120]}")


def _scan_gd():
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if not f.endswith(".gd"):
                continue
            p = os.path.join(dirpath, f)
            src = open(p, encoding="utf-8").read()
            if not _has_cjk(src):
                continue
            _check_scope(src.splitlines(), p[len(ROOT) + 1:])


def _has_cjk(s):
    return bool(re.search(r"[一-鿿]", s))


def _walk_json_strings(obj, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from _walk_json_strings(v, f"{path}/{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _walk_json_strings(v, f"{path}[{i}]")
    elif isinstance(obj, str):
        yield path, obj


def _scan_json():
    data_dir = os.path.join(ROOT, "data")
    for f in sorted(os.listdir(data_dir)):
        if not f.endswith(".json"):
            continue
        p = os.path.join(data_dir, f)
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        for path, s in _walk_json_strings(d):
            if not _has_cjk(s):
                continue
            for bad in FORBID_SUBSTRINGS:
                if bad in s:
                    FAILS.append(f"data/{f}:{path}: 账务「账」误作「帐」——含「{bad}」字样：{s[:120]}")
            for m in HALF_MINUS_RE.finditer(s):
                FAILS.append(f"data/{f}:{path}: 状态增减半角连字符（应为全宽 −）——{s[:120]}")


def _self_test():
    # 负样本：自己加一个错样，自己应能抓到
    bad_line = 'log_msg("【钱不够】掌柜把算盘一推：「客官，先结了前帐罢。」")'
    got = []
    for bad in FORBID_SUBSTRINGS:
        if bad in bad_line:
            got.append(bad)
    if not got:
        FAILS.append("self-test: 负样「前帐」未被检出")
    bad_stat = 'return "【毁约】名声 -1。"'
    if not HALF_MINUS_RE.search(bad_stat):
        FAILS.append("self-test: 负样「名声 -1」未被检出")


def main():
    _self_test()
    _scan_gd()
    _scan_json()
    if FAILS:
        print("结果：%d 项问题" % len(FAILS))
        for m in FAILS:
            print("   ✗ " + m)
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
