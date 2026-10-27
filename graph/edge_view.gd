class_name EdgeView extends Node2D
# Chủ sở hữu: E. Vẽ một tuyến như một con đường, theo trạng thái (Tài liệu chốt 1.4) và kiểu bản Vector MVP:
# khô là đường xám có viền tối và vạch trắng giữa; ngập nhẹ (cạn) là lòng đường tối với vạch đứt vàng;
# ngập sâu là đường xanh dương. Phân biệt cả bằng kiểu nét (liền / đứt), không chỉ bằng màu (1.10).

const CASING_COLOR := Color('#0d1726')       # viền tối hai bên đường
const DRY_COLOR := Color('#aeb8c4')          # mặt đường khô
const DRY_MARK_COLOR := Color(1, 1, 1, 0.75) # vạch trắng giữa đường khô
const SHALLOW_COLOR := Color('#1f2b3c')      # lòng đường ngập nhẹ
const SHALLOW_MARK_COLOR := Color('#e9c85c') # vạch đứt vàng của đường ngập nhẹ
const DEEP_COLOR := Color('#3a8fd0')         # đường ngập sâu
const DEEP_MARK_COLOR := Color('#9fd6f5')    # vệt sóng nhạt giữa đường ngập sâu

const CASING_WIDTH := 13.0
const ROAD_WIDTH := 9.0
const MARK_WIDTH := 1.6
const SHALLOW_MARK_WIDTH := 4.0
const DASH := 10.0
const SHALLOW_DASH := 9.0

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
			_road(a, b, SHALLOW_COLOR)
			draw_dashed_line(a, b, SHALLOW_MARK_COLOR, SHALLOW_MARK_WIDTH, SHALLOW_DASH)
		Types.EdgeState.DEEP:
			_road(a, b, DEEP_COLOR)
			draw_dashed_line(a, b, DEEP_MARK_COLOR, MARK_WIDTH, DASH * 2.0)
		_:
			_road(a, b, DRY_COLOR)
			draw_dashed_line(a, b, DRY_MARK_COLOR, MARK_WIDTH, DASH)


# Mặt đường có viền tối, hai đầu bo tròn để chỗ nối nhiều tuyến vào một điểm trông liền mạch.
func _road(a: Vector2, b: Vector2, fill: Color) -> void:
	for p in [a, b]:
		draw_circle(p, CASING_WIDTH / 2.0, CASING_COLOR)
	draw_line(a, b, CASING_COLOR, CASING_WIDTH)
	for p in [a, b]:
		draw_circle(p, ROAD_WIDTH / 2.0, fill)
	draw_line(a, b, fill, ROAD_WIDTH)
