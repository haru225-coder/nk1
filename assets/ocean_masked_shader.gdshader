shader_type canvas_item;

uniform sampler2D sea_mask : repeat_disable;
uniform float wave_speed : hint_range(0.1, 5.0) = 0.5;
uniform float wave_freq : hint_range(0.1, 20.0) = 15.0;
uniform float wave_amp : hint_range(0.001, 0.1) = 0.02;
uniform vec4 water_color : source_color = vec4(0.1, 0.4, 0.6, 1.0);
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
		float highlight = max(0.0, sin(uv.y * wave_freq * 2.0 + time * 1.5) * cos(uv.x * wave_freq * 2.0 + time * 1.5));
		highlight = pow(highlight, 4.0) * 0.3;

		vec4 water = mix(tex_color, water_color, 0.2) + vec4(highlight);
		float alpha = smoothstep(0.0, shore_fade, sea);
		COLOR = vec4(water.rgb, water.a * alpha);
	}
}