extends Node
# Scene thử bằng tay cho GameManager và ScoreSystem. Chủ sở hữu: E.
# Mở tests/test_game.tscn rồi bấm F6. Tín hiệu của C được giả lập bằng phím (chỉ làm trong tests/).

const HELP := 'Enter: bắt đầu / chơi lại    Space, Esc: tạm dừng / tiếp tục    S: đổi tốc độ\n' \
		+ 'R: cứu SOS lương thực    T: cứu SOS y tế    F: SOS thất bại\n' \
		+ '1 / 2 / 3: chọn thưởng (thêm tuyến / xe tải / ca-nô)'
const SPEEDS := [1.0, 5.0, 20.0]
const LOG_LINES := 14

var _label := Label.new()
var _log: Array[String] = []
var _speed_index := 0
var _next_req := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # vẫn cập nhật chữ khi tạm dừng
	var layer := CanvasLayer.new()
	_label.position = Vector2(16, 16)
	layer.add_child(_label)
	add_child(layer)
	_listen()
	_keep_alive.call_deferred()


# start_game() đổi sang main.tscn và xóa scene thử; chuyển node này lên gốc để không bị xóa theo.
func _keep_alive() -> void:
	reparent(get_tree().root)


func _process(_delta: float) -> void:
	var lines := PackedStringArray([
		HELP,
		'',
		'Trạng thái: %s    Đợt: %d/%d    Còn lại: %.1f giây    Sống sót: %.1f giây    Tốc độ: x%d' % [
			Types.GameState.keys()[GameManager.state], GameManager.get_current_wave() + 1,
			Config.WAVE_COUNT, GameManager._phase_left, GameManager.get_time_survived(),
			SPEEDS[_speed_index]],
		'Điểm: %d    Thất bại: %d/%d' % [
			GameManager.get_score(), GameManager.get_failed_count(), Config.MAX_FAILED],
		'',
	])
	lines.append_array(_log)
	_label.text = '\n'.join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			GameManager.restart()
		KEY_R:
			_fake_rescue(Types.SupplyType.FOOD)
		KEY_T:
			_fake_rescue(Types.SupplyType.MEDICAL)
		KEY_F:
			_fake_fail()
		KEY_1:
			GameManager.choose_reward(Types.Reward.MORE_EDGES)
		KEY_2:
			GameManager.choose_reward(Types.Reward.EXTRA_TRUCK)
		KEY_3:
			GameManager.choose_reward(Types.Reward.EXTRA_BOAT)
		KEY_S:
			_speed_index = (_speed_index + 1) % SPEEDS.size()
			Engine.time_scale = SPEEDS[_speed_index]
		_:
			return  # Space / Esc để GameManager xử lý
	get_viewport().set_input_as_handled()


# Khi tạm dừng, C cũng dừng nên không có SOS nào được cứu hay thất bại.
func _fake_rescue(supply: int) -> void:
	if get_tree().paused:
		return
	_next_req += 1
	EventBus.sos_rescued.emit(_next_req, Config.POINTS[supply])


func _fake_fail() -> void:
	if get_tree().paused:
		return
	_next_req += 1
	EventBus.sos_failed.emit(_next_req)


func _listen() -> void:
	EventBus.game_started.connect(func(): _add_log('game_started'))
	EventBus.game_state_changed.connect(
			func(s): _add_log('game_state_changed(%s)' % Types.GameState.keys()[s]))
	EventBus.wave_started.connect(func(i): _add_log('wave_started(%d)' % i))
	EventBus.wave_ended.connect(func(i): _add_log('wave_ended(%d)' % i))
	EventBus.break_started.connect(func(t): _add_log('break_started(%.1f)' % t))
	EventBus.reward_offered.connect(func(o): _add_log('reward_offered(%s)' % str(o)))
	EventBus.reward_chosen.connect(func(r): _add_log('reward_chosen(%s)' % Types.Reward.keys()[r]))
	EventBus.score_changed.connect(func(s): _add_log('score_changed(%d)' % s))
	EventBus.failed_changed.connect(func(c, m): _add_log('failed_changed(%d, %d)' % [c, m]))
	EventBus.game_won.connect(func(st): _add_log('game_won(%s)' % str(st)))
	EventBus.game_lost.connect(func(st): _add_log('game_lost(%s)' % str(st)))


func _add_log(msg: String) -> void:
	var line := '[%6.1f] %s' % [GameManager.get_time_survived(), msg]
	print(line)
	_log.append(line)
	if _log.size() > LOG_LINES:
		_log.remove_at(0)
