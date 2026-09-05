extends Node
## 数据加载与全局时间推进中枢。
## 时间推进走 advance_days() 这一个入口，避免各系统各自监听信号导致结算顺序不确定。

## 月结产生的通知（欠饷等），供 UI 显示
signal monthly_notice(text: String)

## 海战上下文。SeaChart 开战前写入；WorldMap._ready 读取；SeaChart 结算后清空。
var pending_battle: Dictionary = {}

var scenes_data: Dictionary = {}
var goods_data: Dictionary = {}
var ports_data: Dictionary = {}
var npcs_data: Dictionary = {}
var discoveries_data: Dictionary = {}
var ships_data: Dictionary = {}
var chapters_data: Dictionary = {}
var crew_data: Dictionary = {}
## 历史压力新闻（酒馆传闻），按 Calendar 年月投放
var news_data: Dictionary = {}


func _ready() -> void:
	load_data()


func load_data() -> void:
	scenes_data = _load_json("res://data/scenes.json")
	goods_data = _load_json("res://data/goods.json")
	ports_data = _load_json("res://data/ports.json")
	npcs_data = _load_json("res://data/npcs.json")
	discoveries_data = _load_json("res://data/discoveries.json")
	ships_data = _load_json("res://data/ships.json")
	chapters_data = _load_json("res://data/chapters.json")
	crew_data = _load_json("res://data/crew.json")
	news_data = _load_json("res://data/news.json")

	if scenes_data.has("scenes"):
		print("Data loaded. Scenes:%d Goods:%d Ports:%d Ships:%d" % [
			scenes_data.get("scenes", []).size(),
			goods_data.get("goods", []).size(),
			ports_data.get("ports", []).size(),
			ships_data.get("ships", []).size(),
		])


func _load_json(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var json = JSON.new()
		var parse_result = json.parse(file.get_as_text())
		if parse_result == OK:
			return json.data
		else:
			push_error("JSON Parse Error in %s: %s (line %d)" % [path, json.get_error_message(), json.get_error_line()])
	else:
		push_error("Could not find " + path)
	return {}


# ── 时间推进 ──────────────────────────────────────────

## 全局唯一的日推进入口。所有按日结算的系统在此依次结算。
func advance_days(n: int) -> void:
	for i in range(n):
		var prev_month: int = Calendar.month
		Calendar.advance_days(1)
		if Calendar.month != prev_month:
			GameState.accrue_interest()
			var notice := Crew.pay_wages()
			if notice != "":
				monthly_notice.emit(notice)
			_settle_history()
			for w in Economy.on_month_changed():
				monthly_notice.emit(w)
		Economy.on_day_passed()
		Fleet.on_day_passed()


# ── 资源 ──────────────────────────────────────────────

# ── 跳年 ──────────────────────────────────────────────

## 章节晋升时跳过若干年。
## 这些年不是「什么都没发生」，而是「你一直在跑船，只是不必一趟趟点」。
## 代价必须真实：船会旧，人会走，行情会忘掉你，士气不会自己攒着。
const SKIP_HULL_DECAY := 0.08      # 每年折旧
const SKIP_HULL_FLOOR := 0.20      # 折到底也留两成，不至于一跳就沉
const SKIP_CREW_LEAVE := 0.12      # 每年每人离船概率
const SKIP_MORALE_AFTER := 65      # 久不出海，人心散了

## 返回摘要行数组，供章节对话框显示
func skip_years(n: int) -> Array:
	if n <= 0:
		return []
	var lines := []
	var y0 := Calendar.year

	# 先把这几年的日子真的走完——新闻、月结、行情回归都照常发生
	for i in range(n):
		advance_days(Calendar.DAYS_PER_MONTH * Calendar.MONTHS_PER_YEAR)

	# 船况折旧
	var decayed := 0
	for sh in Fleet.ships:
		var maxd := float(sh.get("max_durability", 100))
		var cur := float(sh.get("durability", maxd))
		var after := maxf(maxd * SKIP_HULL_FLOOR, cur * pow(1.0 - SKIP_HULL_DECAY, float(n)))
		if after < cur - 0.5:
			decayed += 1
		sh["durability"] = after
	if decayed > 0:
		lines.append("船板泡了%d年海水，%d 条船都该进坞了。" % [n, decayed])

	# 水手流失
	var left := []
	for role_id in Crew.hired.keys().duplicate():
		var leave_p := 1.0 - pow(1.0 - SKIP_CREW_LEAVE, float(n))
		if randf() < leave_p:
			left.append(str(Crew.hired[role_id].get("name", "一个人")))
			Crew.hired.erase(role_id)
	if not left.is_empty():
		lines.append("%s没有再上船——有的回了乡，有的上了别家的船。" % "、".join(left))

	# 士气与行情
	Fleet.morale = mini(Fleet.morale, SKIP_MORALE_AFTER)
	for pid in Economy.rates.keys():
		var pr: Dictionary = Economy.rates[pid]
		for gid in pr.keys():
			pr[gid] = 1.0
	lines.append("市价早不是当年的市价了。")

	lines.append("——%d 年至 %d 年。" % [y0, Calendar.year])
	return lines


## 月初结算历史压力：到期新闻投放；1268 年四月殿试一次性锁定身份。
## 历史是天气不是过场——全部走 monthly_notice，不开新场景。
func _settle_history() -> void:
	if GameState.is_ended():
		return
	if Calendar.year > GameState.IDENTITY_YEAR or (Calendar.year == GameState.IDENTITY_YEAR and Calendar.month >= GameState.IDENTITY_MONTH):
		var r := GameState.resolve_identity_1268()
		if r.get("resolved", false):
			monthly_notice.emit("【%s】%s" % [r["title"], r["text"]])
	for n in GameState.pending_news():
		GameState.mark_news_seen(n.get("id", ""))
		GameState.apply_news_flag(n)
		var speaker: String = str(n.get("speaker", ""))
		var prefix := "【酒馆传闻】" if speaker == "" else "【%s】" % speaker
		monthly_notice.emit(prefix + GameState.news_text(n))


## 按文件头而非扩展名加载图片。
## assets 里有若干 .png 文件实际是 JPEG 内容（图片压缩后沿用了原文件名），
## Godot 的导入器与 Image.load_from_file 都按扩展名选解码器，会直接失败。
func load_texture(path: String) -> Texture2D:
	# 有 .import 时资源系统最快，先走它
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	if not FileAccess.file_exists(path):
		return null

	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8:
		return null

	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0xFF and bytes[1] == 0xD8:                       # JPEG: FF D8
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E:  # PNG: 89 50 4E 47
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0x57 and bytes[1] == 0x45:                     # WEBP: WE(BP)
		err = img.load_webp_from_buffer(bytes)

	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


# ── 查询 ──────────────────────────────────────────────

func get_scene_by_id(scene_id: String) -> Dictionary:
	for s in scenes_data.get("scenes", []):
		if s.get("id") == scene_id:
			return s
	return {}


# 按 id 查询发现物（航路复核、碑拓证据等）
## 剧情 effects 里的 discovery 用中文名（"旧避风澳"），此处按 id 或 name 双向查
func get_discovery_id_by_name(name_or_id: String) -> String:
	for d in discoveries_data.get("discoveries", []):
		if d.get("id") == name_or_id or d.get("name") == name_or_id:
			return str(d.get("id", ""))
	return ""


func get_discovery_by_id(discovery_id: String) -> Dictionary:
	for d in discoveries_data.get("discoveries", []):
		if d.get("id") == discovery_id:
			return d
	return {}


func get_news_by_id(news_id: String) -> Dictionary:
	for n in news_data.get("news", []):
		if n.get("id") == news_id:
			return n
	return {}


func get_good_by_id(good_id: String) -> Dictionary:
	for g in goods_data.get("goods", []):
		if g.get("id") == good_id:
			return g
	return {}


func get_good_name(good_id: String) -> String:
	return get_good_by_id(good_id).get("name", good_id)


func get_port_by_id(port_id: String) -> Dictionary:
	for p in ports_data.get("ports", []):
		if p.get("id") == port_id:
			return p
	return {}


func get_port_name(port_id: String) -> String:
	return get_port_by_id(port_id).get("name", port_id)


## 当前章节下已解锁的港口定义列表
func unlocked_ports() -> Array:
	var out := []
	for p in ports_data.get("ports", []):
		if GameState.is_chapter_reached(p.get("unlock", "ch1")):
			out.append(p)
	return out
