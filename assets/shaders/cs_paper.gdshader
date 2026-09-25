// 宣纸底：UI 线宣纸贴图（纤维、杂点，1:1 平铺）+ 低频斑驳 + 四周旧色；贴图缺失时程序纤维 + 深色杂点兜底。
// reveal：纸面按墨晕同款噪声阈值「洇」进来 / 退去（0 = 无纸，1 = 满纸），前沿压一线湿痕——不是整层交叉淡化。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D paper_tex : source_color, filter_linear, repeat_enable;
uniform bool has_paper_tex = false;
uniform sampler2D fiber_tex : filter_linear, repeat_enable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec2 canvas_size = vec2(1280.0, 720.0);
uniform vec3 paper : source_color = vec3(0.914, 0.863, 0.753);
uniform vec3 aged : source_color = vec3(0.804, 0.722, 0.561);
uniform float fiber = 0.22;
uniform float alpha = 1.0;
uniform float reveal = 1.0;
uniform vec2 reveal_origin = vec2(0.55, 0.48);
// true：阈值场反过来（离 origin 越近越先退）——章节卡退场时纸从墨晕窗口往外退
uniform bool reveal_outward = false;
// 阈值扫过的区间：对准 field 在画面上的实际分布（5%–95% 分位约 0.03–0.56，外退场约 0.37–0.90；第 2 轮返工实测），
// 原先 −0.22…1.08 里只有三成真在动，纸两三帧就铺满，读作闪屏
uniform float thr_lo = -0.12;
uniform float thr_hi = 0.80;
uniform float seed = 0.0;

// 片元里重写 COLOR 会丢掉节点 modulate（含父节点链），先在顶点阶段存下
varying vec4 v_mod;
void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec2 px = UV * canvas_size;
	float asp = canvas_size.x / canvas_size.y;
	vec3 base;
	if (has_paper_tex) {
		base = texture(paper_tex, px / 512.0).rgb;
	} else {
		float f = texture(fiber_tex, px / 512.0).r - 0.5;
		float sp = smoothstep(0.36, 0.44, texture(noise_tex, px / 230.0 + vec2(0.71, 0.13)).r - 0.5);
		base = paper + vec3(f * fiber) - vec3(0.2, 0.2, 0.18) * sp;
	}
	float m = texture(noise_tex, px / 900.0 + vec2(0.23, 0.61)).r;
	vec2 q = (UV - 0.5) * vec2(asp, 1.0);
	float edge = smoothstep(0.35, 1.05, length(q * vec2(0.78, 1.0)));
	float age = clamp(edge * 0.85 + (m - 0.5) * 0.35, 0.0, 1.0);
	// 乘法做旧：保住贴图里的纤维与杂点
	vec3 c = base * mix(vec3(1.0), aged / paper, age);
	float a = 1.0;
	if (reveal < 0.999) {
		vec2 p = UV * vec2(asp, 1.0);
		float n1 = texture(noise_tex, p * 0.55 + vec2(seed, 0.37)).r;
		float n2 = texture(noise_tex, p * 1.9 + vec2(0.31, seed)).r;
		float n3 = texture(noise_tex, p * 4.5 + vec2(0.11, 0.57 + seed)).r;
		float d = length((UV - reveal_origin) * vec2(asp, 1.0)) / length(vec2(asp, 1.0));
		if (reveal_outward) {
			d = 0.85 - d;
		}
		// 低频噪声权重 0.6 → 0.35、中频 0.2 → 0.14：原先大块噪声在前沿外成一座座孤岛、边缘是分形棉絮，读作「棉絮块」（第 2 轮美术 M1）
		float field = d * 1.1 + (n1 - 0.5) * 0.35 + (n2 - 0.5) * 0.14 + (n3 - 0.5) * 0.05;
		float thr = mix(thr_lo, thr_hi, reveal);
		// 过渡带 0.025 → 0.10：硬边读作白色剪纸，放宽后是纸吃水洇开
		a = 1.0 - smoothstep(thr - 0.10, thr, field);
		// 前沿一道湿痕：纸边吃了水，略深略暖，带宽 0.18，读作洇湿的纸边而不是亮边
		float rim = smoothstep(thr - 0.18, thr - 0.01, field) * a;
		c = mix(c, c * vec3(0.72, 0.64, 0.52), rim * 0.85);
	}
	COLOR = vec4(c, a * alpha * v_mod.a);
}
