shader_type canvas_item;

uniform sampler2D sea_mask : repeat_disable;
uniform float wave_speed : hint_range(0.1, 5.0) = 0.5;
uniform float wave_freq : hint_range(0.1, 20.0) = 15.0;
uniform float wave_amp : hint_range(0.001, 0.1) = 0.02;
uniform vec4 water_color : source_color = vec4(0.3, 0.35, 0.32, 0.8);
uniform float shore_fade : hint_range(0.0, 0.25) = 0.08;

void fragment() {
	float sea = texture(sea_mask, UV).r;
	if (sea < 0.01) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = UV;
		float time = TIME * wave_speed;
		vec2 wave1 = vec2(sin(uv.y * wave_freq + time), cos(uv.x * wave_freq + time * 0.8)) * wave_amp;
		vec2 wave2 = vec2(cos(uv.y * wave_freq * 1.5 - time * 1.2), sin(uv.x * wave_freq * 1.5 - time)) * (wave_amp * 0.5);
		vec2 distorted_uv = uv + wave1 + wave2;

		vec4 tex_color = texture(TEXTURE, distorted_uv);
		float highlight = max(0.0, wave1.x * wave2.y + wave1.y * wave2.x) * wave_amp * 500.0;

		// 13世纪古画风格：木刻/水墨硬边缘水纹
		float ink_line = step(wave_amp * 0.25, highlight);
		vec4 water = mix(tex_color, water_color, 0.6); // 加深底层填色力度
		water.rgb += vec3(ink_line * 0.25); // 使用清晰的线条代替泛光

		float alpha = smoothstep(0.0, shore_fade, sea);

		// 古风岸线浪花 (木刻版画感)
		float foam_band = smoothstep(0.01, shore_fade * 0.5, sea) - smoothstep(shore_fade * 0.5, shore_fade * 1.2, sea);
		float foam_noise = max(0.0, sin(uv.y * wave_freq * 4.0 + time * 3.0) * cos(uv.x * wave_freq * 4.0 + time * 3.0));
		float foam = step(0.4, foam_band * foam_noise * 1.5);
		water.rgb = mix(water.rgb, vec3(0.85, 0.82, 0.75), foam); // 使用泛黄的羊皮纸色作为浪花色

		COLOR = vec4(water.rgb, water.a * alpha);
	}
}