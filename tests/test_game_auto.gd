extends Node
# Test tự động cho GameManager, ScoreSystem, Endless và Card Draft. Chủ sở hữu: C/E.
# Chạy headless (từ thư mục project):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/test_game_auto.tscn
# Thoát với mã 0 nếu mọi kiểm tra đạt, 1 nếu có kiểm tra trượt.

const SPEED := 10.0  # Engine.time_scale
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
	_test_endless_profiles_and_card_scaling()
	await _test_card_draft_and_inventory()
	await _test_endless_milestone_win()
	await _test_lose_before_milestone()
	await _test_pause()
	await _test_exit_to_menu()
	await _test_speed()
	await _test_stages()
	print('\nKết quả: %d đạt, %d trượt' % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_menu() -> void:
	print('\n== MENU: chưa bắt đầu ván')
	_check(GameManager.state == Types.GameState.MENU, 'trạng thái đầu là MENU')
	GameManager.pause_game()
	_check(GameManager.state == Types.GameState.MENU and not get_tree().paused,
			'pause_game ở MENU không có tác dụng')
	_check(not GameManager.choose_card(&'road_supply'), 'choose_card ở MENU bị bỏ qua')
	_fake_fail()
	_check(GameManager.get_failed_count() == 0, 'SOS thất bại ở MENU không được tính')


func _test_endless_profiles_and_card_scaling() -> void:
	print('\n== Endless profile & Card scaling (deterministic seed)')
	for i in 3:
		var p: Dictionary = Config.get_wave_profile(i + 1)
		_check(is_equal_approx(float(p.water_peak), float(Config.WAVES[i].water_peak))
				and is_equal_approx(float(p.sos_interval), float(Config.WAVES[i].sos_interval)),
				'wave %d giữ nguyên Config.WAVES[%d]' % [i + 1, i])

	var p4: Dictionary = Config.get_wave_profile(4)
	_check(is_equal_approx(float(p4.water_peak), 90.0) and is_equal_approx(float(p4.sos_interval), 3.5)
			and int(p4.sos_max) == 11 and is_equal_approx(float(p4.house_interval), 4.75)
			and is_equal_approx(float(p4.deadline_food), 26.0) and is_equal_approx(float(p4.deadline_medical), 20.0),
			'wave 4 (tier 1): đúng công thức endless')
	var p6: Dictionary = Config.get_wave_profile(6)
	_check(is_equal_approx(float(p6.sos_interval), 3.2) and int(p6.sos_max) == 12
			and is_equal_approx(float(p6.house_interval), 4.5)
			and is_equal_approx(float(p6.deadline_food), 25.0) and is_equal_approx(float(p6.deadline_medical), 19.0),
			'wave 6 (tier 2): đúng công thức endless')
	var p8: Dictionary = Config.get_wave_profile(8)
	_check(is_equal_approx(float(p8.sos_interval), 2.9) and int(p8.sos_max) == 13
			and is_equal_approx(float(p8.house_interval), 4.25)
			and is_equal_approx(float(p8.deadline_food), 24.0) and is_equal_approx(float(p8.deadline_medical), 18.0),
			'wave 8 (tier 3): đúng công thức endless')
	var p18: Dictionary = Config.get_wave_profile(18)
	_check(is_equal_approx(float(p18.sos_interval), 2.0) and int(p18.sos_max) == 16
			and is_equal_approx(float(p18.house_interval), 3.0)
			and is_equal_approx(float(p18.deadline_food), 19.0) and is_equal_approx(float(p18.deadline_medical), 14.0),
			'wave 18 (tier 8): đạt giới hạn min/max')

	GameManager.set_card_seed(424242)
	GameManager.truck_capacity = 1
	GameManager.boat_capacity = 1
	var o1: Array = GameManager._generate_card_offers(1)
	var o4: Array = GameManager._generate_card_offers(4)
	var o8: Array = GameManager._generate_card_offers(8)
	var o12: Array = GameManager._generate_card_offers(12)
	_check(_offers_distinct(o1) and o1.size() == 4, 'draft 1 có đúng 4 template khác nhau')
	_check(_offers_match_scale(o1, 1) and _offers_match_scale(o4, 1),
			'amount scale = 1 ở draft đầu và wave 4')
	_check(_offers_match_scale(o8, 2), 'amount scale = 2 ở draft wave 8')
	_check(_offers_match_scale(o12, 3), 'amount scale = 3 ở draft wave 12')
	_check(_upgrade_amount_is_one(o12), 'capacity upgrade luôn có amount = 1')

	GameManager.truck_capacity = 2
	GameManager.boat_capacity = 2
	var maxed_has_upgrade := false
	for k in 10:
		for o in GameManager._generate_card_offers(8):
			for r in o.rewards:
				if r.reward_id == Types.Reward.UPGRADE_TRUCK_CAP or r.reward_id == Types.Reward.UPGRADE_BOAT_CAP:
					maxed_has_upgrade = true
	_check(not maxed_has_upgrade, 'đã nâng max capacity thì không còn xuất hiện trong pool')


func _test_card_draft_and_inventory() -> void:
	print('\n== Card Draft đầu ván & Inventory API')
	_events.clear()
	GameManager.set_card_seed(10101)
	await GameManager.start_game()
	_check(GameManager.state == Types.GameState.CARD_DRAFT and get_tree().paused,
			'start_game mở CARD_DRAFT trước wave 1 và đóng băng mô phỏng')
	_check(_count('card_offers_ready') == 1, 'phát card_offers_ready đúng 1 lần')
	var offers: Array = GameManager.get_card_offers()
	_check(offers.size() == 4 and _offers_distinct(offers), 'get_card_offers trả về 4 card khác nhau')
	_check(GameManager.get_inventory(Types.Reward.FERRY) == Config.START_FERRIES,
			'khởi đầu có %d token Ferry' % Config.START_FERRIES)

	_check(not GameManager.choose_card(&'invalid_card_id'), 'choose_card với ID không tồn tại trả false')
	_check(GameManager.state == Types.GameState.CARD_DRAFT and get_tree().paused,
			'sau chọn sai, game vẫn ở CARD_DRAFT và đóng băng')

	var picked: Dictionary = offers[0]
	var limit_before: int = GraphManager.get_edge_budget().limit
	var trucks_before: int = RescueManager.get_vehicle_ids().size()
	_check(GameManager.choose_card(picked.id), 'choose_card hợp lệ trả true')
	_check(not GameManager.choose_card(picked.id), 'chọn trùng lần 2 bị chặn')
	_check(GameManager.state == Types.GameState.PLAYING and not get_tree().paused,
			'sau khi chọn card, game sang PLAYING và chạy lại')
	_check(_last('wave_started') == ['wave_started', 0], 'bắt đầu wave 0 sau draft đầu')
	_check(_verify_rewards_applied(picked.rewards, limit_before, trucks_before),
			'bundle reward của card được cấp đầy đủ đúng 1 lần')

	_check(GameManager.grant_reward(Types.Reward.TRAFFIC_LIGHT, 2), 'grant_reward TRAFFIC_LIGHT +2')
	_check(GameManager.get_inventory(Types.Reward.TRAFFIC_LIGHT) == 2, 'inventory TRAFFIC_LIGHT = 2')
	_check(GameManager.try_consume_item(Types.Reward.TRAFFIC_LIGHT, 1)
			and GameManager.get_inventory(Types.Reward.TRAFFIC_LIGHT) == 1, 'try_consume_item trừ đúng 1')
	GameManager.refund_item(Types.Reward.TRAFFIC_LIGHT, 1)
	_check(GameManager.get_inventory(Types.Reward.TRAFFIC_LIGHT) == 2, 'refund_item hoàn đúng 1')
	_check(not GameManager.try_consume_item(Types.Reward.ROUNDABOUT, 1), 'consume khi hết hàng trả false')


func _test_endless_milestone_win() -> void:
	print('\n== Vượt mốc 3 wave -> Endless -> Thua tính WON')
	_events.clear()
	await _start_and_pick_first()

	_fake_rescue(10)
	_fake_rescue(20)
	_check(GameManager.get_score() == 2, 'cứu 2 SOS thì điểm là 2 (+1 mỗi SOS)')
	_check(_last('score_changed') == ['score_changed', 2], 'phát score_changed(2)')
	_fake_fail()
	_check(_last('failed_changed') == ['failed_changed', 1, Config.MAX_FAILED],
			'phát failed_changed(1, MAX_FAILED)')

	for w in Config.WAVE_COUNT:
		GameManager._phase_left = 0.01
		await _wait_state(Types.GameState.CARD_DRAFT)
		_check(_last('wave_ended') == ['wave_ended', w], 'kết thúc wave %d mở draft' % w)
		_check(_count('game_won') == 0, 'qua wave %d chưa kết thúc ván' % w)
		var next_offers: Array = GameManager.get_card_offers()
		_check(next_offers.size() == 4 and GameManager.choose_card(next_offers[0].id),
				'chọn card sau wave %d để tiếp tục' % w)

	_check(GameManager.get_current_wave() == 3 and GameManager.is_milestone_cleared(),
			'đã vào wave 3 (endless) và đánh dấu qua mốc 3 wave')
	for i in Config.MAX_FAILED - 1:
		_fake_fail()
	_check(GameManager.state == Types.GameState.WON and get_tree().paused,
			'thua sau mốc 3 wave thì kết thúc ở trạng thái WON')
	_check(_count('game_won') == 1 and _count('game_lost') == 0, 'phát game_won đúng 1 lần')
	var stats: Dictionary = _last('game_won')[1]
	_check(stats.size() == STATS_KEYS.size() and STATS_KEYS.all(func(k): return stats.has(k)),
			'stats có đúng 6 khóa %s' % str(STATS_KEYS))
	_check(stats['score'] == 2 and stats['saved'] == 2 and stats['failed'] == Config.MAX_FAILED
			and stats['wave_reached'] == 3 and stats['stars'] >= 1,
			'stats endless hợp lệ (score 2, wave 3, stars >= 1)')


func _test_lose_before_milestone() -> void:
	print('\n== Thua trước mốc 3 wave -> LOST, Restart reset đầy đủ')
	_events.clear()
	GameManager.grant_reward(Types.Reward.UPGRADE_TRUCK_CAP, 1)
	GameManager.grant_reward(Types.Reward.HIGHWAY, 3)
	GameManager.restart()
	await _wait_state(Types.GameState.CARD_DRAFT)
	_check(GameManager.get_score() == 0 and GameManager.get_failed_count() == 0
			and GameManager.get_current_wave() == 0 and not GameManager.is_milestone_cleared()
			and GameManager.truck_capacity == 1 and GameManager.boat_capacity == 1
			and GameManager.get_inventory(Types.Reward.HIGHWAY) == 0
			and GameManager.get_inventory(Types.Reward.FERRY) == Config.START_FERRIES,
			'restart đặt lại toàn bộ điểm, mốc, capacity và inventory')
	GameManager.choose_card(GameManager.get_card_offers()[0].id)
	for i in Config.MAX_FAILED:
		_fake_fail()
	_check(GameManager.state == Types.GameState.LOST and get_tree().paused,
			'đủ %d thất bại trước mốc thì LOST' % Config.MAX_FAILED)
	_check(_count('game_lost') == 1 and _count('game_won') == 0, 'phát game_lost đúng 1 lần')
	var stats: Dictionary = _last('game_lost')[1]
	_check(stats['stars'] == 0 and stats['failed'] == Config.MAX_FAILED, 'thua trước mốc thì 0 sao')
	_fake_fail()
	_check(_count('game_lost') == 1, 'thất bại thêm sau khi thua không phát game_lost lần nữa')


func _test_pause() -> void:
	print('\n== Tạm dừng và tiếp tục')
	_events.clear()
	await _start_and_pick_first(true)
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


func _test_exit_to_menu() -> void:
	print('\n== Về menu giữa ván')
	_events.clear()
	await _start_and_pick_first(true)
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
			'ở menu, ván dở đứng yên')
	_fake_fail()
	_check(GameManager.get_failed_count() == failed and _count('game_lost') == 0,
			'ở menu, SOS thất bại không được tính')
	_press(KEY_ESCAPE)
	await _wait_frames(2)
	_check(GameManager.state == Types.GameState.MENU, 'ở menu, phím Esc không có tác dụng')
	_events.clear()
	await _start_and_pick_first()
	_check(GameManager.state == Types.GameState.PLAYING and not get_tree().paused
			and _count('game_started') == 1, 'từ menu bấm Chơi và chọn card thì bắt đầu ván mới')


func _test_speed() -> void:
	print('\n== Tua nhanh')
	GameManager.exit_to_menu()
	Engine.time_scale = 1.0
	_check(GameManager.state == Types.GameState.MENU and GameManager.cycle_speed() == 1 and Engine.time_scale == 1.0,
			'ở MENU không tua được')
	await _start_and_pick_first()
	_check(GameManager.cycle_speed() == 2 and Engine.time_scale == 2.0, 'lần 1: x2')
	_check(GameManager.cycle_speed() == 3 and Engine.time_scale == 3.0, 'lần 2: x3')
	_check(GameManager.cycle_speed() == 1 and Engine.time_scale == 1.0, 'lần 3: quay về x1')
	GameManager.cycle_speed()
	_press(KEY_F)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(GameManager.game_speed == 3, 'phím F đổi tốc độ (%d)' % GameManager.game_speed)
	GameManager.pause_game()
	_check(GameManager.cycle_speed() == 3, 'đang tạm dừng thì không đổi tốc độ')
	GameManager.resume_game()
	GameManager._finish(false)
	_check(GameManager.game_speed == 1 and Engine.time_scale == 1.0, 'hết ván thì về x1')
	await _start_and_pick_first()
	GameManager.cycle_speed()
	GameManager.exit_to_menu()
	_check(GameManager.game_speed == 1 and Engine.time_scale == 1.0, 'về menu thì về x1')
	Engine.time_scale = SPEED


func _test_stages() -> void:
	print('\n== Vùng chơi theo đợt')
	await _start_and_pick_first()
	var stages: Array = GraphManager.get_stages()
	if stages.is_empty():
		_check(GameManager.get_play_rect().size == Vector2(1280, 720), 'bản đồ không có stages: chơi cả bản đồ')
		return
	var rect := GameManager.get_play_rect()
	_check(GameManager.get_stage() == 0 and rect.size.x < 1280.0, 'đầu ván ở vùng 0, nhỏ hơn cả bản đồ')
	var cam := get_viewport().get_camera_2d()
	var fit := float(GameManager._stage_view.get_fit_zoom()) if GameManager._stage_view != null and GameManager._stage_view.has_method('get_fit_zoom') else 1.0
	_check(cam != null and is_equal_approx(cam.zoom.x, float(stages[0].zoom) * fit), 'camera phóng to %.2f lần' % (float(stages[0].zoom) * fit))
	var districts := GraphManager.get_node_ids().filter(func(id: int) -> bool:
		return GraphManager.get_map_node(id).kind == Types.NodeKind.DISTRICT)
	var closed := districts.filter(func(id: int) -> bool: return not rect.has_point(GraphManager.get_map_node(id).pos))
	_check(closed.size() > 0, 'có khu chưa mở ở đợt 1 (%d khu)' % closed.size())
	var free: Array = RescueManager._free_nodes()
	_check(free.size() > 0 and free.all(func(id: int) -> bool: return rect.has_point(GraphManager.get_map_node(id).pos)),
			'SOS chỉ chọn khu đã mở (%d khu)' % free.size())
	_check(not GameManager.is_in_play(Vector2(5, 5)), 'góc bản đồ ngoài vùng chơi')
	GameManager._phase_left = 0.01
	await _wait_state(Types.GameState.CARD_DRAFT)
	var rect1 := GameManager.get_play_rect()
	_check(GameManager.get_stage() == 1 and rect1.encloses(rect), 'hết đợt 1 mở vùng 1, rộng hơn và chứa vùng 0')
	var hubs := GraphManager.get_node_ids().filter(func(id: int) -> bool: return GraphManager.get_map_node(id).kind == Types.NodeKind.HUB)
	_check(hubs.all(func(id: int) -> bool: return rect1.has_point(GraphManager.get_map_node(id).pos)), 'vùng 1 có đủ hai kho')
	GameManager.choose_card(GameManager.get_card_offers()[0].id)
	await _wait_frames(30)
	_check(is_equal_approx(cam.zoom.x, float(stages[1].zoom) * fit), 'camera thu ra %.2f lần sau khi chuyển vùng (%.2f)' % [float(stages[1].zoom) * fit, cam.zoom.x])
	GameManager._enter_stage(stages.size() - 1, false)
	_check(GameManager.get_play_rect() == Rect2(0, 0, 1280, 720), 'vùng cuối là cả bản đồ')
	GameManager.exit_to_menu()


func _start_and_pick_first(use_restart := false) -> void:
	if use_restart:
		GameManager.restart()
	else:
		await GameManager.start_game()
	await _wait_state(Types.GameState.CARD_DRAFT)
	var offers: Array = GameManager.get_card_offers()
	if not offers.is_empty():
		GameManager.choose_card(offers[0].id)


func _offers_distinct(offers: Array) -> bool:
	var seen := {}
	for o in offers:
		if seen.has(o.id):
			return false
		seen[o.id] = true
	return true


func _offers_match_scale(offers: Array, expected_scale: int) -> bool:
	var catalog_by_id := {}
	for tpl in Config.CARD_CATALOG:
		catalog_by_id[tpl.id] = tpl.rewards
	for o in offers:
		if not catalog_by_id.has(o.id):
			return false
		var base_rewards: Array = catalog_by_id[o.id]
		if o.rewards.size() != base_rewards.size():
			return false
		for i in base_rewards.size():
			var rid: int = int(base_rewards[i].reward_id)
			var base_amt: int = int(base_rewards[i].amount)
			var want := base_amt if (rid == Types.Reward.UPGRADE_TRUCK_CAP or rid == Types.Reward.UPGRADE_BOAT_CAP) else base_amt * expected_scale
			if int(o.rewards[i].amount) != want:
				return false
	return true


func _upgrade_amount_is_one(offers: Array) -> bool:
	for o in offers:
		for r in o.rewards:
			if (r.reward_id == Types.Reward.UPGRADE_TRUCK_CAP or r.reward_id == Types.Reward.UPGRADE_BOAT_CAP) and int(r.amount) != 1:
				return false
	return true


func _verify_rewards_applied(rewards: Array, limit_before: int, vehicles_before: int) -> bool:
	var expected_limit := limit_before
	var expected_vehicles := vehicles_before
	for r in rewards:
		var rid: int = int(r.reward_id)
		var amt: int = int(r.amount)
		match rid:
			Types.Reward.MORE_EDGES:
				expected_limit += amt
			Types.Reward.EXTRA_TRUCK, Types.Reward.EXTRA_BOAT:
				expected_vehicles += amt
			Types.Reward.UPGRADE_TRUCK_CAP:
				if GameManager.truck_capacity != 2:
					return false
			Types.Reward.UPGRADE_BOAT_CAP:
				if GameManager.boat_capacity != 2:
					return false
			_:
				if GameManager.get_inventory(rid) < amt:
					return false
	return GraphManager.get_edge_budget().limit == expected_limit and RescueManager.get_vehicle_ids().size() == expected_vehicles


func _listen() -> void:
	EventBus.game_started.connect(func(): _events.append(['game_started']))
	EventBus.game_state_changed.connect(func(s): _events.append(['game_state_changed', s]))
	EventBus.wave_started.connect(func(i): _events.append(['wave_started', i]))
	EventBus.wave_ended.connect(func(i): _events.append(['wave_ended', i]))
	EventBus.card_offers_ready.connect(func(o): _events.append(['card_offers_ready', o]))
	EventBus.inventory_changed.connect(func(rid, avail): _events.append(['inventory_changed', rid, avail]))
	EventBus.score_changed.connect(func(s): _events.append(['score_changed', s]))
	EventBus.failed_changed.connect(func(c, m): _events.append(['failed_changed', c, m]))
	EventBus.game_won.connect(func(st): _events.append(['game_won', st]))
	EventBus.game_lost.connect(func(st): _events.append(['game_lost', st]))
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
