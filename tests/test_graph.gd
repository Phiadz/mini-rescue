extends Node2D
# Chủ sở hữu: A. Kiểm tra tự động module Graph + thử bằng phím.
# Chạy F6: xem cửa sổ Output ("Kết quả: 33 đạt, 0 trượt") và cửa sổ game.

const START := 0
const GOAL := 7
var _log: Array = []
var _pass := 0
var _fail := 0
var _selected := 0
var _path_truck: PathResult
var _path_boat: PathResult

func _ready() -> void:
	EventBus.edge_added.connect(func(id: int): _log.append(['edge_added', id]))
	EventBus.edge_removed.connect(func(id: int): _log.append(['edge_removed', id]))
	EventBus.edge_state_changed.connect(func(id: int, s: int): _log.append(['edge_state_changed', id, s]))
	EventBus.edge_budget_changed.connect(func(u: int, l: int): _log.append(['edge_budget_changed', u, l]))
	_run_checks()
	_setup_demo()
	if DisplayServer.get_name() == 'headless':
		get_tree().quit(_fail)

# ---------- tiện ích ----------
func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print(('  đạt   ' if ok else '  TRƯỢT ') + label)

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true

func _fresh() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	_log.clear()

func _build_example() -> Dictionary:
	_fresh()
	var ids := {}
	for p in [[0, 3], [0, 2], [2, 4], [3, 5], [4, 5], [5, 7]]:
		ids[str(p[0]) + '-' + str(p[1])] = GraphManager.add_edge(p[0], p[1])
	return ids

# ---------- kiểm tra tự động ----------
func _run_checks() -> void:
	print('=== TEST GRAPH ===')
	_fresh()
	_check(GraphManager.get_node_ids().size() == 10, 'load_map: có 10 node')
	var k := GraphManager.get_map_node(0)
	_check(k != null and k.kind == 0 and k.elevation == 70.0, 'node 0 là Kho Bắc (kho, độ cao 70)')
	_check(GraphManager.get_map_node(99) == null, 'get_map_node với id lạ trả null')

	_fresh()
	var e1 := GraphManager.add_edge(0, 3)
	_check(e1 >= 0, 'add_edge hợp lệ trả về id')
	_check(GraphManager.add_edge(3, 0) == -1, 'add_edge trùng cạnh (đảo chiều) trả -1')
	_check(GraphManager.add_edge(2, 2) == -1, 'add_edge nối node với chính nó trả -1')
	_check(GraphManager.add_edge(0, 99) == -1, 'add_edge node không tồn tại trả -1')
	_check(_log.has(['edge_added', e1]), 'phát edge_added đúng id')
	_check(_log.has(['edge_budget_changed', 1, Config.EDGE_LIMIT_START]), 'phát edge_budget_changed(1, 10)')
	var e := GraphManager.get_edge(e1)
	_check(absf(e.length - _d(0, 3)) < 0.1, 'độ dài cạnh 0-3 bằng khoảng cách hai node (%.1f)' % _d(0, 3))
	_check(e.elevation == 47.5, 'độ cao cạnh 0-3 = (70 + 25) / 2 = 47,5')
	_log.clear()
	GraphManager.remove_edge(e1)
	_check(GraphManager.get_edge(e1) == null, 'remove_edge: cạnh biến mất')
	_check(_log.size() == 2 and _log[0] == ['edge_removed', e1] and _log[1] == ['edge_budget_changed', 0, Config.EDGE_LIMIT_START], 'phát edge_removed rồi edge_budget_changed')
	_check(GraphManager.get_edges_of(0).is_empty(), 'danh sách kề của node 0 đã sạch')

	_fresh()
	var made := 0
	for p in [[0, 3], [0, 2], [2, 4], [3, 5], [4, 5], [5, 7], [3, 6], [6, 8], [5, 6], [7, 1]]:
		if GraphManager.add_edge(p[0], p[1]) >= 0:
			made += 1
	_check(made == Config.EDGE_LIMIT_START, 'tạo được đúng 10 cạnh (hạn mức)')
	_check(GraphManager.add_edge(8, 1) == -1, 'vượt hạn mức trả -1')
	GraphManager.add_edge_limit(2)
	_check(GraphManager.add_edge(8, 1) >= 0, 'sau add_edge_limit(2) tạo thêm được')
	var b := GraphManager.get_edge_budget()
	_check(b.used == 11 and b.limit == 12, 'get_edge_budget = 11/12')

	_fresh()
	var s1 := GraphManager.add_edge(0, 3)
	_log.clear()
	GraphManager.set_edge_state(s1, 1)
	GraphManager.set_edge_state(s1, 1)
	_check(_log == [['edge_state_changed', s1, 1]], 'set_edge_state chỉ phát tín hiệu khi đổi thật')
	_check(GraphManager.get_edge(s1).state == 1, 'trạng thái cạnh được lưu')

	var ids := _build_example()
	var pt := GraphManager.find_path(0, 7, Types.VehicleType.TRUCK)
	_check(pt.found and _same(pt.node_ids, [0, 3, 5, 7]), 'xe tải 0→7 đi 0-3-5-7')
	var cost_dry := (_d(0, 3) + _d(3, 5) + _d(5, 7)) / Config.TRUCK_SPEED
	_check(absf(pt.cost - cost_dry) < 0.02, 'chi phí xe tải xấp xỉ %.2f giây' % cost_dry)
	GraphManager.set_edge_state(ids['3-5'], Types.EdgeState.DEEP)
	var pt2 := GraphManager.find_path(0, 7, Types.VehicleType.TRUCK)
	_check(pt2.found and _same(pt2.node_ids, [0, 2, 4, 5, 7]), 'cạnh 3-5 ngập sâu: xe tải đổi sang 0-2-4-5-7')
	var cost_detour := (_d(0, 2) + _d(2, 4) + _d(4, 5) + _d(5, 7)) / Config.TRUCK_SPEED
	_check(absf(pt2.cost - cost_detour) < 0.02, 'chi phí mới xấp xỉ %.2f giây' % cost_detour)
	_check(not GraphManager.find_path(0, 7, Types.VehicleType.BOAT).found, 'ca-nô: các cạnh khác còn khô nên chưa có đường 0→7')
	for eid in GraphManager.get_edge_ids():
		GraphManager.set_edge_state(eid, Types.EdgeState.DEEP)
	_check(not GraphManager.find_path(0, 7, Types.VehicleType.TRUCK).found, 'mọi cạnh ngập sâu: xe tải không có đường')
	var pb := GraphManager.find_path(0, 7, Types.VehicleType.BOAT)
	_check(pb.found and _same(pb.node_ids, [0, 3, 5, 7]), 'mọi cạnh ngập sâu: ca-nô đi 0-3-5-7')

	_build_example()
	for eid in GraphManager.get_edge_ids():
		GraphManager.set_edge_state(eid, Types.EdgeState.SHALLOW)
	var cost_shallow := 2.0 * (_d(0, 3) + _d(3, 5) + _d(5, 7)) / Config.TRUCK_SPEED
	_check(absf(GraphManager.find_path(0, 7, Types.VehicleType.TRUCK).cost - cost_shallow) < 0.03, 'ngập nhẹ: xe tải chậm gấp đôi (xấp xỉ %.2f giây)' % cost_shallow)

	var ids3 := _build_example()
	GraphManager.remove_edge(ids3['3-5'])
	_check(_same(GraphManager.find_path(0, 7, Types.VehicleType.TRUCK).node_ids, [0, 2, 4, 5, 7]), 'xóa cạnh 3-5: đường đi đổi theo')

	var p0 := GraphManager.find_path(0, 0, Types.VehicleType.TRUCK)
	_check(p0.found and p0.node_ids.size() == 1 and p0.cost == 0.0, 'find_path cùng node: có đường, 1 node, chi phí 0')
	_check(not GraphManager.find_path(0, 99, Types.VehicleType.TRUCK).found, 'find_path tới node lạ: không có đường')

	GraphManager.add_edge_limit(2)
	EventBus.game_started.emit()
	_check(GraphManager.get_edge_ids().is_empty() and GraphManager.get_edge_budget().limit == Config.EDGE_LIMIT_START, 'game_started: xóa hết cạnh, đặt lại hạn mức')
	GraphManager.load_map(Config.MAP_PATH)
	_check(GraphManager.get_node_ids().size() == 10, 'load_map gọi lại vẫn đúng 10 node')
	_check(GraphManager.get_node_ids().all(func(id): return ResourceLoader.exists('res://assets/icons/%s.svg' % GraphManager.get_map_node(id).icon)),
			'mỗi node có trường icon trỏ tới file icon có thật')

	print('Kết quả: %d đạt, %d trượt' % [_pass, _fail])

# Khoảng cách giữa hai node theo tọa độ trong map_01.json, để test không phụ thuộc con số cứng.
func _d(a: int, b: int) -> float:
	return GraphManager.get_map_node(a).pos.distance_to(GraphManager.get_map_node(b).pos)

# ---------- thử bằng phím ----------
func _setup_demo() -> void:
	_build_example()
	_selected = 0
	_recompute()

func _recompute() -> void:
	_path_truck = GraphManager.find_path(START, GOAL, Types.VehicleType.TRUCK)
	_path_boat = GraphManager.find_path(START, GOAL, Types.VehicleType.BOAT)
	queue_redraw()

func _selected_id() -> int:
	var ids := GraphManager.get_edge_ids()
	if ids.is_empty():
		return -1
	return ids[clampi(_selected, 0, ids.size() - 1)]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var sid := _selected_id()
	match event.keycode:
		KEY_RIGHT: _selected += 1
		KEY_LEFT: _selected -= 1
		KEY_1: GraphManager.set_edge_state(sid, Types.EdgeState.DRY)
		KEY_2: GraphManager.set_edge_state(sid, Types.EdgeState.SHALLOW)
		KEY_3: GraphManager.set_edge_state(sid, Types.EdgeState.DEEP)
		KEY_DELETE: GraphManager.remove_edge(sid)
		KEY_N: GraphManager.add_edge(0, 7)
		KEY_R: _setup_demo()
	_selected = clampi(_selected, 0, maxi(GraphManager.get_edge_ids().size() - 1, 0))
	_recompute()

func _describe(r: PathResult) -> String:
	if not r.found:
		return 'không có đường'
	var parts: PackedStringArray = []
	for id in r.node_ids:
		parts.append(str(id))
	return ' → '.join(parts) + '   (%.2f giây)' % r.cost

func _draw_path(r: PathResult, offset: Vector2, col: Color) -> void:
	if not r.found:
		return
	for i in range(r.node_ids.size() - 1):
		var a := GraphManager.get_map_node(r.node_ids[i]).pos + offset
		var c := GraphManager.get_map_node(r.node_ids[i + 1]).pos + offset
		draw_line(a, c, col, 2.0)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for eid in GraphManager.get_edge_ids():
		var e := GraphManager.get_edge(eid)
		var a := GraphManager.get_map_node(e.node_a).pos
		var c := GraphManager.get_map_node(e.node_b).pos
		match e.state:
			0: draw_line(a, c, Color('#FFD700'), 4.0)
			1: draw_dashed_line(a, c, Color('#FFD700'), 4.0, 12.0)
			2: draw_line(a, c, Color('#0073E6'), 6.0)
		if eid == _selected_id():
			draw_circle((a + c) / 2.0, 8.0, Color('#FF4500'))
	_draw_path(_path_truck, Vector2(5, 5), Color.WHITE)
	_draw_path(_path_boat, Vector2(-5, -5), Color('#FF66CC'))
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		draw_circle(n.pos, 14.0, Color('#2A2A33'))
		draw_arc(n.pos, 14.0, 0.0, TAU, 24, Color('#E8E8E8'), 2.0)
		draw_string(font, n.pos + Vector2(-4, 5), str(id))
	var bud := GraphManager.get_edge_budget()
	var lines := [
		'←/→ chọn cạnh (chấm cam) | 1/2/3 đổi trạng thái: khô / ngập nhẹ / ngập sâu | Delete xóa | N thêm cạnh 0-7 | R làm lại',
		'Xe tải (nét trắng) 0→7: ' + _describe(_path_truck),
		'Ca-nô (nét hồng) 0→7: ' + _describe(_path_boat),
		'Hạn mức tuyến: %d/%d' % [bud.used, bud.limit],
	]
	for i in lines.size():
		draw_string(font, Vector2(20, 660 + i * 20), lines[i])
