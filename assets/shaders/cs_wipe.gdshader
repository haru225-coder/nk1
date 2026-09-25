// 贴图由左至右「写」出来：揭开的前沿参差（两级噪声，按像素取样），刚写到的地方带一线泥金湿光。
// 开场结尾的游戏名 logo 用（CutscenePlayer.LogoCaption）。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float progress = 0.0;
uniform float soft = 0.09;
uniform float seed = 0.0;
uniform vec2 rect_px = vec2(704.0, 191.0);
uniform float sheen = 0.35;

// 片元里重写 COLOR 会丢掉节点 modulate（含父节点链），先在顶点阶段存下
varying vec4 v_mod;
void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 p = UV * rect_px;
	float n1 = texture(noise_tex, p / 520.0 + vec2(seed, 0.31)).r - 0.5;
	float n2 = texture(noise_tex, p / 180.0 + vec2(0.57, seed)).r - 0.5;
	// 前沿略向右下斜：像一笔横扫
	float x = UV.x + (UV.y - 0.5) * 0.05 + n1 * 0.07 + n2 * 0.025;
	float f = mix(-soft - 0.08, 1.0 + soft + 0.08, progress);
	float a = 1.0 - smoothstep(f - soft, f, x);
	float wet = a * (1.0 - smoothstep(0.0, soft * 1.6, f - x));
	vec3 rgb = c.rgb * (1.0 + sheen * wet);
	COLOR = vec4(rgb * v_mod.rgb, c.a * a * v_mod.a);
}
