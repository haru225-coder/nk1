extends SceneTree
## tour.sh 的出图后处理（lane pg5）：把一站的 Movie Maker 帧拼成 last.png + sheet.jpg，只用 Godot，不要 Python / PIL。
##
## 用法（tour.sh 每站调一次；cwd 须是不含 project.godot 的目录，免得顺带加载游戏工程与 autoload）：
##   cd <站点目录> && godot --headless -s <仓库>/tools/art/tour_sheet.gd -- <站点目录> <站点名>
## 产物（与原 PIL 版同规格）：
##   last.png   最后一帧原样拷贝
##   sheet.jpg  均匀取至多 12 帧，4 列 × 320×180，顶上 24px 标题「<站点>  (<N> frames)」，每格左上角帧号；JPEG 质量 86
## 没有 f*.png 就什么都不写、退 0（与原版一致）；参数错 / 读写失败退 1。
## 字形用仓库自带的 assets/fonts/LXGWWenKai-Medium.ttf（按本脚本位置找，FontFile 在 CPU 上光栅化，headless 可用）；
## 字体缺了照样出图，只是不写字（打 WARN）。

const PICK := 12
const TILE := Vector2i(320, 180)
const COLS := 4
const HEAD := 24
const QUALITY := 0.86
const BG := Color8(16, 14, 12)
const TITLE_COLOR := Color8(233, 220, 192)
const NUM_COLOR := Color8(255, 210, 90)
const NUM_BOX := Vector2i(58, 14)
const FONT_REL := "../../assets/fonts/LXGWWenKai-Medium.ttf"

var _font: FontFile


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	if args.size() != 2:
		printerr("TOUR_SHEET FAIL 用法：-- <站点目录> <站点名>")
		return 1
	var d := args[0]
	var site := args[1]
	if not DirAccess.dir_exists_absolute(d):
		printerr("TOUR_SHEET FAIL 站点目录不在：", d)
		return 1
	var frames: Array[String] = []
	for f in DirAccess.get_files_at(d):
		if f.begins_with("f") and f.ends_with(".png"):
			frames.append(d.path_join(f))
	frames.sort()
	if frames.is_empty():
		print("TOUR_SHEET SKIP ", site, "：没有帧")
		return 0
	if DirAccess.copy_absolute(frames[-1], d.path_join("last.png")) != OK:
		printerr("TOUR_SHEET FAIL 拷不出 last.png：", frames[-1])
		return 1
	var pick := frames
	if frames.size() > PICK:
		var idx := {}
		for i in PICK:
			idx[int(round(i * (frames.size() - 1) / float(PICK - 1)))] = true
		var keys := idx.keys()
		keys.sort()
		pick = []
		for k in keys:
			pick.append(frames[k])
	_font = _load_font()
	var rows := (pick.size() + COLS - 1) / COLS
	var sheet := Image.create(COLS * TILE.x, rows * TILE.y + HEAD, false, Image.FORMAT_RGB8)
	sheet.fill(BG)
	_text(sheet, Vector2i(6, 5), "%s  (%d frames)" % [site, frames.size()], 14, TITLE_COLOR)
	for i in pick.size():
		var im := Image.load_from_file(pick[i])
		if im == null or im.is_empty():
			printerr("TOUR_SHEET FAIL 读不了帧：", pick[i])
			return 1
		im.convert(Image.FORMAT_RGB8)
		im.resize(TILE.x, TILE.y, Image.INTERPOLATE_CUBIC)
		var at := Vector2i((i % COLS) * TILE.x, (i / COLS) * TILE.y + HEAD)
		sheet.blit_rect(im, Rect2i(Vector2i.ZERO, TILE), at)
		sheet.fill_rect(Rect2i(at, NUM_BOX + Vector2i.ONE), Color.BLACK)
		var num := pick[i].get_file().get_basename().substr(1).lstrip("0")
		_text(sheet, at + Vector2i(3, 1), num if num != "" else "0", 13, NUM_COLOR)
	var out := d.path_join("sheet.jpg")
	if sheet.save_jpg(out, QUALITY) != OK:
		printerr("TOUR_SHEET FAIL 写不了 ", out)
		return 1
	print("TOUR_SHEET OK ", site, " frames=", frames.size(), " picked=", pick.size(),
		" sheet=", sheet.get_width(), "x", sheet.get_height())
	return 0


func _load_font() -> FontFile:
	var here := ProjectSettings.globalize_path((get_script() as Script).resource_path).get_base_dir()
	var path := here.path_join(FONT_REL).simplify_path()
	var f := FontFile.new()
	if not FileAccess.file_exists(path) or f.load_dynamic_font(path) != OK:
		print("TOUR_SHEET WARN 字体不在（", path, "），小样不写字")
		return null
	return f


## 在 img 上以 pos 为左上角写一行字（逐字形 alpha 混色；不做字距调整，巡检小样够用）
func _text(img: Image, pos: Vector2i, s: String, px: int, color: Color) -> void:
	if _font == null:
		return
	var sz := Vector2i(px, 0)
	var base := pos.y + int(round(_font.get_ascent(px)))
	var pen := float(pos.x)
	for i in s.length():
		var g := _font.get_glyph_index(px, s.unicode_at(i), 0)
		_font.render_glyph(0, sz, g)
		var uv := Rect2i(_font.get_glyph_uv_rect(0, sz, g))
		if uv.size.x > 0 and uv.size.y > 0:
			var tex := _font.get_texture_image(0, sz, _font.get_glyph_texture_idx(0, sz, g)).get_region(uv)
			var o := Vector2i(_font.get_glyph_offset(0, sz, g).round()) + Vector2i(int(round(pen)), base)
			for y in tex.get_height():
				for x in tex.get_width():
					var a := tex.get_pixel(x, y).a
					var p := o + Vector2i(x, y)
					if a > 0.0 and p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
						img.set_pixelv(p, img.get_pixelv(p).lerp(color, a))
		pen += _font.get_glyph_advance(0, px, g).x
