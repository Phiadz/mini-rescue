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
const BOAT_ESCAPE_FACTOR := 0.1      # ca-nô mắc cạn (nước rút) tìm đường về được bò qua chỗ khô; chỗ khô tính đắt gấp 10
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
# Nút giao tự động (góp ý của Lộc): ngã ba đường thành vòng xoay, ngã tư đường trở lên có đèn giao thông.
const JUNCTION_NONE := 0             # không phải nút giao
const JUNCTION_YIELD := 1            # nhường theo khoảng cách: điểm có từ 3 cạnh, chữ T trước cổng nhà
const JUNCTION_RING := 2             # ô thuộc vòng xoay người chơi vẽ (2×2, 3×3): xe từ ngoài vào nhường xe trên vòng
const JUNCTION_LIGHT := 3            # ngã tư đường trở lên: đèn chia lượt theo trục ngang, dọc
const LIGHT_PHASE := 3.0             # giây mỗi pha đèn xanh của một trục
const ROUNDABOUT_SLOW := 0.8         # hệ số dưới mức này mới tính là kẹt (bật đèn phanh)
const RING_YIELD := 30.0             # xe trên vòng cách chỗ nhập dưới mức này (px) thì xe ngoài vào phải nhường
const UNIT_EXTRA_SECONDS := Config.DELIVERY_TIME  # SOS cần nhiều phần: mỗi phần thêm cộng một lần dỡ hàng (xe xếp hàng dỡ lần lượt)
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
		var w: Dictionary = Config.WAVES[wave_index]
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
	const MOTORBIKE_SIZE := Vector2(14, 9)  # theo spec: chiếm nửa làn
	const CAR_SIZE := Vector2(18, 11)       # chiếm trọn một làn
	const ICON_SIZE := Vector2(21, 14)  # giữ tỉ lệ 96 × 64 của file SVG, vừa một làn của đường rộng 22 px
	const PARK_OFFSET := 18.0  # lúc đỗ ở kho: xe tải lệch trái, ca-nô lệch phải để không chồng nhau
	const LANE_OFFSET := 5.5   # xe chạy lệch sang phải hướng đi, mỗi chiều một làn (đường rộng 22 px)
	const LANE_SWITCH := 0.15  # giây để đổi làn ở chỗ rẽ

	var id: int
	var type: int
	var hub_id: int
	var request: SosRequest
	var path: PathResult
	var path_index := 0
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

	func set_initial_state() -> void:  # không phát tín hiệu
		_state = IdleState.new()
		state_id = Types.VehicleState.IDLE

	func change_state(new_state: VehicleStateBase, new_id: int) -> void:
		if _state:
			_state.exit(self)
		_state = new_state
		state_id = new_id
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

	# Xe đang ở trong kho (đỗ, hoặc chờ ra cổng) thì ẩn, nên xe cùng kho không chồng lên nhau.
	func _update_visible() -> void:
		if is_civilian:
			visible = fading or (state_id != Types.VehicleState.IDLE and state_id != Types.VehicleState.DELIVERING)
			return  # đỗ ở nhà hoặc đang nhận hàng trong kho thì ẩn
		var hidden := state_id == Types.VehicleState.IDLE and slot < 0 and waypoints.is_empty()  # bãi đầy: ở trong kho
		if not hidden:
			var h: MapNode = RescueManager.g().get_map_node(hub_id)
			hidden = h != null and position.distance_to(h.pos) < HUB_HIDE_RADIUS
		visible = not hidden

	func _update_lane(delta: float) -> void:
		var want := Vector2.ZERO
		if state_id != Types.VehicleState.IDLE and not RescueManager.in_lot(self):  # trong bãi: đi giữa lối, không lệch làn
			want = heading.rotated(PI / 2.0) * LANE_OFFSET
		if _lane != want:
			_lane = _lane.move_toward(want, LANE_OFFSET * 2.0 / LANE_SWITCH * delta)
			queue_redraw()

	func lane_offset() -> Vector2:
		return _lane

	# Xe đang chạy trên đường (không đứng ở kho, ở khu dân cư hay kẹt vì mất đường).
	func is_moving() -> bool:
		var running := state_id == Types.VehicleState.EN_ROUTE or state_id == Types.VehicleState.RETURNING
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

	# Ca-nô mắc cạn (nước rút dưới chân): tìm đường về to_node được bò qua chỗ khô (ít chỗ khô nhất), không đứng kẹt trên đất.
	func plan_escape(to_node: int) -> bool:
		var p: PathResult = RescueManager.g().find_path(current_node, to_node, type, {}, BOAT_ESCAPE_FACTOR)
		if not p.found:
			return false
		path = RescueManager.g().smooth_boat_path(p)
		path_index = 0
		return true

	# Đi dọc đường. Trả true khi xe đứng ở cuối đoạn (cần ra quyết định).
	# Xe đã vào một đoạn thì đi hết đoạn đó, tốc độ tối thiểu MIN_EDGE_SPEED_FACTOR.
	func advance(delta: float) -> bool:
		if path == null or path_index >= path.edge_ids.size():
			return true
		if not waypoints.is_empty():
			maneuver(delta)  # vừa rời chỗ đỗ: lùi ra lối đi trước
			return false
		var e: Edge = RescueManager.g().get_edge(path.edge_ids[path_index])
		if e == null:
			_cut()
			return true
		var next_id: int = path.node_ids[path_index + 1]
		var target: Vector2 = RescueManager.arrive_pos(self, next_id)  # điểm có cổng: dừng ở lối vào; về kho: tới lối đi cạnh chỗ đã giữ
		var f := e.speed_factor(type)
		if f <= 0.0:
			f = MIN_EDGE_SPEED_FACTOR  # cạnh vừa thành không đi được: đi nốt với tốc độ tối thiểu
		if position.distance_to(target) > ARRIVE_EPSILON:
			heading = position.direction_to(target)
			queue_redraw()
		var jam := settle_jam(RescueManager.congestion_factor(self), delta)
		position = position.move_toward(target, Config.base_speed(type) * f * jam * delta)
		if position.distance_to(target) < ARRIVE_EPSILON:
			position = target
			current_node = next_id
			path_index += 1
			return not _next_edge_same_segment(e)
		return false

	# Đi chậm tới từng điểm trong waypoints (lùi ra lối đi, hoặc đỗ vào chỗ). Trả true khi đã hết điểm.
	func maneuver(delta: float) -> bool:
		while not waypoints.is_empty():
			var to: Vector2 = waypoints[0]
			if position.distance_to(to) < ARRIVE_EPSILON:
				position = to
				waypoints.pop_front()
				continue
			heading = position.direction_to(to)
			position = position.move_toward(to, Config.base_speed(type) * MANEUVER_SPEED * delta)
			queue_redraw()
			return false
		return true

	func _next_edge_same_segment(e: Edge) -> bool:
		if path_index >= path.edge_ids.size():
			return false
		var after: Edge = RescueManager.g().get_edge(path.edge_ids[path_index])
		return after != null and after.segment == e.segment

	# Cạnh đang đi bị xóa: dịch về node vừa rời, đường rỗng để state tính lại.
	# GraphManager xóa cạnh trước rồi mới xóa ô, nên lúc này node vẫn còn.
	func _cut() -> void:
		if path != null and path_index < path.node_ids.size():
			current_node = path.node_ids[path_index]
			position = RescueManager.stop_pos(current_node)
		path = PathResult.new()
		path_index = 0

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
		if slot >= 0:
			waypoints.append(RescueManager.slot_pos(self))  # từ lối đi vào đúng chỗ đã giữ
		else:
			position = RescueManager.stop_pos(hub_id)
			heading = Vector2.RIGHT
		change_state(IdleState.new(), Types.VehicleState.IDLE)
		RescueManager.mark_dirty()

		func _draw() -> void:
		var offset := _lane
		if state_id == Types.VehicleState.IDLE and slot < 0 and not is_civilian:
			offset.x = -PARK_OFFSET if type == Types.VehicleType.TRUCK else PARK_OFFSET
		var icon: Texture2D = TRUCK_ICON
		var isz := ICON_SIZE
		match type:
			Types.VehicleType.BOAT:
				icon = BOAT_ICON
			Types.VehicleType.MOTORBIKE:
				icon = MOTORBIKE_ICON
				isz = MOTORBIKE_SIZE
			Types.VehicleType.CAR:
				icon = CAR_ICON
				isz = CAR_SIZE
		var left := heading.x < 0.0  # lật hình để xe không chổng ngược khi đi sang trái
		var sc: float = RescueManager.draw_scale(self)
		draw_set_transform(offset, heading.angle() + (PI if left else 0.0), Vector2(-sc if left else sc, sc))
		draw_texture_rect(icon, Rect2(-isz / 2.0, isz), false)
		draw_set_transform(Vector2.ZERO)
		if state_id == Types.VehicleState.STRANDED:
			draw_arc(offset, isz.x / 2.0 + 4.0, 0.0, TAU, 24, Color('#FF4500'), 2.0)
		if jammed and state_id != Types.VehicleState.IDLE:  # đèn phanh: hai chấm đỏ ở đuôi xe
			var rear := offset - heading * (isz.x / 2.0 - 1.0)
			var side := heading.rotated(PI / 2.0) * 4.0
			draw_circle(rear + side, 2.4, Color('#ff3b30'))
			draw_circle(rear - side, 2.4, Color('#ff3b30'))

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
		if v.plan(v.hub_id) or (v.type == Types.VehicleType.BOAT and v.plan_escape(v.hub_id)):
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

# ===== MANAGER =====
var path_provider: Callable = Callable()  # tùy chọn: hàm tìm đường giả cho scene thử
var _requests := {}      # req_id -> SosRequest (SOS còn hiệu lực)
var _hubs := {}          # hub_id -> Hub
var _vehicles := {}      # vehicle_id -> Vehicle
var _civilians := {}       # nhà (node id) -> xe dân của nhà đó (tạo khi nhà có SOS đầu tiên)
var _civilian_type := {}   # nhà -> loại xe dân (xe máy hoặc ô tô), giữ nguyên trong ván
var _fresh: Array = []     # xe cứu hộ vừa nhận SOS trong lượt điều phối này (để thử gom thêm SOS thứ hai)
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
		if v.is_moving() or v.state_id == Types.VehicleState.DELIVERING:
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


# Mỗi xe đang chạy làm 3 cạnh sắp đi của nó đắt thêm CONGESTION_PATH_COST giây.
func congestion_penalty(exclude: Vehicle = null) -> Dictionary:
	var pen := {}
	for v in _vehicles.values():
		if v == exclude or not v.is_moving():
			continue
		for k in range(v.path_index, mini(v.path_index + 3, v.path.edge_ids.size())):
			var eid: int = v.path.edge_ids[k]
			pen[eid] = float(pen.get(eid, 0.0)) + CONGESTION_PATH_COST
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
	var road_deg := 0
	for eid in edges:
		var e: Edge = g().get_edge(eid)
		var other: MapNode = g().get_map_node(e.other_end(node_id)) if e != null else null
		if other != null and other.kind == Types.NodeKind.ROAD:
			road_deg += 1
	if road_deg >= 4:
		return JUNCTION_LIGHT
	return JUNCTION_YIELD if edges.size() >= 3 else JUNCTION_NONE  # ngã ba một ô: nhường theo khoảng cách


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
func congestion_factor(v: Vehicle, others: Array = []) -> float:
	v.at_red = false
	if not v.is_moving():
		return 1.0
	var list: Array = others if not others.is_empty() else _nearby(v.position)
	var f := 1.0
	var nxt := v.next_node()
	var kind := junction_kind(nxt) if nxt != -1 else JUNCTION_NONE
	var jpos := Vector2.ZERO
	var dv := INF
	var approaching := false
	if kind != JUNCTION_NONE:
		jpos = g().get_map_node(nxt).pos
		dv = v.position.distance_to(jpos)
		approaching = dv > JUNCTION_RADIUS and dv < JUNCTION_APPROACH
	var ring: int = g().ring_of(nxt) if kind == JUNCTION_RING else -1
	var entering_ring: bool = ring != -1 and not g().is_ring_edge(v.path.edge_ids[v.path_index])  # từ ngoài nhập vào vòng
	if approaching and kind == JUNCTION_LIGHT and not light_green(nxt, v.heading):
		v.at_red = true
		return 0.0
	for u in list:
		if u == v:
			continue
		# Dỡ hàng lần lượt: xe đang dỡ hàng ở một SOS chặn các xe khác tới đúng SOS đó (xếp hàng chờ).
		# Xe chỉ đi ngang khu đó không bị chặn.
		if u.state_id == Types.VehicleState.DELIVERING and v.request != null and u.dest == v.dest and nxt == u.current_node:
			var gap: float = v.position.distance_to(u.position)
			if gap < FOLLOW_GAP:
				return 0.0
			continue
		if not u.is_moving():
			continue
		var rel: Vector2 = u.position - v.position
		var along := rel.dot(v.heading)
		var ahead: bool = along > 0.0 or (rel.length() < 1.0 and u.id < v.id)  # cùng chỗ (vừa rời kho): xe mã nhỏ đi trước
		if ahead and u.heading.dot(v.heading) > 0.7 and absf(rel.cross(v.heading)) < SAME_LANE:
			if along < STOP_GAP:
				return 0.0
			if along < FOLLOW_GAP:
				f = minf(f, FOLLOW_SLOW)
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
					f = 0.0  # xe trên vòng được đi trước
			JUNCTION_LIGHT:
				if inside and cross:
					f = 0.0
	return f

func _process(delta: float) -> void:
	_clock += delta
	if _retry_stranded:
		_retry_all_stranded()
	_rebuild_grid()
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
	var w: Dictionary = Config.WAVES[_wave]
	_spawn_timer += delta
	if _spawn_timer < w.sos_interval:
		return
	_spawn_timer = 0.0
	if _requests.size() >= w.sos_max:
		return
	var req := SosFactory.create(_next_req_id, _wave, _free_nodes())
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
	return n.pos + Vector2(n.gate) * (g().point_radius(node_id) + PARK_GAP)

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
	var nodes: Array = g().get_dock_nodes(hub_id).filter(func(id: int) -> bool: return not g().is_flood_node(id))  # chỉ trên sông: vùng ngập thêm dần
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
	var last: bool = v.path != null and v.path_index == v.path.edge_ids.size() - 1
	if node_id == v.hub_id and v.slot >= 0 and last:
		return slot_pos(v)
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

# Ca-nô trong kho (bến đầy) nhận nhiệm vụ: ra thẳng nút nước nối bến đầu tiên trên đường, không chạy qua đất từ tâm kho.
func _boat_depart(v: Vehicle) -> void:
	if v.type != Types.VehicleType.BOAT or v.slot >= 0 or v.path == null or v.path.node_ids.size() < 2:
		return
	var w: MapNode = g().get_map_node(v.path.node_ids[1])
	if w != null and w.kind == Types.NodeKind.WATER:
		v.position = w.pos

func _uses_gates() -> bool:
	return g().has_method('uses_gates') and g().uses_gates()

# Mỗi house_interval giây của đợt hiện tại, một nhà mới mọc quanh một khu đã mở.
func _tick_houses(delta: float) -> void:
	if not _uses_gates():
		return
	_house_timer += delta
	if _house_timer < float(Config.WAVES[_wave].get('house_interval', INF)):
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
	var r := Config.HOUSE_RADIUS
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
	# Đồ thị thật: mỗi (kho, loại xe) chỉ tính một cây đường ngắn nhất cho cả lượt (lúc cần tới), rồi lấy
	# đường tới từng SOS từ cây đó. Chi phí chỗ đông lấy lúc đầu lượt. Scene thử (đường giả, đồ thị giả) tính từng cặp như cũ.
	var use_tree: bool = not path_provider.is_valid() and graph == null
	var trees := {}
	var pen := {}
	for r in pending:
		# SOS lớn cần nhiều xe: giao thêm xe rảnh cho tới khi đủ số phần. Xe sau tính đường có cộng
		# chi phí chỗ đông (congestion_penalty) nên có thể tự chọn đường vòng.
		while r.missing() > 0:
			var best_v: Vehicle = null
			var best_p: PathResult = null
			var tried := {}  # xe rảnh cùng kho, cùng loại đứng cùng chỗ nên chung một đường: chỉ tính một lần
			for v in _vehicles.values():
				if v.state_id != Types.VehicleState.IDLE:
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
	_boat_depart(v)
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

# Số phần hàng SOS còn thiếu (chưa giao), 0 nếu không còn SOS. Bong bóng SOS của D hiện số này.
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

func get_vehicle_position(vehicle_id: int) -> Vector2:  # ngoài hợp đồng, cho D nếu cần
	if _vehicles.has(vehicle_id):
		return _vehicles[vehicle_id].position
	return Vector2.ZERO

func get_stock(hub_id: int, supply: int) -> int:
	if not _hubs.has(hub_id):
		return 0
	return _hubs[hub_id].stock[supply]
