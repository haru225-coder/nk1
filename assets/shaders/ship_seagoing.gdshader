shader_type canvas_item;
render_mode blend_mix, unshaded;

/// 出海福船 / 海鹘俯视精灵（任一张 ship_<id>.png 都能套）：
///   帆篷微抖——只抖奶油硬帆 / 绛红帆的色域（按亮度估会连亮木船板一起抖），竹篾硬帆小幅折光，不是软布大摆；
///   午后暖 rim、对比略提；命中处一记炽橙（紧、快，不是整船泛白）；挨过的砲石留焦痕与一圈新茬（最多 6 处，随船到终场）。
/// wind_dir 是船局部坐标里风往哪吹（长度 0–1）；hit / scars 由 CombatFx 的 _Look 逐帧写。
/// modulate / self_modulate（降幡发灰、进水压暗）照乘。受光 / 背光、投影归 ShipLook 的 HullLight / HullWater 两层。

uniform float wind_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 wind_dir = vec2(0.15, -0.4);
uniform float sail_flutter : hint_range(0.0, 1.0) = 0.55;
uniform float warm_rim : hint_range(0.0, 1.0) = 0.42;
uniform float contrast : hint_range(0.8, 1.4) = 1.08;
uniform float time_scale : hint_range(0.2, 3.0) = 1.1;
/// 命中一闪：xy = 命中处 UV，z = 强度 0–1（逐帧衰减），w = 半径（贴图像素）
uniform vec4 hit = vec4(0.5, 0.5, 0.0, 16.0);
/// 焦痕：xy = UV，z = 半径（贴图像素），w = 深浅 0–1
uniform vec4 scars[6];
uniform int scar_n = 0;

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	vec4 peek = texture(TEXTURE, uv);
	float mx = max(peek.r, max(peek.g, peek.b));
	float sat = mx - min(peek.r, min(peek.g, peek.b));
	float cream = smoothstep(0.66, 0.84, mx) * (1.0 - smoothstep(0.16, 0.30, sat));
	float red = smoothstep(0.16, 0.30, peek.r - max(peek.g, peek.b));
	float sail_m = max(cream, red) * peek.a;
	vec2 flutter = wind_dir * (0.0040 * sail_flutter * wind_strength)
		* sin(TIME * time_scale * 5.2 + uv.y * 28.0 + uv.x * 11.0);
	flutter += wind_dir.yx * vec2(-1.0, 1.0) * (0.0018 * sail_flutter)
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

	// 焦痕：参差焦黑 + 一圈新茬浅木
	vec2 tp = uv / TEXTURE_PIXEL_SIZE;
	for (int i = 0; i < 6; i++) {
		if (i >= scar_n) {
			break;
		}
		vec4 s = scars[i];
		float d = distance(tp, s.xy / TEXTURE_PIXEL_SIZE);
		float n = vnoise(tp * 0.22 + float(i) * 7.3) - 0.5;
		float m = (1.0 - smoothstep(s.z * 0.35, s.z, d + n * s.z * 0.9)) * s.w;
		float ring = smoothstep(0.08, 0.35, m) * (1.0 - smoothstep(0.35, 0.8, m));
		c.rgb = mix(c.rgb, c.rgb * vec3(0.26, 0.22, 0.2), m * 0.88);
		c.rgb += vec3(0.5, 0.38, 0.24) * ring * 0.4 * s.w;
	}

	// 命中处一记炽橙
	float hd = distance(tp, hit.xy / TEXTURE_PIXEL_SIZE);
	float hf = hit.z * exp(-(hd * hd) / max(1.0, hit.w * hit.w));
	c.rgb = mix(c.rgb, vec3(1.0, 0.58, 0.24), clamp(hf, 0.0, 0.9));
	c.rgb += vec3(1.0, 0.85, 0.6) * pow(hf, 3.0) * 0.6;

	COLOR = vec4(clamp(c.rgb, 0.0, 1.0), c.a) * v_mod;
}
