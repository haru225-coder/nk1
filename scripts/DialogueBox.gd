extends Control

signal sequence_finished
signal line_shown(beat: Dictionary)
signal active_changed(is_active: bool)

const CHAR_INTERVAL_SPEECH := 0.02
const CHAR_INTERVAL_NARRATION := 0.012
const BLIP_EVERY_N_CHARS := 2

enum DisplayMode { SEQUENCE, PERSISTENT }

@onready var click_catcher: ColorRect = $ClickCatcher
@onready var dim_layer: ColorRect = $DimLayer
@onready var frame_root: NinePatchRect = $Frame
@onready var portrait_panel: PanelContainer = $Frame/Margin/HBox/PortraitPanel
@onready var portrait: TextureRect = $Frame/Margin/HBox/PortraitPanel/PortraitStack/Portrait
@onready var portrait_placeholder: Label = $Frame/Margin/HBox/PortraitPanel/PortraitStack/Placeholder
@onready var name_plate: PanelContainer = $Frame/Margin/HBox/PortraitPanel/PortraitStack/NamePlate
@onready var speaker_label: Label = $Frame/Margin/HBox/PortraitPanel/PortraitStack/NamePlate/SpeakerName
@onready var stage_direction_label: Label = $Frame/Margin/HBox/TextPanel/StageDirection
@onready var dialogue_label: Label = $Frame/Margin/HBox/TextPanel/DialogueText
@onready var hint_label: Label = $Frame/Margin/HBox/TextPanel/HintRow/HintLabel
@onready var actions_slot: HBoxContainer = $Frame/Margin/HBox/TextPanel/ActionsSlot
@onready var blip_player: AudioStreamPlayer = $BlipPlayer

var _beats: Array = []
var _index: int = 0
var _full_text: String = ""
var _char_index: int = 0
var _type_accum: float = 0.0
var _char_interval: float = CHAR_INTERVAL_NARRATION
var _is_typing: bool = false
var _is_speech_line: bool = false
var _portrait_cache: Dictionary = {}
var _hint_pulse: float = 0.0
var _display_mode: DisplayMode = DisplayMode.SEQUENCE
var _is_active: bool = false
var _enter_tween: Tween
var _exit_tween: Tween
var _last_speaker: String = ""
var _frame_offset_top_rest: float = -392.0
var _frame_offset_bottom_rest: float = 0.0

func _ready() -> void:
	visible = false
	hint_label.visible = false
	dim_layer.modulate.a = 0.0
	name_plate.visible = false
	_frame_offset_top_rest = frame_root.offset_top
	_frame_offset_bottom_rest = frame_root.offset_bottom
	click_catcher.gui_input.connect(_on_click_catcher_input)
	blip_player.stream = _make_blip_stream()

func get_actions_slot() -> HBoxContainer:
	return actions_slot

func _process(delta: float) -> void:
	if _is_typing:
		_type_accum += delta
		while _is_typing and _type_accum >= _char_interval and _char_index < _full_text.length():
			_type_accum -= _char_interval
			_char_index += 1
			dialogue_label.text = _full_text.substr(0, _char_index)
			
			# 标点符号额外停顿，模拟口语自然节奏
			var current_char := _full_text.substr(_char_index - 1, 1)
			if current_char in ["，", "。", "！", "？", "；", "：", "…"]:
				_type_accum -= _char_interval * 4.0
				
			if _is_speech_line and _char_index % BLIP_EVERY_N_CHARS == 0:
				_play_blip()
		if _char_index >= _full_text.length():
			_is_typing = false
			_on_typing_finished()
		return

	if hint_label.visible:
		_hint_pulse += delta * 5.5
		var pulse := 0.5 + 0.5 * sin(_hint_pulse)
		hint_label.scale = Vector2.ONE * (0.88 + 0.22 * pulse)
		hint_label.modulate.a = 0.35 + 0.65 * pulse

func start_sequence(beats: Array) -> void:
	_display_mode = DisplayMode.SEQUENCE
	actions_slot.visible = false
	_beats = beats.duplicate()
	_index = 0
	_last_speaker = ""
	if _beats.is_empty():
		_deactivate()
		sequence_finished.emit()
		return
	_activate()
	_show_current_line()

func show_single_beat(beat: Dictionary) -> void:
	start_sequence([beat])

func show_persistent(display_name: String, text: String, avatar_path: String = "") -> void:
	_display_mode = DisplayMode.PERSISTENT
	_beats.clear()
	_index = 0
	if not _is_active:
		_activate()
	else:
		visible = true
	var formatted := DialogueParser.format_speech(text)
	_apply_speech_presentation(display_name, "", avatar_path)
	_full_text = formatted
	_is_speech_line = true
	_char_index = 0
	_type_accum = 0.0
	_char_interval = CHAR_INTERVAL_SPEECH
	dialogue_label.text = ""
	_is_typing = _full_text.length() > 0
	_show_hint(false)
	actions_slot.visible = true

func hide_dialogue() -> void:
	_deactivate()

func _on_click_catcher_input(event: InputEvent) -> void:
	if not visible:
		return
	if _try_advance_input(event):
		click_catcher.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _try_advance_input(event):
		get_viewport().set_input_as_handled()

func _try_advance_input(event: InputEvent) -> bool:
	if _display_mode == DisplayMode.PERSISTENT and actions_slot.visible:
		return false
	if not (event is InputEventKey or event is InputEventMouseButton):
		return false
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return false
	elif event is InputEventKey:
		if not event.pressed or event.keycode not in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			return false
	_on_advance()
	return true

func _on_advance() -> void:
	if _is_typing:
		_char_index = _full_text.length()
		dialogue_label.text = _full_text
		_is_typing = false
		_on_typing_finished()
		_play_advance_blip()
		return
	if _display_mode == DisplayMode.PERSISTENT:
		return
	_play_advance_blip()
	_index += 1
	if _index >= _beats.size():
		_deactivate()
		sequence_finished.emit()
		return
	_show_current_line()

func _show_current_line() -> void:
	var beat: Dictionary = _beats[_index]
	line_shown.emit(beat)
	var display_name: String = beat.get("display_name", "")
	var is_narration: bool = beat.get("is_narration", display_name == "")
	_is_speech_line = not is_narration
	if is_narration:
		_apply_narration_presentation()
	else:
		_apply_speech_presentation(
			display_name,
			beat.get("stage_direction", ""),
			DialogueParser.resolve_avatar(beat)
		)
	_full_text = beat.get("text", "")
	_char_index = 0
	_type_accum = 0.0
	_char_interval = CHAR_INTERVAL_NARRATION if is_narration else CHAR_INTERVAL_SPEECH
	dialogue_label.text = ""
	dialogue_label.theme_type_variation = UITheme.TEXT_DIALOGUE_NARRATION if is_narration else UITheme.TEXT_DIALOGUE_SPEECH
	_is_typing = _full_text.length() > 0
	_show_hint(false)

func _apply_narration_presentation() -> void:
	name_plate.visible = false
	stage_direction_label.visible = false
	portrait_panel.visible = false

func _apply_speech_presentation(
	display_name: String,
	stage_direction: String,
	avatar_path: String
) -> void:
	name_plate.visible = true
	speaker_label.text = display_name
	stage_direction_label.visible = stage_direction != ""
	stage_direction_label.text = "（%s）" % stage_direction if stage_direction != "" else ""
	portrait_panel.visible = true
	if display_name != _last_speaker:
		_animate_speaker_change()
	_last_speaker = display_name
	_set_portrait(avatar_path)

func _animate_speaker_change() -> void:
	# 设定头像框的缩放轴心为中心，避免缩放抖动
	portrait_panel.pivot_offset = portrait_panel.size / 2
	portrait_panel.scale = Vector2(0.97, 0.97)
	
	# 立绘透明度及侧滑初态（从左侧 -10px 处平滑滑入）
	portrait.modulate.a = 0.0
	portrait.position.x = -10.0
	
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(portrait_panel, "scale", Vector2.ONE, 0.22)
	tween.tween_property(portrait, "modulate:a", 1.0, 0.2)
	tween.tween_property(portrait, "position:x", 0.0, 0.24)

func _on_typing_finished() -> void:
	if _display_mode == DisplayMode.PERSISTENT:
		_show_hint(false)
	else:
		_show_hint(true)

func _show_hint(show: bool) -> void:
	hint_label.visible = show and _display_mode == DisplayMode.SEQUENCE
	if hint_label.visible:
		_hint_pulse = 0.0
		hint_label.scale = Vector2.ONE
		hint_label.modulate.a = 1.0

func _activate() -> void:
	if _exit_tween:
		_exit_tween.kill()
		_exit_tween = null
	if _is_active:
		return
	_is_active = true
	active_changed.emit(true)
	visible = true
	if _enter_tween:
		_enter_tween.kill()
	modulate.a = 0.0
	frame_root.offset_top = _frame_offset_top_rest + 36.0
	frame_root.offset_bottom = _frame_offset_bottom_rest + 36.0
	dim_layer.modulate.a = 0.0
	_enter_tween = create_tween().set_parallel(true)
	_enter_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_enter_tween.tween_property(frame_root, "offset_top", _frame_offset_top_rest, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(frame_root, "offset_bottom", _frame_offset_bottom_rest, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(dim_layer, "modulate:a", 1.0, 0.22)

func _deactivate() -> void:
	if not _is_active:
		visible = false
		return
	_is_active = false
	_last_speaker = ""
	active_changed.emit(false)
	if _enter_tween:
		_enter_tween.kill()
	if _exit_tween:
		_exit_tween.kill()
	_exit_tween = create_tween().set_parallel(true)
	_exit_tween.tween_property(self, "modulate:a", 0.0, 0.14)
	_exit_tween.tween_property(dim_layer, "modulate:a", 0.0, 0.14)
	_exit_tween.chain().tween_callback(func():
		visible = false
		modulate.a = 1.0
		frame_root.offset_top = _frame_offset_top_rest
		frame_root.offset_bottom = _frame_offset_bottom_rest
	)

func _set_portrait(path: String) -> void:
	var tex: Texture2D = null
	if path != "":
		if _portrait_cache.has(path):
			tex = _portrait_cache[path]
		else:
			tex = AssetPlaceholder.load_texture(path, "avatar")
			if tex:
				_portrait_cache[path] = tex
	portrait.texture = tex
	portrait.visible = tex != null
	portrait_placeholder.visible = tex == null

func _play_blip() -> void:
	if blip_player.stream == null:
		return
	blip_player.pitch_scale = randf_range(0.95, 1.08)
	blip_player.stop()
	blip_player.play()

func _play_advance_blip() -> void:
	if blip_player.stream == null:
		return
	blip_player.pitch_scale = 0.82
	blip_player.play()

func _make_blip_stream() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var sample_count := 180
	var data := PackedByteArray()
	data.resize(sample_count)
	for i in range(sample_count):
		var t := float(i) / 22050.0
		var env := exp(-t * 120.0)
		var sample := sin(t * 920.0 * TAU) * env * 0.35
		data[i] = int(clamp(sample * 127.0, -128.0, 127.0))
	wav.data = data
	return wav