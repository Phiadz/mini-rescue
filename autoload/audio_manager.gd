extends Node
## Audio-only autoload. No game rules or UI layout belong here.

const SFX_FOLDER := "res://assets/sfx/"
const BGM_FOLDER := "res://assets/sfx/"

# Thang âm ngũ cung thư giãn phong cách Mini Motorways (C Pentatonic: C4, D4, E4, G4, A4, C5, D5, E5)
const PENTATONIC_SCALE: Array[float] = [
	1.0,        # Do (C4)
	1.12246,    # Re (D4)
	1.25992,    # Mi (E4)
	1.49831,    # Sol (G4)
	1.68179,    # La (A4)
	2.0,        # Do cao (C5)
	2.24492,    # Re cao (D5)
	2.51984     # Mi cao (E5)
]

var _road_step: int = 0
var _last_road_draw_ms: int = -100000
var _players: Dictionary = {}
# Tiếng đã nạp (tên -> AudioStream). Nạp sẵn mọi SFX lúc khởi động: nạp lúc phát lần đầu làm bản web khựng ở tiếng đầu tiên.
var _streams: Dictionary = {}
const SFX_NAMES: Array[StringName] = [&"edge_place", &"edge_remove", &"flood_warning", &"hitHurt", &"lose", &"reward",
		&"sos_failed", &"sos_new", &"sos_rescued", &"ui_click", &"ui_hover", &"water_rise", &"wave_start", &"win"]
var _bgm_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in SFX_NAMES:
		_sfx_stream(n)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = &"BGM" if AudioServer.get_bus_index(&"BGM") >= 0 else &"Master"
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)
	# Phat lai khi ket thuc, phong truong hop WAV khong loop do import cu.
	_bgm_player.finished.connect(_on_bgm_finished)

	# Autoload: connects sound cues without changing the game modules.
	EventBus.edge_added.connect(func(_edge_id: int) -> void: _on_edge_placed())
	EventBus.edge_removed.connect(func(_edge_id: int) -> void: _on_edge_removed())
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

# Kéo chuột vẽ đường rải nốt ngũ cung (Mini Motorways Arpeggio)
func _on_edge_placed() -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_road_draw_ms > 700:
		_road_step = 0
	else:
		_road_step = (_road_step + 1) % PENTATONIC_SCALE.size()
	_last_road_draw_ms = now_ms
	var pitch: float = PENTATONIC_SCALE[_road_step]
	# Bù trừ âm lượng: càng lên nốt cao càng hạ dB để tai người nghe êm dịu tuyệt đối
	var high_note_cut: float = (pitch - 1.0) * 3.5
	play_sfx_with_pitch(&"edge_place", pitch, -7.0 - high_note_cut)

# Xóa đường: nốt trượt trầm nhẹ nhàng
func _on_edge_removed() -> void:
	play_sfx_with_pitch(&"edge_remove", randf_range(0.85, 0.95), -9.0)

func play_sfx(name: StringName, pitch_variance: float = 0.0) -> void:
	play_sfx_with_pitch(name, 1.0, 0.0, pitch_variance)

# Tiếng SFX theo tên (nạp một lần rồi giữ). Ưu tiên .mp3 nếu có (cho phép thay SFX bằng MP3 mà không cần chuyển đổi).
func _sfx_stream(name: StringName) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path_mp3 := SFX_FOLDER + String(name) + ".mp3"
	var path_wav := SFX_FOLDER + String(name) + ".wav"
	var path := path_mp3 if ResourceLoader.exists(path_mp3) else path_wav
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_streams[name] = stream
	return stream

func play_sfx_with_pitch(name: StringName, base_pitch: float = 1.0, volume_offset_db: float = 0.0, pitch_variance: float = 0.0) -> void:
	var stream := _sfx_stream(name)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.volume_db = volume_offset_db

	var final_pitch := base_pitch
	if pitch_variance > 0.0:
		final_pitch *= randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	elif name == &"ui_hover":
		final_pitch *= randf_range(0.98, 1.05)
		player.volume_db -= 8.0  # Giảm âm lượng hover để chỉ thoang thoảng êm dịu, không chói
	elif name == &"ui_click":
		final_pitch *= randf_range(0.98, 1.02)
	elif name == &"sos_new":
		# File MP3 mới (chuông ấm): giảm -7 dB, nhẹ biến thiên pitch để không đơn điệu
		player.volume_db -= 7.0
		final_pitch *= randf_range(0.97, 1.03)

	player.pitch_scale = clampf(final_pitch, 0.5, 3.0)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func play_bgm(name: StringName) -> void:
	if _bgm_player == null:
		return
	if name == &"":
		_bgm_player.stop()
		return
	var path_mp3 := BGM_FOLDER + String(name) + ".mp3"
	var path_wav := BGM_FOLDER + String(name) + ".wav"
	var path := path_mp3 if ResourceLoader.exists(path_mp3) else path_wav
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
		var wav := stream.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
		wav.resource_name = String(name)
		stream = wav
	elif stream is AudioStreamMP3:
		var mp3 := stream.duplicate() as AudioStreamMP3
		mp3.loop = true
		mp3.resource_name = String(name)
		stream = mp3
	_bgm_player.stream = stream
	_bgm_player.play()
