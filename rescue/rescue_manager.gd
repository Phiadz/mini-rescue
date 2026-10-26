extends Node
# RescueManager (autoload). KHÔNG đặt class_name. Chủ sở hữu: C.
# Bố cục: hằng số -> SOS -> HUB -> SOS FACTORY -> VEHICLE -> STATE -> VEHICLE FACTORY -> MANAGER

# TODO: xin A chuyển các hằng số này sang autoload/config.gd rồi đổi thành Config.X
const HOSPITAL_ID := 5               # node Bệnh viện luôn ra SOS Y tế
const DISPATCH_INTERVAL := 0.5       # giây giữa hai lượt điều phối
const MIN_EDGE_SPEED_FACTOR := 0.5   # tốc độ tối thiểu khi đi hết cạnh
const STRANDED_RETRY := 0.5          # giây giữa hai lần xe kẹt thử tìm đường
const BONUS_TIME_RATIO := 0.5        # còn quá nửa thời gian thì được thưởng
const ARRIVE_EPSILON := 0.5          # sai số khi tới node (px)

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
	var state: int = Types.SosState.PENDING
	var vehicle_id := -1

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
		req.time_left = req.time_total
		return req

# ===== VEHICLE =====
class Vehicle extends Node2D:
	var id: int
	var type: int
	var hub_id: int
	var request: SosRequest
	var path: PathResult
	var path_index := 0
	var current_node := -1   # node xe vừa rời hoặc đang đứng
	var dest := -1           # node đích của nhiệm vụ
	var state_id: int = Types.VehicleState.IDLE
	var _state: VehicleStateBase

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
		EventBus.vehicle_state_changed.emit(id, new_id)

	func _process(delta: float) -> void:
		if _state:
			_state.update(self, delta)

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
		var p: PathResult = RescueManager.find_path(current_node, to_node, type)
		if p.found:
			path = p
			path_index = 0
			return true
		return false

	# Đi dọc đường. Trả true khi xe đang đứng tại một node (cần ra quyết định).
	# Xe đã vào một cạnh thì đi hết cạnh đó, tốc độ tối thiểu MIN_EDGE_SPEED_FACTOR.
	func advance(delta: float) -> bool:
		if path == null or path_index >= path.edge_ids.size():
			return true
		var e: Edge = RescueManager.g().get_edge(path.edge_ids[path_index])
		if e == null:
			_cut()
			return true
		var next_id: int = path.node_ids[path_index + 1]
		var target: Vector2 = RescueManager.g().get_map_node(next_id).pos
		var f := maxf(e.speed_factor(type), MIN_EDGE_SPEED_FACTOR)
		position = position.move_toward(target, Config.base_speed(type) * f * delta)
		if position.distance_to(target) < ARRIVE_EPSILON:
			position = target
			current_node = next_id
			path_index += 1
			return true
		return false

	# Cạnh đang đi bị xóa: dịch về node vừa rời, đường rỗng để state tính lại.
	func _cut() -> void:
		if path != null and path_index < path.node_ids.size():
			current_node = path.node_ids[path_index]
			position = RescueManager.g().get_map_node(current_node).pos
		path = PathResult.new()
		path_index = 0

	func on_edge_removed(edge_id: int) -> void:
		if path == null or path_index >= path.edge_ids.size():
			return
		if path.edge_ids[path_index] == edge_id:
			_cut()

	# Bỏ nhiệm vụ: SOS về PENDING, hoàn hàng.
	func release_request() -> void:
		if request == null:
			return
		request.state = Types.SosState.PENDING
		request.vehicle_id = -1
		RescueManager.refund(hub_id, request.supply)
		request = null
		RescueManager.mark_dirty()

	# SOS đã hết hạn (Manager đã phát sos_failed): hoàn hàng, về kho.
	func on_request_failed() -> void:
		if request == null:
			return
		RescueManager.refund(hub_id, request.supply)
		request = null
		go_home()

	func go_home() -> void:
		if plan(hub_id):
			change_state(ReturningState.new(), Types.VehicleState.RETURNING)
		else:
			change_state(StrandedState.new(), Types.VehicleState.STRANDED)

	func park() -> void:
		position = RescueManager.g().get_map_node(hub_id).pos
		current_node = hub_id
		path = null
		change_state(IdleState.new(), Types.VehicleState.IDLE)
		RescueManager.mark_dirty()

	func _draw() -> void:
		var c := Color('#FFD700') if type == Types.VehicleType.TRUCK else Color('#FFFFFF')
		if type == Types.VehicleType.TRUCK:
			draw_rect(Rect2(-7, -7, 14, 14), c)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(8, 7), Vector2(-8, 7)]), c)
		if state_id == Types.VehicleState.STRANDED:
			draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, Color('#FF4500'), 2.0)

# ===== VEHICLE STATE (State pattern) =====
class VehicleStateBase extends RefCounted:
	func enter(_v: Vehicle) -> void: pass
	func update(_v: Vehicle, _delta: float) -> void: pass
	func exit(_v: Vehicle) -> void: pass
	func retry(_v: Vehicle) -> void: pass

class IdleState extends VehicleStateBase:
	pass  # đứng ở kho, chờ điều phối

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
			RescueManager.complete_request(req)
			v.go_home()

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

# ===== VEHICLE FACTORY =====
class VehicleFactory extends RefCounted:
	static func create(vehicle_id: int, vehicle_type: int, hub: int) -> Vehicle:
		var v := Vehicle.new()
		v.id = vehicle_id
		v.type = vehicle_type
		v.hub_id = hub
		v.current_node = hub
		var n: MapNode = RescueManager.g().get_map_node(hub)
		if n != null:
			v.position = n.pos
		v.set_initial_state()
		return v

# ===== MANAGER =====
var path_provider: Callable = Callable()  # tùy chọn: hàm tìm đường giả cho scene thử
var _requests := {}      # req_id -> SosRequest (SOS còn hiệu lực)
var _hubs := {}          # hub_id -> Hub
var _vehicles := {}      # vehicle_id -> Vehicle
var _next_req_id := 0
var _next_vehicle_id := 0
var _wave := 0
var _spawning := false
var _spawn_timer := 0.0
var _dispatch_timer := 0.0
var _dirty := false
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
		v.queue_free()
	_vehicles.clear()
	_requests.clear()
	_hubs.clear()
	_last_rescued.clear()
	_next_req_id = 0
	_next_vehicle_id = 0
	_wave = 0
	_spawning = false
	_spawn_timer = 0.0
	_dispatch_timer = 0.0
	_dirty = false
	_clock = 0.0
	var hub_ids := []
	for id in g().get_node_ids():
		var n: MapNode = g().get_map_node(id)
		if n != null and n.kind == Types.NodeKind.HUB:
			hub_ids.append(id)
			var h := Hub.new(id)
			_hubs[id] = h
			for s in h.stock:
				EventBus.stock_changed.emit(id, s, h.stock[s])
	hub_ids.sort()
	# Xe khởi đầu: kho đầu (Bắc) 1 xe tải + 1 ca-nô, kho sau (Nam) 1 xe tải
	if hub_ids.size() >= 1:
		_make_vehicle(Types.VehicleType.TRUCK, hub_ids[0])
		_make_vehicle(Types.VehicleType.BOAT, hub_ids[0])
	if hub_ids.size() >= 2:
		_make_vehicle(Types.VehicleType.TRUCK, hub_ids[1])

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
		v.on_edge_removed(edge_id)
	_on_graph_changed()

func _on_edge_state_changed(_edge_id: int, _state: int) -> void:
	_on_graph_changed()

func _on_graph_changed() -> void:
	_dirty = true
	for v in _vehicles.values():
		v.retry_if_stranded()

func mark_dirty() -> void:
	_dirty = true

func find_path(from_id: int, to_id: int, vehicle_type: int) -> PathResult:
	if path_provider.is_valid():
		return path_provider.call(from_id, to_id, vehicle_type)
	return g().find_path(from_id, to_id, vehicle_type)

func _process(delta: float) -> void:
	_clock += delta
	for h in _hubs.values():
		for s in h.tick(delta):
			EventBus.stock_changed.emit(h.id, s, h.stock[s])
	_tick_requests(delta)
	if _spawning:
		_tick_spawn(delta)
	_dispatch_timer += delta
	if _dirty or _dispatch_timer >= DISPATCH_INTERVAL:
		_dirty = false
		_dispatch_timer = 0.0
		_dispatch()

func _tick_requests(delta: float) -> void:
	for rid in _requests.keys():
		var r: SosRequest = _requests[rid]
		r.time_left -= delta
		if r.time_left <= 0.0:
			r.state = Types.SosState.FAILED
			_requests.erase(rid)
			if _vehicles.has(r.vehicle_id):
				_vehicles[r.vehicle_id].on_request_failed()
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

func _free_nodes() -> Array:
	var busy := []
	for r in _requests.values():
		busy.append(r.node_id)
	var result := []
	for id in g().get_node_ids():
		var n: MapNode = g().get_map_node(id)
		if n == null or n.kind != Types.NodeKind.DISTRICT or id in busy:
			continue
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
	for r in pending:
		var best_v: Vehicle = null
		var best_p: PathResult = null
		for v in _vehicles.values():
			if v.state_id != Types.VehicleState.IDLE:
				continue
			if not _hubs.has(v.hub_id) or _hubs[v.hub_id].stock[r.supply] <= 0:
				continue
			var p: PathResult = find_path(v.hub_id, r.node_id, v.type)
			if p.found and (best_v == null or p.cost < best_p.cost):
				best_v = v
				best_p = p
		if best_v != null:
			_assign(r, best_v, best_p)

func _assign(r: SosRequest, v: Vehicle, p: PathResult) -> void:
	r.state = Types.SosState.ASSIGNED  # đổi trước để không xe nào nhận trùng
	r.vehicle_id = v.id
	v.request = r
	v.dest = r.node_id
	v.path = p
	v.path_index = 0
	v.current_node = v.hub_id
	var h: Hub = _hubs[v.hub_id]
	h.stock[r.supply] -= 1
	EventBus.stock_changed.emit(h.id, r.supply, h.stock[r.supply])
	v.change_state(EnRouteState.new(), Types.VehicleState.EN_ROUTE)
	EventBus.sos_assigned.emit(r.id, v.id)

func refund(hub_id: int, supply: int) -> void:
	if not _hubs.has(hub_id):
		return
	var h: Hub = _hubs[hub_id]
	h.stock[supply] = mini(h.stock[supply] + 1, Config.STOCK_MAX)
	EventBus.stock_changed.emit(hub_id, supply, h.stock[supply])

# Xe giao xong. E cộng điểm, C chỉ phát tín hiệu.
func complete_request(req: SosRequest) -> void:
	if req == null:
		return
	var pts: float = Config.POINTS[req.supply]
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
	var best_hub := -1
	var best_count := 1 << 30
	for hid in _hubs:
		var c := 0
		for v in _vehicles.values():
			if v.hub_id == hid:
				c += 1
		if c < best_count:
			best_count = c
			best_hub = hid
	return _make_vehicle(type, best_hub)

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

func get_pending_requests() -> Array:
	var result := []
	for r in _requests.values():
		if r.state == Types.SosState.PENDING:
			result.append(r)
	return result

func get_vehicle_ids() -> Array[int]:
	var ids: Array[int] = []
	for k in _vehicles:
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
