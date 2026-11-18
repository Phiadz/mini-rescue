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
# Màu đường ngập sâu đang dùng. Mặc định là ba màu trên. Bản đồ kiểu lưới (terrain.style = "grid") pha màu đường với
# màu nước sâu thành màu đặc nhạt, trông như đường chìm dưới nước; pha sẵn chứ không vẽ trong suốt, để chỗ các mảnh
# đường chồng nhau không đậm lên. Đường chìm không có viền (viền trong suốt, mặt đường giữ nguyên bề rộng).
static var deep_fill := DEEP_COLOR
static var deep_casing := DEEP_CASING
static var deep_mark := DEEP_MARK_COLOR
const SUNK_FILL := 0.0    # mặt đường: trùng hẳn màu nước sâu (0 = không pha trắng)
const SUNK_MARK := 0.5    # vạch: màu nước pha trắng chừng này
# Cầu (bản đồ kiểu lưới): đường chưa ngập sâu mà nằm trên mặt nước (sông hoặc vùng lũ) có lan can tối hai bên.
static var bridges := false
const RAIL_COLOR := Color('#55656f')
const RAIL_WIDTH := 3.0
const RAIL_STEP := 3.0      # khoảng lấy mẫu dọc đường khi tìm đoạn nằm trên nước (px)
const WATER_CORNER := 20.0  # bán kính bo góc mặt nước, giống radius trong water_grid.gdshader
var _wet_sig := PackedByteArray()  # ô nào đang có nước (FloodManager.wet_mask), để chỉ vẽ lại khi mặt nước đổi và để vẽ cầu
var _pieces_cache: Array = []     # mảnh đường dựng ở khung hình _pieces_frame, dùng chung cho _draw và _draw_sunk
var _pieces_frame := -1
# Thứ tự vẽ (z_index): nền Terrain -20, lớp lũ FloodOverlay -19 (main.tscn), đường chìm SUNK_Z, ca-nô luồn dưới cầu
# RescueManager.BOAT_UNDER_Z, rồi đường thường (lớp này, z 0), điểm, xe. Bản đồ kiểu lưới: đường ngập sâu vẽ ở lớp con
# _sunk nên ca-nô hiện trên đường chìm nhưng luồn dưới cầu (đường chưa ngập sâu trên mặt nước).
const SUNK_Z := -8
var _sunk: Node2D
var _ci: CanvasItem  # nơi các hàm vẽ mảnh đường vẽ vào: lớp này, hoặc _sunk

const CASING_WIDTH := 26.0  # đường chiếm khoảng nửa ô như Mini Motorways (trước 32/28, đè gần kín lô đất của nhà)
const ROAD_WIDTH := 22.0
const MARK_WIDTH := 2.0
const SHALLOW_MARK_WIDTH := 4.0
const DASH := 8.0
const SHALLOW_DASH := 9.0
const DRIVEWAY_TUCK := 3.0  # lối vào lấn vào dưới mép icon vài px cho liền với tòa nhà
const CURVE_STEPS := 6  # số đoạn thẳng xấp xỉ mỗi nửa đường cong ở chỗ rẽ


func _init() -> void:
	_ci = self


func _ready() -> void:
	_sunk = Node2D.new()
	_sunk.name = 'Sunk'
	_sunk.z_index = SUNK_Z
	_sunk.draw.connect(_draw_sunk)
	add_child(_sunk)
	EventBus.game_started.connect(func() -> void: apply_terrain(GraphManager.get_terrain()))
	EventBus.road_changed.connect(_redraw)
	EventBus.game_started.connect(_redraw)
	EventBus.edge_state_changed.connect(func(id: int, _state: int) -> void:
		var e := GraphManager.get_edge(id)
		if e == null or not e.boat_only:  # cạnh của riêng ca-nô (sông, vùng ngập) không vẽ ở đây
			_redraw())
	EventBus.water_level_changed.connect(func(_l: float) -> void: _check_water())


func _draw() -> void:
	for id in GraphManager.get_road_ids():
		if GraphManager.get_edges_of(id).is_empty():  # ô lẻ chưa nối với gì
			var p := GraphManager.get_map_node(id).pos
			draw_circle(p, CASING_WIDTH / 2.0, DRY_CASING)
			draw_circle(p, ROAD_WIDTH / 2.0, DRY_COLOR)
	_draw_stubs()
	var pieces := _frame_pieces()
	if bridges:  # đường chìm vẽ ở lớp _sunk (dưới ca-nô)
		pieces = pieces.filter(func(p: Dictionary) -> bool: return p.state != Types.EdgeState.DEEP)
	for p in pieces:
		_poly(p, _casing(p.state), CASING_WIDTH)
	if bridges:  # lan can vẽ trước mặt đường: ở ngã ba, ngã tư mặt đường của nhánh khác che đi
		for p in pieces:
			if p.state != Types.EdgeState.DEEP:
				_rails(p.points)
	for p in pieces:
		_poly(p, _fill(p.state), ROAD_WIDTH)
	for p in pieces:
		_mark_poly(p)


# Lớp _sunk: các mảnh đường ngập sâu của bản đồ kiểu lưới (không viền, trùng màu nước, vạch nhạt).
func _draw_sunk() -> void:
	if not bridges:
		return
	var sunk := _frame_pieces().filter(func(p: Dictionary) -> bool: return p.state == Types.EdgeState.DEEP)
	_ci = _sunk
	for p in sunk:
		_poly(p, deep_fill, ROAD_WIDTH)
	for p in sunk:
		_mark_poly(p)
	_ci = self


# Mảnh đường của khung hình này (dựng một lần cho cả lớp đường và lớp đường chìm).
func _frame_pieces() -> Array:
	var f := Engine.get_frames_drawn()
	if f != _pieces_frame:
		_pieces_frame = f
		_pieces_cache = _pieces()
	return _pieces_cache


func _redraw() -> void:
	_pieces_frame = -1
	queue_redraw()
	if _sunk != null:
		_sunk.queue_redraw()


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
		_ci.draw_circle(pts[0], width / 2.0, color)
	if p.cap_b:
		_ci.draw_circle(pts[pts.size() - 1], width / 2.0, color)
	_ci.draw_polyline(pts, color, width, true)


# Vạch giữa đường theo trạng thái ngập, kẻ đứt dọc theo mảnh (thẳng hoặc cong).
func _mark_poly(p: Dictionary) -> void:
	match p.state:
		Types.EdgeState.SHALLOW:
			_dashed(p.points, SHALLOW_MARK_COLOR, SHALLOW_MARK_WIDTH, SHALLOW_DASH)
		Types.EdgeState.DEEP:
			_dashed(p.points, deep_mark, MARK_WIDTH, DASH * 2.0)
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
				_ci.draw_line(a.lerp(b, pos / seg), a.lerp(b, (pos + step) / seg), color, width)
			pos += step
			left -= step
			if left <= 0.001:
				on = not on
				left = dash


# Lối vào ngắn của khu, nhà chưa nối đường (bản đồ có cổng): từ mép lô đất tới đúng mép ô theo hướng gate, đầu vuông,
# nằm gọn trong ô của nhà (không lòi sang ô bên cạnh).
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
		var b := n.pos + d * (Config.CELL_SIZE / 2.0)
		for pass_ in [[DRY_CASING, CASING_WIDTH], [DRY_COLOR, ROAD_WIDTH]]:
			draw_line(a, b, pass_[0], pass_[1])


func _casing(state: int) -> Color:
	match state:
		Types.EdgeState.SHALLOW:
			return SHALLOW_CASING
		Types.EdgeState.DEEP:
			return deep_casing
	return DRY_CASING


func _fill(state: int) -> Color:
	match state:
		Types.EdgeState.SHALLOW:
			return SHALLOW_COLOR
		Types.EdgeState.DEEP:
			return deep_fill
	return DRY_COLOR


# Chọn màu đường ngập sâu theo khóa "terrain" của bản đồ (gọi lại nhiều lần vẫn vậy).
static func apply_terrain(t: Dictionary) -> void:
	if t.get("style", "") == "grid" and t.has("deep"):
		var water := Color(t["deep"])
		deep_fill = water.lerp(Color.WHITE, SUNK_FILL)
		deep_casing = Color(water, 0.0)
		deep_mark = water.lerp(Color.WHITE, SUNK_MARK)
		bridges = true
	else:
		bridges = false
		deep_fill = DEEP_COLOR
		deep_casing = DEEP_CASING
		deep_mark = DEEP_MARK_COLOR


# Lan can hai bên những đoạn của mảnh đường nằm trên mặt nước.
func _rails(pts: PackedVector2Array) -> void:
	var runs := []  # mỗi đoạn trên nước: [các điểm tâm đường, pháp tuyến tại từng điểm]
	var cur := PackedVector2Array()
	var cur_n := PackedVector2Array()
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var n := (b - a).orthogonal().normalized()
		var steps := maxi(1, ceili(seg / RAIL_STEP))
		for i in range(1 if k > 0 else 0, steps + 1):
			var q := a.lerp(b, float(i) / steps)
			if _over_water(q):
				cur.append(q)
				cur_n.append(n)
			elif not cur.is_empty():
				runs.append([cur, cur_n])
				cur = PackedVector2Array()
				cur_n = PackedVector2Array()
	if not cur.is_empty():
		runs.append([cur, cur_n])
	var off := (ROAD_WIDTH + RAIL_WIDTH) / 2.0
	for r in runs:
		var c: PackedVector2Array = r[0]
		var nn: PackedVector2Array = r[1]
		if c.size() < 2:
			continue
		for side in [1.0, -1.0]:
			var line := PackedVector2Array()
			for i in c.size():
				line.append(c[i] + nn[i] * off * side)
			draw_polyline(line, RAIL_COLOR, RAIL_WIDTH, true)


func _wet_cell(c: Vector2i) -> bool:
	c = Vector2i(clampi(c.x, 0, Config.GRID_COLS - 1), clampi(c.y, 0, Config.GRID_ROWS - 1))
	var i := c.y * Config.GRID_COLS + c.x
	if i < _wet_sig.size():
		return _wet_sig[i] == 1  # mặt nạ đã có: tra bảng, không gọi FloodManager
	return FloodManager.is_sea(c) or FloodManager.depth_at(c) >= FloodManager.DRY_EPSILON


# Điểm p có nằm trên mặt nước không, theo đúng luật bo góc của nền và lớp lũ (water_grid.gdshader).
func _over_water(p: Vector2) -> bool:
	var cs := float(Config.CELL_SIZE)
	var c := Vector2i(floori(p.x / cs), floori(p.y / cs))
	var l := p - Vector2(c) * cs
	var s := Vector2i(-1 if l.x < cs / 2.0 else 1, -1 if l.y < cs / 2.0 else 1)
	var e := Vector2(l.x if s.x < 0 else cs - l.x, l.y if s.y < 0 else cs - l.y)
	var a := _wet_cell(c)
	if e.x >= WATER_CORNER or e.y >= WATER_CORNER:
		return a
	var h := _wet_cell(c + Vector2i(s.x, 0))
	var v := _wet_cell(c + Vector2i(0, s.y))
	var d := _wet_cell(c + s)
	var in_circle := (Vector2.ONE * WATER_CORNER - e).length_squared() <= WATER_CORNER * WATER_CORNER
	if a:
		return h or v or d or in_circle
	return h and v and not in_circle


# Mặt nước đổi (lũ lan, rút) thì vẽ lại để lan can cầu theo kịp.
func _check_water() -> void:
	if not bridges:
		return
	var sig := FloodManager.wet_mask()
	if sig != _wet_sig:
		_wet_sig = sig
		_redraw()


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
