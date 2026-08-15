extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error('[SelfTestHost] Missing self-test script path.')
		get_tree().quit(2)
		return
	var script_path := str(args[0])
	var test_script := load(script_path) as GDScript
	if test_script == null:
		push_error('[SelfTestHost] Unable to load: ' + script_path)
		get_tree().quit(2)
		return
	var test_node := Node.new()
	test_node.set_script(test_script)
	add_child(test_node)
