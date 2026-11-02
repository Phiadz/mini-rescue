extends Node
# Test tự động cho Graph View (NodeLayer, EdgeLayer, EdgeDrawer). Chủ sở hữu: E.
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/test_graph_view_auto.tscn
# Thao tác chuột được giả lập bằng Input.parse_input_event để đi qua đúng đường nhận sự kiện thật.
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const FIXTURE_MAP := 'res://data/map_01.json'  # bản đồ cố định cho test

@onready var _drawer: Node2D = $'../EdgeDrawer'

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	await _frames(2)

	print('\n== Bản đồ')
	_check(GraphManager.get_node_ids().size() == 10, 'nạp đủ 10 điểm')

	print('\n== Tô đường')
	await _drag(_pos(0), _pos(3))
	_check(GraphManager.find_path(0, 3, Types.VehicleType.TRUCK).found, 'lia nhanh từ Kho Bắc sang Chợ Cũ vẫn ra đường liền')
	_check(_used() == 4, 'tô đúng 4 ô giữa hai điểm (%d)' % _used())
	await _drag(_pos(3) + Vector2(15, 5), _pos(5) + Vector2(-10, 12))
	_check(GraphManager.find_path(3, 5, Types.VehicleType.TRUCK).found, 'bấm và thả lệch tâm trong bán kính chọn vẫn nối vào điểm')
	var used := _used()
	await _drag(_at(15, 12), _at(17, 12))
	_check(_used() == used + 3 and GraphManager.road_at(Vector2i(16, 12)) != -1, 'bắt đầu từ ô trống vẫn tô được')
	await _drag(_at(15, 13), _at(17, 13))
	_check(GraphManager.get_edges_of(GraphManager.road_at(Vector2i(16, 13))).size() == 2, 'hai đường sát nhau không tự nối')
	await _drag(_at(16, 12), _at(16, 11))
	_check(GraphManager.get_edges_of(GraphManager.road_at(Vector2i(16, 12))).size() == 3, 'kéo từ đường có sẵn tạo ngã rẽ')
	used = _used()
	await _drag(_at(15, 12), _at(17, 12))
	_check(_used() == used, 'kéo lại trên đường có sẵn không tốn hạn mức')
	await _drag(_pos(4), _pos(4) + Vector2(5, 0))
	_check(_used() == used, 'bấm rồi thả ngay tại một điểm không tô gì')

	print('\n== Xóa ô')
	await _click(_at(16, 11), MOUSE_BUTTON_RIGHT)
	_check(GraphManager.road_at(Vector2i(16, 11)) == -1 and _used() == used - 1, 'chuột phải vào ô thì xóa ô, hoàn hạn mức')
	used = _used()
	await _click(_at(25, 2), MOUSE_BUTTON_RIGHT)
	_check(_used() == used, 'chuột phải vào ô trống không làm gì')
	await _button(_at(15, 13), MOUSE_BUTTON_RIGHT, true)
	await _move(_at(17, 13))
	await _button(_at(17, 13), MOUSE_BUTTON_RIGHT, false)
	_check(_used() == used - 3, 'giữ chuột phải và rê thì xóa cả dãy ô')
	await _move(_at(16, 12))
	_check(_drawer._hover_cell == Vector2i(16, 12), 'rê chuột lên ô thì ô được chọn')
	await _key(KEY_DELETE)
	_check(GraphManager.road_at(Vector2i(16, 12)) == -1, 'nhấn Delete xóa ô đang chọn')

	print('\n== Hạn mức')
	await _drag(_at(0, 16), _at(31, 16))
	await _drag(_at(0, 17), _at(31, 17))
	var limit: int = GraphManager.get_edge_budget().limit
	_check(_used() == limit, 'tô dài bị dừng đúng ở hạn mức %d ô' % limit)
	_check(_drawer._reject_left > 0.0, 'ô bị từ chối được nháy đỏ')

	print('\n== Trạng thái đường')
	var eid: int = GraphManager.get_edge_ids()[0]
	for s in [Types.EdgeState.SHALLOW, Types.EdgeState.DEEP, Types.EdgeState.DRY]:
		GraphManager.set_edge_state(eid, s)
		await _frames(1)
	_check(GraphManager.get_edge(eid).state == Types.EdgeState.DRY, 'đổi trạng thái đường qua 3 kiểu vẽ không lỗi')

	print('\n== Chặn thao tác ngoài lúc chơi')
	GraphManager.add_edge_limit(5)
	var road := GraphManager.cell_center(Vector2i(0, 16))
	get_tree().paused = true
	await _drag(_at(25, 2), _at(27, 2))
	_check(GraphManager.road_at(Vector2i(26, 2)) == -1, 'khi tạm dừng, không tô được')
	await _click(road, MOUSE_BUTTON_RIGHT)
	_check(GraphManager.road_at(Vector2i(0, 16)) != -1, 'khi tạm dừng, chuột phải không xóa')
	get_tree().paused = false
	_drawer.only_in_round = true  # GameManager đang ở MENU
	await _drag(_at(25, 2), _at(27, 2))
	_check(GraphManager.road_at(Vector2i(26, 2)) == -1, 'ở menu (không trong ván), không tô được')
	await _click(road, MOUSE_BUTTON_RIGHT)
	_check(GraphManager.road_at(Vector2i(0, 16)) != -1, 'ở menu (không trong ván), chuột phải không xóa')
	_drawer.only_in_round = false

	print('\n== Chơi lại')
	GraphManager.load_map(FIXTURE_MAP)
	EventBus.game_started.emit()
	await _frames(1)
	_check(GraphManager.get_edge_ids().size() == 0 and _used() == 0, 'nạp lại bản đồ và phát game_started thì sạch đường')
	await _drag(_pos(0), _pos(2))
	_check(GraphManager.find_path(0, 2, Types.VehicleType.TRUCK).found, 'ván mới vẫn tô đường bình thường')

	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _used() -> int:
	return GraphManager.get_edge_budget().used


func _at(x: int, y: int) -> Vector2:
	return GraphManager.cell_center(Vector2i(x, y))


func _pos(id: int) -> Vector2:
	return GraphManager.get_map_node(id).pos


func _drag(from: Vector2, to: Vector2) -> void:
	await _button(from, MOUSE_BUTTON_LEFT, true)
	await _move(to)
	await _button(to, MOUSE_BUTTON_LEFT, false)


func _click(at: Vector2, button: MouseButton) -> void:
	await _move(at)
	await _button(at, button, true)
	await _button(at, button, false)


func _button(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = _to_window(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(1)


func _move(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _to_window(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(1)


# Sự kiện chuột mang tọa độ cửa sổ; cửa sổ headless nhỏ hơn 1280×720 nên phải đổi qua phép co giãn.
func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT]   ', label)
	else:
		_failed += 1
		print('  [TRƯỢT] ', label)
