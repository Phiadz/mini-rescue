shader_type canvas_item;
// Theme tối cho nền menu: đổi màu ảnh nền bản đồ (đất kem, nước xanh ngọc) sang đất xanh đen, nước xanh lam đậm.
// Giữ chi tiết sáng tối của ảnh gốc (viền sáng ven bờ, bóng đất đổ xuống nước, lưới trên mặt nước), có khuếch đại.

uniform vec4 land : source_color = vec4(0.106, 0.149, 0.2, 1.0);   // #1b2633
uniform vec4 water : source_color = vec4(0.05, 0.29, 0.36, 1.0);   // #0d4a5c

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float t = smoothstep(0.08, 0.25, c.b - c.r);   // nước: kênh xanh lam rõ hơn kênh đỏ
	// Khuếch đại chênh lệch sáng tối (nền tối thì chênh nhỏ khó thấy): viền sáng ven bờ, lưới mặt nước, bóng ven bờ.
	vec3 l = land.rgb * pow(c.r / 0.957, 8.0);     // đất gốc #f4f0e7: theo kênh đỏ
	vec3 w = water.rgb * pow(c.b / 0.886, 4.0);    // nước gốc #8ccfe2: theo kênh xanh lam
	COLOR = vec4(mix(l, w, t), c.a);
}
