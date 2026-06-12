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
			GameState.money += amount
			print("打捞到木桶，获得现钱: ", amount)
			float_str = "+ " + str(amount) + " 钱"
		else:
			var items = ["私盐", "生丝", "胡椒"]
			var item = items[randi() % items.size()]
			var amount = randi_range(1, 3)
			if not GameState.cargo.has(item):
				GameState.cargo[item] = 0
			GameState.cargo[item] += amount
			print("打捞到木桶，获得货物: ", item, " x", amount)
			float_str = "+ " + item + " x" + str(amount)
		
		var ft = floating_text.instantiate()
		ft.position = position
		ft.text = float_str
		ft.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		get_parent().call_deferred("add_child", ft)
		
		queue_free()
