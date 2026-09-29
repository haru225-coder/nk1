shader_type canvas_item;
render_mode blend_mix;

/// 敌船轮廓（lane atmos）：挂在敌船 Sprite2D 下、show_behind_parent 的同图副本用。
/// 把精灵的 alpha 往外膨两圈：里圈墨、外圈朱，船身本体盖住里面，只露出船外那道边——深色船壳落在深水上也认得出。

uniform vec4 ink : source_color = vec4(0.05, 0.045, 0.04, 0.92);
uniform vec4 edge : source_color = vec4(0.86, 0.35, 0.21, 0.95);
/// 里圈 / 外圈半径（贴图像素）
uniform float r_ink = 2.5;
uniform float r_edge = 7.5;
/// 0–1：敌船进了可接舷的够距时 SeaAtmosphere 让它一明一暗（与顶匾「舷边可接」同一判据）
uniform float pulse = 0.0;

void fragment() {
	// 膨胀：一圈 16 个方向取 alpha 最大值（TEXTURE 不能当实参传进自定义函数，就地展开）
	float a_in = 0.0;
	float a_out = 0.0;
	for (int i = 0; i < 16; i++) {
		float ang = float(i) * 0.3926991;
		vec2 o = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE;
		a_in = max(a_in, texture(TEXTURE, UV + o * r_ink).a);
		a_out = max(a_out, texture(TEXTURE, UV + o * r_edge).a);
	}
	// 阈值抬高：船图外沿自带的软影（半透明）不算船身，免得轮廓跟着影子走
	a_in = smoothstep(0.55, 0.9, a_in);
	a_out = smoothstep(0.55, 0.9, a_out);
	vec4 e = edge;
	e.rgb = mix(e.rgb, vec3(1.0, 0.78, 0.45), pulse * 0.45);
	e.a = min(1.0, e.a * (0.8 + 0.4 * pulse));
	vec4 c = mix(vec4(e.rgb, e.a * a_out), ink, a_in);
	c.a = max(e.a * a_out, ink.a * a_in);
	COLOR = vec4(c.rgb, c.a * COLOR.a);
}
