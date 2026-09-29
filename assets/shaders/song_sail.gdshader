shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 竹席硬篷：顶点色 R 是鼓腹与竹条阴影，色相由 sail_color 定。
// UV 只织细席纹，竹条本身是网格。己方牙白，敌船绛红。同一张网格。
uniform vec4 sail_color : source_color = vec4(0.94, 0.88, 0.74, 1.0);

void fragment() {
	float shade = clamp(COLOR.r, 0.12, 1.0);
	vec3 base = sail_color.rgb * (0.36 + 0.80 * shade);
	float warp = smoothstep(0.045, 0.0, abs(fract(UV.y * 54.0) - 0.5) - 0.455);
	float weft = smoothstep(0.05, 0.0, abs(fract(UV.x * 26.0) - 0.5) - 0.45);
	base *= 1.0 - warp * 0.11 - weft * 0.06;
	ALBEDO = base;
	ROUGHNESS = 0.68;
	SPECULAR = 0.15;
}
