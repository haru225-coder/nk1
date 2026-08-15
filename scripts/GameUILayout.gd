class_name GameUILayout extends RefCounted

const STATUS_BAR_HEIGHT_COMPACT := 88.0
const STATUS_BAR_HEIGHT_FULL := 116.0
const DIALOGUE_BAR_HEIGHT := 408.0
const SEA_HUD_MARGIN_DEFAULT := 20.0
const SEA_HUD_MARGIN_BELOW_CHROME := 8.0


## P8-5: 有壳层状态条时，WorldMap HUD 顶边下移避让
static func sea_hud_top_margin(has_shell_chrome: bool, status_bar_height: float = STATUS_BAR_HEIGHT_FULL) -> float:
	if has_shell_chrome:
		return status_bar_height + SEA_HUD_MARGIN_BELOW_CHROME
	return SEA_HUD_MARGIN_DEFAULT