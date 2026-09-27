extends SceneTree
## 从 ClassDB 导出 Node 及常用基类的 method / property / signal / constant / enum，
## 写成确定性排序的 tools/builtin_api.txt，供 check_symbols.py 二节「内置成员」放行用（lane cs3）；
## 另导 SIGNAL_CLASSES 的信号段，供二之二 / 二之三认引擎基类信号（lane cs5）。
## 每类只列本类新增的成员（no_inheritance），继承链由 inherits 行给出，check_symbols 按 extends 链合并。
## godot --headless --path . -s res://tools/gen_builtin_list.gd [-- 输出路径]
## 通常经 python3 tools/check_symbols.py --regen 调用；生成物勿手改（头部 sha256 自检）。

const CLASSES := [
	"Object", "RefCounted", "Resource",
	"Node", "CanvasItem", "Node2D", "Control", "CanvasLayer",
]
## 只导信号的引擎类（lane cs5，接替 check_symbols 旧手抄 NATIVE_SIGNALS）：二之二 / 二之三 按 extends 链认基类信号。
## 写在 `== signal ==` 分隔行之后，每类只有 inherits + signal 行；上面 CLASSES 的信号照旧在各自全量段里。
const SIGNAL_CLASSES := [
	"AcceptDialog", "AnimatableBody2D", "AnimatedSprite2D", "AnimationMixer", "AnimationPlayer",
	"AnimationTree", "Area2D", "Area3D", "AspectRatioContainer", "AudioStreamPlayer",
	"AudioStreamPlayer2D", "BaseButton", "BoxContainer", "Button", "CPUParticles2D", "Camera2D",
	"Camera3D", "CenterContainer", "CharacterBody2D", "CharacterBody3D", "CheckBox", "CheckButton",
	"CodeEdit", "CollisionObject2D", "CollisionObject3D", "ColorRect", "ConfirmationDialog",
	"Container", "DirectionalLight3D", "FlowContainer", "GPUParticles2D", "GeometryInstance3D",
	"GridContainer", "HBoxContainer", "HFlowContainer", "HScrollBar", "HSeparator", "HSlider",
	"HSplitContainer", "HTTPRequest", "ItemList", "Label", "Light3D", "Line2D", "LineEdit",
	"LinkButton", "MainLoop", "MarginContainer", "Marker2D", "Marker3D", "MenuButton",
	"MeshInstance3D", "NinePatchRect", "Node3D", "OmniLight3D", "OptionButton", "Panel",
	"PanelContainer", "ParallaxBackground", "Path2D", "PathFollow2D", "PhysicsBody2D",
	"PhysicsBody3D", "Polygon2D", "Popup", "PopupMenu", "PopupPanel", "ProgressBar", "Range",
	"ReferenceRect", "RichTextLabel", "RigidBody2D", "SceneTree", "ScrollBar", "ScrollContainer",
	"Separator", "Slider", "SpinBox", "SplitContainer", "Sprite2D", "StaticBody2D", "SubViewport",
	"SubViewportContainer", "TabBar", "TabContainer", "TextEdit", "TextureButton",
	"TextureProgressBar", "TextureRect", "TileMapLayer", "Timer", "Tree", "Tween", "VBoxContainer",
	"VFlowContainer", "VScrollBar", "VSeparator", "VSlider", "VSplitContainer", "Viewport",
	"VisibleOnScreenNotifier2D", "VisualInstance3D", "Window", "WorldEnvironment",
]
const DEFAULT_OUT := "res://tools/builtin_api.txt"
const SKIP_USAGE := PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else DEFAULT_OUT
	var body := _body()
	var v := Engine.get_version_info()
	var ver := "%d.%d" % [v.major, v.minor]
	if int(v.patch) != 0:
		ver += ".%d" % v.patch
	ver += ".%s.%s.%s" % [v.status, v.build, String(v.hash).left(9)]
	var text := "# 由 tools/gen_builtin_list.gd 从 ClassDB 导出，勿手改；重生成：python3 tools/check_symbols.py --regen\n"
	text += "# godot %s\n" % ver
	text += "# sha256 %s\n" % body.sha256_text()
	text += body
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("GEN_BUILTIN_LIST FAIL 写不了 %s（%s）" % [out_path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("GEN_BUILTIN_LIST OK %s" % out_path)
	quit(0)


func _body() -> String:
	var lines: PackedStringArray = []
	for cls in CLASSES:
		if not ClassDB.class_exists(cls):
			printerr("GEN_BUILTIN_LIST 无此类 %s" % cls)
			continue
		lines.append("[%s]" % cls)
		lines.append(("inherits " + ClassDB.get_parent_class(cls)).strip_edges())
		var rows: PackedStringArray = []
		for m in ClassDB.class_get_method_list(cls, true):
			rows.append("method " + String(m.name))
		for p in ClassDB.class_get_property_list(cls, true):
			if int(p.usage) & SKIP_USAGE:
				continue
			rows.append("property " + String(p.name))
		for s in ClassDB.class_get_signal_list(cls, true):
			rows.append("signal " + String(s.name))
		for c in ClassDB.class_get_integer_constant_list(cls, true):
			rows.append("constant " + String(c))
		for e in ClassDB.class_get_enum_list(cls, true):
			rows.append("enum " + String(e))
		rows.sort()
		var last := ""
		for r in rows:
			if r != last:
				lines.append(r)
			last = r
		lines.append("")
	lines.append("== signal ==")
	for cls in SIGNAL_CLASSES:
		if not ClassDB.class_exists(cls):
			printerr("GEN_BUILTIN_LIST 无此类 %s" % cls)
			continue
		lines.append("[%s]" % cls)
		lines.append(("inherits " + ClassDB.get_parent_class(cls)).strip_edges())
		var sigs: PackedStringArray = []
		for s in ClassDB.class_get_signal_list(cls, true):
			sigs.append("signal " + String(s.name))
		sigs.sort()
		var last := ""
		for r in sigs:
			if r != last:
				lines.append(r)
			last = r
		lines.append("")
	return "\n".join(lines)
