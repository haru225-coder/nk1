#!/usr/bin/env python3
"""lane w53-9：过场数据契约（tools/art/import_cutscene_bgs.py --data-only，必跑道 cutscene_data_only）的变异自检。

契约此前对镜头 / 字幕 / 章节卡的键不设防，而播放器只认固定几个键、别的键静默不认：
  · 字幕换句旗写错一个字母（unless_flag → unles_flag）：忠肃第 2 镜「出城侦敌」「缒城出降」两句同出；
    旗名写错（cao_opened → cao_openned）：关城门那一支的句子永远出不来；
  · hold 写错：该退的句子赖到换镜，压着后面的字；hold 过短：一闪就退，读不完；
  · 镜头 captions 写错：整镜没字幕；章节卡 focus 写错：取景按缺省走，画里的人被墨晕窗截一半；
  · 镜头 bg_alt（底图按旗换，与字幕同一套旗标写法）旗名写错：「未归」海口结算第 1 镜换不成兴化海口港页图，
    画面仍是海上船舷、字幕却是「消息是从城里传出来的」（四轮补：三轮的旗名判据只核字幕）；旗键名写错同样换不成；
  · 写字慢的大字挪晚：读完线原先只量起笔（t 离镜头结束 ≥1.5 秒），忠肃第 1 镜「生为宋臣／死为宋鬼」八个大字要写 2.8 秒，
    起笔 5.0 秒、镜终 8.0 秒照报通过，写全只停 0.21 秒就硬切（七轮补写全读完线；真数据已把这一镜让出时间）；
  · 年号竖排挪到左下横排写长：单行上限原先手抄一张表，era/lower_left 写 22 字，引擎一行只放得下 18，19 字折成两行照报通过
    （七轮改为按播放器字号 / 字距 / 排版宽现算）。
门禁照报「契约校验通过」。

本脚本拿真数据做底，逐个注入一种上面的笔误，写进临时文件交给 check_data(path) 判：每一种都要判红、
且红在该红的那一句（判词里带定位）；真数据本身零红。回退契约里未知键 / 旗标有人立（字幕与 bg_alt 两处）/ hold 读完线 /
写全读完线 / 单行上限现算几条判据，本脚本即红。

用法：python3 tools/qa_w53_9_cutscene_contract_mutants.py      # rc 0 全部判中且真数据零红；rc 1 有漏判或误红
"""
import copy
import importlib.util
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("import_cutscene_bgs", ROOT / "tools" / "art" / "import_cutscene_bgs.py")
contract = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(contract)


def _caption(d, cid, shot, pred):
    for c in d["cutscenes"][cid]["shots"][shot]["captions"]:
        if pred(c):
            return c
    raise LookupError(f"{cid}[{shot + 1}] 找不到要改的那句字幕——真数据变了，改本脚本的定位")


def _alt(d, cid, shot, pred):
    for a in d["cutscenes"][cid]["shots"][shot].get("bg_alt", []):
        if pred(a):
            return a
    raise LookupError(f"{cid}[{shot + 1}] 找不到要改的那条 bg_alt——真数据变了，改本脚本的定位")


def _rename(dct, old, new):
    dct[new] = dct.pop(old)


def m_flag_key(d):
    _rename(_caption(d, "ending_zhongsu", 1, lambda c: c.get("unless_flag") == "cao_opened"), "unless_flag", "unles_flag")


def m_flag_name(d):
    _caption(d, "ending_zhongsu", 1, lambda c: c.get("if_flag") == "cao_opened")["if_flag"] = "cao_openned"


def m_hold_key(d):
    _rename(_caption(d, "opening", 8, lambda c: c.get("hold") == 2.8), "hold", "hlod")


def m_hold_short(d):
    _caption(d, "opening", 8, lambda c: c.get("hold") == 2.8)["hold"] = 0.9


def m_captions_key(d):
    _rename(d["cutscenes"]["ending_ledger"]["shots"][3], "captions", "caption")


def m_chapter_key(d):
    _rename(d["chapters"]["2"], "focus", "fcous")


def m_alt_flag_name(d):
    _alt(d, "ending_weigui", 0, lambda a: a.get("if_flag") == "weigui_at_harbor")["if_flag"] = "weigui_at_harbour"


def m_motto_late(d):
    _caption(d, "ending_zhongsu", 0, lambda c: c.get("text", "").startswith("生为宋臣"))["t"] = 5.0


def m_era_lower_left_long(d):
    c = _caption(d, "ending_weigui", 0, lambda c: c.get("style") == "era")
    c["pos"] = "lower_left"
    c["text"] = "景炎元年十二月・消息是在别处听到的城破"


def m_alt_flag_key(d):
    _rename(_alt(d, "ending_weigui", 0, lambda a: a.get("if_flag") == "weigui_at_harbor"), "if_flag", "if_flg")


# （笔误，注入函数，判词里必须出现的定位片段）
MUTANTS = [
    ("字幕换句旗键名写错 unless_flag→unles_flag", m_flag_key, "cutscenes.ending_zhongsu[2].captions[1] 有不认的键 ['unles_flag']"),
    ("字幕换句旗旗名写错 cao_opened→cao_openned", m_flag_name, "cutscenes.ending_zhongsu[2].captions[2] if_flag 旗标 `cao_openned` 没人立"),
    ("字幕 hold 键名写错 hold→hlod", m_hold_key, "cutscenes.opening[9].captions[3] 有不认的键 ['hlod']"),
    ("字幕 hold 过短 2.8→0.9", m_hold_short, "cutscenes.opening[9].captions[3] hold=0.9 不足 1.5 秒"),
    ("镜头 captions 键名写错 captions→caption", m_captions_key, "cutscenes.ending_ledger[4] 有不认的键 ['caption']"),
    ("章节卡 focus 键名写错 focus→fcous", m_chapter_key, "chapters.2 有不认的键 ['fcous']"),
    ("镜头 bg_alt 旗名写错 weigui_at_harbor→weigui_at_harbour", m_alt_flag_name,
     "cutscenes.ending_weigui[1].bg_alt[1] if_flag 旗标 `weigui_at_harbour` 没人立"),
    ("镜头 bg_alt 旗键名写错 if_flag→if_flg", m_alt_flag_key, "cutscenes.ending_weigui[1].bg_alt[1] 有不认的键 ['if_flg']"),
    ("忠肃第 1 镜「生为宋臣／死为宋鬼」挪回起笔 5.0 秒", m_motto_late, "cutscenes.ending_zhongsu[1].captions[4] 写全后只停"),
    ("未归第 1 镜年号挪到左下写 19 字", m_era_lower_left_long,
     "cutscenes.ending_weigui[1].captions[1]「景炎元年十二月・消息是在别处听到的城破」19 字，超出 era/lower_left 单行上限 18"),
]


def main() -> int:
    fails = 0
    base_text = (ROOT / "data" / "cutscenes.json").read_text(encoding="utf-8")
    base = json.loads(base_text)
    real = contract.check_data()
    if real:
        fails += 1
        print(f"  ✗ 真数据本身就判红 {len(real)} 条（先修数据或契约）：")
        for b in real:
            print("      FAIL", b)
    else:
        print("  ✓ 真数据 data/cutscenes.json 契约零红")
    with tempfile.TemporaryDirectory(prefix="w53_9_cs_contract_") as tmp:
        for i, (name, mutate, want) in enumerate(MUTANTS, 1):
            d = copy.deepcopy(base)
            mutate(d)
            path = pathlib.Path(tmp) / f"m{i}.json"
            path.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
            bad = contract.check_data(path)
            if any(want in b for b in bad):
                print(f"  ✓ M{i} {name}：判红「{next(b for b in bad if want in b)[:90]}…」")
            else:
                fails += 1
                print(f"  ✗ M{i} {name}：漏判——契约 {len(bad)} 条红里没有「{want}」" + ("：" if bad else "（契约照报通过）"))
                for b in bad:
                    print("      FAIL", b)
    print("结果：全部通过" if fails == 0 else f"结果：{fails} 项问题")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
