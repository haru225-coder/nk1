shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 竹席硬篷：顶点色 R 是竹条间鼓腹的明暗，色相由 sail_color 定。
// 席面是一条条横篾，竖线压过去，不是方格布，也不是西方横帆。
// 己方牙白，敌船绛红。同一张网格。
uniform vec4 sail_color : source_color = vec4(0.94, 0.88, 0.74, 1.0);

void fragment() {
	float shade = clamp(COLOR.r, 0.06, 1.0);
	vec3 base = sail_color.rgb * (0.24 + 0.98 * shade);

	float slat_f = UV.y * 58.0;
	float slat_i = floor(slat_f);
	float sy = fract(slat_f);
	float tone = 0.90 + 0.10 * fract(sin(slat_i * 17.13) * 43758.5);
	float body = smoothstep(0.0, 0.09, sy) * smoothstep(1.0, 0.90, sy);
	float cord_f = UV.x * 10.0;
	float cx = abs(fract(cord_f) - 0.5);
	float cord = smoothstep(0.08, 0.0, cx - 0.38);
	float over = mod(slat_i + floor(cord_f), 2.0);
	float bite = cord * (0.07 + 0.12 * over);
	base *= tone;
	base *= mix(0.58, 1.0, body);
	base *= 1.0 - bite;
	float sheen = smoothstep(0.18, 0.42, sy) * smoothstep(0.72, 0.50, sy) * body;
	base += sail_color.rgb * sheen * 0.06 * shade;

	ALBEDO = base;
	ROUGHNESS = mix(0.84, 0.56, shade * body);
	SPECULAR = 0.12;
}
