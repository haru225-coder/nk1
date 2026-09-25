shader_type canvas_item;
// 海图视口后期：四边褪色（绢本边缘）、轻晕影、屏幕空间的细颗粒。挂在 SubViewportContainer 上。

uniform vec4 edge_color : source_color = vec4(0.80, 0.72, 0.56, 1.0);
uniform float vignette : hint_range(0.0, 1.0) = 0.32;
uniform float edge_fade : hint_range(0.0, 0.3) = 0.06;
uniform float grain : hint_range(0.0, 0.1) = 0.025;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 q = UV * (1.0 - UV);
	float v = pow(clamp(q.x * q.y * 18.0, 0.0, 1.0), 0.35);
	c.rgb = mix(c.rgb * (1.0 - vignette * 0.6), c.rgb, v);
	// 四边向绢色褪
	float e = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float fade = 1.0 - smoothstep(0.0, edge_fade, e);
	c.rgb = mix(c.rgb, edge_color.rgb, fade * 0.85);
	c.rgb += (hash21(floor(FRAGCOORD.xy)) - 0.5) * grain;
	COLOR = c;
}
