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
var _flooded := PackedByteArray()  # 1 nếu ô đất đã ngập sâu và đã báo GraphManager thành vùng nước cho ca-nô
var _spill := PackedFloat32Array()  # ngưỡng tràn: mức cao nhất phải vượt qua trên đường ra biển thấp nhất (chỉ theo địa hình)
var _flood_st := PackedByteArray()  # trạng thái ngập (DRY/SHALLOW/DEEP) của ô vùng ngập ở lần cập nhật cạnh trước


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
	_flooded.resize(n)
	_flooded.fill(0)
	for i in n:
		var g := GraphManager.cell_elevation(_cell(i)) if has_node("/root/GraphManager") else 50.0
		var river := has_node("/root/GraphManager") and GraphManager.cell_is_water(_cell(i))
		_deck[i] = g
		_ground[i] = 0.0 if river else g
		_sea[i] = 1 if river or g <= Config.SEA_MAX_ELEVATION else 0
	_level = _ground.duplicate()
	_prev = _level.duplicate()
	_flood_st.resize(n)
	_flood_st.fill(255)
	_spill.clear()  # ngưỡng tràn: lấy sẵn từ map (grid.spill), map không có thì tính lần đầu nước rút (_spread)
	var pre: Array = GraphManager.get_spill() if has_node("/root/GraphManager") else []
	if pre.size() == n:
		_spill.resize(n)
		for i in n:
			_spill[i] = float(pre[i])
	if has_node("/root/EventBus"):
		EventBus.water_level_changed.emit(water_level)


func reset_flood() -> void:
	reset()


func start_wave(index: int) -> void:
	if index >= 0 and index < Config.WAVES.size():
		_from = water_level
		_peak = maxf(_from, Config.WAVES[index].water_peak)
		_low = _peak - Config.RECEDE_RATIO * (_peak - _from)
		_wave_t = 0.0
		_running = true
		_warned.clear()  # đợt mới: nước đã rút, đường khô lại, cảnh báo lại từ đầu


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
	return maxf(0.0, _level[i] - _deck[i]) if i >= 0 else 0.0


# Mặt nước của ô (ô khô thì bằng nền). FloodOverlay dùng để vẽ.
func surface_at(cell: Vector2i) -> float:
	var i := _index(cell)
	return _level[i] if i >= 0 else 0.0


# Mặt nạ ô có nước (biển, sông hoặc ô đất đang ngập), mỗi ô một byte theo chỉ số ô. EdgeLayer dùng để vẽ cầu.
func wet_mask() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(_level.size())
	for i in _level.size():
		m[i] = 1 if _sea[i] == 1 or _level[i] - _deck[i] >= DRY_EPSILON else 0
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
	for i in _level.size():
		_level[i] = maxf(_level[i], maxf(_ground[i], level))


# Dùng trong test: đặt mặt nước của một ô.
func set_cell_level(cell: Vector2i, level: float) -> void:
	var i := _index(cell)
	if i >= 0:
		_level[i] = maxf(_ground[i], level)


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
			if wet and _prev[j] > source:
				source = _prev[j]
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

# Mỗi cạnh ngập theo nước tại chính hai ô nó nối (độ sâu trung bình hai ô), nên đường đổi màu đúng chỗ
# nước phủ. Cảnh báo trước 5 giây vẫn gom theo đoạn: mỗi đoạn chỉ cảnh báo một lần cho mỗi mức ngập.
func _update_edges() -> void:
	if not has_node("/root/GraphManager"):
		return
	for eid in GraphManager.get_edge_ids():
		var e = GraphManager.get_edge(eid)
		if e == null:
			continue
		var cells := _cells_of(e)
		var state := state_for_depth(_mean_depth(cells))
		if e.state != state:
			GraphManager.set_edge_state(eid, state)
		var key: int = e.segment if e.segment >= 0 else -1 - eid
		_check_warning(key, [eid], cells, state)
	# Lối xuống nước của ca-nô (ô đường ↔ ô sông): ngập theo chính ô đường, khô thì ca-nô không lên được. Không cảnh báo.
	for eid in GraphManager.get_flood_links():
		var link = GraphManager.get_edge(eid)
		var road = GraphManager.get_map_node(link.node_a) if link != null else null
		if road == null:
			continue
		var link_state := state_for_depth(depth_at(GraphManager.cell_of(road.pos)))
		if link.state != link_state:
			GraphManager.set_edge_state(eid, link_state)
	_update_flood_cells()


# Ô đất ngập sâu lần đầu: báo GraphManager thành vùng nước cho ca-nô (mỗi ô một lần mỗi ván, nút giữ lại cả khi nước rút).
# Cạnh của nút vùng ngập đổi trạng thái theo độ sâu ô (cạnh nối hai ô vùng ngập lấy ô nông hơn): nước rút thì nông dần
# rồi khô, ca-nô không chạy vào nữa; nước dâng lại thì sâu trở lại.
func _update_flood_cells() -> void:
	if not GraphManager.has_method('add_flood_cell') or _flooded.size() != _level.size():
		return
	var changed := {}
	for i in _level.size():
		var d := _level[i] - _deck[i]
		if _flooded[i] == 0:
			if d < Config.SHALLOW_MAX:
				continue
			_flooded[i] = 1
			GraphManager.add_flood_cell(_cell(i))
		var st := state_for_depth(d)
		if st != _flood_st[i]:
			_flood_st[i] = st
			changed[i] = true
			GraphManager.set_flood_open(GraphManager.FLOOD_ID_BASE + i, st == Types.EdgeState.DEEP)
	if changed.is_empty():
		return
	# Cạnh nối hai ô vùng ngập lấy ô nông hơn, nên cập nhật cả ô vùng ngập kề ô vừa đổi.
	var last := []
	var todo := {}
	for i in changed:
		var c := _cell(i)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var j := _index(c + Vector2i(dx, dy))
				if j >= 0 and _flooded[j] == 1:
					todo[j] = true
	for i in todo:
		var d := _level[i] - _deck[i]
		var id: int = GraphManager.FLOOD_ID_BASE + i
		for eid in GraphManager.boat_edges_of(id):
			var e = GraphManager.get_edge(eid)
			var other: int = e.other_end(id)
			var dd := d
			if GraphManager.is_flood_node(other):
				var j: int = other - GraphManager.FLOOD_ID_BASE
				dd = minf(d, _level[j] - _deck[j])
			var st := state_for_depth(dd)
			if GraphManager.set_edge_state(eid, st, true):
				last = [eid, st]
	# Nước rút làm hàng trăm cạnh vùng ngập đổi cùng lúc: phát một tín hiệu thay vì mỗi cạnh một (EdgeLayer, NodeLayer bỏ
	# qua cạnh của riêng ca-nô; RescueManager chỉ cần biết đồ thị đã đổi).
	if not last.is_empty():
		EventBus.edge_state_changed.emit(last[0], last[1])


func _mean_depth(cells: Array) -> float:
	if cells.is_empty():
		return 0.0
	var total := 0.0
	for i in cells:
		total += maxf(0.0, _level[i] - _deck[i])
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
		eta = (_deck[i] + threshold - _level[i]) / rise
	if _level[i] - _deck[i] >= DRY_EPSILON:
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
	if e != null:
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
