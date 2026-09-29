shader_type canvas_item;
render_mode blend_mix, unshaded;

/// 出海福船 / 海鹘俯视精灵：帆布微抖、午后暖 rim、轻微对比提轮廓。
/// 不抠色（RGBA 船图已透明）；wind_dir 是船局部坐标里风往哪吹（长度 0–1）。

uniform float wind_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 wind_dir = vec2(0.15, -0.4);
uniform float sail_flutter : hint_range(0.0, 1.0) = 0.55;
uniform float warm_rim : hint_range(0.0, 1.0) = 0.42;
uniform float contrast : hint_range(0.8, 1.4) = 1.08;
uniform float time_scale : hint_range(0.2, 3.0) = 1.1;

void fragment() {
	vec2 uv = UV;
	// 帆多在图中上部；按亮度估帆区，抖 UV（竹篾硬帆小幅折光，不是软布大摆）
	vec4 peek = texture(TEXTURE, uv);
	float lum = dot(peek.rgb, vec3(0.299, 0.587, 0.114));
	float sail_m = smoothstep(0.55, 0.82, lum) * peek.a;
	vec2 flutter = wind_dir * (0.0045 * sail_flutter * wind_strength)
		* sin(TIME * time_scale * 5.2 + uv.y * 28.0 + uv.x * 11.0);
	flutter += wind_dir.yx * vec2(-1.0, 1.0) * (0.0022 * sail_flutter)
		* cos(TIME * time_scale * 3.4 + uv.x * 18.0);
	uv += flutter * sail_m;

	vec4 c = texture(TEXTURE, uv);
	// 对比略提：船板缝与帆骨更清楚
	vec3 mid = vec3(0.45);
	c.rgb = mid + (c.rgb - mid) * contrast;

	// 午后暖 rim：受风一侧（UV 按 wind_dir）加一圈薄泥金
	vec2 from_c = uv - vec2(0.5);
	float rim = smoothstep(0.22, 0.48, length(from_c));
	float wind_side = clamp(dot(normalize(from_c + vec2(0.0001)), normalize(wind_dir + vec2(0.0001))), 0.0, 1.0);
	vec3 warm = vec3(1.0, 0.86, 0.62);
	c.rgb = mix(c.rgb, c.rgb * warm + warm * 0.08, rim * wind_side * warm_rim * c.a);

	COLOR = c;
}
