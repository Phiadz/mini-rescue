extends Node
# Tự chơi nhiều ván trên mạng đường cố định để chỉnh hạn mức, đồng thời đo thời gian tìm đường.
# Không có kiểm tra đạt/trượt: chỉ in số liệu. Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_balance_auto.tscn
# Cách chơi cố định: nối sẵn 10 đường, không sửa đường, không chọn thưởng. Không thay cho người chơi thật.

const SPEED := 10.0
const GAMES := 10
# 16 tuyến đầu nối hết 17 điểm; các tuyến sau là đường vòng, tô tới khi hết hạn mức.
const ROUTES := [[0, 16], [16, 5], [5, 10], [10, 3], [3, 2], [3, 6], [6, 11], [11, 7], [2, 14], [7, 8], [8, 12], [12, 13],
		[13, 1], [14, 9], [2, 4], [4, 15], [6, 14], [7, 12], [8, 10], [0, 5], [11, 13], [4, 9]]

var _stats := {}
var _won := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	reparent(get_tree().root)  # start_game() đổi sang main.tscn, node này phải sống sót
	EventBus.game_won.connect(func(st: Dictionary) -> void:
		_stats = st
		_won = true)
	EventBus.game_lost.connect(func(st: Dictionary) -> void:
		_stats = st
		_won = false)
	EventBus.wave_ended.connect(_print_states)
	Engine.time_scale = SPEED
	var wins := 0
	var scores := 0
	for i in GAMES:
		_stats = {}
		await GameManager.start_game()
		_build()
		var used: int = GraphManager.get_edge_budget().used
		while _stats.is_empty():
			await get_tree().process_frame
		wins += 1 if _won else 0
		scores += _stats.score
		print('Ván %2d: %-5s %4d điểm, cứu %2d, thất bại %d, %3.0f giây, %d ô đường' % [
			i + 1, 'thắng' if _won else 'thua', _stats.score, _stats.saved, _stats.failed, _stats.time_survived, used])
	print('Tổng: thắng %d/%d, điểm trung bình %.0f' % [wins, GAMES, float(scores) / GAMES])
	_time_find_path()
	get_tree().quit()


func _build() -> void:
	for r in ROUTES:
		var from := _cell(r[0])
		var to := _cell(r[1])
		var last: int = r[0]
		var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
		for i in range(1, steps + 1):
			var cell := Vector2i(Vector2(from).lerp(Vector2(to), float(i) / steps).round())
			last = GraphManager.extend_road(last, cell)
			if last == -1:
				return  # hết hạn mức


# Số cạnh đường theo trạng thái khi hết mỗi đợt, để so độ ngập với kỳ vọng.
func _print_states(wave: int) -> void:
	var count := [0, 0, 0]
	for e in GraphManager.get_edge_ids():
		count[GraphManager.get_edge(e).state] += 1
	print('  hết đợt %d: nước %.0f, khô %d, ngập nhẹ %d, ngập sâu %d' % [wave + 1, FloodManager.water_level, count[0], count[1], count[2]])


func _cell(point: int) -> Vector2i:
	return GraphManager.cell_of(GraphManager.get_map_node(point).pos)


# Đường dài nhất trên bản đồ: giữa hai kho.
func _time_find_path() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	EventBus.game_started.emit()
	_build()
	var start := Time.get_ticks_usec()
	for i in 100:
		GraphManager.find_path(0, 1, Types.VehicleType.TRUCK)
	var usec := (Time.get_ticks_usec() - start) / 100.0
	print('find_path: %.0f micro giây mỗi lần, %d nút đường, %d cạnh' % [
		usec, GraphManager.get_road_ids().size(), GraphManager.get_edge_ids().size()])
