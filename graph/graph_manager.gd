extends Node
# Autoload: GraphManager. Chủ sở hữu: A. Không đặt class_name.

const ROAD_ID_BASE := 1000  # mã nút ô đường = ROAD_ID_BASE + chỉ số ô, không đổi khi tô lại
const HOUSE_ID_BASE := 100  # nhà mọc thêm trong ván: 100, 101, ... (nhỏ hơn ROAD_ID_BASE)
const GATE_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]  # Đ, T, B, N
const GATE_NAMES := {'E': Vector2i(1, 0), 'W': Vector2i(-1, 0), 'N': Vector2i(0, -1), 'S': Vector2i(0, 1)}
const MAP_CENTER := Vector2(640, 360)  # cổng của điểm có sẵn quay về phía tâm bản đồ
const HOUSE_ICONS := ['house_blue', 'house_coral', 'house_gold', 'house_mint']
const WATER_ID_BASE := 2000 # mã nút nước (ô ca-nô đi được) = WATER_ID_BASE + chỉ số ô
const WATER_VIA_BASE := 3000 # nút điểm gãy trên sông (cạnh sông vòng qua khúc quanh), không gắn với ô nào
const BOAT_EDGE_ID_BASE := 100000  # cạnh của ca-nô đánh mã riêng, không bao giờ trùng mã cạnh đường (kể cả sau khi nạp lại bản đồ)

var _nodes := {}        # id -> MapNode (cả điểm trên bản đồ và ô đường)
var _edges := {}        # id -> Edge
var _adj := {}          # id node -> Array các id cạnh kề
var _next_edge_id := 0
var _limit := 0
var _points: Array[int] = []    # các điểm trên bản đồ, theo thứ tự trong json
var _point_cells := {}          # ô -> id điểm
var _cell_elevation: Array = [] # độ cao từng ô, khóa "grid" của bản đồ
var _cell_water: Array = []     # 1 nếu ô là sông (grid.water), bản đồ không có thì rỗng
var _cell_boat: Array = []      # 1 nếu ca-nô đi được trên ô (grid.boat: ít nhất 10% diện tích ô là sông), rỗng nếu bản đồ không có
var _boat_pos: Array = []       # grid.boat_pos: [chỉ số ô, x, y] vị trí nút nước (tâm phần sông trong ô, luôn trên sông)
var _boat_links: Array = []     # grid.boat_links: [i, j] hoặc [i, j, x, y] (vòng qua điểm gãy) — cạnh sông đã kiểm tra nằm trên sông
var _gates_enabled := false     # khóa "gates": mỗi điểm có một ô cổng, đường chỉ nối vào điểm qua ô đó
var _stages: Array = []         # khóa "stages": vùng camera theo đợt (GameManager dùng)
var _terrain: Dictionary = {}   # khóa "terrain" của bản đồ: ảnh độ cao và màu nước cho FloodOverlay
var _roads := 0                 # số ô đường đã tô
var _segments := {}             # id đoạn -> Array các id cạnh
var _gate_cells := {}           # ô cổng -> id điểm (ô cổng là ô đường dựng sẵn, không tính hạn mức, không xóa được)
var _lot_cells := {}            # ô bãi đỗ -> id kho: kho có bãi nằm giữa kho và cổng (kho, bãi, cổng thẳng hàng)
var _gate_override := {}        # id điểm -> hướng cổng ghi trong json (trường "gate": "E"/"W"/"N"/"S")
var _next_house_id := HOUSE_ID_BASE
# Đồ thị riêng của ca-nô: nút nước và cạnh boat_only (sông, bến, lối xuống nước). Không nằm trong _nodes/_adj,
# nên các module vẽ đường, tính lũ, tính ngã ba không thấy; chỉ find_path và xe dùng.
var _water := {}                # id nút nước -> MapNode (kind WATER)
var _badj := {}                 # id node -> Array id cạnh boat_only kề
var _boat_edges := {}           # id cạnh boat_only -> true
var _flood_links := {}          # id cạnh lối xuống nước (ô đường ↔ nút nước) -> true; FloodManager đặt trạng thái theo ô đường
var _next_boat_edge := 0        # mã cạnh ca-nô kế tiếp = BOAT_EDGE_ID_BASE + số này

func _ready() -> void:
	_limit = Config.EDGE_LIMIT_START
	EventBus.game_started.connect(_on_game_started)
	EventBus.point_added.connect(_add_docks)

func _on_game_started() -> void:
	_clear_edges()
	_build_gates()
	EventBus.edge_budget_changed.emit(0, _limit)
	_build_water()

func _clear_edges() -> void:
	_edges.clear()
	for id in _nodes.keys():
		if _nodes[id].kind == Types.NodeKind.ROAD:
			_nodes.erase(id)
			_adj.erase(id)
	for id in _adj:
		_adj[id] = []
	_segments.clear()
	_roads = 0
	_next_edge_id = 0
	_limit = Config.EDGE_LIMIT_START
	# _edges vừa xóa cả cạnh ca-nô: dọn luôn kề của chúng để ô cổng dựng lại ngay sau đây không gặp mã cạnh cũ.
	# Nút nước giữ nguyên; _build_water() dựng lại cạnh sông, bến và lối xuống nước.
	_badj.clear()
	_boat_edges.clear()
	_flood_links.clear()

# --- Nạp bản đồ (gọi nhiều lần vẫn đúng: luôn xóa dữ liệu cũ trước) ---
func load_map(path: String) -> void:
	_nodes.clear()
	_adj.clear()
	_points.clear()
	_point_cells.clear()
	_gate_override.clear()
	_next_house_id = HOUSE_ID_BASE
	_clear_edges()
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has('nodes'):
		push_error('GraphManager: không đọc được bản đồ ' + path)
		return
	_cell_elevation = data.get('grid', {}).get('elevation', [])
	_cell_water = data.get('grid', {}).get('water', [])
	_cell_boat = data.get('grid', {}).get('boat', [])
	_boat_pos = data.get('grid', {}).get('boat_pos', [])
	_boat_links = data.get('grid', {}).get('boat_links', [])
	_gates_enabled = bool(data.get('gates', false))
	_terrain = data.get('terrain', {})
	_stages = data.get('stages', [])
	for d in data['nodes']:
		var n := MapNode.new()
		n.id = int(d['id'])
		n.name = str(d['name'])
		n.kind = int(d['kind'])
		n.pos = Vector2(float(d['x']), float(d['y']))
		n.elevation = float(d['elevation'])
		n.icon = str(d.get('icon', ''))
		_nodes[n.id] = n
		_adj[n.id] = []
		_points.append(n.id)
		_point_cells[cell_of(n.pos)] = n.id
		if GATE_NAMES.has(str(d.get('gate', ''))):
			_gate_override[n.id] = GATE_NAMES[str(d['gate'])]
	_build_gates(false)  # chưa phát tín hiệu: game_started sẽ dựng lại cổng và phát road_changed
	_build_water()

# --- Truy vấn ---
# Chỉ các điểm trên bản đồ, không gồm ô đường.
func get_node_ids() -> Array[int]:
	return _points.duplicate()

# Điểm, ô đường, hoặc nút nước của ca-nô.
func get_map_node(id: int) -> MapNode:
	var n: MapNode = _nodes.get(id)
	return n if n != null else _water.get(id)

func _has_node(id: int) -> bool:
	return _nodes.has(id) or _water.has(id)

func get_edge(edge_id: int) -> Edge:
	return _edges.get(edge_id)

# Chỉ cạnh đường bộ (đường–đường, điểm–đường); cạnh boat_only của ca-nô không có ở đây.
func get_edge_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _edges.keys():
		if not _boat_edges.has(k):
			out.append(k)
	return out

func get_edges_of(node_id: int) -> Array[int]:
	var out: Array[int] = []
	for k in _adj.get(node_id, []):
		out.append(k)
	return out

func get_road_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _nodes:
		if _nodes[id].kind == Types.NodeKind.ROAD:
			out.append(id)
	return out

# Tất cả cạnh cùng đoạn với edge_id, theo thứ tự dọc đường.
func get_segment_edges(edge_id: int) -> Array[int]:
	var out: Array[int] = []
	if _edges.has(edge_id):
		out.assign(_segments[_edges[edge_id].segment])
	return out

# --- Lưới ---
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i((p / float(Config.CELL_SIZE)).floor())

func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(Config.CELL_SIZE)

# Độ cao nền của ô (khóa "grid" trong bản đồ), 0 nếu bản đồ không có lưới độ cao.
func cell_elevation(cell: Vector2i) -> float:
	var i := _cell_index(cell)
	return float(_cell_elevation[i]) if _in_grid(cell) and i < _cell_elevation.size() else 0.0

# Ô nằm trên sông (nguồn nước của lũ; đường tô lên đó là cầu, cao bằng độ cao ô).
func cell_is_water(cell: Vector2i) -> bool:
	var i := _cell_index(cell)
	return _in_grid(cell) and i < _cell_water.size() and int(_cell_water[i]) == 1

# Ô ca-nô đi được (lớp grid.boat, dày và liền hơn lớp sông của lũ). Bản đồ không có lớp này thì không ô nào.
func cell_is_boat(cell: Vector2i) -> bool:
	var i := _cell_index(cell)
	return _in_grid(cell) and i < _cell_boat.size() and int(_cell_boat[i]) == 1

# Bản đồ bật cổng (khóa "gates"): mỗi điểm có một ô cổng, xe vào và ra điểm chỉ qua ô đó.
func uses_gates() -> bool:
	return _gates_enabled

# Các vùng chơi theo đợt [{center: [x, y], zoom}], rỗng nếu bản đồ không khai báo.
func get_stages() -> Array:
	return _stages

# Ảnh độ cao chi tiết và màu nước của bản đồ (rỗng nếu bản đồ không khai báo).
func get_terrain() -> Dictionary:
	return _terrain

# Nút ô đường tại ô, hoặc -1 nếu ô chưa tô.
func road_at(cell: Vector2i) -> int:
	var id := _road_id(cell)
	return id if _nodes.has(id) else -1

func _road_id(cell: Vector2i) -> int:
	return ROAD_ID_BASE + _cell_index(cell)

func _cell_index(cell: Vector2i) -> int:
	return cell.y * Config.GRID_COLS + cell.x

func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < Config.GRID_COLS and cell.y < Config.GRID_ROWS

func _next_to(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) <= 1 and absi(a.y - b.y) <= 1

# --- Tô và xóa ô đường ---
# Nối tiếp đường từ nút from_id (-1 nếu mới bắt đầu kéo) sang ô cell, tạo ô đường nếu chưa có.
# Trả về nút tại ô đó, hoặc -1 nếu ô ngoài lưới, không kề nút trước, hoặc đã hết hạn mức.
func extend_road(from_id: int, cell: Vector2i) -> int:
	if not _in_grid(cell) or _lot_cells.has(cell):
		return -1  # ngoài lưới, hoặc ô bãi đỗ của kho
	if from_id != -1 and not (_nodes.has(from_id) and _next_to(cell_of(_nodes[from_id].pos), cell)):
		return -1
	var to_id: int = _point_cells.get(cell, road_at(cell))
	if not _gate_allows(from_id, to_id):
		return -1  # có cổng: điểm chỉ nối với ô cổng của nó
	var created := false
	if to_id == -1:
		if _roads >= _limit:
			return -1
		to_id = _add_road(cell)
		created = true
	if from_id != -1 and from_id != to_id and add_edge(from_id, to_id) != -1:
		return to_id
	if created:
		EventBus.edge_budget_changed.emit(_roads, _limit)
		EventBus.road_changed.emit()
	return to_id

func _add_road(cell: Vector2i) -> int:
	var n := MapNode.new()
	n.id = _road_id(cell)
	n.kind = Types.NodeKind.ROAD
	n.pos = cell_center(cell)
	var i := _cell_index(cell)
	n.elevation = _cell_elevation[i] if i < _cell_elevation.size() else 0.0
	_nodes[n.id] = n
	_adj[n.id] = []
	_roads += 1
	_link_road_to_water(n.id)
	return n.id

# Xóa ô đường và các cạnh nối vào nó, hoàn 1 hạn mức. Trả false nếu ô không có đường.
func remove_road(cell: Vector2i) -> bool:
	var id := road_at(cell)
	if id == -1 or _gate_cells.has(cell):
		return false  # ô cổng thuộc về điểm, không xóa được
	_unlink_road_from_water(id)
	for eid in _adj[id].duplicate():
		_unlink(eid)
	_nodes.erase(id)
	_adj.erase(id)
	_roads -= 1
	_after_road_edit()
	return true

func _after_road_edit() -> void:
	_refresh_segments()
	EventBus.edge_budget_changed.emit(_roads, _limit)
	EventBus.road_changed.emit()

# --- Cổng và nhà (chỉ khi bản đồ bật "gates") ---
# Mỗi điểm có một ô cổng kề cạnh (4 hướng). Ô cổng là ô đường dựng sẵn: không tính hạn mức, không xóa được.
# Đường chỉ nối vào điểm qua ô cổng, nên xe không đi xuyên qua nhà, và xe ra vào điểm theo một lối.
func _build_gates(notify := true) -> void:
	_gate_cells.clear()
	_lot_cells.clear()
	if not _gates_enabled:
		return
	for id in _points:
		_make_gate(id)
	_refresh_segments()
	if notify:
		EventBus.road_changed.emit()

# Tạo ô cổng và cạnh điểm–cổng cho điểm id. max_level: mức nới điều kiện tối đa (xem _gate_ok).
func _make_gate(id: int, max_level := 2) -> bool:
	var n: MapNode = _nodes[id]
	var cell := cell_of(n.pos)
	var dir := _choose_gate(id, cell, max_level)
	n.gate = dir
	if dir == Vector2i.ZERO:
		return false
	var reach := _gate_reach(id)
	var gcell := cell + dir * reach
	if reach == 2:
		_lot_cells[cell + dir] = id  # kho: ô giữa kho và cổng là bãi đỗ
	var gid := road_at(gcell)
	if gid == -1:
		gid = _add_road(gcell)
		_roads -= 1  # ô cổng không tính vào hạn mức
	_gate_cells[gcell] = id
	_new_edge(id, gid)
	return true

# Hướng cổng: hướng ghi trong json nếu hợp lệ; không thì hướng hợp lệ gần nhất với hướng tới tâm bản đồ
# (nhà: hướng tới khu mẹ). Không hướng nào hợp lệ thì nới dần điều kiện; vẫn không được thì ZERO.
func _choose_gate(id: int, cell: Vector2i, max_level: int) -> Vector2i:
	var n: MapNode = _nodes[id]
	if _gate_override.has(id) and _dir_ok(id, cell, _gate_override[id], max_level):
		return _gate_override[id]
	var anchor := MAP_CENTER
	if n.parent != -1 and _nodes.has(n.parent):
		anchor = _nodes[n.parent].pos
	var want := (anchor - n.pos).normalized()
	var hub := n.kind == Types.NodeKind.HUB
	for level in range(1 if hub else 0, max_level + 1):
		var best := Vector2i.ZERO
		var best_score := -INF
		for d in GATE_DIRS:
			var s := Vector2(d).dot(want)
			if hub and d == Vector2i(0, 1):
				s -= 3.0  # bãi của kho không đặt phía dưới: chỗ đó là tên kho và nhãn tồn kho
			if s > best_score + 0.001 and _dir_ok(id, cell, d, level):
				best = d
				best_score = s
		if best != Vector2i.ZERO:
			return best
	return Vector2i.ZERO

# Hướng d dùng được cho điểm id: ô cổng (và với kho, cả ô bãi ở giữa) đều hợp lệ.
func _dir_ok(id: int, cell: Vector2i, d: Vector2i, level: int) -> bool:
	for k in range(1, _gate_reach(id) + 1):
		if not _gate_ok(cell + d * k, id, level):
			return false
	return true

# Kho có bãi đỗ nên cổng cách kho 2 ô; điểm khác cổng sát bên.
func _gate_reach(id: int) -> int:
	return 2 if _nodes.has(id) and _nodes[id].kind == Types.NodeKind.HUB else 1

# Ô gcell làm cổng cho điểm owner được không. level 0: đủ điều kiện; 1: cho kề điểm khác; 2: cho cả ô ca-nô.
func _gate_ok(gcell: Vector2i, owner: int, level: int) -> bool:
	if not _in_grid(gcell) or cell_is_water(gcell) or _point_cells.has(gcell) or _gate_cells.has(gcell) or _lot_cells.has(gcell):
		return false
	if road_at(gcell) != -1:
		return false
	if level < 2 and cell_is_boat(gcell):
		return false
	return level >= 1 or not _near_point(gcell, owner)

# Ô cell có trùng hoặc kề (8 hướng) một điểm nào khác điểm except không.
func _near_point(cell: Vector2i, except: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var id: int = _point_cells.get(cell + Vector2i(dx, dy), -1)
			if id != -1 and id != except:
				return true
	return false

# Cạnh mới không phát tín hiệu (dùng khi dựng cổng hàng loạt; nơi gọi tự phát road_changed).
func _new_edge(a: int, b: int) -> int:
	var e := Edge.new()
	e.id = _next_edge_id
	_next_edge_id += 1
	e.node_a = a
	e.node_b = b
	e.length = _nodes[a].pos.distance_to(_nodes[b].pos)
	_edges[e.id] = e
	_adj[a].append(e.id)
	_adj[b].append(e.id)
	return e.id

func _is_gated(id: int) -> bool:
	return _nodes.has(id) and _nodes[id].kind != Types.NodeKind.ROAD and _nodes[id].gate != Vector2i.ZERO

# Có cổng thì cạnh giữa from_id và to_id (-1: ô chưa có đường) chỉ được nối nếu đầu là điểm thì đầu kia là ô cổng của nó.
func _gate_allows(from_id: int, to_id: int) -> bool:
	if not _gates_enabled or from_id == -1 or from_id == to_id:
		return true
	if _is_gated(from_id) and to_id != get_gate_node(from_id):
		return false
	return not (to_id != -1 and _is_gated(to_id) and from_id != get_gate_node(to_id))

# Nút ô cổng của điểm, -1 nếu điểm không có cổng.
func get_gate_node(point_id: int) -> int:
	if not _is_gated(point_id):
		return -1
	return road_at(cell_of(_nodes[point_id].pos) + _nodes[point_id].gate * _gate_reach(point_id))

# Nửa cỡ icon của điểm (khớp HUB/DISTRICT/HOUSE_ICON_SIZE của NodeLayer): đường cổng bắt đầu từ mép này, xe giao hàng đỗ
# ngay trước mép này. 0 với ô đường, nút nước.
func point_radius(id: int) -> float:
	var n: MapNode = _nodes.get(id)
	if n == null or n.kind == Types.NodeKind.ROAD:
		return 0.0
	if n.kind == Types.NodeKind.HUB:
		return 28.0
	return 18.0  # khu và nhà cùng cỡ icon 36 px

# Ô bãi đỗ của kho (giữa kho và cổng), Vector2i(-1, -1) nếu kho không có bãi.
func get_lot_cell(hub_id: int) -> Vector2i:
	if not _is_gated(hub_id) or _gate_reach(hub_id) != 2:
		return Vector2i(-1, -1)
	return cell_of(_nodes[hub_id].pos) + _nodes[hub_id].gate

func is_lot_cell(cell: Vector2i) -> bool:
	return _lot_cells.has(cell)

# Hướng từ điểm ra bến: hướng tới một nút nước nối bến, chọn hướng ít chĩa xuống nhất (dưới kho là tên và nhãn hàng),
# rồi hướng ngang rõ nhất. Vector2.ZERO nếu điểm không có bến.
func get_dock_dir(point_id: int) -> Vector2:
	var n: MapNode = _nodes.get(point_id)
	if n == null:
		return Vector2.ZERO
	var best := Vector2.ZERO
	for eid in _badj.get(point_id, []):
		var w: MapNode = get_map_node(_edges[eid].other_end(point_id))
		if w == null or w.kind != Types.NodeKind.WATER or w.pos == n.pos:
			continue
		var dir := (w.pos - n.pos).normalized()
		if best == Vector2.ZERO or dir.y < best.y - 0.01 or (absf(dir.y - best.y) <= 0.01 and absf(dir.x) > absf(best.x)):
			best = dir
	return best

func is_gate_cell(cell: Vector2i) -> bool:
	return _gate_cells.has(cell)

# Ô đặt được nhà: trong lưới, đất liền (không phải ô sông hay ô ca-nô), chưa có đường, không phải điểm hay cổng,
# không kề điểm khác, và có ô cổng hợp lệ chưa có đường.
func can_place_house(cell: Vector2i) -> bool:
	if not _gates_enabled or not _in_grid(cell) or cell_is_water(cell) or cell_is_boat(cell):
		return false
	if road_at(cell) != -1 or _point_cells.has(cell) or _gate_cells.has(cell) or _near_point(cell, -1):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _lot_cells.has(cell + Vector2i(dx, dy)):
				return false  # không đặt nhà sát bãi đỗ của kho
	for d in GATE_DIRS:
		if _gate_ok(cell + d, -1, 1):
			return true
	return false

# Thêm một nhà (điểm DISTRICT không tên) ở ô cell, thuộc khu parent_id. Trả id nhà, -1 nếu ô không hợp lệ.
func add_house(cell: Vector2i, parent_id: int) -> int:
	if not can_place_house(cell):
		return -1
	var n := MapNode.new()
	n.id = _next_house_id
	n.name = ''
	n.kind = Types.NodeKind.DISTRICT
	n.pos = cell_center(cell)
	n.elevation = cell_elevation(cell)
	n.icon = HOUSE_ICONS[randi() % HOUSE_ICONS.size()]
	n.parent = parent_id
	_nodes[n.id] = n
	_adj[n.id] = []
	_points.append(n.id)
	_point_cells[cell] = n.id
	if not _make_gate(n.id, 1):  # can_place_house đã bảo đảm có cổng; phòng hờ thì gỡ lại
		_nodes.erase(n.id)
		_adj.erase(n.id)
		_points.erase(n.id)
		_point_cells.erase(cell)
		return -1
	_next_house_id += 1
	_refresh_segments()
	EventBus.point_added.emit(n.id)
	EventBus.road_changed.emit()
	return n.id

# --- Đoạn: chuỗi cạnh giữa hai đầu mút (điểm, ngã rẽ, ô cụt) ---
# Cả đoạn dùng chung độ cao trung bình các nút nên ngập cùng lúc.
func _refresh_segments() -> void:
	_segments.clear()
	var seen := {}
	for id in _nodes:
		if _is_end(id):
			for eid in _adj[id]:
				if not seen.has(eid):
					_walk(id, eid, seen)
	for eid in _edges:                      # còn lại là vòng kín, không có đầu mút
		if not seen.has(eid) and not _boat_edges.has(eid):
			_walk(_edges[eid].node_a, eid, seen)

func _is_end(id: int) -> bool:
	return _nodes[id].kind != Types.NodeKind.ROAD or _adj[id].size() != 2

func _walk(start: int, first_edge: int, seen: Dictionary) -> void:
	var chain: Array[int] = []
	var sum: float = _nodes[start].elevation
	var count := 1
	var cur := start
	var eid := first_edge
	while not seen.has(eid):
		seen[eid] = true
		chain.append(eid)
		cur = _edges[eid].other_end(cur)
		sum += _nodes[cur].elevation
		count += 1
		if _is_end(cur):
			break
		eid = _adj[cur][0] if _adj[cur][0] != eid else _adj[cur][1]
	var seg: int = chain.min()
	for id in chain:
		_edges[id].segment = seg
		_edges[id].elevation = sum / count
	_segments[seg] = chain

# --- Thêm, xóa, đổi trạng thái cạnh ---
func add_edge(a: int, b: int) -> int:
	if a == b or not _nodes.has(a) or not _nodes.has(b):
		return -1
	for eid in _adj[a]:
		if _edges[eid].other_end(a) == b:
			return -1                       # đã có cạnh giữa hai node
	var e := Edge.new()
	e.id = _next_edge_id
	_next_edge_id += 1
	e.node_a = a
	e.node_b = b
	e.length = _nodes[a].pos.distance_to(_nodes[b].pos)
	_edges[e.id] = e
	_adj[a].append(e.id)
	_adj[b].append(e.id)
	_refresh_segments()
	EventBus.edge_added.emit(e.id)
	EventBus.edge_budget_changed.emit(_roads, _limit)
	EventBus.road_changed.emit()
	return e.id

func remove_edge(edge_id: int) -> void:
	if not _edges.has(edge_id):
		return
	_unlink(edge_id)
	_after_road_edit()

func _unlink(edge_id: int) -> void:
	var e: Edge = _edges[edge_id]
	_adj[e.node_a].erase(edge_id)
	_adj[e.node_b].erase(edge_id)
	_edges.erase(edge_id)
	EventBus.edge_removed.emit(edge_id)

func set_edge_state(edge_id: int, state: int) -> void:
	if not _edges.has(edge_id):
		return
	var e: Edge = _edges[edge_id]
	if e.state == state:
		return                              # chỉ phát tín hiệu khi đổi thật
	e.state = state
	EventBus.edge_state_changed.emit(edge_id, state)

func add_edge_limit(n: int) -> void:
	_limit += n
	EventBus.edge_budget_changed.emit(_roads, _limit)

func get_edge_budget() -> Dictionary:
	return {used = _roads, limit = _limit}

# --- Dijkstra (hàng đợi ưu tiên) ---
# Chi phí cạnh = thời gian đi (giây) theo tốc độ xe và trạng thái cạnh, cộng edge_penalty nếu có.
# Duyệt cả cạnh đường bộ (_adj) lẫn cạnh của ca-nô (_badj); xe tải gặp cạnh boat_only thì hệ số 0, bỏ qua.

# Heap nhị phân nhỏ nhất, mỗi phần tử [chi phí, id nút]. Cho phép đẩy trùng nút (bỏ bản cũ lúc lấy ra).
class MinHeap extends RefCounted:
	var _a: Array = []

	func size() -> int:
		return _a.size()

	func push(cost: float, id: int) -> void:
		_a.append([cost, id])
		var i := _a.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if _a[p][0] <= _a[i][0]:
				break
			var t: Array = _a[p]
			_a[p] = _a[i]
			_a[i] = t
			i = p

	func pop() -> Array:
		var top: Array = _a[0]
		var last: Array = _a.pop_back()
		if not _a.is_empty():
			_a[0] = last
			var i := 0
			var n := _a.size()
			while true:
				var l := 2 * i + 1
				var m := i
				if l < n and _a[l][0] < _a[m][0]:
					m = l
				if l + 1 < n and _a[l + 1][0] < _a[m][0]:
					m = l + 1
				if m == i:
					break
				var t: Array = _a[m]
				_a[m] = _a[i]
				_a[i] = t
				i = m
		return top

# to_id = -1: tính cho mọi nút tới được (cây đường ngắn nhất); khác -1 thì dừng sớm khi tới đích.
func _dijkstra(from_id: int, to_id: int, vehicle_type: int, edge_penalty: Dictionary) -> Dictionary:
	var dist := {from_id: 0.0}
	var prev_node := {}
	var prev_edge := {}
	var done := {}
	var speed: float = Config.base_speed(vehicle_type)
	var heap := MinHeap.new()
	heap.push(0.0, from_id)
	while heap.size() > 0:
		var u: int = heap.pop()[1]
		if done.has(u):
			continue                            # bản cũ của nút đã chốt
		done[u] = true
		if u == to_id:
			break
		if _gates_enabled and vehicle_type == Types.VehicleType.BOAT and u != from_id and _nodes.has(u) and _nodes[u].kind != Types.NodeKind.ROAD:
			continue  # bản đồ có cổng: ca-nô chỉ xuất phát hoặc cập bến ở điểm, không đi xuyên qua (vào bến này ra bến kia là chạy qua đất)
		var du: float = dist[u]
		for list in [_adj.get(u, []), _badj.get(u, [])]:
			for eid in list:
				var e: Edge = _edges[eid]
				var factor := e.speed_factor(vehicle_type)
				if factor <= 0.0:
					continue                    # xe này không đi được cạnh này
				var v := e.other_end(u)
				if done.has(v):
					continue
				var nd := du + e.length / (speed * factor) + float(edge_penalty.get(eid, 0.0))
				if nd < float(dist.get(v, INF)):
					dist[v] = nd
					prev_node[v] = u
					prev_edge[v] = eid
					heap.push(nd, v)
	return {from = from_id, dist = dist, prev_node = prev_node, prev_edge = prev_edge}

# edge_penalty (tùy chọn): số giây cộng thêm cho từng cạnh, RescueManager dùng để né chỗ đang đông xe.
func find_path(from_id: int, to_id: int, vehicle_type: int, edge_penalty: Dictionary = {}) -> PathResult:
	if not _has_node(from_id) or not _has_node(to_id):
		return PathResult.new()
	return path_from_tree(_dijkstra(from_id, to_id, vehicle_type, edge_penalty), from_id, to_id)

# Cây đường ngắn nhất từ from_id tới mọi nút (dist, prev_node, prev_edge). RescueManager tính một lần
# cho mỗi (kho, loại xe) trong một lượt điều phối, rồi lấy đường tới từng SOS bằng path_from_tree.
func shortest_tree(from_id: int, vehicle_type: int, edge_penalty: Dictionary = {}) -> Dictionary:
	if not _has_node(from_id):
		return {from = from_id, dist = {}, prev_node = {}, prev_edge = {}}
	return _dijkstra(from_id, -1, vehicle_type, edge_penalty)

func path_from_tree(tree: Dictionary, from_id: int, to_id: int) -> PathResult:
	var res := PathResult.new()
	var dist: Dictionary = tree.get('dist', {})
	if int(tree.get('from', -1)) != from_id or not dist.has(to_id):
		return res
	var prev_node: Dictionary = tree.prev_node
	var prev_edge: Dictionary = tree.prev_edge
	var cur := to_id
	while cur != from_id:
		res.node_ids.push_front(cur)
		res.edge_ids.push_front(prev_edge[cur])
		cur = prev_node[cur]
	res.node_ids.push_front(from_id)
	res.found = true
	res.cost = dist[to_id]
	return res

# --- Đồ thị của ca-nô: sông (grid.boat), bến, lối xuống nước ---
# Dựng lại toàn bộ: nút nước cho mọi ô ca-nô, cạnh sông (luôn DEEP), bến cho mọi điểm sát sông,
# lối xuống nước cho mọi ô đường sát sông. Gọi sau khi nạp bản đồ và sau game_started.
# Bản đồ có grid.boat_pos / grid.boat_links (tính sẵn từ ảnh độ cao): nút nước đặt ở tâm phần sông của ô (không phải tâm ô,
# vì ô ca-nô chỉ cần 10% là sông nên tâm ô hay nằm trên đất), cạnh sông chỉ gồm các đoạn đã kiểm tra nằm trên sông,
# đoạn qua khúc quanh thì vòng qua một nút điểm gãy. Không có hai khóa đó thì như cũ: tâm ô, nối 8 hướng.
func _build_water() -> void:
	for eid in _boat_edges:
		_edges.erase(eid)
	_boat_edges.clear()
	_flood_links.clear()
	_badj.clear()
	_water.clear()
	_next_boat_edge = 0
	var at := {}  # chỉ số ô -> vị trí nút nước trên sông
	for e in _boat_pos:
		at[int(e[0])] = Vector2(float(e[1]), float(e[2]))
	for i in _cell_boat.size():
		if int(_cell_boat[i]) != 1:
			continue
		var n := MapNode.new()
		n.id = WATER_ID_BASE + i
		n.kind = Types.NodeKind.WATER
		n.pos = at.get(i, cell_center(Vector2i(i % Config.GRID_COLS, i / Config.GRID_COLS)))
		_water[n.id] = n
	if _boat_links.is_empty():
		for id in _water.keys():
			var c := cell_of(_water[id].pos)
			for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:  # mỗi cặp kề chỉ xét một lần
				var other := _water_at(c + d)
				if other != -1:
					_add_boat_edge(id, other, Types.EdgeState.DEEP, false)
	else:
		var via := 0
		for l in _boat_links:
			var a: int = WATER_ID_BASE + int(l[0])
			var b: int = WATER_ID_BASE + int(l[1])
			if not (_water.has(a) and _water.has(b)):
				continue
			if l.size() >= 4:  # vòng qua điểm gãy trên sông
				var m := MapNode.new()
				m.id = WATER_VIA_BASE + via
				via += 1
				m.kind = Types.NodeKind.WATER
				m.pos = Vector2(float(l[2]), float(l[3]))
				_water[m.id] = m
				_add_boat_edge(a, m.id, Types.EdgeState.DEEP, false)
				_add_boat_edge(m.id, b, Types.EdgeState.DEEP, false)
			else:
				_add_boat_edge(a, b, Types.EdgeState.DEEP, false)
	for p in _points:
		_add_docks(p)
	for id in _nodes:
		if _nodes[id].kind == Types.NodeKind.ROAD:
			_link_road_to_water(id)

# Nút nước tại ô, hoặc -1.
func _water_at(cell: Vector2i) -> int:
	if not _in_grid(cell):
		return -1
	var id := WATER_ID_BASE + _cell_index(cell)
	return id if _water.has(id) else -1

func _add_boat_edge(a: int, b: int, state: int, flood_link: bool) -> int:
	var e := Edge.new()
	e.id = BOAT_EDGE_ID_BASE + _next_boat_edge
	_next_boat_edge += 1
	e.node_a = a
	e.node_b = b
	e.length = get_map_node(a).pos.distance_to(get_map_node(b).pos)
	e.state = state
	e.boat_only = true
	_edges[e.id] = e
	_boat_edges[e.id] = true
	if flood_link:
		_flood_links[e.id] = true
	for id in [a, b]:
		if not _badj.has(id):
			_badj[id] = []
		_badj[id].append(e.id)
	return e.id

func _boat_linked(a: int, b: int) -> bool:
	for eid in _badj.get(a, []):
		if _edges[eid].other_end(a) == b:
			return true
	return false

# Bến: điểm (kho, khu, nhà) có chính ô của nó hoặc ô kề 8 hướng là ô ca-nô thì nối với các nút nước đó (luôn DEEP).
# Gọi khi dựng lại đồ thị ca-nô và khi có nhà mới (EventBus.point_added).
func _add_docks(point_id: int) -> void:
	var n: MapNode = _nodes.get(point_id)
	if n == null or n.kind == Types.NodeKind.ROAD:
		return
	var c := cell_of(n.pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var w := _water_at(c + Vector2i(dx, dy))
			if w != -1 and not _boat_linked(point_id, w):
				_add_boat_edge(point_id, w, Types.EdgeState.DEEP, false)

# Các nút nước nối bến với điểm point_id (ca-nô cập bến đỗ trên nước tại đây), rỗng nếu điểm không có bến.
func get_dock_nodes(point_id: int) -> Array[int]:
	var out: Array[int] = []
	if not _nodes.has(point_id) or _nodes[point_id].kind == Types.NodeKind.ROAD:
		return out
	for eid in _badj.get(point_id, []):
		var w: int = _edges[eid].other_end(point_id)
		if _water.has(w):
			out.append(w)
	return out

# Các nút nước nối với nút nước id bằng cạnh sông (để xếp thêm chỗ neo ca-nô cạnh bến).
func get_water_neighbors(id: int) -> Array[int]:
	var out: Array[int] = []
	for eid in _badj.get(id, []):
		var w: int = _edges[eid].other_end(id)
		if _water.has(w):
			out.append(w)
	return out

# Điểm có bến: ca-nô cập được mà không cần đường ngập.
func has_dock(point_id: int) -> bool:
	return not _badj.get(point_id, []).is_empty() and _nodes.has(point_id) and _nodes[point_id].kind != Types.NodeKind.ROAD

# Lối xuống nước: ô đường kề 8 hướng với ô ca-nô (không tính chính ô của nó, ô cầu không nối xuống sông bên dưới).
# Trạng thái cạnh theo độ ngập của ô đường (FloodManager đặt), khô thì ca-nô không qua.
func _link_road_to_water(road_id: int) -> void:
	var c := cell_of(_nodes[road_id].pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var w := _water_at(c + Vector2i(dx, dy))
			if w != -1 and not _boat_linked(road_id, w):
				_add_boat_edge(road_id, w, Types.EdgeState.DRY, true)

# Gỡ lối xuống nước của ô đường sắp xóa; phát edge_removed để xe đang đi trên đó tính lại đường.
func _unlink_road_from_water(road_id: int) -> void:
	for eid in _badj.get(road_id, []).duplicate():
		var e: Edge = _edges[eid]
		var w := e.other_end(road_id)
		_badj[w].erase(eid)
		_edges.erase(eid)
		_boat_edges.erase(eid)
		_flood_links.erase(eid)
		EventBus.edge_removed.emit(eid)
	_badj.erase(road_id)

# Cạnh lối xuống nước (node_a là ô đường), để FloodManager đặt trạng thái theo độ ngập ô đường.
func get_flood_links() -> Array[int]:
	var out: Array[int] = []
	for k in _flood_links:
		out.append(k)
	return out
