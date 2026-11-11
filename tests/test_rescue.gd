extends Node2D

var _test_triggered: bool = false

func _ready() -> void:
	print("=== BẮT ĐẦU MÔ PHỎNG TỰ NHIÊN MODULE C ===")
	
	# 1. Khởi tạo tầng chứa xe đúng chuẩn hợp đồng nhóm
	var vehicle_layer = Node2D.new()
	vehicle_layer.name = "VehicleLayer"
	vehicle_layer.add_to_group("vehicle_layer")
	add_child(vehicle_layer)
	
	# 2. Đăng ký lắng nghe tín hiệu để in log kết quả thật
	_connect_event_listeners()
	
	# 3. Nạp bản đồ và khởi động hệ thống
	GraphManager.load_map(Config.MAP_PATH)
	await get_tree().process_frame
	EventBus.game_started.emit()
	
	# 4. Mở rộng tuyến đường thực tế cho xe di chuyển giữa các kho và node
	GraphManager.add_edge(0, 3)
	GraphManager.add_edge(3, 5)
	GraphManager.add_edge(5, 7)
	GraphManager.add_edge(7, 1)
	print(">>> [SETUP] Đã thiết lập hoàn tất lưới tuyến đường đi.")
	
	# 5. Kích hoạt đợt lũ 1 để hệ thống tự động chạy
	EventBus.wave_started.emit(0)
	print(">>> [SETUP] Đã phát tín hiệu đợt lũ 1. Đang chạy mô phỏng...")
	
	Engine.time_scale = 1.5

func _connect_event_listeners() -> void:
	if EventBus.has_signal("sos_spawned"):
		EventBus.sos_spawned.connect(func(req_id, node_id, supply, time_total):
			var sup_str = "Y Tế" if supply == 1 else "Lương Thực"
			print("[LOG] Sinh SOS -> ID: ", req_id, " | Node: ", node_id, " | Hàng: ", sup_str, " | Hạn: ", time_total, "s")
		)
		
	if EventBus.has_signal("sos_assigned"):
		EventBus.sos_assigned.connect(func(req_id, vehicle_id):
			print("[LOG] Điều phối -> SOS ID: ", req_id, " gán cho Xe ID: ", vehicle_id)
		)

	if EventBus.has_signal("vehicle_state_changed"):
		EventBus.vehicle_state_changed.connect(func(vehicle_id, state_id):
			var states = ["IDLE", "EN_ROUTE", "DELIVERING", "RETURNING", "STRANDED"]
			var state_name = states[state_id] if state_id < states.size() else str(state_id)
			print("[LOG] Xe ID ", vehicle_id, " chuyển trạng thái -> ", state_name)
			
			# BẪY THÔNG MINH: Ngay khi xe vừa đến nơi bắt đầu giao hàng (DELIVERING = 2)
			# Hệ thống sẽ tự động cắt đứt đường về để chắc chắn xe bị kẹt (STRANDED)
			if state_id == 2 and not _test_triggered:
				_test_triggered = true
				_auto_cut_road()
		)

	if EventBus.has_signal("sos_rescued"):
		EventBus.sos_rescued.connect(func(req_id, points):
			print("[LOG] Cứu hộ THÀNH CÔNG -> SOS ID: ", req_id, " | Thưởng: ", points, "đ")
		)

	if EventBus.has_signal("sos_failed"):
		EventBus.sos_failed.connect(func(req_id):
			print("[LOG] Cứu hộ THẤT BẠI (Quá hạn) -> SOS ID: ", req_id)
		)
		
	# BẮT SỰ KIỆN TỒN KHO ĐỂ CÓ LOG MINH CHỨNG
	if EventBus.has_signal("stock_changed"):
		EventBus.stock_changed.connect(func(hub_id, supply, stock):
			var sup_str = "Y Tế" if supply == 1 else "Lương Thực"
			print("[KHO] Kho ", hub_id, " cập nhật ", sup_str, " -> Tồn kho hiện tại: ", stock)
		)

func _auto_cut_road() -> void:
	print("\n>>> [SỰ CỐ TỰ ĐỘNG] Xe đang bận giao hàng, hệ thống ngầm cắt đường về để ép xe STRANDED!")
	var edges = GraphManager.get_edge_ids()
	if edges.size() > 0:
		GraphManager.remove_edge(edges[0]) # Xóa đường về
		
		# Đợi 5 giây rồi nối lại cho xe về nhà
		await get_tree().create_timer(15.0).timeout
		print("\n>>> [PHỤC HỒI TỰ ĐỘNG] Nước rút, nối lại đường. Xe sẽ tự tìm được đường và thoát STRANDED.")
		GraphManager.add_edge(0, 3)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		var edges = GraphManager.get_edge_ids()
		if edges.size() > 0:
			var target_edge = edges[randi() % edges.size()]
			print("\n>>> [SỰ CỐ THỦ CÔNG] Tuyến đường số ", target_edge, " bị ngắt!")
			GraphManager.remove_edge(target_edge)
