extends Node2D
# Chủ sở hữu: E. Giữ chuột trái và kéo để tô đường từng ô, đi được 8 hướng; giữ chuột phải và rê,
# hoặc rê chuột lên ô rồi nhấn Delete, để xóa ô.
# Dùng _unhandled_input để nút giao diện nhận chuột trước. Sự kiện chuột được đổi về tọa độ
# cục bộ (make_input_local), trùng tọa độ bản đồ của GraphManager dù scene cha có dịch đi.

const NO_CELL := Vector2i(-1, -1)
const PICK_RADIUS := 24.0
const DOT_COLOR := Color(0.2, 0.3, 0.4, 0.3)
const DOT_RADIUS := 1.5
# Chấm lưới lúc kéo (576 chấm) vẽ một lần ở lớp con _dots bằng một lệnh draw_multiline, chỉ bật tắt khi bắt đầu, thôi
# kéo: trước đây mỗi lần di chuột vẽ lại 576 hình tròn, làm tụt FPS rõ khi nối đường trên bản web.
var _dots: Node2D
const HOVER_COLOR := Color(0.2, 0.3, 0.4, 0.5)
const REJECT_COLOR := Color(1.0, 0.27, 0.0, 0.7)
const REJECT_TIME := 0.4

## Chỉ cho vẽ trong ván (PLAYING, WAVE_BREAK), vì menu và màn hình khác để chuột đi xuyên qua.
## Scene thử tắt cờ này để chạy riêng, không cần GameManager.
@export var only_in_round := true

enum Tool { ROAD = 0, FERRY = 1 }
var active_tool: int = Tool.ROAD
var _ferry_start_cell := NO_CELL

var _painting := false
var _erasing := false
var _last_node := -1          # nút vừa tô, ô sau nối tiếp từ đây
var _last_cell := NO_CELL     # ô cuối cùng đã xử lý khi đang kéo
var _stroke_cells: Array[Vector2i] = []  # chuỗi ô trong nét kéo hiện tại để nhận diện nắn đường chéo
var _cursor := Vector2.ZERO
var _hover_cell := NO_CELL
var _reject_cell := NO_CELL
var _reject_left := 0.0


func _ready() -> void:
	_dots = Node2D.new()
	_dots.name = 'Dots'
	_dots.visible = false
	_dots.show_behind_parent = true
	_dots.draw.connect(_draw_dots)
	add_child(_dots)
	EventBus.game_started.connect(_cancel)
	EventBus.game_state_changed.connect(func(_s: int) -> void: _cancel())  # bỏ thao tác dở khi tạm dừng, kết thúc
	EventBus.active_tool_changed.connect(_on_tool_changed)
	set_process(false)


func _on_tool_changed(tool_id: int) -> void:
	active_tool = tool_id
	_ferry_start_cell = NO_CELL
	_painting = false
	_erasing = false
	_sync_dots()
	queue_redraw()


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
	if active_tool == Tool.FERRY:
		_on_mouse_button_ferry(mb)
		return

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_start_paint()
		else:
			_painting = false
			_stroke_cells.clear()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_erasing = mb.pressed
		_stroke_cells.clear()
		if _erasing:
			_last_cell = _hover_cell
			GraphManager.remove_road(_hover_cell)
	else:
		return
	_sync_dots()
	queue_redraw()
	get_viewport().set_input_as_handled()


func _on_mouse_button_ferry(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		var target_cell := _hover_cell
		if _ferry_start_cell == NO_CELL:
			if not GameManager.is_in_play(GraphManager.cell_center(target_cell)):
				_reject(target_cell)
				return
			# Chỉ cho phép chọn điểm xuất phát Bến phà từ ô ĐÃ CÓ ĐƯỜNG
			if GraphManager.road_at(target_cell) == -1:
				_reject(target_cell)
				return
			_ferry_start_cell = target_cell
			queue_redraw()
		else:
			if target_cell == _ferry_start_cell or not GameManager.is_in_play(GraphManager.cell_center(target_cell)):
				_reject(target_cell)
				return
			if GraphManager.place_ferry(_ferry_start_cell, target_cell):
				_ferry_start_cell = NO_CELL
				if GraphManager.get_ferries_available() <= 0:
					EventBus.active_tool_changed.emit(Tool.ROAD)
			else:
				_reject(target_cell)
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _ferry_start_cell != NO_CELL:
			_ferry_start_cell = NO_CELL
			queue_redraw()
		else:
			if GraphManager.remove_ferry_at_cell(_hover_cell):
				queue_redraw()
			else:
				EventBus.active_tool_changed.emit(Tool.ROAD)
		get_viewport().set_input_as_handled()


func _on_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_1:
		EventBus.active_tool_changed.emit(Tool.ROAD)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_2:
		if GraphManager.get_ferries_available() > 0:
			EventBus.active_tool_changed.emit(Tool.FERRY)
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE:
		if active_tool == Tool.FERRY:
			if _ferry_start_cell != NO_CELL:
				_ferry_start_cell = NO_CELL
			else:
				EventBus.active_tool_changed.emit(Tool.ROAD)
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DELETE:
		if GraphManager.remove_ferry_at_cell(_hover_cell) or GraphManager.remove_road(_hover_cell):
			queue_redraw()
			get_viewport().set_input_as_handled()


func _start_paint() -> void:
	var cell := _paint_cell()
	if not GameManager.is_in_play(GraphManager.cell_center(cell)):
		_reject(cell)  # ngoài vùng đã mở
		return
	_last_node = GraphManager.extend_road(-1, cell)
	if _last_node == -1:
		_reject(cell)
		return
	_last_cell = cell
	_stroke_cells = [cell]
	_painting = true


func _paint_to(to: Vector2i) -> void:
	for cell in _cells_to(to):
		if cell == _last_cell:
			continue
		_try_collapse_corner(cell)
		var next := GraphManager.extend_road(_last_node, cell) if GameManager.is_in_play(GraphManager.cell_center(cell)) else -1
		if next == -1:
			_painting = false
			_stroke_cells.clear()
			_sync_dots()
			_reject(cell)
			return
		_last_node = next
		_last_cell = cell
		if _stroke_cells.is_empty() or _stroke_cells[-1] != cell:
			_stroke_cells.append(cell)


# Nhận diện nét kéo chéo và gập góc vuông L thành 1 cạnh chéo duy nhất
func _try_collapse_corner(to: Vector2i) -> bool:
	if _stroke_cells.size() < 2:
		return false
	var a: Vector2i = _stroke_cells[-2]
	var b: Vector2i = _stroke_cells[-1]
	var c: Vector2i = to
	
	# C phải là ô chéo của A
	if absi(c.x - a.x) != 1 or absi(c.y - a.y) != 1:
		return false
	
	# Không tự động gập góc nếu A hoặc C là điểm công trình (nhà, kho, khu)
	# để người chơi có thể chủ động rẽ thẳng vào nhà hoặc từ nhà rẽ ra mà không bị gập góc mất đoạn nối
	if GraphManager.is_point_cell(a) or GraphManager.is_point_cell(c):
		return false
	
	# B phải là ô góc vuông trung gian giữa A và C
	if not ((b.x == a.x and b.y == c.y) or (b.x == c.x and b.y == a.y)):
		return false
	
	# Đường chéo A -> C phải hợp lệ theo luật bản đồ (không bị cấn góc công trình/cổng)
	if not GraphManager.diagonal_ok(a, c):
		return false
	
	# Ô góc B phải là ô đường thuần túy được tạo trong nét vẽ, chưa có nhánh rẽ nào khác
	var b_id: int = GraphManager.road_at(b)
	if b_id == -1:
		return false
	if GraphManager.is_point_cell(b) or GraphManager.is_gate_cell(b) or GraphManager.is_lot_cell(b):
		return false
	if GraphManager.get_edges_of(b_id).size() > 1:
		return false # B đã có đường khác rẽ vào, không được phá vỡ
	
	# Hợp lệ: Gỡ bỏ góc B, trả lại 1 hạn mức đường và nối thẳng chéo A -> C
	GraphManager.remove_road(b)
	_stroke_cells.pop_back()
	_last_node = GraphManager.get_node_at_cell(a)
	_last_cell = a
	return true


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
	if active_tool == Tool.FERRY:
		_draw_ferry_preview()
	else:
		if _hover_cell != NO_CELL:
			draw_rect(_cell_rect(_hover_cell), HOVER_COLOR, false, 2.0)
	if _reject_left > 0.0:
		draw_rect(_cell_rect(_reject_cell), REJECT_COLOR)


func _draw_ferry_preview() -> void:
	var time_sec := Time.get_ticks_msec() / 1000.0
	var pulse := 0.8 + 0.2 * sin(time_sec * 5.0)

	if _ferry_start_cell != NO_CELL:
		var p_start: Vector2 = GraphManager.cell_center(_ferry_start_cell)
		# Bến bờ A đã chọn
		draw_circle(p_start, 13.0 * pulse, Color(0.15, 0.65, 0.85, 0.4))
		draw_circle(p_start, 7.0, Color(0.2, 0.8, 1.0, 0.9))
		draw_rect(_cell_rect(_ferry_start_cell), Color(0.2, 0.8, 1.0, 0.8), false, 2.5)

		# Đường nối preview sang bờ B / con trỏ
		if _hover_cell != NO_CELL and _hover_cell != _ferry_start_cell:
			var p_hover: Vector2 = GraphManager.cell_center(_hover_cell)
			var pts: PackedVector2Array = GraphManager.get_ferry_preview_points(_ferry_start_cell, _hover_cell)
			var valid := not pts.is_empty() and GraphManager.can_place_ferry(_ferry_start_cell, _hover_cell)
			var col: Color = Color(0.25, 0.85, 1.0, 0.85) if valid else Color(1.0, 0.3, 0.2, 0.75)

			if valid and pts.size() >= 2:
				for i in range(pts.size() - 1):
					var p1 := pts[i]
					var p2 := pts[i + 1]
					var d := p1.distance_to(p2)
					var steps := maxi(2, int(d / 14.0))
					for s in steps:
						if s % 2 == 0:
							var t1 := float(s) / steps
							var t2 := float(s + 1) / steps
							draw_line(p1.lerp(p2, t1), p1.lerp(p2, t2), col, 2.5)
			else:
				var dist := p_start.distance_to(p_hover)
				var steps := maxi(3, int(dist / 14.0))
				for s in steps:
					if s % 2 == 0:
						var pt1 := p_start.lerp(p_hover, float(s) / steps)
						var pt2 := p_start.lerp(p_hover, float(s + 1) / steps)
						draw_line(pt1, pt2, col, 2.5)

			draw_rect(_cell_rect(_hover_cell), col, false, 2.0)
			draw_circle(p_hover, 5.5, col)
	else:
		if _hover_cell != NO_CELL and GameManager.is_in_play(GraphManager.cell_center(_hover_cell)):
			var p_hover: Vector2 = GraphManager.cell_center(_hover_cell)
			var is_road: bool = (GraphManager.road_at(_hover_cell) != -1)
			if is_road:
				# Gợi ý ô đường hợp lệ để bắt đầu đặt bến phà
				draw_rect(_cell_rect(_hover_cell), Color(0.2, 0.8, 1.0, 0.8 * pulse), false, 2.5)
				draw_circle(p_hover, 6.0, Color(0.2, 0.8, 1.0, 0.9))
			else:
				# Ô đất trống hoặc nước: không thể bắt đầu từ đây
				draw_rect(_cell_rect(_hover_cell), Color(0.6, 0.6, 0.6, 0.3), false, 1.5)


# Chấm lưới hiện trong lúc kéo tô hoặc xóa.
func _sync_dots() -> void:
	if _dots != null:
		_dots.visible = _painting or _erasing


func _draw_dots() -> void:
	var segs := PackedVector2Array()
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			var c := GraphManager.cell_center(Vector2i(x, y))
			segs.append(c - Vector2(DOT_RADIUS, 0.0))
			segs.append(c + Vector2(DOT_RADIUS, 0.0))
	_dots.draw_multiline(segs, DOT_COLOR, DOT_RADIUS * 2.0)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell * Config.CELL_SIZE), Vector2.ONE * Config.CELL_SIZE)


func _cancel() -> void:
	_painting = false
	_erasing = false
	_stroke_cells.clear()
	_sync_dots()
	_hover_cell = NO_CELL
	_ferry_start_cell = NO_CELL
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
