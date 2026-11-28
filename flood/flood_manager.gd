extends Node
# Autoload: FloodManager (module B). Lũ lan theo ô trên lưới 32 × 18.
# - Ô có độ cao tới Config.SEA_MAX_ELEVATION, hoặc ô sông (grid.water), là nguồn nước. Mặt nước biển (water_level) mỗi đợt
#   dâng đều tới WAVES[i].water_peak trong WAVE_RISE_TIME giây đầu, rồi rút RECEDE_RATIO phần vừa dâng tới hết đợt;
#   đứng yên trong lượt nghỉ.
# - Mỗi FLOOD_TICK, nước tràn từ một ô đã ngập (sâu ít nhất FLOOD_SPILL_DEPTH, hoặc là biển) sang 4 ô kề
#   nếu mặt nước ô nguồn cao hơn nền ô kề. Mặt nước ô kề dâng dần về mặt nước ô nguồn, nhanh nhất
#   FLOOD_SPREAD_RATE mỗi giây. Nước rút: ô đất thoát nước về mức cân bằng (mức cao nhất phải vượt qua trên đường ra
#   biển thấp nhất), nhanh nhất FLOOD_DRAIN_RATE mỗi giây; nước đọng trong hố trũng thấm dần FLOOD_SEEP_RATE.
#   Đường đổi trạng thái cả hai chiều.
# - Vùng trũng bị đồi chắn không ngập dù thấp hơn mực biển; vùng xa biển ngập muộn hơn vùng gần biển.
# - Mỗi cạnh đường ngập theo độ sâu trung bình của hai ô nó nối, nên đường đổi màu đúng chỗ nước phủ.

const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DRY_EPSILON := 0.05  # sâu dưới mức này coi như khô (tránh sai số số thực)
const Graph := preload('res://graph/graph_manager.gd')  # dùng Graph.MinHeap

var water_level := 0.0  # mặt nước biển, thang 0–100; HUD hiển thị số này
var _running := false  # đang trong đợt (mặt nước dâng hoặc rút)
var _wave_t := 0.0    # giây đã qua của đợt
var _from := 0.0      # mặt nước lúc bắt đầu đợt
var _peak := 0.0      # đỉnh của đợt
var _low := 0.0       # mặt nước cuối đợt, sau khi rút
var _accum := 0.0
var _warned := {}
var _ground := PackedFloat32Array()  # nền để nước lan: ô sông là 0 (lòng sông)
var _deck := PackedFloat32Array()    # mặt đường để tính độ sâu ngập: bằng nền, riêng ô sông là mặt cầu
var _level := PackedFloat32Array()   # mặt nước từng ô, luôn >= nền
var _prev := PackedFloat32Array()    # mặt nước ở lần cập nhật trước, để ước lượng tốc độ dâng
var _sea := PackedByteArray()        # 1 nếu ô là biển
var _last_dt := 0.0
var _hydraulic_steps := PackedInt32Array()  # -1: dry or disconnected from the sources
var _fourth_cell := PackedByteArray()  # map-designated lowland exceptions
var _hydraulic_dirty := true
var _spill := PackedFloat32Array()  # ngưỡng tràn: mức cao nhất phải vượt qua trên đường ra biển thấp nhất (chỉ theo địa hình)


func _ready() -> void:
	if has_node("/root/EventBus"):
		EventBus.game_started.connect(reset)
		EventBus.wave_started.connect(start_wave)
		EventBus.wave_ended.connect(_on_wave_ended)
		EventBus.edge_added.connect(_on_edge_added)
		EventBus.road_changed.connect(_on_road_changed)


# GameManager nạp bản đồ trước khi phát game_started, nên lúc này đọc được độ cao các ô.
func reset() -> void:
	water_level = 0.0
	_running = false
	_wave_t = 0.0
	_from = 0.0
	_peak = 0.0
	_low = 0.0
	_accum = 0.0
	_last_dt = 0.0
	_warned.clear()
	_edge_cells.clear()
	var n := Config.GRID_COLS * Config.GRID_ROWS
	_ground.resize(n)
	_deck.resize(n)
	_sea.resize(n)
	_fourth_cell.resize(n)
	_hydraulic_dirty = true
	for i in n:
		var g := GraphManager.cell_elevation(_cell(i)) if has_node("/root/GraphManager") else 50.0
		var river := has_node("/root/GraphManager") and GraphManager.cell_is_water(_cell(i))
		_deck[i] = g
		_ground[i] = 0.0 if river else g
		_sea[i] = 1 if river or g <= Config.SEA_MAX_ELEVATION else 0
		_fourth_cell[i] = 1 if GraphManager.is_deep_flood_lowland(_cell(i)) else 0
	_level = _ground.duplicate()
	_prev = _level.duplicate()
	_update_hydraulic_distance()
	_spill.clear()  # ngưỡng tràn: lấy sẵn từ map (grid.spill), map không có thì tính lần đầu nước rút (_spread)
	var pre: Array = GraphManager.get_spill() if has_node("/root/GraphManager") else []
	if pre.size() == n:
		_spill.resize(n)
		for i in n:
			_spill[i] = float(pre[i])
	GraphManager.refresh_boat_depth()
	if has_node("/root/EventBus"):
		EventBus.water_level_changed.emit(water_level)


func reset_flood() -> void:
	reset()


func start_wave(index: int) -> void:
	if index < 0:
		return
	var profile: Dictionary = {}
	if Config.has_method("get_wave_profile"):
		profile = Config.call("get_wave_profile", index + 1)
	elif index < Config.WAVES.size():
		profile = Config.WAVES[index]
	if not profile.has("water_peak"):
		return
	_from = water_level
	_peak = maxf(_from, float(profile.water_peak))
	_low = _peak - Config.RECEDE_RATIO * (_peak - _from)
	_wave_t = 0.0
	_running = true
	_warned.clear()


# Dừng mặt nước (đang dâng hay rút) ở mức hiện tại.
func stop_rising() -> void:
	_running = false


# Mặt nước biển sau t giây của đợt đang chạy: dâng đều tới đỉnh trong WAVE_RISE_TIME giây, rồi rút đều tới hết đợt.
func level_at(t: float) -> float:
	if t <= Config.WAVE_RISE_TIME:
		return lerpf(_from, _peak, t / Config.WAVE_RISE_TIME)
	return lerpf(_peak, _low, clampf((t - Config.WAVE_RISE_TIME) / (Config.WAVE_DURATION - Config.WAVE_RISE_TIME), 0.0, 1.0))


# Mặt nước đang rút (nửa sau đợt).
func is_receding() -> bool:
	return _running and _wave_t > Config.WAVE_RISE_TIME


func _on_wave_ended(_index: int) -> void:
	stop_rising()


func get_water_level() -> float:
	return water_level


# --- Truy vấn theo ô (FloodOverlay vẽ từ đây) ---

func depth_at(cell: Vector2i) -> float:
	var i := _index(cell)
	return _cell_depth(i) if i >= 0 else 0.0


# Mặt nước của ô (ô khô thì bằng nền). FloodOverlay dùng để vẽ.
func surface_at(cell: Vector2i) -> float:
	var i := _index(cell)
	return minf(_level[i], _deck[i] + _cell_depth(i)) if i >= 0 else 0.0


# Mặt nạ ô có nước (biển, sông hoặc ô đất đang ngập), mỗi ô một byte theo chỉ số ô. EdgeLayer dùng để vẽ cầu.
func wet_mask() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(_level.size())
	for i in _level.size():
		m[i] = 1 if _sea[i] == 1 or _cell_depth(i) >= DRY_EPSILON else 0
	return m


func is_sea(cell: Vector2i) -> bool:
	var i := _index(cell)
	return i >= 0 and _sea[i] == 1


func state_for_depth(depth: float) -> int:
	if depth < DRY_EPSILON:
		return Types.EdgeState.DRY
	if depth < Config.SHALLOW_MAX:
		return Types.EdgeState.SHALLOW
	return Types.EdgeState.DEEP


# Trạng thái theo mực biển chung, giữ lại cho scene thử và mã cũ. Đường trong ván dùng depth_at.
func compute_state(edge_elevation: float) -> int:
	var d := water_level - edge_elevation
	if d < 0.0:
		return Types.EdgeState.DRY
	if d < Config.SHALLOW_MAX:
		return Types.EdgeState.SHALLOW
	return Types.EdgeState.DEEP


# Dùng trong test: đặt mặt nước của mọi ô lên tối thiểu `level`, bỏ qua đường lan (như mô hình mực nước chung cũ).
func fill_all(level: float) -> void:
	water_level = level
	_hydraulic_dirty = true
	for i in _level.size():
		_level[i] = maxf(_level[i], maxf(_ground[i], level))


# Dùng trong test: đặt mặt nước của một ô.
func set_cell_level(cell: Vector2i, level: float) -> void:
	var i := _index(cell)
	if i >= 0:
		_level[i] = maxf(_ground[i], level)
		_hydraulic_dirty = true


# --- Mô phỏng ---

func _process(delta: float) -> void:
	if not _running:
		return
	_wave_t += delta
	water_level = clampf(level_at(_wave_t), 0.0, 100.0)
	_accum += delta
	if _accum >= Config.FLOOD_TICK:
		var dt := _accum
		_accum = 0.0
		step(dt)


# Một bước mô phỏng: biển theo water_level, nước lan một bước, rồi cập nhật trạng thái đường.
func step(dt: float) -> void:
	_spread(dt)
	_last_dt = dt
	_update_edges()
	if has_node("/root/EventBus"):
		EventBus.water_level_changed.emit(water_level)


func _spread(dt: float) -> void:
	_hydraulic_dirty = true
	_prev = _level.duplicate()
	# Mặt biển cập nhật trước, để ô đất sát biển nhận nước ngay trong bước này.
	for i in _level.size():
		if _sea[i] == 1:
			_level[i] = maxf(_ground[i], water_level)
	var cols := Config.GRID_COLS
	var rows := Config.GRID_ROWS
	var step_max := Config.FLOOD_SPREAD_RATE * dt
	var drain_max := Config.FLOOD_DRAIN_RATE * dt
	var seep_max := Config.FLOOD_SEEP_RATE * dt
	var draining := _above_sea()  # có ô đất mang nước cao hơn mặt biển (đang rút, hoặc còn nước đọng); lúc chỉ dâng thì không
	if draining and _spill.size() != _level.size():
		_compute_spill()
	for i in _level.size():
		if _sea[i] == 1:
			continue
		var x := i % cols
		var y := i / cols
		var source := -INF
		for d in NEIGHBORS:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var j := ny * cols + nx
			var wet := _sea[j] == 1 or _prev[j] - _ground[j] >= Config.FLOOD_SPILL_DEPTH
			var neighbor_level := _level[j] if _sea[j] == 1 else _prev[j]
			if wet and neighbor_level > source:
				source = neighbor_level
		var eq := maxf(water_level, _spill[i]) if draining else water_level  # mức cân bằng của ô với mặt biển hiện tại
		if draining:
			source = minf(source, eq)  # nước rút: không dâng ô lên quá mức cân bằng
		if source > _level[i]:
			_level[i] = minf(source, _level[i] + step_max)
		elif draining and _level[i] > _ground[i]:
			if _level[i] > eq + 0.001:
				_level[i] = maxf(eq, _level[i] - drain_max)  # thoát ra biển theo đường thấp nhất
			elif eq > water_level + 0.01:
				_level[i] = maxf(_ground[i], _level[i] - seep_max)  # đọng trong hố trũng: thấm dần


# Mức cân bằng của ô khi nước thoát ra biển = max(mặt biển, ngưỡng tràn): mặt nước không xuống thấp hơn mức cao nhất
# phải vượt qua trên đường ra biển thấp nhất. Ngưỡng tràn chỉ phụ thuộc địa hình nên tính một lần mỗi ván
# (priority flood từ các ô biển), lúc rút chỉ còn một phép max mỗi ô.
func _compute_spill() -> void:
	var n := _ground.size()
	_spill.resize(n)
	_spill.fill(INF)
	var heap = Graph.MinHeap.new()
	for i in n:
		if _sea[i] == 1:
			_spill[i] = _ground[i]
			heap.push(_spill[i], i)
	var cols := Config.GRID_COLS
	var rows := Config.GRID_ROWS
	while heap.size() > 0:
		var top: Array = heap.pop()
		var i: int = top[1]
		if top[0] > _spill[i]:
			continue
		var x := i % cols
		var y := i / cols
		for d in NEIGHBORS:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var j := ny * cols + nx
			var v := maxf(_ground[j], _spill[i])
			if v < _spill[j]:
				_spill[j] = v
				heap.push(v, j)


# Có ô đất mang nước cao hơn mặt biển không (đang rút, hoặc còn nước đọng trong hố trũng).
func _above_sea() -> bool:
	for i in _level.size():
		if _sea[i] == 0 and _level[i] > water_level + 0.001 and _level[i] > _ground[i] + 0.001:
			return true
	return false

# Raw water levels still drive spreading and drainage. Gameplay depth is capped only
# after tracing a wet, cardinal path from a source, so the cap does not dam the flood.
func hydraulic_distance_at(cell: Vector2i) -> int:
	var i := _index(cell)
	if i < 0:
		return -1
	_ensure_hydraulic_distance()
	return _hydraulic_steps[i]


func _ensure_hydraulic_distance() -> void:
	if _hydraulic_dirty:
		_update_hydraulic_distance()


func _update_hydraulic_distance() -> void:
	_hydraulic_dirty = false
	_hydraulic_steps.resize(_level.size())
	_hydraulic_steps.fill(-1)
	var queue := PackedInt32Array()
	for i in _level.size():
		if _sea[i] == 1:
			_hydraulic_steps[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var cell := _cell(i)
		for direction in NEIGHBORS:
			var j := _index(cell + direction)
			if j < 0 or _hydraulic_steps[j] >= 0 or _level[j] - _ground[j] < DRY_EPSILON:
				continue
			_hydraulic_steps[j] = _hydraulic_steps[i] + 1
			queue.append(j)


func _can_be_deep(i: int) -> bool:
	var distance := _hydraulic_steps[i]
	if distance >= 0 and distance <= Config.DEEP_FLOOD_REACH:
		return true
	if distance != Config.DEEP_FLOOD_REACH + 1 or _fourth_cell[i] == 0:
		return false
	if _spill.size() != _ground.size():
		_compute_spill()
	return _spill[i] - _ground[i] >= DRY_EPSILON


func _cell_depth(i: int) -> float:
	_ensure_hydraulic_distance()
	return _limited_depth(i, _level[i], _depth_limit(i))


func _depth_limit(i: int) -> float:
	return INF if _can_be_deep(i) else Config.SHALLOW_MAX - DRY_EPSILON


func _limited_depth(i: int, surface: float, limit: float) -> float:
	return clampf(surface - _deck[i], 0.0, limit)


# Mỗi cạnh ngập theo nước tại chính hai ô nó nối (độ sâu trung bình hai ô), nên đường đổi màu đúng chỗ
# nước phủ. Cảnh báo mỗi mức lấy cạnh sắp đổi trạng thái sớm nhất trong đoạn.
func _update_edges() -> void:
	if not has_node("/root/GraphManager"):
		return
	_ensure_hydraulic_distance()
	var warnings := {}
	for eid in GraphManager.get_edge_ids():
		var e = GraphManager.get_edge(eid)
		if e == null:
			continue
		var cells := _cells_of(e)
		var state := state_for_depth(_mean_depth(cells))
		if e.state != state:
			GraphManager.set_edge_state(eid, state)
		var key: int = e.segment if e.segment >= 0 else -1 - eid
		_collect_warning(warnings, key, eid, cells, state)
	GraphManager.refresh_boat_depth()
	for key in warnings:
		_warned[key] = true
		var warning: Dictionary = warnings[key]
		EventBus.flood_warning.emit(warning.edge_id, warning.eta)


func _mean_depth(cells: Array) -> float:
	if cells.is_empty():
		return 0.0
	var total := 0.0
	for i in cells:
		total += _cell_depth(i)
	return total / cells.size()


# Số giây tới khi cạnh sang trạng thái kế tiếp. Sang SHALLOW: ngay khi một trong các ô bắt đầu ngập.
# Sang DEEP: khi độ sâu trung bình tới SHALLOW_MAX, theo tốc độ dâng trung bình của các ô.
# Khóa cảnh báo theo đoạn (key), nên cả đoạn chỉ cảnh báo một lần cho mỗi mức.
func _collect_warning(warnings: Dictionary, key: int, edge_id: int, cells: Array, state: int) -> void:
	if state >= Types.EdgeState.DEEP or _last_dt <= 0.0 or cells.is_empty():
		return
	var warn_key := Vector2i(key, state + 1)
	if _warned.has(warn_key):
		return
	var eta := INF
	if state == Types.EdgeState.DRY:
		for i in cells:
			eta = minf(eta, _eta(i, DRY_EPSILON))
	else:
		eta = _deep_warning_eta(cells)
	if eta <= Config.WARNING_SECONDS and (not warnings.has(warn_key) or eta < warnings[warn_key].eta):
		warnings[warn_key] = {edge_id = edge_id, eta = maxf(eta, 0.0)}


# Extrapolate each cell's effective depth at its current hydraulic limit.
func _deep_warning_eta(cells: Array) -> float:
	var forecasts: Array[Vector3] = []  # current depth, rise per second, depth limit
	for i in cells:
		var limit := _depth_limit(i)
		var depth := _limited_depth(i, _level[i], limit)
		var rise := maxf(0.0, depth - _limited_depth(i, _prev[i], limit)) / _last_dt
		forecasts.append(Vector3(depth, rise, limit))
	var threshold := Config.SHALLOW_MAX * cells.size()
	var upper := Config.WARNING_SECONDS
	if _projected_depth_sum(forecasts, upper) < threshold:
		return INF
	var lower := 0.0
	for iteration in 10:
		var mid := (lower + upper) * 0.5
		if _projected_depth_sum(forecasts, mid) < threshold:
			lower = mid
		else:
			upper = mid
	return upper


func _projected_depth_sum(forecasts: Array[Vector3], seconds: float) -> float:
	var total := 0.0
	for forecast in forecasts:
		total += minf(forecast.z, forecast.x + forecast.y * seconds)
	return total


# Số giây tới khi ô i sâu tới `threshold`. Ô đang ngập: theo tốc độ dâng của chính nó.
# Ô còn khô chưa có mặt nước để đo, nên ước lượng theo các ô kề đang ngập: ô kề đã cao hơn nền ô này
# thì nước tràn sang ngay nhịp sau; ô kề đang dâng thì tính thời gian nó dâng tới nền ô này.
func _eta(i: int, threshold: float) -> float:
	var eta := INF
	var limit := _depth_limit(i)
	var depth := _limited_depth(i, _level[i], limit)
	var rise := (depth - _limited_depth(i, _prev[i], limit)) / _last_dt
	if rise > 0.0:
		eta = (threshold - depth) / rise
	if depth >= DRY_EPSILON:
		return eta
	var c := _cell(i)
	for d in NEIGHBORS:
		var j := _index(c + d)
		if j < 0:
			continue
		var spills := _sea[j] == 1 or _level[j] - _ground[j] >= Config.FLOOD_SPILL_DEPTH
		if spills and _level[j] > _deck[i]:
			eta = minf(eta, Config.FLOOD_TICK)
			continue
		var rise_j := (_level[j] - _prev[j]) / _last_dt
		if rise_j > 0.0 and (_sea[j] == 1 or _level[j] > _ground[j]):
			eta = minf(eta, (_deck[i] - _level[j]) / rise_j + Config.FLOOD_TICK)
	return eta


# Tô đường: cạnh mới lấy trạng thái ngay (theo hai ô của nó); cập nhật toàn bộ (cảnh báo theo đoạn, lối xuống nước, vùng
# ngập) gom lại một lần cuối khung hình, không chạy lại mỗi ô khi kéo chuột vẽ một đường dài.
var _edges_pending := false

func _on_edge_added(edge_id: int) -> void:
	if not has_node("/root/GraphManager") or _level.is_empty():
		return
	var e = GraphManager.get_edge(edge_id)
	if e != null and not e.boat_only and not e.is_ferry and not e.is_highway:
		var cells: Array = []
		for node_id in [e.node_a, e.node_b]:
			var n = GraphManager.get_map_node(node_id)
			if n != null:
				var i := _index(GraphManager.cell_of(n.pos))
				if i >= 0 and not cells.has(i):
					cells.append(i)
		var state := state_for_depth(_mean_depth(cells))
		if e.state != state:
			GraphManager.set_edge_state(edge_id, state)
	_queue_update_edges()


# Ô (chỉ số) hai đầu của cạnh, lưu sẵn: mỗi nhịp lũ không phải tra lại vị trí, ô của từng nút. Xóa khi đường đổi.
var _edge_cells := {}

func _cells_of(e) -> Array:
	var cells = _edge_cells.get(e.id)
	if cells == null:
		cells = []
		for node_id in [e.node_a, e.node_b]:
			var n = GraphManager.get_map_node(node_id)
			if n != null:
				var i := _index(GraphManager.cell_of(n.pos))
				if i >= 0 and not cells.has(i):
					cells.append(i)
		_edge_cells[e.id] = cells
	return cells


func _queue_update_edges() -> void:
	_edge_cells.clear()
	if not _edges_pending:
		_edges_pending = true
		_flush_edges.call_deferred()


func _flush_edges() -> void:
	_edges_pending = false
	_update_edges()


# Tô hoặc xóa ô làm đoạn đổi, kể cả lúc nước đứng yên.
func _on_road_changed() -> void:
	_queue_update_edges()


func _cell(i: int) -> Vector2i:
	return Vector2i(i % Config.GRID_COLS, i / Config.GRID_COLS)


func _index(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= Config.GRID_COLS or cell.y >= Config.GRID_ROWS or _level.is_empty():
		return -1
	return cell.y * Config.GRID_COLS + cell.x
