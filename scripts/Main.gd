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
## 牙行当前选中的船 index（多船分装用），进牙行时重置为旗舰
var _market_ship: int = 0

const FACILITY_SUFFIXES := ["_market", "_yamen", "_shipyard", "_tavern", "_inn", "_residence"]

## 港口页上的特殊卡（非设施）：由 _on_facility_pressed 按 id 路由
const CARD_HANJIANG := "special_hanjiang_escape"
## 守城卡（兴化围城期，甲线）
const CARD_SIEGE_MUSTER := "siege_muster"      # 衙门・募兵 / 石手军
const CARD_SIEGE_GRAIN := "siege_grain"        # 市场・屯粮
const CARD_SIEGE_WALL := "siege_wall"          # 船厂・修城墙
const CARD_SIEGE_ENVOY := "siege_envoy"        # 酒馆・使者
const CARD_SIEGE_NANGSHAN := "siege_nangshan"  # 囊山设伏
const CARD_SIEGE_NUNNERY := "siege_nunnery"    # 福州尼寺（不可操作）
## 士人线 1275 年末「出国门而悔」；海商线 1279 崖山 / 1285 收官
const CARD_RESIGN := "special_resign_1275"
const CARD_YASHAN := "special_yashan"
const CARD_GANGSHOU := "special_gangshou_end"

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
	# 防御：异常路径可能残留未清理的海战上下文，回港时清空
	GameManager.pending_battle = {}
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

	var t := "[b]%s[/b]　%s\n%s\n\n" % [GameState.player_name, Calendar.get_date_string(), Calendar.get_monsoon_desc()]
	t += "金钱：%d\n" % GameState.money
	if GameState.debt > 0:
		t += "[color=orange]欠债：%d[/color]\n" % GameState.debt
	t += "名声：%d\n" % GameState.fame
	var war_lbl := Economy.war_label(GameState.last_port)
	if war_lbl != "":
		t += "[color=orange]战况：%s %s[/color]\n" % [GameManager.get_port_name(GameState.last_port), war_lbl]
	t += "\n"
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

	# 多船时追加每船明细
	if Fleet.ships.size() > 1:
		for i in range(Fleet.ships.size()):
			var s: Dictionary = Fleet.ships[i]
			var per_ship := ""
			var sc: Dictionary = s.get("cargo", {})
			if sc.is_empty():
				per_ship = "空"
			else:
				for gid in sc.keys():
					per_ship += "%s ×%d　" % [GameManager.get_good_name(gid), sc[gid].get("qty", 0)]
			var crew_str := "水手 %d/%d" % [Fleet.ship_crew(i), Fleet.ship_crew_max(i)]
			var crew_color := "white"
			if Fleet.ship_crew(i) < Fleet.ship_crew_min(i):
				crew_color = "red"
				crew_str += "（缺 %d 人）" % (Fleet.ship_crew_min(i) - Fleet.ship_crew(i))
			t += "[i]└ %s（%s）%d/%d 料　帆Lv%d/甲Lv%d　[color=%s]%s[/color]　%s[/i]\n" % [
				s.get("name", ""), Fleet.ship_def(s.get("type", "")).get("name", ""),
				int(Fleet.ship_cargo_bulk(i)), int(Fleet.ship_capacity(i)),
				Fleet.sail_level(i), Fleet.armor_level(i),
				crew_color, crew_str, per_ship,
			]

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
		"_residence":
			_setup_residence(base_loc)


# ── 牙行（市场）─────────────────────────────────────

func _setup_market(port_id: String) -> void:
	scene_title.text = "%s・牙行" % GameManager.get_port_name(port_id)
	body_text.text = "牙行里挤着各色商人，没有人说官话，只用手势、算筹和一把碎银落地就要捡的速度说话。"

	if not Economy.is_market_open(port_id):
		body_text.text += "\n\n牙行的门板上了闸。%s，城里只剩米价在动，没人敢开秤。" % Economy.war_label(port_id)
		_add_leave_button(port_id)
		return

	var goods_ids: Array = Economy.goods_at(port_id)
	if goods_ids.is_empty():
		body_text.text += "\n\n此地并无正经牙行，只有几个渔妇在晒网。"
		_add_leave_button(port_id)
		return

	# 按买价排序，便宜的在前
	goods_ids.sort_custom(func(a, b): return Economy.buy_price(port_id, a) < Economy.buy_price(port_id, b))

	# 多船时选船装货；重置到旗舰
	_market_ship = 0
	if Fleet.ships.size() > 1:
		var sel := HBoxContainer.new()
		sel.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = "装至："
		lbl.custom_minimum_size = Vector2(44, 0)
		sel.add_child(lbl)
		var opt := OptionButton.new()
		for i in range(Fleet.ships.size()):
			var s: Dictionary = Fleet.ships[i]
			opt.add_item("%s（%s）　空 %d 料" % [
				s.get("name", ""), Fleet.ship_def(s.get("type", "")).get("name", ""),
				int(Fleet.ship_free_capacity(i)),
			])
			opt.set_item_metadata(i, i)
		opt.selected = _market_ship
		opt.item_selected.connect(func(idx: int):
			_market_ship = int(opt.get_item_metadata(idx))
			load_scene(current_scene_id))
		sel.add_child(opt)
		choices_container.add_child(sel)

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
	var held := Fleet.cargo_qty(good_id, _market_ship)
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
		b.pressed.connect(_on_buy.bind(port_id, good_id, n, _market_ship))
		row.add_child(b)

	var bmax := Button.new()
	bmax.text = "买满"
	bmax.pressed.connect(_on_buy_max.bind(port_id, good_id, _market_ship))
	row.add_child(bmax)

	for n in [1, 10]:
		var s := Button.new()
		s.text = "卖%d" % n
		s.disabled = held < n
		s.pressed.connect(_on_sell.bind(port_id, good_id, n, _market_ship))
		row.add_child(s)

	var sall := Button.new()
	sall.text = "全卖"
	sall.disabled = held <= 0
	sall.pressed.connect(_on_sell.bind(port_id, good_id, held, _market_ship))
	row.add_child(sall)

	return row


func _on_buy(port_id: String, good_id: String, amount: int, ship_index: int) -> void:
	if amount <= 0:
		return
	var loadable := Fleet.max_loadable(good_id, ship_index)
	if loadable <= 0:
		log_msg("【舱满】这艘船塞不下了。换一艘船，或先卖掉些货。")
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
	Fleet.add_cargo(good_id, actual, float(cost) / float(actual), ship_index)
	Economy.apply_buy_impact(port_id, good_id, actual)

	var note := ""
	if actual < amount:
		note = "（只购得 %d）" % actual
	log_msg("买入 %s ×%d，付 %d 钱。%s" % [GameManager.get_good_name(good_id), actual, cost, note])
	load_scene(current_scene_id)


func _on_buy_max(port_id: String, good_id: String, ship_index: int) -> void:
	var by_hold := Fleet.max_loadable(good_id, ship_index)
	if by_hold <= 0:
		log_msg("【舱满】这艘船塞不下了。换一艘船，或先卖掉些货。")
		return
	var n := by_hold
	while n > 0 and Economy.estimate_buy_cost(port_id, good_id, n) > GameState.money:
		n -= 1
	if n <= 0:
		log_msg("【钱不够】连一件也买不起。")
		return
	_on_buy(port_id, good_id, n, ship_index)


func _on_sell(port_id: String, good_id: String, amount: int, ship_index: int) -> void:
	var held := Fleet.cargo_qty(good_id, ship_index)
	var actual := mini(amount, held)
	if actual <= 0:
		return
	var revenue := Economy.estimate_sell_revenue(port_id, good_id, actual)
	var cost_basis := Fleet.cargo_cost(good_id, ship_index) * actual

	Fleet.remove_cargo(good_id, actual, ship_index)
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
	_setup_quanzhou_standoff(port_id)

	var att := Label.new()
	att.text = "蒲氏关注度 %d　%s" % [GameState.pu_attention, _attention_desc()]
	att.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(att)

	choices_label.visible = true
	_add_leave_button(port_id)


## 泉州对峙期（1276-05 至降元前）：张世杰索船，蒲家不给。市舶司钉出征船名册，你的船在上面。
## 一张卡三选一，选过即止；拖到泉州降元则名册作废，什么也不发生——这本身也是一种选择。
func _setup_quanzhou_standoff(port_id: String) -> void:
	if port_id != "quanzhou" or Economy.war_status("quanzhou") != "contested":
		return
	if GameState.has_flag("sided_zhang") or GameState.has_flag("sided_pu") or GameState.has_flag("fled_quanzhou"):
		return

	var sep := Label.new()
	sep.text = "── 征船名册 ──"
	sep.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(sep)

	var info := Label.new()
	var who: String = GameState.player_name if GameState.has_flag("renamed_wenlong") else "陈纲首"
	info.text = "牙行门口钉着一张纸，第四行是你的船。小吏低声说：「%s。张少保要船，蒲提举说泉州的船蒲家说了算。您站哪边？」" % who
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	choices_container.add_child(info)

	var zhang := Button.new()
	if Fleet.ships.size() > 1:
		zhang.text = "船借张世杰——编出最小一条船（名声 +8，海商信用 −15）"
	else:
		zhang.text = "船借张世杰——只此一条，出人出粮（名声 +8，海商信用 −15，水粮减半）"
	zhang.pressed.connect(func():
		if Fleet.ships.size() > 1:
			var idx := 0
			for i in range(Fleet.ships.size()):
				if Fleet.ship_capacity(i) < Fleet.ship_capacity(idx):
					idx = i
			var sname: String = Fleet.ships[idx].get("name", "一船")
			Fleet.ships.remove_at(idx)
			log_msg("「%s」挂了宋旗，编进张少保的船队。蒲家的人在码头上看着，没说话。" % sname)
		else:
			Fleet.water = Fleet.water / 2
			Fleet.food = Fleet.food / 2
			log_msg("船没给，人和粮给了一半。蒲家的人在码头上看着，没说话。")
		GameState.fame += 8
		GameState.merchant_credit -= 15
		GameState.pu_attention = 0
		GameState.set_flag("sided_zhang")
		GameState.add_ledger_note("借船张世杰")
		load_scene(current_scene_id)
	)
	choices_container.add_child(zhang)

	var pu := Button.new()
	pu.text = "跟蒲家——泉州抽解永久八折（海商信用 +10，名声 −8）"
	pu.pressed.connect(func():
		GameState.merchant_credit += 10
		GameState.fame -= 8
		GameState.set_flag("sided_pu")
		GameState.add_ledger_note("蒲家账房的茶")
		log_msg("蒲家的账房请你喝了茶。茶很好。他说泉州不会有事，「提举心里有数」。你问有数是什么数。他笑，没答。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(pu)

	var flee := Button.new()
	flee.text = "今夜出港，谁也不给——泉州对你封港至降元"
	flee.pressed.connect(func():
		GameState.set_flag("fled_quanzhou")
		GameState.ban_port("quanzhou", "1276-11")
		GameState.add_ledger_note("澎湖避祸")
		log_msg("夜潮。港外张世杰的船队像一座漂着的城。没有人拦你——他们不知道你是谁，这时候这是好事。泉州的门，年内不要再敲。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(flee)


## 港口页特殊卡：只在特定年月与旗标下出现。
func _special_cards() -> Array:
	var out := []
	# 涵江海口 → 旧避风澳：1277 年二三月陈瓒复兴化的那四十天，且第一章复核过旧泊地
	if current_scene_id in ["xinghua", "xinghua_harbor"] \
			and Calendar.year == 1277 and Calendar.month in [2, 3] \
			and Economy.war_status("xinghua") == "loyal" \
			and not GameState.has_flag("renamed_wenlong") \
			and GameState.has_found("nameless_shelter_bay") \
			and not GameState.has_flag("ending_root_sea"):
		out.append({"id": CARD_HANJIANG, "title": "涵江海口", "subtitle": "带族人走旧避风澳"})

	# 士人线：辞呈已批，出不出国门（1275-12 起，未决则一直挂着）
	if GameState.has_flag("vice_councillor") and not _resign_decided():
		out.append({"id": CARD_RESIGN, "title": "临安・辞呈批语", "subtitle": "依奏。车已备在门外"})

	# 海商线：崖山（1279 正月至三月，须在广州）
	if current_scene_id == "guangzhou" and GameState.identity == "merchant" \
			and Calendar.year == 1279 and Calendar.month <= 3:
		out.append({"id": CARD_YASHAN, "title": "崖山", "subtitle": "宋军的船连成一片"})

	# 海商线收官：1285 年后，一局跑到底（乡土线同样收在这里）
	if GameState.identity != "scholar" and Calendar.year >= 1285:
		out.append({"id": CARD_GANGSHOU, "title": "市舶司・新册", "subtitle": "封面换了，名字还在"})

	return out


func _resign_decided() -> bool:
	return GameState.has_flag("petitioned_return") \
		or GameState.has_flag("quiet_return") \
		or GameState.has_flag("late_defection")


## 1275 年十二月：辞呈已批，出了嘉会门又后悔。三条路，用航向选，不用按钮选。
func _on_resign_1275() -> void:
	_enter_panel_mode()
	scene_title.text = "临安・嘉会门"
	body_text.text = "辞呈是三天前批的。批语只有两个字：「依奏。」
车出嘉会门时是卯时，守门的兵在跺脚取暖。车里放着一只书箧，箧里是十三年前那本夹着货引的《论语》。

车过江头。钱塘江的水是灰的，和兴化海口一个颜色。车夫问：过了江往南，走陆路还是走海路？"

	var again := Button.new()
	again.text = "回头。再上一疏求还。"
	again.pressed.connect(func():
		GameState.set_flag("petitioned_return")
		GameState.scholar_tendency += 4
		GameState.add_ledger_note("复上疏不报")
		GameManager.advance_days(7)
		_show_notice_dialog("出国门而悔", "钱塘江畔",
			"你在江边客店里写了一夜。天亮时奏疏送进城去。
等了六天。没有回音。第七天，客店掌柜小心地问你还住不住。
你付了钱，上了去明州的船。奏疏后来有没有人拆过，你一辈子不知道。")
	)
	choices_container.add_child(again)

	var quiet := Button.new()
	quiet.text = "不回头。走海路回兴化。"
	quiet.pressed.connect(func():
		GameState.set_flag("quiet_return")
		GameState.set_flag("no_official_title")
		GameState.sea_tendency += 2
		GameState.hometown_tendency += 4
		GameManager.advance_days(11)
		_show_notice_dialog("不回头", "海上十一日",
			"船在明州换了一次，在温州又换了一次。海上十一天，你大部分时候在看水色。
二十年前阿那教过你怎么看，你以为早忘了。
没忘。")
	)
	choices_container.add_child(quiet)

	var defect := Button.new()
	defect.text = "车转向南，去泉州找林阿舶（清算士人三锚）"
	defect.disabled = GameState.money < 500
	defect.tooltip_text = "县学籍册、名流举荐信、宗祠联名担保——撕这三张纸要钱，也要名声。"
	defect.pressed.connect(func():
		if not GameState.spend_money(500):
			return
		GameState.set_flag("late_defection")
		GameState.fame -= 10
		GameState.sea_tendency += 6
		GameState.identity = "merchant"
		GameState.merchant_credit += 10
		GameState.add_ledger_note("一铺之地")
		GameManager.advance_days(9)
		_show_notice_dialog("一铺之地", "泉州・城南账房",
			"泉州。二十年。
码头比你记得的大了一倍，桅杆密得像一片死掉的林子。你问林阿舶的账房在哪，被问的人看了看你的官袍，指了指城南。

账房里坐着的不是林阿舶。是一个和你差不多年纪的人，算盘打得比林阿舶还快。他抬头：「陈大人？林老爹去年走了。他说过要是有个姓陈的读书人来，账上给留了一铺之地。」

他推过来一张纸。上面是二十年前你叔父那笔债的余数——早清了，用红笔划掉的。红笔底下另起一行：「陈子龙，船股一分。」

你还叫陈文龙。可这张纸上写的是另一个名字。")
	)
	choices_container.add_child(defect)

	choices_label.visible = true
	_add_leave_button(current_scene_id)


## 崖山：把粮与硫黄交上去，然后砍断自己的缆。
func _on_yashan() -> void:
	_enter_panel_mode()
	scene_title.text = "崖山外海"
	var known_here := GameState.has_flag("sided_zhang")
	body_text.text = "祥兴二年二月。张世杰的船连成一片，船和船之间用铁索。
陈瓒的船不在——他回兴化了，听说起了兵，要把兴化夺回来。
"
	if known_here:
		body_text.text += "书吏翻册子翻到一半停住了：「泉州借船的那位。少保记着。」
他没有再问你叫什么。"
	else:
		body_text.text += "一个书吏在册子上记你的名字。他问：「哪个陈？」"

	var join := Button.new()
	join.text = "把粮与硫黄交上去，船留在外围"
	join.pressed.connect(func():
		GameState.fame += 12
		GameState.merchant_credit -= 30
		GameManager.advance_days(5)
		# 泉州借过船的，崖山有人替你留了外围的位置——砍缆的门槛低一截
		var speed_ok := Fleet.fleet_speed() > (70.0 if known_here else 90.0)
		var tail := ""
		if speed_ok and known_here:
			tail = "有人在铁索那头替你留了一道口子。你砍断自己的缆，从那道口子出去。
阿那要是还活着，会告诉你这时候该往哪边走。你自己看了水色。往南。"
		elif speed_ok:
			tail = "你砍断了自己的缆。阿那要是还活着，会告诉你这时候该往哪边走。你自己看了水色。往南。"
		else:
			tail = "你砍缆砍晚了。火从上风头卷过来，烧了半条船。人捞上来一半。往南走的时候，船比来时轻得多。"
		if not speed_ok:
			Fleet.damage_fleet(60.0)
			Fleet.lose_cargo_ratio(0.5)
		_show_notice_dialog("海上宋鬼", "崖山・祥兴二年二月",
			"战到午后，铁索连着的船开始烧。
%s

——
一百多年后，福州台江，江边没有庙。渔船只拜妈祖。二号封舟，空着。
这个世界少了一位海神，多了几条回来的船。" % tail,
			"海上宋鬼")
	)
	choices_container.add_child(join)

	var pass_by := Button.new()
	pass_by.text = "不上前。远远看着，掉头往南"
	pass_by.pressed.connect(func():
		GameState.fame -= 6
		Fleet.morale = maxi(0, Fleet.morale - 10)
		GameState.add_ledger_note("崖山外海掉头")
		GameManager.advance_days(3)
		log_msg("你在十里外看着那片火。水手们没有说话。掉头往南的时候，风是顺的。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(pass_by)

	choices_label.visible = true
	_add_leave_button(current_scene_id)


## 海商线收官：至元年间，泉州更大了。
func _on_gangshou_end() -> void:
	var pu := GameState.has_flag("sided_pu")
	var head := "泉州・至元二十二年"
	var text := ""
	if pu:
		text = "市舶司的册子换了封面。你的名字还在，「纲首」两字旁边加了一个蒙古官名，你不认得。
蒲家的账房说，明年起船去占城不用再走暗关了——「都是一家人」。

"
	else:
		text = "市舶司的册子换了封面。你的名字还在，只是排在很后面。
那些当年站错队的，名字已经不在册上了。你还在。

"
	text += "你活到了至元二十年代。泉州比从前更大，港里有波斯人、大食人、高丽人，还有从前不敢来的北方人。
有一年你雇的一个兴化水手在船上说：他们村口有一座小祠，供一个叫陈瓒的。
你问，有没有一个叫陈文龙的。
他说没听过。

——
一百多年后，福州台江，江边没有庙。渔船只拜妈祖。二号封舟，空着。
这个世界少了一位海神，多了几条回来的船。"
	_show_notice_dialog("纲首" if not pu else "泉州蒲氏的船", head, text, "泉州蒲氏的船" if pu else "纲首")





## 「岸上的根」：陈瓒守城，你带族人出海。第一章那次复核在二十二年后变现。
func _on_hanjiang_escape() -> void:
	if Fleet.supply_days() < 7:
		log_msg("【水粮不足】四条船的人，至少要撑七日。先去船屋补齐。")
		update_status_panel()
		return
	GameManager.advance_days(7)
	GameState.set_flag("ending_root_sea")
	GameState.fame += 10
	GameState.hometown_tendency += 10
	GameState.add_ledger_note("北礁可泊")
	var stake_line := "陈瓒没有上船。他说他姓陈，在这里出生，就死在这里。" if GameState.has_flag("chen_zan_stake") else "陈瓒没有上船。"
	_show_notice_dialog(
		"岸上的根",
		"旧避风澳・景炎三年三月",
		"四条船。族里能走的都在船上，老夫人也在，她把箧底那叠策论草稿带上了船，说是「%s的东西」。\n%s\n\n出海口的时候元兵已经进城了。海上没有人追。你看水色。北礁可泊。二十二年前，一个舵手教过你。\n\n船在旧避风澳泊了六天，避了一场风。第七天早晨，老夫人把那叠草稿拿出来晒。纸都黄了，字还在。她一张一张看，看完了放回去。\n「%s，」她说，「往南走吧。」\n\n——\n一百多年后，福州台江，江边没有庙。渔船只拜妈祖。二号封舟，空着。\n这个世界少了一位海神，多了几条回来的船。" % [
			"子龙", stake_line, "子龙",
		],
		"岸上的根"
	)


## 通用结算对话框（章节晋升以外的历史节点与结局用）。
## ending 非空则落定终局：关掉对话框后港口页只剩回顾札记。
func _show_notice_dialog(title: String, head: String, text: String, ending: String = "") -> void:
	if ending != "":
		GameState.finish(ending, text)
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.ok_button_text = "……" if ending == "" else "此局终"

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var h := Label.new()
	h.text = head
	h.add_theme_font_size_override("font_size", 24)
	v.add_child(h)

	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.custom_minimum_size = Vector2(560, 240)
	body.text = text
	v.add_child(body)

	dlg.add_child(m)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func(): load_scene(current_scene_id))
	update_status_panel()


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

	# 雇水手：缺员时先提供「补足各船最低水手」聚合按钮，再逐船独立雇佣
	var below_min: int = Fleet.crew_to_min_needed()
	if below_min > 0:
		var top_cost := below_min * 20
		var tb := Button.new()
		tb.text = "补足各船最低水手 %d 人（%d 钱）" % [below_min, top_cost]
		tb.pressed.connect(func():
			if GameState.spend_money(top_cost):
				var got: int = Fleet.hire_to_min()
				log_msg("码头上凑齐了 %d 个水手，各船补至最低人手。" % got)
			else:
				log_msg("【钱不够】没人肯赊帐上船。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(tb)

	for i in range(Fleet.ships.size()):
		var room: int = Fleet.ship_crew_room(i)
		if room <= 0:
			continue  # 满员船不显示按钮（0 金额按钮会让人误以为免费雇人）
		var s: Dictionary = Fleet.ships[i]
		var hire_n: int = mini(10, room)
		var hire_cost := hire_n * 20
		var hb := Button.new()
		hb.text = "雇 %d 人 → %s（%d 钱，该船可容 %d，现有 %d）" % [
			hire_n, s.get("name", ""), hire_cost, room, Fleet.ship_crew(i),
		]
		hb.pressed.connect(_on_hire_crew.bind(i, hire_n, hire_cost))
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

	# 改装：帆 Lv 决定航速，甲 Lv 减免风暴/海盗船体伤。逐船两按钮（.bind 传 index 防闭包陷阱）
	var up_lbl := Label.new()
	up_lbl.text = "── 船体改装（帆 Lv 决定航速，甲 Lv 减免风暴/海盗船体伤）──"
	up_lbl.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(up_lbl)

	for i in range(Fleet.ships.size()):
		var s: Dictionary = Fleet.ships[i]
		var sname: String = s.get("name", "船")
		var slv: int = Fleet.sail_level(i)
		var alv: int = Fleet.armor_level(i)

		if Fleet.is_sail_max(i):
			var fsat := Button.new()
			fsat.text = "「%s」帆已满级（Lv%d）" % [sname, Fleet.SAIL_LEVEL_MAX]
			fsat.disabled = true
			choices_container.add_child(fsat)
		else:
			var scost: int = Fleet.upgrade_cost(i, "sail")
			var fb := Button.new()
			fb.text = "改「%s」帆 Lv%d→%d　航速 ×%.2f（%d 钱）" % [
				sname, slv, slv + 1, 1.0 + 0.12 * slv, scost,
			]
			fb.pressed.connect(_on_upgrade.bind(i, "sail", scost))
			choices_container.add_child(fb)

		if Fleet.is_armor_max(i):
			var asat := Button.new()
			asat.text = "「%s」甲已满级（Lv%d）" % [sname, Fleet.ARMOR_LEVEL_MAX]
			asat.disabled = true
			choices_container.add_child(asat)
		else:
			var acost: int = Fleet.upgrade_cost(i, "armor")
			var ab := Button.new()
			ab.text = "改「%s」甲 Lv%d→%d　船体伤 ×%.2f（%d 钱）" % [
				sname, alv, alv + 1, 1.0 - 0.10 * alv, acost,
			]
			ab.pressed.connect(_on_upgrade.bind(i, "armor", acost))
			choices_container.add_child(ab)

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


func _on_hire_crew(ship_index: int, hire_n: int, hire_cost: int) -> void:
	if GameState.spend_money(hire_cost):
		var got: int = Fleet.hire_crew(hire_n, ship_index)
		var s: Dictionary = Fleet.ships[ship_index]
		log_msg("码头上招了 %d 个水手，上了「%s」。" % [got, s.get("name", "")])
	else:
		log_msg("【钱不够】没人肯赊帐上船。")
	load_scene(current_scene_id)


func _on_upgrade(ship_index: int, kind: String, cost: int) -> void:
	if not GameState.spend_money(cost):
		log_msg("【钱不够】船匠掂了掂银袋，摇了摇头。")
	elif kind == "armor":
		Fleet.upgrade_armor(ship_index)
		var s: Dictionary = Fleet.ships[ship_index]
		log_msg("「%s」加厚了船壳，甲升至 Lv%d。" % [s.get("name", "船"), Fleet.armor_level(ship_index)])
	else:
		Fleet.upgrade_sail(ship_index)
		var s2: Dictionary = Fleet.ships[ship_index]
		log_msg("「%s」换了新帆，帆升至 Lv%d。" % [s2.get("name", "船"), Fleet.sail_level(ship_index)])
	load_scene(current_scene_id)


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


# ── 玉湖陈宅（兴化住宅）────────────────────────────

const CHEN_ZAN_STAKE := 3000
const CHEN_ZAN_FROM_YEAR := 1270
const CHEN_ZAN_MIN_FAME := 15

func _setup_residence(port_id: String) -> void:
	scene_title.text = "%s・玉湖陈宅" % GameManager.get_port_name(port_id)
	var mother := "母亲黄氏在隔壁厢房摇着织机，一声声像是催你动笔。" if Calendar.year < 1270 else "母亲黄氏的织机停了，她的手已经摇不动。她坐在织机旁边看你。"
	body_text.text = "祠堂的灯还是二十年前那盏。%s\n案上压着一叠策论草稿，纸边微硬。" % mother

	# 1268 殿试前：替族里跑事。这是「乡土」这条身份唯一的早期写入点。
	if GameState.identity == "undecided":
		var errand := Button.new()
		errand.text = "替族里跑一趟事（费 6 日・30 钱，乡土 +3）"
		errand.disabled = GameState.money < 30
		errand.pressed.connect(func():
			if not GameState.spend_money(30):
				return
			GameState.hometown_tendency += 3
			GameManager.advance_days(6)
			log_msg("修祠堂的木料、外姓那桩田讼、三房的婚事——都不是你的事，可族里只找得到你。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(errand)

	if GameState.has_flag("chen_zan_stake"):
		var l := Label.new()
		l.text = "族叔陈瓒的船股一分，记在账上。他说过：「几时回，走哪条水，要先说。」"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.65, 0.9, 0.7))
		choices_container.add_child(l)
	elif Calendar.year >= CHEN_ZAN_FROM_YEAR:
		var b := Button.new()
		if GameState.fame >= CHEN_ZAN_MIN_FAME:
			b.text = "族叔陈瓒愿入船股一分（得 %d 钱，乡土 +5）" % CHEN_ZAN_STAKE
			b.pressed.connect(func():
				GameState.add_money(CHEN_ZAN_STAKE)
				GameState.hometown_tendency += 5
				GameState.set_flag("chen_zan_stake")
				GameState.add_ledger_note("陈瓒船股一分")
				log_msg("陈瓒把三千钱推过案来，没数。「要多少、走哪条水、几时回——这三句先说清，钱就是你的。」")
				load_scene(current_scene_id)
			)
		else:
			b.text = "族叔陈瓒——「名声不到 %d，钱不能给你」" % CHEN_ZAN_MIN_FAME
			b.disabled = true
		choices_container.add_child(b)

	choices_label.visible = true
	_add_leave_button(port_id)


# ── 酒馆 ────────────────────────────────────────────

func _setup_tavern(port_id: String) -> void:
	scene_title.text = "%s・酒馆" % GameManager.get_port_name(port_id)
	body_text.text = "这里充斥着劣质酒水的味道和水手们的大声喧哗。"
	var recent := GameState.recent_news(3)
	if not recent.is_empty():
		body_text.text += "\n\n── 近日传闻 ──"
		for n in recent:
			var who: String = str(n.get("speaker", ""))
			body_text.text += "\n%s%s" % ["" if who == "" else who + "：", GameState.news_text(n)]

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

	if GameState.is_ended():
		_setup_ended_port()
		return

	if _siege_active():
		_setup_siege_port()
		return

	var facilities: Array = scene_data.get("facilities", []).duplicate()
	facilities.append_array(_special_cards())
	for i in range(facilities.size()):
		var card := _make_facility_card(facilities[i])
		if i % 2 == 0:
			left_facilities.add_child(card)
		else:
			right_facilities.add_child(card)

	_add_sail_button()
	_add_save_button()


# ── 守城模式（甲线・兴化 1276-11~12）───────────────────

## 条件：人在兴化、城被围、走的是士人线（御笔改过名的那条路）
func _siege_active() -> bool:
	if not (current_scene_id in ["xinghua", "xinghua_harbor"]):
		return false
	if not GameState.has_flag("renamed_wenlong"):
		return false
	if Economy.war_status("xinghua") != "besieged":
		return false
	GameState.siege_begin()
	return true


func _setup_siege_port() -> void:
	port_title.text = "兴化军・围城　第 %d/%d 阵" % [
		GameState.siege_get("round"), GameState.SIEGE_ROUNDS_MAX,
	]

	var stat := PanelContainer.new()
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	stat.add_child(m)
	var v := VBoxContainer.new()
	m.add_child(v)
	var head := Label.new()
	head.text = "城头白布八字：生为宋臣，死为宋鬼"
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	v.add_child(head)
	var body := Label.new()
	var grain: int = GameState.siege_get("grain")
	var rounds_left: int = grain / GameState.SIEGE_GRAIN_PER_ROUND
	body.text = "兵 %d / 上限 %d　粮 %d（够打 %d 阵）　城墙 %d　士气 %d%s" % [
		GameState.siege_get("troops"), GameState.siege_troop_cap(),
		grain, rounds_left, GameState.siege_get("wall"),
		GameState.siege_get("morale"),
		"　石手军在城" if str(GameState.siege.get("shishou", "")) == "kept" else "",
	]
	body.add_theme_font_size_override("font_size", 14)
	v.add_child(body)

	if rounds_left < 1:
		var warn := Label.new()
		warn.text = "⚠ 粮已不够打下一阵。此时出战即城破。"
		warn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		warn.add_theme_font_size_override("font_size", 14)
		v.add_child(warn)
	elif rounds_left == 1 and GameState.siege_get("round") < GameState.SIEGE_ROUNDS_MAX - 1:
		var warn2 := Label.new()
		warn2.text = "⚠ 粮只够再打一阵。要守满三阵，还得屯粮。"
		warn2.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
		warn2.add_theme_font_size_override("font_size", 14)
		v.add_child(warn2)

	left_facilities.add_child(stat)

	for fac in _siege_cards():
		var card := _make_facility_card(fac)
		right_facilities.add_child(card)

	_add_save_button()


func _siege_cards() -> Array:
	var out := []
	out.append({"id": CARD_SIEGE_MUSTER, "title": "衙门", "subtitle": "募兵・石手军"})
	out.append({"id": CARD_SIEGE_GRAIN, "title": "市场", "subtitle": "屯粮（粮即守城日）"})
	out.append({"id": CARD_SIEGE_WALL, "title": "船屋", "subtitle": "把修船的料改修城墙"})
	if not (GameState.siege.get("envoy_wang", false) and GameState.siege.get("envoy_kin", false)):
		out.append({"id": CARD_SIEGE_ENVOY, "title": "酒馆", "subtitle": "城下有使者求见"})
	var short_of_grain: bool = GameState.siege_get("grain") < GameState.SIEGE_GRAIN_PER_ROUND
	out.append({
		"id": CARD_SIEGE_NANGSHAN, "title": "囊山",
		"subtitle": "粮尽・出战即城破" if short_of_grain else "设伏迎敌（第 %d 阵）" % (GameState.siege_get("round") + 1),
	})
	out.append({"id": CARD_SIEGE_NUNNERY, "title": "福州尼寺", "subtitle": "母亲与璥儿在那里"})
	return out


func _on_siege_card(card_id: String) -> void:
	match card_id:
		CARD_SIEGE_MUSTER:
			_siege_muster()
		CARD_SIEGE_GRAIN:
			_siege_buy_grain()
		CARD_SIEGE_WALL:
			_siege_repair_wall()
		CARD_SIEGE_ENVOY:
			_siege_envoy()
		CARD_SIEGE_NANGSHAN:
			_siege_nangshan()
		CARD_SIEGE_NUNNERY:
			_show_notice_dialog(
				"福州尼寺", "你什么也做不了",
				"母亲黄氏和幼子璥被扣在福州一座尼寺里。
城里有人说，只要开门，当天就放回来。

你在城头上站了很久。这件事没有选项。"
			)


func _siege_muster() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・衙门"
	body_text.text = "案上摊着户籍。能拿动东西的都登了记，登完还是不满千。"

	var cap := GameState.siege_troop_cap()
	var room := cap - GameState.siege_get("troops")
	if room > 0:
		for n in [50, 200]:
			var take: int = mini(n, room)
			if take <= 0:
				continue
			var cost: int = take * GameState.SIEGE_TROOP_COST
			var b := Button.new()
			b.text = "募兵 %d 人（%d 钱）" % [take, cost]
			b.disabled = GameState.money < cost
			b.pressed.connect(func():
				if GameState.spend_money(cost):
					GameState.siege_add("troops", take)
					log_msg("募得 %d 人。倾家所有，招的是义兵，不是官军。" % take)
				load_scene(current_scene_id)
			)
			choices_container.add_child(b)
	else:
		var l := Label.new()
		l.text = "名声所及，能招的都招了。城中兵不满千。"
		choices_container.add_child(l)

	# 石手军一次性抉择
	if str(GameState.siege.get("shishou", "")) == "":
		var sep := Label.new()
		sep.text = "── 石手军 ──"
		sep.add_theme_font_size_override("font_size", 13)
		choices_container.add_child(sep)
		var info := Label.new()
		info.text = "两百个能把石头掷中人头的乡兵站在木兰陂上。朝廷议者说「不足用」，把他们裁了。他们说：不是反朝廷，是朝廷不要我们。"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
		choices_container.add_child(info)

		var keep := Button.new()
		keep.text = "重编石手军，归你麾下（兵 +200，囊山战力 ×1.5）"
		keep.pressed.connect(func():
			GameState.siege_set("shishou", "kept")
			GameState.siege_add("troops", 200)
			GameState.siege_add("morale", 8)
			GameState.hometown_tendency += 5
			log_msg("他们把石头放下了，没有走。以后五个月，城头上多了两百个不领饷的人。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(keep)

		var disband := Button.new()
		disband.text = "按律解散，不追究"
		disband.pressed.connect(func():
			GameState.siege_set("shishou", "disbanded")
			GameState.scholar_tendency += 2
			log_msg("他们把石头放下了，走了。有些人后来在囊山又出现过一次，不是站在你这边。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(disband)

	choices_label.visible = true
	_add_leave_button("xinghua")


func _siege_buy_grain() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・市场"
	body_text.text = "牙行闭着，只有米在动。价一天一个样。
粮就是守城的日子：每打一阵，耗粮 %d。" % GameState.SIEGE_GRAIN_PER_ROUND

	# 围城米价：随已打轮次上涨
	var unit: int = 12 + GameState.siege_get("round") * 8
	for n in [40, 120]:
		var cost: int = n * unit
		var b := Button.new()
		b.text = "屯粮 %d（%d 钱・每石 %d）" % [n, cost, unit]
		b.disabled = GameState.money < cost
		b.pressed.connect(func():
			if GameState.spend_money(cost):
				GameState.siege_add("grain", n)
				log_msg("买进粮 %d。米价一天一个样，明日只会更贵。" % n)
			load_scene(current_scene_id)
		)
		choices_container.add_child(b)

	choices_label.visible = true
	_add_leave_button("xinghua")


func _siege_repair_wall() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・船屋"
	body_text.text = "船料还剩一些。修船是为了走，修墙是为了不走。"

	for n in [20, 60]:
		var cost: int = n * 15
		var b := Button.new()
		b.text = "加固城墙 +%d（%d 钱）" % [n, cost]
		b.disabled = GameState.money < cost
		b.pressed.connect(func():
			if GameState.spend_money(cost):
				GameState.siege_add("wall", n)
				log_msg("把修船的料改了修墙。木匠没问为什么。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(b)

	choices_label.visible = true
	_add_leave_button("xinghua")


## 两封劝降书，各一次
func _siege_envoy() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・城下使者"

	if not GameState.siege.get("envoy_wang", false):
		body_text.text = "福州知军王刚中派了两个使者来，带着一封劝降书。正使在城下念。念到第三句时，你让人开了城门。"
		var kill := Button.new()
		kill.text = "斩正使，放副使回去，带一封信给王刚中"
		kill.pressed.connect(func():
			GameState.siege_set("envoy_wang", true)
			GameState.siege_add("morale", 10)
			GameState.fame += 5
			GameState.add_ledger_note("斩王刚中使")
			log_msg("信只有一句：「世强、刚中负国，文龙不负。」副使走的时候没敢回头。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(kill)
		var keep := Button.new()
		keep.text = "收下书信，不回话"
		keep.pressed.connect(func():
			GameState.siege_set("envoy_wang", true)
			GameState.siege_add("morale", -8)
			GameState.scholar_tendency -= 3
			GameState.set_flag("hesitated_once")
			log_msg("书信放在案上三天。第三天你把它烧了。城里有人看见你收信，也有人看见你烧信。两种人都在。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(keep)
	elif not GameState.siege.get("envoy_kin", false):
		body_text.text = "第二封劝降书是你的姻家送来的。他跪在城下，说福州那边答应了：只要你出城，老夫人和璥儿当天放回。
城头上有人在看你。"
		var burn := Button.new()
		burn.text = "焚书，斩使"
		burn.pressed.connect(func():
			GameState.siege_set("envoy_kin", true)
			GameState.siege_add("morale", 12)
			GameState.fame += 8
			GameState.hometown_tendency -= 5
			GameState.add_ledger_note("焚姻家书")
			log_msg("火盆里那封信烧得很快。城头上没有人说话。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(burn)
		var spare := Button.new()
		spare.text = "焚书，放他走"
		spare.pressed.connect(func():
			GameState.siege_set("envoy_kin", true)
			GameState.siege_add("morale", 6)
			GameState.fame += 4
			GameState.add_ledger_note("焚姻家书")
			log_msg("信烧了，人放了。他走出三十步又回头看了一眼，你没有再看他。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(spare)
	else:
		body_text.text = "城下没有人了。"

	choices_label.visible = true
	_add_leave_button("xinghua")


## 囊山设伏：数值判定，最多三阵。粮尽或三阵毕即城破。
func _siege_nangshan() -> void:
	if GameState.siege_get("grain") < GameState.SIEGE_GRAIN_PER_ROUND:
		_siege_fall("粮尽")
		return

	var rd := GameState.siege_get("round") + 1

	# 第三阵前的林华事件
	if rd == GameState.SIEGE_ROUNDS_MAX and not GameState.siege.get("lin_hua_sent", false):
		_siege_lin_hua()
		return

	GameState.siege_set("round", rd)
	GameState.set_flag("siege_fought")
	GameState.siege_add("grain", -GameState.SIEGE_GRAIN_PER_ROUND)

	var power := GameState.siege_power()
	var enemy := randf_range(600.0, 1400.0) * (1.0 + 0.25 * (rd - 1))
	var won := power >= enemy

	var txt := ""
	if won:
		GameState.siege_add("morale", 8)
		GameState.fame += 4
		var killed: int = int(GameState.siege_get("troops") * 0.08)
		GameState.siege_add("troops", -killed)
		txt = "山道两边全是石头。%s元兵退了。
城里有人开始说：也许能守。

折损 %d 人。" % [
			"石手军在山上，石头落下去的时候不用弓。" if str(GameState.siege.get("shishou", "")) == "kept" else "",
			killed,
		]
	else:
		GameState.siege_add("morale", -12)
		var killed2: int = int(GameState.siege_get("troops") * 0.22)
		GameState.siege_add("troops", -killed2)
		GameState.siege_add("wall", -20)
		txt = "伏没设成。元兵从背面上了山脊，石头砸下去砸的是自己人。
退回城里的时候少了 %d 人。" % killed2

	if GameState.siege_get("round") >= GameState.SIEGE_ROUNDS_MAX:
		_show_notice_dialog("囊山・第 %d 阵" % rd, "囊山" if won else "囊山失利", txt + "

粮快尽了。这是最后一阵。")
		_siege_fall("三阵毕")
		return

	_show_notice_dialog("囊山・第 %d 阵" % rd, "囊山" if won else "囊山失利", txt)


## 部将林华请出侦。史实不变——他仍然降。
func _siege_lin_hua() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・城头"
	var known := "lin_hua" in GameState.crew_history
	body_text.text = "部将林华上来请命：「大人，元兵在江口。我带五十人出去看看虚实。」"
	if known:
		body_text.text += "

你认得这张脸。二十年前他在林阿舶的船上系过缆，缆绳系得很好。"

	if known:
		var remind := Button.new()
		remind.text = "「你的缆绳系得好。你系的结，从来不松。」让他去"
		remind.pressed.connect(func():
			GameState.siege_set("lin_hua_sent", true)
			GameState.siege_add("morale", 5)
			GameState.set_flag("lin_hua_reminded")
			log_msg("他愣了一下，说大人还记得。城里人看见你认得出一个水手的名字，士气 +5。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(remind)

	var go := Button.new()
	go.text = "让他去"
	go.pressed.connect(func():
		GameState.siege_set("lin_hua_sent", true)
		log_msg("林华带着五十人出了北门。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(go)

	var stay := Button.new()
	stay.text = "不去。关城门，谁也不出"
	stay.pressed.connect(func():
		GameState.siege_set("lin_hua_sent", true)
		GameState.siege_add("grain", -30)
		GameState.set_flag("cao_opened")
		log_msg("城门关了七天。第八天夜里，通判曹澄孙开了东门。他后来说，是城里的人求他开的。这话可能是真的。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(stay)

	choices_label.visible = true
	_add_leave_button("xinghua")


## 城破 → 甲线结局「忠肃」
func _siege_fall(reason: String) -> void:
	var betrayal := ""
	if GameState.has_flag("cao_opened"):
		betrayal = "通判曹澄孙开了东门。"
	elif GameState.has_flag("lin_hua_reminded"):
		betrayal = "林华出去两天。第三天早上他回来了，后面跟着一万人。他在城下抬头看了你一眼，很快低下去。那个结松了。"
	else:
		betrayal = "林华出去两天。第三天早上他回来了，后面跟着一万人。"

	var text := "%s（%s）
城破的时候你在城楼上。白布还挂着。

他们没有动手，把你和家人押去了福州。董文炳的军帐里点着很多灯。他们让你跪，你不跪。有人来扯你的胳膊，有人骂，有人试着往你脸上打。

你用手指着自己的肚子：「此皆节义文章也。可相逼邪？」

从兴化出来那天起，你就没有吃东西。合沙渡口，你要了纸笔——

斗垒孤危势不支，书生守志定难移。
自经沟渎非吾事，臣死封疆是此时。
须信累囚堪衅鼓，未闻烈士竖降旗。
一门百指沦胥尽，唯有丹衷天地知。

杭州是正月到的。你说想去一个地方，他们允了。西湖边，岳飞的庙，庙门前的石阶有二十几级。你走到第十几级的时候，腿停了。
不是跌倒。是坐下来，然后靠着石阶。

福州的尼寺里，老夫人听完杭州的消息，很久没有说话。然后说：「吾与吾儿同死，又何恨哉。」
寺里的人后来说：有斯母，宜有是儿。

——
一百多年后，福州台江，泗洲。江边起了一座庙，匾上四个字：水部尚书。
渔民不知道尚书是什么官。他们只知道出海前拜一拜，海上会平安。
官船出洋，头号船请妈祖，二号船请尚书公。

供在里面的那个人，一辈子没出过海。" % [betrayal, reason]

	GameState.siege = {}
	_show_notice_dialog("忠肃", "兴化・景炎元年十二月", text, "忠肃")


## 士人线错过守城：1276 年兴化陷落时你不在城里。
## 这不是漏判，是这一局的答案——所以它必须有结局，而不是让陈文龙继续跑商到老。
func _check_absent_from_xinghua() -> bool:
	if GameState.is_ended() or not GameState.has_flag("renamed_wenlong"):
		return false
	if GameState.siege_open() or GameState.has_flag("siege_fought"):
		return false
	if Economy.war_status("xinghua") != "fallen":
		return false
	if not (Calendar.year > 1276 or (Calendar.year == 1276 and Calendar.month >= 12)):
		return false

	_show_notice_dialog(
		"未归", "兴化・景炎元年十二月",
		"消息是在别处听到的。

兴化城破了。城中兵不满千，守了四十天。城头上挂过一幅白布，八个字，来往的人都说见过。
部将林华出去侦敌，回来时后面跟着一万人。通判曹澄孙开的东门。

母亲黄氏和幼子璥被扣在福州一座尼寺里。有人说，只要城里那个人肯出来，当天就放。
城里那个人没有出来——因为城里没有那个人。

你姓陈，名文龙，字君贲，咸淳四年殿试第一，御笔改的名。这些年你走的是另一条路。
史书上后来写：是年，兴化陷，守臣不知所终。

——
一百多年后，福州台江，泗洲。江边没有庙。
渔民出海前拜妈祖，只拜妈祖。官船出洋，二号封舟空着。

这个世界少了一位海神。也没有多出几条回来的船。",
		"未归"
	)
	return true


## 终局后的港口页：不出海、不交易、不推进时间，只回顾与读档。
func _setup_ended_port() -> void:
	port_title.text = "%s・%s" % [port_title.text, GameState.ended]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 260)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)

	var head := Label.new()
	head.text = "航海札记"
	head.add_theme_font_size_override("font_size", 22)
	v.add_child(head)

	for line in GameState.epilogue_lines():
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(520, 0)
		l.add_theme_font_size_override("font_size", 14)
		v.add_child(l)

	left_facilities.add_child(panel)

	if GameState.ended_text != "":
		var review := Button.new()
		review.text = "重读结局"
		review.custom_minimum_size = Vector2(250, 44)
		review.pressed.connect(func():
			_show_notice_dialog(GameState.ended, GameState.ended_at, GameState.ended_text)
		)
		right_facilities.add_child(review)

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
	if GameState.is_ended():
		log_msg("【此局已终】%s。船不再出港了。" % GameState.ended)
		return
	if not Fleet.can_sail():
		var bad := Fleet.crew_shortfall()
		if bad.is_empty():
			log_msg("【无法出海】水手不足，船开不动。先去船屋雇人。")
		else:
			var parts := PackedStringArray()
			for b in bad:
				parts.append("%s（%d/%d）" % [b["name"], b["crew"], b["crew_min"]])
			log_msg("【无法出海】下列船水手不足：%s。先去船屋雇人。" % "、".join(parts))
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
	if _check_absent_from_xinghua():
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
	if GameState.is_ended():
		return
	if target_scene == CARD_HANJIANG:
		_on_hanjiang_escape()
		return
	if target_scene == CARD_RESIGN:
		_on_resign_1275()
		return
	if target_scene == CARD_YASHAN:
		_on_yashan()
		return
	if target_scene == CARD_GANGSHOU:
		_on_gangshou_end()
		return
	if target_scene.begins_with("siege_"):
		_on_siege_card(target_scene)
		return
	if target_scene in ["city_market", "city_yamen", "city_shipyard", "city_tavern"]:
		target_scene = current_scene_id + "_" + target_scene.trim_prefix("city_")
	elif target_scene == "city_residence" and current_scene_id == "xinghua":
		# 只有兴化的住宅是玉湖陈宅；别处仍是租来的下处（占位）
		target_scene = "xinghua_residence"
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
			"sea_tendency":
				GameState.sea_tendency += int(val)
			"scholar_tendency":
				GameState.scholar_tendency += int(val)
			"hometown_tendency":
				# 2026-09-04 解冻：键已接住，数据侧尚无写入点（兴化事件待做）
				GameState.hometown_tendency += int(val)
			"name":
				GameState.player_name = str(val)
			# ── 第一/二章（v0.3 时代）效果键，2026-09-04 起接入 ──
			"merchant_credit":
				GameState.merchant_credit += int(val)
			"network":
				GameState.network += int(val)
			"ledger_note", "cargo_loss":
				GameState.add_ledger_note(str(val))
			"supplies":
				Fleet.water = maxi(0, Fleet.water + int(val))
				Fleet.food = maxi(0, Fleet.food + int(val))
			"ship":
				# 正值修船、负值受损，作用于旗舰
				if int(val) < 0:
					Fleet.damage_fleet(float(-int(val)))
				elif not Fleet.ships.is_empty():
					var fs: Dictionary = Fleet.ships[0]
					fs["durability"] = minf(float(fs.get("max_durability", 100)), float(fs.get("durability", 0)) + float(val))
			"discovery":
				var did := GameManager.get_discovery_id_by_name(str(val))
				if did == "":
					push_warning("apply_effects: 未知发现物 %s" % str(val))
				elif GameState.record_discovery(did):
					log_msg("【勘见】%s 已记入发现录。" % GameManager.get_discovery_by_id(did).get("name", did))
			"cargo":
				# 剧情交付的货/文书（林阿舶押货、寺院经卷等），每种一件、无本钱；舱位不足则只记不装
				for gid in val:
					if GameManager.get_good_by_id(str(gid)).is_empty():
						push_warning("apply_effects: 未知货物 %s" % str(gid))
					elif not Fleet.add_cargo(str(gid), 1, 0.0):
						log_msg("【舱满】%s 装不下，暂寄岸上。" % GameManager.get_good_name(str(gid)))
			_:
				push_warning("apply_effects: 未知效果键 %s" % key)
	update_status_panel()
