shader_type canvas_item;
render_mode blend_mix, unshaded;

/// 宋元近海写意：世界坐标涌浪带 + 细碎浪花。不采样旧贴图（避免大块脏高光）。

uniform float wave_speed : hint_range(0.05, 2.5) = 0.35;
uniform float swell_scale : hint_range(0.0002, 0.02) = 0.0036;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.55;
uniform float glint_amount : hint_range(0.0, 1.0) = 0.2;
uniform float wind_angle : hint_range(0.0, 6.28318) = 0.7;
uniform vec4 deep_color : source_color = vec4(0.045, 0.13, 0.24, 1.0);
uniform vec4 mid_color : source_color = vec4(0.08, 0.28, 0.38, 1.0);
uniform vec4 shoal_color : source_color = vec4(0.16, 0.44, 0.46, 1.0);
uniform vec4 foam_color : source_color = vec4(0.80, 0.89, 0.91, 1.0);
uniform vec4 glint_color : source_color = vec4(0.93, 0.90, 0.76, 1.0);

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.08 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 wdir = vec2(cos(wind_angle), sin(wind_angle));
	vec2 wperp = vec2(-wdir.y, wdir.x);

	// TextureRect 平铺时 UV 每片 0–1 最稳；再叠一点世界坐标破接缝
	vec2 uv = UV * 14.0 + v_world * (swell_scale * 0.35);

	vec2 swell_uv = uv + wdir * t * 0.25 + wperp * t * 0.06;
	float swell = fbm(swell_uv);
	float swell2 = fbm(swell_uv * 1.9 + vec2(3.1, -2.4) - wdir * t * 0.14);
	float detail = fbm(uv * 5.0 - wdir * t * 0.45);

	float h = swell * 0.55 + swell2 * 0.45;
	float band = smoothstep(0.30, 0.70, h);
	vec3 base = mix(deep_color.rgb, mid_color.rgb, clamp(h * 0.95 + detail * 0.12, 0.0, 1.0));
	base = mix(base, shoal_color.rgb, band * 0.58);

	// 沿风向的细长浪纹
	float streaks = fbm(vec2(dot(uv, wperp) * 3.2, dot(uv, wdir) * 0.7 - t * 0.3));
	base = mix(base, shoal_color.rgb * 1.05, smoothstep(0.55, 0.85, streaks) * 0.22);

	float foam_n = fbm(uv * 11.0 - wdir * t * 1.0);
	float ridge = 1.0 - abs(h - 0.52) * 3.4;
	float foam = smoothstep(0.58, 0.92, foam_n) * clamp(ridge, 0.0, 1.0) * foam_amount;
	base = mix(base, foam_color.rgb, foam * 0.38);

	float g = pow(clamp(swell2 * detail, 0.0, 1.0), 11.0) * glint_amount;
	g *= smoothstep(0.42, 0.82, band);
	base += glint_color.rgb * g * 0.35;

	float breathe = 0.012 * sin(t * 0.55 + h * 2.8);
	base += vec3(breathe * 0.5, breathe * 0.85, breathe);

	COLOR = vec4(clamp(base, 0.0, 1.0), 1.0);
}
