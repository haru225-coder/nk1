extends SceneTree
## Lane T：headless 探针——四种槽态 label/tip。不改正式存档位 1..SLOTS。
## 用法：godot --headless --path . -s res://tools/qa_save_slot_tip_probe.gd
## --script 无 autoload 全局名，须走 /root/SaveLoad。

const SLOT := 97


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var sl: Node = root.get_node_or_null("SaveLoad")
	if sl == null:
		push_error("SaveLoad autoload missing")
		quit(1)
		return
	var fails := 0
	fails += _expect(sl, "none", "未记", "")
	_write_primary(sl, "景炎二年　兴化　100 钱")
	fails += _expect(sl, "primary", "景炎二年　兴化　100 钱", "")
	_corrupt_primary_keep_bak(sl)
	fails += _expect(sl, "bak", "景炎二年　兴化　100 钱", "正本卷页损了，已从副抄翻出。")
	_corrupt_both(sl)
	fails += _expect(sl, "corrupt", "卷页损了", "正本与副抄皆不可读。")
	_cleanup(sl)
	if fails == 0:
		print("SAVE_SLOT_TIP_PROBE PASS")
		quit(0)
	else:
		print("SAVE_SLOT_TIP_PROBE FAIL fails=%d" % fails)
		quit(1)


func _expect(sl: Node, src: String, label: String, tip: String) -> int:
	var got_src := str(sl.call("slot_source", SLOT))
	var got_label := str(sl.call("save_label", SLOT))
	var got_tip := str(sl.call("save_tip", SLOT))
	var ok := got_src == src and got_label == label and got_tip == tip
	print("  %s  src=%s label=%s tip=%s" % ["✓" if ok else "✗", got_src, got_label, got_tip])
	if not ok:
		print("    want src=%s label=%s tip=%s" % [src, label, tip])
	return 0 if ok else 1


func _save_dir(sl: Node) -> String:
	return str(sl.get("SAVE_DIR"))


func _write_primary(sl: Node, label: String) -> void:
	var dir := _save_dir(sl)
	DirAccess.make_dir_recursive_absolute(dir)
	var data := {
		"version": int(sl.get("VERSION")),
		"calendar": {},
		"economy": {},
		"fleet": {},
		"crew": {},
		"state": {},
		"scene": "xinghua",
		"label": label,
	}
	var path := dir + "save_%d.json" % SLOT
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _corrupt_primary_keep_bak(sl: Node) -> void:
	var path := _save_dir(sl) + "save_%d.json" % SLOT
	var bak := path + ".bak"
	DirAccess.copy_absolute(path, bak)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not-json")
	f.close()


func _corrupt_both(sl: Node) -> void:
	var path := _save_dir(sl) + "save_%d.json" % SLOT
	var bak := path + ".bak"
	for p in [path, bak]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("[")
		f.close()


func _cleanup(sl: Node) -> void:
	var path := _save_dir(sl) + "save_%d.json" % SLOT
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
