// 活背景：给任意 TextureRect 用（LivingBackdrop.attach）。
// 呼吸推拉只放大不缩小，且平移不超出放大留出的余量 → 永不露边。
// shimmer > 0 时只扰动偏蓝 / 偏青的像素（海面），陆地不动。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D grain_tex : filter_nearest, repeat_enable;
uniform vec2 rect_size = vec2(1280.0, 720.0);
// 取景区半宽高（纹理 UV）：STRETCH_KEEP_ASPECT_COVERED 时小于 0.5
uniform vec2 region = vec2(0.5, 0.5);
uniform float breath = 0.03;
uniform float breath_base = 0.012;
uniform float period = 44.0;
uniform float pan = 0.6;
uniform float phase = 0.0;
// 时间由 LivingBackdrop 节点每帧写入（不用内建 TIME：确定、可复现）
uniform float time_s = 0.0;
uniform float vignette = 0.32;
uniform float grain = 0.035;
uniform float shimmer = 0.0;
uniform vec3 g_lift = vec3(0.0);
uniform vec3 g_gain = vec3(1.0);
uniform float g_gamma = 1.0;
uniform float g_sat = 1.0;
uniform float g_contrast = 1.0;
uniform float g_sepia = 0.0;
uniform vec3 g_sepia_tint = vec3(1.08, 0.94, 0.74);

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
	float t = time_s + phase;
	float w = 6.2831853 * t / max(period, 1.0);
	float s = 1.0 + breath_base + breath * (0.5 - 0.5 * cos(w));
	vec2 margin = region * (1.0 - 1.0 / s);
	vec2 drift = vec2(sin(w * 0.73 + 0.4), sin(w * 0.59 + 2.1)) * margin * pan;
	vec2 uv = 0.5 + (UV - 0.5) / s + drift;
	vec4 base = texture(TEXTURE, uv);
	vec3 c = base.rgb;
	if (shimmer > 0.0) {
		float blue = c.b - max(c.r, c.g * 0.9);
		float cyan = min(c.g, c.b) - c.r * 1.05;
		float sea = smoothstep(0.015, 0.1, max(blue, cyan));
		vec2 np = uv * vec2(rect_size.x / rect_size.y, 1.0);
		float n1 = texture(noise_tex, np * 2.4 + vec2(t * 0.011, t * 0.004)).r;
		float n2 = texture(noise_tex, np * 3.1 + vec2(-t * 0.007, t * 0.009) + 0.5).r;
		vec2 off = vec2(n1 - 0.5, n2 - 0.5) * 0.0042 * shimmer * sea;
		vec3 c2 = texture(TEXTURE, uv + off).rgb;
		float glint = pow(clamp(n1 * n2 * 2.2, 0.0, 1.0), 7.0) * 0.1 * shimmer * sea;
		c = mix(c, c2, sea) + vec3(0.9, 0.95, 1.0) * glint;
	}
	c = grade(c);
	vec2 q = (UV - 0.5) * 2.0 * (0.5 / max(region, vec2(0.001)));
	q *= vec2(rect_size.x / rect_size.y, 1.0) * 0.5;
	float vg = smoothstep(0.3, 1.05, length(q * vec2(0.8, 1.0))) * vignette;
	c *= 1.0 - vg;
	float fr = floor(time_s * 24.0);
	vec2 go = fract(vec2(sin(fr * 12.9898) * 43758.5453, sin(fr * 78.233 + 1.3) * 24634.6345));
	vec2 gp = (0.5 + (UV - 0.5) * (0.5 / max(region, vec2(0.001)))) * rect_size / 256.0;
	c += (texture(grain_tex, gp + go).r - 0.5) * 2.0 * grain;
	COLOR = vec4(c * v_mod.rgb, base.a * v_mod.a);
}
