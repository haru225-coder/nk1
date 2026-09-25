shader_type canvas_item;
// 海图/舆图底图着色器。底图纹理是分层设色+晕渲的舆图；mapdata 提供 R 陆高 / G 海深 / B 离岸距离 / A 陆地掩膜。
// mode 0 = 海图（海为主角，陆压向纸色）；mode 1 = 舆图（陆为主角，海压淡）。
// 水面动画与纸纹全部程序化生成，不依赖第二张大图。

uniform sampler2D mapdata : filter_linear, repeat_disable;
uniform float mode : hint_range(0.0, 1.0) = 0.0;
uniform vec4 paper : source_color = vec4(0.894, 0.827, 0.682, 1.0);
uniform vec4 ink : source_color = vec4(0.165, 0.141, 0.114, 1.0);
uniform vec4 sea_tint : source_color = vec4(0.208, 0.376, 0.498, 1.0);
uniform vec4 foam : source_color = vec4(0.949, 0.922, 0.855, 1.0);
uniform float wave_strength : hint_range(0.0, 0.3) = 0.09;
uniform float contour_strength : hint_range(0.0, 0.5) = 0.13;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.045;
uniform float zoom = 1.0;           // 摄像机缩放，控制波纹密度
uniform vec2 canvas_px = vec2(4096.0, 4318.0);

float hash21(vec2 p) {
	// 先取小数再散列：画布坐标到 4000 多时 float 掉精度，纸纹会结成条纹
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 d = texture(mapdata, UV);
	float land = d.a;
	float depth = d.g;      // 0 岸边 → 1 深渊
	float coastd = d.b;     // 海侧离岸距离 0..1（200 px 归一）
	vec2 wp = UV * canvas_px;   // 底图像素坐标，纹样与缩放无关

	// ── 海 ──
	// 大尺度涌浪：随深度变慢变大；小尺度碎波：只在近岸。缩得远时波纹按 zoom 衰减，否则整片深海叠成斑驳。
	float t = TIME;
	float zoom_k = smoothstep(0.30, 1.1, zoom);
	float swell = fbm(wp * 0.006 + vec2(t * 0.02, -t * 0.015));
	float swell2 = fbm(wp * 0.011 - vec2(t * 0.017, t * 0.02) + 31.0);
	float ripple = ((swell - 0.5) * 0.6 + (swell2 - 0.5) * 0.4) * zoom_k;
	// 近岸白浪：与岸平行的柔和条纹，缓慢向岸推进
	float band = exp(-coastd * 22.0);
	float foam_line = sin(coastd * 320.0 - t * 1.4 + fbm(wp * 0.03) * 3.0);
	float foam_m = smoothstep(0.55, 0.95, foam_line) * band * 0.5 * zoom_k;
	// 等深线：海图模式下的淡线，舆图模式收掉
	float cd = abs(fract(depth * 7.0) - 0.5);
	float contour = (1.0 - smoothstep(0.0, 0.035, cd)) * contour_strength * (1.0 - mode) * step(0.02, depth);

	vec3 sea = base.rgb;
	sea += ripple * wave_strength * vec3(0.55, 0.70, 0.85);
	sea = mix(sea, foam.rgb, foam_m * 0.7);
	sea = mix(sea, ink.rgb, contour * 0.55);
	// 海图模式：石青压一点纸色，少一分数码蓝；舆图模式：海压向纸色的一半
	vec3 sea_chart = mix(sea * vec3(0.94, 0.96, 0.97), paper.rgb, 0.14);
	vec3 sea_terrain = mix(sea, paper.rgb * vec3(0.86, 0.92, 0.98), 0.42);
	sea = mix(sea_chart, sea_terrain, mode);

	// ── 陆 ──
	vec3 lnd = base.rgb;
	// 海图模式：陆地压向纸绢色，但山影要留得住；舆图模式：全彩
	vec3 lnd_chart = mix(lnd, paper.rgb, 0.36);
	lnd = mix(lnd_chart, lnd, mode);

	vec3 col = mix(sea, lnd, land);

	// ── 纸绢颗粒（细）与纤维（长） ──
	float g = hash21(floor(wp * 0.9)) - 0.5;
	float fiber = vnoise(vec2(wp.x * 0.02, wp.y * 0.6)) - 0.5;
	col += (g * 0.6 + fiber * 0.4) * grain_strength;
	// 淡淡的大块污渍（远景更淡，免得和涌浪一起结成斑）
	float stain = fbm(wp * 0.0015 + 3.7) - 0.5;
	col *= 1.0 + stain * (0.04 + 0.05 * zoom_k);

	COLOR = vec4(col, 1.0) * COLOR.a;
}
