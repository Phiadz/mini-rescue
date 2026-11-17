extends Node
# Test tự động cho ca-nô: chỉ chạy trên sông (grid.boat), bến và đường đã ngập; không bao giờ đi đường khô.
# Kèm kiểm tra Dijkstra dùng hàng đợi ưu tiên (so với bản cũ) và cây đường ngắn nhất cho điều phối.
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_boat_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const SAIGON := 'res://data/map_saigon.json'
const MAP_01 := 'res://data/map_01.json'
const CAT_LAI := 1
const TAN_SON_NHAT := 0
const CALMETTE := 2
const NHA_BE := 9
const BOAT := Types.VehicleType.BOAT
const TRUCK := Types.VehicleType.TRUCK

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_river()
	_test_on_water()
	_test_flood_links()
	_test_flood_area()
	_test_heap_matches_old()
	_test_tree()
	_test_timing()
	await _test_dispatch()
	await _test_unconnected()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fresh_saigon() -> void:
	GraphManager.load_map(SAIGON)
	EventBus.game_started.emit()  # FloodManager đọc lại độ cao ô, RescueManager đặt xe vào kho


func _test_river() -> void:
	print('\n== Sông cho ca-nô')
	_fresh_saigon()
	var boat_cells := 0
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			if GraphManager.cell_is_boat(Vector2i(x, y)):
				boat_cells += 1
	var cell_nodes := GraphManager._water.keys().filter(func(id: int) -> bool: return id < GraphManager.WATER_VIA_BASE).size()
	_check(cell_nodes == boat_cells and boat_cells > 0, 'mỗi ô ca-nô có một nút nước (%d nút, thêm %d nút điểm gãy)' % [boat_cells, GraphManager._water.size() - cell_nodes])
	# Bản đồ Sài Gòn có cổng: lúc đầu chỉ có các ô cổng dựng sẵn là ô đường.
	var only_gates := GraphManager.get_road_ids().all(func(id: int) -> bool: return GraphManager.is_gate_cell(GraphManager.cell_of(GraphManager.get_map_node(id).pos)))
	_check(GraphManager.get_node_ids().size() == 17 and only_gates, 'nút nước không lẫn vào danh sách điểm và ô đường (chỉ có ô cổng)')
	_check(not GraphManager._boat_edges.is_empty() and GraphManager.get_edge_ids().all(func(eid: int) -> bool: return not GraphManager._boat_edges.has(eid)),
			'get_edge_ids chỉ có cạnh đường bộ, cạnh sông để riêng')
	_check(GraphManager._boat_edges.keys().all(func(eid: int) -> bool: return eid >= GraphManager.BOAT_EDGE_ID_BASE),
			'cạnh ca-nô có dải mã riêng, không trùng mã cạnh đường của bản đồ trước')
	var w: int = GraphManager._water.keys()[0]
	_check(GraphManager.get_map_node(w).kind == Types.NodeKind.WATER and GraphManager.get_edges_of(w).is_empty(), 'nút nước tra được, không có cạnh đường bộ')
	_check(GraphManager.has_dock(CAT_LAI) and not GraphManager.has_dock(TAN_SON_NHAT), 'Kho Cát Lái có bến, Kho Tân Sơn Nhất không')
	_check(RescueManager._hub_for(BOAT) == CAT_LAI, 'ca-nô về kho có bến (Cát Lái)')
	for target in [CALMETTE, NHA_BE]:
		var p := GraphManager.find_path(CAT_LAI, target, BOAT)
		var on_water := p.found and p.node_ids.slice(1, p.node_ids.size() - 1).all(func(id: int) -> bool: return id >= GraphManager.WATER_ID_BASE)
		_check(on_water, 'chưa có đường nào, ca-nô vẫn đi dọc sông từ Cát Lái tới %s (%.1f giây)' % [GraphManager.get_map_node(target).name, p.cost])
	_check(not GraphManager.find_path(CAT_LAI, CALMETTE, TRUCK).found, 'xe tải không đi cạnh sông')


# Ảnh độ cao của bản đồ Sài Gòn: điểm ảnh sông có giá trị 16 bit (R byte cao, G byte thấp) đúng bằng 10944.
var _height: Image

func _river(p: Vector2) -> bool:
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	if _height == null or x < 0 or y < 0 or x >= _height.get_width() or y >= _height.get_height():
		return false
	var c := _height.get_pixel(x, y)
	return roundi(c.r * 255.0) * 256 + roundi(c.g * 255.0) <= 10944

# Tỷ lệ mẫu (mỗi 2 px) nằm trên sông dọc đoạn a-b.
func _water_frac(a: Vector2, b: Vector2) -> float:
	var n := maxi(2, ceili(a.distance_to(b) / 2.0))
	var w := 0
	for s in n + 1:
		if _river(a.lerp(b, float(s) / n)):
			w += 1
	return float(w) / (n + 1)


func _test_on_water() -> void:
	print('\n== Ca-nô ở trên nước, không lên cạn')
	_fresh_saigon()
	_height = Image.load_from_file(ProjectSettings.globalize_path('res://assets/icons/terrain/saigon_height.png'))
	_check(_height != null and _height.get_width() == 1280, 'đọc được ảnh độ cao để biết chỗ nào là sông')
	var nodes: Array = GraphManager._water.keys()
	var off := nodes.filter(func(id: int) -> bool: return not _river(GraphManager.get_map_node(id).pos))
	_check(off.is_empty(), 'mọi nút nước (%d nút) nằm trên sông%s' % [nodes.size(), '' if off.is_empty() else ', lệch: %s' % str(off)])
	# Mỗi đoạn sông giữa hai nút ô: đi thẳng, hoặc vòng qua một nút điểm gãy (chấm cả đường gấp khúc như lúc tính dữ liệu).
	var low := 0
	var worst := 1.0
	var count := 0
	for eid in GraphManager._boat_edges:
		var e: Edge = GraphManager.get_edge(eid)
		var a := GraphManager.get_map_node(e.node_a)
		var b := GraphManager.get_map_node(e.node_b)
		if a.kind != Types.NodeKind.WATER or b.kind != Types.NodeKind.WATER or a.id >= GraphManager.WATER_VIA_BASE or b.id >= GraphManager.WATER_VIA_BASE:
			continue  # bến, lối xuống nước xét riêng; nửa đoạn qua điểm gãy xét ở vòng dưới
		count += 1
		var f := _water_frac(a.pos, b.pos)
		worst = minf(worst, f)
		if f < 0.9:
			low += 1
	for m in nodes:
		if m < GraphManager.WATER_VIA_BASE:
			continue
		var ends: Array = GraphManager._badj[m].map(func(eid: int) -> Vector2: return GraphManager.get_map_node(GraphManager.get_edge(eid).other_end(m)).pos)
		var mp: Vector2 = GraphManager.get_map_node(m).pos
		var la := maxi(2, ceili(ends[0].distance_to(mp) / 2.0))
		var lb := maxi(2, ceili(mp.distance_to(ends[1]) / 2.0))
		var f := (_water_frac(ends[0], mp) * (la + 1) + _water_frac(mp, ends[1]) * (lb + 1)) / (la + lb + 2)
		count += 1
		worst = minf(worst, f)
		if f < 0.9:
			low += 1
	_check(count > 0 and low <= 2 and worst >= 0.75,
			'đoạn sông (%d đoạn) nằm trên sông: %d đoạn dưới 90%% nước (nối chỗ ảnh sông bị đứt), thấp nhất %d%%' % [count, low, roundi(worst * 100.0)])
	_check(Config.SPEED_FACTOR[BOAT][Types.EdgeState.DRY] == 0.0 and Config.SPEED_FACTOR[BOAT][Types.EdgeState.SHALLOW] < Config.SPEED_FACTOR[BOAT][Types.EdgeState.DEEP],
			'ca-nô không lên đất khô; đường ngập nhẹ chạy chậm hơn ngập sâu')
	# Ca-nô cập bến một điểm từ nút nước: dừng trên nước.
	var stops := 0
	var dry := []
	for p in GraphManager.get_node_ids():
		for w in GraphManager.get_dock_nodes(p):
			var v = RescueManager.Vehicle.new()
			v.type = BOAT
			v.hub_id = CAT_LAI
			var path := PathResult.new()
			path.found = true
			path.node_ids.append(w)
			path.node_ids.append(p)
			path.edge_ids.append(-1)
			v.path = path
			v.path_index = 0
			var s: Vector2 = RescueManager.boat_stop_pos(v, p)
			stops += 1
			if not _river(s):
				dry.append(p)
			v.free()
	_check(stops > 0 and dry.is_empty(), 'ca-nô cập bến dừng trên nước (%d bến)%s' % [stops, '' if dry.is_empty() else ', lên cạn ở: %s' % str(dry)])
	# Có nút sông trước đó trên đường: ca-nô dừng sớm dọc đoạn sông đó để không đè lên lô đất khu, nhà.
	var tried := 0
	var bad := []
	for p in GraphManager.get_node_ids():
		var pn := GraphManager.get_map_node(p)
		if pn.kind == Types.NodeKind.HUB:
			continue
		for w in GraphManager.get_dock_nodes(p):
			for b in GraphManager.get_water_neighbors(w):
				var v = RescueManager.Vehicle.new()
				v.type = BOAT
				v.hub_id = CAT_LAI
				var path := PathResult.new()
				path.found = true
				path.node_ids.append_array([b, w, p])
				path.edge_ids.append_array([-1, -1])
				v.path = path
				v.path_index = 1
				var s: Vector2 = RescueManager.boat_stop_pos(v, p)
				v.path_index = 0
				var early: Vector2 = RescueManager.arrive_pos(v, w)
				tried += 1
				var clear := s.distance_to(pn.pos) >= GraphManager.point_radius(p) + RescueManager.BOAT_CLEAR - 0.01 or s == GraphManager.get_map_node(b).pos
				if not _river(s) or not clear or early != s:
					bad.append(p)
				v.free()
				break
	_check(tried > 0 and bad.is_empty(), 'ca-nô cập bến khu, nhà dừng trên nước, không đè lên lô đất, dừng một lần (%d trường hợp)%s' % [tried, '' if bad.is_empty() else ', lỗi ở: %s' % str(bad)])
	var n := RescueManager.slot_count(CAT_LAI, BOAT)
	var slot_ok := n > 0
	for i in n:
		slot_ok = slot_ok and _river(RescueManager.slot_point(CAT_LAI, BOAT, i))
	_check(slot_ok, 'chỗ đỗ ca-nô ở bến Cát Lái (%d chỗ) đều nằm trên sông' % n)
	var parked := RescueManager._vehicles.values().filter(func(x) -> bool: return x.type == BOAT and x.slot >= 0)
	_check(not parked.is_empty() and parked.all(func(x) -> bool: return _river(x.position)), 'ca-nô đang đỗ ở bến nằm trên nước')


# Hai ô đất kề nhau a, b: b sát sông (kề 8 hướng với ô ca-nô), a không sát sông; cả hai cách mọi điểm từ 2 ô
# trở lên để không đụng ô điểm hay ô cổng.
func _shore_pair() -> Array:
	var points := GraphManager.get_node_ids().map(func(id: int) -> Vector2i: return GraphManager.cell_of(GraphManager.get_map_node(id).pos))
	var ok := func(c: Vector2i) -> bool:
		if GraphManager.cell_is_boat(c) or GraphManager.cell_is_water(c):
			return false
		return points.all(func(p: Vector2i) -> bool: return maxi(absi(p.x - c.x), absi(p.y - c.y)) >= 2)
	var near := func(c: Vector2i) -> bool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if GraphManager.cell_is_boat(c + Vector2i(dx, dy)):
					return true
		return false
	for y in range(1, Config.GRID_ROWS - 1):
		for x in range(1, Config.GRID_COLS - 1):
			var b := Vector2i(x, y)
			if not ok.call(b) or not near.call(b):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var a: Vector2i = b + d
				if ok.call(a) and not near.call(a):
					return [a, b]
	return []


func _test_flood_links() -> void:
	print('\n== Lối xuống nước (đường sát sông)')
	_fresh_saigon()
	var pair := _shore_pair()
	_check(pair.size() == 2, 'tìm được hai ô đất kề nhau, một ô sát sông')
	if pair.size() != 2:
		return
	var before := GraphManager.get_flood_links()  # lối xuống nước có sẵn của các ô cổng sát sông
	var a := GraphManager.extend_road(-1, pair[0])
	var b := GraphManager.extend_road(a, pair[1])
	_check(a != -1 and b != -1, 'tô được hai ô đường %s, %s' % [pair[0], pair[1]])
	var links := GraphManager.get_flood_links().filter(func(eid: int) -> bool: return not before.has(eid))
	_check(not links.is_empty() and links.all(func(eid: int) -> bool: return GraphManager.get_edge(eid).node_a == b),
			'chỉ ô sát sông có lối xuống nước (%d lối)' % links.size())
	_check(links.all(func(eid: int) -> bool: return not GraphManager.get_edges_of(b).has(eid)), 'lối xuống nước không tính vào cạnh đường bộ của ô')
	FloodManager._update_edges()
	_check(not GraphManager.find_path(CAT_LAI, a, BOAT).found, 'đường khô: ca-nô không lên được')
	_check(not GraphManager.find_path(b, a, BOAT).found and GraphManager.find_path(b, a, TRUCK).found, 'ca-nô không chạy trên đoạn đường khô, xe tải thì được')
	for c in pair:
		FloodManager.set_cell_level(c, GraphManager.cell_elevation(c) + Config.SHALLOW_MAX + 5.0)
	FloodManager._update_edges()
	_check(links.all(func(eid: int) -> bool: return GraphManager.get_edge(eid).state == Types.EdgeState.DEEP), 'ô đường ngập sâu: lối xuống nước ngập sâu theo')
	var p := GraphManager.find_path(CAT_LAI, a, BOAT)
	_check(p.found and p.node_ids.has(b), 'đường ngập: ca-nô từ sông vào được tới ô trong phố (%.1f giây)' % p.cost)
	_check(not GraphManager.find_path(a, CAT_LAI, TRUCK).found, 'xe tải vẫn không xuống sông')
	GraphManager.remove_road(pair[1])
	_check(GraphManager.get_flood_links().size() == before.size() and not GraphManager._badj.has(b), 'xóa ô đường: lối xuống nước bị gỡ theo')
	_check(not GraphManager.find_path(CAT_LAI, a, BOAT).found, 'mất ô sát sông thì ca-nô không tới được ô còn lại')


# Dijkstra cũ (quét mọi nút, O(V²)), chỉ trên _adj: làm chuẩn để so với bản dùng heap trên map_01 (không có sông).
func _old_cost(from_id: int, to_id: int, vehicle_type: int) -> float:
	var dist := {}
	var unvisited: Array = GraphManager._nodes.keys()
	for id in unvisited:
		dist[id] = INF
	dist[from_id] = 0.0
	while not unvisited.is_empty():
		var u := -1
		var best := INF
		for id in unvisited:
			if dist[id] < best:
				best = dist[id]
				u = id
		if u == -1 or u == to_id:
			break
		unvisited.erase(u)
		for eid in GraphManager._adj[u]:
			var e: Edge = GraphManager._edges[eid]
			var f := e.speed_factor(vehicle_type)
			if f <= 0.0:
				continue
			var v := e.other_end(u)
			var cost := e.length / (Config.base_speed(vehicle_type) * f)
			if dist[u] + cost < dist[v]:
				dist[v] = dist[u] + cost
	return dist[to_id]


# Vùng ngập: ô đất ngập sâu thành nước cho ca-nô, nên ca-nô chạy thẳng qua vùng lũ (không chỉ sông, đường) tới khu bị ngập quanh.
func _test_flood_area() -> void:
	print('
== Ca-nô chạy qua vùng ngập')
	_fresh_saigon()
	var inland := 15  # Kinh Dương Vương: không sát sông
	_check(not GraphManager.has_dock(inland) and not GraphManager.find_path(CAT_LAI, inland, BOAT).found,
			'lúc khô: ca-nô không tới được khu không sát sông, không có đường')
	var flood_nodes := func() -> int: return GraphManager._water.keys().filter(func(id: int) -> bool: return GraphManager.is_flood_node(id)).size()
	_check(flood_nodes.call() == 0, 'lúc khô: chưa có ô vùng ngập nào')
	FloodManager.fill_all(100.0)  # ngập sâu cả bản đồ
	FloodManager._update_edges()
	var n: int = flood_nodes.call()
	_check(n > 200, 'ngập sâu: ô đất thành vùng nước cho ca-nô (%d ô)' % n)
	var on_points := false
	for id in GraphManager.get_node_ids():
		on_points = on_points or GraphManager._flood_at(GraphManager.cell_of(GraphManager.get_map_node(id).pos)) != -1
	_check(not on_points, 'ô của kho, khu, nhà không thành nút nước')
	var p := GraphManager.find_path(CAT_LAI, inland, BOAT)
	_check(p.found and p.node_ids.any(func(id: int) -> bool: return GraphManager.is_flood_node(id)),
			'ngập sâu: ca-nô từ Cát Lái chạy qua vùng ngập tới Kinh Dương Vương mà không cần đường (%.1f giây)' % p.cost)
	_check(not GraphManager.find_path(TAN_SON_NHAT, inland, TRUCK).found, 'xe tải vẫn không chạy qua vùng ngập')
	# Lao thẳng trên nước thoáng: bỏ các nút gấp khúc, đoạn tắt nào cũng đi trọn trên ô ngập sâu hoặc ô sông.
	var s := GraphManager.smooth_boat_path(p)
	var length := func(q: PathResult) -> float:
		var sum := 0.0
		for k in q.node_ids.size() - 1:
			sum += GraphManager.get_map_node(q.node_ids[k]).pos.distance_to(GraphManager.get_map_node(q.node_ids[k + 1]).pos)
		return sum
	_check(s.found and s.node_ids.size() < p.node_ids.size() and length.call(s) < length.call(p) - 1.0,
			'ngập sâu: đường ca-nô được làm thẳng (%d → %d điểm, %.0f → %.0f px)' % [p.node_ids.size(), s.node_ids.size(), length.call(p), length.call(s)])
	_check(s.node_ids[0] == p.node_ids[0] and s.node_ids[-1] == p.node_ids[-1] and s.edge_ids.size() == s.node_ids.size() - 1, 'đường làm thẳng giữ đầu, cuối, đủ cạnh')
	var dry := 0
	for k in s.node_ids.size() - 1:
		var a: Vector2 = GraphManager.get_map_node(s.node_ids[k]).pos
		var b: Vector2 = GraphManager.get_map_node(s.node_ids[k + 1]).pos
		var e := GraphManager.get_edge(s.edge_ids[k])
		if e == null or not e.boat_only:
			dry += 1
			continue
		var steps := maxi(1, ceili(a.distance_to(b) / 4.0))
		for m in range(1, steps):
			var c := GraphManager.cell_of(a.lerp(b, float(m) / steps))
			if c == GraphManager.cell_of(a) or c == GraphManager.cell_of(b):
				continue
			if not (GraphManager.cell_is_water(c) or FloodManager.depth_at(c) >= Config.SHALLOW_MAX):
				dry += 1
	_check(dry == 0, 'mọi đoạn ca-nô đi (kể cả đoạn tắt) nằm trên ô sông hoặc ô ngập sâu')
	_check(GraphManager.smooth_boat_path(p).edge_ids == s.edge_ids, 'đoạn tắt dùng lại, không tạo thêm khi tìm lại đường')
	var shortcuts := s.edge_ids.filter(func(eid: int) -> bool: return not p.edge_ids.has(eid))
	_check(not shortcuts.is_empty() and shortcuts.all(func(eid: int) -> bool: return not GraphManager.get_edge_ids().has(eid)),
			'đoạn tắt (%d) không lẫn vào danh sách cạnh đường bộ' % shortcuts.size())
	var before: int = flood_nodes.call()
	FloodManager._update_edges()
	_check(flood_nodes.call() == before, 'mỗi ô chỉ thêm một lần')
	_check(RescueManager._dock_slots(CAT_LAI).all(func(id: int) -> bool: return not GraphManager.is_flood_node(id)),
			'chỗ đỗ ở bến kho vẫn trên sông, không dời sang vùng ngập')
	_fresh_saigon()
	_check(flood_nodes.call() == 0, 'ván mới: vùng ngập xóa sạch')


func _test_heap_matches_old() -> void:
	print('\n== Dijkstra dùng heap khớp bản cũ (map_01)')
	GraphManager.load_map(MAP_01)
	var ids := {}
	for pr in [[0, 3], [0, 2], [2, 4], [3, 5], [4, 5], [5, 7], [1, 2], [6, 7], [8, 9], [3, 8], [6, 9]]:
		ids[pr] = GraphManager.add_edge(pr[0], pr[1])
	var last := GraphManager.extend_road(-1, Vector2i(20, 10))
	for x in range(21, 25):
		last = GraphManager.extend_road(last, Vector2i(x, 10))
	GraphManager.set_edge_state(ids[[3, 5]], Types.EdgeState.DEEP)
	GraphManager.set_edge_state(ids[[2, 4]], Types.EdgeState.SHALLOW)
	GraphManager.set_edge_state(ids[[6, 7]], Types.EdgeState.DEEP)
	GraphManager.set_edge_state(ids[[8, 9]], Types.EdgeState.SHALLOW)
	var same := true
	var pairs := 0
	for vt in [TRUCK, BOAT]:
		for a in GraphManager.get_node_ids():
			for b in GraphManager.get_node_ids():
				var p := GraphManager.find_path(a, b, vt)
				var old := _old_cost(a, b, vt)
				pairs += 1
				if p.found != (old < INF) or (p.found and absf(p.cost - old) > 1e-4):
					same = false
					print('    khác: %d -> %d loại %d: heap %s %.4f, cũ %.4f' % [a, b, vt, p.found, p.cost, old])
	_check(same, 'chi phí và có/không có đường giống hệt bản cũ (%d cặp, cả xe tải lẫn ca-nô)' % pairs)
	var p0 := GraphManager.find_path(0, 0, TRUCK)
	_check(p0.found and p0.node_ids.size() == 1 and p0.cost == 0.0, 'cùng nút: có đường, 1 nút, chi phí 0')
	_check(not GraphManager.find_path(0, 99, TRUCK).found, 'nút lạ: không có đường')


func _test_tree() -> void:
	print('\n== Cây đường ngắn nhất (điều phối)')
	_fresh_saigon()
	for vt in [BOAT, TRUCK]:
		var tree := GraphManager.shortest_tree(CAT_LAI, vt)
		var all_same := true
		for id in GraphManager.get_node_ids():
			var a := GraphManager.path_from_tree(tree, CAT_LAI, id)
			var b := GraphManager.find_path(CAT_LAI, id, vt)
			if a.found != b.found or (a.found and (absf(a.cost - b.cost) > 1e-4 or a.edge_ids.size() + 1 != a.node_ids.size())):
				all_same = false
		_check(all_same,'path_from_tree khớp find_path cho mọi điểm (%s)' % ('ca-nô' if vt == BOAT else 'xe tải'))
	var tree := GraphManager.shortest_tree(CAT_LAI, BOAT)
	_check(not GraphManager.path_from_tree(tree, TAN_SON_NHAT, CALMETTE).found, 'cây của nút khác thì không dùng được')
	_check(GraphManager.shortest_tree(99999, BOAT).dist.is_empty(), 'cây từ nút lạ: rỗng')


func _test_timing() -> void:
	print('\n== Thời gian tìm đường của ca-nô')
	_fresh_saigon()
	var tree := GraphManager.shortest_tree(CAT_LAI, BOAT)
	var far := CAT_LAI
	for id in tree.dist:
		if tree.dist[id] > tree.dist[far]:
			far = id
	const RUNS := 20
	var t0 := Time.get_ticks_usec()
	for i in RUNS:
		GraphManager.find_path(CAT_LAI, far, BOAT)
	var path_ms := (Time.get_ticks_usec() - t0) / 1000.0 / RUNS
	t0 = Time.get_ticks_usec()
	for i in RUNS:
		GraphManager.shortest_tree(CAT_LAI, BOAT)
	var tree_ms := (Time.get_ticks_usec() - t0) / 1000.0 / RUNS
	print('    find_path ca-nô dài nhất (%d nút nước): %.2f ms; shortest_tree: %.2f ms' % [GraphManager._water.size(), path_ms, tree_ms])
	_check(path_ms < 20.0 and tree_ms < 20.0, 'tìm đường ca-nô nhanh (mục tiêu dưới 5 ms, giới hạn kiểm tra 20 ms)')


func _test_dispatch() -> void:
	print('\n== Điều phối ca-nô dọc sông')
	_fresh_saigon()
	var rescued := [false]
	var on_rescued := func(_rid: int, _pts: int) -> void: rescued[0] = true
	EventBus.sos_rescued.connect(on_rescued)
	var req := RescueManager.SosRequest.new()
	req.id = 900
	req.node_id = CALMETTE
	req.supply = Types.SupplyType.FOOD
	req.time_total = 600.0
	req.time_left = 600.0
	RescueManager._requests[req.id] = req
	RescueManager._dispatch()
	var v = RescueManager._vehicles.get(req.vehicle_id)
	_check(v != null and v.type == BOAT, 'chưa có đường: SOS ở Calmette (sát sông) được giao cho ca-nô')
	if v == null:
		EventBus.sos_rescued.disconnect(on_rescued)
		return
	_check(v.path.edge_ids.all(func(eid: int) -> bool: return GraphManager.get_edge(eid).boat_only), 'ca-nô chỉ đi cạnh sông và bến')
	var frames := 0
	var landed := 0  # số khung hình ca-nô (đang chạy, giao hàng) nằm ngoài sông
	while not rescued[0] and frames < 1800:
		await get_tree().process_frame
		frames += 1
		if v.state_id == Types.VehicleState.DELIVERING and not _river(v.position):
			landed += 1
	_check(rescued[0], 'ca-nô chạy dọc sông tới nơi và giao hàng (%d khung hình)' % frames)
	_check(landed == 0, 'ca-nô giao hàng dừng trên nước (không lên bờ)')
	EventBus.sos_rescued.disconnect(on_rescued)
	RescueManager._requests.clear()


# Nhà, khu chưa nối đường: ca-nô cứu được khi sát sông hoặc xung quanh đã ngập sâu; trong đất liền còn khô thì không xe nào.
func _test_unconnected() -> void:
	print('
== Ca-nô cứu nhà, khu chưa nối đường')
	_fresh_saigon()
	var inland := 15  # Kinh Dương Vương: không sát sông
	var dry_req := _sos(901, inland)
	RescueManager._dispatch()
	_check(dry_req.assigned == 0 and dry_req.vehicle_id == -1, 'khu trong đất liền còn khô, chưa nối đường: không xe nào nhận')
	RescueManager._requests.clear()
	FloodManager.fill_all(100.0)
	FloodManager._update_edges()
	var flood_req := _sos(902, inland)
	RescueManager._dispatch()
	var fv = RescueManager._vehicles.get(flood_req.vehicle_id)
	_check(fv != null and fv.type == BOAT, 'khu đó ngập sâu xung quanh: ca-nô nhận SOS dù chưa có đường')
	if fv != null:
		_check(await _until_rescued(902), 'ca-nô chạy qua vùng ngập tới giao hàng xong')
	RescueManager._requests.clear()
	_fresh_saigon()
	var cell := Vector2i(-1, -1)
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			var c := Vector2i(x, y)
			if cell != Vector2i(-1, -1) or not GraphManager.can_place_house(c) or not GameManager.is_in_play(GraphManager.cell_center(c)):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if GraphManager.cell_is_boat(c + d):
					cell = c
	var house := GraphManager.add_house(cell, CALMETTE) if cell != Vector2i(-1, -1) else -1
	_check(house != -1 and GraphManager.get_gate_node(house) == -1 and GraphManager.has_dock(house), 'nhà mọc sát sông, chưa nối đường, có bến (ô %s)' % cell)
	if house == -1:
		return
	var house_req := _sos(903, house)
	RescueManager._dispatch()
	var hv = RescueManager._vehicles.get(house_req.vehicle_id)
	_check(hv != null and hv.type == BOAT, 'SOS ở nhà đó được giao cho ca-nô')
	if hv != null:
		_check(await _until_rescued(903), 'ca-nô chạy dọc sông tới nhà giao hàng xong')
	RescueManager._requests.clear()


func _sos(id: int, node: int) -> RescueManager.SosRequest:
	var req := RescueManager.SosRequest.new()
	req.id = id
	req.node_id = node
	req.supply = Types.SupplyType.FOOD
	req.time_total = 600.0
	req.time_left = 600.0
	RescueManager._requests[id] = req
	return req


func _until_rescued(id: int) -> bool:
	var done := [false]
	var on := func(rid: int, _p: int) -> void:
		if rid == id:
			done[0] = true
	EventBus.sos_rescued.connect(on)
	var frames := 0
	while not done[0] and frames < 2400:
		await get_tree().process_frame
		frames += 1
	EventBus.sos_rescued.disconnect(on)
	return done[0]


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT] ' + label)
	else:
		_failed += 1
		printerr('  [TRƯỢT] ' + label)
