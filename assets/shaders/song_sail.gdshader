shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 竹席硬篷：顶点色的 R 是明暗（鼓面亮、竹条下暗），色相由 sail_color 定。
// 己方牙白，敌船绛红。同一张网格。
uniform vec4 sail_color : source_color = vec4(0.94, 0.88, 0.74, 1.0);

void fragment() {
	float shade = clamp(COLOR.r, 0.15, 1.0);
	vec3 base = sail_color.rgb * (0.42 + 0.72 * shade);
	// 席纹：横向细线，跟着帆的 UV
	float rib = smoothstep(0.08, 0.0, abs(fract(UV.y * 18.0) - 0.5) - 0.42);
	base *= 1.0 - rib * 0.18;
	ALBEDO = base;
	ROUGHNESS = 0.62;
	SPECULAR = 0.18;
}
