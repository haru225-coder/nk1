class_name FloatingTextConfig extends RefCounted

## NK1-P6-POLISH-004: 浮文（FloatingText）参数配置
## 集中管理所有浮文的速度、生命周期、偏移量、抖动参数
## 便于统一调整游戏反馈节奏

## ── 基础参数（默认）──────────────────────────────────────
const DEFAULT_FLOAT_SPEED: float = 50.0       ## 上浮速度（像素/秒）
const DEFAULT_LIFETIME: float = 1.5           ## 默认生命周期（秒）

## ── 偏移量（各用途）──────────────────────────────────────
const OFFSET_CREW_LOSS := Vector2(-100, -100)  ## 船员损失告警
const OFFSET_SCENERY := Vector2(-120, -80)     ## 航海风景描述
const OFFSET_ECONOMY := Vector2(-200, -120)    ## 经济动态提示
const OFFSET_PORT_NEAR := Vector2(-150, -100)  ## 港口接近提示
const OFFSET_PICKUP := Vector2(0, 0)           ## 拾取提示（原地显示）

## ── 生命周期（各用途，超出默认时）────────────────────────
const LIFETIME_CREW_LOSS: float = 2.0          ## 船员损失（2 秒）
const LIFETIME_SCENERY: float = 3.0            ## 风景描述（3 秒）
const LIFETIME_ECONOMY: float = 4.0            ## 经济动态（4 秒）
const LIFETIME_PORT_NEAR: float = 3.5          ## 港口接近（3.5 秒）
const LIFETIME_PICKUP: float = 1.5             ## 拾取（默认 1.5 秒）

## ── 浮文抖动参数 ─────────────────────────────────────────
const RANDOM_JITTER: float = 20.0             ## 出生位置 ± 随机抖动（像素）

## ── 浮文 Z-Index（显示层级）──────────────────────────────
const Z_INDEX_DEFAULT: int = 100               ## 默认显示层级

## ── 航海风景描述池（NK1-P6: 长航时不枯燥）───────────────
## 与 WorldMap.gd 中的 _VOYAGE_SCENERY 数组保持一致
## 集中后可在 TextMap / JSON 化
const VOYAGE_SCENERY: Array[String] = [
	"远方海天一线，碧波万顷。",
	"一群海鸥掠过桅杆，鸣声不绝。",
	"海面浮起一头巨鲸，喷出水柱后隐入波涛。",
	"云层低垂，海风渐紧，似有风雨将至。",
	"远处隐约可见岛影，绿意葱茏。",
	"夜幕低垂，星辰璀璨，指引航向。",
	"船头劈开浪花，白沫翻飞如雪。",
	"一群飞鱼跃出水面，划过一道道银光。",
	"海风送来远方的螺号声，若有若无。",
	"洋流交汇处，海面泛起异样的波纹。",
]
