// 标题屏引言 / 卷首长文「逐行浮现」（cinematics 线，TitleStage 用）：
// 一段文字按行依次由左至右洇出（居中行由中间向两边），前沿柔边。挂在 Label 上，按字形顶点的本地坐标算行号与横向位置。
// 片元里的 COLOR 已是「顶点色 × 贴图」（含 modulate 与字色），这里只乘 alpha，不丢 modulate。
shader_type canvas_item;

uniform float progress = 1.0;   // 0..1：整段（所有行）的揭开进度
uniform float lines = 1.0;      // 行数
uniform float line_h = 30.0;    // 行距（像素，字高 + line_spacing）
uniform float width = 800.0;    // 控件宽（像素）
uniform float soft = 0.16;      // 前沿柔边（占宽）
uniform bool from_center = false;

varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float line = clamp(floor(v_pos.y / max(line_h, 1.0)), 0.0, max(lines - 1.0, 0.0));
	float lp = clamp(progress * lines - line, 0.0, 1.0);
	float x = clamp(v_pos.x / max(width, 1.0), 0.0, 1.0);
	if (from_center) {
		x = abs(x - 0.5) * 2.0;
	}
	float edge = mix(-soft, 1.0, lp);
	float a = 1.0 - smoothstep(edge, edge + soft, x);
	a = lp >= 1.0 ? 1.0 : a;
	COLOR.a *= a;
}
