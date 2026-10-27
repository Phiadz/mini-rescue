extends Node
# Tạo ảnh nền địa hình tô màu từ bản đồ độ cao của D (assets/icons/terrain/height_field.png).
# Chạy lại khi đổi mực nước trang trí hoặc màu (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/bake_terrain.tscn
# height_field.png lưu độ cao 16 bit: kênh đỏ là byte cao, kênh xanh lá là byte thấp; đổi về thang 0-100.
# Bản đồ độ cao khớp với tọa độ gốc trong data/map_01.json (điểm cao trong json cũng cao trong ảnh).

const SOURCE := 'res://assets/icons/terrain/height_field.png'
const OUTPUT := 'res://assets/icons/terrain/terrain_colored.png'
const WIDTH := 1280
const HEIGHT := 720

const SEA_LEVEL := 26.0    # mực nước trang trí: Làng Nổi, Bến Cảng trong nước; Ven Sông sát bờ
const SHORE_WIDTH := 0.8   # bề rộng dải bờ sáng, tính theo đơn vị độ cao
const DEPTH_RANGE := 12.0  # từ mặt nước xuống bao sâu thì thành màu nước sâu nhất
const BAND := 9.0          # đất chia bậc theo độ cao (kiểu bản đồ phân tầng), mỗi bậc cao BAND đơn vị
const BANDS := 4
const EDGE := 0.25         # độ mềm của ranh giới giữa các bậc (chống răng cưa)
const RELIEF := 0.6        # đổ bóng rất nhẹ theo độ dốc
const LIGHT := Vector2(-0.6, -0.8)  # ánh sáng từ trên bên trái

const DEEP_WATER := Color('#0a1830')
const WATER := Color('#143461')
const SHORE := Color('#78b3cc')
const LOW_LAND := Color('#1f3a52')
const HIGH_LAND := Color('#355f78')


func _ready() -> void:
	var field: Image = load(SOURCE).get_image()
	field.convert(Image.FORMAT_RGBA8)
	var h := PackedFloat32Array()
	h.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			h[y * WIDTH + x] = _height(field, x, y)

	var out := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	for y in HEIGHT:
		for x in WIDTH:
			var v := h[y * WIDTH + x]
			var water := DEEP_WATER.lerp(WATER, clampf(1.0 - (SEA_LEVEL - v) / DEPTH_RANGE, 0.0, 1.0))
			var land := LOW_LAND.lerp(HIGH_LAND, _band(v - SEA_LEVEL) / float(BANDS - 1))
			var slope := Vector2(_at(h, x + 1, y) - _at(h, x - 1, y), _at(h, x, y + 1) - _at(h, x, y - 1)) * 0.5
			var shade := clampf(1.0 + RELIEF * slope.dot(LIGHT), 0.8, 1.2)
			land = Color(land.r * shade, land.g * shade, land.b * shade)
			var on_land := smoothstep(SEA_LEVEL - 0.25, SEA_LEVEL + 0.25, v)
			var col := water.lerp(land, on_land)
			var beach := on_land * (1.0 - smoothstep(SEA_LEVEL + SHORE_WIDTH * 0.5, SEA_LEVEL + SHORE_WIDTH, v))
			out.set_pixel(x, y, col.lerp(SHORE, beach))
	out.save_png(OUTPUT)
	print('Đã tạo ', OUTPUT)
	get_tree().quit()


func _height(field: Image, x: int, y: int) -> float:
	var c := field.get_pixel(mini(x, field.get_width() - 1), mini(y, field.get_height() - 1))
	return (int(round(c.r * 255.0)) * 256 + int(round(c.g * 255.0))) / 65535.0 * 100.0


# Chỉ số bậc (0..BANDS-1) của độ cao trên mặt nước, mềm ở sát ranh giới để mép bậc không răng cưa.
func _band(above_sea: float) -> float:
	var level := clampf(above_sea / BAND, 0.0, BANDS - 1.0)
	var base := floorf(level)
	return minf(base + smoothstep(1.0 - EDGE / BAND, 1.0, level - base), BANDS - 1.0)


func _at(h: PackedFloat32Array, x: int, y: int) -> float:
	return h[clampi(y, 0, HEIGHT - 1) * WIDTH + clampi(x, 0, WIDTH - 1)]
