extends SceneTree
## lane-w53-4 章节 hint 上屏专项。chapters.json 的 next_requires.hint / ending_requires.hint
## 存在 6 年、GameState.chapter_progress().hint 把它转发到 API 出口，但 Main._chapter_hint() 的
## 章目走完（items 全 done）分支一路 fallback 到「终章・可了结」/ ""，从不读 prog.hint ——玩家
## 永远看不到章节数据里那句「这一章要去哪」。本探针把 GameState 摆到「章目全 done + ready」态，
## 直接调 Main._chapter_hint()；修复前返不上 hint（红）、修复后含 hint 里那个最有辨识度的短句（绿）。
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


## 章一需求全达（钱 5000 + 5 港含流求）→ _chapter_hint 须走出 ch1.hint 的标语句
func _c_ch1_ready_hint() -> void:
	_gs.from_dict({})
	_cal.from_dict({"year": 1257, "month": 6, "day": 1})
	_gs.chapter = 1
	_gs.last_port = "quanzhou"
	_gs.money = 6000
	_gs.peak_money = 6000
	_gs.visited_ports = ["xinghua", "quanzhou", "fuzhou", "penghu", "ryukyu"]
	var got: String = str(_main.call("_chapter_hint"))
	# 章一 hint 的原话「攒下五千钱本，走通近海五处港口」是本探针要的红绿字
	_expect(got.contains("攒下五千钱本"),
		"章一 ready 后 _chapter_hint 上屏数据 hint（实读：%s）" % got.substr(0, 60))


## 章二需求全达（本钱 2 万 + 9 港含博多）→ 顶到 ch2.hint
func _c_ch2_ready_hint() -> void:
	_gs.chapter = 2
	_gs.money = 25000
	_gs.peak_money = 25000
	_gs.visited_ports = ["xinghua", "quanzhou", "fuzhou", "penghu", "ryukyu", "mingzhou", "jeju", "hakata", "wenzhou"]
	var got: String = str(_main.call("_chapter_hint"))
	_expect(got.contains("本钱积至两万"),
		"章二 ready 后 _chapter_hint 上屏数据 hint（实读：%s）" % got.substr(0, 60))


## 章四结局需求全达（本钱 8 万 + 13 港含占城）→ 顶到 ch4.ending_requires.hint
func _c_ch4_ready_hint() -> void:
	_gs.chapter = 4
	_gs.money = 90000
	_gs.peak_money = 90000
	_gs.visited_ports = [
		"xinghua", "xinghua_harbor", "quanzhou", "fuzhou", "zhangzhou", "wenzhou",
		"penghu", "ryukyu", "mingzhou", "jeju", "hakata", "guangzhou", "champa",
	]
	var got: String = str(_main.call("_chapter_hint"))
	_expect(got.contains("本钱积至八万"),
		"章四 ready 后 _chapter_hint 上屏数据 hint（实读：%s）" % got.substr(0, 60))


## 反向格：章一需求不达（钱不够）→ 照旧回到 items 行/空串，不吃 hint
func _c_ch1_unready_label_unchanged() -> void:
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 6, "day": 1})
	_gs.chapter = 1
	_gs.last_port = "quanzhou"
	_gs.money = 100  # 不够 5000
	_gs.peak_money = 100
	_gs.visited_ports = ["xinghua"]
	var got: String = str(_main.call("_chapter_hint"))
	_expect(not got.contains("攒下五千钱本"),
		"章一未 ready：不吃 hint（实读：%s）" % got.substr(0, 60))


func _report() -> void:
	print("CHAPTER_HINT_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
