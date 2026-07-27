extends Control

@onready var background: TextureRect = $Background
@onready var left_panel: PanelContainer = $HBoxContainer/LeftPanel
@onready var status_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var message_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/MessageLabel

@onready var title_mode: Control = $HBoxContainer/CenterArea/TitleMode
@onready var main_title: Label = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/MainTitle
@onready var sub_title: Label = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/SubTitle
@onready var start_button: Button = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/StartButton

@onready var investigation_mode: PanelContainer = $HBoxContainer/CenterArea/InvestigationMode
@onready var scene_title: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/SceneTitle
@onready var body_text: RichTextLabel = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/BodyText
@onready var interactive_container: HFlowContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/InteractiveContainer
@onready var choices_container: VBoxContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/ChoicesContainer
@onready var choices_label: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/ChoicesLabel

@onready var port_mode: Control = $HBoxContainer/CenterArea/PortMode
@onready var left_facilities: VBoxContainer = $HBoxContainer/CenterArea/PortMode/LeftFacilities
@onready var right_facilities: VBoxContainer = $HBoxContainer/CenterArea/PortMode/RightFacilities
@onready var port_title: Label = $HBoxContainer/CenterArea/PortMode/PortTitle

@onready var npc_mode: Control = $HBoxContainer/CenterArea/NPCMode
@onready var npc_name_lbl: Label = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCName
@onready var npc_dialog_lbl: RichTextLabel = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCDialog
@onready var npc_actions: VBoxContainer = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCActions
@onready var npc_portrait: TextureRect = $HBoxContainer/CenterArea/NPCMode/HBox/PortraitRect

var current_scene_id: String = ""
var previous_scene_id: String = ""  # 死胡同场景兜底用：只记一层，不做完整历史栈
var title_button_connected: bool = false

const FACILITY_SUFFIXES := ["_market", "_yamen", "_shipyard", "_tavern", "_inn"]

## 无剧情场景的港口使用的通用设施
const GENERIC_FACILITIES := [
	{"id": "city_market", "title": "牙行", "subtitle": "货殖交易"},
	{"id": "city_shipyard", "title": "船屋", "subtitle": "修船・补给・船行"},
	{"id": "city_yamen", "title": "市舶司", "subtitle": "验引・抽解"},
	{"id": "city_tavern", "title": "酒馆", "subtitle": "打听消息"},
	{"id": "city_inn", "title": "旅店", "subtitle": "歇息・候风"},
]


func _ready() -> void:
	message_label.text = ""
	GameManager.monthly_notice.connect(_on_monthly_notice)
	update_status_panel()
	call_deferred("start_game")


func _on_monthly_notice(text: String) -> void:
	log_msg(text)
	update_status_panel()


func start_game() -> void:
	if GameState.has_flag("return_to_port"):
		GameState.flags.erase("return_to_port")
		load_scene(GameState.last_port)
	else:
		var start_id = GameManager.scenes_data.get("start_scene", "cg_title")
		load_scene(start_id)


func log_msg(text: String) -> void:
	message_label.text = text + "\n\n" + message_label.text


# ══════════════════════════════════════════════════════
#  状态面板
# ══════════════════════════════════════════════════════

func update_status_panel() -> void:
	var cargo_str := ""
	if Fleet.cargo.is_empty():
		cargo_str = "空\n"
	else:
		for gid in Fleet.cargo.keys():
			var e: Dictionary = Fleet.cargo[gid]
			cargo_str += "%s ×%d\n" % [GameManager.get_good_name(gid), e.get("qty", 0)]

	var cap_used := Fleet.used_capacity()
	var cap_total := Fleet.total_capacity()
	var supply_d := Fleet.supply_days()
	var supply_color := "white"
	if supply_d <= 3:
		supply_color = "red"
	elif supply_d <= 7:
		supply_color = "yellow"

	var permit_str := "【有】合法" if GameState.has_customs_permit else "【无】黑市"
	var contraband := GameState.contraband_units()

	var t := "[b]%s[/b]\n%s\n\n" % [Calendar.get_date_string(), Calendar.get_monsoon_desc()]
	t += "金钱：%d\n" % GameState.money
	if GameState.debt > 0:
		t += "[color=orange]欠债：%d[/color]\n" % GameState.debt
	t += "名声：%d\n\n" % GameState.fame
	t += "[u]舰队[/u]\n船数：%d　水手：%d\n舱位：%d / %d 料\n耐久：%d / %d\n士气：%d\n" % [
		Fleet.ships.size(), Fleet.total_crew(),
		int(cap_used), int(cap_total),
		int(Fleet.total_durability()), int(Fleet.total_max_durability()),
		Fleet.morale,
	]
	t += "水：%d　粮：%d　[color=%s]（足 %d 日）[/color]\n" % [Fleet.water, Fleet.food, supply_color, supply_d]

	if not Crew.hired.is_empty():
		t += "\n[u]职事[/u]\n"
		for c in Crew.roster():
			t += "%s %s%s\n" % [
				Crew.role_def(c.get("role", "")).get("name", ""),
				c.get("name", ""), _stars(int(c.get("level", 1))),
			]
		var wage := Crew.monthly_wage()
		var wage_color := "orange" if Crew.unpaid_months > 0 else "white"
		t += "[color=%s]月俸共 %d" % [wage_color, wage]
		if Crew.unpaid_months > 0:
			t += "　已欠 %d 月" % Crew.unpaid_months
		t += "[/color]\n"
	t += "\n"
	t += "[u]市舶[/u]\n蒲氏关注：%d\n货引：%s\n" % [GameState.pu_attention, permit_str]
	if contraband > 0:
		t += "[color=orange]舱底违禁：%d 件[/color]\n" % contraband
	t += "\n[u]船舱[/u]\n%s" % cargo_str

	# 章节目标：不写出来玩家不会知道怎样才能开出下一片海
	var prog := GameState.chapter_progress()
	t += "\n[u]第%s章・%s[/u]\n" % [
		_cn_chapter(GameState.chapter), GameState.chapter_def().get("name", ""),
	]
	if prog.get("final", false):
		t += "[color=gray]已至最后一章[/color]\n"
	else:
		for it in prog.get("items", []):
			var mark: String = "[color=lime]✓[/color]" if it["done"] else "・"
			if int(it["need"]) > 1:
				t += "%s %s %d/%d\n" % [mark, it["label"], it["current"], it["need"]]
			else:
				t += "%s %s\n" % [mark, it["label"]]

	status_label.text = t


# ══════════════════════════════════════════════════════
#  场景加载
# ══════════════════════════════════════════════════════

func load_scene(scene_id: String) -> void:
	if current_scene_id != "" and current_scene_id != scene_id:
		previous_scene_id = current_scene_id
	current_scene_id = scene_id

	# 设施场景由代码动态生成，不走 scenes.json
	for suffix in FACILITY_SUFFIXES:
		if scene_id.ends_with(suffix):
			_setup_dynamic_scene(scene_id, suffix)
			return

	var scene_data = GameManager.get_scene_by_id(scene_id)
	if scene_data.is_empty():
		# scenes.json 只为少数港口写了剧情场景；其余按 ports.json 生成通用港口界面
		var pdef := GameManager.get_port_by_id(scene_id)
		if not pdef.is_empty():
			GameState.last_port = scene_id
			_apply_background("port", scene_id)
			_setup_port_mode({
				"title": pdef.get("name", scene_id),
				"facilities": GENERIC_FACILITIES,
			})
			_on_enter_port(scene_id)
			return
		_setup_missing_scene(scene_id)
		return

	var type = scene_data.get("type", "scene")
	var loc = scene_data.get("location", "")
	_apply_background(type, loc)

	if type == "title":
		_setup_title_mode(scene_data)
	elif type == "port":
		GameState.last_port = scene_id
		_setup_port_mode(scene_data)
		_on_enter_port(scene_id)
	else:
		_setup_investigation_mode(scene_data)


## 港口 → 背景图
const PORT_BG := {
	"quanzhou": "bg_quanzhou_harbor.jpg",
	"xinghua": "bg_xinghua_study.jpg",
	"xinghua_harbor": "bg_xinghua_harbor.jpg",
	"fuzhou": "bg_fuzhou_yamen.jpg",
	"hakata": "bg_arab_mosque.jpg",
	"ryukyu": "bg_reef_bay.jpg",
	"penghu": "bg_reef_bay.jpg",
	"kagoshima": "bg_beacon_tower.jpg",
	"champa": "bg_temple_gate.jpg",
	"guangzhou": "bg_arab_mosque.jpg",
}

## 设施后缀 → 背景图
const FACILITY_BG := {
	"_market": "bg_yahang.jpg",
	"_shipyard": "bg_shipyard.jpg",
	"_yamen": "bg_customs_room.jpg",
	"_tavern": "bg_xinghua_wine_shed.jpg",
}


func _apply_background(type: String, loc: String) -> void:
	var file := "bg_sea_route.jpg"
	if type == "title":
		file = "bg_world_map.jpg"
	elif PORT_BG.has(loc):
		file = PORT_BG[loc]
	_set_background_file(file)


func _set_background_file(file_name: String) -> void:
	var tex := GameManager.load_texture("res://assets/" + file_name)
	if tex != null:
		background.texture = tex


func _enter_panel_mode() -> void:
	left_panel.visible = true
	title_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	investigation_mode.visible = true
	for child in interactive_container.get_children():
		child.queue_free()
	for child in choices_container.get_children():
		child.queue_free()
	choices_label.visible = false
	choices_label.text = "请选择"  # 市场会改写它，此处复位避免上一屏文字残留


## 剧情设施尚未实装时的占位文案，比「施工中」更不出戏
const FACILITY_PLACEHOLDER := {
	"city_exam": {
		"title": "贡院",
		"body": "贡院朱门紧闭。今科未开，阶下只有几个背着书箧的士子在张望。\n你想起叔父留下的那笔债，又摸了摸袖中那份还没押字的货单——科举与海路，眼下还容不得你两头都要。",
	},
	"city_guild": {
		"title": "行会",
		"body": "行首正与几名蕃商核对舱位与脚钱。见你进来，只抬了抬眼皮。\n（行会事务尚未实装。）",
	},
	"city_residence": {
		"title": "住处",
		"body": "一间租来的下处，屋角堆着几卷未拆的旧账。\n（住处事务尚未实装。）",
	},
}


func _setup_missing_scene(scene_id: String) -> void:
	_enter_panel_mode()
	if FACILITY_PLACEHOLDER.has(scene_id):
		var ph: Dictionary = FACILITY_PLACEHOLDER[scene_id]
		scene_title.text = ph.get("title", scene_id)
		body_text.text = ph.get("body", "")
	else:
		scene_title.text = "区域施工中..."
		body_text.text = "该区域（" + scene_id + "）尚未实装，请耐心等待后续版本更新。"

	var base_loc = GameState.last_port
	if base_loc == "" or base_loc == scene_id:
		base_loc = "quanzhou" if scene_id.begins_with("quanzhou") else "xinghua"
	_add_leave_button(base_loc)


# ══════════════════════════════════════════════════════
#  设施：牙行 / 市舶司 / 船屋 / 酒馆
# ══════════════════════════════════════════════════════

func _setup_dynamic_scene(scene_id: String, suffix: String) -> void:
	_enter_panel_mode()
	var base_loc := scene_id.trim_suffix(suffix)
	if FACILITY_BG.has(suffix):
		_set_background_file(FACILITY_BG[suffix])

	match suffix:
		"_market":
			_setup_market(base_loc)
		"_tavern":
			_setup_tavern(base_loc)
		"_yamen":
			_setup_yamen(base_loc)
		"_shipyard":
			_setup_shipyard(base_loc)
		"_inn":
			_setup_inn(base_loc)


# ── 牙行（市场）─────────────────────────────────────

func _setup_market(port_id: String) -> void:
	scene_title.text = "%s・牙行" % GameManager.get_port_name(port_id)
	body_text.text = "牙行里挤着各色商人，没有人说官话，只用手势、算筹和一把碎银落地就要捡的速度说话。"

	var goods_ids: Array = Economy.goods_at(port_id)
	if goods_ids.is_empty():
		body_text.text += "\n\n此地并无正经牙行，只有几个渔妇在晒网。"
		_add_leave_button(port_id)
		return

	# 按买价排序，便宜的在前
	goods_ids.sort_custom(func(a, b): return Economy.buy_price(port_id, a) < Economy.buy_price(port_id, b))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	choices_container.add_child(scroll)

	for gid in goods_ids:
		rows.add_child(_make_market_row(port_id, gid))

	choices_label.visible = true
	choices_label.text = "── 舱位 %d / %d 料 ──" % [int(Fleet.used_capacity()), int(Fleet.total_capacity())]
	_add_leave_button(port_id)


func _make_market_row(port_id: String, good_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var g := GameManager.get_good_by_id(good_id)
	var buy_p := Economy.buy_price(port_id, good_id)
	var sell_p := Economy.sell_price(port_id, good_id)
	var held := Fleet.cargo_qty(good_id)
	var role := Economy.get_role(port_id, good_id)

	var name_lbl := Label.new()
	name_lbl.text = g.get("name", good_id)
	name_lbl.custom_minimum_size = Vector2(88, 0)
	if g.get("contraband", false):
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
		name_lbl.tooltip_text = "违禁：宋法不许出海，验引护不住"
	row.add_child(name_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text = Economy.price_hint(port_id, good_id)
	hint_lbl.custom_minimum_size = Vector2(120, 0)
	hint_lbl.add_theme_font_size_override("font_size", 13)
	if role == "origin":
		hint_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	elif role == "consumer":
		hint_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	row.add_child(hint_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "买%d 卖%d" % [buy_p, sell_p]
	price_lbl.custom_minimum_size = Vector2(110, 0)
	row.add_child(price_lbl)

	var held_lbl := Label.new()
	held_lbl.text = "舱%d" % held
	held_lbl.custom_minimum_size = Vector2(52, 0)
	held_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(held_lbl)

	for n in [1, 10]:
		var b := Button.new()
		b.text = "买%d" % n
		b.pressed.connect(_on_buy.bind(port_id, good_id, n))
		row.add_child(b)

	var bmax := Button.new()
	bmax.text = "买满"
	bmax.pressed.connect(_on_buy_max.bind(port_id, good_id))
	row.add_child(bmax)

	for n in [1, 10]:
		var s := Button.new()
		s.text = "卖%d" % n
		s.disabled = held < n
		s.pressed.connect(_on_sell.bind(port_id, good_id, n))
		row.add_child(s)

	var sall := Button.new()
	sall.text = "全卖"
	sall.disabled = held <= 0
	sall.pressed.connect(_on_sell.bind(port_id, good_id, held))
	row.add_child(sall)

	return row


func _on_buy(port_id: String, good_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var loadable := Fleet.max_loadable(good_id)
	if loadable <= 0:
		log_msg("【舱满】再塞不下了。得先卖掉些货，或者换条大船。")
		return
	var actual := mini(amount, loadable)
	var cost := Economy.estimate_buy_cost(port_id, good_id, actual)
	if GameState.money < cost:
		# 按现有钱数尽量买
		var affordable := actual
		while affordable > 0 and Economy.estimate_buy_cost(port_id, good_id, affordable) > GameState.money:
			affordable -= 1
		if affordable <= 0:
			log_msg("【钱不够】牙人翻了翻眼皮，把货单收了回去。")
			return
		actual = affordable
		cost = Economy.estimate_buy_cost(port_id, good_id, actual)

	GameState.spend_money(cost)
	Fleet.add_cargo(good_id, actual, float(cost) / float(actual))
	Economy.apply_buy_impact(port_id, good_id, actual)

	var note := ""
	if actual < amount:
		note = "（只购得 %d）" % actual
	log_msg("买入 %s ×%d，付 %d 钱。%s" % [GameManager.get_good_name(good_id), actual, cost, note])
	load_scene(current_scene_id)


func _on_buy_max(port_id: String, good_id: String) -> void:
	var by_hold := Fleet.max_loadable(good_id)
	if by_hold <= 0:
		log_msg("【舱满】再塞不下了。")
		return
	var n := by_hold
	while n > 0 and Economy.estimate_buy_cost(port_id, good_id, n) > GameState.money:
		n -= 1
	if n <= 0:
		log_msg("【钱不够】连一件也买不起。")
		return
	_on_buy(port_id, good_id, n)


func _on_sell(port_id: String, good_id: String, amount: int) -> void:
	var held := Fleet.cargo_qty(good_id)
	var actual := mini(amount, held)
	if actual <= 0:
		return
	var revenue := Economy.estimate_sell_revenue(port_id, good_id, actual)
	var cost_basis := Fleet.cargo_cost(good_id) * actual

	Fleet.remove_cargo(good_id, actual)
	GameState.add_money(revenue)
	Economy.apply_sell_impact(port_id, good_id, actual)

	var profit := revenue - int(round(cost_basis))
	var profit_str := "赚 %d" % profit if profit >= 0 else "亏 %d" % (-profit)
	log_msg("卖出 %s ×%d，得 %d 钱（%s）。" % [GameManager.get_good_name(good_id), actual, revenue, profit_str])
	load_scene(current_scene_id)


# ── 市舶司 ──────────────────────────────────────────

func _setup_yamen(port_id: String) -> void:
	scene_title.text = "%s・市舶司" % GameManager.get_port_name(port_id)
	body_text.text = "官府重地。几名差役正在慵懒地打瞌睡，案上压着一摞未及批的货单。"

	_add_npc_button("customs_official", "市舶司小吏")

	var duty := GameState.customs_duty()
	var contraband := GameState.contraband_units()

	if GameState.has_customs_permit:
		var info := Label.new()
		info.text = "货引已在手，本次出港可合法验放。"
		info.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		choices_container.add_child(info)
	else:
		var btn := Button.new()
		btn.text = "【正规】按舱货抽解，请领货引（%d 钱）" % duty
		btn.pressed.connect(func():
			var res: Dictionary = GameState.apply_for_permit()
			log_msg(res["msg"])
			load_scene(current_scene_id)
		)
		choices_container.add_child(btn)

	if contraband > 0:
		var warn := Label.new()
		warn.text = "舱底尚有违禁 %d 件——报不进明账，验引也遮不住。" % contraband
		warn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choices_container.add_child(warn)

	_setup_reporting()

	var att := Label.new()
	att.text = "蒲氏关注度 %d　%s" % [GameState.pu_attention, _attention_desc()]
	att.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(att)

	choices_label.visible = true
	_add_leave_button(port_id)


## 上报发现：航中勘见的东西要回衙门报了才换得赏格与名声
func _setup_reporting() -> void:
	var pending := GameState.unreported_discoveries()
	if pending.is_empty():
		return

	var sep := Label.new()
	sep.text = "── 呈报所见 ──"
	sep.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(sep)

	for did in pending:
		var d := GameManager.get_discovery_by_id(did)
		if d.is_empty():
			continue
		var value: int = int(d.get("value", 50))
		var btn := Button.new()
		btn.text = "呈报「%s」　赏格 %d 钱・名声 +%d" % [
			d.get("name", did), value, maxi(1, value / 10),
		]
		btn.tooltip_text = "%s\n%s" % [d.get("location", ""), d.get("historical_hook", "")]
		btn.pressed.connect(func():
			var res: Dictionary = GameState.report_discovery(did)
			if not res.is_empty():
				log_msg("【呈报】%s 录入案册，赏钱 %d，名声 +%d。" % [
					res["name"], res["gold"], res["fame"],
				])
			load_scene(current_scene_id)
		)
		choices_container.add_child(btn)


func _attention_desc() -> String:
	var a := GameState.pu_attention
	if a >= 70:
		return "（暗桩已盯死，出港必查）"
	elif a >= 50:
		return "（蒲氏起了疑心）"
	elif a >= 25:
		return "（偶有闲话传出）"
	return "（尚无人留意）"


# ── 船屋 ────────────────────────────────────────────

func _setup_shipyard(port_id: String) -> void:
	scene_title.text = "%s・船屋" % GameManager.get_port_name(port_id)
	body_text.text = "船坞里散发着桐油与海水的味道。这是修补海船、补充水手与水粮的地方。"

	# 补给
	var grain_price := Economy.buy_price(port_id, "grain") if Economy.is_traded(port_id, "grain") else 12
	var water_price := 1

	var supply_lbl := Label.new()
	supply_lbl.text = "── 补给（水 %d钱/份，粮 %d钱/份；一份供两人一日，现每日耗 %d 份）──" % [
		water_price, grain_price, Fleet.daily_supply_use(),
	]
	supply_lbl.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(supply_lbl)

	for n in [30, 100]:
		var b := Button.new()
		b.text = "补水粮各 %d 份（%d 钱）" % [n, n * (water_price + grain_price)]
		b.pressed.connect(_on_buy_supplies.bind(n, water_price, grain_price))
		choices_container.add_child(b)

	# 修船
	var rc := Fleet.repair_cost()
	if rc > 0:
		var rb := Button.new()
		rb.text = "修补船体（%d 钱）" % rc
		rb.pressed.connect(func():
			if GameState.spend_money(rc):
				Fleet.repair_all()
				log_msg("船匠敲打了整整一日，船体修复如初。")
			else:
				log_msg("【钱不够】船匠摇摇头，把凿子收了。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(rb)

	# 雇水手
	var room := Fleet.crew_max() - Fleet.total_crew()
	if room > 0:
		var hire_n: int = mini(10, room)
		var hire_cost := hire_n * 20
		var hb := Button.new()
		hb.text = "雇水手 %d 人（%d 钱，可容 %d）" % [hire_n, hire_cost, room]
		hb.pressed.connect(func():
			if GameState.spend_money(hire_cost):
				var got: int = Fleet.hire_crew(hire_n)
				log_msg("码头上招了 %d 个水手。" % got)
			else:
				log_msg("【钱不够】没人肯赊帐上船。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(hb)

	# 赊贷：本钱被查扣清空后仍有翻身的路
	var loan_lbl := Label.new()
	loan_lbl.text = "── 蕃商赊贷（月息 %d%%，上限 %d）──" % [
		int(GameState.DEBT_MONTHLY_RATE * 100), GameState.DEBT_CEILING,
	]
	loan_lbl.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(loan_lbl)

	if GameState.debt > 0:
		var debt_lbl := Label.new()
		debt_lbl.text = "现欠蕃商 %d 钱，每月生息 %d。" % [
			GameState.debt, int(ceil(GameState.debt * GameState.DEBT_MONTHLY_RATE)),
		]
		debt_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
		choices_container.add_child(debt_lbl)

	var limit := GameState.borrow_limit()
	for amt in [500, 2000]:
		if amt > limit:
			continue
		var bb := Button.new()
		bb.text = "赊借 %d 钱" % amt
		bb.pressed.connect(func():
			if GameState.borrow(amt):
				log_msg("蕃商掂了掂你的船和名声，点了头。赊得 %d 钱，月息 %d%%。" % [
					amt, int(GameState.DEBT_MONTHLY_RATE * 100),
				])
			load_scene(current_scene_id)
		)
		choices_container.add_child(bb)

	if GameState.debt > 0 and GameState.money > 0:
		var rb2 := Button.new()
		var pay: int = mini(GameState.debt, GameState.money)
		rb2.text = "还债 %d 钱" % pay
		rb2.pressed.connect(func():
			var paid: int = GameState.repay(pay)
			log_msg("还了 %d 钱，尚欠 %d。" % [paid, GameState.debt])
			load_scene(current_scene_id)
		)
		choices_container.add_child(rb2)

	# 买船
	var ship_lbl := Label.new()
	ship_lbl.text = "── 船行 ──"
	ship_lbl.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(ship_lbl)

	for s in GameManager.ships_data.get("ships", []):
		if not GameState.is_chapter_reached(s.get("unlock", "ch1")):
			continue
		var sb := Button.new()
		sb.text = "购入 %s　载 %d 料・水手 %d-%d・耐久 %d　%d 钱" % [
			s.get("name", "?"), s.get("capacity", 0),
			s.get("crew_min", 0), s.get("crew_max", 0),
			s.get("durability", 0), s.get("price", 0),
		]
		sb.tooltip_text = s.get("historical_note", "")
		var price: int = s.get("price", 0)
		var tid: String = s.get("id", "")
		sb.pressed.connect(func():
			if GameState.spend_money(price):
				Fleet.add_ship(tid)
				log_msg("买下一条%s，泊在船坞外侧。记得雇足水手才好出海。" % s.get("name", "船"))
			else:
				log_msg("【钱不够】船行掌柜笑而不语。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(sb)

	choices_label.visible = true
	_add_leave_button(port_id)


func _on_buy_supplies(n: int, wp: int, gp: int) -> void:
	var cost := n * (wp + gp)
	var need_space := float(n * 2) * Fleet.SUPPLY_BULK
	if Fleet.free_capacity() < need_space:
		log_msg("【舱满】水粮也要占舱位，还差 %d 料。" % int(ceil(need_space - Fleet.free_capacity())))
		return
	if not GameState.spend_money(cost):
		log_msg("【钱不够】买不起这许多水粮。")
		return
	Fleet.water += n
	Fleet.food += n
	log_msg("补入水 %d 份、粮 %d 份，付 %d 钱。现可支撑 %d 日。" % [n, n, cost, Fleet.supply_days()])
	load_scene(current_scene_id)


# ── 酒馆 ────────────────────────────────────────────

func _setup_tavern(port_id: String) -> void:
	scene_title.text = "%s・酒馆" % GameManager.get_port_name(port_id)
	body_text.text = "这里充斥着劣质酒水的味道和水手们的大声喧哗。"

	if port_id.begins_with("quanzhou"):
		_add_npc_button("merchant_lin", "林阿舶")
	elif port_id.begins_with("ryukyu"):
		_add_npc_button("pilot_ana", "阿那")

	# 打听行情：给出邻近港口的一条真实价差情报
	var intel := Button.new()
	intel.text = "打听行情（费 1 日）"
	intel.pressed.connect(func():
		GameManager.advance_days(1)
		log_msg(_gather_price_intel(port_id))
		load_scene(current_scene_id)
	)
	choices_container.add_child(intel)

	_setup_hiring(port_id)

	choices_label.visible = true
	_add_leave_button(port_id)


## 酒馆募人。每种职事至多一人，故已雇之职不再列出候选。
func _setup_hiring(port_id: String) -> void:
	var sep := Label.new()
	sep.text = "── 募人（月俸按月支给，欠饷三月则去）──"
	sep.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(sep)

	# 在船的人
	if not Crew.hired.is_empty():
		for c in Crew.roster():
			var row := HBoxContainer.new()
			var lbl := Label.new()
			var rname: String = Crew.role_def(c.get("role", "")).get("name", "")
			lbl.text = "在船：%s（%s %s）月俸 %d" % [
				c.get("name", ""), rname, _stars(int(c.get("level", 1))), c.get("wage", 0),
			]
			lbl.custom_minimum_size = Vector2(400, 0)
			lbl.add_theme_color_override("font_color", Color(0.65, 0.9, 0.7))
			row.add_child(lbl)

			var d := Button.new()
			d.text = "辞退"
			var rid: String = c.get("role", "")
			d.pressed.connect(func():
				var res: Dictionary = Crew.dismiss(rid)
				if res.get("ok", false):
					log_msg(res["msg"])
				load_scene(current_scene_id)
			)
			row.add_child(d)
			choices_container.add_child(row)

	var cands := Crew.candidates_at(port_id)
	if cands.is_empty():
		var none := Label.new()
		none.text = "此处无人可用。"
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		choices_container.add_child(none)
		return

	for c in cands:
		var cid: String = c.get("id", "")
		var role: Dictionary = Crew.role_def(c.get("role", ""))
		var btn := Button.new()
		btn.text = "雇 %s　%s %s　入伙 %d・月俸 %d" % [
			c.get("name", ""), role.get("name", ""), _stars(int(c.get("level", 1))),
			Crew.signing_fee(cid), c.get("wage", 0),
		]
		btn.tooltip_text = "%s\n\n%s\n%s" % [
			c.get("bio", ""), role.get("desc", ""), role.get("effect_hint", ""),
		]
		btn.pressed.connect(func():
			var res: Dictionary = Crew.hire(cid)
			log_msg(res["msg"])
			load_scene(current_scene_id)
		)
		choices_container.add_child(btn)


func _stars(n: int) -> String:
	return "★".repeat(maxi(0, n))


## 旅店：候风。季风按月转向，等到对的月份再发舶是这个游戏最要紧的判断之一。
func _setup_inn(port_id: String) -> void:
	scene_title.text = "%s・旅店" % GameManager.get_port_name(port_id)
	body_text.text = "临街的通铺，草席上还留着上一个客人的潮气。掌柜说，风信不对的时候，港里泰半的海商都在这儿耗着。"

	var info := Label.new()
	info.text = "眼下：%s，%s" % [Calendar.get_date_string(), Calendar.get_monsoon_desc()]
	choices_container.add_child(info)

	var forecast := Label.new()
	forecast.text = _monsoon_forecast()
	forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast.add_theme_font_size_override("font_size", 13)
	forecast.add_theme_color_override("font_color", Color(0.8, 0.85, 0.7))
	choices_container.add_child(forecast)

	for n in [1, 10]:
		var b := Button.new()
		b.text = "歇 %d 日（%d 钱）" % [n, n * INN_RATE]
		b.pressed.connect(_on_rest.bind(n, port_id))
		choices_container.add_child(b)

	# 候风：睡到下月初一，季风可能已转向
	var to_next: int = Calendar.DAYS_PER_MONTH - Calendar.day + 1
	var nb := Button.new()
	nb.text = "候至下月初一（%d 日，%d 钱）" % [to_next, to_next * INN_RATE]
	nb.pressed.connect(_on_rest.bind(to_next, port_id))
	choices_container.add_child(nb)

	choices_label.visible = true
	_add_leave_button(port_id)


const INN_RATE := 15


## 提示下一次季风转向还有多久
func _monsoon_forecast() -> String:
	var cur := Calendar.get_monsoon()
	var m: int = Calendar.month
	var d: int = Calendar.day
	var days := 0
	for i in range(1, 366):
		var mm: int = m
		var dd: int = d + i
		while dd > Calendar.DAYS_PER_MONTH:
			dd -= Calendar.DAYS_PER_MONTH
			mm += 1
			if mm > Calendar.MONTHS_PER_YEAR:
				mm = 1
		var next_monsoon: int
		if mm >= 10 or mm <= 2:
			next_monsoon = Calendar.Monsoon.NORTHEAST
		elif mm >= 5 and mm <= 8:
			next_monsoon = Calendar.Monsoon.SOUTHWEST
		else:
			next_monsoon = Calendar.Monsoon.TRANSITION
		if next_monsoon != cur:
			days = i
			break
	if days == 0:
		return ""
	return "掌柜掐指算了算：约 %d 日后风信要转。北上博多、高丽须候西南风（五至八月），南下流求、南洋须候东北风（十月至次年二月）。" % days


func _on_rest(days: int, port_id: String) -> void:
	var cost := days * INN_RATE
	if not GameState.spend_money(cost):
		log_msg("【钱不够】掌柜把算盘一推：「客官，先结了前帐罢。」")
		return
	GameManager.advance_days(days)
	Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + days * 2)
	log_msg("在店中歇了 %d 日，付房钱 %d。如今是 %s，%s。" % [
		days, cost, Calendar.get_date_string(), Calendar.get_monsoon_desc(),
	])
	load_scene(current_scene_id)


## 在已解锁港口中找一条真实存在的价差，作为情报吐给玩家
func _gather_price_intel(port_id: String) -> String:
	var best := {"profit": 0}
	for p in GameManager.unlocked_ports():
		var pid: String = p.get("id", "")
		if pid == port_id:
			continue
		for gid in Economy.goods_at(port_id):
			if not Economy.is_traded(pid, gid):
				continue
			var profit: int = Economy.sell_price(pid, gid) - Economy.buy_price(port_id, gid)
			if profit > best.get("profit", 0):
				best = {"profit": profit, "port": pid, "good": gid}
	if best.get("profit", 0) <= 0:
		return "【闲谈】几个老水手翻来覆去只讲当年的风暴，没打听出什么有用的。"
	return "【行情】邻座的牙人压低声音：「%s 眼下缺%s，此地买了运过去，一件能多得 %d 钱。」" % [
		GameManager.get_port_name(best["port"]),
		GameManager.get_good_name(best["good"]),
		best["profit"],
	]


# ══════════════════════════════════════════════════════
#  NPC
# ══════════════════════════════════════════════════════

func _add_npc_button(npc_id: String, fallback_name: String) -> void:
	var btn = Button.new()
	btn.text = "【遇见人物】 " + fallback_name
	btn.pressed.connect(func(): _show_npc_mode(npc_id, fallback_name))
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.4, 0.6, 1.0)
	btn.add_theme_stylebox_override("normal", sb)
	choices_container.add_child(btn)
	choices_label.visible = true


func _show_npc_mode(npc_id: String, fallback_name: String) -> void:
	investigation_mode.visible = false
	npc_mode.visible = true

	var npc_data := {}
	for n in GameManager.npcs_data.get("npcs", []):
		if n.get("id") == npc_id:
			npc_data = n
			break

	var n_name = npc_data.get("name", fallback_name)
	npc_name_lbl.text = n_name
	npc_dialog_lbl.text = npc_data.get("function", "（这人看起来有些眼熟，但什么也没说...）")

	var tex_path = "res://assets/sprite_" + npc_id.replace("pilot_", "").replace("merchant_", "") + ".png"
	npc_portrait.texture = GameManager.load_texture(tex_path)

	for child in npc_actions.get_children():
		child.queue_free()

	var intel_btn = Button.new()
	intel_btn.text = "打听情报"
	intel_btn.pressed.connect(func():
		npc_dialog_lbl.text = n_name + " 压低声音说：\n\n" + _gather_price_intel(GameState.last_port)
	)
	npc_actions.add_child(intel_btn)

	if npc_id == "customs_official":
		var bribe_btn = Button.new()
		bribe_btn.text = "塞钱疏通（50 钱，降低关注度）"
		bribe_btn.pressed.connect(func():
			if GameState.spend_money(50):
				GameState.pu_attention = maxi(0, GameState.pu_attention - 15)
				update_status_panel()
				npc_dialog_lbl.text = n_name + " 颠了颠手里的碎银：「算你懂事。近来风声紧，自己当心。」"
			else:
				npc_dialog_lbl.text = n_name + " 满脸鄙夷：「就这点钱也想打通关节？」"
		)
		npc_actions.add_child(bribe_btn)

	var leave_btn = Button.new()
	leave_btn.text = "离开"
	leave_btn.pressed.connect(func():
		npc_mode.visible = false
		investigation_mode.visible = true
	)
	npc_actions.add_child(leave_btn)


# ══════════════════════════════════════════════════════
#  标题 / 港口 / 调查
# ══════════════════════════════════════════════════════

func _setup_title_mode(scene_data: Dictionary) -> void:
	left_panel.visible = false
	investigation_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	title_mode.visible = true

	main_title.text = scene_data.get("cg_title", "东亚海域立志传")
	sub_title.text = scene_data.get("cg_sub", "")

	if title_button_connected:
		for c in start_button.pressed.get_connections():
			start_button.pressed.disconnect(c.callable)

	var choices = scene_data.get("choices", [])
	var next_scene = "prologue_tabletop"
	if choices.size() > 0:
		start_button.text = choices[0].get("label", "开始旅程")
		next_scene = choices[0].get("next", "prologue_tabletop")

	start_button.pressed.connect(_on_start_game_pressed.bind(next_scene))
	title_button_connected = true


func _on_start_game_pressed(next_scene: String) -> void:
	load_scene(next_scene)


func _setup_port_mode(scene_data: Dictionary) -> void:
	left_panel.visible = true
	title_mode.visible = false
	investigation_mode.visible = false
	npc_mode.visible = false
	port_mode.visible = true
	port_title.text = scene_data.get("title", "未知港口")

	for child in left_facilities.get_children():
		child.queue_free()
	for child in right_facilities.get_children():
		child.queue_free()

	var facilities = scene_data.get("facilities", [])
	for i in range(facilities.size()):
		var card := _make_facility_card(facilities[i])
		if i % 2 == 0:
			left_facilities.add_child(card)
		else:
			right_facilities.add_child(card)

	_add_sail_button()
	_add_save_button()


func _make_facility_card(fac: Dictionary) -> Control:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 90)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 0.5)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	card.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	card.add_child(hbox)

	var icon_id = fac.get("id", "").replace("city_", "")
	var icon_path = "res://assets/icon_" + icon_id + ".png"
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(80, 80)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var icon_tex := GameManager.load_texture(icon_path)
	if icon_tex != null:
		tex_rect.texture = icon_tex

	var icon_margin = MarginContainer.new()
	icon_margin.add_theme_constant_override("margin_left", 5)
	icon_margin.add_theme_constant_override("margin_right", 5)
	icon_margin.add_child(tex_rect)
	hbox.add_child(icon_margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = fac.get("title", "未命名设施")
	title_lbl.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = fac.get("subtitle", "")
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	sub_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(sub_lbl)

	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_facility_pressed.bind(fac))
	btn.mouse_entered.connect(func(): style.bg_color = Color(0.25, 0.25, 0.3, 0.8))
	btn.mouse_exited.connect(func(): style.bg_color = Color(0.1, 0.1, 0.1, 0.6))
	card.add_child(btn)

	return card


func _add_sail_button() -> void:
	var btn = Button.new()
	btn.text = "🚢 升帆出海（海图）"
	btn.custom_minimum_size = Vector2(250, 70)
	btn.add_theme_font_size_override("font_size", 22)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.75, 0.22, 0.2, 1.0)
	btn.add_theme_stylebox_override("normal", sb)
	btn.pressed.connect(_on_set_sail)
	right_facilities.add_child(btn)


func _on_set_sail() -> void:
	if not Fleet.can_sail():
		log_msg("【无法出海】水手不足 %d 人，船开不动。先去船屋雇人。" % Fleet.crew_min_required())
		update_status_panel()
		return
	if Fleet.supply_days() < 2:
		log_msg("【补给不足】水粮撑不过两日，此时出海是拿全船人的命赌。")
		update_status_panel()
		return

	var res: Dictionary = GameState.customs_inspection()
	log_msg(res["msg"])
	update_status_panel()

	if res["passed"]:
		GameState.consume_permit()
		get_tree().change_scene_to_file("res://scenes/SeaChart.tscn")


func _add_save_button() -> void:
	var btn = Button.new()
	btn.text = "存档 / 读档"
	btn.custom_minimum_size = Vector2(250, 44)
	btn.pressed.connect(_show_save_dialog)
	right_facilities.add_child(btn)


func _show_save_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "航海日志"
	dlg.dialog_hide_on_ok = true
	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	for slot in range(1, SaveLoad.SLOTS + 1):
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "第 %d 卷：%s" % [slot, SaveLoad.save_label(slot)]
		lbl.custom_minimum_size = Vector2(360, 0)
		row.add_child(lbl)

		var sb := Button.new()
		sb.text = "记录"
		sb.pressed.connect(func():
			SaveLoad.save_game(slot, current_scene_id)
			dlg.queue_free()
			log_msg("已记入航海日志第 %d 卷。" % slot)
		)
		row.add_child(sb)

		var lb := Button.new()
		lb.text = "翻阅"
		lb.disabled = not SaveLoad.has_save(slot)
		lb.pressed.connect(func():
			var scene_id := SaveLoad.saved_scene(slot)
			if SaveLoad.load_game(slot):
				dlg.queue_free()
				update_status_panel()
				load_scene(scene_id if scene_id != "" else GameState.last_port)
				log_msg("翻开日志第 %d 卷，回到 %s。" % [slot, Calendar.get_date_string()])
		)
		row.add_child(lb)
		vb.add_child(row)

	add_child(dlg)
	dlg.popup_centered()


# ══════════════════════════════════════════════════════
#  章节推进
# ══════════════════════════════════════════════════════

## 入港结算：记下走过的港口，够条件就开下一章。
## 只有 ports.json 里登记的港口算数——剧情场景不是港口。
func _on_enter_port(port_id: String) -> void:
	if GameManager.get_port_by_id(port_id).is_empty():
		return
	GameState.visit_port(port_id)
	var res := GameState.try_advance_chapter()
	if res.get("advanced", false):
		_show_chapter_dialog(res)


func _show_chapter_dialog(res: Dictionary) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "第 %s 章・%s" % [
		_cn_chapter(GameState.chapter), GameState.chapter_def().get("name", ""),
	]
	dlg.ok_button_text = "承此一路"

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var head := Label.new()
	head.text = res.get("title", "")
	head.add_theme_font_size_override("font_size", 26)
	v.add_child(head)

	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.custom_minimum_size = Vector2(520, 200)
	body.text = res.get("text", "")
	v.add_child(body)

	dlg.add_child(m)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func(): load_scene(current_scene_id))

	update_status_panel()


func _cn_chapter(n: int) -> String:
	var cn := ["", "一", "二", "三", "四", "五", "六"]
	return cn[n] if n < cn.size() else str(n)


func _on_facility_pressed(fac: Dictionary) -> void:
	var target_scene = fac.get("id", "")
	if target_scene in ["city_market", "city_yamen", "city_shipyard", "city_tavern"]:
		target_scene = current_scene_id + "_" + target_scene.trim_prefix("city_")
	if target_scene != "":
		load_scene(target_scene)


func _setup_investigation_mode(scene_data: Dictionary) -> void:
	_enter_panel_mode()

	scene_title.text = scene_data.get("title", "未命名地点")
	body_text.text = scene_data.get("body", "")

	var investigations = scene_data.get("investigations", [])
	for inv in investigations:
		var btn = Button.new()
		btn.text = "★ " + inv.get("label", "互动")
		btn.pressed.connect(_on_investigate_pressed.bind(inv, btn))
		interactive_container.add_child(btn)

	var choices = scene_data.get("choices", [])
	show_choices(choices)

	if investigations.size() == 0 and choices.size() == 0:
		_add_fallback_return_button()


func _add_fallback_return_button() -> void:
	var target = previous_scene_id
	if target == "":
		target = GameState.last_port
	if target == "" or target == current_scene_id:
		return
	var btn = Button.new()
	btn.text = "返回上一处"
	btn.pressed.connect(func(): load_scene(target))
	choices_container.add_child(btn)
	choices_label.visible = true


func _add_leave_button(port_id: String) -> void:
	var btn = Button.new()
	btn.text = "离开"
	btn.pressed.connect(func(): load_scene(port_id))
	choices_container.add_child(btn)
	choices_label.visible = true


func _on_investigate_pressed(inv_data: Dictionary, btn: Button) -> void:
	var msg = inv_data.get("text", "")
	if msg != "":
		body_text.text += "\n\n" + msg
	apply_effects(inv_data.get("effects", {}))

	var next_sc = inv_data.get("next", "")
	if next_sc != "":
		load_scene(next_sc)
	else:
		btn.disabled = true


func show_choices(choices: Array) -> void:
	if choices.is_empty():
		return
	choices_label.visible = true
	for choice in choices:
		var btn = Button.new()
		btn.text = choice.get("label", "继续")
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		choices_container.add_child(btn)


func _on_choice_pressed(choice_data: Dictionary) -> void:
	apply_effects(choice_data.get("effects", {}))
	var next_scene = choice_data.get("next", "")
	if next_scene != "":
		load_scene(next_scene)


func apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var val = effects[key]
		match key:
			"money":
				GameState.add_money(val)
			"fame":
				GameState.fame += val
			"days":
				GameManager.advance_days(val)
			"flag":
				GameState.set_flag(str(val))
			"chapter":
				GameState.chapter = maxi(GameState.chapter, int(val))
	update_status_panel()
