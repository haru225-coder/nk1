extends RefCounted
## V0928-9 海战镜头顶匾让位的纯算口径（w25-j1）。钉住它的断言在
## tools/godot_story_check.gd `_w25j1_cam_plaque_check`，只读常数纯算，不起窗口。
##
## 判据链：顶匾 TideBar 占屏顶一条（屏矩形 (16,8)—(1264,80)，下沿 PLAQUE_BOTTOM）；它以下才是
## 玩家看敌船的可用区。旧镜头中心永远钉屏中 (640,360)：敌船贴身时船心屏位 = 360 + Δworld·zoom，
## Δworld.y 浅过 (80−360)/zoom = −560（zoom 0.5 时）就进匾——哨船场贴舷 140 屏 px、椭圆兜圈上冲
## 300+，必挨（w22-h1 量得 17.99%）。修法给镜头一份「荣誉 offset」：贴身时 Camera2D.offset.y =
## −dy（屏 px，值在 Ship.gd；WorldMap.gd `_cam_dy_apply` 不挪船身、只写这份 offset），镜头中心从
## 屏中挪向可用区中心：敌船要冲到 (80 − (360 + dy)) / zoom 世界 px 才碰匾，判据余量按 REST 档折回
## 取「屏上 dy + 280 px」。
##
## dy = 0 时回到修复前的居中镜头（判据账目自然「未满」）——断言（tools/godot_story_check.gd
## `_w25j1_cam_plaque_check`）读的是常数与口径函数，dy = 0 时以「让位不再谋求、居中沿用」的口径
## 仍判绿；真正钉红的是 dy > 0 时让位量不足 / 账目倒挂。

const VIEWPORT := Vector2(1280.0, 720.0)
## 顶匾 TideBar 屏下沿（屏 px；scenes/WorldMap.tscn 的 HUD 外边距 8 + 内容 68 + 内边距 4 ≈ 80 量得）
const PLAQUE_BOTTOM := 80.0
## 断言里折世界用的兜底 zoom：镜头全程 zoom ≥ Ship.CAM_ZOOM_FULL 0.42，按它折出的世界量最保守
const MIN_ZOOM := 0.42


## 屏向让位 dy_px（正值 = 镜头下移、给顶匾让位）折回世界 px：镜头 offset 是屏 px 口径，
## 画面上对应的世界位移按 dy_px / zoom 折。dy = 0 时归零（居中镜头）。
static func view_off(dy_px: float, zoom: float) -> Vector2:
	return Vector2(0.0, dy_px / maxf(zoom, 0.05))


## 虚偏 dy_px 屏 px 后「屏 3/4 高处的世界点」相对镜头中心的世界位移：
## 新中心屏 y = 360 + dy_px；屏 (640,540) 相对它偏 (0, 180 − dy_px) 屏 px，折回 / zoom。
## y > 0 即钉住「镜头中心已自屏中向下挪」；dy_px = 0 时旧镜头 y = 180/zoom（仍 > 0，居中沿用）。
static func view_quarter(dy_px: float, zoom: float) -> Vector2:
	var z := maxf(zoom, 0.05)
	return (Vector2(VIEWPORT.x * 0.5, VIEWPORT.y * 0.75)
		- Vector2(VIEWPORT.x * 0.5, VIEWPORT.y * 0.5 + dy_px)) / z


## 虚偏后敌船自本船（新中心 360+dy）上冲到匾下沿要的屏 px：dy + (360 − PLAQUE_BOTTOM) = dy + 280
static func headroom_px(dy_px: float) -> float:
	return (VIEWPORT.y * 0.5 - PLAQUE_BOTTOM) + dy_px
