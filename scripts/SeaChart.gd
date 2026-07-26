extends Control
## 海图。点选目的地 → 按日推进 → 逐日抽事件 → 到港。
## 实时操船（WorldMap.tscn）降级为海战/风涛时切入的战术场景。

var origin_port: String = ""
var selected_port: String = ""

## 航行状态
var sailing: bool = false
var remaining_li: float = 0.0
var total_li: float = 0.0
var course_bearing: float = 0.0
var days_elapsed: int = 0
var pending_event: Dictionary = {}

# UI
var status_label: RichTextLabel
var port_list: VBoxContainer
var detail_box: VBoxContainer
var log_label: RichTextLabel
var sail_button: Button
var event_panel: PanelContainer
var event_title: Label
var event_text: RichTextLabel
var event_actions: HBoxContainer


func _ready() -> void:
	origin_port = GameState.last_port
	selected_port = ""
	_build_ui()
	_refresh_ports()
	_refresh_status()
	_log("【发舶】自 %s 起锚。%s。" % [GameManager.get_port_name(origin_port), Calendar.get_monsoon_desc()])


# ══════════════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var bg_path := "res://assets/bg_world_map.jpg"
	if FileAccess.file_exists(bg_path):
		var tex = load(bg_path) as Texture2D
		if tex == null:
			var img = Image.load_from_file(bg_path)
			if img:
				tex = ImageTexture.create_from_image(img)
		bg.texture = tex
	bg.modulate = Color(0.55, 0.6, 0.7, 1.0)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ── 左：状态 ──
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(left)
	var left_m := MarginContainer.new()
	_set_margins(left_m, 10)
	left.add_child(left_m)
	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	left_m.add_child(status_label)

	# ── 中：港口与航段 ──
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(center)
	var center_m := MarginContainer.new()
	_set_margins(center_m, 12)
	center.add_child(center_m)
	var center_v := VBoxContainer.new()
	center_v.add_theme_constant_override("separation", 8)
	center_m.add_child(center_v)

	var head := Label.new()
	head.text = "海　图"
	head.add_theme_font_size_override("font_size", 26)
	center_v.add_child(head)

	var hint := Label.new()
	hint.text = "选定去处，量过风信与水粮，再决定发不发舶。"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	center_v.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	center_v.add_child(scroll)
	port_list = VBoxContainer.new()
	port_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(port_list)

	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	center_v.add_child(detail_box)

	sail_button = Button.new()
	sail_button.text = "发　舶"
	sail_button.custom_minimum_size = Vector2(0, 48)
	sail_button.add_theme_font_size_override("font_size", 20)
	sail_button.disabled = true
	sail_button.pressed.connect(_on_sail_pressed)
	center_v.add_child(sail_button)

	var back := Button.new()
	back.text = "回港（不出海）"
	back.pressed.connect(_return_to_port)
	center_v.add_child(back)

	# ── 右：航海日志 ──
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(right)
	var right_m := MarginContainer.new()
	_set_margins(right_m, 10)
	right.add_child(right_m)
	var right_v := VBoxContainer.new()
	right_m.add_child(right_v)
	var log_head := Label.new()
	log_head.text = "航海日志"
	log_head.add_theme_font_size_override("font_size", 18)
	right_v.add_child(log_head)
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_v.add_child(log_scroll)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.custom_minimum_size = Vector2(272, 0)
	log_scroll.add_child(log_label)

	# ── 事件浮层 ──
	_build_event_panel()


func _build_event_panel() -> void:
	event_panel = PanelContainer.new()
	event_panel.set_anchors_preset(Control.PRESET_CENTER)
	event_panel.custom_minimum_size = Vector2(560, 0)
	event_panel.position = Vector2(360, 200)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	st.border_width_left = 2
	st.border_width_top = 2
	st.border_width_right = 2
	st.border_width_bottom = 2
	st.border_color = Color(0.6, 0.5, 0.3)
	st.corner_radius_top_left = 8
	st.corner_radius_top_right = 8
	st.corner_radius_bottom_left = 8
	st.corner_radius_bottom_right = 8
	event_panel.add_theme_stylebox_override("panel", st)
	event_panel.visible = false
	add_child(event_panel)

	var m := MarginContainer.new()
	_set_margins(m, 18)
	event_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	event_title = Label.new()
	event_title.add_theme_font_size_override("font_size", 24)
	v.add_child(event_title)

	event_text = RichTextLabel.new()
	event_text.bbcode_enabled = true
	event_text.fit_content = true
	event_text.custom_minimum_size = Vector2(520, 60)
	v.add_child(event_text)

	event_actions = HBoxContainer.new()
	event_actions.add_theme_constant_override("separation", 8)
	v.add_child(event_actions)


func _panel_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.08, 0.11, 0.88)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	return st


func _set_margins(m: MarginContainer, v: int) -> void:
	m.add_theme_constant_override("margin_left", v)
	m.add_theme_constant_override("margin_right", v)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)


# ══════════════════════════════════════════════════════
#  刷新
# ══════════════════════════════════════════════════════

func _refresh_status() -> void:
	var supply_d := Fleet.supply_days()
	var supply_color := "white"
	if supply_d <= 3:
		supply_color = "red"
	elif supply_d <= 7:
		supply_color = "yellow"

	var t := "[b]%s[/b]\n%s\n\n" % [Calendar.get_date_string(), Calendar.get_monsoon_desc()]
	if sailing:
		var pct := 0.0
		if total_li > 0.0:
			pct = clampf((total_li - remaining_li) / total_li, 0.0, 1.0)
		t += "[color=aqua]航行中　第 %d 日[/color]\n已行 %d%%\n余程 %d 里\n\n" % [days_elapsed, int(pct * 100), int(remaining_li)]
	t += "金钱：%d\n名声：%d\n\n" % [GameState.money, GameState.fame]
	t += "[u]舰队[/u]\n船数：%d　水手：%d\n舱位：%d / %d 料\n耐久：%d / %d\n士气：%d\n" % [
		Fleet.ships.size(), Fleet.total_crew(),
		int(Fleet.used_capacity()), int(Fleet.total_capacity()),
		int(Fleet.total_durability()), int(Fleet.total_max_durability()),
		Fleet.morale,
	]
	t += "水：%d　粮：%d　[color=%s]（足 %d 日）[/color]\n" % [Fleet.water, Fleet.food, supply_color, supply_d]
	status_label.text = t


func _refresh_ports() -> void:
	for c in port_list.get_children():
		c.queue_free()

	for p in GameManager.unlocked_ports():
		var pid: String = p.get("id", "")
		if pid == origin_port:
			continue
		# 兴化与海口是陆路可达的剧情点，不列入海图
		if p.get("depth", 0) <= 0:
			continue

		var plan := Voyage.plan(origin_port, pid)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = (pid == selected_port)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 34)

		var known := "" if Voyage.is_known_route(origin_port, pid) else "　[生路]"
		btn.text = "%s　%d里　%s　约 %d 日%s" % [
			p.get("name", pid), int(plan["distance"]), plan["wind_desc"], plan["days"], known,
		]
		if not plan["supply_ok"]:
			btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		elif plan["wind_desc"] == "顺风":
			btn.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))

		btn.pressed.connect(_on_port_selected.bind(pid))
		port_list.add_child(btn)


func _on_port_selected(pid: String) -> void:
	selected_port = pid
	_refresh_ports()
	_refresh_detail()


func _refresh_detail() -> void:
	for c in detail_box.get_children():
		c.queue_free()
	if selected_port == "":
		sail_button.disabled = true
		return

	var plan := Voyage.plan(origin_port, selected_port)
	var lines := [
		"目的：%s" % GameManager.get_port_name(selected_port),
		"航程：%d 里　方位 %d°" % [int(plan["distance"]), int(plan["bearing"])],
		"风信：%s（日速 %d 里）" % [plan["wind_desc"], int(plan["speed"])],
		"预计：%d 日　水粮足 %d 日" % [plan["days"], plan["supply_days"]],
	]
	for l in lines:
		var lbl := Label.new()
		lbl.text = l
		detail_box.add_child(lbl)

	if not Voyage.is_known_route(origin_port, selected_port):
		var w := Label.new()
		w.text = "此非熟路，海图上只有传闻，途中易生变故。"
		w.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
		detail_box.add_child(w)

	if not plan["supply_ok"]:
		var w := Label.new()
		w.text = "水粮不足以支撑此程——半途必要死人。"
		w.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		detail_box.add_child(w)

	sail_button.disabled = false


func _log(text: String) -> void:
	log_label.text = text + "\n\n" + log_label.text


# ══════════════════════════════════════════════════════
#  航行
# ══════════════════════════════════════════════════════

func _on_sail_pressed() -> void:
	if selected_port == "" or sailing:
		return
	total_li = Voyage.distance_li(origin_port, selected_port)
	remaining_li = total_li
	course_bearing = Voyage.bearing(origin_port, selected_port)
	days_elapsed = 0
	sailing = true
	Fleet.at_sea = true

	sail_button.disabled = true
	for c in port_list.get_children():
		c.disabled = true

	_log("[color=aqua]启程往 %s，航程 %d 里。[/color]" % [GameManager.get_port_name(selected_port), int(total_li)])
	_sail_next_day()


func _sail_next_day() -> void:
	if not sailing:
		return

	GameManager.advance_days(1)
	days_elapsed += 1

	var event := Voyage.roll_day_event(course_bearing)
	var kind: int = event.get("kind", Voyage.EventKind.NONE)
	var wf := Voyage.wind_factor(course_bearing)
	var progress := Fleet.fleet_speed() * wf

	if kind == Voyage.EventKind.CALM:
		progress = 0.0
	elif kind == Voyage.EventKind.CURRENT:
		progress *= 1.5

	remaining_li -= progress
	_refresh_status()

	# 补给见底的警告
	if Fleet.supply_days() <= 0 and Fleet.total_crew() > 0:
		_log("[color=red]第 %d 日・水粮已尽，舱里开始有人病倒。[/color]" % days_elapsed)

	if kind != Voyage.EventKind.NONE:
		_show_event(event)
		return

	if remaining_li <= 0.0:
		_arrive()
		return

	# 无事之日直接推进下一天
	_sail_next_day()


func _show_event(event: Dictionary) -> void:
	pending_event = event
	event_title.text = "第 %d 日・%s" % [days_elapsed, event.get("title", "事")]
	event_text.text = event.get("text", "")
	_log("第 %d 日・%s" % [days_elapsed, event.get("title", "")])

	for c in event_actions.get_children():
		c.queue_free()

	var kind: int = event.get("kind", Voyage.EventKind.NONE)
	if kind == Voyage.EventKind.PIRATE:
		_add_event_action("迎战", _on_fight_pirates)
		_add_event_action("扬帆逃走", _on_flee_pirates)
		_add_event_action("献上买路财", _on_pay_pirates)
	elif kind == Voyage.EventKind.DISCOVERY:
		_add_event_action("绕过去看看（费 1 日）", _on_investigate_discovery)
		_add_event_action("不理会，继续航行", _on_event_continue)
	else:
		_add_event_action("继续航行", _on_event_continue)

	event_panel.visible = true


func _add_event_action(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	event_actions.add_child(b)


func _on_event_continue() -> void:
	event_panel.visible = false
	pending_event = {}
	if remaining_li <= 0.0:
		_arrive()
	else:
		_sail_next_day()


# ── 海盗 ────────────────────────────────────────────

## 舰队战力：耐久 + 水手 + 炮位，计入士气
func _fleet_power() -> float:
	var cannons := 0
	for s in Fleet.ships:
		cannons += int(Fleet.ship_def(s.get("type", "")).get("cannon_slots", 0))
	return (Fleet.total_durability() * 0.5 + Fleet.total_crew() * 4.0 + cannons * 25.0) * Fleet.morale_factor()


func _on_fight_pirates() -> void:
	event_panel.visible = false
	var power := _fleet_power()
	var enemy := randf_range(180.0, 520.0)
	if power >= enemy:
		var spoil := int(randf_range(150, 600))
		GameState.add_money(spoil)
		GameState.fame += 3
		var dmg := enemy * 0.06
		Fleet.damage_fleet(dmg)
		Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 5)
		_log("[color=lime]击退海盗，夺得财货 %d 钱。船体受损 %d。[/color]" % [spoil, int(dmg)])
	else:
		var dmg := enemy * 0.16
		Fleet.damage_fleet(dmg)
		Fleet.morale = maxi(0, Fleet.morale - 12)
		var lost := Fleet.lose_cargo_ratio(0.25)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		_log("[color=red]接舷失利，被夺去部分货物。%s船体受损 %d。[/color]" % [lost_str, int(dmg)])
	_refresh_status()
	_after_combat()


func _on_flee_pirates() -> void:
	event_panel.visible = false
	# 逃跑成败取决于航速与士气
	var chance := clampf(Fleet.fleet_speed() / 220.0, 0.25, 0.9)
	if randf() < chance:
		remaining_li += Fleet.fleet_speed() * 0.5  # 绕路
		_log("[color=lime]转舵抢上风头，把那两条快船甩在了后面（绕了些路）。[/color]")
	else:
		var lost := Fleet.lose_cargo_ratio(0.18)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		Fleet.damage_fleet(30.0)
		_log("[color=red]没能甩脱，被追上跳帮，抢走了货。%s[/color]" % lost_str)
	_refresh_status()
	_after_combat()


func _on_pay_pirates() -> void:
	event_panel.visible = false
	var toll: int = maxi(100, int(GameState.money * 0.15))
	if GameState.spend_money(toll):
		Fleet.morale = maxi(0, Fleet.morale - 4)
		_log("[color=yellow]递过去 %d 钱买路。对方点了点数目，掉头走了。[/color]" % toll)
	else:
		var lost := Fleet.lose_cargo_ratio(0.3)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		_log("[color=red]拿不出买路钱，他们自己动手搬空了半个货舱。%s[/color]" % lost_str)
	_refresh_status()
	_after_combat()


func _after_combat() -> void:
	pending_event = {}
	if Fleet.total_durability() <= 0.0:
		_sink()
		return
	if remaining_li <= 0.0:
		_arrive()
	else:
		_sail_next_day()


# ── 发现物 ──────────────────────────────────────────

func _on_investigate_discovery() -> void:
	event_panel.visible = false
	GameManager.advance_days(1)
	days_elapsed += 1
	var did: String = pending_event.get("discovery_id", "")
	var d := GameManager.get_discovery_by_id(did)
	if did != "" and not (did in GameState.discoveries_reported):
		GameState.discoveries_reported.append(did)
		GameState.fame += int(d.get("value", 50)) / 10
		_log("[color=lime]近岸细看，果然是%s。记入海图，名声+%d。[/color]" % [
			d.get("name", "旧泊地"), int(d.get("value", 50)) / 10,
		])
	else:
		_log("绕过去看了一圈，与海图上所记并无出入。")
	_refresh_status()
	_on_event_continue()


# ── 结束 ────────────────────────────────────────────

func _arrive() -> void:
	sailing = false
	Fleet.at_sea = false
	GameState.last_port = selected_port
	_log("[color=aqua]历 %d 日，抵 %s。[/color]" % [days_elapsed, GameManager.get_port_name(selected_port)])

	event_title.text = "到　港"
	event_text.text = "历 %d 日海路，%s 的岸线终于在雾里显出来。\n\n%s" % [
		days_elapsed,
		GameManager.get_port_name(selected_port),
		"舱内尚存水 %d、粮 %d，士气 %d。" % [Fleet.water, Fleet.food, Fleet.morale],
	]
	for c in event_actions.get_children():
		c.queue_free()
	_add_event_action("下船入港", _return_to_port)
	event_panel.visible = true


func _sink() -> void:
	sailing = false
	Fleet.at_sea = false
	Fleet.clear_cargo()
	event_title.text = "沉　没"
	event_text.text = "船身裂开，海水灌进货舱。等你再睁眼时，已被人捞上一条渔船，货与船都没了。"
	for c in event_actions.get_children():
		c.queue_free()
	_add_event_action("……", func():
		# 保底：留一条小艍船，避免死档
		Fleet.ships.clear()
		Fleet.add_ship("sampan", "借来的小艍")
		Fleet.water = 20
		Fleet.food = 20
		Fleet.morale = 50
		GameState.last_port = origin_port
		_return_to_port()
	)
	event_panel.visible = true


func _return_to_port() -> void:
	Fleet.at_sea = false
	GameState.set_flag("return_to_port")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
