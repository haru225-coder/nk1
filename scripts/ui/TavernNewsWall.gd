class_name TavernNewsWall
extends RefCounted
## 酒馆墙上的市井札薄。把 GameState.recent_news 渲成宣纸札记条；
## Main._setup_news_wall 只调 mount，不承担样式。无新闻则不上墙。

## 把最近 k 条墙上贴得出的已投放新闻（posted）挂到 into（通常是 choices_container）。返回实际上墙条数。
static func mount(into: Node, k: int = 3) -> int:
	if into == null:
		return 0
	var wall: Array = []
	for n in GameState.recent_news(GameState.news_seen.size()):
		if posted(n):
			wall.append(n)
		if wall.size() >= k:
			break
	if wall.is_empty():
		return 0
	var sep := Label.new()
	sep.text = "墙上"
	UiTheme.style_section_label(sep)
	into.add_child(sep)
	for n in wall:
		into.add_child(_make_slip(n))
	return wall.size()


## 单条札记：宣纸卡 + 年月旁注 + 说话人题签 + 正文。
static func _make_slip(n: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	UiTheme.paper_card(card)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	var speaker := str(n.get("speaker", "")).strip_edges()
	var who := "酒馆传闻" if speaker == "" else speaker
	var who_lbl := Label.new()
	who_lbl.text = who
	who_lbl.add_theme_font_override("font", UiTheme.title_font() if UiTheme.IS_JUANBEN else UiTheme.font())
	who_lbl.add_theme_font_size_override("font_size", 18)
	who_lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.GOLD))
	who_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(who_lbl)

	var date := str(n.get("date", "")).strip_edges()
	if date != "":
		var date_lbl := Label.new()
		date_lbl.text = era_month(date)
		UiTheme.style_footnote(date_lbl)
		date_lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT_DIM))
		date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(date_lbl)

	var body := Label.new()
	body.text = GameState.news_text(n)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("font", UiTheme.font())
	body.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	body.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)

	return card


## 年月旁注：news.json 的「1276-05」写成「景炎元年五月」，与顶匾、船籍簿、辞船淡字同一套（跳年摘要也明说不写阿拉伯公元年）。
## 年号月名借 Calendar 自己的写法（临时拨到那一月、算完拨回，同 Main._siege_fall_point）；改元当年按月分（1276 正月德祐二年、五月景炎元年）。
## 写得不对的原样返回。
static func era_month(ym: String) -> String:
	var p := ym.split("-")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int() or int(p[1]) < 1 or int(p[1]) > 12:
		return ym
	var keep: Dictionary = Calendar.to_dict()
	Calendar.from_dict({"year": int(p[0]), "month": int(p[1]), "day": 1})
	var out := Calendar.get_era_year_string() + Calendar.get_month_name()
	Calendar.from_dict(keep)
	return out


## 墙上只贴市井听得到的。只发给士人身份、又没有说话人的那几条是临安寄给你一人的短札
## （「短札：你弹劾范文虎、赵溍、黄万石……贬你知抚州」「累迁参知政事」），不是酒馆传闻——修前照样题「酒馆传闻」
## 贴在任一港的酒馆墙上，最近三条里能占两条。有说话人的（小瘸子当面说兴化募兵）是酒桌上的话，照贴；
## 只发给海商的「传闻：……崖山」也是市井传闻，照贴。月初札记里的通告不归这里管。
static func posted(n: Dictionary) -> bool:
	return not (str(n.get("only", "")) == "scholar" and str(n.get("speaker", "")).strip_edges() == "")
