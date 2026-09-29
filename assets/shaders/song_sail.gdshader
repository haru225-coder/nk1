shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 竹席硬篷。横竹是网格上的竹条，这里不再画一道道横肋。
// 顶点色 R 是竹间腹冠的明暗。色相由 sail_color 定：己方牙白，敌船绛红。
// 细篾和纵纤维只留一点，避免席面又变成一排架子。
uniform vec4 sail_color : source_color = vec4(0.94, 0.88, 0.74, 1.0);

void fragment() {
	float shade = clamp(COLOR.r, 0.25, 1.0);
	vec3 base = sail_color.rgb * (0.50 + 0.72 * shade);

	float slat_f = UV.y * 40.0;
	float slat_i = floor(slat_f);
	float sy = fract(slat_f);
	float tone = 0.97 + 0.03 * fract(sin(slat_i * 17.13) * 43758.5);
	float fiber = 0.97 + 0.03 * fract(sin(UV.x * 80.0 + slat_i * 2.1) * 12543.7);
	float grain = 0.985 + 0.015 * sin(UV.x * 120.0 + sy * 6.0);
	float cord_f = UV.x * 8.0;
	float cx = abs(fract(cord_f) - 0.5);
	float cord = smoothstep(0.05, 0.0, cx - 0.44);
	base *= tone * fiber * grain;
	base *= 1.0 - cord * 0.035;

	ALBEDO = base;
	ROUGHNESS = mix(0.84, 0.58, shade);
	SPECULAR = 0.10;
}
