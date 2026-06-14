class_name IntentResult extends RefCounted

var success: bool
var type: String
var message_key: String
var data: Dictionary

func _init(_success: bool, _type: String, _message_key: String = "", _data: Dictionary = {}) -> void:
	self.success = _success
	self.type = _type
	self.message_key = _message_key
	self.data = _data
