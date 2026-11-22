extends Node2D
# FerryLayer (Feature D: Multi-Modal Logistics - Hệ thống Phao & Phà Vượt Sông)
# Chủ sở hữu: D. Vẽ luồng phà, bến phao và tàu phao đang neo đậu chờ đón xe tải vượt sông.

const FAIRWAY_COLOR := Color("#4aa9d6", 0.75)
const FAIRWAY_DASH_COLOR := Color("#ffffff", 0.9)
const DOCK_RAMP_COLOR := Color("#455a64")
const DOCK_RAMP_EDGE := Color("#fbc02d")
const BUOY_RADIUS := 4.5
const FERRY_SIZE := Vector2(36, 24)

var _buoy_texture: Texture2D = null
var _ferry_texture: Texture2D = null

func _ready() -> void:
	z_index = -4  # trên nền nước và đường chìm, dưới điểm và xe
	if ResourceLoader.exists("res://assets/icons/buoy.svg"):
		_buoy_texture = load("res://assets/icons/buoy.svg")
	if ResourceLoader.exists("res://assets/icons/pontoon_ferry.svg"):
		_ferry_texture = load("res://assets/icons/pontoon_ferry.svg")
		
	EventBus.ferry_routes_changed.connect(_on_routes_changed)
	EventBus.road_changed.connect(queue_redraw)
	EventBus.game_started.connect(queue_redraw)
	EventBus.water_level_changed.connect(func(_l: float) -> void: queue_redraw())

func _on_routes_changed() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	# Cập nhật chuyển động nhấp nhô của phao và tàu phao neo đậu
	var routes := GraphManager.get_ferry_routes()
	if not routes.is_empty():
		queue_redraw()

func _draw() -> void:
	var routes := GraphManager.get_ferry_routes()
	if routes.is_empty():
		return

	var time_sec := Time.get_ticks_msec() / 1000.0
	var bobbing := sin(time_sec * 3.0) * 1.5

	for r in routes:
		var pos_a: Vector2 = r.pos_a
		var pos_b: Vector2 = r.pos_b
		var dir := pos_a.direction_to(pos_b)
		var normal := dir.rotated(PI / 2.0)
		var dist := pos_a.distance_to(pos_b)

		# 1. Vẽ luồng phà hàng hải (Dashed fairway waterway line)
		var steps := int(dist / 14.0)
		for s in range(1, steps):
			var t1 := float(s) / float(steps)
			var t2 := (float(s) + 0.55) / float(steps)
			var p1 := pos_a.lerp(pos_b, t1)
			var p2 := pos_a.lerp(pos_b, t2)
			draw_line(p1, p2, FAIRWAY_DASH_COLOR, 2.5)

		# Hai đường viền giới hạn luồng bơi
		var side_offset := normal * 11.0
		draw_line(pos_a + side_offset, pos_b + side_offset, FAIRWAY_COLOR, 1.2)
		draw_line(pos_a - side_offset, pos_b - side_offset, FAIRWAY_COLOR, 1.2)

		# 2. Vẽ hai Bến Phà Phao ở hai đầu bờ sông
		_draw_dock(pos_a, dir, normal, bobbing)
		_draw_dock(pos_b, -dir, -normal, -bobbing)

		# 3. Vẽ Tàu Phao neo đậu chờ nếu hiện chưa có xe tải nào đang chở trên tuyến
		var has_crossing_truck := _is_truck_crossing(r.edge_id)
		if not has_crossing_truck:
			# Tàu phao đậu ở bến A hướng về phía bến B, hơi dập dềnh theo sóng nước
			var dock_wait_pos := pos_a + dir * 18.0 + normal * (bobbing * 0.4)
			_draw_stationed_ferry(dock_wait_pos, dir, bobbing)

# Vẽ bến phà, cầu dẫn và phao tiêu hai bên
func _draw_dock(pos: Vector2, out_dir: Vector2, normal: Vector2, bob: float) -> void:
	# Cầu dẫn (ramp) từ mép đường ra mặt nước
	var ramp_center := pos + out_dir * 8.0
	var ramp_rect := Rect2(-8, -10, 16, 20)
	draw_set_transform(ramp_center, out_dir.angle())
	draw_rect(ramp_rect, DOCK_RAMP_COLOR)
	# Vạch cảnh báo mép cầu dẫn
	draw_line(Vector2(8, -10), Vector2(8, 10), DOCK_RAMP_EDGE, 2.0)
	draw_set_transform(Vector2.ZERO)

	# Phao cứu hộ / Phao tiêu neo ở hai bên mỏm bến
	var buoy_left := pos + out_dir * 12.0 + normal * 14.0 + Vector2(0, bob)
	var buoy_right := pos + out_dir * 12.0 - normal * 14.0 - Vector2(0, bob)

	_draw_buoy(buoy_left)
	_draw_buoy(buoy_right)

func _draw_buoy(at: Vector2) -> void:
	if _buoy_texture != null:
		draw_texture_rect(_buoy_texture, Rect2(at - Vector2(7, 7), Vector2(14, 14)), false)
	else:
		draw_circle(at, BUOY_RADIUS + 1.5, Color("#263238"))
		draw_circle(at, BUOY_RADIUS, Color("#ff5722"))
		draw_circle(at, BUOY_RADIUS * 0.5, Color("#ffffff"))
		draw_circle(at, BUOY_RADIUS * 0.25, Color("#ffea00"))

# Vẽ tàu phao neo đậu tại bến khi không có xe
func _draw_stationed_ferry(at: Vector2, heading: Vector2, bob: float) -> void:
	var left := heading.x < 0.0
	draw_set_transform(at + Vector2(0, bob * 0.6), heading.angle() + (PI if left else 0.0), Vector2(-1.0 if left else 1.0, 1.0))
	if _ferry_texture != null:
		draw_texture_rect(_ferry_texture, Rect2(-FERRY_SIZE / 2.0, FERRY_SIZE), false)
	else:
		draw_rect(Rect2(-FERRY_SIZE.x / 2.0, -FERRY_SIZE.y / 2.0, FERRY_SIZE.x, FERRY_SIZE.y), Color("#2b4f63"))
		draw_rect(Rect2(-FERRY_SIZE.x / 2.0 + 3, -FERRY_SIZE.y / 2.0 + 3, FERRY_SIZE.x - 6, FERRY_SIZE.y - 6), Color("#cfd8dc"))
	draw_set_transform(Vector2.ZERO)

# Kiểm tra xem có xe nào đang di chuyển trên cạnh phà này không
func _is_truck_crossing(edge_id: int) -> bool:
	if not has_node("/root/RescueManager"):
		return false
	var vehicles: Array = RescueManager.get_vehicles()
	for v in vehicles:
		if v.is_moving() and v.path != null and v.path_index < v.path.edge_ids.size():
			if v.path.edge_ids[v.path_index] == edge_id:
				return true
	return false
