extends SceneTree
## 写实海战冒烟探针（lane combat10）：大改后的五块写实机制 + 剧情挂钩，一支 headless 探针验完。
##   零、判据自检：内存里的样本模块（本文件末尾的 _Fake* 内部类）逐节喂同一套判据——好样本须全绿，每个变异须在指定那条判红
##   一、风流机动（combat02 SeaState / ManeuverModel）        二、弹道·装填·缺弹（combat03 Ballistics / ReloadAmmo）
##   三、损伤·浸水·失火（combat04 DamageModel / FloodFire）    四、接舷白刃（combat05 MeleeResolve）
##   五、士气·溃逃（combat06 CombatMorale）
##   六、剧情挂钩：锚点字样（CombatDirector.STORY_ANCHORS）+ 真跑 SeaChart 遇盗 → WorldMap 开战 → 接舷夺船 → 海图回写
##   七、接线普查（只报不判）：各模块被哪些现役脚本引用
## 模块不在：记「⚠ 跳过」，不算通过，判词行写明跳过了哪几块。已知缺陷（KNOWN_DEFECTS，修好即删）记 ⚠ 并点名属主。
## `-- --strict`：跳过与已知缺陷一律判红（整波落地、缺陷修完后用）。
## 用法：godot --headless --path . -s res://tools/combat_realism_probe.gd
##      godot --headless --quiet --path . -s res://tools/combat_realism_probe.gd -- --json      # 一行 JSON（tools/gate_report.gd）
##      godot --headless --path . -s res://tools/combat_realism_probe.gd -- --strict
##      godot --headless --path . -s res://tools/combat_realism_probe.gd -- --only=melee,story   # 只跑几节（零节照跑）
## 判词：COMBAT_REALISM_PROBE PASS … / COMBAT_REALISM_PROBE FAIL k …；读法与各节契约见 docs/combat_realism_verify.md。
## 只改内存里的 Fleet / GameState / GameManager.pending_battle，跑完还原；不写存档、不截图。

const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（lane g2）
const Director := preload("res://scripts/combat/CombatDirector.gd")
const TAG := "COMBAT_REALISM_PROBE"
const GATE := "combat_realism_probe"

## 节：id（--only 用）/ 序号 / 题 / 管的模块（CombatDirector.MODULES 的 id）
const SECTIONS := [
	{"id": "maneuver", "no": "一", "title": "风流机动", "mods": ["sea_state", "maneuver"]},
	{"id": "ballistics", "no": "二", "title": "弹道·装填·缺弹", "mods": ["ballistics", "reload_ammo"]},
	{"id": "damage", "no": "三", "title": "损伤·浸水·失火", "mods": ["damage", "flood_fire"]},
	{"id": "melee", "no": "四", "title": "接舷白刃", "mods": ["melee"]},
	{"id": "morale", "no": "五", "title": "士气·溃逃", "mods": ["morale"]},
	{"id": "story", "no": "六", "title": "剧情挂钩（遇盗 → 开战 → 夺船 → 回写）", "mods": []},
	{"id": "census", "no": "七", "title": "接线普查（只报不判）", "mods": []},
]

## 已知缺陷：判据 key → 属主 / 缘由 / 修法。在这张表里的判据红了只记 ⚠（照样打印），不算本探针红；
## 修好了（判据转绿）反倒判红，逼着把这条删掉——登记不许烂在表里（同 check_data_family 的 known_orphans 基线）。
## --strict 下一律判红。属主不是本 lane 的文件，本 lane 只登记、不修。
const KNOWN_DEFECTS := {
	# combat11：story.capture.boarded / damage / writeback 已在 WorldMap 清掉，表空。
}

var _strict := false
## --mutants：零节逐支打印每个样本（缺省每组一行）
var _mutants := false
var _only: PackedStringArray = []
var _fails: Array = []
var _known_hit: Array = []
## 本节状态：ran 判据条数、bad 红条数、skipped 跳过的模块
var _sec := {}
var _verified: Array = []
var _skipped: Array = []
## 零节自检时把判据结果收进这里、不打印（null = 正常上报）
var _sink = null
var _errlog: _ErrLog = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_strict = "--strict" in args
	_mutants = "--mutants" in args
	for a in args:
		if a.begins_with("--only="):
			_only = a.substr(7).split(",", false)
	_errlog = _ErrLog.new()
	OS.add_logger(_errlog)
	print("%s 写实海战冒烟（lane combat10）　%s" % [TAG, "严格：跳过 / 已知缺陷一律判红" if _strict
		else "默认：缺模块记 ⚠ 跳过、不算通过；已知缺陷记 ⚠ 并点名属主"])
	await process_frame
	_selftest()
	for s in SECTIONS:
		if not _only.is_empty() and not (s["id"] in _only):
			continue
		_begin(s)
		match s["id"]:
			"maneuver":
				_sec_maneuver()
			"ballistics":
				_sec_ballistics()
			"damage":
				_sec_damage()
			"melee":
				_sec_melee()
			"morale":
				_sec_morale()
			"story":
				await _sec_story()
			"census":
				_sec_census()
		_end(s)
	_finish()


# ══ 上报 ══════════════════════════════════════════════════

## 一条判据：key 稳定（零节变异按它认、KNOWN_DEFECTS 按它登记），name 是人读的话
func _t(ok: bool, key: String, name: String, detail := "") -> bool:
	if _sink != null:
		_sink.append({"ok": ok, "key": key, "name": name, "detail": detail})
		return ok
	if KNOWN_DEFECTS.has(key):
		return _known(ok, key, name, detail)
	_emit(ok, name, detail)
	return ok


## verified=false：这条不算「本节验过」（--strict 下的跳过即红）
func _emit(ok: bool, name: String, detail := "", verified := true) -> void:
	var line := ("  ✓ " if ok else "  ✗ ") + name + ("" if detail == "" else "（%s）" % detail)
	print(line)
	GateReport.check(ok, name, str(_sec.get("label", "")) if ok else (detail if detail != "" else str(_sec.get("label", ""))))
	if verified:
		_sec["ran"] = int(_sec.get("ran", 0)) + 1
	if not ok:
		_sec["bad"] = int(_sec.get("bad", 0)) + 1
		_fails.append(name)


## 已知缺陷的判据：红了记 ⚠（--strict 判红）；绿了判红「修好了，删登记」
func _known(ok: bool, key: String, name: String, detail: String) -> bool:
	var d: Dictionary = KNOWN_DEFECTS[key]
	if ok:
		_emit(false, "%s——已修好，请把 KNOWN_DEFECTS[\"%s\"] 删掉（登记不许烂在表里）" % [name, key])
		return true
	if _strict:
		_emit(false, "%s（已知缺陷，--strict 判红；属主 %s）" % [name, d["owner"]], detail)
		return false
	var msg := "已知缺陷 %s：%s——%s；属主 %s；修法：%s" % [key, name, d["why"], d["owner"], d["fix"]]
	print("  ⚠ " + msg + ("" if detail == "" else "（%s）" % detail))
	GateReport.warn(msg, detail)
	_known_hit.append(key)
	return false


func _warn(msg: String, detail := "") -> void:
	if _sink != null:
		return
	print("  ⚠ " + msg)
	GateReport.warn(msg, detail)


func _info(msg: String) -> void:
	if _sink == null:
		print("  · " + msg)


## 模块不在：记跳过（--strict 判红）；返回 true = 跳过了
func _skip_absent(id: String) -> bool:
	if Director.present(id):
		return false
	var e := Director.entry(id)
	var why := "%s 不在（%s 未落地）——%s未验，不算通过" % [Director.path_of(id), e.get("lane", "?"), e.get("what", "")]
	if _strict:
		_emit(false, "跳过即红（--strict）：" + why, "", false)
	else:
		_warn("跳过 " + why)
	_sec["skipped"].append(id)
	return true


## 在就必须编得过；编不过判红并返回 null
func _need(id: String) -> Script:
	var s := Director.load_module(id)
	_t(s != null, "load.%s" % id, "%s 能加载、can_instantiate" % Director.path_of(id).get_file())
	return s


func _begin(s: Dictionary) -> void:
	_sec = {"label": "%s、%s" % [s["no"], s["title"]], "ran": 0, "bad": 0, "skipped": [], "err0": _errlog.count}
	var owners := []
	for m in s["mods"]:
		owners.append("%s %s" % [Director.entry(m).get("lane", "?"), Director.path_of(m).get_file()])
	print("== %s%s" % [_sec["label"], "（%s）" % "、".join(owners) if not owners.is_empty() else ""])


## 收节：本节跑出过 SCRIPT ERROR / ERROR 判红；按跑了几条、跳过几块记进 verified / skipped
func _end(s: Dictionary) -> void:
	var errs: int = _errlog.count - int(_sec["err0"])
	if errs > 0 and s.get("id", "") != "census":  # 普查只报不判：模块编不过已在所属那节判红
		_emit(false, "本节跑出引擎 / 脚本错误 %d 条（首条：%s）" % [errs, _errlog.first_since(int(_sec["err0"]))])
	var label: String = "%s %s" % [s["no"], s["title"]]
	for m in _sec["skipped"]:
		_skipped.append("%s·%s" % [s["no"], Director.path_of(m).get_file().get_basename()])
	if int(_sec["ran"]) > 0:
		_verified.append(label)


func _finish() -> void:
	OS.remove_logger(_errlog)
	var tail := "验过 %d 节（%s）" % [_verified.size(), "、".join(_verified)]
	if not _skipped.is_empty():
		tail += "；跳过 %d 块（%s：模块未落地，未验、不算通过）" % [_skipped.size(), "、".join(_skipped)]
	if not _known_hit.is_empty():
		tail += "；已知缺陷 %d 条（%s，属主待修）" % [_known_hit.size(), "、".join(_known_hit)]
	var rc := 0 if _fails.is_empty() else 1
	var summary := ("%s PASS　" % TAG + tail) if rc == 0 else ("%s FAIL %d　" % [TAG, _fails.size()] + tail)
	print(summary)
	if rc != 0:
		for f in _fails:
			print("   ✗ " + f)
	GateReport.finish(GATE, rc, summary, {"verified": _verified, "skipped": _skipped, "known_defects": _known_hit, "strict": _strict})
	quit(rc)


# ══ 零、判据自检 ══════════════════════════════════════════

## 每节的判据先拿本文件末尾的样本模块跑：好样本须全绿；每个变异须在它点名的那条（且只那条）判红。
## 判据写空了（永远绿）、写反了（好样本红），这里先红——不等真模块落地才知道。
func _selftest() -> void:
	_sec = {"label": "零、判据自检", "ran": 0, "bad": 0, "skipped": [], "err0": _errlog.count}
	print("== 零、判据自检（样本模块：好样本须全绿，每个变异须只在点名那几条判红；-- --mutants 逐支打印）")
	# 锚点样本照锚点表合成（每支函数只含它的字样），与真文件无关：真源码的锚点断了只在六节红，零节照绿
	var anchor_good := _anchor_sample()
	var anchor_muts: Array = []
	for a in Director.STORY_ANCHORS:
		anchor_muts.append(["%s 丢了「%s」" % [a["id"], str(a["needles"][0]).left(24)], _anchor_mutant(anchor_good, a), ["anchor." + a["id"]]])
	_group("一 海况", func(m): _judge_sea(m), _FakeSea, [
		["风向记反", _MutSeaBackwards, ["sea.force_wind", "sea.name"]],
		["风越刮越大", _MutSeaRunaway, ["sea.step_bounds"]],
		["不认种子", _MutSeaUnseeded, ["sea.seed"]]])
	_group("一 机动", func(m): _judge_maneuver(m), _FakeManeuver, [
		["顶风照走", _MutManHeadwind, ["man.headwind", "man.no_go"]],
		["风大风小一个速", _MutManWindBlind, ["man.wind_gain"]],
		["侧风不横漂", _MutManNoLeeway, ["man.leeway"]],
		["大船小船一样转", _MutManSameRadius, ["man.turn_by_type"]],
		["四面都是射界", _MutManArcAll, ["man.fire_arc"]],
		["多远都钩得上", _MutManBoardAlways, ["man.boarding"]],
		["上下风记反", _MutManGaugeFlip, ["man.weather"]]])
	_group("二 弹道", func(m): _judge_ballistics(m), _FakeBallistics, [
		["矢石瞬到", _MutBalInstant, ["bal.flight"]],
		["远近一样准", _MutBalNoSpread, ["bal.spread"]],
		["船头船尾照打", _MutBalAllRound, ["bal.bearing"]]])
	_group("二 装填", func(m): _judge_reload(m, _ship_def()), _FakeReload, [
		["放炮不耗弹", _MutReloadInfinite, ["ammo.consume"]],
		["弹尽照放", _MutReloadEmptyFires, ["ammo.empty"]],
		["一放就装好", _MutReloadInstant, ["ammo.reload", "ammo.reload_time", "ammo.low_slow"]],
		["告急不慢", _MutReloadNoPenalty, ["ammo.low_slow"]]])
	_group("三 损伤", func(m): _judge_damage(m, _ship_def()), _FakeDamage, [
		["水线下中弹不漏", _MutDmgNoLeak, ["dmg.flood", "dmg.damage_control", "dmg.slows", "dmg.founder"]],
		["损管令不管用", _MutDmgNoControl, ["dmg.damage_control"]],
		["舵打不坏", _MutDmgRudderless, ["dmg.rudder"]],
		["永不沉", _MutDmgUnsinkable, ["dmg.founder"]]])
	_group("三 浸水失火", func(m): _judge_floodfire(m), _FakeFloodFire, [
		["火不蔓延", _MutFFNoSpread, ["ff.spread"]],
		["火扑不灭", _MutFFUndousable, ["ff.douse"]],
		["漏自己合上", _MutFFSelfSealing, ["ff.leak"]],
		["戽水不减", _MutFFBailless, ["ff.bail"]],
		["没有隔舱", _MutFFNoBulkheads, ["ff.bulkhead"]]])
	_group("四 接舷白刃", func(m): _judge_melee(m), _FakeMelee, [
		["钩索不看相对速度", _MutMeleeSpeedBlind, ["melee.grapple.rel_speed"]],
		["钩索够得着天边", _MutMeleeLongReach, ["melee.grapple.reach"]],
		["一合定胜负", _MutMeleeOneRound, ["melee.rounds"]],
		["胜负掷硬币", _MutMeleeCoin, ["melee.capture", "melee.repel"]],
		["不认种子", _MutMeleeUnseeded, ["melee.seed"]]])
	_group("五 士气", func(m): _judge_morale(m), _FakeMorale, [
		["从不溃逃", _MutMoraleNeverRout, ["mor.rout_threshold"]],
		["过线前就溃", _MutMoraleEarlyRout, ["mor.rout_threshold"]],
		["死伤不动心", _MutMoraleCasualtyBlind, ["mor.casualties"]],
		["火烧不慌", _MutMoraleFireproof, ["mor.fire"]],
		["从不降幡", _MutMoraleNeverStrike, ["mor.strike"]],
		["无压也降", _MutMoraleStrikeFree, ["mor.strike_pressure"]]])
	_group("六 剧情锚点", func(m): _judge_anchors(m), anchor_good, anchor_muts)
	_group("六 战果常量接线（w23-a10）", func(m): _judge_outcome_contract(m), [
			["win", "lose", "flee"],
			{"boarded": "win：假注一", "sunk": "lose：假注二", "flee_ok": "flee：假注三"}], [
		["outcome 漏一员", [["win", "lose"], {"boarded": "win：假注一", "sunk": "lose：假注二", "flee_ok": "flee：假注三"}],
			["story.outcome.constants"]],
		["story 键漏一枚", [["win", "lose", "flee"], {"boarded": "win：假注一", "sunk": "lose：假注二"}],
			["story.outcome.constants"]],
		["story 键多出用不上的", [["win", "lose", "flee"], {"boarded": "win：a", "sunk": "lose：b", "flee_ok": "flee：c", "ghost": "win：鬼"}],
			["story.outcome.constants"]],
		["两表皆空（DETACHED，读不到 Director 表了）", [[], {}], ["story.outcome.detached"]]])
	_group("六 已知缺陷登记", func(m): _judge_known_table(m), {"x.y": {"owner": "o", "why": "w", "fix": "f"}}, [
		["缺修法", {"x.y": {"owner": "o", "why": "w"}}, ["known.shape"]]])
	_end({"no": "零", "title": "判据自检"})


## 一组：好样本 good 须全绿；mutants 每支 [名, 样本, 须红的 key] 须恰好红在那几条。整组记一条判据，红了列出哪几支不对
func _group(label: String, judge: Callable, good, mutants: Array) -> void:
	var bad: Array = []
	var n := _case(label + "：好样本", judge, good, [], bad)
	for mu in mutants:
		_case("%s 变异「%s」" % [label, mu[0]], judge, mu[1], mu[2], bad)
	_emit(bad.is_empty() and n > 0, "%s：好样本 %d 条判据全绿，变异 %d 支各只在点名处判红" % [label, n, mutants.size()], "; ".join(bad))


## 跑一例，返回判据条数：expect 空 = 须全绿；非空 = 这些 key 须红、别的 key 须绿。不合的写进 bad；--mutants 时逐例打印
func _case(label: String, judge: Callable, mod, expect: Array, bad: Array) -> int:
	_sink = []
	judge.call(mod)
	var got: Array = _sink
	_sink = null
	var red: Array = []
	for r in got:
		if not r["ok"]:
			red.append(r["key"])
	var missed := expect.filter(func(k): return not (k in red))
	var extra := red.filter(func(k): return not (k in expect))
	var why := ""
	if expect.is_empty():
		why = "" if not got.is_empty() and red.is_empty() else ("没有判据" if got.is_empty() else "红了 " + ", ".join(red))
	else:
		why = ("没红 " + ", ".join(missed) if not missed.is_empty() else "") + (" 多红 " + ", ".join(extra) if not extra.is_empty() else "")
	if why != "":
		bad.append("%s：%s" % [label, why.strip_edges()])
	if _mutants:
		print("    %s %s%s" % ["·" if why == "" else "✗", label, "（%d 条全绿）" % got.size() if expect.is_empty() and why == ""
			else ("→ 红在 " + ", ".join(expect) if why == "" else "——" + why.strip_edges())])
	return got.size()


# ══ 六、剧情挂钩 ══════════════════════════════════════════

func _sec_story() -> void:
	_judge_anchors({})
	_judge_outcome_contract([Director.OUTCOMES.duplicate(), (Director.STORY_KEYS as Dictionary).duplicate()])
	_judge_known_table(KNOWN_DEFECTS)
	await _story_live_capture()
	await _story_live_outcomes()


## 锚点字样：sources 空 = 读盘；零节传合成的样本（给了哪个文件就只用它，不读盘）
func _judge_anchors(sources: Dictionary) -> void:
	var probs := Director.anchor_problems(sources)
	for a in Director.STORY_ANCHORS:
		var mine := probs.filter(func(p): return str(p).begins_with(str(a["id"]) + "："))
		_t(mine.is_empty(), "anchor." + a["id"], "锚点 %s：%s.%s（%s）" % [a["id"], str(a["file"]).get_file(), a["func"], a["what"]],
			"; ".join(mine))


## 零节的锚点好样本：每个文件合成一份最小源码，锚点的每支函数只含它登记的字样
func _anchor_sample() -> Dictionary:
	var out := {}
	for a in Director.STORY_ANCHORS:
		var body := "func %s() -> void:\n" % a["func"]
		for n in a["needles"]:
			body += "\t%s\n" % n
		out[a["file"]] = str(out.get(a["file"], "")) + body + "\n\n"
	return out


## 零节的锚点变异：在好样本里把锚点 a 的第一条字样从它的函数体里抹掉
func _anchor_mutant(good: Dictionary, a: Dictionary) -> Dictionary:
	var out := good.duplicate()
	var src := str(out[a["file"]])
	var body := Director.func_body(src, str(a["func"]))
	out[a["file"]] = src.replace(body, body.replace(str(a["needles"][0]), "__nk1_mutant__"))
	return out


## 战果常量接线（w23-a10，零节 + 真树共用一本账）：Director.OUTCOMES / STORY_KEYS 不再只被文档传抄——
## 判据 1 钉接线在不在（现树传真表；判红 = 常量被删回死码或 Director 读不到，先红这条醒目行），
## 判据 2 钉契约内容（发过的 outcome 都在册、发 / 认的剧情键恰好凑齐、每枚键各归一边结局、写明了意思）。
## pair = [outcomes, story_keys]（现树真表 / 零节合成样本），两侧同步进 bad、同一条判据判红——悬案到此为止。
func _judge_outcome_contract(pair: Array) -> void:
	var outcomes: Array = pair[0]
	var keys: Dictionary = pair[1]
	_t(not outcomes.is_empty() or not keys.is_empty(), "story.outcome.detached",
		"战果常量在册：OUTCOMES %d 员、STORY_KEYS %d 枚（这条红了 = 读不到 Director 两表，常量被删回死码）"
			% [outcomes.size(), keys.size()])
	if outcomes.is_empty() and keys.is_empty():
		return  # 两表皆空是 DETACHED 的形态，只红 detached 一条（零节变体按它点名）
	var bad: Array = []
	var missing: Array = []
	for o in ["win", "lose", "flee"]:
		if not (o in outcomes):
			missing.append(o)
	if not missing.is_empty():
		bad.append("outcome 漏 %s（WorldMap / 探针发过的收法）" % [missing])
	var extra: Array = []
	for o in outcomes:
		if not (o in ["win", "lose", "flee"]):
			extra.append(o)
	if not extra.is_empty():
		bad.append("outcome 多出 %s（谁发的？）" % [extra])
	var want_keys := {}
	if "win" in outcomes:
		want_keys["boarded"] = "win"
	if "lose" in outcomes:
		want_keys["sunk"] = "lose"
	if "flee" in outcomes:
		want_keys["flee_ok"] = "flee"
	var lack: Array = []
	for k in want_keys:
		if not keys.has(k):
			lack.append(k)
	if not lack.is_empty():
		bad.append("剧情键漏 %s（海图回写与探针认的）" % [lack])
	var odd: Array = []
	for k in keys:
		if not want_keys.has(k):
			odd.append(k)
	if not odd.is_empty():
		bad.append("剧情键多出 %s（没人发也没人认）" % [odd])
	var vague: Array = []
	for k in keys:
		if not (k in odd):
			var note := str(keys[k]).strip_edges()
			if note == "" or not note.begins_with(str(want_keys[k]) + "："):
				vague.append(k)
	if not vague.is_empty():
		bad.append("键注 %s 空了或没按「结局：」写" % [vague])
	_t(bad.is_empty(), "story.outcome.constants", "战果契约在册：outcome %d 员齐、剧情键 %d 枚恰好（%s）" % [
		outcomes.size(), keys.size(), ", ".join((keys as Dictionary).keys())], "; ".join(bad))


## 已知缺陷表的形状：每条都写了属主 / 缘由 / 修法（修好即删靠的是有人看得懂这条）
func _judge_known_table(table: Dictionary) -> void:
	var bad: Array = []
	for k in table:
		var d: Dictionary = table[k]
		for f in ["owner", "why", "fix"]:
			if str(d.get(f, "")).strip_edges() == "":
				bad.append("%s 缺 %s" % [k, f])
	_t(bad.is_empty(), "known.shape", "已知缺陷登记 %d 条都写了属主 / 缘由 / 修法" % table.size(), "; ".join(bad))


## 真跑一遍：泉州起锚的海图上「迎战」海盗 → WorldMap 开战 → 两艘快船先后接舷夺下 → 海图回写
func _story_live_capture() -> void:
	var st := _save_state()
	var gm: Node = root.get_node("GameManager")
	var fleet: Node = root.get_node("Fleet")
	var gs: Node = root.get_node("GameState")
	_battle_fleet(fleet)
	gs.set("last_port", "quanzhou")
	var chart := await _spawn_chart()
	if chart == null:
		_restore_state(st)
		return
	var consts: Dictionary = (load("res://scripts/SeaChart.gd") as GDScript).get_script_constant_map()
	var pirate: Dictionary = consts.get("PIRATE_ENEMY", {})
	var ships0: int = (fleet.get("ships") as Array).size()
	var money0: int = int(gs.get("money"))
	chart.call("_on_fight_pirates")
	var pb: Dictionary = gm.get("pending_battle")
	_t(bool(pb.get("battle", false)) and pb.get("source", {}) == {"scene": "SeaChart", "event": "pirate"},
		"story.encounter.source", "遇盗迎战写 pending_battle：battle=true，source={scene: SeaChart, event: pirate}",
		"得 %s" % [pb.get("source", {})])
	var ens: Array = pb.get("enemy", [])
	_t(ens.size() == 1 and ens[0] == pirate, "story.encounter.enemy", "敌船条目即 SeaChart.PIRATE_ENEMY（%s）" % [pirate], "得 %s" % [ens])
	var wm := _battle_under(chart)
	var rec: Array = []
	_t(wm != null and bool(wm.get("combat_mode")) and wm.battle_finished.is_connected(Callable(chart, "_on_battle_result")),
		"story.encounter.worldmap", "WorldMap 叠上海图、进战斗模式，battle_finished 接回 SeaChart._on_battle_result")
	if wm == null:
		chart.free()
		_restore_state(st)
		return
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate()]))
	var foes := _foes(wm)
	_t(foes.size() == int(pirate.get("count", 0)) and foes.all(func(f): return str(f.get("ship_type")) == str(pirate.get("type"))),
		"story.encounter.spawn", "按条目刷出 %d 艘 %s" % [int(pirate.get("count", 0)), pirate.get("type", "")], "得 %d 艘" % foes.size())
	for f in foes:
		f.set("fire_timer", INF)  # 只冻敌炮（同 combat_probe_stage.freeze_enemy_fire）：旗舰不挨炮，战损只看夺船记账
		f.set("crew", 0)  # 敌船无人：白刃必胜，夺船这条路一定走到
	var wm_ref: WeakRef = weakref(wm)
	for i in foes.size():
		var foe_ref: WeakRef = weakref(foes[i])
		wm.call("_board_enemy", foes[i])
		await _frames_until(func() -> bool: return foe_ref.get_ref() == null or not rec.is_empty(), 30)
		if i < foes.size() - 1:
			_t(rec.is_empty() and wm_ref.get_ref() != null, "story.capture.hold", "夺下第 %d 艘、还剩敌船：海战不收" % (i + 1))
	await _frames_until(func() -> bool: return not rec.is_empty(), 30)
	var got_ships: Array = (fleet.get("ships") as Array).slice(ships0)
	_t(got_ships.size() == foes.size() and got_ships.all(func(s): return str(s.get("type")) == str(pirate.get("type")) and str(s.get("name")) == "快船"),
		"story.capture.fleet", "夺下的 %d 艘按船型 %s、船名「快船」并入舰队" % [foes.size(), pirate.get("type", "")],
		"得 %s" % [got_ships.map(func(s): return "%s/%s" % [s.get("type"), s.get("name")])])
	_t(rec.size() == 1 and rec[0][0] == "win", "story.capture.win", "敌船夺尽即以 win 收战，battle_finished 恰一次", "得 %s" % [rec])
	var data: Dictionary = rec[0][1] if not rec.is_empty() else {}
	_t(bool(data.get("boarded", false)), "story.capture.boarded", "末一艘是接舷夺下的：data.boarded=true", "得 data=%s" % [data])
	_t(data.has("player_damage") and float(data.get("player_damage", -1.0)) >= 0.0, "story.capture.damage",
		"data.player_damage 在、且不为负（旗舰这仗没挨炮）", "得 %s" % [data.get("player_damage")])
	var log_text := str((chart.get("log_label") as RichTextLabel).text) if chart.get("log_label") != null else ""
	_t((gm.get("pending_battle") as Dictionary).is_empty() and int(gs.get("money")) > money0,
		"story.writeback.settle", "海图结算：pending_battle 清空、战利钱入账", "钱 %d → %d" % [money0, int(gs.get("money"))])
	_t(log_text.find("接舷既定") >= 0, "story.capture.writeback", "海图航海札记记「接舷既定」", "札记首行：%s" % log_text.get_slice("\n", 0))
	chart.free()
	_restore_state(st)


## 另两种了局与元军哨船：弃战（flee_ok）、旗舰沉（sunk）各走一遍 battle_finished → 海图回写；哨船迎战 source.event=yuan_patrol
func _story_live_outcomes() -> void:
	var st := _save_state()
	var gm: Node = root.get_node("GameManager")
	var fleet: Node = root.get_node("Fleet")
	root.get_node("GameState").set("last_port", "quanzhou")
	var fx: GDScript = load("res://scripts/combat/CombatFx.gd")
	# 期望的札记按 CombatFx 现拼（文案归 combat09，改了措辞这里跟着走）：无货、没挨炮、余船尚在
	for c in [["flee", "_on_fight_pirates", "pirate", {"flee_ok": true}, str(fx.call("sea_flee_ok_note"))],
			["lose", "_on_fight_patrol", "yuan_patrol", {"sunk": true}, str(fx.call("sea_sunk_note", "", 0, false))]]:
		_battle_fleet(fleet)
		var chart := await _spawn_chart()
		if chart == null:
			break
		chart.call(c[1])
		var pb: Dictionary = gm.get("pending_battle")
		_t(str(pb.get("source", {}).get("event", "")) == c[2], "story.%s.source" % c[0],
			"%s 迎战：pending_battle.source.event=%s" % [c[1], c[2]], "得 %s" % [pb.get("source", {})])
		var wm := _battle_under(chart)
		if wm == null:
			_t(false, "story.%s.worldmap" % c[0], "%s 叠上 WorldMap" % c[1])
			chart.free()
			continue
		for f in _foes(wm):
			f.set("fire_timer", INF)
		var rec: Array = []
		wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate()]))
		if c[0] == "flee":
			wm.call("_battle_exit", "flee", {"flee_ok": true, "player_damage": 0.0})
		else:
			wm.call("_battle_player_sunk")
		var data: Dictionary = rec[0][1] if rec.size() == 1 else {}
		var want: Dictionary = c[3]
		var key: String = want.keys()[0]
		_t(rec.size() == 1 and rec[0][0] == c[0] and data.get(key) == want[key] and data.has("player_damage"),
			"story.%s.payload" % c[0], "%s：battle_finished(\"%s\", data) 带 %s=%s 与 player_damage" % [c[1], c[0], key, want[key]],
			"得 %s" % [rec])
		var log_text := str((chart.get("log_label") as RichTextLabel).text)
		_t(log_text.find(str(c[4])) >= 0 and (gm.get("pending_battle") as Dictionary).is_empty(),
			"story.%s.writeback" % c[0], "海图回写「%s」、清 pending_battle" % str(c[4]).left(16), "札记首行：%s" % log_text.get_slice("\n", 0))
		chart.free()
	_restore_state(st)


## 开战用的船队：福船（中）一条、水手 40、士气 70（不碰存档）
func _battle_fleet(fleet: Node) -> void:
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "福船", "crew": 40, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": 300.0, "max_durability": 300.0}])
	fleet.set("morale", 70)


## 海图起在 root 下（泉州），等它把界面搭好；remaining_li 设成还有路可走、sailing 仍假：
## 战后 _after_combat 走 _sail_next_day，而它见 sailing 为假当场返回——不抵港、不续航、不抽下一日事件
func _spawn_chart() -> Node:
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	for _i in 4:
		await process_frame
	_t(chart.get("log_label") != null, "story.chart.ready", "SeaChart 在 headless 下起得来（航海札记栏在）")
	if chart.get("log_label") == null:
		chart.free()
		return null
	chart.set("remaining_li", 50.0)
	return chart


func _battle_under(chart: Node) -> Node:
	for c in chart.get_children():
		if c.has_signal("battle_finished") and not c.is_queued_for_deletion():
			return c
	return null


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _frames_until(cond: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _save_state() -> Dictionary:
	var fleet: Node = root.get_node("Fleet")
	var gs: Node = root.get_node("GameState")
	return {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"money": gs.get("money"), "fame": gs.get("fame"), "martial": gs.get("martial"), "last_port": gs.get("last_port"),
		"pb": (root.get_node("GameManager").get("pending_battle") as Dictionary).duplicate(true)}


func _restore_state(st: Dictionary) -> void:
	var fleet: Node = root.get_node("Fleet")
	var gs: Node = root.get_node("GameState")
	fleet.set("ships", st["ships"])
	fleet.set("morale", st["morale"])
	for k in ["money", "fame", "martial", "last_port"]:
		gs.set(k, st[k])
	root.get_node("GameManager").set("pending_battle", st["pb"])


# ══ 七、接线普查 ══════════════════════════════════════════

## 各模块被谁按文件名引用：现役脚本（WorldMap / Ship / PirateShip / Cannonball / SeaChart 等），加上同波别的模块。
## CombatDirector 登记了全部路径，不算引用。只报不判（接线不在本波强制范围）
func _sec_census() -> void:
	var live := ["res://scripts/WorldMap.gd", "res://scripts/Ship.gd", "res://scripts/PirateShip.gd", "res://scripts/Cannonball.gd",
		"res://scripts/SeaChart.gd", "res://scripts/combat/BoardingStage.gd", "res://scripts/combat/CombatFx.gd",
		"res://scripts/ui/CombatLetterbox.gd", "res://scripts/combat/CombatShoreHook.gd", "res://scripts/Main.gd"]
	var rows := Director.census()
	var srcs := {}
	for p in live:
		srcs[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	for row in rows:
		if row["present"]:
			srcs[row["path"]] = FileAccess.get_file_as_string(row["path"])
	for row in rows:
		if not row["present"]:
			_info("%s：未落地（%s）" % [str(row["path"]).get_file(), row["lane"]])
			continue
		var fname := str(row["path"]).get_file()
		var users := []
		var peers := []
		for p in srcs:
			if p == row["path"] or str(srcs[p]).find(fname) < 0:
				continue
			(users if p in live else peers).append(str(p).get_file())
		var by := "现役 %s" % "、".join(users) if not users.is_empty() else "现役脚本还没引用（接线待属主）"
		if not peers.is_empty():
			by += "；同波模块 %s" % "、".join(peers)
		_info("%s（%s）：%s；%s" % [fname, row["lane"], "能加载" if row["loads"] else "加载失败", by])


# ══ 一—五 各节（判据写在各节，样本模块在文件末尾） ═══════════════

func _sec_maneuver() -> void:
	if not _skip_absent("sea_state"):
		var sea := _need("sea_state")
		if sea != null:
			_judge_sea(sea)
	if not _skip_absent("maneuver"):
		var man := _need("maneuver")
		if man != null:
			_judge_maneuver(man)


## 一、海况（combat02 SeaState，一场一份实例）：定风定流照读、风按来向叫；逐帧演化不出 NaN、风力压在 Ship 风暴伤线 150 以下
## （海战固定无风暴伤，见 Ship._process_storm_damage）；同种子可复现
func _judge_sea(m: Script) -> void:
	var miss := _api_missing(m, {"setup": 5, "force_wind": 2, "force_current": 1, "step": 1, "wind_at": 0, "current_at": 0, "wind_name": 0})
	if not _t(miss.is_empty(), "sea.api", "SeaState API：setup / force_wind / force_current / step / wind_at / current_at / wind_name", "; ".join(miss)):
		return
	var s: Object = m.new()
	s.call("setup", 225.0, 0.8, 80.0, "泉州外海", 7)
	s.call("force_wind", 180.0, 100.0)
	var w: Vector2 = s.call("wind_at")
	_t(w.length() > 0.0 and w.normalized().dot(Vector2(0, 1)) > 0.99 and absf(w.length() - 100.0) < 1.0, "sea.force_wind",
		"定风「吹向正南、风力 100」：wind_at ≈ (0, 100)", "得 %s" % w)
	var nm := str(s.call("wind_name"))
	_t(nm.begins_with("北") and nm.ends_with("风"), "sea.name", "风按来向叫：吹向正南的叫「北风」", "得「%s」" % nm)
	s.call("force_current", Vector2(20, 0))
	var c: Vector2 = s.call("current_at")
	_t(c.is_equal_approx(Vector2(20, 0)), "sea.current", "定流 (20, 0)：current_at 照读", "得 %s" % c)
	var lo := INF
	var hi := 0.0
	var finite := true
	for _i in 600:
		s.call("step", 0.1)
		var v: Vector2 = s.call("wind_at")
		finite = finite and is_finite(v.x) and is_finite(v.y)
		lo = minf(lo, v.length())
		hi = maxf(hi, v.length())
	_t(finite and lo > 0.0 and hi < 150.0, "sea.step_bounds", "逐帧演化 60 秒：风力在 (0, 150)、不出 NaN（150 = Ship 风暴伤线）",
		"风力 %.1f–%.1f" % [lo, hi])
	var s1: Object = m.new()
	var s2: Object = m.new()
	s1.call("setup", 225.0, 0.8, 80.0, "澎湖外海", 42)
	s2.call("setup", 225.0, 0.8, 80.0, "澎湖外海", 42)
	for _i in 100:
		s1.call("step", 0.1)
		s2.call("step", 0.1)
	_t(s1.call("wind_at") == s2.call("wind_at") and s1.call("current_at") == s2.call("current_at"), "sea.seed",
		"同种子两份海况演化 10 秒逐帧相同（可复现）", "%s / %s" % [s1.call("wind_at"), s2.call("wind_at")])


## 一、机动（combat02 ManeuverModel）：顶风慢、当头不可行、顺风风大船快；侧风横漂向下风；转向半径随船型；
## 开火舷角分得清正横与船首；接舷接近看舷距与相对航速；上风位不记反；逐帧推进侧风起速、顶风起不来
func _judge_maneuver(m: Script) -> void:
	var miss := _api_missing(m, {"sail_speed": 4, "turn_radius_of": 3, "leeway_drift": 5, "weather_gauge": 3, "fire_arc": 5,
		"boarding_approach": 4, "step": 7})
	if not _t(miss.is_empty(), "man.api", "ManeuverModel API：sail_speed / turn_radius_of / leeway_drift / weather_gauge / fire_arc / boarding_approach / step",
			"; ".join(miss)):
		return
	var t := "fu_ship_medium"
	var head := float(m.call("sail_speed", t, 0.0, 2, 80.0))
	var beam := float(m.call("sail_speed", t, 90.0, 2, 80.0))
	var broad := float(m.call("sail_speed", t, 150.0, 2, 80.0))
	var best := maxf(beam, broad)
	_t(head < beam and head < broad, "man.headwind", "顶风比侧风、斜顺风都慢：顶 %.0f / 侧 %.0f / 斜顺 %.0f" % [head, beam, broad])
	_t(head <= 0.25 * best, "man.no_go", "当头不可行：顶风航速不过最佳帆向的两成五（%.0f / %.0f）" % [head, best])
	var weak := float(m.call("sail_speed", t, 150.0, 2, 40.0))
	var strong := float(m.call("sail_speed", t, 150.0, 2, 120.0))
	_t(strong > broad and broad > weak, "man.wind_gain", "斜顺风风大船快：风力 40 / 80 / 120 得 %.0f / %.0f / %.0f" % [weak, broad, strong])
	var up := Vector2.UP
	var side_drift: Vector2 = m.call("leeway_drift", t, up, 2, Vector2.RIGHT, 80.0)
	var run_drift: Vector2 = m.call("leeway_drift", t, up, 2, up, 80.0)
	_t(side_drift.dot(Vector2.RIGHT) > 1.0 and absf(run_drift.dot(Vector2.RIGHT)) < 0.5, "man.leeway",
		"侧风把船往下风推、正顺风不横漂：侧风 %s / 顺风 %s" % [side_drift, run_drift])
	var r_small := float(m.call("turn_radius_of", "sampan", 200.0, 1))
	var r_big := float(m.call("turn_radius_of", "fu_ship_large", 200.0, 1))
	_t(r_big > r_small, "man.turn_by_type", "转向半径随船型：同航速 200，福船（大）%.0f > 小艍船 %.0f" % [r_big, r_small])
	var beam_arc: Dictionary = m.call("fire_arc", Vector2.ZERO, up, Vector2(300, 0), Vector2.DOWN, 80.0)
	var bow_arc: Dictionary = m.call("fire_arc", Vector2.ZERO, up, Vector2(0, -300), Vector2.DOWN, 80.0)
	_t(bool(beam_arc.get("in_arc", false)) and int(beam_arc.get("side", 0)) == 1 and not bool(bow_arc.get("in_arc", true))
			and int(bow_arc.get("side", 9)) == 0, "man.fire_arc", "开火舷角：正横右舷的目标在射界（side=1），正船首的不在（side=0）",
		"正横 %s / 船首 %s" % [beam_arc.get("side"), bow_arc.get("side")])
	var a := {"pos": Vector2.ZERO, "vel": Vector2(0, -100), "heading": up, "type": t, "gear": 1}
	var near := {"pos": Vector2(100, 0), "vel": Vector2(0, -90), "heading": up, "type": "pirate_boat", "gear": 1}
	var far := _with(near, "pos", Vector2(600, 0))
	var rush := _with(_with(near, "vel", Vector2(0, 500)), "heading", Vector2.DOWN)
	var ok_near := bool((m.call("boarding_approach", a, near, Vector2.RIGHT, 80.0) as Dictionary).get("ok", false))
	var ok_far := bool((m.call("boarding_approach", a, far, Vector2.RIGHT, 80.0) as Dictionary).get("ok", true))
	var ok_rush := bool((m.call("boarding_approach", a, rush, Vector2.RIGHT, 80.0) as Dictionary).get("ok", true))
	_t(ok_near and not ok_far and not ok_rush, "man.boarding", "接舷接近：并舷同速 100 px 钩得上；600 px 够不着；对冲 600 px/s 挂不住",
		"近 %s / 远 %s / 对冲 %s" % [ok_near, ok_far, ok_rush])
	var g_up := float(m.call("weather_gauge", Vector2.ZERO, Vector2(0, 100), Vector2.DOWN))
	var g_dn := float(m.call("weather_gauge", Vector2(0, 100), Vector2.ZERO, Vector2.DOWN))
	_t(g_up > 0.0 and g_dn < 0.0, "man.weather", "上风位：北风里北船对南船占上风（%.2f > 0 > %.2f）" % [g_up, g_dn])
	var hb: Object = m.new(t, 1, 0)
	var hh: Object = m.new(t, 1, 0)
	var vb := Vector2.ZERO
	var vh := Vector2.ZERO
	for _i in 50:
		vb = hb.call("step", up, 0.0, 2, Vector2.RIGHT, 80.0, Vector2.ZERO, 0.1)
		vh = hh.call("step", up, 0.0, 2, Vector2.DOWN, 80.0, Vector2.ZERO, 0.1)
	_t(vb.dot(up) > 50.0 and vh.dot(up) < 0.5 * vb.dot(up), "man.step",
		"逐帧推进 5 秒：侧风满帆起速 %.0f，顶风只 %.0f" % [vb.dot(up), vh.dot(up)])


func _sec_ballistics() -> void:
	if not _skip_absent("ballistics"):
		var b := _need("ballistics")
		if b != null:
			_judge_ballistics(b)
	if not _skip_absent("reload_ammo"):
		var r := _need("reload_ammo")
		if r != null:
			_judge_reload(r, _ship_def())


## 二、弹道（combat03 Ballistics，纯静态）：武器表每样有中文名、装填 > 0、有效射程不过最远；飞行有时、越远越久；
## 越远越难中（散布随射距）；舷角偏出正横射效降
func _judge_ballistics(m: Script) -> void:
	var miss := _api_missing(m, {"weapon": 1, "flight_time": 2, "hit_chance": 2, "bearing_factor": 2, "effective_range": 2})
	if not _t(miss.is_empty(), "bal.api", "Ballistics 静态 API：weapon / flight_time / hit_chance / bearing_factor / effective_range", "; ".join(miss)):
		return
	var table: Dictionary = _const_of(m, "WEAPONS", {})
	var bad: Array = []
	for id in table:
		var w: Dictionary = table[id]
		var nm := str(w.get("name", ""))
		if not _has_cjk(nm):
			bad.append("%s 没有中文名" % id)
		if float(w.get("reload", 0.0)) <= 0.0:
			bad.append("%s 装填 ≤ 0" % id)
		if float(w.get("eff_range", 0.0)) <= 0.0 or float(w.get("eff_range", 0.0)) > float(w.get("max_range", 0.0)):
			bad.append("%s 有效 / 最远射程不合" % id)
	_t(not table.is_empty() and bad.is_empty(), "bal.table", "武器表 %d 样：各有中文名、装填 > 0、有效射程不过最远" % table.size(), "; ".join(bad))
	var slow: Array = []
	var blur: Array = []
	var arc: Array = []
	var narrow := ""
	for id in table:
		var mx := float(table[id].get("max_range", 0.0))
		if not (float(m.call("flight_time", id, 0.8 * mx)) > float(m.call("flight_time", id, 0.3 * mx)) and float(m.call("flight_time", id, 0.3 * mx)) > 0.0):
			slow.append(id)
		if not (float(m.call("hit_chance", id, 0.3 * mx)) > float(m.call("hit_chance", id, 0.9 * mx))):
			blur.append(id)
		# 舷角：正横最好，往船首船尾不升，打不过对舷（偏出正横 150°）；有效射程同样不随偏角变远
		var bf := [0.0, 40.0, 80.0, 150.0].map(func(d): return float(m.call("bearing_factor", id, deg_to_rad(d))))
		var er0 := float(m.call("effective_range", id, 0.0))
		if not (bf[0] >= bf[1] and bf[1] >= bf[2] and bf[2] >= bf[3] and bf[3] < bf[0] and er0 > 0.0
				and er0 >= float(m.call("effective_range", id, deg_to_rad(80.0)))):
			arc.append(id)
		if narrow == "" or float(table[id].get("arc_max", 180.0)) < float(table[narrow].get("arc_max", 180.0)):
			narrow = id
	_t(slow.is_empty(), "bal.flight", "飞行有时：每样武器射得越远飞得越久（三成射程 vs 八成）", "不合：" + ", ".join(slow))
	_t(blur.is_empty(), "bal.spread", "散布随射距：每样武器三成射程比九成射程易中", "不合：" + ", ".join(blur))
	var narrow_cut := narrow != "" and float(m.call("bearing_factor", narrow, deg_to_rad(80.0))) < float(m.call("bearing_factor", narrow, 0.0))
	_t(arc.is_empty() and narrow_cut, "bal.bearing",
		"射界随舷角：每样武器正横最好、往首尾不升、打不过对舷；射界最窄的「%s」偏出正横 80° 射效降" % str(table.get(narrow, {}).get("name", narrow)),
		"不合：" + ", ".join(arc) if not arc.is_empty() else ("" if narrow_cut else "最窄那样偏 80° 照样全效"))


## 二、装填与弹药（combat03 ReloadAmmo，一船一份）：满装能放、放了耗弹、放完要装、装好再放；
## 弹尽不能放（远射一律拒）；告急装得慢（短缺惩罚）
func _judge_reload(m: Script, def: Dictionary) -> void:
	var miss := _api_missing(m, {"setup": 3, "fire": 3, "can_fire": 3, "tick": 1, "is_spent": 0})
	if not _t(miss.is_empty(), "ammo.api", "ReloadAmmo API：setup / fire / can_fire / tick / is_spent", "; ".join(miss)):
		return
	var full: Object = m.new()
	full.call("setup", def, 40, {})
	var stock0 := _ammo_sum(full)
	var shots: Array = full.call("fire", 1, 0.0, 300.0)
	_t(not shots.is_empty(), "ammo.fire", "满装一舷在 300 px 放得出（%d 位）" % shots.size(), "拒：%s" % full.get("last_refusal"))
	_t(_ammo_sum(full) < stock0, "ammo.consume", "放一轮耗弹：%d → %d" % [stock0, _ammo_sum(full)])
	var again: Array = full.call("fire", 1, 0.0, 300.0)
	_t(again.is_empty() and str(full.get("last_refusal")) != "", "ammo.reload", "刚放完再放被拒（装填要时间）", "拒因「%s」" % full.get("last_refusal"))
	var t_full := _ready_after(full)
	_t(t_full > 1.0 and t_full < 60.0, "ammo.reload_time", "装好要 1–60 秒：满装 %.1f 秒后又能放" % t_full)
	var empty: Object = m.new()
	empty.call("setup", def, 40, {"ammo_mult": 0.0})
	var none: Array = empty.call("fire", 1, 0.0, 300.0)
	_t(none.is_empty() and str(empty.get("last_refusal")) != "" and bool(empty.call("is_spent")), "ammo.empty",
		"弹尽：远射一律拒、is_spent 为真", "放出 %d 位，拒因「%s」" % [none.size(), empty.get("last_refusal")])
	var low: Object = m.new()
	low.call("setup", def, 40, {"ammo": _low_stock(full)})
	var low_shots: Array = low.call("fire", 1, 0.0, 300.0)
	var t_low := _ready_after(low) if not low_shots.is_empty() else -1.0
	_t(t_low > t_full, "ammo.low_slow", "告急装得慢：余量一成 %.1f 秒 > 满装 %.1f 秒" % [t_low, t_full])


func _ammo_sum(b: Object) -> int:
	var n := 0
	var d = b.get("ammo")
	if d is Dictionary:
		for k in d:
			n += int(d[k])
	return n


## 各弹种都只留定额的一成（余量告急，但还放得出一轮）
func _low_stock(b: Object) -> Dictionary:
	var out := {}
	var mx = b.get("ammo_max")
	if mx is Dictionary:
		for k in mx:
			out[k] = maxi(8, int(ceil(float(mx[k]) * 0.1)))
	return out


## 放过一轮后，逐 0.1 秒推进到这一舷又能放，返回秒数；60 秒还不行返回 INF
func _ready_after(b: Object) -> float:
	var t := 0.0
	while t < 60.0:
		b.call("tick", 0.1)
		t += 0.1
		if bool(b.call("can_fire", 1, 0.0, 300.0)):
			return t
	return INF


func _sec_damage() -> void:
	if not _skip_absent("damage"):
		var d := _need("damage")
		if d != null:
			_judge_damage(d, _ship_def())
	if not _skip_absent("flood_fire"):
		var f := _need("flood_fire")
		if f != null:
			_judge_floodfire(f)


## 三、损伤（combat04 DamageModel，一船一份）：水线下中弹进水；损管令管用（戽水令比迎敌令水少）；进水拖慢航速；
## 艉部中弹伤舵、转向变钝；火器引火；乱开口子不管就沉。随机数定种，逐场可复现
func _judge_damage(m: Script, def: Dictionary) -> void:
	var miss := _api_missing(m, {"setup": 6, "apply_hit": 1, "step": 2, "set_mode": 1, "speed_factor": 0, "turn_factor": 0,
		"flood_frac": 0, "fire_total": 0})
	if not _t(miss.is_empty(), "dmg.api", "DamageModel API：setup / apply_hit / step / set_mode / speed_factor / turn_factor / flood_frac / fire_total",
			"; ".join(miss)):
		return
	var fresh := _hull(m, def, 7)
	var v0 := float(fresh.call("speed_factor"))
	var r0 := float(fresh.call("turn_factor"))
	_t(float(fresh.call("flood_frac")) == 0.0 and float(fresh.call("fire_total")) == 0.0 and v0 > 0.9, "dmg.fresh",
		"新船：不进水、无火、航速乘数 %.2f" % v0)
	var ctl := _hull(m, def, 11)
	var fight := _hull(m, def, 11)
	for h in [ctl, fight]:
		for z in ["bow", "mid", "stern"]:
			h.call("apply_hit", {"amount": 25.0, "kind": "shot", "zone": z, "side": 1, "high": false})
	ctl.call("set_mode", "flood")
	fight.call("set_mode", "fight")
	_run_hull(fight, 20.0)
	_run_hull(ctl, 20.0)
	var f20 := float(fight.call("flood_frac"))
	_t(f20 > 0.0, "dmg.flood", "水线下中三弹、迎敌令（损管只留几个人）20 秒：进水 %.3f" % f20)
	_t(float(ctl.call("flood_frac")) < f20, "dmg.damage_control",
		"损管令管用：同样三处漏 20 秒，戽水令进水 %.3f < 迎敌令 %.3f" % [ctl.call("flood_frac"), f20])
	_t(float(fight.call("speed_factor")) < v0, "dmg.slows", "进水拖慢航速：%.3f < 新船 %.3f" % [fight.call("speed_factor"), v0])
	var helm := _hull(m, def, 13)
	for _i in 20:
		helm.call("apply_hit", {"amount": 25.0, "kind": "stone", "zone": "stern", "side": 1, "high": true})
	_t(float(helm.call("turn_factor")) < r0, "dmg.rudder", "艉部挨二十颗砲石：转向乘数 %.2f < 新船 %.2f" % [helm.call("turn_factor"), r0])
	var burn := _hull(m, def, 17)
	var lit := false
	for _i in 12:
		burn.call("apply_hit", {"amount": 25.0, "kind": "fire", "zone": "mid", "side": 1, "high": true})
		if float(burn.call("fire_total")) > 0.0:
			lit = true
			break
	_t(lit, "dmg.fire_starts", "火器中甲板引火（十二发内着火）")
	var wreck := _hull(m, def, 19)
	wreck.call("set_mode", "fight")
	for i in 12:
		wreck.call("apply_hit", {"amount": 50.0, "kind": "shot", "zone": ["bow", "mid", "stern"][i % 3], "side": 1 if i % 2 == 0 else -1, "high": false})
	var t := _run_hull(wreck, 600.0, true)
	_t(str(wreck.get("sunk")) != "", "dmg.founder", "水线下十二处大口子、迎敌令不管：%s" % ("%.0f 秒%s" % [t, "倾覆" if str(wreck.get("sunk")) == "capsize" else "灌沉"]
		if str(wreck.get("sunk")) != "" else "600 秒还没沉"))


func _hull(m: Script, def: Dictionary, seed_n: int) -> Object:
	var h: Object = m.new()
	h.call("setup", "fu_ship_medium", def, 40, 300.0, 300.0, seed_n)
	return h


## 按 0.5 秒一步推进 secs 秒（常风、无雨）；until_sunk 时沉了就停。返回走了几秒
func _run_hull(h: Object, secs: float, until_sunk := false) -> float:
	var t := 0.0
	while t < secs:
		h.call("step", 0.5, {"wind": 80.0})
		t += 0.5
		if until_sunk and str(h.get("sunk")) != "":
			break
	return t


## 三、浸水与失火（combat04 FloodFire）：漏了会越灌越多、戽水能减；隔舱板不破水不过舱；火不救会蔓延、有人救能灭
func _judge_floodfire(m: Script) -> void:
	var miss := _api_missing(m, {"setup": 6, "add_leak": 3, "ignite": 2, "step": 5, "flood_frac": 0, "fire_total": 0, "burning": 0,
		"zone_fire": 1})
	if not _t(miss.is_empty(), "ff.api", "FloodFire API：setup / add_leak / ignite / step / flood_frac / fire_total / burning / zone_fire", "; ".join(miss)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var wild: Object = _ff(m)
	wild.call("ignite", "mid", 0.8)
	var t0 := float(wild.call("fire_total"))
	for _i in 120:
		wild.call("step", 0.5, 0, 0, {"wind": 80.0}, rng)
	_t((wild.call("burning") as PackedStringArray).size() >= 2, "ff.spread", "舯部起火无人救 60 秒：烧到邻处（着火 %s）" % [wild.call("burning")],
		"火势 %.2f → %.2f" % [t0, wild.call("fire_total")])
	var saved: Object = _ff(m)
	saved.call("ignite", "mid", 0.5)
	for _i in 20:
		saved.call("step", 0.5, 0, 20, {"wind": 80.0}, rng)
	_t(float(saved.call("zone_fire", "mid")) < 0.05, "ff.douse", "舯部起火、二十人救 10 秒：扑灭（火势 %.2f）" % saved.call("zone_fire", "mid"))
	var leak: Object = _ff(m)
	var bail: Object = _ff(m)
	leak.call("add_leak", 3, 3.0, 1)
	bail.call("add_leak", 3, 3.0, 1)
	var f10 := 0.0
	for i in 60:
		leak.call("step", 0.5, 0, 0, {"wind": 80.0}, rng)
		bail.call("step", 0.5, 12, 0, {"wind": 80.0}, rng)
		if i == 19:
			f10 = float(leak.call("flood_frac"))
	_t(f10 > 0.0 and float(leak.call("flood_frac")) > 1.5 * f10, "ff.leak", "一处漏无人堵：10 秒 %.3f → 30 秒 %.3f，越灌越多（过 1.5 倍）" % [f10, leak.call("flood_frac")])
	_t(float(bail.call("flood_frac")) < float(leak.call("flood_frac")), "ff.bail", "十二人堵漏戽水：30 秒进水 %.3f < 无人 %.3f" % [bail.call("flood_frac"), leak.call("flood_frac")])
	var water = leak.get("water")
	var dry := water is PackedFloat64Array and (water as PackedFloat64Array).size() > 4 and float(water[3]) > 0.0 \
			and float(water[2]) == 0.0 and float(water[4]) == 0.0
	_t(dry, "ff.bulkhead", "水密隔舱：四舱漏、隔舱板没破，三舱与五舱滴水不进", "water=%s" % [water])


func _ff(m: Script) -> Object:
	var f: Object = m.new()
	f.call("setup", 8, 950.0, 0.5, 1.1, 0.0, false)
	return f


func _sec_melee() -> void:
	if _skip_absent("melee"):
		return
	var m := _need("melee")
	if m != null:
		_judge_melee(m)


## 四、接舷白刃（combat05 MeleeResolve，纯静态）：钩索吃相对速度 / 风 / 舷距；多合白刃；人多气盛得船、人少气衰被击退；
## 了局在册、伤亡不越界；同种子可复现；够不着即落空。另跑它自带的 self_check（在就跑）与「两船节点 → 态势」取数。
const MELEE_OUTCOMES := ["capture", "surrender", "repelled", "cut_loose", "hook_miss"]


func _judge_melee(m: Script) -> void:
	var miss := _api_missing(m, {"make_side": 4, "grapple_chance": 3, "resolve": 3, "legacy_outcome": 1})
	if not _t(miss.is_empty(), "melee.api", "MeleeResolve 静态 API：make_side / grapple_chance / resolve / legacy_outcome", "; ".join(miss)):
		return
	var us: Dictionary = m.call("make_side", 80, 70, 1.1, "fu_ship_medium", {"is_player": true})
	var foe: Dictionary = m.call("make_side", 70, 60, 1.0, "pirate_boat")
	var calm := {"rel_speed": 0.0, "distance": 60.0, "wind": 80.0, "windward": 0, "sea": 1}
	var g0 := float(m.call("grapple_chance", us, foe, calm))
	var g_fast := float(m.call("grapple_chance", us, foe, _with(calm, "rel_speed", 300.0)))
	var g_storm := float(m.call("grapple_chance", us, foe, _with(calm, "wind", 260.0)))
	var g_far := float(m.call("grapple_chance", us, foe, _with(calm, "distance", 1000.0)))
	_t(g0 > 0.0 and g0 <= 1.0, "melee.grapple.range", "钩牢率在 (0, 1]：并舷同速、常风 %.2f" % g0)
	_t(g_fast < g0, "melee.grapple.rel_speed", "两船相对快了钩牢率降：相对 300 得 %.2f < 同速 %.2f" % [g_fast, g0])
	_t(g_storm < g0, "melee.grapple.wind", "风急钩牢率降：风力 260 得 %.2f < 常风 80 得 %.2f" % [g_storm, g0])
	_t(g_far == 0.0, "melee.grapple.reach", "舷距 1000 钩索够不着：钩牢率 %.2f" % g_far)
	var hooked := _with(calm, "hooked", true)
	var strong: Dictionary = m.call("make_side", 160, 80, 1.2, "keel_boat", {"is_player": true})
	var weak_d: Dictionary = m.call("make_side", 20, 40, 0.9, "pirate_boat")
	var weak_a: Dictionary = m.call("make_side", 15, 40, 0.9, "keel_boat", {"is_player": true})
	var strong_d: Dictionary = m.call("make_side", 140, 80, 1.2, "pirate_boat")
	var win_s := 0
	var win_w := 0
	var longest := 0
	var bad: Array = []
	for i in 20:
		var r1: Dictionary = m.call("resolve", strong, weak_d, _with(hooked, "seed", 11 + i))
		var r2: Dictionary = m.call("resolve", weak_a, strong_d, _with(hooked, "seed", 11 + i))
		var r3: Dictionary = m.call("resolve", us, foe, _with(hooked, "seed", 11 + i))
		win_s += 1 if str(m.call("legacy_outcome", r1)) == "win" else 0
		win_w += 1 if str(m.call("legacy_outcome", r2)) == "win" else 0
		longest = maxi(longest, int(r3.get("rounds_fought", 0)))
		bad.append_array(_melee_bad(r1, 160, 20) + _melee_bad(r2, 15, 140) + _melee_bad(r3, 80, 70))
	_t(win_s >= 16, "melee.capture", "人多气盛（160 人对 20 人、已钩牢）20 场得船 ≥ 16：得 %d" % win_s)
	_t(win_w <= 4, "melee.repel", "人少气衰（15 人对 140 人、已钩牢）20 场得船 ≤ 4：得 %d" % win_w)
	_t(longest >= 2, "melee.rounds", "均势（80 对 70）甲板白刃打多合：20 场最长 %d 合" % longest)
	_t(bad.is_empty(), "melee.result", "了局在册（%s）、伤亡不为负且不超出人数" % " / ".join(MELEE_OUTCOMES), "; ".join(bad.slice(0, 3)))
	# 六个种子各打两场（lane w53-2）：只打一个种子时，「不认种子」的变异两场随机白刃约 1.85% 碰巧逐字相同（了局、合数、伤亡就那么几种），
	# 变异漏判、本探针随机报红；六个种子全碰巧相同约 4e-11
	var seed_same := true
	for sd in [7, 8, 9, 10, 11, 12]:
		if str(m.call("resolve", us, foe, _with(calm, "seed", sd))) != str(m.call("resolve", us, foe, _with(calm, "seed", sd))):
			seed_same = false
	_t(seed_same, "melee.seed", "同种子两场逐字相同（可复现；六个种子各打两场）")
	var far: Dictionary = m.call("resolve", us, foe, _with(calm, "distance", 1000.0))
	_t(str(far.get("outcome", "")) == "hook_miss" and int(far.get("att_cas", -1)) == 0 and int(far.get("rounds_fought", -1)) == 0,
		"melee.hook_miss", "钩索够不着：了局落空、不开打、无伤亡", "得 %s" % far.get("outcome", ""))
	if m.has_method("approach_from_nodes"):
		var a := CharacterBody2D.new()
		var b := CharacterBody2D.new()
		b.position = Vector2(90, 0)
		a.velocity = Vector2(0, -120)
		b.velocity = Vector2(0, -40)
		var ctx = m.call("approach_from_nodes", a, b)
		_t(ctx is Dictionary and absf(float(ctx.get("distance", -1.0)) - 90.0) < 0.5 and absf(float(ctx.get("rel_speed", -1.0)) - 80.0) < 0.5,
			"melee.approach", "两船节点 → 接舷态势：舷距 90、相对速度 80（ManeuverModel 在就并它的键）", "得 %s" % [ctx])
		a.free()
		b.free()
	if m.has_method("self_check"):
		var probs = m.call("self_check")
		_t(probs is PackedStringArray and (probs as PackedStringArray).is_empty(), "melee.self_check", "MeleeResolve.self_check() 无问题",
			"; ".join(probs) if probs is PackedStringArray else "返回 %s" % type_string(typeof(probs)))


func _melee_bad(r: Dictionary, crew_a: int, crew_d: int) -> Array:
	var out: Array = []
	var o := str(r.get("outcome", ""))
	if not (o in MELEE_OUTCOMES):
		out.append("了局 %s 不在册" % o)
	for pair in [["att_cas", crew_a], ["def_cas", crew_d], ["att_dead", crew_a], ["def_dead", crew_d]]:
		var v := int(r.get(pair[0], -1))
		if v < 0 or v > int(pair[1]):
			out.append("%s=%d 越界（0–%d）" % [pair[0], v, pair[1]])
	return out


func _sec_morale() -> void:
	if _skip_absent("morale"):
		return
	var m := _need("morale")
	if m == null:
		return
	_judge_morale(m)
	if m.has_method("problems"):
		var probs = m.call("problems")
		_t(probs is PackedStringArray and (probs as PackedStringArray).is_empty(), "mor.data", "士气数据 %s 合规、模块在用" % Director.DATA["morale"]["path"],
			"; ".join(probs) if probs is PackedStringArray else "")
	var d = Director.data_of("morale")
	if d is Dictionary and (d as Dictionary).has("bands") and (d as Dictionary).has("strike"):
		var sheet: Object = m.new({"side": "enemy", "morale": 70, "crew": 60, "hull": 300.0})
		var ln := float(sheet.call("rout_line"))
		var lo := float(d["strike"].get("line", 0.0))
		var hi := float(d["bands"].get("shaken", 100.0))
		_t(ln > lo and ln < hi, "mor.data_bands", "溃逃线 %.0f 落在数据的降幡线 %.0f 与动摇线 %.0f 之间" % [ln, lo, hi])


## 五、士气（combat06 CombatMorale，一船一页）：开局如常；死伤、失火压士气；士气过溃逃线才溃（线上不溃、线下即溃）；
## 降幡要士气见底且有压力（被钩、陷围、矢石尽），无压力只溃不降
func _judge_morale(m: Script) -> void:
	var miss := _api_missing(m, {"shock": 1, "tick": 2, "lose_crew": 1, "set_fire": 1, "grapple": 1, "rout_line": 0, "strike_line": 0,
		"is_routing": 0, "has_struck": 0})
	if not _t(miss.is_empty(), "mor.api", "CombatMorale API：shock / tick / lose_crew / set_fire / grapple / rout_line / strike_line / is_routing / has_struck",
			"; ".join(miss)):
		return
	var opts := {"side": "enemy", "type": "", "morale": 70, "crew": 60, "hull": 300.0}
	var calm: Object = m.new(opts)
	_t(not bool(calm.call("is_routing")) and not bool(calm.call("has_struck")), "mor.fresh", "开局士气 70：不溃不降")
	var hurt: Object = m.new(opts)
	var v0 := float(hurt.get("value"))
	hurt.call("lose_crew", 20)
	_t(float(hurt.get("value")) < v0 - 5.0, "mor.casualties", "折三成人手，士气 %.0f → %.0f" % [v0, hurt.get("value")])
	var burnt: Object = m.new(opts)
	var cool: Object = m.new(opts)
	burnt.call("set_fire", 0.8)
	for _i in 20:
		burnt.call("tick", 0.5, {})
		cool.call("tick", 0.5, {})
	_t(float(burnt.get("value")) < float(cool.get("value")) - 2.0, "mor.fire", "大火烧 10 秒：士气 %.0f < 无火 %.0f" % [burnt.get("value"), cool.get("value")])
	var slide: Object = m.new(opts)
	var line := float(slide.call("rout_line"))
	var early := false
	var at := -1.0
	for _i in 60:
		if bool(slide.call("is_routing")):
			at = float(slide.get("value"))
			break
		if float(slide.get("value")) < line - 0.01:
			break
		slide.call("shock", 2.0)
		if bool(slide.call("is_routing")) and float(slide.get("value")) >= line:
			early = true
	_t(not early and at >= 0.0 and at < line, "mor.rout_threshold", "一次压两点往下走：士气过溃逃线 %.0f 才溃（溃时 %.1f）" % [line, at],
		"线上就溃了" if early else ("压到 %.1f 也没溃" % float(slide.get("value")) if at < 0.0 else ""))
	var cornered: Object = m.new(_with(opts, "morale", 30))
	cornered.call("grapple", false)
	for _i in 240:
		cornered.call("tick", 0.5, {"surrounded": true, "ammo_frac": 0.0})
		if bool(cornered.call("has_struck")):
			break
	_t(bool(cornered.call("has_struck")), "mor.strike", "被钩、陷围、矢石尽，士气 30 起耗 120 秒内降幡（得 %s，士气 %.0f）" % [cornered.get("state"), cornered.get("value")])
	var lone: Object = m.new(_with(opts, "morale", 30))
	for _i in 60:
		lone.call("shock", 1.0)
	_t(not bool(lone.call("has_struck")) and float(lone.get("value")) < float(lone.call("strike_line")), "mor.strike_pressure",
		"无压力：士气压到降幡线 %.0f 以下（%.0f）只溃不降" % [lone.call("strike_line"), lone.get("value")], "得 %s" % lone.get("state"))




# ══ 小工具 ══════════════════════════════════════════════

## 脚本 m 上按 want（名字 → 本探针要传的实参个数）逐支查：有这支、且那么多实参调得起（必填 ≤ n ≤ 全部）。返回缺的
func _api_missing(m: Script, want: Dictionary) -> Array:
	var have := {}
	for md in m.get_script_method_list():
		var nm := str(md.get("name", ""))
		if not have.has(nm):
			have[nm] = md
	var out: Array = []
	for nm in want:
		if not have.has(nm):
			out.append("缺 %s" % nm)
			continue
		var n_all := (have[nm].get("args", []) as Array).size()
		var n_req := n_all - (have[nm].get("default_args", []) as Array).size()
		if int(want[nm]) < n_req or int(want[nm]) > n_all:
			out.append("%s 要 %d–%d 个实参，本探针传 %d 个" % [nm, n_req, n_all, int(want[nm])])
	return out


## 脚本（含它继承的内部类）上的常量；样本模块的变异是子类，常量挂在父类上
func _const_of(m: Script, name: String, fallback: Variant) -> Variant:
	var s := m
	while s != null:
		var cm := s.get_script_constant_map()
		if cm.has(name):
			return cm[name]
		s = s.get_base_script()
	return fallback


## 装填 / 损伤两节用的船型条目：福船（中），读 GameManager 的 ships.json（经 Fleet.ship_def）
func _ship_def() -> Dictionary:
	var fleet := root.get_node_or_null("Fleet")
	return fleet.call("ship_def", "fu_ship_medium") if fleet != null else {}


static func _has_cjk(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) >= 0x2E80:
			return true
	return false


static func _with(d: Dictionary, k: String, v) -> Dictionary:
	var c := d.duplicate()
	c[k] = v
	return c


# ══ 引擎错误计数 ══════════════════════════════════════════

## 数带脚本来源的 ERROR / SCRIPT ERROR（push_error、运行期报错、Lambda capture freed 等）；各节收尾看增量
class _ErrLog extends Logger:
	var count := 0
	var lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_ERROR and error_type != ERROR_TYPE_SCRIPT:
			return
		if not file.begins_with("res://") and script_backtraces.is_empty():
			return
		_mutex.lock()
		count += 1
		lines.append(rationale if rationale != "" else code)
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func first_since(n: int) -> String:
		return str(lines[n]) if n < lines.size() else ""


# ══ 零节样本模块（与真模块同一套 API；好样本须全绿，变异各坏一处） ══════════════

## 接舷白刃好样本：钩牢率随相对速度 / 风降、够不着为 0；甲板逐合互折一成二；守方折到两成以下夺船、攻方折到二成五以下击退
class _FakeMelee extends RefCounted:
	static func make_side(crew: int, morale := 60, captain := 1.0, type_id := "", extra := {}) -> Dictionary:
		var s := {"crew": crew, "morale": morale, "captain": captain, "type": type_id}
		s.merge(extra, true)
		return s

	static func grapple_chance(_att: Dictionary, _def: Dictionary, ctx := {}) -> float:
		if float(ctx.get("distance", 60.0)) > 140.0:
			return 0.0
		var wind := float(ctx.get("wind", 80.0))
		return clampf(0.9 / (1.0 + float(ctx.get("rel_speed", 0.0)) / 260.0) * (1.0 if wind <= 100.0 else 100.0 / wind), 0.0, 1.0)

	static func resolve(att: Dictionary, def: Dictionary, ctx := {}) -> Dictionary:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(ctx.get("seed", 1))
		return fight(att, def, ctx, rng, 6)

	static func fight(att: Dictionary, def: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator, max_rounds: int) -> Dictionary:
		var out := {"outcome": "", "rounds_fought": 0, "att_cas": 0, "def_cas": 0, "att_dead": 0, "def_dead": 0}
		if not bool(ctx.get("hooked", false)) and rng.randf() >= _FakeMelee.grapple_chance(att, def, ctx):
			out["outcome"] = "hook_miss"
			return out
		var a0 := float(att["crew"])
		var d0 := float(def["crew"])
		var a := a0
		var d := d0
		for i in max_rounds:
			out["rounds_fought"] = i + 1
			var pa := a * (0.6 + 0.004 * float(att["morale"])) * float(att["captain"])
			var pd := d * (0.6 + 0.004 * float(def["morale"])) * float(def["captain"])
			var la := minf(a, roundf(pd * 0.12 * rng.randf_range(0.75, 1.25)))
			d -= minf(d, roundf(pa * 0.12 * rng.randf_range(0.75, 1.25)))
			a -= la
			if d <= d0 * 0.2:
				out["outcome"] = "capture"
				break
			if a <= a0 * 0.25:
				out["outcome"] = "repelled"
				break
		if out["outcome"] == "":
			out["outcome"] = "cut_loose"
		out["att_cas"] = int(a0 - a)
		out["def_cas"] = int(d0 - d)
		out["att_dead"] = int(out["att_cas"]) / 2
		out["def_dead"] = int(out["def_cas"]) / 2
		return out

	static func legacy_outcome(r: Dictionary) -> String:
		return "win" if str(r.get("outcome", "")) in ["capture", "surrender"] else "lose"

	static func approach_from_nodes(att: Node2D, def: Node2D) -> Dictionary:
		return {"distance": att.global_position.distance_to(def.global_position), "wind": 80.0, "windward": 0, "sea": 1,
			"rel_speed": ((att as CharacterBody2D).velocity - (def as CharacterBody2D).velocity).length()}


class _MutMeleeSpeedBlind extends _FakeMelee:
	static func grapple_chance(_att: Dictionary, _def: Dictionary, ctx := {}) -> float:
		return 0.0 if float(ctx.get("distance", 60.0)) > 140.0 else (0.9 if float(ctx.get("wind", 80.0)) <= 100.0 else 0.4)


class _MutMeleeLongReach extends _FakeMelee:
	static func grapple_chance(_att: Dictionary, _def: Dictionary, ctx := {}) -> float:
		var wind := float(ctx.get("wind", 80.0))
		return clampf(0.9 / (1.0 + float(ctx.get("rel_speed", 0.0)) / 260.0) * (1.0 if wind <= 100.0 else 100.0 / wind), 0.0, 1.0)


class _MutMeleeOneRound extends _FakeMelee:
	static func resolve(att: Dictionary, def: Dictionary, ctx := {}) -> Dictionary:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(ctx.get("seed", 1))
		return _FakeMelee.fight(att, def, ctx, rng, 1)


class _MutMeleeCoin extends _FakeMelee:
	static func resolve(att: Dictionary, def: Dictionary, ctx := {}) -> Dictionary:
		var r := _FakeMelee.resolve(att, def, ctx)
		if str(r["outcome"]) != "hook_miss":
			r["outcome"] = "capture" if int(ctx.get("seed", 0)) % 2 == 1 else "repelled"
		return r


class _MutMeleeUnseeded extends _FakeMelee:
	static func resolve(att: Dictionary, def: Dictionary, ctx := {}) -> Dictionary:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		return _FakeMelee.fight(att, def, ctx, rng, 6)



## 海况好样本：定风按吹向方位存（0 北、90 东，吹向 (sin, −cos)）；逐帧风力围着均值随机游走、夹在 28–130；风按来向叫
class _FakeSea extends RefCounted:
	var wind_to := Vector2(0, 1)
	var wind_speed := 80.0
	var current := Vector2.ZERO
	var mean := 80.0
	var rng := RandomNumberGenerator.new()

	func setup(_bearing: float, _strength: float, base: float, _sea := "", rng_seed := -1) -> void:
		if rng_seed >= 0:
			rng.seed = rng_seed
		else:
			rng.randomize()
		mean = base
		wind_speed = base

	func force_wind(bearing_to: float, strength: float) -> void:
		wind_to = Vector2(sin(deg_to_rad(bearing_to)), -cos(deg_to_rad(bearing_to)))
		mean = strength
		wind_speed = strength

	func force_current(flow: Vector2, _kind := "") -> void:
		current = flow

	func step(dt: float) -> void:
		wind_speed = clampf(wind_speed + ((mean - wind_speed) * 0.5 + rng.randf_range(-20.0, 20.0)) * dt, 28.0, 130.0)

	func wind_at(_pos := Vector2.ZERO) -> Vector2:
		return wind_to * wind_speed

	func current_at(_pos := Vector2.ZERO) -> Vector2:
		return current

	func wind_name() -> String:
		var from := -wind_to
		var b := fposmod(rad_to_deg(atan2(from.x, -from.y)), 360.0)
		return ["北", "东北", "东", "东南", "南", "西南", "西", "西北"][int(round(b / 45.0)) % 8] + "风"


class _MutSeaBackwards extends _FakeSea:
	func force_wind(bearing_to: float, strength: float) -> void:
		super.force_wind(bearing_to, strength)
		wind_to = -wind_to


class _MutSeaRunaway extends _FakeSea:
	func step(dt: float) -> void:
		wind_speed *= 1.0 + 0.1 * dt


class _MutSeaUnseeded extends _FakeSea:
	func setup(bearing: float, strength: float, base: float, sea := "", _rng_seed := -1) -> void:
		super.setup(bearing, strength, base, sea, -1)


## 机动好样本：帆速曲线顶风 0、斜顺风最快、开方吃风；转向半径按船型；横漂 ∝ 侧风分量；射界正横 ±30°；钩距 140、相对 420 挂不住
class _FakeManeuver extends RefCounted:
	var v := 0.0

	func _init(_type := "", _sail_lv := 1, _helmsman := 0) -> void:
		pass

	static func sail_speed(_type: String, theta_deg: float, gear: int, wind_speed: float, _sail_lv := 1, _helmsman := 0) -> float:
		var polar := 0.0 if theta_deg < 45.0 else lerpf(0.5, 1.0, clampf((theta_deg - 45.0) / 105.0, 0.0, 1.0))
		return 280.0 * polar * [0.0, 0.6, 1.0][clampi(gear, 0, 2)] * sqrt(maxf(wind_speed, 0.0) / 80.0)

	static func turn_radius_of(type_id: String, speed: float, _gear := 1, _helmsman := 0) -> float:
		return absf(speed) / float({"sampan": 1.2, "fu_ship_large": 0.6}.get(type_id, 0.9))

	static func leeway_drift(_type: String, heading: Vector2, gear: int, wind_to: Vector2, wind_speed: float) -> Vector2:
		var r := Vector2(-heading.y, heading.x)
		return r * 0.2 * (1.0 + gear) * wind_speed * wind_to.normalized().dot(r)

	static func weather_gauge(a_pos: Vector2, b_pos: Vector2, wind_to: Vector2) -> float:
		return (b_pos - a_pos).normalized().dot(wind_to.normalized())

	static func fire_arc(shooter_pos: Vector2, heading: Vector2, target_pos: Vector2, _wind_to: Vector2, _wind_speed: float,
			_gear := 1, arc_half := 30.0) -> Dictionary:
		var b := rad_to_deg(heading.angle_to(target_pos - shooter_pos))
		var inside := absf(absf(b) - 90.0) <= arc_half
		return {"in_arc": inside, "side": (1 if b > 0.0 else -1) if inside else 0}

	static func boarding_approach(a: Dictionary, b: Dictionary, _wind_to: Vector2, _wind_speed: float, reach := 140.0) -> Dictionary:
		var d := (a["pos"] as Vector2).distance_to(b["pos"])
		var rel := ((a["vel"] as Vector2) - (b["vel"] as Vector2)).length()
		return {"distance": d, "ok": d <= reach and rel <= 420.0}

	func step(heading: Vector2, _helm: float, gear: int, wind_to: Vector2, wind_speed: float, current: Vector2, dt: float,
			_mods := {}) -> Vector2:
		var theta := absf(rad_to_deg(heading.angle_to(-wind_to)))
		v += (_FakeManeuver.sail_speed("", theta, gear, wind_speed) - v) * (1.0 - exp(-0.9 * dt))
		return heading * v + current


class _MutManHeadwind extends _FakeManeuver:
	static func sail_speed(_type: String, _theta_deg: float, gear: int, wind_speed: float, _sail_lv := 1, _helmsman := 0) -> float:
		return 280.0 * [0.0, 0.6, 1.0][clampi(gear, 0, 2)] * sqrt(maxf(wind_speed, 0.0) / 80.0)


class _MutManWindBlind extends _FakeManeuver:
	static func sail_speed(_type: String, theta_deg: float, gear: int, _wind_speed: float, _sail_lv := 1, _helmsman := 0) -> float:
		return _FakeManeuver.sail_speed("", theta_deg, gear, 80.0)


class _MutManNoLeeway extends _FakeManeuver:
	static func leeway_drift(_type: String, _heading: Vector2, _gear: int, _wind_to: Vector2, _wind_speed: float) -> Vector2:
		return Vector2.ZERO


class _MutManSameRadius extends _FakeManeuver:
	static func turn_radius_of(_type_id: String, speed: float, _gear := 1, _helmsman := 0) -> float:
		return absf(speed) / 0.9


class _MutManArcAll extends _FakeManeuver:
	static func fire_arc(_shooter_pos: Vector2, _heading: Vector2, _target_pos: Vector2, _wind_to: Vector2, _wind_speed: float,
			_gear := 1, _arc_half := 30.0) -> Dictionary:
		return {"in_arc": true, "side": 1}


class _MutManBoardAlways extends _FakeManeuver:
	static func boarding_approach(a: Dictionary, b: Dictionary, _wind_to: Vector2, _wind_speed: float, _reach := 140.0) -> Dictionary:
		return {"distance": (a["pos"] as Vector2).distance_to(b["pos"]), "ok": true}


class _MutManGaugeFlip extends _FakeManeuver:
	static func weather_gauge(a_pos: Vector2, b_pos: Vector2, wind_to: Vector2) -> float:
		return -_FakeManeuver.weather_gauge(a_pos, b_pos, wind_to)


## 弹道好样本：两样武器；飞行时 = 射距 / 速；命中率随射距线性降；舷角过全效弧线性收到射界边为 0
class _FakeBallistics extends RefCounted:
	const WEAPONS := {
		"gongnu": {"name": "弓弩", "reload": 4.5, "eff_range": 300.0, "max_range": 500.0, "speed": 520.0, "arc_full": 60.0, "arc_max": 115.0},
		"chuangnu": {"name": "床子弩", "reload": 13.0, "eff_range": 520.0, "max_range": 820.0, "speed": 640.0, "arc_full": 30.0, "arc_max": 62.0},
	}

	static func weapon(id: String) -> Dictionary:
		return _FakeBallistics.WEAPONS.get(id, {})

	static func bearing_factor(id: String, off_beam_rad: float) -> float:
		var w := _FakeBallistics.weapon(id)
		var deg := rad_to_deg(absf(off_beam_rad))
		var full := float(w.get("arc_full", 30.0))
		var lim := float(w.get("arc_max", 60.0))
		return 1.0 if deg <= full else clampf((lim - deg) / (lim - full), 0.0, 1.0)

	static func effective_range(id: String, off_beam_rad := 0.0) -> float:
		return float(_FakeBallistics.weapon(id).get("eff_range", 0.0)) * (0.6 + 0.4 * _FakeBallistics.bearing_factor(id, off_beam_rad))

	static func flight_time(id: String, dist: float) -> float:
		return dist / float(_FakeBallistics.weapon(id).get("speed", 500.0))

	static func hit_chance(id: String, dist: float, off_beam_rad := 0.0) -> float:
		var mx := float(_FakeBallistics.weapon(id).get("max_range", 500.0))
		return clampf(0.95 - 0.8 * dist / mx, 0.0, 1.0) * _FakeBallistics.bearing_factor(id, off_beam_rad)


class _MutBalInstant extends _FakeBallistics:
	static func flight_time(_id: String, _dist: float) -> float:
		return 0.0


class _MutBalNoSpread extends _FakeBallistics:
	static func hit_chance(id: String, _dist: float, off_beam_rad := 0.0) -> float:
		return 0.9 * _FakeBallistics.bearing_factor(id, off_beam_rad)


class _MutBalAllRound extends _FakeBallistics:
	static func bearing_factor(_id: String, _off_beam_rad: float) -> float:
		return 1.0


## 装填好样本：一舷一位弓弩，每放耗箭 4、装 4 秒；余量不到四分之一装 ×1.35；箭不够一放即弹尽
class _FakeReload extends RefCounted:
	const RELOAD := 4.0
	var ammo := {}
	var ammo_max := {}
	var last_refusal := ""
	var wait := 0.0

	func setup(_def: Dictionary, _crew: int, opts := {}) -> void:
		ammo_max = {"jian": roundi(100.0 * float(opts.get("ammo_mult", 1.0)))}
		ammo = ammo_max.duplicate()
		var given: Dictionary = opts.get("ammo", {})
		for k in given:
			ammo[k] = int(given[k])

	func tick(delta: float, _crew := -1, _morale := -1.0) -> void:
		wait = maxf(0.0, wait - delta)

	func refusal(dist: float) -> String:
		if wait > 0.0:
			return "未装毕"
		if int(ammo.get("jian", 0)) < 4:
			return "弹尽"
		return "射程不及" if dist > 500.0 else ""

	func can_fire(_side: int, _off_beam := 0.0, dist := -1.0) -> bool:
		return refusal(dist) == ""

	func fire(side: int, _off_beam := 0.0, dist := -1.0, _max_n := 0) -> Array:
		last_refusal = refusal(dist)
		if last_refusal != "":
			return []
		spend()
		wait = RELOAD * (1.35 if is_low() else 1.0)
		return [{"weapon": "gongnu", "side": side}]

	func spend() -> void:
		ammo["jian"] = int(ammo["jian"]) - 4

	func is_low() -> bool:
		var mx := int(ammo_max.get("jian", 0))
		return mx > 0 and float(ammo.get("jian", 0)) / float(mx) < 0.25

	func is_spent() -> bool:
		return int(ammo.get("jian", 0)) < 4


class _MutReloadInfinite extends _FakeReload:
	func spend() -> void:
		pass


class _MutReloadEmptyFires extends _FakeReload:
	func refusal(dist: float) -> String:
		if wait > 0.0:
			return "未装毕"
		return "射程不及" if dist > 500.0 else ""


class _MutReloadInstant extends _FakeReload:
	func fire(side: int, off_beam := 0.0, dist := -1.0, max_n := 0) -> Array:
		var out := super.fire(side, off_beam, dist, max_n)
		wait = 0.0
		return out


class _MutReloadNoPenalty extends _FakeReload:
	func fire(side: int, off_beam := 0.0, dist := -1.0, max_n := 0) -> Array:
		var out := super.fire(side, off_beam, dist, max_n)
		if not out.is_empty():
			wait = RELOAD
		return out


## 浸水失火好样本：漏按 1% / 秒进舱、各舱不串；堵漏按人头压漏、戽水按人头减水；火按 logistic 涨、过 0.45 引邻处、按人头压
class _FakeFloodFire extends RefCounted:
	const NEIGHBORS := {"bow": ["mid"], "mid": ["bow", "stern", "rig"], "stern": ["mid"], "rig": ["mid"]}
	var water := PackedFloat64Array()
	var flow := PackedFloat64Array()
	var fire := {"bow": 0.0, "mid": 0.0, "stern": 0.0, "rig": 0.0}

	func setup(comps: int, _volume: float, _reserve: float, _stability: float, _fire_resist := 0.0, _powder := false) -> void:
		water.resize(comps)
		water.fill(0.0)
		flow.resize(comps)
		flow.fill(0.0)

	func add_leak(i: int, rate: float, _side: int) -> void:
		flow[i] += rate

	func ignite(zone: String, intensity: float) -> bool:
		fire[zone] = maxf(float(fire[zone]), intensity)
		return true

	func zone_fire(zone: String) -> float:
		return float(fire.get(zone, 0.0))

	func fire_total() -> float:
		var t := 0.0
		for z in fire:
			t += float(fire[z])
		return t

	func burning() -> PackedStringArray:
		var out := PackedStringArray()
		for z in fire:
			if float(fire[z]) > 0.02:
				out.append(z)
		return out

	func flood_frac() -> float:
		var t := 0.0
		for w in water:
			t += w
		return t / maxf(1.0, float(water.size()))

	func step(delta: float, flood_crew: int, fire_crew: int, _env: Dictionary, _rng: RandomNumberGenerator, _heel := 0.0) -> Dictionary:
		flood(delta, flood_crew)
		burn(delta, fire_crew)
		return {"events": []}

	func flood(delta: float, crew: int) -> void:
		for i in water.size():
			flow[i] = maxf(0.0, flow[i] - 0.1 * crew * delta)
			water[i] = clampf(water[i] + (flow[i] * 0.01 - (0.02 * crew if water[i] > 0.0 else 0.0)) * delta, 0.0, 1.0)

	func burn(delta: float, crew: int) -> void:
		var catch: Array = []
		for z in fire:
			var f := float(fire[z])
			if f <= 0.0:
				continue
			f = clampf(f + (0.05 * f * (1.1 - f) - douse(crew)) * delta, 0.0, 1.0)
			fire[z] = f if f >= 0.02 else 0.0
			if f >= 0.45:
				catch.append_array(spread_to(z))
		for nb in catch:
			if float(fire[nb]) <= 0.0:
				fire[nb] = 0.12

	func douse(crew: int) -> float:
		return 0.03 * crew

	func spread_to(zone: String) -> Array:
		return NEIGHBORS[zone]


class _MutFFNoSpread extends _FakeFloodFire:
	func spread_to(_zone: String) -> Array:
		return []


class _MutFFUndousable extends _FakeFloodFire:
	func douse(_crew: int) -> float:
		return 0.0


class _MutFFSelfSealing extends _FakeFloodFire:
	func flood(delta: float, crew: int) -> void:
		super.flood(delta, crew)
		for i in flow.size():
			flow[i] *= 0.2


class _MutFFBailless extends _FakeFloodFire:
	func flood(delta: float, _crew: int) -> void:
		super.flood(delta, 0)


class _MutFFNoBulkheads extends _FakeFloodFire:
	func flood(delta: float, crew: int) -> void:
		super.flood(delta, crew)
		var avg := flood_frac()
		water.fill(avg)


## 损伤好样本：水线下中弹在该段开漏（交 _FakeFloodFire 灌）；艉部中弹伤舵；火器着火；损管令按四档分人；过半舱水即沉
class _FakeDamage extends RefCounted:
	const SPLIT := {"auto": [0.3, 0.3], "fire": [0.1, 0.6], "flood": [0.6, 0.1], "fight": [0.0, 0.0]}
	var ff := _FakeFloodFire.new()
	var sail := 1.0
	var rudder := 1.0
	var mode := "auto"
	var crew := 40
	var sunk := ""

	func setup(_type: String, _def: Dictionary, p_crew: int, _hull: float, _hull_max: float, _seed := 0) -> void:
		ff = _FakeFloodFire.new()
		ff.setup(4, 900.0, 0.5, 1.0)
		crew = p_crew

	func apply_hit(hit: Dictionary) -> Dictionary:
		var zone := str(hit.get("zone", "mid"))
		if not bool(hit.get("high", true)):
			leak(zone, float(hit.get("amount", 25.0)))
		elif str(hit.get("kind", "")) == "fire":
			ff.ignite(zone, 0.3)
		elif zone == "stern":
			hurt_rudder()
		return {"hull": 10.0, "crew": 0, "events": []}

	func leak(zone: String, amount: float) -> void:
		ff.add_leak(int({"bow": 0, "mid": 1, "stern": 3}.get(zone, 1)), amount * 0.2, 1)

	func hurt_rudder() -> void:
		rudder = maxf(0.0, rudder - 0.1)

	func set_mode(p_mode: String) -> bool:
		mode = p_mode
		return true

	func split() -> Array:
		return SPLIT.get(mode, SPLIT["auto"])

	func step(delta: float, _env := {}) -> Dictionary:
		var s := split()
		ff.step(delta, int(crew * float(s[0])), int(crew * float(s[1])), {}, null)
		check_sunk()
		return {"founder": sunk, "events": []}

	func check_sunk() -> void:
		if ff.flood_frac() >= 0.5:
			sunk = "flood"

	func speed_factor() -> float:
		return clampf((0.15 + 0.85 * sail) * (1.0 - 0.9 * ff.flood_frac()), 0.08, 1.0)

	func turn_factor() -> float:
		return clampf((0.25 + 0.75 * rudder) * (1.0 - 0.6 * ff.flood_frac()), 0.1, 1.0)

	func flood_frac() -> float:
		return ff.flood_frac()

	func fire_total() -> float:
		return ff.fire_total()


class _MutDmgNoLeak extends _FakeDamage:
	func leak(_zone: String, _amount: float) -> void:
		pass


class _MutDmgNoControl extends _FakeDamage:
	func split() -> Array:
		return SPLIT["fight"]


class _MutDmgRudderless extends _FakeDamage:
	func hurt_rudder() -> void:
		pass


class _MutDmgUnsinkable extends _FakeDamage:
	func check_sunk() -> void:
		pass


## 士气好样本：溃逃线 20、降幡线 12；死伤按人头比例压、火与压力逐秒耗；压力（被钩 / 陷围 / 矢石尽）凑满二样且过降幡线才降
class _FakeMorale extends RefCounted:
	var value := 60.0
	var state := "steady"
	var crew0 := 1
	var crew := 1
	var fire := 0.0
	var grappled := false

	func _init(opts := {}) -> void:
		value = float(opts.get("morale", 60.0))
		crew0 = maxi(1, int(opts.get("crew", 1)))
		crew = crew0
		judge()

	func rout_line() -> float:
		return 20.0

	func strike_line() -> float:
		return 12.0

	func shock(amount: float, _cause := "") -> float:
		if state == "struck":
			return 0.0
		value = clampf(value - amount, 0.0, 100.0)
		judge()
		return amount

	func lose_crew(n: int) -> void:
		crew = maxi(0, crew - n)
		shock(40.0 * float(n) / float(crew0))

	func set_fire(level: float) -> void:
		fire = level

	func grapple(as_attacker := false) -> void:
		grappled = not as_attacker

	func tick(delta: float, ctx := {}) -> void:
		var p := pressure(ctx)
		var drain := burn_rate() + float(p)
		if drain > 0.0:
			value = clampf(value - drain * delta, 0.0, 100.0)
		judge(p)

	func burn_rate() -> float:
		return 1.5 * fire

	func pressure(ctx := {}) -> int:
		return int(grappled) + int(bool(ctx.get("surrounded", false))) + int(float(ctx.get("ammo_frac", -1.0)) == 0.0)

	func judge(p := 0) -> void:
		if state == "struck":
			return
		if value < strike_line() and p >= 2:
			state = "struck"
		elif value < rout_line():
			state = "routing"
		elif state != "routing":
			state = "steady" if value >= 55.0 else ("shaken" if value >= 35.0 else "wavering")

	func is_routing() -> bool:
		return state == "routing"

	func has_struck() -> bool:
		return state == "struck"


class _MutMoraleNeverRout extends _FakeMorale:
	func judge(p := 0) -> void:
		if state == "struck":
			return
		if value < strike_line() and p >= 2:
			state = "struck"
		else:
			state = "steady" if value >= 55.0 else ("shaken" if value >= 35.0 else "wavering")


class _MutMoraleEarlyRout extends _FakeMorale:
	func judge(p := 0) -> void:
		if state == "struck":
			return
		if value < strike_line() and p >= 2:
			state = "struck"
		elif value < 50.0:
			state = "routing"


class _MutMoraleCasualtyBlind extends _FakeMorale:
	func lose_crew(n: int) -> void:
		crew = maxi(0, crew - n)


class _MutMoraleFireproof extends _FakeMorale:
	func burn_rate() -> float:
		return 0.0


class _MutMoraleNeverStrike extends _FakeMorale:
	func judge(_p := 0) -> void:
		super.judge(0)


class _MutMoraleStrikeFree extends _FakeMorale:
	func judge(_p := 0) -> void:
		super.judge(2)
