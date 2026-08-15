class_name CutscenePlayer extends CanvasLayer

## P7-X CutscenePlayer
## 职责：播全屏 CG + 字幕 + 淡入淡出；可跳过；可多分镜。
## 不操作 GameState，通过信号 finished 通知调用方。
## CG 加载复用 AssetPlaceholder.load_texture（已带缓存+降级）。
## 4 钩子：port_arrival（由 Main 直调 play）/ chapter_change（监听 story.chapter_unlocked）
##       / rank_up（监听 career.rank_changed，P7-C）/ ending（由 P7-E EndingResolver 直调 play）。

signal finished(cutscene_id: String)
signal started(cutscene_id: String)

const FADE_DURATION := 0.4
const PANEL_DURATION := 2.5
const PANEL_FADE := 0.3
const LAYER := 100

@onready var _bg: TextureRect = $Bg
@onready var _caption: RichTextLabel = $Caption
@onready var _skip_hint: Label = $SkipHint

var _data: Dictionary = {}
var _playing: bool = false
var _current_id: String = ""
var _tween: Tween = null
var _panels: Array = []
var _panel_index: int = 0
## 排队：章三收束过场与结局 CG 同帧触发时串播
var _queue: Array[String] = []

func _ready() -> void:
	layer = LAYER
	# P8-4: 壳层托管后即使 Main 禁用仍可播
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_load_data()
	_connect_signals()
	if _skip_hint:
		_skip_hint.text = "按 空格 或 点击 跳过"

## 公开 API：播放过场。cutscene_id 不存在则静默返回（降级，不崩）。
## 正在播放时入队，结束后自动串播（章三收束 + 结局可同帧）。
func play(cutscene_id: String) -> bool:
	var id := cutscene_id.strip_edges()
	if id == "":
		return false
	var entry: Dictionary = _data.get(id, {})
	if entry.is_empty():
		return false
	if _playing:
		if id != _current_id and id not in _queue:
			_queue.append(id)
		return id == _current_id or id in _queue
	_start_play(id, entry)
	return true


func is_playing() -> bool:
	return _playing


func get_current_id() -> String:
	return _current_id

## 跳过当前过场（并清空排队，避免连跳多段）
func skip() -> void:
	if not _playing:
		return
	_queue.clear()
	_end()

## 查询某 hook+id 是否有对应过场（供调用方决定是否播）
func has_cutscene(hook: String, id: String) -> bool:
	return get_cutscene_id_for(hook, id) != ""

## 公开 API：根据 hook+id 查 cutscene id。找不到返回 ""。
## 替代内部 _find_by_hook 暴露（执行模型自洽，不暴露内部细节）。
func get_cutscene_id_for(hook: String, id: String) -> String:
	return _find_by_hook(hook, id)

## ── 内部 ────────────────────────────────────────────────

func _play_single(entry: Dictionary) -> void:
	var cg_path: String = AssetPlaceholder.get_background_path(entry.get("cg_alias", ""))
	var tex: Texture2D = AssetPlaceholder.load_texture(cg_path)
	if _bg:
		_bg.texture = tex
	if _caption:
		_caption.text = entry.get("caption", "")
	_fade_in_then_wait(FADE_DURATION, PANEL_DURATION)

func _play_panel(panel: Dictionary) -> void:
	var cg_path: String = AssetPlaceholder.get_background_path(panel.get("cg_alias", ""))
	var tex: Texture2D = AssetPlaceholder.load_texture(cg_path)
	if _bg:
		_bg.texture = tex
	if _caption:
		_caption.text = panel.get("caption", "")
	var dur: float = float(panel.get("duration", PANEL_DURATION))
	_fade_in_then_wait(FADE_DURATION, dur)

func _fade_in_then_wait(fade_in: float, wait: float) -> void:
	if _tween:
		_tween.kill()
	if _bg:
		_bg.modulate.a = 0.0
	if _caption:
		_caption.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_bg, "modulate:a", 1.0, fade_in)
	_tween.parallel().tween_property(_caption, "modulate:a", 1.0, fade_in)
	_tween.tween_interval(wait)
	_tween.tween_callback(_on_panel_done)

func _on_panel_done() -> void:
	_panel_index += 1
	if _panel_index < _panels.size():
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(_bg, "modulate:a", 0.0, PANEL_FADE)
		_tween.tween_callback(func(): _play_panel(_panels[_panel_index]))
	else:
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(_bg, "modulate:a", 0.0, FADE_DURATION)
		_tween.parallel().tween_property(_caption, "modulate:a", 0.0, FADE_DURATION)
		_tween.tween_callback(_end)

func _start_play(cutscene_id: String, entry: Dictionary) -> void:
	_current_id = cutscene_id
	_panels = entry.get("panels", [])
	_panel_index = 0
	_playing = true
	visible = true
	if _skip_hint:
		_skip_hint.visible = true
	started.emit(cutscene_id)
	if _panels.is_empty():
		_play_single(entry)
	else:
		_play_panel(_panels[0])


func _end() -> void:
	if _tween:
		_tween.kill()
	_playing = false
	visible = false
	if _skip_hint:
		_skip_hint.visible = false
	var id: String = _current_id
	_current_id = ""
	finished.emit(id)
	# 串播队列中的下一段
	if not _queue.is_empty():
		var next_id: String = str(_queue.pop_front())
		var entry: Dictionary = _data.get(next_id, {})
		if not entry.is_empty():
			_start_play(next_id, entry)

func _load_data() -> void:
	# 读 ResourcePaths.DATA_CUTSCENES，JSON 解析，缓存到 _data {id: entry}
	# 文件缺失/解析失败 → _data = {}，play() 静默降级
	var path: String = ResourcePaths.DATA_CUTSCENES
	if not FileAccess.file_exists(path):
		_data = {}
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_data = {}
		return
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_data = {}
		return
	var root: Variant = json.data
	if not (root is Dictionary):
		_data = {}
		return
	var cutscenes_raw: Variant = (root as Dictionary).get("cutscenes", {})
	if not (cutscenes_raw is Dictionary):
		_data = {}
		return
	_data = (cutscenes_raw as Dictionary).duplicate(true)

func _connect_signals() -> void:
	# 章节切换：GameState.story.chapter_unlocked → _on_chapter_unlocked
	if GameState == null:
		return
	var story_obj: Variant = GameState.get("story")
	if story_obj != null and story_obj.has_signal("chapter_unlocked"):
		story_obj.chapter_unlocked.connect(_on_chapter_unlocked)
	# 升秩：P7-C 就绪后连接（try，不阻塞）
	var career_obj: Variant = GameState.get("career")
	if career_obj != null and career_obj.has_signal("rank_changed"):
		career_obj.rank_changed.connect(_on_rank_changed)
	# 港口抵达：由 Main._show_port_intro_if_needed 直接调 play()，不走信号
	# 结局：P7-E EndingResolver 直接调 play()，不走信号

func _on_chapter_unlocked(chapter_id: String) -> void:
	var cs_id: String = _find_by_hook("chapter_change", chapter_id)
	if cs_id != "":
		play(cs_id)

func _on_rank_changed(new_rank: int) -> void:
	var cs_id: String = _find_by_hook("rank_up", str(new_rank))
	if cs_id != "":
		play(cs_id)

func _find_by_hook(hook: String, id: String) -> String:
	var match_field: String = ""
	if hook == "port_arrival":
		match_field = "port_id"
	elif hook == "chapter_change":
		match_field = "chapter_id"
	elif hook == "rank_up":
		match_field = "rank"
	elif hook == "ending":
		match_field = "ending_id"
	else:
		return ""
	for key in _data:
		var e: Dictionary = _data[key]
		if e.get("hook", "") != hook:
			continue
		var val: Variant = e.get(match_field, "")
		if match_field == "rank":
			# JSON 解析把数字当 float；按数值比较
			if is_equal_approx(float(str(val)), float(id)):
				return str(key)
		else:
			if str(val) == id:
				return str(key)
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.physical_keycode == KEY_SPACE and key_event.is_pressed():
			skip()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed():
		skip()
		get_viewport().set_input_as_handled()
