extends SceneTree
## lane-w53-4 立、lane-w53-12 审计改向：顶匾章节注 Main._chapter_hint() 在「章目全 done、尚未开章」时写什么。
## w53-4（b68de41）曾让这一支回 chapters.json 的 next_requires/ending_requires.hint——那句是本章「要办哪几件」的
## 总述（「攒下五千钱本，走通近海五处港口……」），全办完了再上顶匾等于催玩家去办已办完的事（泉州节拍抢在开章
## 之前演、Main 刚由海图载入记事空时，顶匾正是这一支），终章还被它盖掉「终章・可了结」。
## 现钉：章目全达 → 非终章回空串、终章回「终章・可了结」，都不含 hint；章目未达 → 回第一条未达章目（本钱　N / M）。
## 把 b68de41 那三行 hint 回退复原 → 三格 ready 红。
var fails := 0
var cases := 0
var _gs
var _gm
var _main
var _cal


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var root: Window = get_root()
	_gs = root.get_node_or_null("GameState")
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	if _gs == null or _gm == null or _cal == null:
		push_error("autoload missing")
		quit(1)
		return
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	if not _main.has_method("_chapter_hint"):
		_expect(false, "Main._chapter_hint 不在")
		_report()
		return
	_c_ch1_ready_hint()
	_c_ch2_ready_hint()
	_c_ch4_ready_hint()
	_c_ch1_unready_label_unchanged()
	_report()


## 章一需求全达（钱 5000 + 5 港含流求）、尚未开章 → 空串（下一回入港即开章），不回 ch1.hint 的标语句
func _c_ch1_ready_hint() -> void:
	_gs.from_dict({})
	_cal.from_dict({"year": 1257, "month": 6, "day": 1})
	_gs.chapter = 1
	_gs.last_port = "quanzhou"
	_gs.money = 6000
	_gs.peak_money = 6000
	_gs.visited_ports = ["xinghua", "quanzhou", "fuzhou", "penghu", "ryukyu"]
	var got: String = str(_main.call("_chapter_hint"))
	_expect(got == "" and not got.contains("攒下五千钱本"),
		"章一 ready、未开章：_chapter_hint 回空串、不催已办完的 hint（实读：「%s」）" % got.substr(0, 60))


## 章二需求全达（本钱 2 万 + 9 港含博多）、尚未开章 → 空串，不回 ch2.hint
func _c_ch2_ready_hint() -> void:
	_gs.chapter = 2
	_gs.money = 25000
	_gs.peak_money = 25000
	_gs.visited_ports = ["xinghua", "quanzhou", "fuzhou", "penghu", "ryukyu", "mingzhou", "jeju", "hakata", "wenzhou"]
	var got: String = str(_main.call("_chapter_hint"))
	_expect(got == "" and not got.contains("本钱积至两万"),
		"章二 ready、未开章：_chapter_hint 回空串、不催已办完的 hint（实读：「%s」）" % got.substr(0, 60))


## 章四结局需求全达（本钱 8 万 + 13 港含占城）、尚未了结 → 「终章・可了结」，不被 ch4.ending_requires.hint 盖掉
func _c_ch4_ready_hint() -> void:
	_gs.chapter = 4
	_gs.money = 90000
	_gs.peak_money = 90000
	_gs.visited_ports = [
		"xinghua", "xinghua_harbor", "quanzhou", "fuzhou", "zhangzhou", "wenzhou",
		"penghu", "ryukyu", "mingzhou", "jeju", "hakata", "guangzhou", "champa",
	]
	var got: String = str(_main.call("_chapter_hint"))
	_expect(got == "终章・可了结",
		"章四 ready、未了结：_chapter_hint 回「终章・可了结」（实读：「%s」）" % got.substr(0, 60))


## 反向格：章一需求不达（钱不够）→ 回第一条未达章目「本钱　100 / 5000」，不吃 hint
func _c_ch1_unready_label_unchanged() -> void:
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 6, "day": 1})
	_gs.chapter = 1
	_gs.last_port = "quanzhou"
	_gs.money = 100  # 不够 5000
	_gs.peak_money = 100
	_gs.visited_ports = ["xinghua"]
	var got: String = str(_main.call("_chapter_hint"))
	_expect(got == "本钱　100 / 5000" and not got.contains("攒下五千钱本"),
		"章一未 ready：回第一条未达章目、不吃 hint（实读：「%s」）" % got.substr(0, 60))


func _report() -> void:
	print("CHAPTER_HINT_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
