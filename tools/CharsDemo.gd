extends "res://scripts/chars/CharsDemo.gd"
## 人物演示页 dev 入口（w26-k2 收束薄包装）：原先 tools/ 是 w20-a3 完成版真身、与 scripts/chars/ 双开；
## 真身已回灌运行线（被 scenes/chars/CharsDemo.tscn 引用的本体即在 scripts/chars/CharsDemo.gd），
## 本件只剩一行 extends 继承、补「dev 牌照」——本页读人物数据以「开发工具」身份登记，
## 与运行线（runtime）分账；无任何方法覆盖。
## 键位 / 分栏 / 取景随基类（见基类头注）；入口：`godot --path . scenes/chars/CharsDemo.tscn`（基类被场景挂）。
## 平台：工具/门禁可 load("res://tools/CharsDemo.gd") 走本件，行为与运行线脚本一致。
## 红线：tools/ 件立退 res://scripts/，运行线不可反指 tools/——件被挂脚本到场景则立刻被
## 「正式流程引用了只许开发 / 门禁用的原稿读取者」判红。
## 另：verify_story_data._l1b_scan_file 按文件名单扫、不递归 extends——本件须自带一处 api 命中
## 让「dev 读人物」有字面人证（不然 stale 判红 / 防失明兜底会红）。


## dev 接线自证扶手——base 同名数据访问，只是换身份读同一人物字典（GameManager 取数口）。
## 门禁线「api 类别一字不差」靠这一处命中；工具 / 门禁要按 dev 身份取人时用这个。
func get_character_for_dev(id: String) -> Dictionary:
	return GameManager.get_character(id)
