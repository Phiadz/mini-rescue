extends Node
# Autoload: GameManager. Chủ sở hữu: E. Không đặt class_name (script autoload).
# Vòng đời ván: MENU -> PLAYING -> WAVE_BREAK -> PLAYING ... -> WON / LOST; PAUSED chen vào giữa ván.
# Chỉ số đợt (wave index) tính từ 0.

const MAIN_SCENE := 'res://game/main.tscn'
const SPEEDS: Array[int] = [1, 2, 3]  # tua nhanh: phím F hoặc nút trên HUD
const ScoreSystemScript := preload('res://game/score_system.gd')

var state: int = Types.GameState.MENU
# Số giây nghỉ còn lại (chỉ đọc), 0 khi không ở lượt nghỉ. Bảng chọn thưởng của D đọc để đếm ngược;
# đứng yên khi tạm dừng giữa lượt nghỉ.
var break_left: float:
	get:
		var in_break := state == Types.GameState.WAVE_BREAK \
				or (state == Types.GameState.PAUSED and _prev_state == Types.GameState.WAVE_BREAK)
		return maxf(_phase_left, 0.0) if in_break else 0.0

var _prev_state: int = Types.GameState.MENU
var _wave := 0
var _phase_left := 0.0
var _time_survived := 0.0
var _reward_chosen := false
var _starting := false
var _score_system := ScoreSystemScript.new()
# Tốc độ người chơi chọn (1, 2, 3). Chỉ đặt lại Engine.time_scale khi người chơi đã từng tua,
# để các test tự đặt time_scale không bị ghi đè.
var game_speed := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # để còn nhận phím khi đang tạm dừng
	_score_system.name = 'ScoreSystem'
	add_child(_score_system)
	_score_system.max_failed_reached.connect(_finish.bind(false))


func _process(delta: float) -> void:
	# GameManager chạy cả khi tạm dừng, nên phải tự dừng đồng hồ ngoài PLAYING / WAVE_BREAK.
	if not _in_round():
		return
	_time_survived += delta
	_phase_left -= delta
	if _phase_left <= 0.0:
		if state == Types.GameState.PLAYING:
			_end_wave()
		else:
			_end_break()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		if _in_round():
			cycle_speed()
			get_viewport().set_input_as_handled()
		return
	if key.keycode != KEY_SPACE and key.keycode != KEY_ESCAPE:
		return
	if state == Types.GameState.PAUSED:
		resume_game()
	elif _in_round():
		pause_game()
	else:
		return  # MENU / WON / LOST: để phím lại cho giao diện của D
	get_viewport().set_input_as_handled()


func start_game() -> void:
	if _starting:
		return  # bấm Chơi hai lần liên tiếp
	_starting = true
	_reset_speed()
	_reset_counters()
	get_tree().paused = true  # xe ván cũ bị giải phóng cùng scene, C không được chạy tới khi reset xong
	get_tree().change_scene_to_file(MAIN_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame  # chờ scene sẵn sàng
	GraphManager.load_map(Config.MAP_PATH)  # 1. nạp bản đồ
	EventBus.game_started.emit()  # 2. các module tự reset, NodeLayer vẽ node
	get_tree().paused = false
	_score_system.enabled = true
	_set_state(Types.GameState.PLAYING)
	_begin_wave(0)  # 3. B và C bắt đầu khi nghe wave_started(0)
	_starting = false


func pause_game() -> void:
	if _in_round():
		_prev_state = state
		_set_state(Types.GameState.PAUSED)
		get_tree().paused = true


func resume_game() -> void:
	if state == Types.GameState.PAUSED:
		get_tree().paused = false
		_set_state(_prev_state)


func restart() -> void:
	start_game()  # start_game tự đặt lại mọi bộ đếm


# Bỏ ván đang dở để về menu chính. Cây scene bị dừng để lũ, SOS, xe của ván dở đứng yên
# phía sau menu; start_game() sẽ bỏ dừng và đặt lại mọi module.
func exit_to_menu() -> void:
	if state == Types.GameState.MENU:
		return
	_score_system.enabled = false
	_reset_speed()
	get_tree().paused = true
	_set_state(Types.GameState.MENU)


func choose_reward(reward: int) -> void:
	if state != Types.GameState.WAVE_BREAK or _reward_chosen:
		return
	match reward:
		Types.Reward.MORE_EDGES:
			GraphManager.add_edge_limit(Config.REWARD_EDGE_BONUS)
		Types.Reward.EXTRA_TRUCK:
			RescueManager.add_vehicle(Types.VehicleType.TRUCK)
		Types.Reward.EXTRA_BOAT:
			RescueManager.add_vehicle(Types.VehicleType.BOAT)
		_:
			return
	_reward_chosen = true
	EventBus.reward_chosen.emit(reward)


func get_score() -> int:
	return _score_system.score


func get_failed_count() -> int:
	return _score_system.failed


func get_current_wave() -> int:
	return _wave


func get_time_survived() -> float:
	return _time_survived


func _begin_wave(i: int) -> void:
	_wave = i
	_phase_left = Config.WAVE_DURATION
	EventBus.wave_started.emit(i)


func _end_wave() -> void:
	EventBus.wave_ended.emit(_wave)
	if _wave == Config.WAVE_COUNT - 1:
		_finish(true)
		return
	_set_state(Types.GameState.WAVE_BREAK)
	_phase_left = Config.BREAK_DURATION
	_reward_chosen = false
	EventBus.break_started.emit(Config.BREAK_DURATION)
	EventBus.reward_offered.emit(Types.Reward.values())


func _end_break() -> void:
	if not _reward_chosen:
		choose_reward(Types.Reward.MORE_EDGES)  # hết giờ nghỉ mà chưa chọn
	_set_state(Types.GameState.PLAYING)
	_begin_wave(_wave + 1)


func _finish(won: bool) -> void:
	_score_system.enabled = false  # thắng/thua chỉ phát một lần, SOS sau đó bị bỏ qua
	get_tree().paused = true  # lũ, SOS, xe dừng hẳn phía sau màn kết thúc
	_reset_speed()
	_set_state(Types.GameState.WON if won else Types.GameState.LOST)
	var stats := {
		'score': _score_system.score,
		'saved': _score_system.saved,
		'failed': _score_system.failed,
		'time_survived': _time_survived,
		'wave_reached': _wave,  # chỉ số từ 0, D hiển thị +1
		'stars': _score_system.get_stars() if won else 0,
	}
	if won:
		EventBus.game_won.emit(stats)
	else:
		EventBus.game_lost.emit(stats)


# Đổi vòng tốc độ 1 -> 2 -> 3 -> 1, chỉ trong ván (PLAYING hoặc WAVE_BREAK). Trả về tốc độ mới.
func cycle_speed() -> int:
	if not _in_round():
		return game_speed
	game_speed = SPEEDS[(SPEEDS.find(game_speed) + 1) % SPEEDS.size()]
	Engine.time_scale = float(game_speed)
	return game_speed


func _reset_speed() -> void:
	if game_speed != 1:
		game_speed = 1
		Engine.time_scale = 1.0


func _set_state(s: int) -> void:
	state = s
	EventBus.game_state_changed.emit(s)


func _in_round() -> bool:
	return state == Types.GameState.PLAYING or state == Types.GameState.WAVE_BREAK


func _reset_counters() -> void:
	# Tạm về MENU (không phát tín hiệu) để đồng hồ và phím tạm dừng đứng yên trong lúc đổi scene.
	state = Types.GameState.MENU
	_wave = 0
	_phase_left = 0.0
	_time_survived = 0.0
	_reward_chosen = false
	_score_system.enabled = false
	_score_system.reset()
