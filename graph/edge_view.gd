class_name EdgeView extends Node2D
# Chủ sở hữu: E. Vẽ một tuyến theo trạng thái (Tài liệu chốt 1.4, 1.10):
# khô là nét liền vàng, ngập nhẹ là nét đứt, ngập sâu là nét liền xanh và dày hơn.

const DRY_COLOR := Color('#FFD700')
const DEEP_COLOR := Color('#0073E6')
const WIDTH := 4.0
const DEEP_WIDTH := 6.0
const DASH := 12.0

var edge_id: int


func _ready() -> void:
	EventBus.edge_state_changed.connect(_on_state_changed)
	queue_redraw()


func _on_state_changed(id: int, _state: int) -> void:
	if id == edge_id:
		queue_redraw()


func _draw() -> void:
	var e := GraphManager.get_edge(edge_id)
	if e == null:
		return  # cạnh vừa bị xóa, chờ EdgeLayer queue_free
	var a := GraphManager.get_map_node(e.node_a).pos
	var b := GraphManager.get_map_node(e.node_b).pos
	match e.state:
		Types.EdgeState.SHALLOW:
			draw_dashed_line(a, b, DRY_COLOR, WIDTH, DASH)
		Types.EdgeState.DEEP:
			draw_line(a, b, DEEP_COLOR, DEEP_WIDTH)
		_:
			draw_line(a, b, DRY_COLOR, WIDTH)
