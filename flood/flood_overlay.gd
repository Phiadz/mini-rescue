class_name FloodOverlay
extends Node2D
## Lớp nước (module B). Chỉ vẽ, không sửa dữ liệu đồ thị.
## Vẽ một hình chữ nhật phủ cả bản đồ bằng shader water.gdshader:
## - mỗi nhịp lũ (FLOOD_TICK), đóng gói mặt nước và độ ướt của 32 × 18 ô vào một ảnh nhỏ;
## - shader làm mịn ảnh đó, so với height_field.png từng điểm ảnh, nên bờ nước theo đường đồng mức;
## - giữ ảnh nhịp trước và nhịp sau, trộn dần trong khoảng FLOOD_TICK để nước lan liên tục.
## Nằm dưới EdgeLayer và NodeLayer trong main.tscn nên đường, điểm và xe vẫn vẽ đè lên trên.

const HEIGHT_FIELD := preload('res://assets/icons/terrain/height_field.png')  # mặc định (map_01)
const DEFAULT_COLORS := {shallow = Color(0.165, 0.549, 0.753), deep = Color(0.102, 0.396, 0.592), foam = Color(0.78, 0.93, 1.0)}
const WATER_SHADER := preload('res://flood/water.gdshader')
const MAP_SIZE := Vector2(1280, 720)

var _prev_img: Image
var _next_img: Image
var _prev_tex: ImageTexture
var _next_tex: ImageTexture
var _since_tick := 0.0
var _wet_cells := 0
var _height_tex: Texture2D = HEIGHT_FIELD


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # height_field mã hóa 16 bit, không được nội suy
	_prev_img = Image.create(Config.GRID_COLS, Config.GRID_ROWS, false, Image.FORMAT_RGBH)
	_next_img = Image.create(Config.GRID_COLS, Config.GRID_ROWS, false, Image.FORMAT_RGBH)
	_prev_tex = ImageTexture.create_from_image(_prev_img)
	_next_tex = ImageTexture.create_from_image(_next_img)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter('field_prev', _prev_tex)
	mat.set_shader_parameter('field_next', _next_tex)
	mat.set_shader_parameter('shallow_max', Config.SHALLOW_MAX)
	mat.set_shader_parameter('sea_max', Config.SEA_MAX_ELEVATION)
	material = mat
	EventBus.water_level_changed.connect(func(_l: float) -> void: _refresh())
	EventBus.game_started.connect(func() -> void:
		_apply_terrain()
		_refresh()
		_refresh())  # hai lần để ảnh trước và sau giống nhau, không trộn từ ván cũ


func _process(delta: float) -> void:
	_since_tick += delta
	(material as ShaderMaterial).set_shader_parameter('blend', clampf(_since_tick / Config.FLOOD_TICK, 0.0, 1.0))


func _draw() -> void:
	draw_texture_rect(_height_tex, Rect2(Vector2.ZERO, MAP_SIZE), false)


# Ảnh độ cao và màu nước theo khóa "terrain" của bản đồ; bản đồ không khai báo thì dùng mặc định của map_01.
func _apply_terrain() -> void:
	var t: Dictionary = GraphManager.get_terrain()
	_height_tex = load(t["height"]) if t.has("height") else HEIGHT_FIELD
	var mat := material as ShaderMaterial
	for key in ["shallow", "deep", "foam"]:
		mat.set_shader_parameter(key + "_color", Color(t[key]) if t.has(key) else DEFAULT_COLORS[key])
	queue_redraw()


## Các kho và khu dân cư có ô đang ngập.
func flooded_node_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in GraphManager.get_node_ids():
		var n = GraphManager.get_map_node(id)
		if n != null and n.kind != Types.NodeKind.ROAD and FloodManager.depth_at(GraphManager.cell_of(n.pos)) >= FloodManager.DRY_EPSILON:
			ids.append(id)
	return ids


## Số ô đất đang ngập (không tính ô biển).
func wet_cell_count() -> int:
	return _wet_cells


# Kênh B: mức phủ lũ lên sông, biển. Ô đất: mức ngập của nó. Ô sông, biển: mức ngập lớn nhất của 8 ô xung quanh,
# lan thêm 2 ô vào trong, để chỗ bờ đã ngập thì mặt lũ phủ liền qua sông, không lộ viền bờ của nền.
func _sea_cover() -> Dictionary:
	var cover := {}
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			var c := Vector2i(x, y)
			if not FloodManager.is_sea(c):
				cover[c] = clampf(FloodManager.depth_at(c) / Config.FLOOD_SPILL_DEPTH, 0.0, 1.0)
	for pass_i in 3:
		var next := cover.duplicate()
		for y in Config.GRID_ROWS:
			for x in Config.GRID_COLS:
				var c := Vector2i(x, y)
				if not FloodManager.is_sea(c):
					continue
				var best: float = cover.get(c, 0.0)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var n := c + Vector2i(dx, dy)
						if (pass_i == 0 and FloodManager.is_sea(n)) or not cover.has(n):
							continue
						best = maxf(best, cover[n])
				next[c] = best
		cover = next
	return cover


# Ảnh nhịp sau thành ảnh nhịp trước; dựng ảnh nhịp sau từ FloodManager.
# Ô ướt: R = mặt nước, G = độ ướt (độ sâu / FLOOD_SPILL_DEPTH). Ô khô sát nước: R = mặt nước cao nhất
# của ô kề để nội suy không kéo mặt nước tụt xuống ở mép, G = 0.
func _refresh() -> void:
	_prev_img.copy_from(_next_img)
	var surface := {}
	var wet := 0
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			var c := Vector2i(x, y)
			var d := FloodManager.depth_at(c)
			if FloodManager.is_sea(c) or d >= FloodManager.DRY_EPSILON:
				surface[c] = FloodManager.surface_at(c)
				if not FloodManager.is_sea(c):
					wet += 1
	var cover := _sea_cover()
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			var c := Vector2i(x, y)
			var b: float = cover.get(c, 0.0)
			if surface.has(c):
				var g := 1.0 if FloodManager.is_sea(c) else clampf(FloodManager.depth_at(c) / Config.FLOOD_SPILL_DEPTH, 0.0, 1.0)
				_next_img.set_pixel(x, y, Color(surface[c], g, b))
				continue
			var best := 0.0
			for d in FloodManager.NEIGHBORS:
				best = maxf(best, surface.get(c + d, 0.0))
			_next_img.set_pixel(x, y, Color(best, 0.0, b))
	_wet_cells = wet
	_prev_tex.update(_prev_img)
	_next_tex.update(_next_img)
	_since_tick = 0.0
	queue_redraw()
