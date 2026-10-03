extends SceneTree
## lane w53-8：海战墨边题签（scripts/ui/CombatLetterbox.gd）长副题不冲出画布右缘。
## 证（1280×720 与 21:9 1706×720 两种画布；headless 也跑——直接实例化墨边，不走 _spawn 的 headless 拦路）：
##   1. 出战题签照真收场口径拼（outcome_title + exit_subtitle：日期 + 敌船下场 + 我方折损）：
##      南岛海道北口外海受降三艘 + 折水手失船颠落货三段齐写、南岛海道北口外海夺船一走脱一 + 三段折损——
##      题签整行右沿不过「画布宽 − 左边距」（与左边同样留 64 px），且整行仍落在下墨边里。
##   2. 常见收场（泉州外海击沉快船二艘 + 折水手、颠落货）与入战题签：题名照旧 34、副题照旧正文字阶 18，
##      不因修法被白白缩字；21:9 下上面的长副题也放得下、不缩字。
##   3. 极端长副题（五种下场两种船 + 三段折损）：缩到底仍放不下时副题末尾收「…」，右沿照样不出界。
## 旧病（回退即红）：_layout 只按整行宽缩题名（最小 22），副题一字不缩；出战副题自 aa145a5 起多了
## 「颠落舱面货 N 件」一段，南岛海道北口这类长港名下题签宽 1324，右沿冲出 1280 画布 116 px（实截
## 「…折水手二十三人，失船一艘，颠落」后半截看不见），夺船一走脱一那条也冲出 16 px。
## 用法：godot --headless --path . -s res://tools/qa_w53_8_letterbox_fit_probe.gd（带窗口 DISPLAY=:2 同样可跑）

const LB_PATH := "res://scripts/ui/CombatLetterbox.gd"
const CAPTION_X := 64.0
const TITLE_SIZE := 34

var _fails: Array = []
var LB: GDScript


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK %s" % what)
	else:
		_fails.append(what)
		print("FAIL %s" % what)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


## 摆一副墨边演出战，排完版返回 [题签矩形, 题名字号, 副题字号, 副题是否收省略号, 墨边高]
func _measure(title: String, sub: String, enter := false) -> Array:
	var lb: CanvasLayer = LB.new()
	root.add_child(lb)
	await _frames(2)
	if enter:
		lb.call("play_enter", title, sub)
	else:
		lb.call("play_exit", title, sub)
	await _frames(3)
	var r: Rect2 = lb.call("caption_rect")
	var head: Label = lb.get("_head")
	var sub_l: Label = lb.get("_sub")
	var out := [r, head.get_theme_font_size("font_size"), sub_l.get_theme_font_size("font_size"),
		sub_l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING, float(lb.call("bar_height"))]
	lb.queue_free()
	await _frames(2)
	return out


func _fits(tag: String, got: Array, cv: Vector2) -> void:
	var r: Rect2 = got[0]
	var h: float = got[4]
	_check(r.end.x <= cv.x - CAPTION_X + 0.5,
		"%s：题签右沿 %.0f 不过 %.0f（画布 %.0f 减左右各留 %d）——题签 %s" % [tag, r.end.x, cv.x - CAPTION_X, cv.x, int(CAPTION_X), r])
	_check(r.position.y >= cv.y - h - 1.0 and r.end.y <= cv.y + 1.0, "%s：题签仍落在下墨边里（%s，墨边 %.0f）" % [tag, r, h])


func _run() -> void:
	LB = load(LB_PATH) as GDScript
	var date := "咸淳十年　十二月廿九"
	var long3: String = LB.exit_subtitle(date,
		[{"type": "sea_falcon", "fate": "struck"}, {"type": "sea_falcon", "fate": "boarded"}, {"type": "sea_falcon", "fate": "sunk"}],
		{"crew": 23, "ships": 1, "cargo": 17})
	var long2: String = LB.exit_subtitle(date,
		[{"type": "pirate_boat", "fate": "boarded"}, {"type": "pirate_boat", "fate": "fled"}],
		{"crew": 18, "ships": 1, "cargo": 12})
	var common: String = LB.exit_subtitle("景炎元年　腊月二十",
		[{"type": "pirate_boat", "fate": "sunk", "count": 2}], {"crew": 7, "cargo": 4})
	var extreme: String = LB.exit_subtitle(date,
		[{"type": "sea_falcon", "fate": "struck", "count": 2}, {"type": "pirate_boat", "fate": "struck"},
		{"type": "pirate_boat", "fate": "boarded", "count": 2}, {"type": "sea_falcon", "fate": "burned"},
		{"type": "pirate_boat", "fate": "sunk", "count": 3}, {"type": "sea_falcon", "fate": "sunk"},
		{"type": "sea_falcon", "fate": "fled", "count": 2}],
		{"crew": 123, "ships": 3, "cargo": 117})
	var t_struck: String = LB.outcome_title("surrender", "南岛海道北口外海")
	var t_board: String = LB.outcome_title("board", "南岛海道北口外海")
	var t_common: String = LB.outcome_title("win", "泉州外海")

	root.size = Vector2i(1280, 720)
	await _frames(4)
	var cv := root.get_visible_rect().size
	print("画布 %s" % cv)
	var got := await _measure(t_struck, long3)
	print("  「%s」+「%s」（%d 字）→ 题名 %d 副题 %d 省略 %s 题签 %s" % [t_struck, long3, long3.length(), got[1], got[2], got[3], got[0]])
	_fits("1280×720 受降三艘 + 三段折损", got, cv)
	got = await _measure(t_board, long2)
	print("  「%s」+「%s」（%d 字）→ 题名 %d 副题 %d 题签 %s" % [t_board, long2, long2.length(), got[1], got[2], got[0]])
	_fits("1280×720 夺船一走脱一 + 三段折损", got, cv)
	got = await _measure(t_common, common)
	_fits("1280×720 常见收场", got, cv)
	_check(int(got[1]) == TITLE_SIZE and int(got[2]) == UiTheme.SIZE_BODY and not bool(got[3]),
		"1280×720 常见收场「%s」不缩字：题名 %d（应 %d）、副题 %d（应 %d）、无省略" % [common, got[1], TITLE_SIZE, got[2], UiTheme.SIZE_BODY])
	got = await _measure("泉州外海・遇敌", "景炎元年　腊月二十　海鹘三艘", true)
	_fits("1280×720 入战题签", got, cv)
	_check(int(got[1]) == TITLE_SIZE and int(got[2]) == UiTheme.SIZE_BODY, "1280×720 入战题签不缩字（题名 %d、副题 %d）" % [got[1], got[2]])
	got = await _measure(t_struck, extreme)
	print("  极端副题（%d 字）→ 题名 %d 副题 %d 省略 %s 题签 %s" % [extreme.length(), got[1], got[2], got[3], got[0]])
	_fits("1280×720 极端长副题", got, cv)
	_check(bool(got[3]), "1280×720 极端长副题缩到底仍放不下时末尾收「…」")

	root.size = Vector2i(2560, 1080)
	await _frames(4)
	cv = root.get_visible_rect().size
	print("画布 %s" % cv)
	got = await _measure(t_struck, long3)
	_fits("21:9 受降三艘 + 三段折损", got, cv)
	_check(int(got[2]) == UiTheme.SIZE_BODY and not bool(got[3]), "21:9 画布放得下就不缩副题（副题 %d）" % got[2])

	print("QA_W53_8_LETTERBOX_FIT_PROBE %s（%d 项不合）" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	quit(0 if _fails.is_empty() else 1)
