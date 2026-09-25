extends Node
## 巡检截帧驱动（port 线建立，后续角色往 SITES 里加站点）。
## 只在显式运行本场景时生效：游戏本体、门禁都不引用它。
##
## 用法（参数放在 -- 之后）：
##   <Godot> --path . --write-movie /tmp/x/f.png --fixed-fps 10 --quit-after 30 --resolution 1280x720 \
##           res://tools/art/ShotTour.tscn -- --tour=port_quanzhou
##   批量：tools/art/tour.sh [-n 帧数] [-r 运行副本] [-o 输出根] 站点…（每站出小样 sheet.jpg）
##   --list                  打印全部站点
##   --chapter=<n>           进站前把 GameState.chapter 抬到 n（看后几章才开的港口）
##   --shot=<n>              cutscene_ 站点从第 n 镜开始（CutscenePlayer.debug_start_shot）
##   --pick                  seachart 站点顺手选第一张航向牌
##   --quit-after-ready=<n>  准备好后再过 n 帧自己退出（不用 Movie Maker 时方便）
##   --anim                  title / page_cg_* 站点不补全标题演出（看书法写出、分段洇出的过程）
##   --rewatch               title_anim 站点：标题演出补全后按「重看开场」
##   --year=<公元>           chapter_card_ 站点进站前改 Calendar.year（看晚晋升时章节卡年号现算）
##   --raw                   chapter_card_ / banner_ 站点直接调过场引擎，不经 Main 接线
##   --hire=<候选 id,…>      tavern_ / ledger / codex 站点进站前先把这几位雇上船（看在船人物卡、船籍簿小头像、职事已识）
##   --known=all             codex 站点：全员当作本会话见过（看全套立绘）；不给则按真实进度判已识 / 未识
##   --filter=<键>           codex 站点的页签：all / major / crew / minor / historical
##   --scroll=<像素>         codex 站点名册往下滚多少；详页站点则是右栏传记往下滚多少
##   --from-title            codex 站点从标题页「人物志」钮进（默认从泉州港页底「人物志」钮进）
##   --hover=<人物 id>       codex 站点：名册里这一格摆成悬停态
##
## 过场层（cinematics 线）：只有 CINEMA_SITES 里的站点开着 Cinematics.enabled 走 Main 真实接线，
## 其余站点关掉过场层（册页、港页照旧直接出；活背景照挂）；巡检进港（_enter_port）一律不出第一章卡。
##
## 做法：实例化 res://scenes/Main.tscn，按「帧数」（不按秒——Movie Maker 下只有帧数是确定的）
## 调用 Main 现有函数把游戏推进到目标画面，不改 Main.gd。画面就位时打印 TOUR_READY，
## 之后保持不动，直到 --quit-after 到点。
##
## 加站点：在 SITES 里加一行「站点名或前缀 → 方法名」，再写一个 func _site_xxx(arg: String) -> void 协程，
## 末尾调用 _mark_ready()。键以 _ 结尾的是前缀，站点名去掉前缀的部分作为 arg 传入；
## 精确名优先，其次取最长的前缀。方法经 call() 派发，所以站点自己负责 await 与 _mark_ready()。

const MAIN_SCENE := "res://scenes/Main.tscn"
const CHART_SCENE := "res://scenes/SeaChart.tscn"
const CUTSCENES := "res://data/cutscenes.json"
const CHARACTERS := "res://data/characters.json"
## 过场接线的会话开关（cinematics 线）：基础站点关掉过场层，只看界面；过场站点走 Main 真实接线
const Cine := preload("res://scripts/cutscene/Cinematics.gd")
## 人物系统（characters 线）：「见过」表与人物志页签都是会话静态量，巡检摆场直接写
const CharArt := preload("res://scripts/ui/CharacterArt.gd")
const Codex := preload("res://scripts/ui/CharacterCodex.gd")
## 走 Main 真实接线的过场站点（其余站点 Cinematics.enabled = false，册页 / 港页照旧直接出）
const CINEMA_SITES := ["cutscene_opening", "chapter_card_", "banner_", "ending_cs_", "title_anim"]
## Main._ready 末尾 call_deferred("start_game")，再给两帧让标题页排好版
const BOOT_FRAMES := 4
## 每次换页后等几帧：容器排版、主题 hook、背景贴图都要一两帧才稳定
const SETTLE_FRAMES := 3

const SITES := {
	"title": "_site_title",
	"port_": "_site_port",
	"tavern_": "_site_tavern",
	"npc_": "_site_npc",
	"chapter_dialog": "_site_chapter_dialog",
	"chapter_dialog_": "_site_chapter_dialog",
	"ending_": "_site_ending",
	"seachart": "_site_seachart",
	# 过场引擎自带的三种演出（数据在 data/cutscenes.json），不经 Main.gd 接线也能单独看
	"cutscene_": "_site_cutscene",
	"chapter_card_": "_site_chapter_card",
	"banner_": "_site_banner",
	# cinematics 线加：走 Main 真实接线——开机开场（cutscene_opening，从全黑起播）、晋升章节卡 + 册页
	# （chapter_card_<n>，n=1 是序章后第一次进港；--year=<公元> 看晚晋升的年号现算）、海图回港横幅（banner_<港>）、
	# 结局过场 + 结算册页（ending_cs_<结局名 | 过场 id 尾巴 | 章末 id>）、标题演出（title_anim）
	"ending_cs_": "_site_ending_cs",
	"title_anim": "_site_title_anim",
	# reskin 线加：船籍簿浮层、航海日志册页、任意设施内页（page_market = quanzhou_market；也认整 id）
	"ledger": "_site_ledger",
	"save": "_site_save",
	"page_": "_site_page",
	# characters 线加：人物志名册（codex）与单人详页（codex_<人物 id>）
	"codex": "_site_codex",
	"codex_": "_site_codex",
	# fix:r2 加：兴化守城页 / 终局后港口页（先进泉州港页再进，专门复现旧节点残留）。
	# siege_back = 守城页进「市场」再离开；ended_port_reread = 点一次「重读结局」再合上册页
	"siege": "_site_siege",
	"siege_back": "_site_siege",
	"ended_port": "_site_ended_port",
	"ended_port_reread": "_site_ended_port",
}

## 终局六结局：走 Main 里真实的结算函数（文本、底图与游戏一致）；缺的回落通用弹框。
const FINALE_PORT := {
	"忠肃": "xinghua", "未归": "quanzhou", "海上宋鬼": "quanzhou",
	"泉州蒲氏的船": "quanzhou", "纲首": "quanzhou", "岸上的根": "xinghua",
}

var _site := ""
var _args: Dictionary = {}
var _main: Node
var _ready_frame := -1


func _ready() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	_site = str(_args.get("tour", "title"))
	if _args.has("list"):
		print("TOUR sites: ", SITES.keys())
		get_tree().quit(0)
		return
	# 过场层：只有过场站点走真实接线；开机开场只在 cutscene_opening 自动演
	var cinema := false
	for k in CINEMA_SITES:
		if _site == k or (str(k).ends_with("_") and _site.begins_with(k)):
			cinema = true
	Cine.enabled = cinema
	Cine.auto_opening = _site == "cutscene_opening"
	Cine.opening_seen = false
	call_deferred("_dispatch")


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	for a in argv:
		var s := str(a)
		if not s.begins_with("--"):
			continue
		var eq := s.find("=")
		if eq < 0:
			out[s.substr(2)] = "1"
		else:
			out[s.substr(2, eq - 2)] = s.substr(eq + 1)
	return out


func _dispatch() -> void:
	var method := ""
	var arg := ""
	if SITES.has(_site) and not str(_site).ends_with("_"):
		method = str(SITES[_site])
	else:
		var best := ""
		for k in SITES.keys():
			var key := str(k)
			if key.ends_with("_") and _site.begins_with(key) and key.length() > best.length():
				best = key
		if best != "":
			method = str(SITES[best])
			arg = _site.substr(best.length())
	if method == "" or not has_method(method):
		push_error("TOUR 未知站点：%s（--list 看全部）" % _site)
		print("TOUR_UNKNOWN site=", _site)
		get_tree().quit(2)
		return
	print("TOUR_START site=%s method=%s arg=%s" % [_site, method, arg])
	call(method, arg)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _mark_ready() -> void:
	_ready_frame = Engine.get_process_frames()
	# 量对比度用（reskin 线加）：--dump-labels 打印每个可见文字控件的矩形与字色；
	# --hide-text 把字（连描边投影）全隐掉，--fill-off 只隐字芯、描边投影照画。两帧相减即得字形与字下底色。
	if _args.has("dump-labels"):
		_dump_labels(get_tree().root, _find_modal(get_tree().root))
	if _args.has("hide-text") or _args.has("fill-off"):
		_mute_text(get_tree().root, _args.has("hide-text"))
	print("TOUR_READY site=%s frame=%d" % [_site, _ready_frame])
	if _args.has("quit-after-ready"):
		call_deferred("_quit_later", maxi(0, int(_args["quit-after-ready"])))


## 当前压暗整屏的浮层（升章册页 / 航海日志 / 船籍簿 / 人物志）。它后面的字被压暗，本来就不给读，量对比度时标 under。
func _find_modal(node: Node) -> Node:
	for n in ["CharacterCodex", "ChapterSheet", "SaveSheet", "LedgerLayer"]:
		var hit := node.find_child(n, true, false)
		if hit is CanvasItem and (hit as CanvasItem).is_visible_in_tree():
			return hit
	return null


## 字被滚动区裁掉一截（滚到视口外）：量对比度时底色取到的是视口外的东西，不作数，也标 under（characters 线加）。
func _clipped_by_scroll(c: Control) -> bool:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			var box := (p as Control).get_global_rect().grow(1.0)
			if not box.encloses(r):
				return true
		p = p.get_parent()
	return false


func _dump_labels(node: Node, modal: Node) -> void:
	if node is Control and (node as Control).is_visible_in_tree():
		var c := node as Control
		var text := ""
		var col := Color.WHITE
		var fsize := 0
		var outline := 0
		var kind := ""
		if c is Label:
			kind = "Label"
			text = (c as Label).text
			col = c.get_theme_color("font_color")
			fsize = c.get_theme_font_size("font_size")
			outline = c.get_theme_constant("outline_size")
		elif c is RichTextLabel:
			kind = "RichTextLabel"
			text = (c as RichTextLabel).get_parsed_text()
			col = c.get_theme_color("default_color")
			fsize = c.get_theme_font_size("normal_font_size")
		elif c is Button:
			kind = "Button"
			text = (c as Button).text
			col = c.get_theme_color("font_disabled_color" if (c as Button).disabled else "font_color")
			fsize = c.get_theme_font_size("font_size")
			outline = c.get_theme_constant("outline_size")
		if kind != "" and text.strip_edges() != "":
			var r := c.get_global_rect()
			print("TOUR_LABEL ", JSON.stringify({
				"kind": kind, "text": text.strip_edges().substr(0, 18), "path": str(c.get_path()).right(60),
				"rect": [r.position.x, r.position.y, r.size.x, r.size.y],
				"color": [col.r, col.g, col.b, col.a], "size": fsize, "outline": outline,
				"disabled": c is Button and (c as Button).disabled,
				"under": (modal != null and modal != c and not modal.is_ancestor_of(c)) or _clipped_by_scroll(c),
			}))
	for child in node.get_children():
		_dump_labels(child, modal)


func _mute_text(node: Node, all: bool) -> void:
	var clear := Color(0, 0, 0, 0)
	if node is Label:
		var l := node as Label
		l.add_theme_color_override("font_color", clear)
		if all:
			l.add_theme_color_override("font_outline_color", clear)
			l.add_theme_color_override("font_shadow_color", clear)
	elif node is RichTextLabel:
		(node as RichTextLabel).visible_characters = 0
	elif node is Button:
		var b := node as Button
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				"font_hover_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(k, clear)
		if all:
			b.add_theme_color_override("font_outline_color", clear)
	for child in node.get_children():
		_mute_text(child, all)


func _quit_later(n: int) -> void:
	await _frames(n)
	get_tree().quit(0)


func _boot_main() -> void:
	if _args.has("chapter"):
		GameState.chapter = maxi(GameState.chapter, int(_args["chapter"]))
	var packed: PackedScene = load(MAIN_SCENE)
	_main = packed.instantiate()
	add_child(_main)
	await _frames(BOOT_FRAMES)


## 进港：ports.json 的 unlock（ch2…）比当前章高时先抬章，免得 load_scene 被「还没到时候」挡回泉州。
func _enter_port(port_id: String) -> void:
	var pdef: Dictionary = GameManager.get_port_by_id(port_id)
	var unlock := str(pdef.get("unlock", "ch1"))
	if unlock.begins_with("ch"):
		GameState.chapter = maxi(GameState.chapter, int(unlock.substr(2)))
	GameState.last_port = port_id
	# 巡检进港是「摆场」，不是抵港：过场层先关（不出第一章卡），进完再还原
	var was := Cine.enabled
	Cine.enabled = false
	_main.call("load_scene", port_id)
	Cine.enabled = was
	await _frames(SETTLE_FRAMES)


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


# ── 站点 ──────────────────────────────────────────────

func _site_title(_arg: String) -> void:
	await _boot_main()
	_settle_title()
	await _frames(SETTLE_FRAMES)
	_mark_ready()


## 标题演出（书法写出 / 引首章 / 分段洇出）要五六秒：基础站点直接补全到终态；title_anim 站点看过程
func _settle_title() -> void:
	if _args.has("anim"):
		return
	var stage: Node = _main.find_child("TitleStage", true, false) if _main != null else null
	if stage != null and bool(stage.call("is_revealing")):
		stage.call("_complete")


func _site_title_anim(_arg: String) -> void:
	await _boot_main()
	if _args.has("rewatch"):
		# 标题演出补全后按「重看开场」：开场从标题页压黑起播（--shot=n 可从第 n 镜起）
		CutscenePlayer.debug_start_shot = maxi(0, int(_args.get("shot", "0")))
		_settle_title()
		await _frames(2)
		var btn := _main.find_child("RewatchButton", true, false) as Button
		if btn != null and btn.visible:
			btn.pressed.emit()
	_mark_ready()


func _site_port(arg: String) -> void:
	await _boot_main()
	await _enter_port(arg if arg != "" else "quanzhou")
	_mark_ready()


func _site_tavern(arg: String) -> void:
	var port_id := arg if arg != "" else "quanzhou"
	await _boot_main()
	_apply_hires()
	await _enter_port(port_id)
	_main.call("load_scene", port_id + "_tavern")
	await _frames(SETTLE_FRAMES)
	_mark_ready()


## --hire=<候选 id,…>：直接把人写进 Crew.hired（与 Crew.hire 同一记法，含 crew_history），不扣钱——巡检摆场用
func _apply_hires() -> void:
	if not _args.has("hire"):
		return
	for raw in str(_args["hire"]).split(",", false):
		var cand: Dictionary = Crew.candidate_def(str(raw).strip_edges())
		if cand.is_empty():
			push_warning("TOUR --hire 查无此人：%s" % raw)
			continue
		Crew.hired[str(cand.get("role", ""))] = cand
		GameState.record_crew(str(cand.get("id", "")))
	_main.call("update_status_panel")


func _site_npc(arg: String) -> void:
	var npc_id := arg if arg != "" else "merchant_lin"
	var npc_name := npc_id
	var chars: Dictionary = _load_json(CHARACTERS)
	for c in chars.get("characters", []):
		if typeof(c) == TYPE_DICTIONARY and str(c.get("id", "")) == npc_id:
			npc_name = str(c.get("name", npc_id))
			break
	await _boot_main()
	await _enter_port("quanzhou")
	# 市舶司小吏在衙门见，其余在酒馆见（与 Main 里 _add_npc_button 的出处一致）
	_main.call("load_scene", "quanzhou_yamen" if npc_id == "customs_official" else "quanzhou_tavern")
	await _frames(SETTLE_FRAMES)
	_main.call("_show_npc_mode", npc_id, npc_name)
	await _frames(SETTLE_FRAMES)
	_mark_ready()


## 伪造一次晋升：照 GameState.try_advance_chapter() 的返回拼 res，交给 Main._show_chapter_dialog。
## chapter_dialog = 第一章→第二章；chapter_dialog_<n> = 第 n 章→第 n+1 章（n=1..3）。
## 含 advance_years 跳年（会真的走完那几年的日子），与游戏里一模一样。
func _site_chapter_dialog(arg: String) -> void:
	var from_ch := clampi(int(arg) if arg.is_valid_int() else 1, 1, 3)
	await _boot_main()
	await _enter_port("quanzhou")
	var cur: Dictionary = GameState.chapter_def(from_ch)
	GameState.chapter = from_ch + 1
	var res := {
		"advanced": true,
		"resolved": false,
		"title": cur.get("advance_title", "新的一章"),
		"text": cur.get("advance_text", ""),
		"scene": str(cur.get("advance_scene", "")),
		"years": int(cur.get("advance_years", 0)),
	}
	_main.call("_show_chapter_dialog", res)
	await _frames(SETTLE_FRAMES)
	_mark_ready()


## ending_<结局名或 id>：终局六结局名（忠肃…）、它们的过场 id 尾巴（zhongsu…）、
## 或 chapters.json 终章 endings 的 id（sea_letter…，也认过场 id 尾巴 ledger / history）。
func _site_ending(arg: String) -> void:
	var key := _resolve_ending(arg)
	await _boot_main()
	var ch4_ids: Array = []
	for e in GameState.chapter_def(4).get("endings", []):
		if typeof(e) == TYPE_DICTIONARY:
			ch4_ids.append(str(e.get("id", "")))
	if key in ch4_ids:
		await _chapter_end(key)
	else:
		await _finale(key)
	await _frames(SETTLE_FRAMES)
	_mark_ready()


func _resolve_ending(arg: String) -> String:
	var ends: Dictionary = _load_json(CUTSCENES).get("endings", {})
	if ends.has(arg):
		return arg
	for k in ends.keys():
		var v := str(ends[k])
		if v == arg or v == "ending_" + arg:
			return str(k)
	return arg


## 章末了结：照 GameState.try_resolve_ending() 的返回拼 res（占城港上弹「了结」册页）。
func _chapter_end(eid: String) -> void:
	GameState.chapter = 4
	await _enter_port("champa")
	var picked := {}
	for e in GameState.chapter_def(4).get("endings", []):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == eid:
			picked = e
	GameState.ending_id = eid
	_main.call("_show_chapter_dialog", {
		"advanced": false,
		"resolved": true,
		"title": picked.get("title", "了结"),
		"text": picked.get("text", ""),
		"scene": str(picked.get("scene", "")),
	})


func _finale(ending_name: String) -> void:
	await _enter_port(str(FINALE_PORT.get(ending_name, "quanzhou")))
	match ending_name:
		"忠肃":
			_main.call("_siege_fall", "粮尽援绝")
		"未归":
			GameState.set_flag("renamed_wenlong")
			Calendar.year = 1276
			Calendar.month = 12
			_main.call("_check_absent_from_xinghua")
		"海上宋鬼":
			_main.call("_on_yashan")
			await _frames(1)
			var box: Node = _main.get("choices_container")
			for child in box.get_children():
				if child is Button:
					(child as Button).pressed.emit()
					break
		"泉州蒲氏的船":
			GameState.set_flag("sided_pu")
			_main.call("_on_gangshou_end")
		"纲首":
			_main.call("_on_gangshou_end")
		"岸上的根":
			Fleet.water = maxi(Fleet.water, 999)
			Fleet.food = maxi(Fleet.food, 999)
			_main.call("_on_hanjiang_escape")
		_:
			_main.call("_show_notice_dialog", ending_name, "（巡检）", "巡检站点：未登记的结局名「%s」。" % ending_name, "")


func _site_seachart(_arg: String) -> void:
	GameState.last_port = "quanzhou"
	var packed: PackedScene = load(CHART_SCENE)
	var chart := packed.instantiate()
	add_child(chart)
	await _frames(SETTLE_FRAMES + 1)
	if _args.has("pick"):
		var hand: PackedStringArray = chart.get("_hand")
		if hand.size() > 0:
			chart.call("_select_heading", hand[0])
			await _frames(SETTLE_FRAMES)
	_mark_ready()


func _site_cutscene(arg: String) -> void:
	CutscenePlayer.debug_start_shot = maxi(0, int(_args.get("shot", "0")))
	if arg == "" or arg == "opening":
		# 真实接线：新开一局，Main.start_game 从全黑起播开场，标题页在黑幕底下就位，演完揭开并重演标题演出
		await _boot_main()
		_mark_ready()
		return
	await _boot_main()
	CutscenePlayer.play(self, arg)
	_mark_ready()


## chapter_card_<n>：n=2..4 照 try_advance_chapter() 的返回拼 res 交给 Main._show_chapter_dialog——先演章节卡
## （年号 = 当前年 + 跳年，按 Calendar 现算），卡退场后弹原册页；n=1 = 序章走完第一次进港（visited_ports 为空）。
## --year=<公元>：进站前把 Calendar.year 设成它（看晚晋升时的年号，例如 --year=1268 的第三章）。
func _site_chapter_card(arg: String) -> void:
	var n := clampi(int(arg) if arg.is_valid_int() else 2, 1, 4)
	if _args.has("raw"):
		await _boot_main()
		await _enter_port("quanzhou")
		ChapterCard.play(self, n)
		_mark_ready()
		return
	if _args.has("year"):
		Calendar.year = int(_args["year"])
	await _boot_main()
	if n == 1:
		GameState.visited_ports.clear()
		GameState.chapter = 1
		GameState.last_port = "quanzhou"
		_main.call("load_scene", "quanzhou")
		_mark_ready()
		return
	await _enter_port("quanzhou")
	var cur: Dictionary = GameState.chapter_def(n - 1)
	GameState.chapter = n
	_main.call("_show_chapter_dialog", {
		"advanced": true,
		"resolved": false,
		"title": cur.get("advance_title", "新的一章"),
		"text": cur.get("advance_text", ""),
		"scene": str(cur.get("advance_scene", "")),
		"years": int(cur.get("advance_years", 0)),
	})
	_mark_ready()


## banner_<港>：真实的海图回港——立 return_to_port、记一笔「前一日从别港出港」，再起 Main：
## start_game 判定真正抵港 → load_scene → _on_enter_port 出横幅。--raw 直接调引擎。
func _site_banner(arg: String) -> void:
	var port_id := arg if arg != "" else "quanzhou"
	if _args.has("raw"):
		await _boot_main()
		await _enter_port(port_id)
		PortBanner.show_banner(self, port_id)
		_mark_ready()
		return
	var pdef: Dictionary = GameManager.get_port_by_id(port_id)
	var unlock := str(pdef.get("unlock", "ch1"))
	if unlock.begins_with("ch"):
		GameState.chapter = maxi(GameState.chapter, int(unlock.substr(2)))
	if GameState.visited_ports.is_empty():
		GameState.visited_ports.append("xinghua" if port_id != "xinghua" else "quanzhou")
	GameState.last_port = port_id
	GameState.set_flag("return_to_port")
	Cine.note_departure("penghu" if port_id != "penghu" else "quanzhou", Calendar.absolute_day() - 3)
	await _boot_main()
	_mark_ready()
	# --then=<场景 id>：横幅出来后过 --then-after 帧（默认 8）进这一页，逐帧打印场上横幅数（看离开港页时横幅是否快速退去）
	if _args.has("then"):
		await _frames(int(_args.get("then-after", "8")))
		_main.call("load_scene", str(_args["then"]))
		for i in 12:
			print("TOUR_BANNERS frame+%d n=%d" % [i, get_tree().get_nodes_in_group(PortBanner.GROUP).size()])
			await get_tree().process_frame


## ending_cs_<x>：与 ending_<x> 同一条真实结算路径，但开着过场层——先演结局过场，过场全黑时换结算底图、弹册页
func _site_ending_cs(arg: String) -> void:
	CutscenePlayer.debug_start_shot = maxi(0, int(_args.get("shot", "0")))
	await _site_ending(arg)


func _site_ledger(_arg: String) -> void:
	await _boot_main()
	_apply_hires()
	await _enter_port("quanzhou")
	_main.call("_toggle_ledger")
	await _frames(SETTLE_FRAMES)
	_mark_ready()


func _site_save(_arg: String) -> void:
	await _boot_main()
	await _enter_port("quanzhou")
	_main.call("_show_save_dialog")
	await _frames(SETTLE_FRAMES)
	_mark_ready()


## siege / siege_back：先进泉州港页（岸门带、看风都排好），再照 godot_story_check 的摆法立守城（改名、1276-11、siege_begin）
## 进兴化——原先这一步会残留泉州的岸门；siege_back 再点「市场」进屯粮页、按离开回来，看城防账与门排不翻倍。
func _site_siege(_arg: String) -> void:
	await _boot_main()
	await _enter_port("quanzhou")
	GameState.from_dict({})
	GameState.set_flag("renamed_wenlong")
	GameState.identity = "scholar"
	Calendar.from_dict({"year": 1276, "month": 11, "day": 3})
	GameState.siege_begin()
	GameState.chapter = 4
	GameState.last_port = "xinghua"
	_main.call("load_scene", "xinghua")
	await _frames(SETTLE_FRAMES)
	if _site == "siege_back":
		_main.call("_on_facility_pressed", {"id": "siege_grain", "title": "市场"})
		await _frames(SETTLE_FRAMES)
		_main.call("load_scene", "xinghua")
		await _frames(SETTLE_FRAMES)
	_mark_ready()


## ended_port / ended_port_reread：先进泉州港页，再落定一个结局（泉州蒲氏的船）回泉州——终局后港口页；
## _reread 再按「重读结局」、合上册页，看港名匾不累加、札记不翻倍。
func _site_ended_port(_arg: String) -> void:
	await _boot_main()
	await _enter_port("quanzhou")
	GameState.set_flag("sided_pu")
	GameState.finish("泉州蒲氏的船", "市舶司的册子换了封面。（巡检摆场）")
	_main.call("load_scene", "quanzhou")
	await _frames(SETTLE_FRAMES)
	if _site == "ended_port_reread":
		_main.call("_on_reread_ending")
		await _frames(SETTLE_FRAMES)
		_main.call("_confirm_chapter_sheet")
		await _frames(SETTLE_FRAMES)
	_mark_ready()


## page_<后缀或整 id>：page_market → quanzhou_market；page_xinghua_shipyard 原样；
## page_<scenes.json 里的场景 id>（如 page_prologue_tabletop）直接进该场景。
func _site_page(arg: String) -> void:
	var sid := arg if arg != "" else "market"
	var port_id := "quanzhou"
	if not GameManager.get_scene_by_id(sid).is_empty():
		pass
	elif sid.find("_") > 0 and not GameManager.get_port_by_id(sid.get_slice("_", 0)).is_empty():
		port_id = sid.get_slice("_", 0)
	else:
		sid = port_id + "_" + sid
	await _boot_main()
	await _enter_port(port_id)
	_main.call("load_scene", sid)
	await _frames(1)
	_settle_title()  # 卷首四方沙盘（cg_world_*）是标题模式：直接看终态；过程用 --anim
	await _frames(SETTLE_FRAMES)
	_mark_ready()


## codex = 人物志名册；codex_<人物 id> = 此人详页（先开名册再点进去，与游戏里一样）。
## 入口按真的钮：默认泉州港页底「人物志」，--from-title 走标题页「人物志」。缩略图分帧补完再就位（至多等 90 帧）。
func _site_codex(arg: String) -> void:
	await _boot_main()
	_apply_hires()
	if _args.get("known", "") == "all":
		for ch in GameManager.all_characters():
			CharArt.note_met(str(ch.get("id", "")))
	Codex.last_filter = str(_args.get("filter", "all"))
	var entry: Button = null
	if _args.has("from-title"):
		_settle_title()
		await _frames(1)
		entry = _main.find_child("CodexTitleButton", true, false) as Button
	else:
		await _enter_port("quanzhou")
		var acts: Node = _main.find_child("ShoreActions", true, false)
		if acts != null:
			for b in acts.get_children():
				if b is Button and (b as Button).text == "人物志":
					entry = b
	if entry == null or not entry.is_visible_in_tree():
		push_error("TOUR codex：找不到「人物志」入口钮")
		get_tree().quit(3)
		return
	entry.pressed.emit()
	await _frames(1)
	var codex: Node = _main.find_child("CharacterCodex", true, false)
	if codex == null:
		push_error("TOUR codex：点了「人物志」没有开出浮页")
		get_tree().quit(3)
		return
	for _i in 90:
		if int(codex.call("pending_thumbs")) == 0:
			break
		await get_tree().process_frame
	if arg != "":
		codex.call("show_detail", arg, false)
		for _i in 60:
			if int(codex.call("pending_thumbs")) == 0:
				break
			await get_tree().process_frame
		await _frames(SETTLE_FRAMES)
	if _args.has("scroll"):
		var sc := codex.find_child("DetailScroll" if arg != "" else "GridScroll", true, false) as ScrollContainer
		if sc != null:
			sc.scroll_vertical = int(_args["scroll"])
	if _args.has("hover"):
		# 看名册格的悬停态：对那一格发 mouse_entered（Movie Maker 下没有真鼠标）
		var cell := codex.find_child("Cell_" + str(_args["hover"]), true, false) as Control
		if cell != null:
			cell.mouse_entered.emit()
	# 淡入 0.18 秒 + 缩略图逐张淡入 0.22 秒：多等几帧看终态
	await _frames(SETTLE_FRAMES + 3)
	_mark_ready()
