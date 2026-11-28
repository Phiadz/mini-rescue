extends Node
# RescueManager (autoload). KHÔNG đặt class_name. Chủ sở hữu: C.
# Bố cục: hằng số -> SOS -> HUB -> SOS FACTORY -> VEHICLE -> STATE -> VEHICLE FACTORY -> MANAGER

# TODO: xin A chuyển các hằng số này sang autoload/config.gd rồi đổi thành Config.X
const HOSPITAL_ID := 5               # node Bệnh viện luôn ra SOS Y tế
const START_TRUCKS := 12             # số xe tải lúc đầu ván (ở kho cao nhất)
const START_BOATS := 8               # số ca-nô lúc đầu ván (ở kho thấp nhất)
const PARK_GAP := 10.0               # điểm có cổng: xe giao hàng đỗ ở lối vào, cách mép trước tòa nhà chừng này (px)
const HUB_HIDE_RADIUS := 20.0        # xe trong bán kính này quanh kho của nó thì ẩn (đang ở trong kho)
const LOT_SLOTS := 6                 # chỗ đỗ xe tải trong bãi của kho: 3 chỗ mỗi bên lối đi giữa
const DOCK_SLOTS := 4                # chỗ đỗ ca-nô ở bến của kho
const DOCK_MAX_DOWN := 0.3           # chỗ đỗ ca-nô không chĩa xuống quá mức này (dưới kho là tên kho và nhãn hàng)
const DOCK_REACH := 95.0             # chỗ neo thêm ở nút sông kề bến cách kho tối đa (px)
const SLOT_PITCH := 13.0             # khoảng cách hai chỗ đỗ cạnh nhau (px)
const SLOT_DEPTH := 17.0             # tâm chỗ đỗ cách giữa lối đi (px)
const DOCK_OUT := 38.0               # chỗ đỗ ca-nô cách tâm kho về phía sông (px), ra ngoài icon kho 56 px
const PARKED_SCALE := 0.8            # xe trong bãi, ở bến vẽ nhỏ lại cho vừa chỗ đỗ
const MANEUVER_SPEED := 0.4          # hệ số tốc độ khi lùi ra khỏi chỗ đỗ hoặc đỗ vào chỗ
const BOAT_CLEAR := 12.0             # ca-nô cập bến khu, nhà: cách mép lô đất ít nhất chừng này px (không đè lên lô)
const BOAT_UNDER_Z := -7             # ca-nô luồn dưới cầu: trên đường chìm (EdgeLayer.SUNK_Z), dưới đường thường (z 0)
const Road := preload('res://graph/edge_layer.gd')
const DISPATCH_INTERVAL := 0.5       # giây giữa hai lượt điều phối
const DIRTY_DISPATCH_GAP := 0.1      # đồ thị đổi (tô đường, nước dâng rút): điều phối lại sớm nhưng không dày hơn mức này
									 # (SOS mới, xe rảnh vẫn điều phối ngay khung sau)
const MIN_EDGE_SPEED_FACTOR := 0.5   # tốc độ tối thiểu khi đi hết cạnh
const STRANDED_RETRY := 0.5          # giây giữa hai lần xe kẹt thử tìm đường
const BONUS_TIME_RATIO := 0.5        # còn quá nửa thời gian thì được thưởng
const ARRIVE_EPSILON := 0.5          # sai số khi tới node (px)
# Kẹt xe: chỉ dùng khoảng cách và đồ thị, không dùng vật lý.
const FOLLOW_GAP := 34.0             # xe phía trước cùng làn gần hơn mức này (px) thì chạy chậm
const STOP_GAP := 20.0               # gần hơn mức này thì dừng chờ
const FOLLOW_SLOW := 0.5             # hệ số tốc độ khi bám đuôi
const SAME_LANE := 6.0               # lệch ngang dưới mức này (px) coi là cùng làn
const JUNCTION_RADIUS := 24.0        # bán kính ngã ba, ngã tư (px)
const JUNCTION_APPROACH := 46.0      # trong khoảng này trước ngã ba thì xét nhường đường
const JAM_GIVE_UP := 3.0             # đứng chờ quá lâu (giây) thì đi chậm qua, tránh tắc vĩnh viễn
const CONGESTION_PATH_COST := 1.5    # giây cộng thêm khi tìm đường qua cạnh sắp có xe đi
const WATER_VESSEL_CONGESTION_COST := 35.0 # phạt nặng trên luồng nước để thuyền tự động chọn ô nước thoáng lân cận lách qua nhau
# Nút giao tự động (góp ý của Lộc): ngã ba đường thành vòng xoay, ngã tư đường trở lên có đèn giao thông.
const JUNCTION_NONE := 0             # không phải nút giao
const JUNCTION_YIELD := 1            # nhường theo khoảng cách: điểm có từ 3 cạnh, chữ T trước cổng nhà
const JUNCTION_RING := 2             # ô thuộc vòng xoay người chơi vẽ (2×2, 3×3): xe từ ngoài vào nhường xe trên vòng
const JUNCTION_LIGHT := 3            # ngã tư đường trở lên: đèn chia lượt theo trục ngang, dọc
const LIGHT_PHASE := 3.0             # giây mỗi pha đèn xanh của một trục
const ROUNDABOUT_SLOW := 0.8         # hệ số dưới mức này mới tính là kẹt (bật đèn phanh)
const RING_YIELD := 30.0             # xe trên vòng cách chỗ nhập dưới mức này (px) thì xe ngoài vào phải nhường
const UNIT_EXTRA_SECONDS: float = 0.5  # bằng Config.DELIVERY_TIME; SOS cần nhiều phần: mỗi phần thêm cộng một lần dỡ hàng (xe xếp hàng dỡ lần lượt)
const GRID_CELL := 40.0              # ô lưới để tìm xe ở gần khi tính kẹt xe (bằng một ô đường)

# Nguồn đồ thị. null = dùng GraphManager thật. Scene thử gán đồ thị giả vào đây.
var graph = null

func g():
	return graph if graph != null else GraphManager

# ===== SOS =====
class SosRequest extends RefCounted:
	var id: int
	var node_id: int
	var supply: int
	var time_total: float
	var time_left: float
	var prioritized := false
	var state: int = Types.SosState.PENDING  # PENDING: còn cần thêm xe; ASSIGNED: đủ xe đang chở tới
	var vehicle_id := -1      # xe nhận gần nhất (giữ cho mã cũ)
	var units := 1            # số phần hàng cần; mỗi xe chở 1 phần
	var assigned := 0         # số xe đang chở tới
	var delivered := 0        # số phần đã giao
	var vehicle_ids: Array[int] = []
	var heavy_only := false   # nhà này chỉ nhận xe cứu hộ hạng nặng (xe dân đã gặp ngập giữa đường)
	var civ_next_try := 0.0   # lần sớm nhất thử lại xe dân (theo _clock), tránh tìm đường mỗi khung hình

	# Còn thiếu bao nhiêu xe để đủ số phần.
	func missing() -> int:
		return units - assigned - delivered

# ===== HUB =====
class Hub extends RefCounted:
	var id: int
	var stock := {}
	var _regen := {}

	func _init(p_id: int) -> void:
		id = p_id
		for s in [Types.SupplyType.FOOD, Types.SupplyType.MEDICAL]:
			stock[s] = Config.STOCK_START
			_regen[s] = 0.0

	# Trả về danh sách loại hàng vừa tăng để Manager phát stock_changed
	func tick(delta: float) -> Array:
		var changed := []
		for s in stock:
			if stock[s] >= Config.STOCK_MAX:
				_regen[s] = 0.0
				continue
			_regen[s] += delta
			if _regen[s] >= Config.STOCK_REGEN:
				_regen[s] = 0.0
				stock[s] += 1
				changed.append(s)
		return changed

# ===== SOS FACTORY =====
class SosFactory extends RefCounted:
	static func create(req_id: int, wave_index: int, free_node_ids: Array) -> SosRequest:
		if free_node_ids.is_empty():
			return null
		var w: Dictionary = Config.get_wave_profile(wave_index + 1)
		var req := SosRequest.new()
		req.id = req_id
		req.node_id = free_node_ids[randi() % free_node_ids.size()]
		if req.node_id == HOSPITAL_ID:
			req.supply = Types.SupplyType.MEDICAL
		elif randf() < w.food_ratio:
			req.supply = Types.SupplyType.FOOD
		else:
			req.supply = Types.SupplyType.MEDICAL
		if req.supply == Types.SupplyType.FOOD:
			req.time_total = w.deadline_food
		else:
			req.time_total = w.deadline_medical
		req.units = int(w.get("sos_units", 1))
		req.time_total += UNIT_EXTRA_SECONDS * (req.units - 1)  # nhiều xe phải xếp hàng dỡ hàng
		req.time_left = req.time_total  # gán sau khi cộng thêm, để vòng đếm giờ bắt đầu đầy và hạn thật có phần cộng thêm
		return req

# ===== VEHICLE =====
class Vehicle extends Node2D:
	# Hình xe SVG của D (cùng bộ với icon tòa nhà trên bản đồ), đầu xe quay sang phải.
	const TRUCK_ICON := preload('res://assets/icons/truck.svg')
	const BOAT_ICON := preload('res://assets/icons/boat.svg')
	const MOTORBIKE_ICON := preload('res://assets/icons/motorbike.svg')
	const CAR_ICON := preload('res://assets/icons/car.svg')
	const ICON_SIZE := Vector2(21, 14)           # giữ tỉ lệ 96 × 64 của file SVG, vừa một làn của đường rộng 22 px
	const MOTORBIKE_ICON_SIZE := Vector2(14, 9)  # xe máy: nhỏ gọn, chiếm 1/2 làn, 2 xe ngược chiều lách được
	const CAR_ICON_SIZE := Vector2(18, 11)       # ô tô con: vừa vặn 1 làn đường, dễ tạo ùn ứ
	const FADE_OUT_DURATION := 0.25              # thời gian mờ dần (giây) khi xe dân gặp nước ngập
	const PARK_OFFSET := 18.0  # lúc đỗ ở kho: xe tải lệch trái, ca-nô lệch phải để không chồng nhau
	const LANE_OFFSET := 5.5   # xe chạy lệch sang phải hướng đi, mỗi chiều một làn (đường rộng 22 px)
	const LANE_SWITCH := 0.15  # giây để đổi làn ở chỗ rẽ

	var id: int
	var type: int
	var hub_id: int
	var request: SosRequest
	var path: PathResult:
		set(value):
			if value == null or value.edge_ids.is_empty() or value.edge_ids[0] != _entered_road_edge:
				_entered_road_edge = -1
			path = value
	var path_index := 0
	var _entered_road_edge := -1
	var current_speed := 0.0
	var target_speed := 0.0
	var traffic_stop_distance := INF
	var _curve_edge := -1
	var _curve_index := 0
	var current_node := -1   # node xe vừa rời hoặc đang đứng
	var dest := -1           # node đích của nhiệm vụ
	var state_id: int = Types.VehicleState.IDLE
	var heading := Vector2.RIGHT  # hướng đang chạy
	var _state: VehicleStateBase
	var _lane := Vector2.ZERO     # độ lệch làn khi vẽ; position vẫn nằm giữa đường
	var jammed := false           # đang bị kẹt (bám đuôi hoặc chờ ở ngã ba): vẽ đèn phanh
	var at_red := false           # đang dừng trước đèn đỏ (congestion_factor đặt mỗi lần xét)
	var slot := -1                # chỗ đỗ đang giữ ở bãi (xe tải) hoặc bến (ca-nô) của kho, -1: không có (ở trong kho)
	var waypoints: Array[Vector2] = []  # điểm phải đi qua khi lùi ra hoặc đỗ vào chỗ, trước khi chạy theo đường
	var _jam_time := 0.0
	var is_civilian := false   # xe dân của một nhà: tự ra kho lấy hàng rồi chở về nhà
	var home_id := -1          # node nhà của xe dân
	var fading := false        # xe dân đang mờ dần vì gặp ngập
	var queue := []            # các SOS còn phải giao sau SOS hiện tại (xe nâng cấp chở 2 hàng)
	var parked := false           # xe dân đang đỗ trong nhà (PARKED): ẩn hoàn toàn
	var _fading := false          # đang chạy Tween mờ dần khi gặp nước ngập
	var _fade_tween: Tween = null
	var _ferry_tex: Texture2D = null
	var _water_detour_cooldown: float = 0.0
	var is_boarded_on_ferry := false
	var waiting_at_ferry := false

	func ferry_weight() -> int:
		match type:
			Types.VehicleType.TRUCK:
				return 2
			Types.VehicleType.CAR:
				return 2
			Types.VehicleType.MOTORBIKE:
				return 1
			_:
				return 2

	func request_water_detour() -> void:
		# Tính lại đường với chi phí chiếm đóng hiện tại (congestion_penalty) để thuyền
		# tự động lách vào nhánh sông thoáng thay vì dừng đối đầu.
		var goal := hub_id if state_id == Types.VehicleState.RETURNING else dest
		if _water_detour_cooldown > 0.0 or goal == -1 or type != Types.VehicleType.BOAT:
			return
		_water_detour_cooldown = 2.5
		# plan() gọi RescueManager.find_path() bao gồm congestion_penalty → tự né đường đắt
		plan(goal)

	func is_on_ferry() -> bool:
		return is_boarded_on_ferry

	func is_civilian_type() -> bool:
		return type == Types.VehicleType.MOTORBIKE or type == Types.VehicleType.CAR

	func is_fading() -> bool:
		return fading or _fading

	func reset_visual() -> void:
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = null
		_fading = false
		fading = false
		modulate.a = 1.0
		queue_redraw()

	# Hiệu ứng mờ dần (modulate.a: 1.0 -> 0.0 trong 0.25s) khi xe dân gặp nước ngập, sau đó hủy hoặc ẩn đi.
	func fade_out(free_after: bool = false, on_finished: Callable = Callable()) -> void:
		if fading or _fading:
			return
		_fading = true
		fading = true
		visible = true
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		if not is_inside_tree():
			modulate.a = 0.0
			_finish_fade_out(free_after, on_finished)
			return
		modulate.a = 1.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(self, 'modulate:a', 0.0, FADE_OUT_DURATION)
		_fade_tween.finished.connect(func() -> void:
			_finish_fade_out(free_after, on_finished)
		)

	func _finish_fade_out(free_after: bool, on_finished: Callable) -> void:
		_fading = false
		fading = false
		_fade_tween = null
		if free_after:
			queue_free()
		else:
			visible = false
			parked = true
		if on_finished.is_valid():
			on_finished.call()

	func set_initial_state() -> void:  # không phát tín hiệu
		_state = IdleState.new()
		state_id = Types.VehicleState.IDLE
		parked = is_civilian_type()
		if parked:
			visible = false

	func change_state(new_state: VehicleStateBase, new_id: int) -> void:
		if _state:
			_state.exit(self)
		_state = new_state
		state_id = new_id
		if new_id in [Types.VehicleState.IDLE, Types.VehicleState.DELIVERING, Types.VehicleState.STRANDED]:
			current_speed = 0.0
			target_speed = 0.0
		if is_civilian_type() and new_id == Types.VehicleState.EN_ROUTE:
			parked = false
			if _fading or modulate.a < 1.0:
				reset_visual()
		_state.enter(self)
		queue_redraw()
		if not is_civilian:
			EventBus.vehicle_state_changed.emit(id, new_id)

	func _process(delta: float) -> void:
		if _state:
			_state.update(self, delta)
		_update_lane(delta)
		_update_visible()
		if type == Types.VehicleType.BOAT:
			z_index = BOAT_UNDER_Z if RescueManager.under_bridge(self) else 0

	# Xe đang ở trong kho (đỗ, hoặc chờ ra cổng) hoặc xe dân đang đỗ trong nhà (PARKED) thì ẩn.
	func _update_visible() -> void:
		if fading or _fading:
			visible = true
			return  # đỗ ở nhà hoặc đang nhận hàng trong kho thì ẩn
		var hidden: bool
		if is_civilian_type():
			hidden = parked or state_id == Types.VehicleState.IDLE
		else:
			hidden = state_id == Types.VehicleState.IDLE and slot < 0 and waypoints.is_empty()  # bãi đầy: ở trong kho
		if not hidden:
			var h: MapNode = RescueManager.g().get_map_node(hub_id)
			hidden = h != null and position.distance_to(h.pos) < HUB_HIDE_RADIUS
		visible = not hidden
		if visible and modulate.a < 1.0:
			modulate.a = 1.0

	func _update_lane(delta: float) -> void:
		var want := Vector2.ZERO
		if state_id != Types.VehicleState.IDLE and not RescueManager.in_lot(self) and not is_on_ferry():  # trong bãi hoặc trên phà: đi giữa lối, không lệch làn
			want = heading.rotated(PI / 2.0) * LANE_OFFSET
		if _lane != want:
			_lane = _lane.move_toward(want, LANE_OFFSET * 2.0 / LANE_SWITCH * delta)
			queue_redraw()
		if type == Types.VehicleType.BOAT and _lane != Vector2.ZERO and not RescueManager._boat_segment_open(position, position + _lane):
			_lane = Vector2.ZERO
			queue_redraw()

	func lane_offset() -> Vector2:
		return _lane

	# Xe đang chạy trên đường (không đứng ở kho, ở khu dân cư hay kẹt vì mất đường).
	func is_moving() -> bool:
		if waiting_at_ferry:
			return false
		if is_boarded_on_ferry:
			return true
		var running: bool = state_id == Types.VehicleState.EN_ROUTE or state_id == Types.VehicleState.RETURNING
		return running and path != null and path_index < path.edge_ids.size()

	# Node kế tiếp xe đang chạy tới, -1 nếu đứng yên.
	func next_node() -> int:
		return path.node_ids[path_index + 1] if is_moving() else -1

	# Node xe vừa rời trên đường đang chạy, -1 nếu đứng yên.
	func prev_node() -> int:
		return path.node_ids[path_index] if is_moving() else -1

	# Cộng thời gian kẹt và áp luật chờ quá JAM_GIVE_UP thì đi chậm qua (tránh tắc vĩnh viễn).
	# Đang dừng đèn đỏ thì không vượt: đèn luôn đổi pha nên không tắc vĩnh viễn.
	# Chạy chậm trong vòng xoay (ROUNDABOUT_SLOW) không tính là kẹt.
	func settle_jam(jam: float, delta: float) -> float:
		_jam_time = _jam_time + delta if jam < ROUNDABOUT_SLOW else 0.0
		if _jam_time > JAM_GIVE_UP and not at_red:
			jam = maxf(jam, FOLLOW_SLOW)  # chờ quá lâu: đi chậm qua
		var stuck := jam < ROUNDABOUT_SLOW
		if jammed != stuck:
			jammed = stuck
			queue_redraw()
		return jam

	func retry_if_stranded() -> void:
		if state_id == Types.VehicleState.STRANDED and _state:
			_state.retry(self)

	# Tính lại đường từ node hiện tại tới to_node. true nếu tìm được.
	func plan(to_node: int) -> bool:
		if current_node == to_node:
			path = PathResult.new()
			path.found = true
			path.node_ids.append(to_node)
			path_index = 0
			return true
		var p: PathResult = RescueManager.find_path(current_node, to_node, type, self)
		if p.found:
			path = p
			path_index = 0
			return true
		return false

	# Đi dọc đường. Trả true khi xe đứng ở cuối đoạn (cần ra quyết định).
	# Xe đường bộ đã vào một đoạn thì đi hết đoạn đó, tốc độ tối thiểu MIN_EDGE_SPEED_FACTOR.
	func advance(delta: float) -> bool:
		_water_detour_cooldown = maxf(0.0, _water_detour_cooldown - delta)
		if is_boarded_on_ferry:
			return false
		if path == null or path_index >= path.edge_ids.size():
			return true
		if not waypoints.is_empty():
			maneuver(delta)
			return false
		var remaining := delta
		while remaining > 0.0 and path_index < path.edge_ids.size():
			var edge: Edge = RescueManager.g().get_edge(path.edge_ids[path_index])
			if edge == null:
				_cut()
				return true
			var factor := edge.speed_factor(type)
			if factor <= 0.0:
				if type == Types.VehicleType.BOAT or edge.suspended:
					_cut()
					return true
				# Only a truck already moving along this edge may finish it after it floods.
				if type == Types.VehicleType.TRUCK and edge.state == Types.EdgeState.DEEP and _entered_road_edge != edge.id:
					_cut(false)
					return true
				factor = MIN_EDGE_SPEED_FACTOR
			if edge.is_ferry:
				current_speed = 0.0
				target_speed = 0.0
				waiting_at_ferry = true
				RescueManager.register_ferry_passenger(self, current_node)
				return false
			waiting_at_ferry = false
			var next_id: int = path.node_ids[path_index + 1]
			if type == Types.VehicleType.BOAT and RescueManager._redirect_boat_departure(self, next_id):
				return path.edge_ids.is_empty()
			var target := RescueManager.arrive_pos(self, next_id)
			if type == Types.VehicleType.BOAT and not RescueManager._boat_segment_open(position, target):
				# A replan starts at the last graph node. The vessel may still be on its old edge.
				var anchor: MapNode = RescueManager.g().get_map_node(current_node)
				if anchor == null or anchor.kind != Types.NodeKind.WATER \
						or not RescueManager._boat_segment_open(position, anchor.pos) \
						or not RescueManager._boat_segment_open(anchor.pos, target):
					_cut()
					return true
				heading = position.direction_to(anchor.pos)
				var limit := sqrt(2.0 * Config.BRAKING[type] * position.distance_to(anchor.pos))
				_drive_to(anchor.pos, minf(Config.base_speed(type), limit), INF, remaining)
				return false
			var last_point := true
			var ahead := position.distance_to(target)
			if edge.is_highway:
				var forward := edge.node_a == current_node
				if _curve_edge != edge.id:
					_curve_edge = edge.id
					_curve_index = 1 if forward else edge.curve.size() - 2
				target = edge.curve[_curve_index]
				last_point = _curve_index == (edge.curve.size() - 1 if forward else 0)
				ahead = position.distance_to(target)
				var direction := 1 if forward else -1
				var i := _curve_index
				while i + direction >= 0 and i + direction < edge.curve.size():
					ahead += edge.curve[i].distance_to(edge.curve[i + direction])
					i += direction
			if position.distance_to(target) > ARRIVE_EPSILON:
				heading = position.direction_to(target)
			var jam := RescueManager.congestion_factor(self, [], true)
			jam = settle_jam(jam, remaining)
			var limit := Config.base_speed(type) * factor * jam
			var brake: float = Config.BRAKING[type]
			var approach_limit := _lookahead_speed_limit(ahead, brake, remaining)
			var stop_limit := _approach_speed(0.0, traffic_stop_distance, brake, remaining)
			limit = minf(limit, minf(approach_limit, stop_limit))
			var previous_position := position
			var leftover := _drive_to(target, limit, traffic_stop_distance, remaining)
			if leftover < 0.0:
				if type == Types.VehicleType.TRUCK and position != previous_position:
					_entered_road_edge = edge.id
				return false
			remaining = leftover
			if not last_point:
				_curve_index += 1 if edge.node_a == current_node else -1
				continue
			_curve_edge = -1
			_entered_road_edge = -1
			current_node = next_id
			path_index += 1
			var next_edge: Edge = RescueManager.g().get_edge(path.edge_ids[path_index]) if path_index < path.edge_ids.size() else null
			if next_edge == null or next_edge.is_ferry:
				current_speed = 0.0
				target_speed = 0.0
			if not _next_edge_same_segment(edge):
				return true
		return path_index >= path.edge_ids.size()

	# Look ahead across short tiles so braking can begin before entering the last edge.
	func _lookahead_speed_limit(distance: float, brake: float, delta: float) -> float:
		var result := INF
		var base := Config.base_speed(type)
		var horizon := maxf(current_speed, base * Config.HIGHWAY_SPEED_FACTOR)
		horizon = horizon * horizon / (2.0 * brake)
		for i in range(path_index, path.edge_ids.size()):
			var next := RescueManager.g().get_edge(path.edge_ids[i + 1]) as Edge if i + 1 < path.edge_ids.size() else null
			if next == null or next.is_ferry:
				return minf(result, _approach_speed(0.0, distance, brake, delta))
			var next_factor := next.speed_factor(type)
			if next_factor > 0.0:
				result = minf(result, _approach_speed(base * next_factor, distance, brake, delta))
			if type != Types.VehicleType.BOAT:
				var junction := path.node_ids[i + 1]
				var kind := RescueManager.junction_kind(junction)
				if kind != JUNCTION_NONE:
					var turn := base * Config.JUNCTION_SPEED_FACTOR
					if i > path_index and kind == JUNCTION_LIGHT:
						var from: MapNode = RescueManager.g().get_map_node(path.node_ids[i])
						var to: MapNode = RescueManager.g().get_map_node(junction)
						if not RescueManager.light_green(junction, from.pos.direction_to(to.pos)):
							turn = 0.0
					result = minf(result, _approach_speed(turn, maxf(0.0, distance - JUNCTION_RADIUS), brake, delta))
			if distance > horizon:
				break
			distance += next.length
		return result

	func _approach_speed(exit_speed: float, distance: float, brake: float, delta: float) -> float:
		# Start braking before cruising for another frame would cross the braking envelope.
		return sqrt(exit_speed * exit_speed + 2.0 * brake * maxf(0.0, distance - current_speed * delta))

	# Return unused frame time on arrival. A traffic stop is a hard position limit even
	# if a new obstacle appears closer than the physical braking distance.
	func _drive_to(target: Vector2, limit: float, traffic_distance: float, delta: float) -> float:
		target_speed = limit
		var length := position.distance_to(target)
		if traffic_distance <= 0.0:
			current_speed = 0.0
			return -1.0
		if length == 0.0:
			return delta
		var start_speed := current_speed
		var rate: float = Config.ACCELERATION[type] if limit > start_speed else Config.BRAKING[type]
		var next_speed := move_toward(start_speed, limit, rate * delta)
		var ramp := absf(next_speed - start_speed) / rate
		var movement := (start_speed + next_speed) * 0.5 * ramp + next_speed * (delta - ramp)
		var travel := minf(length, minf(traffic_distance, movement))
		position = position.move_toward(target, travel)
		current_speed = next_speed
		queue_redraw()
		if travel >= traffic_distance:
			current_speed = 0.0
			return -1.0
		if travel < length:
			return -1.0
		var acceleration := signf(next_speed - start_speed) * rate
		var ramp_distance := (start_speed + next_speed) * 0.5 * ramp
		var used := ramp
		if travel < ramp_distance:
			current_speed = sqrt(maxf(0.0, start_speed * start_speed + 2.0 * acceleration * travel))
			used = absf(current_speed - start_speed) / rate
		elif next_speed > 0.0:
			used += (travel - ramp_distance) / next_speed
		return maxf(0.0, delta - used)

	func maneuver(delta: float) -> bool:
		var remaining := delta
		while not waypoints.is_empty() and remaining > 0.0:
			var to: Vector2 = waypoints[0]
			if type == Types.VehicleType.BOAT and not RescueManager._boat_segment_open(position, to):
				waypoints.clear()
				current_speed = 0.0
				target_speed = 0.0
				return true
			if position.distance_to(to) > ARRIVE_EPSILON:
				heading = position.direction_to(to)
			var limit := Config.base_speed(type) * MANEUVER_SPEED
			var distance := position.distance_to(to)
			for i in range(1, waypoints.size()):
				distance += waypoints[i - 1].distance_to(waypoints[i])
			limit = minf(limit, _approach_speed(0.0, distance, Config.BRAKING[type], remaining))
			remaining = _drive_to(to, limit, INF, remaining)
			if remaining < 0.0:
				return false
			waypoints.pop_front()
		if waypoints.is_empty() and state_id == Types.VehicleState.IDLE:
			current_speed = 0.0
			target_speed = 0.0
		return waypoints.is_empty()

	func _next_edge_same_segment(e: Edge) -> bool:
		if path_index >= path.edge_ids.size():
			return false
		var after: Edge = RescueManager.g().get_edge(path.edge_ids[path_index])
		return after != null and after.segment == e.segment

	# Cạnh đang đi bị xóa: dịch về node vừa rời, đường rỗng để state tính lại.
	# GraphManager xóa cạnh trước rồi mới xóa ô, nên lúc này node vẫn còn.
	func _cut(snap_to_node := true) -> void:
		if path != null and path_index < path.node_ids.size():
			current_node = path.node_ids[path_index]
			var node: MapNode = RescueManager.g().get_map_node(current_node)
			if snap_to_node and (type != Types.VehicleType.BOAT or (node != null and node.kind == Types.NodeKind.WATER)):
				position = RescueManager.stop_pos(current_node)
		path = PathResult.new()
		path_index = 0
		_curve_edge = -1
		current_speed = 0.0
		target_speed = 0.0

	func on_edge_removed(edge_id: int) -> void:
		if path == null or path_index >= path.edge_ids.size():
			return
		if path.edge_ids[path_index] == edge_id:
			_cut()

		# Bỏ nhiệm vụ: mọi SOS xe đang giữ (hiện tại và trong hàng đợi) về PENDING, hoàn hàng.
	func release_request() -> void:
		_release_one(request)
		request = null
		for q in queue:
			_release_one(q)
		queue.clear()
		RescueManager.mark_dirty()

	func _release_one(r: SosRequest) -> void:
		if r == null:
			return
		r.assigned = maxi(0, r.assigned - 1)
		r.vehicle_ids.erase(id)
		r.state = Types.SosState.PENDING
		r.vehicle_id = r.vehicle_ids.back() if not r.vehicle_ids.is_empty() else -1
		RescueManager.refund(hub_id, r.supply)

	# SOS đã hết hạn (Manager đã phát sos_failed): hoàn hàng, sang SOS kế tiếp hoặc về kho.
	func on_request_failed() -> void:
		if request == null:
			return
		RescueManager.refund(hub_id, request.supply)
		request = null
		if is_civilian:
			civilian_go_home_empty()
		else:
			next_or_home()

	# SOS r hết hạn: xe bỏ qua nó (đang đi tới r thì sang SOS kế tiếp, nằm trong hàng đợi thì chỉ bỏ khỏi hàng).
	func drop_request(r: SosRequest) -> void:
		if request == r:
			on_request_failed()
		elif queue.has(r):
			queue.erase(r)
			RescueManager.refund(hub_id, r.supply)

	# Sang SOS kế tiếp trong hàng đợi (nếu có đường), không còn thì về kho.
	func next_or_home() -> void:
		while not queue.is_empty():
			var nxt = queue.pop_front()
			request = nxt
			dest = nxt.node_id
			if plan(dest):
				change_state(EnRouteState.new(), Types.VehicleState.EN_ROUTE)
				return
			release_request()  # không có đường tới nhà kế: trả lại hàng chờ
		go_home()

	# ----- Xe dân -----
	# Đoạn đang đi hoặc đoạn kế tiếp đã ngập quá khả năng của xe (hệ số tốc độ 0) thì phải biến mất.
	func civilian_blocked() -> bool:
		if path == null:
			return false
		for k in [path_index, path_index + 1]:
			if k < path.edge_ids.size():
				var e: Edge = RescueManager.g().get_edge(path.edge_ids[k])
				if e != null and e.speed_factor(type) <= 0.0:
					return true
		return false

	# Xe dân gặp ngập: mờ dần rồi về đỗ ở nhà (ẩn). SOS về hàng chờ, chỉ còn xe cứu hộ hạng nặng nhận.
	func civilian_vanish() -> void:
		var req := request
		release_request()  # SOS về PENDING, hàng hoàn kho
		if req != null:
			req.heavy_only = true
		fading = true
		path = null
		waypoints.clear()
		change_state(IdleState.new(), Types.VehicleState.IDLE)
		modulate.a = 1.0
		var tw := create_tween()
		tw.tween_property(self, 'modulate:a', 0.0, Config.CIVILIAN_FADE_TIME)
		tw.tween_callback(_finish_vanish)

	func _finish_vanish() -> void:
		fading = false
		_fading = false
		parked = true
		modulate.a = 1.0
		current_node = home_id
		position = RescueManager.stop_pos(home_id)
		queue_redraw()

	# Xe dân về tới nhà: SOS được cứu (nếu còn), xe đỗ lại.
	func civilian_arrive_home() -> void:
		var req := request
		request = null
		path = null
		change_state(IdleState.new(), Types.VehicleState.IDLE)
		if req != null:
			RescueManager.complete_request(req, self)

	# SOS hết hạn khi xe dân đang đi: hàng đã hoàn, xe về nhà tay không.
	func civilian_go_home_empty() -> void:
		if plan(home_id):
			change_state(CivToHomeState.new(), Types.VehicleState.RETURNING)
		else:
			civilian_vanish()

	func go_home() -> void:
		RescueManager.reserve_slot(self)  # giữ sẵn một chỗ trong bãi; bãi đầy thì vào trong kho
		if plan(hub_id):
			change_state(ReturningState.new(), Types.VehicleState.RETURNING)
		else:
			change_state(StrandedState.new(), Types.VehicleState.STRANDED)

	func park() -> void:
		current_node = hub_id
		path = null
		_lane = Vector2.ZERO
		waypoints.clear()
		if slot >= 0 and type == Types.VehicleType.BOAT:
			waypoints = RescueManager._boat_berth_waypoints(self)
			if waypoints.is_empty():
				RescueManager.release_slot(self)
		elif slot >= 0:
			waypoints.append(RescueManager.slot_pos(self))  # từ lối đi vào đúng chỗ đã giữ
		if slot < 0:
			position = RescueManager.stop_pos(hub_id)
			heading = Vector2.RIGHT
		change_state(IdleState.new(), Types.VehicleState.IDLE)
		RescueManager.mark_dirty()

	func _vehicle_icon() -> Texture2D:
		match type:
			Types.VehicleType.TRUCK:
				return TRUCK_ICON
			Types.VehicleType.BOAT:
				return BOAT_ICON
			Types.VehicleType.MOTORBIKE:
				return MOTORBIKE_ICON
			Types.VehicleType.CAR:
				return CAR_ICON
		return TRUCK_ICON

	func _vehicle_icon_size() -> Vector2:
		match type:
			Types.VehicleType.MOTORBIKE:
				return MOTORBIKE_ICON_SIZE
			Types.VehicleType.CAR:
				return CAR_ICON_SIZE
		return ICON_SIZE

	func _draw_water_wake(center_offset: Vector2, rear_dist: float, spread: float, wake_len: float) -> void:
		if not is_moving():
			return
		var rear_pos := center_offset - heading * rear_dist
		var side_vec := heading.rotated(PI / 2.0) * spread
		var col := Color(1.0, 1.0, 1.0, 0.42)
		draw_line(rear_pos + side_vec * 0.7, rear_pos + side_vec * 1.4 - heading * wake_len, col, 1.6)
		draw_line(rear_pos - side_vec * 0.7, rear_pos - side_vec * 1.4 - heading * wake_len, col, 1.6)

	func _draw() -> void:
		var on_ferry: bool = is_on_ferry()
		var offset := _lane
		if not is_civilian_type() and state_id == Types.VehicleState.IDLE and slot < 0:
			offset.x = -PARK_OFFSET if type == Types.VehicleType.TRUCK else PARK_OFFSET
		var icon := _vehicle_icon()
		var icon_size := _vehicle_icon_size()
		var left := heading.x < 0.0  # lật hình để xe không chổng ngược khi đi sang trái
		var sc: float = RescueManager.draw_scale(self)

		if on_ferry:
			# Xe đỗ trên sàn phà: chỉ vẽ icon xe, thân phà và vệt rẽ nước do FerryLayer vẽ
			draw_set_transform(Vector2.ZERO, heading.angle() + (PI if left else 0.0), Vector2(-sc if left else sc, sc))
			draw_texture_rect(icon, Rect2(-icon_size / 2.0, icon_size), false)
			draw_set_transform(Vector2.ZERO)
		else:
			# Ca-nô lướt sóng trên mặt nước
			if type == Types.VehicleType.BOAT:
				_draw_water_wake(offset, icon_size.x * 0.4, icon_size.y * 0.4, 11.0)

			draw_set_transform(offset, heading.angle() + (PI if left else 0.0), Vector2(-sc if left else sc, sc))
			draw_texture_rect(icon, Rect2(-icon_size / 2.0, icon_size), false)
			draw_set_transform(Vector2.ZERO)
		if state_id == Types.VehicleState.STRANDED:
			draw_arc(offset, icon_size.x / 2.0 + 4.0, 0.0, TAU, 24, Color('#FF4500'), 2.0)
		if (jammed or waiting_at_ferry) and state_id != Types.VehicleState.IDLE:  # đèn phanh ở đuôi xe
			var rear := offset - heading * (icon_size.x / 2.0 - 1.0)
			var brake_r := 1.8 if is_civilian_type() else 2.4
			if type == Types.VehicleType.MOTORBIKE:
				draw_circle(rear, brake_r, Color('#ff3b30'))
			else:
				var side := heading.rotated(PI / 2.0) * (icon_size.y * 0.28)
				draw_circle(rear + side, brake_r, Color('#ff3b30'))
				draw_circle(rear - side, brake_r, Color('#ff3b30'))

# ===== VEHICLE STATE (State pattern) =====
class VehicleStateBase extends RefCounted:
	func enter(_v: Vehicle) -> void: pass
	func update(_v: Vehicle, _delta: float) -> void: pass
	func exit(_v: Vehicle) -> void: pass
	func retry(_v: Vehicle) -> void: pass

class IdleState extends VehicleStateBase:
	# Đứng ở kho chờ điều phối; vừa về thì chạy chậm vào chỗ đỗ đã giữ rồi quay đầu xe theo chỗ đỗ.
	func update(v: Vehicle, delta: float) -> void:
		if not v.waypoints.is_empty() and v.maneuver(delta) and v.slot >= 0:
			v.heading = RescueManager.slot_heading(v.hub_id, v.type, v.slot)
			v.queue_redraw()

class EnRouteState extends VehicleStateBase:
	func update(v: Vehicle, delta: float) -> void:
		if not v.advance(delta):
			return
		if v.current_node == v.dest:
			v.change_state(DeliveringState.new(), Types.VehicleState.DELIVERING)
		elif not v.plan(v.dest):
			v.release_request()  # không tới được SOS: trả SOS về PENDING
			v.go_home()

class DeliveringState extends VehicleStateBase:
	var _t := 0.0
	func update(v: Vehicle, delta: float) -> void:
		_t += delta
		if _t >= Config.DELIVERY_TIME:
			var req := v.request
			v.request = null
			RescueManager.complete_request(req, v)
			v.next_or_home()

class ReturningState extends VehicleStateBase:
	func update(v: Vehicle, delta: float) -> void:
		if not v.advance(delta):
			return
		if v.current_node == v.hub_id:
			v.park()
		elif not v.plan(v.hub_id):
			v.change_state(StrandedState.new(), Types.VehicleState.STRANDED)

class StrandedState extends VehicleStateBase:
	var _t := 0.0
	func enter(v: Vehicle) -> void:
		v.release_request()  # đang kẹt thì không giữ SOS
	func update(v: Vehicle, delta: float) -> void:
		_t += delta
		if _t >= STRANDED_RETRY:
			_t = 0.0
			retry(v)
	func retry(v: Vehicle) -> void:
		if v.plan(v.hub_id):
			v.change_state(ReturningState.new(), Types.VehicleState.RETURNING)

# Xe dân: từ nhà ra kho. Đoạn đường ngập quá khả năng xe thì biến mất, SOS chuyển cho xe cứu hộ.
class CivToHubState extends VehicleStateBase:
	func update(v: Vehicle, delta: float) -> void:
		if v.civilian_blocked():
			v.civilian_vanish()
			return
		if not v.advance(delta):
			return
		if v.current_node == v.dest:
			v.change_state(CivLoadingState.new(), Types.VehicleState.DELIVERING)
		elif not v.plan(v.dest):
			v.civilian_vanish()

# Xe dân nhận hàng ở kho. Các xe tới sau xếp hàng chờ ở cổng nhờ luật dỡ hàng lần lượt trong congestion_factor.
class CivLoadingState extends VehicleStateBase:
	var _t := 0.0
	func update(v: Vehicle, delta: float) -> void:
		_t += delta
		if _t < Config.CIVILIAN_LOAD_TIME:
			return
		v.dest = v.home_id
		if v.plan(v.home_id):
			v.change_state(CivToHomeState.new(), Types.VehicleState.RETURNING)
		else:
			v.civilian_vanish()

# Xe dân chở hàng về nhà; về tới nhà thì SOS mới tính là được cứu.
class CivToHomeState extends VehicleStateBase:
	func update(v: Vehicle, delta: float) -> void:
		if v.civilian_blocked():
			v.civilian_vanish()
			return
		if not v.advance(delta):
			return
		if v.current_node == v.home_id:
			v.civilian_arrive_home()
		elif not v.plan(v.home_id):
			v.civilian_vanish()

# ===== VEHICLE FACTORY =====
class VehicleFactory extends RefCounted:
	static func create(vehicle_id: int, vehicle_type: int, hub: int) -> Vehicle:
		var v := Vehicle.new()
		v.id = vehicle_id
		v.type = vehicle_type
		v.hub_id = hub
		v.current_node = hub
		if RescueManager.g().get_map_node(hub) != null:
			v.position = RescueManager.stop_pos(hub)
		v.set_initial_state()
		return v

# ===== FERRY VESSEL (Thực thể Tàu phao vận tải độc lập) =====
class FerryVessel extends RefCounted:
	enum VesselState { DOCKED_A, SAILING_TO_B, DOCKED_B, SAILING_TO_A }

	var route_id: int
	var route_dict: Dictionary
	var node_a: int
	var node_b: int
	var pos_a: Vector2
	var pos_b: Vector2
	var dir_a: Vector2
	var dir_b: Vector2
	var dock_wait_pos_a: Vector2
	var dock_wait_pos_b: Vector2
	var path_points: PackedVector2Array = []
	var total_path_len: float = 0.0

	var state: int = VesselState.DOCKED_A
	var position: Vector2
	var heading: Vector2

	var capacity: int = 4 # Tải trọng tối đa: Xe tải=2, Ô tô=2, Xe máy=1
	var carried_vehicles: Array = []
	var queue_a: Array = []
	var queue_b: Array = []

	var progress_dist: float = 0.0
	var speed: float = 70.0
	var dwell_timer: float = 0.0
	const DWELL_MAX := 3.0

	func _init(r: Dictionary) -> void:
		update_route(r)
		position = dock_wait_pos_a
		heading = dir_a

	func update_route(r: Dictionary) -> void:
		route_dict = r
		route_id = r.get("edge_id", -1)
		node_a = r.get("node_a", -1)
		node_b = r.get("node_b", -1)
		pos_a = r.get("pos_a", Vector2.ZERO)
		pos_b = r.get("pos_b", Vector2.ZERO)
		var route_nodes: Array = r.get("route_nodes", [])
		var n1 = GraphManager.get_map_node(route_nodes[1]) if route_nodes.size() >= 3 else null
		var n_penult = GraphManager.get_map_node(route_nodes[-2]) if route_nodes.size() >= 3 else null
		dir_a = GraphManager.get_shore_river_direction(r.cell_a, n1.pos if n1 != null else Vector2.INF)
		if dir_a == Vector2.ZERO:
			dir_a = pos_a.direction_to(pos_b)
		dir_b = GraphManager.get_shore_river_direction(r.cell_b, n_penult.pos if n_penult != null else Vector2.INF)
		if dir_b == Vector2.ZERO:
			dir_b = pos_b.direction_to(pos_a)
		dock_wait_pos_a = pos_a + dir_a * 17.0
		dock_wait_pos_b = pos_b + dir_b * 17.0
		_build_path()

	func _build_path() -> void:
		path_points.clear()
		total_path_len = 0.0
		path_points.append(dock_wait_pos_a)
		var route_nodes: Array = route_dict.get("route_nodes", [])
		if route_nodes.size() > 2:
			for i in range(1, route_nodes.size() - 1):
				var wid: int = route_nodes[i]
				var wn = GraphManager.get_map_node(wid)
				if wn != null:
					path_points.append(wn.pos)
		path_points.append(dock_wait_pos_b)
		for i in range(path_points.size() - 1):
			total_path_len += path_points[i].distance_to(path_points[i + 1])

	func is_sailing() -> bool:
		return state == VesselState.SAILING_TO_B or state == VesselState.SAILING_TO_A

	func _current_load() -> int:
		var total := 0
		for v in carried_vehicles:
			if is_instance_valid(v):
				total += v.ferry_weight()
		return total

	func get_point_at_dist(d: float) -> Dictionary:
		if path_points.size() < 2:
			return {"pos": position, "dir": heading}
		var clamped_d := clampf(d, 0.0, total_path_len)
		var accum := 0.0
		for i in range(path_points.size() - 1):
			var p1 := path_points[i]
			var p2 := path_points[i + 1]
			var seg_len := p1.distance_to(p2)
			if accum + seg_len >= clamped_d or i == path_points.size() - 2:
				var t := (clamped_d - accum) / maxf(0.001, seg_len)
				var pos := p1.lerp(p2, clampf(t, 0.0, 1.0))
				var dir := (p2 - p1).normalized() if p1 != p2 else heading
				return {"pos": pos, "dir": dir}
			accum += seg_len
		return {"pos": path_points[-1], "dir": heading}

	func tick(delta: float) -> void:
		_clean_queues()
		match state:
			VesselState.DOCKED_A:
				position = dock_wait_pos_a
				heading = dir_a
				if not carried_vehicles.is_empty():
					_unboard_passengers(node_a, pos_a)
				_board_passengers(queue_a, node_a)
				_sync_carried_positions()
				if not carried_vehicles.is_empty():
					if _current_load() >= capacity:
						state = VesselState.SAILING_TO_B
						progress_dist = 0.0
						dwell_timer = 0.0
					else:
						if RescueManager.has_approaching_vehicle_to_dock(node_a, capacity - _current_load(), 3.0, route_id):
							dwell_timer += delta
							if dwell_timer >= DWELL_MAX:
								state = VesselState.SAILING_TO_B
								progress_dist = 0.0
								dwell_timer = 0.0
						else:
							state = VesselState.SAILING_TO_B
							progress_dist = 0.0
							dwell_timer = 0.0

			VesselState.SAILING_TO_B:
				progress_dist += speed * delta
				var sample := get_point_at_dist(progress_dist)
				position = sample.pos
				heading = sample.dir
				_sync_carried_positions()
				if progress_dist >= total_path_len:
					state = VesselState.DOCKED_B
					progress_dist = 0.0
					dwell_timer = 0.0
					position = dock_wait_pos_b
					heading = dir_b

			VesselState.DOCKED_B:
				position = dock_wait_pos_b
				heading = dir_b
				if not carried_vehicles.is_empty():
					_unboard_passengers(node_b, pos_b)
				_board_passengers(queue_b, node_b)
				_sync_carried_positions()
				if not carried_vehicles.is_empty():
					if _current_load() >= capacity:
						state = VesselState.SAILING_TO_A
						progress_dist = total_path_len
						dwell_timer = 0.0
					else:
						if RescueManager.has_approaching_vehicle_to_dock(node_b, capacity - _current_load(), 3.0, route_id):
							dwell_timer += delta
							if dwell_timer >= DWELL_MAX:
								state = VesselState.SAILING_TO_A
								progress_dist = total_path_len
								dwell_timer = 0.0
						else:
							state = VesselState.SAILING_TO_A
							progress_dist = total_path_len
							dwell_timer = 0.0

			VesselState.SAILING_TO_A:
				progress_dist -= speed * delta
				var sample := get_point_at_dist(progress_dist)
				position = sample.pos
				heading = -sample.dir
				_sync_carried_positions()
				if progress_dist <= 0.0:
					state = VesselState.DOCKED_A
					progress_dist = 0.0
					dwell_timer = 0.0
					position = dock_wait_pos_a
					heading = dir_a

	func can_queue(v: Variant, dock: int) -> bool:
		if not is_instance_valid(v) or not v.waiting_at_ferry or v.current_node != dock:
			return false
		if v.path == null or v.path_index >= v.path.edge_ids.size() or v.path_index + 1 >= v.path.node_ids.size():
			return false
		var edge := GraphManager.get_edge(v.path.edge_ids[v.path_index])
		var destination := node_b if dock == node_a else node_a
		return (dock == node_a or dock == node_b) and edge != null and not edge.suspended \
				and edge.ferry_route_id == route_id and v.path.node_ids[v.path_index + 1] == destination

	func _clean_queues() -> void:
		queue_a = queue_a.filter(func(v): return can_queue(v, node_a))
		queue_b = queue_b.filter(func(v): return can_queue(v, node_b))

	func _board_passengers(q: Array, dock: int) -> void:
		while not q.is_empty():
			var v = q[0]
			if not can_queue(v, dock):
				q.pop_front()
				continue
			var w: int = v.ferry_weight()
			if _current_load() + w <= capacity:
				q.pop_front()
				v.waiting_at_ferry = false
				v.is_boarded_on_ferry = true
				carried_vehicles.append(v)
			else:
				break

	func _unboard_passengers(dest_node: int, dest_pos: Vector2) -> void:
		for v in carried_vehicles:
			if is_instance_valid(v):
				v.is_boarded_on_ferry = false
				v.waiting_at_ferry = false
				v.current_node = dest_node
				v.position = dest_pos
				var matching_leg := false
				if v.path != null and v.path_index < v.path.edge_ids.size() and v.path_index + 1 < v.path.node_ids.size():
					var edge := GraphManager.get_edge(v.path.edge_ids[v.path_index])
					matching_leg = edge != null and edge.ferry_route_id == route_id and v.path.node_ids[v.path_index + 1] == dest_node
				if matching_leg:
					v.path_index += 1
				else:
					v.path = null
					v.path_index = 0
				v.visible = true
				v.queue_redraw()
		carried_vehicles.clear()

	func _sync_carried_positions() -> void:
		var count := carried_vehicles.size()
		if count == 0:
			return
		elif count == 1:
			var v: Vehicle = carried_vehicles[0]
			if is_instance_valid(v):
				v.position = position
				v.heading = heading
		elif count == 2:
			for i in range(2):
				var v: Vehicle = carried_vehicles[i]
				if is_instance_valid(v):
					var offset := heading * (-6.0 if i == 0 else 6.0)
					v.position = position + offset
					v.heading = heading
		else:
			var normal := heading.rotated(PI / 2.0)
			for i in range(count):
				var v: Vehicle = carried_vehicles[i]
				if is_instance_valid(v):
					var f_off := heading * (-6.0 if i < 2 else 6.0)
					var s_off := normal * (-4.0 if i % 2 == 0 else 4.0)
					v.position = position + f_off + s_off
					v.heading = heading

	func destroy() -> void:
		for v in carried_vehicles:
			if is_instance_valid(v):
				v.position = RescueManager.stop_pos(v.current_node)
				v.is_boarded_on_ferry = false
				v.waiting_at_ferry = false
				v.path = null
				v.path_index = 0
		carried_vehicles.clear()
		for dock in [node_a, node_b]:
			var queue: Array = queue_a if dock == node_a else queue_b
			for v in queue:
				if is_instance_valid(v) and v.waiting_at_ferry and v.current_node == dock:
					# Removal may already have cut the path. If a reroute selected
					# another ferry, the old queue has no claim on the passenger.
					if v.path != null and v.path_index < v.path.edge_ids.size() and v.path.edge_ids[v.path_index] != route_id:
						continue
					v.waiting_at_ferry = false
					v.path = null
					v.path_index = 0
			queue.clear()

# ===== MANAGER =====
var path_provider: Callable = Callable()  # tùy chọn: hàm tìm đường giả cho scene thử
var _requests := {}      # req_id -> SosRequest (SOS còn hiệu lực)
var _hubs := {}          # hub_id -> Hub
var _vehicles := {}      # vehicle_id -> Vehicle
var _civilians := {}       # nhà (node id) -> xe dân của nhà đó (tạo khi nhà có SOS đầu tiên)
var _civilian_type := {}   # nhà -> loại xe dân (xe máy hoặc ô tô), giữ nguyên trong ván
var _fresh: Array = []     # xe cứu hộ vừa nhận SOS trong lượt điều phối này (để thử gom thêm SOS thứ hai)
var _ferry_vessels := {}   # route_id -> FerryVessel
var _next_req_id := 0
var _next_vehicle_id := 0
var _wave := 0
var _spawning := false
var _spawn_timer := 0.0
var _house_timer := 0.0  # nhà mọc dần (bản đồ có cổng)
var _dispatch_timer := 0.0
var _dirty := false
var _graph_dirty := false  # đồ thị vừa đổi: điều phối lại, giãn cách DIRTY_DISPATCH_GAP
var _retry_stranded := false  # đồ thị vừa đổi: xe kẹt thử tìm đường lại, gom một lần mỗi khung hình
var _clock := 0.0
var _last_rescued := {}  # node_id -> thời điểm được cứu gần nhất

func _ready() -> void:
	EventBus.game_started.connect(reset)
	EventBus.wave_started.connect(set_wave)
	EventBus.wave_ended.connect(_on_wave_ended)
	EventBus.edge_added.connect(_on_edge_added)
	EventBus.edge_removed.connect(_on_edge_removed)
	EventBus.edge_state_changed.connect(_on_edge_state_changed)
	EventBus.ferry_routes_changed.connect(_sync_ferry_vessels)

func reset() -> void:
	for v in _vehicles.values():
		if is_instance_valid(v):  # xe gắn vào VehicleLayer đã bị giải phóng khi chơi lại (đổi scene)
			v.queue_free()
	_vehicles.clear()
	_civilians.clear()
	_civilian_type.clear()
	_fresh.clear()
	_slots.clear()
	_requests.clear()
	_hubs.clear()
	_last_rescued.clear()
	_ferry_vessels.clear()
	_sync_ferry_vessels()
	_next_req_id = 0
	_next_vehicle_id = 0
	_wave = 0
	_spawning = false
	_spawn_timer = 0.0
	_house_timer = 0.0
	_dispatch_timer = 0.0
	_dirty = false
	_clock = 0.0
	for id in g().get_node_ids():
		var n: MapNode = g().get_map_node(id)
		if n != null and n.kind == Types.NodeKind.HUB:
			var h := Hub.new(id)
			_hubs[id] = h
			for s in h.stock:
				EventBus.stock_changed.emit(id, s, h.stock[s])
	if _hubs.is_empty():
		return
	for i in START_TRUCKS:
		add_vehicle(Types.VehicleType.TRUCK)
	for i in START_BOATS:
		add_vehicle(Types.VehicleType.BOAT)

func set_wave(index: int) -> void:
	_wave = index
	_spawn_timer = 0.0
	_spawning = true

func set_spawning(enabled: bool) -> void:
	_spawning = enabled

func _on_wave_ended(_index: int) -> void:
	_spawning = false

# A roundabout edit can replace a node under a moving vehicle. Preserve its
# assignment and resume from the nearest legal anchor in the replacement graph.
func remap_roundabout_vehicles(replaced: Array, anchors: Array) -> void:
	for vehicle: Vehicle in _vehicles.values():
		if not is_instance_valid(vehicle) or vehicle.type == Types.VehicleType.BOAT or not replaced.has(vehicle.current_node):
			continue
		var best := INF
		var replacement: MapNode = null
		for id in anchors:
			var node := GraphManager.get_map_node(id)
			var distance: float = vehicle.position.distance_squared_to(node.pos)
			if distance < best:
				best = distance
				replacement = node
		vehicle.current_node = replacement.id
		vehicle.position = replacement.pos
		vehicle.path = null
		vehicle.path_index = 0
		vehicle._curve_edge = -1
		vehicle.current_speed = 0.0
		vehicle.target_speed = 0.0


func _on_edge_added(_edge_id: int) -> void:
	_on_graph_changed()

func _on_edge_removed(edge_id: int) -> void:
	for v in _vehicles.values():
		if is_instance_valid(v):  # xe ván cũ đã giải phóng cùng scene, chờ reset() dọn
			v.on_edge_removed(edge_id)
	_on_graph_changed()

func _on_edge_state_changed(_edge_id: int, _state: int) -> void:
	_on_graph_changed()

# Nước rút làm nhiều cạnh vùng ngập đổi trạng thái trong cùng một nhịp lũ: không cho mỗi lần đổi một lượt tìm đường
# của mọi xe kẹt, mà gom lại, xe kẹt thử lại một lần ở đầu khung hình sau (_process).
func _on_graph_changed() -> void:
	_graph_dirty = true
	_retry_stranded = true

func _retry_all_stranded() -> void:
	_retry_stranded = false
	for v in _vehicles.values():
		if is_instance_valid(v):
			v.retry_if_stranded()

func mark_dirty() -> void:
	_dirty = true

# Tìm đường cho xe; cạnh sắp có xe khác đi qua tính đắt hơn (CONGESTION_PATH_COST mỗi xe) để xe mới né chỗ đông.
# exclude: xe đang tự tính lại đường, không tính phần của chính nó.
func find_path(from_id: int, to_id: int, vehicle_type: int, exclude: Vehicle = null) -> PathResult:
	if path_provider.is_valid():
		return path_provider.call(from_id, to_id, vehicle_type)
	if graph != null:
		return g().find_path(from_id, to_id, vehicle_type)  # đồ thị giả của scene thử
	var p: PathResult = g().find_path(from_id, to_id, vehicle_type, congestion_penalty(exclude))
	return g().smooth_boat_path(p) if vehicle_type == Types.VehicleType.BOAT else p  # ca-nô lao thẳng trên nước thoáng


# ===== Kẹt xe =====
var _grid := {}  # ô lưới -> các xe đang chạy hoặc đang dỡ hàng trong ô đó (dựng lại mỗi khung hình)


func _rebuild_grid() -> void:
	_grid.clear()
	for v in _vehicles.values():
		if v.is_moving() or v.waiting_at_ferry or v.state_id == Types.VehicleState.DELIVERING:
			var key := Vector2i((v.position / GRID_CELL).floor())
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(v)


# Xe ở gần p (trong 3 ô quanh p, đủ cho FOLLOW_GAP và vùng ngã ba JUNCTION_APPROACH), để không phải so mọi cặp xe.
func _nearby(p: Vector2) -> Array:
	var out := []
	var c := Vector2i((p / GRID_CELL).floor())
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var k := c + Vector2i(dx, dy)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out


# Mỗi xe đang chạy làm các cạnh sắp đi của nó đắt thêm chi phí để xe khác tự né đường.
func congestion_penalty(exclude: Vehicle = null) -> Dictionary:
	var pen := {}
	for v in _vehicles.values():
		if v == exclude or not v.is_moving() or v.path == null:
			continue
		var is_water: bool = (v.type == Types.VehicleType.BOAT or v.is_on_ferry())
		var cost: float = WATER_VESSEL_CONGESTION_COST if is_water else CONGESTION_PATH_COST
		var lookahead: int = 5 if is_water else 3
		for k in range(v.path_index, mini(v.path_index + lookahead, v.path.edge_ids.size())):
			var eid: int = v.path.edge_ids[k]
			pen[eid] = float(pen.get(eid, 0.0)) + cost
	return pen


# Loại nút giao, quyết định luật nhường đường (congestion_factor) và hình vẽ (JunctionLayer):
# - ô đường nối với đúng 3 ô đường khác: vòng xoay; từ 4 ô đường trở lên: đèn giao thông;
# - ô đường có từ 3 cạnh nhưng chỉ 2 cạnh sang ô đường (chữ T trước cổng nhà), hoặc điểm có từ 3 cạnh
#   (bản đồ không có cổng như map_01): nhường theo khoảng cách như cũ;
# - còn lại (đoạn thẳng, khúc cua, nút nước của ca-nô): không phải nút giao.
func junction_kind(node_id: int) -> int:
	var n: MapNode = g().get_map_node(node_id)
	if n == null:
		return JUNCTION_NONE
	if g().has_method('ring_of') and g().ring_of(node_id) != -1:
		return JUNCTION_RING
	var edges: Array = g().get_edges_of(node_id)
	if n.kind != Types.NodeKind.ROAD:
		return JUNCTION_YIELD if edges.size() >= 3 else JUNCTION_NONE
	if g().has_method("has_traffic_light") and g().has_traffic_light(node_id):
		return JUNCTION_LIGHT
	return JUNCTION_YIELD if edges.size() >= 3 else JUNCTION_NONE


# Đèn ở nút node_id có xanh cho xe đi theo hướng heading không. Hai trục ngang, dọc luân phiên xanh
# mỗi LIGHT_PHASE giây theo đồng hồ ván (_clock); mỗi ngã tư lệch pha theo mã nút để không đổi cùng lúc.
func light_green(node_id: int, heading: Vector2) -> bool:
	var offset := fposmod(float(node_id) * 1.7, LIGHT_PHASE * 2.0)
	var phase := int(floor((_clock + offset) / LIGHT_PHASE)) % 2
	var axis := 0 if absf(heading.x) >= absf(heading.y) else 1
	return axis == phase


# Xe đang chạy trong vòng xoay: cách tâm nút vòng xoay vừa rời hoặc sắp tới dưới JUNCTION_RADIUS.
# Xe u đang chạy trên một cạnh của vòng xoay ring.
func _on_ring(u: Vehicle, ring: int) -> bool:
	if not u.is_moving():
		return false
	var eid: int = u.path.edge_ids[u.path_index]
	return g().is_ring_edge(eid) and g().ring_of(u.next_node()) == ring


# Hệ số tốc độ do kẹt xe (1 = chạy bình thường, 0 = dừng chờ), chỉ dùng khoảng cách:
# - bám đuôi: xe phía trước cùng hướng, cùng làn, cách dưới FOLLOW_GAP thì chậm, dưới STOP_GAP thì dừng;
# - nút giao (junction_kind của nút sắp tới), xét khi xe sắp vào (cách tâm từ JUNCTION_RADIUS tới JUNCTION_APPROACH):
#   - nhường theo khoảng cách: nhường xe đang ở trong nút, hoặc xe từ nhánh cắt ngang ở gần nút hơn;
#     bằng nhau thì xe có mã nhỏ hơn đi trước, nên hai xe không cùng nhường nhau;
#   - vòng xoay (vòng đường 2×2, 3×3 người chơi vẽ): xe từ ngoài nhập vào nhường xe đang chạy trên vòng ở gần
#     chỗ nhập (RING_YIELD); xe trên vòng chạy tiếp;
#   - đèn: trục của mình đang đỏ thì dừng (at_red); xanh thì vẫn nhường xe còn trong ngã tư đi cắt ngang.
# others: danh sách xe để xét (test truyền vào); rỗng thì dùng mọi xe của RescueManager.
func congestion_factor(v: Vehicle, others: Array = [], brake_ahead := false) -> float:
	v.at_red = false
	v.traffic_stop_distance = INF
	if not v.is_moving():
		return 1.0
	var list: Array = others if not others.is_empty() else _nearby(v.position)
	var current: Edge = g().get_edge(v.path.edge_ids[v.path_index])
	var f := 1.0
	var nxt := v.next_node()
	var kind := junction_kind(nxt) if nxt != -1 else JUNCTION_NONE
	var jpos := Vector2.ZERO
	var dv := INF
	var approaching := false
	if kind != JUNCTION_NONE:
		jpos = g().get_map_node(nxt).pos
		dv = v.position.distance_to(jpos)
		var anticipation: float = v.current_speed * v.current_speed / (2.0 * Config.BRAKING[v.type]) if brake_ahead else 0.0
		approaching = dv >= JUNCTION_RADIUS - ARRIVE_EPSILON and dv <= JUNCTION_APPROACH + anticipation
	var ring: int = g().ring_of(nxt) if kind == JUNCTION_RING else -1
	var entering_ring: bool = ring != -1 and not g().is_ring_edge(v.path.edge_ids[v.path_index])  # từ ngoài nhập vào vòng
	if approaching and kind == JUNCTION_LIGHT and not light_green(nxt, v.heading):
		v.at_red = true
		if not brake_ahead:
			return 0.0
		v.traffic_stop_distance = maxf(0.0, dv - JUNCTION_RADIUS)
	for u in list:
		if u == v or u.is_boarded_on_ferry:
			continue
		var other: Edge = g().get_edge(u.path.edge_ids[u.path_index]) if u.is_moving() else null
		if current != null and current.is_highway and (other == null or other.id != current.id):
			continue
		if other != null and other.is_highway and (current == null or other.id != current.id):
			continue
		# Dỡ hàng lần lượt: xe đang dỡ hàng ở một SOS chặn các xe khác tới đúng SOS đó (xếp hàng chờ).
		# Xe chỉ đi ngang khu đó không bị chặn.
		if u.state_id == Types.VehicleState.DELIVERING and v.request != null and u.dest == v.dest and nxt == u.current_node:
			var gap: float = v.position.distance_to(u.position)
			if brake_ahead:
				v.traffic_stop_distance = minf(v.traffic_stop_distance, maxf(0.0, gap - FOLLOW_GAP))
			elif gap < FOLLOW_GAP:
				return 0.0
			continue
		if not u.is_moving() and not u.waiting_at_ferry:
			continue
		var rel: Vector2 = u.position - v.position
		var along := rel.dot(v.heading)
		var ahead: bool = along > 0.0 or (rel.length() < 1.0 and u.id < v.id)  # cùng chỗ (vừa rời kho): xe mã nhỏ đi trước
		if ahead and u.heading.dot(v.heading) > 0.7 and absf(rel.cross(v.heading)) < SAME_LANE:
			if brake_ahead:
				v.traffic_stop_distance = minf(v.traffic_stop_distance, maxf(0.0, along - STOP_GAP))
			elif along < STOP_GAP:
				return 0.0
			if along < FOLLOW_GAP:
				f = minf(f, FOLLOW_SLOW)
		# Tuyến phà vượt sông: xe ngược chiều đang qua phà thì nhường đường ở bến
		if v.path != null and v.path_index < v.path.edge_ids.size():
			var v_eid: int = v.path.edge_ids[v.path_index]
			var fe: Edge = g().get_edge(v_eid)
			if fe != null and fe.is_ferry and u.is_moving() and u.path != null and u.path_index < u.path.edge_ids.size():
				if u.path.edge_ids[u.path_index] == v_eid and u.heading.dot(v.heading) < -0.3:
					return 0.0
		if not approaching:
			continue
		var du: float = u.position.distance_to(jpos)
		var inside: bool = du <= JUNCTION_RADIUS
		var cross: bool = absf(u.heading.dot(v.heading)) < 0.7
		match kind:
			JUNCTION_YIELD:
				var first: bool = u.next_node() == nxt and (du < dv or (is_equal_approx(du, dv) and u.id < v.id))
				if cross and (inside or first):
					f = 0.0
			JUNCTION_RING:
				if entering_ring and _on_ring(u, ring) and u.position.distance_to(jpos) < RING_YIELD:
					f = 0.0
			JUNCTION_LIGHT:
				if inside and cross:
					f = 0.0
	if brake_ahead and f == 0.0:
		v.traffic_stop_distance = minf(v.traffic_stop_distance, maxf(0.0, dv - JUNCTION_RADIUS))
		f = 1.0
	return f

func _process(delta: float) -> void:
	_clock += delta
	if _retry_stranded:
		_retry_all_stranded()
	_rebuild_grid()
	_tick_water_detour(delta)
	_tick_ferry_vessels(delta)
	for h in _hubs.values():
		for s in h.tick(delta):
			EventBus.stock_changed.emit(h.id, s, h.stock[s])
	_tick_requests(delta)
	if _spawning:
		_tick_spawn(delta)
		_tick_houses(delta)
	_dispatch_timer += delta
	if _dirty or (_graph_dirty and _dispatch_timer >= DIRTY_DISPATCH_GAP) or _dispatch_timer >= DISPATCH_INTERVAL:
		_dirty = false
		_graph_dirty = false
		_dispatch_timer = 0.0
		_dispatch()

# Phát hiện 2 thuyền / phà đối đầu ngược chiều trên mặt nước và kích hoạt tìm đường vòng lách tránh.
func _tick_water_detour(delta: float) -> void:
	var water_vessels: Array = []
	for v in _vehicles.values():
		if v.is_moving() and (v.type == Types.VehicleType.BOAT or v.is_on_ferry()):
			water_vessels.append(v)
	for i in range(water_vessels.size()):
		var v: Vehicle = water_vessels[i]
		for j in range(i + 1, water_vessels.size()):
			var u: Vehicle = water_vessels[j]
			var dist: float = v.position.distance_to(u.position)
			if dist > 90.0:
				continue
			# Hai thuyền đối đầu ngược chiều
			if v.heading.dot(u.heading) < -0.5:
				# Thuyền có ID nhỏ hơn (ưu tiên thấp) nhường đường, tìm đường vòng khác
				var lower: Vehicle = v if v.id < u.id else u
				lower.request_water_detour()

func get_ferry_vessels() -> Array:
	if _ferry_vessels.is_empty() and not g().get_ferry_routes().is_empty():
		_sync_ferry_vessels()
	return _ferry_vessels.values()

func _sync_ferry_vessels() -> void:
	var routes: Array = g().get_ferry_routes()
	var active_ids := {}
	for r in routes:
		var rid: int = r.get("route_id", -1)
		if rid == -1 or not r.get("open", false):
			continue
		active_ids[rid] = true
		if not _ferry_vessels.has(rid):
			_ferry_vessels[rid] = FerryVessel.new(r)
		elif _ferry_vessels[rid].route_dict.route_nodes != r.route_nodes:
			_ferry_vessels[rid].destroy()
			_ferry_vessels[rid] = FerryVessel.new(r)
	var to_remove := []
	for rid in _ferry_vessels.keys():
		if not active_ids.has(rid):
			to_remove.append(rid)
	for rid in to_remove:
		_ferry_vessels[rid].destroy()
		_ferry_vessels.erase(rid)

func _tick_ferry_vessels(delta: float) -> void:
	for fv in _ferry_vessels.values():
		fv.tick(delta)

func register_ferry_passenger(v: Vehicle, dock_node: int) -> void:
	if v.path == null or v.path_index >= v.path.edge_ids.size():
		return
	var edge: Edge = g().get_edge(v.path.edge_ids[v.path_index])
	if edge == null:
		return
	var ferry: FerryVessel = _ferry_vessels.get(edge.ferry_route_id)
	if ferry == null or not ferry.can_queue(v, dock_node):
		return
	var queue: Array = ferry.queue_a if ferry.node_a == dock_node else ferry.queue_b
	if not queue.has(v):
		queue.append(v)


func has_approaching_vehicle_to_dock(dock_node: int, max_weight: int, max_eta: float, route_id: int = -1) -> bool:
	var dock_n = g().get_map_node(dock_node)
	if dock_n == null:
		return false
	for v in _vehicles.values():
		if not v.is_moving() or v.is_on_ferry() or v.path == null:
			continue
		if v.ferry_weight() > max_weight:
			continue
		for k in range(v.path_index, mini(v.path_index + 4, v.path.node_ids.size())):
			if v.path.node_ids[k] == dock_node:
				if route_id != -1:
					var edge: Edge = g().get_edge(v.path.edge_ids[k]) if k < v.path.edge_ids.size() else null
					if edge == null or edge.ferry_route_id != route_id:
						continue
				var dist: float = v.position.distance_to(dock_n.pos)
				var speed: float = Config.base_speed(v.type)
				var acceleration: float = Config.ACCELERATION[v.type]
				var ramp := clampf((speed - v.current_speed) / acceleration, 0.0, max_eta)
				var reachable: float = (v.current_speed + acceleration * ramp * 0.5) * ramp + speed * (max_eta - ramp)
				if dist <= reachable:
					return true
				break
	return false

func _tick_requests(delta: float) -> void:
	for rid in _requests.keys():
		var r: SosRequest = _requests[rid]
		r.time_left -= delta
		if r.time_left <= 0.0:
			r.state = Types.SosState.FAILED
			_requests.erase(rid)
			for vid in r.vehicle_ids.duplicate():  # mọi xe đang giữ SOS này (đang đi tới hoặc trong hàng đợi)
				if _vehicles.has(vid) and is_instance_valid(_vehicles[vid]):
					_vehicles[vid].drop_request(r)
			EventBus.sos_failed.emit(rid)

func _tick_spawn(delta: float) -> void:
	var w: Dictionary = Config.get_wave_profile(_wave + 1)
	_spawn_timer += delta
	if _spawn_timer < w.sos_interval:
		return
	_spawn_timer = 0.0
	if _requests.size() >= w.sos_max:
		return
	var req := SosFactory.create(_next_req_id, _wave, _free_nodes().filter(has_rescue_route))
	if req == null:
		return
	_next_req_id += 1
	_requests[req.id] = req
	EventBus.sos_spawned.emit(req.id, req.node_id, req.supply, req.time_total)
	_dirty = true

# ===== Cổng, chỗ đỗ, nhà mọc dần (bản đồ có cổng) =====
# Vị trí xe dừng ở node: điểm có cổng thì dừng trên lối vào, ngay trước mép tòa nhà (không đè lên icon); điểm không cổng ở tâm.
func stop_pos(node_id: int) -> Vector2:
	var n: MapNode = g().get_map_node(node_id)
	if n == null:
		return Vector2.ZERO
	if n.kind == Types.NodeKind.HUB:
		return n.pos  # kho: trong nhà kho; chỗ đỗ ở bãi tính riêng (slot_pos)
	if n.gate == Vector2i.ZERO:
		return n.pos
	return n.pos + Vector2(n.gate).normalized() * (g().point_radius(node_id) + PARK_GAP)

# ----- Bãi đỗ của kho (xe tải) và bến (ca-nô) -----
# Bãi nằm ở ô giữa kho và cổng: lối đi giữa chạy từ kho ra cổng, mỗi bên 3 chỗ đỗ vuông góc (xe đỗ đầu vào trong).
# Bến ở phía sông: các chỗ xếp hàng dọc bờ, mũi ca-nô hướng ra sông. Bãi, bến đầy thì xe vào trong kho (ẩn).
var _slots := {}  # Vector2i(kho, loại xe) -> Array id xe ở từng chỗ (-1: trống)

func slot_count(hub_id: int, type: int) -> int:
	if not _uses_gates():
		return 0
	if type == Types.VehicleType.TRUCK:
		return LOT_SLOTS if g().get_lot_cell(hub_id) != Vector2i(-1, -1) else 0
	return _dock_slots(hub_id).size()

# Giữ một chỗ trống cho xe (khi xe mới vào kho hoặc bắt đầu về kho). Hết chỗ thì xe vào trong kho.
func reserve_slot(v: Vehicle) -> void:
	if v.slot >= 0:
		return
	var n := slot_count(v.hub_id, v.type)
	if n == 0:
		return
	var key := Vector2i(v.hub_id, v.type)
	if not _slots.has(key):
		var empty := []
		empty.resize(n)
		empty.fill(-1)
		_slots[key] = empty
	var arr: Array = _slots[key]
	for i in n:
		if arr[i] == -1:
			arr[i] = v.id
			v.slot = i
			return

func release_slot(v: Vehicle) -> void:
	if v.slot < 0:
		return
	var arr: Array = _slots.get(Vector2i(v.hub_id, v.type), [])
	if v.slot < arr.size() and arr[v.slot] == v.id:
		arr[v.slot] = -1
	v.slot = -1

# Xe nhận nhiệm vụ: trả chỗ; xe tải lùi ra lối đi cạnh chỗ đỗ rồi mới chạy ra cổng.
func _leave_slot(v: Vehicle) -> void:
	v.waypoints.clear()
	if v.slot >= 0 and v.type == Types.VehicleType.TRUCK:
		v.waypoints.append(aisle_pos(v.hub_id, v.slot))
	release_slot(v)

# Hệ trục của bãi: tâm ô bãi, hướng từ kho ra cổng (dọc lối đi), hướng ngang lối đi.
func _lot_frame(hub_id: int) -> Array:
	var n: MapNode = g().get_map_node(hub_id)
	var d := Vector2(n.gate)
	return [g().cell_center(g().get_lot_cell(hub_id)), d, Vector2(-d.y, d.x)]

func slot_point(hub_id: int, type: int, i: int) -> Vector2:
	var n: MapNode = g().get_map_node(hub_id)
	if type == Types.VehicleType.TRUCK:
		var f := _lot_frame(hub_id)
		var side := -1.0 if i < LOT_SLOTS / 2 else 1.0
		return f[0] + f[1] * (float(i % (LOT_SLOTS / 2)) - 1.0) * SLOT_PITCH + f[2] * side * SLOT_DEPTH
	var docks := _dock_slots(hub_id)
	return g().get_map_node(docks[i]).pos if i < docks.size() else n.pos  # đỗ ngay tại nút nước nối bến: luôn trên sông

func slot_heading(hub_id: int, type: int, i: int) -> Vector2:
	if type == Types.VehicleType.TRUCK:
		var f := _lot_frame(hub_id)
		return f[2] * (-1.0 if i < LOT_SLOTS / 2 else 1.0)  # đầu xe hướng vào trong chỗ đỗ
	var h: MapNode = g().get_map_node(hub_id)
	return (slot_point(hub_id, type, i) - h.pos).normalized()  # mũi ca-nô hướng ra sông, đuôi về phía kho

func slot_pos(v: Vehicle) -> Vector2:
	return slot_point(v.hub_id, v.type, v.slot)

# Điểm trên lối đi giữa bãi, ngay cạnh chỗ đỗ i.
func aisle_pos(hub_id: int, i: int) -> Vector2:
	var f := _lot_frame(hub_id)
	return f[0] + f[1] * (float(i % (LOT_SLOTS / 2)) - 1.0) * SLOT_PITCH

# Đích của xe khi tới node: về kho có chỗ giữ sẵn thì xe tải tới lối đi cạnh chỗ đó, ca-nô tới thẳng chỗ ở bến.
func arrive_pos(v: Vehicle, node_id: int) -> Vector2:
	if v.type == Types.VehicleType.BOAT:
		return boat_stop_pos(v, node_id)
	if node_id == v.hub_id and v.slot >= 0 and v.path != null and v.path_index == v.path.edge_ids.size() - 1:
		return aisle_pos(v.hub_id, v.slot) if v.type == Types.VehicleType.TRUCK else slot_pos(v)
	return stop_pos(node_id)

# Xe tải đang ở trong ô bãi của kho mình (đi giữa lối, vẽ nhỏ).
func in_lot(v: Vehicle) -> bool:
	if v.type != Types.VehicleType.TRUCK or slot_count(v.hub_id, v.type) == 0:
		return false
	var f := _lot_frame(v.hub_id)
	var rel: Vector2 = v.position - f[0]
	return absf(rel.dot(f[1])) <= Config.CELL_SIZE / 2.0 + 1.0 and absf(rel.dot(f[2])) <= SLOT_DEPTH + 12.0

func draw_scale(v: Vehicle) -> float:
	if in_lot(v):
		return PARKED_SCALE
	if v.type == Types.VehicleType.BOAT and v.slot >= 0 and v.position.distance_to(slot_pos(v)) < 12.0:
		return PARKED_SCALE  # ca-nô đỗ ở bến
	return 1.0

# ----- Ca-nô: đỗ và cập bến trên nước, không lên bờ -----
# Chỗ đỗ ca-nô ở bến kho: các nút nước nối bến, ưu tiên hướng ít chĩa xuống (dưới kho là tên kho và nhãn hàng),
# bỏ nút nằm thẳng phía dưới kho; tối đa DOCK_SLOTS chỗ.
func _dock_slots(hub_id: int) -> Array[int]:
	var out: Array[int] = []
	if not g().has_method('get_dock_nodes'):
		return out
	var h: MapNode = g().get_map_node(hub_id)
	if h == null:
		return out
	var nodes: Array = g().get_dock_nodes(hub_id).filter(func(id: int) -> bool: return not g().is_flood_node(id))  # stable berths on permanent water
	var dir := func(id: int) -> Vector2: return (g().get_map_node(id).pos - h.pos).normalized()
	var ok := func(id: int) -> bool: return dir.call(id).y <= DOCK_MAX_DOWN  # không chĩa xuống chỗ tên kho, nhãn hàng
	nodes = nodes.filter(ok)
	nodes.sort_custom(func(a: int, b: int) -> bool:
		var da: Vector2 = dir.call(a)
		var db: Vector2 = dir.call(b)
		return da.y < db.y - 0.01 or (absf(da.y - db.y) <= 0.01 and a < b))
	for id in nodes:
		if out.size() >= DOCK_SLOTS:
			break
		out.append(id)
	# Chưa đủ chỗ: neo thêm ở các nút sông kề bến (vẫn trên nước, không chĩa xuống, không quá xa kho).
	var k := 0
	while out.size() < DOCK_SLOTS and k < out.size():
		for w in g().get_water_neighbors(out[k]):
			if out.size() >= DOCK_SLOTS:
				break
			if not out.has(w) and not g().is_flood_node(w) and ok.call(w) and g().get_map_node(w).pos.distance_to(h.pos) <= DOCK_REACH:
				out.append(w)
		k += 1
	return out

# Các nút nước làm chỗ đỗ ca-nô ở bến kho (NodeLayer vẽ cầu tàu tới những chỗ sát kho).
func dock_slot_nodes(hub_id: int) -> Array[int]:
	return _dock_slots(hub_id)

# Ca-nô đang chạy trên cạnh của riêng nó (sông, vùng ngập, bến) và nằm dưới một mảnh đường chưa ngập sâu (cầu):
# vẽ dưới lớp đường để thấy ca-nô luồn dưới cầu. Chạy dọc đường ngập, đang đỗ, hay bản đồ không theo lưới thì vẽ trên.
func under_bridge(v: Vehicle) -> bool:
	if not Road.bridges or not v.is_moving():
		return false
	var e: Edge = g().get_edge(v.path.edge_ids[v.path_index])
	if e == null or not e.boat_only:
		return false
	var reach: float = Road.CASING_WIDTH / 2.0 + Vehicle.ICON_SIZE.x / 2.0
	var c: Vector2i = g().cell_of(v.position)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var rid: int = g().road_at(c + Vector2i(dx, dy))
			if rid == -1:
				continue
			var rp: Vector2 = g().get_map_node(rid).pos
			for eid in g().get_edges_of(rid):
				var re: Edge = g().get_edge(eid)
				if re.state == Types.EdgeState.DEEP:
					continue
				var mid: Vector2 = (rp + g().get_map_node(re.other_end(rid)).pos) / 2.0  # mảnh đường của ô: từ tâm ô tới giữa cạnh
				if Geometry2D.get_closest_point_to_segment(v.position, rp, mid).distance_to(v.position) <= reach:
					return true
	return false

# Đích của ca-nô khi tới node: về kho có chỗ thì tới chỗ đỗ ở bến; cập bến một điểm (kho, khu, nhà) từ nút nước thì
# dừng ngay trên nút nước đó (đã bảo đảm nằm trên sông), không chạy lên bờ tới tâm điểm.
func boat_stop_pos(v: Vehicle, node_id: int) -> Vector2:
	var n: MapNode = g().get_map_node(node_id)
	if n == null:
		return Vector2.ZERO
	if n.kind == Types.NodeKind.HUB or n.kind == Types.NodeKind.DISTRICT:
		var prev: int = v.path.node_ids[v.path_index] if v.path != null and v.path_index < v.path.node_ids.size() else -1
		var w: MapNode = g().get_map_node(prev) if prev != -1 else null
		if w != null and w.kind == Types.NodeKind.WATER:
			if n.kind == Types.NodeKind.HUB:
				return w.pos
			var before: int = v.path.node_ids[v.path_index - 1] if v.path_index >= 1 else -1
			return _boat_clear_point(node_id, prev, before)
	if n.kind == Types.NodeKind.WATER and v.path != null and v.path_index + 2 == v.path.node_ids.size() - 1:
		var dest: MapNode = g().get_map_node(v.path.node_ids[-1])
		if dest != null and dest.kind == Types.NodeKind.DISTRICT:  # sắp cập bến khu, nhà: dừng luôn ở chỗ cách lô đất
			return _boat_clear_point(dest.id, node_id, v.path.node_ids[v.path_index])
	return stop_pos(node_id)

# Chỗ ca-nô dừng khi cập bến khu, nhà qua nút nước w: tại w, hoặc nếu w sát lô đất thì lùi dọc đoạn sông từ w về nút
# nước trước đó (đoạn đã kiểm tra nằm trên nước) tới khi cách tâm nhà ít nhất nửa lô + BOAT_CLEAR. Không đè lên lô.
func _boat_clear_point(point_id: int, w_id: int, before_id: int) -> Vector2:
	var n: MapNode = g().get_map_node(point_id)
	var w: Vector2 = g().get_map_node(w_id).pos
	var need: float = g().point_radius(point_id) + BOAT_CLEAR
	var b: MapNode = g().get_map_node(before_id) if before_id != -1 else null
	if w.distance_to(n.pos) >= need or b == null or b.kind != Types.NodeKind.WATER:
		return w
	for k in range(1, 11):
		var p := w.lerp(b.pos, k / 10.0)
		if p.distance_to(n.pos) >= need:
			return p
	return b.pos

func _boat_segment_open(a: Vector2, b: Vector2) -> bool:
	return not g().has_method("water_line") or g().water_line(a, b)


func _boat_berth_waypoints(v: Vehicle) -> Array[Vector2]:
	var berth := slot_pos(v)
	if _boat_segment_open(v.position, berth):
		return [berth]
	var from: int = g().boat_node_at(g().cell_of(v.position))
	var to: int = g().boat_node_at(g().cell_of(berth))
	var path := find_path(from, to, Types.VehicleType.BOAT, v)
	var points: Array[Vector2] = []
	if path.found and _boat_segment_open(v.position, g().get_map_node(from).pos):
		for id in path.node_ids:
			points.append(g().get_map_node(id).pos)
	return points


# Launch a stored boat at its dock. A boat already on the river must reach the
# destination from its actual water cell, even if the logical dock chose another berth.
func _redirect_boat_departure(v: Vehicle, next_id: int) -> bool:
	var from: MapNode = g().get_map_node(v.current_node)
	var to: MapNode = g().get_map_node(next_id)
	if from == null or to == null or from.kind == Types.NodeKind.WATER or to.kind != Types.NodeKind.WATER:
		return false
	if _boat_segment_open(v.position, to.pos):
		return false
	var anchor: int = g().boat_node_at(g().cell_of(v.position))
	if anchor == -1 and from.kind == Types.NodeKind.HUB and v.position.is_equal_approx(from.pos):
		v.position = to.pos
		return false
	var goal: int = v.path.node_ids.back()
	v.path = PathResult.new()
	v.path_index = 0
	if anchor != -1:
		v.current_node = anchor
		v.plan(goal)
	return true


func _uses_gates() -> bool:
	return g().has_method('uses_gates') and g().uses_gates()

# Mỗi house_interval giây của đợt hiện tại, một nhà mới mọc quanh một khu đã mở.
func _tick_houses(delta: float) -> void:
	if not _uses_gates():
		return
	_house_timer += delta
	if _house_timer < float(Config.get_wave_profile(_wave + 1).get('house_interval', INF)):
		return
	_house_timer = 0.0
	try_spawn_house()

# Chọn ngẫu nhiên một khu đã mở còn chưa đủ HOUSE_MAX_PER_DISTRICT nhà, đặt nhà ở ô khô trong vùng chơi
# cách khu tối đa HOUSE_RADIUS ô. Trả id nhà mới, -1 nếu không khu nào còn ô hợp lệ.
func try_spawn_house() -> int:
	var houses := {}  # khu mẹ -> số nhà
	for id in g().get_node_ids():
		var n: MapNode = g().get_map_node(id)
		if n.parent != -1:
			houses[n.parent] = int(houses.get(n.parent, 0)) + 1
	var districts := []
	for id in g().get_node_ids():
		var n: MapNode = g().get_map_node(id)
		if n.kind == Types.NodeKind.DISTRICT and n.parent == -1 and GameManager.is_in_play(n.pos) \
				and int(houses.get(id, 0)) < Config.HOUSE_MAX_PER_DISTRICT:
			districts.append(id)
	if districts.is_empty():
		return -1
	# Chọn khu ngẫu nhiên, rồi ô ngẫu nhiên trong số mọi ô hợp lệ quanh khu đó (chọn ô hú họa hay trượt hết lượt
	# dù còn chỗ). Khu không còn ô nào thì thử khu khác.
	var r: int = Config.HOUSE_RADIUS
	districts.shuffle()
	for d in districts:
		var center: Vector2i = g().cell_of(g().get_map_node(d).pos)
		var cells: Array[Vector2i] = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := center + Vector2i(dx, dy)
				if GameManager.is_in_play(g().cell_center(cell)) and FloodManager.depth_at(cell) < 0.05 and g().can_place_house(cell):
					cells.append(cell)
		if not cells.is_empty():
			return g().add_house(cells[randi() % cells.size()], d)
	return -1

# Số xe đang đỗ ở kho hub_id theo loại (nhãn ở kho), và số xe thuộc kho đó.
# Bỏ qua xe đã bị giải phóng (đổi scene khi chơi lại, trước khi reset() dọn danh sách).
func get_idle_count(hub_id: int, type: int) -> int:
	var count := 0
	for v in _vehicles.values():
		if is_instance_valid(v) and not v.is_civilian and v.hub_id == hub_id and v.type == type and v.state_id == Types.VehicleState.IDLE:
			count += 1
	return count

func get_home_count(hub_id: int, type: int) -> int:
	var count := 0
	for v in _vehicles.values():
		if is_instance_valid(v) and not v.is_civilian and v.hub_id == hub_id and v.type == type:
			count += 1
	return count

func _free_nodes() -> Array:
	var busy := []
	for r in _requests.values():
		busy.append(r.node_id)
	var result := []
	for id in g().get_node_ids():
		var n: MapNode = g().get_map_node(id)
		if n == null or n.kind != Types.NodeKind.DISTRICT or id in busy:
			continue
		if not GameManager.is_in_play(n.pos):
			continue  # khu chưa mở (vùng chơi theo đợt)
		if _clock - _last_rescued.get(id, -INF) < Config.SOS_COOLDOWN:
			continue
		result.append(id)
	return result

# ===== Điều phối =====
func _dispatch() -> void:
	var pending := get_pending_requests()
	pending.sort_custom(func(a, b):
		if a.prioritized != b.prioritized:
			return a.prioritized
		return a.time_left < b.time_left)
	# Đồ thị thật: mỗi (kho, loại xe) chỉ tính một cây đường ngắn nhất cho cả lượt (lúc cần tới), rồi lấy
	# đường tới từng SOS từ cây đó. Chi phí chỗ đông lấy lúc đầu lượt. Scene thử (đường giả, đồ thị giả) tính từng cặp như cũ.
	var use_tree: bool = not path_provider.is_valid() and graph == null
	var trees := {}
	var pen := {}
	for r in pending:
		if _dispatch_civilian(r):
			continue  # nhà này đã có xe dân tự ra kho lấy hàng
		# SOS lớn cần nhiều xe: giao thêm xe rảnh cho tới khi đủ số phần. Xe sau tính đường có cộng
		# chi phí chỗ đông (congestion_penalty) nên có thể tự chọn đường vòng.
		while r.missing() > 0:
			var best_v: Vehicle = null
			var best_p: PathResult = null
			var tried := {}  # xe rảnh cùng kho, cùng loại đứng cùng chỗ nên chung một đường: chỉ tính một lần
			for v in _vehicles.values():
				if v.is_civilian or v.state_id != Types.VehicleState.IDLE:
					continue
				if not _hubs.has(v.hub_id) or _hubs[v.hub_id].stock[r.supply] <= 0:
					continue
				var key := Vector2i(v.hub_id, v.type)
				if tried.has(key):
					continue
				tried[key] = true
				var p: PathResult
				if use_tree:
					if not trees.has(key):
						if trees.is_empty():
							pen = congestion_penalty()
						trees[key] = g().shortest_tree(v.hub_id, v.type, pen)
					p = g().path_from_tree(trees[key], v.hub_id, r.node_id)
				else:
					p = find_path(v.hub_id, r.node_id, v.type)
				if p.found and (best_v == null or p.cost < best_p.cost):
					best_v = v
					best_p = p
			if best_v == null:
				break
			_assign(r, best_v, best_p)
	# Xe cứu hộ vừa nhận việc, tải trọng ≥ 2: thử gom thêm một SOS thứ hai ở gần.
	for v in _fresh:
		if is_instance_valid(v) and v.request != null:
			_try_add_second(v, v.request)
	_fresh.clear()

func _assign(r: SosRequest, v: Vehicle, p: PathResult) -> void:
	r.assigned += 1
	r.vehicle_ids.append(v.id)
	r.vehicle_id = v.id
	if r.missing() <= 0:
		r.state = Types.SosState.ASSIGNED  # đủ xe: đổi trước để không xe nào nhận thêm
	v.request = r
	v.dest = r.node_id
	v.path = p
	v.path_index = 0
	v.current_node = v.hub_id
	var h: Hub = _hubs[v.hub_id]
	h.stock[r.supply] -= 1
	EventBus.stock_changed.emit(h.id, r.supply, h.stock[r.supply])
	if v.type == Types.VehicleType.BOAT and g().has_method('smooth_boat_path'):
		v.path = g().smooth_boat_path(v.path)  # đường từ cây điều phối: ca-nô lao thẳng trên nước thoáng
	_leave_slot(v)
	v.change_state(EnRouteState.new(), Types.VehicleState.EN_ROUTE)
	EventBus.sos_assigned.emit(r.id, v.id)
	_fresh.append(v)  # xe cứu hộ vừa nhận việc: thử gom thêm SOS thứ hai

# ===== Xe dân =====
# Nhà có SOS: xe của nhà tự ra kho gần nhất còn hàng lấy hàng rồi chở về. Trả true nếu đã giao việc cho xe dân.
# Không có đường (nhà bị cô lập) hoặc xe dân đã gặp ngập thì trả false: SOS để cho xe cứu hộ hạng nặng.
func _dispatch_civilian(r: SosRequest) -> bool:
	if r.heavy_only or r.units != 1 or r.assigned > 0 or _clock < r.civ_next_try:
		return false
	var v: Vehicle = _civilian_for(r.node_id)
	if v == null or v.state_id != Types.VehicleState.IDLE or v.fading:
		return false
	var best_hub := -1
	var best_p: PathResult = null
	for hid in _hubs:
		if _hubs[hid].stock[r.supply] <= 0:
			continue
		var p: PathResult = find_path(r.node_id, hid, v.type, v)
		if p.found and (best_p == null or p.cost < best_p.cost):
			best_hub = hid
			best_p = p
	if best_p == null:
		r.civ_next_try = _clock + DISPATCH_INTERVAL
		return false
	_assign_civilian(r, v, best_hub, best_p)
	return true

func _assign_civilian(r: SosRequest, v: Vehicle, hub_id: int, p: PathResult) -> void:
	r.assigned += 1
	r.vehicle_ids.append(v.id)
	r.vehicle_id = v.id
	r.state = Types.SosState.ASSIGNED  # SOS xe dân luôn cần đúng 1 phần
	v.request = r
	v.hub_id = hub_id
	v.dest = hub_id
	v.path = p
	v.path_index = 0
	v.current_node = r.node_id
	v.position = stop_pos(r.node_id)
	var h: Hub = _hubs[hub_id]
	h.stock[r.supply] -= 1
	EventBus.stock_changed.emit(h.id, r.supply, h.stock[r.supply])
	v.change_state(CivToHubState.new(), Types.VehicleState.EN_ROUTE)
	EventBus.sos_assigned.emit(r.id, v.id)

# Xe dân của nhà home_id: tạo ở lần đầu nhà có SOS (70% xe máy, 30% ô tô), sau đó dùng lại.
func _civilian_for(home_id: int) -> Vehicle:
	var cur = _civilians.get(home_id)
	if cur != null and is_instance_valid(cur):
		return cur
	if not _civilian_type.has(home_id):
		_civilian_type[home_id] = Types.VehicleType.MOTORBIKE if randf() < Config.MOTORBIKE_RATIO else Types.VehicleType.CAR
	var v := VehicleFactory.create(_next_vehicle_id, _civilian_type[home_id], -1)
	_next_vehicle_id += 1
	v.is_civilian = true
	v.home_id = home_id
	v.current_node = home_id
	v.position = stop_pos(home_id)
	_vehicles[v.id] = v
	_civilians[home_id] = v
	var layer := get_tree().get_first_node_in_group('vehicle_layer')
	if layer == null:
		push_warning('Không thấy nhóm vehicle_layer, gắn xe vào RescueManager')
		layer = self
	layer.add_child(v)  # không phát vehicle_added: xe dân không thuộc đội xe của người chơi
	return v

# ===== Xe chở 2 hàng (multi-drop) =====
# Tải trọng hiện tại của xe cứu hộ. Đọc từ GameManager (D thêm truck_capacity, boat_capacity); chưa có thì dùng mặc định,
# nên mã này chạy được trước cả khi D merge.
func capacity_of(type: int) -> int:
	if type != Types.VehicleType.TRUCK and type != Types.VehicleType.BOAT:
		return 1
	var key := 'truck_capacity' if type == Types.VehicleType.TRUCK else 'boat_capacity'
	var value = GameManager.get(key)
	var fallback := Config.TRUCK_CAPACITY_DEFAULT if type == Types.VehicleType.TRUCK else Config.BOAT_CAPACITY_DEFAULT
	return maxi(int(value) if value != null else fallback, 1)

# Xe v vừa nhận SOS first. Nếu xe chở được ≥ 2 thì thêm một SOS thứ hai ở gần first (trong MULTIDROP_RADIUS), ưu tiên SOS
# sắp hết hạn nhất. Chỉ lấy SOS xe dân không phục vụ được (đã bị cô lập), để không cướp việc của xe dân.
func _try_add_second(v: Vehicle, first: SosRequest) -> void:
	if v.state_id != Types.VehicleState.EN_ROUTE or capacity_of(v.type) < 2 or not v.queue.is_empty():
		return
	if not _hubs.has(v.hub_id):
		return
	var h: Hub = _hubs[v.hub_id]
	var fnode: MapNode = g().get_map_node(first.node_id)
	if fnode == null:
		return
	var best: SosRequest = null
	for r in get_pending_requests():
		if r == first or r.units != 1 or r.missing() <= 0 or h.stock[r.supply] <= 0:
			continue
		if not (r.heavy_only or r.civ_next_try > 0.0):
			continue  # nhà này xe dân còn lo được
		var n: MapNode = g().get_map_node(r.node_id)
		if n == null or n.pos.distance_to(fnode.pos) > Config.MULTIDROP_RADIUS:
			continue
		if best != null and r.time_left >= best.time_left:
			continue
		if find_path(first.node_id, r.node_id, v.type).found:  # xe phải đi được từ nhà đầu sang nhà này
			best = r
	if best == null:
		return
	best.assigned += 1
	best.vehicle_ids.append(v.id)
	best.vehicle_id = v.id
	best.state = Types.SosState.ASSIGNED
	v.queue.append(best)
	h.stock[best.supply] -= 1
	EventBus.stock_changed.emit(h.id, best.supply, h.stock[best.supply])
	EventBus.sos_assigned.emit(best.id, v.id)

func refund(hub_id: int, supply: int) -> void:
	if not _hubs.has(hub_id):
		return
	var h: Hub = _hubs[hub_id]
	h.stock[supply] = mini(h.stock[supply] + 1, Config.STOCK_MAX)
	EventBus.stock_changed.emit(hub_id, supply, h.stock[supply])

# Một xe giao xong 1 phần. Đủ số phần thì SOS được cứu (E cộng điểm, C chỉ phát tín hiệu); điểm nhân theo số phần.
func complete_request(req: SosRequest, v: Vehicle = null) -> void:
	if req == null:
		return
	req.assigned = maxi(0, req.assigned - 1)
	req.delivered += 1
	if v != null:
		req.vehicle_ids.erase(v.id)
	if req.delivered < req.units:
		return  # chưa đủ phần: chờ các xe còn lại
	var pts: float = Config.POINTS[req.supply] * req.units
	if req.time_left > req.time_total * BONUS_TIME_RATIO:
		pts *= Config.BONUS_RATIO
	req.state = Types.SosState.RESCUED
	_requests.erase(req.id)
	_last_rescued[req.node_id] = _clock
	EventBus.sos_rescued.emit(req.id, roundi(pts))

# ===== Xe =====
func _make_vehicle(type: int, hub_id: int) -> int:
	var v := VehicleFactory.create(_next_vehicle_id, type, hub_id)
	_next_vehicle_id += 1
	_vehicles[v.id] = v
	reserve_slot(v)
	if v.slot >= 0:
		v.position = slot_pos(v)
		v.heading = slot_heading(hub_id, type, v.slot)
	var layer := get_tree().get_first_node_in_group('vehicle_layer')
	if layer == null:
		push_warning('Không thấy nhóm vehicle_layer, gắn xe vào RescueManager')
		layer = self
	layer.add_child(v)
	EventBus.vehicle_added.emit(v.id, type, hub_id)
	_dirty = true
	return v.id

# ===== Hàm công khai (hợp đồng mục 2.8) =====
func add_vehicle(type: int) -> int:
	if _hubs.is_empty():
		return -1
	return _make_vehicle(type, _hub_for(type))


# Xe tải về kho cao nhất vì đường quanh đó khô lâu; ca-nô về kho thấp nhất vì đường quanh đó ngập sớm.
# Bản đồ có sông cho ca-nô: ca-nô chỉ về kho có bến (sát sông), chọn kho thấp nhất trong số đó.
# Bản đồ có cổng (mỗi kho có bãi đỗ): xe tải chia đều các kho, xe mới về kho đang ít xe tải nhất (bằng nhau thì kho cao hơn).
func _hub_for(type: int) -> int:
	if type == Types.VehicleType.TRUCK and _uses_gates():
		var pick := -1
		for hid in _hubs:
			if pick == -1:
				pick = hid
				continue
			var a := get_home_count(hid, type)
			var b := get_home_count(pick, type)
			if a < b or (a == b and g().get_map_node(hid).elevation > g().get_map_node(pick).elevation):
				pick = hid
		return pick
	var docked := {}
	if type == Types.VehicleType.BOAT and g().has_method('has_dock'):
		for hid in _hubs:
			if g().has_dock(hid):
				docked[hid] = true
	var best := -1
	for hid in _hubs:
		if not docked.is_empty() and not docked.has(hid):
			continue
		if best == -1:
			best = hid
			continue
		var e: float = g().get_map_node(hid).elevation
		var top: float = g().get_map_node(best).elevation
		if (type == Types.VehicleType.TRUCK and e > top) or (type == Types.VehicleType.BOAT and e < top):
			best = hid
	return best

func prioritize(req_id: int) -> bool:
	if not _requests.has(req_id):
		return false
	var r: SosRequest = _requests[req_id]
	if r.prioritized:
		r.prioritized = false  # gọi lại thì bỏ ưu tiên
		return false
	var count := 0
	for x in _requests.values():
		if x.prioritized:
			count += 1
	if count >= Config.MAX_PRIORITIZED:
		return false
	r.prioritized = true
	_dirty = true
	return true

# Routeability for SOS eligibility. Busy fleet vehicles count; stock, deadlines and
# assignment remain dispatch concerns. This query never creates vehicles or paths for them.
func has_rescue_route(node_id: int) -> bool:
	if GraphManager.get_map_node(node_id) == null:
		return false
	var checked := {}
	for vehicle in _vehicles.values():
		if not is_instance_valid(vehicle) or vehicle.is_fading():
			continue
		if vehicle.is_civilian:
			if vehicle.home_id != node_id:
				continue
			for hub_id in _hubs:
				if GraphManager.find_path(node_id, hub_id, vehicle.type).found and GraphManager.find_path(hub_id, node_id, vehicle.type).found:
					return true
			continue
		var origin := Vector2i(vehicle.hub_id, vehicle.type)
		if origin.x == node_id or checked.has(origin):
			continue
		checked[origin] = true
		if GraphManager.find_path(origin.x, node_id, origin.y).found:
			return true
	return false


# Số phần hàng SOS còn thiếu (chưa giao), 0 nếu không còn SOS.
func get_units_left(req_id: int) -> int:
	if not _requests.has(req_id):
		return 0
	var r: SosRequest = _requests[req_id]
	return r.units - r.delivered

func get_pending_requests() -> Array:
	var result := []
	for r in _requests.values():
		if r.state == Types.SosState.PENDING:
			result.append(r)
	return result

func get_vehicle_ids() -> Array[int]:
	var ids: Array[int] = []
	for k in _vehicles:
		if is_instance_valid(_vehicles[k]) and not _vehicles[k].is_civilian:
			ids.append(k)
	return ids

func get_vehicles() -> Array:
	return _vehicles.values()

func get_vehicle_position(vehicle_id: int) -> Vector2:  # ngoài hợp đồng, cho D nếu cần
	if _vehicles.has(vehicle_id):
		return _vehicles[vehicle_id].position
	return Vector2.ZERO

func get_stock(hub_id: int, supply: int) -> int:
	if not _hubs.has(hub_id):
		return 0
	return _hubs[hub_id].stock[supply]
