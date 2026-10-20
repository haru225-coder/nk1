extends Node
## 只用键盘走 Main 各页（lane w54-a11y）：挂在 Main 底下的一个空节点，Main._ready 末尾 _a11y_mount 挂上，不画东西、不入存档。
## 浮层焦点：人物志 / 名册 / 市舶纪事 / 伙伴预览 / 船籍簿 / 航海日志 / 册页盖在页上时，Tab / 方向键原先照样走到暗幕底下的
## 工席门、动作钮、选项上（Godot 的焦点轮转不看谁被盖住），回车就在浮层底下开门、出海、接委办——人物志开着按两下 Tab
## 一下回车，底下的行会页就开了。现在浮层开着时 Main 的其余几枝整枝不收焦点（Control.focus_behavior_recursive），
## 焦点原在底下的当场放掉；浮层全合上再放开，焦点回到开浮层前那颗钮上。不吞按键的浮层（船籍簿 / 市舶纪事 / 伙伴预览）
## 开着时，没落在浮层钮上的回车 / 空格也收住，不落到 Main 去按底下这一页的头一扇门。
## Esc 有出口：设施页、见面页、只有「离开 / 返回上一处」可走的剧情页，按 Esc 即按页上那颗离开钮（同鼠标点它）；船籍簿开着
## 先合上船籍簿。原先 Main 不认 Esc，只有人物志 / 名册 / 市舶纪事 / 航海日志各自认，进了设施页按 Esc 没有反应。
## 港页是总汇、无处可退，Esc 不动；剧情岔路（挂 no_enter 的选项）不替人选；册页只有落定一条路，Esc 不替人落定。

var main: Control
## 头一层浮层开起来之前焦点在哪（合上后还给它；鼠标点出来的那份焦点不画框，还回去也不画）
var _before: Control = null
var _before_shown := false
var _queued := false


func _ready() -> void:
	main.child_entered_tree.connect(_queue_sync)
	main.child_exiting_tree.connect(_queue_sync)
	if main._ledger_layer != null:
		main._ledger_layer.visibility_changed.connect(_queue_sync)


func _queue_sync(_n: Node = null) -> void:
	if _queued:
		return
	_queued = true
	_sync.call_deferred()


## 开着的浮层里最上面那一层（Main 的子节点，排得越后越在上）；没有返回 null
func top_overlay() -> Control:
	var open: Array = []
	if main._ledger_layer != null and main._ledger_layer.visible:
		open.append(main._ledger_layer)
	for o in [main._save_host, main._chapter_host, main._codex, main._chars_wire, main._vision_stage, main._companion_preview]:
		if is_instance_valid(o) and o is Control and (o as Node).is_inside_tree() and not (o as Node).is_queued_for_deletion():
			open.append(o)
	var top: Control = null
	for o in open:
		if (o as Node).get_parent() == main and (top == null or (o as Node).get_index() > top.get_index()):
			top = o
	return top


func _sync() -> void:
	_queued = false
	if main == null or not is_instance_valid(main) or not main.is_inside_tree():
		return
	var top := top_overlay()
	var vp := main.get_viewport()
	var held: Control = vp.gui_get_focus_owner() if vp != null else null
	if top != null and _before == null and held != null and not _inside(top, held):
		_before = held
		_before_shown = held.has_focus(true)
	for c in main.get_children():
		if c is Control:
			(c as Control).focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED \
				if top != null and c != top else Control.FOCUS_BEHAVIOR_INHERITED
	if top != null:
		if held != null and is_instance_valid(held) and not _inside(top, held) and held.has_focus():
			held.release_focus()
		return
	var back := _before
	_before = null
	if back != null and is_instance_valid(back) and back.is_visible_in_tree() and back.focus_mode != Control.FOCUS_NONE \
			and vp != null and vp.gui_get_focus_owner() == null:
		back.grab_focus(not _before_shown)


static func _inside(top: Control, c: Control) -> bool:
	return c == top or top.is_ancestor_of(c)


## 船籍簿 / 市舶纪事 / 伙伴预览不吞按键：开着时没落在浮层钮上的回车 / 空格到这里收住（KeyNav 是 Main 的子节点，先于 Main 收到）。
## 航海日志与册页另有口径（回车落到 Main 合上 / 落定），照旧放过去
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		return
	if not event.is_action_pressed("ui_accept"):
		return
	var top := top_overlay()
	if top != null and top != main._save_host and top != main._chapter_host:
		get_viewport().set_input_as_handled()


## Esc：船籍簿开着先合上；别的浮层自己认 Esc（人物志 / 名册 / 市舶纪事 / 伙伴预览，航海日志「合上」挂着 ui_cancel 快捷键），
## 走不到这里；册页开着不动。没有浮层就按这一页的离开钮
func _on_cancel() -> void:
	var top := top_overlay()
	if top != null and top == main._ledger_layer:
		get_viewport().set_input_as_handled()
		main._close_ledger()
		return
	if top != null:
		return
	var leave := leave_button()
	if leave != null:
		get_viewport().set_input_as_handled()
		leave.pressed.emit()


## 这一页看得见、按得动的离开钮：见面页「离开」、设施页页脚「离开」、剧情页只剩的「离开 / 返回上一处」。
## 剧情岔路上挂 no_enter 的不算（那是要人自己挑的一条路）
const LEAVE_TEXTS := ["离开", "返回上一处"]


func leave_button() -> Button:
	for host in [main.npc_actions, main._page_footer, main.choices_container]:
		if host == null or not (host as Control).is_visible_in_tree():
			continue
		for b in (host as Node).find_children("*", "Button", true, false):
			var btn := b as Button
			if btn.text in LEAVE_TEXTS and not btn.disabled and btn.is_visible_in_tree() and not btn.has_meta("no_enter") \
					and not btn.is_queued_for_deletion():
				return btn
	return null
