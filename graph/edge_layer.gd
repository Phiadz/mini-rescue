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

const CASING_WIDTH := 26.0  # đường chiếm khoảng nửa ô như Mini Motorways (trước 32/28, đè gần kín lô đất của nhà)
const ROAD_WIDTH := 22.0
const MARK_WIDTH := 2.0
const SHALLOW_MARK_WIDTH := 4.0
const DASH := 8.0
const SHALLOW_DASH := 9.0
const DRIVEWAY_TUCK := 3.0  # lối vào lấn vào dưới mép icon vài px cho liền với tòa nhà
const CURVE_STEPS := 6  # số đoạn thẳng xấp xỉ mỗi nửa đường cong ở chỗ rẽ
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
	var pieces := _pieces()
	for p in pieces:
		_poly(p, _casing(p.state), CASING_WIDTH)
	for p in pieces:
		_poly(p, _fill(p.state), ROAD_WIDTH)
	for p in pieces:
		_mark_poly(p)


# Đường mềm như Mini Motorways: mỗi cạnh chia đôi ở giữa. Ô đường chỉ có 2 nhánh (đường đi qua) thì nối trung điểm hai
# cạnh bằng đường cong Bézier bậc 2 nhận tâm ô làm điểm điều khiển, nên chỗ rẽ thành cung tròn thay vì gãy góc.
# Ngã ba, ngã tư, điểm (kho, khu, nhà), ô cụt: nửa cạnh thẳng từ tâm (điểm có cổng: từ mép tòa nhà) ra trung điểm.
# Mỗi mảnh mang trạng thái ngập của cạnh của nó, nên chỗ đổi màu vẫn đúng giữa hai cạnh.
func _pieces() -> Array:
	var out := []
	var nodes := {}
	for eid in GraphManager.get_edge_ids():
		var e := GraphManager.get_edge(eid)
		nodes[e.node_a] = true
		nodes[e.node_b] = true
	for id in nodes:
		var edges := GraphManager.get_edges_of(id)
		var n := GraphManager.get_map_node(id)
		if n.kind == Types.NodeKind.ROAD and edges.size() == 2:
			var e1 := GraphManager.get_edge(edges[0])
			var e2 := GraphManager.get_edge(edges[1])
			var m1 := _mid(e1)
			var m2 := _mid(e2)
			out.append({points = _bezier(m1, n.pos, m2, 0.0, 0.5), state = e1.state, cap_a = true, cap_b = true})
			out.append({points = _bezier(m1, n.pos, m2, 0.5, 1.0), state = e2.state, cap_a = true, cap_b = true})
		else:
			for eid in edges:
				var e := GraphManager.get_edge(eid)
				var other := e.other_end(id)
				out.append({points = PackedVector2Array([_end(id, other), _mid(e)]), state = e.state,
						cap_a = not _is_gated_point(id), cap_b = true})
	return out


func _mid(e: Edge) -> Vector2:
	return (_pos(e.node_a) + _pos(e.node_b)) / 2.0


# Các điểm trên đường cong Bézier bậc 2 (a, điều khiển c, b) với t từ t0 tới t1.
func _bezier(a: Vector2, c: Vector2, b: Vector2, t0: float, t1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in CURVE_STEPS + 1:
		var t := lerpf(t0, t1, float(k) / CURVE_STEPS)
		pts.append(a * (1.0 - t) * (1.0 - t) + c * 2.0 * (1.0 - t) * t + b * t * t)
	return pts


# Vẽ một mảnh đường, hai đầu bo tròn (trừ đầu ở mép tòa nhà) để các mảnh nối nhau liền mạch.
func _poly(p: Dictionary, color: Color, width: float) -> void:
	var pts: PackedVector2Array = p.points
	if p.cap_a:
		draw_circle(pts[0], width / 2.0, color)
	if p.cap_b:
		draw_circle(pts[pts.size() - 1], width / 2.0, color)
	draw_polyline(pts, color, width, true)


# Vạch giữa đường theo trạng thái ngập, kẻ đứt dọc theo mảnh (thẳng hoặc cong).
func _mark_poly(p: Dictionary) -> void:
	match p.state:
		Types.EdgeState.SHALLOW:
			_dashed(p.points, SHALLOW_MARK_COLOR, SHALLOW_MARK_WIDTH, SHALLOW_DASH)
		Types.EdgeState.DEEP:
			_dashed(p.points, DEEP_MARK_COLOR, MARK_WIDTH, DASH * 2.0)
		_:
			_dashed(p.points, DRY_MARK_COLOR, MARK_WIDTH, DASH)


func _dashed(pts: PackedVector2Array, color: Color, width: float, dash: float) -> void:
	var on := true
	var left := dash
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		var pos := 0.0
		while pos < seg - 0.001:
			var step := minf(left, seg - pos)
			if on:
				draw_line(a.lerp(b, pos / seg), a.lerp(b, (pos + step) / seg), color, width)
			pos += step
			left -= step
			if left <= 0.001:
				on = not on
				left = dash


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


# Bản đồ có cổng: đoạn nối điểm với đường bắt đầu từ mép trước của tòa nhà (lối vào), không vẽ dưới nhà
# và không có đầu tròn ở tâm nhà, để nhà không trông như nằm trên đường.
func _is_gated_point(id: int) -> bool:
	var n := GraphManager.get_map_node(id)
	return GraphManager.uses_gates() and n != null and n.kind != Types.NodeKind.ROAD and n.gate != Vector2i.ZERO


# Đầu mút đoạn đường ở node id (hướng về node other): điểm có cổng thì lùi ra mép trước tòa nhà.
func _end(id: int, other: int) -> Vector2:
	var p := _pos(id)
	if not _is_gated_point(id):
		return p
	return p + p.direction_to(_pos(other)) * (GraphManager.point_radius(id) - DRIVEWAY_TUCK)
