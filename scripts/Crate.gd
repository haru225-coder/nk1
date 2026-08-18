extends Area2D

## 海上宝箱/漂流物 — 非战斗世界事件拾取
## 资源结算统一通过 LootResolver.apply_world_pickup（不直接操作 LedgerSystem）。
## preset_good_id 非空时为落货还原箱（永远还同一货物，不当钱）。

const WORLD_CRATE_GROUP := "world_crate"
const MONEY_MIN := 15
const MONEY_MAX := 40
const CARGO_AMOUNT_MIN := 1
const CARGO_AMOUNT_MAX := 3
const DAILY_PICKUP_CAP := 8
const WORLD_MONEY_THRESHOLD := 0.5

static var _pickup_day_key: String = ""
static var _daily_pickups: int = 0

## 空 = 随机世界箱（钱/货 各半）；船击落货时由 Ship 写入。
var preset_good_id: String = ""
var preset_amount: int = 0

func _ready() -> void:
	add_to_group(WORLD_CRATE_GROUP)
	body_entered.connect(_on_body_entered)

func _pick_random_cargo_good() -> Dictionary:
	var candidates: Array = []
	for g in GameManager.goods_data.get("goods", []):
		if g.get("category") == "货物":
			candidates.append(g)
	if candidates.is_empty():
		return {}
	return candidates[randi() % candidates.size()]

static func calendar_day_key() -> String:
	var cal = GameState.calendar
	if cal == null:
		return ""
	var year = cal.get("year")
	var month = cal.get("month")
	var day = cal.get("day")
	if year != null and month != null and day != null:
		return "%d-%02d-%02d" % [int(year), int(month), int(day)]
	if cal.has_method("date_key"):
		return str(cal.date_key())
	return ""

static func _sync_pickup_day() -> void:
	var key := calendar_day_key()
	if key != _pickup_day_key:
		_pickup_day_key = key
		_daily_pickups = 0

static func record_world_pickup() -> void:
	_sync_pickup_day()
	_daily_pickups += 1

static func world_pickups_today() -> int:
	_sync_pickup_day()
	return _daily_pickups

static func is_daily_pickup_cap_reached() -> bool:
	return world_pickups_today() >= DAILY_PICKUP_CAP

func _good_display_name(good_id: String) -> String:
	if GameManager != null and GameManager.has_method("get_good_data"):
		var data = GameManager.get_good_data(good_id)
		if data is Dictionary and not data.is_empty():
			return str(data.get("name", good_id))
	return good_id

func _apply_preset_cargo() -> String:
	var amount: int = preset_amount if preset_amount > 0 else 1
	var result = LootResolver.apply_world_pickup(0, preset_good_id, amount)
	if result.get("cargo", "") != "":
		return "+ " + _good_display_name(preset_good_id) + " x" + str(amount)
	return "货舱已满"

func _apply_world_loot() -> String:
	record_world_pickup()
	var is_money: bool = randf() > WORLD_MONEY_THRESHOLD
	if is_money:
		var amount: int = randi_range(MONEY_MIN, MONEY_MAX)
		LootResolver.apply_world_pickup(amount)
		return "+ " + str(amount) + " 钱"
	var good: Dictionary = _pick_random_cargo_good()
	if good.is_empty():
		return ""
	var good_id: String = good.get("id", "")
	var amount: int = randi_range(CARGO_AMOUNT_MIN, CARGO_AMOUNT_MAX)
	var result = LootResolver.apply_world_pickup(0, good_id, amount)
	if result.get("cargo", "") != "":
		return "+ " + good.get("name", good_id) + " x" + str(amount)
	return "货舱已满"

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player_ship"):
		return

	var float_str: String = ""
	if not preset_good_id.is_empty():
		float_str = _apply_preset_cargo()
	else:
		float_str = _apply_world_loot()

	if float_str != "":
		var ft = ResourceManager.FloatingText.instantiate()
		ft.global_position = global_position + FloatingTextConfig.OFFSET_PICKUP
		ft.text = float_str
		ft.modulate = GameColors.FLOATING_PICKUP
		var parent := get_parent()
		if is_instance_valid(parent):
			parent.call_deferred("add_child", ft)

	queue_free()
