shader_type canvas_item;
render_mode blend_mix, unshaded;

/// 海上水气（lane atmos）：全屏一层，四角压一点冷青、上沿一抹天光——像隔着薄雾看海。很淡，不遮 HUD（在 HUD 之下）。

uniform float amount : hint_range(0.0, 1.0) = 0.5;
uniform vec4 cold : source_color = vec4(0.05, 0.10, 0.13, 1.0);
uniform vec4 sky : source_color = vec4(0.82, 0.86, 0.84, 1.0);
/// 接舷时收紧暗角（0–1）
uniform float focus : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = (uv - 0.5) * vec2(1.25, 1.0);
	float r = length(d);
	float vig = smoothstep(0.45 - focus * 0.12, 0.95 - focus * 0.2, r);
	float top = smoothstep(0.28, 0.0, uv.y) * 0.5;
	float a_v = vig * (0.34 + focus * 0.3) * amount;
	float a_s = top * 0.16 * amount * (1.0 - focus);
	vec3 c = mix(cold.rgb, sky.rgb, a_s / max(a_v + a_s, 1e-4));
	COLOR = vec4(c, clamp(a_v + a_s, 0.0, 1.0));
}
