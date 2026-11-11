shader_type canvas_item;
// Lớp nước của FloodOverlay. Vẽ trên một hình chữ nhật phủ cả bản đồ, TEXTURE là height_field.png.
// - field_prev, field_next: ảnh 32 × 18 (mỗi điểm ảnh là một ô), kênh R = mặt nước, G = độ ướt 0..1.
//   Lọc tuyến tính nên giữa các ô được làm mịn; `blend` trộn dần từ nhịp lũ trước sang nhịp lũ sau.
// - So mặt nước với độ cao từng điểm ảnh của height_field nên bờ nước chạy theo đường đồng mức.
// - Bỏ qua điểm ảnh là biển (nền đã vẽ biển).

uniform sampler2D field_prev : filter_linear, repeat_disable;
uniform sampler2D field_next : filter_linear, repeat_disable;
uniform float blend = 1.0;
uniform vec4 shallow_color : source_color = vec4(0.165, 0.549, 0.753, 1.0);
uniform vec4 deep_color : source_color = vec4(0.102, 0.396, 0.592, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.93, 1.0, 1.0);
uniform float shallow_max = 15.0;
uniform float h0 = 16.7;      // height_field = h0 + hscale × độ cao (xem tools/bake_grid.gd)
uniform float hscale = 0.667;
uniform float sea_max = 1.0;
uniform float opacity = 0.9;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 f = mix(texture(field_prev, uv).rg, texture(field_next, uv).rg, blend);
	vec4 hc = texture(TEXTURE, uv);  // height_field: R byte cao, G byte thấp, thang 0–100
	float hf = (floor(hc.r * 255.0 + 0.5) * 256.0 + floor(hc.g * 255.0 + 0.5)) / 65535.0 * 100.0;
	float t = clamp((hf - h0) / hscale, 0.0, 100.0);
	float depth = f.r - t;
	// Nhiễu chậm để mép nước không thẳng theo lưới ô.
	float n = vnoise(uv * vec2(48.0, 27.0) + TIME * 0.03) - 0.5;
	float reach = smoothstep(0.42, 0.58, f.g + n * 0.3);
	float wet = smoothstep(0.0, 0.5, depth + n * 0.4);
	float land = smoothstep(sea_max, sea_max + 1.5, t);
	float a = reach * wet * land;
	if (a < 0.01) {
		discard;
	}
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, shallow_max, depth));
	// Gợn sóng nhẹ.
	float ripple = vnoise(uv * vec2(160.0, 90.0) + vec2(TIME * 0.35, TIME * 0.2));
	col += (ripple - 0.5) * 0.06;
	// Viền bọt ở chỗ nước nông sát bờ và ở mép nước đang lan.
	float foam = max(1.0 - smoothstep(0.0, 1.4, depth), 1.0 - smoothstep(0.55, 0.75, f.g + n * 0.3));
	col = mix(col, foam_color.rgb, foam * 0.55);
	COLOR = vec4(col, a * opacity);
}
