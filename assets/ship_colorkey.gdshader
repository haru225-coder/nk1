shader_type canvas_item;

/// ship_topdown.png 是 1024×1024 RGB，灰白棋盘底 sat≈0。
/// 船体/帆 sat 多在 20 以上。低饱和像素抠掉，避免海战里盖住一整块白/红板。
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float key = 1.0 - smoothstep(0.035, 0.055, sat);
	COLOR = vec4(c.rgb, c.a * (1.0 - key));
}
