// 抵港绢带：旧绢底 + 经纬纹 + 上下泥金细线 + 右端毛边渐隐。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D weave_tex : filter_linear, repeat_enable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec2 band_size = vec2(620.0, 104.0);
uniform vec3 silk : source_color = vec3(0.804, 0.722, 0.561);
uniform vec3 silk_dark : source_color = vec3(0.64, 0.54, 0.38);
uniform vec3 gold : source_color = vec3(0.788, 0.631, 0.29);
uniform vec3 indigo : source_color = vec3(0.122, 0.227, 0.302);
uniform float fray_start = 0.72;
// 左端毛边（挂签式两端都毛；0 = 左端直接出画，不做毛边）
uniform float fray_left = 0.0;
uniform float alpha = 1.0;
uniform float seed = 0.0;

// 片元里重写 COLOR 会丢掉节点 modulate（含父节点链），先在顶点阶段存下
varying vec4 v_mod;
void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec2 px = UV * band_size;
	float w = texture(weave_tex, px / 96.0).r - 0.5;
	float n = texture(noise_tex, px / 420.0 + vec2(seed, 0.3)).r;
	float nf = texture(noise_tex, vec2(UV.y * 3.1, seed * 0.7) + vec2(0.0, px.x / 900.0)).r;
	// 竖向：中间亮，上下略暗，像绢被卷过
	float vy = abs(UV.y - 0.5) * 2.0;
	vec3 c = mix(silk, silk_dark, smoothstep(0.35, 1.0, vy) * 0.55 + (n - 0.5) * 0.35);
	c += w * 0.07;
	// 泥金细线：距上下边 9% 处各一道，细线也有断续
	float line_y = min(abs(UV.y - 0.1), abs(UV.y - 0.9)) * band_size.y;
	float gl = (1.0 - smoothstep(0.55, 1.45, line_y)) * smoothstep(0.25, 0.5, nf + 0.2);
	c = mix(c, gold, gl * 0.85);
	// 上下缘是撕开的绢边，不是尺子裁的直边：沿边走向的两层噪声把边缘咬进 0–5px（先算，压边随咬口走）
	float ey = min(UV.y, 1.0 - UV.y) * band_size.y;
	float bite = texture(noise_tex, vec2(px.x / 70.0, seed + (UV.y < 0.5 ? 0.11 : 0.63))).r * 3.6
		+ texture(noise_tex, vec2(px.x / 13.0, seed + (UV.y < 0.5 ? 0.37 : 0.81))).r * 1.6;
	// 上下边沿的焦墨压边（原为靛青），随咬口起伏
	float edge = 1.0 - smoothstep(0.0, 3.0, ey - bite);
	c = mix(c, indigo, edge * 0.8);
	// 右端毛边：噪声扰动的渐隐阈值
	float fray = fray_start + (texture(noise_tex, vec2(UV.y * 1.7, seed)).r - 0.5) * 0.12
		+ (texture(noise_tex, vec2(UV.y * 11.0, seed + 0.5)).r - 0.5) * 0.05;
	float a = 1.0 - smoothstep(fray, fray + 0.16, UV.x);
	if (fray_left > 0.0) {
		float fl = fray_left + (texture(noise_tex, vec2(UV.y * 1.9, seed + 0.27)).r - 0.5) * 0.10;
		a *= smoothstep(fl - 0.12, fl, UV.x);
	}
	a *= smoothstep(bite - 0.6, bite + 1.1, ey);
	COLOR = vec4(c, a * alpha * v_mod.a);
}
