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
	# 预留：codex_（人物志）等由后续角色添加
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
	print("TOUR_READY site=%s frame=%d" % [_site, _ready_frame])
	if _args.has("quit-after-ready"):
		call_deferred("_quit_later", maxi(0, int(_args["quit-after-ready"])))


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
	_main.call("load_scene", port_id)
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
	await _frames(SETTLE_FRAMES)
	_mark_ready()


func _site_port(arg: String) -> void:
	await _boot_main()
	await _enter_port(arg if arg != "" else "quanzhou")
	_mark_ready()


func _site_tavern(arg: String) -> void:
	var port_id := arg if arg != "" else "quanzhou"
	await _boot_main()
	await _enter_port(port_id)
	_main.call("load_scene", port_id + "_tavern")
	await _frames(SETTLE_FRAMES)
	_mark_ready()


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
	await _boot_main()
	CutscenePlayer.play(self, arg if arg != "" else "opening")
	_mark_ready()


func _site_chapter_card(arg: String) -> void:
	await _boot_main()
	await _enter_port("quanzhou")
	ChapterCard.play(self, clampi(int(arg) if arg.is_valid_int() else 1, 1, 4))
	_mark_ready()


func _site_banner(arg: String) -> void:
	var port_id := arg if arg != "" else "quanzhou"
	await _boot_main()
	await _enter_port(port_id)
	PortBanner.show_banner(self, port_id)
	_mark_ready()
