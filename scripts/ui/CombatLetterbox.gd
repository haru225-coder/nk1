## 进出海战的上下墨边：焦墨宽边自上下合拢 → 下边里一行题签自左擦出（小朱印 + 题名 + 泥金竖线 + 副题）→
## 停一拍 → 题签淡去、墨边退开。底下的海面始终看得见，不是 UiTransition 那种全黑墨幕。
## 题签写法与 UiTransition 同一路：只写可核对的事实——「海名・事由」，副题是历法日期与敌船数，不写评语。
##
##   var lb := CombatLetterbox.enter(self, CombatLetterbox.sea_title("刺桐外海", "接舷"), "咸淳三年六月十二　快船二艘")
##   var lb := CombatLetterbox.exit(self, CombatLetterbox.outcome_title("win", "刺桐外海"), sub, on_black)
##   if lb != null: await lb.finished
##
## 出战事由按怎么收的场分开写（lane combat09）：炮战得胜分击沉 / 焚舟 / 击退，接舷夺船、敌船降幡受降各有一格，
## 我方分脱战（转舵走开）/ 溃逃（水手溃散）/ 请降（我方降幡）/ 败退（旗舰沉没），天晚起风各自收帆记两散。
## 朱印跟着换字（捷 / 获 / 降 / 毕 / 散 / 溃 / 败），
## 溃逃、请降、败退的印色与题名压暗。印字由题名里的事由反查（act_key），旧调用 exit(…, outcome_title(旧键), …) 不改一字也换印。
## 海战收场一行接线（WorldMap._battle_exit 的 outcome / data 原样递进来，事由、副题、印字都在这里算）：
##   var lb := CombatLetterbox.exit_for(parent, outcome, data, sea_name, Calendar.get_date_string())
##   data 里认的键见 outcome_key / fates_of / fate_counts：本 lane 的 fates / losses / surrendered / burned / repelled / routed，
##   也认士气收场（CombatMorale.battle_outcome）的 morale_verdict / enemy_struck / enemy_fled / struck_types / rout / struck。
##   都缺省时 win 记击沉（旧口径写战罢，outcome_title("win") 仍是战罢）、lose 记败退、flee 记脱战。
##
## 信号契约（lane gd12）：finished 是终止信号，每副墨边不论怎么收尾——演完 / 被新墨边顶掉（_abort）/ 随父节点释放或被摘下——
## 都恰好发一次，所以裸 await finished 不会挂死。caption_shown / covered 是进度信号，只在真演到时发、最多一次：
## 题签前被顶掉就没有 caption_shown，随父释放不补 covered / on_black；等进度信号的一方须带上界，或拿 finished 当放弃的边。
##
## 出战带 on_black 时墨边一直合到中线（全黑）再调它，调用方趁黑换场景，墨边随后退开；不带就和入战一样只留边。
## headless 与 -s 工具脚本（门禁、smoke）下静态入口不建节点、返回 null——调用方自己当帧调 on_black（同 Main.play_transition）。
## 入战不吞输入（开炮倒计时照走，题签只盖在上下边里）；出战合拢时吞键盘和鼠标，防止连按。不暂停游戏、不入存档。
##
## 协程不许挂死（lane gd15）：演出里的等待只走 _await_tween / _await_frame 两个挂起点，不直接 await tween 的 finished
## 或 get_tree().process_frame——kill 掉的 tween 永不发 finished，随父释放 / 退出时 process_frame 不再来，挂着的协程
## 永不醒，退出时报 ObjectDB 泄漏（GDScriptFunctionState），随父释放还报「after await, but class instance is gone」。
## 本幕作废（新一幕 / _abort / 离树）一律走 _cancel_waits：kill tween 并唤醒挂起点，协程醒来见 _run_id 已变就自退。
## waiters 记全部墨边里还挂着的协程数，探针收尾后断言为 0。
extends CanvasLayer

signal caption_shown
signal covered
signal finished
## 内部：挂起点的唤醒（tween 放完 / 下一帧到 / 本幕作废），只由 _wake 与 _cancel_waits 发
signal _woken

const Kit := preload("res://scripts/cutscene/cs_kit.gd")

## 海战 HUD（WorldMap 的 CanvasLayer 1）之上、UiTransition 墨幕 60 之下
const LAYER_INDEX := 58
const GROUP := "nk1_combat_letterbox"
## 单边墨边占画布高度的比例：720 高时 90px，HUD 顶匾与底栏各让出一条
const BAR_FRAC := 0.125
const T_BAR_IN := 0.46
const T_WIPE := 0.40
const T_SUB := 0.26
const T_HOLD := 1.3
const T_CAPTION_OUT := 0.24
const T_BAR_OUT := 0.50
const T_SHUT := 0.36
## 题签离画布左缘
const CAPTION_X := 64.0
const TITLE_SIZE := 34
const SEAL_ENTER := "战"
const SEAL_EXIT := "毕"

## 出战结局 → 事由。结局键与 WorldMap._battle_exit 同名（win / lose / flee），board 为白刃夺船；
## 其余是按怎么收的场细分的键（lane combat09，由 outcome_key 从 outcome + data 算出）。事由两两不同：act_key 按它反查。
const OUTCOME_ACT := {
	"win": "战罢",
	"gun": "击沉",
	"burn": "焚舟",
	"repel": "击退",
	"board": "夺船",
	"surrender": "受降",
	"flee": "脱战",
	"parted": "两散",
	"rout": "溃逃",
	"yield": "请降",
	"lose": "败退",
}
## 结局键 → 出战朱印字。炮战得胜「捷」、夺船「获」、受降「降」、脱战照旧「毕」、两散「散」、溃逃「溃」、请降与败退「败」
const OUTCOME_SEAL := {
	"win": "捷",
	"gun": "捷",
	"burn": "捷",
	"repel": "捷",
	"board": "获",
	"surrender": "降",
	"flee": "毕",
	"parted": "散",
	"rout": "溃",
	"yield": "败",
	"lose": "败",
}
## 这几种收场印色压暗、题名改旧绢色：我方失利，不与得胜的泥金题签同一个样子
const OUTCOME_SOMBER := ["rout", "yield", "lose"]
## 压暗的朱印：朱砂压三成，印面字仍是 SEAL_TEXT（对比只升不降）
const SOMBER_SEAL_DARKEN := 0.32
## 敌船下场 → 副题动词（fate_note）。次序即副题里的先后：受降、夺、焚、击沉、走脱
const FATE_VERB := {
	"struck": "受降",
	"boarded": "夺",
	"burned": "焚",
	"sunk": "击沉",
	"fled": "走脱",
}

var title := ""
var subtitle := ""
var seal_text := ""

var _root: Control
var _top: ColorRect
var _bottom: ColorRect
var _top_line: ColorRect
var _bottom_line: ColorRect
var _clip: Control
var _caption: HBoxContainer
var _head: Label
var _seal: Label
var _rule: ColorRect
var _sub: Label
var _built := false
var _run_id := 0
var _tween: Tween
var _swallow := false
var _black_done := false
var _on_black := Callable()
## finished 已发（本幕终结）：_abort / 离树 / 同帧重入都不再补发
var _done := false
## 挂起序号：每次挂起 +1、作废 +1；过期的 tween.finished / process_frame 回调序号对不上，不唤醒后来的挂起
var _wait_seq := 0
## 全部墨边实例里挂在 _await_tween / _await_frame 上的协程数（探针查：场上墨边全收尾后须为 0，否则就是挂死的协程）
static var waiters := 0

# ── 战后收拾小卡（w53-p4-after，「战后单子」三到五行小选择）────────────
## 挂卡闭包（SeaChart 给的）：(chosen: Dictionary) -> void——chosen 形如 {key: option_id}，每行选什么
var _choice_callback := Callable()
## 卡上的行：每行一个 HBoxContainer，第一个子节点 Label 写行题，后面跟着 Button
var _choice_rows: Array = []
## 每行的 choice 元数据（choices_for 的行原样，择项描色反查 options / key 用；与 _choice_rows 同序）
var _choice_meta: Array = []
## 每行当前选的 option id（_choice_rows 同序；初始 = 该行的 default 项）
var _chosen: Array = []
## 卡本体（PanelContainer）；null = 没挂卡
var _choice_panel: PanelContainer
## 尾行「收拾停当」钮
var _choice_done_btn: Button
## 卡挂出期间吞键盘鼠标（_input 用），免得海图底栏收到 Enter（Enter 只按尾钮）
var _choice_swallow := false
## 卡上每行的行题 + 各选项去重后的最小宽度：触屏点得着的底线
const CHOICE_BTN_MIN := Vector2(72, 36)
## 卡底离屏底的缝
const CHOICE_BOTTOM_MARGIN := 24.0


## 「海名・事由」。海名空着就只写事由，不在这里补地名。
static func sea_title(sea_name: String, act: String) -> String:
	var sea := sea_name.strip_edges()
	var a := act.strip_edges()
	if sea == "":
		return a
	return sea if a == "" else "%s・%s" % [sea, a]


static func outcome_title(outcome: String, sea_name := "") -> String:
	return sea_title(sea_name, OUTCOME_ACT.get(outcome, "战罢"))


## WorldMap._battle_exit 的 (outcome, data) → 出战事由键（OUTCOME_ACT 的键），下场艘数见 fate_counts：
##   win：有敌船降幡 → surrender；有接舷夺下 → board；烧沉的不少于打沉的 → burn；一艘没沉、只是遁走 → repel；
##        其余 → gun（矢石、砲把敌船打沉，即炮战得胜）
##   lose：我方降幡（morale_verdict=player_struck，或 lose 带 struck）→ yield；水手溃散 → rout；否则 lose（旗舰沉没）
##   flee：带 parted（天晚 / 起风，两边各自收帆）→ parted，先于溃散与脱战；水手溃散 → rout；否则 flee（转舵脱离）。
##        溃散认 routed / rout 旗标或 morale_verdict=player_rout。
##   disengaged（combat_phases.json 阶段图的收场，outcomes.disengaged.letterbox_key=parted）→ parted。
##   其余 outcome 原样返回：本就是细分键的直接用，认不得的由 outcome_title 兜底「战罢」。
static func outcome_key(outcome: String, data := {}) -> String:
	var verdict := str(data.get("morale_verdict", ""))
	var routed := _flag(data, "routed") or _flag(data, "rout") or verdict == "player_rout"
	match outcome:
		"win":
			var n := fate_counts(data)
			if int(n["struck"]) > 0:
				return "surrender"
			if int(n["boarded"]) > 0:
				return "board"
			if int(n["burned"]) > 0 and int(n["burned"]) >= int(n["sunk"]):
				return "burn"
			if int(n["sunk"]) == 0 and int(n["fled"]) > 0:
				return "repel"
			return "gun"
		"lose":
			if verdict == "player_struck" or _flag(data, "struck"):
				return "yield"
			return "rout" if routed else "lose"
		"flee":
			if _flag(data, "parted"):
				return "parted"
			return "rout" if routed else "flee"
		"disengaged":
			return "parted"
	return outcome


## data 里敌船下场的明细 [{type, fate, count?}]（fate 取 FATE_VERB 的键）：有 data.fates 就用它；
## 没有就按士气收场（CombatMorale.battle_outcome）拼——struck_types 逐艘记降幡，enemy_struck 比船种多出的、enemy_fled 各按「敌船」记。
static func fates_of(data: Dictionary) -> Array:
	var fates = data.get("fates", [])
	if fates is Array and not fates.is_empty():
		return fates
	var out: Array = []
	var types = data.get("struck_types", [])
	if types is Array:
		for t in types:
			out.append({"type": str(t), "fate": "struck"})
	var more_struck := _count(data, "enemy_struck") - out.size()
	if more_struck > 0:
		out.append({"type": "", "fate": "struck", "count": more_struck})
	var fled := _count(data, "enemy_fled")
	if fled > 0:
		out.append({"type": "", "fate": "fled", "count": fled})
	return out


## 这一战敌船各落了什么下场：FATE_VERB 的键（struck / boarded / burned / sunk / fled）→ 艘数。
##   明细走 fates_of；另认旗标 boarded（WorldMap 现有：末一艘是接舷夺下）、surrendered、burned、repelled（敌船遁走），
##   各记一艘——明细里已有同类下场就不再补记，免得同一艘算两遍。
##   不认 struck 旗标：士气收场里它是我方降幡（lose 才带），outcome_key 另判。
static func fate_counts(data: Dictionary) -> Dictionary:
	var n := {}
	for f in FATE_VERB:
		n[f] = 0
	for entry in fates_of(data):
		if entry is Dictionary and n.has(str(entry.get("fate", ""))):
			n[str(entry.get("fate", ""))] += maxi(0, int(entry.get("count", 1)))
	for pair in [["boarded", "boarded"], ["surrendered", "struck"], ["burned", "burned"], ["repelled", "fled"]]:
		if _flag(data, pair[0]) and int(n[pair[1]]) == 0:
			n[pair[1]] = 1
	return n


## data 里的旗标：true 或正数才算；缺、null、字符串一律不算（不在这里对着坏数据报错）
static func _flag(data: Dictionary, key: String) -> bool:
	var v = data.get(key, false)
	if v is bool:
		return v
	return (v is int or v is float) and v > 0


## data 里的艘数：整数 / 浮点取整，别的一律 0
static func _count(data: Dictionary, key: String) -> int:
	var v = data.get(key, 0)
	return maxi(0, int(v)) if (v is int or v is float) else 0


## 题名里的事由反查结局键：「刺桐外海・受降」→ surrender；入战题名、探针自拟的题名认不得，返回 ""。
static func act_key(p_title: String) -> String:
	var parts := p_title.strip_edges().split("・")
	var act := parts[parts.size() - 1].strip_edges()
	for k in OUTCOME_ACT:
		if OUTCOME_ACT[k] == act:
			return k
	return ""


## 出战朱印字：按题名里的事由取 OUTCOME_SEAL，认不得的照旧「毕」。
static func seal_for(p_title: String) -> String:
	return str(OUTCOME_SEAL.get(act_key(p_title), SEAL_EXIT))


## 副题里的敌船下场：「受降海鹘一艘，夺快船一艘，击沉海鹘二艘」。fates 形同 data.fates（[{type, fate, count?}]）；
## 同一下场里按船种并数（船名走 enemy_note 的短表），下场按 FATE_VERB 的次序排；没有可写的返回 ""。
static func fate_note(fates: Array) -> String:
	var parts: PackedStringArray = []
	for fate in FATE_VERB:
		var order: Array = []
		var counts := {}
		for entry in fates:
			if not entry is Dictionary or str(entry.get("fate", "")) != fate:
				continue
			var type_id := str(entry.get("type", ""))
			if not counts.has(type_id):
				counts[type_id] = 0
				order.append(type_id)
			counts[type_id] += int(entry.get("count", 1))
		var rows: Array = []
		for type_id in order:
			rows.append({"type": type_id, "count": counts[type_id]})
		var ships := enemy_note(rows)
		if ships != "":
			parts.append(str(FATE_VERB[fate]) + ships)
	return "，".join(parts)


## 战后单子第一行（lane w53-16，方案§二 7）：「敌船二艘，击沉一艘、受降一艘。」——先写这一仗的下场，
## 再写账目原句。fates 取 fates_of 的明细（同一下场里按船种并数，写完船种再写「共 N 艘」）；rescued > 0 时续
## 「救起水手 N 人。」（world 侧的落水救援由 w53-17 的 morale_carry 项代管，读不到数就不写）；都没有返回 ""。
static func aftermath_note(fates: Array, rescued := 0) -> String:
	return aftermath_note_opts(fates, rescued, false)


## 战后单子第一行的全参变体（w53-p4-after 战败捞人）：伤亡折损前先垫「冒死救起水手 N 人」——击沉句之前，
## 写一句自己人被捞回来的事。旧三行不变，第四行（前半）加的是冒死救人那一笔。
static func aftermath_note_opts(fates: Array, rescued := 0, lost_rescue := false) -> String:
	var parts: PackedStringArray = []
	var total := 0
	var tally := {}
	for entry in fates:
		if not entry is Dictionary:
			continue
		var fate := str(entry.get("fate", ""))
		if not FATE_VERB.has(fate):
			continue
		var n: int = maxi(1, int(entry.get("count", 1)))
		if not tally.has(fate):
			tally[fate] = 0
		tally[fate] += n
		total += n
	var verbs: PackedStringArray = []
	for fate in FATE_VERB:
		var n := int(tally.get(fate, 0))
		if n > 0:
			verbs.append("%s%s艘" % [str(FATE_VERB[fate]), _cn_count(n)])
	var head := ""
	if total > 0:
		head = "敌船%s艘，%s。" % [_cn_count(total), "、".join(verbs)]
	elif not verbs.is_empty():
		head = "%s。" % "、".join(verbs)
	if head != "":
		parts.append(head)
	if rescued > 0:
		if lost_rescue:
			parts.append("自家落水的水手冒死救回%s人。" % _cn_count(rescued))
		else:
			parts.append("救起水手%s人。" % _cn_count(rescued))
	return "".join(parts)


## 我方折损：「折水手十二人，失船一艘，颠落舱面货九件」。losses 认 crew（折损水手人数）/ ships（沉没或被夺的艘数）/
## cargo（中弹颠落的舱面货件数，WorldMap 收战按开战时货账差出）；都没有返回 ""。
static func loss_note(losses: Dictionary) -> String:
	var parts: PackedStringArray = []
	var crew := int(losses.get("crew", 0))
	if crew > 0:
		parts.append("折水手%s人" % _cn_count(crew))
	var ships := int(losses.get("ships", 0))
	if ships > 0:
		parts.append("失船%s艘" % _cn_count(ships))
	var cargo := int(losses.get("cargo", 0))
	if cargo > 0:
		parts.append("颠落舱面货%s件" % _cn_count(cargo))
	return "，".join(parts)


## 出战副题：「历法日期　敌船下场　我方折损」，缺哪段略哪段；三段都空返回 ""。
static func exit_subtitle(date_str: String, fates := [], losses := {}) -> String:
	var segs: PackedStringArray = []
	for seg in [date_str.strip_edges(), fate_note(fates), loss_note(losses)]:
		if seg != "":
			segs.append(seg)
	return "　".join(segs)


## 敌船数副题：「快船二艘」。entry 形同 pending_battle.enemy（type / count）。
## 船名用本地短表，避免 -s 探针编译期依赖 Fleet/GameManager；表里凡是 ships.json 的 type，名字须与 ships.json 的 name 一致（check_symbols 对账）。
static func enemy_note(enemy_list: Array) -> String:
	var type_names := {
		"pirate_boat": "快船",
		"sea_falcon": "海鹘",
		"fu_ship": "福船",
		"iron_child": "铁子",
		"tetsu": "铁子",
	}
	var parts: PackedStringArray = []
	for entry in enemy_list:
		if not entry is Dictionary:
			continue
		var count := int(entry.get("count", 1))
		if count <= 0:
			continue
		var type_id := String(entry.get("type", ""))
		var ship_name := String(type_names.get(type_id, "敌船"))
		parts.append("%s%s艘" % [ship_name, _cn_count(count)])
	return "・".join(parts)


static func _cn_count(n: int) -> String:
	var digits := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n < 10:
		return digits[n]
	if n < 20:
		return "十" + (digits[n - 10] if n > 10 else "")
	if n < 100:
		return digits[int(n / 10)] + "十" + (digits[n % 10] if n % 10 else "")
	return str(n)


## 入战：墨边合拢、题签、退开。返回的节点演完自删。
static func enter(parent: Node, p_title: String, p_subtitle := "") -> CanvasLayer:
	var lb := _spawn(parent)
	if lb != null:
		lb.call("play_enter", p_title, p_subtitle)
	return lb


## 出战：题签后若带 on_black，墨边合到全黑时调一次，再退开。
static func exit(parent: Node, p_title: String, p_subtitle := "", on_black := Callable()) -> CanvasLayer:
	var lb := _spawn(parent)
	if lb != null:
		lb.call("play_exit", p_title, p_subtitle, on_black)
	return lb


## 海战收场：outcome / data 原样取自 WorldMap._battle_exit，事由走 outcome_key，副题走 exit_subtitle（敌船下场取 fates_of，
## 我方折损取 data.losses），印字随事由；其余同 exit（headless 下返回 null，调用方当帧自己调 on_black）。
static func exit_for(parent: Node, outcome: String, data := {}, sea_name := "", date_str := "",
		on_black := Callable()) -> CanvasLayer:
	var losses = data.get("losses", {})
	var sub := exit_subtitle(date_str, fates_of(data), losses if losses is Dictionary else {})
	return exit(parent, outcome_title(outcome_key(outcome, data), sea_name), sub, on_black)


static func _spawn(parent: Node) -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	# 同时只留一副墨边：旧的立刻收场（没到全黑的先补调它的 on_black）
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		n.call("_abort")
	var lb: CanvasLayer = (load("res://scripts/ui/CombatLetterbox.gd") as GDScript).new()
	lb.set_meta(&"auto_free", true)
	lb.add_to_group(GROUP)
	parent.add_child(lb)
	return lb


## 战后收拾小卡（w53-p4-after，方案 §九「战后单子」）：选择行挂在一副墨边同层的 CanvasLayer 上，
## 海图札记照落、卡浮在上面。choices = AfterAction.choices_for 的各行；Enter 或点尾钮「收拾停当」，
## 按 chosen 回填 callback（chosen: Dictionary（key→option_id））。
## headless 返回 null；调用方自己走 callback({})（各开关默认项的账，探针直接调落账，不经这里）。
## 卡不暂停航行 / 不吞海图底栏 Enter 之外的操作；挂卡期间 _input 只吞键盘鼠标（海图底栏在卡下，连按不穿透）。
static func attach_after_action(parent: Node, choices: Array, callback: Callable) -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	var lb: CanvasLayer = (load("res://scripts/ui/CombatLetterbox.gd") as GDScript).new()
	lb.set_meta(&"auto_free", true)
	parent.add_child(lb)
	lb.call("_build_after_action", choices, callback)
	return lb


func _build_after_action(choices: Array, callback: Callable) -> void:
	_choice_callback = callback
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_choice_swallow = true

	_choice_panel = PanelContainer.new()
	# 底中挂、给左右各留一掌边，行题 + 按钮一字排开塞得下五行（方案 §九「三到五行」）。
	# 尺寸照内容自定：先铺满 VB（每行一行题 + 按钮），再按 combined_minimum_size 反推 PanelContainer 的 size，
	# 底沿贴画布底留 CHOICE_BOTTOM_MARGIN 一缝。
	_choice_panel.add_theme_stylebox_override("panel", UiTheme.plaque())
	_root.add_child(_choice_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.add_theme_constant_override("margin_left", 16)
	vb.add_theme_constant_override("margin_top", 10)
	vb.add_theme_constant_override("margin_right", 16)
	vb.add_theme_constant_override("margin_bottom", 10)
	_choice_panel.add_child(vb)

	var head_lbl := Label.new()
	head_lbl.text = "战后收拾"
	head_lbl.add_theme_font_override("font", UiTheme.title_font())
	head_lbl.add_theme_font_size_override("font_size", 22)
	head_lbl.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	vb.add_child(head_lbl)

	for row in choices:
		if not row is Dictionary:
			continue
		var opts = row.get("options", [])
		if not opts is Array or opts.is_empty():
			continue
		# 该行默认项：没有 default=true 的就取头一个
		var def_idx := 0
		for j in opts.size():
			if bool(opts[j].get("default", false)):
				def_idx = j
				break
		var idx := _choice_rows.size()
		_choice_meta.append(row)
		_chosen.append(str(opts[def_idx].get("id", "")))

		# 行题一行（整行宽放得下「索赎（放回 12 人，当场折价兑付）」这样的长短）
		var lbl := Label.new()
		lbl.text = str(row.get("label", ""))
		lbl.clip_text = false
		lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		lbl.add_theme_font_override("font", UiTheme.font())
		lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY + 2)
		lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		vb.add_child(lbl)

		# 选项钮一行（靠右），按钮宽按字数估，触屏点得着
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_END
		hb.add_theme_constant_override("separation", 10)
		_choice_rows.append(hb)
		for j in opts.size():
			var b := Button.new()
			b.text = str(opts[j].get("label", ""))
			b.custom_minimum_size = Vector2(minf(120.0, 28.0 + float(str(opts[j].get("label", "")).length()) * 20.0), 36)
			b.add_theme_font_override("font", UiTheme.font())
			b.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
			var opt_id := str(opts[j].get("id", ""))
			b.pressed.connect(_on_choice_press.bind(idx, opt_id))
			hb.add_child(b)
		vb.add_child(hb)
		_paint_row(idx)

	var sep := HSeparator.new()
	vb.add_child(sep)

	_choice_done_btn = Button.new()
	_choice_done_btn.text = "收拾停当　（Enter）"
	_choice_done_btn.custom_minimum_size = Vector2(200, 44)
	_choice_done_btn.add_theme_font_override("font", UiTheme.title_font())
	_choice_done_btn.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY + 2)
	_choice_done_btn.pressed.connect(_on_choice_done)
	vb.add_child(_choice_done_btn)
	# 尾钮贴底多留条垫，字别贴边
	var tail_pad := Control.new()
	tail_pad.custom_minimum_size = Vector2(0, 6)
	vb.add_child(tail_pad)
	# 卡片本体按内容反推尺寸，底沿贴画布底留一缝；宽度取「最长行题」与画布折中
	await get_tree().process_frame
	var cv := Kit.canvas_size(self)
	var want := vb.get_combined_minimum_size() + Vector2(32, 20)
	# 行题按最长那行估（SIZE_BODY+2 × 字宽 ≈ ×0.62），放画布宽对折到九成之间
	var row_need := 0.0
	for i in range(_choice_meta.size()):
		var lbl_text := str(_choice_meta[i].get("label", ""))
		row_need = maxf(row_need, float(lbl_text.length()) * (float(UiTheme.SIZE_BODY + 2) * 0.62))
	var take_x := clampf(maxf(want.x, row_need + 60.0), 480.0, cv.x * 0.90)
	_choice_panel.size = Vector2(take_x, want.y)
	_choice_panel.position = Vector2(cv.x * 0.5 - take_x * 0.5,
		cv.y - _choice_panel.size.y - CHOICE_BOTTOM_MARGIN)
	_choice_done_btn.grab_focus()


## 换一行里高亮的选项（按下的钮松开焦，重描该行各钮的底色）
func _on_choice_press(idx: int, opt_id: String) -> void:
	if idx < 0 or idx >= _chosen.size():
		return
	_chosen[idx] = opt_id
	_paint_row(idx)


## 该行各钮按选没选上描底色（选中 = 泥金题签那一路的亮底，未选 = 照旧）
func _paint_row(idx: int) -> void:
	if idx < 0 or idx >= _choice_rows.size():
		return
	var hb: HBoxContainer = _choice_rows[idx]
	for i in range(1, hb.get_child_count()):
		var b := hb.get_child(i) as Button
		if b == null:
			continue
		var opt_id := ""  # bind 的次序 = 选项次序：第 1 个 Button 起
		# b 的选项 id 反查（按 _choice_rows 里 bind 的次序重建）
		var opts = _choice_opts(idx)
		var j := i - 1
		if j >= 0 and j < opts.size():
			opt_id = str(opts[j].get("id", ""))
		var on := opt_id == str(_chosen[idx])
		b.modulate = Color(1.0, 0.95, 0.75) if on else Color(0.82, 0.78, 0.70)
		b.disabled = false


## 卡上第 idx 行的 options 数组（_build 挂卡时存下，择项描色反查用）
func _choice_opts(idx: int) -> Array:
	if idx < 0 or idx >= _choice_meta.size():
		return []
	var o = (_choice_meta[idx] as Dictionary).get("options", [])
	return o if o is Array else []


## Enter 或尾钮：回填 callback 并揭卡收尾
func _on_choice_done() -> void:
	if _done:
		return
	_choice_swallow = false
	var out := {}
	for i in range(_choice_meta.size()):
		out[str(_choice_meta[i].get("key", ""))] = str(_chosen[i])
	if _choice_callback.is_valid():
		_choice_callback.call(out)
	_finish()


## 键盘：Enter / KP Enter 按尾钮；左右在同行的选项间跳；上下换行（触鼠之外给键盘一条通路）
func _input_choice(event: InputEvent) -> bool:
	if _choice_panel == null or not is_instance_valid(_choice_panel):
		return false
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var kc := (event as InputEventKey).keycode
	if kc == KEY_ENTER or kc == KEY_KP_ENTER:
		_on_choice_done()
		return true
	return false


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func play_enter(p_title: String, p_subtitle := "") -> void:
	_start(p_title, p_subtitle, SEAL_ENTER)
	var id := _run_id
	if not await _bars_in(id):
		return
	await _hold_and_open(id)


func play_exit(p_title: String, p_subtitle := "", on_black := Callable()) -> void:
	_start(p_title, p_subtitle, seal_for(p_title), act_key(p_title) in OUTCOME_SOMBER)
	_on_black = on_black
	var id := _run_id
	if not await _bars_in(id):
		return
	if not _on_black.is_valid():
		await _hold_and_open(id)
		return
	if not await _hold(id):
		return
	_swallow = true
	var half := Kit.canvas_size(self).y * 0.5
	_tween = create_tween()
	_tween.tween_property(_clip, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.tween_property(_top, "size:y", half + 1.0, T_SHUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_bottom, "size:y", half + 1.0, T_SHUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_bottom, "position:y", half - 1.0, T_SHUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_top_line, "modulate:a", 0.0, T_SHUT)
	_tween.parallel().tween_property(_bottom_line, "modulate:a", 0.0, T_SHUT)
	if not await _await_tween(id):
		return
	_black()
	# 换场景那一帧常卡一下，停两帧再揭，揭开就是新页
	if not await _await_frame(id) or not await _await_frame(id):
		return
	_tween = create_tween()
	_tween.tween_property(_top, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "position:y", half * 2.0, T_BAR_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not await _await_tween(id):
		return
	_swallow = false
	_finish()


## 当前单边墨边高（探针量排版用）
func bar_height() -> float:
	return roundf(Kit.canvas_size(self).y * BAR_FRAC)


## 题签整行在画布上的矩形（探针量是否落在下边里）
func caption_rect() -> Rect2:
	return Rect2(_clip.position + _caption.position, _caption.size)


func _build() -> void:
	if _built:
		return
	_built = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_top = _bar()
	_bottom = _bar()
	# 墨边内沿一道泥金细线，压在画面与墨边交界上
	_top_line = _hairline()
	_bottom_line = _hairline()

	_caption = HBoxContainer.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.alignment = BoxContainer.ALIGNMENT_BEGIN
	_caption.add_theme_constant_override("separation", 18)

	_seal = Label.new()
	_seal.add_theme_font_override("font", UiTheme.title_font())
	_seal.add_theme_font_size_override("font_size", 22)
	_seal.add_theme_color_override("font_color", UiTheme.SEAL_TEXT)
	_seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seal.custom_minimum_size = Vector2(36, 36)
	_seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.SEAL
	sb.set_corner_radius_all(3)
	_seal.add_theme_stylebox_override("normal", sb)
	_seal.rotation = -0.06
	_caption.add_child(_seal)

	_head = Label.new()
	_head.add_theme_font_override("font", UiTheme.title_font())
	_head.add_theme_font_size_override("font_size", TITLE_SIZE)
	_head.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_child(_head)

	_rule = ColorRect.new()
	_rule.color = UiTheme.GOLD
	_rule.custom_minimum_size = Vector2(1, 30)
	_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_rule)

	_sub = Label.new()
	_sub.add_theme_font_override("font", UiTheme.font())
	_sub.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_sub)

	# 擦出：题签放在裁切框里，框宽 0 → 全宽
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_clip)
	_clip.add_child(_caption)


func _bar() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.INK_SOLID
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


func _hairline() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.GOLD, 0.55)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


## 新的一幕：旧 tween 作废、旧协程按 _run_id 自退，排版从零开始。somber：我方失利的出战，印色与题名压暗。
func _start(p_title: String, p_subtitle: String, p_seal: String, somber := false) -> void:
	_build()
	_run_id += 1
	_cancel_waits()
	_black_done = false
	_done = false
	_on_black = Callable()
	_swallow = false
	title = p_title
	subtitle = p_subtitle
	if seal_text == "":
		seal_text = p_seal
	_head.text = title
	_sub.text = subtitle
	_seal.text = seal_text
	_seal.visible = seal_text != ""
	_rule.visible = subtitle != ""
	_sub.visible = subtitle != ""
	seal_text = ""
	_head.add_theme_color_override("font_color", UiTheme.TEXT_DIM if somber else UiTheme.GOLD_HI)
	var seal_box := _seal.get_theme_stylebox("normal") as StyleBoxFlat
	if seal_box != null:
		seal_box.bg_color = UiTheme.SEAL.darkened(SOMBER_SEAL_DARKEN) if somber else UiTheme.SEAL
	_layout()


func _layout() -> void:
	var cv := Kit.canvas_size(self)
	var h := bar_height()
	_top.position = Vector2.ZERO
	_top.size = Vector2(cv.x, 0.0)
	_bottom.position = Vector2(0.0, cv.y)
	_bottom.size = Vector2(cv.x, 0.0)
	_top_line.size = Vector2(cv.x, 1.0)
	_bottom_line.size = Vector2(cv.x, 1.0)
	_top_line.modulate.a = 0.0
	_bottom_line.modulate.a = 0.0
	_top_line.position = Vector2(0.0, h - 1.0)
	_bottom_line.position = Vector2(0.0, cv.y - h)

	_head.add_theme_font_size_override("font_size", TITLE_SIZE)
	_sub.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_sub.clip_text = false
	_sub.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_sub.custom_minimum_size = Vector2.ZERO
	var sz := _caption.get_combined_minimum_size()
	# 过长的题签不许冲出画布右缘：先缩题名（不小于 22）；还宽就缩副题（不小于脚注字阶），再不够才在副题末尾收「…」。
	# 出战副题 = 日期 + 敌船下场 + 我方折损，原先只缩题名：南岛海道北口外海受降三艘、折水手失船颠落货三段齐写时
	# 题签宽 1324，右沿冲出 1280 画布 116 px，「舱面货十七件」整截看不见
	var room := cv.x - CAPTION_X * 2.0
	if sz.x > room and _head.text.length() > 0:
		_head.add_theme_font_size_override("font_size", maxi(22, int(TITLE_SIZE * room / sz.x)))
		sz = _caption.get_combined_minimum_size()
	if sz.x > room and _sub.visible and _sub.text != "":
		var sub_w := _sub.get_combined_minimum_size().x
		var keep := sz.x - sub_w
		_sub.add_theme_font_size_override("font_size",
			maxi(UiTheme.SIZE_FOOT, int(floor(UiTheme.SIZE_BODY * (room - keep) / maxf(sub_w, 1.0)))))
		sz = _caption.get_combined_minimum_size()
		if sz.x > room:
			_sub.clip_text = true
			_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_sub.custom_minimum_size = Vector2(maxf(0.0, room - keep), 0.0)
			sz = _caption.get_combined_minimum_size()
	_caption.size = sz
	_caption.position = Vector2.ZERO
	# 题签行在下边里垂直居中；阴影与朱印倾斜会被裁，框上下各多留 8
	var y := roundf(cv.y - h + (h - sz.y) * 0.5)
	_clip.position = Vector2(CAPTION_X, y - 8.0)
	_caption.position.y = 8.0
	_clip.size = Vector2(0.0, sz.y + 16.0)
	_clip.set_meta(&"full_w", sz.x + 8.0)
	_clip.modulate.a = 1.0


## 挂起点一：等刚排好的 _tween 放完。醒来本幕还是 id 才返回 true；中途作废返回 false，调用方自退。
func _await_tween(id: int) -> bool:
	if id != _run_id:
		return false
	_wait_seq += 1
	_tween.finished.connect(_wake.bind(_wait_seq), CONNECT_ONE_SHOT)
	waiters += 1
	await _woken
	waiters -= 1
	return id == _run_id


## 挂起点二：等下一帧（同 await get_tree().process_frame 的时机）。已离树或本幕已作废直接返回 false。
func _await_frame(id: int) -> bool:
	if id != _run_id or not is_inside_tree():
		return false
	_wait_seq += 1
	get_tree().process_frame.connect(_wake.bind(_wait_seq), CONNECT_ONE_SHOT)
	waiters += 1
	await _woken
	waiters -= 1
	return id == _run_id


func _wake(seq: int) -> void:
	if seq == _wait_seq:
		_woken.emit()


## 作废本幕的等待（调用方先 _run_id += 1）：kill tween、让还没到的回调过期，并当场唤醒挂着的协程。
## kill 掉的 tween 不发 finished、离树后 process_frame 不再唤醒本节点，不在这里补这一声，协程就永远挂着。
func _cancel_waits() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_wait_seq += 1
	_woken.emit()


## 墨边合拢 + 题签擦出。被新一幕打断时返回 false。
func _bars_in(id: int) -> bool:
	var cv := Kit.canvas_size(self)
	var h := bar_height()
	_tween = create_tween()
	_tween.tween_property(_top, "size:y", h, T_BAR_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "size:y", h, T_BAR_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "position:y", cv.y - h, T_BAR_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_top_line, "modulate:a", 1.0, 0.18)
	_tween.parallel().tween_property(_bottom_line, "modulate:a", 1.0, 0.18)
	_tween.parallel().tween_property(_clip, "size:x", float(_clip.get_meta(&"full_w")), T_WIPE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_caption, "position:x", 0.0, T_WIPE).from(-20.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _sub.visible:
		_sub.modulate.a = 0.0
		_tween.tween_property(_sub, "modulate:a", 1.0, T_SUB)
	if not await _await_tween(id):
		return false
	caption_shown.emit()
	return true


func _hold(id: int) -> bool:
	var left := T_HOLD
	while left > 0.0:
		if not await _await_frame(id):
			return false
		left -= get_process_delta_time()
	return true


func _hold_and_open(id: int) -> void:
	if not await _hold(id):
		return
	var cv := Kit.canvas_size(self)
	_tween = create_tween()
	_tween.tween_property(_clip, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.parallel().tween_property(_top_line, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.parallel().tween_property(_bottom_line, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.tween_property(_top, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_bottom, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_bottom, "position:y", cv.y, T_BAR_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not await _await_tween(id):
		return
	_finish()


## 出战合拢时吞掉键盘与鼠标（B / Esc 不再穿到底下）；入战不拦。
## 挂「战后收拾」卡期间也吞——Enter 只按尾钮、不穿透到海图底栏。
func _input(event: InputEvent) -> void:
	if _swallow and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
		return
	if _choice_swallow:
		if _input_choice(event):
			get_viewport().set_input_as_handled()
			return
		# 卡挂出期间：键盘未消费的键吞掉（海图底栏在卡下，连按不穿透）；
		# 鼠标 / 触屏放行——Button 靠它们，set_input_as_handled 会把钮按住
		if _choice_swallow and event is InputEventKey:
			get_viewport().set_input_as_handled()


func _black() -> void:
	if _black_done:
		return
	_black_done = true
	covered.emit()
	if _on_black.is_valid():
		_on_black.call()


func _abort() -> void:
	remove_from_group(GROUP)
	_run_id += 1
	_cancel_waits()
	# 出战没到全黑就被顶掉：补调 on_black，调用方的换场不丢
	if _on_black.is_valid():
		_black()
	_finish()


## 三条收尾（演完 / _abort / 离树）都走这里：finished 恰好一次，随后自删。
## 已终结的（演完还没真释放，同帧又被 _spawn / 探针收尾扫到再 _abort）在这里挡掉，不再补发。
func _finish(free_self := true) -> void:
	if _done:
		return
	_done = true
	_swallow = false
	finished.emit()
	if free_self and get_meta(&"auto_free", false):
		queue_free()


## 没演完就离树（挂在布景下随布景释放 / 被摘下）不经 _abort，也得发 finished，否则裸 await 的一方永远不醒。
## 不补调 on_black、不发 covered：父都拆了，换场是往拆了的场里调；进度信号只在真演到时发。
## 离了树的节点归让它离树的一方处置（随父释放的已在释放），这里不再 queue_free。
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and not _done:
		_run_id += 1
		_cancel_waits()
		_finish(false)
