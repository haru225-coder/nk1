shader_type canvas_item;

uniform float wave_speed : hint_range(0.1, 5.0) = 1.0;
uniform float wave_freq : hint_range(0.1, 20.0) = 10.0;
uniform float wave_amp : hint_range(0.001, 0.1) = 0.01;
uniform vec4 water_color : source_color = vec4(0.1, 0.4, 0.6, 1.0);

void fragment() {
    vec2 uv = UV;
    
    // Complex layered sine waves for organic distortion
    float time = TIME * wave_speed;
    vec2 wave1 = vec2(sin(uv.y * wave_freq + time), cos(uv.x * wave_freq + time * 0.8)) * wave_amp;
    vec2 wave2 = vec2(cos(uv.y * wave_freq * 1.5 - time * 1.2), sin(uv.x * wave_freq * 1.5 - time)) * (wave_amp * 0.5);
    
    vec2 distorted_uv = uv + wave1 + wave2;
    
    vec4 tex_color = texture(TEXTURE, distorted_uv);
    
    // Add specular highlights on peaks of waves
    float highlight = max(0.0, sin(uv.y * wave_freq * 2.0 + time * 1.5) * cos(uv.x * wave_freq * 2.0 + time * 1.5));
    highlight = pow(highlight, 4.0) * 0.3;
    
    COLOR = mix(tex_color, water_color, 0.2) + vec4(highlight);
}
