extends SceneTree
## Lane w53-5：半写档探针——.tmp 写不全 / 读不回时，记录（save_game）与迁移回写（_write_back_migrated）
## 都不得拿它去顶正本：正本与副抄逐字节不动、.tmp 不留、记录报未成；连着失败两回这一卷也照样读得出。
## 修前：store_string 的成败与写后内容一概不看，正本先退 .bak、坏 .tmp 顶上正本还报「已记入」；
## 再记一回，那份好 .bak 也被冲掉——一卷全毁。迁移回写同病：坏 .tmp 顶上正本，原件只剩 _resolve 不看的 .v<N>。
## 注入法：.tmp 预先建成「只写不可读」（属主只写 0200）——写入照报成功、读回读不出，与磁盘满 / 配额 / I/O 错时
## store_string 只落半截还报成功同属「写了却核不上」。本进程读得动只写文件（root）或平台不给改权限时注入不成立，
## 打 ⚠ 判未测、不出 ✓/✗。只动存档位 93，不碰正式位 1..SLOTS。
## 5 节（lane w53-5 二轮）：正本已坏、副抄尚好时再记一卷——坏正本不得退成 .bak 冲掉那份好副抄
## （崩溃 / 断电留下坏正本后，玩家自然的下一步就是从副抄翻出、接着玩、再记；修前这一记把唯一的好退路换成了坏卷，
## 新正本日后再坏就一卷全无）。
## 用法：godot --headless --path . -s res://tools/qa_w53_5_half_write_probe.gd
## 判绿须 rc=0 且末行 `QA_W53_5_HALF_WRITE_END`（headless 下 SCRIPT ERROR 不自非零退出，缺末行 = 中途空转）。

const SLOT := 93
const WRITE_ONLY := FileAccess.UNIX_WRITE_OWNER  # 只写：属主可写不可读

var sl: Node
var gs: Node
var cases := 0
var fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	sl = root.get_node_or_null("SaveLoad")
	gs = root.get_node_or_null("GameState")
	if sl == null or gs == null:
		push_error("SaveLoad / GameState autoload missing")
		quit(1)
		return
	_cleanup()
	if not _injection_works():
		print("  ⚠ 只写权限对本进程不生效（root 或平台不支持 unix 权限），半写注入未判")
		_cleanup()
		print("QA_W53_5_HALF_WRITE cases=0 fails=0 skipped=1")
		print("QA_W53_5_HALF_WRITE_END")
		quit(0)
		return

	# ── 1 两卷好档：正本 222、副抄 111 ──
	gs.money = 111
	_report("好档一记", bool(sl.save_game(SLOT, "quanzhou")), "")
	gs.money = 222
	_report("好档二记", bool(sl.save_game(SLOT, "quanzhou")), "")
	var prim := _read(_primary())
	var bak := _read(_bak())
	_report("正本 222、副抄 111", prim.contains("222 钱") and bak.contains("111 钱"), "")

	# ── 2 .tmp 写了读不回：记录须报未成，正本 / 副抄一字不动，.tmp 不留 ──
	for round in [1, 2]:
		_plant_write_only_tmp(_primary() + ".tmp")
		gs.money = 333 * round
		var ok: bool = sl.save_game(SLOT, "quanzhou")
		_report("半写第 %d 回：记录报未成" % round, not ok, "save_game=%s" % str(ok))
		_report("半写第 %d 回：正本逐字节未动" % round, _read(_primary()) == prim, _peek(_primary()))
		_report("半写第 %d 回：副抄逐字节未动" % round, _read(_bak()) == bak, _peek(_bak()))
		_report("半写第 %d 回：不留 .tmp" % round, not FileAccess.file_exists(_primary() + ".tmp"), "")
		_report("半写第 %d 回：这一卷仍从正本翻出" % round, str(sl.slot_source(SLOT)) == "primary",
			"slot_source=%s" % str(sl.slot_source(SLOT)))
	gs.money = 1
	var loaded: bool = sl.load_game(SLOT)
	_report("连失两回后读档得正本 222", loaded and int(gs.money) == 222, "load=%s money=%d" % [str(loaded), int(gs.money)])

	# ── 3 注入撤掉：照常记，正本退副抄 ──
	gs.money = 444
	_report("撤注入后照常记录", bool(sl.save_game(SLOT, "quanzhou")), "")
	_report("正本 444、副抄 222", _read(_primary()).contains("444 钱") and _read(_bak()) == prim, "")

	# ── 4 迁移回写读不回：不回写，正本仍是原件，照读迁好的数据 ──
	_cleanup()
	var v3 := {
		"version": int(sl.get("VERSION")), str(sl.get("SCHEMA_KEY")): 3,
		"calendar": {"year": 1260, "month": 5, "day": 3},
		"economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
		"fleet": {"ships": [{"type": "fuchuan", "cargo": {}, "crew": 20}], "water": 30, "food": 30, "morale": 70},
		"crew": {"hired": {"huozhang": {"id": "wu_zhen", "role": "huozhang"}}, "unpaid_months": 0},
		"state": {"money": 555, "last_port": "quanzhou"},
		"scene": "quanzhou", "label": "景定元年　五月初三　泉州　555 钱",
	}
	var v3_text := JSON.stringify(v3, "\t")
	_write(_primary(), v3_text)
	_plant_write_only_tmp(_primary() + ".tmp")
	gs.money = 1
	loaded = sl.load_game(SLOT)
	_report("迁移回写半写：照读迁好的数据", loaded and int(gs.money) == 555, "load=%s money=%d" % [str(loaded), int(gs.money)])
	_report("迁移回写半写：正本仍是原件", _read(_primary()) == v3_text, _peek(_primary()))
	_report("迁移回写半写：不留 .tmp", not FileAccess.file_exists(_primary() + ".tmp"), "")
	_report("迁移回写半写：这一卷仍读得出", str(sl.slot_source(SLOT)) == "primary",
		"slot_source=%s" % str(sl.slot_source(SLOT)))

	# ── 5 正本已坏、副抄尚好：再记一卷，好副抄留着，坏正本不退成 .bak ──
	_cleanup()
	gs.money = 666
	sl.save_game(SLOT, "quanzhou")
	gs.money = 777
	sl.save_game(SLOT, "quanzhou")
	var good_bak := _read(_bak())
	_write(_primary(), "{\"version\": 4, \"calendar\": ")  # 崩溃留下的半截正本
	_report("坏正本时从副抄翻出 666", str(sl.slot_source(SLOT)) == "bak" and bool(sl.load_game(SLOT)) and int(gs.money) == 666,
		"slot_source=%s money=%d" % [str(sl.slot_source(SLOT)), int(gs.money)])
	gs.money = 888
	_report("坏正本时照常记录", bool(sl.save_game(SLOT, "quanzhou")), "")
	_report("新正本 888", _read(_primary()).contains("888 钱"), _peek(_primary()))
	_report("好副抄仍在（未被坏正本冲掉）", _read(_bak()) == good_bak, _peek(_bak()))
	# 新正本日后再坏：仍能从那份好副抄翻出
	_write(_primary(), "[")
	gs.money = 1
	var again: bool = sl.load_game(SLOT)
	_report("新正本再坏仍从副抄翻出 666", again and str(sl.slot_source(SLOT)) == "bak" and int(gs.money) == 666,
		"load=%s slot_source=%s money=%d" % [str(again), str(sl.slot_source(SLOT)), int(gs.money)])

	_cleanup()
	print("QA_W53_5_HALF_WRITE cases=%d fails=%d" % [cases, fails])
	if fails == 0:
		print("QA_W53_5_HALF_WRITE_END")
		quit(0)
	else:
		quit(1)


## 注入前提：只写文件本进程真读不动（root 绕过权限、Windows 不支持 unix 权限时不成立）
func _injection_works() -> bool:
	var probe := _primary() + ".perm"
	_write(probe, "x")
	var err := FileAccess.set_unix_permissions(probe, WRITE_ONLY)
	var readable := FileAccess.open(probe, FileAccess.READ) != null
	DirAccess.remove_absolute(probe)
	return err == OK and not readable


func _plant_write_only_tmp(path: String) -> void:
	_write(path, "")
	FileAccess.set_unix_permissions(path, WRITE_ONLY)


func _report(name: String, ok: bool, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail])
	if not ok:
		fails += 1


func _primary() -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % SLOT


func _bak() -> String:
	return _primary() + ".bak"


## 读不出（不存在或不可读）给「<读不出>」，与任何真内容都不等
func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "<读不出>"
	var t := f.get_as_text()
	f.close()
	return t


func _peek(path: String) -> String:
	var t := _read(path)
	return t if t == "<读不出>" else "%d 字" % t.length()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(str(sl.get("SAVE_DIR")))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp", ".perm", ".v3", ".bak.tmp"]:
		var p: String = _primary() + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
