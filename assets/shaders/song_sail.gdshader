shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 竹席硬篷：顶点色 R 是竹条间鼓腹的明暗，色相由 sail_color 定。
// 席面是一条条横篾，篾里还有纵纤维，竖线压过去。不是方格布，也不是西方横帆。
// 己方牙白，敌船绛红。同一张网格。底色保持亮，缝只压一截，避免整面发黑。
uniform vec4 sail_color : source_color = vec4(0.94, 0.88, 0.74, 1.0);

void fragment() {
	float shade = clamp(COLOR.r, 0.25, 1.0);
	vec3 base = sail_color.rgb * (0.62 + 0.55 * shade);

	float slat_f = UV.y * 64.0;
	float slat_i = floor(slat_f);
	float sy = fract(slat_f);
	float tone = 0.90 + 0.10 * fract(sin(slat_i * 17.13) * 43758.5);
	float body = smoothstep(0.0, 0.04, sy) * smoothstep(1.0, 0.94, sy);
	float fiber = 0.94 + 0.06 * fract(sin(UV.x * 90.0 + slat_i * 3.7) * 12543.7);
	float grain = 0.96 + 0.04 * sin(UV.x * 180.0 + sy * 14.0 + slat_i);
	float cord_f = UV.x * 9.0;
	float cx = abs(fract(cord_f) - 0.5);
	float cord = smoothstep(0.06, 0.0, cx - 0.42);
	float over = mod(slat_i + floor(cord_f), 2.0);
	float bite = cord * (0.03 + 0.03 * over);
	base *= tone * fiber * grain;
	base *= mix(0.97, 1.0, body);
	base *= 1.0 - bite;
	float sheen = smoothstep(0.18, 0.40, sy) * smoothstep(0.72, 0.52, sy) * body;
	base += sail_color.rgb * sheen * 0.05 * shade;

	float bat = abs(fract(UV.y * 9.0 + 0.02) - 0.5);
	float ex = min(min(abs(UV.x - 0.34), abs(UV.x - 0.58)), abs(UV.x - 0.82));
	float eye = smoothstep(0.028, 0.006, length(vec2(ex * 2.8, bat * 6.0)));
	base *= 1.0 - eye * 0.28;

	ALBEDO = base;
	ROUGHNESS = mix(0.82, 0.55, shade * body);
	SPECULAR = 0.12;
}
