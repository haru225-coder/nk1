extends SceneTree
## lane w32-k2 无门禁 sweep：LogFold.render 港页记事栏 dim_rest=true 分支褪色字样断言
##（w30-k3 交主控末条「按月分组的 fold:i:ym 展开后单列那一月」未守面实查：qa_crew_fold_probe C2 三次
##   直调全是 render(host, "\n", false) 海图札记档——dim_rest=true 分支（LogFold.gd:168
##   `faded := dim_rest and i > 0`，港页记事栏：头则宣纸色、其余淡一档）此前全仓无一探针点过。
##   一并补守 w30-k3 留口的「点开之折排在次则时，折头与其下月行的上屏形态」。）
##   摆场复用 w30-k3 仿作宿主 qa_crew_fold_host（LogFold 只读写宿主五件现价字段，不经屏控件）：
##   D1 单条染字：次则折起行 dim=true 裹一层暗色、折头（点开）引子 [url=fold:1] 原样在内；
##     头则平常句 dim=true 照原墨不裹色；次则平常句 dim=true 整句裹一层暗色。
##   D2 折行排头（点开之折当次则、头行是一则平常句）：折头（收起）与月行引子 [url=fold:1:<ym>]
##     同裹一层暗色——外一层裹折头、内一层照旧裹月行，颜色值同一、字面与引子逐字照旧在内。
##   D3 相变一格：同一摆场 dim=false 与 dim=true 换着染，次则折头由无 [color= 转成裹色
##     （守「换档才褪色」，不守「开场即淡」的常染写法）。
##   本探针随本片同 commit 登记 gate_json REGISTRY lane 档 + godot_compile_check SCRIPTS。
##   探针本体已 registration（gate_json REGISTRY lane 档「qa_fold_dim_probe」，不入 EXEMPT、不入 SHOT_PROBES）。
## 用法：godot --headless --path . -s res://tools/qa_fold_dim_probe.gd
## 输出末行 FOLD_DIM cases=N fails=M；M>0 时 exit 1。

const ShotGate := preload("res://tools/shot_gate.gd")

var fails := 0
var cases := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ShotGate.frame_pressure(self)
	var dim: String = UiTheme.hex(UiTheme.TEXT_DIM)

	# 仿作宿主（tools/qa_crew_fold_host.gd，w30-k3 同件）备五件现价字段；直调 render 直收 BBCode 串
	var host: Object = load("res://tools/qa_crew_fold_host.gd").new()
	host.set("_log_lines", PackedStringArray(["则一平常句", "【同一折句】"]))
	host.set("_log_folds", {"【同一折句】": {
		"lines": ["新一则", "旧一则"],
		"groups": [
			{"ym": "1278-05", "date": "1278-05-01", "md": "五月初一", "last": "1278-05-30", "lines": ["新一则"]},
			{"ym": "1278-04", "date": "1278-04-01", "md": "四月初一", "last": "1278-04-29", "lines": ["旧一则"]},
		],
		"open": "",
	}})
	host.set("_log_fold_open", "")
	host.set("_notice_run", 0)
	host.set("_notice_when", [])

	# ── D1 单条染字：折起行当次则裹色；平常句头则不裹、次则裹 ──
	print("── D1 dim_rest=true：次则折行裹一层暗色、头则平常句照原墨")
	var closed: String = LogFold.render(host, "\n", true)
	_expect(closed.contains("[color=#%s][url=fold:1]【同一折句】（点开）[/url][/color]" % dim),
		"次则折起行（i=1）：整行裹 [color=#<dim>]、折头（点开）与引子 [url=fold:1] 原样在内（实读：%s）" % closed.left(80))
	_expect(closed.begins_with("则一平常句\n") and not closed.begins_with("[color="),
		"头则平常句（i=0）：照原墨不裹色、不占褪色份（实读前 40：%s）" % closed.left(40))
	host.set("_log_lines", PackedStringArray(["平常头句", "平常次句"]))
	host.set("_log_folds", {})
	var plain: String = LogFold.render(host, "\n", true)
	_expect(plain == "平常头句\n[color=#%s]平常次句[/color]" % dim,
		"两条平常句：头条照原墨、次条整句裹 [color=#<dim>]（实读全串：%s）" % plain)

	# ── D2 折行排头：点开之折当次则，折头与头一行月行同裹一层色 ──
	print("── D2 dim_rest=true：点开之折排在次则——折头与其下月行的上屏形态")
	host.set("_log_lines", PackedStringArray(["则一平常句", "【同一折句】"]))
	host.set("_log_folds", {"【同一折句】": {
		"lines": ["新一则", "旧一则"],
		"groups": [
			{"ym": "1278-05", "date": "1278-05-01", "md": "五月初一", "last": "1278-05-30", "lines": ["新一则"]},
			{"ym": "1278-04", "date": "1278-04-01", "md": "四月初一", "last": "1278-04-29", "lines": ["旧一则"]},
		],
		"open": "",
	}})
	host.set("_log_fold_open", "【同一折句】")
	var opened: String = LogFold.render(host, "\n", true)
	var fhead2 := "[url=fold:1]【同一折句】（收起）[/url]"
	_expect(opened.contains("[color=#%s]%s[/color]" % [dim, fhead2]),
		"点开之折当次则：折头（收起）整行裹一层暗色、引子 [url=fold:1] 原样在内（实读：%s）" % opened.left(80))
	var month_line := "[color=#%s][url=fold:1:1278-05]　1278-05-01，通告 1 则（点开）[/url][/color]" % dim
	_expect(opened.contains(month_line),
		"折内头一行月行：照旧裹同一暗色、引子 [url=fold:1:1278-05] 与「通告 1 则（点开）」逐字在内"
		+ "（实读后段：%s）" % opened.substr(opened.find(fhead2) + fhead2.length(), 100))
	_expect(opened.contains("[color=#%s]%s[/color]\n%s" % [dim, fhead2, month_line]),
		"折头与头一行月行相邻列开、各裹各的一层暗色（外裹折头 / 内裹月行，层数与色值同一）")

	# ── D3 相变：同一摆场换档才褪色 ──
	print("── D3 同一摆场换档：false 不裹 → true 裹，褪色随开关转")
	host.set("_log_fold_open", "")
	var sea: String = LogFold.render(host, "\n", false)
	_expect(sea.contains("[url=fold:1]【同一折句】（点开）[/url]") and not sea.contains("[color="),
		"同一摆场 dim=false（海图札记档）：折头不裹色、全串无 [color=（实读：%s）" % sea.left(80))
	_expect(closed.contains("[color=#%s][url=fold:1]【同一折句】（点开）[/url][/color]" % dim),
		"同一摆场 dim=true（港页记事栏档）：次则折头转裹 [color=#<dim>]——褪色随档转、不是常染")

	host.free()
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _report() -> void:
	print("FOLD_DIM cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
