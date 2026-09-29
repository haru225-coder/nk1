shader_type canvas_item;
render_mode blend_mix, unshaded;

/// 海战海面（lane atmos）：「层波叠浪」——照马远《水图》的路数画俯视海面。
/// 花青作底，四道随风的涌浪（摆线形、域扭曲让浪脊打卷）定明暗三阶；浪高的等值线画成断续的月白水纹（白描），
/// 镜头拉远时水纹按屏幕疏密淡出，只剩色阶。风定水纹走向与碎浪，阵风压出风痕，长条风道顺风拖；
/// 云影漂过当天色，泥金闪点只落在向阳浪面。全用世界坐标，不采样旧 ocean_water.png（那是透视画，铺成俯视必有接缝）。
/// 交互口：hulls[] 画船边白沫、艏波与开尔文尾浪，ripples[] 画矢石落水的涟漪圈。由 scripts/combat/SeaAtmosphere.gd 每帧喂。
/// 与 ship-vfx 线的 _sync_ocean_look 兼容：wind_angle / wave_speed / foam_amount / glint_amount 同名同义。

// ── 风与海况 ──
/// 风往哪吹（世界坐标弧度，atan2(y, x)；y 向下）
uniform float wind_angle = 0.7;
/// 风力 0–1（SeaState.wind_speed / WIND_CAP）：碎浪、白头浪、风道都跟它
uniform float wind_strength : hint_range(0.0, 1.0) = 0.6;
/// 阵风 −1–1：正值压出风痕（暗、碎的一片）
uniform float gust : hint_range(-1.0, 1.0) = 0.0;
/// 浪行速度倍数；0.3 为常速（沿用 ship-vfx 线 0.18–0.42 的量纲）
uniform float wave_speed : hint_range(0.0, 1.5) = 0.3;
/// 白头浪多少
uniform float foam_amount : hint_range(0.0, 1.0) = 0.45;
/// 泥金闪点多少
uniform float glint_amount : hint_range(0.0, 1.0) = 0.22;
/// 水纹浓淡（0 关白描）
uniform float stroke_amount : hint_range(0.0, 1.0) = 0.62;
/// 近岸浅滩的石绿斑（0 外海一色）
uniform float shallows : hint_range(0.0, 1.0) = 0.35;
/// 云影浓淡
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.5;
/// 涌浪主波长（世界像素）
uniform float swell_len : hint_range(80.0, 900.0) = 330.0;
/// 与 ship-vfx 线同名：涌浪的世界空间频率（1/像素）；> 0 时主波长取 1 / swell_scale，盖过 swell_len
uniform float swell_scale : hint_range(0.0, 0.02) = 0.0;

// ── 色 ──
uniform vec4 deep_color : source_color = vec4(0.086, 0.188, 0.247, 1.0);
uniform vec4 mid_color : source_color = vec4(0.141, 0.337, 0.416, 1.0);
uniform vec4 shoal_color : source_color = vec4(0.247, 0.498, 0.478, 1.0);
uniform vec4 foam_color : source_color = vec4(0.867, 0.910, 0.890, 1.0);
uniform vec4 glint_color : source_color = vec4(0.914, 0.835, 0.604, 1.0);
uniform vec4 ink_color : source_color = vec4(0.063, 0.102, 0.125, 1.0);

/// 丝绢纤维底纹（可空）
uniform sampler2D fiber_tex : hint_default_white, repeat_enable, filter_linear;
uniform float fiber_amount : hint_range(0.0, 1.0) = 0.5;

// ── 交互 ──
/// 每条船：xy 世界位置，z 船首向（弧度，Node2D.rotation；船首朝 -y 旋转后），w 对水航速（像素/秒）
uniform vec4 hulls[8];
/// 每条船：x 半宽，y 半长（世界像素），z 1=敌船，w 保留
uniform vec4 hulls_b[8];
uniform int hull_count = 0;
/// 每圈涟漪：xy 世界位置，z 已过秒数，w 强度（0.3 一排矢，1 砲石，2 沉船）
uniform vec4 ripples[12];
uniform int ripple_count = 0;

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(7.3, 1.9);
		a *= 0.5;
	}
	return v / 0.875;
}

vec2 ghash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

// 梯度噪声连解析导数：返回 (值 ≈ −0.7–0.7, d/dx, d/dy)
vec3 gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = ghash(i);
	vec2 gb = ghash(i + vec2(1.0, 0.0));
	vec2 gc = ghash(i + vec2(0.0, 1.0));
	vec2 gd = ghash(i + vec2(1.0, 1.0));
	float va = dot(ga, f);
	float vb = dot(gb, f - vec2(1.0, 0.0));
	float vc = dot(gc, f - vec2(0.0, 1.0));
	float vd = dot(gd, f - vec2(1.0, 1.0));
	float v = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd);
	vec2 d = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
		+ du * (u.yx * (va - vb - vc + vd) + vec2(vb, vc) - va);
	return vec3(v, d);
}

// 0–1 的平滑梯度噪声：碎沫、断笔用（值噪声阈值一切会露出方格）
float fn(vec2 p) {
	return clamp(0.5 + gnoise(p).x * 0.8, 0.0, 1.0);
}

// 一道摆线涌浪：返回 (高, d高/dx, d高/dy)。steep 越大浪脊越尖、浪谷越平
vec3 swell(vec2 p, vec2 dir, float len, float amp, float steep, float t) {
	float k = 6.28318 / len;
	// 深水色散：c = sqrt(g·λ / 2π)，1 像素约 0.1 米 → 像素/秒
	float c = sqrt(9.8 * len * 0.1 / 6.28318) / 0.1;
	float th = k * (dot(dir, p) - c * t);
	float s = 0.5 + 0.5 * sin(th);
	float sp = pow(s, steep);
	float h = amp * (2.0 * sp * s - 1.0);
	float dh = amp * 2.0 * (steep + 1.0) * sp * 0.5 * cos(th) * k;
	return vec3(h, dir * dh);
}

// 拉远程度（fwidth 的世界像素 / 屏幕像素）
float zl_early(float px) {
	return smoothstep(0.9, 2.2, px);
}

vec2 rot(vec2 v, float a) {
	float cs = cos(a);
	float sn = sin(a);
	return vec2(cs * v.x - sn * v.y, sn * v.x + cs * v.y);
}

void fragment() {
	vec2 p = wpos;
	float t = TIME * (wave_speed / 0.3);
	vec2 wd = vec2(cos(wind_angle), sin(wind_angle));
	vec2 wn = vec2(-wd.y, wd.x);
	// 一屏像素对应多少世界像素：定水纹的抗锯齿与远景淡出
	float px = max(fwidth(p.x), 1e-4);
	float ws = clamp(wind_strength, 0.0, 1.0);

	// ── 涌浪：域扭曲后叠四道 ──
	vec2 warp = vec2(fbm3(p / 760.0 + vec2(0.0, t * 0.012)), fbm3(p / 760.0 + vec2(5.2, 1.3) - t * 0.01)) - 0.5;
	vec2 q = p + warp * 150.0;
	float L = swell_scale > 0.0 ? clamp(1.0 / swell_scale, 80.0, 900.0) : swell_len;
	// 浪群：每道涌的振幅按大尺度噪声起落，免得四道正弦叠成拉远后一眼看穿的菱格
	float e1 = 0.55 + 0.9 * fn(p / 1500.0 + vec2(2.0, 7.0));
	float e2 = 0.35 + 1.1 * fn(p / 1150.0 + vec2(-5.0, 3.0));
	float e3 = 0.3 + 1.2 * fn(p / 900.0 + vec2(9.0, -1.0));
	float e4 = 0.3 + 1.2 * fn(p / 700.0 + vec2(-3.0, -8.0));
	vec3 h1 = swell(q, wd, L, 1.0, 1.4, t) * e1;
	vec3 h = h1;
	h += swell(q, rot(wd, 0.42), L * 0.67, 0.58, 1.1, t) * e2;
	h += swell(q, rot(wd, -0.36), L * 0.47, 0.40, 0.9, t) * e3;
	h += swell(q, rot(wd, 0.78), L * 0.29, 0.22, 0.6, t) * e4;

	// 碎浪：横风拉长的细碎起伏（梯度噪声带解析导数），风大更碎
	vec2 ax = vec2(dot(p, wn), dot(p, wd));
	float chop_k = mix(0.45, 1.0, ws);
	vec2 cs1 = vec2(58.0, 24.0);
	vec3 c1 = gnoise(ax / cs1 + warp * 1.7 - vec2(0.0, t * 0.9));
	vec2 cs2 = vec2(27.0, 12.0);
	vec3 c2 = gnoise(ax / cs2 + vec2(4.1, 7.7) - vec2(t * 0.15, t * 1.6));
	float ch = 0.5 + (c1.x * 0.65 + c2.x * 0.35) * 0.8;
	vec2 cga = c1.yz / cs1 * 0.65 + c2.yz / cs2 * 0.35;
	vec2 cg = wn * cga.x + wd * cga.y;

	// 风痕：阵风压下来的一片，快速顺风走
	float paw = smoothstep(0.5, 0.85, fbm3((p - wd * t * 90.0) / 520.0 + 11.0)) * clamp(0.35 + gust * 1.3, 0.0, 1.0);
	float rough = chop_k * (0.35 + 0.65 * ws) * (1.0 + paw * 1.4);

	float height = h.x;
	// 明暗只随涌浪（与涟漪）走；碎浪另作一层细纹理，不参与分阶——否则三阶色被碎浪切成迷彩
	vec2 grad = h.yz;

	// ── 涟漪（矢石落水 / 沉船） ──
	float ring_foam = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= ripple_count) break;
		vec4 r = ripples[i];
		float age = r.z;
		float life = 1.6 + r.w * 0.9;
		if (age < 0.0 || age > life) continue;
		vec2 dv = p - r.xy;
		float d = length(dv);
		float rad = 10.0 + age * (70.0 + 30.0 * r.w);
		if (d > rad + 90.0) continue;
		float fade = 1.0 - age / life;
		float band = d - rad;
		float wv = exp(-band * band / (60.0 + 90.0 * age)) * fade;
		float ph = band * 0.19;
		height += sin(ph) * wv * 0.9 * r.w;
		grad += normalize(dv + 1e-3) * cos(ph) * 0.19 * wv * 0.9 * r.w;
		// 落点一团白沫，外圈一圈细沫
		float core = smoothstep(18.0 + 14.0 * r.w, 0.0, d) * smoothstep(life * 0.7, 0.0, age);
		float rim = exp(-band * band / 18.0) * fade * fade;
		ring_foam = max(ring_foam, core * 0.9 + rim * 0.55 * min(r.w, 1.3));
	}

	// ── 船：船边白沫、艏波、开尔文尾浪 ──
	float hull_foam = 0.0;
	float hull_dark = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= hull_count) break;
		vec4 hv = hulls[i];
		vec4 hb = hulls_b[i];
		vec2 dv = p - hv.xy;
		// 远处像素直接跳过：尾浪最长约 船长 + 410 像素
		float reach_all = hb.y * 1.9 + 460.0;
		if (dot(dv, dv) > reach_all * reach_all) continue;
		// 船局部：y 向船首为负（Node2D 船首 -y）
		vec2 lp = rot(dv, -hv.z);
		float spd = clamp(hv.w / 260.0, 0.0, 1.2);
		float hw = max(hb.x, 1.0);
		float hl = max(hb.y, 1.0);
		// 船形橄榄距离（近似）：1 = 船舷
		vec2 e = vec2(lp.x / hw, lp.y / hl);
		float ed = length(e);
		// 船下水色压暗一点（吃水）
		hull_dark = max(hull_dark, smoothstep(1.25, 0.8, ed) * 0.5);
		// 船舷白沫：贴着船舷碎成一簇一簇，航速越高越宽越密；静泊只剩一点
		float fr = (ed - 1.0) * hw;
		float fleck = fn(dv / 7.0 + vec2(t * 1.3, -t * 0.7)) * 0.6 + fn(dv / 3.0 - t) * 0.4;
		float fringe = smoothstep(3.0 + 14.0 * spd, 0.0, fr) * step(-2.0, fr);
		fringe *= smoothstep(0.62 - 0.25 * spd, 0.85, fleck) * (0.35 + 0.65 * spd);
		// 艏波：从船首贴着船舷往后撇开的一对短浪（约 17° 张角），只到船长的四分之一
		float bow = 0.0;
		float from_tip = lp.y + hl;
		if (from_tip > 0.0 && from_tip < hl * 0.6) {
			float yy = clamp(lp.y / hl, -1.0, 1.0);
			float side_w = hw * sqrt(max(0.0, 1.0 - yy * yy));
			float wave_x = side_w + from_tip * 0.3 + 3.0;
			bow = smoothstep(3.5 + 3.0 * spd, 0.0, abs(abs(lp.x) - wave_x));
			bow *= smoothstep(hl * 0.6, hl * 0.12, from_tip) * spd;
			bow *= smoothstep(0.3, 0.7, fleck);
		}
		// 开尔文尾浪：船尾后约 19.5° 两道斜浪，碎成沫点、越远越散越淡
		float back = lp.y - hl * 0.85;
		float kel = 0.0;
		if (back > 0.0) {
			float reach = 110.0 + 300.0 * spd;
			float fall = smoothstep(reach, 0.0, back);
			float arm = abs(abs(lp.x) - back * 0.354 - hw * 0.55);
			float aw = 3.0 + back * 0.06;
			float kf = fn(vec2(lp.x, back - t * 30.0) / 6.0) * 0.6 + fn(vec2(lp.x, back) / 14.0 + t * 0.2) * 0.4;
			kel = smoothstep(aw, 0.0, arm) * fall * spd * smoothstep(0.35 + back / reach * 0.35, 0.8, kf);
		}
		hull_foam = max(hull_foam, max(fringe, max(bow, kel)));
	}

	// ── 明暗三阶：按向阳坡面分色，不走光滑高光 ──
	vec2 sun = normalize(vec2(-0.62, -0.78));
	float slope = dot(grad, sun) * (L / 6.28318) * 0.33;
	float lit = clamp(0.5 + slope * 0.9 + height * 0.12, 0.0, 1.0);
	// 软阶：三段色阶之间留一道窄过渡
	float lit_q = smoothstep(0.28, 0.40, lit) * 0.5 + smoothstep(0.62, 0.74, lit) * 0.5;
	lit = mix(lit, lit_q, 0.6);
	// 海图尺度（拉远）：浪面明暗收一半，免得交叉涌浪排成菱格；让深浅斑与云影出来说话
	float zl = smoothstep(0.9, 2.2, px);
	lit = mix(lit, 0.5 + (lit - 0.5) * 0.45, zl);

	// 深浅斑：大尺度的水色起落 + 近岸石绿
	float depth_n = fbm3(p / 1700.0 + vec2(3.0, 9.0));
	float shoal_n = smoothstep(0.55, 0.8, fbm3(p / 1100.0 + vec2(-4.0, 2.0))) * shallows;
	vec3 base_deep = mix(deep_color.rgb * 0.84, deep_color.rgb * 1.14, depth_n);
	base_deep = mix(base_deep, mid_color.rgb * 0.8, smoothstep(0.55, 0.9, depth_n) * 0.35 * zl_early(px));
	vec3 col = mix(base_deep, mid_color.rgb, lit * 0.85);
	col = mix(col, shoal_color.rgb, clamp(shoal_n * (0.55 + 0.45 * lit), 0.0, 1.0) * 0.6);
	// 碎浪细纹理：只调一点明暗
	col *= 1.0 + ((ch - 0.5) * 0.16 + dot(cg, sun) * 9.0 * 0.05) * rough;
	// 风痕：压暗、偏冷
	col = mix(col, deep_color.rgb * 0.85, paw * 0.35);

	// ── 白描水纹：层波叠浪 ──
	// 顺着主涌的相位排出平行长线（每个波长四道），次涌与碎浪把线推得起伏；线聚在浪脊、浪谷稀——马远《水图》的路数。
	float k1 = 6.28318 / L;
	float c1s = sqrt(9.8 * L * 0.1 / 6.28318) / 0.1;
	float th1 = k1 * (dot(wd, q) - c1s * t);
	float sfield = th1 / 6.28318 * 4.0 + (height - h1.x) * 0.9 + (ch - 0.5) * 0.22 * rough;
	float sw = max(fwidth(sfield), 1e-4);
	// 线疏于约 5 屏像素才画：拉远后自然淡成色阶
	float lod = smoothstep(0.26, 0.11, sw);
	float stroke = 0.0;
	{
		float dd = abs(fract(sfield + 0.5) - 0.5) / sw;
		float line = 1.0 - smoothstep(0.45, 1.45, dd);
		// 笔意：沿线（横风方向）断续，一笔长一笔短
		float brk = smoothstep(0.38, 0.6, fn(vec2(ax.x / 70.0, ax.y / 16.0) + warp * 2.0));
		// 浪脊一侧浓、浪谷淡
		float crest_w = smoothstep(-0.25, 0.95, h1.x / e1);
		stroke = line * lod * brk * (0.12 + 0.88 * crest_w) * stroke_amount;
	}
	// 墨线：浪谷背阴处错开半道的淡墨，给层次
	float ink = 0.0;
	{
		float dd = abs(fract(sfield) - 0.5) / sw;
		float line = 1.0 - smoothstep(0.4, 1.3, dd);
		ink = line * lod * smoothstep(0.1, -0.9, h1.x / e1) * 0.3 * stroke_amount;
	}

	// ── 白头浪：浪脊高处、风大才起，碎成点片 ──
	float cap_n = fn((p - wd * t * 26.0) / 12.0) * 0.6 + fn((p + wn * 13.0) / 5.5 + t * 0.4) * 0.4;
	float crest = smoothstep(0.9, 1.55, height + (ch - 0.5) * 0.9 * rough);
	float caps = crest * smoothstep(0.62 - 0.22 * ws, 0.9, cap_n) * foam_amount * (0.35 + 0.95 * ws) * (1.0 + paw);

	// ── 风道：顺风的长条浅纹 ──
	vec2 lax = ax + warp * 120.0;
	float lane_n = fn(vec2(lax.x / 60.0, (lax.y - t * 34.0) / 700.0));
	float lanes = smoothstep(0.62, 0.92, lane_n) * (0.1 + 0.5 * ws) * smoothstep(0.1, 0.45, ws);
	lanes *= fn(vec2(ax.x / 400.0, ax.y / 1100.0));

	// ── 云影：天色从海上过 ──
	float cloud = smoothstep(0.52, 0.78, fbm3((p - wd * t * 22.0) / 2600.0 + vec2(1.7, 4.4)));
	col *= 1.0 - cloud * 0.22 * cloud_amount;

	// ── 泥金闪点：向阳浪面，格点里偶尔一闪 ──
	vec2 gcell = floor(p / 9.0);
	float gh = hash21(gcell);
	float tw = 0.5 + 0.5 * sin(t * (3.0 + gh * 5.0) + gh * 40.0);
	float face = smoothstep(0.72, 0.95, lit + (ch - 0.5) * 0.4);
	float glint = step(0.985 - 0.02 * ws, gh) * tw * tw * face * glint_amount * (1.0 - cloud * 0.8);
	vec2 gf = fract(p / 9.0) - 0.5;
	glint *= smoothstep(0.32, 0.0, length(gf));
	// 拉远时闪点收成浪面一层微亮
	float glod = smoothstep(2.4, 0.9, px);
	glint = glint * glod + face * glint_amount * 0.08 * (1.0 - glod);

	stroke *= 1.0 - 0.45 * zl;
	ink *= 1.0 - 0.7 * zl;
	caps *= 1.0 - 0.35 * zl;

	// ── 合成 ──
	col = mix(col, ink_color.rgb, ink);
	col = mix(col, foam_color.rgb, clamp(stroke * 0.7, 0.0, 1.0));
	col = mix(col, foam_color.rgb, clamp(lanes * 0.1, 0.0, 1.0));
	col *= 1.0 - hull_dark * 0.18;
	float foam = clamp(caps + ring_foam + hull_foam, 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam * 0.85);
	col += glint_color.rgb * glint * 1.1;

	// 丝绢纤维：很淡的一层，调暗亮两头
	float fib = texture(fiber_tex, p / 620.0).r;
	col *= 1.0 + (fib - 0.5) * 0.12 * fiber_amount;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
