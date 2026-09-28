extends RefCounted
## 调试钩子（DebugHooks）：调试构建里 F11 跳港（泉州 → 福州 → 兴化回访，设施页先剥后缀回基港）、F12 预览了结册页
## （沙盒直接凑齐第四章八万钱 + 十三港 + 一条结局线旗标，再走 try_resolve_ending）。云电脑点验用，非调试构建按不到。
## Lane main12 从 Main.gd 原样搬出（第十二刀，_debug_jump_port / _debug_preview_ending 两支）。
## Main 留同名同签名的一行转发，调用点不动：F11 / F12 键位判断（OS.is_debug_build()）仍在 Main._unhandled_input，照旧调 Main 的同名方法。
## 留在 Main 的：_unhandled_input 与其余 F7 / F8 / F9 点验键、current_scene_id、FACILITY_SUFFIXES、load_scene、_show_chapter_dialog、
## log_msg、update_status_panel，经 main 取；这里不存状态。
## 门禁 check_symbols 经 main_splits.txt 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


## 调试局跳港。第一次泉州（剧情九卡），再按福州（通用九卡），再按兴化回访。
## 设施页 current_scene_id 是 {港}_guild，要剥后缀，否则会误跳回泉州。
static func debug_jump_port(main: Control) -> void:
	var here: String = main.current_scene_id
	if not here.begins_with("city_"):
		for suffix in main.FACILITY_SUFFIXES:
			if here.ends_with(suffix):
				here = here.trim_suffix(suffix)
				break
	if here == "quanzhou":
		GameState.last_port = "fuzhou"
		main.load_scene("fuzhou")
		return
	if here == "fuzhou":
		GameState.last_port = "xinghua"
		main.load_scene("xinghua")
		return
	GameState.last_port = "quanzhou"
	main.load_scene("quanzhou")


## 调试局预览了结弹窗。沙盒攒到八万+占城太慢，云电脑点验用。
static func debug_preview_ending(main: Control) -> void:
	GameState.chapter = 4
	if GameState.money < 80000:
		GameState.add_money(80000 - GameState.money)
	GameState.peak_money = maxi(GameState.peak_money, 80000)
	for pid in ["quanzhou", "xinghua", "fuzhou", "wenzhou", "zhangzhou", "penghu", "ryukyu", "mingzhou", "hakata", "jeju", "kagoshima", "guangzhou", "champa"]:
		GameState.visit_port(pid)
	if not GameState.has_flag("chen_line_open") and not GameState.has_flag("merchant_distance") and not GameState.has_flag("history_pressure_seen"):
		GameState.set_flag("chen_line_open")
	GameState.last_port = "champa"
	var res := GameState.try_resolve_ending()
	if res.get("resolved", false):
		main._show_chapter_dialog(res)
	else:
		main.log_msg("预览了结未触发。")
	main.update_status_panel()
