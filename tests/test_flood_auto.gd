extends Node
# Test tự động cho module Flood (B), theo các ca TC-B01 đến TC-B07 trong báo cáo.
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_flood_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

var _passed := 0
var _failed := 0
var _warnings: Array = []
var _state_changes: Array = []


func _ready() -> void:
	EventBus.flood_warning.connect(func(e: int, s: float) -> void: _warnings.append([e, s]))
	EventBus.edge_state_changed.connect(func(e: int, s: int) -> void: _state_changes.append([e, s]))
	_run.call_deferred()


func _run() -> void:
	_test_compute_state()
	await _test_rise_and_stop()
	_test_get_level()
	await _test_tick_update()
	_test_edge_added_still()
	await _test_warning_once()
	_test_overlay()
	FloodManager.reset()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fresh() -> void:
	GraphManager.load_map(Config.MAP_PATH)
	FloodManager.reset()
	_warnings.clear()
	_state_changes.clear()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _test_compute_state() -> void:
	print('\n== TC-B01 compute_state ở các mốc biên')
	_fresh()
	var cases := [[0.0, 10.0, Types.EdgeState.DRY], [10.0, 10.0, Types.EdgeState.SHALLOW],
		[24.9, 10.0, Types.EdgeState.SHALLOW], [25.0, 10.0, Types.EdgeState.DEEP], [90.0, 87.5, Types.EdgeState.SHALLOW]]
	for c in cases:
		FloodManager.water_level = c[0]
		_check(FloodManager.compute_state(c[1]) == c[2], 'nước %s, độ cao %s' % [c[0], c[1]])


func _test_rise_and_stop() -> void:
	print('\n== TC-B02 start_wave và stop_rising')
	_fresh()
	FloodManager.start_wave(0)
	var rate: float = Config.WAVES[0].water_delta / Config.WAVE_DURATION
	await _frames(60)
	_check(absf(FloodManager.water_level - rate) < 0.02, 'sau 1 giây nước dâng đúng water_delta / WAVE_DURATION (%.3f)' % FloodManager.water_level)
	FloodManager.stop_rising()
	var held := FloodManager.water_level
	await _frames(30)
	_check(is_equal_approx(FloodManager.water_level, held), 'stop_rising: nước đứng yên')


func _test_get_level() -> void:
	print('\n== TC-B03 get_water_level')
	_check(is_equal_approx(FloodManager.get_water_level(), FloodManager.water_level), 'trả đúng mực nước hiện tại')
	FloodManager.water_level = 99.99
	FloodManager.start_wave(2)
	FloodManager._process(10.0)
	_check(FloodManager.get_water_level() <= 100.0, 'không vượt 100')
	FloodManager.stop_rising()


func _test_tick_update() -> void:
	print('\n== TC-B04 cập nhật trạng thái cạnh theo chu kỳ')
	_fresh()
	var eid := GraphManager.add_edge(2, 4)  # độ cao (10 + 20) / 2 = 15
	var e = GraphManager.get_edge(eid)
	_check(eid >= 0 and is_equal_approx(e.elevation, 15.0), 'cạnh thử có độ cao 15')
	FloodManager.water_level = 14.95
	FloodManager.start_wave(0)
	await _frames(40)  # 0,66 giây > một chu kỳ FLOOD_TICK sau khi qua mốc 15
	_check(GraphManager.get_edge(eid).state == Types.EdgeState.SHALLOW, 'qua mốc độ cao thì cạnh sang SHALLOW qua set_edge_state')
	_check(_state_changes.has([eid, Types.EdgeState.SHALLOW]), 'phát edge_state_changed')
	FloodManager.stop_rising()


func _test_edge_added_still() -> void:
	print('\n== TC-B05 cạnh vẽ lúc nước đứng yên')
	_fresh()
	FloodManager.water_level = 30.0
	var eid := GraphManager.add_edge(2, 4)  # độ cao 15, sâu 15
	_check(GraphManager.get_edge(eid).state == Types.EdgeState.DEEP, 'cạnh mới là DEEP ngay khi vẽ')


func _test_warning_once() -> void:
	print('\n== TC-B06 cảnh báo trước 5 giây, một lần')
	_fresh()
	var eid := GraphManager.add_edge(2, 4)  # SHALLOW từ 15, DEEP từ 30
	FloodManager.water_level = 29.0
	GraphManager.set_edge_state(eid, Types.EdgeState.SHALLOW)
	_warnings.clear()
	FloodManager.start_wave(0)  # còn khoảng 4,8 giây là sang DEEP
	await _frames(90)
	var mine := _warnings.filter(func(w) -> bool: return w[0] == eid)
	_check(mine.size() == 1, 'phát flood_warning đúng một lần (%d)' % mine.size())
	_check(mine.size() > 0 and mine[0][1] <= Config.WARNING_SECONDS, 'thời gian còn lại không quá WARNING_SECONDS')
	FloodManager.stop_rising()


func _test_overlay() -> void:
	print('\n== TC-B07 lớp phủ nước')
	_check(FloodOverlay.water_alpha(0.0) == 0.0, 'nước bằng 0 thì không phủ')
	_check(is_equal_approx(FloodOverlay.water_alpha(100.0), 0.35), 'nước 100 phủ độ mờ 0,35')
	_check(FloodOverlay.water_alpha(55.0) > FloodOverlay.water_alpha(25.0), 'nước càng cao càng đậm')
	_fresh()
	var ov := FloodOverlay.new()
	add_child(ov)
	EventBus.water_level_changed.emit(12.0)
	var ids := ov.flooded_node_ids()
	_check(ids.has(2) and ids.has(9) and not ids.has(4) and not ids.has(0), 'quầng nước ở Bến Cảng (10) và Làng Nổi (5), không ở Trường Học (20) hay Kho Bắc (70)')
	remove_child(ov)
	ov.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT] ' + label)
	else:
		_failed += 1
		printerr('  [TRƯỢT] ' + label)
