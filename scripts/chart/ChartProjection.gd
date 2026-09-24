class_name ChartProjection
extends RefCounted
## 海图投影：等距圆锥（标准纬线 15°N / 35°N，中央经线 120°E）。
## 与 tools/build_terrain.py 同一公式；参数从 data/chart_projection.json 读，两边必须一致。
## 单位：投影平面以地球半径为 1；画布像素按 bounds 线性映射，y 向下。

var n: float = 0.0
var G: float = 0.0
var rho0: float = 0.0
var lon0_rad: float = 0.0
var canvas_w: float = 1.0
var canvas_h: float = 1.0
var x0: float = 0.0
var x1: float = 1.0
var y0: float = 0.0
var y1: float = 1.0
var loaded: bool = false


static func from_json(path: String = "res://data/chart_projection.json") -> ChartProjection:
	var p := ChartProjection.new()
	if not FileAccess.file_exists(path):
		push_error("ChartProjection: 找不到 %s" % path)
		return p
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("ChartProjection: %s 解析失败" % path)
		return p
	p.setup(j.data)
	return p


func setup(d: Dictionary) -> void:
	var phi1 := deg_to_rad(float(d.get("phi1", 15.0)))
	var phi2 := deg_to_rad(float(d.get("phi2", 35.0)))
	lon0_rad = deg_to_rad(float(d.get("lon0", 120.0)))
	# 不直接信 json 里的派生量，按同一公式重算，避免两边漂移
	n = (cos(phi1) - cos(phi2)) / (phi2 - phi1)
	G = cos(phi1) / n + phi1
	rho0 = G - (phi1 + phi2) * 0.5
	var cp: Array = d.get("canvas_px", [1, 1])
	canvas_w = float(cp[0])
	canvas_h = float(cp[1])
	var b: Dictionary = d.get("bounds", {})
	x0 = float(b.get("x0", 0.0))
	x1 = float(b.get("x1", 1.0))
	y0 = float(b.get("y0", 0.0))
	y1 = float(b.get("y1", 1.0))
	loaded = true


## 经纬度（度）→ 投影平面 (x, y)，y 向北为正
func forward(lon: float, lat: float) -> Vector2:
	var rho := G - deg_to_rad(lat)
	var theta := n * (deg_to_rad(lon) - lon0_rad)
	return Vector2(rho * sin(theta), rho0 - rho * cos(theta))


## 投影平面 → 经纬度（度）
func inverse(x: float, y: float) -> Vector2:
	var dy := rho0 - y
	var rho := signf(n) * sqrt(x * x + dy * dy)
	var theta := atan2(x, dy) if n > 0.0 else atan2(-x, -dy)
	var lat := rad_to_deg(G - rho)
	var lon := rad_to_deg(lon0_rad + theta / n)
	return Vector2(lon, lat)


## 经纬度 → 底图像素（左上原点，y 向下）
func to_px(lon: float, lat: float) -> Vector2:
	var p := forward(lon, lat)
	return Vector2((p.x - x0) / (x1 - x0) * canvas_w, (y1 - p.y) / (y1 - y0) * canvas_h)


## 底图像素 → 经纬度
func from_px(px: Vector2) -> Vector2:
	var x := x0 + px.x / canvas_w * (x1 - x0)
	var y := y1 - px.y / canvas_h * (y1 - y0)
	return inverse(x, y)


## 一个像素在该点对应多少公里（用于比例尺）
func km_per_px_at(lon: float, lat: float) -> float:
	var a := from_px(to_px(lon, lat) + Vector2(1, 0))
	var b := from_px(to_px(lon, lat))
	var dl := deg_to_rad(a.x - b.x) * cos(deg_to_rad(lat))
	var dp := deg_to_rad(a.y - b.y)
	return 6371.0 * sqrt(dl * dl + dp * dp)
