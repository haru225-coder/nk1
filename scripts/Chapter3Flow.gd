class_name Chapter3Flow extends RefCounted

## 章三续进解析（内容/体验）
## 根据 story flags 返回最近未完成场景 id；无可续则 ""。

static func resolve_resume_scene() -> String:
	if not GameState.has_story_flag("chapter2_complete"):
		return ""
	if GameState.has_story_flag("chapter3_complete"):
		return ""
	# 投附线
	if GameState.has_story_flag("chapter3_pu_deal_accepted"):
		if GameState.has_story_flag("chapter3_comply_audit_done"):
			return ""
		if GameState.has_story_flag("chapter3_comply_taixue_registered") \
				or GameState.has_story_flag("chapter3_comply_questioned_guarantee") \
				or GameState.has_story_flag("chapter3_comply_browsed_old_rolls"):
			return "chapter3_comply_audit"
		if GameState.has_story_flag("chapter3_comply_rode_pu_carriage") \
				or GameState.has_story_flag("chapter3_comply_walked_to_taixue") \
				or GameState.has_story_flag("chapter3_comply_delayed_one_day"):
			return "chapter3_comply_taixue_register"
		return "chapter3_after_summon_comply"
	# 拒召线
	if GameState.has_story_flag("chapter3_pu_deal_refused"):
		if GameState.has_story_flag("chapter3_refuse_escape_done"):
			return ""
		if GameState.has_story_flag("chapter3_refuse_sea_route_chosen") \
				or GameState.has_story_flag("chapter3_refuse_land_route_chosen"):
			return "chapter3_refuse_sea_route"
		if GameState.has_story_flag("chapter3_refuse_back_alley_safe") \
				or GameState.has_story_flag("chapter3_refuse_back_alley_questioned") \
				or GameState.has_story_flag("chapter3_refuse_stayed_linan"):
			return "chapter3_refuse_seek_lin"
		if GameState.has_story_flag("chapter3_refuse_took_main_street") \
				or GameState.has_story_flag("chapter3_refuse_took_back_alley") \
				or GameState.has_story_flag("chapter3_refuse_glanced_back"):
			return "chapter3_refuse_linan_back_alley"
		return "chapter3_after_summon_refuse"
	# 烧帖线
	if GameState.has_story_flag("chapter3_pu_card_burned"):
		if GameState.has_story_flag("chapter3_burn_escape_done"):
			return ""
		if GameState.has_story_flag("chapter3_burn_jumped_window") \
				or GameState.has_story_flag("chapter3_burn_talked_out") \
				or GameState.has_story_flag("chapter3_burn_drew_blade"):
			return "chapter3_burn_flee"
		if GameState.has_story_flag("chapter3_burn_took_main_gate") \
				or GameState.has_story_flag("chapter3_burn_took_back_alley") \
				or GameState.has_story_flag("chapter3_burn_took_guard_badge"):
			return "chapter3_burn_arrest"
		return "chapter3_after_summon_burn"
	return "chapter3_pu_summon"
