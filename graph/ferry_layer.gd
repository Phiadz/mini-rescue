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

		var n1 = GraphManager.get_map_node(route_nodes[1]) if route_nodes.size() >= 3 else null
		var n_penult = GraphManager.get_map_node(route_nodes[-2]) if route_nodes.size() >= 3 else null

		var dir_a: Vector2 = GraphManager.get_shore_river_direction(r.cell_a, n1.pos if n1 != null else Vector2.INF)
		if dir_a == Vector2.ZERO:
			dir_a = pos_a.direction_to(pos_b)

		var dir_b: Vector2 = GraphManager.get_shore_river_direction(r.cell_b, n_penult.pos if n_penult != null else Vector2.INF)
		if dir_b == Vector2.ZERO:
			dir_b = pos_b.direction_to(pos_a)

		var normal_a: Vector2 = dir_a.rotated(PI / 2.0)
		var normal_b: Vector2 = dir_b.rotated(PI / 2.0)

		# 1. Vẽ hai Bến đón / trả khách tinh gọn ở 2 đầu bờ sông
		_draw_minimal_dock(pos_a, dir_a, normal_a)
		_draw_minimal_dock(pos_b, dir_b, normal_b)

	# 2. Vẽ các Tàu phao (Ferry Vessels) độc lập di chuyển hoặc neo đậu tại bến
	var drawn_routes := {}
	if has_node("/root/RescueManager"):
		var vessels: Array = RescueManager.get_ferry_vessels()
		for fv in vessels:
			drawn_routes[fv.route_id] = true
			_draw_ferry_vessel(fv)

	# Fallback vẽ tàu đứng yên nếu RescueManager chưa khởi tạo tàu
	for r in routes:
		var rid: int = r.get("edge_id", -1)
		if not drawn_routes.has(rid):
			var pos_a: Vector2 = r.get("pos_a", Vector2.ZERO)
			var pos_b: Vector2 = r.get("pos_b", Vector2.ZERO)
			var dir_a: Vector2 = GraphManager.get_shore_river_direction(r.cell_a)
			if dir_a == Vector2.ZERO:
				dir_a = pos_a.direction_to(pos_b)
			var dock_wait_pos: Vector2 = pos_a + dir_a * 17.0
			_draw_stationed_ferry(dock_wait_pos, dir_a)

func _draw_ferry_vessel(fv) -> void:
	var pos: Vector2 = fv.position
	var heading: Vector2 = fv.heading
	if fv.is_sailing():
		_draw_vessel_wake(pos, heading)
	_draw_stationed_ferry(pos, heading)

func _draw_vessel_wake(pos: Vector2, heading: Vector2) -> void:
	var wake_color := Color(1.0, 1.0, 1.0, 0.42)
	var rear := pos - heading * 14.0
	var normal := heading.rotated(PI / 2.0)
	draw_line(rear - heading * 2.0, rear - heading * 14.0 + normal * 9.0, wake_color, 1.6)
	draw_line(rear - heading * 2.0, rear - heading * 14.0 - normal * 9.0, wake_color, 1.6)

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
