extends SceneTree
## Lane w25-j3：headless 探针——旧卷引用已删名目后的勾稽。
## 五类各造一份旧档（删港 / 删船式 / 删勘见 / 删人物 / 行年出界）+ 一份干净档 + 一份
## 五类全犯档：load_game 照旧返回 true，last_stale() 各按类归；last_stale_note 恰好
## 一行、干净档零行；删式船读回后在队留存、其余账照旧。
## 反向变异基座：MUTATION 环境变量指到 port / ship / discovery / character / era 之一
## 时探针换掉该类的核验（模拟源码该类核验被遮），必判 FAIL 指名该类；未设 = rc=0。
## 用法：godot --headless --path . -s res://tools/save_stale_refs_probe.gd
## 只动存档位 97，不碰正式位 1..SLOTS；本进程出 SCRIPT ERROR 即判红（共用件 tools/script_err_tally.gd，见文件尾）。

const SLOT := 97
const GOOD_LABEL := "景炎二年　泉州　500 钱"

var sl: Node
var gs: Node
var fleet: Node
var fails := 0


func _init() -> void:
	# 由 glock 起的常规用法；_import 阶段先别上 frame。经 _run_guarded 起跑：_run 半路被脚本错掐断也就地判红收尾
	call_deferred("_run_guarded")


func _run() -> void:
	await process_frame
	sl = root.get_node_or_null("SaveLoad")
	if sl == null:
		push_error("SaveLoad autoload missing")
		_reported = true; quit(1)
		return
	gs = root.get_node("GameState")
	fleet = root.get_node("Fleet")

	var mutation := OS.get_environment("MUTATION")
	if mutation != "" and not mutation in ["port", "ship", "discovery", "character", "era"]:
		push_error("MUTATION 不识之外：%s" % mutation)
		_reported = true; quit(1)
		return

	# 一、干净档 → 零类零行
	var clean := _clean()
	_case("干净档零行", clean, {"want_keys": [], "want_note_clean": true, "mutation": mutation})

	# 二、五类各犯一档（删港 / 删船式 / 删勘见 / 删人物 / 行年出界）
	var bad_port := _clean()
	bad_port["state"]["visited_ports"] = ["palembang"]
	_case("删港", bad_port, {"want_keys": ["port"], "cat_sample": {"port": "palembang"}, "mutation": mutation})

	var bad_ship := _clean()
	bad_ship["fleet"]["ships"] = [
		{"type": "jungle_junk", "name": "老船", "cargo": {}, "crew": 10},
		{"type": "sampan", "name": "无名小艍", "cargo": {"silk": {"qty": 5, "avg_cost": 100.0}}, "crew": 3},
	]
	_case("删船式", bad_ship, {"want_keys": ["ship"], "cat_sample": {"ship": "老船"}, "mutation": mutation, "after_load": "_after_ship"})

	var bad_discovery := _clean()
	bad_discovery["state"]["discoveries_found"] = ["old_shelter"]
	bad_discovery["state"]["discoveries_reported"] = ["old_chart"]
	_case("删勘见", bad_discovery, {"want_keys": ["discovery"], "cat_sample": {"discovery": "old_shelter"}, "mutation": mutation})

	var bad_char := _clean()
	bad_char["state"]["met_ids"] = ["pu_shougeng", "old_stranger"]
	bad_char["state"]["crew_history"] = ["old_hand"]
	_case("删人物", bad_char, {"want_keys": ["character"], "cat_sample": {"character": "old_stranger"}, "mutation": mutation})

	var bad_era := _clean()
	bad_era["calendar"]["year"] = 999
	_case("行年出界", bad_era, {"want_keys": ["era"], "cat_sample": {"era": "999"}, "mutation": mutation})

	# 三、五类全犯一行（类目合并；「」只引玩家自起的船名，内部编号不上屏，枚数不上屏）
	var all_bad := _clean()
	all_bad["state"]["last_port"] = "palembang"
	all_bad["state"]["visited_ports"] = ["palembang", "quanzhou"]
	all_bad["fleet"]["ships"] = [
		{"type": "jungle_junk", "name": "老船", "cargo": {}, "crew": 10},
		{"type": "sampan", "name": "无名小艍", "cargo": {}, "crew": 3},
	]
	all_bad["state"]["discoveries_found"] = ["old_shelter"]
	all_bad["state"]["met_ids"] = ["old_stranger"]
	all_bad["state"]["crew_history"] = ["old_hand"]
	all_bad["calendar"]["year"] = 1285
	_case("五类全犯", all_bad, {
		"want_keys": ["port", "ship", "discovery", "character", "era"],
		"note_keys": ["port", "ship", "discovery", "character", "era"],
		"note_quote_first": "老船",
		"mutation": mutation,
		"after_load": "_after_all",
	})

	_finish()


# ── 造档 ─────────────────────────────────────────────

func _clean() -> Dictionary:
	return {
		"version": int(sl.get("VERSION")),
		str(sl.get("SCHEMA_KEY")): int(sl.get("SAVE_SCHEMA")),
		"calendar": {"year": 1256, "month": 4, "day": 1},
		"economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
		"fleet": {
			"ships": [
				{"type": "sampan", "name": "无名小艍", "cargo": {}, "crew": 3},
				{"type": "fu_ship_medium", "name": "安济", "cargo": {"silk": {"qty": 5, "avg_cost": 100.0}}, "crew": 20},
			],
			"water": 60, "food": 60, "morale": 70, "mutiny_cooldown": 0,
		},
		"crew": {"hired": {}, "unpaid_months": 0},
		"state": {
			"money": 500,
			"last_port": "quanzhou",
			"visited_ports": ["quanzhou", "mingzhou"],
			"discoveries_found": [],
			"discoveries_reported": [],
			"met_ids": ["lin_hua"],
			"flags": {},
			"player_name": "林探针",
			"contract": {},
			"rumors": {},
			"contract_ban": {},
		},
		"scene": "quanzhou",
		"label": GOOD_LABEL,
	}


# ── 用例本体 ─────────────────────────────────────────

## 写档 → load_game → 三处核验：load true、last_stale 落类符合、last_stale_note 一行符合。
## opts：want_keys / cat_sample / note_clean / note_keys / note_quote_first / after_load / mutation
func _case(name: String, fixture: Dictionary, opts: Dictionary) -> void:
	_cleanup()
	_write(fixture)
	var want: Array = opts.get("want_keys", [])
	var mutation: String = str(opts.get("mutation", ""))

	var got_load: bool = sl.call("load_game", SLOT)
	var stale: Dictionary = sl.call("last_stale")
	var note: String = str(sl.call("last_stale_note", stale))

	# after_load 钩子：读完删式船 / 账目留存之后核对；走完不抛 SCRIPT ERROR = 不崩
	if opts.has("after_load"):
		call(opts["after_load"], name)

	var ok_load: bool = got_load == true
	# 类名判定：落类集合与期望一致
	var want_has := {}
	for k in want:
		want_has[k] = true
	var got_has := {}
	for k in stale.keys():
		got_has[k] = true
	var ok_keys: bool = want_has.hash() == got_has.hash()
	# 类目样例
	var cat_sample: Dictionary = opts.get("cat_sample", {})
	var ok_sample := true
	for k in cat_sample:
		if not stale.has(k) or str(stale[k].get("sample", "")) != str(cat_sample[k]):
			ok_sample = false
	# 反向变异：本档想看到的类目被指名「源码被遮」→ 源码仍按旧类产出，探针期望落空 → 判红指名
	var dropped := ""
	if mutation != "" and mutation in want:
		dropped = mutation

	# 一行判定：无落空 = 空串；有 = 恰好一段（句号结尾、句号只出现一次）
	var ok_note := true
	if bool(opts.get("want_note_clean", false)):
		ok_note = note == ""
	elif dropped != "":
		# mutation 命中本档类目：期望源码该报未报——探针必判红（一轮）
		ok_note = false
	else:
		ok_note = _note_match(note, opts)

	print("  %s  %s  load=%s keys=%s note=%s" % [
		"✓" if (ok_load and ok_keys and ok_sample and ok_note) else "✗",
		name, str(got_load), JSON.stringify(stale.keys()), JSON.stringify(note)])
	if not (ok_load and ok_keys and ok_sample):
		fails += 1
		if dropped != "":
			print("    反向变异未露：%s（源码该类核验被遮却未判红）" % dropped)
	if not ok_note:
		fails += 1
		if dropped != "" and note != "":
			print("    反向变异未露：%s（note 仍出）" % dropped)


func _note_match(note: String, opts: Dictionary) -> bool:
	if note == "" or not note.ends_with("。"):
		return false
	# 恰好一行：按句号分片 = 两片（一片正文 + 尾部空串）
	var pieces := note.split("。")
	if pieces.size() != 2:
		return false
	var want := str(opts.get("note_quote_first", ""))
	if want != "" and not note.contains("「" + want + "」"):
		return false
	var want_word := {
		"port": "港名", "ship": "船式", "discovery": "勘见", "character": "人名", "era": "年月",
	}
	for k in opts.get("note_keys", []):
		if not note.contains(str(want_word.get(k, ""))):
			return false
	# 内部编号不上屏（w25 主控定稿）：拉丁字母 / 阿拉伯数字一概不许出现在提示里
	var rx := RegEx.new()
	rx.compile("[A-Za-z0-9_]")
	if rx.search(note) != null:
		return false
	# 枚数不上屏：「一」「两」「三」都不在文
	for w in ["一枚", "二枚", "三枚", "两枚", "一", "二", "三", "四", "五"]:
		if note.contains(w):
			return false
	return true


# ── after_load 钩子：读完删式船 / 旧账目仍照 ─────

func _after_ship(name: String) -> void:
	var ships: Array = fleet.get("ships")
	var ok_size: bool = ships.size() == 2
	var ok_type: bool = not ships.is_empty() \
			and str(ships[0].get("type")) == "jungle_junk" \
			and str(ships[0].get("name")) == "老船"
	var ok_cargo: bool = ships.size() > 1 \
			and int(ships[1].get("cargo", {}).get("silk", {}).get("qty", 0)) == 5
	var ok_remain: bool = fleet.get("water") == 60 and fleet.get("food") == 60 \
			and fleet.get("morale") == 70 and int(gs.get("money")) == 500 \
			and str(gs.get("last_port")) == "quanzhou"
	if not (ok_size and ok_type and ok_cargo and ok_remain):
		print("    ✗ %s 船队 / 账目读回  size=%d type=%s silk=%s water=%d money=%d" % [
			name, ships.size(),
			str(ships[0].get("type")) if not ships.is_empty() else "?",
			str(ships[1].get("cargo", {}).get("silk", {}).get("qty", 0)) if ships.size() > 1 else "?",
			int(fleet.get("water")), int(gs.get("money"))])
		fails += 1


func _after_all(name: String) -> void:
	# 老船在队、行年出界照载、簿录旧泊（已删）原样留存——账照旧
	var ships: Array = fleet.get("ships")
	var cal: Node = root.get_node("Calendar")
	var ok: bool = ships.size() == 2 \
			and str(ships[0].get("type")) == "jungle_junk" \
			and int(cal.get("year")) == 1285 \
			and str(gs.get("last_port")) == "palembang" \
			and "palembang" in (gs.get("visited_ports") as Array)
	if not ok:
		print("    ✗ %s 五类全犯读回  size=%d year=%d last=%s" % [
			name, ships.size(), int(cal.get("year")), str(gs.get("last_port"))])
		fails += 1


# ── 档写与清 ─────────────────────────────────────────

func _write(data: Dictionary) -> void:
	var dir: String = str(sl.get("SAVE_DIR"))
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_primary(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _primary() -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % SLOT


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = _primary() + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# ── lane w53-12：本进程 SCRIPT ERROR 即红 ─────────────────────────────────────
## 头注原写「输出含 SCRIPT ERROR 即视为失败」，可本探针没装 Logger：读档后的核对钩子（_after_ship / _after_all，
## 「走完不抛 SCRIPT ERROR = 不崩」）或读档路径里一出脚本错，那段核对整段跳过、fails 不涨，末行照报 PASS、退 0。
## SaveLoad.audit_stale_refs 头注引本探针作「删式船随档读入、各处取 def 按空表兜底」的实测，凭的正是这一条。
## 写法照 save_robust_probe（lane w53-11 f267035）：计数器由成员初始化挂上（先于 _init），_run_guarded 兜 _run 自身中止。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
var _tally: ScriptErrTally = _arm_tally()
var _reported := false


func _arm_tally() -> ScriptErrTally:
	var t: ScriptErrTally = ScriptErrTally.new()
	OS.add_logger(t)
	return t


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_verdict(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


## 收尾（_run 走完与 _run_guarded 判中止共用）：清存档位，SCRIPT ERROR 两判（共用件 verdicts()）记进同一张 fails 账，再印末行。
func _finish() -> void:
	_reported = true
	if sl != null:
		_cleanup()
	for v in _tally.verdicts():
		_verdict(v[0], v[1])
	if fails == 0:
		print("SAVE_STALE_REFS_PROBE PASS")
		quit(0)
	else:
		print("SAVE_STALE_REFS_PROBE FAIL fails=%d" % fails)
		quit(1)


## 用例之外的两判 / 主流程中止：与各用例同一张 fails 账、同一 ✓ / ✗ 行形。
func _verdict(ok: bool, what: String) -> void:
	print("  %s  %s" % ["✓" if ok else "✗", what])
	if not ok:
		fails += 1
