extends Node
# Test tự động cho kẹt xe (RescueManager.congestion_factor, junction_kind, light_green, congestion_penalty, GraphManager.find_path có edge_penalty).
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_traffic_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const FIXTURE_MAP := 'res://data/map_01.json'
const JunctionLayerScript := preload('res://graph/junction_layer.gd')

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
	_test_light()
	_test_yield_point()
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


# Ngã ba đường tự thành vòng xoay: xe sắp vào chỉ nhường xe đang ở trong vòng, không còn luật ai gần hơn đi trước.
func _test_junction() -> void:
	print('\n== Vòng xoay ở ngã ba')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	var t := _t_junction()
	_check(GraphManager.get_edges_of(t.j).size() == 3, 'ô (19, 14) là ngã ba')
	_check(RescueManager.junction_kind(t.j) == RescueManager.JUNCTION_ROUNDABOUT, 'ngã ba đường tự thành vòng xoay')
	_check(RescueManager.junction_kind(t.w) == RescueManager.JUNCTION_NONE, 'đầu đường không phải nút giao')
	var jp: Vector2 = GraphManager.get_map_node(t.j).pos
	var west = _car(10, jp - Vector2(35, 0), t.w, t.j)
	var inside = _car(11, jp - Vector2(0, 18), t.n, t.j)
	_check(RescueManager.congestion_factor(west, [west, inside]) == 0.0, 'xe sắp vào vòng xoay chờ xe đang ở trong vòng')
	_check(RescueManager.congestion_factor(inside, [west, inside]) == RescueManager.ROUNDABOUT_SLOW,
			'xe trong vòng không phải chờ, chạy chậm %.1f' % RescueManager.ROUNDABOUT_SLOW)
	_check(RescueManager.in_roundabout(inside) and not RescueManager.in_roundabout(west), 'phân biệt xe ở trong vòng và xe sắp vào')
	var far_north = _car(12, jp - Vector2(0, 42), t.n, t.j)
	_check(RescueManager.congestion_factor(west, [west, far_north]) == 1.0
			and RescueManager.congestion_factor(far_north, [west, far_north]) == 1.0, 'hai xe cùng sắp vào vòng xoay thì không ai phải chờ')
	var east = _car(14, jp + Vector2(35, 0), t.e, t.j)
	_check(RescueManager.congestion_factor(west, [west, east]) == 1.0, 'hai xe ngược chiều sắp vào không phải nhường')
	var leaving = _car(15, jp - Vector2(12, 0), t.j, t.w)
	_check(RescueManager.congestion_factor(west, [west, leaving]) == 1.0, 'xe đang ra theo nhánh mình vào (làn bên kia) không làm mình chờ')
	inside._update_lane(1.0)
	_check(inside.lane_offset().distance_to(inside.heading.rotated(PI / 2.0) * RescueManager.RING_RADIUS) < 0.01,
			'xe trong vòng xoay vẽ lệch ra vòng quanh đảo')
	var slowed = _car(16, jp - Vector2(0, 18), t.n, t.j)
	slowed.settle_jam(RescueManager.ROUNDABOUT_SLOW, 1.0)
	_check(not slowed.jammed, 'chạy chậm trong vòng xoay không tính là kẹt (không bật đèn phanh)')
	var layer = JunctionLayerScript.new()
	add_child(layer)
	_check(layer._roundabouts == [t.j] and layer._lights.is_empty(), 'lớp vẽ nút giao nhận ra vòng xoay ở ngã ba')
	layer.free()


# Ngã tư đường tự có đèn: hai trục ngang, dọc luân phiên xanh mỗi LIGHT_PHASE giây.
func _test_light() -> void:
	print('\n== Đèn giao thông ở ngã tư')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	var c := Vector2i(8, 14)
	var w := GraphManager.extend_road(-1, c - Vector2i(1, 0))
	var x := GraphManager.extend_road(w, c)
	GraphManager.extend_road(x, c + Vector2i(1, 0))
	var n := GraphManager.extend_road(x, c - Vector2i(0, 1))
	GraphManager.extend_road(x, c + Vector2i(0, 1))
	_check(RescueManager.junction_kind(x) == RescueManager.JUNCTION_LIGHT, 'ngã tư đường tự có đèn')
	_check(RescueManager.light_green(x, Vector2.RIGHT) != RescueManager.light_green(x, Vector2.DOWN), 'mỗi lúc chỉ một trục xanh')
	var layer = JunctionLayerScript.new()
	add_child(layer)
	_check(layer._lights == [x] and layer._roundabouts.is_empty() and layer.is_processing(), 'lớp vẽ nút giao nhận ra ngã tư có đèn, theo dõi đổi pha')
	layer.free()
	var cp: Vector2 = GraphManager.get_map_node(x).pos
	var saved_clock: float = RescueManager._clock
	RescueManager._clock = 0.0
	if RescueManager.light_green(x, Vector2.RIGHT):
		RescueManager._clock += RescueManager.LIGHT_PHASE  # bắt đầu từ pha trục ngang đỏ
	var west = _car(20, cp - Vector2(35, 0), w, x)
	var north = _car(21, cp - Vector2(0, 35), n, x)
	_check(RescueManager.congestion_factor(west, [west]) == 0.0 and west.at_red, 'trục ngang đỏ: xe phía tây dừng trước vạch')
	_check(RescueManager.congestion_factor(north, [north]) == 1.0 and not north.at_red, 'trục dọc xanh: xe phía bắc đi')
	RescueManager._clock += RescueManager.LIGHT_PHASE
	_check(RescueManager.congestion_factor(west, [west]) == 1.0 and not west.at_red, 'sau một pha: trục ngang xanh, xe phía tây đi')
	_check(RescueManager.congestion_factor(north, [north]) == 0.0 and north.at_red, 'sau một pha: trục dọc đỏ, xe phía bắc dừng')
	var crossing = _car(22, cp - Vector2(0, 10), n, x)
	_check(RescueManager.congestion_factor(west, [west, crossing]) == 0.0, 'đèn xanh vẫn nhường xe còn trong ngã tư đi cắt ngang')
	RescueManager._clock -= RescueManager.LIGHT_PHASE
	var jam := RescueManager.congestion_factor(west, [west])
	_check(west.settle_jam(jam, RescueManager.JAM_GIVE_UP + 1.0) == 0.0 and west.jammed, 'chờ đèn đỏ quá JAM_GIVE_UP vẫn không vượt')
	var stuck = _car(23, cp - Vector2(35, 0), w, x)
	_check(stuck.settle_jam(0.0, RescueManager.JAM_GIVE_UP + 1.0) == RescueManager.FOLLOW_SLOW,
			'kẹt thường (không phải đèn đỏ) quá JAM_GIVE_UP thì đi chậm qua')
	RescueManager._clock = saved_clock


# Luật nhường cũ vẫn dùng ở điểm có từ 3 đường vào (bản đồ không có cổng) và ở chữ T trước cổng nhà.
func _test_yield_point() -> void:
	print('\n== Nhường theo khoảng cách ở điểm có 3 đường vào')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	var p := 5  # Bệnh viện, ô (16, 8)
	var pc := GraphManager.cell_of(GraphManager.get_map_node(p).pos)
	var a := GraphManager.extend_road(p, pc - Vector2i(1, 0))
	GraphManager.extend_road(p, pc + Vector2i(1, 0))
	var c := GraphManager.extend_road(p, pc - Vector2i(0, 1))
	_check(GraphManager.get_edges_of(p).size() == 3 and RescueManager.junction_kind(p) == RescueManager.JUNCTION_YIELD,
			'điểm có 3 đường vào: nhường theo khoảng cách')
	var pp: Vector2 = GraphManager.get_map_node(p).pos
	var west = _car(30, pp - Vector2(35, 0), a, p)
	var inside = _car(31, pp - Vector2(0, 18), c, p)
	_check(RescueManager.congestion_factor(west, [west, inside]) == 0.0, 'xe đang ở trong nút được đi trước, xe sắp vào phải chờ')
	_check(RescueManager.congestion_factor(inside, [west, inside]) == 1.0, 'xe trong nút đi tiếp')
	var far_north = _car(32, pp - Vector2(0, 42), c, p)
	_check(RescueManager.congestion_factor(west, [west, far_north]) == 1.0
			and RescueManager.congestion_factor(far_north, [west, far_north]) == 0.0, 'xe gần nút hơn đi trước, xe xa hơn nhường')
	var tie_north = _car(33, pp - Vector2(0, 35), c, p)
	_check(RescueManager.congestion_factor(west, [west, tie_north]) == 1.0
			and RescueManager.congestion_factor(tie_north, [west, tie_north]) == 0.0, 'cách đều thì xe mã nhỏ đi trước, không cùng chờ nhau')
	# Chữ T trước cổng: ô đường nối điểm và hai ô đường khác (chỉ 2 nhánh đường) vẫn nhường theo khoảng cách.
	GraphManager.extend_road(a, pc + Vector2i(-1, -1))
	GraphManager.extend_road(a, pc + Vector2i(-1, 1))
	_check(RescueManager.junction_kind(a) == RescueManager.JUNCTION_YIELD, 'ô đường có 2 nhánh đường và 1 lối vào điểm: nhường theo khoảng cách')


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
