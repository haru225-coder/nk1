extends RefCounted
## 陆战骰子（战斗方案 §七「陆战的骰子单独成文件」）：lane w53-p5-siege 从 Main._siege_nangshan 原样搬来。
## 一次接战 = 我方战力对一枚敌军骰：敌军 = randf_range(下限, 上限) × 阵次放大，战力不低于敌军即胜。
## 囊山一阵的胜负增减（折兵、士气、城墙、名声）也记在这里；数值、掷骰次序与搬家前逐字相同——
## 一阵只掷一次全局 randf_range，不另起 RandomNumberGenerator，种子相同则搬家前后同一阵同胜负、同折损。
## 纯静态：不碰 GameState、不建节点；增减由调用方（Main._siege_nangshan）照原先的次序落账。
## 我方战力仍是 GameState.siege_power()（兵 × 士气 × 石手军加成，城墙作底），不在本件。

## 囊山敌军骰：下限 600、上限 1400；第 rd 阵放大 1 + 0.25 × (rd − 1)
const NANGSHAN_LO := 600.0
const NANGSHAN_HI := 1400.0
const NANGSHAN_ROUND_STEP := 0.25

## 囊山一阵的胜负增减：胜，士气加 8、名声加 4、折兵 8%；败，士气减 12、折兵 22%、城墙减 20
const WIN_MORALE := 8
const WIN_FAME := 4
const WIN_LOSS_RATE := 0.08
const LOSE_MORALE := -12
const LOSE_LOSS_RATE := 0.22
const LOSE_WALL := -20


## 一次接战：掷一枚敌军骰 randf_range(lo, hi) × scale，power 不低于它即胜。返回 {enemy 敌军数, won 胜否}
static func clash(power: float, lo: float, hi: float, scale: float) -> Dictionary:
	var enemy := randf_range(lo, hi) * scale
	return {"enemy": enemy, "won": power >= enemy}


## 囊山第 rd 阵的敌军放大倍数
static func nangshan_scale(rd: int) -> float:
	return 1.0 + NANGSHAN_ROUND_STEP * (rd - 1)


## 囊山第 rd 阵：power 是我方战力（GameState.siege_power()）。返回同 clash
static func nangshan(rd: int, power: float) -> Dictionary:
	return clash(power, NANGSHAN_LO, NANGSHAN_HI, nangshan_scale(rd))


## 一阵打完的折兵：troops 取落账那一刻的兵数（胜时士气、名声先落账再算折兵，败时士气先落账——同搬家前）
static func casualties(troops: int, won: bool) -> int:
	return int(troops * (WIN_LOSS_RATE if won else LOSE_LOSS_RATE))
