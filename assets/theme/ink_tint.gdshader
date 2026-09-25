// 墨迹着色（UI 线）：按贴图 alpha 给 ink_splash_* 这类「焦墨 + alpha」贴图着任意颜色。
// modulate / self_modulate 是乘法，焦墨 #0d0b09 乘什么都近黑，出不了朱色墨迹；这里直接用 tint 换色，
// 薄墨处略亮、积墨处略深。modulate 的 alpha 照常调浓淡。
// 用法：TextureRect.material = preload("res://assets/theme/ink_tint_zhu.tres")（朱砂预置），
//       或 ShaderMaterial + 本 shader，set_shader_parameter("tint", Color("#c9a14a")) 改色。
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.690, 0.188, 0.165, 1.0);

void fragment() {
	float a = COLOR.a;
	COLOR = vec4(mix(tint.rgb * 1.08, tint.rgb * 0.9, a), a * tint.a);
}
