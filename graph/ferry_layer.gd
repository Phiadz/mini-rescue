extends Node2D
# FerryLayer (Feature D: Minimalist Ferry Docks & Stationed Pontoon Ferry)
# Thiết kế tối giản phong cách Mini Motorways:
# - Bến phà đứng yên tĩnh lặng tại 2 bờ (chỗ đón và chỗ trả).
# - Không vẽ vạch kẻ thẳng luồng hàng hải cắt qua sông.
# - Tàu phao neo đậu cố định tại bến khi chưa có xe qua lại.

const DOCK_RAMP_COLOR := Color("#37474f")
const DOCK_RAMP_BORDER := Color("#263238")
const DOCK_RAMP_EDGE := Color("#fbc02d")
const BOLLARD_COLOR := Color("#20282c")
const FERRY_SIZE := Vector2(36, 24)

var _ferry_texture: Texture2D = null

func _ready() -> void:
	z_index = -4  # trên nền nước, dưới điểm và xe
	if ResourceLoader.exists("res://assets/icons/pontoon_ferry.svg"):
		_ferry_texture = load("res://assets/icons/pontoon_ferry.svg")
		
	EventBus.ferry_routes_changed.connect(queue_redraw)
	EventBus.road_changed.connect(queue_redraw)
	EventBus.game_started.connect(queue_redraw)
	EventBus.water_level_changed.connect(func(_l: float) -> void: queue_redraw())

func _process(_delta: float) -> void:
	# Cập nhật hiển thị khi có xe qua lại trên phà
	var routes := GraphManager.get_ferry_routes()
	if not routes.is_empty():
		queue_redraw()

func _draw() -> void:
	var routes := GraphManager.get_ferry_routes()
	if routes.is_empty():
		return

	for r in routes:
		var pos_a: Vector2 = r.pos_a
		var pos_b: Vector2 = r.pos_b
		var route_nodes: Array = r.get("route_nodes", [])

		var dir_a := pos_a.direction_to(pos_b)
		var dir_b := pos_b.direction_to(pos_a)
		if route_nodes.size() >= 3:
			var n1 = GraphManager.get_map_node(route_nodes[1])
			if n1 != null:
				dir_a = pos_a.direction_to(n1.pos)
			var n_penult = GraphManager.get_map_node(route_nodes[-2])
			if n_penult != null:
				dir_b = pos_b.direction_to(n_penult.pos)

		var normal_a := dir_a.rotated(PI / 2.0)
		var normal_b := dir_b.rotated(PI / 2.0)

		# 1. Vẽ hai Bến đón / trả khách tinh gọn ở 2 đầu bờ sông
		_draw_minimal_dock(pos_a, dir_a, normal_a)
		_draw_minimal_dock(pos_b, dir_b, normal_b)

		# 2. Tàu phao neo đậu đứng im tại bến A chờ đón xe khi tuyến đang rảnh
		var has_crossing_truck := _is_truck_crossing_route(r)
		if not has_crossing_truck:
			var dock_wait_pos := pos_a + dir_a * 17.0
			_draw_stationed_ferry(dock_wait_pos, dir_a)

# Vẽ mố bến phà phẳng tối giản (Minimalist Dock Berth)
func _draw_minimal_dock(pos: Vector2, out_dir: Vector2, normal: Vector2) -> void:
	# Cầu dẫn cập bến (Ramp)
	var ramp_center := pos + out_dir * 9.0
	var ramp_size := Vector2(16, 20)
	draw_set_transform(ramp_center, out_dir.angle())
	draw_rect(Rect2(-ramp_size.x / 2.0, -ramp_size.y / 2.0, ramp_size.x, ramp_size.y), DOCK_RAMP_COLOR)
	draw_rect(Rect2(-ramp_size.x / 2.0, -ramp_size.y / 2.0, ramp_size.x, ramp_size.y), DOCK_RAMP_BORDER, false, 1.2)
	# Vạch cảnh báo vàng mép nước
	draw_line(Vector2(ramp_size.x / 2.0, -ramp_size.y / 2.0), Vector2(ramp_size.x / 2.0, ramp_size.y / 2.0), DOCK_RAMP_EDGE, 2.0)
	draw_set_transform(Vector2.ZERO)

	# Hai cột bích neo thuyền (Mooring bollards) nhỏ gọn hai bên
	draw_circle(pos + out_dir * 6.0 + normal * 12.0, 2.4, BOLLARD_COLOR)
	draw_circle(pos + out_dir * 6.0 - normal * 12.0, 2.4, BOLLARD_COLOR)

# Vẽ tàu phao neo đậu đứng yên tại bến (không dập dềnh)
func _draw_stationed_ferry(at: Vector2, heading: Vector2) -> void:
	var left := heading.x < 0.0
	draw_set_transform(at, heading.angle() + (PI if left else 0.0), Vector2(-1.0 if left else 1.0, 1.0))
	if _ferry_texture != null:
		draw_texture_rect(_ferry_texture, Rect2(-FERRY_SIZE / 2.0, FERRY_SIZE), false)
	else:
		draw_rect(Rect2(-FERRY_SIZE.x / 2.0, -FERRY_SIZE.y / 2.0, FERRY_SIZE.x, FERRY_SIZE.y), Color("#2b4f63"))
		draw_rect(Rect2(-FERRY_SIZE.x / 2.0 + 3, -FERRY_SIZE.y / 2.0 + 3, FERRY_SIZE.x - 6, FERRY_SIZE.y - 6), Color("#cfd8dc"))
	draw_set_transform(Vector2.ZERO)

# Kiểm tra xem có xe nào đang di chuyển trên tuyến phà này không
func _is_truck_crossing_route(r: Dictionary) -> bool:
	if not has_node("/root/RescueManager"):
		return false
	var eids: Array = r.get("edge_ids", [r.get("edge_id")])
	var vehicles: Array = RescueManager.get_vehicles()
	for v in vehicles:
		if v.is_moving() and v.path != null and v.path_index < v.path.edge_ids.size():
			if eids.has(v.path.edge_ids[v.path_index]):
				return true
	return false
