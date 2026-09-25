// 朱印：把 SubViewport 里画好的印面蒙版（白 = 印泥，黑 = 空）着成印泥色。
// · 印边：按到矩形边的屏幕像素距离 + 两级噪声做阈值（颗粒 + 缓慢起伏），外加两三口按 seed 落位的缺角——不是笔直的矩形。
// · 字口：蒙版轻模糊后用噪声阈值，刻痕边缘有残破。
// · 印泥：取 UI 线空白印底（seal_blank.png）内部的浓淡与漏印白点；缺图时用噪声团块兜底。
// 所有噪声都按屏幕像素取样（1 纹素 ≲ 1.5 像素），不会出现方块状的「迷彩」走样。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D blank_tex : source_color, filter_linear, repeat_disable;
uniform bool has_blank = false;
// 取样窗：xy = 左上 UV，zw = 宽高（负值 = 翻转）
uniform vec4 blank_win = vec4(0.05, 0.05, 0.5, 0.5);
uniform vec2 seal_px = vec2(72.0, 72.0);
uniform vec3 ink : source_color = vec3(0.69, 0.188, 0.165);
uniform vec3 hollow_color : source_color = vec3(0.914, 0.863, 0.753);
uniform float hollow_alpha = 0.0;
uniform float density = 1.0;
uniform float seed = 0.0;
// 蒙版模糊半径（蒙版像素）与字口阈值（< 0.5 笔画更粗）
uniform float blur = 1.3;
uniform float fill = 0.5;
// 印边内缩（像素）与起伏幅度
uniform float edge_in = 3.2;
uniform float edge_wobble = 1.5;

// 片元里重写 COLOR 会丢掉节点 modulate（含父节点链），先在顶点阶段存下
varying vec4 v_mod;
void vertex() {
	v_mod = COLOR;
}

float nz(vec2 px_pos, float scale, vec2 off) {
	return texture(noise_tex, px_pos / scale + off).r - 0.5;
}

void fragment() {
	vec2 p = UV * seal_px;
	float s = min(seal_px.x, seal_px.y);
	// ── 印边 ──
	vec2 e = min(p, seal_px - p);
	float d = min(e.x, e.y);
	float rc = 3.0;
	if (e.x < rc && e.y < rc) {
		d = rc - length(vec2(rc) - e);
	}
	float wob = nz(p, 190.0, vec2(seed * 3.1, 0.17)) * 1.25 + nz(p, 620.0, vec2(0.61, seed * 2.3)) * 1.6;
	float body = smoothstep(edge_in - 0.8, edge_in + 0.5, d + wob * edge_wobble * 1.4);
	// 缺角：三口，按 seed 落在不同边上，口沿参差
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float side = floor(fract(seed * 13.7 + fi * 0.618) * 4.0);
		float t = 0.14 + 0.72 * fract(seed * 29.3 + fi * 0.413);
		vec2 c = vec2(t * seal_px.x, 0.0);
		if (side > 2.5) {
			c = vec2(0.0, t * seal_px.y);
		} else if (side > 1.5) {
			c = vec2(t * seal_px.x, seal_px.y);
		} else if (side > 0.5) {
			c = vec2(seal_px.x, t * seal_px.y);
		}
		float rad = edge_in + s * (0.028 + 0.036 * fract(seed * 17.9 + fi * 0.731));
		float dn = length(p - c) + nz(p, 170.0, vec2(fi * 0.37, seed)) * rad * 0.9;
		body *= smoothstep(rad * 0.85, rad * 1.2, dn);
	}
	// ── 印泥 ──
	vec3 col = ink;
	float pa = 1.0;
	if (has_blank) {
		vec4 b = texture(blank_tex, blank_win.xy + UV * blank_win.zw);
		col = b.rgb;
		pa = b.a;
	} else {
		float clump = nz(p, 420.0, vec2(seed, 0.29));
		float grain = nz(p, 170.0, vec2(0.13, seed * 1.9));
		col = ink * (0.97 + 0.12 * clump);
		pa = clamp(0.93 + 0.14 * clump + 0.1 * grain, 0.0, 1.0);
		pa *= 1.0 - 0.85 * smoothstep(0.34, 0.42, nz(p, 260.0, vec2(0.71, seed)));
	}
	// ── 字口 ──
	vec2 tp = TEXTURE_PIXEL_SIZE * blur;
	float m = texture(TEXTURE, UV).r * 0.4;
	m += texture(TEXTURE, UV + vec2(tp.x, 0.0)).r * 0.15;
	m += texture(TEXTURE, UV - vec2(tp.x, 0.0)).r * 0.15;
	m += texture(TEXTURE, UV + vec2(0.0, tp.y)).r * 0.15;
	m += texture(TEXTURE, UV - vec2(0.0, tp.y)).r * 0.15;
	// 过渡宽度跟屏幕像素走（fwidth）：原先固定 ±0.08 叠上噪声几乎是二值，1:1 看得到阶梯（第 2 轮美术 minor 6）
	float v = m + nz(p, 170.0, vec2(0.37, seed)) * 0.3 + nz(p, 480.0, vec2(seed, 0.61)) * 0.18;
	float aa = max(fwidth(v) * 1.2, 0.04);
	float g = smoothstep(fill - aa, fill + aa, v);
	float ink_a = body * g * pa * density;
	float hol = body * (1.0 - g) * hollow_alpha;
	float oa = max(ink_a, hol);
	vec3 oc = mix(hollow_color, col, ink_a / max(oa, 0.0001));
	COLOR = vec4(oc, oa * v_mod.a);
}
