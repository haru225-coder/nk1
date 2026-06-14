class_name Intent extends RefCounted

# 核心防腐原则：Intent 是不可变对象 (Immutable)
# 类似于一张“申请单”，生成后任何人不得修改其内容。
var id: String = ""
var type: String = ""
var source: String = ""
var target: String = ""
var parameters: Dictionary = {}
var context: Dictionary = {}

func _init(_type: String, _source: String, _target: String, _params: Dictionary = {}, _context: Dictionary = {}) -> void:
	self.id = "intent_" + str(randi() % 1000000).pad_zeros(6)
	self.type = _type
	self.source = _source
	self.target = _target
	self.parameters = _params.duplicate(true)
	self.context = _context.duplicate(true)
	# 通过 duplicate 确保内部引用也不可被外部意外修改
