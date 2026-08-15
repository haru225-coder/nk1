class_name SeaFeedback extends RefCounted

## 航海/海战/海遇 → 玩家可见文案与壳层日志（AppRoot.log_event）
## 不引用 CombatState/GameState 标识符，避免 class 编译期依赖 autoload。

const COLOR_BRASS := "#d4a84b"
const COLOR_PLAYER := "#7ec8e8"
const COLOR_ENEMY := "#e88888"
const COLOR_PHASE := "#a09070"
const COLOR_ROUND := "#e0d0a0"
const COLOR_WIN := "#ffd700"

## 与 CombatState.VictoryType 序值对齐（NONE=0 … DEFEATED_CAPTURED=6）
const VT_NONE := 0
const VT_SUNK := 1
const VT_CAPTURED := 2
const VT_DUEL_VICTORY := 3
const VT_FLED := 4
const VT_DEFEATED_SUNK := 5
const VT_DEFEATED_CAPTURED := 6


static func combat_start_log(enemy_name: String) -> String:
	var name := enemy_name.strip_edges()
	if name == "":
		name = "未知敌舰"
	return "【海战】遭遇 %s，进入交战。\n" % name


static func combat_end_log(result: Dictionary, combat_state = null) -> String:
	if result == null or not (result is Dictionary) or result.is_empty():
		return "【海战】交战中止。\n"
	var vt: int = int(result.get("victory_type", VT_NONE))
	var short := victory_short(vt)
	var enemy := ""
	if combat_state != null:
		var n = combat_state.get("enemy_name")
		if n != null:
			enemy = str(n)
	var rounds: int = int(result.get("round", 0))
	var bits: PackedStringArray = [short]
	if enemy != "":
		bits.append(enemy)
	if rounds > 0:
		bits.append("第%d回合" % rounds)
	return "【海战】%s。\n" % " · ".join(bits)


static func victory_short(victory_type: int) -> String:
	match victory_type:
		VT_SUNK:
			return "击沉敌舰"
		VT_CAPTURED:
			return "拿捕敌舰"
		VT_DUEL_VICTORY:
			return "单挑获胜"
		VT_FLED:
			return "成功撤退"
		VT_DEFEATED_SUNK:
			return "旗舰沉没"
		VT_DEFEATED_CAPTURED:
			return "甲板失守"
		_:
			return "交战结束"


static func is_player_victory(victory_type: int) -> bool:
	return victory_type == VT_SUNK \
		or victory_type == VT_CAPTURED \
		or victory_type == VT_DUEL_VICTORY \
		or victory_type == VT_FLED


static func event_open_log(title: String) -> String:
	var t := title.strip_edges()
	if t == "":
		t = "海上遭遇"
	return "【海遇】%s\n" % t


static func event_result_log(title: String, msg: String) -> String:
	var t := title.strip_edges()
	if t == "":
		t = "海上遭遇"
	var one := msg.replace("\n", " ").strip_edges()
	if one.length() > 72:
		one = one.substr(0, 70) + "…"
	if one == "":
		return "【海遇】%s — 已处理。\n" % t
	return "【海遇】%s — %s\n" % [t, one]


static func event_to_combat_log(enemy_name: String) -> String:
	var name := enemy_name.strip_edges()
	if name == "":
		name = "敌舰"
	return "【海遇】冲突升级，与 %s 开战。\n" % name


static func contact_engage_bbcode(enemy_name: String) -> String:
	return "[color=%s]【接敌】[/color] %s 出现在视野中，距离尚远。风帆已张，听候号令。" % [
		COLOR_BRASS, enemy_name
	]


static func phase_status_bbcode(phase_label: String, extra: String = "") -> String:
	var line := "[color=%s]当前阶段：%s[/color]" % [COLOR_PHASE, phase_label]
	if extra != "":
		line += " · " + extra
	return line


static func round_header_bbcode(round_n: int, kind: String) -> String:
	return "[color=%s]── 第 %d %s ──[/color]" % [COLOR_ROUND, round_n, kind]


static func victory_bbcode(narration: String) -> String:
	return "[color=%s]%s[/color]" % [COLOR_WIN, narration]


## 写入 AppRoot 消息栏
static func push_shell(msg: String) -> void:
	if msg.strip_edges() == "":
		return
	var tree: SceneTree = null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		tree = loop as SceneTree
	if tree == null:
		return
	var MS = load(ResourcePaths.SCRIPT_MODE_STACK)
	if MS != null and MS.has_method("find_host"):
		var host = MS.find_host(tree)
		if host != null and host.has_method("log_event"):
			host.call("log_event", msg)
