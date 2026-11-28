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
const FERRY_EDGE_ID_BASE := 200000  # mã cạnh phà phao vượt sông cho xe tải (Feature D)

const HIGHWAY_EDGE_ID_BASE := 300000
const ITEM_TRAFFIC_LIGHT := 5
const ITEM_ROUNDABOUT := 6
const ITEM_HIGHWAY := 7
const ITEM_FERRY := 8
const HIGHWAY_CURVE_RATIO := 0.22
const HIGHWAY_CURVE_MAX_CELLS := 3.0
const HIGHWAY_SAMPLE_STEP_CELLS := 0.5

var _editing_infrastructure := false  # inventory and graph signals are synchronous
var _traffic_lights := {}
var _placed_rings := {}      # original junction id -> footprint, ports and suspended edges
var _ring_footprint := {}   # reserved cell -> original junction id
var _highways := {}
var _highway_adj := {}
var _next_highway := HIGHWAY_EDGE_ID_BASE

var _nodes := {}        # id -> MapNode (cả điểm trên bản đồ và ô đường)
var _edges := {}        # id -> Edge
var _adj := {}          # id node -> Array các id cạnh kề
var _next_edge_id := 0
var _limit := 0
var _points: Array[int] = []    # các điểm trên bản đồ, theo thứ tự trong json
var _point_cells := {}          # ô -> id điểm
var _cell_elevation: Array = [] # độ cao từng ô, khóa "grid" của bản đồ
var _cell_water: Array = []     # 1 nếu ô là sông (grid.water), bản đồ không có thì rỗng
var _cell_boat: Array = []      # 1 nếu ca-nô đi được trên ô (grid.boat), rỗng nếu bản đồ không có
var _deep_flood_lowlands := {}  # grid.deep_flood_lowland: row-major indices
var _cell_bank: Array = []      # 1 nếu ô đất là mép sông (grid.bank: sông thật phủ từ 10% ô), nhà không mọc ở đó
var _cell_spill: Array = []     # grid.spill: ngưỡng tràn từng ô tính sẵn (FloodManager dùng khi nước rút), rỗng nếu map không có
var _boat_pos: Array = []       # grid.boat_pos: [chỉ số ô, x, y] vị trí nút nước (tâm phần sông trong ô, luôn trên sông)
var _boat_links: Array = []     # grid.boat_links: [i, j] hoặc [i, j, x, y] (vòng qua điểm gãy) — cạnh sông đã kiểm tra nằm trên sông
var _gates_enabled := false     # khóa "gates": mỗi điểm có một ô cổng, đường chỉ nối vào điểm qua ô đó
var _stages: Array = []         # khóa "stages": vùng camera theo đợt (GameManager dùng)
var _terrain: Dictionary = {}   # khóa "terrain" của bản đồ: ảnh độ cao và màu nước cho FloodOverlay
var _roads := 0                 # số ô đường đã tô
var _segments := {}             # id đoạn -> Array các id cạnh
var _rings: Array = []          # vòng xoay người chơi vẽ: [{center: Vector2, size: 2 | 3, nodes: Array id ô đường}]
var _ring_of := {}              # id ô đường -> chỉ số vòng trong _rings
var _ring_from := {}            # id cạnh vòng -> nút được đi từ đó (vòng một chiều, ngược kim đồng hồ trên màn hình)
var _shortcuts := {}            # Vector2i(a, b) (a < b) -> id cạnh tắt của ca-nô trên nước thoáng (không nằm trong đồ thị tìm đường)
var _gate_cells := {}           # ô cổng -> id điểm (ô cổng là ô đường dựng sẵn, không tính hạn mức, không xóa được)
var _lot_cells := {}            # ô bãi đỗ -> id kho: kho có bãi nằm giữa kho và cổng (kho, bãi, cổng thẳng hàng)
var _gate_override := {}        # id điểm -> hướng cổng ghi trong json (trường "gate": "E"/"W"/"N"/"S")
var _next_house_id := HOUSE_ID_BASE
# Đồ thị riêng của ca-nô: nút nước và cạnh boat_only (sông, bến, lối xuống nước). Không nằm trong _nodes/_adj,
# nên các module vẽ đường, tính lũ, tính ngã ba không thấy; chỉ find_path và xe dùng.
var _water := {}                # id nút nước -> MapNode (kind WATER)
var _badj := {}                 # id node -> Array id cạnh boat_only kề
var _boat_edges := {}           # id cạnh boat_only -> true
var _channel_open := {}        # marked land cells -> whether navigation depth is sufficient
var _boat_edge_channels := {}  # edge id -> seasonal cells that must all be open
var _flood_links := {}          # road-to-water connector ids
var _next_boat_edge := 0        # mã cạnh ca-nô kế tiếp = BOAT_EDGE_ID_BASE + số này
var _ferry_edges := {}              # edge id phà -> Edge
var _fadj := {}                     # id node -> Array id cạnh phà kề (đồ thị riêng của phà phao, không chung _adj để không vẽ nhầm mặt đường)
var _ferry_routes: Array = []       # danh sách thông tin các tuyến phà hiện có
var _next_ferry_edge := 0

func _ready() -> void:
	_limit = Config.EDGE_LIMIT_START
	EventBus.game_started.connect(_on_game_started)
	EventBus.point_added.connect(_add_docks)
	EventBus.water_level_changed.connect(func(_l: float) -> void: _update_ferry_fallbacks())

func _on_game_started() -> void:
	_clear_edges()
	_build_gates()
	EventBus.edge_budget_changed.emit(0, _limit)
	_build_water()

func _clear_edges() -> void:
	_edges.clear()
	_traffic_lights.clear()
	_placed_rings.clear()
	_ring_footprint.clear()
	_rings.clear()
	_ring_of.clear()
	_ring_from.clear()
	_highways.clear()
	_highway_adj.clear()
	_next_highway = HIGHWAY_EDGE_ID_BASE
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
	_channel_open.clear()
	_boat_edge_channels.clear()
	_shortcuts.clear()
	# --- Dọn dữ liệu phà phao ---
	for eid in _ferry_edges.keys():
		_edges.erase(eid)
	_ferry_edges.clear()
	_fadj.clear()
	_ferry_routes.clear()
	_next_ferry_edge = 0
	_emit_ferry_inventory()

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
	_cell_spill = data.get('grid', {}).get('spill', [])
	_cell_boat = data.get('grid', {}).get('boat', [])
	_deep_flood_lowlands.clear()
	for index in data.get('grid', {}).get('deep_flood_lowland', []):
		_deep_flood_lowlands[int(index)] = true
	_cell_bank = data.get('grid', {}).get('bank', [])
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

# Chỉ cạnh đường bộ (đường–đường, điểm–đường); cạnh boat_only của ca-nô và cạnh phà không có ở đây.
func get_edge_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _edges.keys():
		if not _boat_edges.has(k) and not _ferry_edges.has(k) and not _highways.has(k) and not _edges[k].suspended:
			out.append(k)
	return out

func get_edges_of(node_id: int) -> Array[int]:
	var out: Array[int] = []
	for k in _adj.get(node_id, []):
		if not _edges[k].suspended:
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
	if _edges.has(edge_id) and not _edges[edge_id].suspended:
		out.assign(_segments.get(_edges[edge_id].segment, []))
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

# Permanent mapped water. Seasonal channels are queried separately.
func cell_is_boat(cell: Vector2i) -> bool:
	return cell_is_water(cell)


func is_boat_route_cell(cell: Vector2i) -> bool:
	var i := _cell_index(cell)
	return cell_is_boat(cell) or (_in_grid(cell) and i < _cell_boat.size() and int(_cell_boat[i]) == 1)


func is_boat_route_open(cell: Vector2i) -> bool:
	return cell_is_boat(cell) or _channel_open.get(cell, false)


func is_deep_flood_lowland(cell: Vector2i) -> bool:
	return _in_grid(cell) and _deep_flood_lowlands.has(_cell_index(cell))


# Ô đất ở mép sông (lớp grid.bank): nhà không mọc ở đây. Bản đồ không có lớp này thì không ô nào.
func cell_is_bank(cell: Vector2i) -> bool:
	var i := _cell_index(cell)
	return _in_grid(cell) and i < _cell_bank.size() and int(_cell_bank[i]) == 1

# Bản đồ bật cổng (khóa "gates"): mỗi điểm có một ô cổng, xe vào và ra điểm chỉ qua ô đó.
func uses_gates() -> bool:
	return _gates_enabled

# Các vùng chơi theo đợt [{center: [x, y], zoom}], rỗng nếu bản đồ không khai báo.
func get_stages() -> Array:
	return _stages

# Ảnh độ cao chi tiết và màu nước của bản đồ (rỗng nếu bản đồ không khai báo).
# Ngưỡng tràn tính sẵn của map (theo chỉ số ô), rỗng nếu map không có.
func get_spill() -> Array:
	return _cell_spill


func get_terrain() -> Dictionary:
	return _terrain

# Nút ô đường tại ô, hoặc -1 nếu ô chưa tô.
func road_at(cell: Vector2i) -> int:
	if not _in_grid(cell):
		return -1
	var id := _road_id(cell)
	return id if _nodes.has(id) else -1

# Nút bản đồ tại ô (điểm công trình hoặc ô đường), hoặc -1.
func get_node_at_cell(cell: Vector2i) -> int:
	return _point_cells.get(cell, road_at(cell))

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
	if _editing_infrastructure or not _in_grid(cell) or _lot_cells.has(cell) or not _allows_ring_port(cell):
		return -1  # ngoài lưới, hoặc ô bãi đỗ của kho
	if from_id != -1 and not (_nodes.has(from_id) and _next_to(cell_of(_nodes[from_id].pos), cell)):
		return -1
	if from_id != -1:
		var from := cell_of(_nodes[from_id].pos)
		if not diagonal_ok(from, cell) or not _can_connect_ring_cells(from, cell):
			return -1
	var to_id: int = _point_cells.get(cell, road_at(cell))
	if not _gate_allows(from_id, to_id, cell):
		return -1  # có cổng: kho chỉ nối qua ô cổng; khu, nhà chỉ một lối vào, nối từ một cạnh
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

func _add_road(cell: Vector2i, use_budget := true) -> int:
	var n := MapNode.new()
	n.id = _road_id(cell)
	n.kind = Types.NodeKind.ROAD
	n.pos = cell_center(cell)
	var i := _cell_index(cell)
	n.elevation = _cell_elevation[i] if i < _cell_elevation.size() else 0.0
	_nodes[n.id] = n
	_adj[n.id] = []
	if use_budget:
		_roads += 1
	_link_road_to_water(n.id)
	return n.id

# Xóa ô đường và các cạnh nối vào nó, hoàn 1 hạn mức. Trả false nếu ô không có đường.
func remove_road(cell: Vector2i) -> bool:
	if _editing_infrastructure:
		return false
	_editing_infrastructure = true
	var removed := _remove_road(cell)
	_editing_infrastructure = false
	return removed


func _remove_road(cell: Vector2i) -> bool:
	var id := road_at(cell)
	if id == -1 or _gate_cells.has(cell):
		return false  # ô cổng thuộc về điểm, không xóa được
	if _ring_footprint.has(cell):
		var center: int = _ring_footprint[cell]
		var original: bool = id == center or not _placed_rings[center].created.has(id)
		_remove_roundabout(center)
		if not original:
			return true
	for route_id in _highway_adj.get(id, []).duplicate():
		_remove_highway(route_id)
	for route in _ferry_routes.duplicate():
		if route.node_a == id or route.node_b == id:
			_remove_ferry_route(route)
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
	_refund_invalid_lights()
	EventBus.edge_budget_changed.emit(_roads, _limit)
	EventBus.road_changed.emit()

# --- Cổng và nhà (chỉ khi bản đồ bật "gates") ---
# Kho: ô bãi rồi ô cổng thẳng hàng; ô cổng là ô đường dựng sẵn (không tính hạn mức, không xóa được), đường chỉ nối
# vào kho qua ô cổng. Khu, nhà (như nhà trong Mini Motorways): không dựng sẵn ô nào, chỉ có lối vào ngắn nhô ra một chút
# theo hướng gate; vẽ đường vào từ cạnh nào (4 hướng) cũng được, lối vào xoay về phía đó. Mỗi điểm chỉ một lối vào,
# nên xe không đi xuyên qua nhà.
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
	if n.kind != Types.NodeKind.HUB:
		return true  # khu, nhà: chỉ hướng lối vào mặc định, không dựng ô cổng
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

# Hướng d dùng được cho điểm id: kho cần ô bãi và ô cổng hợp lệ; khu, nhà chỉ cần ô trước lối vào không phải sông,
# điểm khác hay bãi (ô đó có đường sẵn cũng được: nhà mọc cạnh đường thì lối vào chĩa ra đường).
func _dir_ok(id: int, cell: Vector2i, d: Vector2i, level: int) -> bool:
	if _nodes.has(id) and _nodes[id].kind != Types.NodeKind.HUB:
		return _drive_ok(cell + d)
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

# Luật không cắt góc (bản đồ có cổng): bước chéo từ ô a sang ô b chạy qua góc chung của hai ô kề còn lại; đường rộng
# nên lấn vào góc hai ô đó. Không cho đi chéo nếu một trong hai ô góc đó là điểm khác (không phải a hay b) hay bãi kho.
# Cho phép đi thẳng vào/ra nhà theo đường chéo nếu chính ô nhà là a hoặc b.
func diagonal_ok(a: Vector2i, b: Vector2i) -> bool:
	if not _gates_enabled or absi(a.x - b.x) != 1 or absi(a.y - b.y) != 1:
		return true
	for c in [Vector2i(a.x, b.y), Vector2i(b.x, a.y)]:
		if _lot_cells.has(c):
			return false
		var pid: int = _point_cells.get(c, -1)
		if pid != -1:
			# chặn chỉ khi ô góc là điểm khác (không phải ô a hay ô b)
			var cpa: int = _point_cells.get(a, -1)
			var cpb: int = _point_cells.get(b, -1)
			if pid != cpa and pid != cpb:
				return false
	return true

# Ô cell đang bị một đoạn đường chéo cắt qua góc (đoạn nối hai ô kề cạnh của nó theo đường chéo).
func _corner_cut(cell: Vector2i) -> bool:
	for d in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var a := road_at(cell + Vector2i(d.x, 0))
		var b := road_at(cell + Vector2i(0, d.y))
		if a == -1 or b == -1:
			continue
		for eid in _adj[a]:
			if _edges[eid].other_end(a) == b:
				return true
	return false

# Ô trước lối vào của khu, nhà: trong lưới, không phải ô sông, ô của điểm, ô cổng hay ô bãi của kho.
func _drive_ok(c: Vector2i) -> bool:
	return _in_grid(c) and not cell_is_water(c) and not _point_cells.has(c) and not _gate_cells.has(c) and not _lot_cells.has(c)

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

# Có cổng thì cạnh giữa from_id và ô cell (nút to_id, -1 nếu ô chưa có đường) chỉ được nối nếu:
# - kho: đầu kia là ô cổng của kho;
# - khu, nhà: đầu kia kề cạnh (4 hướng), và điểm chưa nối đường nào (hoặc đang nối đúng ô đó); không nối thẳng hai điểm.
func _gate_allows(from_id: int, to_id: int, cell: Vector2i) -> bool:
	if not _gates_enabled or from_id == -1 or from_id == to_id:
		return true
	if _is_gated(from_id) and _is_gated(to_id):
		return false  # hai điểm phải nối qua ít nhất một ô đường
	if _is_gated(from_id) and not _point_link_ok(from_id, to_id, cell):
		return false
	return not (to_id != -1 and _is_gated(to_id) and not _point_link_ok(to_id, from_id, cell_of(_nodes[from_id].pos)))

# Điểm p (có cổng) nối được với ô other_cell (nút other_id, -1 nếu chưa có đường) không.
func _point_link_ok(p: int, other_id: int, other_cell: Vector2i) -> bool:
	if _nodes[p].kind == Types.NodeKind.HUB:
		return other_id != -1 and other_id == get_gate_node(p)
	var d := other_cell - cell_of(_nodes[p].pos)
	if absi(d.x) > 1 or absi(d.y) > 1 or (d.x == 0 and d.y == 0):
		return false  # cho phép cả 8 hướng kề cạnh (4 thẳng và 4 chéo)
	var linked := get_gate_node(p)
	return linked == -1 or (other_id != -1 and linked == other_id)

# Khu, nhà vừa nối đường: lối vào xoay về phía ô đường đó (như nhà trong Mini Motorways).
func _turn_driveway(p: int, other: int) -> void:
	if not _is_gated(p) or _nodes[p].kind == Types.NodeKind.HUB or not _nodes.has(other):
		return
	var d := cell_of(_nodes[other].pos) - cell_of(_nodes[p].pos)
	if absi(d.x) <= 1 and absi(d.y) <= 1 and (d.x != 0 or d.y != 0):
		_nodes[p].gate = d

# Nút đường ngay trước lối vào của điểm: kho là ô cổng dựng sẵn; khu, nhà là ô đường đang nối vào (-1 nếu chưa nối).
# -1 nếu điểm không có cổng.
func get_gate_node(point_id: int) -> int:
	if not _is_gated(point_id):
		return -1
	if _nodes[point_id].kind != Types.NodeKind.HUB:
		for eid in _adj.get(point_id, []):
			return _edges[eid].other_end(point_id)
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
	return 16.0  # khu và nhà: nửa lô đất 32 px (icon 30 px nằm trong lô)

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

func is_point_cell(cell: Vector2i) -> bool:
	return _point_cells.has(cell)

# Ô đặt được nhà: trong lưới, đất liền (không phải ô sông, ô ca-nô hay mép sông), chưa có đường, không phải điểm hay cổng,
# không kề điểm khác, không sát bãi kho, và có một hướng hợp lệ cho lối vào (nhà mọc sát đường cũng được).
func can_place_house(cell: Vector2i) -> bool:
	if not _gates_enabled or not _in_grid(cell) or cell_is_water(cell) or cell_is_boat(cell) or cell_is_bank(cell):
		return false
	if road_at(cell) != -1 or _point_cells.has(cell) or _gate_cells.has(cell) or _near_point(cell, -1) or _corner_cut(cell):
		return false  # (gồm ô đang bị đường chéo cắt góc: nhà đặt vào sẽ đè lên đường)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _lot_cells.has(cell + Vector2i(dx, dy)):
				return false  # không đặt nhà sát bãi đỗ của kho
	for d in GATE_DIRS:
		if _drive_ok(cell + d):
			return true  # có hướng cho lối vào
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
			for eid in get_edges_of(id):
				if not seen.has(eid):
					_walk(id, eid, seen)
	for eid in _edges:                      # còn lại là vòng kín, không có đầu mút
		if not seen.has(eid) and not _boat_edges.has(eid) and not _ferry_edges.has(eid) and not _highways.has(eid) and not _edges[eid].suspended:
			_walk(_edges[eid].node_a, eid, seen)
	_detect_rings()

# Rebuild directional lookup tables from placed roundabouts.
func _detect_rings() -> void:
	_rings.clear()
	_ring_of.clear()
	_ring_from.clear()
	for junction_id in _placed_rings:
		var ring: Dictionary = _placed_rings[junction_id]
		var idx := _rings.size()
		_rings.append({junction_id = junction_id, center = ring.center, size = 3, nodes = ring.nodes})
		for i in ring.nodes.size():
			_ring_of[ring.nodes[i]] = idx
			_ring_from[ring.edges[i]] = ring.nodes[i]


func _edge_between(a: int, b: int) -> int:
	for eid in _adj.get(a, []):
		if _edges[eid].other_end(a) == b:
			return eid
	return -1

# Chỉ số vòng xoay chứa ô đường node_id, -1 nếu không thuộc vòng nào.
func ring_of(node_id: int) -> int:
	return _ring_of.get(node_id, -1)

func is_ring_edge(edge_id: int) -> bool:
	return _ring_from.has(edge_id)

# Nút được đi từ đó trên cạnh vòng (đi theo chiều vòng), -1 nếu không phải cạnh vòng.
func ring_from(edge_id: int) -> int:
	return _ring_from.get(edge_id, -1)

func get_rings() -> Array:
	return _rings.duplicate(true)

func _is_end(id: int) -> bool:
	if not _nodes.has(id):
		return true
	return _nodes[id].kind != Types.NodeKind.ROAD or get_edges_of(id).size() != 2

func _walk(start: int, first_edge: int, seen: Dictionary) -> void:
	var chain: Array[int] = []
	var start_node := get_map_node(start)
	if start_node == null:
		return
	var sum: float = start_node.elevation
	var count := 1
	var cur := start
	var eid := first_edge
	while not seen.has(eid):
		seen[eid] = true
		chain.append(eid)
		cur = _edges[eid].other_end(cur)
		var cur_node := get_map_node(cur)
		if cur_node != null:
			sum += cur_node.elevation
		count += 1
		if _is_end(cur):
			break
		var cur_adj := get_edges_of(cur)
		if cur_adj.size() < 2:
			break
		eid = cur_adj[0] if cur_adj[0] != eid else cur_adj[1]
	var seg: int = chain.min()
	for id in chain:
		_edges[id].segment = seg
		_edges[id].elevation = sum / count
	_segments[seg] = chain

# --- Thêm, xóa, đổi trạng thái cạnh ---
func add_edge(a: int, b: int) -> int:
	if _editing_infrastructure or a == b or not _nodes.has(a) or not _nodes.has(b):
		return -1
	var cell_a := cell_of(_nodes[a].pos)
	var cell_b := cell_of(_nodes[b].pos)
	if not _can_connect_ring_cells(cell_a, cell_b):
		return -1
	for eid in _adj[a]:
		if _edges[eid].other_end(a) == b:
			return -1                       # đã có cạnh giữa hai node
	var id := _insert_road_edge(a, b)
	_turn_driveway(a, b)
	_turn_driveway(b, a)
	_refresh_segments()
	EventBus.edge_added.emit(id)
	EventBus.edge_budget_changed.emit(_roads, _limit)
	EventBus.road_changed.emit()
	return id


func _insert_road_edge(a: int, b: int) -> int:
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


func remove_edge(edge_id: int) -> void:
	if _editing_infrastructure:
		return
	_editing_infrastructure = true
	_remove_edge(edge_id)
	_editing_infrastructure = false


func _remove_edge(edge_id: int) -> void:
	if not _edges.has(edge_id):
		return
	if _highways.has(edge_id):
		_remove_highway(edge_id)
		return
	if _boat_edges.has(edge_id) or _ferry_edges.has(edge_id):
		return
	var edge := get_edge(edge_id)
	for node_id in [edge.node_a, edge.node_b]:
		var cell := cell_of(_nodes[node_id].pos)
		if _ring_footprint.has(cell) and (edge.suspended or is_ring_edge(edge_id)):
			_remove_roundabout(_ring_footprint[cell])
			break
	if _edges.has(edge_id):
		_unlink(edge_id)
	_after_road_edit()

func _unlink(edge_id: int, notify := true) -> void:
	var e: Edge = _edges[edge_id]
	_adj[e.node_a].erase(edge_id)
	_adj[e.node_b].erase(edge_id)
	_edges.erase(edge_id)
	if notify:
		EventBus.edge_removed.emit(edge_id)

# quiet: đổi mà không phát tín hiệu (FloodManager đổi hàng loạt cạnh vùng ngập rồi tự phát một lần). Trả true nếu đổi thật.
func set_edge_state(edge_id: int, state: int, quiet: bool = false) -> bool:
	if not _edges.has(edge_id):
		return false
	var e: Edge = _edges[edge_id]
	if e.state == state:
		return false                        # chỉ phát tín hiệu khi đổi thật
	e.state = state
	if not quiet:
		EventBus.edge_state_changed.emit(edge_id, state)
	return true

# IDs follow the shared Reward contract until C adds the enum entries.
func _inventory_ready() -> bool:
	return GameManager.has_method("get_inventory") and GameManager.has_method("try_consume_item") and GameManager.has_method("refund_item")


func _consume_item(id: int) -> bool:
	return _inventory_ready() and bool(GameManager.call("try_consume_item", id))


func _refund_item(id: int) -> void:
	if _inventory_ready():
		GameManager.call("refund_item", id)


# Validate before consumption; commit validates again against the current graph.
# A negative commit result means that no graph change was made.
func _place_item(reward_id: int, commit: Callable) -> int:
	if _editing_infrastructure:
		return -1
	_editing_infrastructure = true
	var id := -1
	if _consume_item(reward_id):
		id = int(commit.call())
		if id == -1:
			_refund_item(reward_id)
	_editing_infrastructure = false
	return id


func has_traffic_light(junction_id: int) -> bool:
	return _traffic_lights.has(junction_id)


func can_place_traffic_light(junction_id: int) -> bool:
	return _nodes.has(junction_id) and _nodes[junction_id].kind == Types.NodeKind.ROAD \
			and get_edges_of(junction_id).size() >= 3 and not _ring_footprint.has(cell_of(_nodes[junction_id].pos)) \
			and not has_traffic_light(junction_id)


func place_traffic_light(junction_id: int) -> bool:
	return can_place_traffic_light(junction_id) and _place_item(ITEM_TRAFFIC_LIGHT, _commit_traffic_light.bind(junction_id)) != -1


func _commit_traffic_light(junction_id: int) -> int:
	if not can_place_traffic_light(junction_id):
		return -1
	_traffic_lights[junction_id] = true
	EventBus.road_changed.emit()
	return junction_id


func _refund_invalid_lights() -> void:
	for id in _traffic_lights.keys():
		if get_edges_of(id).size() < 3 and _traffic_lights.erase(id):
			_refund_item(ITEM_TRAFFIC_LIGHT)


func _allows_ring_port(cell: Vector2i) -> bool:
	if not _ring_footprint.has(cell):
		return true
	var center: int = _ring_footprint[cell]
	var id := road_at(cell)
	return id != center and not _placed_rings[center].created.has(id)


func _can_connect_ring_cells(a: Vector2i, b: Vector2i) -> bool:
	if not _allows_ring_port(a) or not _allows_ring_port(b):
		return false
	var ring_a := roundabout_at_cell(a)
	return ring_a == -1 or ring_a != roundabout_at_cell(b)


func _roundabout_cells(center: Vector2i) -> Array[Vector2i]:
	return [center + Vector2i(-1, -1), center + Vector2i(0, -1), center + Vector2i(1, -1),
		center + Vector2i(1, 0), center + Vector2i(1, 1), center + Vector2i(0, 1),
		center + Vector2i(-1, 1), center + Vector2i(-1, 0)]


func can_place_roundabout(junction_id: int) -> bool:
	if not _nodes.has(junction_id) or _nodes[junction_id].kind != Types.NodeKind.ROAD or has_traffic_light(junction_id):
		return false
	var center := cell_of(_nodes[junction_id].pos)
	var branches: Array = _adj[junction_id]
	if branches.size() < 3 or branches.size() > 4 or _ring_footprint.has(center) or _gate_cells.has(center) \
			or not _highway_adj.get(junction_id, []).is_empty() or not _fadj.get(junction_id, []).is_empty():
		return false
	var ports := {}
	for eid in branches:
		var port := get_edge(eid).other_end(junction_id)
		if not _nodes.has(port) or _nodes[port].kind != Types.NodeKind.ROAD or not _next_to(center, cell_of(_nodes[port].pos)):
			return false
		ports[port] = true
	var cells := _roundabout_cells(center)
	cells.append(center)
	for cell in cells:
		if not _in_grid(cell) or _point_cells.has(cell) or _lot_cells.has(cell) or _gate_cells.has(cell) \
				or _ring_footprint.has(cell) or is_boat_route_cell(cell):
			return false
		var occupant := road_at(cell)
		if cell == center or occupant == -1:
			continue
		if not ports.has(occupant) or has_traffic_light(occupant):
			return false
		for eid in _adj[occupant]:
			if ports.has(get_edge(eid).other_end(occupant)):
				return false
	return true


func place_roundabout(junction_id: int) -> bool:
	return can_place_roundabout(junction_id) and _place_item(ITEM_ROUNDABOUT, _commit_roundabout.bind(junction_id)) != -1


func _commit_roundabout(junction_id: int) -> int:
	if not can_place_roundabout(junction_id):
		return -1
	var center := cell_of(_nodes[junction_id].pos)
	var cells := _roundabout_cells(center)
	var ring := {center = cell_center(center), nodes = [], edges = [], created = [], original = _adj[junction_id].duplicate()}
	for cell in cells:
		var id := road_at(cell)
		if id == -1:
			id = _add_road(cell, false)  # the entire ring is paid by one item
			ring.created.append(id)
		_ring_footprint[cell] = junction_id
		ring.nodes.append(id)
	for eid in ring.original:
		get_edge(eid).suspended = true
	_ring_footprint[center] = junction_id
	for i in ring.nodes.size():
		ring.edges.append(_insert_road_edge(ring.nodes[i], ring.nodes[(i + 1) % ring.nodes.size()]))
	_placed_rings[junction_id] = ring
	_refresh_segments()
	RescueManager.remap_roundabout_vehicles([junction_id], ring.nodes)
	for eid in ring.original:
		EventBus.edge_state_changed.emit(eid, get_edge(eid).state)
	for eid in ring.edges:
		EventBus.edge_added.emit(eid)
	EventBus.road_changed.emit()
	return junction_id


func remove_roundabout(junction_id: int) -> bool:
	if _editing_infrastructure:
		return false
	_editing_infrastructure = true
	var removed := _remove_roundabout(junction_id)
	_editing_infrastructure = false
	return removed


func roundabout_at_cell(cell: Vector2i) -> int:
	return _ring_footprint.get(cell, -1)


func _remove_roundabout(junction_id: int) -> bool:
	if not _placed_rings.has(junction_id):
		return false
	var ring: Dictionary = _placed_rings[junction_id]
	_placed_rings.erase(junction_id)
	for eid in ring.edges:
		_unlink(eid, false)
	for eid in ring.original:
		get_edge(eid).suspended = false
	for id in ring.nodes:
		_ring_footprint.erase(cell_of(_nodes[id].pos))
	for id in ring.created:
		_unlink_road_from_water(id)
		_nodes.erase(id)
		_adj.erase(id)
	_ring_footprint.erase(cell_of(_nodes[junction_id].pos))
	RescueManager.remap_roundabout_vehicles(ring.created, [junction_id])
	for eid in ring.edges:
		EventBus.edge_removed.emit(eid)
	for eid in ring.original:
		EventBus.edge_added.emit(eid)
	_after_road_edit()
	_refund_item(ITEM_ROUNDABOUT)
	return true


func can_start_highway(cell: Vector2i) -> bool:
	return road_at(cell) != -1 and not _ring_footprint.has(cell)


func can_place_highway(start: Vector2i, end: Vector2i) -> bool:
	var a := road_at(start)
	var b := road_at(end)
	if a == b or not can_start_highway(start) or not can_start_highway(end):
		return false
	for id in _highway_adj.get(a, []):
		if get_edge(id).other_end(a) == b:
			return false
	return true


func get_highway_preview_points(start: Vector2i, end: Vector2i) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not can_place_highway(start, end):
		return points
	var a := cell_center(start)
	var b := cell_center(end)
	var normal := a.direction_to(b).orthogonal()
	var control := ((a + b) * 0.5 + normal * minf(a.distance_to(b) * HIGHWAY_CURVE_RATIO, Config.CELL_SIZE * HIGHWAY_CURVE_MAX_CELLS)).clamp(
		Vector2.ZERO, Vector2(Config.GRID_COLS, Config.GRID_ROWS) * Config.CELL_SIZE)
	var segments := maxi(2, ceili(a.distance_to(b) / (Config.CELL_SIZE * HIGHWAY_SAMPLE_STEP_CELLS)))
	for i in range(segments + 1):
		var t := float(i) / segments
		points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return points


func place_highway(start: Vector2i, end: Vector2i) -> int:
	if not can_place_highway(start, end):
		return -1
	return _place_item(ITEM_HIGHWAY, _commit_highway.bind(start, end))


func _commit_highway(start: Vector2i, end: Vector2i) -> int:
	var points := get_highway_preview_points(start, end)
	if points.is_empty():
		return -1
	var edge := Edge.new()
	edge.id = _next_highway
	_next_highway += 1
	edge.node_a = road_at(start)
	edge.node_b = road_at(end)
	edge.is_highway = true
	edge.curve = points
	for i in range(1, points.size()):
		edge.length += points[i - 1].distance_to(points[i])
	_edges[edge.id] = edge
	_highways[edge.id] = true
	for id in [edge.node_a, edge.node_b]:
		if not _highway_adj.has(id):
			_highway_adj[id] = []
		_highway_adj[id].append(edge.id)
	EventBus.edge_added.emit(edge.id)
	EventBus.road_changed.emit()
	return edge.id


func get_highway_ids() -> Array:
	return _highways.keys()


func get_highway_route(route_id: int) -> Dictionary:
	if not _highways.has(route_id):
		return {}
	var edge := get_edge(route_id)
	return {route_id = route_id, node_a = edge.node_a, node_b = edge.node_b,
		start = cell_of(_nodes[edge.node_a].pos), end = cell_of(_nodes[edge.node_b].pos),
		points = edge.curve.duplicate(), length = edge.length}


func highway_at_position(pos: Vector2) -> int:
	var closest := -1
	var distance := 13.0
	for id in _highways:
		var points: PackedVector2Array = _edges[id].curve
		for i in range(1, points.size()):
			var hit := Geometry2D.get_closest_point_to_segment(pos, points[i - 1], points[i])
			var candidate := pos.distance_to(hit)
			if candidate < distance:
				distance = candidate
				closest = id
	return closest


func remove_highway(route_id: int) -> bool:
	if _editing_infrastructure:
		return false
	_editing_infrastructure = true
	var removed := _remove_highway(route_id)
	_editing_infrastructure = false
	return removed


func _remove_highway(route_id: int) -> bool:
	if not _highways.erase(route_id):
		return false
	var edge := get_edge(route_id)
	_highway_adj[edge.node_a].erase(route_id)
	_highway_adj[edge.node_b].erase(route_id)
	_edges.erase(route_id)
	EventBus.edge_removed.emit(route_id)
	EventBus.road_changed.emit()
	_refund_item(ITEM_HIGHWAY)
	return true


func add_edge_limit(amount: int) -> void:
	if amount <= 0:
		return
	_limit += amount
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
		if vehicle_type == Types.VehicleType.BOAT and u != from_id and _nodes.has(u) and _nodes[u].kind != Types.NodeKind.ROAD:
			continue  # bản đồ có cổng: ca-nô chỉ xuất phát hoặc cập bến ở điểm, không đi xuyên qua (vào bến này ra bến kia là chạy qua đất)
		var du: float = dist[u]
		for list in [_adj.get(u, []), _badj.get(u, []), _fadj.get(u, []), _highway_adj.get(u, [])]:
			for eid in list:
				var e: Edge = _edges[eid]
				if _ring_from.has(eid) and _ring_from[eid] != u:
					continue                    # vòng xoay một chiều: không đi ngược
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

# --- Ca-nô lao thẳng trên nước thoáng ---
# A shortcut stays on open, mapped navigation cells, including its endpoints.
func water_line(a: Vector2, b: Vector2) -> bool:
	for cell in _line_cells(a, b):
		if not is_boat_route_open(cell):
			return false
	return true


# Check both sides of a grid line and both adjacent cells at an exact corner.
# The same traversed cells determine whether a cached shortcut stays open.
func _line_cells(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var cell := cell_of(a)
	var end := cell_of(b)
	var cells: Array[Vector2i] = [cell]
	var delta := b - a
	var direction := Vector2i(signf(delta.x), signf(delta.y))
	var next_x := float(cell.x + int(direction.x > 0)) * Config.CELL_SIZE
	var next_y := float(cell.y + int(direction.y > 0)) * Config.CELL_SIZE
	var tx := (next_x - a.x) / delta.x if direction.x != 0 else INF
	var ty := (next_y - a.y) / delta.y if direction.y != 0 else INF
	var dx := absf(float(Config.CELL_SIZE) / delta.x) if direction.x != 0 else INF
	var dy := absf(float(Config.CELL_SIZE) / delta.y) if direction.y != 0 else INF
	while cell != end:
		var corner := cell.x != end.x and cell.y != end.y and is_equal_approx(tx, ty)
		var cross_x := cell.x != end.x and (cell.y == end.y or tx <= ty or corner)
		var cross_y := cell.y != end.y and (cell.x == end.x or ty <= tx or corner)
		if corner:
			cells.append(cell + Vector2i(direction.x, 0))
			cells.append(cell + Vector2i(0, direction.y))
		if cross_x:
			cell.x += direction.x
			tx += dx
		if cross_y:
			cell.y += direction.y
			ty += dy
		cells.append(cell)
	var across := Vector2i.ZERO
	if direction.x == 0 and direction.y != 0 and fposmod(a.x, Config.CELL_SIZE) == 0.0:
		across = Vector2i.LEFT
	elif direction.y == 0 and direction.x != 0 and fposmod(a.y, Config.CELL_SIZE) == 0.0:
		across = Vector2i.UP
	if across != Vector2i.ZERO:
		for i in cells.size():
			cells.append(cells[i] + across)
	return cells


# Làm thẳng đường ca-nô (như Theta*): trên mỗi đoạn đi liền qua các nút nước, từ một nút nhảy thẳng tới nút nước xa nhất
# còn nhìn thấy trên nước thoáng, bỏ các nút gấp khúc ở giữa. Đoạn tắt là cạnh boat_only riêng (DEEP), dùng lại nếu đã có.
# Ven bờ hay còn đất khô chắn thì giữ nguyên đường theo ô như cũ, nên ca-nô không băng qua đất.
func smooth_boat_path(p: PathResult, cache_edges := true) -> PathResult:
	if not p.found or p.node_ids.size() < 3:
		return p
	var ids := p.node_ids
	var out := PathResult.new()
	out.found = true
	out.cost = p.cost
	out.node_ids.append(ids[0])
	var i := 0
	while i < ids.size() - 1:
		var j := i + 1
		if _water.has(ids[i]):
			var a: Vector2 = _water[ids[i]].pos
			var k := i + 2
			while k < ids.size() and _water.has(ids[k - 1]) and _water.has(ids[k]) \
					and water_line(a, _water[ids[k]].pos):
				j = k
				k += 1
		if cache_edges:
			out.edge_ids.append(p.edge_ids[i] if j == i + 1 else _boat_shortcut(ids[i], ids[j]))
		out.node_ids.append(ids[j])
		i = j
	return out

func _boat_shortcut(a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if _shortcuts.has(key) and _edges.has(_shortcuts[key]):
		return _shortcuts[key]
	var a_pos := get_map_node(a).pos
	var b_pos := get_map_node(b).pos
	var id := _add_boat_edge(a, b, _line_cells(a_pos, b_pos), false, false)
	_shortcuts[key] = id
	return id


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
	_channel_open.clear()
	_boat_edge_channels.clear()
	_shortcuts.clear()
	_badj.clear()
	_water.clear()
	_next_boat_edge = 0
	var at := {}
	for e in _boat_pos:
		at[int(e[0])] = Vector2(float(e[1]), float(e[2]))
	for i in Config.GRID_COLS * Config.GRID_ROWS:
		var cell := Vector2i(i % Config.GRID_COLS, i / Config.GRID_COLS)
		if not is_boat_route_cell(cell):
			continue
		var n := MapNode.new()
		n.id = WATER_ID_BASE + i
		n.kind = Types.NodeKind.WATER
		n.pos = at.get(i, cell_center(cell))
		_water[n.id] = n
		if not cell_is_boat(cell):
			_channel_open[cell] = false
	for id in _water.keys():
		var cell := _water_cell(id)
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var other_cell: Vector2i = cell + offset
			var other := _water_at(other_cell)
			if other == -1:
				continue
			var permanent := cell_is_boat(cell) and cell_is_boat(other_cell)
			if (permanent and _boat_links.is_empty()) or (not permanent and (offset.x == 0 or offset.y == 0)):
				_connect_water(id, other)
	var via := 0
	for link in _boat_links:
		var a: int = WATER_ID_BASE + int(link[0])
		var b: int = WATER_ID_BASE + int(link[1])
		if not (_water.has(a) and _water.has(b)):
			continue
		if link.size() >= 4:
			var n := MapNode.new()
			n.id = WATER_VIA_BASE + via
			n.kind = Types.NodeKind.WATER
			n.pos = Vector2(float(link[2]), float(link[3]))
			_water[n.id] = n
			via += 1
			_connect_water(a, n.id)
			_connect_water(n.id, b)
		else:
			_connect_water(a, b)
	for p in _points:
		_add_docks(p)
	for id in _nodes:
		if _nodes[id].kind == Types.NodeKind.ROAD:
			_link_road_to_water(id)


func _connect_water(a: int, b: int) -> void:
	var cells := _line_cells(get_map_node(a).pos, get_map_node(b).pos)
	if not _boat_linked(a, b) and cells.all(is_boat_route_cell):
		_add_boat_edge(a, b, cells)


func refresh_boat_depth() -> void:
	var changed := false
	for cell in _channel_open:
		var open := FloodManager.depth_at(cell) >= Config.BOAT_CHANNEL_MIN_DEPTH
		if _channel_open[cell] != open:
			_channel_open[cell] = open
			changed = true
	if not changed:
		return
	var last := -1
	for eid in _boat_edge_channels:
		var state := _boat_state(_boat_edge_channels[eid])
		if set_edge_state(eid, state, true):
			last = eid
	if last != -1:
		EventBus.edge_state_changed.emit(last, _edges[last].state)


func _boat_state(channels: Array[Vector2i]) -> int:
	return Types.EdgeState.DEEP if channels.all(is_boat_route_open) else Types.EdgeState.DRY


func boat_edges_of(id: int) -> Array:
	return _badj.get(id, [])


func is_flood_node(id: int) -> bool:
	return id >= WATER_ID_BASE and id < WATER_VIA_BASE and _channel_open.has(_water_cell(id))


func _water_cell(id: int) -> Vector2i:
	var i := id - WATER_ID_BASE
	return Vector2i(i % Config.GRID_COLS, i / Config.GRID_COLS)


func _water_at(cell: Vector2i) -> int:
	if not _in_grid(cell):
		return -1
	var id := WATER_ID_BASE + _cell_index(cell)
	return id if _water.has(id) else -1


func boat_node_at(cell: Vector2i) -> int:
	return _water_at(cell)


func _add_boat_edge(a: int, b: int, cells: Array[Vector2i], flood_link := false, in_graph := true) -> int:
	var channels: Array[Vector2i] = []
	for cell in cells:
		if _channel_open.has(cell):
			channels.append(cell)
	var e := Edge.new()
	e.id = BOAT_EDGE_ID_BASE + _next_boat_edge
	_next_boat_edge += 1
	e.node_a = a
	e.node_b = b
	e.length = get_map_node(a).pos.distance_to(get_map_node(b).pos)
	e.state = _boat_state(channels)
	e.boat_only = true
	_edges[e.id] = e
	_boat_edges[e.id] = true
	if not channels.is_empty():
		_boat_edge_channels[e.id] = channels
	if flood_link:
		_flood_links[e.id] = true
	if in_graph:
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

# Docks are terminal connectors to nearby mapped water or seasonal channels.
func _add_docks(point_id: int) -> void:
	var n: MapNode = _nodes.get(point_id)
	if n == null or n.kind == Types.NodeKind.ROAD:
		return
	var c := cell_of(n.pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var water_cell := c + Vector2i(dx, dy)
			var w := _water_at(water_cell)
			if w != -1 and not _boat_linked(point_id, w):
				_add_boat_edge(point_id, w, [water_cell])

# Các nút nước nối bến với điểm point_id (ca-nô cập bến đỗ trên nước tại đây), rỗng nếu điểm không có bến.
func get_dock_nodes(point_id: int) -> Array[int]:
	var out: Array[int] = []
	if not _nodes.has(point_id) or _nodes[point_id].kind == Types.NodeKind.ROAD:
		return out
	for eid in _badj.get(point_id, []):
		var w: int = _edges[eid].other_end(point_id)
		if _water.has(w) and _edges[eid].state != Types.EdgeState.DRY:
			out.append(w)
	return out

# Các nút nước nối với nút nước id bằng cạnh sông (để xếp thêm chỗ neo ca-nô cạnh bến).
func get_water_neighbors(id: int) -> Array[int]:
	var out: Array[int] = []
	for eid in _badj.get(id, []):
		var w: int = _edges[eid].other_end(id)
		if _water.has(w) and _edges[eid].state != Types.EdgeState.DRY:
			out.append(w)
	return out

# Only currently open docks are usable.
func has_dock(point_id: int) -> bool:
	return not get_dock_nodes(point_id).is_empty()

# A road drawn on a seasonal channel gets a same-cell connector while the channel is open.
func _link_road_to_water(road_id: int) -> void:
	var cell := cell_of(_nodes[road_id].pos)
	var water := _water_at(cell)
	if water != -1 and _channel_open.has(cell):
		_add_boat_edge(road_id, water, [cell], true)


# Gỡ lối xuống nước của ô đường sắp xóa; phát edge_removed để xe đang đi trên đó tính lại đường.
func _unlink_road_from_water(road_id: int) -> void:
	for eid in _badj.get(road_id, []).duplicate():
		var e: Edge = _edges[eid]
		var w := e.other_end(road_id)
		_badj[w].erase(eid)
		_edges.erase(eid)
		_boat_edges.erase(eid)
		_flood_links.erase(eid)
		_boat_edge_channels.erase(eid)
		EventBus.edge_removed.emit(eid)
	_badj.erase(road_id)

# Water connectors attached to roads drawn on marked channels.
func get_flood_links() -> Array[int]:
	var out: Array[int] = []
	for k in _flood_links:
		out.append(k)
	return out

# --- Feature D: Hệ thống Phà Phao Vượt Sông Đặt Thủ Công (Multi-Modal Logistics) ---

func get_ferries_available() -> int:
	return int(GameManager.call("get_inventory", ITEM_FERRY)) if _inventory_ready() else 0


func get_ferries_total() -> int:
	return get_ferries_available() + _ferry_routes.size()


func _emit_ferry_inventory() -> void:
	EventBus.ferry_inventory_changed.emit(get_ferries_available(), get_ferries_total())


func add_ferry_token(count := 1) -> void:
	if has_node("/root/GameManager"):
		GameManager.grant_reward(Types.Reward.FERRY, count)


func get_ferry_routes() -> Array:
	return _ferry_routes.duplicate(true)

func is_ferry_edge(edge_id: int) -> bool:
	return _ferry_edges.has(edge_id)

func get_ferry_edge_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _ferry_edges.keys():
		out.append(k)
	return out

func can_start_ferry(cell: Vector2i) -> bool:
	return _in_grid(cell) and road_at(cell) != -1 and not cell_is_water(cell) \
		and not _point_cells.has(cell) and not _ring_footprint.has(cell) \
		and _ferry_docks_open(cell, cell)


func _ferry_plan(cell_a: Vector2i, cell_b: Vector2i) -> Dictionary:
	if cell_a == cell_b or not can_start_ferry(cell_a) or not _in_grid(cell_b):
		return {}
	if cell_is_water(cell_b) or _point_cells.has(cell_b) or _lot_cells.has(cell_b) or _ring_footprint.has(cell_b):
		return {}
	if not _ferry_docks_open(cell_a, cell_b) or (road_at(cell_b) == -1 and _roads >= _limit):
		return {}
	if _ferry_pair_taken(cell_a, cell_b):
		return {}
	var pos_a := cell_center(cell_a)
	var pos_b := cell_center(cell_b)
	if not _is_water_crossing(cell_a, cell_b, pos_a, pos_b):
		return {}
	var water_nodes := _ferry_water_nodes(cell_a, cell_b)
	if water_nodes.is_empty():
		return {}
	var length := pos_a.distance_to(_water[water_nodes.front()].pos) + pos_b.distance_to(_water[water_nodes.back()].pos)
	for i in range(1, water_nodes.size()):
		length += _water[water_nodes[i - 1]].pos.distance_to(_water[water_nodes[i]].pos)
	if length < 30.0 or length > 550.0:
		return {}
	return {water_nodes = water_nodes}


func can_place_ferry(cell_a: Vector2i, cell_b: Vector2i) -> bool:
	return not _ferry_plan(cell_a, cell_b).is_empty()

func place_ferry(cell_a: Vector2i, cell_b: Vector2i) -> bool:
	return can_place_ferry(cell_a, cell_b) and _place_item(ITEM_FERRY, _commit_ferry.bind(cell_a, cell_b)) != -1


func _commit_ferry(cell_a: Vector2i, cell_b: Vector2i) -> int:
	var plan := _ferry_plan(cell_a, cell_b)
	if plan.is_empty():
		return -1
	var u := road_at(cell_a)
	var v := road_at(cell_b)
	var create_dock := v == -1
	if create_dock:
		v = _add_road(cell_b)
	var route := {route_id = FERRY_EDGE_ID_BASE + _next_ferry_edge, placed_cell_a = cell_a, placed_cell_b = cell_b}
	_next_ferry_edge += 1
	_build_ferry_route(route, u, v, plan.water_nodes)
	_ferry_routes.append(route)
	for eid in route.edge_ids:
		EventBus.edge_added.emit(eid)
	if create_dock:
		_after_road_edit()
	EventBus.ferry_routes_changed.emit()
	_emit_ferry_inventory()
	return route.route_id


func _build_ferry_route(route: Dictionary, u: int, v: int, water_nodes: Array) -> void:
	var nodes: Array[int] = [u]
	nodes.append_array(water_nodes)
	nodes.append(v)
	var edge := Edge.new()
	edge.id = route.route_id
	edge.node_a = u
	edge.node_b = v
	for i in nodes.size() - 1:
		edge.length += get_map_node(nodes[i]).pos.distance_to(get_map_node(nodes[i + 1]).pos)
	edge.is_ferry = true
	edge.ferry_route_id = route.route_id
	_edges[edge.id] = edge
	_ferry_edges[edge.id] = edge
	for id in [u, v]:
		if not _fadj.has(id):
			_fadj[id] = []
		_fadj[id].append(edge.id)
	route.merge({edge_id = edge.id, edge_ids = [edge.id], node_a = u, node_b = v, route_nodes = nodes,
		pos_a = _nodes[u].pos, pos_b = _nodes[v].pos, cell_a = cell_of(_nodes[u].pos),
		cell_b = cell_of(_nodes[v].pos), length = edge.length, open = true}, true)

func _detach_ferry_edges(route: Dictionary) -> void:
	for id in route.edge_ids:
		var edge := get_edge(id)
		_fadj[edge.node_a].erase(id)
		_fadj[edge.node_b].erase(id)
		_ferry_edges.erase(id)
		_edges.erase(id)
		EventBus.edge_removed.emit(id)


# A shared dock is ambiguous. Remove a selected route by id in that case.
func remove_ferry_at_cell(cell: Vector2i) -> bool:
	var route_id := -1
	for route in _ferry_routes:
		if route.cell_a == cell or route.cell_b == cell:
			if route_id != -1:
				return false
			route_id = route.route_id
	return route_id != -1 and remove_ferry(route_id)


func remove_ferry(route_id: int) -> bool:
	if _editing_infrastructure:
		return false
	for route in _ferry_routes:
		if route.route_id == route_id:
			_editing_infrastructure = true
			_remove_ferry_route(route)
			_editing_infrastructure = false
			return true
	return false


func _remove_ferry_route(route: Dictionary) -> void:
	_ferry_routes.erase(route)
	_detach_ferry_edges(route)
	EventBus.ferry_routes_changed.emit()
	_refund_item(ITEM_FERRY)
	_emit_ferry_inventory()


func _ferry_pair_taken(a: Vector2i, b: Vector2i, except_id := -1) -> bool:
	for route in _ferry_routes:
		if route.route_id == except_id:
			continue
		if (route.cell_a == a and route.cell_b == b) or (route.cell_a == b and route.cell_b == a):
			return true
	return false


func _ferry_docks_open(a: Vector2i, b: Vector2i) -> bool:
	return FloodManager.depth_at(a) < Config.SHALLOW_MAX and FloodManager.depth_at(b) < Config.SHALLOW_MAX


func _ferry_water_nodes(a: Vector2i, b: Vector2i) -> Array[int]:
	var w_a := _nearest_water_node_to_cell(a, cell_center(b))
	var w_b := _nearest_water_node_to_cell(b, cell_center(a))
	return _find_water_path_between(w_a, w_b).node_ids


func _ferry_water_open(route: Dictionary) -> bool:
	var nodes: Array = route.route_nodes
	for i in range(1, nodes.size() - 1):
		var pos := get_map_node(nodes[i]).pos
		if not is_boat_route_open(cell_of(pos)):
			return false
		if i > 1 and not water_line(get_map_node(nodes[i - 1]).pos, pos):
			return false
	return true

func _update_ferry_fallbacks() -> void:
	if _editing_infrastructure:
		return
	_editing_infrastructure = true
	var changed := false
	for route in _ferry_routes:
		var can_sail := _ferry_docks_open(route.cell_a, route.cell_b) and _ferry_water_open(route)
		if not can_sail:
			var replacement := _find_ferry_fallback(route)
			if not replacement.is_empty():
				_detach_ferry_edges(route)
				_build_ferry_route(route, replacement.a, replacement.b, replacement.water_nodes)
				EventBus.edge_added.emit(route.edge_id)
				changed = true
				can_sail = true
		if can_sail != route.open:
			route.open = can_sail
			var edge := get_edge(route.edge_id)
			edge.suspended = not can_sail
			EventBus.edge_state_changed.emit(edge.id, edge.state)
			changed = true
	if changed:
		EventBus.ferry_routes_changed.emit()
	_editing_infrastructure = false


func _find_ferry_fallback(route: Dictionary) -> Dictionary:
	var far_docks := _fallback_docks(route.node_b)
	for u in _fallback_docks(route.node_a):
		var a := cell_of(_nodes[u].pos)
		for v in far_docks:
			var b := cell_of(_nodes[v].pos)
			if a == b or _ferry_pair_taken(a, b, route.route_id) or not _is_water_crossing(a, b, cell_center(a), cell_center(b)):
				continue
			var water_nodes := _ferry_water_nodes(a, b)
			if not water_nodes.is_empty():
				return {a = u, b = v, water_nodes = water_nodes}
	return {}


# Search along existing road branches for the nearest usable shore on this side.
func _fallback_docks(start: int) -> Array[int]:
	var start_cell := cell_of(_nodes[start].pos)
	if FloodManager.depth_at(start_cell) < Config.SHALLOW_MAX:
		return [start]
	var docks: Array[int] = []
	var pending: Array[int] = [start]
	var seen := {start: true}
	var head := 0
	while head < pending.size():
		var id := pending[head]
		head += 1
		var cell := cell_of(_nodes[id].pos)
		if not cell_is_water(cell) and _ferry_docks_open(cell, cell) \
				and _nearest_water_node_to_cell(cell, cell_center(cell)) != -1:
			docks.append(id)
		for eid in get_edges_of(id):
			var other := get_edge(eid).other_end(id)
			if seen.has(other) or _nodes[other].kind != Types.NodeKind.ROAD:
				continue
			var next := cell_of(_nodes[other].pos)
			if _ring_footprint.has(next) or cell_is_water(next):
				continue
			seen[other] = true
			pending.append(other)
	return docks


# Tìm nút nước gần nhất kề ô bờ cell hướng về phía towards
func _nearest_water_node_to_cell(cell: Vector2i, towards: Vector2) -> int:
	var best_id := -1
	var best_dist := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := cell + Vector2i(dx, dy)
			var w := _water_at(c)
			if w != -1 and is_boat_route_open(c):
				var p: Vector2 = _water[w].pos
				var d: float = p.distance_to(towards)
				if d < best_dist:
					best_dist = d
					best_id = w
	return best_id

# Tìm lộ trình đường thủy nối 2 nút nước (uốn theo sông và làm thẳng trên nước thoáng)
func _find_water_path_between(w_a: int, w_b: int) -> PathResult:
	if not (_water.has(w_a) and _water.has(w_b)):
		return PathResult.new()
	if w_a == w_b:
		var res := PathResult.new()
		res.found = true
		res.node_ids = [w_a]
		return res
	var tree := _dijkstra(w_a, w_b, Types.VehicleType.BOAT, {})
	var p := path_from_tree(tree, w_a, w_b)
	if p.found:
		return smooth_boat_path(p, false)
	return PathResult.new()

# Lấy các điểm preview lộ trình phà phao để vẽ nét đứt khi người chơi kéo chuột
func get_ferry_preview_points(cell_a: Vector2i, cell_b: Vector2i) -> PackedVector2Array:
	var points := PackedVector2Array()
	var plan := _ferry_plan(cell_a, cell_b)
	if plan.is_empty():
		return points
	points.append(cell_center(cell_a))
	for id in plan.water_nodes:
		points.append(get_map_node(id).pos)
	points.append(cell_center(cell_b))
	return points


# Hướng vuông góc từ ô bờ đất quay thẳng ra lòng sông
func get_shore_river_direction(cell: Vector2i, preferred_water_pos: Vector2 = Vector2.INF) -> Vector2:
	const CARDINALS: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	var water_dirs: Array[Vector2i] = []
	for d: Vector2i in CARDINALS:
		var c: Vector2i = cell + d
		if is_boat_route_open(c):
			water_dirs.append(d)
	
	if water_dirs.size() == 1:
		return Vector2(water_dirs[0])
	elif water_dirs.size() > 1:
		if preferred_water_pos != Vector2.INF:
			var cell_pos: Vector2 = cell_center(cell)
			var target_dir: Vector2 = (preferred_water_pos - cell_pos).normalized()
			var best_d: Vector2i = water_dirs[0]
			var best_dot: float = -2.0
			for d: Vector2i in water_dirs:
				var dot: float = Vector2(d).dot(target_dir)
				if dot > best_dot:
					best_dot = dot
					best_d = d
			return Vector2(best_d)
		else:
			return Vector2(water_dirs[0])

	# Nếu không có hướng chính nào là nước, thử tìm trong 8 hướng
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c: Vector2i = cell + Vector2i(dx, dy)
			if is_boat_route_open(c):
				return Vector2(dx, dy).normalized()

	return Vector2.ZERO

func _is_water_crossing(cell_a: Vector2i, cell_b: Vector2i, pos_a: Vector2, pos_b: Vector2) -> bool:
	var dist: float = pos_a.distance_to(pos_b)
	var steps: int = maxi(3, int(ceil(dist / 10.0)))
	var water_hits := 0
	var land_cells := 0

	for s in range(1, steps):
		var t := float(s) / float(steps)
		var p: Vector2 = pos_a.lerp(pos_b, t)
		var c: Vector2i = cell_of(p)
		if c == cell_a or c == cell_b:
			continue
		if _point_cells.has(c):
			return false
		if is_boat_route_open(c):
			water_hits += 1
		else:
			land_cells += 1

	return water_hits >= 1 and water_hits >= land_cells
