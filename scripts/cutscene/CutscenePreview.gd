## 过场引擎预览场景（cutscene_engine 线自检用；游戏本体不引用）。
## 用法（参数放在 -- 之后）：
##   --cs=<id>                 播过场（可加 --from=<镜号> 从某一镜开始）
##   --chapter=<n>             播章节卡
##   --banner=<port_id>        播抵港横幅（--banner=all 依次播全部港口）
##   --backdrop=<res 路径>     看活背景；可加 --shimmer --grade=<名> --period=<秒> --breath=<幅度>
##   --data=<res 路径>         数据文件（默认 res://data/cutscenes.json，不存在回落 res://tools/art/cutscenes_fixture.json）
##   --list                    列出数据里的过场 id
##   --autoquit                播完退出（headless 自测用）
##   --click=<秒,秒…>          在这些时刻模拟一次左键点击（验证跳字 / 跳镜）
##   --esc=<秒>                在该时刻模拟 Esc
## 什么都不给：依次播数据里第一段过场。
extends Control

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const Seal := preload("res://scripts/cutscene/cs_seal.gd")

var _args: Dictionary = {}
var _data := ""
var _t := 0.0
var _clicks: Array = []
var _snaps: Array = []
var _perf_acc := 0.0
var _perf_frames := 0
var _perf_worst := 0.0
var _esc_at := -1.0
var _mock_bg: TextureRect
var _banner_queue: Array = []
var _banner_next := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_args = _parse(OS.get_cmdline_user_args())
	_data = str(_args.get("data", ""))
	if _data == "":
		_data = Kit.DEFAULT_DATA if FileAccess.file_exists(Kit.DEFAULT_DATA) else Kit.FIXTURE_DATA
	print("PREVIEW data=", _data, " headless=", Kit.is_headless())
	CutscenePlayer.verbose = true
	CutscenePlayer.debug_start_shot = int(_args.get("from", "0"))
	for s in str(_args.get("click", "")).split(",", false):
		_clicks.append(float(s))
	for s in str(_args.get("snap", "")).split(",", false):
		_snaps.append(float(s))
	_esc_at = float(_args.get("esc", "-1"))
	if _args.has("window"):
		# 自测画幅：--window=1600x720（expand 模式下画布随窗口比例变宽 / 变高）
		var wh := str(_args["window"]).split("x")
		if wh.size() == 2:
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		print("PREVIEW window=", get_window().size, " canvas=", get_viewport().get_visible_rect().size)
	if _args.has("list"):
		var d := Kit.load_json(_data)
		print("PREVIEW cutscenes: ", (d.get("cutscenes", {}) as Dictionary).keys())
		get_tree().quit(0)
		return
	if _args.has("backdrop"):
		_start_backdrop()
		return
	if _args.has("seals"):
		_start_seals()
		return
	_build_mock_game()
	if _args.has("chapter"):
		var c := ChapterCard.play(self, int(_args["chapter"]), _data)
		if c != null:
			c.finished.connect(_on_done.bind("chapter"))
	elif _args.has("banner"):
		var b := str(_args["banner"])
		if b == "all":
			var d := Kit.load_json(_data)
			_banner_queue = (d.get("port_banners", {}) as Dictionary).keys()
		else:
			_banner_queue = Array(b.split(",", false))
		_banner_next = 0.4
		if Kit.is_headless():
			var r := PortBanner.show_banner(self, str(_banner_queue[0]), _data)
			print("PREVIEW banner headless returned ", r)
			_on_done("banner")
	else:
		var id := str(_args.get("cs", ""))
		if id == "":
			var d := Kit.load_json(_data)
			var keys: Array = (d.get("cutscenes", {}) as Dictionary).keys()
			id = str(keys[0]) if not keys.is_empty() else "missing"
		var p := CutscenePlayer.play(self, id, _data)
		if p != null:
			p.finished.connect(_on_done.bind("cs:" + id))


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	for a in argv:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2)
		var eq := kv.find("=")
		if eq < 0:
			out[kv] = "1"
		else:
			out[kv.substr(0, eq)] = kv.substr(eq + 1)
	return out


## 模拟游戏画面：港口底图 + 左侧状态栏 + 顶部港名，用来看叠层与淡入淡出
func _build_mock_game() -> void:
	_mock_bg = TextureRect.new()
	_mock_bg.texture = Kit.load_texture(str(_args.get("under", "res://assets/bg_quanzhou_harbor.jpg")))
	_mock_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mock_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_mock_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_mock_bg)
	# --living：模拟集成后 Main._ready 里给底图挂活背景（顺带预热管线），用来量横幅 / 章节卡首次出现的卡顿
	if _args.has("living"):
		LivingBackdrop.attach(_mock_bg)
	var panel := ColorRect.new()
	panel.color = Color(0.1, 0.086, 0.07, 0.82)
	panel.position = Vector2.ZERO
	panel.size = Vector2(300, 720)
	add_child(panel)
	var lbl := Label.new()
	lbl.text = "（模拟游戏 UI）\n泉州・刺桐港\n金钱：5200\n名声：37"
	lbl.position = Vector2(24, 24)
	lbl.add_theme_font_override("font", Kit.body_font())
	lbl.add_theme_font_size_override("font_size", 18)
	add_child(lbl)


func _start_backdrop() -> void:
	var rect := TextureRect.new()
	rect.texture = Kit.load_texture(str(_args["backdrop"]))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	var opts := {"shimmer": _args.has("shimmer"), "grade": str(_args.get("grade", "neutral"))}
	if _args.has("period"):
		opts["period"] = float(_args["period"])
	if _args.has("breath"):
		opts["breath"] = float(_args["breath"])
	if _args.has("vignette"):
		opts["vignette"] = float(_args["vignette"])
	if _args.has("grain"):
		opts["grain"] = float(_args["grain"])
	if _args.has("pan"):
		opts["pan"] = float(_args["pan"])
	var d := LivingBackdrop.attach(rect, opts)
	print("PREVIEW backdrop attached=", d != null, " opts=", opts)
	if Kit.is_headless():
		LivingBackdrop.detach(rect)
		_on_done("backdrop")


## --seals：印章样张。上半宣纸、下半压在暗色油画上；程序印（白文 / 朱文）与 UI 线成品印并排，按显示尺寸 1:1 看崩边与字口
func _start_seals() -> void:
	var paper := ColorRect.new()
	paper.color = Kit.C_XUAN
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	var dark := TextureRect.new()
	dark.texture = Kit.load_texture("res://assets/bg_hakata.jpg")
	dark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	dark.position = Vector2(0, 360)
	dark.size = Vector2(1280, 360)
	dark.modulate = Color(0.55, 0.5, 0.45)
	add_child(dark)
	var rows := [
		[["北", 58.0, "baiwen", 0.0, false], ["东", 58.0, "baiwen", 0.0, false], ["南", 58.0, "baiwen", 0.0, false], ["西", 58.0, "baiwen", 0.0, false],
			["乙卯", 44.0, "baiwen", 0.0, false], ["泊", 34.0, "baiwen", 0.0, false], ["立志", 38.0, "baiwen", 0.0, true], ["立志", 38.0, "baiwen", 0.0, false],
			["立志", 38.0, "zhuwen", 0.0, true], ["宋鬼忠肃", 40.0, "baiwen", 0.0, false]],
		[["北", 58.0, "baiwen", 0.9, false], ["东", 58.0, "baiwen", 0.9, false], ["南", 58.0, "baiwen", 0.9, false], ["西", 58.0, "baiwen", 0.9, false],
			["乙卯", 44.0, "baiwen", 0.9, false], ["泊", 34.0, "zhuwen", 0.9, false], ["立志", 38.0, "baiwen", 0.9, true], ["立志", 38.0, "baiwen", 0.0, false],
			["海商", 38.0, "zhuwen", 0.9, true], ["宋鬼忠肃", 40.0, "zhuwen", 0.9, false]],
	]
	for ri in range(rows.size()):
		var x := 40.0
		var k := 0
		for spec: Array in rows[ri]:
			var s: Control = Seal.new()
			s.configure(str(spec[0]), {"cell": spec[1], "style": spec[2], "hollow_alpha": spec[3], "procedural": spec[4],
				"seed": fmod(float(k) * 0.37 + float(ri) * 0.11, 1.0), "tilt": 0.0})
			add_child(s)
			s.position = Vector2(x, 180.0 + 360.0 * ri - s.size.y * 0.5)
			s.advance(2.0)
			x += s.size.x + 36.0
			k += 1
	print("PREVIEW seals built")
	if Kit.is_headless():
		_on_done("seals")


func _process(delta: float) -> void:
	_t += delta
	if _args.has("perf"):
		_perf_acc += delta
		_perf_frames += 1
		_perf_worst = maxf(_perf_worst, delta)
		# 单帧超过 30 ms 的都记下时刻（看卡顿落在黑场里还是画面上）
		if delta > 0.03 and _t > 0.25:
			print("PREVIEW slow_frame t=%.2f ms=%.1f" % [_t, delta * 1000.0])
		if _perf_acc >= 2.0:
			print("PREVIEW perf fps=%.1f worst_frame_ms=%.1f process_ms=%.2f draw_calls=%d video_mem_mb=%.0f" % [
				float(_perf_frames) / _perf_acc, _perf_worst * 1000.0,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
			_perf_acc = 0.0
			_perf_frames = 0
			_perf_worst = 0.0
	# --snap=<秒,…>：整张画布存图（窗口比例不是 16:9 时 Movie Maker 只截左上 1280×720，用这个看全貌）
	if not _snaps.is_empty() and _t >= float(_snaps[0]) and not Kit.is_headless():
		var at := float(_snaps.pop_front())
		var img := get_viewport().get_texture().get_image()
		var dir := str(_args.get("snapdir", "/tmp"))
		var path := "%s/snap_%05.2f.png" % [dir, at]
		img.save_png(path)
		print("PREVIEW snap ", path, " ", img.get_size())
	var hit: Array = []
	for c in _clicks:
		if _t >= float(c):
			hit.append(c)
	for c in hit:
		_clicks.erase(c)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = Vector2(640, 360)
		Input.parse_input_event(ev)
		print("PREVIEW click at ", snappedf(_t, 0.01))
	if _esc_at >= 0.0 and _t >= _esc_at:
		_esc_at = -1.0
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.pressed = true
		Input.parse_input_event(k)
		print("PREVIEW esc at ", snappedf(_t, 0.01))
	if not _banner_queue.is_empty() and not Kit.is_headless() and _t >= _banner_next:
		var pid := str(_banner_queue.pop_front())
		var b := PortBanner.show_banner(self, pid, _data)
		print("PREVIEW banner ", pid, " ok=", b != null)
		_banner_next = _t + 2.9
		if _banner_queue.is_empty() and b != null:
			b.finished.connect(_on_done.bind("banner"))


func _on_done(what: String) -> void:
	print("PREVIEW_FINISHED ", what, " t=", snappedf(_t, 0.01))
	if _args.has("autoquit"):
		get_tree().create_timer(0.8 if not Kit.is_headless() else 0.0).timeout.connect(func() -> void: get_tree().quit(0))
