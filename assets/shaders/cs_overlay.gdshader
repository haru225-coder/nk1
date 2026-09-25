// 常驻画面层：暗角 + 胶片颗粒（CutscenePlayer / ChapterCard 共用）。
// 普通混合近似：暗角是黑色 alpha；颗粒正值提亮、负值压暗。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D grain_tex : filter_nearest, repeat_enable;
uniform vec2 canvas_size = vec2(1280.0, 720.0);
uniform float vignette = 0.42;
uniform float vignette_soft = 0.62;
uniform float grain = 0.045;
uniform float fps = 24.0;
// 时间由脚本每帧写入（不用内建 TIME：确定、可暂停、Movie Maker 截帧可复现）
uniform float time_s = 0.0;
uniform vec3 shadow_tint : source_color = vec3(0.05, 0.035, 0.02);

// 片元里重写 COLOR 会丢掉节点 modulate（含父节点链），先在顶点阶段存下
varying vec4 v_mod;
void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec2 q = (UV - 0.5) * vec2(canvas_size.x / canvas_size.y, 1.0);
	float r = length(q * vec2(0.82, 1.0));
	float v = smoothstep(vignette_soft * 0.45, vignette_soft * 1.25, r) * vignette;
	float fr = floor(time_s * fps);
	vec2 off = fract(vec2(sin(fr * 12.9898) * 43758.5453, sin(fr * 78.233 + 1.3) * 24634.6345));
	float g = (texture(grain_tex, UV * canvas_size / 256.0 + off).r - 0.5) * 2.0 * grain;
	float a = clamp(v + abs(g), 0.0, 1.0);
	vec3 c = g > 0.0 ? vec3(1.0, 0.97, 0.9) * (g / max(a, 0.0001)) : shadow_tint;
	COLOR = vec4(c, a * v_mod.a);
}
