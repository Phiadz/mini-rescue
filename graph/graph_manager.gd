extends Node
# Autoload: GraphManager. Chủ sở hữu: A. Không đặt class_name.

var _nodes := {}        # id -> MapNode
var _edges := {}        # id -> Edge
var _adj := {}          # id node -> Array các id cạnh kề
var _next_edge_id := 0
var _limit := 0

func _ready() -> void:
	_limit = Config.EDGE_LIMIT_START
	EventBus.game_started.connect(_on_game_started)

func _on_game_started() -> void:
	_clear_edges()
	EventBus.edge_budget_changed.emit(0, _limit)

func _clear_edges() -> void:
	_edges.clear()
	for id in _adj:
		_adj[id] = []
	_next_edge_id = 0
	_limit = Config.EDGE_LIMIT_START

# --- Nạp bản đồ (gọi nhiều lần vẫn đúng: luôn xóa dữ liệu cũ trước) ---
func load_map(path: String) -> void:
	_nodes.clear()
	_adj.clear()
	_clear_edges()
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has('nodes'):
		push_error('GraphManager: không đọc được bản đồ ' + path)
		return
	for d in data['nodes']:
		var n := MapNode.new()
		n.id = int(d['id'])
		n.name = str(d['name'])
		n.kind = int(d['kind'])
		n.pos = Vector2(float(d['x']), float(d['y']))
		n.elevation = float(d['elevation'])
		_nodes[n.id] = n
		_adj[n.id] = []

# --- Truy vấn ---
func get_node_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _nodes.keys():
		out.append(k)
	return out

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

# --- Thêm, xóa, đổi trạng thái ---
func add_edge(a: int, b: int) -> int:
	if a == b or not _nodes.has(a) or not _nodes.has(b):
		return -1
	if _edges.size() >= _limit:
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
	e.elevation = (_nodes[a].elevation + _nodes[b].elevation) / 2.0
	_edges[e.id] = e
	_adj[a].append(e.id)
	_adj[b].append(e.id)
	EventBus.edge_added.emit(e.id)
	EventBus.edge_budget_changed.emit(_edges.size(), _limit)
	return e.id

func remove_edge(edge_id: int) -> void:
	if not _edges.has(edge_id):
		return
	var e: Edge = _edges[edge_id]
	_adj[e.node_a].erase(edge_id)
	_adj[e.node_b].erase(edge_id)
	_edges.erase(edge_id)
	EventBus.edge_removed.emit(edge_id)
	EventBus.edge_budget_changed.emit(_edges.size(), _limit)

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
	EventBus.edge_budget_changed.emit(_edges.size(), _limit)

func get_edge_budget() -> Dictionary:
	return {used = _edges.size(), limit = _limit}

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
