extends SceneTree
## 两组截图逐张比对（lane gd20）：同一套截图探针「正常速度 vs 压帧（NK1_PROBE_SLOW_MS）」截出的图是否是同一个画面。
## 用法：godot --headless --path . -s res://tools/shot_consistency.gd -- --a=<目录A> --b=<目录B> [--noise=<目录A2>] [--strict] [--json]
##   A / B 为两次跑的 NK1_SHOT_DIR（或其任一子目录），按相对路径配对全部 *.png；
##   --noise=A2[,A3…]：同条件（正常速度）再跑的目录（逗号分隔可多份，取并集），作「自身抖动」基线——A 与任一 An
##   之间也会变的格子（每局随机的行情 / 人名、着色器 TIME 水纹、闪烁光标）不算压帧造成的差异。
## 判法：两图各按 8×8 像素块求平均（shrink_x2 三次，1280×720 → 160×90 格），某格任一通道差 > CELL_TOL 记「变格」。
##   SAME  ：零变格；
##   NOISE ：有变格，但全落在基线变格（外扩 1 格）之内——与正常速度自己跟自己比同样会变的地方；
##   EXTRA ：有基线之外的变格——压帧特有的差异，行尾给出变格外接框，须人看图逐条解释（报表不代为解释）；
##   MISSING / SIZE：一边缺图或尺寸不同，一律判红。
## --diff-out=<目录>：有变格的每对另存一张标注图（B 压暗一半；基线之外的变格涂红、基线之内的涂黄），供人看图解释。
## 目录可写相对路径（按启动时的 $PWD 展开，同 ShotGate.out_dir）；任一目录打不开、或一对图都没配上，判红——
##   路径写错不许得出「0 对全一致」。
## 退出码：有 MISSING / SIZE / 目录打不开 / 零对为 1；加 --strict 时 EXTRA 也为 1；其余 0。无 --noise 时 NOISE 不可判，有变格即 EXTRA。

const GateReport := preload("res://tools/gate_report.gd")
const CELL := 8
## 格均值差阈值（0–255）：PNG 无损，同帧重截为 0；8 足以滤掉抗锯齿 / 亚像素抖动，又抓得到半透明层淡入未满
const CELL_TOL := 8
const TAG := "SHOT_CONSISTENCY"


func _init() -> void:
	var opt := {"a": "", "b": "", "noise": "", "diff-out": ""}
	var strict := false
	for arg in OS.get_cmdline_user_args():
		for k in opt:
			if arg.begins_with("--%s=" % k):
				opt[k] = arg.trim_prefix("--%s=" % k)
		if arg == "--strict":
			strict = true
	if opt.a == "" or opt.b == "":
		_fail_early("缺 --a= / --b=")
		return
	var dirs: Array = [opt.a, opt.b]
	dirs.append_array(opt.noise.split(",", false))
	for i in dirs.size():
		dirs[i] = _abs(dirs[i])
		if not DirAccess.dir_exists_absolute(dirs[i]):
			_fail_early("目录打不开：%s" % dirs[i])
			return
	var pa := _pngs(dirs[0])
	var pb := _pngs(dirs[1])
	var pn: Array = []
	for d in dirs.slice(2):
		pn.append(_pngs(d))
	var rels: Array = pa.keys()
	for r in pb:
		if not r in pa:
			rels.append(r)
	rels.sort()
	var count := {"SAME": 0, "NOISE": 0, "EXTRA": 0, "MISSING": 0, "SIZE": 0}
	for rel in rels:
		var fns: Array = []
		for m in pn:
			if rel in m:
				fns.append(m[rel])
		var row := _compare(rel, pa.get(rel, ""), pb.get(rel, ""), fns, opt["diff-out"])
		count[row.verdict] += 1
		print("%-7s %-58s %s" % [row.verdict, rel, row.note])
		GateReport.check(row.verdict in ["SAME", "NOISE"] or (row.verdict == "EXTRA" and not strict), "%s %s %s" % [row.verdict, rel, row.note], "shot")
	if rels.is_empty():
		_fail_early("两个目录下都没有 *.png：%s / %s" % [dirs[0], dirs[1]])
		return
	var red: int = count.MISSING + count.SIZE + (count.EXTRA if strict else 0)
	var line := "%s_%s pairs=%d same=%d noise=%d extra=%d missing=%d size=%d" % [TAG, "OK" if red == 0 else "FAIL", rels.size(), count.SAME, count.NOISE, count.EXTRA, count.MISSING, count.SIZE]
	print(line)
	GateReport.finish(GateReport.main_script_name(), 0 if red == 0 else 1, line, {"tag": TAG, "counts": count, "strict": strict})
	quit(0 if red == 0 else 1)


func _fail_early(why: String) -> void:
	GateReport.check(false, why)
	print("%s_FAIL %s" % [TAG, why])
	GateReport.finish(GateReport.main_script_name(), 1, "%s_FAIL %s" % [TAG, why], {"tag": TAG})
	quit(1)


func _abs(dir: String) -> String:
	return dir if dir.is_absolute_path() else OS.get_environment("PWD").path_join(dir)


## 目录下全部 *.png：相对路径 → 绝对路径
func _pngs(dir: String) -> Dictionary:
	var out := {}
	_walk(dir, "", out)
	return out


func _walk(base: String, rel: String, out: Dictionary) -> void:
	var d := DirAccess.open(base.path_join(rel))
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension().to_lower() == "png":
			out[rel.path_join(f) if rel != "" else f] = base.path_join(rel).path_join(f)
	for sub in d.get_directories():
		_walk(base, rel.path_join(sub) if rel != "" else sub, out)


func _compare(rel: String, fa: String, fb: String, fns: Array, diff_out: String) -> Dictionary:
	if fa == "" or fb == "":
		return {"verdict": "MISSING", "note": "只在 %s 有" % ("A" if fb == "" else "B")}
	var a := _load(fa)
	var b := _load(fb)
	if a == null or b == null or a.get_size() != b.get_size():
		return {"verdict": "SIZE", "note": "A %s / B %s" % [a.get_size() if a else "读不出", b.get_size() if b else "读不出"]}
	var m := a.compute_image_metrics(b, false)
	var ab := _cells(a, b)
	var note := "mean=%.2f max=%d cells=%d/%d" % [float(m.get("mean", 0.0)), int(m.get("max", 0)), ab.n, ab.total]
	if ab.n == 0:
		return {"verdict": "SAME", "note": note}
	var noise := {}
	var noise_n := 0
	for fn in fns:
		var n := _load(fn)
		if n != null and n.get_size() == a.get_size():
			var an := _cells(a, n)
			noise.merge(_dilate(an.mask, ab.w, ab.h))
			noise_n = maxi(noise_n, an.n)
	if not fns.is_empty():
		note += " noise=%d" % noise_n
	var extra: Array = []
	for k in ab.mask:
		if not k in noise:
			extra.append(k)
	if diff_out != "":
		_write_diff(b, ab.mask, noise, diff_out.path_join(rel))
	if fns.is_empty():
		return {"verdict": "EXTRA", "note": note + " " + _bbox(extra)}
	if extra.is_empty():
		return {"verdict": "NOISE", "note": note}
	return {"verdict": "EXTRA", "note": note + " extra=%d %s" % [extra.size(), _bbox(extra)]}


func _write_diff(b: Image, mask: Dictionary, noise: Dictionary, path: String) -> void:
	var img := b.duplicate() as Image
	img.adjust_bcs(0.5, 1.0, 1.0)
	for k in mask:
		var tint := Color(1, 0.85, 0, 0.45) if k in noise else Color(1, 0, 0, 0.6)
		for y in range(k.y * CELL, mini((k.y + 1) * CELL, img.get_height())):
			for x in range(k.x * CELL, mini((k.x + 1) * CELL, img.get_width())):
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(tint, tint.a))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)


func _load(path: String) -> Image:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGB8)
	return img


## 两图按 CELL×CELL 块平均后逐格比：返回变格集合（Vector2i → true）、变格数、格网宽高
func _cells(a: Image, b: Image) -> Dictionary:
	var sa := _shrink(a)
	var sb := _shrink(b)
	var mask := {}
	for y in sa.get_height():
		for x in sa.get_width():
			var ca := sa.get_pixel(x, y)
			var cb := sb.get_pixel(x, y)
			if maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0 > CELL_TOL:
				mask[Vector2i(x, y)] = true
	return {"mask": mask, "n": mask.size(), "w": sa.get_width(), "h": sa.get_height(), "total": sa.get_width() * sa.get_height()}


## 边长先补到 CELL 的整数倍（最近邻拉伸，两图同一变换）：视口常是 1280×719，直接 shrink_x2 会把末 7 行舍掉不比
func _shrink(img: Image) -> Image:
	var s := img.duplicate() as Image
	var w := ceili(s.get_width() / float(CELL)) * CELL
	var h := ceili(s.get_height() / float(CELL)) * CELL
	if w != s.get_width() or h != s.get_height():
		s.resize(w, h, Image.INTERPOLATE_NEAREST)
	var k := CELL
	while k > 1:
		s.shrink_x2()
		k /= 2
	return s


func _dilate(mask: Dictionary, w: int, h: int) -> Dictionary:
	var out := {}
	for k in mask:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := Vector2i(k.x + dx, k.y + dy)
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
					out[q] = true
	return out


## 变格外接框，换回原图像素坐标
func _bbox(keys: Array) -> String:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for k in keys:
		lo = Vector2i(mini(lo.x, k.x), mini(lo.y, k.y))
		hi = Vector2i(maxi(hi.x, k.x), maxi(hi.y, k.y))
	return "bbox=(%d,%d)-(%d,%d)" % [lo.x * CELL, lo.y * CELL, (hi.x + 1) * CELL, (hi.y + 1) * CELL]
