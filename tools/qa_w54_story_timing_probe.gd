extends SceneTree
## lane-w54-story：剧情事件按设计的年月出场。
##   R 辞呈卡（士人线「临安・辞呈批语」）：终局系统化 §四定「identity = scholar 且 Calendar 到 1275-12」，Main._special_cards
##     注释也写「1275-12 起，未决则一直挂着」；卡上正文「辞呈是三天前批的」。修前只认 vice_councillor 旗——那枚旗是 1275-11 的
##     临安短札「累迁参知政事……朝议降」投放时立的，于是升参知政事的信刚到、同一个月岸上就挂出「辞呈已批」，中间一个月没了。
##     逐月真走日子（新闻照月初投放、旗照新闻立），断：1275-10 不挂、1275-11 信到旗立但不挂、1275-12 挂、1276-01 未决照挂、
##     选过一条路就不挂；反向基：海商线同月不挂。
## 用法：godot --headless --path . -s res://tools/qa_w54_story_timing_probe.gd（经门锁跑）
## 末行 W54_STORY_TIMING cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const RESIGN := "special_resign_1275"

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _gm: Node
var _cal: Node
var _tally: ScriptErrTally
var _reported := false


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _boot()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _boot() -> void:
	_gs = root.get_node_or_null("GameState")
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	if _gs == null or _gm == null or _cal == null:
		_expect(false, "autoload GameState / GameManager / Calendar 都在")
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _r_resign_month()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_STORY_TIMING cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


## 从 y-m 初一的前一日起，真走一日跨进这个月（月初结算：新闻投放、立旗），再进港排岸带
func _month(y: int, m: int, port: String) -> void:
	var py := y if m > 1 else y - 1
	var pm := m - 1 if m > 1 else 12
	_cal.from_dict({"year": py, "month": pm, "day": 30})
	_gm.advance_days(1)
	_gs.last_port = port
	_main.load_scene(port)
	await process_frame


func _start(identity: String) -> void:
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_gs.identity = identity
	_gs.money = 3000
	if identity == "scholar":
		_gs.player_name = "陈文龙"
		_gs.set_flag("renamed_wenlong")
	# 1275-10 之前的新闻当作早已投过（只看 1275-11 那封短札在本月初真投放、真立旗）
	_cal.from_dict({"year": 1275, "month": 10, "day": 1})
	for n in _gs.pending_news():
		_gs.mark_news_seen(str(n.get("id", "")))


# ── R 辞呈卡 ─────────────────────────────────────────────

func _r_resign_month() -> void:
	print("── R 辞呈卡：德祐元年腊月起挂，不与「累迁参知政事」同月")
	_start("scholar")
	await _month(1275, 10, "fuzhou")
	_expect(not _gs.has_flag("vice_councillor") and not (RESIGN in _main.shore_hand),
		"1275-10：还没升参知政事、不挂辞呈卡（旗 %s，名单 %s）" % [str(_gs.has_flag("vice_councillor")), _main.shore_hand])
	await _month(1275, 11, "fuzhou")
	_expect(_gs.has_flag("vice_councillor") and "n_1275_11_vice" in _gs.news_seen,
		"1275-11 月初：临安短札「累迁参知政事」投放、立 vice_councillor（旗 %s）" % str(_gs.has_flag("vice_councillor")))
	_expect(not (RESIGN in _main.shore_hand),
		"1275-11：升参知政事的信刚到，岸上不挂「辞呈已批」（名单 %s）" % [_main.shore_hand])
	await _month(1275, 12, "fuzhou")
	_expect(RESIGN in _main.shore_hand, "1275-12：岸上挂辞呈卡（名单 %s）" % [_main.shore_hand])
	await _month(1276, 1, "fuzhou")
	_expect(RESIGN in _main.shore_hand, "1276-01：辞呈未决照挂（名单 %s）" % [_main.shore_hand])
	_gs.set_flag("quiet_return")
	_main.load_scene("fuzhou")
	await process_frame
	_expect(not (RESIGN in _main.shore_hand), "选过一条路（quiet_return）就不挂（名单 %s）" % [_main.shore_hand])
	# 反向基：海商线同月不挂
	_start("merchant")
	await _month(1275, 12, "fuzhou")
	_expect(not _gs.has_flag("vice_councillor") and not (RESIGN in _main.shore_hand),
		"反向基：海商线 1275-12 不立旗、不挂辞呈卡（名单 %s）" % [_main.shore_hand])
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
