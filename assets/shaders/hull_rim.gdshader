shader_type canvas_item;
render_mode blend_mix;

/// 敌船轮廓（lane atmos）：挂在敌船 Sprite2D 下、show_behind_parent 的同图副本用。
/// 把精灵的 alpha 往外膨两圈：里圈墨、外圈朱，船身本体盖住里面，只露出船外那道边——深色船壳落在深水上也认得出。
/// 注意：不可把 TEXTURE 传进自定义函数（Godot canvas_item 会打 custom_samplers/tex_builtin 错），膨胀环在 fragment 里直接写。

uniform vec4 ink : source_color = vec4(0.05, 0.045, 0.04, 0.92);
uniform vec4 edge : source_color = vec4(0.78, 0.27, 0.17, 0.9);
/// 里圈 / 外圈半径（贴图像素）
uniform float r_ink = 3.0;
uniform float r_edge = 6.5;
uniform float pulse = 0.0;

void fragment() {
	float a_in = 0.0;
	float a_out = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;
		vec2 dir = vec2(cos(ang), sin(ang));
		a_in = max(a_in, texture(TEXTURE, UV + dir * TEXTURE_PIXEL_SIZE * r_ink).a);
		a_out = max(a_out, texture(TEXTURE, UV + dir * TEXTURE_PIXEL_SIZE * r_edge).a);
	}
	// 阈值抬高：船图外沿自带的软影（半透明）不算船身，免得轮廓跟着影子走
	a_in = smoothstep(0.55, 0.9, a_in);
	a_out = smoothstep(0.55, 0.9, a_out);
	vec4 e = edge;
	e.a *= 0.75 + 0.25 * pulse;
	vec4 c = mix(vec4(e.rgb, e.a * a_out), ink, a_in);
	c.a = max(e.a * a_out, ink.a * a_in);
	COLOR = vec4(c.rgb, c.a * COLOR.a);
}
