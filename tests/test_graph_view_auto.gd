extends Node
# Test tự động cho Graph View (NodeLayer, EdgeLayer, EdgeView, EdgeDrawer). Chủ sở hữu: E.
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/test_graph_view_auto.tscn
# Thao tác chuột được giả lập bằng Input.parse_input_event để đi qua đúng đường nhận sự kiện thật.
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

@onready var _edges: Node2D = $'../EdgeLayer'
@onready var _drawer: Node2D = $'../EdgeDrawer'

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	EventBus.game_started.emit()
	await _frames(2)
	var limit: int = GraphManager.get_edge_budget().limit

	print('\n== Bản đồ')
	_check(GraphManager.get_node_ids().size() == 10, 'nạp đủ 10 điểm')

	print('\n== Kéo thả tạo tuyến')
	await _drag(_pos(0), _pos(3))
	_check(GraphManager.get_edge_ids().size() == 1, 'kéo từ Kho Bắc sang Khu Chợ Cũ tạo 1 tuyến')
	_check(_views().size() == 1 and _views()[0].edge_id == GraphManager.get_edge_ids()[0],
			'EdgeLayer có đúng 1 EdgeView cho tuyến đó')
	await _drag(_pos(3) + Vector2(15, 5), _pos(5) + Vector2(-10, 12))
	_check(GraphManager.get_edge_ids().size() == 2, 'thả lệch tâm nhưng trong bán kính chọn vẫn tạo tuyến')
	await _drag(Vector2(600, 500), _pos(4))
	_check(GraphManager.get_edge_ids().size() == 2, 'bắt đầu kéo ở chỗ trống thì không tạo tuyến')
	await _drag(_pos(4), Vector2(560, 560))
	_check(GraphManager.get_edge_ids().size() == 2, 'thả ở chỗ trống thì không tạo tuyến')
	await _drag(_pos(4), _pos(4) + Vector2(5, 0))
	_check(GraphManager.get_edge_ids().size() == 2, 'thả lại đúng điểm xuất phát thì không tạo tuyến')
	await _drag(_pos(3), _pos(0))
	_check(GraphManager.get_edge_ids().size() == 2, 'nối lại hai điểm đã có tuyến thì bị từ chối')
	_check(_drawer._reject_left > 0.0, 'tuyến bị từ chối được nháy đỏ')

	print('\n== Xóa tuyến')
	var e0 := GraphManager.get_edge(GraphManager.get_edge_ids()[0])
	await _click(_pos(e0.node_a).lerp(_pos(e0.node_b), 0.5), MOUSE_BUTTON_RIGHT)
	await _frames(1)
	_check(GraphManager.get_edge_ids().size() == 1 and _views().size() == 1,
			'chuột phải vào giữa tuyến thì xóa tuyến và EdgeView')
	var e1 := GraphManager.get_edge(GraphManager.get_edge_ids()[0])
	await _click(_pos(e1.node_a).lerp(_pos(e1.node_b), 0.5) + Vector2(0, 30), MOUSE_BUTTON_RIGHT)
	_check(GraphManager.get_edge_ids().size() == 1, 'chuột phải xa tuyến thì không xóa')
	await _move(_pos(e1.node_a).lerp(_pos(e1.node_b), 0.3))
	_check(_drawer._hover_edge == e1.id, 'rê chuột lên tuyến thì tuyến được chọn')
	await _key(KEY_DELETE)
	await _frames(1)
	_check(GraphManager.get_edge_ids().size() == 0 and _views().size() == 0, 'nhấn Delete xóa tuyến đang chọn')

	print('\n== Hạn mức tuyến')
	var pairs := [[0, 2], [0, 3], [2, 3], [2, 4], [3, 4], [3, 5], [4, 5], [5, 6], [5, 7], [6, 8],
			[7, 8], [1, 7], [1, 9], [4, 9]]
	for p in pairs:
		await _drag(_pos(p[0]), _pos(p[1]))
	_check(GraphManager.get_edge_ids().size() == limit and _views().size() == limit,
			'kéo %d lần chỉ tạo đúng %d tuyến (hạn mức)' % [pairs.size(), limit])

	print('\n== Trạng thái tuyến')
	var eid: int = GraphManager.get_edge_ids()[0]
	for s in [Types.EdgeState.SHALLOW, Types.EdgeState.DEEP, Types.EdgeState.DRY]:
		GraphManager.set_edge_state(eid, s)
		await _frames(1)
	_check(GraphManager.get_edge(eid).state == Types.EdgeState.DRY, 'đổi trạng thái tuyến qua 3 kiểu nét không lỗi')

	print('\n== Chặn thao tác ngoài lúc chơi')
	get_tree().paused = true
	var before := GraphManager.get_edge_ids().size()
	var victim := GraphManager.get_edge(eid)
	await _click(_pos(victim.node_a).lerp(_pos(victim.node_b), 0.5), MOUSE_BUTTON_RIGHT)
	_check(GraphManager.get_edge_ids().size() == before, 'khi tạm dừng, chuột phải không xóa tuyến')
	get_tree().paused = false
	_drawer.only_in_round = true  # GameManager đang ở MENU
	await _click(_pos(victim.node_a).lerp(_pos(victim.node_b), 0.5), MOUSE_BUTTON_RIGHT)
	_check(GraphManager.get_edge_ids().size() == before, 'ở menu (không trong ván), chuột phải không xóa tuyến')
	_drawer.only_in_round = false

	print('\n== Chơi lại')
	GraphManager.load_map(Config.MAP_PATH)
	EventBus.game_started.emit()
	await _frames(1)
	_check(GraphManager.get_edge_ids().size() == 0 and _views().size() == 0,
			'nạp lại bản đồ và phát game_started thì xóa hết EdgeView')
	await _drag(_pos(0), _pos(2))
	_check(_views().size() == 1, 'ván mới vẫn tạo tuyến bình thường')

	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _views() -> Array:
	return _edges.get_children().filter(func(c): return not c.is_queued_for_deletion())


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
