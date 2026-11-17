extends Node
# Test tự động cho kẹt xe (RescueManager.congestion_factor, congestion_penalty, GraphManager.find_path có edge_penalty).
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_traffic_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const FIXTURE_MAP := 'res://data/map_01.json'

var _passed := 0
var _failed := 0
var _cars: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	_test_follow()
	_test_junction()
	_test_penalty()
	for c in _cars:
		c.free()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# Ngã ba chữ T ở ô (19, 14): nhánh tây (18, 14), nhánh đông (20, 14), nhánh bắc (19, 13).
func _t_junction() -> Dictionary:
	var w := GraphManager.extend_road(-1, Vector2i(18, 14))
	var j := GraphManager.extend_road(w, Vector2i(19, 14))
	var e := GraphManager.extend_road(j, Vector2i(20, 14))
	var n := GraphManager.extend_road(j, Vector2i(19, 13))
	return {w = w, j = j, e = e, n = n}


func _edge_between(a: int, b: int) -> int:
	for eid in GraphManager.get_edges_of(a):
		if GraphManager.get_edge(eid).other_end(a) == b:
			return eid
	return -1


# Xe giả đang chạy từ node a tới node b, đặt ở vị trí pos.
func _car(id: int, pos: Vector2, a: int, b: int, state: int = Types.VehicleState.EN_ROUTE):
	var v = RescueManager.Vehicle.new()
	v.id = id
	v.position = pos
	v.heading = pos.direction_to(GraphManager.get_map_node(b).pos)
	v.state_id = state
	var p := PathResult.new()
	p.found = true
	p.node_ids.append(a)
	p.node_ids.append(b)
	p.edge_ids.append(_edge_between(a, b))
	v.path = p
	v.path_index = 0
	_cars.append(v)
	return v


func _test_follow() -> void:
	print('\n== Bám đuôi')
	var t := _t_junction()
	var jp: Vector2 = GraphManager.get_map_node(t.j).pos
	var start: Vector2 = GraphManager.get_map_node(t.w).pos
	var a = _car(1, start, t.w, t.j)
	var near = _car(2, start + Vector2(26, 0), t.w, t.j)
	var close = _car(3, start + Vector2(14, 0), t.w, t.j)
	var opposite = _car(4, jp, t.j, t.w)
	opposite.position = start + Vector2(26, 0)
	var behind = _car(5, start - Vector2(20, 0), t.w, t.j)
	var parked = _car(6, start + Vector2(14, 0), t.w, t.j, Types.VehicleState.DELIVERING)
	_check(RescueManager.congestion_factor(a, [a, near]) == RescueManager.FOLLOW_SLOW, 'xe phía trước cùng làn cách 26 px: chạy chậm 50%')
	_check(RescueManager.congestion_factor(a, [a, close]) == 0.0, 'cách 14 px: dừng chờ')
	_check(RescueManager.congestion_factor(a, [a, opposite]) == 1.0, 'xe ngược chiều ở làn bên kia không làm chậm')
	_check(RescueManager.congestion_factor(a, [a, behind]) == 1.0, 'xe phía sau không làm chậm')
	_check(RescueManager.congestion_factor(a, [a, parked]) == 1.0, 'xe đang dỡ hàng không chặn xe chỉ đi ngang')
	var unloading = _car(7, GraphManager.get_map_node(t.j).pos, t.w, t.j, Types.VehicleState.DELIVERING)
	unloading.current_node = t.j
	unloading.dest = t.j
	var queued = _car(8, GraphManager.get_map_node(t.j).pos - Vector2(25, 0), t.w, t.j)
	queued.dest = t.j
	queued.request = RescueManager.SosRequest.new()
	_check(RescueManager.congestion_factor(queued, [queued, unloading]) == 0.0, 'xe tới cùng SOS chờ xe trước dỡ hàng xong')


func _test_junction() -> void:
	print('\n== Ngã ba')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	var t := _t_junction()
	_check(GraphManager.get_edges_of(t.j).size() == 3, 'ô (19, 14) là ngã ba')
	var jp: Vector2 = GraphManager.get_map_node(t.j).pos
	var west = _car(10, jp - Vector2(35, 0), t.w, t.j)
	var inside = _car(11, jp - Vector2(0, 18), t.n, t.j)
	_check(RescueManager.congestion_factor(west, [west, inside]) == 0.0, 'xe đang ở trong ngã ba được đi trước, xe sắp vào phải chờ')
	_check(RescueManager.congestion_factor(inside, [west, inside]) == 1.0, 'xe trong ngã ba đi tiếp')
	var far_north = _car(12, jp - Vector2(0, 42), t.n, t.j)
	_check(RescueManager.congestion_factor(west, [west, far_north]) == 1.0
			and RescueManager.congestion_factor(far_north, [west, far_north]) == 0.0, 'xe gần ngã ba hơn đi trước, xe xa hơn nhường')
	var tie_north = _car(13, jp - Vector2(0, 35), t.n, t.j)
	_check(RescueManager.congestion_factor(west, [west, tie_north]) == 1.0
			and RescueManager.congestion_factor(tie_north, [west, tie_north]) == 0.0, 'cách đều thì xe mã nhỏ đi trước, không cùng chờ nhau')
	var east = _car(14, jp + Vector2(35, 0), t.e, t.j)
	_check(RescueManager.congestion_factor(west, [west, east]) == 1.0, 'hai xe đi thẳng ngược chiều qua ngã ba không phải nhường')


func _test_penalty() -> void:
	print('\n== Tìm đường né chỗ đông')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	var e03 := GraphManager.add_edge(0, 3)
	var e35 := GraphManager.add_edge(3, 5)
	var e57 := GraphManager.add_edge(5, 7)
	GraphManager.add_edge(0, 2)
	GraphManager.add_edge(2, 4)
	GraphManager.add_edge(4, 5)
	var p1 := GraphManager.find_path(0, 7, Types.VehicleType.TRUCK)
	_check(p1.edge_ids.has(e03), 'không có xe: đi đường ngắn 0-3-5-7')
	var p2 := GraphManager.find_path(0, 7, Types.VehicleType.TRUCK, {e03: 5.0})
	_check(not p2.edge_ids.has(e03) and p2.found, 'cạnh 0-3 đông xe: chuyển sang đường vòng 0-2-4-5-7')
	var busy = RescueManager.Vehicle.new()
	busy.id = 99
	busy.state_id = Types.VehicleState.EN_ROUTE
	busy.path = p1
	busy.path_index = 0
	_cars.append(busy)
	RescueManager._vehicles[99] = busy
	var pen: Dictionary = RescueManager.congestion_penalty()
	_check(pen.get(e03, 0.0) == RescueManager.CONGESTION_PATH_COST and pen.has(e35) and pen.has(e57),
			'xe đang chạy làm 3 cạnh sắp đi đắt thêm %.1f giây' % RescueManager.CONGESTION_PATH_COST)
	_check(RescueManager.congestion_penalty(busy).is_empty(), 'xe tự tính lại đường không né chính nó')
	RescueManager._vehicles.erase(99)


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT] ' + label)
	else:
		_failed += 1
		printerr('  [TRƯỢT] ' + label)
