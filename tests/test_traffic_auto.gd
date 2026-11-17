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
	_test_ring()
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
	print('\n== Ngã ba một ô: nhường theo khoảng cách (không phải vòng xoay)')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	var t := _t_junction()
	_check(GraphManager.get_edges_of(t.j).size() == 3, 'ô (19, 14) là ngã ba')
	_check(RescueManager.junction_kind(t.j) == RescueManager.JUNCTION_YIELD, 'ngã ba một ô chỉ là giao lộ: nhường theo khoảng cách')
	_check(RescueManager.junction_kind(t.w) == RescueManager.JUNCTION_NONE, 'đầu đường không phải nút giao')
	var jp: Vector2 = GraphManager.get_map_node(t.j).pos
	var west = _car(10, jp - Vector2(35, 0), t.w, t.j)
	var inside = _car(11, jp - Vector2(0, 18), t.n, t.j)
	_check(RescueManager.congestion_factor(west, [west, inside]) == 0.0, 'xe đang ở trong ngã ba được đi trước, xe sắp vào phải chờ')
	var far_north = _car(12, jp - Vector2(0, 42), t.n, t.j)
	_check(RescueManager.congestion_factor(west, [west, far_north]) == 1.0
			and RescueManager.congestion_factor(far_north, [west, far_north]) == 0.0, 'xe gần ngã ba hơn đi trước, xe xa hơn nhường')
	var layer = JunctionLayerScript.new()
	add_child(layer)
	_check(layer._rings.is_empty() and layer._lights.is_empty(), 'ngã ba một ô không vẽ vòng xoay, không đèn')
	layer.free()


# Vòng xoay là vòng đường người chơi vẽ: 2×2 (bốn ô nối kín) hoặc 3×3 (tám ô quanh ô trống). Một chiều, ngược kim
# đồng hồ trên màn hình; xe từ ngoài nhập vào nhường xe đang chạy trên vòng.
func _test_ring() -> void:
	print('\n== Vòng xoay 2×2 và 3×3')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	var tl := Vector2i(6, 15)
	var c := {tl = tl, tr = tl + Vector2i(1, 0), br = tl + Vector2i(1, 1), bl = tl + Vector2i(0, 1)}
	var tlid := GraphManager.extend_road(-1, c.tl)
	var trid := GraphManager.extend_road(tlid, c.tr)
	var brid := GraphManager.extend_road(trid, c.br)
	var blid := GraphManager.extend_road(brid, c.bl)
	_check(GraphManager.ring_of(tlid) == -1, 'chưa khép vòng: chưa là vòng xoay')
	GraphManager.extend_road(blid, c.tl)
	var ring := GraphManager.ring_of(tlid)
	_check(ring != -1 and [trid, brid, blid].all(func(id: int) -> bool: return GraphManager.ring_of(id) == ring), 'bốn ô 2×2 nối kín thành vòng xoay')
	_check(RescueManager.junction_kind(tlid) == RescueManager.JUNCTION_RING, 'ô thuộc vòng là nút vòng xoay')
	var p := GraphManager.find_path(tlid, trid, Types.VehicleType.TRUCK)
	_check(p.found and p.node_ids == [tlid, blid, brid, trid], 'chạy một chiều ngược kim đồng hồ: từ trên trái sang trên phải phải đi vòng qua dưới')
	var back := GraphManager.find_path(trid, tlid, Types.VehicleType.TRUCK)
	_check(back.found and back.node_ids == [trid, tlid], 'đi đúng chiều thì đi thẳng')
	var entry := GraphManager.extend_road(-1, c.tl - Vector2i(1, 0))
	GraphManager.extend_road(entry, c.tl)
	_check(GraphManager.ring_of(tlid) != -1 and GraphManager.ring_of(entry) == -1, 'nối đường vào vòng vẫn là vòng xoay, đường vào không thuộc vòng')
	var tp: Vector2 = GraphManager.get_map_node(tlid).pos
	var coming = _car(20, tp - Vector2(30, 0), entry, tlid)
	var circling = _car(21, tp + Vector2(15, 0), trid, tlid)
	_check(RescueManager.congestion_factor(coming, [coming, circling]) == 0.0, 'xe nhập vào vòng nhường xe đang chạy trên vòng')
	_check(RescueManager.congestion_factor(circling, [coming, circling]) == 1.0, 'xe trên vòng chạy tiếp, không nhường xe ngoài')
	var far = _car(22, tp + Vector2(38, 0), trid, tlid)
	_check(RescueManager.congestion_factor(coming, [coming, far]) == 1.0, 'xe trên vòng còn xa chỗ nhập thì xe ngoài được vào')
	var layer = JunctionLayerScript.new()
	add_child(layer)
	_check(layer._rings.size() == 1 and layer._rings[0].size == 2, 'lớp vẽ có một vòng xoay 2×2 (đảo ở giữa)')
	layer.free()
	# Vòng 3×3 quanh ô trống
	var o := Vector2i(13, 13)
	var cells: Array[Vector2i] = [o, o + Vector2i(1, 0), o + Vector2i(2, 0), o + Vector2i(2, 1), o + Vector2i(2, 2),
			o + Vector2i(1, 2), o + Vector2i(0, 2), o + Vector2i(0, 1)]
	var last := -1
	for cell in cells:
		last = GraphManager.extend_road(last, cell)
	last = GraphManager.extend_road(last, cells[0])
	var big := GraphManager.ring_of(GraphManager.road_at(o))
	_check(big != -1 and big != ring and GraphManager.get_rings()[big].size == 3, 'tám ô quanh ô trống thành vòng xoay 3×3')
	var mid: Vector2 = GraphManager.cell_center(o + Vector2i(1, 1))
	var round := cells.all(func(c: Vector2i) -> bool: return absf(GraphManager.get_map_node(GraphManager.road_at(c)).pos.distance_to(mid) - GraphManager.RING3_RADIUS) < 0.01)
	_check(round, 'vòng 3×3 tròn: 8 nút cách đều tâm vòng %d px (ô góc dời vào trong)' % int(GraphManager.RING3_RADIUS))
	var corner := GraphManager.road_at(o)
	_check(GraphManager.cell_of(GraphManager.get_map_node(corner).pos) == o, 'nút ô góc dời vào trong nhưng vẫn nằm trong ô của nó')
	GraphManager.extend_road(-1, o + Vector2i(1, 1))
	_check(GraphManager.ring_of(GraphManager.road_at(o)) == -1, 'tô cả ô giữa thì không còn là vòng xoay 3×3')
	_check(GraphManager.get_map_node(corner).pos == GraphManager.cell_center(o), 'vòng bị phá: nút ô góc về lại tâm ô')


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
	_check(layer._lights == [x] and layer._rings.is_empty() and layer.is_processing(), 'lớp vẽ nút giao nhận ra ngã tư có đèn, theo dõi đổi pha')
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
