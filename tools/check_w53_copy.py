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
     签——「籖」是「籤」的异体，简体正文只写「签」（新闻「太学签榜」曾夹此字）。
     蒲家留意（五轮）——船籍簿「蒲家留意　%d」、市舶司页「蒲家留意 %d　尚无人留意」；市舶司小吏的疏通笺
     曾写「关注　减 15」（「关注」是开发文档里的叫法，玩家面没有这个数）。
  G. 增减号后面要有数（三轮）：「名声 +」「士气 −」这类只有正负号没有数目的串即红；
     海图事件钮文写「（名声 +N）」的，按下去的处理函数须真是 GameState.fame += N。
     （征船「交出一条船（名声 +）」曾缺数，实加 6。）
  H. 一个人不说「有的…有的…」（三轮）：跳年摘要「没有再上船」须经 GameManager.crew_left_line
     （单人「不知是回了乡，还是上了别家的船」/ 多人「有的回了乡，有的上了别家的船」），
     skip_years 里不得再内联多人句；两种说法的字面由 godot_story_check 判。
  I. 上屏的每个字都要在正文字库里（四轮）：标题字（马善政）、海图名（朱雀仿宋）缺字都回落到文楷子集
     assets/fonts/LXGWWenKai-Medium.ttf，文楷子集再缺就由引擎落到系统字体——同一句里单单一个字换了
     字形（没有 CJK 字体的机器上是豆腐块）。子集由 tools/art/subset_fonts.py 按仓库全文生成，此后新添的字
     不重跑就缺：海图「不明船影」的「瞭望手」（cdbdb66 依通用规范汉字表改「瞭」）与弹道表的「砲」「毬」曾如此。
     纯标准库读字库 cmap，逐字核上屏串：gd 字符串字面量、data/*.json 文本值（跳过 /meta 与出处 / 引文 / 注记类键；
     人物原稿不读，人物志文本层 characters_codex.json 整份核）、场景 text 属性。缺字就重跑
     subset_fonts.py（--download 取上游原版）。
  J. 海战上屏文案不用叹号（四轮）：data/combat_phases.json 的 meta.copy_style 立的规矩「纪实短句，不用叹号」，
     管海战场景与船（WorldMap / Ship / PirateShip / Cannonball）、scripts/combat/、scripts/ui/Combat* 的 CJK 串
     与 data/combat_*.json 的文本值。「敌船抛钩咬舷！」曾是全仓 gd 玩家串里唯一的叹号（同处「敌船抛钩落空」
     就没有）。copy_style 不再写「不用叹号」时本钉先红——规矩撤了就改本钉，不守一条已撤的规矩。
  K. 札记写明的货损成数 = 实扣（六轮）：海图「献上买路财」拿不出钱时札记写「他们自己动手搬空了半个货舱」，
     同一函数实扣 Fleet.lose_cargo_ratio(0.3)——每样货三成（向上取整），札记后面列的件数就是三成，与「半个」对不上。
     函数里调了 lose_cargo_ratio(字面数) 的，玩家串写「半个货舱 / 半舱 / 一半的货」（0.5）或「N成货」（N/10）就须等于
     实参；不调的不比（剧情里「一小份货」这类不写数的也不比）。
  L. 数量词前的「二」写「两」（七轮）：海战读数「帆　二成」「浸水二成」「可喊　约二成」、损伤札记「帆损二成」、
     船屋「此帆比光船快二成四」——成数照《现代汉语词典》「增产两成」与全作手写文案写「两成」（五轮守城「已守二阵」同类）。
     cn_num 系帮手（GameManager.cn_num / Main._cn_num / CombatStatusHud.cn_num / FloodFire.cn_num）都认 liang；
     格式串里「%s」紧跟量词（成、阵、年、条、趟、石……）、不是「第%s」序数的，对应实参若是 cn_num(…) 就须带 true；
     手拼的 digits[…] + "成" 所在函数里须有「两」。序数（第二阵、二等、二舱）与记账体「海鹘二艘」（_cn_count）不在此列。
  M. 职事效力提示每一句都要有代码接着（七轮）：酒馆募人卡品级下那行 effect_hint（雇入钮悬停也印）是玩家掂量雇谁的
     依据。火长曾写「日行更远，不易失道」——迷航几率只看生路与航法（Voyage.LOST_*），不看火长，「不易失道」无此效力；
     杂事曾写「买卖价差改善」——实是抽解与佣金打折（trade_cost_factor），价差是通事的效力（interpreter_edge）。
     设计表（复刻设计 §职事）：火长日速 +6%/级、杂事抽解与佣金 −12%/级。提示按「，、；」切句，每句须在 ROLE_HINT_FN
     登记接着它的 Crew 加成函数，该函数须读本职事的品级（level_of("<职事 id>")）、且在 Crew.gd 以外有调用。
  N. 记事句里的增减写汉字（七轮）：同一记事栏里曾三样并存——「委办交清…名声 +1。」「…修埠…名声加 5。」「…入案。
     赏钱 70，名声添 7。」。全作文案口径是纪实短句（修埠一句早有 smoke 钉「名声加 %d」、禁「名声 +%d」）：记事、
     札记、悬停说明里写「名声加 N / 名声减 N」（士气、海商信用、乡土……同）；只有钮文括注里的预告（「交出一条船
     （名声 +6）」「（费 6 日・30 钱，乡土 +3）」）照写 +N / −N（钉 G 核它们 = 实扣）。「名声添」统一作「名声加」。
  O. 间隔号写全角「・」（七轮）：全作间隔号 gd 玩家串里 83 处是全角「・」（「第%s章・%s」「粮 120・够打三阵」），
     另有 8 处半角「·」（U+00B7）——旅店钮「歇 10 日　150·误期」、海图去处牌「斜逆风·换风」、科举通告题「咸淳四年 ·
     唱第」等，半角点在全角空格与汉字之间挤成一粒。gd 玩家串里不许再写「·」。数据里的书证出处（《论语·公冶长》）与
     海图旧式题签（「興化軍·莆田」）照原样，不扫。拼接用的分隔符（"·".join(…)，不带汉字）另扫一遍，
     把半角点归一成全角的 .replace("·", "・") 写法放过。

查法：纯静态扫 scripts/*.gd 字符串字面量与 data/*.json 文本值（不上引擎），快且可重复。
与 wave53-10 二轮 scratch 探针（`qa_w53_10_page_dump.gd`，运行期挂 Main.tscn 走 35 页）：
二者层不同——本脚本钉源码层禁写样，dump 探针验证 UI 渲染零错样；本脚本进 gates-locked
一键，dump 探针跑完后已撤（_probe.gd 命名不入 commit）。
"""
import json, os, re, struct, sys, unicodedata

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
    ("籖", "签"),
    ("关注", "蒲家留意"),
)
TERM_IDIOM_OK = ("声名鹊起", "声名狼藉", "声名远播", "声名大噪")

# ═══ 钉 G：属性名 + 正负号 + 不是数目（也不是 %d 占位）= 漏了数。
DELTA_WORDS = ("名声", "士气", "海商信用", "人脉", "乡土", "学者", "海路", "水粮")
DANGLING_SIGN_RE = re.compile(r"(%s)\s*[+−](?!\s*[0-9%%])" % "|".join(DELTA_WORDS))
# 海图事件钮：_add_event_action("…（…名声 +N…）", 回调)；回调体里须有 GameState.fame += N。
EVENT_FAME_RE = re.compile(r'_add_event_action\("([^"]*（[^"]*名声 \+(\d+)[^"]*）)",\s*(_\w+)\)')
# 防沉默绿：这几颗钮文必须被上面的正则抓到（钮文改了格式、正则抓空时判红，不当绿）。
EVENT_FAME_MUST = ("交出一条船",)

# ═══ 钉 K：札记写的货损成数 = 同一函数里 Fleet.lose_cargo_ratio 的字面实参。
CARGO_FRAC_RE = re.compile(r"半个?货舱|半舱|一半的?货|([一二两三四五六七八九十])成的?货")
CARGO_RATIO_RE = re.compile(r"lose_cargo_ratio\(\s*([0-9.]+)\s*\)")
CN_DIGIT = {"一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}
# 防沉默绿：这几处札记的成数必须被抓到（札记改了写法、正则抓空时判红，不当绿）。
CARGO_FRAC_MUST = (("scripts/SeaChart.gd", "_on_pay_pirates"),)

# ═══ 钉 L：量词前的 cn_num 须带 liang；手拼「成」须会写「两」；cn_num 系帮手须认 liang。
CN_CLASSIFIERS = "成阵年条趟石人艘日次件个位名家处座门匹担斤"
CN_CALL_RE = re.compile(r"(?<![\w])(?:\w+\.)*_?cn_num\(")
FMT_PH_RE = re.compile(r"%(?:%|[-+ 0#]*\d*(?:\.\d+)?[sdifxXoceEgGv])")
CHENG_CONCAT_RE = re.compile(r"\]\s*\)?\s*\+\s*\"成")
CN_HELPERS = (("scripts/GameManager.gd", "cn_num"), ("scripts/Main.gd", "_cn_num"),
              ("scripts/ui/CombatStatusHud.gd", "cn_num"), ("scripts/combat/FloodFire.gd", "cn_num"))
# 防沉默绿：这几处「量词前带 liang 的 cn_num」必须被认出来（格式串 / 实参解析坏了时判红，不当绿）。
CN_LIANG_MUST = (("scripts/ui/ChapterSheet.gd", "趟"), ("scripts/Main.gd", "阵"), ("scripts/ui/CombatStatusHud.gd", "成"))

# ═══ 钉 M：职事效力提示的每一句 → 接着它的 Crew 加成函数（读本职事品级、Crew.gd 以外有调用）。
ROLE_HINT_FN = {
    "日行更远": "speed_factor",
    "顶头逆风的折损减轻": "wind_floor",
    "货物腐损与风涛货损减少": "cargo_loss_factor",
    "抽解与佣金减少": "trade_cost_factor",
    "在异国港口买卖更划算": "interpreter_edge",
    "断粮时减员更少": "crew_loss_factor",
    "士气回复更快": "morale_bonus",
}
# ═══ 钉 O：gd 玩家串的间隔号只用全角「・」（U+30FB），不用半角「·」（U+00B7）。
HALF_INTERPUNCT = "\u00b7"

# ═══ 钉 N：括注外的「名声 +N / 士气 −N」= 记事句写了钮文记号；「名声添」= 动词没统一。
DELTA_NOTE_RE = re.compile(r"(%s)\s*[+−]\s*(?:\d|%%d)" % "|".join(DELTA_WORDS))
DELTA_TIAN_RE = re.compile(r"(%s)添" % "|".join(DELTA_WORDS))
# 防沉默绿：这颗钮文括注里的增减必须被认出来（正则抓空时判红，不当绿）。
DELTA_PAREN_MUST = (("scripts/SeaChart.gd", "交出一条船"),)
CREW_JSON = "data/crew.json"
CREW_GD = "scripts/core/Crew.gd"

# ═══ 钉 I：上屏串逐字对正文字库的 cmap。字库是 subset_fonts.py 出的文楷子集，标题字 / 海图字缺字都回落到它。
BODY_FONT = "assets/fonts/LXGWWenKai-Medium.ttf"
# 人物志文本层整份上屏（verify_story_data 的 CODEX_ONSCREEN 管着每个键），只取来核字形；人物原稿不读
CODEX_JSON = "data/characters_codex.json"
# data/*.json 里不上屏的键：出处、引文、今名对照、可信度、旧值、设计说明（/meta 整段也跳过）
GLYPH_SKIP_KEYS = {"note", "notes", "source", "sources", "quote", "today", "confidence", "legacy", "why", "copy_style"}
# 场景里写死的上屏属性（Label / Button 的 text、提示、窗口题）
TSCN_TEXT_RE = re.compile(r'^(?:text|tooltip_text|placeholder_text|title) = "((?:[^"\\]|\\.)*)"', re.M)
GLYPH_MISS = {}  # 缺的字 → [(出处, 原串)]

# ═══ 钉 J：海战上屏文案（copy_style 所管）不用叹号。gd 按路径前缀认，data 按文件认。
COMBAT_STYLE_JSON = "data/combat_phases.json"
COMBAT_GD_PREFIXES = ("scripts/WorldMap.gd", "scripts/Ship.gd", "scripts/PirateShip.gd", "scripts/Cannonball.gd",
                      "scripts/combat/", "scripts/ui/Combat")
COMBAT_DATA = ("combat_phases.json", "combat_morale.json", "combat_sea_state.json")

FAILS = []

# ─── 数据集玩家可见字段（lane w53-10 brief 钦定 data 域条款：chapters/endings/scenes/news
#     剧情正文归 lane 4，这里只修/禁错字与占位符，不动逻辑）
DATA_TEXT_KEYS = {
    "scenes.json": {"body", "objective", "title", "label", "postlude", "result"},
    # summary 章目 / hint 晋升条件 / story_hooks 的 label 与 text（酒馆旧事）
    "chapters.json": {"advance_text", "title", "name", "sub", "summary", "hint", "label", "text"},
    "endings.json": {"text", "title"},
    # name 港口横幅港名 / epigraph 章节卡题辞与出处 / year_text 章节卡年款
    "cutscenes.json": {"text", "title", "sub", "name", "epigraph", "epigraph_src", "year_text"},
    "news.json": {"text", "text_S", "text_M", "speaker"},
    # historical_hook：市舶司呈报钮与寺观细看钮的 tooltip
    "discoveries.json": {"name", "location", "historical_hook"},
    "titles.json": {"name"},
    "npcs.json": {"name", "title"},
    # bio / desc / effect_hint：酒馆募人卡
    "crew.json": {"name", "role", "leave_note", "bio", "desc", "effect_hint"},
    "goods.json": {"name", "category"},
    # label / sub：海图港签（海图用繁体是有意的，不查繁简，只查配对 / 标点 / 异称）
    "ports.json": {"name", "region", "label", "sub"},
    "weapons.json": {"name"},
    # historical_note：船屋坞外待售船的旁注
    "ships.json": {"name", "historical_note"},
}
# characters.json 不入扫：L1B 读取入口锁（verify_story_data.py 的 L1B_READERS）管着谁能读人物原稿，
# 原稿 bio 不上屏。人物志文本层 characters_codex.json 只给钉 I 核字形（已登记 codex 类读取），其余钉不扫它——
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


def _check_dangling_sign(text, tag):
    m = DANGLING_SIGN_RE.search(text)
    if m:
        FAILS.append(f"{tag}: 「{m.group(0).strip()}」后面缺数目：{text[:120]}")


def _check_exclaim(text, tag):
    if "！" in text or "!" in text:
        FAILS.append(f"{tag}: 海战上屏文案用了叹号（combat_phases.json copy_style：纪实短句，不用叹号）：{text[:120]}")


def _ttf_cmap(path):
    """读 TrueType 的 cmap（format 4 / 12 子表取并集），返回有字形的码位集；读不出返回空集。只用标准库。"""
    try:
        data = open(path, "rb").read()
        tables = {}
        for i in range(struct.unpack_from(">H", data, 4)[0]):
            tag, _sum, off, _len = struct.unpack_from(">4sIII", data, 12 + 16 * i)
            tables[tag] = off
        base = tables[b"cmap"]
        out, seen = set(), set()
        for i in range(struct.unpack_from(">H", data, base + 2)[0]):
            sub = base + struct.unpack_from(">I", data, base + 8 + 8 * i)[0]
            if sub in seen:
                continue
            seen.add(sub)
            fmt = struct.unpack_from(">H", data, sub)[0]
            if fmt == 4:
                seg = struct.unpack_from(">H", data, sub + 6)[0] // 2
                ends = struct.unpack_from(">%dH" % seg, data, sub + 14)
                starts = struct.unpack_from(">%dH" % seg, data, sub + 16 + 2 * seg)
                deltas = struct.unpack_from(">%dh" % seg, data, sub + 16 + 4 * seg)
                ro_at = sub + 16 + 6 * seg
                ros = struct.unpack_from(">%dH" % seg, data, ro_at)
                for k in range(seg):
                    for c in range(starts[k], ends[k] + 1):
                        if c == 0xFFFF:
                            continue
                        if ros[k] == 0:
                            g = (c + deltas[k]) & 0xFFFF
                        else:
                            g = struct.unpack_from(">H", data, ro_at + 2 * k + ros[k] + 2 * (c - starts[k]))[0]
                            g = (g + deltas[k]) & 0xFFFF if g else 0
                        if g:
                            out.add(c)
            elif fmt == 12:
                for j in range(struct.unpack_from(">I", data, sub + 12)[0]):
                    s, e, g0 = struct.unpack_from(">III", data, sub + 16 + 12 * j)
                    out.update(c for c in range(s, e + 1) if g0 + c - s)
        return out
    except (OSError, KeyError, struct.error):
        return set()


def _check_glyphs(text, tag, cmap):
    """串里每个字（ASCII、空白、控制 / 格式符、异体选择符除外）都须在 cmap 里；缺的记进 GLYPH_MISS 按字汇总。
    cmap 为 None（自检已判字库读不出）时不核，免得满屏缺字。"""
    if cmap is None:
        return
    for ch in dict.fromkeys(text):
        o = ord(ch)
        if o < 0x80 or o in cmap or 0xFE00 <= o <= 0xFE0F or unicodedata.category(ch) in ("Cc", "Cf", "Zs", "Zl", "Zp"):
            continue
        GLYPH_MISS.setdefault(ch, []).append((tag, text))


def _report_glyphs():
    for ch, hits in sorted(GLYPH_MISS.items()):
        tag, text = hits[0]
        more = f"（共 {len(hits)} 处）" if len(hits) > 1 else ""
        FAILS.append(f"{tag}: 正文字库缺「{ch}」U+{ord(ch):04X}{more}——屏上这个字会落到系统字体；"
                     f"重跑 python3 tools/art/subset_fonts.py 补字：{text[:80]}")


def _func_body_gd(src, name):
    i = src.find("\nfunc %s(" % name)
    if i < 0:
        return ""
    j = src.find("\nfunc ", i + 1)
    return src[i:] if j < 0 else src[i:j]


def _check_event_fame(src, rel):
    """钮文的「名声 +N」与回调实加数对齐；返回抓到的钮文列表（供防沉默绿）。"""
    seen = []
    for m in EVENT_FAME_RE.finditer(src):
        label, n, cb = m.group(1), int(m.group(2)), m.group(3)
        seen.append(label)
        body = _func_body_gd(src, cb)
        got = [int(x) for x in re.findall(r"GameState\.fame \+= (\d+)", body)]
        if got != [n]:
            FAILS.append(f"{rel}: 钮文「{label}」写名声 +{n}，回调 {cb} 实加 {got or '无'}")
    return seen


def _scan_gd_strings(cmap):
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
                _check_dangling_sign(lit, tag)
                _check_delta_note(lit, tag, DELTA_PAREN_SEEN)
                _check_interpunct(lit, tag)
                _check_glyphs(lit, tag, cmap)
                if rel.replace(os.sep, "/").startswith(COMBAT_GD_PREFIXES):
                    _check_exclaim(lit, tag)
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
            _check_dangling_sign(text, tag)
            _check_delta_note(text, tag)


def _scan_data_glyphs(cmap):
    """钉 I：data/*.json 的文本值逐字核字形——上表之外的上屏键（场景副题 / 说话人、海图地名、海战提示、
    海况名……）也核。人物原稿不读（L1B 锁），人物志文本层整份核；/meta 与 GLYPH_SKIP_KEYS 不上屏，跳过。"""
    data_dir = os.path.join(ROOT, "data")
    codex = os.path.basename(CODEX_JSON)
    seen_codex = False
    for f in sorted(os.listdir(data_dir)):
        if not f.endswith(".json") or (f.startswith("characters") and f != codex):
            continue
        try:
            d = json.load(open(os.path.join(data_dir, f), encoding="utf-8"))
        except (OSError, ValueError):
            continue
        seen_codex = seen_codex or f == codex
        for path, key, text in _walk_json_strings(d):
            if _has_cjk(text) and key not in GLYPH_SKIP_KEYS and not path.startswith("/meta"):
                _check_glyphs(text, f"data/{f}:{path}", cmap)
    if not seen_codex:
        FAILS.append(f"{CODEX_JSON}: 钉 I 读不到人物志文本层")


def _scan_combat_data():
    """钉 J：data/combat_*.json 的上屏文本值（/meta 与注记键除外）不用叹号；copy_style 须仍写着这条规矩。"""
    try:
        style = str(json.load(open(os.path.join(ROOT, COMBAT_STYLE_JSON), encoding="utf-8"))["meta"]["copy_style"])
    except (OSError, ValueError, KeyError, TypeError):
        style = ""
    if "不用叹号" not in style:
        FAILS.append(f"{COMBAT_STYLE_JSON}: meta.copy_style 不再写「不用叹号」——钉 J 的依据变了，先改钉 J")
    for f in COMBAT_DATA:
        try:
            d = json.load(open(os.path.join(ROOT, "data", f), encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for path, key, text in _walk_json_strings(d):
            if _has_cjk(text) and key not in GLYPH_SKIP_KEYS and not path.startswith("/meta"):
                _check_exclaim(text, f"data/{f}:{path}")


def _scan_tscn_glyphs(cmap):
    """钉 I：场景里写死的 text / tooltip_text / placeholder_text / title。"""
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scenes")):
        for f in sorted(files):
            if not f.endswith(".tscn"):
                continue
            p = os.path.join(dirpath, f)
            rel = p[len(ROOT) + 1:]
            src = open(p, encoding="utf-8").read()
            for m in TSCN_TEXT_RE.finditer(src):
                if _has_cjk(m.group(1)):
                    _check_glyphs(m.group(1), f"{rel}:{_line_of(src, m.start(1))}", cmap)


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
    ("term", "临安发了太学籖榜。", "签"),
    ("term", "疏通　关注　减 15", "蒲家留意"),
    ("sign", "交出一条船（名声 +）", "缺数目"),
    ("sign", "士气 −。", "缺数目"),
    ("exclaim", "敌船抛钩咬舷！", "叹号"),
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
        elif kind == "sign":
            _check_dangling_sign(text, "self")
        elif kind == "exclaim":
            _check_exclaim(text, "self")
        return FAILS[:]
    finally:
        FAILS.clear()
        FAILS.extend(saved)


def _gd_funcs(src):
    """按行首 func 切函数：yield (函数名, 函数体)。"""
    heads = list(re.finditer(r"^(?:static )?func (\w+)\(", src, re.M))
    for k, m in enumerate(heads):
        end = heads[k + 1].start() if k + 1 < len(heads) else len(src)
        yield m.group(1), src[m.start():end]


def _check_cargo_frac(src, rel):
    """札记写的货损成数与同函数 lose_cargo_ratio 实参对齐；返回 [(函数名, 成数)]（供防沉默绿）。"""
    seen = []
    for name, body in _gd_funcs(src):
        ratios = [float(x) for x in CARGO_RATIO_RE.findall(body)]
        if not ratios:
            continue
        for lit, _pos in _gd_strings_only(body):
            for m in CARGO_FRAC_RE.finditer(lit):
                said = 0.5 if m.group(1) is None else CN_DIGIT[m.group(1)] / 10.0
                seen.append((name, said))
                if not any(abs(said - r) < 1e-6 for r in ratios):
                    FAILS.append(f"{rel}: {name} 札记写「{m.group(0)}」（{said:g}），实扣 lose_cargo_ratio "
                                 f"{' / '.join(f'{r:g}' for r in ratios)}：{lit[:40]}")
    return seen


def _skip_str(src, i):
    """src[i] 是引号：返回字符串字面量之后的位置。"""
    q = src[i] * 3 if src.startswith(src[i] * 3, i) else src[i]
    i += len(q)
    while i < len(src):
        if src[i] == "\\":
            i += 2
            continue
        if src.startswith(q, i):
            return i + len(q)
        i += 1
    return i


def _split_top(text):
    """按顶层逗号切实参（括号、方括号、花括号与字符串里的逗号不切）。"""
    parts, depth, cur, i = [], 0, 0, 0
    while i < len(text):
        c = text[i]
        if c in "\"'":
            i = _skip_str(text, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(text[cur:i])
            cur = i + 1
        i += 1
    parts.append(text[cur:])
    return [x for x in parts if x.strip()]


def _balanced(src, i):
    """src[i] 是开括号：返回 (括号里的内容, 闭括号之后的位置)。"""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack, j = [pairs[src[i]]], i + 1
    while j < len(src) and stack:
        c = src[j]
        if c in "\"'":
            j = _skip_str(src, j)
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif c == stack[-1]:
            stack.pop()
        j += 1
    return src[i + 1:j - 1], j


def _fmt_args(src, end):
    """字面量结尾之后若是「% 实参」：返回实参表（单个实参也装成表）；不是格式化就返回 None。"""
    i = end
    while i < len(src) and src[i] in " \t":
        i += 1
    if i >= len(src) or src[i] != "%" or src.startswith("%=", i):
        return None
    i += 1
    while i < len(src) and src[i] in " \t":
        i += 1
    if i < len(src) and src[i] == "[":
        return _split_top(_balanced(src, i)[0])
    j, depth = i, 0
    while j < len(src):
        c = src[j]
        if c in "\"'":
            j = _skip_str(src, j)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and (c in ",\n#" ):
            break
        j += 1
    return [src[i:j]]


def _cn_call_liang(arg):
    """实参里的 cn_num(…) 调用带不带 liang（末个实参是 true）；没有 cn_num 调用返回 None。"""
    m = CN_CALL_RE.search(arg)
    if m is None:
        return None
    inner = _balanced(arg, m.end() - 1)[0]
    parts = _split_top(inner)
    return len(parts) >= 2 and parts[-1].strip() == "true"


def _check_liang(src, rel):
    """量词前的 cn_num 带 liang、手拼「成」会写「两」；返回认出的 [(rel, 量词)]（供防沉默绿）。"""
    seen = []
    for lit, pos in _gd_strings_only(src):
        if "%s" not in lit:
            continue
        q = 3 if src[pos - 3:pos] in ('"""', "'''") else 1
        args = _fmt_args(src, pos + len(lit) + q)
        if not args:
            continue
        idx = 0
        for m in FMT_PH_RE.finditer(lit):
            if m.group(0) == "%%":
                continue
            k, idx = idx, idx + 1
            nxt, prev = lit[m.end():m.end() + 1], lit[max(0, m.start() - 1):m.start()]
            if m.group(0) != "%s" or not nxt or nxt not in CN_CLASSIFIERS or (prev and prev in "第初"):
                continue
            ok = _cn_call_liang(args[k]) if k < len(args) else None
            if ok is None:
                continue
            seen.append((rel, nxt))
            if not ok:
                FAILS.append(f"{rel}:{_line_of(src, pos)}: 量词「{nxt}」前的 {args[k].strip()[:40]} 没带 liang，"
                             f"数到 2 上屏写「二{nxt}」：{lit[:40]}")
    for name, body in _gd_funcs(src):
        if CHENG_CONCAT_RE.search(body) and '"两"' not in body:
            FAILS.append(f"{rel}: {name} 手拼「…成」，数到 2 写不出「两成」")
    return seen


def _check_cn_helpers():
    for rel, name in CN_HELPERS:
        src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        body = dict(_gd_funcs(src)).get(name, "")
        head = body.split("\n", 1)[0]
        if "liang" not in head or not ('"两"' in body or re.search(r"cn_num\(\s*\w+\s*,\s*liang\s*\)", body)):
            FAILS.append(f"{rel}: {name} 不认 liang（带 true 也写不出「两」）")


def _check_delta_note(text, tag, seen=None):
    """括注（全角圆括号）外的带符号增减判红、「X添」判红；括注里的记作已认（供防沉默绿）。"""
    for m in DELTA_NOTE_RE.finditer(text):
        depth = text.count("（", 0, m.start()) - text.count("）", 0, m.start())
        if depth > 0:
            if seen is not None:
                seen.append(text)
            continue
        FAILS.append(f"{tag}: 记事句里写成钮文记号「{m.group(0)}」——写「{m.group(1)}加 N / {m.group(1)}减 N」：{text[:48]}")
    for m in DELTA_TIAN_RE.finditer(text):
        FAILS.append(f"{tag}: 「{m.group(0)}」——增减统一写「{m.group(1)}加」：{text[:48]}")


def _check_interpunct(text, tag):
    if HALF_INTERPUNCT in text:
        FAILS.append(f"{tag}: 间隔号写成半角「·」——全作写全角「・」：{text[:48]}")


INTERPUNCT_NORMALIZE_RE = re.compile(r"\.(?:replace|trim_suffix|trim_prefix)\(\s*$")


def _check_interpunct_bare(src, rel):
    """不带汉字的串（拼接用的分隔符，如 "·".join(bits)）另扫一遍；把半角点改成全角的归一化写法（.replace("·", …)）放过。"""
    for lit, pos in _gd_strings_only(src):
        if HALF_INTERPUNCT not in lit or _has_cjk(lit):
            continue
        if INTERPUNCT_NORMALIZE_RE.search(src[max(0, pos - 40):pos - 1]):
            continue
        FAILS.append(f"{rel}:{_line_of(src, pos)}: 拼接用的间隔号写成半角「·」——写全角「・」：{src[pos - 1:pos + 12].strip()}")


def _scan_interpunct_bare():
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if f.endswith(".gd"):
                p = os.path.join(dirpath, f)
                _check_interpunct_bare(open(p, encoding="utf-8").read(), p[len(ROOT) + 1:])


def _check_role_hints(roles, crew_src, game_src, tag):
    """每个职事 effect_hint 的每一句：登记过、登记的函数读本职事品级、Crew.gd 以外有调用。返回核过的句数。"""
    funcs = dict(_gd_funcs(crew_src))
    n = 0
    for r in roles:
        rid, rname = str(r.get("id", "")), str(r.get("name", ""))
        for clause in re.split(r"[，、；]", str(r.get("effect_hint", ""))):
            clause = clause.strip("。 ")
            if not clause:
                continue
            fn = ROLE_HINT_FN.get(clause)
            if fn is None:
                FAILS.append(f"{tag}: 职事「{rname}」提示「{clause}」没有登记接着它的 Crew 加成函数（ROLE_HINT_FN）"
                             "——代码里没有这条效力就别写")
                continue
            n += 1
            if f'level_of("{rid}")' not in funcs.get(fn, ""):
                FAILS.append(f"{tag}: 职事「{rname}」提示「{clause}」登记的 Crew.{fn} 不读「{rid}」的品级——效力不归这个职事")
            elif not re.search(r"(?<![\w.])Crew\.%s\(" % fn, game_src):
                FAILS.append(f"{tag}: 职事「{rname}」提示「{clause}」登记的 Crew.{fn} 在 {CREW_GD} 以外没有调用——效力没接进游戏")
    return n


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


def _self_test_event_fame():
    """钉 G 自检：钮文 +6、回调 += 4 须判红；+6 / += 6 须判绿。"""
    bad = []
    tpl = '\t_add_event_action("交出一条船（名声 +6）", _on_x)\n\nfunc _on_x() -> void:\n\tGameState.fame += %d\n'
    saved = FAILS[:]
    try:
        for n, want_red in ((4, True), (6, False)):
            FAILS.clear()
            seen = _check_event_fame(tpl % n, "self")
            if not seen or bool(FAILS) != want_red:
                bad.append(f"钉 G 自检：回调 += {n} 判{'红' if FAILS else '绿'}，应判{'红' if want_red else '绿'}")
    finally:
        FAILS.clear()
        FAILS.extend(saved)
    return bad


def _self_test_cargo_frac():
    """钉 K 自检：实扣 0.3、札记写「半个货舱」「两成货」须判红，写「三成货」须判绿；不调 lose_cargo_ratio 的函数不比。"""
    bad = []
    tpl = 'func _on_x() -> void:\n\tvar lost := Fleet.lose_cargo_ratio(0.3)\n\t_log("拿不出买路钱，他们自己动手%s。")\n'
    saved = FAILS[:]
    try:
        for said, want_red in (("搬空了半个货舱", True), ("搬走了两成货", True), ("搬走了三成货", False)):
            FAILS.clear()
            seen = _check_cargo_frac(tpl % said, "self")
            if not seen or bool(FAILS) != want_red:
                bad.append(f"钉 K 自检：札记「{said}」判{'红' if FAILS else '绿'}，应判{'红' if want_red else '绿'}")
        FAILS.clear()
        if _check_cargo_frac('func _on_y() -> void:\n\t_log("他们搬走了半个货舱。")\n', "self") or FAILS:
            bad.append("钉 K 自检：不调 lose_cargo_ratio 的函数也被比了")
    finally:
        FAILS.clear()
        FAILS.extend(saved)
    return bad


def _self_test_liang():
    """钉 L 自检：量词前 cn_num 不带 liang、手拼「成」不会写「两」须判红；带了 / 序数 / 会写「两」须判绿。"""
    bad = []
    cases = (
        ('func f() -> String:\n\treturn "%s成" % cn_num(2)\n', True),
        ('func f() -> String:\n\treturn "%s成" % cn_num(2, true)\n', False),
        ('func f() -> String:\n\treturn "第%s阵" % _cn_num(2)\n', False),
        ('func f() -> String:\n\treturn "%s%s成" % [NAMES[k], StatusHud.cn_num(x)]\n', True),
        ('func f() -> String:\n\treturn "%s%s成" % [\n\t\tNAMES[k], StatusHud.cn_num(x, true),\n\t]\n', False),
        ('func f() -> String:\n\tvar d := ["一", "二"]\n\treturn d[n] + "成"\n', True),
        ('func f() -> String:\n\tvar d := ["一", "二"]\n\treturn ("两" if n == 2 else d[n]) + "成"\n', False),
    )
    saved = FAILS[:]
    try:
        for src, want_red in cases:
            FAILS.clear()
            _check_liang(src, "self")
            if bool(FAILS) != want_red:
                bad.append(f"钉 L 自检：{src.splitlines()[1].strip()[:44]} 判{'红' if FAILS else '绿'}，应判{'红' if want_red else '绿'}")
    finally:
        FAILS.clear()
        FAILS.extend(saved)
    return bad


def _self_test_delta_note():
    """钉 N 自检：记事句的 +N / −N、「名声添」判红；括注预告与「名声加 / 减」判绿。"""
    cases = (
        ("委办交清，牙行付了 %d 钱。名声 +1。", True),
        ("[color=red]被哨船追上。罚钱 %d，名声 −4。[/color]", True),
        ("毁约即扣 %d 钱、名声 −1；误期作废同罚。", True),
        ("【呈报】「%s」入案。赏钱 %d，名声添 %d。", True),
        ("交出一条船（名声 +6）", False),
        ("替族里跑一趟事（费 6 日・30 钱，乡土 +3）", False),
        ("委办交清，牙行付了 %d 钱。名声加 1。", False),
        ("没有停。士气减 3。", False),
    )
    bad = []
    saved = FAILS[:]
    try:
        for text, want_red in cases:
            FAILS.clear()
            _check_delta_note(text, "self")
            if bool(FAILS) != want_red:
                bad.append(f"钉 N 自检：「{text[:24]}」判{'红' if FAILS else '绿'}，应判{'红' if want_red else '绿'}")
    finally:
        FAILS.clear()
        FAILS.extend(saved)
    return bad


def _self_test_interpunct():
    """钉 O 自检：半角「·」判红、全角「・」判绿。"""
    bad = []
    saved = FAILS[:]
    try:
        for text, want_red in (("歇 10 日　150\u00b7误期", True), ("歇 10 日　150・误期", False)):
            FAILS.clear()
            _check_interpunct(text, "self")
            if bool(FAILS) != want_red:
                bad.append(f"钉 O 自检：「{text}」判{'红' if FAILS else '绿'}，应判{'红' if want_red else '绿'}")
        for src, want_red in (('\treturn s + "\u00b7".join(bits)\n', True), ('\treturn t.replace("\u00b7", "・")\n', False)):
            FAILS.clear()
            _check_interpunct_bare(src, "self")
            if bool(FAILS) != want_red:
                bad.append(f"钉 O 自检：{src.strip()} 判{'红' if FAILS else '绿'}，应判{'红' if want_red else '绿'}")
    finally:
        FAILS.clear()
        FAILS.extend(saved)
    return bad


def _self_test_role_hints():
    """钉 M 自检：未登记的句、登记到别的职事的函数、没接进游戏的函数都须判红；照实的提示判绿。"""
    crew_src = ('func level_of(r):\n\treturn 0\n\nfunc speed_factor() -> float:\n\treturn 1.0 + 0.06 * level_of("huozhang")\n\n'
                'func interpreter_edge(p) -> float:\n\treturn 0.07 * level_of("tongshi")\n')
    game = "var v := Crew.speed_factor()\nvar e := Crew.interpreter_edge(pid)\n"
    cases = (
        ([{"id": "huozhang", "name": "火长", "effect_hint": "日行更远"}], game, False),
        ([{"id": "huozhang", "name": "火长", "effect_hint": "日行更远，不易失道"}], game, True),
        ([{"id": "zashi", "name": "杂事", "effect_hint": "在异国港口买卖更划算"}], game, True),
        ([{"id": "huozhang", "name": "火长", "effect_hint": "日行更远"}], "var e := Crew.interpreter_edge(pid)\n", True),
    )
    bad = []
    saved = FAILS[:]
    try:
        for roles, g, want_red in cases:
            FAILS.clear()
            _check_role_hints(roles, crew_src, g, "self")
            if bool(FAILS) != want_red:
                bad.append(f"钉 M 自检：{roles[0]['name']}「{roles[0]['effect_hint']}」判{'红' if FAILS else '绿'}，应判{'红' if want_red else '绿'}")
    finally:
        FAILS.clear()
        FAILS.extend(saved)
    return bad


def _self_test_glyphs(cmap):
    """钉 I 自检：字库读出来要像个文楷子集（常用字在、基本汉字区不全在）；常用字句判绿，
    字库外的字判红。cmap 读坏（空 / 全收）时这里先红，不让后面整扫沉默放行。"""
    if len(cmap) < 7000 or any(ord(c) not in cmap for c in "一桅斗上的人「」・，。"):
        return [f"钉 I 自检：{BODY_FONT} 读出 {len(cmap)} 个码位、常用字不全——字库不在或读法失真"]
    absent = next((chr(c) for c in range(0x4E00, 0x9FA6) if c not in cmap), "")
    if not absent:
        return [f"钉 I 自检：{BODY_FONT} 读出基本汉字区全收——子集不该如此，读法失真（真改发全量字库就改这条自检）"]
    bad = []
    saved = dict(GLYPH_MISS)
    try:
        GLYPH_MISS.clear()
        _check_glyphs("桅斗上的人喊了一声。", "self", cmap)
        if GLYPH_MISS:
            bad.append(f"钉 I 自检：常用字句被判缺字 {sorted(GLYPH_MISS)}")
        GLYPH_MISS.clear()
        _check_glyphs("桅斗上的%s望手。" % absent, "self", cmap)
        if list(GLYPH_MISS) != [absent]:
            bad.append(f"钉 I 自检：字库外的「{absent}」没被单独抓到（抓到 {sorted(GLYPH_MISS)}）")
    finally:
        GLYPH_MISS.clear()
        GLYPH_MISS.update(saved)
    return bad


def _scan_event_fame():
    rel = "scripts/SeaChart.gd"
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    seen = _check_event_fame(src, rel)
    for must in EVENT_FAME_MUST:
        if not any(must in lab for lab in seen):
            FAILS.append(f"{rel}: 钉 G 没抓到「{must}」钮文的「（名声 +N）」——钮文缺数或改了格式")


def _scan_cargo_frac():
    seen = set()
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if not f.endswith(".gd"):
                continue
            p = os.path.join(dirpath, f)
            rel = p[len(ROOT) + 1:].replace(os.sep, "/")
            src = open(p, encoding="utf-8").read()
            if "lose_cargo_ratio(" in src:
                seen.update((rel, name) for name, _said in _check_cargo_frac(src, rel))
    for rel, name in CARGO_FRAC_MUST:
        if (rel, name) not in seen:
            FAILS.append(f"{rel}: 钉 K 没抓到 {name} 札记里的货损成数——札记改了写法或正则抓空")


def _scan_liang():
    seen = set()
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if not f.endswith(".gd"):
                continue
            p = os.path.join(dirpath, f)
            rel = p[len(ROOT) + 1:].replace(os.sep, "/")
            seen.update(_check_liang(open(p, encoding="utf-8").read(), rel))
    for rel, cls in CN_LIANG_MUST:
        if (rel, cls) not in seen:
            FAILS.append(f"{rel}: 钉 L 没认出「%s{cls}」前带 liang 的 cn_num——格式串或实参解析坏了")
    _check_cn_helpers()


DELTA_PAREN_SEEN = []


def _scan_delta_paren_must():
    for rel, label in DELTA_PAREN_MUST:
        src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        if not any(label in t and t in src for t in DELTA_PAREN_SEEN):
            FAILS.append(f"{rel}: 钉 N 没认出「{label}」钮文括注里的增减——正则抓空或钮文改了格式")


def _scan_role_hints():
    roles = json.load(open(os.path.join(ROOT, CREW_JSON), encoding="utf-8")).get("roles", [])
    crew_src = open(os.path.join(ROOT, CREW_GD), encoding="utf-8").read()
    game = []
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            p = os.path.join(dirpath, f)
            if f.endswith(".gd") and p[len(ROOT) + 1:].replace(os.sep, "/") != CREW_GD:
                game.append(_code_only_gd(open(p, encoding="utf-8").read()))
    n = _check_role_hints(roles, crew_src, "\n".join(game), CREW_JSON)
    if n < len(ROLE_HINT_FN):
        FAILS.append(f"{CREW_JSON}: 钉 M 只核到 {n} 句职事提示，ROLE_HINT_FN 登记了 {len(ROLE_HINT_FN)} 句"
                     "——提示读不到，或改了提示没同步登记表")


def _code_only_gd(src):
    """去掉 # 注释（字符串里的 # 不算），只留代码供「有没有调用」判断。"""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in "\"'":
            j = _skip_str(src, i)
            out.append(src[i:j])
            i = j
            continue
        if c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _scan_crew_left_wiring():
    rel = "scripts/GameManager.gd"
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    body = _func_body_gd(src, "skip_years")
    if not body:
        FAILS.append(f"{rel}: 钉 H 找不到 func skip_years")
        return
    if "crew_left_line(" not in body:
        FAILS.append(f"{rel}: skip_years 的「没有再上船」一句没走 crew_left_line（单人会写成「有的…有的…」）")
    for lit, _pos in _gd_strings_only(body):
        if "有的回了乡" in lit:
            FAILS.append(f"{rel}: skip_years 内联了多人句「{lit[:40]}」，只走一人时说不通")


def main():
    cmap = _ttf_cmap(os.path.join(ROOT, BODY_FONT))
    glyph_fails = _self_test_glyphs(cmap)
    if glyph_fails:
        cmap = None
    self_fails = _self_test() + _self_test_event_fame() + _self_test_cargo_frac() + _self_test_liang() + _self_test_role_hints() + _self_test_delta_note() + _self_test_interpunct() + glyph_fails
    _scan_gd_strings(cmap)
    _scan_json_text()
    _scan_data_glyphs(cmap)
    _scan_tscn_glyphs(cmap)
    _report_glyphs()
    _scan_combat_data()
    _scan_event_fame()
    _scan_crew_left_wiring()
    _scan_cargo_frac()
    _scan_liang()
    _scan_role_hints()
    _scan_delta_paren_must()
    _scan_interpunct_bare()
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
