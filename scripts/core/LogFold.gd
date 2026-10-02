class_name LogFold
extends RefCounted
## 记事栏折叠（lane fx7 立于 Main，lane w19-g9 抽成公共件，港页船籍簿记事栏与海图船况札记共用一份）：
## 月初通告连着进来、多到要把下面那句（候一日、第 N 日之类玩家这一手的结果句）顶出去时，整串收成一行「冬月初一，
## 月初通告一连 N 则」，原文都留在折叠里、点开就地看；跨了月份的（跳年一次几十则、跨月航程）按月分组，点开先列各月
## 一行、再点哪月铺哪月。折叠会话内，不入存档。
## 宿主（Main / SeaChart）自备五个字段，这里只读写它们、不存状态：
##   _log_lines: PackedStringArray  记事，新的在前；折起的那一行字即 _log_folds 的键
##   _log_folds: Dictionary          键 = 折起那一行的字，值 = {lines: 原文（新的在前）, groups: 按月分组（新的在前）, open: 点开的那月}
##   _log_fold_open: String          就地点开的那一折（键同 _log_folds），"" 为都收着
##   _notice_run: int                记事顶上连着几行是本批通告（折起后算一行）；别的记事一写即归零
##   _notice_when: Array             本批还没折的那几行各自的日子（与 _log_lines 顶上 _notice_run 行一一对应，新的在前）
## 本件不在解析期写 autoload 名（class_name 登记早于 autoload）：历法经 _calendar() 现取。

## 未另给门槛时，连着几则通告就折（与港页 Main.LOG_KEEP 同数：再多一则就把下面那句顶出 8 行记事尾）
const FOLD_AT := 8


static func _calendar() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Calendar")


## 此刻的日子：ym 分组用，date 写起讫，md 写「冬月初一」
static func stamp() -> Dictionary:
	var cal := _calendar()
	return {
		"ym": "%04d-%02d" % [int(cal.year), int(cal.month)],
		"date": str(cal.get_date_string()),
		"md": str(cal.get_month_name()) + str(cal.get_day_name()),
	}


## 记一句寻常记事（玩家这一手的结果句等）：新的在上，本批通告就此断开。keep > 0 时只留最近 keep 条
static func push_line(host: Object, line: String, keep: int) -> void:
	host._notice_run = 0
	host._notice_when = []
	var logs: PackedStringArray = host._log_lines
	logs.insert(0, line)
	if keep > 0 and logs.size() > keep:
		logs.resize(keep)
	host._log_lines = logs
	prune(host)


## 记一则通告（GameManager.monthly_notice）。连着进来的通告够 fold_at 则时整串收成一行，此后同批的都收进这一折；
## 玩家这一手的结果句（候日句先写，通告排在它上面）始终留在记事里，通告也一则不丢
static func push_notice(host: Object, line: String, keep: int, fold_at := FOLD_AT) -> void:
	var logs: PackedStringArray = host._log_lines
	var folds: Dictionary = host._log_folds
	var run: int = mini(int(host._notice_run), logs.size())
	var when: Array = (host._notice_when as Array).slice(0, run)
	var now := stamp()
	var top: String = logs[0] if run > 0 else ""
	if run > 0 and folds.has(top):
		var fold: Dictionary = folds[top]
		folds.erase(top)
		_fold_add(fold, line, now)
		var key := head(fold)
		folds[key] = fold
		logs[0] = key
		if host._log_fold_open == top:
			host._log_fold_open = key
		run = 0
		when = []
	elif run + 1 >= fold_at:
		var fold := {"lines": [], "groups": [], "open": ""}
		# 先折进去的在后：自旧到新逐则收，末了收这一则
		for i in range(run - 1, -1, -1):
			_fold_add(fold, logs[i], when[i] if i < when.size() else now)
		_fold_add(fold, line, now)
		for _i in run:
			logs.remove_at(0)
		var key := head(fold)
		folds[key] = fold
		logs.insert(0, key)
		run = 0
		when = []
	else:
		logs.insert(0, line)
		when.insert(0, now)
	if keep > 0 and logs.size() > keep:
		logs.resize(keep)
	host._log_lines = logs
	host._notice_run = run + 1
	host._notice_when = when
	prune(host)


## 往一折里收一则（新的在前）：同月的进这月那一组，换了月另起一组
static func _fold_add(fold: Dictionary, line: String, when: Dictionary) -> void:
	(fold["lines"] as Array).insert(0, line)
	var groups: Array = fold["groups"]
	if groups.is_empty() or str(groups[0]["ym"]) != str(when["ym"]):
		groups.insert(0, {"ym": when["ym"], "date": when["date"], "md": when["md"], "last": when["date"], "lines": []})
	var g: Dictionary = groups[0]
	(g["lines"] as Array).insert(0, line)
	g["last"] = when["date"]


## 折起那一行的字：同一天的写「冬月初一，月初通告一连 N 则」；一月之内跨了日子写起讫；跨了月（跳年、跨月航程）另写凡几月
static func head(fold: Dictionary) -> String:
	var n: int = (fold["lines"] as Array).size()
	var groups: Array = fold["groups"]
	var first: Dictionary = groups[-1]
	var from := str(first["date"])
	var to := str((groups[0] as Dictionary)["last"])
	if groups.size() > 1:
		return "自%s至于%s，通告一连 %d 则，凡 %d 月" % [from, to, n, groups.size()]
	if from == to:
		return "%s，月初通告一连 %d 则" % [first["md"], n]
	return "自%s至于%s，通告一连 %d 则" % [from, to, n]


## 滚出记事的折叠一并清掉
static func prune(host: Object) -> void:
	var folds: Dictionary = host._log_folds
	for key in folds.keys():
		if not (host._log_lines as PackedStringArray).has(key):
			folds.erase(key)
	if host._log_fold_open != "" and not folds.has(host._log_fold_open):
		host._log_fold_open = ""


## 状态条 / 顶匾那一格：折起的一串仍取其中最上那则（与没折时同一则）
static func latest(host: Object) -> String:
	var logs: PackedStringArray = host._log_lines
	if logs.is_empty():
		return ""
	var fold: Dictionary = (host._log_folds as Dictionary).get(logs[0], {})
	if not fold.is_empty():
		return str(fold["lines"][0]).strip_edges()
	return logs[0].strip_edges()


## 点折起那一行（meta「fold:i」）就地展开 / 收起；点开后按月分组的某月（「fold:i:ym」）再展开 / 收起那一月。
## 认得这个 meta、状态有变时返回 true（宿主据此重画）
static func toggle(host: Object, meta: Variant) -> bool:
	var parts := str(meta).split(":")
	if parts.size() < 2 or parts[0] != "fold":
		return false
	var i := int(parts[1])
	var logs: PackedStringArray = host._log_lines
	if i < 0 or i >= logs.size():
		return false
	var key: String = logs[i]
	var folds: Dictionary = host._log_folds
	if not folds.has(key):
		return false
	if parts.size() >= 3:
		var fold: Dictionary = folds[key]
		fold["open"] = "" if str(fold.get("open", "")) == parts[2] else parts[2]
		host._log_fold_open = key
	else:
		host._log_fold_open = "" if host._log_fold_open == key else key
	return true


## 记事正文（BBCode）：新的在上，sep 隔条；dim_rest 时首条宣纸色、其余淡一档（港页记事栏），否则各条照原墨（海图札记）。
## 折起那一行可点（[url=fold:i]）；点开后原文缩一格淡一档列在它下面，按月分组的先列各月一行（[url=fold:i:ym]）
static func render(host: Object, sep: String, dim_rest: bool) -> String:
	var logs: PackedStringArray = host._log_lines
	var folds: Dictionary = host._log_folds
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)
	var parts := PackedStringArray()
	for i in logs.size():
		var line: String = logs[i]
		var fold: Dictionary = folds.get(line, {})
		var faded := dim_rest and i > 0
		if fold.is_empty():
			parts.append("[color=#%s]%s[/color]" % [dim, line] if faded else line)
			continue
		var open: bool = host._log_fold_open == line
		var fhead := "[url=fold:%d]%s（%s）[/url]" % [i, line, "收起" if open else "点开"]
		var block := PackedStringArray([("[color=#%s]%s[/color]" % [dim, fhead]) if faded else fhead])
		if open:
			block.append_array(_fold_body(fold, i, dim))
		parts.append("\n".join(block))
	return sep.join(parts)


static func _fold_body(fold: Dictionary, i: int, dim: String) -> PackedStringArray:
	var out := PackedStringArray()
	var groups: Array = fold.get("groups", [])
	if groups.size() <= 1:
		for sub in fold["lines"]:
			out.append("[color=#%s]　%s[/color]" % [dim, sub])
		return out
	var open_ym := str(fold.get("open", ""))
	for g in groups:
		var ym := str(g["ym"])
		var gopen := ym == open_ym
		out.append("[color=#%s][url=fold:%d:%s]　%s，通告 %d 则（%s）[/url][/color]" % [
			dim, i, ym, g["date"], (g["lines"] as Array).size(), "收起" if gopen else "点开"])
		if gopen:
			for sub in g["lines"]:
				out.append("[color=#%s]　　%s[/color]" % [dim, sub])
	return out
