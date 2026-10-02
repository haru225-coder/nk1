class_name NK1CutLib
## 5 例编排 hook 序公共库（接舷开场比 resolve 要有的判定 / 探针 headless 探头）。
extends RefCounted

static func headless() -> bool:
	return DisplayServer.get_name() == "headless"

## MeleeResolve 改键抓：verdict / rounds 字段从结果拿。
## 判敌我预定局面：us 满员 100，foe 14，顺风，hooked=true…… _append_hook_strong_capture 复用。
static func strong_ctx(us: Dictionary, foe: Dictionary, ship: Node2D, enemy: Node2D) -> Dictionary:
	var ctx := {
		"hooked": true,
		"wind_from": Vector2.RIGHT,
		"wind_speed": 150.0,
		"distance": 120.0,
	}
	# 不用 MeleeResolve.approach_from_nodes（它要带船速船首向）；按预定局面装
	ctx["att_wind"] = 1.0
	ctx["att_speed"] = 1.0
	return ctx
