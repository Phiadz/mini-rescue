class_name FloodOverlay
extends Node2D
## Lớp phủ nước (module B). Chỉ vẽ, không sửa dữ liệu đồ thị.
## - Phủ màu nước lên cả bản đồ, đậm dần theo mực nước (độ mờ 0,05 khi nước vừa dâng, 0,35 ở mức 100).
## - Vẽ quầng nước bán kính 40 px quanh mỗi kho và khu dân cư đã thấp hơn mực nước; ngập càng sâu quầng càng đậm.
## Nằm dưới EdgeLayer và NodeLayer trong main.tscn nên đường, điểm và xe vẫn vẽ đè lên trên.

const WATER := Color("#0073E6")
const MAP_SIZE := Vector2(1280, 720)
const HALO_RADIUS := 40.0
const ALPHA_MIN := 0.05
const ALPHA_MAX := 0.35

var _level := 0.0


func _ready() -> void:
	EventBus.water_level_changed.connect(_on_water_level)
	EventBus.game_started.connect(func() -> void: _on_water_level(0.0))


func _on_water_level(level: float) -> void:
	if is_equal_approx(level, _level):
		return
	_level = level
	queue_redraw()


## Độ mờ của lớp phủ theo mực nước (thang 0–100). Nước chưa dâng thì không phủ.
static func water_alpha(level: float) -> float:
	if level <= 0.0:
		return 0.0
	return lerpf(ALPHA_MIN, ALPHA_MAX, clampf(level / 100.0, 0.0, 1.0))


## Các kho và khu dân cư có độ cao thấp hơn mực nước hiện tại (bỏ qua ô đường).
func flooded_node_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in GraphManager.get_node_ids():
		var n = GraphManager.get_map_node(id)
		if n != null and n.kind != Types.NodeKind.ROAD and n.elevation < _level:
			ids.append(id)
	return ids


func _draw() -> void:
	if _level <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(WATER, water_alpha(_level)))
	for id in flooded_node_ids():
		var n = GraphManager.get_map_node(id)
		var depth: float = _level - n.elevation
		var a: float = clampf(0.25 + depth / 60.0, 0.25, 0.6)
		draw_circle(n.pos, HALO_RADIUS, Color(WATER, a * 0.6))
		draw_arc(n.pos, HALO_RADIUS, 0.0, TAU, 48, Color(WATER.lightened(0.4), a), 2.0)
