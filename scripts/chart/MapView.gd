class_name MapView
extends Node2D
## 海图世界：底图、矢量图层、船标、摄像机。只管画与看，不碰航行逻辑。
## 世界坐标 = 投影画布像素（data/chart_projection.json 的 canvas_px），底图纹理按此缩放。
## 所有自绘层在 _draw 里按摄像机缩放反算线宽与字号，缩放时线不变粗、字不变大。

signal port_clicked(port_id: String)
signal camera_changed

const ZOOM_MIN := 0.28   # 4096 画布在 1280 宽下 0.32 才盖满屏；画布外已铺绢底，放宽到 0.28 让远程两港（广州—占城）装进图带
const ZOOM_MAX := 3.2    # 岸线数据 0.008 度、底图 0.9 km/px，再放大只剩折线与糊纹理（近景实测 3.7 倍已显）
## 自动取景（选向 / 发舶 / 回全图框港）的缩放上限，玩家滚轮仍可放到 ZOOM_MAX（w19-g13，用户验图「比例尺也太大了 都看不到海岸线了」）。
## 近港短程（泉州—兴化、兴化—海口）两港相距不足百里，按 120 px 最小框 + pad 0.30 算出来是 1.75（1280×720 图带），
## 窗口一高还会顶到 3.2：一屏只剩港湾一角、比例尺缩到一百里嫌长，底图 0.9 km/px 放大近两倍已发糊。
## 收到 1.5：图带（1280×336 屏幕 px）约合 770×200 公里，港口两侧各露出一段岸线与陆地轮廓，底图每像素放大不过 1.5 倍。
const FRAME_ZOOM_MAX := 1.5
## 航行中镜头跟船：船标离图带边至少留这么多屏幕像素（_follow_ship）
const FOLLOW_MARGIN := 64.0
const DRAG_FRICTION := 6.5
const KM_PER_LI := 0.576

## 颜色（宋绢本矿物色板，出处见 ~/tmp/nk1-map/research/cartography.md §6.4 与 docs/海图重制设计）
const COL_INK := Color(0.165, 0.141, 0.114)          # 墨 #2A241D
const COL_INK_SOFT := Color(0.361, 0.322, 0.278)     # 淡墨 #5C5247
const COL_CINNABAR := Color(0.659, 0.196, 0.165)     # 朱砂 #A8322A
const COL_GOLD := Color(0.769, 0.604, 0.235)         # 金泥 #C49A3C
const COL_AZURITE := Color(0.208, 0.376, 0.498)      # 石青 #35607F
const COL_AZURITE_DEEP := Color(0.122, 0.227, 0.322) # 石青深 #1F3A52
const COL_OCHRE := Color(0.549, 0.369, 0.204)        # 赭石 #8C5E34
const COL_PAPER := Color(0.894, 0.827, 0.682)        # 绢底 #E4D3AE
const COL_SHELL := Color(0.949, 0.922, 0.855)        # 蛤粉 #F2EBDA
## 航段：顺季风朱砂实线；逆风淡墨虚线；途中换风赭石
const COL_ROUTE_FAIR := COL_CINNABAR
const COL_ROUTE_FOUL := COL_INK_SOFT
const COL_ROUTE_MIXED := COL_OCHRE

var proj: ChartProjection
var font: Font
var font_title: Font   # 海名 / 地区名用的仿宋；缺则同 font
var terrain: Sprite2D
var camera: Camera2D
var ship: ShipMarker

var layer_paper: Node2D
var layer_coast: Node2D
var layer_flow: Node2D
var layer_lanes: Node2D
var layer_route: Node2D
var layer_ports: Node2D
var layer_labels: Node2D

## 数据
var ports: Array = []           # 已解锁港口定义
var port_px: Dictionary = {}    # id → Vector2 世界坐标
var coast_rings: Array = []     # 投影后的 PackedVector2Array
var coast_boxes: Array = []     # 每环的 Rect2
var lanes: Dictionary = {}      # "a|b" → [[lon,lat],…]
var labels: Array = []          # chart_labels.json 的 labels（kind / tier）
var flows: Array = []           # chart_labels.json 的 flows（洋流折线，按农历月显隐）
var hazards: Array = []         # chart_labels.json 的 hazards（险地）
var tiers: Dictionary = {"far": [0.0, 1.05], "mid": [0.55, 2.6], "near": [1.3, 99.0]}
var rumored: Array = []         # sealanes meta.rumored：剧情虚构的「传闻海道」，画虚线
var visited: Array = []
var offered: Array = []          # 本手可选的港；空数组 = 不限制
var cal_month: int = 3
var cal_year: int = 1255

## 状态
var origin_id: String = ""
var dest_id: String = ""
var route_color: Color = COL_ROUTE_MIXED
var route_points: PackedVector2Array = PackedVector2Array()
var route_lengths: PackedFloat32Array = PackedFloat32Array()
var route_total: float = 0.0
var known_route: bool = true
var wind_bearing: float = -1.0    # <0 转换期
var mode: float = 0.0             # 0 海图 1 舆图
var flow_phase: float = 0.0
var route_phase: float = 0.0
var ship_progress: float = 0.0
var ship_visible: bool = false

## 摄像机
var _dragging := false
var _drag_last := Vector2.ZERO
var _velocity := Vector2.ZERO
var _cam_tween: Tween
var _follow_tween: Tween                # 跟船平移（_keep_in_band）：与取景补间分开，下一日接着跟时顶掉它重起
var _follow := false                    # 镜头在跟船（set_follow）；玩家拖动 / 缩放即关（_take_camera），船标回到图带里下一日再开
var _ship_goal := Vector2.ZERO          # 船标这一日的落点：跟船按它平移，图带变了也按它保船标
var _ship_tween: Tween
var _mode_tween: Tween
var _hover_port: String = ""
var _drag_moved := 0.0                  # 本次按下以来累计位移（屏幕 px），判点击用
var _drag_last_move_ms := 0             # 最后一次拖动的时刻，松手时判要不要甩出去
var layer_mat: Node2D                   # 画布外的纸边盖层：盖住画到画布外的岸线与网格
var _layout_key := ""                   # 上次算港口布局时的状态键（缩放、镜头、起讫、手牌、船位、年份）
var _port_layout: Dictionary = {}       # 本帧要画的港：id -> {v, r, box, text, sub, pos …}
var _port_label_texts: Dictionary = {}  # 本帧画出的港名 -> true，同名岛名 / 地区名不再标
var _port_obstacles: Array[Rect2] = []  # 港框、船标、已放的港名，地名层避让用
var map_size: Vector2 = Vector2(4096, 4318)


func _ready() -> void:
	proj = ChartProjection.from_json()
	map_size = Vector2(proj.canvas_w, proj.canvas_h)
	# 字体：文楷子集（美术线的 Medium 落地后改指同名路径，见 docs/海图重制设计）；缺了就用 UiTheme 的系统字
	var fp := "res://assets/fonts/LXGWWenKai-Medium.ttf"   # 与美术线统一用 Medium 全字（子集缺「討」等字）
	if ResourceLoader.exists(fp):
		font = load(fp) as Font
	if font == null:
		font = UiTheme.font()
	# 图名字：朱雀仿宋（OFL，TrionesType/zhuque v0.212 子集）——海名、国名 / 地区名用仿宋，取宋刻本气；
	# 港名与小字仍用文楷（仿宋细笔画在 15 px 以下不够清楚）。子集缺的字（阯 等）回退到文楷。
	var tp := "res://assets/fonts/ZhuqueFangsong-nk1.ttf"
	if ResourceLoader.exists(tp):
		font_title = load(tp) as Font
		if font_title is FontFile:
			(font_title as FontFile).fallbacks = [font]
	if font_title == null:
		font_title = font
	_build_nodes()
	set_process(true)


func _build_nodes() -> void:
	# 画布之外铺绢底并描一圈墨线图框：拖到边上或最小缩放时露出的是纸，不是视口底色
	layer_paper = _make_layer("Paper", _draw_paper)
	terrain = Sprite2D.new()
	terrain.centered = false
	var tex := GameManager.load_texture("res://assets/map/terrain_4096.png")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/map/ChartTerrain.gdshader")
	var data_tex := GameManager.load_texture("res://assets/map/mapdata_2048.png")
	if data_tex != null:
		mat.set_shader_parameter("mapdata", data_tex)
	mat.set_shader_parameter("canvas_px", map_size)
	terrain.material = mat
	if tex != null:
		terrain.texture = tex
		terrain.scale = map_size / Vector2(tex.get_size())
	else:
		push_warning("MapView: 底图缺失，只画矢量层")
	add_child(terrain)

	layer_coast = _make_layer("Coast", _draw_coast)
	layer_flow = _make_layer("Flow", _draw_flow)
	layer_lanes = _make_layer("Lanes", _draw_lanes)
	layer_route = _make_layer("Route", _draw_route)
	layer_mat = _make_layer("Mat", _draw_mat)
	layer_labels = _make_layer("Labels", _draw_labels)
	layer_ports = _make_layer("Ports", _draw_ports)

	ship = ShipMarker.new()
	ship.visible = false
	ship.z_index = 5
	add_child(ship)

	camera = Camera2D.new()
	camera.zoom = Vector2(0.5, 0.5)
	camera.position = map_size * 0.5
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()


func _make_layer(n: String, cb: Callable) -> Node2D:
	var l := Node2D.new()
	l.name = n
	l.draw.connect(func(): cb.call(l))
	add_child(l)
	return l


# ══════════════════════════════════════════════════════
#  数据接入
# ══════════════════════════════════════════════════════

func setup(port_defs: Array, coast: Dictionary, lane_data: Dictionary, label_data: Dictionary, visited_ports: Array) -> void:
	ports = port_defs
	visited = visited_ports
	port_px.clear()
	for p in ports:
		port_px[str(p.get("id", ""))] = proj.to_px(float(p.get("lon", 0.0)), float(p.get("lat", 0.0)))
	lanes = lane_data.get("lanes", {})
	rumored = lane_data.get("meta", {}).get("rumored", [])
	labels = label_data.get("labels", [])
	flows = label_data.get("flows", [])
	hazards = label_data.get("hazards", [])
	var t: Dictionary = label_data.get("meta", {}).get("tiers", {})
	if not t.is_empty():
		tiers = t
	coast_rings.clear()
	coast_boxes.clear()
	# 数据是按包围盒裁过的：环上两端都贴在同一条包围盒边上的段是裁边不是岸（103E 西缘在圆锥投影里是一条斜线，
	# 会斜穿云南、老挝汇到画布角上），在那儿把环断成开放折线；没裁边的环才闭合
	var bbox: Array = coast.get("meta", {}).get("bbox", [])
	for ring in coast.get("land", []):
		var n: int = ring.size()
		if n < 3:
			continue
		var cut := PackedByteArray()
		cut.resize(n)
		var start := -1
		for i in n:
			cut[i] = 1 if _on_same_bbox_edge(ring[i], ring[(i + 1) % n], bbox) else 0
			if cut[i] == 1 and start < 0:
				start = (i + 1) % n
		if start < 0:
			var poly := PackedVector2Array()
			for pt in ring:
				poly.append(proj.to_px(float(pt[0]), float(pt[1])))
			_add_coast_piece(poly, true)
			continue
		var piece := PackedVector2Array()
		for k in n:
			var i := (start + k) % n
			var pt = ring[i]
			piece.append(proj.to_px(float(pt[0]), float(pt[1])))
			if cut[i] == 1:
				_add_coast_piece(piece, false)
				piece = PackedVector2Array()
		_add_coast_piece(piece, false)
	_redraw_all()


## 岸线片段入缓存：先把长段加密到 5 世界像素（约 4.5 km）以内，再做一次 Chaikin 切角——数据是 0.008 度简化过的折线，
## 近景折线感重；直接切角会把长段的拐点削掉最多四分之一段长（实测偏离底图岸缘 24 屏幕像素），先加密再切只圆角不走样。
## 闭合环按环平滑并补首点，开放折线保留两端
func _add_coast_piece(src: PackedVector2Array, closed: bool) -> void:
	if src.size() < 2:
		return
	var poly := _chaikin(_densify(src, closed, 5.0), closed)
	if closed:
		poly.append(poly[0])
	var r := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		r = r.expand(v)
	coast_rings.append(poly)
	coast_boxes.append(r)


static func _densify(src: PackedVector2Array, closed: bool, max_len: float) -> PackedVector2Array:
	var n := src.size()
	var out := PackedVector2Array()
	if n < 2:
		return PackedVector2Array(src)
	var segs := n if closed else n - 1
	for i in segs:
		var a := src[i]
		var b := src[(i + 1) % n]
		out.append(a)
		var k := int(ceilf(a.distance_to(b) / max_len))
		for j in range(1, k):
			out.append(a.lerp(b, float(j) / float(k)))
	if not closed:
		out.append(src[n - 1])
	return out


static func _chaikin(src: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var n := src.size()
	var out := PackedVector2Array()
	if n < 3:
		return PackedVector2Array(src)
	var segs := n if closed else n - 1
	if not closed:
		out.append(src[0])
	for i in segs:
		var a := src[i]
		var b := src[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	if not closed:
		out.append(src[n - 1])
	return out


## 两点是否都贴在数据包围盒的同一条边上（bbox = [西, 南, 东, 北]，经纬度）
static func _on_same_bbox_edge(a: Array, b: Array, bbox: Array) -> bool:
	if bbox.size() != 4:
		return false
	var eps := 1e-4
	var ax := float(a[0])
	var ay := float(a[1])
	var bx := float(b[0])
	var by := float(b[1])
	for x_edge in [float(bbox[0]), float(bbox[2])]:
		if absf(ax - x_edge) < eps and absf(bx - x_edge) < eps:
			return true
	for y_edge in [float(bbox[1]), float(bbox[3])]:
		if absf(ay - y_edge) < eps and absf(by - y_edge) < eps:
			return true
	return false


func set_mode(terrain_mode: bool) -> void:
	var target := 1.0 if terrain_mode else 0.0
	if _mode_tween and _mode_tween.is_valid():
		_mode_tween.kill()
	_mode_tween = create_tween()
	_mode_tween.tween_method(func(v: float):
		mode = v
		if terrain and terrain.material:
			terrain.material.set_shader_parameter("mode", v)
		layer_coast.queue_redraw()
		layer_labels.queue_redraw()
	, mode, target, 0.5).set_trans(Tween.TRANS_SINE)


func set_wind(bearing: float) -> void:
	wind_bearing = bearing
	layer_flow.queue_redraw()


## 农历月与年：洋流按月显隐，港口小字按年切换（如温州 1265 起「瑞安府」）
func set_calendar(month: int, year: int) -> void:
	if month == cal_month and year == cal_year:
		return
	cal_month = month
	cal_year = year
	layer_flow.queue_redraw()
	layer_ports.queue_redraw()


## 某层级在当前缩放下是否可见
func _tier_visible(tier: String, z: float) -> bool:
	var r: Array = tiers.get(tier, [0.0, 99.0])
	return z >= float(r[0]) and z <= float(r[1])


## 当前航段：起点、终点、颜色（顺风绿/逆风朱/换风金）、是否熟路
func set_route(from_id: String, to_id: String, color: Color, known: bool) -> void:
	origin_id = from_id
	dest_id = to_id
	route_color = color
	known_route = known
	route_points = lane_points(from_id, to_id)
	route_lengths = PackedFloat32Array()
	route_total = 0.0
	for i in range(route_points.size() - 1):
		var seg := route_points[i].distance_to(route_points[i + 1])
		route_lengths.append(seg)
		route_total += seg
	layer_route.queue_redraw()
	layer_ports.queue_redraw()
	layer_lanes.queue_redraw()


func clear_route() -> void:
	dest_id = ""
	route_points = PackedVector2Array()
	route_total = 0.0
	layer_route.queue_redraw()
	layer_ports.queue_redraw()


## 两港之间的画线点列。sealanes 记了大圆穿陆港对的绕岸折线（key 字母序 "a|b"）；没记录的退回直线。
func lane_points(from_id: String, to_id: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not port_px.has(from_id) or not port_px.has(to_id):
		return pts
	var lo := from_id
	var hi := to_id
	var reverse := false
	if hi < lo:
		lo = to_id
		hi = from_id
		reverse = true
	var lane: Array = lanes.get("%s|%s" % [lo, hi], [])
	if reverse:
		lane = lane.duplicate()
		lane.reverse()
	pts.append(port_px[from_id])
	for w in lane:
		pts.append(proj.to_px(float(w[0]), float(w[1])))
	pts.append(port_px[to_id])
	return pts


# ══════════════════════════════════════════════════════
#  船标
# ══════════════════════════════════════════════════════

func show_ship_at_port(port_id: String) -> void:
	if not port_px.has(port_id):
		return
	ship.visible = true
	ship_visible = true
	ship.position = port_px[port_id]
	ship_progress = 0.0
	_update_ship_scale()


func hide_ship() -> void:
	ship.visible = false
	ship_visible = false


## 船标推到经纬度处（云端 Voyage.point_along_track 按折线里程给点），frac 是已行比例，没有航线的退路里用来描深走过的线。
## 沿画出的航线折线按弧长走，不在像素空间对两点抄直线（一日跨过拐点时船会压到岸上）；
## 朝向取所在线段方向，顺带扣掉了圆锥投影的经线收敛角。没有航线（不该发生）才退回直线。
## 描深（ship_progress）与船标同取折线弧长，不按里程比例 frac：里程按大圆量、折线按投影画布 px 量，南北跨得远的航线
## 两者对不上——占城→博多走到五成五，描深末端落在船标后 33 画布 px，放大看船尾后一截航线像没走过（lane w53-1）
func move_ship_lonlat(lon: float, lat: float, heading_deg: float, frac: float, dur: float) -> Tween:
	var target := proj.to_px(lon, lat)
	var rot := deg_to_rad(heading_deg)
	if _ship_tween and _ship_tween.is_valid():
		_ship_tween.kill()
	ship.visible = true
	ship_visible = true
	var from_pos := ship.position
	var from_rot := ship.rotation
	var from_frac := ship_progress
	_ship_tween = create_tween()
	if route_points.size() >= 2 and route_total > 0.0:
		var s0 := _arc_of_point(from_pos)
		var s1 := _arc_of_point(target)
		_follow_ship(from_pos, _pose_at_arc(s1)[0], dur)
		_ship_tween.tween_method(func(t: float):
			var s := lerpf(s0, s1, t)
			var pose := _pose_at_arc(s)
			ship.position = pose[0]
			ship.rotation = lerp_angle(ship.rotation, pose[1], 0.35)
			ship_progress = 0.0 if route_total <= 0.0 else clampf(s / route_total, 0.0, 1.0)
			_update_ship_scale()
			layer_route.queue_redraw()
		, 0.0, 1.0, maxf(0.01, dur)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_follow_ship(from_pos, target, dur)
		_ship_tween.tween_method(func(t: float):
			ship.position = from_pos.lerp(target, t)
			ship.rotation = lerp_angle(from_rot, rot, t)
			ship_progress = lerpf(from_frac, frac, t)
			_update_ship_scale()
			layer_route.queue_redraw()
		, 0.0, 1.0, maxf(0.01, dur)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return _ship_tween


## 点到航线折线的最近投影处的弧长
func _arc_of_point(p: Vector2) -> float:
	var best_d := INF
	var best_s := 0.0
	var acc := 0.0
	for i in range(route_lengths.size()):
		var a := route_points[i]
		var b := route_points[i + 1]
		var seg := route_lengths[i]
		var f := 0.0
		if seg > 0.0:
			f = clampf((p - a).dot(b - a) / (seg * seg), 0.0, 1.0)
		var q := a.lerp(b, f)
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best_s = acc + f * seg
		acc += seg
	return best_s


## 弧长 s 处的位置与朝向（弧度，图上正北为 0）
func _pose_at_arc(s: float) -> Array:
	return route_pose(0.0 if route_total <= 0.0 else clampf(s / route_total, 0.0, 1.0))


## 船标这一日要走出图带就平移镜头跟上（lane w53-1）：远程（明州—占城、占城—萨摩）缩到最小也装不下起讫两港，
## 发舶取景保起点，船走到半程就钻到航向牌底下，后十几日一路看不见。与补间同时、同长平移，只挪到船标离图带边留
## FOLLOW_MARGIN 屏幕像素，不改缩放。玩家拖开去看别处、船标已不在图带里，不拽回；拖动与甩动惯性中不跟。
## 一日接一日是在上一日船标补间 finished 里同步起的，那一刻同长的跟船补间还差最后一帧——要顶掉它重起，不能当「镜头忙」让掉。
## 取景过渡（发舶框起讫两港、点全图）在走时这一日让它；跟船开着的过渡一完接着跟，关着的过渡中图带在挪、船标在不在带里不作数
func _follow_ship(from_pos: Vector2, to_pos: Vector2, dur: float) -> void:
	_ship_goal = to_pos
	if _dragging or _velocity.length() > 2.0:
		return
	var framing: bool = _cam_tween != null and _cam_tween.is_valid() and _cam_tween.is_running()
	if not _follow:
		if framing or not _band_world_rect().has_point(from_pos):
			return
		_follow = true
	if framing:
		return
	_keep_in_band(to_pos, dur)


## 航行中镜头跟不跟船（lane w53-1）：SeaChart 发舶时开——按住空格一日 0.05 s，发舶取景若要过渡 0.9 s，船在里头走十几日，
## 过渡一完要接着跟；点全图时关——玩家要看全图，全图里没有船标就别拽回去，船标落回图带里下一日自会再开
func set_follow(on: bool) -> void:
	_follow = on
	if not on and _follow_tween and _follow_tween.is_valid():
		_follow_tween.kill()


## 平移镜头让 p 落进图带、离边留 FOLLOW_MARGIN 屏幕像素，不改缩放；还在跑的上一段跟船平移顶掉
func _keep_in_band(p: Vector2, dur: float) -> void:
	var z := camera.zoom.x
	var inner := _band_world_rect().grow(-FOLLOW_MARGIN / z)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0 or inner.has_point(p):
		return
	var shift := Vector2.ZERO
	if p.x < inner.position.x:
		shift.x = p.x - inner.position.x
	elif p.x > inner.end.x:
		shift.x = p.x - inner.end.x
	if p.y < inner.position.y:
		shift.y = p.y - inner.position.y
	elif p.y > inner.end.y:
		shift.y = p.y - inner.end.y
	var goal := _clamped_position(camera.position + shift, z)
	if goal.is_equal_approx(camera.position):
		return
	if _follow_tween and _follow_tween.is_valid():
		_follow_tween.kill()
	_velocity = Vector2.ZERO
	_follow_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_follow_tween.tween_property(camera, "position", goal, maxf(0.01, dur))
	_follow_tween.tween_method(func(_v: float): _on_camera_moved(), 0.0, 1.0, maxf(0.01, dur))


## 这一手风放出的向（云端「风发三向」）：不在其中的港标画淡
func set_offered(ids: Array) -> void:
	offered = ids
	layer_ports.queue_redraw()


func _set_ship_progress(t: float) -> void:
	ship_progress = t
	var pose := route_pose(t)
	ship.position = pose[0]
	ship.rotation = pose[1]
	_update_ship_scale()


## 航线上比例 t 处的位置与朝向（弧度，图上正北为 0）
func route_pose(t: float) -> Array:
	if route_points.size() < 2 or route_total <= 0.0:
		return [ship.position, ship.rotation]
	var want := t * route_total
	var acc := 0.0
	for i in range(route_lengths.size()):
		var seg := route_lengths[i]
		if acc + seg >= want or i == route_lengths.size() - 1:
			var f := 0.0 if seg <= 0.0 else clampf((want - acc) / seg, 0.0, 1.0)
			var a := route_points[i]
			var b := route_points[i + 1]
			var dir := b - a
			var rot := 0.0 if dir.length() < 0.001 else dir.angle() + PI * 0.5
			return [a.lerp(b, f), rot]
		acc += seg
	return [route_points[route_points.size() - 1], ship.rotation]


func _update_ship_scale() -> void:
	# 屏幕上约 30px 长；放大到 4× 时允许长到 1.8 倍，别变成一个像素点也别盖住港湾
	var z := camera.zoom.x
	var screen_px := clampf(30.0 * sqrt(z / 0.5), 24.0, 54.0)
	var s := screen_px / z / ShipMarker.BASE_LEN
	ship.scale = Vector2(s, s)


# ══════════════════════════════════════════════════════
#  摄像机
# ══════════════════════════════════════════════════════

func _process(delta: float) -> void:
	flow_phase += delta * 0.9
	route_phase += delta * 1.6
	if not _dragging and _velocity.length() > 2.0:
		camera.position += _velocity * delta / camera.zoom.x
		_velocity = _velocity.lerp(Vector2.ZERO, clampf(DRAG_FRICTION * delta, 0.0, 1.0))
		_clamp_camera()
		_on_camera_moved()
	layer_flow.queue_redraw()
	if dest_id != "":
		layer_route.queue_redraw()
	if terrain and terrain.material:
		terrain.material.set_shader_parameter("zoom", camera.zoom.x)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(get_global_mouse_position(), 1.18)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(get_global_mouse_position(), 1.0 / 1.18)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_last = mb.position
				_drag_moved = 0.0
				_drag_last_move_ms = Time.get_ticks_msec()
				_velocity = Vector2.ZERO
				_take_camera()
			else:
				_dragging = false
				# 拖住停一会再松手不该再甩出去：最后一次移动距今超过 80 ms 就把速度清零
				if Time.get_ticks_msec() - _drag_last_move_ms > 80:
					_velocity = Vector2.ZERO
				# 点击判定看按下到松手的累计位移，不看瞬时速度（手抖 1 px 也算点）
				var pid := _port_at(_event_world(mb))
				if pid != "" and _drag_moved < 6.0:
					_velocity = Vector2.ZERO
					port_clicked.emit(pid)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			var d: Vector2 = mm.position - _drag_last
			_drag_last = mm.position
			_drag_moved += d.length()
			_drag_last_move_ms = Time.get_ticks_msec()
			camera.position -= d / camera.zoom.x
			_velocity = -d * 60.0
			_velocity = _velocity.limit_length(2400.0)
			_clamp_camera()
			_on_camera_moved()
		else:
			var pid := _port_at(_event_world(mm))
			if pid != _hover_port:
				_hover_port = pid
				layer_ports.queue_redraw()
	elif event is InputEventMagnifyGesture:
		_take_camera()
		_velocity = Vector2.ZERO
		zoom_at(get_global_mouse_position(), (event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		# 取景过渡中双指平移也要立刻接管，否则被 tween 盖掉等于无效
		_take_camera()
		_velocity = Vector2.ZERO
		camera.position += (event as InputEventPanGesture).delta * 3.0 / camera.zoom.x
		_clamp_camera()
		_on_camera_moved()


func zoom_at(world_anchor: Vector2, factor: float) -> void:
	_take_camera()
	var old_z := camera.zoom.x
	var z := clampf(old_z * factor, ZOOM_MIN, ZOOM_MAX)
	# 让锚点在屏幕上不动：锚点相对镜头中心的屏幕偏移 = 世界偏移 × zoom，保持不变
	var offset := world_anchor - camera.position
	camera.zoom = Vector2(z, z)
	camera.position = world_anchor - offset * (old_z / z)
	_clamp_camera()
	_on_camera_moved()


func _clamp_camera() -> void:
	camera.position = _clamped_position(camera.position, camera.zoom.x)


## 镜头中心在给定缩放下的钳位（允许越出画布 4%）
func _clamped_position(pos: Vector2, z: float) -> Vector2:
	var half := get_viewport_rect().size * 0.5 / z
	var margin := map_size * 0.04
	var lo := half - margin
	var hi := map_size - half + margin
	return Vector2(clampf(pos.x, minf(lo.x, hi.x), maxf(lo.x, hi.x)), clampf(pos.y, minf(lo.y, hi.y), maxf(lo.y, hi.y)))


## 露出的图带在世界坐标里的矩形（去掉顶匾与牌区）
func _band_world_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var z := camera.zoom.x
	var top_left := camera.position + Vector2(-vp.x * 0.5, -vp.y * 0.5 + inset_top) / z
	return Rect2(top_left, Vector2(vp.x, maxf(vp.y - inset_top - inset_bottom, 1.0)) / z)


func _on_camera_moved() -> void:
	_update_ship_scale()
	_redraw_all()
	camera_changed.emit()


func _kill_cam_tween() -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	if _follow_tween and _follow_tween.is_valid():
		_follow_tween.kill()


## 玩家亲手动镜头（拖动 / 缩放 / 双指平移）：停掉取景与跟船，不再跟船；下一日船标还在图带里再跟（_follow_ship）
func _take_camera() -> void:
	_kill_cam_tween()
	_follow = false


## HUD 压住的屏幕高度（顶匾 / 底部牌区，屏幕像素）。取景只用中间露出来的那一段，
## 免得起讫港被航向牌盖住。由 SeaChart 在布局后写入。
var inset_top := 0.0
var inset_bottom := 0.0
## 盖在图带上的 HUD 块（屏幕坐标：罗盘、题记框、比例尺，SeaChart 推来）。港名、地名、出带箭头摆的时候当障碍让开
var hud_rects: Array[Rect2] = []


func set_hud_rects(rects: Array) -> void:
	hud_rects.clear()
	for r in rects:
		hud_rects.append(r)
	_layout_key = ""
	_redraw_all()


## 屏幕矩形 → 当前镜头下的世界矩形
func _screen_to_world_rect(r: Rect2) -> Rect2:
	var z := camera.zoom.x
	return Rect2(camera.position + (r.position - get_viewport_rect().size * 0.5) / z, r.size / z)


func set_view_inset(top: float, bottom: float) -> void:
	var changed := absf(top - inset_top) > 0.5 or absf(bottom - inset_bottom) > 0.5
	inset_top = maxf(top, 0.0)
	inset_bottom = maxf(bottom, 0.0)
	if not changed or not is_inside_tree() or camera == null:
		return
	# 图带变了（收牌 / 展牌 / 拉窗口）：起点港或目的港若被挤出图带，平移镜头把它拉回来，不改缩放
	if _cam_tween and _cam_tween.is_valid() and _cam_tween.is_running():
		return
	# 航行中镜头在跟船：保船标这一日的落点，不拉起讫港——远程起点港早出了图带，拉它回来会把船标挤到牌底下（lane w53-1）
	if _follow and ship_visible:
		_keep_in_band(_ship_goal, 0.35)
		return
	var band := _band_world_rect().grow(-56.0 / camera.zoom.x)
	if band.size.x <= 0.0 or band.size.y <= 0.0:
		return
	for pid in [origin_id, dest_id]:
		if pid == "" or not port_px.has(pid):
			continue
		var p: Vector2 = port_px[pid]
		if band.has_point(p):
			continue
		var shift := Vector2.ZERO
		if p.x < band.position.x:
			shift.x = p.x - band.position.x
		elif p.x > band.end.x:
			shift.x = p.x - band.end.x
		if p.y < band.position.y:
			shift.y = p.y - band.position.y
		elif p.y > band.end.y:
			shift.y = p.y - band.end.y
		var target := _clamped_position(camera.position + shift, camera.zoom.x)
		_velocity = Vector2.ZERO
		_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_cam_tween.tween_property(camera, "position", target, 0.35)
		_cam_tween.tween_method(func(_v: float): _on_camera_moved(), 0.0, 1.0, 0.35)
		return


## 取景到一组港口（世界矩形外扩 pad 比例），平滑过去。
## anchor_id：装不下全部港口时（如第四章占城到高丽 2700 公里），至少保证这一港露在图带里；
## 没传就默认起点港（选向 / 发舶取景也一样保起点，目的地出带时港标层会在图带边上画箭头指向它）。
func frame_ports(ids: Array, pad: float = 0.28, dur: float = 0.8, anchor_id: String = "") -> void:
	var use := []
	for id in ids:
		if port_px.has(id):
			use.append(id)
	if use.is_empty():
		return
	if anchor_id == "" and origin_id in use:
		anchor_id = origin_id
	var r := _rect_of(use)
	# 全部港装不下时退而框「起点 + 本手可选港」，其余港让位（全图默认取景把手牌港压在牌下的问题）
	if use.size() > 2 and not offered.is_empty() and _fit_zoom(r, pad) < ZOOM_MIN:
		var sub := []
		for id in use:
			if id == origin_id or id in offered:
				sub.append(id)
		if not sub.is_empty():
			r = _rect_of(sub)
	var anchor: Vector2 = port_px[anchor_id] if port_px.has(anchor_id) else Vector2(INF, INF)
	frame_rect(r, pad, dur, anchor)


func _rect_of(ids: Array) -> Rect2:
	var r := Rect2(port_px[ids[0]], Vector2.ZERO)
	for id in ids:
		r = r.expand(port_px[id])
	return r


## 把矩形装进露出的图带需要的缩放（未钳位）
func _fit_zoom(r: Rect2, pad: float) -> float:
	var vp := get_viewport_rect().size
	var clear_h := maxf(vp.y - inset_top - inset_bottom, vp.y * 0.25)
	var w := maxf(r.size.x, 120.0) * (1.0 + pad * 2.0)
	var h := maxf(r.size.y, 120.0) * (1.0 + pad * 2.0)
	return minf(vp.x / w, clear_h / h)


func frame_rect(r: Rect2, pad: float = 0.28, dur: float = 0.8, anchor: Vector2 = Vector2(INF, INF)) -> void:
	var vp := get_viewport_rect().size
	# 露出来的图带：整个视口去掉顶匾与底部牌区；缩放按这段算，目标点落在这段的中央
	var z := clampf(_fit_zoom(r, pad), ZOOM_MIN, FRAME_ZOOM_MAX)
	# 图带中心比屏幕中心低 (top - bottom)/2 像素；镜头中心要反向偏这么多世界单位
	var target := r.get_center() + Vector2(0.0, (inset_bottom - inset_top) * 0.5 / z)
	# 最小缩放仍装不下时，把镜头挪到锚点港落进图带内（留 56 px 边，名字与船标都露出来）
	if is_finite(anchor.x) and is_finite(anchor.y):
		var m := 56.0 / z
		var half_w := vp.x * 0.5 / z
		var band_top := target.y - (vp.y * 0.5 - inset_top) / z
		var band_bottom := target.y + (vp.y * 0.5 - inset_bottom) / z
		if anchor.y < band_top + m:
			target.y += anchor.y - (band_top + m)
		elif anchor.y > band_bottom - m:
			target.y += anchor.y - (band_bottom - m)
		if anchor.x < target.x - half_w + m:
			target.x += anchor.x - (target.x - half_w + m)
		elif anchor.x > target.x + half_w - m:
			target.x += anchor.x - (target.x + half_w - m)
	# 先按目标缩放钳位，tween 走完就不会再跳一下
	target = _clamped_position(target, z)
	_kill_cam_tween()
	_velocity = Vector2.ZERO
	# 已在这一取景上（选向时框过、发舶再框一遍）不起空转补间：它占着镜头 0.9 s，跟船得让，按住空格时船在里头走出十几日（lane w53-1）
	if dur <= 0.0 or (target.is_equal_approx(camera.position) and is_equal_approx(z, camera.zoom.x)):
		camera.zoom = Vector2(z, z)
		camera.position = target
		_on_camera_moved()
		return
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(camera, "zoom", Vector2(z, z), dur)
	_cam_tween.tween_property(camera, "position", target, dur)
	# 过程中同步重绘：线宽、字号、比例尺跟着缩放走（与 zoom / position 在同一并行组里，不是走完再空转）
	_cam_tween.tween_method(func(_v: float): _on_camera_moved(), 0.0, 1.0, dur)
	_cam_tween.set_parallel(false)
	_cam_tween.tween_callback(func():
		_clamp_camera()
		_on_camera_moved()
	)


func world_visible_rect() -> Rect2:
	var half := get_viewport_rect().size * 0.5 / camera.zoom.x
	return Rect2(camera.position - half, half * 2.0)


## 鼠标事件落在图上的世界坐标：按事件自己的位置换算（推进来的就是那一点），不另去读这一刻的系统鼠标
func _event_world(ev: InputEventMouse) -> Vector2:
	return (make_input_local(ev) as InputEventMouse).position


## 点 / 悬停落在哪个港：先看落没落在这一帧画出来的港框（外扩 3 屏幕 px，叠着取最近）上，再看落没落在港名上，
## 都不是才取离港位 14 屏幕 px 内的最近港（港框小，手抖也点得中）。原先只认港位 14 px：港名摆在港框右侧或上下左、
## 离港位十几到五六十 px，玩家照字点「泉州」没有反应，要点字旁那个小方框才算；缩远时「兴化海口」的字又落在福州港位
## 14 px 内，点字点成福州。港名在先、14 px 在后，点哪个字就是哪个港（lane w53-1）
func _port_at(world: Vector2) -> String:
	_ensure_layout()
	var best := ""
	var best_d := INF
	for pid: String in _port_layout.keys():
		var L: Dictionary = _port_layout[pid]
		if (L["box"] as Rect2).grow(_px(3.0)).has_point(world):
			var d0 := (L["v"] as Vector2).distance_to(world)
			if d0 < best_d:
				best_d = d0
				best = pid
	if best != "":
		return best
	for pid: String in _port_layout.keys():
		if (_port_layout[pid]["rect"] as Rect2).has_point(world):
			return pid
	best_d = 14.0 / camera.zoom.x
	for id in port_px.keys():
		var d: float = port_px[id].distance_to(world)
		if d < best_d:
			best_d = d
			best = id
	return best


func _near_port(world: Vector2, radius: float) -> bool:
	for id in port_px.keys():
		if (port_px[id] as Vector2).distance_to(world) < radius:
			return true
	return false


func _redraw_all() -> void:
	for l in [layer_paper, layer_coast, layer_flow, layer_lanes, layer_route, layer_mat, layer_labels, layer_ports]:
		if l:
			l.queue_redraw()


# ══════════════════════════════════════════════════════
#  绘制工具
# ══════════════════════════════════════════════════════

func _px(screen_px: float) -> float:
	return screen_px / camera.zoom.x


## 屏幕像素字号画字：局部变换按 1/zoom 缩放，字在任何缩放下都是 size_px 大；f 不传就用 font（文楷）
func _text(ci: CanvasItem, world_pos: Vector2, text: String, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, outline: bool = true, f: Font = null) -> void:
	var fnt: Font = f if f != null else font
	var z := camera.zoom.x
	ci.draw_set_transform(world_pos, 0.0, Vector2(1.0 / z, 1.0 / z))
	var w := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var ox := 0.0
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		ox = -w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		ox = -w
	if outline:
		ci.draw_string_outline(fnt, Vector2(ox, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(COL_SHELL, 0.90))
	ci.draw_string(fnt, Vector2(ox, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 竖排（海名用）：一字一行
func _text_vertical(ci: CanvasItem, world_pos: Vector2, text: String, size_px: int, col: Color, spacing: float = 1.15, f: Font = null) -> void:
	var fnt: Font = f if f != null else font
	var z := camera.zoom.x
	ci.draw_set_transform(world_pos, 0.0, Vector2(1.0 / z, 1.0 / z))
	var y := 0.0
	for ch in text:
		var w := fnt.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		ci.draw_string_outline(fnt, Vector2(-w * 0.5, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 3, Color(COL_SHELL, 0.72))
		ci.draw_string(fnt, Vector2(-w * 0.5, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
		y += size_px * spacing
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text_width_world(text: String, size_px: int, f: Font = null) -> float:
	var fnt: Font = f if f != null else font
	return fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x / camera.zoom.x


# ══════════════════════════════════════════════════════
#  图层绘制
# ══════════════════════════════════════════════════════

## 岸线墨线 + 计里画方
## 计里画方当前一方折多少里（题记框按它写「每方折地百里 / 五百里 / 千里」）
func grid_step_li() -> float:
	var z := camera.zoom.x
	return 1000.0 if z < 1.1 else (500.0 if z < 2.2 else 100.0)


func _draw_coast(ci: CanvasItem) -> void:
	var view := world_visible_rect().grow(40.0)
	# 计里画方：宋《禹迹图》每方折地百里。缩得远时改千里方，免得糊成一片。只画在画布内。
	var li_per_px := proj.km_per_px_at(120.0, 25.0) / KM_PER_LI
	var step := grid_step_li() / li_per_px
	var grid_col := Color(COL_INK, 0.10 + 0.05 * mode)
	var gv := view.intersection(Rect2(Vector2.ZERO, map_size))
	if gv.size.x > 0.0 and gv.size.y > 0.0:
		var x := floorf(gv.position.x / step) * step
		while x < gv.end.x:
			if x >= gv.position.x:
				ci.draw_line(Vector2(x, gv.position.y), Vector2(x, gv.end.y), grid_col, _px(1.0))
			x += step
		var y := floorf(gv.position.y / step) * step
		while y < gv.end.y:
			if y >= gv.position.y:
				ci.draw_line(Vector2(gv.position.x, y), Vector2(gv.end.x, y), grid_col, _px(1.0))
			y += step
	# 岸线：只画视窗相交的片段（闭合环在缓存里已补首点；裁边处断开的是开放折线）；线宽 1.25 屏幕像素
	var w := _px(1.25)
	var col := Color(COL_INK, 0.78)
	for i in coast_rings.size():
		if not (coast_boxes[i] as Rect2).intersects(view):
			continue
		ci.draw_polyline(coast_rings[i], col, w, true)


## 季风流线：全图匀布的短划，沿风向缓缓流动；洋流（flows）按折线画流动虚线
func _draw_flow(ci: CanvasItem) -> void:
	var view := world_visible_rect()
	var z := camera.zoom.x
	if wind_bearing >= 0.0:
		var dir := Vector2(sin(deg_to_rad(wind_bearing)), -cos(deg_to_rad(wind_bearing)))
		var perp := Vector2(-dir.y, dir.x)
		var spacing := _px(72.0)
		var len := _px(18.0)
		var col := Color(COL_AZURITE, 0.30)
		# 以风向为轴建网格，划线沿轴滑动。上下界要看视窗四个角在轴上的投影（只看两个角，东北风时 u 区间是空的，一根都不画）
		var corners := [view.position, Vector2(view.end.x, view.position.y), view.end, Vector2(view.position.x, view.end.y)]
		var umin := INF
		var umax := -INF
		var vmin := INF
		var vmax := -INF
		for c in corners:
			var cv: Vector2 = c
			umin = minf(umin, cv.dot(dir))
			umax = maxf(umax, cv.dot(dir))
			vmin = minf(vmin, cv.dot(perp))
			vmax = maxf(vmax, cv.dot(perp))
		var u0 := floorf((umin - spacing * 2.0) / spacing)
		var u1 := ceilf((umax + spacing * 2.0) / spacing)
		var v0 := floorf((vmin - spacing * 2.0) / spacing)
		var v1 := ceilf((vmax + spacing * 2.0) / spacing)
		var shift := fmod(flow_phase * spacing * 0.35, spacing)
		var vi := v0
		while vi <= v1:
			var ui := u0
			var stagger := 0.5 * spacing if int(vi) % 2 == 0 else 0.0
			while ui <= u1:
				var c := dir * (ui * spacing + shift + stagger) + perp * (vi * spacing)
				if view.grow(spacing).has_point(c):
					var a := c - dir * len * 0.5
					var b := c + dir * len * 0.5
					ci.draw_line(a, b, col, _px(1.2), true)
					ci.draw_line(b, b - dir * _px(5.0) + perp * _px(2.6), col, _px(1.2), true)
					ci.draw_line(b, b - dir * _px(5.0) - perp * _px(2.6), col, _px(1.2), true)
				ui += 1.0
			vi += 1.0
	# 洋流折线（黑潮、沿岸流…）：流动虚线，按农历月显隐；暖流金泥、寒流石青
	for f in flows:
		var months: Array = f.get("months", [])
		if not months.is_empty() and not (cal_month in months):
			continue
		var pts: Array = f.get("points", [])
		if pts.size() < 2:
			continue
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(proj.to_px(float(p[0]), float(p[1])))
		var warm := str(f.get("kind", "warm")) == "warm"
		var fcol := Color(COL_GOLD, 0.50) if warm else Color(COL_AZURITE, 0.42)
		_draw_flow_dashes(ci, poly, fcol, _px(2.0), _px(14.0), _px(10.0), flow_phase * _px(30.0))
		if z >= 0.75 and str(f.get("text", "")) != "":
			var mid_i := poly.size() / 2
			_text(ci, poly[mid_i] + Vector2(0, _px(-6)), str(f.get("text", "")), 12, Color(COL_OCHRE if warm else COL_AZURITE, 0.8), HORIZONTAL_ALIGNMENT_CENTER)


## 沿折线画虚线：划段按整条折线的弧长排布，跨顶点不断；phase 为弧长偏移，递增即流动
func _draw_flow_dashes(ci: CanvasItem, poly: PackedVector2Array, col: Color, w: float, dash: float, gap: float, phase: float) -> void:
	var period := dash + gap
	if period <= 0.0:
		return
	var start := -fmod(phase, period)   # 第一段划的弧长起点（≤ 0）
	var acc := 0.0                       # 当前线段起点的弧长
	for i in range(poly.size() - 1):
		var a := poly[i]
		var b := poly[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var dir := (b - a) / seg
		var k := floorf((acc - start) / period)
		var t := start + k * period
		while t < acc + seg:
			var s0 := maxf(t, acc) - acc
			var s1 := minf(t + dash, acc + seg) - acc
			if s1 > s0:
				ci.draw_line(a + dir * s0, a + dir * s1, col, w, true)
			t += period
		acc += seg


## 画布外的绢底：底图只覆盖投影画布，镜头钳位允许越界 4%，最小缩放时四周也会露边
func _draw_paper(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(-map_size, map_size * 3.0), COL_PAPER, true)


## 纸边盖层（画在岸线 / 网格 / 航线之上、地名之下）：岸线数据是 103–143E / 1–49N 裁的，比画布宽一圈，
## 网格也按视窗画，这里用四条纸边把画布外的一切盖掉，再描图框——宋石刻图边栏外粗内细双线
func _draw_mat(ci: CanvasItem) -> void:
	var big := map_size * 3.0
	ci.draw_rect(Rect2(Vector2(-big.x, -big.y), Vector2(big.x * 2.0 + map_size.x, big.y)), COL_PAPER, true)
	ci.draw_rect(Rect2(Vector2(-big.x, map_size.y), Vector2(big.x * 2.0 + map_size.x, big.y)), COL_PAPER, true)
	ci.draw_rect(Rect2(Vector2(-big.x, 0.0), Vector2(big.x, map_size.y)), COL_PAPER, true)
	ci.draw_rect(Rect2(Vector2(map_size.x, 0.0), Vector2(big.x, map_size.y)), COL_PAPER, true)
	ci.draw_rect(Rect2(Vector2.ZERO, map_size).grow(_px(10.0)), Color(COL_INK, 0.55), false, _px(3.0))
	ci.draw_rect(Rect2(Vector2.ZERO, map_size).grow(_px(4.0)), Color(COL_INK, 0.45), false, _px(1.0))


## 熟路淡线 / 传闻海道虚线：已解锁港口之间的 connections
func _draw_lanes(ci: CanvasItem) -> void:
	var drawn := {}
	for p in ports:
		var a := str(p.get("id", ""))
		for cid in p.get("connections", []):
			var b := str(cid)
			if not port_px.has(b):
				continue
			var key := a + "|" + b if a < b else b + "|" + a
			if drawn.has(key):
				continue
			drawn[key] = true
			if (a == origin_id and b == dest_id) or (b == origin_id and a == dest_id):
				continue
			var pts := lane_points(a, b)
			if key in rumored:
				_draw_flow_dashes(ci, pts, Color(COL_INK, 0.30), _px(1.0), _px(5.0), _px(6.0), 0.0)
			else:
				ci.draw_polyline(pts, Color(COL_INK, 0.26), _px(1.0), true)


## 当前航段：流动虚线 + 起终点
func _draw_route(ci: CanvasItem) -> void:
	if route_points.size() < 2:
		return
	# 底衬：蛤粉宽线。沿岸航段的赭石 / 淡墨线压在赭石岸上会消失（第三章明州→广州实测），衬一层纸色才读得出
	ci.draw_polyline(route_points, Color(COL_SHELL, 0.62), _px(6.5), true)
	ci.draw_polyline(route_points, Color(route_color, 0.18), _px(4.0), true)
	if known_route and route_color != COL_ROUTE_FOUL:
		ci.draw_polyline(route_points, route_color, _px(2.2), true)
	else:
		# 生路或逆风：虚线（《舆地图》式：可行段实线，逆风段淡墨虚线）
		_draw_flow_dashes(ci, route_points, route_color, _px(2.2), _px(9.0), _px(7.0), 0.0)
	# 流向：沿线滑动的亮点
	_draw_flow_dashes(ci, route_points, Color(COL_SHELL, 0.9), _px(2.6), _px(4.0), _px(26.0), route_phase * _px(40.0))
	# 已走过的部分描深
	if ship_visible and ship_progress > 0.0:
		var walked := PackedVector2Array()
		var want := ship_progress * route_total
		var acc := 0.0
		walked.append(route_points[0])
		for i in range(route_lengths.size()):
			var seg := route_lengths[i]
			if acc + seg >= want:
				var f := 0.0 if seg <= 0.0 else (want - acc) / seg
				walked.append(route_points[i].lerp(route_points[i + 1], f))
				break
			walked.append(route_points[i + 1])
			acc += seg
		if walked.size() >= 2:
			ci.draw_polyline(walked, Color(COL_INK, 0.55), _px(2.6), true)


## 港口标：宋《地理图》式「州府加方框」——朱砂方框、蛤粉内填；市舶司港双框；当前所在加墨圈，目的地加金圈。
## 名字用 chart.label（繁体），小字 chart.sub（按年切换）；远景只留市舶港与本手可选的港，免得叠字。
## 先由 _ensure_layout 算好这一帧画哪些港、名字放哪（避开别的港框、船标、已放的名字），地名层也用同一份布局避让。
func _draw_ports(ci: CanvasItem) -> void:
	_ensure_layout()
	for pid: String in _port_layout.keys():
		var L: Dictionary = _port_layout[pid]
		var p: Dictionary = L["p"]
		var chart: Dictionary = p.get("chart", {})
		var v: Vector2 = L["v"]
		var r: float = L["r"]
		var box: Rect2 = L["box"]
		var is_here := pid == origin_id
		var is_dest := pid == dest_id
		var seen: bool = pid in visited
		var hov := pid == _hover_port
		var offered_now: bool = offered.is_empty() or (pid in offered)
		var shibo: bool = bool(chart.get("shibo", false))
		var alpha := 1.0 if offered_now else 0.45
		# 方框：蛤粉内填 + 朱砂框；市舶司港外加一圈
		ci.draw_rect(box, Color(COL_SHELL, 0.95 * alpha), true)
		ci.draw_rect(box, Color(COL_CINNABAR, alpha), false, _px(1.5))
		if shibo:
			ci.draw_rect(box.grow(_px(2.6)), Color(COL_CINNABAR, 0.85 * alpha), false, _px(1.0))
		if seen and not is_here:
			ci.draw_circle(v, _px(1.3), Color(COL_CINNABAR, alpha))
		if is_here:
			ci.draw_arc(v, r + _px(6.0), 0.0, TAU, 40, COL_INK, _px(1.4), true)
			ci.draw_arc(v, r + _px(9.0), 0.0, TAU, 48, Color(COL_INK, 0.45), _px(1.0), true)
		elif is_dest:
			ci.draw_arc(v, r + _px(6.0), 0.0, TAU, 40, COL_GOLD, _px(2.0), true)
		elif hov:
			ci.draw_arc(v, r + _px(5.5), 0.0, TAU, 40, Color(COL_INK, 0.6), _px(1.0), true)
		var tcol := COL_INK if (seen or is_here) else Color(COL_INK, 0.75)
		if is_dest:
			tcol = COL_OCHRE
		tcol.a *= alpha
		if bool(L.get("name_hidden", false)):
			continue
		var size_px: int = L["size_px"]
		var pos: Vector2 = L["pos"]
		_text(ci, pos, str(L["text"]), size_px, tcol)
		if float(L["sub_w"]) > 0.0:
			var sub_px: int = L["sub_px"]
			_text(ci, pos + Vector2(0, _px(sub_px * 1.2)), str(L["sub"]), sub_px, Color(COL_INK_SOFT, 0.9 * alpha))
	_draw_dest_edge_hint(ci)


## 这一帧的港口布局：哪些港要画、方框在哪、名字放哪。港标层与地名层各自 _draw 时都先调它；
## 按状态键判重（帧号不可靠：首帧取景前后会各画一次，帧号相同就会沿用 0.5 缩放时的旧布局）
func _ensure_layout() -> void:
	var key := "%s|%s|%s|%s|%s|%s|%s|%d|%s" % [camera.zoom.x, camera.position, origin_id, dest_id, offered, visited.size(), ship.position if ship else Vector2.ZERO, cal_year, ship_visible]
	if _layout_key == key:
		return
	_layout_key = key
	_port_layout.clear()
	_port_label_texts.clear()
	_port_obstacles.clear()
	var z := camera.zoom.x
	var order := ports.duplicate()
	# 重要的先摆（当前/目的地优先，其次市舶港，然后按纬度自北向南），避让时它们不让位
	order.sort_custom(func(a, b):
		var ia := str(a.get("id", ""))
		var ib := str(b.get("id", ""))
		var pa := _port_rank(ia, a)
		var pb := _port_rank(ib, b)
		if pa != pb:
			return pa > pb
		return float(a.get("lat", 0.0)) > float(b.get("lat", 0.0))
	)
	# 字号：默认取景（z 约 0.6–0.9）下 13 px 只剩 11 px 高，读不清（snowchan27-02 走查），提到 15 起
	var size_px := 16 if z < 0.7 else (17 if z < 1.6 else 19)
	var show_sub := z >= 0.9
	var view := world_visible_rect().grow(300.0)
	# 障碍：船标 + 每个要画的港的框（名字要避开别的港框，兴化 / 兴化海口那种挨着的港才不会读反）
	if ship_visible and ship.visible:
		# Lane U：船标避让放大，港名/航段边标不压船
		var sr := _px(26.0)
		_port_obstacles.append(Rect2(ship.position - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)))
	# 罗盘、题记框、比例尺盖住的那几块：港名、小字地名、出带箭头都让开（lane w53-1）
	var hud_w: Array[Rect2] = []
	for hr: Rect2 in hud_rects:
		hud_w.append(_screen_to_world_rect(hr))
	_port_obstacles.append_array(hud_w)
	var drawn := []
	for p in order:
		var pid := str(p.get("id", ""))
		if not port_px.has(pid):
			continue
		var rank := _port_rank(pid, p)
		# 远景裁标：缩得很远只留市舶港、当前与本手可选的港
		if z < 0.45 and rank < 2:
			continue
		var v: Vector2 = port_px[pid]
		if not view.has_point(v):
			continue
		var r := _px(4.6 if (pid == origin_id or pid == dest_id) else 3.8)
		var box := Rect2(v - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		_port_obstacles.append(box.grow(_px(3.0)))
		drawn.append({"id": pid, "p": p, "v": v, "r": r, "box": box})
	for d in drawn:
		var p: Dictionary = d["p"]
		var pid: String = d["id"]
		var v: Vector2 = d["v"]
		var r: float = d["r"]
		var chart: Dictionary = p.get("chart", {})
		var text := str(chart.get("label", p.get("name", pid)))
		var sub := _port_sub(chart)
		# 港位本身落在 HUD 块底下：名字摆哪一侧都有半截钻进去（罗盘下露出「海道北口」），不写名字，港框照画
		if _rect_hits_point(hud_w, v):
			_port_label_texts[text] = true
			_port_layout[pid] = {"p": p, "v": v, "r": r, "box": d["box"], "text": text, "sub": sub, "sub_w": 0.0,
				"size_px": size_px, "sub_px": 11, "pos": v, "rect": Rect2(v, Vector2.ZERO), "name_hidden": true}
			continue
		var tw := _text_width_world(text, size_px)
		var th := _px(size_px * 1.15)
		var sub_px := 11
		var sub_w := _text_width_world(sub, sub_px) if (show_sub and sub != "") else 0.0
		var block_w := maxf(tw, sub_w)
		var block_h := th + (_px(sub_px * 1.2) if sub_w > 0.0 else 0.0)
		var pad := r + _px(7.0)
		# 右、左、上、下、右上、右下；全撞时取重叠面积最小的那个，不再一律放右边
		var candidates := [
			Vector2(pad, _px(size_px * 0.4)),
			Vector2(-pad - block_w, _px(size_px * 0.4)),
			Vector2(-block_w * 0.5, -pad - block_h + th),
			Vector2(-block_w * 0.5, pad + th),
			Vector2(pad, -pad - block_h + th),
			Vector2(pad, pad + th),
		]
		var best: Vector2 = candidates[0]
		var best_rect := Rect2(v + best - Vector2(0, th * 0.8), Vector2(block_w, block_h))
		var best_cost := INF
		for c in candidates:
			var cv: Vector2 = c
			var rect := Rect2(v + cv - Vector2(0, th * 0.8), Vector2(block_w, block_h))
			var cost := 0.0
			for o in _port_obstacles:
				if o.intersects(rect):
					cost += o.intersection(rect).get_area()
			if cost < best_cost:
				best_cost = cost
				best = cv
				best_rect = rect
			if cost <= 0.0:
				break
		_port_obstacles.append(best_rect)
		_port_label_texts[text] = true
		_port_layout[pid] = {"p": p, "v": v, "r": r, "box": d["box"], "text": text, "sub": sub, "sub_w": sub_w,
			"size_px": size_px, "sub_px": sub_px, "pos": v + best, "rect": best_rect}


## 目的地被顶匾 / 牌区挤到图带外时，在图带边上画朱砂箭头指向它并写名字（远程港对装不下时的指引）
func _draw_dest_edge_hint(ci: CanvasItem) -> void:
	var h := dest_hint_layout()
	if h.is_empty():
		return
	var tri: PackedVector2Array = h["tri"]
	ci.draw_colored_polygon(tri, COL_CINNABAR)
	ci.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(COL_SHELL, 0.9), _px(1.0), true)
	_text(ci, h["text_pos"], str(h["text"]), 14, COL_CINNABAR, HORIZONTAL_ALIGNMENT_CENTER)


## 出带箭头摆在哪（_ensure_layout 之后调）：图带边上朝目的地的那一点。朱箭或名字压到港框 / 港名 / 船标时沿图带边
## 左右挪（每步 14 屏幕 px，至多 8 步），朱箭仍指着目的地；全挪不开取压得最少的。原先只让开船标，放大看海岸时
## 常压在近岸港名上（泉州往占城，「占城」两字叠在漳州港标头上，像是那港的名字）。lane w53-1。返回 {} = 不画
func dest_hint_layout() -> Dictionary:
	if dest_id == "" or not port_px.has(dest_id):
		return {}
	var band := _band_world_rect().grow(-_px(20.0))
	if band.size.x <= 0.0 or band.size.y <= 0.0:
		return {}
	var d: Vector2 = port_px[dest_id]
	# 图带下沿之下还有一条航法钮的缝（约 50 px）能露出港标，落在缝里的不算出带
	if band.grow_individual(0.0, 0.0, 0.0, _px(52.0)).has_point(d):
		return {}
	# 目的港的港框（连金圈）与港名整个露在图带里（贴着顶匾也算）就不出箭头：再写一个朱字港名是重名，还会与港名本身相撞——
	# 原先离图带边 20 px 内就出，306 个出箭头的镜头里 6 处目的港框与港名其实全在带里（lane w53-1）
	if _dest_in_view():
		return {}
	var c := band.get_center()
	var dir := (d - c).normalized()
	if dir.length() < 0.5:
		return {}
	var half := band.size * 0.5
	var tx := INF if absf(dir.x) < 1e-6 else half.x / absf(dir.x)
	var ty := INF if absf(dir.y) < 1e-6 else half.y / absf(dir.y)
	var e0 := c + dir * minf(tx, ty)
	# 落在上下沿就横着挪，落在左右沿就竖着挪
	var along := Vector2(1.0, 0.0) if ty <= tx else Vector2(0.0, 1.0)
	var chart: Dictionary = _port_def(dest_id).get("chart", {})
	var text := str(chart.get("label", dest_id))
	var best := {}
	var best_cost := INF
	for k: int in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8]:
		var e := e0 + along * _px(14.0) * k
		e = Vector2(clampf(e.x, band.position.x, band.end.x), clampf(e.y, band.position.y, band.end.y))
		var h := _dest_hint_at(e, d, text)
		var cost := 0.0
		for o: Rect2 in _port_obstacles:
			for r: Rect2 in [h["tri_rect"], h["label_rect"]]:
				if o.intersects(r):
					cost += o.intersection(r).get_area()
		if cost < best_cost:
			best_cost = cost
			best = h
		if cost <= 0.0:
			break
	return best

## 目的港这一帧画出来了，港框连金圈（半径 + 7 屏幕 px）与港名都整个在图带里（不含航法钮那条缝）
func _dest_in_view() -> bool:
	_ensure_layout()
	if not _port_layout.has(dest_id):
		return false
	var L: Dictionary = _port_layout[dest_id]
	var seen := _band_world_rect()
	var ring := Rect2(L["v"], Vector2.ZERO).grow(float(L["r"]) + _px(7.0))
	return seen.encloses(ring) and seen.encloses(L["rect"])


## 朱箭尖在 e、指向 d 时的三角与名字（名字往带内侧偏，再让开船标）
func _dest_hint_at(e: Vector2, d: Vector2, text: String) -> Dictionary:
	var dir := (d - e).normalized()
	var s := _px(9.0)
	var perp := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([e, e - dir * s * 1.7 + perp * s * 0.8, e - dir * s * 1.7 - perp * s * 0.8])
	var tp := e - dir * s * 3.2
	# 名字往带内侧偏，别贴着箭头
	tp += Vector2(0, _px(5.0)) if dir.y < 0.0 else Vector2(0, -_px(4.0))
	# Lane U：边沿航段提示再让开船标，避免朱箭/港名压船
	if ship_visible and ship.visible:
		var clear := _px(28.0)
		var delta := tp - ship.position
		if delta.length() < clear and delta.length() > 0.01:
			tp = ship.position + delta.normalized() * clear
	var tw := _text_width_world(text, 14)
	var th := _px(14.0 * 1.15)
	return {
		"tip": e, "tri": tri, "text": text, "text_pos": tp,
		"tri_rect": Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2]),
		"label_rect": Rect2(tp + Vector2(-tw * 0.5, -th * 0.8), Vector2(tw, th)),
	}


func _port_def(pid: String) -> Dictionary:
	for p in ports:
		if str(p.get("id", "")) == pid:
			return p
	return {}


## 是否离这一帧画出来的某个港标很近（地名层用：同地的岛名 / 地区名不重复标；没画出来的港不算，免得两者都不显示）
func _near_drawn_port(world: Vector2, radius: float) -> bool:
	for pid in _port_layout:
		if (_port_layout[pid]["v"] as Vector2).distance_to(world) < radius:
			return true
	return false


func _port_rank(pid: String, p: Dictionary) -> int:
	if pid == origin_id or pid == dest_id:
		return 3
	if bool(p.get("chart", {}).get("shibo", false)) or (not offered.is_empty() and pid in offered):
		return 2
	return 1


## 港口小字：chart.sub，若 sub_by_year 里有已到年份的条目就换掉（取 from 最大的那条）
func _port_sub(chart: Dictionary) -> String:
	var sub := str(chart.get("sub", ""))
	var best_from := -99999
	for e in chart.get("sub_by_year", []):
		var from := int(e.get("from", 0))
		if cal_year >= from and from > best_from:
			best_from = from
			sub = str(e.get("sub", sub))
	return sub


## 这一帧要画哪些地名、各落在哪（_ensure_layout 之后调；_draw_labels 照它画，探针照它验）：
## 小字地名（岛 / 岬 / 水门 / 山 / 河 / 注）避开港框、港名、船标、HUD 块（罗盘 / 题记框 / 比例尺）与先摆下的地名，撞了就不画；
## 地区名（日本 / 筑前 / 交趾……）避开港框、港名、HUD 块与先摆下的地名，原处撞了往下、往上各挪一行，都撞就不画——
## 原先地区名不避让：选向框福州—博多（缩放 0.28）时「日本」两字压在「博多」港名上，读成「博多本」；
## 放大到 2.6 看博多，「筑前」压港名。地区名不避船标：船从旁驶过时字不跳。海名照旧不避（画在开阔海面）。lane w53-1
## 返回 [{lb, kind, text, pos}]：pos 是画字的锚点（与原先的经纬落点相同，地区名挪过一行的除外）
func label_layout() -> Array:
	_ensure_layout()
	var z := camera.zoom.x
	var view := world_visible_rect().grow(200.0)
	var placed_small: Array[Rect2] = []
	var marks: Array[Rect2] = []
	for pid: String in _port_layout.keys():
		var L: Dictionary = _port_layout[pid]
		marks.append((L["box"] as Rect2).grow(_px(3.0)))
		marks.append(L["rect"])
	for hr: Rect2 in hud_rects:
		marks.append(_screen_to_world_rect(hr))
	var out: Array = []
	for lb in labels:
		var tier := str(lb.get("tier", "mid"))
		if lb.has("zoom_min") or lb.has("zoom_max"):
			if z < float(lb.get("zoom_min", 0.0)) or z > float(lb.get("zoom_max", 99.0)):
				continue
		elif not _tier_visible(tier, z):
			continue
		var v: Vector2 = proj.to_px(float(lb.get("lon", 0.0)), float(lb.get("lat", 0.0)))
		if not view.has_point(v):
			continue
		var kind := str(lb.get("kind", "sea"))
		var text := str(lb.get("text", ""))
		# 与画出来的港同名（耽羅之于耽罗港、彭湖之于澎湖港）或同地的岛名 / 地区名 / 山名不重复标，免得叠字
		if kind in ["island", "region", "cape", "mountain", "note"]:
			if _port_label_texts.has(text):
				continue
			if _near_drawn_port(v, _px(30.0 if kind != "mountain" else 20.0)):
				continue
		var small := kind in ["island", "cape", "strait", "mountain", "river", "note"] or not (kind in ["sea", "region"])
		var pos := v
		if small:
			var sz_s := int(lb.get("size", 12))
			var w_s := _text_width_world(text, sz_s)
			var th_s := _px(sz_s * 1.15)
			var off_y := _px(sz_s + 4) if kind == "mountain" else 0.0
			var rect := Rect2(v + Vector2(-w_s * 0.5, off_y - th_s * 0.8), Vector2(w_s, th_s))
			if _rect_hits(rect, _port_obstacles) or _rect_hits(rect, placed_small):
				continue
			placed_small.append(rect)
		elif kind == "region":
			var rect_r := _region_label_rect(v, text, int(lb.get("size", 16)))
			var placed := false
			for dy: float in [0.0, rect_r.size.y * 1.1, -rect_r.size.y * 1.1]:
				var r := Rect2(rect_r.position + Vector2(0.0, dy), rect_r.size)
				if not _rect_hits(r, marks) and not _rect_hits(r, placed_small):
					pos = v + Vector2(0.0, dy)
					placed_small.append(r)
					placed = true
					break
			if not placed:
				continue
		out.append({"lb": lb, "kind": kind, "text": text, "pos": pos})
	return out


## 地区名（仿宋，字号比数据大 1）以 v 为基线中点画出时的外框
func _region_label_rect(v: Vector2, text: String, data_size: int) -> Rect2:
	var sz := data_size + 1
	var w := _text_width_world(text, sz, font_title)
	var th := _px(sz * 1.15)
	return Rect2(v + Vector2(-w * 0.5, -th * 0.8), Vector2(w, th))


## 海名 / 国名 / 岛名 / 山川 / 险地：按 kind 与层级（tier）显隐，画哪些、落在哪照 label_layout。
## 小地名（岛、岬、河、山、族群）与险地名要避开港框、港名、船标（同一帧的港口布局），撞了就不画。
func _draw_labels(ci: CanvasItem) -> void:
	var z := camera.zoom.x
	var view := world_visible_rect().grow(200.0)
	for item: Dictionary in label_layout():
		var lb: Dictionary = item["lb"]
		var kind: String = item["kind"]
		var text: String = item["text"]
		var v: Vector2 = item["pos"]
		match kind:
			"sea":
				# 仿宋笔画细，比文楷多给 2 px、多给一点墨
				var sz := int(lb.get("size", 22)) + 2
				_text_vertical(ci, v, text, sz, Color(COL_AZURITE_DEEP, 0.64), 1.30, font_title)
			"region":
				# 赭石压在赭石陆上对比只有 1.5:1（走查实测），加深
				_text(ci, v, text, int(lb.get("size", 16)) + 1, Color(COL_OCHRE.darkened(0.32), 0.88), HORIZONTAL_ALIGNMENT_CENTER, true, font_title)
			"island", "cape", "strait":
				_text(ci, v, text, int(lb.get("size", 12)), Color(COL_INK, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
			"mountain":
				if mode < 0.35 and bool(lb.get("chart_hide", false)):
					continue
				var sz2 := int(lb.get("size", 11))
				# 山形符号：《地理图》写景法三峰
				var s := _px(5.0)
				var mc := Color(COL_OCHRE.darkened(0.2), 0.6 + 0.3 * mode)
				ci.draw_polyline(PackedVector2Array([v + Vector2(-s * 2.0, 0), v + Vector2(-s, -s * 1.3), v + Vector2(0, 0), v + Vector2(s, -s * 1.9), v + Vector2(s * 2.0, 0)]), mc, _px(1.2), true)
				_text(ci, v + Vector2(0, _px(sz2 + 4)), text, sz2, Color(COL_OCHRE.darkened(0.3), 0.8 + 0.2 * mode), HORIZONTAL_ALIGNMENT_CENTER)
			"river":
				_text(ci, v, text, int(lb.get("size", 11)), Color(COL_AZURITE_DEEP, 0.74 + 0.2 * mode), HORIZONTAL_ALIGNMENT_CENTER)
			_:
				_text(ci, v, text, int(lb.get("size", 12)), Color(COL_INK, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	# 险地：朱砂三叠浪 + 名（13 px，11 px 在纹理上读不清）
	for hz in hazards:
		if not _tier_visible(str(hz.get("tier", "mid")), z):
			continue
		var v: Vector2 = proj.to_px(float(hz.get("lon", 0.0)), float(hz.get("lat", 0.0)))
		if not view.has_point(v):
			continue
		var htext := str(hz.get("text", ""))
		var hw := _text_width_world(htext, 13)
		var hrect := Rect2(v + Vector2(-hw * 0.5, _px(16.0) - _px(13.0 * 0.8)), Vector2(hw, _px(13.0 * 1.15)))
		if _rect_hits(hrect, _port_obstacles):
			continue
		var s := _px(4.0)
		var hc := Color(COL_CINNABAR, 0.9)
		for k in range(3):
			var o := v + Vector2((k - 1) * s * 2.2, 0)
			ci.draw_polyline(PackedVector2Array([o + Vector2(-s, s * 0.5), o + Vector2(0, -s * 0.6), o + Vector2(s, s * 0.5)]), hc, _px(1.3), true)
		_text(ci, v + Vector2(0, _px(16)), htext, 13, hc, HORIZONTAL_ALIGNMENT_CENTER)


static func _rect_hits_point(rects: Array[Rect2], p: Vector2) -> bool:
	for o in rects:
		if o.has_point(p):
			return true
	return false


static func _rect_hits(r: Rect2, rects: Array) -> bool:
	for o in rects:
		if (o as Rect2).intersects(r):
			return true
	return false
