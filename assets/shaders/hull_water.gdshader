shader_type canvas_item;

/// 船底下那片水（lane combat12-E，Ship / PirateShip 的 HullWater，画在船图之下，参数由 scripts/combat/ShipLook.gd 逐帧写）：
///   投影——船形往背日一侧落、边缘虚，海面上压一片深青；
///   贴舷白浪——船形外一圈碎沫，停着只是细细一线拍舷，船走起来船头与两舷变厚、船尾翻白。
/// 与船图用同一张贴图、同一套变换，换图（CombatFx.apply_ship_sprite）由 ShipLook 跟着换。

/// 投影在贴图 UV 里的偏移（ShipLook 按日照方向与船向换算）与颜色、虚化半径（贴图像素）
uniform vec2 shadow_uv = vec2(0.02, 0.03);
uniform vec4 shadow_color : source_color = vec4(0.01, 0.05, 0.1, 0.58);
uniform float shadow_blur = 10.0;
/// 白浪颜色、基础宽度（贴图像素）、航速（0..1）、每条船错开的相位、整体淡出（沉没 / 离场时跟船图的 alpha）
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 0.97, 0.8);
uniform float foam_px = 5.0;
uniform float speed = 0.0;
uniform float phase = 0.0;
uniform float fade = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 s = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), s.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), s.x), s.y);
}

// 八向取样（轴向四个 + 斜向四个，斜向按单位长）。TEXTURE 不能当实参传进自定义函数（Godot 取不到内建采样器），
// 所以投影虚化与白浪外扩都在 fragment 里就地循环
const vec2 DIRS[8] = vec2[8](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
	vec2(0.7071, 0.7071), vec2(-0.7071, -0.7071), vec2(0.7071, -0.7071), vec2(-0.7071, 0.7071));

void fragment() {
	float a0 = texture(TEXTURE, UV).a;
	vec2 suv = UV - shadow_uv;
	float sh = texture(TEXTURE, suv).a * 0.2;
	float sp = clamp(speed, 0.0, 1.0);
	// 船头（贴图上方）与船尾（下方）：走起来这两处白浪最厚
	float bow = smoothstep(0.5, 0.12, UV.y);
	float stern = smoothstep(0.72, 0.95, UV.y);
	float w = foam_px * (1.0 + 1.4 * sp * (bow + 0.6 * stern));
	float ring = 0.0;
	for (int i = 0; i < 8; i++) {
		// 投影：轴向每样 0.12、斜向 0.08，连中心合 1
		sh += texture(TEXTURE, suv + DIRS[i] * TEXTURE_PIXEL_SIZE * shadow_blur).a * (i < 4 ? 0.12 : 0.08);
		// 白浪：船形往外扩 w 与 0.45w 两圈取最大，减去船形本身，剩贴舷一圈
		ring = max(ring, texture(TEXTURE, UV + DIRS[i] * TEXTURE_PIXEL_SIZE * w).a);
		ring = max(ring, texture(TEXTURE, UV + DIRS[i] * TEXTURE_PIXEL_SIZE * w * 0.45).a);
	}
	float band = clamp(ring - a0, 0.0, 1.0);
	float t = TIME * (0.5 + 2.2 * sp);
	float n = vnoise(vec2(UV.x * 46.0 + phase, UV.y * 70.0 - t * 3.0 + phase * 1.7));
	n = n * 0.65 + 0.35 * vnoise(vec2(UV.x * 110.0 - phase, UV.y * 150.0 - t * 5.0));
	float strength = 0.12 + 0.88 * clamp(sp * (0.22 + 1.3 * bow + 0.9 * stern), 0.0, 1.0);
	float foam = band * smoothstep(0.28, 0.72, n) * strength;
	vec4 col = vec4(shadow_color.rgb, shadow_color.a * sh);
	col.rgb = mix(col.rgb, foam_color.rgb, clamp(foam * 1.6, 0.0, 1.0));
	col.a = max(col.a, foam * foam_color.a);
	COLOR = vec4(col.rgb, col.a * clamp(fade, 0.0, 1.0));
}
