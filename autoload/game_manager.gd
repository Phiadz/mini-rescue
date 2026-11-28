extends Node
# Autoload: GameManager. Chủ sở hữu: E/C (C sở hữu wave/card/inventory/run state). Không đặt class_name.
# Vòng đời ván: MENU -> CARD_DRAFT -> PLAYING -> CARD_DRAFT -> PLAYING ... -> WON / LOST; PAUSED chen vào PLAYING.
# Chỉ số đợt (wave index) tính từ 0.

const MAIN_SCENE := 'res://game/main.tscn'
const SPEEDS: Array[int] = [1, 2, 3]  # tua nhanh: phím F hoặc nút trên HUD
const ScoreSystemScript := preload('res://game/score_system.gd')
const StageViewScript := preload('res://game/stage_view.gd')
const FerryLayerScript := preload('res://graph/ferry_layer.gd')

const PLACEABLE_REWARDS: Array[int] = [
	Types.Reward.TRAFFIC_LIGHT,
	Types.Reward.ROUNDABOUT,
	Types.Reward.HIGHWAY,
	Types.Reward.FERRY,
]

var state: int = Types.GameState.MENU
# Deprecated shop shim until E replaces reward_popup.gd.
var break_left: float = 0.0

var _prev_state: int = Types.GameState.MENU
var _wave := 0
var _phase_left := 0.0
var _time_survived := 0.0
var _milestone_cleared := false
# Sức chứa của xe cứu hộ
var truck_capacity: int = 1
var boat_capacity: int = 1
var _inventory := {}  # Types.Reward (placeable) -> int available
var _card_offers: Array = []
var _awaiting_choice := false
var _pending_wave_index := 0
var _rng := RandomNumberGenerator.new()
var _has_custom_seed := false

var _starting := false
var _score_system := ScoreSystemScript.new()
# Tốc độ người chơi chọn (1, 2, 3). Chỉ đặt lại Engine.time_scale khi người chơi đã từng tua,
# để các test tự đặt time_scale không bị ghi đè.
var game_speed := 1
var _stage := 0                  # vùng chơi hiện tại (chỉ số trong GraphManager.get_stages())
var _play_rect := Rect2(Vector2.ZERO, Vector2(1280, 720))
var _stage_view: Node2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # để còn nhận phím khi đang tạm dừng
	_rng.randomize()
	_score_system.name = 'ScoreSystem'
	add_child(_score_system)
	_score_system.max_failed_reached.connect(_on_max_failed)


func _process(delta: float) -> void:
	# GameManager chạy cả khi tạm dừng, nên phải tự dừng đồng hồ ngoài PLAYING.
	if state != Types.GameState.PLAYING:
		return
	_time_survived += delta
	_phase_left -= delta
	if _phase_left <= 0.0:
		_end_wave()


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
		return  # MENU / CARD_DRAFT / WON / LOST: để phím lại cho giao diện
	get_viewport().set_input_as_handled()


# Scene game nạp sẵn ở màn khởi động (ui/boot.gd): bấm Chơi chỉ còn dựng scene, đỡ khựng trên bản web.
var _main_packed: PackedScene

func preload_main_scene() -> PackedScene:
	if _main_packed == null:
		_main_packed = load(MAIN_SCENE)
	return _main_packed


func set_card_seed(seed_value: int) -> void:
	_rng.seed = seed_value
	_has_custom_seed = true


func start_game() -> void:
	if _starting:
		return  # bấm Chơi hai lần liên tiếp
	_starting = true
	_reset_speed()
	_reset_counters()
	if not _has_custom_seed:
		_rng.randomize()
	get_tree().paused = true  # xe ván cũ bị giải phóng cùng scene, C không được chạy tới khi reset xong
	if _main_packed != null:
		get_tree().change_scene_to_packed(_main_packed)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame  # chờ scene sẵn sàng
	GraphManager.load_map(Config.MAP_PATH)  # 1. nạp bản đồ
	_mount_stage_view()
	_mount_ferry_layer()
	EventBus.game_started.emit()  # 2. các module tự reset, NodeLayer vẽ node
	_emit_all_inventory()
	_open_card_draft(0)  # 3. mở card draft đầu tiên trước wave 1, mô phỏng đóng băng
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
	_awaiting_choice = false
	_card_offers.clear()
	_reset_speed()
	get_tree().paused = true
	_set_state(Types.GameState.MENU)


# --- Card Draft & Inventory API ---
func get_card_offers() -> Array:
	return _card_offers.duplicate(true)


func choose_card(card_id: StringName) -> bool:
	if state != Types.GameState.CARD_DRAFT or not _awaiting_choice:
		return false
	var chosen: Dictionary = {}
	for offer in _card_offers:
		if offer.get('id', &'') == card_id:
			chosen = offer
			break
	if chosen.is_empty():
		push_warning('GameManager.choose_card: không tìm thấy card_id "%s"' % String(card_id))
		return false
	_awaiting_choice = false
	_card_offers.clear()
	for r in chosen.get('rewards', []):
		grant_reward(int(r.get('reward_id', -1)), int(r.get('amount', 0)))
	get_tree().paused = false
	_score_system.enabled = true
	_set_state(Types.GameState.PLAYING)
	_begin_wave(_pending_wave_index)
	return true


func get_inventory(reward_id: int) -> int:
	return int(_inventory.get(reward_id, 0))


func grant_reward(reward_id: int, amount: int) -> bool:
	if amount <= 0:
		push_warning('GameManager.grant_reward: amount không hợp lệ (%d)' % amount)
		return false
	match reward_id:
		Types.Reward.MORE_EDGES:
			GraphManager.add_edge_limit(amount)
			return true
		Types.Reward.EXTRA_TRUCK:
			for i in amount:
				RescueManager.add_vehicle(Types.VehicleType.TRUCK)
			return true
		Types.Reward.EXTRA_BOAT:
			for i in amount:
				RescueManager.add_vehicle(Types.VehicleType.BOAT)
			return true
		Types.Reward.UPGRADE_TRUCK_CAP:
			if truck_capacity >= Config.CAPACITY_UPGRADED:
				return false
			truck_capacity = Config.CAPACITY_UPGRADED
			EventBus.truck_capacity_upgraded.emit(truck_capacity)
			return true
		Types.Reward.UPGRADE_BOAT_CAP:
			if boat_capacity >= Config.CAPACITY_UPGRADED:
				return false
			boat_capacity = Config.CAPACITY_UPGRADED
			EventBus.boat_capacity_upgraded.emit(boat_capacity)
			return true
		Types.Reward.TRAFFIC_LIGHT, Types.Reward.ROUNDABOUT, Types.Reward.HIGHWAY, Types.Reward.FERRY:
			_inventory[reward_id] = get_inventory(reward_id) + amount
			_emit_inventory(reward_id)
			return true
	push_warning('GameManager.grant_reward: reward_id không hợp lệ (%d)' % reward_id)
	return false


func try_consume_item(reward_id: int, amount: int = 1) -> bool:
	if amount <= 0 or not reward_id in PLACEABLE_REWARDS:
		push_warning('GameManager.try_consume_item: tham số không hợp lệ (%d, %d)' % [reward_id, amount])
		return false
	var cur := get_inventory(reward_id)
	if cur < amount:
		return false
	_inventory[reward_id] = cur - amount
	_emit_inventory(reward_id)
	return true


func refund_item(reward_id: int, amount: int = 1) -> void:
	if amount <= 0 or not reward_id in PLACEABLE_REWARDS:
		push_warning('GameManager.refund_item: tham số không hợp lệ (%d, %d)' % [reward_id, amount])
		return
	_inventory[reward_id] = get_inventory(reward_id) + amount
	_emit_inventory(reward_id)


func _emit_inventory(reward_id: int) -> void:
	var avail := get_inventory(reward_id)
	EventBus.inventory_changed.emit(reward_id, avail)
	if reward_id == Types.Reward.FERRY:
		EventBus.ferry_inventory_changed.emit(avail, avail)


func _emit_all_inventory() -> void:
	for rid in PLACEABLE_REWARDS:
		_emit_inventory(rid)


func _open_card_draft(next_wave_index: int) -> void:
	_pending_wave_index = next_wave_index
	_awaiting_choice = true
	_score_system.enabled = false
	get_tree().paused = true
	_card_offers = _generate_card_offers(next_wave_index + 1)
	_set_state(Types.GameState.CARD_DRAFT)
	EventBus.card_offers_ready.emit(_card_offers.duplicate(true))


func _generate_card_offers(wave_number: int) -> Array:
	var t := Config.get_pressure_tier(wave_number)
	var amount_scale := mini(Config.CARD_AMOUNT_SCALE_MAX, 1 + floori(float(t - 1) / 2.0))
	var infra_mult := minf(Config.CARD_INFRA_WEIGHT_MAX_MULT, 1.0 + Config.CARD_INFRA_WEIGHT_STEP * float(t - 1))

	var pool: Array = []
	var weights: Array[float] = []
	for tpl in Config.CARD_CATALOG:
		if _is_template_maxed(tpl):
			continue
		var w: float = float(tpl.base_weight)
		if _template_has_infra(tpl):
			w *= infra_mult
		pool.append(tpl)
		weights.append(w)

	var offers: Array = []
	var pick_count := mini(Config.CARD_CHOICES_COUNT, pool.size())
	for _i in pick_count:
		var idx := _pick_weighted_index(weights)
		var tpl: Dictionary = pool[idx]
		pool.remove_at(idx)
		weights.remove_at(idx)
		var scaled_rewards: Array[Dictionary] = []
		for r in tpl.rewards:
			var rid: int = int(r.reward_id)
			var amt: int = int(r.amount)
			if rid != Types.Reward.UPGRADE_TRUCK_CAP and rid != Types.Reward.UPGRADE_BOAT_CAP:
				amt *= amount_scale
			scaled_rewards.append({'reward_id': rid, 'amount': amt})
		offers.append({
			'id': tpl.id,
			'title': tpl.title,
			'icon_key': tpl.icon_key,
			'rewards': scaled_rewards,
		})
	return offers


func _is_template_maxed(tpl: Dictionary) -> bool:
	for r in tpl.rewards:
		var rid: int = int(r.reward_id)
		if rid == Types.Reward.UPGRADE_TRUCK_CAP and truck_capacity >= Config.CAPACITY_UPGRADED:
			return true
		if rid == Types.Reward.UPGRADE_BOAT_CAP and boat_capacity >= Config.CAPACITY_UPGRADED:
			return true
	return false


func _template_has_infra(tpl: Dictionary) -> bool:
	for r in tpl.rewards:
		if int(r.reward_id) in PLACEABLE_REWARDS:
			return true
	return false


func _pick_weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return _rng.randi() % weights.size()
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(weights[i], 0.0)
		if roll <= acc:
			return i
	return weights.size() - 1


# Deprecated shop shims until E replaces reward_popup.gd.
func choose_reward(_reward: int) -> bool:
	return false

func get_price(_reward: int) -> int:
	return 0

func get_funds() -> int:
	return 0

func get_bought_count(_reward: int) -> int:
	return 0


func get_score() -> int:
	return _score_system.score


func get_failed_count() -> int:
	return _score_system.failed


func get_current_wave() -> int:
	return _wave


func get_time_survived() -> float:
	return _time_survived


func is_milestone_cleared() -> bool:
	return _milestone_cleared


func _begin_wave(i: int) -> void:
	_wave = i
	_phase_left = Config.WAVE_DURATION
	EventBus.wave_started.emit(i)


func _end_wave() -> void:
	EventBus.wave_ended.emit(_wave)
	if _wave >= Config.WAVE_COUNT - 1:
		_milestone_cleared = true
	var next_wave := _wave + 1
	_enter_stage(next_wave, true)
	_open_card_draft(next_wave)


func _on_max_failed() -> void:
	_finish(_milestone_cleared)


func _finish(won: bool) -> void:
	_score_system.enabled = false  # thắng/thua chỉ phát một lần, SOS sau đó bị bỏ qua
	_awaiting_choice = false
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


# Đổi vòng tốc độ 1 -> 2 -> 3 -> 1, chỉ trong ván (PLAYING). Trả về tốc độ mới.
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


# --- Vùng chơi theo đợt ---
# Vùng đang chơi (đơn vị bản đồ). Ngoài vùng không tô đường, không sinh SOS.
func get_play_rect() -> Rect2:
	return _play_rect


func is_in_play(p: Vector2) -> bool:
	return _play_rect.has_point(p)


func get_stage() -> int:
	return _stage


func _stage_data(i: int) -> Dictionary:
	var stages: Array = GraphManager.get_stages()
	if stages.is_empty():
		return {center = [640, 360], zoom = 1.0}
	return stages[clampi(i, 0, stages.size() - 1)]


func _enter_stage(i: int, animate: bool) -> void:
	_stage = i
	var data := _stage_data(i)
	_play_rect = StageViewScript.play_rect(data)
	if _stage_view != null and is_instance_valid(_stage_view):
		_stage_view.apply(data, animate)


# Camera và lớp mép vùng nằm trong World (vẽ trên đường và điểm, dưới giao diện).
func _mount_stage_view() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_stage_view = StageViewScript.new()
	_stage_view.name = 'StageView'
	var world := scene.get_node_or_null('World')
	(world if world != null else scene).add_child(_stage_view)
	_enter_stage(0, false)


func _mount_ferry_layer() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var world := scene.get_node_or_null('World')
	var target = world if world != null else scene
	if target.get_node_or_null('FerryLayer') == null:
		var fl := FerryLayerScript.new()
		fl.name = 'FerryLayer'
		target.add_child(fl)


func _set_state(s: int) -> void:
	state = s
	EventBus.game_state_changed.emit(s)


func _in_round() -> bool:
	return state == Types.GameState.PLAYING


func _reset_counters() -> void:
	# Tạm về MENU (không phát tín hiệu) để đồng hồ và phím tạm dừng đứng yên trong lúc đổi scene.
	state = Types.GameState.MENU
	_prev_state = Types.GameState.MENU
	_wave = 0
	_phase_left = 0.0
	_time_survived = 0.0
	_milestone_cleared = false
	_awaiting_choice = false
	_pending_wave_index = 0
	_card_offers.clear()
	_inventory.clear()
	_inventory[Types.Reward.FERRY] = Config.START_FERRIES
	_stage = 0
	_play_rect = Rect2(Vector2.ZERO, Vector2(1280, 720))
	_score_system.enabled = false
	_score_system.reset()
	truck_capacity = 1
	boat_capacity = 1
