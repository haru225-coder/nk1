## 过场接线（cinematics 线）：Main 在哪些时刻演开场 / 章节卡 / 结局过场 / 抵港横幅，由这里统一判定。
## 只放会话内状态（静态变量），**不进存档**；headless（门禁）下 live() 恒为假，Main 直接走原逻辑、不延迟一帧。
##
##   Cinematics.live()                       过场层是否上场（非 headless 且没被巡检关掉）
##   Cinematics.want_opening()               新开一局要不要先演开场（本会话只自动演一次）
##   Cinematics.note_departure(port, day)    过关出港时记一笔
##   Cinematics.take_arrival(port, day)      海图回港时问：这是不是真正抵港（走了日子或换了港）
##   Cinematics.year_text(year, eras)        「景定五年・一二六四」，章节卡按当前年现算
extends RefCounted

const DATA := "res://data/cutscenes.json"
const OPENING := "opening"
const _Player := preload("res://scripts/cutscene/CutscenePlayer.gd")

## 总开关：false 时 Main 一律直接走原逻辑（巡检里「只看册页」的站点用；游戏里恒为 true）
static var enabled := true
## 新开一局是否先演开场（巡检的非开场站点关掉）
static var auto_opening := true
## 本会话已自动演过开场：同一会话再回到起始场景不再自动演（标题页「重看开场」不受限）
static var opening_seen := false
## 出港记录 {"port": id, "day": 绝对日}；判「真正抵港」用，一次一清
static var _departure: Dictionary = {}

const _CN_DIGITS := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
const _CN_NUM := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]


## 过场层是否上场：非 headless、没被巡检关掉、且不是 -s 工具脚本驱动（patrol_shell 等主循环是脚本化的 SceneTree，
## 它量的是界面排版、截的是界面本身，过场盖在上面只会让截图全黑）。游戏本体与 ShotTour 的主循环都是普通 SceneTree。
static func live() -> bool:
	if not enabled or DisplayServer.get_name() == "headless":
		return false
	var ml := Engine.get_main_loop()
	return ml == null or ml.get_script() == null


## 新开一局自动演开场的条件：本会话没演过，且本机航海日志里一卷都没记过——回头玩家（有存档的）不再每次启动
## 先看 84 秒开场（第 1 轮评审 UX M3），想看就点标题页「重看开场」。不写任何偏好文件、不碰存档字段。
static func want_opening() -> bool:
	return live() and auto_opening and not opening_seen and not _any_save() and _Player.has_cutscene(OPENING, DATA)


static func _any_save() -> bool:
	for slot in range(1, SaveLoad.SLOTS + 1):
		if SaveLoad.has_save(slot):
			return true
	return false


static func note_departure(port_id: String, day: int) -> void:
	_departure = {"port": port_id, "day": day}


## 海图回港：出过港，且走了日子或换了港，才算真正抵港（海图上点「回港」原路折回不算）。记录用一次就清。
static func take_arrival(port_id: String, day: int) -> bool:
	if _departure.is_empty():
		return false
	var d := _departure
	_departure = {}
	return day > int(d.get("day", day)) or port_id != str(d.get("port", port_id))


## 年号 + 公元数字：1264 →「景定五年・一二六四」。eras 取 Calendar.ERAS（[起年, 止年, 年号]）；
## 不在年号表里（1279 以后）返回 ""，章节卡退回数据里的静态年号。
static func year_text(year: int, eras: Array) -> String:
	for e in eras:
		if typeof(e) != TYPE_ARRAY or (e as Array).size() < 3:
			continue
		if year >= int(e[0]) and year <= int(e[1]):
			var n := year - int(e[0]) + 1
			var ny := "元" if n == 1 else _cn_small(n)
			var digits := ""
			for ch in str(year):
				digits += _CN_DIGITS[int(ch)]
			return "%s%s年・%s" % [str(e[2]), ny, digits]
	return ""


static func _cn_small(n: int) -> String:
	if n <= 10:
		return _CN_NUM[n]
	if n < 20:
		return "十" + _CN_NUM[n - 10]
	var tens := floori(n / 10.0)
	return _CN_NUM[tens] + "十" + (_CN_NUM[n % 10] if n % 10 > 0 else "")
