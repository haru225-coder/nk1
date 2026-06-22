class_name ShipState extends RefCounted

## 船只状态管理模块

var name: String = "未命名船只"
var hp: float = 100.0
var max_hp: float = 100.0
var crew: int = 30
var max_crew: int = 50
var armor_level: int = 1
var sail_level: int = 1
var sail_type: String = "square"

## ── 战斗属性 (Phase 3) ──────────────────────────────────
## 武装评分：火炮数量与威力系数，影响炮击伤害
var artillery: int = 3
## 剑术/肉搏：提督或冲锋队长战斗力，影响白刃战胜损比与单挑胜率
var swordplay: int = 2
## 机动性：船只操控能力，影响T字战法判定与撤退成功率
var maneuverability: int = 5
