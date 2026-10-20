extends RefCounted
## 探针摆场的共用小件（lane w54-gates）：每支 headless 探针开头那几行「取 autoload、缺了就判红」与
## 「压掉序章过场、起一张 Main」在 57 支探针里各抄一份，抄漏一行就是另一支探针才发现的假绿。
## 这里只收「写法一字不差、判词不许走样」的那两件，收不进的不硬收：
##
##   autoloads(tree, names)  → Dictionary{名字: Node}；缺哪个就回 null 表，调用方照自己的话判红。
##       原先每支写的是 root.get_node_or_null("GameState") 连写三行 + 一个 if null 判词。
##       名字是数组而不是固定三件：qa_w53_5_* 还要 Crew，qa_w53_6_* 还要 Economy。
##
##   main_scene(tree, size, settle_frames) → Node；按各探针原样的
##       (load("res://scenes/Main.tscn") as PackedScene).instantiate() → root.add_child → 等若干帧。
##       settle_frames 原样传（各探针要的帧数不同，不在这里统一）。
##       返回 null = Main.tscn 起不来（根脚本 Parse Error），调用方照自己的话判红。
##
##   quiet_opening()  压掉序章过场（Cinematics.auto_opening = false / opening_seen = true）。
##       原先写在起 Main 之前，三行；只管这两面旗，别的什么都不碰。
##
## 刻意不收的：
##   - root.size：有的探针设 1280×720，有的不设（headless 下无意义），有的在起 Main 之后设——顺序是要紧的。
##   - Switches.reset()：各节开关状态由各探针自己排，收进来反而把「哪一节先 reset」藏了。
##   - 起 WorldMap / SeaChart / 战报册页那些布景：各有各的冻敌炮、拆墨边的时序（见 combat_probe_stage.gd），
##     不是同一段写法，硬抽会把时序差别藏进 helper。
##
## 用法（headless -s）：
##   const ProbeBoot := preload("res://tools/probe_boot.gd")
##   var a := ProbeBoot.autoloads(root, ["GameState", "Calendar", "Fleet"])
##   if a.is_empty():
##       _expect(false, "autoload GameState / Calendar / Fleet 都在"); _report(); return
##   var _gs: Node = a["GameState"]
##   ProbeBoot.quiet_opening()
##   _main = ProbeBoot.main_scene(root, Vector2i(1280, 720), 10)


## 取 root 下的 autoload；names 里缺一个就整表回空（调用方按自己的判词报缺哪几件）
static func autoloads(root_node: Node, names: Array) -> Dictionary:
	var out := {}
	for n in names:
		var node: Node = root_node.get_node_or_null(str(n))
		if node == null:
			return {}
		out[str(n)] = node
	return out


## 压掉序章过场：新局不再自动播开场、也不再记「看过」（两支旗各探针原样都这么写）
static func quiet_opening() -> void:
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine == null:
		return
	cine.set("auto_opening", false)
	cine.set("opening_seen", true)


## 起 Main：instantiate → （可选）设 root.size → add_child → 过 settle_frames 帧。
## root_node 是探针里的 root（SceneTree.root，Window）；等帧走 Engine 主循环，不依赖调用方是不是 SceneTree。
static func main_scene(root_node: Node, size: Vector2i = Vector2i.ZERO, settle_frames: int = 10) -> Node:
	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		return null
	var m: Node = packed.instantiate()
	if m == null or m.get_script() == null:
		if m != null:
			m.free()
		return null
	if size != Vector2i.ZERO:
		root_node.size = size
	root_node.add_child(m)
	for i in settle_frames:
		await (root_node.get_tree() as SceneTree).process_frame
	return m
