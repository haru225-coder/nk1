// 章节卡：油画在宣纸上以墨晕形状铺开。
// 揭开区 = 画（略做旧、贴纸面），边缘积墨，外圈一层淡墨水痕。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D tex : source_color, hint_default_black, filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec4 view = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 canvas_size = vec2(1280.0, 720.0);
uniform vec2 center = vec2(0.36, 0.5);
uniform float radius = 0.52;
uniform float progress = 0.0;
uniform float alpha = 1.0;
uniform float seed = 0.0;
uniform vec3 paper : source_color = vec3(0.914, 0.863, 0.753);
uniform vec3 ink : source_color = vec3(0.102, 0.086, 0.071);

// 片元里重写 COLOR 会丢掉节点 modulate（含父节点链），先在顶点阶段存下
varying vec4 v_mod;
void vertex() {
	v_mod = COLOR;
}

void fragment() {
	float asp = canvas_size.x / canvas_size.y;
	vec2 p = (UV - center) * vec2(asp, 1.0);
	float d = length(p * vec2(0.86, 1.0)) / radius;
	vec2 np = UV * vec2(asp, 1.0);
	float n1 = texture(noise_tex, np * 0.62 + vec2(seed, 0.17)).r;
	float n2 = texture(noise_tex, np * 2.3 + vec2(0.41, seed)).r;
	float n3 = texture(noise_tex, np * 7.7 + vec2(seed * 0.5, 0.83)).r;
	// 噪声只在外圈起作用：核心区衰减到三成，免得窗里冒出一块块纸色孤岛（第 1 轮评审 M7）
	float nk = mix(0.3, 1.0, smoothstep(0.55, 0.95, d));
	float field = d + ((n1 - 0.5) * 0.62 + (n2 - 0.5) * 0.22 + (n3 - 0.5) * 0.07) * nk;
	float thr = progress;
	float paint = 1.0 - smoothstep(thr - 0.04, thr + 0.008, field);
	// 积墨：边缘一圈放宽到 thr-0.18，浓淡随细噪声起伏（不是一道均匀的焦边）；越靠边越浓，往深墨过渡
	float rim = smoothstep(thr - 0.18, thr - 0.005, field) * paint * mix(0.55, 1.0, smoothstep(0.3, 0.7, n3));
	// 画与纸之间紧贴一道深墨（画缘外 0.035 以内）。不乘 (1-paint)：画淡出的那一段 alpha 由这道墨托住，
	// 否则画缘 paint≈0.5 处整体只剩半透明，纸色从底下透上来，成一圈发白的剪纸亮边（第 1 轮评审 M7）
	float seam = 1.0 - smoothstep(thr - 0.005, thr + 0.035, field);
	float wash = (1.0 - smoothstep(thr, thr + 0.06 + 0.22 * progress, field)) * (1.0 - paint);

	vec3 c = texture(tex, view.xy + UV * view.zw).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, vec3(l) * vec3(1.06, 0.95, 0.78), 0.28);      // 略做旧
	c = mix(c, c * paper * 1.12, 0.4);                         // 贴着纸面
	c = mix(c, ink, rim * 0.7);                                // 边缘积墨
	float gran = smoothstep(0.35, 0.75, n3);
	float wash_a = wash * (0.18 + 0.22 * gran);
	float seam_a = seam * mix(0.72, 0.9, gran);
	float a = max(paint, max(wash_a, seam_a));
	vec3 outc = mix(ink, c, paint / max(a, 0.0001));
	COLOR = vec4(outc, a * alpha * v_mod.a);
}
