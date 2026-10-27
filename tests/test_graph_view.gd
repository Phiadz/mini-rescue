extends Node2D
# Scene thử bằng tay cho Graph View. Chủ sở hữu: E. Mở tests/test_graph_view.tscn rồi bấm F6.
# Chỉ trong scene thử này E được gọi GraphManager.set_edge_state (ngoài game chỉ B được gọi).

const HELP := 'Kéo chuột trái từ điểm này sang điểm khác: tạo tuyến    Chuột phải vào tuyến (hoặc rê lên tuyến rồi Delete): xóa\n' \
		+ '1 / 2 / 3: đổi tuyến vừa tạo sang khô / ngập nhẹ / ngập sâu    R: nạp lại bản đồ (giả lập chơi lại)'

var _label := Label.new()
var _last_edge := -1


func _ready() -> void:
	var layer := CanvasLayer.new()
	_label.position = Vector2(16, 650)
	layer.add_child(_label)
	add_child(layer)
	EventBus.edge_added.connect(func(id: int) -> void: _last_edge = id)
	EventBus.edge_removed.connect(func(id: int) -> void: _last_edge = -1 if id == _last_edge else _last_edge)
	_reload.call_deferred()  # chờ các lớp con _ready xong mới phát game_started


func _process(_delta: float) -> void:
	var budget := GraphManager.get_edge_budget()
	_label.text = '%s\nSố điểm: %d    Hạn mức tuyến: %d / %d    Tuyến vừa tạo: %d' % [
		HELP, GraphManager.get_node_ids().size(), budget.used, budget.limit, _last_edge]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			GraphManager.set_edge_state(_last_edge, Types.EdgeState.DRY)
		KEY_2:
			GraphManager.set_edge_state(_last_edge, Types.EdgeState.SHALLOW)
		KEY_3:
			GraphManager.set_edge_state(_last_edge, Types.EdgeState.DEEP)
		KEY_R:
			_reload()
		_:
			return
	get_viewport().set_input_as_handled()


# Giống trình tự trong GameManager.start_game(): nạp bản đồ rồi mới phát game_started.
func _reload() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	EventBus.game_started.emit()
	_last_edge = -1
