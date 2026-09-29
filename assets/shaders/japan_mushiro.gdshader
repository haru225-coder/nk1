shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, shadows_disabled;

// 一张软筵。一根根竖苇：缝是暗的，茎是圆的，茎与茎颜色不一样。
// 频率只放在席的横向上。不要 sin(up * 大数)，那会变成横档。
// 也不要沿高度对齐的色带。阴影会顺着网格切出横竹，所以这张席不吃影。
uniform vec4 sail_color : source_color = vec4(0.86, 0.70, 0.40, 1.0);

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float along = UV.x;
	float up = UV.y;

	// 大约四十根苇，略斜，宽度不齐。
	float count = 42.0;
	float x = along * count + up * 0.40;
	float id = floor(x);
	float f = fract(x);
	float gap_w = mix(0.10, 0.20, hash1(id + 4.0));
	float left = smoothstep(0.0, 0.045, f);
	float right = smoothstep(1.0, 1.0 - gap_w, f);
	float gap = left * right;
	// 茎的圆截面：中间亮，靠边暗。
	float core = abs(f - 0.5) * 2.0;
	float roundness = clamp(1.0 - core * core, 0.0, 1.0);
	// 茎里再分两三缕细丝，仍是竖的。
	float strand = 0.5 + 0.5 * sin((f * 3.0 + hash1(id) * 0.2) * 6.2831853);
	// 每根茎自己的深浅和一点暖冷，错开，不会排成横带。
	float tone = hash1(id + 2.2);
	float blot = hash1(id * 3.7 + floor(up * 5.0 + hash1(id) * 6.0));

	vec3 pale = vec3(0.95, 0.84, 0.58);
	vec3 deep = vec3(0.48, 0.32, 0.13);
	vec3 straw = mix(deep, pale, 0.35 + 0.65 * tone);
	straw = mix(straw, sail_color.rgb, 0.28);
	straw *= mix(0.90, 1.06, blot);
	straw *= mix(0.62, 1.14, roundness);
	straw *= mix(0.88, 1.0, strand);
	straw *= mix(0.34, 1.0, gap);
	// 脚略暗、头略亮，是整张布的缓坡，不是一档一档。
	straw *= mix(0.86, 1.0, smoothstep(0.0, 0.22, up));
	float belly = sin(along * 3.14159) * (1.0 - up);
	straw *= mix(1.0, 0.92, belly * 0.28);

	ALBEDO = straw;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
