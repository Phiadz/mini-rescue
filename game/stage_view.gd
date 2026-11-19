extends Node2D
# Vùng chơi theo đợt (E). GameManager tạo node này trong World mỗi ván.
# Bản đồ khai báo "stages": [{center: [x, y], zoom: z}, ...], mỗi đợt một vùng (đợt i dùng stages[i]):
# camera phóng to vào vùng đó; hết mỗi đợt, đầu lượt nghỉ, camera thu ra vùng kế tiếp để mở thêm khu dân cư.
# Zoom luôn >= 1 nên chữ và biểu tượng không bao giờ nhỏ hơn kích thước gốc.
# Ngoài vùng chơi (gồm dải mép EDGE_MARGIN) không tô đường, không sinh SOS; vẽ một lớp tối nhẹ để người chơi thấy giới hạn.
# Bản đồ không khai báo stages thì thấy cả bản đồ như cũ.

const MAP_SIZE := Vector2(1280, 720)
const EDGE_MARGIN := 40.0  # đơn vị bản đồ; vùng cuối (zoom 1) không có mép
const MOVE_TIME := 1.6
const FOG := Color(0.02, 0.05, 0.1, 0.32)
const BORDER := Color(1.0, 1.0, 1.0, 0.35)

var camera := Camera2D.new()
var fog_rect := Rect2(Vector2.ZERO, MAP_SIZE)  # vùng không phủ tối (đang tween cùng camera)
var _tween: Tween


func _ready() -> void:
	add_child(camera)
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.position = MAP_SIZE / 2.0
	camera.make_current()


# Hình chữ nhật camera nhìn thấy ở một vùng.
static func view_rect(stage: Dictionary) -> Rect2:
	var size: Vector2 = MAP_SIZE / float(stage.get('zoom', 1.0))
	var c := Vector2(stage.get('center', [MAP_SIZE.x / 2.0, MAP_SIZE.y / 2.0])[0], stage.get('center', [MAP_SIZE.x / 2.0, MAP_SIZE.y / 2.0])[1])
	return Rect2(c - size / 2.0, size)


# Vùng được chơi: vùng nhìn thấy trừ dải mép; vùng cuối (zoom 1) là cả bản đồ.
static func play_rect(stage: Dictionary) -> Rect2:
	var view := view_rect(stage)
	return view if float(stage.get('zoom', 1.0)) <= 1.001 else view.grow(-EDGE_MARGIN)


func apply(stage: Dictionary, animate: bool) -> void:
	var target_pos := view_rect(stage).get_center()
	var z := float(stage.get('zoom', 1.0))
	var target_fog := play_rect(stage)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate:
		camera.position = target_pos
		camera.zoom = Vector2(z, z)
		_set_fog(target_fog)
		return
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, 'position', target_pos, MOVE_TIME)
	_tween.tween_property(camera, 'zoom', Vector2(z, z), MOVE_TIME)
	_tween.tween_method(_set_fog, fog_rect, target_fog, MOVE_TIME)


func _set_fog(r: Rect2) -> void:
	fog_rect = r
	queue_redraw()


func _draw() -> void:
	if fog_rect.size.x >= MAP_SIZE.x - 1.0 and fog_rect.size.y >= MAP_SIZE.y - 1.0:
		return
	var outer := Rect2(-MAP_SIZE, MAP_SIZE * 3.0)
	var r := fog_rect
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, r.position.y - outer.position.y)), FOG)
	draw_rect(Rect2(Vector2(outer.position.x, r.end.y), Vector2(outer.size.x, outer.end.y - r.end.y)), FOG)
	draw_rect(Rect2(Vector2(outer.position.x, r.position.y), Vector2(r.position.x - outer.position.x, r.size.y)), FOG)
	draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(outer.end.x - r.end.x, r.size.y)), FOG)
	draw_rect(r, BORDER, false, 2.0)
