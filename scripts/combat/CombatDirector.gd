## 写实海战装配台（lane combat10）：登记 hali-combat-wave1 各路新模块的路径 / 所属 lane / 数据文件，
## 探测哪些已落地、能否加载；另登记剧情挂钩锚点（SeaChart 遇盗 → WorldMap 开战 → 战果回写 → 夺船入列）。
## 只装配、只探测：不改玩法，WorldMap / Ship / PirateShip 不调它（接线归各自 lane），不读 autoload、不碰存档。
## 调用方：tools/combat_realism_probe.gd（五块冒烟 + 剧情挂钩）、tools/combat_wire_probe.gd（锚点断言）。
## 日后接线想按「在就用、不在就走旧公式」取可选模块，走 load_module(id)，不必硬 preload 还没落地的文件。
extends RefCounted

## 模块登记：id → 路径 / lane / 管什么。路径照各 lane brief 的独占范围写；挪了路径改这里，探针跟着走。
const MODULES := {
	"sea_state": {"path": "res://scripts/combat/SeaState.gd", "lane": "combat02", "what": "风级 / 风向 / 海流"},
	"maneuver": {"path": "res://scripts/combat/ManeuverModel.gd", "lane": "combat02", "what": "舷向航速 / 转向 / 舷角 / 接舷接近"},
	"ballistics": {"path": "res://scripts/combat/Ballistics.gd", "lane": "combat03", "what": "飞行 / 散布 / 舷角射程"},
	"reload_ammo": {"path": "res://scripts/combat/ReloadAmmo.gd", "lane": "combat03", "what": "分炮位装填 / 弹药存量 / 缺弹"},
	"damage": {"path": "res://scripts/combat/DamageModel.gd", "lane": "combat04", "what": "船体 / 帆 / 舵 / 水手分系统损伤"},
	"flood_fire": {"path": "res://scripts/combat/FloodFire.gd", "lane": "combat04", "what": "浸水缓沉 / 失火蔓延与扑救"},
	"melee": {"path": "res://scripts/combat/MeleeResolve.gd", "lane": "combat05", "what": "钩索 / 跳帮 / 多回合白刃 / 夺船"},
	"morale": {"path": "res://scripts/combat/CombatMorale.gd", "lane": "combat06", "what": "战斗士气 / 溃逃 / 降幡 / 投降"},
	"captain_ai": {"path": "res://scripts/combat/EnemyCaptainAI.gd", "lane": "combat07", "what": "敌将战术状态机"},
	"orders_panel": {"path": "res://scripts/ui/CombatOrdersPanel.gd", "lane": "combat08", "what": "玩家海战指令"},
	"status_hud": {"path": "res://scripts/ui/CombatStatusHud.gd", "lane": "combat08", "what": "风 / 舷角 / 弹药 / 损伤 / 士气状态条"},
}

## 数据文件登记（combat01 立 schema，combat06 立士气表）
const DATA := {
	"combat_phases": {"path": "res://data/combat_phases.json", "lane": "combat01", "what": "战斗阶段"},
	"weapons": {"path": "res://data/weapons.json", "lane": "combat01", "what": "宋元近海武器槽"},
	"sea_state": {"path": "res://data/combat_sea_state.json", "lane": "combat01", "what": "风级 / 流向枚举与默认值"},
	"morale": {"path": "res://data/combat_morale.json", "lane": "combat06", "what": "士气阈值"},
}

## 剧情挂钩锚点：遇盗 / 夺船两条故事线挂在哪几支函数上、那里必须还有什么字样。
## needles 按原文子串认（落在该函数体里）；func 按行首 `[static ]func 名字(` 认（同 tools/src_probe.gd）。
## 剧情日后要在「遇盗开打」「夺得敌船」上挂旗标 / 新闻，就挂在这些函数上；锚点动了，探针先红。
const STORY_ANCHORS := [
	{"id": "encounter_roll", "file": "res://scripts/core/Voyage.gd", "func": "pirate_sighting",
		"needles": ["EventKind.PIRATE"], "what": "逐日抽签抽到海盗：返回 kind=PIRATE 的「不明船影」事件"},
	{"id": "encounter_choice", "file": "res://scripts/SeaChart.gd", "func": "_show_event",
		"needles": ["Voyage.EventKind.PIRATE", "_add_event_action(\"迎战\", _on_fight_pirates)"],
		"what": "海图事件浮层：海盗事件给「迎战」，接 _on_fight_pirates"},
	{"id": "encounter_battle", "file": "res://scripts/SeaChart.gd", "func": "_on_fight_pirates",
		"needles": ["GameManager.pending_battle", "PIRATE_ENEMY", "\"source\": {\"scene\": \"SeaChart\", \"event\": \"pirate\"}", "_enter_battle()"],
		"what": "迎战：写 pending_battle（source.event=pirate）再开战"},
	{"id": "patrol_battle", "file": "res://scripts/SeaChart.gd", "func": "_on_fight_patrol",
		"needles": ["GameManager.pending_battle", "PATROL_ENEMY", "\"event\": \"yuan_patrol\"", "_enter_battle()"],
		"what": "元军哨船迎战：同一条开战路（source.event=yuan_patrol）"},
	{"id": "battle_enter", "file": "res://scripts/SeaChart.gd", "func": "_enter_battle",
		"needles": ["WorldMap.tscn", "battle_finished.connect(_on_battle_result)"],
		"what": "叠 WorldMap 上场，战果信号接回海图"},
	{"id": "battle_setup", "file": "res://scripts/WorldMap.gd", "func": "_ready",
		"needles": ["GameManager.pending_battle", "_setup_combat("], "what": "WorldMap 读 pending_battle 进战斗"},
	{"id": "capture_ship", "file": "res://scripts/WorldMap.gd", "func": "_cut_win",
		"needles": ["Fleet.add_ship(", "_BoardingStage.begin("],
		"what": "白刃胜：开场挂「接舷」钩索题签、入册敌船、resolve「夺船」、调用 _end_capture 收战收尾"},
	{"id": "capture_ship_exit", "file": "res://scripts/WorldMap.gd", "func": "_end_capture",
		"needles": ["_battle_exit(\"win\", {\"boarded\": true})", "_note_fate(enemy"],
		"what": "夺下末一艘即以 boarded=true 收战（_cut_win / _cut_yield 共用收尾）"},
	{"id": "battle_exit", "file": "res://scripts/WorldMap.gd", "func": "_battle_exit",
		"needles": ["battle_finished.emit(outcome, data)", "\"player_damage\""],
		"what": "收战：发 battle_finished(outcome, data)，data 带战损"},
	{"id": "result_writeback", "file": "res://scripts/SeaChart.gd", "func": "_on_battle_result",
		"needles": ["\"boarded\"", "接舷既定。", "GameManager.pending_battle = {}"],
		"what": "海图结算：boarded 记「接舷既定」，清 pending_battle"},
]

## 战果信号 battle_finished(outcome, data)：outcome 取值；data 恒带 player_damage，另按结局带下列剧情键（可缺省）
const OUTCOMES := ["win", "lose", "flee"]
const STORY_KEYS := {"boarded": "win：末一艘是接舷夺下的", "sunk": "lose：旗舰沉没", "flee_ok": "flee：甩脱追船"}


static func entry(id: String) -> Dictionary:
	return MODULES.get(id, {})


static func path_of(id: String) -> String:
	return str(entry(id).get("path", ""))


## 文件在不在（不 load，不触发编译）
static func present(id: String) -> bool:
	var p := path_of(id)
	return p != "" and FileAccess.file_exists(p)


## 在就 load，编不过 / 不在返回 null。调用方拿 null 走旧公式或判红，本件不打错。
static func load_module(id: String) -> Script:
	if not present(id):
		return null
	var s := load(path_of(id)) as Script
	if s == null or not s.can_instantiate():
		return null
	return s


## 一次普查：每个登记模块在不在、编不编得过、有几支方法 / 常量（探针打表用）
static func census() -> Array:
	var out: Array = []
	for id in MODULES:
		var e: Dictionary = MODULES[id]
		var row := {"id": id, "path": e["path"], "lane": e["lane"], "what": e["what"],
			"present": present(id), "loads": false, "methods": [], "consts": []}
		if row["present"]:
			var s := load(e["path"]) as Script
			row["loads"] = s != null and s.can_instantiate()
			if row["loads"]:
				row["methods"] = method_names(s)
				row["consts"] = s.get_script_constant_map().keys()
		out.append(row)
	return out


## 脚本自己声明的方法名（不含基类的）
static func method_names(s: Script) -> Array:
	var out: Array = []
	if s == null:
		return out
	for m in s.get_script_method_list():
		var n := str(m.get("name", ""))
		if n != "" and not out.has(n):
			out.append(n)
	return out


## 数据文件：在就解析，返回 Dictionary / Array；不在或坏了返回 null
static func data_of(id: String) -> Variant:
	var p := str(DATA.get(id, {}).get("path", ""))
	if p == "" or not FileAccess.file_exists(p):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))


## 装配：取一组模块，在的给脚本、不在的记进 missing。探针按它决定哪节验、哪节跳过。
static func assemble(ids: Array) -> Dictionary:
	var kit := {"scripts": {}, "missing": [], "broken": []}
	for id in ids:
		if not present(id):
			kit["missing"].append(id)
			continue
		var s := load_module(id)
		if s == null:
			kit["broken"].append(id)
		else:
			kit["scripts"][id] = s
	return kit


## 剧情挂钩锚点体检：sources 给 {res 路径: 源码}（缺省读盘），返回问题列表，空 = 锚点全在。
## 源码由调用方传入，探针可以拿改过的副本自证「锚点丢了会红」。
static func anchor_problems(sources := {}) -> Array:
	var out: Array = []
	var cache := sources.duplicate()
	for a in STORY_ANCHORS:
		var f := str(a["file"])
		if not cache.has(f):
			cache[f] = FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else ""
		var body := func_body(str(cache[f]), str(a["func"]))
		if body == "":
			out.append("%s：%s 里找不到 func %s（%s）" % [a["id"], f.get_file(), a["func"], a["what"]])
			continue
		for n in a["needles"]:
			if body.find(str(n)) < 0:
				out.append("%s：%s.%s 里没有「%s」（%s）" % [a["id"], f.get_file(), a["func"], n, a["what"]])
	return out


## 行首 `[static ]func 名字(` 起、到下一个行首 func 止（口径同 tools/src_probe.gd 的 func_body；本件在 scripts/ 下，不反向依赖 tools/）
static func func_body(src: String, fn: String) -> String:
	var rx := RegEx.create_from_string("(?m)^[ \\t]*(?:static\\s+)?func\\s+" + _esc(fn) + "\\s*\\(")
	var m := rx.search(src)
	if m == null:
		return ""
	var nx := RegEx.create_from_string("(?m)^(?:static\\s+)?func\\s").search(src, m.get_end())
	return src.substr(m.get_start(), (nx.get_start() if nx != null else src.length()) - m.get_start())


static func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out
