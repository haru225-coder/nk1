// 过场镜头底图：Ken Burns 取景 + 调色 + 入场转场（墨染溶解 / 渐显）。
// 挂在铺满画布的 ColorRect 上；取景窗 view 由 CutscenePlayer 每帧算好（已保证不出界）。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D tex : source_color, hint_default_black, filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
// 取景窗：xy = 纹理 UV 左上，zw = 纹理 UV 宽高
uniform vec4 view = vec4(0.0, 0.0, 1.0, 1.0);
// 转场：mode 0 = 直接显示，1 = 墨染，2 = 渐显；reveal 0..1
uniform int mode = 0;
uniform float reveal = 1.0;
uniform vec2 ink_origin = vec2(0.5, 0.56);
uniform float aspect = 1.7778;
uniform float seed = 0.0;
// 调色（lift/gain/gamma + 饱和 + 对比 + 旧色调）
uniform vec3 g_lift = vec3(0.0);
uniform vec3 g_gain = vec3(1.0);
uniform float g_gamma = 1.0;
uniform float g_sat = 1.0;
uniform float g_contrast = 1.0;
uniform float g_sepia = 0.0;
uniform vec3 g_sepia_tint = vec3(1.08, 0.94, 0.74);
// 压暗到黑（退场）
uniform float dim = 0.0;
uniform vec3 ink_color : source_color = vec3(0.05, 0.043, 0.035);

vec3 grade(vec3 c) {
	c = g_lift + c * (g_gain - g_lift);
	c = pow(max(c, vec3(0.0)), vec3(1.0 / g_gamma));
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, g_sat);
	c = (c - 0.5) * g_contrast + 0.5;
	float l2 = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, clamp(vec3(l2) * g_sepia_tint, 0.0, 1.0), g_sepia);
	return clamp(c, 0.0, 1.0);
}

// 片元里重写 COLOR 会丢掉节点 modulate（含父节点链），先在顶点阶段存下
varying vec4 v_mod;
void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec2 uv_t = view.xy + UV * view.zw;
	vec3 col = grade(texture(tex, uv_t).rgb) * (1.0 - dim);
	float a = 1.0;
	if (mode == 1) {
		// 墨染：墨先行——一团团墨自 ink_origin 洇开、盖住旧画（墨分浓淡，前沿积墨）；
		// 新画随后从墨里浮出（边缘压一圈墨）。field 越小越早被染到。
		vec2 p = UV * vec2(aspect, 1.0);
		float n1 = texture(noise_tex, p * 0.55 + vec2(seed, seed * 0.37)).r;
		float n2 = texture(noise_tex, p * 1.9 + vec2(0.31 + seed, 0.73)).r;
		float n3 = texture(noise_tex, p * 6.3 + vec2(0.11, 0.57 + seed)).r;
		float d = length((UV - ink_origin) * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0));
		float field = d * 1.1 + (n1 - 0.5) * 0.6 + (n2 - 0.5) * 0.2 + (n3 - 0.5) * 0.07;
		float ri = clamp(reveal * 1.55, 0.0, 1.0);
		float rp = clamp((reveal - 0.22) / 0.78, 0.0, 1.0);
		float thr_i = mix(-0.4, 1.2, ri);
		float thr_p = mix(-0.4, 1.2, rp);
		float ink_cov = 1.0 - smoothstep(thr_i - 0.04, thr_i, field);
		float front = smoothstep(thr_i - 0.07, thr_i - 0.006, field) * ink_cov;
		float dens = mix(0.5, 0.88, smoothstep(0.3, 0.72, n2)) * mix(0.9, 1.0, n3) + front * 0.12;
		float pic = 1.0 - smoothstep(thr_p - 0.06, thr_p + 0.004, field);
		float rim = smoothstep(thr_p - 0.12, thr_p - 0.004, field) * pic;
		vec3 picc = mix(col, ink_color, rim * 0.72);
		float ia = ink_cov * clamp(dens, 0.0, 1.0) * (1.0 - pic);
		a = pic + ia;
		col = (picc * pic + ink_color * ia) / max(a, 0.0001);
	} else if (mode == 2) {
		a = reveal;
	}
	COLOR = vec4(col, a * v_mod.a);
}
