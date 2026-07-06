shader_type canvas_item;

uniform float grain_amount : hint_range(0.0, 1.0) = 0.08;
uniform float bump_amount : hint_range(0.0, 3.0) = 1.0;
uniform float paper_darkness : hint_range(0.0, 1.0) = 0.05;

// 伪随机函数
float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

// 简单 2D 噪声
float noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float a = random(i);
	float b = random(i + vec2(1.0, 0.0));
	float c = random(i + vec2(0.0, 1.0));
	float d = random(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a)* u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// 分形布朗运动 (FBM)
float fbm(vec2 uv) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.50)));
	for (int i = 0; i < 6; ++i) {
		v += a * noise(uv);
		uv = rot * uv * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);

	if (base_color.a < 0.01) {
		base_color.rgb = vec3(0.0);
	}

	// 1. 高频纤维质感
	vec2 grain_uv = UV * 4000.0;
	float grain = fbm(grain_uv);

	// 2. 基于亮度的伪浮雕 (Bump Mapping)
	float dx = TEXTURE_PIXEL_SIZE.x * 2.0;
	float dy = TEXTURE_PIXEL_SIZE.y * 2.0;

	// 计算亮度 (高度)
	float h_center = dot(base_color.rgb, vec3(0.299, 0.587, 0.114));
	float h_right  = dot(texture(TEXTURE, UV + vec2(dx, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
	float h_down   = dot(texture(TEXTURE, UV + vec2(0.0, dy)).rgb, vec3(0.299, 0.587, 0.114));

	// 高频地形起伏再加一层宏观 FBM 噪声，避免大平原过于平坦
	float macro_noise = fbm(UV * 200.0) * 0.1;
	float h_right_noise = fbm((UV + vec2(dx, 0.0)) * 200.0) * 0.1;
	float h_down_noise = fbm((UV + vec2(0.0, dy)) * 200.0) * 0.1;

	h_center += macro_noise;
	h_right += h_right_noise;
	h_down += h_down_noise;

	// 计算梯度偏导数
	float dzdx = (h_right - h_center) / dx;
	float dzdy = (h_down - h_center) / dy;

	// 法线向量构造 (Z 朝上，光从左上打来)
	vec3 normal = normalize(vec3(-dzdx * bump_amount, -dzdy * bump_amount, 1.0));
	vec3 light_dir = normalize(vec3(1.0, 1.0, 0.8));

	float diffuse = clamp(dot(normal, light_dir), 0.0, 1.0);

	// 调整光照强度使原图颜色不至于过曝
	float light_factor = diffuse * 1.5 + 0.3;
	vec3 final_color = base_color.rgb * light_factor;

	// 3. 颜色混合
	// 纸张颗粒导致的暗点/亮点
	final_color -= (0.5 - grain) * grain_amount;
	// 添加一抹旧纸张的泛黄沉淀
	final_color = mix(final_color, vec3(0.85, 0.78, 0.65), paper_darkness);

	// 4. 古画“泥金/金箔”特效 (Gold Leaf/Flakes)
	// 使用高频的 Hash 噪点并进行严苛的 Threshold 裁剪，生成稀疏的碎片
	float gold_noise = random(UV * 8500.0);
	float gold_flake = step(0.998, gold_noise); // 千分之二的概率出现金箔
	// 大块金箔：使用低频 FBM 加持
	float gold_cluster = step(0.7, fbm(UV * 50.0)) * step(0.992, random(UV * 4200.0));
	float combined_gold = max(gold_flake, gold_cluster);

	vec3 gold_color = vec3(0.95, 0.75, 0.25);
	// 根据光照让金箔闪烁
	float gold_shine = diffuse * 1.2 + 0.5;
	final_color = mix(final_color, gold_color * gold_shine, combined_gold * 0.85);

	COLOR = vec4(final_color, base_color.a);
}
