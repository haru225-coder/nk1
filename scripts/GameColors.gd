class_name GameColors extends RefCounted

## NK1-P6-POLISH-003: 统一游戏颜色常量
## 集中管理 UI/效果/天气等场景使用的颜色
## 便于主题切换、无障碍调整、统一调色

## ── 状态色：警告/危险/成功/信息 ─────────────────────────
## 警告/危险（红色系：饥饿、风暴、灾害、价格暴涨）
const WARNING := Color(1, 0.3, 0.3)                 ## 标准警告红
const WARNING_SOFT := Color(1.0, 0.7, 0.4)           ## 柔和警告橙
const DANGER_TEXT := Color(0.95, 0.55, 0.45)         ## 海关告警红
const DAMAGE := Color(1, 0.28, 0.22)                ## 伤害红（FloatingTextDamage）
const PIRATE_RED := Color(1.0, 0.45, 0.4)            ## 海盗舰队红
const ENEMY_BLIP := Color(1.0, 0.35, 0.35)           ## 雷达敌舰红点

## 成功/许可（绿色系：获得奖励、合法通关、繁荣）
const SUCCESS := Color(0.2, 1.0, 0.2)                ## 拾取成功绿
const PERMIT_OK := Color(0.55, 0.95, 0.7)            ## 海关合法绿
const PRICE_CRASH := Color(0.4, 1.0, 0.4)            ## 价格暴跌绿
const PRICE_DROP := Color(0.7, 1.0, 0.7)             ## 价格下跌浅绿
const PORT_BLIP := Color.GREEN                       ## 雷达港口绿点

## 信息/平静（蓝色系：天气晴朗、风景、海军巡逻）
const INFO := Color(0.5, 0.8, 1)                     ## 信息蓝（晴朗）
const SCENERY := Color(0.7, 0.85, 1.0, 0.9)         ## 风景描述浅蓝
const PATROL_BLUE := Color(0.55, 0.75, 1.0)         ## 海军巡逻蓝
const NAVY_HUD := Color(0, 0.1, 0.2, 0.8)           ## 雷达背景
const RADAR_RING := Color(0.2, 0.5, 0.8)            ## 雷达扫描环

## ── UI 文字色：金/灰/警示 ────────────────────────────────
const TEXT_GOLD := Color(0.98, 0.84, 0.42, 1)       ## 高亮金（任务标题/按钮高亮）
const TEXT_GOLD_BRIGHT := Color(0.98, 0.92, 0.72, 1) ## 港状态栏默认文字
const TEXT_WARN := Color(1.0, 0.75, 0.4, 1)          ## 警告橙（港状态栏 25% 阈值）
const TEXT_DIM := Color(0.62, 0.6, 0.52, 1)          ## 暗淡灰（已完成/禁用）
const TEXT_ICON_DIM := Color(0.72, 0.72, 0.72, 1)   ## 图标灰（已完成）
const TEXT_ICON_AVAILABLE := Color(0.5, 0.5, 0.5, 0.7) ## 图标半透明（不可用）
const FLEET_DEFAULT := Color(0.85, 0.85, 0.9)        ## 默认舰队灰白

## ── 港状态栏专用 ─────────────────────────────────────────
const METER_NORMAL := Color(0.82, 0.62, 0.24, 1)    ## 港状态栏计量条正常
const METER_WARN := Color(0.95, 0.72, 0.28, 1)       ## 港状态栏计量条警告
const METER_DANGER := Color(0.92, 0.38, 0.32, 1)     ## 港状态栏计量条危险

## ── 浮文专用（FloatingText 颜色）─────────────────────────
const FLOATING_ECONOMY := Color(1.0, 0.9, 0.6, 0.85) ## 经济动态浮文（金色）
const FLOATING_PORT_NEAR := Color(0.9, 1.0, 0.8, 0.95) ## 接近港口浮文（奶绿）
const FLOATING_CREW_LOSS := Color.RED                ## 船员损失浮文（红）
const FLOATING_PICKUP := Color(0.2, 1.0, 0.2)        ## 拾取浮文（绿）

## ── 天气与时间 ───────────────────────────────────────────
const LIGHT_NOON := Color(1, 1, 1, 1)                ## 正午
const LIGHT_NIGHT := Color(0.2, 0.2, 0.4, 1.0)       ## 夜晚
const LIGHT_DAWN := Color(0.8, 0.5, 0.4, 1.0)        ## 黎明
const LIGHT_DUSK := Color(0.8, 0.4, 0.2, 1.0)        ## 黄昏
const LIGHT_STORM := Color(0.3, 0.3, 0.4, 1.0)      ## 风暴覆盖
const WEATHER_CLEAR := Color(0.5, 0.8, 1)            ## 晴朗文字
const WEATHER_STORM := Color(1, 0.3, 0.3)            ## 风暴文字
const MAP_LINE := Color(1, 1, 1, 0.3)                ## 港口连接线
const MAP_LABEL := Color(0.8, 0.8, 0.8, 0.8)         ## 海里标签

## ── 模态遮罩 ─────────────────────────────────────────────
const MODAL_TOP := Color(0.02, 0.02, 0.03, 0.72)      ## 模态顶部（半透明黑）
const MODAL_BOTTOM := Color(0.01, 0.01, 0.02, 0.88)   ## 模态底部
const MODAL_DIM := Color(0.02, 0.02, 0.02, 0.82)      ## 模态背景遮罩
const MARKET_BG := Color(0.02, 0.02, 0.02, 0.88)      ## 市集背景

## ── 通用 ─────────────────────────────────────────────────
const WHITE := Color.WHITE
const TRANSPARENT := Color.TRANSPARENT
const RESET := Color(1, 1, 1)                        ## 重置 modulate 用的中性白

## ── 辅助方法 ─────────────────────────────────────────────

## 根据饱和度返回价格趋势色（用于市集 UI）
static func get_price_trend_color(ratio: float) -> Color:
	if ratio >= 2.0: return WARNING                   ## 暴涨
	if ratio >= 1.2: return WARNING_SOFT              ## 上涨
	if ratio <= 0.5: return PRICE_CRASH               ## 暴跌
	if ratio <= 0.8: return PRICE_DROP                ## 下跌
	return TRANSPARENT

## 根据繁荣度返回状态色
static func get_prosperity_color(prosperity: float) -> Color:
	if prosperity > 1.1: return TEXT_GOLD              ## 繁荣
	if prosperity < 0.9: return WARNING                ## 萧条
	return TEXT_GOLD_BRIGHT                           ## 平稳

## 根据 HP/资源比例返回港状态栏色
static func get_ratio_status_color(ratio: float) -> Color:
	if ratio <= 0.1: return WARNING                   ## 危险
	if ratio <= 0.25: return WARNING_SOFT              ## 警告
	return TEXT_GOLD_BRIGHT                           ## 正常
