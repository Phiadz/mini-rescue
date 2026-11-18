shader_type canvas_item;
// Lớp lũ kiểu tối giản cho bản đồ theo lưới (terrain.style = "grid"), thay cho water.gdshader.
// Mỗi ô có nước là một ô vuông màu phẳng; cạnh ô giữ thẳng, góc bo theo cung tròn bán kính `radius`:
// - góc lồi (ô nước, hai ô kề và ô chéo đều khô) cắt theo cung tròn;
// - góc lõm (ô khô, hai ô kề đều có nước) lấp theo cung tròn.
// Nền bản đồ vẽ sông bằng đúng luật này (grid_base.js), nên chỗ lũ chạm sông liền một mảng, không lộ mép.
// field_prev, field_next: ảnh số cột × số hàng, kênh R = 1 nếu ô sâu (hoặc sông), G = 1 nếu ô có nước (ngập hoặc sông).
// Ảnh nhịp lũ trước mờ dần sang ảnh nhịp sau theo `blend`.
// Bóng đất: nước tối dần ở sát bờ, để đất trông cao hơn mặt nước. Độ "gần bờ" lấy từ kênh G nội suy B-spline bậc ba
// (4 lần lấy mẫu tuyến tính), lệch về phía trên trái nên bóng đổ về dưới phải; B-spline cho bóng tròn theo góc, không nhọn.

uniform sampler2D field_prev : filter_linear, repeat_disable;  // texelFetch cho luật góc ô, texture() (tuyến tính) cho bóng
uniform sampler2D field_next : filter_linear, repeat_disable;
uniform float blend = 1.0;
uniform vec4 shallow_color : source_color = vec4(0.761, 0.902, 0.937, 1.0);
uniform vec4 deep_color : source_color = vec4(0.549, 0.812, 0.886, 1.0);
uniform vec2 map_size = vec2(1280.0, 720.0);
uniform float cell = 40.0;
uniform float radius = 20.0;
uniform vec2 shade_offset = vec2(2.0, 4.0);  // bóng đổ về dưới phải, như bóng của nhà
uniform float shade_band = 0.18;            // bề rộng bóng theo giá trị nội suy (khoảng 11 px)
uniform float shade_strength = 0.16;        // tối nhất ở sát bờ
uniform float grid_step = 120.0;            // lưới mảnh trên mặt nước: mỗi ô lưới bằng 3 × 3 ô gốc
uniform float grid_width = 1.5;             // bề rộng nét (px bản đồ)
uniform float grid_alpha = 0.32;            // độ sáng nét lưới (trộn với trắng)

vec4 cubic_w(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) * (1.0 / 6.0);
}

// Kênh G nội suy B-spline bậc ba bằng 4 lần lấy mẫu tuyến tính.
float bspline_g(sampler2D tex, vec2 uv) {
	vec2 res = vec2(textureSize(tex, 0));
	vec2 tc = uv * res - 0.5;
	vec2 f = fract(tc);
	tc -= f;
	vec4 xc = cubic_w(f.x);
	vec4 yc = cubic_w(f.y);
	vec4 c = tc.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 o = (c + vec4(xc.yw, yc.yw) / s) / res.xxyy;
	float s0 = textureLod(tex, o.xz, 0.0).g;
	float s1 = textureLod(tex, o.yz, 0.0).g;
	float s2 = textureLod(tex, o.xw, 0.0).g;
	float s3 = textureLod(tex, o.yw, 0.0).g;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

float corner_rule(float a, float h, float v, float d, bool in_square, bool in_circle) {
	bool wa = a > 0.5;
	if (!in_square) {
		return wa ? 1.0 : 0.0;
	}
	if (wa) {
		return (h > 0.5 || v > 0.5 || d > 0.5 || in_circle) ? 1.0 : 0.0;
	}
	return (h > 0.5 && v > 0.5 && !in_circle) ? 1.0 : 0.0;
}

// Độ phủ (sâu, có nước) tại điểm p của bản đồ, đã trộn nhịp trước và nhịp sau.
vec2 cover(vec2 p) {
	ivec2 grid = textureSize(field_prev, 0);
	ivec2 c = ivec2(floor(p / cell));
	vec2 l = p - vec2(c) * cell;
	ivec2 s = ivec2(l.x < cell * 0.5 ? -1 : 1, l.y < cell * 0.5 ? -1 : 1);
	vec2 e = vec2(s.x < 0 ? l.x : cell - l.x, s.y < 0 ? l.y : cell - l.y);
	bool in_square = e.x < radius && e.y < radius;
	vec2 q = vec2(radius) - e;
	bool in_circle = dot(q, q) <= radius * radius;
	ivec2 hi = grid - ivec2(1);
	ivec2 ca = clamp(c, ivec2(0), hi);
	ivec2 ch = clamp(c + ivec2(s.x, 0), ivec2(0), hi);
	ivec2 cv = clamp(c + ivec2(0, s.y), ivec2(0), hi);
	ivec2 cd = clamp(c + s, ivec2(0), hi);
	vec2 pa = texelFetch(field_prev, ca, 0).rg, ph = texelFetch(field_prev, ch, 0).rg;
	vec2 pv = texelFetch(field_prev, cv, 0).rg, pd = texelFetch(field_prev, cd, 0).rg;
	vec2 na = texelFetch(field_next, ca, 0).rg, nh = texelFetch(field_next, ch, 0).rg;
	vec2 nv = texelFetch(field_next, cv, 0).rg, nd = texelFetch(field_next, cd, 0).rg;
	vec2 prev = vec2(corner_rule(pa.r, ph.r, pv.r, pd.r, in_square, in_circle),
			corner_rule(pa.g, ph.g, pv.g, pd.g, in_square, in_circle));
	vec2 next = vec2(corner_rule(na.r, nh.r, nv.r, nd.r, in_square, in_circle),
			corner_rule(na.g, nh.g, nv.g, nd.g, in_square, in_circle));
	return mix(prev, next, blend);
}

void fragment() {
	vec2 p = UV * map_size;
	float px = max(fwidth(p.x), 1e-4);  // cỡ một điểm ảnh màn hình theo px bản đồ, để khử răng cưa khi phóng to, thu nhỏ
	// 4 mẫu lưới xoay trong một điểm ảnh.
	vec2 sum = cover(p + vec2(0.125, 0.375) * px) + cover(p + vec2(0.375, -0.125) * px)
			+ cover(p + vec2(-0.125, -0.375) * px) + cover(p + vec2(-0.375, 0.125) * px);
	sum *= 0.25;
	if (sum.y < 0.004) {
		discard;
	}
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, clamp(sum.x / sum.y, 0.0, 1.0));
	vec2 gd = abs(p - grid_step * round(p / grid_step));
	float line = clamp((grid_width * 0.5 - min(gd.x, gd.y)) / px + 0.5, 0.0, 1.0);
	col = mix(col, vec3(1.0), line * grid_alpha);
	vec2 uv_s = (p - shade_offset) / map_size;
	float w = mix(bspline_g(field_prev, uv_s), bspline_g(field_next, uv_s), blend);
	col *= 1.0 - shade_strength * (1.0 - smoothstep(0.5, 0.5 + shade_band, w));
	COLOR = vec4(col, sum.y);
}
