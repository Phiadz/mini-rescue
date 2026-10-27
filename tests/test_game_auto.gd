extends Node
# Test tự động cho GameManager và ScoreSystem. Chủ sở hữu: E.
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_game_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const SPEED := 10.0  # Engine.time_scale: một ván 390 giây chạy hết trong vài giây
const MAX_FRAMES := 20000
const STATS_KEYS := ['score', 'saved', 'failed', 'time_survived', 'wave_reached', 'stars']

var _events: Array = []  # [tên tín hiệu, tham số...] theo thứ tự phát
var _passed := 0
var _failed := 0
var _next_req := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	reparent(get_tree().root)  # start_game() đổi sang main.tscn, node này phải sống sót
	_listen()
	Engine.time_scale = SPEED
	_test_menu()
	await _test_full_game_win()
	await _test_lose()
	await _test_lose_in_break()
	await _test_pause()
	await _test_exit_to_menu()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_menu() -> void:
	print('\n== MENU: chưa bắt đầu ván')
	_check(GameManager.state == Types.GameState.MENU, 'trạng thái đầu là MENU')
	GameManager.pause_game()
	_check(GameManager.state == Types.GameState.MENU and not get_tree().paused,
			'pause_game ở MENU không có tác dụng')
	GameManager.choose_reward(Types.Reward.MORE_EDGES)
	_check(_count('reward_chosen') == 0, 'choose_reward ở MENU bị bỏ qua')
	_fake_fail()
	_check(GameManager.get_failed_count() == 0, 'SOS thất bại ở MENU không được tính')


func _test_full_game_win() -> void:
	print('\n== Thắng sau 3 đợt, tự chọn thưởng khi hết giờ nghỉ')
	_events.clear()
	await GameManager.start_game()
	_check(GameManager.state == Types.GameState.PLAYING, 'start_game chuyển sang PLAYING')
	_check(_count('game_started') == 1, 'phát game_started đúng 1 lần')
	_check(_last('wave_started') == ['wave_started', 0], 'đợt đầu có chỉ số 0')
	_check(_events.find(['game_started']) < _events.find(['wave_started', 0]),
			'game_started phát trước wave_started(0)')

	_fake_rescue(10)
	_fake_rescue(20)
	_check(GameManager.get_score() == 30, 'cứu 2 SOS (10 + 20 điểm) thì điểm là 30')
	_check(_last('score_changed') == ['score_changed', 30], 'phát score_changed(30)')
	_fake_fail()
	_check(_last('failed_changed') == ['failed_changed', 1, Config.MAX_FAILED],
			'phát failed_changed(1, MAX_FAILED)')

	await _wait_state(Types.GameState.WAVE_BREAK)
	_check(absf(GameManager.get_time_survived() - Config.WAVE_DURATION) < 0.5,
			'đợt 0 kéo dài WAVE_DURATION giây (%.2f)' % GameManager.get_time_survived())
	_check(_last('wave_ended') == ['wave_ended', 0], 'hết đợt thì phát wave_ended(0)')
	_check(_last('break_started') == ['break_started', Config.BREAK_DURATION],
			'phát break_started(BREAK_DURATION)')
	_check(_last('reward_offered') == ['reward_offered', [0, 1, 2]], 'phát reward_offered([0, 1, 2])')

	await _wait_state(Types.GameState.PLAYING)
	_check(_last('reward_chosen') == ['reward_chosen', Types.Reward.MORE_EDGES],
			'hết giờ nghỉ mà chưa chọn thì tự nhận MORE_EDGES')
	_check(_last('wave_started') == ['wave_started', 1], 'sau giờ nghỉ bắt đầu đợt 1')

	await _wait_state(Types.GameState.WAVE_BREAK)
	GameManager.choose_reward(Types.Reward.EXTRA_TRUCK)
	GameManager.choose_reward(Types.Reward.EXTRA_BOAT)
	_check(_count('reward_chosen') == 2
			and _last('reward_chosen') == ['reward_chosen', Types.Reward.EXTRA_TRUCK],
			'mỗi lượt nghỉ chỉ chọn được 1 phần thưởng')

	await _wait_state(Types.GameState.WON)
	_check(_count('game_won') == 1 and _count('game_lost') == 0, 'hết đợt 2 thì game_won đúng 1 lần')
	var stats: Dictionary = _last('game_won')[1]
	_check(stats.size() == STATS_KEYS.size() and STATS_KEYS.all(func(k): return stats.has(k)),
			'stats có đúng 6 khóa %s' % str(STATS_KEYS))
	_check(stats['score'] == 30 and stats['saved'] == 2 and stats['failed'] == 1,
			'stats: score 30, saved 2, failed 1')
	_check(stats['stars'] == 2, '1 thất bại thì 2 sao')
	_check(stats['wave_reached'] == Config.WAVE_COUNT - 1, 'wave_reached là chỉ số đợt cuối')
	var expected_time := Config.WAVE_COUNT * Config.WAVE_DURATION \
			+ (Config.WAVE_COUNT - 1) * Config.BREAK_DURATION
	_check(absf(stats['time_survived'] - expected_time) < 1.0,
			'time_survived khoảng %.0f giây (%.2f)' % [expected_time, stats['time_survived']])

	_fake_fail()
	_fake_rescue(10)
	_check(GameManager.get_failed_count() == 1 and GameManager.get_score() == 30
			and _count('game_lost') == 0, 'sau khi thắng, tín hiệu SOS bị bỏ qua')
	GameManager.pause_game()
	_check(GameManager.state == Types.GameState.WON, 'pause_game sau khi thắng không có tác dụng')


func _test_lose() -> void:
	print('\n== Thua khi đủ MAX_FAILED lần thất bại')
	_events.clear()
	GameManager.restart()
	await _wait_until(func(): return _count('wave_started') > 0)
	_check(GameManager.get_score() == 0 and GameManager.get_failed_count() == 0
			and GameManager.get_current_wave() == 0 and GameManager.get_time_survived() < 0.5,
			'restart đặt lại mọi bộ đếm')
	for i in Config.MAX_FAILED:
		_fake_fail()
	_check(GameManager.state == Types.GameState.LOST, 'đủ %d thất bại thì LOST' % Config.MAX_FAILED)
	_check(_count('game_lost') == 1 and _count('game_won') == 0, 'phát game_lost đúng 1 lần')
	var stats: Dictionary = _last('game_lost')[1]
	_check(stats['stars'] == 0 and stats['failed'] == Config.MAX_FAILED, 'thua thì 0 sao')
	_fake_fail()
	_check(_count('game_lost') == 1 and GameManager.get_failed_count() == Config.MAX_FAILED,
			'thất bại thêm sau khi thua không phát game_lost lần nữa')


func _test_lose_in_break() -> void:
	print('\n== Thua trong lúc nghỉ giữa đợt')
	_events.clear()
	GameManager.restart()
	await _wait_until(func(): return _count('wave_started') > 0)
	await _wait_state(Types.GameState.WAVE_BREAK)
	for i in Config.MAX_FAILED:
		_fake_fail()
	_check(GameManager.state == Types.GameState.LOST, 'SOS vẫn đếm ngược lúc nghỉ, đủ thất bại thì thua')
	_check(_last('game_lost')[1]['wave_reached'] == 0, 'wave_reached là 0')
	await _wait_frames(roundi(Config.BREAK_DURATION / SPEED * 60.0) + 30)
	_check(_count('wave_started') == 1, 'sau khi thua không sang đợt mới')


func _test_pause() -> void:
	print('\n== Tạm dừng và tiếp tục')
	_events.clear()
	GameManager.restart()
	await _wait_until(func(): return _count('wave_started') > 0)
	await _wait_frames(30)
	GameManager.pause_game()
	_check(GameManager.state == Types.GameState.PAUSED and get_tree().paused,
			'pause_game: PAUSED và cây scene dừng')
	var t := GameManager.get_time_survived()
	await _wait_frames(120)
	_check(is_equal_approx(GameManager.get_time_survived(), t), 'đồng hồ đứng yên khi tạm dừng')
	GameManager.resume_game()
	_check(GameManager.state == Types.GameState.PLAYING and not get_tree().paused,
			'resume_game quay lại PLAYING')
	await _wait_frames(10)
	_check(GameManager.get_time_survived() > t, 'đồng hồ chạy lại sau khi tiếp tục')

	_press(KEY_ESCAPE)
	await _wait_frames(2)
	_check(GameManager.state == Types.GameState.PAUSED, 'phím Esc tạm dừng')
	_press(KEY_SPACE)
	await _wait_frames(2)
	_check(GameManager.state == Types.GameState.PLAYING, 'phím Space tiếp tục')

	await _wait_state(Types.GameState.WAVE_BREAK)
	GameManager.pause_game()
	GameManager.choose_reward(Types.Reward.EXTRA_BOAT)
	_check(_count('reward_chosen') == 0, 'không chọn được thưởng khi đang tạm dừng')
	GameManager.resume_game()
	_check(GameManager.state == Types.GameState.WAVE_BREAK, 'tạm dừng lúc nghỉ, tiếp tục thì về WAVE_BREAK')


func _test_exit_to_menu() -> void:
	print('\n== Về menu giữa ván')
	_events.clear()
	GameManager.restart()
	await _wait_until(func(): return _count('wave_started') > 0)
	await _wait_frames(30)
	GameManager.pause_game()
	GameManager.exit_to_menu()
	_check(GameManager.state == Types.GameState.MENU
			and _last('game_state_changed') == ['game_state_changed', Types.GameState.MENU],
			'exit_to_menu: về MENU và phát game_state_changed(MENU)')
	var t := GameManager.get_time_survived()
	var failed := GameManager.get_failed_count()
	await _wait_frames(120)
	_check(get_tree().paused and is_equal_approx(GameManager.get_time_survived(), t),
			'ở menu, ván dở đứng yên (cây scene dừng, đồng hồ không chạy)')
	_fake_fail()
	_check(GameManager.get_failed_count() == failed and _count('game_lost') == 0,
			'ở menu, SOS thất bại không được tính')
	_press(KEY_ESCAPE)
	await _wait_frames(2)
	_check(GameManager.state == Types.GameState.MENU, 'ở menu, phím Esc không có tác dụng')
	_events.clear()
	await GameManager.start_game()
	_check(GameManager.state == Types.GameState.PLAYING and not get_tree().paused
			and _count('game_started') == 1, 'từ menu bấm Chơi thì bắt đầu ván mới')


func _listen() -> void:
	EventBus.game_started.connect(func(): _events.append(['game_started']))
	EventBus.game_state_changed.connect(func(s): _events.append(['game_state_changed', s]))
	EventBus.wave_started.connect(func(i): _events.append(['wave_started', i]))
	EventBus.wave_ended.connect(func(i): _events.append(['wave_ended', i]))
	EventBus.break_started.connect(func(t): _events.append(['break_started', t]))
	EventBus.reward_offered.connect(func(o): _events.append(['reward_offered', o]))
	EventBus.reward_chosen.connect(func(r): _events.append(['reward_chosen', r]))
	EventBus.score_changed.connect(func(s): _events.append(['score_changed', s]))
	EventBus.failed_changed.connect(func(c, m): _events.append(['failed_changed', c, m]))
	EventBus.game_won.connect(func(st): _events.append(['game_won', st]))
	EventBus.game_lost.connect(func(st): _events.append(['game_lost', st]))
	# C bật sinh SOS khi nghe wave_started; tắt lại để chỉ còn SOS giả của test.
	# RescueManager là autoload nên đã connect trước, hàm này chạy sau nó.
	EventBus.wave_started.connect(func(_i): RescueManager.set_spawning(false))


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print('  [ĐẠT]   ', label)
	else:
		_failed += 1
		print('  [TRƯỢT] ', label)


func _count(signal_name: String) -> int:
	return _events.filter(func(e): return e[0] == signal_name).size()


func _last(signal_name: String) -> Array:
	for i in range(_events.size() - 1, -1, -1):
		if _events[i][0] == signal_name:
			return _events[i]
	return []


func _wait_until(cond: Callable) -> bool:
	for i in MAX_FRAMES:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _wait_state(s: int) -> bool:
	return await _wait_until(func(): return GameManager.state == s)


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _press(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _fake_rescue(points: int) -> void:
	_next_req += 1
	EventBus.sos_rescued.emit(_next_req, points)


func _fake_fail() -> void:
	_next_req += 1
	EventBus.sos_failed.emit(_next_req)
