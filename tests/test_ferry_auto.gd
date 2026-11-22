extends Node
# Test tự động cho Feature D: Multi-Modal Logistics (Hệ thống Phao / Phà vượt sông chở xe tải).

const SAIGON_MAP := "res://data/map_saigon.json"

var _passed := 0
var _failed := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("==========================================")
	print("BẮT ĐẦU TEST FEATURE D: HỆ THỐNG PHÀ PHAO")
	print("==========================================")
	
	_test_ferry_creation()
	_test_truck_pathfinding()
	_test_ferry_removal_on_road_deleted()
	_test_auto_fallback()

	print("\n==========================================")
	print("KẾT QUẢ TEST FEATURE D: %d đạt, %d trượt" % [_passed, _failed])
	print("==========================================")
	get_tree().quit(1 if _failed > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + msg)
	else:
		_failed += 1
		push_error("  [FAIL] " + msg)

func _fresh_saigon() -> void:
	GraphManager.load_map(SAIGON_MAP)
	EventBus.game_started.emit()

func _test_ferry_creation() -> void:
	print("\n== 1. Đặt vật phẩm Bến phà thủ công bằng công cụ Phà Phao giữa 2 bờ sông")
	_fresh_saigon()
	
	_check(GraphManager.get_ferries_available() == 1, "Người chơi có sẵn 1 phà trong túi đồ")
	
	# Kiểm tra không cho phép đặt phà từ ô đất trống chưa có đường
	_check(not GraphManager.can_place_ferry(Vector2i(11, 6), Vector2i(17, 6)), "Không cho phép đặt phà khi ô xuất phát chưa có đường")
	_check(not GraphManager.place_ferry(Vector2i(11, 6), Vector2i(17, 6)), "place_ferry từ chối khi ô xuất phát chưa có đường")

	# Bờ Tây (11, 6) và Bờ Đông (17, 6)
	var w1 := GraphManager.extend_road(-1, Vector2i(10, 6))
	var w2 := GraphManager.extend_road(w1, Vector2i(11, 6))
	var e1 := GraphManager.extend_road(-1, Vector2i(18, 6))
	var e2 := GraphManager.extend_road(e1, Vector2i(17, 6))
	
	# Đặt bến phà thủ công
	var ok: bool = GraphManager.place_ferry(Vector2i(11, 6), Vector2i(17, 6))
	_check(ok, "Đặt bến phà thành công giữa ô (11, 6) và (17, 6)")
	_check(GraphManager.get_ferries_available() == 0, "Số phà khả dụng giảm về 0 sau khi đặt")
	
	var routes := GraphManager.get_ferry_routes()
	_check(routes.size() == 1, "Đã thiết lập chính xác 1 tuyến phà nối 2 bờ sông")
	
	if not routes.is_empty():
		var r: Dictionary = routes[0]
		var e: Edge = GraphManager.get_edge(r.edge_id)
		_check(e != null and e.is_ferry, "Cạnh tạo ra có cờ is_ferry = true")
		_check(e.speed_factor(Types.VehicleType.TRUCK) > 0.0, "Xe tải được phép đi qua cạnh phà với tốc độ hợp lệ")
		_check(e.speed_factor(Types.VehicleType.BOAT) == 0.0, "Ca-nô không đi cạnh phà mà đi đường sông riêng")

func _test_truck_pathfinding() -> void:
	print("\n== 2. Thuật toán tìm đường Dijkstra cho xe tải vượt sông bằng Phà Phao")
	_fresh_saigon()

	# Cổng kho Tân Sơn Nhất (kho 0)
	var gate := GraphManager.get_gate_node(0)
	var gate_pos := GraphManager.get_map_node(gate).pos
	var gate_cell := GraphManager.cell_of(gate_pos)

	# Nối đường từ cổng kho đến mép sông Tây ở (11, 6)
	var last := gate
	var cur := gate_cell
	while cur.x < 11:
		cur.x += 1
		last = GraphManager.extend_road(last, cur)
	while cur.y < 6:
		cur.y += 1
		last = GraphManager.extend_road(last, cur)

	# Bờ Đông sông ở (17, 6), nối tới Nguyễn Hữu Cảnh (node 3) hoặc khu dân cư bên bờ Đông
	var east_bank := GraphManager.extend_road(-1, Vector2i(17, 6))
	var east_road := GraphManager.extend_road(east_bank, Vector2i(18, 6))
	
	# Đặt Bến Phà nối 2 bờ
	GraphManager.place_ferry(Vector2i(11, 6), Vector2i(17, 6))
	
	# Nối từ east_road tới nhà hoặc khu bên phải sông
	var east_target := GraphManager.extend_road(east_road, Vector2i(18, 7))

	# Tìm đường cho xe tải từ Kho (node 0) tới ô bên kia sông (east_target)
	var path: PathResult = GraphManager.find_path(0, east_target, Types.VehicleType.TRUCK)
	_check(path.found, "Xe tải đã tìm được đường từ Kho Tân Sơn Nhất vượt sông qua Phà Phao")
	
	var uses_ferry := false
	for eid in path.edge_ids:
		var edge := GraphManager.get_edge(eid)
		if edge != null and edge.is_ferry:
			uses_ferry = true
			break
	_check(uses_ferry, "Lộ trình di chuyển của xe tải thực sự đi qua Cạnh Phà Phao")

	# Đường về kho (RETURNING): tìm đường ngược lại từ bên kia sông về Kho Tân Sơn Nhất
	var return_path: PathResult = GraphManager.find_path(east_target, 0, Types.VehicleType.TRUCK)
	_check(return_path.found, "Xe tải tìm được đường về kho Tân Sơn Nhất sau khi cứu hộ")

func _test_ferry_removal_on_road_deleted() -> void:
	print("\n== 3. Tự động thu hồi và hoàn trả Phà Phao khi xóa ô đường ở bến hoặc hủy phà")
	_fresh_saigon()

	var w := GraphManager.extend_road(-1, Vector2i(11, 6))
	var e := GraphManager.extend_road(-1, Vector2i(17, 6))
	var placed := GraphManager.place_ferry(Vector2i(11, 6), Vector2i(17, 6))
	_check(placed and not GraphManager.get_ferry_routes().is_empty(), "Đã đặt tuyến phà giữa ô 11 và ô 17")
	_check(GraphManager.get_ferries_available() == 0, "Túi đồ còn 0 phà")

	# Xóa ô đường ở bờ Tây
	GraphManager.remove_road(Vector2i(11, 6))
	_check(GraphManager.get_ferry_routes().is_empty(), "Tuyến phà tự động hủy khi xóa đường ở bến bờ sông")
	_check(GraphManager.get_ferries_available() == 1, "Phà đã được hoàn trả lại vào túi đồ (số lượng = 1)")

func _test_auto_fallback() -> void:
	print("\n== 4. Cơ chế Auto-Fallback (Phao tự động lùi bến khi mép nước ngập sâu)")
	_fresh_saigon()

	# Chuỗi đường: ô cạn (10, 6) -> ô mép nước (11, 6)
	var w1 := GraphManager.extend_road(-1, Vector2i(10, 6))
	var w2 := GraphManager.extend_road(w1, Vector2i(11, 6))

	# Bờ đối diện
	var e := GraphManager.extend_road(-1, Vector2i(17, 6))
	GraphManager.place_ferry(Vector2i(11, 6), Vector2i(17, 6))
	_check(not GraphManager.get_ferry_routes().is_empty(), "Đã có tuyến phà ban đầu")

	# Bến ban đầu ở w2
	var r: Dictionary = GraphManager.get_ferry_routes()[0]
	_check(r.node_a == w2 or r.node_b == w2, "Bến phà ban đầu gắn vào ô mép nước (11, 6)")
