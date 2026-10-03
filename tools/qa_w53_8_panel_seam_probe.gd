extends SceneTree
## lane w53-8：靛墨面板（UiTheme.panel()）九宫的纵向接缝——800×600 / 4:3 / 5:4 / 竖屏这类高画布下，
## 剧情页、设施页、见面页的大面板中腰不再冒出泥金「田」字块，左右框沿中段也不再多出「⊐」形碎钩。
## 证：
##   1. 纯算（headless 也跑）：照 Godot 画布着色器九宫取样的式子（map_ninepatch_axis：边距内一比一，
##      中段 TILE_FIT 按「区长 / 贴图中段长」四舍五入铺几片），把 panel() 的贴图铺到六种页面面板尺寸上
##      （16:9 1248×620、16:10 1248×700、4:3 1248×860、5:4 1248×924、9:16 1248×2215、21:9 1674×620），
##      离上下沿 48 px 以外（左右框沿中段 + 面板中腰）落到泥金包角钩上的像素数 = 0；
##      四角包角钩仍在（左上角 48×48 内有泥金）；16:9 下上沿一排泥金的横向位置（左右两片贴图接缝处的腰花）
##      与原先九宫边距 20 时逐列相同——1280×720 的样子不变。
##   2. 有窗口时再实画一遍：1280×960 画布里摆一块 1248×860 的 panel() 面板，截图量同一条带的泥金像素 = 0、
##      左上角仍有泥金。
## 旧病（回退即红）：panel_ink 贴图 592 px，包角泥金钩占 15–38 px，九宫四边都只切 20 px，钩的下半截落进
## 左右框沿与中心区；面板高过约 860 px 时纵向 TILE_FIT 铺成两片以上，片与片相接处四个碎角拼成面板正中的
## 「田」字泥金块、左右框沿中段各一个「⊐」（4:3 下 1248×860 的页面面板中腰实测 256 px 泥金、竖屏一列七八个）。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_w53_8_panel_seam_probe.gd
##（headless 也能跑：只做纯算，不实画）

const CORNER := 48            # 包角区：离面板四角这么远以内的泥金算包角钩本身
const SIZES := [
	["16:9", Vector2(1248, 620)],
	["16:10", Vector2(1248, 700)],
	["4:3", Vector2(1248, 860)],
	["5:4", Vector2(1248, 924)],
	["9:16", Vector2(1248, 2215)],
	["21:9", Vector2(1674, 620)],
]
const ORIGINAL_MARGIN := 20.0  # 修前四边的九宫边距：16:9 上沿腰花的位置以它为准

var _fails: Array = []
var _gold := PackedByteArray()
var _tw := 0
var _th := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK %s" % what)
	else:
		_fails.append(what)
		print("FAIL %s" % what)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


static func _is_gold(c: Color) -> bool:
	return c.a > 0.23 and c.r > 0.47 and c.g > 0.35 and c.b < 0.43 and c.r - c.b > 0.19


## 着色器 map_ninepatch_axis 的同一式：p 是画出来的第几个像素（取像素中心），d 画长，t 贴图长，mb / me 两头边距
static func _texel(p: float, d: float, t: float, mb: float, me: float, mode: int) -> int:
	var tx: float
	if p < mb:
		tx = p
	elif p >= d - me:
		tx = t - (d - p)
	else:
		var src := d - mb - me
		var dst := t - mb - me
		if mode == StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH:
			tx = mb + (p - mb) / src * dst
		elif mode == StyleBoxTexture.AXIS_STRETCH_MODE_TILE:
			tx = mb + fmod(p - mb, dst)
		else:
			var scale := maxf(1.0, floor(src / maxf(dst, 0.0000001) + 0.5))
			tx = mb + fmod((p - mb) / src * scale, 1.0) * dst
	return clampi(int(tx), 0, int(t) - 1)


static func _axis(d: int, t: int, mb: float, me: float, mode: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(d)
	for i in d:
		out[i] = _texel(float(i) + 0.5, float(d), float(t), mb, me, mode)
	return out


## 按给定九宫边距把贴图铺到 size（含 expand 外扩）上，返回 [中腰带泥金像素数, 左上角泥金像素数, 上沿带有泥金的列号集合]
func _lay(sb: StyleBoxTexture, size: Vector2, ml: float, mt: float, mr: float, mbot: float) -> Array:
	var dw := int(size.x + sb.expand_margin_left + sb.expand_margin_right)
	var dh := int(size.y + sb.expand_margin_top + sb.expand_margin_bottom)
	var mx := _axis(dw, _tw, ml, mr, sb.axis_stretch_horizontal)
	var my := _axis(dh, _th, mt, mbot, sb.axis_stretch_vertical)
	var band := 0
	var corner := 0
	var top_cols := {}
	for y in dh:
		var row := my[y] * _tw
		var in_band := y >= CORNER and y < dh - CORNER
		for x in dw:
			if _gold[row + mx[x]] == 0:
				continue
			if in_band:
				band += 1
			elif y < CORNER:
				top_cols[x] = true
				if x < CORNER:
					corner += 1
	return [band, corner, top_cols]


func _render_check() -> void:
	root.size = Vector2i(1280, 960)
	await _frames(4)
	var host := Control.new()
	host.size = Vector2(1280, 960)
	root.add_child(host)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.panel())
	host.add_child(pc)
	pc.position = Vector2(16, 84)
	pc.size = Vector2(1248, 860)
	await _frames(6)
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		_check(false, "实画：取不到截图")
		return
	var sb := UiTheme.panel() as StyleBoxTexture
	var r := Rect2(pc.position, pc.size).grow_individual(
		sb.get_expand_margin(SIDE_LEFT), sb.get_expand_margin(SIDE_TOP),
		sb.get_expand_margin(SIDE_RIGHT), sb.get_expand_margin(SIDE_BOTTOM))
	var band := 0
	var corner := 0
	for y in range(int(r.position.y), int(r.end.y)):
		var in_band := y >= int(r.position.y) + CORNER and y < int(r.end.y) - CORNER
		for x in range(int(r.position.x), int(r.end.x)):
			if not _is_gold(img.get_pixel(x, y)):
				continue
			if in_band:
				band += 1
			elif y < int(r.position.y) + CORNER and x < int(r.position.x) + CORNER:
				corner += 1
	_check(band == 0, "实画 1280×960 画布上 1248×860 的 panel() 面板：离上下沿 48 px 以外（中腰 + 左右框沿中段）泥金像素 0（得 %d）" % band)
	_check(corner > 0, "实画：左上角包角钩仍在（泥金像素 %d）" % corner)
	host.queue_free()


func _run() -> void:
	var sb0 := UiTheme.panel()
	if not (sb0 is StyleBoxTexture):
		_check(false, "UiTheme.panel() 应是九宫贴图（绢本），得 %s" % sb0.get_class())
		_finish()
		return
	var sb := sb0 as StyleBoxTexture
	var img: Image = sb.texture.get_image() if sb.texture != null else null
	if img == null or img.is_empty():
		_check(false, "panel() 的贴图取不到像素")
		_finish()
		return
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	_tw = img.get_width()
	_th = img.get_height()
	_gold.resize(_tw * _th)
	var n_gold := 0
	for y in _th:
		for x in _tw:
			var g := 1 if _is_gold(img.get_pixel(x, y)) else 0
			_gold[y * _tw + x] = g
			n_gold += g
	_check(n_gold > 0, "panel() 贴图上认得出泥金包角钩（%d 像素，%d×%d）" % [n_gold, _tw, _th])
	var ml := sb.texture_margin_left
	var mt := sb.texture_margin_top
	var mr := sb.texture_margin_right
	var mbot := sb.texture_margin_bottom
	print("panel(): 边距 左%d 上%d 右%d 下%d　纵向铺法 %d　横向铺法 %d" % [ml, mt, mr, mbot, sb.axis_stretch_vertical, sb.axis_stretch_horizontal])
	for e in SIZES:
		var tag: String = e[0]
		var size: Vector2 = e[1]
		var got := _lay(sb, size, ml, mt, mr, mbot)
		_check(int(got[0]) == 0, "%s 页面面板 %d×%d：离上下沿 48 px 以外泥金像素 0（得 %d——纵向贴图接缝冒出的碎钩）" % [tag, size.x, size.y, got[0]])
		_check(int(got[1]) > 0, "%s 页面面板：左上角包角钩仍在（泥金像素 %d）" % [tag, got[1]])
	# 16:9 上沿一排泥金（左右两片贴图接缝处的腰花）与原先边距 20 时同列：1280×720 的样子不变
	var now := _lay(sb, SIZES[0][1], ml, mt, mr, mbot)
	var was := _lay(sb, SIZES[0][1], ORIGINAL_MARGIN, ORIGINAL_MARGIN, ORIGINAL_MARGIN, ORIGINAL_MARGIN)
	var now_cols: Array = (now[2] as Dictionary).keys()
	var was_cols: Array = (was[2] as Dictionary).keys()
	now_cols.sort()
	was_cols.sort()
	_check(now_cols == was_cols and not now_cols.is_empty(),
		"16:9 页面面板上沿泥金所在列与原先（边距 20）相同：现 %d 列 / 原 %d 列" % [now_cols.size(), was_cols.size()])
	if DisplayServer.get_name() != "headless":
		await _render_check()
	_finish()


func _finish() -> void:
	print("QA_W53_8_PANEL_SEAM_PROBE %s（%d 项不合）" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	quit(0 if _fails.is_empty() else 1)
