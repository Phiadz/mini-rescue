extends Node
## Audio-only autoload. No game rules or UI layout belong here.

const SFX_FOLDER := "res://assets/sfx/"
const BGM_FOLDER := "res://assets/sfx/"

var _players: Dictionary = {}
var _bgm_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = &"BGM" if AudioServer.get_bus_index(&"BGM") >= 0 else &"Master"
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)
	# Phat lai khi ket thuc, phong truong hop WAV khong loop do import cu.
	_bgm_player.finished.connect(_on_bgm_finished)

	# Autoload: connects sound cues without changing the game modules.
	EventBus.edge_added.connect(func(_edge_id: int) -> void: play_sfx(&"edge_place"))
	EventBus.edge_removed.connect(func(_edge_id: int) -> void: play_sfx(&"edge_remove"))
	EventBus.flood_warning.connect(_on_flood_warning)
	EventBus.sos_spawned.connect(func(_request_id: int, _node_id: int, _supply: int, _duration: float) -> void: play_sfx(&"sos_new"))
	EventBus.sos_rescued.connect(func(_request_id: int, _points: int) -> void: play_sfx(&"sos_rescued"))
	EventBus.sos_failed.connect(func(_request_id: int) -> void: play_sfx(&"sos_failed"))
	EventBus.wave_started.connect(func(_index: int) -> void: play_sfx(&"wave_start"))
	EventBus.reward_offered.connect(func(_options: Array) -> void: play_sfx(&"reward"))
	EventBus.game_won.connect(func(_stats: Dictionary) -> void: play_sfx(&"win"))
	EventBus.game_lost.connect(func(_stats: Dictionary) -> void: play_sfx(&"lose"))
	call_deferred("play_bgm", &"game_bgm")

func _on_bgm_finished() -> void:
	if _bgm_player != null and _bgm_player.stream != null:
		_bgm_player.play()

var _last_flood_warning_ms: int = -100000
func _on_flood_warning(_edge_id: int, _seconds_left: float) -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_flood_warning_ms >= 3500:
		_last_flood_warning_ms = now_ms
		play_sfx(&"flood_warning")

func set_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("Audio bus not found: " + String(bus_name))
		return
	var level := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, level <= 0.0001)
	if level > 0.0001:
		AudioServer.set_bus_volume_db(idx, linear_to_db(level))

func play_sfx(name: StringName) -> void:
	var path := SFX_FOLDER + String(name) + ".wav"
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func play_bgm(name: StringName) -> void:
	if _bgm_player == null:
		return
	if name == &"":
		_bgm_player.stop()
		return
	var path := BGM_FOLDER + String(name) + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Missing BGM: " + path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Invalid BGM: " + path)
		return
	if _bgm_player.playing and _bgm_player.stream != null and _bgm_player.stream.resource_name == String(name):
		return
	if stream is AudioStreamWAV:
		# loop_end mac dinh = 0 nen phai set ro; get_length() vi file import dang nen QOA
		var wav := stream.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
		wav.resource_name = String(name)
		stream = wav
	_bgm_player.stream = stream
	_bgm_player.play()
