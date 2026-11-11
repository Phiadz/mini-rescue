extends Node
# Autoload: FloodManager (module B). Lũ lan theo ô trên lưới 32 × 18.
# - Ô có độ cao tới Config.SEA_MAX_ELEVATION là biển. Mặt nước biển (water_level) dâng theo đợt như trước:
#   tốc độ = WAVES[i].water_delta / WAVE_DURATION, đứng yên trong lượt nghỉ.
# - Mỗi FLOOD_TICK, nước tràn từ một ô đã ngập (sâu ít nhất FLOOD_SPILL_DEPTH, hoặc là biển) sang 4 ô kề
#   nếu mặt nước ô nguồn cao hơn nền ô kề. Mặt nước ô kề dâng dần về mặt nước ô nguồn, nhanh nhất
#   FLOOD_SPREAD_RATE mỗi giây. Nước không rút (giữ luật một chiều DRY -> SHALLOW -> DEEP).
# - Vùng trũng bị đồi chắn không ngập dù thấp hơn mực biển; vùng xa biển ngập muộn hơn vùng gần biển.
# - Mỗi cạnh đường ngập theo độ sâu trung bình của hai ô nó nối, nên đường đổi màu đúng chỗ nước phủ.

const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DRY_EPSILON := 0.05  # sâu dưới mức này coi như khô (tránh sai số số thực)

var water_level := 0.0  # mặt nước biển, thang 0–100; HUD hiển thị số này
var _rate := 0.0
var _rising := false
var _accum := 0.0
var _warned := {}
var _ground := PackedFloat32Array()  # độ cao nền từng ô
var _level := PackedFloat32Array()   # mặt nước từng ô, luôn >= nền
var _prev := PackedFloat32Array()    # mặt nước ở lần cập nhật trước, để ước lượng tốc độ dâng
var _sea := PackedByteArray()        # 1 nếu ô là biển
var _last_dt := 0.0


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
	_rate = 0.0
	_rising = false
	_accum = 0.0
	_last_dt = 0.0
	_warned.clear()
	var n := Config.GRID_COLS * Config.GRID_ROWS
	_ground.resize(n)
	_sea.resize(n)
	for i in n:
		var g := GraphManager.cell_elevation(_cell(i)) if has_node("/root/GraphManager") else 50.0
		_ground[i] = g
		_sea[i] = 1 if g <= Config.SEA_MAX_ELEVATION else 0
	_level = _ground.duplicate()
	_prev = _level.duplicate()
	if has_node("/root/EventBus"):
		EventBus.water_level_changed.emit(water_level)


func reset_flood() -> void:
	reset()


func start_wave(index: int) -> void:
	if index >= 0 and index < Config.WAVES.size():
		_rate = Config.WAVES[index].water_delta / Config.WAVE_DURATION
		_rising = true


func stop_rising() -> void:
	_rising = false


func _on_wave_ended(_index: int) -> void:
	stop_rising()


func get_water_level() -> float:
	return water_level


# --- Truy vấn theo ô (FloodOverlay vẽ từ đây) ---

func depth_at(cell: Vector2i) -> float:
	var i := _index(cell)
	return maxf(0.0, _level[i] - _ground[i]) if i >= 0 else 0.0


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
	for i in _level.size():
		_level[i] = maxf(_level[i], maxf(_ground[i], level))


# Dùng trong test: đặt mặt nước của một ô.
func set_cell_level(cell: Vector2i, level: float) -> void:
	var i := _index(cell)
	if i >= 0:
		_level[i] = maxf(_ground[i], level)


# --- Mô phỏng ---

func _process(delta: float) -> void:
	if not _rising:
		return
	water_level = minf(water_level + _rate * delta, 100.0)
	_accum += delta
	if _accum >= Config.FLOOD_TICK:
		var dt := _accum
		_accum = 0.0
		step(dt)


# Một bước mô phỏng: biển theo water_level, nước lan một bước, rồi cập nhật trạng thái đường.
func step(dt: float) -> void:
	_spread(dt)
	_last_dt = dt
	if has_node("/root/EventBus"):
		EventBus.water_level_changed.emit(water_level)
	_update_edges()


func _spread(dt: float) -> void:
	# Mặt biển cập nhật trước, để ô đất sát biển nhận nước ngay trong bước này.
	for i in _level.size():
		if _sea[i] == 1:
			_level[i] = maxf(_ground[i], water_level)
	_prev = _level.duplicate()
	var cols := Config.GRID_COLS
	var rows := Config.GRID_ROWS
	var step_max := Config.FLOOD_SPREAD_RATE * dt
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
			if wet and _prev[j] > source:
				source = _prev[j]
		if source > _level[i]:
			_level[i] = minf(source, _level[i] + step_max)


# Mỗi cạnh ngập theo nước tại chính hai ô nó nối (độ sâu trung bình hai ô), nên đường đổi màu đúng chỗ
# nước phủ. Cảnh báo trước 5 giây vẫn gom theo đoạn: mỗi đoạn chỉ cảnh báo một lần cho mỗi mức ngập.
func _update_edges() -> void:
	if not has_node("/root/GraphManager"):
		return
	for eid in GraphManager.get_edge_ids():
		var e = GraphManager.get_edge(eid)
		if e == null:
			continue
		var cells: Array = []
		for node_id in [e.node_a, e.node_b]:
			var n = GraphManager.get_map_node(node_id)
			if n != null:
				var i := _index(GraphManager.cell_of(n.pos))
				if i >= 0 and not cells.has(i):
					cells.append(i)
		var state := state_for_depth(_mean_depth(cells))
		if e.state != state:
			GraphManager.set_edge_state(eid, state)
		var key: int = e.segment if e.segment >= 0 else -1 - eid
		_check_warning(key, [eid], cells, state)


func _mean_depth(cells: Array) -> float:
	if cells.is_empty():
		return 0.0
	var total := 0.0
	for i in cells:
		total += maxf(0.0, _level[i] - _ground[i])
	return total / cells.size()


# Số giây tới khi cạnh sang trạng thái kế tiếp. Sang SHALLOW: ngay khi một trong các ô bắt đầu ngập.
# Sang DEEP: khi độ sâu trung bình tới SHALLOW_MAX, theo tốc độ dâng trung bình của các ô.
# Khóa cảnh báo theo đoạn (key), nên cả đoạn chỉ cảnh báo một lần cho mỗi mức.
func _check_warning(key: int, edges: Array, cells: Array, state: int) -> void:
	if state >= Types.EdgeState.DEEP or _last_dt <= 0.0 or cells.is_empty():
		return
	var eta := INF
	if state == Types.EdgeState.DRY:
		for i in cells:
			eta = minf(eta, _eta(i, DRY_EPSILON))
	else:
		var rise := 0.0
		for i in cells:
			rise += maxf(0.0, _level[i] - _prev[i]) / _last_dt
		rise /= cells.size()
		if rise > 0.0:
			eta = (Config.SHALLOW_MAX - _mean_depth(cells)) / rise
	var warn_key := Vector2i(key, state + 1)
	if eta <= Config.WARNING_SECONDS and not _warned.has(warn_key):
		_warned[warn_key] = true
		if has_node("/root/EventBus"):
			EventBus.flood_warning.emit(edges[0], maxf(eta, 0.0))


# Số giây tới khi ô i sâu tới `threshold`. Ô đang ngập: theo tốc độ dâng của chính nó.
# Ô còn khô chưa có mặt nước để đo, nên ước lượng theo các ô kề đang ngập: ô kề đã cao hơn nền ô này
# thì nước tràn sang ngay nhịp sau; ô kề đang dâng thì tính thời gian nó dâng tới nền ô này.
func _eta(i: int, threshold: float) -> float:
	var eta := INF
	var rise := (_level[i] - _prev[i]) / _last_dt
	if rise > 0.0:
		eta = (_ground[i] + threshold - _level[i]) / rise
	if _level[i] - _ground[i] >= DRY_EPSILON:
		return eta
	var c := _cell(i)
	for d in NEIGHBORS:
		var j := _index(c + d)
		if j < 0:
			continue
		var spills := _sea[j] == 1 or _level[j] - _ground[j] >= Config.FLOOD_SPILL_DEPTH
		if spills and _level[j] > _ground[i]:
			eta = minf(eta, Config.FLOOD_TICK)
			continue
		var rise_j := (_level[j] - _prev[j]) / _last_dt
		if rise_j > 0.0 and (_sea[j] == 1 or _level[j] > _ground[j]):
			eta = minf(eta, (_ground[i] - _level[j]) / rise_j + Config.FLOOD_TICK)
	return eta


func _on_edge_added(_edge_id: int) -> void:
	_update_edges()


# Tô hoặc xóa ô làm đoạn đổi, kể cả lúc nước đứng yên.
func _on_road_changed() -> void:
	_update_edges()


func _cell(i: int) -> Vector2i:
	return Vector2i(i % Config.GRID_COLS, i / Config.GRID_COLS)


func _index(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= Config.GRID_COLS or cell.y >= Config.GRID_ROWS or _level.is_empty():
		return -1
	return cell.y * Config.GRID_COLS + cell.x
