extends Node2D
# Chủ sở hữu: E. Kéo chuột trái từ node này sang node kia để tạo tuyến; chuột phải vào tuyến,
# hoặc rê chuột lên tuyến rồi nhấn Delete, để xóa (Tài liệu chốt 1.3).
# Dùng _unhandled_input để nút giao diện nhận chuột trước. Sự kiện chuột được đổi về tọa độ
# cục bộ (make_input_local), trùng tọa độ bản đồ của GraphManager dù scene cha có dịch đi.

const PICK_RADIUS := 24.0
const EDGE_PICK := 10.0
const PREVIEW_COLOR := Color('#FFFFFF')
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const HOVER_WIDTH := 12.0
const REJECT_COLOR := Color('#FF4500')
const REJECT_TIME := 0.4

## Chỉ cho vẽ trong ván (PLAYING, WAVE_BREAK), vì menu và màn hình khác để chuột đi xuyên qua.
## Scene thử tắt cờ này để chạy riêng, không cần GameManager.
@export var only_in_round := true

var _from_id := -1
var _cursor := Vector2.ZERO
var _hover_edge := -1
var _reject_a := Vector2.ZERO
var _reject_b := Vector2.ZERO
var _reject_left := 0.0


func _ready() -> void:
	EventBus.game_started.connect(_cancel)
	EventBus.game_state_changed.connect(func(_s: int) -> void: _cancel())  # bỏ thao tác dở khi tạm dừng, kết thúc
	set_process(false)


func _process(delta: float) -> void:
	_reject_left -= delta
	if _reject_left <= 0.0:
		set_process(false)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouse or event is InputEventKey):
		return
	if only_in_round and not _in_round():
		return
	if event is InputEventMouse:
		_cursor = (make_input_local(event) as InputEventMouse).position
	if event is InputEventMouseMotion:
		_hover_edge = _edge_near(_cursor) if _from_id == -1 else -1
		queue_redraw()
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	else:
		_on_key(event)


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_from_id = _node_at(_cursor)
			if _from_id == -1:
				return
			_hover_edge = -1
		elif _from_id != -1:
			var to_id := _node_at(_cursor)
			if to_id != -1 and to_id != _from_id and GraphManager.add_edge(_from_id, to_id) == -1:
				_reject(_from_id, to_id)  # hết hạn mức hoặc đã có tuyến
			_from_id = -1
		else:
			return
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _from_id == -1:
		var eid := _edge_near(_cursor)
		if eid == -1:
			return
		GraphManager.remove_edge(eid)
		_hover_edge = -1
	else:
		return
	queue_redraw()
	get_viewport().set_input_as_handled()


func _on_key(key: InputEventKey) -> void:
	if key.pressed and not key.echo and key.keycode == KEY_DELETE and _hover_edge != -1:
		GraphManager.remove_edge(_hover_edge)
		_hover_edge = -1
		queue_redraw()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _hover_edge != -1:
		var e := GraphManager.get_edge(_hover_edge)
		if e != null:
			draw_line(_pos(e.node_a), _pos(e.node_b), HOVER_COLOR, HOVER_WIDTH)
	if _from_id != -1:
		var a := _pos(_from_id)
		var to_id := _node_at(_cursor)
		var end := _pos(to_id) if to_id != -1 and to_id != _from_id else _cursor
		draw_arc(a, PICK_RADIUS, 0.0, TAU, 32, PREVIEW_COLOR, 2.0)
		draw_dashed_line(a, end, PREVIEW_COLOR, 2.0, 8.0)
	if _reject_left > 0.0:
		draw_line(_reject_a, _reject_b, REJECT_COLOR, 4.0)


func _cancel() -> void:
	_from_id = -1
	_hover_edge = -1
	queue_redraw()


func _reject(a: int, b: int) -> void:
	_reject_a = _pos(a)
	_reject_b = _pos(b)
	_reject_left = REJECT_TIME
	set_process(true)


func _in_round() -> bool:
	return GameManager.state == Types.GameState.PLAYING or GameManager.state == Types.GameState.WAVE_BREAK


func _pos(id: int) -> Vector2:
	var n := GraphManager.get_map_node(id)
	return n.pos if n != null else Vector2.ZERO


# Node gần nhất trong bán kính PICK_RADIUS, hoặc -1.
func _node_at(p: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if n != null and n.pos.distance_to(p) < best_d:
			best_d = n.pos.distance_to(p)
			best = id
	return best


# Tuyến gần nhất trong khoảng EDGE_PICK, hoặc -1.
func _edge_near(p: Vector2) -> int:
	var best := -1
	var best_d := EDGE_PICK
	for eid in GraphManager.get_edge_ids():
		var e := GraphManager.get_edge(eid)
		if e == null:
			continue
		var d := Geometry2D.get_closest_point_to_segment(p, _pos(e.node_a), _pos(e.node_b)).distance_to(p)
		if d < best_d:
			best_d = d
			best = eid
	return best
