shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 竹席硬篷。横竹是网格上的扁条，这里不另画厚肋，也不把篾纹涂成一层层板。
// 顶点色 R 是竹间腹的一点明暗。色相由 sail_color 定：己方牙白，敌船绛红。
// 篾纹只是竹条之间的细缝和浅纵线，整张仍是一块布。
uniform vec4 sail_color : source_color = vec4(0.94, 0.88, 0.74, 1.0);

void fragment() {
	float shade = clamp(COLOR.r, 0.25, 1.0);
	vec3 base = sail_color.rgb * (0.50 + 0.72 * shade);

	float reed_f = UV.y * 36.0;
	float reed_i = floor(reed_f);
	float ry = fract(reed_f);
	float reed_tone = 0.97 + 0.03 * fract(sin(reed_i * 12.989) * 43758.5);
	float seam = smoothstep(0.14, 0.0, ry);
	float along = 0.985 + 0.015 * sin(UV.x * 70.0 + reed_i);
	float warp_f = UV.x * 14.0;
	float wy = abs(fract(warp_f) - 0.5);
	float warp = smoothstep(0.045, 0.0, wy - 0.455);
	base *= reed_tone * along;
	base *= 1.0 - seam * 0.18;
	base *= 1.0 - warp * 0.09;

	ALBEDO = base;
	ROUGHNESS = mix(0.86, 0.62, shade);
	SPECULAR = 0.08;
}
