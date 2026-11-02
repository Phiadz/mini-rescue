extends Node2D
# Chủ sở hữu: E. Vẽ toàn bộ đường theo trạng thái (Tài liệu chốt 1.4), kiểu tối giản trên nền sáng:
# khô là đường trắng viền xám xanh; ngập nhẹ là đường vàng nhạt với vạch đứt nâu đậm;
# ngập sâu là đường xanh dương viền đậm. Phân biệt cả bằng kiểu nét (liền / đứt), không chỉ bằng màu (1.10).
# Đường rộng đủ hai làn, vạch giữa là vạch chia làn.
# Một node vẽ cả mạng theo ba lượt (viền, mặt đường, vạch) để viền của ô sau không đè lên mặt đường ô trước.

const DRY_CASING := Color('#b9cdd6')
const DRY_COLOR := Color('#fbfaf6')          # mặt đường khô
const DRY_MARK_COLOR := Color('#cfd9de')     # vạch chia làn đường khô
const SHALLOW_CASING := Color('#c9a24a')
const SHALLOW_COLOR := Color('#f7e6ae')      # đường ngập nhẹ
const SHALLOW_MARK_COLOR := Color('#b9862b') # vạch đứt đậm của đường ngập nhẹ
const DEEP_CASING := Color('#2f6f9f')
const DEEP_COLOR := Color('#5aa7d6')         # đường ngập sâu
const DEEP_MARK_COLOR := Color('#d8f0fb')    # vệt sóng nhạt giữa đường ngập sâu

const CASING_WIDTH := 32.0
const ROAD_WIDTH := 28.0
const MARK_WIDTH := 2.0
const SHALLOW_MARK_WIDTH := 4.0
const DASH := 10.0
const SHALLOW_DASH := 9.0


func _ready() -> void:
	EventBus.road_changed.connect(queue_redraw)
	EventBus.game_started.connect(queue_redraw)
	EventBus.edge_state_changed.connect(func(_id: int, _state: int) -> void: queue_redraw())


func _draw() -> void:
	for id in GraphManager.get_road_ids():
		if GraphManager.get_edges_of(id).is_empty():  # ô lẻ chưa nối với gì
			var p := GraphManager.get_map_node(id).pos
			draw_circle(p, CASING_WIDTH / 2.0, DRY_CASING)
			draw_circle(p, ROAD_WIDTH / 2.0, DRY_COLOR)
	var edges := GraphManager.get_edge_ids()
	for eid in edges:
		var e := GraphManager.get_edge(eid)
		_stroke(e, _casing(e.state), CASING_WIDTH)
	for eid in edges:
		var e := GraphManager.get_edge(eid)
		_stroke(e, _fill(e.state), ROAD_WIDTH)
	for eid in edges:
		_mark(GraphManager.get_edge(eid))


func _casing(state: int) -> Color:
	match state:
		Types.EdgeState.SHALLOW:
			return SHALLOW_CASING
		Types.EdgeState.DEEP:
			return DEEP_CASING
	return DRY_CASING


func _fill(state: int) -> Color:
	match state:
		Types.EdgeState.SHALLOW:
			return SHALLOW_COLOR
		Types.EdgeState.DEEP:
			return DEEP_COLOR
	return DRY_COLOR


func _pos(id: int) -> Vector2:
	return GraphManager.get_map_node(id).pos


# Hai đầu bo tròn để chỗ rẽ và chỗ nối nhiều đường vào một điểm trông liền mạch.
func _stroke(e: Edge, color: Color, width: float) -> void:
	var a := _pos(e.node_a)
	var b := _pos(e.node_b)
	draw_circle(a, width / 2.0, color)
	draw_circle(b, width / 2.0, color)
	draw_line(a, b, color, width, true)


func _mark(e: Edge) -> void:
	var a := _pos(e.node_a)
	var b := _pos(e.node_b)
	match e.state:
		Types.EdgeState.SHALLOW:
			draw_dashed_line(a, b, SHALLOW_MARK_COLOR, SHALLOW_MARK_WIDTH, SHALLOW_DASH)
		Types.EdgeState.DEEP:
			draw_dashed_line(a, b, DEEP_MARK_COLOR, MARK_WIDTH, DASH * 2.0)
		_:
			draw_dashed_line(a, b, DRY_MARK_COLOR, MARK_WIDTH, DASH)
