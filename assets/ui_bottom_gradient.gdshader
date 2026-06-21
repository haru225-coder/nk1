shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 bottom_color : source_color = vec4(0.0, 0.0, 0.0, 0.48);

void fragment() {
	float t = smoothstep(0.0, 1.0, UV.y);
	COLOR = mix(top_color, bottom_color, t);
}