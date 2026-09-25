## 逐字浮现的中文字幕控件（过场 / 章节卡 / 抵港横幅共用）。
## 横排或竖排；避头尾；竖排时括号破折号转 90°、句读挪到右上；
## 浮现有「上浮」「墨晕凝字」两种；浅字压图时加深色晕边，可选字块背后一团柔和墨晕。
## 时间由调用方推进：advance(dt)。
extends Control

const Kit := preload("res://scripts/cutscene/cs_kit.gd")

enum Effect { RISE, BLEED, NONE }

const EM_ASC := 0.88
const NO_LINE_START := "，。、．：；！？」』）》〉】〕…～・"
const NO_LINE_END := "「『（《〈【〔"
const PHRASE_END := "，。；！？、："
const V_ROTATE := "「」『』（）《》〈〉【】〔〕—…～：；-–()[]<>"
const V_CORNER := "，。、．"
## 竖排句读挪到右上所需的字形包围盒中心（em/1000，y 向上，基线为 0）。用 fontTools 实测。
const CORNER_BOX := {
	"body": {"，": Vector2(166, -1), "。": Vector2(214, 50), "、": Vector2(180, 40), "．": Vector2(214, 50)},
	"title": {"，": Vector2(500, 101), "。": Vector2(250, 143), "、": Vector2(211, 115), "．": Vector2(250, 143)},
}

var text := ""
var font: Font
var font_kind := "body"
var font_size := 24
var color := Color(0.914, 0.863, 0.753)
var vertical := false
var max_extent := 0.0
var spacing := 0.0
var line_gap := 0.55
var align := 0
var halo := 0.0
var halo_color := Color(0.051, 0.043, 0.035)
var backing := 0.0
var effect := Effect.RISE
var interval := 0.05
var fade := 0.4

var _glyphs: Array = []
var _block := Vector2.ZERO
var _t := 0.0
var _out_start := -1.0
var _out_dur := 0.5
var _backing_tex: Texture2D
var _warm := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## opts: font_kind("title"/"body") size spacing gap color vertical max_extent align halo backing effect interval fade
func configure(p_text: String, opts: Dictionary) -> void:
	text = p_text
	font_kind = str(opts.get("font_kind", "body"))
	font = Kit.title_font() if font_kind == "title" else Kit.body_font()
	font_size = int(opts.get("size", 24))
	color = opts.get("color", color)
	vertical = bool(opts.get("vertical", false))
	max_extent = float(opts.get("max_extent", 0.0))
	spacing = float(opts.get("spacing", 0.0))
	line_gap = float(opts.get("gap", 0.55))
	align = int(opts.get("align", 0))
	halo = float(opts.get("halo", 0.0))
	halo_color = opts.get("halo_color", halo_color)
	backing = float(opts.get("backing", 0.0))
	effect = int(opts.get("effect", Effect.RISE)) as Effect
	interval = float(opts.get("interval", 0.05))
	fade = maxf(float(opts.get("fade", 0.4)), 0.01)
	if backing > 0.0:
		_backing_tex = Kit.fx_texture("soft_dot.png")
	_layout()


func block_size() -> Vector2:
	return _block


func glyph_count() -> int:
	return _glyphs.size()


# ── 时间协议（与 cs_seal 一致）─────────────────────────────
func advance(dt: float) -> void:
	_t += dt
	queue_redraw()


func reveal_duration() -> float:
	return maxf(0.0, float(_glyphs.size() - 1)) * interval + fade


func is_revealed() -> bool:
	return _t >= reveal_duration()


func finish_reveal() -> void:
	_t = maxf(_t, reveal_duration())
	queue_redraw()


func fade_out(duration: float) -> void:
	if _out_start >= 0.0:
		return
	_out_start = _t
	_out_dur = maxf(duration, 0.01)


func is_fading() -> bool:
	return _out_start >= 0.0


func is_gone() -> bool:
	return _out_start >= 0.0 and _t >= _out_start + _out_dur


## 预热：下一次绘制把全部字形（含晕边与凝字描边）以近乎透明（α 0.004）画一遍，随后自行隐藏。
## 字形光栅化发生在 draw 时，大字号带描边的单字要几毫秒——让它落在调用方挑的时机（画面全黑时）。
## 只对还没开始浮现的字调用（调用方负责）。
func prewarm() -> void:
	_warm = true
	visible = true
	queue_redraw()


func _draw_warm() -> void:
	var ci := get_canvas_item()
	var fs := float(font_size)
	var faint := Color(color, 0.004)
	for g in _glyphs:
		var cp: int = g["cp"]
		var pos := Vector2(float(g["x"]), float(g["y"]) + fs * EM_ASC)
		if halo > 0.0:
			font.draw_char_outline(ci, pos, cp, font_size, maxi(int(fs * 0.26), 3), faint)
			font.draw_char_outline(ci, pos, cp, font_size, maxi(int(fs * 0.15), 2), faint)
			font.draw_char_outline(ci, pos, cp, font_size, maxi(int(fs * 0.06), 1), faint)
		if effect == Effect.BLEED:
			font.draw_char_outline(ci, pos, cp, font_size, maxi(int(fs * 0.13), 1), faint)
		font.draw_char(ci, pos, cp, font_size, faint)


# ── 排版 ────────────────────────────────────────────────
func _advance_of(cp: int) -> float:
	if font == null:
		return float(font_size)
	return font.get_char_size(cp, font_size).x


func _wrap(para: String, limit: float, step_of: Callable, phrase := false) -> Array:
	# 返回若干行，每行是字符串数组；limit ≤ 0 不折。
	# phrase：按句读切成短语整句换行（竖排题记「苍官影里三洲路，／涨海声中万国商。」不会孤零零剩一个字）；
	# 单个短语本身超长时退回逐字折行。
	var units: Array = []
	if phrase and limit > 0.0:
		var buf := ""
		for k in range(para.length()):
			buf += para[k]
			if PHRASE_END.contains(para[k]):
				units.append(buf)
				buf = ""
		if buf != "":
			units.append(buf)
	else:
		units = [para]
	var rows: Array = []
	var cur: Array = []
	var used := 0.0
	for u in units:
		var unit := str(u)
		if phrase and limit > 0.0 and not cur.is_empty():
			var uw := 0.0
			for k in range(unit.length()):
				uw += float(step_of.call(unit[k]))
			if used + uw > limit and uw <= limit:
				rows.append(cur)
				cur = []
				used = 0.0
		for k in range(unit.length()):
			var ch := unit[k]
			var step: float = step_of.call(ch)
			if limit > 0.0 and not cur.is_empty() and used + step > limit and not NO_LINE_START.contains(ch):
				var carry: Array = []
				if cur.size() > 1 and NO_LINE_END.contains(str(cur[cur.size() - 1])):
					carry.append(cur.pop_back())
				rows.append(cur)
				cur = carry
				used = 0.0
				for c in carry:
					used += float(step_of.call(c))
			cur.append(ch)
			used += step
	rows.append(cur)
	return rows


func _layout() -> void:
	_glyphs.clear()
	var fs := float(font_size)
	var paragraphs := text.split("\n")
	var idx := 0
	if not vertical:
		var sp := fs * spacing
		var line_h := fs * (1.0 + line_gap)
		var lines: Array = []
		var limit_h := max_extent + sp if max_extent > 0.0 else 0.0
		for para in paragraphs:
			lines.append_array(_wrap(para, limit_h, func(ch: String) -> float: return _advance_of(ch.unicode_at(0)) + sp))
		var widths: Array = []
		var bw := 0.0
		for ln in lines:
			var w := 0.0
			for ch in ln:
				w += _advance_of(str(ch).unicode_at(0)) + sp
			w = maxf(w - sp, 0.0)
			widths.append(w)
			bw = maxf(bw, w)
		for li in range(lines.size()):
			var x := 0.0
			if align == 1:
				x = (bw - float(widths[li])) * 0.5
			elif align == 2:
				x = bw - float(widths[li])
			var top := float(li) * line_h + (line_h - fs) * 0.5
			for ch in lines[li]:
				var cp := str(ch).unicode_at(0)
				var adv := _advance_of(cp)
				_glyphs.append({"cp": cp, "ch": str(ch), "x": x, "y": top, "w": adv, "rot": false, "corner": false, "i": idx})
				idx += 1
				x += adv + sp
		_block = Vector2(bw, float(lines.size()) * line_h)
	else:
		var cell := fs * (1.0 + spacing)
		var col_w := fs * (1.0 + line_gap)
		var cols: Array = []
		var limit_v := max_extent + fs * spacing if max_extent > 0.0 else 0.0
		for para in paragraphs:
			cols.append_array(_wrap(para, limit_v, func(_ch: String) -> float: return cell, true))
		var rows_max := 0
		for c in cols:
			rows_max = maxi(rows_max, c.size())
		var bh := maxf(float(rows_max) * cell - fs * spacing, 0.0)
		var bw := float(cols.size()) * col_w
		for ci in range(cols.size()):
			var xc := bw - (float(ci) + 0.5) * col_w
			var col: Array = cols[ci]
			var y0 := 0.0
			if align == 1:
				y0 = (bh - (float(col.size()) * cell - fs * spacing)) * 0.5
			for ri in range(col.size()):
				var ch := str(col[ri])
				var cp := ch.unicode_at(0)
				var adv := _advance_of(cp)
				var rot := V_ROTATE.contains(ch)
				var corner := V_CORNER.contains(ch)
				var w := fs if (rot or corner) else adv
				_glyphs.append({"cp": cp, "ch": ch, "x": xc - w * 0.5, "y": y0 + float(ri) * cell, "w": w, "adv": adv, "rot": rot, "corner": corner, "i": idx})
				idx += 1
		_block = Vector2(bw, bh)
	custom_minimum_size = _block
	size = _block
	queue_redraw()


# ── 绘制 ────────────────────────────────────────────────
func _draw() -> void:
	if font == null or _glyphs.is_empty():
		return
	if _warm:
		_warm = false
		_draw_warm()
		if _t <= 0.0:
			hide.call_deferred()
			return
	var out_a := 1.0
	if _out_start >= 0.0:
		out_a = 1.0 - Kit.ease_in_out((_t - _out_start) / _out_dur)
	if out_a <= 0.001:
		return
	var ci := get_canvas_item()
	var fs := float(font_size)
	if backing > 0.0 and _backing_tex != null:
		var ba := Kit.ease_in_out(_t / 0.8) * backing * out_a
		var pad := Vector2(fs * 3.2, fs * 2.2)
		draw_texture_rect(_backing_tex, Rect2(-pad, _block + pad * 2.0), false, Color(halo_color, ba))
	var halo_wide := maxi(int(fs * 0.26), 3)
	var halo_mid := maxi(int(fs * 0.15), 2)
	var halo_tight := maxi(int(fs * 0.06), 1)
	var bleed_w := maxi(int(fs * 0.13), 1)
	var corner_tbl: Dictionary = CORNER_BOX.get(font_kind, CORNER_BOX["body"])
	for g in _glyphs:
		var p := (_t - float(g["i"]) * interval) / fade
		if p <= 0.0:
			continue
		p = minf(p, 1.0)
		var a := Kit.ease_in_out(p) * out_a
		var cp: int = g["cp"]
		var w: float = g["w"]
		var center := Vector2(float(g["x"]) + w * 0.5, float(g["y"]) + fs * 0.5)
		var sc := 1.0
		var off := Vector2.ZERO
		if effect == Effect.RISE:
			off.y = (1.0 - Kit.ease_out_cubic(p)) * fs * 0.22
		elif effect == Effect.BLEED:
			sc = 1.0 + (1.0 - Kit.ease_out_cubic(p)) * 0.16
		var ang := PI * 0.5 if bool(g["rot"]) else 0.0
		var base := Vector2(-w * 0.5, fs * (EM_ASC - 0.5))
		if bool(g["rot"]) and g.has("adv"):
			base.x = -float(g["adv"]) * 0.5
		if bool(g["corner"]):
			var bb: Vector2 = corner_tbl.get(str(g["ch"]), Vector2(200, 50))
			base = Vector2(fs * 0.22 - bb.x * fs / 1000.0, -fs * 0.22 + bb.y * fs / 1000.0)
		draw_set_transform(center + off, ang, Vector2(sc, sc))
		if halo > 0.0:
			# 三层由宽到窄、由淡到浓的外晕：柔和的墨晕，而不是一道硬描边
			font.draw_char_outline(ci, base, cp, font_size, halo_wide, Color(halo_color, 0.1 * halo * a))
			font.draw_char_outline(ci, base, cp, font_size, halo_mid, Color(halo_color, 0.2 * halo * a))
			font.draw_char_outline(ci, base, cp, font_size, halo_tight, Color(halo_color, 0.42 * halo * a))
		if effect == Effect.BLEED and p < 1.0:
			font.draw_char_outline(ci, base, cp, font_size, bleed_w, Color(color, sin(p * PI) * 0.4 * a))
		font.draw_char(ci, base, cp, font_size, Color(color, a))
	draw_set_transform_matrix(Transform2D.IDENTITY)
