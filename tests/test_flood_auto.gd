extends Node
# Test tự động cho module Flood (lũ lan theo ô).
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_flood_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const TICK := 0.25

var _passed := 0
var _failed := 0
var _warnings: Array = []


func _ready() -> void:
	EventBus.flood_warning.connect(func(e: int, s: float) -> void: _warnings.append([e, s]))
	_run.call_deferred()


func _run() -> void:
	_test_states()
	await _test_rise_and_stop()
	_test_sea()
	_test_spread_gradually()
	_test_blocked_basin()
	_test_no_recede()
	_test_edges_follow_deepest()
	_test_warning_once()
	_test_warning_dry()
	_test_overlay()
	FloodManager.reset()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fresh() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	FloodManager.reset()
	_warnings.clear()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Config.GRID_ROWS:
		for x in Config.GRID_COLS:
			out.append(Vector2i(x, y))
	return out


func _wet_land() -> Array[Vector2i]:
	return _all_cells().filter(func(c: Vector2i) -> bool:
		return not FloodManager.is_sea(c) and FloodManager.depth_at(c) >= FloodManager.DRY_EPSILON)


# Chạy mô phỏng tới khi không còn ô nào đổi (tối đa `limit` bước), trả về số bước.
func _settle(limit: int = 400) -> int:
	for i in limit:
		var before := FloodManager._level.duplicate()
		FloodManager.step(TICK)
		if FloodManager._level == before:
			return i
	return limit


func _test_states() -> void:
	print('\n== Trạng thái theo độ sâu')
	_fresh()
	for c in [[0.0, Types.EdgeState.DRY], [1.0, Types.EdgeState.SHALLOW], [14.9, Types.EdgeState.SHALLOW], [15.0, Types.EdgeState.DEEP]]:
		_check(FloodManager.state_for_depth(c[0]) == c[1], 'sâu %s' % c[0])
	FloodManager.water_level = 25.0
	_check(FloodManager.compute_state(10.0) == Types.EdgeState.DEEP, 'compute_state theo mực biển vẫn dùng được')


func _test_rise_and_stop() -> void:
	print('\n== Mực biển dâng theo đợt')
	_fresh()
	FloodManager.start_wave(0)
	var rate: float = Config.WAVES[0].water_delta / Config.WAVE_DURATION
	await _frames(60)
	_check(absf(FloodManager.water_level - rate) < 0.02, 'sau 1 giây mực biển dâng đúng water_delta / WAVE_DURATION (%.3f)' % FloodManager.water_level)
	FloodManager.stop_rising()
	var held := FloodManager.water_level
	await _frames(30)
	_check(is_equal_approx(FloodManager.water_level, held), 'stop_rising: nước đứng yên')
	_check(is_equal_approx(FloodManager.get_water_level(), FloodManager.water_level), 'get_water_level trả mực biển')


func _test_sea() -> void:
	print('\n== Ô biển')
	_fresh()
	var sea := _all_cells().filter(func(c: Vector2i) -> bool: return FloodManager.is_sea(c)).size()
	_check(sea > 50, 'bản đồ có vùng biển (%d ô)' % sea)
	_check(_wet_land().is_empty(), 'đầu ván chưa ô đất nào ngập')


func _test_spread_gradually() -> void:
	print('\n== Nước lan dần từ biển')
	_fresh()
	FloodManager.water_level = 30.0
	var counts: Array[int] = []
	for i in 12:
		FloodManager.step(TICK)
		counts.append(_wet_land().size())
	_check(counts[0] > 0, 'sau một bước đã có ô sát biển bị ngập (%d)' % counts[0])
	_check(counts[11] > counts[0], 'số ô ngập tăng dần qua các bước (%d → %d)' % [counts[0], counts[11]])
	var steps := _settle()
	_check(steps < 400, 'mô phỏng tới trạng thái ổn định (%d bước)' % steps)
	var orphan := _wet_land().filter(func(c: Vector2i) -> bool:
		for d in FloodManager.NEIGHBORS:
			var n: Vector2i = c + d
			if FloodManager.is_sea(n) or FloodManager.depth_at(n) >= Config.FLOOD_SPILL_DEPTH:
				return false
		return true)
	_check(orphan.is_empty(), 'ô ngập nào cũng nối với biển qua ô ngập (%d ô lạc)' % orphan.size())
	var over := _wet_land().filter(func(c: Vector2i) -> bool:
		return GraphManager.cell_elevation(c) + FloodManager.depth_at(c) > 30.0 + 0.001)
	_check(over.is_empty(), 'mặt nước không cao hơn mực biển')


func _test_blocked_basin() -> void:
	print('\n== Vùng trũng có đồi chắn')
	_fresh()
	var pocket := Vector2i(-1, -1)
	for c in _all_cells():
		if c.x == 0 or c.y == 0 or c.x == Config.GRID_COLS - 1 or c.y == Config.GRID_ROWS - 1:
			continue
		var ring := FloodManager.NEIGHBORS.all(func(d: Vector2i) -> bool: return GraphManager.cell_elevation(c + d) > 60.0)
		if ring and GraphManager.cell_elevation(c) > 60.0:
			pocket = c
			break
	_check(pocket.x >= 0, 'tìm được ô giữa vùng đồi cao để thử')
	var i := pocket.y * Config.GRID_COLS + pocket.x
	FloodManager._ground[i] = 5.0  # biến ô đó thành hố trũng giữa đồi
	FloodManager._level[i] = 5.0
	FloodManager.water_level = 40.0
	_settle()
	_check(FloodManager.depth_at(pocket) < FloodManager.DRY_EPSILON, 'hố trũng (độ cao 5) giữa đồi không ngập dù mực biển 40')


func _test_no_recede() -> void:
	print('\n== Nước không rút')
	_fresh()
	FloodManager.water_level = 20.0
	_settle()
	var before := FloodManager._level.duplicate()
	FloodManager.water_level = 5.0  # giả sử biển hạ
	for i in 20:
		FloodManager.step(TICK)
	var lower := 0
	for k in before.size():
		if FloodManager._sea[k] == 0 and FloodManager._level[k] < before[k] - 0.001:
			lower += 1
	_check(lower == 0, 'mặt nước ô đất không giảm (%d ô giảm)' % lower)


func _test_edges_follow_deepest() -> void:
	print('\n== Cạnh ngập theo độ sâu trung bình hai ô')
	_fresh()
	var eid := GraphManager.add_edge(2, 4)  # Bến Cảng – Trường Học
	var c2 := GraphManager.cell_of(GraphManager.get_map_node(2).pos)
	var c4 := GraphManager.cell_of(GraphManager.get_map_node(4).pos)
	var low := c2 if GraphManager.cell_elevation(c2) < GraphManager.cell_elevation(c4) else c4
	var high := c4 if low == c2 else c2
	FloodManager.set_cell_level(low, GraphManager.cell_elevation(low) + 20.0)
	FloodManager._update_edges()
	_check(GraphManager.get_edge(eid).state == Types.EdgeState.SHALLOW, 'một đầu sâu 20, đầu kia khô: trung bình 10, SHALLOW')
	FloodManager.set_cell_level(low, GraphManager.cell_elevation(low) + 30.0)
	FloodManager._update_edges()
	_check(GraphManager.get_edge(eid).state == Types.EdgeState.DEEP, 'một đầu sâu 30, đầu kia khô: trung bình 15, DEEP')
	_check(FloodManager.depth_at(high) < FloodManager.DRY_EPSILON, 'đầu kia vẫn khô')
	_fresh()
	eid = GraphManager.add_edge(2, 4)
	FloodManager.fill_all(GraphManager.cell_elevation(low) + 3.0)
	var eid2 := GraphManager.add_edge(4, 5)
	_check(GraphManager.get_edge(eid2).state == FloodManager.state_for_depth((
			FloodManager.depth_at(c4) + FloodManager.depth_at(GraphManager.cell_of(GraphManager.get_map_node(5).pos))) / 2.0),
			'cạnh mới vẽ lúc nước đứng yên nhận trạng thái ngay')


func _test_warning_once() -> void:
	print('\n== Cảnh báo trước 5 giây, một lần')
	_fresh()
	var eid := GraphManager.add_edge(2, 4)
	var c2 := GraphManager.cell_of(GraphManager.get_map_node(2).pos)
	var g := GraphManager.cell_elevation(c2)
	FloodManager.set_cell_level(c2, g + Config.SHALLOW_MAX - 1.0)  # sâu 14, trung bình 7: SHALLOW
	FloodManager._update_edges()
	_warnings.clear()
	for k in 3:  # ô c2 dâng 4 mỗi 0,25 giây: trung bình dâng 8 mỗi giây, còn chưa tới 5 giây là tới 15
		FloodManager._prev = FloodManager._level.duplicate()
		FloodManager.set_cell_level(c2, g + Config.SHALLOW_MAX - 1.0 + 1.0 * (k + 1))
		FloodManager._last_dt = TICK
		FloodManager._update_edges()
	var mine := _warnings.filter(func(w) -> bool: return GraphManager.get_segment_edges(eid).has(w[0]) or w[0] == eid)
	_check(mine.size() == 1, 'phát flood_warning đúng một lần (%d)' % mine.size())
	_check(mine.size() > 0 and mine[0][1] <= Config.WARNING_SECONDS, 'thời gian còn lại không quá WARNING_SECONDS')


# Ô còn khô chưa có mặt nước: cảnh báo dựa vào ô kề đang dâng tới nền ô này.
func _test_warning_dry() -> void:
	print('
== Cảnh báo sắp ngập nhẹ cho đoạn còn khô')
	_fresh()
	var eid := GraphManager.add_edge(2, 4)
	var c2 := GraphManager.cell_of(GraphManager.get_map_node(2).pos)
	var g := GraphManager.cell_elevation(c2)
	var n: Vector2i = c2 + Vector2i(0, 1)
	var j := n.y * Config.GRID_COLS + n.x
	FloodManager._ground[j] = g - 5.0  # ô kề thấp hơn và đang ngập
	FloodManager._prev = FloodManager._level.duplicate()
	FloodManager._prev[j] = g - 1.0
	FloodManager._level[j] = g - 0.5  # dâng 2 mỗi giây, còn 0,25 giây nữa ngang nền ô c2
	FloodManager._last_dt = TICK
	_warnings.clear()
	FloodManager._update_edges()
	_check(GraphManager.get_edge(eid).state == Types.EdgeState.DRY, 'đoạn vẫn khô')
	_check(_warnings.size() == 1 and _warnings[0][1] <= 1.0, 'đã phát cảnh báo sắp ngập (%d)' % _warnings.size())


func _test_overlay() -> void:
	print('\n== Lớp nước')
	_fresh()
	var ov := FloodOverlay.new()
	add_child(ov)
	EventBus.water_level_changed.emit(0.0)
	_check(ov.wet_cell_count() == 0, 'chưa ngập thì không vẽ ô nào')
	FloodManager.water_level = 12.0
	_settle()
	EventBus.water_level_changed.emit(12.0)
	_check(ov.wet_cell_count() == _wet_land().size() and ov.wet_cell_count() > 0, 'vẽ đúng số ô đất đang ngập (%d)' % ov.wet_cell_count())
	var ids := ov.flooded_node_ids()
	_check(not ids.has(0) and not ids.has(1), 'hai kho trên cao không ngập ở mực 12')
	remove_child(ov)
	ov.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT] ' + label)
	else:
		_failed += 1
		printerr('  [TRƯỢT] ' + label)
