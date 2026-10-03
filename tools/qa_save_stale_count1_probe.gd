extends SceneTree
## Lane w38-k1：headless 探针——「恰 1 枚已删港名目」临界断言（无门禁 sweep 补位）。
## 母本 tools/save_stale_refs_probe.gd（w25-j3，c0fcb77 登记），构造法同型：写信道存档 →
## load_game 后 last_stale() 直读核验；不经 UI；只动存档位 97，不碰正式位。
## 现网断言零覆盖的缝：scripts/core/SaveLoad.gd 的 audit_stale_refs 港类
##   `if port["count"] > 0:` 若被退化成 `> 1`（j3mut 退化纹 /tmp/w26/k11-j3mut 实证在卷），
## 则「恰 1 枚陈旧港名目」整段漏报（out 不落 "port" 键）而母本探针照旧全绿。
## 本档九案把这处钉死：K1 现网临界 = count==1 且 sample==该 id；K2 三个触发位各仅 1 处指向
## stale 港（visited_ports / last_port / contract.from）各落 count==1；K3 对照组 0 枚（port 键
## 不在）、2 枚（双旧港 count==2），外加同 id 多现只计一枚（_flag_port 去重口径）。共 7 案。
## 用法：godot --headless --path . -s res://tools/qa_save_stale_count1_probe.gd
## 输出含 SCRIPT ERROR 即视为失败；末两行 `STALE_COUNT1 cases=N fails=M` + `QA_STALE_COUNT1_END`。

const SLOT := 97
const STALE_PORT := "old_haven"

var sl: Node
var fails := 0
var cases := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	sl = root.get_node_or_null("SaveLoad")
	if sl == null:
		push_error("SaveLoad autoload missing")
		quit(1)
		return

	# K1 ── 现网临界断言（j3mut 退化纹钉件）
	_case("K1-1 visited_ports 恰 1 枚旧港 → count==1 且 sample==该 id",
		{"state": {"visited_ports": ["quanzhou", STALE_PORT]}},
		{"port": {"count": 1, "sample": STALE_PORT}})

	# K2 ── 三个触发位各仅 1 处指向 stale 港，其余触发位皆洁净仓值
	_case("K2-1 visited_ports 一处 → count==1",
		{"state": {"visited_ports": ["quanzhou", STALE_PORT], "last_port": "quanzhou"}},
		{"port": {"count": 1, "sample": STALE_PORT}})
	_case("K2-2 last_port 一处 → count==1",
		{"state": {"visited_ports": ["quanzhou"], "last_port": STALE_PORT}},
		{"port": {"count": 1, "sample": STALE_PORT}})
	_case("K2-3 contract.from 一处 → count==1",
		{"state": {"visited_ports": ["quanzhou"], "last_port": "quanzhou",
			"contract": {"from": STALE_PORT, "dest": "quanzhou"}}},
		{"port": {"count": 1, "sample": STALE_PORT}})

	# K3 ── 对照
	_case("K3-1 零枚 → port 键不在 out",
		{},
		{"want_keys": []})
	_case("K3-2 双旧港 → count==2",
		{"state": {"visited_ports": ["quanzhou", STALE_PORT], "last_port": "old_port_2"}},
		{"port": {"count": 2, "sample": STALE_PORT}})
	_case("K3-3 同 id 双现（visited_ports+contract.dest）→ 去重只计 count==1",
		{"state": {"visited_ports": ["quanzhou", STALE_PORT],
			"contract": {"from": "quanzhou", "dest": STALE_PORT}}},
		{"port": {"count": 1, "sample": STALE_PORT}})

	_cleanup()
	print("STALE_COUNT1 cases=%d fails=%d" % [cases, fails])
	print("QA_STALE_COUNT1_END")
	quit(1 if fails > 0 else 0)


# ── 造档：母本 _clean() 同型 ─────────────────────────────

func _clean() -> Dictionary:
	return {
		"version": int(sl.get("VERSION")),
		str(sl.get("SCHEMA_KEY")): int(sl.get("SAVE_SCHEMA")),
		"calendar": {"year": 1256, "month": 4, "day": 1},
		"economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
		"fleet": {
			"ships": [
				{"type": "sampan", "name": "无名小艍", "cargo": {}, "crew": 3},
			],
			"water": 60, "food": 60, "morale": 70, "mutiny_cooldown": 0,
		},
		"crew": {"hired": {}, "unpaid_months": 0},
		"state": {
			"money": 500,
			"last_port": "quanzhou",
			"visited_ports": ["quanzhou", "mingzhou"],
			"discoveries_found": [],
			"discoveries_reported": [],
			"met_ids": [],
			"flags": {},
			"player_name": "林探针",
			"contract": {},
			"rumors": {},
			"contract_ban": {},
		},
		"scene": "quanzhou",
		"label": "景炎二年　泉州　500 钱",
	}


## patch 只合 state 各键；其余类（船式 / 勘见 / 人物 / 行年）照洁净档置零触发。
func _fixture(patch: Dictionary) -> Dictionary:
	var data := _clean()
	var st: Dictionary = patch.get("state", {})
	for k in st:
		data["state"][k] = st[k]
	return data


# ── 用例本体 ──────────────────────────────────────────

func _case(name: String, patch: Dictionary, want: Dictionary) -> void:
	cases += 1
	_cleanup()
	_write(_fixture(patch))
	var got_load: bool = sl.call("load_game", SLOT)
	var stale: Dictionary = sl.call("last_stale")

	var ok := got_load == true
	var detail := "load=%s" % str(got_load)

	if want.has("want_keys"):
		var got_keys := {}
		for k in stale.keys():
			got_keys[str(k)] = true
		var want_has := {}
		for k in want["want_keys"]:
			want_has[str(k)] = true
		if want_has.hash() != got_keys.hash():
			ok = false
			detail += " keys=%s 期望 %s" % [JSON.stringify(stale.keys()), JSON.stringify(want["want_keys"])]
	if want.has("port"):
		if not stale.has("port"):
			ok = false
			detail += " port 键不在 out（count 期望 %d 实得 0）" % int(want["port"]["count"])
		else:
			var p: Dictionary = stale["port"]
			var wc := int(want["port"]["count"])
			if int(p.get("count", -1)) != wc:
				ok = false
				detail += " count 期望 %d 实得 %s" % [wc, str(p.get("count", "<缺>"))]
			var ws := str(want["port"]["sample"])
			if str(p.get("sample", "")) != ws:
				ok = false
				detail += " sample 期望 %s 实得 %s" % [ws, JSON.stringify(p.get("sample", ""))]
			if p.has("examples"):
				ok = false
				detail += " examples 未 erase（内部数组漏出到 out）"

	print("  %s %s  %s  out=%s" % [
		"✓" if ok else "✗", name, detail, JSON.stringify(stale)])
	if not ok:
		fails += 1


# ── 档写与清 ─────────────────────────────────────────

func _write(data: Dictionary) -> void:
	var dir: String = str(sl.get("SAVE_DIR"))
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_primary(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _primary() -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % SLOT


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = _primary() + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
