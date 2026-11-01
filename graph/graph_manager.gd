extends Node
# Autoload: GraphManager. Chủ sở hữu: A. Không đặt class_name.

const ROAD_ID_BASE := 1000  # mã nút ô đường = ROAD_ID_BASE + chỉ số ô, không đổi khi tô lại

var _nodes := {}        # id -> MapNode (cả điểm trên bản đồ và ô đường)
var _edges := {}        # id -> Edge
var _adj := {}          # id node -> Array các id cạnh kề
var _next_edge_id := 0
var _limit := 0
var _points: Array[int] = []    # các điểm trên bản đồ, theo thứ tự trong json
var _point_cells := {}          # ô -> id điểm
var _cell_elevation: Array = [] # độ cao từng ô, khóa "grid" của bản đồ
var _roads := 0                 # số ô đường đã tô
var _segments := {}             # id đoạn -> Array các id cạnh

func _ready() -> void:
	_limit = Config.EDGE_LIMIT_START
	EventBus.game_started.connect(_on_game_started)

func _on_game_started() -> void:
	_clear_edges()
	EventBus.edge_budget_changed.emit(0, _limit)

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

# --- Nạp bản đồ (gọi nhiều lần vẫn đúng: luôn xóa dữ liệu cũ trước) ---
func load_map(path: String) -> void:
	_nodes.clear()
	_adj.clear()
	_points.clear()
	_point_cells.clear()
	_clear_edges()
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has('nodes'):
		push_error('GraphManager: không đọc được bản đồ ' + path)
		return
	_cell_elevation = data.get('grid', {}).get('elevation', [])
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

# --- Truy vấn ---
# Chỉ các điểm trên bản đồ, không gồm ô đường.
func get_node_ids() -> Array[int]:
	return _points.duplicate()

func get_map_node(id: int) -> MapNode:
	return _nodes.get(id)

func get_edge(edge_id: int) -> Edge:
	return _edges.get(edge_id)

func get_edge_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _edges.keys():
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
	if not _in_grid(cell):
		return -1
	if from_id != -1 and not (_nodes.has(from_id) and _next_to(cell_of(_nodes[from_id].pos), cell)):
		return -1
	var to_id: int = _point_cells.get(cell, road_at(cell))
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
	return n.id

# Xóa ô đường và các cạnh nối vào nó, hoàn 1 hạn mức. Trả false nếu ô không có đường.
func remove_road(cell: Vector2i) -> bool:
	var id := road_at(cell)
	if id == -1:
		return false
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
		if not seen.has(eid):
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

# --- Dijkstra ---
func find_path(from_id: int, to_id: int, vehicle_type: int) -> PathResult:
	var res := PathResult.new()
	if not _nodes.has(from_id) or not _nodes.has(to_id):
		return res
	var dist := {}
	var prev_node := {}
	var prev_edge := {}
	var unvisited: Array = _nodes.keys()
	for id in unvisited:
		dist[id] = INF
	dist[from_id] = 0.0
	while not unvisited.is_empty():
		var u := -1
		var best := INF
		for id in unvisited:
			if dist[id] < best:
				best = dist[id]
				u = id
		if u == -1 or u == to_id:
			break
		unvisited.erase(u)
		for eid in _adj[u]:
			var e: Edge = _edges[eid]
			var factor := e.speed_factor(vehicle_type)
			if factor <= 0.0:
				continue                    # xe này không đi được cạnh này
			var v := e.other_end(u)
			var cost := e.length / (Config.base_speed(vehicle_type) * factor)
			if dist[u] + cost < dist[v]:
				dist[v] = dist[u] + cost
				prev_node[v] = u
				prev_edge[v] = eid
	if dist[to_id] == INF:
		return res
	var cur := to_id
	while cur != from_id:
		res.node_ids.push_front(cur)
		res.edge_ids.push_front(prev_edge[cur])
		cur = prev_node[cur]
	res.node_ids.push_front(from_id)
	res.found = true
	res.cost = dist[to_id]
	return res
