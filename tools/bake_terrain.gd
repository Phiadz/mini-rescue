extends Node
# Tạo ảnh nền địa hình tô màu từ bản đồ độ cao của D (assets/icons/terrain/height_field.png),
# kèm cây (assets/icons/tree.svg) rải trên đất. Bảng màu theo bản "Vector MVP": đất xanh đen,
# nước xanh dương sáng dần về phía bờ, đảo có viền cát.
# Chạy lại khi đổi mực nước, màu hoặc bản đồ (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/bake_terrain.tscn
# height_field.png lưu độ cao 16 bit: kênh đỏ là byte cao, kênh xanh lá là byte thấp; đổi về thang 0-100.
# Bản đồ độ cao khớp với tọa độ gốc trong data/map_01.json (điểm cao trong json cũng cao trong ảnh).

const SOURCE := 'res://assets/icons/terrain/height_field.png'
const TREE := 'res://assets/icons/tree.svg'
const MAP := 'res://data/map_01.json'
const OUTPUT := 'res://assets/icons/terrain/terrain_colored.png'
const WIDTH := 1280
const HEIGHT := 720

const SEA_LEVEL := 26.0    # mực nước trang trí: Làng Nổi, Bến Cảng trong nước; Ven Sông sát bờ (28 thì Ven Sông bị ngập)
const SAND_WIDTH := 0.7    # dải cát trên bờ, tính theo đơn vị độ cao
const SHALLOW_DEPTH := 2.5 # vùng nước nông sáng màu sát bờ
const DEPTH_RANGE := 14.0  # từ mặt nước xuống bao sâu thì thành màu nước sâu nhất
const BAND := 9.0          # đất chia bậc theo độ cao (kiểu bản đồ phân tầng), mỗi bậc cao BAND đơn vị
const BANDS := 4
const EDGE := 0.25         # độ mềm của ranh giới giữa các bậc (chống răng cưa)
const RELIEF := 0.5        # đổ bóng rất nhẹ theo độ dốc
const LIGHT := Vector2(-0.6, -0.8)  # ánh sáng từ trên bên trái

const LOW_LAND := Color('#141f35')
const HIGH_LAND := Color('#1f2e4a')
const SAND := Color('#c9cf86')
const SHALLOW := Color('#5ec3df')
const WATER := Color('#2a8ec2')
const DEEP_WATER := Color('#1a6597')

const TREE_SEED := 7
const TREE_COUNT := 60
const TREE_SIZE := Vector2i(34, 45)    # giữ tỉ lệ 112 × 150 của tree.svg
const TREE_GAP := 50.0                 # khoảng cách tối thiểu giữa hai cây
const NODE_CLEARANCE := 80.0           # không trồng cây quá gần điểm trên bản đồ
const LABEL_CLEARANCE := Rect2(-80, 20, 160, 50)  # chừa chỗ cho tên điểm phía dưới icon


func _ready() -> void:
	var field: Image = load(SOURCE).get_image()
	field.convert(Image.FORMAT_RGBA8)
	var h := PackedFloat32Array()
	h.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			h[y * WIDTH + x] = _height(field, x, y)

	var out := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			out.set_pixel(x, y, _color(h, x, y))
	_plant_trees(out, h)
	out.save_png(OUTPUT)
	print('Đã tạo ', OUTPUT)
	get_tree().quit()


func _color(h: PackedFloat32Array, x: int, y: int) -> Color:
	var v := h[y * WIDTH + x]
	var depth := SEA_LEVEL - v
	var water := SHALLOW.lerp(WATER, smoothstep(0.0, SHALLOW_DEPTH, depth)) \
			.lerp(DEEP_WATER, smoothstep(SHALLOW_DEPTH, DEPTH_RANGE, depth))
	var land := LOW_LAND.lerp(HIGH_LAND, _band(v - SEA_LEVEL) / float(BANDS - 1))
	var slope := Vector2(_at(h, x + 1, y) - _at(h, x - 1, y), _at(h, x, y + 1) - _at(h, x, y - 1)) * 0.5
	var shade := clampf(1.0 + RELIEF * slope.dot(LIGHT), 0.85, 1.15)
	land = Color(land.r * shade, land.g * shade, land.b * shade)
	var on_land := smoothstep(SEA_LEVEL - 0.25, SEA_LEVEL + 0.25, v)
	var sand := on_land * (1.0 - smoothstep(SEA_LEVEL + SAND_WIDTH * 0.5, SEA_LEVEL + SAND_WIDTH, v))
	return water.lerp(land, on_land).lerp(SAND, sand)


# Rải cây ngẫu nhiên (cố định theo TREE_SEED) trên đất liền và đảo, tránh điểm, tên điểm và bờ cát.
func _plant_trees(out: Image, h: PackedFloat32Array) -> void:
	var tree: Image = load(TREE).get_image()
	tree.convert(Image.FORMAT_RGBA8)
	tree.resize(TREE_SIZE.x, TREE_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var nodes: Array = JSON.parse_string(FileAccess.get_file_as_string(MAP))['nodes']
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED
	var planted: Array[Vector2] = []
	var tries := 0
	while planted.size() < TREE_COUNT and tries < 20000:
		tries += 1
		var p := Vector2(rng.randf_range(16, WIDTH - 16), rng.randf_range(16, HEIGHT - 16))
		if _at(h, int(p.x), int(p.y)) < SEA_LEVEL + SAND_WIDTH + 0.3:
			continue
		if planted.any(func(q: Vector2) -> bool: return q.distance_to(p) < TREE_GAP):
			continue
		var blocked := false
		for n in nodes:
			var np := Vector2(float(n['x']), float(n['y']))
			if np.distance_to(p) < NODE_CLEARANCE or Rect2(np + LABEL_CLEARANCE.position, LABEL_CLEARANCE.size).has_point(p):
				blocked = true
				break
		if blocked:
			continue
		planted.append(p)
	planted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)  # cây phía dưới đè cây phía trên
	for p in planted:
		var at := Vector2i(int(p.x) - TREE_SIZE.x / 2, int(p.y) - TREE_SIZE.y + 6)
		out.blend_rect(tree, Rect2i(Vector2i.ZERO, TREE_SIZE), at)


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
