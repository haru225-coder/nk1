shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 占城软帆：横矩形一整块布。中间鼓腹亮，正中一道竖缝。
// 没有横竹，也不分成好几幅。顶点色跟着鼓腹走，缝线用 UV 画。
// 默认是战舟近景已经能看见的那一档。货船帆在画面里更小，
// 截图时把鼓腹和缝宽调高，18° 才不会看成一块平板。
uniform vec4 sail_color : source_color = vec4(0.90, 0.74, 0.46, 1.0);
uniform float lobe_gain : hint_range(0.0, 1.6) = 0.48;
uniform float crease_width : hint_range(0.008, 0.12) = 0.045;
uniform float crease_dark : hint_range(0.0, 1.0) = 0.16;
uniform float stitch_width : hint_range(0.002, 0.06) = 0.007;
uniform float seam_scale : hint_range(0.4, 2.0) = 1.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float lobe = pow(max(sin(PI * u), 0.0), 0.82) * pow(max(sin(PI * v), 0.0), 0.75);
	float lit = 0.62 + lobe_gain * lobe;
	vec3 base = sail_color.rgb * lit;
	float vc = clamp(COLOR.r, 0.2, 1.0);
	base *= 0.78 + 0.28 * vc;
	// 一道竖缝：折影加一条缝线。不是横竹。
	float seam_d = abs(u - 0.5);
	float crease = 1.0 - smoothstep(0.0, crease_width, seam_d);
	float stitch = 1.0 - smoothstep(0.0, stitch_width, seam_d);
	base *= 1.0 - crease * crease_dark;
	float dash = smoothstep(0.18, 0.55, abs(fract(v * 38.0) - 0.5));
	vec3 thread = sail_color.rgb * vec3(0.34, 0.22, 0.12);
	base = mix(base, thread, stitch * (0.62 + 0.28 * dash) * seam_scale);
	float hem_u = smoothstep(0.030, 0.0, min(u, 1.0 - u));
	float hem_v = smoothstep(0.048, 0.0, min(v, 1.0 - v));
	base *= 1.0 - max(hem_u, hem_v) * 0.22;
	float weave_u = smoothstep(0.008, 0.0, abs(fract(u * 46.0) - 0.5) - 0.492);
	float weave_v = smoothstep(0.008, 0.0, abs(fract(v * 34.0) - 0.5) - 0.492);
	base *= 1.0 - weave_u * 0.04 - weave_v * 0.028;
	ALBEDO = base;
	ROUGHNESS = 0.90 - 0.10 * lobe;
	SPECULAR = 0.04;
}
