## VisionStage 待补三项贴图生成器（lane-v2）。可复跑，结果确定：FastNoiseLite 固定种子，无随机源。
## 用法：godot --headless --path . -s res://tools/art/vision_fill_gen.gd
## 产物全部写入 res://scenes/vision/fill/，RGBA8 透明底：
##   vs_muzzle_strip.png   1024×64   舷侧炮焰 8 帧横排，每帧 128×64；炮口在帧左中 (6,32)，焰朝 +x
##   vs_splash_strip.png    768×128  落弹水花 8 帧横排，每帧 96×128；水线在帧底中 (48,112)
##   vs_corner_gilt.png      96×96   大裱框泥金角花，左上角朝向（其余三角由 flip 得）
##   vs_chart_fragment.png  768×400  宋绢海图残片：计里画方 + 鱼鳞水纹 + 岸线 + 山形符 + 残边虫蛀
## 风格约束：宋绢 + 暖墨，焰用赭金朱砂、烟用暖墨、水花用绢白靛影；不做渐变玻璃与现代滤镜。
## 这四张是程序仿绘占位：炮焰 / 水花不是手绘序列帧，海图残片不是宋绢实物扫描。换手绘 / 绢本见
## docs/VisionStage待补工单.md；换上后别再整跑本脚本（会把四张一起重写回程序版）。
extends SceneTree

const OUT := "res://scenes/vision/fill"
const MUZZLE_FRAMES := 8
const MUZZLE_CELL := Vector2i(128, 64)
const SPLASH_FRAMES := 8
const SPLASH_CELL := Vector2i(96, 128)
const CORNER_SIZE := 96
const CHART_SIZE := Vector2i(768, 400)

# 色（线性值足够，全部在 0..1）
const INK := Color(0.110, 0.090, 0.070)
const INK_WARM := Color(0.230, 0.205, 0.180)
const INK_PALE := Color(0.430, 0.395, 0.350)
const FLAME_CORE := Color(1.000, 0.930, 0.720)
const FLAME_MID := Color(0.930, 0.560, 0.230)
const FLAME_EDGE := Color(0.700, 0.240, 0.120)
const SILK_WHITE := Color(0.930, 0.905, 0.840)
const WATER_SHADE := Color(0.440, 0.570, 0.630)
const GOLD_LO := Color(0.540, 0.390, 0.160)
const GOLD_MID := Color(0.800, 0.640, 0.330)
const GOLD_HI := Color(0.960, 0.840, 0.540)
const JUAN := Color(0.740, 0.640, 0.470)
const JUAN_BURN := Color(0.360, 0.250, 0.140)
const OCHRE := Color(0.600, 0.470, 0.300)
const SEA_INK := Color(0.200, 0.255, 0.290)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var made: Array = []
	made.append(_save(_muzzle_strip(), "vs_muzzle_strip.png"))
	made.append(_save(_splash_strip(), "vs_splash_strip.png"))
	made.append(_save(_corner_gilt(), "vs_corner_gilt.png"))
	made.append(_save(_chart_fragment(), "vs_chart_fragment.png"))
	var bad := made.count("")
	for m in made:
		if m != "":
			print("  wrote ", m)
	print("vision_fill_gen %s files=%d bad=%d" % ["OK" if bad == 0 else "FAIL", made.size() - bad, bad])
	quit(0 if bad == 0 else 1)


func _save(img: Image, name: String) -> String:
	var path := "%s/%s" % [OUT, name]
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("save failed %s (%d)" % [path, err])
		return ""
	return "%s %dx%d" % [path, img.get_width(), img.get_height()]


# ── 小工具 ─────────────────────────────────────────────

func _noise(seed_v: int, freq: float, octaves := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n


func _sstep(e0: float, e1: float, v: float) -> float:
	var t := clampf((v - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 往 (x,y) 叠一层颜色（premultiplied 意义上的 over）。
func _over(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if a <= 0.0:
		return
	a = minf(a, 1.0)
	var d := img.get_pixel(x, y)
	var out_a := a + d.a * (1.0 - a)
	if out_a <= 0.0001:
		return
	var r := (c.r * a + d.r * d.a * (1.0 - a)) / out_a
	var g := (c.g * a + d.g * d.a * (1.0 - a)) / out_a
	var b := (c.b * a + d.b * d.a * (1.0 - a)) / out_a
	img.set_pixel(x, y, Color(r, g, b, out_a))


## 离散哈希 0..1，用于撒金点、虫蛀位置等（确定性）。
func _hash01(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 100000) / 100000.0


## 笔画栅格化：strokes 每项 {pts: PackedVector2Array, w: PackedFloat32Array 逐点宽}。取覆盖最大值。
func _raster(w: int, h: int, strokes: Array) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(w * h)
	for s in strokes:
		var pts: PackedVector2Array = s["pts"]
		var ws: PackedFloat32Array = s["w"]
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var wa := ws[k]
			var wb := ws[k + 1]
			var pad := maxf(wa, wb) * 0.5 + 1.5
			var x0 := maxi(0, int(floor(minf(a.x, b.x) - pad)))
			var x1 := mini(w - 1, int(ceil(maxf(a.x, b.x) + pad)))
			var y0 := maxi(0, int(floor(minf(a.y, b.y) - pad)))
			var y1 := mini(h - 1, int(ceil(maxf(a.y, b.y) + pad)))
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 0.000001)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var p := Vector2(x + 0.5, y + 0.5)
					var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
					var dist := p.distance_to(a + ab * t)
					var cov := clampf(lerpf(wa, wb, t) * 0.5 - dist + 0.5, 0.0, 1.0)
					var i := y * w + x
					if cov > buf[i]:
						buf[i] = cov
	return buf


## 线宽剖面：taper = 线性 w0→w1；leaf = 两端尖中间 w0 粗。
func _stroke(pts: PackedVector2Array, w0: float, w1: float, leaf := false) -> Dictionary:
	var ws := PackedFloat32Array()
	var n := pts.size()
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		ws.append(w0 * sin(PI * t) if leaf else lerpf(w0, w1, t))
	return {"pts": pts, "w": ws}


func _spiral(c: Vector2, r0: float, r1: float, a0: float, turns: float, steps := 64) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var r := lerpf(r0, r1, t)
		var a := a0 + TAU * turns * t
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _line(a: Vector2, b: Vector2, steps := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		pts.append(a.lerp(b, float(i) / float(steps)))
	return pts


func _mirror_diag(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.y, p.x))
	return out


# ── 1. 舷侧炮焰 ─────────────────────────────────────────

func _muzzle_strip() -> Image:
	var cw := MUZZLE_CELL.x
	var ch := MUZZLE_CELL.y
	var img := Image.create(cw * MUZZLE_FRAMES, ch, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var nz := _noise(4101, 0.09, 3)
	var nz_s := _noise(4102, 0.06, 4)
	# 逐帧参数：焰强 / 焰长 / 焰宽 / 烟浓
	var flame_i := PackedFloat32Array([1.0, 1.0, 0.78, 0.42, 0.16, 0.0, 0.0, 0.0])
	var flame_l := PackedFloat32Array([30.0, 66.0, 88.0, 94.0, 90.0, 0.0, 0.0, 0.0])
	var flame_w := PackedFloat32Array([9.0, 14.0, 16.0, 15.0, 12.0, 0.0, 0.0, 0.0])
	var smoke_i := PackedFloat32Array([0.0, 0.45, 0.70, 0.80, 0.78, 0.68, 0.50, 0.28])
	# 烟团：沿炮轴的基准距离、半径、上飘系数
	var puffs := [[12.0, 6.0, 0.4], [22.0, 7.5, 0.8], [33.0, 8.5, 0.5], [45.0, 9.5, 1.1],
		[57.0, 10.0, 0.7], [70.0, 10.5, 1.3], [84.0, 11.0, 0.9]]
	for f in MUZZLE_FRAMES:
		var g := float(f) / float(MUZZLE_FRAMES - 1)
		var ox := f * cw
		for y in ch:
			for x in cw:
				var u := float(x) - 6.0
				var v := float(y) - 32.0
				# 烟：暖墨团，逐帧外推、上飘、胀大
				var sa := 0.0
				if smoke_i[f] > 0.0:
					var keep := 1.0
					for pf in puffs:
						var cx: float = pf[0] * (0.55 + 0.75 * g)
						var cy: float = -pf[2] * 10.0 * g
						var r: float = pf[1] * (0.55 + 1.35 * g)
						var dd := Vector2(u - cx, v - cy).length() / r
						dd += 0.32 * nz_s.get_noise_3d(x * 1.0, y * 1.0, f * 9.0)
						keep *= 1.0 - _sstep(1.0, 0.25, dd) * 0.8
					sa = (1.0 - keep) * smoke_i[f]
					# 干笔：烟边有纤维断续
					sa *= 0.78 + 0.22 * nz.get_noise_2d(x * 2.0, y * 0.6 + f * 13.0)
				if sa > 0.004:
					var lit: float = flame_i[f] * 0.55
					var sc := INK_WARM.lerp(INK_PALE, clampf(1.0 - sa, 0.0, 1.0)).lerp(FLAME_EDGE, lit * 0.5)
					_over(img, ox + x, y, sc, sa)
				# 焰：炮口喷出的舌形，芯亮边赭
				if flame_i[f] > 0.0 and u >= -2.0:
					var fl: float = flame_l[f]
					var tt := clampf(u / fl, 0.0, 1.0)
					var hw: float = flame_w[f] * pow(sin(PI * clampf(tt * 0.92 + 0.04, 0.0, 1.0)), 0.7) * (1.0 - 0.4 * tt)
					hw *= 1.0 + 0.38 * nz.get_noise_3d(x * 1.3, y * 1.3, f * 5.0)
					if u <= fl and hw > 0.2:
						var d := absf(v + 2.0 * tt * tt) / hw
						var a := _sstep(1.0, 0.7, d) * flame_i[f]
						var core := pow(clampf(1.0 - d, 0.0, 1.0), 1.4) * pow(1.0 - tt, 0.6)
						var fc := FLAME_EDGE.lerp(FLAME_MID, _sstep(0.0, 0.45, core)).lerp(FLAME_CORE, _sstep(0.45, 0.9, core))
						_over(img, ox + x, y, fc, a * (0.55 + 0.45 * _sstep(0.0, 0.3, core)))
					# 炮口闪：前两帧一团亮芯
					if f <= 1:
						var r := Vector2(u, v).length()
						# 半径压小并在帧左缘 4px 内收掉，免得光晕被帧边切出硬线
						var star := exp(-r / (3.6 + 1.6 * f)) * (1.0 - 0.3 * f) * _sstep(0.0, 4.0, float(x))
						_over(img, ox + x, y, FLAME_CORE, star)
	return img


# ── 2. 落弹水花 ─────────────────────────────────────────

func _splash_strip() -> Image:
	var cw := SPLASH_CELL.x
	var ch := SPLASH_CELL.y
	var img := Image.create(cw * SPLASH_FRAMES, ch, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var nz := _noise(4201, 0.05, 3)
	var nz_b := _noise(4202, 0.18, 2)
	var col_h := PackedFloat32Array([16.0, 56.0, 90.0, 102.0, 94.0, 66.0, 32.0, 0.0])
	var col_w := PackedFloat32Array([11.0, 14.0, 15.0, 16.0, 18.0, 21.0, 24.0, 0.0])
	var col_i := PackedFloat32Array([0.85, 0.95, 0.95, 0.9, 0.75, 0.55, 0.35, 0.0])
	var ring_i := PackedFloat32Array([0.45, 0.65, 0.75, 0.75, 0.7, 0.58, 0.44, 0.26])
	# 飞沫：水平速度 / 竖直初速 / 半径（确定性表）
	var drops: Array = []
	for k in 16:
		var side := -1.0 if k % 2 == 0 else 1.0
		drops.append([side * (5.0 + 2.3 * float((k * 3) % 8)), 62.0 + 7.0 * float((k * 7) % 9), 1.1 + 0.3 * float(k % 3)])
	var bx := 48.0
	var by := 112.0
	for f in SPLASH_FRAMES:
		var ox := f * cw
		var tf := float(f) / float(SPLASH_FRAMES - 1)
		for y in ch:
			for x in cw:
				var px := float(x) + 0.5
				var py := float(y) + 0.5
				# 基脚水圈：随帧外扩的扁椭圆环
				var rx := 9.0 + float(f) * 5.0
				var ry := rx * 0.26
				var e := Vector2((px - bx) / rx, (py - by) / ry).length()
				var ring := exp(-pow((e - 1.0) * rx / 2.4, 2.0)) * ring_i[f]
				ring *= 0.7 + 0.3 * nz_b.get_noise_2d(px * 2.0, py * 2.0 + f * 7.0)
				if e < 1.0 and f <= 3:
					ring = maxf(ring, (1.0 - e) * 0.35 * (1.0 - float(f) / 4.0))
				if ring > 0.01:
					_over(img, ox + x, y, SILK_WHITE.lerp(WATER_SHADE, 0.25), ring)
				# 水柱：底宽顶收、顶端冠开，竖纹断续；后几帧散成水点
				var hh: float = col_h[f]
				var h := by - py
				if hh > 0.0 and h >= -2.0 and h <= hh + 8.0:
					var th := clampf(h / hh, 0.0, 1.0)
					var hw: float = col_w[f] * (1.0 - 0.6 * th) + 7.0 * exp(-pow((hh - h) / 9.0, 2.0))
					hw *= 1.0 + 0.3 * nz.get_noise_2d(px * 1.5, py * 0.8 + f * 11.0)
					var d := absf(px - bx) / maxf(hw, 0.5)
					var a := _sstep(1.0, 0.55, d) * _sstep(hh + 8.0, hh - 6.0, h) * col_i[f]
					var streak := 0.62 + 0.38 * nz_b.get_noise_2d(px * 1.2, py * 0.12)
					a *= streak
					if f >= 4:
						# 塌落：用低频团块断开水柱（高频会成黑麻点）
						var clump := nz_b.get_noise_2d(px * 0.55, py * 0.35 + f * 17.0) * 0.5 + 0.5
						a *= _sstep(0.12 + 0.12 * float(f - 4), 0.42 + 0.12 * float(f - 4), clump)
					if a > 0.01:
						var shade := _sstep(0.1, 0.9, (px - bx) / maxf(hw, 0.5))
						var c := SILK_WHITE.lerp(WATER_SHADE, shade * 0.7 + 0.15 * th)
						_over(img, ox + x, y, c, a)
						# 淡墨勾边：只在柱边一线，压低透明度，免成卡通描边
						var edge := exp(-pow((d - 0.92) * 9.0, 2.0)) * a * 0.22
						_over(img, ox + x, y, SEA_INK, edge)
		# 飞沫点
		for dr in drops:
			var tt := tf * 1.6
			var dx: float = bx + dr[0] * tt * 1.3
			var dy: float = by - (dr[1] * tt - 0.5 * 95.0 * tt * tt)
			if dy > by + 2.0 or f == 0:
				continue
			var rr: float = dr[2]
			for yy in range(int(dy - rr - 2.0), int(dy + rr + 3.0)):
				for xx in range(int(dx - rr - 2.0), int(dx + rr + 3.0)):
					if xx < 0 or yy < 0 or xx >= cw or yy >= ch:
						continue
					var dd := Vector2(xx + 0.5 - dx, yy + 0.5 - dy).length()
					var a := clampf(rr - dd + 0.5, 0.0, 1.0) * (1.0 - tf * 0.7)
					_over(img, ox + xx, yy, SILK_WHITE, a)
	return img


# ── 3. 大裱框泥金角花 ─────────────────────────────────────

func _corner_gilt() -> Image:
	var n := CORNER_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half: Array = []
	# 外框双线：粗线贴边、细线在内，末端收笔（接进裱框本身的 1px 金线）
	half.append(_stroke(_line(Vector2(5, 5), Vector2(94, 5), 40), 2.6, 0.5))
	half.append(_stroke(_line(Vector2(11, 11), Vector2(64, 11), 30), 1.3, 0.3))
	# 如意云头：两枚对称卷涡，从对角茎分出，向外绕一圈半收进
	var lobe_c := Vector2(33, 20)
	var a0 := (Vector2(23, 23) - lobe_c).angle()
	half.append(_stroke(_spiral(lobe_c, 10.4, 2.0, a0, 1.35, 90), 2.2, 0.8))
	# 卷草：沿顶边的波状茎，末端小卷；两片叶
	var vine := PackedVector2Array()
	for i in 41:
		var t := float(i) / 40.0
		var x := lerpf(42.0, 78.0, t)
		vine.append(Vector2(x, 18.5 + 3.2 * sin(t * PI * 1.5)))
	half.append(_stroke(vine, 1.6, 0.9))
	var tip := vine[vine.size() - 1]
	var curl_c := tip + Vector2(0, 4.6)
	half.append(_stroke(_spiral(curl_c, 4.6, 0.8, (tip - curl_c).angle(), 1.15, 40), 0.9, 0.5))
	half.append(_stroke(_line(Vector2(51, 21), Vector2(58, 29), 16), 3.2, 0.0, true))
	half.append(_stroke(_line(Vector2(66, 17), Vector2(71, 10.5), 16), 2.6, 0.0, true))
	var strokes: Array = []
	for s in half:
		strokes.append(s)
		strokes.append({"pts": _mirror_diag(s["pts"]), "w": s["w"]})
	# 对角茎与珠（自身对称，只画一次）
	strokes.append(_stroke(_line(Vector2(11, 11), Vector2(23, 23), 16), 1.8, 1.8))
	var pearl := PackedVector2Array([Vector2(29.5, 29.5), Vector2(29.6, 29.6)])
	strokes.append({"pts": pearl, "w": PackedFloat32Array([5.0, 5.0])})
	var cov := _raster(n, n, strokes)
	var nz := _noise(4301, 0.35, 2)
	# 先落一道极淡的墨影（右下 1px），金才浮在裱绫上
	for y in n:
		for x in n:
			var sx := x - 1
			var sy := y - 1
			if sx >= 0 and sy >= 0:
				var s := cov[sy * n + sx]
				if s > 0.0:
					_over(img, x, y, INK, s * 0.55)
	# 泥金：细颗粒明暗 + 零星金屑高光
	for y in n:
		for x in n:
			var a := cov[y * n + x]
			if a <= 0.0:
				continue
			var grain := nz.get_noise_2d(x * 1.0, y * 1.0) * 0.5 + 0.5
			var c := GOLD_LO.lerp(GOLD_MID, _sstep(0.15, 0.6, grain)).lerp(GOLD_HI, _sstep(0.62, 0.95, grain))
			if _hash01(x, y, 43) > 0.965:
				c = GOLD_HI
			_over(img, x, y, c, a)
	return img


# ── 4. 宋绢海图残片 ───────────────────────────────────────

func _chart_fragment() -> Image:
	var w := CHART_SIZE.x
	var h := CHART_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var n_edge := _noise(4401, 0.018, 4)
	var n_fine := _noise(4402, 0.11, 2)
	var n_stain := _noise(4403, 0.006, 3)
	var n_fiber := _noise(4404, 0.02, 2)
	var n_land := _noise(4405, 0.0075, 4)
	var n_wear := _noise(4406, 0.012, 3)
	# 陆地场：左上高 + 右下一小岛；阈值 0 为岸
	var land := PackedFloat32Array()
	land.resize(w * h)
	var isle := Vector2(662, 300)
	for y in h:
		for x in w:
			var bias := 0.62 - (float(x) / w * 1.35 + float(y) / h * 1.15)
			var bump := 0.55 * exp(-Vector2(x, y).distance_squared_to(isle) / (2.0 * 34.0 * 34.0)) - 0.12
			land[y * w + x] = maxf(bias + 0.42 * n_land.get_noise_2d(x, y), bump + 0.12 * n_land.get_noise_2d(x + 900.0, y))
	# 虫蛀：靠边的若干小洞（确定性表）
	var holes := [[Vector2(58, 356), 7.0], [Vector2(212, 372), 4.5], [Vector2(705, 64), 6.0],
		[Vector2(742, 188), 4.0], [Vector2(30, 140), 5.0], [Vector2(480, 30), 3.5]]
	# 山形符（计里画方图常用的三峰记号）
	var mounts := [Vector2(70, 70), Vector2(128, 46), Vector2(52, 150), Vector2(186, 84), Vector2(660, 292)]
	var mstrokes: Array = []
	for m in mounts:
		var s := 7.0 if m.x < 600 else 5.0
		var pts := PackedVector2Array([m + Vector2(-s * 1.6, 0), m + Vector2(-s * 0.8, -s * 0.9), m + Vector2(0, -s * 0.1),
			m + Vector2(s * 0.6, -s * 1.4), m + Vector2(s * 1.3, -s * 0.1), m + Vector2(s * 1.9, -s * 0.8), m + Vector2(s * 2.5, 0)])
		mstrokes.append(_stroke(pts, 1.6, 1.0))
	var mcov := _raster(w, h, mstrokes)
	var grid := 64.0
	var sc_dx := 30.0
	var sc_dy := 16.0
	for y in h:
		for x in w:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			# 残边：边距被噪声啃成毛边，右下缺一角
			var dm := minf(minf(px, w - px), minf(py, h - py))
			var e := dm - 16.0 - 14.0 * n_edge.get_noise_2d(px, py) - 3.5 * n_fine.get_noise_2d(px, py)
			var cut := (px / w * 0.9 + py / h) - 1.62 - 0.06 * n_edge.get_noise_2d(px * 2.0, py * 2.0)
			e = minf(e, -cut * 160.0)
			for hl in holes:
				var hc: Vector2 = hl[0]
				var hr: float = hl[1] * (1.0 + 0.35 * n_fine.get_noise_2d(px * 2.0, py * 2.0))
				e = minf(e, Vector2(px, py).distance_to(hc) - hr)
			var alpha := _sstep(-0.9, 0.9, e)
			if alpha <= 0.0:
				continue
			# 绢地：经纬细纹 + 纵向丝缕 + 大片水渍
			var weave := 0.022 * (sin(px * 2.2) + sin(py * 2.05))
			var fiber := 0.035 * n_fiber.get_noise_2d(px * 0.15, py * 6.0)
			var stain := 0.14 * maxf(n_stain.get_noise_2d(px, py), 0.0)
			var c := JUAN * (1.0 + weave + fiber - stain)
			c.a = 1.0
			# 边缘焦黄：离残边越近越深
			c = c.lerp(JUAN_BURN, 0.62 * exp(-maxf(e, 0.0) / 9.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
			var lv := land[y * w + x]
			var wear := _sstep(-0.35, 0.15, n_wear.get_noise_2d(px, py))
			# 计里画方：淡墨方格，墨色随磨损断续
			var gx := absf(fposmod(px + 1.5 * n_fine.get_noise_2d(py, 0.0), grid) - grid * 0.5)
			var gy := absf(fposmod(py + 1.5 * n_fine.get_noise_2d(0.0, px), grid) - grid * 0.5)
			var gl := maxf(clampf(1.2 - (grid * 0.5 - gx), 0.0, 1.0), clampf(1.2 - (grid * 0.5 - gy), 0.0, 1.0))
			_over(img, x, y, INK_WARM, gl * 0.16 * (0.4 + 0.6 * wear))
			if lv > 0.0:
				# 陆：赭色淡染，斑驳
				_over(img, x, y, OCHRE, (0.30 + 0.12 * n_fine.get_noise_2d(px * 0.5, py * 0.5)) * _sstep(0.0, 0.05, lv))
			else:
				# 海：极淡靛染 + 鱼鳞水纹（上半弧），近岸渐隐
				var sea_fade := _sstep(-0.02, -0.12, lv)
				_over(img, x, y, SEA_INK, 0.07 * sea_fade)
				var row := int(floor(py / sc_dy))
				var best := 99.0
				for j in range(row, row + 3):
					var cy := float(j) * sc_dy
					if py > cy:
						continue
					var off := sc_dx * 0.5 if j % 2 == 1 else 0.0
					var ci := roundi((px - off) / sc_dx)
					for i in range(ci - 1, ci + 2):
						var cx := float(i) * sc_dx + off
						var r := sc_dx * 0.5 + 0.9 * n_fine.get_noise_2d(cx, cy)
						best = minf(best, absf(Vector2(px - cx, py - cy).length() - r))
				var wave := clampf(1.0 - best / 0.85, 0.0, 1.0)
				_over(img, x, y, SEA_INK, wave * 0.34 * sea_fade * (0.35 + 0.65 * wear))
			# 岸线：|场|/|梯度| 近似距离，焦墨一线 + 内侧淡墨双勾
			if x > 0 and y > 0 and x < w - 1 and y < h - 1:
				var gxv := (land[y * w + x + 1] - land[y * w + x - 1]) * 0.5
				var gyv := (land[(y + 1) * w + x] - land[(y - 1) * w + x]) * 0.5
				var gm := maxf(sqrt(gxv * gxv + gyv * gyv), 0.00001)
				var d0 := absf(lv) / gm
				var d1 := absf(lv - 0.045) / gm
				var coast := exp(-pow(d0 / 1.05, 2.0)) * 0.85
				var inner := exp(-pow(d1 / 0.8, 2.0)) * 0.35
				_over(img, x, y, INK, maxf(coast, inner) * (0.7 + 0.3 * wear))
			var mc := mcov[y * w + x]
			if mc > 0.0:
				_over(img, x, y, INK, mc * 0.7 * (0.6 + 0.4 * wear))
			# 墨色都落在不透明绢地上，最后才把残边透明度盖回去
			var fin := img.get_pixel(x, y)
			fin.a = alpha
			img.set_pixel(x, y, fin)
	return img
