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
const DRIVEWAY_TUCK := 3.0  # lối vào lấn vào dưới mép icon vài px cho liền với tòa nhà
const DRIVEWAY_STUB := 9.0  # khu, nhà chưa nối đường: lối vào nhô ra khỏi mép nhà chừng này px (như Mini Motorways)


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
	_draw_stubs()
	var edges := GraphManager.get_edge_ids()
	for eid in edges:
		var e := GraphManager.get_edge(eid)
		_stroke(e, _casing(e.state), CASING_WIDTH)
	for eid in edges:
		var e := GraphManager.get_edge(eid)
		_stroke(e, _fill(e.state), ROAD_WIDTH)
	for eid in edges:
		_mark(GraphManager.get_edge(eid))


# Lối vào ngắn của khu, nhà chưa nối đường (bản đồ có cổng): từ mép nhà nhô ra một chút theo hướng gate, đầu bo tròn.
# Nối đường vào từ cạnh nào thì GraphManager xoay gate về cạnh đó; đã nối thì đoạn đường nối thay cho lối vào này.
func _draw_stubs() -> void:
	if not GraphManager.uses_gates():
		return
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if n == null or n.kind == Types.NodeKind.HUB or n.gate == Vector2i.ZERO or GraphManager.get_gate_node(id) != -1:
			continue
		var d := Vector2(n.gate)
		var r := GraphManager.point_radius(id)
		var a := n.pos + d * (r - DRIVEWAY_TUCK)
		var b := n.pos + d * (r + DRIVEWAY_STUB)
		for pass_ in [[DRY_CASING, CASING_WIDTH], [DRY_COLOR, ROAD_WIDTH]]:
			draw_line(a, b, pass_[0], pass_[1])
			draw_circle(b, pass_[1] / 2.0, pass_[0])


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
# Bản đồ có cổng: đoạn nối điểm với ô cổng bắt đầu từ mép trước của tòa nhà (lối vào), không vẽ dưới nhà
# và không có đầu tròn ở tâm nhà, để nhà không trông như nằm trên đường.
func _stroke(e: Edge, color: Color, width: float) -> void:
	var a := _end(e.node_a, e.node_b)
	var b := _end(e.node_b, e.node_a)
	if not _is_gated_point(e.node_a):
		draw_circle(a, width / 2.0, color)
	if not _is_gated_point(e.node_b):
		draw_circle(b, width / 2.0, color)
	draw_line(a, b, color, width, true)


func _is_gated_point(id: int) -> bool:
	var n := GraphManager.get_map_node(id)
	return GraphManager.uses_gates() and n != null and n.kind != Types.NodeKind.ROAD and n.gate != Vector2i.ZERO


# Đầu mút đoạn đường ở node id (hướng về node other): điểm có cổng thì lùi ra mép trước tòa nhà.
func _end(id: int, other: int) -> Vector2:
	var p := _pos(id)
	if not _is_gated_point(id):
		return p
	return p + p.direction_to(_pos(other)) * (GraphManager.point_radius(id) - DRIVEWAY_TUCK)


func _mark(e: Edge) -> void:
	var a := _end(e.node_a, e.node_b)
	var b := _end(e.node_b, e.node_a)
	match e.state:
		Types.EdgeState.SHALLOW:
			draw_dashed_line(a, b, SHALLOW_MARK_COLOR, SHALLOW_MARK_WIDTH, SHALLOW_DASH)
		Types.EdgeState.DEEP:
			draw_dashed_line(a, b, DEEP_MARK_COLOR, MARK_WIDTH, DASH * 2.0)
		_:
			draw_dashed_line(a, b, DRY_MARK_COLOR, MARK_WIDTH, DASH)
