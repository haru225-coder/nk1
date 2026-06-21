shader_type canvas_item;

uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 0.38);
uniform float softness : hint_range(0.1, 1.0) = 0.62;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float vignette = smoothstep(softness, 1.15, dist);
	COLOR = vec4(edge_color.rgb, edge_color.a * vignette);
}