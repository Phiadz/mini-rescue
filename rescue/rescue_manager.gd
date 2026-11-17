extends Node
# RescueManager (autoload). KHÔNG đặt class_name. Chủ sở hữu: C.
# Bố cục: hằng số -> SOS -> HUB -> SOS FACTORY -> VEHICLE -> STATE -> VEHICLE FACTORY -> MANAGER

# TODO: xin A chuyển các hằng số này sang autoload/config.gd rồi đổi thành Config.X
const HOSPITAL_ID := 5               # node Bệnh viện luôn ra SOS Y tế
const START_TRUCKS := 100             # số xe tải lúc đầu ván (ở kho cao nhất)
const START_BOATS := 100              # số ca-nô lúc đầu ván (ở kho thấp nhất)
const DISPATCH_INTERVAL := 0.5       # giây giữa hai lượt điều phối
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
const UNIT_EXTRA_SECONDS := 2.0      # SOS cần nhiều phần: mỗi phần thêm cộng 2 giây (xe xếp hàng dỡ hàng lần lượt)
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
		req.time_left = req.time_total
		req.units = int(w.get("sos_units", 1))
		req.time_total += UNIT_EXTRA_SECONDS * (req.units - 1)  # nhiều xe phải xếp hàng dỡ hàng
		return req

# ===== VEHICLE =====
class Vehicle extends Node2D:
	# Hình xe SVG của D (cùng bộ với icon tòa nhà trên bản đồ), đầu xe quay sang phải.
	const TRUCK_ICON := preload('res://assets/icons/truck.svg')
	const BOAT_ICON := preload('res://assets/icons/boat.svg')
	const ICON_SIZE := Vector2(24, 16)  # giữ tỉ lệ 96 × 64 của file SVG
	const PARK_OFFSET := 18.0  # lúc đỗ ở kho: xe tải lệch trái, ca-nô lệch phải để không chồng nhau
	const LANE_OFFSET := 7.0   # xe chạy lệch sang phải hướng đi, mỗi chiều một làn
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
	var _jam_time := 0.0

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
		_update_lane(delta)

	func _update_lane(delta: float) -> void:
		var want := Vector2.ZERO
		if state_id != Types.VehicleState.IDLE:
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
	# Xe đã vào một đoạn thì đi hết đoạn đó, tốc độ tối thiểu MIN_EDGE_SPEED_FACTOR.
	func advance(delta: float) -> bool:
		if path == null or path_index >= path.edge_ids.size():
			return true
		var e: Edge = RescueManager.g().get_edge(path.edge_ids[path_index])
		if e == null:
			_cut()
			return true
		var next_id: int = path.node_ids[path_index + 1]
		var target: Vector2 = RescueManager.g().get_map_node(next_id).pos
		var f := e.speed_factor(type)
		if f <= 0.0:
			f = MIN_EDGE_SPEED_FACTOR  # cạnh vừa thành không đi được: đi nốt với tốc độ tối thiểu
		if position.distance_to(target) > ARRIVE_EPSILON:
			heading = position.direction_to(target)
			queue_redraw()
		var jam := RescueManager.congestion_factor(self)
		_jam_time = _jam_time + delta if jam < 1.0 else 0.0
		if _jam_time > JAM_GIVE_UP:
			jam = maxf(jam, FOLLOW_SLOW)  # chờ quá lâu: đi chậm qua
		if jammed != (jam < 1.0):
			jammed = jam < 1.0
			queue_redraw()
		position = position.move_toward(target, Config.base_speed(type) * f * jam * delta)
		if position.distance_to(target) < ARRIVE_EPSILON:
			position = target
			current_node = next_id
			path_index += 1
			return not _next_edge_same_segment(e)
		return false

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
		request.assigned = maxi(0, request.assigned - 1)
		request.vehicle_ids.erase(id)
		request.state = Types.SosState.PENDING
		request.vehicle_id = request.vehicle_ids.back() if not request.vehicle_ids.is_empty() else -1
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
		heading = Vector2.RIGHT
		_lane = Vector2.ZERO
		change_state(IdleState.new(), Types.VehicleState.IDLE)
		RescueManager.mark_dirty()

	func _draw() -> void:
		var offset := _lane
		if state_id == Types.VehicleState.IDLE:
			offset.x = -PARK_OFFSET if type == Types.VehicleType.TRUCK else PARK_OFFSET
		var icon := TRUCK_ICON if type == Types.VehicleType.TRUCK else BOAT_ICON
		var left := heading.x < 0.0  # lật hình để xe không chổng ngược khi đi sang trái
		draw_set_transform(offset, heading.angle() + (PI if left else 0.0), Vector2(-1.0 if left else 1.0, 1.0))
		draw_texture_rect(icon, Rect2(-ICON_SIZE / 2.0, ICON_SIZE), false)
		draw_set_transform(Vector2.ZERO)
		if state_id == Types.VehicleState.STRANDED:
			draw_arc(offset, ICON_SIZE.x / 2.0 + 4.0, 0.0, TAU, 24, Color('#FF4500'), 2.0)
		if jammed and state_id != Types.VehicleState.IDLE:  # đèn phanh: hai chấm đỏ ở đuôi xe
			var rear := offset - heading * (ICON_SIZE.x / 2.0 - 1.0)
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
			RescueManager.complete_request(req, v)
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
		if is_instance_valid(v):  # xe gắn vào VehicleLayer đã bị giải phóng khi chơi lại (đổi scene)
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

# Tìm đường cho xe; cạnh sắp có xe khác đi qua tính đắt hơn (CONGESTION_PATH_COST mỗi xe) để xe mới né chỗ đông.
# exclude: xe đang tự tính lại đường, không tính phần của chính nó.
func find_path(from_id: int, to_id: int, vehicle_type: int, exclude: Vehicle = null) -> PathResult:
	if path_provider.is_valid():
		return path_provider.call(from_id, to_id, vehicle_type)
	if graph != null:
		return g().find_path(from_id, to_id, vehicle_type)  # đồ thị giả của scene thử
	return g().find_path(from_id, to_id, vehicle_type, congestion_penalty(exclude))


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


# Hệ số tốc độ do kẹt xe (1 = chạy bình thường, 0 = dừng chờ), chỉ dùng khoảng cách:
# - bám đuôi: xe phía trước cùng hướng, cùng làn, cách dưới FOLLOW_GAP thì chậm, dưới STOP_GAP thì dừng;
# - ngã ba, ngã tư (node có từ 3 cạnh): xe sắp vào nhường xe đang ở trong ngã ba, hoặc xe từ nhánh cắt ngang
#   ở gần ngã ba hơn; bằng nhau thì xe có mã nhỏ hơn đi trước, nên hai xe không cùng nhường nhau.
# others: danh sách xe để xét (test truyền vào); rỗng thì dùng mọi xe của RescueManager.
func congestion_factor(v: Vehicle, others: Array = []) -> float:
	if not v.is_moving():
		return 1.0
	var list: Array = others if not others.is_empty() else _nearby(v.position)
	var f := 1.0
	var nxt := v.next_node()
	var jpos := Vector2.ZERO
	var dv := INF
	var approaching := false
	if nxt != -1 and g().get_edges_of(nxt).size() >= 3:
		jpos = g().get_map_node(nxt).pos
		dv = v.position.distance_to(jpos)
		approaching = dv > JUNCTION_RADIUS and dv < JUNCTION_APPROACH
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
		if approaching and absf(u.heading.dot(v.heading)) < 0.7:
			var du: float = u.position.distance_to(jpos)
			var inside: bool = du <= JUNCTION_RADIUS
			var first: bool = u.next_node() == nxt and (du < dv or (is_equal_approx(du, dv) and u.id < v.id))
			if inside or first:
				f = 0.0
	return f

func _process(delta: float) -> void:
	_clock += delta
	_rebuild_grid()
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
			for vid in r.vehicle_ids:  # mọi xe đang chở tới SOS này quay về, hoàn hàng
				if _vehicles.has(vid) and _vehicles[vid].request == r:
					_vehicles[vid].on_request_failed()
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
				var p: PathResult = find_path(v.hub_id, r.node_id, v.type)
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
	v.change_state(EnRouteState.new(), Types.VehicleState.EN_ROUTE)
	EventBus.sos_assigned.emit(r.id, v.id)

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
func _hub_for(type: int) -> int:
	var best := -1
	for hid in _hubs:
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
