extends SceneTree
## Lane disc2：发现录探针——每港至少两条近侧发现、id 不重、near_ports 合法。
## 用法：godot --headless --path . -s res://tools/qa_w57_discovery_probe.gd
## 输出末行 DISCOVERY_PROBE fails=N；N>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_fail("主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	var disc_text := _read_text("res://data/discoveries.json")
	var ports_text := _read_text("res://data/ports.json")
	if disc_text == "" or ports_text == "":
		_fail("数据文件读不到")
		_report()
		return
	var disc_doc: Dictionary = JSON.parse_string(disc_text)
	var ports_doc: Dictionary = JSON.parse_string(ports_text)
	if typeof(disc_doc) != TYPE_DICTIONARY or typeof(ports_doc) != TYPE_DICTIONARY:
		_fail("JSON 解析失败")
		_report()
		return

	var discoveries: Array = disc_doc.get("discoveries", [])
	var ports: Array = ports_doc.get("ports", [])
	var port_ids := {}
	for p in ports:
		port_ids[str(p.get("id", ""))] = true

	# ids 唯一
	var seen_ids := {}
	var dup := false
	for d in discoveries:
		var did := str(d.get("id", ""))
		if did == "":
			_fail("发现条缺 id")
			continue
		if seen_ids.has(did):
			dup = true
			_fail("发现 id 重复：%s" % did)
		seen_ids[did] = true
	_expect(not dup, "发现 id 不重")

	# near_ports 合法
	var bad_ports := false
	for d in discoveries:
		for pid in d.get("near_ports", []):
			if not port_ids.has(str(pid)):
				bad_ports = true
				_fail("near_ports 含非法港：%s（%s）" % [str(pid), str(d.get("id", ""))])
	_expect(not bad_ports, "near_ports 全部合法")

	# 每港至少两条
	var counts := {}
	for pid in port_ids:
		counts[pid] = 0
	for d in discoveries:
		for pid in d.get("near_ports", []):
			if counts.has(str(pid)):
				counts[str(pid)] += 1
	var bare := []
	for pid in port_ids:
		if int(counts.get(pid, 0)) < 2:
			bare.append("%s(%d)" % [pid, int(counts.get(pid, 0))])
	_expect(bare.is_empty(), "每港至少两条近侧发现" + ("" if bare.is_empty() else "：" + ", ".join(bare)))

	_report()


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 12:
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		if v[0]:
			print("  ✓ " + str(v[1]))
		else:
			_fail(str(v[1]))
	print("DISCOVERY_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
