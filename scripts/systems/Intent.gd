class_name Intent extends RefCounted

# ═══════════════════════════════════════════════════════════
# Intent — 不可变意图对象
# ═══════════════════════════════════════════════════════════
# 核心防腐原则：Intent 是不可变对象 (Immutable)
# 类似于一张“申请单”，生成后任何人不得修改其内容。
#
# ID 生成规则：
#   格式: “intent_<16位十六进制>”
#   使用 randi() 的完整 32 位范围 × 2，碰撞概率极低
#   例: “intent_a3f1_7b2e_4c90_d158”
# ═══════════════════════════════════════════════════════════

var id: String = ""
var type: String = ""
var source: String = ""
var target: String = ""
var parameters: Dictionary = {}
var context: Dictionary = {}

func _init(_type: String, _source: String, _target: String, _params: Dictionary = {}, _context: Dictionary = {}) -> void:
	self.id = "intent_%s%s%s%s" % [
		"%04x" % (randi() % 0xFFFF),
		"%04x" % (randi() % 0xFFFF),
		"%04x" % (randi() % 0xFFFF),
		"%04x" % (randi() % 0xFFFF),
	]
	self.type = _type
	self.source = _source
	self.target = _target
	self.parameters = _params.duplicate(true)
	self.context = _context.duplicate(true)
	# 通过 duplicate 确保内部引用也不可被外部意外修改
