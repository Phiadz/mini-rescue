extends Node2D
# Chủ sở hữu: E. Giữ chuột trái và kéo để tô đường từng ô, đi được 8 hướng; giữ chuột phải và rê,
# hoặc rê chuột lên ô rồi nhấn Delete, để xóa ô.
# Dùng _unhandled_input để nút giao diện nhận chuột trước. Sự kiện chuột được đổi về tọa độ
# cục bộ (make_input_local), trùng tọa độ bản đồ của GraphManager dù scene cha có dịch đi.

const NO_CELL := Vector2i(-1, -1)
const PICK_RADIUS := 24.0
const DOT_COLOR := Color(0.2, 0.3, 0.4, 0.3)
const DOT_RADIUS := 1.5
const HOVER_COLOR := Color(0.2, 0.3, 0.4, 0.5)
const REJECT_COLOR := Color(1.0, 0.27, 0.0, 0.7)
const REJECT_TIME := 0.4

## Chỉ cho vẽ trong ván (PLAYING, WAVE_BREAK), vì menu và màn hình khác để chuột đi xuyên qua.
## Scene thử tắt cờ này để chạy riêng, không cần GameManager.
@export var only_in_round := true

var _painting := false
var _erasing := false
var _last_node := -1          # nút vừa tô, ô sau nối tiếp từ đây
var _last_cell := NO_CELL     # ô cuối cùng đã xử lý khi đang kéo
var _cursor := Vector2.ZERO
var _hover_cell := NO_CELL
var _reject_cell := NO_CELL
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
		_hover_cell = GraphManager.cell_of(_cursor)
	if event is InputEventMouseMotion:
		_on_mouse_motion()
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	else:
		_on_key(event)


func _on_mouse_motion() -> void:
	if _painting:
		_paint_to(_paint_cell())
	elif _erasing:
		_erase_to(_hover_cell)
	queue_redraw()


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_start_paint()
		else:
			_painting = false
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_erasing = mb.pressed
		if _erasing:
			_last_cell = _hover_cell
			GraphManager.remove_road(_hover_cell)
	else:
		return
	queue_redraw()
	get_viewport().set_input_as_handled()


func _on_key(key: InputEventKey) -> void:
	if key.pressed and not key.echo and key.keycode == KEY_DELETE and GraphManager.remove_road(_hover_cell):
		queue_redraw()
		get_viewport().set_input_as_handled()


func _start_paint() -> void:
	var cell := _paint_cell()
	_last_node = GraphManager.extend_road(-1, cell)
	if _last_node == -1:
		_reject(cell)
		return
	_last_cell = cell
	_painting = true


func _paint_to(to: Vector2i) -> void:
	for cell in _cells_to(to):
		var next := GraphManager.extend_road(_last_node, cell)
		if next == -1:
			_painting = false
			_reject(cell)
			return
		_last_node = next
		_last_cell = cell


func _erase_to(to: Vector2i) -> void:
	for cell in _cells_to(to):
		GraphManager.remove_road(cell)
		_last_cell = cell


# Các ô từ _last_cell tới to, mỗi bước sang ô kề, để chuột lia nhanh không làm đứt đường.
func _cells_to(to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var steps := maxi(absi(to.x - _last_cell.x), absi(to.y - _last_cell.y))
	for i in range(1, steps + 1):
		out.append(Vector2i(Vector2(_last_cell).lerp(Vector2(to), float(i) / steps).round()))
	return out


# Ô dưới con trỏ khi tô; con trỏ chạm vào một điểm thì lấy ô của điểm đó.
func _paint_cell() -> Vector2i:
	var point := _node_at(_cursor)
	return GraphManager.cell_of(GraphManager.get_map_node(point).pos) if point != -1 else _hover_cell


func _draw() -> void:
	if _painting or _erasing:
		for y in Config.GRID_ROWS:
			for x in Config.GRID_COLS:
				draw_circle(GraphManager.cell_center(Vector2i(x, y)), DOT_RADIUS, DOT_COLOR)
	if _hover_cell != NO_CELL:
		draw_rect(_cell_rect(_hover_cell), HOVER_COLOR, false, 2.0)
	if _reject_left > 0.0:
		draw_rect(_cell_rect(_reject_cell), REJECT_COLOR)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell * Config.CELL_SIZE), Vector2.ONE * Config.CELL_SIZE)


func _cancel() -> void:
	_painting = false
	_erasing = false
	_hover_cell = NO_CELL
	queue_redraw()


func _reject(cell: Vector2i) -> void:
	_reject_cell = cell
	_reject_left = REJECT_TIME
	set_process(true)


func _in_round() -> bool:
	return GameManager.state == Types.GameState.PLAYING or GameManager.state == Types.GameState.WAVE_BREAK


# Điểm gần nhất trong bán kính PICK_RADIUS, hoặc -1.
func _node_at(p: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for id in GraphManager.get_node_ids():
		var n := GraphManager.get_map_node(id)
		if n != null and n.pos.distance_to(p) < best_d:
			best_d = n.pos.distance_to(p)
			best = id
	return best
