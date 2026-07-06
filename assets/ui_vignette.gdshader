shader_type canvas_item;

// 古风暗角：深褐色墨渍
uniform vec4 edge_color : source_color = vec4(0.18, 0.12, 0.05, 0.8);
uniform float softness : hint_range(0.1, 1.0) = 0.5;
uniform float stain_intensity : hint_range(0.0, 1.0) = 0.35;

// 简单的伪随机数与2D噪声生成（用于墨渍斑驳）
vec2 hash(vec2 p) {
    p = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
    return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float noise(in vec2 p) {
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;
    vec2 i = floor(p + (p.x+p.y)*K1);
    vec2 a = p - i + (i.x+i.y)*K2;
    float m = step(a.y, a.x);
    vec2 o = vec2(m, 1.0-m);
    vec2 b = a - o + K2;
    vec2 c = a - 1.0 + 2.0*K2;
    vec3 h = max(0.5-vec3(dot(a,a), dot(b,b), dot(c,c)), 0.0);
    vec3 n = h*h*h*h*vec3(dot(a,hash(i+0.0)), dot(b,hash(i+o)), dot(c,hash(i+1.0)));
    return dot(n, vec3(70.0));
}

// 分形布朗运动 (FBM)
float fbm(vec2 uv) {
    float f = 0.0;
    float w = 0.5;
    for (int i = 0; i < 4; i++) {
        f += w * noise(uv);
        uv *= 2.0;
        w *= 0.5;
    }
    return f;
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    float dist = length(uv);

    // 基础暗角 (椭圆形)
    float base_vignette = smoothstep(softness, 1.25, dist);

    // 生成不规则的受潮/墨渍边缘
    // 使用 FBM 制造低频和高频的纸张斑驳感
    float stain = fbm(UV * 8.0) * 0.5 + 0.5;
    stain += fbm(UV * 24.0) * 0.2;

    // 将斑驳感叠加到边缘
    float final_vignette = base_vignette * (1.0 + stain * stain_intensity);

    // 限制在 0.0 - 1.0 之间
    final_vignette = clamp(final_vignette, 0.0, 1.0);

    COLOR = vec4(edge_color.rgb, edge_color.a * final_vignette);
}