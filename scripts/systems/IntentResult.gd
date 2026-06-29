class_name IntentResult extends RefCounted

var success: bool = false
var type: String = ""
var error_code: String = ""
var message: String = ""
var message_key: String = ""
var data: Dictionary = {}

func _init(_success: bool = false, _type: String = "", _message_key: String = "", _data: Dictionary = {}) -> void:
	success = _success
	type = _type
	message_key = _message_key
	message = _message_key
	error_code = "" if _success else _message_key
	data = _data

static func ok(data: Dictionary = {}, message_key: String = TextKeys.INTENT_OK) -> IntentResult:
	var r := IntentResult.new()
	r.success = true
	r.message_key = message_key
	r.message = message_key
	r.data = data
	return r

static func error(code: String, msg: String = "", intent_type: String = "") -> IntentResult:
	var r := IntentResult.new()
	r.success = false
	r.error_code = code
	r.type = intent_type
	r.message_key = code
	r.message = msg if msg != "" else code
	return r