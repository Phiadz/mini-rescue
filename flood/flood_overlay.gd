class_name FloodOverlay
extends Node2D
## Lớp nước (module B). Chỉ vẽ, không sửa dữ liệu đồ thị.
## Mỗi ô đất đã ngập vẽ một hình tròn bán kính 0,75 ô; các ô kề nhau chồng lên nhau thành mảng nước loang.
## Màu đục, cùng tông với biển trên nền, nên chỗ chồng nhau không bị đậm lên: ngập nông màu biển gần bờ,
## ngập sâu màu biển xa. Ô biển không vẽ vì nền đã có biển.
## Nằm dưới EdgeLayer và NodeLayer trong main.tscn nên đường, điểm và xe vẫn vẽ đè lên trên.

const SHALLOW_COLOR := Color("#2a8cc0")
const DEEP_COLOR := Color("#1a6597")
const RADIUS_RATIO := 0.75

var _wet: Array[Vector2] = []   # tâm các ô ngập nông hoặc sâu
var _deep: Array[Vector2] = []  # tâm các ô ngập sâu


func _ready() -> void:
	EventBus.water_level_changed.connect(func(_l: float) -> void: _refresh())
	EventBus.game_started.connect(_refresh)


## Các kho và khu dân cư có ô đang ngập.
func flooded_node_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in GraphManager.get_node_ids():
		var n = GraphManager.get_map_node(id)
		if n != null and n.kind != Types.NodeKind.ROAD and FloodManager.depth_at(GraphManager.cell_of(n.pos)) >= FloodManager.DRY_EPSILON:
			ids.append(id)
	return ids


func wet_cell_count() -> int:
	return _wet.size()


func _refresh() -> void:
	var wet: Array[Vector2] = []
	var deep: Array[Vector2] = []
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			var cell := Vector2i(x, y)
			if FloodManager.is_sea(cell):
				continue
			var d := FloodManager.depth_at(cell)
			if d < FloodManager.DRY_EPSILON:
				continue
			var c := GraphManager.cell_center(cell)
			wet.append(c)
			if d >= Config.SHALLOW_MAX:
				deep.append(c)
	if wet != _wet or deep != _deep:
		_wet = wet
		_deep = deep
		queue_redraw()


func _draw() -> void:
	var r := Config.CELL_SIZE * RADIUS_RATIO
	for c in _wet:
		draw_circle(c, r, SHALLOW_COLOR)
	for c in _deep:
		draw_circle(c, r, DEEP_COLOR)
