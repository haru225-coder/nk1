shader_type canvas_item;
render_mode unshaded;

/// 本船重挨一下时的一拍屏幕反应（约 0.15 s）：顺来力方向的红蓝错位 + 四角压暗 + 极淡暖闪。
/// 画在世界画布最上层（HUD 在 CanvasLayer 上，不受影响）；amount 由 CombatFx._Look 逐帧衰减，为 0 时节点隐藏。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
/// 错位方向（屏幕坐标，单位向量）
uniform vec2 dir = vec2(1.0, 0.0);

void fragment() {
	vec2 suv = SCREEN_UV;
	vec2 off = dir * SCREEN_PIXEL_SIZE * (4.5 * amount);
	float r = texture(screen_tex, suv + off).r;
	vec4 g = texture(screen_tex, suv);
	float b = texture(screen_tex, suv - off).b;
	vec3 col = vec3(r, g.g, b);
	vec2 q = suv - 0.5;
	float vig = 1.0 - smoothstep(0.25, 0.75, length(q * vec2(1.3, 1.0))) * 0.45 * amount;
	col *= vig;
	col += vec3(1.0, 0.82, 0.55) * 0.05 * amount;
	COLOR = vec4(col, 1.0);
}
