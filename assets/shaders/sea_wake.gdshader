shader_type canvas_item;
render_mode blend_mix;

/// 航迹白练（lane atmos，SeaWake.gd 画的带子用）：UV.x 横跨带子 0–1，UV.y 是年纪 0（新）–1（老）；
/// 顶点色 alpha 是整体浓淡。中间翻白、两沿碎成沫，越老越碎越稀。世界坐标取噪声，船走迹不跟着滑。

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 ghash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

// 0–1 梯度噪声（值噪声阈值一切会露方格）
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float va = dot(ghash(i), f);
	float vb = dot(ghash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float vc = dot(ghash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float vd = dot(ghash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return clamp(0.5 + 0.8 * (va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd)), 0.0, 1.0);
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float age = UV.y;
	float n = vnoise(wpos / 7.0) * 0.55 + vnoise(wpos / 17.0 + TIME * 0.3) * 0.45;
	// 中心带：新迹宽而实，老迹收成一线
	float core = smoothstep(0.55 + 0.25 * (1.0 - age), 0.0, across);
	// 两沿碎沫：阈值随年纪抬高，越老越稀
	float edge = smoothstep(1.0, 0.55, across) * smoothstep(0.35 + age * 0.4, 0.8 + age * 0.15, n);
	float a = max(core * (0.55 + 0.45 * n), edge * 0.9);
	a *= smoothstep(0.25 + age * 0.35, 0.75, n + core * 0.4);
	vec3 foam = vec3(0.87, 0.915, 0.895);
	// 老迹偏青，融回海色
	foam = mix(foam, vec3(0.55, 0.70, 0.72), age * 0.6);
	COLOR = vec4(foam, clamp(a * COLOR.a * 0.8, 0.0, 1.0));
}
