extends RefCounted
## 人物系统的画与小件（characters 线）：立绘 / 缩略图 / 小头像、五维条、特技签、阵营签、品级点、小画框，
## 以及人物志的「已识」判定。数据一律经 GameManager（data/characters.json）。
## 只作展示：不接任何玩法数值，不写存档（「见过」只记在本会话的静态表里）。
## 两套皮肤都能用：绢本走 assets/theme/tex 贴图与纸上墨色，夜潮走平面盒与潮光色（UiTheme.IS_JUANBEN 分支）。
## headless（假渲染器）下贴图取不到像素：缩略图直接回落原图，不报错。

const TEX_DIR := "res://assets/theme/tex/"
## 旧绢（小画框的绢边）#cdb88f
const SILK := Color(0.804, 0.722, 0.561)
const INK_EDGE := Color(0.051, 0.043, 0.035, 0.9)
## 小头像取景：512×640 立绘里头面大致落在这一块（油画与墨影卡都按此构图）
const HEAD_REGION := Rect2i(104, 40, 304, 304)
## 终局（chapters 里的 5）：1275 年十二月起
const ENDGAME_YM := 1275 * 12 + 12
const TIER_ORDER := ["protagonist", "major", "crew", "minor", "historical"]
const TIER_NAME := {
	"protagonist": "主角", "major": "要人", "crew": "职事", "minor": "市井", "historical": "史实",
}

## 本会话在见面页见过的人 {id: true}。不入存档：读档后靠进度、雇用记录与传闻重新推得。
static var met: Dictionary = {}
static var _thumbs: Dictionary = {}
static var _box_tex: Dictionary = {}


# ── 数据 ─────────────────────────────────────────────

static func attr_defs() -> Array:
	var defs = GameManager.character_meta().get("attr_def", [])
	return defs if typeof(defs) == TYPE_ARRAY else []


static func trait_def(key: String) -> Dictionary:
	var all = GameManager.character_meta().get("trait_def", {})
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var d = all.get(key, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func faction_def(key: String) -> Dictionary:
	var all = GameManager.character_meta().get("faction_def", {})
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var d = all.get(key, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func attrs_of(ch: Dictionary) -> Dictionary:
	var a = ch.get("attrs", {})
	return a if typeof(a) == TYPE_DICTIONARY else {}


static func traits_of(ch: Dictionary) -> Array:
	var t = ch.get("traits", [])
	return t if typeof(t) == TYPE_ARRAY else []


static func crew_id_of(ch: Dictionary) -> String:
	var src = ch.get("sources", {})
	if typeof(src) != TYPE_DICTIONARY:
		return ""
	var cid = src.get("crew_id")
	return "" if cid == null else str(cid)


## 字号一行：可见段用「；」连起（人物志上屏文本层 courtesy；无则原稿）。例：开局只见「初字德刚」，
## 「咸淳四年御赐字君贲」到终局了结才露出来。空则空串。
static func courtesy_of(ch: Dictionary) -> String:
	var segs = layer(ch).get("courtesy")
	if typeof(segs) == TYPE_ARRAY:
		return "；".join(visible_segments(segs))
	return fill_names(str(ch.get("courtesy", "")).strip_edges())


## 画面上写的名字。主角随 GameState.player_name（殿试走士人线后改「陈文龙」），其余用设定集原名。
static func display_name(ch: Dictionary) -> String:
	if str(ch.get("tier", "")) == "protagonist" and str(GameState.player_name) != "":
		return str(GameState.player_name)
	return str(ch.get("name", ch.get("id", "")))


## 主角此刻的名字（开局「陈子龙」，殿试改名后「陈文龙」）。
static func hero_name() -> String:
	var n := str(GameState.player_name)
	return n if n != "" else "陈子龙"


## 上屏文字里的人名替换：{主角} → 主角此刻的名字；设定集原稿里写死的「陈文龙」在改名之前也换成此刻的名字
## （「陈文龙之母」在宝祐三年读作「陈子龙之母」）。
static func fill_names(text: String) -> String:
	var hero := hero_name()
	var out := text.replace("{主角}", hero)
	if hero != "陈文龙":
		out = out.replace("陈文龙", hero)
	return out


## 身份一行：称谓・籍贯（籍贯括注去掉，只留地名；称谓里已含籍贯时不重复）。
## 称谓先走上屏文本层（按年份取最后一段可见的），原稿里「后为……」这类透底的尾巴截掉；分隔点统一成「・」。
static func identity_line(ch: Dictionary, with_origin := true) -> String:
	var title := codex_title(ch)
	var origin := str(ch.get("origin", "")).strip_edges()
	var cut := origin.find("（")
	if cut > 0:
		origin = origin.substr(0, cut)
	if not with_origin or origin == "" or origin == "未详" or (title != "" and title.find(origin) >= 0):
		return title
	return "%s・%s" % [title, origin] if title != "" else origin


## 生卒：「1232—」「1232—1277」；只知一头时写「卒于 1274」「生于 1236」；都不详返回空串。
## 卒年只在那一年已到（Calendar.year ≥ 卒年）或终局了结后才写——宝祐三年第一次见林阿舶，名下不该写着「卒于 1274」。
static func life_line(ch: Dictionary) -> String:
	var born = ch.get("born")
	var died = ch.get("died")
	if died != null and not (GameState.is_ended() or Calendar.year >= int(died)):
		died = null
	if born == null and died == null:
		return ""
	if born == null:
		return "卒于 %d" % int(died)
	if died == null:
		return "生于 %d" % int(born)
	return "%d—%d" % [int(born), int(died)]


## 五维的一字简称（迷你条用）：航 / 商 / 武 / 学 / 望。
const ATTR_SHORT := {"hang": "航", "shang": "商", "wu": "武", "xue": "学", "wang": "望"}
const PHASE_NAME := ["序章", "第一章", "第二章", "第三章", "第四章", "终局"]


## 出场只写起点：「登场　序章起」「见于　终局」。史实人物写「见于」（传闻、短札里提到），其余写「登场」。
## 不列后面几段——「序章至终局」「第一章、终局」会把此人活到哪一段一并透出来。
static func appear_line(ch: Dictionary) -> String:
	var chs = ch.get("chapters", [])
	if typeof(chs) != TYPE_ARRAY or (chs as Array).is_empty():
		return ""
	var lo := 99
	var hi := -1
	for n in chs:
		var k := int(n)
		if k >= 0 and k < PHASE_NAME.size():
			lo = mini(lo, k)
			hi = maxi(hi, k)
	if hi < 0:
		return ""
	var verb := "见于" if str(ch.get("tier", "")) == "historical" else "登场"
	return "%s　%s%s" % [verb, PHASE_NAME[lo], "起" if hi > lo else ""]


# ── 上屏文本层（data/characters_codex.json）─────────────────
# 设定集 characters.json 的 bio / bio_short 是策划原稿（写着「本作」「玩家」「士人线」、雇佣攻略与结局），不上屏。
# 人物志、见面页一律读这一层：每段 [可见条件, 文字]，按当下年份 / 进度 / 是否了结取可见的几段。

const CODEX_PATH := "res://data/characters_codex.json"
static var _layer_all: Dictionary = {}
static var _rel_from: Dictionary = {}
static var _layer_loaded := false


## 关系签的可见条件（文本层 rel_from：「主将」到景炎元年才成立，「后世齐名」要终局后）；没登记的签恒可见。
static func rel_visible(rel: String) -> bool:
	layer({})
	return segment_visible(_rel_from[rel]) if _rel_from.has(rel) else true


static func layer(ch: Dictionary) -> Dictionary:
	if not _layer_loaded:
		_layer_loaded = true
		if FileAccess.file_exists(CODEX_PATH):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(CODEX_PATH)) == OK and typeof(json.data) == TYPE_DICTIONARY:
				var all = (json.data as Dictionary).get("characters", {})
				if typeof(all) == TYPE_DICTIONARY:
					_layer_all = all
				var rf = (json.data as Dictionary).get("rel_from", {})
				if typeof(rf) == TYPE_DICTIONARY:
					_rel_from = rf
			else:
				push_warning("人物志文本层解析失败：%s" % CODEX_PATH)
		else:
			push_warning("人物志文本层缺失：%s（人物志只显示身份与五维）" % CODEX_PATH)
	var e = _layer_all.get(str(ch.get("id", "")), {})
	return e if typeof(e) == TYPE_DICTIONARY else {}


## 一段的可见条件：0 一直可见；公元年 = 那一年到了；"c2"…"c5" = 进度到了第几段；"end" = 终局了结后。了结后全部可见。
static func segment_visible(cond) -> bool:
	if GameState.is_ended():
		return true
	match typeof(cond):
		TYPE_INT, TYPE_FLOAT:
			return int(cond) <= 0 or Calendar.year >= int(cond)
		TYPE_STRING:
			var s := str(cond)
			if s == "end":
				return false
			if s.begins_with("c") and s.substr(1).is_valid_int():
				return story_phase() >= int(s.substr(1))
	return false


## 可见的几段文字（已换好人名）。
static func visible_segments(segs) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(segs) != TYPE_ARRAY:
		return out
	for s in segs:
		if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 2 and segment_visible(s[0]):
			out.append(fill_names(str(s[1])))
	return out


## 这一栏还有没露出来的段（人物志小传末尾据此添一句「此后之事，尚在将来。」）。
static func has_hidden(segs) -> bool:
	if typeof(segs) != TYPE_ARRAY:
		return false
	for s in segs:
		if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 2 and not segment_visible(s[0]):
			return true
	return false


## 人物志小传（可见段连成一段）。
static func codex_bio(ch: Dictionary) -> String:
	return "".join(visible_segments(layer(ch).get("bio", [])))


static func codex_bio_pending(ch: Dictionary) -> bool:
	return has_hidden(layer(ch).get("bio", []))


## 见面页 / 人物卡上的一句简介。
static func codex_short(ch: Dictionary) -> String:
	return "".join(visible_segments(layer(ch).get("short", [])))


## 其言：文本层给了就按段取可见的，没给就用原稿三句。
static func codex_lines(ch: Dictionary) -> PackedStringArray:
	var segs = layer(ch).get("lines")
	if typeof(segs) == TYPE_ARRAY:
		return visible_segments(segs)
	var out := PackedStringArray()
	var raw = ch.get("lines", [])
	if typeof(raw) == TYPE_ARRAY:
		for l in raw:
			out.append(fill_names(str(l)))
	return out


static func codex_look(ch: Dictionary) -> String:
	var o = layer(ch).get("look")
	return fill_names(str(o if o != null else ch.get("look", "")))


## 又称：文本层给了就按段取可见的（「陈文龙」「元世祖」「瀛国公」这类后来才有的名号，到时候才露），没给就用原稿。
static func codex_alts(ch: Dictionary) -> PackedStringArray:
	var segs = layer(ch).get("alt")
	if typeof(segs) == TYPE_ARRAY:
		return visible_segments(segs)
	var out := PackedStringArray()
	var raw = ch.get("alt_names", [])
	if typeof(raw) == TYPE_ARRAY:
		for a in raw:
			out.append(fill_names(str(a)))
	return out


## 称谓：文本层给了就取最后一段可见的（一段都不可见返回空串）；否则用原稿，截掉「后为……」、统一分隔点。
static func codex_title(ch: Dictionary) -> String:
	var segs = layer(ch).get("title")
	var t := ""
	if typeof(segs) == TYPE_ARRAY:
		var vis := visible_segments(segs)
		t = vis[vis.size() - 1] if not vis.is_empty() else ""
	else:
		t = fill_names(str(ch.get("title", "")).strip_edges())
		var cut := t.find("后为")
		if cut > 0:
			t = t.substr(0, cut).trim_suffix("·").trim_suffix("・")
	return t.replace("·", "・")


static func attr_short(key: String, full: String) -> String:
	return str(ATTR_SHORT.get(key, full.left(1)))


# ── 已识 ─────────────────────────────────────────────

static func note_met(id: String) -> void:
	if id != "":
		met[id] = true


## 人物志里此人是否「已识」。全部由现有状态推得，不新增存档字段：
##   主角恒识；职事（crew_id）须雇过（GameState.crew_history 或此刻在船）；
##   其余：本会话见过、传闻里出现过（news_seen 的说话人或正文提到名字），或进度已到其最早出场的一段
##   （chapters 0=序章开局即识，1=序章走完，2–4=第几章，5=终局 1275 年十二月起）。
static func is_known(ch: Dictionary) -> bool:
	var id := str(ch.get("id", ""))
	if id == "":
		return false
	if str(ch.get("tier", "")) == "protagonist" or met.has(id):
		return true
	var crew_id := crew_id_of(ch)
	if crew_id != "":
		return ever_hired(crew_id)
	if heard_of(ch):
		return true
	return story_phase() >= first_phase(ch)


static func ever_hired(crew_id: String) -> bool:
	if crew_id in GameState.crew_history:
		return true
	for c in Crew.roster():
		if typeof(c) == TYPE_DICTIONARY and str(c.get("id", "")) == crew_id:
			return true
	return false


static func first_phase(ch: Dictionary) -> int:
	var chs = ch.get("chapters", [])
	if typeof(chs) != TYPE_ARRAY or (chs as Array).is_empty():
		return 0
	var lo := 99
	for n in chs:
		lo = mini(lo, int(n))
	return lo


static func story_phase() -> int:
	if GameState.is_ended() or not GameState.siege.is_empty():
		return 5
	if Calendar.year * 12 + Calendar.month >= ENDGAME_YM:
		return 5
	var ch := int(GameState.chapter)
	if ch <= 1 and GameState.visited_ports.is_empty():
		return 0
	return clampi(ch, 1, 4)


## 已投放的传闻里出现过：说话人对得上 speaker_names，或正文里写到其名 / 别名。
static func heard_of(ch: Dictionary) -> bool:
	if GameState.news_seen.is_empty():
		return false
	var names: Array = [str(ch.get("name", ""))]
	var alts = ch.get("alt_names", [])
	if typeof(alts) == TYPE_ARRAY:
		names.append_array(alts)
	var speakers: Array = []
	var src = ch.get("sources", {})
	if typeof(src) == TYPE_DICTIONARY and typeof(src.get("speaker_names", [])) == TYPE_ARRAY:
		speakers = src.get("speaker_names", [])
	for nid in GameState.news_seen:
		var n: Dictionary = GameManager.get_news_by_id(str(nid))
		if n.is_empty():
			continue
		if str(n.get("speaker", "")) != "" and str(n.get("speaker", "")) in speakers:
			return true
		var body := "%s%s%s" % [str(n.get("text", "")), str(n.get("text_S", "")), str(n.get("text_M", ""))]
		for nm in names:
			var s := str(nm)
			if s.length() >= 2 and body.find(s) >= 0:
				return true
	return false


## 职事候选在哪个港候雇（人物志「未识」页的一句提示用）。
static func hire_port_name(ch: Dictionary) -> String:
	var crew_id := crew_id_of(ch)
	if crew_id == "":
		return ""
	var cand: Dictionary = Crew.candidate_def(crew_id)
	var pid := str(cand.get("port", ""))
	return GameManager.get_port_name(pid) if pid != "" else ""


# ── 画 ─────────────────────────────────────────────

static func portrait(ch: Dictionary) -> Texture2D:
	var path := str(ch.get("portrait", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	# 后台线程已经读好的直接取走（顺手把线程任务清掉）；否则同步读
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path) as Texture2D
	return load(path) as Texture2D


## 名册一口气要七十多张：先把读图（解码 + 上传，约占一张缩略图八成的工夫）丢给后台线程，
## 读好了再在主线程缩（get_image 只在主线程取）。已缓存或已在读的不重复请求。
static func request_portrait(ch: Dictionary) -> void:
	var path := str(ch.get("portrait", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path, "Texture2D")


## 这张立绘可以拿来缩了（后台读完，或本来就没在后台读 / 读失败——那就同步读或回落）。
static func portrait_ready(ch: Dictionary) -> bool:
	var path := str(ch.get("portrait", ""))
	if path == "":
		return true
	return ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS


static func _thumb_key(ch: Dictionary, logical: Vector2i, head: bool, edge := Color(0, 0, 0, 0)) -> String:
	var tail := ("h" if head else "") + ("|" + edge.to_html() if edge.a > 0.0 else "")
	return "%s@%dx%d%s" % [str(ch.get("id", "")), logical.x, logical.y, tail]


## 已经缩好的那张（没有返回 null，不现做）。
static func cached_thumb(ch: Dictionary, logical: Vector2i, head := false) -> Texture2D:
	return _thumbs.get(_thumb_key(ch, logical, head)) as Texture2D


## 按显示尺寸（逻辑像素）缩好的立绘：Lanczos 缩到 2 倍、带 mipmap，Retina 与 1× 都清楚。
## head=true 取头面方块（小头像）；edge 不透明时烤一道 1 逻辑像素的边（富文本里的小头像没法另套画框）。
## 缓存按人物 + 尺寸；headless 取不到像素时直接回落原图（不缓存）。
static func thumb(ch: Dictionary, logical: Vector2i, head := false, edge := Color(0, 0, 0, 0)) -> Texture2D:
	var key := _thumb_key(ch, logical, head, edge)
	if _thumbs.has(key):
		return _thumbs[key]
	var full := portrait(ch)
	if full == null:
		return null
	var src: Image = full.get_image()
	if src == null or src.is_empty():
		return full
	var img: Image = src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var region := Rect2i(0, 0, w, h)
	if head:
		var sx := float(w) / 512.0
		var sy := float(h) / 640.0
		region = Rect2i(int(HEAD_REGION.position.x * sx), int(HEAD_REGION.position.y * sy),
			int(HEAD_REGION.size.x * sx), int(HEAD_REGION.size.y * sy))
	else:
		# 按目标宽高比取景：横向居中，纵向偏上（人像头面在上）
		var want := float(logical.x) / float(maxi(logical.y, 1))
		if float(w) / float(h) > want:
			var cw := int(round(h * want))
			region = Rect2i(int((w - cw) * 0.5), 0, cw, h)
		else:
			var chh := int(round(w / want))
			region = Rect2i(0, int((h - chh) * 0.25), w, chh)
	img = img.get_region(region)
	var tw := maxi(1, logical.x * 2)
	var th := maxi(1, logical.y * 2)
	if img.get_width() != tw or img.get_height() != th:
		img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	if edge.a > 0.0:
		for x in tw:
			for y in [0, 1, th - 2, th - 1]:
				img.set_pixel(x, y, edge)
		for y in th:
			for x in [0, 1, tw - 2, tw - 1]:
				img.set_pixel(x, y, edge)
	img.generate_mipmaps()
	var it := ImageTexture.create_from_image(img)
	it.set_size_override(logical)
	_thumbs[key] = it
	return it


## 把一张画糊掉（金字塔式逐级减半再逐级放大，近似 sigma 逻辑像素的高斯）：人物志「未识」详页用，
## 只压暗时还认得出脸和铠甲。不缓存（同时只开一页）；headless 取不到像素返回 null，调用方照旧用原图。
static func blurred(tex: Texture2D, sigma := 12.0) -> Texture2D:
	if tex == null:
		return null
	var src: Image = tex.get_image()
	if src == null or src.is_empty():
		return null
	var img: Image = src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var px_per_logical := float(w) / maxf(1.0, float(tex.get_width()))
	var steps := clampi(int(round(log(maxf(2.0, sigma * px_per_logical * 0.7)) / log(2.0))), 1, 6)
	var sizes: Array = []
	var cw := w
	var chh := h
	for _i in steps:
		sizes.append(Vector2i(cw, chh))
		cw = maxi(2, cw / 2)
		chh = maxi(2, chh / 2)
		img.resize(cw, chh, Image.INTERPOLATE_BILINEAR)
	for i in range(sizes.size() - 1, -1, -1):
		var s: Vector2i = sizes[i]
		img.resize(s.x, s.y, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	out.set_size_override(Vector2i(tex.get_width(), tex.get_height()))
	return out


static func picture(tex: Texture2D, logical: Vector2) -> TextureRect:
	var pic := TextureRect.new()
	pic.texture = tex
	pic.custom_minimum_size = logical
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.clip_contents = true
	return pic


## 小画框：绢本是旧绢裱边 + 焦墨（纸上）/ 泥金（墨上）细线；夜潮沿用 icon_frame 的深底潮光边。
static func mat_style(on_paper: bool, hot := false) -> StyleBox:
	if not UiTheme.IS_JUANBEN:
		var yc := StyleBoxFlat.new()
		yc.bg_color = Color(0.04, 0.10, 0.15, 1.0)
		yc.border_color = Color(UiTheme.TIDE, 1.0 if hot else 0.72)
		yc.set_border_width_all(2 if hot else 1)
		yc.set_corner_radius_all(2)
		yc.set_content_margin_all(3)
		return yc
	var st := StyleBoxFlat.new()
	st.bg_color = SILK
	st.set_content_margin_all(3)
	if hot:
		st.border_color = UiTheme.GOLD_HI
		st.set_border_width_all(2)
	else:
		st.border_color = INK_EDGE if on_paper else Color(UiTheme.GOLD, 0.70)
		st.set_border_width_all(1)
	st.shadow_color = Color(0, 0, 0, 0.30 if on_paper else 0.45)
	st.shadow_size = 3 if on_paper else 5
	st.shadow_offset = Vector2(0, 1)
	return st


## 立绘装进小画框。tex 为 null（查无立绘）时画框里是一方墨，不留白洞。
static func framed(tex: Texture2D, logical: Vector2, on_paper: bool) -> PanelContainer:
	var mat := PanelContainer.new()
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.add_theme_stylebox_override("panel", mat_style(on_paper))
	mat.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mat.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if tex == null:
		mat.add_child(unknown_face(logical, 0))
	else:
		mat.add_child(picture(tex, logical))
	return mat


## 未识之人：一方淡墨，中间一个「？」。glyph_px=0 按画幅自定字号。
static func unknown_face(logical: Vector2, glyph_px := 0) -> Control:
	var face := Panel.new()
	face.custom_minimum_size = logical
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.086, 0.078, 0.070) if UiTheme.IS_JUANBEN else Color(0.03, 0.08, 0.12)
	face.add_theme_stylebox_override("panel", fill)
	var wash_path := "res://assets/ui/nk1/ink_splash_ring.png"
	if UiTheme.IS_JUANBEN and ResourceLoader.exists(wash_path):
		var wash := TextureRect.new()
		wash.set_anchors_preset(Control.PRESET_FULL_RECT)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		wash.texture = load(wash_path)
		wash.modulate = Color(0.55, 0.47, 0.34, 0.30)
		face.add_child(wash)
	var q := Label.new()
	q.text = "？"
	q.set_anchors_preset(Control.PRESET_FULL_RECT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 马善政的全角问号字面居中（文楷的偏左），一笔墨书
	q.add_theme_font_override("font", UiTheme.title_font())
	q.add_theme_font_size_override("font_size", glyph_px if glyph_px > 0 else int(clampf(logical.y * 0.34, 18.0, 110.0)))
	q.add_theme_color_override("font_color", Color(UiTheme.GOLD, 0.55))
	face.add_child(q)
	return face


# ── 字 ─────────────────────────────────────────────

static func label(text: String, px: int, color: Color, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font_for(text) if title else UiTheme.font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 宣纸卡会把 ≥ SIZE_CARD 的字或石青字自动改马善政并放大四号；这里的字号已按版面定好，先标记跳过
	l.set_meta(&"nk1_title", true)
	return l


## 标题字体按整串取：马善政缺其中任何一个字（「黄恮」的恮、「赵溍」的溍），整串改文楷，
## 不让一个名字里逐字回落、两种笔重混排。
static func title_font_for(text: String) -> Font:
	var tf: Font = UiTheme.title_font()
	# 马善政本体（title_font 是带文楷回落的 FontVariation，查字要查本体，否则回落字也算「有」）
	var head: Font = tf
	if tf is FontVariation and (tf as FontVariation).base_font != null:
		head = (tf as FontVariation).base_font
	if head == tf or head == UiTheme.font():
		return tf
	for i in text.length():
		var cp := text.unicode_at(i)
		if cp > 0x2E80 and not head.has_char(cp):
			return UiTheme.font()
	return tf


## 纸上 / 墨上的字色：绢本宣纸卡上换成纸上墨色，夜潮与墨底原样。
static func tone(c: Color, on_paper: bool) -> Color:
	return UiTheme.on_paper(c) if on_paper else c


# ── 五维 ─────────────────────────────────────────────

static func _tex(tex_name: String) -> Texture2D:
	if _box_tex.has(tex_name):
		return _box_tex[tex_name]
	var path := TEX_DIR + tex_name + ".res"
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_box_tex[tex_name] = t
	return t


static func _bar_box(fill: bool) -> StyleBox:
	if UiTheme.IS_JUANBEN:
		var tex := _tex("attr_fill_gold" if fill else "attr_bg")
		if tex != null:
			var st := StyleBoxTexture.new()
			st.texture = tex
			st.texture_margin_left = 5
			st.texture_margin_top = 4
			st.texture_margin_right = 5
			st.texture_margin_bottom = 4
			st.content_margin_left = 3
			st.content_margin_right = 3
			st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
			return st
	var fb := StyleBoxFlat.new()
	fb.set_corner_radius_all(2)
	fb.content_margin_left = 2
	fb.content_margin_right = 2
	if fill:
		fb.bg_color = UiTheme.GOLD if UiTheme.IS_JUANBEN else Color(UiTheme.TIDE, 0.9)
	else:
		fb.bg_color = Color(0, 0, 0, 0.40)
		fb.border_color = Color(UiTheme.GOLD if UiTheme.IS_JUANBEN else UiTheme.TIDE, 0.28)
		fb.set_border_width_all(1)
	return fb


static func bar(v: int, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = 100
	b.value = clampi(v, 0, 100)
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background", _bar_box(false))
	b.add_theme_stylebox_override("fill", _bar_box(true))
	return b


## 五维一栏（墨底用）：「航术 ▬▬▬▬ 18」五行；≥80 的数字点亮泥金。行上悬停看释义。
static func attr_block(ch: Dictionary, bar_w := 168.0, row_px := 16) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "AttrBlock"
	box.add_theme_constant_override("separation", 5)
	var attrs := attrs_of(ch)
	for ad in attr_defs():
		if typeof(ad) != TYPE_DICTIONARY:
			continue
		var key := str(ad.get("key", ""))
		var v := clampi(int(attrs.get(key, 0)), 0, 100)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.tooltip_text = "%s　%s" % [str(ad.get("name", "")), str(ad.get("desc", ""))]
		var nl := label(str(ad.get("name", key)), row_px, UiTheme.TEXT_DIM)
		nl.custom_minimum_size.x = row_px * 2 + 4
		row.add_child(nl)
		row.add_child(bar(v, bar_w, 12))
		var vl := label(str(v), row_px, UiTheme.GOLD_HI if v >= 80 else UiTheme.TEXT)
		vl.custom_minimum_size.x = row_px * 2
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		box.add_child(row)
	return box


## 五维迷你条（宣纸卡用）：五列「航 18」下面一道细条。
static func attr_strip(ch: Dictionary, col_w := 58.0, on_paper := true) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.name = "AttrStrip"
	strip.add_theme_constant_override("separation", 8)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var attrs := attrs_of(ch)
	var fill := UiTheme.PAPER_GOLD if (on_paper and UiTheme.IS_JUANBEN) else UiTheme.GOLD
	var hi := UiTheme.PAPER_CINNABAR if (on_paper and UiTheme.IS_JUANBEN) else UiTheme.GOLD_HI
	var track := Color(UiTheme.PAPER_TEXT, 0.16) if (on_paper and UiTheme.IS_JUANBEN) else Color(0, 0, 0, 0.40)
	for ad in attr_defs():
		if typeof(ad) != TYPE_DICTIONARY:
			continue
		var key := str(ad.get("key", ""))
		var nm := str(ad.get("name", key))
		var v := clampi(int(attrs.get(key, 0)), 0, 100)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.custom_minimum_size.x = col_w
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		col.tooltip_text = "%s %d　%s" % [nm, v, str(ad.get("desc", ""))]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(label(attr_short(key, nm), UiTheme.SIZE_FOOT, tone(UiTheme.TEXT_DIM, on_paper)))
		var num := label(str(v), UiTheme.SIZE_FOOT, tone(UiTheme.TEXT, on_paper))
		num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(num)
		col.add_child(head)
		var mb := MiniBar.new()
		mb.value = v
		mb.fill = hi if v >= 80 else fill
		mb.track = track
		mb.custom_minimum_size = Vector2(col_w, 4)
		col.add_child(mb)
		strip.add_child(col)
	return strip


# ── 品级、特技、阵营 ───────────────────────────────────

## 职事品级点：初习一点、谙熟两点、老练三点（与「初习 / 谙熟 / 老练」同读，不用星号）。
static func pips(level: int, on_paper := true) -> Control:
	var p := Pips.new()
	p.level = clampi(level, 0, 3)
	p.fill = UiTheme.PAPER_CINNABAR if (on_paper and UiTheme.IS_JUANBEN) else UiTheme.GOLD_HI
	p.line = Color(p.fill, 0.55)
	p.tooltip_text = Crew.rank_word(level)
	return p


static func _seal_box() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	# 绢本：签底比朱砂钮深一成二——17px 印面字在原朱砂上实渲染只有 4.41:1（返工 cap3 实测），压深后声明约 6.6
	st.bg_color = UiTheme.SEAL.darkened(0.12) if UiTheme.IS_JUANBEN else UiTheme.SEAL
	st.border_color = Color(0.40, 0.07, 0.06, 0.85) if UiTheme.IS_JUANBEN else Color(1, 0.78, 0.70, 0.45)
	st.set_border_width_all(1)
	st.set_corner_radius_all(2)
	st.corner_detail = 1
	st.content_margin_left = 7
	st.content_margin_right = 7
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	return st


## 一枚特技签：朱砂底、印面字（马善政）。悬停看释义。
static func trait_badge(key: String, px := 16) -> PanelContainer:
	var d := trait_def(key)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _seal_box())
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	badge.tooltip_text = "%s　%s" % [str(d.get("name", key)), str(d.get("desc", ""))]
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(str(d.get("name", key)), px, UiTheme.SEAL_TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(l)
	return badge


static func trait_row(ch: Dictionary, px := 16) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TraitRow"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in traits_of(ch):
		row.add_child(trait_badge(str(t), px))
	return row


## 阵营签：阵营色底 + 设定集里实测过对比度的字色；浅色阵营加焦墨描边（纸上）/ 泥金描边（墨上）。
## 16px 起：15px 文楷在阵营色上抗锯齿后实渲染只剩 3.8–4.3:1（第 2 轮 UX M5）；faction_def 每对声明值 ≥6.0 由 smoke 断言。
static func faction_chip(ch: Dictionary, on_paper := false, px := 16) -> PanelContainer:
	var key := str(ch.get("faction", ""))
	var fd := faction_def(key)
	var chip := PanelContainer.new()
	chip.name = "FactionChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = Color.from_string(str(fd.get("color", "#54585c")), Color(0.33, 0.35, 0.36))
	st.border_color = INK_EDGE if on_paper else Color(UiTheme.GOLD, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(2)
	st.corner_detail = 1
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", st)
	var l := label(str(fd.get("name", key)), px, Color.from_string(str(fd.get("text", "#e9dcc0")), UiTheme.TEXT))
	chip.add_child(l)
	return chip


## 一方朱文小印（两字竖排，印面字），略歪一点像手钤的。人物志「未识」页钤「待访」。
static func stamp(text: String, side := 58.0) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(side, side)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := Control.new()
	inner.size = Vector2(side, side)
	inner.pivot_offset = Vector2(side, side) * 0.5
	inner.rotation = deg_to_rad(-5.0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)
	var path := "res://assets/ui/nk1/seal_blank.png"
	if UiTheme.IS_JUANBEN and ResourceLoader.exists(path):
		var ink := TextureRect.new()
		ink.texture = load(path)
		ink.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ink.stretch_mode = TextureRect.STRETCH_SCALE
		ink.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ink.size = Vector2(side, side)
		ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(ink)
	else:
		var plate := Panel.new()
		plate.size = Vector2(side, side)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel", _seal_box())
		inner.add_child(plate)
	var chars := PackedStringArray()
	for i in text.length():
		chars.append(text.substr(i, 1))
	var l := label("\n".join(chars), int(side * 0.36), UiTheme.SEAL_TEXT, true)
	l.size = Vector2(side, side)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("line_spacing", -int(side * 0.08))
	inner.add_child(l)
	return box


## 泥金细线（墨底分隔）。
static func rule(alpha := 0.45) -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(UiTheme.GOLD, alpha)
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	sep.add_theme_constant_override("separation", 6)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


# ── 小件（自绘） ─────────────────────────────────────

class MiniBar extends Control:
	var value := 0
	var fill := Color.WHITE
	var track := Color(0, 0, 0, 0.3)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, track)
		var w := roundf(size.x * clampf(float(value) / 100.0, 0.0, 1.0))
		if w > 0.0:
			draw_rect(Rect2(0, 0, w, size.y), fill)
			# 一道亮口：像泥金笔锋的反光
			draw_rect(Rect2(0, 0, w, 1), Color(1, 1, 1, 0.18))


class Pips extends Control:
	var level := 0
	var fill := Color.WHITE
	var line := Color.WHITE
	const N := 3
	const D := 8.0
	const GAP := 4.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(N * D + (N - 1) * GAP, D + 2)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var cy := size.y * 0.5
		for i in N:
			var cx := D * 0.5 + i * (D + GAP)
			var pts := PackedVector2Array([
				Vector2(cx, cy - D * 0.5), Vector2(cx + D * 0.5, cy),
				Vector2(cx, cy + D * 0.5), Vector2(cx - D * 0.5, cy),
			])
			if i < level:
				draw_colored_polygon(pts, fill)
			else:
				var ring := pts.duplicate()
				ring.append(pts[0])
				draw_polyline(ring, line, 1.0, true)
