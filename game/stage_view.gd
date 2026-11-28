extends Node2D
# Vùng chơi theo đợt, nền đệm 16:10 và camera zoom thủ công theo con trỏ (E).
# Bản đồ 16:9 (1280×720) nằm chính giữa viewport mục tiêu 16:10 (1920×1200) mà không bị kéo giãn;
# phần viewport dư có nền đệm tối xanh-xám ít tương phản.
# Zoom nhỏ nhất luôn hiển thị trọn bản đồ (1× mức fit-map); zoom lớn nhất mặc định 2× mức fit-map.

const MAP_SIZE := Vector2(1280.0, 720.0)
const EDGE_MARGIN := 40.0  # đơn vị bản đồ; vùng cuối (zoom 1) không có mép
const MOVE_TIME := 1.6
const FOG := Color(0.02, 0.05, 0.1, 0.32)
const BORDER := Color(1.0, 1.0, 1.0, 0.35)
const BACKDROP_COLOR := Color("#151e28")  # nền đệm xanh-xám tối, ít tương phản
const MAP_FRAME_COLOR := Color(0.24, 0.35, 0.45, 0.45)
const BACKDROP_PADDING := Vector2(3200.0, 2400.0)

# Tham số zoom thủ công (giữ trong hằng số tập trung để dễ cân bằng).
const MIN_ZOOM_FACTOR := 1.0  # 1× mức fit-map: hiển thị trọn bản đồ 1280×720
const MAX_ZOOM_FACTOR := 2.0  # 2× mức fit-map theo baseline prototype
const ZOOM_STEP := 1.15       # hệ số mỗi nấc con lăn chuột

## Chỉ cho zoom tay khi đang trong lượt chơi (PLAYING / WAVE_BREAK); scene test có thể tắt cờ này.
@export var only_in_round := true

var camera := Camera2D.new()
var fog_rect := Rect2(Vector2.ZERO, MAP_SIZE)  # vùng không phủ tối (đang tween cùng camera)
var _tween: Tween
var _backdrop: Node2D
var _zoom_factor := MIN_ZOOM_FACTOR
var _current_stage := {"center": [MAP_SIZE.x / 2.0, MAP_SIZE.y / 2.0], "zoom": 1.0}


func _ready() -> void:
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.z_index = -100
	_backdrop.z_as_relative = false
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop)

	add_child(camera)
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.make_current()

	var fit := get_fit_zoom()
	var z := fit * _zoom_factor
	camera.zoom = Vector2(z, z)
	camera.position = clamp_camera_position(MAP_SIZE * 0.5, z, _viewport_size())

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)


# Mức zoom fit toàn bộ bản đồ 16:9 vào viewport bất kỳ mà không kéo giãn (zoom X == zoom Y).
static func compute_fit_zoom(viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	return minf(viewport_size.x / MAP_SIZE.x, viewport_size.y / MAP_SIZE.y)


# Đổi tọa độ điểm trên viewport về tọa độ bản đồ theo vị trí/zoom hiện tại của camera.
static func screen_to_world(screen_pos: Vector2, cam_pos: Vector2, cam_zoom: float, viewport_size: Vector2) -> Vector2:
	return cam_pos + (screen_pos - viewport_size * 0.5) / maxf(cam_zoom, 0.001)


# Giữ tâm camera trong giới hạn bản đồ; khi khung nhìn >= kích thước bản đồ theo trục nào thì căn giữa trục đó.
static func clamp_camera_position(pos: Vector2, cam_zoom: float, viewport_size: Vector2) -> Vector2:
	var safe_zoom := maxf(cam_zoom, 0.001)
	var visible_world := viewport_size / safe_zoom
	var out := pos
	if visible_world.x >= MAP_SIZE.x - 0.5:
		out.x = MAP_SIZE.x * 0.5
	else:
		var half_w := visible_world.x * 0.5
		out.x = clampf(out.x, half_w, MAP_SIZE.x - half_w)
	if visible_world.y >= MAP_SIZE.y - 0.5:
		out.y = MAP_SIZE.y * 0.5
	else:
		var half_h := visible_world.y * 0.5
		out.y = clampf(out.y, half_h, MAP_SIZE.y - half_h)
	return out


# Hình chữ nhật camera nhìn thấy ở một vùng (tọa độ bản đồ 1280×720).
static func view_rect(stage: Dictionary) -> Rect2:
	var size: Vector2 = MAP_SIZE / float(stage.get("zoom", 1.0))
	var center_arr = stage.get("center", [MAP_SIZE.x / 2.0, MAP_SIZE.y / 2.0])
	var c := Vector2(float(center_arr[0]), float(center_arr[1]))
	return Rect2(c - size / 2.0, size)


# Vùng được chơi: vùng nhìn thấy trừ dải mép; vùng cuối (zoom 1) là cả bản đồ.
static func play_rect(stage: Dictionary) -> Rect2:
	var view := view_rect(stage)
	return view if float(stage.get("zoom", 1.0)) <= 1.001 else view.grow(-EDGE_MARGIN)


func get_fit_zoom() -> float:
	return compute_fit_zoom(_viewport_size())


func get_min_zoom() -> float:
	return get_fit_zoom() * MIN_ZOOM_FACTOR


func get_max_zoom() -> float:
	return get_fit_zoom() * MAX_ZOOM_FACTOR


func get_zoom_factor() -> float:
	return _zoom_factor


func apply(stage: Dictionary, animate: bool) -> void:
	_current_stage = stage.duplicate(true)
	var vp := _viewport_size()
	var fit := compute_fit_zoom(vp)
	var stage_factor := clampf(float(stage.get("zoom", 1.0)), MIN_ZOOM_FACTOR, MAX_ZOOM_FACTOR)
	var target_zoom := fit * stage_factor
	var target_pos := clamp_camera_position(view_rect(stage).get_center(), target_zoom, vp)
	var target_fog := play_rect(stage)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate:
		_zoom_factor = stage_factor
		camera.position = target_pos
		camera.zoom = Vector2(target_zoom, target_zoom)
		_set_fog(target_fog)
		return
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "position", target_pos, MOVE_TIME)
	_tween.tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), MOVE_TIME)
	_tween.tween_property(self, "_zoom_factor", stage_factor, MOVE_TIME)
	_tween.tween_method(_set_fog, fog_rect, target_fog, MOVE_TIME)


# Phóng to / thu nhỏ hướng về điểm con trỏ (tọa độ viewport). Trả true nếu mức zoom thay đổi.
func zoom_at_screen_pos(screen_pos: Vector2, multiplier: float) -> bool:
	if multiplier <= 0.0:
		return false
	var vp := _viewport_size()
	var fit := compute_fit_zoom(vp)
	var old_zoom := camera.zoom.x if camera.zoom.x > 0.001 else fit
	var new_factor := clampf((old_zoom / fit) * multiplier, MIN_ZOOM_FACTOR, MAX_ZOOM_FACTOR)
	var new_zoom := fit * new_factor
	if is_equal_approx(new_zoom, old_zoom):
		return false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var world_before := screen_to_world(screen_pos, camera.position, old_zoom, vp)
	var new_pos := world_before - (screen_pos - vp * 0.5) / new_zoom
	new_pos = clamp_camera_position(new_pos, new_zoom, vp)
	_zoom_factor = new_factor
	camera.zoom = Vector2(new_zoom, new_zoom)
	camera.position = new_pos
	return true


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if get_tree() != null and get_tree().paused:
		return
	if only_in_round and not _in_round():
		return
	var step_scale := ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_STEP)
	zoom_at_screen_pos(mb.position, step_scale)
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _on_viewport_size_changed() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var vp := _viewport_size()
	var fit := compute_fit_zoom(vp)
	var z := fit * clampf(_zoom_factor, MIN_ZOOM_FACTOR, MAX_ZOOM_FACTOR)
	camera.zoom = Vector2(z, z)
	camera.position = clamp_camera_position(camera.position, z, vp)
	if _backdrop != null:
		_backdrop.queue_redraw()
	queue_redraw()


func _viewport_size() -> Vector2:
	var rect := get_viewport_rect()
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		return rect.size
	return Vector2(1920.0, 1200.0)


func _in_round() -> bool:
	if not has_node("/root/GameManager"):
		return true
	return GameManager.state == Types.GameState.PLAYING or GameManager.state == Types.GameState.WAVE_BREAK


func _set_fog(r: Rect2) -> void:
	fog_rect = r
	queue_redraw()


func _draw_backdrop() -> void:
	var bg_rect := Rect2(-BACKDROP_PADDING, MAP_SIZE + BACKDROP_PADDING * 2.0)
	_backdrop.draw_rect(bg_rect, BACKDROP_COLOR)
	_backdrop.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), MAP_FRAME_COLOR, false, 2.0)


func _draw() -> void:
	if fog_rect.size.x >= MAP_SIZE.x - 1.0 and fog_rect.size.y >= MAP_SIZE.y - 1.0:
		return
	var map_bounds := Rect2(Vector2.ZERO, MAP_SIZE)
	var r := fog_rect.intersection(map_bounds)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		draw_rect(map_bounds, FOG)
		return
	if r.position.y > map_bounds.position.y:
		draw_rect(Rect2(map_bounds.position, Vector2(map_bounds.size.x, r.position.y - map_bounds.position.y)), FOG)
	if r.end.y < map_bounds.end.y:
		draw_rect(Rect2(Vector2(map_bounds.position.x, r.end.y), Vector2(map_bounds.size.x, map_bounds.end.y - r.end.y)), FOG)
	if r.position.x > map_bounds.position.x:
		draw_rect(Rect2(Vector2(map_bounds.position.x, r.position.y), Vector2(r.position.x - map_bounds.position.x, r.size.y)), FOG)
	if r.end.x < map_bounds.end.x:
		draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(map_bounds.end.x - r.end.x, r.size.y)), FOG)
	draw_rect(r, BORDER, false, 2.0)
