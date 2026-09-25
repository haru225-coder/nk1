## 朱印控件（过场字幕 style=seal、章节卡、抵港横幅共用）。
## 印面来源按优先级：
##   1. UI 线成品印（assets/ui/nk1/seal_<名>_{bai,zhu}.png）——印文相同时直接用，全游戏同一方「立志」印；
##   2. 程序生成：SubViewport 里按 2 倍分辨率画一次印面蒙版（字形按实际包围盒撑满格子、描边加粗成刻刀笔画），
##      再由 cs_seal.gdshader 着色——崩边与缺角按屏幕像素生成，印泥浓淡取 UI 线的空白印底 seal_blank.png
##      （缺图时程序噪声兜底），与 UI 线的印同一种质感。
## 时间协议与 cs_ink_text 相同：advance(dt) / finish_reveal() / fade_out(d) / is_gone()。
## 盖印：自 1.75 倍落下 → 触纸（发 impacted）→ 回弹 → 印泥洇开一圈淡红。
extends Control

signal impacted

const Kit := preload("res://scripts/cutscene/cs_kit.gd")

enum Style { BAIWEN, ZHUWEN }

const FALL := 0.16
const SETTLE := 0.26
const SPREAD := 0.8
## 印面留边（占单格边长）
const PAD := 0.1
## 字形（含加粗描边）撑满格子的比例
const GLYPH_FILL := 0.95
## 加粗描边宽度（占字号）：笔画要粗到像刻出来的
const STROKE := 0.12
## 长宽比不合时另一向的最大拉伸
const MAX_STRETCH := 1.25
## UI 线已交付的成品印：[白文, 朱文]
const UI_SEALS := {
	"立志": ["res://assets/ui/nk1/seal_lizhi_bai.png", "res://assets/ui/nk1/seal_lizhi_zhu.png"],
	"海商": ["res://assets/ui/nk1/seal_haishang_bai.png", "res://assets/ui/nk1/seal_haishang_zhu.png"],
	"东亚海域": ["res://assets/ui/nk1/seal_dongya_bai.png", "res://assets/ui/nk1/seal_dongya_zhu.png"],
	"兴化陈氏": ["res://assets/ui/nk1/seal_xinghua_bai.png", "res://assets/ui/nk1/seal_xinghua_zhu.png"],
}
const UI_SEAL_BLANK := "res://assets/ui/nk1/seal_blank.png"


## 印面蒙版：只负责画。每个字的字体、字号、拉伸、笔位由外层按字形包围盒算好传进来（glyphs）。
class SealFace:
	extends Control
	var glyphs: Array = []
	var style := 0
	var border_px := 6.0

	func _draw() -> void:
		var fg := Color.BLACK if style == 0 else Color.WHITE
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE if style == 0 else Color.BLACK)
		if style == 1:
			var inset := border_px * 0.5 + size.x * 0.028
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color.WHITE, false, border_px)
		var ci := get_canvas_item()
		for g: Dictionary in glyphs:
			var f: Font = g["font"]
			var px: int = g["px"]
			var cp: int = g["cp"]
			draw_set_transform(g["center"], 0.0, g["scale"])
			f.draw_char_outline(ci, g["pen"], cp, px, g["stroke"], fg)
			f.draw_char(ci, g["pen"], cp, px, fg)
		draw_set_transform_matrix(Transform2D.IDENTITY)


var seal_text := "立志"
var cell := 40.0
var style := Style.BAIWEN
var hollow_alpha := 0.0
var ink := Color(0.69, 0.188, 0.165)
var tilt := -0.045

var _vp: SubViewport
var _rect: TextureRect
var _mat: ShaderMaterial
var _halo: TextureRect
var _seal_size := Vector2.ZERO
var _t := 0.0
var _hit := false
var _out_start := -1.0
var _out_dur := 0.5
var _textured := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 字形包围盒（字号 px 下，相对笔位：x 向右、y 向下，基线 y=0）。取不到返回空 Rect2。
static func glyph_box(f: Font, cp: int, px: int) -> Rect2:
	if f == null:
		return Rect2()
	var ts := TextServerManager.get_primary_interface()
	for rid: RID in f.get_rids():
		var gi := ts.font_get_glyph_index(rid, px, cp, 0)
		if gi == 0:
			continue
		var c: Dictionary = ts.font_get_glyph_contours(rid, px, gi)
		var pts: PackedVector3Array = c.get("points", PackedVector3Array())
		if pts.is_empty():
			continue
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in pts:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		return Rect2(mn, mx - mn)
	return Rect2()


## 该印文 / 样式有没有 UI 线成品印（有则返回贴图路径）
static func ui_seal_path(txt: String, zhuwen: bool) -> String:
	if not UI_SEALS.has(txt):
		return ""
	var path: String = (UI_SEALS[txt] as Array)[1 if zhuwen else 0]
	return path if ResourceLoader.exists(path) else ""


static func _font_has(f: Font, cp: int) -> bool:
	if f is FontVariation:
		var b := (f as FontVariation).base_font
		return b != null and b.has_char(cp)
	return f != null and f.has_char(cp)


## 一个印文字的排法：按字形实际包围盒撑满格子（含加粗描边），长宽比差得多时另一向至多拉伸 MAX_STRETCH 倍——印文本就是「填满」的。
## 马善政缺字时用文楷。
func _fit_glyph(cp: int, r: Rect2) -> Dictionary:
	var f: Font = Kit.title_font()
	if not _font_has(f, cp):
		f = Kit.body_font()
	var probe := 100
	var bb := glyph_box(f, cp, probe)
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		bb = Rect2(Vector2(8.0, -84.0), Vector2(84.0, 90.0))
	var target := r.size * GLYPH_FILL
	var rw := bb.size.x / float(probe) + STROKE
	var rh := bb.size.y / float(probe) + STROKE
	var fs := minf(target.x / rw, target.y / rh)
	var sx := clampf(target.x / (rw * fs), 1.0, MAX_STRETCH)
	var sy := clampf(target.y / (rh * fs), 1.0, MAX_STRETCH)
	var px := maxi(int(fs), 4)
	var k := float(px) / float(probe)
	return {"font": f, "cp": cp, "px": px, "stroke": maxi(int(float(px) * STROKE), 2),
		"center": r.get_center(), "scale": Vector2(sx, sy), "pen": -(bb.position + bb.size * 0.5) * k}


## opts: cell(float) style("baiwen"/"zhuwen") hollow_alpha(float) tilt(弧度) seed(float) procedural(bool，强制程序生成)
func configure(p_text: String, opts: Dictionary) -> void:
	seal_text = p_text.strip_edges().replace(" ", "")
	if seal_text == "":
		seal_text = "印"
	if seal_text.length() > 4:
		push_warning("朱印最多四字，截断：%s" % seal_text)
		seal_text = seal_text.substr(0, 4)
	cell = float(opts.get("cell", 40.0))
	style = Style.ZHUWEN if str(opts.get("style", "baiwen")) == "zhuwen" else Style.BAIWEN
	hollow_alpha = float(opts.get("hollow_alpha", 0.0))
	tilt = float(opts.get("tilt", -0.045))
	var n := seal_text.length()
	var pad := cell * PAD
	var grid := Vector2i(1, n) if n <= 3 else Vector2i(2, 2)
	_seal_size = (Vector2(cell * grid.x, cell * grid.y) + Vector2(pad, pad) * 2.0).round()
	var seed_v := float(opts.get("seed", 0.0))
	var ui_path := "" if bool(opts.get("procedural", false)) else ui_seal_path(seal_text, style == Style.ZHUWEN)
	var tex: Texture2D = Kit.load_texture(ui_path) if ui_path != "" else null
	if tex != null:
		# 成品印按原图比例，宽度对齐程序印
		var ts := tex.get_size()
		_seal_size = Vector2(_seal_size.x, roundf(_seal_size.x * ts.y / maxf(ts.x, 1.0)))
		if grid.x == 2:
			_seal_size = Vector2(_seal_size.x, _seal_size.x)
	custom_minimum_size = _seal_size
	size = _seal_size
	pivot_offset = _seal_size * 0.5
	_build_halo()
	if tex != null:
		_build_textured(tex)
	else:
		_build(grid, pad, seed_v)
	rotation = tilt
	_apply()


func block_size() -> Vector2:
	return _seal_size


## 是否用的是 UI 线成品印
func is_textured() -> bool:
	return _textured


func _build_halo() -> void:
	_halo = TextureRect.new()
	_halo.texture = Kit.fx_texture("soft_dot.png")
	_halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_halo.stretch_mode = TextureRect.STRETCH_SCALE
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.size = _seal_size * 1.9
	_halo.position = (_seal_size - _halo.size) * 0.5
	_halo.pivot_offset = _halo.size * 0.5
	_halo.modulate = Color(ink, 0.0)
	add_child(_halo)


func _build_textured(tex: Texture2D) -> void:
	_textured = true
	_rect = TextureRect.new()
	_rect.texture = tex
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 成品印比显示尺寸大 2–4 倍：走 mipmap 缩小，崩边不闪
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rect.size = _seal_size
	add_child(_rect)


func _build(grid: Vector2i, pad: float, seed_v: float) -> void:
	var k := 2.0
	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.size = Vector2i(ceili(_seal_size.x * k), ceili(_seal_size.y * k))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var face := SealFace.new()
	face.size = Vector2(_vp.size)
	face.style = int(style)
	face.border_px = cell * k * 0.085
	# 朱文印的字要让出印框
	var p := (pad + (cell * 0.07 if style == Style.ZHUWEN else 0.0)) * k
	# 格子在留边内均分（四字印两列之间留一线，字不粘连）
	var inner := Vector2(_vp.size) - Vector2(p, p) * 2.0
	var cw := inner.x / float(grid.x)
	var ch := inner.y / float(grid.y)
	var glyphs: Array = []
	for i in range(seal_text.length()):
		var col := 0
		var row := i
		if grid.x == 2:
			# 四字印：右列先读，自上而下
			col = 1 - floori(i / 2.0)
			row = i % 2
		var r := Rect2(Vector2(p + cw * col, p + ch * row), Vector2(cw, ch)).grow(-cell * k * 0.01)
		glyphs.append(_fit_glyph(seal_text.unicode_at(i), r))
	face.glyphs = glyphs
	_vp.add_child(face)

	_rect = TextureRect.new()
	_rect.texture = _vp.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.size = _seal_size
	_mat = Kit.material("cs_seal.gdshader")
	if _mat != null:
		_mat.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
		_mat.set_shader_parameter("ink", ink)
		_mat.set_shader_parameter("hollow_color", Kit.C_XUAN)
		_mat.set_shader_parameter("hollow_alpha", hollow_alpha)
		_mat.set_shader_parameter("seed", seed_v)
		_mat.set_shader_parameter("seal_px", _seal_size)
		_mat.set_shader_parameter("density", 0.0)
		_set_blank(seed_v)
		_rect.material = _mat
	add_child(_rect)


## 印泥浓淡取 UI 线空白印底的内部（避开它自己的边），1 张图纹 ≈ 1 个 2× 印面像素；按 seed 选窗口与翻转，几方印不雷同
func _set_blank(seed_v: float) -> void:
	var blank: Texture2D = Kit.load_texture(UI_SEAL_BLANK) if ResourceLoader.exists(UI_SEAL_BLANK) else null
	_mat.set_shader_parameter("has_blank", blank != null)
	if blank == null:
		return
	_mat.set_shader_parameter("blank_tex", blank)
	var bs := blank.get_size()
	var face := _seal_size * 2.0
	var sc := minf(1.0, 0.9 * minf(bs.x, bs.y) / maxf(face.x, face.y))
	var win := face * sc / bs
	var room := Vector2(0.9, 0.9) - win
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_v * 100003.0) + 17
	var pos := Vector2(0.05, 0.05) + Vector2(rng.randf() * maxf(room.x, 0.0), rng.randf() * maxf(room.y, 0.0))
	var sz := win
	if rng.randf() < 0.5:
		pos.x += win.x
		sz.x = -win.x
	if rng.randf() < 0.5:
		pos.y += win.y
		sz.y = -win.y
	_mat.set_shader_parameter("blank_win", Vector4(pos.x, pos.y, sz.x, sz.y))


# ── 时间协议 ───────────────────────────────────────────
func advance(dt: float) -> void:
	_t += dt
	_apply()


func reveal_duration() -> float:
	return FALL + SETTLE


func is_revealed() -> bool:
	return _t >= FALL + SETTLE


func finish_reveal() -> void:
	if _t < FALL + SETTLE:
		_t = FALL + SETTLE
		_apply()


func fade_out(duration: float) -> void:
	if _out_start >= 0.0:
		return
	_out_start = _t
	_out_dur = maxf(duration, 0.01)


func is_fading() -> bool:
	return _out_start >= 0.0


func is_gone() -> bool:
	return _out_start >= 0.0 and _t >= _out_start + _out_dur


func _apply() -> void:
	var sc := 1.0
	var a := 1.0
	var dens := 1.0
	if _t < FALL:
		var p := _t / FALL
		sc = lerpf(1.75, 1.0, p * p)
		a = clampf(p * 2.2, 0.0, 1.0)
		dens = 0.7
	else:
		if not _hit:
			_hit = true
			impacted.emit()
		var q := clampf((_t - FALL) / SETTLE, 0.0, 1.0)
		# 触纸瞬间压扁到 0.93，再阻尼回弹到 1
		sc = 1.0 - 0.07 * exp(-q * 5.0) * cos(q * 9.0)
		dens = lerpf(0.72, 1.0, Kit.ease_out_cubic((_t - FALL) / (SETTLE + SPREAD)))
	var out_a := 1.0
	if _out_start >= 0.0:
		out_a = 1.0 - Kit.ease_in_out((_t - _out_start) / _out_dur)
	scale = Vector2(sc, sc)
	modulate.a = a * out_a
	if _mat != null:
		_mat.set_shader_parameter("density", dens)
	elif _rect != null:
		# 成品印：印泥「吃进纸里」用亮度模拟（刚落下时略淡）
		var v := lerpf(1.18, 1.0, clampf((dens - 0.7) / 0.3, 0.0, 1.0))
		_rect.self_modulate = Color(v, v, v, lerpf(0.82, 1.0, clampf((dens - 0.7) / 0.3, 0.0, 1.0)))
	if _halo != null:
		var h := clampf((_t - FALL) / SPREAD, 0.0, 1.0) if _t >= FALL else 0.0
		var ha := 0.0
		if _t >= FALL:
			ha = (1.0 - Kit.ease_out_cubic(h)) * 0.3
		_halo.modulate = Color(ink, ha * out_a)
		var hs := 0.75 + 0.55 * Kit.ease_out_cubic(h)
		_halo.scale = Vector2(hs, hs)
