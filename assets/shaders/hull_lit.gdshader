shader_type canvas_item;
render_mode blend_mix;

/// 海船受光罩（lane combat12-E）：Ship / PirateShip 的 HullLight，排在 Sprite2D 之后、同贴图同变换叠在船图上，
/// 参数由 scripts/combat/ShipLook.gd 逐帧写。船图自己的材质（CombatFx.dress_ship 的帆抖 / 暖 rim）照旧，这层只薄薄盖一道：
///   朝日一侧的船舷、帆缘提一层暖光，背光一侧与贴水的船缘压一层海青；横摇时迎日那舷亮一点、背日那舷暗一点。
/// 只画颜色不改形，所以船图的中弹闪红、进水压暗、降幡发灰都还看得见。

/// 朝日方向（贴图坐标系，x 右 y 下；ShipLook 按船向把世界里的日照方向换算进来）
uniform vec2 light_dir = vec2(-0.55, -0.83);
/// 整船明暗坡度、船缘受光、船缘取梯度的半径（贴图像素）、横摇（-1..1）
uniform float light_gain = 0.18;
uniform float rim_gain = 0.32;
uniform float edge_px = 9.0;
uniform float roll = 0.0;
/// 受光 / 背光的颜色与最浓的不透明度；fade 跟船图的 alpha（沉没 / 离场一起淡）
uniform vec4 sun_color : source_color = vec4(1.0, 0.9, 0.68, 1.0);
uniform vec4 shade_color : source_color = vec4(0.03, 0.1, 0.2, 1.0);
uniform float sun_max = 0.3;
uniform float shade_max = 0.42;
uniform float fade = 1.0;

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 px = TEXTURE_PIXEL_SIZE * edge_px;
	float l = texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
	float r = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	float u = texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float d = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	// 向外的法线 ≈ alpha 下降的方向；与朝日方向同向的船缘受光
	float rim = dot(vec2(l - r, u - d), light_dir);
	float inner = min(min(l, r), min(u, d));
	vec2 c = UV - 0.5;
	float lit = light_gain * (dot(c, light_dir) * 1.6 + roll * c.x * 3.2) + rim_gain * rim * (1.0 - 0.6 * inner);
	// 贴水的船缘（离透明处近）另压一点暗：船是坐在水里，不是贴在纸上
	float ao = (1.0 - smoothstep(0.0, 0.9, inner)) * 0.1;
	float sun = step(0.0, lit);
	vec3 rgb = mix(shade_color.rgb, sun_color.rgb, sun);
	float alpha = mix(clamp(-lit * 1.8 + ao, 0.0, shade_max), clamp(lit * 1.4 - ao, 0.0, sun_max), sun);
	COLOR = vec4(rgb, alpha * a * clamp(fade, 0.0, 1.0));
}
