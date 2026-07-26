extends Area2D

var floating_text = preload("res://scenes/FloatingText.tscn")

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Ship":
		var is_money = randf() > 0.5
		var float_str = ""
		
		if is_money:
			var amount = randi_range(100, 500)
			GameState.add_money(amount)
			float_str = "+ " + str(amount) + " 钱"
		else:
			var items = ["sea_salt", "raw_silk", "pepper"]
			var item = items[randi() % items.size()]
			var amount = randi_range(1, 3)
			var good_name = GameManager.get_good_name(item)
			# 舱满则折成现钱，避免捞到的货凭空消失
			if Fleet.add_cargo(item, amount, 0.0):
				float_str = "+ " + good_name + " x" + str(amount)
			else:
				var g = GameManager.get_good_by_id(item)
				var fallback = int(g.get("base_value", 20)) * amount
				GameState.add_money(fallback)
				float_str = "舱满，折钱 +" + str(fallback)
		
		var ft = floating_text.instantiate()
		ft.position = position
		ft.text = float_str
		ft.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		get_parent().call_deferred("add_child", ft)
		
		queue_free()
