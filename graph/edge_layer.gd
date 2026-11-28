extends Node2D
# Chủ sở hữu: E. Vẽ toàn bộ đường theo trạng thái (Tài liệu chốt 1.4), kiểu tối giản trên nền sáng:
# khô là đường trắng viền xám xanh; ngập nhẹ là đường vàng nhạt với vạch đứt nâu đậm;
# ngập sâu là đường xanh dương viền đậm. Phân biệt cả bằng kiểu nét (liền / đứt), không chỉ bằng màu (1.10).
# Đường rộng đủ hai làn, vạch giữa là vạch chia làn.
# Vẽ theo lượt: viền (lớp con _casing_ci), lan can cầu (lớp con _rails_ci), rồi mặt đường và vạch (lớp này), để viền
# của nét sau không đè lên mặt đường nét trước. Hai lớp con vẽ sau lưng lớp này (show_behind_parent).
# Hiệu năng (bản web): các mảnh nửa cạnh liền nhau cùng trạng thái được gộp thành một nét dài (chỉ đứt ở ngã ba, ngã
# tư, điểm, chỗ đổi trạng thái), vạch kẻ mỗi kiểu một lệnh draw_multiline; nét, vạch, lan can dựng một lần mỗi khi
# đường hay trạng thái đổi (bộ đệm), mặt nước đổi thì chỉ dựng lại lan can, và chỉ khi ô có nước nằm sát đường.

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
var _wet_sig := PackedByteArray()  # ô nào đang có nước (FloodManager.wet_mask), tra khi dựng lan can cầu
var _near_cells := PackedInt32Array()  # ô nằm sát đường (3 × 3 quanh điểm của nét): chỉ các ô này đổi nước mới dựng lại lan can
var _near_sig := PackedByteArray()     # nước ở các ô _near_cells lần dựng lan can trước
var _strokes: Array = []   # nét đường: {points, state, cap_a, cap_b}
var _dashes := {}          # trạng thái -> PackedVector2Array các cặp điểm đầu, cuối của từng gạch vạch kẻ
var _rail_lines: Array = []  # PackedVector2Array: lan can hai bên các đoạn đường trên mặt nước
var _dirty := true         # đường hoặc trạng thái đổi: dựng lại nét, vạch, lan can ở lần vẽ tới
var _rails_dirty := true
var _road_sig := PackedInt64Array()  # cạnh, hai đầu, trạng thái lần dựng trước: không đổi thì khỏi dựng lại (vd. nhà mới mọc)
var _casing_ci: Node2D
var _rails_ci: Node2D
# Thứ tự vẽ (z_index): nền Terrain -20, lớp lũ FloodOverlay -19 (main.tscn), đường chìm SUNK_Z, ca-nô luồn dưới cầu
# RescueManager.BOAT_UNDER_Z, rồi đường thường (lớp này, z 0), điểm, xe. Bản đồ kiểu lưới: đường ngập sâu vẽ ở lớp con
# _sunk nên ca-nô hiện trên đường chìm nhưng luồn dưới cầu (đường chưa ngập sâu trên mặt nước).
const SUNK_Z := -8
var _sunk: Node2D
var _highway_layer: Node2D

const CASING_WIDTH := 26.0  # đường chiếm khoảng nửa ô như Mini Motorways (trước 32/28, đè gần kín lô đất của nhà)
const ROAD_WIDTH := 22.0
const HIGHWAY_SHADOW := Color("#466170")
const HIGHWAY_RAIL := Color("#344d61")
const HIGHWAY_SURFACE := Color("#c1d7e8")
const HIGHWAY_MARK := Color("#f6fbff")
const MARK_WIDTH := 2.0
const SHALLOW_MARK_WIDTH := 4.0
const DASH := 8.0
const SHALLOW_DASH := 9.0
const DRIVEWAY_TUCK := 3.0  # lối vào lấn vào dưới mép icon vài px cho liền với tòa nhà
const CURVE_STEPS := 6  # số đoạn thẳng xấp xỉ mỗi nửa đường cong ở chỗ rẽ


func _ready() -> void:
	_highway_layer = Node2D.new()
	_highway_layer.name = "Highways"
	_highway_layer.draw.connect(_draw_highways)
	add_child(_highway_layer)
	_sunk = Node2D.new()
	_sunk.name = 'Sunk'
	_sunk.z_index = SUNK_Z
	_sunk.draw.connect(_draw_sunk)
	add_child(_sunk)
	_casing_ci = Node2D.new()
	_casing_ci.name = 'Casing'
	_casing_ci.show_behind_parent = true
	_casing_ci.draw.connect(_draw_casing)
	add_child(_casing_ci)
	_rails_ci = Node2D.new()
	_rails_ci.name = 'Rails'
	_rails_ci.show_behind_parent = true
	_rails_ci.draw.connect(_draw_rails)
	add_child(_rails_ci)
	EventBus.game_started.connect(func() -> void: apply_terrain(GraphManager.get_terrain()))
	EventBus.road_changed.connect(_redraw)
	EventBus.game_started.connect(_redraw)
	EventBus.edge_state_changed.connect(func(id: int, _state: int) -> void:
		var e := GraphManager.get_edge(id)
		if e == null or not e.boat_only:  # cạnh của riêng ca-nô (sông, vùng ngập) không vẽ ở đây
			_redraw())
	EventBus.water_level_changed.connect(func(_l: float) -> void: _check_water())


func _draw() -> void:
	_ensure()
	for id in GraphManager.get_road_ids():
		if GraphManager.get_edges_of(id).is_empty():  # ô lẻ chưa nối với gì
			var p := GraphManager.get_map_node(id).pos
			draw_circle(p, CASING_WIDTH / 2.0, DRY_CASING)
			draw_circle(p, ROAD_WIDTH / 2.0, DRY_COLOR)
	_draw_stubs()
	for s in _strokes:
		if not (bridges and s.state == Types.EdgeState.DEEP):
			_stroke(self, s, _fill(s.state), ROAD_WIDTH)
	for st in [Types.EdgeState.DRY, Types.EdgeState.SHALLOW, Types.EdgeState.DEEP]:
		if not (bridges and st == Types.EdgeState.DEEP):
			_draw_dashes(self, st)


# Lớp con sau lưng: viền của các nét (đường chìm của bản đồ kiểu lưới không có viền).
func _draw_casing() -> void:
	_ensure()
	for s in _strokes:
		if not (bridges and s.state == Types.EdgeState.DEEP):
			_stroke(_casing_ci, s, _casing(s.state), CASING_WIDTH)


# Lớp con sau lưng, trên viền: lan can cầu (mặt đường của nhánh khác ở ngã ba, ngã tư che đi).
func _draw_rails() -> void:
	_ensure()
	if _rails_dirty:
		_rails_dirty = false
		_build_rails()
	for line in _rail_lines:
		_rails_ci.draw_polyline(line, RAIL_COLOR, RAIL_WIDTH, true)


# Lớp _sunk: các nét đường ngập sâu của bản đồ kiểu lưới (không viền, trùng màu nước, vạch nhạt).
func _draw_sunk() -> void:
	if not bridges:
		return
	_ensure()
	for s in _strokes:
		if s.state == Types.EdgeState.DEEP:
			_stroke(_sunk, s, deep_fill, ROAD_WIDTH)
	_draw_dashes(_sunk, Types.EdgeState.DEEP)


func _draw_highways() -> void:
	for route_id in GraphManager.get_highway_ids():
		var points: PackedVector2Array = GraphManager.get_highway_route(route_id).points
		var shadow := points.duplicate()
		for i in shadow.size():
			shadow[i] += Vector2(0.0, 4.0)
		_highway_layer.draw_polyline(shadow, HIGHWAY_SHADOW, CASING_WIDTH, true)
		_highway_layer.draw_polyline(points, HIGHWAY_RAIL, CASING_WIDTH, true)
		_highway_layer.draw_polyline(points, HIGHWAY_SURFACE, ROAD_WIDTH - 3.0, true)
		var markings := PackedVector2Array()
		_dash_into(markings, points, DASH)
		if not markings.is_empty():
			_highway_layer.draw_multiline(markings, HIGHWAY_MARK, MARK_WIDTH, true)


func _redraw() -> void:
	_dirty = true
	queue_redraw()
	for ci in [_sunk, _casing_ci, _rails_ci, _highway_layer]:
		if ci != null:
			ci.queue_redraw()


# Dựng lại nét, vạch kẻ, danh sách ô sát đường (một lần dù nhiều tín hiệu tới trong cùng khung hình).
func _ensure() -> void:
	if not _dirty:
		return
	_dirty = false
	var sig := _roads_signature()
	if sig == _road_sig and not _strokes.is_empty():
		return  # mạng đường và trạng thái như cũ (vd. nhà mới mọc chỉ đổi lối vào ngắn): giữ nét đã dựng
	_road_sig = sig
	_strokes = _build_strokes(_pieces())
	_dashes = {}
	for st in [Types.EdgeState.DRY, Types.EdgeState.SHALLOW, Types.EdgeState.DEEP]:
		_dashes[st] = PackedVector2Array()
	var near := {}
	for s in _strokes:
		_dash_into(_dashes[s.state], s.points, _dash_len(s.state))
		var mine := {}  # ô quanh nét: lan can chỉ dựng cho nét có ô nước ở gần
		for p in s.points:
			var c := GraphManager.cell_of(p)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var x := c.x + dx
					var y := c.y + dy
					if x >= 0 and y >= 0 and x < Config.GRID_COLS and y < Config.GRID_ROWS:
						mine[y * Config.GRID_COLS + x] = true
		s.cells = PackedInt32Array(mine.keys())
		near.merge(mine)
	_near_cells = PackedInt32Array(near.keys())
	_near_sig = _near_wet()
	_rails_dirty = true


func _roads_signature() -> PackedInt64Array:
	var sig := PackedInt64Array()
	for eid in GraphManager.get_edge_ids():
		var e := GraphManager.get_edge(eid)
		sig.append(eid)
		sig.append(e.node_a)
		sig.append(e.node_b)
		sig.append(e.state)
	return sig


# Gộp các mảnh liền nhau cùng trạng thái thành nét dài: hai mảnh nối nhau khi đúng hai mảnh gặp nhau ở một điểm
# (trung điểm cạnh, hoặc giữa đường cong ở ô đường đi qua). Ở ngã ba, ngã tư (từ ba mảnh) và chỗ đổi trạng thái thì
# nét đứt, hai đầu bo tròn như mảnh gốc.
func _build_strokes(pieces: Array) -> Array:
	var at := {}  # điểm đầu mút (làm tròn 0,25 px) -> [[mảnh, đầu 0 hay 1], ...]
	for i in pieces.size():
		var pts: PackedVector2Array = pieces[i].points
		for end in [0, 1]:
			var q: Vector2 = pts[0] if end == 0 else pts[pts.size() - 1]
			var k := Vector2i(roundi(q.x * 4.0), roundi(q.y * 4.0))
			if not at.has(k):
				at[k] = []
			at[k].append([i, end])
	var link := {}  # Vector2i(mảnh, đầu) -> Vector2i(mảnh kia, đầu kia)
	for k in at:
		var l: Array = at[k]
		if l.size() == 2 and l[0][0] != l[1][0] and pieces[l[0][0]].state == pieces[l[1][0]].state:
			link[Vector2i(l[0][0], l[0][1])] = Vector2i(l[1][0], l[1][1])
			link[Vector2i(l[1][0], l[1][1])] = Vector2i(l[0][0], l[0][1])
	var used := {}
	var out := []
	for pass_ in 2:  # lượt đầu: bắt đầu từ mảnh có đầu tự do; lượt sau: phần còn lại là vòng kín
		for i in pieces.size():
			if used.has(i):
				continue
			var start := 0
			if pass_ == 0:
				if not link.has(Vector2i(i, 0)):
					start = 0
				elif not link.has(Vector2i(i, 1)):
					start = 1
				else:
					continue
			var pts := PackedVector2Array()
			var cur := i
			var enter := start
			var cap_a: bool = pieces[i].cap_a if start == 0 else pieces[i].cap_b
			var cap_b := true
			while true:
				used[cur] = true
				var p: PackedVector2Array = pieces[cur].points
				if enter == 1:
					p = p.duplicate()
					p.reverse()
				pts.append_array(p if pts.is_empty() else p.slice(1))
				var leave := 1 - enter
				cap_b = pieces[cur].cap_b if leave == 1 else pieces[cur].cap_a
				var nx: Vector2i = link.get(Vector2i(cur, leave), Vector2i(-1, -1))
				if nx.x == -1 or used.has(nx.x):
					break
				cur = nx.x
				enter = nx.y
			out.append({points = pts, state = pieces[i].state, cap_a = cap_a, cap_b = cap_b})
	return out


# Một nét đường, hai đầu bo tròn (trừ đầu ở mép tòa nhà).
func _stroke(ci: CanvasItem, s: Dictionary, color: Color, width: float) -> void:
	var pts: PackedVector2Array = s.points
	if s.cap_a:
		ci.draw_circle(pts[0], width / 2.0, color)
	if s.cap_b:
		ci.draw_circle(pts[pts.size() - 1], width / 2.0, color)
	ci.draw_polyline(pts, color, width, true)


func _dash_len(state: int) -> float:
	match state:
		Types.EdgeState.SHALLOW:
			return SHALLOW_DASH
		Types.EdgeState.DEEP:
			return DASH * 2.0
	return DASH


# Vạch giữa đường theo trạng thái ngập: mọi gạch của một kiểu vẽ bằng một lệnh draw_multiline.
func _draw_dashes(ci: CanvasItem, state: int) -> void:
	var segs: PackedVector2Array = _dashes.get(state, PackedVector2Array())
	if segs.is_empty():
		return
	match state:
		Types.EdgeState.SHALLOW:
			ci.draw_multiline(segs, SHALLOW_MARK_COLOR, SHALLOW_MARK_WIDTH)
		Types.EdgeState.DEEP:
			ci.draw_multiline(segs, deep_mark, MARK_WIDTH)
		_:
			ci.draw_multiline(segs, DRY_MARK_COLOR, MARK_WIDTH)


# Cắt nét thành gạch dài dash, cách nhau dash, nối thêm vào out (từng cặp điểm đầu, cuối).
func _dash_into(out: PackedVector2Array, pts: PackedVector2Array, dash: float) -> void:
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
				out.append(a.lerp(b, pos / seg))
				out.append(a.lerp(b, (pos + step) / seg))
			pos += step
			left -= step
			if left <= 0.001:
				on = not on
				left = dash


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


# Lối vào ngắn của khu, nhà chưa nối đường (bản đồ có cổng): từ mép lô đất tới đúng mép ô theo hướng gate, đầu vuông,
# nằm gọn trong ô của nhà (không lòi sang ô bên cạnh).
# Nối đường vào từ cạnh nào thì GraphManager xoay gate về cạnh đó; đã nối thì đoạn đường nối thay cho lối vào này.
# Hỗ trợ cả gate thẳng (4 hướng) lẫn gate chéo (4 hướng) khi nhà đã nối đường chéo.
func _draw_stubs() -> void:
	if not GraphManager.uses_gates():
		return
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if n == null or n.kind == Types.NodeKind.HUB or n.gate == Vector2i.ZERO or GraphManager.get_gate_node(id) != -1:
			continue
		var d := Vector2(n.gate).normalized()
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


# Lan can hai bên những đoạn đường (chưa ngập sâu) nằm trên mặt nước: dựng lại khi nét đổi hoặc nước sát đường đổi.
func _build_rails() -> void:
	_rail_lines = []
	if not bridges:
		return
	var off := (ROAD_WIDTH + RAIL_WIDTH) / 2.0
	for s in _strokes:
		if s.state == Types.EdgeState.DEEP or not _any_wet(s.cells):
			continue  # nét chìm, hoặc quanh nét không có ô nước: không có cầu
		var pts: PackedVector2Array = s.points
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
		for r in runs:
			var c: PackedVector2Array = r[0]
			var nn: PackedVector2Array = r[1]
			if c.size() < 2:
				continue
			for side in [1.0, -1.0]:
				var line := PackedVector2Array()
				for i in c.size():
					line.append(c[i] + nn[i] * off * side)
				_rail_lines.append(line)


func _any_wet(cells: PackedInt32Array) -> bool:
	for i in cells:
		if _wet_cell(Vector2i(i % Config.GRID_COLS, i / Config.GRID_COLS)):
			return true
	return false


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


# Mặt nước đổi (lũ lan, rút): chỉ khi ô sát đường đổi nước mới dựng lại lan can cầu (không vẽ lại cả lớp đường).
func _check_water() -> void:
	if not bridges:
		return
	_wet_sig = FloodManager.wet_mask()
	var sig := _near_wet()
	if sig != _near_sig:
		_near_sig = sig
		_rails_dirty = true
		_rails_ci.queue_redraw()


func _near_wet() -> PackedByteArray:
	var sig := PackedByteArray()
	sig.resize(_near_cells.size())
	for k in _near_cells.size():
		var i := _near_cells[k]
		sig[k] = _wet_sig[i] if i < _wet_sig.size() else 0
	return sig


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
