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
var titles_data: Dictionary = {}
## 本地 main：按月投放的历史新闻（data/news.json）
var news_data: Dictionary = {}
## 真实岸线（Natural Earth）与绕陆航线，只供海图绘制
var coastline_data: Dictionary = {}
var sealanes_data: Dictionary = {}
var chart_labels_data: Dictionary = {}
## 人物设定集（data/characters.json）：立绘、五维、特技、小传、关系。只作展示，不接任何玩法数值，不入存档。
## 文件缺失或解析失败时回落空表（只打 WARNING），游戏照常。
const CHARACTERS_PATH := "res://data/characters.json"
var characters_data: Dictionary = {}
var _char_list: Array = []
var _char_by_id: Dictionary = {}
var _char_by_npc: Dictionary = {}
var _char_by_crew: Dictionary = {}


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
	titles_data = _load_json("res://data/titles.json")
	news_data = _load_json("res://data/news.json")
	coastline_data = _load_json("res://data/coastline.json")
	sealanes_data = _load_json("res://data/sealanes.json")
	chart_labels_data = _load_json("res://data/chart_labels.json")
	_load_characters()

	if scenes_data.has("scenes"):
		print("Data loaded. Scenes:%d Goods:%d Ports:%d Ships:%d Titles:%d" % [
			scenes_data.get("scenes", []).size(),
			goods_data.get("goods", []).size(),
			ports_data.get("ports", []).size(),
			ships_data.get("ships", []).size(),
			titles_data.get("ranks", []).size(),
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


# ── 人物设定集 ────────────────────────────────────────

func _load_characters() -> void:
	characters_data = {}
	_char_list = []
	_char_by_id = {}
	_char_by_npc = {}
	_char_by_crew = {}
	if not FileAccess.file_exists(CHARACTERS_PATH):
		push_warning("人物设定集缺失：%s（人物志与立绘回落旧图）" % CHARACTERS_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CHARACTERS_PATH)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("人物设定集解析失败：%s（第 %d 行 %s）" % [CHARACTERS_PATH, json.get_error_line(), json.get_error_message()])
		return
	var raw: Dictionary = json.data
	var list = raw.get("characters", [])
	if typeof(list) != TYPE_ARRAY:
		push_warning("人物设定集没有 characters 表：%s" % CHARACTERS_PATH)
		return
	characters_data = raw
	for c in list:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cid := str(c.get("id", ""))
		if cid == "" or _char_by_id.has(cid):
			continue
		_char_list.append(c)
		_char_by_id[cid] = c
		var src = c.get("sources", {})
		if typeof(src) != TYPE_DICTIONARY:
			continue
		var npc_id = src.get("npc_id")
		if npc_id != null and str(npc_id) != "" and not _char_by_npc.has(str(npc_id)):
			_char_by_npc[str(npc_id)] = c
		var crew_id = src.get("crew_id")
		if crew_id != null and str(crew_id) != "" and not _char_by_crew.has(str(crew_id)):
			_char_by_crew[str(crew_id)] = c


## 按人物 id 取一条设定（查无返回空字典）。
func get_character(id: String) -> Dictionary:
	return _char_by_id.get(id, {})


## NPC id → 人物。先认 sources.npc_id，再认同名人物 id（市舶司小吏等不在 npcs.json 的见面人）。
func character_for_npc(npc_id: String) -> Dictionary:
	if _char_by_npc.has(npc_id):
		return _char_by_npc[npc_id]
	return get_character(npc_id)


## 职事候选 id（crew.json candidates）→ 人物。先认 sources.crew_id，再认同名人物 id。
func character_for_crew(crew_id: String) -> Dictionary:
	if _char_by_crew.has(crew_id):
		return _char_by_crew[crew_id]
	return get_character(crew_id)


## 全部人物，按设定集原顺序（主角、主要、次要、职事、史实）。
func all_characters() -> Array:
	return _char_list


## 设定集 meta：attr_def（五维名）、trait_def（特技）、faction_def（阵营色与字色）。
func character_meta() -> Dictionary:
	var m = characters_data.get("meta", {})
	return m if typeof(m) == TYPE_DICTIONARY else {}


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
		var broke := GameState.tick_contract()
		if broke != "":
			monthly_notice.emit(broke)


# ── 资源 ──────────────────────────────────────────────

# ── 跳年 ──────────────────────────────────────────────

## 章节晋升时跳过若干年。
## 这些年不是「什么都没发生」，而是「你一直在跑船，只是不必一趟趟点」。
## 代价必须真实：船会旧，人会走，行情会忘掉你，士气不会自己攒着。
const SKIP_HULL_DECAY := 0.08      # 每年折旧
const SKIP_HULL_FLOOR := 0.20      # 折到底也留两成，不至于一跳就沉
const SKIP_CREW_LEAVE := 0.12      # 每年每人离船概率
const SKIP_MORALE_AFTER := 65      # 久不出海，人心散了

## 小数目写中文（零 至 九十九；liang=true 时单独的二写「两」：两年、两条船）。上屏的册页、城防账用，账目钱数仍写阿拉伯数字。
func cn_num(n: int, liang := false) -> String:
	var d := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n < 0 or n >= 100:
		return str(n)
	if n == 2 and liang:
		return "两"
	if n < 10:
		return d[n]
	var tens := int(n / 10)
	var ones := n % 10
	return ("" if tens == 1 else d[tens]) + "十" + ("" if ones == 0 else d[ones])


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
		# 册页是每章必看的一页：小数目写中文、不留空格（第 2 轮美术 minor 8）
		if decayed == 1:
			lines.append("船板泡了%s年海水，船该进坞了。" % cn_num(n, true))
		else:
			lines.append("船板泡了%s年海水，%s条船都该进坞了。" % [cn_num(n, true), cn_num(decayed, true)])

	# 水手流失
	var left := []
	for role_id in Crew.hired.keys().duplicate():
		var leave_p := 1.0 - pow(1.0 - SKIP_CREW_LEAVE, float(n))
		if randf() < leave_p:
			left.append(str(Crew.hired[role_id].get("name", "一个人")))
			Crew.hired.erase(role_id)
	if not left.is_empty():
		lines.append("%s没有再上船。有的回了乡，有的上了别家的船。" % "、".join(left))

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
## 若干真 PNG 的 .import 被标成 valid=false。ResourceLoader.load() 这两种
## 都会打 ERROR，即便字节本身能解开——所以先读文件头，load() 只作兜底。
func load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() >= 8:
		var img := Image.new()
		var err := ERR_FILE_UNRECOGNIZED
		if bytes[0] == 0xFF and bytes[1] == 0xD8:                       # JPEG: FF D8
			err = img.load_jpg_from_buffer(bytes)
		elif bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E:  # PNG: 89 50 4E 47
			err = img.load_png_from_buffer(bytes)
		elif bytes.size() >= 12 and bytes[8] == 0x57 and bytes[9] == 0x45:  # RIFF....WEBP
			err = img.load_webp_from_buffer(bytes)
		if err == OK:
			return ImageTexture.create_from_image(img)
	return load(path) as Texture2D


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


## 与该港近侧相关的发现物（上陆勘见用）。航中遭遇仍走 Voyage。
func discoveries_near(port_id: String) -> Array:
	var out: Array = []
	for d in discoveries_data.get("discoveries", []):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		if port_id in d.get("near_ports", []):
			out.append(d)
	return out


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


# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══

func get_news_by_id(news_id: String) -> Dictionary:
	for n in news_data.get("news", []):
		if n.get("id") == news_id:
			return n
	return {}


