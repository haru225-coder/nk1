extends Control

signal status_updated
signal npc_finished

@onready var npc_name_lbl: Label = $HBox/DialogPanel/NPCName
@onready var npc_dialog_lbl: RichTextLabel = $HBox/DialogPanel/NPCDialog
@onready var npc_actions: VBoxContainer = $HBox/DialogPanel/NPCActions
@onready var npc_portrait: TextureRect = $HBox/PortraitRect

func setup(npc_id: String, fallback_name: String) -> void:
	var npc_data = {}
	var npcs = GameManager.npcs_data.get("npcs", [])
	for n in npcs:
		if n.get("id") == npc_id:
			npc_data = n
			break
			
	var n_name = npc_data.get("name", fallback_name)
	npc_name_lbl.text = n_name
	npc_dialog_lbl.text = npc_data.get("function", "（这人看起来有些眼熟，但什么也没说...）")
	
	# Load Portrait safely using JSON data to avoid hardcoded string path construction
	var tex_path = npc_data.get("avatar", "")
	if tex_path != "" and FileAccess.file_exists(tex_path):
		var img = Image.load_from_file(tex_path)
		if img: npc_portrait.texture = ImageTexture.create_from_image(img)
	else:
		npc_portrait.texture = null
		
	# Clear previous actions
	for child in npc_actions.get_children(): 
		child.queue_free()
	
	# Action: Gather Intel
	var intel_btn = Button.new()
	intel_btn.text = "打听情报"
	intel_btn.pressed.connect(func():
		var goods = GameManager.goods_data.get("goods", [])
		if goods.size() > 0:
			var random_g = goods[randi() % goods.size()]
			npc_dialog_lbl.text = n_name + " 压低声音说：“听说最近 %s 的买卖很赚，你要不要试试？”" % random_g.get("name", "这行")
	)
	npc_actions.add_child(intel_btn)
	
	# Action: Bribe (Only for Yamen official)
	if npc_id == "customs_official":
		var bribe_btn = Button.new()
		bribe_btn.text = "塞钱买通 (50钱)"
		bribe_btn.pressed.connect(func():
			var res = GameState.handle_special_action("bribe_official_50")
			if res["success"]:
				status_updated.emit()
				npc_dialog_lbl.text = n_name + " 颠了颠手里的碎银：“算你懂事。文牒拿好，路上小心。”"
			else:
				npc_dialog_lbl.text = n_name + " 满脸鄙夷：“就这点钱也想打通关节？滚滚滚！”"
		)
		npc_actions.add_child(bribe_btn)
		
	var leave_btn = Button.new()
	leave_btn.text = "离开"
	leave_btn.pressed.connect(func():
		npc_finished.emit()
	)
	npc_actions.add_child(leave_btn)
