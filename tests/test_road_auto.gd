extends Node
# Test tự động cho đường theo ô: ô đường, đoạn, hạn mức, lũ theo đoạn, xe hai làn.
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_road_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const HUB := 0        # Kho Bắc, ô (5, 3)
const MARKET := 3     # Khu Chợ Cũ, ô (10, 5)
const CHAIN: Array[Vector2i] = [Vector2i(6, 3), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 5)]

var _passed := 0
var _failed := 0
var _road_changed := 0
var _warnings := 0
var _rescued := 0


func _ready() -> void:
	EventBus.road_changed.connect(func() -> void: _road_changed += 1)
	EventBus.flood_warning.connect(func(_e: int, _s: float) -> void: _warnings += 1)
	EventBus.sos_rescued.connect(func(_r: int, _p: int) -> void: _rescued += 1)
	_run.call_deferred()


func _run() -> void:
	_test_cells()
	_test_budget()
	_test_segments()
	_test_remove()
	_test_flood()
	await _test_vehicle_lane()
	await _test_erase_under_vehicle()
	await _test_finish_segment()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_cells() -> void:
	print('\n== Ô đường')
	_fresh()
	_check(GraphManager.cell_of(Vector2(200, 120)) == Vector2i(5, 3), 'cell_of đổi tọa độ sang ô')
	_check(GraphManager.cell_center(Vector2i(5, 3)) == Vector2(220, 140), 'cell_center trả tâm ô')
	var free := GraphManager.extend_road(-1, Vector2i(20, 10))
	var n := GraphManager.get_map_node(free)
	_check(free >= 0 and n.kind == Types.NodeKind.ROAD, 'tô ô trống tạo nút loại ROAD')
	_check(n.pos == GraphManager.cell_center(Vector2i(20, 10)), 'nút ô đường nằm ở tâm ô')
	_check(GraphManager.get_node_ids().size() == 10, 'get_node_ids vẫn chỉ trả 10 điểm')
	_check(GraphManager.extend_road(-1, Vector2i(-1, 0)) == -1, 'ô ngoài lưới bên trái bị từ chối')
	_check(GraphManager.extend_road(-1, Vector2i(32, 0)) == -1, 'ô ngoài lưới bên phải bị từ chối')
	var used: int = GraphManager.get_edge_budget().used
	_check(GraphManager.extend_road(-1, _cell(HUB)) == HUB, 'ô của một điểm trả về chính điểm đó')
	_check(GraphManager.get_edge_budget().used == used, 'chạm vào điểm không tốn hạn mức')

	var a := GraphManager.extend_road(HUB, CHAIN[0])
	_check(a >= 0 and GraphManager.get_edges_of(HUB).size() == 1, 'kéo từ điểm sang ô kề tạo một cạnh')
	_check(GraphManager.extend_road(a, Vector2i(9, 9)) == -1, 'ô không kề với nút trước bị từ chối')
	var b := GraphManager.extend_road(a, CHAIN[1])
	var diag := GraphManager.get_edge(GraphManager.get_edges_of(b)[0])
	_check(absf(diag.length - 40.0 * sqrt(2.0)) < 0.1, 'cạnh chéo dài bằng đường chéo ô')
	var edges := GraphManager.get_edge_ids().size()
	var budget: int = GraphManager.get_edge_budget().used
	GraphManager.extend_road(a, CHAIN[1])
	_check(GraphManager.get_edge_ids().size() == edges and GraphManager.get_edge_budget().used == budget,
			'kéo lại đoạn đã có không tạo thêm và không tốn hạn mức')

	_fresh()
	_chain()
	var p := GraphManager.find_path(HUB, MARKET, Types.VehicleType.TRUCK)
	_check(p.found and p.node_ids[0] == HUB and p.node_ids[-1] == MARKET and p.node_ids.size() == 6,
			'find_path đi qua 4 ô từ Kho Bắc tới Chợ Cũ')

	_fresh()
	var top := GraphManager.extend_road(-1, Vector2i(20, 10))
	var below := GraphManager.extend_road(-1, Vector2i(20, 11))
	_check(GraphManager.get_edges_of(top).is_empty() and GraphManager.get_edges_of(below).is_empty(),
			'hai ô nằm sát nhau không tự nối')


func _test_budget() -> void:
	print('\n== Hạn mức theo ô')
	_fresh()
	var limit: int = GraphManager.get_edge_budget().limit
	for i in limit:
		GraphManager.extend_road(-1, Vector2i(i % Config.GRID_COLS, 16 + i / Config.GRID_COLS))
	_check(GraphManager.get_edge_budget().used == limit, 'tô đúng %d ô thì dùng hết hạn mức' % limit)
	_check(GraphManager.extend_road(-1, Vector2i(30, 2)) == -1, 'hết hạn mức thì ô mới bị từ chối')
	var first := GraphManager.road_at(Vector2i(0, 16))
	var again := GraphManager.road_at(Vector2i(1, 16))
	_check(GraphManager.extend_road(first, Vector2i(1, 16)) == again, 'hết hạn mức vẫn đi lại được trên ô đã có')
	GraphManager.add_edge_limit(2)
	_check(GraphManager.extend_road(-1, Vector2i(30, 2)) >= 0, 'sau add_edge_limit tô thêm được')
	var id := GraphManager.road_at(Vector2i(30, 2))
	EventBus.game_started.emit()
	_check(GraphManager.get_edge_budget().used == 0 and GraphManager.get_edge_budget().limit == limit,
			'game_started đặt lại hạn mức')
	_check(GraphManager.get_map_node(id) == null and GraphManager.get_edge_ids().is_empty(),
			'game_started xóa hết ô đường và cạnh')


func _test_segments() -> void:
	print('\n== Đoạn')
	_fresh()
	var ids := _chain()
	var edges := GraphManager.get_edge_ids()
	_check(edges.size() == 5, 'chuỗi 4 ô giữa hai điểm có 5 cạnh')
	var seg: int = GraphManager.get_edge(edges[0]).segment
	var elev: float = GraphManager.get_edge(edges[0]).elevation
	var same := true
	for e in edges:
		same = same and GraphManager.get_edge(e).segment == seg and GraphManager.get_edge(e).elevation == elev
	_check(same, 'cả chuỗi cùng một đoạn, cùng độ cao')
	var sum := GraphManager.get_map_node(HUB).elevation + GraphManager.get_map_node(MARKET).elevation
	for id in ids:
		sum += GraphManager.get_map_node(id).elevation
	_check(absf(elev - sum / 6.0) < 0.01, 'độ cao đoạn là trung bình các nút (%.1f)' % elev)
	_check(GraphManager.get_segment_edges(edges[2]).size() == 5, 'get_segment_edges trả cả đoạn')

	var fork := GraphManager.extend_road(ids[1], Vector2i(7, 5))
	_check(fork >= 0, 'thêm ngã rẽ giữa chuỗi')
	var near: int = GraphManager.get_edges_of(HUB)[0]
	var far: int = GraphManager.get_edges_of(MARKET)[0]
	_check(GraphManager.get_edge(near).segment != GraphManager.get_edge(far).segment, 'ngã rẽ tách chuỗi thành hai đoạn')
	_check(GraphManager.get_segment_edges(near).size() == 2 and GraphManager.get_segment_edges(far).size() == 3,
			'hai đoạn có 2 và 3 cạnh')
	_check(GraphManager.get_edge(near).elevation > GraphManager.get_edge(far).elevation,
			'đoạn gần kho (cao) có độ cao lớn hơn đoạn gần chợ')

	_fresh()
	var ring := [Vector2i(20, 8), Vector2i(21, 8), Vector2i(21, 9), Vector2i(20, 9)]
	var prev := -1
	for c in ring:
		prev = GraphManager.extend_road(prev, c)
	var start := GraphManager.road_at(ring[0])
	GraphManager.extend_road(prev, ring[0])
	var all := GraphManager.get_edge_ids()
	_check(all.size() == 4 and GraphManager.get_segment_edges(all[0]).size() == 4 and start >= 0,
			'vòng kín không có đầu mút vẫn là một đoạn')

	_fresh()
	var before := _road_changed
	GraphManager.extend_road(-1, Vector2i(20, 8))
	_check(_road_changed > before, 'tô ô phát road_changed')
	before = _road_changed
	GraphManager.remove_road(Vector2i(20, 8))
	_check(_road_changed > before, 'xóa ô phát road_changed')


func _test_remove() -> void:
	print('\n== Xóa ô')
	_fresh()
	var ids := _chain()
	var used: int = GraphManager.get_edge_budget().used
	_check(GraphManager.remove_road(CHAIN[1]), 'remove_road trả true khi có ô')
	_check(GraphManager.get_map_node(ids[1]) == null, 'nút ô đã xóa biến mất')
	_check(GraphManager.get_edge_budget().used == used - 1, 'xóa ô hoàn 1 hạn mức')
	_check(GraphManager.get_edge_ids().size() == 3, 'các cạnh nối vào ô đã xóa cũng mất')
	_check(not GraphManager.find_path(HUB, MARKET, Types.VehicleType.TRUCK).found, 'đường bị cắt thì không còn đường đi')
	_check(not GraphManager.remove_road(Vector2i(30, 2)), 'xóa ô trống trả false')
	_check(not GraphManager.remove_road(_cell(HUB)), 'không xóa được ô của một điểm')
	_check(GraphManager.extend_road(ids[0], CHAIN[1]) == ids[1], 'tô lại ô cho đúng mã nút cũ')


func _test_flood() -> void:
	print('\n== Lũ theo đoạn')
	_fresh()
	var ids := _chain()
	var edges := GraphManager.get_edge_ids()
	var elev: float = GraphManager.get_edge(edges[0]).elevation
	FloodManager.water_level = elev + 1.0
	FloodManager._update_edges()
	_check(edges.all(func(e: int) -> bool: return GraphManager.get_edge(e).state == Types.EdgeState.SHALLOW),
			'nước vượt độ cao đoạn thì cả đoạn ngập nhẹ cùng lúc')

	_fresh()
	ids = _chain()
	edges = GraphManager.get_edge_ids()
	elev = GraphManager.get_edge(edges[0]).elevation
	_warnings = 0
	FloodManager._rate = 1.0
	FloodManager.water_level = elev - 1.0
	FloodManager._update_edges()
	_check(_warnings == 1, 'mỗi đoạn chỉ cảnh báo một lần (%d)' % _warnings)

	_fresh()
	ids = _chain()
	GraphManager.extend_road(ids[1], Vector2i(7, 5))
	var near: int = GraphManager.get_edges_of(HUB)[0]
	var far: int = GraphManager.get_edges_of(MARKET)[0]
	var high: float = GraphManager.get_edge(near).elevation
	var low: float = GraphManager.get_edge(far).elevation
	GraphManager.remove_road(Vector2i(7, 5))
	FloodManager.water_level = (high + low) / 2.0
	FloodManager._update_edges()
	var merged: int = GraphManager.get_edge(near).state
	GraphManager.extend_road(ids[1], Vector2i(7, 5))
	_check(GraphManager.get_edge(near).state == Types.EdgeState.DRY
			and GraphManager.get_edge(far).state == Types.EdgeState.SHALLOW and merged != -1,
			'tách đoạn lúc nước đứng yên thì trạng thái cập nhật ngay')

	_fresh()
	_chain()
	var overlay: Node2D = load('res://ui/flood_warning_overlay.gd').new()
	add_child(overlay)
	edges = GraphManager.get_edge_ids()
	EventBus.flood_warning.emit(edges[2], 3.0)
	var item: Dictionary = overlay.active.get(edges[2], {})
	_check(item.get('links', []).size() == 5, 'cảnh báo nháy cả đoạn, không chỉ một cạnh')
	overlay.free()


func _test_vehicle_lane() -> void:
	print('\n== Xe hai làn')
	_fresh()
	_chain()
	var truck := _truck()
	_sos(100)
	await _wait(func() -> bool: return truck.state_id == Types.VehicleState.EN_ROUTE and truck.path_index >= 1)
	await _frames(20)
	_check(truck.state_id == Types.VehicleState.EN_ROUTE, 'xe tải nhận SOS và chạy trên đường ô')
	var want := truck.heading.rotated(PI / 2.0) * RescueManager.Vehicle.LANE_OFFSET
	_check(truck.lane_offset().distance_to(want) < 0.5, 'xe chạy lệch sang bên phải hướng đi')
	_check(_on_road(truck.position), 'vị trí tính đường của xe vẫn nằm giữa đường')
	await _wait(func() -> bool: return _rescued > 0)
	_check(_rescued == 1, 'xe giao hàng tới nơi')
	await _wait(func() -> bool: return truck.state_id == Types.VehicleState.IDLE)
	_check(truck.state_id == Types.VehicleState.IDLE and truck.lane_offset() == Vector2.ZERO, 'về kho thì đứng yên, hết lệch làn')


func _test_erase_under_vehicle() -> void:
	print('\n== Xóa ô dưới xe')
	_fresh()
	_chain()
	var truck := _truck()
	var stock := RescueManager.get_stock(HUB, Types.SupplyType.FOOD)
	var req := _sos(101)
	await _wait(func() -> bool: return truck.state_id == Types.VehicleState.EN_ROUTE and truck.path_index >= 2)
	var left: int = truck.path.node_ids[truck.path_index]
	GraphManager.remove_road(GraphManager.cell_of(GraphManager.get_map_node(left).pos))
	await _frames(3)
	_check(truck.state_id == Types.VehicleState.STRANDED, 'ô dưới xe bị xóa thì xe kẹt tại chỗ')
	_check(req.state == Types.SosState.PENDING, 'SOS trả về hàng chờ')
	_check(RescueManager.get_stock(HUB, Types.SupplyType.FOOD) == stock, 'hàng được hoàn về kho')
	GraphManager.extend_road(GraphManager.road_at(CHAIN[0]), CHAIN[1])
	GraphManager.extend_road(GraphManager.road_at(CHAIN[1]), CHAIN[2])
	await _frames(3)
	_check(truck.state_id != Types.VehicleState.STRANDED, 'tô lại ô thì xe hết kẹt')


func _test_finish_segment() -> void:
	print('\n== Xe đi hết đoạn')
	_fresh()
	_chain()
	var truck := _truck()
	_rescued = 0
	_sos(102)
	await _wait(func() -> bool: return truck.state_id == Types.VehicleState.EN_ROUTE and truck.path_index >= 1)
	for e in GraphManager.get_edge_ids():
		GraphManager.set_edge_state(e, Types.EdgeState.DEEP)
	await _wait(func() -> bool: return _rescued > 0 or truck.state_id == Types.VehicleState.STRANDED)
	_check(_rescued == 1, 'đoạn ngập sâu khi xe đang đi: xe đi hết đoạn rồi mới tính lại')


func _fresh() -> void:
	FloodManager.water_level = 0.0
	GraphManager.load_map(Config.MAP_PATH)
	EventBus.game_started.emit()


# Kho Bắc → 4 ô → Chợ Cũ, trả về mã nút của 4 ô.
func _chain() -> Array[int]:
	var ids: Array[int] = []
	var last := HUB
	for c in CHAIN:
		last = GraphManager.extend_road(last, c)
		ids.append(last)
	GraphManager.extend_road(last, _cell(MARKET))
	return ids


func _cell(point: int) -> Vector2i:
	return GraphManager.cell_of(GraphManager.get_map_node(point).pos)


func _truck() -> RescueManager.Vehicle:
	for id in RescueManager.get_vehicle_ids():
		var v: RescueManager.Vehicle = RescueManager._vehicles[id]
		if v.type == Types.VehicleType.TRUCK and v.hub_id == HUB:
			return v
	return null


func _sos(id: int) -> RescueManager.SosRequest:
	var req := RescueManager.SosRequest.new()
	req.id = id
	req.node_id = MARKET
	req.supply = Types.SupplyType.FOOD
	req.time_total = 600.0
	req.time_left = 600.0
	RescueManager._requests[id] = req
	RescueManager.mark_dirty()
	return req


func _on_road(p: Vector2) -> bool:
	for e in GraphManager.get_edge_ids():
		var edge := GraphManager.get_edge(e)
		var a := GraphManager.get_map_node(edge.node_a).pos
		var b := GraphManager.get_map_node(edge.node_b).pos
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 0.5:
			return true
	return false


func _wait(done: Callable) -> void:
	for i in 1800:
		if done.call():
			return
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT]   ', label)
	else:
		_failed += 1
		print('  [TRƯỢT] ', label)
