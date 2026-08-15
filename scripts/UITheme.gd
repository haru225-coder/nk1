class_name UITheme extends RefCounted

## NK1-P6-POLISH-002: 统一 UI Theme 字符串常量
## 将散落在各处的 theme_type_variation 字符串集中管理
## 修改时只需改此处，所有引用自动更新

## ── 按钮变体 ─────────────────────────────────────────────
const BTN_ACTION := "ActionButton"           ## 主要操作按钮（购买/确认/招募/修理等）
const BTN_CHOICE := "ChoiceButton"           ## 次要选择按钮（取消/返回/出售等）
const BTN_SET_SAIL := "SetSailButton"        ## 升帆/出港/确认出航（红色高亮）
const BTN_TITLE_MENU := "TitleMenuButton"     ## 标题界面菜单按钮
const BTN_NPC := "NPCButton"                 ## NPC 交互按钮
const BTN_COMMAND := "CommandBarButton"       ## 快捷指令底栏按钮
const LABEL_COMMAND_CAPTION := "CommandBarCaption"
const LABEL_COMMAND_CAPTION_HIGHLIGHT := "CommandBarCaptionHighlight"


## ── 市集 UI ──────────────────────────────────────────────
const MARKET_SHELL := "MarketShell"           ## 市集主面板
const MARKET_TITLE := "MarketTitle"           ## 市集标题
const MARKET_ALERT := "MarketAlert"           ## 市集异常提示
const MARKET_PANEL := "MarketPanel"           ## 市集信息面板
const MARKET_PREVIEW := "MarketPreview"       ## 市集预览/价格标签

## ── 港口设施 ─────────────────────────────────────────────
const CARD_FACILITY := "PortFacilityCard"            ## 设施卡片面板
const CARD_FACILITY_QUEST := "PortFacilityCardQuest" ## 任务设施卡片面板
const TITLE_FACILITY := "FacilityTitle"               ## 设施标题
const SUBTITLE_FACILITY := "FacilitySubtitle"         ## 设施副标题
const BTN_FACILITY_CARD := "FacilityCardButton"       ## 设施卡片点击按钮
const BADGE_FACILITY_QUEST := "FacilityQuestBadge"     ## 设施任务徽章
const FRAME_FACILITY_ICON := "FacilityIconFrame"       ## 设施图标框

## ── 港状态栏 ─────────────────────────────────────────────
const CHIP_PORT_STAT := "PortStatChip"        ## 港状态栏芯片背景
const LABEL_PORT_STAT := "PortStatLabel"      ## 港状态栏标题
const VALUE_PORT_STAT := "PortStatValue"      ## 港状态栏数值

## ── 通用 ─────────────────────────────────────────────────
const SECTION_LABEL := "SectionLabel"         ## 区域标题

## ── 事件/战斗 UI ────────────────────────────────────────
const TITLE_EVENT := "EventTitle"             ## 事件标题
const BODY_EVENT := "EventBody"               ## 事件正文
const PANEL_DIALOGUE_INNER := "DialoguePanelInner" ## 对话框内层面板

## ── 对话框 ──────────────────────────────────────────────
const TEXT_DIALOGUE_NARRATION := "DialogueNarrationText" ## 旁白文字
const TEXT_DIALOGUE_SPEECH := "DialogueSpeechText"       ## 对话文字

## ── 标题界面 ─────────────────────────────────────────────
const TEXT_TITLE_SUB := "TitleSub"            ## 标题副标题
const TEXT_TITLE_SAVE_HEADER := "TitleSaveHeader"

## ── 发布路径收口（P9-C）────────────────────────────────
const ENDING_KICKER := "EndingKicker"
const ENDING_TITLE := "EndingTitle"
const ENDING_SUBTITLE := "EndingSubtitle"
const ENDING_META := "EndingMeta"
const ENDING_SUMMARY := "EndingSummary"
const ENDING_EPILOGUE := "EndingEpilogue"
const TOWN_HOTSPOT_PANEL := "TownHotspotPanel"
const TOWN_HOTSPOT_PANEL_QUEST := "TownHotspotPanelQuest"
const TOWN_HOTSPOT_TITLE := "TownHotspotTitle"
const TOWN_HOTSPOT_TITLE_QUEST := "TownHotspotTitleQuest"
const TOWN_HOTSPOT_TITLE_DONE := "TownHotspotTitleDone"
const TOWN_HINT_PANEL := "TownHintPanel"
const TOWN_HINT_LABEL := "TownHintLabel"
const PORT_COLUMN_HEADER := "PortColumnHeader"
const PORT_COLUMN_HEADER_LABEL := "PortColumnHeaderLabel"
const PORT_FACILITY_HINT := "PortFacilityHint"
const MAP_STRATEGIC_POPUP := "MapStrategicPopup"
const MAP_STRATEGIC_TITLE := "MapStrategicTitle"
const MAP_STRATEGIC_INFO := "MapStrategicInfo"
const MAP_STRATEGIC_BUTTON := "MapStrategicButton"

## ── 航行 HUD ─────────────────────────────────────────────
const LABEL_SEA_HUD_FLEET := "SeaHudFleet"     ## 航行舰队标签

## ── 验证常量（test assert）─────────────────────────────
## 用于 verify_ui_r1_r3.gd 等测试脚本验证 theme 正确性
static func assert_all_known(theme_name: String) -> bool:
	var known := [
		BTN_ACTION, BTN_CHOICE, BTN_SET_SAIL, BTN_TITLE_MENU, BTN_NPC, BTN_COMMAND,
		LABEL_COMMAND_CAPTION, LABEL_COMMAND_CAPTION_HIGHLIGHT,
		MARKET_SHELL, MARKET_TITLE, MARKET_ALERT, MARKET_PANEL, MARKET_PREVIEW,
		CARD_FACILITY, CARD_FACILITY_QUEST, TITLE_FACILITY, SUBTITLE_FACILITY,
		BTN_FACILITY_CARD, BADGE_FACILITY_QUEST, FRAME_FACILITY_ICON,
		CHIP_PORT_STAT, LABEL_PORT_STAT, VALUE_PORT_STAT,
		SECTION_LABEL, TITLE_EVENT, BODY_EVENT, PANEL_DIALOGUE_INNER,
		TEXT_DIALOGUE_NARRATION, TEXT_DIALOGUE_SPEECH, TEXT_TITLE_SUB, TEXT_TITLE_SAVE_HEADER,
		ENDING_KICKER, ENDING_TITLE, ENDING_SUBTITLE, ENDING_META,
		ENDING_SUMMARY, ENDING_EPILOGUE,
		TOWN_HOTSPOT_PANEL, TOWN_HOTSPOT_PANEL_QUEST,
		TOWN_HOTSPOT_TITLE, TOWN_HOTSPOT_TITLE_QUEST, TOWN_HOTSPOT_TITLE_DONE,
		TOWN_HINT_PANEL, TOWN_HINT_LABEL, PORT_COLUMN_HEADER, PORT_COLUMN_HEADER_LABEL,
		PORT_FACILITY_HINT, MAP_STRATEGIC_POPUP, MAP_STRATEGIC_TITLE,
		MAP_STRATEGIC_INFO, MAP_STRATEGIC_BUTTON,
		LABEL_SEA_HUD_FLEET,
	]
	return theme_name in known
