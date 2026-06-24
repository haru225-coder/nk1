extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _pick_random_cargo_good() -> Dictionary:
	var candidates: Array = []
	for g in GameManager.goods_data.get("goods", []):
		if g.get("category") == "货物":
			candidates.append(g)
	if candidates.is_empty():
		return {}
	return candidates[randi() % candidates.size()]

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player_ship"):
		var is_money = randf() > 0.5
		var float_str = ""
		
		if is_money:
			var amount = randi_range(100, 500)
			# INTENT_DEFERRED: 海上宝箱金钱奖励 — 世界事件拾取，暂不迁移至 Intent
			LedgerSystem.apply({"amount": amount, "source": "world_event", "reason": "collect_crate", "actor": "Player"})
			float_str = "+ " + str(amount) + " 钱"
		else:
			var good = _pick_random_cargo_good()
			if good.is_empty():
				queue_free()
				return
			var good_id = good.get("id", "")
			var amount = randi_range(1, 3)
			if CargoSystem.add_item(good_id, amount):
				float_str = "+ " + good.get("name", good_id) + " x" + str(amount)
			else:
				float_str = "货舱已满"
		
		var ft = ResourceManager.FloatingText.instantiate()
		ft.global_position = global_position
		ft.text = float_str
		ft.modulate = Color(0.2, 1.0, 0.2)
		get_parent().call_deferred("add_child", ft)
		
		queue_free()