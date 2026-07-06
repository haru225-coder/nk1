shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable;
uniform float speed_x = 0.002;
uniform float speed_y = 0.001;
uniform float shadow_alpha = 0.25;

void fragment() {
    vec2 uv = UV + vec2(TIME * speed_x, TIME * speed_y);
    float noise = texture(noise_tex, uv).r;

    // 基础云影遮蔽
    float cloud = smoothstep(0.3, 0.7, noise);

    // 史实古地图：高频静态噪点（模拟粗糙羊皮纸/绢帛纤维）
    float grain = fract(sin(dot(UV * 2000.0, vec2(12.9898, 78.233))) * 43758.5453);

    // 最终 Alpha：云影与纸张噪点的叠加
    float final_alpha = (cloud * shadow_alpha) + (grain * 0.15);

    // 泛黄的底色（石青流派中的做旧感）
    vec3 out_color = vec3(0.2, 0.15, 0.05);

    COLOR = vec4(out_color, min(final_alpha, 0.95));
}
