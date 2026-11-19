extends Node
# Test tự động cho cổng, chỗ đỗ và nhà mọc dần trên bản đồ Sài Gòn (bản đồ bật "gates").
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_gate_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const HUB := 0         # Kho Tân Sơn Nhất
const NEAR := 16       # Lê Đức Thọ, gần Kho Tân Sơn Nhất
const NB8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var _passed := 0
var _failed := 0
var _added: Array[int] = []
var _rescued := 0


func _ready() -> void:
	EventBus.point_added.connect(func(id: int) -> void: _added.append(id))
	EventBus.sos_rescued.connect(func(_r: int, _p: int) -> void: _rescued += 1)
	_run.call_deferred()


func _run() -> void:
	seed(7)
	_fresh()
	_test_gates()
	_test_driveway()
	_test_corner()
	_test_extend()
	_test_stop_pos()
	await _test_vehicle()
	_fresh()
	_test_house()
	_test_spawn()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fresh() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	EventBus.game_started.emit()


func _cell(id: int) -> Vector2i:
	return GraphManager.cell_of(GraphManager.get_map_node(id).pos)


func _test_gates() -> void:
	print('\n== Kho có ô cổng và bãi; khu có lối vào ngắn')
	_check(GraphManager.uses_gates(), 'bản đồ Sài Gòn bật cổng')
	var ok_hub := true
	var ok_point := true
	var names := []
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		var edges := GraphManager.get_edges_of(id)
		var orth := n.gate != Vector2i.ZERO and absi(n.gate.x) + absi(n.gate.y) == 1
		if n.kind == Types.NodeKind.HUB:
			var gcell: Vector2i = _cell(id) + n.gate * 2  # kho, ô bãi, ô cổng thẳng hàng
			var gid := GraphManager.get_gate_node(id)
			var lot: Vector2i = _cell(id) + n.gate
			ok_hub = ok_hub and orth and gid != -1 and GraphManager.is_gate_cell(gcell) and GraphManager.road_at(gcell) == gid
			ok_hub = ok_hub and edges.size() == 1 and GraphManager.get_edge(edges[0]).other_end(id) == gid
			ok_hub = ok_hub and GraphManager.get_lot_cell(id) == lot and GraphManager.is_lot_cell(lot) and GraphManager.road_at(lot) == -1
			ok_hub = ok_hub and n.gate != Vector2i(0, 1)  # bãi không nằm phía dưới (nhãn hàng)
		else:
			var front: Vector2i = _cell(id) + n.gate
			ok_point = ok_point and orth and edges.is_empty() and GraphManager.get_gate_node(id) == -1
			ok_point = ok_point and not GraphManager.cell_is_water(front) and GraphManager.road_at(front) == -1
		names.append('%s %s' % [n.name, {Vector2i(1, 0): 'Đ', Vector2i(-1, 0): 'T', Vector2i(0, -1): 'B', Vector2i(0, 1): 'N'}.get(n.gate, '?')])
	print('  hướng lối vào: ', ', '.join(names))
	_check(ok_hub, '2 kho có ô cổng dựng sẵn cách 2 ô, ô giữa là bãi đỗ, nối với kho bằng một cạnh')
	_check(ok_point, '15 khu chỉ có hướng lối vào (4 hướng, trước mặt là đất), chưa dựng ô nào, chưa nối đường')
	_check(GraphManager.get_edge_budget().used == 0, 'ô cổng kho không tính vào hạn mức')
	_check(not GraphManager.remove_road(_cell(HUB) + GraphManager.get_map_node(HUB).gate * 2), 'không xóa được ô cổng kho')
	_check(GraphManager.get_road_ids().size() == 2, 'đầu ván chỉ có 2 ô đường là 2 ô cổng kho')


# Khu, nhà như Mini Motorways: vẽ đường vào từ cạnh nào (4 hướng) cũng được, lối vào xoay về phía đó; mỗi điểm một lối.
func _test_driveway() -> void:
	print('\n== Lối vào khu xoay theo đường vẽ vào')
	var p := NEAR
	var pc := _cell(p)
	var sides: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = pc + d
		if GraphManager.road_at(c) == -1 and not GraphManager.cell_is_water(c) and not GraphManager._point_cells.has(c) and not GraphManager.is_lot_cell(c):
			sides.append(c)
	_check(sides.size() >= 2, 'Lê Đức Thọ có ít nhất 2 cạnh trống để thử (%d)' % sides.size())
	if sides.size() < 2:
		return
	var a := GraphManager.extend_road(p, sides[0])
	_check(a != -1 and GraphManager.get_gate_node(p) == a and GraphManager.get_map_node(p).gate == sides[0] - pc,
			'kéo đường từ khu ra một cạnh: nối được, lối vào xoay về cạnh đó')
	var b := GraphManager.extend_road(-1, sides[1])
	_check(GraphManager.extend_road(b, pc) == -1, 'khu đã có lối vào: không nối thêm đường từ cạnh khác')
	GraphManager.remove_road(sides[0])
	_check(GraphManager.get_gate_node(p) == -1, 'xóa đường: khu không còn nối')
	_check(GraphManager.extend_road(b, pc) == p and GraphManager.get_map_node(p).gate == sides[1] - pc,
			'kéo đường từ cạnh khác vào khu: nối được, lối vào xoay theo')
	GraphManager.remove_road(sides[1])
	var diag := pc + Vector2i(1, 1)
	var dg := GraphManager.extend_road(-1, diag) if GraphManager.road_at(diag) == -1 and not GraphManager._point_cells.has(diag) else -1
	if dg != -1:
		_check(GraphManager.extend_road(dg, pc) == -1, 'không nối vào khu theo đường chéo')
		GraphManager.remove_road(diag)
	var other := -1
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if id != p and n.kind != Types.NodeKind.HUB:
			other = id
			break
	_check(not GraphManager._gate_allows(p, other, _cell(other)), 'không nối thẳng hai điểm với nhau')
	_check(GraphManager.get_edge_budget().used == 0, 'dọn sạch đường vừa thử')


# Luật không cắt góc: đường chéo không đi qua góc ô có công trình; nhà không mọc vào ô bị đường chéo cắt góc.
func _test_corner() -> void:
	print('
== Đường chéo không cắt góc công trình')
	var pc := _cell(NEAR)
	var free := func(c: Vector2i) -> bool:
		return GraphManager.road_at(c) == -1 and not GraphManager.cell_is_water(c) and not GraphManager._point_cells.has(c) and not GraphManager.is_lot_cell(c)
	var tried := false
	for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var a: Vector2i = pc + Vector2i(d.x, 0)
		var b: Vector2i = pc + Vector2i(0, d.y)
		if free.call(a) and free.call(b):
			var ra := GraphManager.extend_road(-1, a)
			_check(GraphManager.extend_road(ra, b) == -1, 'không vẽ đường chéo cắt qua góc ô nhà')
			GraphManager.remove_road(a)
			tried = true
			break
	_check(tried, 'tìm được hai ô kề nhà để thử bước chéo')
	# Ô trống bị một đoạn đường chéo cắt góc: không mọc nhà ở đó.
	var found := false
	for y in range(2, Config.GRID_ROWS - 2):
		for x in range(2, Config.GRID_COLS - 2):
			var c := Vector2i(x, y)
			if found or not GraphManager.can_place_house(c):
				continue
			var a := c + Vector2i(1, 0)
			var b := c + Vector2i(0, 1)
			if not (free.call(a) and free.call(b)):
				continue
			var ra := GraphManager.extend_road(-1, a)
			var rb := GraphManager.extend_road(ra, b)
			if rb == -1:
				GraphManager.remove_road(a)
				continue
			found = true
			_check(not GraphManager.can_place_house(c), 'không mọc nhà ở ô đang bị đường chéo cắt góc')
			GraphManager.remove_road(a)
			GraphManager.remove_road(b)
			_check(GraphManager.can_place_house(c), 'xóa đường chéo thì ô đó lại đặt được nhà')
	_check(found, 'tìm được ô trống để thử đường chéo cắt góc')
	_check(GraphManager.get_edge_budget().used == 0, 'dọn sạch đường vừa thử')


func _test_extend() -> void:
	print('\n== Đường chỉ vào điểm qua cổng')
	var hub_cell := _cell(HUB)
	var gate: Vector2i = GraphManager.get_map_node(HUB).gate
	var side := Vector2i.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var c: Vector2i = hub_cell + d
		if d != gate and GraphManager.road_at(c) == -1 and not GraphManager.cell_is_water(c):
			side = c
			break
	var side_id := GraphManager.extend_road(-1, side)
	_check(side_id != -1, 'tô được ô cạnh kho (không phải cổng)')
	_check(GraphManager.extend_road(side_id, hub_cell) == -1, 'từ ô cạnh không phải cổng không nối vào kho được')
	_check(GraphManager.extend_road(HUB, side) == -1, 'từ kho không đi thẳng ra ô không phải cổng')
	var gid := GraphManager.get_gate_node(HUB)
	_check(GraphManager.extend_road(-1, hub_cell + gate) == -1 and GraphManager.extend_road(gid, hub_cell + gate) == -1, 'không tô đường lên ô bãi đỗ giữa kho và cổng')
	var link: Array = GraphManager.get_edges_of(HUB)
	_check(link.size() == 1 and GraphManager.get_edge(link[0]).other_end(HUB) == gid, 'kho nối sẵn với ô cổng bằng một cạnh qua bãi')
	var gcell := hub_cell + gate * 2
	var out := gcell + gate  # ô trống kề ô cổng (thẳng ra ngoài có thể trùng ô cổng của điểm bên cạnh)
	for d in [gate, Vector2i(gate.y, gate.x), Vector2i(-gate.y, -gate.x)]:
		var c: Vector2i = gcell + d
		if GraphManager.road_at(c) == -1 and not GraphManager._point_cells.has(c) and not GraphManager.is_lot_cell(c) and not GraphManager.cell_is_water(c):
			out = c
			break
	var before: int = GraphManager.get_edge_budget().used
	var out_id := GraphManager.extend_road(gid, out)
	_check(out_id != -1 and GraphManager.get_edge_budget().used == before + 1, 'tô tiếp từ ô cổng ra ngoài, tính 1 ô hạn mức')
	GraphManager.remove_road(side)
	GraphManager.remove_road(out)


func _test_stop_pos() -> void:
	print('\n== Chỗ đỗ ở lối vào')
	var n := GraphManager.get_map_node(NEAR)
	var p := RescueManager.stop_pos(NEAR)
	var off := GraphManager.point_radius(NEAR) + RescueManager.PARK_GAP
	_check(p == n.pos + Vector2(n.gate) * off, 'xe đỗ trên lối vào, cách tâm %d px (ngay trước mép nhà)' % int(off))
	var gid := GraphManager.get_gate_node(HUB)  # ô cổng kho là ô đường
	_check(RescueManager.stop_pos(gid) == GraphManager.get_map_node(gid).pos, 'ô đường: dừng ở tâm ô như cũ')


func _test_vehicle() -> void:
	print('\n== Bãi đỗ ở kho, bến ca-nô, đỗ ở lối vào khi giao hàng')
	await get_tree().process_frame
	await get_tree().process_frame  # process_frame phát trước _process của xe: chờ thêm một khung
	var idle := RescueManager._vehicles.values()
	for type in [Types.VehicleType.TRUCK, Types.VehicleType.BOAT]:
		var mine := idle.filter(func(v) -> bool: return v.type == type and v.hub_id == (HUB if type == Types.VehicleType.TRUCK else 1))  # xét từng kho
		var slotted := mine.filter(func(v) -> bool: return v.slot >= 0)
		var spots := {}
		for v in slotted:
			spots[Vector2i(v.position.round())] = true
		var cap := RescueManager.slot_count(mine[0].hub_id, type) if not mine.is_empty() else 0
		var name := 'xe tải ở bãi' if type == Types.VehicleType.TRUCK else 'ca-nô ở bến'
		_check(cap > 0 and slotted.size() == mini(cap, mine.size()) and spots.size() == slotted.size()
				and slotted.all(func(v) -> bool: return v.visible and v.position.distance_to(RescueManager.slot_pos(v)) < 0.5),
				'%s: %d chỗ, mỗi xe một chỗ riêng, không chồng nhau, nhìn thấy được' % [name, cap])
		_check(mine.filter(func(v) -> bool: return v.slot < 0).all(func(v) -> bool: return not v.visible), '%s: hết chỗ thì xe vào trong kho (ẩn)' % name)
	var front: Vector2i = _cell(NEAR) + GraphManager.get_map_node(NEAR).gate
	_check(_connect(GraphManager.get_gate_node(HUB), front) and GraphManager.extend_road(GraphManager.road_at(front), _cell(NEAR)) == NEAR,
			'nối đường từ cổng kho tới lối vào Lê Đức Thọ')
	var req := RescueManager.SosRequest.new()
	req.id = 900
	req.node_id = NEAR
	req.supply = Types.SupplyType.FOOD
	req.time_total = 600.0
	req.time_left = 600.0
	RescueManager._requests[900] = req
	RescueManager.mark_dirty()
	var hub_pos := GraphManager.get_map_node(HUB).pos
	var found := []  # lambda chụp biến cục bộ theo giá trị, nên trả xe ra qua mảng
	await _wait(func() -> bool:
		for v in RescueManager._vehicles.values():
			if v.request == req and found.is_empty():
				found.append(v)
		return not found.is_empty())
	var truck = found[0] if not found.is_empty() else null
	_check(truck != null, 'một xe tải nhận SOS')
	if truck == null:
		return
	_check(truck.slot == -1, 'xe nhận nhiệm vụ thì trả chỗ đỗ')
	await _wait(func() -> bool: return truck.position.distance_to(hub_pos) > RescueManager.HUB_HIDE_RADIUS + 4.0)
	await get_tree().process_frame
	_check(truck.visible, 'ra khỏi kho thì xe hiện')
	await _wait(func() -> bool: return truck.state_id == Types.VehicleState.DELIVERING)
	_check(truck.position.distance_to(RescueManager.stop_pos(NEAR)) < 0.5, 'xe đỗ ở lối vào trước nhà')
	_check(truck.position.distance_to(GraphManager.get_map_node(NEAR).pos) > 10.0, 'xe không chồng lên tâm nhà')
	await _wait(func() -> bool: return _rescued > 0)
	_check(_rescued == 1, 'giao hàng xong')
	await _wait(func() -> bool: return truck.state_id == Types.VehicleState.IDLE)
	await get_tree().process_frame
	_check(truck.slot >= 0, 'về kho: giữ được một chỗ trong bãi')
	await _wait(func() -> bool: return truck.waypoints.is_empty())
	await get_tree().process_frame
	_check(truck.visible and truck.position.distance_to(RescueManager.slot_pos(truck)) < 0.5, 'về kho thì đỗ vào đúng chỗ đã giữ trong bãi')
	var parked := RescueManager._vehicles.values().filter(func(v) -> bool: return v.type == Types.VehicleType.TRUCK and v.slot >= 0)
	var at := {}
	for v in parked:
		at[Vector2i(v.position.round())] = true
	_check(at.size() == parked.size(), 'các xe trong bãi không chồng nhau')


func _test_house() -> void:
	print('\n== Đặt nhà')
	var hub_cell := _cell(HUB)
	_check(not GraphManager.can_place_house(hub_cell), 'không đặt nhà lên ô của điểm')
	_check(not GraphManager.can_place_house(hub_cell + GraphManager.get_map_node(HUB).gate), 'không đặt nhà lên ô cổng')
	_check(not GraphManager.can_place_house(hub_cell + Vector2i(1, 1)), 'không đặt nhà kề điểm khác')
	var water := Vector2i(-1, -1)
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			if water == Vector2i(-1, -1) and GraphManager.cell_is_boat(Vector2i(x, y)):
				water = Vector2i(x, y)
	_check(not GraphManager.can_place_house(water), 'không đặt nhà trên sông')
	var cell := _free_cell_near(NEAR)
	_check(cell != Vector2i(-1, -1) and GraphManager.can_place_house(cell), 'tìm được ô hợp lệ gần Lê Đức Thọ')
	_added.clear()
	var before: int = GraphManager.get_edge_budget().used
	var id := GraphManager.add_house(cell, NEAR)
	var n := GraphManager.get_map_node(id)
	_check(id >= GraphManager.HOUSE_ID_BASE and id < GraphManager.ROAD_ID_BASE, 'nhà mới có mã từ %d' % GraphManager.HOUSE_ID_BASE)
	_check(n != null and n.kind == Types.NodeKind.DISTRICT and n.name.is_empty() and n.parent == NEAR and n.icon.begins_with('house_'),
			'nhà là khu dân cư không tên, thuộc Lê Đức Thọ, icon nhà')
	_check(n.gate != Vector2i.ZERO and GraphManager.get_gate_node(id) == -1 and GraphManager.get_edges_of(id).is_empty(),
			'nhà mới có hướng lối vào, chưa dựng ô nào, chờ người chơi nối đường')
	_check(GraphManager.get_edge_budget().used == before, 'cổng nhà không tính hạn mức')
	_check(_added == [id] and GraphManager.get_node_ids().has(id), 'phát point_added, nhà có trong danh sách điểm')
	_check(not GraphManager.can_place_house(cell) and GraphManager.add_house(cell, NEAR) == -1, 'không đặt chồng nhà lên ô đã có nhà')


func _test_spawn() -> void:
	print('\n== Nhà mọc dần')
	GameManager._enter_stage(0, false)  # vùng chơi đợt 1
	_added.clear()
	RescueManager.set_wave(0)
	var w: Dictionary = Config.WAVES[0]
	RescueManager._tick_houses(float(w.house_interval) - 0.5)
	_check(_added.is_empty(), 'chưa đủ house_interval thì chưa mọc nhà')
	RescueManager._tick_houses(1.0)
	_check(_added.size() == 1, 'đủ house_interval (%.0f giây) thì mọc một nhà' % float(w.house_interval))
	for i in 80:
		RescueManager.try_spawn_house()
	var per := {}
	var near := true
	var inside := true
	var dry := true
	for id in _added:  # chỉ xét nhà vừa mọc trong bài này
		var n := GraphManager.get_map_node(id)
		per[n.parent] = int(per.get(n.parent, 0)) + 1
		var d: Vector2i = GraphManager.cell_of(n.pos) - _cell(n.parent)
		near = near and maxi(absi(d.x), absi(d.y)) <= Config.HOUSE_RADIUS
		inside = inside and GameManager.is_in_play(n.pos) and GameManager.is_in_play(GraphManager.get_map_node(n.parent).pos)
		dry = dry and not GraphManager.cell_is_boat(GraphManager.cell_of(n.pos))
	var max_per := 0
	for k in per:
		max_per = maxi(max_per, per[k])
	_check(_added.size() >= 8, 'mọc được nhiều nhà (%d)' % _added.size())
	_check(max_per <= Config.HOUSE_MAX_PER_DISTRICT, 'mỗi khu tối đa %d nhà' % Config.HOUSE_MAX_PER_DISTRICT)
	_check(near, 'nhà cách khu mẹ tối đa %d ô' % Config.HOUSE_RADIUS)
	_check(inside, 'nhà và khu mẹ đều trong vùng chơi đợt 1')
	_check(dry, 'nhà không mọc trên sông')
	_check(_added.all(func(id: int) -> bool: return GraphManager.get_map_node(id).gate != Vector2i.ZERO), 'nhà nào cũng có hướng lối vào')
	RescueManager.set_spawning(false)
	GameManager._enter_stage(2, false)


# Ô trống đặt được nhà gần điểm id (bán kính 3), hoặc (-1, -1).
func _free_cell_near(id: int) -> Vector2i:
	var c := _cell(id)
	for r in range(2, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if GraphManager.can_place_house(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return Vector2i(-1, -1)


# Nối đường từ nút from_id tới ô to theo đường ngắn nhất (BFS 8 hướng, tránh ô của điểm).
func _connect(from_id: int, to: Vector2i) -> bool:
	var start := GraphManager.cell_of(GraphManager.get_map_node(from_id).pos)
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty() and not prev.has(to):
		var c: Vector2i = queue.pop_front()
		for d in NB8:
			var n: Vector2i = c + d
			if prev.has(n) or n.x < 0 or n.y < 0 or n.x >= Config.GRID_COLS or n.y >= Config.GRID_ROWS:
				continue
			if GraphManager._point_cells.has(n) or GraphManager.is_lot_cell(n) or not GraphManager.diagonal_ok(c, n):
				continue
			prev[n] = c
			queue.append(n)
	if not prev.has(to):
		return false
	var path: Array[Vector2i] = []
	var cur := to
	while cur != start:
		path.push_front(cur)
		cur = prev[cur]
	var last := from_id
	for c in path:
		last = GraphManager.extend_road(last, c)
		if last == -1:
			return false
	return true


func _wait(done: Callable) -> void:
	for i in 1800:
		if done.call():
			return
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT]   ', label)
	else:
		_failed += 1
		print('  [TRƯỢT] ', label)
