extends SceneTree
## chars 线「数据接线」巡检重打（lane w26-k8；b6 遗留①：w20-a3 工单那支带钉探针随 36f91de 湮灭，36f91de 全卷已
##   考古找回，见 /workspace/nk1-agent-briefs/lane-w26-k8-chars-wire-probe.md §Verify）。本片补湮灭单从没钉过的一环——
##   「Characters 数据 → 屏上人物」逐行对上：湮灭前那支只截 4 张图、零数据断言，上图对不对全靠目睹，故湮灭后一条断言都复跑不了。
## 用法：NK1_SHOT_DIR=<root> DISPLAY=:2 godot --path . -s res://tools/qa_chars_wire_screenshots.gd   # 截图门禁（须出 6 张 wire_*.png）
##       godot --headless --path . -s res://tools/qa_chars_wire_screenshots.gd -- --contract             # 只验断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 判定项（全部按人物数据经 GameManager 取数口现读真值逐行对屏上控件文本——
##   探针与上屏同一条取数口，dict 一改全链都跟着改）：
##   W1 无角色的档：直接起岸上名册浮页。begin("chen_wenlong") 选中者落在「主」页签，右栏名行 / 左栏立绘名牌 / 品级签
##      逐个 == display_name 与 TIER_NAME[tier] 真值。
##   W2 focus_id("chen_zan")：名牌 == 陈瓒；右栏短注第一行前 24 字 == codex_short 真值；「身份」行在文本层口径下
##      不得透出隐藏 origin 前缀（玉湖陈氏 / 兴化莆田玉湖——Ch2 前这些是隐藏段，上屏不许透）；trait 签逐枚 == traits_of。
##   W3 focus_id("merchant_lin")：阵营签 == faction_def 的玉湖陈氏→泉州海商转场对上；名牌 / 品级签 == 要人真值。
##   W4 有角色的档：临时整仓雇舵工 ChenLaodaoProbe（hire → hired={duogong:选型 id}；探针尾 dismiss(role)
##      复原必走、全程不落存档）：「职事」页签在船 Row_ id 序列 == hired 账册 id（无档空、有档一枚 chen_laodao、
##      首行名 == 数据 display_name——名册数据源切错登对即红）；
##      陈老舵右栏：阵营签 == 海上人（浅底深字含对焦）、五维数字 == attrs 五值按 attr_def 序全对上、短注 == 真值。
##      这是湮灭工单最有名的一处「漏洞」：旧探针只出一张「名册职事页」图、职事行有没有绑对账册 id 从不断言。
##   W5 每档各一屏：无角色的档三屏（W1 主档全景 / W2 陈瓒 / W3 泉州海商）+ 职事页无档空档一屏；有角色的档两屏（替身全景 /
##      陈老舵详情）；共 6 张 wire_*.png。
##   ——名牌 / 品级 / 阵营 / 五维 / 短注 / 身份行隐藏段不透出，六项断言每一行在判什么都写在上头对应的 ## 行里。
## 反向变异自证（探针不依赖被改件的措辞，换行对不上即 rc=1）：「focus_id 后 _panel 信然不改（选中者接线断）」→ W2 / W3 红；
##   「陈瓒的 faction / bio_short 改错」→ W2 / W3 红；「hired 底账改绑别 id（数据源切错）」→ W4 红（验证留痕见 Verify）。
## 接线口径：等待只走 probe_clock 的演出推进（帧数下限 + 补间演完 + 墙钟上界），不按魔法帧数 --quit-after；
##   出图一律 ShotGate.shot（空视口 / 一色空图 / 张数不足都以真失败计）。NK1_CHARS_SYNC=1 防后台拉立绘线程把截图打花。

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("chars")
const TAG := "QA_CHARS_WIRE"
const EXPECTED_SHOTS := 6
const HIRE_BOND := "chen_laodao"
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
var _ov: Control
var _crew: Node
var _gm: Node
var _Art: GDScript
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("NK1_CHARS_SYNC", "1")
	root.size = Vector2i(VIEW)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_CHARS_WIRE_BEGIN")
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.055, 1.0)
	ShotGate.frame_pressure(self)
	root.add_child(bg)
	# ── 无角色的档（W1–W3）：经场景实例化，等 autoload就绪后再解析脚本
	_gm = root.get_node_or_null("/root/GameManager")
	_Art = load("res://scripts/ui/CharacterArt.gd")  # 树起来后再解析：它静态段引用 GameManager/GameState autoload
	_crew = root.get_node_or_null("/root/Crew")
	_ov = ShotGate.start_tree_probe("res://scenes/chars/CharsShoreOverlay.tscn", _fails, TAG)
	if _ov == null:
		quit(_finish())
		return
	root.add_child(_ov)
	_ov.call("begin", "chen_wenlong")
	await _settle(14)
	await _shot("wire_01_roster_panel")
	# W1：无角色的档——选中者 == 请求者；右栏名行 / 名牌 / 品级签 == 数据真值
	_expect_selected("W1", "chen_wenlong")
	_expect_panel_badge("W1", "chen_wenlong")
	_expect_panel_pin("W1", "chen_wenlong")

	_ov.call("focus_id", "chen_zan")
	await _settle(8)
	await _shot("wire_02_placeholder")
	# W2：陈瓒短注 / 身份行（文本层隐藏段不得透出）/ trait 签 == 数据真值
	_expect_panel_badge("W2", "chen_zan")
	_expect_bio_short("W2", "chen_zan")
	_expect_identity_masked("W2", "chen_zan", ["玉湖陈氏", "兴化莆田玉湖"])
	_expect_traits("W2", "chen_zan")

	_ov.call("focus_id", "merchant_lin")
	await _settle(6)
	await _shot("wire_03_merchant_lin")
	# W3：林阿舶阵营签「泉州海商」（转换点错一位都对不上）；名牌 / 品级签 == 要人
	_expect_faction("W3", "merchant_lin")
	_expect_panel_badge("W3", "merchant_lin")
	_expect_panel_pin("W3", "merchant_lin")

	var roster: Node = _ov.get("_roster")
	if roster == null or not roster.has_method("_on_tab"):
		_fail("W1：浮页左栏缺 CharRoster / _on_tab")
		quit(_finish())
		return
	roster.call("_on_tab", "职事")
	await _settle(6)
	await _shot("wire_04_roster_crew")
	# W4a：职事页签在无角色的档下查无职事行（有行即「无档却陈列」）
	_expect_crew_rows("W4a", roster, [])

	# ── 有角色的档（W4b–W4d）：现场雇一名舵工，探针尾 dismiss(role) 复原（不入存档）
	# 名册行是新时聘就的——雇人前先把职事页重排一遭，之后 hired 变动才有研究资格
	roster.call("_on_tab", "主")
	await _settle(2)
	roster.call("_on_tab", "职事")
	await _settle(4)
	var bond: Dictionary = _crew.call("hire", HIRE_BOND)
	if not bool(bond.get("ok", false)):
		_fail("W4b：hire(%s) 失败（%s），有角色的档无从演" % [HIRE_BOND, str(bond.get("msg", ""))])
		_crew.call("dismiss", str(_crew.call("candidate_def", HIRE_BOND).get("role", "")))
		quit(_finish())
		return
	await _settle(2)
	await _shot("wire_05_hired_crew")
	# W4b：职事页签行数 / 首行名 == hired 真值（陈老舵一名在职）
	_expect_crew_rows("W4b", roster, [HIRE_BOND])
	# W4c / W4d：有档下右栏——选中者 == 雇者；海上人浅底阵营签 / 五维数字 / 短注 == 数据真值
	_ov.call("focus_id", HIRE_BOND)
	await _settle(6)
	await _shot("wire_06_hired_detail")
	_expect_selected("W4c", HIRE_BOND)
	_expect_panel_badge("W4c", HIRE_BOND)
	_expect_faction("W4c", HIRE_BOND)
	_expect_attrs("W4c", HIRE_BOND)
	_expect_bio_short("W4d", HIRE_BOND)

	_crew.call("dismiss", str(_crew.call("candidate_def", HIRE_BOND).get("role", "")))
	quit(_finish())


func _finish() -> int:
	return ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails)


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)
		print("  ✗ 演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _shot(stem: String) -> void:
	await _settle(2)
	_expect_fits(stem)
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)


## ── 数据真值 ────────────────────────────────────────────

func _char(where: String, id: String) -> Dictionary:
	var ch: Dictionary = _gm.call("get_character", id)
	if ch.is_empty():
		_fail("%s：get_character(%s) 空（数据 / 载入断线，以上断言无从对）" % [where, id])
	return ch


func _panel_pin(where: String) -> bool:
	var panel: Node = _ov.get("_panel")
	if panel == null:
		_fail("%s：右栏缺 CharPortraitPanel" % where)
		return false
	if str(panel.get("current_id")) == "":
		_fail("%s：CharPortraitPanel.current_id 空，show_character 没走" % where)
		return false
	return true


func _panel_label(where: String, path: String) -> Label:
	var panel := _ov.get("_panel") as Control
	if panel == null:
		_fail("%s：右栏缺 CharPortraitPanel" % where)
		return null
	var l := panel.find_child(path, true, false) as Label
	if l == null:
		_fail("%s：CharPortraitPanel 下找不到 %s（接线点名失配）" % [where, path])
	return l


## W1/W4c：选中者 == 探针请求者；右栏名行 / 左栏立绘名牌 == 数据的 display_name（玩家名口径下同一条线）
func _expect_selected(where: String, id: String) -> void:
	var want := str(_ov.get("current_id"))
	if want != id:
		_fail("%s：浮页选中者 %s ≠ 探针请求 %s（名册接线改错档 / 改错行）" % [where, want, id])


func _expect_panel_badge(where: String, id: String) -> void:
	if not _panel_pin(where):
		return
	var ch := _char(where, id)
	if ch.is_empty():
		return
	var nm: String = _Art.display_name(ch)
	var head := _panel_label(where, "Name")
	if head != null and str(head.text) != nm:
		_fail("%s：名行上屏「%s」≠ 数据 %s.display_name「%s」" % [where, str(head.text), id, nm])
	## 立绘名牌挂在 PortraitFrame（绢本）底下，跨过 ScrollContainer 结构，从整页搜
	var plate := _ov.find_child("NamePlate", true, false)
	if plate == null:
		if DisplayServer.get_name() != "headless":
			_fail("%s：绢本画框缺 NamePlate（名牌无从判）" % where)
	elif (plate as Control).get_child_count() == 0 or str(((plate as Control).get_child(0) as Label).text) != nm:
		_fail("%s：名牌「%s」≠ 数据 %s.display_name「%s」（绢本画框名牌断线）" % [where, str(((plate as Control).get_child(0) as Label).text) if (plate as Control).get_child_count() > 0 else "<empty>", id, nm])


## W1/W3/W4c：立绘下方品级签 == TIER_NAME[tier]（层级口径改断即红）
func _expect_panel_pin(where: String, id: String) -> void:
	if not _panel_pin(where):
		return
	var ch := _char(where, id)
	if ch.is_empty():
		return
	var want: String = str(_Art.TIER_NAME.get(str(ch.get("tier", "")), ""))
	var panel := _ov.get("_panel") as Control
	var chips := panel.find_child("Chips", true, false) as Container if panel != null else null
	if chips == null:
		_fail("%s：CharPortraitPanel 缺 Chips（品级签无处查）" % where)
		return
	var pin := chips.get_child(1) as Label if chips.get_child_count() >= 2 else null
	if pin == null:
		_fail("%s：Chips 第 2 枚不是 Label（faction_chip / 品级签序断）" % where)
		return
	if str(pin.text) != want:
		_fail("%s：品级签「%s」≠ TIER_NAME[%s.tier=%s]「%s」" % [where, str(pin.text), id, str(ch.get("tier", "")), want])


## W2/W4d：右栏短注第一行前 24 字 == codex_short 真值（隐藏段 / 换稿都对得上）
func _expect_bio_short(where: String, id: String) -> void:
	if not _panel_pin(where):
		return
	var ch := _char(where, id)
	if ch.is_empty():
		return
	var want: String = _Art.codex_short(ch).left(24)
	var l := _panel_label(where, "Short")
	if l == null:
		return
	if not str(l.text).begins_with(want):
		_fail("%s：%s 短注上屏「%s…」≠ 数据 codex_short 前 24 字「%s…」（换稿 / 隐藏段口径错）" % [where, id, str(l.text).left(24), want])


## W2：「身份」行不得透出隐藏 origin 前缀（layer 口径断——未解锁的设定上了屏即红）
func _expect_identity_masked(where: String, id: String, masked: Array) -> void:
	if not _panel_pin(where):
		return
	if _char(where, id).is_empty():
		return
	var panel := _ov.get("_panel") as Control
	var info := panel.find_child("Info", true, false) as Container if panel != null else null
	if info == null:
		_fail("%s：CharPortraitPanel 缺 Info（_kv 行无处查）" % where)
		return
	for row in info.get_children():
		var h := row as Container
		if h == null or h.get_child_count() < 2:
			continue
		var k := h.get_child(0) as Label
		if k == null or str(k.text) != "身份":
			continue
		var v := str((h.get_child(1) as Label).text)
		for m in masked:
			if v.contains(str(m)):
				_fail("%s：%s 身份行「%s」透出隐藏段「%s」（layer 口径断——未解锁的设定上了屏）" % [where, id, v, str(m)])
		return
	_fail("%s：Info 里找不到「身份」行（_kv 接线断）" % where)


## W2：trait 签逐枚 == traits_of 的 trait_def 名（特技断错线即红）
func _expect_traits(where: String, id: String) -> void:
	if not _panel_pin(where):
		return
	var ch := _char(where, id)
	if ch.is_empty():
		return
	var panel := _ov.get("_panel") as Control
	var row := panel.find_child("TraitRow", true, false) as Container if panel != null else null
	if row == null:
		_fail("%s：CharPortraitPanel 缺 TraitRow（特技签无处查）" % where)
		return
	var want: Array = []
	for t in _Art.traits_of(ch):
		want.append(str(_Art.trait_def(str(t)).get("name", str(t))))
	var got: Array = []
	for badge in row.get_children():
		var l := (badge as Control).get_child(0) as Label if (badge as Control).get_child_count() > 0 else null
		got.append(str(l.text) if l != null else "<no label>")
	if got != want:
		_fail("%s：%s trait 签 %s ≠ 数据 traits→trait_def.name %s（traits 接线断）" % [where, id, str(got), str(want)])


## W3/W4c：阵营签 == faction_def[faction].name（玉湖陈氏→泉州海商→海上人三档转场）
func _expect_faction(where: String, id: String) -> void:
	if not _panel_pin(where):
		return
	var ch := _char(where, id)
	if ch.is_empty():
		return
	var want: String = str(_Art.faction_def(str(ch.get("faction", ""))).get("name", str(ch.get("faction", ""))))
	var panel := _ov.get("_panel") as Control
	## 阵营签是 Chips 第 1 枚（show_character 现搭时一个不落）；dev 流派 CharsDemo 另起名——这里以名字打头
	var chips := panel.find_child("Chips", true, false) as Container
	if chips == null or chips.get_child_count() == 0:
		_fail("%s：CharPortraitPanel 缺 Chips（阵营签无处查）" % where)
		return
	var chip := chips.get_child(0) as PanelContainer
	if chip == null or chip.get_child_count() == 0:
		_fail("%s：Chips 第 1 枚不是 PanelContainer（faction_chip 换成别家了就查不到）" % where)
		return
	var l := chip.get_child(0) as Label
	if l == null or str(l.text) != want:
		_fail("%s：%s 阵营签「%s」≠ faction_def[%s].name「%s」（faction 接线断）" % [where, id, str(l.text) if l != null else "<null>", str(ch.get("faction", "")), want])


## W4c：五维右列数字 == attrs 五值按 attr_def 序全对上（换源 / 改值即红）
func _expect_attrs(where: String, id: String) -> void:
	if not _panel_pin(where):
		return
	var ch := _char(where, id)
	if ch.is_empty():
		return
	var panel := _ov.get("_panel") as Control
	var block := panel.find_child("AttrBlock", true, false) as Container if panel != null else null
	if block == null:
		_fail("%s：CharPortraitPanel 缺 AttrBlock（五维无处查）" % where)
		return
	var defs: Array = _Art.attr_defs()
	var attrs: Dictionary = _Art.attrs_of(ch)
	var want: Array = []
	for ad in defs:
		want.append(str(clampi(int(attrs.get(str(ad.get("key", "")), 0)), 0, 100)))
	var got: Array = []
	for r in block.get_children():
		var row := r as Container
		if row != null and row.get_child_count() >= 3:
			got.append(str((row.get_child(2) as Label).text))
	if got != want:
		_fail("%s：%s 五维上屏 %s ≠ 数据 attrs（attr_def 序）%s（attrs 接线断）" % [where, id, str(got), str(want)])


## W4a/W4b：「职事」页签全体候选人常驻（18 人是名册合同）；在船者另体现在行上。
##   这里钉两件事：① prevalence —— 每枚 Row_<id> 首行名 == 数据 display_name（名册数据源切错登对即红）；② boarding ——
##   hired 账册里的 id 在 page 上 Row_<id> 必须存在（无档 hired 为空 —— 什么多出来的都不该多）。
func _expect_crew_rows(where: String, roster: Object, hired_ids: Array) -> void:
	var list := roster.find_child("RosterList", true, false) as VBoxContainer
	if list == null:
		_fail("%s：名册职事页缺 RosterList（行容器接线断）" % where)
		return
	var rows: Dictionary = {}
	for row in list.get_children():
		if str(row.name).begins_with("Row_"):
			rows[str(row.name).substr(4)] = row
	for id in rows.keys():
		var row := rows[id] as Container
		var labels := row.find_children("*", "Label", true, false)
		var ch: Dictionary = _gm.call("get_character", str(id))
		if ch.is_empty():
			_fail("%s：Row_%s 的 id 账册查无此人（名册里混进了不在数据原稿的行）" % [where, str(id)])
			continue
		var want: String = _Art.display_name(ch)
		if labels.size() < 1 or str((labels[0] as Label).text) != want:
			_fail("%s：Row_%s 首行名「%s」≠ 数据 display_name「%s」（替身对位断——名册 id 挂错了名）" % [where, str(id), str((labels[0] as Label).text) if labels.size() > 0 else "<no label>", want])
	for id in hired_ids:
		if not rows.has(str(id)):
			_fail("%s：在船者 %s 的 Row_ 没落进职事页签（其职事锚档 / 页签切片断）" % [where, str(id)])


## lane fx1：浮页在视口里放得下——WireSheet 最小宽 ≤ 视口宽减左右边距，整框与「合上」钮不出视口右缘 / 下缘
func _expect_fits(where: String) -> void:
	var sheet := _ov.get("_sheet") as Control
	var close := _ov.find_child("CloseButton", true, false) as Control
	if sheet == null or close == null:
		_fail("%s：浮页缺 WireSheet / CloseButton" % where)
		return
	var vp := root.get_visible_rect()
	var room := vp.size.x - sheet.offset_left + sheet.offset_right
	var min_w := sheet.get_combined_minimum_size().x
	if min_w > room + 0.5:
		_fail("%s：浮页最小宽 %.0f 超出视口可用宽 %.0f（名册行 / 立绘面板有字撑宽）" % [where, min_w, room])
	for pair in [["WireSheet", sheet.get_global_rect()], ["「合上」钮", close.get_global_rect()]]:
		var r: Rect2 = pair[1]
		if r.end.x > vp.end.x + 0.5 or r.end.y > vp.end.y + 0.5 or r.position.x < vp.position.x - 0.5:
			_fail("%s：%s %s 出视口 %s" % [where, str(pair[0]), str(r), str(vp)])


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("  ✗ " + msg)


## lane w19-g6：三处名册宿主 × 三档视口，按比例分栏且不裁不挤
const SPLIT_VIEWS := [Vector2i(1280, 720), Vector2i(1706, 720), Vector2i(1920, 1080)]


func _expect_split_hosts() -> void:
	var consts := (load("res://scripts/chars/CharRoster.gd") as GDScript).get_script_constant_map()
	if not consts.has("COLUMN_RATIO") or not consts.has("COLUMN_MIN_W"):
		_fail("CharRoster 缺分栏常量 COLUMN_RATIO / COLUMN_MIN_W（三处名册宿主该同走 split_columns）")
		return
	var ratio := float(consts["COLUMN_RATIO"])
	var min_w := float(consts["COLUMN_MIN_W"])
	for kind in ["人物志内嵌名册", "岸上名册浮页", "CharsDemo"]:
		for sz in SPLIT_VIEWS:
			var vp := SubViewport.new()
			vp.size = sz
			vp.disable_3d = kind != "CharsDemo"
			root.add_child(vp)
			var host: Control
			if kind == "人物志内嵌名册":
				host = (load("res://scripts/ui/CharacterCodex.gd") as GDScript).new()
				vp.add_child(host)
				host.call("begin", "")
				host.call("_open_chars_wire")
			elif kind == "岸上名册浮页":
				host = (load("res://scenes/chars/CharsShoreOverlay.tscn") as PackedScene).instantiate()
				vp.add_child(host)
				host.call("begin", "chen_wenlong")
			else:
				host = (load("res://scenes/chars/CharsDemo.tscn") as PackedScene).instantiate()
				vp.add_child(host)
			await _settle(8)
			var where := "%s %d×%d" % [kind, sz.x, sz.y]
			_expect_split(where, host, sz, ratio, min_w)
			if kind == "CharsDemo" and not (host.has_method("is_narrow") and host.has_method("_show_view")):
				_fail("%s：演示页缺 is_narrow / _show_view，窄屏两栏无从查" % where)
			elif kind == "CharsDemo" and bool(host.call("is_narrow")):
				var vb := host.find_child("ViewButton", true, false) as Button
				if vb == null or not vb.is_visible_in_tree():
					_fail("%s：窄屏两栏却没有「看站台」钮，站台无从换看" % where)
				host.call("_show_view", "stage")
				await _settle(4)
				_expect_split(where + "（换看站台）", host, sz, ratio, min_w)
				host.call("_show_view", "panel")
			vp.queue_free()
			await process_frame


func _expect_split(where: String, host: Control, sz: Vector2i, ratio: float, min_w: float) -> void:
	var left := host.find_child("RosterHost", true, false) as Control
	if left == null:
		left = host.find_child("RosterPanel", true, false) as Control
	if left == null:
		_fail("%s：找不到名册左栏（RosterHost / RosterPanel）" % where)
		return
	var row := left.get_parent() as Control
	var cols: Array = []
	for c in row.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			cols.append(c)
	var right: Control = null
	for c in cols:
		if c != left and (c as Control).size_flags_horizontal & Control.SIZE_EXPAND:
			right = c
	if right == null:
		_fail("%s：名册右边没有按比例分宽的栏" % where)
		return
	if absf(left.size_flags_stretch_ratio - ratio) > 0.001 or not (left.size_flags_horizontal & Control.SIZE_EXPAND) \
			or left.custom_minimum_size.x < min_w - 0.5 or absf(right.size_flags_stretch_ratio - 1.0) > 0.001:
		_fail("%s：左栏没走 CharRoster.split_columns（stretch %.2f / 最小宽 %.0f / 右栏 stretch %.2f）" % [where,
			left.size_flags_stretch_ratio, left.custom_minimum_size.x, right.size_flags_stretch_ratio])
	if left.size.x < min_w - 0.5:
		_fail("%s：名册栏 %.0f 窄于 %.0f" % [where, left.size.x, min_w])
	var got := left.size.x / maxf(right.size.x, 1.0)
	var at_min := left.size.x <= left.get_combined_minimum_size().x + 0.5 or right.size.x <= right.get_combined_minimum_size().x + 0.5
	if not at_min and absf(got - ratio) > 0.02:
		_fail("%s：名册栏 %.0f : %s %.0f = %.3f，应为 %.2f" % [where, left.size.x, right.name, right.size.x, got, ratio])
	var sep := float(row.get_theme_constant("separation"))
	var need := sep * float(cols.size() - 1)
	for c in cols:
		need += (c as Control).get_combined_minimum_size().x
	if row.get_combined_minimum_size().x > row.size.x + 0.5 or need > row.size.x + 0.5:
		_fail("%s：分栏最小宽 %.0f 超出可用 %.0f（挤）" % [where, need, row.size.x])
	var vr := Rect2(Vector2.ZERO, Vector2(sz))
	var boxes: Array = cols.duplicate()
	boxes.append(row)
	for b in host.find_children("*", "Button", true, false):
		if (b as Control).is_visible_in_tree():
			boxes.append(b)
	for c in boxes:
		var r := (c as Control).get_global_rect()
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > vr.end.x + 0.5 or r.end.y > vr.end.y + 0.5:
			_fail("%s：%s %s 出视口 %s（裁）" % [where, str((c as Node).name), str(r), str(vr)])
