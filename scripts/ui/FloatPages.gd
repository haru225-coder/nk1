extends RefCounted
## 浮页（FloatPages）：盖在当前画面上的一层薄页——人物志（CharacterCodex）、岸上名册（CharsShoreOverlay）、
## 伙伴草案预览（CompanionPreview，调试 F7，只读剪影卡、不接招募）、市舶纪事（VisionStage 册页叠层，立像裱框 + 海战定格）。
## 都不入存档、不过日子。Lane w21-d20 从 Main.gd 原样搬出（第十四刀，_open_codex / _open_chars_wire / _close_chars_wire /
## _toggle_companion_preview / _open_companion_preview / _close_companion_preview / _open_vision_stage / _close_vision_stage 八支）。
## Main 留同名同签名的一行转发，调用点不动：岸带「人物志 / 名册 / 市舶纪事」钮、CodexTitleButton、F7 / F8 仍调 Main 的同名方法。
## 留在 Main 的：_codex / _chars_wire / _vision_stage / _companion_preview 四个浮页句柄与 _close_ledger / _dismiss_banner，经 main 取；
## 这里不存状态。
## 门禁 check_symbols 经 main_splits.txt 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


## 人物志：一层浮页盖在当前画面上（港口页底、标题页进）。focus_id 非空直接开此人详页。不入存档。
static func open_codex(main: Control, focus_id := "") -> void:
	main._close_companion_preview()
	main._close_ledger()
	main._dismiss_banner()
	main._close_chars_wire()
	main._close_vision_stage()
	if is_instance_valid(main._codex) and not bool(main._codex.get("_closing")):
		if focus_id != "":
			main._codex.call("show_detail", focus_id, false)
		return
	var cx: Control = main._CODEX.new()
	main.add_child(cx)
	cx.call("begin", focus_id)
	main._codex = cx


## chars 线：岸上名册浮页（CharRoster + CharPortraitPanel）。与人物志互斥；不入存档。
static func open_chars_wire(main: Control, focus_id := "") -> void:
	main._close_companion_preview()
	main._close_ledger()
	main._dismiss_banner()
	main._close_vision_stage()
	if is_instance_valid(main._codex) and not bool(main._codex.get("_closing")):
		main._codex.call("close_codex")
	if is_instance_valid(main._chars_wire) and not bool(main._chars_wire.get("_closing")):
		if focus_id != "":
			main._chars_wire.call("focus_id", focus_id)
		return
	var ov: Control = main._CHARS_WIRE.new()
	main.add_child(ov)
	ov.call("begin", focus_id)
	main._chars_wire = ov


static func close_chars_wire(main: Control) -> void:
	if is_instance_valid(main._chars_wire) and not bool(main._chars_wire.get("_closing")):
		main._chars_wire.call("close_overlay")


## Lane Z3：伙伴草案预览浮页（只读剪影六卡）。F7 开关；不入存档、不接招募。
static func toggle_companion_preview(main: Control) -> void:
	if is_instance_valid(main._companion_preview) and not bool(main._companion_preview.get("_closing")):
		close_companion_preview(main)
		return
	open_companion_preview(main)


static func open_companion_preview(main: Control) -> void:
	main._close_ledger()
	main._dismiss_banner()
	main._close_chars_wire()
	main._close_vision_stage()
	if is_instance_valid(main._codex) and not bool(main._codex.get("_closing")):
		main._codex.call("close_codex")
	if is_instance_valid(main._companion_preview) and not bool(main._companion_preview.get("_closing")):
		return
	var ov: Control = main._COMPANION_PREVIEW.new()
	main.add_child(ov)
	ov.call("begin")
	main._companion_preview = ov
	ov.tree_exited.connect(func() -> void:
		if main._companion_preview == ov:
			main._companion_preview = null
	)


static func close_companion_preview(main: Control) -> void:
	if is_instance_valid(main._companion_preview) and not bool(main._companion_preview.get("_closing")):
		main._companion_preview.call("close_overlay")


## Lane L：叠一层 VisionStage（立像裱框 + 海战定格）。B/Esc 合上；不入存档、不过日子。
static func open_vision_stage(main: Control) -> void:
	main._close_companion_preview()
	main._close_ledger()
	main._dismiss_banner()
	main._close_chars_wire()
	if is_instance_valid(main._codex) and not bool(main._codex.get("_closing")):
		main._codex.call("close_codex")
	if is_instance_valid(main._vision_stage):
		return
	var vs: Control = main._VISION_STAGE.instantiate()
	main.add_child(vs)
	main._vision_stage = vs
	# 子节点离开时清引用（VisionStage._leave → queue_free）
	vs.tree_exited.connect(func() -> void:
		if main._vision_stage == vs:
			main._vision_stage = null
	)


static func close_vision_stage(main: Control) -> void:
	if is_instance_valid(main._vision_stage):
		main._vision_stage.queue_free()
		main._vision_stage = null
